# Norge360 moderation Worker

This Worker is the server-only boundary for reviewing community reports and applying reversible moderation actions. It deliberately does not expose Supabase service-role credentials to the iOS app.

## Before deployment

1. Run the corresponding Supabase migrations, in order:
   - `20260909075000_add_server_moderation_review_workflow.sql`
   - `20260909100000_add_reversible_server_moderation_actions.sql`
   - `20260912100000_async_community_media_safety_scan.sql`
   - `20260912110000_async_community_media_cleanup.sql`
   - `20260912120000_async_push_delivery.sql`
2. Grant a first staff member a role from a trusted SQL session, for example:

   ```sql
   insert into public.community_moderator_roles (user_id, role)
   values ('<authenticated-user-uuid>', 'admin');
   ```

3. From this directory, install the locked dependencies and run the local deployment gates. Never use `.dev.vars` in source control.

   ```sh
   npm ci
   npm run secret-scan
   npm run check
   npm run types:check
   npm test
   npm audit --omit=dev --audit-level=high
   npm run deploy:dry-run
   ```

4. `SUPABASE_URL` is a non-secret development variable in `wrangler.toml`; do not store it with `wrangler secret put`. Store only these values as Worker secrets:

   ```sh
   npx wrangler secret put SUPABASE_ANON_KEY
   npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
   npx wrangler secret put PUSH_WEBHOOK_SECRET
   npx wrangler secret put APNS_KEY_ID
   npx wrangler secret put APNS_TEAM_ID
   npx wrangler secret put APNS_BUNDLE_ID
   npx wrangler secret put APNS_PRIVATE_KEY
   npx wrangler secret put CF_IMAGES_ACCOUNT_ID
   npx wrangler secret put CF_IMAGES_API_TOKEN
   npx wrangler secret put GOOGLE_VISION_API_KEY
   ```

   The Cloudflare Images token must have only the account-level permission required
   by the enabled Images operations. For a named environment, use the matching
   `--env <environment>` flag for both secret and deploy commands.

5. Production deployment must use a dedicated, minimum-scope `CLOUDFLARE_API_TOKEN`
   stored in the CI secret store, never a personal global API token. The token must
   be restricted to this Worker and its declared Queue/deployment operations. Deploy
   with the explicit environment after its separate resources have been provisioned:

   ```sh
   npx wrangler deploy --env production
   ```

## Secret rotation and rollback

- Keep the current provider credential valid while provisioning and smoke-testing its replacement.
- Update the corresponding Worker secret with `wrangler secret put <NAME>` using the intended environment; never commit or print the value.
- Deploy the new Worker version, verify `/health` and one protected operation, then revoke the old provider credential in Supabase, Cloudflare, Apple, Google, or the relevant provider console.
- Record the deployment/version and rotation event in the provider audit log and the team incident log.
- If the deployment fails, roll back the Worker version. Restore a previous secret only from the approved secret manager; never from repository history or shell output.

The repository workflow runs dependency installation from `package-lock.json`, production dependency audit, secret scanning, typecheck, generated-type verification, optional tests/lint, and Wrangler dry-run on Worker changes. It does not hold production credentials and does not deploy automatically.

## Routes

- `GET /health` — deployment health check.
- `GET /v1/reports?status=open&limit=50` — authenticated staff report queue.
- `GET /v1/reports/:reportID/context` — safe target preview and immutable action history.
- `POST /v1/reports/:reportID/resolve` — records an auditable, non-destructive review. Body:

  ```json
  {
    "status": "resolved",
    "action": "needs_investigation",
    "note": "Optional internal note"
  }
  ```

- `POST /v1/reports/:reportID/actions` — moderator/admin-only reversible enforcement. Body:

  ```json
  {
    "action": "remove_content",
    "note": "Internal, auditable reason",
    "memberNotice": "Optional clear explanation for the member"
  }
  ```

  Actions are `remove_content`, `restore_content`, `restrict_author`, and
  `revoke_author_restriction`. `restrict_author` may include
  `restrictionHours` from 1 through 8760; omit it for an indefinite posting
  restriction.

The caller must have a valid Supabase session and an entry in `community_moderator_roles`. Bearer-authenticated routes reject malformed, expired, wrong-audience, or wrong-issuer tokens before calling Supabase Auth; `auth.getUser` remains authoritative for signature, session, and revocation checks. The Worker checks the session, checks the role, and the database RPC checks the role again before recording the review. `npm test` combines source-level security contracts with runtime Hono handler tests using controlled Supabase fetch mocks; provider, Queue, and disposable Supabase/RLS integration tests remain deployment-pipeline work.

Reviewers can inspect and close reports, while moderators and admins can enforce
actions. The Worker and database both enforce that separation. Event removal,
appeals, media retention, and rate limits remain separate reviewed phases.
