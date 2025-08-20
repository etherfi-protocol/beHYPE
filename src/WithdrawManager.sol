// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
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
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */
    
    IBeHYPEToken public beHypeToken;
    IStakingCore public stakingCore;
    IRoleRegistry public roleRegistry;
    
    uint256 public totalQueuedWithdrawals;
    uint256 public lastFinalizedIndex;
    
    WithdrawalEntry[] public withdrawalQueue;
    mapping(address => uint256[]) public userWithdrawals;

    uint256 public minWithdrawalAmount;
    uint256 public maxWithdrawalAmount;

    uint256 public lowWatermarkInBpsOfTvl;

    /* ========== CONSTANTS ========== */

    uint256 public constant BUCKET_UNIT_SCALE = 1e12;
    uint256 public constant BASIS_POINT_SCALE = 1e4;
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        uint256 _minStakeAmount,
        uint256 _maxStakeAmount,
        uint256 _lowWatermarkInBpsOfTvl,
        address _roleRegistry,
        address _beHypeToken,
        address _stakingCore
    ) public initializer {
        
        __ReentrancyGuard_init();

        minWithdrawalAmount = _minStakeAmount;
        maxWithdrawalAmount = _maxStakeAmount;
        lowWatermarkInBpsOfTvl = _lowWatermarkInBpsOfTvl;
        
        roleRegistry = IRoleRegistry(_roleRegistry);
        beHypeToken = IBeHYPEToken(_beHypeToken);
        stakingCore = IStakingCore(_stakingCore);
    }
    
    /* ========== MAIN FUNCTIONS ========== */
    
    function withdraw(
        uint256 beHypeAmount, bool instant
    ) external nonReentrant returns (uint256 withdrawalId) {
        if (paused()) revert WithdrawalsPaused();
        if (beHypeAmount < minWithdrawalAmount) revert InvalidAmount();
        if (beHypeAmount > maxWithdrawalAmount) revert InvalidAmount();
        if (beHypeToken.balanceOf(msg.sender) < beHypeAmount) revert InsufficientBeHYPEBalance();

        if (instant) {


        } else {

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
        
    }
    
    function claimWithdrawal(uint256 withdrawalId) external nonReentrant {
        if (paused()) revert WithdrawalsPaused();
        if (withdrawalId >= lastFinalizedIndex) revert WithdrawalNotFinalized();
        if (withdrawalId >= withdrawalQueue.length) revert InvalidWithdrawalID();
        
        _finalizeWithdrawal(withdrawalId);
    }

    function instantWithdrawal(uint256 beHypeAmount) external nonReentrant {
        if (paused()) revert WithdrawalsPaused();
        if (beHypeAmount < minWithdrawalAmount) revert InvalidAmount();
        if (beHypeAmount > maxWithdrawalAmount) revert InvalidAmount();
        if (beHypeToken.balanceOf(msg.sender) < beHypeAmount) revert InsufficientBeHYPEBalance();
        
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function finalizeWithdrawals(uint256 index) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        if (index >= withdrawalQueue.length) revert IndexOutOfBounds();
        if (index < lastFinalizedIndex) revert CanOnlyFinalizeForward();
        
        lastFinalizedIndex = index;
        
        emit WithdrawalsBatchFinalized(index);
    }

    function adminWithdrawalFinalization(uint256[] memory indexes) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_GUARDIAN(), msg.sender)) revert NotAuthorized();


        for (uint256 i = 0; i < indexes.length; i++) {
            _finalizeWithdrawal(indexes[i]);
        }
    }

    function adminWithdrawalInvalidation(uint256 index) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_GUARDIAN(), msg.sender)) revert NotAuthorized();

        WithdrawalEntry storage entry = withdrawalQueue[index];
        if (entry.claimed) revert AlreadyClaimed();

        entry.claimed = true;
        totalQueuedWithdrawals -= entry.hypeAmount;

        beHypeToken.transfer(roleRegistry.protocolTreasury(), entry.beHypeAmount);

        emit WithdrawalInvalidated(entry.user, index, entry.beHypeAmount);
    }

    function pauseWithdrawals() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_PAUSER(), msg.sender)) revert NotAuthorized();
        _pause();
    }
    
    function unpauseWithdrawals() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_UNPAUSER(), msg.sender)) revert NotAuthorized();
        _unpause();
    }
    
    /* ========== VIEW FUNCTIONS ========== */

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
    
    function getPendingWithdrawalsCount() external view returns (uint256) {
        return withdrawalQueue.length - lastFinalizedIndex;
    }

    /**
     * @dev if StakerCore has less than the low watermark, instant redemption will not be allowed.
     */
    function lowWatermarkInHYPE() public view returns (uint256) {
        return stakingCore.getTotalProtocolHype().mulDiv(lowWatermarkInBpsOfTvl, BASIS_POINT_SCALE);
    }
    
    /* ========== INTERNAL FUNCTIONS ========== */

    function _finalizeWithdrawal(uint256 index) internal {
        if (index >= withdrawalQueue.length) revert InvalidWithdrawalID();

        WithdrawalEntry storage entry = withdrawalQueue[index];
        if (entry.claimed) revert AlreadyClaimed();

        uint256 hypeAmount = entry.hypeAmount;
        uint256 beHypeAmount = entry.beHypeAmount;
        
        entry.claimed = true;
        
        totalQueuedWithdrawals -= entry.hypeAmount;
        
        beHypeToken.burn(address(this), beHypeAmount);
        
        (bool success, ) = payable(entry.user).call{value: hypeAmount}("");
        if (!success) revert TransferFailed();
        
        emit WithdrawalClaimed(entry.user, index, hypeAmount);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
    
    receive() external payable {}
}
