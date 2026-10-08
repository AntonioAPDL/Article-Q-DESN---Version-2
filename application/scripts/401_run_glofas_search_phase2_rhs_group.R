#!/usr/bin/env Rscript

Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1")
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "model_contract.R", "feature_contract.R", "covariate_design.R", "build_application_panel.R",
  "latent_path_design.R", "discrepancy_design.R", "latent_path_vb_al.R", "reservoir_screening.R",
  "glofas_normal_desn_part1_screening.R", "glofas_normal_oracle_forecast.R", "glofas_search_phase2.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(runtime_root = "", design_group_id = "", forecast_backend = "auto"))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
run_manifest <- app_read_yaml(file.path(root, "configs", "run_manifest.yaml"))
app_glofas_search2_assert_git_state(expected_head = run_manifest$git_head)
group_id <- as.character(args$design_group_id)
jobs <- app_read_csv(file.path(root, "configs", "job_manifest.csv"))
rows <- jobs[jobs$design_group_id == group_id, , drop = FALSE]
if (!nrow(rows) || any(rows$method != "rhs") || length(unique(rows$candidate_id)) != 1L ||
    length(unique(rows$fold_id)) != 1L || length(unique(rows$target)) != 1L) {
  stop(sprintf("Invalid Search-II RHS design group '%s'.", group_id), call. = FALSE)
}
pending <- rows[!file.exists(file.path(root, "status", paste0(rows$job_id, ".done"))) &
  !file.exists(file.path(root, "status", paste0(rows$job_id, ".failed"))), , drop = FALSE]
if (!nrow(pending)) quit(save = "no", status = 0L)

packet_path <- normalizePath(pending$model_packet_path[[1L]], mustWork = TRUE)
if (!identical(app_sha256_file(packet_path), as.character(pending$model_packet_sha256[[1L]]))) {
  stop("Model packet hash mismatch for grouped RHS execution.", call. = FALSE)
}
packet <- readRDS(packet_path)
app_glofas_search2_validate_model_packet(packet)
prep_started <- Sys.time()
prepared <- tryCatch(app_glofas_search2_prepare_fit_inputs(packet, pending[1L, , drop = FALSE]), error = function(e) e)
prep_seconds <- as.numeric(difftime(Sys.time(), prep_started, units = "secs"))
if (inherits(prepared, "error")) {
  for (job_id in pending$job_id) writeLines(conditionMessage(prepared), file.path(root, "status", paste0(job_id, ".failed")))
  stop(conditionMessage(prepared), call. = FALSE)
}

failures <- 0L
for (i in seq_len(nrow(pending))) {
  row <- pending[i, , drop = FALSE]
  job_id <- as.character(row$job_id[[1L]])
  running <- file.path(root, "status", paste0(job_id, ".running"))
  failed <- file.path(root, "status", paste0(job_id, ".failed"))
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), running)
  result <- tryCatch(
    app_glofas_search2_fit_and_forecast(packet, row, args$forecast_backend, prepared = prepared),
    error = function(e) e
  )
  if (inherits(result, "error")) {
    app_write_csv(cbind(row, data.frame(status = "failed", error_message = conditionMessage(result), stringsAsFactors = FALSE)),
      file.path(root, "fits", paste0(job_id, "_summary.csv")))
    writeLines(conditionMessage(result), failed)
    unlink(running)
    failures <- failures + 1L
    next
  }
  result$summary$shared_design_prep_seconds <- prep_seconds
  app_write_csv(result$summary, file.path(root, "fits", paste0(job_id, "_summary.csv")))
  app_write_csv(result$path, file.path(root, "forecasts", paste0(job_id, "_forecast.csv")))
  if (nrow(result$trace)) app_write_csv(result$trace, file.path(root, "traces", paste0(job_id, "_trace.csv")))
  app_write_csv(result$coefficient_top, file.path(root, "coefficients", paste0(job_id, "_top50.csv")))
  app_write_csv(result$coefficient_activity, file.path(root, "coefficients", paste0(job_id, "_activity.csv")))
  writeLines(c(
    paste0("forecast_sha256=", app_sha256_file(file.path(root, "forecasts", paste0(job_id, "_forecast.csv")))),
    paste0("completed_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
  ), file.path(root, "status", paste0(job_id, ".model_done")))
  unlink(running)
  score_status <- system2(file.path(R.home("bin"), "Rscript"), c(
    app_path("application/scripts/397_score_glofas_search_phase2.R"),
    "--runtime_root", root, "--job_id", job_id
  ))
  if (!identical(score_status, 0L)) failures <- failures + 1L
}

cat(sprintf("RHS design group %s complete: %d jobs, %d failures\n", group_id, nrow(pending), failures))
quit(save = "no", status = if (failures) 1L else 0L)
