# Phase 123 MCMC confirmation audit and article-candidate freeze.

app_joint_qdesn_default_phase123_mcmc_article_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase123_mcmc_article_candidate_freeze_20260711")
}

app_joint_qdesn_phase123_required_phase122_files <- function() {
  c(
    "run_config.csv",
    "phase121_source_manifest_verification.csv",
    "fixture_source_manifest.csv",
    "case_winner_controls.csv",
    "scenario_worker_failures.csv",
    "mcmc_case_summary.csv",
    "mcmc_case_assessment.csv",
    "forecast_truth_distance_summary.csv",
    "forecast_check_loss_summary.csv",
    "forecast_crps_grid_summary.csv",
    "forecast_hit_rate_summary.csv",
    "forecast_interval_summary.csv",
    "fit_truth_distance_summary.csv",
    "fit_check_loss_summary.csv",
    "crossing_summary.csv",
    "raw_crossing_summary.csv",
    "vb_convergence_audit.csv",
    "objective_diagnostics.csv",
    "mcmc_draw_summary.csv",
    "vb_mcmc_distance_summary.csv",
    "chain_to_pooled_distance_summary.csv",
    "runtime_summary.csv",
    "provenance.csv",
    "artifact_manifest.csv"
  )
}

app_joint_qdesn_phase123_read_csv <- function(dir, file, required = TRUE) {
  path <- file.path(dir, file)
  app_read_csv(path, required = required)
}

app_joint_qdesn_phase123_load_phase122 <- function(phase122_dir) {
  phase122_dir <- normalizePath(phase122_dir, winslash = "/", mustWork = TRUE)
  required <- app_joint_qdesn_phase123_required_phase122_files()
  missing <- required[!file.exists(file.path(phase122_dir, required))]
  if (length(missing)) {
    stop(sprintf(
      "Phase122 directory is missing required files: %s",
      paste(missing, collapse = ", ")
    ), call. = FALSE)
  }

  manifest <- app_joint_qdesn_phase108_manifest_verify(phase122_dir, "phase122_mcmc_case_confirmation")
  summary <- app_joint_qdesn_phase123_read_csv(phase122_dir, "mcmc_case_summary.csv")
  assessment <- app_joint_qdesn_phase123_read_csv(phase122_dir, "mcmc_case_assessment.csv")
  run_config <- app_joint_qdesn_phase123_read_csv(phase122_dir, "run_config.csv")
  app_check_required_columns(summary, c(
    "case_id", "scenario_id", "scenario_class", "distribution_family",
    "dynamics_class", "source_model_id", "model_id", "display_label",
    "likelihood", "fit_structure", "mcmc_n_chains", "mcmc_n_iter",
    "mcmc_burn", "mcmc_thin", "mcmc_n_keep_total",
    "all_chain_init_source_provided", "mcmc_draws_all_finite",
    "vb_fit_truth_mae", "mcmc_fit_truth_mae",
    "vb_forecast_truth_mae", "mcmc_forecast_truth_mae",
    "vb_forecast_check_loss_mean", "mcmc_forecast_check_loss_mean",
    "mcmc_forecast_raw_crossing_pairs",
    "mcmc_forecast_contract_crossing_pairs",
    "mcmc_forecast_max_abs_adjustment",
    "vb_mcmc_max_normalized_distance",
    "max_chain_to_pooled_normalized_distance",
    "mcmc_elapsed_seconds", "total_elapsed_seconds"
  ), "Phase122 MCMC case summary")
  app_check_required_columns(assessment, c(
    "case_id", "scenario_id", "source_model_id", "implementation_status",
    "distance_status", "chain_status", "raw_crossing_status",
    "gate_status", "contract_crossing_pairs", "raw_crossing_pairs",
    "max_abs_adjustment", "status_reason"
  ), "Phase122 MCMC case assessment")

  list(
    phase122_dir = phase122_dir,
    manifest = manifest,
    run_config = run_config,
    phase121_manifest = app_joint_qdesn_phase123_read_csv(phase122_dir, "phase121_source_manifest_verification.csv"),
    fixture_manifest = app_joint_qdesn_phase123_read_csv(phase122_dir, "fixture_source_manifest.csv"),
    controls = app_joint_qdesn_phase123_read_csv(phase122_dir, "case_winner_controls.csv"),
    failures = app_joint_qdesn_phase123_read_csv(phase122_dir, "scenario_worker_failures.csv"),
    summary = summary,
    assessment = assessment,
    forecast_truth = app_joint_qdesn_phase123_read_csv(phase122_dir, "forecast_truth_distance_summary.csv"),
    forecast_check = app_joint_qdesn_phase123_read_csv(phase122_dir, "forecast_check_loss_summary.csv"),
    forecast_crps = app_joint_qdesn_phase123_read_csv(phase122_dir, "forecast_crps_grid_summary.csv"),
    forecast_hit = app_joint_qdesn_phase123_read_csv(phase122_dir, "forecast_hit_rate_summary.csv"),
    forecast_interval = app_joint_qdesn_phase123_read_csv(phase122_dir, "forecast_interval_summary.csv"),
    fit_truth = app_joint_qdesn_phase123_read_csv(phase122_dir, "fit_truth_distance_summary.csv"),
    fit_check = app_joint_qdesn_phase123_read_csv(phase122_dir, "fit_check_loss_summary.csv"),
    crossing = app_joint_qdesn_phase123_read_csv(phase122_dir, "crossing_summary.csv"),
    raw_crossing = app_joint_qdesn_phase123_read_csv(phase122_dir, "raw_crossing_summary.csv"),
    vb_convergence = app_joint_qdesn_phase123_read_csv(phase122_dir, "vb_convergence_audit.csv"),
    objective = app_joint_qdesn_phase123_read_csv(phase122_dir, "objective_diagnostics.csv"),
    draws = app_joint_qdesn_phase123_read_csv(phase122_dir, "mcmc_draw_summary.csv"),
    vb_mcmc_distance = app_joint_qdesn_phase123_read_csv(phase122_dir, "vb_mcmc_distance_summary.csv"),
    chain_distance = app_joint_qdesn_phase123_read_csv(phase122_dir, "chain_to_pooled_distance_summary.csv"),
    runtime = app_joint_qdesn_phase123_read_csv(phase122_dir, "runtime_summary.csv"),
    provenance = app_joint_qdesn_phase123_read_csv(phase122_dir, "provenance.csv")
  )
}

app_joint_qdesn_phase123_gate <- function(status) {
  status <- as.character(status)
  if (!length(status) || any(status == "fail", na.rm = TRUE)) return("fail")
  if (any(status == "review", na.rm = TRUE)) return("review")
  "pass"
}

app_joint_qdesn_phase123_label <- function(x) {
  x <- as.character(x)
  x <- gsub(" MCMC$", "", x)
  x <- ifelse(x == "JOINT QDESN RHS", "Joint QDESN RHS", x)
  x <- ifelse(x == "QDESN RHS", "Independent QDESN RHS", x)
  x <- ifelse(x == "JOINT exQDESN RHS", "Joint exQDESN RHS", x)
  x <- ifelse(x == "exQDESN RHS", "Independent exQDESN RHS", x)
  x
}

app_joint_qdesn_phase123_scenario_label <- function(x) {
  out <- tools::toTitleCase(gsub("_", " ", as.character(x), fixed = TRUE))
  out <- ifelse(out %in% c("Student T Location Scale", "Student t Location Scale"), "Student-t Location-Scale", out)
  out <- ifelse(out == "Gaussian Mixture Bridge", "Gaussian-Mixture Bridge", out)
  out
}

app_joint_qdesn_phase123_fmt_num <- function(x, digits = 3L) {
  x <- suppressWarnings(as.numeric(x))
  if (!length(x) || !is.finite(x[[1L]])) return("--")
  formatC(x[[1L]], format = "f", digits = digits)
}

app_joint_qdesn_phase123_fmt_int <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  if (!length(x) || !is.finite(x[[1L]])) return("--")
  formatC(round(x[[1L]]), format = "d", big.mark = ",")
}

app_joint_qdesn_phase123_latex_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("([#$%&_{}])", "\\\\\\1", x, perl = TRUE)
  x <- gsub("~", "\\\\textasciitilde{}", x, fixed = TRUE)
  x <- gsub("\\^", "\\\\textasciicircum{}", x)
  x
}

app_joint_qdesn_phase123_write_latex_table <- function(
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
    "% Generated by application/scripts/126_freeze_joint_qdesn_phase123_mcmc_article_candidate.R.",
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

app_joint_qdesn_phase123_write_csv <- function(x, path) {
  app_ensure_dir(dirname(path))
  utils::write.csv(x, path, row.names = FALSE, na = "")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

app_joint_qdesn_phase123_model_order <- function(model_id) {
  order <- c(
    "joint_qdesn_rhs_vb",
    "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb",
    "exqdesn_rhs_independent_vb"
  )
  match(model_id, order)
}

app_joint_qdesn_phase123_mean_metric <- function(x, by, value, out_name = value) {
  if (!value %in% names(x)) {
    return(data.frame())
  }
  out <- aggregate(x[[value]], x[by], mean, na.rm = TRUE)
  names(out)[ncol(out)] <- out_name
  out
}

app_joint_qdesn_phase123_model_summary <- function(src) {
  s <- src$summary
  a <- src$assessment[, c("case_id", "gate_status", "status_reason"), drop = FALSE]
  s <- merge(s, a, by = "case_id", all.x = TRUE, suffixes = c("", "_assessment"))
  by <- c("source_model_id", "model_id", "display_label", "likelihood", "fit_structure")
  rows <- lapply(split(s, s$source_model_id), function(block) {
    data.frame(
      source_model_id = block$source_model_id[[1L]],
      model_id = block$model_id[[1L]],
      model_label = app_joint_qdesn_phase123_label(block$display_label[[1L]]),
      likelihood = block$likelihood[[1L]],
      fit_structure = block$fit_structure[[1L]],
      n_cases = nrow(block),
      n_pass = sum(block$gate_status == "pass", na.rm = TRUE),
      n_review = sum(block$gate_status == "review", na.rm = TRUE),
      n_fail = sum(block$gate_status == "fail", na.rm = TRUE),
      mcmc_fit_truth_mae = mean(block$mcmc_fit_truth_mae, na.rm = TRUE),
      mcmc_forecast_truth_mae = mean(block$mcmc_forecast_truth_mae, na.rm = TRUE),
      mcmc_forecast_check_loss = mean(block$mcmc_forecast_check_loss_mean, na.rm = TRUE),
      vb_forecast_truth_mae = mean(block$vb_forecast_truth_mae, na.rm = TRUE),
      mcmc_minus_vb_forecast_truth_mae = mean(block$mcmc_forecast_truth_mae - block$vb_forecast_truth_mae, na.rm = TRUE),
      mcmc_forecast_raw_crossing_pairs = sum(block$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE),
      mcmc_forecast_contract_crossing_pairs = sum(block$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE),
      max_abs_adjustment = max(block$mcmc_forecast_max_abs_adjustment, na.rm = TRUE),
      vb_mcmc_max_normalized_distance = max(block$vb_mcmc_max_normalized_distance, na.rm = TRUE),
      max_chain_to_pooled_normalized_distance = max(block$max_chain_to_pooled_normalized_distance, na.rm = TRUE),
      mean_total_runtime_minutes = mean(block$total_elapsed_seconds, na.rm = TRUE) / 60,
      total_mcmc_runtime_minutes = sum(block$mcmc_elapsed_seconds, na.rm = TRUE) / 60,
      gate_status = app_joint_qdesn_phase123_gate(block$gate_status),
      stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  crps <- app_joint_qdesn_phase123_mean_metric(
    src$forecast_crps[grepl("_mcmc$", src$forecast_crps$model_id), , drop = FALSE],
    by = c("model_id"), value = "crps_grid_mean", out_name = "mcmc_forecast_crps_grid"
  )
  hit <- app_joint_qdesn_phase123_mean_metric(
    src$forecast_hit[grepl("_mcmc$", src$forecast_hit$model_id), , drop = FALSE],
    by = c("model_id"), value = "abs_hit_rate_error", out_name = "mcmc_abs_hit_rate_error"
  )
  interval <- app_joint_qdesn_phase123_mean_metric(
    src$forecast_interval[grepl("_mcmc$", src$forecast_interval$model_id), , drop = FALSE],
    by = c("model_id"), value = "abs_coverage_error", out_name = "mcmc_abs_coverage_error"
  )
  for (extra in list(crps, hit, interval)) {
    if (nrow(extra)) out <- merge(out, extra, by = "model_id", all.x = TRUE)
  }
  out <- out[order(app_joint_qdesn_phase123_model_order(out$source_model_id)), , drop = FALSE]
  row.names(out) <- NULL
  out
}

app_joint_qdesn_phase123_case_summary <- function(src) {
  s <- src$summary
  a <- src$assessment[, c("case_id", "gate_status", "status_reason", "raw_crossing_status"), drop = FALSE]
  out <- merge(s, a, by = "case_id", all.x = TRUE)
  out$scenario_label <- app_joint_qdesn_phase123_scenario_label(out$scenario_id)
  out$model_label <- app_joint_qdesn_phase123_label(out$display_label)
  out$fit_truth_mae_delta_mcmc_minus_vb <- out$mcmc_fit_truth_mae - out$vb_fit_truth_mae
  out$forecast_truth_mae_delta_mcmc_minus_vb <- out$mcmc_forecast_truth_mae - out$vb_forecast_truth_mae
  out$forecast_check_loss_delta_mcmc_minus_vb <- out$mcmc_forecast_check_loss_mean - out$vb_forecast_check_loss_mean
  out$forecast_raw_crossing_delta_mcmc_minus_vb <- out$mcmc_forecast_raw_crossing_pairs - out$vb_forecast_raw_crossing_pairs
  keep <- c(
    "case_id", "scenario_id", "scenario_label", "scenario_class", "distribution_family",
    "dynamics_class", "source_model_id", "model_id", "model_label", "likelihood",
    "fit_structure", "phase121_selection_status", "gate_status", "status_reason",
    "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae",
    "mcmc_forecast_check_loss_mean", "fit_truth_mae_delta_mcmc_minus_vb",
    "forecast_truth_mae_delta_mcmc_minus_vb", "forecast_check_loss_delta_mcmc_minus_vb",
    "mcmc_forecast_raw_crossing_pairs", "mcmc_forecast_contract_crossing_pairs",
    "mcmc_forecast_max_abs_adjustment", "vb_mcmc_max_normalized_distance",
    "max_chain_to_pooled_normalized_distance", "mcmc_elapsed_seconds",
    "total_elapsed_seconds"
  )
  out <- out[, intersect(keep, names(out)), drop = FALSE]
  out[order(app_joint_qdesn_phase123_model_order(out$source_model_id), out$scenario_id), , drop = FALSE]
}

app_joint_qdesn_phase123_scope_audit <- function(src, expected_model_ids = NULL) {
  if (is.null(expected_model_ids)) {
    expected_model_ids <- c(
      "joint_qdesn_rhs_vb",
      "qdesn_rhs_independent_vb",
      "joint_exqdesn_rhs_vb",
      "exqdesn_rhs_independent_vb"
    )
  }
  s <- src$summary
  scenarios <- sort(unique(s$scenario_id))
  grid <- expand.grid(
    scenario_id = scenarios,
    source_model_id = expected_model_ids,
    stringsAsFactors = FALSE
  )
  present_key <- paste(s$scenario_id, s$source_model_id, sep = "||")
  grid$present_in_phase122 <- paste(grid$scenario_id, grid$source_model_id, sep = "||") %in% present_key
  grid$scenario_label <- app_joint_qdesn_phase123_scenario_label(grid$scenario_id)
  model_labels <- setNames(
    c("Joint QDESN RHS", "Independent QDESN RHS", "Joint exQDESN RHS", "Independent exQDESN RHS"),
    expected_model_ids
  )
  grid$model_label <- unname(model_labels[grid$source_model_id])

  by_model <- lapply(expected_model_ids, function(mid) {
    sc <- sort(unique(s$scenario_id[s$source_model_id == mid]))
    data.frame(
      source_model_id = mid,
      model_label = unname(model_labels[mid]),
      n_scenarios_confirmed = length(sc),
      scenario_ids_confirmed = paste(sc, collapse = ","),
      n_scenarios_missing = sum(!grid$present_in_phase122[grid$source_model_id == mid]),
      scenario_ids_missing = paste(grid$scenario_id[grid$source_model_id == mid & !grid$present_in_phase122], collapse = ","),
      stringsAsFactors = FALSE
    )
  })
  by_model <- app_joint_qdesn_bind_rows(by_model)
  scenario_sets <- split(s$scenario_id, s$source_model_id)
  common <- Reduce(intersect, scenario_sets[intersect(expected_model_ids, names(scenario_sets))])
  full_grid_complete <- all(grid$present_in_phase122)
  status <- if (all(expected_model_ids %in% unique(s$source_model_id)) && length(common) > 0L && full_grid_complete) "pass" else "review"
  decision <- data.frame(
    audit_item = c(
      "case_specific_winner_confirmation",
      "balanced_four_model_by_scenario_comparison",
      "common_scenario_intersection",
      "recommended_article_use"
    ),
    status = c(
      ifelse(all(expected_model_ids %in% unique(s$source_model_id)), "pass", "fail"),
      ifelse(full_grid_complete, "pass", "review"),
      ifelse(length(common) > 0L, "pass", "review"),
      "review"
    ),
    detail = c(
      sprintf("%d frozen Phase121 case-specific winners were confirmed by Phase122 MCMC.", nrow(s)),
      sprintf("%d of %d model-scenario cells are present.", sum(grid$present_in_phase122), nrow(grid)),
      if (length(common)) paste(common, collapse = ",") else "No scenario has all four model rows confirmed by MCMC.",
      "Use Phase122 as a case-specific MCMC confirmation packet. Do not present it as a balanced four-model comparison unless missing cells are completed or the manuscript explicitly frames it as case-specific."
    ),
    stringsAsFactors = FALSE
  )
  list(matrix = grid, by_model = by_model, decision = decision, scope_status = status)
}

app_joint_qdesn_phase123_status_counts <- function(x) {
  tab <- table(as.character(x), useNA = "ifany")
  paste(sprintf("%s=%s", names(tab), as.integer(tab)), collapse = "; ")
}

app_joint_qdesn_phase123_gate_summary <- function(src, scope) {
  manifest_status <- if (nrow(src$manifest) && all(src$manifest$status == "pass")) "pass" else "fail"
  phase121_status <- if (nrow(src$phase121_manifest) && all(src$phase121_manifest$status == "pass")) "pass" else "fail"
  fixture_status <- if (nrow(src$fixture_manifest) && all(src$fixture_manifest$status == "pass")) "pass" else "fail"
  scalar_claim <- if ("scalar_predictive_density_claim" %in% names(src$run_config)) {
    isTRUE(as.logical(src$run_config$scalar_predictive_density_claim[[1L]]))
  } else {
    NA
  }
  assessment <- src$assessment
  summary <- src$summary
  total_raw_crossings <- sum(assessment$raw_crossing_pairs, na.rm = TRUE)
  forecast_raw_crossings <- sum(summary$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE)
  contract_crossings <- sum(assessment$contract_crossing_pairs, na.rm = TRUE)
  rows <- data.frame(
    gate = c(
      "phase122_artifact_manifest",
      "phase121_source_manifest",
      "fixture_source_manifest",
      "worker_failures",
      "finite_mcmc_draws",
      "provided_vb_initialization",
      "contract_crossings",
      "raw_crossings",
      "chain_stability",
      "vb_mcmc_distance",
      "quantile_grid_predictive_contract",
      "balanced_article_scope"
    ),
    status = c(
      manifest_status,
      phase121_status,
      fixture_status,
      ifelse(nrow(src$failures) == 0L, "pass", "fail"),
      ifelse(all(summary$mcmc_draws_all_finite), "pass", "fail"),
      ifelse(all(summary$all_chain_init_source_provided), "pass", "fail"),
      ifelse(contract_crossings == 0, "pass", "fail"),
      ifelse(total_raw_crossings == 0, "pass", "review"),
      app_joint_qdesn_phase123_gate(assessment$chain_status),
      app_joint_qdesn_phase123_gate(assessment$distance_status),
      ifelse(isFALSE(scalar_claim), "pass", "fail"),
      scope$scope_status
    ),
    detail = c(
      sprintf("%d Phase122 files verified by SHA-256.", nrow(src$manifest)),
      sprintf("%d Phase121 source rows checked.", nrow(src$phase121_manifest)),
      sprintf("%d fixture source rows checked.", nrow(src$fixture_manifest)),
      sprintf("%d worker failure rows.", nrow(src$failures)),
      sprintf("%d of %d cases report finite MCMC draws.", sum(summary$mcmc_draws_all_finite), nrow(summary)),
      sprintf("%d of %d cases report provided VB initialization.", sum(summary$all_chain_init_source_provided), nrow(summary)),
      sprintf("%d contract crossing pairs after monotone grid contract.", contract_crossings),
      sprintf("%d total raw diagnostic crossing pairs before monotone grid contract; %d occur in the forecast window.", total_raw_crossings, forecast_raw_crossings),
      app_joint_qdesn_phase123_status_counts(assessment$chain_status),
      app_joint_qdesn_phase123_status_counts(assessment$distance_status),
      sprintf("scalar_predictive_density_claim=%s; validation is quantile-grid based.", as.character(scalar_claim)),
      scope$decision$detail[scope$decision$audit_item == "balanced_four_model_by_scenario_comparison"]
    ),
    stringsAsFactors = FALSE
  )
  rows
}

app_joint_qdesn_phase123_health_summary <- function(src, gate_summary, scope) {
  summary <- src$summary
  assessment <- src$assessment
  total_raw_crossings <- sum(assessment$raw_crossing_pairs, na.rm = TRUE)
  forecast_raw_crossings <- sum(summary$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE)
  contract_crossings <- sum(assessment$contract_crossing_pairs, na.rm = TRUE)
  data.frame(
    component = c(
      "Phase122 run completion",
      "Case-specific MCMC confirmation",
      "Implementation gates",
      "Raw crossing diagnostics",
      "Balanced comparison coverage",
      "Predictive contract",
      "Article integration"
    ),
    status = c(
      "complete",
      app_joint_qdesn_phase123_gate(assessment$gate_status),
      app_joint_qdesn_phase123_gate(gate_summary$status[gate_summary$gate %in% c(
        "phase122_artifact_manifest", "phase121_source_manifest", "fixture_source_manifest",
        "worker_failures", "finite_mcmc_draws", "provided_vb_initialization", "contract_crossings"
      )]),
      ifelse(total_raw_crossings == 0, "pass", "review"),
      scope$scope_status,
      gate_summary$status[gate_summary$gate == "quantile_grid_predictive_contract"],
      "not_mutated"
    ),
    progress = c(
      sprintf("%d/%d cases complete", nrow(summary), nrow(summary)),
      sprintf("%d pass, %d review, %d fail", sum(assessment$gate_status == "pass"), sum(assessment$gate_status == "review"), sum(assessment$gate_status == "fail")),
      "All hard implementation gates are evaluated from frozen CSV artifacts.",
      sprintf("%d total raw pairs (%d forecast); %d contract pairs", total_raw_crossings, forecast_raw_crossings, contract_crossings),
      sprintf("%d/%d model-scenario cells present", sum(scope$matrix$present_in_phase122), nrow(scope$matrix)),
      "Scores are quantile-grid/readout scores; no scalar predictive-density claim is used.",
      "Phase123 writes candidate assets in cache only."
    ),
    immediate_action = c(
      "No more waiting on Phase122.",
      "Use as MCMC confirmation evidence with review language where raw crossings remain.",
      "Do not rerun MCMC for implementation reasons.",
      "Report raw crossings as diagnostics and contract crossings as the scored grid.",
      "Decide whether to launch a balanced completion run before main-table promotion.",
      "Keep manuscript claims scoped to quantile-grid validation.",
      "Do not edit main.tex until the scope decision is approved."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase123_article_model_table <- function(model_summary) {
  data.frame(
    Model = model_summary$model_label,
    Cases = app_joint_qdesn_phase123_fmt_int(model_summary$n_cases),
    `Fit MAE` = vapply(model_summary$mcmc_fit_truth_mae, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Forecast MAE` = vapply(model_summary$mcmc_forecast_truth_mae, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Check loss` = vapply(model_summary$mcmc_forecast_check_loss, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Grid CRPS` = vapply(model_summary$mcmc_forecast_crps_grid, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Hit error` = vapply(model_summary$mcmc_abs_hit_rate_error, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Raw crossings` = vapply(model_summary$mcmc_forecast_raw_crossing_pairs, app_joint_qdesn_phase123_fmt_int, character(1L)),
    `Status` = model_summary$gate_status,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

app_joint_qdesn_phase123_article_case_table <- function(case_summary) {
  data.frame(
    Scenario = case_summary$scenario_label,
    Model = case_summary$model_label,
    `Forecast MAE` = vapply(case_summary$mcmc_forecast_truth_mae, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Check loss` = vapply(case_summary$mcmc_forecast_check_loss_mean, app_joint_qdesn_phase123_fmt_num, character(1L), digits = 3),
    `Raw crossings` = vapply(case_summary$mcmc_forecast_raw_crossing_pairs, app_joint_qdesn_phase123_fmt_int, character(1L)),
    `Contract crossings` = vapply(case_summary$mcmc_forecast_contract_crossing_pairs, app_joint_qdesn_phase123_fmt_int, character(1L)),
    `Status` = case_summary$gate_status,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

app_joint_qdesn_phase123_promotion_recommendation <- function(
  gate_summary,
  scope,
  model_summary,
  case_summary,
  total_raw_diagnostic_crossing_pairs = NA_real_
) {
  overall <- app_joint_qdesn_phase123_gate(gate_summary$status)
  hard_gates <- gate_summary[gate_summary$gate %in% c(
    "phase122_artifact_manifest", "phase121_source_manifest", "fixture_source_manifest",
    "worker_failures", "finite_mcmc_draws", "provided_vb_initialization",
    "contract_crossings", "quantile_grid_predictive_contract"
  ), , drop = FALSE]
  hard_gate <- app_joint_qdesn_phase123_gate(hard_gates$status)
  balanced <- scope$decision$status[scope$decision$audit_item == "balanced_four_model_by_scenario_comparison"]
  data.frame(
    recommendation = if (identical(hard_gate, "pass")) {
      "ready_for_case_specific_article_candidate_review"
    } else {
      "blocked_fix_implementation"
    },
    overall_gate = overall,
    hard_implementation_gate = hard_gate,
    case_specific_mcmc_confirmation = ifelse(identical(hard_gate, "pass"), "complete", "blocked"),
    balanced_four_model_table = ifelse(identical(balanced, "pass"), "ready", "needs_phase124_completion_or_case_specific_framing"),
    n_case_rows = nrow(case_summary),
    n_model_rows = nrow(model_summary),
    n_review_cases = sum(case_summary$gate_status == "review", na.rm = TRUE),
    n_fail_cases = sum(case_summary$gate_status == "fail", na.rm = TRUE),
    forecast_contract_crossing_pairs = sum(case_summary$mcmc_forecast_contract_crossing_pairs, na.rm = TRUE),
    forecast_raw_crossing_pairs = sum(case_summary$mcmc_forecast_raw_crossing_pairs, na.rm = TRUE),
    total_raw_diagnostic_crossing_pairs = total_raw_diagnostic_crossing_pairs,
    manuscript_action = "Do not update the authoritative manuscript until deciding whether the article table is case-specific or a balanced four-model comparison.",
    next_step = if (identical(balanced, "pass")) {
      "Build article tables directly from Phase123 evidence and compile."
    } else {
      "Either promote a clearly labeled case-specific MCMC confirmation table, or launch Phase124 to complete missing model-scenario MCMC cells before a balanced comparison table."
    },
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase123_integration_plan <- function(scope, recommendation) {
  missing <- scope$matrix[!scope$matrix$present_in_phase122, , drop = FALSE]
  launch_note <- if (nrow(missing)) {
    sprintf(
      "Phase124 should target %d missing model-scenario cells if a balanced four-model MCMC table is required.",
      nrow(missing)
    )
  } else {
    "No Phase124 balanced-completion launch is required."
  }
  data.frame(
    step = seq_len(6L),
    action = c(
      "Freeze Phase123 evidence packet",
      "Choose article table scope",
      "If balanced scope is required, prepare Phase124 completion registry",
      "If case-specific scope is accepted, build manuscript tables from Phase123",
      "Run manuscript compile and article QA",
      "Commit/push only after table-scope decision and compile pass"
    ),
    status = c(
      "done_by_phase123",
      "requires_user_decision",
      ifelse(nrow(missing), "recommended_before_balanced_table", "not_needed"),
      ifelse(identical(recommendation$hard_implementation_gate[[1L]], "pass"), "available", "blocked"),
      "pending",
      "pending"
    ),
    detail = c(
      "All Phase122 source hashes, gates, and article-candidate summaries are written here.",
      "Case-specific MCMC confirmation is complete; balanced four-model comparison is not complete.",
      launch_note,
      "Use raw/contract crossing language and quantile-grid predictive contract language.",
      "Compile after modifying top-level tables or manuscript text.",
      "No commit is made by Phase123 unless explicitly requested."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_phase123_readme <- function(run_config, gate_summary, recommendation) {
  c(
    "# Joint QDESN Phase 123 MCMC Article-Candidate Freeze",
    "",
    "This artifact audits the completed Phase122 MCMC confirmation layer and freezes an article-candidate evidence packet.",
    "",
    "Phase123 does not run VB, VB-LD, MCMC, fixture generation, or manuscript edits. It consumes frozen Phase122 CSV artifacts.",
    "",
    sprintf("- Phase122 source: `%s`", run_config$phase122_dir[[1L]]),
    sprintf("- Cases audited: %s", recommendation$n_case_rows[[1L]]),
    sprintf("- Overall gate: `%s`", recommendation$overall_gate[[1L]]),
    sprintf("- Hard implementation gate: `%s`", recommendation$hard_implementation_gate[[1L]]),
    sprintf("- Recommendation: `%s`", recommendation$recommendation[[1L]]),
    "",
    "Important interpretation:",
    "",
    "- MCMC confirms case-specific VB/VB-LD winners selected by earlier screening.",
    "- Scores are quantile-grid/readout metrics, not scalar posterior predictive-density validation.",
    "- Raw crossings are retained as diagnostics; reported/scored contract quantiles are monotone.",
    "- The Phase122 case set is not a balanced four-model-by-scenario grid.",
    "",
    "Recommended next action:",
    "",
    recommendation$next_step[[1L]]
  )
}

app_joint_qdesn_run_phase123_mcmc_article_freeze <- function(
  out_dir = app_joint_qdesn_default_phase123_mcmc_article_freeze_dir(),
  phase122_dir = app_joint_qdesn_default_phase122_mcmc_case_confirmation_dir()
) {
  phase122_dir <- normalizePath(phase122_dir, winslash = "/", mustWork = TRUE)
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = FALSE)
  app_ensure_dir(out_dir)

  src <- app_joint_qdesn_phase123_load_phase122(phase122_dir)
  scope <- app_joint_qdesn_phase123_scope_audit(src)
  gate_summary <- app_joint_qdesn_phase123_gate_summary(src, scope)
  health <- app_joint_qdesn_phase123_health_summary(src, gate_summary, scope)
  model_summary <- app_joint_qdesn_phase123_model_summary(src)
  case_summary <- app_joint_qdesn_phase123_case_summary(src)
  model_table <- app_joint_qdesn_phase123_article_model_table(model_summary)
  case_table <- app_joint_qdesn_phase123_article_case_table(case_summary)
  gate_table <- gate_summary[, c("gate", "status", "detail"), drop = FALSE]
  names(gate_table) <- c("Gate", "Status", "Detail")
  recommendation <- app_joint_qdesn_phase123_promotion_recommendation(
    gate_summary,
    scope,
    model_summary,
    case_summary,
    total_raw_diagnostic_crossing_pairs = sum(src$assessment$raw_crossing_pairs, na.rm = TRUE)
  )
  integration_plan <- app_joint_qdesn_phase123_integration_plan(scope, recommendation)

  run_config <- data.frame(
    run_id = "joint_qdesn_phase123_mcmc_article_candidate_freeze",
    out_dir = out_dir,
    phase122_dir = phase122_dir,
    n_cases = nrow(case_summary),
    n_models = length(unique(case_summary$source_model_id)),
    overall_gate = recommendation$overall_gate[[1L]],
    hard_implementation_gate = recommendation$hard_implementation_gate[[1L]],
    validation_contract = "quantile_grid_readout_fit_and_no_refit_forecast",
    scalar_predictive_density_claim = FALSE,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )

  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_qdesn_phase123_readme(run_config, gate_summary, recommendation), readme_path, useBytes = TRUE)

  paths <- c(
    run_config = app_joint_qdesn_phase123_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    phase122_source_manifest_verification = app_joint_qdesn_phase123_write_csv(src$manifest, file.path(out_dir, "phase122_source_manifest_verification.csv")),
    phase121_source_manifest_verification = app_joint_qdesn_phase123_write_csv(src$phase121_manifest, file.path(out_dir, "phase121_source_manifest_verification.csv")),
    fixture_source_manifest = app_joint_qdesn_phase123_write_csv(src$fixture_manifest, file.path(out_dir, "fixture_source_manifest.csv")),
    health_check_summary = app_joint_qdesn_phase123_write_csv(health, file.path(out_dir, "health_check_summary.csv")),
    article_gate_summary = app_joint_qdesn_phase123_write_csv(gate_summary, file.path(out_dir, "article_gate_summary.csv")),
    model_confirmation_summary = app_joint_qdesn_phase123_write_csv(model_summary, file.path(out_dir, "model_confirmation_summary.csv")),
    case_confirmation_summary = app_joint_qdesn_phase123_write_csv(case_summary, file.path(out_dir, "case_confirmation_summary.csv")),
    article_scope_matrix = app_joint_qdesn_phase123_write_csv(scope$matrix, file.path(out_dir, "article_scope_matrix.csv")),
    article_scope_by_model = app_joint_qdesn_phase123_write_csv(scope$by_model, file.path(out_dir, "article_scope_by_model.csv")),
    article_scope_decision = app_joint_qdesn_phase123_write_csv(scope$decision, file.path(out_dir, "article_scope_decision.csv")),
    raw_crossing_diagnostic_summary = app_joint_qdesn_phase123_write_csv(src$assessment[src$assessment$raw_crossing_pairs > 0, , drop = FALSE], file.path(out_dir, "raw_crossing_diagnostic_summary.csv")),
    vb_mcmc_delta_summary = app_joint_qdesn_phase123_write_csv(src$vb_mcmc_distance, file.path(out_dir, "vb_mcmc_delta_summary.csv")),
    chain_stability_summary = app_joint_qdesn_phase123_write_csv(src$chain_distance, file.path(out_dir, "chain_stability_summary.csv")),
    article_candidate_model_table_csv = app_joint_qdesn_phase123_write_csv(model_table, file.path(out_dir, "article_candidate_mcmc_model_table.csv")),
    article_candidate_case_table_csv = app_joint_qdesn_phase123_write_csv(case_table, file.path(out_dir, "article_candidate_mcmc_case_table.csv")),
    article_candidate_gate_table_csv = app_joint_qdesn_phase123_write_csv(gate_table, file.path(out_dir, "article_candidate_gate_table.csv")),
    article_candidate_model_table_tex = app_joint_qdesn_phase123_write_latex_table(
      model_table,
      file.path(out_dir, "article_candidate_mcmc_model_table.tex"),
      "Case-specific MCMC confirmation summary for the joint multi-quantile validation study. Metrics are averaged only over the Phase122-confirmed case-specific winners for each row, so the table should not be read as a balanced four-model comparison over a common scenario set.",
      "tab:joint-qdesn-phase123-mcmc-model-table",
      align = "@{}>{\\raggedright\\arraybackslash}p{0.22\\textwidth}rrrrrrrl@{}",
      resize = TRUE
    ),
    article_candidate_case_table_tex = app_joint_qdesn_phase123_write_latex_table(
      case_table,
      file.path(out_dir, "article_candidate_mcmc_case_table.tex"),
      "Scenario-level MCMC confirmation diagnostics for the frozen case-specific joint QDESN validation winners. Reported scores use monotone contract quantiles; raw crossings are retained as diagnostics.",
      "tab:joint-qdesn-phase123-mcmc-case-table",
      align = "@{}>{\\raggedright\\arraybackslash}p{0.20\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}rrrrrl@{}",
      resize = TRUE
    ),
    article_candidate_gate_table_tex = app_joint_qdesn_phase123_write_latex_table(
      gate_table,
      file.path(out_dir, "article_candidate_mcmc_gate_table.tex"),
      "Phase123 validation gates for the MCMC article-candidate evidence packet.",
      "tab:joint-qdesn-phase123-gate-table",
      align = "@{}>{\\raggedright\\arraybackslash}p{0.26\\textwidth}l>{\\raggedright\\arraybackslash}p{0.56\\textwidth}@{}",
      resize = TRUE
    ),
    article_promotion_recommendation = app_joint_qdesn_phase123_write_csv(recommendation, file.path(out_dir, "article_promotion_recommendation.csv")),
    article_integration_plan = app_joint_qdesn_phase123_write_csv(integration_plan, file.path(out_dir, "article_integration_plan.csv")),
    provenance = app_joint_qdesn_phase123_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
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
    recommendation = recommendation
  )
}
