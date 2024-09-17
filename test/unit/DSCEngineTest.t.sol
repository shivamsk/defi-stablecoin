// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import "forge-std/console.sol";

contract DSCEngineTest is Test {
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

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

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
        mockDsc.mint(user, AMOUNT_COLLATERAL);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscEngine));

        // Arrange - user
        vm.startPrank(user);
        // Get the approval from user to transfer mockDsc Amount to transfer to mockDscEngine
        ERC20Mock(address(mockDsc)).approve(address(mockDscEngine), AMOUNT_COLLATERAL);

        // Act // Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedTokenCollateralAddress() public {
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);

        // Get the approval from user to transfer AMOUNT_COLLATERAL to dscEngine
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL);
    }

    //////////////////////////////////////////
    //// depositCollateralAndMintDsc Tests ///
    //////////////////////////////////////////

    function testRevertsIfMintDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();

        vm.startPrank(user);
        // Get the approval from user to transfer AMOUNT_COLLATERAL to dscEngine
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        // expectedHealthFactor = 10000/20000 = 0.5 < 1
        // 0.5 * 1e18 = 5e17
        uint256 expectedHealthFactor =
            dscEngine.calculateHealthFactor(amountToMint, dscEngine.getUsdValue(weth, AMOUNT_COLLATERAL));

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    modifier depsoitedCollateralAndMintedDsc() {
        vm.startPrank(user);
        // Get the approval from user to transfer AMOUNT_COLLATERAL to dscEngine
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depsoitedCollateralAndMintedDsc {
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
        ERC20Mock randomToken = new ERC20Mock("RAN", "RAN", user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.redeemCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateral_FailsIfNoCollateralDeposited() public {
        vm.startPrank(user);
        // Expect the arithmetic underflow error (Panic(0x11))
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateral_FailsWithoutMintingDsc() public depositedCollateral {
        vm.startPrank(user);

        // This error comes when the DSC is not minted and so the totalDscMinted = 0 in healthFactor calculation
        // expected error: panic: division or modulo by zero (0x12
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x12));
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
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

    function testMintDscAndGetAccountInformation() public depositedCollateral {
        vm.startPrank(user);
        dscEngine.mintDsc(4 ether);
        vm.stopPrank();

        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(user);
        assertEq(4 ether, totalDscMinted);
    }

    // function testMintDsc_FailsIfHealthFactorIsBroken() public depositedCollateral {
    //     vm.startPrank(user);
    //     uint256 randomHealthFactor = 0.98
    //     vm.expectRevert(abi.encodeWithSignature("DSCEngine__BreaksHealthFactor(uint256)", invalidHealthFactor));

    //     dscEngine.mintDsc(10001 ether);
    //     vm.stopPrank();
    // }

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
    //// Liquidate Tests ///
    ///////////////////////

    function testLiquidate_FailsWithAmountZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.liquidate(weth, user, 0);
        vm.stopPrank();
    }

    function testLiquidate_Success() public {
        vm.startPrank(user);
    }
}
