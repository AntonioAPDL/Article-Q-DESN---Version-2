# Phase148 numerical target-invariance audit for sampled-gamma exAL MCMC.

app_joint_exqdesn_phase148_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase148_target_invariance_20260726")
}

app_joint_exqdesn_phase148_state <- function(tau, seed = 148L, n = 12L) {
  set.seed(as.integer(seed))
  support <- app_joint_qvp_exal_support(tau)
  gamma <- support$lower[[1L]] + 0.55 * (support$upper[[1L]] - support$lower[[1L]])
  list(
    y = stats::rnorm(n, sd = 0.8),
    fitted_no_alpha = stats::rnorm(n, sd = 0.25),
    alpha = stats::qnorm(tau) * 0.15,
    s = abs(stats::rnorm(n, mean = 0.7, sd = 0.25)),
    v = pmax(stats::rgamma(n, shape = 2, rate = 2), 0.05),
    sigma = 0.8,
    gamma = gamma,
    tau = tau,
    kappa = 1,
    a_sigma = 0.1,
    b_sigma = 0.1
  )
}

app_joint_exqdesn_phase148_sigma_gig_terms <- function(state, gamma = state$gamma) {
  cst <- app_joint_qvp_exal_constants(state$tau, gamma)
  r <- state$y - state$alpha - state$fitted_no_alpha
  list(
    lambda = -state$a_sigma - 1.5 * state$kappa * length(state$y),
    chi = 2 * state$b_sigma + 2 * state$kappa * sum(state$v) +
      state$kappa * sum((r - cst$A[[1L]] * state$v)^2 / (cst$B[[1L]] * state$v)),
    psi = state$kappa * sum(cst$lambda[[1L]]^2 * state$s^2 / (cst$B[[1L]] * state$v))
  )
}

app_joint_exqdesn_phase148_gig_log_kernel <- function(sigma, terms) {
  (terms$lambda - 1) * log(sigma) -
    0.5 * (terms$chi / sigma + terms$psi * sigma)
}

app_joint_exqdesn_phase148_joint_log_kernel <- function(state, sigma = state$sigma,
                                                         gamma = state$gamma) {
  app_joint_qvp_exal_sigma_gamma_log_kernel(
    sigma = sigma,
    gamma = gamma,
    y = state$y,
    fitted_no_alpha = state$fitted_no_alpha,
    alpha = state$alpha,
    s = state$s,
    v = state$v,
    tau = state$tau,
    kappa = state$kappa,
    a_sigma = state$a_sigma,
    b_sigma = state$b_sigma
  )
}

app_joint_exqdesn_phase148_gamma_conditional_log_kernel <- function(state, gamma) {
  app_joint_qvp_gamma_log_kernel(
    gamma = gamma,
    y = state$y,
    fitted_no_alpha = state$fitted_no_alpha,
    alpha = state$alpha,
    sigma = state$sigma,
    s = state$s,
    v = state$v,
    tau = state$tau,
    kappa = state$kappa
  )
}

app_joint_exqdesn_phase148_constant_difference <- function(reference, candidate) {
  delta <- as.numeric(reference) - as.numeric(candidate)
  reference <- as.numeric(reference)
  candidate <- as.numeric(candidate)
  keep <- is.finite(delta) & is.finite(reference) & is.finite(candidate)
  if (any(keep)) {
    keep <- keep &
      reference >= max(reference[keep]) - 500 &
      candidate >= max(candidate[keep]) - 500
  }
  delta <- delta[keep]
  if (!length(delta)) return(Inf)
  max(abs(delta - stats::median(delta)))
}

app_joint_exqdesn_phase148_identity_audit <- function(
  tau_grid = c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
  tolerance = 1e-7
) {
  rows <- list()
  for (ii in seq_along(tau_grid)) {
    state <- app_joint_exqdesn_phase148_state(tau_grid[[ii]], seed = 14800L + ii)
    sigma_grid <- exp(seq(log(0.08), log(4), length.out = 81L))
    terms <- app_joint_exqdesn_phase148_sigma_gig_terms(state)
    joint_sigma <- vapply(sigma_grid, function(x) {
      app_joint_exqdesn_phase148_joint_log_kernel(state, sigma = x)
    }, numeric(1L))
    gig_sigma <- vapply(sigma_grid, app_joint_exqdesn_phase148_gig_log_kernel, numeric(1L), terms = terms)
    sigma_error <- app_joint_exqdesn_phase148_constant_difference(joint_sigma, gig_sigma)

    support <- app_joint_qvp_exal_support(state$tau)
    gamma_grid <- app_joint_qvp_eta_to_gamma(
      seq(-8, 8, length.out = 101L),
      support$lower[[1L]],
      support$upper[[1L]]
    )
    joint_gamma <- vapply(gamma_grid, function(x) {
      app_joint_exqdesn_phase148_joint_log_kernel(state, gamma = x)
    }, numeric(1L))
    conditional_gamma <- vapply(gamma_grid, function(x) {
      app_joint_exqdesn_phase148_gamma_conditional_log_kernel(state, x)
    }, numeric(1L))
    gamma_error <- app_joint_exqdesn_phase148_constant_difference(joint_gamma, conditional_gamma)
    rows[[ii]] <- data.frame(
      tau = state$tau,
      sigma_grid_n = length(sigma_grid),
      gamma_grid_n = length(gamma_grid),
      sigma_conditional_max_centered_log_error = sigma_error,
      gamma_conditional_max_centered_log_error = gamma_error,
      tolerance = tolerance,
      sigma_identity_status = if (is.finite(sigma_error) && sigma_error <= tolerance) "pass" else "fail",
      gamma_identity_status = if (is.finite(gamma_error) && gamma_error <= tolerance) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

app_joint_exqdesn_phase148_grid <- function(state, n_log_sigma = 101L, n_eta = 121L) {
  support <- app_joint_qvp_exal_support(state$tau)
  log_sigma <- seq(log(0.04), log(6), length.out = as.integer(n_log_sigma))
  eta <- seq(-8, 8, length.out = as.integer(n_eta))
  grid <- expand.grid(log_sigma = log_sigma, eta = eta, KEEP.OUT.ATTRS = FALSE)
  grid$sigma <- exp(grid$log_sigma)
  grid$gamma <- app_joint_qvp_eta_to_gamma(grid$eta, support$lower[[1L]], support$upper[[1L]])
  grid$log_target <- vapply(seq_len(nrow(grid)), function(ii) {
    app_joint_exqdesn_phase148_joint_log_kernel(
      state,
      sigma = grid$sigma[[ii]],
      gamma = grid$gamma[[ii]]
    ) + grid$log_sigma[[ii]] +
      app_joint_qvp_gamma_logit_jacobian(grid$eta[[ii]], support$lower[[1L]], support$upper[[1L]])
  }, numeric(1L))
  log_norm <- max(grid$log_target)
  grid$weight <- exp(grid$log_target - log_norm)
  grid$weight <- grid$weight / sum(grid$weight)
  grid
}

app_joint_exqdesn_phase148_weighted_quantile <- function(x, w, probs) {
  ord <- order(x)
  x <- x[ord]
  w <- w[ord] / sum(w)
  stats::approx(cumsum(w), x, xout = probs, method = "linear", ties = "ordered", rule = 2)$y
}

app_joint_exqdesn_phase148_grid_summary <- function(grid, tau) {
  probs <- c(0.05, 0.50, 0.95)
  sq <- app_joint_exqdesn_phase148_weighted_quantile(grid$sigma, grid$weight, probs)
  gq <- app_joint_exqdesn_phase148_weighted_quantile(grid$gamma, grid$weight, probs)
  sigma_mean <- sum(grid$weight * grid$sigma)
  gamma_mean <- sum(grid$weight * grid$gamma)
  data.frame(
    tau = tau,
    grid_n = nrow(grid),
    sigma_mean = sigma_mean,
    sigma_sd = sqrt(sum(grid$weight * (grid$sigma - sigma_mean)^2)),
    sigma_q05 = sq[[1L]],
    sigma_median = sq[[2L]],
    sigma_q95 = sq[[3L]],
    gamma_mean = gamma_mean,
    gamma_sd = sqrt(sum(grid$weight * (grid$gamma - gamma_mean)^2)),
    gamma_q05 = gq[[1L]],
    gamma_median = gq[[2L]],
    gamma_q95 = gq[[3L]],
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase148_refresh_chain <- function(state, n_iter = 12000L,
                                                      burn = 2000L, thin = 2L,
                                                      seed = 148L) {
  set.seed(as.integer(seed))
  support <- app_joint_qvp_exal_support(state$tau)
  sigma <- state$sigma
  gamma <- state$gamma
  keep <- seq.int(as.integer(burn) + 1L, as.integer(n_iter), by = as.integer(thin))
  out <- matrix(NA_real_, nrow = length(keep), ncol = 2L, dimnames = list(NULL, c("sigma", "gamma")))
  pos <- 0L
  for (iter in seq_len(as.integer(n_iter))) {
    terms <- app_joint_exqdesn_phase148_sigma_gig_terms(state, gamma)
    sigma <- app_joint_qvp_rgig(
      lambda = terms$lambda,
      chi = terms$chi,
      psi = max(terms$psi, .Machine$double.eps),
      current = sigma
    )[[1L]]
    eta0 <- app_joint_qvp_gamma_to_eta(gamma, support$lower[[1L]], support$upper[[1L]])
    eta <- app_joint_qvp_slice_bounded_one(
      x0 = eta0,
      lower = -12,
      upper = 12,
      width = 2,
      max_steps = 250L,
      log_density = function(x) {
        g <- app_joint_qvp_eta_to_gamma(x, support$lower[[1L]], support$upper[[1L]])
        local_state <- state
        local_state$sigma <- sigma
        app_joint_exqdesn_phase148_gamma_conditional_log_kernel(local_state, g) +
          app_joint_qvp_gamma_logit_jacobian(x, support$lower[[1L]], support$upper[[1L]])
      }
    )
    gamma <- app_joint_qvp_eta_to_gamma(eta, support$lower[[1L]], support$upper[[1L]])
    if (iter %in% keep) {
      pos <- pos + 1L
      out[pos, ] <- c(sigma, gamma)
    }
  }
  out
}

app_joint_exqdesn_phase148_sampler_comparison <- function(
  tau_grid = c(0.10, 0.50, 0.90),
  n_iter = 12000L,
  burn = 2000L,
  thin = 2L
) {
  rows <- list()
  grid_rows <- list()
  for (ii in seq_along(tau_grid)) {
    state <- app_joint_exqdesn_phase148_state(tau_grid[[ii]], seed = 14800L + ii)
    grid <- app_joint_exqdesn_phase148_grid(state)
    truth <- app_joint_exqdesn_phase148_grid_summary(grid, state$tau)
    draws <- app_joint_exqdesn_phase148_refresh_chain(
      state, n_iter = n_iter, burn = burn, thin = thin, seed = 14900L + ii
    )
    rows[[ii]] <- data.frame(
      tau = state$tau,
      sampler = "conditional_refresh",
      n_draws = nrow(draws),
      sigma_mean = mean(draws[, "sigma"]),
      gamma_mean = mean(draws[, "gamma"]),
      grid_sigma_mean = truth$sigma_mean,
      grid_gamma_mean = truth$gamma_mean,
      sigma_mean_abs_error = abs(mean(draws[, "sigma"]) - truth$sigma_mean),
      gamma_mean_abs_error = abs(mean(draws[, "gamma"]) - truth$gamma_mean),
      sigma_standardized_error = abs(mean(draws[, "sigma"]) - truth$sigma_mean) / max(truth$sigma_sd, 1e-12),
      gamma_standardized_error = abs(mean(draws[, "gamma"]) - truth$gamma_mean) / max(truth$gamma_sd, 1e-12),
      stringsAsFactors = FALSE
    )
    grid_rows[[ii]] <- truth
  }
  list(
    grid_summary = do.call(rbind, grid_rows),
    sampler_comparison = do.call(rbind, rows)
  )
}

app_joint_exqdesn_run_phase148_target_invariance <- function(
  out_dir = app_joint_exqdesn_phase148_default_dir(),
  sampler_tau_grid = c(0.10, 0.50, 0.90),
  n_iter = 12000L,
  burn = 2000L,
  thin = 2L,
  identity_tolerance = 1e-7,
  sampler_review_tolerance = 0.20
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  identity <- app_joint_exqdesn_phase148_identity_audit(tolerance = identity_tolerance)
  sampled <- app_joint_exqdesn_phase148_sampler_comparison(
    tau_grid = sampler_tau_grid, n_iter = n_iter, burn = burn, thin = thin
  )
  identity_fail <- any(identity$sigma_identity_status == "fail" | identity$gamma_identity_status == "fail")
  sampler_review <- any(
    sampled$sampler_comparison$sigma_standardized_error > sampler_review_tolerance |
      sampled$sampler_comparison$gamma_standardized_error > sampler_review_tolerance
  )
  assessment <- data.frame(
    audit_id = "phase148_target_invariance",
    gate_status = if (identity_fail) "fail" else if (sampler_review) "review" else "pass",
    identity_rows = nrow(identity),
    identity_failures = sum(identity$sigma_identity_status == "fail") +
      sum(identity$gamma_identity_status == "fail"),
    sampler_rows = nrow(sampled$sampler_comparison),
    max_sigma_standardized_error = max(sampled$sampler_comparison$sigma_standardized_error),
    max_gamma_standardized_error = max(sampled$sampler_comparison$gamma_standardized_error),
    production_sampler_recommendation = if (identity_fail) {
      "block_screening_and_fix_target_implementation"
    } else {
      "conditional_refresh_verified_for_case_specific_screening_and_mcmc_confirmation"
    },
    stringsAsFactors = FALSE
  )
  run_config <- data.frame(
    n_iter = as.integer(n_iter),
    burn = as.integer(burn),
    thin = as.integer(thin),
    sampler_tau_grid = paste(sampler_tau_grid, collapse = ","),
    identity_tolerance = identity_tolerance,
    sampler_review_tolerance = sampler_review_tolerance,
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase148 target-invariance audit",
    "",
    "This is a software-correctness gate, not a model-calibration campaign.",
    "It verifies that the joint sigma-gamma log target agrees with the implemented sigma GIG and gamma slice conditionals up to additive constants.",
    "It also compares the established conditional refresh transition with a normalized fixed-state sigma-gamma grid.",
    "",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Recommendation: `%s`", assessment$production_sampler_recommendation[[1L]])
  ), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    conditional_identity_audit = app_joint_qvp_write_csv(identity, file.path(out_dir, "conditional_identity_audit.csv")),
    exact_grid_posterior_summary = app_joint_qvp_write_csv(sampled$grid_summary, file.path(out_dir, "exact_grid_posterior_summary.csv")),
    sampler_grid_comparison = app_joint_qvp_write_csv(sampled$sampler_comparison, file.path(out_dir, "sampler_grid_comparison.csv")),
    target_invariance_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "target_invariance_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(out_dir = out_dir, assessment = assessment, paths = c(paths, artifact_manifest = manifest_path))
}
