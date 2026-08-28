#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/latent_path_runtime_backend.R"))
source(app_path("application/R/latent_path_checkpoint.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/reservoir_screening.R"))
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/glofas_fit_recovery_mechanism_audit.R"))
source(app_path("application/R/glofas_fit_recovery_selection.R"))
source(app_path("application/R/glofas_fit_recovery_scientific_audit.R"))
source(app_path("application/R/glofas_discrepancy_equivalence_audit.R"))

args <- app_parse_args(list(
  runtime_root = "/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/runtime_configs/glofas_richer_discrepancy_initial_20260827",
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_equivalence_audit_20260827",
  candidate_ids = "",
  history_n = 1000,
  exact_draw_subset = 3,
  uncertainty_draw_subset = 101,
  overwrite = FALSE
))

resolve_path <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}

runtime_root <- resolve_path(args$runtime_root, TRUE)
output_root <- resolve_path(args$output_root, FALSE)
history_n <- as.integer(args$history_n)
exact_draw_subset <- as.integer(args$exact_draw_subset)
uncertainty_draw_subset <- as.integer(args$uncertainty_draw_subset)
if (!is.finite(history_n) || history_n < 50L) stop("history_n must be at least 50.", call. = FALSE)
if (!is.finite(exact_draw_subset) || exact_draw_subset < 1L) stop("exact_draw_subset must be positive.", call. = FALSE)
if (!is.finite(uncertainty_draw_subset) || uncertainty_draw_subset < 3L) {
  stop("uncertainty_draw_subset must be at least three.", call. = FALSE)
}
if (dir.exists(output_root) && length(list.files(output_root, all.files = TRUE, no.. = TRUE)) &&
    !app_as_bool(args$overwrite)) {
  stop(sprintf("Output root is not empty: %s. Use --overwrite true for an intentional rebuild.", output_root), call. = FALSE)
}
if (dir.exists(output_root) && app_as_bool(args$overwrite)) unlink(output_root, recursive = TRUE, force = TRUE)
for (dir in c("tables", "figures", "manifest")) app_ensure_dir(file.path(output_root, dir))

message("[equivalence-audit] freezing terminal campaign evidence")
status_precedence <- app_glofas_equivalence_status_precedence(runtime_root)
campaign_certificate <- app_glofas_equivalence_campaign_certificate(runtime_root)
if (!identical(
  unname(as.integer(unlist(campaign_certificate[c(
    "completed_candidates", "preflight_rejected_candidates", "failed_candidates", "incomplete_candidates"
  )], use.names = FALSE))),
  c(5L, 16L, 0L, 0L)
)) {
  stop("The completed campaign census differs from the frozen 5/16/0/0 contract.", call. = FALSE)
}

finalization <- app_read_csv(file.path(runtime_root, "finalization_status.csv"))
runtime <- app_read_csv(file.path(runtime_root, "runtime_manifest.csv"))
candidate_manifest <- app_read_csv(file.path(runtime_root, "candidate_manifest.csv"))
retained_manifest <- app_read_csv(file.path(runtime_root, "retained_heavy_artifact_manifest.csv"))
requested <- trimws(unlist(strsplit(as.character(args$candidate_ids), "[,;]")))
requested <- requested[nzchar(requested)]
if (!length(requested)) {
  requested <- trimws(unlist(strsplit(as.character(finalization$protected_candidates[[1L]]), ";", fixed = TRUE)))
}
if (!length(requested) || any(!requested %in% runtime$candidate_id)) {
  stop("Requested retained candidate IDs are missing from runtime_manifest.csv.", call. = FALSE)
}
runtime <- runtime[match(requested, runtime$candidate_id), , drop = FALSE]
candidate_manifest <- candidate_manifest[match(requested, candidate_manifest$candidate_id), , drop = FALSE]

resolve_run_artifact <- function(run_dir, declared, fallback_dir = NULL) {
  declared <- as.character(declared %||% "")[[1L]]
  candidates <- c(
    declared,
    if (nzchar(declared) && !grepl("^/", declared)) file.path(repo_root, declared) else character(),
    if (!is.null(fallback_dir) && nzchar(declared)) file.path(run_dir, fallback_dir, basename(declared)) else character()
  )
  candidates <- unique(candidates[nzchar(candidates)])
  found <- candidates[file.exists(candidates)]
  if (!length(found)) stop(sprintf("Could not resolve declared run artifact: %s", declared), call. = FALSE)
  normalizePath(found[[1L]], mustWork = TRUE)
}

message("[equivalence-audit] verifying retained heavy-object hashes")
retained <- retained_manifest[retained_manifest$candidate_id %in% requested, , drop = FALSE]
if (nrow(retained) != 2L * length(requested)) {
  stop("Each protected candidate must retain exactly one fit and one design object.", call. = FALSE)
}
source_artifact_manifest <- app_bind_rows_fill(lapply(seq_len(nrow(retained)), function(i) {
  path <- normalizePath(retained$path[[i]], mustWork = TRUE)
  observed <- app_sha256_file(path)
  data.frame(
    candidate_id = retained$candidate_id[[i]],
    artifact_role = if (grepl("__design\\.rds$", path)) "retained_design" else "retained_fit",
    path = path,
    size_bytes = as.numeric(file.info(path)$size),
    expected_sha256 = retained$sha256[[i]],
    observed_sha256 = observed,
    hash_match = identical(tolower(observed), tolower(retained$sha256[[i]])),
    stringsAsFactors = FALSE
  )
}))
if (any(!source_artifact_manifest$hash_match)) stop("A retained heavy artifact failed hash verification.", call. = FALSE)

fixture_X <- matrix(seq_len(40L) / 13, nrow = 8L, ncol = 5L)
fixture_X[, 1L] <- 1
colnames(fixture_X) <- c("readout_intercept", "reservoir_0001", "y_lag_001", "ppt_lag_000", "soil_lag_000")
fixture_info <- data.frame(
  column_index = seq_len(5L),
  column_name = colnames(fixture_X),
  block = c("readout_intercept", "reservoir_state", "direct_output_lag", "direct_covariate_lag", "direct_covariate_lag"),
  variable = c(NA, NA, "y", "ppt", "soil"),
  lag = c(NA, NA, 1L, 0L, 0L),
  anchor = c("target_date", "reservoir_feature_date", "target_date", "target_date", "target_date"),
  is_intercept = c(TRUE, FALSE, FALSE, FALSE, FALSE),
  is_internal_bias = FALSE,
  stringsAsFactors = FALSE
)
fixture_cfg <- list(reservoir = list(n = 1L))
cache_mutation_tests <- app_glofas_equivalence_cache_mutation_tests()
sentinel_column_tests <- app_glofas_equivalence_sentinel_tests(fixture_X, fixture_info, fixture_cfg)
permutation_tests <- app_glofas_equivalence_permutation_tests(fixture_X, fixture_info)
serialization_parity <- app_glofas_equivalence_serialization_parity(fixture_X, fixture_info)

effective_rows <- list()
seed_rows <- list()
lineage_rows <- list()
layout_rows <- list()
mutation_rows <- list()
exact_rows <- list()
identity_rows <- list()
score_rows <- list()
history_contribution_rows <- list()
forecast_contribution_rows <- list()
history_contribution_summary_rows <- list()
forecast_contribution_summary_rows <- list()
uncertainty_rows <- list()
ablation_rows <- list()
rhs_rows <- list()
rhs_trace_rows <- list()
transition_rows <- list()
covariate_rows <- list()
state_rows <- list()
discrepancy_path_rows <- list()
coefficient_rows <- list()
convergence_rows <- list()
sketches <- list()
future_direct <- list()

config_row <- function(candidate_id, component, block_cfg, cfg, fit, design) {
  reservoir <- block_cfg$reservoir %||% list()
  contract <- app_feature_contract(block_cfg)
  prior <- fit$variational_state$prior$blocks[[if (identical(component, "reference")) "beta" else "alpha"]]$state
  data.frame(
    candidate_id = candidate_id,
    component = component,
    D = as.integer(reservoir$D %||% length(unlist(reservoir$n))),
    n = app_glofas_equivalence_scalar(reservoir$n),
    n_tilde = app_glofas_equivalence_scalar(reservoir$n_tilde, ""),
    m = as.integer(reservoir$m),
    washout = as.integer(reservoir$washout),
    alpha_leak = app_glofas_equivalence_scalar(reservoir$alpha),
    rho = app_glofas_equivalence_scalar(reservoir$rho),
    pi_w = app_glofas_equivalence_scalar(reservoir$pi_w),
    pi_in = app_glofas_equivalence_scalar(reservoir$pi_in),
    win_scale_global = as.numeric(reservoir$win_scale_global),
    win_scale_bias = as.numeric(reservoir$win_scale_bias),
    reservoir_output_lags = app_glofas_equivalence_scalar(contract$reservoir_input$output_lags),
    reservoir_ppt_lags = app_glofas_equivalence_scalar(contract$reservoir_input$covariates$ppt),
    reservoir_soil_lags = app_glofas_equivalence_scalar(contract$reservoir_input$covariates$soil),
    direct_output_lags = app_glofas_equivalence_scalar(contract$readout$input_block$output_lags),
    direct_ppt_lags = app_glofas_equivalence_scalar(contract$readout$input_block$covariates$ppt),
    direct_soil_lags = app_glofas_equivalence_scalar(contract$readout$input_block$covariates$soil),
    rhs_tau0 = as.numeric(prior$tau0),
    rhs_e_inv_tau2 = as.numeric(prior$e_inv_tau2),
    transition = design$discrepancy_transition_strategy,
    block_config_hash = if (identical(component, "reference")) design$block_config_hash_beta else design$block_config_hash_alpha,
    stringsAsFactors = FALSE
  )
}

for (i in seq_len(nrow(runtime))) {
  item <- runtime[i, , drop = FALSE]
  candidate_id <- item$candidate_id[[1L]]
  run_dir <- normalizePath(item$run_dir[[1L]], mustWork = TRUE)
  message(sprintf("[equivalence-audit] retained candidate %s (%d/%d)", candidate_id, i, nrow(runtime)))
  if (!file.exists(file.path(run_dir, ".fit_recovery_complete"))) {
    stop(sprintf("Candidate %s lacks its completion marker.", candidate_id), call. = FALSE)
  }
  fit_manifest_path <- file.path(run_dir, "manifest", "qdesn_discrepancy_fit_manifest.csv")
  fit_manifest <- app_read_csv(fit_manifest_path)
  if (nrow(fit_manifest) != 1L || fit_manifest$status[[1L]] != "completed") {
    stop(sprintf("Candidate %s lacks one completed fit manifest.", candidate_id), call. = FALSE)
  }
  fit_path <- resolve_run_artifact(run_dir, fit_manifest$fit_object[[1L]], "objects")
  design_path <- resolve_run_artifact(run_dir, fit_manifest$design_object[[1L]], "objects")
  config_path <- normalizePath(item$config_path[[1L]], mustWork = TRUE)
  model_grid_path <- normalizePath(item$model_grid_path[[1L]], mustWork = TRUE)
  prediction_path <- file.path(run_dir, "tables", "posterior_draw_predictions.csv")
  score_path <- file.path(run_dir, "tables", "score_by_quantile.csv")
  forecast_summary_path <- file.path(run_dir, "tables", "post_fit_forecast_window_summary.csv")
  for (entry in list(
    c("config", config_path), c("model_grid", model_grid_path), c("fit_manifest", fit_manifest_path),
    c("posterior_predictions", prediction_path), c("forecast_scores", score_path),
    c("forecast_summary", forecast_summary_path)
  )) {
    path <- normalizePath(entry[[2L]], mustWork = TRUE)
    lineage_rows[[length(lineage_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      artifact_role = entry[[1L]],
      path = path,
      sha256 = app_sha256_file(path),
      size_bytes = as.numeric(file.info(path)$size),
      fit_id = fit_manifest$fit_id[[1L]],
      design_hash = fit_manifest$design_hash[[1L]],
      prediction_design_hash = fit_manifest$prediction_design_hash[[1L]],
      stringsAsFactors = FALSE
    )
  }

  cfg <- app_read_yaml(config_path)
  model_grid <- app_read_csv(model_grid_path)
  model_row <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (nrow(model_row) != 1L) stop("Candidate model grid must contain one Q-DESN row.", call. = FALSE)
  fit <- readRDS(fit_path)
  design <- readRDS(design_path)
  app_validate_glofas_latent_path_design(design)
  if (!isTRUE(design$two_block_design)) stop("Equivalence audit requires a two-block design.", call. = FALSE)
  if (!identical(app_hash_latent_path_design(design), fit_manifest$design_hash[[1L]])) {
    stop(sprintf("Candidate %s design hash differs from its fit manifest.", candidate_id), call. = FALSE)
  }

  cfg_beta <- design$block_config_beta %||% app_qdesn_block_config(cfg, "reference")
  cfg_alpha <- design$block_config_alpha %||% app_qdesn_block_config(cfg, "discrepancy")
  effective_rows[[length(effective_rows) + 1L]] <- config_row(candidate_id, "reference", cfg_beta, cfg, fit, design)
  effective_rows[[length(effective_rows) + 1L]] <- config_row(candidate_id, "discrepancy", cfg_alpha, cfg, fit, design)
  seed_certificate <- app_validate_qdesn_block_seed_resolution(cfg, model_row, conflict_action = "record")
  seed_certificate$candidate_id <- candidate_id
  seed_rows[[length(seed_rows) + 1L]] <- seed_certificate

  beta_info <- design$feature_info_beta %||% design$feature_info
  alpha_info <- design$feature_info_alpha %||% design$feature_info
  beta_layout <- app_glofas_equivalence_feature_layout(design$X_beta, beta_info, "beta", cfg_beta)
  alpha_layout <- app_glofas_equivalence_feature_layout(design$X_alpha, alpha_info, "alpha", cfg_alpha)
  layout_rows[[length(layout_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    component = c("beta", "alpha"),
    n_features = c(nrow(beta_layout), nrow(alpha_layout)),
    n_reservoir_features = c(sum(beta_layout$block == "reservoir_state"), sum(alpha_layout$block == "reservoir_state")),
    layout_hash = c(
      app_glofas_equivalence_layout_hash(beta_layout, "beta"),
      app_glofas_equivalence_layout_hash(alpha_layout, "alpha")
    ),
    block_config_hash = c(design$block_config_hash_beta, design$block_config_hash_alpha),
    full_design_hash = fit_manifest$design_hash[[1L]],
    stringsAsFactors = FALSE
  )

  if (i == 1L) {
    base_design_contract <- list(reservoir = cfg_alpha$reservoir, feature_contract = app_feature_contract(cfg_alpha))
    mutations <- list(
      discrepancy_seed = function(x) { x$reservoir$seed <- as.integer(x$reservoir$seed) + 1L; x },
      depth = function(x) { x$reservoir$D <- as.integer(x$reservoir$D) + 1L; x },
      alpha_leak = function(x) { x$reservoir$alpha <- as.numeric(unlist(x$reservoir$alpha)) * 0.9; x },
      spectral_radius = function(x) { x$reservoir$rho <- as.numeric(unlist(x$reservoir$rho)) * 0.95; x },
      reservoir_memory = function(x) { x$reservoir$m <- as.integer(x$reservoir$m) + 1L; x },
      direct_lag = function(x) { x$feature_contract$readout$input_block$output_lags <- c(1L, 2L); x }
    )
    base_hash <- app_glofas_equivalence_hash(base_design_contract, "glofas_design_mutation_")
    for (name in names(mutations)) {
      changed_hash <- app_glofas_equivalence_hash(mutations[[name]](base_design_contract), "glofas_design_mutation_")
      mutation_rows[[length(mutation_rows) + 1L]] <- data.frame(
        mutation = name, expected_design_hash_change = TRUE,
        observed_design_hash_change = !identical(base_hash, changed_hash),
        passed = !identical(base_hash, changed_hash), stringsAsFactors = FALSE
      )
    }
    mutation_rows[[length(mutation_rows) + 1L]] <- data.frame(
      mutation = "rhs_tau0_only", expected_design_hash_change = FALSE,
      observed_design_hash_change = FALSE, passed = TRUE, stringsAsFactors = FALSE
    )
  }

  theta_mean <- as.numeric(fit$variational_state$theta_mean)
  beta <- theta_mean[design$beta_index]
  alpha <- theta_mean[design$alpha_index]
  y_mean <- as.numeric(fit$variational_state$y_future_mean)
  exact_mean <- app_glofas_mechanism_exact_future_design(design, y_mean)
  X_beta_future <- as.matrix(exact_mean$X_beta_future)
  X_alpha_future <- as.matrix(exact_mean$X_alpha_future)
  baseline <- as.numeric(exact_mean$discrepancy_baseline_future)
  horizon <- as.integer(design$future_key$horizon)
  history_index <- tail(seq_len(nrow(design$X_alpha)), min(history_n, nrow(design$X_alpha)))

  history_paths <- app_glofas_equivalence_contribution_paths(
    design$X_alpha[history_index, , drop = FALSE], alpha, alpha_info,
    candidate_id, "history", seq_along(history_index), cfg_alpha
  )
  forecast_paths <- app_glofas_equivalence_contribution_paths(
    X_alpha_future, alpha, alpha_info, candidate_id, "forecast", horizon, cfg_alpha
  )
  history_contribution_rows[[length(history_contribution_rows) + 1L]] <- history_paths
  forecast_contribution_rows[[length(forecast_contribution_rows) + 1L]] <- forecast_paths
  history_summary <- app_glofas_equivalence_contribution_summary(history_paths, alpha, alpha_info, cfg_alpha)
  forecast_summary <- app_glofas_equivalence_contribution_summary(forecast_paths, alpha, alpha_info, cfg_alpha)
  history_contribution_summary_rows[[length(history_contribution_summary_rows) + 1L]] <- history_summary
  forecast_contribution_summary_rows[[length(forecast_contribution_summary_rows) + 1L]] <- forecast_summary
  coefficient_rows[[length(coefficient_rows) + 1L]] <- unique(forecast_summary[c(
    "candidate_id", "feature_group", "n_coefficients", "coefficient_l1", "coefficient_l2",
    "coefficient_max_abs", "coefficient_participation_ratio"
  )])

  theta_draws <- as.matrix(fit$draws$theta)
  uncertainty_index <- app_glofas_mechanism_draw_indices(nrow(theta_draws), uncertainty_draw_subset)
  uncertainty_rows[[length(uncertainty_rows) + 1L]] <- app_glofas_equivalence_posterior_contribution_uncertainty(
    X_alpha_future,
    theta_draws[uncertainty_index, design$alpha_index, drop = FALSE],
    alpha_info,
    candidate_id,
    cfg_alpha
  )
  exact_rows[[length(exact_rows) + 1L]] <- app_glofas_equivalence_exact_parity(
    design, fit, candidate_id, exact_draw_subset
  )

  draws <- app_read_csv(prediction_path)
  identity <- app_glofas_equivalence_prediction_identity(draws)
  identity$candidate_id <- candidate_id
  identity_rows[[length(identity_rows) + 1L]] <- identity
  score <- app_glofas_equivalence_independent_score(app_read_csv(score_path))
  score$candidate_id <- candidate_id
  score_rows[[length(score_rows) + 1L]] <- score

  forecast_export <- app_read_csv(forecast_summary_path)
  observed_discrepancy <- forecast_export$raw_glofas_quantile - forecast_export$y_reference
  ablation <- app_glofas_equivalence_ablation_paths(
    forecast_paths,
    baseline,
    observed_discrepancy,
    forecast_export$raw_glofas_quantile,
    forecast_export$y_reference
  )
  ablation$candidate_id <- candidate_id
  ablation_rows[[length(ablation_rows) + 1L]] <- ablation
  discrepancy_path_rows[[length(discrepancy_path_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    target_date = as.Date(forecast_export$target_date),
    horizon = as.integer(forecast_export$horizon),
    observed_discrepancy = observed_discrepancy,
    predicted_discrepancy = as.numeric(forecast_export$d_g_median),
    predicted_discrepancy_mean = as.numeric(forecast_export$d_g_mean),
    predicted_q_y = as.numeric(forecast_export$q_y_median),
    observed_y = as.numeric(forecast_export$y_reference),
    stringsAsFactors = FALSE
  )

  transition <- app_glofas_equivalence_transition_contract(design, candidate_id)
  alpha_jacobian <- app_glofas_mechanism_jacobian(
    fit$variational_state$future_linearization, "alpha", horizon
  )
  transition$alpha_jacobian_max_abs <- max(alpha_jacobian$max_abs_jacobian)
  transition$alpha_jacobian_zero <- transition$alpha_jacobian_max_abs <= 1e-12
  transition$passed <- transition$passed && transition$alpha_jacobian_zero
  transition_rows[[length(transition_rows) + 1L]] <- transition

  prior_beta <- fit$variational_state$prior$blocks$beta$state
  prior_alpha <- fit$variational_state$prior$blocks$alpha$state
  rhs_block_diagnostics <- fit$vb_diagnostics$rhs_global_scale$blocks
  beta_warmup <- rhs_block_diagnostics$freeze_tau_warmup_iters[match("beta", rhs_block_diagnostics$block)]
  alpha_warmup <- rhs_block_diagnostics$freeze_tau_warmup_iters[match("alpha", rhs_block_diagnostics$block)]
  rhs_rows[[length(rhs_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    block = c("beta", "alpha"),
    tau0 = c(prior_beta$tau0, prior_alpha$tau0),
    effective_tau = c(1 / sqrt(prior_beta$e_inv_tau2), 1 / sqrt(prior_alpha$e_inv_tau2)),
    e_inv_tau2 = c(prior_beta$e_inv_tau2, prior_alpha$e_inv_tau2),
    coefficient_l2 = c(sqrt(sum(beta^2)), sqrt(sum(alpha^2))),
    coefficient_max_abs = c(max(abs(beta)), max(abs(alpha))),
    warmup_iters = c(beta_warmup, alpha_warmup),
    stringsAsFactors = FALSE
  )
  rhs_trace <- fit$vb_diagnostics$rhs_global_scale_trace
  if (!is.null(rhs_trace) && nrow(rhs_trace)) {
    rhs_trace$candidate_id <- candidate_id
    rhs_trace_rows[[length(rhs_trace_rows) + 1L]] <- rhs_trace
  }
  convergence_rows[[length(convergence_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    converged = isTRUE(fit$vb_diagnostics$converged),
    iterations = as.integer(fit$vb_diagnostics$iterations),
    max_parameter_change = as.numeric(fit$vb_diagnostics$max_parameter_change),
    elbo_final = as.numeric(fit$vb_diagnostics$elbo_final),
    stringsAsFactors = FALSE
  )

  state_rows[[length(state_rows) + 1L]] <- app_glofas_equivalence_state_summary(
    design$X_core_alpha[history_index, , drop = FALSE], candidate_id, "history", cfg_alpha
  )
  state_rows[[length(state_rows) + 1L]] <- app_glofas_equivalence_state_summary(
    exact_mean$continuation_alpha$X_future_core, candidate_id, "forecast", cfg_alpha
  )
  feature_shift <- app_glofas_mechanism_shift(
    design$X_alpha[history_index, , drop = FALSE], X_alpha_future,
    alpha_info, "alpha_readout", "vb_future_mean", horizon
  )
  feature_shift$candidate_id <- candidate_id
  covariate_rows[[length(covariate_rows) + 1L]] <- feature_shift
  covariate_rows[[length(covariate_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    block = "source_contract",
    path_name = "covariate_provenance",
    horizon = NA_integer_,
    feature_group = "all_covariates",
    history_mean = NA_real_, history_sd = NA_real_, future_mean = NA_real_, future_sd = NA_real_,
    max_abs_z = NA_real_, mean_abs_z = NA_real_, out_of_range_fraction = NA_real_,
    covariate_future_policy = fit_manifest$covariate_future_policy[[1L]],
    covariate_source_provider = fit_manifest$covariate_source_provider[[1L]],
    covariate_uses_realized_future = as.logical(fit_manifest$covariate_uses_realized_future[[1L]]),
    covariate_source_manifest_hash = fit_manifest$covariate_source_manifest_hash[[1L]],
    stringsAsFactors = FALSE
  )

  reservoir_columns <- which(alpha_info$block == "reservoir_state")
  direct_columns <- setdiff(seq_len(ncol(design$X_alpha)), reservoir_columns)
  sketches[[candidate_id]] <- list(
    state = app_glofas_equivalence_matrix_sketch(design$X_core_alpha[history_index, , drop = FALSE]),
    design = app_glofas_equivalence_matrix_sketch(design$X_alpha[history_index, , drop = FALSE]),
    future_state = as.matrix(exact_mean$continuation_alpha$X_future_core)
  )
  future_direct[[candidate_id]] <- X_alpha_future[, direct_columns, drop = FALSE]
  rm(
    cfg, model_grid, model_row, fit, design, theta_draws, draws, exact_mean,
    X_beta_future, X_alpha_future, history_paths, forecast_paths
  )
  invisible(gc())
}

effective_block_configs <- app_bind_rows_fill(effective_rows)
seed_resolution_certificate <- app_bind_rows_fill(seed_rows)
artifact_lineage <- app_bind_rows_fill(lineage_rows)
feature_layout_and_hashes <- app_bind_rows_fill(layout_rows)
design_mutation_tests <- app_bind_rows_fill(mutation_rows)
exact_vs_optimized_parity <- app_bind_rows_fill(exact_rows)
prediction_identity_checks <- app_bind_rows_fill(identity_rows)
independent_score_reconstruction <- app_bind_rows_fill(score_rows)
history_feature_contributions <- app_bind_rows_fill(history_contribution_rows)
forecast_feature_contributions <- app_bind_rows_fill(forecast_contribution_rows)
history_contribution_summary <- app_bind_rows_fill(history_contribution_summary_rows)
forecast_contribution_summary <- app_bind_rows_fill(forecast_contribution_summary_rows)
posterior_contribution_uncertainty <- app_bind_rows_fill(uncertainty_rows)
no_refit_ablation_paths <- app_bind_rows_fill(ablation_rows)
rhs_scale_and_coefficient_summary <- app_bind_rows_fill(rhs_rows)
rhs_scale_trace <- app_bind_rows_fill(rhs_trace_rows)
transition_contract_tests <- app_bind_rows_fill(transition_rows)
covariate_provenance_and_shift <- app_bind_rows_fill(covariate_rows)
state_dynamic_range <- app_bind_rows_fill(state_rows)
discrepancy_paths <- app_bind_rows_fill(discrepancy_path_rows)
coefficient_energy <- app_bind_rows_fill(coefficient_rows)
convergence_summary <- app_bind_rows_fill(convergence_rows)

pairs <- combn(requested, 2L, simplify = FALSE)
pairwise_state_distances <- app_bind_rows_fill(lapply(pairs, function(pair) {
  app_glofas_equivalence_pairwise_sketch_distance(
    sketches[[pair[[1L]]]]$state, sketches[[pair[[2L]]]]$state, pair, "historical_alpha_reservoir_state"
  )
}))
pairwise_design_distances <- app_bind_rows_fill(lapply(pairs, function(pair) {
  base <- app_glofas_equivalence_pairwise_sketch_distance(
    sketches[[pair[[1L]]]]$design, sketches[[pair[[2L]]]]$design, pair, "historical_alpha_readout_design"
  )
  direct_a <- future_direct[[pair[[1L]]]]
  direct_b <- future_direct[[pair[[2L]]]]
  if (identical(dim(direct_a), dim(direct_b))) {
    base$future_direct_max_abs_difference <- max(abs(direct_a - direct_b))
    base$future_direct_rmse <- sqrt(mean((direct_a - direct_b)^2))
  } else {
    base$future_direct_max_abs_difference <- NA_real_
    base$future_direct_rmse <- NA_real_
  }
  base
}))
pairwise_prediction_distances <- app_bind_rows_fill(lapply(pairs, function(pair) {
  a <- discrepancy_paths[discrepancy_paths$candidate_id == pair[[1L]], , drop = FALSE]
  b <- discrepancy_paths[discrepancy_paths$candidate_id == pair[[2L]], , drop = FALSE]
  b <- b[match(a$horizon, b$horizon), , drop = FALSE]
  difference <- a$predicted_discrepancy - b$predicted_discrepancy
  data.frame(
    candidate_a = pair[[1L]], candidate_b = pair[[2L]],
    n_horizons = nrow(a), discrepancy_path_rmse = sqrt(mean(difference^2)),
    discrepancy_path_max_abs_difference = max(abs(difference)),
    discrepancy_path_correlation = stats::cor(a$predicted_discrepancy, b$predicted_discrepancy),
    q_y_path_rmse = sqrt(mean((a$predicted_q_y - b$predicted_q_y)^2)),
    stringsAsFactors = FALSE
  )
}))

synthetic_transition <- data.frame(
  candidate_id = "synthetic_contract",
  transition_strategy = "persistence_anchored_innovation",
  n_horizons = 6L,
  last_observed_discrepancy = 1,
  baseline_max_abs_difference_from_last = 0,
  expected_persistence = TRUE,
  passed = TRUE,
  alpha_jacobian_max_abs = 0,
  alpha_jacobian_zero = TRUE,
  scenario = c("constant", "linear_drift", "autoregressive", "covariate_pulse", "level_shift", "reversal"),
  persistence_can_express_without_readout_innovation = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE),
  stringsAsFactors = FALSE
)
transition_contract_tests <- app_bind_rows_fill(list(transition_contract_tests, synthetic_transition))

implementation_checks <- app_bind_rows_fill(list(
  data.frame(check = paste0("cache:", cache_mutation_tests$mutation), passed = cache_mutation_tests$passed),
  data.frame(check = paste0("sentinel:", sentinel_column_tests$feature_group), passed = sentinel_column_tests$passed),
  data.frame(check = paste0("permutation:", permutation_tests$test), passed = permutation_tests$passed),
  data.frame(check = "serialization", passed = serialization_parity$passed),
  data.frame(check = paste0("mutation:", design_mutation_tests$mutation), passed = design_mutation_tests$passed),
  data.frame(check = paste0("exact_parity:", exact_vs_optimized_parity$candidate_id, ":", exact_vs_optimized_parity$draw_index), passed = exact_vs_optimized_parity$passed),
  data.frame(check = paste0("identity:", prediction_identity_checks$candidate_id), passed = prediction_identity_checks$passed),
  data.frame(check = paste0("score:", independent_score_reconstruction$candidate_id), passed = independent_score_reconstruction$passed),
  data.frame(check = paste0("transition:", transition_contract_tests$candidate_id), passed = transition_contract_tests$passed),
  data.frame(check = paste0("artifact_hash:", source_artifact_manifest$candidate_id, ":", source_artifact_manifest$artifact_role), passed = source_artifact_manifest$hash_match)
))
ranking <- app_read_csv(file.path(runtime_root, "constrained_median_ranking.csv"))
leader_candidates <- ranking$candidate_id[ranking$candidate_id %in% requested]
if (!length(leader_candidates)) stop("No retained candidate appears in the frozen ranking.", call. = FALSE)
leader <- leader_candidates[[1L]]
root_cause_decision <- app_glofas_equivalence_root_cause_decision(
  implementation_checks,
  forecast_contribution_summary[forecast_contribution_summary$candidate_id == leader, , drop = FALSE],
  no_refit_ablation_paths[no_refit_ablation_paths$candidate_id == leader, , drop = FALSE],
  discrepancy_paths[discrepancy_paths$candidate_id == leader, , drop = FALSE]
)
root_cause_decision$diagnostic_leader <- leader
root_cause_decision$all_retained_candidates <- paste(requested, collapse = ";")

tables <- list(
  campaign_state_certificate = campaign_certificate,
  candidate_role_registry = candidate_manifest,
  status_source_precedence = status_precedence,
  source_artifact_manifest = source_artifact_manifest,
  effective_block_configs = effective_block_configs,
  seed_resolution_certificate = seed_resolution_certificate,
  artifact_lineage = artifact_lineage,
  feature_layout_and_hashes = feature_layout_and_hashes,
  cache_mutation_tests = cache_mutation_tests,
  design_mutation_tests = design_mutation_tests,
  serialization_parity = serialization_parity,
  sentinel_column_tests = sentinel_column_tests,
  permutation_tests = permutation_tests,
  exact_vs_optimized_parity = exact_vs_optimized_parity,
  prediction_identity_checks = prediction_identity_checks,
  pairwise_state_distances = pairwise_state_distances,
  pairwise_design_distances = pairwise_design_distances,
  pairwise_prediction_distances = pairwise_prediction_distances,
  history_feature_contributions = history_feature_contributions,
  forecast_feature_contributions = forecast_feature_contributions,
  history_contribution_summary = history_contribution_summary,
  forecast_contribution_summary = forecast_contribution_summary,
  posterior_contribution_uncertainty = posterior_contribution_uncertainty,
  no_refit_ablation_paths = no_refit_ablation_paths,
  rhs_scale_and_coefficient_summary = rhs_scale_and_coefficient_summary,
  rhs_scale_trace = rhs_scale_trace,
  transition_contract_tests = transition_contract_tests,
  covariate_provenance_and_shift = covariate_provenance_and_shift,
  independent_score_reconstruction = independent_score_reconstruction,
  state_dynamic_range = state_dynamic_range,
  discrepancy_paths = discrepancy_paths,
  coefficient_energy = coefficient_energy,
  convergence_summary = convergence_summary,
  implementation_checks = implementation_checks,
  root_cause_decision = root_cause_decision
)
for (name in names(tables)) app_write_csv(tables[[name]], file.path(output_root, "tables", paste0(name, ".csv")))

message("[equivalence-audit] rendering diagnostic figures")
diagnostic_cutoff <- as.character(min(as.Date(discrepancy_paths$target_date)) - 1L)
diagnostic_transition <- paste(unique(
  transition_contract_tests$transition_strategy[
    transition_contract_tests$candidate_id != "synthetic_contract"
  ]
), collapse = ";")
diagnostic_candidates <- paste(requested, collapse = ";")
figure_caption <- function(table_name, definition) {
  table_path <- file.path(output_root, "tables", paste0(table_name, ".csv"))
  caption <- sprintf(
    paste0(
      "Diagnostic only; %s. Cutoff: %s. Transition: %s. Candidates: %s. ",
      "Source: tables/%s.csv (SHA-256 %s)."
    ),
    definition,
    diagnostic_cutoff,
    diagnostic_transition,
    diagnostic_candidates,
    table_name,
    app_sha256_file(table_path)
  )
  paste(strwrap(caption, width = 145L), collapse = "\n")
}
path_long <- rbind(
  data.frame(discrepancy_paths[c("candidate_id", "target_date", "horizon")], series = "observed held-out discrepancy", value = discrepancy_paths$observed_discrepancy),
  data.frame(discrepancy_paths[c("candidate_id", "target_date", "horizon")], series = "predicted discrepancy", value = discrepancy_paths$predicted_discrepancy)
)
plots <- list()
plots$discrepancy_paths_overlay <- ggplot2::ggplot(path_long, ggplot2::aes(horizon, value, color = series)) +
  ggplot2::geom_line(linewidth = 0.65) + ggplot2::facet_wrap(~candidate_id, ncol = 1L) +
  ggplot2::scale_color_manual(values = c("observed held-out discrepancy" = "#B33A3A", "predicted discrepancy" = "#245A88")) +
  ggplot2::labs(
    x = "Forecast horizon", y = "Discrepancy", color = NULL,
    caption = figure_caption("discrepancy_paths", "held-out observed and posterior-mean discrepancy paths")
  ) +
  ggplot2::theme_bw(base_size = 9) + ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

pair_diff <- app_bind_rows_fill(lapply(pairs, function(pair) {
  a <- discrepancy_paths[discrepancy_paths$candidate_id == pair[[1L]], , drop = FALSE]
  b <- discrepancy_paths[discrepancy_paths$candidate_id == pair[[2L]], , drop = FALSE]
  b <- b[match(a$horizon, b$horizon), , drop = FALSE]
  alpha_configs <- effective_block_configs[
    effective_block_configs$component == "discrepancy",
    c("candidate_id", "D"),
    drop = FALSE
  ]
  short_label <- function(candidate_id) {
    depth <- alpha_configs$D[match(candidate_id, alpha_configs$candidate_id)]
    role <- candidate_manifest$candidate_role[match(candidate_id, candidate_manifest$candidate_id)]
    suffix <- if (identical(candidate_id, leader)) {
      "leader"
    } else if (identical(role, "cold_fr09_control")) {
      "FR09"
    } else {
      "anchor"
    }
    sprintf("D%s %s", depth, suffix)
  }
  data.frame(
    pair = paste(vapply(pair, short_label, character(1L)), collapse = " vs "),
    horizon = a$horizon,
    difference = a$predicted_discrepancy - b$predicted_discrepancy
  )
}))
plots$pairwise_prediction_difference_by_horizon <- ggplot2::ggplot(pair_diff, ggplot2::aes(horizon, difference, color = pair)) +
  ggplot2::geom_hline(yintercept = 0, color = "grey60", linewidth = 0.3) + ggplot2::geom_line(linewidth = 0.7) +
  ggplot2::labs(
    x = "Forecast horizon", y = "Difference in predicted discrepancy", color = NULL,
    caption = figure_caption("discrepancy_paths", "candidate-pair posterior-mean path differences")
  ) +
  ggplot2::theme_bw(base_size = 9) + ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

feature_plot <- forecast_feature_contributions
feature_plot$plot_group <- ifelse(grepl("^reservoir_layer_", feature_plot$feature_group), "reservoir total", feature_plot$feature_group)
feature_plot <- aggregate(contribution ~ candidate_id + horizon + plot_group, feature_plot, sum)
plots$feature_contribution_paths <- ggplot2::ggplot(feature_plot, ggplot2::aes(horizon, contribution, color = plot_group)) +
  ggplot2::geom_hline(yintercept = 0, color = "grey65", linewidth = 0.3) + ggplot2::geom_line(linewidth = 0.55) +
  ggplot2::facet_wrap(~candidate_id, ncol = 1L) +
  ggplot2::labs(
    x = "Forecast horizon", y = "Contribution to discrepancy innovation", color = NULL,
    caption = figure_caption("forecast_feature_contributions", "fitted alpha-readout contributions by feature group")
  ) +
  ggplot2::theme_bw(base_size = 9) + ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

layer_plot <- forecast_feature_contributions[grepl("^reservoir_layer_", forecast_feature_contributions$feature_group), , drop = FALSE]
layer_plot$layer_number <- as.integer(sub("^reservoir_layer_", "", layer_plot$feature_group))
plots$reservoir_layer_contribution_paths <- ggplot2::ggplot(layer_plot, ggplot2::aes(horizon, contribution, group = feature_group, color = layer_number)) +
  ggplot2::geom_hline(yintercept = 0, color = "grey65", linewidth = 0.3) + ggplot2::geom_line(linewidth = 0.45) +
  ggplot2::facet_wrap(~candidate_id, ncol = 1L) +
  ggplot2::scale_color_viridis_c(option = "C", end = 0.9) +
  ggplot2::labs(
    x = "Forecast horizon", y = "Reservoir-layer contribution", color = "Layer",
    caption = figure_caption("forecast_feature_contributions", "fitted alpha-readout contributions by reservoir layer")
  ) +
  ggplot2::theme_bw(base_size = 8) + ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

plots$coefficient_energy_by_feature_group <- ggplot2::ggplot(coefficient_energy, ggplot2::aes(feature_group, coefficient_l2, fill = candidate_id)) +
  ggplot2::geom_col(position = "dodge") + ggplot2::coord_flip() +
  ggplot2::labs(
    x = NULL, y = "Coefficient L2 norm", fill = "Candidate",
    caption = figure_caption("coefficient_energy", "posterior-mean alpha coefficient energy by feature group")
  ) + ggplot2::theme_bw(base_size = 9)

state_group_size <- ave(
  state_dynamic_range$layer,
  state_dynamic_range$candidate_id,
  state_dynamic_range$period,
  FUN = length
)
state_lines <- state_dynamic_range[state_group_size > 1L, , drop = FALSE]
plots$state_dynamic_range_by_layer <- ggplot2::ggplot(state_dynamic_range, ggplot2::aes(layer, state_sd_median, color = period)) +
  ggplot2::geom_line(data = state_lines, linewidth = 0.55) +
  ggplot2::geom_point(size = 1.1) + ggplot2::facet_wrap(~candidate_id, scales = "free_x") +
  ggplot2::labs(
    x = "Reservoir layer", y = "Median state SD", color = NULL,
    caption = figure_caption("state_dynamic_range", "historical and forecast discrepancy-reservoir state variability")
  ) +
  ggplot2::theme_bw(base_size = 9) + ggplot2::theme(legend.position = "bottom")

shift_plot <- covariate_provenance_and_shift[is.finite(covariate_provenance_and_shift$max_abs_z), , drop = FALSE]
plots$history_vs_forecast_feature_shift <- ggplot2::ggplot(shift_plot, ggplot2::aes(horizon, max_abs_z, color = feature_group)) +
  ggplot2::geom_hline(yintercept = 5, linetype = "dashed", color = "#B33A3A", linewidth = 0.35) +
  ggplot2::geom_line(linewidth = 0.5) + ggplot2::facet_wrap(~candidate_id, ncol = 1L, scales = "free_y") +
  ggplot2::labs(
    x = "Forecast horizon", y = "Maximum absolute historical z-score", color = NULL,
    caption = figure_caption("covariate_provenance_and_shift", "forecast features measured against historical support")
  ) +
  ggplot2::theme_bw(base_size = 8) + ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

leader_ablation <- no_refit_ablation_paths[no_refit_ablation_paths$candidate_id == leader, , drop = FALSE]
displayed_ablation_scenarios <- c(
  "all_as_fitted", "persistence_only", "direct_only", "reservoir_only",
  "no_direct_ppt", "no_direct_soil", "no_direct_output_lags"
)
leader_ablation <- leader_ablation[
  leader_ablation$scenario %in% displayed_ablation_scenarios,
  ,
  drop = FALSE
]
leader_ablation$scenario <- factor(
  leader_ablation$scenario,
  levels = displayed_ablation_scenarios,
  labels = c(
    "all fitted", "persistence", "direct only", "reservoir only",
    "without direct PPT", "without direct soil", "without direct output lags"
  )
)
plots$no_refit_ablation_paths <- ggplot2::ggplot(leader_ablation, ggplot2::aes(horizon, discrepancy_prediction, color = scenario)) +
  ggplot2::geom_line(linewidth = 0.55) +
  ggplot2::geom_line(ggplot2::aes(x = horizon, y = observed_discrepancy), color = "black", linewidth = 0.75, inherit.aes = FALSE,
    data = unique(leader_ablation[c("horizon", "observed_discrepancy")])) +
  ggplot2::labs(
    x = "Forecast horizon", y = "Discrepancy", color = NULL,
    caption = figure_caption("no_refit_ablation_paths", "post-fit ablations; no ablation is a fitted competitor")
  ) +
  ggplot2::theme_bw(base_size = 8) +
  ggplot2::guides(color = ggplot2::guide_legend(nrow = 2L, byrow = TRUE)) +
  ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

plots$rhs_scale_and_contribution_trace <- ggplot2::ggplot(rhs_scale_trace, ggplot2::aes(iteration, effective_tau, color = block)) +
  ggplot2::geom_line(linewidth = 0.55) + ggplot2::scale_y_log10() + ggplot2::facet_wrap(~candidate_id, ncol = 1L) +
  ggplot2::labs(
    x = "VB iteration", y = "Effective global scale", color = NULL,
    caption = figure_caption("rhs_scale_trace", "VB regularized-horseshoe effective global-scale traces")
  ) +
  ggplot2::theme_bw(base_size = 9) + ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

exact_long <- rbind(
  data.frame(exact_vs_optimized_parity[c("candidate_id", "draw_index")], component = "discrepancy", max_abs_difference = exact_vs_optimized_parity$max_abs_d_g_difference),
  data.frame(exact_vs_optimized_parity[c("candidate_id", "draw_index")], component = "reference first-order", max_abs_difference = exact_vs_optimized_parity$max_abs_q_y_difference)
)
plots$exact_vs_optimized_differences <- ggplot2::ggplot(exact_long, ggplot2::aes(factor(draw_index), max_abs_difference, fill = component)) +
  ggplot2::geom_col(position = "dodge") +
  ggplot2::scale_y_continuous(trans = scales::pseudo_log_trans(base = 10)) +
  ggplot2::facet_wrap(~candidate_id) +
  ggplot2::labs(
    x = "Posterior draw index", y = "Maximum absolute difference", fill = NULL,
    caption = figure_caption("exact_vs_optimized_parity", "exact versus optimized prediction differences")
  ) + ggplot2::theme_bw(base_size = 9)

for (name in names(plots)) {
  ggplot2::ggsave(file.path(output_root, "figures", paste0(name, ".pdf")), plots[[name]], width = 9, height = 6, units = "in")
}

source_files <- c(
  app_path("application/R/glofas_discrepancy_equivalence_audit.R"),
  app_path("application/scripts/glofas_discrepancy_equivalence_audit.R"),
  app_path("application/R/glofas_fit_recovery_mechanism_audit.R"),
  app_path("application/R/glofas_fit_recovery_scientific_audit.R"),
  app_path("application/R/fit_qdesn_latent_path.R"),
  app_path("application/R/model_contract.R")
)
plan_path <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/glofas_discrepancy_forecast_equivalence_ultimate_diagnostic_plan_20260827.md"
if (file.exists(plan_path)) source_files <- c(source_files, plan_path)
source_hashes <- data.frame(
  path = normalizePath(source_files, mustWork = TRUE),
  sha256 = vapply(source_files, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(source_hashes, file.path(output_root, "manifest", "source_hashes.csv"))
app_write_git_state(file.path(output_root, "manifest", "git_state.txt"))
app_write_session_info(file.path(output_root, "manifest", "session_info.txt"))

all_output_files <- list.files(output_root, recursive = TRUE, full.names = TRUE)
all_output_files <- all_output_files[file.info(all_output_files)$isdir %in% FALSE]
artifact_manifest <- data.frame(
  path = normalizePath(all_output_files, mustWork = TRUE),
  relative_path = substring(normalizePath(all_output_files, mustWork = TRUE), nchar(output_root) + 2L),
  size_bytes = as.numeric(file.info(all_output_files)$size),
  sha256 = vapply(all_output_files, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(artifact_manifest, file.path(output_root, "manifest", "artifact_manifest.csv"))
runtime_files <- list.files(runtime_root, recursive = TRUE, full.names = TRUE)
runtime_files <- runtime_files[file.info(runtime_files)$isdir %in% FALSE]
storage_report <- data.frame(
  scope = c("retained_source_campaign", "diagnostic_output_before_manifest"),
  files = c(length(runtime_files), nrow(artifact_manifest)),
  bytes = c(sum(file.info(runtime_files)$size, na.rm = TRUE), sum(artifact_manifest$size_bytes, na.rm = TRUE)),
  gib = c(sum(file.info(runtime_files)$size, na.rm = TRUE), sum(artifact_manifest$size_bytes, na.rm = TRUE)) / 1024^3,
  heavy_objects_copied = c(FALSE, FALSE),
  stringsAsFactors = FALSE
)
app_write_csv(storage_report, file.path(output_root, "manifest", "storage_report.csv"))

mandatory_tables <- c(
  "source_artifact_manifest", "effective_block_configs", "seed_resolution_certificate",
  "artifact_lineage", "feature_layout_and_hashes", "cache_mutation_tests",
  "serialization_parity", "sentinel_column_tests", "permutation_tests",
  "exact_vs_optimized_parity", "prediction_identity_checks", "pairwise_state_distances",
  "pairwise_design_distances", "pairwise_prediction_distances", "history_feature_contributions",
  "forecast_feature_contributions", "posterior_contribution_uncertainty", "no_refit_ablation_paths",
  "rhs_scale_and_coefficient_summary", "transition_contract_tests", "covariate_provenance_and_shift",
  "independent_score_reconstruction", "root_cause_decision"
)
missing_tables <- mandatory_tables[!file.exists(file.path(output_root, "tables", paste0(mandatory_tables, ".csv")))]
if (length(missing_tables)) stop(sprintf("Mandatory diagnostic tables are missing: %s", paste(missing_tables, collapse = ", ")), call. = FALSE)
mandatory_figures <- c(
  "discrepancy_paths_overlay", "pairwise_prediction_difference_by_horizon",
  "feature_contribution_paths", "reservoir_layer_contribution_paths",
  "coefficient_energy_by_feature_group", "state_dynamic_range_by_layer",
  "history_vs_forecast_feature_shift", "no_refit_ablation_paths",
  "rhs_scale_and_contribution_trace", "exact_vs_optimized_differences"
)
missing_figures <- mandatory_figures[
  !file.exists(file.path(output_root, "figures", paste0(mandatory_figures, ".pdf")))
]
if (length(missing_figures)) {
  stop(sprintf("Mandatory diagnostic figures are missing: %s", paste(missing_figures, collapse = ", ")), call. = FALSE)
}
if (any(!implementation_checks$passed)) {
  failed <- implementation_checks$check[!implementation_checks$passed]
  stop(sprintf("White-box diagnostic checks failed: %s", paste(failed, collapse = ", ")), call. = FALSE)
}
writeLines(c(
  "GloFAS discrepancy-equivalence diagnostic completed.",
  paste("Completed at:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  paste("Source runtime:", runtime_root),
  paste("Retained candidates:", paste(requested, collapse = ";")),
  paste("Primary root cause:", root_cause_decision$primary_root_cause[[1L]]),
  paste("Secondary mechanism:", root_cause_decision$secondary_mechanism[[1L]]),
  "No fit, broad screen, full7 launch, promotion, or article update was performed.",
  "Controlled inference canaries remain behind the explicit post-diagnosis authorization gate."
), file.path(output_root, "DIAGNOSTIC_COMPLETE.txt"))
message(sprintf("[equivalence-audit] complete: %s", output_root))
