# Auth Rate Limiting (Application + Gateway/WAF)

## Why ASP.NET app-level limiting is not enough
- The current `AddRateLimiter` policies in `Norge360.Auth.API` run inside each API instance.
- In multi-instance deployments, this is node-local. Attack traffic can be spread across nodes and bypass per-node thresholds.
- App-level limiter is still useful as a last-mile safeguard, but it must not be treated as the primary brute-force control.

## Multi-instance risk
- With `N` auth instances, an attacker can get roughly `N x permit-limit` effective budget.
- Instance churn/autoscaling changes effective global limits unpredictably.
- If edge and origin are both public, direct-origin traffic can bypass edge controls.

## Required control: distributed/global limits at Gateway/WAF
- Enforce global rate limits at Cloudflare/API Gateway/WAF before traffic reaches auth service.
- Keep app-level limiter enabled as defense-in-depth.

## Recommended endpoint policies
- `POST /api/auth/login` (and legacy `/login` if routed)
- `POST /api/auth/register` (and legacy `/register`)
- `POST /api/auth/forgot-password` (and legacy `/forgot-password`)
- `POST /api/auth/reset-password` (and legacy `/reset-password`)
- `POST /api/auth/resend-confirm-email` (and legacy `/resend-confirmation` if exposed)
- `POST /api/auth/refresh` (and legacy `/refresh`)
- `POST /api/auth/logout` (and legacy `/logout`)

## Recommended dimensions (keys)
- `method + path` (base partition)
- source IP
- tenant (`tenant_id` or trusted tenant context)
- tenant + normalized identity/email hash (for login/forgot/resend abuse)

Do not use raw email/identity in logs, labels, or WAF analytics fields.

## Example WAF/Gateway rule set (conceptual)
1. Login hard limit:
   - Key: `ip + method + path`
   - Action: challenge, then block on repeated violations
2. Tenant protection:
   - Key: `tenant + method + path`
   - Action: throttle/challenge
3. Account-target protection:
   - Key: `tenant + identity_hash + method + path`
   - Action: throttle
4. Refresh/logout abuse guard:
   - Key: `ip + tenant + method + path`
   - Action: throttle/challenge

Tune exact thresholds by observed baseline traffic.

## Rollout and safety notes
- Start with monitor/challenge mode in staging.
- Validate false-positive rates before block mode.
- Enable structured security event monitoring for:
  - rate-limit rejections
  - challenged/blocked requests by endpoint
  - tenant-level spikes

## Origin bypass prevention
- Origin firewall must allow traffic only from Cloudflare/Gateway egress IP ranges.
- Block direct internet access to auth origin, otherwise distributed edge limits can be bypassed.
