#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else ""
repo_root <- if (nzchar(script_path)) {
  normalizePath(file.path(dirname(normalizePath(script_path, mustWork = TRUE)), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(getwd(), mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))
source(app_path("application/R/joint_exqdesn_inference_dispatch.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))
source(app_path("application/R/glofas_part3_partitioned_rhs.R"))
source(app_path("application/R/glofas_part3_quantile_bridge.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_part1_quantile_oracle_forecast.R"))
source(app_path("application/R/glofas_part2_bridge_forecast.R"))
source(app_path("application/R/glofas_part3_historical_forecast.R"))
source(app_path("application/R/glofas_dec25_final_refit_workflow.R"))

default_source_root <- Sys.getenv(
  "APP_GLOFAS_JEREZ_SOURCE_ROOT",
  unset = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part2_rhs_jerez_20260904"
)
default_base_config <- file.path(
  default_source_root,
  "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml"
)
default_part2_rhs_runtime <- file.path(
  default_source_root,
  "local_trackers/runtime_configs/glofas_normal_part2_rhs_top50_jerez_recovery_20260904"
)
default_part3_winner_manifest <- file.path(
  default_source_root,
  "local_trackers/runtime_configs/glofas_part3_normal_historical_jerez_20260904/configs/part3_frozen_g1_g2_winners.csv"
)

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_part23_final_dec25_2022_relaunch_jerez_20260905",
  part = "",
  job_id = "",
  job_type = "",
  model_family = "",
  tau = "",
  likelihood = "",
  fit_structure = "",
  method = "",
  fit_job_id = "",
  init_fit_job_ids = "",
  base_config = default_base_config,
  rhs_runtime_root = default_part2_rhs_runtime,
  rhs_candidate_id = "normal_part2_rhs_top16_part2ridge_targeted_0016_disc_covars__D1_n2500__a080_r070__reftau1e00_disctau1em03",
  candidate_id = "part2ridge_targeted_0016_disc_covars__D1_n2500__a080_r070",
  winner_manifest = default_part3_winner_manifest,
  part3_candidate_id = "part3_frozen_g1_g2_joint_historical",
  origin_date = "2022-12-25",
  horizon_days = "30",
  max_iter = "100",
  min_iter = "30",
  tol = "0.01",
  normal_draws = "500",
  seed = "20260905",
  forecast_backend = "cpp",
  freeze_beta_warmup_iters = "20",
  min_beta_updates = "30",
  require_cpp = "false"
))

truthy <- function(x) {
  tolower(as.character(x)[[1L]]) %in% c("true", "1", "yes", "y")
}

runtime_root <- app_resolve_path(args$runtime_root, must_work = FALSE)
part <- as.character(args$part[[1L]])
job_id <- as.character(args$job_id[[1L]])
job_type <- as.character(args$job_type[[1L]])
model_family <- as.character(args$model_family[[1L]])
horizon_days <- as.integer(args$horizon_days)
origin_date <- as.Date(args$origin_date)
if (!part %in% c("part2", "part3")) stop("--part must be part2 or part3.", call. = FALSE)
if (!job_type %in% c("design_cache", "fit", "forecast")) stop("--job_type must be design_cache, fit, or forecast.", call. = FALSE)
if (!nzchar(job_id)) stop("--job_id is required.", call. = FALSE)
app_glofas_dec25_assert_window(origin_date, horizon_days, label = paste("Dec25 job", job_id))

for (sub in c("configs", "objects", "forecasts", "scores", "traces", "coefficients", "tables", "logs", "status", "figures")) {
  app_ensure_dir(file.path(runtime_root, sub))
}

running_path <- file.path(runtime_root, "status", paste0(job_id, ".running"))
completed_path <- file.path(runtime_root, "status", paste0(job_id, ".completed"))
failed_path <- file.path(runtime_root, "status", paste0(job_id, ".failed"))
if (file.exists(completed_path)) stop(sprintf("Job is already completed: %s", job_id), call. = FALSE)
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), running_path)

cache_path <- function(part) file.path(runtime_root, "configs", paste0(part, "_final_dec25_design_cache.rds"))
fit_path <- function(id) file.path(runtime_root, "objects", paste0(id, "_fit.rds"))
warm_path <- function(id) file.path(runtime_root, "objects", paste0(id, "_warm_start.rds"))

parse_tau <- function(part, x) {
  x <- trimws(as.character(x[[1L]] %||% ""))
  if (!nzchar(x) || identical(tolower(x), "all7")) {
    return(if (identical(part, "part2")) app_glofas_part2_bridge_quantile_grid() else app_glofas_part3_quantile_grid())
  }
  out <- suppressWarnings(as.numeric(strsplit(gsub("[[:space:]]+", "", x), "[,;|]")[[1L]]))
  out <- out[is.finite(out)]
  if (!length(out)) stop("Could not parse --tau.", call. = FALSE)
  out
}

resolve_job_fit_paths <- function(ids) {
  ids <- trimws(unlist(strsplit(as.character(ids %||% ""), "[,;|]"), use.names = FALSE))
  ids <- ids[nzchar(ids)]
  if (!length(ids)) return(character())
  paths <- vapply(ids, function(id) {
    path <- fit_path(id)
    if (!file.exists(path)) stop(sprintf("Missing initializer fit for job %s at %s.", id, path), call. = FALSE)
    normalizePath(path, mustWork = TRUE)
  }, character(1L))
  unname(paths)
}

write_contract <- function(fields) {
  fields <- as.data.frame(fields, stringsAsFactors = FALSE)
  app_write_csv(fields, file.path(runtime_root, "logs", paste0(job_id, "_execution_contract.csv")))
}

write_fit_artifacts <- function(fit, design, tau = numeric(), component = NULL) {
  saveRDS(fit, fit_path(job_id), version = 2L)
  if (nrow(fit$trace %||% data.frame())) {
    app_write_csv(fit$trace, file.path(runtime_root, "traces", paste0(job_id, "_trace.csv")))
  }
  coeffs <- if (identical(part, "part3") && !is.null(fit$beta_reference_mean)) {
    app_glofas_part3_quantile_coefficient_table(fit, design)
  } else if (identical(part, "part3")) {
    app_glofas_normal_part3_coefficient_table(fit, design)
  } else if (length(tau)) {
    app_glofas_part1_quantile_coefficient_rows(
      fit,
      as.matrix(design$forecast_design$X[, -1L, drop = FALSE]),
      tau
    )
  } else {
    app_glofas_normal_rhs_coefficient_table(fit, design$design$discrepancy$feature_info)
  }
  app_write_csv(coeffs, file.path(runtime_root, "coefficients", paste0(job_id, "_coefficients.csv")))
  invisible(fit_path(job_id))
}

main <- function() {
  if (identical(job_type, "design_cache")) {
    base_cfg <- app_read_config(app_resolve_path(args$base_config, must_work = TRUE))
    if (identical(part, "part2")) {
      rhs_row <- app_glofas_part2_bridge_selected_rhs_row(
        rhs_runtime_root = args$rhs_runtime_root,
        rhs_candidate_id = args$rhs_candidate_id,
        candidate_id = args$candidate_id,
        rank = 1L
      )
      cache <- app_glofas_dec25_part2_design_cache(base_cfg = base_cfg, rhs_row = rhs_row)
    } else {
      manifest <- app_glofas_normal_part3_validate_winner_manifest(
        app_resolve_path(args$winner_manifest, must_work = TRUE),
        require_frozen = TRUE
      )
      candidate <- app_glofas_normal_part3_candidate_from_winners(
        manifest,
        candidate_id = args$part3_candidate_id,
        require_frozen = TRUE
      )
      cache <- app_glofas_dec25_part3_design_cache(base_cfg = base_cfg, candidate_row = candidate)
    }
    saveRDS(cache, cache_path(part), version = 2L)
    sha <- app_sha256_file(cache_path(part))
    cert <- data.frame(
      job_id = job_id,
      part = part,
      schema_version = cache$schema_version,
      design_cache = normalizePath(cache_path(part), mustWork = TRUE),
      design_cache_sha256 = sha,
      cutoff_id = cache$contract$cutoff_id,
      train_end = as.character(cache$contract$train_end),
      forecast_start = as.character(cache$contract$forecast_start),
      forecast_end = as.character(cache$contract$forecast_end),
      horizon_days = cache$contract$horizon_days,
      part2_rows = if (identical(part, "part2")) length(cache$design$dates) else NA_integer_,
      part3_dates = if (identical(part, "part3")) length(cache$design$dates) else NA_integer_,
      part3_stacked_rows = if (identical(part, "part3")) nrow(cache$design$H) else NA_integer_,
      stringsAsFactors = FALSE
    )
    app_write_csv(cert, file.path(runtime_root, "configs", paste0(part, "_final_dec25_design_cache_certificate.csv")))
    write_contract(cert)
    return(invisible(TRUE))
  }

  cache <- readRDS(cache_path(part))
  design_sha <- app_sha256_file(cache_path(part))
  tau <- parse_tau(part, args$tau)
  init_paths <- resolve_job_fit_paths(args$init_fit_job_ids)

  if (identical(job_type, "fit")) {
    if (identical(part, "part2")) {
      if (identical(model_family, "normal_ridge")) {
        result <- app_glofas_dec25_fit_part2_normal_ridge(cache)
        fit <- result$fit
        saveRDS(result$warm_start, warm_path(job_id), version = 2L)
        write_fit_artifacts(fit, cache)
      } else if (identical(model_family, "normal_rhs_vb")) {
        ridge_warm <- readRDS(warm_path("part2_fit_normal_ridge"))
        result <- app_glofas_dec25_fit_part2_normal_rhs(cache, warm_start = ridge_warm)
        fit <- result$fit
        write_fit_artifacts(fit, cache)
      } else {
        controls <- app_glofas_part1_quantile_default_controls(
          max_iter = as.integer(args$max_iter),
          min_iter = as.integer(args$min_iter),
          tol = as.numeric(args$tol),
          tau0 = cache$candidate_row$rhs_tau0[[1L]],
          zeta2 = Inf,
          rhs_vb_inner = 5L,
          exal_method_id = "VB1_structured_v",
          joint_backend = "auto",
          init_fit_paths = paste(init_paths, collapse = "|"),
          progress_path = file.path(runtime_root, "traces", paste0(job_id, "_progress.csv")),
          progress_every = 1L,
          freeze_beta_warmup_iters = as.integer(args$freeze_beta_warmup_iters),
          min_beta_updates = as.integer(args$min_beta_updates)
        )
        fit <- app_glofas_dec25_fit_part2_quantile(
          cache,
          model_family = model_family,
          tau = tau,
          controls = controls
        )
        write_fit_artifacts(fit, cache, tau = tau)
      }
    } else {
      if (identical(model_family, "normal_ridge")) {
        result <- app_glofas_dec25_fit_part3_normal_ridge(cache)
        fit <- result$fit
        saveRDS(result$warm_start, warm_path(job_id), version = 2L)
        write_fit_artifacts(fit, cache$design)
      } else if (identical(model_family, "normal_rhs_vb")) {
        ridge_warm <- readRDS(warm_path("part3_fit_normal_ridge"))
        result <- app_glofas_dec25_fit_part3_normal_rhs(cache, warm_start = ridge_warm)
        fit <- result$fit
        write_fit_artifacts(fit, cache$design)
      } else {
        controls <- app_glofas_part3_quantile_default_controls(
          max_iter = as.integer(args$max_iter),
          min_iter = as.integer(args$min_iter),
          tol = as.numeric(args$tol),
          tau0_reference = 1,
          tau0_discrepancy = 0.001,
          rhs_vb_inner = 5L,
          progress_path = file.path(runtime_root, "traces", paste0(job_id, "_progress.csv")),
          progress_every = 1L,
          freeze_beta_warmup_iters = as.integer(args$freeze_beta_warmup_iters),
          min_beta_updates = as.integer(args$min_beta_updates)
        )
        init <- if (!length(init_paths)) NULL else if (length(init_paths) == 1L) init_paths[[1L]] else list(fits = as.list(init_paths))
        fit <- app_glofas_part3_quantile_fit(
          cache$design,
          cache$split,
          tau = tau,
          likelihood = args$likelihood,
          fit_structure = args$fit_structure,
          controls = controls,
          init = init,
          fit_id = job_id
        )
        write_fit_artifacts(fit, cache$design, tau = tau)
      }
    }
    fit_sha <- app_sha256_file(fit_path(job_id))
    trace <- fit$trace %||% data.frame()
    beta_freeze_verified <- if (nrow(trace) && "beta_updated" %in% names(trace)) {
      all(!trace$beta_updated[trace$iter <= as.integer(args$freeze_beta_warmup_iters)]) &&
        any(trace$beta_updated[trace$iter > as.integer(args$freeze_beta_warmup_iters)])
    } else identical(model_family, "normal_ridge")
    contract <- data.frame(
      job_id = job_id,
      part = part,
      job_type = job_type,
      model_family = model_family,
      tau = paste(sprintf("%.2f", tau), collapse = "|"),
      cutoff_id = app_glofas_dec25_contract()$cutoff_id,
      train_end = as.character(app_glofas_dec25_contract()$train_end),
      design_cache = normalizePath(cache_path(part), mustWork = TRUE),
      design_cache_sha256 = design_sha,
      fit_path = normalizePath(fit_path(job_id), mustWork = TRUE),
      fit_sha256 = fit_sha,
      initializer_paths = paste(init_paths, collapse = "|"),
      initializer_sha256s = paste(vapply(init_paths, app_sha256_file, character(1L)), collapse = "|"),
      converged = isTRUE(fit$converged),
      iterations = as.integer(fit$iterations %||% nrow(trace) %||% NA_integer_),
      freeze_beta_warmup_iters = if (identical(model_family, "normal_ridge")) 0L else as.integer(args$freeze_beta_warmup_iters),
      min_beta_updates = if (identical(model_family, "normal_ridge")) 0L else as.integer(args$min_beta_updates),
      beta_freeze_verified = isTRUE(beta_freeze_verified),
      stringsAsFactors = FALSE
    )
    write_contract(contract)
    return(invisible(TRUE))
  }

  if (identical(job_type, "forecast")) {
    source_fit <- fit_path(args$fit_job_id)
    if (!file.exists(source_fit)) stop(sprintf("Missing retained fit for forecast: %s", source_fit), call. = FALSE)
    fit <- readRDS(source_fit)
    fit$fit_object_path <- normalizePath(source_fit, mustWork = TRUE)
    if (identical(part, "part2")) {
      if (model_family %in% c("normal_ridge", "normal_rhs_vb")) {
        mode <- if (identical(args$method, "rhs") || identical(model_family, "normal_rhs_vb")) "draw_recursive" else "plugin_mean_recursive"
        result <- app_glofas_dec25_forecast_part2_normal(
          cache,
          fit = fit,
          method = if (identical(model_family, "normal_ridge")) "ridge" else "rhs",
          forecast_mode = mode,
          n_draws = as.integer(args$normal_draws),
          seed = as.integer(args$seed),
          forecast_backend = args$forecast_backend
        )
        written <- app_glofas_part2_bridge_write_normal_result(result, runtime_root, job_id)
      } else {
        result <- app_glofas_dec25_forecast_part2_quantile(
          cache,
          fit = fit,
          tau = tau,
          forecast_backend = args$forecast_backend
        )
        written <- app_glofas_part2_bridge_write_quantile_result(result, runtime_root, job_id)
      }
      output_paths <- unname(unlist(written, recursive = TRUE, use.names = FALSE))
    } else {
      if (model_family %in% c("normal_ridge", "normal_rhs_vb")) {
        forecast <- app_glofas_part3_normal_forecast(
          cache$design,
          cache$split,
          fit = fit,
          method = if (identical(model_family, "normal_ridge")) "ridge" else "rhs",
          horizon_days = horizon_days,
          n_draws = as.integer(args$normal_draws),
          seed = as.integer(args$seed),
          backend = args$forecast_backend,
          origin_date = origin_date,
          allow_missing_future_truth = TRUE
        )
      } else {
        forecast <- app_glofas_part3_quantile_forecast(
          cache$design,
          cache$split,
          fit = fit,
          horizon_days = horizon_days,
          backend = args$forecast_backend,
          origin_date = origin_date,
          allow_missing_future_truth = TRUE
        )
      }
      app_glofas_dec25_assert_window(forecast$origin$origin_date, forecast$origin$horizon_days, forecast$origin$future_dates, label = job_id)
      written <- app_glofas_part3_write_forecast(forecast, cache$design, runtime_root, job_id)
      output_paths <- unname(written$paths)
    }
    output_paths <- output_paths[file.exists(output_paths)]
    contract <- data.frame(
      job_id = job_id,
      part = part,
      job_type = job_type,
      model_family = model_family,
      tau = paste(sprintf("%.2f", tau), collapse = "|"),
      cutoff_id = app_glofas_dec25_contract()$cutoff_id,
      origin_date = as.character(origin_date),
      forecast_start = as.character(app_glofas_dec25_contract()$forecast_start),
      forecast_end = as.character(app_glofas_dec25_contract()$forecast_end),
      horizon_days = horizon_days,
      design_cache = normalizePath(cache_path(part), mustWork = TRUE),
      design_cache_sha256 = design_sha,
      retained_fit_path = normalizePath(source_fit, mustWork = TRUE),
      retained_fit_sha256 = app_sha256_file(source_fit),
      output_paths = paste(normalizePath(output_paths, mustWork = TRUE), collapse = "|"),
      output_sha256s = paste(vapply(output_paths, app_sha256_file, character(1L)), collapse = "|"),
      future_truth_policy = if (identical(part, "part2")) "scores_unavailable_if_retrospective_glofas_missing" else "truth_may_be_missing_post_cutoff_scores_na",
      stringsAsFactors = FALSE
    )
    write_contract(contract)
    return(invisible(TRUE))
  }
  stop("Unhandled job type.", call. = FALSE)
}

ok <- tryCatch({
  main()
  TRUE
}, error = function(e) {
  message(conditionMessage(e))
  app_write_csv(
    data.frame(job_id = job_id, error = conditionMessage(e), failed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), stringsAsFactors = FALSE),
    file.path(runtime_root, "logs", paste0(job_id, "_failure.csv"))
  )
  writeLines(conditionMessage(e), failed_path)
  FALSE
})
unlink(running_path)
if (!isTRUE(ok)) quit(status = 1L, save = "no")
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), completed_path)
message(sprintf("Completed Dec25 job: %s", job_id))
