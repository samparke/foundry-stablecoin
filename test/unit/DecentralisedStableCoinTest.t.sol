// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";

contract DecentralisedStableCoinTest is Test {
    DecentralisedStableCoin dsc;
    address owner = makeAddr("owner");

    function setUp() public {
        dsc = new DecentralisedStableCoin();
    }

    function testRevertMustBeMoreThanZeroBurn() public {
        dsc.transferOwnership(owner);
        vm.startPrank(owner);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
        vm.stopPrank();
    }

    function testRevertBurnAmountExceedBalanceRevert() public {
        dsc.transferOwnership(owner);
        vm.startPrank(owner);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStablecoin__BurnAmountExceedsBalance.selector);
        dsc.burn(1);
        vm.stopPrank();
    }
}
