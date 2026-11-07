# Generated whole-path importance and likelihood-tempering checks only.
local({
  source("scripts/diagnostics/glofas_global_path_reference.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  near <- function(x, y, tolerance) ok(max(abs(x - y)) <= tolerance)
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  log_mvn <- function(mean, covariance) {
    root <- chol(covariance)
    function(x) ggpr_log_mvn(matrix(x, 1L), mean, root)[1L]
  }
  mean <- c(.5, -.4)
  covariance <- matrix(c(1, .3, .3, 1.4), 2L)
  control <- list(particles = 12000L, seed = 2026110601L,
    max_evaluations = 12000L, max_wall_seconds = 60,
    min_ess_fraction = .99, max_weight_fraction = .001)
  set.seed(991L); before <- .Random.seed
  exact <- ggpr_importance(log_mvn(mean, covariance), mean, covariance,
    c(.05, .5, .95), control)
  ok(identical(before, .Random.seed))
  ok(exact$status == "REFERENCE_GATE_PASS" &&
    exact$effective_sample_size > .999 * control$particles)
  near(exact$mean, mean, .04)
  near(exact$covariance, covariance, .06)
  ok(max(exact$weights) - min(exact$weights) < 1e-12)
  ok(!exact$time_sequential_resampling && !exact$future_truth_read &&
    exact$full_parameter_refits == 0L && !exact$production_qualified)
  repeated <- ggpr_importance(log_mvn(mean, covariance), mean, covariance,
    c(.05, .5, .95), control)
  ok(identical(exact$paths, repeated$paths) && identical(exact$weights, repeated$weights))

  target_mean <- c(1, -.5)
  target_covariance <- diag(c(.35, .5))
  temper_control <- list(particles = 800L, seed = 2026110602L,
    max_evaluations = 60000L, max_wall_seconds = 60,
    min_ess_fraction = .99, max_weight_fraction = .01,
    ess_target_fraction = .75, max_tempering_steps = 50L,
    rejuvenation_steps = 3L, random_walk_scale = .45,
    resample_final = TRUE)
  tempered <- ggpr_tempered(log_mvn(target_mean, target_covariance), c(0, 0),
    diag(2), c(.05, .5, .95), temper_control)
  ok(tempered$complete && tempered$beta == 1 &&
    tempered$status == "REFERENCE_GATE_PASS")
  near(tempered$mean, target_mean, .12)
  near(tempered$covariance, target_covariance, .14)
  ok(nrow(tempered$diagnostics) >= 2L &&
    all(diff(tempered$diagnostics$beta) > 0) &&
    all(tempered$diagnostics$unique_initial_lineages >= 2L))
  ok(!tempered$time_sequential_resampling && !tempered$future_truth_read &&
    tempered$full_parameter_refits == 0L && !tempered$production_qualified)
  repeat_tempered <- ggpr_tempered(log_mvn(target_mean, target_covariance), c(0, 0),
    diag(2), c(.05, .5, .95), temper_control)
  keep <- setdiff(names(tempered), "elapsed_seconds")
  ok(identical(tempered[keep], repeat_tempered[keep]))

  near(ggpr_weighted_quantile(1:4, c(.1, .2, .3, .4), c(.1, .3, .6, .99)),
    c(1, 2, 3, 4), 0)
  bad <- control; bad$particles <- 1L
  reject(ggpr_importance(log_mvn(mean, covariance), mean, covariance, .5, bad))
  bad <- temper_control; bad$ess_target_fraction <- 1
  reject(ggpr_tempered(log_mvn(mean, covariance), mean, covariance, .5, bad))
  reject(ggpr_importance(log_mvn(mean, covariance), mean, matrix(1, 2, 2), .5,
    control))
  message("GLOFAS_GLOBAL_PATH_REFERENCE_PASS checks=", checks,
    " authentic_reads=0 scientific_fits=0")
})

