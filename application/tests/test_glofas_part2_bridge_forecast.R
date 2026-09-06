if (!exists("app_glofas_part2_bridge_selected_rhs_row", mode = "function", inherits = TRUE)) {
  script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else ""
  repo_root <- if (nzchar(script_path)) {
    normalizePath(file.path(dirname(normalizePath(script_path, mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    path <- normalizePath(getwd(), mustWork = TRUE)
    repeat {
      if (file.exists(file.path(path, "main.tex")) && dir.exists(file.path(path, "application"))) break
      parent <- dirname(path)
      if (identical(parent, path)) stop("Could not locate Article-Q-DESN repository root.", call. = FALSE)
      path <- parent
    }
    path
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
  source(app_path("application/R/glofas_normal_oracle_forecast.R"))
  source(app_path("application/R/glofas_part1_quantile_oracle_forecast.R"))
  source(app_path("application/R/glofas_part2_bridge_forecast.R"))
}

winner_row <- data.frame(
  rhs_candidate_id = "normal_part2_rhs_top16_part2ridge_targeted_0016_disc_covars__D1_n2500__a080_r070__reftau1e00_disctau1em03",
  candidate_id = "part2ridge_targeted_0016_disc_covars__D1_n2500__a080_r070",
  disc_input_contract = "disc_covars",
  disc_include_covariates = TRUE,
  disc_include_glofas_lags = FALSE,
  disc_include_usgs_lags = FALSE,
  disc_D = 1L,
  disc_n_vector = "2500",
  disc_m = 360L,
  disc_output_lag_max = 360L,
  disc_covariate_lag_max = 180L,
  disc_auxiliary_lag_max = 360L,
  disc_washout = 500L,
  disc_alpha = 0.8,
  disc_rho = 0.7,
  disc_seed = 20261521L,
  ridge_tau2 = 10000,
  intercept_var = 1e6,
  sigma_a = 2,
  sigma_b = 1,
  validation_n = 365L,
  rhs_tau0_discrepancy = 0.001,
  rhs_max_iter = 100L,
  rhs_min_iter = 30L,
  rhs_tol = 1e-4,
  rhs_update_every = 1L,
  rhs_freeze_tau_warmup_iters = 0L,
  rhs_min_tau_updates = 0L,
  status = "completed",
  corrected_valid_mean_crps = 0.1,
  discrepancy_valid_mean_crps = 0.1,
  stringsAsFactors = FALSE
)
app_glofas_part2_bridge_validate_disc_covars_contract(winner_row, strict_winner = TRUE)
candidate <- app_glofas_part2_bridge_candidate_from_rhs_row(winner_row)
stopifnot(identical(as.character(candidate$n_vector[[1L]]), "2500"))
stopifnot(as.integer(candidate$output_lag_max[[1L]]) == 360L)
stopifnot(as.integer(candidate$covariate_lag_max[[1L]]) == 180L)
stopifnot(abs(as.numeric(candidate$rhs_tau0[[1L]]) - 0.001) < 1.0e-12)

audit <- data.frame(
  input_block = c("output_lag", "output_lag", "covariate"),
  role = c("historical_usgs", "latent_future_usgs", "oracle_realized_future"),
  source = c("observed_usgs_history", "recursive_latent_path", "realized_ppt_soil_covariates"),
  stringsAsFactors = FALSE
)
audit2 <- app_glofas_part2_bridge_relabel_audit(audit)
stopifnot(!any(grepl("future_usgs", audit2$role, ignore.case = TRUE)))
stopifnot(any(audit2$role == "latent_future_discrepancy"))
app_glofas_part2_bridge_validate_no_future_usgs_leakage(audit2)

fit <- list(
  beta_mean = c(0, 2),
  beta_var_diag = c(0.01, 0.25),
  sigma_a = 3,
  sigma_b = 2,
  sigma2_mean = 1,
  p = 2L
)
X <- cbind(readout_intercept = 1, reservoir_0001 = c(0, 2))
pred <- app_glofas_normal_predict(fit, X)
stopifnot(isTRUE(all.equal(pred$mean, c(0, 4), tolerance = 1.0e-12)))
stopifnot(isTRUE(all.equal(pred$sd, sqrt(c(1.01, 2.01)), tolerance = 1.0e-12)))
draws <- app_glofas_oracle_parameter_draws(fit, method = "rhs", n_draws = 6L, seed = 20260904L)
stopifnot(identical(dim(draws$beta), c(6L, 2L)))
stopifnot(identical(draws$beta_draw_backend, "beta_var_diag_independent"))

qpath <- data.frame(
  date = as.Date("2022-12-26") + 0:1,
  segment = "oracle_realized_forecast",
  discrepancy_tau = c(0.35, 0.65),
  corrected_tau = c(0.65, 0.35),
  observed_usgs = c(10, 11),
  retrospective_glofas = c(12, 13),
  observed_discrepancy = c(2, 2),
  discrepancy_qhat = c(3, 1),
  corrected_qhat = c(9, 12),
  stringsAsFactors = FALSE
)
qs <- app_glofas_part2_bridge_score_quantile(qpath)
stopifnot(nrow(qs$pointwise) == 2L)
stopifnot(isTRUE(all.equal(
  qs$pointwise$corrected_check_loss,
  app_glofas_part1_quantile_check_loss(qpath$observed_usgs, qpath$corrected_qhat, qpath$corrected_tau),
  tolerance = 0
)))

message("GloFAS Part 2 bridge forecast adapter tests passed.")
