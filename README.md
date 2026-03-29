# Victor (Virtual Intelligence Constantly Tracking Online Requests)

Victor is an event-driven, polyglot assistant in a single Bazel monorepo.

## Architecture

- `backend/`: Kotlin orchestration service.
- `web/`: TypeScript + React dashboard.
- `scripts/`: Python toolbelt and automation helpers.
- `core/proto/`: Shared protobuf schema.

## Build and Run

Use Bazel for all builds.

```bash
./build.sh
```

```bash
# Backend
bazel run //backend

# Web dev server
bazel run //web:dev

# Web production build
bazel build //web:build

# Python scripts entrypoint
bazel run //scripts
```

## Tech Stack

- Build system: Bazel (Bzlmod)
- Rules: `rules_kotlin`, `rules_python`, `rules_proto`, `aspect_rules_js`, `aspect_rules_ts`
- Languages: Kotlin, Python, TypeScript
