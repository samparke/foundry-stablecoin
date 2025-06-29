// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockFailMint} from "../mocks/MockFailMint.sol";
import {MockFailTransfer} from "../mocks/MockFailTransfer.sol";
import {MockFailTransferFrom} from "../mocks/MockFailTransferFrom.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public user = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_MINT = 100 ether;
    uint256 public constant AMOUNT_BURN = 1 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        // sets deployer using deploy script
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        // mints to user using a mint function from our erc20 mock
        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
    }

    // MODIFIERS

    // modifer of depositing collateral to avoid repeatedly typing out code
    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
        _;
    }

    // PRICE TESTS
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/eth = 30,000e18
        uint256 expectedUsd = 30000e18;
        // calls the getUsdValue from dsce contract to get actual weth price.
        // it passes the weth address, which then passes to chainlink to get the price, and then the function calculates the exact value via amount parameter
        // in our example, because we are only on an anvil chain, this is a mock - defined in the HelperConfig
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetUsdValueNotTheSame() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30001e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertNotEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // if eth is $2000, 100 ether / $2000 is 0.05 ether
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    // DEPOSIT COLLATERAL TESTS
    function testRevertsIfCollateralIsZero() public depositCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertTransferFailDepositCollateral() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailTransferFrom mockCollateral = new MockFailTransferFrom();
        // replacing weth (where transferFrom will succeed), with mockDsc (where it will fail)
        tokenAddresses = [address(mockCollateral)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        // we pass address(dsc) because we want to use the real stablecoin to mint and burn
        // this test is strictly about depositing collateral, not minting or burning
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        mockCollateral.mint(user, AMOUNT_COLLATERAL);

        vm.startPrank(user);
        ERC20Mock(address(mockCollateral)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockCollateral), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCollateralDepositIncrease() public depositCollateral {
        vm.startPrank(user);
        uint256 userCollateralAmount = dsce.getUserCollateralDeposited(address(user), weth);
        assertEq(userCollateralAmount, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCollateralInsufficientAllowance() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert();
        dsce.depositCollateral(weth, 100 ether);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedToken() public {
        ERC20Mock testToken = new ERC20Mock("TEST", "TEST", user, AMOUNT_COLLATERAL);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(testToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testRevertNotallowedTokenDepositCollateral() public {
        ERC20Mock failToken = new ERC20Mock("FAIL", "FAIL", user, 100e18);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(failToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralWithoutMinting() public depositCollateral {
        uint256 balance = dsc.balanceOf(user);
        assertEq(balance, 0);
    }

    // DEPOSIT COLLATERAL AND MINT DSC TESTS

    function testDepositCollateralAndMintDscToSeeIfDSCMintedIncreases() public depositCollateralAndMintDsc {
        uint256 actualDscMintedMapping = dsce.getDscMintedForUser(user);
        uint256 expectedDscMintedMapping = AMOUNT_MINT;
        assertEq(expectedDscMintedMapping, actualDscMintedMapping);
    }

    function testDepositCollateralAndMintToSeeIfDscBalanceIncreases() public depositCollateralAndMintDsc {
        uint256 actualDscBalanceOfUser = dsc.balanceOf(user);
        uint256 expectedDscBalanceOfUser = AMOUNT_MINT;
        assertEq(actualDscBalanceOfUser, expectedDscBalanceOfUser);
    }

    // REDEEM COLLATERAL TESTS

    function testRevertNeedsMoreThanZeroRedeemCollateral() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertTransferFailRedeemCollateral() public {
        address owner = msg.sender;
        vm.prank(owner);
        // deploy mock fail transfer contract
        MockFailTransfer mockDsc = new MockFailTransfer();
        // we use the address(mockDsc) instead of weth, becuase the mockDsc has a fail transfer, unlike weth which will succeed transfer
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
        mockDsc.mint(user, AMOUNT_COLLATERAL);
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));

        vm.startPrank(user);
        // user approves dsce engine to use the minted mockDsc (we approved earlier)
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockDsc), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralBalanceIncrease() public depositCollateral {
        vm.startPrank(user);
        uint256 expectedBalanceBeforeRedeem = AMOUNT_COLLATERAL;
        uint256 balanceBeforeRedeem = dsce.getUserCollateralDeposited(user, weth);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 expectedBalanceAfterRedeem = 0;
        uint256 balanceAfterRedeem = dsce.getUserCollateralDeposited(user, weth);
        vm.stopPrank();

        assertEq(expectedBalanceBeforeRedeem, balanceBeforeRedeem);
        assertEq(expectedBalanceAfterRedeem, balanceAfterRedeem);
    }

    // REDEEM COLLATERAL FOR DSC

    function testRedeemDepositCollateralForDsc() public depositCollateralAndMintDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), AMOUNT_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
        uint256 balance = dsc.balanceOf(user);
        assertEq(balance, 0);
    }

    // BURN TESTS

    function testRevertNeedsMoreThanZeroBurn() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testDscBalancedReducedWhenBurn() public depositCollateralAndMintDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), AMOUNT_MINT);
        uint256 expectedBalanceBeforeBurn = AMOUNT_MINT;
        uint256 balanceBeforeBurn = dsc.balanceOf(user);
        dsce.burnDsc(AMOUNT_BURN);
        uint256 expectedBalanceAfterBurn = 99 ether;
        uint256 balanceAfterBurn = dsc.balanceOf(user);
        vm.stopPrank();

        assertEq(expectedBalanceBeforeBurn, balanceBeforeBurn);
        assertEq(expectedBalanceAfterBurn, balanceAfterBurn);
    }

    function testBurnMoreThanUserHas() public depositCollateralAndMintDsc {
        vm.startPrank(user);
        vm.expectRevert();
        dsce.burnDsc(1);
        vm.stopPrank();
    }

    // // MINT TESTS

    function testRevertNeedsMoreThanZeroMint() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertFailMint() public {
        // deploys mock fail
        MockFailMint mockFailMint = new MockFailMint();
        // sets token and price address to pass into new dsc engine instance (constructor)
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        // we make a mockDsc, which passes the mockFailMint, instead of the correct passing of dsc in our deploy script
        DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockFailMint));
        // the dsc mock needs to be owned by mockDsce to mint
        mockFailMint.transferOwnership(address(mockDsce));

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
    }

    function testUserCanMint() public depositCollateral {
        vm.startPrank(user);
        dsce.mintDsc(AMOUNT_MINT);
        uint256 expectedUserBalance = AMOUNT_MINT;
        uint256 actualUserBalance = dsc.balanceOf(user);
        vm.stopPrank();
        assertEq(expectedUserBalance, actualUserBalance);
    }

    function testDscBalancedIncreaseWhenMint() public depositCollateralAndMintDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce), AMOUNT_MINT);
        uint256 expectedBalanceBeforeMint = AMOUNT_MINT;
        uint256 balanceBeforeMint = dsc.balanceOf(user);
        dsce.mintDsc(AMOUNT_MINT);
        uint256 expectedBalanceAfterMint = 200 ether;
        uint256 balanceAfterMint = dsc.balanceOf(user);
        vm.stopPrank();

        assertEq(expectedBalanceBeforeMint, balanceBeforeMint);
        assertEq(expectedBalanceAfterMint, balanceAfterMint);
    }

    // CONSTRUCTOR TESTS

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        // our constructor evaluates whether the tokenAddresses and priceFeedAddresses are the same length
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsce));
    }

    // GETTER TESTS

    function testGetPrecision() public view {
        uint256 precision = dsce.getPrecision();
        assertEq(precision, 1e18);
    }

    function testAdditionFeedPrecision() public view {
        uint256 additionalFeedPrecision = dsce.getAdditionalFeedPrecision();
        assertEq(additionalFeedPrecision, 1e10);
    }

    function testLiquidationThreshold() public view {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, 50);
    }

    function testLiquidationPrecision() public view {
        uint256 liquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(liquidationPrecision, 100);
    }

    function testLiquidationBonus() public view {
        uint256 liquidationBonus = dsce.getLiquidationBonus();
        assertEq(liquidationBonus, 10);
    }

    function testMinHealthFactor() public view {
        uint256 minHealth = dsce.getMinHealthFactor();
        assertEq(minHealth, 1e18);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(weth, collateralTokens[0]);
    }

    function testGetCollateralFeed() public view {
        address feed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(ethUsdPriceFeed, feed);
    }
}
