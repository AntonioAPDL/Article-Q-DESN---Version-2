#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_part3_historical_forecast.R"))

args <- app_parse_args(list(
  runtime_root = "", design_cache = "", design_cache_sha256 = "",
  fit_path = "", fit_sha256 = "", method = "rhs", job_id = "",
  horizon_days = "30", n_draws = "500", seed = "20260904", backend = "auto"
))
runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
job_id <- as.character(args$job_id)
running <- file.path(runtime_root, "status", paste0(job_id, ".running"))
completed <- file.path(runtime_root, "status", paste0(job_id, ".completed"))
failed <- file.path(runtime_root, "status", paste0(job_id, ".failed"))
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), running)

tryCatch({
  cache_path <- app_resolve_path(args$design_cache, must_work = TRUE)
  fit_path <- app_resolve_path(args$fit_path, must_work = TRUE)
  if (!identical(tolower(app_sha256_file(cache_path)), tolower(args$design_cache_sha256))) stop("Part 3 design-cache SHA256 mismatch.", call. = FALSE)
  if (!identical(tolower(app_sha256_file(fit_path)), tolower(args$fit_sha256))) stop("Part 3 Normal-fit SHA256 mismatch.", call. = FALSE)
  cache <- readRDS(cache_path)
  fit <- readRDS(fit_path)
  forecast <- app_glofas_part3_normal_forecast(
    design = cache$design, split = cache$split, fit = fit,
    method = args$method, horizon_days = as.integer(args$horizon_days),
    n_draws = as.integer(args$n_draws), seed = as.integer(args$seed), backend = args$backend
  )
  written <- app_glofas_part3_write_forecast(forecast, cache$design, runtime_root, job_id)
  contract <- data.frame(
    job_id = job_id, method = args$method, fit_path = fit_path,
    fit_sha256 = app_sha256_file(fit_path), design_cache = cache_path,
    design_cache_sha256 = app_sha256_file(cache_path),
    forecast_backend = forecast$backend, n_draws = forecast$n_draws,
    origin_date = as.character(forecast$origin$origin_date),
    horizon_days = forecast$origin$horizon_days,
    forecast_path = written$paths[["forecast"]],
    forecast_sha256 = app_sha256_file(written$paths[["forecast"]]),
    completed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
  app_write_csv(contract, file.path(runtime_root, "logs", paste0(job_id, "_execution_contract.csv")))
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), completed)
  if (file.exists(running)) unlink(running)
}, error = function(e) {
  writeLines(conditionMessage(e), failed)
  if (file.exists(running)) unlink(running)
  stop(e)
})
