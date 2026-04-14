#!/usr/bin/env python3
"""Tests for GitHub Actions output emission."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from tools.deploy import emit_github_actions_outputs


class EmitGithubActionsOutputsTest(unittest.TestCase):
    def test_emits_expected_keys(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config_path = root / "tools" / "deploy" / "dev_environment.json"
            config_path.parent.mkdir(parents=True)
            config_path.write_text(
                json.dumps(
                    {
                        "gcp": {
                            "project_id": "victor-dev-493319",
                            "region": "europe-west1",
                            "artifact_registry_repository": "victor-dev",
                        },
                        "firebase": {
                            "project_id": "victor-dev-493319",
                            "default_tester_groups": ["android-dev-testers"],
                        },
                        "github_actions": {
                            "workload_identity_provider": "projects/617611994239/locations/global/workloadIdentityPools/github/providers/victor",
                            "service_account": "victor-deployer@victor-dev-493319.iam.gserviceaccount.com",
                        },
                    },
                )
                + "\n",
                encoding="utf-8",
            )
            github_output = root / "github_output.txt"
            env_key = "BUILD_WORKSPACE_DIRECTORY"
            previous_workspace = os.environ.get(env_key)
            try:
                os.environ[env_key] = str(root)
                rc = emit_github_actions_outputs.main(
                    [
                        "--config",
                        "tools/deploy/dev_environment.json",
                        "--github-output",
                        str(github_output),
                    ],
                )
            finally:
                if previous_workspace is None:
                    os.environ.pop(env_key, None)
                else:
                    os.environ[env_key] = previous_workspace

            self.assertEqual(rc, 0)
            self.assertEqual(
                github_output.read_text(encoding="utf-8").splitlines(),
                [
                    "gcp_project_id=victor-dev-493319",
                    "gcp_region=europe-west1",
                    "workload_identity_provider=projects/617611994239/locations/global/workloadIdentityPools/github/providers/victor",
                    "service_account=victor-deployer@victor-dev-493319.iam.gserviceaccount.com",
                ],
            )


if __name__ == "__main__":
    unittest.main()
