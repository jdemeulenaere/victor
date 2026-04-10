# AGENTS.md

## Repository Expectations

- Use Bazel as the primary interface for build/test/run workflows:
  - Build with `bazel build <target>`
  - Test with `bazel test <target>`
  - Run executables with `bazel run <target>`.
- Run `./build.sh` after changing any source file to ensure that everything still compiles.
- Run `./test.sh` after changing any source file to ensure that all tests still pass.
- When adding dependencies or tools, use the latest stable released version whenever possible.
