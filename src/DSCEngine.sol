// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// tokens maintain a 1 token == 1 dollar peg
// this stablecoin has the properties:
// - exogenous collerateral
// - dollar pegged
// - algorithmic
// - similar to dai if it has no governance, and was only backed by wETH and wBTC

// our dsc system should always be overcollaterised to ensure we have sufficient coverage for dsc mints

// this contract is the core of the DSC system. It handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing colleratal
// this contract is very loosely based on the MakerDao DSS (DAI) system

contract DSCEngine is ReentrancyGuard {
    // ERRORS
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();

    // STATE VARIABLES

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    // EVENTS
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    DecentralisedStableCoin private immutable i_dsc;

    // MODIFIERS
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
            _;
        }
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    // FUNCTIONS

    /*
    @params tokenAddress 0 maps to priceFeedAddresses
    @ params dscAddress is our stablecoin
    @params priceFeeds are denominated in USD. e.g. ETH -> USD, BTC -> USD
     */

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    // EXTERNAL FUNCTIONS

    // deposit collateral and mint stablecoin
    function depositCollateralAndMintDsc() external {}

    /*
    @param tokenCollateralAddress: the address of the token to deposit as collateral
    @param amountCollateral: the amount of collateral to deposit
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // IERC20 is simply an interface for ERC20, meaning it uses its functionality without actually modifying an existing ERC20
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // redeem collateral by providing collateral
    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    // if people are nervous they have too much stablecoin and not enough collateral, and they want a quick way to have more collateral than dsc, they can quickly burn
    function burnDsc() external {}

    // if value of collateral drops too much, we need to liquidate to ensure backing of our stablecoin
    function liquidate() external {}

    // if you are under a threshold of, say, 150%, someone can pay back your minted dsc and can have your collateral for a discount.
    // e.g.
    // $100 ETH collateral reduces to $74
    // original mint of $50 dsc
    // becomes undercollateralised and users can liquidate others with undercollateralised positions
    // (ill pay back the $50 dsc, now user has zero debt, and liqidator gets all collateral)
    // liquidator gets $74 dollars for $50 dsc. incentivses people to always have health collateralisation
    function healthFactor() external view {}
}
