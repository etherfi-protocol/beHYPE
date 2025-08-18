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
    
    IBeHYPEToken public beHypeToken;
    IStakingCore public stakingCore;
    IRoleRegistry public roleRegistry;
    
    uint256 public totalQueuedWithdrawals;
    uint256 public lastFinalizedIndex;
    
    bool public withdrawalsPaused;
    
    WithdrawalEntry[] public withdrawalQueue;
    
    // Mapping from user address to array of withdrawal IDs
    mapping(address => uint256[]) public userWithdrawals;
    
    /* ========== CONSTRUCTOR ========== */
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /* ========== INITIALIZATION ========== */
    
    function initialize(
        address _roleRegistry,
        address _beHypeToken,
        address _stakingCore
    ) public initializer {
        require(_roleRegistry != address(0), "Invalid role registry");
        require(_beHypeToken != address(0), "Invalid beHYPE token");
        require(_stakingCore != address(0), "Invalid staking core");
        
        __ReentrancyGuard_init();
        
        roleRegistry = IRoleRegistry(_roleRegistry);
        beHypeToken = IBeHYPEToken(_beHypeToken);
        stakingCore = IStakingCore(_stakingCore);
    }
    
    /* ========== MAIN FUNCTIONS ========== */
    
    function queueWithdrawal(
        uint256 beHypeAmount
    ) external nonReentrant returns (uint256 withdrawalId) {
        require(!withdrawalsPaused, "Withdrawals are paused");
        require(beHypeAmount > 0, "Invalid amount");
        require(beHypeToken.balanceOf(msg.sender) >= beHypeAmount, "Insufficient beHYPE balance");
        
        withdrawalId = withdrawalQueue.length;
        
        uint256 hypeAmount = stakingCore.kHYPEToHYPE(beHypeAmount);
        require(hypeAmount > 0, "Invalid HYPE amount");
        
        beHypeToken.transferFrom(msg.sender, address(this), beHypeAmount);
        
        withdrawalQueue.push(WithdrawalEntry({
            user: msg.sender,
            beHypeAmount: beHypeAmount,
            hypeAmount: hypeAmount,
            claimed: false
        }));
        
        userWithdrawals[msg.sender].push(withdrawalId);
        
        totalQueuedWithdrawals += hypeAmount;
        
        emit WithdrawalQueued(msg.sender, withdrawalId, beHypeAmount, hypeAmount, withdrawalId);
    }
    
    function finalizeWithdrawals(uint256 index) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_GOVERNOR(), msg.sender)) revert("Not authorized");
        require(index < withdrawalQueue.length, "Index out of bounds");
        require(index >= lastFinalizedIndex, "Can only finalize forward");
        
        lastFinalizedIndex = index;
        
        emit WithdrawalsBatchFinalized(index);
    }
    
    function claimWithdrawal(uint256 withdrawalId) external nonReentrant {
        require(withdrawalId < lastFinalizedIndex, "Withdrawal not finalized");
        require(withdrawalId < withdrawalQueue.length, "Invalid withdrawal ID");
        
        WithdrawalEntry storage entry = withdrawalQueue[withdrawalId];
        require(entry.user == msg.sender, "Not your withdrawal");
        require(!entry.claimed, "Already claimed");
        
        uint256 hypeAmount = entry.hypeAmount;
        uint256 beHypeAmount = entry.beHypeAmount;
        
        entry.claimed = true;
        
        totalQueuedWithdrawals -= entry.hypeAmount;
        
        beHypeToken.burn(address(this), beHypeAmount);
        
    
        (bool success, ) = payable(msg.sender).call{value: hypeAmount}("");
        require(success, "Transfer failed");
        
        emit WithdrawalClaimed(msg.sender, withdrawalId, hypeAmount);
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    function getWithdrawalQueueLength() external view returns (uint256) {
        return withdrawalQueue.length;
    }
    
    function getWithdrawalEntry(uint256 index) external view returns (WithdrawalEntry memory) {
        require(index < withdrawalQueue.length, "Index out of bounds");
        return withdrawalQueue[index];
    }
    
    function getPendingWithdrawalsCount() external view returns (uint256) {
        return withdrawalQueue.length - lastFinalizedIndex;
    }
    
    function canClaimWithdrawal(uint256 withdrawalId) external view returns (bool) {
        if (withdrawalId >= withdrawalQueue.length) return false;
        if (withdrawalId >= lastFinalizedIndex) return false;
        
        WithdrawalEntry storage entry = withdrawalQueue[withdrawalId];
        return !entry.claimed && entry.hypeAmount > 0;
    }
    
    function getUserWithdrawals(address user) external view returns (uint256[] memory) {
        return userWithdrawals[user];
    }
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    function pauseWithdrawals() external {
        if (!roleRegistry.hasRole(MANAGER_ROLE, msg.sender)) revert("Not authorized");
        withdrawalsPaused = true;
        emit WithdrawalsPaused(msg.sender);
    }
    
    function unpauseWithdrawals() external {
        if (!roleRegistry.hasRole(MANAGER_ROLE, msg.sender)) revert("Not authorized");
        withdrawalsPaused = false;
        emit WithdrawalsUnpaused(msg.sender);
    }
    
    function cancelWithdrawal(
        address user,
        uint256 withdrawalId
    ) external {
        if (!roleRegistry.hasRole(MANAGER_ROLE, msg.sender)) revert("Not authorized");
        require(withdrawalId < withdrawalQueue.length, "Invalid withdrawal ID");
        
        WithdrawalEntry storage entry = withdrawalQueue[withdrawalId];
        require(entry.user == user, "User mismatch");
        require(!entry.claimed, "Already claimed or cancelled");
        
        uint256 hypeAmount = entry.hypeAmount;
        uint256 beHypeAmount = entry.beHypeAmount;
        
        require(beHypeToken.balanceOf(address(this)) >= beHypeAmount, "Insufficient beHYPE balance");
        
        // Mark as cancelled
        entry.claimed = true;
        
        totalQueuedWithdrawals -= hypeAmount;
        
        beHypeToken.transfer(user, beHypeAmount);
        
        emit WithdrawalCancelled(user, withdrawalId, beHypeAmount);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
    
    receive() external payable {}
}
