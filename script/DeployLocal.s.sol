// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// FEAT-UFXU: Settler Deployment
// UC-UFXZ: Deploy the Settler to Local Anvil

import {Script, console} from "forge-std/Script.sol";
import {PromoSettler} from "../src/PromoSettler.sol";

/// @dev The local exchange call the script makes. On Anvil the deployer is the exchange admin.
interface ILocalExchange {
    function addOperator(address operator) external;
}

/// @dev The local TestUSDC calls the script makes. `mint` is owner-only, and the deployer owns it.
interface ILocalUSDC {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @param addressesPath       The local addresses file the meta project wrote. The script adds
///                            `promoSettler` to it.
/// @param exchange            The local ProphetCTFExchange, from the file's `exchange` key.
/// @param promoWallet         The local promo wallet. It approves the settler in a second
///                            broadcast, signed with its own local key.
/// @param maxCreditUnits      The settler's first credit maximum, in USDC raw units.
/// @param localPromoFundUnits The TestUSDC minted to the promo wallet and approved to the settler.
struct LocalConfig {
    string addressesPath;
    address exchange;
    address promoWallet;
    uint256 maxCreditUnits;
    uint256 localPromoFundUnits;
}

/// @title DeployLocal
/// @notice Deploys, registers, funds, and publishes PromoSettler on the local Anvil chain, as the
///         third step of the server's `make deploy-local`.
/// @dev Usage, from contracts/lib/promo-settler in the server repository:
///        forge script script/DeployLocal.s.sol --sig "run()" --rpc-url $RPC_URL --broadcast \
///          --private-keys $DEPLOYER_PK --private-keys $PROMO_PK
///      Forge signs each broadcast with the key of its address. The script reads no private key.
contract DeployLocal is Script {
    /// @dev The server's harness runs Anvil at the Amoy chain ID.
    uint256 internal constant LOCAL_CHAIN_ID = 80002;

    error UnexpectedChainId(uint256 got, uint256 expected);
    /// @dev A required value is zero or missing. `name` is the variable or file key to set.
    error ZeroAddress(string name);
    error ZeroMaxCreditUnits();
    error MaxCreditUnitsTooLarge();
    error ZeroFundUnits();

    // SC-UFYV: CLI entry point, the deployer comes from the addresses file
    function run() external returns (PromoSettler settler) {
        (LocalConfig memory cfg, address deployer) = _configFromEnv();
        settler = _run(deployer, cfg);
    }

    // SC-UFYV: test entry point, configuration from the environment and the addresses file
    function run(address deployer) external returns (PromoSettler settler) {
        (LocalConfig memory cfg,) = _configFromEnv();
        settler = _run(deployer, cfg);
    }

    // SC-UFYU, SC-UFYW: test entry point, configuration passed directly
    function run(address deployer, LocalConfig memory cfg) external returns (PromoSettler settler) {
        settler = _run(deployer, cfg);
    }

    // SC-UFYV: the only function that reads the environment (ADR-UFZG)
    /// @dev Reads the exchange and the deployer from the addresses file, and the other values
    ///      from the environment. envOr turns a missing variable into zero, so _validate reports
    ///      it by name.
    function _configFromEnv() internal view returns (LocalConfig memory cfg, address deployer) {
        cfg.addressesPath = vm.envString("ADDRESSES_JSON_PATH");
        string memory json = vm.readFile(cfg.addressesPath);
        cfg.exchange = vm.parseJsonAddress(json, ".exchange");
        deployer = vm.parseJsonAddress(json, ".deployer");
        cfg.promoWallet = vm.envOr("PROMO_WALLET_ADDRESS", address(0));
        cfg.maxCreditUnits = vm.envOr("MAX_CREDIT_UNITS", uint256(0));
        cfg.localPromoFundUnits = vm.envOr("LOCAL_PROMO_FUND_UNITS", uint256(0));
    }

    // SC-UFYU, SC-UFYW: check the chain and the values, deploy, then publish
    /// @dev The two broadcasts sign as different keys: the deployer deploys, registers, and
    ///      mints, and the promo wallet approves. The file write comes last, so a failed deploy
    ///      leaves the addresses file unchanged.
    function _run(address deployer, LocalConfig memory cfg) internal returns (PromoSettler settler) {
        if (block.chainid != LOCAL_CHAIN_ID) revert UnexpectedChainId(block.chainid, LOCAL_CHAIN_ID);
        _validate(cfg);

        vm.startBroadcast(deployer);
        settler = new PromoSettler(cfg.exchange, cfg.promoWallet, deployer, deployer, uint128(cfg.maxCreditUnits));
        ILocalExchange(cfg.exchange).addOperator(address(settler));
        // The settler read its USDC from the exchange, so the mint and the approval use the same
        // token the settler pulls from.
        ILocalUSDC(settler.usdc()).mint(cfg.promoWallet, cfg.localPromoFundUnits);
        vm.stopBroadcast();

        vm.startBroadcast(cfg.promoWallet);
        ILocalUSDC(settler.usdc()).approve(address(settler), cfg.localPromoFundUnits);
        vm.stopBroadcast();

        // FR-UFZ6: add promoSettler to the file and keep every other key.
        vm.writeJson(vm.toString(address(settler)), cfg.addressesPath, ".promoSettler");

        console.log("PromoSettler:", address(settler));
        console.log("Promo wallet funded and approved:", cfg.localPromoFundUnits);
        console.log("Addresses file:", cfg.addressesPath);
    }

    /// @dev Runs before the broadcast starts, so a bad configuration creates nothing and leaves
    ///      no broadcast open.
    function _validate(LocalConfig memory cfg) internal pure {
        if (cfg.exchange == address(0)) revert ZeroAddress("exchange");
        if (cfg.promoWallet == address(0)) revert ZeroAddress("PROMO_WALLET_ADDRESS");
        if (cfg.maxCreditUnits == 0) revert ZeroMaxCreditUnits();
        if (cfg.maxCreditUnits > type(uint128).max) revert MaxCreditUnitsTooLarge();
        if (cfg.localPromoFundUnits == 0) revert ZeroFundUnits();
    }
}
