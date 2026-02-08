#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:a:h}"
zsh "$SCRIPT_DIR/run_tests.sh" "$@"
