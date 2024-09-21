// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import "forge-std/console.sol";

/**
 * @title DSCEngine
 * @author Siva Krishna Merugu
 * The system is designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg
 * This stablecoin has the properties:
 * - Exogenous collateral
 * - Dollar pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral  <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as
 * Depositing and Withdrawing Collateral.
 *
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 *
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////////
    // Errors
    ////////////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ////////////////////
    // Type
    ////////////////////
    using OracleLib for AggregatorV3Interface;

    ////////////////////
    // State Variables
    ////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus

    // Token to PriceFeed mapping
    //https://data.chain.link/feeds
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    // Amount of DSC minted by User
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////
    // Events
    ////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    ////////////////////
    // Modifiers
    ////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////////
    // Functions
    ////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        // USD PriceFeeds
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        // Ex: ETH/USD, BTC/USD ,MKR/USD etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////
    // External Functions
    ////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the collateral to deposit
     * @param amountDscToMint The amount of Decentralized Stable Coin to mint
     * @notice This function will deposit the collateral and mint the DSC in one t ransaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI ( Checks, Effects and Interactions)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // Effects
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // Updated state . Emit event
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // Interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token to redeem from collateral
     * @param amountCollateral The amount of the collateral to redeem
     * @param amountDscToBurn The amount of Decentralized Stable Coin to burn
     * This function burns DSC and redeems the underlying collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health factor
    }

    // In order to redeem collateral:
    // 1. Health factor must be > 1 after collateral pulled
    // CEI : Checks, Effects and Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Threshold - 150%
    // $100 ETH Collateral -> $74
    // $50 DSC
    // UNDERCOLLATERALIZED !!!

    // I'll pay back the $50 DSC -> Get all your collateral
    // $74 ETH
    // -$50 DSC
    // +$24

    // 1. Check if collateral value > DSC amount
    /**
     * @notice Follows CEI
     * @param amountDscToMint The amount of Decentralized  StableCoin to Mint
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;

        // If they minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    // No need to check for the breaking of healthFactor as the burning can only improve the HealthFactor
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);

        // This may never happen. Can remove it later if needed
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // If we do start nearing undercollateralization, we need someone to liquidate positions

    // Initialy, $100 ETH backing $50 DSC
    // Now, $20 ETH backing $50 DSC <- DSC isn't worth $1 anymore ,need to liquidate.

    // If $75 ETH backing $50 DSC,
    // Liquidator takes $75 backing and burns off the $50 DSC

    // If someone is almost undercollateralized, we will pay you to liquidate them.

    /**
     *
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their healthFactor should be below MIN_HEALTH_FACTOR. The user to be liquidated
     * @param debtToCover The amount of DSC you want to burn to improve User's heath factor
     * @notice You can partially liquidate a User.
     * @notice You will get a liquidation bonus for taking the Users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators
     * Ex : If the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follow CEI ( Checks, Effects and Interactions)
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);

        //No need to liquidate if the health factor is good
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // We want to burn their DSC debt and take their collateral
        // Bad User : $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC = How much in ETH?
        // 0.05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // Give them a 10% bonus
        // Need to give liquidator $110 WETH for $100 DSC

        // Not implementing this:
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury

        // 0.05 eth * 0.1 = 0.005
        // Getting 0.055 eth
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        // Revert if the health factor of the liquidator is broken
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////////
    // Private & Internal View & Pure Functions
    ///////////////////////////////////

    /**
     * @dev Low level internal function, do not call this unless the function calling this is checking for health factor breaking
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        // Transfer DSC tokens from User to this Contract and then Burn
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        // Solidity will check if the diff value goes to negative and thrown an error
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        // Calculate HealthFactor after redemption
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * Check health factor( Do they have enough collateral ? )
     * Revert if they don't
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated.
     * @param user Address of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC Minted
        // total Collateral Value
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDscMinted, collateralValueInUSD);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        // If the user deposited collateral but didn't mint any DSC, then the user's health factor should be max
        if (totalDscMinted == 0) return type(uint256).max;
        // $150 ETH  / 100 DSC
        // 150 * 50  = 7500 / 100 = 75/100 < 1

        // $1000 ETH / 100 DSC
        // 1000 * 50  = 50000 / 100 =  500/100 > 1

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    //////////////////////////////////////////
    // Public & External View & Pure Functions
    /////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // Price of ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH -> price in USD
        // ??    -> usdAmountInWei

        // ($10e18 * 1e18) / ($2000e8 * 1e10)
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            // console.log("Token: %s , amount : %d", token, amount);
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        // 1 ETH = $1000
        // https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1&search=ETH+%2F+USD
        // The returned value from priceFeed will be 1000* 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; //  (1000 * 1e8 * 1e10)/
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getLiquidationBonus() external view returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getCollateralTokenPriceFeed(address tokenCollateralAddress) external view returns (address) {
        return s_priceFeeds[tokenCollateralAddress];
    }
}
