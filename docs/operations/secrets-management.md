# Secrets Management Runbook

## Scope
- Auth API and Notification Worker runtime secrets.
- AWS SSM Parameter Store as source of truth for production secrets.

## Rules
- Never commit real secrets to repository.
- Use placeholders only in `appsettings*.json`.
- Prefer `SecureString` for credentials, keys, tokens, connection strings.
- Rotate secrets on schedule and after incidents.

## Secret sources by environment
- Development: user-secrets + local appsettings + env vars.
- Production: SSM Parameter Store + IAM role credentials.

## Rotation checklist
1. Create new value in SSM under same logical key/path.
2. Validate in staging.
3. Roll deployment.
4. Confirm startup validation and health checks.
5. Remove deprecated material after cutover window.

## Incident checklist
1. Revoke compromised credentials/keys.
2. Rotate affected SSM parameters.
3. Restart or redeploy affected services.
4. Revoke active auth sessions/tokens when relevant.
5. Audit logs and security events.

## Audit and observability
- Alert on startup failures due to missing required config keys.
- Alert on repeated SSM load failures.
- Do not emit secret values in logs, traces, or metric labels.
