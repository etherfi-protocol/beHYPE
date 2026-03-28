// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/StdJson.sol";
import "../utils/GnosisHelpers.sol";
import "../../src/BeHYPEOFTAdapter.sol";
import {ILayerZeroEndpointV2} from "lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IMessageLibManager, SetConfigParam} from "lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "lib/LayerZero-v2/packages/layerzero-v2/evm/messagelib/contracts/uln/UlnBase.sol";
import {OptionsBuilder} from "lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOAppOptionsType3, EnforcedOptionParam} from "lib/devtools/packages/oapp-evm/contracts/oapp/interfaces/IOAppOptionsType3.sol";

/**
 * @title ConfigureOFTAdapterGnosis
 * @notice Generates a Gnosis Safe Transaction Builder JSON bundle for configuring
 *         the BeHYPEOFTAdapter on HyperEVM, then simulates execution on fork.
 *
 * forge script script/oft/ConfigureOFTAdapterGnosis.s.sol \
 *   --rpc-url $HYPEREVM_RPC \
 *   -vvvv
 */
contract ConfigureOFTAdapterGnosis is GnosisHelpers {
    using stdJson for string;
    using OptionsBuilder for bytes;

    string constant OUTPUT_PATH = "output/hyperevm-adapter-config-bundle.json";
    string constant CHAIN_ID = "999";

    function run() external {
        string memory config = vm.readFile("config/production.json");

        address adapter = config.readAddress(".addresses.BeHYPEOFTAdapter");
        address optimismOFT = config.readAddress(".addresses.BeHYPEOFT");
        uint32 optimismEid = uint32(config.readUint(".layerZero.optimism.eid"));

        address endpoint = config.readAddress(".layerZero.hyperEVM.endpoint");
        address sendLib = config.readAddress(".layerZero.hyperEVM.send302");
        address receiveLib = config.readAddress(".layerZero.hyperEVM.receive302");
        address nevermindDvn = config.readAddress(".layerZero.hyperEVM.nevermindDvn");
        address layerZeroDvn = config.readAddress(".layerZero.hyperEVM.layerZeroDvn");

        address safeAddress = BeHYPEOFTAdapter(adapter).owner();

        // --- 1. setPeer calldata ---
        bytes memory setPeerData = abi.encodeWithSignature(
            "setPeer(uint32,bytes32)",
            optimismEid,
            bytes32(uint256(uint160(optimismOFT)))
        );

        // --- 2 & 3. setConfig calldata (send + receive) ---
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

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(optimismEid, 2, abi.encode(ulnConfig));

        bytes memory setConfigSendData = abi.encodeWithSelector(
            IMessageLibManager.setConfig.selector,
            adapter,
            sendLib,
            params
        );

        bytes memory setConfigReceiveData = abi.encodeWithSelector(
            IMessageLibManager.setConfig.selector,
            adapter,
            receiveLib,
            params
        );

        // --- 4. setEnforcedOptions calldata ---
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](2);
        enforcedOptions[0] = EnforcedOptionParam({
            eid: optimismEid,
            msgType: 1,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        });
        enforcedOptions[1] = EnforcedOptionParam({
            eid: optimismEid,
            msgType: 2,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(170_000, 0)
        });

        bytes memory setEnforcedOptionsData = abi.encodeWithSelector(
            IOAppOptionsType3.setEnforcedOptions.selector,
            enforcedOptions
        );

        // --- Build Gnosis JSON bundle ---
        string memory safeHex = addressToHex(safeAddress);
        string memory adapterHex = addressToHex(adapter);
        string memory endpointHex = addressToHex(endpoint);

        string memory bundle = string.concat(
            _getGnosisHeader(CHAIN_ID, safeHex),
            _getGnosisTransaction(adapterHex, iToHex(setPeerData), "0", false),
            _getGnosisTransaction(endpointHex, iToHex(setConfigSendData), "0", false),
            _getGnosisTransaction(endpointHex, iToHex(setConfigReceiveData), "0", false),
            _getGnosisTransaction(adapterHex, iToHex(setEnforcedOptionsData), "0", true)
        );

        vm.writeFile(OUTPUT_PATH, bundle);

        // --- Simulate execution on fork ---
        executeGnosisTransactionBundle(OUTPUT_PATH);

        // --- Verify ---
        bytes32 peer = BeHYPEOFTAdapter(adapter).peers(optimismEid);
        require(
            peer == bytes32(uint256(uint160(optimismOFT))),
            "Peer not set correctly"
        );
    }
}
