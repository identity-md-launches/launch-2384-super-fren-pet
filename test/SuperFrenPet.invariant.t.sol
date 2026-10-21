// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SuperFrenPet} from "../src/SuperFrenPet.sol";

/// @dev A closed set of holders lets the invariant sum every possible token balance.
contract TokenHandler is Test {
    SuperFrenPet public immutable token;
    address[4] public actors;
    // The model starts from the specified allocation and changes only on successful
    // calls. Never resynchronize it from the token: that would hide earlier corruption.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(SuperFrenPet token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
        }
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, 0, balance);
        uint256 recipientBalance = expectedBalance[to];

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? balance : balance - amount);
        assertEq(token.balanceOf(to), from == to ? recipientBalance : recipientBalance + amount);
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[owner];

        _approve(owner, spender, amount);
        assertEq(token.balanceOf(owner), balance);
    }

    // Make infinite approvals and revocation common in a sequence instead of
    // relying on the fuzzer to happen to choose exactly uint256.max or zero.
    function approveMaximumOrRevoke(uint256 ownerSeed, uint256 spenderSeed, bool revoke) external {
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], revoke ? 0 : type(uint256).max);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 allowance = expectedAllowance[from][spender];
        uint256 recipientBalance = expectedBalance[to];
        amount = bound(amount, 0, balance < allowance ? balance : allowance);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.balanceOf(from), from == to ? balance : balance - amount);
        assertEq(token.balanceOf(to), from == to ? recipientBalance : recipientBalance + amount);
        assertEq(token.allowance(from, spender), allowance == type(uint256).max ? allowance : allowance - amount);
        _recordTransfer(from, to, amount);
        if (allowance != type(uint256).max) expectedAllowance[from][spender] -= amount;
    }

    function transferBeyondBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - balance);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update on rejection. The invariant checks ALL balances and
        // allowances, including accounts unrelated to this attempted transfer.
    }

    function transferFromBeyondAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 approved)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approved = bound(approved, 0, 1_000_000_000 * 10 ** 18);
        _approve(from, spender, approved);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(from, to, approved + 1);
    }

    function transferFromBeyondBalance(
        uint256 spenderSeed,
        uint256 fromSeed,
        uint256 toSeed,
        uint256 excess,
        bool infiniteApproval
    ) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + bound(excess, 1, type(uint256).max - 1 - balance);
        _approve(from, spender, infiniteApproval ? type(uint256).max : amount);

        // The allowance is sufficient, so this reaches the balance check after
        // the finite allowance would have been spent. Reverting must restore it.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function transferToZero(uint256 fromSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        if (delegated) _approve(from, spender, amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(from, address(0), amount);
        } else {
            vm.prank(from);
            token.transfer(address(0), amount);
        }
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SuperFrenPetInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SuperFrenPet private token;
    TokenHandler private handler;

    function setUp() public {
        token = new SuperFrenPet();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        // Give each actor funds and a finite approval before randomized calls,
        // so delegated transfers can move real value early in every sequence.
        for (uint256 i; i < 4; ++i) {
            if (i != 0) handler.transfer(0, i, SUPPLY / 4);
            handler.approve(i, (i + 1) % 4, SUPPLY / 4);
        }

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.approveMaximumOrRevoke.selector;
        selectors[4] = TokenHandler.transferBeyondBalance.selector;
        selectors[5] = TokenHandler.transferFromBeyondAllowance.selector;
        selectors[6] = TokenHandler.transferFromBeyondBalance.selector;
        selectors[7] = TokenHandler.transferToZero.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariantSupplyAndSumOfBalancesStayConstant() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            balances += token.balanceOf(actor);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "balance differs from call history");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(actor, spender),
                    handler.expectedAllowance(actor, spender),
                    "allowance differs from call history"
                );
            }
            assertEq(token.allowance(actor, address(0)), 0);
        }
        assertEq(balances, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
