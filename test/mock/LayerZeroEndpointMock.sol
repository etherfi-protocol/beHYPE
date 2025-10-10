// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MessagingReceipt, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";

contract LayerZeroEndpointMock {
    uint32 public constant MOCK_EID = 30102;
    uint64 public nonce = 0;

    function setDelegate(address _delegate) external {
        // Mock implementation - do nothing
    }
    
    function eid() external pure returns (uint32) {
        return MOCK_EID;
    }

    function send(
        MessagingParam calldata _param,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt) {
        nonce++;
        receipt = MessagingReceipt({
            guid: keccak256(abi.encodePacked(block.timestamp, nonce, msg.sender)),
            nonce: nonce,
            fee: MessagingFee({nativeFee: msg.value, lzTokenFee: 0})
        });
    }

    function sendCompose(
        address _to,
        bytes32 _guid,
        uint16 _index,
        bytes calldata _message
    ) external {
        // Mock implementation - do nothing
    }

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external {
        // Mock implementation - do nothing
    }

    function quote(
        QuoteParam calldata _param,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee) {
        fee = MessagingFee({nativeFee: 0.01 ether, lzTokenFee: 0});
    }
}

struct MessagingParam {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

struct QuoteParam {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}
