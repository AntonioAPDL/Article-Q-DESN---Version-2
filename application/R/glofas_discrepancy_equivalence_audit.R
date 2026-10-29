# White-box diagnostics for near-equivalent GloFAS discrepancy forecasts.

app_glofas_equivalence_required_columns <- function(x, required, label) {
  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf("%s is missing columns: %s", label, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_equivalence_scalar <- function(x, default = NA_character_) {
  if (is.null(x) || !length(x)) return(default)
  paste(as.character(unlist(x, recursive = TRUE, use.names = FALSE)), collapse = ";")
}

app_glofas_equivalence_hash <- function(x, prefix = "glofas_equivalence_") {
  app_latent_path_contract_hash(x, prefix = prefix)
}

app_glofas_equivalence_status_precedence <- function(runtime_root) {
  paths <- c(
    strict_finalization = file.path(runtime_root, "finalization_status.csv"),
    terminal_census = file.path(runtime_root, "candidate_state_census.csv"),
    mutable_health_snapshot = file.path(runtime_root, "health_summary.csv")
  )
  present <- stats::setNames(file.exists(paths), names(paths))
  if (!present[["strict_finalization"]] || !present[["terminal_census"]]) {
    stop("A strict finalization certificate and terminal candidate census are required.", call. = FALSE)
  }
  finalization <- app_read_csv(paths[["strict_finalization"]])
  census <- app_read_csv(paths[["terminal_census"]])
  if (nrow(finalization) != 1L || !isTRUE(as.logical(finalization$batch_complete[[1L]]))) {
    stop("The campaign is not certified complete by finalization_status.csv.", call. = FALSE)
  }
  if (!nrow(census) || any(!as.logical(census$terminal_for_strict_closeout))) {
    stop("The candidate census contains nonterminal candidates.", call. = FALSE)
  }
  data.frame(
    source = names(paths),
    path = unname(paths),
    exists = present,
    precedence = seq_along(paths),
    authoritative_for_terminal_state = names(paths) %in% c("strict_finalization", "terminal_census"),
    selected = names(paths) == "strict_finalization",
    reason = c(
      "immutable strict closeout certificate",
      "candidate-level terminal source of truth",
      "mutable monitoring snapshot; never overrides strict closeout"
    ),
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_campaign_certificate <- function(runtime_root) {
  finalization <- app_read_csv(file.path(runtime_root, "finalization_status.csv"))
  census <- app_read_csv(file.path(runtime_root, "candidate_state_census.csv"))
  counts <- table(factor(
    census$state,
    levels = c("completed", "preflight_rejected", "failed", "incomplete")
  ))
  data.frame(
    batch_complete = isTRUE(as.logical(finalization$batch_complete[[1L]])),
    total_candidates = nrow(census),
    completed_candidates = unname(counts[["completed"]]),
    preflight_rejected_candidates = unname(counts[["preflight_rejected"]]),
    failed_candidates = unname(counts[["failed"]]),
    incomplete_candidates = sum(!as.logical(census$terminal_for_strict_closeout)),
    terminal_candidates = sum(as.logical(census$terminal_for_strict_closeout)),
    finalization_status = as.character(finalization$status[[1L]]),
    finalization_timestamp = as.character(finalization$timestamp[[1L]]),
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_layer_labels <- function(feature_info, block_cfg = NULL) {
  labels <- rep(NA_character_, nrow(feature_info))
  reservoir_index <- which(as.character(feature_info$block) == "reservoir_state")
  if (!length(reservoir_index)) return(labels)
  widths <- suppressWarnings(as.integer(unlist(
    ((block_cfg %||% list())$reservoir %||% list())$n %||% length(reservoir_index),
    use.names = FALSE
  )))
  widths <- widths[is.finite(widths) & widths > 0L]
  if (!length(widths) || sum(widths) != length(reservoir_index)) widths <- length(reservoir_index)
  layer <- rep(seq_along(widths), widths)
  labels[reservoir_index] <- sprintf("reservoir_layer_%02d", layer)
  labels
}

app_glofas_equivalence_feature_groups <- function(feature_info, block_cfg = NULL) {
  app_glofas_equivalence_required_columns(
    feature_info,
    c("column_index", "column_name", "block", "variable", "lag"),
    "feature_info"
  )
  groups <- app_glofas_mechanism_feature_group(feature_info)
  layers <- app_glofas_equivalence_layer_labels(feature_info, block_cfg)
  reservoir <- !is.na(layers)
  groups[reservoir] <- layers[reservoir]
  groups
}

app_glofas_equivalence_feature_layout <- function(
  X,
  feature_info,
  component,
  block_cfg = NULL
) {
  X <- as.matrix(X)
  if (ncol(X) != nrow(feature_info)) {
    stop("Feature layout requires one metadata row per design column.", call. = FALSE)
  }
  if (anyDuplicated(feature_info$column_index) || anyDuplicated(feature_info$column_name)) {
    stop("Feature layout contains duplicated indices or names.", call. = FALSE)
  }
  if (!identical(as.integer(feature_info$column_index), seq_len(ncol(X)))) {
    stop("Feature layout indices are not contiguous and ordered.", call. = FALSE)
  }
  if (!is.null(colnames(X)) && !identical(as.character(colnames(X)), as.character(feature_info$column_name))) {
    stop("Design column names do not match feature metadata.", call. = FALSE)
  }
  data.frame(
    component = component,
    column_index = as.integer(feature_info$column_index),
    column_name = as.character(feature_info$column_name),
    feature_group = app_glofas_equivalence_feature_groups(feature_info, block_cfg),
    block = as.character(feature_info$block),
    variable = as.character(feature_info$variable),
    lag = suppressWarnings(as.integer(feature_info$lag)),
    anchor = as.character(feature_info$anchor),
    is_intercept = as.logical(feature_info$is_intercept),
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_layout_hash <- function(layout, component) {
  app_glofas_equivalence_hash(
    list(schema_version = "glofas_feature_layout_v1", component = component, layout = layout),
    prefix = paste0("glofas_", component, "_layout_")
  )
}

app_glofas_equivalence_sentinel_tests <- function(
  X,
  feature_info,
  block_cfg = NULL,
  sentinel = 2.75,
  tolerance = 1e-10
) {
  X <- as.matrix(X)
  layout <- app_glofas_equivalence_feature_layout(X, feature_info, "alpha", block_cfg)
  groups <- split(layout$column_index, layout$feature_group)
  rows <- lapply(names(groups), function(group) {
    index <- groups[[group]][[1L]]
    alpha <- numeric(ncol(X))
    alpha[[index]] <- sentinel
    paths <- app_latent_path_component_paths(
      matrix(0, nrow(X), 1L), X, 0, alpha, rep(0, nrow(X))
    )
    expected <- sentinel * X[, index]
    error <- paths$d_g - expected
    data.frame(
      feature_group = group,
      column_index = index,
      column_name = layout$column_name[[index]],
      sentinel = sentinel,
      max_abs_error = max(abs(error)),
      tolerance = tolerance,
      passed = max(abs(error)) <= tolerance,
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_equivalence_permutation_tests <- function(X, feature_info, tolerance = 1e-10) {
  X <- as.matrix(X)
  p <- ncol(X)
  if (p < 2L) stop("Permutation tests require at least two features.", call. = FALSE)
  coefficient <- seq_len(p) / p
  permutation <- rev(seq_len(p))
  baseline <- as.numeric(X %*% coefficient)
  paired <- as.numeric(X[, permutation, drop = FALSE] %*% coefficient[permutation])
  unpaired <- as.numeric(X[, permutation, drop = FALSE] %*% coefficient)
  metadata_error <- tryCatch({
    app_glofas_equivalence_feature_layout(
      X,
      feature_info[permutation, , drop = FALSE],
      "alpha"
    )
    FALSE
  }, error = function(e) TRUE)
  data.frame(
    test = c("paired_feature_coefficient_permutation", "unpaired_feature_permutation", "metadata_only_permutation"),
    max_abs_difference = c(max(abs(paired - baseline)), max(abs(unpaired - baseline)), NA_real_),
    expected = c("invariant", "changes", "rejected"),
    passed = c(
      max(abs(paired - baseline)) <= tolerance,
      max(abs(unpaired - baseline)) > tolerance,
      metadata_error
    ),
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_serialization_parity <- function(X, feature_info, tolerance = 1e-12) {
  payload <- list(X = as.matrix(X), feature_info = feature_info)
  path <- tempfile("glofas_equivalence_serialization_", fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  before_hash <- app_glofas_equivalence_hash(payload, "glofas_serialization_before_")
  saveRDS(payload, path, version = 3L)
  restored <- readRDS(path)
  after_hash <- app_glofas_equivalence_hash(restored, "glofas_serialization_before_")
  coefficient <- seq_len(ncol(X)) / max(1L, ncol(X))
  before <- as.numeric(payload$X %*% coefficient)
  after <- as.numeric(restored$X %*% coefficient)
  data.frame(
    exact_dimensions = identical(dim(payload$X), dim(restored$X)),
    exact_feature_metadata = identical(payload$feature_info, restored$feature_info),
    exact_semantic_hash = identical(before_hash, after_hash),
    max_abs_prediction_difference = max(abs(before - after)),
    tolerance = tolerance,
    passed = identical(before_hash, after_hash) && max(abs(before - after)) <= tolerance,
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_cache_mutation_tests <- function() {
  root <- tempfile("glofas_equivalence_cache_")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  cache_cfg <- list(
    enabled = TRUE,
    root = root,
    wait_seconds = 0.1,
    poll_seconds = 0.01,
    schema_version = "glofas_reference_feature_cache_v1"
  )
  base <- list(
    block_role = "reference", panel = "panel-a", cutoff = "dec25_2022",
    seed = 20260512L, config = "cfg-a", engine = "engine-a"
  )
  make_contract <- function(x) {
    list(
      block_role = x$block_role,
      contract_hash = app_glofas_equivalence_hash(x, "glofas_cache_contract_")
    )
  }
  builds <- 0L
  builder <- function() {
    builds <<- builds + 1L
    list(feature = list(X = diag(2L)), qfit = list(seed = builds))
  }
  first <- app_latent_reference_feature_cache_get_or_build(cache_cfg, make_contract(base), builder)
  second <- app_latent_reference_feature_cache_get_or_build(cache_cfg, make_contract(base), builder)
  rows <- list(data.frame(
    mutation = "none_warm_cache",
    expected = "hit_identical",
    cache_hit = isTRUE(second$diagnostics$hit),
    contract_changed = FALSE,
    passed = isTRUE(second$diagnostics$hit) && identical(first$beta_block, second$beta_block),
    stringsAsFactors = FALSE
  ))
  mutations <- list(
    panel = "panel-b", cutoff = "jan01_2023", seed = 20261521L,
    config = "cfg-b", engine = "engine-b"
  )
  for (name in names(mutations)) {
    changed <- base
    changed[[name]] <- mutations[[name]]
    value <- app_latent_reference_feature_cache_get_or_build(cache_cfg, make_contract(changed), builder)
    rows[[length(rows) + 1L]] <- data.frame(
      mutation = name,
      expected = "cache_miss",
      cache_hit = isTRUE(value$diagnostics$hit),
      contract_changed = !identical(make_contract(base)$contract_hash, make_contract(changed)$contract_hash),
      passed = !isTRUE(value$diagnostics$hit),
      stringsAsFactors = FALSE
    )
  }
  discrepancy <- base
  discrepancy$block_role <- "discrepancy"
  rejected <- tryCatch({
    app_latent_reference_feature_cache_get_or_build(cache_cfg, make_contract(discrepancy), builder)
    FALSE
  }, error = function(e) TRUE)
  rows[[length(rows) + 1L]] <- data.frame(
    mutation = "discrepancy_block_role",
    expected = "rejected",
    cache_hit = FALSE,
    contract_changed = TRUE,
    passed = rejected,
    stringsAsFactors = FALSE
  )
  app_bind_rows_fill(rows)
}

app_glofas_equivalence_sample_indices <- function(n, maximum) {
  if (!is.finite(n) || n < 1L) return(integer())
  unique(as.integer(round(seq(1L, n, length.out = min(as.integer(n), as.integer(maximum))))))
}

app_glofas_equivalence_matrix_sketch <- function(X, max_rows = 512L, max_cols = 128L) {
  X <- as.matrix(X)
  row_index <- app_glofas_equivalence_sample_indices(nrow(X), max_rows)
  col_index <- app_glofas_equivalence_sample_indices(ncol(X), max_cols)
  Z <- X[row_index, col_index, drop = FALSE]
  center <- colMeans(Z)
  scale <- apply(Z, 2L, app_glofas_mechanism_safe_sd)
  Z <- sweep(sweep(Z, 2L, center, "-"), 2L, scale, "/")
  list(
    Z = Z,
    row_profile = rowMeans(Z),
    row_energy = sqrt(rowMeans(Z^2)),
    n_rows = nrow(X),
    n_cols = ncol(X),
    sampled_rows = length(row_index),
    sampled_cols = length(col_index)
  )
}

app_glofas_equivalence_subspace_similarity <- function(a, b, tolerance = 1e-10) {
  n <- min(nrow(a$Z), nrow(b$Z))
  A <- a$Z[seq_len(n), , drop = FALSE]
  B <- b$Z[seq_len(n), , drop = FALSE]
  qa <- qr.Q(qr(A, tol = tolerance))
  qb <- qr.Q(qr(B, tol = tolerance))
  values <- svd(crossprod(qa, qb), nu = 0L, nv = 0L)$d
  c(
    leading_canonical_correlation = if (length(values)) max(values) else NA_real_,
    median_canonical_correlation = if (length(values)) stats::median(values) else NA_real_
  )
}

app_glofas_equivalence_pairwise_sketch_distance <- function(a, b, pair, object) {
  similarity <- app_glofas_equivalence_subspace_similarity(a, b)
  n <- min(length(a$row_profile), length(b$row_profile))
  profile_difference <- a$row_profile[seq_len(n)] - b$row_profile[seq_len(n)]
  energy_difference <- a$row_energy[seq_len(n)] - b$row_energy[seq_len(n)]
  data.frame(
    candidate_a = pair[[1L]],
    candidate_b = pair[[2L]],
    object = object,
    n_rows_a = a$n_rows,
    n_rows_b = b$n_rows,
    n_features_a = a$n_cols,
    n_features_b = b$n_cols,
    sampled_rows = n,
    leading_canonical_correlation = similarity[["leading_canonical_correlation"]],
    median_canonical_correlation = similarity[["median_canonical_correlation"]],
    row_profile_rmse = sqrt(mean(profile_difference^2)),
    row_energy_rmse = sqrt(mean(energy_difference^2)),
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_state_summary <- function(
  X,
  candidate_id,
  period,
  block_cfg = NULL,
  saturation_abs = 0.995,
  dead_tolerance = 1e-8
) {
  X <- as.matrix(X)
  widths <- suppressWarnings(as.integer(unlist(
    ((block_cfg %||% list())$reservoir %||% list())$n %||% ncol(X),
    use.names = FALSE
  )))
  widths <- widths[is.finite(widths) & widths > 0L]
  if (!length(widths) || sum(widths) != ncol(X)) widths <- ncol(X)
  ends <- cumsum(widths)
  starts <- c(1L, head(ends, -1L) + 1L)
  rows <- lapply(seq_along(widths), function(layer) {
    Z <- X[, starts[[layer]]:ends[[layer]], drop = FALSE]
    sample_rows <- app_glofas_equivalence_sample_indices(nrow(Z), 1000L)
    Zs <- Z[sample_rows, , drop = FALSE]
    finite_fraction <- mean(is.finite(Zs))
    sds <- apply(Zs, 2L, app_glofas_mechanism_safe_sd)
    live <- sds > dead_tolerance
    rank_entropy <- NA_real_
    rank_participation <- NA_real_
    condition <- NA_real_
    near_duplicate <- NA_real_
    if (all(is.finite(Zs)) && any(live) && nrow(Zs) > 1L) {
      Zlive <- scale(Zs[, live, drop = FALSE])
      Zlive[!is.finite(Zlive)] <- 0
      singular <- svd(Zlive, nu = 0L, nv = 0L)$d
      lambda <- singular^2
      if (sum(lambda) > 0) {
        probability <- lambda / sum(lambda)
        probability <- probability[probability > 0]
        rank_entropy <- exp(-sum(probability * log(probability)))
        rank_participation <- sum(lambda)^2 / sum(lambda^2)
        positive <- singular[singular > max(singular) * 1e-10]
        condition <- if (length(positive) == min(dim(Zlive))) max(positive) / min(positive) else Inf
      }
      if (ncol(Zlive) > 1L) {
        C <- abs(stats::cor(Zlive))
        near_duplicate <- mean(C[upper.tri(C)] > 0.999)
      }
    }
    data.frame(
      candidate_id = candidate_id,
      period = period,
      layer = layer,
      n_rows = nrow(Z),
      n_states = ncol(Z),
      finite_fraction = finite_fraction,
      dead_fraction = mean(!live),
      saturation_fraction = mean(abs(Zs) >= saturation_abs, na.rm = TRUE),
      state_mean = mean(Zs, na.rm = TRUE),
      state_sd_median = stats::median(sds),
      state_sd_p90 = unname(stats::quantile(sds, 0.9)),
      state_sd_max = max(sds),
      effective_rank_entropy = rank_entropy,
      effective_rank_participation = rank_participation,
      relative_effective_rank_entropy = rank_entropy / min(nrow(Zs), ncol(Zs)),
      condition_z = condition,
      near_duplicate_fraction = near_duplicate,
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_equivalence_contribution_paths <- function(
  X,
  coefficients,
  feature_info,
  candidate_id,
  period,
  horizon,
  block_cfg = NULL
) {
  X <- as.matrix(X)
  coefficients <- as.numeric(coefficients)
  if (ncol(X) != length(coefficients) || nrow(feature_info) != ncol(X)) {
    stop("Contribution decomposition received an unaligned design.", call. = FALSE)
  }
  groups <- app_glofas_equivalence_feature_groups(feature_info, block_cfg)
  rows <- lapply(split(seq_len(ncol(X)), groups), function(index) {
    value <- as.numeric(X[, index, drop = FALSE] %*% coefficients[index])
    data.frame(
      candidate_id = candidate_id,
      period = period,
      row_index = seq_len(nrow(X)),
      horizon = as.integer(horizon),
      feature_group = groups[index[[1L]]],
      contribution = value,
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_equivalence_contribution_summary <- function(paths, coefficients, feature_info, block_cfg = NULL) {
  groups <- app_glofas_equivalence_feature_groups(feature_info, block_cfg)
  coefficient_rows <- lapply(split(seq_along(coefficients), groups), function(index) {
    data.frame(
      feature_group = groups[index[[1L]]],
      n_coefficients = length(index),
      coefficient_l1 = sum(abs(coefficients[index])),
      coefficient_l2 = sqrt(sum(coefficients[index]^2)),
      coefficient_max_abs = max(abs(coefficients[index])),
      coefficient_participation_ratio = if (sum(coefficients[index]^4) > 0) {
        sum(coefficients[index]^2)^2 / sum(coefficients[index]^4)
      } else 0,
      stringsAsFactors = FALSE
    )
  })
  contribution <- lapply(split(paths, paths$feature_group), function(x) {
    data.frame(
      candidate_id = x$candidate_id[[1L]],
      period = x$period[[1L]],
      feature_group = x$feature_group[[1L]],
      contribution_mean = mean(x$contribution),
      contribution_sd = stats::sd(x$contribution),
      contribution_rms = sqrt(mean(x$contribution^2)),
      contribution_max_abs = max(abs(x$contribution)),
      stringsAsFactors = FALSE
    )
  })
  merge(app_bind_rows_fill(contribution), app_bind_rows_fill(coefficient_rows), by = "feature_group", all.x = TRUE)
}

app_glofas_equivalence_posterior_contribution_uncertainty <- function(
  X,
  coefficient_draws,
  feature_info,
  candidate_id,
  block_cfg = NULL,
  practical_tolerance = 1e-4
) {
  X <- as.matrix(X)
  coefficient_draws <- as.matrix(coefficient_draws)
  groups <- app_glofas_equivalence_feature_groups(feature_info, block_cfg)
  rows <- lapply(split(seq_len(ncol(X)), groups), function(index) {
    value <- X[, index, drop = FALSE] %*% t(coefficient_draws[, index, drop = FALSE])
    draw_rms <- sqrt(colMeans(value^2))
    data.frame(
      candidate_id = candidate_id,
      feature_group = groups[index[[1L]]],
      n_draws = ncol(value),
      posterior_contribution_mean = mean(value),
      posterior_contribution_sd = stats::sd(as.numeric(value)),
      posterior_draw_rms_median = stats::median(draw_rms),
      posterior_draw_rms_p90 = unname(stats::quantile(draw_rms, 0.9)),
      fraction_practically_nonzero = mean(draw_rms > practical_tolerance),
      practical_tolerance = practical_tolerance,
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_equivalence_ablation_paths <- function(
  contributions,
  discrepancy_baseline,
  observed_discrepancy,
  raw_glofas,
  observed_y
) {
  horizons <- sort(unique(contributions$horizon))
  groups <- unique(contributions$feature_group)
  matrix_by_group <- sapply(groups, function(group) {
    x <- contributions[contributions$feature_group == group, , drop = FALSE]
    x$contribution[match(horizons, x$horizon)]
  })
  if (is.null(dim(matrix_by_group))) matrix_by_group <- matrix(matrix_by_group, ncol = 1L)
  colnames(matrix_by_group) <- groups
  reservoir <- grepl("^reservoir_layer_", groups)
  direct <- !reservoir
  scenarios <- list(
    all_as_fitted = rep(TRUE, length(groups)),
    persistence_only = rep(FALSE, length(groups)),
    direct_only = direct,
    reservoir_only = reservoir,
    no_direct_ppt = !grepl("direct_covariate_lag:ppt", groups, fixed = TRUE),
    no_direct_soil = !grepl("direct_covariate_lag:soil", groups, fixed = TRUE),
    no_direct_output_lags = groups != "direct_output_lag"
  )
  for (group in groups[reservoir]) {
    scenarios[[paste0(group, "_only")]] <- groups == group
  }
  rows <- lapply(names(scenarios), function(scenario) {
    keep <- scenarios[[scenario]]
    innovation <- if (any(keep)) rowSums(matrix_by_group[, keep, drop = FALSE]) else rep(0, length(horizons))
    discrepancy <- as.numeric(discrepancy_baseline) + innovation
    corrected <- as.numeric(raw_glofas) - discrepancy
    data.frame(
      scenario = scenario,
      horizon = horizons,
      discrepancy_prediction = discrepancy,
      observed_discrepancy = observed_discrepancy,
      corrected_reference_prediction = corrected,
      observed_reference = observed_y,
      discrepancy_mae = mean(abs(discrepancy - observed_discrepancy)),
      reference_check_loss = mean(0.5 * abs(corrected - observed_y)),
      diagnostic_status = "post_fit_diagnostic_only",
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_equivalence_prediction_identity <- function(draws, tolerance = 1e-10) {
  app_glofas_equivalence_required_columns(
    draws, c("q_y_draw", "q_g_draw", "d_g_draw", "horizon"), "posterior draw table"
  )
  error <- as.numeric(draws$q_g_draw) - as.numeric(draws$q_y_draw) - as.numeric(draws$d_g_draw)
  data.frame(
    n_rows = nrow(draws),
    max_abs_identity_error = max(abs(error)),
    mean_abs_identity_error = mean(abs(error)),
    tolerance = tolerance,
    passed = max(abs(error)) <= tolerance,
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_exact_parity <- function(
  design,
  fit,
  candidate_id,
  draw_subset = 3L,
  alpha_tolerance = 1e-8,
  beta_first_order_tolerance = 0.05
) {
  linearization <- fit$variational_state$future_linearization
  if (is.null(linearization)) stop("Retained fit lacks future linearization.", call. = FALSE)
  theta_draws <- as.matrix(fit$draws$theta)
  y_draws <- as.matrix(fit$draws$y_future)
  draw_index <- app_glofas_mechanism_draw_indices(nrow(y_draws), draw_subset)
  rows <- lapply(draw_index, function(index) {
    exact <- app_glofas_mechanism_exact_future_design(design, y_draws[index, ])
    X_beta_linear <- app_glofas_mechanism_linearized_design(linearization, y_draws[index, ], "beta")
    X_alpha_linear <- app_glofas_mechanism_linearized_design(linearization, y_draws[index, ], "alpha")
    beta <- theta_draws[index, design$beta_index]
    alpha <- theta_draws[index, design$alpha_index]
    baseline <- exact$discrepancy_baseline_future
    linear <- app_latent_path_component_paths(X_beta_linear, X_alpha_linear, beta, alpha, baseline)
    rebuilt <- app_latent_path_component_paths(exact$X_beta_future, exact$X_alpha_future, beta, alpha, baseline)
    data.frame(
      candidate_id = candidate_id,
      draw_index = index,
      max_abs_X_beta_difference = max(abs(exact$X_beta_future - X_beta_linear)),
      max_abs_X_alpha_difference = max(abs(exact$X_alpha_future - X_alpha_linear)),
      max_abs_q_y_difference = max(abs(rebuilt$q_y - linear$q_y)),
      max_abs_d_g_difference = max(abs(rebuilt$d_g - linear$d_g)),
      max_abs_q_g_difference = max(abs(rebuilt$q_g - linear$q_g)),
      alpha_tolerance = alpha_tolerance,
      beta_first_order_tolerance = beta_first_order_tolerance,
      alpha_exact_passed = max(abs(rebuilt$d_g - linear$d_g)) <= alpha_tolerance,
      beta_first_order_passed = max(abs(rebuilt$q_y - linear$q_y)) <= beta_first_order_tolerance,
      passed = max(abs(rebuilt$d_g - linear$d_g)) <= alpha_tolerance &&
        max(abs(rebuilt$q_y - linear$q_y)) <= beta_first_order_tolerance,
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

app_glofas_equivalence_transition_contract <- function(design, candidate_id, tolerance = 1e-12) {
  strategy <- design$discrepancy_transition_strategy %||% "recursive_level"
  baseline <- as.numeric(design$discrepancy_baseline_future)
  last_discrepancy <- utils::tail(as.numeric(design$future_context$d_history_full), 1L)
  linearization <- design$future_context
  data.frame(
    candidate_id = candidate_id,
    transition_strategy = strategy,
    n_horizons = length(baseline),
    last_observed_discrepancy = last_discrepancy,
    baseline_max_abs_difference_from_last = max(abs(baseline - last_discrepancy)),
    expected_persistence = identical(strategy, "persistence_anchored_innovation"),
    passed = !identical(strategy, "persistence_anchored_innovation") ||
      max(abs(baseline - last_discrepancy)) <= tolerance,
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_independent_score <- function(score_table, tolerance = 1e-10) {
  q <- score_table[score_table$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (!nrow(q)) stop("Score table has no Q-DESN discrepancy rows.", call. = FALSE)
  reconstructed <- ifelse(
    q$y_reference >= q$qhat,
    q$quantile_level * (q$y_reference - q$qhat),
    (1 - q$quantile_level) * (q$qhat - q$y_reference)
  )
  data.frame(
    n_rows = nrow(q),
    exported_mean_check_loss = mean(q$check_loss),
    reconstructed_mean_check_loss = mean(reconstructed),
    max_abs_row_difference = max(abs(reconstructed - q$check_loss)),
    tolerance = tolerance,
    passed = max(abs(reconstructed - q$check_loss)) <= tolerance,
    stringsAsFactors = FALSE
  )
}

app_glofas_equivalence_root_cause_decision <- function(
  implementation_checks,
  forecast_contribution_summary,
  ablation_paths,
  discrepancy_paths,
  reservoir_share_threshold = 0.10
) {
  implementation_passed <- all(implementation_checks$passed)
  forecast <- forecast_contribution_summary
  reservoir_rms <- sum(forecast$contribution_rms[grepl("^reservoir_layer_", forecast$feature_group)], na.rm = TRUE)
  direct_rms <- sum(forecast$contribution_rms[!grepl("^reservoir_layer_", forecast$feature_group)], na.rm = TRUE)
  reservoir_share <- reservoir_rms / max(reservoir_rms + direct_rms, .Machine$double.eps)
  ablation_score <- unique(ablation_paths[c("scenario", "discrepancy_mae", "reference_check_loss")])
  full_mae <- ablation_score$discrepancy_mae[ablation_score$scenario == "all_as_fitted"][[1L]]
  direct_mae <- ablation_score$discrepancy_mae[ablation_score$scenario == "direct_only"][[1L]]
  direct_near_full <- abs(direct_mae - full_mae) <= 0.02 * max(1, abs(full_mae))
  observed_shift <- abs(mean(discrepancy_paths$observed_discrepancy) - mean(discrepancy_paths$predicted_discrepancy))
  primary <- if (!implementation_passed) {
    "implementation_or_provenance_defect"
  } else if (reservoir_share < reservoir_share_threshold && direct_near_full) {
    "rhs_readout_suppression_with_common_direct_feature_dominance"
  } else if (reservoir_share < reservoir_share_threshold) {
    "rhs_readout_suppression"
  } else {
    "transition_or_information_bottleneck"
  }
  data.frame(
    primary_root_cause = primary,
    implementation_passed = implementation_passed,
    forecast_reservoir_rms_share = reservoir_share,
    reservoir_share_threshold = reservoir_share_threshold,
    direct_only_near_full = direct_near_full,
    all_as_fitted_discrepancy_mae = full_mae,
    direct_only_discrepancy_mae = direct_mae,
    observed_forecast_discrepancy_level_gap = observed_shift,
    secondary_mechanism = if (observed_shift > 0.5) {
      "persistence_anchor_and_forecast_regime_shift"
    } else {
      "no_large_forecast_level_shift_detected"
    },
    broad_screen_authorized = FALSE,
    full7_authorized = FALSE,
    article_update_authorized = FALSE,
    next_gate = if (!implementation_passed) {
      "repair_failed_white_box_contract_before_any_fit"
    } else {
      "review_no_refit_diagnosis_then_authorize_minimal_rhs_or_transition_canaries"
    },
    stringsAsFactors = FALSE
  )
}
