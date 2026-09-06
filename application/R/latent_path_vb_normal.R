# Normal VB for the GloFAS Part 4 latent-path ensemble-likelihood model.

app_latent_normal_sigma_update <- function(row_moments, prior_sigma = list(a = 2, b = 1)) {
  source <- app_latent_all_source(row_moments)
  residual_second <- app_latent_all_R(row_moments)
  weight <- app_latent_all_weight(row_moments)
  a0 <- as.numeric(prior_sigma$a %||% 2)
  b0 <- as.numeric(prior_sigma$b %||% 1)
  shape <- rate <- setNames(numeric(2L), c("Y", "G"))
  for (src in names(shape)) {
    idx <- which(source == src)
    shape[[src]] <- a0 + 0.5 * sum(weight[idx])
    rate[[src]] <- b0 + 0.5 * sum(weight[idx] * residual_second[idx])
  }
  app_latent_ig_expectations(shape, pmax(rate, 1.0e-12))
}

app_latent_normal_objective <- function(row_moments, sigma_state, theta_mean, theta_cov, prior_state) {
  source <- app_latent_all_source(row_moments)
  residual_second <- app_latent_all_R(row_moments)
  weight <- app_latent_all_weight(row_moments)
  value <- 0
  for (src in c("Y", "G")) {
    idx <- which(source == src)
    if (!length(idx)) next
    value <- value - 0.5 * sum(weight[idx] * (
      sigma_state$log_mean[[src]] + sigma_state$inv_mean[[src]] * residual_second[idx]
    ))
  }
  theta_second <- theta_mean^2 + diag(theta_cov)
  value - 0.5 * sum(prior_state$prior_precision * theta_second) +
    sum(as.numeric(prior_state$prior_linear %||% numeric(length(theta_mean))) * theta_mean)
}

app_latent_normal_initial_state <- function(design, vb_args, p, horizon) {
  state <- vb_args$initial_state %||% list()
  theta_mean <- as.numeric(state$theta_mean %||% rep(0, p))
  theta_cov <- as.matrix(state$theta_cov %||% diag(1, p))
  y_mean <- as.numeric(state$y_future_mean %||% design$y_future_init)
  y_cov <- as.matrix(state$y_future_cov %||% diag(max(stats::var(design$z_fixed), 1.0e-3), horizon))
  if (length(theta_mean) != p || !identical(dim(theta_cov), c(p, p))) {
    stop("Normal latent-path coefficient initializer has incompatible dimensions.", call. = FALSE)
  }
  if (length(y_mean) != horizon || !identical(dim(y_cov), c(horizon, horizon))) {
    stop("Normal latent-path future initializer has incompatible dimensions.", call. = FALSE)
  }
  if (any(!is.finite(c(theta_mean, theta_cov, y_mean, y_cov)))) {
    stop("Normal latent-path initializer must be finite.", call. = FALSE)
  }
  list(
    theta_mean = theta_mean,
    theta_cov = (theta_cov + t(theta_cov)) / 2,
    y_mean = y_mean,
    y_cov = (y_cov + t(y_cov)) / 2,
    provenance = state$provenance %||% list(type = if (length(state)) "explicit" else "cold")
  )
}

app_fit_latent_path_normal_vb_core <- function(
  design,
  coefficient_prior = c("ridge", "rhs_ns"),
  vb_args = list(),
  seed = NULL
) {
  coefficient_prior <- match.arg(coefficient_prior)
  p <- ncol(design$H_fixed)
  horizon <- nrow(design$future_key)
  seed <- as.integer(seed %||% vb_args$seed %||% 20260513L)
  max_iter <- as.integer(vb_args$max_iter %||% 100L)
  min_iter <- as.integer(vb_args$min_iter_elbo %||% vb_args$min_iter %||% 30L)
  tol <- as.numeric(vb_args$tol %||% 1.0e-4)
  n_draws <- as.integer(vb_args$n_draws %||% 500L)
  freeze_beta <- as.integer(vb_args$freeze_beta_warmup_iters %||% 0L)
  min_beta_updates <- as.integer(vb_args$min_beta_updates %||% 1L)
  progress_every <- as.integer(vb_args$progress_every %||% 1L)
  progress_path <- as.character(vb_args$progress_path %||% "")[[1L]]
  if (max_iter < 1L || min_iter < 1L || min_iter > max_iter || tol < 0 ||
      freeze_beta < 0L || freeze_beta >= max_iter || min_beta_updates < 1L ||
      freeze_beta + min_beta_updates > max_iter || n_draws < 1L) {
    stop("Invalid Normal latent-path VB controls.", call. = FALSE)
  }
  initial <- app_latent_normal_initial_state(design, vb_args, p, horizon)
  theta_mean <- initial$theta_mean
  theta_cov <- initial$theta_cov
  y_mean <- initial$y_mean
  y_cov <- initial$y_cov
  prior_state <- app_latent_prior_state_init(
    p = p,
    prior = coefficient_prior,
    intercept_index = design$intercept_index,
    vb_args = vb_args,
    beta_index = design$beta_index,
    alpha_index = design$alpha_index
  )
  prior_state <- app_latent_prior_apply_addition(prior_state, vb_args$prior_addition %||% NULL)
  row_moments <- app_latent_row_moments(
    design, y_mean, y_cov, theta_mean, theta_cov, strategy = "streamed_grouped"
  )
  sigma_state <- app_latent_normal_sigma_update(row_moments, vb_args$prior_sigma)
  constants <- list(A = 0, B = 1)
  trace <- vector("list", max_iter)
  started <- Sys.time()
  converged <- FALSE
  beta_update_count <- 0L
  repaired <- FALSE

  for (iter in seq_len(max_iter)) {
    old <- c(theta_mean, y_mean, sigma_state$inv_mean)
    beta_updated <- iter > freeze_beta
    if (isTRUE(beta_updated)) {
      update <- app_latent_update_theta(
        row_moments = row_moments,
        e_inv_v = rep(1, length(app_latent_all_R(row_moments))),
        sigma_state = sigma_state,
        constants = constants,
        prior_state = prior_state,
        chunking = vb_args$chunking %||% NULL
      )
      theta_mean <- as.numeric(update$mean)
      theta_cov <- (update$cov + t(update$cov)) / 2
      repaired <- repaired || isTRUE(update$repaired)
      beta_update_count <- beta_update_count + 1L
    }
    future_update <- app_latent_update_future_gaussian_delta(
      row_moments = row_moments,
      y_start = y_mean,
      theta_mean = theta_mean,
      theta_cov = theta_cov,
      e_inv_v = rep(1, length(app_latent_all_R(row_moments))),
      sigma_state = sigma_state,
      constants = constants
    )
    y_mean <- future_update$mean
    y_cov <- future_update$cov
    row_moments <- app_latent_row_moments(
      design, y_mean, y_cov, theta_mean, theta_cov, strategy = "streamed_grouped"
    )
    sigma_state <- app_latent_normal_sigma_update(row_moments, vb_args$prior_sigma)
    prior_state <- app_latent_prior_state_update(prior_state, theta_mean, theta_cov, iter = iter)
    rhs_gate <- app_latent_prior_rhs_gate(prior_state, iter)
    current <- c(theta_mean, y_mean, sigma_state$inv_mean)
    change <- max(abs(current - old) / pmax(1, abs(old)))
    objective <- app_latent_normal_objective(row_moments, sigma_state, theta_mean, theta_cov, prior_state)
    eligible <- iter >= min_iter && beta_update_count >= min_beta_updates && isTRUE(rhs_gate$passed)
    trace[[iter]] <- data.frame(
      iteration = iter,
      beta_updated = beta_updated,
      beta_update_count = beta_update_count,
      parameter_change = change,
      objective = objective,
      convergence_eligible = eligible,
      elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    )
    if (progress_every > 0L && (iter == 1L || iter %% progress_every == 0L || iter == max_iter)) {
      message(sprintf("[Part4 Normal %s] iteration %d/%d change=%.6g", coefficient_prior, iter, max_iter, change))
      if (nzchar(progress_path)) {
        app_ensure_dir(dirname(progress_path))
        app_write_csv(do.call(rbind, trace[seq_len(iter)]), progress_path)
      }
    }
    if (isTRUE(eligible) && is.finite(change) && change < tol) {
      converged <- TRUE
      trace <- trace[seq_len(iter)]
      break
    }
  }
  trace <- do.call(rbind, trace[vapply(trace, is.data.frame, logical(1L))])
  set.seed(seed)
  theta_draws <- app_latent_mvn_draws_exact(theta_mean, theta_cov, n_draws, seed + 11L)
  y_draws <- app_latent_mvn_draws_exact(y_mean, y_cov, n_draws, seed + 17L)
  sigma_draws <- cbind(
    sigma_Y = 1 / stats::rgamma(n_draws, sigma_state$shape[["Y"]], sigma_state$rate[["Y"]]),
    sigma_G = 1 / stats::rgamma(n_draws, sigma_state$shape[["G"]], sigma_state$rate[["G"]])
  )
  colnames(theta_draws) <- colnames(design$H_fixed)
  colnames(y_draws) <- sprintf("y_future_%02d", seq_len(horizon))
  list(
    method = "vb",
    likelihood_family = "normal",
    prior = coefficient_prior,
    summary = list(
      theta_mean = theta_mean,
      theta_cov = theta_cov,
      sigma_mean = sigma_state$mean,
      y_future_mean = y_mean,
      y_future_cov = y_cov
    ),
    draws = list(theta = theta_draws, sigma = sigma_draws, y_future = y_draws),
    vb_diagnostics = list(
      converged = converged,
      iterations = nrow(trace),
      objective_trace = trace$objective,
      parameter_change_trace = trace$parameter_change,
      freeze_beta_warmup_iters = freeze_beta,
      beta_update_count = beta_update_count,
      coefficient_precision_repaired = repaired,
      ensemble_weight_contract = "each_horizon_sums_to_one",
      future_truth_policy = design$future_truth_policy,
      initialization = initial$provenance,
      iteration_trace = trace,
      objective_type = "normal_mean_field_expected_log_joint"
    ),
    variational_state = list(
      theta_mean = theta_mean,
      theta_cov = theta_cov,
      y_future_mean = y_mean,
      y_future_cov = y_cov,
      sigma = sigma_state,
      prior = prior_state,
      future_linearization = app_latent_extract_future_linearization(row_moments, design)
    )
  )
}
