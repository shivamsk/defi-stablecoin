// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// Handler will narrow down the way we call function

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
    }

    // redeem collateral

    function depositCollateral(address collateralSeed, uint256 amountCollateral) public {
        dscEngine.depositCollateral(collateralSeed, amountCollateral);
    }
}
