#!/usr/bin/env Rscript
# Synthetic software fixtures only. Never discovers or reads scientific caches.
file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
repo <- normalizePath(file.path(dirname(file_arg), "../.."), mustWork = TRUE)
for (file in c("joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R",
  "latent_path_design.R", "joint_qdesn_recursive_mean_design.R",
  "joint_qdesn_recursive_mean_score_packet.R", "integrated_quantile_forecast.R"))
  source(file.path(repo, "application/R", file))
`%||%` <- function(a, b) if (is.null(a)) b else a
checks <- 0L
check <- function(condition) {
  stopifnot(isTRUE(condition)); checks <<- checks + 1L
}
reject <- function(expr, pattern = NULL) {
  result <- tryCatch({ force(expr); NULL }, error = identity)
  check(inherits(result, "error"))
  if (!is.null(pattern)) check(grepl(pattern, conditionMessage(result)))
}
hash <- paste(rep("a", 64L), collapse = "")

# Exact grid law: endpoint probability atoms, flat segments, and deterministic
# equal-weight projection. Sorting is not the specified contract.
tau <- c(.1, .5, .9)
check(identical(app_iqf_mq_grid_cdf(c(-1, 0, .5, 1, 2), c(0, 0, 1), tau), c(0, .5, .7, 1, 1)))
check(all(app_iqf_mq_grid_inverse(rep(3, 3), tau, c(0, .5, 1)) == 3))
check(all(app_iqf_mq_grid_cdf(c(2, 3, 4), rep(3, 3), tau) == c(0, 1, 1)))
check(all(app_iqf_grid(c(2, 0, 1), tau)$q == c(1, 1, 1)))
g <- list(family = "mq_grid", q = c(0, 0, 1), tau = tau)
check(max(abs(app_iqf_invert_cdf(list(g), c(.05, .3, .5, .7, .95)) - c(0, 0, 0, .5, 1))) < 1e-7)
reject(app_iqf_mq_grid_cdf(0, 1:3, c(.2, .1, .9)), "Invalid MQ")

# Knot/slope/jump inversion preserves the same generalized inverse as the
# original mixture-CDF bisection. Endpoint atoms, flats, disjoint support and
# CDF plateaus require the leftmost root, not interpolation through an atom.
mq_kernel <- function(q, p = tau) list(family = "mq_grid", q = q, tau = p)
mq_cases <- list(list(g), list(mq_kernel(rep(0, 3)), mq_kernel(rep(10, 3))),
  list(mq_kernel(c(-2, 0, 0)), mq_kernel(c(0, 0, 2))),
  list(mq_kernel(c(2, -1, 0)), mq_kernel(c(-3, 1, 1))),
  list(mq_kernel(c(-5, -4, -3)), mq_kernel(c(3, 4, 5))))
mq_probabilities <- c(.001, .05, .1, .3, .5, .500000001, .7, .9, .95, .999)
for (case in mq_cases) {
  fast <- app_iqf_mq_mixture_inverse(case, mq_probabilities, 1e-8)
  reference <- app_iqf_invert_cdf_bisection(case, mq_probabilities, 5e-9)
  check(max(abs(fast - reference)) < 1e-8)
  probe <- app_iqf_mixture_cdf(c(fast - 1e-8, fast + 1e-8), case)
  check(all(probe[seq_along(fast)] < mq_probabilities) &&
    all(probe[length(fast) + seq_along(fast)] >= mq_probabilities))
  q_matrix <- do.call(rbind, lapply(case, function(k) app_iqf_grid(k$q, k$tau)$q))
  cdf_probe <- sort(unique(c(-Inf, Inf, q_matrix, q_matrix - 1e-8, q_matrix + 1e-8)))
  check(max(abs(app_iqf_mq_matrix_cdf(cdf_probe, q_matrix, tau) -
    app_iqf_mixture_cdf(cdf_probe, case))) < 1e-12)
}
mq_tau7 <- c(.05, .10, .25, .50, .75, .90, .95)
set.seed(9361L)
for (L in c(1L, 3L, 8L, 21L)) for (replicate in seq_len(3L)) {
  grids <- lapply(seq_len(L), function(i) mq_kernel(
    round(stats::qnorm(mq_tau7) + stats::rnorm(7L, sd = .7) + stats::rnorm(1L), 1L), mq_tau7))
  rng_before <- .Random.seed
  fast <- app_iqf_invert_cdf(grids, mq_probabilities, 1e-8)
  reference <- app_iqf_invert_cdf_bisection(grids, mq_probabilities, 5e-9)
  check(max(abs(fast - reference)) < 1e-8)
  check(identical(.Random.seed, rng_before))
  q_matrix <- do.call(rbind, lapply(grids, function(k) app_iqf_grid(k$q, k$tau)$q))
  check(max(abs(app_iqf_mq_matrix_cdf(c(-5, -1, 0, 1, 5), q_matrix, mq_tau7) -
    app_iqf_mixture_cdf(c(-5, -1, 0, 1, 5), grids))) < 1e-12)
}
# Shared latent feature histories with one fixed stacked coefficient draw are
# also covered; no rank recoupling or change of independent/joint assembly.
features <- c(-2, -.3, .2, 1.7)
coupled_grids <- lapply(features, function(x) mq_kernel(
  stats::qnorm(mq_tau7) + x * seq(.1, .7, length.out = 7L), mq_tau7))
check(max(abs(app_iqf_mq_mixture_inverse(coupled_grids, mq_tau7) -
  app_iqf_invert_cdf_bisection(coupled_grids, mq_tau7, 5e-9))) < 1e-8)
# Translation and rescaling do not replace the original quantile-grid law.
scaled_grids <- lapply(coupled_grids, function(k) mq_kernel(7 + 2.3 * k$q, k$tau))
check(max(abs(app_iqf_mq_mixture_inverse(scaled_grids, mq_tau7) -
  (7 + 2.3 * app_iqf_mq_mixture_inverse(coupled_grids, mq_tau7)))) < 1e-8)
reject(app_iqf_mq_mixture_inverse(list(), .5), "Invalid MQ mixture")
heterogeneous <- list(g, mq_kernel(c(-1, 0, 2), c(.05, .6, .95)))
check(max(abs(app_iqf_mq_mixture_inverse(heterogeneous, mq_probabilities) -
  app_iqf_invert_cdf_bisection(heterogeneous, mq_probabilities, 5e-9))) < 1e-8)
extreme_narrow <- list(mq_kernel(c(0, 1e-320, 2e-320)))
check(max(abs(app_iqf_mq_mixture_inverse(extreme_narrow, mq_probabilities) -
  app_iqf_invert_cdf_bisection(extreme_narrow, mq_probabilities))) < 1e-8)

# Hash streams are stable scientific streams, preserve caller RNG, and extend
# by prefixes when L increases. No host/routing/resolution field enters the key.
set.seed(294L); old <- .Random.seed; old_kind <- RNGkind()
seed <- app_iqf_seed("immutable-science", "chain1/draw9", "origin3", 7, 2, "response")
a <- app_iqf_rng(seed, function() stats::runif(8))
b <- app_iqf_rng(seed, function() stats::runif(8))
check(identical(a, b) && identical(.Random.seed, old) && identical(RNGkind(), old_kind))
check(!identical(seed, app_iqf_seed("immutable-science", "chain1/draw9", "origin3", 8, 2, "response")))
check(!identical(seed, app_iqf_seed("immutable-science", "chain1/draw9", "origin3", 7, 2, "state_innovation")))

# Fresh paired AL/exAL errors and normalized CDFs. In particular the exAL
# location is the designated quantile at nonzero shape, not a Gaussian median.
for (p in c(.05, .5, .9)) {
  check(abs(app_iqf_error_cdf(0, 0, 1.7, "al", p) - p) < 1e-12)
  support <- app_joint_exqdesn_support(p)
  for (gamma in c(support$lower / 5, 0, support$upper / 5)) {
    check(abs(app_iqf_error_cdf(0, 0, 1.7, "exal", p, gamma) - p) < 2e-7)
  }
}
al <- app_iqf_error_noise("al", .25, 2, 0, seed)
ex0 <- app_iqf_error_noise("exal", .25, 2, 0, seed)
check(identical(al$error, ex0$error))
check(al$error != app_iqf_error_noise("al", .25, 3, 0, seed)$error)
reject(app_iqf_error_noise("al", .5, NA_real_, 0, seed), "paired positive")

# A tiny native direct design exercises the *existing* feature/readout helpers.
# Its coefficient on lag_y is 2; the known seasonal/trend coefficients are 0.
feature_names <- app_joint_qvp_registry_feature_names("ar_fixture")
design <- list(scenario_id = "synthetic_ar", design_class = "direct",
  feature_contract = "legacy_fixture", Z = matrix(0, 3L, length(feature_names),
    dimnames = list(NULL, feature_names)), row_meta = data.frame(full_time_index = 1:3),
  dgp_row = data.frame(simulated_length = 100L, period = 12L,
    regime_start_fraction = .5, dynamics_class = "ar_fixture"),
  reservoir_meta = list(win_scale_global = 1))
posterior <- list(beta = matrix(c(2, rep(0, length(feature_names) - 1L)), nrow = 1L),
  alpha = matrix(0, 1L, 1L), sigma = 1, gamma = 0,
  draw_ids = "chain1/draw1", chain_id = 1L, source_draw_index = 1L)
origins <- list(o3 = list(origin_time = 3L, H = 2L, history = c(0, 0, 0),
  observed_input_features = matrix(0, 3L, length(feature_names), dimnames = list(NULL, feature_names))))
adapter <- app_iqf_desn_adapter(design, posterior, origins, .5, "normal",
  rng_namespace = "synthetic_normal_ar_v1")
small <- app_iqf_run_task(adapter, "chain1/draw1", "o3", 8L, c(.5, .95), "ar", include_paths = TRUE)
large <- app_iqf_run_task(adapter, "chain1/draw1", "o3", 1800L, c(.5, .95), "ar", include_paths = TRUE)
check(identical(small$paths, large$paths[1:8, , drop = FALSE]))
# Y1=e1; Y2=2 e1+e2. Therefore q_.95(Y2)=sqrt(5) Phi^-1(.95).
q2 <- large$quantiles$quantile[large$quantiles$horizon == 2L]
check(abs(q2[1L]) < .13)
check(abs(q2[2L] - sqrt(5) * stats::qnorm(.95)) < .2)
check(abs(large$quantiles$quantile[large$quantiles$horizon == 1L &
  large$quantiles$probability == .95] - stats::qnorm(.95)) < 1e-7)
# The terminal locations remain dispersed under fixed theta; they are NOT
# posterior draws of q_h(theta). Integrating errors gives the correct wider law.
check(stats::sd(vapply(large$cdf_components[[2L]], `[[`, numeric(1L), "mu")) > 1.7)
check(abs(q2[2L] - stats::qnorm(.95)) > 1.5)
rerouted <- app_iqf_run_task(adapter, "chain1/draw1", "o3", 8L, c(.5, .95), "ar", include_paths = TRUE)
check(identical(small, rerouted))
check(identical(small$original_draw, list(chain_id = 1L, source_draw_index = 1L)))

# Native reservoir-only recursion (identity activation) realizes the same AR.
# This traverses the actual reservoir snapshot/continue/readout implementation,
# not a test-only predictor callback. Appended future design rows are ignored.
reservoir_design <- design
reservoir_design$design_class <- "reservoir"
reservoir_design$reservoir <- list(D = 1L, n = 1L, alpha = 1,
  W = list(matrix(0)), Win = list(matrix(c(0, 1, 0, 0, 0, 0), nrow = 1L)),
  act_f = "identity", act_k = "identity")
reservoir_design$state_center <- 0; reservoir_design$state_scale <- 1
reservoir_design$Z <- matrix(c(0, 0, 0, 999, 999), ncol = 1L,
  dimnames = list(NULL, "reservoir_0001"))
reservoir_design$row_meta <- data.frame(full_time_index = 1:5)
reservoir_design$scale_params <- list(standardize = FALSE,
  center = stats::setNames(rep(0, length(feature_names)), feature_names),
  scale = stats::setNames(rep(1, length(feature_names)), feature_names))
reservoir_posterior <- posterior; reservoir_posterior$beta <- matrix(2)
reservoir_adapter <- app_iqf_desn_adapter(reservoir_design, reservoir_posterior, origins,
  .5, "normal", rng_namespace = "synthetic_normal_ar_v1")
reservoir_result <- app_iqf_run_task(reservoir_adapter, "chain1/draw1", "o3", 8L,
  c(.5, .95), "ar", include_paths = TRUE)
check(identical(small$paths, reservoir_result$paths))
check(identical(small$quantiles$quantile, reservoir_result$quantiles$quantile))

# Exercise the installed package's real explicit-noise recursion on a synthetic
# fit schema. This is NOT use of that version for any historical fitted result.
if (requireNamespace("exdqlm", quietly = TRUE)) {
  native_env <- NULL
  native <- get0("forecast_paths.qdesn_fit", envir = asNamespace("exdqlm"), mode = "function")
  # Optional explicit source-code fixture, never a fit/cache. Source bytes are
  # hashed before loading. This proves the sourced-kernel interface only, not
  # historical 1.0.0/1.1.1 execution parity under the installed 1.1.2 runtime.
  fixture_root <- Sys.getenv("IQF_NATIVE_FIXTURE_ROOT", unset = "")
  kernel_paths <- c("R/00_utils.R", "R/qdesn_vb.R")
  if (is.null(native) && nzchar(fixture_root) && all(file.exists(file.path(fixture_root, kernel_paths)))) {
    native_manifest <- data.frame(relative_path = kernel_paths,
      size_bytes = file.info(file.path(fixture_root, kernel_paths))$size,
      sha256 = vapply(file.path(fixture_root, kernel_paths), app_iqf_hash, character(1L), file = TRUE),
      role = "native_kernel")
    native_env <- app_iqf_load_native_kernels(fixture_root, native_manifest, kernel_paths,
      as.character(utils::packageVersion("exdqlm")))
    native <- get("forecast_paths.qdesn_fit", envir = native_env)
  }
  if (is.function(native) && "noise_draws" %in% names(formals(native))) {
    native_object <- list(fit = list(misc = list(p0 = .5)), X = matrix(0, 3L, 1L),
      meta = list(D = 1L, m = 1L, m_input = 1L, add_bias = FALSE, p_res = 1L),
      reservoir = list(D = 1L, n = 1L, alpha = 1, W = list(matrix(0)),
        Win = list(matrix(c(0, 1), nrow = 1L)), act_f = "identity", act_k = "identity"))
    native_origins <- origins
    native_origins$o3$origin_state <- list(0)
    native_origins$o3$readout_spec <- list(p_res = 1L)
    native_posterior <- posterior; native_posterior$beta <- matrix(2)
    native_adapter <- app_iqf_single_desn_adapter(native_object, native_posterior, native_origins,
      "al", .5, "native_package_synthetic", as.character(utils::packageVersion("exdqlm")),
      app_iqf_hash(list(formals(native), body(native))), native_env)
    native_path <- native_adapter$path("chain1/draw1", "o3", 1L)
    check(length(native_path$response) == 2L && all(is.finite(native_path$response)))
    check(native_path$kernels[[1L]]$mu == 0)
    check(native_path$kernels[[2L]]$mu == 2 * native_path$response[1L])
    reject(app_iqf_single_desn_adapter(native_object, native_posterior, native_origins,
      "al", .5, "native_package_synthetic", "0.0.0", hash), "unavailable")
    reject(app_iqf_single_desn_adapter(native_object, native_posterior, native_origins,
      "al", .5, "native_package_synthetic", as.character(utils::packageVersion("exdqlm")), hash,
      native_env), "hash")
  } else cat("SKIP_OPTIONAL_NATIVE_INTERFACE_TEST: supply IQF_NATIVE_FIXTURE_ROOT explicitly; no production qualification implied.\n")
} else cat("SKIP_OPTIONAL_NATIVE_INTERFACE_TEST: exdqlm unavailable; no production qualification implied.\n")

# Fixed parameter + no feedback: integrated-quantile uncertainty collapses,
# although each simulated response remains noisy. No location/path surrogate.
constant <- posterior; constant$beta[,] <- 0
constant$beta <- constant$beta[rep(1L, 2L), , drop = FALSE]
constant$alpha <- matrix(0, 2L, 1L); constant$sigma <- c(1, 1); constant$gamma <- c(0, 0)
constant$draw_ids <- c("chain1/draw1", "chain2/draw1"); constant$chain_id <- 1:2
constant$source_draw_index <- c(1L, 1L)
fixed <- app_iqf_desn_adapter(design, constant, origins, .5, "normal", rng_namespace = "fixed_theta")
s1 <- app_iqf_run_task(fixed, constant$draw_ids[1L], "o3", 3L, c(.5, .95), "constant")
s2 <- app_iqf_run_task(fixed, constant$draw_ids[2L], "o3", 3L, c(.5, .95), "constant")
s1$identity <- s2$identity <- list(source_commit = paste(rep("a", 40L), collapse = ""),
  source_tree = paste(rep("b", 40L), collapse = ""), source_manifest_sha256 = hash,
  posterior_target_sha256 = hash, input_manifest_sha256 = hash, task_manifest_sha256 = hash,
  rng_namespace = "fixed_theta", outer_conditioning = "parameters_and_observed_origin_reservoir_state")
check(identical(s1$quantiles$quantile, s2$quantiles$quantile))
accuracy <- app_iqf_run_task(fixed, constant$draw_ids[1L], "o3", 4L, c(.5, .95),
  "constant", diagnose_integration = TRUE)
check(all(accuracy$integration_diagnostic$split_stream_absolute_difference == 0))
dkw <- app_iqf_run_task(fixed, constant$draw_ids[1L], "o3", 128L, c(.5, .95),
  "constant", mc_confidence_alpha = .05)
check(all(dkw$integration_dkw$empirical_cdf_epsilon == sqrt(log(2 * 2 / .05) / (2 * 128))))
check(all(is.infinite(dkw$integration_dkw$upper[dkw$integration_dkw$probability == .95])))
check(is.null(dkw$paths))
reject(app_iqf_run_task(fixed, constant$draw_ids[1L], "o3", 3L, .5, "constant",
  mc_confidence_alpha = 2), "confidence budget")
reject(app_iqf_run_task(fixed, constant$draw_ids[1L], "o3", 4L, c(.5, .95),
  "constant", max_kernel_bytes = 10), "memory budget")
pp <- app_iqf_posterior_predictive(list(s1, s2), c(.5, .95))
check(identical(pp$quantile, s1$quantiles$quantile))
# Nonidentical posterior kernels: pooling CDFs is not averaging quantiles.
s_shift <- s2
for (h in seq_along(s_shift$cdf_components)) for (l in seq_along(s_shift$cdf_components[[h]])) {
  s_shift$cdf_components[[h]][[l]]$mu <- 5
  s_shift$cdf_components[[h]][[l]]$sigma <- .5
}
pooled <- app_iqf_posterior_predictive(list(s1, s_shift), .95)
check(abs(pooled$quantile[1L] - mean(c(stats::qnorm(.95), 5 + .5 * stats::qnorm(.95)))) > 1)
reject(app_iqf_posterior_predictive(list(s1, s1), .5), "unique outer")
shortened <- s2; shortened$cdf_components <- shortened$cdf_components[1L]
reject(app_iqf_posterior_predictive(list(s1, shortened), .5), "incomplete horizon")
shortened <- s2; shortened$cdf_components[[2L]] <- shortened$cdf_components[[2L]][1L]
reject(app_iqf_posterior_predictive(list(s1, shortened), .5), "inner-kernel")
mixed <- s2; mixed$identity$posterior_target_sha256 <- paste(rep("d", 64L), collapse = "")
reject(app_iqf_posterior_predictive(list(s1, mixed), .5), "mixed scientific")
missing <- s1; missing$cdf_components <- NULL
reject(app_iqf_posterior_predictive(list(missing), .5), "quantiles-only")
nonfinite <- s2; nonfinite$cdf_components[[1L]][[1L]]$mu <- NA_real_
reject(app_iqf_posterior_predictive(list(s1, nonfinite), .5), "Nonfinite")
wrong_law <- s2; wrong_law$cdf_components[[2L]][[1L]]$family <- "al"
reject(app_iqf_posterior_predictive(list(s1, wrong_law), .5), "mix response laws")

# Native MQ coupling is mandatory; all classes use the same grid response law.
mqpost <- posterior
mqpost$beta <- matrix(rep(posterior$beta, 3L), nrow = 1L)
mqpost$alpha <- matrix(c(-1, 0, 1), nrow = 1L)
coupling <- list(method = "native_joint_posterior", recipe_sha256 = hash, draw_mapping_sha256 = hash)
mq <- app_iqf_desn_adapter(design, mqpost, origins, tau, "mq_grid", coupling, "mq_fixture")
mq_result <- app_iqf_run_task(mq, "chain1/draw1", "o3", 4L, tau, "mq")
check(max(abs(mq_result$quantiles$quantile[mq_result$quantiles$horizon == 1L] - c(-1, 0, 1))) < 1e-7)
reject(app_iqf_desn_adapter(design, mqpost, origins, tau, "mq_grid", NULL, "mq_fixture"), "coupling")

# DQLM/exDQLM state integration preserves the conditional origin-state law AND
# future W. It refuses a saved point state without either authentic joint draws
# or a retained conditional covariance. This toy has Var(Y1)=2, Var(Y2)=6.
state_model <- list(family = "normal", tau = .5, state_conditioning = "per_parameter_draw",
  outer_conditioning = "parameters_only_integrate_filtered_origin_state",
  state_evolution = "known_G_W", state_source_sha256 = hash, evolution_source_sha256 = hash)
state_origins <- origins
state_origins$o3$conditional_state <- list(list(kind = "conditional_gaussian", mean = 0, covariance = matrix(0)))
state_origins$o3$future_G <- list(list(matrix(2), matrix(2)))
state_origins$o3$future_W <- list(list(matrix(1), matrix(1)))
state_origins$o3$future_F <- list(list(1, 1))
state_adapter <- app_iqf_state_space_adapter(state_model, posterior, state_origins, "state_fixture")
state <- app_iqf_run_task(state_adapter, "chain1/draw1", "o3", 1300L, .95, "dlm")
check(identical(state$outer_conditioning, state_model$outer_conditioning) &&
  identical(state$identity$outer_conditioning, state_model$outer_conditioning))
check(abs(state$quantiles$quantile[1L] - sqrt(2) * stats::qnorm(.95)) < .2)
check(abs(state$quantiles$quantile[2L] - sqrt(6) * stats::qnorm(.95)) < .25)
bad <- state_origins; bad$o3$conditional_state[[1L]] <- list(kind = "point_state", value = 0)
reject(app_iqf_state_space_adapter(state_model, posterior, bad, "state_fixture"), "Point-state")
bad <- state_origins; bad$o3$future_W <- NULL
reject(app_iqf_state_space_adapter(state_model, posterior, bad, "state_fixture"), "future G/F/W")
mixed_states <- state_origins
mixed_states$o3$conditional_state <- list(state_origins$o3$conditional_state[[1L]],
  list(kind = "joint_retained_draw", value = 0))
reject(app_iqf_state_conditioning(state_model, mixed_states), "mix outer-conditioning")
mixed_origins <- state_origins; mixed_origins$o4 <- mixed_origins$o3
mixed_origins$o4$conditional_state <- list(list(kind = "joint_retained_draw", value = 0))
reject(app_iqf_state_conditioning(state_model, mixed_origins), "mix outer-conditioning")
joint_model <- state_model; joint_model$outer_conditioning <- "parameters_and_joint_retained_origin_state"
reject(app_iqf_state_conditioning(joint_model, state_origins), "freeze its explicit")
joint_origins <- state_origins
joint_origins$o3$conditional_state <- list(list(kind = "joint_retained_draw", value = 0))
joint_adapter <- app_iqf_state_space_adapter(joint_model, posterior, joint_origins, "joint_state_fixture")
joint_state <- app_iqf_run_task(joint_adapter, "chain1/draw1", "o3", 2L, .5, "joint_state")
check(identical(joint_state$identity$outer_conditioning, joint_model$outer_conditioning))
reject(app_iqf_psd_factor(matrix(-1)), "not positive")

# Truth firewall: never permit teacher-forced future responses, even if they
# are conveniently present in a retained forecast object or plotting fixture.
bad <- origins; bad$o3$history <- c(bad$o3$history, 99)
reject(app_iqf_desn_adapter(design, posterior, bad, .5, "normal", rng_namespace = "x"), "observed cutoff")
bad <- origins; bad$o3$future_y <- c(100, 200)
reject(app_iqf_desn_adapter(design, posterior, bad, .5, "normal", rng_namespace = "x"), "truth")

# Sum and count first, posterior intervals second; missing/duplicated work and
# unbound between-model row pairing are hard errors.
scores <- data.frame(model_id = c("a", "a", "a", "a"), draw_id = c("d1", "d1", "d2", "d2"),
  origin_id = c("o1", "o2", "o1", "o2"), horizon = 1L,
  source_manifest_sha256 = hash, posterior_target_sha256 = hash,
  outer_conditioning = "parameters_and_observed_origin_reservoir_state",
  score_sum = c(1, 9, 2, 18), score_count = c(1, 3, 1, 3))
keys <- do.call(paste, c(scores[c("model_id", "draw_id", "origin_id", "horizon")], sep = "|"))
agg <- app_iqf_aggregate_scores(list(scores[1:2, ], scores[3:4, ]), keys)
check(identical(agg$draw_scores$score, c(2.5, 5)))
check(agg$summary$mean == 3.75)
check(all(agg$draw_scores$outer_conditioning == scores$outer_conditioning[1L]) &&
  agg$summary$outer_conditioning == scores$outer_conditioning[1L])
mixed_score <- scores; mixed_score$outer_conditioning[2L] <- "parameters_only_integrate_filtered_origin_state"
reject(app_iqf_aggregate_scores(list(mixed_score), keys), "mixed outer-conditioning")
other_model <- scores; other_model$model_id <- "b"
other_model$outer_conditioning <- "parameters_only_integrate_filtered_origin_state"
combined_score <- rbind(scores, other_model)
combined_keys <- do.call(paste, c(combined_score[c("model_id", "draw_id", "origin_id", "horizon")], sep = "|"))
different_conventions <- app_iqf_aggregate_scores(list(combined_score), combined_keys)
check(nrow(different_conventions$summary) == 2L &&
  length(unique(different_conventions$summary$outer_conditioning)) == 2L)
reject(app_iqf_aggregate_scores(list(scores, scores[1L, ]), keys), "Duplicate")
reject(app_iqf_aggregate_scores(list(scores[-1L, ]), keys), "missing")
reversed <- app_iqf_aggregate_scores(list(scores[4:1, ]), keys)
check(identical(agg, reversed))
pairing <- data.frame(pair_id = "p1", left_model = "a", left_draw_id = "d1",
  right_model = "a", right_draw_id = "d2", pairing_contract_sha256 = hash)
check(app_iqf_contrasts(agg$draw_scores, pairing)$contrast == -2.5)
reject(app_iqf_contrasts(agg$draw_scores, data.frame()), "Explicit")

# Authenticated compact bundle enrollment, tamper rejection and path confinement.
tmp <- tempfile("iqf_synthetic_bundle_"); dir.create(tmp)
saveRDS(design, file.path(tmp, "design.rds"))
saveRDS(posterior, file.path(tmp, "posterior.rds"))
saveRDS(origins, file.path(tmp, "origins.rds"))
spec <- list(schema_version = "integrated_quantile_forecast_bundle_v1", adapter = "mq_desn_native_v1",
  identity = list(source_commit = paste(rep("a", 40), collapse = "")),
  payloads = list(design = "design.rds", posterior = "posterior.rds", origins = "origins.rds"))
saveRDS(spec, file.path(tmp, "spec.rds"))
files <- c("design.rds", "posterior.rds", "origins.rds", "spec.rds")
manifest <- data.frame(relative_path = files, size_bytes = file.info(file.path(tmp, files))$size,
  sha256 = vapply(file.path(tmp, files), app_iqf_hash, character(1L), file = TRUE),
  role = c("retained_design", "retained_posterior", "observed_prefix", "bundle_spec"))
mp <- file.path(tmp, "manifest.csv"); utils::write.csv(manifest, mp, row.names = FALSE)
bundle <- app_iqf_prepare_bundle(tmp, mp, "spec.rds", app_iqf_hash(mp, TRUE))
check(identical(bundle$payloads$posterior, posterior))

# The CSV-to-native-matrix converter verifies real source bytes and an explicit
# cross-level mapping. Reusing one correlated row is mandatory for joint fits.
worker <- data.frame(beta_0001 = c(1, 2), beta_0002 = c(3, 4), beta_0003 = c(5, 6),
  alpha_0001 = c(10, 20), alpha_0002 = c(30, 40), alpha_0003 = c(50, 60))
connection <- gzfile(file.path(tmp, "posterior.csv.gz"), "wt")
utils::write.csv(worker, connection, row.names = FALSE); close(connection)
wm <- data.frame(relative_path = "posterior.csv.gz", size_bytes = file.info(file.path(tmp, "posterior.csv.gz"))$size,
  sha256 = app_iqf_hash(file.path(tmp, "posterior.csv.gz"), TRUE), role = "retained_posterior")
mapping <- data.frame(draw_id = "chain1/draw1", quantile_index = 1:3, chain_id = 1L,
  source_draw_index = 1L, source_relative_path = "posterior.csv.gz")
converted <- app_iqf_materialize_mq_draws(tmp, wm, mapping, 1L, tau, "native_joint_posterior")
check(identical(as.numeric(converted$beta), c(1, 3, 5)))
check(identical(as.numeric(converted$alpha), c(10, 30, 50)))
mapping$source_draw_index[2L] <- 2L
reject(app_iqf_materialize_mq_draws(tmp, wm, mapping, 1L, tau, "native_joint_posterior"), "correlated source row")
independent <- app_iqf_materialize_mq_draws(tmp, wm, mapping, 1L, tau,
  "frozen_product_posterior_assembly")
check(identical(as.numeric(independent$beta), c(1, 4, 5)))
check(identical(independent$source_draw_index[[1L]], c(1L, 2L, 1L)))
reject(app_iqf_safe_path(tmp, "../not_allowed"), "confined")
claimed_out <- file.path(tmp, "fresh_claim_output")
check(app_iqf_verify_output_root(claimed_out, claimed_out))
reject(app_iqf_verify_output_root(claimed_out, paste0(claimed_out, "_other")), "exactly match")
reject(app_iqf_verify_output_root(tmp, tmp), "existing claimed")
if (.Platform$OS.type == "unix") {
  linked_parent <- file.path(tmp, "linked_output_parent")
  if (file.symlink(tmp, linked_parent)) {
    linked_out <- file.path(linked_parent, "fresh_claim")
    reject(app_iqf_verify_output_root(linked_out, linked_out), "Symbolic-link output ancestry")
  }
}
saveRDS(list(tampered = TRUE), file.path(tmp, "posterior.rds"))
reject(app_iqf_prepare_bundle(tmp, mp, "spec.rds", app_iqf_hash(mp, TRUE)), "artifact changed")
symlink <- file.path(tmp, "linked_design.rds")
if (file.symlink(file.path(tmp, "design.rds"), symlink))
  reject(app_iqf_safe_path(tmp, "linked_design.rds"), "Symbolic-link")

# Pure synthetic acceptance-envelope construction proves the Python controller's
# exact artifact/identity contract without admitting or executing a real claim.
out <- file.path(tmp, "synthetic_output"); dir.create(out)
saveRDS(list(synthetic = TRUE), file.path(out, "one.rds"))
output_table <- data.frame(relative_path = "one.rds", size_bytes = file.info(file.path(out, "one.rds"))$size,
  sha256 = app_iqf_hash(file.path(out, "one.rds"), TRUE), draw_id = "d1", origin_id = "o1",
  integration_status = "PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE", artifact_key = "draw:d1|origin:o1")
utils::write.csv(output_table, file.path(out, "output_manifest.csv"), row.names = FALSE)
request <- list(task_id = "synthetic", routing_id = "route1", rng_namespace = "science1",
  source_commit = paste(rep("b", 40L), collapse = ""), source_tree = paste(rep("c", 40L), collapse = ""),
  source_manifest_sha256 = hash, posterior_target_sha256 = hash, input_manifest_sha256 = hash,
  task_manifest_sha256 = hash, expected_output_keys_sha256 = hash,
  expected_output_keys = "draw:d1|origin:o1")
claim <- list(verified = TRUE, task_id = "synthetic", routing_id = "route1", claim_nonce = "synthetic_nonce")
envelope <- app_iqf_output_envelope(request, claim, output_table, out)
check(envelope$schema_version == "forecast_transition_output_v1" && envelope$numerical_gates_pass)
check(length(envelope$shards) == 1L && length(envelope$artifacts) == 2L)
check(envelope$shards[[1L]]$key == "draw:d1|origin:o1")
review_table <- output_table; review_table$integration_status <- "REVIEW_INNER_INTEGRATION_RESOLUTION"
utils::write.csv(review_table, file.path(out, "output_manifest.csv"), row.names = FALSE)
check(!app_iqf_output_envelope(request, claim, review_table, out)$numerical_gates_pass)
bad_claim <- claim; bad_claim$routing_id <- "stale_route"
reject(app_iqf_output_envelope(request, bad_claim, review_table, out), "identity")
saveRDS(1, file.path(out, "unowned_extra.rds"))
reject(app_iqf_output_envelope(request, claim, review_table, out), "Uninventoried")
unlink(tmp, recursive = TRUE)

# Default CLI cannot start science, write a result, or infer authorization.
cli <- system2(file.path(R.home("bin"), "Rscript"),
  shQuote(file.path(repo, "application/scripts/run_integrated_quantile_forecast.R")),
  stdout = TRUE, stderr = TRUE)
check(any(grepl("NO_LAUNCH", cli)) && is.null(attr(cli, "status")))
noauth <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
  c(shQuote(file.path(repo, "application/scripts/run_integrated_quantile_forecast.R")), "--mode", "run"),
  stdout = TRUE, stderr = TRUE))
check(!is.null(attr(noauth, "status")) && any(grepl("requires a frozen request", noauth)))
cat(sprintf("test_integrated_quantile_forecast: PASS (%d synthetic checks; zero production tasks)\n", checks))
