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
A0_DECISION="${OUTPUT_ROOT}/decisions/a0_mechanism_decision.csv"
A0_HASHES="${OUTPUT_ROOT}/decisions/a0_decision_inputs_and_hashes.csv"
if [[ ! -f "$CAMPAIGN_YAML" || ! -f "$CONTRACT" || ! -f "$A0_DECISION" || ! -f "$A0_HASHES" ]]; then
  echo "Campaign, orchestration contract, or finalized A0 evidence is missing." >&2
  exit 66
fi
# shellcheck disable=SC1090
source "$CONTRACT"

sha256_file() {
  sha256sum "$1" | awk '{print tolower($1)}'
}

if [[ "$LAUNCH_AUTHORIZED" != "true" ]]; then
  echo "The prepared campaign did not authorize execution." >&2
  exit 67
fi
if [[ "$(sha256_file "$CAMPAIGN_YAML")" != "${CAMPAIGN_SHA256,,}" ]] ||
   [[ "$(sha256_file "${OUTPUT_ROOT}/campaign_snapshot.yaml")" != "${CAMPAIGN_SNAPSHOT_SHA256,,}" ]]; then
  echo "Campaign source or prepared snapshot changed after materialization." >&2
  exit 68
fi

cd "$REPO_ROOT"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD="$(git rev-parse HEAD)"
UPSTREAM_REF="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
UPSTREAM_HEAD="$(git rev-parse '@{upstream}')"
case "$BRANCH" in
  main|overleaf/article-snapshot|overleaf-direct/main)
    echo "A1 recovery requires a dedicated task branch." >&2
    exit 69
    ;;
esac
if [[ "$HEAD" != "$UPSTREAM_HEAD" ]] ||
   [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "A1 recovery requires a clean task branch synchronized with upstream." >&2
  exit 70
fi
if ! git merge-base --is-ancestor "$PREPARED_HEAD" "$HEAD"; then
  echo "The prepared implementation HEAD is not an ancestor of the recovery HEAD." >&2
  exit 71
fi
if [[ -f "${OUTPUT_ROOT}/STOP" ]]; then
  echo "A STOP marker is present; refusing implicit recovery." >&2
  exit 72
fi

mkdir -p "${OUTPUT_ROOT}/status" "${OUTPUT_ROOT}/logs" \
  "${OUTPUT_ROOT}/decisions" "${OUTPUT_ROOT}/recovery"
exec 9>"${OUTPUT_ROOT}/recovery/a1_resume.lock"
if ! flock -n 9; then
  echo "Another A1 recovery process holds the campaign lock." >&2
  exit 73
fi

Rscript - "$OUTPUT_ROOT" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
root <- args[[1L]]
decision <- read.csv(file.path(root, "decisions", "a0_mechanism_decision.csv"),
                     stringsAsFactors = FALSE, check.names = FALSE)
hashes <- read.csv(file.path(root, "decisions", "a0_decision_inputs_and_hashes.csv"),
                   stringsAsFactors = FALSE, check.names = FALSE)
manifest <- read.csv(file.path(root, "runtime_manifest_a0.csv"),
                     stringsAsFactors = FALSE, check.names = FALSE)
if (nrow(decision) != 1L || !isTRUE(as.logical(decision$proceed_to_a1[[1L]])) ||
    as.integer(decision$completed[[1L]]) != 8L || as.integer(decision$failed[[1L]]) != 0L) {
  stop("A0 does not contain an eight-fit, zero-failure authorization for A1.", call. = FALSE)
}
if (nrow(manifest) != 8L || any(!file.exists(file.path(manifest$run_dir, ".fit_recovery_complete")))) {
  stop("A0 completion markers are incomplete.", call. = FALSE)
}
sha256 <- function(path) {
  out <- system2("sha256sum", path, stdout = TRUE)
  tolower(strsplit(out[[1L]], "[[:space:]]+")[[1L]][[1L]])
}
for (i in seq_len(nrow(hashes))) {
  if (!file.exists(hashes$path[[i]]) ||
      !identical(sha256(hashes$path[[i]]), tolower(hashes$sha256[[i]]))) {
    stop(sprintf("A0 decision input hash mismatch: %s", hashes$artifact[[i]]), call. = FALSE)
  }
}
RS

for pid in $(pgrep -f 'glofas_discrepancy_grouped_rhs_(orchestrate|resume_a1)[.]sh' || true); do
  if [[ "$pid" != "$$" && "$pid" != "$PPID" ]]; then
    cmd="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
    if [[ "$cmd" == *"$OUTPUT_ROOT"* ]]; then
      echo "A live campaign orchestrator already owns this output root (pid $pid)." >&2
      exit 74
    fi
  fi
done

A0_DECISION_SHA256="$(sha256_file "$A0_DECISION")"
A0_RANKING_SHA256="$(sha256_file "${OUTPUT_ROOT}/tables/a0_ranking.csv")"
printf '%s\n' \
  'campaign_id,recovery_wave,recovery_head,prepared_head,branch,upstream_ref,upstream_head,a0_decision_sha256,a0_ranking_sha256,finalizer_sha256,resume_script_sha256,created_at' \
  "${CAMPAIGN_ID},A1,${HEAD},${PREPARED_HEAD},${BRANCH},${UPSTREAM_REF},${UPSTREAM_HEAD},${A0_DECISION_SHA256},${A0_RANKING_SHA256},$(sha256_file application/scripts/glofas_discrepancy_grouped_rhs_finalize.R),$(sha256_file application/scripts/glofas_discrepancy_grouped_rhs_resume_a1.sh),$(date -Is)" \
  > "${OUTPUT_ROOT}/recovery/a1_resume_contract.csv"

STATUS_PATH="${OUTPUT_ROOT}/orchestration_status.csv"
EVENT_PATH="${OUTPUT_ROOT}/orchestration_events.csv"
CURRENT_PHASE="a1_recovery_preflight"
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
  if [[ $exit_code -ne 0 ]]; then write_status "failed" "$exit_code"; fi
}
trap on_exit EXIT

CURRENT_PHASE="a1_scheduler"
write_status "running"
CORES="$(python3 application/scripts/glofas_select_free_cpus.py \
  --count "$MAX_WORKERS" \
  --report "${OUTPUT_ROOT}/status/a1_recovery_cpu_ownership_audit.csv")"
AVAILABLE_COUNT="$(awk -F, '{print NF}' <<< "$CORES")"
PARALLEL=10
if (( PARALLEL > MAX_WORKERS )); then PARALLEL="$MAX_WORKERS"; fi
if (( PARALLEL > AVAILABLE_COUNT )); then PARALLEL="$AVAILABLE_COUNT"; fi
if (( PARALLEL < 1 )); then
  echo "No free physical core is available for A1 recovery." >&2
  exit 75
fi
CALIBRATION_JOBS=4
if (( CALIBRATION_JOBS > PARALLEL )); then CALIBRATION_JOBS="$PARALLEL"; fi
printf '%s\n' "$CORES" > "${OUTPUT_ROOT}/status/a1_recovery_selected_physical_cpus.txt"
printf 'wave,requested_jobs,available_physical_cores,parallel_limit,calibration_jobs,timestamp\nA1,10,%s,%s,%s,%s\n' \
  "$AVAILABLE_COUNT" "$PARALLEL" "$CALIBRATION_JOBS" "$(date -Is)" \
  > "${OUTPUT_ROOT}/status/a1_recovery_launch_resources.csv"

python3 application/scripts/glofas_fit_recovery_scheduler.py \
  --manifest "${OUTPUT_ROOT}/runtime_manifest_a1.csv" \
  --output-root "$OUTPUT_ROOT" \
  --max-parallel "$PARALLEL" \
  --cores "$CORES" \
  --max-load "$MAXIMUM_LOAD" \
  --min-memory-gb "$MEMORY_RESERVE_GB" \
  --min-disk-gb "$MINIMUM_FREE_DISK_GB" \
  --poll-seconds "$POLL_SECONDS" \
  --state-file "${OUTPUT_ROOT}/status/scheduler_state_a1.csv" \
  --calibration-jobs "$CALIBRATION_JOBS" \
  --calibration-iterations "$CALIBRATION_ITERATIONS" \
  --memory-reserve-gb "$MEMORY_RESERVE_GB" \
  --memory-safety-log "${OUTPUT_ROOT}/status/a1_recovery_memory_safety.csv" \
  --numerical-backend "$NUMERICAL_BACKEND" \
  --backend-threads "$BACKEND_THREADS" \
  --backend-library "$BACKEND_LIBRARY" \
  --backend-sha256 "$BACKEND_LIBRARY_SHA256" \
  --reference-feature-cache-root "${OUTPUT_ROOT}/common_cache/reference_features"

CURRENT_PHASE="stage_a_finalizer"
write_status "running"
Rscript application/scripts/glofas_discrepancy_grouped_rhs_finalize.R \
  --output_root "$OUTPUT_ROOT" \
  --wave ALL \
  > "${OUTPUT_ROOT}/logs/stage_a_finalizer_recovery.log" 2>&1

CURRENT_PHASE="complete"
write_status "completed" "0"
