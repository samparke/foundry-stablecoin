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
    error DSCEngine__HealthFactorIsOk();
    error DSCEngine__HealthFactorNotImproved();

    // STATE VARIABLES
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollaterised
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    // maps token to price feed (which is the chainlink address). This is set in the constructor.
    mapping(address token => address priceFeed) private s_priceFeeds;
    // maps the users to a token and how much token they have deposited for collateral.
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    // maps user to the amount they minted
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    // EVENTS
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

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

    /*
     * @param tokenCollateralAddress The address of the token to be deposited as collateral
     * @param amountCollateral amount collateral
     * @param amountDscToMint amount to stablecoin to mint
     * @notice this function will deposit your collateral and mint dsc in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
    This function allows users to deposit collateral of a specific tokenAddress,
    checks if the token is allowed, and if so, transfers the tokens from their address to the contract.

    @param tokenCollateralAddress: the address of the token to deposit as collateral
    @param amountCollateral: the amount of collateral to deposit
    */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
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

    /*
     * 
     * @param tokenCollateralAddress the collateral address to redeem
     * @param amountCollateral the amount of collateral to redeem
     * @param amountDscToBurn the amount stablecoin to burn
     * This function burns dsc and redeems collateral in one transaction
     * 
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeem collateral already checks health factor
    }

    // to redeem collateral:
    // 1. health factor must be above 1 after collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * 
     * @param amountDscToMint: the amount of DSC to mint. A user may have $100 of ETH deposited but only want to mint a certain amount of DSC
     * 
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        // increases dsc minted mapping for user
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    // if people are nervous they have too much stablecoin and not enough collateral, and they want a quick way to have more collateral than dsc, they can quickly burn
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // if value of collateral drops too much, we need to liquidate to ensure backing of our stablecoin
    // essentially, if someone is almost is undercollaterised, we will pay you to liquidate them
    // for example: if $100 eth is backing $50 dsc, which then drops to $75eth (undercollaterised),
    // the liquidator takes the $75 and burns the $50 dsc, receiving a bonus

    /*
     * @param collateral  the erc20 collateral address to liquidate from the user
     * @param user the user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover the amount of dsc you want to burn to improve the users health factor
     * You can partially liquidate a user (we just want to improve the users health factor).
     * you will get a liquidation bonus for taking users funds
     * this function working assumes the protocol will be roughly 200% overcollateralised in order for this to work.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // first get health factor for user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOk();
        }

        // burn their dsc debt
        // and take their collateral
        // for example: a bad user -> $140eth, $100 dsc
        // debt to cover is $100
        // $100 of dsc = ??? eth?
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // give liquidator 10% bonus ($110 of WETH for 100 DSC).
        // 0.1 ETH * 0.1 = liquidator gets 0.11 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // if you are under a threshold of, say, 150%, someone can pay back your minted dsc and can have your collateral for a discount.
    // e.g.
    // $100 ETH collateral reduces to $74
    // original mint of $50 dsc
    // becomes undercollateralised and users can liquidate others with undercollateralised positions
    // (ill pay back the $50 dsc, now user has zero debt, and liqidator gets all collateral)
    // liquidator gets $74 dollars for $50 dsc. incentivses people to always have health collateralisation
    function healthFactor() external view {}

    // PRIVATE AND INTERNAL VIEW FUNCTIONS

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(onBehalfOf, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

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

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of token, such as ETH
        // $/ETH. How much ETH?
        // e.g. $2000 / $1000 ETH = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price)) * ADDITIONAL_FEED_PRECISION;
    }

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
