// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// FEAT-UFXU: Settler Deployment
// UC-UFXY: Deploy the Settler to Polygon

import {Script, console} from "forge-std/Script.sol";
import {PromoSettler} from "../src/PromoSettler.sol";

/// @param exchange       ProphetCTFExchange on the target chain. The settler reads USDC and the
///                       Conditional Tokens address from it.
/// @param promoWallet    The EOA that funds every credit and receives every recovered token.
///                       Immutable in the settler.
/// @param admin          The first settler admin.
/// @param operator       The first settler operator: the server's operator EOA, which the
///                       exchange already lists as an operator.
/// @param maxCreditUnits The first credit maximum in USDC raw units (1,000,000 = $1.00). Held as
///                       uint256 so an out-of-range environment value fails loudly instead of
///                       wrapping when the script narrows it to the settler's uint128.
struct DeployConfig {
    address exchange;
    address promoWallet;
    address admin;
    address operator;
    uint256 maxCreditUnits;
}

/// @title Deploy
/// @notice Deploys PromoSettler to Polygon mainnet (137) or Amoy (80002). Only --rpc-url and
///         the environment change between the two.
/// @dev Usage:
///        forge script script/Deploy.s.sol --sig "run()" --account <name> --sender <address> \
///          --rpc-url $RPC_URL --broadcast
///      Signing uses Foundry's CLI flags (--account, --ledger, --trezor). No private key is read
///      from the environment. DEPLOYMENT.md lists the two follow-up actions other keys perform.
contract Deploy is Script {
    /// @dev A required value is zero or missing. `name` is the environment variable to set.
    error ZeroAddress(string name);
    error ZeroMaxCreditUnits();
    error MaxCreditUnitsTooLarge();

    // SC-UFYS: CLI entry point, signer from the CLI flags
    function run() external returns (PromoSettler settler) {
        DeployConfig memory cfg = _configFromEnv();
        _validate(cfg);
        vm.startBroadcast();
        settler = _deploy(cfg);
        vm.stopBroadcast();
    }

    // SC-UFYS: test entry point, broadcasts as `deployer`, configuration from the environment
    function run(address deployer) external returns (PromoSettler settler) {
        DeployConfig memory cfg = _configFromEnv();
        _validate(cfg);
        vm.startBroadcast(deployer);
        settler = _deploy(cfg);
        vm.stopBroadcast();
    }

    // SC-UFYR, SC-UFYT: test entry point, configuration passed directly
    function run(address deployer, DeployConfig memory cfg) external returns (PromoSettler settler) {
        _validate(cfg);
        vm.startBroadcast(deployer);
        settler = _deploy(cfg);
        vm.stopBroadcast();
    }

    // SC-UFYS: the only function that reads the environment (ADR-UFZG)
    /// @dev envOr turns a missing variable into zero, so _validate reports it by name instead of
    ///      Foundry's generic missing-variable error.
    function _configFromEnv() internal view returns (DeployConfig memory) {
        return DeployConfig({
            exchange: vm.envOr("EXCHANGE_ADDRESS", address(0)),
            promoWallet: vm.envOr("PROMO_WALLET_ADDRESS", address(0)),
            admin: vm.envOr("ADMIN_ADDRESS", address(0)),
            operator: vm.envOr("OPERATOR_ADDRESS", address(0)),
            maxCreditUnits: vm.envOr("MAX_CREDIT_UNITS", uint256(0))
        });
    }

    // SC-UFYT, FR-UFZ5: refuse a zero or out-of-range value by name
    /// @dev Runs before the broadcast starts, so a bad configuration creates nothing and leaves
    ///      no broadcast open.
    function _validate(DeployConfig memory cfg) internal pure {
        if (cfg.exchange == address(0)) revert ZeroAddress("EXCHANGE_ADDRESS");
        if (cfg.promoWallet == address(0)) revert ZeroAddress("PROMO_WALLET_ADDRESS");
        if (cfg.admin == address(0)) revert ZeroAddress("ADMIN_ADDRESS");
        if (cfg.operator == address(0)) revert ZeroAddress("OPERATOR_ADDRESS");
        if (cfg.maxCreditUnits == 0) revert ZeroMaxCreditUnits();
        if (cfg.maxCreditUnits > type(uint128).max) revert MaxCreditUnitsTooLarge();
    }

    // SC-UFYR: deploy the settler from a validated configuration and log what it holds
    /// @dev The caller owns the broadcast context.
    function _deploy(DeployConfig memory cfg) internal returns (PromoSettler settler) {
        settler = new PromoSettler(cfg.exchange, cfg.promoWallet, cfg.admin, cfg.operator, uint128(cfg.maxCreditUnits));

        console.log("Chain ID:", block.chainid);
        console.log("PromoSettler:", address(settler));
        console.log("Exchange:", settler.exchange());
        console.log("USDC (from the exchange):", settler.usdc());
        console.log("Conditional Tokens (from the exchange):", settler.ctf());
        console.log("Promo wallet:", settler.promoWallet());
        console.log("Admin:", cfg.admin);
        console.log("Operator:", cfg.operator);
        console.log("Max credit units:", cfg.maxCreditUnits);
    }
}
