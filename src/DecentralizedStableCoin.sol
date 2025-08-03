//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Illia Verbanov
 * @notice This is ther contract meant to be governed by DSCEngine. This is just ERC20 token that is backed by collateral.
 * @dev This contract is implementation of a decentralized stablecoin.
 * Collateral: wETH, wBTC (Exogenous)
 * Stability mechanism: Algorithmic
 * Relative stability: Anchored (Pegged)
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin_InsufficientBalance(uint256 balance, uint256 amount);
    error DecentralizedStableCoin_BurnAmountMustBeMoreThanZero();
    error DecentralizedStableCoin_MintToZeroAddress();
    error DecentralizedStableCoin_MintAmountMustBeMoreThanZero();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 amount) public override onlyOwner {
        if (amount <= 0) {
            revert DecentralizedStableCoin_BurnAmountMustBeMoreThanZero();
        }
        uint256 balance = balanceOf(msg.sender);
        if (amount > balance) {
            revert DecentralizedStableCoin_InsufficientBalance(balance, amount);
        }
        super.burn(amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DecentralizedStableCoin_MintToZeroAddress();
        }
        if (amount <= 0) {
            revert DecentralizedStableCoin_MintAmountMustBeMoreThanZero();
        }
        _mint(to, amount);
        return true;
    }
}
