// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "forge-std/StdJson.sol";
import "../../src/BeHYPEOFT.sol";
import "../../src/BeHYPEOFTAdapter.sol";

/*
* For Optimism (BeHYPEOFT):
* forge script script/OFT/TransferOFTOwnership.s.sol:TransferOFTOwnership \
* --rpc-url $OPTIMISM_RPC \
* --broadcast
*
* For HyperEVM (BeHYPEOFTAdapter):
* forge script script/OFT/TransferOFTOwnership.s.sol:TransferOFTOwnership \
* --rpc-url $HYPEREVM_RPC \
* --broadcast
*/
contract TransferOFTOwnership is Script {
    using stdJson for string;

    string public config;
    address public scriptDeployer;
    bool public isOptimism;

    function run() external {
        config = vm.readFile("config/production.json");
        scriptDeployer = msg.sender;

        vm.startBroadcast();
        
        uint256 chainId = block.chainid;
        isOptimism = (chainId == 10);

        if (isOptimism) {
            _transferOptimismOFTOwnership();
        } else {
            _transferHyperEVMOFTAdapterOwnership();
        }

        vm.stopBroadcast();
    }

    function _transferOptimismOFTOwnership() private {
        address oftAddress = config.readAddress(".addresses.BeHYPEOFT");
        address optimismController = config.readAddress(".roles.optimismController");
        address pauser = config.readAddress(".roles.pauser");

        BeHYPEOFT oft = BeHYPEOFT(oftAddress);

        oft.setDelegate(optimismController);

        oft.setRole(pauser, oft.PROTOCOL_PAUSER(), true);

        oft.setRole(optimismController, oft.PROTOCOL_UNPAUSER(), true);

        oft.transferOwnership(optimismController);

    }

    function _transferHyperEVMOFTAdapterOwnership() private {
        address adapterAddress = config.readAddress(".addresses.BeHYPEOFTAdapter");
        address guardian = config.readAddress(".roles.guardian");

        BeHYPEOFTAdapter adapter = BeHYPEOFTAdapter(adapterAddress);

        adapter.setDelegate(guardian);

        adapter.transferOwnership(guardian);

        console.log("New Owner:", adapter.owner());
    }
}

