#!/usr/bin/env python3
"""Unit tests for deploy runner dry-run planning."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from tools.deploy import runner_lib


class RunnerDryRunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace_root = Path(self.temp_dir.name)
        self.config_path = (
            self.workspace_root / "tools" / "deploy" / "dev_environment.json"
        )
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        self.config_path.write_text(
            json.dumps(
                {
                    "gcp": {
                        "project_id": "victor-dev-project",
                        "region": "europe-west1",
                        "artifact_registry_repository": "victor-dev",
                    },
                    "github_actions": {
                        "workload_identity_provider": "projects/123/providers/test",
                        "service_account": "deployer@example.com",
                    },
                    "firebase": {
                        "project_id": "victor-dev-project",
                        "default_tester_groups": ["android-dev-testers"],
                    },
                },
            )
            + "\n",
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _write_manifest(self, name: str, payload: dict[str, object]) -> Path:
        path = self.workspace_root / f"{name}.json"
        path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
        return path

    def _dry_run(self, manifest_path: Path) -> dict[str, object]:
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            rc = runner_lib.main(
                [
                    "--manifest",
                    str(manifest_path),
                    "--config",
                    str(self.config_path),
                    "--workspace-root",
                    str(self.workspace_root),
                    "--dry-run",
                ],
            )
        self.assertEqual(rc, 0)
        return json.loads(stdout.getvalue())

    def test_grpc_server_dry_run(self) -> None:
        backend_dir = (
            self.workspace_root
            / "bazel-out"
            / "test"
            / "bin"
            / "example"
            / "greeter"
            / "kotlin"
        )
        (backend_dir / "backend.runfiles").mkdir(parents=True)
        (backend_dir / "backend").write_text("#!/usr/bin/env bash\n", encoding="utf-8")
        (backend_dir / "backend.repo_mapping").write_text("", encoding="utf-8")
        (backend_dir / "backend.runfiles_manifest").write_text("", encoding="utf-8")

        plan = self._dry_run(
            self._write_manifest(
                "backend_manifest",
                {
                    "deploy_kind": "grpc_server",
                    "service": "greeter-backend-dev",
                    "app_executable_path": "bazel-out/test/bin/example/greeter/kotlin/backend",
                    "app_runfiles_path": "bazel-out/test/bin/example/greeter/kotlin/backend.runfiles",
                    "app_repo_mapping_path": "bazel-out/test/bin/example/greeter/kotlin/backend.repo_mapping",
                    "app_runfiles_manifest_path": "bazel-out/test/bin/example/greeter/kotlin/backend.runfiles_manifest",
                },
            ),
        )

        self.assertEqual(plan["deploy_kind"], "grpc_server")
        self.assertEqual(plan["service"], "greeter-backend-dev")
        self.assertIn("eclipse-temurin:21-jre", plan["dockerfile"])
        self.assertIn("docker", plan["commands"][1][0])
        self.assertIn("gcloud", plan["commands"][3][0])
        self.assertTrue(
            plan["image_uri"].endswith("/greeter-backend-dev:" + plan["revision"])
        )

    def test_web_app_dry_run_with_backend(self) -> None:
        dist_dir = (
            self.workspace_root
            / "bazel-out"
            / "test"
            / "bin"
            / "example"
            / "greeter"
            / "web"
            / "dist"
        )
        dist_dir.mkdir(parents=True)
        (dist_dir / "index.html").write_text("<html></html>\n", encoding="utf-8")
        backend_manifest = self._write_manifest(
            "backend_manifest",
            {
                "deploy_kind": "grpc_server",
                "service": "greeter-backend-dev",
            },
        )
        plan = self._dry_run(
            self._write_manifest(
                "web_manifest",
                {
                    "deploy_kind": "web_app",
                    "site": "greeter-web-dev",
                    "app_dist_path": "bazel-out/test/bin/example/greeter/web/dist",
                    "backend_manifest_path": str(
                        backend_manifest.relative_to(self.workspace_root)
                    ),
                },
            ),
        )

        self.assertEqual(plan["deploy_kind"], "web_app")
        self.assertEqual(plan["site"], "greeter-web-dev")
        self.assertEqual(plan["firebase_json"]["hosting"]["public"], "public")
        rewrites = plan["firebase_json"]["hosting"]["rewrites"]
        self.assertEqual(rewrites[0]["run"]["serviceId"], "greeter-backend-dev")
        self.assertTrue(rewrites[0]["run"]["pinTag"])

    def test_android_app_dry_run_uses_default_tester_groups(self) -> None:
        apk_path = (
            self.workspace_root
            / "bazel-out"
            / "test"
            / "bin"
            / "example"
            / "greeter"
            / "android"
            / "app.apk"
        )
        apk_path.parent.mkdir(parents=True)
        apk_path.write_text("apk", encoding="utf-8")

        plan = self._dry_run(
            self._write_manifest(
                "android_manifest",
                {
                    "deploy_kind": "android_app",
                    "firebase_app_id": "1:1234567890:android:deadbeef",
                    "apk_path": "bazel-out/test/bin/example/greeter/android/app.apk",
                    "tester_groups": [],
                },
            ),
        )

        self.assertEqual(plan["deploy_kind"], "android_app")
        self.assertEqual(plan["tester_groups"], ["android-dev-testers"])
        command = plan["commands"][0]
        self.assertEqual(command[0], "firebase")
        self.assertIn("--groups", command)
        self.assertIn("1:1234567890:android:deadbeef", command)


if __name__ == "__main__":
    unittest.main()
