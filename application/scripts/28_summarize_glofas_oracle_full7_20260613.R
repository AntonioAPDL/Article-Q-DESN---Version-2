#!/usr/bin/env Rscript
# Purpose: summarize health, provenance, and scores for the D14 oracle full-seven
# GloFAS launch without mutating any run artifacts.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))

args <- app_parse_args(list(
  runtime_dir = "local_trackers/runtime_configs/glofas_d14_oracle_full7_20260613",
  out_csv = NULL
))

runtime_dir <- app_path(args$runtime_dir)
manifest_path <- file.path(runtime_dir, "launch_manifest.csv")
if (!file.exists(manifest_path)) stop(sprintf("Missing launch manifest: %s", manifest_path), call. = FALSE)

read_csv_or_null <- function(path) {
  if (file.exists(path)) app_read_csv(path) else NULL
}

process_state <- function(run_id, pattern) {
  out <- tryCatch(system2("pgrep", c("-af", pattern), stdout = TRUE, stderr = FALSE), error = function(e) character())
  if (!length(out)) return("inactive")
  if (any(grepl(run_id, out, fixed = TRUE))) "active" else "inactive"
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
      x <- app_read_csv(status_path)
      if (nrow(x)) return(as.character(utils::tail(x$status, 1L)))
      return("status_empty")
    }
    if (started) return("running")
    "pending"
  }, character(1L))
  idx <- max(which(states != "pending"), na.rm = TRUE)
  if (!is.finite(idx)) return(list(stage = "not_started", status = "pending"))
  list(stage = stages[[idx]], status = states[[idx]])
}

covariate_summary <- function(run_dir) {
  x <- read_csv_or_null(file.path(run_dir, "tables", "covariate_policy_audit.csv"))
  if (is.null(x) || !nrow(x)) {
    return(list(policy = NA_character_, provider = NA_character_, n_oracle = NA_integer_, n_missing = NA_integer_, source_hash = NA_character_))
  }
  list(
    policy = paste(unique(as.character(x$future_policy)), collapse = ";"),
    provider = paste(unique(as.character(x$source_provider)), collapse = ";"),
    n_oracle = sum(as.integer(x$n_oracle_realized %||% 0L), na.rm = TRUE),
    n_missing = sum(as.integer(x$n_missing %||% 0L), na.rm = TRUE),
    source_hash = paste(unique(as.character(x$source_manifest_hash %||% NA_character_)), collapse = ";")
  )
}

fit_summary <- function(run_dir, qdesn_fit_id) {
  x <- read_csv_or_null(file.path(run_dir, "tables", "fit_status.csv"))
  if (is.null(x) || !nrow(x)) {
    return(list(fit_status = "pending", runtime_min = NA_real_, message = NA_character_))
  }
  row <- x[x$fit_id == qdesn_fit_id, , drop = FALSE]
  if (!nrow(row)) row <- utils::tail(x, 1L)
  list(
    fit_status = as.character(row$status[[1L]]),
    runtime_min = as.numeric(row$runtime_seconds[[1L]]) / 60,
    message = as.character(row$message[[1L]])
  )
}

score_summary <- function(run_dir) {
  x <- read_csv_or_null(file.path(run_dir, "tables", "score_summary.csv"))
  if (is.null(x) || !nrow(x)) return(list(crps = NA_real_, q_check = NA_real_))
  qdesn <- x[grepl("qdesn", as.character(x$model_id %||% x$fit_id %||% ""), ignore.case = TRUE), , drop = FALSE]
  row <- if (nrow(qdesn)) qdesn[1L, , drop = FALSE] else x[1L, , drop = FALSE]
  list(
    crps = if ("crps" %in% names(row)) as.numeric(row$crps[[1L]]) else NA_real_,
    q_check = if ("q_check" %in% names(row)) as.numeric(row$q_check[[1L]]) else NA_real_
  )
}

manifest <- app_read_csv(manifest_path)
rows <- vector("list", nrow(manifest))
for (i in seq_len(nrow(manifest))) {
  run_id <- as.character(manifest$run_id[[i]])
  run_dir <- app_path(file.path("application", "runs", run_id))
  st <- stage_state(run_dir)
  cov <- covariate_summary(run_dir)
  fit <- fit_summary(run_dir, as.character(manifest$qdesn_fit_id[[i]]))
  score <- score_summary(run_dir)
  rows[[i]] <- data.frame(
    run_index = as.integer(manifest$run_index[[i]]),
    quantile_id = as.character(manifest$quantile_id[[i]]),
    quantile_level = as.numeric(manifest$quantile_level[[i]]),
    run_id = run_id,
    core = as.integer(manifest$core[[i]]),
    process = process_state(run_id, run_id),
    latest_stage = st$stage,
    stage_status = st$status,
    fit_status = fit$fit_status,
    fit_runtime_min = fit$runtime_min,
    covariate_future_policy = cov$policy,
    covariate_source_provider = cov$provider,
    n_oracle_covariate_rows = cov$n_oracle,
    n_missing_covariates = cov$n_missing,
    covariate_source_manifest_hash = cov$source_hash,
    qdesn_crps = score$crps,
    qdesn_q_check = score$q_check,
    message = fit$message,
    stringsAsFactors = FALSE
  )
}

summary <- do.call(rbind, rows)
summary <- summary[order(summary$run_index), , drop = FALSE]

out_csv <- args$out_csv %||% file.path(runtime_dir, "health_summary.csv")
app_write_csv(summary, out_csv)
print(summary[, c(
  "quantile_id", "quantile_level", "process", "latest_stage", "stage_status",
  "fit_status", "fit_runtime_min", "covariate_future_policy",
  "n_oracle_covariate_rows", "qdesn_crps", "qdesn_q_check"
)], row.names = FALSE)
cat(out_csv, "\n")
