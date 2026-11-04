# Fixed-parameter AL path diagnostics. These functions perform no file reads,
# application fit, source modification or publication. A caller must separately
# authenticate the location callbacks and admit every authentic evaluation.

gapr_stop <- function(message, class = "gapr_contract_error") {
  stop(structure(list(message = message, call = NULL),
                 class = c(class, "error", "condition")))
}

gapr_dates <- function(x) {
  if (!inherits(x, "Date") && !is.character(x)) gapr_stop("Dates must be Date or ISO strings.")
  out <- tryCatch(as.Date(x), error = function(e) rep(as.Date(NA), length(x)))
  if (anyNA(out)) gapr_stop("Invalid diagnostic dates.")
  out
}

gapr_new_target <- function(location_callback, contract) {
  needed <- c("mode", "likelihood_family", "p", "sigma_y", "sigma_g", "issued", "member_weights",
              "forecast_dates", "origin_date", "known_baseline", "parameter_id",
              "feature_id", "coefficient_covariance", "truth_access",
              "max_callback_calls", "max_jacobian_calls", "ensemble_location_convention")
  if (!is.function(location_callback) || !is.list(contract) ||
      !all(needed %in% names(contract))) gapr_stop("Incomplete conditional-path contract.")
  if (!identical(contract$likelihood_family, "al"))
    gapr_stop("This marginal conditional-path reference supports AL only, not exAL or Normal.")
  if (!contract$mode %in% c("generated", "authentic") ||
      length(contract$p) != 1L || !is.finite(contract$p) ||
      contract$p <= 0 || contract$p >= 1) gapr_stop("Invalid scope or AL probability.")
  for (name in c("sigma_y", "sigma_g")) {
    if (length(contract[[name]]) != 1L || !is.finite(contract[[name]]) || contract[[name]] <= 0) {
      gapr_stop("Source scales must be fixed positive AL scales, not variances.")
    }
  }
  issued <- as.matrix(contract$issued)
  weights <- as.matrix(contract$member_weights)
  H <- nrow(issued); M <- ncol(issued)
  if (!H || !M || any(!is.finite(issued)) || !identical(dim(issued), dim(weights)) ||
      any(!is.finite(weights)) || any(weights != 1)) gapr_stop("All included members need ordinary unit factors.")
  dates <- gapr_dates(contract$forecast_dates)
  origin <- gapr_dates(contract$origin_date)
  if (length(origin) != 1L || length(dates) != H ||
      !identical(as.numeric(dates - origin), as.numeric(seq_len(H)))) {
    gapr_stop("Forecast dates must be consecutive and strictly after origin.")
  }
  if (contract$mode == "authentic" &&
      (H != 28L || M != 51L || !contract$p %in% c(.05, .5))) {
    gapr_stop("Authentic admission is restricted to H=28, 51 members and p=.05/.50.")
  }
  if (length(contract$known_baseline) != H || any(!is.finite(contract$known_baseline)) ||
      !identical(contract$ensemble_location_convention,
        "total_reference_plus_discrepancy_plus_known_baseline") ||
      !identical(contract$truth_access, "forbidden")) {
    gapr_stop("The response/location convention or scoring-truth boundary is unclear.")
  }
  cov <- as.matrix(contract$coefficient_covariance)
  if (!length(cov) || nrow(cov) != ncol(cov) || any(!is.finite(cov)) || any(cov != 0)) {
    gapr_stop("This diagnostic conditions on coefficients; covariance must be zero.")
  }
  for (name in c("parameter_id", "feature_id")) {
    if (length(contract[[name]]) != 1L || is.na(contract[[name]]) || !nzchar(contract[[name]])) {
      gapr_stop("Missing fixed-parameter/feature identity.")
    }
  }
  for (name in c("max_callback_calls", "max_jacobian_calls")) {
    value <- contract[[name]]
    if (length(value) != 1L || !is.finite(value) || value < 1 || value != floor(value)) {
      gapr_stop("Callback budgets must be explicitly positive integers.")
    }
  }
  contract$issued <- issued; contract$member_weights <- weights
  contract$forecast_dates <- dates; contract$origin_date <- origin
  contract$coefficient_covariance <- cov
  counter <- new.env(parent = emptyenv())
  counter$value <- 0L; counter$jacobian <- 0L
  structure(list(contract = contract, callback = location_callback, counter = counter,
    horizon = H, n_members = M,
    estimand = "nonlinear_future_path_conditional_on_fixed_parameters_not_full_parameter_posterior"),
    class = "gapr_target")
}

gapr_locations <- function(target, y, jacobian_callback = NULL) {
  if (!inherits(target, "gapr_target") || length(y) != target$horizon || any(!is.finite(y))) {
    gapr_stop("Path and conditional target are not aligned.")
  }
  kind <- if (is.null(jacobian_callback)) "value" else "jacobian"
  limit <- target$contract[[if (kind == "value") "max_callback_calls" else "max_jacobian_calls"]]
  if (target$counter[[kind]] >= limit) gapr_stop("Callback budget exhausted.", "gapr_budget_exhausted")
  target$counter[[kind]] <- target$counter[[kind]] + 1L
  out <- if (kind == "value") target$callback(as.numeric(y)) else jacobian_callback(as.numeric(y))
  for (name in c("reference_location", "ensemble_location")) {
    if (length(out[[name]]) != target$horizon || any(!is.finite(out[[name]]))) {
      gapr_stop("Callback must return finite reference and TOTAL ensemble locations.")
    }
    out[[name]] <- as.numeric(out[[name]])
  }
  if (kind == "jacobian") {
    H <- target$horizon
    for (name in c("reference_jacobian", "ensemble_jacobian")) {
      J <- as.matrix(out[[name]])
      if (!identical(dim(J), c(H, H)) || any(!is.finite(J)) ||
          any(abs(J[row(J) <= col(J)]) > 1e-12)) {
        gapr_stop("Location Jacobians must be H by H and strictly causal.")
      }
      out[[name]] <- J
    }
  }
  out
}

gapr_log_al <- function(response, location, p, sigma) {
  residual <- response - location
  log(p) + log1p(-p) - log(sigma) - residual * (p - (residual < 0)) / sigma
}

gapr_log_target <- function(target, y, components = FALSE) {
  locations <- gapr_locations(target, y)
  c <- target$contract
  log_y <- gapr_log_al(as.numeric(y), locations$reference_location, c$p, c$sigma_y)
  location_g <- matrix(locations$ensemble_location, target$horizon, target$n_members)
  log_g <- gapr_log_al(c$issued, location_g, c$p, c$sigma_g)
  total <- sum(log_y) + sum(log_g)
  if (is.na(total) || total == Inf) gapr_stop("Invalid conditional log density.")
  if (isTRUE(components)) list(value = total, future_y = log_y, members = log_g,
                               locations = locations) else total
}

gapr_one_dimensional_reference <- function(log_density, split_points = 0,
                                            probabilities = c(.05, .5, .95)) {
  points <- sort(unique(as.numeric(split_points)))
  if (!length(points) || any(!is.finite(points))) gapr_stop("Missing finite integration splits.")
  anchor <- max(vapply(points, log_density, numeric(1L)))
  if (!is.finite(anchor)) gapr_stop("Nonfinite integration anchor.")
  integrate_to <- function(upper = Inf, tight = TRUE) {
    boundaries <- c(-Inf, points, Inf); value <- error <- 0
    if (upper == -Inf) return(c(value = 0, error = 0))
    for (i in seq_len(length(boundaries) - 1L)) {
      left <- boundaries[i]; right <- min(upper, boundaries[i + 1L])
      if (right <= left) next
      v <- stats::integrate(function(x) exp(vapply(x, log_density, numeric(1L)) - anchor),
        left, right, rel.tol = if (tight) 1e-11 else 1e-9,
        abs.tol = if (tight) 1e-13 else 1e-11, subdivisions = 1000L)
      value <- value + v$value; error <- error + v$abs.error
    }
    c(value = value, error = error)
  }
  fine <- integrate_to(); coarse <- integrate_to(tight = FALSE)
  if (!is.finite(fine[["value"]]) || fine[["value"]] <= 0) gapr_stop("Invalid reference normalization.")
  cdf <- function(x, tight = TRUE) vapply(x, function(y) {
    integrate_to(y, tight)[["value"]] / if (tight) fine[["value"]] else coarse[["value"]]
  }, numeric(1L))
  interval <- range(c(points, -20, 20))
  q <- vapply(probabilities, function(p) stats::uniroot(function(x) cdf(x) - p,
      interval, tol = 1e-10)$root, numeric(1L))
  qc <- vapply(probabilities, function(p) stats::uniroot(function(x) cdf(x, FALSE) - p,
      interval, tol = 1e-10)$root, numeric(1L))
  list(cdf = cdf, probabilities = probabilities, quantiles = q,
       estimated_normalization_error = fine[["error"]] / fine[["value"]],
       normalization_tightening = abs(fine[["value"]] - coarse[["value"]]) / fine[["value"]],
       quantile_tightening = max(abs(q - qc)),
       interpretation = "deterministic_numerical_reference_with_explicit_integration_errors")
}

gapr_posterior_dependency <- function() {
  available <- requireNamespace("posterior", quietly = TRUE)
  version <- if (available) as.character(utils::packageVersion("posterior")) else NA_character_
  list(available = available && identical(version, "1.6.1"), version = version,
       status = if (!available) "BLOCKED_POSTERIOR_PACKAGE" else if (version != "1.6.1")
         "BLOCKED_DIAGNOSTIC_VERSION" else "PASS")
}

gapr_named_seeds <- function(p) {
  if (p == .5) stats::setNames(2026110301:2026110304, paste0("chain", 1:4)) else
    stats::setNames(2026110311:2026110314, paste0("chain", 1:4))
}

gapr_diagnose_draws <- function(draws, target, control) {
  dependency <- gapr_posterior_dependency()
  if (!dependency$available) return(list(status = dependency$status, qualified = FALSE,
                                        dependency = dependency))
  if (length(dim(draws)) != 3L || dim(draws)[2L] != 4L ||
      dim(draws)[3L] != target$horizon || any(!is.finite(draws))) {
    return(list(status = "INCONCLUSIVE_INCOMPLETE_DRAWS", qualified = FALSE,
                dependency = dependency))
  }
  summaries <- diagnostics <- list()
  probs <- sort(unique(c(target$contract$p, .5)))
  for (h in seq_len(target$horizon)) {
    x <- matrix(draws[, , h], nrow = dim(draws)[1L], ncol = 4L)
    rh <- posterior::rhat(x)
    bulk <- posterior::ess_bulk(x); tail <- posterior::ess_tail(x)
    eq <- as.numeric(posterior::ess_quantile(x, probs = probs))
    mc <- as.numeric(posterior::mcse_quantile(x, probs = probs))
    summaries[[h]] <- data.frame(horizon = h, probability = probs,
      quantile = as.numeric(stats::quantile(x, probs, names = FALSE, type = 7)),
      ess_quantile = eq, mcse_quantile = mc)
    relevant <- probs == target$contract$p
    passed <- all(is.finite(c(rh, bulk, tail, eq[relevant], mc[relevant]))) &&
      rh <= control$rhat_max && bulk >= control$min_ess && tail >= control$min_ess &&
      all(eq[relevant] >= control$min_ess) && all(mc[relevant] <= control$max_quantile_mcse)
    diagnostics[[h]] <- data.frame(horizon = h, rank_folded_split_rhat = rh,
      ess_bulk = bulk, ess_tail = tail, target_quantile_pass = passed)
  }
  diagnostics <- do.call(rbind, diagnostics)
  qualified <- all(diagnostics$target_quantile_pass)
  list(status = if (qualified) "QUALIFIED_CONDITIONAL_REFERENCE" else "INCONCLUSIVE_MCMC_DIAGNOSTICS",
       qualified = qualified, diagnostics = diagnostics,
       quantiles = do.call(rbind, summaries), dependency = dependency,
       interpretation = "finite_MCMC_reference_for_exact_conditional_density_not_exact_draws_or_full_posterior")
}

gapr_sample_reference <- function(target, starts, proposal_scale = NULL, control,
                                   proposal_covariance = NULL) {
  needed <- c("warmup", "samples", "max_evaluations", "max_wall_seconds", "adapt_warmup",
              "rhat_max", "min_ess", "max_quantile_mcse")
  if (!all(needed %in% names(control))) gapr_stop("Sampler limits/criteria must be explicit.")
  for (name in c("warmup", "samples", "max_evaluations")) {
    if (length(control[[name]]) != 1L || !is.finite(control[[name]]) ||
        control[[name]] != floor(control[[name]]) || control[[name]] < if (name == "warmup") 0 else 1) {
      gapr_stop("Invalid fixed sampler iteration budget.")
    }
  }
  if (control$samples < 20L || any(!is.finite(c(control$max_wall_seconds, control$rhat_max,
      control$min_ess, control$max_quantile_mcse))) || control$max_wall_seconds <= 0 ||
      control$rhat_max <= 1 || control$min_ess <= 0 || control$max_quantile_mcse <= 0) {
    gapr_stop("Invalid sampler qualification thresholds.")
  }
  if (!is.logical(control$adapt_warmup) || length(control$adapt_warmup) != 1L ||
      is.na(control$adapt_warmup)) gapr_stop("Warmup adaptation must be explicitly logical.")
  H <- target$horizon; starts <- as.matrix(starts)
  if (!identical(dim(starts), c(H, 4L)) || any(!is.finite(starts)))
    gapr_stop("Four explicit finite starting paths are required.")
  proposal_kind <- if (is.null(control$proposal_kind)) "componentwise" else control$proposal_kind
  chain_ids <- if (is.null(control$chain_ids)) 1:4 else as.integer(control$chain_ids)
  if (!proposal_kind %in% c("componentwise", "blocked_preconditioned") ||
      !length(chain_ids) || anyNA(chain_ids) || any(!chain_ids %in% 1:4) || anyDuplicated(chain_ids))
    gapr_stop("Invalid predetermined proposal or chain subset.")
  if (proposal_kind == "componentwise") {
    if (length(proposal_scale) != H || any(!is.finite(proposal_scale)) || any(proposal_scale <= 0))
      gapr_stop("Positive component proposal scales are required.")
    root_covariance <- NULL
  } else {
    proposal_covariance <- as.matrix(proposal_covariance)
    if (!identical(dim(proposal_covariance), c(H, H)) || any(!is.finite(proposal_covariance)) ||
        max(abs(proposal_covariance - t(proposal_covariance))) > 1e-12)
      gapr_stop("An explicitly symmetric blocked proposal covariance is required.")
    root_covariance <- tryCatch(t(chol(proposal_covariance)), error = function(e) NULL)
    if (is.null(root_covariance)) gapr_stop("Blocked proposal covariance must be positive definite.")
    proposal_scale <- sqrt(diag(proposal_covariance))
  }
  seeds <- gapr_named_seeds(target$contract$p)
  dependency <- gapr_posterior_dependency()
  if (!dependency$available) return(list(status = dependency$status, qualified = FALSE,
    dependency = dependency, seeds = seeds, scientific_runs = 0L, authentic_reads = 0L,
    full_parameter_refits = 0L, conditional_reference_chains_requested = length(chain_ids),
    conditional_reference_chains_attempted = 0L, conditional_reference_chains_completed = 0L))
  remaining_calls <- target$contract$max_callback_calls - target$counter$value
  if (control$max_evaluations > remaining_calls)
    gapr_stop("Declared sampler evaluation cap exceeds its remaining callback allocation.")
  old_kind <- RNGkind(); old_seed <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE))
    get(".Random.seed", .GlobalEnv) else NULL
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (is.null(old_seed)) {
      if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old_seed, .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  draws <- array(NA_real_, c(control$samples, 4L, H))
  accepted <- attempted <- matrix(0L, H, 4L)
  final_steps <- matrix(NA_real_, H, 4L)
  final_factors <- rep(NA_real_, 4L)
  start_time <- proc.time()[["elapsed"]]; start_calls <- target$counter$value
  started_chains <- completed_chains <- 0L
  evaluate <- function(y) {
    if (proc.time()[["elapsed"]] - start_time > control$max_wall_seconds ||
        target$counter$value - start_calls >= control$max_evaluations) {
      gapr_stop("Declared sampler budget exhausted.", "gapr_budget_exhausted")
    }
    gapr_log_target(target, y)
  }
  failure <- NULL
  tryCatch({
    for (chain in chain_ids) {
      started_chains <- started_chains + 1L
      set.seed(seeds[[chain]])
      y <- starts[, chain]; value <- evaluate(y)
      if (!is.finite(value)) gapr_stop("An explicit start has nonfinite density.")
      initial_factor <- 2.38 / sqrt(H); factor <- initial_factor
      step <- as.numeric(proposal_scale)
      if (proposal_kind == "blocked_preconditioned") step <- step * factor
      for (iteration in seq_len(control$warmup + control$samples)) {
        sweep_accept <- numeric(H)
        proposal_indices <- if (proposal_kind == "componentwise") seq_len(H) else 1L
        for (h in proposal_indices) {
          candidate <- if (proposal_kind == "componentwise") {
            z <- y; z[h] <- z[h] + stats::rnorm(1L, sd = step[h]); z
          } else y + factor * as.numeric(root_covariance %*% stats::rnorm(H))
          proposed_value <- evaluate(candidate)
          affected <- if (proposal_kind == "componentwise") h else seq_len(H)
          attempted[affected, chain] <- attempted[affected, chain] + 1L
          if (log(stats::runif(1L)) < proposed_value - value) {
            y <- candidate; value <- proposed_value
            accepted[affected, chain] <- accepted[affected, chain] + 1L
            sweep_accept[affected] <- 1
          }
        }
        if (iteration <= control$warmup && isTRUE(control$adapt_warmup)) {
          eta <- min(.05, (iteration + 10)^(-.6))
          if (proposal_kind == "componentwise") {
            step <- pmin(20 * proposal_scale, pmax(.05 * proposal_scale,
                          step * exp(eta * (sweep_accept - .44))))
          } else {
            factor <- min(20 * initial_factor, max(.05 * initial_factor,
                          factor * exp(eta * (sweep_accept[1L] - .234))))
            step <- proposal_scale * factor
          }
        }
        if (iteration > control$warmup) draws[iteration - control$warmup, chain, ] <- y
      }
      final_steps[, chain] <- step
      if (proposal_kind == "blocked_preconditioned") final_factors[chain] <- factor
      completed_chains <- completed_chains + 1L
    }
  }, gapr_budget_exhausted = function(e) failure <<- "INCONCLUSIVE_BUDGET_LIMITED",
     error = function(e) failure <<- paste0("FAIL_REFERENCE_EXECUTION: ", conditionMessage(e)))
  out <- if (is.null(failure) && identical(sort(chain_ids), 1:4)) gapr_diagnose_draws(draws, target, control) else if (is.null(failure))
    list(status = "CHAINS_PENDING_COMBINATION", qualified = FALSE, dependency = dependency) else
    list(status = failure, qualified = FALSE, dependency = dependency)
  out$draws <- draws; out$seeds <- seeds; out$control <- control
  out$chain_ids <- chain_ids; out$proposal_kind <- proposal_kind
  out$proposal_covariance <- proposal_covariance
  out$initial_proposal_scales <- proposal_scale
  out$adaptation <- "warmup_only_then_frozen_symmetric_MH_proposal"
  out$acceptance <- accepted / pmax(attempted, 1L)
  out$final_proposal_scales <- final_steps
  out$final_proposal_factors <- final_factors
  out$callback_evaluations <- target$counter$value - start_calls
  out$elapsed_seconds <- proc.time()[["elapsed"]] - start_time
  out$condition <- target$contract; out$scientific_runs <- 0L; out$authentic_reads <- 0L
  out$full_parameter_refits <- 0L
  out$conditional_reference_chains_requested <- length(chain_ids)
  out$conditional_reference_chains_attempted <- started_chains
  out$conditional_reference_chains_completed <- completed_chains
  out
}

gapr_combine_chains <- function(parts, target, control) {
  if (!is.list(parts) || !length(parts)) gapr_stop("No chain receipts supplied.")
  selected <- unlist(lapply(parts, function(x) x$chain_ids), use.names = FALSE)
  if (length(selected) != 4L || anyDuplicated(selected) || !identical(sort(selected), 1:4))
    gapr_stop("Combination requires each predetermined chain exactly once.")
  H <- target$horizon
  draws <- array(NA_real_, c(control$samples, 4L, H))
  control_names <- setdiff(names(control), "chain_ids")
  kind <- if (is.null(control$proposal_kind)) "componentwise" else control$proposal_kind
  proposal_covariance <- parts[[1L]]$proposal_covariance
  proposal_scales <- parts[[1L]]$initial_proposal_scales
  for (part in parts) {
    if (!part$status %in% c("CHAINS_PENDING_COMBINATION", "QUALIFIED_CONDITIONAL_REFERENCE",
                             "INCONCLUSIVE_MCMC_DIAGNOSTICS"))
      return(list(status = "INCONCLUSIVE_CHAIN_EXECUTION", qualified = FALSE, parts = parts))
    if (!identical(part$seeds, gapr_named_seeds(target$contract$p)) ||
        !identical(part$proposal_kind, kind) ||
        !identical(part$proposal_covariance, proposal_covariance) ||
        !identical(part$initial_proposal_scales, proposal_scales) ||
        !identical(sort(setdiff(names(part$control), "chain_ids")), sort(control_names)) ||
        !all(vapply(control_names, function(n) identical(part$control[[n]],control[[n]]), logical(1L))))
      gapr_stop("Chain controls, proposal or predetermined seeds differ.")
    fields <- c("likelihood_family", "p", "sigma_y", "sigma_g", "parameter_id", "feature_id", "issued",
                "known_baseline", "forecast_dates", "coefficient_covariance")
    if (!all(vapply(fields, function(n) identical(part$condition[[n]], target$contract[[n]]), logical(1L))) ||
        !identical(dim(part$draws), c(as.integer(control$samples), 4L, H)))
      gapr_stop("Chain conditional targets or draw allocations differ.")
    for (chain in part$chain_ids) draws[, chain, ] <- part$draws[, chain, ]
  }
  out <- gapr_diagnose_draws(draws, target, control)
  out$draws <- draws; out$condition <- target$contract
  out$callback_evaluations <- sum(vapply(parts, function(x) x$callback_evaluations, numeric(1L)))
  out$scientific_runs <- 0L; out$authentic_reads <- 0L
  out$full_parameter_refits <- 0L
  out$conditional_reference_chains_requested <- 4L
  out$conditional_reference_chains_attempted <- sum(vapply(parts,
    function(x)x$conditional_reference_chains_attempted,integer(1L)))
  out$conditional_reference_chains_completed <- sum(vapply(parts,
    function(x)x$conditional_reference_chains_completed,integer(1L)))
  out$scope <- "Four predeclared conditional-reference chains; not a full posterior fit."
  out
}

gapr_callback_timing <- function(target, paths) {
  paths <- as.matrix(paths)
  if (nrow(paths) != target$horizon || !ncol(paths) || any(!is.finite(paths)))
    gapr_stop("Timing paths must be explicitly declared and aligned.")
  before <- target$counter$value; start <- proc.time()[["elapsed"]]
  values <- vapply(seq_len(ncol(paths)), function(i) gapr_log_target(target, paths[, i]), numeric(1L))
  elapsed <- proc.time()[["elapsed"]] - start
  list(evaluations = target$counter$value - before, elapsed_seconds = elapsed,
       seconds_per_evaluation = elapsed / ncol(paths), values = values,
       interpretation = "Measured fixed-input pilot; not permission to launch or widen budgets.")
}

gapr_matched_fixed_vb <- function(target, location_jacobian_callback, engine_env,
                                  initial_mean, initial_covariance, max_iterations = 500L,
                                  max_wall_seconds = 120, tolerance = 1e-8, jitter = 1e-8) {
  H <- target$horizon; M <- target$n_members; c <- target$contract
  mean <- as.numeric(initial_mean); covariance <- as.matrix(initial_covariance)
  if (length(mean) != H || !identical(dim(covariance), c(H, H)) ||
      any(!is.finite(c(mean, covariance))) || any(eigen((covariance + t(covariance))/2,
        symmetric = TRUE, only.values = TRUE)$values <= 0) ||
      max_iterations < 1 || max_iterations != floor(max_iterations) || max_wall_seconds <= 0) {
    gapr_stop("Invalid matched fixed-parameter VB initial state/budget.")
  }
  constants <- engine_env$app_latent_al_constants(c$p)
  sigma_state <- list(inv_mean = c(Y = 1 / c$sigma_y, G = 1 / c$sigma_g))
  make_rows <- function(m, V) {
    loc <- gapr_locations(target, m, location_jacobian_callback)
    E <- diag(H) - loc$reference_jacobian
    variance_y <- diag(E %*% V %*% t(E))
    variance_g <- diag(loc$ensemble_jacobian %*% V %*% t(loc$ensemble_jacobian))
    residual_g <- as.numeric(t(c$issued - matrix(loc$ensemble_location, H, M)))
    list(strategy = "streamed_grouped", source = c(rep("Y", H), rep("G", H*M)),
      fixed = list(n = 0L, source = character(), R = numeric(), e = numeric(), weight = numeric()),
      future = list(n_y = H, n_g = H*M, H_y = matrix(loc$reference_location, H, 1L),
        H_g_key = matrix(loc$ensemble_location, H, 1L),
        J_y = lapply(seq_len(H), function(h) matrix(loc$reference_jacobian[h, ], 1L, H)),
        J_g_key = lapply(seq_len(H), function(h) matrix(loc$ensemble_jacobian[h, ], 1L, H)),
        R_y = (m-loc$reference_location)^2+variance_y,
        R_g = residual_g^2+rep(variance_g, each = M),
        e_y = m-loc$reference_location, e_g = residual_g,
        z_g = as.numeric(t(c$issued)), g_future_index = rep(seq_len(H), each = M),
        g_index_by_h = lapply(seq_len(H), function(h) (h-1L)*M+seq_len(M)),
        weight_y = rep(1,H), weight_g = rep(1,H*M)))
  }
  start <- proc.time()[["elapsed"]]; before <- target$counter$jacobian
  rows <- make_rows(mean,covariance)
  local <- engine_env$app_latent_update_v(rows,sigma_state,constants)
  scales <- c(rep(c$sigma_y,H),rep(c$sigma_g,H*M))
  old <- c(mean/c$sigma_y,covariance/c$sigma_y^2,scales*local$inv_mean)
  stable <- 0L; repaired <- FALSE; status <- "INCONCLUSIVE_ITERATION_LIMIT"
  for (iteration in seq_len(max_iterations)) {
    if (proc.time()[["elapsed"]]-start > max_wall_seconds) {status <- "INCONCLUSIVE_WALL_LIMIT";break}
    update <- engine_env$app_latent_update_future_gaussian_delta(rows,mean,
      theta_mean=1,theta_cov=matrix(0,1L,1L),e_inv_v=local$inv_mean,
      sigma_state=sigma_state,constants=constants,jitter=jitter,
      future_gaussian_prior=NULL,include_future_y_working_likelihood=TRUE)
    mean <- update$mean;covariance <- update$cov;repaired <- repaired||isTRUE(update$repaired)
    rows <- make_rows(mean,covariance)
    local <- engine_env$app_latent_update_v(rows,sigma_state,constants)
    current <- c(mean/c$sigma_y,covariance/c$sigma_y^2,scales*local$inv_mean)
    change <- max(abs(current-old));old <- current
    stable <- if(change <= tolerance) stable+1L else 0L
    if(stable >= 3L) {status <- "FIXED_PARAMETER_VB_STABILIZED";break}
  }
  probs <- sort(unique(c(c$p,.5)))
  quantiles <- do.call(rbind,lapply(probs,function(p) data.frame(horizon=seq_len(H),
    probability=p,quantile=mean+stats::qnorm(p)*sqrt(diag(covariance)))))
  list(status=status,mean=mean,covariance=covariance,quantiles=quantiles,
    iterations=iteration,max_scaled_change=change,repaired=repaired,
    jacobian_evaluations=target$counter$jacobian-before,condition=c,
    comparison_type="matched_fixed_parameter_VB_not_original_full_qF",
    scientific_runs=0L,authentic_reads=0L,full_parameter_refits=0L,
    conditional_future_path_vb_optimizations=1L)
}

gapr_compare_matched_vb <- function(reference, vb) {
  if (!identical(vb$comparison_type,"matched_fixed_parameter_VB_not_original_full_qF") ||
      !is.list(reference$condition) || !is.list(vb$condition)) gapr_stop("Unmatched posterior comparison.")
  fields <- c("likelihood_family","p","sigma_y","sigma_g","parameter_id","feature_id","issued","known_baseline",
              "forecast_dates","coefficient_covariance","ensemble_location_convention")
  if (!all(vapply(fields,function(n) identical(reference$condition[[n]],vb$condition[[n]]),logical(1L))) ||
      any(vb$condition$coefficient_covariance != 0)) gapr_stop("Conditional parameters/features differ.")
  if (!isTRUE(reference$qualified)) return(list(status="INCONCLUSIVE_REFERENCE_UNQUALIFIED",comparison=NULL))
  if (!identical(vb$status,"FIXED_PARAMETER_VB_STABILIZED") || isTRUE(vb$repaired))
    return(list(status="INCONCLUSIVE_VB_UNQUALIFIED",comparison=NULL))
  a <- reference$quantiles; names(a)[names(a)=="quantile"] <- "reference_quantile"
  b <- vb$quantiles;names(b)[names(b)=="quantile"] <- "matched_vb_quantile"
  result <- merge(a,b,by=c("horizon","probability"),all=TRUE,sort=TRUE)
  if(anyNA(result)) gapr_stop("Matched conditional summaries are incomplete.")
  result$difference <- result$matched_vb_quantile-result$reference_quantile
  list(status="MATCHED_CONDITIONAL_COMPARISON",comparison=result,
       scope="Not a comparison with original qF or a full-posterior repair.")
}
