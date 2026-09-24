// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// UC-UFXX: Control Credit Settlement
// T-003: The admin sets the credit maximum, pauses the settler, and recovers stray tokens
// Integration tests driven through the settler's admin controls over the real exchange and
// Conditional Tokens bytecode, so a maximum change is proved against real settlements and a
// recovery against real token balances.

import {PromoSettlerFixture} from "../../fixtures/PromoSettlerFixture.sol";
import {PromoSettler} from "../../../src/PromoSettler.sol";
import {Order} from "exchange/libraries/OrderStructs.sol";

contract ControlCreditSettlementTest is PromoSettlerFixture {
    address internal stranger = makeAddr("stranger");

    // ──────────────────────────────────────────────
    // SC-UFYL: The admin sets the credit maximum
    // ──────────────────────────────────────────────

    // SC-UFYL: A lower maximum keeps a credit in progress and bounds new credits
    //
    // Credit sizes change between campaigns. A lower maximum stops new large credits without
    // cutting one in progress: the record for S and C fixed its 5,000,000 total before the
    // change, so its remaining 3,000,000 still settle, and a new total of 1,000,001 is one unit
    // above the new 1,000,000 maximum.
    function test_lowerMaximumKeepsARecordedCreditAndBoundsNewCredits() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        _settleTaker(5_000_000, 2_000_000, userBuy, houseSell, 2_000_000, 4_000_000);

        vm.expectEmit(address(settler));
        emit PromoSettler.MaxCreditUnitsUpdated(10_000_000, 1_000_000);
        vm.prank(admin);
        settler.setMaxCreditUnits(1_000_000);
        assertEq(settler.maxCreditUnits(), 1_000_000);

        _settleTaker(5_000_000, 3_000_000, userBuy, houseSell, 3_000_000, 6_000_000);
        (uint128 total, uint128 spent) = _record();
        assertEq(total, 5_000_000);
        assertEq(spent, 5_000_000);

        Order memory otherBuy = _userBuy(yesId, 1_000_000, 2_000_000, 0);
        Order memory otherSell = _houseSell(yesId, 2_000_000, 1_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(otherSell, 2_000_000);
        vm.prank(operator);
        vm.expectRevert(PromoSettler.CreditTotalAboveMaximum.selector);
        settler.settle(keccak256("another-code"), 1_000_001, 1_000_000, 0, otherBuy, makers, 1_000_000, makerFills);
    }

    // SC-UFYL: A zero maximum is refused
    //
    // A zero maximum would refuse every new credit with a misleading error. The pause is the
    // control that stops settlement.
    function test_zeroMaximumIsRefused() public {
        vm.prank(admin);
        vm.expectRevert(PromoSettler.ZeroMaxCredit.selector);
        settler.setMaxCreditUnits(0);
        assertEq(settler.maxCreditUnits(), MAX_CREDIT);
    }

    // ──────────────────────────────────────────────
    // SC-UFYM: The admin pauses and unpauses the settler
    // ──────────────────────────────────────────────

    // SC-UFYM: The admin pauses and unpauses the settler
    //
    // The pause stops promo spending without the promo wallet key and without touching the
    // exchange. The flag follows each call, and each call names the admin in its event.
    function test_adminPausesAndUnpausesTheSettler() public {
        assertFalse(settler.paused());

        vm.expectEmit(address(settler));
        emit PromoSettler.Paused(admin);
        vm.prank(admin);
        settler.pause();
        assertTrue(settler.paused());

        vm.expectEmit(address(settler));
        emit PromoSettler.Unpaused(admin);
        vm.prank(admin);
        settler.unpause();
        assertFalse(settler.paused());
        assertEq(usdc.balanceOf(promoWallet), PROMO_FUND);
    }

    // ──────────────────────────────────────────────
    // SC-UFYN: The admin recovers stray USDC to the promo wallet
    // ──────────────────────────────────────────────

    // SC-UFYN: The admin recovers stray USDC to the promo wallet
    //
    // The settler holds nothing at rest, so stray USDC is a donation or a mistake. recover(0)
    // sends the whole 700,000 units to the promo wallet and none to the admin.
    function test_adminRecoversStrayUsdcToThePromoWallet() public {
        usdc.mint(address(settler), 700_000);

        vm.expectEmit(address(settler));
        emit PromoSettler.Recovered(0, 700_000);
        vm.prank(admin);
        settler.recover(0);

        assertEq(usdc.balanceOf(address(settler)), 0);
        assertEq(usdc.balanceOf(promoWallet), PROMO_FUND + 700_000);
        assertEq(usdc.balanceOf(admin), 0);
    }

    // ──────────────────────────────────────────────
    // SC-UFYO: The admin recovers a stray outcome token to the promo wallet
    // ──────────────────────────────────────────────

    // SC-UFYO: The admin recovers a stray outcome token to the promo wallet
    //
    // The receiver hook accepts any token the Conditional Tokens contract sends, so a holder can
    // place shares in the settler outside a settlement. recover(yesId) sends all 300,000 to the
    // promo wallet.
    function test_adminRecoversAStrayOutcomeTokenToThePromoWallet() public {
        address holder = makeAddr("holder");
        _mintCompleteSets(usdc, holder, conditionId, 300_000);
        vm.prank(holder);
        ctf.safeTransferFrom(holder, address(settler), yesId, 300_000, "");

        vm.expectEmit(address(settler));
        emit PromoSettler.Recovered(yesId, 300_000);
        vm.prank(admin);
        settler.recover(yesId);

        assertEq(ctf.balanceOf(address(settler), yesId), 0);
        assertEq(ctf.balanceOf(promoWallet, yesId), 300_000);
    }

    // ──────────────────────────────────────────────
    // SC-UFYP: Recovery of a zero balance is refused
    // ──────────────────────────────────────────────

    // SC-UFYP: Recovery of a zero balance is refused
    //
    // A Recovered event for a transfer that did not happen would mislead the reconciliation
    // that reads it, so a zero balance reverts for USDC and for an outcome token alike.
    function test_recoveryOfAZeroBalanceIsRefused() public {
        vm.startPrank(admin);
        vm.expectRevert(PromoSettler.NothingToRecover.selector);
        settler.recover(0);
        vm.expectRevert(PromoSettler.NothingToRecover.selector);
        settler.recover(noId);
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────
    // SC-UFYQ: A caller outside the admins cannot use the controls
    // ──────────────────────────────────────────────

    // SC-UFYQ: A caller outside the admins cannot use the controls
    //
    // Each control reverts with NotAdmin for an address with admins(address) = 0, and the
    // maximum, the flag, and the settler's 700,000 stray units stay where they were.
    function test_callerOutsideTheAdminsCannotUseTheControls() public {
        usdc.mint(address(settler), 700_000);

        vm.startPrank(stranger);
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.setMaxCreditUnits(1);
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.pause();
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.unpause();
        vm.expectRevert(PromoSettler.NotAdmin.selector);
        settler.recover(0);
        vm.stopPrank();

        assertEq(settler.maxCreditUnits(), MAX_CREDIT);
        assertFalse(settler.paused());
        assertEq(usdc.balanceOf(address(settler)), 700_000);
    }
}
