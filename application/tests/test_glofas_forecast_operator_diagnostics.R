#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_forecast_operator_diagnostics.R"))

compiled <- list(
  static_values = matrix(c(1, NA, 2, NA, 3, NA), nrow = 3L, byrow = TRUE),
  future_index = matrix(c(0L, 0L, 0L, 1L, 0L, 2L), nrow = 3L, byrow = TRUE)
)
recursive <- app_glofas_operator_apply_endogenous_policy(compiled, "stochastic_recursive", 10, c(11, 12, 13))
stopifnot(identical(recursive$future_index, compiled$future_index), recursive$deployable)
frozen <- app_glofas_operator_apply_endogenous_policy(compiled, "frozen_last", 10, c(11, 12, 13))
stopifnot(all(frozen$future_index == 0L), identical(frozen$static_values[cbind(2:3, 2)], c(10, 10)))
teacher <- app_glofas_operator_apply_endogenous_policy(compiled, "teacher_forced", 10, c(11, 12, 13))
stopifnot(all(teacher$future_index == 0L), identical(teacher$static_values[cbind(2:3, 2)], c(11, 12)))
stopifnot(!teacher$deployable, teacher$truth_used_in_inputs)

if (!requireNamespace("Rcpp", quietly = TRUE) || !requireNamespace("RcppArmadillo", quietly = TRUE)) {
  stop("Rcpp and RcppArmadillo are required for the operator diagnostic test.", call. = FALSE)
}
Rcpp::sourceCpp(app_path("application/src/glofas_oracle_desn_forecast.cpp"), rebuild = FALSE, showOutput = FALSE)
cpp <- glofas_oracle_d1_draw_recursive_cpp(
  W = matrix(0.2, 1L, 1L), Win = matrix(c(0.1, 0.4, -0.2), 1L, 3L), state0 = 0,
  static_values = matrix(c(1, 2, 1, NA), nrow = 2L, byrow = TRUE),
  future_index = matrix(c(0L, 0L, 0L, 1L), nrow = 2L, byrow = TRUE),
  lag_center = c(0, 0), lag_scale = c(1, 1), standardize_inputs = FALSE,
  input_bound = "none", win_scale_global = 1, win_scale_bias = 1, alpha = 0.5,
  beta_draws = matrix(c(0.2, 0.8, 0.1, 0.9), nrow = 2L, byrow = TRUE),
  sigma_draws = c(0.1, 0.2), z_obs = matrix(0, 2L, 2L), act_f = "tanh"
)
stopifnot(
  identical(dim(cpp$forecast_draws), c(2L, 2L)),
  length(cpp$state_norm_mean) == 2L,
  length(cpp$state_saturation_mean) == 2L,
  all(is.finite(cpp$state_norm_mean)),
  all(cpp$state_saturation_mean >= 0 & cpp$state_saturation_mean <= 1)
)

cat("GLOFAS_FORECAST_OPERATOR_DIAGNOSTIC_TEST_PASS\n")
