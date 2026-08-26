# Staged repair campaign for causal GloFAS discrepancy context.

app_glofas_context_repair_required_candidate_columns <- function() {
  c(
    app_glofas_transition_required_candidate_columns(),
    "execution_stage", "warm_start_source_candidate",
    "warm_start_compatibility_mode", "warm_start_use_theta",
    "warm_start_use_future", "warm_start_use_sigma"
  )
}

app_glofas_context_repair_validate_candidates <- function(x) {
  missing <- setdiff(
    app_glofas_context_repair_required_candidate_columns(),
    names(x)
  )
  if (length(missing)) {
    stop(sprintf(
      "The context-repair registry is missing: %s.",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  x <- app_glofas_transition_validate_candidates(x)
  x$execution_stage <- as.character(x$execution_stage)
  x$warm_start_source_candidate <- as.character(
    x$warm_start_source_candidate
  )
  x$warm_start_compatibility_mode <- as.character(
    x$warm_start_compatibility_mode
  )
  x$warm_start_use_theta <- app_as_bool_vec(x$warm_start_use_theta)
  x$warm_start_use_future <- app_as_bool_vec(x$warm_start_use_future)
  x$warm_start_use_sigma <- app_as_bool_vec(x$warm_start_use_sigma)

  if (any(!x$execution_stage %in% c("stage0", "stage1"))) {
    stop("Context-repair execution stages must be stage0 or stage1.", call. = FALSE)
  }
  if (any(!x$warm_start_compatibility_mode %in%
      c("exact_design", "state_only"))) {
    stop("Context-repair warm starts must be exact_design or state_only.", call. = FALSE)
  }
  stage0 <- x$execution_stage == "stage0"
  if (!setequal(x$candidate_id[stage0], c("t01_last", "t10_last_gctx"))) {
    stop("Stage 0 must contain exactly T01 and T10.", call. = FALSE)
  }
  if (any(x$warm_start_compatibility_mode[stage0] != "exact_design") ||
      any(!x$warm_start_use_theta[stage0])) {
    stop("Stage-0 continuation requires exact-design theta transfer.", call. = FALSE)
  }
  stage1 <- !stage0
  if (any(x$warm_start_compatibility_mode[stage1] != "state_only") ||
      any(x$warm_start_use_theta[stage1])) {
    stop("Stage-1 ablations require state-only transfer without theta.", call. = FALSE)
  }
  if (any(!x$warm_start_use_future) || any(!x$warm_start_use_sigma)) {
    stop("Every repair candidate must transfer future and source-scale state.", call. = FALSE)
  }
  if (any(x$anchor_method != "last")) {
    stop("The repair campaign freezes the last-observation discrepancy anchor.", call. = FALSE)
  }
  if (any(x$anomaly_window != 50L) || any(x$context_lags != "0")) {
    stop("The repair campaign freezes anomaly window 50 and context lag zero.", call. = FALSE)
  }

  expected <- expand.grid(
    variables = c("level", "anomaly", "level_anomaly"),
    placement = c("readout", "reservoir", "both"),
    stringsAsFactors = FALSE
  )
  stage1_key <- paste(
    ifelse(
      x$glofas_level[stage1] & x$glofas_anomaly[stage1],
      "level_anomaly",
      ifelse(x$glofas_level[stage1], "level", "anomaly")
    ),
    ifelse(
      x$context_in_reservoir[stage1] & x$context_in_readout[stage1],
      "both",
      ifelse(x$context_in_reservoir[stage1], "reservoir", "readout")
    ),
    sep = "__"
  )
  t10_key <- "level_anomaly__both"
  expected_key <- paste(expected$variables, expected$placement, sep = "__")
  if (anyDuplicated(stage1_key) ||
      !setequal(c(stage1_key, t10_key), expected_key)) {
    stop(
      "Stage 1 plus T10 must form the complete 3-by-3 context factorial.",
      call. = FALSE
    )
  }
  x[order(x$priority), , drop = FALSE]
}

app_glofas_context_repair_source_inventory <- function(
  source_root,
  expected_manifest_sha256,
  source_candidates = c("t01_last", "t10_last_gctx"),
  cutoff_ids = c("nov12_2021", "dec21_2021", "may11_2022")
) {
  source_root <- normalizePath(source_root, mustWork = TRUE)
  manifest_path <- file.path(source_root, "runtime_manifest.csv")
  if (!file.exists(manifest_path)) {
    stop("The frozen transition source manifest is missing.", call. = FALSE)
  }
  observed_hash <- app_sha256_file(manifest_path)
  if (!identical(observed_hash, as.character(expected_manifest_sha256))) {
    stop("The frozen transition source manifest hash changed.", call. = FALSE)
  }
  manifest <- app_read_csv(manifest_path)
  rows <- list()
  for (candidate_id in source_candidates) {
    for (cutoff_id in cutoff_ids) {
      source <- manifest[
        manifest$base_candidate_id == candidate_id &
          manifest$cutoff_id == cutoff_id,
        ,
        drop = FALSE
      ]
      if (nrow(source) != 1L) {
        stop(sprintf(
          "Could not identify one frozen source for %s at %s.",
          candidate_id, cutoff_id
        ), call. = FALSE)
      }
      grid <- app_read_csv(source$model_grid_path[[1L]])
      qrow <- grid[grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
      if (nrow(qrow) != 1L) {
        stop("A frozen source model grid has a nonunique Q-DESN row.", call. = FALSE)
      }
      fit_path <- file.path(
        source$run_dir[[1L]], "objects", paste0(qrow$fit_id[[1L]], ".rds")
      )
      if (!file.exists(fit_path)) {
        stop(sprintf("Retained source fit is missing: %s.", fit_path), call. = FALSE)
      }
      fit <- readRDS(fit_path)
      contract <- fit$warm_start_contract %||% NULL
      required <- c(
        "design_hash", "quantile_level", "n_theta", "theta_names_hash",
        "n_future", "future_key_hash"
      )
      if (is.null(contract) || length(setdiff(required, names(contract)))) {
        stop(sprintf("Source fit lacks a complete warm contract: %s.", fit_path), call. = FALSE)
      }
      rows[[length(rows) + 1L]] <- data.frame(
        source_candidate_id = candidate_id,
        cutoff_id = cutoff_id,
        source_runtime_candidate_id = source$candidate_id[[1L]],
        source_fit_object = normalizePath(fit_path, mustWork = TRUE),
        source_fit_sha256 = app_sha256_file(fit_path),
        source_design_hash = as.character(contract$design_hash),
        source_theta_names_hash = as.character(contract$theta_names_hash),
        source_future_key_hash = as.character(contract$future_key_hash),
        source_n_theta = as.integer(contract$n_theta),
        source_n_future = as.integer(contract$n_future),
        source_vb_converged = app_as_bool(fit$vb_diagnostics$converged %||% FALSE),
        source_vb_iterations = as.integer(fit$vb_diagnostics$iterations %||% NA_integer_),
        stringsAsFactors = FALSE
      )
      rm(fit)
      gc(FALSE)
    }
  }
  app_bind_rows_fill(rows)
}

app_glofas_context_repair_warm_start_config <- function(candidate, source) {
  if (!is.data.frame(candidate) || nrow(candidate) != 1L ||
      !is.data.frame(source) || nrow(source) != 1L) {
    stop("Warm-start materialization requires one candidate and source.", call. = FALSE)
  }
  list(
    enabled = TRUE,
    fit_object = source$source_fit_object[[1L]],
    use_theta = isTRUE(candidate$warm_start_use_theta[[1L]]),
    use_future = isTRUE(candidate$warm_start_use_future[[1L]]),
    use_sigma = isTRUE(candidate$warm_start_use_sigma[[1L]]),
    require_theta = isTRUE(candidate$warm_start_use_theta[[1L]]),
    require_future = TRUE,
    require_sigma = TRUE,
    require_contract = TRUE,
    compatibility_mode = candidate$warm_start_compatibility_mode[[1L]]
  )
}

app_glofas_context_repair_trace_summary <- function(fit) {
  diagnostics <- fit$vb_diagnostics %||% list()
  objective <- as.numeric(diagnostics$elbo_trace %||% numeric())
  objective <- objective[is.finite(objective)]
  parameter <- as.numeric(diagnostics$parameter_change_trace %||% numeric())
  parameter <- parameter[is.finite(parameter)]
  tail_objective <- utils::tail(objective, min(10L, length(objective)))
  relative_range <- if (length(tail_objective)) {
    diff(range(tail_objective)) / max(abs(utils::tail(tail_objective, 1L)), 1)
  } else {
    Inf
  }
  max_parameter_change <- if (length(parameter)) utils::tail(parameter, 1L) else Inf
  converged <- app_as_bool(diagnostics$converged %||% FALSE)
  stable_at_cap <- !converged && is.finite(relative_range) &&
    relative_range <= 5.0e-4 && is.finite(max_parameter_change) &&
    max_parameter_change <= 5.0e-4
  data.frame(
    vb_converged = converged,
    vb_iterations = as.integer(diagnostics$iterations %||% NA_integer_),
    vb_elbo_final = if (length(objective)) utils::tail(objective, 1L) else NA_real_,
    vb_elbo_tail_relative_range = relative_range,
    vb_final_parameter_change = max_parameter_change,
    vb_stable_at_cap = stable_at_cap,
    vb_numerical_gate = converged || stable_at_cap,
    stringsAsFactors = FALSE
  )
}

app_glofas_context_repair_stage0_gate_decision <- function(audit, policy) {
  required_columns <- c(
    "base_candidate_id", "passes_warm_contract", "passes_finiteness",
    "vb_numerical_gate", "passes_stage0_gate"
  )
  missing <- setdiff(required_columns, names(audit))
  if (length(missing)) {
    stop(sprintf(
      "The Stage-0 audit is missing: %s.", paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  required_ids <- as.character(unlist(policy$required_anchor_candidates))
  advisory_ids <- as.character(unlist(policy$advisory_comparator_candidates))
  if (!length(required_ids) || !length(advisory_ids) ||
      any(!nzchar(c(required_ids, advisory_ids))) ||
      anyDuplicated(c(required_ids, advisory_ids))) {
    stop(
      "Stage-0 policy requires disjoint, nonempty anchor and advisory IDs.",
      call. = FALSE
    )
  }
  observed_ids <- unique(as.character(audit$base_candidate_id))
  if (!setequal(observed_ids, c(required_ids, advisory_ids))) {
    stop("Stage-0 policy candidates do not match the audit.", call. = FALSE)
  }
  required_idx <- audit$base_candidate_id %in% required_ids
  advisory_idx <- audit$base_candidate_id %in% advisory_ids
  expected_required <- as.integer(policy$expected_required_fits)
  expected_advisory <- as.integer(policy$expected_advisory_fits)
  minimum_advisory <- as.integer(policy$minimum_advisory_numerical_passes)
  if (sum(required_idx) != expected_required ||
      sum(advisory_idx) != expected_advisory) {
    stop("Stage-0 required/advisory cardinality changed.", call. = FALSE)
  }
  if (!is.finite(minimum_advisory) || minimum_advisory < 0L ||
      minimum_advisory > expected_advisory) {
    stop("Stage-0 minimum advisory passes are invalid.", call. = FALSE)
  }

  audit$gate_role <- ifelse(required_idx, "required_anchor", "advisory_comparator")
  audit$required_for_stage1 <- required_idx
  audit$passes_semantic_gate <- audit$passes_warm_contract & audit$passes_finiteness
  required_authorized <- all(audit$passes_stage0_gate[required_idx])
  all_semantic_authorized <- all(audit$passes_semantic_gate)
  advisory_passes <- sum(audit$passes_stage0_gate[advisory_idx])
  advisory_minimum_met <- advisory_passes >= minimum_advisory
  stage1_authorized <- required_authorized && all_semantic_authorized &&
    advisory_minimum_met

  summary <- data.frame(
    stage0_fits = nrow(audit),
    stage0_passed = sum(audit$passes_stage0_gate),
    stage0_failed = sum(!audit$passes_stage0_gate),
    required_fits = sum(required_idx),
    required_passed = sum(audit$passes_stage0_gate[required_idx]),
    required_failed = sum(!audit$passes_stage0_gate[required_idx]),
    advisory_fits = sum(advisory_idx),
    advisory_passed = advisory_passes,
    advisory_failed = sum(!audit$passes_stage0_gate[advisory_idx]),
    minimum_advisory_numerical_passes = minimum_advisory,
    required_anchor_authorized = required_authorized,
    all_semantic_contracts_pass = all_semantic_authorized,
    advisory_minimum_met = advisory_minimum_met,
    stage1_authorized = stage1_authorized,
    authorization_basis = "stable_required_anchor_with_advisory_comparator",
    stringsAsFactors = FALSE
  )
  list(audit = audit, summary = summary)
}

app_glofas_context_repair_validate_stage1_dependency <- function(manifest, policy) {
  required_columns <- c(
    "candidate_id", "warm_start_source_candidate",
    "warm_start_compatibility_mode", "warm_start_use_theta",
    "warm_start_use_future", "warm_start_use_sigma"
  )
  missing <- setdiff(required_columns, names(manifest))
  if (length(missing)) {
    stop(sprintf(
      "The Stage-1 manifest is missing: %s.", paste(missing, collapse = ", ")
    ), call. = FALSE)
  }
  allowed_sources <- as.character(unlist(policy$stage1_warm_source_candidates))
  if (!length(allowed_sources) || any(!nzchar(allowed_sources))) {
    stop("Stage-1 policy lacks warm-source candidates.", call. = FALSE)
  }
  theta <- app_as_bool_vec(manifest$warm_start_use_theta)
  future <- app_as_bool_vec(manifest$warm_start_use_future)
  sigma <- app_as_bool_vec(manifest$warm_start_use_sigma)
  checks <- data.frame(
    candidate_id = as.character(manifest$candidate_id),
    source_candidate = as.character(manifest$warm_start_source_candidate),
    source_is_allowed = manifest$warm_start_source_candidate %in% allowed_sources,
    state_only_compatibility = manifest$warm_start_compatibility_mode == "state_only",
    theta_transfer_disabled = !theta,
    future_transfer_enabled = future,
    sigma_transfer_enabled = sigma,
    stringsAsFactors = FALSE
  )
  checks$dependency_contract_pass <- with(checks,
    source_is_allowed & state_only_compatibility & theta_transfer_disabled &
      future_transfer_enabled & sigma_transfer_enabled
  )
  if (!all(checks$dependency_contract_pass)) {
    stop("Stage-1 warm-start dependency contract failed.", call. = FALSE)
  }
  checks
}

app_glofas_context_repair_context_audit <- function(
  design,
  fit,
  candidate_id,
  cutoff_id
) {
  contract <- design$discrepancy_transition_contract %||% list()
  variables <- app_glofas_discrepancy_context_variables(contract)
  timeline <- (design$feature_meta_alpha %||% list())$covariate_timeline %||%
    data.frame()
  origin_date <- as.Date((design$latent_data %||% list())$origin_date %||% NA)
  context_rows <- list()
  if (!length(variables)) {
    context_rows[[1L]] <- data.frame(
      candidate_id = candidate_id,
      cutoff_id = cutoff_id,
      variable = "none",
      context_enabled = FALSE,
      stringsAsFactors = FALSE
    )
  } else {
    for (variable in variables) {
      scaled_name <- paste0(variable, "_scaled")
      if (!all(c("date", variable, scaled_name) %in% names(timeline))) {
        stop(sprintf("Context timeline lacks '%s'.", variable), call. = FALSE)
      }
      raw <- as.numeric(timeline[[variable]])
      scaled <- as.numeric(timeline[[scaled_name]])
      historical <- as.Date(timeline$date) <= origin_date
      future <- as.Date(timeline$date) > origin_date
      hraw <- raw[historical & is.finite(raw)]
      fraw <- raw[future & is.finite(raw)]
      fscaled <- scaled[future & is.finite(scaled)]
      params <- (attr(timeline, "scale_params") %||% list())[[variable]] %||%
        list(center = NA_real_, scale = NA_real_)
      context_rows[[length(context_rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        cutoff_id = cutoff_id,
        variable = variable,
        context_enabled = TRUE,
        scale_center = as.numeric(params$center),
        scale_sd = as.numeric(params$scale),
        history_min = min(hraw),
        history_max = max(hraw),
        history_q05 = as.numeric(stats::quantile(hraw, 0.05, names = FALSE)),
        history_q50 = as.numeric(stats::quantile(hraw, 0.50, names = FALSE)),
        history_q95 = as.numeric(stats::quantile(hraw, 0.95, names = FALSE)),
        future_min = min(fraw),
        future_max = max(fraw),
        future_max_abs_scaled = max(abs(fscaled)),
        future_outside_history_fraction = mean(
          fraw < min(hraw) | fraw > max(hraw)
        ),
        all_finite = all(is.finite(c(raw, scaled))),
        uses_realized_future = any(
          app_as_bool_vec(timeline[[paste0(variable, "_uses_realized_future")]] %||%
            FALSE)
        ),
        stringsAsFactors = FALSE
      )
    }
  }

  feature_info <- design$feature_info_alpha %||% data.frame()
  direct <- feature_info[
    feature_info$block == "direct_covariate_lag" &
      as.character(feature_info$variable) %in% variables,
    ,
    drop = FALSE
  ]
  coefficient_rows <- list()
  if (nrow(direct)) {
    theta_names <- fit$warm_start_contract$theta_names %||%
      names(fit$variational_state$theta_mean)
    theta_mean <- as.numeric(fit$variational_state$theta_mean)
    theta_sd <- sqrt(pmax(diag(as.matrix(fit$variational_state$theta_cov)), 0))
    names(theta_mean) <- theta_names
    names(theta_sd) <- theta_names
    for (i in seq_len(nrow(direct))) {
      theta_name <- paste0("alpha__", direct$column_name[[i]])
      coefficient_rows[[length(coefficient_rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        cutoff_id = cutoff_id,
        variable = as.character(direct$variable[[i]]),
        lag = as.integer(direct$lag[[i]]),
        theta_name = theta_name,
        posterior_mean = unname(theta_mean[[theta_name]] %||% NA_real_),
        posterior_sd = unname(theta_sd[[theta_name]] %||% NA_real_),
        stringsAsFactors = FALSE
      )
    }
  }

  reservoir_idx <- which(feature_info$block == "reservoir_state")
  states <- if (length(reservoir_idx)) {
    as.matrix(design$X_alpha[, reservoir_idx, drop = FALSE])
  } else {
    matrix(numeric(), nrow = 0L, ncol = 0L)
  }
  state_row <- data.frame(
    candidate_id = candidate_id,
    cutoff_id = cutoff_id,
    n_state_rows = nrow(states),
    n_state_columns = ncol(states),
    finite_state_fraction = if (length(states)) mean(is.finite(states)) else NA_real_,
    saturated_state_fraction = if (length(states)) mean(abs(states) >= 0.99) else NA_real_,
    dead_state_fraction = if (ncol(states)) {
      mean(apply(states, 2L, stats::sd, na.rm = TRUE) <= 1.0e-8)
    } else {
      NA_real_
    },
    stringsAsFactors = FALSE
  )
  if (ncol(states) && nrow(states)) {
    row_idx <- unique(round(seq(1, nrow(states), length.out = min(2000L, nrow(states)))))
    sample_states <- states[row_idx, , drop = FALSE]
    sample_states <- scale(sample_states, center = TRUE, scale = FALSE)
    singular <- svd(sample_states, nu = 0L, nv = 0L)$d
    energy <- singular^2
    probability <- energy / sum(energy)
    probability <- probability[is.finite(probability) & probability > 0]
    state_row$state_effective_rank <- exp(-sum(probability * log(probability)))
    live <- singular[singular > max(singular) * 1.0e-10]
    state_row$state_condition_number <- if (length(live)) max(live) / min(live) else Inf
    column_idx <- seq_len(min(120L, ncol(sample_states)))
    correlations <- stats::cor(sample_states[, column_idx, drop = FALSE])
    upper <- abs(correlations[upper.tri(correlations)])
    state_row$near_duplicate_state_fraction <- mean(upper >= 0.999, na.rm = TRUE)
  } else {
    state_row$state_effective_rank <- NA_real_
    state_row$state_condition_number <- NA_real_
    state_row$near_duplicate_state_fraction <- NA_real_
  }
  list(
    context = app_bind_rows_fill(context_rows),
    coefficients = app_bind_rows_fill(coefficient_rows),
    states = state_row
  )
}

app_glofas_context_repair_bias_gate <- function(candidate_bias, comparator_bias, tolerance = 0.02) {
  is.finite(candidate_bias) && is.finite(comparator_bias) &&
    abs(candidate_bias) <= abs(comparator_bias) + as.numeric(tolerance)
}
