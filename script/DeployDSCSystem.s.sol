//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {ConfigHelper} from "./config/ConfigHelper.s.sol";

contract DeployDSCSystem is Script {
    function run() external returns (DecentralizedStableCoin, DSCEngine, ConfigHelper) {
        ConfigHelper configHelper = new ConfigHelper();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address wethToken, address wbtcToken, uint256 deployerKey)
        = configHelper.s_activeNetworkConfig();

        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = wethToken;
        tokenAddresses[1] = wbtcToken;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = wethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (dsc, engine, configHelper);
    }
}
