# Generated-data-tested, fixed-parameter AL innovation sampler. This module
# performs no file reads, dispatch, prior/model changes or publication.
gis_require <- function(ok, why, class = "gis_contract_error") {
  if (!isTRUE(ok)) stop(structure(list(message = why, call = NULL),
    class = c(class, "error", "condition")))
  invisible(TRUE)
}

gis_validate_control <- function(c) {
  keys <- c("warmup", "samples", "max_evaluations", "max_wall_seconds",
    "delta_initial", "delta_min", "delta_max", "target_accept", "adapt_warmup",
    "seeds", "progress_every", "rhat_max", "min_ess", "max_quantile_mcse")
  q <- gis_require
  q(is.list(c) && setequal(names(c), keys) && length(c) == length(keys),
    "exact pCN controls required")
  for (n in c("warmup", "samples", "max_evaluations", "progress_every"))
    q(is.numeric(c[[n]]) && length(c[[n]]) == 1L && is.finite(c[[n]]) &&
      c[[n]] == floor(c[[n]]) && c[[n]] >= if (n == "warmup") 0 else 1,
      "finite fixed iteration, evaluation and progress budgets required")
  q(c$samples >= 20L && c$max_evaluations >= 1 + c$warmup + c$samples &&
    length(c$max_wall_seconds) == 1L && is.finite(c$max_wall_seconds) && c$max_wall_seconds > 0,
    "complete chain and native wall budgets required")
  q(all(vapply(c[c("delta_initial", "delta_min", "delta_max", "target_accept")],
    function(x) is.numeric(x) && length(x) == 1L && is.finite(x), logical(1L))) &&
    0 < c$delta_min && c$delta_min <= c$delta_initial &&
    c$delta_initial <= c$delta_max && c$delta_max < 1 &&
    c$target_accept > 0 && c$target_accept < 1 &&
    is.logical(c$adapt_warmup) && length(c$adapt_warmup) == 1L && !is.na(c$adapt_warmup),
    "bounded pCN scale and explicit warmup adaptation required")
  q(is.numeric(c$seeds) && length(c$seeds) == 4L && !anyDuplicated(c$seeds) &&
    all(is.finite(c$seeds)) && all(c$seeds == floor(c$seeds)) &&
    all(c$seeds > 0 & c$seeds <= .Machine$integer.max), "four distinct named seeds required")
  q(all(vapply(c[c("rhat_max", "min_ess", "max_quantile_mcse")],
    function(x) is.numeric(x) && length(x) == 1L && is.finite(x), logical(1L))) &&
    c$rhat_max > 1 && c$min_ess > 0 && c$max_quantile_mcse > 0,
    "explicit precision thresholds required")
  invisible(TRUE)
}

gis_pcn_proposal <- function(z, delta, noise) {
  gis_require(is.numeric(z) && length(z) > 0L && all(is.finite(z)) &&
    is.numeric(noise) && length(noise) == length(z) && all(is.finite(noise)) &&
    length(delta) == 1L && is.finite(delta) && delta > 0 && delta < 1,
    "finite pCN state/noise and interior scale required")
  sqrt(1 - delta^2) * z + delta * noise
}

gis_pcn_log_proposal <- function(to, from, delta) {
  gis_pcn_proposal(from, delta, rep(0, length(from)))
  gis_require(length(to) == length(from) && all(is.finite(to)), "aligned proposal point required")
  sum(stats::dnorm(to, sqrt(1 - delta^2) * from, delta, log = TRUE))
}

gis_sample_chain <- function(evaluate, initial_base, control, chain_id, progress = NULL) {
  q <- gis_require; gis_validate_control(control)
  q(is.function(evaluate) && is.numeric(initial_base) && length(initial_base) > 0L &&
    all(is.finite(initial_base)) && length(chain_id) == 1L && chain_id %in% 1:4 &&
    (is.null(progress) || is.function(progress)), "finite declared chain and evaluator required")
  old_kind <- RNGkind()
  old_seed <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE))
    get(".Random.seed", .GlobalEnv) else NULL
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (is.null(old_seed)) {
      if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
    } else assign(".Random.seed", old_seed, .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  seed <- as.integer(control$seeds[chain_id]); set.seed(seed)
  started <- proc.time()[["elapsed"]]
  calls <- 0L; completed <- 0L; accepted_warmup <- 0L; accepted_retained <- 0L
  squared_movement <- 0; delta <- control$delta_initial; frozen_delta <- NA_real_
  z <- as.numeric(initial_base); current <- NULL
  H <- length(z); draws <- matrix(NA_real_, control$samples, H)
  failure <- NULL; status <- "CHAIN_COMPLETE_NOT_PRODUCTION_QUALIFICATION"
  run <- function(z) {
    if (calls >= control$max_evaluations ||
        proc.time()[["elapsed"]] - started >= control$max_wall_seconds)
      q(FALSE, "declared innovation chain budget exhausted", "gis_budget_exhausted")
    calls <<- calls + 1L
    result <- evaluate(z)
    if (proc.time()[["elapsed"]] - started >= control$max_wall_seconds)
      q(FALSE, "declared innovation chain wall budget exhausted during evaluation", "gis_budget_exhausted")
    q(is.list(result) && is.numeric(result$path) && length(result$path) == H &&
      all(is.finite(result$path)) && is.numeric(result$log_likelihood) &&
      length(result$log_likelihood) == 1L && !is.na(result$log_likelihood) &&
      result$log_likelihood != Inf, "evaluator must return a finite path and member-only log likelihood")
    result
  }
  emit <- function() {
    if (!is.null(progress)) progress(list(schema_version = "glofas_innovation_progress_v1",
      chain_id = as.integer(chain_id), completed_iterations = completed,
      retained_iterations = max(0L, completed - control$warmup),
      callback_evaluations = calls, elapsed_seconds = proc.time()[["elapsed"]] - started,
      delta = delta, accepted_warmup = accepted_warmup,
      accepted_retained = accepted_retained,
      fully_completed = completed == control$warmup + control$samples))
    invisible(NULL)
  }
  tryCatch({
    current <- run(z)
    q(is.finite(current$log_likelihood), "initial member likelihood must be finite")
    if (control$warmup == 0L) frozen_delta <- delta
    for (iteration in seq_len(control$warmup + control$samples)) {
      candidate_z <- gis_pcn_proposal(z, delta, stats::rnorm(H))
      candidate <- run(candidate_z)
      # pCN is reversible for the independent standard-Normal coordinate
      # reference. The base and proposal terms cancel exactly; only G remains.
      accepted <- log(stats::runif(1L)) < candidate$log_likelihood - current$log_likelihood
      if (accepted) {
        if (iteration > control$warmup) squared_movement <- squared_movement +
          sum((candidate$path - current$path)^2)
        z <- candidate_z; current <- candidate
        if (iteration <= control$warmup) accepted_warmup <- accepted_warmup + 1L else
          accepted_retained <- accepted_retained + 1L
      }
      if (iteration <= control$warmup && isTRUE(control$adapt_warmup)) {
        eta <- min(.05, (iteration + 10)^(-.6))
        delta <- min(control$delta_max, max(control$delta_min,
          delta * exp(eta * (as.numeric(accepted) - control$target_accept))))
      }
      if (iteration == control$warmup) frozen_delta <- delta
      if (iteration > control$warmup) draws[iteration - control$warmup, ] <- current$path
      completed <- iteration
      if (iteration %% control$progress_every == 0L ||
          iteration == control$warmup + control$samples) emit()
    }
  }, gis_budget_exhausted = function(e) {
    failure <<- conditionMessage(e); status <<- "INCONCLUSIVE_BUDGET_LIMITED"
  }, error = function(e) {
    failure <<- conditionMessage(e); status <<- "FAILED_OR_PARTIAL_CHAIN_NOT_PROMOTABLE"
  })
  list(schema_version = "glofas_innovation_chain_v1", status = status,
    chain_id = as.integer(chain_id), seed = seed, control = control, draws = draws,
    completed_iterations = completed, retained_iterations = max(0L, completed - control$warmup),
    callback_evaluations = calls, elapsed_seconds = proc.time()[["elapsed"]] - started,
    accepted_warmup = accepted_warmup, accepted_retained = accepted_retained,
    retained_squared_jump_sum = squared_movement, frozen_delta = frozen_delta,
    final_delta = delta, final_base = z,
    final_rng_state = get(".Random.seed", .GlobalEnv), failure = failure,
    fully_completed = is.null(failure) &&
      identical(status, "CHAIN_COMPLETE_NOT_PRODUCTION_QUALIFICATION") &&
      completed == control$warmup + control$samples && all(is.finite(draws)),
    reference_qualified = FALSE, full_posterior_accuracy_qualified = FALSE,
    production_launch_authorized = FALSE, publication_authorized = FALSE,
    exact_resume_qualified = FALSE,
    scope = "Fixed-parameter conditional pCN pilot; no full parameter posterior or production approval.")
}

gis_combine_chains <- function(parts, target, control) {
  q <- gis_require; gis_validate_control(control)
  q(is.list(parts) && length(parts) == 4L &&
    identical(sort(vapply(parts, function(x) x$chain_id, integer(1L))), 1:4),
    "all four predeclared innovation chains required exactly once")
  H <- target$horizon; draws <- array(NA_real_, c(control$samples, 4L, H))
  for (x in parts) {
    q(identical(x$control, control) && identical(x$seed, as.integer(control$seeds[x$chain_id])) &&
      identical(dim(x$draws), c(as.integer(control$samples), as.integer(H))),
      "innovation chain controls, seeds or dimensions differ")
    draws[, x$chain_id, ] <- x$draws
  }
  complete <- all(vapply(parts, function(x) isTRUE(x$fully_completed) &&
    identical(x$status, "CHAIN_COMPLETE_NOT_PRODUCTION_QUALIFICATION") && is.null(x$failure) &&
    x$completed_iterations == control$warmup + control$samples &&
    x$retained_iterations == control$samples && all(is.finite(x$draws)), logical(1L)))
  diagnostics <- if (complete) gapr_diagnose_draws(draws, target, control) else
    list(status = "INCONCLUSIVE_PARTIAL_CHAINS", qualified = FALSE)
  pass <- isTRUE(diagnostics$qualified)
  diagnostics$original_precision_status <- diagnostics$status
  diagnostics$status <- if (complete) {
    if (pass) "PILOT_PRECISION_THRESHOLDS_PASS_NOT_REFERENCE_QUALIFICATION" else
      "PILOT_PRECISION_THRESHOLDS_NOT_MET"
  } else "INCONCLUSIVE_PARTIAL_CHAINS"
  diagnostics$qualified <- FALSE
  list(status = if (complete) "PILOT_CHAINS_COMPLETE_NOT_PRODUCTION_QUALIFICATION" else
      "PILOT_PARTIAL_RETAINED_NOT_PROMOTABLE", draws = draws,
    diagnostic_thresholds_passed = pass, diagnostics = diagnostics,
    chains = lapply(parts, function(x) {x$draws <- NULL; x$final_rng_state <- NULL; x}),
    total_value_evaluations = sum(vapply(parts, function(x) x$callback_evaluations, integer(1L))),
    reference_qualified = FALSE, full_posterior_accuracy_qualified = FALSE,
    production_launch_authorized = FALSE, publication_authorized = FALSE)
}
