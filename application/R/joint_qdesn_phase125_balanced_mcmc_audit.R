# Phase 125 balanced MCMC merge and article-readiness audit.
#
# Phase 122 confirmed the first set of case-specific MCMC rows.  Phase 124c
# confirmed the remaining rows needed for a balanced four-model-by-scenario
# comparison.  Phase 125 merges those frozen MCMC artifacts, verifies their
# manifests, checks the balanced grid, and writes compact article-candidate
# audit tables without copying the large source quantile grids.

app_joint_qdesn_default_phase125_balanced_mcmc_audit_dir <- function() {
  app_path("application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712")
}

app_joint_qdesn_phase125_default_mcmc_blocks <- function() {
  data.frame(
    source_block_id = c("phase122_existing_mcmc", "phase124c_missing_cell_mcmc"),
    source_role = c("existing_case_specific_mcmc_rows", "balanced_missing_cell_mcmc_rows"),
    source_dir = c(
      app_joint_qdesn_default_phase122_mcmc_case_confirmation_dir(),
      app_path("application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711")
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase125_expected_scenarios <- function() {
  c(
    "normal_bridge",
    "laplace_bridge",
    "gaussian_mixture_bridge",
    "student_t_location_scale",
    "asymmetric_laplace_tail",
    "persistent_heavy_tail",
    "regime_shift",
    "nonlinear_reservoir_friendly"
  )
}

app_joint_qdesn_phase125_expected_models <- function() {
  c(
    "joint_qdesn_rhs_vb",
    "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb",
    "exqdesn_rhs_independent_vb"
  )
}

app_joint_qdesn_phase125_write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

app_joint_qdesn_phase125_add_source <- function(x, source_block_id, source_dir) {
  n <- nrow(x)
  x$source_block_id <- rep(source_block_id, n)
  x$source_dir <- rep(source_dir, n)
  x
}

app_joint_qdesn_phase125_load_block <- function(source_block_id, source_dir) {
  source_dir <- normalizePath(source_dir, winslash = "/", mustWork = TRUE)
  src <- app_joint_qdesn_phase123_load_phase122(source_dir)
  add <- function(x) app_joint_qdesn_phase125_add_source(x, source_block_id, source_dir)
  src$source_block_id <- source_block_id
  src$source_dir <- source_dir
  src$manifest <- add(src$manifest)
  src$run_config <- add(src$run_config)
  src$phase121_manifest <- add(src$phase121_manifest)
  src$fixture_manifest <- add(src$fixture_manifest)
  src$controls <- add(src$controls)
  src$failures <- add(src$failures)
  src$summary <- add(src$summary)
  src$assessment <- add(src$assessment)
  src$forecast_truth <- add(src$forecast_truth)
  src$forecast_check <- add(src$forecast_check)
  src$forecast_crps <- add(src$forecast_crps)
  src$forecast_hit <- add(src$forecast_hit)
  src$forecast_interval <- add(src$forecast_interval)
  src$fit_truth <- add(src$fit_truth)
  src$fit_check <- add(src$fit_check)
  src$crossing <- add(src$crossing)
  src$raw_crossing <- add(src$raw_crossing)
  src$vb_convergence <- add(src$vb_convergence)
  src$objective <- add(src$objective)
  src$draws <- add(src$draws)
  src$vb_mcmc_distance <- add(src$vb_mcmc_distance)
  src$chain_distance <- add(src$chain_distance)
  src$runtime <- add(src$runtime)
  src$provenance <- add(src$provenance)
  src
}

app_joint_qdesn_phase125_load_blocks <- function(blocks) {
  app_check_required_columns(blocks, c("source_block_id", "source_dir"), "Phase125 MCMC source blocks")
  if (anyDuplicated(blocks$source_block_id)) {
    stop("Phase125 source_block_id values must be unique.", call. = FALSE)
  }
  lapply(seq_len(nrow(blocks)), function(ii) {
    app_joint_qdesn_phase125_load_block(blocks$source_block_id[[ii]], blocks$source_dir[[ii]])
  })
}

app_joint_qdesn_phase125_bind_source_field <- function(sources, field) {
  app_joint_qdesn_bind_rows(lapply(sources, `[[`, field))
}

app_joint_qdesn_phase125_combined_source <- function(sources) {
  list(
    manifest = app_joint_qdesn_phase125_bind_source_field(sources, "manifest"),
    run_config = app_joint_qdesn_phase125_bind_source_field(sources, "run_config"),
    phase121_manifest = app_joint_qdesn_phase125_bind_source_field(sources, "phase121_manifest"),
    fixture_manifest = app_joint_qdesn_phase125_bind_source_field(sources, "fixture_manifest"),
    controls = app_joint_qdesn_phase125_bind_source_field(sources, "controls"),
    failures = app_joint_qdesn_phase125_bind_source_field(sources, "failures"),
    summary = app_joint_qdesn_phase125_bind_source_field(sources, "summary"),
    assessment = app_joint_qdesn_phase125_bind_source_field(sources, "assessment"),
    forecast_truth = app_joint_qdesn_phase125_bind_source_field(sources, "forecast_truth"),
    forecast_check = app_joint_qdesn_phase125_bind_source_field(sources, "forecast_check"),
    forecast_crps = app_joint_qdesn_phase125_bind_source_field(sources, "forecast_crps"),
    forecast_hit = app_joint_qdesn_phase125_bind_source_field(sources, "forecast_hit"),
    forecast_interval = app_joint_qdesn_phase125_bind_source_field(sources, "forecast_interval"),
    fit_truth = app_joint_qdesn_phase125_bind_source_field(sources, "fit_truth"),
    fit_check = app_joint_qdesn_phase125_bind_source_field(sources, "fit_check"),
    crossing = app_joint_qdesn_phase125_bind_source_field(sources, "crossing"),
    raw_crossing = app_joint_qdesn_phase125_bind_source_field(sources, "raw_crossing"),
    vb_convergence = app_joint_qdesn_phase125_bind_source_field(sources, "vb_convergence"),
    objective = app_joint_qdesn_phase125_bind_source_field(sources, "objective"),
    draws = app_joint_qdesn_phase125_bind_source_field(sources, "draws"),
    vb_mcmc_distance = app_joint_qdesn_phase125_bind_source_field(sources, "vb_mcmc_distance"),
    chain_distance = app_joint_qdesn_phase125_bind_source_field(sources, "chain_distance"),
    runtime = app_joint_qdesn_phase125_bind_source_field(sources, "runtime"),
    provenance = app_joint_qdesn_phase125_bind_source_field(sources, "provenance")
  )
}

app_joint_qdesn_phase125_source_block_summary <- function(src) {
  rows <- lapply(split(src$summary, src$summary$source_block_id), function(block) {
    assessment <- src$assessment[src$assessment$source_block_id == block$source_block_id[[1L]], , drop = FALSE]
    data.frame(
      source_block_id = block$source_block_id[[1L]],
      source_dir = block$source_dir[[1L]],
      n_cases = nrow(block),
      n_pass = sum(assessment$gate_status == "pass", na.rm = TRUE),
      n_review = sum(assessment$gate_status == "review", na.rm = TRUE),
      n_fail = sum(assessment$gate_status == "fail", na.rm = TRUE),
      worker_failures = sum(src$failures$source_block_id == block$source_block_id[[1L]], na.rm = TRUE),
      contract_crossing_pairs = sum(assessment$contract_crossing_pairs, na.rm = TRUE),
      raw_crossing_pairs = sum(assessment$raw_crossing_pairs, na.rm = TRUE),
      mcmc_elapsed_hours = sum(block$mcmc_elapsed_seconds, na.rm = TRUE) / 3600,
      total_elapsed_hours = sum(block$total_elapsed_seconds, na.rm = TRUE) / 3600,
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase125_scope_audit <- function(
  src,
  expected_scenarios = app_joint_qdesn_phase125_expected_scenarios(),
  expected_models = app_joint_qdesn_phase125_expected_models()
) {
  s <- src$summary
  key <- paste(s$scenario_id, s$source_model_id, sep = "||")
  duplicate_key <- unique(key[duplicated(key)])
  grid <- expand.grid(
    scenario_id = expected_scenarios,
    source_model_id = expected_models,
    stringsAsFactors = FALSE
  )
  present_key <- paste(s$scenario_id, s$source_model_id, sep = "||")
  grid$present_in_balanced_mcmc <- paste(grid$scenario_id, grid$source_model_id, sep = "||") %in% present_key
  grid$n_matching_rows <- vapply(
    paste(grid$scenario_id, grid$source_model_id, sep = "||"),
    function(k) sum(present_key == k),
    integer(1L)
  )
  grid$scenario_label <- app_joint_qdesn_phase123_scenario_label(grid$scenario_id)
  model_labels <- setNames(
    c("Joint QDESN RHS", "Independent QDESN RHS", "Joint exQDESN RHS", "Independent exQDESN RHS"),
    expected_models
  )
  grid$model_label <- unname(model_labels[grid$source_model_id])
  grid <- grid[order(grid$scenario_id, app_joint_qdesn_phase123_model_order(grid$source_model_id)), , drop = FALSE]

  extra <- s[!paste(s$scenario_id, s$source_model_id, sep = "||") %in% paste(grid$scenario_id, grid$source_model_id, sep = "||"),
    c("case_id", "scenario_id", "source_model_id", "source_block_id"), drop = FALSE
  ]

  by_model <- lapply(expected_models, function(mid) {
    block <- grid[grid$source_model_id == mid, , drop = FALSE]
    data.frame(
      source_model_id = mid,
      model_label = unname(model_labels[mid]),
      n_scenarios_confirmed = sum(block$present_in_balanced_mcmc),
      n_scenarios_missing = sum(!block$present_in_balanced_mcmc),
      scenario_ids_missing = paste(block$scenario_id[!block$present_in_balanced_mcmc], collapse = ","),
      stringsAsFactors = FALSE
    )
  })
  by_model <- app_joint_qdesn_bind_rows(by_model)

  full_grid_complete <- all(grid$present_in_balanced_mcmc) && all(grid$n_matching_rows == 1L)
  no_extras <- nrow(extra) == 0L
  no_duplicates <- length(duplicate_key) == 0L
  decision <- data.frame(
    audit_item = c(
      "balanced_four_model_by_scenario_comparison",
      "unique_model_scenario_cells",
      "no_extra_model_scenario_cells",
      "recommended_article_use"
    ),
    status = c(
      ifelse(full_grid_complete, "pass", "fail"),
      ifelse(no_duplicates, "pass", "fail"),
      ifelse(no_extras, "pass", "review"),
      ifelse(full_grid_complete && no_duplicates, "review", "fail")
    ),
    detail = c(
      sprintf("%d/%d expected model-scenario cells are present exactly once.", sum(grid$present_in_balanced_mcmc & grid$n_matching_rows == 1L), nrow(grid)),
      if (no_duplicates) "No duplicated scenario-model cells." else paste("Duplicated keys:", paste(duplicate_key, collapse = ",")),
      if (no_extras) "No source rows outside the expected balanced grid." else sprintf("%d rows fall outside the expected grid.", nrow(extra)),
      if (full_grid_complete && no_duplicates) {
        "Use as the frozen balanced MCMC evidence packet after retaining review language for raw crossings and VB initialization diagnostics."
      } else {
        "Do not build article tables until missing/duplicated balanced cells are resolved."
      }
    ),
    stringsAsFactors = FALSE
  )
  list(
    matrix = grid,
    by_model = by_model,
    extra_rows = extra,
    duplicate_keys = data.frame(duplicate_key = duplicate_key, stringsAsFactors = FALSE),
    decision = decision,
    scope_status = if (full_grid_complete && no_duplicates && no_extras) {
      "pass"
    } else if (full_grid_complete && no_duplicates) {
      "review"
    } else {
      "fail"
    }
  )
}

app_joint_qdesn_phase125_raw_contract_summary <- function(src) {
  s <- src$summary
  cols <- c(
    "vb_fit_raw_crossing_pairs",
    "vb_forecast_raw_crossing_pairs",
    "mcmc_fit_raw_crossing_pairs",
    "mcmc_forecast_raw_crossing_pairs",
    "vb_fit_contract_crossing_pairs",
    "vb_forecast_contract_crossing_pairs",
    "mcmc_fit_contract_crossing_pairs",
    "mcmc_forecast_contract_crossing_pairs"
  )
  app_check_required_columns(s, c("source_model_id", cols), "Phase125 MCMC case summary crossing columns")
  aggregate(s[, cols], by = list(source_model_id = s$source_model_id), sum, na.rm = TRUE)
}

app_joint_qdesn_phase125_scenario_winners <- function(src) {
  s <- src$summary
  crps <- src$forecast_crps[grepl("_mcmc$", src$forecast_crps$model_id), , drop = FALSE]
  crps <- aggregate(crps_grid_mean ~ scenario_id + model_id, crps, mean, na.rm = TRUE)
  s <- merge(s, crps, by = c("scenario_id", "model_id"), all.x = TRUE)
  metrics <- c(
    "mcmc_fit_truth_mae",
    "mcmc_forecast_truth_mae",
    "mcmc_forecast_check_loss_mean",
    "crps_grid_mean"
  )
  rows <- lapply(metrics, function(metric) {
    app_joint_qdesn_bind_rows(lapply(split(s, s$scenario_id), function(block) {
      block <- block[order(block[[metric]], app_joint_qdesn_phase123_model_order(block$source_model_id)), , drop = FALSE]
      data.frame(
        scenario_id = block$scenario_id[[1L]],
        scenario_label = app_joint_qdesn_phase123_scenario_label(block$scenario_id[[1L]]),
        metric = metric,
        best_source_model_id = block$source_model_id[[1L]],
        best_model_label = app_joint_qdesn_phase123_label(block$display_label[[1L]]),
        best_value = block[[metric]][[1L]],
        second_source_model_id = if (nrow(block) >= 2L) block$source_model_id[[2L]] else NA_character_,
        second_model_label = if (nrow(block) >= 2L) app_joint_qdesn_phase123_label(block$display_label[[2L]]) else NA_character_,
        second_value = if (nrow(block) >= 2L) block[[metric]][[2L]] else NA_real_,
        best_margin = if (nrow(block) >= 2L) block[[metric]][[2L]] - block[[metric]][[1L]] else NA_real_,
        stringsAsFactors = FALSE
      )
    }))
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_phase125_gate_summary <- function(src, scope) {
  manifest_status <- if (nrow(src$manifest) && all(src$manifest$status == "pass")) "pass" else "fail"
  phase121_status <- if (nrow(src$phase121_manifest) && all(src$phase121_manifest$status == "pass")) "pass" else "fail"
  fixture_status <- if (nrow(src$fixture_manifest) && all(src$fixture_manifest$status == "pass")) "pass" else "fail"
  assessment <- src$assessment
  summary <- src$summary
  total_raw_crossings <- sum(assessment$raw_crossing_pairs, na.rm = TRUE)
  contract_crossings <- sum(assessment$contract_crossing_pairs, na.rm = TRUE)
  forecast_contract_crossings <- sum(summary$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE)
  scalar_claim <- if ("scalar_predictive_density_claim" %in% names(src$run_config)) {
    any(as.logical(src$run_config$scalar_predictive_density_claim), na.rm = TRUE)
  } else {
    NA
  }
  rows <- data.frame(
    gate = c(
      "source_artifact_manifests",
      "source_vb_freeze_manifests",
      "fixture_source_manifests",
      "worker_failures",
      "balanced_grid_complete",
      "duplicate_model_scenario_cells",
      "finite_mcmc_draws",
      "provided_vb_initialization",
      "contract_crossings",
      "raw_crossings",
      "chain_stability",
      "vb_mcmc_distance",
      "quantile_grid_predictive_contract",
      "article_asset_build_readiness"
    ),
    status = c(
      manifest_status,
      phase121_status,
      fixture_status,
      ifelse(nrow(src$failures) == 0L, "pass", "fail"),
      scope$decision$status[scope$decision$audit_item == "balanced_four_model_by_scenario_comparison"],
      scope$decision$status[scope$decision$audit_item == "unique_model_scenario_cells"],
      ifelse(all(summary$mcmc_draws_all_finite), "pass", "fail"),
      ifelse(all(summary$all_chain_init_source_provided), "pass", "fail"),
      ifelse(contract_crossings == 0 && forecast_contract_crossings == 0, "pass", "fail"),
      ifelse(total_raw_crossings == 0, "pass", "review"),
      app_joint_qdesn_phase123_gate(assessment$chain_status),
      app_joint_qdesn_phase123_gate(assessment$distance_status),
      ifelse(isFALSE(scalar_claim), "pass", "fail"),
      "review"
    ),
    detail = c(
      sprintf("%d/%d source artifact-manifest rows pass.", sum(src$manifest$status == "pass"), nrow(src$manifest)),
      sprintf("%d/%d source VB-freeze manifest rows pass.", sum(src$phase121_manifest$status == "pass"), nrow(src$phase121_manifest)),
      sprintf("%d/%d fixture manifest rows pass.", sum(src$fixture_manifest$status == "pass"), nrow(src$fixture_manifest)),
      sprintf("%d worker failure rows across source MCMC blocks.", nrow(src$failures)),
      scope$decision$detail[scope$decision$audit_item == "balanced_four_model_by_scenario_comparison"],
      scope$decision$detail[scope$decision$audit_item == "unique_model_scenario_cells"],
      sprintf("%d/%d cases report finite MCMC draws.", sum(summary$mcmc_draws_all_finite), nrow(summary)),
      sprintf("%d/%d cases report provided VB initialization.", sum(summary$all_chain_init_source_provided), nrow(summary)),
      sprintf("%d total contract crossing pairs; %d forecast contract crossing pairs.", contract_crossings, forecast_contract_crossings),
      sprintf("%d raw diagnostic crossing pairs before monotone contract.", total_raw_crossings),
      app_joint_qdesn_phase123_status_counts(assessment$chain_status),
      app_joint_qdesn_phase123_status_counts(assessment$distance_status),
      sprintf("scalar_predictive_density_claim=%s; validation remains quantile-grid/readout based.", as.character(scalar_claim)),
      "Balanced MCMC evidence is ready for article asset construction only with explicit review language for raw crossings and VB initialization diagnostics."
    ),
    stringsAsFactors = FALSE
  )
  rows
}

app_joint_qdesn_phase125_health_summary <- function(src, gate_summary, scope) {
  assessment <- src$assessment
  summary <- src$summary
  hard_gate_names <- c(
    "source_artifact_manifests", "source_vb_freeze_manifests", "fixture_source_manifests",
    "worker_failures", "balanced_grid_complete", "duplicate_model_scenario_cells",
    "finite_mcmc_draws", "provided_vb_initialization", "contract_crossings",
    "quantile_grid_predictive_contract"
  )
  hard_gate <- app_joint_qdesn_phase123_gate(gate_summary$status[gate_summary$gate %in% hard_gate_names])
  data.frame(
    component = c(
      "Source MCMC blocks",
      "Balanced grid",
      "Hard implementation gates",
      "Case gates",
      "Raw crossing diagnostics",
      "Predictive contract",
      "Article integration"
    ),
    status = c(
      "complete",
      scope$scope_status,
      hard_gate,
      app_joint_qdesn_phase123_gate(assessment$gate_status),
      ifelse(sum(assessment$raw_crossing_pairs, na.rm = TRUE) == 0, "pass", "review"),
      gate_summary$status[gate_summary$gate == "quantile_grid_predictive_contract"],
      ifelse(identical(hard_gate, "pass"), "ready_with_review_language", "blocked")
    ),
    progress = c(
      sprintf("%d source MCMC blocks merged.", length(unique(summary$source_block_id))),
      sprintf("%d/%d model-scenario cells present.", sum(scope$matrix$present_in_balanced_mcmc), nrow(scope$matrix)),
      sprintf("%d hard gates pass, %d fail.", sum(gate_summary$gate %in% hard_gate_names & gate_summary$status == "pass"), sum(gate_summary$gate %in% hard_gate_names & gate_summary$status == "fail")),
      sprintf("%d pass, %d review, %d fail cases.", sum(assessment$gate_status == "pass"), sum(assessment$gate_status == "review"), sum(assessment$gate_status == "fail")),
      sprintf("%d raw pairs; %d MCMC forecast raw pairs; %d contract pairs.", sum(assessment$raw_crossing_pairs, na.rm = TRUE), sum(summary$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE), sum(assessment$contract_crossing_pairs, na.rm = TRUE)),
      "Scores validate posterior quantile grids/readout paths, not a scalar predictive-density construction.",
      "No manuscript files are changed by Phase125."
    ),
    immediate_action = c(
      "Use Phase125 as the single source for final MCMC audit tables.",
      "Do not run more MCMC for missing cells.",
      "Fix implementation only if a hard gate fails.",
      "Keep review cases visible in article-supporting diagnostics.",
      "Report raw crossings as diagnostics and contract crossings as scored-grid behavior.",
      "Keep article claims scoped to quantile-grid validation.",
      "After review, rebuild article validation assets from Phase125 and compile."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase125_model_table <- function(model_summary) {
  data.frame(
    Model = model_summary$model_label,
    Cases = vapply(model_summary$n_cases, app_joint_qdesn_phase123_fmt_int, character(1L)),
    `Fit MAE` = vapply(model_summary$mcmc_fit_truth_mae, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Forecast MAE` = vapply(model_summary$mcmc_forecast_truth_mae, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Check loss` = vapply(model_summary$mcmc_forecast_check_loss, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Grid CRPS` = vapply(model_summary$mcmc_forecast_crps_grid, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Hit error` = vapply(model_summary$mcmc_abs_hit_rate_error, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Raw crossings` = vapply(model_summary$mcmc_forecast_raw_crossing_pairs, app_joint_qdesn_phase123_fmt_int, character(1L)),
    `Contract crossings` = vapply(model_summary$mcmc_forecast_contract_crossing_pairs, app_joint_qdesn_phase123_fmt_int, character(1L)),
    Status = model_summary$gate_status,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

app_joint_qdesn_phase125_case_table <- function(case_summary) {
  data.frame(
    Scenario = case_summary$scenario_label,
    Model = case_summary$model_label,
    `Forecast MAE` = vapply(case_summary$mcmc_forecast_truth_mae, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Check loss` = vapply(case_summary$mcmc_forecast_check_loss_mean, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Raw crossings` = vapply(case_summary$mcmc_forecast_raw_crossing_pairs, app_joint_qdesn_phase123_fmt_int, character(1L)),
    `Contract crossings` = vapply(case_summary$mcmc_forecast_contract_crossing_pairs, app_joint_qdesn_phase123_fmt_int, character(1L)),
    Status = case_summary$gate_status,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

app_joint_qdesn_phase125_write_latex_table <- function(
  x,
  path,
  caption,
  label,
  align = NULL,
  size = "\\scriptsize",
  resize = FALSE
) {
  app_ensure_dir(dirname(path))
  if (is.null(align)) align <- paste0("@{}", paste(rep("l", ncol(x)), collapse = ""), "@{}")
  body <- lapply(seq_len(nrow(x)), function(ii) {
    paste(app_joint_qdesn_phase123_latex_escape(unlist(x[ii, , drop = FALSE], use.names = FALSE)), collapse = " & ")
  })
  lines <- c(
    "% Generated by application/scripts/129_freeze_joint_qdesn_phase125_balanced_mcmc_audit.R.",
    "\\begin{table}[!htbp]",
    "\\centering",
    size
  )
  if (isTRUE(resize)) lines <- c(lines, "\\resizebox{\\textwidth}{!}{%")
  lines <- c(
    lines,
    sprintf("\\begin{tabular}{%s}", align),
    "\\toprule",
    paste(app_joint_qdesn_phase123_latex_escape(names(x)), collapse = " & "),
    "\\\\",
    "\\midrule",
    paste0(body, " \\\\"),
    "\\bottomrule",
    "\\end{tabular}"
  )
  if (isTRUE(resize)) lines <- c(lines, "}%")
  lines <- c(lines, sprintf("\\caption{%s}", caption), sprintf("\\label{%s}", label), "\\end{table}")
  writeLines(lines, path, useBytes = TRUE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

app_joint_qdesn_phase125_recommendation <- function(gate_summary, scope, model_summary, case_summary) {
  hard_gate_names <- c(
    "source_artifact_manifests", "source_vb_freeze_manifests", "fixture_source_manifests",
    "worker_failures", "balanced_grid_complete", "duplicate_model_scenario_cells",
    "finite_mcmc_draws", "provided_vb_initialization", "contract_crossings",
    "quantile_grid_predictive_contract"
  )
  hard_gate <- app_joint_qdesn_phase123_gate(gate_summary$status[gate_summary$gate %in% hard_gate_names])
  overall <- app_joint_qdesn_phase123_gate(gate_summary$status)
  data.frame(
    recommendation = if (identical(hard_gate, "pass")) "ready_for_article_asset_build_with_review_language" else "blocked_fix_implementation",
    overall_gate = overall,
    hard_implementation_gate = hard_gate,
    balanced_mcmc_grid = if (all(scope$matrix$present_in_balanced_mcmc)) "complete" else "incomplete",
    n_case_rows = nrow(case_summary),
    n_model_rows = nrow(model_summary),
    n_review_cases = sum(case_summary$gate_status == "review", na.rm = TRUE),
    n_fail_cases = sum(case_summary$gate_status == "fail", na.rm = TRUE),
    forecast_contract_crossing_pairs = sum(case_summary$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE),
    forecast_raw_crossing_pairs = sum(case_summary$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE),
    manuscript_action = "Do not mutate the article automatically. Use this frozen audit as the input to the next article-asset rebuild and manuscript QA pass.",
    next_step = if (identical(hard_gate, "pass")) {
      "Build Phase126 article validation assets from Phase125, then compile and QA the manuscript with quantile-grid predictive-contract language."
    } else {
      "Resolve hard implementation gates before article asset construction."
    },
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase125_integration_plan <- function(recommendation) {
  data.frame(
    step = seq_len(6L),
    action = c(
      "Freeze balanced MCMC evidence packet",
      "Review Phase125 gates and diagnostics",
      "Build article validation assets from Phase125",
      "Run manuscript QA for predictive-contract language",
      "Compile the authoritative article repository",
      "Commit/push only after article asset and compile review"
    ),
    status = c(
      "done_by_phase125",
      "ready",
      ifelse(identical(recommendation$hard_implementation_gate[[1L]], "pass"), "recommended_next", "blocked"),
      "pending",
      "pending",
      "pending"
    ),
    detail = c(
      "Phase122 and Phase124c MCMC artifacts are merged by hash-verified source references.",
      "Reviews are raw-crossing/VB diagnostics, not implementation failures.",
      "Use Phase125 as the single source for balanced MCMC tables and figures.",
      "Keep claims restricted to quantile-grid/readout validation.",
      "Compile only after the article-safe asset update.",
      "No article commit is made by Phase125."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase125_readme <- function(run_config, health, recommendation) {
  c(
    "# Joint QDESN Phase 125 Balanced MCMC Audit",
    "",
    "This artifact merges the completed Phase122 and Phase124c MCMC confirmation blocks into a balanced 32-row evidence packet.",
    "",
    "Phase125 does not run VB, VB-LD, MCMC, fixture generation, or manuscript edits. It consumes frozen CSV artifacts and verifies their manifests.",
    "",
    sprintf("- Output directory: `%s`", run_config$out_dir[[1L]]),
    sprintf("- Source blocks: `%s`", run_config$source_block_ids[[1L]]),
    sprintf("- Cases audited: %s", recommendation$n_case_rows[[1L]]),
    sprintf("- Balanced MCMC grid: `%s`", recommendation$balanced_mcmc_grid[[1L]]),
    sprintf("- Overall gate: `%s`", recommendation$overall_gate[[1L]]),
    sprintf("- Hard implementation gate: `%s`", recommendation$hard_implementation_gate[[1L]]),
    sprintf("- Recommendation: `%s`", recommendation$recommendation[[1L]]),
    "",
    "Interpretation contract:",
    "",
    "- VB/VB-LD was used for screening, calibration, and initialization.",
    "- MCMC provides the article-facing confirmation layer for the balanced grid.",
    "- Scores are quantile-grid/readout metrics, not scalar posterior predictive-density validation.",
    "- Raw crossings are retained as diagnostics; reported/scored contract quantiles are monotone.",
    "",
    "Health summary:",
    "",
    paste(sprintf("- `%s`: `%s` (%s)", health$component, health$status, health$progress), collapse = "\n"),
    "",
    "Recommended next action:",
    "",
    recommendation$next_step[[1L]]
  )
}

app_joint_qdesn_run_phase125_balanced_mcmc_audit <- function(
  out_dir = app_joint_qdesn_default_phase125_balanced_mcmc_audit_dir(),
  source_blocks = app_joint_qdesn_phase125_default_mcmc_blocks(),
  expected_scenarios = app_joint_qdesn_phase125_expected_scenarios(),
  expected_models = app_joint_qdesn_phase125_expected_models()
) {
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  app_ensure_dir(out_dir)

  source_blocks$source_dir <- vapply(source_blocks$source_dir, normalizePath, character(1L), winslash = "/", mustWork = TRUE)
  sources <- app_joint_qdesn_phase125_load_blocks(source_blocks)
  src <- app_joint_qdesn_phase125_combined_source(sources)
  scope <- app_joint_qdesn_phase125_scope_audit(src, expected_scenarios = expected_scenarios, expected_models = expected_models)
  gate_summary <- app_joint_qdesn_phase125_gate_summary(src, scope)
  health <- app_joint_qdesn_phase125_health_summary(src, gate_summary, scope)
  model_summary <- app_joint_qdesn_phase123_model_summary(src)
  case_summary <- app_joint_qdesn_phase123_case_summary(src)
  scenario_winners <- app_joint_qdesn_phase125_scenario_winners(src)
  raw_contract <- app_joint_qdesn_phase125_raw_contract_summary(src)
  source_summary <- app_joint_qdesn_phase125_source_block_summary(src)
  model_table <- app_joint_qdesn_phase125_model_table(model_summary)
  case_table <- app_joint_qdesn_phase125_case_table(case_summary)
  gate_table <- gate_summary[, c("gate", "status", "detail"), drop = FALSE]
  names(gate_table) <- c("Gate", "Status", "Detail")
  recommendation <- app_joint_qdesn_phase125_recommendation(gate_summary, scope, model_summary, case_summary)
  integration_plan <- app_joint_qdesn_phase125_integration_plan(recommendation)

  run_config <- data.frame(
    run_id = "joint_qdesn_phase125_balanced_mcmc_audit",
    out_dir = out_dir,
    source_block_ids = paste(source_blocks$source_block_id, collapse = ","),
    source_dirs = paste(source_blocks$source_dir, collapse = ","),
    n_source_blocks = nrow(source_blocks),
    n_cases = nrow(case_summary),
    n_expected_scenarios = length(expected_scenarios),
    n_expected_models = length(expected_models),
    n_expected_cells = length(expected_scenarios) * length(expected_models),
    overall_gate = recommendation$overall_gate[[1L]],
    hard_implementation_gate = recommendation$hard_implementation_gate[[1L]],
    validation_contract = "quantile_grid_readout_fit_and_no_refit_forecast",
    scalar_predictive_density_claim = FALSE,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )

  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase125_readme(run_config, health, recommendation), readme_path, useBytes = TRUE)

  paths <- c(
    run_config = app_joint_qdesn_phase125_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    source_blocks = app_joint_qdesn_phase125_write_csv(source_blocks, file.path(out_dir, "source_blocks.csv")),
    source_block_summary = app_joint_qdesn_phase125_write_csv(source_summary, file.path(out_dir, "source_block_summary.csv")),
    source_artifact_manifest_verification = app_joint_qdesn_phase125_write_csv(src$manifest, file.path(out_dir, "source_artifact_manifest_verification.csv")),
    source_vb_freeze_manifest_verification = app_joint_qdesn_phase125_write_csv(src$phase121_manifest, file.path(out_dir, "source_vb_freeze_manifest_verification.csv")),
    fixture_source_manifest_verification = app_joint_qdesn_phase125_write_csv(src$fixture_manifest, file.path(out_dir, "fixture_source_manifest_verification.csv")),
    combined_mcmc_case_summary = app_joint_qdesn_phase125_write_csv(src$summary, file.path(out_dir, "combined_mcmc_case_summary.csv")),
    combined_mcmc_case_assessment = app_joint_qdesn_phase125_write_csv(src$assessment, file.path(out_dir, "combined_mcmc_case_assessment.csv")),
    model_confirmation_summary = app_joint_qdesn_phase125_write_csv(model_summary, file.path(out_dir, "model_confirmation_summary.csv")),
    scenario_model_confirmation_summary = app_joint_qdesn_phase125_write_csv(case_summary, file.path(out_dir, "scenario_model_confirmation_summary.csv")),
    scenario_winner_summary = app_joint_qdesn_phase125_write_csv(scenario_winners, file.path(out_dir, "scenario_winner_summary.csv")),
    balanced_scope_matrix = app_joint_qdesn_phase125_write_csv(scope$matrix, file.path(out_dir, "balanced_scope_matrix.csv")),
    balanced_scope_by_model = app_joint_qdesn_phase125_write_csv(scope$by_model, file.path(out_dir, "balanced_scope_by_model.csv")),
    balanced_scope_decision = app_joint_qdesn_phase125_write_csv(scope$decision, file.path(out_dir, "balanced_scope_decision.csv")),
    balanced_scope_extra_rows = app_joint_qdesn_phase125_write_csv(scope$extra_rows, file.path(out_dir, "balanced_scope_extra_rows.csv")),
    balanced_scope_duplicate_keys = app_joint_qdesn_phase125_write_csv(scope$duplicate_keys, file.path(out_dir, "balanced_scope_duplicate_keys.csv")),
    balanced_gate_summary = app_joint_qdesn_phase125_write_csv(gate_summary, file.path(out_dir, "balanced_gate_summary.csv")),
    health_check_summary = app_joint_qdesn_phase125_write_csv(health, file.path(out_dir, "health_check_summary.csv")),
    raw_contract_crossing_summary = app_joint_qdesn_phase125_write_csv(raw_contract, file.path(out_dir, "raw_contract_crossing_summary.csv")),
    raw_crossing_diagnostic_summary = app_joint_qdesn_phase125_write_csv(src$assessment[src$assessment$raw_crossing_pairs > 0, , drop = FALSE], file.path(out_dir, "raw_crossing_diagnostic_summary.csv")),
    vb_mcmc_delta_summary = app_joint_qdesn_phase125_write_csv(src$vb_mcmc_distance, file.path(out_dir, "vb_mcmc_delta_summary.csv")),
    chain_stability_summary = app_joint_qdesn_phase125_write_csv(src$chain_distance, file.path(out_dir, "chain_stability_summary.csv")),
    runtime_summary = app_joint_qdesn_phase125_write_csv(src$runtime, file.path(out_dir, "runtime_summary.csv")),
    forecast_truth_distance_summary = app_joint_qdesn_phase125_write_csv(src$forecast_truth, file.path(out_dir, "forecast_truth_distance_summary.csv")),
    forecast_check_loss_summary = app_joint_qdesn_phase125_write_csv(src$forecast_check, file.path(out_dir, "forecast_check_loss_summary.csv")),
    forecast_crps_grid_summary = app_joint_qdesn_phase125_write_csv(src$forecast_crps, file.path(out_dir, "forecast_crps_grid_summary.csv")),
    forecast_hit_rate_summary = app_joint_qdesn_phase125_write_csv(src$forecast_hit, file.path(out_dir, "forecast_hit_rate_summary.csv")),
    forecast_interval_summary = app_joint_qdesn_phase125_write_csv(src$forecast_interval, file.path(out_dir, "forecast_interval_summary.csv")),
    fit_truth_distance_summary = app_joint_qdesn_phase125_write_csv(src$fit_truth, file.path(out_dir, "fit_truth_distance_summary.csv")),
    fit_check_loss_summary = app_joint_qdesn_phase125_write_csv(src$fit_check, file.path(out_dir, "fit_check_loss_summary.csv")),
    article_candidate_mcmc_model_table_csv = app_joint_qdesn_phase125_write_csv(model_table, file.path(out_dir, "article_candidate_mcmc_model_table.csv")),
    article_candidate_mcmc_case_table_csv = app_joint_qdesn_phase125_write_csv(case_table, file.path(out_dir, "article_candidate_mcmc_case_table.csv")),
    article_candidate_gate_table_csv = app_joint_qdesn_phase125_write_csv(gate_table, file.path(out_dir, "article_candidate_gate_table.csv")),
    article_candidate_mcmc_model_table_tex = app_joint_qdesn_phase125_write_latex_table(
      model_table,
      file.path(out_dir, "article_candidate_mcmc_model_table.tex"),
      "Balanced MCMC confirmation summary for the joint multi-quantile validation study. Each model is averaged over the same eight synthetic scenarios. Scores use monotone contract quantile grids; raw crossings are retained as diagnostics.",
      "tab:joint-qdesn-phase125-balanced-mcmc-model-table",
      align = "@{}>{\\raggedright\\arraybackslash}p{0.22\\textwidth}rrrrrrrll@{}",
      resize = TRUE
    ),
    article_candidate_mcmc_case_table_tex = app_joint_qdesn_phase125_write_latex_table(
      case_table,
      file.path(out_dir, "article_candidate_mcmc_case_table.tex"),
      "Scenario-level balanced MCMC confirmation diagnostics. Raw crossings are pre-contract diagnostics; contract crossings correspond to the monotone quantile grids used for scoring.",
      "tab:joint-qdesn-phase125-balanced-mcmc-case-table",
      align = "@{}>{\\raggedright\\arraybackslash}p{0.19\\textwidth}>{\\raggedright\\arraybackslash}p{0.17\\textwidth}rrrrll@{}",
      resize = TRUE
    ),
    article_candidate_gate_table_tex = app_joint_qdesn_phase125_write_latex_table(
      gate_table,
      file.path(out_dir, "article_candidate_mcmc_gate_table.tex"),
      "Phase125 validation gates for the balanced MCMC article-candidate evidence packet.",
      "tab:joint-qdesn-phase125-balanced-mcmc-gate-table",
      align = "@{}>{\\raggedright\\arraybackslash}p{0.27\\textwidth}l>{\\raggedright\\arraybackslash}p{0.55\\textwidth}@{}",
      resize = TRUE
    ),
    article_promotion_recommendation = app_joint_qdesn_phase125_write_csv(recommendation, file.path(out_dir, "article_promotion_recommendation.csv")),
    article_integration_plan = app_joint_qdesn_phase125_write_csv(integration_plan, file.path(out_dir, "article_integration_plan.csv")),
    provenance = app_joint_qdesn_phase125_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, winslash = "/", mustWork = TRUE)
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, winslash = "/", mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    health = health,
    gate_summary = gate_summary,
    model_summary = model_summary,
    case_summary = case_summary,
    scope = scope,
    scenario_winners = scenario_winners,
    recommendation = recommendation
  )
}
