// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * this library is used to check Chainlink Oracle for stale data
 * if a price is stale, the function will revert and render the dsce unusable - by design
 * we want dsce to freeze is price becomes stale
 * if Chainlink network explodes, and you have money locked in the protocol, you are not in a good position
 * this is a known issue
 */
library OracleLib {
    error OracleLib__StalePrice();
    // this heartbeat is much longer than Chainlinks

    uint256 private constant TIMEOUT = 3 hours;
    // (uint80, int256, uint256, uint256, uint80) -> the same data returned from latestRoundData from Aggregator

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        // fetches data from Chainlink aggregator
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
