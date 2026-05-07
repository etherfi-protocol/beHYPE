// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/StdJson.sol";

import {ILayerZeroEndpointV2} from "lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IMessageLibManager, SetConfigParam} from "lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "lib/LayerZero-v2/packages/layerzero-v2/evm/messagelib/contracts/uln/UlnBase.sol";

import {GnosisHelpers} from "../utils/GnosisHelpers.sol";
import {L1BeHYPEOAppStaker} from "../../src/L1BeHYPEOAppStaker.sol";

/**
 * @title ConfigureL1OAppStakerForOP
 * @notice Generates a Gnosis Safe Transaction Builder JSON bundle for the HyperEVM
 *         controller (current L1BeHYPEOAppStaker owner) to peer the already-deployed
 *         L1BeHYPEOAppStaker with the new OP-side L2BeHYPEOAppStaker, and configure
 *         the HyperEVM endpoint send/receive DVNs for the OP route.
 *
 *         The bundle is simulated on the current fork to surface any reverts before
 *         signing the multisig transaction.
 *
 *         Bundle (executed by the L1 staker owner Safe):
 *           1. L1BeHYPEOAppStaker.setPeer(OP_EID, L2BeHYPEOAppStaker)
 *           2. endpoint.setConfig on send302 with [Nethermind, LayerZero] DVNs
 *           3. endpoint.setConfig on receive302 with [Nethermind, LayerZero] DVNs
 *
 * forge script script/oapp/ConfigureL1OAppStakerForOP.s.sol:ConfigureL1OAppStakerForOP \
 *   --rpc-url $HYPEREVM_RPC \
 *   -vvvv
 */
contract ConfigureL1OAppStakerForOP is GnosisHelpers {
    using stdJson for string;

    string constant OUTPUT_PATH = "output/hyperevm-l1-staker-op-config-bundle.json";
    string constant CHAIN_ID = "999";

    function run() external {
        string memory cfg = vm.readFile("config/production.json");

        address l1Staker = cfg.readAddress(".layerZero.L1BeHYPEOAppStaker");
        // L2 staker is expected to land at the same CREATE3 address on OP as Scroll
        // (per script/oapp/DeployAndConfigureOApps.s.sol).
        address l2Staker = cfg.readAddress(".layerZero.L2BeHYPEOAppStaker");
        uint32 optimismEid = uint32(cfg.readUint(".layerZero.optimism.eid"));

        address endpoint = cfg.readAddress(".layerZero.hyperEVM.endpoint");
        address sendLib = cfg.readAddress(".layerZero.hyperEVM.send302");
        address receiveLib = cfg.readAddress(".layerZero.hyperEVM.receive302");
        address nevermindDvn = cfg.readAddress(".layerZero.hyperEVM.nevermindDvn");
        address layerZeroDvn = cfg.readAddress(".layerZero.hyperEVM.layerZeroDvn");

        address safeAddress = L1BeHYPEOAppStaker(payable(l1Staker)).owner();

        // --- 1. setPeer calldata ---
        bytes memory setPeerData = abi.encodeWithSignature(
            "setPeer(uint32,bytes32)",
            optimismEid,
            bytes32(uint256(uint160(l2Staker)))
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
            confirmations: 30,
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
            l1Staker,
            sendLib,
            params
        );

        bytes memory setConfigReceiveData = abi.encodeWithSelector(
            IMessageLibManager.setConfig.selector,
            l1Staker,
            receiveLib,
            params
        );

        // --- Build Gnosis JSON bundle ---
        string memory safeHex = addressToHex(safeAddress);
        string memory l1StakerHex = addressToHex(l1Staker);
        string memory endpointHex = addressToHex(endpoint);

        string memory bundle = string.concat(
            _getGnosisHeader(CHAIN_ID, safeHex),
            _getGnosisTransaction(l1StakerHex, iToHex(setPeerData), "0", false),
            _getGnosisTransaction(endpointHex, iToHex(setConfigSendData), "0", false),
            _getGnosisTransaction(endpointHex, iToHex(setConfigReceiveData), "0", true)
        );

        vm.writeFile(OUTPUT_PATH, bundle);

        // --- Simulate execution on fork ---
        executeGnosisTransactionBundle(OUTPUT_PATH);

        // --- Verify ---
        bytes32 peer = L1BeHYPEOAppStaker(payable(l1Staker)).peers(optimismEid);
        require(
            peer == bytes32(uint256(uint160(l2Staker))),
            "Peer not set correctly"
        );
    }
}
