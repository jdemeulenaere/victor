#!/usr/bin/env python3
"""CLI entrypoint for Bazel-backed deploy targets."""

from __future__ import annotations

from build.deploy.runner_lib import main


if __name__ == "__main__":
    raise SystemExit(main())
