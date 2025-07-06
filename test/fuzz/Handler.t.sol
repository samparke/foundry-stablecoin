// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralisedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // max uint96 value
    address[] public usersWithCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralisedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;
        // returns an array of collateral tokens from our engine
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // gets the token - either weth or wbtc
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // never deposits 0 or above MAX_DEPOSIT_SIZE (max uint96 number)
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        // deposits that specific collateral
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);

        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // the amount of collateral the user has deposited as collateral, and thus the total to be redeemed
        uint256 maxCollateralToRedeem = dsce.getUserCollateralDeposited(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();
    }

    // helper functions

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
