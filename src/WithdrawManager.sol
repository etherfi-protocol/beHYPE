// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRoleRegistry} from "./interfaces/IRoleRegistry.sol";
import {IBeHYPEToken} from "./interfaces/IBeHype.sol";
import {IStakingCore} from "./interfaces/IStakingCore.sol";
import {IWithdrawManager} from "./interfaces/IWithdrawManager.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BucketLimiter} from "./lib/BucketLimiter.sol";

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
    
    uint256 public hypeRequestedForWithdraw;
    uint256 public lastFinalizedIndex;

    WithdrawalEntry[] public withdrawalQueue;
    mapping(address => uint256[]) public userWithdrawals;

    uint256 public minWithdrawalAmount;
    uint256 public maxWithdrawalAmount;

    uint16 public instantWithdrawalFeeInBps;
    uint16 public lowWatermarkInBpsOfTvl;

    // Bucket rate limiter for instant withdrawals
    BucketLimiter.Limit public instantWithdrawalLimit;

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
        uint16 _lowWatermarkInBpsOfTvl,
        uint16 _instantWithdrawalFeeInBps,
        address _roleRegistry,
        address _beHypeToken,
        address _stakingCore,
        uint256 _bucketCapacity,
        uint64 _bucketRefillRate
    ) public initializer {
        
        __ReentrancyGuard_init();

        minWithdrawalAmount = _minStakeAmount;
        maxWithdrawalAmount = _maxStakeAmount;
        lowWatermarkInBpsOfTvl = _lowWatermarkInBpsOfTvl;
        instantWithdrawalFeeInBps = _instantWithdrawalFeeInBps;
        
        roleRegistry = IRoleRegistry(_roleRegistry);
        beHypeToken = IBeHYPEToken(_beHypeToken);
        stakingCore = IStakingCore(_stakingCore);

        instantWithdrawalLimit = BucketLimiter.create(
            _convertToBucketUnit(_bucketCapacity, Math.Rounding.Floor), 
            _bucketRefillRate
        );

        withdrawalQueue.push(WithdrawalEntry({
            user: address(0),
            beHypeAmount: 0,
            hypeAmount: 0,
            claimed: true
        }));
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
            uint256 hypeAmount = stakingCore.BeHYPEToHYPE(beHypeAmount);
            
            // Check rate limit first - this will revert if rate limit is exceeded
            _updateRateLimit(hypeAmount);
            
            if (!canInstantWithdraw(hypeAmount)) revert InsufficientHYPELiquidity();

            beHypeToken.transferFrom(msg.sender, address(this), beHypeAmount);

            uint256 instantWithdrawalFee = beHypeAmount.mulDiv(instantWithdrawalFeeInBps, BASIS_POINT_SCALE);
            beHypeToken.transfer(roleRegistry.protocolTreasury(), instantWithdrawalFee);

            uint256 beHypeWithdrawalAfterFee = beHypeAmount - instantWithdrawalFee;
            uint256 hypeWithdrawalAfterFee = stakingCore.BeHYPEToHYPE(beHypeWithdrawalAfterFee);

            beHypeToken.burn(address(this), beHypeWithdrawalAfterFee);

            stakingCore.sendToWithdrawManager(hypeWithdrawalAfterFee);
            (bool success, ) = payable(msg.sender).call{value: hypeWithdrawalAfterFee}("");
            if (!success) revert TransferFailed();

            emit InstantWithdrawal(msg.sender, beHypeAmount, hypeWithdrawalAfterFee, instantWithdrawalFee);

        } else {
            withdrawalId = withdrawalQueue.length;
        
            uint256 hypeAmount = stakingCore.BeHYPEToHYPE(beHypeAmount);
            if (hypeAmount == 0) revert InvalidHYPEAmount();

            hypeRequestedForWithdraw += hypeAmount;
        
            beHypeToken.transferFrom(msg.sender, address(this), beHypeAmount);
        
            withdrawalQueue.push(WithdrawalEntry({
                user: msg.sender,
                beHypeAmount: beHypeAmount,
                hypeAmount: hypeAmount,
                claimed: false
            }));
        
            userWithdrawals[msg.sender].push(withdrawalId);
                
            emit WithdrawalQueued(msg.sender, withdrawalId, beHypeAmount, hypeAmount, withdrawalId);
        }
        
    }
    
    function claimWithdrawal(uint256 withdrawalId) external nonReentrant {
        if (paused()) revert WithdrawalsPaused();
        if (!canClaimWithdrawal(withdrawalId)) revert WithdrawalNotFinalized();
        
        _claimWithdrawal(withdrawalId);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function finalizeWithdrawals(uint256 index) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        if (index >= withdrawalQueue.length) revert IndexOutOfBounds();
        if (index < lastFinalizedIndex) revert CanOnlyFinalizeForward();

        uint256 hypeAmountToFinalize = 0;
        for (uint256 i = lastFinalizedIndex; i <= index;) {
            hypeAmountToFinalize += withdrawalQueue[i].hypeAmount;

            unchecked { ++i; }
        }

        uint256 liquidHypeAmount = getLiquidHypeAmount();
        if (liquidHypeAmount < hypeAmountToFinalize) revert InsufficientHYPELiquidity(); 

        hypeRequestedForWithdraw -= hypeAmountToFinalize;
        lastFinalizedIndex = index;

        stakingCore.sendToWithdrawManager(hypeAmountToFinalize);

        emit WithdrawalsBatchFinalized(index);
    }

    function setInstantWithdrawalFeeInBps(uint16 _instantWithdrawalFeeInBps) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_GUARDIAN(), msg.sender)) revert NotAuthorized();
        if (_instantWithdrawalFeeInBps > BASIS_POINT_SCALE) revert InvalidInstantWithdrawalFee();

        instantWithdrawalFeeInBps = _instantWithdrawalFeeInBps;

        emit InstantWithdrawalFeeInBpsUpdated(_instantWithdrawalFeeInBps);
    }

    /**
     * @dev Sets the maximum size of the bucket that can be consumed in a given time period.
     * @param capacity The capacity of the bucket in HYPE.
     */
    function setInstantWithdrawalCapacity(uint256 capacity) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        // max capacity = max(uint64) * 1e12 ~= 16 * 1e18 * 1e12 = 16 * 1e12 HYPE, which is practically enough
        uint64 bucketUnit = _convertToBucketUnit(capacity, Math.Rounding.Floor);
        BucketLimiter.setCapacity(instantWithdrawalLimit, bucketUnit);
    }

     /**
     * @dev Sets the rate at which the bucket is refilled per second.
     * @param refillRate The rate at which the bucket is refilled per second in HYPE.
     */
    function setInstantWithdrawalRefillRatePerSecond(uint64 refillRate) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        BucketLimiter.setRefillRate(instantWithdrawalLimit, refillRate);
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

    function canClaimWithdrawal(uint256 withdrawalId) public view returns (bool) {
        if (withdrawalId >= withdrawalQueue.length) return false;
        if (withdrawalId > lastFinalizedIndex) return false;
        
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

    /**
     * @dev Returns whether the given amount can be instantly withdrawn.
     * @param hypeAmount The HYPE amount to check.
     */
    function canInstantWithdraw(uint256 hypeAmount) public view returns (bool) {
        if (getLiquidHypeAmount() < lowWatermarkInHYPE()) return false;
        
        return hypeAmount <= getLiquidHypeAmount();
    }

    /**
     * @dev Returns the total amount that can be instantly withdrawn.
     */
    function totalInstantWithdrawableAmount() external view returns (uint256) {
        if (getLiquidHypeAmount() < lowWatermarkInHYPE()) return 0;
        
        return getLiquidHypeAmount();
    }

    /**
     * @dev Returns the current liquid HYPE amount available for withdrawals.
     * This is the difference between the staking core's balance and this contract's balance.
     */
    function getLiquidHypeAmount() public view returns (uint256) {
        return address(stakingCore).balance - address(this).balance;
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

    function _claimWithdrawal(uint256 index) internal {
        if (index >= withdrawalQueue.length) revert InvalidWithdrawalID();

        WithdrawalEntry storage entry = withdrawalQueue[index];
        if (entry.claimed) revert AlreadyClaimed();

        uint256 hypeAmount = entry.hypeAmount;
        uint256 beHypeAmount = entry.beHypeAmount;
        
        entry.claimed = true;

        beHypeToken.burn(address(this), beHypeAmount);
        
        (bool success, ) = payable(entry.user).call{value: hypeAmount}("");
        if (!success) revert TransferFailed();
        
        emit WithdrawalClaimed(entry.user, index, hypeAmount);
    }

    function _updateRateLimit(uint256 amount) internal {
        uint64 bucketUnit = _convertToBucketUnit(amount, Math.Rounding.Ceil);
        if (!BucketLimiter.consume(instantWithdrawalLimit, bucketUnit)) revert InstantWithdrawalRateLimitExceeded();
    }

    function _convertToBucketUnit(uint256 amount, Math.Rounding rounding) internal pure returns (uint64) {
        require(amount < type(uint64).max * BUCKET_UNIT_SCALE, "WithdrawManager: Amount too large");
        return (rounding == Math.Rounding.Ceil) ? SafeCast.toUint64((amount + BUCKET_UNIT_SCALE - 1) / BUCKET_UNIT_SCALE) : SafeCast.toUint64(amount / BUCKET_UNIT_SCALE);
    }

    function _convertFromBucketUnit(uint64 bucketUnit) internal pure returns (uint256) {
        return bucketUnit * BUCKET_UNIT_SCALE;
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
    
    receive() external payable {}
}
