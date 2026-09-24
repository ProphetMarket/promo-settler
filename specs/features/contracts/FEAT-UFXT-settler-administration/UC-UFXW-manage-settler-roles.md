---
id: UC-UFXW
name: Manage Settler Roles
feature: FEAT-UFXT
status: implemented
version: 1
actor: Admin
---

# UC-UFXW: Manage Settler Roles

> The admin controls who may administer the settler and who may call `settle`.

## Preconditions

- The settler is deployed with one admin (`adminCount = 1`) and one operator.

## Trigger

An admin calls `addAdmin`, `removeAdmin`, `renounceAdminRole`, `transferAdmin`, `addOperator`, or `removeOperator`, or a proposed admin calls `acceptAdmin`.

---

### SC-UFYF: A caller outside the admins is refused

**Given:**
- Address X has `admins(X) = 0`.

**Steps:**
1. X calls each of `addAdmin`, `removeAdmin`, `renounceAdminRole`, `transferAdmin`, `addOperator`, and `removeOperator`.
2. System reverts each call with `NotAdmin`.

**Outcomes:**
- `adminCount`, `pendingAdmin`, and every role mapping keep their values.

**Side Effects:**
- No role event emitted.

---

### SC-UFYG: The admin adds and removes an operator

**Given:**
- Address P has `operators(P) = 0`.

**Steps:**
1. The admin calls `addOperator(P)`.
2. System sets `operators(P) = 1`.
3. The admin calls `removeOperator(P)`.
4. System sets `operators(P) = 0`.

**Outcomes:**
- P could call `settle` between the two calls, and cannot after the second.

**Side Effects:**
- `NewOperator(P, admin)` event emitted, then `RemovedOperator(P, admin)`.

---

### SC-UFYH: The admin adds and removes an admin

**Given:**
- Address N has `admins(N) = 0`.

**Steps:**
1. The admin calls `addAdmin(N)`.
2. System sets `admins(N) = 1` and `adminCount = 2`.
3. The admin calls `addAdmin(N)` again.
4. System keeps `adminCount = 2` and emits the event again.
5. The admin calls `removeAdmin(N)`.
6. System sets `admins(N) = 0` and `adminCount = 1`.
7. The admin calls `addAdmin(address(0))`.
8. System reverts with `ZeroAddress`.

**Outcomes:**
- `adminCount` counts each admin once.

**Side Effects:**
- `NewAdmin(N, admin)` event emitted twice, then `RemovedAdmin(N, admin)`.

---

### SC-UFYI: The last admin cannot leave

**Given:**
- `adminCount = 1`.

**Steps:**
1. The admin calls `removeAdmin(admin)`.
2. System reverts with `CannotRemoveLastAdmin`.
3. The admin calls `renounceAdminRole()`.
4. System reverts with `CannotRemoveLastAdmin`.
5. The admin adds a second admin N, then calls `renounceAdminRole()`.
6. System sets `admins(admin) = 0` and `adminCount = 1`.

**Outcomes:**
- The settler always has at least one admin.

**Side Effects:**
- `RemovedAdmin(admin, admin)` event emitted for the renounce in step 5.

---

### SC-UFYJ: An admin transfer takes two steps

**Given:**
- Address X is not an admin.

**Steps:**
1. The admin calls `transferAdmin(X)`.
2. System sets `pendingAdmin = X`.
3. Address Y calls `acceptAdmin()`.
4. System reverts with `NotPendingAdmin`.
5. X calls `acceptAdmin()`.
6. System sets `admins(X) = 1`, `adminCount = 2`, and `pendingAdmin = address(0)`.
7. The admin calls `transferAdmin(address(0))`, then `transferAdmin(X)`.
8. System reverts with `ZeroAddress`, then with `AlreadyAdmin`.

**Outcomes:**
- Only the proposed address can complete the transfer.

**Side Effects:**
- `AdminTransferProposed(admin, X)` event emitted, then `NewAdmin(X, X)`.

---

### SC-UFYK: Removing or renouncing an admin withdraws its pending transfer

**Given:**
- The admin proposed X with `transferAdmin(X)`, and X holds no role.

**Steps:**
1. The admin calls `removeAdmin(X)`.
2. System sets `pendingAdmin = address(0)`.
3. X calls `acceptAdmin()`.
4. System reverts with `NotPendingAdmin`.
5. The admin calls `transferAdmin(N)`, then `addAdmin(N)`, so N is an admin and still the pending admin.
6. N calls `renounceAdminRole()`.
7. System sets `admins(N) = 0` and `pendingAdmin = address(0)`.

**Outcomes:**
- A removed or renounced address cannot accept an earlier proposal.

**Side Effects:**
- `RemovedAdmin(X, admin)` event emitted even though X held no role.
