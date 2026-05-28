# Norge360 Auth Test Suite

This folder contains the Auth bounded-context test architecture:

- `Norge360.Auth.ArchitectureTests`
- `Norge360.Auth.Domain.UnitTests`
- `Norge360.Auth.Application.UnitTests`
- `Norge360.Auth.Infrastructure.IntegrationTests`
- `Norge360.Auth.Api.FunctionalTests`
- `Norge360.Auth.Contracts.Tests`
- `Norge360.Auth.TestKit`

## Test Categories

- Architecture boundary rules (layer dependencies, clean architecture direction)
- Domain behavior and invariants
- Application handlers, validation, error mapping, token/session flows
- Infrastructure persistence and repository behavior
- API functional behavior (HTTP + ProblemDetails + auth/session endpoints)
- Contracts serialization and payload-shape assertions
- Security regression scenarios
- Startup/configuration validation

## Commands

Run from repository root:

```powershell
dotnet restore Norge360.slnx
dotnet build Norge360.slnx -c Release --no-restore -m:1 -v minimal
dotnet test Norge360.slnx -c Release --no-build -m:1 -v minimal
```

Auth-only test command with coverage:

```powershell
dotnet test services/auth/tests --collect:"XPlat Code Coverage"
```

Scripted flow:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-auth.ps1 -Restore
```

## Coverage / SonarQube Notes

- `coverlet.collector` is enabled in shared test props at `services/auth/tests/Directory.Build.props`.
- Coverage output is produced by `XPlat Code Coverage` in `TestResults/**/coverage.cobertura.xml`.
- Keep exclusions limited to generated artifacts (for example migration snapshots) and avoid excluding critical auth/security logic.
