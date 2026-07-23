# GloFAS discrepancy-calibration Q-DESN fit adapter.

app_fit_qdesn_discrepancy <- function(panel, cfg, model_row, cutoff_row = NULL, X_base = NULL, drop = NULL) {
  if (app_is_latent_path_contract(cfg, model_row)) {
    stop(
      paste(
        "app_fit_qdesn_discrepancy() implements the origin-state bridge.",
        "The latent-path ensemble-likelihood model requires a separate",
        "latent-path fitter because future reservoir states depend on the",
        "latent future USGS path."
      ),
      call. = FALSE
    )
  }
  engine_report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = TRUE,
    stop_on_failure = TRUE
  )
  engine <- engine_report$engine
  fit_fun <- get("qdesn_fit_discrepancy", envir = engine_report$env, inherits = FALSE)
  contract <- app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
  include_ensemble_training <- identical(contract$prediction_unit, "posterior_draw") &&
    identical(contract$q_g_source, "posterior_model_quantile")

  design <- app_make_glofas_discrepancy_data(
    panel,
    cfg,
    cutoff_row = cutoff_row,
    model_row = model_row,
    X_base = X_base,
    include_ensemble_training = include_ensemble_training,
    feature_strategy = contract$discrepancy_feature_strategy,
    drop = drop
  )
  p0 <- as.numeric(model_row$quantile_level[[1L]])
  method <- app_normalize_qdesn_method(model_row$inference_method[[1L]])
  likelihood_family <- app_model_row_likelihood_family(model_row, cfg)
  prior <- app_map_qdesn_prior(model_row$coefficient_prior[[1L]])
  seed <- suppressWarnings(as.integer(app_model_row_value(model_row, "reservoir_seed", cfg$reservoir$seed %||% 20260511L)))
  if (!is.finite(seed)) seed <- as.integer(cfg$reservoir$seed %||% 20260511L)

  mcmc_cfg <- cfg$inference$mcmc %||% list()
  mcmc_args <- list(
    n_burn = as.integer(mcmc_cfg$burn_in %||% mcmc_cfg$n_burn %||% 1000L),
    n_mcmc = as.integer(mcmc_cfg$n_mcmc %||% mcmc_cfg$n_iter %||% 1000L),
    thin = as.integer(mcmc_cfg$thin %||% 1L),
    seed = seed,
    beta_prior_type = prior,
    beta_rhs = list(
      tau0 = as.numeric(mcmc_cfg$rhs_tau0 %||% 1),
      s2 = as.numeric(mcmc_cfg$rhs_slab_s2 %||% 4),
      a_zeta = as.numeric(mcmc_cfg$rhs_a_zeta %||% 2),
      b_zeta = as.numeric(mcmc_cfg$rhs_b_zeta %||% 4),
      intercept_prec = as.numeric(mcmc_cfg$intercept_prec %||% 1.0e-9),
      n_inner = as.integer(mcmc_cfg$rhs_n_inner %||% 1L)
    ),
    prior_sigma = list(
      a = as.numeric(mcmc_cfg$sigma_a %||% 2),
      b = as.numeric(mcmc_cfg$sigma_b %||% 1)
    )
  )
  vb_args <- app_make_qdesn_discrepancy_vb_args(
    cfg,
    prior = prior,
    seed = seed,
    likelihood_family = likelihood_family
  )

  fit_call <- list(
    z = design$z,
    H = design$H,
    source = design$source,
    p0 = p0,
    method = method,
    likelihood_family = likelihood_family,
    beta_prior_type = prior,
    source_levels = c("Y", "G"),
    intercept_index = design$intercept_index,
    mcmc_args = mcmc_args
  )
  if (identical(method, "vb")) fit_call$vb_args <- vb_args
  fit <- do.call(fit_fun, fit_call)

  list(
    fit_id = model_row$fit_id[[1L]],
    model_id = model_row$model_id[[1L]],
    model_family = model_row$model_family[[1L]],
    quantile_level = p0,
    method = method,
    likelihood_family = likelihood_family,
    coefficient_prior = prior,
    fit = fit,
    design = design,
    design_summary = app_discrepancy_design_summary(design),
    engine = engine,
    mcmc_args = mcmc_args,
    vb_args = vb_args,
    status = "completed",
    message = "fit completed"
  )
}

app_make_qdesn_discrepancy_vb_args <- function(cfg, prior, seed = NULL, likelihood_family = NULL) {
  vb_cfg <- cfg$inference$vb_ld %||% list()
  mcmc_cfg <- cfg$inference$mcmc %||% list()
  vb_diag_cfg <- vb_cfg$diagnostics %||% list()
  seed <- seed %||% cfg$reservoir$seed %||% 20260511L
  likelihood_family <- tolower(as.character(likelihood_family %||% cfg$inference$likelihood_family %||% "al"))
  max_iter <- as.integer(vb_cfg$max_iter %||% 200L)
  max_iter_hard_cap <- as.integer(vb_cfg$max_iter_hard_cap %||% 500L)
  if (!is.finite(max_iter) || max_iter < 1L) {
    stop("VB max_iter must be a positive integer.", call. = FALSE)
  }
  if (!is.finite(max_iter_hard_cap) || max_iter_hard_cap < 1L) {
    stop("VB max_iter_hard_cap must be a positive integer.", call. = FALSE)
  }
  if (max_iter > max_iter_hard_cap) {
    stop(
      sprintf(
        "Configured VB max_iter = %d exceeds the hard cap of %d. Reduce max_iter or explicitly revise the launch policy.",
        max_iter,
        max_iter_hard_cap
      ),
      call. = FALSE
    )
  }
  out <- list(
    max_iter = max_iter,
    max_iter_hard_cap = max_iter_hard_cap,
    min_iter_elbo = as.integer(vb_cfg$min_iter_elbo %||% 10L),
    tol = as.numeric(vb_cfg$tol %||% 1.0e-4),
    tol_par = as.numeric(vb_cfg$tol_par %||% vb_cfg$tol %||% 1.0e-4),
    n_samp_xi = as.integer(vb_cfg$n_samp_xi %||% 500L),
    n_draws = as.integer(vb_cfg$n_draws %||% 2000L),
    seed = as.integer(seed),
    beta_prior_type = prior,
    beta_rhs = list(
      tau0 = as.numeric(vb_cfg$rhs_tau0 %||% mcmc_cfg$rhs_tau0 %||% 1),
      s2 = as.numeric(vb_cfg$rhs_slab_s2 %||% mcmc_cfg$rhs_slab_s2 %||% 4),
      a_zeta = as.numeric(vb_cfg$rhs_a_zeta %||% mcmc_cfg$rhs_a_zeta %||% 2),
      b_zeta = as.numeric(vb_cfg$rhs_b_zeta %||% mcmc_cfg$rhs_b_zeta %||% 4),
      intercept_prec = as.numeric(vb_cfg$intercept_prec %||% mcmc_cfg$intercept_prec %||% 1.0e-9)
    ),
    alpha_rhs = list(
      tau0 = as.numeric(vb_cfg$rhs_alpha_tau0 %||% vb_cfg$rhs_tau0 %||% mcmc_cfg$rhs_alpha_tau0 %||% mcmc_cfg$rhs_tau0 %||% 1),
      s2 = as.numeric(vb_cfg$rhs_alpha_slab_s2 %||% vb_cfg$rhs_slab_s2 %||% mcmc_cfg$rhs_alpha_slab_s2 %||% mcmc_cfg$rhs_slab_s2 %||% 4),
      a_zeta = as.numeric(vb_cfg$rhs_alpha_a_zeta %||% vb_cfg$rhs_a_zeta %||% mcmc_cfg$rhs_alpha_a_zeta %||% mcmc_cfg$rhs_a_zeta %||% 2),
      b_zeta = as.numeric(vb_cfg$rhs_alpha_b_zeta %||% vb_cfg$rhs_b_zeta %||% mcmc_cfg$rhs_alpha_b_zeta %||% mcmc_cfg$rhs_b_zeta %||% 4),
      intercept_prec = as.numeric(vb_cfg$intercept_prec %||% mcmc_cfg$intercept_prec %||% 1.0e-9)
    ),
    prior_sigma = list(
      a = as.numeric(vb_cfg$sigma_a %||% mcmc_cfg$sigma_a %||% 2),
      b = as.numeric(vb_cfg$sigma_b %||% mcmc_cfg$sigma_b %||% 1)
    ),
    rhs = list(
      freeze_tau_warmup_iters = as.integer(vb_cfg$rhs_freeze_tau_warmup_iters %||% 0L),
      update_every = as.integer(vb_cfg$rhs_update_every %||% 1L),
      min_tau_updates = as.integer(vb_cfg$rhs_min_tau_updates %||% 0L)
    ),
    diagnostics = list(
      elbo_check_frequency = as.integer(vb_cfg$elbo_check_frequency %||% 10L),
      save_elbo_trace = app_as_bool(vb_cfg$save_elbo_trace %||% TRUE),
      save_parameter_summaries = app_as_bool(vb_cfg$save_parameter_summaries %||% TRUE),
      profile_substeps = app_as_bool(vb_diag_cfg$profile_substeps %||% vb_cfg$profile_substeps %||% FALSE),
      trace_iterations = app_as_bool(vb_diag_cfg$trace_iterations %||% vb_cfg$trace_iterations %||% FALSE)
    ),
    future_moment_strategy = tolower(as.character(vb_cfg$future_moment_strategy %||% "streamed_grouped")),
    future_update_strategy = tolower(as.character(vb_cfg$future_update_strategy %||% "linearized_delta")),
    future_objective_strategy = tolower(as.character(vb_cfg$future_objective_strategy %||% "grouped")),
    dense_debug_allowed = app_as_bool(vb_cfg$dense_debug_allowed %||% FALSE),
    ld_block_active = identical(likelihood_family, "exal")
  )
  if (!is.null(vb_cfg$chunking)) {
    out$chunking <- vb_cfg$chunking
  }
  if (!is.null(vb_cfg$warm_start)) {
    out$warm_start <- vb_cfg$warm_start
  }
  if (!is.null(vb_cfg$draw_backend) && nzchar(as.character(vb_cfg$draw_backend))) {
    out$draw_backend <- tolower(as.character(vb_cfg$draw_backend)[[1L]])
  }
  out
}

app_predict_qdesn_discrepancy <- function(result, panel, cfg, model_row) {
  if (app_is_latent_path_contract(cfg, model_row)) {
    stop(
      "app_predict_qdesn_discrepancy() is an origin-state bridge predictor; use the latent-path predictor for latent_path_ensemble_likelihood.",
      call. = FALSE
    )
  }
  required_result <- c("fit", "design", "fit_id", "model_id", "model_family", "quantile_level")
  missing_result <- setdiff(required_result, names(result))
  if (length(missing_result)) {
    stop(sprintf("Discrepancy prediction result is missing: %s", paste(missing_result, collapse = ", ")), call. = FALSE)
  }
  app_validate_glofas_discrepancy_data(result$design)
  fit <- result$fit
  design <- result$design
  if (is.null(fit$summary$theta_mean)) {
    stop("Discrepancy fit is missing theta_mean summary.", call. = FALSE)
  }
  contract <- app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
  if (!identical(contract$discrepancy_feature_strategy, "origin_state_pilot")) {
    stop(
      sprintf(
        "Discrepancy feature strategy '%s' is not implemented in the article adapter.",
        contract$discrepancy_feature_strategy
      ),
      call. = FALSE
    )
  }

  ens <- panel[panel$is_ensemble & is.finite(panel$g_transformed), , drop = FALSE]
  if (!nrow(ens)) {
    stop("No finite GloFAS ensemble rows are available for discrepancy prediction.", call. = FALSE)
  }
  ens$origin_date <- as.Date(ens$origin_date)
  ens$target_date <- as.Date(ens$target_date)

  base <- design$base_panel
  base$target_date <- as.Date(base$target_date)
  origin_key <- as.character(base$target_date)
  x_by_origin <- split(seq_len(nrow(base)), origin_key)

  theta <- as.numeric(fit$summary$theta_mean)
  alpha <- theta[design$alpha_index]
  X_alpha <- app_discrepancy_alpha_matrix(design)
  if (length(alpha) != ncol(X_alpha) || any(!is.finite(alpha))) {
    stop("Discrepancy coefficient summary is incompatible with the discrepancy feature block.", call. = FALSE)
  }

  keys <- unique(ens[, c("origin_date", "target_date", "horizon"), drop = FALSE])
  rows <- vector("list", nrow(keys))
  p0 <- as.numeric(result$quantile_level)
  k <- 1L
  for (j in seq_len(nrow(keys))) {
    origin <- as.character(keys$origin_date[[j]])
    idx_base <- x_by_origin[[origin]]
    if (!length(idx_base)) next
    idx_base <- idx_base[[1L]]
    x_origin <- X_alpha[idx_base, , drop = FALSE]
    discrepancy_hat <- as.numeric(x_origin %*% alpha)

    idx <- ens$origin_date == keys$origin_date[[j]] &
      ens$target_date == keys$target_date[[j]] &
      ens$horizon == keys$horizon[[j]]
    block <- ens[idx, , drop = FALSE]
    raw_glofas_quantile <- app_ensemble_quantile(block, p0)
    y_ref <- block$y_transformed[[which(is.finite(block$y_transformed))[1L]]]
    if (!is.finite(raw_glofas_quantile) || !is.finite(discrepancy_hat) || !is.finite(y_ref)) next

    rows[[k]] <- app_make_discrepancy_prediction_row(
      result = result,
      key_row = keys[j, , drop = FALSE],
      block = block,
      p0 = p0,
      q_g_hat = raw_glofas_quantile,
      d_g_hat = discrepancy_hat,
      feature_date = as.Date(origin),
      cfg = cfg
    )
    k <- k + 1L
  }
  rows <- rows[seq_len(k - 1L)]
  rows <- rows[!vapply(rows, is.null, logical(1L))]
  if (!length(rows)) {
    stop(
      paste(
        "No discrepancy predictions were produced. Check that forecast origins",
        "are present in the fitted retrospective design after washout."
      ),
      call. = FALSE
    )
  }
  out <- do.call(rbind, rows)
  app_validate_prediction_table_contract(out, final_launch = FALSE)
  out[order(out$origin_date, out$target_date, out$horizon), , drop = FALSE]
}

app_discrepancy_theta_draws <- function(fit) {
  theta <- fit$draws$theta %||% fit$samp.theta %||% NULL
  if (is.null(theta)) {
    stop("Discrepancy fit does not contain posterior theta draws.", call. = FALSE)
  }
  theta <- as.matrix(theta)
  storage.mode(theta) <- "double"
  if (!nrow(theta) || !ncol(theta) || any(!is.finite(theta))) {
    stop("Discrepancy posterior theta draws must be a finite numeric matrix.", call. = FALSE)
  }
  theta
}

app_discrepancy_sigma_draws <- function(fit) {
  sigma <- fit$draws$sigma %||% fit$samp.sigma %||% NULL
  if (is.null(sigma)) return(NULL)
  sigma <- as.matrix(sigma)
  storage.mode(sigma) <- "double"
  if (!nrow(sigma) || !ncol(sigma) || any(!is.finite(sigma))) {
    stop("Discrepancy posterior sigma draws must be a finite numeric matrix.", call. = FALSE)
  }
  sigma
}

app_mcmc_ess_univariate <- function(x, max_lag = NULL) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 4L || stats::sd(x) <= 0) return(as.numeric(n))
  max_lag <- as.integer(max_lag %||% min(100L, n - 1L))
  ac <- as.numeric(stats::acf(x, lag.max = max_lag, plot = FALSE)$acf)[-1L]
  if (!length(ac)) return(as.numeric(n))
  pos <- ac[ac > 0]
  if (!length(pos)) return(as.numeric(n))
  ess <- n / (1 + 2 * sum(pos))
  max(1, min(n, ess))
}

app_mcmc_ess_summary <- function(draws) {
  draws <- as.matrix(draws)
  ess <- apply(draws, 2L, app_mcmc_ess_univariate)
  c(
    min = min(ess, na.rm = TRUE),
    median = stats::median(ess, na.rm = TRUE)
  )
}

app_discrepancy_fit_diagnostics <- function(result) {
  theta <- app_discrepancy_theta_draws(result$fit)
  sigma <- app_discrepancy_sigma_draws(result$fit)
  beta <- theta[, result$design$beta_index, drop = FALSE]
  alpha <- theta[, result$design$alpha_index, drop = FALSE]
  beta_norm <- sqrt(rowSums(beta^2))
  alpha_norm <- sqrt(rowSums(alpha^2))
  is_mcmc <- identical(tolower(as.character(result$method %||% "")), "mcmc")
  theta_ess <- if (is_mcmc) app_mcmc_ess_summary(theta) else c(min = NA_real_, median = NA_real_)
  sigma_ess <- if (is_mcmc && !is.null(sigma)) app_mcmc_ess_summary(sigma) else c(min = NA_real_, median = NA_real_)
  sigma_means <- if (!is.null(sigma)) colMeans(sigma) else numeric()
  sigma_sds <- if (!is.null(sigma)) apply(sigma, 2L, stats::sd) else numeric()
  sigma_value <- function(x, name) {
    if (!length(x)) return(NA_real_)
    idx <- match(name, names(x))
    if (is.na(idx)) return(NA_real_)
    as.numeric(x[[idx]])
  }

  data.frame(
    fit_id = result$fit_id,
    model_id = result$model_id,
    model_family = result$model_family,
    quantile_level = result$quantile_level,
    method = result$method %||% NA_character_,
    likelihood_family = result$likelihood_family %||% NA_character_,
    coefficient_prior = result$coefficient_prior %||% NA_character_,
    n_draws = nrow(theta),
    n_theta = ncol(theta),
    n_beta = ncol(beta),
    n_alpha = ncol(alpha),
    finite_theta = all(is.finite(theta)),
    finite_sigma = if (!is.null(sigma)) all(is.finite(sigma)) else NA,
    beta_norm_mean = mean(beta_norm),
    beta_norm_sd = stats::sd(beta_norm),
    alpha_norm_mean = mean(alpha_norm),
    alpha_norm_sd = stats::sd(alpha_norm),
    sigma_Y_mean = sigma_value(sigma_means, "sigma_Y"),
    sigma_G_mean = sigma_value(sigma_means, "sigma_G"),
    sigma_Y_sd = sigma_value(sigma_sds, "sigma_Y"),
    sigma_G_sd = sigma_value(sigma_sds, "sigma_G"),
    theta_ess_min = unname(theta_ess[["min"]]),
    theta_ess_median = unname(theta_ess[["median"]]),
    sigma_ess_min = unname(sigma_ess[["min"]]),
    sigma_ess_median = unname(sigma_ess[["median"]]),
    max_abs_theta = max(abs(theta)),
    vb_converged = app_discrepancy_vb_diag_value(result$fit, "converged"),
    vb_iterations = app_discrepancy_vb_diag_value(result$fit, "iterations"),
    vb_runtime_seconds = app_discrepancy_vb_diag_value(result$fit, "runtime_seconds"),
    vb_elbo_final = app_discrepancy_vb_diag_value(result$fit, "elbo_final"),
    vb_elbo_relative_change = app_discrepancy_vb_diag_value(result$fit, "elbo_relative_change"),
    vb_max_parameter_change = app_discrepancy_vb_diag_value(result$fit, "max_parameter_change"),
    stringsAsFactors = FALSE
  )
}

app_discrepancy_vb_diag_value <- function(fit, name) {
  candidates <- list(
    fit$vb_diagnostics,
    fit$diagnostics,
    fit$vb,
    fit$summary$vb_diagnostics
  )
  for (obj in candidates) {
    if (is.list(obj) && name %in% names(obj)) return(obj[[name]][[1L]])
  }
  NA
}

app_discrepancy_prediction_draw_checks <- function(draws, tolerance = 1.0e-8) {
  app_validate_posterior_draw_prediction_table(draws, tolerance = tolerance)
  err <- abs(as.numeric(draws$q_y_draw) - (as.numeric(draws$q_g_draw) - as.numeric(draws$d_g_draw)))
  key <- unique(draws[, c("fit_id", "model_id", "model_family", "quantile_level"), drop = FALSE])
  if (nrow(key) != 1L) {
    stop("Draw checks require one fit per draw table block.", call. = FALSE)
  }
  data.frame(
    key,
    n_draw_rows = nrow(draws),
    n_unique_draws = length(unique(draws$draw_id)),
    n_prediction_keys = nrow(unique(draws[, c("origin_date", "target_date", "horizon"), drop = FALSE])),
    max_identity_error = max(err),
    all_identity_errors_within_tolerance = all(err <= tolerance),
    finite_q_y = all(is.finite(draws$q_y_draw)),
    finite_q_g = all(is.finite(draws$q_g_draw)),
    finite_d_g = all(is.finite(draws$d_g_draw)),
    q_y_draw_min = min(draws$q_y_draw),
    q_y_draw_max = max(draws$q_y_draw),
    d_g_draw_min = min(draws$d_g_draw),
    d_g_draw_max = max(draws$d_g_draw),
    stringsAsFactors = FALSE
  )
}

app_prediction_contract_columns <- function(contract, model_family, n) {
  meta <- app_prediction_contract_metadata(contract, model_family = model_family)
  out <- meta[rep(1L, n), , drop = FALSE]
  rownames(out) <- NULL
  out
}

app_summarize_discrepancy_draw_predictions <- function(draws) {
  app_validate_posterior_draw_prediction_table(draws)
  key_cols <- c(
    "fit_id", "model_id", "model_family", "quantile_level", "origin_date",
    "target_date", "horizon", "prediction_contract", "contract_version",
    "forecast_scope", "q_g_source", "discrepancy_feature_strategy",
    "prediction_unit", "posterior_draw_contract", "posterior_predictive_sampling",
    "beyond_issued_horizon", "discrepancy_feature_date"
  )
  missing <- setdiff(key_cols, names(draws))
  if (length(missing)) {
    stop(sprintf("Posterior-draw table is missing summary keys: %s", paste(missing, collapse = ", ")), call. = FALSE)
  }
  draws$origin_date <- as.Date(draws$origin_date)
  draws$target_date <- as.Date(draws$target_date)
  draws$discrepancy_feature_date <- as.Date(draws$discrepancy_feature_date)
  draws$horizon <- as.integer(draws$horizon)
  draws$quantile_level <- as.numeric(draws$quantile_level)

  aggregate_formula <- stats::as.formula(paste(
    "cbind(q_y_draw, q_g_draw, d_g_draw, raw_glofas_quantile, y_reference) ~",
    paste(key_cols, collapse = " + ")
  ))
  out <- stats::aggregate(aggregate_formula, data = draws, FUN = mean, na.rm = TRUE)
  names(out)[names(out) == "q_y_draw"] <- "qhat"
  names(out)[names(out) == "q_g_draw"] <- "q_g_hat"
  names(out)[names(out) == "d_g_draw"] <- "d_g_hat"
  out$discrepancy_hat <- out$d_g_hat
  out$qhat_summary <- "posterior_draw_mean"
  out <- out[order(out$origin_date, out$target_date, out$horizon), , drop = FALSE]
  app_validate_prediction_table_contract(out, final_launch = FALSE)
  out
}

app_predict_qdesn_discrepancy_draws <- function(result, panel, cfg, model_row) {
  required_result <- c("fit", "design", "fit_id", "model_id", "model_family", "quantile_level")
  missing_result <- setdiff(required_result, names(result))
  if (length(missing_result)) {
    stop(sprintf("Discrepancy prediction result is missing: %s", paste(missing_result, collapse = ", ")), call. = FALSE)
  }
  contract <- app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
  if (!identical(contract$prediction_unit, "posterior_draw")) {
    stop("Posterior-draw discrepancy prediction requires prediction_unit = 'posterior_draw'.", call. = FALSE)
  }
  app_validate_glofas_discrepancy_data(result$design)
  pred_design <- app_make_glofas_prediction_design(
    design = result$design,
    panel = panel,
    cfg = cfg,
    model_row = model_row,
    contract = contract
  )

  theta <- app_discrepancy_theta_draws(result$fit)
  max_idx <- max(c(result$design$beta_index, result$design$alpha_index))
  if (ncol(theta) < max_idx) {
    stop("Discrepancy posterior theta draws are incompatible with the design indices.", call. = FALSE)
  }
  beta <- theta[, result$design$beta_index, drop = FALSE]
  alpha <- theta[, result$design$alpha_index, drop = FALSE]
  X_beta_pred <- app_discrepancy_prediction_beta_matrix(pred_design)
  X_alpha_pred <- app_discrepancy_prediction_alpha_matrix(pred_design)
  if (ncol(beta) != ncol(X_beta_pred) || ncol(alpha) != ncol(X_alpha_pred)) {
    stop("Posterior draw dimensions are incompatible with the prediction design.", call. = FALSE)
  }

  q_y_model <- beta %*% t(X_beta_pred)
  d_g <- alpha %*% t(X_alpha_pred)
  q_g_model <- q_y_model + d_g
  if (identical(contract$q_g_source, "posterior_model_quantile")) {
    q_g <- q_g_model
    q_y <- q_y_model
  } else {
    seed <- suppressWarnings(as.integer(app_model_row_value(model_row, "reservoir_seed", 20260511L)))
    if (!is.finite(seed)) seed <- 20260511L
    q_g <- app_prediction_qg_draw_matrix(
      panel = panel,
      row_info = pred_design$row_info,
      p0 = as.numeric(result$quantile_level),
      n_draws = nrow(theta),
      q_g_source = contract$q_g_source,
      seed = seed
    )
    q_y <- q_g - d_g
  }
  n_draw <- nrow(theta)
  n_pred <- nrow(X_beta_pred)
  idx <- expand.grid(
    draw_index = seq_len(n_draw),
    prediction_row = seq_len(n_pred),
    KEEP.OUT.ATTRS = FALSE
  )
  row_info <- pred_design$row_info[idx$prediction_row, , drop = FALSE]
  rownames(row_info) <- NULL

  draw_rows <- data.frame(
    draw_id = sprintf("%s:draw_%05d", result$fit_id, idx$draw_index),
    draw_index = idx$draw_index,
    fit_id = result$fit_id,
    model_id = result$model_id,
    model_family = result$model_family,
    quantile_level = as.numeric(result$quantile_level),
    origin_date = row_info$origin_date,
    target_date = row_info$target_date,
    horizon = row_info$horizon,
    discrepancy_feature_date = row_info$discrepancy_feature_date,
    q_y_draw = as.numeric(q_y[cbind(idx$draw_index, idx$prediction_row)]),
    q_g_draw = as.numeric(q_g[cbind(idx$draw_index, idx$prediction_row)]),
    d_g_draw = as.numeric(d_g[cbind(idx$draw_index, idx$prediction_row)]),
    q_y_model_draw = as.numeric(q_y_model[cbind(idx$draw_index, idx$prediction_row)]),
    q_g_model_draw = as.numeric(q_g_model[cbind(idx$draw_index, idx$prediction_row)]),
    raw_glofas_quantile = row_info$raw_glofas_quantile,
    y_reference = row_info$y_reference,
    prediction_design_hash = app_hash_prediction_design(pred_design),
    stringsAsFactors = FALSE
  )
  draw_rows <- cbind(
    draw_rows,
    app_prediction_contract_columns(contract, result$model_family, nrow(draw_rows))
  )
  app_validate_posterior_draw_prediction_table(draw_rows)

  list(
    draws = draw_rows[order(draw_rows$origin_date, draw_rows$target_date, draw_rows$horizon, draw_rows$draw_index), , drop = FALSE],
    summary = app_summarize_discrepancy_draw_predictions(draw_rows),
    prediction_design = pred_design,
    prediction_design_summary = app_prediction_design_summary(pred_design)
  )
}

app_discrepancy_status <- function(model_row, message = "discrepancy adapter not yet implemented") {
  data.frame(
    fit_id = model_row$fit_id[[1L]],
    model_id = model_row$model_id[[1L]],
    model_family = model_row$model_family[[1L]],
    quantile_level = as.numeric(model_row$quantile_level[[1L]]),
    inference_method = model_row$inference_method[[1L]],
    coefficient_prior = model_row$coefficient_prior[[1L]],
    status = "not_run",
    message = message,
    runtime_seconds = NA_real_,
    stringsAsFactors = FALSE
  )
}
