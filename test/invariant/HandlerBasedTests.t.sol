//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.t.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.t.sol";

contract HandlerBasedTests is Test {
    uint256 private constant MAX_DEPOSIT_AMOUNT = type(uint96).max;
    DSCEngine private immutable i_engine;
    DecentralizedStableCoin private immutable i_dsc;
    ERC20Mock private immutable i_weth;
    ERC20Mock private immutable i_wbtc;

    uint256 public s_timesMintCalled;
    address[] private s_usersDeposited;

    constructor(DSCEngine engine, DecentralizedStableCoin dsc) {
        i_engine = engine;
        i_dsc = dsc;
        address[] memory collateralTokens = i_engine.getAllowedCollateralTokens();
        i_weth = ERC20Mock(collateralTokens[0]);
        i_wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT_AMOUNT);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(i_engine), amount);
        i_engine.depositCollateral(address(collateral), amount);
        vm.stopPrank();

        if(_isUserDeposited(msg.sender)) {
            return;
        }
        
        s_usersDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT_AMOUNT);
        vm.startPrank(msg.sender);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        (uint256 totalDscMinted, uint256 totalCollateralDepositedInUsd) = i_engine.getAccountInformation();
        uint256 certainCollateralAmount = i_engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        int256 maxCollateralToRedeemInUsd = (int256(totalCollateralDepositedInUsd) / 2) - int256(totalDscMinted);
        vm.assume(i_engine.getHealthFactor() > 1);
        vm.assume(certainCollateralAmount > 0);
        uint256 certainCollateralValueInUsd = i_engine.getUsdValue(address(collateral), certainCollateralAmount);
        uint256 amountToRedeemInUsd = i_engine.getUsdValue(address(collateral), amount);
        vm.assume(amountToRedeemInUsd <= certainCollateralValueInUsd);
        int256 maxCertainCollateralToRedeem = maxCollateralToRedeemInUsd - (maxCollateralToRedeemInUsd - int256(certainCollateralValueInUsd));
        vm.assume(maxCertainCollateralToRedeem > 0);
        vm.assume(amountToRedeemInUsd <= uint256(maxCertainCollateralToRedeem));
        i_engine.redeemCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 userSeed) public {
        if(s_usersDeposited.length == 0) {
            return;
        }

        address user = getUserDepositedFromSeed(userSeed);
        vm.startPrank(user);
        (uint256 totalDscMinted, uint256 totalCollateralDepositedInUsd) = i_engine.getAccountInformation();
        int256 maxDscToMint = (int256(totalCollateralDepositedInUsd) / 2) - int256(totalDscMinted);
        vm.assume(maxDscToMint > 0);
        amount = bound(amount, 0, uint256(maxDscToMint));
        vm.assume(amount > 0);
        i_engine.mintDsc(amount);
        vm.stopPrank();
        s_timesMintCalled++;
    }

    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if(seed % 2 == 0) {
            return i_weth;
        }

        return i_wbtc;
    }

     function _isUserDeposited(address user) private view returns (bool) {
        for(uint256 i = 0; i < s_usersDeposited.length; i++) {
            if(s_usersDeposited[i] == user) {
                return true;
            }
        }

        return false;
    }

    function getUserDepositedFromSeed(uint256 seed) public view returns (address) {
        return s_usersDeposited[seed % s_usersDeposited.length];
    }
}