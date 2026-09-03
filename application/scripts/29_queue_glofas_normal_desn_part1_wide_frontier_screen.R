#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  current_runtime_root = "local_trackers/runtime_configs/glofas_normal_part1_ridge_n300_1000_20260901",
  next_runtime_root = "",
  workers = "20",
  poll_seconds = "300",
  queue_session_label = "",
  next_session_label = "",
  allow_current_failures = "false"
))

if (!nzchar(Sys.which("tmux"))) stop("tmux is required for deferred launch.", call. = FALSE)

current_runtime_root <- app_resolve_path(args$current_runtime_root, must_work = TRUE)
next_runtime_root <- app_resolve_path(args$next_runtime_root, must_work = TRUE)
workers <- as.integer(args$workers)
poll_seconds <- as.integer(args$poll_seconds)
allow_current_failures <- app_as_bool(args$allow_current_failures)
if (!is.finite(workers) || workers < 1L) stop("--workers must be positive.", call. = FALSE)
if (!is.finite(poll_seconds) || poll_seconds < 30L) stop("--poll_seconds must be at least 30.", call. = FALSE)

queue_session_label <- as.character(args$queue_session_label)[[1L]]
if (!nzchar(queue_session_label)) queue_session_label <- paste0(basename(next_runtime_root), "_queue")
queue_session_label <- gsub("[^A-Za-z0-9_.-]", "_", queue_session_label)
next_session_label <- as.character(args$next_session_label)[[1L]]
if (!nzchar(next_session_label)) next_session_label <- basename(next_runtime_root)
next_session_label <- gsub("[^A-Za-z0-9_.-]", "_", next_session_label)

tmux_has_session <- function(session) {
  identical(system2("tmux", c("has-session", "-t", session), stdout = FALSE, stderr = FALSE), 0L)
}
command_status <- function(x) as.integer(attr(x, "status") %||% 0L)
if (tmux_has_session(queue_session_label)) {
  stop(sprintf("tmux session already exists: %s", queue_session_label), call. = FALSE)
}

current_manifest <- file.path(current_runtime_root, "configs", "candidate_manifest.csv")
next_manifest <- file.path(next_runtime_root, "configs", "candidate_manifest.csv")
if (!file.exists(current_manifest)) stop(sprintf("Missing current manifest: %s", current_manifest), call. = FALSE)
if (!file.exists(next_manifest)) stop(sprintf("Missing next manifest: %s", next_manifest), call. = FALSE)

queue_log <- file.path(next_runtime_root, "logs", "deferred_launch_queue.log")
queue_script <- file.path(next_runtime_root, "configs", "deferred_launch_queue.sh")

queue_text <- paste(
  "set -euo pipefail",
  sprintf("cd %s", shQuote(repo_root)),
  "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1",
  sprintf("current_root=%s", shQuote(current_runtime_root)),
  sprintf("next_root=%s", shQuote(next_runtime_root)),
  sprintf("workers=%d", workers),
  sprintf("poll_seconds=%d", poll_seconds),
  sprintf("allow_current_failures=%s", shQuote(tolower(as.character(allow_current_failures)))),
  sprintf("next_session_label=%s", shQuote(next_session_label)),
  sprintf("log=%s", shQuote(queue_log)),
  "current_manifest=\"$current_root/configs/candidate_manifest.csv\"",
  "status_dir=\"$current_root/status\"",
  "total=$(tail -n +2 \"$current_manifest\" | wc -l | tr -d ' ')",
  "echo \"[$(date)] deferred queue started; waiting on $current_root; total=$total\" >> \"$log\"",
  "while true; do",
  "  done_count=$(find \"$status_dir\" -type f -name '*.done' 2>/dev/null | wc -l | tr -d ' ')",
  "  failed_count=$(find \"$status_dir\" -type f -name '*.failed' 2>/dev/null | wc -l | tr -d ' ')",
  "  running_count=$(find \"$status_dir\" -type f -name '*.running' 2>/dev/null | wc -l | tr -d ' ')",
  "  pending_count=$(( total - done_count - failed_count - running_count ))",
  "  if [ \"$pending_count\" -lt 0 ]; then pending_count=0; fi",
  "  echo \"[$(date)] current done=$done_count running=$running_count pending=$pending_count failed=$failed_count\" >> \"$log\"",
  "  if [ \"$failed_count\" -gt 0 ] && [ \"$allow_current_failures\" != \"true\" ]; then",
  "    echo \"[$(date)] aborting deferred launch because current run has failures\" >> \"$log\"",
  "    exit 2",
  "  fi",
  "  if [ $(( done_count + failed_count )) -ge \"$total\" ] && [ \"$running_count\" -eq 0 ]; then",
  "    break",
  "  fi",
  "  sleep \"$poll_seconds\"",
  "done",
  "echo \"[$(date)] current run complete; refreshing current health\" >> \"$log\"",
  "Rscript application/scripts/26_check_glofas_normal_desn_part1_ridge_screen.R --runtime_root \"$current_root\" >> \"$log\" 2>&1",
  "echo \"[$(date)] launching wide-frontier run $next_root with $workers workers\" >> \"$log\"",
  "Rscript application/scripts/27_launch_glofas_normal_desn_part1_ridge_screen.R --runtime_root \"$next_root\" --workers \"$workers\" --session_label \"$next_session_label\" --poll_seconds \"$poll_seconds\" >> \"$log\" 2>&1",
  "echo \"[$(date)] deferred queue completed launch request\" >> \"$log\"",
  sep = "\n"
)
writeLines(queue_text, queue_script)
Sys.chmod(queue_script, mode = "0755")

queue_manifest <- data.frame(
  current_runtime_root = current_runtime_root,
  next_runtime_root = next_runtime_root,
  workers = workers,
  poll_seconds = poll_seconds,
  queue_session = queue_session_label,
  next_session_label = next_session_label,
  allow_current_failures = allow_current_failures,
  queue_script = queue_script,
  queue_log = queue_log,
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  git_head = app_git_sha(short = FALSE),
  stringsAsFactors = FALSE
)
app_write_csv(queue_manifest, file.path(next_runtime_root, "configs", "deferred_launch_manifest.csv"))

status <- system2(
  "tmux",
  c("new-session", "-d", "-s", queue_session_label, "bash", queue_script),
  stdout = TRUE,
  stderr = TRUE
)
if (!identical(command_status(status), 0L)) {
  stop(sprintf("Failed to launch deferred queue: %s", paste(status, collapse = "\n")), call. = FALSE)
}
print(queue_manifest)
