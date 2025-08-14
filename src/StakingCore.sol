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

    IRoleRegistry public roleRegistry;
    IBeHYPEToken public beHypeToken;
    uint256 public totalHypeSupply;

    uint256 public exchangeRatio = 1e18;
    
    // APR limit threshold: 0.3% = 0.003 * 1e18 = 3e15
    uint256 public constant MAX_APR_CHANGE = 3e15; // 0.3%
    
    address public constant L1_HYPE_CONTRACT = 0x2222222222222222222222222222222222222222;
    L1Read internal l1ReadContract = L1Read(0x0000000000000000000000000000000000000800);
    CoreWriter internal constant coreWriterContract = CoreWriter(0x3333333333333333333333333333333333333333);

    bytes32 public constant LIQUIDITY_MANAGER_ROLE = keccak256("LIQUIDITY_MANAGER_ROLE");


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

    function updateExchangeRatio() external {
        require(roleRegistry.hasRole(roleRegistry.PROTOCOL_UPDATER(), msg.sender), "Not authorized");
        
        uint256 totalBeHypeSupply = beHypeToken.totalSupply();

        try l1ReadContract.delegatorSummary(address(this)) returns (L1Read.DelegatorSummary memory delegatorSummary) {
            uint256 newRatio = Math.mulDiv(delegatorSummary.delegated, 1e18, totalBeHypeSupply);
            
            // Prevent negative rebases - ratio can only increase or stay the same
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
        require(amount > 0, "Amount must be greater than 0");
        
        // Encode action 4: Staking deposit
        bytes memory encodedAction = abi.encode(amount);
        bytes memory data = new bytes(4 + encodedAction.length);
        
        // Version 1
        data[0] = 0x01;
        // Action ID 4 (big-endian)
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x04;
        
        // Copy action data
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        
        coreWriterContract.sendRawAction(data);
        emit StakingDeposit(amount);
    }

    function withdrawFromStaking(uint256 amount) external {
        require(roleRegistry.hasRole(LIQUIDITY_MANAGER_ROLE, msg.sender), "Not authorized");
        require(amount > 0, "Amount must be greater than 0");
        
        // Encode action 5: Staking withdraw
        bytes memory encodedAction = abi.encode(amount);
        bytes memory data = new bytes(4 + encodedAction.length);
        
        // Version 1
        data[0] = 0x01;
        // Action ID 5 (big-endian)
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x05;
        
        // Copy action data
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        
        coreWriterContract.sendRawAction(data);
        emit StakingWithdraw(amount);
    }

    function delegateTokens(address validator, uint256 amount, bool isUndelegate) external {
        require(roleRegistry.hasRole(LIQUIDITY_MANAGER_ROLE, msg.sender), "Not authorized");
        require(validator != address(0), "Invalid validator address");
        require(amount > 0, "Amount must be greater than 0");
        
        // Encode action 3: Token delegate
        bytes memory encodedAction = abi.encode(validator, amount, isUndelegate);
        bytes memory data = new bytes(4 + encodedAction.length);
        
        // Version 1
        data[0] = 0x01;
        // Action ID 3 (big-endian)
        data[1] = 0x00;
        data[2] = 0x00;
        data[3] = 0x03;
        
        // Copy action data
        for (uint256 i = 0; i < encodedAction.length; i++) {
            data[4 + i] = encodedAction[i];
        }
        
        coreWriterContract.sendRawAction(data);
        emit TokenDelegated(validator, amount, isUndelegate);
    }

    function kHYPEToHYPE(uint256 kHYPEAmount) public view returns (uint256) {
        return Math.mulDiv(kHYPEAmount, exchangeRatio, 1e18);
    }

    function HYPEToKHYPE(uint256 HYPEAmount) public view returns (uint256) {
        return Math.mulDiv(HYPEAmount, 1e18, exchangeRatio);
    }

    function l1Read() external view returns (address) {
        return address(l1ReadContract);
    }

    function coreWriter() external pure returns (address) {
        return address(coreWriterContract);
    }

     function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
}
