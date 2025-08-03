//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.t.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.t.sol";

contract ConfigHelper is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address wethToken;
        address wbtcToken;
        uint256 deployerKey;
    }

    uint8 private constant DECIMALS = 8;
    int256 private constant ETH_USD_PRICE = 2000e8;
    int256 private constant BTC_USD_PRICE = 2000e8;

    NetworkConfig public s_activeNetworkConfig;

    constructor() {
        if(block.chainid == 11155111) {
            s_activeNetworkConfig = getSepoliaNetworkConfig();
        } else {
            s_activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaNetworkConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wethToken: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            wbtcToken: 0x29f2D40B0605204364af54EC677bD022dA425d03,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if(s_activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return s_activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock weth = new ERC20Mock("WETH", "WETH", address(this), 10000 ether);
        ERC20Mock wbtc = new ERC20Mock("WBTC", "WBTC", address(this), 10000 ether);
        vm.stopBroadcast();
        return NetworkConfig({
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            wethToken: address(weth),
            wbtcToken: address(wbtc),
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
        });
    }

}