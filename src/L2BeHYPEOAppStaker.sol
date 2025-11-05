// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OAppUpgradeable, Origin} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOFT, SendParam} from "lib/devtools/packages/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract L2BeHYPEOAppStaker is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    OAppUpgradeable
{
    using OptionsBuilder for bytes;
    using SafeERC20 for IERC20;

    uint32 public constant HYPEREVM_EID = 30367;
    IOFT public constant WHYPE = IOFT(0xd83E3d560bA6F05094d9D8B3EB8aaEA571D1864E);
    uint128 public enforceOptions;
    uint128 public lzReceiveGasLimit;

    error InsufficientFee();
    error AmountContainsDust();

    struct StakeParams {
        SendParam oftParam;
        MessagingFee oftFee;
        uint256 WHYPEWithoutDust;
    }

    constructor(address _endpoint) OAppUpgradeable(_endpoint) {
        _disableInitializers();
    }

    function initialize(address _owner, uint128 _enforceOptions, uint128 _lzReceiveGasLimit) external initializer {
        __Ownable_init(_owner);
        __OApp_init(_owner);
        __UUPSUpgradeable_init();
        
        enforceOptions = _enforceOptions;
        lzReceiveGasLimit = _lzReceiveGasLimit;
    }

    /**
     * @notice Quotes the total fee required to stake WHYPE tokens
     * @param hypeAmountIn The amount of WHYPE tokens to stake
     * @param receiver The user's cash safe address where beHYPE will be asynchronously delivered
     */
    function quoteStake(
        uint256 hypeAmountIn,
        address receiver
    ) external view returns (uint256 totalFee) {
        StakeParams memory params = _buildStakeParams(hypeAmountIn, receiver);
        return params.oftFee.nativeFee;
    }

    /**
     * @notice Stakes WHYPE tokens by sending them cross-chain to be staked on HyperEVM
     * @dev Reverts if the amount contains dust beyond shared decimal precision
     * @param hypeAmountIn The amount of WHYPE tokens to stake
     * @param receiver The user's cash safe address where beHYPE will be asynchronously delivered after staking completes
     */
    function stake(uint256 hypeAmountIn, address receiver) external payable { 
        StakeParams memory params = _buildStakeParams(hypeAmountIn, receiver);
        if (msg.value < params.oftFee.nativeFee) revert InsufficientFee();
        
        IERC20(address(WHYPE)).transferFrom(msg.sender, address(this), params.WHYPEWithoutDust);
        WHYPE.send{value: params.oftFee.nativeFee}(params.oftParam, params.oftFee, msg.sender);
    }

    /**
     * @notice Updates the enforceOptions parameter used for executor LzCompose options
     * @param _enforceOptions The new enforceOptions value (gas limit for lzCompose execution)
     */
    function setEnforceOptions(uint128 _enforceOptions) external onlyOwner {
        enforceOptions = _enforceOptions;
    }

    /**
     * @notice Updates the lzReceiveGasLimit parameter used for executor LzReceive options
     * @param _lzReceiveGasLimit The new lzReceiveGasLimit value (gas limit for lzReceive execution)
     */
    function setLzReceiveGasLimit(uint128 _lzReceiveGasLimit) external onlyOwner {
        lzReceiveGasLimit = _lzReceiveGasLimit;
    }

    function _buildStakeParams(
        uint256 hypeAmountIn,
        address receiver
    ) internal view returns (StakeParams memory params) {
        bytes memory composeMsg = abi.encode(receiver);

        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(lzReceiveGasLimit, 0)
            .addExecutorLzComposeOption(0, enforceOptions, 0);

        uint256 amountWithoutDust = _removeDust(hypeAmountIn);
        params.WHYPEWithoutDust = amountWithoutDust;
        params.oftParam = SendParam({
            dstEid: HYPEREVM_EID,
            to: _getPeerOrRevert(HYPEREVM_EID),
            amountLD: amountWithoutDust,
            minAmountLD: amountWithoutDust,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: ""
        });
        
        params.oftFee = WHYPE.quoteSend(params.oftParam, false);
    }

    /**
     * @dev Removes dust from the given local decimal amount using the OFT's decimalConversionRate
     * @param _amountLD The amount in local decimals
     * @return The amount after removing dust
     * @dev matches the calculation used in OFTCore: (amountLD / conversionRate) * conversionRate
     */
    function _removeDust(uint256 _amountLD) internal pure returns (uint256) {
        uint256 conversionRate = 1e12; // 10^12 (18 decimals - 6 shared decimals)
        return (_amountLD / conversionRate) * conversionRate;
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata /*_message*/,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {}

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}
}
