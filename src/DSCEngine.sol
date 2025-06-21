// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// tokens maintain a 1 token == 1 dollar peg
// this stablecoin has the properties:
// - exogenous collerateral
// - dollar pegged
// - algorithmic
// - similar to dai if it has no governance, and was only backed by wETH and wBTC

// our dsc system should always be overcollaterised to ensure we have sufficient coverage for dsc mints

// this contract is the core of the DSC system. It handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing colleratal
// this contract is very loosely based on the MakerDao DSS (DAI) system

contract DSCEngine {
    // deposit collateral and mint stablecoin
    function depositCollateralAndMintDsc() external {}

    function depositCollateral() external {}

    // redeem collateral by providing collateral
    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    // if people are nervous they have too much stablecoin and not enough collateral, and they want a quick way to have more collateral than dsc, they can quickly burn
    function burnDsc() external {}

    // if value of collateral drops too much, we need to liquidate to ensure backing of our stablecoin
    function liquidate() external {}

    // if you are under a threshold of, say, 150%, someone can pay back your minted dsc and can have your collateral for a discount.
    // e.g.
    // $100 ETH collateral reduces to $74
    // original mint of $50 dsc
    // becomes undercollateralised and users can liquidate others with undercollateralised positions
    // (ill pay back the $50 dsc, now user has zero debt, and liqidator gets all collateral)
    // liquidator gets $74 dollars for $50 dsc. incentivses people to always have health collateralisation
    function healthFactor() external view {}
}
