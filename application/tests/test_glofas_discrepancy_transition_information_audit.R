transition_horizon <- 1:4
transition_identity <- app_glofas_transition_operator(transition_horizon, 0)
stopifnot(identical(unname(transition_identity), diag(4)))

transition_cumulative <- app_glofas_transition_operator(transition_horizon, 1)
stopifnot(identical(
  unname(transition_cumulative),
  matrix(c(1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1), 4, 4)
))

transition_innovation <- c(1, -0.5, 0.25, 2)
transition_path <- app_glofas_transition_path(-2, transition_innovation, 0.75)
transition_recurrence <- numeric(length(transition_innovation))
state <- 0
for (h in seq_along(transition_innovation)) {
  state <- 0.75 * state + transition_innovation[[h]]
  transition_recurrence[[h]] <- -2 + state
}
stopifnot(max(abs(transition_path - transition_recurrence)) < 1e-12)

transition_X <- matrix(seq_len(20) / 7, nrow = 4, ncol = 5)
transition_beta <- seq_len(5) / 11
stopifnot(max(abs(
  as.numeric(app_glofas_transition_design(transition_X, 0.75) %*% transition_beta) -
    as.numeric(app_glofas_transition_operator(1:4, 0.75) %*% (transition_X %*% transition_beta))
)) < 1e-12)

transition_J <- lapply(seq_len(4), function(h) {
  matrix((seq_len(15) + h) / 19, nrow = 5, ncol = 3)
})
transition_J_star <- app_glofas_transition_jacobians(transition_J, 0.75)
transition_delta <- c(0.2, -0.4, 0.7)
transition_direct <- vapply(seq_len(4), function(h) {
  sum(app_glofas_transition_operator(1:4, 0.75)[h, seq_len(h)] *
    vapply(transition_J[seq_len(h)], function(J) {
      sum((J %*% transition_delta) * transition_beta)
    }, numeric(1L)))
}, numeric(1L))
transition_transformed <- vapply(transition_J_star, function(J) {
  sum((J %*% transition_delta) * transition_beta)
}, numeric(1L))
stopifnot(max(abs(transition_direct - transition_transformed)) < 1e-12)

transition_bad_phi <- tryCatch({
  app_glofas_transition_operator(1:3, 1.01)
  NULL
}, error = function(e) e)
stopifnot(inherits(transition_bad_phi, "error"))
transition_bad_horizon <- tryCatch({
  app_glofas_transition_operator(c(1, 3), 0.5)
  NULL
}, error = function(e) e)
stopifnot(inherits(transition_bad_horizon, "error"))

transition_identifiability <- app_glofas_transition_future_identifiability(
  diag(3),
  matrix(c(1, 0, 1, 0, 1, 1, 1, 1, 0), 3, 3)
)
stopifnot(transition_identifiability$reference_rank[[1L]] == 3L)
stopifnot(transition_identifiability$discrepancy_rank[[1L]] == 3L)
stopifnot(transition_identifiability$canonical_near_one[[1L]] == 3L)
stopifnot(!transition_identifiability$future_sum_identifies_components[[1L]])

transition_panel <- data.frame(
  g_transformed = c(1.2, 1.6, 1.1),
  y_transformed = c(1.0, 1.3, 1.2),
  horizon = 0L
)
transition_baseline <- c(0.1, 0.2, 0.3)
transition_increment <- transition_panel$g_transformed -
  transition_panel$y_transformed - transition_baseline
transition_fixture_design <- list(
  z_fixed = c(
    transition_panel$y_transformed,
    transition_panel$y_transformed + transition_increment
  ),
  source_fixed = factor(rep(c("Y", "G"), each = 3), levels = c("Y", "G")),
  base_panel = transition_panel,
  discrepancy_baseline_fixed = transition_baseline,
  discrepancy_baseline_future = rep(-0.25, 4),
  discrepancy_transition_strategy = "persistence_anchored_innovation"
)
transition_contract <- app_glofas_transition_historical_contract(transition_fixture_design)
stopifnot(transition_contract$response_identity_passed[[1L]])
stopifnot(transition_contract$history_horizons[[1L]] == "0")
stopifnot(transition_contract$future_baseline_unique_values[[1L]] == 1L)
stopifnot(!transition_contract$target_semantics_match[[1L]])

transition_prediction <- data.frame(
  target_date = as.Date("2022-12-26") + 0:3,
  horizon = 1:4,
  qhat_summary = "posterior_draw_mean",
  y_reference = c(1.0, 1.5, 1.2, 2.0),
  raw_glofas_quantile = c(0.8, 1.0, 0.7, 1.1),
  discrepancy_hat = c(-0.2, -0.3, -0.1, -0.4)
)
transition_counterfactual <- app_glofas_transition_counterfactual(
  transition_prediction,
  last_discrepancy = -0.25,
  phi = c(0, 1)
)
transition_phi0 <- transition_counterfactual$paths[
  transition_counterfactual$paths$phi == 0,
]
stopifnot(max(abs(
  transition_phi0$estimated_discrepancy - transition_prediction$discrepancy_hat
)) < 1e-12)
stopifnot(all(
  transition_counterfactual$metrics$diagnostic_status ==
    "no_refit_counterfactual_not_model_evidence"
))

transition_registry <- app_glofas_transition_draft_registry()
stopifnot(nrow(transition_registry) == 7L)
stopifnot(all(!transition_registry$launch_authorized))
stopifnot(any(transition_registry$transition == "cumulative_innovation"))
