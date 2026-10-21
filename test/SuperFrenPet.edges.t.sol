// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SuperFrenPet} from "src/SuperFrenPet.sol";

/// @dev A token recipient need not implement a receiver hook. Any attempted
/// callback to this contract would revert, but an ordinary ERC-20 transfer works.
contract SFPRecipientWithoutHook {
    fallback() external {
        revert("unexpected receiver callback");
    }

    function send(SuperFrenPet token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

/// @dev Supplements the original suite with boundary and multi-step properties.
/// forge-config: default.fuzz.runs = 1000
contract SuperFrenPetEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    SuperFrenPet private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new SuperFrenPet();
        alice = makeAddr("edge-alice");
        bob = makeAddr("edge-bob");
        spender = makeAddr("edge-spender");
    }

    function testOneWeiCanBeTransferredAndSpentExactly() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));

        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);

        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testOwnerTransferFromRequiresAndConsumesSelfApproval() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);

        vm.startPrank(alice);
        assertTrue(token.approve(alice, 1));
        assertTrue(token.transferFrom(alice, bob, 1));
        vm.stopPrank();
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function testMaximumMinusOneAllowanceIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));

        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function testMaximumTransferFromCannotBypassBalanceWithInfiniteAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);

        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInfiniteApprovalSurvivesFailureAndAuthorizesFutureReceipts() public {
        vm.prank(alice);
        token.approve(spender, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);

        // The approval is a continuing authorization, not a snapshot of funds.
        for (uint256 i; i < 2; ++i) {
            assertTrue(token.transfer(alice, 1));
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 1));
            assertEq(token.allowance(alice, spender), type(uint256).max);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), i + 1);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testLoweringPartlySpentAllowanceDiscardsTheOldBudget() public {
        token.approve(spender, 10);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        assertEq(token.allowance(address(this), spender), 6);

        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 3);
        assertEq(token.allowance(address(this), spender), 2);
        assertEq(token.balanceOf(alice), 4);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 6);
        assertEq(token.balanceOf(address(this)), SUPPLY - 6);
    }

    function testZeroSpenderIsInvalidForZeroAndMaximumApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);

        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromStillRejectsZeroEndpoints() public {
        // Both calls are reachable from an ordinary nonzero caller. No prank
        // impersonates address(0), which cannot originate a transaction.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);

        // OpenZeppelin validates the owner while spending even a zero allowance.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);

        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testEntireSupplyCanRoundTripThroughContractWithoutReceiverHook() public {
        SFPRecipientWithoutHook recipient = new SFPRecipientWithoutHook();
        assertTrue(token.transfer(address(recipient), SUPPLY));
        assertEq(token.balanceOf(address(recipient)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);

        assertTrue(recipient.send(token, address(this), SUPPLY));
        assertEq(token.balanceOf(address(recipient)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzApprovalsAreIsolatedByOwnerAndSpender(uint256 first, uint256 second, uint256 replacement) public {
        token.approve(spender, first);
        token.approve(bob, second);
        vm.prank(alice);
        token.approve(spender, second);

        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), bob), second);
        assertEq(token.allowance(alice, spender), second);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzBalanceFailureRestoresAnyFiniteAllowance(uint256 balance, uint256 amount, uint256 approved)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        approved = bound(approved, amount, type(uint256).max - 1);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);

        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInvalidReceiverRestoresAnyAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);

        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromWithAliasedRoles(uint256 amount, uint256 approved, uint8 layout) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        layout %= 4;
        // Cover from == to, from == caller, caller == to, and all three equal.
        address caller = layout == 1 || layout == 3 ? alice : spender;
        address to = layout == 0 || layout == 3 ? alice : (layout == 2 ? spender : bob);
        token.transfer(alice, SUPPLY);
        vm.prank(alice);
        token.approve(caller, approved);

        vm.prank(caller);
        assertTrue(token.transferFrom(alice, to, amount));

        assertEq(token.balanceOf(alice), to == alice ? SUPPLY : SUPPLY - amount);
        if (to != alice) assertEq(token.balanceOf(to), amount);
        assertEq(token.allowance(alice, caller), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzRoundTripRestoresPreexistingBalances(uint256 aliceBalance, uint256 bobBalance, uint256 amount)
        public
    {
        aliceBalance = bound(aliceBalance, 0, SUPPLY);
        bobBalance = bound(bobBalance, 0, SUPPLY - aliceBalance);
        amount = bound(amount, 0, aliceBalance);
        token.transfer(alice, aliceBalance);
        token.transfer(bob, bobBalance);

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceBalance - amount);
        assertEq(token.balanceOf(bob), bobBalance + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));

        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSplitSpendingExhaustsOnlyItsApprovedBudget(uint256 budget, uint256 first) public {
        budget = bound(budget, 1, SUPPLY);
        first = bound(first, 0, budget);
        token.approve(spender, budget);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), budget - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, budget - first));

        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), budget - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - budget);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
