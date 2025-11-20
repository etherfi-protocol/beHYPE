// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OAppUpgradeable, Origin} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOAppComposer} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import {IStakingCore} from "./interfaces/IStakingCore.sol";
import {BeHYPEOFTAdapter} from "./BeHYPEOFTAdapter.sol";
import {IOFT, SendParam} from "lib/devtools/packages/oft-evm/contracts/interfaces/IOFT.sol";
import {OFTComposeMsgCodec} from "lib/devtools/packages/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWHYPE} from "./interfaces/IWHYPE.sol";

contract L1BeHYPEOAppStaker is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    OAppUpgradeable,
    IOAppComposer
{
    using OptionsBuilder for bytes;
    using SafeERC20 for IERC20;

    IWHYPE public constant WHYPE = IWHYPE(0x5555555555555555555555555555555555555555);
    IStakingCore public constant STAKING_CORE = IStakingCore(0xCeaD893b162D38e714D82d06a7fe0b0dc3c38E0b);
    BeHYPEOFTAdapter public constant BEHYPE_OFT_ADAPTER = BeHYPEOFTAdapter(0x637De4A55cdD37700F9B54451B709b01040D48dF);
    IERC20 public constant BEHYPE = IERC20(0xd8FC8F0b03eBA61F64D08B0bef69d80916E5DdA9);
    address public constant WHYPE_OFT_ADAPTER = 0x2B7E48511ea616101834f09945c11F7d78D9136d;

    error OnlyWHYPEOFTAdapter();

    constructor(address _endpoint) OAppUpgradeable(_endpoint) {
        _disableInitializers();
    }
    
    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
        __OApp_init(_owner);
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Receives composed messages from L2BeHYPEOAppStaker after token transfer completes
     * @dev This function is called by the LayerZero endpoint after the OFT transfer completes
     * @param _from The address that initiated the compose (the OFT contract)
     * @param _message The composed message encoded by OFTComposeMsgCodec
     */
    function lzCompose(
        address _from,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) external payable override {
        if (address(endpoint) != msg.sender) revert OnlyEndpoint(msg.sender);
        if (_from != WHYPE_OFT_ADAPTER) revert OnlyWHYPEOFTAdapter();
        
        uint256 amountReceived = OFTComposeMsgCodec.amountLD(_message);
        bytes memory originalComposeMsg = OFTComposeMsgCodec.composeMsg(_message);
        
        address receiver = abi.decode(originalComposeMsg, (address));

        WHYPE.withdraw(amountReceived);
        STAKING_CORE.stake{value: amountReceived}("");
        uint256 beHYPEStaked = BEHYPE.balanceOf(address(this));
        uint256 beHYPEStakedWithoutDust = _removeDust(beHYPEStaked);

        SendParam memory sendParam = SendParam({
            dstEid: OFTComposeMsgCodec.srcEid(_message),
            to: bytes32(uint256(uint160(receiver))),
            amountLD: beHYPEStakedWithoutDust,
            minAmountLD: beHYPEStakedWithoutDust,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = BEHYPE_OFT_ADAPTER.quoteSend(sendParam, false);

        BEHYPE.approve(address(BEHYPE_OFT_ADAPTER), beHYPEStakedWithoutDust);
        BEHYPE_OFT_ADAPTER.send{value: fee.nativeFee}(sendParam, fee, address(this));
    }

    /**
     * @notice Sweeps accumulated dust beHYPE tokens to the contract owner
     * @dev This function recovers dust funds that accumulate due to the 6 decimal shared precision
     *      limitation between HypeEVM and Scroll chains. When beHYPE is staked on HypeEVM, the
     *      amount received from STAKING_CORE is computed dynamically and has precision beyond
     *      6 decimals. During cross-chain bridging, only 6 decimal precision is preserved, leaving
     *      dust (< 10^12 wei) locked in this contract.
     */
    function sweepDust() external onlyOwner {
        BEHYPE.safeTransfer(owner(), BEHYPE.balanceOf(address(this)));
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
