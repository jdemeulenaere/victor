#!/usr/bin/env python3
"""Lists deploy targets tagged for main-branch deployment."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

_DEPLOY_KINDS = ("grpc_server", "web_app", "android_app")


def _query_expression(kind: str) -> str:
    return (
        f'attr("tags", "deploy_on_main", //...) '
        f'intersect attr("tags", "deploy_kind={kind}", //...)'
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=_DEPLOY_KINDS, required=True)
    args = parser.parse_args(argv)

    repo_root = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        ["bazel", "query", _query_expression(args.kind), "--output=label"],
        check=False,
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        return result.returncode

    labels = sorted(line.strip() for line in result.stdout.splitlines() if line.strip())
    if labels:
        sys.stdout.write("\n".join(labels) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
