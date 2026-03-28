// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "../../src/lib/UUPSProxy.sol";
import "../../src/BeHYPEOFT.sol";
import "../../src/BeHYPEOFTAdapter.sol";
import "../utils/Utils.sol";
import {ILayerZeroEndpointV2} from "lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "lib/LayerZero-v2/packages/layerzero-v2/evm/messagelib/contracts/uln/UlnBase.sol";
import {OptionsBuilder} from "lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "lib/devtools/packages/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract DeployOFT is Script, Utils {
    using stdJson for string;
    using OptionsBuilder for bytes;

    BeHYPEOFT public beHYPEOFTImpl;
    BeHYPEOFTAdapter public beHYPEOFTAdapterImpl;
    UUPSProxy public oftProxy;
    UUPSProxy public oftAdapterProxy;

    string public config;
    string public configPath;
    bool public isOptimism;
    EnforcedOptionParam[] public enforcedOptions;

    /*
    * For Optimism (BeHYPEOFT):
    * forge script script/oft/DeployOFT.s.sol:DeployOFT \
    * --rpc-url $OPTIMISM_RPC \
    * --ledger \
    * --sender 0xd8F3803d8412e61e04F53e1C9394e13eC8b32550 \
    * --broadcast \
    * --verify \
    *
    * For HyperEVM (BeHYPEOFTAdapter):
    * forge script script/oft/DeployOFT.s.sol:DeployOFT \
    * --rpc-url $HYPEREVM_RPC \
    * --ledger \
    * --sender 0xd8F3803d8412e61e04F53e1C9394e13eC8b32550 \
    * --broadcast \
    * --verify
    */
    function run() external {
        config = vm.readFile("config/production.json");

        vm.startBroadcast();
        uint256 chainId = block.chainid;
        isOptimism = (chainId == 10);

        if (isOptimism) {
            _deployBeHYPEOFT();
            _configureBeHYPEOFT();
        } else {
            _deployBeHYPEOFTAdapter();
            _configureBeHYPEOFTAdapter();
        }

        vm.stopBroadcast();
    }

    function _deployBeHYPEOFT() private {
        address optimismEndpoint = config.readAddress(".layerZero.optimism.endpoint");

        beHYPEOFTImpl = new BeHYPEOFT(optimismEndpoint);

        address deployedAddress = deployWithCreate3(
            abi.encodePacked(
                type(UUPSProxy).creationCode,
                abi.encode(
                    address(beHYPEOFTImpl),
                    abi.encodeWithSelector(
                        BeHYPEOFT.initialize.selector,
                        config.readString(".token.name"),
                        config.readString(".token.symbol"),
                        msg.sender
                    )
                )
            ),
            keccak256(bytes("BeHYPEOFTProxy"))
        );

        address expectedAddress = config.readAddress(".addresses.BeHYPEOFT");
        if (deployedAddress != expectedAddress) {
            revert(string(abi.encodePacked("Address mismatch for BeHYPEOFT")));
        }

        oftProxy = UUPSProxy(payable(deployedAddress));
    }

    function _deployBeHYPEOFTAdapter() private {
        address hyperEVMEndpoint = config.readAddress(".layerZero.hyperEVM.endpoint");
        address beHYPEToken = config.readAddress(".addresses.BeHYPE");

        beHYPEOFTAdapterImpl = new BeHYPEOFTAdapter(beHYPEToken, hyperEVMEndpoint);

        address deployedAddress = deployWithCreate3(
            abi.encodePacked(
                type(UUPSProxy).creationCode,
                abi.encode(
                    address(beHYPEOFTAdapterImpl),
                    abi.encodeWithSelector(
                        BeHYPEOFTAdapter.initialize.selector,
                        msg.sender,
                        config.readAddress(".addresses.RoleRegistry")
                    )
                )
            ),
            keccak256(bytes("BeHYPEOFTAdapterProxy"))
        );

        address expectedAddress = config.readAddress(".addresses.BeHYPEOFTAdapter");
        if (deployedAddress != expectedAddress) {
            revert(string(abi.encodePacked("Address mismatch for BeHYPEOFTAdapter")));
        }

        oftAdapterProxy = UUPSProxy(payable(deployedAddress));
    }

    function _configureBeHYPEOFT() private {
        // BeHYPEOFT oft = BeHYPEOFT(address(oftProxy));
        BeHYPEOFT oft = BeHYPEOFT(config.readAddress(".addresses.BeHYPEOFT"));

        uint32 hyperEVMEid = uint32(config.readUint(".layerZero.hyperEVM.eid"));
        address hyperEVMAdapter = config.readAddress(".addresses.BeHYPEOFTAdapter");

        oft.setPeer(hyperEVMEid, bytes32(uint256(uint160(hyperEVMAdapter))));

        address optimismEndpoint = config.readAddress(".layerZero.optimism.endpoint");
        _setDVN(
            hyperEVMEid,
            optimismEndpoint,
            config.readAddress(".layerZero.optimism.send302"),
            config.readAddress(".layerZero.optimism.receive302"),
            config.readAddress(".layerZero.optimism.nevermindDvn"),
            config.readAddress(".layerZero.optimism.layerZeroDvn"),
            address(oft)
        );

        _appendEnforcedOptions(hyperEVMEid);
        oft.setEnforcedOptions(enforcedOptions);
    }

    function _configureBeHYPEOFTAdapter() private {
        BeHYPEOFTAdapter adapter = BeHYPEOFTAdapter(address(oftAdapterProxy));

        uint32 optimismEid = uint32(config.readUint(".layerZero.optimism.eid"));
        address optimismOFT = config.readAddress(".addresses.BeHYPEOFT");

        adapter.setPeer(optimismEid, bytes32(uint256(uint160(optimismOFT))));

        address hyperEVMEndpoint = config.readAddress(".layerZero.hyperEVM.endpoint");
        _setDVN(
            optimismEid,
            hyperEVMEndpoint,
            config.readAddress(".layerZero.hyperEVM.send302"),
            config.readAddress(".layerZero.hyperEVM.receive302"),
            config.readAddress(".layerZero.hyperEVM.nevermindDvn"),
            config.readAddress(".layerZero.hyperEVM.layerZeroDvn"),
            address(oftAdapterProxy)
        );

        _appendEnforcedOptions(optimismEid);
        adapter.setEnforcedOptions(enforcedOptions);
    }

    function _setDVN(
        uint32 dstEid,
        address endpoint,
        address sendLib,
        address receiveLib,
        address nevermindDvn,
        address layerZeroDvn,
        address oapp
    ) private {
        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](2);

        if (layerZeroDvn > nevermindDvn) {
            requiredDVNs[0] = nevermindDvn;
            requiredDVNs[1] = layerZeroDvn;
        } else {
            requiredDVNs[0] = layerZeroDvn;
            requiredDVNs[1] = nevermindDvn;
        }

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 5,
            requiredDVNCount: 2,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(dstEid, 2, abi.encode(ulnConfig));
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, sendLib, params);
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, receiveLib, params);
    }

    function _appendEnforcedOptions(uint32 dstEid) private {
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        }));
        enforcedOptions.push(EnforcedOptionParam({
            eid: dstEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        }));
    }
}
