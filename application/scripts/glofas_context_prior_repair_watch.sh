#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_ROOT="${1:-${REPO_ROOT}/local_trackers/runtime_configs/glofas_context_prior_repair_20260826}"
INTERVAL="${2:-120}"

while true; do
  clear || true
  date -Is
  python3 "${REPO_ROOT}/application/scripts/glofas_discrepancy_context_repair_health.py" \
    --output-root "$OUTPUT_ROOT" --details || true
  if [[ -f "${OUTPUT_ROOT}/.context_prior_campaign_complete" || \
        -f "${OUTPUT_ROOT}/STOP" ]]; then
    exit 0
  fi
  sleep "$INTERVAL"
done
