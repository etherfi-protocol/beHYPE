// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRoleRegistry} from "./IRoleRegistry.sol";
import {IBeHYPEToken} from "./IBeHYPE.sol";
import {IStakingCore} from "./IStakingCore.sol";

/**
 * @title IWithdrawManager
 * @notice Interface for the WithdrawalQueue contract
 * @dev Defines all public and external functions for withdrawal management
 */
interface IWithdrawManager {

    /* ========== STRUCTS ========== */
    
    struct WithdrawalEntry {
        address user;              // Address of the user
        uint256 beHypeAmount;      // Amount of beHYPE tokens locked
        uint256 hypeAmount;        // Amount of HYPE to be withdrawn
        bool claimed;              // Whether the withdrawal has been claimed
    }

    /* ========== ERRORS ========== */

    error WithdrawalsPaused();
    error InvalidAmount();
    error InsufficientBeHYPEBalance();
    error InvalidHYPEAmount();
    error NotAuthorized();
    error IndexOutOfBounds();
    error CanOnlyFinalizeForward();
    error WithdrawalNotFinalized();
    error InvalidWithdrawalID();
    error AlreadyClaimed();
    error TransferFailed();
    error WithdrawalsNotPaused();
    error InsufficientHYPELiquidity();
    error InvalidInstantWithdrawalFee();

    /* ========== EVENTS ========== */
    
    event WithdrawalQueued(
        address indexed user,
        uint256 indexed withdrawalId,
        uint256 beHypeAmount,
        uint256 hypeAmount,
        uint256 queueIndex
    );
    
    event WithdrawalsBatchFinalized(uint256 upToIndex);
    
    event WithdrawalClaimed(
        address indexed user,
        uint256 indexed withdrawalId,
        uint256 hypeAmount
    );
    
    event WithdrawalCancelled(
        address indexed user,
        uint256 indexed withdrawalId,
        uint256 beHypeAmount
    );
    
    event WithdrawalInvalidated(
        address indexed user,
        uint256 indexed withdrawalId,
        uint256 beHypeAmount
    );
    
    event InstantWithdrawal(
        address indexed user,
        uint256 beHypeAmountWithdrawn,
        uint256 hypeAmountReceived,
        uint256 beHypeInstantWithdrawalFee
    );
    
    event InstantWithdrawalFeeInBpsUpdated(uint256 instantWithdrawalFeeInBps);
    
    /* ========== MAIN FUNCTIONS ========== */
    
    /**
     * @notice Queue a withdrawal request
     * @param beHypeAmount Amount of beHYPE tokens to withdraw
     * @param instant Whether to withdraw instantly for a fee or queue
     * @return withdrawalId The ID of the withdrawal request
     */
    function withdraw(uint256 beHypeAmount, bool instant) external returns (uint256 withdrawalId);
    
    /**
     * @notice Finalize withdrawals up to a specific index (protocol governor only)
     * @param index Index up to which withdrawals should be finalized
     */
    function finalizeWithdrawals(uint256 index) external;
    
    /**
     * @notice Claim finalized withdrawal
     * @param withdrawalId ID of the withdrawal to claim
     */
    function claimWithdrawal(uint256 withdrawalId) external;
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Get the count of pending (unfinalized) withdrawals
     * @return uint256 Number of pending withdrawals
     */
    function getPendingWithdrawalsCount() external view returns (uint256);
    
    /**
     * @notice Check if a withdrawal can be claimed
     * @param withdrawalId ID of the withdrawal to check
     * @return bool True if the withdrawal can be claimed
     */
    function canClaimWithdrawal(uint256 withdrawalId) external view returns (bool);
    
    /**
     * @notice Check if a withdrawal can be instant withdrawn
     * @param beHypeAmount Amount of beHYPE tokens to withdraw
     * @return bool True if the withdrawal can be instant withdrawn
     */
    function canInstantWithdraw(uint256 beHypeAmount) external view returns (bool);
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    /**
     * @notice Pause withdrawals
     */
    function pauseWithdrawals() external;
    
    /**
     * @notice Unpause withdrawals
     */
    function unpauseWithdrawals() external;
    
}
