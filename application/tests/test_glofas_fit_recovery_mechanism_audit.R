mechanism_draws <- app_glofas_mechanism_draw_indices(100L, 5L)
stopifnot(identical(mechanism_draws, c(1L, 26L, 50L, 75L, 100L)))
stopifnot(length(app_glofas_mechanism_draw_indices(3L, 10L)) == 3L)

mechanism_info <- data.frame(
  block = c("readout_intercept", "reservoir_state", "direct_output_lag", "direct_covariate_lag"),
  variable = c(NA, NA, "y", "ppt"),
  stringsAsFactors = FALSE
)
mechanism_X <- matrix(c(1, 2, 3, 4, 1, 3, 2, 5), nrow = 2L, byrow = TRUE)
mechanism_coef <- c(1, 0.5, -0.25, 0.1)
mechanism_contrib <- app_glofas_mechanism_contributions(
  mechanism_X, mechanism_coef, mechanism_info, "alpha", "fixture", 1:2
)
mechanism_sum <- aggregate(contribution ~ horizon, mechanism_contrib, sum)
stopifnot(isTRUE(all.equal(mechanism_sum$contribution, as.numeric(mechanism_X %*% mechanism_coef))))

mechanism_history <- rbind(mechanism_X, mechanism_X + 0.1, mechanism_X - 0.1)
mechanism_future <- mechanism_X
mechanism_future[2, 2] <- 20
mechanism_shift <- app_glofas_mechanism_shift(
  mechanism_history, mechanism_future, mechanism_info, "alpha_readout", "fixture", 1:2
)
stopifnot(max(mechanism_shift$max_abs_z) > 5)

mechanism_scores <- app_glofas_mechanism_score_paths(
  y = c(2, 2), raw = c(1, 1), q_g = c(1, 1), q_y = c(4, 4), last_discrepancy = -1
)
stopifnot(
  mechanism_scores$check_loss_mean[mechanism_scores$path == "discrepancy_persistence"] <
    mechanism_scores$check_loss_mean[mechanism_scores$path == "learned_discrepancy"]
)

mechanism_decision <- app_glofas_mechanism_decision(
  exact_draw_summary = data.frame(max_abs_q_y_diff = 0.01, max_abs_d_g_diff = 0.02),
  state_shift = data.frame(block = "alpha_reservoir", max_abs_z = 8),
  feature_shift = data.frame(block = "alpha_readout", max_abs_z = 9),
  counterfactual_scores = mechanism_scores
)
stopifnot(identical(
  mechanism_decision$primary_mechanism[[1L]],
  "discrepancy_state_or_readout_extrapolation"
))
