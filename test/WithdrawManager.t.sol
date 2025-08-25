// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract WithdrawManagerTest is BaseTest {

    function setUp() public override {
        super.setUp();

        vm.prank(user);
        stakingCore.stake{value: 1 ether}("");

        vm.prank(user2);
        stakingCore.stake{value: 10 ether}("");
    }

    function test_withdraw() public {
        vm.startPrank(user);
        beHYPE.approve(address(withdrawManager), 1 ether);
        withdrawManager.withdraw(1 ether, false);
        vm.stopPrank();

        assertEq(beHYPE.balanceOf(user), 0 ether);
        assertEq(beHYPE.balanceOf(address(withdrawManager)), 1 ether);

        vm.startPrank(user2);
        beHYPE.approve(address(withdrawManager), 10 ether);
        withdrawManager.withdraw(10 ether, false);
        vm.stopPrank();

        assertEq(beHYPE.balanceOf(user2), 0 ether);
        assertEq(beHYPE.balanceOf(address(withdrawManager)), 11 ether);

        uint256[] memory unclaimedWithdrawals = withdrawManager.getUserUnclaimedWithdrawals(user);
        assertEq(unclaimedWithdrawals.length, 1);
        assertEq(unclaimedWithdrawals[0], 1);

        unclaimedWithdrawals = withdrawManager.getUserUnclaimedWithdrawals(user2);
        assertEq(unclaimedWithdrawals.length, 1);
        assertEq(unclaimedWithdrawals[0], 2);

        vm.prank(admin);
        withdrawManager.finalizeWithdrawals(1);
        assertEq(withdrawManager.canClaimWithdrawal(1), true);
        assertEq(withdrawManager.canClaimWithdrawal(2), false);

        uint256 balanceBefore = address(user).balance;
        uint256 balanceBeforeBeHYPE = beHYPE.balanceOf(address(withdrawManager));
        vm.prank(user);
        withdrawManager.claimWithdrawal(1);

        assertEq(user.balance, balanceBefore + 1 ether);
        assertEq(beHYPE.balanceOf(address(withdrawManager)), balanceBeforeBeHYPE - 1 ether);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.WithdrawalNotFinalized.selector));
        withdrawManager.claimWithdrawal(1);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.WithdrawalNotFinalized.selector));
        withdrawManager.claimWithdrawal(2);
    }

    /* ========== INSTANT WITHDRAWAL TESTS ========== */

    function test_instantWithdrawal() public {
        vm.deal(user, 100 ether);

        vm.prank(user);
        stakingCore.stake{value: 89 ether}("");
        assertEq(stakingCore.getTotalProtocolHype(), 100 ether);

        mockDepositToHyperCore(99 ether);

        assertEq(withdrawManager.getLiquidHypeAmount(), 1 ether);

        // 1 ether should be able to be withdrawn instantly
        vm.startPrank(user);
        uint256 userBalanceBefore = user.balance;
        beHYPE.approve(address(withdrawManager), 1 ether);
        withdrawManager.withdraw(1 ether, true);
       
        uint256 instantWithdrawalFee = 0.003 ether; // 30 bps fee on 1 ether
        assertEq(beHYPE.balanceOf(roleRegistry.protocolTreasury()), instantWithdrawalFee);
        assertEq(user.balance, userBalanceBefore + 0.997 ether);
        assertEq(beHYPE.balanceOf(address(withdrawManager)), 0 ether);
        assertEq(withdrawManager.totalInstantWithdrawableAmount(), 0);
    }

    function test_instantWithdrawal_with_exchange_rate() public {
        vm.deal(user, 100 ether);

        vm.prank(user);
        stakingCore.stake{value: 89 ether}("");
        assertEq(stakingCore.getTotalProtocolHype(), 100 ether);
    }

    /**
     * @dev Tests instant withdrawal rate limiting
     * This test verifies that the bucket rate limiter correctly prevents
     * withdrawals that exceed the configured capacity
     */
    // function test_instantWithdrawalRateLimit() public {
    //     // Setup: Give user enough beHYPE for multiple withdrawals
    //     _mintTokens(user, 20 ether);
        
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 20 ether);
        
    //     // First withdrawal should succeed
    //     withdrawManager.withdraw(5 ether, true);
        
    //     // Second withdrawal should also succeed (within bucket capacity)
    //     withdrawManager.withdraw(5 ether, true);
        
    //     // Third withdrawal should fail due to rate limiting
    //     vm.expectRevert("BucketRateLimiter: rate limit exceeded");
    //     withdrawManager.withdraw(5 ether, true);
    //     vm.stopPrank();
    // }

    // /**
    //  * @dev Tests instant withdrawal low watermark check
    //  * This test verifies that instant withdrawals are blocked when
    //  * the protocol's liquid HYPE falls below the low watermark
    //  */
    // function test_instantWithdrawalLowWatermark() public {
    //     // Setup: Give user some beHYPE tokens
    //     _mintTokens(user, 5 ether);
        
    //     // Mock the staking core to have low liquid HYPE
    //     vm.mockCall(
    //         address(stakingCore),
    //         abi.encodeWithSelector(stakingCore.getTotalProtocolHype.selector),
    //         abi.encode(1 ether) // Very low total protocol HYPE
    //     );
        
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 5 ether);
        
    //     // Instant withdrawal should fail due to low watermark
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.InsufficientHYPELiquidity.selector));
    //     withdrawManager.withdraw(5 ether, true);
    //     vm.stopPrank();
    // }

    // /* ========== QUEUED WITHDRAWAL TESTS ========== */

    // /**
    //  * @dev Tests queued withdrawal lifecycle
    //  * This test verifies the complete flow: queue withdrawal, finalize, claim
    //  */
    // function test_queuedWithdrawalLifecycle() public {
    //     // Setup: Give user some beHYPE tokens
    //     _mintTokens(user, 3 ether);
        
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 3 ether);
        
    //     // Queue withdrawal
    //     uint256 withdrawalId = withdrawManager.withdraw(3 ether, false);
    //     assertEq(withdrawalId, 1);
    //     vm.stopPrank();
        
    //     // Verify withdrawal is queued
    //     assertEq(withdrawManager.getPendingWithdrawalsCount(), 1);
    //     assertFalse(withdrawManager.canClaimWithdrawal(withdrawalId));
        
    //     // Finalize withdrawal
    //     vm.prank(admin);
    //     withdrawManager.finalizeWithdrawals(1);
        
    //     // Verify withdrawal can now be claimed
    //     assertTrue(withdrawManager.canClaimWithdrawal(withdrawalId));
        
    //     // Claim withdrawal
    //     uint256 balanceBefore = address(user).balance;
    //     vm.prank(user);
    //     withdrawManager.claimWithdrawal(withdrawalId);
        
    //     // Verify user received HYPE
    //     assertGt(address(user).balance, balanceBefore);
    // }

    // /**
    //  * @dev Tests multiple queued withdrawals
    //  * This test verifies that multiple users can queue withdrawals
    //  * and they are processed in the correct order
    //  */
    // function test_multipleQueuedWithdrawals() public {
    //     // Setup: Give both users beHYPE tokens
    //     _mintTokens(user, 2 ether);
    //     _mintTokens(user2, 4 ether);
        
    //     // User 1 queues withdrawal
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 2 ether);
    //     uint256 withdrawalId1 = withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
        
    //     // User 2 queues withdrawal
    //     vm.startPrank(user2);
    //     beHYPE.approve(address(withdrawManager), 4 ether);
    //     uint256 withdrawalId2 = withdrawManager.withdraw(4 ether, false);
    //     vm.stopPrank();
        
    //     // Verify both withdrawals are queued
    //     assertEq(withdrawManager.getPendingWithdrawalsCount(), 2);
    //     assertEq(withdrawalId1, 1);
    //     assertEq(withdrawalId2, 2);
        
    //     // Finalize both withdrawals
    //     vm.prank(admin);
    //     withdrawManager.finalizeWithdrawals(2);
        
    //     // Both should now be claimable
    //     assertTrue(withdrawManager.canClaimWithdrawal(1));
    //     assertTrue(withdrawManager.canClaimWithdrawal(2));
    // }

    // /* ========== ADMIN FUNCTION TESTS ========== */

    // /**
    //  * @dev Tests admin finalization of withdrawals
    //  * This test verifies that only authorized admins can finalize withdrawals
    //  */
    // function test_adminFinalizeWithdrawals() public {
    //     // Setup: Queue a withdrawal
    //     _mintTokens(user, 2 ether);
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 2 ether);
    //     withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
        
    //     // Non-admin cannot finalize
    //     vm.prank(user);
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.NotAuthorized.selector));
    //     withdrawManager.finalizeWithdrawals(1);
        
    //     // Admin can finalize
    //     vm.prank(admin);
    //     withdrawManager.finalizeWithdrawals(1);
        
    //     // Verify withdrawal is now claimable
    //     assertTrue(withdrawManager.canClaimWithdrawal(1));
    // }

    // /**
    //  * @dev Tests admin claim withdrawals functionality
    //  * This test verifies that guardians can claim withdrawals on behalf of users
    //  */
    // function test_adminClaimWithdrawals() public {
    //     // Setup: Queue and finalize a withdrawal
    //     _mintTokens(user, 2 ether);
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 2 ether);
    //     uint256 withdrawalId = withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
        
    //     vm.prank(admin);
    //     withdrawManager.finalizeWithdrawals(1);
        
    //     // Guardian claims withdrawal for user
    //     uint256[] memory indexes = new uint256[](1);
    //     indexes[0] = 1;
        
    //     vm.prank(admin);
    //     withdrawManager.adminClaimWithdrawals(indexes);
        
    //     // Verify withdrawal is marked as claimed
    //     assertFalse(withdrawManager.canClaimWithdrawal(1));
    // }

    // /**
    //  * @dev Tests pause/unpause functionality
    //  * This test verifies that withdrawals can be paused and unpaused by authorized roles
    //  */
    // function test_pauseUnpauseWithdrawals() public {
    //     // Setup: Give user some beHYPE tokens
    //     _mintTokens(user, 2 ether);
        
    //     // Pause withdrawals
    //     vm.prank(admin);
    //     withdrawManager.pauseWithdrawals();
        
    //     // Verify withdrawals are paused
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 2 ether);
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.WithdrawalsPaused.selector));
    //     withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
        
    //     // Unpause withdrawals
    //     vm.prank(admin);
    //     withdrawManager.unpauseWithdrawals();
        
    //     // Verify withdrawals work again
    //     vm.startPrank(user);
    //     withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
    // }

    // /* ========== CONFIGURATION TESTS ========== */

    // /**
    //  * @dev Tests instant withdrawal fee configuration
    //  * This test verifies that the instant withdrawal fee can be updated by guardians
    //  */
    // function test_setInstantWithdrawalFee() public {
    //     uint16 newFee = 50; // 0.5%
        
    //     // Non-guardian cannot set fee
    //     vm.prank(user);
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.NotAuthorized.selector));
    //     withdrawManager.setInstantWithdrawalFeeInBps(newFee);
        
    //     // Guardian can set fee
    //     vm.prank(admin);
    //     withdrawManager.setInstantWithdrawalFeeInBps(newFee);
        
    //     // Verify fee was updated
    //     assertEq(withdrawManager.instantWithdrawalFeeInBps(), newFee);
    // }

    // /**
    //  * @dev Tests rate limiter configuration
    //  * This test verifies that admins can configure the bucket rate limiter parameters
    //  */
    // function test_setRateLimiterConfig() public {
    //     uint256 newCapacity = 10000 ether;
    //     uint256 newRefillRate = 100 ether;
        
    //     // Non-admin cannot set capacity
    //     vm.prank(user);
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.NotAuthorized.selector));
    //     withdrawManager.setInstantWithdrawalCapacity(newCapacity);
        
    //     // Admin can set capacity
    //     vm.prank(admin);
    //     withdrawManager.setInstantWithdrawalCapacity(newCapacity);
        
    //     // Admin can set refill rate
    //     vm.prank(admin);
    //     withdrawManager.setInstantWithdrawalRefillRatePerSecond(newRefillRate);
        
    //     // Verify configuration allows larger withdrawals
    //     _mintTokens(user, 1000 ether);
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 1000 ether);
        
    //     // Should now be able to withdraw more due to increased capacity
    //     withdrawManager.withdraw(1000 ether, true);
    //     vm.stopPrank();
    // }

    // /* ========== EDGE CASE TESTS ========== */

    // /**
    //  * @dev Tests withdrawal amount validation
    //  * This test verifies that withdrawals are rejected for amounts outside valid ranges
    //  */
    // function test_withdrawalAmountValidation() public {
    //     // Test minimum amount
    //     _mintTokens(user, 1 ether);
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 1 ether);
        
    //     // Should fail for amount below minimum
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.InvalidAmount.selector));
    //     withdrawManager.withdraw(0.05 ether, false);
        
    //     // Should fail for amount above maximum
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.InvalidAmount.selector));
    //     withdrawManager.withdraw(200 ether, false);
    //     vm.stopPrank();
    // }

    // /**
    //  * @dev Tests insufficient balance scenarios
    //  * This test verifies that withdrawals are rejected when users don't have enough tokens
    //  */
    // function test_insufficientBalance() public {
    //     // User has no beHYPE tokens
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 1 ether);
        
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.InsufficientBeHYPEBalance.selector));
    //     withdrawManager.withdraw(1 ether, false);
    //     vm.stopPrank();
    // }

    // /**
    //  * @dev Tests withdrawal finalization order
    //  * This test verifies that withdrawals can only be finalized in forward order
    //  */
    // function test_finalizationOrder() public {
    //     // Setup: Queue multiple withdrawals
    //     _mintTokens(user, 2 ether);
    //     _mintTokens(user2, 2 ether);
        
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 2 ether);
    //     withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
        
    //     vm.startPrank(user2);
    //     beHYPE.approve(address(withdrawManager), 2 ether);
    //     withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
        
    //     // Finalize second withdrawal first (should fail)
    //     vm.prank(admin);
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.CanOnlyFinalizeForward.selector));
    //     withdrawManager.finalizeWithdrawals(2);
        
    //     // Finalize first withdrawal (should succeed)
    //     vm.prank(admin);
    //     withdrawManager.finalizeWithdrawals(1);
    // }

    // /**
    //  * @dev Tests double claim prevention
    //  * This test verifies that withdrawals cannot be claimed multiple times
    //  */
    // function test_doubleClaimPrevention() public {
    //     // Setup: Queue and finalize a withdrawal
    //     _mintTokens(user, 2 ether);
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 2 ether);
    //     uint256 withdrawalId = withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
        
    //     vm.prank(admin);
    //     withdrawManager.finalizeWithdrawals(1);
        
    //     // Claim withdrawal
    //     vm.prank(user);
    //     withdrawManager.claimWithdrawal(withdrawalId);
        
    //     // Try to claim again (should fail)
    //     vm.prank(user);
    //     vm.expectRevert(abi.encodeWithSelector(IWithdrawManager.AlreadyClaimed.selector));
    //     withdrawManager.claimWithdrawal(withdrawalId);
    // }

    // /* ========== VIEW FUNCTION TESTS ========== */

    // /**
    //  * @dev Tests view functions for withdrawal status
    //  * This test verifies that all view functions return correct information
    //  */
    // function test_viewFunctions() public {
    //     // Setup: Queue a withdrawal
    //     _mintTokens(user, 2 ether);
    //     vm.startPrank(user);
    //     beHYPE.approve(address(withdrawManager), 2 ether);
    //     uint256 withdrawalId = withdrawManager.withdraw(2 ether, false);
    //     vm.stopPrank();
        
    //     // Test getPendingWithdrawalsCount
    //     assertEq(withdrawManager.getPendingWithdrawalsCount(), 1);
        
    //     // Test canClaimWithdrawal (should be false before finalization)
    //     assertFalse(withdrawManager.canClaimWithdrawal(withdrawalId));
        
    //     // Test getUserUnclaimedWithdrawals
    //     uint256[] memory unclaimed = withdrawManager.getUserUnclaimedWithdrawals(user);
    //     assertEq(unclaimed.length, 1);
    //     assertEq(unclaimed[0], withdrawalId);
        
    //     // Finalize withdrawal
    //     vm.prank(admin);
    //     withdrawManager.finalizeWithdrawals(1);
        
    //     // Test canClaimWithdrawal (should be true after finalization)
    //     assertTrue(withdrawManager.canClaimWithdrawal(withdrawalId));
        
    //     // Test totalInstantWithdrawableAmount
    //     uint256 instantAmount = withdrawManager.totalInstantWithdrawableAmount();
    //     assertGt(instantAmount, 0);
    // }
}
