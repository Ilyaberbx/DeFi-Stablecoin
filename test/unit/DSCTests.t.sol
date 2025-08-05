//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DSCTests is Test {
    DecentralizedStableCoin private s_dsc;

    function setUp() external {
        s_dsc = new DecentralizedStableCoin();
    }

    function testBurnRevertsWhenAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin_BurnAmountMustBeMoreThanZero.selector);
        s_dsc.burn(0);
    }

    function testBurnRevertsWhenAmountIsGreaterThanBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(DecentralizedStableCoin.DecentralizedStableCoin_InsufficientBalance.selector, 0, 1)
        );
        s_dsc.burn(1);
    }

    function testMintRevertsWhenToIsZeroAddress() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin_MintToZeroAddress.selector);
        s_dsc.mint(address(0), 1);
    }

    function testMintRevertsWhenAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin_MintAmountMustBeMoreThanZero.selector);
        s_dsc.mint(address(1), 0);
    }
}
