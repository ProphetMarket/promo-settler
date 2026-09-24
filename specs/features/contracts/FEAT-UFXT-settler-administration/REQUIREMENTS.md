---
id: FEAT-UFXT
name: Settler Administration
module: contracts
domain: admin
status: implemented
version: 1
refs: []
---

# Settler Administration

> The admin manages the settler's admins and operators, sets the credit maximum, pauses settlement, and recovers stray tokens to the promo wallet.

## Non-Goals

- Does not manage roles on ProphetCTFExchange. The exchange admin registers the settler as an exchange operator.
- Does not add an oracle role. The settler has no market lifecycle.
- Does not let an admin call `settle` as an admin, or send tokens to an address of its choice.
- Does not change a credit total already recorded -- see promo credit settlement (FEAT-UFXS).
- Does not change the exchange or the promo wallet after deployment. Both are immutable.

## Actors

| Actor | Role | Notes |
|-------|------|-------|
| Admin | Manages roles and the three controls | At least one admin always exists |
| Promo Wallet | Receives every recovered token | The fixed recovery destination |

## Functional Requirements

**FR-UFZ1** `If a caller outside the settler's admins calls a role or control function, then the settler shall revert with NotAdmin.`
Fit Criterion: Given an address with `admins(address) = 0`, each of `addAdmin`, `removeAdmin`, `renounceAdminRole`, `transferAdmin`, `addOperator`, `removeOperator`, `setMaxCreditUnits`, `pause`, `unpause`, and `recover` reverts with `NotAdmin`.
Linked to: UC-UFXW, UC-UFXX

**FR-UFZ2** `The settler shall always keep at least one admin.`
Fit Criterion: Given `adminCount = 1`, `removeAdmin` of that admin and `renounceAdminRole` by that admin revert with `CannotRemoveLastAdmin`.
Linked to: UC-UFXW

**FR-UFZ3** `When the admin recovers a token, the settler shall send its whole balance of that token to the promo wallet.`
Fit Criterion: Given the settler holds 700,000 USDC units, `recover(0)` leaves the settler at 0 and raises the promo wallet by 700,000.
Linked to: UC-UFXX

**FR-UFZ4** `When the admin changes the credit maximum, the settler shall apply the new maximum to credit records created after the change only.`
Fit Criterion: Given a record with `total = 5,000,000`, after `setMaxCreditUnits(1,000,000)` a settlement against that record with `creditTotal = 5,000,000` succeeds, and a new record with `creditTotal = 1,000,001` reverts with `CreditTotalAboveMaximum`.
Linked to: UC-UFXX

## Non-Functional Requirements

**Not applicable:** the admin functions change storage only, and their security properties are the functional requirements above.

## Acceptance

> The feature is complete when all of the following are true:

- Every scenario of manage settler roles (UC-UFXW) and control credit settlement (UC-UFXX) passes its integration test.
- Coverage gate met against `.molcajete/settings.json` `testing.thresholds` for `src/PromoSettler.sol`.
- ARCHITECTURE.md diagrams reflect the built system.
- FEATURES.md status is `implemented`.
