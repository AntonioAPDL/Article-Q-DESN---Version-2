script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- sub("^--file=", "", script_arg[[1L]])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_path)), "..", ".."))
source(file.path(repo_root, "application/R/pricefm_recursive_forecast.R"))

regions <- c("A", "B", "C")
initial_histories <- list(A = c(1, 2), B = c(10, 20), C = c(100, 200))
initial_states <- list(A = 0, B = 0, C = 0)
parameters <- setNames(lapply(regions, function(region) rep(list(list(sd = 0)), 3L)), regions)

teacher <- app_pricefm_causal_teacher_forcing(
  observed_prices = list(A = c(1, 2, 999), B = c(10, 20, 999), C = c(100, 200, 999)),
  start_index = 3L,
  build_input = function(region, time_index, histories, exogenous) {
    c(last_seen = utils::tail(histories[[region]], 1L), panel_last_mean = mean(vapply(histories, tail, numeric(1L), n = 1L)))
  },
  regions = regions,
  calculation_order = rev(regions)
)
stopifnot(all(vapply(teacher$inputs, function(x) x[["last_seen"]], numeric(1L)) < 999))
stopifnot(all(teacher$audit$information_end_index == teacher$audit$time_index - 1L))
stopifnot(all(teacher$audit$response == 999))

build_input <- function(region, horizon, path_id, histories, exogenous, parameter) {
  c(panel_mean = mean(vapply(histories, tail, numeric(1L), n = 1L)))
}
transition <- function(region, state, input, horizon, path_id, parameter) input[["panel_mean"]]
predict <- function(region, state, input, horizon, path_id, parameter) state
draw <- function(region, location, state, input, horizon, path_id, parameter) location

forward <- app_pricefm_recursive_panel(
  initial_histories, initial_states, horizon = 3L, n_paths = 3L,
  parameter_draws = parameters, exogenous = NULL, build_input = build_input,
  transition_state = transition, predict_location = predict, draw_response = draw,
  regions = regions, calculation_order = regions, seed = 42L,
  history_limits = c(A = 1L, B = 2L, C = 2L)
)
reverse <- app_pricefm_recursive_panel(
  initial_histories, initial_states, horizon = 3L, n_paths = 3L,
  parameter_draws = parameters, exogenous = NULL, build_input = build_input,
  transition_state = transition, predict_location = predict, draw_response = draw,
  regions = regions, calculation_order = rev(regions), seed = 42L,
  history_limits = c(A = 1L, B = 2L, C = 2L)
)
stopifnot(isTRUE(all.equal(forward$response_draws, reverse$response_draws, tolerance = 0)))
stopifnot(all(forward$response_draws[, 1L, ] == mean(c(2, 20, 200))))
stopifnot(all(forward$input_audit$panel_snapshot == "all_regions_h_minus_1"))
stopifnot(identical(forward$contract$update_order, "build_all_predict_all_draw_all_then_update_all"))
stopifnot(ncol(forward$final_histories$A) == 1L, ncol(forward$final_histories$B) == 2L)

stochastic_draw <- function(region, location, state, input, horizon, path_id, parameter) {
  location + stats::rnorm(1L)
}
stochastic_forward <- app_pricefm_recursive_panel(
  initial_histories, initial_states, horizon = 2L, n_paths = 3L,
  parameter_draws = parameters, exogenous = NULL, build_input = build_input,
  transition_state = transition, predict_location = predict, draw_response = stochastic_draw,
  regions = regions, calculation_order = regions, seed = 77L
)
stochastic_reverse <- app_pricefm_recursive_panel(
  initial_histories, initial_states, horizon = 2L, n_paths = 3L,
  parameter_draws = parameters, exogenous = NULL, build_input = build_input,
  transition_state = transition, predict_location = predict, draw_response = stochastic_draw,
  regions = regions, calculation_order = rev(regions), seed = 77L
)
stopifnot(isTRUE(all.equal(stochastic_forward$response_draws, stochastic_reverse$response_draws, tolerance = 0)))
stopifnot(identical(stochastic_forward$seed_ledger[order(stochastic_forward$seed_ledger$path_id, stochastic_forward$seed_ledger$horizon, stochastic_forward$seed_ledger$region), ],
                    stochastic_reverse$seed_ledger[order(stochastic_reverse$seed_ledger$path_id, stochastic_reverse$seed_ledger$horizon, stochastic_reverse$seed_ledger$region), ]))

ids <- app_pricefm_recursive_path_ids(5L)
resume <- app_pricefm_recursive_resume_plan(ids, ids[c(1L, 3L)])
stopifnot(identical(resume$pending_path_ids, ids[c(2L, 4L, 5L)]))
bad_resume <- try(app_pricefm_recursive_resume_plan(ids, c(ids[[1L]], ids[[1L]])), silent = TRUE)
stopifnot(inherits(bad_resume, "try-error"))

driver_copy <- forward$response_draws
quantile_parameters <- setNames(lapply(regions, function(region) rep(list(list(offset = 1)), 3L)), regions)
quantile <- app_pricefm_quantile_on_common_driver(
  forward, tau = c(0.1, 0.5), parameter_draws = quantile_parameters,
  evaluate_quantile = function(region, horizon, path_id, tau, common_driver, parameter) {
    common_driver[path_id, as.character(horizon), region] + parameter$offset + tau
  }
)
stopifnot(identical(forward$response_draws, driver_copy))
stopifnot(identical(quantile$common_driver_path_ids, forward$path_ids))
stopifnot(identical(quantile$contract, "quantile_outputs_do_not_feed_primary_endogenous_path"))

mixture_median <- app_pricefm_mixture_quantile(
  list(function(x) stats::pnorm(x, -1, 1), function(x) stats::pnorm(x, 1, 1)),
  tau = 0.5, lower = -10, upper = 10
)
stopifnot(abs(mixture_median) < 1e-7)

cat("PriceFM recursive forecast tests passed.\n")
