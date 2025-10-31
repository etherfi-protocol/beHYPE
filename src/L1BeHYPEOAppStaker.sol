// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OAppUpgradeable, Origin} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IStakingCore} from "./interfaces/IStakingCore.sol";
import {BeHYPEOFTAdapter} from "./BeHYPEOFTAdapter.sol";
import {IOFT, SendParam} from "lib/devtools/packages/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWHYPE} from "./interfaces/IWHYPE.sol";

contract L1BeHYPEOAppStaker is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    OAppUpgradeable
{
    using OptionsBuilder for bytes;
    using SafeERC20 for IERC20;

    IWHYPE public constant WHYPE = IWHYPE(0x5555555555555555555555555555555555555555);
    IStakingCore public constant STAKING_CORE = IStakingCore(0xCeaD893b162D38e714D82d06a7fe0b0dc3c38E0b);
    BeHYPEOFTAdapter public constant BEHYPE_OFT_ADAPTER = BeHYPEOFTAdapter(0x637De4A55cdD37700F9B54451B709b01040D48dF);
    IERC20 public constant BEHYPE = IERC20(0xd8FC8F0b03eBA61F64D08B0bef69d80916E5DdA9);

    constructor(address _endpoint) OAppUpgradeable(_endpoint) {
        _disableInitializers();
    }
    
    function initialize(address _owner) external initializer {
        __Ownable_init(_owner);
        __OApp_init(_owner);
        __UUPSUpgradeable_init();
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        (uint256 amountReceived, address receiver) = abi.decode(_message, (uint256, address));

        WHYPE.withdraw(amountReceived);
        STAKING_CORE.stake{value: amountReceived}("");
        uint256 beHYPEStaked = BEHYPE.balanceOf(address(this));
        uint256 minAmount = beHYPEStaked - (beHYPEStaked / 10000); 

        SendParam memory sendParam = SendParam({
            dstEid: _origin.srcEid,
            to: bytes32(uint256(uint160(receiver))),
            amountLD: beHYPEStaked,
            minAmountLD: minAmount,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory fee = BEHYPE_OFT_ADAPTER.quoteSend(sendParam, false);

        BEHYPE.approve(address(BEHYPE_OFT_ADAPTER), beHYPEStaked);
        BEHYPE_OFT_ADAPTER.send{value: fee.nativeFee}(sendParam, fee, address(this));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}
}
