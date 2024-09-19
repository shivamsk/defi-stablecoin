// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedMintDsc} from "../mocks/MockFailedMintDsc.sol";
import {MockFailedMintDsc} from "../mocks/MockFailedMintDsc.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import "forge-std/console.sol";

contract DSCEngineTest is Test {
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    uint256 public amountToMint = 100 ether;
    address public user = makeAddr("user");

    uint256 public amountCollateral = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    // liquidator
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 1 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
    }

    //////////////////////////
    //// Constructor Tests ///
    //////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////
    //// Price Tests ///
    ////////////////////

    function testGetUsdValue() public {
        uint256 amount = 15e18; //15 eth
            // 15e18 * $2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, amount);
        assertEq(expectedUsd, actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2000/ETH , $100 USD
        // 100/2000 = 0.05 ether
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////////////
    //// Deposit Collateral Tests ///
    /////////////////////////////////

    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(user, amountCollateral);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine));

        // Arrange - user
        vm.startPrank(user);
        // Get the approval from user to transfer mockDsc Amount to transfer to mockDscEngine
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), amountCollateral);

        // Act // Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.depositCollateral(address(mockDsc), amountCollateral);

        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedTokenCollateralAddress() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", user, amountCollateral);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(randomToken), amountCollateral);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);

        // Get the approval from user to transfer amountCollateral to dscEngine
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(expectedDepositAmount, amountCollateral);
    }

    //////////////////////////////////////////
    //// depositCollateralAndMintDsc Tests ///
    //////////////////////////////////////////

    function testRevertsIfMintDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (amountCollateral * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();

        vm.startPrank(user);
        // Get the approval from user to transfer amountCollateral to dscEngine
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);

        // expectedHealthFactor = 10000/20000 = 0.5 < 1
        // 0.5 * 1e18 = 5e17
        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(weth, amountCollateral));

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        // Get the approval from user to transfer amountCollateral to dscEngine
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 totalDscMinted = dsc.balanceOf(user);
        assertEq(amountToMint, totalDscMinted);
    }

    /////////////////////////////////
    //// Redeem Collateral Tests ///
    /////////////////////////////////

    function testRedeemRevertsWithCollateralAmountZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsWithUnapprovedTokenCollateralAddress() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", user, amountCollateral);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.redeemCollateral(address(randomToken), amountCollateral);
        vm.stopPrank();
    }

    function testRedeemCollateral_FailsIfNoCollateralDeposited() public {
        vm.startPrank(user);
        // Expect the arithmetic underflow error (Panic(0x11))
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        dscEngine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];

        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(user, amountCollateral);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine));

        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), amountCollateral);

        mockDscEngine.depositCollateral(address(mockDsc), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.redeemCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.redeemCollateral(weth, amountCollateral);
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userBalance, amountCollateral);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedEvent() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(user, user, weth, amountCollateral);
        vm.startPrank(user);
        dscEngine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    ////////////////////////
    //// Mint DSC Tests ///
    ///////////////////////

    function testMintDsc_FailsWithAmountZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public {
        // Arrange - Setup

        MockFailedMintDsc mockDsc = new MockFailedMintDsc();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.transferOwnership(address(mockDscEngine));

        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDscEngine), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDscEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testMintDscAndGetAccountInformation() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.mintDsc(4 ether);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(user);
        assertEq(4 ether, totalDscMinted);
    }

    function testMintDsc_FailsIfHealthFactorIsBroken() public depositedCollateral {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (amountCollateral * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();

        vm.startPrank(user);
        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(weth, amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    ////////////////////////
    //// Burn DSC Tests ///
    ///////////////////////

    function testBurnDsc_FailsWithAmountZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnDsc_Success() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.mintDsc(4 ether);
        ERC20Mock(address(dsc)).approve(address(dscEngine), 3 ether);
        dscEngine.burnDsc(3 ether);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(user);
        assertEq(1 ether, totalDscMinted);
    }

    // function testBurnDsc_RevertsWithTransferFailed() public depositedCollateral {
    //     vm.startPrank(user);
    //     dscEngine.mintDsc(4 ether);
    //     // No user Approval to transfer
    //     // ERC20Mock(address(dsc)).approve(address(dscEngine), 3 ether);
    //     vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    //     dscEngine.burnDsc(3 ether);
    //     vm.stopPrank();
    // }

    ////////////////////////
    //// Health Factor Tests ///
    ///////////////////////

    function testHealthFactor() public depositedCollateralAndMintedDsc {
        // amountCollateralInUsd = 2000 * 10 = 20000
        // amountCollateralThreshold = 20000 / 2 = 10000
        // mintedDsc = 100
        // healthFactor = 10000/100 =100
        uint256 healthFactor = dscEngine.getHealthFactor(user);
        assertEq(100 ether, healthFactor);
    }

    function testHealthFactorBelowOne() public depositedCollateralAndMintedDsc {
        // Update ethUsdPriceFeed in mock from 2000 to 10
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(10e8);

        // depositedCollateral = 10 * 10 = 100
        // amountMinted = 100
        // healthFactor = 1000/2 = 50 / 100 = 0.5

        assertEq(dscEngine.getHealthFactor(user), 0.5 ether);
    }

    ////////////////////////
    //// Liquidate Tests ///
    ///////////////////////

    function testLiquidate_FailsWithAmountZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.liquidate(weth, user, 0);
        vm.stopPrank();
    }

    function testMustImproveHealthFactorOnLiquidation() public {
        ERC20Mock(weth).mint(user, 30 ether);
        ERC20Mock(weth).mint(liquidator, 30 ether);

        amountCollateral = 30 ether;
        amountToMint = 100 ether;
        vm.startPrank(user);
        // Get the approval from user to transfer amountCollateral to dscEngine
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        uint256 liquidatorAmountToMint = 100 ether;

        // Arange - Liquidator
        vm.startPrank(liquidator);
        // liquidator is approving to transfer weth of amount amountCollateral to the contract address mockDscEngine
        ERC20Mock(weth).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(weth, amountCollateral, liquidatorAmountToMint);

        // uint256 debtToCover = 10 ether;
        // // liquidator is approving to transfer mockDsc of amount debtToCover to the contract address mockDscEngine
        // mockDsc.approve(address(mockDscEngine), debtToCover);

        // Act
        int256 ethUsdUpdatedPrice = 5e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Assert
        // vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);

        uint256 debtToCover = 100 ether;
        dsc.approve(address(dscEngine), debtToCover);
        dscEngine.liquidate(weth, user, debtToCover);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(liquidator);
        assertEq(260 ether, collateralValueInUsd);
        assertEq(0 ether, totalDscMinted);
        vm.stopPrank();
    }

    function testRevertsWithHealthFactorOk() public depositedCollateralAndMintedDsc {
        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, user, 20 ether);
        vm.stopPrank();
    }
}
