#!/usr/bin/env bash
set -euo pipefail

got="$1"
expected="$2"

diff -u "$expected" "$got"
