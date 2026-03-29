# Victor (Virtual Intelligence Constantly Tracking Online Requests)

Victor is an event-driven, polyglot personal AI assistant designed to operate autonomously in the background. It is capable of receiving events (e.g., Slack messages, emails, chron jobs), determining the appropriate actions, and even generating, testing, and deploying its own code to accomplish tasks.

## 🏗 Architecture

Victor is structured as a highly modular, event-driven system inside a **Bazel Monorepo (Bzlmod)**:

*   **`backend/` (The Brain):** Written in Kotlin (JVM). This is the central orchestrator. It manages the event loop, state, short/long-term memory, and coordinates with external LLM APIs.
*   **`web/` (The Dashboard):** Written in TypeScript. A companion web interface to monitor Victor's background tasks, configure settings, and provide a direct manual chat interface.
*   **`scripts/` (The Toolbelt):** Written in Python. A sandboxed area where Victor can generate, test, and execute data-scraping, automation, or machine-learning scripts.
*   **`core/proto/` (The Lingua Franca):** Language-agnostic Protocol Buffers defining the internal communication schemas (e.g., the standard `Event` model) across all of Victor's components.

## 🚀 Getting Started

This repository uses **Bazel 8** via `bazelisk`. Ensure you have `bazelisk` installed on your system.
The project is configured to use fully hermetic toolchains (Java, Python, Node), meaning it will download its own necessary compilers and runtimes automatically.

### Running the Components

**The Brain (Kotlin Backend)**
```bash
bazel run //backend
```

**The Web Dashboard (TypeScript)**
```bash
# (Coming soon: bazel run //web:dev_server)
bazel build //web/...
```

**The Toolbelt (Python Sandbox)**
```bash
# (Coming soon: execution environments)
bazel build //scripts/...
```

## 🛠 Tech Stack

*   **Build System:** Bazel (Bzlmod)
    *   `rules_kotlin`
    *   `rules_python`
    *   `aspect_rules_ts` 
    *   `rules_proto`
*   **Languages:** Kotlin 1.9+, Python 3.12, TypeScript
*   **Communication:** gRPC / Protocol Buffers
