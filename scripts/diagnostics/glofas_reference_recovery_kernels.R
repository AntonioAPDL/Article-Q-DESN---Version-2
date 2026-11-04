# Same-target, fixed-parameter conditional-path recovery kernels. This module
# performs no file I/O, fitting, source-scale updates, prior updates or feature
# changes. Source draws are admitted by the caller and used ONLY to freeze an
# MCMC proposal; they are not an original-posterior approximation or a prior.
# Source glofas_al_path_reference.R first to supply the authenticated target API.

grr_require_api <- function() {
  needed <- c("gapr_stop", "gapr_log_target", "gapr_named_seeds", "gapr_diagnose_draws",
              "gapr_posterior_dependency")
  if (!all(vapply(needed, function(n) exists(n, envir = environment(grr_require_api),
      mode = "function", inherits = TRUE), logical(1L))))
    stop("Source the fixed-parameter AL path target API first.", call. = FALSE)
}

grr_frozen_covariance <- function(S) {
  H <- nrow(S)
  C <- .95 * S + .05 * diag(diag(S), H, H)
  C <- (C + t(C)) / 2
  average_variance <- sum(diag(C)) / H
  if (!is.finite(average_variance) || average_variance <= 0)
    gapr_stop("Proposal calibration requires positive total pooled variance.")
  # Deterministic safeguard, not a statistical regularizer or model update:
  # when an eigenvalue is below 1e-10 * trace(C) / H, replace only those
  # eigenvalues by that floor, using the trace BEFORE any flooring.
  floor <- 1e-10 * average_variance
  eig <- eigen(C, symmetric = TRUE)
  floored <- eig$values < floor
  if (any(floored)) {
    C <- tcrossprod(sweep(eig$vectors, 2L, sqrt(pmax(eig$values, floor)), "*"))
    C <- (C + t(C)) / 2
  }
  root <- tryCatch(t(chol(C)), error = function(e) NULL)
  if (is.null(root)) gapr_stop("Deterministic proposal calibration is not positive definite.")
  list(covariance = C, root = root, floor = floor, floor_applied = any(floored),
       floored_eigenvalues = sum(floored), minimum_eigenvalue_before_floor = min(eig$values))
}

grr_calibrate_proposal <- function(draws, require_authentic_shape = TRUE) {
  grr_require_api()
  shape <- dim(draws)
  if (!is.numeric(draws) || length(shape) != 3L || shape[1L] < 2L ||
      shape[2L] != 4L || shape[3L] < 1L || any(!is.finite(draws)) ||
      !is.logical(require_authentic_shape) || length(require_authentic_shape) != 1L ||
      is.na(require_authentic_shape)) gapr_stop("Calibration needs a finite numeric iterations x 4 x H array.")
  if (require_authentic_shape && !identical(shape, c(20000L, 4L, 28L)))
    gapr_stop("Authentic recovery calibration requires the complete 20000 x 4 x 28 array.")
  H <- shape[3L]
  pooled <- matrix(draws, ncol = H)
  pooled_mean <- colMeans(pooled)
  S <- matrix(stats::cov(pooled), H, H)
  frozen <- grr_frozen_covariance(S)
  list(schema_version = "glofas_reference_recovery_calibration_v1", role = "MCMC_PROPOSAL_ONLY",
       pooled_mean = pooled_mean, pooled_covariance = S,
       proposal_covariance = frozen$covariance, root_covariance = frozen$root,
       input_dimensions = shape, pooled_observations = nrow(pooled),
       require_authentic_shape = require_authentic_shape,
       covariance_recipe = "0.95*S + 0.05*diag(diag(S)); S is all-chain pooled sample covariance",
       spd_floor_recipe = "If needed, clamp eigenvalues below 1e-10*trace(C_unfloored)/H to that fixed floor",
       spd_floor = frozen$floor, spd_floor_applied = frozen$floor_applied,
       floored_eigenvalues = frozen$floored_eigenvalues,
       minimum_eigenvalue_before_floor = frozen$minimum_eigenvalue_before_floor,
       fixed_model_updates = FALSE, theta_updates = 0L, prior_updates = 0L,
       source_scale_updates = 0L, feature_updates = 0L,
       interpretation = "Frozen MCMC proposal calibration only; not an original-posterior claim")
}

grr_validate_calibration <- function(calibration, H) {
  if (!is.list(calibration) ||
      !identical(calibration$schema_version, "glofas_reference_recovery_calibration_v1") ||
      !identical(calibration$role, "MCMC_PROPOSAL_ONLY") ||
      length(calibration$pooled_mean) != H || any(!is.finite(calibration$pooled_mean)) ||
      !identical(dim(calibration$pooled_covariance), c(H, H)) ||
      any(!is.finite(calibration$pooled_covariance)) ||
      !identical(dim(calibration$proposal_covariance), c(H, H)) ||
      any(!is.finite(calibration$proposal_covariance)) ||
      !identical(calibration$fixed_model_updates, FALSE))
    gapr_stop("Invalid frozen proposal-only calibration.")
  expected <- grr_frozen_covariance(calibration$pooled_covariance)$covariance
  if (!isTRUE(all.equal(calibration$proposal_covariance, expected, tolerance = 1e-12)))
    gapr_stop("Proposal calibration differs from its declared deterministic covariance recipe.")
  invisible(TRUE)
}

grr_student_t_geometry <- function(location, scale, df = 5) {
  H <- length(location)
  if (!is.numeric(location) || H < 1L || any(!is.finite(location)) ||
      !identical(dim(scale), c(H, H)) || any(!is.finite(scale)) ||
      max(abs(scale - t(scale))) > 1e-12 || length(df) != 1L || !is.finite(df) || df <= 0)
    gapr_stop("Student-t proposal needs finite location, symmetric SPD scale and positive df.")
  R <- tryCatch(chol(scale), error = function(e) NULL)
  if (is.null(R)) gapr_stop("Student-t proposal scale is not positive definite.")
  list(location = as.numeric(location), scale = scale, df = df, R = R, H = H,
       log_constant = lgamma((df + H) / 2) - lgamma(df / 2) -
         H / 2 * log(df * pi) - sum(log(diag(R))))
}

grr_log_student_t_geometry <- function(x, geometry) {
  if (length(x) != geometry$H || any(!is.finite(x)))
    gapr_stop("Student-t density path is not aligned with its proposal.")
  z <- backsolve(geometry$R, as.numeric(x) - geometry$location, transpose = TRUE)
  geometry$log_constant - (geometry$df + geometry$H) / 2 * log1p(sum(z^2) / geometry$df)
}

grr_log_student_t <- function(x, location, scale, df = 5) {
  grr_log_student_t_geometry(x, grr_student_t_geometry(location, scale, df))
}

grr_draw_student_t_geometry <- function(geometry) {
  geometry$location + as.numeric(t(geometry$R) %*% stats::rnorm(geometry$H)) /
    sqrt(stats::rchisq(1L, geometry$df) / geometry$df)
}

grr_log_mh_ratio <- function(log_pi_current, log_pi_candidate,
                             log_q_current = 0, log_q_candidate = 0) {
  if (any(lengths(list(log_pi_current, log_pi_candidate, log_q_current, log_q_candidate)) != 1L) ||
      !is.finite(log_pi_current) || is.na(log_pi_candidate) || log_pi_candidate == Inf ||
      !is.finite(log_q_current) || !is.finite(log_q_candidate))
    gapr_stop("Invalid log density in the MH ratio.")
  # q(current)-q(candidate) is used ONLY for the independence component.
  log_pi_candidate - log_pi_current + log_q_current - log_q_candidate
}

grr_validate_control <- function(control) {
  needed <- c("warmup", "samples", "max_evaluations", "max_wall_seconds", "adapt_warmup",
              "rhat_max", "min_ess", "max_quantile_mcse", "kernel")
  if (!is.list(control) || !all(needed %in% names(control)))
    gapr_stop("Recovery kernels and all iteration, wall/evaluation and qualification limits must be explicit.")
  for (name in c("warmup", "samples", "max_evaluations")) {
    value <- control[[name]]
    if (length(value) != 1L || !is.finite(value) || value != floor(value) ||
        value < if (name == "warmup") 0 else 1) gapr_stop("Invalid recovery iteration/evaluation budget.")
  }
  if (control$samples < 20L ||
      !all(vapply(c("max_wall_seconds", "rhat_max", "min_ess", "max_quantile_mcse"),
        function(n) length(control[[n]]) == 1L && is.finite(control[[n]]), logical(1L))) ||
      control$max_wall_seconds <= 0 || control$rhat_max <= 1 || control$min_ess <= 0 ||
      control$max_quantile_mcse <= 0 || !is.logical(control$adapt_warmup) ||
      length(control$adapt_warmup) != 1L || is.na(control$adapt_warmup) ||
      length(control$kernel) != 1L || !control$kernel %in%
        c("calibrated_random_walk", "mixture_random_walk_student_t"))
    gapr_stop("Invalid prospectively declared recovery kernel or limits.")
  ids <- if (is.null(control$chain_ids)) 1:4 else control$chain_ids
  if (!is.numeric(ids) || !length(ids) || anyNA(ids) || any(ids != floor(ids)) ||
      any(!ids %in% 1:4) || anyDuplicated(ids)) gapr_stop("Use each predetermined chain ID at most once.")
  if (!is.null(control$initial_factor) && (length(control$initial_factor) != 1L ||
      !is.finite(control$initial_factor) || control$initial_factor <= 0))
    gapr_stop("The declared initial random-walk scale factor must be positive.")
  as.integer(ids)
}

grr_sample_reference <- function(target, starts, calibration, control, progress_callback = NULL) {
  grr_require_api()
  chain_ids <- grr_validate_control(control)
  if (!inherits(target, "gapr_target")) gapr_stop("Recovery requires the unchanged AL conditional target API.")
  H <- target$horizon
  if (target$contract$mode == "authentic" &&
      (target$contract$p != .5 || H != 28L || target$n_members != 51L))
    gapr_stop("Authentic recovery is restricted to the H=28, 51-unit-member AL median target.")
  starts <- as.matrix(starts)
  if (!identical(dim(starts), c(H, 4L)) || any(!is.finite(starts)))
    gapr_stop("Four predetermined finite starting paths are required; chain selection is not allowed.")
  grr_validate_calibration(calibration, H)
  if (target$contract$mode == "authentic" &&
      (!isTRUE(calibration$require_authentic_shape) ||
       !identical(calibration$input_dimensions, c(20000L, 4L, 28L))))
    gapr_stop("Authentic recovery requires the admitted complete four-chain calibration.")
  if (!is.null(progress_callback) && !is.function(progress_callback))
    gapr_stop("The optional bounded metadata progress callback must be a function.")
  if (control$max_evaluations > target$contract$max_callback_calls - target$counter$value)
    gapr_stop("Recovery evaluation cap exceeds the remaining admitted target callback allocation.")
  old_kind <- RNGkind()
  old_seed <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) get(".Random.seed", .GlobalEnv) else NULL
  restore_rng <- function(kind, seed) {
    do.call(RNGkind, as.list(kind))
    if (is.null(seed)) {
      if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", seed, .GlobalEnv)
  }
  on.exit(restore_rng(old_kind, old_seed), add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  seeds <- gapr_named_seeds(target$contract$p)
  dependency <- gapr_posterior_dependency()
  total_iterations <- as.integer(control$warmup + control$samples)
  draws <- array(NA_real_, c(as.integer(control$samples), 4L, H))
  chain_states <- stats::setNames(vector("list", 4L), paste0("chain", 1:4))
  count_matrix <- function() matrix(0, 2L, 4L,
    dimnames = list(c("random_walk", "independence_student_t"), paste0("chain", 1:4)))
  attempted <- accepted <- moved <- squared_jump <- count_matrix()
  retained_attempted <- retained_accepted <- retained_moved <- retained_squared_jump <- count_matrix()
  factors <- matrix(NA_real_, total_iterations + 1L, 4L)
  initial_factor <- if (is.null(control$initial_factor)) 2.38 / sqrt(H) else control$initial_factor
  root <- t(chol(calibration$proposal_covariance))
  t_geometry <- grr_student_t_geometry(calibration$pooled_mean, (5 - 2) / 5 * calibration$proposal_covariance, 5)
  start_time <- proc.time()[["elapsed"]]
  start_calls <- target$counter$value
  started_chains <- completed_chains <- 0L
  failure <- error_message <- NULL
  check_budget <- function(needs_evaluation = FALSE) {
    if (proc.time()[["elapsed"]] - start_time > control$max_wall_seconds ||
        (needs_evaluation && target$counter$value - start_calls >= control$max_evaluations))
      gapr_stop("Declared recovery sampler budget exhausted.", "gapr_budget_exhausted")
  }
  evaluate <- function(y) {
    check_budget(TRUE)
    value <- gapr_log_target(target, y)
    check_budget()
    value
  }
  progress_calls <- 0L
  progress <- function(final = FALSE) {
    if (is.null(progress_callback) || (completed_iterations %% 250L != 0L && !final)) return(invisible(NULL))
    if (completed_iterations == last_progress_iteration) return(invisible(NULL))
    check_budget()
    metadata <- list(schema_version = "recovery_progress_metadata_v1", chain_id = chain,
      completed_iterations = completed_iterations,
      retained_iterations = max(0L, completed_iterations - control$warmup),
      callback_evaluations = target$counter$value - start_calls,
      elapsed_seconds = proc.time()[["elapsed"]] - start_time,
      kernel_attempted = attempted[, chain], kernel_accepted = accepted[, chain],
      fully_completed = completed_iterations == total_iterations)
    callback_kind <- RNGkind(); callback_seed <- get(".Random.seed", .GlobalEnv)
    tryCatch(progress_callback(metadata), finally = restore_rng(callback_kind, callback_seed))
    progress_calls <<- progress_calls + 1L
    last_progress_iteration <<- completed_iterations
    check_budget()
    invisible(NULL)
  }
  capture_state <- function() list(schema_version = "same_target_recovery_chain_state_v1",
    chain_id = chain, seed = seeds[[chain]], RNG_kind = RNGkind(),
    initial_RNG_state = initial_rng_state, final_RNG_state = get(".Random.seed", .GlobalEnv),
    initial_path = as.numeric(starts[, chain]), final_path = as.numeric(y),
    current_log_density = value, completed_iterations = completed_iterations,
    retained_iterations = max(0L, completed_iterations - control$warmup),
    fully_completed = completed_iterations == total_iterations,
    initial_proposal_factor = initial_factor, frozen_proposal_factor = factor,
    proposal_factor_at_sampling_start = factor_at_sampling_start,
    adaptation_updates = adaptation_updates, proposal_kind = control$kernel,
    calibration_role = calibration$role, control = control, exact_resume_qualified = FALSE,
    interpretation = "Preserved diagnostic transition state; no qualified resume or full-posterior inference")
  tryCatch({
    for (chain in chain_ids) {
      started_chains <- started_chains + 1L
      set.seed(seeds[[chain]])
      initial_rng_state <- get(".Random.seed", .GlobalEnv)
      y <- starts[, chain]; value <- NA_real_; completed_iterations <- 0L
      last_progress_iteration <- -1L
      factor <- initial_factor; factor_at_sampling_start <- if (control$warmup == 0L) factor else NA_real_
      adaptation_updates <- 0L
      factors[1L, chain] <- factor
      value <- evaluate(y)
      if (!is.finite(value)) gapr_stop("A predetermined starting path has nonfinite target density.")
      for (iteration in seq_len(total_iterations)) {
        check_budget(TRUE)
        # Fixed, state-independent mixing weights. Each component is separately
        # reversible; do not use a mixture-density Hastings ratio for the RW.
        component <- if (control$kernel == "calibrated_random_walk") 1L else
          if (stats::runif(1L) < .5) 1L else 2L
        candidate <- if (component == 1L) y + factor * as.numeric(root %*% stats::rnorm(H)) else
          grr_draw_student_t_geometry(t_geometry)
        proposed_value <- evaluate(candidate)
        log_ratio <- if (component == 1L) grr_log_mh_ratio(value, proposed_value) else
          grr_log_mh_ratio(value, proposed_value,
            grr_log_student_t_geometry(y, t_geometry), grr_log_student_t_geometry(candidate, t_geometry))
        accept <- log(stats::runif(1L)) < min(0, log_ratio)
        change <- if (accept) sum((candidate - y)^2) else 0
        did_move <- accept && any(candidate != y)
        attempted[component, chain] <- attempted[component, chain] + 1L
        accepted[component, chain] <- accepted[component, chain] + as.integer(accept)
        moved[component, chain] <- moved[component, chain] + as.integer(did_move)
        squared_jump[component, chain] <- squared_jump[component, chain] + change
        if (accept) { y <- candidate; value <- proposed_value }
        if (iteration <= control$warmup && isTRUE(control$adapt_warmup) && component == 1L) {
          eta <- min(.05, (attempted[1L, chain] + 10)^(-.6))
          factor <- min(20 * initial_factor, max(.05 * initial_factor,
            factor * exp(eta * (as.integer(accept) - .234))))
          adaptation_updates <- adaptation_updates + 1L
        }
        if (iteration == control$warmup) factor_at_sampling_start <- factor
        factors[iteration + 1L, chain] <- factor
        if (iteration > control$warmup) {
          draws[iteration - control$warmup, chain, ] <- y
          retained_attempted[component, chain] <- retained_attempted[component, chain] + 1L
          retained_accepted[component, chain] <- retained_accepted[component, chain] + as.integer(accept)
          retained_moved[component, chain] <- retained_moved[component, chain] + as.integer(did_move)
          retained_squared_jump[component, chain] <- retained_squared_jump[component, chain] + change
        }
        completed_iterations <- iteration
        progress()
      }
      completed_chains <- completed_chains + 1L
      chain_states[[chain]] <- capture_state()
      progress(final = TRUE)
    }
  }, gapr_budget_exhausted = function(e) failure <<- "INCONCLUSIVE_BUDGET_LIMITED",
     error = function(e) { failure <<- "FAIL_REFERENCE_EXECUTION"; error_message <<- conditionMessage(e) })
  if (!is.null(failure) && started_chains > completed_chains) chain_states[[chain]] <- capture_state()
  complete <- is.null(failure) && identical(sort(chain_ids), 1:4)
  out <- if (complete) tryCatch(gapr_diagnose_draws(draws, target, control), error = function(e)
    list(status = "INCONCLUSIVE_DIAGNOSTIC_CALCULATION_ERROR", qualified = FALSE,
         error = conditionMessage(e), dependency = dependency)) else
    list(status = if (is.null(failure)) "CHAINS_PENDING_COMBINATION" else failure,
         qualified = FALSE, dependency = dependency)
  out$error <- if (!is.null(error_message)) error_message else out$error
  out$draws <- draws; out$chain_states <- chain_states; out$seeds <- seeds
  out$chain_ids <- chain_ids; out$control <- control; out$calibration <- calibration
  out$proposal_kind <- control$kernel
  out$kernel_attempted <- attempted; out$kernel_accepted <- accepted; out$kernel_moved <- moved
  out$kernel_squared_jump_distance <- squared_jump
  out$kernel_acceptance <- accepted / pmax(attempted, 1L)
  out$retained_kernel_counts <- list(attempted = retained_attempted, accepted = retained_accepted,
    moved = retained_moved, squared_jump_distance = retained_squared_jump)
  out$proposal_factors <- factors
  out$adaptation <- "random_walk_scalar_factor_warmup_only_then_frozen; covariance_location_t_scale_and_weights_always_frozen"
  out$mixture_weights <- if (control$kernel == "calibrated_random_walk") c(random_walk = 1, independence_student_t = 0) else
    c(random_walk = .5, independence_student_t = .5)
  out$independence_df <- 5
  out$independence_scale <- t_geometry$scale
  out$callback_evaluations <- target$counter$value - start_calls
  out$elapsed_seconds <- proc.time()[["elapsed"]] - start_time
  out$progress_callback_calls <- progress_calls
  out$condition <- target$contract
  out$scientific_runs <- 0L; out$authentic_reads <- 0L; out$full_parameter_refits <- 0L
  out$conditional_reference_chains_requested <- length(chain_ids)
  out$conditional_reference_chains_attempted <- started_chains
  out$conditional_reference_chains_completed <- completed_chains
  out$scope <- "Same fixed-parameter AL conditional path only; no original-posterior or exact-draw claim"
  out
}

grr_combine_chains <- function(parts, target, control) {
  grr_require_api()
  grr_validate_control(control)
  if (!is.list(parts) || !length(parts) || !inherits(target, "gapr_target"))
    gapr_stop("Recovery combination needs chain receipts and the unchanged target.")
  selected <- unlist(lapply(parts, function(x) x$chain_ids), use.names = FALSE)
  if (length(selected) != 4L || anyDuplicated(selected) || !identical(sort(as.integer(selected)), 1:4))
    gapr_stop("Recovery combination requires all four predetermined chains exactly once.")
  H <- target$horizon
  calibration <- parts[[1L]]$calibration
  grr_validate_calibration(calibration, H)
  fields <- setdiff(names(target$contract), c("max_callback_calls", "max_jacobian_calls"))
  control_fields <- setdiff(names(control), "chain_ids")
  out <- parts[[1L]]
  out$draws[] <- NA_real_; out$proposal_factors[] <- NA_real_
  out$chain_states <- stats::setNames(vector("list", 4L), paste0("chain", 1:4))
  metrics <- c("kernel_attempted", "kernel_accepted", "kernel_moved", "kernel_squared_jump_distance")
  for (n in metrics) out[[n]][] <- 0
  for (n in names(out$retained_kernel_counts)) out$retained_kernel_counts[[n]][] <- 0
  complete <- TRUE
  for (part in parts) {
    if (!identical(part$seeds, gapr_named_seeds(target$contract$p)) ||
        !identical(part$calibration, calibration) || !identical(part$proposal_kind, control$kernel) ||
        !identical(sort(setdiff(names(part$control), "chain_ids")), sort(control_fields)) ||
        !all(vapply(control_fields, function(n) identical(part$control[[n]], control[[n]]), logical(1L))) ||
        !all(vapply(fields, function(n) identical(part$condition[[n]], target$contract[[n]]), logical(1L))) ||
        !identical(dim(part$draws), c(as.integer(control$samples), 4L, H)))
      gapr_stop("Recovery chain seeds, frozen calibration, controls or conditional targets differ.")
    for (chain in part$chain_ids) {
      out$draws[, chain, ] <- part$draws[, chain, ]
      out$proposal_factors[, chain] <- part$proposal_factors[, chain]
      out$chain_states[chain] <- part$chain_states[chain]
      for (n in metrics) out[[n]][, chain] <- part[[n]][, chain]
      for (n in names(out$retained_kernel_counts))
        out$retained_kernel_counts[[n]][, chain] <- part$retained_kernel_counts[[n]][, chain]
      complete <- complete && !is.null(part$chain_states[[chain]]) &&
        isTRUE(part$chain_states[[chain]]$fully_completed)
    }
    complete <- complete && part$status %in% c("CHAINS_PENDING_COMBINATION", "QUALIFIED_CONDITIONAL_REFERENCE",
      "INCONCLUSIVE_MCMC_DIAGNOSTICS", "BLOCKED_POSTERIOR_PACKAGE", "BLOCKED_DIAGNOSTIC_VERSION")
  }
  diagnosis <- if (complete && all(is.finite(out$draws)))
    tryCatch(gapr_diagnose_draws(out$draws, target, control), error = function(e)
      list(status = "INCONCLUSIVE_DIAGNOSTIC_CALCULATION_ERROR", qualified = FALSE, error = conditionMessage(e))) else
    list(status = "INCONCLUSIVE_CHAIN_EXECUTION", qualified = FALSE)
  for (n in c("diagnostics", "quantiles", "error")) out[[n]] <- NULL
  for (n in names(diagnosis)) out[[n]] <- diagnosis[[n]]
  out$chain_ids <- 1:4; out$control <- control; out$condition <- target$contract
  out$kernel_acceptance <- out$kernel_accepted / pmax(out$kernel_attempted, 1L)
  for (n in c("callback_evaluations", "elapsed_seconds", "progress_callback_calls",
              "conditional_reference_chains_attempted", "conditional_reference_chains_completed"))
    out[[n]] <- sum(vapply(parts, function(x) as.numeric(x[[n]]), numeric(1L)))
  out$conditional_reference_chains_requested <- 4L
  out$scope <- "All four predetermined same-target conditional chains retained; no original-posterior claim"
  out
}
