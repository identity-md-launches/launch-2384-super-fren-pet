// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SuperFrenPet} from "../src/SuperFrenPet.sol";

/// @dev Test-only factory: exercises the immediate deployer and CREATE2 launch path.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (SuperFrenPet) {
        return new SuperFrenPet{salt: salt}();
    }

    function send(SuperFrenPet token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract SuperFrenPetTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    SuperFrenPet private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new SuperFrenPet();
    }

    function testMetadataAndInitialSupply() public view {
        assertEq(token.name(), "Super Fren Pet");
        assertEq(token.symbol(), "SFP");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        SuperFrenPet deployed = new SuperFrenPet();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function testEOADeployerReceivesEntireSupply() public {
        vm.prank(alice);
        SuperFrenPet deployed = new SuperFrenPet();
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testFactoryReceivesEntireSupplyInsteadOfTransactionOrigin() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        vm.prank(alice, alice);
        SuperFrenPet deployed = factory.deploy(keccak256("launch"));

        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testLaunchDistributionClaimAndPoolTransfersAreExact() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        SuperFrenPet deployed = factory.deploy(keccak256("distribution"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainderRecipient = makeAddr("remainder recipient");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;

        assertTrue(factory.send(deployed, distributor, swarmShare));
        assertTrue(factory.send(deployed, poolManager, poolShare));
        assertTrue(factory.send(deployed, remainderRecipient, SUPPLY - swarmShare - poolShare));
        assertEq(deployed.balanceOf(distributor), swarmShare);
        assertEq(deployed.balanceOf(poolManager), poolShare);
        assertEq(deployed.balanceOf(remainderRecipient), SUPPLY / 10);
        assertEq(deployed.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, swarmShare));
        assertEq(deployed.balanceOf(alice), swarmShare);
        assertEq(deployed.balanceOf(distributor), 0);

        // Token-side settlement only; the network's protected suite runs actual v4 swaps.
        uint256 tradeAmount = 125 ether;
        vm.prank(poolManager);
        assertTrue(deployed.transfer(bob, tradeAmount));
        assertEq(deployed.balanceOf(bob), tradeAmount);
        assertEq(deployed.balanceOf(poolManager), poolShare - tradeAmount);
        vm.prank(bob);
        assertTrue(deployed.transfer(poolManager, tradeAmount));
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(poolManager), poolShare);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testTransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 17 ether);
        assertTrue(token.transfer(alice, 17 ether));
        assertEq(token.balanceOf(alice), 17 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 17 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferEntireBalance() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function testSelfTransferDoesNotChangeBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testTransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testInsufficientBalanceRevertsWithoutChangingBalances() public {
        token.transfer(alice, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 5 ether + 1)
        );
        vm.prank(alice);
        token.transfer(bob, 5 ether + 1);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferAmountRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testApproveReplacesAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 30 ether);
        assertTrue(token.approve(spender, 30 ether));
        assertEq(token.allowance(address(this), spender), 30 ether);

        assertTrue(token.approve(spender, 12 ether));
        assertEq(token.allowance(address(this), spender), 12 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testApprovalDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1 ether));
        assertEq(token.allowance(alice, spender), 1 ether);
        assertEq(token.balanceOf(alice), 0);
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1 ether);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testTransferFromDecrementsFiniteAllowanceAndEmitsTransfer() public {
        token.transfer(alice, 50 ether);
        vm.prank(alice);
        token.approve(spender, 20 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 12 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 12 ether));
        assertEq(token.balanceOf(alice), 38 ether);
        assertEq(token.balanceOf(bob), 12 ether);
        assertEq(token.allowance(alice, spender), 8 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testExhaustedAllowanceCannotBeReused() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10 ether));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function testInfiniteAllowanceIsNotDecremented() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 17 ether));
        assertTrue(token.transferFrom(address(this), bob, 23 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 17 ether);
        assertEq(token.balanceOf(bob), 23 ether);
    }

    function testRevokedAllowanceCannotBeSpent() public {
        token.approve(spender, type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testInsufficientAllowanceRevertsAtomically() public {
        token.approve(spender, 9 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 9 ether, 10 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 9 ether);
    }

    function testBalanceFailureRestoresSpentAllowance() public {
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        token.approve(spender, 20 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 10 ether)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 10 ether);
        assertEq(token.allowance(alice, spender), 20 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function testInvalidReceiverRestoresSpentAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testDeployerCannotSpendHolderBalanceWithoutApproval() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function testUnapprovedThirdPartyCannotUseAnotherSpendersAllowance() public {
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromToSelfConsumesAllowanceButPreservesBalance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testNoMintBurnOwnershipOrUpgradeEntryPoints() public {
        bytes[] memory calls = new bytes[](10);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[5] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[7] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[8] = abi.encodeWithSignature("initialize(address)", bob);
        calls[9] = abi.encodeWithSignature("setMinter(address)", bob);

        token.transfer(alice, 10 ether);
        for (uint256 i; i < calls.length; ++i) {
            _assertUnsupportedCall(address(this), calls[i]);
            _assertUnsupportedCall(alice, calls[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function testNoPrivilegedFreezeOrSeizureAndHolderStillTransfers() public {
        bytes[] memory calls = new bytes[](10);
        calls[0] = abi.encodeWithSignature("pause()");
        calls[1] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[2] = abi.encodeWithSignature("blocklist(address)", alice);
        calls[3] = abi.encodeWithSignature("freeze(address)", alice);
        calls[4] = abi.encodeWithSignature("freezeAccount(address)", alice);
        calls[5] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[6] = abi.encodeWithSignature("setBlocked(address,bool)", alice, true);
        calls[7] = abi.encodeWithSignature("lock(address)", alice);
        calls[8] = abi.encodeWithSignature("disableTransfers()");
        calls[9] = abi.encodeWithSignature("seize(address)", alice);

        token.transfer(alice, 10 ether);
        for (uint256 i; i < calls.length; ++i) {
            _assertUnsupportedCall(address(this), calls[i]);
            _assertUnsupportedCall(spender, calls[i]);
        }
        assertEq(token.balanceOf(alice), 10 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromConservesBalancesAndConsumesAllowance(
        uint256 balance,
        uint256 approved,
        uint256 amount
    ) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, balance);
        approved = bound(approved, amount, type(uint256).max - 1);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), balance - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(alice, spender), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzOverspendingRevertsWithoutChangingState(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        uint256 amount = balance + excess;
        token.transfer(alice, balance);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzUnapprovedTransferReverts(uint256 balance, uint256 approved) public {
        balance = bound(balance, 1, SUPPLY);
        approved = bound(approved, 0, balance - 1);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, approved + 1);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _assertUnsupportedCall(address caller, bytes memory data) private {
        vm.prank(caller);
        (bool success,) = address(token).call(data);
        assertFalse(success, "unexpected privileged entry point");
    }
}

