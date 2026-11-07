# Truth-free whole-path references for fixed-parameter GloFAS targets.
# These routines consume caller-supplied log densities and never read files,
# fit historical parameters, inspect scoring truth or authorize production.

ggpr_stop <- function(message, class = "ggpr_contract_error") {
  stop(structure(list(message = paste0("GloFAS global path reference: ", message),
    call = NULL), class = c(class, "error", "condition")))
}

ggpr_scalar <- function(x, lower = -Inf, upper = Inf, integer = FALSE) {
  is.numeric(x) && length(x) == 1L && is.finite(x) && x >= lower && x <= upper &&
    (!integer || x == floor(x))
}

ggpr_logsumexp <- function(x) {
  anchor <- max(x)
  if (!is.finite(anchor)) return(anchor)
  anchor + log(sum(exp(x - anchor)))
}

ggpr_root <- function(covariance) {
  covariance <- as.matrix(covariance)
  if (!nrow(covariance) || nrow(covariance) != ncol(covariance) ||
      any(!is.finite(covariance)) ||
      max(abs(covariance - t(covariance))) > 1e-10) {
    ggpr_stop("proposal covariance must be finite, square and symmetric")
  }
  root <- tryCatch(chol(covariance), error = function(e) NULL)
  if (is.null(root)) ggpr_stop("proposal covariance must be positive definite")
  root
}

ggpr_log_mvn <- function(paths, mean, root) {
  paths <- as.matrix(paths)
  mean <- as.numeric(mean)
  if (ncol(paths) != length(mean) || !identical(dim(root), c(length(mean), length(mean))) ||
      any(!is.finite(paths))) ggpr_stop("Gaussian proposal inputs are not aligned")
  centered <- sweep(paths, 2L, mean)
  standardized <- backsolve(root, t(centered), transpose = TRUE)
  -.5 * (length(mean) * log(2 * pi) + 2 * sum(log(diag(root))) +
    colSums(standardized^2))
}

ggpr_draw_mvn <- function(n, mean, root) {
  matrix(stats::rnorm(n * length(mean)), nrow = n) %*% root +
    matrix(mean, n, length(mean), byrow = TRUE)
}

ggpr_restore_rng <- function(old_kind, old_seed, had_seed) {
  do.call(RNGkind, as.list(old_kind))
  if (had_seed) {
    assign(".Random.seed", old_seed, envir = .GlobalEnv)
  } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
    rm(".Random.seed", envir = .GlobalEnv)
  }
}

ggpr_weights <- function(log_weights) {
  normalizer <- ggpr_logsumexp(log_weights)
  if (!is.finite(normalizer)) ggpr_stop("all path weights are numerically zero")
  weights <- exp(log_weights - normalizer)
  weights / sum(weights)
}

ggpr_weighted_quantile <- function(values, weights, probabilities) {
  values <- as.numeric(values)
  weights <- as.numeric(weights)
  probabilities <- as.numeric(probabilities)
  if (!length(values) || length(values) != length(weights) ||
      any(!is.finite(c(values, weights, probabilities))) || any(weights < 0) ||
      sum(weights) <= 0 || any(probabilities <= 0 | probabilities >= 1)) {
    ggpr_stop("invalid weighted empirical distribution")
  }
  order <- order(values)
  values <- values[order]
  cumulative <- cumsum(weights[order] / sum(weights))
  vapply(probabilities, function(p) values[which(cumulative +
    16 * .Machine$double.eps >= p)[1L]], numeric(1L))
}

ggpr_summary <- function(paths, weights, probabilities) {
  paths <- as.matrix(paths)
  weights <- as.numeric(weights) / sum(weights)
  mean <- colSums(paths * weights)
  centered <- sweep(paths, 2L, mean)
  covariance <- crossprod(centered * sqrt(weights), centered * sqrt(weights))
  quantiles <- do.call(rbind, lapply(seq_len(ncol(paths)), function(h) {
    data.frame(horizon = h, probability = probabilities,
      quantile = ggpr_weighted_quantile(paths[, h], weights, probabilities))
  }))
  list(mean = mean, covariance = covariance, quantiles = quantiles,
    effective_sample_size = 1 / sum(weights^2),
    maximum_weight = max(weights),
    normalized_entropy = -sum(ifelse(weights > 0, weights * log(weights), 0)) /
      log(length(weights)))
}

ggpr_validate_common <- function(log_target, proposal_mean, proposal_covariance,
    control, tempered = FALSE) {
  if (!is.function(log_target)) ggpr_stop("log_target must be a function")
  proposal_mean <- as.numeric(proposal_mean)
  root <- ggpr_root(proposal_covariance)
  if (!length(proposal_mean) || ncol(root) != length(proposal_mean) ||
      any(!is.finite(proposal_mean))) ggpr_stop("proposal mean and covariance differ")
  needed <- c("particles", "seed", "max_evaluations", "max_wall_seconds",
    "min_ess_fraction", "max_weight_fraction")
  if (tempered) needed <- c(needed, "ess_target_fraction", "max_tempering_steps",
    "rejuvenation_steps", "random_walk_scale", "resample_final")
  if (!is.list(control) || !all(needed %in% names(control)) ||
      !ggpr_scalar(control$particles, 2, 100000, TRUE) ||
      !ggpr_scalar(control$seed, 1, .Machine$integer.max, TRUE) ||
      !ggpr_scalar(control$max_evaluations, control$particles, Inf, TRUE) ||
      !ggpr_scalar(control$max_wall_seconds, .Machine$double.eps) ||
      !ggpr_scalar(control$min_ess_fraction, 0, 1) ||
      !ggpr_scalar(control$max_weight_fraction, 0, 1)) {
    ggpr_stop("invalid finite reference controls")
  }
  if (tempered && (!ggpr_scalar(control$ess_target_fraction, .05, .99) ||
      !ggpr_scalar(control$max_tempering_steps, 1, 1000, TRUE) ||
      !ggpr_scalar(control$rejuvenation_steps, 0, 100, TRUE) ||
      !ggpr_scalar(control$random_walk_scale, .Machine$double.eps, 10) ||
      !is.logical(control$resample_final) || length(control$resample_final) != 1L ||
      is.na(control$resample_final))) {
    ggpr_stop("invalid likelihood-tempering controls")
  }
  list(mean = proposal_mean, covariance = as.matrix(proposal_covariance), root = root,
    control = control)
}

ggpr_evaluate <- function(paths, log_target, max_evaluations, start_time,
    max_wall_seconds, evaluations) {
  paths <- as.matrix(paths)
  if (evaluations + nrow(paths) > max_evaluations) {
    ggpr_stop("evaluation budget exhausted", "ggpr_budget_exhausted")
  }
  if (proc.time()[["elapsed"]] - start_time > max_wall_seconds) {
    ggpr_stop("wall budget exhausted", "ggpr_budget_exhausted")
  }
  values <- vapply(seq_len(nrow(paths)), function(i) log_target(paths[i, ]), numeric(1L))
  if (any(is.na(values) | values == Inf)) ggpr_stop("target returned an invalid value")
  list(values = values, evaluations = evaluations + nrow(paths))
}

ggpr_importance <- function(log_target, proposal_mean, proposal_covariance,
    probabilities, control, retain_paths = TRUE) {
  setup <- ggpr_validate_common(log_target, proposal_mean, proposal_covariance, control)
  probabilities <- as.numeric(probabilities)
  if (!length(probabilities) || any(!is.finite(probabilities)) ||
      any(probabilities <= 0 | probabilities >= 1)) ggpr_stop("invalid probabilities")
  old_kind <- RNGkind()
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit(ggpr_restore_rng(old_kind, old_seed, had_seed), add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(as.integer(control$seed))
  start <- proc.time()[["elapsed"]]
  paths <- ggpr_draw_mvn(as.integer(control$particles), setup$mean, setup$root)
  evaluated <- ggpr_evaluate(paths, log_target, control$max_evaluations,
    start, control$max_wall_seconds, 0L)
  log_q <- ggpr_log_mvn(paths, setup$mean, setup$root)
  log_ratio <- evaluated$values - log_q
  weights <- ggpr_weights(log_ratio)
  summary <- ggpr_summary(paths, weights, probabilities)
  passed <- summary$effective_sample_size >= control$min_ess_fraction * nrow(paths) &&
    summary$maximum_weight <= control$max_weight_fraction
  out <- c(list(schema_version = "glofas_global_path_importance_v1",
    status = if (passed) "REFERENCE_GATE_PASS" else "REFERENCE_GATE_FAIL",
    diagnostic_thresholds_passed = passed,
    log_normalizer_estimate = ggpr_logsumexp(log_ratio) - log(nrow(paths)),
    log_target = evaluated$values, log_proposal = log_q, weights = weights,
    evaluations = evaluated$evaluations,
    elapsed_seconds = proc.time()[["elapsed"]] - start,
    method = "whole_path_self_normalized_importance",
    time_sequential_resampling = FALSE, future_truth_read = FALSE,
    full_parameter_refits = 0L, production_qualified = FALSE), summary)
  if (isTRUE(retain_paths)) out$paths <- paths
  out
}

ggpr_systematic_resample <- function(weights) {
  n <- length(weights)
  positions <- stats::runif(1L, 0, 1 / n) + (0:(n - 1L)) / n
  pmin(findInterval(positions, c(0, cumsum(weights)), rightmost.closed = TRUE), n)
}

ggpr_next_beta <- function(beta, weights, log_ratio, target_ess) {
  upper <- 1 - beta
  ess <- function(delta) {
    w <- ggpr_weights(log(weights) + delta * log_ratio)
    1 / sum(w^2)
  }
  if (ess(upper) >= target_ess) return(1)
  low <- 0
  high <- upper
  for (iteration in seq_len(80L)) {
    middle <- (low + high) / 2
    if (ess(middle) < target_ess) high <- middle else low <- middle
  }
  beta + low
}

ggpr_tempered <- function(log_target, proposal_mean, proposal_covariance,
    probabilities, control, retain_paths = TRUE) {
  setup <- ggpr_validate_common(log_target, proposal_mean, proposal_covariance,
    control, tempered = TRUE)
  probabilities <- as.numeric(probabilities)
  if (!length(probabilities) || any(!is.finite(probabilities)) ||
      any(probabilities <= 0 | probabilities >= 1)) ggpr_stop("invalid probabilities")
  old_kind <- RNGkind()
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit(ggpr_restore_rng(old_kind, old_seed, had_seed), add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(as.integer(control$seed))
  start <- proc.time()[["elapsed"]]
  n <- as.integer(control$particles)
  paths <- ggpr_draw_mvn(n, setup$mean, setup$root)
  evaluated <- ggpr_evaluate(paths, log_target, control$max_evaluations,
    start, control$max_wall_seconds, 0L)
  evaluations <- evaluated$evaluations
  log_target_values <- evaluated$values
  log_q <- ggpr_log_mvn(paths, setup$mean, setup$root)
  log_ratio <- log_target_values - log_q
  weights <- rep(1 / n, n)
  lineages <- seq_len(n)
  beta <- 0
  log_normalizer <- 0
  records <- list()
  accepted <- attempted <- 0L
  failure <- NULL
  for (stage in seq_len(as.integer(control$max_tempering_steps))) {
    next_beta <- ggpr_next_beta(beta, weights, log_ratio,
      control$ess_target_fraction * n)
    if (!is.finite(next_beta) || next_beta <= beta + 1e-12) {
      failure <- "INCONCLUSIVE_TEMPERING_STALLED"
      break
    }
    increment <- (next_beta - beta) * log_ratio
    log_increment <- ggpr_logsumexp(log(weights) + increment)
    weights <- ggpr_weights(log(weights) + increment)
    log_normalizer <- log_normalizer + log_increment
    pre_resample_ess <- 1 / sum(weights^2)
    beta <- next_beta
    do_resample <- beta < 1 || isTRUE(control$resample_final)
    if (do_resample) {
      selected <- ggpr_systematic_resample(weights)
      paths <- paths[selected, , drop = FALSE]
      log_target_values <- log_target_values[selected]
      log_q <- log_q[selected]
      log_ratio <- log_ratio[selected]
      lineages <- lineages[selected]
      weights <- rep(1 / n, n)
    }
    stage_accepted <- stage_attempted <- 0L
    if (control$rejuvenation_steps > 0L) {
      for (move in seq_len(as.integer(control$rejuvenation_steps))) {
        proposals <- paths + control$random_walk_scale *
          (matrix(stats::rnorm(n * length(setup$mean)), nrow = n) %*% setup$root)
        proposal_eval <- tryCatch(ggpr_evaluate(proposals, log_target,
          control$max_evaluations, start, control$max_wall_seconds, evaluations),
          ggpr_budget_exhausted = identity)
        if (inherits(proposal_eval, "ggpr_budget_exhausted")) {
          failure <- "INCONCLUSIVE_BUDGET_LIMITED"
          break
        }
        evaluations <- proposal_eval$evaluations
        proposal_log_q <- ggpr_log_mvn(proposals, setup$mean, setup$root)
        current_tempered <- (1 - beta) * log_q + beta * log_target_values
        proposed_tempered <- (1 - beta) * proposal_log_q + beta * proposal_eval$values
        take <- log(stats::runif(n)) < proposed_tempered - current_tempered
        if (any(take)) {
          paths[take, ] <- proposals[take, , drop = FALSE]
          log_target_values[take] <- proposal_eval$values[take]
          log_q[take] <- proposal_log_q[take]
          log_ratio[take] <- log_target_values[take] - log_q[take]
        }
        stage_accepted <- stage_accepted + sum(take)
        stage_attempted <- stage_attempted + n
      }
    }
    accepted <- accepted + stage_accepted
    attempted <- attempted + stage_attempted
    records[[stage]] <- data.frame(stage = stage, beta = beta,
      pre_resample_ess = pre_resample_ess,
      resampled = do_resample,
      unique_initial_lineages = length(unique(lineages)),
      rejuvenation_acceptance = if (stage_attempted) stage_accepted / stage_attempted else NA_real_)
    if (!is.null(failure) || beta >= 1 - 1e-12) break
  }
  complete <- is.null(failure) && beta >= 1 - 1e-12
  summary <- ggpr_summary(paths, weights, probabilities)
  diagnostics <- if (length(records)) do.call(rbind, records) else data.frame()
  min_lineages <- if (nrow(diagnostics)) min(diagnostics$unique_initial_lineages) else 0L
  passed <- complete && summary$effective_sample_size >= control$min_ess_fraction * n &&
    summary$maximum_weight <= control$max_weight_fraction && min_lineages >= 2L
  out <- c(list(schema_version = "glofas_global_path_tempered_v1",
    status = if (!complete) failure else if (passed) "REFERENCE_GATE_PASS" else
      "REFERENCE_GATE_FAIL",
    diagnostic_thresholds_passed = passed, complete = complete,
    log_normalizer_estimate = log_normalizer, beta = beta,
    diagnostics = diagnostics, lineages = lineages,
    evaluations = evaluations,
    acceptance_rate = if (attempted) accepted / attempted else NA_real_,
    elapsed_seconds = proc.time()[["elapsed"]] - start,
    method = "whole_path_adaptive_likelihood_tempering",
    time_sequential_resampling = FALSE, future_truth_read = FALSE,
    full_parameter_refits = 0L, production_qualified = FALSE,
    weights = weights, log_target = log_target_values, log_proposal = log_q), summary)
  if (isTRUE(retain_paths)) out$paths <- paths
  out
}

