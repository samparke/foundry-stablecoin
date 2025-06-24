// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralisedStableCoin, DSCEngine, HelperConfig) {
        // fetches to appropriate chain, such as sepolia or anvil, and then sets token addresses etc from our config
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        // deployerKey is our private key
        vm.startBroadcast(deployerKey);
        DecentralisedStableCoin dsc = new DecentralisedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        // inherits transferOwnership from DecentralisedStableCoin, which inherits from ERC20 contract.
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (dsc, engine, config);
    }
}
