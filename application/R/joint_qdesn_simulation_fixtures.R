# Long-series fixture layer for the new joint QDESN simulation study.

app_joint_qdesn_default_simulation_registry_path <- function() {
  app_path("application/config/joint_qdesn_simulation_dgp_registry_20260706.csv")
}

app_joint_qdesn_default_simulation_fixture_dir <- function() {
  app_path("application/cache/joint_qdesn_simulation_dgp_fixtures_20260706")
}

app_joint_qdesn_simulation_registry_columns <- function() {
  c(
    "registry_version", "enabled", "scenario_id", "scenario_class",
    "distribution_family", "dynamics_class", "tau_grid", "simulated_length",
    "dgp_warmup_length", "effective_length", "analysis_window_length",
    "washout_length", "desn_washout_length", "train_length", "fit_length",
    "test_length", "validation_length", "forecast_origin_stride", "max_lead",
    "seed", "seed_role", "truth_quantile_method", "df", "al_tau",
    "mixture_weight", "mixture_mean_1", "mixture_sd_1", "mixture_mean_2",
    "mixture_sd_2", "period", "initial_y", "location_intercept",
    "scale_intercept", "beta_location", "beta_scale", "regime_start_fraction",
    "regime_location_shift", "regime_scale_shift", "nonlinear_strength",
    "notes"
  )
}

app_joint_qdesn_validate_simulation_registry <- function(registry) {
  app_check_required_columns(
    registry,
    app_joint_qdesn_simulation_registry_columns(),
    "joint QDESN simulation DGP registry"
  )
  if (!nrow(registry)) stop("Joint QDESN simulation registry must contain at least one row.", call. = FALSE)
  if (any(!nzchar(as.character(registry$scenario_id))) || anyDuplicated(as.character(registry$scenario_id))) {
    stop("Joint QDESN simulation registry scenario_id values must be nonempty and unique.", call. = FALSE)
  }
  app_joint_qvp_validate_synthetic_dgp_registry(registry)
  for (ii in seq_len(nrow(registry))) {
    sc <- registry[ii, , drop = FALSE]
    scenario_id <- as.character(sc$scenario_id[[1L]])
    simulated_length <- as.integer(sc$simulated_length[[1L]])
    dgp_warmup_length <- as.integer(sc$dgp_warmup_length[[1L]])
    effective_length <- as.integer(sc$effective_length[[1L]])
    analysis_window_length <- as.integer(sc$analysis_window_length[[1L]])
    washout_length <- as.integer(sc$washout_length[[1L]])
    desn_washout_length <- as.integer(sc$desn_washout_length[[1L]])
    train_length <- as.integer(sc$train_length[[1L]])
    fit_length <- as.integer(sc$fit_length[[1L]])
    test_length <- as.integer(sc$test_length[[1L]])
    validation_length <- as.integer(sc$validation_length[[1L]])
    forecast_origin_stride <- as.integer(sc$forecast_origin_stride[[1L]])
    max_lead <- as.integer(sc$max_lead[[1L]])
    vals <- c(
      simulated_length, dgp_warmup_length, effective_length, analysis_window_length,
      washout_length, desn_washout_length, train_length, fit_length, test_length,
      validation_length, forecast_origin_stride, max_lead
    )
    if (any(is.na(vals)) || any(vals <= 0L)) {
      stop(sprintf("Scenario '%s' has nonpositive or missing geometry fields.", scenario_id), call. = FALSE)
    }
    if (simulated_length != dgp_warmup_length + effective_length) {
      stop(sprintf("Scenario '%s' simulated_length must equal dgp_warmup_length + effective_length.", scenario_id), call. = FALSE)
    }
    if (analysis_window_length != desn_washout_length + fit_length + validation_length) {
      stop(sprintf("Scenario '%s' analysis_window_length must equal DESN washout + fit + validation.", scenario_id), call. = FALSE)
    }
    if (analysis_window_length > effective_length) {
      stop(sprintf("Scenario '%s' analysis_window_length cannot exceed effective_length.", scenario_id), call. = FALSE)
    }
    expected_washout <- dgp_warmup_length + (effective_length - analysis_window_length) + desn_washout_length
    if (washout_length != expected_washout) {
      stop(sprintf("Scenario '%s' washout_length must align with the last-analysis-window geometry.", scenario_id), call. = FALSE)
    }
    if (train_length != fit_length || test_length != validation_length) {
      stop(sprintf("Scenario '%s' train/test lengths must match fit/validation lengths.", scenario_id), call. = FALSE)
    }
    if (validation_length < max_lead) {
      stop(sprintf("Scenario '%s' validation_length must be at least max_lead.", scenario_id), call. = FALSE)
    }
    if (forecast_origin_stride > validation_length) {
      stop(sprintf("Scenario '%s' forecast_origin_stride cannot exceed validation_length.", scenario_id), call. = FALSE)
    }
    if (!nzchar(as.character(sc$seed_role[[1L]]))) {
      stop(sprintf("Scenario '%s' seed_role must be recorded.", scenario_id), call. = FALSE)
    }
  }
  invisible(registry)
}

app_joint_qdesn_load_simulation_registry <- function(
  path = app_joint_qdesn_default_simulation_registry_path(),
  enabled_only = TRUE
) {
  registry <- app_read_csv(path)
  app_joint_qdesn_validate_simulation_registry(registry)
  if (enabled_only) {
    registry <- registry[app_as_bool_vec(registry$enabled), , drop = FALSE]
    rownames(registry) <- NULL
  }
  registry
}

app_joint_qdesn_analysis_indices <- function(sc) {
  simulated_length <- as.integer(sc$simulated_length[[1L]])
  dgp_warmup_length <- as.integer(sc$dgp_warmup_length[[1L]])
  effective_length <- as.integer(sc$effective_length[[1L]])
  analysis_window_length <- as.integer(sc$analysis_window_length[[1L]])
  desn_washout_length <- as.integer(sc$desn_washout_length[[1L]])
  fit_length <- as.integer(sc$fit_length[[1L]])
  validation_length <- as.integer(sc$validation_length[[1L]])
  analysis_start_effective <- effective_length - analysis_window_length + 1L
  analysis_end_effective <- effective_length
  analysis_start_full <- dgp_warmup_length + analysis_start_effective
  analysis_end_full <- simulated_length
  desn_start_full <- analysis_start_full
  desn_end_full <- desn_start_full + desn_washout_length - 1L
  fit_start_full <- desn_end_full + 1L
  fit_end_full <- fit_start_full + fit_length - 1L
  validation_start_full <- fit_end_full + 1L
  validation_end_full <- validation_start_full + validation_length - 1L
  list(
    dgp_warmup_start_full = 1L,
    dgp_warmup_end_full = dgp_warmup_length,
    effective_start_full = dgp_warmup_length + 1L,
    effective_end_full = simulated_length,
    analysis_start_effective = analysis_start_effective,
    analysis_end_effective = analysis_end_effective,
    analysis_start_full = analysis_start_full,
    analysis_end_full = analysis_end_full,
    desn_washout_start_full = desn_start_full,
    desn_washout_end_full = desn_end_full,
    fit_start_full = fit_start_full,
    fit_end_full = fit_end_full,
    validation_start_full = validation_start_full,
    validation_end_full = validation_end_full,
    desn_washout_start_effective = analysis_start_effective,
    desn_washout_end_effective = analysis_start_effective + desn_washout_length - 1L,
    fit_start_effective = analysis_start_effective + desn_washout_length,
    fit_end_effective = analysis_start_effective + desn_washout_length + fit_length - 1L,
    validation_start_effective = analysis_start_effective + desn_washout_length + fit_length,
    validation_end_effective = effective_length
  )
}

app_joint_qdesn_detailed_split <- function(sc) {
  idx <- app_joint_qdesn_analysis_indices(sc)
  simulated_length <- as.integer(sc$simulated_length[[1L]])
  full_time_index <- seq_len(simulated_length)
  effective_index <- ifelse(full_time_index > idx$dgp_warmup_end_full, full_time_index - idx$dgp_warmup_end_full, NA_integer_)
  analysis_window_index <- ifelse(full_time_index >= idx$analysis_start_full, full_time_index - idx$analysis_start_full + 1L, NA_integer_)
  role <- rep("effective_pre_analysis", simulated_length)
  role[full_time_index <= idx$dgp_warmup_end_full] <- "dgp_warmup"
  role[full_time_index >= idx$desn_washout_start_full & full_time_index <= idx$desn_washout_end_full] <- "desn_washout"
  role[full_time_index >= idx$fit_start_full & full_time_index <= idx$fit_end_full] <- "fit"
  role[full_time_index >= idx$validation_start_full & full_time_index <= idx$validation_end_full] <- "validation"
  role_index <- ave(full_time_index, role, FUN = seq_along)
  retained_after_desn_index <- ifelse(
    role %in% c("fit", "validation"),
    full_time_index - idx$fit_start_full + 1L,
    NA_integer_
  )
  data.frame(
    full_time_index = full_time_index,
    effective_index = as.integer(effective_index),
    analysis_window_index = as.integer(analysis_window_index),
    role = role,
    role_index = as.integer(role_index),
    retained_after_desn_index = as.integer(retained_after_desn_index),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_fixture_from_registry_row <- function(sc) {
  app_joint_qdesn_validate_simulation_registry(sc)
  fixture <- app_joint_qvp_fixture_from_synthetic_dgp_registry_row(sc)
  fixture$detailed_split <- app_joint_qdesn_detailed_split(sc)
  fixture$analysis_indices <- app_joint_qdesn_analysis_indices(sc)
  fixture$dgp_warmup_length <- as.integer(sc$dgp_warmup_length[[1L]])
  fixture$effective_length <- as.integer(sc$effective_length[[1L]])
  fixture$analysis_window_length <- as.integer(sc$analysis_window_length[[1L]])
  fixture$desn_washout_length <- as.integer(sc$desn_washout_length[[1L]])
  fixture$fit_length <- as.integer(sc$fit_length[[1L]])
  fixture$validation_length <- as.integer(sc$validation_length[[1L]])
  fixture$forecast_origin_stride <- as.integer(sc$forecast_origin_stride[[1L]])
  fixture$max_lead <- as.integer(sc$max_lead[[1L]])
  fixture$seed_role <- as.character(sc$seed_role[[1L]])
  fixture
}

app_joint_qdesn_observed_rows <- function(fixture) {
  data.frame(
    scenario_id = fixture$scenario_id,
    fixture$detailed_split,
    y = fixture$y,
    mu = fixture$mu,
    sigma = fixture$sigma,
    innovation = fixture$innovation,
    innovation_raw = fixture$innovation_raw,
    distribution_family = fixture$distribution_family,
    dynamics_class = fixture$dynamics_class,
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_design_rows <- function(fixture) {
  data.frame(
    scenario_id = fixture$scenario_id,
    fixture$detailed_split,
    fixture$Z,
    check.names = FALSE
  )
}

app_joint_qdesn_true_quantile_wide_rows <- function(fixture) {
  data.frame(
    scenario_id = fixture$scenario_id,
    fixture$detailed_split,
    fixture$true_q,
    check.names = FALSE
  )
}

app_joint_qdesn_true_quantile_long_rows <- function(fixture) {
  app_joint_qdesn_bind_rows(lapply(seq_along(fixture$tau), function(k) {
    data.frame(
      scenario_id = fixture$scenario_id,
      fixture$detailed_split,
      quantile_index = k,
      tau = fixture$tau[[k]],
      true_quantile = fixture$true_q[, k],
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_qdesn_split_metadata_row <- function(fixture) {
  idx <- fixture$analysis_indices
  data.frame(
    scenario_id = fixture$scenario_id,
    simulated_length = fixture$simulated_length,
    dgp_warmup_length = fixture$dgp_warmup_length,
    effective_length = fixture$effective_length,
    analysis_window_length = fixture$analysis_window_length,
    desn_washout_length = fixture$desn_washout_length,
    fit_length = fixture$fit_length,
    validation_length = fixture$validation_length,
    dgp_warmup_full_start = idx$dgp_warmup_start_full,
    dgp_warmup_full_end = idx$dgp_warmup_end_full,
    effective_full_start = idx$effective_start_full,
    effective_full_end = idx$effective_end_full,
    analysis_full_start = idx$analysis_start_full,
    analysis_full_end = idx$analysis_end_full,
    analysis_effective_start = idx$analysis_start_effective,
    analysis_effective_end = idx$analysis_end_effective,
    desn_washout_full_start = idx$desn_washout_start_full,
    desn_washout_full_end = idx$desn_washout_end_full,
    fit_full_start = idx$fit_start_full,
    fit_full_end = idx$fit_end_full,
    validation_full_start = idx$validation_start_full,
    validation_full_end = idx$validation_end_full,
    desn_washout_effective_start = idx$desn_washout_start_effective,
    desn_washout_effective_end = idx$desn_washout_end_effective,
    fit_effective_start = idx$fit_start_effective,
    fit_effective_end = idx$fit_end_effective,
    validation_effective_start = idx$validation_start_effective,
    validation_effective_end = idx$validation_end_effective,
    split_strategy = "last_2000_effective_rows_with_desn_washout_fit_validation",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_dgp_parameter_rows <- function(fixture, sc) {
  base <- app_joint_qvp_registry_dgp_parameter_rows(fixture, sc)
  extra <- data.frame(
    scenario_id = fixture$scenario_id,
    block = "joint_qdesn_geometry",
    name = c(
      "dgp_warmup_length", "effective_length", "analysis_window_length",
      "desn_washout_length", "fit_length", "validation_length",
      "forecast_origin_stride", "max_lead", "seed_role"
    ),
    value = as.character(c(
      fixture$dgp_warmup_length, fixture$effective_length, fixture$analysis_window_length,
      fixture$desn_washout_length, fixture$fit_length, fixture$validation_length,
      fixture$forecast_origin_stride, fixture$max_lead, fixture$seed_role
    )),
    stringsAsFactors = FALSE
  )
  rbind(base, extra)
}

app_joint_qdesn_scenario_summary_row <- function(fixture) {
  roles <- fixture$detailed_split$role
  analysis <- roles %in% c("desn_washout", "fit", "validation")
  fit <- roles == "fit"
  validation <- roles == "validation"
  data.frame(
    scenario_id = fixture$scenario_id,
    scenario_class = fixture$scenario_class,
    distribution_family = fixture$distribution_family,
    dynamics_class = fixture$dynamics_class,
    truth_quantile_method = fixture$truth_quantile_method,
    seed = fixture$seed,
    seed_role = fixture$seed_role,
    simulated_length = fixture$simulated_length,
    dgp_warmup_length = fixture$dgp_warmup_length,
    effective_length = fixture$effective_length,
    analysis_window_length = fixture$analysis_window_length,
    desn_washout_length = fixture$desn_washout_length,
    fit_length = fixture$fit_length,
    validation_length = fixture$validation_length,
    forecast_origin_stride = fixture$forecast_origin_stride,
    max_lead = fixture$max_lead,
    p = ncol(fixture$Z),
    K = length(fixture$tau),
    tau_grid = app_joint_qdesn_format_tau(fixture$tau),
    sigma_min = min(fixture$sigma),
    sigma_max = max(fixture$sigma),
    analysis_y_mean = mean(fixture$y[analysis]),
    analysis_y_sd = stats::sd(fixture$y[analysis]),
    fit_y_mean = mean(fixture$y[fit]),
    validation_y_mean = mean(fixture$y[validation]),
    total_true_crossing_pairs = sum(fixture$crossing_diagnostics$n_crossing_pairs),
    max_quantile_width = max(fixture$true_q[, ncol(fixture$true_q)] - fixture$true_q[, 1L]),
    notes = fixture$notes,
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_forecast_origin_plan_rows <- function(fixture) {
  idx <- fixture$analysis_indices
  offsets <- seq.int(0L, fixture$validation_length - fixture$max_lead, by = fixture$forecast_origin_stride)
  if (!length(offsets)) return(data.frame())
  data.frame(
    scenario_id = fixture$scenario_id,
    origin_index = seq_along(offsets),
    origin_full_time_index = idx$fit_end_full + offsets,
    origin_effective_index = idx$fit_end_effective + offsets,
    target_start_full_time_index = idx$fit_end_full + offsets + 1L,
    target_end_full_time_index = idx$fit_end_full + offsets + fixture$max_lead,
    target_start_effective_index = idx$fit_end_effective + offsets + 1L,
    target_end_effective_index = idx$fit_end_effective + offsets + fixture$max_lead,
    lead_start = 1L,
    lead_end = fixture$max_lead,
    n_leads = fixture$max_lead,
    fit_window_start_full_time_index = idx$fit_start_full,
    fit_window_end_full_time_index = idx$fit_end_full,
    fit_window_start_effective_index = idx$fit_start_effective,
    fit_window_end_effective_index = idx$fit_end_effective,
    origin_stride = fixture$forecast_origin_stride,
    refit_within_block = FALSE,
    coefficient_refit_policy = "single_fit_no_refit_across_validation_blocks",
    no_future_validation_leakage = TRUE,
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_oracle_policy_rows <- function(registry) {
  data.frame(
    scenario_id = registry$scenario_id,
    distribution_family = registry$distribution_family,
    truth_quantile_method = registry$truth_quantile_method,
    oracle_materialization = "precomputed_in_fixture",
    recompute_inside_fit_or_forecast = FALSE,
    seed_role = registry$seed_role,
    status = "pass",
    note = ifelse(
      registry$truth_quantile_method == "numerical",
      "Numerical inversion is used once during fixture materialization and hashed.",
      "Analytic conditional quantiles are materialized once and hashed."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_fixture_validation_rows <- function(registry, fixtures) {
  rows <- list(data.frame(
    scope = "registry",
    scenario_id = "ALL",
    check = "schema_unique_ids_geometry_and_fields",
    status = "pass",
    detail = "registry schema and TT500-like geometry validation passed",
    stringsAsFactors = FALSE
  ))
  for (fixture in fixtures) {
    roles <- fixture$detailed_split$role
    split_counts <- table(factor(roles, levels = c("dgp_warmup", "effective_pre_analysis", "desn_washout", "fit", "validation")))
    expected_pre <- fixture$effective_length - fixture$analysis_window_length
    checks <- list(
      finite_observed = all(is.finite(fixture$y)),
      finite_design = all(is.finite(fixture$Z)),
      finite_true_quantiles = all(is.finite(fixture$true_q)),
      positive_scale = all(fixture$sigma > 0),
      monotone_true_quantiles = all(apply(fixture$true_q, 1L, function(x) all(diff(x) >= -1.0e-10))),
      zero_true_crossing_pairs = sum(fixture$crossing_diagnostics$n_crossing_pairs) == 0L,
      role_lengths = identical(
        as.integer(split_counts),
        c(fixture$dgp_warmup_length, expected_pre, fixture$desn_washout_length, fixture$fit_length, fixture$validation_length)
      ),
      forecast_origin_plan_nonempty = nrow(app_joint_qdesn_forecast_origin_plan_rows(fixture)) > 0L
    )
    for (nm in names(checks)) {
      rows[[length(rows) + 1L]] <- data.frame(
        scope = "scenario",
        scenario_id = fixture$scenario_id,
        check = nm,
        status = if (isTRUE(checks[[nm]])) "pass" else "fail",
        detail = if (isTRUE(checks[[nm]])) "check passed" else "check failed",
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

app_joint_qdesn_fixture_readme_lines <- function(registry, scenario_summary) {
  c(
    "# Joint QDESN Simulation DGP Fixtures",
    "",
    "This artifact directory materializes the long-series fixture layer for the new joint QDESN simulation study.",
    "It emulates the TT500 validation structure by using the last 2000 effective observations for DESN washout, fit, and validation.",
    "",
    "This is a fixture layer only. It does not fit JOINT QDESN RHS, JOINT exQDESN RHS, QDESN RHS, or exQDESN RHS.",
    "",
    sprintf("- Registry rows: %s", nrow(registry)),
    sprintf("- Bridge scenarios: %s", sum(registry$scenario_class == "bridge")),
    sprintf("- Stress scenarios: %s", sum(registry$scenario_class == "stress")),
    sprintf("- Total observed rows: %s", sum(scenario_summary$simulated_length)),
    sprintf("- Quantile grid: %s", scenario_summary$tau_grid[[1L]]),
    "- Full simulated length: 12000.",
    "- DGP warmup: 2000.",
    "- Effective series: 10000.",
    "- Last effective analysis window: 2000 = 500 DESN washout + 500 fit + 1000 validation.",
    "- Forecast-origin plan: origins every 30 observations, leads 1--30, no coefficient refit within the validation blocks.",
    "",
    "Primary files:",
    "",
    "- `frozen_registry.csv`: exact registry snapshot used for materialization.",
    "- `observed_series.csv`: response, location, scale, innovations, and detailed role labels.",
    "- `design_matrix.csv`: deterministic DGP feature matrix.",
    "- `true_quantile_wide.csv` and `true_quantile_long.csv`: materialized oracle conditional quantiles.",
    "- `split_metadata.csv`: full/effective/analysis-window indices.",
    "- `forecast_origin_plan.csv`: no-refit lead 1--30 scoring plan.",
    "- `oracle_policy.csv`: analytic/numerical oracle method declaration.",
    "- `fixture_validation.csv`: pass/fail checks.",
    "- `artifact_manifest.csv`: SHA-256 hashes for reproducibility."
  )
}

app_joint_qdesn_materialize_simulation_fixtures <- function(
  out_dir = app_joint_qdesn_default_simulation_fixture_dir(),
  registry_path = app_joint_qdesn_default_simulation_registry_path(),
  registry = NULL,
  scenario_ids = NULL
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  registry_source <- if (is.null(registry)) app_read_csv(registry_path) else registry
  app_joint_qdesn_validate_simulation_registry(registry_source)
  registry_source <- registry_source[app_as_bool_vec(registry_source$enabled), , drop = FALSE]
  if (!is.null(scenario_ids) && length(scenario_ids)) {
    missing <- setdiff(scenario_ids, registry_source$scenario_id)
    if (length(missing)) stop("Unknown scenario_ids: ", paste(missing, collapse = ", "), call. = FALSE)
    registry_source <- registry_source[match(scenario_ids, registry_source$scenario_id), , drop = FALSE]
  }
  rownames(registry_source) <- NULL
  fixtures <- lapply(seq_len(nrow(registry_source)), function(ii) {
    app_joint_qdesn_fixture_from_registry_row(registry_source[ii, , drop = FALSE])
  })

  run_config <- data.frame(
    run_id = "joint_qdesn_simulation_dgp_fixture_materialization",
    registry_path = app_prefer_repo_relative_path(registry_path),
    out_dir = normalizePath(out_dir, mustWork = FALSE),
    n_scenarios = nrow(registry_source),
    total_observed_rows = sum(vapply(fixtures, function(x) length(x$y), integer(1L))),
    fixture_layer_only = TRUE,
    model_fit_launched = FALSE,
    mcmc_launched = FALSE,
    stringsAsFactors = FALSE
  )
  observed <- app_joint_qdesn_bind_rows(lapply(fixtures, app_joint_qdesn_observed_rows))
  design <- app_joint_qdesn_bind_rows(lapply(fixtures, app_joint_qdesn_design_rows))
  true_wide <- app_joint_qdesn_bind_rows(lapply(fixtures, app_joint_qdesn_true_quantile_wide_rows))
  true_long <- app_joint_qdesn_bind_rows(lapply(fixtures, app_joint_qdesn_true_quantile_long_rows))
  split_metadata <- app_joint_qdesn_bind_rows(lapply(fixtures, app_joint_qdesn_split_metadata_row))
  dgp_parameters <- app_joint_qdesn_bind_rows(Map(app_joint_qdesn_dgp_parameter_rows, fixtures, split(registry_source, seq_len(nrow(registry_source)))))
  scenario_summary <- app_joint_qdesn_bind_rows(lapply(fixtures, app_joint_qdesn_scenario_summary_row))
  forecast_origin_plan <- app_joint_qdesn_bind_rows(lapply(fixtures, app_joint_qdesn_forecast_origin_plan_rows))
  oracle_policy <- app_joint_qdesn_oracle_policy_rows(registry_source)
  validation <- app_joint_qdesn_fixture_validation_rows(registry_source, fixtures)
  crossing_summary <- app_joint_qdesn_bind_rows(lapply(fixtures, function(fixture) {
    cbind(data.frame(scenario_id = fixture$scenario_id, stringsAsFactors = FALSE), fixture$crossing_diagnostics)
  }))
  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_fixture_readme_lines(registry_source, scenario_summary), readme_path, useBytes = TRUE)

  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    frozen_registry = app_joint_qvp_write_csv(registry_source, file.path(out_dir, "frozen_registry.csv")),
    scenario_summary = app_joint_qvp_write_csv(scenario_summary, file.path(out_dir, "scenario_summary.csv")),
    observed_series = app_joint_qvp_write_csv(observed, file.path(out_dir, "observed_series.csv")),
    design_matrix = app_joint_qvp_write_csv(design, file.path(out_dir, "design_matrix.csv")),
    true_quantile_wide = app_joint_qvp_write_csv(true_wide, file.path(out_dir, "true_quantile_wide.csv")),
    true_quantile_long = app_joint_qvp_write_csv(true_long, file.path(out_dir, "true_quantile_long.csv")),
    split_metadata = app_joint_qvp_write_csv(split_metadata, file.path(out_dir, "split_metadata.csv")),
    dgp_parameters = app_joint_qvp_write_csv(dgp_parameters, file.path(out_dir, "dgp_parameters.csv")),
    forecast_origin_plan = app_joint_qvp_write_csv(forecast_origin_plan, file.path(out_dir, "forecast_origin_plan.csv")),
    oracle_policy = app_joint_qvp_write_csv(oracle_policy, file.path(out_dir, "oracle_policy.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing_summary, file.path(out_dir, "crossing_summary.csv")),
    fixture_validation = app_joint_qvp_write_csv(validation, file.path(out_dir, "fixture_validation.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    registry = registry_source,
    fixtures = fixtures,
    run_config = run_config,
    scenario_summary = scenario_summary,
    split_metadata = split_metadata,
    forecast_origin_plan = forecast_origin_plan,
    fixture_validation = validation
  )
}
