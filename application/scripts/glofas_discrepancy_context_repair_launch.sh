#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_ROOT="${1:-${REPO_ROOT}/local_trackers/runtime_configs/glofas_discrepancy_context_repair_20260825}"
MAX_PARALLEL="${2:-20}"
CORE_SPEC="${3:-auto}"
STAGE0_MANIFEST="${OUTPUT_ROOT}/runtime_manifest_stage0.csv"
STAGE1_MANIFEST="${OUTPUT_ROOT}/runtime_manifest_stage1.csv"
STATUS_FILE="${OUTPUT_ROOT}/status/supervisor.csv"
BACKEND_LIBRARY="$(readlink -f /lib64/libopenblas.so.0)"
BACKEND_SHA256="$(sha256sum "$BACKEND_LIBRARY" | awk '{print $1}')"

if [[ ! -f "$STAGE0_MANIFEST" || ! -f "$STAGE1_MANIFEST" ]]; then
  echo "Missing prepared context-repair stage manifests under: $OUTPUT_ROOT" >&2
  exit 2
fi
if [[ "$MAX_PARALLEL" -ne 20 ]]; then
  echo "The frozen repair campaign requires 20 one-thread worker slots." >&2
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
on_exit() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    write_status "failed" "${CURRENT_STAGE:-initializing}"
  fi
}
trap on_exit EXIT

run_scheduler() {
  local manifest="$1"
  local state_name="$2"
  python3 application/scripts/glofas_fit_recovery_scheduler.py \
    --manifest "$manifest" \
    --output-root "$OUTPUT_ROOT" \
    --state-name "$state_name" \
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
}

cd "$REPO_ROOT"
if [[ -f "${OUTPUT_ROOT}/.context_repair_campaign_complete" ]]; then
  write_status "completed_existing" "complete"
  exit 0
fi

if [[ ! -f "${OUTPUT_ROOT}/.stage0_passed" ]]; then
  CURRENT_STAGE="stage0_exact_continuation"
  write_status "running" "$CURRENT_STAGE"
  run_scheduler "$STAGE0_MANIFEST" "scheduler_state_stage0.csv"

  CURRENT_STAGE="stage0_gate"
  write_status "running" "$CURRENT_STAGE"
  Rscript application/scripts/glofas_discrepancy_context_repair_stage0_gate.R \
    --output_root "$OUTPUT_ROOT"
fi

if [[ ! -f "${OUTPUT_ROOT}/.stage0_passed" ]]; then
  echo "Stage 0 did not authorize the context factorial." >&2
  exit 3
fi

CURRENT_STAGE="stage1_context_factorial"
write_status "running" "$CURRENT_STAGE"
run_scheduler "$STAGE1_MANIFEST" "scheduler_state_stage1.csv"

CURRENT_STAGE="finalization"
write_status "running" "$CURRENT_STAGE"
Rscript application/scripts/glofas_discrepancy_context_repair_finalize.R \
  --output_root "$OUTPUT_ROOT" \
  --cleanup true

CURRENT_STAGE="complete"
write_status "completed" "$CURRENT_STAGE"
