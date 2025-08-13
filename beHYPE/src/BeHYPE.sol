// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IRoleRegistry} from "./interfaces/IRoleRegistry.sol";

contract BeHYPE is ERC20PermitUpgradeable, UUPSUpgradeable {
    
    IRoleRegistry public roleRegistry;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        string calldata name,
        string calldata symbol,
        address _roleRegistry) public initializer {

        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);

        roleRegistry = IRoleRegistry(_roleRegistry);
    }

    function mint(address to, uint256 amount) external {
        if (!roleRegistry.hasRole(MINTER_ROLE, msg.sender)) revert("Incorrect role");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (!roleRegistry.hasRole(BURNER_ROLE, msg.sender)) revert("Incorrect role");
        _burn(from, amount);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    ) internal view override {
        roleRegistry.onlyProtocolUpgrader(msg.sender);
    }

}
