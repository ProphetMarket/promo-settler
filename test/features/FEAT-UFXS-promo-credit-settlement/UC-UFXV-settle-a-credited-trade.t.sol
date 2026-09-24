// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// UC-UFXV: Settle a Credited Trade
// T-001: The operator settles a credited trade in one transaction
// T-003: The admin sets the credit maximum, pauses the settler, and recovers stray tokens (SC-UFYB)
// Integration tests driven through PromoSettler.settle over the real exchange and Conditional
// Tokens bytecode. Prices are 0.50 unless a scenario names another, and fees are 0 unless a
// scenario names a rate.

import {PromoSettlerFixture} from "../../fixtures/PromoSettlerFixture.sol";
import {IProphetCTFExchange} from "../../fixtures/ExchangeFixture.sol";
import {MockERC20} from "../../fixtures/MockERC20.sol";
import {PromoSettler} from "../../../src/PromoSettler.sol";
import {Order, Side, SignatureType} from "exchange/libraries/OrderStructs.sol";

contract SettleACreditedTradeTest is PromoSettlerFixture {
    // ──────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────

    /// @dev FR-UFYZ: after every settlement the settler holds no USDC and no outcome shares.
    function _assertSettlerEmpty() internal view {
        assertEq(usdc.balanceOf(address(settler)), 0, "settler USDC");
        assertEq(ctf.balanceOf(address(settler), yesId), 0, "settler YES");
        assertEq(ctf.balanceOf(address(settler), noId), 0, "settler NO");
    }

    /// @dev A refused settlement moves nothing: the promo wallet and the Safe keep their USDC.
    function _assertNothingMoved(uint256 promoBefore, uint256 safeBefore) internal view {
        assertEq(usdc.balanceOf(promoWallet), promoBefore, "promo wallet USDC");
        assertEq(usdc.balanceOf(safe), safeBefore, "Safe USDC");
    }

    /// @dev SC-UFY9: after a rejected match, a retry with a fresh valid pair of orders pays the
    ///      credit exactly once.
    function _retryPaysOnce() internal {
        Order memory freshBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory freshSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        uint256 promoBefore = usdc.balanceOf(promoWallet);
        _settleTaker(5_000_000, 5_000_000, freshBuy, freshSell, 5_000_000, 10_000_000);
        assertEq(usdc.balanceOf(promoWallet), promoBefore - 5_000_000);
        _assertRecord(5_000_000, 5_000_000);
    }

    function _assertRecord(uint128 expectedTotal, uint128 expectedSpent) internal view {
        (uint128 total, uint128 spent) = _record();
        assertEq(total, expectedTotal, "record total");
        assertEq(spent, expectedSpent, "record spent");
    }

    // ──────────────────────────────────────────────
    // SC-UFY0: Credited initial bet on a new market mints the shares into the Safe
    // ──────────────────────────────────────────────

    // SC-UFY0: Credited initial bet on a new market mints the shares into the Safe
    //
    // Creating a market with a first bet is the most common use of a credit, and the server
    // matches that bet against a house BUY of the other outcome, which the exchange settles as a
    // mint. The user's Safe holds 0 USDC, so the trade can execute only if the credit arrives in
    // the same transaction.
    //
    // Example: user BUY 10,000,000 YES for 5,000,000 units, house BUY 10,000,000 NO for
    // 5,000,000 units. 5,000,000 + 5,000,000 = 10,000,000 units split into 10,000,000 pairs.
    function test_creditedInitialBetMintsTheSharesIntoTheSafe() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseBuy = _houseBuy(noId, 5_000_000, 10_000_000, 0);
        assertEq(usdc.balanceOf(safe), 0);

        vm.expectEmit(address(settler));
        emit PromoSettler.CreditSettled(safe, CODE, operator, 5_000_000, 5_000_000, 5_000_000);
        vm.expectEmit(address(usdc));
        emit MockERC20.Transfer(promoWallet, safe, 5_000_000);
        _settleTaker(5_000_000, 5_000_000, userBuy, houseBuy, 5_000_000, 5_000_000);

        assertEq(usdc.balanceOf(promoWallet), PROMO_FUND - 5_000_000);
        assertEq(ctf.balanceOf(safe, yesId), 10_000_000);
        assertEq(usdc.balanceOf(safe), 0);
        assertEq(ctf.balanceOf(house, noId), 10_000_000);
        _assertRecord(5_000_000, 5_000_000);
        _assertSettlerEmpty();
    }

    // ──────────────────────────────────────────────
    // SC-UFY1: Credited BUY fills against a house SELL on an existing market
    // ──────────────────────────────────────────────

    // SC-UFY1: Credited BUY fills against a house SELL on an existing market
    //
    // Buying into an existing market is the second use of a credit. A BUY against a SELL is the
    // complementary match: the exchange moves the house's shares to the Safe and the Safe's
    // USDC, which is the credit, to the house, and mints nothing.
    function test_creditedBuyFillsAgainstAHouseSell() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        uint256 houseUsdcBefore = usdc.balanceOf(house);

        vm.expectEmit(address(settler));
        emit PromoSettler.CreditSettled(safe, CODE, operator, 5_000_000, 5_000_000, 5_000_000);
        _settleTaker(5_000_000, 5_000_000, userBuy, houseSell, 5_000_000, 10_000_000);

        assertEq(ctf.balanceOf(safe, yesId), 10_000_000);
        assertEq(usdc.balanceOf(safe), 0);
        assertEq(usdc.balanceOf(house), houseUsdcBefore + 5_000_000);
        assertEq(ctf.balanceOf(house, yesId), 0);
        assertEq(usdc.balanceOf(promoWallet), PROMO_FUND - 5_000_000);
        // No shares are minted: the house keeps the 10,000,000 NO from its own split, and the
        // Safe receives no NO.
        assertEq(ctf.balanceOf(house, noId), 10_000_000);
        assertEq(ctf.balanceOf(safe, noId), 0);
    }

    // ──────────────────────────────────────────────
    // SC-UFY2: Credited resting order fills as a maker
    // ──────────────────────────────────────────────

    // SC-UFY2: Credited resting order fills as a maker
    //
    // User orders rest on the book by default, so a credited order can fill as a maker when a
    // house order crosses it as the taker. creditedIndex = 1 names makerOrders[0], and the credit
    // must reach that maker, the user's Safe. Paying the taker's maker would pay the house.
    function test_creditedRestingOrderFillsAsAMaker() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(userBuy, 5_000_000);
        uint256 houseUsdcBefore = usdc.balanceOf(house);

        vm.expectEmit(address(usdc));
        emit MockERC20.Transfer(promoWallet, safe, 5_000_000);
        vm.prank(operator);
        settler.settle(CODE, 5_000_000, 5_000_000, 1, houseSell, makers, 10_000_000, makerFills);

        assertEq(ctf.balanceOf(safe, yesId), 10_000_000);
        assertEq(usdc.balanceOf(safe), 0);
        assertEq(usdc.balanceOf(house), houseUsdcBefore + 5_000_000);
        _assertRecord(5_000_000, 5_000_000);
        (uint128 houseTotal,) = settler.credits(house, CODE);
        assertEq(houseTotal, 0, "no record for the house");
    }

    // ──────────────────────────────────────────────
    // SC-UFY3: A second settlement for the same Safe and code spends only the remainder
    // ──────────────────────────────────────────────

    // SC-UFY3: A second settlement for the same Safe and code spends only the remainder
    //
    // The server draws one credit across several trades. The record lets a second draw spend
    // what the first left, and no more: 5,000,000 - 2,000,000 = 3,000,000 units remain.
    function test_secondSettlementSpendsOnlyTheRemainder() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        _settleTaker(5_000_000, 2_000_000, userBuy, houseSell, 2_000_000, 4_000_000);
        _assertRecord(5_000_000, 2_000_000);

        vm.expectEmit(address(settler));
        emit PromoSettler.CreditSettled(safe, CODE, operator, 3_000_000, 5_000_000, 5_000_000);
        _settleTaker(5_000_000, 3_000_000, userBuy, houseSell, 3_000_000, 6_000_000);

        _assertRecord(5_000_000, 5_000_000);
        assertEq(usdc.balanceOf(promoWallet), PROMO_FUND - 5_000_000);
        assertEq(ctf.balanceOf(safe, yesId), 10_000_000);
    }

    // ──────────────────────────────────────────────
    // SC-UFY4: A settlement above the recorded credit is refused
    // ──────────────────────────────────────────────

    // SC-UFY4: A settlement above the recorded credit is refused
    //
    // This is the on-chain form of "a credit can never pay twice". Once spent equals total, one
    // more unit for the same Safe and code reverts before any USDC moves.
    function test_settlementAboveTheRecordedCreditIsRefused() public {
        Order memory firstBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory firstSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        _settleTaker(5_000_000, 5_000_000, firstBuy, firstSell, 5_000_000, 10_000_000);

        Order memory nextBuy = _userBuy(yesId, 1_000_000, 2_000_000, 0);
        Order memory nextSell = _houseSell(yesId, 2_000_000, 1_000_000, 0);
        uint256 promoBefore = usdc.balanceOf(promoWallet);
        uint256 safeBefore = usdc.balanceOf(safe);

        (Order[] memory makers, uint256[] memory makerFills) = _one(nextSell, 2_000_000);
        vm.prank(operator);
        vm.expectRevert(PromoSettler.CreditExceeded.selector);
        settler.settle(CODE, 5_000_000, 1, 0, nextBuy, makers, 1_000_000, makerFills);

        _assertRecord(5_000_000, 5_000_000);
        _assertNothingMoved(promoBefore, safeBefore);
    }

    // FR-UFYY: any sequence of settlements for one Safe and one code pays at most the total
    //
    // The server may retry, repeat, or misbehave. Whatever sequence of draws the operator sends,
    // the promo wallet pays exactly the sum of the draws the record accepted, and that sum never
    // passes the total. A draw that would pass it reverts with CreditExceeded.
    function testFuzz_anySequenceOfSettlementsPaysAtMostTheCreditTotal(uint128 total, uint128[4] memory draws) public {
        total = uint128(bound(total, 1, MAX_CREDIT));
        Order memory userBuy = _userBuy(yesId, 10_000_000, 20_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 20_000_000, 10_000_000, 0);

        uint256 paid;
        for (uint256 i; i < draws.length; ++i) {
            uint128 amount = uint128(bound(draws[i], 1, 3_000_000));
            bool refused = paid + amount > total;
            (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, uint256(amount) * 2);
            vm.prank(operator);
            if (refused) vm.expectRevert(PromoSettler.CreditExceeded.selector);
            settler.settle(CODE, total, amount, 0, userBuy, makers, amount, makerFills);
            if (!refused) paid += amount;
        }

        assertLe(paid, total);
        assertEq(usdc.balanceOf(promoWallet), PROMO_FUND - paid);
        (, uint128 spent) = _record();
        assertEq(spent, paid);
    }

    // ──────────────────────────────────────────────
    // SC-UFY5: A first credit total above the maximum is refused
    // ──────────────────────────────────────────────

    // SC-UFY5: A first credit total above the maximum is refused
    //
    // The admin maximum is the ceiling that a server bug or a compromised operator cannot pass
    // for one credit. 10,000,001 is one unit above the 10,000,000 maximum.
    function test_firstCreditTotalAboveTheMaximumIsRefused() public {
        Order memory userBuy = _userBuy(yesId, 1_000_000, 2_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 2_000_000, 1_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 2_000_000);
        uint256 promoBefore = usdc.balanceOf(promoWallet);

        vm.prank(operator);
        vm.expectRevert(PromoSettler.CreditTotalAboveMaximum.selector);
        settler.settle(CODE, 10_000_001, 1_000_000, 0, userBuy, makers, 1_000_000, makerFills);

        _assertRecord(0, 0);
        _assertNothingMoved(promoBefore, 0);

        // The maximum itself is allowed: only a total above it is refused.
        vm.prank(operator);
        settler.settle(CODE, 10_000_000, 1_000_000, 0, userBuy, makers, 1_000_000, makerFills);
        _assertRecord(10_000_000, 1_000_000);
    }

    // ──────────────────────────────────────────────
    // SC-UFY6: A changed credit total is refused
    // ──────────────────────────────────────────────

    // SC-UFY6: A changed credit total is refused
    //
    // The first settlement fixes the total. Accepting a new total later would let a caller
    // raise a credit after it started.
    function test_changedCreditTotalIsRefused() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        _settleTaker(5_000_000, 2_000_000, userBuy, houseSell, 2_000_000, 4_000_000);
        uint256 promoBefore = usdc.balanceOf(promoWallet);

        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 2_000_000);
        vm.prank(operator);
        vm.expectRevert(PromoSettler.CreditTotalMismatch.selector);
        settler.settle(CODE, 6_000_000, 1_000_000, 0, userBuy, makers, 1_000_000, makerFills);

        _assertRecord(5_000_000, 2_000_000);
        _assertNothingMoved(promoBefore, 0);
    }

    // ──────────────────────────────────────────────
    // SC-UFY7: An amount above the credited order's fill, or a zero amount, is refused
    // ──────────────────────────────────────────────

    // SC-UFY7: An amount above the credited order's fill is refused
    //
    // The exchange pulls exactly the fill from the Safe. A credit above it would leave promo
    // USDC in the Safe, free to withdraw without trading: 2,000,001 - 2,000,000 = 1 unit.
    function test_amountAboveTheCreditedFillIsRefused() public {
        Order memory userBuy = _userBuy(yesId, 2_000_000, 4_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 4_000_000, 2_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 4_000_000);

        vm.prank(operator);
        vm.expectRevert(PromoSettler.AmountAboveFill.selector);
        settler.settle(CODE, 5_000_000, 2_000_001, 0, userBuy, makers, 2_000_000, makerFills);

        _assertRecord(0, 0);
        _assertNothingMoved(PROMO_FUND, 0);
    }

    // SC-UFY7: A zero amount is refused
    //
    // A settlement that pays nothing is not a credited trade, so the operator must call the
    // exchange directly for it.
    function test_zeroAmountIsRefused() public {
        Order memory userBuy = _userBuy(yesId, 2_000_000, 4_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 4_000_000, 2_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 4_000_000);

        vm.prank(operator);
        vm.expectRevert(PromoSettler.ZeroAmount.selector);
        settler.settle(CODE, 5_000_000, 0, 0, userBuy, makers, 2_000_000, makerFills);

        _assertRecord(0, 0);
    }

    // ──────────────────────────────────────────────
    // SC-UFY8: A credited order that is not a Safe BUY is refused
    // ──────────────────────────────────────────────

    // SC-UFY8: A credited SELL is refused
    //
    // Only a BUY spends USDC, so only a BUY can use a credit.
    function test_creditedSellIsRefused() public {
        Order memory userSell = _safeOrder(USER_PK, yesId, 10_000_000, 5_000_000, Side.SELL, 0);
        Order memory houseBuy = _houseBuy(yesId, 5_000_000, 10_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseBuy, 5_000_000);

        vm.prank(operator);
        vm.expectRevert(PromoSettler.CreditedOrderNotSafeBuy.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userSell, makers, 10_000_000, makerFills);

        _assertNothingMoved(PROMO_FUND, 0);
    }

    // SC-UFY8: A credited BUY that is not signed as a Safe order is refused
    //
    // POLY_GNOSIS_SAFE makes the exchange check that the maker is the Safe the signer owns. An
    // EOA-signed order names its signer as maker, so a credit would go to a plain wallet.
    function test_creditedBuyWithAnEoaSignatureIsRefused() public {
        Order memory eoaBuy = _eoaOrder(USER_PK, yesId, 5_000_000, 10_000_000, Side.BUY, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 10_000_000);

        vm.prank(operator);
        vm.expectRevert(PromoSettler.CreditedOrderNotSafeBuy.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, eoaBuy, makers, 5_000_000, makerFills);

        _assertNothingMoved(PROMO_FUND, 0);
    }

    // SC-UFY8: A credited index above the maker count is refused
    //
    // creditedIndex = 2 names makerOrders[1], and the call carries one maker order.
    function test_creditedIndexAboveTheMakerCountIsRefused() public {
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(userBuy, 5_000_000);

        vm.prank(operator);
        vm.expectRevert(PromoSettler.CreditedIndexOutOfRange.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 2, houseSell, makers, 10_000_000, makerFills);

        _assertNothingMoved(PROMO_FUND, 0);
    }

    // ──────────────────────────────────────────────
    // SC-UFY9: A match the exchange rejects leaves the credit unspent
    // ──────────────────────────────────────────────

    // SC-UFY9: A match that does not cross reverts the credit with it, and a retry pays once
    //
    // Atomicity is the point of the design. The credit transfer runs before matchOrders, so the
    // exchange's revert must undo it. A retry with a valid match then pays exactly once.
    function test_matchThatDoesNotCrossLeavesTheCreditUnspent() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory dearSell = _houseSell(yesId, 10_000_000, 6_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(dearSell, 10_000_000);

        vm.prank(operator);
        vm.expectRevert(IProphetCTFExchange.NotCrossing.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);

        _assertRecord(0, 0);
        _assertNothingMoved(PROMO_FUND, 0);

        Order memory fairSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        _settleTaker(5_000_000, 5_000_000, userBuy, fairSell, 5_000_000, 10_000_000);
        assertEq(usdc.balanceOf(promoWallet), PROMO_FUND - 5_000_000);
        _assertRecord(5_000_000, 5_000_000);
    }

    // SC-UFY9: A cancelled order reverts the credit with it
    function test_cancelledOrderLeavesTheCreditUnspent() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        vm.prank(safe);
        exchange.cancelOrder(userBuy);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 10_000_000);

        vm.prank(operator);
        vm.expectRevert(IProphetCTFExchange.OrderFilledOrCancelled.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);

        _assertRecord(0, 0);
        _assertNothingMoved(PROMO_FUND, 0);
        _retryPaysOnce();
    }

    // SC-UFY9: An order the exchange records as filled reverts the credit with it
    //
    // A first settlement under another code fills the user order in full. A second settlement
    // of the same order under CODE reaches the exchange, which refuses the filled order, so the
    // record for CODE stays empty and the promo wallet pays nothing more.
    function test_filledOrderLeavesTheCreditUnspent() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 20_000_000, 10_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 10_000_000);
        vm.prank(operator);
        settler.settle(keccak256("first-code"), 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);
        uint256 promoBefore = usdc.balanceOf(promoWallet);
        uint256 safeBefore = usdc.balanceOf(safe);

        vm.prank(operator);
        vm.expectRevert(IProphetCTFExchange.OrderFilledOrCancelled.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);

        _assertRecord(0, 0);
        _assertNothingMoved(promoBefore, safeBefore);
        _retryPaysOnce();
    }

    // SC-UFY9: An order reserved for another taker reverts the credit with it
    //
    // Every server path signs taker = 0, but the server copies the taker field from the client,
    // so a non-zero taker is possible. The exchange sees the settler as the caller and rejects
    // the order, and the whole call fails safe.
    function test_orderReservedForAnotherTakerLeavesTheCreditUnspent() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        userBuy.taker = makeAddr("another-taker");
        userBuy.signature = _signOrder(USER_PK, userBuy);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 10_000_000);

        vm.prank(operator);
        vm.expectRevert(IProphetCTFExchange.NotTaker.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);

        _assertRecord(0, 0);
        _assertNothingMoved(PROMO_FUND, 0);
        _retryPaysOnce();
    }

    // ──────────────────────────────────────────────
    // SC-UFYA: A caller that is not an operator of both the settler and the exchange is refused
    // ──────────────────────────────────────────────

    // SC-UFYA: A caller outside the settler's operators is refused
    function test_callerOutsideTheSettlerOperatorsIsRefused() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 10_000_000);

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(PromoSettler.NotOperator.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);

        _assertNothingMoved(PROMO_FUND, 0);
    }

    // SC-UFYA: A settler operator the exchange does not list is refused
    //
    // The settler holds the exchange operator role. Without the second check, the settler's
    // admin could grant exchange-operator power by adding a settler operator, outside the
    // exchange admin's control.
    function test_settlerOperatorTheExchangeDoesNotListIsRefused() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 10_000_000);
        exchange.removeOperator(operator);

        vm.prank(operator);
        vm.expectRevert(PromoSettler.NotExchangeOperator.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);

        _assertNothingMoved(PROMO_FUND, 0);
    }

    // ──────────────────────────────────────────────
    // SC-UFYB: A paused settler refuses settlement
    // ──────────────────────────────────────────────

    // SC-UFYB: A paused settler refuses settlement until the admin unpauses it
    //
    // The pause stops promo spending without touching the exchange or the promo wallet. The
    // paused call moves nothing, and the same arguments settle once the admin unpauses.
    function test_pausedSettlerRefusesSettlementUntilUnpaused() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);
        (Order[] memory makers, uint256[] memory makerFills) = _one(houseSell, 10_000_000);
        vm.prank(admin);
        settler.pause();

        vm.prank(operator);
        vm.expectRevert(PromoSettler.SettlerPaused.selector);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);
        _assertRecord(0, 0);
        _assertNothingMoved(PROMO_FUND, 0);

        vm.prank(admin);
        settler.unpause();
        vm.prank(operator);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);
        _assertRecord(5_000_000, 5_000_000);
    }

    // ──────────────────────────────────────────────
    // SC-UFYC: The fees reach the operator and the settler ends empty
    // ──────────────────────────────────────────────

    // SC-UFYC: The fees reach the operator and the settler ends empty
    //
    // The exchange pays fees to its caller, the settler. The settler forwards them, so the
    // operator's balances and fee tools stay as they are without the settler. One match carries
    // all three fee kinds. For a BUY at price p the fee is rate * min(p, 1 - p) * shares / p,
    // and for a SELL it is rate * min(p, 1 - p) * shares, with rate = 200 / 10,000 and p = 0.50:
    //   taker BUY of 10,000,000 YES:     0.02 * 0.50 * 10,000,000 / 0.50 = 200,000 YES
    //   maker SELL of 4,000,000 YES:     0.02 * 0.50 * 4,000,000        =  40,000 USDC
    //   maker BUY (mint) of 6,000,000 NO: 0.02 * 0.50 * 6,000,000 / 0.50 = 120,000 NO
    function test_feesReachTheOperatorAndTheSettlerEndsEmpty() public {
        Order memory userBuy = _userBuy(yesId, 5_000_000, 10_000_000, 200);
        Order[] memory makers = new Order[](2);
        makers[0] = _houseSell(yesId, 4_000_000, 2_000_000, 200);
        makers[1] = _houseBuy(noId, 3_000_000, 6_000_000, 200);
        uint256[] memory makerFills = new uint256[](2);
        makerFills[0] = 4_000_000;
        makerFills[1] = 3_000_000;

        vm.prank(operator);
        settler.settle(CODE, 5_000_000, 5_000_000, 0, userBuy, makers, 5_000_000, makerFills);

        assertEq(ctf.balanceOf(operator, yesId), 200_000, "taker fee in YES");
        assertEq(usdc.balanceOf(operator), 40_000, "SELL maker fee in USDC");
        assertEq(ctf.balanceOf(operator, noId), 120_000, "mint maker fee in NO");
        assertEq(ctf.balanceOf(safe, yesId), 10_000_000 - 200_000);
        _assertSettlerEmpty();
    }

    // ──────────────────────────────────────────────
    // SC-UFYD: A price-improvement refund stays in the Safe
    // ──────────────────────────────────────────────

    // SC-UFYD: A price-improvement refund stays in the Safe
    //
    // The exchange refunds unused USDC to the taker order's maker. The user signed 0.60 and the
    // house sells at 0.50, so 10,000,000 shares cost 5,000,000 of the 6,000,000 pulled, and
    // 6,000,000 - 5,000,000 = 1,000,000 units return to the Safe. The user accepted this
    // remainder: pulling it back would need the Safe to approve the settler.
    function test_priceImprovementRefundStaysInTheSafe() public {
        Order memory userBuy = _userBuy(yesId, 6_000_000, 10_000_000, 0);
        Order memory houseSell = _houseSell(yesId, 10_000_000, 5_000_000, 0);

        _settleTaker(6_000_000, 6_000_000, userBuy, houseSell, 6_000_000, 10_000_000);

        assertEq(ctf.balanceOf(safe, yesId), 10_000_000);
        assertEq(usdc.balanceOf(safe), 1_000_000);
        assertEq(usdc.balanceOf(promoWallet), PROMO_FUND - 6_000_000);
        _assertRecord(6_000_000, 6_000_000);
        _assertSettlerEmpty();
    }

    // ──────────────────────────────────────────────
    // SC-UFYE: Tokens from a contract other than Conditional Tokens are refused
    // ──────────────────────────────────────────────

    // SC-UFYE: Tokens from a contract other than Conditional Tokens are refused
    //
    // Inside a receiver hook msg.sender is the token contract. The hooks accept only the
    // exchange's Conditional Tokens contract, so no other ERC-1155 can place tokens in the
    // settler.
    function test_receiverHooksRefuseAnotherTokenContract() public {
        address stranger = makeAddr("other-erc1155");

        vm.prank(stranger);
        vm.expectRevert(PromoSettler.NotConditionalTokens.selector);
        settler.onERC1155Received(stranger, stranger, yesId, 1, "");

        vm.prank(stranger);
        vm.expectRevert(PromoSettler.NotConditionalTokens.selector);
        settler.onERC1155BatchReceived(stranger, stranger, new uint256[](1), new uint256[](1), "");
    }

    // SC-UFYE: The hooks answer the Conditional Tokens contract with their selectors
    function test_receiverHooksAcceptTheConditionalTokensContract() public {
        vm.startPrank(address(ctf));
        assertEq(settler.onERC1155Received(house, house, yesId, 1, ""), PromoSettler.onERC1155Received.selector);
        assertEq(
            settler.onERC1155BatchReceived(house, house, new uint256[](1), new uint256[](1), ""),
            PromoSettler.onERC1155BatchReceived.selector
        );
        vm.stopPrank();
    }

    // SC-UFYE: supportsInterface answers for IERC1155Receiver and IERC165 only
    function test_supportsInterfaceAnswersForTheReceiverAndErc165Only() public view {
        assertTrue(settler.supportsInterface(0x4e2312e0));
        assertTrue(settler.supportsInterface(0x01ffc9a7));
        assertFalse(settler.supportsInterface(0xffffffff));
    }
}
