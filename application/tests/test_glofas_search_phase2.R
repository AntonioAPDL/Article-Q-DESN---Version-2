search2_folds <- app_glofas_search2_fold_registry()
stopifnot(nrow(search2_folds) == 6L)
stopifnot(all(search2_folds$origin_date < as.Date("2022-12-25")))
stopifnot(all(search2_folds$primary_horizon == 28L), all(search2_folds$secondary_horizon == 30L))

bad_final_fold <- search2_folds[1L, , drop = FALSE]
bad_final_fold$origin_date <- as.Date("2022-12-25")
stopifnot(grepl("must precede", tryCatch({
  app_glofas_search2_validate_folds(bad_final_fold)
  ""
}, error = conditionMessage), fixed = TRUE))

small_pool <- data.frame(
  D = c(1, 1, 2, 2), n_state_features = c(100, 200, 300, 400),
  output_lag_max = c(10, 20, 30, 40), covariate_lag_max = c(5, 10, 15, 20),
  alpha = c(0.2, 0.4, 0.6, 0.8), rho = c(0.3, 0.5, 0.7, 0.9),
  pi_w = c(0.01, 0.03, 0.1, 0.3), pi_in = c(0.1, 0.3, 0.6, 1),
  effective_input_gain = c(0.5, 1, 2, 4), stringsAsFactors = FALSE
)
maximin_a <- app_glofas_search2_maximin(small_pool, 3L)
maximin_b <- app_glofas_search2_maximin(small_pool, 3L)
stopifnot(identical(maximin_a, maximin_b), nrow(maximin_a) == 3L)

candidate_manifest <- app_glofas_search2_candidate_manifest("reference", n_space_filling = 8L)
stopifnot(any(candidate_manifest$candidate_role == "phase1_legacy_anchor"))
stopifnot(any(candidate_manifest$candidate_role == "phase1_standardized_anchor"))
stopifnot(any(candidate_manifest$ridge_tau2 == 1), any(candidate_manifest$ridge_tau2 == 10000))
stopifnot(all(candidate_manifest$pi_w > 0 & candidate_manifest$pi_w <= 1))
stopifnot(all(candidate_manifest$pi_in > 0 & candidate_manifest$pi_in <= 1))
stopifnot(!anyDuplicated(candidate_manifest$candidate_id))

set.seed(44)
dates <- seq.Date(as.Date("2015-01-01"), as.Date("2019-02-28"), by = "day")
toy_master_data <- data.frame(
  date = dates,
  usgs = exp(0.3 + sin(seq_along(dates) / 30)) - 1,
  glofas = exp(0.4 + sin(seq_along(dates) / 28)) - 1,
  ppt = pmax(0, rnorm(length(dates))), soil = runif(length(dates)),
  stringsAsFactors = FALSE
)
toy_master_data$usgs_log1p <- log1p(toy_master_data$usgs)
toy_master_data$glofas_log1p <- log1p(toy_master_data$glofas)
toy_master_data$discrepancy_log1p <- toy_master_data$glofas_log1p - toy_master_data$usgs_log1p
toy_master <- list(data = toy_master_data, sha256 = c(reference = "a", retrospective = "b", covariates = "c"))
toy_fold <- data.frame(
  fold_id = "toy_fold", origin_date = as.Date("2018-12-25"), primary_horizon = 28L,
  secondary_horizon = 30L, retrospective_product = "toy", primary = TRUE, stringsAsFactors = FALSE
)
packets <- app_glofas_search2_make_fold_packets(toy_master, toy_fold, "reference")
app_glofas_search2_validate_model_packet(packets$model)
stopifnot(max(packets$model$panel_bundle$panel$target_date) == toy_fold$origin_date)
stopifnot(nrow(packets$scoring) == 30L, sum(packets$scoring$primary_28) == 28L)
stopifnot(!any(c("future_truth", "observed", "usgs_future", "glofas_future") %in% names(packets$model)))
toy_timeline <- attr(packets$model$panel_bundle$panel, "model_covariate_timeline", exact = TRUE)
stopifnot(max(toy_timeline$date) == toy_fold$origin_date + 30L)
stopifnot(all(toy_timeline$ppt_role[toy_timeline$date > toy_fold$origin_date] == "oracle_realized_future"))

set.seed(45)
X_raw <- cbind(intercept = 1, x1 = rnorm(50, 10, 2), x2 = rnorm(50, -4, 0.5))
scaler <- app_glofas_normal_readout_scaler_fit(X_raw, "train_zscore")
X_scaled <- app_glofas_normal_readout_scaler_apply(X_raw, scaler)
beta_scaled <- c(0.2, -0.7, 1.1)
beta_raw <- app_glofas_normal_readout_beta_to_raw(beta_scaled, scaler)
stopifnot(max(abs(as.numeric(X_scaled %*% beta_scaled) - as.numeric(X_raw %*% beta_raw))) < 1e-12)
draws <- rbind(beta_scaled, beta_scaled + c(0.1, 0.2, -0.3))
draws_raw <- app_glofas_normal_readout_beta_draws_to_raw(draws, scaler)
stopifnot(max(abs(X_scaled %*% t(draws) - X_raw %*% t(draws_raw))) < 1e-12)

set.seed(46)
X <- cbind(1, matrix(rnorm(120), nrow = 30))
y <- as.numeric(X %*% c(0.4, -0.3, 0.2, 0.1, -0.1) + rnorm(30, sd = 0.1))
ridge <- app_glofas_normal_ridge_fit(X, y, ridge_tau2 = 10)
warm <- list(
  type = "glofas_normal_part1_ridge_warm_start", version = "0.1", candidate_id = "toy",
  design = list(colnames = colnames(X)),
  fit = list(beta_mean = ridge$beta_mean, beta_var_diag = ridge$beta_var_diag,
    sigma_a = ridge$sigma_a, sigma_b = ridge$sigma_b, sigma2_mean = ridge$sigma2_mean, p = ridge$p)
)
class(warm) <- c("glofas_normal_part1_ridge_warm_start", "list")
rhs <- app_glofas_normal_rhs_fit(
  X, y, warm, tau0 = 0.1, zeta2_fixed = 4, max_iter = 5L, min_iter = 5L, tol = 0,
  freeze_beta_warmup_iters = 2L, min_beta_updates = 3L
)
stopifnot(identical(rhs$trace$beta_solve_performed, c(FALSE, FALSE, TRUE, TRUE, TRUE)))
stopifnot(all(rhs$trace$zeta_update_enabled == FALSE))
stopifnot(all(abs(rhs$trace$e_inv_zeta2 - 0.25) < 1e-12))
stopifnot(rhs$iterations == 5L, rhs$rhs_state$tau_update_count >= 1L)

tau <- app_glofas_search2_calibrated_tau0(m0 = 100, p_penalized = 3000, sigma_ref = 0.2, n_fit = 10000)
stopifnot(abs(tau - (100 / 2900) * 0.2 / 100) < 1e-15)

path <- data.frame(
  job_id = "toy_job", candidate_id = "toy", fold_id = "toy_fold", target = "reference", method = "ridge",
  prior_id = NA_character_, origin_date = toy_fold$origin_date,
  date = toy_fold$origin_date + 1:30, horizon = 1:30,
  pred_mean = packets$scoring$observed, pred_sd = 0.1, stringsAsFactors = FALSE
)
score <- app_glofas_search2_score_forecast(path, packets$scoring)
stopifnot(nrow(score$summary) == 2L, score$summary$n_score[[1L]] == 28L, score$summary$n_score[[2L]] == 30L)
stopifnot(all(is.finite(score$summary$mean_crps)))

agg_input <- rbind(
  transform(score$summary, candidate_id = "a", mean_crps = c(0.10561, 0.10570)),
  transform(score$summary, candidate_id = "b", mean_crps = c(0.10564, 0.10573))
)
aggregate_score <- app_glofas_search2_aggregate_scores(agg_input)
stopifnot(nrow(aggregate_score) == 2L)
stopifnot(all(aggregate_score$equivalence_4dp))

guardrail_input <- do.call(rbind, lapply(c("anchor", "good", "bad"), function(id) {
  transform(
    score$summary,
    candidate_id = id,
    candidate_role = if (id == "anchor") "phase1_legacy_anchor" else "space_filling_primary",
    mean_crps = if (id == "anchor") c(0.12, 0.13) else if (id == "good") c(0.10, 0.11) else c(0.09, 0.10),
    historical_all_rmse = if (id == "bad") 1.02 else 1,
    historical_last200_rmse = if (id == "bad") 1.04 else 1,
    fit_converged = TRUE,
    finite_pass = TRUE,
    diagnostic_decision = "pass",
    sampled_saturation_fraction = 0.1,
    sampled_relative_effective_rank = 0.5,
    runtime_seconds = 1,
    D = 1L,
    n_state_features = 100L
  )
}))
guardrail_score <- app_glofas_search2_aggregate_scores(guardrail_input, require_folds = 1L)
stopifnot(guardrail_score$candidate_id[[1L]] == "good")
stopifnot(!guardrail_score$promotion_eligible[guardrail_score$candidate_id == "bad"])
stopifnot(all(guardrail_score$guardrail_baseline_available))

rhs_candidates <- candidate_manifest[seq_len(3L), , drop = FALSE]
rhs_candidates$candidate_id <- c("anchor", "good", "bad")
rhs_candidates$candidate_role <- c("phase1_legacy_anchor", "space_filling_primary", "space_filling_primary")
rhs_selected <- app_glofas_search2_select_rhs_architectures(
  transform(guardrail_score, target = "reference"), rhs_candidates,
  n_top = 1L, n_diverse = 1L
)
stopifnot(sum(rhs_selected$rhs_selection_role == "phase1_legacy_anchor") == 1L)
