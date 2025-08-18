// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ========== IMPORTS ========== */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IRoleRegistry} from "./interfaces/IRoleRegistry.sol";
import {IBeHYPEToken} from "./interfaces/IBeHype.sol";
import {IStakingCore} from "./interfaces/IStakingCore.sol";
import {L1Read} from "./lib/L1Read.sol";
import {CoreWriter} from "./lib/CoreWriter.sol";

contract StakingCore is IStakingCore, Initializable, UUPSUpgradeable {

    /* ========== CONSTANTS ========== */

    uint256 public exchangeRatio = 1e18;

    uint256 public constant MAX_APR_CHANGE = 3e15;

    address public constant L1_HYPE_CONTRACT = 0x2222222222222222222222222222222222222222;
    L1Read internal l1ReadContract = L1Read(0x0000000000000000000000000000000000000800);
    CoreWriter internal constant coreWriterContract = CoreWriter(0x3333333333333333333333333333333333333333);

    bytes32 public constant LIQUIDITY_MANAGER_ROLE = keccak256("LIQUIDITY_MANAGER_ROLE");

    /* ========== STATE VARIABLES ========== */

    IRoleRegistry public roleRegistry;
    IBeHYPEToken public beHypeToken;
    uint256 public totalHypeSupply;
   
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _roleRegistry,
        address /* _l1Read */,
        address _beHype) public initializer {

        roleRegistry = IRoleRegistry(_roleRegistry);
        beHypeToken = IBeHYPEToken(_beHype);
    }

    /* ========== MAIN FUNCTIONS ========== */

    function stake(string memory communityCode) public payable {
       beHypeToken.mint(msg.sender, HYPEToKHYPE(msg.value));

       emit Deposit(msg.sender, msg.value, communityCode); 
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function updateExchangeRatio() external {
        require(roleRegistry.hasRole(roleRegistry.PROTOCOL_GOVERNOR(), msg.sender), "Not authorized");
        
        uint256 totalBeHypeSupply = beHypeToken.totalSupply();

        try l1ReadContract.delegatorSummary(address(this)) returns (L1Read.DelegatorSummary memory delegatorSummary) {
            uint256 newRatio = Math.mulDiv(delegatorSummary.delegated, 1e18, totalBeHypeSupply);
            
            require(newRatio >= exchangeRatio, "Exchange ratio cannot decrease");
            
            uint256 ratioChange;
            if (newRatio > exchangeRatio) {
                ratioChange = newRatio - exchangeRatio;
            } else {
                ratioChange = exchangeRatio - newRatio;
            }
            
            require(ratioChange <= MAX_APR_CHANGE, "Exchange ratio change exceeds 0.3% threshold");
            
            uint256 oldRatio = exchangeRatio;
            exchangeRatio = newRatio;
            
            emit ExchangeRatioUpdated(oldRatio, exchangeRatio);
        } catch {
            revert("Failed to fetch delegator summary from L1");
        }
    }

    function depositToStaking(uint256 amount) external {
        require(roleRegistry.hasRole(LIQUIDITY_MANAGER_ROLE, msg.sender), "Not authorized");
        
        _encodeAction(4, abi.encode(_convertTo8Decimals(amount)));
        emit HyperCoreDeposit(amount);
    }

    function withdrawFromStaking(uint256 amount) external {
        require(roleRegistry.hasRole(LIQUIDITY_MANAGER_ROLE, msg.sender), "Not authorized");
        
        _encodeAction(5, abi.encode(_convertTo8Decimals(amount)));
        emit HyperCoreWithdraw(amount);
    }

    function delegateTokens(address validator, uint256 amount, bool isUndelegate) external {
        require(roleRegistry.hasRole(LIQUIDITY_MANAGER_ROLE, msg.sender), "Not authorized");
        
        _encodeAction(3, abi.encode(validator, _convertTo8Decimals(amount), isUndelegate));
        emit TokenDelegated(validator, amount, isUndelegate);
    }

    function kHYPEToHYPE(uint256 kHYPEAmount) public view returns (uint256) {
        return Math.mulDiv(kHYPEAmount, exchangeRatio, 1e18);
    }

    function HYPEToKHYPE(uint256 HYPEAmount) public view returns (uint256) {
        return Math.mulDiv(HYPEAmount, 1e18, exchangeRatio);
    }

     /**
     * @notice Converts amount from 18 decimals to 8 decimals for L1 operations
     * @param amount Amount in 18 decimals
     * @return truncatedAmount Amount in 8 decimals
     */
    function _convertTo8Decimals(uint256 amount) internal pure returns (uint64) {
        uint256 truncatedAmount = amount / 1e10;
        require(truncatedAmount <= type(uint64).max, "Amount exceeds uint64 max");
        return uint64(truncatedAmount);
    }

    /**
     * @notice Encodes actions for hyperCore
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
        coreWriterContract.sendRawAction(data);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
}
