if (!exists("app_glofas_normal_part3_model_families", mode = "function")) {
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
  source("application/R/glofas_normal_desn_part3_joint_bridge.R")
}

normal_part3_cfg <- list(
  data = list(transform = list(response = "identity", forecast = "identity")),
  covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
  feature_contract = list(),
  reservoir = list()
)

part3_dates <- as.Date("2021-01-01") + 0:95
part3_y <- sin(seq_along(part3_dates) / 5) + seq_along(part3_dates) / 100
part3_d <- 0.15 * cos(seq_along(part3_dates) / 8) + 0.03 * sin(seq_along(part3_dates) / 3)
part3_g <- part3_y + part3_d
part3_panel <- data.frame(
  origin_date = part3_dates,
  target_date = part3_dates,
  horizon = 0L,
  member = NA_character_,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_reference = part3_y,
  g_glofas = part3_g,
  y_transformed = part3_y,
  g_transformed = part3_g,
  split = "train",
  cutoff_id = "toy",
  ppt = cos(seq_along(part3_dates) / 7),
  soil = sin(seq_along(part3_dates) / 9),
  stringsAsFactors = FALSE
)
part3_panel$ppt_role <- "realized_history"
part3_panel$soil_role <- "realized_history"
part3_timeline <- data.frame(
  date = part3_dates,
  ppt = part3_panel$ppt,
  soil = part3_panel$soil,
  ppt_role = part3_panel$ppt_role,
  soil_role = part3_panel$soil_role,
  stringsAsFactors = FALSE
)
attr(part3_timeline, "covariate_future_policy") <- "historical_bridge"
attr(part3_timeline, "covariate_source_provider") <- "toy_fixture"
attr(part3_panel, "model_covariate_timeline") <- part3_timeline
part3_bundle <- list(
  panel = part3_panel,
  cutoff = data.frame(
    train_start = min(part3_dates),
    train_end = max(part3_dates),
    stringsAsFactors = FALSE
  )
)

families <- app_glofas_normal_part3_model_families()
stopifnot(nrow(families) == 6L)
stopifnot(all(c("normal_ridge_joint", "normal_rhs_vb_joint") %in% families$model_family))
stopifnot(sum(families$executable_now) == 6L)
stopifnot(identical(app_glofas_normal_part3_quantile_grid(), c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)))

winner_manifest <- data.frame(
  component = c("reference", "discrepancy"),
  stage = c("G1", "G2"),
  candidate_id = c("toy_ref_winner", "toy_disc_winner"),
  source_runtime_root = c("toy_g1", "toy_g2"),
  score_path = c("toy_g1_scores.csv", "toy_g2_scores.csv"),
  method = c("normal_rhs_vb", "normal_rhs_vb"),
  status = c("completed", "completed"),
  winner_role = c("reference", "discrepancy"),
  n_vector = c("5", "4"),
  m = c(3L, 3L),
  output_lag_max = c(3L, 3L),
  covariate_lag_max = c(2L, 2L),
  auxiliary_lag_max = c(0L, 2L),
  input_contract = c("reference_usgs_covars", "disc_usgs_covars"),
  washout = c(4L, 4L),
  alpha = c(0.2, 0.3),
  rho = c(0.9, 0.85),
  seed = c(101L, 202L),
  rhs_tau0 = c(0.1, 0.001),
  design_hash = c("refhash", "dischash"),
  frozen = c(FALSE, FALSE),
  stringsAsFactors = FALSE
)
blocked <- tryCatch({
  app_glofas_normal_part3_validate_winner_manifest(winner_manifest, require_frozen = TRUE)
  FALSE
}, error = function(e) TRUE)
stopifnot(isTRUE(blocked))
winner_manifest$frozen <- TRUE
validated_manifest <- app_glofas_normal_part3_validate_winner_manifest(winner_manifest, require_frozen = TRUE)
stopifnot(nrow(validated_manifest) == 2L)

part3_candidate <- app_glofas_normal_part3_candidate_from_winners(
  winner_manifest,
  candidate_id = "toy_part3_joint",
  require_frozen = TRUE
)
part3_candidate$validation_n <- 8L
part3_candidate$rhs_max_iter <- 4L
part3_candidate$rhs_min_iter <- 2L
part3_candidate$rhs_tol <- 0
stopifnot(identical(part3_candidate$ref_n_vector[[1L]], "5"))
stopifnot(identical(part3_candidate$disc_n_vector[[1L]], "4"))
stopifnot(identical(part3_candidate$disc_input_contract[[1L]], "disc_usgs_covars"))
stopifnot(part3_candidate$rhs_tau0_reference[[1L]] == 0.1)
stopifnot(part3_candidate$rhs_tau0_discrepancy[[1L]] == 0.001)

part3_design <- app_glofas_normal_part3_build_design(
  normal_part3_cfg,
  part3_candidate,
  panel_bundle = part3_bundle
)
stopifnot(part3_design$n_dates == 92L)
stopifnot(nrow(part3_design$H) == 2L * part3_design$n_dates)
stopifnot(ncol(part3_design$H) == ncol(part3_design$reference$X) + ncol(part3_design$discrepancy$X))
stopifnot(max(abs(part3_design$y_reference + part3_design$d_g - part3_design$g_retrospective)) < 1.0e-12)
stopifnot(max(abs(part3_design$H[seq_len(part3_design$n_dates), part3_design$alpha_index, drop = FALSE])) < 1.0e-12)
stopifnot(max(abs(
  part3_design$H[part3_design$n_dates + seq_len(part3_design$n_dates), part3_design$alpha_index, drop = FALSE] -
    part3_design$discrepancy$X
)) < 1.0e-12)
stopifnot(isTRUE(part3_design$pairing_certificate$paired_beta_rows))

ridge_out <- app_glofas_normal_part3_fit_ridge(
  normal_part3_cfg,
  part3_candidate,
  panel_bundle = part3_bundle
)
stopifnot(identical(ridge_out$summary$status[[1L]], "completed"))
stopifnot(is.finite(ridge_out$summary$corrected_valid_mean_crps[[1L]]))
stopifnot(inherits(ridge_out$warm_start, "glofas_normal_part3_ridge_warm_start"))

warm_start_path <- tempfile(fileext = ".rds")
saveRDS(ridge_out$warm_start, warm_start_path, version = 2L)
warm_start_sha256 <- app_sha256_file(warm_start_path)
loaded_warm_start <- app_glofas_normal_part3_load_warm_start(
  warm_start_path,
  warm_start_sha256,
  design = ridge_out$design,
  split = ridge_out$split
)
stopifnot(inherits(loaded_warm_start, "glofas_normal_part3_ridge_warm_start"))
stopifnot(identical(attr(loaded_warm_start, "source_sha256"), warm_start_sha256))
bad_sha_failed <- tryCatch({
  app_glofas_normal_part3_load_warm_start(
    warm_start_path,
    paste(rep("0", 64L), collapse = "")
  )
  FALSE
}, error = function(e) TRUE)
stopifnot(isTRUE(bad_sha_failed))

rhs_progress_path <- tempfile(fileext = ".csv")
rhs_out <- app_glofas_normal_part3_fit_rhs(
  normal_part3_cfg,
  part3_candidate,
  panel_bundle = part3_bundle,
  warm_start = loaded_warm_start,
  progress_path = rhs_progress_path,
  progress_every = 1L
)
stopifnot(inherits(rhs_out$fit, "glofas_normal_part3_rhs_vb_fit"))
stopifnot(nrow(rhs_out$trace) >= 2L)
stopifnot(file.exists(rhs_progress_path))
stopifnot(nrow(app_read_csv(rhs_progress_path)) == nrow(rhs_out$trace))
stopifnot(is.finite(rhs_out$summary$corrected_valid_mean_crps[[1L]]))
stopifnot(rhs_out$summary$rhs_tau0_reference[[1L]] == 0.1)
stopifnot(rhs_out$summary$rhs_tau0_discrepancy[[1L]] == 0.001)
stopifnot(all(c("reference", "discrepancy") %in% unique(rhs_out$coefficients$part3_block)))

contract <- app_glofas_normal_part3_forecast_contract_template()
app_glofas_normal_part3_validate_forecast_contract(contract)
bad_contract <- contract
bad_contract$covariate_source[[1L]] <- "cefs"
bad_contract_failed <- tryCatch({
  app_glofas_normal_part3_validate_forecast_contract(bad_contract)
  FALSE
}, error = function(e) TRUE)
stopifnot(isTRUE(bad_contract_failed))

deferred_manifest <- app_glofas_normal_part3_launch_manifest(run_label = "toy_deferred")
stopifnot(nrow(deferred_manifest) == 18L)
stopifnot(all(grepl("^blocked_", deferred_manifest$status[deferred_manifest$model_family %in% c("normal_ridge_joint", "normal_rhs_vb_joint")])))
stopifnot(all(
  deferred_manifest$status[!deferred_manifest$model_family %in% c("normal_ridge_joint", "normal_rhs_vb_joint")] ==
    "implemented_via_part3_quantile_forecast_continuation"
))

ready_manifest <- app_glofas_normal_part3_launch_manifest(
  selected_winner_manifest = winner_manifest,
  run_label = "toy_ready",
  require_frozen = TRUE
)
stopifnot(nrow(ready_manifest) == 18L)
stopifnot(all(ready_manifest$status[ready_manifest$model_family %in% c("normal_ridge_joint", "normal_rhs_vb_joint")] == "ready_after_operator_launch_approval"))
stopifnot(any(ready_manifest$status == "implemented_via_part3_quantile_forecast_continuation"))
