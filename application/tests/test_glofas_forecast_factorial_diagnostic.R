# Generated factorial target, reporting and crossing checks only.
local({
  source("scripts/diagnostics/glofas_global_path_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_forecast_factorial_diagnostic.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  near <- function(x, y, tolerance) ok(max(abs(x - y)) <= tolerance)
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  H <- 2L
  issued <- matrix(-1, H, 51L)
  callback <- function(path) list(
    reference_location = c(0, .1 * tanh(path[1L])),
    ensemble_location = c(0, .5 * path[1L]))
  grid <- gffd_grid("generated", .5, issued, .7, .2, c(0, 0), diag(2),
    "generated_fixed_parameters", "generated_causal_features")
  ok(length(grid) == 4L)
  ok(sum(vapply(grid, function(x) x$promotion_eligible, logical(1L))) == 1L)
  ok(all(!vapply(grid, function(x) x$exact_legacy_augmented_replay, logical(1L))))
  unit <- grid[["same_family_al_transition__unit_member_likelihood_v1"]]
  fractional <- grid[[paste("same_family_al_transition",
    "fractional_marginal_information_diagnostic_v1", sep = "__")]]
  path <- c(1, 0)
  a <- gffd_log_target(path, callback, unit, TRUE)
  b <- gffd_log_target(path, callback, fractional, TRUE)
  near(a$path, b$path, 0)
  near(a$members, 51 * b$members, 1e-10)
  ok(a$total < b$total)
  tampered <- unit; tampered$sigma_y <- 1
  reject(gffd_log_target(path, callback, tampered))

  empty <- matrix(numeric(), H, 0L)
  gaussian <- gffd_contract("generated", .5, empty, .7, .2,
    "gaussian_path_prior", "unit_member_likelihood_v1", c(.2, -.1),
    matrix(c(.5, .1, .1, .4), 2L), "fixed", "features")
  importance_control <- list(particles = 10000L, seed = 2026110603L,
    max_evaluations = 10000L, max_wall_seconds = 60,
    min_ess_fraction = .99, max_weight_fraction = .001)
  reference <- gffd_reference(gaussian, callback, gaussian$gaussian_path_mean,
    gaussian$gaussian_path_covariance, c(.05, .5, .95), importance_control)
  ok(reference$importance$status == "REFERENCE_GATE_PASS" &&
    !reference$future_truth_read && reference$full_parameter_refits == 0L)
  near(reference$importance$mean, gaussian$gaussian_path_mean, .04)
  report <- gffd_reporting(reference, callback,
    list(mean = c(.2, -.1), covariance = gaussian$gaussian_path_covariance))
  ok(setequal(unique(report$reporting_operator), c(
    "marginal_future_response_quantile",
    "legacy_weighted_mean_readout_location",
    "local_gaussian_delta_marginal_quantile")))
  marginal <- report[report$reporting_operator == "marginal_future_response_quantile", ]
  near(marginal$estimate, c(.2, -.1), .04)

  crossing_rows <- data.frame(horizon = rep(1:2, each = 3),
    probability = rep(c(.05, .5, .95), 2),
    estimate = c(0, 1, .5, 0, .5, 1), reporting_operator = "raw")
  crossings <- gffd_crossings(crossing_rows)
  ok(sum(crossings$crossing_pairs) == 1L &&
    max(crossings$maximum_crossing) == .5)
  authentic_fractional <- gffd_contract("authentic", .5, matrix(0, 28, 51), .7, .2,
    "same_family_al_transition", "fractional_marginal_information_diagnostic_v1",
    parameter_id = "x", feature_id = "y")
  ok(authentic_fractional$authentic_source_diagnostic_only &&
    !authentic_fractional$promotion_eligible &&
    !authentic_fractional$exact_legacy_augmented_replay)
  reject(gffd_contract("authentic", .5, matrix(0, 27, 51), .7, .2,
    "same_family_al_transition", "unit_member_likelihood_v1",
    parameter_id = "x", feature_id = "y"))
  bad_callback <- function(path) list(reference_location = 0,
    ensemble_location = rep(0, H))
  reject(gffd_log_target(path, bad_callback, unit))
  message("GLOFAS_FORECAST_FACTORIAL_DIAGNOSTIC_PASS checks=", checks,
    " authentic_reads=0 scientific_fits=0")
})

