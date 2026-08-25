#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_exqdesn_trace_tools.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase133_performance_first_audit_20260714",
  phase125_dir = "application/cache/joint_qdesn_phase125_balanced_mcmc_audit_20260712",
  phase126_dir = "application/cache/joint_qdesn_phase126_article_assets_20260712",
  phase129_dir = "application/cache/joint_qdesn_phase129_joint_exqdesn_gamma_width4_packet_20260713",
  phase130_dir = "application/cache/joint_qdesn_phase130_joint_exqdesn_targeted_long_chains_20260713",
  phase131_dir = "application/cache/joint_qdesn_phase131_nonlinear_tau025_sampler_tuning_20260713",
  phase132_dir = "application/cache/joint_qdesn_phase132_nonlinear_tau025_width8_long_confirmation_20260714",
  joint_exqdesn_model_label = "Joint exQDESN RHS",
  large_gap_threshold = "0.025",
  moderate_gap_threshold = "0.005",
  rhat_review_threshold = "1.20",
  qhat_distance_review_threshold = "0.05",
  chain_qhat_distance_review_threshold = "0.10"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

parse_number <- function(x) {
  out <- suppressWarnings(as.numeric(as.character(x)[[1L]]))
  if (!is.finite(out)) stop(sprintf("Expected finite numeric value, got '%s'.", x), call. = FALSE)
  out
}

read_csv_if_exists <- function(path) {
  if (!file.exists(path)) return(data.frame())
  app_read_csv(path)
}

verify_manifest <- function(dir, source_label) {
  manifest_path <- file.path(dir, "artifact_manifest.csv")
  if (!dir.exists(dir)) {
    return(data.frame(
      source_label = source_label,
      source_dir = dir,
      manifest_exists = FALSE,
      n_manifest_rows = 0L,
      n_hash_pass = 0L,
      n_hash_fail = 0L,
      status = "missing_source_dir",
      stringsAsFactors = FALSE
    ))
  }
  if (!file.exists(manifest_path)) {
    return(data.frame(
      source_label = source_label,
      source_dir = dir,
      manifest_exists = FALSE,
      n_manifest_rows = 0L,
      n_hash_pass = 0L,
      n_hash_fail = 0L,
      status = "missing_manifest",
      stringsAsFactors = FALSE
    ))
  }
  manifest <- app_read_csv(manifest_path)
  if (!all(c("relative_path", "sha256") %in% names(manifest))) {
    return(data.frame(
      source_label = source_label,
      source_dir = dir,
      manifest_exists = TRUE,
      n_manifest_rows = nrow(manifest),
      n_hash_pass = 0L,
      n_hash_fail = nrow(manifest),
      status = "malformed_manifest",
      stringsAsFactors = FALSE
    ))
  }
  actual <- vapply(manifest$relative_path, function(rel) {
    path <- file.path(dir, rel)
    if (!file.exists(path)) return(NA_character_)
    app_sha256_file(path)
  }, character(1L))
  ok <- !is.na(actual) & actual == manifest$sha256
  data.frame(
    source_label = source_label,
    source_dir = dir,
    manifest_exists = TRUE,
    n_manifest_rows = nrow(manifest),
    n_hash_pass = sum(ok),
    n_hash_fail = sum(!ok),
    status = if (all(ok)) "pass" else "fail",
    stringsAsFactors = FALSE
  )
}

latest_by_scenario <- function(rows) {
  if (!nrow(rows)) return(rows)
  phase_rank <- c(phase129 = 1L, phase130 = 2L, phase132 = 3L)
  rows$phase_rank <- unname(phase_rank[rows$source_phase])
  rows <- rows[order(rows$scenario_id, -rows$phase_rank), , drop = FALSE]
  rows[!duplicated(rows$scenario_id), setdiff(names(rows), "phase_rank"), drop = FALSE]
}

metric_rank_rows <- function(case_table, metric_name) {
  x <- case_table[is.finite(case_table[[metric_name]]), , drop = FALSE]
  if (!nrow(x)) return(data.frame())
  pieces <- lapply(split(x, x$scenario_id), function(block) {
    block <- block[order(block[[metric_name]], block$model_label), , drop = FALSE]
    best <- block[1L, , drop = FALSE]
    block$rank <- seq_len(nrow(block))
    block$best_model_label <- best$model_label[[1L]]
    block$best_value <- best[[metric_name]][[1L]]
    block$gap_to_best <- block[[metric_name]] - best[[metric_name]][[1L]]
    block
  })
  out <- app_bind_rows_fill(pieces)
  out$metric <- metric_name
  out
}

aggregate_aux_metrics <- function(phase125_dir) {
  crps <- read_csv_if_exists(file.path(phase125_dir, "forecast_crps_grid_summary.csv"))
  hit <- read_csv_if_exists(file.path(phase125_dir, "forecast_hit_rate_summary.csv"))
  interval <- read_csv_if_exists(file.path(phase125_dir, "forecast_interval_summary.csv"))
  crps_mcmc <- crps[grepl("_mcmc$", crps$model_id), , drop = FALSE]
  hit_mcmc <- hit[grepl("_mcmc$", hit$model_id), , drop = FALSE]
  interval_mcmc <- interval[grepl("_mcmc$", interval$model_id), , drop = FALSE]
  crps_agg <- if (nrow(crps_mcmc)) {
    stats::aggregate(crps_grid_mean ~ scenario_id + model_id, crps_mcmc, mean, na.rm = TRUE)
  } else {
    data.frame()
  }
  hit_agg <- if (nrow(hit_mcmc)) {
    stats::aggregate(abs_hit_rate_error ~ scenario_id + model_id, hit_mcmc, mean, na.rm = TRUE)
  } else {
    data.frame()
  }
  interval_agg <- if (nrow(interval_mcmc)) {
    stats::aggregate(abs_coverage_error ~ scenario_id + model_id, interval_mcmc, mean, na.rm = TRUE)
  } else {
    data.frame()
  }
  Reduce(function(a, b) merge(a, b, by = c("scenario_id", "model_id"), all = TRUE),
         list(crps_agg, hit_agg, interval_agg))
}

build_performance_gap_audit <- function(phase125_dir, target_label, moderate_gap, large_gap) {
  case_table <- app_read_csv(file.path(phase125_dir, "scenario_model_confirmation_summary.csv"))
  aux <- aggregate_aux_metrics(phase125_dir)
  ranks <- metric_rank_rows(case_table, "mcmc_forecast_truth_mae")
  target <- ranks[ranks$model_label == target_label, , drop = FALSE]
  if (!nrow(target)) stop(sprintf("No rows found for target model label '%s'.", target_label), call. = FALSE)
  fit_ranks <- metric_rank_rows(case_table, "mcmc_fit_truth_mae")
  check_ranks <- metric_rank_rows(case_table, "mcmc_forecast_check_loss_mean")
  fit_target <- fit_ranks[fit_ranks$model_label == target_label, c("scenario_id", "rank", "gap_to_best", "best_model_label", "best_value"), drop = FALSE]
  names(fit_target) <- c("scenario_id", "fit_mae_rank", "fit_mae_gap_to_best", "fit_mae_winner", "fit_mae_winner_value")
  check_target <- check_ranks[check_ranks$model_label == target_label, c("scenario_id", "rank", "gap_to_best", "best_model_label", "best_value"), drop = FALSE]
  names(check_target) <- c("scenario_id", "check_loss_rank", "check_loss_gap_to_best", "check_loss_winner", "check_loss_winner_value")
  out <- target[, c(
    "scenario_id", "scenario_label", "scenario_class", "distribution_family", "dynamics_class",
    "source_model_id", "model_id", "model_label", "likelihood", "fit_structure", "gate_status",
    "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae", "mcmc_forecast_check_loss_mean",
    "mcmc_forecast_raw_crossing_pairs", "mcmc_forecast_contract_crossing_pairs",
    "vb_mcmc_max_normalized_distance", "max_chain_to_pooled_normalized_distance",
    "rank", "best_model_label", "best_value", "gap_to_best"
  ), drop = FALSE]
  names(out)[names(out) == "rank"] <- "forecast_mae_rank"
  names(out)[names(out) == "best_model_label"] <- "forecast_mae_winner"
  names(out)[names(out) == "best_value"] <- "forecast_mae_winner_value"
  names(out)[names(out) == "gap_to_best"] <- "forecast_mae_gap_to_best"
  out <- merge(out, fit_target, by = "scenario_id", all.x = TRUE)
  out <- merge(out, check_target, by = "scenario_id", all.x = TRUE)
  out <- merge(out, aux, by = c("scenario_id", "model_id"), all.x = TRUE)
  out$performance_gap_class <- ifelse(
    out$forecast_mae_gap_to_best >= large_gap, "large_gap",
    ifelse(out$forecast_mae_gap_to_best >= moderate_gap, "moderate_gap", "near_winner")
  )
  out$performance_gate <- ifelse(out$performance_gap_class == "large_gap", "review", "pass")
  out[order(-out$forecast_mae_gap_to_best), , drop = FALSE]
}

build_model_context <- function(phase125_dir) {
  model <- app_read_csv(file.path(phase125_dir, "model_confirmation_summary.csv"))
  model[, c(
    "model_label", "likelihood", "fit_structure", "n_cases", "n_pass", "n_review", "n_fail",
    "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae", "mcmc_forecast_check_loss",
    "mcmc_forecast_crps_grid", "mcmc_abs_hit_rate_error", "mcmc_abs_coverage_error",
    "mcmc_forecast_raw_crossing_pairs", "mcmc_forecast_contract_crossing_pairs",
    "vb_mcmc_max_normalized_distance", "max_chain_to_pooled_normalized_distance",
    "gate_status"
  ), drop = FALSE]
}

read_sampler_phase <- function(dir, source_phase) {
  case_assessment <- read_csv_if_exists(file.path(dir, "case_assessment.csv"))
  if (!nrow(case_assessment)) return(data.frame())
  distance <- read_csv_if_exists(file.path(dir, "vb_mcmc_distance_summary.csv"))
  chain <- read_csv_if_exists(file.path(dir, "chain_to_pooled_distance_summary.csv"))
  runtime <- read_csv_if_exists(file.path(dir, "runtime_summary.csv"))
  rhat <- read_csv_if_exists(file.path(dir, "mcmc_rhat_ess_summary.csv"))
  worst_tau <- if (nrow(rhat)) {
    pieces <- lapply(split(rhat[rhat$parameter %in% c("gamma", "sigma"), , drop = FALSE], rhat$scenario_id), function(block) {
      block[which.max(block$rhat), c("scenario_id", "tau", "parameter", "rhat"), drop = FALSE]
    })
    out <- app_bind_rows_fill(pieces)
    names(out) <- c("scenario_id", "worst_tau", "worst_parameter", "worst_parameter_rhat")
    out
  } else {
    data.frame()
  }
  chain_agg <- if (nrow(chain)) {
    stats::aggregate(qhat_normalized_to_pooled ~ scenario_id, chain, max, na.rm = TRUE)
  } else {
    data.frame()
  }
  names(chain_agg)[names(chain_agg) == "qhat_normalized_to_pooled"] <- "max_chain_qhat_normalized_to_pooled"
  runtime_agg <- if (nrow(runtime) && "runtime_component" %in% names(runtime)) {
    chain_rows <- runtime[runtime$runtime_component == "mcmc_chain", , drop = FALSE]
    if (nrow(chain_rows)) {
      stats::aggregate(elapsed_seconds ~ scenario_id, chain_rows, mean, na.rm = TRUE)
    } else data.frame()
  } else data.frame()
  names(runtime_agg)[names(runtime_agg) == "elapsed_seconds"] <- "mean_chain_elapsed_seconds"
  dist_cols <- intersect(c("scenario_id", "qhat_normalized_distance", "gamma_normalized_distance", "sigma_normalized_distance", "max_normalized_distance"), names(distance))
  distance <- distance[, dist_cols, drop = FALSE]
  out <- case_assessment
  out <- merge(out, distance, by = "scenario_id", all.x = TRUE)
  out <- merge(out, chain_agg, by = "scenario_id", all.x = TRUE)
  out <- merge(out, runtime_agg, by = "scenario_id", all.x = TRUE)
  out <- merge(out, worst_tau, by = "scenario_id", all.x = TRUE)
  out$source_phase <- source_phase
  out$source_dir <- dir
  out
}

build_sampler_audit <- function(phase129_dir, phase130_dir, phase132_dir, rhat_review, qhat_review, chain_qhat_review) {
  rows <- app_bind_rows_fill(list(
    read_sampler_phase(phase129_dir, "phase129"),
    read_sampler_phase(phase130_dir, "phase130"),
    read_sampler_phase(phase132_dir, "phase132")
  ))
  if (!nrow(rows)) return(rows)
  rows$sampler_rhat_gate <- ifelse(is.finite(rows$max_rhat) & rows$max_rhat <= rhat_review, "pass", "review")
  rows$qhat_vb_mcmc_gate <- ifelse(
    is.finite(rows$qhat_normalized_distance) & rows$qhat_normalized_distance <= qhat_review,
    "pass", "review"
  )
  rows$chain_qhat_gate <- ifelse(
    is.finite(rows$max_chain_qhat_normalized_to_pooled) &
      rows$max_chain_qhat_normalized_to_pooled <= chain_qhat_review,
    "pass", "review"
  )
  rows$gamma_parameter_gate <- ifelse(
    is.finite(rows$max_gamma_rhat) & rows$max_gamma_rhat <= rhat_review,
    "pass", "review"
  )
  rows$sampler_interpretation <- ifelse(
    rows$gamma_parameter_gate == "review" & rows$qhat_vb_mcmc_gate == "pass",
    "parameter_level_review_but_quantile_grid_stable",
    ifelse(rows$qhat_vb_mcmc_gate == "review" | rows$chain_qhat_gate == "review",
           "quantile_grid_stability_review", "sampler_support_pass")
  )
  rows
}

build_priority_table <- function(performance, sampler_latest, moderate_gap, large_gap, rhat_review) {
  perf_cols <- c(
    "scenario_id", "scenario_label", "scenario_class", "distribution_family", "dynamics_class",
    "mcmc_forecast_truth_mae", "forecast_mae_winner", "forecast_mae_winner_value",
    "forecast_mae_gap_to_best", "forecast_mae_rank", "performance_gap_class",
    "mcmc_forecast_check_loss_mean", "crps_grid_mean", "abs_hit_rate_error",
    "abs_coverage_error", "mcmc_forecast_raw_crossing_pairs",
    "mcmc_forecast_contract_crossing_pairs"
  )
  out <- performance[, intersect(perf_cols, names(performance)), drop = FALSE]
  sampler_cols <- c(
    "scenario_id", "source_phase", "case_gate_status", "max_rhat", "max_gamma_rhat",
    "min_rough_ess_total", "max_gamma_chain_mean_gap", "max_gamma_lag1_autocorrelation",
    "qhat_normalized_distance", "gamma_normalized_distance", "max_chain_qhat_normalized_to_pooled",
    "worst_tau", "worst_parameter", "sampler_interpretation", "mean_chain_elapsed_seconds"
  )
  out <- merge(out, sampler_latest[, intersect(sampler_cols, names(sampler_latest)), drop = FALSE], by = "scenario_id", all.x = TRUE)
  out$performance_priority <- ifelse(
    out$forecast_mae_gap_to_best >= large_gap, "high",
    ifelse(out$forecast_mae_gap_to_best >= moderate_gap, "medium", "low")
  )
  out$sampler_priority <- ifelse(
    is.finite(out$max_rhat) & out$max_rhat > rhat_review, "high",
    ifelse(grepl("quantile_grid_stability_review", out$sampler_interpretation %||% ""), "medium", "low")
  )
  out$primary_diagnosis <- ifelse(
    out$performance_priority == "high" & out$sampler_priority == "high",
    "performance_gap_with_sampler_ridge",
    ifelse(out$performance_priority == "high",
           "performance_gap_likely_specification_or_summary",
           ifelse(out$sampler_priority == "high",
                  "sampler_support_issue_but_performance_gap_smaller",
                  "lower_priority_monitor"))
  )
  out$recommended_next_action <- ifelse(
    out$primary_diagnosis == "performance_gap_with_sampler_ridge",
    "run_scored_sampler_geometry_and_exal_spec_screen",
    ifelse(out$primary_diagnosis == "performance_gap_likely_specification_or_summary",
           "run_posterior_summary_sensitivity_then_exal_spec_screen",
           ifelse(out$primary_diagnosis == "sampler_support_issue_but_performance_gap_smaller",
                  "run_bounded_sampler_efficiency_check_only_if_mcmc_cost_blocks_confirmation",
                  "retain_current_setting_and_monitor"))
  )
  out$priority_score <- 100 * pmax(0, out$forecast_mae_gap_to_best) +
    ifelse(out$sampler_priority == "high", 1, ifelse(out$sampler_priority == "medium", 0.5, 0))
  out[order(-out$priority_score), , drop = FALSE]
}

build_decision_matrix <- function(priority) {
  data.frame(
    decision_area = c(
      "promotion_gate",
      "mixing_role",
      "phase132_replacement",
      "posterior_summary",
      "next_expensive_runs",
      "article_table_policy"
    ),
    decision = c(
      "Use quantile-grid performance and qhat stability before parameter-level gamma diagnostics.",
      "Treat gamma/tau/sigma Rhat as support diagnostics unless qhat stability or forecast scores are harmed.",
      "Do not replace article rows from Phase132 alone because Phase132 is a sampler-diagnostic packet without full score tables.",
      "Add posterior mean-vs-median qhat sensitivity before judging exAL performance as a model failure.",
      "Prioritize high-gap scenarios; combine sampler geometry with exAL specification screening only where both are implicated.",
      "Do not update article tables until a scored, manifest-audited balanced MCMC packet is complete."
    ),
    evidence = c(
      "Joint exQDESN has zero raw/contract forecast crossings but worse forecast MAE than AL competitors.",
      "Phase132 nonlinear gamma distance is large while qhat VB-MCMC distance is small.",
      "Phase132 contains Rhat/ESS/trace summaries but no forecast truth/check/CRPS score tables.",
      "Sticky or skewed gamma can affect posterior means more than medians; existing summaries do not decide this.",
      paste(priority$scenario_id[seq_len(min(5L, nrow(priority)))], collapse = ", "),
      "Current article table should remain tied to Phase125/126 until the next scored confirmation layer exists."
    ),
    gate = c("review", "review", "review", "review", "pass", "pass"),
    stringsAsFactors = FALSE
  )
}

build_posterior_summary_readiness <- function(source_dirs) {
  rows <- lapply(names(source_dirs), function(label) {
    dir <- source_dirs[[label]]
    files <- list.files(dir, pattern = "(qhat|quantile).*draw|draw.*qhat|fit_quantiles|forecast_quantiles", full.names = FALSE)
    data.frame(
      source_phase = label,
      source_dir = dir,
      qhat_draw_files_detected = length(files),
      detected_files = paste(files, collapse = ";"),
      readiness = if (length(files)) "possible_from_existing_artifact" else "requires_scored_or_draw_level_rerun",
      recommendation = if (length(files)) {
        "compute_mean_median_trimmed_qhat_sensitivity_from_existing_files"
      } else {
        "rerun_selected_cases_with_qhat_draw_summary_or_extend_mcmc_runner_to_emit_draw_level_qhat_summaries"
      },
      stringsAsFactors = FALSE
    )
  })
  app_bind_rows_fill(rows)
}

build_phase132_replacement_readiness <- function(performance, sampler_latest) {
  nonlinear <- performance[performance$scenario_id == "nonlinear_reservoir_friendly", , drop = FALSE]
  phase132 <- sampler_latest[sampler_latest$scenario_id == "nonlinear_reservoir_friendly", , drop = FALSE]
  data.frame(
    scenario_id = "nonlinear_reservoir_friendly",
    current_phase125_joint_exqdesn_forecast_mae = if (nrow(nonlinear)) nonlinear$mcmc_forecast_truth_mae[[1L]] else NA_real_,
    current_phase125_gap_to_best = if (nrow(nonlinear)) nonlinear$forecast_mae_gap_to_best[[1L]] else NA_real_,
    phase132_max_rhat = if (nrow(phase132)) phase132$max_rhat[[1L]] else NA_real_,
    phase132_gamma_rhat = if (nrow(phase132)) phase132$max_gamma_rhat[[1L]] else NA_real_,
    phase132_qhat_vb_mcmc_distance = if (nrow(phase132)) phase132$qhat_normalized_distance[[1L]] else NA_real_,
    phase132_has_full_score_tables = FALSE,
    replacement_status = "not_promotable_from_phase132_alone",
    required_next_step = "run_or_extend_a_scored_mcmc_confirmation_for_the_width8_tau025_policy_before_replacing_article_metrics",
    stringsAsFactors = FALSE
  )
}

build_next_plan <- function(priority) {
  high_scenarios <- priority$scenario_id[priority$performance_priority == "high"]
  high_scenarios <- paste(high_scenarios, collapse = ",")
  data.frame(
    step_order = seq_len(6L),
    phase_label = c("Phase133A", "Phase133B", "Phase134", "Phase135", "Phase136", "Phase137"),
    objective = c(
      "Freeze this performance-first audit as the experiment control plane.",
      "Implement posterior mean/median/trimmed qhat sensitivity for selected existing or rerun MCMC outputs.",
      "Run scenario-specific exAL specification screens for high-gap cases.",
      "Run sampler-geometry pilots only for cases where sampler support is implicated.",
      "Launch scored scenario-specific MCMC confirmations from selected VB/VB-LD winners.",
      "Build a balanced article packet only after scored MCMC confirmation passes reproducibility gates."
    ),
    target_scenarios = c(
      "all eight",
      high_scenarios,
      high_scenarios,
      "nonlinear_reservoir_friendly first; student_t_location_scale only if needed",
      "one selected winner per scenario/model class",
      "all article-facing rows"
    ),
    implementation_notes = c(
      "Read-only audit; no article mutation.",
      "Prefer qhat summary files over raw RData; rerun only selected cases if summaries are unavailable.",
      "Do not force a universal specification; optimize per case.",
      "Test transformed gamma and occasional joint gamma/log-sigma moves; use ESS per qhat stability per hour.",
      "Use fixed seeds, manifests, provenance, and no article mutation.",
      "Update manuscript assets only after hard gates, qhat stability, and score gates pass."
    ),
    launch_now = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
    gate_before_launch = c(
      "complete",
      "confirm qhat summaries are available or implement compact qhat draw summaries",
      "Phase133B identifies summary-vs-specification failure mode",
      "Phase133 priority table flags sampler ridge as material",
      "VB/VB-LD winners selected and frozen",
      "MCMC confirmations complete and audited"
    ),
    stringsAsFactors = FALSE
  )
}

build_assessment <- function(manifest_audit, performance, priority, posterior_readiness) {
  hard_fail <- any(manifest_audit$status %in% c("fail", "missing_manifest", "malformed_manifest", "missing_source_dir"))
  large_gap_n <- sum(performance$performance_gap_class == "large_gap", na.rm = TRUE)
  qhat_rerun_needed <- any(posterior_readiness$readiness == "requires_scored_or_draw_level_rerun")
  data.frame(
    audit_gate = if (hard_fail) "fail" else "review",
    implementation_gate = if (hard_fail) "fail" else "pass",
    n_large_performance_gaps = large_gap_n,
    n_high_priority_scenarios = sum(priority$performance_priority == "high" | priority$sampler_priority == "high", na.rm = TRUE),
    posterior_summary_sensitivity_status = if (qhat_rerun_needed) "requires_runner_extension_or_selected_rerun" else "available_from_existing_artifacts",
    article_update_recommendation = "do_not_update_article_until_scored_candidate_packet_exists",
    next_stage_recommendation = "implement_phase133B_qhat_summary_sensitivity_then_targeted_exal_spec_and_sampler_screens",
    status_reason = if (hard_fail) {
      "At least one source manifest failed; repair source artifacts before inference decisions."
    } else {
      "Source manifests verify, but Joint exQDESN has large performance gaps and posterior qhat summary sensitivity is not yet resolved."
    },
    stringsAsFactors = FALSE
  )
}

out_dir <- resolve_path(arg_value("output_dir"), must_work = FALSE)
app_ensure_dir(out_dir)

source_dirs <- c(
  phase125 = resolve_path(arg_value("phase125_dir"), must_work = FALSE),
  phase126 = resolve_path(arg_value("phase126_dir"), must_work = FALSE),
  phase129 = resolve_path(arg_value("phase129_dir"), must_work = FALSE),
  phase130 = resolve_path(arg_value("phase130_dir"), must_work = FALSE),
  phase131 = resolve_path(arg_value("phase131_dir"), must_work = FALSE),
  phase132 = resolve_path(arg_value("phase132_dir"), must_work = FALSE)
)

moderate_gap <- parse_number(arg_value("moderate_gap_threshold"))
large_gap <- parse_number(arg_value("large_gap_threshold"))
rhat_review <- parse_number(arg_value("rhat_review_threshold"))
qhat_review <- parse_number(arg_value("qhat_distance_review_threshold"))
chain_qhat_review <- parse_number(arg_value("chain_qhat_distance_review_threshold"))
target_label <- as.character(arg_value("joint_exqdesn_model_label"))[[1L]]

run_config <- data.frame(
  run_id = "joint_qdesn_phase133_performance_first_audit",
  output_dir = out_dir,
  target_model_label = target_label,
  moderate_gap_threshold = moderate_gap,
  large_gap_threshold = large_gap,
  rhat_review_threshold = rhat_review,
  qhat_distance_review_threshold = qhat_review,
  chain_qhat_distance_review_threshold = chain_qhat_review,
  phase125_dir = source_dirs[["phase125"]],
  phase126_dir = source_dirs[["phase126"]],
  phase129_dir = source_dirs[["phase129"]],
  phase130_dir = source_dirs[["phase130"]],
  phase131_dir = source_dirs[["phase131"]],
  phase132_dir = source_dirs[["phase132"]],
  validation_contract = "performance_first_quantile_grid_audit_no_article_mutation",
  stringsAsFactors = FALSE
)

manifest_audit <- app_bind_rows_fill(Map(verify_manifest, source_dirs, names(source_dirs)))
performance <- build_performance_gap_audit(source_dirs[["phase125"]], target_label, moderate_gap, large_gap)
model_context <- build_model_context(source_dirs[["phase125"]])
sampler_all <- build_sampler_audit(
  source_dirs[["phase129"]],
  source_dirs[["phase130"]],
  source_dirs[["phase132"]],
  rhat_review,
  qhat_review,
  chain_qhat_review
)
sampler_latest <- latest_by_scenario(sampler_all)
priority <- build_priority_table(performance, sampler_latest, moderate_gap, large_gap, rhat_review)
decision_matrix <- build_decision_matrix(priority)
posterior_readiness <- build_posterior_summary_readiness(source_dirs[c("phase125", "phase129", "phase130", "phase132")])
phase132_readiness <- build_phase132_replacement_readiness(performance, sampler_latest)
next_plan <- build_next_plan(priority)
assessment <- build_assessment(manifest_audit, performance, priority, posterior_readiness)

readme <- c(
  "# Joint exQDESN Phase133 Performance-First Audit",
  "",
  "This artifact audits the completed balanced MCMC validation and recent Joint exQDESN sampler diagnostics under a performance-first policy.",
  "It does not mutate article tables, figures, manuscript text, or prior cache artifacts.",
  "",
  "## Main conclusion",
  "",
  "Gamma/tau/sigma mixing is treated as a support diagnostic. The primary promotion criteria are quantile-grid fit and forecast metrics, qhat stability, and crossing behavior.",
  "",
  sprintf("- Target model: `%s`", target_label),
  sprintf("- Large forecast-MAE gap threshold: `%s`", large_gap),
  sprintf("- Moderate forecast-MAE gap threshold: `%s`", moderate_gap),
  sprintf("- Source manifest status: `%s`", if (all(manifest_audit$status == "pass")) "pass" else "review/fail"),
  sprintf("- Audit gate: `%s`", assessment$audit_gate[[1L]]),
  sprintf("- Next stage: `%s`", assessment$next_stage_recommendation[[1L]]),
  "",
  "## Generated tables",
  "",
  "- `source_manifest_audit.csv`: source artifact hash verification.",
  "- `joint_exqdesn_model_performance_context.csv`: model-level balanced MCMC context.",
  "- `joint_exqdesn_performance_gap_audit.csv`: scenario-level target-model performance gaps.",
  "- `joint_exqdesn_sampler_vs_qhat_stability_audit.csv`: all available sampler diagnostic phases.",
  "- `joint_exqdesn_latest_sampler_state.csv`: latest sampler diagnostic per scenario.",
  "- `joint_exqdesn_scenario_priority_table.csv`: merged performance/sampler priority ranking.",
  "- `posterior_summary_sensitivity_readiness.csv`: whether existing artifacts can support mean-vs-median qhat sensitivity.",
  "- `phase132_replacement_readiness.csv`: why Phase132 cannot by itself replace article metrics.",
  "- `joint_exqdesn_next_experiment_plan.csv`: recommended implementation sequence.",
  "- `audit_assessment.csv`: pass/review/fail summary.",
  "",
  "## Important limitation",
  "",
  "Phase132 is a sampler-diagnostic packet. It improves the nonlinear tau-0.25 sampler diagnostics but does not include the full fit/forecast scoring tables required for article replacement."
)

paths <- c(
  run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
  source_manifest_audit = app_joint_qvp_write_csv(manifest_audit, file.path(out_dir, "source_manifest_audit.csv")),
  joint_exqdesn_model_performance_context = app_joint_qvp_write_csv(model_context, file.path(out_dir, "joint_exqdesn_model_performance_context.csv")),
  joint_exqdesn_performance_gap_audit = app_joint_qvp_write_csv(performance, file.path(out_dir, "joint_exqdesn_performance_gap_audit.csv")),
  joint_exqdesn_sampler_vs_qhat_stability_audit = app_joint_qvp_write_csv(sampler_all, file.path(out_dir, "joint_exqdesn_sampler_vs_qhat_stability_audit.csv")),
  joint_exqdesn_latest_sampler_state = app_joint_qvp_write_csv(sampler_latest, file.path(out_dir, "joint_exqdesn_latest_sampler_state.csv")),
  joint_exqdesn_scenario_priority_table = app_joint_qvp_write_csv(priority, file.path(out_dir, "joint_exqdesn_scenario_priority_table.csv")),
  joint_exqdesn_stage_decision_matrix = app_joint_qvp_write_csv(decision_matrix, file.path(out_dir, "joint_exqdesn_stage_decision_matrix.csv")),
  posterior_summary_sensitivity_readiness = app_joint_qvp_write_csv(posterior_readiness, file.path(out_dir, "posterior_summary_sensitivity_readiness.csv")),
  phase132_replacement_readiness = app_joint_qvp_write_csv(phase132_readiness, file.path(out_dir, "phase132_replacement_readiness.csv")),
  joint_exqdesn_next_experiment_plan = app_joint_qvp_write_csv(next_plan, file.path(out_dir, "joint_exqdesn_next_experiment_plan.csv")),
  audit_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "audit_assessment.csv")),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = {
    path <- file.path(out_dir, "README.md")
    writeLines(readme, path)
    path
  }
)
manifest_info <- app_joint_exqdesn_trace_manifest(paths, out_dir)

cat(sprintf("Phase133 performance-first audit written to %s\n", out_dir))
cat(sprintf("Audit gate: %s\n", assessment$audit_gate[[1L]]))
cat(sprintf("Implementation gate: %s\n", assessment$implementation_gate[[1L]]))
cat(sprintf("Large performance gaps: %s\n", assessment$n_large_performance_gaps[[1L]]))
cat(sprintf("Artifact manifest: %s\n", manifest_info$manifest_path))
