#!/bin/bash

# beHYPE Protocol Deployment Script
# This script deploys the beHYPE protocol to the specified network

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required environment variables are set
check_env() {
    if [ -z "$PRIVATE_KEY" ]; then
        print_error "PRIVATE_KEY environment variable is not set"
        exit 1
    fi

    if [ -z "$NETWORK" ]; then
        print_error "NETWORK environment variable is not set"
        exit 1
    fi

    if [ -z "$CONFIG_PATH" ]; then
        print_error "CONFIG_PATH environment variable is not set"
        exit 1
    fi

    if [ ! -f "$CONFIG_PATH" ]; then
        print_error "Configuration file not found: $CONFIG_PATH"
        exit 1
    fi
}

# Validate configuration file
validate_config() {
    print_status "Validating configuration file..."
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_warning "jq is not installed. Skipping configuration validation."
        return
    fi

    # Validate required fields
    required_fields=(
        "deployment.saltShift"
        "roles.admin"
        "roles.guardian"
        "roles.protocolTreasury"
        "token.name"
        "token.symbol"
        "staking.acceptableAprInBps"
        "staking.exchangeRateGuard"
        "staking.withdrawalCooldownPeriod"
        "withdrawals.minWithdrawalAmount"
        "withdrawals.maxWithdrawalAmount"
        "withdrawals.lowWatermarkInBpsOfTvl"
        "withdrawals.instantWithdrawalFeeInBps"
        "withdrawals.bucketCapacity"
        "withdrawals.bucketRefillRate"
        "timelock.minDelay"
    )

    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$CONFIG_PATH" > /dev/null 2>&1; then
            print_error "Missing required field in configuration: $field"
            exit 1
        fi
    done

    print_status "Configuration file validation passed"
}

# Deploy the protocol
deploy() {
    print_status "Starting beHYPE protocol deployment..."
    print_status "Network: $NETWORK"
    print_status "Config: $CONFIG_PATH"
    
    # Build the forge command
    cmd="forge script script/Deploy.s.sol:DeployCore --rpc-url $NETWORK --private-key $PRIVATE_KEY --broadcast --sig \"run(string)\" $CONFIG_PATH"
    
    # Add verification if ETHERSCAN_API_KEY is set
    if [ ! -z "$ETHERSCAN_API_KEY" ]; then
        cmd="$cmd --verify --etherscan-api-key $ETHERSCAN_API_KEY"
        print_status "Contract verification enabled"
    else
        print_warning "ETHERSCAN_API_KEY not set. Skipping contract verification."
    fi
    
    # Add gas settings if provided
    if [ ! -z "$GAS_LIMIT" ]; then
        cmd="$cmd --gas-limit $GAS_LIMIT"
    fi
    
    if [ ! -z "$GAS_PRICE" ]; then
        cmd="$cmd --gas-price $GAS_PRICE"
    fi
    
    # Execute deployment
    print_status "Executing deployment command..."
    eval $cmd
    
    if [ $? -eq 0 ]; then
        print_status "Deployment completed successfully!"
        print_status "Check the configuration file for deployed contract addresses."
    else
        print_error "Deployment failed!"
        exit 1
    fi
}

# Main execution
main() {
    print_status "beHYPE Protocol Deployment Script"
    print_status "=================================="
    
    check_env
    validate_config
    deploy
    
    print_status "Deployment script completed successfully!"
}

# Run main function
main "$@"
