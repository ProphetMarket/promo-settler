# Modules

> Physical application layers that make up the system.
> Each module maps to a deployable application, service, or package.
> `Tests` is the per-module root for integration/component test files; see the plan-authoring skill's Test File Convention.
> `Driving Ports` is the comma-separated list of inbound entry-point kinds the module exposes (e.g., `http, event, cron`). The entry point a task drives must be one of these values. See the setup skill's "Driving Ports Column" rule.

| ID | Module | Description | Directory | Tests | Driving Ports |
|----|--------|-------------|-----------|-------|---------------|
| contracts | Promo Settler Contracts | Solidity smart contract that pays a promotional USDC credit and forwards a trade to ProphetCTFExchange in one transaction, so the credit reaches the user's Safe wallet only when the trade it funds settles | `.` | `test/features` | contract-call |
