#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_ROOT="${1:-${REPO_ROOT}/local_trackers/runtime_configs/glofas_context_prior_repair_20260826}"
MAX_PARALLEL="${2:-18}"
CORE_SPEC="${3:-auto}"
MANIFEST="${OUTPUT_ROOT}/runtime_manifest_stage1.csv"
STATUS_FILE="${OUTPUT_ROOT}/status/supervisor.csv"
PREFLIGHT_MARKER="${OUTPUT_ROOT}/.context_prior_preflight_passed"
BACKEND_LIBRARY="$(readlink -f /lib64/libopenblas.so.0)"
BACKEND_SHA256="$(sha256sum "$BACKEND_LIBRARY" | awk '{print $1}')"

if [[ ! -s "$MANIFEST" ]]; then
  echo "Missing prepared context-prior manifest: $MANIFEST" >&2
  exit 2
fi
if [[ ! -s "$PREFLIGHT_MARKER" ]]; then
  echo "Missing passed real-design preflight: $PREFLIGHT_MARKER" >&2
  exit 2
fi
if (( MAX_PARALLEL < 1 || MAX_PARALLEL > 18 )); then
  echo "The context-prior campaign permits 1--18 one-thread workers." >&2
  exit 2
fi
if [[ -e "${OUTPUT_ROOT}/STOP" ]]; then
  echo "A STOP marker is present: ${OUTPUT_ROOT}/STOP" >&2
  exit 2
fi

mkdir -p "${OUTPUT_ROOT}/status"
write_status() {
  local status="$1"
  local stage="$2"
  printf 'status,stage,timestamp,pid\n%s,%s,%s,%s\n' \
    "$status" "$stage" "$(date -Is)" "$$" > "${STATUS_FILE}.tmp"
  mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
}
CURRENT_STAGE="initializing"
on_exit() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    write_status "failed" "$CURRENT_STAGE"
  fi
}
trap on_exit EXIT

cd "$REPO_ROOT"
if [[ -f "${OUTPUT_ROOT}/.context_prior_campaign_complete" ]]; then
  write_status "completed_existing" "complete"
  exit 0
fi

CURRENT_STAGE="context_prior_screen"
write_status "running" "$CURRENT_STAGE"
python3 application/scripts/glofas_fit_recovery_scheduler.py \
  --manifest "$MANIFEST" \
  --output-root "$OUTPUT_ROOT" \
  --state-name scheduler_state_stage1.csv \
  --max-parallel "$MAX_PARALLEL" \
  --max-load 60 \
  --min-memory-gb 64 \
  --min-disk-gb 150 \
  --poll-seconds 30 \
  --cores "$CORE_SPEC" \
  --numerical-backend openblas_serial \
  --backend-threads 1 \
  --backend-library "$BACKEND_LIBRARY" \
  --backend-sha256 "$BACKEND_SHA256" \
  --reference-feature-cache-root "${OUTPUT_ROOT}/common_cache/reference_feature_cache"

CURRENT_STAGE="finalization"
write_status "running" "$CURRENT_STAGE"
Rscript application/scripts/glofas_discrepancy_context_repair_finalize.R \
  --output_root "$OUTPUT_ROOT" \
  --cleanup true

CURRENT_STAGE="complete"
write_status "completed" "$CURRENT_STAGE"
