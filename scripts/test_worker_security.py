#!/usr/bin/env python3
"""Regression tests for the repository-level Worker secret scan."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCANNER = Path(__file__).with_name("check_worker_secrets.py")
WORKER_SOURCE = Path(__file__).parents[1] / "workers" / "moderation" / "src" / "index.ts"
JWT_THREAT_MODEL = Path(__file__).parents[1] / "Documentation" / "worker-auth-jwt-threat-model.md"


class WorkerSecurityScanTests(unittest.TestCase):
    def run_scan(self, files: dict[str, str]) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for relative_path, content in files.items():
                path = root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(SCANNER), "--root", str(root)],
                capture_output=True,
                text=True,
                check=False,
            )

    def test_examples_and_source_markers_are_allowed(self) -> None:
        result = self.run_scan(
            {
                ".dev.vars.example": "SUPABASE_SERVICE_ROLE_KEY=your-service-role-key\n",
                "src/import-key.ts": (
                    'const marker = "-----BEGIN PRIVATE KEY-----";\n'
                    'const clean = value.replace(marker, "");\n'
                ),
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_local_secret_file_is_rejected_without_echoing_value(self) -> None:
        secret = "super-secret-value"
        key_name = "SUPABASE_SERVICE_ROLE_KEY"
        result = self.run_scan({".dev.vars": f"{key_name}={secret}\n"})
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(secret, result.stdout + result.stderr)

    def test_secret_assignment_is_rejected_without_echoing_value(self) -> None:
        secret = "actual-private-key-value"
        key_name = "APNS_PRIVATE_KEY"
        result = self.run_scan(
            {"src/config.ts": f'const {key_name} = "{secret}";\n'}
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(secret, result.stdout + result.stderr)

    def test_supabase_cli_temp_state_is_not_scanned(self) -> None:
        key_name = "SUPABASE_SERVICE_ROLE_KEY"
        result = self.run_scan(
            {
                "supabase/.temp/start-secrets/env/docker.env": (
                    f"{key_name}=local-generated-secret\n"
                )
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_worker_auth_validates_bearer_claims_before_remote_user_lookup(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")

        self.assertIn("function hasValidSupabaseAccessTokenClaims", source)
        self.assertIn("payload.exp", source)
        self.assertIn("payload.aud", source)
        self.assertIn("payload.iss", source)
        self.assertIn("expectedSupabaseAuthIssuer", source)
        self.assertIn('audience.includes("authenticated")', source)
        self.assertIn('`${new URL(supabaseURL).origin}/auth/v1`', source)
        self.assertIn("getUser(token)", source)
        self.assertEqual(source.count("auth.getUser("), 1)

    def test_supabase_calls_have_a_bounded_deadline_without_sdk_retries(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")

        self.assertIn("const supabaseRequestTimeoutMilliseconds = 10_000", source)
        self.assertIn("const supabaseFetchWithTimeout: typeof fetch", source)
        self.assertIn("setTimeout(() => controller.abort(), supabaseRequestTimeoutMilliseconds)", source)
        self.assertIn("db: { timeout: supabaseRequestTimeoutMilliseconds, retry: false }", source)
        self.assertEqual(source.count("global: { fetch: supabaseFetchWithTimeout }"), 2)

    def test_worker_jwt_threat_model_preserves_remote_verification_boundary(self) -> None:
        threat_model = JWT_THREAT_MODEL.read_text(encoding="utf-8")

        self.assertIn("does not perform local JWT signature verification", threat_model)
        self.assertIn("JWKS", threat_model)
        self.assertIn("Revocation-latency threats", threat_model)
        self.assertIn("unknown `kid`", threat_model)
        self.assertIn("Remote Supabase `getUser`", threat_model)

    def test_account_deletion_uses_verified_identity_and_server_cleanup(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")
        start = source.index('app.post("/account/delete"')
        end = source.index("// This member-authenticated endpoint", start)
        route = source[start:end]

        self.assertIn("authenticatedUserID(context)", route)
        self.assertIn("begin_community_account_deletion", route)
        self.assertIn("processPendingAccountDeletionJobs", route)
        self.assertIn("}, 202)", route)
        self.assertNotIn("prepare_community_account_deletion", route)
        self.assertNotIn("auth.admin.deleteUser(userID)", route)
        self.assertNotIn("context.req.json", route)
        self.assertIn("auth.admin.deleteUser(job.user_id)", source)
        self.assertIn("record_community_account_deletion_inventory", source)
        self.assertIn("claim_community_account_deletion_media", source)
        self.assertIn('"uploader_id"', source)
        self.assertIn('"community_direct_message_attachments"', source)
        self.assertIn('[userID],\n    true\n  );', source)
        self.assertIn('.storage\n        .from(bucket)\n        .list(', source)

    def test_account_export_and_retention_are_server_owned(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")
        migration = (
            Path(__file__).parents[1]
            / "supabase"
            / "migrations"
            / "20260912200000_add_account_export_and_moderation_retention.sql"
        ).read_text(encoding="utf-8")
        paginated_migration = (
            Path(__file__).parents[1]
            / "supabase"
            / "migrations"
            / "20260913120000_add_paginated_account_export.sql"
        ).read_text(encoding="utf-8")
        start = source.index('app.post("/account/export"')
        end = source.index("// This member-authenticated endpoint", start)
        route = source[start:end]

        self.assertIn("authenticatedUserID(context)", route)
        self.assertIn("export_community_account_metadata", route)
        self.assertIn("export_community_account_section", route)
        self.assertNotIn("export_community_account_data", route)
        self.assertIn('"Cache-Control": "no-store"', route)
        self.assertNotIn("context.req.json", route)
        self.assertIn("purge_community_moderation_retention", source)
        self.assertIn("pruneModerationRetention(env)", source)
        self.assertIn("communityAccountExportMaximumCharacters", source)
        self.assertIn("export_community_account_metadata", route)
        self.assertIn("export_community_account_section", route)
        self.assertIn("account export too large", route)
        self.assertIn("set_config('statement_timeout', '15000', true)", migration)
        self.assertIn("export_community_account_metadata", paginated_migration)
        self.assertIn("export_community_account_section", paginated_migration)
        self.assertIn("page_size not between 1 and 250", paginated_migration)
        self.assertIn("limit $3", paginated_migration)

    def test_account_export_has_a_server_side_member_quota(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")
        migration = (
            Path(__file__).parents[1]
            / "supabase"
            / "migrations"
            / "20260913110000_add_community_request_rate_limits.sql"
        ).read_text(encoding="utf-8")
        start = source.index('app.post("/account/export"')
        end = source.index("// This member-authenticated endpoint", start)
        route = source[start:end]

        self.assertIn('"consume_community_request_rate_limit"', route)
        self.assertIn('target_bucket: "account_export"', route)
        self.assertIn("target_limit: 3", route)
        self.assertIn('account_export_rate_limited', route)
        self.assertIn('"Retry-After": "3600"', route)
        self.assertIn("create table if not exists public.community_request_rate_limits", migration)
        self.assertIn("community_request_rate_limits", migration)
        self.assertIn("target_user_id uuid default null", migration)
        self.assertIn("to authenticated, service_role", migration)
        self.assertIn("community_conversation_request_rate_limit", migration)
        self.assertIn("community_direct_message_rate_limit", migration)
        self.assertIn("community_group_message_rate_limit", migration)
        self.assertIn("community_report_rate_limit", migration)

        scan_status_start = source.index("async function mediaScanStatusResponse(")
        scan_status_end = source.index("function mediaViewResponse(", scan_status_start)
        scan_status = source[scan_status_start:scan_status_end]
        self.assertIn('target_bucket: "media_scan_status"', scan_status)
        self.assertIn('media_scan_rate_limited', scan_status)
        self.assertIn('"Retry-After": "60"', scan_status)

    def test_private_media_view_rechecks_authorization_before_using_cache(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")
        start = source.index("async function issuePrivateMediaViewURL(")
        end = source.index("function readPrivateMediaViewCache", start)
        issue_function = source[start:end]

        authorization_position = issue_function.index('.rpc("issue_community_media_view"')
        cache_position = issue_function.index("const cached = readPrivateMediaViewCache(cacheKey)")

        self.assertLess(authorization_position, cache_position)
        self.assertIn("const providerAssetID = authorization.provider_asset_id", issue_function)
        self.assertIn("cached?.providerAssetID === providerAssetID", issue_function)
        self.assertIn("const providerRequestKey = `${cacheKey}:${providerAssetID}`", issue_function)
        self.assertIn("privateMediaViewInFlight.get(providerRequestKey)", issue_function)
        self.assertNotIn('if (cached) return { status: "ok", url: cached }', issue_function)

    def test_media_upload_routes_use_atomic_server_staging(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")
        group_start = source.index('app.post("/media/group-chat/upload-url"')
        group_end = source.index('app.post("/media/group-chat/:attachmentID/upload-complete"', group_start)
        direct_start = source.index('app.post("/media/direct-chat/upload-url"')
        direct_end = source.index('app.post("/media/direct-chat/:attachmentID/upload-complete"', direct_start)
        group_route = source[group_start:group_end]
        direct_route = source[direct_start:direct_end]

        self.assertIn('"stage_community_group_chat_attachment"', group_route)
        self.assertIn('"stage_community_direct_message_attachment"', direct_route)
        self.assertNotIn('.select("id", { count: "exact", head: true })', group_route)
        self.assertNotIn('.select("id", { count: "exact", head: true })', direct_route)
        self.assertNotIn('crypto.randomUUID()', group_route)
        self.assertNotIn('crypto.randomUUID()', direct_route)

    def test_http_json_bodies_are_bounded_and_runtime_validated(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")

        self.assertIn("async function readBoundedJSONBody", source)
        self.assertIn('context.req.raw.body', source)
        self.assertIn('context.req.header("Content-Length")', source)
        self.assertIn('request_body_too_large', source)
        self.assertIn('bodyResult.reason === "too_large" ? 413 : 400', source)
        self.assertNotIn("context.req.json<", source)

        for limit in (
            "mediaJSONBodyLimitBytes",
            "moderationJSONBodyLimitBytes",
            "pushWebhookJSONBodyLimitBytes",
        ):
            self.assertIn(f"readBoundedJSONBody(context, {limit})", source)

        self.assertIn("isRecord(payload.record)", source)
        self.assertIn("normalizedOptionalText(body.note, 1_000)", source)
        self.assertIn('typeof body.restrictionHours === "number"', source)

    def test_media_provider_cleanup_is_durable_on_provider_failure(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")

        self.assertIn("quarantineUntrackedMediaProviderAsset", source)
        self.assertIn('status: "deleted"', source)
        self.assertIn("provider_asset_id: providerAssetID", source)
        self.assertIn("group_media_cancellation_provider_cleanup_deferred", source)
        self.assertIn("direct_media_cancellation_provider_cleanup_deferred", source)
        self.assertIn("finalize_community_media_cleanup", source)
        self.assertGreaterEqual(source.count("!await deleteCloudflareImage"), 2)

    def test_push_delivery_retries_active_leases_and_recovers_expired_rows(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")
        migration = (
            Path(__file__).parents[1]
            / "supabase"
            / "migrations"
            / "20260913100000_harden_push_delivery_leases.sql"
        ).read_text(encoding="utf-8")

        self.assertIn("CommunityPushDeliveryRetryableError", source)
        self.assertIn("pushDeliveryRetryDelay(leasedRows)", source)
        self.assertIn('row.claim_state === "leased"', source)
        self.assertIn("dispatchExpiredCommunityPushDeliveries", source)
        self.assertIn("requeue_expired_community_push_deliveries", source)
        self.assertIn("drop function if exists public.claim_community_push_deliveries", migration)
        self.assertIn("claim_state text", migration)
        self.assertIn("for update skip locked", migration)

    def test_transport_retention_is_bounded_and_service_owned(self) -> None:
        source = WORKER_SOURCE.read_text(encoding="utf-8")
        migration = (
            Path(__file__).parents[1]
            / "supabase"
            / "migrations"
            / "20260913150000_add_transport_retention_purge.sql"
        ).read_text(encoding="utf-8")

        self.assertIn('"purge_community_transport_retention"', source)
        self.assertIn("pruneTransportRetention(env)", source)
        self.assertIn("interval '30 days'", migration)
        self.assertIn("interval '7 days'", migration)
        self.assertIn("processing' and ledger.attempts >= 5", migration)
        self.assertIn("for update skip locked", migration)
        self.assertIn("grant execute on function public.purge_community_transport_retention(integer) to service_role", migration)
        self.assertIn("revoke all on function public.purge_community_transport_retention(integer) from public, anon, authenticated", migration)


if __name__ == "__main__":
    unittest.main()
