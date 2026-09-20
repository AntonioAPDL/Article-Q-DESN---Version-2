#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R", "latent_path_design.R",
  "discrepancy_design.R", "latent_path_vb_al.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R", "glofas_quantile_integrity.R",
  "glofas_normal_desn_part1_screening.R",
  "glofas_normal_desn_part2_bridge.R", "glofas_normal_desn_part3_joint_bridge.R",
  "glofas_part3_partitioned_rhs.R", "glofas_part3_quantile_bridge.R",
  "glofas_normal_oracle_forecast.R", "glofas_part1_quantile_oracle_forecast.R",
  "glofas_part2_bridge_forecast.R", "glofas_part3_historical_forecast.R",
  "glofas_dec25_final_refit_workflow.R", "glofas_search_phase2.R",
  "glofas_normal_driver_bank.R", "glofas_external_driver_forecast.R",
  "glofas_part4_ensemble_likelihood_contract.R", "glofas_part4_normal_driver_prior.R",
  "glofas_post_search2_workflow.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(
  runtime_root = "",
  job_id = "",
  job_type = "",
  base_config = "",
  selected_components = "",
  calibration_path = "",
  model_family = "",
  tau = "",
  likelihood = "",
  fit_structure = "",
  fit_job_id = "",
  init_fit_job_ids = "",
  normal_driver_bank_path = "",
  part2_runtime_root = "",
  part3_runtime_root = "",
  part4_runtime_root = "",
  part4_base_config = "application/config/glofas_latent_path_al_vb_dec25_main.yaml",
  part4_run_label = "glofas_part4_post_search2_normal_driver_20260916",
  max_iter = "100",
  min_iter = "30",
  tol = "0.01",
  n_draws = "500",
  seed = "20260916",
  forecast_backend = "cpp",
  freeze_beta_warmup_iters = "20",
  min_beta_updates = "30",
  fixed_iterations = "false",
  full_state_convergence = "false",
  convergence_tolerance = "1e-4",
  terminal_consecutive_passes = "3"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = FALSE)
job_id <- as.character(args$job_id[[1L]])
job_type <- as.character(args$job_type[[1L]])
if (!nzchar(job_id) || !nzchar(job_type)) stop("--job_id and --job_type are required.", call. = FALSE)
for (sub in c("configs", "objects", "forecasts", "scores", "traces", "coefficients", "tables", "logs", "status", "figures")) {
  app_ensure_dir(file.path(runtime_root, sub))
}

running <- file.path(runtime_root, "status", paste0(job_id, ".running"))
completed <- file.path(runtime_root, "status", paste0(job_id, ".completed"))
failed <- file.path(runtime_root, "status", paste0(job_id, ".failed"))
if (file.exists(completed)) quit(save = "no", status = 0L)
writeLines(c(sprintf("job_id=%s", job_id), sprintf("pid=%d", Sys.getpid())), running)

part1_cache_path <- file.path(runtime_root, "configs", "part1_post_search2_design_cache.rds")
fit_path <- function(id) file.path(runtime_root, "objects", paste0(id, "_fit.rds"))
warm_path <- function(id) file.path(runtime_root, "objects", paste0(id, "_warm_start.rds"))

parse_tau <- function(x) {
  x <- trimws(as.character(x[[1L]] %||% ""))
  if (!nzchar(x) || identical(tolower(x), "all7")) return(app_glofas_part1_quantile_grid())
  out <- suppressWarnings(as.numeric(strsplit(gsub("[[:space:]]+", "", x), "[,;|]")[[1L]]))
  out <- out[is.finite(out)]
  if (!length(out)) stop("Could not parse --tau.", call. = FALSE)
  out
}

resolve_fit_paths <- function(ids) {
  ids <- trimws(unlist(strsplit(as.character(ids %||% ""), "[,;|]"), use.names = FALSE))
  ids <- ids[nzchar(ids)]
  vapply(ids, function(id) normalizePath(fit_path(id), mustWork = TRUE), character(1L), USE.NAMES = FALSE)
}

load_selection <- function() app_glofas_post_search2_read_selection(args$selected_components)
load_calibration <- function() app_read_csv(app_resolve_path(args$calibration_path, must_work = TRUE))

write_contract <- function(fields) {
  fields <- as.data.frame(fields, stringsAsFactors = FALSE)
  fields$job_id <- job_id
  fields$job_type <- job_type
  app_write_csv(fields, file.path(runtime_root, "logs", paste0(job_id, "_execution_contract.csv")))
}

part1_fitted <- function(cache, fit, method) {
  list(
    method = method,
    candidate_row = cache$candidate_row,
    base_cfg = cache$base_cfg,
    bundle = cache$bundle,
    design = cache$design,
    Z = cache$Z,
    fit = fit,
    fit_reused = TRUE,
    fit_object_path = as.character(fit$fit_object_path %||% NA_character_),
    fit_runtime_seconds = as.numeric(fit$fit_runtime_seconds %||% NA_real_)
  )
}

write_external <- function(result) {
  object <- file.path(runtime_root, "forecasts", paste0(job_id, "_forecast.rds"))
  table <- file.path(runtime_root, "forecasts", paste0(job_id, "_forecast.csv"))
  saveRDS(result, object, version = 2L)
  app_write_csv(result$forecast, table)
  app_write_csv(result$future_input_audit, file.path(runtime_root, "logs", paste0(job_id, "_future_input_audit.csv")))
  c(object, table)
}

run_job <- function() {
  if (identical(job_type, "part1_design")) {
    base_cfg <- app_read_config(app_resolve_path(args$base_config, must_work = TRUE))
    selection <- load_selection()
    row <- app_glofas_post_search2_component_row(selection, "reference")
    contract <- app_glofas_dec25_contract()
    bundle <- app_glofas_oracle_prepare_panel_bundle(
      base_cfg, contract$origin_date, contract$horizon_days, target = "usgs"
    )
    design <- app_glofas_oracle_build_part1_design(base_cfg, row, bundle)
    post_contract <- app_glofas_post_search2_final_design_contract(selection)
    app_glofas_post_search2_validate_final_dates(
      design$dates,
      selection,
      "Part 1 post-Search-II design"
    )
    cache <- list(
      schema_version = "glofas_part1_post_search2_final_design_v1",
      contract = contract, base_cfg = base_cfg, candidate_row = row,
      bundle = bundle, design = design, Z = as.matrix(design$X[, -1L, drop = FALSE]),
      post_search2_design_contract = post_contract,
      selection_manifest_path = normalizePath(app_resolve_path(args$selected_components, must_work = TRUE), mustWork = TRUE),
      selection_manifest_sha256 = attr(selection, "selection_sha256"),
      design_hash = app_glofas_normal_part1_design_fingerprint(
        design$X, design$y, design$dates, design$feature_info
      )
    )
    saveRDS(cache, part1_cache_path, version = 2L)
    write_contract(data.frame(design_cache = part1_cache_path, design_hash = cache$design_hash,
      rows = nrow(design$X), columns = ncol(design$X), stringsAsFactors = FALSE))
    return(invisible(TRUE))
  }

  if (identical(job_type, "calibration")) {
    cache <- readRDS(part1_cache_path)
    p1_ridge <- readRDS(fit_path("part1_fit_normal_ridge"))
    part2_root <- app_resolve_path(args$part2_runtime_root, must_work = TRUE)
    p2_ridge <- readRDS(file.path(part2_root, "objects", "part2_fit_normal_ridge_fit.rds"))
    p2_cache <- readRDS(file.path(part2_root, "configs", "part2_final_dec25_design_cache.rds"))
    calibration <- app_glofas_post_search2_calibration_record(
      load_selection(), p1_ridge, p2_ridge,
      p_reference = ncol(cache$design$X),
      p_discrepancy = ncol(p2_cache$design$discrepancy$X),
      n_reference = nrow(cache$design$X),
      n_discrepancy = nrow(p2_cache$design$discrepancy$X)
    )
    calibration$selection_sha256 <- cache$selection_manifest_sha256
    path <- app_resolve_path(args$calibration_path, must_work = FALSE)
    app_write_csv(calibration, path)
    saveRDS(calibration, sub("\\.csv$", ".rds", path), version = 2L)
    write_contract(calibration)
    return(invisible(TRUE))
  }

  if (identical(job_type, "anchor_manifest")) {
    p1 <- readRDS(part1_cache_path)
    p2_root <- app_resolve_path(args$part2_runtime_root, must_work = TRUE)
    p2 <- readRDS(file.path(p2_root, "configs", "part2_final_dec25_design_cache.rds"))
    anchors <- app_glofas_post_search2_anchor_manifest(
      load_selection(), load_calibration(), runtime_root,
      list(reference = p1$design_hash, discrepancy = p2$design_hash$discrepancy_full)
    )
    path <- file.path(runtime_root, "configs", "post_search2_selected_anchor_manifest.csv")
    app_write_csv(anchors, path)
    write_contract(data.frame(anchor_manifest = path, anchor_sha256 = app_sha256_file(path)))
    return(invisible(TRUE))
  }

  if (identical(job_type, "part4_prior")) {
    bank <- readRDS(app_resolve_path(args$normal_driver_bank_path, must_work = TRUE))
    dates <- as.Date(bank$contract$future_dates)
    keep <- seq_len(28L)
    short_bank <- app_glofas_normal_driver_bank(
      future_dates = dates[keep],
      components = lapply(bank$components, function(x) as.matrix(x)[keep, , drop = FALSE]),
      cutoff_date = bank$contract$cutoff_date,
      seed = bank$contract$seed,
      source_fit_path = bank$contract$source_fit_path,
      source_fit_sha256 = bank$contract$source_fit_sha256,
      source_model_id = bank$contract$source_model_id,
      response_scale = bank$contract$response_scale,
      exogenous_policy = bank$contract$exogenous_policy,
      observed_sources = bank$contract$observed_sources,
      forbidden_sources = bank$contract$forbidden_sources
    )
    prior <- app_glofas_part4_normal_driver_prior(short_bank, component = "usgs", expected_paths = 500L)
    part4_root <- app_resolve_path(args$part4_runtime_root, must_work = FALSE)
    app_ensure_dir(file.path(part4_root, "objects"))
    path <- file.path(part4_root, "objects", "part4_normal_driver_prior.rds")
    saveRDS(prior, path, version = 2L)
    write_contract(data.frame(part4_prior = path, prior_sha256 = app_sha256_file(path), horizon = 28L))
    return(invisible(TRUE))
  }

  if (identical(job_type, "part4_prepare")) {
    anchors <- file.path(runtime_root, "configs", "post_search2_selected_anchor_manifest.csv")
    bundle <- app_glofas_part4_prepare_bundle(
      base_config_path = args$part4_base_config,
      anchor_manifest_path = anchors,
      run_label = as.character(args$part4_run_label[[1L]]),
      runtime_root = args$part4_runtime_root,
      require_frozen = TRUE, allow_forbidden_sources = FALSE,
      dry_run = FALSE, write_candidate_configs = TRUE, require_input_files = TRUE,
      max_iter = as.integer(args$max_iter), min_iter = as.integer(args$min_iter),
      tol = as.numeric(args$tol),
      freeze_beta_warmup_iters = as.integer(args$freeze_beta_warmup_iters),
      min_beta_updates = as.integer(args$min_beta_updates), n_draws = as.integer(args$n_draws)
    )
    write_contract(data.frame(part4_runtime_root = bundle$metadata$runtime_root,
      manifest_path = bundle$metadata$manifest_path, ready_rows = bundle$metadata$ready_rows,
      blocked_rows = bundle$metadata$blocked_rows))
    return(invisible(TRUE))
  }

  cache <- readRDS(part1_cache_path)
  needs_calibration <- app_glofas_post_search2_needs_calibration(job_type, args$model_family)
  calibration <- if (needs_calibration) load_calibration() else NULL
  tau0 <- if (needs_calibration) {
    as.numeric(calibration$rhs_tau0[calibration$component == "reference"])
  } else {
    NA_real_
  }
  if (needs_calibration) cache$candidate_row$rhs_tau0 <- tau0
  tau <- parse_tau(args$tau)

  if (identical(job_type, "part1_fit")) {
    if (identical(args$model_family, "normal_ridge")) {
      fit <- app_glofas_normal_ridge_fit(
        cache$design$X, cache$design$y,
        ridge_tau2 = cache$candidate_row$ridge_tau2,
        intercept_var = cache$candidate_row$intercept_var,
        sigma_a = cache$candidate_row$sigma_a, sigma_b = cache$candidate_row$sigma_b
      )
      fit$type <- "normal_ridge_part1_post_search2_final"
      fit$converged <- TRUE
      warm <- app_glofas_oracle_ridge_warm_start(cache$candidate_row, cache$design, fit)
      saveRDS(warm, warm_path(job_id), version = 2L)
    } else if (identical(args$model_family, "normal_rhs_vb")) {
      warm <- readRDS(warm_path("part1_fit_normal_ridge"))
      zeta <- suppressWarnings(as.numeric(cache$candidate_row$rhs_zeta2_fixed[[1L]]))
      fit <- app_glofas_normal_rhs_fit(
        cache$design$X, cache$design$y, warm, tau0 = tau0,
        a_zeta = cache$candidate_row$rhs_a_zeta,
        b_zeta = cache$candidate_row$rhs_b_zeta,
        zeta2_fixed = if (is.finite(zeta)) zeta else NULL,
        max_iter = 100L, min_iter = 30L, tol = 1.0e-4,
        freeze_beta_warmup_iters = as.integer(args$freeze_beta_warmup_iters),
        min_beta_updates = as.integer(args$min_beta_updates)
      )
      fit$type <- "normal_rhs_vb_part1_post_search2_final"
    } else {
      if (app_as_bool(args$fixed_iterations)) {
        app_glofas_quantile_validate_production_iteration_contract(
          args$max_iter, args$min_iter, TRUE, args$freeze_beta_warmup_iters,
          args$terminal_consecutive_passes
        )
      }
      init_paths <- resolve_fit_paths(args$init_fit_job_ids)
      slab <- app_glofas_post_search2_quantile_slab(cache$candidate_row)
      controls <- app_glofas_part1_quantile_default_controls(
        max_iter = as.integer(args$max_iter), min_iter = as.integer(args$min_iter),
        tol = as.numeric(args$tol), tau0 = tau0,
        zeta2 = slab$zeta2, slab_fixed = slab$slab_fixed,
        init_fit_paths = paste(init_paths, collapse = "|"), progress_every = 1L,
        progress_path = file.path(runtime_root, "traces", paste0(job_id, "_progress.csv")),
        freeze_beta_warmup_iters = as.integer(args$freeze_beta_warmup_iters),
        min_beta_updates = as.integer(args$min_beta_updates),
        fixed_iterations = app_as_bool(args$fixed_iterations),
        full_state_convergence = app_as_bool(args$full_state_convergence),
        convergence_tolerance = as.numeric(args$convergence_tolerance),
        terminal_consecutive_passes = as.integer(args$terminal_consecutive_passes)
      )
      fit <- app_glofas_part1_quantile_fit_readout(
        cache$design$y, cache$Z, tau, as.character(args$model_family[[1L]]), controls
      )
      fit$target <- "usgs"
      fit$cutoff_id <- cache$contract$cutoff_id
    }
    saveRDS(fit, fit_path(job_id), version = 2L)
    if (nrow(fit$trace %||% data.frame())) app_write_csv(fit$trace, file.path(runtime_root, "traces", paste0(job_id, "_trace.csv")))
    trace <- fit$trace %||% data.frame()
    write_contract(data.frame(fit_path = fit_path(job_id), fit_sha256 = app_sha256_file(fit_path(job_id)),
      model_family = args$model_family, tau = paste(tau, collapse = "|"),
      rhs_tau0 = tau0,
      rhs_slab_policy = if (exists("slab", inherits = FALSE)) slab$policy else NA_character_,
      converged = isTRUE(fit$converged),
      iterations = as.integer(fit$iterations %||% nrow(trace) %||% NA_integer_),
      fixed_iterations_requested = app_as_bool(args$fixed_iterations),
      full_state_convergence_requested = app_as_bool(args$full_state_convergence),
      terminal_certificate_passed = isTRUE((fit$convergence_certificate %||% fit$terminal_certificate %||% list())$passed),
      stopping_reason = as.character(fit$stopping_reason %||% NA_character_),
      stringsAsFactors = FALSE))
    return(invisible(TRUE))
  }

  if (identical(job_type, "part1_forecast")) {
    source_fit <- fit_path(args$fit_job_id)
    fit <- readRDS(source_fit)
    fit$fit_object_path <- normalizePath(source_fit, mustWork = TRUE)
    if (args$model_family %in% c("normal_ridge", "normal_rhs_vb")) {
      result <- app_glofas_oracle_forecast_part1_single(
        cache$base_cfg, cache$candidate_row, cache$contract$origin_date,
        cache$contract$horizon_days, target = "usgs",
        method = if (identical(args$model_family, "normal_ridge")) "ridge" else "rhs",
        forecast_mode = "draw_recursive", n_draws = as.integer(args$n_draws),
        seed = as.integer(args$seed), retain_draws = TRUE,
        fit_object_path = source_fit, reuse_fit = TRUE,
        forecast_backend = args$forecast_backend
      )
      written <- app_glofas_oracle_write_result(result, runtime_root, job_id)
      output <- unname(written$figures %||% character())
      if (identical(args$model_family, "normal_rhs_vb")) {
        bank <- app_glofas_normal_driver_bank_from_part1(
          result$forecast, cache$contract$origin_date, as.integer(args$seed), source_fit
        )
        bank_path <- app_resolve_path(args$normal_driver_bank_path, must_work = FALSE)
        saveRDS(bank, bank_path, version = 2L)
        output <- c(output, bank_path)
      }
    } else {
      bank <- readRDS(app_resolve_path(args$normal_driver_bank_path, must_work = TRUE))
      fitted <- part1_fitted(cache, fit, "quantile")
      result <- app_glofas_part1_quantile_external_driver_forecast(
        fitted, fit, tau, bank,
        covariate_timeline = attr(cache$bundle$panel, "model_covariate_timeline", exact = TRUE),
        n_draws = as.integer(args$n_draws), seed = as.integer(args$seed),
        backend = args$forecast_backend
      )
      output <- write_external(result)
    }
    write_contract(data.frame(retained_fit = source_fit, retained_fit_sha256 = app_sha256_file(source_fit),
      model_family = args$model_family, tau = paste(tau, collapse = "|"),
      output_paths = paste(output, collapse = "|"), stringsAsFactors = FALSE))
    return(invisible(TRUE))
  }
  stop(sprintf("Unsupported post-Search-II support job type '%s'.", job_type), call. = FALSE)
}

ok <- tryCatch({ run_job(); TRUE }, error = function(e) {
  writeLines(conditionMessage(e), failed)
  message(conditionMessage(e))
  FALSE
})
unlink(running)
if (!ok) quit(save = "no", status = 1L)
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), completed)
message(sprintf("Completed post-Search-II job: %s", job_id))
