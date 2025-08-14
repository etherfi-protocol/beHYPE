// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRoleRegistry} from "./interfaces/IRoleRegistry.sol";
import {IBeHYPEToken} from "./interfaces/IBeHype.sol";
import {IStakingCore} from "./interfaces/IStakingCore.sol";
import {IWithdrawManager} from "./interfaces/IWithdrawManager.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title WithdrawalQueue
 * @notice Manages withdrawal requests with a time delay mechanism
 * @dev Implements upgradeable patterns with role-based access control via RoleRegistry
 * Integrates with beHYPE token and StakingCore for exchange rate calculations
 */
contract WithdrawalQueue is
    Initializable,
    UUPSUpgradeable,
    IWithdrawManager,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* ========== CONSTANTS ========== */
    
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /* ========== STATE VARIABLES ========== */
    
    // Core contracts
    IBeHYPEToken public beHypeToken;
    IStakingCore public stakingCore;
    IRoleRegistry public roleRegistry;
    
    // Withdrawal parameters
    uint256 public withdrawalDelay;
    
    // Global accounting
    uint256 public totalQueuedWithdrawals; // Total HYPE amount queued for withdrawal
    uint256 public totalClaimed; // Total HYPE amount claimed
    
    // User tracking
    mapping(address => uint256) public nextWithdrawalId;
    
    // Pause state
    bool public withdrawalsPaused;
    
    // Private storage
    mapping(address => mapping(uint256 => WithdrawalRequest)) private _withdrawalRequests;
    
    /* ========== CONSTRUCTOR ========== */
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /* ========== INITIALIZATION ========== */
    
    /**
     * @notice Initializes the WithdrawalQueue contract
     * @param _roleRegistry Address of the role registry contract
     * @param _beHypeToken Address of the beHYPE token contract
     * @param _stakingCore Address of the staking core contract
     * @param _withdrawalDelay Initial withdrawal delay in seconds
     */
    function initialize(
        address _roleRegistry,
        address _beHypeToken,
        address _stakingCore,
        uint256 _withdrawalDelay
    ) public initializer {
        require(_roleRegistry != address(0), "Invalid role registry");
        require(_beHypeToken != address(0), "Invalid beHYPE token");
        require(_stakingCore != address(0), "Invalid staking core");
        
        __ReentrancyGuard_init();
        
        roleRegistry = IRoleRegistry(_roleRegistry);
        beHypeToken = IBeHYPEToken(_beHypeToken);
        stakingCore = IStakingCore(_stakingCore);
        withdrawalDelay = _withdrawalDelay;
    }
    
    /* ========== MAIN FUNCTIONS ========== */
    
    /**
     * @notice Queue a withdrawal request
     * @param beHypeAmount Amount of beHYPE tokens to withdraw
     * @return withdrawalId The ID of the withdrawal request
     */
    function queueWithdrawal(
        uint256 beHypeAmount
    ) external nonReentrant returns (uint256 withdrawalId) {
        require(!withdrawalsPaused, "Withdrawals are paused");
        require(beHypeAmount > 0, "Invalid amount");
        require(beHypeToken.balanceOf(msg.sender) >= beHypeAmount, "Insufficient beHYPE balance");
        
        withdrawalId = nextWithdrawalId[msg.sender];
        
        // Calculate HYPE amount using current exchange ratio
        uint256 hypeAmount = stakingCore.kHYPEToHYPE(beHypeAmount);
        require(hypeAmount > 0, "Invalid HYPE amount");
        
        // // Lock beHYPE tokens
        // TODO: do we need safeTransfer?
        // beHypeToken.safeTransferFrom(msg.sender, address(this), beHypeAmount);
        beHypeToken.transferFrom(msg.sender, address(this), beHypeAmount);

        // Create withdrawal request
        _withdrawalRequests[msg.sender][withdrawalId] = WithdrawalRequest({
            beHypeAmount: beHypeAmount,
            hypeAmount: hypeAmount,
            timestamp: block.timestamp
        });
        
        nextWithdrawalId[msg.sender]++;
        totalQueuedWithdrawals += hypeAmount;
        
        emit WithdrawalQueued(msg.sender, withdrawalId, beHypeAmount, hypeAmount);
    }
    
    /**
     * @notice Confirm a single withdrawal request
     * @param withdrawalId ID of the withdrawal to confirm
     */
    function confirmWithdrawal(uint256 withdrawalId) external nonReentrant {
        uint256 amount = _processConfirmation(msg.sender, withdrawalId);
        require(amount > 0, "No valid withdrawal request");
        require(address(this).balance >= amount, "Insufficient contract balance");
        
        totalClaimed += amount;
        
        // Process withdrawal
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @notice Confirm multiple withdrawal requests
     * @param withdrawalIds Array of withdrawal IDs to confirm
     */
    function batchConfirmWithdrawals(uint256[] calldata withdrawalIds) external nonReentrant {
        uint256 totalAmount = 0;
        
        for (uint256 i = 0; i < withdrawalIds.length; i++) {
            totalAmount += _processConfirmation(msg.sender, withdrawalIds[i]);
        }
        
        if (totalAmount > 0) {
            require(address(this).balance >= totalAmount, "Insufficient contract balance");
            
            totalClaimed += totalAmount;
            
            // Process withdrawal
            (bool success, ) = payable(msg.sender).call{value: totalAmount}("");
            require(success, "Transfer failed");
        }
    }
    
    /* ========== INTERNAL FUNCTIONS ========== */
    
    /**
     * @dev Process a single withdrawal confirmation
     * @param user Address of the user
     * @param withdrawalId ID of the withdrawal
     * @return amount The amount processed, 0 if skipped
     */
    function _processConfirmation(address user, uint256 withdrawalId) internal returns (uint256) {
        WithdrawalRequest memory request = _withdrawalRequests[user][withdrawalId];
        
        // Skip if request doesn't exist or delay period not met
        if (request.hypeAmount == 0 || block.timestamp < request.timestamp + withdrawalDelay) {
            return 0;
        }
        
        uint256 hypeAmount = request.hypeAmount;
        uint256 beHypeAmount = request.beHypeAmount;
        
        // Check beHYPE token balance
        require(beHypeToken.balanceOf(address(this)) >= beHypeAmount, "Insufficient beHYPE balance");
        
        // Update state
        totalQueuedWithdrawals -= hypeAmount;
        delete _withdrawalRequests[user][withdrawalId];
        
        // Burn beHYPE tokens
        beHypeToken.burn(address(this), beHypeAmount);
        
        emit WithdrawalConfirmed(user, withdrawalId, hypeAmount);
        
        return hypeAmount;
    }
    
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
    ) external view returns (WithdrawalRequest memory) {
        return _withdrawalRequests[user][withdrawalId];
    }
    
    /**
     * @notice Check if a withdrawal is ready to be confirmed
     * @param user Address of the user
     * @param withdrawalId ID of the withdrawal request
     * @return bool True if the withdrawal can be confirmed
     */
    function canConfirmWithdrawal(
        address user,
        uint256 withdrawalId
    ) external view returns (bool) {
        WithdrawalRequest memory request = _withdrawalRequests[user][withdrawalId];
        return request.hypeAmount > 0 && 
               block.timestamp >= request.timestamp + withdrawalDelay &&
               address(this).balance >= request.hypeAmount;
    }
    
    /**
     * @notice Get the time remaining until a withdrawal can be confirmed
     * @param user Address of the user
     * @param withdrawalId ID of the withdrawal request
     * @return uint256 Time remaining in seconds, 0 if ready
     */
    function getWithdrawalTimeRemaining(
        address user,
        uint256 withdrawalId
    ) external view returns (uint256) {
        WithdrawalRequest memory request = _withdrawalRequests[user][withdrawalId];
        if (request.hypeAmount == 0) return 0;
        
        uint256 readyTime = request.timestamp + withdrawalDelay;
        if (block.timestamp >= readyTime) return 0;
        
        return readyTime - block.timestamp;
    }
    
    /**
     * @notice Get current exchange ratio from staking core
     * @return uint256 Current exchange ratio
     */
    function getCurrentExchangeRatio() external view returns (uint256) {
        return stakingCore.exchangeRatio();
    }
    
    /**
     * @notice Calculate HYPE amount for given beHYPE amount
     * @param beHypeAmount Amount of beHYPE tokens
     * @return uint256 Equivalent HYPE amount
     */
    function calculateHypeAmount(uint256 beHypeAmount) external view returns (uint256) {
        return stakingCore.kHYPEToHYPE(beHypeAmount);
    }
    
    /**
     * @notice Calculate beHYPE amount for given HYPE amount
     * @param hypeAmount Amount of HYPE tokens
     * @return uint256 Equivalent beHYPE amount
     */
    function calculateBeHypeAmount(uint256 hypeAmount) external view returns (uint256) {
        return stakingCore.HYPEToKHYPE(hypeAmount);
    }
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    /**
     * @notice Set withdrawal delay period
     * @param newDelay New delay period in seconds
     */
    function setWithdrawalDelay(uint256 newDelay) external {
        if (!roleRegistry.hasRole(MANAGER_ROLE, msg.sender)) revert("Not authorized");
        withdrawalDelay = newDelay;
        emit WithdrawalDelayUpdated(newDelay);
    }
    
    /**
     * @notice Pause withdrawals
     */
    function pauseWithdrawals() external {
        if (!roleRegistry.hasRole(MANAGER_ROLE, msg.sender)) revert("Not authorized");
        withdrawalsPaused = true;
        emit WithdrawalsPaused(msg.sender);
    }
    
    /**
     * @notice Unpause withdrawals
     */
    function unpauseWithdrawals() external {
        if (!roleRegistry.hasRole(MANAGER_ROLE, msg.sender)) revert("Not authorized");
        withdrawalsPaused = false;
        emit WithdrawalsUnpaused(msg.sender);
    }
    
    /**
     * @notice Cancel a withdrawal request (manager only)
     * @param user Address of the user
     * @param withdrawalId ID of the withdrawal to cancel
     */
    function cancelWithdrawal(
        address user,
        uint256 withdrawalId
    ) external {
        if (!roleRegistry.hasRole(MANAGER_ROLE, msg.sender)) revert("Not authorized");
        WithdrawalRequest storage request = _withdrawalRequests[user][withdrawalId];
        require(request.hypeAmount > 0, "No such withdrawal request");
        
        uint256 hypeAmount = request.hypeAmount;
        uint256 beHypeAmount = request.beHypeAmount;
        
        // Check beHYPE token balance
        require(beHypeToken.balanceOf(address(this)) >= beHypeAmount, "Insufficient beHYPE balance");
        
        // Clear the withdrawal request
        delete _withdrawalRequests[user][withdrawalId];
        totalQueuedWithdrawals -= hypeAmount;
        
        // Return beHYPE tokens to user
        // beHypeToken.safeTransfer(user, beHypeAmount);
        beHypeToken.transfer(user, beHypeAmount);
        
        emit WithdrawalCancelled(user, withdrawalId, beHypeAmount);
    }
    
    /**
     * @notice Update the staking core address
     * @param newStakingCore New staking core address
     */
    function setStakingCore(address newStakingCore) external {
        if (!roleRegistry.hasRole(MANAGER_ROLE, msg.sender)) revert("Not authorized");
        require(newStakingCore != address(0), "Invalid staking core");
        
        address oldStakingCore = address(stakingCore);
        stakingCore = IStakingCore(newStakingCore);
        
        emit StakingCoreUpdated(oldStakingCore, newStakingCore);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
    
    /**
     * @notice Receive function to accept ETH
     */
    receive() external payable {}
}
