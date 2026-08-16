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

args <- app_parse_args(list(
  baseline_dir = "application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_20260702",
  followup_dir = "",
  baseline_audit_dir = "",
  followup_audit_dir = "",
  output_dir = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

read_required <- function(dir, filename) {
  path <- file.path(dir, filename)
  if (!file.exists(path)) stop(sprintf("Missing required Phase 4e audit input: %s", path), call. = FALSE)
  utils::read.csv(path, stringsAsFactors = FALSE)
}

summarize_scenarios <- function(phase3_dir, scenario_ids) {
  raw <- read_required(phase3_dir, "raw_crossing_summary.csv")
  contract <- read_required(phase3_dir, "crossing_summary.csv")
  adjust <- read_required(phase3_dir, "forecast_monotone_adjustment.csv")
  vb <- read_required(phase3_dir, "vb_convergence_audit.csv")
  runtime <- read_required(phase3_dir, "runtime_summary.csv")
  assessment <- read_required(phase3_dir, "forecast_validation_assessment.csv")

  rows <- lapply(scenario_ids, function(id) {
    r <- raw[raw$scenario_id == id, , drop = FALSE]
    c <- contract[contract$scenario_id == id, , drop = FALSE]
    a <- adjust[adjust$scenario_id == id, , drop = FALSE]
    v <- vb[vb$scenario_id == id & app_as_bool_vec(vb$refit), , drop = FALSE]
    t <- runtime[runtime$scenario_id == id, , drop = FALSE]
    s <- assessment[assessment$scenario_id == id, , drop = FALSE]
    data.frame(
      scenario_id = id,
      gate_status = if (nrow(s)) s$gate_status[[1L]] else NA_character_,
      implementation_status = if (nrow(s)) s$implementation_status[[1L]] else NA_character_,
      truth_normalized_qhat_distance = if (nrow(s)) s$truth_normalized_qhat_distance[[1L]] else NA_real_,
      max_abs_hit_rate_error = if (nrow(s)) s$max_abs_hit_rate_error[[1L]] else NA_real_,
      contract_crossing_pairs = if (nrow(c)) sum(c$n_crossing_pairs, na.rm = TRUE) else NA_real_,
      raw_crossing_pairs = if (nrow(r)) sum(r$n_crossing_pairs, na.rm = TRUE) else NA_real_,
      raw_crossing_origins = if (nrow(r)) sum(r$n_crossing_pairs > 0L, na.rm = TRUE) else NA_real_,
      raw_max_crossing_magnitude = if (nrow(r)) max(r$max_crossing_magnitude, na.rm = TRUE) else NA_real_,
      monotone_adjusted_origins = if (nrow(a)) sum(a$n_adjusted_quantiles > 0L, na.rm = TRUE) else NA_real_,
      monotone_adjusted_quantiles = if (nrow(a)) sum(a$n_adjusted_quantiles, na.rm = TRUE) else NA_real_,
      max_monotone_adjustment = if (nrow(a)) max(a$max_abs_adjustment, na.rm = TRUE) else NA_real_,
      vb_refit_count = nrow(v),
      vb_max_iter_count = if (nrow(v)) sum(as.character(v$status) != "prototype_success", na.rm = TRUE) else NA_real_,
      vb_max_iter_rate = if (nrow(v)) mean(as.character(v$status) != "prototype_success", na.rm = TRUE) else NA_real_,
      vb_max_n_iter = if (nrow(v)) max(v$n_iter, na.rm = TRUE) else NA_real_,
      runtime_total_sec = if (nrow(t)) sum(t$elapsed_sec, na.rm = TRUE) else NA_real_,
      runtime_max_sec = if (nrow(t)) max(t$elapsed_sec, na.rm = TRUE) else NA_real_,
      note = if (nrow(s)) s$note[[1L]] else NA_character_,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

prefix_cols <- function(x, prefix, key = "scenario_id") {
  names(x)[names(x) != key] <- paste0(prefix, names(x)[names(x) != key])
  x
}

phase4e_readme <- function(overall, recommendation) {
  c(
    "# Joint-QVP Phase 4e Raw-Crossing/VB Follow-Up Audit",
    "",
    "This artifact compares the full Phase 4 contract calibration baseline against a targeted stronger-VB rerun over the replicated scenario rows that produced raw forecast crossings.",
    "It does not rerun the full calibration campaign and does not change article outputs.",
    "",
    sprintf("- Baseline raw crossing pairs: %s", overall$baseline_raw_crossing_pairs[[1L]]),
    sprintf("- Follow-up raw crossing pairs: %s", overall$followup_raw_crossing_pairs[[1L]]),
    sprintf("- Baseline contract crossing pairs: %s", overall$baseline_contract_crossing_pairs[[1L]]),
    sprintf("- Follow-up contract crossing pairs: %s", overall$followup_contract_crossing_pairs[[1L]]),
    sprintf("- Baseline VB max-iteration rate: %.3f", overall$baseline_vb_max_iter_rate[[1L]]),
    sprintf("- Follow-up VB max-iteration rate: %.3f", overall$followup_vb_max_iter_rate[[1L]]),
    sprintf("- Recommendation: %s", recommendation$recommendation_status[[1L]]),
    "",
    "Primary files:",
    "",
    "- `phase4e_before_after_overall_summary.csv`: one-row baseline/follow-up comparison.",
    "- `phase4e_before_after_scenario_comparison.csv`: scenario-level raw crossing, monotone adjustment, VB, and runtime deltas.",
    "- `phase4e_crossing_origin_set_comparison.csv`: crossing-pair set overlap between baseline and follow-up.",
    "- `phase4e_vb_runtime_comparison.csv`: compact VB/runtime deltas.",
    "- `phase4e_recommendation.csv`: conservative decision row.",
    "- `artifact_manifest.csv`: SHA-256 hashes."
  )
}

baseline_dir <- normalizePath(as.character(arg_value("baseline_dir"))[[1L]], mustWork = TRUE)
followup_dir <- if (nzchar(as.character(arg_value("followup_dir")))) {
  normalizePath(as.character(arg_value("followup_dir"))[[1L]], mustWork = TRUE)
} else {
  normalizePath(file.path(baseline_dir, "phase4e_targeted_crossing_followup_vb480"), mustWork = TRUE)
}
baseline_phase3_dir <- file.path(baseline_dir, "phase3_forecast_validation")
baseline_audit_dir <- if (nzchar(as.character(arg_value("baseline_audit_dir")))) {
  normalizePath(as.character(arg_value("baseline_audit_dir"))[[1L]], mustWork = TRUE)
} else {
  normalizePath(file.path(baseline_dir, "phase4c_crossing_audit"), mustWork = TRUE)
}
followup_audit_dir <- if (nzchar(as.character(arg_value("followup_audit_dir")))) {
  normalizePath(as.character(arg_value("followup_audit_dir"))[[1L]], mustWork = TRUE)
} else {
  normalizePath(file.path(followup_dir, "phase4e_crossing_audit"), mustWork = TRUE)
}
out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  file.path(followup_dir, "phase4e_raw_crossing_vb_audit")
}
out_dir <- normalizePath(out_dir, mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

targeted_registry <- read_required(baseline_audit_dir, "targeted_crossing_registry.csv")
scenario_ids <- unique(as.character(targeted_registry$scenario_id))

baseline_summary <- summarize_scenarios(baseline_phase3_dir, scenario_ids)
followup_summary <- summarize_scenarios(followup_dir, scenario_ids)
scenario_comparison <- merge(
  prefix_cols(baseline_summary, "baseline_"),
  prefix_cols(followup_summary, "followup_"),
  by = "scenario_id",
  all = TRUE,
  sort = FALSE
)
scenario_comparison$delta_raw_crossing_pairs <- scenario_comparison$followup_raw_crossing_pairs - scenario_comparison$baseline_raw_crossing_pairs
scenario_comparison$delta_raw_crossing_origins <- scenario_comparison$followup_raw_crossing_origins - scenario_comparison$baseline_raw_crossing_origins
scenario_comparison$delta_max_monotone_adjustment <- scenario_comparison$followup_max_monotone_adjustment - scenario_comparison$baseline_max_monotone_adjustment
scenario_comparison$delta_vb_max_iter_rate <- scenario_comparison$followup_vb_max_iter_rate - scenario_comparison$baseline_vb_max_iter_rate
scenario_comparison$runtime_ratio_followup_to_baseline <- scenario_comparison$followup_runtime_total_sec / scenario_comparison$baseline_runtime_total_sec

sum_cols <- function(x, col) sum(x[[col]], na.rm = TRUE)
overall <- data.frame(
  baseline_dir = app_prefer_repo_relative_path(baseline_dir),
  followup_dir = app_prefer_repo_relative_path(followup_dir),
  n_targeted_scenarios = length(scenario_ids),
  baseline_raw_crossing_pairs = sum_cols(baseline_summary, "raw_crossing_pairs"),
  followup_raw_crossing_pairs = sum_cols(followup_summary, "raw_crossing_pairs"),
  delta_raw_crossing_pairs = sum_cols(followup_summary, "raw_crossing_pairs") - sum_cols(baseline_summary, "raw_crossing_pairs"),
  baseline_contract_crossing_pairs = sum_cols(baseline_summary, "contract_crossing_pairs"),
  followup_contract_crossing_pairs = sum_cols(followup_summary, "contract_crossing_pairs"),
  baseline_adjusted_origins = sum_cols(baseline_summary, "monotone_adjusted_origins"),
  followup_adjusted_origins = sum_cols(followup_summary, "monotone_adjusted_origins"),
  baseline_max_monotone_adjustment = max(baseline_summary$max_monotone_adjustment, na.rm = TRUE),
  followup_max_monotone_adjustment = max(followup_summary$max_monotone_adjustment, na.rm = TRUE),
  baseline_vb_max_iter_rate = sum_cols(baseline_summary, "vb_max_iter_count") / sum_cols(baseline_summary, "vb_refit_count"),
  followup_vb_max_iter_rate = sum_cols(followup_summary, "vb_max_iter_count") / sum_cols(followup_summary, "vb_refit_count"),
  baseline_runtime_sec = sum_cols(baseline_summary, "runtime_total_sec"),
  followup_runtime_sec = sum_cols(followup_summary, "runtime_total_sec"),
  stringsAsFactors = FALSE
)
overall$delta_vb_max_iter_rate <- overall$followup_vb_max_iter_rate - overall$baseline_vb_max_iter_rate
overall$runtime_ratio_followup_to_baseline <- overall$followup_runtime_sec / overall$baseline_runtime_sec

baseline_pairs <- read_required(baseline_audit_dir, "crossing_pair_detail.csv")
followup_pairs <- read_required(followup_audit_dir, "crossing_pair_detail.csv")
key_cols <- c("scenario_id", "origin_index", "forecast_time_index", "lower_tau", "upper_tau")
baseline_pairs$baseline_crossing_present <- TRUE
followup_pairs$followup_crossing_present <- TRUE
pair_compare <- merge(
  baseline_pairs[, c(key_cols, "crossing_magnitude", "baseline_crossing_present"), drop = FALSE],
  followup_pairs[, c(key_cols, "crossing_magnitude", "followup_crossing_present"), drop = FALSE],
  by = key_cols,
  all = TRUE,
  suffixes = c("_baseline", "_followup"),
  sort = FALSE
)
pair_compare$baseline_crossing_present[is.na(pair_compare$baseline_crossing_present)] <- FALSE
pair_compare$followup_crossing_present[is.na(pair_compare$followup_crossing_present)] <- FALSE
pair_compare$set_status <- ifelse(
  pair_compare$baseline_crossing_present & pair_compare$followup_crossing_present,
  "both",
  ifelse(pair_compare$baseline_crossing_present, "baseline_only", "followup_only")
)

vb_runtime_comparison <- scenario_comparison[, c(
  "scenario_id",
  "baseline_vb_refit_count", "followup_vb_refit_count",
  "baseline_vb_max_iter_rate", "followup_vb_max_iter_rate", "delta_vb_max_iter_rate",
  "baseline_runtime_total_sec", "followup_runtime_total_sec", "runtime_ratio_followup_to_baseline"
), drop = FALSE]

raw_reduction_fraction <- if (overall$baseline_raw_crossing_pairs[[1L]] > 0) {
  -overall$delta_raw_crossing_pairs[[1L]] / overall$baseline_raw_crossing_pairs[[1L]]
} else {
  NA_real_
}
vb_improved <- overall$followup_vb_max_iter_rate[[1L]] < overall$baseline_vb_max_iter_rate[[1L]]
raw_materially_improved <- is.finite(raw_reduction_fraction) && raw_reduction_fraction >= 0.50
gate_status <- if (overall$followup_contract_crossing_pairs[[1L]] > 0) {
  "fail"
} else if (overall$followup_raw_crossing_pairs[[1L]] > 0 || overall$followup_vb_max_iter_rate[[1L]] > 0.25) {
  "review"
} else {
  "pass"
}
recommendation_status <- if (overall$followup_contract_crossing_pairs[[1L]] > 0) {
  "blocked_contract_crossings"
} else if (vb_improved && !raw_materially_improved && overall$followup_raw_crossing_pairs[[1L]] > 0) {
  "vb_improved_raw_crossings_persist"
} else if (vb_improved && raw_materially_improved) {
  "vb_and_raw_crossings_improved"
} else {
  "review_before_article_candidate"
}
recommendation <- data.frame(
  gate_status = gate_status,
  recommendation_status = recommendation_status,
  article_candidate_ready = identical(gate_status, "pass"),
  raw_reduction_fraction = raw_reduction_fraction,
  vb_improved = vb_improved,
  raw_materially_improved = raw_materially_improved,
  recommended_next_action = if (identical(recommendation_status, "vb_improved_raw_crossings_persist")) {
    "Do not rerun full calibration yet; inspect raw crossing magnitudes/origins and decide whether raw adjustment review is acceptable under the contract."
  } else if (identical(gate_status, "pass")) {
    "Proceed to article-candidate planning."
  } else {
    "Continue targeted review before article-candidate planning."
  },
  rationale = app_joint_qvp_ts_assessment_note(c(
    if (overall$followup_contract_crossing_pairs[[1L]] == 0) "contract crossings remain zero",
    if (overall$followup_raw_crossing_pairs[[1L]] > 0) "raw crossings persist after stronger VB",
    if (vb_improved) "VB max-iteration rate improved",
    if (!raw_materially_improved) "raw crossings did not materially reduce"
  )),
  stringsAsFactors = FALSE
)

readme_path <- file.path(out_dir, "README.md")
writeLines(phase4e_readme(overall, recommendation), readme_path, useBytes = TRUE)
paths <- c(
  phase4e_before_after_overall_summary = app_joint_qvp_write_csv(overall, file.path(out_dir, "phase4e_before_after_overall_summary.csv")),
  phase4e_before_after_scenario_comparison = app_joint_qvp_write_csv(scenario_comparison, file.path(out_dir, "phase4e_before_after_scenario_comparison.csv")),
  phase4e_crossing_origin_set_comparison = app_joint_qvp_write_csv(pair_compare, file.path(out_dir, "phase4e_crossing_origin_set_comparison.csv")),
  phase4e_vb_runtime_comparison = app_joint_qvp_write_csv(vb_runtime_comparison, file.path(out_dir, "phase4e_vb_runtime_comparison.csv")),
  phase4e_recommendation = app_joint_qvp_write_csv(recommendation, file.path(out_dir, "phase4e_recommendation.csv")),
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

cat(sprintf("Joint-QVP Phase 4e raw-crossing/VB audit written to %s\n", out_dir))
cat(sprintf("Gate: %s\n", recommendation$gate_status[[1L]]))
cat(sprintf("Recommendation: %s\n", recommendation$recommendation_status[[1L]]))
cat(sprintf("Raw crossings: %s -> %s\n", overall$baseline_raw_crossing_pairs[[1L]], overall$followup_raw_crossing_pairs[[1L]]))
cat(sprintf("VB max-iteration rate: %.3f -> %.3f\n", overall$baseline_vb_max_iter_rate[[1L]], overall$followup_vb_max_iter_rate[[1L]]))
cat(sprintf("Artifact manifest: %s\n", manifest_path))
