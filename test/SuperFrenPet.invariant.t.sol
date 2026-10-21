// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SuperFrenPet} from "../src/SuperFrenPet.sol";

/// @dev A closed set of holders lets the invariant sum every possible token balance.
contract TokenHandler is Test {
    SuperFrenPet public immutable token;
    address[4] public actors;

    constructor(SuperFrenPet token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = token.balanceOf(from);
        amount = bound(amount, 0, balance);
        uint256 recipientBalance = token.balanceOf(to);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? balance : balance - amount);
        assertEq(token.balanceOf(to), from == to ? recipientBalance : recipientBalance + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = token.balanceOf(owner);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.balanceOf(owner), balance);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = token.balanceOf(from);
        uint256 allowance = token.allowance(from, spender);
        uint256 recipientBalance = token.balanceOf(to);
        amount = bound(amount, 0, balance < allowance ? balance : allowance);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.balanceOf(from), from == to ? balance : balance - amount);
        assertEq(token.balanceOf(to), from == to ? recipientBalance : recipientBalance + amount);
        assertEq(token.allowance(from, spender), allowance == type(uint256).max ? allowance : allowance - amount);
    }
}

contract SuperFrenPetInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SuperFrenPet private token;
    TokenHandler private handler;

    function setUp() public {
        token = new SuperFrenPet();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantSupplyAndSumOfBalancesStayConstant() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(balances, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
