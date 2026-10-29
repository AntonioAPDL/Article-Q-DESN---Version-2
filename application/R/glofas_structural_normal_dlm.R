# Structural Normal DLM feature generator for the GloFAS application.
#
# This module is a screening/feature-construction helper only. It fits a
# Normal DLM to the historical USGS path up to the cutoff, extracts level,
# seasonal, transfer, fitted-mean, and innovation-residual summaries, and
# exposes leakage-safe lagged features for later Q-DESN experiments.

app_glofas_structural_dlm_default_values <- function() {
  list(
    period = 363.5854,
    harmonics = c(1, 2, 1 / 6.8068493),
    lambda = 0.97,
    covariates = c("ppt", "soil"),
    covariate_mode = "transfer_only",
    standardize_covariates = TRUE,
    df_level = 1.0,
    df_seasonal_1 = 1.0,
    df_seasonal_2 = 1.0,
    df_seasonal_67 = 1.0,
    df_transfer = 1.0,
    df_covariate_coefficients = 1.0,
    df_readout_coefficients = 1.0,
    n0 = 20,
    S0 = 1,
    C0_level = 5,
    C0_seasonal = 1.5,
    C0_transfer = 2,
    C0_covariate_coefficient = 1,
    C0_readout_coefficient = 1,
    cov_eig_floor = 1.0e-8,
    cov_eig_cap = 1.0e8,
    cov_diag_jitter = 1.0e-10,
    backend = "cpp"
  )
}

app_glofas_structural_dlm_mode <- function(mode) {
  mode <- tolower(trimws(as.character(mode %||% "transfer_only")[[1L]]))
  allowed <- c("transfer_only", "readout_only", "transfer_plus_readout", "none")
  if (!mode %in% allowed) {
    stop(sprintf("Unsupported structural DLM covariate mode '%s'.", mode), call. = FALSE)
  }
  mode
}

app_glofas_structural_dlm_backend <- function(backend) {
  backend <- tolower(trimws(as.character(backend %||% "cpp")[[1L]]))
  if (!backend %in% c("cpp", "r")) {
    stop("Structural DLM backend must be one of: cpp, r.", call. = FALSE)
  }
  backend
}

app_glofas_structural_dlm_uses_transfer <- function(mode) {
  mode <- app_glofas_structural_dlm_mode(mode)
  mode %in% c("transfer_only", "transfer_plus_readout")
}

app_glofas_structural_dlm_uses_readout_covariates <- function(mode) {
  mode <- app_glofas_structural_dlm_mode(mode)
  mode %in% c("readout_only", "transfer_plus_readout")
}

app_glofas_structural_dlm_make_cfg <- function(...) {
  args <- list(...)
  if (length(args) == 1L && is.null(names(args)) && is.list(args[[1L]])) {
    args <- args[[1L]]
  }
  cfg <- app_glofas_structural_dlm_default_values()
  for (nm in names(args)) cfg[[nm]] <- args[[nm]]
  cfg$covariate_mode <- app_glofas_structural_dlm_mode(cfg$covariate_mode)
  cfg$backend <- app_glofas_structural_dlm_backend(cfg$backend)
  cfg$harmonics <- as.numeric(unlist(cfg$harmonics, use.names = FALSE))
  cfg$covariates <- as.character(unlist(cfg$covariates, use.names = FALSE))
  cfg$covariates <- cfg$covariates[nzchar(cfg$covariates)]
  app_glofas_structural_dlm_validate_cfg(cfg)
  cfg
}

app_glofas_structural_dlm_validate_cfg <- function(cfg) {
  period <- as.numeric(cfg$period)
  if (!is.finite(period) || period <= 0) stop("Structural DLM period must be positive.", call. = FALSE)
  harmonics <- as.numeric(unlist(cfg$harmonics, use.names = FALSE))
  if (length(harmonics) != 3L || any(!is.finite(harmonics))) {
    stop("Structural DLM requires exactly three finite harmonics.", call. = FALSE)
  }
  lambda <- as.numeric(cfg$lambda)
  if (!is.finite(lambda) || lambda <= 0 || lambda >= 1) {
    stop("Structural DLM transfer lambda must lie in (0, 1).", call. = FALSE)
  }
  mode <- app_glofas_structural_dlm_mode(cfg$covariate_mode)
  variables <- as.character(unlist(cfg$covariates, use.names = FALSE))
  unknown <- setdiff(variables, c("ppt", "soil"))
  if (length(unknown)) {
    stop(sprintf("Unsupported structural DLM covariates: %s.", paste(unknown, collapse = ", ")), call. = FALSE)
  }
  if ((app_glofas_structural_dlm_uses_transfer(mode) ||
       app_glofas_structural_dlm_uses_readout_covariates(mode)) && !length(variables)) {
    stop("Structural DLM covariate mode requires at least one covariate.", call. = FALSE)
  }
  df_names <- c(
    "df_level", "df_seasonal_1", "df_seasonal_2", "df_seasonal_67",
    "df_transfer", "df_covariate_coefficients", "df_readout_coefficients"
  )
  for (nm in df_names) {
    val <- as.numeric(cfg[[nm]])
    if (!is.finite(val) || val <= 0 || val > 1) {
      stop(sprintf("%s must be numeric in (0, 1].", nm), call. = FALSE)
    }
  }
  for (nm in c("n0", "S0", "C0_level", "C0_seasonal", "C0_transfer",
               "C0_covariate_coefficient", "C0_readout_coefficient",
               "cov_eig_floor", "cov_eig_cap")) {
    val <- as.numeric(cfg[[nm]])
    if (!is.finite(val) || val <= 0) stop(sprintf("%s must be positive.", nm), call. = FALSE)
  }
  if (as.numeric(cfg$cov_eig_cap) <= as.numeric(cfg$cov_eig_floor)) {
    stop("cov_eig_cap must exceed cov_eig_floor.", call. = FALSE)
  }
  if (as.numeric(cfg$cov_diag_jitter) < 0) {
    stop("cov_diag_jitter must be nonnegative.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_structural_dlm_rotation_block <- function(freq) {
  matrix(c(cos(freq), sin(freq), -sin(freq), cos(freq)), nrow = 2L, byrow = TRUE)
}

app_glofas_structural_dlm_base_G <- function(cfg) {
  period <- as.numeric(cfg$period)
  harmonics <- as.numeric(cfg$harmonics)
  G <- matrix(0, nrow = 7L, ncol = 7L)
  G[1L, 1L] <- 1
  for (j in seq_along(harmonics)) {
    i0 <- 2L + 2L * (j - 1L)
    G[i0:(i0 + 1L), i0:(i0 + 1L)] <-
      app_glofas_structural_dlm_rotation_block(2 * pi * harmonics[[j]] / period)
  }
  G
}

app_glofas_structural_dlm_state_map <- function(cfg) {
  mode <- app_glofas_structural_dlm_mode(cfg$covariate_mode)
  variables <- if (app_glofas_structural_dlm_uses_transfer(mode) ||
                   app_glofas_structural_dlm_uses_readout_covariates(mode)) {
    as.character(cfg$covariates)
  } else {
    character(0)
  }
  idx <- list(
    level = 1L,
    seasonal_1 = c(2L, 3L),
    seasonal_2 = c(4L, 5L),
    seasonal_67 = c(6L, 7L),
    transfer = integer(0),
    transfer_coefficients = integer(0),
    readout_coefficients = integer(0)
  )
  labels <- c(
    "level",
    "seasonal_1_cos", "seasonal_1_sin",
    "seasonal_2_cos", "seasonal_2_sin",
    "seasonal_67_cos", "seasonal_67_sin"
  )
  p <- 7L
  if (app_glofas_structural_dlm_uses_transfer(mode)) {
    idx$transfer <- p + 1L
    idx$transfer_coefficients <- seq.int(p + 2L, p + 1L + length(variables))
    labels <- c(labels, "transfer_state", paste0("transfer_coef_", variables))
    p <- p + 1L + length(variables)
  }
  if (app_glofas_structural_dlm_uses_readout_covariates(mode)) {
    idx$readout_coefficients <- seq.int(p + 1L, p + length(variables))
    labels <- c(labels, paste0("direct_coef_", variables))
    p <- p + length(variables)
  }
  idx$p <- p
  idx$labels <- labels
  idx$variables <- variables
  idx$mode <- mode
  idx
}

app_glofas_structural_dlm_scale_covariates <- function(
  covariates,
  dates,
  variables = c("ppt", "soil"),
  standardize = TRUE,
  scale_params = NULL
) {
  dates <- as.Date(dates)
  variables <- as.character(variables)
  if (!length(variables)) {
    X <- matrix(numeric(0), nrow = length(dates), ncol = 0L)
    return(list(X = X, raw = X, scale_params = list(columns = character(), center = numeric(), scale = numeric())))
  }
  if (is.null(covariates)) stop("Structural DLM covariates are required.", call. = FALSE)
  if (is.data.frame(covariates) && "date" %in% names(covariates)) {
    covariates$date <- as.Date(covariates$date)
    idx <- match(dates, covariates$date)
    if (any(is.na(idx))) {
      missing_dates <- sort(unique(dates[is.na(idx)]))
      stop(sprintf("Structural DLM covariates are missing dates: %s", paste(missing_dates, collapse = ", ")), call. = FALSE)
    }
    raw <- as.matrix(covariates[idx, variables, drop = FALSE])
  } else {
    raw <- as.matrix(covariates[, variables, drop = FALSE])
    if (nrow(raw) != length(dates)) {
      stop("Covariate matrix row count must match dates.", call. = FALSE)
    }
  }
  storage.mode(raw) <- "double"
  colnames(raw) <- variables
  if (any(!is.finite(raw))) stop("Structural DLM covariates contain non-finite values.", call. = FALSE)
  X <- raw
  if (isTRUE(standardize)) {
    if (is.null(scale_params)) {
      center <- colMeans(raw)
      scale <- apply(raw, 2L, stats::sd)
      scale[!is.finite(scale) | scale <= 0] <- 1
      scale_params <- list(columns = variables, center = center, scale = scale)
    }
    center <- as.numeric(scale_params$center[variables])
    scale <- as.numeric(scale_params$scale[variables])
    if (any(!is.finite(center)) || any(!is.finite(scale)) || any(scale <= 0)) {
      stop("Invalid structural DLM covariate scale parameters.", call. = FALSE)
    }
    X <- sweep(raw, 2L, center, "-")
    X <- sweep(X, 2L, scale, "/")
  } else if (is.null(scale_params)) {
    scale_params <- list(columns = variables, center = rep(0, length(variables)), scale = rep(1, length(variables)))
  }
  list(X = X, raw = raw, scale_params = scale_params)
}

app_glofas_structural_dlm_discount_block <- function(df, n) {
  n <- as.integer(n)
  if (!is.finite(n) || n < 1L) return(matrix(0, 0L, 0L))
  df <- as.numeric(df)
  if (!is.finite(df) || df <= 0 || df > 1) stop("Discount factors must lie in (0, 1].", call. = FALSE)
  scale <- if (df >= 1) 0 else (1 - df) / df
  matrix(scale, nrow = n, ncol = n)
}

app_glofas_structural_dlm_discount_scale_matrix <- function(cfg, state_map) {
  blocks <- list(
    app_glofas_structural_dlm_discount_block(cfg$df_level, 1L),
    app_glofas_structural_dlm_discount_block(cfg$df_seasonal_1, 2L),
    app_glofas_structural_dlm_discount_block(cfg$df_seasonal_2, 2L),
    app_glofas_structural_dlm_discount_block(cfg$df_seasonal_67, 2L)
  )
  if (length(state_map$transfer)) {
    blocks <- c(blocks, list(
      app_glofas_structural_dlm_discount_block(cfg$df_transfer, 1L),
      app_glofas_structural_dlm_discount_block(cfg$df_covariate_coefficients, length(state_map$variables))
    ))
  }
  if (length(state_map$readout_coefficients)) {
    blocks <- c(blocks, list(
      app_glofas_structural_dlm_discount_block(cfg$df_readout_coefficients, length(state_map$variables))
    ))
  }
  p <- sum(vapply(blocks, nrow, integer(1L)))
  out <- matrix(0, nrow = p, ncol = p)
  pos <- 1L
  for (blk in blocks) {
    k <- nrow(blk)
    out[pos:(pos + k - 1L), pos:(pos + k - 1L)] <- blk
    pos <- pos + k
  }
  out
}

app_glofas_structural_dlm_build_sequences <- function(y, dates, covariates = NULL, cfg = app_glofas_structural_dlm_make_cfg()) {
  cfg <- app_glofas_structural_dlm_make_cfg(cfg)
  y <- as.numeric(y)
  dates <- as.Date(dates)
  if (!length(y) || length(y) != length(dates) || any(!is.finite(y)) || any(is.na(dates))) {
    stop("Structural DLM y and dates must be finite and aligned.", call. = FALSE)
  }
  state_map <- app_glofas_structural_dlm_state_map(cfg)
  cov <- app_glofas_structural_dlm_scale_covariates(
    covariates = covariates,
    dates = dates,
    variables = state_map$variables,
    standardize = isTRUE(cfg$standardize_covariates)
  )
  X <- cov$X
  p <- state_map$p
  Tn <- length(y)
  F_mat <- matrix(0, nrow = Tn, ncol = p)
  colnames(F_mat) <- state_map$labels
  F_mat[, state_map$level] <- 1
  F_mat[, state_map$seasonal_1[[1L]]] <- 1
  F_mat[, state_map$seasonal_2[[1L]]] <- 1
  F_mat[, state_map$seasonal_67[[1L]]] <- 1
  if (length(state_map$transfer)) F_mat[, state_map$transfer] <- 1
  if (length(state_map$readout_coefficients)) {
    F_mat[, state_map$readout_coefficients] <- X
  }

  base_G <- app_glofas_structural_dlm_base_G(cfg)
  G_array <- array(0, dim = c(p, p, Tn), dimnames = list(state_map$labels, state_map$labels, NULL))
  for (tt in seq_len(Tn)) {
    G_t <- matrix(0, nrow = p, ncol = p)
    G_t[1:7, 1:7] <- base_G
    if (length(state_map$transfer)) {
      tr <- state_map$transfer
      tc <- state_map$transfer_coefficients
      G_t[tr, tr] <- as.numeric(cfg$lambda)
      G_t[tr, tc] <- X[tt, ]
      diag(G_t)[tc] <- 1
    }
    if (length(state_map$readout_coefficients)) {
      diag(G_t)[state_map$readout_coefficients] <- 1
    }
    G_array[, , tt] <- G_t
  }

  m0 <- rep(0, p)
  names(m0) <- state_map$labels
  m0[state_map$level] <- mean(y)
  C0_diag <- c(
    as.numeric(cfg$C0_level),
    rep(as.numeric(cfg$C0_seasonal), 6L)
  )
  if (length(state_map$transfer)) {
    C0_diag <- c(C0_diag, as.numeric(cfg$C0_transfer), rep(as.numeric(cfg$C0_covariate_coefficient), length(state_map$variables)))
  }
  if (length(state_map$readout_coefficients)) {
    C0_diag <- c(C0_diag, rep(as.numeric(cfg$C0_readout_coefficient), length(state_map$variables)))
  }
  C0_star <- diag(C0_diag, p)
  dimnames(C0_star) <- list(state_map$labels, state_map$labels)
  discount_scale <- app_glofas_structural_dlm_discount_scale_matrix(cfg, state_map)
  dimnames(discount_scale) <- list(state_map$labels, state_map$labels)
  list(
    y = y,
    dates = dates,
    covariates_scaled = X,
    covariates_raw = cov$raw,
    covariate_scale_params = cov$scale_params,
    F_mat = F_mat,
    G_array = G_array,
    m0 = m0,
    C0_star = C0_star,
    n0 = as.numeric(cfg$n0),
    S0 = as.numeric(cfg$S0),
    discount_scale_mat = discount_scale,
    state_map = state_map,
    cfg = cfg
  )
}

app_glofas_structural_dlm_cov_stabilize <- function(Sigma, cfg = app_glofas_structural_dlm_default_values()) {
  Sigma <- as.matrix(Sigma)
  if (!all(is.finite(Sigma))) Sigma[!is.finite(Sigma)] <- 0
  Sigma <- (Sigma + t(Sigma)) / 2
  eig <- tryCatch(suppressWarnings(eigen(Sigma, symmetric = TRUE)), error = function(e) NULL)
  floor <- as.numeric(cfg$cov_eig_floor %||% 1.0e-8)
  cap <- as.numeric(cfg$cov_eig_cap %||% 1.0e8)
  jitter <- as.numeric(cfg$cov_diag_jitter %||% 1.0e-10)
  if (is.null(eig) || any(!is.finite(eig$values)) || any(!is.finite(eig$vectors))) {
    Sigma <- diag(floor, nrow(Sigma))
  } else {
    vals <- pmin(pmax(as.numeric(eig$values), floor), cap)
    Sigma <- eig$vectors %*% diag(vals, length(vals)) %*% t(eig$vectors)
  }
  (Sigma + t(Sigma)) / 2 + diag(jitter, nrow(Sigma))
}

app_glofas_structural_dlm_safe_inverse_r <- function(Sigma, cfg = app_glofas_structural_dlm_default_values()) {
  Sigma <- app_glofas_structural_dlm_cov_stabilize(Sigma, cfg)
  inv <- tryCatch(solve(Sigma), error = function(e) NULL)
  if (!is.null(inv) && all(is.finite(inv))) return(inv)
  sv <- svd(Sigma)
  tol <- max(1.0e-12, .Machine$double.eps * max(dim(Sigma)) * max(sv$d, na.rm = TRUE))
  d_inv <- ifelse(is.finite(sv$d) & sv$d > tol, 1 / sv$d, 1 / tol)
  inv <- sv$v %*% diag(d_inv, length(d_inv)) %*% t(sv$u)
  if (!all(is.finite(inv))) {
    stop("Structural DLM R smoother failed to invert covariance matrix.", call. = FALSE)
  }
  inv
}

app_glofas_structural_dlm_filter_r <- function(sequences) {
  cfg <- sequences$cfg
  y <- sequences$y
  F_mat <- as.matrix(sequences$F_mat)
  G_array <- as.array(sequences$G_array)
  discount <- as.matrix(sequences$discount_scale_mat)
  m_prev <- as.numeric(sequences$m0)
  C_prev <- app_glofas_structural_dlm_cov_stabilize(sequences$C0_star, cfg)
  n_prev <- as.numeric(sequences$n0)
  S_prev <- as.numeric(sequences$S0)
  Tn <- length(y)
  p <- length(m_prev)
  a <- m <- matrix(0, nrow = p, ncol = Tn)
  P_star <- R_star <- C_star <- array(0, dim = c(p, p, Tn))
  f <- Q_star <- e <- n_prev_seq <- S_prev_seq <- n <- S <- Q_scale <- pred_var_actual <- fitted_mean <- fitted_var_actual <- rep(NA_real_, Tn)
  for (tt in seq_len(Tn)) {
    F_t <- as.numeric(F_mat[tt, ])
    G_t <- as.matrix(G_array[, , tt])
    a_t <- as.numeric(G_t %*% m_prev)
    P_t <- app_glofas_structural_dlm_cov_stabilize(G_t %*% C_prev %*% t(G_t), cfg)
    W_t <- discount * P_t
    R_t <- app_glofas_structural_dlm_cov_stabilize(P_t + W_t, cfg)
    f_t <- as.numeric(crossprod(F_t, a_t))
    Q_t <- as.numeric(1 + crossprod(F_t, R_t %*% F_t))
    Q_t <- max(Q_t, 1.0e-10)
    e_t <- y[[tt]] - f_t
    A_t <- as.numeric((R_t %*% F_t) / Q_t)
    m_t <- as.numeric(a_t + A_t * e_t)
    C_t <- app_glofas_structural_dlm_cov_stabilize(R_t - (A_t %*% t(A_t)) * Q_t, cfg)
    n_t <- n_prev + 1
    S_t <- (n_prev * S_prev + e_t^2 / Q_t) / n_t
    if (!is.finite(S_t) || S_t <= 0) S_t <- S_prev
    a[, tt] <- a_t
    m[, tt] <- m_t
    P_star[, , tt] <- P_t
    R_star[, , tt] <- R_t
    C_star[, , tt] <- C_t
    f[tt] <- f_t
    Q_star[tt] <- Q_t
    e[tt] <- e_t
    n_prev_seq[tt] <- n_prev
    S_prev_seq[tt] <- S_prev
    n[tt] <- n_t
    S[tt] <- S_t
    Q_scale[tt] <- S_prev * Q_t
    pred_var_actual[tt] <- if (n_prev > 2) n_prev / (n_prev - 2) * Q_scale[tt] else NA_real_
    fitted_mean[tt] <- as.numeric(crossprod(F_t, m_t))
    post_scale <- S_t * as.numeric(crossprod(F_t, C_t %*% F_t))
    fitted_var_actual[tt] <- if (n_t > 2) n_t / (n_t - 2) * post_scale else NA_real_
    m_prev <- m_t
    C_prev <- C_t
    n_prev <- n_t
    S_prev <- S_t
  }
  list(
    a = a,
    m = m,
    P_star = P_star,
    R_star = R_star,
    C_star = C_star,
    f = f,
    Q_star = Q_star,
    e = e,
    n_prev = n_prev_seq,
    S_prev = S_prev_seq,
    n = n,
    S = S,
    Q_scale = Q_scale,
    pred_var_actual = pred_var_actual,
    fitted_mean = fitted_mean,
    fitted_var_actual = fitted_var_actual,
    stabilization = list(calls = NA_integer_, cov_projected = NA_integer_)
  )
}

app_glofas_structural_dlm_load_cpp <- function() {
  if (exists("glofas_structural_dlm_filter_forward_cpp", mode = "function", inherits = TRUE) &&
      exists("glofas_structural_dlm_smooth_backward_cpp", mode = "function", inherits = TRUE) &&
      exists("glofas_structural_dlm_safe_inv_cpp", mode = "function", inherits = TRUE)) {
    return(invisible(TRUE))
  }
  app_require_namespace("Rcpp")
  cpp_path <- app_path("application/src/glofas_structural_normal_dlm_kalman.cpp")
  if (!file.exists(cpp_path)) {
    stop(sprintf("Missing structural DLM C++ backend: %s", cpp_path), call. = FALSE)
  }
  Rcpp::sourceCpp(cpp_path, rebuild = FALSE, showOutput = FALSE)
  invisible(TRUE)
}

app_glofas_structural_dlm_filter <- function(sequences, backend = NULL) {
  backend <- app_glofas_structural_dlm_backend(backend %||% sequences$cfg$backend)
  if (identical(backend, "r")) return(app_glofas_structural_dlm_filter_r(sequences))
  app_glofas_structural_dlm_load_cpp()
  out <- glofas_structural_dlm_filter_forward_cpp(
    y = as.numeric(sequences$y),
    F_mat = as.matrix(sequences$F_mat),
    G_array = as.array(sequences$G_array),
    discount_scale_mat = as.matrix(sequences$discount_scale_mat),
    m0 = as.numeric(sequences$m0),
    C0_star_in = as.matrix(sequences$C0_star),
    n0 = as.numeric(sequences$n0),
    S0 = as.numeric(sequences$S0),
    cov_eig_floor = as.numeric(sequences$cfg$cov_eig_floor),
    cov_eig_cap = as.numeric(sequences$cfg$cov_eig_cap),
    cov_diag_jitter = as.numeric(sequences$cfg$cov_diag_jitter)
  )
  for (nm in c("f", "Q_star", "e", "n_prev", "S_prev", "n", "S", "Q_scale",
               "pred_var_actual", "fitted_mean", "fitted_var_actual")) {
    out[[nm]] <- as.numeric(out[[nm]])
  }
  out
}

app_glofas_structural_dlm_smooth_r <- function(sequences, filter) {
  cfg <- sequences$cfg
  F_mat <- as.matrix(sequences$F_mat)
  G_array <- as.array(sequences$G_array)
  Tn <- ncol(filter$m)
  p <- nrow(filter$m)
  if (!length(Tn) || Tn < 1L || !length(p) || p < 1L) {
    stop("Structural DLM smoother requires nonempty filter matrices.", call. = FALSE)
  }
  s <- as.matrix(filter$m)
  D_star <- as.array(filter$C_star)
  B_star <- array(0, dim = c(p, p, Tn))
  D_star[, , Tn] <- app_glofas_structural_dlm_cov_stabilize(D_star[, , Tn], cfg)
  if (Tn > 1L) {
    for (tt in seq.int(Tn - 1L, 1L)) {
      C_t <- app_glofas_structural_dlm_cov_stabilize(filter$C_star[, , tt], cfg)
      R_next <- app_glofas_structural_dlm_cov_stabilize(filter$R_star[, , tt + 1L], cfg)
      G_next <- as.matrix(G_array[, , tt + 1L])
      B_t <- C_t %*% t(G_next) %*% app_glofas_structural_dlm_safe_inverse_r(R_next, cfg)
      s[, tt] <- as.numeric(filter$m[, tt] + B_t %*% (s[, tt + 1L] - filter$a[, tt + 1L]))
      D_star[, , tt] <- app_glofas_structural_dlm_cov_stabilize(
        C_t + B_t %*% (D_star[, , tt + 1L] - R_next) %*% t(B_t),
        cfg
      )
      B_star[, , tt] <- B_t
    }
  }
  final_n <- as.numeric(utils::tail(filter$n, 1L))
  final_S <- as.numeric(utils::tail(filter$S, 1L))
  smoothed_mean <- rowSums(F_mat * t(s))
  smoothed_var_actual <- rep(NA_real_, Tn)
  for (tt in seq_len(Tn)) {
    F_t <- as.numeric(F_mat[tt, ])
    mean_var_scale <- final_S * as.numeric(crossprod(F_t, D_star[, , tt] %*% F_t))
    if (is.finite(final_n) && final_n > 2 && is.finite(mean_var_scale) && mean_var_scale >= 0) {
      smoothed_var_actual[[tt]] <- final_n / (final_n - 2) * mean_var_scale
    }
  }
  list(
    s = s,
    D_star = D_star,
    B_star = B_star,
    smoothed_mean = smoothed_mean,
    smoothed_var_actual = smoothed_var_actual,
    final_n = final_n,
    final_S = final_S,
    stabilization = list(calls = NA_integer_, cov_projected = NA_integer_)
  )
}

app_glofas_structural_dlm_smooth <- function(sequences, filter, backend = NULL) {
  backend <- app_glofas_structural_dlm_backend(backend %||% sequences$cfg$backend)
  if (identical(backend, "r")) return(app_glofas_structural_dlm_smooth_r(sequences, filter))
  app_glofas_structural_dlm_load_cpp()
  out <- glofas_structural_dlm_smooth_backward_cpp(
    F_mat = as.matrix(sequences$F_mat),
    G_array = as.array(sequences$G_array),
    a = as.matrix(filter$a),
    m = as.matrix(filter$m),
    R_star = as.array(filter$R_star),
    C_star = as.array(filter$C_star),
    n = as.numeric(filter$n),
    S = as.numeric(filter$S),
    cov_eig_floor = as.numeric(sequences$cfg$cov_eig_floor),
    cov_eig_cap = as.numeric(sequences$cfg$cov_eig_cap),
    cov_diag_jitter = as.numeric(sequences$cfg$cov_diag_jitter)
  )
  for (nm in c("smoothed_mean", "smoothed_var_actual", "final_n", "final_S")) {
    out[[nm]] <- as.numeric(out[[nm]])
  }
  out
}

app_glofas_structural_dlm_component_matrix <- function(state_mat, sequences) {
  state_map <- sequences$state_map
  X <- sequences$covariates_scaled
  Tn <- ncol(state_mat)
  level <- as.numeric(state_mat[state_map$level, ])
  seasonal_1 <- as.numeric(state_mat[state_map$seasonal_1[[1L]], ])
  seasonal_2 <- as.numeric(state_mat[state_map$seasonal_2[[1L]], ])
  seasonal_67 <- as.numeric(state_mat[state_map$seasonal_67[[1L]], ])
  transfer <- rep(0, Tn)
  if (length(state_map$transfer)) transfer <- as.numeric(state_mat[state_map$transfer, ])
  direct <- rep(0, Tn)
  if (length(state_map$readout_coefficients)) {
    beta_direct <- t(state_mat[state_map$readout_coefficients, , drop = FALSE])
    direct <- rowSums(beta_direct * X)
  }
  mean <- level + seasonal_1 + seasonal_2 + seasonal_67 + transfer + direct
  data.frame(
    date = sequences$dates,
    y = sequences$y,
    dlm_level = level,
    dlm_seasonal_1 = seasonal_1,
    dlm_seasonal_2 = seasonal_2,
    dlm_seasonal_67 = seasonal_67,
    dlm_transfer = transfer,
    dlm_direct_covariate = direct,
    dlm_mean = mean,
    stringsAsFactors = FALSE
  )
}

app_glofas_structural_dlm_components <- function(fit, timing = "filtered") {
  timing <- tolower(trimws(as.character(timing %||% "filtered")[[1L]]))
  if (!timing %in% c("one_step_forecast", "filtered", "smoothed")) {
    stop("Structural DLM component timing must be one_step_forecast, filtered, or smoothed.", call. = FALSE)
  }
  state_mat <- switch(
    timing,
    one_step_forecast = fit$filter$a,
    filtered = fit$filter$m,
    smoothed = {
      if (is.null(fit$smoother) || is.null(fit$smoother$s)) {
        stop("Structural DLM fit does not contain smoothed states.", call. = FALSE)
      }
      fit$smoother$s
    }
  )
  out <- app_glofas_structural_dlm_component_matrix(state_mat, fit$sequences)
  out$timing <- timing
  out$one_step_mean <- as.numeric(fit$filter$f)
  out$filtered_mean <- as.numeric(fit$filter$fitted_mean)
  out$smoothed_mean <- if (!is.null(fit$smoother) && !is.null(fit$smoother$smoothed_mean)) {
    as.numeric(fit$smoother$smoothed_mean)
  } else {
    rep(NA_real_, nrow(out))
  }
  out$dlm_residual <- as.numeric(fit$sequences$y) - as.numeric(fit$filter$f)
  out$dlm_filtered_residual <- as.numeric(fit$sequences$y) - as.numeric(fit$filter$fitted_mean)
  out$dlm_smoothed_residual <- as.numeric(fit$sequences$y) - as.numeric(out$smoothed_mean)
  out$pred_sd <- sqrt(pmax(as.numeric(fit$filter$pred_var_actual), .Machine$double.eps))
  out$fitted_sd <- sqrt(pmax(as.numeric(fit$filter$fitted_var_actual), .Machine$double.eps))
  out$smoothed_sd <- if (!is.null(fit$smoother) && !is.null(fit$smoother$smoothed_var_actual)) {
    sqrt(pmax(as.numeric(fit$smoother$smoothed_var_actual), .Machine$double.eps))
  } else {
    rep(NA_real_, nrow(out))
  }
  if (identical(timing, "one_step_forecast")) out$dlm_mean <- out$one_step_mean
  if (identical(timing, "filtered")) out$dlm_mean <- out$filtered_mean
  if (identical(timing, "smoothed")) out$dlm_mean <- out$smoothed_mean
  out
}

app_glofas_structural_dlm_crps <- function(y, mu, sd) {
  y <- as.numeric(y)
  mu <- as.numeric(mu)
  sd <- pmax(as.numeric(sd), .Machine$double.eps)
  z <- (y - mu) / sd
  sd * (z * (2 * stats::pnorm(z) - 1) + 2 * stats::dnorm(z) - 1 / sqrt(pi))
}

app_glofas_structural_dlm_score_vector <- function(y, mu, sd, prefix = "") {
  err <- as.numeric(mu) - as.numeric(y)
  out <- data.frame(
    mean_crps = mean(app_glofas_structural_dlm_crps(y, mu, sd), na.rm = TRUE),
    mae = mean(abs(err), na.rm = TRUE),
    rmse = sqrt(mean(err^2, na.rm = TRUE)),
    mean_sd = mean(as.numeric(sd), na.rm = TRUE),
    stringsAsFactors = FALSE
  )
  if (nzchar(prefix)) names(out) <- paste0(prefix, names(out))
  out
}

app_glofas_structural_dlm_score <- function(fit) {
  y <- fit$sequences$y
  pred_sd <- sqrt(pmax(as.numeric(fit$filter$pred_var_actual), .Machine$double.eps))
  fitted_sd <- sqrt(pmax(as.numeric(fit$filter$fitted_var_actual), .Machine$double.eps))
  smoothed_sd <- if (!is.null(fit$smoother) && !is.null(fit$smoother$smoothed_var_actual)) {
    sqrt(pmax(as.numeric(fit$smoother$smoothed_var_actual), .Machine$double.eps))
  } else {
    rep(NA_real_, length(y))
  }
  cbind(
    data.frame(
      covariate_mode = fit$cfg$covariate_mode,
      n_rows = length(y),
      state_dim = fit$sequences$state_map$p,
      lambda = as.numeric(fit$cfg$lambda),
      period = as.numeric(fit$cfg$period),
      stringsAsFactors = FALSE
    ),
    app_glofas_structural_dlm_score_vector(y, fit$filter$f, pred_sd, prefix = "one_step_"),
    app_glofas_structural_dlm_score_vector(y, fit$filter$fitted_mean, fitted_sd, prefix = "filtered_"),
    app_glofas_structural_dlm_score_vector(y, fit$smoother$smoothed_mean, smoothed_sd, prefix = "smoothed_")
  )
}

app_glofas_structural_dlm_fit <- function(
  y,
  dates,
  covariates = NULL,
  cfg = app_glofas_structural_dlm_make_cfg(),
  backend = NULL
) {
  cfg <- app_glofas_structural_dlm_make_cfg(cfg)
  sequences <- app_glofas_structural_dlm_build_sequences(y, dates, covariates, cfg)
  filter <- app_glofas_structural_dlm_filter(sequences, backend = backend %||% cfg$backend)
  smoother <- app_glofas_structural_dlm_smooth(sequences, filter, backend = backend %||% cfg$backend)
  out <- list(
    type = "glofas_structural_normal_dlm",
    version = "0.2",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    cfg = cfg,
    sequences = sequences,
    filter = filter,
    smoother = smoother,
    score = NULL
  )
  out$score <- app_glofas_structural_dlm_score(out)
  class(out) <- c("glofas_structural_normal_dlm_fit", "list")
  out
}

app_glofas_structural_dlm_prepare_usgs_panel <- function(cfg, manifest = NULL, schema = NULL) {
  manifest <- manifest %||% app_load_input_manifest(app_config_path(cfg, "input_manifest"), required = TRUE)
  schema <- schema %||% app_read_yaml(app_config_path(cfg, "schema"))
  panel <- app_build_application_panel(cfg, manifest, schema)
  cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
  if (nrow(cutoffs) != 1L) {
    stop("Structural DLM diagnostics expect exactly one enabled cutoff.", call. = FALSE)
  }
  cutoff <- cutoffs[1L, , drop = FALSE]
  panel$target_date <- as.Date(panel$target_date)
  hist <- panel[
    app_as_bool_vec(panel$is_retrospective) &
      panel$target_date >= as.Date(cutoff$train_start[[1L]]) &
      panel$target_date <= as.Date(cutoff$train_end[[1L]]) &
      is.finite(panel$y_transformed),
    ,
    drop = FALSE
  ]
  hist <- hist[order(hist$target_date), , drop = FALSE]
  if (!nrow(hist)) stop("No historical USGS rows available for structural DLM.", call. = FALSE)
  if (anyDuplicated(hist$target_date)) {
    stop("Structural DLM historical panel must have one row per target_date.", call. = FALSE)
  }
  hist <- app_copy_covariate_attrs(hist, panel)
  list(panel = hist, cutoff = cutoff)
}

app_glofas_structural_dlm_covariates_from_panel <- function(panel, variables = c("ppt", "soil")) {
  timeline <- app_panel_covariate_timeline(panel, required = TRUE)
  timeline$date <- as.Date(timeline$date)
  needed <- c("date", variables)
  app_check_required_columns(timeline, needed, "structural DLM covariate timeline")
  timeline[, needed, drop = FALSE]
}

app_glofas_structural_dlm_fit_from_glofas_config <- function(
  base_cfg,
  mode = "transfer_only",
  backend = NULL,
  panel_bundle = NULL,
  dlm_cfg = list()
) {
  bundle <- panel_bundle %||% app_glofas_structural_dlm_prepare_usgs_panel(base_cfg)
  panel <- bundle$panel
  cfg <- do.call(
    app_glofas_structural_dlm_make_cfg,
    c(list(covariate_mode = mode, backend = backend %||% "cpp"), dlm_cfg)
  )
  covariates <- if (app_glofas_structural_dlm_uses_transfer(cfg$covariate_mode) ||
                    app_glofas_structural_dlm_uses_readout_covariates(cfg$covariate_mode)) {
    app_glofas_structural_dlm_covariates_from_panel(panel, cfg$covariates)
  } else {
    NULL
  }
  fit <- app_glofas_structural_dlm_fit(
    y = panel$y_transformed,
    dates = panel$target_date,
    covariates = covariates,
    cfg = cfg,
    backend = backend %||% cfg$backend
  )
  fit$cutoff <- bundle$cutoff
  fit
}

app_glofas_structural_dlm_augment_panel <- function(panel, components, timing = "filtered") {
  timing <- tolower(trimws(as.character(timing %||% "filtered")[[1L]]))
  components <- components[as.character(components$timing) == timing, , drop = FALSE]
  if (!nrow(components)) stop(sprintf("No DLM component rows found for timing '%s'.", timing), call. = FALSE)
  comp_cols <- grep("^dlm_", names(components), value = TRUE)
  keep <- components[, c("date", comp_cols), drop = FALSE]
  names(keep)[names(keep) == "date"] <- "target_date"
  if (anyDuplicated(as.Date(keep$target_date))) {
    stop("DLM augmentation requires one component row per target_date.", call. = FALSE)
  }
  panel$.dlm_original_row_id <- seq_len(nrow(panel))
  panel$target_date <- as.Date(panel$target_date)
  keep$target_date <- as.Date(keep$target_date)
  out <- merge(panel, keep, by = "target_date", all.x = TRUE, sort = FALSE)
  out <- out[order(out$.dlm_original_row_id), , drop = FALSE]
  out$.dlm_original_row_id <- NULL
  retro <- if ("is_retrospective" %in% names(out)) {
    app_as_bool_vec(out$is_retrospective)
  } else {
    rep(TRUE, nrow(out))
  }
  if (any(!is.finite(out$dlm_mean[retro]), na.rm = TRUE)) {
    stop("DLM augmentation produced non-finite historical dlm_mean values.", call. = FALSE)
  }
  app_copy_covariate_attrs(out, panel)
}

app_glofas_structural_dlm_default_feature_families <- function() {
  c(
    "dlm_level",
    "dlm_seasonal_1",
    "dlm_seasonal_2",
    "dlm_seasonal_67",
    "dlm_transfer",
    "dlm_mean",
    "dlm_residual"
  )
}

app_glofas_structural_dlm_lag_matrix <- function(
  panel,
  anchor_dates,
  lags,
  feature_families = app_glofas_structural_dlm_default_feature_families(),
  standardize = TRUE,
  scale_params = NULL
) {
  anchor_dates <- as.Date(anchor_dates)
  lags <- app_parse_lag_spec(lags, default = integer(0), allow_zero = TRUE, label = "DLM feature lags")
  if (!length(lags)) return(list(X = NULL, scale_params = scale_params, feature_info = data.frame()))
  feature_families <- as.character(feature_families)
  missing <- setdiff(feature_families, names(panel))
  if (length(missing)) {
    stop(sprintf("Panel is missing DLM feature columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  if ("dlm_residual" %in% feature_families && any(lags == 0L)) {
    stop("dlm_residual_lag_0 is forbidden because it leaks the observed response.", call. = FALSE)
  }
  timeline <- panel[, c("target_date", feature_families), drop = FALSE]
  timeline$target_date <- as.Date(timeline$target_date)
  timeline <- timeline[order(timeline$target_date), , drop = FALSE]
  timeline <- timeline[!duplicated(timeline$target_date), , drop = FALSE]
  cols <- list()
  names_out <- character()
  vars_out <- character()
  lags_out <- integer()
  for (family in feature_families) {
    for (L in lags) {
      idx <- match(anchor_dates - L, timeline$target_date)
      if (any(is.na(idx))) {
        missing_dates <- sort(unique(anchor_dates[is.na(idx)] - L))
        stop(sprintf("%s_lag_%d is missing dates: %s", family, L, paste(missing_dates, collapse = ", ")), call. = FALSE)
      }
      values <- as.numeric(timeline[[family]][idx])
      if (any(!is.finite(values))) {
        stop(sprintf("%s_lag_%d contains non-finite values.", family, L), call. = FALSE)
      }
      cols[[length(cols) + 1L]] <- values
      names_out <- c(names_out, sprintf("%s_lag_%d", family, L))
      vars_out <- c(vars_out, family)
      lags_out <- c(lags_out, as.integer(L))
    }
  }
  X <- do.call(cbind, cols)
  colnames(X) <- names_out
  storage.mode(X) <- "double"
  if (isTRUE(standardize)) {
    if (is.null(scale_params)) {
      center <- colMeans(X)
      scale <- apply(X, 2L, stats::sd)
      scale[!is.finite(scale) | scale <= 0] <- 1
      scale_params <- list(columns = names_out, center = center, scale = scale)
    }
    center <- as.numeric(scale_params$center[names_out])
    scale <- as.numeric(scale_params$scale[names_out])
    if (any(!is.finite(center)) || any(!is.finite(scale)) || any(scale <= 0)) {
      stop("Invalid DLM feature scaling parameters.", call. = FALSE)
    }
    X <- sweep(X, 2L, center, "-")
    X <- sweep(X, 2L, scale, "/")
  } else if (is.null(scale_params)) {
    scale_params <- list(columns = names_out, center = rep(0, length(names_out)), scale = rep(1, length(names_out)))
  }
  info <- app_feature_info_rows(
    names_out,
    block = "dlm_component_lag",
    variable = vars_out,
    lag = lags_out,
    anchor = "target_date"
  )
  info$column_index <- seq_len(nrow(info))
  info <- info[, c("column_index", setdiff(names(info), "column_index")), drop = FALSE]
  list(X = X, scale_params = scale_params, feature_info = info)
}

app_glofas_structural_dlm_feature_contract <- function(
  output_lags,
  feature_families = app_glofas_structural_dlm_default_feature_families(),
  timing = "filtered",
  placement = "reservoir_input"
) {
  output_lags <- app_parse_lag_spec(output_lags, allow_zero = FALSE, label = "DLM feature output_lags")
  timing <- tolower(trimws(as.character(timing %||% "filtered")[[1L]]))
  if (!timing %in% c("one_step_forecast", "filtered", "smoothed")) {
    stop("DLM feature timing must be one_step_forecast, filtered, or smoothed.", call. = FALSE)
  }
  placement <- as.character(placement)
  if (identical(timing, "smoothed") && !identical(placement, "diagnostic")) {
    stop("Smoothed DLM components are diagnostic-only and cannot be declared as predictive features.", call. = FALSE)
  }
  list(
    version = "glofas_structural_dlm_augmented_v0.1",
    timing = timing,
    placement = placement,
    feature_families = as.character(feature_families),
    lags = output_lags,
    leakage_rules = list(
      residual_lag0_forbidden = TRUE,
      smoothed_components_predictive_forbidden = TRUE
    )
  )
}

app_glofas_structural_dlm_plot_fit <- function(
  fit,
  path,
  last_n = 200L,
  timing = "filtered"
) {
  app_ensure_dir(dirname(path))
  comp <- app_glofas_structural_dlm_components(fit, timing = timing)
  timing_label <- gsub("_", " ", as.character(timing))
  last_n <- as.integer(last_n)
  if (!is.finite(last_n) || last_n < 1L) last_n <- 200L
  idx_last <- utils::tail(seq_len(nrow(comp)), min(last_n, nrow(comp)))
  grDevices::pdf(path, width = 11, height = 8.5)
  oldpar <- graphics::par(no.readonly = TRUE)
  on.exit({
    graphics::par(oldpar)
    grDevices::dev.off()
  }, add = TRUE)
  graphics::par(mfrow = c(2L, 1L), mar = c(4, 4, 3, 1))
  graphics::plot(comp$date, comp$y, type = "l", col = "grey30", lwd = 1.3,
                 xlab = "Date", ylab = "Transformed USGS",
                 main = sprintf("Structural Normal DLM %s fit, %s, full history", timing_label, fit$cfg$covariate_mode))
  graphics::lines(comp$date, comp$dlm_mean, col = "#2563eb", lwd = 1.2)
  graphics::legend("topleft", legend = c("Observed USGS", "DLM mean"),
                   col = c("grey30", "#2563eb"), lwd = c(1.3, 1.2), bty = "n")
  graphics::plot(comp$date[idx_last], comp$y[idx_last], type = "l", col = "grey30", lwd = 1.4,
                 xlab = "Date", ylab = "Transformed USGS",
                 main = sprintf("Last %d observations up to cutoff", length(idx_last)))
  graphics::lines(comp$date[idx_last], comp$dlm_mean[idx_last], col = "#2563eb", lwd = 1.3)
  graphics::legend("topleft", legend = c("Observed USGS", "DLM mean"),
                   col = c("grey30", "#2563eb"), lwd = c(1.4, 1.3), bty = "n")
  invisible(path)
}

app_glofas_structural_dlm_plot_components <- function(fit, path, last_n = 200L, timing = "filtered") {
  app_ensure_dir(dirname(path))
  comp <- app_glofas_structural_dlm_components(fit, timing = timing)
  timing <- tolower(trimws(as.character(timing %||% "filtered")[[1L]]))
  residual_col <- switch(
    timing,
    one_step_forecast = "dlm_residual",
    filtered = "dlm_filtered_residual",
    smoothed = "dlm_smoothed_residual",
    "dlm_filtered_residual"
  )
  residual_label <- switch(
    timing,
    one_step_forecast = "One-step residual",
    filtered = "Filtered residual",
    smoothed = "Smoothed residual",
    "Residual"
  )
  last_n <- as.integer(last_n)
  idx <- utils::tail(seq_len(nrow(comp)), min(last_n, nrow(comp)))
  grDevices::pdf(path, width = 11, height = 8.5)
  oldpar <- graphics::par(no.readonly = TRUE)
  on.exit({
    graphics::par(oldpar)
    grDevices::dev.off()
  }, add = TRUE)
  graphics::par(mfrow = c(3L, 1L), mar = c(4, 4, 3, 1))
  graphics::matplot(
    comp$date[idx],
    cbind(comp$dlm_level[idx], comp$dlm_seasonal_1[idx], comp$dlm_seasonal_2[idx], comp$dlm_seasonal_67[idx]),
    type = "l", lty = 1, lwd = 1.2,
    col = c("#111827", "#059669", "#d97706", "#7c3aed"),
    xlab = "Date", ylab = "Component",
    main = sprintf("DLM %s trend and seasonal components, last %d", gsub("_", " ", timing), length(idx))
  )
  graphics::legend("topleft", legend = c("Level", "Seasonal 1", "Seasonal 2", "Seasonal 67"),
                   col = c("#111827", "#059669", "#d97706", "#7c3aed"), lty = 1, lwd = 1.2, bty = "n")
  graphics::matplot(
    comp$date[idx],
    cbind(comp$dlm_transfer[idx], comp$dlm_direct_covariate[idx]),
    type = "l", lty = 1, lwd = 1.2,
    col = c("#dc2626", "#0891b2"),
    xlab = "Date", ylab = "Component",
    main = "Transfer and direct covariate contribution"
  )
  graphics::legend("topleft", legend = c("Transfer", "Direct covariate"),
                   col = c("#dc2626", "#0891b2"), lty = 1, lwd = 1.2, bty = "n")
  graphics::plot(comp$date[idx], comp[[residual_col]][idx], type = "h", col = "#4b5563",
                 xlab = "Date", ylab = residual_label,
                 main = residual_label)
  graphics::abline(h = 0, lty = 2, col = "grey50")
  invisible(path)
}
