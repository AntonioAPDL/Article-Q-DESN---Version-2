#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R", "latent_path_design.R",
  "discrepancy_design.R", "latent_path_vb_al.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R", "glofas_quantile_integrity.R",
  "glofas_normal_desn_part1_screening.R", "glofas_normal_desn_part2_bridge.R",
  "glofas_normal_desn_part3_joint_bridge.R", "glofas_part3_partitioned_rhs.R",
  "glofas_part1_quantile_oracle_forecast.R", "glofas_part3_quantile_bridge.R",
  "glofas_quantile_certification_restart.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(
  runtime_root = "", job_id = "", part = "", model_family = "", tau = "",
  source_fit_path = "", source_fit_sha256 = "", design_cache = "",
  design_cache_sha256 = "", max_iter = "200", min_iter = "200",
  convergence_tolerance = "1e-4", freeze_beta_warmup_iters = "20",
  min_beta_updates = "30", terminal_consecutive_passes = "3",
  progress_every = "1"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
job_id <- as.character(args$job_id[[1L]])
part <- as.character(args$part[[1L]])
model_family <- as.character(args$model_family[[1L]])
if (!part %in% c("part1", "part2", "part3")) stop("--part must be part1, part2, or part3.", call. = FALSE)
if (!nzchar(job_id)) stop("--job_id is required.", call. = FALSE)

for (sub in c("objects", "scores", "traces", "coefficients", "tables", "logs", "status")) {
  app_ensure_dir(file.path(runtime_root, sub))
}
running <- file.path(runtime_root, "status", paste0(job_id, ".running"))
completed <- file.path(runtime_root, "status", paste0(job_id, ".completed"))
certified <- file.path(runtime_root, "status", paste0(job_id, ".certified"))
failed <- file.path(runtime_root, "status", paste0(job_id, ".failed"))
if (file.exists(completed)) quit(save = "no", status = 0L)
writeLines(c(sprintf("job_id=%s", job_id), sprintf("pid=%d", Sys.getpid())), running)

parse_tau <- function(value) {
  value <- trimws(as.character(value[[1L]]))
  if (identical(tolower(value), "all7")) return(app_glofas_part1_quantile_grid())
  out <- suppressWarnings(as.numeric(strsplit(gsub("[[:space:]]+", "", value), "[,;|]")[[1L]]))
  if (!length(out) || any(!is.finite(out))) stop("Invalid --tau value.", call. = FALSE)
  out
}

truth_sha <- function(path, expected, label) {
  path <- normalizePath(app_resolve_path(path, must_work = TRUE), mustWork = TRUE)
  observed <- tolower(app_sha256_file(path))
  if (!identical(observed, tolower(as.character(expected[[1L]])))) {
    stop(sprintf("%s SHA256 mismatch: %s != %s", label, observed, expected[[1L]]), call. = FALSE)
  }
  path
}

write_contract <- function(row) {
  app_write_csv(as.data.frame(row, stringsAsFactors = FALSE),
    file.path(runtime_root, "logs", paste0(job_id, "_execution_contract.csv")))
}

run_restart <- function() {
  Sys.setenv(
    OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
  )
  app_glofas_quantile_validate_production_iteration_contract(
    as.integer(args$max_iter), as.integer(args$min_iter), TRUE,
    as.integer(args$freeze_beta_warmup_iters), as.integer(args$terminal_consecutive_passes)
  )
  source_fit_path <- truth_sha(args$source_fit_path, args$source_fit_sha256, "source fit")
  cache_path <- truth_sha(args$design_cache, args$design_cache_sha256, "design cache")
  source_fit <- app_glofas_quantile_unwrap_fit(readRDS(source_fit_path))
  cache <- readRDS(cache_path)
  tau <- parse_tau(args$tau)
  source_trace <- as.data.frame(source_fit$trace %||% data.frame())
  if (nrow(source_trace) != 200L || app_glofas_restart_source_iterations(source_fit) != 200L) {
    stop("Certification source must contain exactly 200 completed iterations.", call. = FALSE)
  }

  if (part %in% c("part1", "part2")) {
    y <- if (identical(part, "part1")) as.numeric(cache$design$y) else as.numeric(cache$forecast_design$y)
    Z <- if (identical(part, "part1")) as.matrix(cache$Z) else as.matrix(cache$forecast_design$X[, -1L, drop = FALSE])
    restart <- app_glofas_part12_build_restart_state(
      source_fit, model_family, tau, ncol(Z), length(y),
      source_path = source_fit_path, source_sha256 = args$source_fit_sha256
    )
    source_controls <- source_fit$part1_quantile_controls
    if (is.null(source_controls)) stop("Source fit lacks frozen Part 1/2 controls.", call. = FALSE)
    controls <- source_controls
    controls$max_iter <- as.integer(args$max_iter)
    controls$min_iter <- as.integer(args$min_iter)
    controls$tol <- as.numeric(args$convergence_tolerance)
    controls$init <- NULL
    controls$init_fit_path <- NULL
    controls$init_fit_paths <- NULL
    controls$restart_state <- restart
    controls$progress_path <- file.path(runtime_root, "traces", paste0(job_id, "_progress.csv"))
    controls$progress_every <- as.integer(args$progress_every)
    controls$freeze_beta_warmup_iters <- as.integer(args$freeze_beta_warmup_iters)
    controls$min_beta_updates <- as.integer(args$min_beta_updates)
    controls$fixed_iterations <- TRUE
    controls$full_state_convergence <- TRUE
    controls$convergence_tolerance <- as.numeric(args$convergence_tolerance)
    controls$terminal_consecutive_passes <- as.integer(args$terminal_consecutive_passes)
    prior_identity <- app_glofas_restart_assert_prior_identity(source_controls, controls, "part12")
    fit <- app_glofas_part1_quantile_fit_readout(y, Z, tau, model_family, controls)
    fit$target <- source_fit$target %||% if (identical(part, "part1")) "usgs" else "discrepancy"
    fit$cutoff_id <- source_fit$cutoff_id %||% cache$contract$cutoff_id
    fit$train_end <- source_fit$train_end %||% cache$contract$train_end
    coefficient_table <- app_glofas_part1_quantile_coefficient_rows(fit, Z, tau)
  } else {
    restart <- app_glofas_part3_build_restart_state(
      source_fit, tau, cache$design$p_beta, cache$design$p_alpha,
      2L * length(cache$split$train_idx), source_path = source_fit_path,
      source_sha256 = args$source_fit_sha256
    )
    source_controls <- source_fit$controls
    if (is.null(source_controls)) stop("Source fit lacks frozen Part 3 controls.", call. = FALSE)
    controls <- source_controls
    controls$max_iter <- as.integer(args$max_iter)
    controls$min_iter <- as.integer(args$min_iter)
    controls$tol <- as.numeric(args$convergence_tolerance)
    controls$progress_path <- file.path(runtime_root, "traces", paste0(job_id, "_progress.csv"))
    controls$progress_every <- as.integer(args$progress_every)
    controls$freeze_beta_warmup_iters <- as.integer(args$freeze_beta_warmup_iters)
    controls$min_beta_updates <- as.integer(args$min_beta_updates)
    controls$fixed_iterations <- TRUE
    controls$full_state_convergence <- TRUE
    controls$convergence_tolerance <- as.numeric(args$convergence_tolerance)
    controls$terminal_consecutive_passes <- as.integer(args$terminal_consecutive_passes)
    prior_identity <- app_glofas_restart_assert_prior_identity(source_controls, controls, "part3")
    fit <- app_glofas_part3_quantile_fit(
      cache$design, cache$split, tau = tau, likelihood = "AL",
      fit_structure = "joint", controls = controls, restart_state = restart,
      fit_id = job_id
    )
    coefficient_table <- app_glofas_part3_quantile_coefficient_table(fit, cache$design)
  }

  cumulative_trace <- app_glofas_restart_combine_traces(source_trace, fit$trace)
  certificate_row <- app_glofas_restart_certificate_row(
    fit, args$source_fit_sha256, restart$source_state_sha256, prior_identity,
    expected_segment_iterations = 200L, expected_source_iterations = 200L
  )
  fit$certification_restart <- list(
    source_fit_path = source_fit_path,
    source_fit_sha256 = as.character(args$source_fit_sha256[[1L]]),
    source_state_sha256 = restart$source_state_sha256,
    restart_kind = restart$restart_kind,
    prior_signature = prior_identity$restart$sha256,
    segment_iterations = 200L,
    cumulative_iterations = 400L,
    certified = isTRUE(certificate_row$certified[[1L]])
  )
  fit_path <- file.path(runtime_root, "objects", paste0(job_id, "_fit.rds"))
  saveRDS(fit, fit_path, version = 2L)
  trace_path <- app_write_csv(fit$trace, file.path(runtime_root, "traces", paste0(job_id, "_trace.csv")))
  cumulative_path <- app_write_csv(cumulative_trace, file.path(runtime_root, "traces", paste0(job_id, "_cumulative_trace.csv")))
  coefficient_path <- app_write_csv(coefficient_table, file.path(runtime_root, "coefficients", paste0(job_id, "_coefficients.csv")))
  certificate_path <- app_write_csv(certificate_row, file.path(runtime_root, "tables", paste0(job_id, "_certification.csv")))
  contract <- data.frame(
    job_id = job_id, part = part, model_family = model_family,
    tau = paste(sprintf("%.2f", tau), collapse = "|"),
    source_fit_path = source_fit_path,
    source_fit_sha256 = as.character(args$source_fit_sha256[[1L]]),
    source_state_sha256 = restart$source_state_sha256,
    restart_kind = restart$restart_kind,
    design_cache = cache_path, design_cache_sha256 = as.character(args$design_cache_sha256[[1L]]),
    prior_source_sha256 = prior_identity$source$sha256,
    prior_restart_sha256 = prior_identity$restart$sha256,
    fit_path = normalizePath(fit_path, mustWork = TRUE), fit_sha256 = app_sha256_file(fit_path),
    trace_path = trace_path, cumulative_trace_path = cumulative_path,
    coefficient_path = coefficient_path, certificate_path = certificate_path,
    segment_iterations = nrow(fit$trace), cumulative_iterations = nrow(cumulative_trace),
    terminal_certificate_passed = isTRUE(certificate_row$terminal_certificate_passed[[1L]]),
    certified = isTRUE(certificate_row$certified[[1L]]),
    stringsAsFactors = FALSE
  )
  write_contract(contract)
  if (isTRUE(certificate_row$certified[[1L]])) {
    writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), certified)
  }
  invisible(contract)
}

ok <- tryCatch({ run_restart(); TRUE }, error = function(e) {
  writeLines(conditionMessage(e), failed)
  message(conditionMessage(e))
  FALSE
})
unlink(running)
if (!ok) quit(save = "no", status = 1L)
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), completed)
message(sprintf("Completed certification restart: %s", job_id))
