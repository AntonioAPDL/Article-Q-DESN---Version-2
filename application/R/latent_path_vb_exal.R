# Structured exAL VB for the GloFAS Part 4 latent-path model.

app_latent_exal_require_kernels <- function() {
  required <- c(
    "app_joint_qvp_default_gamma",
    "app_joint_qvp_check_gamma",
    "app_joint_qvp_truncnorm_positive_moments",
    "app_joint_exqdesn_point_scale_shape_moments",
    "app_joint_exqdesn_structured_scale_shape_update"
  )
  missing <- required[!vapply(required, exists, logical(1L), mode = "function", inherits = TRUE)]
  if (length(missing)) {
    stop(sprintf("Part 4 exAL kernels are not sourced: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_latent_exal_shift_row_moments <- function(row_moments, response_offset) {
  response_offset <- as.numeric(response_offset)
  n_fixed <- row_moments$fixed$n
  n_y <- row_moments$future$n_y
  n_g <- row_moments$future$n_g
  if (length(response_offset) != n_fixed + n_y + n_g) {
    stop("exAL response offsets are not row aligned.", call. = FALSE)
  }
  out <- row_moments
  out$fixed$z <- out$fixed$z - response_offset[seq_len(n_fixed)]
  y_offset <- response_offset[n_fixed + seq_len(n_y)]
  for (h in seq_len(n_y)) {
    out$future$b_y[[h]] <- out$future$b_y[[h]] - y_offset[[h]] * out$future$H_y[h, ]
  }
  g_offset <- response_offset[n_fixed + n_y + seq_len(n_g)]
  out$future$z_g <- out$future$z_g - g_offset
  out
}

app_latent_exal_working_state <- function(row_moments, latent_inv, s_mean, block_moments) {
  source <- app_latent_all_source(row_moments)
  effective_precision <- response_offset <- numeric(length(source))
  for (src in c("Y", "G")) {
    idx <- which(source == src)
    moments <- block_moments[[src]]
    inv_b_sigma <- as.numeric(moments[["inv_B_sigma_mean"]])
    effective_precision[idx] <- inv_b_sigma * latent_inv[idx]
    response_offset[idx] <-
      as.numeric(moments[["lambda_over_B_mean"]]) / inv_b_sigma * s_mean[idx] +
      as.numeric(moments[["A_inv_B_sigma_mean"]]) /
        pmax(inv_b_sigma * latent_inv[idx], .Machine$double.eps)
  }
  list(
    row_moments = app_latent_exal_shift_row_moments(row_moments, response_offset),
    effective_precision = effective_precision,
    response_offset = response_offset,
    sigma_proxy = list(inv_mean = c(Y = 1, G = 1))
  )
}

app_latent_exal_local_update <- function(row_moments, block_moments, latent_mean, latent_inv, s_mean, s2_mean) {
  source <- app_latent_all_source(row_moments)
  residual <- app_latent_all_e(row_moments)
  residual_second <- app_latent_all_R(row_moments)
  weight <- app_latent_all_weight(row_moments)
  for (src in c("Y", "G")) {
    idx <- which(source == src)
    moments <- block_moments[[src]]
    chi <- as.numeric(moments[["inv_B_sigma_mean"]]) * residual_second[idx] -
      2 * as.numeric(moments[["lambda_over_B_mean"]]) * residual[idx] * s_mean[idx] +
      as.numeric(moments[["sigma_lambda2_over_B_mean"]]) * s2_mean[idx]
    psi <- rep(
      as.numeric(moments[["A2_inv_B_sigma_mean"]]) +
        2 * as.numeric(moments[["sigma_inv_mean"]]),
      length(idx)
    )
    gig <- app_latent_gig_moments(
      lambda = 1 - weight[idx] / 2,
      chi = weight[idx] * pmax(chi, .Machine$double.eps),
      psi = weight[idx] * pmax(psi, .Machine$double.eps)
    )
    latent_mean[idx] <- gig$mean
    latent_inv[idx] <- gig$inv_mean
    s_precision <- weight[idx] * (
      1 + as.numeric(moments[["sigma_lambda2_over_B_mean"]]) * latent_inv[idx]
    )
    s_linear <- weight[idx] * (
      as.numeric(moments[["lambda_over_B_mean"]]) * residual[idx] * latent_inv[idx] -
        as.numeric(moments[["A_lambda_over_B_mean"]])
    )
    truncated <- app_joint_qvp_truncnorm_positive_moments(
      mean = s_linear / s_precision,
      sd = sqrt(1 / s_precision)
    )
    s_mean[idx] <- truncated$mean
    s2_mean[idx] <- truncated$second
  }
  list(latent_mean = latent_mean, latent_inv = latent_inv, s_mean = s_mean, s2_mean = s2_mean)
}

app_latent_exal_scale_shape_update <- function(
  row_moments,
  tau,
  latent_mean,
  latent_inv,
  s_mean,
  s2_mean,
  vb_args
) {
  source <- app_latent_all_source(row_moments)
  residual <- app_latent_all_e(row_moments)
  residual_second <- app_latent_all_R(row_moments)
  weight <- app_latent_all_weight(row_moments)
  out <- list()
  for (src in c("Y", "G")) {
    idx <- which(source == src)
    out[[src]] <- app_joint_exqdesn_structured_scale_shape_update(
      tau = tau,
      augmentation = "v",
      r_mean = residual[idx],
      r2_mean = residual_second[idx],
      latent_mean = latent_mean[idx],
      latent_inv_mean = latent_inv[idx],
      s_mean = s_mean[idx],
      s2_mean = s2_mean[idx],
      a_sigma = as.numeric((vb_args$prior_sigma %||% list())$a %||% 2),
      b_sigma = as.numeric((vb_args$prior_sigma %||% list())$b %||% 1),
      observation_weight = weight[idx],
      quadrature_nodes = as.integer(vb_args$quadrature_nodes %||% c(4L, 8L, 12L)),
      quadrature_tolerance = as.numeric(vb_args$quadrature_tolerance %||% 1.0e-6)
    )
  }
  out
}

app_fit_latent_path_exal_vb_core <- function(design, p0, coefficient_prior = "rhs_ns", vb_args = list(), seed = NULL) {
  app_latent_exal_require_kernels()
  p <- ncol(design$H_fixed)
  horizon <- nrow(design$future_key)
  seed <- as.integer(seed %||% vb_args$seed %||% 20260513L)
  max_iter <- as.integer(vb_args$max_iter %||% 100L)
  min_iter <- as.integer(vb_args$min_iter_elbo %||% vb_args$min_iter %||% 30L)
  tol <- as.numeric(vb_args$tol %||% 0.01)
  n_draws <- as.integer(vb_args$n_draws %||% 500L)
  freeze_beta <- as.integer(vb_args$freeze_beta_warmup_iters %||% 0L)
  min_beta_updates <- as.integer(vb_args$min_beta_updates %||% 1L)
  progress_every <- as.integer(vb_args$progress_every %||% 1L)
  progress_path <- as.character(vb_args$progress_path %||% "")[[1L]]
  profile_substeps <- isTRUE((vb_args$diagnostics %||% list())$profile_substeps %||% FALSE)
  if (max_iter < 1L || min_iter < 1L || min_iter > max_iter || tol <= 0 ||
      freeze_beta < 0L || freeze_beta >= max_iter || freeze_beta + min_beta_updates > max_iter) {
    stop("Invalid exAL latent-path VB controls.", call. = FALSE)
  }
  initial <- app_latent_normal_initial_state(design, vb_args, p, horizon)
  theta_mean <- initial$theta_mean
  theta_cov <- initial$theta_cov
  y_mean <- initial$y_mean
  y_cov <- initial$y_cov
  prior_state <- app_latent_prior_state_init(
    p, coefficient_prior, design$intercept_index, vb_args,
    beta_index = design$beta_index, alpha_index = design$alpha_index
  )
  prior_state <- app_latent_prior_apply_addition(prior_state, vb_args$prior_addition %||% NULL)
  row_moments <- app_latent_row_moments(
    design, y_mean, y_cov, theta_mean, theta_cov,
    profile_substeps = profile_substeps
  )
  source <- app_latent_all_source(row_moments)
  n_rows <- length(source)
  gamma_init <- as.numeric((vb_args$initial_state %||% list())$gamma %||% app_joint_qvp_default_gamma(p0))
  if (length(gamma_init) == 1L) gamma_init <- rep(gamma_init, 2L)
  if (length(gamma_init) != 2L) {
    stop("Part 4 exAL gamma initializer must have length one or two (Y, G).", call. = FALSE)
  }
  gamma <- setNames(vapply(gamma_init, function(x) {
    app_joint_qvp_check_gamma(p0, x)[[1L]]
  }, numeric(1L)), c("Y", "G"))
  sigma_init <- pmax(as.numeric((vb_args$initial_state %||% list())$sigma_mean %||% stats::mad(design$z_fixed)), 1.0e-3)
  if (length(sigma_init) == 1L) sigma_init <- rep(sigma_init, 2L)
  names(sigma_init) <- c("Y", "G")
  block_moments <- lapply(c("Y", "G"), function(src) {
    app_joint_exqdesn_point_scale_shape_moments(p0, gamma[[src]], sigma_init[[src]])
  })
  names(block_moments) <- c("Y", "G")
  latent_mean <- latent_inv <- rep(1, n_rows)
  s_mean <- rep(sqrt(2 / pi), n_rows)
  s2_mean <- rep(1, n_rows)
  trace <- vector("list", max_iter)
  iteration_timing <- vector("list", max_iter)
  quadrature_trace <- list()
  beta_update_count <- 0L
  converged <- FALSE
  started <- Sys.time()

  for (iter in seq_len(max_iter)) {
    timing <- list()
    timed <- function(name, expr) {
      start <- proc.time()[["elapsed"]]
      value <- force(expr)
      timing[[length(timing) + 1L]] <<- data.frame(
        step = name,
        elapsed_seconds = proc.time()[["elapsed"]] - start,
        stringsAsFactors = FALSE
      )
      value
    }
    old <- c(theta_mean, y_mean, unlist(lapply(block_moments, `[[`, "sigma_mean")), gamma)
    beta_updated <- iter > freeze_beta
    working <- timed("working_state", app_latent_exal_working_state(
      row_moments, latent_inv, s_mean, block_moments
    ))
    if (isTRUE(beta_updated)) {
      theta_update <- timed("theta_update", app_latent_update_theta(
        working$row_moments,
        working$effective_precision,
        working$sigma_proxy,
        list(A = 0, B = 1),
        prior_state,
        chunking = vb_args$chunking %||% NULL,
        profile_substeps = profile_substeps
      ))
      theta_mean <- as.numeric(theta_update$mean)
      theta_cov <- theta_update$cov
      beta_update_count <- beta_update_count + 1L
    }
    n_fixed <- row_moments$fixed$n
    n_y <- row_moments$future$n_y
    future_update <- timed("future_update", app_latent_update_future_gaussian_delta(
      row_moments,
      y_mean,
      theta_mean,
      theta_cov,
      working$effective_precision,
      working$sigma_proxy,
      list(A = 0, B = 1),
      response_offset_y = working$response_offset[n_fixed + seq_len(n_y)],
      response_offset_g = working$response_offset[n_fixed + n_y + seq_len(row_moments$future$n_g)]
    ))
    y_mean <- future_update$mean
    y_cov <- future_update$cov
    row_moments <- timed("row_moments", app_latent_row_moments(
      design, y_mean, y_cov, theta_mean, theta_cov,
      profile_substeps = profile_substeps
    ))
    local <- timed("local_update", app_latent_exal_local_update(
      row_moments, block_moments, latent_mean, latent_inv, s_mean, s2_mean
    ))
    latent_mean <- local$latent_mean
    latent_inv <- local$latent_inv
    s_mean <- local$s_mean
    s2_mean <- local$s2_mean
    scale_updates <- timed("scale_shape_update", app_latent_exal_scale_shape_update(
      row_moments, p0, latent_mean, latent_inv, s_mean, s2_mean, vb_args
    ))
    for (src in c("Y", "G")) {
      block_moments[[src]] <- scale_updates[[src]]$moments
      gamma[[src]] <- block_moments[[src]][["gamma_mean"]]
      if (iter == 1L || iter %% 10L == 0L || iter == max_iter) {
        quadrature_trace[[length(quadrature_trace) + 1L]] <- transform(
          scale_updates[[src]]$diagnostics,
          iteration = iter,
          source = src
        )
      }
    }
    prior_state <- timed("prior_update", app_latent_prior_state_update(
      prior_state, theta_mean, theta_cov, iter = iter
    ))
    gate <- app_latent_prior_rhs_gate(prior_state, iter)
    now <- c(theta_mean, y_mean, unlist(lapply(block_moments, `[[`, "sigma_mean")), gamma)
    change <- max(abs(now - old) / pmax(1, abs(old)))
    eligible <- iter >= min_iter && beta_update_count >= min_beta_updates && isTRUE(gate$passed)
    iteration_timing[[iter]] <- transform(do.call(rbind, timing), iteration = iter)
    trace[[iter]] <- data.frame(
      iteration = iter,
      beta_updated = beta_updated,
      beta_update_count = beta_update_count,
      parameter_change = change,
      gamma_Y = gamma[["Y"]],
      gamma_G = gamma[["G"]],
      sigma_Y = block_moments$Y[["sigma_mean"]],
      sigma_G = block_moments$G[["sigma_mean"]],
      convergence_eligible = eligible,
      elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    )
    if (progress_every > 0L && (iter == 1L || iter %% progress_every == 0L || iter == max_iter)) {
      message(sprintf("[Part4 exAL] iteration %d/%d change=%.6g", iter, max_iter, change))
      if (nzchar(progress_path)) {
        app_ensure_dir(dirname(progress_path))
        app_write_csv(do.call(rbind, trace[seq_len(iter)]), progress_path)
      }
    }
    if (isTRUE(eligible) && is.finite(change) && change < tol &&
        all(vapply(scale_updates, function(x) isTRUE(x$converged), logical(1L)))) {
      converged <- TRUE
      trace <- trace[seq_len(iter)]
      break
    }
  }
  trace <- do.call(rbind, trace[vapply(trace, is.data.frame, logical(1L))])
  iteration_timing <- do.call(rbind, iteration_timing[vapply(iteration_timing, is.data.frame, logical(1L))])
  post_fit_timing <- list()
  post_timed <- function(name, expr) {
    start <- proc.time()[["elapsed"]]
    value <- force(expr)
    post_fit_timing[[length(post_fit_timing) + 1L]] <<- data.frame(
      step = name,
      elapsed_seconds = proc.time()[["elapsed"]] - start,
      stringsAsFactors = FALSE
    )
    value
  }
  theta_draws <- post_timed("theta_draw_generation", app_latent_mvn_draws_exact(
    theta_mean, theta_cov, n_draws, seed + 11L, assume_symmetric = TRUE
  ))
  y_draws <- post_timed("future_draw_generation", app_latent_mvn_draws_exact(
    y_mean, y_cov, n_draws, seed + 17L, assume_symmetric = TRUE
  ))
  sigma_draws <- post_timed("sigma_draw_generation", vapply(c("Y", "G"), function(src) {
    mean <- block_moments[[src]][["sigma_mean"]]
    second <- block_moments[[src]][["sigma2_mean"]]
    variance <- pmax(second - mean^2, 1.0e-12)
    log_var <- log1p(variance / mean^2)
    stats::rlnorm(n_draws, log(mean) - log_var / 2, sqrt(log_var))
  }, numeric(n_draws)))
  colnames(sigma_draws) <- c("sigma_Y", "sigma_G")
  colnames(theta_draws) <- colnames(design$H_fixed)
  colnames(y_draws) <- sprintf("y_future_%02d", seq_len(horizon))
  list(
    method = "vb",
    likelihood_family = "exal",
    prior = coefficient_prior,
    summary = list(
      theta_mean = theta_mean,
      theta_cov = theta_cov,
      sigma_mean = vapply(block_moments, `[[`, numeric(1L), "sigma_mean"),
      gamma_mean = gamma,
      y_future_mean = y_mean,
      y_future_cov = y_cov
    ),
    draws = list(theta = theta_draws, sigma = sigma_draws, y_future = y_draws),
    vb_diagnostics = list(
      converged = converged,
      iterations = nrow(trace),
      parameter_change_trace = trace$parameter_change,
      iteration_trace = trace,
      iteration_timing = iteration_timing,
      stage_timing = do.call(rbind, post_fit_timing),
      quadrature_trace = app_bind_rows_fill(quadrature_trace),
      freeze_beta_warmup_iters = freeze_beta,
      beta_update_count = beta_update_count,
      scale_shape_method = "source_partitioned_structured_v_quadrature",
      weighted_local_factor_contract = "fractional_likelihood_complete_data_power",
      ensemble_weight_contract = "each_horizon_sums_to_one",
      future_truth_policy = design$future_truth_policy,
      objective_type = "structured_exal_coordinate_monitor",
      initialization = initial$provenance
    ),
    variational_state = list(
      theta_mean = theta_mean,
      theta_cov = theta_cov,
      y_future_mean = y_mean,
      y_future_cov = y_cov,
      gamma = gamma,
      block_moments = block_moments,
      latent_mean = latent_mean,
      latent_inv_mean = latent_inv,
      s_mean = s_mean,
      s2_mean = s2_mean,
      prior = prior_state,
      future_linearization = app_latent_extract_future_linearization(row_moments, design)
    )
  )
}
