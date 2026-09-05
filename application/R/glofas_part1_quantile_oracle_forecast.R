# Oracle-realized Part 1 quantile forecasts for the GloFAS Normal-DESN ladder.
#
# These helpers reuse the selected Part 1 DESN design and fit AL/exAL RHS-VB
# quantile readouts on USGS history through the cutoff. Forecasts are recursive
# quantile paths that use realized retrospective ppt/soil covariates after the
# origin for diagnostics only. They do not run quantile synthesis.

app_glofas_part1_quantile_grid <- function() {
  c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
}

app_glofas_part1_quantile_slug <- function(tau) {
  paste0("q", gsub("\\.", "p", sprintf("%.2f", as.numeric(tau))))
}

app_glofas_part1_quantile_check_loss <- function(y, q, tau) {
  if (exists("app_check_loss", mode = "function", inherits = TRUE)) {
    return(app_check_loss(y, q, tau))
  }
  u <- as.numeric(y) - as.numeric(q)
  ifelse(u >= 0, as.numeric(tau) * u, (as.numeric(tau) - 1) * u)
}

app_glofas_part1_quantile_model_families <- function() {
  data.frame(
    model_family = c("independent_al", "independent_exal", "joint_al", "joint_exal"),
    likelihood = c("AL", "exAL", "AL", "exAL"),
    fit_structure = c("independent_single_tau", "independent_single_tau", "joint_all_tau", "joint_all_tau"),
    inference = c("VB-RHS", "VB-LD-RHS-structured-scale", "VB-RHS", "VB-LD-RHS-structured-scale"),
    synthesis = FALSE,
    stringsAsFactors = FALSE
  )
}

app_glofas_part1_quantile_prepare_design <- function(
  base_cfg,
  candidate_row = NULL,
  origin_date = NULL,
  horizon_days = NULL,
  target = "usgs",
  root_candidates = NULL
) {
  candidate_row <- candidate_row %||% app_glofas_oracle_default_part1_winner_row()
  candidate_row <- app_glofas_oracle_complete_part1_candidate_row(candidate_row)
  bundle <- app_glofas_oracle_prepare_panel_bundle(
    cfg = base_cfg,
    origin_date = origin_date,
    horizon_days = horizon_days,
    target = target,
    root_candidates = root_candidates
  )
  design <- app_glofas_oracle_build_part1_design(
    base_cfg = base_cfg,
    candidate_row = candidate_row,
    panel_bundle = bundle
  )
  if (!identical(colnames(design$X)[[1L]], "readout_intercept")) {
    stop("Part 1 quantile design expects a leading readout_intercept column.", call. = FALSE)
  }
  Z <- as.matrix(design$X[, -1L, drop = FALSE])
  storage.mode(Z) <- "double"
  list(
    candidate_row = candidate_row,
    bundle = bundle,
    design = design,
    Z = Z
  )
}

app_glofas_part1_quantile_default_controls <- function(
  max_iter = 100L,
  tol = 0,
  min_iter = 1L,
  tau0 = NULL,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = Inf,
  max_dense_dim = 4000L,
  rhs_vb_inner = 5L,
  exal_method_id = "VB1_structured_v",
  exal_prefit_max_iter = 25L,
  joint_backend = "auto",
  init = NULL,
  init_fit_path = NULL,
  init_fit_paths = NULL,
  progress_path = NULL,
  progress_every = 0L
) {
  list(
    max_iter = as.integer(max_iter),
    tol = as.numeric(tol),
    min_iter = as.integer(min_iter),
    tau0 = tau0,
    zeta2 = as.numeric(zeta2),
    a_sigma = as.numeric(a_sigma),
    b_sigma = as.numeric(b_sigma),
    alpha_prior_sd = alpha_prior_sd,
    max_dense_dim = max_dense_dim,
    rhs_vb_inner = as.integer(rhs_vb_inner),
    exal_method_id = as.character(exal_method_id),
    exal_prefit_max_iter = as.integer(exal_prefit_max_iter),
    joint_backend = as.character(joint_backend),
    init = init,
    init_fit_path = init_fit_path,
    init_fit_paths = init_fit_paths,
    progress_path = progress_path,
    progress_every = as.integer(progress_every)
  )
}

app_glofas_part1_quantile_split_paths <- function(paths) {
  if (is.null(paths) || !length(paths)) return(character())
  paths <- unlist(strsplit(as.character(paths), "[,;|]"), use.names = FALSE)
  paths <- trimws(paths)
  paths[nzchar(paths)]
}

app_glofas_part1_quantile_sigma_from_fit <- function(fit, y, residual = NULL) {
  out <- fit$sigma_mean %||% fit$sigma %||% NULL
  if (is.null(out) && !is.null(fit$sigma2_mean)) out <- sqrt(pmax(as.numeric(fit$sigma2_mean), .Machine$double.eps))
  if (is.null(out) && !is.null(fit$sigma_a) && !is.null(fit$sigma_b)) {
    out <- sqrt(pmax(as.numeric(fit$sigma_b) / pmax(as.numeric(fit$sigma_a) - 1, .Machine$double.eps), .Machine$double.eps))
  }
  if (is.null(out)) {
    residual <- residual %||% (as.numeric(y) - mean(as.numeric(y), na.rm = TRUE))
    out <- stats::mad(residual, na.rm = TRUE)
  }
  out <- as.numeric(out)
  out[!is.finite(out) | out <= 0] <- max(stats::mad(as.numeric(y), na.rm = TRUE), 1.0e-3)
  out
}

app_glofas_part1_quantile_init_from_fit <- function(fit, y, Z, tau, source_path = NA_character_) {
  y <- as.numeric(y)
  Z <- as.matrix(Z)
  tau <- as.numeric(tau)
  K <- length(tau)
  p <- ncol(Z)
  beta <- as.numeric(fit$beta_mean %||% fit$beta %||% numeric())
  if (!length(beta)) stop(sprintf("Warm-start fit has no beta_mean: %s", source_path), call. = FALSE)
  if (length(beta) == p + 1L) {
    beta_no_intercept <- beta[-1L]
    residual <- as.numeric(y - Z %*% beta_no_intercept)
    alpha <- as.numeric(stats::quantile(residual, probs = tau, names = FALSE, type = 8))
    beta_out <- rep(beta_no_intercept, times = K)
    sigma <- rep(app_glofas_part1_quantile_sigma_from_fit(fit, y, residual), length.out = K)
  } else if (length(beta) == p) {
    beta_no_intercept <- beta
    residual <- as.numeric(y - Z %*% beta_no_intercept)
    source_tau <- as.numeric(fit$tau %||% NA_real_)
    source_tau_matches <- length(source_tau) == K &&
      all(is.finite(source_tau)) &&
      max(abs(source_tau - tau)) < 1.0e-12
    alpha <- if (source_tau_matches) {
      as.numeric(fit$alpha_mean %||% fit$alpha %||%
        stats::quantile(residual, probs = tau, names = FALSE, type = 8))
    } else {
      alpha <- as.numeric(stats::quantile(residual, probs = tau, names = FALSE, type = 8))
    }
    if (length(alpha) != K) {
      alpha <- as.numeric(stats::quantile(residual, probs = tau, names = FALSE, type = 8))
    }
    beta_out <- if (K == 1L) beta_no_intercept else rep(beta_no_intercept, times = K)
    sigma <- rep(app_glofas_part1_quantile_sigma_from_fit(fit, y, residual), length.out = K)
  } else if (length(beta) == K * p) {
    beta_out <- beta
    beta_mat <- app_joint_qvp_beta_matrix(beta, K, p)
    residual <- y - rowMeans(Z %*% beta_mat)
    source_tau <- as.numeric(fit$tau %||% NA_real_)
    source_tau_matches <- length(source_tau) == K &&
      all(is.finite(source_tau)) &&
      max(abs(source_tau - tau)) < 1.0e-12
    alpha <- if (source_tau_matches) {
      as.numeric(fit$alpha_mean %||% fit$alpha %||%
        stats::quantile(y, probs = tau, names = FALSE, type = 8))
    } else {
      as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8))
    }
    if (length(alpha) != K) alpha <- as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8))
    sigma <- rep(app_glofas_part1_quantile_sigma_from_fit(fit, y, residual), length.out = K)
  } else {
    stop(
      sprintf("Warm-start beta length %d is incompatible with target p=%d, K=%d: %s", length(beta), p, K, source_path),
      call. = FALSE
    )
  }
  out <- list(
    beta_mean = as.numeric(beta_out),
    alpha_mean = as.numeric(alpha),
    sigma_mean = as.numeric(sigma),
    init_source_path = as.character(source_path),
    init_source_class = paste(class(fit), collapse = ";")
  )
  if (!is.null(fit$gamma_mean) || !is.null(fit$gamma)) {
    gamma <- as.numeric(fit$gamma_mean %||% fit$gamma)
    if (length(gamma) == K) out$gamma_mean <- gamma
  }
  out
}

app_glofas_part1_quantile_init_from_paths <- function(paths, y, Z, tau) {
  paths <- app_glofas_part1_quantile_split_paths(paths)
  if (!length(paths)) return(NULL)
  tau <- as.numeric(tau)
  if (length(paths) == 1L) {
    path <- app_glofas_oracle_resolve_repo_path(paths[[1L]], must_work = TRUE)
    return(app_glofas_part1_quantile_init_from_fit(readRDS(path), y = y, Z = Z, tau = tau, source_path = path))
  }
  if (length(paths) != length(tau)) {
    stop("Multiple warm-start paths must have length one or length(tau).", call. = FALSE)
  }
  pieces <- vector("list", length(tau))
  for (ii in seq_along(paths)) {
    path <- app_glofas_oracle_resolve_repo_path(paths[[ii]], must_work = TRUE)
    pieces[[ii]] <- app_glofas_part1_quantile_init_from_fit(readRDS(path), y = y, Z = Z, tau = tau[[ii]], source_path = path)
  }
  out <- list(
    beta_mean = unlist(lapply(pieces, `[[`, "beta_mean"), use.names = FALSE),
    alpha_mean = vapply(pieces, function(x) x$alpha_mean[[1L]], numeric(1L)),
    sigma_mean = vapply(pieces, function(x) x$sigma_mean[[1L]], numeric(1L)),
    init_source_path = paste(paths, collapse = "|"),
    init_source_class = paste(vapply(pieces, function(x) x$init_source_class[[1L]], character(1L)), collapse = "|")
  )
  if (all(vapply(pieces, function(x) !is.null(x$gamma_mean), logical(1L)))) {
    out$gamma_mean <- vapply(pieces, function(x) x$gamma_mean[[1L]], numeric(1L))
  }
  out
}

app_glofas_part1_quantile_resolve_init <- function(controls, y, Z, tau) {
  if (!is.null(controls$init)) return(controls$init)
  paths <- app_glofas_part1_quantile_split_paths(controls$init_fit_paths)
  if (!length(paths)) paths <- app_glofas_part1_quantile_split_paths(controls$init_fit_path)
  app_glofas_part1_quantile_init_from_paths(paths, y = y, Z = Z, tau = tau)
}

app_glofas_part1_quantile_prior_precisions <- function(rhs_state, K, p) {
  prior_state <- app_joint_qvp_rhs_state_to_prior(rhs_state)
  anchor <- app_joint_qvp_rhs_ns_precision(
    lambda2 = prior_state$anchor$lambda2 %||% rep(1, p),
    tau2 = prior_state$anchor$tau2 %||% 1,
    zeta2 = prior_state$anchor$zeta2 %||% Inf,
    p = p
  )
  deltas <- vector("list", max(0L, K - 1L))
  if (K > 1L) {
    for (kk in 2:K) {
      block <- prior_state$innovations[[paste0("delta_", kk)]] %||%
        prior_state$innovations[[kk - 1L]] %||%
        list(lambda2 = rep(1, p), tau2 = 1, zeta2 = Inf)
      deltas[[kk - 1L]] <- app_joint_qvp_rhs_ns_precision(
        lambda2 = block$lambda2 %||% rep(1, p),
        tau2 = block$tau2 %||% 1,
        zeta2 = block$zeta2 %||% Inf,
        p = p
      )
    }
  }
  list(anchor = anchor, deltas = deltas)
}

app_glofas_part1_quantile_prior_terms <- function(rhs_state, beta_mat, K, p) {
  prec <- app_glofas_part1_quantile_prior_precisions(rhs_state, K, p)
  diag_terms <- vector("list", K)
  linear_terms <- vector("list", K)
  for (kk in seq_len(K)) {
    d <- rep(0, p)
    l <- rep(0, p)
    if (kk == 1L) {
      d <- d + prec$anchor
      if (K > 1L) {
        d <- d + prec$deltas[[1L]]
        l <- l + prec$deltas[[1L]] * beta_mat[, 2L]
      }
    } else if (kk == K) {
      d <- d + prec$deltas[[K - 1L]]
      l <- l + prec$deltas[[K - 1L]] * beta_mat[, K - 1L]
    } else {
      d <- d + prec$deltas[[kk - 1L]] + prec$deltas[[kk]]
      l <- l + prec$deltas[[kk - 1L]] * beta_mat[, kk - 1L] +
        prec$deltas[[kk]] * beta_mat[, kk + 1L]
    }
    diag_terms[[kk]] <- pmax(as.numeric(d), .Machine$double.eps)
    linear_terms[[kk]] <- as.numeric(l)
  }
  list(diag = diag_terms, linear = linear_terms)
}

app_glofas_part1_quantile_solve_block <- function(Z, weight, linear, prior_diag, prior_linear) {
  Z <- as.matrix(Z)
  weight <- pmax(as.numeric(weight), .Machine$double.eps)
  p <- ncol(Z)
  zw <- Z * sqrt(weight)
  precision <- crossprod(zw) + diag(pmax(as.numeric(prior_diag), .Machine$double.eps), nrow = p)
  rhs <- as.numeric(crossprod(Z, as.numeric(linear))) + as.numeric(prior_linear)
  jitter <- 0
  for (attempt in 0:6) {
    precision_try <- if (jitter > 0) precision + diag(jitter, p) else precision
    chol_try <- tryCatch(chol(precision_try), error = function(e) NULL)
    if (!is.null(chol_try)) {
      beta <- backsolve(chol_try, forwardsolve(t(chol_try), rhs))
      cov <- chol2inv(chol_try)
      return(list(beta = as.numeric(beta), cov = cov, cov_diag = pmax(diag(cov), 0), jitter = jitter))
    }
    jitter <- if (jitter == 0) 1.0e-8 else jitter * 10
  }
  stop("Block mean-field quantile solve failed even after jitter.", call. = FALSE)
}

app_glofas_part1_quantile_update_rhs_blockmf <- function(rhs_state, beta_mat, cov_diag, K, p, n_inner) {
  theta_second <- vector("list", K)
  theta_second[[1L]] <- beta_mat[, 1L]^2 + cov_diag[[1L]]
  if (K > 1L) {
    for (kk in 2:K) {
      theta_second[[kk]] <- (beta_mat[, kk] - beta_mat[, kk - 1L])^2 +
        cov_diag[[kk]] + cov_diag[[kk - 1L]]
    }
  }
  rhs_state$anchor <- app_joint_qvp_update_rhs_vb_block(rhs_state$anchor, theta_second[[1L]], n_inner = n_inner)
  if (K > 1L) {
    for (kk in 2:K) {
      rhs_state[[paste0("delta_", kk)]] <- app_joint_qvp_update_rhs_vb_block(
        rhs_state[[paste0("delta_", kk)]],
        theta_second[[kk]],
        n_inner = n_inner
      )
    }
  }
  rhs_state
}

app_glofas_part1_quantile_fit_al_blockmf <- function(
  y,
  Z,
  tau,
  max_iter,
  tol,
  min_iter,
  tau0,
  zeta2,
  a_sigma,
  b_sigma,
  alpha_prior_sd,
  rhs_vb_inner,
  init = NULL,
  progress_path = NULL,
  progress_every = 0L,
  progress_label = "joint_al_blockmf"
) {
  y <- as.numeric(y)
  Z <- as.matrix(Z)
  storage.mode(Z) <- "double"
  tau <- as.numeric(tau)
  K <- length(tau)
  p <- ncol(Z)
  Tn <- length(y)
  constants <- app_joint_qvp_al_constants(tau)
  alpha_prior <- app_joint_qvp_alpha_prior_spec(y, tau, "empirical_quantile", alpha_prior_sd)
  init <- app_joint_qvp_normalize_init(init, K, p)
  beta_mat <- if (!is.null(init$beta)) app_joint_qvp_beta_matrix(init$beta, K, p) else matrix(0, p, K)
  alpha <- init$alpha %||% sort(as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8)))
  sigma_shape <- rep(a_sigma + 1.5 * Tn, K)
  sigma_rate <- rep(b_sigma + max(stats::var(y), 1.0e-3), K)
  if (!is.null(init$sigma)) sigma_rate <- pmax(init$sigma * pmax(sigma_shape - 1, .Machine$double.eps), .Machine$double.eps)
  v_mean <- matrix(1, Tn, K)
  v_inv_mean <- matrix(1, Tn, K)
  rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = tau0, zeta2 = zeta2)
  trace <- vector("list", max_iter)
  sigma_trace <- matrix(NA_real_, max_iter, K)
  colnames(sigma_trace) <- paste0("tau_", format(tau, trim = TRUE))
  converged <- FALSE
  for (iter in seq_len(max_iter)) {
    beta_old <- beta_mat
    sigma_old <- sigma_rate / pmax(sigma_shape - 1, .Machine$double.eps)
    prior_terms <- app_glofas_part1_quantile_prior_terms(rhs_state, beta_mat, K, p)
    beta_var <- vector("list", K)
    cov_diag <- vector("list", K)
    jitter_max <- 0
    sigma_inv <- sigma_shape / sigma_rate
    for (kk in seq_len(K)) {
      w <- sigma_inv[[kk]] * v_inv_mean[, kk] / constants$B[[kk]]
      linear <- sigma_inv[[kk]] / constants$B[[kk]] *
        (v_inv_mean[, kk] * (y - alpha[[kk]]) - constants$A[[kk]])
      solved <- app_glofas_part1_quantile_solve_block(
        Z = Z,
        weight = w,
        linear = linear,
        prior_diag = prior_terms$diag[[kk]],
        prior_linear = prior_terms$linear[[kk]]
      )
      beta_mat[, kk] <- solved$beta
      beta_var[[kk]] <- rowSums((Z %*% solved$cov) * Z)
      cov_diag[[kk]] <- solved$cov_diag
      jitter_max <- max(jitter_max, solved$jitter)
    }
    fitted_no_alpha <- Z %*% beta_mat
    for (kk in seq_len(K)) {
      w <- sigma_inv[[kk]] * v_inv_mean[, kk] / constants$B[[kk]]
      cA <- sigma_inv[[kk]] * constants$A[[kk]] / constants$B[[kk]]
      prior_prec <- alpha_prior$precision[[kk]]
      mean_alpha <- (sum(w * (y - fitted_no_alpha[, kk]) - cA) +
        prior_prec * alpha_prior$mean[[kk]]) / (sum(w) + prior_prec)
      lower <- if (kk == 1L) -Inf else alpha[[kk - 1L]]
      upper <- if (kk == K) Inf else alpha[[kk + 1L]]
      alpha[[kk]] <- min(max(mean_alpha, lower), upper)
    }
    for (kk in seq_len(K)) {
      r_mean <- y - alpha[[kk]] - fitted_no_alpha[, kk]
      r2_mean <- r_mean^2 + beta_var[[kk]]
      chi <- sigma_inv[[kk]] * r2_mean / constants$B[[kk]]
      psi <- sigma_inv[[kk]] * (constants$A[[kk]]^2 / constants$B[[kk]] + 2)
      v_mean[, kk] <- app_joint_qvp_gig_moment(0.5, chi, psi, 1)
      v_inv_mean[, kk] <- app_joint_qvp_gig_moment(0.5, chi, psi, -1)
      sigma_rate[[kk]] <- b_sigma + (
        sum(v_mean[, kk]) +
          0.5 / constants$B[[kk]] * sum(r2_mean * v_inv_mean[, kk] -
            2 * constants$A[[kk]] * r_mean + constants$A[[kk]]^2 * v_mean[, kk])
      )
    }
    rhs_state <- app_glofas_part1_quantile_update_rhs_blockmf(rhs_state, beta_mat, cov_diag, K, p, rhs_vb_inner)
    rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_state, K, p)
    sigma_mean <- sigma_rate / pmax(sigma_shape - 1, .Machine$double.eps)
    sigma_trace[iter, ] <- sigma_mean
    max_beta_change <- max(abs(beta_mat - beta_old))
    max_sigma_change <- max(abs(sigma_mean - sigma_old))
    trace[[iter]] <- data.frame(
      iter = iter,
      max_beta_change = max_beta_change,
      max_sigma_change = max_sigma_change,
      max_jitter = jitter_max,
      rhs_mean_precision = mean(rhs_summary$mean_precision),
      rhs_max_precision = max(rhs_summary$max_precision),
      monitor = -sum((y - rowMeans(fitted_no_alpha + matrix(alpha, Tn, K, byrow = TRUE)))^2),
      backend = "block_mean_field",
      stringsAsFactors = FALSE
    )
    if (progress_every > 0L && (iter == 1L || iter == max_iter || iter %% progress_every == 0L)) {
      app_joint_qvp_progress_append(progress_path, transform(trace[[iter]], label = progress_label, max_iter = max_iter, min_iter = min_iter, converged = FALSE, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
    }
    if (iter >= min_iter && max(max_beta_change, max_sigma_change) < tol) {
      converged <- TRUE
      trace <- trace[seq_len(iter)]
      sigma_trace <- sigma_trace[seq_len(iter), , drop = FALSE]
      if (progress_every > 0L) {
        app_joint_qvp_progress_append(progress_path, transform(trace[[iter]], label = progress_label, max_iter = max_iter, min_iter = min_iter, converged = TRUE, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
      }
      break
    }
  }
  qhat_mean <- Z %*% beta_mat + matrix(alpha, Tn, K, byrow = TRUE)
  out <- list(
    beta_mean = as.numeric(beta_mat),
    beta_cov = NULL,
    beta_covariance_approximation = "block_mean_field_by_tau",
    alpha_mean = alpha,
    sigma_mean = sigma_rate / pmax(sigma_shape - 1, .Machine$double.eps),
    sigma_shape = sigma_shape,
    sigma_rate = sigma_rate,
    rhs_state = rhs_state,
    rhs_prior_summary = app_joint_qvp_rhs_vb_summary(rhs_state, K, p),
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    trace = do.call(rbind, trace),
    sigma_trace = sigma_trace,
    converged = converged,
    tau = tau,
    kappa = 1,
    monitor_label = "al_vb_block_mean_field_coordinate_monitor",
    backend = "joint_al_block_mean_field_rhs_vb",
    manifest = app_joint_qvp_manifest_row(
      fit_id = sprintf("glofas_joint_al_blockmf_%s", format(Sys.time(), "%Y%m%d%H%M%S")),
      tau = tau,
      kappa = 1,
      likelihood = "al",
      inference = "vb_block_mean_field",
      seed = NA_integer_,
      status = if (converged) "prototype_success" else "prototype_max_iter"
    )
  )
  class(out) <- c("joint_qvp_qdesn_vb_fit", "list")
  out
}

app_glofas_part1_quantile_fit_exal_blockmf <- function(
  y,
  Z,
  tau,
  max_iter,
  tol,
  min_iter,
  tau0,
  zeta2,
  a_sigma,
  b_sigma,
  alpha_prior_sd,
  rhs_vb_inner,
  init = NULL,
  progress_path = NULL,
  progress_every = 0L,
  progress_label = "joint_exal_blockmf"
) {
  y <- as.numeric(y)
  Z <- as.matrix(Z)
  storage.mode(Z) <- "double"
  tau <- as.numeric(tau)
  K <- length(tau)
  p <- ncol(Z)
  Tn <- length(y)
  init <- app_joint_qvp_normalize_init(init, K, p)
  gamma <- init$gamma %||% app_joint_qvp_default_gamma(tau)
  gamma <- app_joint_qvp_check_gamma(tau, gamma)
  support <- app_joint_qvp_exal_support(tau)
  alpha_prior <- app_joint_qvp_alpha_prior_spec(y, tau, "empirical_quantile", alpha_prior_sd)
  beta_mat <- if (!is.null(init$beta)) app_joint_qvp_beta_matrix(init$beta, K, p) else matrix(0, p, K)
  alpha <- init$alpha %||% sort(as.numeric(stats::quantile(y, tau, names = FALSE, type = 8)))
  sigma_mean <- init$sigma %||% rep(max(stats::mad(y), 1.0e-3), K)
  sigma_inv_mean <- 1 / sigma_mean
  v_mean <- matrix(1, Tn, K)
  v_inv_mean <- matrix(1, Tn, K)
  s_mean <- matrix(sqrt(2 / pi), Tn, K)
  s2_mean <- matrix(1, Tn, K)
  rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = tau0, zeta2 = zeta2)
  trace <- vector("list", max_iter)
  gamma_trace <- matrix(NA_real_, max_iter, K)
  sigma_trace <- matrix(NA_real_, max_iter, K)
  colnames(gamma_trace) <- colnames(sigma_trace) <- paste0("tau_", format(tau, trim = TRUE))
  converged <- FALSE
  for (iter in seq_len(max_iter)) {
    beta_old <- beta_mat
    gamma_old <- gamma
    sigma_old <- sigma_mean
    constants <- app_joint_qvp_exal_constants(tau, gamma)
    prior_terms <- app_glofas_part1_quantile_prior_terms(rhs_state, beta_mat, K, p)
    beta_var <- vector("list", K)
    cov_diag <- vector("list", K)
    jitter_max <- 0
    for (kk in seq_len(K)) {
      w <- sigma_inv_mean[[kk]] * v_inv_mean[, kk] / constants$B[[kk]]
      shifted_y <- y - alpha[[kk]] - constants$lambda[[kk]] * sigma_mean[[kk]] * s_mean[, kk]
      linear <- sigma_inv_mean[[kk]] / constants$B[[kk]] *
        (v_inv_mean[, kk] * shifted_y - constants$A[[kk]])
      solved <- app_glofas_part1_quantile_solve_block(
        Z = Z,
        weight = w,
        linear = linear,
        prior_diag = prior_terms$diag[[kk]],
        prior_linear = prior_terms$linear[[kk]]
      )
      beta_mat[, kk] <- solved$beta
      beta_var[[kk]] <- rowSums((Z %*% solved$cov) * Z)
      cov_diag[[kk]] <- solved$cov_diag
      jitter_max <- max(jitter_max, solved$jitter)
    }
    fitted_no_alpha <- Z %*% beta_mat
    for (kk in seq_len(K)) {
      w <- sigma_inv_mean[[kk]] * v_inv_mean[, kk] / constants$B[[kk]]
      shifted <- y - fitted_no_alpha[, kk] - constants$lambda[[kk]] * sigma_mean[[kk]] * s_mean[, kk]
      cA <- sigma_inv_mean[[kk]] * constants$A[[kk]] / constants$B[[kk]]
      prior_prec <- alpha_prior$precision[[kk]]
      mean_alpha <- (sum(w * shifted - cA) + prior_prec * alpha_prior$mean[[kk]]) / (sum(w) + prior_prec)
      lower <- if (kk == 1L) -Inf else alpha[[kk - 1L]]
      upper <- if (kk == K) Inf else alpha[[kk + 1L]]
      alpha[[kk]] <- min(max(mean_alpha, lower), upper)
    }
    likelihood_quadratic <- 0
    latent_linear <- 0
    positive_shift_quadratic <- 0
    for (kk in seq_len(K)) {
      r_mean <- y - alpha[[kk]] - fitted_no_alpha[, kk]
      r2_mean <- r_mean^2 + beta_var[[kk]]
      centered_s2 <- r2_mean -
        2 * constants$lambda[[kk]] * sigma_mean[[kk]] * r_mean * s_mean[, kk] * v_inv_mean[, kk] +
        constants$lambda[[kk]]^2 * sigma_mean[[kk]]^2 * s2_mean[, kk] * v_inv_mean[, kk]
      chi_v <- pmax(sigma_inv_mean[[kk]] * centered_s2 / constants$B[[kk]], .Machine$double.eps)
      psi_v <- pmax(sigma_inv_mean[[kk]] * (constants$A[[kk]]^2 / constants$B[[kk]] + 2), .Machine$double.eps)
      v_mean[, kk] <- app_joint_qvp_gig_moment(0.5, chi_v, psi_v, 1)
      v_inv_mean[, kk] <- app_joint_qvp_gig_moment(0.5, chi_v, psi_v, -1)
      prec_s <- 1 + sigma_mean[[kk]] * constants$lambda[[kk]]^2 * v_inv_mean[, kk] / constants$B[[kk]]
      linear_s <- constants$lambda[[kk]] *
        (r_mean * v_inv_mean[, kk] - constants$A[[kk]]) / constants$B[[kk]]
      tn <- app_joint_qvp_truncnorm_positive_moments(mean = linear_s / prec_s, sd = sqrt(1 / prec_s))
      s_mean[, kk] <- tn$mean
      s2_mean[, kk] <- tn$second
      chi_sigma <- 2 * b_sigma + 2 * sum(v_mean[, kk]) +
        1 / constants$B[[kk]] * sum(
          r2_mean * v_inv_mean[, kk] -
            2 * constants$A[[kk]] * r_mean +
            constants$A[[kk]]^2 * v_mean[, kk]
        )
      psi_sigma <- constants$lambda[[kk]]^2 / constants$B[[kk]] * sum(s2_mean[, kk] * v_inv_mean[, kk])
      lambda_sigma <- -a_sigma - 1.5 * Tn
      sigma_mean[[kk]] <- app_joint_qvp_gig_moment(lambda_sigma, chi_sigma, max(psi_sigma, .Machine$double.eps), 1)
      sigma_inv_mean[[kk]] <- app_joint_qvp_gig_moment(lambda_sigma, chi_sigma, max(psi_sigma, .Machine$double.eps), -1)
      gamma_objective <- function(g) {
        cst <- tryCatch(app_joint_qvp_exal_constants(tau[[kk]], g), error = function(e) NULL)
        if (is.null(cst)) return(-Inf)
        quad <- r2_mean * v_inv_mean[, kk] -
          2 * cst$lambda[[1L]] * sigma_mean[[kk]] * r_mean * s_mean[, kk] * v_inv_mean[, kk] +
          cst$lambda[[1L]]^2 * sigma_mean[[kk]]^2 * s2_mean[, kk] * v_inv_mean[, kk] -
          2 * cst$A[[1L]] * (r_mean - cst$lambda[[1L]] * sigma_mean[[kk]] * s_mean[, kk]) +
          cst$A[[1L]]^2 * v_mean[, kk]
        val <- -0.5 * sum(log(cst$B[[1L]]) + quad / (cst$B[[1L]] * sigma_mean[[kk]]))
        if (is.finite(val)) val else -Inf
      }
      opt <- stats::optimize(
        f = gamma_objective,
        interval = c(support$lower[[kk]] + 1.0e-8, support$upper[[kk]] - 1.0e-8),
        maximum = TRUE
      )
      gamma[[kk]] <- opt$maximum
      likelihood_quadratic <- likelihood_quadratic + 0.5 *
        sum(centered_s2 * sigma_inv_mean[[kk]] * v_inv_mean[, kk]) / constants$B[[kk]]
      latent_linear <- latent_linear + sum(v_mean[, kk])
      positive_shift_quadratic <- positive_shift_quadratic + 0.5 * sum(s2_mean[, kk])
    }
    rhs_state <- app_glofas_part1_quantile_update_rhs_blockmf(rhs_state, beta_mat, cov_diag, K, p, rhs_vb_inner)
    rhs_summary <- app_joint_qvp_rhs_vb_summary(rhs_state, K, p)
    max_beta_change <- max(abs(beta_mat - beta_old))
    max_gamma_change <- max(abs(gamma - gamma_old))
    max_sigma_change <- max(abs(sigma_mean - sigma_old))
    monitor <- -likelihood_quadratic - latent_linear - positive_shift_quadratic
    gamma_trace[iter, ] <- gamma
    sigma_trace[iter, ] <- sigma_mean
    trace[[iter]] <- data.frame(
      iter = iter,
      max_beta_change = max_beta_change,
      max_gamma_change = max_gamma_change,
      max_sigma_change = max_sigma_change,
      max_jitter = jitter_max,
      rhs_mean_precision = mean(rhs_summary$mean_precision),
      rhs_max_precision = max(rhs_summary$max_precision),
      monitor = monitor,
      backend = "block_mean_field",
      stringsAsFactors = FALSE
    )
    if (progress_every > 0L && (iter == 1L || iter == max_iter || iter %% progress_every == 0L)) {
      app_joint_qvp_progress_append(progress_path, transform(trace[[iter]], label = progress_label, max_iter = max_iter, min_iter = min_iter, converged = FALSE, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
    }
    if (iter >= min_iter && max(max_beta_change, max_gamma_change, max_sigma_change) < tol) {
      converged <- TRUE
      trace <- trace[seq_len(iter)]
      gamma_trace <- gamma_trace[seq_len(iter), , drop = FALSE]
      sigma_trace <- sigma_trace[seq_len(iter), , drop = FALSE]
      if (progress_every > 0L) {
        app_joint_qvp_progress_append(progress_path, transform(trace[[iter]], label = progress_label, max_iter = max_iter, min_iter = min_iter, converged = TRUE, timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
      }
      break
    }
  }
  qhat_mean <- Z %*% beta_mat + matrix(alpha, Tn, K, byrow = TRUE)
  out <- list(
    beta_mean = as.numeric(beta_mat),
    beta_cov = NULL,
    beta_covariance_approximation = "block_mean_field_by_tau",
    alpha_mean = alpha,
    sigma_mean = sigma_mean,
    sigma_inv_mean = sigma_inv_mean,
    gamma_mean = gamma,
    v_mean = v_mean,
    v_inv_mean = v_inv_mean,
    s_mean = s_mean,
    s2_mean = s2_mean,
    rhs_state = rhs_state,
    rhs_prior_summary = app_joint_qvp_rhs_vb_summary(rhs_state, K, p),
    qhat_mean = qhat_mean,
    crossing_diagnostics = app_joint_qvp_crossing_diagnostics(qhat_mean, tau),
    trace = do.call(rbind, trace),
    gamma_trace = gamma_trace,
    sigma_trace = sigma_trace,
    converged = converged,
    tau = tau,
    kappa = 1,
    monitor_label = "exal_vb_block_mean_field_coordinate_monitor",
    backend = "joint_exal_block_mean_field_rhs_vb",
    manifest = app_joint_qvp_manifest_row(
      fit_id = sprintf("glofas_joint_exal_blockmf_%s", format(Sys.time(), "%Y%m%d%H%M%S")),
      tau = tau,
      kappa = 1,
      likelihood = "exal",
      inference = "vb_ld_block_mean_field",
      seed = NA_integer_,
      status = if (converged) "prototype_success" else "prototype_max_iter"
    )
  )
  class(out) <- c("joint_qvp_qdesn_vb_fit", "list")
  out
}

app_glofas_part1_quantile_fit_readout <- function(
  y,
  Z,
  tau,
  model_family = c("independent_al", "independent_exal", "joint_al", "joint_exal"),
  controls = app_glofas_part1_quantile_default_controls()
) {
  model_family <- match.arg(model_family)
  y <- as.numeric(y)
  Z <- as.matrix(Z)
  storage.mode(Z) <- "double"
  tau <- as.numeric(tau)
  if (!length(tau) || any(!is.finite(tau)) || any(tau <= 0 | tau >= 1)) {
    stop("tau must contain finite probabilities in (0, 1).", call. = FALSE)
  }
  if (nrow(Z) != length(y) || any(!is.finite(Z)) || any(!is.finite(y))) {
    stop("Quantile readout design/response are malformed.", call. = FALSE)
  }
  if (startsWith(model_family, "independent") && length(tau) != 1L) {
    stop("Independent Part 1 quantile jobs fit exactly one tau.", call. = FALSE)
  }
  p <- ncol(Z)
  K <- length(tau)
  max_dense_dim <- as.integer(controls$max_dense_dim %||% 4000L)
  joint_backend <- tolower(as.character(controls$joint_backend %||% "auto")[[1L]])
  joint_backend <- match.arg(joint_backend, c("auto", "dense", "blockmf", "block_mean_field"))
  if (identical(joint_backend, "block_mean_field")) joint_backend <- "blockmf"
  is_joint <- startsWith(model_family, "joint")
  dense_possible <- p * K <= max_dense_dim
  use_blockmf <- is_joint && (identical(joint_backend, "blockmf") || (identical(joint_backend, "auto") && !dense_possible))
  if (is_joint && identical(joint_backend, "dense") && !dense_possible) {
    stop(
      sprintf(
        "Requested dense %s fit has K*p=%d beta dimensions, above max_dense_dim=%d.",
        model_family,
        p * K,
        max_dense_dim
      ),
      call. = FALSE
    )
  }
  tau0 <- as.numeric(controls$tau0 %||% 1)
  fit_tol <- max(as.numeric(controls$tol), .Machine$double.xmin)
  min_iter <- as.integer(controls$min_iter %||% 1L)
  if (!is.finite(min_iter) || min_iter < 1L) stop("min_iter must be positive.", call. = FALSE)
  min_iter <- min(min_iter, as.integer(controls$max_iter))
  progress_path <- controls$progress_path %||% NULL
  progress_every <- as.integer(controls$progress_every %||% 0L)
  if (!is.finite(progress_every) || progress_every < 0L) progress_every <- 0L
  init <- app_glofas_part1_quantile_resolve_init(controls, y = y, Z = Z, tau = tau)
  started <- Sys.time()

  if (identical(model_family, "independent_al") || (identical(model_family, "joint_al") && !use_blockmf)) {
    fit <- app_joint_qvp_fit_al_vb_tiny(
      y = y,
      Z = Z,
      tau = tau,
      max_iter = as.integer(controls$max_iter),
      tol = fit_tol,
      min_iter = min_iter,
      kappa = 1,
      tau0 = tau0,
      zeta2 = as.numeric(controls$zeta2),
      a_sigma = as.numeric(controls$a_sigma),
      b_sigma = as.numeric(controls$b_sigma),
      alpha_prior_mean = "empirical_quantile",
      alpha_prior_sd = controls$alpha_prior_sd,
      alpha_min_spacing = if (K > 1L) 0 else 0,
      max_dense_dim = max_dense_dim,
      rhs_vb_inner = as.integer(controls$rhs_vb_inner),
      init = init,
      progress_path = progress_path,
      progress_every = progress_every,
      progress_label = model_family
    )
  } else if (identical(model_family, "joint_al") && use_blockmf) {
    fit <- app_glofas_part1_quantile_fit_al_blockmf(
      y = y,
      Z = Z,
      tau = tau,
      max_iter = as.integer(controls$max_iter),
      tol = fit_tol,
      min_iter = min_iter,
      tau0 = tau0,
      zeta2 = as.numeric(controls$zeta2),
      a_sigma = as.numeric(controls$a_sigma),
      b_sigma = as.numeric(controls$b_sigma),
      alpha_prior_sd = controls$alpha_prior_sd,
      rhs_vb_inner = as.integer(controls$rhs_vb_inner),
      init = init,
      progress_path = progress_path,
      progress_every = progress_every,
      progress_label = "joint_al_blockmf"
    )
  } else if (identical(model_family, "independent_exal") || (identical(model_family, "joint_exal") && !use_blockmf)) {
    al_init <- init
    if (is.null(al_init)) {
      prefit_iter <- as.integer(controls$exal_prefit_max_iter %||% 25L)
      if (prefit_iter > 0L) {
        al_init <- app_joint_qvp_fit_al_vb_tiny(
          y = y,
          Z = Z,
          tau = tau,
          max_iter = min(prefit_iter, as.integer(controls$max_iter)),
          tol = fit_tol,
          min_iter = min(min_iter, min(prefit_iter, as.integer(controls$max_iter))),
          kappa = 1,
          tau0 = tau0,
          zeta2 = as.numeric(controls$zeta2),
          a_sigma = as.numeric(controls$a_sigma),
          b_sigma = as.numeric(controls$b_sigma),
          alpha_prior_mean = "empirical_quantile",
          alpha_prior_sd = controls$alpha_prior_sd,
          alpha_min_spacing = if (K > 1L) 0 else 0,
          max_dense_dim = max_dense_dim,
          rhs_vb_inner = as.integer(controls$rhs_vb_inner),
          progress_path = progress_path,
          progress_every = progress_every,
          progress_label = paste0(model_family, "_al_prefit")
        )
      }
    }
    fit <- app_joint_exqdesn_fit_vb_dispatch(
      method_id = as.character(controls$exal_method_id),
      y = y,
      Z = Z,
      tau = tau,
      max_iter = as.integer(controls$max_iter),
      tol = fit_tol,
      min_iter = min_iter,
      kappa = 1,
      tau0 = tau0,
      zeta2 = as.numeric(controls$zeta2),
      a_sigma = as.numeric(controls$a_sigma),
      b_sigma = as.numeric(controls$b_sigma),
      init = al_init,
      alpha_prior_mean = "empirical_quantile",
      alpha_prior_sd = controls$alpha_prior_sd,
      alpha_min_spacing = if (K > 1L) 0 else 0,
      max_dense_dim = max_dense_dim,
      rhs_vb_inner = as.integer(controls$rhs_vb_inner),
      progress_path = progress_path,
      progress_every = progress_every,
      progress_label = model_family
    )
  } else if (identical(model_family, "joint_exal") && use_blockmf) {
    fit <- app_glofas_part1_quantile_fit_exal_blockmf(
      y = y,
      Z = Z,
      tau = tau,
      max_iter = as.integer(controls$max_iter),
      tol = fit_tol,
      min_iter = min_iter,
      tau0 = tau0,
      zeta2 = as.numeric(controls$zeta2),
      a_sigma = as.numeric(controls$a_sigma),
      b_sigma = as.numeric(controls$b_sigma),
      alpha_prior_sd = controls$alpha_prior_sd,
      rhs_vb_inner = as.integer(controls$rhs_vb_inner),
      init = init,
      progress_path = progress_path,
      progress_every = progress_every,
      progress_label = "joint_exal_blockmf"
    )
  } else {
    stop(sprintf("Unsupported Part 1 quantile model_family '%s'.", model_family), call. = FALSE)
  }
  fit$model_family <- model_family
  fit$fit_runtime_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  fit$part1_quantile_controls <- controls
  fit$part1_quantile_tau0 <- tau0
  fit$joint_backend_requested <- joint_backend
  fit$joint_backend_used <- if (use_blockmf) "blockmf" else "dense"
  fit$init_source_path <- if (!is.null(init$init_source_path)) init$init_source_path else NA_character_
  fit$init_source_class <- if (!is.null(init$init_source_class)) init$init_source_class else NA_character_
  fit
}

app_glofas_part1_quantile_beta_matrix <- function(fit, p, tau) {
  tau <- as.numeric(tau)
  K <- length(tau)
  beta <- as.numeric(fit$beta_mean)
  if (length(beta) != K * p) {
    stop("Quantile fit beta dimension does not match design/tau grid.", call. = FALSE)
  }
  beta_mat <- app_joint_qvp_beta_matrix(beta, K, p)
  alpha <- as.numeric(fit$alpha_mean)
  if (length(alpha) != K) stop("Quantile fit alpha dimension does not match tau grid.", call. = FALSE)
  list(alpha = alpha, beta = beta_mat)
}

app_glofas_part1_quantile_predict <- function(fit, Z, tau) {
  Z <- as.matrix(Z)
  parts <- app_glofas_part1_quantile_beta_matrix(fit, ncol(Z), tau)
  out <- Z %*% parts$beta + matrix(parts$alpha, nrow = nrow(Z), ncol = length(tau), byrow = TRUE)
  colnames(out) <- app_glofas_part1_quantile_slug(tau)
  out
}

app_glofas_part1_quantile_recursive_one <- function(
  fitted,
  fit,
  tau_index,
  tau,
  future_dates,
  covariate_timeline = NULL,
  forecast_backend = c("auto", "cpp", "r")
) {
  forecast_backend <- match.arg(forecast_backend)
  design <- fitted$design
  qfit <- list(reservoir = design$reservoir, states = design$states, meta = design$design_meta)
  app_glofas_oracle_validate_forecastable_qfit(qfit)
  future_dates <- as.Date(future_dates)
  H <- length(future_dates)
  if (!H) stop("future_dates must be non-empty.", call. = FALSE)
  p <- ncol(fitted$Z)
  parts <- app_glofas_part1_quantile_beta_matrix(fit, p, tau)
  beta_full <- c(parts$alpha[[tau_index]], parts$beta[, tau_index])
  names(beta_full) <- colnames(design$X)
  compiled_inputs <- app_glofas_oracle_compiled_future_inputs(
    qfit,
    future_dates = future_dates,
    covariate_timeline = covariate_timeline %||% qfit$meta$covariate_timeline %||% NULL
  )
  pseudo <- list(
    design = design,
    fit = list(beta_mean = beta_full, p = length(beta_full))
  )
  cpp_supported <- app_glofas_oracle_d1_cpp_supported(pseudo)
  use_cpp <- identical(forecast_backend, "cpp") ||
    (identical(forecast_backend, "auto") && isTRUE(cpp_supported) && app_glofas_oracle_load_cpp(required = FALSE))
  if (identical(forecast_backend, "cpp") && (!isTRUE(cpp_supported) || !app_glofas_oracle_load_cpp(required = TRUE))) {
    stop("Requested C++ quantile forecast backend is not supported for this fitted object.", call. = FALSE)
  }
  if (isTRUE(use_cpp)) {
    cpp_out <- glofas_oracle_d1_plugin_recursive_cpp(
      W = as.matrix(design$reservoir$W[[1L]]),
      Win = as.matrix(design$reservoir$Win[[1L]]),
      state0 = as.numeric(app_qdesn_last_states(qfit)[[1L]]),
      static_values = as.matrix(compiled_inputs$static_values),
      future_index = matrix(as.integer(compiled_inputs$future_index), nrow = H),
      lag_center = as.numeric(qfit$meta$lag_center),
      lag_scale = as.numeric(qfit$meta$lag_scale),
      standardize_inputs = isTRUE(qfit$meta$standardize_inputs %||% FALSE),
      input_bound = as.character(qfit$meta$input_bound %||% "none"),
      win_scale_global = as.numeric(qfit$meta$win_scale_global %||% 1),
      win_scale_bias = as.numeric(qfit$meta$win_scale_bias %||% 1),
      alpha = as.numeric(design$reservoir$alpha[[1L]]),
      beta_mean = as.numeric(beta_full),
      act_f = as.character(design$reservoir$act_f %||% "tanh")
    )
    return(list(
      qhat = as.numeric(cpp_out$pred_mean),
      X_future = as.matrix(cpp_out$X_future),
      input_lag_matrix = as.matrix(cpp_out$input_rows),
      future_input_audit = compiled_inputs$audit,
      forecast_backend = as.character(cpp_out$backend %||% "cpp_d1_plugin_recursive")
    ))
  }

  states <- app_qdesn_last_states(qfit)
  y_future <- rep(NA_real_, H)
  X_future <- matrix(NA_real_, nrow = H, ncol = ncol(design$X))
  colnames(X_future) <- colnames(design$X)
  input_rows <- matrix(NA_real_, nrow = H, ncol = ncol(compiled_inputs$static_values))
  colnames(input_rows) <- colnames(compiled_inputs$static_values)
  future_positions <- lapply(seq_len(H), function(h) which(compiled_inputs$future_index[h, ] > 0L))
  future_indices <- lapply(seq_len(H), function(h) compiled_inputs$future_index[h, future_positions[[h]]])
  for (h in seq_len(H)) {
    row_value <- compiled_inputs$static_values[h, ]
    if (length(future_positions[[h]])) {
      row_value[future_positions[[h]]] <- y_future[future_indices[[h]]]
    }
    states <- app_qdesn_continue_one_step(states, row_value, design$reservoir, qfit$meta)
    core <- app_qdesn_readout_row_from_states(states, design$reservoir)
    Xrow <- app_glofas_oracle_make_readout_row(core, colnames(design$X))
    y_future[[h]] <- sum(as.numeric(Xrow) * as.numeric(beta_full))
    X_future[h, ] <- Xrow
    input_rows[h, ] <- row_value
  }
  list(
    qhat = y_future,
    X_future = X_future,
    input_lag_matrix = input_rows,
    future_input_audit = compiled_inputs$audit,
    forecast_backend = "r_compiled_inputs_quantile_recursive"
  )
}

app_glofas_part1_quantile_recursive_forecast <- function(
  fitted,
  fit,
  tau,
  future_dates,
  covariate_timeline = NULL,
  forecast_backend = c("auto", "cpp", "r")
) {
  forecast_backend <- match.arg(forecast_backend)
  tau <- as.numeric(tau)
  rows <- vector("list", length(tau))
  audits <- vector("list", length(tau))
  input_tables <- vector("list", length(tau))
  backends <- character(length(tau))
  started <- Sys.time()
  for (kk in seq_along(tau)) {
    one <- app_glofas_part1_quantile_recursive_one(
      fitted = fitted,
      fit = fit,
      tau_index = kk,
      tau = tau,
      future_dates = future_dates,
      covariate_timeline = covariate_timeline,
      forecast_backend = forecast_backend
    )
    rows[[kk]] <- data.frame(
      target_date = as.Date(future_dates),
      horizon = seq_along(future_dates),
      tau = tau[[kk]],
      qhat = as.numeric(one$qhat),
      forecast_backend = one$forecast_backend,
      stringsAsFactors = FALSE
    )
    audits[[kk]] <- cbind(
      data.frame(tau = tau[[kk]], stringsAsFactors = FALSE),
      one$future_input_audit
    )
    input_tables[[kk]] <- cbind(
      data.frame(target_date = as.Date(future_dates), tau = tau[[kk]], stringsAsFactors = FALSE),
      as.data.frame(one$input_lag_matrix, check.names = FALSE)
    )
    backends[[kk]] <- one$forecast_backend
  }
  list(
    forecast = app_bind_rows_fill(rows),
    future_input_audit = app_bind_rows_fill(audits),
    input_lag_matrix = app_bind_rows_fill(input_tables),
    forecast_backend = paste(unique(backends), collapse = ";"),
    forecast_runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
}

app_glofas_part1_quantile_path_table <- function(fitted, fit, tau, forecast, future_truth = NULL) {
  hist_q <- app_glofas_part1_quantile_predict(fit, fitted$Z, tau)
  hist_rows <- vector("list", length(tau))
  for (kk in seq_along(tau)) {
    hist_rows[[kk]] <- data.frame(
      date = as.Date(fitted$design$dates),
      segment = "historical_fit",
      tau = tau[[kk]],
      observed = as.numeric(fitted$design$y),
      qhat = as.numeric(hist_q[, kk]),
      stringsAsFactors = FALSE
    )
  }
  fut <- forecast$forecast
  if (!is.null(future_truth) && nrow(future_truth)) {
    truth <- as.numeric(future_truth$y_transformed)
    truth <- truth[match(as.Date(fut$target_date), as.Date(future_truth$date))]
  } else {
    truth <- rep(NA_real_, nrow(fut))
  }
  fut_rows <- data.frame(
    date = as.Date(fut$target_date),
    segment = "oracle_realized_forecast",
    tau = as.numeric(fut$tau),
    observed = truth,
    qhat = as.numeric(fut$qhat),
    stringsAsFactors = FALSE
  )
  app_bind_rows_fill(c(hist_rows, list(fut_rows)))
}

app_glofas_part1_quantile_score_forecast <- function(path_table) {
  fut <- path_table[path_table$segment == "oracle_realized_forecast" & is.finite(path_table$observed), , drop = FALSE]
  if (!nrow(fut)) return(list(pointwise = data.frame(), aggregate = data.frame()))
  fut$check_loss <- app_glofas_part1_quantile_check_loss(fut$observed, fut$qhat, fut$tau)
  fut$abs_error <- abs(fut$qhat - fut$observed)
  fut$squared_error <- (fut$qhat - fut$observed)^2
  aggregate_rows <- lapply(split(fut, fut$tau), function(x) {
    data.frame(
      tau = unique(x$tau)[[1L]],
      n_scores = nrow(x),
      forecast_check_loss_mean = mean(x$check_loss, na.rm = TRUE),
      forecast_mae = mean(x$abs_error, na.rm = TRUE),
      forecast_rmse = sqrt(mean(x$squared_error, na.rm = TRUE)),
      stringsAsFactors = FALSE
    )
  })
  list(pointwise = fut, aggregate = app_bind_rows_fill(aggregate_rows))
}

app_glofas_part1_quantile_trace_rows <- function(fit, model_family, tau) {
  trace <- fit$trace %||% data.frame()
  if (!nrow(trace)) return(data.frame())
  if (!"tau" %in% names(trace)) {
    trace <- cbind(data.frame(tau = if (length(tau) == 1L) tau[[1L]] else NA_real_), trace)
  }
  cbind(data.frame(model_family = model_family, stringsAsFactors = FALSE), trace)
}

app_glofas_part1_quantile_coefficient_rows <- function(fit, Z, tau) {
  parts <- app_glofas_part1_quantile_beta_matrix(fit, ncol(Z), tau)
  rows <- vector("list", length(tau))
  for (kk in seq_along(tau)) {
    rows[[kk]] <- data.frame(
      tau = tau[[kk]],
      column_index = seq_len(ncol(Z) + 1L),
      column_name = c("readout_intercept", colnames(Z)),
      beta_mean = c(parts$alpha[[kk]], parts$beta[, kk]),
      block = c("readout_intercept", rep("reservoir_state", ncol(Z))),
      stringsAsFactors = FALSE
    )
  }
  app_bind_rows_fill(rows)
}

app_glofas_part1_quantile_plot_paths <- function(
  path_table,
  pdf_path,
  origin_date,
  last_n_history = NULL,
  title = NULL
) {
  app_ensure_dir(dirname(pdf_path))
  x <- path_table
  origin_date <- as.Date(origin_date)
  if (!is.null(last_n_history)) {
    hist_dates <- utils::tail(sort(unique(x$date[x$segment == "historical_fit"])), as.integer(last_n_history))
    x <- x[x$date %in% c(hist_dates, x$date[x$segment == "oracle_realized_forecast"]), , drop = FALSE]
  }
  tau_values <- sort(unique(as.numeric(x$tau)))
  cols <- grDevices::hcl.colors(length(tau_values), palette = "Dark 3")
  ylim <- range(c(x$observed, x$qhat), finite = TRUE)
  pdf(pdf_path, width = 10.5, height = 5.8)
  on.exit(dev.off(), add = TRUE)
  par(mar = c(4.2, 4.4, 2.7, 1.1), las = 1)
  plot(
    x$date,
    x$qhat,
    type = "n",
    xlab = "Date",
    ylab = "Transformed response",
    ylim = ylim,
    main = title %||% "Part 1 quantile recursive forecast"
  )
  points(
    x$date[x$segment == "historical_fit"],
    x$observed[x$segment == "historical_fit"],
    pch = 16,
    cex = 0.35,
    col = grDevices::adjustcolor("#1d1d1d", alpha.f = 0.75)
  )
  points(
    x$date[x$segment == "oracle_realized_forecast"],
    x$observed[x$segment == "oracle_realized_forecast"],
    pch = 16,
    cex = 0.55,
    col = "#c0392b"
  )
  for (kk in seq_along(tau_values)) {
    block <- x[abs(as.numeric(x$tau) - tau_values[[kk]]) < 1.0e-12, , drop = FALSE]
    block <- block[order(block$date), , drop = FALSE]
    lines(block$date, block$qhat, col = cols[[kk]], lwd = 1.7)
  }
  abline(v = origin_date, lty = 2, col = "#555555", lwd = 1.1)
  legend(
    "topleft",
    bty = "n",
    cex = 0.82,
    lwd = c(rep(1.7, length(tau_values)), NA, NA, 1.1),
    pch = c(rep(NA, length(tau_values)), 16, 16, NA),
    col = c(cols, "#1d1d1d", "#c0392b", "#555555"),
    legend = c(sprintf("tau %.2f", tau_values), "observed history", "future observed", "origin")
  )
  invisible(pdf_path)
}

app_glofas_part1_quantile_write_result <- function(result, root, run_label) {
  root <- normalizePath(root, mustWork = FALSE)
  dirs <- file.path(root, c("tables", "figures", "objects", "logs", "traces", "coefficients"))
  invisible(lapply(dirs, app_ensure_dir))
  app_write_csv(result$path_table, file.path(root, "tables", paste0(run_label, "_path.csv")))
  app_write_csv(result$forecast$forecast, file.path(root, "tables", paste0(run_label, "_forecast.csv")))
  app_write_csv(result$forecast$future_input_audit, file.path(root, "tables", paste0(run_label, "_future_input_audit.csv")))
  app_write_csv(result$forecast$input_lag_matrix, file.path(root, "tables", paste0(run_label, "_future_input_lag_matrix.csv")))
  app_write_csv(result$scores$pointwise, file.path(root, "tables", paste0(run_label, "_forecast_scores_by_horizon.csv")))
  app_write_csv(result$scores$aggregate, file.path(root, "tables", paste0(run_label, "_forecast_scores.csv")))
  app_write_csv(result$trace, file.path(root, "traces", paste0(run_label, "_vb_trace.csv")))
  app_write_csv(result$coefficients, file.path(root, "coefficients", paste0(run_label, "_coefficients.csv")))
  app_write_csv(result$candidate_row, file.path(root, "tables", paste0(run_label, "_candidate.csv")))
  app_write_yaml(
    list(
      run_label = run_label,
      diagnostic_type = "part1_quantile_oracle_realized_recursive_forecast",
      model_family = result$model_family,
      likelihood = result$likelihood,
      synthesis = FALSE,
      target = result$target,
      tau = as.numeric(result$tau),
      forecast_backend = result$forecast$forecast_backend,
      joint_backend_requested = result$fit$joint_backend_requested %||% NA_character_,
      joint_backend_used = result$fit$joint_backend_used %||% NA_character_,
      init_source_path = result$fit$init_source_path %||% NA_character_,
      min_iter = as.integer(result$controls$min_iter %||% NA_integer_),
      progress_path = result$controls$progress_path %||% NA_character_,
      forecast_covariate_policy = "realized retrospective ppt/soil only",
      response_leakage_policy = "future response unavailable to recursive inputs; recursive quantile forecasts feed their own future output lags",
      fit_contract = "AL/exAL RHS-VB quantile readout on fixed Part 1 USGS-only DESN states",
      fit_runtime_seconds = result$fit$fit_runtime_seconds,
      forecast_runtime_seconds = result$forecast$forecast_runtime_seconds
    ),
    file.path(root, "logs", paste0(run_label, "_contract.yaml"))
  )
  saveRDS(result$fit, file.path(root, "objects", paste0(run_label, "_fit.rds")), version = 2L)
  summary <- data.frame(
    run_label = run_label,
    target = result$target,
    model_family = result$model_family,
    likelihood = result$likelihood,
    fit_structure = result$fit_structure,
    tau_grid = paste(sprintf("%.2f", result$tau), collapse = ","),
    candidate_id = as.character(result$candidate_row$candidate_id[[1L]]),
    rhs_candidate_id = as.character(result$candidate_row$rhs_candidate_id[[1L]]),
    rhs_tau0 = as.numeric(result$controls$tau0 %||% result$candidate_row$rhs_tau0[[1L]]),
    max_iter = as.integer(result$controls$max_iter),
    tol = as.numeric(result$controls$tol),
    min_iter = as.integer(result$controls$min_iter %||% NA_integer_),
    converged = isTRUE(result$fit$converged),
    fit_runtime_seconds = as.numeric(result$fit$fit_runtime_seconds),
    forecast_runtime_seconds = as.numeric(result$forecast$forecast_runtime_seconds),
    forecast_backend = result$forecast$forecast_backend,
    joint_backend_used = result$fit$joint_backend_used %||% NA_character_,
    init_source_path = result$fit$init_source_path %||% NA_character_,
    synthesis = FALSE,
    stringsAsFactors = FALSE
  )
  score_wide <- result$scores$aggregate
  if (nrow(score_wide)) {
    score_wide$model_family <- summary$model_family[[1L]]
    score_wide$run_label <- run_label
  }
  app_write_csv(summary, file.path(root, "tables", paste0(run_label, "_summary.csv")))
  app_write_csv(score_wide, file.path(root, "tables", paste0(run_label, "_score_summary_by_tau.csv")))
  full_pdf <- file.path(root, "figures", paste0(run_label, "_forecast_full_history.pdf"))
  recent_pdf <- file.path(root, "figures", paste0(run_label, "_forecast_last200_history.pdf"))
  app_glofas_part1_quantile_plot_paths(
    result$path_table,
    full_pdf,
    origin_date = result$origin_date,
    title = sprintf("%s %s forecast: full history", result$model_family, result$likelihood)
  )
  app_glofas_part1_quantile_plot_paths(
    result$path_table,
    recent_pdf,
    origin_date = result$origin_date,
    last_n_history = 200L,
    title = sprintf("%s %s forecast: last 200 history rows", result$model_family, result$likelihood)
  )
  app_write_csv(
    data.frame(
      figure = c("full_history", "last200_history"),
      path = c(full_pdf, recent_pdf),
      stringsAsFactors = FALSE
    ),
    file.path(root, "figures", paste0(run_label, "_figure_manifest.csv"))
  )
  list(root = root, summary = summary, figures = c(full_pdf, recent_pdf))
}

app_glofas_part1_quantile_oracle_forecast <- function(
  base_cfg,
  candidate_row = NULL,
  model_family = c("independent_al", "independent_exal", "joint_al", "joint_exal"),
  tau = NULL,
  origin_date = NULL,
  horizon_days = NULL,
  target = "usgs",
  max_iter = 100L,
  tol = 0,
  tau0 = NULL,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = Inf,
  max_dense_dim = NULL,
  rhs_vb_inner = 5L,
  exal_method_id = "VB1_structured_v",
  exal_prefit_max_iter = 25L,
  min_iter = 1L,
  joint_backend = "auto",
  init = NULL,
  init_fit_path = NULL,
  init_fit_paths = NULL,
  progress_path = NULL,
  progress_every = 0L,
  forecast_backend = c("auto", "cpp", "r"),
  root_candidates = NULL
) {
  model_family <- match.arg(model_family)
  forecast_backend <- match.arg(forecast_backend)
  tau <- if (is.null(tau) || !length(tau)) {
    if (startsWith(model_family, "joint")) app_glofas_part1_quantile_grid() else 0.5
  } else {
    as.numeric(tau)
  }
  prepared <- app_glofas_part1_quantile_prepare_design(
    base_cfg = base_cfg,
    candidate_row = candidate_row,
    origin_date = origin_date,
    horizon_days = horizon_days,
    target = target,
    root_candidates = root_candidates
  )
  controls <- app_glofas_part1_quantile_default_controls(
    max_iter = max_iter,
    tol = tol,
    min_iter = min_iter,
    tau0 = tau0 %||% prepared$candidate_row$rhs_tau0[[1L]],
    zeta2 = zeta2,
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_sd = alpha_prior_sd,
    max_dense_dim = max_dense_dim %||% 4000L,
    rhs_vb_inner = rhs_vb_inner,
    exal_method_id = exal_method_id,
    exal_prefit_max_iter = exal_prefit_max_iter,
    joint_backend = joint_backend,
    init = init,
    init_fit_path = init_fit_path,
    init_fit_paths = init_fit_paths,
    progress_path = progress_path,
    progress_every = progress_every
  )
  fit <- app_glofas_part1_quantile_fit_readout(
    y = prepared$design$y,
    Z = prepared$Z,
    tau = tau,
    model_family = model_family,
    controls = controls
  )
  fitted <- list(
    candidate_row = prepared$candidate_row,
    bundle = prepared$bundle,
    design = prepared$design,
    Z = prepared$Z
  )
  forecast <- app_glofas_part1_quantile_recursive_forecast(
    fitted = fitted,
    fit = fit,
    tau = tau,
    future_dates = prepared$bundle$future_dates,
    covariate_timeline = attr(prepared$bundle$panel, "model_covariate_timeline", exact = TRUE),
    forecast_backend = forecast_backend
  )
  path_table <- app_glofas_part1_quantile_path_table(
    fitted = fitted,
    fit = fit,
    tau = tau,
    forecast = forecast,
    future_truth = prepared$bundle$future_truth
  )
  family_row <- app_glofas_part1_quantile_model_families()
  family_row <- family_row[family_row$model_family == model_family, , drop = FALSE]
  list(
    target = target,
    model_family = model_family,
    likelihood = family_row$likelihood[[1L]],
    fit_structure = family_row$fit_structure[[1L]],
    tau = tau,
    origin_date = as.Date(prepared$bundle$cutoff$train_end[[1L]]),
    candidate_row = prepared$candidate_row,
    controls = controls,
    fit = fit,
    forecast = forecast,
    path_table = path_table,
    scores = app_glofas_part1_quantile_score_forecast(path_table),
    trace = app_glofas_part1_quantile_trace_rows(fit, model_family, tau),
    coefficients = app_glofas_part1_quantile_coefficient_rows(fit, prepared$Z, tau)
  )
}
