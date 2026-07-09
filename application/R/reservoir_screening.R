# Reservoir screening diagnostics for application Q-DESN designs.

app_validate_screening_decision <- function(x) {
  x <- as.character(x %||% "")[[1L]]
  allowed <- c("pass", "repair", "reject")
  if (!x %in% allowed) {
    stop(sprintf("Invalid reservoir screening decision '%s'.", x), call. = FALSE)
  }
  x
}

app_screening_decision_rank <- function(x) {
  x <- app_validate_screening_decision(x)
  switch(x, pass = 1L, repair = 2L, reject = 3L)
}

app_screening_worst_decision <- function(x) {
  x <- as.character(unlist(x %||% "pass", use.names = FALSE))
  x <- x[nzchar(x)]
  if (!length(x)) return("pass")
  x <- vapply(x, app_validate_screening_decision, character(1L))
  x[[which.max(vapply(x, app_screening_decision_rank, integer(1L)))]]
}

app_reservoir_diagnostic_config <- function(..., allow_unknown = FALSE) {
  defaults <- list(
    washout = 0L,
    drop_intercept = TRUE,
    intercept_tol = 1.0e-10,
    spectral_radius_tolerance = 0.10,
    require_spectral_radius_below_one = TRUE,
    strict_singular_norm_check = FALSE,
    singular_norm_max_n = 1000L,
    max_dense_spectral_radius_n = 512L,
    leaky_effective_radius_check = TRUE,
    initial_forgetting_ratio_max = 1.0e-2,
    initial_forgetting_final_max = NULL,
    dead_std_tol = 1.0e-8,
    dead_fraction_warn = 0.10,
    dead_fraction_reject = 0.30,
    saturation_check = TRUE,
    saturation_abs = 0.99,
    saturation_fraction_warn = 0.10,
    saturation_fraction_reject = 0.30,
    high_corr_thresholds = c(0.80, 0.90, 0.95, 0.98, 0.995),
    near_duplicate_corr_threshold = 0.995,
    near_duplicate_fraction_warn = 0.05,
    near_duplicate_fraction_reject = 0.20,
    corr_fraction_reject_at_090 = 0.50,
    relative_effective_rank_warn = 0.15,
    relative_effective_rank_reject = 0.05,
    condition_z_warn = 1.0e4,
    condition_z_reject = 1.0e6,
    condition_cov_warn = 1.0e8,
    condition_cov_reject = 1.0e12,
    eigen_tol = 1.0e-12,
    max_corr_features_full = 5000L,
    corr_block_size = 512L,
    corr_quantile_probs = c(0.50, 0.90, 0.95, 0.99),
    seed_fail_rate_reject = 0.30,
    seed_score_cv_warn = 0.20,
    random_state = NULL,
    validation_metric = "pinball",
    quantile_levels = NULL,
    cheap_readout = "ridge",
    cheap_ridge_lambda = 1.0e-4,
    reject_on_cheap_validation = FALSE,
    validation_relative_degradation_repair = 0.10,
    validation_relative_degradation_reject = 0.30,
    pruning_threshold = NULL,
    pruning_prefer = "variance",
    max_svd_features = Inf,
    max_svd_rows = Inf,
    large_matrix_policy = "blockwise"
  )
  overrides <- list(...)
  if (length(overrides)) {
    bad <- setdiff(names(overrides), names(defaults))
    if (length(bad) && !isTRUE(allow_unknown)) {
      stop(
        sprintf("Unknown reservoir diagnostic config field(s): %s.", paste(bad, collapse = ", ")),
        call. = FALSE
      )
    }
    for (nm in intersect(names(overrides), names(defaults))) defaults[[nm]] <- overrides[[nm]]
  }
  defaults$washout <- as.integer(defaults$washout %||% 0L)
  defaults$max_corr_features_full <- as.integer(defaults$max_corr_features_full)
  defaults$corr_block_size <- as.integer(defaults$corr_block_size)
  defaults$singular_norm_max_n <- as.integer(defaults$singular_norm_max_n)
  defaults$max_dense_spectral_radius_n <- as.integer(defaults$max_dense_spectral_radius_n)
  defaults$high_corr_thresholds <- sort(unique(as.numeric(defaults$high_corr_thresholds)))
  defaults$corr_quantile_probs <- sort(unique(as.numeric(defaults$corr_quantile_probs)))
  defaults$validation_metric <- tolower(as.character(defaults$validation_metric %||% "pinball")[[1L]])
  defaults$cheap_readout <- tolower(as.character(defaults$cheap_readout %||% "ridge")[[1L]])
  defaults$pruning_prefer <- match.arg(
    as.character(defaults$pruning_prefer %||% "variance")[[1L]],
    c("variance", "validation", "original_order")
  )
  defaults$large_matrix_policy <- match.arg(
    as.character(defaults$large_matrix_policy %||% "blockwise")[[1L]],
    c("blockwise", "subsample", "skip")
  )
  if (!is.finite(defaults$washout) || defaults$washout < 0L) {
    stop("Reservoir diagnostic washout must be a nonnegative integer.", call. = FALSE)
  }
  class(defaults) <- c("app_reservoir_diagnostic_config", "list")
  defaults
}

app_reservoir_as_config <- function(config = NULL) {
  if (inherits(config, "app_reservoir_diagnostic_config")) return(config)
  if (is.null(config)) return(app_reservoir_diagnostic_config())
  do.call(app_reservoir_diagnostic_config, config)
}

app_safe_sd <- function(x) {
  x <- as.numeric(x)
  if (length(x) <= 1L) return(0)
  out <- stats::sd(x)
  if (!is.finite(out)) 0 else out
}

app_numeric_summary <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) {
    return(list(min = NA_real_, q25 = NA_real_, median = NA_real_, q75 = NA_real_, max = NA_real_))
  }
  qs <- as.numeric(stats::quantile(x, probs = c(0.25, 0.50, 0.75), names = FALSE, type = 7))
  list(min = min(x), q25 = qs[[1L]], median = qs[[2L]], q75 = qs[[3L]], max = max(x))
}

app_json_safe_value <- function(x) {
  if (is.data.frame(x)) {
    for (nm in names(x)) x[[nm]] <- app_json_safe_value(x[[nm]])
    return(x)
  }
  if (is.matrix(x)) return(app_json_safe_value(as.data.frame(x)))
  if (is.list(x)) return(lapply(x, app_json_safe_value))
  if (is.numeric(x)) {
    out <- x
    out[is.nan(out)] <- NA_real_
    out[is.infinite(out)] <- NA_real_
    return(out)
  }
  x
}

app_reservoir_report_to_list <- function(x) {
  y <- unclass(x)
  app_json_safe_value(y)
}

app_reservoir_report_to_json <- function(x, pretty = TRUE) {
  app_require_namespace("jsonlite")
  jsonlite::toJSON(app_reservoir_report_to_list(x), auto_unbox = TRUE, pretty = pretty, null = "null")
}

app_coerce_state_matrix <- function(states) {
  if (inherits(states, "Matrix")) states <- as.matrix(states)
  if (is.data.frame(states)) states <- data.matrix(states)
  if (is.vector(states) && is.numeric(states) && is.null(dim(states))) {
    states <- matrix(as.numeric(states), ncol = 1L)
  }
  if (is.list(states) && !is.data.frame(states)) {
    mats <- lapply(states, app_coerce_state_matrix)
    nrs <- vapply(mats, nrow, integer(1L))
    if (length(unique(nrs)) != 1L) {
      stop("Layer state matrices must have the same number of rows.", call. = FALSE)
    }
    states <- do.call(cbind, mats)
  }
  if (!is.matrix(states)) stop("States must be coercible to a numeric matrix.", call. = FALSE)
  storage.mode(states) <- "double"
  states
}

app_drop_intercept_like_columns <- function(R, config) {
  if (!isTRUE(config$drop_intercept) || !ncol(R)) {
    return(list(matrix = R, indices = integer(0)))
  }
  tol <- as.numeric(config$intercept_tol %||% 1.0e-10)
  is_intercept <- vapply(seq_len(ncol(R)), function(j) {
    x <- R[, j]
    all(is.finite(x)) && max(abs(x - 1), na.rm = TRUE) <= tol
  }, logical(1L))
  list(matrix = R[, !is_intercept, drop = FALSE], indices = which(is_intercept))
}

app_standardize_matrix <- function(R, dead_std_tol = 1.0e-8) {
  center <- colMeans(R)
  scale <- apply(R, 2L, app_safe_sd)
  ok <- is.finite(scale) & scale >= dead_std_tol
  if (!any(ok)) return(list(Z = matrix(numeric(0), nrow = nrow(R), ncol = 0L), center = center, scale = scale, ok = ok))
  Z <- sweep(R[, ok, drop = FALSE], 2L, center[ok], "-")
  Z <- sweep(Z, 2L, scale[ok], "/")
  list(Z = Z, center = center, scale = scale, ok = ok)
}

app_corr_summary <- function(Z, config) {
  d <- ncol(Z)
  thresholds <- as.numeric(config$high_corr_thresholds)
  names(thresholds) <- sprintf("%.3f", thresholds)
  empty <- list(
    fractions = setNames(rep(0, length(thresholds)), names(thresholds)),
    near_duplicate_fraction = 0,
    max_abs_corr = NA_real_,
    corr_quantiles = setNames(rep(NA_real_, length(config$corr_quantile_probs)), as.character(config$corr_quantile_probs)),
    mode = "not_applicable"
  )
  if (d < 2L || nrow(Z) < 2L) return(empty)

  n <- nrow(Z)
  if (d <= as.integer(config$max_corr_features_full)) {
    C <- abs(crossprod(Z) / (n - 1))
    C[C > 1] <- 1
    vals <- C[upper.tri(C, diag = FALSE)]
    if (!length(vals)) return(empty)
    fractions <- vapply(thresholds, function(th) mean(vals > th), numeric(1L))
    q <- as.numeric(stats::quantile(vals, probs = config$corr_quantile_probs, names = FALSE, na.rm = TRUE))
    names(q) <- as.character(config$corr_quantile_probs)
    return(list(
      fractions = fractions,
      near_duplicate_fraction = mean(vals > as.numeric(config$near_duplicate_corr_threshold)),
      max_abs_corr = max(vals, na.rm = TRUE),
      corr_quantiles = q,
      mode = "full"
    ))
  }

  policy <- as.character(config$large_matrix_policy %||% "blockwise")[[1L]]
  if (identical(policy, "skip")) {
    empty$mode <- "skipped_large_matrix"
    return(empty)
  }
  if (identical(policy, "subsample")) {
    seed <- config$random_state %||% 1L
    old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) get(".Random.seed", envir = .GlobalEnv) else NULL
    on.exit({
      if (is.null(old_seed)) {
        if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
      } else {
        assign(".Random.seed", old_seed, envir = .GlobalEnv)
      }
    }, add = TRUE)
    set.seed(as.integer(seed))
    keep <- sort(sample.int(d, as.integer(config$max_corr_features_full)))
    out <- app_corr_summary(Z[, keep, drop = FALSE], config)
    out$mode <- "subsampled_features"
    return(out)
  }

  block <- max(1L, as.integer(config$corr_block_size))
  starts <- seq.int(1L, d, by = block)
  total <- 0
  counts <- setNames(rep(0, length(thresholds)), names(thresholds))
  near_count <- 0
  max_corr <- -Inf
  for (a in seq_along(starts)) {
    i1 <- starts[[a]]
    i2 <- min(d, i1 + block - 1L)
    Zi <- Z[, i1:i2, drop = FALSE]
    for (b in a:length(starts)) {
      j1 <- starts[[b]]
      j2 <- min(d, j1 + block - 1L)
      C <- abs(crossprod(Zi, Z[, j1:j2, drop = FALSE]) / (n - 1))
      C[C > 1] <- 1
      if (a == b) {
        vals <- C[upper.tri(C, diag = FALSE)]
      } else {
        vals <- as.numeric(C)
      }
      if (!length(vals)) next
      total <- total + length(vals)
      counts <- counts + vapply(thresholds, function(th) sum(vals > th), numeric(1L))
      near_count <- near_count + sum(vals > as.numeric(config$near_duplicate_corr_threshold))
      max_corr <- max(max_corr, vals, na.rm = TRUE)
    }
  }
  if (!total) return(empty)
  list(
    fractions = counts / total,
    near_duplicate_fraction = near_count / total,
    max_abs_corr = max_corr,
    corr_quantiles = empty$corr_quantiles,
    mode = "blockwise_exact_counts"
  )
}

app_effective_rank_summary <- function(Z, config) {
  n_eff <- nrow(Z)
  d_eff <- ncol(Z)
  out_empty <- list(
    effective_rank_entropy = 0,
    effective_rank_participation = 0,
    relative_effective_rank_entropy = 0,
    relative_effective_rank_participation = 0,
    singular_values_summary = app_numeric_summary(numeric()),
    lambda_max = NA_real_,
    lambda_min_positive = NA_real_,
    condition_z = Inf,
    condition_cov = Inf,
    eigenvalue_spread = Inf
  )
  if (n_eff < 2L || d_eff < 1L) return(out_empty)
  if (n_eff <= d_eff) {
    lambda <- eigen(tcrossprod(Z) / (n_eff - 1), symmetric = TRUE, only.values = TRUE)$values
  } else {
    lambda <- eigen(crossprod(Z) / (n_eff - 1), symmetric = TRUE, only.values = TRUE)$values
  }
  lambda <- pmax(as.numeric(lambda), 0)
  lambda <- lambda[is.finite(lambda)]
  if (!length(lambda) || sum(lambda) <= 0) return(out_empty)
  lambda_max <- max(lambda)
  tol <- as.numeric(config$eigen_tol) * lambda_max
  pos <- lambda[lambda > tol]
  expected_positive <- max(1L, min(n_eff - 1L, d_eff))
  lambda_min <- if (length(pos)) min(pos) else NA_real_
  probs <- lambda / sum(lambda)
  probs <- probs[probs > 0]
  r_entropy <- exp(-sum(probs * log(probs)))
  r_participation <- (sum(lambda)^2) / sum(lambda^2)
  denom <- min(n_eff, d_eff)
  svals <- sqrt(lambda * (n_eff - 1))
  condition_cov <- if (length(pos) < expected_positive) {
    Inf
  } else if (is.finite(lambda_min) && lambda_min > 0) {
    lambda_max / lambda_min
  } else {
    Inf
  }
  condition_z <- if (is.finite(condition_cov)) sqrt(condition_cov) else Inf
  list(
    effective_rank_entropy = r_entropy,
    effective_rank_participation = r_participation,
    relative_effective_rank_entropy = r_entropy / denom,
    relative_effective_rank_participation = r_participation / denom,
    singular_values_summary = app_numeric_summary(svals),
    lambda_max = lambda_max,
    lambda_min_positive = lambda_min,
    condition_z = condition_z,
    condition_cov = condition_cov,
    eigenvalue_spread = condition_cov
  )
}

app_state_repair_suggestions <- function(report, config) {
  suggestions <- character()
  if (!isTRUE(report$finite_pass)) suggestions <- c(suggestions, "remove or repair nonfinite reservoir states before fitting")
  if (is.finite(report$dead_fraction) && report$dead_fraction > config$dead_fraction_warn) {
    suggestions <- c(suggestions, "inspect input scaling, leak rate, spectral radius, or seed because many states are dead")
  }
  if (is.finite(report$saturation_fraction) && report$saturation_fraction > config$saturation_fraction_warn) {
    suggestions <- c(suggestions, "lower win_scale_global or win_scale_bias, use input_bound = 'tanh', lower pi_in, or lower spectral radius to reduce tanh saturation")
  }
  if (is.finite(report$near_duplicate_fraction) && report$near_duplicate_fraction > config$near_duplicate_fraction_warn) {
    suggestions <- c(suggestions, "prune near-duplicate states, add a reducer/PCA layer, or change seed/topology")
  }
  if (is.finite(report$relative_effective_rank_entropy) && report$relative_effective_rank_entropy < config$relative_effective_rank_warn) {
    suggestions <- c(suggestions, "increase state diversity or reduce redundant features because effective rank is low")
  }
  if (is.finite(report$condition_z) && report$condition_z > config$condition_z_warn) {
    suggestions <- c(suggestions, "use stronger ridge/horseshoe shrinkage, prune correlated states, or reduce feature dimension")
  }
  unique(suggestions)
}

app_compute_state_matrix_diagnostics <- function(
  states,
  config = NULL,
  feature_names = NULL,
  matrix_role = "reservoir",
  metadata = list()
) {
  config <- app_reservoir_as_config(config)
  R_raw <- app_coerce_state_matrix(states)
  n_raw <- nrow(R_raw)
  d_raw <- ncol(R_raw)
  if (config$washout >= n_raw) {
    report <- list(
      matrix_role = matrix_role,
      n_samples_raw = n_raw,
      n_samples_after_washout = 0L,
      n_features_raw = d_raw,
      n_intercept_like_features = NA_integer_,
      n_features_after_intercept_drop = NA_integer_,
      n_dead_features = NA_integer_,
      n_features_after_dead_removal = NA_integer_,
      dead_fraction = NA_real_,
      saturation_fraction = NA_real_,
      finite_pass = FALSE,
      standardization_pass = FALSE,
      high_corr_fractions = list(),
      near_duplicate_fraction = NA_real_,
      max_abs_corr = NA_real_,
      corr_quantiles = list(),
      corr_computation_mode = "not_run",
      effective_rank_entropy = 0,
      effective_rank_participation = 0,
      relative_effective_rank_entropy = 0,
      relative_effective_rank_participation = 0,
      singular_values_summary = list(),
      lambda_max = NA_real_,
      lambda_min_positive = NA_real_,
      condition_z = Inf,
      condition_cov = Inf,
      eigenvalue_spread = Inf,
      suggested_pruning_threshold = NA_real_,
      selected_feature_indices_after_pruning = NULL,
      warnings = "washout removes all rows",
      decision = "reject",
      repair_suggestions = "reduce washout or provide more rows",
      metadata = metadata
    )
    class(report) <- c("app_state_matrix_diagnostic_report", "list")
    return(report)
  }
  idx <- seq.int(config$washout + 1L, n_raw)
  R <- R_raw[idx, , drop = FALSE]
  finite_pass <- all(is.finite(R))
  warnings <- character()
  if (!finite_pass) warnings <- c(warnings, "state matrix contains NA/NaN/Inf after washout")

  dropped <- app_drop_intercept_like_columns(R, config)
  R_no_intercept <- dropped$matrix
  n_intercept <- length(dropped$indices)
  saturation_fraction <- if (isTRUE(config$saturation_check) && length(R_no_intercept)) {
    mean(abs(R_no_intercept) > as.numeric(config$saturation_abs))
  } else {
    NA_real_
  }

  if (!finite_pass || !ncol(R_no_intercept)) {
    decision <- "reject"
    report <- list(
      matrix_role = matrix_role,
      n_samples_raw = n_raw,
      n_samples_after_washout = nrow(R),
      n_features_raw = d_raw,
      n_intercept_like_features = n_intercept,
      n_features_after_intercept_drop = ncol(R_no_intercept),
      n_dead_features = NA_integer_,
      n_features_after_dead_removal = 0L,
      dead_fraction = NA_real_,
      saturation_fraction = saturation_fraction,
      finite_pass = finite_pass,
      standardization_pass = FALSE,
      high_corr_fractions = list(),
      near_duplicate_fraction = NA_real_,
      max_abs_corr = NA_real_,
      corr_quantiles = list(),
      corr_computation_mode = "not_run",
      effective_rank_entropy = 0,
      effective_rank_participation = 0,
      relative_effective_rank_entropy = 0,
      relative_effective_rank_participation = 0,
      singular_values_summary = list(),
      lambda_max = NA_real_,
      lambda_min_positive = NA_real_,
      condition_z = Inf,
      condition_cov = Inf,
      eigenvalue_spread = Inf,
      suggested_pruning_threshold = NA_real_,
      selected_feature_indices_after_pruning = NULL,
      warnings = warnings,
      decision = decision,
      repair_suggestions = c("provide finite non-intercept reservoir features"),
      metadata = metadata
    )
    class(report) <- c("app_state_matrix_diagnostic_report", "list")
    return(report)
  }

  sds <- apply(R_no_intercept, 2L, app_safe_sd)
  dead <- !is.finite(sds) | sds < as.numeric(config$dead_std_tol)
  n_dead <- sum(dead)
  dead_fraction <- n_dead / max(1L, ncol(R_no_intercept))
  R_live <- R_no_intercept[, !dead, drop = FALSE]
  standardization_pass <- ncol(R_live) > 0L
  if (!standardization_pass) warnings <- c(warnings, "all non-intercept features are dead or near-constant")
  if (is.finite(dead_fraction) && dead_fraction > config$dead_fraction_warn) {
    warnings <- c(warnings, sprintf("dead-state fraction %.3f exceeds warning threshold", dead_fraction))
  }
  if (is.finite(saturation_fraction) && saturation_fraction > config$saturation_fraction_warn) {
    warnings <- c(warnings, sprintf("saturation fraction %.3f exceeds warning threshold", saturation_fraction))
  }

  if (standardization_pass) {
    Z <- app_standardize_matrix(R_live, dead_std_tol = config$dead_std_tol)$Z
    corr <- app_corr_summary(Z, config)
    rank <- app_effective_rank_summary(Z, config)
  } else {
    corr <- list(
      fractions = setNames(rep(NA_real_, length(config$high_corr_thresholds)), sprintf("%.3f", config$high_corr_thresholds)),
      near_duplicate_fraction = NA_real_,
      max_abs_corr = NA_real_,
      corr_quantiles = setNames(rep(NA_real_, length(config$corr_quantile_probs)), as.character(config$corr_quantile_probs)),
      mode = "not_run"
    )
    rank <- app_effective_rank_summary(matrix(numeric(0), nrow = nrow(R_live), ncol = 0L), config)
  }

  if (is.finite(corr$near_duplicate_fraction) && corr$near_duplicate_fraction > config$near_duplicate_fraction_warn) {
    warnings <- c(warnings, sprintf("near-duplicate fraction %.3f exceeds warning threshold", corr$near_duplicate_fraction))
  }
  corr090_name <- sprintf("%.3f", 0.90)
  corr090 <- corr$fractions[[corr090_name]] %||% NA_real_
  if (is.finite(corr090) && corr090 > config$corr_fraction_reject_at_090) {
    warnings <- c(warnings, sprintf("correlation fraction above 0.90 is %.3f", corr090))
  }
  if (is.finite(rank$relative_effective_rank_entropy) &&
      rank$relative_effective_rank_entropy < config$relative_effective_rank_warn) {
    warnings <- c(warnings, sprintf("relative entropy effective rank %.3f is low", rank$relative_effective_rank_entropy))
  }
  if (is.finite(rank$condition_z) && rank$condition_z > config$condition_z_warn) {
    warnings <- c(warnings, sprintf("standardized design condition number %.3g is high", rank$condition_z))
  }
  if (is.finite(rank$condition_cov) && rank$condition_cov > config$condition_cov_warn) {
    warnings <- c(warnings, sprintf("covariance condition number %.3g is high", rank$condition_cov))
  }

  hard_reject <- !finite_pass ||
    !standardization_pass ||
    dead_fraction > config$dead_fraction_reject ||
    (is.finite(saturation_fraction) && saturation_fraction > config$saturation_fraction_reject) ||
    (is.finite(rank$relative_effective_rank_entropy) && rank$relative_effective_rank_entropy < config$relative_effective_rank_reject) ||
    (!is.finite(rank$condition_z) || rank$condition_z > config$condition_z_reject) ||
    (!is.finite(rank$condition_cov) || rank$condition_cov > config$condition_cov_reject)

  repair <- !hard_reject && (
    dead_fraction > config$dead_fraction_warn ||
      (is.finite(saturation_fraction) && saturation_fraction > config$saturation_fraction_warn) ||
      (is.finite(corr$near_duplicate_fraction) && corr$near_duplicate_fraction > config$near_duplicate_fraction_warn) ||
      (is.finite(corr090) && corr090 > 0) ||
      (is.finite(rank$relative_effective_rank_entropy) && rank$relative_effective_rank_entropy < config$relative_effective_rank_warn) ||
      (is.finite(rank$condition_z) && rank$condition_z > config$condition_z_warn) ||
      (is.finite(rank$condition_cov) && rank$condition_cov > config$condition_cov_warn)
  )
  decision <- if (hard_reject) "reject" else if (repair) "repair" else "pass"

  report <- c(
    list(
      matrix_role = matrix_role,
      n_samples_raw = n_raw,
      n_samples_after_washout = nrow(R),
      n_features_raw = d_raw,
      n_intercept_like_features = n_intercept,
      n_features_after_intercept_drop = ncol(R_no_intercept),
      n_dead_features = n_dead,
      n_features_after_dead_removal = ncol(R_live),
      dead_fraction = dead_fraction,
      saturation_fraction = saturation_fraction,
      finite_pass = finite_pass,
      standardization_pass = standardization_pass,
      high_corr_fractions = as.list(corr$fractions),
      near_duplicate_fraction = corr$near_duplicate_fraction,
      max_abs_corr = corr$max_abs_corr,
      corr_quantiles = as.list(corr$corr_quantiles),
      corr_computation_mode = corr$mode
    ),
    rank,
    list(
      suggested_pruning_threshold = if (is.finite(corr$near_duplicate_fraction) && corr$near_duplicate_fraction > config$near_duplicate_fraction_warn) {
        as.numeric(config$near_duplicate_corr_threshold)
      } else {
        NA_real_
      },
      selected_feature_indices_after_pruning = NULL,
      warnings = unique(warnings),
      decision = decision,
      repair_suggestions = character(),
      metadata = metadata
    )
  )
  report$repair_suggestions <- app_state_repair_suggestions(report, config)
  class(report) <- c("app_state_matrix_diagnostic_report", "list")
  report
}

app_reservoir_spectral_radius <- function(A) {
  A <- as.matrix(A)
  if (nrow(A) != ncol(A)) stop("Spectral radius requires a square matrix.", call. = FALSE)
  if (exists("app_qdesn_spectral_radius", mode = "function")) {
    return(app_qdesn_spectral_radius(A))
  }
  max(Mod(eigen(A, only.values = TRUE)$values))
}

app_layer_repair_suggestions <- function(report) {
  suggestions <- character()
  if (!isTRUE(report$finite_pass)) suggestions <- c(suggestions, "repair nonfinite recurrent weights")
  if (!isTRUE(report$shape_pass)) suggestions <- c(suggestions, "provide a square recurrent matrix")
  if (is.na(report$spectral_radius_pass) || is.na(report$leaky_effective_pass)) {
    suggestions <- c(suggestions, "install RSpectra or rerun with a higher exact spectral-radius limit to verify large-layer stability")
  } else {
    if (!isTRUE(report$spectral_radius_pass)) suggestions <- c(suggestions, "rescale recurrent matrix or revise target rho")
    if (!isTRUE(report$leaky_effective_pass)) suggestions <- c(suggestions, "lower alpha or rho, or inspect leaky-radius enforcement")
  }
  if (is.finite(report$singular_norm) && report$singular_norm > 1) {
    suggestions <- c(suggestions, "large singular norm may amplify transient responses; consider rescaling or stronger shrinkage")
  }
  unique(suggestions)
}

app_compute_layer_stability_diagnostics <- function(
  reservoir = NULL,
  recurrent_matrices = NULL,
  leak_rates = NULL,
  target_spectral_radii = NULL,
  config = NULL
) {
  config <- app_reservoir_as_config(config)
  if (!is.null(reservoir)) {
    recurrent_matrices <- recurrent_matrices %||% reservoir$W
    leak_rates <- leak_rates %||% reservoir$alpha
    target_spectral_radii <- target_spectral_radii %||% reservoir$rho
  }
  if (is.null(recurrent_matrices)) return(list())
  if (is.matrix(recurrent_matrices)) recurrent_matrices <- list(recurrent_matrices)
  n_layers <- length(recurrent_matrices)
  leak_rates <- as.numeric(unlist(leak_rates %||% rep(NA_real_, n_layers), use.names = FALSE))
  target_spectral_radii <- as.numeric(unlist(target_spectral_radii %||% rep(NA_real_, n_layers), use.names = FALSE))
  if (length(leak_rates) == 1L && n_layers > 1L) leak_rates <- rep(leak_rates, n_layers)
  if (length(target_spectral_radii) == 1L && n_layers > 1L) target_spectral_radii <- rep(target_spectral_radii, n_layers)

  lapply(seq_len(n_layers), function(i) {
    W <- as.matrix(recurrent_matrices[[i]])
    warnings <- character()
    shape_pass <- nrow(W) == ncol(W) && nrow(W) > 0L
    finite_pass <- all(is.finite(W))
    n_units <- nrow(W)
    n_nonzero <- sum(abs(W) > 0)
    connectivity <- n_nonzero / max(1, length(W))
    actual <- NA_real_
    leaky_actual <- NA_real_
    singular_norm <- NA_real_
    singular_status <- "skipped"
    if (!shape_pass) warnings <- c(warnings, "recurrent matrix is not square")
    if (!finite_pass) warnings <- c(warnings, "recurrent matrix contains nonfinite values")
    skip_exact_radius <- shape_pass && finite_pass &&
      n_units > as.integer(config$max_dense_spectral_radius_n) &&
      !requireNamespace("RSpectra", quietly = TRUE) &&
      !isTRUE(config$strict_singular_norm_check)
    if (isTRUE(skip_exact_radius)) {
      warnings <- c(
        warnings,
        sprintf(
          "exact spectral radius skipped for large dense %d x %d matrix because RSpectra is unavailable",
          n_units,
          n_units
        )
      )
    }
    if (shape_pass && finite_pass && !isTRUE(skip_exact_radius)) {
      actual <- tryCatch(app_reservoir_spectral_radius(W), error = function(e) NA_real_)
      alpha <- leak_rates[[min(i, length(leak_rates))]]
      if (is.finite(alpha)) {
        J <- (1 - alpha) * diag(n_units) + alpha * W
        leaky_actual <- tryCatch(app_reservoir_spectral_radius(J), error = function(e) NA_real_)
      }
      if (n_units <= config$singular_norm_max_n || isTRUE(config$strict_singular_norm_check)) {
        singular_norm <- tryCatch(svd(W, nu = 0L, nv = 0L)$d[[1L]], error = function(e) NA_real_)
        singular_status <- if (is.finite(singular_norm)) "computed" else "failed"
      }
    }
    target <- target_spectral_radii[[min(i, length(target_spectral_radii))]]
    rel_err <- if (is.finite(actual) && is.finite(target) && target > 0) abs(actual - target) / target else NA_real_
    spectral_pass <- if (isTRUE(skip_exact_radius)) {
      NA
    } else {
      isTRUE(shape_pass && finite_pass) &&
        is.finite(actual) &&
        (!is.finite(target) || rel_err <= config$spectral_radius_tolerance) &&
        (!isTRUE(config$require_spectral_radius_below_one) || actual < 1 + 1.0e-8)
    }
    leaky_pass <- if (isTRUE(skip_exact_radius)) {
      NA
    } else {
      !isTRUE(config$leaky_effective_radius_check) ||
        (is.finite(leaky_actual) && leaky_actual < 1 + 1.0e-8)
    }
    if (!isTRUE(spectral_pass)) warnings <- c(warnings, "spectral radius check failed, was skipped, or could not be verified")
    if (!isTRUE(leaky_pass)) warnings <- c(warnings, "leaky effective spectral radius check failed, was skipped, or could not be verified")
    decision <- if (!shape_pass || !finite_pass || isFALSE(leaky_pass)) {
      "reject"
    } else if (!isTRUE(spectral_pass) ||
               is.na(leaky_pass) ||
               (is.finite(singular_norm) && singular_norm > 1 && isTRUE(config$strict_singular_norm_check))) {
      "repair"
    } else {
      "pass"
    }
    report <- list(
      layer_index = i,
      n_units = n_units,
      n_nonzero = n_nonzero,
      connectivity = connectivity,
      target_spectral_radius = target,
      actual_spectral_radius = actual,
      spectral_radius_relative_error = rel_err,
      spectral_radius_pass = spectral_pass,
      leaky_rate = leak_rates[[min(i, length(leak_rates))]],
      leaky_effective_spectral_radius = leaky_actual,
      leaky_effective_pass = leaky_pass,
      singular_norm = singular_norm,
      singular_norm_status = singular_status,
      finite_pass = finite_pass,
      shape_pass = shape_pass,
      warnings = unique(warnings),
      decision = decision,
      repair_suggestions = character()
    )
    report$repair_suggestions <- app_layer_repair_suggestions(report)
    class(report) <- c("app_layer_stability_report", "list")
    report
  })
}

app_prune_correlated_states <- function(
  R,
  threshold = 0.95,
  prefer = c("variance", "validation", "original_order"),
  validation_scores = NULL,
  max_features = NULL,
  return_indices = TRUE,
  return_matrix = FALSE
) {
  prefer <- match.arg(prefer)
  R <- app_coerce_state_matrix(R)
  if (!ncol(R)) {
    out <- list(indices = integer(0))
    if (isTRUE(return_matrix)) out$matrix <- R
    return(out)
  }
  sds <- apply(R, 2L, app_safe_sd)
  keepable <- which(is.finite(sds) & sds > 0)
  if (!length(keepable)) {
    out <- list(indices = integer(0))
    if (isTRUE(return_matrix)) out$matrix <- R[, integer(0), drop = FALSE]
    return(out)
  }
  if (identical(prefer, "variance")) {
    order_idx <- keepable[order(sds[keepable], decreasing = TRUE)]
  } else if (identical(prefer, "validation")) {
    if (is.null(validation_scores) || length(validation_scores) != ncol(R)) {
      stop("validation_scores must have one value per feature when prefer = 'validation'.", call. = FALSE)
    }
    order_idx <- keepable[order(validation_scores[keepable], decreasing = TRUE)]
  } else {
    order_idx <- keepable
  }
  Z <- app_standardize_matrix(R[, order_idx, drop = FALSE], dead_std_tol = 0)$Z
  selected_pos <- integer(0)
  for (j in seq_along(order_idx)) {
    if (!length(selected_pos)) {
      selected_pos <- c(selected_pos, j)
    } else {
      cors <- abs(drop(crossprod(Z[, selected_pos, drop = FALSE], Z[, j, drop = FALSE]) / (nrow(Z) - 1)))
      if (all(cors < threshold, na.rm = TRUE)) selected_pos <- c(selected_pos, j)
    }
    if (!is.null(max_features) && length(selected_pos) >= as.integer(max_features)) break
  }
  selected <- sort(order_idx[selected_pos])
  out <- list(indices = selected)
  if (isTRUE(return_matrix)) out$matrix <- R[, selected, drop = FALSE]
  if (isTRUE(return_indices) && !isTRUE(return_matrix)) return(selected)
  out
}

app_empirical_initial_condition_forgetting_test <- function(
  input_matrix = NULL,
  reservoir = NULL,
  meta = list(),
  config = NULL,
  initial_states_a = NULL,
  initial_states_b = NULL
) {
  config <- app_reservoir_as_config(config)
  skip <- function(reason) {
    out <- list(
      ran = FALSE,
      skip_reason = reason,
      n_steps = NA_integer_,
      n_state_features = NA_integer_,
      early_distance_median = NA_real_,
      late_distance_median = NA_real_,
      final_distance = NA_real_,
      forgetting_ratio = NA_real_,
      passed = NA,
      warnings = reason,
      decision = "repair",
      repair_suggestions = "initial-condition forgetting test was skipped"
    )
    class(out) <- c("app_initial_condition_forgetting_report", "list")
    out
  }
  if (is.null(input_matrix) || is.null(reservoir)) return(skip("missing input matrix or reservoir"))
  if (!exists("app_qdesn_continue_one_step", mode = "function")) return(skip("reservoir step function unavailable"))
  U <- as.matrix(input_matrix)
  D <- as.integer(reservoir$D %||% length(reservoir$n))
  n <- as.integer(unlist(reservoir$n, use.names = FALSE))
  if (!length(n) || length(n) != D) return(skip("invalid reservoir state dimensions"))
  states_a <- initial_states_a %||% lapply(n, function(k) rep(0, k))
  states_b <- initial_states_b %||% lapply(n, function(k) rep(1 / sqrt(k), k))
  dist <- numeric(nrow(U))
  for (i in seq_len(nrow(U))) {
    states_a <- app_qdesn_continue_one_step(states_a, U[i, ], reservoir, meta)
    states_b <- app_qdesn_continue_one_step(states_b, U[i, ], reservoir, meta)
    va <- unlist(states_a, use.names = FALSE)
    vb <- unlist(states_b, use.names = FALSE)
    dist[[i]] <- sqrt(sum((va - vb)^2)) / sqrt(length(va))
  }
  idx <- seq.int(config$washout + 1L, length(dist))
  if (!length(idx)) return(skip("washout removes all forgetting-test distances"))
  d <- dist[idx]
  half <- max(1L, floor(length(d) / 2L))
  early <- d[seq_len(half)]
  late <- d[(length(d) - half + 1L):length(d)]
  early_med <- stats::median(early, na.rm = TRUE)
  late_med <- stats::median(late, na.rm = TRUE)
  ratio <- if (is.finite(early_med) && early_med > 0) late_med / early_med else NA_real_
  final <- tail(d, 1L)
  passed <- is.finite(ratio) && ratio <= config$initial_forgetting_ratio_max &&
    (is.null(config$initial_forgetting_final_max) || final <= config$initial_forgetting_final_max)
  warnings <- if (isTRUE(passed)) character() else "initial-condition forgetting ratio exceeds threshold"
  out <- list(
    ran = TRUE,
    skip_reason = "",
    n_steps = length(dist),
    n_state_features = sum(n),
    early_distance_median = early_med,
    late_distance_median = late_med,
    final_distance = final,
    forgetting_ratio = ratio,
    passed = passed,
    warnings = warnings,
    decision = if (isTRUE(passed)) "pass" else "repair",
    repair_suggestions = if (isTRUE(passed)) character() else "lower rho/alpha or inspect echo-state stability"
  )
  class(out) <- c("app_initial_condition_forgetting_report", "list")
  out
}

app_cheap_readout_score <- function(R, y, train_index, validation_index, config, cheap_readout_fn = NULL) {
  if (is.null(y)) return(list(score = NA_real_, pass = NA))
  y <- as.numeric(y)
  R <- app_coerce_state_matrix(R)
  if (length(y) != nrow(R)) return(list(score = NA_real_, pass = NA))
  if (is.null(train_index) || is.null(validation_index)) return(list(score = NA_real_, pass = NA))
  if (!is.null(cheap_readout_fn)) {
    score <- cheap_readout_fn(R = R, y = y, train_index = train_index, validation_index = validation_index, config = config)
    return(list(score = as.numeric(score)[[1L]], pass = is.finite(as.numeric(score)[[1L]])))
  }
  tr <- train_index
  va <- validation_index
  Xtr <- cbind(1, R[tr, , drop = FALSE])
  Xva <- cbind(1, R[va, , drop = FALSE])
  ytr <- y[tr]
  yva <- y[va]
  ok_tr <- is.finite(ytr) & rowSums(!is.finite(Xtr)) == 0
  ok_va <- is.finite(yva) & rowSums(!is.finite(Xva)) == 0
  if (sum(ok_tr) < 2L || sum(ok_va) < 1L) return(list(score = NA_real_, pass = NA))
  Xtr <- Xtr[ok_tr, , drop = FALSE]
  ytr <- ytr[ok_tr]
  Xva <- Xva[ok_va, , drop = FALSE]
  yva <- yva[ok_va]
  lam <- as.numeric(config$cheap_ridge_lambda %||% 1.0e-4)
  P <- diag(lam, ncol(Xtr))
  P[1L, 1L] <- 0
  beta <- tryCatch(solve(crossprod(Xtr) + P, crossprod(Xtr, ytr)), error = function(e) NULL)
  if (is.null(beta)) beta <- tryCatch(qr.solve(crossprod(Xtr) + P, crossprod(Xtr, ytr)), error = function(e) NULL)
  if (is.null(beta)) return(list(score = NA_real_, pass = NA))
  pred <- drop(Xva %*% beta)
  if (identical(config$validation_metric, "pinball")) {
    tau <- as.numeric((config$quantile_levels %||% 0.50)[[1L]])
    if (exists("app_check_loss", mode = "function")) {
      score <- mean(app_check_loss(yva, pred, tau), na.rm = TRUE)
    } else {
      e <- yva - pred
      score <- mean(ifelse(e >= 0, tau * e, (tau - 1) * e), na.rm = TRUE)
    }
  } else {
    score <- mean((yva - pred)^2, na.rm = TRUE)
  }
  list(score = score, pass = is.finite(score))
}

app_evaluate_precomputed_states <- function(
  states,
  config = NULL,
  recurrent_matrices = NULL,
  leak_rates = NULL,
  target_spectral_radii = NULL,
  y = NULL,
  train_index = NULL,
  validation_index = NULL,
  cheap_readout_fn = NULL,
  baseline_score = NULL,
  feature_names = NULL,
  metadata = list()
) {
  config <- app_reservoir_as_config(config)
  R <- app_coerce_state_matrix(states)
  state_report <- app_compute_state_matrix_diagnostics(
    R,
    config = config,
    feature_names = feature_names,
    matrix_role = metadata$matrix_role %||% "reservoir",
    metadata = metadata
  )
  layer_reports <- app_compute_layer_stability_diagnostics(
    recurrent_matrices = recurrent_matrices,
    leak_rates = leak_rates,
    target_spectral_radii = target_spectral_radii,
    config = config
  )
  cheap <- app_cheap_readout_score(
    R,
    y = y,
    train_index = train_index,
    validation_index = validation_index,
    config = config,
    cheap_readout_fn = cheap_readout_fn
  )
  validation_pass <- cheap$pass
  if (is.finite(cheap$score) && is.finite(baseline_score) && baseline_score > 0) {
    degradation <- (cheap$score - baseline_score) / baseline_score
    if (isTRUE(config$reject_on_cheap_validation) && degradation > config$validation_relative_degradation_reject) {
      validation_pass <- FALSE
    } else if (degradation > config$validation_relative_degradation_repair) {
      validation_pass <- FALSE
    }
  }
  decisions <- c(
    state_report$decision,
    vapply(layer_reports, function(x) x$decision, character(1L))
  )
  if (isFALSE(validation_pass) && isTRUE(config$reject_on_cheap_validation)) decisions <- c(decisions, "reject")
  if (isFALSE(validation_pass) && !isTRUE(config$reject_on_cheap_validation)) decisions <- c(decisions, "repair")
  decision <- app_screening_worst_decision(decisions)
  suggestions <- unique(c(
    state_report$repair_suggestions,
    unlist(lapply(layer_reports, function(x) x$repair_suggestions), use.names = FALSE),
    if (isFALSE(validation_pass)) "cheap validation underperforms baseline or failed" else character()
  ))
  out <- list(
    spec_id = metadata$spec_id %||% NA_character_,
    seed = metadata$seed %||% NA_integer_,
    layer_reports = layer_reports,
    forgetting_report = NULL,
    state_report = state_report,
    readout_state_report = NULL,
    cheap_validation_score = cheap$score,
    baseline_validation_score = baseline_score %||% NA_real_,
    validation_metric = config$validation_metric,
    validation_pass = validation_pass,
    decision = decision,
    repair_suggestions = suggestions,
    metadata = metadata
  )
  class(out) <- c("app_seed_diagnostic_report", "list")
  out
}

app_empty_state_matrix_report <- function(matrix_role = "not_run", reason = "state matrix diagnostics not run", metadata = list()) {
  out <- list(
    matrix_role = matrix_role,
    n_samples_raw = NA_integer_,
    n_samples_after_washout = NA_integer_,
    n_features_raw = NA_integer_,
    n_intercept_like_features = NA_integer_,
    n_features_after_intercept_drop = NA_integer_,
    n_dead_features = NA_integer_,
    n_features_after_dead_removal = NA_integer_,
    dead_fraction = NA_real_,
    saturation_fraction = NA_real_,
    finite_pass = NA,
    standardization_pass = NA,
    high_corr_fractions = list(),
    near_duplicate_fraction = NA_real_,
    max_abs_corr = NA_real_,
    corr_quantiles = list(),
    corr_computation_mode = "not_run",
    effective_rank_entropy = NA_real_,
    effective_rank_participation = NA_real_,
    relative_effective_rank_entropy = NA_real_,
    relative_effective_rank_participation = NA_real_,
    singular_values_summary = list(),
    lambda_max = NA_real_,
    lambda_min_positive = NA_real_,
    condition_z = NA_real_,
    condition_cov = NA_real_,
    eigenvalue_spread = NA_real_,
    suggested_pruning_threshold = NA_real_,
    selected_feature_indices_after_pruning = NULL,
    warnings = reason,
    decision = "pass",
    repair_suggestions = character(),
    metadata = metadata
  )
  class(out) <- c("app_state_matrix_diagnostic_report", "list")
  out
}

app_evaluate_reservoir_layers_only <- function(
  cfg,
  seed = NULL,
  config = NULL,
  metadata = list()
) {
  config <- app_reservoir_as_config(config)
  seed <- suppressWarnings(as.integer(seed %||% cfg$reservoir$seed %||% 20260513L))
  if (!is.finite(seed)) seed <- 20260513L
  m_input <- suppressWarnings(as.integer(cfg$reservoir$m %||% 1L))
  if (exists("app_qdesn_reservoir_input_spec", mode = "function")) {
    spec <- tryCatch(app_qdesn_reservoir_input_spec(cfg), error = function(e) NULL)
    if (!is.null(spec) && is.finite(spec$m_input)) m_input <- as.integer(spec$m_input)
  }
  reservoir <- app_qdesn_generate_article_reservoir(cfg, seed = seed, m_input = m_input)
  layer_reports <- app_compute_layer_stability_diagnostics(reservoir = reservoir, config = config)
  decision <- app_screening_worst_decision(vapply(layer_reports, function(x) x$decision, character(1L)))
  suggestions <- unique(unlist(lapply(layer_reports, function(x) x$repair_suggestions), use.names = FALSE))
  out <- list(
    spec_id = metadata$spec_id %||% NA_character_,
    seed = seed,
    layer_reports = layer_reports,
    forgetting_report = NULL,
    state_report = app_empty_state_matrix_report("layers_only", "state matrix diagnostics skipped for layer-only reservoir screen", metadata),
    readout_state_report = NULL,
    cheap_validation_score = NA_real_,
    baseline_validation_score = NA_real_,
    validation_metric = config$validation_metric,
    validation_pass = NA,
    decision = decision,
    repair_suggestions = suggestions,
    metadata = modifyList(list(m_input = m_input, matrix_role = "layers"), metadata)
  )
  class(out) <- c("app_seed_diagnostic_report", "list")
  out
}

app_latent_path_semantic_state_matrices <- function(
  design,
  matrix_role = c("reservoir", "readout", "both")
) {
  matrix_role <- match.arg(matrix_role)
  if (!isTRUE(design$two_block_design %||% FALSE)) return(list())
  out <- list()
  if (matrix_role %in% c("reservoir", "both")) {
    if (!is.null(design$X_core_beta)) {
      out$reference_reservoir <- design$X_core_beta
    } else if (!is.null(design$X_beta)) {
      out$reference_reservoir <- design$X_beta
    }
    if (!is.null(design$X_core_alpha)) {
      out$discrepancy_reservoir <- design$X_core_alpha
    } else if (!is.null(design$X_alpha)) {
      out$discrepancy_reservoir <- design$X_alpha
    }
  }
  if (matrix_role %in% c("readout", "both")) {
    if (!is.null(design$X_beta)) out$reference_readout <- design$X_beta
    if (!is.null(design$X_alpha)) out$discrepancy_readout <- design$X_alpha
  }
  out[!vapply(out, is.null, logical(1L))]
}

app_semantic_state_report_block <- function(matrix_role) {
  role <- as.character(matrix_role %||% "")[[1L]]
  sub("_(reservoir|readout)$", "", role)
}

app_compute_semantic_state_reports <- function(
  design,
  config = NULL,
  matrix_role = c("reservoir", "readout", "both"),
  metadata = list()
) {
  config <- app_reservoir_as_config(config)
  matrix_role <- match.arg(matrix_role)
  mats <- app_latent_path_semantic_state_matrices(design, matrix_role = matrix_role)
  if (!length(mats)) return(list())
  out <- lapply(names(mats), function(nm) {
    app_compute_state_matrix_diagnostics(
      mats[[nm]],
      config = config,
      matrix_role = nm,
      metadata = modifyList(
        list(
          semantic_block = app_semantic_state_report_block(nm),
          semantic_matrix_role = nm,
          two_block_design = TRUE
        ),
        metadata
      )
    )
  })
  names(out) <- names(mats)
  out
}

app_latent_path_semantic_layer_reports <- function(
  design,
  config = NULL
) {
  config <- app_reservoir_as_config(config)
  qfits <- list(
    reference = design$future_context$qfit_beta %||% design$qfit_beta %||% NULL,
    discrepancy = design$future_context$qfit_alpha %||% design$qfit_alpha %||% NULL
  )
  out <- list()
  for (nm in names(qfits)) {
    reservoir <- qfits[[nm]]$reservoir %||% NULL
    if (is.null(reservoir)) next
    block_reports <- app_compute_layer_stability_diagnostics(
      reservoir = reservoir,
      config = config
    )
    if (!length(block_reports)) next
    block_reports <- lapply(block_reports, function(x) {
      x$semantic_block <- nm
      x$reservoir_seed <- reservoir$seed %||% NA_integer_
      x
    })
    out <- c(out, block_reports)
  }
  out
}

app_evaluate_qdesn_design_object <- function(
  design,
  config = NULL,
  matrix_role = c("reservoir", "readout", "both"),
  y = NULL,
  metadata = list()
) {
  config <- app_reservoir_as_config(config)
  matrix_role <- match.arg(matrix_role)
  qfit <- design$future_context$qfit %||% design$qfit %||% design
  reservoir <- qfit$reservoir %||% design$reservoir %||% NULL
  semantic_reports <- app_compute_semantic_state_reports(
    design,
    config = config,
    matrix_role = matrix_role,
    metadata = metadata
  )
  if (length(semantic_reports)) {
    layer_reports <- app_latent_path_semantic_layer_reports(design, config = config)
    if (!length(layer_reports) && !is.null(reservoir)) {
      layer_reports <- app_compute_layer_stability_diagnostics(reservoir = reservoir, config = config)
    }
    semantic_decisions <- vapply(semantic_reports, function(x) x$decision, character(1L))
    layer_decisions <- if (length(layer_reports)) {
      vapply(layer_reports, function(x) x$decision, character(1L))
    } else {
      character()
    }
    semantic_suggestions <- unlist(lapply(semantic_reports, function(x) x$repair_suggestions %||% character()), use.names = FALSE)
    layer_suggestions <- unlist(lapply(layer_reports, function(x) x$repair_suggestions %||% character()), use.names = FALSE)
    out <- list(
      spec_id = metadata$spec_id %||% design$fit_id %||% design$model_id %||% NA_character_,
      seed = reservoir$seed %||% metadata$seed %||% NA_integer_,
      layer_reports = layer_reports,
      forgetting_report = NULL,
      state_report = semantic_reports[[1L]],
      readout_state_report = NULL,
      semantic_state_reports = semantic_reports,
      cheap_validation_score = NA_real_,
      baseline_validation_score = NA_real_,
      validation_metric = config$validation_metric,
      validation_pass = NA,
      decision = app_screening_worst_decision(c(semantic_decisions, layer_decisions)),
      repair_suggestions = unique(c(semantic_suggestions, layer_suggestions)),
      metadata = modifyList(
        list(
          two_block_design = TRUE,
          semantic_matrix_roles = names(semantic_reports)
        ),
        metadata
      )
    )
    class(out) <- c("app_seed_diagnostic_report", "list")
    return(out)
  }
  R_res <- qfit$X %||% design$X %||% design$X_base %||% design$X_beta
  R_readout <- design$X_beta %||% design$X_base %||% design$X %||% R_res
  target <- if (identical(matrix_role, "readout")) R_readout else R_res
  if (identical(matrix_role, "both")) target <- R_res
  yy <- y %||% qfit$y_fit %||% design$y_fit %||% NULL
  seed_report <- app_evaluate_precomputed_states(
    states = target,
    config = config,
    recurrent_matrices = reservoir$W %||% NULL,
    leak_rates = reservoir$alpha %||% NULL,
    target_spectral_radii = reservoir$rho %||% NULL,
    y = yy,
    metadata = modifyList(
      list(
        spec_id = design$fit_id %||% design$model_id %||% metadata$spec_id %||% NA_character_,
        seed = reservoir$seed %||% metadata$seed %||% NA_integer_,
        matrix_role = if (identical(matrix_role, "both")) "reservoir" else matrix_role
      ),
      metadata
    )
  )
  if (identical(matrix_role, "both") && !is.null(R_readout)) {
    seed_report$readout_state_report <- app_compute_state_matrix_diagnostics(
      R_readout,
      config = config,
      matrix_role = "readout",
      metadata = metadata
    )
    seed_report$decision <- app_screening_worst_decision(c(seed_report$decision, seed_report$readout_state_report$decision))
    seed_report$repair_suggestions <- unique(c(seed_report$repair_suggestions, seed_report$readout_state_report$repair_suggestions))
  }
  seed_report$semantic_state_reports <- list()
  seed_report
}

app_evaluate_reservoir_spec <- function(
  cfg,
  panel = NULL,
  model_row = NULL,
  cutoff_row = NULL,
  seed = NULL,
  runner = NULL,
  config = NULL,
  return_states = FALSE,
  metadata = list()
) {
  config <- app_reservoir_as_config(config)
  if (!is.null(runner)) {
    design <- runner(cfg = cfg, panel = panel, model_row = model_row, cutoff_row = cutoff_row, seed = seed)
  } else if (identical(metadata$matrix_role %||% "", "layers")) {
    return(app_evaluate_reservoir_layers_only(
      cfg = cfg,
      seed = seed %||% if (!is.null(model_row) && "reservoir_seed" %in% names(model_row)) model_row$reservoir_seed[[1L]] else cfg$reservoir$seed,
      config = config,
      metadata = modifyList(
        list(
          spec_id = if (!is.null(model_row) && "fit_id" %in% names(model_row)) model_row$fit_id[[1L]] else metadata$spec_id %||% NA_character_,
          fit_id = if (!is.null(model_row) && "fit_id" %in% names(model_row)) model_row$fit_id[[1L]] else metadata$fit_id %||% NA_character_
        ),
        metadata
      )
    ))
  } else {
    if (is.null(panel)) stop("panel is required when no custom reservoir screening runner is supplied.", call. = FALSE)
    if (!is.null(model_row) && !is.null(seed) && "reservoir_seed" %in% names(model_row)) {
      model_row$reservoir_seed[[1L]] <- as.integer(seed)
    }
    if (exists("app_is_latent_path_contract", mode = "function") &&
        isTRUE(app_is_latent_path_contract(cfg)) &&
        !is.null(model_row)) {
      design <- app_make_glofas_latent_path_design(
        panel = panel,
        cfg = cfg,
        model_row = model_row,
        cutoff_row = cutoff_row
      )
    } else if (exists("app_qdesn_reservoir_uses_covariates", mode = "function") &&
               isTRUE(app_qdesn_reservoir_uses_covariates(cfg))) {
      design <- app_qdesn_build_article_design_full(
        panel = panel,
        cfg = cfg,
        seed = seed %||% cfg$reservoir$seed,
        drop = cfg$reservoir$washout %||% NULL
      )
    } else {
      design <- app_build_qdesn_design_full(
        y = panel$y_transformed %||% panel$y,
        cfg = cfg,
        seed = seed %||% cfg$reservoir$seed,
        drop = cfg$reservoir$washout %||% NULL
      )
    }
  }
  report <- app_evaluate_qdesn_design_object(
    design,
    config = config,
    matrix_role = metadata$matrix_role %||% "reservoir",
    metadata = modifyList(
      list(
        spec_id = if (!is.null(model_row) && "fit_id" %in% names(model_row)) model_row$fit_id[[1L]] else metadata$spec_id %||% NA_character_,
        seed = seed %||% if (!is.null(model_row) && "reservoir_seed" %in% names(model_row)) model_row$reservoir_seed[[1L]] else cfg$reservoir$seed %||% NA_integer_
      ),
      metadata
    )
  )
  if (isTRUE(return_states)) report$metadata$design <- design
  report
}

app_architecture_summary_row <- function(report) {
  data.frame(
    spec_id = report$spec_id,
    n_seeds = report$n_seeds,
    decision = report$decision,
    pass_rate = report$pass_rate,
    repair_rate = report$repair_rate,
    fail_rate = report$fail_rate,
    median_relative_effective_rank_entropy = report$median_relative_effective_rank_entropy,
    median_relative_effective_rank_participation = report$median_relative_effective_rank_participation,
    median_condition_z = report$median_condition_z,
    median_condition_cov = report$median_condition_cov,
    median_near_duplicate_fraction = report$median_near_duplicate_fraction,
    median_validation_score = report$median_validation_score,
    seed_score_cv = report$seed_score_cv,
    accepted_seeds = paste(report$accepted_seeds, collapse = ","),
    repair_seeds = paste(report$repair_seeds, collapse = ","),
    rejected_seeds = paste(report$rejected_seeds, collapse = ","),
    recommended_seed_ids = paste(report$recommended_seed_ids, collapse = ","),
    stringsAsFactors = FALSE
  )
}

app_screen_reservoir_architecture <- function(
  cfg,
  panel = NULL,
  model_row = NULL,
  cutoff_row = NULL,
  seeds = 0:9,
  runner = NULL,
  config = NULL,
  baseline_score = NULL,
  metadata = list()
) {
  config <- app_reservoir_as_config(config)
  seeds <- as.integer(seeds)
  reports <- lapply(seeds, function(seed) {
    app_evaluate_reservoir_spec(
      cfg = cfg,
      panel = panel,
      model_row = model_row,
      cutoff_row = cutoff_row,
      seed = seed,
      runner = runner,
      config = config,
      metadata = metadata
    )
  })
  decisions <- vapply(reports, function(x) x$decision, character(1L))
  scores <- vapply(reports, function(x) x$cheap_validation_score %||% NA_real_, numeric(1L))
  rel_rank_e <- vapply(reports, function(x) app_seed_state_metric(x, "relative_effective_rank_entropy", min), numeric(1L))
  rel_rank_p <- vapply(reports, function(x) app_seed_state_metric(x, "relative_effective_rank_participation", min), numeric(1L))
  cond_z <- vapply(reports, function(x) app_seed_state_metric(x, "condition_z", max), numeric(1L))
  cond_cov <- vapply(reports, function(x) app_seed_state_metric(x, "condition_cov", max), numeric(1L))
  near_dup <- vapply(reports, function(x) app_seed_state_metric(x, "near_duplicate_fraction", max), numeric(1L))
  fail_rate <- mean(decisions == "reject")
  repair_rate <- mean(decisions == "repair")
  pass_rate <- mean(decisions == "pass")
  accepted <- seeds[decisions == "pass"]
  repair <- seeds[decisions == "repair"]
  rejected <- seeds[decisions == "reject"]
  finite_scores <- scores[is.finite(scores)]
  score_cv <- if (length(finite_scores) > 1L && mean(finite_scores) != 0) stats::sd(finite_scores) / abs(mean(finite_scores)) else NA_real_
  decision <- if (fail_rate > config$seed_fail_rate_reject) {
    "reject"
  } else if (repair_rate > 0 || (is.finite(score_cv) && score_cv > config$seed_score_cv_warn)) {
    "repair"
  } else {
    "pass"
  }
  recommendations <- character()
  if (decision == "reject") recommendations <- c(recommendations, "too many seeds fail diagnostics; revise the architecture")
  if (decision == "repair") recommendations <- c(recommendations, "inspect repair suggestions before launch; avoid selecting only the best lucky seed")
  rec_seeds <- accepted
  if (!length(rec_seeds) && length(repair)) rec_seeds <- repair
  out <- list(
    spec_id = metadata$spec_id %||% if (!is.null(model_row) && "fit_id" %in% names(model_row)) model_row$fit_id[[1L]] else NA_character_,
    n_seeds = length(seeds),
    per_seed_reports = reports,
    fail_rate = fail_rate,
    repair_rate = repair_rate,
    pass_rate = pass_rate,
    median_validation_score = if (length(finite_scores)) stats::median(finite_scores) else NA_real_,
    mean_validation_score = if (length(finite_scores)) mean(finite_scores) else NA_real_,
    std_validation_score = if (length(finite_scores) > 1L) stats::sd(finite_scores) else NA_real_,
    iqr_validation_score = if (length(finite_scores) > 1L) stats::IQR(finite_scores) else NA_real_,
    seed_score_cv = score_cv,
    median_relative_effective_rank_entropy = stats::median(rel_rank_e, na.rm = TRUE),
    median_relative_effective_rank_participation = stats::median(rel_rank_p, na.rm = TRUE),
    median_condition_z = stats::median(cond_z, na.rm = TRUE),
    median_condition_cov = stats::median(cond_cov, na.rm = TRUE),
    median_near_duplicate_fraction = stats::median(near_dup, na.rm = TRUE),
    accepted_seeds = accepted,
    repair_seeds = repair,
    rejected_seeds = rejected,
    recommended_seed_ids = rec_seeds,
    decision = decision,
    repair_suggestions = unique(c(recommendations, unlist(lapply(reports, function(x) x$repair_suggestions), use.names = FALSE))),
    metadata = metadata
  )
  class(out) <- c("app_architecture_screening_report", "list")
  out
}

app_screen_many_reservoir_specs <- function(
  specs,
  panel = NULL,
  seeds = 0:9,
  runner = NULL,
  config = NULL,
  baseline_fn = NULL,
  n_jobs = NULL
) {
  reports <- lapply(seq_along(specs), function(i) {
    spec <- specs[[i]]
    cfg <- spec$cfg %||% spec
    model_row <- spec$model_row %||% NULL
    cutoff_row <- spec$cutoff_row %||% NULL
    baseline <- if (!is.null(baseline_fn)) baseline_fn(spec) else NULL
    app_screen_reservoir_architecture(
      cfg = cfg,
      panel = panel %||% spec$panel %||% NULL,
      model_row = model_row,
      cutoff_row = cutoff_row,
      seeds = seeds,
      runner = runner,
      config = config,
      baseline_score = baseline,
      metadata = list(spec_id = spec$spec_id %||% paste0("spec_", i))
    )
  })
  ord <- order(
    vapply(reports, function(x) app_screening_decision_rank(x$decision), integer(1L)),
    vapply(reports, function(x) x$median_validation_score %||% Inf, numeric(1L)),
    na.last = TRUE
  )
  reports <- reports[ord]
  class(reports) <- c("app_many_architecture_screening_report", "list")
  reports
}

app_seed_state_metric_reports <- function(report) {
  semantic_reports <- report$semantic_state_reports %||% list()
  if (length(semantic_reports)) return(semantic_reports)
  list(report$state_report)
}

app_seed_state_metric <- function(report, field, fun = stats::median) {
  vals <- vapply(
    app_seed_state_metric_reports(report),
    function(x) as.numeric(x[[field]] %||% NA_real_),
    numeric(1L)
  )
  vals <- vals[is.finite(vals)]
  if (!length(vals)) return(NA_real_)
  fun(vals)
}

app_seed_report_row <- function(report) {
  semantic_decision <- if (length(report$semantic_state_reports %||% list())) {
    app_screening_worst_decision(vapply(report$semantic_state_reports, function(x) x$decision, character(1L)))
  } else {
    NA_character_
  }
  warning_count <- sum(vapply(
    app_seed_state_metric_reports(report),
    function(x) length(x$warnings %||% character()),
    integer(1L)
  ))
  data.frame(
    spec_id = report$spec_id,
    fit_id = report$metadata$fit_id %||% report$spec_id,
    seed = report$seed,
    decision = report$decision,
    state_decision = report$state_report$decision %||% NA_character_,
    semantic_state_decision = semantic_decision,
    n_semantic_state_reports = length(report$semantic_state_reports %||% list()),
    layer_decision = app_screening_worst_decision(vapply(report$layer_reports, function(x) x$decision, character(1L)) %||% "pass"),
    forgetting_decision = report$forgetting_report$decision %||% NA_character_,
    cheap_validation_score = report$cheap_validation_score,
    baseline_validation_score = report$baseline_validation_score,
    validation_pass = report$validation_pass,
    n_warnings = warning_count,
    n_repair_suggestions = length(report$repair_suggestions %||% character()),
    stringsAsFactors = FALSE
  )
}

app_state_report_row <- function(seed_report, report = seed_report$state_report) {
  data.frame(
    spec_id = seed_report$spec_id,
    fit_id = seed_report$metadata$fit_id %||% seed_report$spec_id,
    seed = seed_report$seed,
    matrix_role = report$matrix_role,
    semantic_block = report$metadata$semantic_block %||% NA_character_,
    n_samples_after_washout = report$n_samples_after_washout,
    n_features_after_dead_removal = report$n_features_after_dead_removal,
    dead_fraction = report$dead_fraction,
    saturation_fraction = report$saturation_fraction,
    near_duplicate_fraction = report$near_duplicate_fraction,
    max_abs_corr = report$max_abs_corr,
    relative_effective_rank_entropy = report$relative_effective_rank_entropy,
    relative_effective_rank_participation = report$relative_effective_rank_participation,
    condition_z = report$condition_z,
    condition_cov = report$condition_cov,
    eigenvalue_spread = report$eigenvalue_spread,
    corr_computation_mode = report$corr_computation_mode,
    decision = report$decision,
    stringsAsFactors = FALSE
  )
}

app_state_report_rows <- function(seed_report) {
  semantic_reports <- seed_report$semantic_state_reports %||% list()
  if (length(semantic_reports)) {
    return(app_bind_rows_fill(lapply(semantic_reports, function(x) app_state_report_row(seed_report, x))))
  }
  rows <- list(app_state_report_row(seed_report, seed_report$state_report))
  if (!is.null(seed_report$readout_state_report)) {
    rows[[length(rows) + 1L]] <- app_state_report_row(seed_report, seed_report$readout_state_report)
  }
  app_bind_rows_fill(rows)
}

app_layer_report_rows <- function(seed_report) {
  rows <- lapply(seed_report$layer_reports, function(x) {
    data.frame(
      spec_id = seed_report$spec_id,
      fit_id = seed_report$metadata$fit_id %||% seed_report$spec_id,
      seed = seed_report$seed,
      semantic_block = x$semantic_block %||% NA_character_,
      layer_index = x$layer_index,
      n_units = x$n_units,
      connectivity = x$connectivity,
      target_spectral_radius = x$target_spectral_radius,
      actual_spectral_radius = x$actual_spectral_radius,
      spectral_radius_relative_error = x$spectral_radius_relative_error,
      leaky_rate = x$leaky_rate,
      leaky_effective_spectral_radius = x$leaky_effective_spectral_radius,
      singular_norm = x$singular_norm,
      decision = x$decision,
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_repair_suggestion_rows <- function(seed_report) {
  suggestions <- seed_report$repair_suggestions %||% character()
  if (!length(suggestions)) return(data.frame())
  data.frame(
    spec_id = seed_report$spec_id,
    fit_id = seed_report$metadata$fit_id %||% seed_report$spec_id,
    seed = seed_report$seed,
    source = "seed_report",
    severity = seed_report$decision,
    suggestion = suggestions,
    stringsAsFactors = FALSE
  )
}

app_reservoir_report_to_data_frame <- function(x) {
  if (inherits(x, "app_architecture_screening_report")) return(app_architecture_summary_row(x))
  if (inherits(x, "app_seed_diagnostic_report")) return(app_seed_report_row(x))
  if (inherits(x, "app_state_matrix_diagnostic_report")) return(app_state_report_row(list(spec_id = NA, seed = NA, metadata = list()), x))
  data.frame()
}

app_format_reservoir_screening_report <- function(x) {
  if (inherits(x, "app_architecture_screening_report")) {
    return(paste(
      sprintf("Reservoir screening report for %s", x$spec_id),
      sprintf("Decision: %s", x$decision),
      sprintf("Seeds: %d | pass %.2f | repair %.2f | reject %.2f", x$n_seeds, x$pass_rate, x$repair_rate, x$fail_rate),
      sprintf("Median relative effective rank: %.3f", x$median_relative_effective_rank_entropy),
      sprintf("Median condition_z: %.3g", x$median_condition_z),
      paste("Recommended seeds:", paste(x$recommended_seed_ids, collapse = ",")),
      sep = "\n"
    ))
  }
  if (inherits(x, "app_seed_diagnostic_report")) {
    return(paste(
      sprintf("Seed %s decision: %s", x$seed, x$decision),
      sprintf("State decision: %s", x$state_report$decision),
      paste("Suggestions:", paste(x$repair_suggestions, collapse = "; ")),
      sep = "\n"
    ))
  }
  paste(capture.output(str(x)), collapse = "\n")
}
