# Generated-only outer-score optimization of a collapsed particle bound.
# No authentic reads, source loading, native dispatch or production authority.
# eta=m+L diag(exp(log_sd)) epsilon, with fixed invertible L (NULL means I).
# All supplied means and log standard deviations are optimized; this family
# is not an unrestricted full covariance family. L is never learned here.
#
# With inner randomness U~K(.|eta) independent of phi CONDITIONAL ON eta,
# d_phi E_qphi E_K[log Zhat(eta,U)] = E[score_qphi(eta) log Zhat(eta,U)].
# Thus this outer likelihood-ratio estimator does not drop an inner resampling
# derivative. It does not optimize the inner proposal. Historical ELBO terms
# may instead be supplied analytically, INCLUDING entropy, to avoid noisy
# high-dimensional historical rewards. Either route keeps the full parameter
# target and its same-measure density ratio; neither freezes it at a point.

gcpopt_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS collapsed parameter optimizer: ", why), call. = FALSE)
  invisible(TRUE)
}
gcpopt_number <- function(x) is.numeric(x) && length(x) > 0L && all(is.finite(x))
gcpopt_hash <- function(x) {
  gcpopt_require(requireNamespace("digest", quietly = TRUE), "digest is required for in-memory seals")
  digest::digest(x, algo = "sha256", serialize = TRUE)
}
gcpopt_plain <- function(x, depth = 0L) {
  gcpopt_require(depth <= 12L && !is.function(x) && !is.environment(x) && !isS4(x) &&
    (is.null(x) || is.numeric(x) || is.character(x) || is.logical(x) || is.list(x)) && !is.object(x),
    "plain declared generated inputs only")
  if (is.list(x)) for (v in x) gcpopt_plain(v, depth + 1L)
  else if (is.numeric(x)) gcpopt_require(all(is.finite(x)), "finite declared numeric inputs required")
  else gcpopt_require(!anyNA(x), "missing declared inputs forbidden")
  invisible(TRUE)
}
gcpopt_input_contract <- function(parameter_names, coordinate_measure, target_inputs, source_sha256) {
  gcpopt_require(is.character(parameter_names) && length(parameter_names) > 0L &&
    all(nzchar(parameter_names)) && !anyDuplicated(parameter_names) &&
    is.character(coordinate_measure) && length(coordinate_measure) == 1L && nzchar(coordinate_measure) &&
    is.list(target_inputs) && is.character(source_sha256) && length(source_sha256) > 0L &&
    all(grepl("^[a-f0-9]{64}$", source_sha256)), "exact names, measure, inputs and source identities required")
  gcpopt_plain(target_inputs)
  list(schema_version = "glofas_generated_outer_score_input_v1", scope = "generated_only",
    parameter_names = parameter_names, coordinate_measure = coordinate_measure,
    jacobian_policy = "caller_supplied_once_in_target_and_same_measure_log_q",
    inner_kernel_phi_independent = TRUE, target_inputs = target_inputs,
    target_inputs_sha256 = gcpopt_hash(target_inputs), source_sha256 = source_sha256,
    authentic_reads_authorized = FALSE, production_authorized = FALSE)
}
gcpopt_control <- function(max_iterations = 300L, batch_size = 64L, learning_rate = .03,
    minimum_iterations = 30L, gradient_tolerance = .01, gradient_mcse_tolerance = .02,
    step_tolerance = .001, objective_tolerance = .01, stable_iterations = 5L,
    max_evaluations = 100000L, max_wall_seconds = 300, seed = 2026110501L,
    gradient_clip = 100, log_sd_bounds = c(-12, 4),
    max_inner_calls = 10000000L, inner_call_bound = 100000L) {
  as.list(environment())
}
gcpopt_validate_control <- function(c) {
  q <- gcpopt_require
  q(is.list(c) && setequal(names(c), names(gcpopt_control())), "exact optimizer controls required; no frozen dimensions")
  integer_keys <- c("max_iterations", "batch_size", "minimum_iterations", "stable_iterations",
    "max_evaluations", "seed", "max_inner_calls", "inner_call_bound")
  q(all(vapply(c[integer_keys], function(x) gcpopt_number(x) && length(x) == 1L &&
    x == floor(x) && x > 0, logical(1L))) && c$max_iterations <= 1000L &&
    c$batch_size >= 4L && c$batch_size <= 4096L && c$minimum_iterations <= c$max_iterations &&
    c$stable_iterations >= 2L && c$stable_iterations <= 20L && c$seed <= .Machine$integer.max &&
    c$max_evaluations <= 1000000L && c$max_inner_calls <= 1000000000 &&
    c$inner_call_bound <= c$max_inner_calls, "bounded iteration, independent-sample and evaluation budgets required")
  keys <- c("learning_rate", "gradient_tolerance", "gradient_mcse_tolerance", "step_tolerance",
    "objective_tolerance", "max_wall_seconds", "gradient_clip")
  q(all(vapply(c[keys], function(x) gcpopt_number(x) && length(x) == 1L && x > 0, logical(1L))) &&
    c$learning_rate <= .2 && c$max_wall_seconds <= 3600 && gcpopt_number(c$log_sd_bounds) &&
    length(c$log_sd_bounds) == 2L && c$log_sd_bounds[1L] < c$log_sd_bounds[2L] &&
    c$log_sd_bounds[1L] >= -20 && c$log_sd_bounds[2L] <= 10,
    "finite optimizer tolerances and explicit variational-scale bounds required")
  invisible(TRUE)
}
gcpopt_factor <- function(factor, p) {
  if (is.null(factor)) return(list(matrix = NULL, inverse = NULL, log_abs_determinant = 0))
  gcpopt_require(p <= 512L && is.matrix(factor) && is.numeric(factor) &&
    identical(dim(factor), c(p, p)) && all(is.finite(factor)), "bounded fixed square factor required")
  inverse <- tryCatch(solve(factor), error = function(e) NULL)
  determinant <- determinant(factor, logarithm = TRUE)
  gcpopt_require(!is.null(inverse) && all(is.finite(inverse)) && determinant$sign != 0 &&
    is.finite(as.numeric(determinant$modulus)) && max(abs(factor %*% inverse - diag(p))) < 1e-8,
    "fixed factor must be numerically invertible")
  list(matrix = factor, inverse = inverse, log_abs_determinant = as.numeric(determinant$modulus))
}
gcpopt_score_gradient <- function(mean, log_sd, factor = NULL, epsilon, rewards,
    baseline = c("leave_one_out", "none"), include_entropy = TRUE) {
  baseline <- match.arg(baseline); p <- length(mean); B <- nrow(epsilon)
  q <- gcpopt_require
  q(gcpopt_number(mean) && gcpopt_number(log_sd) && length(log_sd) == p &&
    is.matrix(epsilon) && is.numeric(epsilon) && ncol(epsilon) == p && B >= 4L &&
    all(is.finite(epsilon)) && gcpopt_number(rewards) && length(rewards) == B &&
    is.logical(include_entropy) && length(include_entropy) == 1L && !is.na(include_entropy),
    "finite independent outer draws and rewards required")
  f <- gcpopt_factor(factor, p)
  scores_m <- sweep(epsilon, 2L, exp(-log_sd), `*`)
  if (!is.null(f$inverse)) scores_m <- scores_m %*% f$inverse
  # Local mean coordinates a satisfy dm=L diag(s) da. Their score is exactly
  # epsilon, so its MCSE can be estimated directly without discarding covariance
  # among physical mean-score components under a non-diagonal fixed factor.
  scores <- cbind(scores_m, epsilon^2 - 1, epsilon)
  columns <- 3L * p
  if (baseline == "leave_one_out") {
    # This is the unbiased sample covariance between score and reward. Delete-
    # one jackknife MCSE accounts for the shared leave-one-out baselines; a
    # naive sd(contributions)/sqrt(B) would ignore their dependence.
    sr <- colSums(scores * rewards); ss <- colSums(scores); rr <- sum(rewards)
    gradient <- (sr - ss * rr / B) / (B - 1L)
    minus <- (matrix(sr, B, columns, byrow = TRUE) - scores * rewards -
      (matrix(ss, B, columns, byrow = TRUE) - scores) * (rr - rewards) / (B - 1L)) / (B - 2L)
    pseudovalues <- matrix(B * gradient, B, columns, byrow = TRUE) - (B - 1L) * minus
    mcse <- apply(pseudovalues, 2L, stats::sd) / sqrt(B)
  } else {
    contributions <- scores * rewards
    gradient <- colMeans(contributions)
    mcse <- apply(contributions, 2L, stats::sd) / sqrt(B)
  }
  if (include_entropy) gradient[p + seq_len(p)] <- gradient[p + seq_len(p)] + 1
  q(all(is.finite(c(gradient, mcse))), "nonfinite outer-score gradient/MCSE")
  list(gradient_mean = gradient[seq_len(p)], gradient_log_sd = gradient[p + seq_len(p)],
    gradient = gradient[seq_len(2L * p)], mcse = mcse[seq_len(2L * p)], baseline = baseline,
    standardized_gradient_mean = gradient[2L * p + seq_len(p)],
    standardized_mcse_mean = mcse[2L * p + seq_len(p)],
    mcse_method = if (baseline == "leave_one_out") "delete_one_jackknife_independent_outer_draws" else "independent_sample_standard_error",
    entropy_added = include_entropy)
}

# A factory is evaluated before the current independent outer sample is drawn.
# Its function c(eta) is then frozen. Supplied moments are E_q[c] and
# E_q[score_q c] HOLDING THAT FUNCTION FIXED, not total derivatives of a
# phi-dependent factory/anchor. Conditional unbiasedness requires these moments
# to be correct; an independence declaration cannot certify their mathematics.
gcpopt_validate_control_variate <- function(x, p) {
  q <- gcpopt_require
  keys <- c("evaluate", "expected_value", "score_mean", "score_log_sd", "freeze_policy", "moment_scope", "source_identity")
  q(is.list(x) && setequal(names(x), keys) && length(x) == length(keys) && is.function(x$evaluate) &&
    gcpopt_number(x$expected_value) && length(x$expected_value) == 1L &&
    gcpopt_number(x$score_mean) && length(x$score_mean) == p &&
    gcpopt_number(x$score_log_sd) && length(x$score_log_sd) == p &&
    is.character(x$freeze_policy) && length(x$freeze_policy) == 1L &&
    x$freeze_policy %in% c("exact_control", "independent_frozen_control") &&
    identical(x$moment_scope, "partial_outer_score_holding_control_fixed") &&
    is.character(x$source_identity) && length(x$source_identity) == 1L &&
    grepl("^[a-f0-9]{64}$", x$source_identity),
    "frozen exact/independent control with analytic partial-score moments required")
  invisible(TRUE)
}
gcpopt_control_variate_seal <- function(x) gcpopt_hash(list(expected_value = x$expected_value,
  score_mean = x$score_mean, score_log_sd = x$score_log_sd,
  freeze_policy = x$freeze_policy, moment_scope = x$moment_scope, source_identity = x$source_identity,
  formals = deparse(formals(x$evaluate)), body = deparse(body(x$evaluate))))

gcpopt_optimize <- function(log_historical = NULL, log_evidence_estimate,
    initial_mean, initial_log_sd, factor = NULL, control = gcpopt_control(),
    input_contract, analytic_historical = NULL, control_variate = NULL, future_projection = NULL,
    step_strategy = "legacy_adam_0999") {
  q <- gcpopt_require; gcpopt_validate_control(control)
  strategies <- c(legacy_adam_0999 = .999, short_memory_adam_099 = .99,
    short_memory_adam_095 = .95)
  q(is.character(step_strategy) && length(step_strategy) == 1L && !is.na(step_strategy) &&
    step_strategy %in% names(strategies), "named, prespecified Adam step strategy required")
  beta2 <- unname(strategies[[step_strategy]])
  second_moment_weight <- unname(c(legacy_adam_0999 = .001,
    short_memory_adam_099 = .01, short_memory_adam_095 = .05)[[step_strategy]])
  p <- length(initial_mean)
  q(gcpopt_number(initial_mean) && gcpopt_number(initial_log_sd) && length(initial_log_sd) == p &&
    p <= 20000L && p * control$batch_size <= 2000000L &&
    all(initial_log_sd > control$log_sd_bounds[1L] & initial_log_sd < control$log_sd_bounds[2L]),
    "bounded, finite, fully free transformed parameter coordinates required")
  q(is.function(log_evidence_estimate) && xor(is.function(log_historical), is.function(analytic_historical)) &&
    (is.null(log_historical) || is.function(log_historical)) &&
    (is.null(analytic_historical) || is.function(analytic_historical)),
    "exactly one historical route; analytic historical ELBO must already include entropy")
  q(is.null(control_variate) || is.function(control_variate), "control variate must be a factory frozen before each batch")
  projector <- NULL; projection_identity <- NULL
  if (!is.null(future_projection)) {
    q(is.environment(future_projection) && is.function(analytic_historical) && is.null(factor) &&
      exists("gafsp_project_future", envir = environment(gcpopt_optimize), mode = "function", inherits = TRUE),
      "authenticated generated future projection requires analytic history and identity factor")
    projector <- get("gafsp_project_future", envir = environment(gcpopt_optimize), inherits = TRUE)
    projection_identity <- list(dimension = future_projection$dimension,
      coordinate_names = future_projection$coordinate_names, source_sha256 = future_projection$source_sha256)
    gcpopt_plain(projection_identity)
  }
  q(is.list(input_contract) && identical(input_contract$schema_version, "glofas_generated_outer_score_input_v1") &&
    identical(input_contract$scope, "generated_only") && length(input_contract$parameter_names) == p &&
    identical(input_contract$inner_kernel_phi_independent, TRUE) &&
    identical(input_contract$authentic_reads_authorized, FALSE) && identical(input_contract$production_authorized, FALSE) &&
    identical(input_contract$jacobian_policy, "caller_supplied_once_in_target_and_same_measure_log_q") &&
    identical(input_contract$target_inputs_sha256, gcpopt_hash(input_contract$target_inputs)),
    "sealed generated target/coordinate declaration required")
  q(identical(input_contract, gcpopt_input_contract(input_contract$parameter_names,
    input_contract$coordinate_measure, input_contract$target_inputs, input_contract$source_sha256)),
    "input contract fields, coordinate names or source identities changed")
  f <- gcpopt_factor(factor, p)
  callbacks <- list(historical = log_historical, evidence = log_evidence_estimate,
    analytic = analytic_historical, control_variate = control_variate, projection = projector)
  body_identity <- function() lapply(callbacks, function(fn) if (is.null(fn)) NULL else
    list(formals = deparse(formals(fn)), body = deparse(body(fn))))
  sealed <- function() gcpopt_hash(list(input_contract, control, initial_mean, initial_log_sd, factor,
    body_identity(), projection_identity, step_strategy, beta2, second_moment_weight))
  seal <- sealed()
  old_kind <- RNGkind(); old_seed <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (is.null(old_seed)) {
      if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old_seed, .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection"); set.seed(as.integer(control$seed))
  started <- proc.time()[["elapsed"]]; calls <- inner_calls <- control_calls <- projection_calls <- 0L
  m <- last_m <- as.numeric(initial_mean); ls <- last_ls <- as.numeric(initial_log_sd)
  adam_m <- adam_v <- rep(0, 2L * p); history <- list(); stable <- 0L
  prior_objective <- NA_real_; prior_parameters <- NULL; final_gradient <- NULL
  status <- "ITERATION_BUDGET_EXHAUSTED_NOT_QUALIFIED"; failure <- NULL; stopping <- FALSE
  callback <- function(fn, ..., cost_role = "model") {
    q(proc.time()[["elapsed"]] - started < control$max_wall_seconds, "optimizer callback/wall budget exhausted")
    if (cost_role == "model") {
      q(calls < control$max_evaluations, "optimizer callback/wall budget exhausted")
      calls <<- calls + 1L
    } else if (cost_role == "control") {
      q(control_calls < control$max_iterations * (control$batch_size + 1), "control-variate callback budget exhausted")
      control_calls <<- control_calls + 1L
    } else {
      q(identical(cost_role, "projection") && projection_calls < 2 * control$max_iterations,
        "future projection callback budget exhausted")
      projection_calls <<- projection_calls + 1L
    }
    before <- get(".Random.seed", .GlobalEnv)
    out <- fn(...)
    q(identical(before, get(".Random.seed", .GlobalEnv)), "callbacks must preserve the outer RNG stream")
    out
  }
  tryCatch({
    for (iteration in seq_len(control$max_iterations)) {
      q(identical(seal, sealed()), "declared inputs/control/source bodies changed")
      cv <- if (is.null(control_variate)) NULL else callback(control_variate, m, ls, factor, cost_role = "control")
      cv_seal <- NULL
      if (!is.null(cv)) {
        gcpopt_validate_control_variate(cv, p)
        cv_seal <- gcpopt_control_variate_seal(cv)
      }
      if (!is.null(projector)) {
        zeros <- rep(0, p)
        empty_gradient <- list(gradient_mean = zeros, gradient_log_sd = zeros,
          standardized_gradient_mean = zeros, mcse = rep(0, 2L * p),
          standardized_mcse_mean = zeros, gradient = rep(0, 2L * p),
          standardized_gradient = rep(0, 2L * p), standardized_mcse = rep(0, 2L * p))
        callback(projector, empty_gradient, future_projection, factor = factor,
          evidence = log_evidence_estimate, surrogate = cv, cost_role = "projection")
      }
      epsilon <- matrix(stats::rnorm(control$batch_size * p), control$batch_size, p)
      q(all(apply(epsilon, 2L, stats::var) > 0), "degenerate independent outer Monte Carlo draws")
      scaled <- sweep(epsilon, 2L, exp(ls), `*`)
      if (!is.null(f$matrix)) scaled <- scaled %*% t(f$matrix)
      eta <- sweep(scaled, 2L, m, `+`)
      seeds <- sample.int(.Machine$integer.max, control$batch_size, replace = FALSE)
      reward <- evidence <- control_values <- numeric(control$batch_size)
      historical <- if (!is.null(analytic_historical)) callback(analytic_historical, m, ls, factor) else NULL
      if (!is.null(historical)) q(is.list(historical) && gcpopt_number(historical$value) && length(historical$value) == 1L &&
        gcpopt_number(historical$gradient_mean) && length(historical$gradient_mean) == p &&
        gcpopt_number(historical$gradient_log_sd) && length(historical$gradient_log_sd) == p,
        "complete analytic historical ELBO/gradient including entropy required")
      for (j in seq_len(control$batch_size)) {
        q(inner_calls + control$inner_call_bound <= control$max_inner_calls, "inner evidence budget reserve exhausted")
        estimate <- callback(log_evidence_estimate, as.numeric(eta[j, ]), as.integer(seeds[j]))
        q(is.list(estimate) && isTRUE(estimate$complete) && isTRUE(estimate$diagnostic_thresholds_passed) &&
          gcpopt_number(estimate$log_estimate) && length(estimate$log_estimate) == 1L &&
          is.numeric(estimate$callback_calls) && length(estimate$callback_calls) == 1L &&
          is.finite(estimate$callback_calls) && estimate$callback_calls >= 0 &&
          estimate$callback_calls == floor(estimate$callback_calls) && estimate$callback_calls <= control$inner_call_bound,
          "inner estimate incomplete, degenerate, nonfinite or outside declared budget")
        inner_calls <- inner_calls + estimate$callback_calls
        evidence[j] <- estimate$log_estimate
        if (is.null(historical)) {
          h <- callback(log_historical, as.numeric(eta[j, ]))
          q(gcpopt_number(h) && length(h) == 1L, "finite same-measure historical log target required")
          reward[j] <- h + evidence[j]
        } else reward[j] <- evidence[j]
        if (!is.null(cv)) {
          cv_value <- callback(cv$evaluate, as.numeric(eta[j, ]), cost_role = "control")
          q(gcpopt_number(cv_value) && length(cv_value) == 1L, "finite scalar frozen control value required")
          control_values[j] <- cv_value
        }
      }
      raw_reward <- reward
      raw_gradient <- gcpopt_score_gradient(m, ls, factor, epsilon, raw_reward,
        include_entropy = is.null(historical))
      reward <- reward - control_values
      gradient <- if (is.null(cv)) raw_gradient else gcpopt_score_gradient(m, ls, factor, epsilon, reward,
        include_entropy = is.null(historical))
      if (!is.null(cv)) {
        q(identical(cv_seal, gcpopt_control_variate_seal(cv)), "frozen control changed within the current batch")
        gradient$gradient <- gradient$gradient + c(cv$score_mean, cv$score_log_sd)
        moment_m <- if (is.null(f$matrix)) cv$score_mean else as.numeric(crossprod(f$matrix, cv$score_mean))
        gradient$standardized_gradient_mean <- gradient$standardized_gradient_mean + exp(ls) * moment_m
      }
      gradient$gradient_mean <- gradient$gradient[seq_len(p)]
      gradient$gradient_log_sd <- gradient$gradient[p + seq_len(p)]
      gradient$standardized_gradient <- c(gradient$standardized_gradient_mean, gradient$gradient_log_sd)
      gradient$standardized_mcse <- c(gradient$standardized_mcse_mean, gradient$mcse[p + seq_len(p)])
      controlled_unprojected_mcse <- gradient$mcse
      controlled_unprojected_standardized_mcse <- gradient$standardized_mcse
      if (!is.null(projector)) gradient <- callback(projector, gradient, future_projection, factor = factor,
        evidence = log_evidence_estimate, surrogate = cv, cost_role = "projection")
      if (!is.null(historical)) gradient$gradient <- gradient$gradient +
        c(historical$gradient_mean, historical$gradient_log_sd)
      gradient$gradient_mean <- gradient$gradient[seq_len(p)]
      gradient$gradient_log_sd <- gradient$gradient[p + seq_len(p)]
      if (!is.null(historical)) {
        h_mean <- if (is.null(f$matrix)) historical$gradient_mean else
          as.numeric(crossprod(f$matrix, historical$gradient_mean))
        gradient$standardized_gradient_mean <- gradient$standardized_gradient_mean + exp(ls) * h_mean
      }
      gradient$standardized_gradient <- c(gradient$standardized_gradient_mean, gradient$gradient_log_sd)
      gradient$standardized_mcse <- c(gradient$standardized_mcse_mean, gradient$mcse[p + seq_len(p)])
      gradient$raw_no_control_mcse <- raw_gradient$mcse
      gradient$raw_no_control_standardized_mcse <- c(raw_gradient$standardized_mcse_mean, raw_gradient$mcse[p + seq_len(p)])
      gradient$controlled_unprojected_mcse <- controlled_unprojected_mcse
      gradient$controlled_unprojected_standardized_mcse <- controlled_unprojected_standardized_mcse
      entropy <- .5 * p * (1 + log(2 * pi)) + sum(ls) + f$log_abs_determinant
      objective <- mean(reward) + (if (is.null(cv)) 0 else cv$expected_value) +
        if (is.null(historical)) entropy else historical$value
      objective_mcse <- stats::sd(reward) / sqrt(control$batch_size)
      q(all(is.finite(c(gradient$gradient, gradient$mcse, gradient$standardized_gradient,
        gradient$standardized_mcse, objective, objective_mcse))), "nonfinite optimizer state")
      parameters <- c(m, ls)
      step <- if (is.null(prior_parameters)) Inf else max(abs(parameters - prior_parameters))
      standardized_step <- if (is.null(prior_parameters)) Inf else {
        delta_m <- m - prior_parameters[seq_len(p)]
        if (!is.null(f$inverse)) delta_m <- as.numeric(f$inverse %*% delta_m)
        max(abs(c(delta_m / exp(prior_parameters[p + seq_len(p)]), ls - prior_parameters[p + seq_len(p)])))
      }
      change <- if (is.na(prior_objective)) Inf else abs(objective - prior_objective)
      at_bound <- any(ls <= control$log_sd_bounds[1L] + 1e-10 | ls >= control$log_sd_bounds[2L] - 1e-10)
      eligible <- iteration >= control$minimum_iterations && !at_bound &&
        max(abs(gradient$standardized_gradient)) <= control$gradient_tolerance &&
        max(gradient$standardized_mcse) <= control$gradient_mcse_tolerance && standardized_step <= control$step_tolerance &&
        change <= control$objective_tolerance && objective_mcse <= control$objective_tolerance
      stable <- if (eligible) stable + 1L else 0L
      norm <- sqrt(sum(gradient$standardized_gradient^2))
      multiplier <- min(1, control$gradient_clip / max(norm, .Machine$double.eps))
      history[[iteration]] <- data.frame(iteration = iteration, objective = objective, objective_mcse = objective_mcse,
        max_abs_gradient = max(abs(gradient$gradient)), max_gradient_mcse = max(gradient$mcse),
        raw_no_control_max_gradient_mcse = max(raw_gradient$mcse),
        raw_no_control_max_standardized_mcse = max(c(raw_gradient$standardized_mcse_mean, raw_gradient$mcse[p + seq_len(p)])),
        controlled_unprojected_max_gradient_mcse = max(controlled_unprojected_mcse),
        controlled_unprojected_max_standardized_mcse = max(controlled_unprojected_standardized_mcse),
        max_abs_standardized_gradient = max(abs(gradient$standardized_gradient)),
        max_standardized_gradient_mcse = max(gradient$standardized_mcse),
        max_parameter_change = step, max_standardized_parameter_change = standardized_step,
        objective_change = change, stable_iterations = stable,
        gradient_clip_multiplier = multiplier, variance_bound_active = at_bound,
        evaluations = calls, control_variate_evaluations = control_calls, projection_evaluations = projection_calls,
        total_callbacks = calls + control_calls + projection_calls,
        inner_calls = inner_calls, elapsed_seconds = proc.time()[["elapsed"]] - started)
      last_m <- m; last_ls <- ls; final_gradient <- gradient
      if (stable >= control$stable_iterations) {
        stopping <- TRUE; status <- "OPTIMIZER_STOPPING_CRITERIA_MET_NOT_POSTERIOR_QUALIFICATION"; break
      }
      if (iteration == control$max_iterations) break
      update <- gradient$standardized_gradient * multiplier
      adam_m <- .9 * adam_m + .1 * update; adam_v <- beta2 * adam_v + second_moment_weight * update^2
      standardized_update <- control$learning_rate * (adam_m / (1 - .9^iteration)) /
        (sqrt(adam_v / (1 - beta2^iteration)) + 1e-8)
      mean_update <- exp(ls) * standardized_update[seq_len(p)]
      if (!is.null(f$matrix)) mean_update <- as.numeric(f$matrix %*% mean_update)
      next_parameters <- parameters + c(mean_update, standardized_update[p + seq_len(p)])
      q(all(is.finite(next_parameters)), "nonfinite Adam proposal")
      prior_parameters <- parameters; prior_objective <- objective
      m <- next_parameters[seq_len(p)]
      ls <- pmin(control$log_sd_bounds[2L], pmax(control$log_sd_bounds[1L], next_parameters[p + seq_len(p)]))
    }
  }, error = function(e) { failure <<- conditionMessage(e); status <<- "FAILED_OR_BUDGET_LIMITED_NOT_QUALIFIED" })
  q(identical(seal, sealed()), "declared input/source seal failed after optimization")
  trace <- if (length(history)) do.call(rbind, history) else data.frame()
  variance <- if (is.null(f$matrix)) exp(2 * last_ls) else as.numeric((f$matrix^2) %*% exp(2 * last_ls))
  list(schema_version = "glofas_generated_collapsed_parameter_optimizer_v1", status = status,
    mean = last_m, log_sd = last_ls, factor = factor, marginal_variance = variance,
    initial_mean = initial_mean, initial_log_sd = initial_log_sd,
    history = trace, last_gradient = final_gradient, completed_iterations = nrow(trace),
    stopping_criteria_met = stopping, failure = failure, evaluations = calls, inner_calls = inner_calls,
    control_variate_evaluations = control_calls, projection_evaluations = projection_calls,
    total_callbacks = calls + control_calls + projection_calls,
    control_variate_call_limit = control$max_iterations * (control$batch_size + 1),
    projection_call_limit = 2 * control$max_iterations,
    control_variate_used = !is.null(control_variate), future_projection_used = !is.null(future_projection),
    control_moment_scope = "Partial outer-score moments with each control frozen before current independent outer draws.",
    controlled_mcse_scope = "Sampling variability conditional on a frozen control and correct supplied moments; not a guarantee of moment correctness or posterior accuracy.",
    elapsed_seconds = proc.time()[["elapsed"]] - started, control = control, input_contract = input_contract,
    input_seal_sha256 = seal, callback_source_sha256 = gcpopt_hash(body_identity()),
    seal_scope = "Declared generated value inputs and callback bodies; no opaque closure environments are serialized or authenticated.",
    family = "fixed_affine_factor_diagonal_Gaussian_all_supplied_transformed_coordinates",
    step_strategy = step_strategy, adam_beta1 = .9, adam_beta2 = beta2,
    mean_update_coordinates = "local_variational_standard_deviation_units_L_diag_sd",
    stopping_gradient_coordinates = "standardized_means_and_log_standard_deviations_raw_metrics_retained",
    all_parameter_dimensions_optimized = TRUE, historical_parameters_frozen = FALSE,
    analytic_historical_includes_entropy = !is.null(analytic_historical),
    inner_phi_independent_given_parameters = TRUE, inner_proposal_parameters_optimized = FALSE,
    finite_particle_expected_log_bound = TRUE, realized_objective_is_a_bound = FALSE,
    posterior_accuracy_qualified = FALSE, reference_qualified = FALSE,
    production_launch_authorized = FALSE, publication_authorized = FALSE,
    original_reads = 0L, authentic_fits = 0L)
}
