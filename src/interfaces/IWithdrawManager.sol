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
    
    struct WithdrawalRequest {
        uint256 beHypeAmount;      // Amount of beHYPE tokens locked
        uint256 hypeAmount;        // Amount of HYPE to be withdrawn
        uint256 timestamp;         // Request timestamp
    }
    
    /* ========== CONSTANTS ========== */
    
    function MANAGER_ROLE() external view returns (bytes32);
    function OPERATOR_ROLE() external view returns (bytes32);
    
    /* ========== STATE VARIABLES ========== */
    
    // These are public state variables that automatically generate getter functions
    // beHypeToken() external view returns (IBeHYPEToken);
    // stakingCore() external view returns (IStakingCore);
    // roleRegistry() external view returns (IRoleRegistry);
    // withdrawalDelay() external view returns (uint256);
    // totalQueuedWithdrawals() external view returns (uint256);
    // totalClaimed() external view returns (uint256);
    // nextWithdrawalId(address user) external view returns (uint256);
    // withdrawalsPaused() external view returns (bool);
    
    /* ========== MAIN FUNCTIONS ========== */
    
    /**
     * @notice Queue a withdrawal request
     * @param beHypeAmount Amount of beHYPE tokens to withdraw
     * @return withdrawalId The ID of the withdrawal request
     */
    function queueWithdrawal(uint256 beHypeAmount) external returns (uint256 withdrawalId);
    
    /**
     * @notice Confirm a single withdrawal request
     * @param withdrawalId ID of the withdrawal to confirm
     */
    function confirmWithdrawal(uint256 withdrawalId) external;
    
    /**
     * @notice Confirm multiple withdrawal requests
     * @param withdrawalIds Array of withdrawal IDs to confirm
     */
    function batchConfirmWithdrawals(uint256[] calldata withdrawalIds) external;
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Get withdrawal request details
     * @param user Address of the user
     * @param withdrawalId ID of the withdrawal request
     * @return Withdrawal request details
     */
    function getWithdrawalRequest(
        address user,
        uint256 withdrawalId
    ) external view returns (WithdrawalRequest memory);
    
    /**
     * @notice Check if a withdrawal is ready to be confirmed
     * @param user Address of the user
     * @param withdrawalId ID of the withdrawal request
     * @return bool True if the withdrawal can be confirmed
     */
    function canConfirmWithdrawal(
        address user,
        uint256 withdrawalId
    ) external view returns (bool);
    
    /**
     * @notice Get the time remaining until a withdrawal can be confirmed
     * @param user Address of the user
     * @param withdrawalId ID of the withdrawal request
     * @return uint256 Time remaining in seconds, 0 if ready
     */
    function getWithdrawalTimeRemaining(
        address user,
        uint256 withdrawalId
    ) external view returns (uint256);
    
    /**
     * @notice Get current exchange ratio from staking core
     * @return uint256 Current exchange ratio
     */
    function getCurrentExchangeRatio() external view returns (uint256);
    
    /**
     * @notice Calculate HYPE amount for given beHYPE amount
     * @param beHypeAmount Amount of beHYPE tokens
     * @return uint256 Equivalent HYPE amount
     */
    function calculateHypeAmount(uint256 beHypeAmount) external view returns (uint256);
    
    /**
     * @notice Calculate beHYPE amount for given HYPE amount
     * @param hypeAmount Amount of HYPE tokens
     * @return uint256 Equivalent beHYPE amount
     */
    function calculateBeHypeAmount(uint256 hypeAmount) external view returns (uint256);
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    /**
     * @notice Set withdrawal delay period
     * @param newDelay New delay period in seconds
     */
    function setWithdrawalDelay(uint256 newDelay) external;
    
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
    
    /**
     * @notice Update the staking core address
     * @param newStakingCore New staking core address
     */
    function setStakingCore(address newStakingCore) external;
    
    /* ========== EVENTS ========== */
    
    event WithdrawalQueued(
        address indexed user,
        uint256 indexed withdrawalId,
        uint256 beHypeAmount,
        uint256 hypeAmount
    );
    
    event WithdrawalConfirmed(
        address indexed user,
        uint256 indexed withdrawalId,
        uint256 hypeAmount
    );
    
    event WithdrawalCancelled(
        address indexed user,
        uint256 indexed withdrawalId,
        uint256 beHypeAmount
    );
    
    event WithdrawalDelayUpdated(uint256 newDelay);
    event WithdrawalsPaused(address by);
    event WithdrawalsUnpaused(address by);
    event StakingCoreUpdated(address oldStakingCore, address newStakingCore);
}
