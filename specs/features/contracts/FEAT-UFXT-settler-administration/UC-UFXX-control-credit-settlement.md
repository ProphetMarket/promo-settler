---
id: UC-UFXX
name: Control Credit Settlement
feature: FEAT-UFXT
status: implemented
version: 1
actor: Admin
---

# UC-UFXX: Control Credit Settlement

> The admin bounds new credits, stops and restarts settlement, and returns stray tokens to the promo wallet.

## Preconditions

- The settler is deployed with one admin, one operator, and `maxCreditUnits = 10,000,000`.

## Trigger

An admin calls `setMaxCreditUnits`, `pause`, `unpause`, or `recover`.

---

### SC-UFYL: The admin sets the credit maximum

**Given:**
- A record for Safe S and code C with `total = 5,000,000` and `spent = 2,000,000`.

**Steps:**
1. The admin calls `setMaxCreditUnits(1,000,000)`.
2. System stores the new maximum.
3. Operator settles 3,000,000 units for S and C with `creditTotal = 5,000,000`.
4. System settles, because the record already fixed its total.
5. Operator settles a new Safe and code with `creditTotal = 1,000,001`.
6. System reverts with `CreditTotalAboveMaximum`.
7. The admin calls `setMaxCreditUnits(0)`.
8. System reverts with `ZeroMaxCredit`.

**Outcomes:**
- `maxCreditUnits() = 1,000,000`.
- The record for S and C reads `spent = 5,000,000` and `total = 5,000,000`.

**Side Effects:**
- `MaxCreditUnitsUpdated(10000000, 1000000)` event emitted.

---

### SC-UFYM: The admin pauses and unpauses the settler

**Given:**
- `paused() = false`.

**Steps:**
1. The admin calls `pause()`.
2. System sets `paused() = true`.
3. The admin calls `unpause()`.
4. System sets `paused() = false`.

**Outcomes:**
- The flag follows each call.

**Side Effects:**
- `Paused(admin)` event emitted, then `Unpaused(admin)`.
- No USDC moves.

---

### SC-UFYN: The admin recovers stray USDC to the promo wallet

**Given:**
- Someone sent 700,000 USDC units to the settler.

**Steps:**
1. The admin calls `recover(0)`.
2. System sends the settler's whole USDC balance to the promo wallet.

**Outcomes:**
- The settler holds 0 USDC.
- The promo wallet holds 700,000 units more.

**Side Effects:**
- `Recovered(0, 700000)` event emitted.
- No USDC moves to the admin.

---

### SC-UFYO: The admin recovers a stray outcome token to the promo wallet

**Given:**
- The Conditional Tokens contract delivered 300,000 YES shares to the settler outside a settlement.

**Steps:**
1. The admin calls `recover(yesTokenId)`.
2. System sends the settler's whole YES balance to the promo wallet.

**Outcomes:**
- The settler holds 0 YES.
- The promo wallet holds 300,000 YES.

**Side Effects:**
- `Recovered(yesTokenId, 300000)` event emitted.

---

### SC-UFYP: Recovery of a zero balance is refused

**Given:**
- The settler holds 0 USDC and 0 NO shares.

**Steps:**
1. The admin calls `recover(0)`.
2. System reverts with `NothingToRecover`.
3. The admin calls `recover(noTokenId)`.
4. System reverts with `NothingToRecover`.

**Outcomes:**
- Balances are unchanged.

**Side Effects:**
- No `Recovered` event emitted.

---

### SC-UFYQ: A caller outside the admins cannot use the controls

**Given:**
- Address X has `admins(X) = 0`, and the settler holds 700,000 USDC units.

**Steps:**
1. X calls each of `setMaxCreditUnits(1)`, `pause()`, `unpause()`, and `recover(0)`.
2. System reverts each call with `NotAdmin`.

**Outcomes:**
- `maxCreditUnits`, `paused`, and the settler's balance are unchanged.

**Side Effects:**
- No control event emitted.
