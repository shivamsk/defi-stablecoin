// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";

contract OracleLibTest is StdCheats, Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator mockV3Aggregator;

    uint8 private constant DECIMALS = 8;
    int256 private constant ANSWER = 2000 ether;

    function setUp() public {
        mockV3Aggregator = new MockV3Aggregator(DECIMALS, ANSWER);
    }

    function testRevertsWhenupdatedAtIsZero() public {
        mockV3Aggregator.updateRoundData(0, 0, 0, 0);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(mockV3Aggregator)));
    }

    function testRevertsWhenTimeOut() public {
        console.log("BlockTimestamp ", block.timestamp); // 1
        // UpdatedAt = 1 , coming from mockv3aggregator
        vm.warp(block.timestamp + 4 hours);
        console.log("Later BlockTimestamp", block.timestamp);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(mockV3Aggregator)).staleCheckLatestRoundData();
    }

    function testStateCheckLatestRoundDataSuccess() public {
        console.log("BlockTimestamp ", block.timestamp); // 1
        // UpdatedAt = 1 , coming from mockv3aggregator
        vm.warp(block.timestamp + OracleLib.getTimeOut()); // 10801
        // secondsSince = 10801 - 1= 10800 < TIME_OUT
        console.log("Later BlockTimestamp", block.timestamp);
        AggregatorV3Interface(address(mockV3Aggregator)).staleCheckLatestRoundData();
    }
}
