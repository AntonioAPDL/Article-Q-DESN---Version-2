#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 CANDIDATE_ID CONFIG RUN_ID OUTPUT_ROOT" >&2
  exit 2
fi

CANDIDATE_ID="$1"
CONFIG="$2"
RUN_ID="$3"
OUTPUT_ROOT="$4"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATUS_DIR="${OUTPUT_ROOT}/status"
RUN_DIR="${OUTPUT_ROOT}/runs/${RUN_ID}"
STATUS_FILE="${STATUS_DIR}/${CANDIDATE_ID}.csv"
LOCK_FILE="${STATUS_DIR}/${CANDIDATE_ID}.lock"
CURRENT_STAGE="initializing"

mkdir -p "$STATUS_DIR"
cd "$REPO_ROOT"
CONFIG_ARG="$CONFIG"
if [[ "$CONFIG_ARG" == "${REPO_ROOT}/"* ]]; then
  CONFIG_ARG="${CONFIG_ARG#"${REPO_ROOT}/"}"
fi

write_status() {
  local status="$1"
  local stage="$2"
  local exit_code="${3:-}"
  printf 'candidate_id,status,stage,timestamp,run_id,pid,exit_code\n%s,%s,%s,%s,%s,%s,%s\n' \
    "$CANDIDATE_ID" "$status" "$stage" "$(date -Is)" "$RUN_ID" "$$" "$exit_code" \
    > "${STATUS_FILE}.tmp"
  mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
}

on_exit() {
  local exit_code=$?
  if [[ $exit_code -ne 0 && ! -f "${RUN_DIR}/.fit_recovery_complete" ]]; then
    write_status "failed" "$CURRENT_STAGE" "$exit_code"
  fi
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Candidate ${CANDIDATE_ID} is already owned by another worker." >&2
  exit 75
fi
trap on_exit EXIT

export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1
export NUMEXPR_NUM_THREADS=1

if [[ -f "${RUN_DIR}/.fit_recovery_complete" ]]; then
  write_status "completed_existing" "complete"
  exit 0
fi

CURRENT_STAGE="03_fit_models"
write_status "running" "$CURRENT_STAGE"
Rscript application/scripts/03_fit_models.R \
  --config "$CONFIG_ARG" \
  --run_id "$RUN_ID" \
  --confirm_final_launch true

CURRENT_STAGE="04_score_models"
write_status "running" "$CURRENT_STAGE"
Rscript application/scripts/04_score_models.R --config "$CONFIG_ARG" --run_id "$RUN_ID"

CURRENT_STAGE="05_make_outputs"
write_status "running" "$CURRENT_STAGE"
Rscript application/scripts/05_make_outputs.R --config "$CONFIG_ARG" --run_id "$RUN_ID"

CURRENT_STAGE="07_post_analysis"
write_status "running" "$CURRENT_STAGE"
Rscript application/scripts/07_post_analysis.R --config "$CONFIG_ARG" --run_id "$RUN_ID"

CURRENT_STAGE="observed_fit_scoring"
write_status "running" "$CURRENT_STAGE"
Rscript application/scripts/glofas_fit_recovery_score_run.R \
  --candidate_id "$CANDIDATE_ID" \
  --run_dir "$RUN_DIR" \
  --output_root "${OUTPUT_ROOT}/scores"

printf 'completed %s\n' "$(date -Is)" > "${RUN_DIR}/.fit_recovery_complete"
CURRENT_STAGE="complete"
write_status "completed" "$CURRENT_STAGE"
