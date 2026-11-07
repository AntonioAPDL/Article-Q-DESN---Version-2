# Generated qualification of the global path reference against deterministic
# low-dimensional integration and a bounded H=28 causal contract.
local({
  source("scripts/diagnostics/glofas_al_path_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_global_path_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_forecast_factorial_diagnostic.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  near <- function(x, y, tolerance) ok(max(abs(x - y)) <= tolerance)

  callback_h1 <- function(path) list(reference_location = 0,
    ensemble_location = .35 * path)
  issued_h1 <- matrix(c(-.15, .1, .25), 1L)
  contract_h1 <- gffd_contract("generated", .5, issued_h1, .8, .5,
    "same_family_al_transition", "unit_member_likelihood_v1",
    parameter_id = "generated_h1_parameters", feature_id = "generated_h1_features")
  target_h1 <- function(path) gffd_log_target(path, callback_h1, contract_h1)
  exact_h1 <- gapr_one_dimensional_reference(function(y) target_h1(y),
    split_points = c(-.15 / .35, 0, .1 / .35, .25 / .35),
    probabilities = c(.05, .5, .95))
  control_h1 <- list(particles = 30000L, seed = 2026110604L,
    max_evaluations = 30000L, max_wall_seconds = 60,
    min_ess_fraction = 0, max_weight_fraction = 1)
  sampled_h1 <- ggpr_importance(target_h1, 0, matrix(.7, 1L),
    c(.05, .5, .95), control_h1)
  sampled_h1_q <- sampled_h1$quantiles$quantile
  near(sampled_h1_q, exact_h1$quantiles, .06)
  ok(exact_h1$estimated_normalization_error < 1e-7 &&
    exact_h1$quantile_tightening < 1e-6)

  callback_h2 <- function(path) list(
    reference_location = c(0, .3 * tanh(path[1L])),
    ensemble_location = c(.2 * path[1L], .25 * tanh(path[1L]) + .2 * path[2L]))
  issued_h2 <- matrix(c(-.1, .2, .05, .1, -.15, .25), 2L, 3L)
  contract_h2 <- gffd_contract("generated", .5, issued_h2, .9, .7,
    "same_family_al_transition", "unit_member_likelihood_v1",
    parameter_id = "generated_h2_parameters", feature_id = "generated_h2_features")
  target_h2 <- function(path) gffd_log_target(path, callback_h2, contract_h2)
  grid <- seq(-5, 5, length.out = 201L)
  grid_paths <- as.matrix(expand.grid(grid, grid))
  grid_log <- vapply(seq_len(nrow(grid_paths)),
    function(i) target_h2(grid_paths[i, ]), numeric(1L))
  grid_weights <- ggpr_weights(grid_log)
  grid_mean <- colSums(grid_paths * grid_weights)
  grid_centered <- sweep(grid_paths, 2L, grid_mean)
  grid_covariance <- crossprod(grid_centered * sqrt(grid_weights),
    grid_centered * sqrt(grid_weights))
  grid_quantiles <- do.call(rbind, lapply(1:2, function(h)
    ggpr_weighted_quantile(grid_paths[, h], grid_weights, c(.05, .5, .95))))
  control_h2 <- list(particles = 25000L, seed = 2026110605L,
    max_evaluations = 25000L, max_wall_seconds = 60,
    min_ess_fraction = 0, max_weight_fraction = 1)
  sampled_h2 <- ggpr_importance(target_h2, grid_mean, grid_covariance,
    c(.05, .5, .95), control_h2)
  near(sampled_h2$mean, grid_mean, .06)
  near(sampled_h2$quantiles$quantile, as.numeric(t(grid_quantiles)), .16)
  ok(sampled_h2$effective_sample_size > 10000 && sampled_h2$maximum_weight < .005)

  H <- 28L
  issued_h28 <- matrix(0, H, 51L)
  callback_h28 <- function(path) {
    reference <- numeric(H)
    ensemble <- numeric(H)
    for (h in seq_len(H)) {
      prefix <- if (h == 1L) 0 else path[h - 1L]
      reference[h] <- .12 * tanh(prefix)
      ensemble[h] <- reference[h] + .04 * tanh(prefix)
    }
    list(reference_location = reference, ensemble_location = ensemble)
  }
  contract_h28 <- gffd_contract("authentic", .5, issued_h28, 1, 25,
    "same_family_al_transition", "unit_member_likelihood_v1",
    parameter_id = "generated_h28_parameters", feature_id = "generated_h28_features")
  contract_hash <- digest::digest(contract_h28, algo = "sha256", serialize = TRUE)
  callback_environment <- environment(callback_h28)
  control_h28 <- list(particles = 1200L, seed = 2026110606L,
    max_evaluations = 1200L, max_wall_seconds = 60,
    min_ess_fraction = 0, max_weight_fraction = 1)
  sampled_h28 <- ggpr_importance(
    function(path) gffd_log_target(path, callback_h28, contract_h28),
    rep(0, H), diag(.8, H), c(.05, .5, .95), control_h28)
  ok(nrow(sampled_h28$paths) == 1200L && ncol(sampled_h28$paths) == H &&
    nrow(sampled_h28$quantiles) == 3L * H && all(is.finite(sampled_h28$quantiles$quantile)))
  ok(!sampled_h28$future_truth_read && sampled_h28$full_parameter_refits == 0L &&
    !sampled_h28$production_qualified)
  ok(identical(contract_hash,
    digest::digest(contract_h28, algo = "sha256", serialize = TRUE)) &&
    identical(environment(callback_h28), callback_environment))
  ok(identical(contract_h28$truth_access, "forbidden") &&
    identical(contract_h28$members, 51L) && identical(contract_h28$horizon, 28L))

  message("GLOFAS_GLOBAL_PATH_GENERATED_QUALIFICATION_PASS checks=", checks,
    " authentic_reads=0 scientific_fits=0 H28=TRUE")
})
