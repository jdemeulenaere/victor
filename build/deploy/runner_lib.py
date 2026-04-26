#!/usr/bin/env python3
"""Deployment planning and execution helpers."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

CLOUD_RUN_URL_PLACEHOLDER = "$CLOUD_RUN_URL"
APK_PATH_PLACEHOLDER = "$APK_PATH"
_ANDROID_SERVICE_URL_PROFILE_FLAG = (
    "--//build/tools/android:android_service_url_profile=deploy"
)
_ANDROID_DEPLOY_SERVICE_URL_FLAG = (
    "--//build/tools/android:android_deploy_service_url={service_url}"
)
_ANDROID_DEPLOY_BAZEL_FLAGS = ("-c", "opt")
_ANDROID_VERSION_CODE_DEFINE = "ANDROID_VERSION_CODE"
_ANDROID_VERSION_NAME_DEFINE = "ANDROID_VERSION_NAME"


def _workspace_root(explicit_workspace_root: str | None = None) -> Path:
    if explicit_workspace_root:
        return Path(explicit_workspace_root).resolve()
    build_workspace_directory = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if build_workspace_directory:
        return Path(build_workspace_directory).resolve()
    return Path.cwd().resolve()


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _resolve_artifact_path(
    workspace_root: Path, artifact_path: str | None
) -> Path | None:
    if artifact_path is None:
        return None
    path = Path(artifact_path)
    if path.is_absolute():
        return path
    return (workspace_root / path).resolve()


def _deploy_runfiles_root(manifest_path: Path) -> Path | None:
    manifest_name = manifest_path.name
    if not manifest_name.endswith("__manifest.json"):
        return None
    candidate = manifest_path.with_name(
        f"{manifest_name.removesuffix('__manifest.json')}.runfiles"
    )
    if candidate.exists():
        return candidate.resolve()
    return None


def _runfiles_root(environment: dict[str, str]) -> Path | None:
    for key in ("RUNFILES_DIR", "JAVA_RUNFILES"):
        candidate = environment.get(key)
        if candidate:
            path = Path(candidate)
            if path.exists():
                return path.resolve()
    manifest_file = environment.get("RUNFILES_MANIFEST_FILE")
    if manifest_file:
        candidate = Path(manifest_file).resolve().parent
        if candidate.exists():
            return candidate
    return None


def _manifest_rlocation(
    environment: dict[str, str], runfiles_logical_path: str
) -> Path | None:
    manifest_file = environment.get("RUNFILES_MANIFEST_FILE")
    if not manifest_file:
        root = _runfiles_root(environment)
        if root is None:
            return None
        manifest_candidate = root / "MANIFEST"
        if not manifest_candidate.exists():
            return None
        manifest_file = str(manifest_candidate)
    with open(manifest_file, encoding="utf-8") as f:
        for line in f:
            logical_path, _, real_path = line.rstrip("\n").partition(" ")
            if logical_path == runfiles_logical_path and real_path:
                return Path(real_path).resolve()
    return None


def _resolve_runfiles_path(
    environment: dict[str, str],
    runfiles_logical_path: str | None,
    *,
    runfiles_root: Path | None = None,
) -> Path | None:
    if not runfiles_logical_path:
        return None
    root = runfiles_root or _runfiles_root(environment)
    if root is not None:
        candidate = (root / runfiles_logical_path).resolve()
        if candidate.exists():
            return candidate
    return _manifest_rlocation(environment, runfiles_logical_path)


def _resolve_runtime_path(
    workspace_root: Path,
    environment: dict[str, str],
    *,
    artifact_path: str | None,
    runfiles_logical_path: str | None = None,
    runfiles_root: Path | None = None,
) -> Path | None:
    runfiles_path = _resolve_runfiles_path(
        environment,
        runfiles_logical_path,
        runfiles_root=runfiles_root,
    )
    if runfiles_path is not None:
        return runfiles_path
    return _resolve_artifact_path(workspace_root, artifact_path)


def _command_display(command: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in command)


def _run_command(command: list[str], *, cwd: Path | None = None) -> None:
    print(f"[deploy] {_command_display(command)}", file=sys.stderr)
    subprocess.run(command, cwd=str(cwd) if cwd else None, check=True)


def _run_command_output(command: list[str], *, cwd: Path | None = None) -> str:
    print(f"[deploy] {_command_display(command)}", file=sys.stderr)
    result = subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        message = f"Command failed ({result.returncode}): {_command_display(command)}"
        if detail:
            message = f"{message}\n{detail}"
        raise RuntimeError(message)
    return result.stdout.strip()


def _git_output(workspace_root: Path, *args: str) -> str | None:
    result = subprocess.run(
        ["git", *args],
        cwd=workspace_root,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def _release_revision(environment: dict[str, str], workspace_root: Path) -> str:
    github_sha = environment.get("GITHUB_SHA")
    if github_sha:
        return github_sha[:12].lower()
    git_sha = _git_output(workspace_root, "rev-parse", "--short=12", "HEAD")
    if git_sha:
        return git_sha.lower()
    return datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")


def _release_notes(environment: dict[str, str], workspace_root: Path) -> str:
    github_sha = environment.get("GITHUB_SHA")
    if github_sha:
        subject = environment.get("GITHUB_EVENT_HEAD_COMMIT_MESSAGE", "")
        header = f"GitHub commit: {github_sha}"
        return header if not subject else f"{header}\n{subject}"

    commit = _git_output(workspace_root, "log", "-1", "--format=%H%n%s%n%b")
    if commit:
        return commit

    return f"Manual deploy at {datetime.now(timezone.utc).isoformat()}"


def _android_version_code(environment: dict[str, str]) -> str:
    run_number = environment.get("GITHUB_RUN_NUMBER")
    if not run_number:
        return "1"
    run_attempt = environment.get("GITHUB_RUN_ATTEMPT", "1")
    try:
        return str(int(run_number) * 100 + int(run_attempt))
    except ValueError as exc:
        raise RuntimeError(
            "GITHUB_RUN_NUMBER and GITHUB_RUN_ATTEMPT must be integers "
            "for Android deploy versioning"
        ) from exc


def _android_version(
    environment: dict[str, str], workspace_root: Path
) -> dict[str, str]:
    return {
        "version_code": _android_version_code(environment),
        "version_name": _release_revision(environment, workspace_root),
    }


def _require_tools(tools: list[str]) -> None:
    missing = [tool for tool in tools if shutil.which(tool) is None]
    if missing:
        raise RuntimeError(
            "Missing required deploy tools on PATH: {}".format(
                ", ".join(sorted(missing)),
            ),
        )


def _copy_tree(source: Path, destination: Path) -> None:
    shutil.copytree(source, destination, symlinks=False)


def _build_backend_image_uri(
    config: dict[str, Any], service: str, revision: str
) -> str:
    region = config["gcp"]["region"]
    project_id = config["gcp"]["project_id"]
    repository = config["gcp"]["artifact_registry_repository"]
    registry_host = f"{region}-docker.pkg.dev"
    return f"{registry_host}/{project_id}/{repository}/{service}:{revision}"


def _android_deploy_service_url_flags(service_url: str) -> list[str]:
    return [
        _ANDROID_SERVICE_URL_PROFILE_FLAG,
        _ANDROID_DEPLOY_SERVICE_URL_FLAG.format(service_url=service_url),
    ]


def _android_version_define_flags(android_version: dict[str, str]) -> list[str]:
    return [
        "--define",
        f"{_ANDROID_VERSION_CODE_DEFINE}={android_version['version_code']}",
        "--define",
        f"{_ANDROID_VERSION_NAME_DEFINE}={android_version['version_name']}",
    ]


def _cloud_run_url_command(service: str, config: dict[str, Any]) -> list[str]:
    return [
        "gcloud",
        "run",
        "services",
        "describe",
        service,
        "--project",
        config["gcp"]["project_id"],
        "--region",
        config["gcp"]["region"],
        "--platform",
        "managed",
        "--format=value(status.url)",
    ]


def _bazel_android_build_command(
    app_label: str, service_url: str, android_version: dict[str, str]
) -> list[str]:
    return [
        "bazel",
        "build",
        *_ANDROID_DEPLOY_BAZEL_FLAGS,
        *_android_deploy_service_url_flags(service_url),
        *_android_version_define_flags(android_version),
        app_label,
    ]


def _bazel_android_cquery_command(
    app_label: str, service_url: str, android_version: dict[str, str]
) -> list[str]:
    return [
        "bazel",
        "cquery",
        *_ANDROID_DEPLOY_BAZEL_FLAGS,
        *_android_deploy_service_url_flags(service_url),
        *_android_version_define_flags(android_version),
        "--output=files",
        app_label,
    ]


def _select_signed_apk_path(cquery_output: str) -> str:
    output_paths = [line.strip() for line in cquery_output.splitlines() if line.strip()]
    apk_paths = [
        path
        for path in output_paths
        if path.endswith(".apk") and not path.endswith("_unsigned.apk")
    ]
    if len(apk_paths) != 1:
        raise RuntimeError(
            "expected exactly one signed APK output, found {}: {}".format(
                len(apk_paths),
                apk_paths,
            ),
        )
    return apk_paths[0]


def _replace_command_placeholders(
    command: list[str], replacements: dict[str, str]
) -> list[str]:
    materialized = []
    for part in command:
        for placeholder, value in replacements.items():
            part = part.replace(placeholder, value)
        materialized.append(part)
    return materialized


def _grpc_dockerfile(entrypoint_name: str) -> str:
    return "\n".join(
        [
            "FROM eclipse-temurin:21-jre",
            "WORKDIR /app",
            f"COPY {entrypoint_name} /app/{entrypoint_name}",
            f"COPY {entrypoint_name}.runfiles /app/{entrypoint_name}.runfiles",
            f"COPY {entrypoint_name}.repo_mapping /app/{entrypoint_name}.repo_mapping",
            f"COPY {entrypoint_name}.runfiles_manifest /app/{entrypoint_name}.runfiles_manifest",
            "ENV PORT=8080",
            "EXPOSE 8080",
            f'ENTRYPOINT ["/app/{entrypoint_name}"]',
            "",
        ],
    )


def _plan_grpc_server(
    manifest: dict[str, Any],
    config: dict[str, Any],
    workspace_root: Path,
    environment: dict[str, str],
    deploy_runfiles_root: Path | None,
) -> dict[str, Any]:
    revision = _release_revision(environment, workspace_root)
    image_uri = _build_backend_image_uri(config, manifest["service"], revision)
    executable_path = _resolve_runtime_path(
        workspace_root,
        environment,
        artifact_path=manifest["app_executable_path"],
        runfiles_logical_path=manifest.get("app_executable_runfiles_path"),
        runfiles_root=deploy_runfiles_root,
    )
    assert executable_path is not None
    runfiles_root = deploy_runfiles_root or _runfiles_root(environment)
    runtime_runfiles_path = _resolve_artifact_path(
        workspace_root, manifest["app_runfiles_path"]
    )
    runtime_repo_mapping_path = _resolve_artifact_path(
        workspace_root, manifest["app_repo_mapping_path"]
    )
    runtime_runfiles_manifest_path = _resolve_artifact_path(
        workspace_root, manifest["app_runfiles_manifest_path"]
    )
    if (
        runfiles_root is not None
        and _resolve_runfiles_path(
            environment,
            manifest.get("app_executable_runfiles_path"),
            runfiles_root=runfiles_root,
        )
        is not None
    ):
        runtime_runfiles_path = runfiles_root
        runtime_repo_mapping_path = (runfiles_root / "_repo_mapping").resolve()
        runtime_runfiles_manifest_path = (runfiles_root / "MANIFEST").resolve()
    commands = [
        [
            "gcloud",
            "auth",
            "configure-docker",
            f"{config['gcp']['region']}-docker.pkg.dev",
            "--quiet",
        ],
        ["docker", "build", "--tag", image_uri, "$WORKDIR"],
        ["docker", "push", image_uri],
        [
            "gcloud",
            "run",
            "deploy",
            manifest["service"],
            "--image",
            image_uri,
            "--project",
            config["gcp"]["project_id"],
            "--region",
            config["gcp"]["region"],
            "--platform",
            "managed",
            "--allow-unauthenticated",
            "--use-http2",
            "--quiet",
        ],
    ]
    return {
        "deploy_kind": "grpc_server",
        "service": manifest["service"],
        "image_uri": image_uri,
        "revision": revision,
        "inputs": {
            "app_executable": str(executable_path),
            "app_repo_mapping": str(runtime_repo_mapping_path),
            "app_runfiles": str(runtime_runfiles_path),
            "app_runfiles_manifest": str(runtime_runfiles_manifest_path),
        },
        "dockerfile": _grpc_dockerfile(executable_path.name),
        "commands": commands,
    }


def _plan_web_app(
    manifest: dict[str, Any],
    config: dict[str, Any],
    workspace_root: Path,
    environment: dict[str, str],
    deploy_runfiles_root: Path | None,
) -> dict[str, Any]:
    public_source_dir = _resolve_runtime_path(
        workspace_root,
        environment,
        artifact_path=manifest["app_dist_path"],
        runfiles_logical_path=manifest.get("app_dist_runfiles_path"),
        runfiles_root=deploy_runfiles_root,
    )
    assert public_source_dir is not None
    firebase_config: dict[str, Any] = {
        "hosting": {
            "site": manifest["site"],
            "public": "public",
            "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
        },
    }
    backend_manifest_path = manifest.get("backend_manifest_path")
    if backend_manifest_path:
        backend_manifest = _load_json(
            _resolve_runtime_path(
                workspace_root,
                environment,
                artifact_path=backend_manifest_path,
                runfiles_logical_path=manifest.get("backend_manifest_runfiles_path"),
                runfiles_root=deploy_runfiles_root,
            )
        )
        if backend_manifest.get("deploy_kind") != "grpc_server":
            raise RuntimeError(
                f"Expected backend deploy manifest to be grpc_server, got {backend_manifest.get('deploy_kind')}",
            )
        firebase_config["hosting"]["rewrites"] = [
            {
                "source": "/grpc/**",
                "run": {
                    "serviceId": backend_manifest["service"],
                    "region": config["gcp"]["region"],
                    "pinTag": True,
                },
            },
        ]
    firebase_rc = {"projects": {"default": config["firebase"]["project_id"]}}
    commands = [
        [
            "firebase",
            "deploy",
            "--project",
            config["firebase"]["project_id"],
            "--only",
            "hosting",
            "--config",
            "$WORKDIR/firebase.json",
            "--non-interactive",
        ],
    ]
    return {
        "deploy_kind": "web_app",
        "site": manifest["site"],
        "inputs": {
            "public_source_dir": str(public_source_dir),
        },
        "firebase_json": firebase_config,
        "firebaserc": firebase_rc,
        "commands": commands,
    }


def _plan_android_app(
    manifest: dict[str, Any],
    config: dict[str, Any],
    workspace_root: Path,
    environment: dict[str, str],
    deploy_runfiles_root: Path | None,
) -> dict[str, Any]:
    _ = deploy_runfiles_root
    tester_groups = manifest.get("tester_groups") or config["firebase"].get(
        "default_tester_groups", []
    )
    release_notes = _release_notes(environment, workspace_root)
    android_version = _android_version(environment, workspace_root)
    app_label = manifest["app_label"]
    commands = [
        _cloud_run_url_command(manifest["service"], config),
        _bazel_android_build_command(
            app_label,
            CLOUD_RUN_URL_PLACEHOLDER,
            android_version,
        ),
        _bazel_android_cquery_command(
            app_label,
            CLOUD_RUN_URL_PLACEHOLDER,
            android_version,
        ),
        [
            "firebase",
            "appdistribution:distribute",
            APK_PATH_PLACEHOLDER,
            "--app",
            manifest["firebase_app_id"],
            "--project",
            config["firebase"]["project_id"],
            "--release-notes",
            release_notes,
        ],
    ]
    if tester_groups:
        commands[-1].extend(["--groups", ",".join(tester_groups)])
    return {
        "deploy_kind": "android_app",
        "service": manifest["service"],
        "firebase_app_id": manifest["firebase_app_id"],
        "inputs": {
            "app_label": app_label,
            "workspace_root": str(workspace_root),
        },
        "service_url": CLOUD_RUN_URL_PLACEHOLDER,
        "android_version": android_version,
        "tester_groups": tester_groups,
        "release_notes": release_notes,
        "commands": commands,
    }


def build_plan(
    manifest_path: Path,
    config_path: Path,
    *,
    workspace_root: str | None = None,
    environment: dict[str, str] | None = None,
) -> dict[str, Any]:
    manifest = _load_json(manifest_path)
    config = _load_json(config_path)
    env = dict(os.environ if environment is None else environment)
    resolved_workspace_root = _workspace_root(workspace_root)
    resolved_manifest_path = manifest_path.resolve()
    deploy_runfiles_root = _deploy_runfiles_root(resolved_manifest_path)

    kind = manifest["deploy_kind"]
    if kind == "grpc_server":
        return _plan_grpc_server(
            manifest,
            config,
            resolved_workspace_root,
            env,
            deploy_runfiles_root,
        )
    if kind == "web_app":
        return _plan_web_app(
            manifest,
            config,
            resolved_workspace_root,
            env,
            deploy_runfiles_root,
        )
    if kind == "android_app":
        return _plan_android_app(
            manifest,
            config,
            resolved_workspace_root,
            env,
            deploy_runfiles_root,
        )
    raise RuntimeError(f"Unsupported deploy kind: {kind}")


def _execute_grpc_server(plan: dict[str, Any]) -> None:
    _require_tools(["docker", "gcloud"])
    executable_path = Path(plan["inputs"]["app_executable"])
    runfiles_path = Path(plan["inputs"]["app_runfiles"])
    repo_mapping_path = Path(plan["inputs"]["app_repo_mapping"])
    runfiles_manifest_path = Path(plan["inputs"]["app_runfiles_manifest"])

    with tempfile.TemporaryDirectory(
        prefix=f"victor-deploy-{plan['service']}-"
    ) as temp_dir:
        workdir = Path(temp_dir)
        staged_executable = workdir / executable_path.name
        shutil.copy2(executable_path, staged_executable)
        _copy_tree(runfiles_path, workdir / f"{executable_path.name}.runfiles")
        shutil.copy2(
            repo_mapping_path, workdir / f"{executable_path.name}.repo_mapping"
        )
        shutil.copy2(
            runfiles_manifest_path,
            workdir / f"{executable_path.name}.runfiles_manifest",
        )
        (workdir / "Dockerfile").write_text(plan["dockerfile"], encoding="utf-8")

        for command in plan["commands"]:
            materialized_command = [
                temp_dir if part == "$WORKDIR" else part for part in command
            ]
            _run_command(materialized_command)


def _execute_web_app(plan: dict[str, Any]) -> None:
    _require_tools(["firebase"])
    public_source_dir = Path(plan["inputs"]["public_source_dir"])

    with tempfile.TemporaryDirectory(prefix=f"victor-web-{plan['site']}-") as temp_dir:
        workdir = Path(temp_dir)
        _copy_tree(public_source_dir, workdir / "public")
        (workdir / "firebase.json").write_text(
            json.dumps(plan["firebase_json"], indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (workdir / ".firebaserc").write_text(
            json.dumps(plan["firebaserc"], indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        for command in plan["commands"]:
            materialized_command = [
                part.replace("$WORKDIR", temp_dir) for part in command
            ]
            _run_command(materialized_command, cwd=workdir)


def _execute_android_app(plan: dict[str, Any]) -> None:
    _require_tools(["bazel", "firebase", "gcloud"])
    workspace_root = Path(plan["inputs"]["workspace_root"])

    service_url = _run_command_output(plan["commands"][0], cwd=workspace_root)
    if not service_url:
        raise RuntimeError(
            "Cloud Run service {} did not report status.url".format(plan["service"]),
        )

    replacements = {CLOUD_RUN_URL_PLACEHOLDER: service_url}
    _run_command(
        _replace_command_placeholders(plan["commands"][1], replacements),
        cwd=workspace_root,
    )
    cquery_output = _run_command_output(
        _replace_command_placeholders(plan["commands"][2], replacements),
        cwd=workspace_root,
    )
    apk_output_path = _select_signed_apk_path(cquery_output)
    apk_path = _resolve_artifact_path(workspace_root, apk_output_path)
    if apk_path is None or not apk_path.exists():
        raise RuntimeError(
            "signed APK output does not exist: {}".format(apk_output_path)
        )

    replacements[APK_PATH_PLACEHOLDER] = str(apk_path)
    _run_command(
        _replace_command_placeholders(plan["commands"][3], replacements),
        cwd=workspace_root,
    )


def execute_plan(plan: dict[str, Any]) -> None:
    kind = plan["deploy_kind"]
    if kind == "grpc_server":
        _execute_grpc_server(plan)
        return
    if kind == "web_app":
        _execute_web_app(plan)
        return
    if kind == "android_app":
        _execute_android_app(plan)
        return
    raise RuntimeError(f"Unsupported deploy kind: {kind}")


def main(
    argv: list[str] | None = None, *, environment: dict[str, str] | None = None
) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--workspace-root")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    try:
        plan = build_plan(
            Path(args.manifest),
            Path(args.config),
            workspace_root=args.workspace_root,
            environment=environment,
        )
        if args.dry_run:
            json.dump(plan, sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
            return 0
        execute_plan(plan)
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"deploy failed: {exc}", file=sys.stderr)
        return 1
