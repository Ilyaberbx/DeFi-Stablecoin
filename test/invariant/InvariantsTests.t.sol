//SPDX-License-Identifier: MIT

//1. Total Supply of DSC should be less or equal to the total value of all collateral deposited
//2. Getter view functions should never revert => evergreen invariant
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSCSystem} from "../../script/DeployDSCSystem.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ConfigHelper} from "../../script/config/ConfigHelper.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";
import {HandlerBasedTests} from "./HandlerBasedTests.t.sol";

contract InvariantsTests is Test {
    DecentralizedStableCoin private s_dsc;
    DSCEngine private s_engine;
    ConfigHelper private s_configHelper;
    HandlerBasedTests private s_handler;
    address private s_wethUsdPriceFeed;
    address private s_wbtcUsdPriceFeed;
    address private s_wethToken;
    address private s_wbtcToken;
    uint256 private s_deployerKey;

    function setUp() external {
        DeployDSCSystem deployer = new DeployDSCSystem();
        (s_dsc, s_engine, s_configHelper) = deployer.run();
        (s_wethUsdPriceFeed, s_wbtcUsdPriceFeed, s_wethToken, s_wbtcToken, s_deployerKey) =
            s_configHelper.s_activeNetworkConfig();
        s_handler = new HandlerBasedTests(s_engine, s_dsc);
        targetContract(address(s_handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = s_dsc.totalSupply();
        uint256 totalWeth = IERC20(s_wethToken).balanceOf(address(s_engine));
        uint256 totalWbtc = IERC20(s_wbtcToken).balanceOf(address(s_engine));
        uint256 totalWethValue = s_engine.getUsdValue(s_wethToken, totalWeth);
        uint256 totalWbtcValue = s_engine.getUsdValue(s_wbtcToken, totalWbtc);
        uint256 totalCollateralValue = totalWethValue + totalWbtcValue;
        console.log("times mint called", s_handler.s_timesMintCalled());
        console.log("totalSupply", totalSupply);
        console.log("totalWethValue", totalWethValue);
        console.log("totalWbtcValue", totalWbtcValue);
        assert(totalCollateralValue >= totalSupply);
    }
}
