// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    error DSCEngine_NeedsMoreThanZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_NotAllowedToken();
    error DSCEngine_TransferFailed();

    ////////////////////
    // State Variables
    ////////////////////

    // Token to PriceFeed mapping
    //https://data.chain.link/feeds
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////
    // Events
    ////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ////////////////////
    // Modifiers
    ////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine_NotAllowedToken();
        }
        _;
    }

    ////////////////////
    // Functions
    ////////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        // USD PriceFeeds
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        // Ex: ETH/USD, BTC/USD ,MKR/USD etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////
    // External Functions
    ////////////////////

    function depositCollateralAndMintDsc() external {}

    /**
     * @notice follows CEI ( Checks, Effects and Interactions)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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
            revert DSCEngine_TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    // Threshold - 150%
    // $100 ETH Collateral -> $74
    // $50 DSC
    // UNDERCOLLATERALIZED !!!

    // I'll pay back the $50 DSC -> Get all your collateral
    // $74 ETH
    // -$50 DSC
    // +$24

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
