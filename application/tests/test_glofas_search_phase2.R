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

tiny_candidate <- candidate_manifest[1L, , drop = FALSE]
tiny_candidate$candidate_id <- "toy_reusable_ridge"
tiny_candidate$target <- "reference"
tiny_candidate$method <- "ridge"
tiny_candidate$D <- 1L
tiny_candidate$n_vector <- "12"
tiny_candidate$n_state_features <- 12L
tiny_candidate$output_lag_max <- 3L
tiny_candidate$covariate_lag_max <- 2L
tiny_candidate$m <- 3L
tiny_candidate$washout <- 5L
tiny_candidate$seed <- 47L
tiny_candidate$state_scaling <- "train_zscore"
tiny_candidate$ridge_tau2 <- 10
tiny_prepared <- app_glofas_search2_prepare_fit_inputs(packets$model, tiny_candidate)
warm_path <- tempfile(fileext = ".rds")
saveRDS(tiny_prepared$ridge_warm_start, warm_path, version = 2L)
tiny_rhs <- tiny_candidate
tiny_rhs$method <- "rhs"
tiny_rhs$ridge_warm_start_path <- warm_path
tiny_rhs$ridge_warm_start_sha256 <- app_sha256_file(warm_path)
tiny_reused <- app_glofas_search2_prepare_fit_inputs(packets$model, tiny_rhs)
stopifnot(isTRUE(tiny_reused$ridge_warm_start_reused))
stopifnot(identical(tiny_reused$ridge_fit$beta_mean, tiny_prepared$ridge_fit$beta_mean))
tiny_rhs$job_id <- "toy_rhs_reused"
tiny_rhs$fold_id <- "toy_fold"
tiny_rhs$prior_id <- "phase1_legacy_tau0"
tiny_rhs$prior_mode <- "legacy_tau0"
tiny_rhs$rhs_a_zeta <- 2
tiny_rhs$rhs_b_zeta <- 4
tiny_rhs$rhs_zeta2_fixed <- NA_real_
tiny_rhs$rhs_max_iter <- 3L
tiny_rhs$rhs_min_iter <- 3L
tiny_rhs$rhs_tol <- 0
tiny_rhs$rhs_update_every <- 1L
tiny_rhs$rhs_freeze_tau_warmup_iters <- 0L
tiny_rhs$rhs_min_tau_updates <- 1L
tiny_rhs$rhs_freeze_beta_warmup_iters <- 0L
tiny_rhs$rhs_min_beta_updates <- 3L
tiny_result <- app_glofas_search2_fit_and_forecast(
  packets$model, tiny_rhs, forecast_backend = "r", prepared = tiny_reused
)
stopifnot(nrow(tiny_result$path) == 30L, nrow(tiny_result$trace) == 3L)
stopifnot(isTRUE(tiny_result$summary$ridge_warm_start_reused))
stopifnot(nrow(tiny_result$coefficient_top) >= 1L, nrow(tiny_result$coefficient_activity) >= 1L)
unlink(warm_path)

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

practical_tie <- data.frame(
  candidate_id = c("lower_exact", "better_worst"), target = "reference", method = "rhs",
  prior_id = "prior", promotion_eligible = TRUE,
  mean_primary_crps = c(0.10561, 0.10564), worst_primary_crps = c(0.14, 0.12),
  mean_secondary_crps = c(0.11, 0.11), historical_guardrail_pass = TRUE,
  sampled_saturation_fraction = 0.1, sampled_relative_effective_rank = 0.5,
  runtime_seconds = 1, n_state_features = 100L, stringsAsFactors = FALSE
)
practical_tie <- app_glofas_search2_rank_aggregate(practical_tie)
stopifnot(practical_tie$candidate_id[[1L]] == "better_worst")
stopifnot(all(practical_tie$equivalence_4dp))

seed_cells <- do.call(rbind, lapply(c(101L, 102L), function(seed_value) {
  do.call(rbind, lapply(c("fold_a", "fold_b"), function(fold_value) {
    transform(
      score$summary,
      job_id = paste(seed_value, fold_value, score$summary$score_window, sep = "__"),
      candidate_id = paste0("seeded__seed", seed_value), base_candidate_id = "seeded",
      seed = seed_value, fold_id = fold_value, target = "reference", method = "rhs",
      prior_id = "prior", candidate_role = "ridge_top", rhs_selection_role = "ridge_top",
      fit_converged = TRUE, finite_pass = TRUE, diagnostic_decision = "pass"
    )
  }))
}))
seed_aggregate <- app_glofas_search2_aggregate_scores(seed_cells, require_folds = 4L)
stopifnot(nrow(seed_aggregate) == 1L)
stopifnot(seed_aggregate$candidate_id[[1L]] == "seeded")
stopifnot(seed_aggregate$n_folds[[1L]] == 4L, seed_aggregate$n_unique_folds[[1L]] == 2L)
stopifnot(seed_aggregate$n_seeds[[1L]] == 2L, seed_aggregate$complete_fold_pass[[1L]])

confirmation_jobs <- do.call(rbind, lapply(c("reference", "discrepancy"), function(target_value) {
  transform(
    expand.grid(
      fold_id = c("fold_a", "fold_b", "fold_c"),
      seed = c(201L, 202L, 203L),
      KEEP.OUT.ATTRS = FALSE,
      stringsAsFactors = FALSE
    ),
    target = target_value
  )[, c("target", "fold_id", "seed")]
}))
confirmation_reuse <- data.frame(
  target = rep(c("reference", "discrepancy"), each = 3L),
  fold_id = rep(c("fold_a", "fold_b", "fold_c"), 2L),
  seed = rep(c(101L, 102L), each = 3L),
  stringsAsFactors = FALSE
)
stopifnot(app_glofas_search2_confirmation_expected_cells(
  confirmation_jobs, confirmation_reuse
) == 12L)
incomplete_confirmation_jobs <- confirmation_jobs[-1L, , drop = FALSE]
stopifnot(inherits(try(
  app_glofas_search2_confirmation_expected_cells(
    incomplete_confirmation_jobs, confirmation_reuse
  ),
  silent = TRUE
), "try-error"))

confirmation_fixture <- tempfile("search2_confirmation_source_")
pilot_fixture <- tempfile("search2_confirmation_pilot_")
for (root in c(confirmation_fixture, pilot_fixture)) {
  invisible(lapply(file.path(root, c("configs", "scores", "fits", "status")), dir.create,
    recursive = TRUE, showWarnings = FALSE))
}
fixture_jobs <- function(candidate_id, root, source_seed = 700L) {
  jobs <- data.frame(
    job_id = paste0("job_", candidate_id, "_", c("fold_a", "fold_b")),
    target = "reference", candidate_id = candidate_id, prior_id = "prior_a",
    fold_id = c("fold_a", "fold_b"), seed = source_seed,
    D = 1L, n_vector = "10", n_state_features = 10L,
    output_lag_max = 2L, covariate_lag_max = 1L,
    alpha = 0.5, rho = 0.9, stringsAsFactors = FALSE
  )
  app_write_csv(jobs, file.path(root, "configs", "job_manifest.csv"))
  for (job_id in jobs$job_id) {
    app_write_csv(data.frame(job_id = job_id, mean_crps = 0.1),
      file.path(root, "scores", paste0(job_id, "_summary.csv")))
    app_write_csv(data.frame(job_id = job_id, horizon = 1L, crps = 0.1),
      file.path(root, "scores", paste0(job_id, "_detail.csv")))
    app_write_csv(data.frame(job_id = job_id, fit_converged = TRUE),
      file.path(root, "fits", paste0(job_id, "_summary.csv")))
    writeLines("done", file.path(root, "status", paste0(job_id, ".done")))
  }
  jobs
}
new_fixture_jobs <- fixture_jobs("new_candidate", confirmation_fixture)
reused_fixture_jobs <- fixture_jobs("reused_candidate", pilot_fixture)
reuse_fixture <- data.frame(
  target = reused_fixture_jobs$target, candidate_id = reused_fixture_jobs$candidate_id,
  prior_id = reused_fixture_jobs$prior_id, fold_id = reused_fixture_jobs$fold_id,
  score_summary_path = file.path(pilot_fixture, "scores", paste0(reused_fixture_jobs$job_id, "_summary.csv")),
  score_detail_path = file.path(pilot_fixture, "scores", paste0(reused_fixture_jobs$job_id, "_detail.csv")),
  fit_summary_path = file.path(pilot_fixture, "fits", paste0(reused_fixture_jobs$job_id, "_summary.csv")),
  source_runtime_root = pilot_fixture, stringsAsFactors = FALSE
)
reuse_fixture$score_summary_sha256 <- vapply(reuse_fixture$score_summary_path, app_sha256_file, character(1L))
reuse_fixture$score_detail_sha256 <- vapply(reuse_fixture$score_detail_path, app_sha256_file, character(1L))
reuse_fixture$fit_summary_sha256 <- vapply(reuse_fixture$fit_summary_path, app_sha256_file, character(1L))
app_write_csv(reuse_fixture, file.path(confirmation_fixture, "configs", "reused_score_registry.csv"))

source_fixture <- app_glofas_search2_confirmation_source_registry(confirmation_fixture)
stopifnot(nrow(source_fixture) == 4L)
stopifnot(sum(source_fixture$source_kind == "source_runtime_job") == 2L)
stopifnot(sum(source_fixture$source_kind == "reused_prior_runtime_job") == 2L)
fixture_finalists <- data.frame(
  target = "reference", candidate_id = c("new_candidate", "reused_candidate"),
  prior_id = "prior_a", stringsAsFactors = FALSE
)
fixture_folds <- data.frame(fold_id = c("fold_a", "fold_b"), stringsAsFactors = FALSE)
resolved_fixture <- app_glofas_search2_confirmation_templates(
  fixture_finalists, source_fixture, fixture_folds
)
stopifnot(nrow(resolved_fixture$templates) == 2L, nrow(resolved_fixture$source_cells) == 4L)
stopifnot(setequal(resolved_fixture$templates$candidate_id, fixture_finalists$candidate_id))

missing_fold_error <- try(
  app_glofas_search2_confirmation_templates(
    fixture_finalists, source_fixture,
    data.frame(fold_id = c("fold_a", "fold_b", "fold_c"), stringsAsFactors = FALSE)
  ),
  silent = TRUE
)
stopifnot(inherits(missing_fold_error, "try-error"))

duplicate_reuse <- rbind(reuse_fixture, reuse_fixture[1L, , drop = FALSE])
app_write_csv(duplicate_reuse, file.path(confirmation_fixture, "configs", "reused_score_registry.csv"))
stopifnot(inherits(try(
  app_glofas_search2_confirmation_source_registry(confirmation_fixture), silent = TRUE
), "try-error"))

bad_hash_reuse <- reuse_fixture
bad_hash_reuse$score_summary_sha256[[1L]] <- paste(rep("0", 64L), collapse = "")
app_write_csv(bad_hash_reuse, file.path(confirmation_fixture, "configs", "reused_score_registry.csv"))
stopifnot(inherits(try(
  app_glofas_search2_confirmation_source_registry(confirmation_fixture), silent = TRUE
), "try-error"))
app_write_csv(reuse_fixture, file.path(confirmation_fixture, "configs", "reused_score_registry.csv"))

candidate_complete <- app_bind_rows_fill(lapply(c("candidate_a", "candidate_b"), function(candidate_id) {
  transform(
    expand.grid(fold_id = c("fold_a", "fold_b"), seed = c(1L, 2L),
      KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE),
    target = "reference", base_candidate_id = candidate_id
  )
}))
stopifnot(app_glofas_search2_confirmation_expected_cells(candidate_complete) == 4L)
candidate_incomplete <- candidate_complete[-1L, , drop = FALSE]
stopifnot(inherits(try(
  app_glofas_search2_confirmation_expected_cells(candidate_incomplete), silent = TRUE
), "try-error"))
unlink(c(confirmation_fixture, pilot_fixture), recursive = TRUE, force = TRUE)

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

external_candidate <- transform(
  guardrail_score[guardrail_score$candidate_id == "good", , drop = FALSE],
  candidate_id = "confirmed", candidate_role = "ridge_top",
  historical_all_rmse = 1.02, historical_last200_rmse = 1.04,
  numerical_pass = TRUE, promotion_eligible = TRUE
)
external_baseline <- transform(
  guardrail_score[guardrail_score$candidate_id == "anchor", , drop = FALSE],
  historical_all_rmse = 1, historical_last200_rmse = 1
)
external_guardrail <- app_glofas_search2_apply_external_guardrails(external_candidate, external_baseline)
stopifnot(!external_guardrail$historical_guardrail_pass[[1L]])
stopifnot(!external_guardrail$promotion_eligible[[1L]])

rhs_candidates <- candidate_manifest[seq_len(3L), , drop = FALSE]
rhs_candidates$candidate_id <- c("anchor", "good", "bad")
rhs_candidates$candidate_role <- c("phase1_legacy_anchor", "space_filling_primary", "space_filling_primary")
rhs_selected <- app_glofas_search2_select_rhs_architectures(
  transform(guardrail_score, target = "reference"), rhs_candidates,
  n_top = 1L, n_diverse = 1L
)
stopifnot(sum(rhs_selected$rhs_selection_role == "phase1_legacy_anchor") == 1L)
