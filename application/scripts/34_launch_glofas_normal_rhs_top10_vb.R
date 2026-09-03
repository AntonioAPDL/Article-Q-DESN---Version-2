#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_normal_rhs_top10_vb_20260901",
  workers = "20",
  session_label = "",
  poll_seconds = "300",
  score_train = "false"
))

if (!nzchar(Sys.which("tmux"))) stop("tmux is required for background launch.", call. = FALSE)

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
workers <- as.integer(args$workers)
poll_seconds <- as.integer(args$poll_seconds)
if (!is.finite(workers) || workers < 1L) stop("--workers must be positive.", call. = FALSE)
if (!is.finite(poll_seconds) || poll_seconds < 30L) stop("--poll_seconds must be at least 30.", call. = FALSE)

session_label <- as.character(args$session_label)[[1L]]
if (!nzchar(session_label)) session_label <- basename(runtime_root)
session_label <- gsub("[^A-Za-z0-9_.-]", "_", session_label)
scheduler_session <- paste0(session_label, "_scheduler")
watch_session <- paste0(session_label, "_watch")

tmux_has_session <- function(session) {
  identical(system2("tmux", c("has-session", "-t", session), stdout = FALSE, stderr = FALSE), 0L)
}
command_status <- function(x) as.integer(attr(x, "status") %||% 0L)
if (tmux_has_session(scheduler_session)) stop(sprintf("tmux session already exists: %s", scheduler_session), call. = FALSE)
if (tmux_has_session(watch_session)) stop(sprintf("tmux session already exists: %s", watch_session), call. = FALSE)

warm_ids_path <- file.path(runtime_root, "configs", "warm_start_candidate_ids.txt")
rhs_ids_path <- file.path(runtime_root, "configs", "rhs_candidate_ids.txt")
if (!file.exists(warm_ids_path)) stop(sprintf("Missing warm-start id list: %s", warm_ids_path), call. = FALSE)
if (!file.exists(rhs_ids_path)) stop(sprintf("Missing RHS id list: %s", rhs_ids_path), call. = FALSE)
warm_ids <- readLines(warm_ids_path, warn = FALSE)
rhs_ids <- readLines(rhs_ids_path, warn = FALSE)

worker_log <- file.path(runtime_root, "logs", "normal_rhs_worker_pool.log")
closeout_log <- file.path(runtime_root, "logs", "normal_rhs_scheduler_closeout.log")
watch_log <- file.path(runtime_root, "logs", "normal_rhs_watch.log")
scheduler_script <- file.path(runtime_root, "configs", "run_normal_rhs_worker_pool.sh")
watch_script <- file.path(runtime_root, "configs", "watch_normal_rhs_health.sh")

warm_workers <- min(workers, length(warm_ids))
worker_script <- paste(
  "set -euo pipefail",
  sprintf("cd %s", shQuote(repo_root)),
  "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1",
  sprintf("runtime_root=%s", shQuote(runtime_root)),
  sprintf("warm_ids=%s", shQuote(warm_ids_path)),
  sprintf("rhs_ids=%s", shQuote(rhs_ids_path)),
  sprintf("worker_log=%s", shQuote(worker_log)),
  sprintf("closeout_log=%s", shQuote(closeout_log)),
  sprintf("score_train=%s", shQuote(tolower(as.character(app_as_bool(args$score_train))))),
  sprintf("echo \"[$(date)] rebuilding %d ridge warm starts with %d workers\" >> \"$worker_log\"", length(warm_ids), warm_workers),
  sprintf(
    "cat \"$warm_ids\" | xargs -r -P %d -I{} sh -c 'Rscript application/scripts/31_run_glofas_normal_rhs_top10_warm_start_worker.R --runtime_root \"$0\" --candidate_id \"$1\" >> \"$0/logs/normal_rhs_worker_pool.log\" 2>&1 || true' \"$runtime_root\" {}",
    warm_workers
  ),
  sprintf("echo \"[$(date)] launching %d Normal RHS/VB fits\" >> \"$worker_log\"", length(rhs_ids)),
  sprintf(
    "cat \"$rhs_ids\" | xargs -r -P %d -I{} sh -c 'Rscript application/scripts/32_run_glofas_normal_rhs_top10_vb_worker.R --runtime_root \"$0\" --rhs_candidate_id \"$1\" --score_train \"$2\" >> \"$0/logs/normal_rhs_worker_pool.log\" 2>&1 || true' \"$runtime_root\" {} \"$score_train\"",
    workers
  ),
  "Rscript application/scripts/33_check_glofas_normal_rhs_top10_vb.R --runtime_root \"$runtime_root\" >> \"$closeout_log\" 2>&1",
  "echo \"[$(date)] Normal RHS/VB scheduler finished\" >> \"$worker_log\"",
  sep = "\n"
)
watch_script_text <- paste(
  "set -euo pipefail",
  sprintf("cd %s", shQuote(repo_root)),
  sprintf("while true; do date; Rscript application/scripts/33_check_glofas_normal_rhs_top10_vb.R --runtime_root %s; sleep %d; done >> %s 2>&1",
          shQuote(runtime_root), poll_seconds, shQuote(watch_log)),
  sep = "\n"
)
writeLines(worker_script, scheduler_script)
writeLines(watch_script_text, watch_script)
Sys.chmod(c(scheduler_script, watch_script), mode = "0755")

status_scheduler <- system2("tmux", c("new-session", "-d", "-s", scheduler_session, "bash", scheduler_script), stdout = TRUE, stderr = TRUE)
if (!identical(command_status(status_scheduler), 0L)) {
  stop(sprintf("Failed to launch scheduler tmux session: %s", paste(status_scheduler, collapse = "\n")), call. = FALSE)
}
status_watch <- system2("tmux", c("new-session", "-d", "-s", watch_session, "bash", watch_script), stdout = TRUE, stderr = TRUE)
if (!identical(command_status(status_watch), 0L)) {
  stop(sprintf("Failed to launch watch tmux session: %s", paste(status_watch, collapse = "\n")), call. = FALSE)
}

launch <- data.frame(
  runtime_root = runtime_root,
  rhs_fits = length(rhs_ids),
  warm_starts = length(warm_ids),
  workers = workers,
  warm_start_workers = warm_workers,
  scheduler_session = scheduler_session,
  watch_session = watch_session,
  scheduler_script = scheduler_script,
  watch_script = watch_script,
  worker_log = worker_log,
  watch_log = watch_log,
  closeout_log = closeout_log,
  launched_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  git_head = app_git_sha(short = FALSE),
  stringsAsFactors = FALSE
)
app_write_csv(launch, file.path(runtime_root, "configs", "launch_manifest.csv"))
print(launch)
