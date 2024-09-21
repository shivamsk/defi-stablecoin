// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {console} from "forge-std/console.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;

    uint256 public constant AMOUNT = 100 ether;
    address public constant OWNER_ADDRESS = address(1);
    address public constant ADDRESS_2 = address(2);

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
        vm.stopPrank();
    }

    function testMintRevertsIfAddressIsZero() public {
        vm.startPrank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), AMOUNT);
        vm.stopPrank();
    }

    function testMintRevertsIfAmountisZero() public {
        vm.startPrank(dsc.owner());
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(address(1), 0);
        vm.stopPrank();
    }

    function testMintSuccess() public {
        bool result;
        vm.startPrank(dsc.owner());
        result = dsc.mint(address(1), AMOUNT);
        vm.stopPrank();
        assertEq(result, true);
        assertEq(AMOUNT, dsc.balanceOf(address(1)));
    }

    function testBurnRevertsIfBalanceIsLessThanAmount() public {
        vm.startPrank(dsc.owner());
        console.log("balance: ", dsc.balanceOf(msg.sender));
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(200 ether);
        vm.stopPrank();
    }

    function testCanBurn() public {
        dsc.transferOwnership(OWNER_ADDRESS);
        vm.startPrank(OWNER_ADDRESS);
        // console.log("owner: ", dsc.owner());
        // console.log("balance: ", dsc.balanceOf(dsc.owner()));
        dsc.mint(OWNER_ADDRESS, AMOUNT);
        // console.log("address 2 balance: ", dsc.balanceOf(address(2)));
        // console.log("balance: ", dsc.balanceOf(dsc.owner()));
        // dsc.transferFrom(address(2), dsc.owner(), 100 ether);
        dsc.burn(100 ether);
        // console.log("After Burning - address 2 balance: ", dsc.balanceOf(address(2)));
        // console.log("After Burning - balance: ", dsc.balanceOf(dsc.owner()));
        vm.stopPrank();
    }

    function testCanBurnWithDifferentAddress() public {
        dsc.transferOwnership(OWNER_ADDRESS);

        vm.prank(ADDRESS_2);
        dsc.approve(OWNER_ADDRESS, AMOUNT);

        vm.startPrank(OWNER_ADDRESS);
        // console.log("owner: ", dsc.owner());
        // console.log("balance: ", dsc.balanceOf(dsc.owner()));
        dsc.mint(ADDRESS_2, AMOUNT);
        // console.log("address 2 balance: ", dsc.balanceOf(address(2)));
        // console.log("balance: ", dsc.balanceOf(dsc.owner()));
        dsc.transferFrom(ADDRESS_2, OWNER_ADDRESS, AMOUNT);
        dsc.burn(AMOUNT);
        // console.log("After Burning - address 2 balance: ", dsc.balanceOf(address(2)));
        // console.log("After Burning - balance: ", dsc.balanceOf(dsc.owner()));
        vm.stopPrank();
    }
}
