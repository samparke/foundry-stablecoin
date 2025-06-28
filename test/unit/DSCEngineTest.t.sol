// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

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

    // // MINT TESTS

    function testRevertNeedsMoreThanZeroMint() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
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
}
