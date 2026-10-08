#!/usr/bin/env Rscript

Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1")
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "model_contract.R", "feature_contract.R", "covariate_design.R", "build_application_panel.R",
  "latent_path_design.R", "discrepancy_design.R", "latent_path_vb_al.R", "reservoir_screening.R",
  "glofas_normal_desn_part1_screening.R", "glofas_normal_oracle_forecast.R",
  "glofas_search_phase2.R", "glofas_search3_rainy_season.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(runtime_root = "", job_id = "", forecast_backend = "auto"))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
run_manifest <- app_read_yaml(file.path(root, "configs", "run_manifest.yaml"))
app_glofas_search2_assert_git_state(expected_head = run_manifest$git_head)
jobs <- app_read_csv(file.path(root, "configs", "job_manifest.csv"))
row <- jobs[jobs$job_id == as.character(args$job_id), , drop = FALSE]
if (nrow(row) != 1L) stop("Expected exactly one Search III job row.", call. = FALSE)
job_id <- as.character(row$job_id[[1L]])
done <- file.path(root, "status", paste0(job_id, ".done"))
running <- file.path(root, "status", paste0(job_id, ".running"))
failed <- file.path(root, "status", paste0(job_id, ".failed"))
if (file.exists(done)) quit(save = "no", status = 0L)
if (file.exists(failed)) unlink(failed)
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), running)

started <- Sys.time()
result <- tryCatch({
  packet_path <- normalizePath(row$model_packet_path[[1L]], mustWork = TRUE)
  if (!identical(app_sha256_file(packet_path), as.character(row$model_packet_sha256[[1L]]))) {
    stop("Search III model packet hash mismatch.", call. = FALSE)
  }
  packet <- readRDS(packet_path)
  app_glofas_search2_validate_model_packet(packet)
  app_glofas_search3_fit_and_forecast(packet, row, as.character(args$forecast_backend))
}, error = function(e) e)

if (inherits(result, "error")) {
  app_write_csv(cbind(row, data.frame(
    status = "failed", error_message = conditionMessage(result),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")), stringsAsFactors = FALSE
  )), file.path(root, "fits", paste0(job_id, "_summary.csv")))
  writeLines(conditionMessage(result), failed)
  unlink(running)
  quit(save = "no", status = 1L)
}

app_write_csv(result$summary, file.path(root, "fits", paste0(job_id, "_summary.csv")))
app_write_csv(result$path, file.path(root, "forecasts", paste0(job_id, "_forecast.csv")))
if (nrow(result$trace)) app_write_csv(result$trace, file.path(root, "traces", paste0(job_id, "_trace.csv")))
app_write_csv(result$coefficient_top, file.path(root, "coefficients", paste0(job_id, "_top50.csv")))
app_write_csv(result$coefficient_activity, file.path(root, "coefficients", paste0(job_id, "_activity.csv")))
if (identical(as.character(row$method[[1L]]), "ridge")) {
  warm_path <- file.path(root, "warm_starts", paste0(job_id, "_warm_start.rds"))
  saveRDS(result$ridge_warm_start, warm_path, version = 2L)
}
writeLines(c(
  paste0("forecast_sha256=", app_sha256_file(file.path(root, "forecasts", paste0(job_id, "_forecast.csv")))),
  paste0("completed_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
), file.path(root, "status", paste0(job_id, ".model_done")))
unlink(running)
quit(save = "no", status = 0L)
