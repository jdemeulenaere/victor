#!/usr/bin/env python3
"""Integration smoke test for the greeter Python client.

This test:
1. Stops any previous backend listening on the test port and waits for it to exit.
2. Starts the backend binary.
3. Executes the Python client binary and verifies the backend response message.
"""

import os
import signal
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

PORT = int(os.environ.get("VICTOR_SMOKE_TEST_PORT", "18080"))
REQUEST_NAME = "smoke-test"
EXPECTED_MESSAGE = f"Hello, {REQUEST_NAME}! (from Kotlin backend)"
START_TIMEOUT_SECONDS = float(
    os.environ.get("VICTOR_SMOKE_START_TIMEOUT_SECONDS", "180")
)
STOP_TIMEOUT_SECONDS = float(os.environ.get("VICTOR_SMOKE_STOP_TIMEOUT_SECONDS", "20"))
LSOF_BIN = shutil.which("lsof") or "/usr/sbin/lsof"


def _listening_pids(port: int) -> list[int]:
    if not Path(LSOF_BIN).exists():
        raise RuntimeError(
            "Could not find `lsof` (looked in PATH and /usr/sbin/lsof), "
            "which is required to stop a previous backend instance."
        )

    result = subprocess.run(
        [LSOF_BIN, "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"],
        capture_output=True,
        text=True,
        check=False,
    )

    if result.returncode not in (0, 1):
        raise RuntimeError(f"Failed to inspect port {port}: {result.stderr.strip()}")

    pids: list[int] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.isdigit():
            pids.append(int(line))
    return sorted(set(pids))


def _wait_until_port_closed(port: int, timeout_seconds: float) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if not _listening_pids(port):
            return True
        time.sleep(0.2)
    return not _listening_pids(port)


def _wait_until_port_open(
    port: int, timeout_seconds: float, proc: subprocess.Popen[str]
) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            return False

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return True

        time.sleep(0.2)

    return False


def _stop_existing_backend(port: int) -> None:
    pids = _listening_pids(port)
    if not pids:
        print(f"No existing backend detected on port {port}.")
        return

    print(
        f"Stopping existing backend process(es) on port {port}: {', '.join(map(str, pids))}"
    )
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue

    if _wait_until_port_closed(port, STOP_TIMEOUT_SECONDS):
        print("Existing backend stopped.")
        return

    pids = _listening_pids(port)
    if pids:
        print(f"Force killing remaining process(es): {', '.join(map(str, pids))}")
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                continue

    if not _wait_until_port_closed(port, 5):
        raise RuntimeError(f"Could not stop existing backend on port {port}.")

    print("Existing backend stopped.")


def _start_backend(
    backend_bin: str, port: int, backend_log: Path
) -> subprocess.Popen[str]:
    env = os.environ.copy()
    env["PORT"] = str(port)

    backend_log.write_text("")
    log_handle = backend_log.open("a", encoding="utf-8")

    proc = subprocess.Popen(
        [backend_bin],
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
        start_new_session=True,
    )
    log_handle.close()

    if not _wait_until_port_open(port, START_TIMEOUT_SECONDS, proc):
        rc = proc.poll()
        log_tail = _tail_log(backend_log)
        if rc is None:
            _stop_backend_process(proc, port)
            raise RuntimeError(
                "Backend did not become ready before timeout.\n"
                f"Last backend log lines:\n{log_tail}"
            )
        raise RuntimeError(
            f"Backend exited with code {rc} before becoming ready.\n"
            f"Last backend log lines:\n{log_tail}"
        )

    print(f"Backend is listening on localhost:{port}.")
    return proc


def _stop_backend_process(proc: subprocess.Popen[str], port: int) -> None:
    if proc.poll() is not None:
        _wait_until_port_closed(port, 2)
        return

    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

    try:
        proc.wait(timeout=STOP_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=5)

    if not _wait_until_port_closed(port, 5):
        raise RuntimeError(
            f"Backend process did not release port {port} during cleanup."
        )


def _run_python_client(client_bin: str, port: int) -> str:
    result = subprocess.run(
        [client_bin, REQUEST_NAME, "--target", f"localhost:{port}"],
        capture_output=True,
        text=True,
        check=False,
    )
    output = f"{result.stdout}{result.stderr}".strip()

    if result.returncode != 0:
        raise RuntimeError(
            f"Python client failed with exit code {result.returncode}.\nOutput:\n{output}"
        )

    if EXPECTED_MESSAGE not in output:
        raise AssertionError(
            "Python client output did not include the expected backend response.\n"
            f"Expected: {EXPECTED_MESSAGE}\n"
            f"Output:\n{output}"
        )

    print(f"Verified expected response: {EXPECTED_MESSAGE}")
    return output


def _tail_log(path: Path, lines: int = 100) -> str:
    if not path.exists():
        return "<log file not found>"
    content = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(content[-lines:]) if content else "<empty log>"


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "Usage: smoke_test.py <backend_binary> <python_client_binary>",
            file=sys.stderr,
        )
        return 2

    backend_bin = sys.argv[1]
    python_client_bin = sys.argv[2]
    backend_log = (
        Path(os.environ.get("TEST_TMPDIR", "/tmp")) / "victor_backend_smoke_test.log"
    )

    backend_proc: subprocess.Popen[str] | None = None
    try:
        _stop_existing_backend(PORT)
        backend_proc = _start_backend(backend_bin, PORT, backend_log)
        _run_python_client(python_client_bin, PORT)
        print("Smoke test passed.")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"Smoke test failed: {exc}", file=sys.stderr)
        print(f"Backend log: {backend_log}", file=sys.stderr)
        return 1
    finally:
        if backend_proc is not None:
            try:
                _stop_backend_process(backend_proc, PORT)
            except Exception as cleanup_exc:  # noqa: BLE001
                print(f"Cleanup warning: {cleanup_exc}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
