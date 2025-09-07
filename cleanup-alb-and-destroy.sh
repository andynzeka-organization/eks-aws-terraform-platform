#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper to run the main cleanup script from the repo root
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "${SCRIPT_DIR}/scripts/cleanup-alb-and-destroy.sh" "$@"

