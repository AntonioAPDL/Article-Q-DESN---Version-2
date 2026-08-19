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
PREFLIGHT_ENABLED="${GLOFAS_RESERVOIR_PREFLIGHT_ENABLED:-false}"
PREFLIGHT_TARGET="${GLOFAS_RESERVOIR_PREFLIGHT_TARGET:-reservoir}"
PREFLIGHT_REJECT_DECISION="${GLOFAS_RESERVOIR_PREFLIGHT_REJECT_DECISION:-reject}"
PREFLIGHT_RUN_ID="${GLOFAS_RESERVOIR_PREFLIGHT_RUN_ID:-${RUN_ID}__reservoir_preflight}"
PREFLIGHT_SUMMARY="${GLOFAS_RESERVOIR_PREFLIGHT_SUMMARY_PATH:-${OUTPUT_ROOT}/runs/${PREFLIGHT_RUN_ID}/tables/reservoir_screening_architecture_summary.csv}"
PREFLIGHT_MAX_CORR="${GLOFAS_RESERVOIR_PREFLIGHT_MAX_CORR_FEATURES_FULL:-5000}"
PREFLIGHT_CORR_BLOCK="${GLOFAS_RESERVOIR_PREFLIGHT_CORR_BLOCK_SIZE:-512}"
PREFLIGHT_SPECTRAL_EXACT="${GLOFAS_RESERVOIR_PREFLIGHT_SPECTRAL_RADIUS_EXACT_MAX_N:-512}"
PREFLIGHT_CHEAP_VALIDATION="${GLOFAS_RESERVOIR_PREFLIGHT_CHEAP_VALIDATION:-false}"

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
if [[ -f "${RUN_DIR}/.reservoir_preflight_rejected" ]]; then
  write_status "rejected_existing" "reservoir_preflight"
  exit 0
fi

if [[ "$PREFLIGHT_ENABLED" == "true" ]]; then
  CURRENT_STAGE="reservoir_preflight"
  write_status "running" "$CURRENT_STAGE"
  PREFLIGHT_RUN_DIR="${OUTPUT_ROOT}/runs/${PREFLIGHT_RUN_ID}"
  if [[ -d "$PREFLIGHT_RUN_DIR" && ! -f "$PREFLIGHT_SUMMARY" ]]; then
    mv "$PREFLIGHT_RUN_DIR" "${PREFLIGHT_RUN_DIR}__incomplete_$(date +%Y%m%d_%H%M%S)"
  fi
  if [[ ! -f "$PREFLIGHT_SUMMARY" ]]; then
    Rscript application/scripts/03_screen_reservoir_design.R \
      --config "$CONFIG_ARG" \
      --run_id "$PREFLIGHT_RUN_ID" \
      --diagnostic_target "$PREFLIGHT_TARGET" \
      --cheap_validation "$PREFLIGHT_CHEAP_VALIDATION" \
      --max_corr_features_full "$PREFLIGHT_MAX_CORR" \
      --corr_block_size "$PREFLIGHT_CORR_BLOCK" \
      --spectral_radius_exact_max_n "$PREFLIGHT_SPECTRAL_EXACT"
  fi
  PREFLIGHT_AUDIT="${STATUS_DIR}/${CANDIDATE_ID}.reservoir_preflight.csv"
  set +e
  Rscript application/scripts/glofas_reservoir_preflight_gate.R \
    --summary "$PREFLIGHT_SUMMARY" \
    --candidate_id "$CANDIDATE_ID" \
    --reject_decision "$PREFLIGHT_REJECT_DECISION" \
    --output "$PREFLIGHT_AUDIT"
  PREFLIGHT_EXIT=$?
  set -e
  if [[ $PREFLIGHT_EXIT -eq 42 ]]; then
    mkdir -p "$RUN_DIR"
    cp "$PREFLIGHT_AUDIT" "${RUN_DIR}/reservoir_preflight_gate.csv"
    printf 'rejected %s\n' "$(date -Is)" > "${RUN_DIR}/.reservoir_preflight_rejected"
    write_status "rejected" "$CURRENT_STAGE" "42"
    exit 0
  fi
  if [[ $PREFLIGHT_EXIT -ne 0 ]]; then
    exit "$PREFLIGHT_EXIT"
  fi
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
