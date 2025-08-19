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

contract WithdrawManager is
    Initializable,
    UUPSUpgradeable,
    IWithdrawManager,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */
    
    IBeHYPEToken public beHypeToken;
    IStakingCore public stakingCore;
    IRoleRegistry public roleRegistry;
    
    uint256 public totalQueuedWithdrawals;
    uint256 public lastFinalizedIndex;
    
    bool public withdrawalsPaused;
    
    WithdrawalEntry[] public withdrawalQueue;
    mapping(address => uint256[]) public userWithdrawals;

    uint256 public minWithdrawalAmount;
    uint256 public maxWithdrawalAmount;
    
    /* ========== CONSTANTS ========== */
    
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        uint256 _minStakeAmount,
        uint256 _maxStakeAmount,
        address _roleRegistry,
        address _beHypeToken,
        address _stakingCore
    ) public initializer {
        
        __ReentrancyGuard_init();

        minWithdrawalAmount = _minStakeAmount;
        maxWithdrawalAmount = _maxStakeAmount;
        
        roleRegistry = IRoleRegistry(_roleRegistry);
        beHypeToken = IBeHYPEToken(_beHypeToken);
        stakingCore = IStakingCore(_stakingCore);
    }
    
    /* ========== MAIN FUNCTIONS ========== */
    
    function queueWithdrawal(
        uint256 beHypeAmount
    ) external nonReentrant returns (uint256 withdrawalId) {
        if (withdrawalsPaused) revert WithdrawalsPaused();
        if (beHypeAmount < minWithdrawalAmount) revert InvalidAmount();
        if (beHypeAmount > maxWithdrawalAmount) revert InvalidAmount();
        if (beHypeToken.balanceOf(msg.sender) < beHypeAmount) revert InsufficientBeHYPEBalance();
        
        withdrawalId = withdrawalQueue.length;
        
        uint256 hypeAmount = stakingCore.kHYPEToHYPE(beHypeAmount);
        if (hypeAmount == 0) revert InvalidHYPEAmount();
        
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
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        if (index >= withdrawalQueue.length) revert IndexOutOfBounds();
        if (index < lastFinalizedIndex) revert CanOnlyFinalizeForward();
        
        lastFinalizedIndex = index;
        
        emit WithdrawalsBatchFinalized(index);
    }
    
    function claimWithdrawal(uint256 withdrawalId) external nonReentrant {
        if (withdrawalId >= lastFinalizedIndex) revert WithdrawalNotFinalized();
        if (withdrawalId >= withdrawalQueue.length) revert InvalidWithdrawalID();
        
        WithdrawalEntry storage entry = withdrawalQueue[withdrawalId];
        if (entry.claimed) revert AlreadyClaimed();
        
        uint256 hypeAmount = entry.hypeAmount;
        uint256 beHypeAmount = entry.beHypeAmount;
        
        entry.claimed = true;
        
        totalQueuedWithdrawals -= entry.hypeAmount;
        
        beHypeToken.burn(address(this), beHypeAmount);
        
        (bool success, ) = payable(entry.user).call{value: hypeAmount}("");
        if (!success) revert TransferFailed();
        
        emit WithdrawalClaimed(entry.user, withdrawalId, hypeAmount);
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    function getPendingWithdrawalsCount() external view returns (uint256) {
        return withdrawalQueue.length - lastFinalizedIndex;
    }
    
    function canClaimWithdrawal(uint256 withdrawalId) external view returns (bool) {
        if (withdrawalId >= withdrawalQueue.length) return false;
        if (withdrawalId >= lastFinalizedIndex) return false;
        
        WithdrawalEntry storage entry = withdrawalQueue[withdrawalId];
        return !entry.claimed;
    }
    
    function getUserUnclaimedWithdrawals(address user) external view returns (uint256[] memory) {
        uint256[] memory unclaimedWithdrawals = new uint256[](userWithdrawals[user].length);
        
        for (uint256 i = 0; i < userWithdrawals[user].length; i++) {
            WithdrawalEntry storage entry = withdrawalQueue[userWithdrawals[user][i]];
            if (!entry.claimed && entry.hypeAmount > 0) {
                unclaimedWithdrawals[i] = userWithdrawals[user][i];
            }
        }
        return unclaimedWithdrawals;
    }
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    function pauseWithdrawals() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_PAUSER(), msg.sender)) revert NotAuthorized();
        withdrawalsPaused = true;
        // emit WithdrawalsPaused();
    }
    
    function unpauseWithdrawals() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_UNPAUSER(), msg.sender)) revert NotAuthorized();
        withdrawalsPaused = false;
        // emit WithdrawalsUnpaused();  
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
    
    receive() external payable {}
}
