// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Siva Krishna Merugu
 * @notice This library is used to check the Chainlink Oracle for Stale Data
 * If a price is stale, functions will revert and render the DSCEngine unusable - this is by Design
 * We want the DSCEngine to freeze if prices become stale
 *
 * So if chainlink network explodes and you have a lot of money locked in the protocol --- Very bad
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIME_OUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface chainlinkFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            chainlinkFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StalePrice();
        }

        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIME_OUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
