// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "forge-std/StdJson.sol";
import "../src/lib/UUPSProxy.sol";
import "../src/BeHYPE.sol";
import "../src/RoleRegistry.sol";
import "../src/StakingCore.sol";
import "../src/WithdrawManager.sol";
import "../src/BeHYPETimelock.sol";

contract DeployCore is Script {
    using stdJson for string;

    // Contract instances
    RoleRegistry public roleRegistry;
    BeHYPE public beHYPE;
    StakingCore public stakingCore;
    WithdrawManager public withdrawManager;
    BeHYPETimelock public timelock;

    // Proxy instances
    UUPSProxy public roleRegistryProxy;
    UUPSProxy public beHYPEProxy;
    UUPSProxy public stakingCoreProxy;
    UUPSProxy public withdrawManagerProxy;

    string public config;
    string public configPath;

    /*
    * forge script script/Deploy.s.sol:DeployCore \
    * --rpc-url $NETWORK \
    * --ledger \
    * --sender 0xd8F3803d8412e61e04F53e1C9394e13eC8b32550 \
    * --broadcast \
    * --verify \
    * --etherscan-api-key $ETH_ETHERSCAN_KEY \
    * --sig "run(string)" $CONFIG_PATH
    */
    function run(string memory _configPath) external {
        // Store config path
        configPath = _configPath;

        // Load configuration
        config = vm.readFile(configPath);

        vm.startBroadcast();

        _deployProxies();

        _deployTimelock();

        _setupInitialRoles();

        _logDeployments();
    }

    function _deployProxy(string memory configKey, address implementation, bytes memory initData) private returns (UUPSProxy proxy) {
        // Read base salt and shift value
        uint256 saltShift = config.readUint(".deployment.saltShift");

        // Create unique salt for each proxy by hashing configKey and shifting
        bytes32 salt = bytes32(uint256(keccak256(bytes(configKey))) + saltShift);

        proxy = new UUPSProxy{salt: salt}(
            address(implementation),
            initData
        );
        
        // Write the address to config
        vm.writeJson(vm.toString(address(proxy)), configPath, string.concat(".deployed.", configKey));
    }

    function _deployProxies() private {
        // Deploy implementations first
        RoleRegistry roleRegistryImpl = new RoleRegistry();
        BeHYPE beHYPEImpl = new BeHYPE();
        StakingCore stakingCoreImpl = new StakingCore();
        WithdrawManager withdrawManagerImpl = new WithdrawManager();

        // Deploy proxies with initialization data
        roleRegistryProxy = _deployProxy("roleRegistryProxy", address(roleRegistryImpl), 
            abi.encodeWithSelector(
                RoleRegistry.initialize.selector,
                config.readAddress(".roles.admin"),
                address(0), // Will be updated after withdrawManager is deployed
                address(0), // Will be updated after stakingCore is deployed
                config.readAddress(".roles.protocolTreasury")
            )
        );

        beHYPEProxy = _deployProxy("beHYPEProxy", address(beHYPEImpl),
            abi.encodeWithSelector(
                BeHYPE.initialize.selector,
                config.readString(".token.name"),
                config.readString(".token.symbol"),
                address(roleRegistryProxy),
                address(0), // Will be updated after stakingCore is deployed
                address(0)  // Will be updated after withdrawManager is deployed
            )
        );

        stakingCoreProxy = _deployProxy("stakingCoreProxy", address(stakingCoreImpl),
            abi.encodeWithSelector(
                StakingCore.initialize.selector,
                address(roleRegistryProxy),
                address(beHYPEProxy),
                address(0), // Will be updated after withdrawManager is deployed
                config.readUint(".staking.acceptableAprInBps"),
                config.readBool(".staking.exchangeRateGuard"),
                config.readUint(".staking.withdrawalCooldownPeriod")
            )
        );

        withdrawManagerProxy = _deployProxy("withdrawManagerProxy", address(withdrawManagerImpl),
            abi.encodeWithSelector(
                WithdrawManager.initialize.selector,
                config.readUint(".withdrawals.minWithdrawalAmount"),
                config.readUint(".withdrawals.maxWithdrawalAmount"),
                config.readUint(".withdrawals.lowWatermarkInBpsOfTvl"),
                config.readUint(".withdrawals.instantWithdrawalFeeInBps"),
                address(roleRegistryProxy),
                address(beHYPEProxy),
                address(stakingCoreProxy),
                config.readUint(".withdrawals.bucketCapacity"),
                config.readUint(".withdrawals.bucketRefillRate")
            )
        );
    }



    function _deployTimelock() private {
        // Deploy timelock directly (no proxy needed)
        address[] memory proposers = new address[](1);
        proposers[0] = config.readAddress(".roles.admin");
        
        address[] memory executors = new address[](1);
        executors[0] = config.readAddress(".roles.admin");

        timelock = new BeHYPETimelock(
            config.readUint(".timelock.minDelay"),
            proposers,
            executors,
            config.readAddress(".roles.admin")
        );

        // Write timelock address to config
        vm.writeJson(vm.toString(address(timelock)), configPath, ".deployed.timelock");
    }

    function _setupInitialRoles() private {
        // Cast proxies to contract interfaces
        roleRegistry = RoleRegistry(address(roleRegistryProxy));
        beHYPE = BeHYPE(address(beHYPEProxy));
        stakingCore = StakingCore(payable(address(stakingCoreProxy)));
        withdrawManager = WithdrawManager(payable(address(withdrawManagerProxy)));

        // Update role registry with actual contract addresses
        roleRegistry.setWithdrawManager(address(withdrawManagerProxy));
        roleRegistry.setStakingCore(address(stakingCoreProxy));

        // Grant initial roles
        roleRegistry.grantRole(roleRegistry.PROTOCOL_ADMIN(), config.readAddress(".roles.admin"));
        roleRegistry.grantRole(roleRegistry.PROTOCOL_GUARDIAN(), config.readAddress(".roles.guardian"));
        roleRegistry.grantRole(roleRegistry.PROTOCOL_PAUSER(), config.readAddress(".roles.admin"));

        // Update BeHYPE with actual contract addresses
        beHYPE.setStakingCore(address(stakingCoreProxy));
        beHYPE.setWithdrawManager(address(withdrawManagerProxy));

        // Update StakingCore with actual withdraw manager address
        stakingCore.setWithdrawManager(address(withdrawManagerProxy));
    }

    function _logDeployments() private view {
        console.log("\n=== Deployed Contracts ===");
        console.log("RoleRegistry:", address(roleRegistryProxy));
        console.log("BeHYPE:", address(beHYPEProxy));
        console.log("StakingCore:", address(stakingCoreProxy));
        console.log("WithdrawManager:", address(withdrawManagerProxy));
        console.log("BeHYPETimelock:", address(timelock));

        console.log("\n=== Roles ===");
        console.log("Admin:", config.readAddress(".roles.admin"));
        console.log("Guardian:", config.readAddress(".roles.guardian"));
        console.log("Protocol Treasury:", config.readAddress(".roles.protocolTreasury"));

        console.log("\n=== Token Configuration ===");
        console.log("Token Name:", config.readString(".token.name"));
        console.log("Token Symbol:", config.readString(".token.symbol"));

        console.log("\n=== Staking Configuration ===");
        console.log("Acceptable APR:", config.readUint(".staking.acceptableAprInBps"), "bps");
        console.log("Exchange Rate Guard:", config.readBool(".staking.exchangeRateGuard"));
        console.log("Withdrawal Cooldown:", config.readUint(".staking.withdrawalCooldownPeriod"), "seconds");

        console.log("\n=== Withdrawal Configuration ===");
        console.log("Min Withdrawal:", config.readUint(".withdrawals.minWithdrawalAmount"), "wei");
        console.log("Max Withdrawal:", config.readUint(".withdrawals.maxWithdrawalAmount"), "wei");
        console.log("Low Watermark:", config.readUint(".withdrawals.lowWatermarkInBpsOfTvl"), "bps");
        console.log("Instant Withdrawal Fee:", config.readUint(".withdrawals.instantWithdrawalFeeInBps"), "bps");
        console.log("Bucket Capacity:", config.readUint(".withdrawals.bucketCapacity"), "wei");
        console.log("Bucket Refill Rate:", config.readUint(".withdrawals.bucketRefillRate"), "per second");

        console.log("\n=== Timelock Configuration ===");
        console.log("Min Delay:", config.readUint(".timelock.minDelay"), "seconds");
    }
}
