#!/usr/bin/env bash
# Convenience wrapper to run the standard lint + test suite.

set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

scripts/lint.sh
scripts/run-tests.sh
scripts/smoke-test.sh
