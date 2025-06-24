// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    // STATE VARIABLES
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollaterised
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    // maps token to price feed (which is the chainlink address). This is set in the constructor.
    mapping(address token => address priceFeed) private s_priceFeeds;
    // maps the users to a token and how much token they have deposited for collateral.
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    // maps user to the amount they minted
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    // EVENTS
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    DecentralisedStableCoin private immutable i_dsc;

    // MODIFIERS
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    // checks if the token a user is passing is allowed in our contract
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
        // each token must be matched with a price feed address, otherwise there is a mismatch
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // set allowed tokens and their price feed addresses
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        // initialising stablecoin
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    // EXTERNAL FUNCTIONS

    // deposit collateral and mint stablecoin
    function depositCollateralAndMintDsc() external {}

    /*
    This function allows users to deposit collateral of a specific tokenAddress,
    checks if the token is allowed, and if so, transfers the tokens from their address to the contract.

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

    /*
     * 
     * @param amountDscToMint: the amount of DSC to mint. A user may have $100 of ETH deposited but only want to mint a certain amount of DSC
     * 
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        // increases dsc minted mapping for user
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

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

    // PRIVATE AND INTERNAL VIEW FUNCTIONS

    /*
     * by using multiple subsequent functions, as explained below, it returns the total stablecoin minted,
     and collateral value, this then can be checked to see if health factor is acceptable.
     */
    function _getAcountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * returns how close to liquidation a user is
     * if a user goes below 1, they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAcountInformation(user);
        // checks if collateral caclulated (using multiple functions) is acceptable for our conditions
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health factor (do they have enough collateral)
        // 2. revert if they do not

        uint256 userHealthFactor = _healthFactor(user);
        // if the user health factor is below 1, they cannot mint
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    // PUBLIC AND EXTERNAL VIEW FUNCTIONS

    /**
     *  gets collateral value by retreiving the specific token and amount the user requests,
     * passing these values to getUsdValue, which uses Chainlink to fetch price values and calculate collateral value.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     *  get price feed token for the token the user is wanting via chainlink,
     * and multiple by amount to get usd value
     * ADDITIONAL_FEED_PRECISION and PRECISION are decimal conversion to ensure consistency and correct calculations.
     *
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
