// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ========== IMPORTS ========== */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IRoleRegistry} from "./interfaces/IRoleRegistry.sol";
import {IBeHYPEToken} from "./interfaces/IBeHYPE.sol";
import {IStakingCore} from "./interfaces/IStakingCore.sol";
import {L1Read} from "./lib/L1Read.sol";
import {CoreWriter} from "./lib/CoreWriter.sol";

contract StakingCore is IStakingCore, Initializable, UUPSUpgradeable, PausableUpgradeable {

     /* ========== STATE VARIABLES ========== */

    IRoleRegistry public roleRegistry;
    IBeHYPEToken public beHypeToken;

    /* ========== CONSTANTS ========== */

    uint256 public exchangeRatio = 1e18;
    uint256 public constant MAX_APR_CHANGE = 3e15; // TODO: make this configurable? compare to other protocols to see what they do
    uint64 public HYPE_TOKEN_ID = 150;
    address public constant L1_HYPE_CONTRACT = 0x2222222222222222222222222222222222222222;
    L1Read public constant l1Read = L1Read(0xb7467E0524Afba7006957701d1F06A59000d15A2);
    CoreWriter public constant coreWriter = CoreWriter(0x3333333333333333333333333333333333333333);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _roleRegistry,
        address _beHype) public initializer {

        roleRegistry = IRoleRegistry(_roleRegistry);
        beHypeToken = IBeHYPEToken(_beHype);
    }

    /* ========== MAIN FUNCTIONS ========== */

    function stake(string memory communityCode) public payable {
       if (paused()) revert StakingPaused();
        
       beHypeToken.mint(msg.sender, HYPEToKHYPE(msg.value));

       emit Deposit(msg.sender, msg.value, communityCode); 
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function updateExchangeRatio() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();

        uint256 newRatio = Math.mulDiv(getTotalProtocolHype(), 1e18, beHypeToken.totalSupply());
        
        if (newRatio < exchangeRatio) revert ExchangeRatioCannotDecrease();
        
        uint256 ratioChange;
        if (newRatio > exchangeRatio) {
            ratioChange = newRatio - exchangeRatio;
        } else {
            ratioChange = exchangeRatio - newRatio;
        }
        
        if (ratioChange > MAX_APR_CHANGE) revert ExchangeRatioChangeExceedsThreshold();
        
        uint256 oldRatio = exchangeRatio;
        exchangeRatio = newRatio;
        
        emit ExchangeRatioUpdated(oldRatio, exchangeRatio);
    }

    function depositToHyperCore(uint256 amount) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();

        (bool success,) = payable(L1_HYPE_CONTRACT).call{value: amount}("");
        if (!success) revert FailedToDepositToHyperCore();
        emit HyperCoreDeposit(amount);
    }

    function withdrawFromHyperCore(uint amount) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        
        _encodeAction(6, abi.encode(address(this), HYPE_TOKEN_ID, amount));
        emit HyperCoreWithdraw(amount);
    }

    function depositToStaking(uint256 amount) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        
        _encodeAction(4, abi.encode(_convertTo8Decimals(amount)));
        emit HyperCoreStakingDeposit(amount);
    }

    function withdrawFromStaking(uint256 amount) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        
        _encodeAction(5, abi.encode(_convertTo8Decimals(amount)));
        emit HyperCoreStakingWithdraw(amount);
    }

    function delegateTokens(address validator, uint256 amount, bool isUndelegate) external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_ADMIN(), msg.sender)) revert NotAuthorized();
        
        _encodeAction(3, abi.encode(validator, _convertTo8Decimals(amount), isUndelegate));
        emit TokenDelegated(validator, amount, isUndelegate);
    }

    function pauseStaking() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_PAUSER(), msg.sender)) revert NotAuthorized();
        _pause();
    }

    function unpauseStaking() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_UNPAUSER(), msg.sender)) revert NotAuthorized();
        _unpause();
    }

    /* ========== VIEW FUNCTIONS ========== */

    function kHYPEToHYPE(uint256 kHYPEAmount) public view returns (uint256) {
        return Math.mulDiv(kHYPEAmount, exchangeRatio, 1e18);
    }

    function HYPEToKHYPE(uint256 HYPEAmount) public view returns (uint256) {
        return Math.mulDiv(HYPEAmount, 1e18, exchangeRatio);
    }

    function getTotalProtocolHype() public view returns (uint256) {
        L1Read.DelegatorSummary memory delegatorSummary = l1Read.delegatorSummary(address(this));
        uint256 totalHypeInStakingAccount = _convertTo18Decimals(delegatorSummary.delegated) + _convertTo18Decimals(delegatorSummary.undelegated) + _convertTo18Decimals(delegatorSummary.totalPendingWithdrawal);

        L1Read.SpotBalance memory spotBalance = l1Read.spotBalance(address(this), HYPE_TOKEN_ID);
        uint256 totalHypeInSpotAccount = _convertTo18Decimals(spotBalance.total);

        uint256 totalHypeInLiquidityPool = address(this).balance;

        return totalHypeInStakingAccount + totalHypeInSpotAccount + totalHypeInLiquidityPool;
    }

    function 

    /* ========== INTERNAL FUNCTIONS ========== */

    // TODO: create a unit test to go back and forth between 8 and 18 decimals
    function _convertTo8Decimals(uint256 amount) internal pure returns (uint64) {
        uint256 truncatedAmount = amount / 1e10;
        if (truncatedAmount > type(uint64).max) revert AmountExceedsUint64Max();
        return uint64(truncatedAmount);
    }

    function _convertTo18Decimals(uint64 amount) internal pure returns (uint256) {
        return uint256(amount) * 1e10;
    }

    /**
     * @notice Encodes and calls the action on hyperCore
     * @dev https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore
     * @param actionId The action ID (1-255)
     * @param actionData The encoded action data
     */
    function _encodeAction(uint8 actionId, bytes memory actionData) internal {
        bytes memory data = new bytes(4 + actionData.length);

        data[0] = 0x01;
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = bytes1(actionId);
        
        for (uint256 i = 0; i < actionData.length; i++) {
            data[4 + i] = actionData[i];
        }
        coreWriter.sendRawAction(data);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
}
