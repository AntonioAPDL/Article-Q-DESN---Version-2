#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_ROOT="${1:-${REPO_ROOT}/local_trackers/runtime_configs/glofas_discrepancy_transition_bridge_20260825}"
HEALTH_LOG="${OUTPUT_ROOT}/logs/health_watch.log"
mkdir -p "$(dirname "$HEALTH_LOG")"

while true; do
  {
    date -Is
    python3 "${REPO_ROOT}/application/scripts/glofas_discrepancy_transition_health.py" \
      --output-root "$OUTPUT_ROOT" || true
    echo
  } >> "$HEALTH_LOG"
  if [[ -f "${OUTPUT_ROOT}/.transition_campaign_complete" ]]; then
    break
  fi
  if [[ -f "${OUTPUT_ROOT}/STOP" ]]; then
    break
  fi
  sleep 300
done
