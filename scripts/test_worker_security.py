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

    def test_worker_jwt_threat_model_preserves_remote_verification_boundary(self) -> None:
        threat_model = JWT_THREAT_MODEL.read_text(encoding="utf-8")

        self.assertIn("does not perform local JWT signature verification", threat_model)
        self.assertIn("JWKS", threat_model)
        self.assertIn("Revocation-latency threats", threat_model)
        self.assertIn("unknown `kid`", threat_model)
        self.assertIn("Remote Supabase `getUser`", threat_model)


if __name__ == "__main__":
    unittest.main()
