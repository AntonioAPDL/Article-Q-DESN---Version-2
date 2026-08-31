#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_ROOT="${1:-${REPO_ROOT}/local_trackers/runtime_configs/glofas_discrepancy_tau0_relax_p50_20260831}"
SOURCE_ROOT="${2:-${REPO_ROOT}/local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829}"
MAX_PARALLEL="${GLOFAS_TAU0_MAX_PARALLEL:-5}"
RETRY_FAILED="${GLOFAS_TAU0_RETRY_FAILED:-false}"
MANIFEST="${OUTPUT_ROOT}/candidate_registry.csv"
LAUNCH_LOG="${OUTPUT_ROOT}/logs/campaign_launcher.log"
LOCK_PATH="${OUTPUT_ROOT}/status/campaign_launcher.lock"

mkdir -p "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/status"
exec 9>"${LOCK_PATH}"
if ! flock -n 9; then
  echo "The discrepancy tau0 campaign is already owned by another launcher." >&2
  exit 75
fi
exec > >(tee -a "${LAUNCH_LOG}") 2>&1
cd "${REPO_ROOT}"

on_exit() {
  local exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    printf 'failed %s exit=%s\n' "$(date -Is)" "${exit_code}" > "${OUTPUT_ROOT}/.launch_failed"
  fi
}
trap on_exit EXIT

echo "[$(date -Is)] GloFAS discrepancy tau0 campaign launcher started."
case "${RETRY_FAILED,,}" in
  true|t|1|yes|y) RETRY_ARGS=(--retry-failed) ;;
  false|f|0|no|n|"") RETRY_ARGS=() ;;
  *)
    echo "Invalid GLOFAS_TAU0_RETRY_FAILED value: ${RETRY_FAILED}" >&2
    exit 2
    ;;
esac
if [[ ! -f "${MANIFEST}" ]]; then
  Rscript application/scripts/glofas_discrepancy_tau0_screen_prepare.R \
    --source_root "${SOURCE_ROOT}" \
    --output_root "${OUTPUT_ROOT}" \
    --max_iter 400
fi

Rscript application/scripts/glofas_discrepancy_tau0_screen_preflight.R \
  --manifest "${MANIFEST}" \
  --output_root "${OUTPUT_ROOT}"

printf 'started %s\n' "$(date -Is)" > "${OUTPUT_ROOT}/.launch_started"
python3 application/scripts/glofas_fit_recovery_scheduler.py \
  --manifest "${MANIFEST}" \
  --output-root "${OUTPUT_ROOT}" \
  --max-parallel "${MAX_PARALLEL}" \
  --max-load 58 \
  --min-memory-gb 48 \
  --min-disk-gb 120 \
  --poll-seconds 60 \
  --cores auto \
  --numerical-backend bundled_rblas \
  --backend-threads 1 \
  "${RETRY_ARGS[@]}"

Rscript application/scripts/glofas_discrepancy_tau0_screen_finalize.R \
  --manifest "${MANIFEST}" \
  --output_root "${OUTPUT_ROOT}" \
  --source_root "${SOURCE_ROOT}"

rm -f "${OUTPUT_ROOT}/.launch_failed"
printf 'completed %s\n' "$(date -Is)" > "${OUTPUT_ROOT}/.launch_complete"
echo "[$(date -Is)] GloFAS discrepancy tau0 campaign completed and finalized."
