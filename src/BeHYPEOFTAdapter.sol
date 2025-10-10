// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OFTAdapterUpgradeable} from "lib/devtools/packages/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IRoleRegistry} from "./interfaces/IRoleRegistry.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

/// @notice OFTAdapter uses a deployed ERC-20 token and SafeERC20 to interact with the OFTCore contract.
contract BeHYPEOFTAdapter is OFTAdapterUpgradeable, UUPSUpgradeable, PausableUpgradeable {

    error NotAuthorized();

    IRoleRegistry public roleRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _token,
        address _lzEndpoint
    ) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    function initialize(address _owner, address _roleRegistry) public initializer {
        __Ownable_init(_owner);
        __OFTAdapter_init(_owner);
        __UUPSUpgradeable_init();
        __Pausable_init();

        roleRegistry = IRoleRegistry(_roleRegistry);
    }

    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override whenNotPaused() returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused() returns (uint256 amountReceivedLD) {
        return super._credit(_to, _amountLD, _srcEid);
    }


    function pauseBridge() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_PAUSER(), msg.sender)) revert NotAuthorized();
        _pause();
    }

    function unpauseBridge() external {
        if (!roleRegistry.hasRole(roleRegistry.PROTOCOL_GUARDIAN(), msg.sender)) revert NotAuthorized();
        _unpause();
    }
    
    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }
}
