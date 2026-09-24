# Feature Inventory

> The permanent catalog of all product features.
> Features are never removed -- they accumulate use cases over their lifetime.

## Status Key

- `pending` -- Spec written, not yet implemented
- `implemented` -- Code exists that fulfills this spec
- `dirty` -- Spec changed after implementation; code needs to catch up
- `deprecated` -- No longer active; retained for audit trail

## @settlement

| ID | Feature | Description | Status |
|----|---------|-------------|--------|
| FEAT-UFXS | Promo Credit Settlement | The settler pays a promotional USDC credit to the credited order's Safe and settles its trade in one transaction, capped per Safe and promo code | implemented |

## @admin

| ID | Feature | Description | Status |
|----|---------|-------------|--------|
| FEAT-UFXT | Settler Administration | The admin manages the settler's roles, credit maximum, pause, and token recovery to the promo wallet | implemented |
| FEAT-UFXU | Settler Deployment | The deployer creates the settler on Polygon, and on local Anvil with registration, funding, and a published address | implemented |
