#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "${repo_root}"

freeze_dir="application/cache/joint_qdesn_phase156b_collapsed_gamma_sigma_recovery_freeze_20260802"
output_dir="application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802"
orchestration_dir="application/cache/joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802_orchestration"
preflight_dir="local_trackers/joint_exqdesn_phase157b_worker_preflight_20260802"
session_name="joint_exqdesn_phase157b_collapsed_20260802"
requested_parallel="24"
reserve_cores="16"
min_parallel="8"
min_memory_gib="64"
min_disk_gib="10"
execute="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --freeze-dir) freeze_dir="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --orchestration-dir) orchestration_dir="$2"; shift 2 ;;
    --preflight-dir) preflight_dir="$2"; shift 2 ;;
    --session-name) session_name="$2"; shift 2 ;;
    --max-parallel) requested_parallel="$2"; shift 2 ;;
    --reserve-cores) reserve_cores="$2"; shift 2 ;;
    --min-parallel) min_parallel="$2"; shift 2 ;;
    --min-memory-gib) min_memory_gib="$2"; shift 2 ;;
    --min-disk-gib) min_disk_gib="$2"; shift 2 ;;
    --execute) execute="true"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

freeze_dir="$(realpath "${freeze_dir}")"
preflight_dir="$(realpath "${preflight_dir}")"
output_dir="$(realpath -m "${output_dir}")"
orchestration_dir="$(realpath -m "${orchestration_dir}")"

if [[ ! -f "${freeze_dir}/artifact_manifest.csv" ]]; then
  echo "Missing Phase156b freeze manifest: ${freeze_dir}" >&2
  exit 1
fi
if [[ ! -f "${preflight_dir}/preflight_assessment.csv" ]]; then
  echo "Missing Phase157b worker-lifecycle preflight: ${preflight_dir}" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "Phase157b launch requires a clean committed task worktree." >&2
  git status --short >&2
  exit 1
fi
if tmux has-session -t "${session_name}" 2>/dev/null; then
  echo "tmux session already exists: ${session_name}" >&2
  exit 1
fi
if [[ -e "${orchestration_dir}/abort_after_worker_failure" ]]; then
  echo "An abort sentinel already exists in ${orchestration_dir}; use a fresh orchestration directory." >&2
  exit 1
fi
if [[ -e "${orchestration_dir}/phase157b.exit" ]]; then
  echo "A completed/failed controller receipt already exists in ${orchestration_dir}; use a fresh directory." >&2
  exit 1
fi

Rscript --vanilla - "${freeze_dir}" "${preflight_dir}" "$(git rev-parse HEAD)" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
verify_manifest <- function(dir) {
  manifest <- read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE, check.names = FALSE)
  if (!nrow(manifest) || !all(c("relative_path", "sha256") %in% names(manifest))) stop("Malformed manifest: ", dir)
  paths <- file.path(dir, manifest$relative_path)
  if (any(!file.exists(paths))) stop("Manifest paths are missing: ", dir)
  actual <- unname(tools::sha256sum(paths))
  if (any(actual != manifest$sha256)) stop("Manifest hash failure: ", dir)
  TRUE
}
verify_manifest(args[[1L]])
verify_manifest(args[[2L]])
assessment <- read.csv(file.path(args[[2L]], "preflight_assessment.csv"), stringsAsFactors = FALSE)
if (nrow(assessment) != 1L || assessment$gate_status[[1L]] != "pass") stop("Phase157b preflight gate is not pass.")
source_commit <- read.csv(file.path(args[[1L]], "source_commit.csv"), stringsAsFactors = FALSE)
if (nrow(source_commit) != 1L || source_commit$git_head[[1L]] != args[[3L]] || !isTRUE(source_commit$worktree_clean[[1L]])) {
  stop("Phase156b source commit does not match the clean launch commit.")
}
plan <- read.csv(file.path(args[[1L]], "chain_plan.csv"), stringsAsFactors = FALSE)
if (nrow(plan) != 64L || length(unique(plan$scenario_id)) != 8L || anyDuplicated(plan$worker_id) || anyDuplicated(plan$chain_seed)) {
  stop("Phase156b launch plan is not the expected 64-worker/8-scenario packet.")
}
RS

nproc_total="$(nproc)"
active_equiv="$(ps -eo comm=,pcpu= | awk '$1 ~ /^(R|Rscript)$/ {sum += $2} END {printf "%d", (sum + 99) / 100}')"
available=$(( nproc_total - reserve_cores - active_equiv ))
if (( available < min_parallel )); then
  echo "Insufficient launch capacity: total=${nproc_total}, active_R=${active_equiv}, reserve=${reserve_cores}, available=${available}, minimum=${min_parallel}." >&2
  exit 1
fi
parallel="${requested_parallel}"
if (( parallel > available )); then parallel="${available}"; fi
if (( parallel < 1 )); then parallel=1; fi

available_memory_kib="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
available_memory_gib=$(( available_memory_kib / 1024 / 1024 ))
output_parent="$(dirname "${output_dir}")"
available_disk_kib="$(df -Pk "${output_parent}" | awk 'NR == 2 {print $4}')"
available_disk_gib=$(( available_disk_kib / 1024 / 1024 ))
if (( available_memory_gib < min_memory_gib )); then
  echo "Insufficient memory for Phase157b admission: available=${available_memory_gib} GiB, minimum=${min_memory_gib} GiB." >&2
  exit 1
fi
if (( available_disk_gib < min_disk_gib )); then
  echo "Insufficient disk for Phase157b admission: available=${available_disk_gib} GiB, minimum=${min_disk_gib} GiB." >&2
  exit 1
fi

mkdir -p "${orchestration_dir}/worker_logs" "${orchestration_dir}/failures" \
  "${orchestration_dir}/running" "${orchestration_dir}/skipped"

worker_ids="${orchestration_dir}/worker_ids.txt"
Rscript --vanilla - "${freeze_dir}/chain_plan.csv" "${worker_ids}" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
x <- read.csv(args[[1L]], stringsAsFactors = FALSE)
writeLines(as.character(x$worker_id), args[[2L]])
RS

abort_file="${orchestration_dir}/abort_after_worker_failure"
worker_wrapper="${orchestration_dir}/phase157b_worker_wrapper.sh"
cat > "${worker_wrapper}" <<EOF
#!/usr/bin/env bash
set -u
id="\$1"
if [[ -e $(printf '%q' "${abort_file}") ]]; then
  printf 'worker_id,state,timestamp\n%s,skipped_after_abort,%s\n' "\${id}" "\$(date -Is)" > $(printf '%q' "${orchestration_dir}/skipped")/worker_\$(printf '%03d' "\${id}").csv
  exit 75
fi
log=$(printf '%q' "${orchestration_dir}/worker_logs")/worker_\$(printf '%03d' "\${id}").log
state=$(printf '%q' "${orchestration_dir}/running")/worker_\$(printf '%03d' "\${id}").csv
OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 \
  Rscript application/scripts/190_run_joint_exqdesn_phase157_chain.R \
    --freeze-dir $(printf '%q' "${freeze_dir}") \
    --worker-id "\${id}" \
    --reuse-completed true \
    --failure-dir $(printf '%q' "${orchestration_dir}/failures") > "\${log}" 2>&1 &
pid=\$!
printf 'worker_id,pid,started_at\n%s,%s,%s\n' "\${id}" "\${pid}" "\$(date -Is)" > "\${state}"
wait "\${pid}"
code=\$?
rm -f "\${state}"
if [[ "\${code}" -ne 0 ]]; then
  (set -o noclobber; printf 'worker_id,exit_code,timestamp\n%s,%s,%s\n' "\${id}" "\${code}" "\$(date -Is)" > $(printf '%q' "${abort_file}")) 2>/dev/null || true
fi
exit "\${code}"
EOF
chmod +x "${worker_wrapper}"

wrapper="${orchestration_dir}/phase157b_controller.sh"
main_log="${orchestration_dir}/phase157b_tmux.log"
exit_file="${orchestration_dir}/phase157b.exit"
cat > "${wrapper}" <<EOF
#!/usr/bin/env bash
set -u
cd $(printf '%q' "${repo_root}")
echo "PHASE157B_START=\$(date -Is)"
set +e
cat $(printf '%q' "${worker_ids}") | xargs -P $(printf '%q' "${parallel}") -I '{}' $(printf '%q' "${worker_wrapper}") '{}'
worker_code=\$?
echo "PHASE157B_WORKERS_EXIT=\${worker_code}"
if [[ "\${worker_code}" -eq 0 ]]; then
  Rscript application/scripts/193_finalize_joint_exqdesn_phase157_collapsed_gamma_sigma.R \
    --freeze-dir $(printf '%q' "${freeze_dir}") \
    --output-dir $(printf '%q' "${output_dir}")
  code=\$?
else
  code=\${worker_code}
fi
echo "\${code}" > $(printf '%q' "${exit_file}")
echo "PHASE157B_END=\$(date -Is) EXIT=\${code}"
exit "\${code}"
EOF
chmod +x "${wrapper}"

Rscript --vanilla - "${orchestration_dir}" "${freeze_dir}" "${output_dir}" "${preflight_dir}" \
  "${session_name}" "${nproc_total}" "${active_equiv}" "${reserve_cores}" \
  "${requested_parallel}" "${parallel}" "$(git rev-parse HEAD)" \
  "${available_memory_gib}" "${min_memory_gib}" "${available_disk_gib}" "${min_disk_gib}" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
plan <- data.frame(
  freeze_dir = args[[2L]], output_dir = args[[3L]], preflight_dir = args[[4L]],
  session_name = args[[5L]], host_logical_cores = as.integer(args[[6L]]),
  active_R_core_equivalents_at_launch = as.integer(args[[7L]]),
  reserved_cores = as.integer(args[[8L]]), requested_parallel = as.integer(args[[9L]]),
  selected_parallel = as.integer(args[[10L]]), source_git_head = args[[11L]],
  available_memory_gib = as.integer(args[[12L]]), minimum_memory_gib = as.integer(args[[13L]]),
  available_disk_gib = as.integer(args[[14L]]), minimum_disk_gib = as.integer(args[[15L]]),
  fail_fast_admission = TRUE, nested_threads = 1L, stringsAsFactors = FALSE
)
write.csv(plan, file.path(args[[1L]], "launch_resource_plan.csv"), row.names = FALSE)
writeLines(c(
  "# Phase157b orchestration", "",
  "This controller requires a verified real-fixture worker preflight and a clean source commit.",
  "A worker failure creates an abort sentinel: active jobs drain, while queued jobs are skipped.",
  sprintf("- Session: `%s`", plan$session_name),
  sprintf("- Selected parallel workers: %d", plan$selected_parallel),
  sprintf("- Reserved logical cores: %d", plan$reserved_cores),
  sprintf("- Available/minimum memory: %d/%d GiB", plan$available_memory_gib, plan$minimum_memory_gib),
  sprintf("- Available/minimum disk: %d/%d GiB", plan$available_disk_gib, plan$minimum_disk_gib),
  sprintf("- Source commit: `%s`", plan$source_git_head)
), file.path(args[[1L]], "README.md"))
paths <- c(
  "launch_resource_plan.csv", "README.md", "phase157b_controller.sh",
  "phase157b_worker_wrapper.sh", "worker_ids.txt"
)
full <- file.path(args[[1L]], paths)
manifest <- data.frame(
  label = sub("\\..*$", "", paths), relative_path = paths,
  size_bytes = file.info(full)$size,
  sha256 = unname(tools::sha256sum(full)), stringsAsFactors = FALSE
)
write.csv(manifest, file.path(args[[1L]], "artifact_manifest.csv"), row.names = FALSE)
RS

if [[ "${execute}" != "true" ]]; then
  echo "Prepared verified Phase157b launch. Add --execute to start it."
  echo "Selected parallel workers: ${parallel}"
  echo "Controller: ${wrapper}"
  exit 0
fi

tmux new-session -d -s "${session_name}" "${wrapper} > $(printf '%q' "${main_log}") 2>&1"
echo "Launched ${session_name} with ${parallel} concurrent chain workers."
echo "Log: ${main_log}"
echo "Output: ${output_dir}"
