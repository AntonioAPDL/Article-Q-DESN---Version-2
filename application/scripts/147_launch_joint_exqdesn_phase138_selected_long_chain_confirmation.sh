#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

phase137_dir="application/cache/joint_qdesn_phase137_exal_gamma_kernel_readiness_20260716"
orchestration_dir="application/cache/joint_qdesn_phase138_selected_long_chain_confirmation_20260716_orchestration"
session_name="joint_qdesn_phase138_selected_long_chain_20260716"
prepare_only="false"
execute_mode="false"
allow_existing="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase137-dir)
      phase137_dir="$2"
      shift 2
      ;;
    --orchestration-dir)
      orchestration_dir="$2"
      shift 2
      ;;
    --session-name)
      session_name="$2"
      shift 2
      ;;
    --prepare-only)
      prepare_only="$2"
      shift 2
      ;;
    --execute)
      execute_mode="true"
      shift
      ;;
    --allow-existing)
      allow_existing="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

cd "$repo_root"
mkdir -p "$orchestration_dir"

phase137_abs="$(cd "$(dirname "$phase137_dir")" && pwd)/$(basename "$phase137_dir")"
orchestration_abs="$(cd "$orchestration_dir" && pwd)"

prepare_jobs() {
  Rscript --vanilla - "$repo_root" "$phase137_abs" "$orchestration_abs" "$allow_existing" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
repo_root <- normalizePath(args[[1L]], mustWork = TRUE)
phase137_dir <- normalizePath(args[[2L]], mustWork = TRUE)
orchestration_dir <- normalizePath(args[[3L]], mustWork = TRUE)
allow_existing <- tolower(args[[4L]]) %in% c("true", "t", "yes", "y", "1")

sha256_file <- function(path) {
  line <- system2("sha256sum", shQuote(path), stdout = TRUE)
  strsplit(line[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
safe_id <- function(x) gsub("[^A-Za-z0-9]+", "_", x)
write_csv <- function(x, path) {
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, mustWork = TRUE)
}

plan_path <- file.path(phase137_dir, "phase137_next_launch_plan.csv")
decision_path <- file.path(phase137_dir, "phase137_decision_summary.csv")
health_path <- file.path(phase137_dir, "phase137_health_summary.csv")
if (!file.exists(plan_path)) stop("Missing Phase137 launch plan: ", plan_path, call. = FALSE)
if (!file.exists(decision_path)) stop("Missing Phase137 decision summary: ", decision_path, call. = FALSE)
if (!file.exists(health_path)) stop("Missing Phase137 health summary: ", health_path, call. = FALSE)

plan <- utils::read.csv(plan_path, stringsAsFactors = FALSE, check.names = FALSE)
decision <- utils::read.csv(decision_path, stringsAsFactors = FALSE, check.names = FALSE)
health <- utils::read.csv(health_path, stringsAsFactors = FALSE, check.names = FALSE)
required <- c("launch_group_id", "phase136_variant_id", "n_cases", "total_chain_jobs",
              "mcmc_n_iter", "n_cores", "output_dir", "command")
missing <- setdiff(required, names(plan))
if (length(missing)) stop("Phase137 launch plan missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
if (!identical(decision$phase137_decision[[1L]], "review_ready_for_selected_long_chain_confirmation")) {
  stop("Phase137 decision is not launch-ready: ", decision$phase137_decision[[1L]], call. = FALSE)
}
if (any(health$status == "fail")) {
  stop("Phase137 health summary contains hard failures; refusing launch.", call. = FALSE)
}
if (any(as.logical(plan$launched_in_phase137))) {
  stop("Phase137 launch plan unexpectedly marks a group as already launched.", call. = FALSE)
}
ord <- match(plan$launch_group_id, c("selected_bounded_w4", "selected_logit_w4"))
ord[is.na(ord)] <- seq_len(sum(is.na(ord))) + length(ord)
plan <- plan[order(ord, plan$launch_group_id), , drop = FALSE]

blocked <- character()
for (ii in seq_len(nrow(plan))) {
  out <- file.path(repo_root, plan$output_dir[[ii]])
  if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)) && !allow_existing) {
    blocked <- c(blocked, out)
  }
}
if (length(blocked)) {
  stop("Refusing to overwrite non-empty Phase138 output directories: ", paste(blocked, collapse = ", "), call. = FALSE)
}

jobs <- plan
jobs$job_index <- seq_len(nrow(jobs))
jobs$job_id <- sprintf("%02d_%s", jobs$job_index, safe_id(jobs$launch_group_id))
jobs$job_script <- file.path(orchestration_dir, paste0(jobs$job_id, ".sh"))
jobs$stdout_log <- file.path(orchestration_dir, paste0(jobs$job_id, ".stdout.log"))
jobs$time_log <- file.path(orchestration_dir, paste0(jobs$job_id, ".time.log"))
jobs$exit_file <- file.path(orchestration_dir, paste0(jobs$job_id, ".exit"))
jobs$launch_status <- "prepared_not_started"

for (ii in seq_len(nrow(jobs))) {
  lines <- c(
    "#!/usr/bin/env bash",
    "set -u",
    sprintf("cd %s", shQuote(repo_root)),
    sprintf("echo PHASE138_JOB_START=%s", shQuote(jobs$launch_group_id[[ii]])),
    "date -Is",
    "set +e",
    sprintf(
      "/usr/bin/time -v -o %s bash -lc %s > %s 2>&1",
      shQuote(jobs$time_log[[ii]]),
      shQuote(jobs$command[[ii]]),
      shQuote(jobs$stdout_log[[ii]])
    ),
    "code=$?",
    sprintf("echo \"$code\" > %s", shQuote(jobs$exit_file[[ii]])),
    sprintf("echo PHASE138_JOB_EXIT=%s:$code", shQuote(jobs$launch_group_id[[ii]])),
    "date -Is",
    "exit $code"
  )
  writeLines(lines, jobs$job_script[[ii]], useBytes = TRUE)
  Sys.chmod(jobs$job_script[[ii]], mode = "0755")
}

orchestration_plan_path <- write_csv(jobs, file.path(orchestration_dir, "phase138_orchestration_plan.csv"))
readme_path <- file.path(orchestration_dir, "README.md")
writeLines(c(
  "# Phase138 selected long-chain confirmation orchestration",
  "",
  "This directory was generated from the Phase137 readiness launch plan.",
  "The scheduler runs launch groups sequentially to respect current shared-machine load.",
  "",
  sprintf("- Phase137 source: `%s`", phase137_dir),
  sprintf("- Launch groups: `%s`", nrow(jobs)),
  sprintf("- Total chain jobs: `%s`", sum(jobs$total_chain_jobs)),
  sprintf("- MCMC iterations per chain: `%s`", paste(unique(jobs$mcmc_n_iter), collapse = ",")),
  "",
  "The job scripts call the existing Phase136 gamma-kernel runner with selected case/kernel groups.",
  "No article assets are updated by this launcher."
), readme_path, useBytes = TRUE)

manifest_paths <- c(orchestration_plan_path, readme_path, jobs$job_script)
manifest <- data.frame(
  label = c("phase138_orchestration_plan", "readme", paste0("job_script_", jobs$job_id)),
  relative_path = basename(manifest_paths),
  size_bytes = as.numeric(file.info(manifest_paths)$size),
  sha256 = vapply(manifest_paths, sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
manifest_path <- write_csv(manifest, file.path(orchestration_dir, "artifact_manifest.csv"))
cat("Prepared Phase138 orchestration in", orchestration_dir, "\n")
cat("Plan:", orchestration_plan_path, "\n")
cat("Manifest:", manifest_path, "\n")
RS
}

execute_jobs() {
  echo "PHASE138_SCHEDULER_START=$session_name"
  date -Is
  set +e
  mapfile -t job_scripts < <(Rscript --vanilla - "$orchestration_abs" <<'RS'
args <- commandArgs(trailingOnly = TRUE)
plan <- utils::read.csv(file.path(args[[1L]], "phase138_orchestration_plan.csv"), stringsAsFactors = FALSE, check.names = FALSE)
cat(plan$job_script, sep = "\n")
RS
)
  scheduler_code=0
  for job_script in "${job_scripts[@]}"; do
    echo "PHASE138_SCHEDULER_RUNNING=$job_script"
    bash "$job_script"
    job_code=$?
    echo "PHASE138_SCHEDULER_JOB_CODE=$job_code"
    if [[ "$job_code" -ne 0 ]]; then
      scheduler_code="$job_code"
      echo "PHASE138_SCHEDULER_FAIL_FAST=$job_script"
      break
    fi
  done
  echo "$scheduler_code" > "$orchestration_abs/phase138_scheduler.exit"
  echo "PHASE138_SCHEDULER_EXIT=$scheduler_code"
  date -Is
  exit "$scheduler_code"
}

prepare_jobs

if [[ "$execute_mode" == "true" ]]; then
  execute_jobs
fi

if [[ "$prepare_only" == "true" ]]; then
  echo "Prepared only; no tmux session launched."
  exit 0
fi

if tmux has-session -t "$session_name" 2>/dev/null; then
  echo "tmux session already exists: $session_name" >&2
  exit 1
fi

scheduler_log="$orchestration_abs/phase138_scheduler.log"
tmux new-session -d -s "$session_name" "cd '$repo_root' && bash '$script_dir/147_launch_joint_exqdesn_phase138_selected_long_chain_confirmation.sh' --execute --phase137-dir '$phase137_abs' --orchestration-dir '$orchestration_abs' --session-name '$session_name' --allow-existing '$allow_existing' > '$scheduler_log' 2>&1"
echo "Launched Phase138 scheduler tmux session: $session_name"
echo "Scheduler log: $scheduler_log"
