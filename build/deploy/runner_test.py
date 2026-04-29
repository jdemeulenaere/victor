#!/usr/bin/env python3
"""Unit tests for deploy runner dry-run planning."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from build.deploy import runner_lib


class RunnerDryRunTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace_root = Path(self.temp_dir.name)
        self.config_path = (
            self.workspace_root / "build" / "deploy" / "dev_environment.json"
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

    def _dry_run(
        self, manifest_path: Path, *, environment: dict[str, str] | None = None
    ) -> dict[str, object]:
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
                environment=environment,
            )
        self.assertEqual(rc, 0)
        return json.loads(stdout.getvalue())

    def test_grpc_server_dry_run(self) -> None:
        backend_dir = (
            self.workspace_root
            / "bazel-out"
            / "test"
            / "bin"
            / "src"
            / "samples"
            / "greeter"
            / "backend"
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
                    "app_executable_path": "bazel-out/test/bin/src/samples/greeter/backend/backend",
                    "app_executable_runfiles_path": "_main/src/samples/greeter/backend/backend",
                    "app_runfiles_path": "bazel-out/test/bin/src/samples/greeter/backend/backend.runfiles",
                    "app_repo_mapping_path": "bazel-out/test/bin/src/samples/greeter/backend/backend.repo_mapping",
                    "app_runfiles_manifest_path": "bazel-out/test/bin/src/samples/greeter/backend/backend.runfiles_manifest",
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

    def test_grpc_server_dry_run_uses_active_runfiles_tree(self) -> None:
        backend_dir = (
            self.workspace_root
            / "bazel-out"
            / "test"
            / "bin"
            / "src"
            / "samples"
            / "greeter"
            / "backend"
        )
        backend_dir.mkdir(parents=True)
        (backend_dir / "backend").write_text("#!/usr/bin/env bash\n", encoding="utf-8")

        runfiles_root = self.workspace_root / "deploy.runfiles"
        runfiles_backend = (
            runfiles_root
            / "_main"
            / "src"
            / "samples"
            / "greeter"
            / "backend"
            / "backend"
        )
        runfiles_backend.parent.mkdir(parents=True, exist_ok=True)
        runfiles_backend.write_text("#!/usr/bin/env bash\n", encoding="utf-8")
        (runfiles_root / "_repo_mapping").write_text("", encoding="utf-8")
        (runfiles_root / "MANIFEST").write_text(
            "_main/src/samples/greeter/backend/backend " + str(runfiles_backend) + "\n",
            encoding="utf-8",
        )

        plan = self._dry_run(
            self._write_manifest(
                "backend_runfiles_manifest",
                {
                    "deploy_kind": "grpc_server",
                    "service": "greeter-backend-dev",
                    "app_executable_path": "bazel-out/test/bin/src/samples/greeter/backend/backend",
                    "app_executable_runfiles_path": "_main/src/samples/greeter/backend/backend",
                    "app_runfiles_path": "bazel-out/test/bin/src/samples/greeter/backend/backend.runfiles",
                    "app_repo_mapping_path": "bazel-out/test/bin/src/samples/greeter/backend/backend.repo_mapping",
                    "app_runfiles_manifest_path": "bazel-out/test/bin/src/samples/greeter/backend/backend.runfiles_manifest",
                },
            ),
            environment={"RUNFILES_DIR": str(runfiles_root)},
        )

        self.assertEqual(
            plan["inputs"]["app_executable"],
            str(runfiles_backend.resolve()),
        )
        self.assertEqual(
            plan["inputs"]["app_runfiles"],
            str(runfiles_root.resolve()),
        )
        self.assertEqual(
            plan["inputs"]["app_repo_mapping"],
            str((runfiles_root / "_repo_mapping").resolve()),
        )
        self.assertEqual(
            plan["inputs"]["app_runfiles_manifest"],
            str((runfiles_root / "MANIFEST").resolve()),
        )

    def test_web_app_dry_run_with_backend(self) -> None:
        dist_dir = (
            self.workspace_root
            / "bazel-out"
            / "test"
            / "bin"
            / "src"
            / "samples"
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
                    "app_dist_path": "bazel-out/test/bin/src/samples/greeter/web/dist",
                    "app_dist_runfiles_path": "_main/src/samples/greeter/web/dist",
                    "backend_manifest_path": str(
                        backend_manifest.relative_to(self.workspace_root)
                    ),
                    "backend_manifest_runfiles_path": "_main/backend_manifest.json",
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
        plan = self._dry_run(
            self._write_manifest(
                "android_manifest",
                {
                    "deploy_kind": "android_app",
                    "app_label": "//src/samples/greeter/android:app",
                    "backend_endpoint_configs": [
                        {
                            "deploy_service_url_flag": "//src/samples/greeter/backend:backend_config_deploy_service_url",
                            "service": "greeter-backend-dev",
                        },
                    ],
                    "firebase_app_id": "1:1234567890:android:deadbeef",
                    "tester_groups": [],
                },
            ),
            environment={
                "GITHUB_RUN_NUMBER": "123",
                "GITHUB_RUN_ATTEMPT": "4",
                "GITHUB_SHA": "abcdef1234567890abcdef1234567890abcdef12",
            },
        )

        self.assertEqual(plan["deploy_kind"], "android_app")
        self.assertEqual(plan["services"], ["greeter-backend-dev"])
        self.assertEqual(
            plan["inputs"]["app_label"],
            "//src/samples/greeter/android:app",
        )
        self.assertEqual(
            plan["backend_endpoint_configs"],
            [
                {
                    "deploy_service_url_flag": "//src/samples/greeter/backend:backend_config_deploy_service_url",
                    "service": "greeter-backend-dev",
                    "service_url": runner_lib.CLOUD_RUN_URL_PLACEHOLDER,
                },
            ],
        )
        self.assertEqual(
            plan["android_version"],
            {
                "version_code": "12304",
                "version_name": "abcdef123456",
            },
        )
        self.assertEqual(plan["tester_groups"], ["android-dev-testers"])
        self.assertEqual(len(plan["service_url_commands"]), 1)
        self.assertEqual(
            plan["service_url_commands"][0],
            {
                "command": [
                    "gcloud",
                    "run",
                    "services",
                    "describe",
                    "greeter-backend-dev",
                    "--project",
                    "victor-dev-project",
                    "--region",
                    "europe-west1",
                    "--platform",
                    "managed",
                    "--format=value(status.url)",
                ],
                "placeholder": runner_lib.CLOUD_RUN_URL_PLACEHOLDER,
                "service": "greeter-backend-dev",
            },
        )
        self.assertEqual(plan["commands"][0][0:2], ["bazel", "build"])
        self.assertEqual(plan["commands"][0][2:4], ["-c", "opt"])
        self.assertIn(
            "--//build/rules/backend:backend_service_url_profile=deploy",
            plan["commands"][0],
        )
        self.assertIn(
            "--//src/samples/greeter/backend:backend_config_deploy_service_url=$CLOUD_RUN_URL",
            plan["commands"][0],
        )
        self.assertNotIn(
            "--//build/rules/backend:backend_deploy_service_url=$CLOUD_RUN_URL",
            plan["commands"][0],
        )
        self.assertIn("ANDROID_VERSION_CODE=12304", plan["commands"][0])
        self.assertIn("ANDROID_VERSION_NAME=abcdef123456", plan["commands"][0])
        self.assertEqual(
            plan["commands"][0][-1],
            "//src/samples/greeter/android:app",
        )
        self.assertEqual(plan["commands"][1][0:2], ["bazel", "cquery"])
        self.assertEqual(plan["commands"][1][2:4], ["-c", "opt"])
        self.assertIn("ANDROID_VERSION_CODE=12304", plan["commands"][1])
        self.assertIn("ANDROID_VERSION_NAME=abcdef123456", plan["commands"][1])
        self.assertIn("--output=files", plan["commands"][1])
        command = plan["commands"][2]
        self.assertEqual(command[0], "firebase")
        self.assertIn(runner_lib.APK_PATH_PLACEHOLDER, command)
        self.assertIn("--groups", command)
        self.assertIn("1:1234567890:android:deadbeef", command)

    def test_android_app_dry_run_uses_ci_bazel_wrapper_when_buildbuddy_is_available(
        self,
    ) -> None:
        wrapper = self.workspace_root / ".github" / "scripts" / "run-bazel-ci.sh"
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        wrapper.write_text("#!/usr/bin/env bash\n", encoding="utf-8")

        plan = self._dry_run(
            self._write_manifest(
                "android_ci_manifest",
                {
                    "deploy_kind": "android_app",
                    "app_label": "//src/samples/greeter/android:app",
                    "backend_endpoint_configs": [],
                    "firebase_app_id": "1:1234567890:android:deadbeef",
                    "tester_groups": [],
                },
            ),
            environment={
                "BUILDBUDDY_API_KEY": "secret-key",
                "GITHUB_EVENT_NAME": "push",
                "GITHUB_REF": "refs/heads/main",
            },
        )

        plan_json = json.dumps(plan)
        self.assertNotIn("secret-key", plan_json)

        build_command = plan["commands"][0]
        self.assertEqual(
            build_command[0:3],
            ["./.github/scripts/run-bazel-ci.sh", "build", "--config=ci"],
        )

        cquery_command = plan["commands"][1]
        self.assertEqual(
            cquery_command[0:3],
            ["./.github/scripts/run-bazel-ci.sh", "cquery", "--config=ci"],
        )

    def test_android_app_dry_run_supports_multiple_backend_endpoint_configs(
        self,
    ) -> None:
        plan = self._dry_run(
            self._write_manifest(
                "android_multi_backend_manifest",
                {
                    "deploy_kind": "android_app",
                    "app_label": "//src/samples/multi/android:app",
                    "backend_endpoint_configs": [
                        {
                            "deploy_service_url_flag": "//src/backends/greeter:config_deploy_service_url",
                            "service": "greeter-backend-dev",
                        },
                        {
                            "deploy_service_url_flag": "//src/backends/auth:config_deploy_service_url",
                            "service": "auth-backend-dev",
                        },
                        {
                            "deploy_service_url_flag": "//src/backends/greeter:admin_config_deploy_service_url",
                            "service": "greeter-backend-dev",
                        },
                    ],
                    "firebase_app_id": "1:1234567890:android:deadbeef",
                    "tester_groups": ["qa"],
                },
            ),
        )

        self.assertEqual(plan["services"], ["auth-backend-dev", "greeter-backend-dev"])
        self.assertEqual(len(plan["service_url_commands"]), 2)
        self.assertEqual(plan["service_url_commands"][0]["service"], "auth-backend-dev")
        self.assertEqual(
            plan["service_url_commands"][0]["placeholder"],
            runner_lib.CLOUD_RUN_URL_PLACEHOLDER,
        )
        self.assertEqual(
            plan["service_url_commands"][1]["placeholder"],
            "$CLOUD_RUN_URL_1",
        )
        build_command = plan["commands"][0]
        self.assertIn(
            "--//src/backends/auth:config_deploy_service_url=$CLOUD_RUN_URL",
            build_command,
        )
        self.assertIn(
            "--//src/backends/greeter:admin_config_deploy_service_url=$CLOUD_RUN_URL_1",
            build_command,
        )
        self.assertIn(
            "--//src/backends/greeter:config_deploy_service_url=$CLOUD_RUN_URL_1",
            build_command,
        )

    def test_select_signed_apk_path_ignores_unsigned_outputs(self) -> None:
        cquery_output = "\n".join(
            [
                "bazel-out/test/bin/src/samples/greeter/android/app_unsigned.apk",
                "bazel-out/test/bin/src/samples/greeter/android/app.apk",
                "bazel-out/test/bin/src/samples/greeter/android/app.deploy.jar",
            ],
        )

        self.assertEqual(
            runner_lib._select_signed_apk_path(cquery_output),
            "bazel-out/test/bin/src/samples/greeter/android/app.apk",
        )

    def test_select_signed_apk_path_rejects_ambiguous_outputs(self) -> None:
        cquery_output = "\n".join(
            [
                "bazel-out/test/bin/src/samples/greeter/android/app.apk",
                "bazel-out/test/bin/src/samples/greeter/android/other.apk",
            ],
        )

        with self.assertRaisesRegex(RuntimeError, "expected exactly one signed APK"):
            runner_lib._select_signed_apk_path(cquery_output)


if __name__ == "__main__":
    unittest.main()
