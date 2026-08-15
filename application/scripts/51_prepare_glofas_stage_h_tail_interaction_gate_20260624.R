#!/usr/bin/env Rscript
# Purpose: prepare a controlled Stage H p05/p50/p95 tail and interaction gate
# for the GloFAS Q-DESN application after the completed Stage G p50 screen.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))

args <- app_parse_args(list(
  stage_g_runtime_dir = "local_trackers/runtime_configs/glofas_stage_g_median_screen_20260624",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_stage_h_tail_interaction_gate_20260624",
  batch_id = "glofas_stage_h_tail_interaction_gate_20260624",
  first_core = "16",
  n_cores = "16",
  max_active = "16",
  spread_factor = "1.4",
  spread_additive_width = "0.5",
  spread_center_quantile = "0.5",
  spread_calibration_id = "scorebalanced_spread_x1p400_plus0p500"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))
repeat_value <- function(x, n) as.list(rep(x, n))

out_dir <- app_path(args$out_dir)
stage_g_dir <- app_path(args$stage_g_runtime_dir)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "logs"))

first_core <- as.integer(args$first_core)
n_core_use <- as.integer(args$n_cores)
max_active <- as.integer(args$max_active)
n_detected <- parallel::detectCores(logical = TRUE)
if (any(!is.finite(c(first_core, n_core_use, max_active))) || first_core < 0L || n_core_use < 1L || max_active < 1L) {
  stop("Invalid core scheduler arguments.", call. = FALSE)
}
if ((first_core + n_core_use - 1L) >= n_detected) {
  stop(sprintf("Requested cores %d:%d exceed detected core count %d.", first_core, first_core + n_core_use - 1L, n_detected), call. = FALSE)
}

intervals <- list(list(lower = 0.05, upper = 0.95, nominal = 0.90))
target_levels <- c(0.05, 0.50, 0.95)
targets <- app_validate_quantile_grid(app_path(args$quantile_targets))
targets <- targets[round(as.numeric(targets$quantile_level), 8) %in% target_levels, , drop = FALSE]
targets <- targets[order(as.numeric(targets$quantile_level)), , drop = FALSE]
if (!identical(round(as.numeric(targets$quantile_level), 8), target_levels)) {
  stop("Quantile target file must contain p05, p50, and p95 for Stage H.", call. = FALSE)
}

stage_g_candidates <- app_read_csv(file.path(stage_g_dir, "candidate_manifest.csv"))
stage_g_components <- app_read_csv(file.path(stage_g_dir, "stage_g_scheduler_manifest.csv"))
stage_g_scores <- app_read_csv(file.path(stage_g_dir, "stage_g_ranked_scores.csv"))

direct_map <- data.frame(
  candidate_id = c(
    "h_reuse_alpha_0225",
    "h_reuse_rho098_a0200",
    "h_reuse_alpha_0200",
    "h_reuse_win014",
    "h_reuse_disc_tau001",
    "h_reuse_rho098_a0250"
  ),
  stage_g_source_candidate_id = c(
    "g_alpha_0225",
    "g_rho_098_a0200",
    "g_alpha_0200",
    "g_win_014",
    "g_disc_tau_0p01",
    "g_rho_098_a0250"
  ),
  candidate_kind = "direct_stage_g_winner",
  launch_quantiles = "0.05,0.95",
  purpose = c(
    "Tail-check the Stage G alpha=0.0225 median winner.",
    "Tail-check the Stage G alpha=0.020/rho=0.98 median winner.",
    "Tail-check the Stage G alpha=0.020 median winner.",
    "Tail-check the Stage G win_scale=0.14 median winner.",
    "Tail-check the Stage G discrepancy tau0=0.01 median winner.",
    "Tail-check the Stage G rho=0.98 at alpha=0.025 median winner."
  ),
  stringsAsFactors = FALSE
)

candidate_from_stage_g <- function(stage_g_id, candidate_id, kind, launch_quantiles, purpose) {
  src <- stage_g_candidates[stage_g_candidates$candidate_id == stage_g_id, , drop = FALSE]
  if (nrow(src) != 1L) stop(sprintf("Missing Stage G candidate definition: %s", stage_g_id), call. = FALSE)
  src$candidate_id <- candidate_id
  src$stage_g_source_candidate_id <- stage_g_id
  src$candidate_kind <- kind
  src$launch_quantiles <- launch_quantiles
  src$purpose <- purpose
  src
}

direct_candidates <- do.call(
  rbind,
  lapply(seq_len(nrow(direct_map)), function(i) {
    candidate_from_stage_g(
      direct_map$stage_g_source_candidate_id[[i]],
      direct_map$candidate_id[[i]],
      direct_map$candidate_kind[[i]],
      direct_map$launch_quantiles[[i]],
      direct_map$purpose[[i]]
    )
  })
)

combo_candidate <- function(candidate_id, alpha = 0.0225, rho = 0.95,
                            win_scale_global = 0.18, discrepancy_tau0 = 0.03,
                            purpose = "") {
  data.frame(
    candidate_id = candidate_id,
    block = "tail_interaction",
    D = 4L,
    width = 100L,
    reservoir_m = 300L,
    alpha = alpha,
    rho = rho,
    pi_w = 0.03,
    pi_in = 1.0,
    win_scale_global = win_scale_global,
    win_scale_bias = win_scale_global,
    shared_tau0 = 1e-3,
    discrepancy_tau0 = discrepancy_tau0,
    shared_slab_s2 = 1.0,
    discrepancy_slab_s2 = 1.0,
    seed = 20260512L,
    purpose = purpose,
    stage = "H_tail_interaction_gate",
    quantile_level = 0.50,
    stage_g_source_candidate_id = NA_character_,
    candidate_kind = "new_interaction_candidate",
    launch_quantiles = "0.05,0.50,0.95",
    stringsAsFactors = FALSE
  )
}

interaction_candidates <- rbind(
  combo_candidate(
    "h_combo_alpha0225_rho098",
    rho = 0.98,
    purpose = "Test alpha=0.0225 with the Stage G rho=0.98 signal."
  ),
  combo_candidate(
    "h_combo_alpha0225_win014",
    win_scale_global = 0.14,
    purpose = "Test alpha=0.0225 with the Stage G lower input-scale signal."
  ),
  combo_candidate(
    "h_combo_alpha0225_dtau001",
    discrepancy_tau0 = 0.01,
    purpose = "Test alpha=0.0225 with stronger discrepancy shrinkage."
  ),
  combo_candidate(
    "h_combo_alpha0225_rho098_win014_dtau001",
    rho = 0.98,
    win_scale_global = 0.14,
    discrepancy_tau0 = 0.01,
    purpose = "Adventurous local interaction among all positive Stage G signals."
  )
)

candidates <- app_bind_rows_fill(list(direct_candidates, interaction_candidates))
if (anyDuplicated(candidates$candidate_id)) {
  dupes <- unique(candidates$candidate_id[duplicated(candidates$candidate_id)])
  stop(sprintf("Duplicate Stage H candidate ids: %s", paste(dupes, collapse = ", ")), call. = FALSE)
}

apply_candidate <- function(cfg, cand) {
  D <- as.integer(cand$D[[1L]])
  width <- as.integer(cand$width[[1L]])
  m <- as.integer(cand$reservoir_m[[1L]])
  alpha <- as.numeric(cand$alpha[[1L]])
  rho <- as.numeric(cand$rho[[1L]])
  pi_w <- as.numeric(cand$pi_w[[1L]])
  win <- as.numeric(cand$win_scale_global[[1L]])
  win_bias <- as.numeric(cand$win_scale_bias[[1L]])

  cfg$reservoir$D <- D
  cfg$reservoir$n <- repeat_value(width, D)
  cfg$reservoir$n_tilde <- if (D > 1L) repeat_value(width, D - 1L) else list()
  cfg$reservoir$m <- m
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- repeat_value(alpha, D)
  cfg$reservoir$rho <- repeat_value(rho, D)
  cfg$reservoir$pi_w <- repeat_value(pi_w, D)
  cfg$reservoir$pi_in <- repeat_value(1.0, D)
  cfg$reservoir$win_scale_global <- win
  cfg$reservoir$win_scale_bias <- win_bias
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$act_f <- "tanh"
  cfg$reservoir$act_k <- "identity"
  cfg$reservoir$standardize_inputs <- TRUE
  cfg$reservoir$add_bias <- TRUE
  cfg$reservoir$seed <- as.integer(cand$seed[[1L]])

  cfg$covariates$readout$include_lags <- TRUE
  cfg$covariates$readout$lags <- list(range = c(0L, m))
  cfg$covariates$readout$standardize <- TRUE
  cfg$covariates$readout$scale_reference <- "retrospective_train"

  cfg$feature_contract$version <- "latent_path_v0.3"
  cfg$feature_contract$two_block_design <- TRUE
  cfg$feature_contract$reservoir_input$internal_bias <- TRUE
  cfg$feature_contract$reservoir_input$output_lags <- list(range = c(1L, m))
  cfg$feature_contract$reservoir_input$covariates$ppt <- list(range = c(0L, m))
  cfg$feature_contract$reservoir_input$covariates$soil <- list(range = c(0L, m))
  cfg$feature_contract$reservoir_input$standardize <- TRUE
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$reservoir_state_lags <- list()
  cfg$feature_contract$readout$include_input_block <- FALSE
  cfg$feature_contract$readout$include_horizon_scaled <- FALSE
  cfg$feature_contract$readout$standardize_output_lags <- TRUE
  cfg$feature_contract$readout$standardize_non_intercept <- FALSE
  cfg$feature_contract$forecast_alignment$output_lags_anchor <- "target_date"
  cfg$feature_contract$forecast_alignment$covariate_lags_anchor <- "target_date"

  cfg$prediction$posterior_predictive_sampling <- "disabled"
  cfg$inference$default_method <- "vb_ld"
  cfg$inference$likelihood_family <- "al"
  cfg$inference$coefficient_prior_default <- "rhs"
  cfg$inference$vb_ld$max_iter <- 150L
  cfg$inference$vb_ld$max_iter_hard_cap <- 150L
  cfg$inference$vb_ld$tol <- 1e-3
  cfg$inference$vb_ld$tol_par <- 1e-3
  cfg$inference$vb_ld$n_samp_xi <- 500L
  cfg$inference$vb_ld$n_draws <- 2000L
  cfg$inference$vb_ld$rhs_tau0 <- as.numeric(cand$shared_tau0[[1L]])
  cfg$inference$vb_ld$rhs_slab_s2 <- as.numeric(cand$shared_slab_s2[[1L]])
  cfg$inference$vb_ld$rhs_a_zeta <- 2.0
  cfg$inference$vb_ld$rhs_b_zeta <- 4.0
  cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(cand$discrepancy_tau0[[1L]])
  cfg$inference$vb_ld$rhs_alpha_slab_s2 <- as.numeric(cand$discrepancy_slab_s2[[1L]])
  cfg$inference$vb_ld$rhs_alpha_a_zeta <- 2.0
  cfg$inference$vb_ld$rhs_alpha_b_zeta <- 4.0
  cfg$inference$vb_ld$rhs_freeze_tau_warmup_iters <- 50L
  cfg$inference$vb_ld$rhs_update_every <- 1L
  cfg$inference$vb_ld$rhs_min_tau_updates <- 1L
  cfg$inference$vb_ld$diagnostics$profile_substeps <- FALSE
  cfg$inference$vb_ld$diagnostics$trace_iterations <- FALSE

  cfg$execution$seed_contract <- cfg$execution$seed_contract %||% list()
  cfg$execution$seed_contract$require_config_model_grid_match <- TRUE
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- "User-approved Stage H tail and interaction gate."
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg
}

make_scorebalanced_config <- function(cfg) {
  cfg$synthesis <- cfg$synthesis %||% list()
  cfg$synthesis$spread_calibration <- list(
    enabled = TRUE,
    factor = as.numeric(args$spread_factor),
    additive_width = as.numeric(args$spread_additive_width),
    center_quantile = as.numeric(args$spread_center_quantile),
    calibration_id = as.character(args$spread_calibration_id)
  )
  cfg
}

resolve_run_dir <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

reuse_ready <- function(row) {
  run_dir <- resolve_run_dir(row$run_dir[[1L]])
  fit_status_path <- file.path(run_dir, "tables", "fit_status.csv")
  pred_path <- file.path(run_dir, "tables", "prediction_quantiles.csv")
  score_path <- file.path(run_dir, "tables", "score_summary.csv")
  ok <- file.exists(fit_status_path) && file.exists(pred_path) && file.exists(score_path)
  if (ok) {
    fit_status <- app_read_csv(fit_status_path)
    ids <- c(row$raw_fit_id[[1L]], row$qdesn_fit_id[[1L]])
    rows <- fit_status[fit_status$fit_id %in% ids, , drop = FALSE]
    ok <- nrow(rows) == 2L && all(rows$status == "completed")
  }
  ok
}

stage_g_component_for <- function(stage_g_source_candidate_id) {
  row <- stage_g_components[
    stage_g_components$candidate_id == stage_g_source_candidate_id &
      abs(as.numeric(stage_g_components$quantile_level) - 0.50) < 1e-12,
    ,
    drop = FALSE
  ]
  if (nrow(row) != 1L) stop(sprintf("Missing unique Stage G p50 component row for %s.", stage_g_source_candidate_id), call. = FALSE)
  row
}

stage_g_config_for <- function(stage_g_source_candidate_id) {
  row <- stage_g_component_for(stage_g_source_candidate_id)
  cfg <- app_read_config(app_path(row$config_path[[1L]]))
  cfg$.__config_path__ <- NULL
  cfg
}

stage_g_model_grid_for <- function(stage_g_source_candidate_id) {
  row <- stage_g_component_for(stage_g_source_candidate_id)
  cfg <- stage_g_config_for(stage_g_source_candidate_id)
  app_validate_model_grid(app_path(row$model_grid_path[[1L]]), app_config_path(cfg, "schema"))
}

prepare_one_candidate <- function(cand, candidate_index) {
  candidate_id <- cand$candidate_id[[1L]]
  cand_dir <- file.path(out_dir, candidate_id)
  app_ensure_dir(cand_dir)
  app_ensure_dir(file.path(cand_dir, "logs"))

  is_direct <- identical(cand$candidate_kind[[1L]], "direct_stage_g_winner")
  source_id <- cand$stage_g_source_candidate_id[[1L]]
  source_id <- if (is.na(source_id) || !nzchar(source_id)) "g_alpha_0225" else source_id

  base_cfg <- stage_g_config_for(source_id)
  base_grid <- stage_g_model_grid_for(source_id)
  raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
  qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
  if (!nrow(raw_base) || !nrow(qdesn_base)) {
    stop(sprintf("Candidate %s base grid must contain raw_glofas and qdesn_glofas_discrepancy rows.", candidate_id), call. = FALSE)
  }
  if (!is_direct) {
    base_cfg <- apply_candidate(base_cfg, cand)
    raw_base$model_id <- sprintf("raw_glofas_%s_%s", args$batch_id, candidate_id)
    qdesn_base$model_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s_%s", args$batch_id, candidate_id)
    qdesn_base$reservoir_seed <- as.integer(cand$seed[[1L]])
  }
  raw_model_id <- raw_base$model_id[[1L]]
  qdesn_model_id <- qdesn_base$model_id[[1L]]

  component_rows <- vector("list", nrow(targets))
  launch_rows <- list()
  model_rows_all <- list()
  qgrid_rows_all <- list()
  prelaunch_rows <- list()

  for (i in seq_len(nrow(targets))) {
    qid <- q_label(targets$quantile_id[[i]])
    qlev <- as.numeric(targets$quantile_level[[i]])
    role <- as.character(targets$role[[i]])
    reuse_p50 <- is_direct && abs(qlev - 0.50) < 1e-12

    if (reuse_p50) {
      src_row <- stage_g_component_for(source_id)
      ok <- reuse_ready(src_row)
      prelaunch_rows[[length(prelaunch_rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        quantile_id = qid,
        quantile_level = qlev,
        source_kind = paste0("reused_stage_g_median_screen_", source_id),
        ready = ok,
        detail = src_row$run_dir[[1L]],
        stringsAsFactors = FALSE
      )
      component_rows[[i]] <- data.frame(
        batch_id = args$batch_id,
        candidate_id = candidate_id,
        stage_g_source_candidate_id = source_id,
        run_index = i,
        quantile_id = qid,
        quantile_level = qlev,
        role = role,
        run_id = src_row$run_id[[1L]],
        config_path = src_row$config_path[[1L]],
        quantile_grid_path = src_row$quantile_grid_path[[1L]],
        model_grid_path = src_row$model_grid_path[[1L]],
        run_dir = src_row$run_dir[[1L]],
        raw_fit_id = src_row$raw_fit_id[[1L]],
        qdesn_fit_id = src_row$qdesn_fit_id[[1L]],
        raw_model_id = src_row$raw_model_id[[1L]],
        qdesn_model_id = src_row$qdesn_model_id[[1L]],
        source_kind = paste0("reused_stage_g_median_screen_", source_id),
        required = TRUE,
        enabled = TRUE,
        stringsAsFactors = FALSE
      )
      model_rows_all[[length(model_rows_all) + 1L]] <- stage_g_model_grid_for(source_id)
      qgrid_rows_all[[length(qgrid_rows_all) + 1L]] <- app_read_csv(app_path(src_row$quantile_grid_path[[1L]]))
      next
    }

    run_id <- sprintf("%s_%s_%s", args$batch_id, candidate_id, qid)
    qgrid_path <- file.path(cand_dir, sprintf("quantile_grid_%s.csv", qid))
    model_grid_path <- file.path(cand_dir, sprintf("model_grid_%s.csv", qid))
    config_path <- file.path(cand_dir, sprintf("config_%s.yaml", qid))
    app_write_csv(targets[i, , drop = FALSE], qgrid_path)

    raw_row <- raw_base
    qdesn_row <- qdesn_base
    raw_row$fit_id <- sprintf("%s_%s", raw_model_id, qid)
    raw_row$quantile_level <- qlev
    raw_row$config_hash <- "TO_BE_COMPUTED"
    raw_row$notes <- sprintf("Raw GloFAS baseline for Stage H candidate %s; quantile=%s (%s).", candidate_id, qlev, role)
    qdesn_row$fit_id <- sprintf("%s_%s", qdesn_model_id, qid)
    qdesn_row$quantile_level <- qlev
    qdesn_row$reservoir_seed <- as.integer(cand$seed[[1L]])
    qdesn_row$config_hash <- "TO_BE_COMPUTED"
    qdesn_row$notes <- sprintf("Q-DESN Stage H tail/interaction candidate %s; quantile=%s (%s).", candidate_id, qlev, role)
    model_grid <- rbind(raw_row, qdesn_row)
    app_write_csv(model_grid, model_grid_path)

    cfg <- base_cfg
    cfg$application_name <- run_id
    cfg$description <- paste(
      sprintf("GloFAS Stage H tail/interaction component for %s.", candidate_id),
      sprintf("Quantile %s (%s).", qlev, role)
    )
    cfg$paths$quantile_grid <- repo_rel(qgrid_path)
    cfg$paths$model_grid <- repo_rel(model_grid_path)
    cfg$paths$cache <- file.path("application/cache", run_id)
    cfg$scoring$intervals <- intervals
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- sprintf("User-approved Stage H tail/interaction gate component for %s.", candidate_id)
    cfg$post_analysis$run_after_outputs <- FALSE
    app_write_yaml(cfg, config_path)

    validated_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
    app_validate_qdesn_model_grid_prior_contract(validated_grid)
    app_validate_qdesn_seed_contract(cfg, validated_grid)
    engine_report <- app_check_qdesn_engine_api(
      cfg,
      require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, validated_grid),
      stop_on_failure = TRUE
    )

    launch_index <- length(launch_rows) + 1L
    core <- first_core + (((candidate_index - 1L) * 3L + launch_index - 1L) %% n_core_use)
    session <- sprintf("%s_%s_%s", args$batch_id, candidate_id, qid)
    log_path <- file.path("application/logs", sprintf("%s.log", run_id))
    run_dir <- file.path("application/runs", run_id)
    prelaunch_rows[[length(prelaunch_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      quantile_id = qid,
      quantile_level = qlev,
      source_kind = "new_stage_h_tail_interaction_gate",
      ready = isTRUE(engine_report$ok) && !file.exists(app_path(run_dir)),
      detail = run_dir,
      stringsAsFactors = FALSE
    )
    launch_rows[[length(launch_rows) + 1L]] <- data.frame(
      batch_id = args$batch_id,
      candidate_id = candidate_id,
      run_index = i,
      quantile_id = qid,
      quantile_level = qlev,
      role = role,
      run_id = run_id,
      config_path = repo_rel(config_path),
      quantile_grid_path = repo_rel(qgrid_path),
      model_grid_path = repo_rel(model_grid_path),
      core = core,
      raw_fit_id = raw_row$fit_id,
      qdesn_fit_id = qdesn_row$fit_id,
      raw_model_id = raw_model_id,
      qdesn_model_id = qdesn_model_id,
      log_path = log_path,
      session = session,
      run_dir = run_dir,
      launch_status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
    component_rows[[i]] <- data.frame(
      batch_id = args$batch_id,
      candidate_id = candidate_id,
      stage_g_source_candidate_id = if (is_direct) source_id else NA_character_,
      run_index = i,
      quantile_id = qid,
      quantile_level = qlev,
      role = role,
      run_id = run_id,
      config_path = repo_rel(config_path),
      quantile_grid_path = repo_rel(qgrid_path),
      model_grid_path = repo_rel(model_grid_path),
      run_dir = run_dir,
      raw_fit_id = raw_row$fit_id,
      qdesn_fit_id = qdesn_row$fit_id,
      raw_model_id = raw_model_id,
      qdesn_model_id = qdesn_model_id,
      source_kind = "new_stage_h_tail_interaction_gate",
      required = TRUE,
      enabled = TRUE,
      stringsAsFactors = FALSE
    )
    model_rows_all[[length(model_rows_all) + 1L]] <- model_grid
    qgrid_rows_all[[length(qgrid_rows_all) + 1L]] <- targets[i, , drop = FALSE]
  }

  source_manifest <- do.call(rbind, component_rows)
  source_manifest <- source_manifest[order(source_manifest$run_index), , drop = FALSE]
  launch_manifest <- if (length(launch_rows)) do.call(rbind, launch_rows) else data.frame()
  prelaunch <- do.call(rbind, prelaunch_rows)
  qgrid_all <- do.call(rbind, qgrid_rows_all)
  qgrid_all <- qgrid_all[order(as.numeric(qgrid_all$quantile_level)), , drop = FALSE]
  model_grid_all <- app_bind_rows_fill(model_rows_all)

  app_write_csv(source_manifest, file.path(cand_dir, "synthesis_source_manifest.csv"))
  app_write_csv(source_manifest, file.path(cand_dir, "component_manifest.csv"))
  app_write_csv(launch_manifest, file.path(cand_dir, "launch_manifest.csv"))
  app_write_csv(prelaunch, file.path(cand_dir, "prelaunch_validation.csv"))
  app_write_csv(qgrid_all, file.path(cand_dir, "quantile_grid_all.csv"))
  app_write_csv(model_grid_all, file.path(cand_dir, "model_grid_all.csv"))

  synthesis_cfg <- base_cfg
  synthesis_cfg$application_name <- paste0(args$batch_id, "_", candidate_id, "_tail_synthesis")
  synthesis_cfg$description <- sprintf("Stage H p05/p50/p95 raw synthesis and scoring config for GloFAS candidate %s.", candidate_id)
  synthesis_cfg$paths$quantile_grid <- repo_rel(file.path(cand_dir, "quantile_grid_all.csv"))
  synthesis_cfg$paths$model_grid <- repo_rel(file.path(cand_dir, "model_grid_all.csv"))
  synthesis_cfg$paths$cache <- file.path("application/cache", paste0(args$batch_id, "_", candidate_id, "_tail_synthesis"))
  synthesis_cfg$scoring$intervals <- intervals
  synthesis_cfg$execution$final_launch$enabled <- FALSE
  synthesis_cfg$execution$final_launch$note <- "Tail-gate synthesis-only config; consumes completed Stage H component fits."
  synthesis_cfg$post_analysis$run_after_outputs <- FALSE
  app_write_yaml(synthesis_cfg, file.path(cand_dir, "synthesis_config.yaml"))
  app_write_yaml(make_scorebalanced_config(synthesis_cfg), file.path(cand_dir, "synthesis_config_scorebalanced.yaml"))

  list(source_manifest = source_manifest, launch_manifest = launch_manifest, prelaunch = prelaunch)
}

candidate_payloads <- vector("list", nrow(candidates))
for (j in seq_len(nrow(candidates))) {
  candidate_payloads[[j]] <- prepare_one_candidate(candidates[j, , drop = FALSE], j)
}

all_launch <- app_bind_rows_fill(lapply(candidate_payloads, `[[`, "launch_manifest"))
all_components <- app_bind_rows_fill(lapply(candidate_payloads, `[[`, "source_manifest"))
all_prelaunch <- app_bind_rows_fill(lapply(candidate_payloads, `[[`, "prelaunch"))

if (nrow(all_launch)) {
  all_launch$core <- first_core + ((seq_len(nrow(all_launch)) - 1L) %% n_core_use)
}

score_lookup <- stage_g_scores[, c("candidate_id", "q_check", "delta_vs_anchor", "pct_vs_anchor"), drop = FALSE]
candidates$stage_g_p50_check_loss <- NA_real_
candidates$stage_g_p50_pct_vs_anchor <- NA_real_
for (i in seq_len(nrow(candidates))) {
  src <- candidates$stage_g_source_candidate_id[[i]]
  if (!is.na(src) && nzchar(src)) {
    row <- score_lookup[score_lookup$candidate_id == src, , drop = FALSE]
    if (nrow(row) == 1L) {
      candidates$stage_g_p50_check_loss[[i]] <- row$q_check[[1L]]
      candidates$stage_g_p50_pct_vs_anchor[[i]] <- row$pct_vs_anchor[[1L]]
    }
  }
}

app_write_csv(candidates, file.path(out_dir, "stage_h_candidate_manifest.csv"))
app_write_csv(all_launch, file.path(out_dir, "stage_h_scheduler_manifest.csv"))
app_write_csv(all_components, file.path(out_dir, "stage_h_component_manifest.csv"))
app_write_csv(all_prelaunch, file.path(out_dir, "stage_h_prelaunch_validation.csv"))

if (!all(app_as_bool_vec(all_prelaunch$ready))) {
  failed <- all_prelaunch[!app_as_bool_vec(all_prelaunch$ready), , drop = FALSE]
  app_write_csv(failed, file.path(out_dir, "stage_h_prelaunch_failures.csv"))
  stop(sprintf("Stage H prelaunch validation failed for %d rows.", nrow(failed)), call. = FALSE)
}

write_stage_scheduler <- function() {
  path <- file.path(out_dir, sprintf("launch_%s_scheduler.sh", args$batch_id))
  state_path <- file.path(out_dir, "stage_h_scheduler_state.csv")
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    "export OMP_NUM_THREADS=1",
    "export OPENBLAS_NUM_THREADS=1",
    "export MKL_NUM_THREADS=1",
    "export VECLIB_MAXIMUM_THREADS=1",
    "export NUMEXPR_NUM_THREADS=1",
    sprintf("manifest=%s", shQuote(repo_rel(file.path(out_dir, "stage_h_scheduler_manifest.csv")))),
    sprintf("state=%s", shQuote(repo_rel(state_path))),
    sprintf("max_active=%d", max_active),
    "mkdir -p application/logs",
    "echo 'run_id,status,started_at,core,session,log_path,pid,exit_code' > \"$state\"",
    "pids=()",
    "run_ids=()",
    "cores=()",
    "sessions=()",
    "logs=()",
    "compact_jobs() {",
    "  local new_pids=() new_run_ids=() new_cores=() new_sessions=() new_logs=()",
    "  local i pid run_id core session log_path exit_code",
    "  for i in \"${!pids[@]}\"; do",
    "    pid=\"${pids[$i]}\"",
    "    run_id=\"${run_ids[$i]}\"",
    "    core=\"${cores[$i]}\"",
    "    session=\"${sessions[$i]}\"",
    "    log_path=\"${logs[$i]}\"",
    "    if kill -0 \"$pid\" 2>/dev/null; then",
    "      new_pids+=(\"$pid\")",
    "      new_run_ids+=(\"$run_id\")",
    "      new_cores+=(\"$core\")",
    "      new_sessions+=(\"$session\")",
    "      new_logs+=(\"$log_path\")",
    "    else",
    "      set +e",
    "      wait \"$pid\"",
    "      exit_code=$?",
    "      set -e",
    "      echo \"$run_id,finished,$(date -Is),$core,$session,$log_path,$pid,$exit_code\" >> \"$state\"",
    "    fi",
    "  done",
    "  pids=(\"${new_pids[@]}\")",
    "  run_ids=(\"${new_run_ids[@]}\")",
    "  cores=(\"${new_cores[@]}\")",
    "  sessions=(\"${new_sessions[@]}\")",
    "  logs=(\"${new_logs[@]}\")",
    "}",
    "wait_for_slot() {",
    "  while true; do",
    "    compact_jobs",
    "    if [[ \"${#pids[@]}\" -lt \"$max_active\" ]]; then break; fi",
    "    sleep 30",
    "  done",
    "}",
    "while IFS=$'\\t' read -r batch_id candidate_id run_index quantile_id quantile_level role run_id config_path core log_path session run_dir; do",
    "  wait_for_slot",
    "  if [[ -d \"$run_dir\" ]]; then",
    "    echo \"$run_id,skipped_existing,$(date -Is),$core,$session,$log_path,,\" >> \"$state\"",
    "    continue",
    "  fi",
    "  taskset -c \"$core\" Rscript application/scripts/run_all.R --config \"$config_path\" --run_id \"$run_id\" --preflight true --confirm_final_launch true > \"$log_path\" 2>&1 &",
    "  pid=$!",
    "  pids+=(\"$pid\")",
    "  run_ids+=(\"$run_id\")",
    "  cores+=(\"$core\")",
    "  sessions+=(\"$session\")",
    "  logs+=(\"$log_path\")",
    "  echo \"$run_id,launched,$(date -Is),$core,$session,$log_path,$pid,\" >> \"$state\"",
    "done < <(python3 - \"$manifest\" <<'PY'",
    "import csv",
    "import sys",
    "cols = ['batch_id','candidate_id','run_index','quantile_id','quantile_level','role','run_id','config_path','core','log_path','session','run_dir']",
    "with open(sys.argv[1], newline='') as handle:",
    "    for row in csv.DictReader(handle):",
    "        print('\\t'.join(str(row.get(k, '')) for k in cols))",
    "PY",
    ")",
    "while [[ \"${#pids[@]}\" -gt 0 ]]; do",
    "  compact_jobs",
    "  if [[ \"${#pids[@]}\" -gt 0 ]]; then sleep 30; fi",
    "done",
    "echo \"scheduler_complete,done,$(date -Is),,,,,\" >> \"$state\""
  )
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

write_stage_finalizer <- function() {
  path <- file.path(out_dir, sprintf("finalize_%s_candidates.sh", args$batch_id))
  log_path <- file.path("application/logs", sprintf("%s_finalize.log", args$batch_id))
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    sprintf("log=%s", shQuote(log_path)),
    "echo \"$(date -Is) finalizer started\" >> \"$log\""
  )
  for (candidate_id in candidates$candidate_id) {
    candidate_dir <- repo_rel(file.path(out_dir, candidate_id))
    raw_run <- sprintf("%s_%s_tail_synthesis_final", args$batch_id, candidate_id)
    score_run <- sprintf("%s_%s_tail_scorebalanced_synthesis_final", args$batch_id, candidate_id)
    raw_diag <- sprintf("%s_%s_tail_diagnostic_figures", args$batch_id, candidate_id)
    score_diag <- sprintf("%s_%s_tail_scorebalanced_diagnostic_figures", args$batch_id, candidate_id)
    prefix <- sprintf("glofas_stage_h_%s", candidate_id)
    lines <- c(
      lines,
      sprintf("echo '--- %s raw tail ---' >> \"$log\"", candidate_id),
      sprintf(
        "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R --config %s --source_manifest %s --run_id %s >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(raw_run)
      ),
      sprintf(
        "Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R --config %s --source_manifest %s --synthesis_run_id %s --run_id %s --figure_prefix %s >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(raw_run),
        shQuote(raw_diag),
        shQuote(prefix)
      ),
      sprintf("echo '--- %s scorebalanced tail ---' >> \"$log\"", candidate_id),
      sprintf(
        "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R --config %s --source_manifest %s --run_id %s >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config_scorebalanced.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(score_run)
      ),
      sprintf(
        "Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R --config %s --source_manifest %s --synthesis_run_id %s --run_id %s --figure_prefix %s_scorebalanced >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config_scorebalanced.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(score_run),
        shQuote(score_diag),
        shQuote(prefix)
      )
    )
  }
  lines <- c(lines, "echo \"$(date -Is) finalizer complete\" >> \"$log\"")
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

write_stage_watcher <- function(finalizer_path) {
  path <- file.path(out_dir, sprintf("watch_and_finalize_%s.sh", args$batch_id))
  log_path <- file.path("application/logs", sprintf("%s_watch.log", args$batch_id))
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    sprintf("manifest=%s", shQuote(repo_rel(file.path(out_dir, "stage_h_component_manifest.csv")))),
    sprintf("finalizer=%s", shQuote(repo_rel(finalizer_path))),
    sprintf("log=%s", shQuote(log_path)),
    "echo \"$(date -Is) watch started\" >> \"$log\"",
    "while true; do",
    "  read -r total done_count failed_count < <(python3 - \"$manifest\" <<'PY'",
    "import csv",
    "import pathlib",
    "import sys",
    "total = done = failed = 0",
    "with open(sys.argv[1], newline='') as handle:",
    "    for row in csv.DictReader(handle):",
    "        total += 1",
    "        run_dir = pathlib.Path(row['run_dir'])",
    "        fit = run_dir / 'tables' / 'fit_status.csv'",
    "        pred = run_dir / 'tables' / 'prediction_quantiles.csv'",
    "        ids = {row['raw_fit_id'], row['qdesn_fit_id']}",
    "        if fit.is_file():",
    "            txt = fit.read_text(errors='ignore')",
    "            if 'failed' in txt.lower():",
    "                failed += 1",
    "            if all(x in txt for x in ids) and txt.lower().count('completed') >= 2 and pred.is_file() and pred.stat().st_size > 0:",
    "                done += 1",
    "print(total, done, failed)",
    "PY",
    "  )",
    "  echo \"$(date -Is) completed=${done_count}/${total} failed=${failed_count}\" >> \"$log\"",
    "  if [ \"$failed_count\" -gt 0 ]; then echo \"failure detected; not finalizing\" >> \"$log\"; exit 1; fi",
    "  if [ \"$done_count\" -eq \"$total\" ] && [ \"$total\" -gt 0 ]; then break; fi",
    "  sleep 300",
    "done",
    "bash \"$finalizer\" >> \"$log\" 2>&1",
    "echo \"$(date -Is) watch/finalize complete\" >> \"$log\""
  )
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

write_stage_health <- function() {
  path <- file.path(out_dir, sprintf("health_check_%s.R", args$batch_id))
  r_string <- function(x) paste0("\"", gsub("\\\\", "\\\\\\\\", gsub("\"", "\\\\\"", x, fixed = TRUE)), "\"")
  lines <- c(
    "#!/usr/bin/env Rscript",
    sprintf("repo_root <- %s", r_string(app_repo_root())),
    "source(file.path(repo_root, 'application/R/00_packages.R'))",
    "app_set_repo_root(repo_root)",
    sprintf("component_manifest_path <- %s", r_string(repo_rel(file.path(out_dir, "stage_h_component_manifest.csv")))),
    sprintf("out_path <- %s", r_string(repo_rel(file.path(out_dir, "health_check_latest.csv")))),
    "m <- read.csv(file.path(repo_root, component_manifest_path), stringsAsFactors = FALSE)",
    "rows <- lapply(seq_len(nrow(m)), function(i) {",
    "  r <- m[i, , drop = FALSE]",
    "  run_dir <- file.path(repo_root, r$run_dir)",
    "  fit_path <- file.path(run_dir, 'tables', 'fit_status.csv')",
    "  score_path <- file.path(run_dir, 'tables', 'score_summary.csv')",
    "  pred_path <- file.path(run_dir, 'tables', 'prediction_quantiles.csv')",
    "  status <- if (!dir.exists(run_dir)) 'pending' else if (!file.exists(fit_path)) 'running' else {",
    "    fit <- read.csv(fit_path, stringsAsFactors = FALSE)",
    "    ids <- c(r$raw_fit_id, r$qdesn_fit_id)",
    "    if (any(tolower(fit$status) == 'failed')) 'failed' else if (all(ids %in% fit$fit_id) && all(fit$status[fit$fit_id %in% ids] == 'completed') && file.exists(pred_path)) 'completed' else 'running'",
    "  }",
    "  check <- raw_check <- NA_real_",
    "  if (file.exists(score_path)) {",
    "    s <- read.csv(score_path, stringsAsFactors = FALSE)",
    "    q <- s[grepl('qdesn', s$model_id, ignore.case = TRUE), , drop = FALSE]",
    "    raw <- s[grepl('raw_glofas', s$model_id, ignore.case = TRUE), , drop = FALSE]",
    "    check <- if (nrow(q) && 'check_loss_mean' %in% names(q)) as.numeric(q$check_loss_mean[1]) else NA_real_",
    "    raw_check <- if (nrow(raw) && 'check_loss_mean' %in% names(raw)) as.numeric(raw$check_loss_mean[1]) else NA_real_",
    "  }",
    "  data.frame(candidate_id=r$candidate_id, quantile_id=r$quantile_id, quantile_level=as.numeric(r$quantile_level), status=status, check_loss_mean=check, raw_check_loss_mean=raw_check, source_kind=r$source_kind, run_id=r$run_id, run_dir=r$run_dir, stringsAsFactors=FALSE)",
    "})",
    "d <- do.call(rbind, rows)",
    "write.csv(d, file.path(repo_root, out_path), row.names = FALSE)",
    "print(d[order(d$candidate_id, d$quantile_level), ], row.names = FALSE)",
    "cat(sprintf('\\ncomponents_completed=%d/%d failed=%d pending_or_running=%d\\n', sum(d$status == 'completed'), nrow(d), sum(d$status == 'failed'), sum(!d$status %in% c('completed','failed'))))",
    "agg <- aggregate(check_loss_mean ~ candidate_id, d[d$status == 'completed', ], mean, na.rm = TRUE)",
    "if (nrow(agg)) {",
    "  cat('\\ncompleted-component mean check loss by candidate:\\n')",
    "  print(agg[order(agg$check_loss_mean), ], row.names = FALSE)",
    "}",
    "runs <- file.path(repo_root, 'application/runs')",
    sprintf("prefix <- %s", r_string(args$batch_id)),
    "synth <- list.files(runs, pattern = paste0('^', prefix, '.*tail.*synthesis_final$'), full.names = TRUE)",
    "if (length(synth)) {",
    "  cat('\\nSynthesis scores found:\\n')",
    "  for (dir in synth) {",
    "    p <- file.path(dir, 'tables', 'score_summary.csv')",
    "    if (file.exists(p)) {",
    "      cat(sprintf('\\n%s\\n', basename(dir)))",
    "      print(read.csv(p, stringsAsFactors = FALSE), row.names = FALSE)",
    "    }",
    "  }",
    "}"
  )
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

launch_path <- write_stage_scheduler()
finalizer_path <- write_stage_finalizer()
watch_path <- write_stage_watcher(finalizer_path)
health_path <- write_stage_health()

plan_path <- file.path(out_dir, "PLAN.md")
if (file.exists(plan_path)) {
  plan_lines <- readLines(plan_path, warn = FALSE)
  plan_lines <- gsub("- \\[ \\] Write Stage H preparation script using the Stage E/F conventions and the", "- [x] Write Stage H preparation script using the Stage E/F conventions and the", plan_lines)
  plan_lines <- gsub("- \\[ \\] Generate manifests and configs\\.", "- [x] Generate manifests and configs.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Validate all direct p50 reuse rows exist and have completed fit/prediction", "- [x] Validate all direct p50 reuse rows exist and have completed fit/prediction", plan_lines)
  plan_lines <- gsub("- \\[ \\] Validate all new configs pass engine and prior-contract checks\\.", "- [x] Validate all new configs pass engine and prior-contract checks.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Confirm no Stage H run directories already exist unless intentionally", "- [x] Confirm no Stage H run directories already exist unless intentionally", plan_lines)
  writeLines(plan_lines, plan_path)
}

runbook <- file.path(out_dir, "RUNBOOK.md")
writeLines(c(
  "# Stage H Generated Runtime Package",
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "## Workload",
  "",
  sprintf("- Candidates: %d", nrow(candidates)),
  sprintf("- Components: %d", nrow(all_components)),
  sprintf("- New fits to launch: %d", nrow(all_launch)),
  sprintf("- Reused p50 fits: %d", sum(grepl("^reused_stage_g_median_screen_", all_components$source_kind))),
  sprintf("- Scheduler cores: %d:%d", first_core, first_core + n_core_use - 1L),
  sprintf("- Max active jobs: %d", max_active),
  "",
  "## Files",
  "",
  sprintf("- Candidate manifest: `%s`", repo_rel(file.path(out_dir, "stage_h_candidate_manifest.csv"))),
  sprintf("- Component manifest: `%s`", repo_rel(file.path(out_dir, "stage_h_component_manifest.csv"))),
  sprintf("- Scheduler manifest: `%s`", repo_rel(file.path(out_dir, "stage_h_scheduler_manifest.csv"))),
  sprintf("- Prelaunch validation: `%s`", repo_rel(file.path(out_dir, "stage_h_prelaunch_validation.csv"))),
  sprintf("- Scheduler: `%s`", repo_rel(launch_path)),
  sprintf("- Watch/finalize: `%s`", repo_rel(watch_path)),
  sprintf("- Finalizer: `%s`", repo_rel(finalizer_path)),
  sprintf("- Health check: `%s`", repo_rel(health_path)),
  "",
  "## Launch",
  "",
  sprintf("```bash\ntmux new-session -d -s %s_scheduler 'cd %s && bash %s > %s 2>&1'\n```",
          args$batch_id, app_repo_root(), repo_rel(launch_path), repo_rel(file.path(out_dir, "scheduler_stdout.log"))),
  "",
  sprintf("```bash\ntmux new-session -d -s %s_watch 'cd %s && bash %s > %s 2>&1'\n```",
          args$batch_id, app_repo_root(), repo_rel(watch_path), repo_rel(file.path(out_dir, "watch_stdout.log"))),
  "",
  "## Monitor",
  "",
  sprintf("```bash\nRscript %s\n```", repo_rel(health_path))
), runbook)

cat(sprintf("prepared=%s\n", repo_rel(out_dir)))
cat(sprintf("candidates=%d\n", nrow(candidates)))
cat(sprintf("new_fits=%d reused_fits=%d\n", nrow(all_launch), sum(grepl("^reused_stage_g_median_screen_", all_components$source_kind))))
cat(sprintf("launch=%s\n", repo_rel(launch_path)))
cat(sprintf("watch=%s\n", repo_rel(watch_path)))
cat(sprintf("health=%s\n", repo_rel(health_path)))
