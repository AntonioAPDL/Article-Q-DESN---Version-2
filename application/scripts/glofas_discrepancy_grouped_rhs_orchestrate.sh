#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 CAMPAIGN_YAML OUTPUT_ROOT" >&2
  exit 2
fi

CAMPAIGN_YAML="$1"
OUTPUT_ROOT="$2"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ "$CAMPAIGN_YAML" != /* ]]; then CAMPAIGN_YAML="${REPO_ROOT}/${CAMPAIGN_YAML}"; fi
if [[ "$OUTPUT_ROOT" != /* ]]; then OUTPUT_ROOT="${REPO_ROOT}/${OUTPUT_ROOT}"; fi
CAMPAIGN_YAML="$(readlink -f "$CAMPAIGN_YAML")"
OUTPUT_ROOT="$(readlink -f "$OUTPUT_ROOT")"
OWNED_ROOT="$(readlink -f "${REPO_ROOT}/local_trackers/runtime_configs")"

case "$OUTPUT_ROOT" in
  "$OWNED_ROOT"/*) ;;
  *) echo "Refusing output root outside the task-owned runtime tree: $OUTPUT_ROOT" >&2; exit 64 ;;
esac

CONTRACT="${OUTPUT_ROOT}/orchestration_contract.env"
if [[ ! -f "$CAMPAIGN_YAML" || ! -f "$CONTRACT" ]]; then
  echo "Campaign YAML or prepared orchestration contract is missing." >&2
  exit 66
fi
# shellcheck disable=SC1090
source "$CONTRACT"

sha256_file() {
  sha256sum "$1" | awk '{print tolower($1)}'
}

if [[ "$LAUNCH_AUTHORIZED" != "true" ]]; then
  echo "Prepared contract does not authorize launch." >&2
  exit 67
fi
if [[ "$(sha256_file "$CAMPAIGN_YAML")" != "${CAMPAIGN_SHA256,,}" ]] ||
   [[ "$(sha256_file "${OUTPUT_ROOT}/campaign_snapshot.yaml")" != "${CAMPAIGN_SNAPSHOT_SHA256,,}" ]]; then
  echo "Campaign source or prepared snapshot changed after materialization." >&2
  exit 68
fi
if [[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" != "$PREPARED_HEAD" ]] ||
   ! git -C "$REPO_ROOT" diff --quiet --ignore-submodules --; then
  echo "Tracked implementation state differs from the prepared campaign provenance." >&2
  exit 71
fi

mkdir -p "${OUTPUT_ROOT}/status" "${OUTPUT_ROOT}/logs" "${OUTPUT_ROOT}/decisions"
STATUS_PATH="${OUTPUT_ROOT}/orchestration_status.csv"
EVENT_PATH="${OUTPUT_ROOT}/orchestration_events.csv"
CURRENT_PHASE="preflight"

write_status() {
  local state="$1"
  local exit_code="${2:-}"
  printf 'campaign_id,state,phase,timestamp,pid,exit_code\n%s,%s,%s,%s,%s,%s\n' \
    "$CAMPAIGN_ID" "$state" "$CURRENT_PHASE" "$(date -Is)" "$$" "$exit_code" \
    > "${STATUS_PATH}.tmp"
  mv "${STATUS_PATH}.tmp" "$STATUS_PATH"
  if [[ ! -f "$EVENT_PATH" ]]; then
    printf 'campaign_id,state,phase,timestamp,pid,exit_code\n' > "$EVENT_PATH"
  fi
  printf '%s,%s,%s,%s,%s,%s\n' \
    "$CAMPAIGN_ID" "$state" "$CURRENT_PHASE" "$(date -Is)" "$$" "$exit_code" >> "$EVENT_PATH"
}

on_exit() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    write_status "failed" "$exit_code"
  fi
}
trap on_exit EXIT

select_cores() {
  local wave="$1"
  python3 application/scripts/glofas_select_free_cpus.py \
    --count "$MAX_WORKERS" \
    --report "${OUTPUT_ROOT}/status/${wave,,}_cpu_ownership_audit.csv"
}

run_wave() {
  local wave="$1"
  local manifest="$2"
  local requested="$3"
  local calibration_jobs="$4"
  local cores
  while ! cores="$(select_cores "$wave" 2>> "${OUTPUT_ROOT}/logs/resource_wait.log")"; do
    if [[ -f "${OUTPUT_ROOT}/STOP" ]]; then
      echo "STOP marker observed while waiting for a free physical core." >&2
      return 70
    fi
    printf '%s wave=%s waiting_for_free_physical_core\n' "$(date -Is)" "$wave" \
      >> "${OUTPUT_ROOT}/logs/resource_wait.log"
    sleep "$POLL_SECONDS"
  done
  local available_count
  available_count="$(awk -F, '{print NF}' <<< "$cores")"
  local parallel="$requested"
  if (( parallel > MAX_WORKERS )); then parallel="$MAX_WORKERS"; fi
  if (( parallel > available_count )); then parallel="$available_count"; fi
  if (( parallel < 1 )); then
    echo "No free physical core is available for wave $wave." >&2
    return 69
  fi
  if (( calibration_jobs > parallel )); then calibration_jobs="$parallel"; fi
  printf '%s\n' "$cores" > "${OUTPUT_ROOT}/status/${wave,,}_selected_physical_cpus.txt"
  printf 'wave,requested_jobs,available_physical_cores,parallel_limit,calibration_jobs,timestamp\n%s,%s,%s,%s,%s,%s\n' \
    "$wave" "$requested" "$available_count" "$parallel" "$calibration_jobs" "$(date -Is)" \
    > "${OUTPUT_ROOT}/status/${wave,,}_launch_resources.csv"

  python3 application/scripts/glofas_fit_recovery_scheduler.py \
    --manifest "$manifest" \
    --output-root "$OUTPUT_ROOT" \
    --max-parallel "$parallel" \
    --cores "$cores" \
    --max-load "$MAXIMUM_LOAD" \
    --min-memory-gb "$MEMORY_RESERVE_GB" \
    --min-disk-gb "$MINIMUM_FREE_DISK_GB" \
    --poll-seconds "$POLL_SECONDS" \
    --state-file "${OUTPUT_ROOT}/status/scheduler_state_${wave,,}.csv" \
    --calibration-jobs "$calibration_jobs" \
    --calibration-iterations "$CALIBRATION_ITERATIONS" \
    --memory-reserve-gb "$MEMORY_RESERVE_GB" \
    --memory-safety-log "${OUTPUT_ROOT}/status/${wave,,}_memory_safety.csv" \
    --numerical-backend "$NUMERICAL_BACKEND" \
    --backend-threads "$BACKEND_THREADS" \
    --backend-library "$BACKEND_LIBRARY" \
    --backend-sha256 "$BACKEND_LIBRARY_SHA256" \
    --reference-feature-cache-root "${OUTPUT_ROOT}/common_cache/reference_features"
}

cd "$REPO_ROOT"
if [[ -f "${OUTPUT_ROOT}/STOP" ]]; then
  echo "A STOP marker is present; refusing to resume implicitly." >&2
  exit 70
fi

CURRENT_PHASE="a0_scheduler"
write_status "running"
run_wave "A0" "${OUTPUT_ROOT}/runtime_manifest_a0.csv" 8 "$A0_CALIBRATION_JOBS"

CURRENT_PHASE="a0_finalizer"
write_status "running"
Rscript application/scripts/glofas_discrepancy_grouped_rhs_finalize.R \
  --output_root "$OUTPUT_ROOT" \
  --wave A0 \
  > "${OUTPUT_ROOT}/logs/a0_finalizer.log" 2>&1

PROCEED="$(Rscript - "${OUTPUT_ROOT}/decisions/a0_mechanism_decision.csv" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
x <- read.csv(args[[1L]], stringsAsFactors = FALSE, check.names = FALSE)
if (nrow(x) != 1L || !"proceed_to_a1" %in% names(x)) quit(status = 2L)
cat(tolower(as.character(x$proceed_to_a1[[1L]])))
RS
)"
if [[ "$PROCEED" != "true" ]]; then
  CURRENT_PHASE="a0_scientific_stop"
  printf 'campaign_id,decision,timestamp\n%s,stop_after_a0,%s\n' \
    "$CAMPAIGN_ID" "$(date -Is)" > "${OUTPUT_ROOT}/decisions/campaign_stop_after_a0.csv"
  write_status "completed_scientific_stop" "0"
  exit 0
fi

CURRENT_PHASE="a1_scheduler"
write_status "running"
run_wave "A1" "${OUTPUT_ROOT}/runtime_manifest_a1.csv" 10 4

CURRENT_PHASE="stage_a_finalizer"
write_status "running"
Rscript application/scripts/glofas_discrepancy_grouped_rhs_finalize.R \
  --output_root "$OUTPUT_ROOT" \
  --wave ALL \
  > "${OUTPUT_ROOT}/logs/stage_a_finalizer.log" 2>&1

CURRENT_PHASE="complete"
write_status "completed" "0"
