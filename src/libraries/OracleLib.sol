// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Ebenezer Jojo Mensah
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale, the function will revert, and render the ZaxEngine unusable - this is by design.
 * We want the ZaxEngine to freeze if prices become stale.
 *
 * So if the Chainlink network explodes and you have a lot of money locked in the protocol... too bad.
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    /**
     *
     * @param priceFeed Pricefeed of the collateral on sepolia (*or any other network)
     * @return id of the latest round data
     * @return answer
     * @return the seconds since the priceFeed started
     * @return the last time the price was updated
     * @return
     */
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSincePriceUpdated = block.timestamp - updatedAt;
        if (secondsSincePriceUpdated > TIMEOUT) revert OracleLib__StalePrice();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
