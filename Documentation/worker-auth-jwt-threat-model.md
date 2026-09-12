# Worker JWT Verification Threat Model

## Scope

This document covers bearer-token authentication for the `workers/moderation`
Worker. It is intentionally limited to JWT signature verification, JWKS key
rotation, and revocation latency.

## Current decision

The Worker does not perform local JWT signature verification and does not cache
JWKS keys. Its protected-request flow is:

1. Parse the `Authorization: Bearer` header.
2. Reject malformed, expired, wrong-audience, wrong-issuer, or invalid-subject
   tokens with the local claim pre-check.
3. Call Supabase Auth `getUser(token)` over the network.
4. Use only the user ID returned by Supabase Auth for role and resource checks.

The local claim pre-check is not authentication. The JWT payload is untrusted
until Supabase Auth accepts the token. This preserves server-side signature,
session, and revocation checks and means the Worker has no local-JWKS
revocation gap today. If the Auth request fails, the Worker does not fall back
to the unverified claims.

## Threat model if local verification is introduced

### Assets and trust boundaries

- **Protected assets:** moderation routes, service-role database operations,
  private media authorization, and moderator role state.
- **Untrusted input:** every bearer token, including its header, payload,
  `kid`, `alg`, `iss`, `aud`, and `sub` values.
- **Trusted issuer:** the fixed project issuer derived from `SUPABASE_URL`.
- **Trusted key source:** only the issuer's HTTPS JWKS endpoint; never a URL
  supplied by a request.
- **Authorization source:** the database role/resource checks. JWT claims must
  not replace the moderator-role lookup or ownership checks.

### Key rotation and stale-key threats

If local verification is added, the verifier must handle both the current and
previously used signing key during a normal rotation. A cache that is too old
can reject valid tokens signed by a new key, while a cache that retains a
revoked key can continue accepting tokens that should no longer be trusted.

Required controls:

- Use `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json` for the
  fixed project issuer.
- Allow only explicitly configured asymmetric algorithms and validate the
  `alg`, `kty`, `use`, and `kid` relationship. Never accept an algorithm chosen
  by the token alone.
- Keep the application JWKS cache no longer than the provider's documented
  cache window unless an authenticated purge mechanism exists.
- On an unknown `kid`, perform one coalesced refresh before rejecting the token;
  do not retry unboundedly or fall back to a stale key without an explicit
  incident policy.
- Isolate caches by issuer and environment. A key from another Supabase
  project or deployment must never verify this project's token.
- Emit bounded operational metrics for JWKS refresh failures, unknown `kid`,
  and key-set changes. Never log bearer tokens or full JWT claims.

### Revocation-latency threats

Local signature verification proves that a token was signed by a trusted key;
it does not prove that the session is still active. A locally verified token
can remain usable until its `exp` time after sign-out, session revocation,
password reset, or an account-security event.

Required controls:

- Define the maximum acceptable revocation window before enabling local-only
  verification. The window must be no longer than the configured access-token
  lifetime plus the bounded JWKS cache interval.
- Keep Supabase Auth `getUser` or another online revocation check on
  high-impact moderation, destructive, and secret-bearing operations unless a
  documented denylist/introspection design provides an equivalent guarantee.
- Provide an incident path to bypass or purge local verification caches and to
  disable local-only verification without shipping a client update.
- Test sign-out, user disablement, password reset, and key revocation against
  both cached and freshly fetched keys.

### Failure modes

| Failure | Safe behavior |
| --- | --- |
| JWKS endpoint unavailable | Reject tokens whose key is not already trusted; never accept an unknown key or use token claims as identity. |
| Unknown `kid` | Coalesce one forced refresh, then reject if still unknown. |
| Key revoked | Reject after cache purge/refresh; retain online verification for operations requiring immediate revocation. |
| Algorithm or issuer mismatch | Reject before authorization and do not retry with another algorithm or issuer. |
| Supabase Auth unavailable in current design | Do not authorize from local claims; return an authentication failure. |

## Decision gate for a future implementation

Local signature verification should not be introduced until all of the
following are reviewed and tested:

1. The project is using asymmetric Supabase signing keys and the exact signing
   algorithms are recorded.
2. JWKS cache TTL, forced-refresh behavior, cache coalescing, and purge/incident
   controls are implemented and observable.
3. The accepted revocation window is approved for each route class, with
   moderation and destructive operations explicitly covered.
4. Tests cover current, previous, revoked, unknown, and rotated keys plus
   expired, wrong-issuer, wrong-audience, and malformed tokens.
5. Remote Supabase `getUser` remains the fallback for routes that require
   immediate revocation guarantees.

Until this gate is met, the Worker must keep the current remote `getUser`
verification path. The local claim pre-check may remain as an early rejection
and performance guard, but must never establish identity by itself.

## References

- [Supabase JWT Signing Keys](https://supabase.com/docs/guides/auth/signing-keys)
- [Supabase JSON Web Token guidance](https://supabase.com/docs/guides/auth/jwts)
- [Supabase JavaScript `auth.getUser`](https://supabase.com/docs/reference/javascript/auth-getuser)
- [RFC 8725 — JSON Web Token Best Current Practices](https://www.rfc-editor.org/rfc/rfc8725)
