# Auth Key Rotation Runbook

## Scope
- JWT signing key rotation for `Norge360.Auth.API`
- ASP.NET DataProtection key rotation/persistence for auth secrets (MFA/outbox payload protection)

## Current implementation summary
- JWT tokens include `kid` (`JwtAccessTokenFactory`).
- JWKS endpoint is exposed at `/.well-known/jwks.json`.
- Validation supports multiple active public keys (`IssuerSigningKeys` from `TokenSigningKeyProvider`).
- Exactly one signing key must be marked current (`Jwt:SigningKeys:IsCurrent` validation).
- Production fail-fast exists for missing/unsafe signing key settings.
- DataProtection supports persistent key ring path and production validation (`RequirePersistentKeyRingInProduction`).

## Decision: no runtime hot-reload in this hardening pass
- Runtime key hot-reload is not added.
- Reason: lower-risk and auditable approach is formal rotation with controlled deploy/restart.
- Existing multi-key validation + JWKS already supports safe overlap-based rotation.

## JWT signing key rotation procedure

### 1) Pre-rotation
- Generate a new RSA key pair.
- Assign a unique `kid` (example: `auth-rsa-prod-2026-07`).
- Add new key to `Jwt:SigningKeys` in config/secrets.
- Keep current key present for validation overlap.
- Ensure only one key has `IsCurrent=true` after the planned cutover step.

### 2) Rotation deploy (safe overlap)
- Step A: Deploy config with both old and new keys available; keep old key as current.
- Step B: Deploy config switching `IsCurrent=true` to new key.
- Step C: Roll through all instances (rolling restart/deploy) until every instance signs with new key.

### 3) Overlap window
- Keep old key in validation set for at least:
  - max access-token lifetime (`Jwt:AccessTokenMinutes`)
  - plus operational skew/JWKS cache margin
- Do not remove old key immediately after cutover.

### 4) Post-overlap cleanup
- Remove old private/public key material from config.
- Deploy and verify all instances expose only intended keys in JWKS.

## Refresh/session implications
- Access tokens rotate naturally on refresh.
- Key rotation does not require immediate session revocation by itself.
- If compromise is suspected, follow emergency procedure below.

## Rollback plan
- If new key causes validation/signing failures:
  - restore previous config with old key as `IsCurrent=true`
  - redeploy all instances
  - verify JWKS and token issuance/validation health checks

## Emergency compromise response
- Immediately rotate to a fresh key (`IsCurrent=true`).
- Remove compromised key from validation set as soon as feasible.
- Invalidate active auth state:
  - increment affected users' token/security state (`TokenVersion` strategy)
  - revoke sessions (`UserSession` revocation paths) as required by incident scope
- Monitor failed token validations and suspicious refresh attempts.

## Deploy/restart order (multi-instance consistency)
- Use rolling deploy with health checks enabled.
- Confirm each instance loads identical key set/version.
- Avoid partial long-lived mixed configs beyond planned overlap window.

## JWKS cache considerations
- Downstream verifiers may cache JWKS.
- Keep overlap long enough to cover consumer cache TTL + propagation delay.
- During emergency compromise, communicate forced cache refresh requirements.

## DataProtection key rotation and persistence

### Production requirements
- Use a shared persistent key ring across auth instances (`Infrastructure:DataProtection:KeyRingPath`).
- Keep `RequirePersistentKeyRingInProduction=true`.

### Operational notes
- DataProtection rotates keys automatically; ensure shared storage is durable.
- Back up key ring storage.
- Key ring loss can break decryption of previously protected payloads (MFA secrets/outbox protected payloads).

## Operational checklist

### Before rotation
- Confirm new key quality/size and unique `kid`.
- Confirm staging validation and JWKS visibility.
- Confirm alerting dashboards for auth failures.

### During rotation
- Deploy overlap config.
- Switch current signing key.
- Complete rolling deployment.

### After rotation
- Validate login/refresh/protected flows.
- Validate JWKS content and health checks.
- Monitor auth failure spikes.

### Rollback
- Re-enable previous `IsCurrent` key.
- Redeploy.
- Re-verify end-to-end auth.

### Incident response
- Trigger emergency key replacement.
- Execute scoped revoke/invalidation.
- Preserve audit/security alert timeline for postmortem.
