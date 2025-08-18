// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRoleRegistry} from "./IRoleRegistry.sol";
import {IBeHYPEToken} from "./IBeHype.sol";

/**
 * @title IStakingCore
 * @notice Interface for the StakingCore contract that manages staking operations and exchange ratios
 * @dev Provides functionality for staking deposits, withdrawals, token delegation, and exchange ratio management
 * @author EtherFi
 */
interface IStakingCore {
    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when the exchange ratio is updated
     * @param oldRatio The previous exchange ratio
     * @param newRatio The new exchange ratio
     */
    event ExchangeRatioUpdated(uint256 oldRatio, uint256 newRatio);

    /**
     * @notice Emitted when tokens are deposited to HyperCore staking module
     * @param amount The amount of tokens deposited
     */
    event HyperCoreDeposit(uint256 amount);

    /**
     * @notice Emitted when tokens are withdrawn from HyperCore staking module
     * @param amount The amount of tokens withdrawn
     */
    event HyperCoreWithdraw(uint256 amount);

    /**
     * @notice Emitted when tokens are staked
     * @param user Who minted the tokens
     * @param amount The amount of tokens staked
     * @param communityCode The community code of the staked tokens
     */
    event Deposit(address user, uint256 amount, string communityCode);

    /**
    event Staked(uint256 oldSupply, uint256 newSupply);

    /**
     * @notice Emitted when tokens are delegated or undelegated
     * @param validator The validator address
     * @param amount The amount of tokens delegated/undelegated
     * @param isUndelegate True if undelegating, false if delegating 22
     */
    event TokenDelegated(address validator, uint256 amount, bool isUndelegate);

    /* ========== STATE VARIABLES ========== */

    /**
     * @notice Returns the role registry contract address
     * @return The address of the role registry contract
     */
    function roleRegistry() external view returns (IRoleRegistry);

    /**
     * @notice Returns the BeHYPE token contract address
     * @return The address of the BeHYPE token contract
     */
    function beHypeToken() external view returns (IBeHYPEToken);

    /**
     * @notice Returns the total HYPE supply
     * @return The total HYPE supply
     */
    function totalHypeSupply() external view returns (uint256);

    /**
     * @notice Returns the current exchange ratio between kHYPE and HYPE
     * @return The exchange ratio (scaled by 1e18)
     */
    function exchangeRatio() external view returns (uint256);

    /**
     * @notice Returns the maximum allowed APR change threshold
     * @return The maximum APR change threshold (0.3% = 3e15)
     */
    function MAX_APR_CHANGE() external view returns (uint256);

    /**
     * @notice Returns the L1 HYPE contract address
     * @return The address of the L1 HYPE contract
     */
    function L1_HYPE_CONTRACT() external view returns (address);

    /**
     * @notice Returns the LIQUIDITY_MANAGER_ROLE identifier
     * @return The bytes32 identifier for the LIQUIDITY_MANAGER_ROLE
     */
    function LIQUIDITY_MANAGER_ROLE() external view returns (bytes32);

    /* ========== INITIALIZATION ========== */

    /**
     * @notice Initializes the StakingCore contract
     * @param _roleRegistry The address of the role registry contract
     * @param _l1Read The address of the L1Read precompile contract
     * @param _beHype The address of the BeHYPE token contract
     * @dev This function can only be called once during contract initialization
     */
    function initialize(
        address _roleRegistry,
        address _l1Read,
        address _beHype
    ) external;

    /* ========== EXCHANGE RATIO MANAGEMENT ========== */

    /**
     * @notice Updates the exchange ratio based on L1 delegator summary
     * @dev Only callable by accounts with PROTOCOL_GOVERNOR role
     * @dev Prevents negative rebases and enforces maximum APR change threshold
     * @dev Emits ExchangeRatioUpdated event on successful update
     */
    function updateExchangeRatio() external;

    /* ========== STAKING OPERATIONS ========== */

    /**
     * @notice Deposits tokens to staking via CoreWriter Action 4
     * @param amount The amount of tokens to deposit in wei
     * @dev Only callable by accounts with LIQUIDITY_MANAGER_ROLE
     * @dev Sends Action 4 to CoreWriter for HyperCore processing
     * @dev Emits StakingDeposit event
     */
    function depositToStaking(uint256 amount) external;

    /**
     * @notice Withdraws tokens from staking via CoreWriter Action 5
     * @param amount The amount of tokens to withdraw in wei
     * @dev Only callable by accounts with LIQUIDITY_MANAGER_ROLE
     * @dev Sends Action 5 to CoreWriter for HyperCore processing
     * @dev Emits StakingWithdraw event
     */
    function withdrawFromStaking(uint256 amount) external;

    /**
     * @notice Delegates or undelegates tokens via CoreWriter Action 3
     * @param validator The validator address to delegate/undelegate from
     * @param amount The amount of tokens to delegate/undelegate in wei
     * @param isUndelegate True if undelegating, false if delegating
     * @dev Only callable by accounts with LIQUIDITY_MANAGER_ROLE
     * @dev Sends Action 3 to CoreWriter for HyperCore processing
     * @dev Emits TokenDelegated event
     */
    function delegateTokens(address validator, uint256 amount, bool isUndelegate) external;

    /* ========== CONVERSION FUNCTIONS ========== */

    /**
     * @notice Converts kHYPE amount to HYPE using current exchange ratio
     * @param kHYPEAmount The amount of kHYPE tokens to convert
     * @return The equivalent amount of HYPE tokens
     * @dev Uses current exchange ratio for conversion
     */
    function kHYPEToHYPE(uint256 kHYPEAmount) external view returns (uint256);

    /**
     * @notice Converts HYPE amount to kHYPE using current exchange ratio
     * @param HYPEAmount The amount of HYPE tokens to convert
     * @return The equivalent amount of kHYPE tokens
     * @dev Uses current exchange ratio for conversion
     */
    function HYPEToKHYPE(uint256 HYPEAmount) external view returns (uint256);
}
