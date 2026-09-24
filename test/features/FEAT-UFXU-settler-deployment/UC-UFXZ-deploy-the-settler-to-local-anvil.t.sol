// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// UC-UFXZ: Deploy the Settler to Local Anvil
// T-005: The deployer deploys the settler to local Anvil and publishes its address
// Integration tests driven through DeployLocal.run over the real exchange bytecode. Each test
// writes its own scratch addresses file under the git-ignored ./tmp/, so no test reads or
// changes the harness file (ADR-UFZI).

import {PromoSettlerFixture} from "../../fixtures/PromoSettlerFixture.sol";
import {IProphetCTFExchange} from "../../fixtures/ExchangeFixture.sol";
import {MockERC20} from "../../fixtures/MockERC20.sol";
import {PromoSettler} from "../../../src/PromoSettler.sol";
import {DeployLocal, LocalConfig} from "../../../script/DeployLocal.s.sol";

contract DeployTheSettlerToLocalAnvilTest is PromoSettlerFixture {
    uint256 internal constant FUND_UNITS = 100_000_000;

    DeployLocal internal script;
    address internal deployer = makeAddr("local-deployer");
    address internal localPromoWallet = makeAddr("local-promo-wallet");

    function setUp() public override {
        super.setUp();
        script = new DeployLocal();
        // On Anvil the deployer is the exchange admin, so it can register the settler.
        exchange.addAdmin(deployer);
        vm.createDir("./tmp", true);
    }

    /// @dev Writes a scratch addresses file with the three keys the meta project writes.
    function _writeAddressesFile(string memory path) internal {
        vm.serializeAddress("addresses", "exchange", address(exchange));
        vm.serializeAddress("addresses", "usdc", address(usdc));
        string memory json = vm.serializeAddress("addresses", "deployer", deployer);
        vm.writeJson(json, path);
    }

    function _config(string memory path) internal view returns (LocalConfig memory) {
        return LocalConfig({
            addressesPath: path,
            exchange: address(exchange),
            promoWallet: localPromoWallet,
            maxCreditUnits: MAX_CREDIT,
            localPromoFundUnits: FUND_UNITS
        });
    }

    /// @dev The four outcomes of a completed local deploy, read from the chain and the file.
    function _assertPublished(PromoSettler deployed, string memory path) internal view {
        assertTrue(exchange.isOperator(address(deployed)), "exchange lists the settler");
        assertEq(usdc.balanceOf(localPromoWallet), FUND_UNITS, "promo wallet funded");
        assertEq(usdc.allowance(localPromoWallet, address(deployed)), FUND_UNITS, "promo wallet approved");
        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonAddress(json, ".promoSettler"), address(deployed), "published address");
        assertEq(vm.parseJsonAddress(json, ".exchange"), address(exchange), "exchange key kept");
        assertEq(vm.parseJsonAddress(json, ".usdc"), address(usdc), "usdc key kept");
        assertEq(vm.parseJsonAddress(json, ".deployer"), deployer, "deployer key kept");
    }

    // ──────────────────────────────────────────────
    // SC-UFYU: The local deploy registers, funds, approves, and publishes the settler
    // ──────────────────────────────────────────────

    // SC-UFYU: The local deploy registers, funds, approves, and publishes the settler
    //
    // The server's harness needs a settler it can call at once: registered on the exchange, with
    // a funded promo wallet that approves it, and listed in the addresses file beside the other
    // local contracts. The deployer is the settler's first admin and operator.
    function test_localDeployRegistersFundsApprovesAndPublishesTheSettler() public {
        string memory path = "./tmp/UC-UFXZ-register-fund-publish.json";
        _writeAddressesFile(path);
        vm.chainId(80002);
        // The deployer's next CREATE address is the settler the script deploys.
        address expected = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

        vm.expectEmit(address(exchange));
        emit IProphetCTFExchange.NewOperator(expected, deployer);
        vm.expectEmit(address(usdc));
        emit MockERC20.Approval(localPromoWallet, expected, FUND_UNITS);
        PromoSettler deployed = script.run(deployer, _config(path));
        assertEq(address(deployed), expected);

        _assertPublished(deployed, path);
        assertEq(deployed.admins(deployer), 1);
        assertEq(deployed.operators(deployer), 1);
        assertEq(deployed.maxCreditUnits(), MAX_CREDIT);
        assertEq(deployed.promoWallet(), localPromoWallet);
    }

    // ──────────────────────────────────────────────
    // SC-UFYV: The local deploy reads its configuration from the addresses file and the environment
    // ──────────────────────────────────────────────

    // SC-UFYV: The local deploy reads its configuration from the addresses file and the environment
    //
    // The Makefile passes the file path and three values through the environment. The script
    // reads the exchange from the file, so the settler always joins the stack the meta project
    // just deployed.
    function test_localDeployReadsTheAddressesFileAndTheEnvironment() public {
        string memory path = "./tmp/UC-UFXZ-from-environment.json";
        _writeAddressesFile(path);
        vm.chainId(80002);
        vm.setEnv("ADDRESSES_JSON_PATH", path);
        vm.setEnv("PROMO_WALLET_ADDRESS", vm.toString(localPromoWallet));
        vm.setEnv("MAX_CREDIT_UNITS", "10000000");
        vm.setEnv("LOCAL_PROMO_FUND_UNITS", "100000000");

        PromoSettler deployed = script.run(deployer);

        _assertPublished(deployed, path);
        assertEq(deployed.exchange(), address(exchange));
    }

    // ──────────────────────────────────────────────
    // SC-UFYW: The local deploy refuses a chain other than Amoy
    // ──────────────────────────────────────────────

    // SC-UFYW: The local deploy refuses a chain other than Amoy
    //
    // The script mints USDC and grants an exchange operator role, which must never run against
    // mainnet. It refuses before any broadcast, so nothing is created and the file keeps its
    // three keys.
    function test_localDeployRefusesAChainOtherThanAmoy() public {
        string memory path = "./tmp/UC-UFXZ-wrong-chain.json";
        _writeAddressesFile(path);
        vm.chainId(137);
        address wouldBe = vm.computeCreateAddress(deployer, vm.getNonce(deployer));

        vm.expectRevert(abi.encodeWithSelector(DeployLocal.UnexpectedChainId.selector, 137, 80002));
        script.run(deployer, _config(path));

        assertEq(wouldBe.code.length, 0, "no settler created");
        assertFalse(exchange.isOperator(wouldBe), "no exchange role granted");
        assertEq(usdc.balanceOf(localPromoWallet), 0);
        assertFalse(vm.keyExistsJson(vm.readFile(path), ".promoSettler"));
    }
}
