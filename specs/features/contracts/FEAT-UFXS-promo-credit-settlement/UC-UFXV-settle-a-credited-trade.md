---
id: UC-UFXV
name: Settle a Credited Trade
feature: FEAT-UFXS
status: implemented
version: 1
actor: Operator
---

# UC-UFXV: Settle a Credited Trade

> The Operator pays a promotional credit to the credited order's Safe and settles the match in one transaction.

## Preconditions

- The settler is deployed with an exchange, a promo wallet, an admin, an operator, and a credit maximum of 10,000,000 units ($10.00).
- ProphetCTFExchange lists the settler as an operator.
- The promo wallet holds USDC and approves the settler for at least the credit amount.
- The market's YES and NO token IDs are registered on the exchange.
- The user's Safe is the CREATE2 address the exchange derives from the Safe's owner key, and the Safe approves the exchange for USDC.
- Amounts are USDC raw units: 1,000,000 units = $1.00. Outcome shares use the same units.

## Trigger

The Operator calls `settle(codeId, creditTotal, amount, creditedIndex, takerOrder, makerOrders, takerFillAmount, makerFillAmounts)` for a trade that spends a promotional credit.

---

### SC-UFY0: Credited initial bet on a new market mints the shares into the Safe

**Given:**
- The user's Safe holds 0 USDC.
- The user signed a BUY of YES for 5,000,000 units at a price of 0.50 (`makerAmount = 5,000,000`, `takerAmount = 10,000,000`), with `feeRateBps = 0`.
- The house signed a BUY of NO for 5,000,000 units at a price of 0.50, with `feeRateBps = 0`.

**Steps:**
1. Operator calls `settle` with `creditTotal = 5,000,000`, `amount = 5,000,000`, `creditedIndex = 0`, the user order as taker, the house order as the one maker, `takerFillAmount = 5,000,000`, and `makerFillAmounts = [5,000,000]`.
2. System pays 5,000,000 units from the promo wallet to the Safe.
3. System forwards the match, and the exchange mints 10,000,000 YES and NO pairs.

**Outcomes:**
- The promo wallet's balance fell by exactly 5,000,000 units.
- The Safe holds 10,000,000 YES shares and 0 USDC.
- The house holds 10,000,000 NO shares.
- The credit record for the Safe and the code reads `total = 5,000,000` and `spent = 5,000,000`.

**Side Effects:**
- `CreditSettled(safe, codeId, operator, 5000000, 5000000, 5000000)` event emitted.
- USDC `Transfer` from the promo wallet to the Safe for 5,000,000 units.
- `credits[safe][codeId]` storage: record created with `total` and `spent`.
- No USDC and no shares remain in the settler.

---

### SC-UFY1: Credited BUY fills against a house SELL on an existing market

**Given:**
- The user signed a BUY of YES for 5,000,000 units at a price of 0.50.
- The house holds 10,000,000 YES shares and signed a SELL of them at a price of 0.50 (`makerAmount = 10,000,000`, `takerAmount = 5,000,000`).

**Steps:**
1. Operator calls `settle` with `creditTotal = 5,000,000`, `amount = 5,000,000`, `creditedIndex = 0`, `takerFillAmount = 5,000,000`, and `makerFillAmounts = [10,000,000]`.
2. System pays the credit to the Safe and forwards the match.

**Outcomes:**
- The Safe holds 10,000,000 YES shares and 0 USDC.
- The house holds 5,000,000 USDC more and 0 YES shares.
- The promo wallet's balance fell by exactly 5,000,000 units.

**Side Effects:**
- `CreditSettled(safe, codeId, operator, 5000000, 5000000, 5000000)` event emitted.
- No shares are minted.

---

### SC-UFY2: Credited resting order fills as a maker

**Given:**
- The user signed a BUY of YES for 5,000,000 units at a price of 0.50, and the order rests on the book.
- The house holds 10,000,000 YES shares and signed a SELL of them at a price of 0.50, which crosses the user's order as the taker.

**Steps:**
1. Operator calls `settle` with `creditTotal = 5,000,000`, `amount = 5,000,000`, `creditedIndex = 1`, the house order as taker, the user order as `makerOrders[0]`, `takerFillAmount = 10,000,000`, and `makerFillAmounts = [5,000,000]`.
2. System pays the credit to `makerOrders[0].maker`, the user's Safe, and forwards the match.

**Outcomes:**
- The Safe holds 10,000,000 YES shares and 0 USDC.
- The house Safe holds 5,000,000 USDC more.
- The credit record is keyed to the user's Safe, not to the house.

**Side Effects:**
- USDC `Transfer` from the promo wallet to the user's Safe for 5,000,000 units.
- No USDC moves from the promo wallet to the house.

---

### SC-UFY3: A second settlement for the same Safe and code spends only the remainder

**Given:**
- A credit of 5,000,000 units for code C.
- A first settlement spent 2,000,000 units for Safe S on a user BUY of YES for 5,000,000 units against a house SELL of 10,000,000 YES.

**Steps:**
1. Operator calls `settle` for S and C with `creditTotal = 5,000,000`, `amount = 3,000,000`, and `takerFillAmount = 3,000,000` on the same two orders.
2. System checks that 2,000,000 + 3,000,000 does not pass 5,000,000, and settles.

**Outcomes:**
- The record reads `spent = 5,000,000` and `total = 5,000,000`.
- The promo wallet paid 5,000,000 units across the two settlements.
- The Safe holds 10,000,000 YES shares.

**Side Effects:**
- `CreditSettled(safe, codeId, operator, 3000000, 5000000, 5000000)` event emitted.

---

### SC-UFY4: A settlement above the recorded credit is refused

**Given:**
- A record for Safe S and code C with `total = 5,000,000` and `spent = 5,000,000`.
- A new user BUY of YES for 1,000,000 units from S, and a crossing house SELL.

**Steps:**
1. Operator calls `settle` for S and C with `creditTotal = 5,000,000` and `amount = 1`.
2. System reverts with `CreditExceeded`.

**Outcomes:**
- The record still reads `spent = 5,000,000`.
- The promo wallet and the Safe hold what they held before the call.

**Side Effects:**
- No USDC moves.
- No `CreditSettled` event emitted.
- No match reaches the exchange.

---

### SC-UFY5: A first credit total above the maximum is refused

**Given:**
- `maxCreditUnits = 10,000,000`.
- No record exists for Safe S and code C.

**Steps:**
1. Operator calls `settle` for S and C with `creditTotal = 10,000,001`.
2. System reverts with `CreditTotalAboveMaximum`.

**Outcomes:**
- No record exists for S and C.

**Side Effects:**
- No USDC moves.
- No `CreditSettled` event emitted.

---

### SC-UFY6: A changed credit total is refused

**Given:**
- A record for Safe S and code C with `total = 5,000,000` and `spent = 2,000,000`.

**Steps:**
1. Operator calls `settle` for S and C with `creditTotal = 6,000,000`.
2. System reverts with `CreditTotalMismatch`.

**Outcomes:**
- The record still reads `total = 5,000,000` and `spent = 2,000,000`.

**Side Effects:**
- No USDC moves.

---

### SC-UFY7: An amount above the credited order's fill, or a zero amount, is refused

**Given:**
- A credited taker BUY settled with `takerFillAmount = 2,000,000`.

**Steps:**
1. Operator calls `settle` with `amount = 2,000,001`.
2. System reverts with `AmountAboveFill`.
3. Operator calls `settle` with `amount = 0`.
4. System reverts with `ZeroAmount`.

**Outcomes:**
- No record exists for the Safe and the code.

**Side Effects:**
- No USDC moves.

---

### SC-UFY8: A credited order that is not a Safe BUY is refused

**Given:**
- One house maker order.

**Steps:**
1. Operator calls `settle` with a credited order whose `side` is SELL.
2. System reverts with `CreditedOrderNotSafeBuy`.
3. Operator calls `settle` with a credited BUY whose `signatureType` is `EOA`.
4. System reverts with `CreditedOrderNotSafeBuy`.
5. Operator calls `settle` with `creditedIndex = 2` and one maker order.
6. System reverts with `CreditedIndexOutOfRange`.

**Outcomes:**
- No record exists.

**Side Effects:**
- No USDC moves.

---

### SC-UFY9: A match the exchange rejects leaves the credit unspent

**Given:**
- A user BUY of YES and a house order.

**Steps:**
1. Operator calls `settle` with a house SELL priced above the user's BUY.
2. The exchange reverts with `NotCrossing`, and the system reverts the whole call.
3. Operator calls `settle` with a user order that the exchange already records as filled.
4. The exchange reverts with `OrderFilledOrCancelled`, and the system reverts the whole call.
5. Operator calls `settle` with a user order whose `taker` field names an address other than the settler.
6. The exchange reverts with `NotTaker`, and the system reverts the whole call.

**Outcomes:**
- The promo wallet balance, the Safe balance, and the credit record equal their values before each call.
- A retry with valid orders pays the credit exactly once.

**Side Effects:**
- No USDC moves.
- No `CreditSettled` event emitted.

---

### SC-UFYA: A caller that is not an operator of both the settler and the exchange is refused

**Given:**
- Address A is not in the settler's `operators`.
- Address B is in the settler's `operators` and is not an operator on the exchange.

**Steps:**
1. A calls `settle`.
2. System reverts with `NotOperator`.
3. B calls `settle`.
4. System reverts with `NotExchangeOperator`.

**Outcomes:**
- No record exists.

**Side Effects:**
- No USDC moves.

---

### SC-UFYB: A paused settler refuses settlement

**Given:**
- The admin paused the settler.

**Steps:**
1. Operator calls `settle` with a valid credited trade.
2. System reverts with `SettlerPaused`.
3. The admin unpauses the settler.
4. Operator calls `settle` with the same arguments.
5. System settles the trade.

**Outcomes:**
- The paused call moved nothing. The call after `unpause` records the credit.

**Side Effects:**
- No USDC moves during the pause.

---

### SC-UFYC: The fees reach the operator and the settler ends empty

**Given:**
- Every order is signed at `feeRateBps = 200` and a price of 0.50.
- The user signed a BUY of YES for 5,000,000 units.
- The house signed a SELL of 4,000,000 YES and a BUY of NO for 3,000,000 units.

**Steps:**
1. Operator calls `settle` with `amount = 5,000,000`, `takerFillAmount = 5,000,000`, and `makerFillAmounts = [4,000,000, 3,000,000]`.
2. System settles the match and forwards every fee the exchange paid it to the Operator.

**Outcomes:**
- The Operator holds 200,000 YES (the taker's fee), 40,000 USDC (the SELL maker's fee), and 120,000 NO (the mint maker's fee).
- The Safe holds 9,800,000 YES shares.
- The settler's USDC balance, YES balance, and NO balance are 0.

**Side Effects:**
- USDC `Transfer` from the settler to the Operator for 40,000 units.
- ERC-1155 `TransferSingle` events from the settler to the Operator for the YES and the NO fees.

---

### SC-UFYD: A price-improvement refund stays in the Safe

**Given:**
- The user signed a BUY of 10,000,000 YES at a price of 0.60 (`makerAmount = 6,000,000`).
- The house signed a SELL of 10,000,000 YES at a price of 0.50.

**Steps:**
1. Operator calls `settle` with `amount = 6,000,000`, `takerFillAmount = 6,000,000`, and `makerFillAmounts = [10,000,000]`.
2. The exchange fills at 0.50 and refunds the unused USDC to the Safe.

**Outcomes:**
- The Safe holds 10,000,000 YES shares and 1,000,000 USDC.
- The record reads `spent = 6,000,000`.

**Side Effects:**
- No USDC moves from the Safe back to the settler or to the promo wallet.

---

### SC-UFYE: Tokens from a contract other than Conditional Tokens are refused

**Given:**
- An address that is not the Conditional Tokens contract.

**Steps:**
1. The address calls `onERC1155Received` on the settler.
2. System reverts with `NotConditionalTokens`.
3. The address calls `onERC1155BatchReceived` on the settler.
4. System reverts with `NotConditionalTokens`.
5. A caller asks `supportsInterface` for the ERC-1155 receiver interface (`0x4e2312e0`), the ERC-165 interface (`0x01ffc9a7`), and `0xffffffff`.

**Outcomes:**
- The two hooks refuse the address.
- `supportsInterface` answers true, true, and false.

**Side Effects:**
- No token enters the settler.
