// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Zax} from "../../src/Zax.sol";

contract ZaxTest is StdCheats, Test {
    Zax zax;

    function setUp() public {
        zax = new Zax();
    }

    function testMustMintMoreThanZero() public {
        vm.prank(zax.owner());
        vm.expectRevert();
        zax.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(zax.owner());
        zax.mint(address(this), 100);
        vm.expectRevert();
        zax.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(zax.owner());
        zax.mint(address(this), 100);
        vm.expectRevert();
        zax.burn(101);
        vm.stopPrank();
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(zax.owner());
        vm.expectRevert();
        zax.mint(address(0), 100);
        vm.stopPrank();
    }
}
