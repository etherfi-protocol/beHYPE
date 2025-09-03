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
import "../src/interfaces/ICreate3Deployer.sol";

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
    
    
    ICreate3Deployer public create3Deployer;

    /*
    * forge script script/Deploy.s.sol:DeployCore \
    * --rpc-url $NETWORK \
    * --ledger \
    * --sender 0xd8F3803d8412e61e04F53e1C9394e13eC8b32550 \
    * --broadcast \
    * --verify \
    * --etherscan-api-key $ETH_ETHERSCAN_KEY \
    * --sig "run(bool)" true
    */
    function run(bool _isMainnet) external {
        configPath = _isMainnet ? "config/production.json" : "config/testnet.json";

        config = vm.readFile(configPath);
        
        create3Deployer = ICreate3Deployer(config.readAddress(".addresses.Create3Deployer"));

        vm.startBroadcast();

        _deployProxies();

        _deployTimelock();

        _setupInitialRoles();

        _logDeployments();
    }
    


    function _deployProxy(string memory contractName, address implementation, bytes memory initData) private returns (UUPSProxy proxy) {
        
        address deployedAddress = create3Deployer.deployCreate3(
            keccak256(bytes(contractName)),
            abi.encodePacked(
                type(UUPSProxy).creationCode,
                abi.encode(address(implementation), initData)
            )
        );
        
        address expectedAddress = config.readAddress(string.concat(".addresses.", contractName));
        if (deployedAddress != expectedAddress) {
            revert(string(abi.encodePacked(
                "Address mismatch for ", contractName, 
                ": expected ", vm.toString(expectedAddress), 
                ", got ", vm.toString(deployedAddress)
            )));
        }
        
        proxy = UUPSProxy(payable(deployedAddress));
    }

    function _deployProxies() private {
        RoleRegistry roleRegistryImpl = new RoleRegistry();
        BeHYPE beHYPEImpl = new BeHYPE();
        StakingCore stakingCoreImpl = new StakingCore();
        WithdrawManager withdrawManagerImpl = new WithdrawManager();

        roleRegistryProxy = _deployProxy("RoleRegistry", address(roleRegistryImpl), 
            abi.encodeWithSelector(
                RoleRegistry.initialize.selector,
                msg.sender, // start as the deployer for setting the initial roles
                config.readAddress(".addresses.WithdrawManager"),
                config.readAddress(".addresses.StakingCore"),
                config.readAddress(".roles.protocolTreasury")
            )
        );

        beHYPEProxy = _deployProxy("BeHYPE", address(beHYPEImpl),
            abi.encodeWithSelector(
                BeHYPE.initialize.selector,
                config.readString(".token.name"),
                config.readString(".token.symbol"),
                config.readAddress(".addresses.RoleRegistry"),
                config.readAddress(".addresses.StakingCore"),
                config.readAddress(".addresses.WithdrawManager")
            )
        );

        stakingCoreProxy = _deployProxy("StakingCore", address(stakingCoreImpl),
            abi.encodeWithSelector(
                StakingCore.initialize.selector,
                config.readAddress(".addresses.RoleRegistry"),
                config.readAddress(".addresses.BeHYPE"),
                config.readAddress(".addresses.WithdrawManager"),
                config.readUint(".staking.acceptableAprInBps"),
                config.readBool(".staking.exchangeRateGuard"),
                config.readUint(".staking.withdrawalCooldownPeriod")
            )
        );

        withdrawManagerProxy = _deployProxy("WithdrawManager", address(withdrawManagerImpl),
            abi.encodeWithSelector(
                WithdrawManager.initialize.selector,
                config.readUint(".withdrawals.minWithdrawalAmount"),
                config.readUint(".withdrawals.maxWithdrawalAmount"),
                config.readUint(".withdrawals.lowWatermarkInBpsOfTvl"),
                config.readUint(".withdrawals.instantWithdrawalFeeInBps"),
                config.readAddress(".addresses.RoleRegistry"),
                config.readAddress(".addresses.BeHYPE"),
                config.readAddress(".addresses.StakingCore"),
                config.readUint(".withdrawals.bucketCapacity"),
                config.readUint(".withdrawals.bucketRefillRate")
            )
        );
    }

    function _deployTimelock() private {
        address[] memory proposers = new address[](1);
        proposers[0] = config.readAddress(".roles.guardian");
        
        address[] memory executors = new address[](1);
        executors[0] = config.readAddress(".roles.guardian");
        
        address deployedAddress = create3Deployer.deployCreate3(
            keccak256(bytes(string("BeHYPETimelock"))),
            abi.encodePacked(
                type(BeHYPETimelock).creationCode,
                abi.encode(
                    config.readUint(".timelock.minDelay"),
                    proposers,
                    executors,
                    address(0) // admin of the timelock is the timelock itself
                )
            )
        );
        
        address expectedAddress = config.readAddress(".addresses.BeHYPETimelock");
        if (deployedAddress != expectedAddress) {
            revert(string(abi.encodePacked(
                "Address mismatch for BeHYPETimelock", 
                ": expected ", vm.toString(expectedAddress), 
                ", got ", vm.toString(deployedAddress)
            )));
        }
        
        timelock = BeHYPETimelock(payable(deployedAddress));
    }

    function _setupInitialRoles() private {
        roleRegistry = RoleRegistry(address(roleRegistryProxy));

        roleRegistry.grantRole(roleRegistry.PROTOCOL_ADMIN(), config.readAddress(".roles.admin"));
        roleRegistry.grantRole(roleRegistry.PROTOCOL_GUARDIAN(), config.readAddress(".roles.guardian"));
        roleRegistry.grantRole(roleRegistry.PROTOCOL_PAUSER(), config.readAddress(".roles.admin"));
        roleRegistry.grantRole(roleRegistry.PROTOCOL_PAUSER(), config.readAddress(".roles.pauser"));

        roleRegistry.transferOwnership(config.readAddress(".addresses.BeHYPETimelock"));
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
        console.log("Bucket Refill Rate:", config.readUint(".withdrawals.bucketRefillRate"), "wei per second");

        console.log("\n=== Timelock Configuration ===");
        console.log("Min Delay:", config.readUint(".timelock.minDelay"), "seconds");
    }
}
