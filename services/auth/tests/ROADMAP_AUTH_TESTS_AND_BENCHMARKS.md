# Auth Tests and Benchmarks Roadmap

## Goal
Build high-confidence, security-focused test and benchmark coverage for `services/auth` in phased, shippable increments.

## Principles
- Prioritize auth/security critical paths first.
- Add deterministic tests before performance measurements.
- Keep each phase independently runnable in CI.
- Use benchmarks mainly for regression guardrails, not vanity metrics.

## Phase Plan
1. Phase 0 - Baseline and Inventory
- Map source-to-test coverage for API/Application/Infrastructure/Domain.
- Identify untested public methods and security-sensitive branches.
- Produce a prioritized backlog by risk and request frequency.

2. Phase 1 - Critical Security Unit Coverage (start now)
- Add detailed unit tests for:
  - `PermissionAuthorizationHandler`
  - `TrustedInternalSourceAuthorizationHandler`
- Cover success, failure, edge, and malformed-input scenarios.

3. Phase 2 - Benchmark Foundation (start now)
- Create `Norge360.Auth.Benchmarks` project.
- Add initial micro-benchmarks for hottest synchronous authorization checks:
  - `PermissionAuthorizationHandler` (allow/deny variants)
  - `TrustedInternalSourceAuthorizationHandler` (allow/deny variants)
- Ensure output is compatible with existing merged HTML report flow.

4. Phase 3 - Application Handler Deep Matrix
- For each command/query handler:
  - happy-path
  - validation failure paths
  - security policy paths
  - persistence failure and cancellation propagation
- Add table-driven tests where possible to keep noise low.

5. Phase 4 - API Middleware and Endpoint Behavior
- Expand functional tests for all auth endpoints:
  - status codes
  - problem details contracts
  - cookie/session behavior
  - tenant and trusted gateway requirements
- Add negative tests for spoofed headers and malformed token flows.

6. Phase 5 - Infrastructure + Data Access Performance
- Add repository and token persistence benchmarks (read/write hot paths).
- Track allocations and p95/p99 where feasible.
- Add CI thresholds for selected benchmarks.

7. Phase 6 - CI Guardrails and Reporting
- Add auth-specific benchmark script and CI job.
- Fail builds on agreed regression thresholds.
- Publish consolidated benchmark HTML artifact.

## Definition of Done per Area
- Tests: meaningful branch/path coverage with clear assertions.
- Benchmarks: deterministic setup, Release config, no debug noise.
- Docs: command examples and expected outputs.
- CI: repeatable locally and on pipeline agents.

## Immediate Next Steps
1. Land Phase 1 + Phase 2 initial slice.
2. Run `dotnet test services/auth/tests/Norge360.Auth.Api.FunctionalTests`.
3. Run auth benchmark project and merge reports into `reports.html`.
