if (!exists("app_glofas_normal_part2_candidate_template", mode = "function")) {
  source("application/R/00_packages.R")
  app_set_repo_root(getwd())
  source(app_path("application/R/input_contract.R"))
  source(app_path("application/R/model_contract.R"))
  source(app_path("application/R/feature_contract.R"))
  source(app_path("application/R/covariate_design.R"))
  source(app_path("application/R/build_application_panel.R"))
  source(app_path("application/R/latent_path_design.R"))
  source("application/R/discrepancy_design.R")
  source("application/R/latent_path_vb_al.R")
  source("application/R/glofas_normal_desn_part1_screening.R")
  source("application/R/glofas_normal_desn_part2_bridge.R")
}

normal_part2_cfg <- list(
  data = list(transform = list(response = "identity", forecast = "identity")),
  covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
  feature_contract = list(),
  reservoir = list()
)

toy_dates <- as.Date("2020-01-01") + 0:119
toy_y <- sin(seq_along(toy_dates) / 6) + seq_along(toy_dates) / 120
toy_d <- 0.25 * cos(seq_along(toy_dates) / 7) - 0.02 * sin(seq_along(toy_dates) / 3)
toy_g <- toy_y + toy_d
toy_panel <- data.frame(
  origin_date = toy_dates,
  target_date = toy_dates,
  horizon = 0L,
  member = NA_character_,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_reference = toy_y,
  g_glofas = toy_g,
  y_transformed = toy_y,
  g_transformed = toy_g,
  split = "train",
  cutoff_id = "toy",
  ppt = cos(seq_along(toy_dates) / 9),
  soil = sin(seq_along(toy_dates) / 11),
  stringsAsFactors = FALSE
)
toy_panel$ppt_role <- "realized_history"
toy_panel$soil_role <- "realized_history"
toy_timeline <- data.frame(
  date = toy_dates,
  ppt = toy_panel$ppt,
  soil = toy_panel$soil,
  ppt_role = toy_panel$ppt_role,
  soil_role = toy_panel$soil_role,
  stringsAsFactors = FALSE
)
attr(toy_timeline, "covariate_future_policy") <- "historical_bridge"
attr(toy_timeline, "covariate_source_provider") <- "toy_fixture"
attr(toy_panel, "model_covariate_timeline") <- toy_timeline
toy_bundle <- list(
  panel = toy_panel,
  cutoff = data.frame(
    train_start = min(toy_dates),
    train_end = max(toy_dates),
    stringsAsFactors = FALSE
  )
)

toy_candidate <- app_glofas_normal_part2_candidate_template()
toy_candidate$candidate_id <- "toy_part2"
toy_candidate$ref_n_vector <- "5"
toy_candidate$disc_n_vector <- "4"
toy_candidate$ref_m <- 3L
toy_candidate$disc_m <- 3L
toy_candidate$ref_output_lag_max <- 3L
toy_candidate$disc_output_lag_max <- 3L
toy_candidate$ref_covariate_lag_max <- 2L
toy_candidate$disc_covariate_lag_max <- 2L
toy_candidate$ref_washout <- 5L
toy_candidate$disc_washout <- 5L
toy_candidate$ref_alpha <- 0.2
toy_candidate$disc_alpha <- 0.3
toy_candidate$ref_rho <- 0.9
toy_candidate$disc_rho <- 0.85
toy_candidate$ref_seed <- 101L
toy_candidate$disc_seed <- 202L
toy_candidate$validation_n <- 10L
toy_candidate$rhs_tau0_reference <- 0.1
toy_candidate$rhs_tau0_discrepancy <- 1.0e-3
toy_candidate$rhs_max_iter <- 5L
toy_candidate$rhs_min_iter <- 2L
toy_candidate$rhs_tol <- 0

paired <- app_glofas_normal_part2_prepare_panel(
  normal_part2_cfg,
  panel_bundle = toy_bundle
)
stopifnot(nrow(paired$panel) == nrow(toy_panel))
stopifnot(max(abs(paired$panel$d_g_transformed - (toy_g - toy_y))) < 1.0e-12)
stopifnot(!anyDuplicated(paired$panel$target_date))
stopifnot(!is.null(attr(paired$panel, "model_covariate_timeline", exact = TRUE)))
stopifnot(!is.null(attr(paired$panel, "model_auxiliary_timeline", exact = TRUE)))

ref_cfg <- app_glofas_normal_part2_component_cfg(normal_part2_cfg, toy_candidate, "reference")
disc_cfg <- app_glofas_normal_part2_component_cfg(normal_part2_cfg, toy_candidate, "discrepancy")
stopifnot(identical(as.integer(ref_cfg$reservoir$n), 5L))
stopifnot(identical(as.integer(disc_cfg$reservoir$n), 4L))
stopifnot(identical(app_feature_contract(ref_cfg)$reservoir_input$output_lags, 1:3))
stopifnot(identical(app_feature_contract(disc_cfg)$reservoir_input$covariate_lags$ppt, 0:2))
stopifnot(!isTRUE(app_feature_contract(ref_cfg)$readout$include_input_block))
stopifnot(!isTRUE(app_feature_contract(disc_cfg)$readout$include_input_block))

toy_full_candidate <- toy_candidate
toy_full_candidate$candidate_id <- "toy_part2_full_hist"
toy_full_candidate$disc_input_contract <- "disc_full_hist"
toy_full_candidate$disc_auxiliary_lag_max <- 2L
disc_full_cfg <- app_glofas_normal_part2_component_cfg(normal_part2_cfg, toy_full_candidate, "discrepancy")
disc_full_contract <- app_feature_contract(disc_full_cfg)
stopifnot(identical(disc_full_contract$reservoir_input$auxiliary_lags$glofas, 1:2))
stopifnot(identical(disc_full_contract$reservoir_input$auxiliary_lags$usgs, 1:2))
stopifnot(identical(disc_full_contract$reservoir_input$covariate_lags$ppt, 0:2))

toy_disc_only <- toy_candidate
toy_disc_only$candidate_id <- "toy_part2_disc_only"
toy_disc_only$disc_input_contract <- "disc_only"
disc_only_cfg <- app_glofas_normal_part2_component_cfg(normal_part2_cfg, toy_disc_only, "discrepancy")
disc_only_contract <- app_feature_contract(disc_only_cfg)
stopifnot(!length(disc_only_contract$reservoir_input$auxiliary_lags))
stopifnot(!length(disc_only_contract$reservoir_input$covariate_lags))

bridge_design <- app_glofas_normal_part2_build_design(
  normal_part2_cfg,
  toy_candidate,
  panel_bundle = toy_bundle
)
stopifnot(length(bridge_design$dates) == 115L)
stopifnot(ncol(bridge_design$reference$X) == 6L)
stopifnot(ncol(bridge_design$discrepancy$X) == 5L)
stopifnot(all(is.finite(bridge_design$y_reference)))
stopifnot(all(is.finite(bridge_design$g_retrospective)))
stopifnot(all(is.finite(bridge_design$d_g)))
stopifnot(max(abs(bridge_design$g_retrospective - bridge_design$d_g - bridge_design$y_reference)) < 1.0e-12)
stopifnot(!any(grepl(
  "^y_lag_|^ppt_lag_|^soil_lag_",
  c(
    bridge_design$reference$feature_info$column_name,
    bridge_design$discrepancy$feature_info$column_name
  )
)))

bridge_full_design <- app_glofas_normal_part2_build_design(
  normal_part2_cfg,
  toy_full_candidate,
  panel_bundle = toy_bundle
)
disc_input_columns <- bridge_full_design$discrepancy$component_design$design_meta$reservoir_input_columns
stopifnot(any(grepl("^glofas_lag_", disc_input_columns)))
stopifnot(any(grepl("^usgs_lag_", disc_input_columns)))
stopifnot(!any(grepl("^glofas_lag_|^usgs_lag_", bridge_full_design$discrepancy$feature_info$column_name)))

reference_cache <- app_glofas_normal_part2_prepare_reference_cache(
  normal_part2_cfg,
  toy_full_candidate,
  panel_bundle = toy_bundle
)
bridge_cached <- app_glofas_normal_part2_build_design(
  normal_part2_cfg,
  toy_full_candidate,
  panel_bundle = toy_bundle,
  reference_cache = reference_cache
)
stopifnot(identical(bridge_cached$reference$X, bridge_full_design$reference$X))
stopifnot(identical(bridge_cached$dates, bridge_full_design$dates))

ridge <- app_glofas_normal_part2_score_ridge_candidate(
  normal_part2_cfg,
  toy_candidate,
  panel_bundle = toy_bundle
)
stopifnot(identical(ridge$summary$status[[1L]], "completed"))
stopifnot(is.finite(ridge$summary$corrected_valid_mean_crps[[1L]]))
stopifnot(is.finite(ridge$summary$discrepancy_valid_mean_crps[[1L]]))
stopifnot(identical(ridge$summary$valid_mean_crps[[1L]], ridge$summary$corrected_valid_mean_crps[[1L]]))
stopifnot(all(c("reference_pred_mean", "discrepancy_pred_mean", "corrected_pred_mean") %in% names(ridge$detail)))

ridge_cached <- app_glofas_normal_part2_score_ridge_candidate(
  normal_part2_cfg,
  toy_full_candidate,
  panel_bundle = toy_bundle,
  reference_cache = reference_cache
)
stopifnot(identical(ridge_cached$summary$status[[1L]], "completed"))
stopifnot(is.finite(ridge_cached$summary$corrected_valid_mean_crps[[1L]]))

warm_pack <- app_glofas_normal_part2_fit_ridge_components(
  normal_part2_cfg,
  toy_candidate,
  panel_bundle = toy_bundle
)
app_glofas_normal_part2_validate_warm_start(
  warm_pack$warm_start,
  design = warm_pack$design,
  train_idx = warm_pack$split$train_idx
)
bad_warm <- warm_pack$warm_start
bad_warm$design_hash$discrepancy_train <- paste(rep("0", 64L), collapse = "")
stopifnot(inherits(
  try(app_glofas_normal_part2_validate_warm_start(
    bad_warm,
    design = warm_pack$design,
    train_idx = warm_pack$split$train_idx
  ), silent = TRUE),
  "try-error"
))

rhs <- app_glofas_normal_part2_score_rhs_candidate(
  normal_part2_cfg,
  toy_candidate,
  panel_bundle = toy_bundle,
  warm_start = warm_pack$warm_start
)
stopifnot(identical(rhs$summary$status[[1L]], "completed"))
stopifnot(is.finite(rhs$summary$corrected_valid_mean_crps[[1L]]))
stopifnot(is.finite(rhs$summary$discrepancy_valid_mean_crps[[1L]]))
stopifnot(nrow(rhs$trace) == 10L)
stopifnot(identical(sort(unique(rhs$trace$component)), c("discrepancy", "reference")))
stopifnot(identical(sort(unique(rhs$activity$component)), c("discrepancy", "reference")))
stopifnot(identical(sort(unique(rhs$coefficients$component)), c("discrepancy", "reference")))
stopifnot(rhs$summary$reference_iterations[[1L]] == 5L)
stopifnot(rhs$summary$discrepancy_iterations[[1L]] == 5L)

collect_root <- tempfile("part2_rhs_collect_")
dir.create(file.path(collect_root, "scores"), recursive = TRUE)
dir.create(file.path(collect_root, "tables"), recursive = TRUE)
app_write_csv(rhs$summary, file.path(collect_root, "scores", "toy_rhs_summary.csv"))
app_write_csv(rhs$detail, file.path(collect_root, "scores", "toy_rhs_validation_detail.csv"))
rhs_scores <- app_glofas_normal_part2_collect_rhs_scores(collect_root)
stopifnot(file.exists(file.path(collect_root, "tables", "part2_rhs_scores_latest.csv")))
stopifnot(file.exists(file.path(collect_root, "tables", "part2_rhs_validation_detail_latest.csv")))
stopifnot(nrow(rhs_scores) == 1L)
stopifnot(identical(rhs_scores$status[[1L]], "completed"))
stopifnot(rhs_scores$rank_corrected_valid_crps[[1L]] == 1L)

manifest <- app_glofas_normal_part2_ridge_candidate_manifest(candidate_prefix = "toy_part2ridge")
stopifnot(nrow(manifest) == 2250L)
stopifnot(all(c(
  "disc_input_contract", "disc_geometry_id", "disc_dynamics_id",
  "disc_include_glofas_lags", "disc_include_usgs_lags"
) %in% names(manifest)))
stopifnot(identical(sort(unique(manifest$disc_input_contract)), sort(app_glofas_normal_part2_input_contracts()$disc_input_contract)))
stopifnot(all(manifest$ref_n_vector == "3000"))
stopifnot(all(manifest$ref_alpha == 0.50))
stopifnot(all(manifest$ref_rho == 0.90))

real_cfg_path <- "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml"
if (file.exists(real_cfg_path)) {
  real_cfg <- app_read_yaml(real_cfg_path)
  real_candidate <- app_glofas_normal_part2_candidate_template()
  real_candidate$candidate_id <- "real_part2_tiny_ridge_contract"
  real_candidate$ref_n_vector <- "3"
  real_candidate$disc_n_vector <- "3"
  real_candidate$ref_m <- 3L
  real_candidate$disc_m <- 3L
  real_candidate$ref_output_lag_max <- 3L
  real_candidate$disc_output_lag_max <- 3L
  real_candidate$ref_covariate_lag_max <- 2L
  real_candidate$disc_covariate_lag_max <- 2L
  real_candidate$ref_washout <- 5L
  real_candidate$disc_washout <- 5L
  real_candidate$validation_n <- 30L
  real_score <- app_glofas_normal_part2_score_ridge_candidate(real_cfg, real_candidate)
  stopifnot(identical(real_score$summary$status[[1L]], "completed"))
  stopifnot(real_score$summary$n_rows_design[[1L]] > 10000L)
  stopifnot(is.finite(real_score$summary$corrected_valid_mean_crps[[1L]]))
  stopifnot(is.finite(real_score$summary$discrepancy_valid_mean_crps[[1L]]))
  stopifnot(max(abs(
    real_score$detail$retrospective_glofas -
      real_score$detail$observed_discrepancy -
      real_score$detail$observed_usgs
  )) < 1.0e-10)
}
