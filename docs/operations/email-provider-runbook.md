# Email Provider Runbook

## Pre-deployment
1. Confirm `Notification:Email:Provider` for environment.
2. Confirm sender domain verification status (SES) or SMTP relay allowlist.
3. Confirm `notifications@norge360.com` is configured as sender.
4. Confirm SSM parameters exist for required provider settings.

## Production expectations
- Provider must not be `console` or `disabled`.
- From-address domain must be approved.
- SMTP must enforce STARTTLS and credentials.
- SES region/configuration set must be valid.

## Change procedure
1. Update SSM parameter values.
2. Deploy rolling restart.
3. Validate worker health and queue consumption.
4. Send smoke test email and verify delivery logs.

## Failure triage
- Startup failure: check options validation output and missing required keys.
- Delivery failure spikes: check provider credentials/network/TLS and retry behavior.
- No queue drain: check RabbitMQ connectivity and consumer health.

## Rollback
1. Restore previous SSM values.
2. Redeploy or restart worker instances.
3. Confirm queue starts draining and failure rate returns to baseline.
