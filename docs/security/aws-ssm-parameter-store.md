# AWS SSM Parameter Store (SecureString) for Norge360

## Purpose
- Centralize sensitive configuration and secrets outside repository files.
- Use AWS SSM `SecureString` + KMS for secret material.
- Keep local development productive with explicit fallback (`appsettings.Development.json`, user-secrets, environment variables).

## Runtime integration
- Shared extension: `builder.Configuration.AddNorge360AwsParameterStore(builder.Environment);`
- Implementation location: `packages/dotnet/src/Norge360.Configuration`.
- Current behavior: startup-time load (snapshot). `ReloadOnChange=true` is currently informational and not active hot-reload.

## Path standard
- `/norge360/{environment}/shared/database/default-connection`
- `/norge360/{environment}/shared/redis/connection-string`
- `/norge360/{environment}/shared/rabbitmq/connection-string`
- `/norge360/{environment}/auth/database/connection-string`
- `/norge360/{environment}/auth/jwt/signing-keys`
- `/norge360/{environment}/auth/dataprotection/key-ring`
- `/norge360/{environment}/notification/email/provider`
- `/norge360/{environment}/notification/email/from-address`
- `/norge360/{environment}/notification/email/from-name`
- `/norge360/{environment}/notification/email/ses/region`
- `/norge360/{environment}/notification/email/ses/configuration-set`
- `/norge360/{environment}/notification/email/smtp/host`
- `/norge360/{environment}/notification/email/smtp/port`
- `/norge360/{environment}/notification/email/smtp/username`
- `/norge360/{environment}/notification/email/smtp/password`

## Mapping strategy
- Known auth/notification/shared paths are mapped to existing config keys (for example: `auth/database/connection-string -> ConnectionStrings:IdentityConnection`).
- Unknown paths are mapped hierarchically (`/a/b/c-d` -> `A:B:CD` style).
- `auth/jwt/signing-keys` supports JSON payload flattening into `Jwt:SigningKeys:*` keys.

## Local fallback
- Development/Test can keep `Infrastructure:AwsParameterStore:Enabled=false`.
- App uses local config chain without requiring AWS calls.

## Production fail-fast
- `Infrastructure:AwsParameterStore:Enabled=true` and `RequireInProduction=true`.
- `RequiredConfigurationKeys` list is validated after load.
- Missing required keys causes startup failure.

## Security notes
- Do not store raw secrets in repo files.
- Do not log secret values; logs may contain path/key names only.
- Use IAM role/instance profile/task role credential chain. Avoid static credentials in app config.

## KMS and SecureString
- Use customer-managed KMS key where required by compliance.
- Secrets should be written as `SecureString`.
- Non-sensitive toggles may remain `String`.

## IAM minimum scope (example)
- `ssm:GetParameter`
- `ssm:GetParametersByPath`
- `kms:Decrypt` for KMS key(s) used by SecureString parameters
- Scope resources to `/norge360/{environment}/*` and explicit key ARNs.
