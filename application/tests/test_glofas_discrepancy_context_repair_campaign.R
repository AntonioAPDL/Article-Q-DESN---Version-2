candidate_path <- app_path(
  "application/config/glofas_discrepancy_context_repair_candidates_20260825.csv"
)
repair_candidates <- app_glofas_context_repair_validate_candidates(
  app_read_csv(candidate_path)
)
stopifnot(nrow(repair_candidates) == 10L)
stopifnot(sum(repair_candidates$execution_stage == "stage0") == 2L)
stopifnot(sum(repair_candidates$execution_stage == "stage1") == 8L)
stopifnot(all(
  repair_candidates$warm_start_compatibility_mode[
    repair_candidates$execution_stage == "stage0"
  ] == "exact_design"
))
stopifnot(all(!repair_candidates$warm_start_use_theta[
  repair_candidates$execution_stage == "stage1"
]))

source_fixture <- data.frame(
  source_fit_object = "/tmp/source.rds",
  stringsAsFactors = FALSE
)
warm_exact <- app_glofas_context_repair_warm_start_config(
  repair_candidates[repair_candidates$candidate_id == "t01_last", , drop = FALSE],
  source_fixture
)
stopifnot(isTRUE(warm_exact$enabled))
stopifnot(isTRUE(warm_exact$use_theta))
stopifnot(identical(warm_exact$compatibility_mode, "exact_design"))
warm_state <- app_glofas_context_repair_warm_start_config(
  repair_candidates[repair_candidates$candidate_id == "c01_level_readout", , drop = FALSE],
  source_fixture
)
stopifnot(!isTRUE(warm_state$use_theta))
stopifnot(isTRUE(warm_state$use_future))
stopifnot(identical(warm_state$compatibility_mode, "state_only"))

trace_fit <- list(vb_diagnostics = list(
  converged = FALSE,
  iterations = 300L,
  elbo_trace = c(seq(1, 290), rep(300, 10)),
  parameter_change_trace = c(rep(0.01, 299), 0.0004)
))
trace_summary <- app_glofas_context_repair_trace_summary(trace_fit)
stopifnot(isTRUE(trace_summary$vb_stable_at_cap[[1L]]))
stopifnot(isTRUE(trace_summary$vb_numerical_gate[[1L]]))
trace_fit$vb_diagnostics$parameter_change_trace[[300L]] <- 0.002
stopifnot(!app_glofas_context_repair_trace_summary(trace_fit)$vb_numerical_gate[[1L]])

timeline <- data.frame(
  date = as.Date("2020-01-01") + 0:5,
  glofas_level = c(1, 2, 3, 4, 5, 6),
  glofas_level_scaled = c(-1.5, -0.5, 0.5, 1.5, 2.5, 3.5),
  glofas_level_uses_realized_future = FALSE,
  stringsAsFactors = FALSE
)
attr(timeline, "scale_params") <- list(
  glofas_level = list(center = 2.5, scale = 1)
)
design_fixture <- list(
  discrepancy_transition_contract = list(
    context = list(glofas_level = TRUE, glofas_anomaly = FALSE)
  ),
  feature_meta_alpha = list(covariate_timeline = timeline),
  feature_info_alpha = data.frame(
    block = c("reservoir_state", "reservoir_state", "direct_covariate_lag"),
    variable = c(NA, NA, "glofas_level"),
    lag = c(NA, NA, 0L),
    column_name = c("reservoir_0001", "reservoir_0002", "glofas_level_lag_0"),
    stringsAsFactors = FALSE
  ),
  X_alpha = cbind(
    c(-0.5, 0.1, 0.5, 0.2, -0.1, 0.3),
    c(0.2, -0.4, 0.4, -0.2, 0.6, -0.6),
    timeline$glofas_level_scaled
  ),
  latent_data = list(origin_date = as.Date("2020-01-04"))
)
fit_fixture <- list(
  warm_start_contract = list(
    theta_names = c(
      "alpha__reservoir_0001", "alpha__reservoir_0002",
      "alpha__glofas_level_lag_0"
    )
  ),
  variational_state = list(
    theta_mean = c(0.1, 0.2, 0.3),
    theta_cov = diag(c(0.01, 0.02, 0.03))
  )
)
context_audit <- app_glofas_context_repair_context_audit(
  design_fixture, fit_fixture, "fixture", "cutoff"
)
stopifnot(nrow(context_audit$context) == 1L)
stopifnot(context_audit$context$future_outside_history_fraction[[1L]] == 1)
stopifnot(nrow(context_audit$coefficients) == 1L)
stopifnot(context_audit$coefficients$posterior_mean[[1L]] == 0.3)
stopifnot(context_audit$states$n_state_columns[[1L]] == 2L)
stopifnot(is.finite(context_audit$states$state_effective_rank[[1L]]))

stopifnot(app_glofas_context_repair_bias_gate(-0.02, 0.01, 0.02))
stopifnot(!app_glofas_context_repair_bias_gate(-0.05, 0.01, 0.02))

cat("GloFAS discrepancy-context repair campaign tests passed.\n")
