# Two-component AL/exAL inference for the historical GloFAS Part 3 bridge.

app_glofas_part3_quantile_grid <- function() {
  c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
}

app_glofas_part3_quantile_default_controls <- function(
  max_iter = 100L,
  min_iter = 30L,
  tol = 0.01,
  tau0_reference = 1,
  tau0_discrepancy = 1.0e-3,
  slab_s2 = 1,
  a_zeta = 2,
  b_zeta = 4,
  a_sigma = 2,
  b_sigma = 1,
  rhs_vb_inner = 5L,
  progress_path = NULL,
  progress_every = 1L,
  quadrature_nodes = c(4L, 8L, 12L),
  quadrature_tolerance = 1.0e-6,
  diagnostic_stride = 10L
) {
  list(
    max_iter = as.integer(max_iter),
    min_iter = as.integer(min_iter),
    tol = as.numeric(tol),
    tau0_reference = as.numeric(tau0_reference),
    tau0_discrepancy = as.numeric(tau0_discrepancy),
    slab_s2 = as.numeric(slab_s2),
    a_zeta = as.numeric(a_zeta),
    b_zeta = as.numeric(b_zeta),
    a_sigma = as.numeric(a_sigma),
    b_sigma = as.numeric(b_sigma),
    rhs_vb_inner = as.integer(rhs_vb_inner),
    progress_path = progress_path,
    progress_every = as.integer(progress_every),
    quadrature_nodes = as.integer(quadrature_nodes),
    quadrature_tolerance = as.numeric(quadrature_tolerance),
    diagnostic_stride = as.integer(diagnostic_stride)
  )
}

app_glofas_part3_validate_quantile_controls <- function(controls) {
  if (controls$max_iter < 1L || controls$min_iter < 1L ||
      controls$min_iter > controls$max_iter || !is.finite(controls$tol) ||
      controls$tol <= 0) {
    stop("Invalid Part 3 quantile iteration controls.", call. = FALSE)
  }
  positive <- c(
    controls$tau0_reference, controls$tau0_discrepancy, controls$slab_s2,
    controls$a_zeta, controls$b_zeta, controls$a_sigma, controls$b_sigma,
    controls$quadrature_tolerance
  )
  if (any(!is.finite(positive)) || any(positive <= 0) || controls$rhs_vb_inner < 1L) {
    stop("Part 3 quantile prior and scale controls must be finite and positive.", call. = FALSE)
  }
  if (!length(controls$quadrature_nodes) || any(controls$quadrature_nodes < 2L)) {
    stop("Part 3 exAL quadrature node counts must be at least two.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_part3_validate_quantile_design <- function(design) {
  app_glofas_normal_part3_validate_design(design)
  if (!identical(colnames(design$reference$X)[[1L]], "readout_intercept") ||
      !identical(colnames(design$discrepancy$X)[[1L]], "readout_intercept")) {
    stop("Part 3 component designs must contain their own leading intercepts.", call. = FALSE)
  }
  if (ncol(design$reference$X) != design$p_beta ||
      ncol(design$discrepancy$X) != design$p_alpha) {
    stop("Part 3 component dimensions disagree with the stacked design.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_part3_quantile_check_loss <- function(y, q, tau) {
  residual <- as.numeric(y) - as.numeric(q)
  as.numeric((as.numeric(tau) - (residual < 0)) * residual)
}

app_glofas_part3_weighted_solve <- function(X, weight, linear, prior_diag, prior_linear, jitter = 1.0e-8) {
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  weight <- pmax(as.numeric(weight), .Machine$double.eps)
  linear <- as.numeric(linear)
  p <- ncol(X)
  if (length(weight) != nrow(X) || length(linear) != nrow(X) ||
      length(prior_diag) != p || length(prior_linear) != p) {
    stop("Part 3 weighted solve dimensions are inconsistent.", call. = FALSE)
  }
  Xw <- X * sqrt(weight)
  precision <- crossprod(Xw)
  diag(precision) <- diag(precision) + pmax(as.numeric(prior_diag), 1.0e-12)
  rhs <- as.numeric(crossprod(X, linear)) + as.numeric(prior_linear)
  solved <- app_glofas_normal_spd_solve(precision, rhs, jitter = jitter, max_tries = 7L)
  covariance <- solved$inv
  list(
    mean = as.numeric(solved$x),
    covariance = covariance,
    variance_diag = pmax(diag(covariance), 0),
    jitter_attempt = as.integer(solved$jitter_attempt),
    precision_chol = solved$chol
  )
}

app_glofas_part3_prediction_variance <- function(X, covariance) {
  X <- as.matrix(X)
  covariance <- as.matrix(covariance)
  pmax(rowSums((X %*% covariance) * X), 0)
}

app_glofas_part3_quantile_sigma_from_fit <- function(fit, z) {
  sigma <- fit$sigma_mean %||% NULL
  if (is.null(sigma) && !is.null(fit$sigma2_mean)) sigma <- sqrt(pmax(fit$sigma2_mean, .Machine$double.eps))
  if (is.null(sigma) && !is.null(fit$sigma_a) && !is.null(fit$sigma_b)) {
    sigma <- sqrt(pmax(fit$sigma_b / pmax(fit$sigma_a - 1, .Machine$double.eps), .Machine$double.eps))
  }
  sigma <- as.numeric(sigma %||% stats::mad(z))
  sigma <- sigma[is.finite(sigma) & sigma > 0]
  if (!length(sigma)) sigma <- max(stats::mad(z), 1.0e-3)
  sigma
}

app_glofas_part3_quantile_normalize_fit_object <- function(x) {
  if (is.character(x) && length(x) == 1L) {
    path <- normalizePath(x, mustWork = TRUE)
    out <- readRDS(path)
    attr(out, "part3_source_path") <- path
    attr(out, "part3_source_sha256") <- app_sha256_file(path)
    x <- out
  }
  if (is.list(x) && !is.null(x$fit) && is.list(x$fit)) x <- x$fit
  if (!is.list(x)) stop("Part 3 quantile initializer must be a fit object or RDS path.", call. = FALSE)
  x
}

app_glofas_part3_quantile_init_one <- function(init, design, tau) {
  init <- app_glofas_part3_quantile_normalize_fit_object(init)
  p_reference <- design$p_beta
  p_discrepancy <- design$p_alpha
  p_total <- p_reference + p_discrepancy
  source_tau <- as.numeric(init$tau %||% NA_real_)
  if (!is.null(init$beta_reference_mean) && !is.null(init$beta_discrepancy_mean)) {
    ref <- as.matrix(init$beta_reference_mean)
    disc <- as.matrix(init$beta_discrepancy_mean)
    if (nrow(ref) != p_reference || nrow(disc) != p_discrepancy) {
      stop("Part 3 quantile initializer component dimensions do not match.", call. = FALSE)
    }
    idx <- if (length(source_tau) == ncol(ref) && any(abs(source_tau - tau) < 1.0e-12)) {
      which.min(abs(source_tau - tau))
    } else 1L
    ref_var <- as.matrix(init$beta_reference_var_diag %||% matrix(0, p_reference, ncol(ref)))[, idx]
    disc_var <- as.matrix(init$beta_discrepancy_var_diag %||% matrix(0, p_discrepancy, ncol(disc)))[, idx]
    return(list(
      beta_reference = ref[, idx],
      beta_discrepancy = disc[, idx],
      var_reference = ref_var,
      var_discrepancy = disc_var,
      sigma = app_glofas_part3_quantile_sigma_from_fit(init, design$z),
      gamma = if (!is.null(init$gamma_mean) && length(init$gamma_mean) >= idx) init$gamma_mean[[idx]] else NULL,
      rhs_state_reference = if (length(source_tau) == 1L) init$rhs_state_reference %||% NULL else NULL,
      rhs_state_discrepancy = if (length(source_tau) == 1L) init$rhs_state_discrepancy %||% NULL else NULL,
      source_path = attr(init, "part3_source_path", exact = TRUE) %||% init$fit_object_path %||% NA_character_,
      source_sha256 = attr(init, "part3_source_sha256", exact = TRUE) %||% NA_character_,
      source_class = paste(class(init), collapse = ";")
    ))
  }
  beta <- as.numeric(init$beta_mean %||% numeric())
  if (length(beta) != p_total) {
    stop(sprintf("Part 3 Normal initializer has %d coefficients; expected %d.", length(beta), p_total), call. = FALSE)
  }
  variance <- as.numeric(init$beta_var_diag %||% if (!is.null(init$beta_cov)) diag(init$beta_cov) else rep(0, p_total))
  if (length(variance) != p_total) stop("Part 3 Normal initializer variance has the wrong dimension.", call. = FALSE)
  list(
    beta_reference = beta[seq_len(p_reference)],
    beta_discrepancy = beta[p_reference + seq_len(p_discrepancy)],
    var_reference = variance[seq_len(p_reference)],
    var_discrepancy = variance[p_reference + seq_len(p_discrepancy)],
    sigma = app_glofas_part3_quantile_sigma_from_fit(init, design$z),
    gamma = NULL,
    rhs_state_reference = init$rhs_state_reference %||% NULL,
    rhs_state_discrepancy = init$rhs_state_discrepancy %||% NULL,
    source_path = attr(init, "part3_source_path", exact = TRUE) %||% init$fit_object_path %||% NA_character_,
    source_sha256 = attr(init, "part3_source_sha256", exact = TRUE) %||% NA_character_,
    source_class = paste(class(init), collapse = ";")
  )
}

app_glofas_part3_quantile_initialize <- function(init, design, tau) {
  tau <- as.numeric(tau)
  K <- length(tau)
  p_reference <- design$p_beta
  p_discrepancy <- design$p_alpha
  if (is.null(init)) {
    return(list(
      beta_reference = matrix(0, p_reference, K),
      beta_discrepancy = matrix(0, p_discrepancy, K),
      var_reference = matrix(0, p_reference, K),
      var_discrepancy = matrix(0, p_discrepancy, K),
      sigma = rep(max(stats::mad(design$z), 1.0e-3), K),
      gamma = NULL,
      rhs_state_reference = NULL,
      rhs_state_discrepancy = NULL,
      provenance = data.frame(source_path = NA_character_, source_sha256 = NA_character_, source_class = "cold", stringsAsFactors = FALSE)
    ))
  }
  init_list <- if (is.list(init) && !is.null(init$fits)) init$fits else if (is.list(init) && length(init) == K && is.null(init$beta_mean) && is.null(init$beta_reference_mean)) init else list(init)
  if (length(init_list) == 1L && K > 1L) init_list <- rep(init_list, K)
  if (length(init_list) != K) stop("Part 3 joint initializer must contain one fit per quantile.", call. = FALSE)
  pieces <- lapply(seq_len(K), function(kk) app_glofas_part3_quantile_init_one(init_list[[kk]], design, tau[[kk]]))
  list(
    beta_reference = do.call(cbind, lapply(pieces, `[[`, "beta_reference")),
    beta_discrepancy = do.call(cbind, lapply(pieces, `[[`, "beta_discrepancy")),
    var_reference = do.call(cbind, lapply(pieces, `[[`, "var_reference")),
    var_discrepancy = do.call(cbind, lapply(pieces, `[[`, "var_discrepancy")),
    sigma = vapply(pieces, function(x) as.numeric(x$sigma[[1L]]), numeric(1L)),
    gamma = if (all(vapply(pieces, function(x) !is.null(x$gamma), logical(1L)))) vapply(pieces, `[[`, numeric(1L), "gamma") else NULL,
    rhs_state_reference = if (K == 1L) pieces[[1L]]$rhs_state_reference else NULL,
    rhs_state_discrepancy = if (K == 1L) pieces[[1L]]$rhs_state_discrepancy else NULL,
    provenance = app_bind_rows_fill(lapply(pieces, function(x) data.frame(
      source_path = as.character(x$source_path),
      source_sha256 = as.character(x$source_sha256),
      source_class = as.character(x$source_class),
      stringsAsFactors = FALSE
    )))
  )
}

app_glofas_part3_quantile_progress <- function(path, row) {
  if (is.null(path) || !nzchar(as.character(path))) return(invisible(NULL))
  app_ensure_dir(dirname(path))
  old <- if (file.exists(path)) app_read_csv(path) else data.frame()
  app_write_csv(app_bind_rows_fill(list(old, row)), path)
  invisible(path)
}

app_glofas_part3_quantile_working_update <- function(
  R,
  D,
  y,
  g,
  weight_y,
  weight_g,
  linear_y,
  linear_g,
  beta_reference,
  beta_discrepancy,
  prior_reference,
  prior_discrepancy
) {
  discrepancy_mean <- as.numeric(D %*% beta_discrepancy)
  ref_solve <- app_glofas_part3_weighted_solve(
    X = R,
    weight = weight_y + weight_g,
    linear = linear_y + linear_g - weight_g * discrepancy_mean,
    prior_diag = prior_reference$diagonal,
    prior_linear = prior_reference$linear
  )
  reference_mean <- as.numeric(R %*% ref_solve$mean)
  disc_solve <- app_glofas_part3_weighted_solve(
    X = D,
    weight = weight_g,
    linear = linear_g - weight_g * reference_mean,
    prior_diag = prior_discrepancy$diagonal,
    prior_linear = prior_discrepancy$linear
  )
  list(reference = ref_solve, discrepancy = disc_solve)
}

app_glofas_part3_quantile_fit <- function(
  design,
  split,
  tau,
  likelihood = c("AL", "exAL"),
  fit_structure = c("independent", "joint"),
  controls = app_glofas_part3_quantile_default_controls(),
  init = NULL,
  fit_id = NULL
) {
  likelihood <- match.arg(likelihood)
  fit_structure <- match.arg(fit_structure)
  app_glofas_part3_validate_quantile_controls(controls)
  app_glofas_part3_validate_quantile_design(design)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  if (identical(fit_structure, "independent") && length(tau) != 1L) {
    stop("Independent Part 3 quantile fits require exactly one tau.", call. = FALSE)
  }
  idx <- as.integer(split$train_idx)
  R <- as.matrix(design$reference$X[idx, , drop = FALSE])
  D <- as.matrix(design$discrepancy$X[idx, , drop = FALSE])
  y <- as.numeric(design$y_reference[idx])
  g <- as.numeric(design$g_retrospective[idx])
  z <- c(y, g)
  Tn <- length(y)
  K <- length(tau)
  initialized <- app_glofas_part3_quantile_initialize(init, design, tau)
  beta_reference <- initialized$beta_reference
  beta_discrepancy <- initialized$beta_discrepancy
  variance_reference <- initialized$var_reference
  variance_discrepancy <- initialized$var_discrepancy
  rhs_controls <- app_glofas_part3_rhs_default_controls(
    tau0_reference = controls$tau0_reference,
    tau0_discrepancy = controls$tau0_discrepancy,
    slab_s2 = controls$slab_s2,
    a_zeta = controls$a_zeta,
    b_zeta = controls$b_zeta
  )
  warm_reference <- if (K == 1L && !is.null(initialized$rhs_state_reference)) {
    initialized$rhs_state_reference$anchor %||% initialized$rhs_state_reference
  } else NULL
  warm_discrepancy <- if (K == 1L && !is.null(initialized$rhs_state_discrepancy)) {
    initialized$rhs_state_discrepancy$anchor %||% initialized$rhs_state_discrepancy
  } else NULL
  rhs_reference <- app_glofas_part3_rhs_initialize(
    K, ncol(R), controls$tau0_reference, rhs_controls,
    warm_anchor = warm_reference,
    coefficient_mean = beta_reference,
    coefficient_var_diag = variance_reference
  )
  rhs_discrepancy <- app_glofas_part3_rhs_initialize(
    K, ncol(D), controls$tau0_discrepancy, rhs_controls,
    warm_anchor = warm_discrepancy,
    coefficient_mean = beta_discrepancy,
    coefficient_var_diag = variance_discrepancy
  )
  partition_certificate <- app_glofas_part3_rhs_partition_certificate(
    ncol(R), ncol(D), rhs_reference, rhs_discrepancy
  )
  sigma_mean <- pmax(as.numeric(initialized$sigma), 1.0e-6)
  if (length(sigma_mean) != K) sigma_mean <- rep(sigma_mean[[1L]], K)
  sigma_shape <- rep(controls$a_sigma + 1.5 * length(z), K)
  sigma_rate <- sigma_mean * pmax(sigma_shape - 1, .Machine$double.eps)
  latent_mean <- matrix(1, length(z), K)
  latent_inv_mean <- matrix(1, length(z), K)
  gamma <- block_moments <- s_mean <- s2_mean <- NULL
  if (identical(likelihood, "exAL")) {
    gamma <- initialized$gamma %||% app_joint_qvp_default_gamma(tau)
    gamma <- app_joint_qvp_check_gamma(tau, gamma)
    s_mean <- matrix(sqrt(2 / pi), length(z), K)
    s2_mean <- matrix(1, length(z), K)
    block_moments <- lapply(seq_len(K), function(kk) {
      app_joint_exqdesn_point_scale_shape_moments(tau[[kk]], gamma[[kk]], sigma_mean[[kk]])
    })
  }
  q_reference_old <- R %*% beta_reference
  q_discrepancy_old <- D %*% beta_discrepancy
  trace <- vector("list", controls$max_iter)
  quadrature_trace <- list()
  scale_shape_trace <- list()
  converged <- FALSE
  stop_reason <- "max_iter"
  started <- Sys.time()
  constants_al <- if (identical(likelihood, "AL")) app_joint_qvp_al_constants(tau) else NULL

  for (iter in seq_len(controls$max_iter)) {
    old_reference <- beta_reference
    old_discrepancy <- beta_discrepancy
    old_sigma <- sigma_mean
    old_gamma <- gamma
    prior_reference <- app_glofas_part3_rhs_prior_terms(rhs_reference, beta_reference)
    prior_discrepancy <- app_glofas_part3_rhs_prior_terms(rhs_discrepancy, beta_discrepancy)
    jitter_max <- 0L
    all_quadrature_converged <- TRUE

    for (kk in seq_len(K)) {
      if (identical(likelihood, "AL")) {
        A <- constants_al$A[[kk]]
        B <- constants_al$B[[kk]]
        sigma_inv <- sigma_shape[[kk]] / sigma_rate[[kk]]
        w <- sigma_inv * latent_inv_mean[, kk] / B
        linear <- sigma_inv / B * (latent_inv_mean[, kk] * z - A)
      } else {
        moments <- block_moments[[kk]]
        w <- moments[["inv_B_sigma_mean"]] * latent_inv_mean[, kk]
        linear <- w * z - moments[["lambda_over_B_mean"]] * s_mean[, kk] * latent_inv_mean[, kk] -
          moments[["A_inv_B_sigma_mean"]]
      }
      solved <- app_glofas_part3_quantile_working_update(
        R = R,
        D = D,
        y = y,
        g = g,
        weight_y = w[seq_len(Tn)],
        weight_g = w[Tn + seq_len(Tn)],
        linear_y = linear[seq_len(Tn)],
        linear_g = linear[Tn + seq_len(Tn)],
        beta_reference = beta_reference[, kk],
        beta_discrepancy = beta_discrepancy[, kk],
        prior_reference = list(
          diagonal = prior_reference$diagonal[[kk]],
          linear = prior_reference$linear[[kk]]
        ),
        prior_discrepancy = list(
          diagonal = prior_discrepancy$diagonal[[kk]],
          linear = prior_discrepancy$linear[[kk]]
        )
      )
      beta_reference[, kk] <- solved$reference$mean
      beta_discrepancy[, kk] <- solved$discrepancy$mean
      variance_reference[, kk] <- solved$reference$variance_diag
      variance_discrepancy[, kk] <- solved$discrepancy$variance_diag
      jitter_max <- max(jitter_max, solved$reference$jitter_attempt, solved$discrepancy$jitter_attempt)
      q_reference <- as.numeric(R %*% beta_reference[, kk])
      q_discrepancy <- as.numeric(D %*% beta_discrepancy[, kk])
      var_reference <- app_glofas_part3_prediction_variance(R, solved$reference$covariance)
      var_discrepancy <- app_glofas_part3_prediction_variance(D, solved$discrepancy$covariance)
      residual <- c(y - q_reference, g - q_reference - q_discrepancy)
      residual_second <- c(
        (y - q_reference)^2 + var_reference,
        (g - q_reference - q_discrepancy)^2 + var_reference + var_discrepancy
      )

      if (identical(likelihood, "AL")) {
        sigma_inv <- sigma_shape[[kk]] / sigma_rate[[kk]]
        A <- constants_al$A[[kk]]
        B <- constants_al$B[[kk]]
        chi <- pmax(sigma_inv * residual_second / B, .Machine$double.eps)
        psi <- rep(pmax(sigma_inv * (A^2 / B + 2), .Machine$double.eps), length(z))
        latent_mean[, kk] <- app_joint_qvp_gig_moment(0.5, chi, psi, 1)
        latent_inv_mean[, kk] <- app_joint_qvp_gig_moment(0.5, chi, psi, -1)
        sigma_rate[[kk]] <- controls$b_sigma + sum(latent_mean[, kk]) +
          0.5 / B * sum(
            residual_second * latent_inv_mean[, kk] - 2 * A * residual + A^2 * latent_mean[, kk]
          )
        sigma_mean[[kk]] <- sigma_rate[[kk]] / pmax(sigma_shape[[kk]] - 1, .Machine$double.eps)
      } else {
        moments <- block_moments[[kk]]
        chi <- moments[["inv_B_sigma_mean"]] * residual_second -
          2 * moments[["lambda_over_B_mean"]] * residual * s_mean[, kk] +
          moments[["sigma_lambda2_over_B_mean"]] * s2_mean[, kk]
        psi <- rep(moments[["A2_inv_B_sigma_mean"]] + 2 * moments[["sigma_inv_mean"]], length(z))
        latent_mean[, kk] <- app_joint_qvp_gig_moment(0.5, pmax(chi, .Machine$double.eps), pmax(psi, .Machine$double.eps), 1)
        latent_inv_mean[, kk] <- app_joint_qvp_gig_moment(0.5, pmax(chi, .Machine$double.eps), pmax(psi, .Machine$double.eps), -1)
        s_precision <- 1 + moments[["sigma_lambda2_over_B_mean"]] * latent_inv_mean[, kk]
        s_linear <- moments[["lambda_over_B_mean"]] * residual * latent_inv_mean[, kk] -
          moments[["A_lambda_over_B_mean"]]
        s_update <- app_joint_qvp_truncnorm_positive_moments(
          mean = s_linear / s_precision,
          sd = sqrt(1 / s_precision)
        )
        s_mean[, kk] <- s_update$mean
        s2_mean[, kk] <- s_update$second
        scale_update <- app_joint_exqdesn_structured_scale_shape_update(
          tau = tau[[kk]],
          augmentation = "v",
          r_mean = residual,
          r2_mean = residual_second,
          latent_mean = latent_mean[, kk],
          latent_inv_mean = latent_inv_mean[, kk],
          s_mean = s_mean[, kk],
          s2_mean = s2_mean[, kk],
          a_sigma = controls$a_sigma,
          b_sigma = controls$b_sigma,
          quadrature_nodes = controls$quadrature_nodes,
          quadrature_tolerance = controls$quadrature_tolerance
        )
        block_moments[[kk]] <- scale_update$moments
        gamma[[kk]] <- scale_update$moments[["gamma_mean"]]
        sigma_mean[[kk]] <- scale_update$moments[["sigma_mean"]]
        all_quadrature_converged <- all_quadrature_converged && isTRUE(scale_update$converged)
        if (iter == 1L || iter == controls$max_iter || iter %% controls$diagnostic_stride == 0L) {
          quadrature_trace[[length(quadrature_trace) + 1L]] <- transform(
            scale_update$diagnostics,
            iter = iter,
            quantile_index = kk,
            tau = tau[[kk]],
            augmentation = "v"
          )
          scale_shape_trace[[length(scale_shape_trace) + 1L]] <- data.frame(
            iter = iter,
            quantile_index = kk,
            tau = tau[[kk]],
            t(scale_update$moments),
            negative_branch_mass = scale_update$branch_mass[["negative"]],
            positive_branch_mass = scale_update$branch_mass[["positive"]],
            quadrature_nodes_per_panel = scale_update$nodes_per_panel,
            quadrature_relative_change = scale_update$relative_change,
            quadrature_converged = scale_update$converged,
            stringsAsFactors = FALSE,
            check.names = FALSE
          )
        }
      }
    }

    for (inner in seq_len(controls$rhs_vb_inner)) {
      rhs_reference <- app_glofas_part3_rhs_update(
        rhs_reference, beta_reference, variance_reference, iter = iter,
        update_global = if (inner == controls$rhs_vb_inner) NULL else FALSE
      )
      rhs_discrepancy <- app_glofas_part3_rhs_update(
        rhs_discrepancy, beta_discrepancy, variance_discrepancy, iter = iter,
        update_global = if (inner == controls$rhs_vb_inner) NULL else FALSE
      )
    }
    q_reference <- R %*% beta_reference
    q_discrepancy <- D %*% beta_discrepancy
    q_glofas <- q_reference + q_discrepancy
    max_reference_change <- max(abs(beta_reference - old_reference))
    max_discrepancy_change <- max(abs(beta_discrepancy - old_discrepancy))
    max_sigma_change <- max(abs(sigma_mean - old_sigma))
    max_gamma_change <- if (identical(likelihood, "exAL")) max(abs(gamma - old_gamma)) else 0
    max_path_change <- max(abs(q_reference - q_reference_old), abs(q_discrepancy - q_discrepancy_old))
    rhs_reference_summary <- app_glofas_part3_rhs_summary(rhs_reference, "reference")
    rhs_discrepancy_summary <- app_glofas_part3_rhs_summary(rhs_discrepancy, "discrepancy")
    monitor <- -sum((matrix(y, Tn, K) - q_reference)^2) - sum((matrix(g, Tn, K) - q_glofas)^2)
    max_change <- max(
      max_reference_change, max_discrepancy_change, max_sigma_change,
      max_gamma_change, max_path_change
    )
    trace[[iter]] <- data.frame(
      iter = iter,
      max_iter = controls$max_iter,
      min_iter = controls$min_iter,
      likelihood = likelihood,
      fit_structure = fit_structure,
      max_reference_change = max_reference_change,
      max_discrepancy_change = max_discrepancy_change,
      max_sigma_change = max_sigma_change,
      max_gamma_change = max_gamma_change,
      max_path_change = max_path_change,
      max_change = max_change,
      reference_effective_tau = mean(rhs_reference_summary$effective_tau),
      discrepancy_effective_tau = mean(rhs_discrepancy_summary$effective_tau),
      reference_tau_updates = sum(rhs_reference_summary$tau_update_count),
      discrepancy_tau_updates = sum(rhs_discrepancy_summary$tau_update_count),
      max_jitter_attempt = jitter_max,
      coordinate_monitor = monitor,
      objective_accounting_status = if (identical(likelihood, "AL")) {
        "coordinate_monitor_not_full_elbo"
      } else {
        "partial_missing_local_and_point_intercept_entropy"
      },
      all_quadrature_converged = if (identical(likelihood, "exAL")) all_quadrature_converged else NA,
      elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    )
    if (controls$progress_every > 0L &&
        (iter == 1L || iter == controls$max_iter || iter %% controls$progress_every == 0L)) {
      app_glofas_part3_quantile_progress(
        controls$progress_path,
        transform(trace[[iter]], timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
      )
      message(sprintf(
        "Part 3 %s %s iteration %d/%d: max_change=%.6g elapsed=%.1fs",
        fit_structure, likelihood, iter, controls$max_iter, max_change,
        trace[[iter]]$elapsed_seconds[[1L]]
      ))
    }
    q_reference_old <- q_reference
    q_discrepancy_old <- q_discrepancy
    if (iter >= controls$min_iter && max_change <= controls$tol &&
        (!identical(likelihood, "exAL") || all_quadrature_converged)) {
      converged <- TRUE
      stop_reason <- "tolerance"
      trace <- trace[seq_len(iter)]
      break
    }
  }

  trace <- app_bind_rows_fill(trace)
  q_reference <- R %*% beta_reference
  q_discrepancy <- D %*% beta_discrepancy
  q_glofas <- q_reference + q_discrepancy
  fit <- list(
    schema_version = "glofas_part3_quantile_fit_v1",
    fit_id = as.character(fit_id %||% sprintf("part3_%s_%s_%s", tolower(likelihood), fit_structure, format(Sys.time(), "%Y%m%d%H%M%S"))),
    model_family = paste0(fit_structure, "_", tolower(likelihood), "_rhs_vb"),
    likelihood = likelihood,
    fit_structure = fit_structure,
    tau = tau,
    beta_reference_mean = beta_reference,
    beta_discrepancy_mean = beta_discrepancy,
    beta_reference_var_diag = variance_reference,
    beta_discrepancy_var_diag = variance_discrepancy,
    reference_intercept_mean = beta_reference[1L, ],
    discrepancy_intercept_mean = beta_discrepancy[1L, ],
    sigma_mean = sigma_mean,
    sigma_shape = if (identical(likelihood, "AL")) sigma_shape else NULL,
    sigma_rate = if (identical(likelihood, "AL")) sigma_rate else NULL,
    gamma_mean = gamma,
    rhs_state_reference = rhs_reference,
    rhs_state_discrepancy = rhs_discrepancy,
    rhs_summary_reference = app_glofas_part3_rhs_summary(rhs_reference, "reference"),
    rhs_summary_discrepancy = app_glofas_part3_rhs_summary(rhs_discrepancy, "discrepancy"),
    rhs_partition_certificate = partition_certificate,
    qhat_reference_train = q_reference,
    qhat_discrepancy_train = q_discrepancy,
    qhat_glofas_train = q_glofas,
    trace = trace,
    quadrature_trace = app_bind_rows_fill(quadrature_trace),
    scale_shape_trace = app_bind_rows_fill(scale_shape_trace),
    converged = converged,
    stop_reason = stop_reason,
    iterations = nrow(trace),
    covariance_approximation = "mean_field_by_component_and_quantile",
    monitor_label = if (identical(likelihood, "AL")) {
      "al_block_cavi_coordinate_monitor_not_full_elbo"
    } else {
      "structured_exal_block_cavi_coordinate_monitor_not_full_elbo"
    },
    inference_method_id = if (identical(likelihood, "exAL")) "VB1_structured_v" else "AL_VB_partitioned_rhs",
    init_provenance = transform(initialized$provenance, target_tau = tau),
    design_hash = design$design_hash,
    train_index = idx,
    p_reference = ncol(R),
    p_discrepancy = ncol(D),
    controls = controls,
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
  class(fit) <- c("glofas_part3_quantile_fit", "list")
  fit
}

app_glofas_part3_predict_components <- function(fit, design, indices = seq_len(design$n_dates)) {
  if (!inherits(fit, "glofas_part3_quantile_fit")) stop("Expected a Part 3 quantile fit.", call. = FALSE)
  indices <- as.integer(indices)
  R <- as.matrix(design$reference$X[indices, , drop = FALSE])
  D <- as.matrix(design$discrepancy$X[indices, , drop = FALSE])
  reference <- R %*% fit$beta_reference_mean
  discrepancy <- D %*% fit$beta_discrepancy_mean
  glofas <- reference + discrepancy
  list(reference = reference, discrepancy = discrepancy, glofas = glofas)
}

app_glofas_part3_quantile_crps_grid <- function(y, qhat, tau) {
  qhat <- as.matrix(qhat)
  tau <- as.numeric(tau)
  if (ncol(qhat) != length(tau) || length(tau) < 2L) return(rep(NA_real_, nrow(qhat)))
  ord <- order(tau)
  tau <- tau[ord]
  qhat <- qhat[, ord, drop = FALSE]
  loss <- sapply(seq_along(tau), function(kk) app_glofas_part3_quantile_check_loss(y, qhat[, kk], tau[[kk]]))
  2 * rowSums(
    sweep((loss[, -ncol(loss), drop = FALSE] + loss[, -1L, drop = FALSE]) / 2, 2L, diff(tau), "*")
  )
}

app_glofas_part3_quantile_score_block <- function(y, qhat, tau, prefix) {
  qhat <- as.matrix(qhat)
  rows <- lapply(seq_along(tau), function(kk) {
    err <- qhat[, kk] - y
    data.frame(
      metric_block = prefix,
      tau = tau[[kk]],
      n = length(y),
      mean_check_loss = mean(app_glofas_part3_quantile_check_loss(y, qhat[, kk], tau[[kk]])),
      mae = mean(abs(err)),
      rmse = sqrt(mean(err^2)),
      hit_rate = mean(y <= qhat[, kk]),
      hit_rate_minus_tau = mean(y <= qhat[, kk]) - tau[[kk]],
      stringsAsFactors = FALSE
    )
  })
  out <- app_bind_rows_fill(rows)
  if (length(tau) > 1L) {
    out$mean_crps_grid <- mean(app_glofas_part3_quantile_crps_grid(y, qhat, tau))
  } else {
    out$mean_crps_grid <- NA_real_
  }
  out
}

app_glofas_part3_score_quantile_fit <- function(fit, design, split) {
  pred <- app_glofas_part3_predict_components(fit, design)
  blocks <- list()
  for (segment in c("train", "valid")) {
    idx <- as.integer(split[[paste0(segment, "_idx")]])
    blocks <- c(blocks, list(
      app_glofas_part3_quantile_score_block(design$y_reference[idx], pred$reference[idx, , drop = FALSE], fit$tau, paste0("usgs_", segment)),
      app_glofas_part3_quantile_score_block(design$g_retrospective[idx], pred$glofas[idx, , drop = FALSE], fit$tau, paste0("glofas_", segment)),
      app_glofas_part3_quantile_score_block(design$d_g[idx], pred$discrepancy[idx, , drop = FALSE], fit$tau, paste0("discrepancy_diagnostic_", segment)),
      app_glofas_part3_quantile_score_block(
        design$y_reference[idx],
        matrix(design$g_retrospective[idx], nrow = length(idx), ncol = length(fit$tau)) - pred$discrepancy[idx, , drop = FALSE],
        fit$tau,
        paste0("corrected_usgs_diagnostic_", segment)
      )
    ))
  }
  crossing <- app_bind_rows_fill(list(
    transform(app_joint_qvp_crossing_diagnostics(pred$reference, fit$tau), path = "usgs_reference"),
    transform(app_joint_qvp_crossing_diagnostics(pred$glofas, fit$tau), path = "retrospective_glofas")
  ))
  list(summary = app_bind_rows_fill(blocks), crossing = crossing, predictions = pred)
}

app_glofas_part3_quantile_coefficient_table <- function(fit, design) {
  make <- function(mean, variance, names, component) {
    rows <- lapply(seq_along(fit$tau), function(kk) data.frame(
      component = component,
      tau = fit$tau[[kk]],
      coefficient_index = seq_along(names),
      coefficient = names,
      mean = mean[, kk],
      sd = sqrt(pmax(variance[, kk], 0)),
      ci95_lower = mean[, kk] - 1.96 * sqrt(pmax(variance[, kk], 0)),
      ci95_upper = mean[, kk] + 1.96 * sqrt(pmax(variance[, kk], 0)),
      is_intercept = seq_along(names) == 1L,
      stringsAsFactors = FALSE
    ))
    app_bind_rows_fill(rows)
  }
  app_bind_rows_fill(list(
    make(fit$beta_reference_mean, fit$beta_reference_var_diag, colnames(design$reference$X), "reference"),
    make(fit$beta_discrepancy_mean, fit$beta_discrepancy_var_diag, colnames(design$discrepancy$X), "discrepancy")
  ))
}

app_glofas_part3_write_quantile_result <- function(fit, design, split, runtime_root, run_label) {
  runtime_root <- normalizePath(runtime_root, mustWork = FALSE)
  dirs <- file.path(runtime_root, c("objects", "scores", "traces", "coefficients", "tables", "status"))
  invisible(lapply(dirs, app_ensure_dir))
  scored <- app_glofas_part3_score_quantile_fit(fit, design, split)
  object_path <- file.path(runtime_root, "objects", paste0(run_label, "_fit.rds"))
  saveRDS(fit, object_path, version = 2L)
  paths <- c(
    fit = object_path,
    scores = app_write_csv(scored$summary, file.path(runtime_root, "scores", paste0(run_label, "_scores.csv"))),
    crossings = app_write_csv(scored$crossing, file.path(runtime_root, "scores", paste0(run_label, "_crossings.csv"))),
    trace = app_write_csv(fit$trace, file.path(runtime_root, "traces", paste0(run_label, "_trace.csv"))),
    coefficients = app_write_csv(app_glofas_part3_quantile_coefficient_table(fit, design), file.path(runtime_root, "coefficients", paste0(run_label, "_coefficients.csv"))),
    init_provenance = app_write_csv(fit$init_provenance, file.path(runtime_root, "tables", paste0(run_label, "_init_provenance.csv"))),
    rhs_reference = app_write_csv(fit$rhs_summary_reference, file.path(runtime_root, "tables", paste0(run_label, "_rhs_reference.csv"))),
    rhs_discrepancy = app_write_csv(fit$rhs_summary_discrepancy, file.path(runtime_root, "tables", paste0(run_label, "_rhs_discrepancy.csv")))
  )
  if (nrow(fit$quadrature_trace)) {
    paths <- c(paths, quadrature = app_write_csv(fit$quadrature_trace, file.path(runtime_root, "traces", paste0(run_label, "_quadrature.csv"))))
  }
  manifest <- data.frame(
    artifact = names(paths),
    path = unname(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_write_csv(manifest, file.path(runtime_root, "tables", paste0(run_label, "_artifact_manifest.csv")))
  list(paths = c(paths, artifact_manifest = manifest_path), scores = scored, fit_sha256 = app_sha256_file(object_path))
}
