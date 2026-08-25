#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Launch a Phase 119 case-specific joint QDESN screening shard as disjoint
candidate-row chunks.

This is the preferred high-throughput launcher for Phase 119.  Each worker gets
an explicit --candidate-ids subset and writes summaries to its own worker
directory.  Candidate fit/forecast artifacts remain in the unique paths already
declared by the Phase 119 registry.  After all workers finish, run the printed
audit command to build the canonical shard summary.

Options:
  --shard NAME                  exal_high_priority, al_high_priority,
                                high_priority, moderate_priority, context_priority.
  --workers N                   Number of row-level workers to launch.
  --n-cores-per-worker N        Cores passed to each Phase 106 worker.
  --readiness-dir PATH          Phase 119 readiness artifact directory.
  --screening-output-dir PATH   Phase 119 screening output root.
  --fixture-dir PATH            Joint QDESN simulation fixture directory.
  --phase118-log PATH           Phase 118 log used for clean-exit verification.
  --session-prefix PREFIX       Prefix for worker tmux sessions.
  --run-id ID                   Stable id for worker/log directories.
  --incomplete-only true|false  Launch only candidates missing fit or forecast manifests.
  --skip-phase118-check true|false
                                Skip the Phase 118 EXIT_CODE=0 check.
  --dry-run true|false          Prepare chunks and print commands without launching.
  --foreground true|false       Run chunks sequentially in current shell; mainly for debugging.
  --help                        Show this message.
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
shard="exal_high_priority"
workers="8"
n_cores_per_worker="1"
readiness_dir="${repo_root}/application/cache/joint_qdesn_phase119_case_specific_calibration_readiness_20260709"
screening_output_dir="${repo_root}/application/cache/joint_qdesn_vb_case_specific_screening_phase119_20260709"
fixture_dir="${repo_root}/application/cache/joint_qdesn_simulation_dgp_fixtures_20260706"
phase118_log="${repo_root}/application/cache/joint_qdesn_phase118_exal_tail_screen_20260709_tmux.log"
session_prefix=""
run_id=""
incomplete_only="true"
skip_phase118_check="false"
dry_run="false"
foreground="false"

bool_value() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true|t|1|yes|y) printf 'true' ;;
    false|f|0|no|n) printf 'false' ;;
    *) echo "Expected boolean value, got '$1'." >&2; exit 2 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --shard) shard="$2"; shift 2 ;;
    --workers) workers="$2"; shift 2 ;;
    --n-cores-per-worker) n_cores_per_worker="$2"; shift 2 ;;
    --readiness-dir) readiness_dir="$2"; shift 2 ;;
    --screening-output-dir) screening_output_dir="$2"; shift 2 ;;
    --fixture-dir) fixture_dir="$2"; shift 2 ;;
    --phase118-log) phase118_log="$2"; shift 2 ;;
    --session-prefix) session_prefix="$2"; shift 2 ;;
    --run-id) run_id="$2"; shift 2 ;;
    --incomplete-only) incomplete_only="$(bool_value "$2")"; shift 2 ;;
    --skip-phase118-check) skip_phase118_check="$(bool_value "$2")"; shift 2 ;;
    --dry-run) dry_run="$(bool_value "$2")"; shift 2 ;;
    --foreground) foreground="$(bool_value "$2")"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "${repo_root}"

readiness_dir="$(realpath -m "${readiness_dir}")"
screening_output_dir="$(realpath -m "${screening_output_dir}")"
fixture_dir="$(realpath -m "${fixture_dir}")"
phase118_log="$(realpath -m "${phase118_log}")"

case "${shard}" in
  high_priority|exal_high_priority|al_high_priority|moderate_priority|context_priority) ;;
  *) echo "Unknown Phase 119 shard '${shard}'." >&2; exit 2 ;;
esac

if ! [[ "${workers}" =~ ^[0-9]+$ ]] || [ "${workers}" -lt 1 ]; then
  echo "--workers must be a positive integer." >&2
  exit 2
fi
if ! [[ "${n_cores_per_worker}" =~ ^[0-9]+$ ]] || [ "${n_cores_per_worker}" -lt 1 ]; then
  echo "--n-cores-per-worker must be a positive integer." >&2
  exit 2
fi

registry_path="${readiness_dir}/phase119_${shard}_registry.csv"
canonical_output_dir="${screening_output_dir}/${shard}"
if [ -z "${run_id}" ]; then
  run_id="$(date +%Y%m%d_%H%M%S)"
fi
if [ -z "${session_prefix}" ]; then
  session_prefix="joint_qdesn_phase119_${shard}_${run_id}"
fi
worker_root="${canonical_output_dir}/parallel_${run_id}"
chunk_dir="${worker_root}/chunks"
log_dir="${worker_root}/logs"
runner_dir="${worker_root}/runners"

if [ ! -d "${readiness_dir}" ]; then
  echo "Missing readiness directory: ${readiness_dir}" >&2
  exit 2
fi
if [ ! -f "${registry_path}" ]; then
  echo "Missing Phase 119 registry shard: ${registry_path}" >&2
  exit 2
fi
if [ ! -d "${fixture_dir}" ]; then
  echo "Missing fixture directory: ${fixture_dir}" >&2
  exit 2
fi
if [ "${skip_phase118_check}" != "true" ]; then
  if [ ! -f "${phase118_log}" ]; then
    echo "Missing Phase 118 log: ${phase118_log}" >&2
    exit 2
  fi
  if ! grep -Fq "EXIT_CODE=0" "${phase118_log}"; then
    echo "Phase 118 log does not contain EXIT_CODE=0: ${phase118_log}" >&2
    exit 2
  fi
fi

mkdir -p "${chunk_dir}" "${log_dir}" "${runner_dir}" "${canonical_output_dir}"

Rscript --vanilla - "${registry_path}" "${chunk_dir}" "${workers}" "${incomplete_only}" <<'RS'
args <- commandArgs(TRUE)
registry_path <- args[[1L]]
chunk_dir <- args[[2L]]
workers <- as.integer(args[[3L]])
incomplete_only <- identical(tolower(args[[4L]]), "true")
registry <- utils::read.csv(registry_path, stringsAsFactors = FALSE)
fit_done <- file.exists(file.path(registry$fit_dir, "artifact_manifest.csv"))
forecast_done <- file.exists(file.path(registry$forecast_dir, "artifact_manifest.csv"))
registry$phase119_fit_manifest_exists <- fit_done
registry$phase119_forecast_manifest_exists <- forecast_done
registry$phase119_complete <- fit_done & forecast_done
selected <- if (incomplete_only) registry[!registry$phase119_complete, , drop = FALSE] else registry
workers <- min(workers, max(1L, nrow(selected)))
chunk_manifest <- data.frame(
  chunk_id = character(),
  chunk_path = character(),
  n_candidates = integer(),
  first_candidate_id = character(),
  last_candidate_id = character(),
  stringsAsFactors = FALSE
)
if (nrow(selected)) {
  split_id <- ((seq_len(nrow(selected)) - 1L) %% workers) + 1L
  for (ii in seq_len(workers)) {
    chunk <- selected[split_id == ii, , drop = FALSE]
    if (!nrow(chunk)) next
    chunk_id <- sprintf("chunk_%02d", ii)
    path <- file.path(chunk_dir, paste0(chunk_id, "_candidate_ids.txt"))
    writeLines(chunk$candidate_id, path, useBytes = TRUE)
    chunk_manifest <- rbind(
      chunk_manifest,
      data.frame(
        chunk_id = chunk_id,
        chunk_path = normalizePath(path, mustWork = TRUE),
        n_candidates = nrow(chunk),
        first_candidate_id = chunk$candidate_id[[1L]],
        last_candidate_id = chunk$candidate_id[[nrow(chunk)]],
        stringsAsFactors = FALSE
      )
    )
  }
}
utils::write.csv(
  data.frame(
    registry_path = normalizePath(registry_path, mustWork = TRUE),
    total_registry_rows = nrow(registry),
    complete_before_launch = sum(registry$phase119_complete),
    incomplete_before_launch = sum(!registry$phase119_complete),
    selected_rows = nrow(selected),
    requested_workers = as.integer(args[[3L]]),
    launched_chunks = nrow(chunk_manifest),
    incomplete_only = incomplete_only,
    stringsAsFactors = FALSE
  ),
  file.path(chunk_dir, "chunk_plan_summary.csv"),
  row.names = FALSE
)
utils::write.csv(chunk_manifest, file.path(chunk_dir, "chunk_manifest.csv"), row.names = FALSE)
RS

chunk_manifest="${chunk_dir}/chunk_manifest.csv"
chunk_summary="${chunk_dir}/chunk_plan_summary.csv"
if [ ! -f "${chunk_manifest}" ]; then
  echo "Failed to create chunk manifest." >&2
  exit 2
fi

printf 'repo_root=%s\n' "${repo_root}"
printf 'shard=%s\n' "${shard}"
printf 'registry=%s\n' "${registry_path}"
printf 'canonical_output_dir=%s\n' "${canonical_output_dir}"
printf 'worker_root=%s\n' "${worker_root}"
printf 'fixture_dir=%s\n' "${fixture_dir}"
printf 'workers_requested=%s\n' "${workers}"
printf 'n_cores_per_worker=%s\n' "${n_cores_per_worker}"
printf 'incomplete_only=%s\n' "${incomplete_only}"
cat "${chunk_summary}"
printf '\n'

mapfile -t chunk_rows < <(Rscript --vanilla - "${chunk_manifest}" <<'RS'
args <- commandArgs(TRUE)
x <- utils::read.csv(args[[1L]], stringsAsFactors = FALSE)
if (!nrow(x)) quit(status = 0)
for (ii in seq_len(nrow(x))) {
  cat(sprintf("%s\t%s\t%d\n", x$chunk_id[[ii]], x$chunk_path[[ii]], x$n_candidates[[ii]]))
}
RS
)

if [ "${#chunk_rows[@]}" -eq 0 ]; then
  echo "No candidate rows need launching for shard '${shard}'."
  exit 0
fi

for row in "${chunk_rows[@]}"; do
  IFS=$'\t' read -r chunk_id chunk_path n_candidates <<< "${row}"
  candidate_ids="$(paste -sd, "${chunk_path}")"
  worker_out_dir="${worker_root}/${chunk_id}"
  worker_log="${log_dir}/${chunk_id}.log"
  worker_runner="${runner_dir}/${chunk_id}.sh"
  session_name="${session_prefix}_${chunk_id}"
  mkdir -p "${worker_out_dir}" "$(dirname "${worker_log}")"
  run_command=(
    Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R
    --registry "${registry_path}"
    --output-dir "${worker_out_dir}"
    --fixture-dir "${fixture_dir}"
    --candidate-ids "${candidate_ids}"
    --n-cores "${n_cores_per_worker}"
    --reuse-completed true
    --audit-only false
  )
  printf 'chunk=%s n_candidates=%s session=%s log=%s\n' "${chunk_id}" "${n_candidates}" "${session_name}" "${worker_log}"
  printf 'command='
  printf '%q ' "${run_command[@]}"
  printf '\n'
  cat > "${worker_runner}" <<RUNNER
#!/usr/bin/env bash
set -u
cd "$(printf '%q' "${repo_root}")" || exit 1
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1
{
  echo "START \$(date -Is)"
  printf 'SHARD=%s\n' "$(printf '%q' "${shard}")"
  printf 'CHUNK_ID=%s\n' "$(printf '%q' "${chunk_id}")"
  printf 'N_CANDIDATES=%s\n' "$(printf '%q' "${n_candidates}")"
  printf 'REGISTRY=%s\n' "$(printf '%q' "${registry_path}")"
  printf 'OUTPUT_DIR=%s\n' "$(printf '%q' "${worker_out_dir}")"
  printf 'FIXTURE_DIR=%s\n' "$(printf '%q' "${fixture_dir}")"
  $(printf '%q ' "${run_command[@]}")
  ec=\$?
  echo "EXIT_CODE=\${ec}"
  echo "END \$(date -Is)"
  exit "\${ec}"
} > "$(printf '%q' "${worker_log}")" 2>&1
RUNNER
  chmod +x "${worker_runner}"
  if [ "${dry_run}" = "true" ]; then
    continue
  fi
  if [ "${foreground}" = "true" ]; then
    bash "${worker_runner}"
  else
    if ! command -v tmux >/dev/null 2>&1; then
      echo "tmux is required for detached launch; rerun with --foreground true." >&2
      exit 2
    fi
    if tmux has-session -t "${session_name}" 2>/dev/null; then
      echo "tmux session already exists: ${session_name}" >&2
      exit 2
    fi
    tmux new-session -d -s "${session_name}" "bash $(printf '%q' "${worker_runner}")"
  fi
done

cat <<AUDIT

After all worker sessions finish, build the canonical shard audit with:

Rscript application/scripts/106_run_joint_qdesn_vb_spec_screening.R \\
  --registry ${registry_path} \\
  --output-dir ${canonical_output_dir} \\
  --fixture-dir ${fixture_dir} \\
  --n-cores ${n_cores_per_worker} \\
  --reuse-completed true \\
  --audit-only true

Worker root:
${worker_root}
AUDIT
