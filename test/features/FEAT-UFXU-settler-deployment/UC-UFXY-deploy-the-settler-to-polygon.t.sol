// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// UC-UFXY: Deploy the Settler to Polygon
// T-004: The deployer deploys the settler to Polygon
// Integration tests driven through Deploy.run over the real exchange bytecode, so the settler
// reads its USDC and Conditional Tokens addresses from a real exchange.

import {PromoSettlerFixture} from "../../fixtures/PromoSettlerFixture.sol";
import {PromoSettler} from "../../../src/PromoSettler.sol";
import {Deploy, DeployConfig} from "../../../script/Deploy.s.sol";

contract DeployTheSettlerToPolygonTest is PromoSettlerFixture {
    Deploy internal script;
    address internal deployer = makeAddr("deployer");

    function setUp() public override {
        super.setUp();
        script = new Deploy();
    }

    function _config() internal view returns (DeployConfig memory) {
        return DeployConfig({
            exchange: address(exchange),
            promoWallet: promoWallet,
            admin: admin,
            operator: operator,
            maxCreditUnits: MAX_CREDIT
        });
    }

    /// @dev Every value the configuration names, read back from the deployed settler.
    function _assertMatchesConfig(PromoSettler deployed) internal view {
        assertEq(deployed.exchange(), address(exchange));
        assertEq(deployed.promoWallet(), promoWallet);
        assertEq(deployed.usdc(), exchange.getCollateral());
        assertEq(deployed.usdc(), address(usdc));
        assertEq(deployed.ctf(), exchange.getCtf());
        assertEq(deployed.ctf(), address(ctf));
        assertEq(deployed.admins(admin), 1);
        assertEq(deployed.adminCount(), 1);
        assertEq(deployed.operators(operator), 1);
        assertEq(deployed.maxCreditUnits(), MAX_CREDIT);
        assertFalse(deployed.paused());
    }

    // ──────────────────────────────────────────────
    // SC-UFYR: Deploy with a complete configuration
    // ──────────────────────────────────────────────

    // SC-UFYR: Deploy with a complete configuration
    //
    // The settler reads USDC and the Conditional Tokens address from the exchange, which removes
    // two deploy values that could disagree with it. The deploy grants no exchange role and no
    // USDC approval: DEPLOYMENT.md has other keys perform both.
    function test_deployWithACompleteConfigurationMatchesIt() public {
        PromoSettler deployed = script.run(deployer, _config());

        _assertMatchesConfig(deployed);
        assertFalse(exchange.isOperator(address(deployed)));
        assertEq(usdc.allowance(promoWallet, address(deployed)), 0);
    }

    // ──────────────────────────────────────────────
    // SC-UFYS: Deploy reads its configuration from the environment
    // ──────────────────────────────────────────────

    // SC-UFYS: Deploy reads its configuration from the environment
    //
    // _configFromEnv is the only reader of the environment. The five variables produce the same
    // settler that the struct overload produces.
    function test_deployReadsItsConfigurationFromTheEnvironment() public {
        vm.setEnv("EXCHANGE_ADDRESS", vm.toString(address(exchange)));
        vm.setEnv("PROMO_WALLET_ADDRESS", vm.toString(promoWallet));
        vm.setEnv("ADMIN_ADDRESS", vm.toString(admin));
        vm.setEnv("OPERATOR_ADDRESS", vm.toString(operator));
        vm.setEnv("MAX_CREDIT_UNITS", "10000000");

        PromoSettler deployed = script.run(deployer);

        _assertMatchesConfig(deployed);
    }

    // ──────────────────────────────────────────────
    // SC-UFYT: A missing or zero value is refused
    // ──────────────────────────────────────────────

    // SC-UFYT: Each zero address is refused by the name of its variable
    //
    // The error names the variable to set, so the deployer fixes the environment without
    // reading the script.
    function test_eachZeroAddressIsRefusedByName() public {
        DeployConfig memory cfg = _config();
        cfg.exchange = address(0);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ZeroAddress.selector, "EXCHANGE_ADDRESS"));
        script.run(deployer, cfg);

        cfg = _config();
        cfg.promoWallet = address(0);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ZeroAddress.selector, "PROMO_WALLET_ADDRESS"));
        script.run(deployer, cfg);

        cfg = _config();
        cfg.admin = address(0);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ZeroAddress.selector, "ADMIN_ADDRESS"));
        script.run(deployer, cfg);

        cfg = _config();
        cfg.operator = address(0);
        vm.expectRevert(abi.encodeWithSelector(Deploy.ZeroAddress.selector, "OPERATOR_ADDRESS"));
        script.run(deployer, cfg);
    }

    // SC-UFYT: A zero or out-of-range credit maximum is refused
    //
    // The settler stores the maximum as uint128. 2^128 would wrap to 0 in a silent cast, so the
    // script refuses it before the cast.
    function test_zeroOrOutOfRangeMaximumIsRefused() public {
        DeployConfig memory cfg = _config();
        cfg.maxCreditUnits = 0;
        vm.expectRevert(Deploy.ZeroMaxCreditUnits.selector);
        script.run(deployer, cfg);

        cfg.maxCreditUnits = uint256(type(uint128).max) + 1;
        vm.expectRevert(Deploy.MaxCreditUnitsTooLarge.selector);
        script.run(deployer, cfg);
    }

    // SC-UFYT: The settler's constructor refuses a zero address or a zero maximum
    //
    // A direct deployment skips the script's checks, so the constructor holds its own.
    function test_constructorRefusesAZeroValue() public {
        address ex = address(exchange);
        vm.expectRevert(PromoSettler.ZeroAddress.selector);
        new PromoSettler(address(0), promoWallet, admin, operator, MAX_CREDIT);
        vm.expectRevert(PromoSettler.ZeroAddress.selector);
        new PromoSettler(ex, address(0), admin, operator, MAX_CREDIT);
        vm.expectRevert(PromoSettler.ZeroAddress.selector);
        new PromoSettler(ex, promoWallet, address(0), operator, MAX_CREDIT);
        vm.expectRevert(PromoSettler.ZeroAddress.selector);
        new PromoSettler(ex, promoWallet, admin, address(0), MAX_CREDIT);
        vm.expectRevert(PromoSettler.ZeroMaxCredit.selector);
        new PromoSettler(ex, promoWallet, admin, operator, 0);
    }
}
