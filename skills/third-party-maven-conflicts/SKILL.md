---
name: third-party-maven-conflicts
description: Add, update, and troubleshoot third-party Maven dependencies in Bazel monorepos that use rules_jvm_external with libs.versions.toml. Use when editing third_party/maven files, migrating labels to @third_party_maven, repinning dependencies, or resolving Coursier "Conflicting dependencies" errors.
---

# Third-Party Maven Conflicts

## Overview

Handle dependency lifecycle for `third_party/maven` from declaration to pin to validation, using a repeatable conflict-resolution loop.

## Workflow

1. Inspect current dependency wiring.
- Read `third_party/maven/libs.versions.toml`, `third_party/maven/maven.MODULE.bazel`, and affected `BUILD.bazel` files.
- Prefer `@third_party_maven` for repo-owned dependencies.
- Keep `@maven` only where intentionally separated (for example shared transitive graphs such as grpc/protobuf).

2. Add or update dependencies in TOML.
- Add version keys under `[versions]`.
- Add artifact aliases under `[libraries]`.
- Keep entries sorted between keep-sorted markers.
- Reuse `version.ref` keys so related artifacts stay aligned.

3. Wire Bazel targets.
- Replace direct `@maven//:...` labels with `@third_party_maven//:...` where appropriate.
- For OS-specific runtime artifacts, depend on one shared selector target instead of listing every platform artifact in each consumer target.

4. Repin.
```bash
REPIN=1 bazel run @third_party_maven//:pin
```
- If this fails, continue with the conflict loop below.

5. Validate.
```bash
./build.sh
./test.sh
```
- Treat successful pin + build + tests as done criteria.

## Conflict Loop

1. Capture conflict coordinates.
```bash
REPIN=1 bazel run @third_party_maven//:pin > /tmp/pin.log 2>&1
rg -n '^[a-zA-Z0-9_.-]+:[a-zA-Z0-9_.-]+:[^ ]+.* wanted by$' /tmp/pin.log | sed -E 's/^[0-9]+://'
```

2. Decide version policy per coordinate.
- Align to the dominant ecosystem already pinned in the repo (AndroidX, Compose Desktop, Kotlin).
- If asked to use latest, look up Maven metadata before pinning:
```bash
# Maven Central
curl -s https://repo1.maven.org/maven2/<group path>/<artifact>/maven-metadata.xml

# Google Maven (AndroidX)
curl -s https://dl.google.com/dl/android/maven2/<group path>/<artifact>/maven-metadata.xml
```
- Prefer stable versions unless the repo already tracks alpha, beta, or rc lines.

3. Pin explicit conflict breakers in TOML.
- Add the conflicting artifact under `[libraries]` with a dedicated version key when needed.
- Repin and iterate until the conflict set is empty.

4. Re-validate.
- Run `./build.sh` and `./test.sh` after the final pin.

## Guardrails

- Do not edit generated lockfiles manually; regenerate with `:pin`.
- Do not mix unrelated large upgrades while fixing one conflict set.
- Keep fixes minimal and reversible.
- Record why non-obvious explicit pins were added.

## Done Checklist

- `libs.versions.toml` updated and sorted.
- Consumers use `@third_party_maven` where intended.
- `REPIN=1 bazel run @third_party_maven//:pin` passes.
- `./build.sh` passes.
- `./test.sh` passes.
