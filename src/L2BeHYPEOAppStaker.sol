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

    error InsufficientFee();

    struct StakeParams {
        SendParam oftParam;
        bytes message;
        bytes options;
        MessagingFee oftFee;
        MessagingFee lzFee;
    }

    constructor(address _endpoint) OAppUpgradeable(_endpoint) {
        _disableInitializers();
    }

    function initialize(address _owner, uint128 _enforceOptions) external initializer {
        __Ownable_init(_owner);
        __OApp_init(_owner);
        __UUPSUpgradeable_init();
        
        enforceOptions = _enforceOptions;
    }

    function quoteStake(
        uint256 hypeAmountIn,
        address receiver
    ) external view returns (uint256 totalFee) {
        StakeParams memory params = _buildStakeParams(hypeAmountIn, receiver);
        totalFee = params.oftFee.nativeFee + params.lzFee.nativeFee;
    }

    function stake(uint256 hypeAmountIn, address staker, address receiver) external payable {
        StakeParams memory params = _buildStakeParams(hypeAmountIn, receiver);

        uint256 totalFee = params.oftFee.nativeFee + params.lzFee.nativeFee;
        if (msg.value < totalFee) revert InsufficientFee();
        
        // Send the users WHYPE to the peer contract on hyperEVM
        IERC20(address(WHYPE)).transferFrom(staker, address(this), hypeAmountIn);
        WHYPE.send{value: params.oftFee.nativeFee}(params.oftParam, params.oftFee, msg.sender);
        
        // Send the message to the peer contract on hyperEVM to stake the WHYPE for the user
        _lzSend(HYPEREVM_EID, params.message, params.options, params.lzFee, payable(msg.sender));
    }

    function _buildStakeParams(
        uint256 hypeAmountIn,
        address receiver
    ) internal view returns (StakeParams memory params) {
        uint256 minAmount = hypeAmountIn - (hypeAmountIn / 100);

        params.oftParam = SendParam({
            dstEid: HYPEREVM_EID,
            to: _getPeerOrRevert(HYPEREVM_EID),
            amountLD: hypeAmountIn,
            minAmountLD: minAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        params.oftFee = WHYPE.quoteSend(params.oftParam, false);
        
        params.message = abi.encode(hypeAmountIn, receiver);
        params.options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(enforceOptions, 0);
        
        params.lzFee = _quote(HYPEREVM_EID, params.message, params.options, false);
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata /*_message*/,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {}

    /**
     * @dev Allow multiple LayerZero messages in a single transaction by accepting msg.value >= per-fee.
     */
    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}
}
