---
id: FEAT-UFXS
name: Promo Credit Settlement
module: contracts
domain: settlement
status: implemented
version: 1
refs: [FEAT-UFXT]
---

# Promo Credit Settlement

> The settler pays a promotional USDC credit to the user's Safe and settles the trade it funds in one transaction, so a user whose only money is the promotion can trade and a credit never pays more than its total.

## Non-Goals

- Does not decide who gets a credit or how large it is. The server decides both and passes the credit total and the amount.
- Does not price, validate, or sign orders. ProphetCTFExchange validates every order and enforces every signed price.
- Does not settle a trade that spends no credit. The Operator calls `matchOrders` on the exchange directly for every other trade.
- Does not pull back a price-improvement refund. The exchange refunds unused USDC to the taker order's maker, and the refund stays in the Safe.
- Does not hold a campaign budget. The promo wallet holds the USDC and approves the settler for a finite allowance.
- Does not manage roles, the credit maximum, the pause, or recovery -- see settler administration (FEAT-UFXT).
- Does not deploy the settler -- see settler deployment (FEAT-UFXU).

## Actors

| Actor | Role | Notes |
|-------|------|-------|
| Operator | Calls `settle` with the credit values and the four `matchOrders` arguments | Must be an operator on both the settler and ProphetCTFExchange. Receives every fee |
| User | Owns the Safe that receives the credit and the bought shares | Never calls the settler. Signs the credited order with the Safe's owner key |
| Promo Wallet | Funds the credit through its USDC allowance to the settler | The only address the settler pulls USDC from |
| ProphetCTFExchange | Validates and settles the forwarded match | Pays its fees to the settler, which forwards them |

## Functional Requirements

**FR-UFYX** `The settler shall pay a credit only to the maker of the credited signed order, and shall take no recipient address as a parameter.`
Fit Criterion: Given a settlement with `creditedIndex = 1`, the USDC `Transfer` from the promo wallet names `makerOrders[0].maker` as its recipient, and `settle` has no address parameter.
Linked to: UC-UFXV

**FR-UFYY** `The settler shall never pay a Safe more than the credit total recorded for one promo code ID.`
Fit Criterion: Given any sequence of settlements for one Safe and one promo code ID, the promo wallet's balance falls by at most the recorded total, and the record's `spent` never exceeds its `total`.
Linked to: UC-UFXV

**FR-UFYZ** `After every settlement, the settler shall hold no USDC and no outcome shares.`
Fit Criterion: Given a settlement of orders signed at `feeRateBps = 200`, the settler's USDC balance and its balance of every token ID in the orders are 0 after the call.
Linked to: UC-UFXV

**FR-UFZ0** `If ProphetCTFExchange rejects the match, then the settler shall revert the whole settlement, credit payment included.`
Fit Criterion: Given a match the exchange rejects, the promo wallet balance, the Safe balance, and the credit record equal their values before the call.
Linked to: UC-UFXV

## Non-Functional Requirements

**NFR-UFZ7** Security: `The settler shall move USDC out of no address other than the promo wallet and its own balance.`
Fit Criterion: Given any successful settlement, the only USDC `Transfer` the settler initiates with `transferFrom` has the promo wallet as its source.

## Acceptance

> The feature is complete when all of the following are true:

- Every scenario of settle a credited trade (UC-UFXV) passes its integration test.
- Coverage gate met against `.molcajete/settings.json` `testing.thresholds` for `src/PromoSettler.sol`.
- ARCHITECTURE.md diagrams reflect the built system.
- FEATURES.md status is `implemented`.
