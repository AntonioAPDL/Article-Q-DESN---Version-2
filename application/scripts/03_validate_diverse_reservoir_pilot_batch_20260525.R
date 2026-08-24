#!/usr/bin/env Rscript
# Purpose: run sampler-free readiness checks for the prepared diverse
# reservoir-candidate batch. This script intentionally avoids run_all.R and
# 03_fit_models.R; it validates inputs, rebuilds per-config panels, and builds
# Q-DESN designs only.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  batch = "application/config/glofas_diverse_reservoir_pilot_batch_20260525.csv",
  run_id_prefix = "diverse8_prelaunch_design_20260525",
  n_jobs = "2",
  output = "application/config/glofas_diverse_reservoir_pilot_batch_20260525_validation.csv"
))

batch_path <- app_resolve_path(args$batch, must_work = TRUE)
batch <- app_read_csv(batch_path)
required <- c("pilot_rank", "spec_id", "config_path", "model_grid_path")
missing <- setdiff(required, names(batch))
if (length(missing)) {
  stop(sprintf("Batch table is missing required columns: %s.", paste(missing, collapse = ", ")), call. = FALSE)
}

n_jobs <- suppressWarnings(as.integer(args$n_jobs))
if (!is.finite(n_jobs) || n_jobs < 1L) n_jobs <- 1L
n_jobs <- min(n_jobs, nrow(batch))

run_stage <- function(script, config_path, run_id) {
  stage_args <- c(
    file.path("application", "scripts", script),
    "--config", config_path,
    "--run_id", run_id
  )
  start <- proc.time()[["elapsed"]]
  out <- tryCatch(
    system2("Rscript", stage_args, stdout = TRUE, stderr = TRUE),
    error = function(e) conditionMessage(e)
  )
  status <- attr(out, "status")
  exit_code <- if (is.null(status)) 0L else as.integer(status)
  list(
    exit_code = exit_code,
    runtime_seconds = proc.time()[["elapsed"]] - start,
    output_tail = paste(utils::tail(as.character(out), 8L), collapse = " | ")
  )
}

validate_one <- function(row) {
  rank <- as.integer(row$pilot_rank[[1L]])
  spec_id <- as.character(row$spec_id[[1L]])
  config_path <- as.character(row$config_path[[1L]])
  run_id <- sprintf("%s_%02d", args$run_id_prefix, rank)

  cfg <- app_read_yaml(app_path(config_path))
  run_dir <- file.path(app_config_path(cfg, "runs"), run_id)

  stages <- c("00_check_inputs.R", "01_build_panel.R", "03_check_model_design.R")
  results <- lapply(stages, run_stage, config_path = config_path, run_id = run_id)
  names(results) <- sub("\\.R$", "", stages)

  data.frame(
    pilot_rank = rank,
    spec_id = spec_id,
    config_path = config_path,
    model_grid_path = as.character(row$model_grid_path[[1L]]),
    run_id = run_id,
    run_dir = app_prefer_repo_relative_path(run_dir),
    check_inputs_exit = results$`00_check_inputs`$exit_code,
    build_panel_exit = results$`01_build_panel`$exit_code,
    design_check_exit = results$`03_check_model_design`$exit_code,
    check_inputs_seconds = round(results$`00_check_inputs`$runtime_seconds, 3),
    build_panel_seconds = round(results$`01_build_panel`$runtime_seconds, 3),
    design_check_seconds = round(results$`03_check_model_design`$runtime_seconds, 3),
    design_preflight_path = app_prefer_repo_relative_path(file.path(run_dir, "tables", "qdesn_discrepancy_design_preflight.csv")),
    inference_support_path = app_prefer_repo_relative_path(file.path(run_dir, "tables", "qdesn_inference_support_preflight.csv")),
    check_inputs_tail = results$`00_check_inputs`$output_tail,
    build_panel_tail = results$`01_build_panel`$output_tail,
    design_check_tail = results$`03_check_model_design`$output_tail,
    validation_status = if (all(vapply(results, function(x) identical(x$exit_code, 0L), logical(1L)))) "passed" else "failed",
    stringsAsFactors = FALSE
  )
}

if (n_jobs > 1L && .Platform$OS.type == "unix") {
  rows <- parallel::mclapply(seq_len(nrow(batch)), function(i) validate_one(batch[i, , drop = FALSE]), mc.cores = n_jobs)
} else {
  rows <- lapply(seq_len(nrow(batch)), function(i) validate_one(batch[i, , drop = FALSE]))
}

out <- app_bind_rows_fill(rows)
out_path <- app_resolve_path(args$output, must_work = FALSE)
app_write_csv(out, out_path)
print(out[, c("pilot_rank", "spec_id", "validation_status", "check_inputs_exit", "build_panel_exit", "design_check_exit", "design_check_seconds"), drop = FALSE])
cat(sprintf("wrote %s\n", app_prefer_repo_relative_path(out_path)))

if (any(out$validation_status != "passed")) {
  stop("One or more diverse reservoir-candidate sampler-free validation checks failed.", call. = FALSE)
}
