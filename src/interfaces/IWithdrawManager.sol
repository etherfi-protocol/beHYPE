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
    
    /* ========== CONSTANTS ========== */
    
    function MANAGER_ROLE() external view returns (bytes32);
    function OPERATOR_ROLE() external view returns (bytes32);
    
    /* ========== STATE VARIABLES ========== */
    
    // These are public state variables that automatically generate getter functions
    // beHypeToken() external view returns (IBeHYPEToken);
    // stakingCore() external view returns (IStakingCore);
    // roleRegistry() external view returns (IRoleRegistry);
    // totalQueuedWithdrawals() external view returns (uint256);
    // totalClaimed() external view returns (uint256);
    // lastFinalizedIndex() external view returns (uint256);
    // withdrawalsPaused() external view returns (bool);
    
    /* ========== MAIN FUNCTIONS ========== */
    
    /**
     * @notice Queue a withdrawal request
     * @param beHypeAmount Amount of beHYPE tokens to withdraw
     * @return withdrawalId The ID of the withdrawal request
     */
    function queueWithdrawal(uint256 beHypeAmount) external returns (uint256 withdrawalId);
    
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
     * @notice Get the total length of the withdrawal queue
     * @return uint256 Total number of withdrawals in the queue
     */
    function getWithdrawalQueueLength() external view returns (uint256);
    
    /**
     * @notice Get a specific withdrawal entry from the queue
     * @param index Index in the withdrawal queue
     * @return WithdrawalEntry The withdrawal entry at the specified index
     */
    function getWithdrawalEntry(uint256 index) external view returns (WithdrawalEntry memory);
    
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
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    /**
     * @notice Pause withdrawals
     */
    function pauseWithdrawals() external;
    
    /**
     * @notice Unpause withdrawals
     */
    function unpauseWithdrawals() external;
    
    /**
     * @notice Cancel a withdrawal request (manager only)
     * @param user Address of the user
     * @param withdrawalId ID of the withdrawal to cancel
     */
    function cancelWithdrawal(address user, uint256 withdrawalId) external;
    
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
    
    event WithdrawalsPaused(address by);
    event WithdrawalsUnpaused(address by);
}
