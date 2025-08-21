// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IRoleRegistry} from "./interfaces/IRoleRegistry.sol";
import {IBeHYPEToken} from "./interfaces/IBeHype.sol";

contract BeHYPE is IBeHYPEToken, ERC20PermitUpgradeable, UUPSUpgradeable {

    /* ========== STATE VARIABLES ========== */

    address public stakingCore;
    IRoleRegistry public roleRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        string calldata name,
        string calldata symbol,
        address _roleRegistry,
        address _stakingCore) public initializer {

        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);

        roleRegistry = IRoleRegistry(_roleRegistry);
        stakingCore = _stakingCore;
    }

    /* ========== MAIN FUNCTIONS ========== */

    function mint(address to, uint256 amount) external {
        if (msg.sender != stakingCore) revert Unauthorized();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != stakingCore) revert Unauthorized();
        _burn(from, amount);
    }

    function setStakingCore(address _stakingCore) external {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
        stakingCore = _stakingCore;

        emit StakingCoreUpdated(stakingCore);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }

}
