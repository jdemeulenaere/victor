#!/usr/bin/env python3
"""Emits selected deploy config values into GitHub Actions outputs."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def _workspace_root() -> Path:
    build_workspace_directory = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if build_workspace_directory:
        return Path(build_workspace_directory).resolve()
    return Path.cwd().resolve()


def _resolve_path(path: str) -> Path:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate
    return (_workspace_root() / candidate).resolve()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="tools/deploy/dev_environment.json")
    parser.add_argument("--github-output")
    args = parser.parse_args(argv)

    output_path_value = args.github_output or os.environ.get("GITHUB_OUTPUT")
    if not output_path_value:
        raise SystemExit("GITHUB_OUTPUT is required via --github-output or environment")

    config = json.loads(_resolve_path(args.config).read_text(encoding="utf-8"))
    output_path = Path(output_path_value)
    with output_path.open("a", encoding="utf-8") as handle:
        print(f"gcp_project_id={config['gcp']['project_id']}", file=handle)
        print(f"gcp_region={config['gcp']['region']}", file=handle)
        print(
            f"workload_identity_provider={config['github_actions']['workload_identity_provider']}",
            file=handle,
        )
        print(
            f"service_account={config['github_actions']['service_account']}",
            file=handle,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
