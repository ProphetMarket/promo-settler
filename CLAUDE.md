<!-- molcajete:principles:start -->
## Engineering Principles (Molcajete)

Trust comes from tests, not code shape. Code can change; behavior is the contract.

- Integration tests are the only test type Molcajete generates. Every UC and feature is backed by integration tests, no exceptions. Unit tests, if the team wants them for algorithmic code, live outside Molcajete's lifecycle and are not counted toward the coverage floor.
- Hexagonal architecture: drive tests through driver ports with the real internal stack; mock only the outer-edge driven ports.
- Dependency injection makes the outer edge swappable at test time.
- 80% coverage floor on touched files (configurable via `.molcajete/settings.json testing.threshold`).
- Small functions, clear module boundaries, no god files. Refactor to reuse; never duplicate.
- Principles are technology-agnostic. The stack is recorded in `specs/TECH-STACK.md`.
- Write every spec, plan, comment, and report in Simplified Technical English (ASD-STE100): one meaning per word, active voice, simple tenses, one instruction per sentence.
- Name the concept before its identifier. Write "register user (UC-0KTg)", never `UC-0KTg` alone. Machine-readable fields, file paths, and defined comment formats keep the bare ID.
- Carry what the reader needs for their next action, then stop. Never drop a fact to meet a budget — move it or split it instead.

See `.claude/rules/principles.md` for full text and rationale. Re-read it before any architecture decision, test-scope decision, or refactor.
<!-- molcajete:principles:end -->
