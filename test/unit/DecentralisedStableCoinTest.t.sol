// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";

contract DecentralisedStableCoinTest is Test {
    DecentralisedStableCoin dsc;

    function setUp() public {
        dsc = new DecentralisedStableCoin();
    }

    function testRevertMustBeMoreThanZeroBurn() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testRevertBurnAmountExceedBalance() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStablecoin__BurnAmountExceedsBalance.selector);
        dsc.burn(1);
    }

    function testRevertNotZeroAddressMint() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), 1);
    }

    function testRevertMustBeMoreThanZeroMint() public {
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(address(1), 0);
    }
}
