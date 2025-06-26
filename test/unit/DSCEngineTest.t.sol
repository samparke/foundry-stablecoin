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
    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(user);
        // user approves dsce engine to use token, this is equivalent to allowing uniswap or another
        // dapp to swap your tokens, for example
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCollateralDepositIncrease() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 userCollateralAmount = dsce.getUserCollateralDeposited(address(user), weth);
        assertEq(userCollateralAmount, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCollateralTransferFailed() public {}

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
