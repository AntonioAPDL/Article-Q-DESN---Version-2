#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))
source(app_path("application/R/glofas_part3_partitioned_rhs.R"))
source(app_path("application/R/glofas_part3_quantile_bridge.R"))
source(app_path("application/R/glofas_part3_historical_forecast.R"))

args <- app_parse_args(list(
  runtime_root = "", design_cache = "", design_cache_sha256 = "", job_id = "",
  likelihood = "AL", fit_structure = "independent", tau = "0.50", init_fit_paths = "",
  max_iter = "100", min_iter = "30", tol = "0.01", tau0_reference = "1",
  tau0_discrepancy = "0.001", slab_s2 = "1", a_zeta = "2", b_zeta = "4",
  rhs_vb_inner = "5", progress_every = "1", horizon_days = "30", backend = "auto"
))
runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
job_id <- as.character(args$job_id)
running <- file.path(runtime_root, "status", paste0(job_id, ".running"))
completed <- file.path(runtime_root, "status", paste0(job_id, ".completed"))
failed <- file.path(runtime_root, "status", paste0(job_id, ".failed"))
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), running)

split_paths <- function(x) {
  out <- trimws(unlist(strsplit(as.character(x), "[|;,]"), use.names = FALSE))
  out[nzchar(out)]
}

tryCatch({
  cache_path <- app_resolve_path(args$design_cache, must_work = TRUE)
  if (!identical(tolower(app_sha256_file(cache_path)), tolower(args$design_cache_sha256))) stop("Part 3 design-cache SHA256 mismatch.", call. = FALSE)
  cache <- readRDS(cache_path)
  tau <- as.numeric(split_paths(args$tau))
  init_paths <- split_paths(args$init_fit_paths)
  init <- if (length(init_paths)) {
    paths <- vapply(init_paths, app_resolve_path, character(1L), must_work = TRUE)
    list(fits = lapply(paths, function(path) {
      fit <- readRDS(path)
      attr(fit, "part3_source_path") <- path
      attr(fit, "part3_source_sha256") <- app_sha256_file(path)
      fit
    }))
  } else NULL
  if (is.null(init)) stop("Part 3 quantile production fits require explicit warm-start fit paths.", call. = FALSE)
  progress_path <- file.path(runtime_root, "traces", paste0(job_id, "_progress.csv"))
  controls <- app_glofas_part3_quantile_default_controls(
    max_iter = as.integer(args$max_iter), min_iter = as.integer(args$min_iter), tol = as.numeric(args$tol),
    tau0_reference = as.numeric(args$tau0_reference), tau0_discrepancy = as.numeric(args$tau0_discrepancy),
    slab_s2 = as.numeric(args$slab_s2), a_zeta = as.numeric(args$a_zeta), b_zeta = as.numeric(args$b_zeta),
    rhs_vb_inner = as.integer(args$rhs_vb_inner), progress_path = progress_path,
    progress_every = as.integer(args$progress_every)
  )
  fit <- app_glofas_part3_quantile_fit(
    design = cache$design, split = cache$split, tau = tau,
    likelihood = args$likelihood, fit_structure = args$fit_structure,
    controls = controls, init = init, fit_id = job_id
  )
  fitted <- app_glofas_part3_write_quantile_result(fit, cache$design, cache$split, runtime_root, job_id)
  forecast <- app_glofas_part3_quantile_forecast(
    design = cache$design, split = cache$split, fit = fit,
    horizon_days = as.integer(args$horizon_days), backend = args$backend
  )
  forecasted <- app_glofas_part3_write_forecast(forecast, cache$design, runtime_root, job_id)
  init_rows <- data.frame(
    path = init_paths,
    sha256 = vapply(init_paths, function(path) app_sha256_file(app_resolve_path(path, must_work = TRUE)), character(1L)),
    stringsAsFactors = FALSE
  )
  init_manifest_path <- app_write_csv(init_rows, file.path(runtime_root, "tables", paste0(job_id, "_initializer_manifest.csv")))
  contract <- data.frame(
    job_id = job_id, likelihood = args$likelihood, fit_structure = args$fit_structure,
    tau = paste(sprintf("%.2f", tau), collapse = "|"),
    design_cache = cache_path, design_cache_sha256 = app_sha256_file(cache_path),
    initializer_manifest = init_manifest_path, initializer_manifest_sha256 = app_sha256_file(init_manifest_path),
    fit_path = fitted$paths[["fit"]], fit_sha256 = fitted$fit_sha256,
    forecast_path = forecasted$paths[["forecast"]], forecast_sha256 = app_sha256_file(forecasted$paths[["forecast"]]),
    inference_method_id = fit$inference_method_id, forecast_backend = forecast$backend,
    iterations = fit$iterations, converged = fit$converged, stop_reason = fit$stop_reason,
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
