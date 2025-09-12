#!/usr/bin/env bash
set -euo pipefail

# Orchestrated teardown: destroys platform apps, ALB controller, ingress stack,
# then root stack. Falls back to force-deleting VPC dependencies if needed.

export FORCE=${FORCE:-true}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
"${SCRIPT_DIR}/cleanup-alb-and-destroy.sh"

