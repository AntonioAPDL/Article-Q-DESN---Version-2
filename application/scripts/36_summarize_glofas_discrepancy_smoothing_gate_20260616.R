#!/usr/bin/env Rscript
# Purpose: summarize health, progress, and candidate ranking for the focused
# GloFAS discrepancy-smoothing p05/p50/p95 gate.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))

args <- app_parse_args(list(
  runtime_dir = "local_trackers/runtime_configs/glofas_discrepancy_smoothing_gate_20260616"
))

runtime_dir <- app_path(args$runtime_dir)
manifest_path <- file.path(runtime_dir, "launch_manifest.csv")
if (!file.exists(manifest_path)) stop(sprintf("Missing launch manifest: %s", manifest_path), call. = FALSE)

read_csv_or_null <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(app_read_csv(path), error = function(e) NULL)
}

stage_state <- function(run_dir) {
  stages <- c(
    "00_check_inputs", "00_audit_input_bundle", "01_build_panel",
    "02_make_input_figures", "03_fit_models", "04_score_models",
    "05_make_outputs", "06_preflight_launch"
  )
  states <- vapply(stages, function(stage) {
    started <- file.exists(file.path(run_dir, "logs", sprintf("%s_started.csv", stage)))
    status_path <- file.path(run_dir, "logs", sprintf("%s_status.csv", stage))
    if (file.exists(status_path)) {
      x <- read_csv_or_null(status_path)
      if (!is.null(x) && nrow(x) && "status" %in% names(x)) return(as.character(utils::tail(x$status, 1L)))
      return("status_empty")
    }
    if (started) return("running")
    "pending"
  }, character(1L))
  idx <- suppressWarnings(max(which(states != "pending"), na.rm = TRUE))
  if (!is.finite(idx)) return(list(stage = "not_started", status = "pending"))
  list(stage = stages[[idx]], status = states[[idx]])
}

session_live <- function(session) {
  sessions <- tryCatch(system("tmux list-sessions 2>/dev/null", intern = TRUE), error = function(e) character())
  any(grepl(as.character(session), sessions, fixed = TRUE))
}

extract_fit <- function(run_dir, qdesn_fit_id) {
  fit <- read_csv_or_null(file.path(run_dir, "tables", "fit_status.csv"))
  out <- list(status = "pending", runtime_min = NA_real_, message = NA_character_)
  if (is.null(fit) || !nrow(fit)) return(out)
  idx <- which(as.character(fit$fit_id) == as.character(qdesn_fit_id))
  row <- if (length(idx)) fit[idx[[1L]], , drop = FALSE] else fit[nrow(fit), , drop = FALSE]
  out$status <- as.character(row$status[[1L]])
  out$message <- as.character(row$message[[1L]])
  if ("runtime_seconds" %in% names(row)) out$runtime_min <- as.numeric(row$runtime_seconds[[1L]]) / 60
  out
}

extract_score <- function(run_dir) {
  score <- read_csv_or_null(file.path(run_dir, "tables", "score_summary.csv"))
  out <- list(q_check = NA_real_, raw_check = NA_real_, improvement = NA_real_)
  if (is.null(score) || !nrow(score) || !"check_loss_mean" %in% names(score)) return(out)
  ids <- as.character(score$model_id %||% score$fit_id %||% "")
  qidx <- which(grepl("qdesn", ids, ignore.case = TRUE))
  ridx <- which(grepl("raw_glofas|raw", ids, ignore.case = TRUE))
  if (length(qidx)) out$q_check <- as.numeric(score$check_loss_mean[qidx[[1L]]])
  if (length(ridx)) out$raw_check <- as.numeric(score$check_loss_mean[ridx[[1L]]])
  if (is.finite(out$q_check) && is.finite(out$raw_check) && out$raw_check != 0) {
    out$improvement <- (out$raw_check - out$q_check) / abs(out$raw_check)
  }
  out
}

manifest <- app_read_csv(manifest_path)
candidate_grid <- read_csv_or_null(file.path(runtime_dir, "candidate_grid.csv"))
if (is.null(candidate_grid)) candidate_grid <- unique(manifest[, c("candidate_id", "candidate_name"), drop = FALSE])

rows <- lapply(seq_len(nrow(manifest)), function(i) {
  m <- manifest[i, , drop = FALSE]
  run_dir <- app_path(file.path("application/runs", m$run_id[[1L]]))
  st <- stage_state(run_dir)
  fit <- extract_fit(run_dir, m$qdesn_fit_id[[1L]])
  score <- extract_score(run_dir)
  live <- session_live(m$session[[1L]])
  status <- if (identical(fit$status, "completed") && is.finite(score$q_check)) {
    "complete_scored"
  } else if (grepl("fail|error", fit$status, ignore.case = TRUE)) {
    "failed"
  } else if (isTRUE(live)) {
    "running"
  } else if (dir.exists(run_dir)) {
    "partial_or_waiting"
  } else {
    "not_started"
  }
  data.frame(
    run_index = as.integer(m$run_index[[1L]]),
    candidate_id = as.character(m$candidate_id[[1L]]),
    candidate_name = as.character(m$candidate_name[[1L]]),
    quantile_id = as.character(m$quantile_id[[1L]]),
    quantile_level = as.numeric(m$quantile_level[[1L]]),
    run_id = as.character(m$run_id[[1L]]),
    session = as.character(m$session[[1L]]),
    core = as.integer(m$core[[1L]]),
    live = isTRUE(live),
    status = status,
    latest_stage = st$stage,
    stage_status = st$status,
    fit_status = fit$status,
    runtime_min = fit$runtime_min,
    qdesn_check_loss = score$q_check,
    raw_check_loss = score$raw_check,
    relative_improvement = score$improvement,
    message = fit$message,
    stringsAsFactors = FALSE
  )
})

health <- app_bind_rows_fill(rows)
health <- health[order(health$run_index), , drop = FALSE]
app_write_csv(health, file.path(runtime_dir, "health_check_latest.csv"))

complete <- health[health$status == "complete_scored", , drop = FALSE]
ranking <- data.frame()
if (nrow(complete)) {
  by_candidate <- split(complete, complete$candidate_id)
  ranking <- do.call(rbind, lapply(by_candidate, function(block) {
    data.frame(
      candidate_id = block$candidate_id[[1L]],
      candidate_name = block$candidate_name[[1L]],
      n_complete = nrow(block),
      qdesn_check_loss_mean = mean(block$qdesn_check_loss, na.rm = TRUE),
      qdesn_check_loss_max = max(block$qdesn_check_loss, na.rm = TRUE),
      raw_check_loss_mean = mean(block$raw_check_loss, na.rm = TRUE),
      relative_improvement_mean = mean(block$relative_improvement, na.rm = TRUE),
      p05_check = block$qdesn_check_loss[match(0.05, block$quantile_level)],
      p50_check = block$qdesn_check_loss[match(0.50, block$quantile_level)],
      p95_check = block$qdesn_check_loss[match(0.95, block$quantile_level)],
      p05_improvement = block$relative_improvement[match(0.05, block$quantile_level)],
      p50_improvement = block$relative_improvement[match(0.50, block$quantile_level)],
      p95_improvement = block$relative_improvement[match(0.95, block$quantile_level)],
      stringsAsFactors = FALSE
    )
  }))
  ranking <- merge(ranking, candidate_grid, by = c("candidate_id", "candidate_name"), all.x = TRUE)
  ranking <- ranking[order(ranking$n_complete < 3L, ranking$qdesn_check_loss_mean, ranking$p95_check, na.last = TRUE), , drop = FALSE]
}
app_write_csv(ranking, file.path(runtime_dir, "candidate_ranking_latest.csv"))

references <- data.frame(
  reference = c("m360_full7_current_baseline", "m420_full7_current_candidate"),
  qdesn_check_loss = c(0.577575321885477, 0.571918628145349),
  qdesn_crps = c(1.155944, 1.147799),
  notes = c(
    "previous promoted reservoir-only full-seven synthesis",
    "current best completed m420 full-seven completion"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(references, file.path(runtime_dir, "reference_baselines.csv"))

status_counts <- as.data.frame(table(health$status), stringsAsFactors = FALSE)
names(status_counts) <- c("status", "n")

cat("\nGloFAS discrepancy-smoothing gate health\n")
print(health[, c(
  "candidate_id", "candidate_name", "quantile_id", "status", "live",
  "latest_stage", "stage_status", "runtime_min", "qdesn_check_loss", "raw_check_loss"
)], row.names = FALSE)

cat("\nStatus counts\n")
print(status_counts, row.names = FALSE)

if (nrow(ranking)) {
  cat("\nCandidate ranking from completed scored rows\n")
  keep <- intersect(c(
    "candidate_id", "candidate_name", "n_complete", "m", "alpha", "tau_profile",
    "beta_tau0", "alpha_tau0", "qdesn_check_loss_mean", "p05_check", "p50_check",
    "p95_check", "relative_improvement_mean"
  ), names(ranking))
  print(ranking[, keep, drop = FALSE], row.names = FALSE)
} else {
  cat("\nCandidate ranking unavailable: no completed scored rows yet.\n")
}

cat("\nReferences\n")
print(references, row.names = FALSE)

cat("\nWrote:\n")
cat(file.path(args$runtime_dir, "health_check_latest.csv"), "\n")
cat(file.path(args$runtime_dir, "candidate_ranking_latest.csv"), "\n")
cat(file.path(args$runtime_dir, "reference_baselines.csv"), "\n")
