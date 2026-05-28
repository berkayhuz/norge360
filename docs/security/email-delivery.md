# Email Delivery Security Baseline

## Sender standard
- Default sender address: `notifications@norge360.com`
- Default sender name: `Norge360 Notifications`

## Provider policy
- Supported providers: `ses`, `smtp`, `console`, `disabled`
- Production: `console` and `disabled` are rejected at startup.
- Development/Test: `console` or `disabled` can be used intentionally.

## From-address policy
- Sender domain must be approved (`Notification:Email:ApprovedSenderDomains`).
- Production should allow only controlled domains (for example `norge360.com`).

## Token/link handling
- Password-reset and verification URLs must never be written to logs.
- Raw token values must never be logged.
- Correlation IDs can be logged.

## Template safety
- HTML body placeholders are HTML-encoded during rendering.
- Keep user-controlled values out of unescaped HTML contexts.

## SES operational requirements
- Verify domain identity in SES.
- Configure SPF, DKIM, DMARC for sending domain.
- If Cloudflare is used, keep mail-related DNS records as DNS-only.
- Move out of SES sandbox before production traffic.

## Roadmap note
- Bounce/complaint webhook handling should be added for automated suppression and reputation controls.
