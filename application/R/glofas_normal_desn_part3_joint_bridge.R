# Historical joint USGS/GloFAS bridge for the GloFAS Normal-DESN workflow.
#
# Part 3 is the intermediate model between the separate G1/G2 screens and the
# article-facing forecast-ensemble application. It uses retrospective paired
# USGS/GloFAS observations only:
#
#   y_usgs(t)   = q(x_q(t))                 + eps_y(t)
#   y_glofas(t) = q(x_q(t)) + d(x_d(t))     + eps_g(t)
#
# The discrepancy convention matches Part 2: d(t) = GloFAS(t) - USGS(t). The
# implied USGS correction is therefore GloFAS(t) - d_hat(t).

app_glofas_normal_part3_model_families <- function() {
  data.frame(
    model_family = c(
      "normal_ridge_joint",
      "normal_rhs_vb_joint",
      "independent_al_rhs_vb",
      "independent_exal_rhs_vb",
      "joint_al_rhs_vb",
      "joint_exal_rhs_vb"
    ),
    likelihood = c("normal", "normal", "AL", "exAL", "AL", "exAL"),
    inference = c(
      "closed_form_ridge",
      "VB_block_regularized_horseshoe",
      "VB_regularized_horseshoe_independent_quantiles",
      "VB_regularized_horseshoe_independent_quantiles_structured_scale",
      "VB_regularized_horseshoe_joint_quantiles",
      "VB_regularized_horseshoe_joint_quantiles_structured_scale"
    ),
    executable_now = rep(TRUE, 6L),
    status = c(
      "implemented_for_gated_smoke_and_future_launch",
      "implemented_for_gated_smoke_and_future_launch",
      "implemented_in_part3_quantile_forecast_continuation_chain",
      "implemented_in_part3_quantile_forecast_continuation_chain",
      "implemented_in_part3_quantile_forecast_continuation_chain",
      "implemented_in_part3_quantile_forecast_continuation_chain"
    ),
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_part3_quantile_grid <- function() {
  c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
}

app_glofas_normal_part3_required_winner_columns <- function() {
  c(
    "component",
    "stage",
    "candidate_id",
    "source_runtime_root",
    "score_path",
    "method",
    "status",
    "winner_role",
    "n_vector",
    "m",
    "output_lag_max",
    "covariate_lag_max",
    "washout",
    "alpha",
    "rho",
    "seed",
    "rhs_tau0",
    "design_hash",
    "frozen"
  )
}

app_glofas_normal_part3_as_bool <- function(x) {
  if (is.logical(x)) return(isTRUE(x[[1L]]))
  val <- tolower(trimws(as.character(x[[1L]] %||% "")))
  val %in% c("true", "t", "yes", "y", "1")
}

app_glofas_normal_part3_validate_winner_manifest <- function(
  manifest,
  require_frozen = TRUE
) {
  if (is.character(manifest) && length(manifest) == 1L) {
    if (!file.exists(manifest)) {
      stop(sprintf("Winner manifest does not exist: %s", manifest), call. = FALSE)
    }
    manifest <- app_read_csv(manifest)
  }
  if (!is.data.frame(manifest)) stop("Winner manifest must be a data frame or CSV path.", call. = FALSE)
  app_check_required_columns(
    manifest,
    app_glofas_normal_part3_required_winner_columns(),
    "GloFAS Part 3 selected winner manifest"
  )
  manifest$component <- tolower(trimws(as.character(manifest$component)))
  manifest$stage <- toupper(trimws(as.character(manifest$stage)))
  manifest$status <- tolower(trimws(as.character(manifest$status)))
  expected <- data.frame(
    component = c("reference", "discrepancy"),
    stage = c("G1", "G2"),
    stringsAsFactors = FALSE
  )
  for (i in seq_len(nrow(expected))) {
    idx <- manifest$component == expected$component[[i]] &
      manifest$stage == expected$stage[[i]]
    if (sum(idx) != 1L) {
      stop(sprintf(
        "Winner manifest must contain exactly one %s/%s row.",
        expected$stage[[i]], expected$component[[i]]
      ), call. = FALSE)
    }
  }
  if (!all(manifest$status %in% c("completed", "frozen", "promoted"))) {
    stop("Winner manifest rows must have status completed, frozen, or promoted.", call. = FALSE)
  }
  for (nm in c("m", "output_lag_max", "covariate_lag_max", "washout", "alpha", "rho", "rhs_tau0")) {
    vals <- suppressWarnings(as.numeric(manifest[[nm]]))
    if (any(!is.finite(vals))) {
      stop(sprintf("Winner manifest column '%s' must be finite.", nm), call. = FALSE)
    }
  }
  if (isTRUE(require_frozen)) {
    frozen <- vapply(manifest$frozen, app_glofas_normal_part3_as_bool, logical(1L))
    if (!all(frozen)) stop("Winner manifest is not frozen; Part 3 launch remains blocked.", call. = FALSE)
  }
  manifest
}

app_glofas_normal_part3_winner_row <- function(manifest, component, stage) {
  idx <- manifest$component == component & manifest$stage == stage
  manifest[idx, , drop = FALSE][1L, , drop = FALSE]
}

app_glofas_normal_part3_candidate_from_winners <- function(
  winner_manifest,
  candidate_id = "part3_joint_selected_from_g1_g2",
  require_frozen = TRUE
) {
  manifest <- app_glofas_normal_part3_validate_winner_manifest(
    winner_manifest,
    require_frozen = require_frozen
  )
  ref <- app_glofas_normal_part3_winner_row(manifest, "reference", "G1")
  disc <- app_glofas_normal_part3_winner_row(manifest, "discrepancy", "G2")
  defaults <- app_glofas_normal_part2_default_values()
  row_value <- function(row, nm, default = NA) {
    if (nm %in% names(row) && length(row[[nm]]) && !is.na(row[[nm]][[1L]])) row[[nm]][[1L]] else default
  }
  data.frame(
    candidate_id = as.character(candidate_id),
    model_family = "normal_joint_historical_bridge",
    ref_n_vector = as.character(row_value(ref, "n_vector")),
    disc_n_vector = as.character(row_value(disc, "n_vector")),
    ref_m = as.integer(row_value(ref, "m")),
    disc_m = as.integer(row_value(disc, "m")),
    ref_output_lag_max = as.integer(row_value(ref, "output_lag_max")),
    disc_output_lag_max = as.integer(row_value(disc, "output_lag_max")),
    ref_covariate_lag_max = as.integer(row_value(ref, "covariate_lag_max")),
    disc_covariate_lag_max = as.integer(row_value(disc, "covariate_lag_max")),
    ref_auxiliary_lag_max = as.integer(row_value(ref, "auxiliary_lag_max", 0L)),
    disc_auxiliary_lag_max = as.integer(row_value(disc, "auxiliary_lag_max", row_value(disc, "output_lag_max"))),
    ref_input_contract = as.character(row_value(ref, "input_contract", "reference_usgs_covars")),
    disc_input_contract = as.character(row_value(disc, "input_contract", "disc_usgs_covars")),
    ref_washout = as.integer(row_value(ref, "washout")),
    disc_washout = as.integer(row_value(disc, "washout")),
    ref_alpha = as.numeric(row_value(ref, "alpha")),
    disc_alpha = as.numeric(row_value(disc, "alpha")),
    ref_rho = as.numeric(row_value(ref, "rho")),
    disc_rho = as.numeric(row_value(disc, "rho")),
    ref_seed = as.integer(row_value(ref, "seed")),
    disc_seed = as.integer(row_value(disc, "seed")),
    ref_source_candidate_id = as.character(row_value(ref, "candidate_id")),
    disc_source_candidate_id = as.character(row_value(disc, "candidate_id")),
    ref_source_runtime_root = as.character(row_value(ref, "source_runtime_root")),
    disc_source_runtime_root = as.character(row_value(disc, "source_runtime_root")),
    ref_source_design_hash = as.character(row_value(ref, "design_hash")),
    disc_source_design_hash = as.character(row_value(disc, "design_hash")),
    rhs_tau0_reference = as.numeric(row_value(ref, "rhs_tau0")),
    rhs_tau0_discrepancy = as.numeric(row_value(disc, "rhs_tau0")),
    rhs_max_iter = 100L,
    rhs_min_iter = 30L,
    rhs_tol = 1.0e-4,
    rhs_update_every = 1L,
    rhs_freeze_tau_warmup_iters = 0L,
    rhs_min_tau_updates = 0L,
    ridge_tau2 = defaults$ridge_tau2,
    intercept_var = defaults$intercept_var,
    sigma_a = defaults$sigma_a,
    sigma_b = defaults$sigma_b,
    validation_n = defaults$validation_n,
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_part3_feature_info <- function(component_info, column_names, block, offset = 0L) {
  p <- length(column_names)
  if (is.null(component_info) || !is.data.frame(component_info) || !nrow(component_info)) {
    component_info <- data.frame(
      local_column_index = seq_len(p),
      component_column_name = column_names,
      stringsAsFactors = FALSE
    )
  } else {
    component_info <- component_info[, names(component_info), drop = FALSE]
    component_info$component_column_name <- as.character(component_info$column_name %||% column_names)
    component_info$local_column_index <- seq_len(nrow(component_info))
  }
  component_info$part3_block <- block
  component_info$global_column_index <- offset + seq_len(p)
  component_info$column_name <- paste0(if (identical(block, "reference")) "beta__" else "alpha__", column_names)
  component_info
}

app_glofas_normal_part3_build_design <- function(
  base_cfg,
  candidate_row,
  panel_bundle = NULL,
  reference_cache = NULL
) {
  if (!exists("app_glofas_normal_part2_build_design", mode = "function")) {
    stop("Part 3 requires application/R/glofas_normal_desn_part2_bridge.R to be sourced.", call. = FALSE)
  }
  if (!exists("app_make_augmented_discrepancy_design", mode = "function")) {
    stop("Part 3 requires application/R/discrepancy_design.R to be sourced.", call. = FALSE)
  }
  candidate_row <- candidate_row[1L, , drop = FALSE]
  bridge <- app_glofas_normal_part2_build_design(
    base_cfg,
    candidate_row,
    panel_bundle = panel_bundle,
    reference_cache = reference_cache
  )
  n_dates <- length(bridge$dates)
  if (!n_dates) stop("Part 3 bridge design has no paired dates.", call. = FALSE)
  sign_gap <- max(abs(as.numeric(bridge$y_reference) + as.numeric(bridge$d_g) - as.numeric(bridge$g_retrospective)))
  if (!is.finite(sign_gap) || sign_gap > 1.0e-10) {
    stop("Part 3 sign check failed: USGS + discrepancy must equal retrospective GloFAS.", call. = FALSE)
  }
  X_ref <- as.matrix(bridge$reference$X)
  X_disc <- as.matrix(bridge$discrepancy$X)
  storage.mode(X_ref) <- "double"
  storage.mode(X_disc) <- "double"
  source <- c(rep("Y", n_dates), rep("G", n_dates))
  X_beta_stack <- rbind(X_ref, X_ref)
  X_alpha_stack <- rbind(X_disc, X_disc)
  H <- app_make_augmented_discrepancy_design(
    X_beta = X_beta_stack,
    source = source,
    X_alpha = X_alpha_stack
  )
  z <- c(as.numeric(bridge$y_reference), as.numeric(bridge$g_retrospective))
  row_info <- data.frame(
    row_index = seq_along(z),
    source = source,
    date = as.Date(rep(bridge$dates, 2L)),
    target = c(rep("usgs_reference", n_dates), rep("retrospective_glofas", n_dates)),
    z = z,
    observed_usgs = rep(as.numeric(bridge$y_reference), 2L),
    retrospective_glofas = rep(as.numeric(bridge$g_retrospective), 2L),
    observed_discrepancy = rep(as.numeric(bridge$d_g), 2L),
    stringsAsFactors = FALSE
  )
  p_beta <- ncol(X_ref)
  p_alpha <- ncol(X_disc)
  beta_index <- seq_len(p_beta)
  alpha_index <- p_beta + seq_len(p_alpha)
  feature_info <- app_bind_rows_fill(list(
    app_glofas_normal_part3_feature_info(
      bridge$reference$feature_info,
      colnames(X_ref),
      "reference",
      offset = 0L
    ),
    app_glofas_normal_part3_feature_info(
      bridge$discrepancy$feature_info,
      colnames(X_disc),
      "discrepancy",
      offset = p_beta
    )
  ))
  train_hash <- NULL
  full_hash <- app_glofas_normal_part1_design_fingerprint(
    H,
    z,
    row_info$date,
    feature_info
  )
  pairing_certificate <- if (exists("app_latent_pairing_certificate", mode = "function")) {
    app_latent_pairing_certificate(
      X_beta_stack = X_beta_stack,
      source = source,
      beta_index = beta_index,
      alpha_index = alpha_index,
      feature_names = colnames(H),
      tol = 0,
      optimization_enabled = TRUE
    )
  } else {
    list(
      paired_beta_rows = TRUE,
      n_y = n_dates,
      n_g = n_dates,
      n_beta = p_beta,
      beta_index = beta_index,
      alpha_index = alpha_index,
      construction = "validated_equal_ordered_beta_rows_without_latent_certificate"
    )
  }
  design <- list(
    candidate_id = as.character(candidate_row$candidate_id[[1L]] %||% "part3_candidate"),
    bridge_design = bridge,
    dates = bridge$dates,
    n_dates = n_dates,
    H = H,
    z = z,
    source = source,
    row_info = row_info,
    reference = bridge$reference,
    discrepancy = bridge$discrepancy,
    y_reference = as.numeric(bridge$y_reference),
    g_retrospective = as.numeric(bridge$g_retrospective),
    d_g = as.numeric(bridge$d_g),
    X_beta_stack = X_beta_stack,
    X_alpha_stack = X_alpha_stack,
    beta_index = beta_index,
    alpha_index = alpha_index,
    p_beta = p_beta,
    p_alpha = p_alpha,
    feature_info = feature_info,
    pairing_certificate = pairing_certificate,
    design_hash = c(bridge$design_hash, part3_stacked_full = full_hash),
    train_design_hash = train_hash,
    sign_convention = "d_g = retrospective_glofas - usgs; corrected_usgs = retrospective_glofas - d_hat"
  )
  app_glofas_normal_part3_validate_design(design)
  design
}

app_glofas_normal_part3_validate_design <- function(design, tol = 1.0e-10) {
  required <- c("H", "z", "source", "reference", "discrepancy", "beta_index", "alpha_index", "n_dates")
  missing <- setdiff(required, names(design))
  if (length(missing)) stop(sprintf("Part 3 design is missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
  H <- as.matrix(design$H)
  source <- as.character(design$source)
  if (nrow(H) != length(design$z) || nrow(H) != length(source)) {
    stop("Part 3 stacked design row counts are inconsistent.", call. = FALSE)
  }
  n_dates <- as.integer(design$n_dates)
  if (n_dates <= 0L || nrow(H) != 2L * n_dates) {
    stop("Part 3 stacked design must contain paired USGS and GloFAS rows.", call. = FALSE)
  }
  y_rows <- which(source == "Y")
  g_rows <- which(source == "G")
  if (length(y_rows) != n_dates || length(g_rows) != n_dates) {
    stop("Part 3 stacked design must contain exactly one Y and one G row per date.", call. = FALSE)
  }
  if (!identical(y_rows, seq_len(n_dates)) || !identical(g_rows, n_dates + seq_len(n_dates))) {
    stop("Part 3 stacked design rows must be ordered as all USGS rows followed by all GloFAS rows.", call. = FALSE)
  }
  beta_index <- as.integer(design$beta_index)
  alpha_index <- as.integer(design$alpha_index)
  X_ref <- as.matrix(design$reference$X)
  X_disc <- as.matrix(design$discrepancy$X)
  if (!isTRUE(all.equal(
    H[y_rows, beta_index, drop = FALSE],
    X_ref,
    tolerance = tol,
    check.attributes = FALSE
  ))) stop("Part 3 Y beta block does not match the reference design.", call. = FALSE)
  if (!isTRUE(all.equal(
    H[g_rows, beta_index, drop = FALSE],
    X_ref,
    tolerance = tol,
    check.attributes = FALSE
  ))) stop("Part 3 G beta block does not match the reference design.", call. = FALSE)
  if (max(abs(H[y_rows, alpha_index, drop = FALSE])) > tol) {
    stop("Part 3 Y rows must have zero discrepancy-design contribution.", call. = FALSE)
  }
  if (!isTRUE(all.equal(
    H[g_rows, alpha_index, drop = FALSE],
    X_disc,
    tolerance = tol,
    check.attributes = FALSE
  ))) stop("Part 3 G alpha block does not match the discrepancy design.", call. = FALSE)
  sign_gap <- max(abs(as.numeric(design$y_reference) + as.numeric(design$d_g) - as.numeric(design$g_retrospective)))
  if (!is.finite(sign_gap) || sign_gap > tol) {
    stop("Part 3 sign convention check failed.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_normal_part3_validation_split <- function(design, candidate_row) {
  validation_n <- as.integer(app_glofas_normal_part2_row_value(
    candidate_row,
    "validation_n",
    app_glofas_normal_part2_default_values()$validation_n
  ))
  app_glofas_normal_part1_validation_split(length(design$dates), validation_n)
}

app_glofas_normal_part3_stack_split <- function(design, split) {
  n_dates <- as.integer(design$n_dates)
  list(
    train_idx = c(split$train_idx, n_dates + split$train_idx),
    valid_idx = c(split$valid_idx, n_dates + split$valid_idx),
    train_y_idx = split$train_idx,
    train_g_idx = n_dates + split$train_idx,
    valid_y_idx = split$valid_idx,
    valid_g_idx = n_dates + split$valid_idx
  )
}

app_glofas_normal_part3_make_ridge_warm_start <- function(fit, design, split, candidate_row) {
  stack_split <- app_glofas_normal_part3_stack_split(design, split)
  train_hash <- app_glofas_normal_part1_design_fingerprint(
    design$H[stack_split$train_idx, , drop = FALSE],
    design$z[stack_split$train_idx],
    design$row_info$date[stack_split$train_idx],
    design$feature_info
  )
  warm <- list(
    type = "glofas_normal_part3_ridge_warm_start",
    version = "0.1",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    candidate_id = as.character(candidate_row$candidate_id[[1L]] %||% design$candidate_id),
    split = split,
    stack_split = stack_split,
    design_hash = list(
      part3_stacked_train = train_hash,
      part3_stacked_full = as.character(design$design_hash[["part3_stacked_full"]]),
      reference_full = as.character(design$design_hash[["reference_full"]]),
      discrepancy_full = as.character(design$design_hash[["discrepancy_full"]])
    ),
    block = list(
      p_beta = as.integer(design$p_beta),
      p_alpha = as.integer(design$p_alpha),
      beta_index = as.integer(design$beta_index),
      alpha_index = as.integer(design$alpha_index)
    ),
    fit = list(
      beta_mean = as.numeric(fit$beta_mean),
      beta_var_diag = as.numeric(fit$beta_var_diag),
      sigma_a = as.numeric(fit$sigma_a),
      sigma_b = as.numeric(fit$sigma_b),
      sigma2_mean = as.numeric(fit$sigma2_mean),
      ridge_tau2 = as.numeric(fit$ridge_tau2),
      intercept_var = as.numeric(fit$intercept_var),
      n_train = as.integer(fit$n_train),
      p = as.integer(fit$p)
    )
  )
  class(warm) <- c("glofas_normal_part3_ridge_warm_start", "list")
  warm
}

app_glofas_normal_part3_validate_warm_start <- function(warm_start, design = NULL, split = NULL) {
  if (!inherits(warm_start, "glofas_normal_part3_ridge_warm_start") ||
      !identical(as.character(warm_start$type %||% "")[[1L]], "glofas_normal_part3_ridge_warm_start")) {
    stop("Expected a GloFAS Normal Part 3 ridge warm-start object.", call. = FALSE)
  }
  p <- as.integer(warm_start$fit$p %||% length(warm_start$fit$beta_mean))
  if (!is.finite(p) || p < 1L) stop("Part 3 warm-start p must be positive.", call. = FALSE)
  if (length(warm_start$fit$beta_mean) != p || length(warm_start$fit$beta_var_diag) != p) {
    stop("Part 3 warm-start coefficient moments have inconsistent dimensions.", call. = FALSE)
  }
  if (any(!is.finite(warm_start$fit$beta_mean)) || any(!is.finite(warm_start$fit$beta_var_diag))) {
    stop("Part 3 warm-start coefficient moments must be finite.", call. = FALSE)
  }
  if (!is.null(design)) {
    if (ncol(design$H) != p) stop("Part 3 warm-start dimension does not match stacked design.", call. = FALSE)
    if (as.integer(warm_start$block$p_beta) != as.integer(design$p_beta) ||
        as.integer(warm_start$block$p_alpha) != as.integer(design$p_alpha)) {
      stop("Part 3 warm-start block dimensions do not match design.", call. = FALSE)
    }
  }
  if (!is.null(design) && !is.null(split)) {
    stack_split <- app_glofas_normal_part3_stack_split(design, split)
    observed <- app_glofas_normal_part1_design_fingerprint(
      design$H[stack_split$train_idx, , drop = FALSE],
      design$z[stack_split$train_idx],
      design$row_info$date[stack_split$train_idx],
      design$feature_info
    )
    expected <- as.character(warm_start$design_hash$part3_stacked_train %||% "")
    if (nzchar(expected) && !identical(observed, expected)) {
      stop("Part 3 warm-start training design fingerprint mismatch.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

app_glofas_normal_part3_load_warm_start <- function(
  path,
  expected_sha256,
  design = NULL,
  split = NULL
) {
  path <- normalizePath(path, mustWork = TRUE)
  expected_sha256 <- tolower(trimws(as.character(expected_sha256 %||% "")[[1L]]))
  if (!grepl("^[0-9a-f]{64}$", expected_sha256)) {
    stop("Part 3 ridge warm-start requires an explicit SHA256 digest.", call. = FALSE)
  }
  observed_sha256 <- tolower(app_sha256_file(path))
  if (!identical(observed_sha256, expected_sha256)) {
    stop("Part 3 ridge warm-start SHA256 mismatch.", call. = FALSE)
  }
  warm_start <- readRDS(path)
  app_glofas_normal_part3_validate_warm_start(
    warm_start,
    design = design,
    split = split
  )
  attr(warm_start, "source_path") <- path
  attr(warm_start, "source_sha256") <- observed_sha256
  warm_start
}

app_glofas_normal_part3_predict_block <- function(fit, X, index, chunk_size = 64L) {
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  index <- as.integer(index)
  mean <- as.numeric(X %*% fit$beta_mean[index])
  beta_cov <- as.matrix(fit$beta_cov[index, index, drop = FALSE])
  sigma2 <- as.numeric(fit$sigma2_mean)
  if (!is.finite(sigma2) || sigma2 <= 0) sigma2 <- fit$sigma_b / max(fit$sigma_a, .Machine$double.eps)
  chunk_size <- as.integer(chunk_size %||% nrow(X))
  if (!is.finite(chunk_size) || chunk_size < 1L) chunk_size <- nrow(X)
  param_var <- numeric(nrow(X))
  starts <- seq.int(1L, nrow(X), by = chunk_size)
  for (st in starts) {
    en <- min(nrow(X), st + chunk_size - 1L)
    Xi <- X[st:en, , drop = FALSE]
    solved <- Xi %*% beta_cov
    param_var[st:en] <- rowSums(solved * Xi)
  }
  list(
    mean = mean,
    sd = sqrt(pmax(sigma2 + param_var, .Machine$double.eps)),
    leverage = param_var / max(sigma2, .Machine$double.eps)
  )
}

app_glofas_normal_part3_score_from_fit <- function(
  design,
  split,
  fit,
  candidate_row,
  method,
  started,
  trace = NULL,
  activity = NULL,
  coefficients = NULL
) {
  stack_split <- app_glofas_normal_part3_stack_split(design, split)
  ref_valid <- app_glofas_normal_part3_predict_block(
    fit,
    design$reference$X[split$valid_idx, , drop = FALSE],
    design$beta_index
  )
  disc_valid <- app_glofas_normal_part3_predict_block(
    fit,
    design$discrepancy$X[split$valid_idx, , drop = FALSE],
    design$alpha_index
  )
  ref_train <- app_glofas_normal_part3_predict_block(
    fit,
    design$reference$X[split$train_idx, , drop = FALSE],
    design$beta_index
  )
  disc_train <- app_glofas_normal_part3_predict_block(
    fit,
    design$discrepancy$X[split$train_idx, , drop = FALSE],
    design$alpha_index
  )
  joint_valid_y <- app_glofas_normal_predict(
    fit,
    design$H[stack_split$valid_y_idx, , drop = FALSE],
    chunk_size = 64L
  )
  joint_valid_g <- app_glofas_normal_predict(
    fit,
    design$H[stack_split$valid_g_idx, , drop = FALSE],
    chunk_size = 64L
  )
  joint_train_y <- app_glofas_normal_predict(
    fit,
    design$H[stack_split$train_y_idx, , drop = FALSE],
    chunk_size = 64L
  )
  joint_train_g <- app_glofas_normal_predict(
    fit,
    design$H[stack_split$train_g_idx, , drop = FALSE],
    chunk_size = 64L
  )
  corrected_valid <- list(
    mean = design$g_retrospective[split$valid_idx] - disc_valid$mean,
    sd = disc_valid$sd
  )
  corrected_train <- list(
    mean = design$g_retrospective[split$train_idx] - disc_train$mean,
    sd = disc_train$sd
  )
  detail <- data.frame(
    candidate_id = as.character(candidate_row$candidate_id[[1L]] %||% design$candidate_id),
    method = method,
    date = as.Date(design$dates[split$valid_idx]),
    observed_usgs = design$y_reference[split$valid_idx],
    retrospective_glofas = design$g_retrospective[split$valid_idx],
    observed_discrepancy = design$d_g[split$valid_idx],
    reference_mean = ref_valid$mean,
    reference_sd = ref_valid$sd,
    discrepancy_mean = disc_valid$mean,
    discrepancy_sd = disc_valid$sd,
    joint_usgs_mean = joint_valid_y$mean,
    joint_glofas_mean = joint_valid_g$mean,
    corrected_usgs_mean = corrected_valid$mean,
    corrected_usgs_sd = corrected_valid$sd,
    stringsAsFactors = FALSE
  )
  trace_tail <- if (!is.null(trace) && nrow(trace)) utils::tail(trace, 1L) else data.frame()
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  summary <- cbind(
    candidate_row,
    data.frame(
      status = "completed",
      method = method,
      n_dates_design = length(design$dates),
      n_stacked_rows_design = nrow(design$H),
      n_train_dates = length(split$train_idx),
      n_valid_dates = length(split$valid_idx),
      n_train_stacked_rows = length(stack_split$train_idx),
      n_valid_stacked_rows = length(stack_split$valid_idx),
      n_reference_readout_features = design$p_beta,
      n_discrepancy_readout_features = design$p_alpha,
      n_joint_readout_features = ncol(design$H),
      design_start_date = as.character(min(design$dates)),
      design_end_date = as.character(max(design$dates)),
      valid_start_date = as.character(min(design$dates[split$valid_idx])),
      valid_end_date = as.character(max(design$dates[split$valid_idx])),
      reference_design_hash = as.character(design$design_hash[["reference_full"]]),
      discrepancy_design_hash = as.character(design$design_hash[["discrepancy_full"]]),
      part3_stacked_design_hash = as.character(design$design_hash[["part3_stacked_full"]]),
      rhs_tau0_reference = as.numeric(candidate_row$rhs_tau0_reference[[1L]] %||% NA_real_),
      rhs_tau0_discrepancy = as.numeric(candidate_row$rhs_tau0_discrepancy[[1L]] %||% NA_real_),
      runtime_seconds = elapsed,
      iterations = as.integer(fit$iterations %||% NA_integer_),
      converged = isTRUE(fit$converged %||% TRUE),
      reference_effective_tau = as.numeric(trace_tail$reference_effective_tau[[1L]] %||% NA_real_),
      discrepancy_effective_tau = as.numeric(trace_tail$discrepancy_effective_tau[[1L]] %||% NA_real_),
      stringsAsFactors = FALSE
    ),
    app_glofas_normal_score_predictions(design$y_reference[split$train_idx], ref_train, prefix = "reference_train_"),
    app_glofas_normal_score_predictions(design$y_reference[split$valid_idx], ref_valid, prefix = "reference_valid_"),
    app_glofas_normal_score_predictions(design$d_g[split$train_idx], disc_train, prefix = "discrepancy_train_"),
    app_glofas_normal_score_predictions(design$d_g[split$valid_idx], disc_valid, prefix = "discrepancy_valid_"),
    app_glofas_normal_score_predictions(design$y_reference[split$train_idx], corrected_train, prefix = "corrected_train_"),
    app_glofas_normal_score_predictions(design$y_reference[split$valid_idx], corrected_valid, prefix = "corrected_valid_"),
    app_glofas_normal_score_predictions(design$y_reference[split$train_idx], joint_train_y, prefix = "joint_usgs_train_"),
    app_glofas_normal_score_predictions(design$y_reference[split$valid_idx], joint_valid_y, prefix = "joint_usgs_valid_"),
    app_glofas_normal_score_predictions(design$g_retrospective[split$train_idx], joint_train_g, prefix = "joint_glofas_train_"),
    app_glofas_normal_score_predictions(design$g_retrospective[split$valid_idx], joint_valid_g, prefix = "joint_glofas_valid_"),
    app_glofas_normal_part2_score_baseline(
      design$y_reference[split$valid_idx],
      design$g_retrospective[split$valid_idx],
      prefix = "raw_glofas_valid_"
    )
  )
  summary$valid_mean_crps <- summary$corrected_valid_mean_crps
  summary$valid_mae <- summary$corrected_valid_mae
  summary$valid_rmse <- summary$corrected_valid_rmse
  summary$primary_score_contract <- "historical_joint_corrected_usgs_from_retrospective_glofas_minus_predicted_discrepancy"
  list(
    summary = summary,
    detail = detail,
    trace = trace %||% data.frame(),
    activity = activity %||% data.frame(),
    coefficients = coefficients %||% data.frame(),
    fit = fit,
    design = design,
    split = split
  )
}

app_glofas_normal_part3_fit_ridge <- function(
  base_cfg,
  candidate_row,
  panel_bundle = NULL,
  reference_cache = NULL
) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  started <- Sys.time()
  design <- app_glofas_normal_part3_build_design(
    base_cfg,
    candidate_row,
    panel_bundle = panel_bundle,
    reference_cache = reference_cache
  )
  split <- app_glofas_normal_part3_validation_split(design, candidate_row)
  stack_split <- app_glofas_normal_part3_stack_split(design, split)
  ridge_tau2 <- as.numeric(app_glofas_normal_part2_row_value(candidate_row, "ridge_tau2", app_glofas_normal_part2_default_values()$ridge_tau2))
  intercept_var <- as.numeric(app_glofas_normal_part2_row_value(candidate_row, "intercept_var", app_glofas_normal_part2_default_values()$intercept_var))
  sigma_a <- as.numeric(app_glofas_normal_part2_row_value(candidate_row, "sigma_a", app_glofas_normal_part2_default_values()$sigma_a))
  sigma_b <- as.numeric(app_glofas_normal_part2_row_value(candidate_row, "sigma_b", app_glofas_normal_part2_default_values()$sigma_b))
  fit <- app_glofas_normal_ridge_fit(
    X = design$H[stack_split$train_idx, , drop = FALSE],
    y = design$z[stack_split$train_idx],
    ridge_tau2 = ridge_tau2,
    intercept_var = intercept_var,
    sigma_a = sigma_a,
    sigma_b = sigma_b
  )
  fit$type <- "normal_ridge_joint_historical"
  fit$iterations <- NA_integer_
  fit$converged <- TRUE
  warm_start <- app_glofas_normal_part3_make_ridge_warm_start(fit, design, split, candidate_row)
  out <- app_glofas_normal_part3_score_from_fit(
    design = design,
    split = split,
    fit = fit,
    candidate_row = candidate_row,
    method = "normal_scaled_ridge_joint_historical",
    started = started
  )
  out$warm_start <- warm_start
  out
}

app_glofas_normal_part3_rhs_trace_monitor <- function(stats, theta_mean, theta_cov, sigma_a, sigma_b, prior_prec, sse, chol_precision) {
  log_det_precision <- 2 * sum(log(pmax(abs(diag(chol_precision)), .Machine$double.eps)))
  e_inv_sigma2 <- sigma_a / sigma_b
  quad_prior <- sum(as.numeric(prior_prec) * diag(theta_cov + tcrossprod(theta_mean)))
  monitor <- -0.5 * (e_inv_sigma2 * sse + quad_prior - log_det_precision)
  data.frame(
    normal_block_rhs_coordinate_monitor = as.numeric(monitor),
    partial_elbo = as.numeric(monitor),
    expected_sse = as.numeric(sse),
    prior_quadratic_mean = as.numeric(quad_prior),
    log_det_precision = as.numeric(log_det_precision),
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_part3_rhs_fit_blocked <- function(
  X,
  y,
  ridge_warm_start,
  p_beta,
  p_alpha,
  reference_intercept_index = 1L,
  discrepancy_intercept_index = 1L,
  tau0_reference = 1,
  tau0_discrepancy = 1,
  a_zeta = 2,
  b_zeta = 4,
  max_iter = 100L,
  min_iter = 30L,
  tol = 1.0e-4,
  rhs_update_every = 1L,
  freeze_tau_warmup_iters = 0L,
  min_tau_updates = 0L,
  intercept_prec = 1.0e-9,
  jitter = 1.0e-8,
  progress_path = NULL,
  progress_every = 1L
) {
  if (!exists("app_latent_rhs_state_init", mode = "function")) {
    stop("Part 3 Normal RHS requires application/R/latent_path_vb_al.R to be sourced.", call. = FALSE)
  }
  X <- as.matrix(X)
  storage.mode(X) <- "double"
  y <- as.numeric(y)
  if (!nrow(X) || !ncol(X) || any(!is.finite(X))) stop("X must be finite.", call. = FALSE)
  if (length(y) != nrow(X) || any(!is.finite(y))) stop("y must match X and be finite.", call. = FALSE)
  app_glofas_normal_part3_validate_warm_start(ridge_warm_start)
  p <- ncol(X)
  p_beta <- as.integer(p_beta)
  p_alpha <- as.integer(p_alpha)
  if (p_beta + p_alpha != p) stop("Part 3 RHS block dimensions must sum to ncol(X).", call. = FALSE)
  if (as.integer(ridge_warm_start$fit$p) != p) {
    stop("Part 3 ridge warm-start dimension does not match X.", call. = FALSE)
  }
  reference_intercept_index <- as.integer(reference_intercept_index)
  discrepancy_intercept_index <- as.integer(discrepancy_intercept_index)
  if (!length(reference_intercept_index)) reference_intercept_index <- 1L
  if (!length(discrepancy_intercept_index)) discrepancy_intercept_index <- 1L
  max_iter <- as.integer(max_iter)
  min_iter <- as.integer(min_iter)
  tol <- as.numeric(tol)
  tau0_reference <- as.numeric(tau0_reference)
  tau0_discrepancy <- as.numeric(tau0_discrepancy)
  if (!is.finite(max_iter) || max_iter < 1L) stop("max_iter must be positive.", call. = FALSE)
  if (!is.finite(min_iter) || min_iter < 1L) stop("min_iter must be positive.", call. = FALSE)
  if (!is.finite(tol) || tol < 0) stop("tol must be finite and nonnegative.", call. = FALSE)
  if (!is.finite(tau0_reference) || tau0_reference <= 0) stop("tau0_reference must be positive.", call. = FALSE)
  if (!is.finite(tau0_discrepancy) || tau0_discrepancy <= 0) stop("tau0_discrepancy must be positive.", call. = FALSE)
  progress_path <- as.character(progress_path %||% "")[[1L]]
  progress_every <- as.integer(progress_every %||% 1L)
  if (!is.finite(progress_every) || progress_every < 1L) progress_every <- 1L
  if (nzchar(progress_path)) {
    app_ensure_dir(dirname(progress_path))
  }
  beta_index <- seq_len(p_beta)
  alpha_index <- p_beta + seq_len(p_alpha)
  stats <- list(
    n = nrow(X),
    p = p,
    XtX = crossprod(X),
    Xty = as.numeric(crossprod(X, y)),
    yty = as.numeric(crossprod(y))
  )
  m <- as.numeric(ridge_warm_start$fit$beta_mean)
  init_var <- pmax(as.numeric(ridge_warm_start$fit$beta_var_diag), 1.0e-12)
  V <- diag(init_var, p)
  sigma_a0 <- 2.0
  sigma_b0 <- 1.0
  sigma_a <- as.numeric(ridge_warm_start$fit$sigma_a %||% (sigma_a0 + nrow(X) / 2))
  sigma_b <- as.numeric(ridge_warm_start$fit$sigma_b %||% sigma_b0)
  if (!is.finite(sigma_a) || sigma_a <= 0) sigma_a <- sigma_a0 + nrow(X) / 2
  if (!is.finite(sigma_b) || sigma_b <= 0) sigma_b <- sigma_b0
  control <- list(
    update_every = rhs_update_every,
    freeze_tau_warmup_iters = freeze_tau_warmup_iters,
    min_tau_updates = min_tau_updates
  )
  beta_state <- app_latent_rhs_state_init(
    p = p_beta,
    intercept_index = reference_intercept_index,
    args = list(
      tau0 = tau0_reference,
      a_zeta = a_zeta,
      b_zeta = b_zeta,
      intercept_prec = intercept_prec
    ),
    rhs_control = control
  )
  alpha_state <- app_latent_rhs_state_init(
    p = p_alpha,
    intercept_index = discrepancy_intercept_index,
    args = list(
      tau0 = tau0_discrepancy,
      a_zeta = a_zeta,
      b_zeta = b_zeta,
      intercept_prec = intercept_prec
    ),
    rhs_control = control
  )
  beta_state <- app_latent_rhs_state_update(
    beta_state,
    theta_mean = m[beta_index],
    theta_cov = V[beta_index, beta_index, drop = FALSE],
    iter = 0L,
    update_global = FALSE
  )
  alpha_state <- app_latent_rhs_state_update(
    alpha_state,
    theta_mean = m[alpha_index],
    theta_cov = V[alpha_index, alpha_index, drop = FALSE],
    iter = 0L,
    update_global = FALSE
  )
  trace <- vector("list", max_iter)
  Pn <- NULL
  chol_P <- NULL
  converged <- FALSE
  final_delta <- NA_real_
  started <- Sys.time()
  for (iter in seq_len(max_iter)) {
    m_old <- m
    sigma2_old <- if (sigma_a > 1) sigma_b / (sigma_a - 1) else sigma_b / sigma_a
    e_inv_sigma2 <- sigma_a / sigma_b
    beta_prec <- app_latent_rhs_prior_precision(beta_state, p_beta)
    alpha_prec <- app_latent_rhs_prior_precision(alpha_state, p_alpha)
    prior_prec <- c(beta_prec, alpha_prec)
    if (length(prior_prec) != p || any(!is.finite(prior_prec)) || any(prior_prec <= 0)) {
      stop("Part 3 RHS prior precision must be finite and positive.", call. = FALSE)
    }
    Pn <- e_inv_sigma2 * stats$XtX
    diag(Pn) <- diag(Pn) + prior_prec
    hn <- e_inv_sigma2 * stats$Xty
    sol <- app_glofas_normal_spd_solve(Pn, hn, jitter = jitter)
    m <- sol$x
    V <- sol$inv
    chol_P <- sol$chol
    Emm <- V + tcrossprod(m)
    sse <- stats$yty - 2 * as.numeric(crossprod(m, stats$Xty)) + sum(stats$XtX * Emm)
    sse <- max(as.numeric(sse), .Machine$double.eps)
    sigma_a <- sigma_a0 + nrow(X) / 2
    sigma_b <- sigma_b0 + 0.5 * sse
    beta_state <- app_latent_rhs_state_update(
      beta_state,
      theta_mean = m[beta_index],
      theta_cov = V[beta_index, beta_index, drop = FALSE],
      iter = iter,
      update_global = NULL
    )
    alpha_state <- app_latent_rhs_state_update(
      alpha_state,
      theta_mean = m[alpha_index],
      theta_cov = V[alpha_index, alpha_index, drop = FALSE],
      iter = iter,
      update_global = NULL
    )
    sigma2_new <- if (sigma_a > 1) sigma_b / (sigma_a - 1) else sigma_b / sigma_a
    beta_delta <- max(abs(m - m_old))
    sigma_delta <- abs(sigma2_new - sigma2_old) / max(1, abs(sigma2_old))
    final_delta <- max(beta_delta, sigma_delta)
    beta_diag <- app_glofas_normal_rhs_state_diagnostics(beta_state, p_beta)
    names(beta_diag) <- paste0("reference_", names(beta_diag))
    alpha_diag <- app_glofas_normal_rhs_state_diagnostics(alpha_state, p_alpha)
    names(alpha_diag) <- paste0("discrepancy_", names(alpha_diag))
    monitor <- app_glofas_normal_part3_rhs_trace_monitor(
      stats = stats,
      theta_mean = m,
      theta_cov = V,
      sigma_a = sigma_a,
      sigma_b = sigma_b,
      prior_prec = c(
        app_latent_rhs_prior_precision(beta_state, p_beta),
        app_latent_rhs_prior_precision(alpha_state, p_alpha)
      ),
      sse = sse,
      chol_precision = chol_P
    )
    previous_monitor <- if (iter > 1L && length(trace[[iter - 1L]]) &&
                            "partial_elbo" %in% names(trace[[iter - 1L]])) {
      as.numeric(trace[[iter - 1L]]$partial_elbo[[1L]])
    } else {
      NA_real_
    }
    monitor$partial_elbo_delta <- if (is.finite(previous_monitor)) {
      as.numeric(monitor$partial_elbo[[1L]]) - previous_monitor
    } else {
      NA_real_
    }
    trace[[iter]] <- cbind(
      data.frame(
        iter = iter,
        sigma2_mean = sigma2_new,
        beta_max_abs_delta = beta_delta,
        sigma2_relative_delta = sigma_delta,
        max_delta = final_delta,
        jitter_attempt = sol$jitter_attempt,
        elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
        stringsAsFactors = FALSE
      ),
      beta_diag,
      alpha_diag,
      monitor
    )
    if (nzchar(progress_path) &&
        (iter == 1L || iter == max_iter || iter %% progress_every == 0L)) {
      app_write_csv(
        app_bind_rows_fill(trace[seq_len(iter)]),
        progress_path
      )
      message(sprintf(
        "Part 3 Normal RHS/VB iteration %d/%d: max_delta=%.6g, elapsed=%.1fs",
        iter,
        max_iter,
        final_delta,
        as.numeric(difftime(Sys.time(), started, units = "secs"))
      ))
    }
    if (iter >= min_iter && final_delta <= tol) {
      converged <- TRUE
      trace <- trace[seq_len(iter)]
      break
    }
  }
  trace_df <- app_bind_rows_fill(trace)
  sigma2_mean <- if (sigma_a > 1) sigma_b / (sigma_a - 1) else sigma_b / sigma_a
  fit <- list(
    type = "normal_rhs_vb_joint_historical",
    beta_mean = m,
    beta_cov = V,
    beta_var_diag = diag(V),
    precision = Pn,
    precision_chol = chol_P,
    sigma_a = sigma_a,
    sigma_b = sigma_b,
    sigma2_mean = sigma2_mean,
    rhs_state_reference = beta_state,
    rhs_state_discrepancy = alpha_state,
    rhs_tau0_reference = tau0_reference,
    rhs_tau0_discrepancy = tau0_discrepancy,
    a_zeta = a_zeta,
    b_zeta = b_zeta,
    trace = trace_df,
    converged = converged,
    iterations = nrow(trace_df),
    final_delta = final_delta,
    n_train = nrow(X),
    p = p,
    p_beta = p_beta,
    p_alpha = p_alpha,
    uses_vb = TRUE
  )
  class(fit) <- c("glofas_normal_part3_rhs_vb_fit", "glofas_normal_rhs_vb_fit", "list")
  fit
}

app_glofas_normal_part3_fit_rhs <- function(
  base_cfg,
  candidate_row,
  panel_bundle = NULL,
  reference_cache = NULL,
  warm_start = NULL,
  progress_path = NULL,
  progress_every = 1L
) {
  candidate_row <- candidate_row[1L, , drop = FALSE]
  started <- Sys.time()
  design <- app_glofas_normal_part3_build_design(
    base_cfg,
    candidate_row,
    panel_bundle = panel_bundle,
    reference_cache = reference_cache
  )
  split <- app_glofas_normal_part3_validation_split(design, candidate_row)
  stack_split <- app_glofas_normal_part3_stack_split(design, split)
  if (is.null(warm_start)) {
    warm_start <- app_glofas_normal_part3_fit_ridge(
      base_cfg,
      candidate_row,
      panel_bundle = panel_bundle,
      reference_cache = reference_cache
    )$warm_start
  }
  app_glofas_normal_part3_validate_warm_start(warm_start, design = design, split = split)
  fit <- app_glofas_normal_part3_rhs_fit_blocked(
    X = design$H[stack_split$train_idx, , drop = FALSE],
    y = design$z[stack_split$train_idx],
    ridge_warm_start = warm_start,
    p_beta = design$p_beta,
    p_alpha = design$p_alpha,
    reference_intercept_index = {
      idx <- app_constant_one_columns(design$reference$X)
      if (length(idx)) idx else 1L
    },
    discrepancy_intercept_index = {
      idx <- app_constant_one_columns(design$discrepancy$X)
      if (length(idx)) idx else 1L
    },
    tau0_reference = as.numeric(app_glofas_normal_part2_row_value(candidate_row, "rhs_tau0_reference", 1)),
    tau0_discrepancy = as.numeric(app_glofas_normal_part2_row_value(candidate_row, "rhs_tau0_discrepancy", 1)),
    max_iter = as.integer(app_glofas_normal_part2_row_value(candidate_row, "rhs_max_iter", 100L)),
    min_iter = as.integer(app_glofas_normal_part2_row_value(candidate_row, "rhs_min_iter", 30L)),
    tol = as.numeric(app_glofas_normal_part2_row_value(candidate_row, "rhs_tol", 1.0e-4)),
    rhs_update_every = as.integer(app_glofas_normal_part2_row_value(candidate_row, "rhs_update_every", 1L)),
    freeze_tau_warmup_iters = as.integer(app_glofas_normal_part2_row_value(candidate_row, "rhs_freeze_tau_warmup_iters", 0L)),
    min_tau_updates = as.integer(app_glofas_normal_part2_row_value(candidate_row, "rhs_min_tau_updates", 0L)),
    progress_path = progress_path,
    progress_every = progress_every
  )
  coefficients <- app_glofas_normal_part3_coefficient_table(fit, design)
  app_glofas_normal_part3_score_from_fit(
    design = design,
    split = split,
    fit = fit,
    candidate_row = candidate_row,
    method = "normal_block_rhs_vb_joint_historical",
    started = started,
    trace = fit$trace,
    coefficients = coefficients
  )
}

app_glofas_normal_part3_coefficient_table <- function(fit, design, level = 0.95) {
  mean <- as.numeric(fit$beta_mean)
  var <- pmax(as.numeric(fit$beta_var_diag), 0)
  z <- stats::qnorm((1 + level) / 2)
  out <- design$feature_info
  if (!nrow(out)) {
    out <- data.frame(
      column_name = colnames(design$H),
      global_column_index = seq_len(ncol(design$H)),
      stringsAsFactors = FALSE
    )
  }
  idx <- as.integer(out$global_column_index)
  out$posterior_mean <- mean[idx]
  out$posterior_sd <- sqrt(var[idx])
  out$ci_lower <- out$posterior_mean - z * out$posterior_sd
  out$ci_upper <- out$posterior_mean + z * out$posterior_sd
  out$credible_level <- level
  out$mean_abs <- abs(out$posterior_mean)
  out$interval_excludes_zero <- out$ci_lower > 0 | out$ci_upper < 0
  out
}

app_glofas_normal_part3_forecast_contract_template <- function() {
  data.frame(
    model_family = app_glofas_normal_part3_model_families()$model_family,
    forecast_surface = c(
      "normal_joint_recursive_oracle_adapter",
      "normal_joint_recursive_oracle_adapter",
      "quantile_joint_recursive_oracle_adapter",
      "quantile_joint_recursive_oracle_adapter",
      "quantile_joint_recursive_oracle_adapter",
      "quantile_joint_recursive_oracle_adapter"
    ),
    covariate_source = "realized_prism_era5_oracle_only",
    forbidden_sources = "CEFS,GEFS",
    rolling_origin_required = FALSE,
    launch_ready_without_frozen_g1_g2 = FALSE,
    status = c(
      "adapter_contract_declared_normal_runtime_not_launched",
      "adapter_contract_declared_normal_runtime_not_launched",
      "implemented_pending_frozen_runtime_preflight",
      "implemented_pending_frozen_runtime_preflight",
      "implemented_pending_frozen_runtime_preflight",
      "implemented_pending_frozen_runtime_preflight"
    ),
    stringsAsFactors = FALSE
  )
}

app_glofas_normal_part3_validate_forecast_contract <- function(contract) {
  app_check_required_columns(
    contract,
    c("model_family", "forecast_surface", "covariate_source", "forbidden_sources", "status"),
    "GloFAS Part 3 forecast contract"
  )
  bad <- grepl("cefs|gefs", tolower(as.character(contract$covariate_source)))
  if (any(bad)) stop("Part 3 forecast contract must not use CEFS/GEFS covariates.", call. = FALSE)
  invisible(TRUE)
}

app_glofas_normal_part3_launch_manifest <- function(
  selected_winner_manifest = NULL,
  run_label = "glofas_part3_joint_historical_deferred",
  require_frozen = TRUE
) {
  families <- app_glofas_normal_part3_model_families()
  quantiles <- app_glofas_normal_part3_quantile_grid()
  rows <- list(
    data.frame(
      run_label = run_label,
      model_family = "normal_ridge_joint",
      quantile = NA_real_,
      worker_slots = 1L,
      status = "blocked_missing_frozen_g1_g2_winner_manifest",
      launch_command = NA_character_,
      stringsAsFactors = FALSE
    ),
    data.frame(
      run_label = run_label,
      model_family = "normal_rhs_vb_joint",
      quantile = NA_real_,
      worker_slots = 1L,
      status = "blocked_missing_frozen_g1_g2_winner_manifest",
      launch_command = NA_character_,
      stringsAsFactors = FALSE
    ),
    data.frame(
      run_label = run_label,
      model_family = "independent_al_rhs_vb",
      quantile = quantiles,
      worker_slots = 1L,
      status = "implemented_via_part3_quantile_forecast_continuation",
      launch_command = NA_character_,
      stringsAsFactors = FALSE
    ),
    data.frame(
      run_label = run_label,
      model_family = "independent_exal_rhs_vb",
      quantile = quantiles,
      worker_slots = 1L,
      status = "implemented_via_part3_quantile_forecast_continuation",
      launch_command = NA_character_,
      stringsAsFactors = FALSE
    ),
    data.frame(
      run_label = run_label,
      model_family = "joint_al_rhs_vb",
      quantile = NA_real_,
      worker_slots = 1L,
      status = "implemented_via_part3_quantile_forecast_continuation",
      launch_command = NA_character_,
      stringsAsFactors = FALSE
    ),
    data.frame(
      run_label = run_label,
      model_family = "joint_exal_rhs_vb",
      quantile = NA_real_,
      worker_slots = 1L,
      status = "implemented_via_part3_quantile_forecast_continuation",
      launch_command = NA_character_,
      stringsAsFactors = FALSE
    )
  )
  manifest <- app_bind_rows_fill(rows)
  manifest$model_status <- families$status[match(manifest$model_family, families$model_family)]
  if (!is.null(selected_winner_manifest)) {
    validated <- app_glofas_normal_part3_validate_winner_manifest(
      selected_winner_manifest,
      require_frozen = require_frozen
    )
    manifest$status[manifest$model_family %in% c("normal_ridge_joint", "normal_rhs_vb_joint")] <- "ready_after_operator_launch_approval"
    manifest$selected_reference_candidate_id <- app_glofas_normal_part3_winner_row(validated, "reference", "G1")$candidate_id[[1L]]
    manifest$selected_discrepancy_candidate_id <- app_glofas_normal_part3_winner_row(validated, "discrepancy", "G2")$candidate_id[[1L]]
  }
  manifest
}
