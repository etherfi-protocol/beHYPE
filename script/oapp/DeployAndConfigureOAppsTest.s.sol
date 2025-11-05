// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {UUPSProxy} from "../../src/lib/UUPSProxy.sol";
import {L1BeHYPEOAppStaker} from "../../src/L1BeHYPEOAppStaker.sol";
import {L2BeHYPEOAppStaker} from "../../src/L2BeHYPEOAppStaker.sol";
import "../utils/Utils.sol";

import {ILayerZeroEndpointV2} from "lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "lib/LayerZero-v2/packages/layerzero-v2/evm/messagelib/contracts/uln/UlnBase.sol";

///
/// Deploys and configures L1BeHYPEOAppStaker (on HyperEVM) and L2BeHYPEOAppStaker (on Scroll)
/// 
/// Usage:
///   forge script script/oapp/DeployAndConfigureOAppsTest.s.sol:DeployAndConfigureOAppsTest \
///     --rpc-url $RPC \
///     --broadcast \
///     -vvvv
contract DeployAndConfigureOAppsTest is Script, Utils {
    using stdJson for string;

    address payable public constant HYPEREVM_DEPLOYMENT = payable(address(0x07B23BB48BDf6C223D727e0979DcE34f3e911b40));
    address payable public constant SCROLL_DEPLOYMENT = payable(address(0x15Ce935E7721Cee88B4Bc0bb4Dc89bb348Cd3A4A));
    
    address payable public l1BeHYPEOAppStaker;
    address payable public l2BeHYPEOAppStaker;

    function run() external {
        string memory cfg = _readConfig();
        bool isScroll = (block.chainid == 534352);
        uint128 enforceGas = uint128(500_000);
        uint128 lzReceiveGasLimit = uint128(200_000);
        address owner = msg.sender;

        vm.startBroadcast();

        if (isScroll) {
            L2BeHYPEOAppStaker l2Impl = new L2BeHYPEOAppStaker(cfg.readAddress(".layerZero.scroll.endpoint"));
            l2BeHYPEOAppStaker = _deployL2OAppStaker(address(l2Impl), owner, enforceGas, lzReceiveGasLimit);
            
            if (l2BeHYPEOAppStaker != address(SCROLL_DEPLOYMENT)) {
                revert("L2BeHYPEOAppStaker is not the same as SCROLL_DEPLOYMENT");
            }

            address scrollEndpoint = cfg.readAddress(".layerZero.scroll.endpoint");
            uint32 dstEid = uint32(cfg.readUint(".layerZero.hyperEVM.eid"));
            L2BeHYPEOAppStaker(l2BeHYPEOAppStaker).setPeer(dstEid, bytes32(uint256(uint160(address(HYPEREVM_DEPLOYMENT)))));
            
            _setDVN(
                dstEid,
                scrollEndpoint,
                cfg.readAddress(".layerZero.scroll.send302"),
                cfg.readAddress(".layerZero.scroll.receive302"),
                cfg.readAddress(".layerZero.scroll.nevermindDvn"),
                cfg.readAddress(".layerZero.scroll.layerZeroDvn"),
                address(l2BeHYPEOAppStaker)
            );
            
        } else {
            L1BeHYPEOAppStaker l1Impl = new L1BeHYPEOAppStaker(cfg.readAddress(".layerZero.hyperEVM.endpoint"));
            l1BeHYPEOAppStaker = _deployL1OAppStaker(address(l1Impl), owner);
            
            if (l1BeHYPEOAppStaker != address(HYPEREVM_DEPLOYMENT)) {
                revert("L1BeHYPEOAppStaker is not the same as HYPEREVM_DEPLOYMENT");
            }

            address hyperEVMEndpoint = cfg.readAddress(".layerZero.hyperEVM.endpoint");
            uint32 dstEid = uint32(cfg.readUint(".layerZero.scroll.eid"));
            L1BeHYPEOAppStaker(l1BeHYPEOAppStaker).setPeer(dstEid, bytes32(uint256(uint160(address(SCROLL_DEPLOYMENT)))));
            
            _setDVN(
                dstEid,
                hyperEVMEndpoint,
                cfg.readAddress(".layerZero.hyperEVM.send302"),
                cfg.readAddress(".layerZero.hyperEVM.receive302"),
                cfg.readAddress(".layerZero.hyperEVM.nevermindDvn"),
                cfg.readAddress(".layerZero.hyperEVM.layerZeroDvn"),
                address(l1BeHYPEOAppStaker)
            );
        }

        vm.stopBroadcast();
    }

    function _deployL1OAppStaker(address impl, address owner) internal returns (address payable) {
        address proxy = deployWithCreate3(
            abi.encodePacked(
                type(UUPSProxy).creationCode,
                abi.encode(impl, abi.encodeWithSelector(L1BeHYPEOAppStaker.initialize.selector, owner))
            ),
            keccak256(bytes("L1BeHYPEOAppStakerTest2"))
        );
        return payable(proxy);
    }

    function _deployL2OAppStaker(address impl, address owner, uint128 enforceOptions, uint128 lzReceiveGasLimit) internal returns (address payable) {
        address proxy = deployWithCreate3(
            abi.encodePacked(
                type(UUPSProxy).creationCode,
                abi.encode(impl, abi.encodeWithSelector(L2BeHYPEOAppStaker.initialize.selector, owner, enforceOptions, lzReceiveGasLimit))
            ),
            keccak256(bytes("L2BeHYPEOAppStakerTest2"))
        );
        return payable(proxy);
    }

    function _readConfig() private returns (string memory) {
        string memory path;
        try vm.envString("CONFIG_PATH") returns (string memory p) { path = p; } catch { path = "config/production.json"; }
        if (vm.isFile(path)) return vm.readFile(path);
        return "";
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
            confirmations: 30,
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
}
