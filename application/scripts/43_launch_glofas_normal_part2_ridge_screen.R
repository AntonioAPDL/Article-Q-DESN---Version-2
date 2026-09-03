#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))

args <- app_parse_args(list(
  runtime_root = "",
  workers = "20",
  session_label = "",
  poll_seconds = "300",
  retain_detail = "false"
))

if (!nzchar(Sys.which("tmux"))) stop("tmux is required for background launch.", call. = FALSE)

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
manifest_path <- file.path(runtime_root, "configs", "candidate_manifest.csv")
manifest <- app_read_csv(manifest_path)
workers <- as.integer(args$workers)
poll_seconds <- as.integer(args$poll_seconds)
retain_detail <- tolower(as.character(args$retain_detail)[[1L]])
if (!is.finite(workers) || workers < 1L) stop("--workers must be a positive integer.", call. = FALSE)
if (!is.finite(poll_seconds) || poll_seconds < 30L) {
  stop("--poll_seconds must be at least 30.", call. = FALSE)
}
if (!retain_detail %in% c("true", "false", "t", "f", "1", "0", "yes", "no")) {
  stop("--retain_detail must be true or false.", call. = FALSE)
}

session_label <- as.character(args$session_label)[[1L]]
if (!nzchar(session_label)) session_label <- basename(runtime_root)
session_label <- gsub("[^A-Za-z0-9_.-]", "_", session_label)
scheduler_session <- paste0(session_label, "_scheduler")
watch_session <- paste0(session_label, "_watch")

tmux_has_session <- function(session) {
  identical(
    system2("tmux", c("has-session", "-t", session), stdout = FALSE, stderr = FALSE),
    0L
  )
}
command_status <- function(x) {
  as.integer(attr(x, "status") %||% 0L)
}
if (tmux_has_session(scheduler_session)) {
  stop(sprintf("tmux session already exists: %s", scheduler_session), call. = FALSE)
}
if (tmux_has_session(watch_session)) {
  stop(sprintf("tmux session already exists: %s", watch_session), call. = FALSE)
}

closeout_log <- file.path(runtime_root, "logs", "scheduler_closeout.log")
watch_log <- file.path(runtime_root, "logs", "watch.log")
scheduler_script <- file.path(runtime_root, "configs", "run_sharded_worker_pool.sh")
watch_script <- file.path(runtime_root, "configs", "watch_health.sh")

worker_lines <- vapply(seq_len(workers), function(i) {
  log_i <- file.path(runtime_root, "logs", sprintf("worker_%02d.log", i))
  sprintf(
    "(Rscript application/scripts/41_run_glofas_normal_part2_ridge_worker.R --runtime_root %s --worker_index %d --total_workers %d --retain_detail %s >> %s 2>&1 || true) &",
    shQuote(runtime_root),
    i,
    workers,
    shQuote(retain_detail),
    shQuote(log_i)
  )
}, character(1L))
worker_script <- paste(
  "set -euo pipefail",
  sprintf("cd %s", shQuote(repo_root)),
  "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1",
  paste(worker_lines, collapse = "\n"),
  "wait",
  sprintf(
    "Rscript application/scripts/42_check_glofas_normal_part2_ridge_screen.R --runtime_root %s >> %s 2>&1",
    shQuote(runtime_root),
    shQuote(closeout_log)
  ),
  sep = "\n"
)
watch_script_text <- paste(
  "set -euo pipefail",
  sprintf("cd %s", shQuote(repo_root)),
  sprintf(
    "while true; do date; Rscript application/scripts/42_check_glofas_normal_part2_ridge_screen.R --runtime_root %s; sleep %d; done >> %s 2>&1",
    shQuote(runtime_root),
    poll_seconds,
    shQuote(watch_log)
  ),
  sep = "\n"
)
writeLines(worker_script, scheduler_script)
writeLines(watch_script_text, watch_script)
Sys.chmod(c(scheduler_script, watch_script), mode = "0755")

status_scheduler <- system2(
  "tmux",
  c("new-session", "-d", "-s", scheduler_session, "bash", scheduler_script),
  stdout = TRUE,
  stderr = TRUE
)
if (!identical(command_status(status_scheduler), 0L)) {
  stop(
    sprintf("Failed to launch scheduler tmux session: %s", paste(status_scheduler, collapse = "\n")),
    call. = FALSE
  )
}
status_watch <- system2(
  "tmux",
  c("new-session", "-d", "-s", watch_session, "bash", watch_script),
  stdout = TRUE,
  stderr = TRUE
)
if (!identical(command_status(status_watch), 0L)) {
  stop(
    sprintf("Failed to launch watch tmux session: %s", paste(status_watch, collapse = "\n")),
    call. = FALSE
  )
}

launch <- data.frame(
  runtime_root = runtime_root,
  total_candidates = nrow(manifest),
  workers = workers,
  scheduler_session = scheduler_session,
  watch_session = watch_session,
  scheduler_script = scheduler_script,
  watch_script = watch_script,
  watch_log = watch_log,
  closeout_log = closeout_log,
  retain_detail = retain_detail,
  launched_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  git_head = app_git_sha(short = FALSE),
  stringsAsFactors = FALSE
)
app_write_csv(launch, file.path(runtime_root, "configs", "launch_manifest.csv"))
print(launch)
