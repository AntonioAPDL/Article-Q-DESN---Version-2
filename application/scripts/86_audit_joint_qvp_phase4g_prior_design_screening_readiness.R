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
  output_dir = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

read_required <- function(path) {
  if (!file.exists(path)) stop(sprintf("Missing required Phase 4g readiness input: %s", path), call. = FALSE)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

repo_rel <- function(path) app_prefer_repo_relative_path(normalizePath(path, mustWork = TRUE))

contains_text <- function(txt, pattern, fixed = TRUE) {
  grepl(pattern, txt, fixed = fixed)
}

extract_block <- function(txt, start_marker, end_marker) {
  start <- regexpr(start_marker, txt, fixed = TRUE)[[1L]]
  if (start < 0L) return("")
  end <- regexpr(end_marker, substring(txt, start + nchar(start_marker)), fixed = TRUE)[[1L]]
  if (end < 0L) return(substring(txt, start))
  substring(txt, start, start + nchar(start_marker) + end - 2L)
}

baseline_dir <- normalizePath(as.character(arg_value("baseline_dir"))[[1L]], mustWork = TRUE)
followup_dir <- if (nzchar(as.character(arg_value("followup_dir")))) {
  normalizePath(as.character(arg_value("followup_dir"))[[1L]], mustWork = TRUE)
} else {
  normalizePath(file.path(baseline_dir, "phase4e_targeted_crossing_followup_vb480"), mustWork = TRUE)
}
out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  file.path(baseline_dir, "phase4g_prior_design_screening_readiness_audit")
}
out_dir <- normalizePath(out_dir, mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

phase4e_audit_dir <- file.path(followup_dir, "phase4e_raw_crossing_vb_audit")
phase4f_diag_dir <- file.path(baseline_dir, "phase4f_sparsity_tau0_diagnostics")
phase4f_overlay_dir <- file.path(followup_dir, "phase4f_data_truth_fit_overlays")
phase4c_audit_dir <- file.path(baseline_dir, "phase4c_crossing_audit")

overall <- read_required(file.path(phase4e_audit_dir, "phase4e_before_after_overall_summary.csv"))
scenario <- read_required(file.path(phase4e_audit_dir, "phase4e_before_after_scenario_comparison.csv"))
overlay_summary <- read_required(file.path(phase4f_overlay_dir, "phase4f_data_truth_fit_summary.csv"))
phase4f_summary <- read_required(file.path(phase4f_diag_dir, "phase4f_summary.csv"))
phase4f_recommendation <- read_required(file.path(phase4f_diag_dir, "phase4f_sparsity_recommendation.csv"))
targeted_registry <- read_required(file.path(phase4c_audit_dir, "targeted_crossing_registry.csv"))

qdesn_path <- app_path("application/R/joint_qvp_qdesn.R")
script77_path <- app_path("application/scripts/77_run_joint_qvp_synthetic_dgp_forecast_validation.R")
qdesn_text <- paste(readLines(qdesn_path, warn = FALSE), collapse = "\n")
script77_text <- paste(readLines(script77_path, warn = FALSE), collapse = "\n")
tiny_block <- extract_block(qdesn_text, "app_joint_qvp_fit_al_vb_tiny <- function(", "app_joint_qvp_fit_exal_vb_ld <- function(")
adaptive_block <- extract_block(qdesn_text, "app_joint_qvp_fit_al_vb_adaptive <- function(", "app_joint_qvp_fit_ts_synthetic_scenario <- function(")
phase3_block <- extract_block(
  qdesn_text,
  "app_joint_qvp_run_synthetic_dgp_forecast_validation <- function(",
  "app_joint_qvp_default_synthetic_dgp_forecast_calibration_dir <- function()"
)

plumbing_audit <- data.frame(
  control = c(
    "tau0",
    "alpha_prior_sd",
    "rhs_vb_inner",
    "zeta2",
    "alpha_min_spacing",
    "anchor_tau0_vs_innovation_tau0",
    "raw_contract_forecast_policy",
    "targeted_registry_seed_preservation",
    "feature_readout_norm_audit"
  ),
  current_status = c(
    "partially_wired",
    "partially_wired",
    "partially_wired",
    "internal_only",
    "internal_only",
    "not_wired",
    "wired",
    "wired",
    "not_wired"
  ),
  evidence = c(
    "Phase 3 runner accepts tau0 and passes it to adaptive VB; CLI 77 does not expose it.",
    "Phase 3 runner accepts alpha_prior_sd and passes it to adaptive VB; CLI 77 does not expose it.",
    "Phase 3 runner accepts rhs_vb_inner and passes it to adaptive VB; CLI 77 does not expose it.",
    "app_joint_qvp_fit_al_vb_tiny supports zeta2; adaptive VB and Phase 3 forecast runner do not yet expose it.",
    "app_joint_qvp_fit_al_vb_tiny supports alpha_min_spacing; adaptive VB and Phase 3 forecast runner do not yet expose it.",
    "Current RHS initializer uses one tau0/zeta2 for anchor and innovations.",
    "Phase 3 writes forecast_quantiles_raw.csv, forecast_quantiles.csv, forecast_monotone_adjustment.csv, raw_crossing_summary.csv, and crossing_summary.csv.",
    "Phase 4c writes targeted_crossing_registry.csv with scenario ids, seeds, replicate ids, and base scenario ids.",
    "Feature norm/readout norm diagnostics are not yet exported for forecast-origin screening."
  ),
  required_phase4g_action = c(
    "Add CLI flag and record in screen configs.",
    "Add CLI flag and record in screen configs.",
    "Add CLI flag and record in screen configs.",
    "Add zeta2 to adaptive VB and Phase 3 forecast runner; add CLI flag.",
    "Add alpha_min_spacing to adaptive VB and Phase 3 forecast runner; add CLI flag.",
    "Defer to Tier 2 after Tier 1; implement separate anchor/innovation controls only if needed.",
    "Reuse as fixed contract; do not relax contract crossing hard gate.",
    "Use targeted registry as frozen input for all Tier 1 runs.",
    "Add as diagnostic output in Phase 4g or Phase 4g-b if Tier 1 is inconclusive."
  ),
  priority = c("high", "medium", "medium", "high", "medium", "second_wave", "hard_requirement", "hard_requirement", "second_wave"),
  stringsAsFactors = FALSE
)

code_presence <- data.frame(
  check = c(
    "fit_al_vb_tiny_has_zeta2",
    "fit_al_vb_tiny_has_alpha_min_spacing",
    "adaptive_vb_exposes_zeta2",
    "phase3_runner_exposes_zeta2",
    "script77_exposes_tau0",
    "script77_exposes_zeta2",
    "phase3_writes_raw_and_contract_outputs"
  ),
  passed = c(
    contains_text(tiny_block, "zeta2 = Inf"),
    contains_text(tiny_block, "alpha_min_spacing = 0"),
    contains_text(adaptive_block, "zeta2 = Inf"),
    contains_text(phase3_block, "zeta2 = Inf"),
    contains_text(script77_text, "tau0"),
    contains_text(script77_text, "zeta2"),
    contains_text(phase3_block, "forecast_quantiles_raw") && contains_text(phase3_block, "forecast_monotone_adjustment")
  ),
  expected_now = c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, TRUE),
  stringsAsFactors = FALSE
)
code_presence$status <- ifelse(code_presence$passed == code_presence$expected_now, "as_expected", "review")

evidence_audit <- data.frame(
  evidence_item = c(
    "raw_crossing_iteration_sensitivity",
    "contract_crossing_status",
    "vb_convergence_response",
    "largest_raw_crossing_source",
    "truth_metric_watchlist",
    "tau0_direction",
    "screening_scope"
  ),
  finding = c(
    sprintf(
      "Raw crossings changed from %s to %s under stronger VB, a reduction of %.3f.",
      overall$baseline_raw_crossing_pairs[[1L]],
      overall$followup_raw_crossing_pairs[[1L]],
      (overall$baseline_raw_crossing_pairs[[1L]] - overall$followup_raw_crossing_pairs[[1L]]) /
        overall$baseline_raw_crossing_pairs[[1L]]
    ),
    sprintf("Contract crossings are %s in the stronger-VB targeted follow-up.", overall$followup_contract_crossing_pairs[[1L]]),
    sprintf(
      "VB max-iteration rate improved from %.3f to %.3f.",
      overall$baseline_vb_max_iter_rate[[1L]],
      overall$followup_vb_max_iter_rate[[1L]]
    ),
    sprintf(
      "Persistent heavy tail remains the largest raw crossing contributor with %s raw pairs and max adjustment %.3f.",
      overlay_summary$raw_crossing_pairs[overlay_summary$scenario_id == "persistent_heavy_tail__calibration_r05"],
      overlay_summary$max_abs_monotone_adjustment[overlay_summary$scenario_id == "persistent_heavy_tail__calibration_r05"]
    ),
    sprintf(
      "Regime shift has the largest mean absolute truth error among targeted rows: %.3f.",
      max(overlay_summary$mean_abs_truth_error, na.rm = TRUE)
    ),
    "Larger tau0 weakens RHS shrinkage because tau2 is initialized as tau0^2 and prior precision includes 1 / (tau2 * lambda2).",
    sprintf("The optimal next screen should use the %s frozen targeted rows before any full calibration rerun.", nrow(targeted_registry))
  ),
  implication = c(
    "Do not spend on another VB-only iteration run; test regularization/design controls.",
    "Keep the raw/contract policy; hard-fail only contract crossings, review raw adjustments.",
    "Use the Phase 4e VB controls as the targeted-screen compute baseline.",
    "Prior/design screen should include heavy-tail cases and not only bridge scenarios.",
    "Ranking must guard against crossing reduction that worsens truth fit.",
    "Screen smaller tau0, finite zeta2, and eventually innovation-specific shrinkage.",
    "This reduces compute and preserves exact failing seeds/origins."
  ),
  status = c("supports_phase4g", "supports_phase4g", "supports_phase4g", "supports_phase4g", "guardrail", "supports_phase4g", "supports_phase4g"),
  stringsAsFactors = FALSE
)

hypothesis_diagnosis <- data.frame(
  hypothesis = c(
    "H1_global_rhs_shrinkage",
    "H2_finite_slab_zeta2",
    "H3_adjacent_innovation_shrinkage",
    "H4_alpha_intercept_stabilization",
    "H5_feature_readout_design"
  ),
  diagnosis = c(
    "Plausible first screen because raw crossings are adjacent-tail readout artifacts and larger iteration budgets did not remove them.",
    "Plausible first screen because zeta2 adds a precision floor for large coefficients and is already present in the lower-level VB implementation.",
    "Most structurally aligned with adjacent quantile crossing, but requires new anchor/innovation-specific prior controls.",
    "Useful secondary check because ordered intercepts do not prevent slope-induced crossings; too-tight alpha priors may harm conditional calibration.",
    "Important if crossings correlate with large design row norms or beta-difference norms, but not yet diagnosed."
  ),
  immediate_action = c(
    "Tier 1 grid over tau0 in {1,0.5,0.25,0.1}.",
    "Tier 1 grid over zeta2 in {Inf,10,4}, plus selected tau0+zeta2 combinations.",
    "Tier 2 after Tier 1; implement only if global/slab screen is insufficient or inconclusive.",
    "Tier 1 include alpha_prior_sd=0.5 as a cautious single-point diagnostic.",
    "Add feature/readout norm audit if Tier 1 does not produce a clear winner."
  ),
  risk = c(
    "Underfit and worse truth distance if tau0 is too small.",
    "Underfit sharp tail dynamics if zeta2 is too small.",
    "Requires more plumbing and tests.",
    "May improve apparent stability while hurting conditional tails.",
    "Could distract from prior issue if run before simpler controls."
  ),
  priority = c("tier1", "tier1", "tier2", "tier1_single_point", "tier3"),
  stringsAsFactors = FALSE
)

screen_grid <- data.frame(
  screen_id = c(
    "baseline_vb480",
    "tau0_0p5",
    "tau0_0p25",
    "tau0_0p1",
    "zeta2_10",
    "zeta2_4",
    "tau0_0p5_zeta2_10",
    "tau0_0p25_zeta2_10",
    "alpha_sd_0p5",
    "rhs_inner_8"
  ),
  tier = "targeted",
  tau0 = c(1, 0.5, 0.25, 0.1, 1, 1, 0.5, 0.25, 1, 1),
  zeta2 = c(Inf, Inf, Inf, Inf, 10, 4, 10, 10, Inf, Inf),
  alpha_prior_sd = c(1, 1, 1, 1, 1, 1, 1, 1, 0.5, 1),
  rhs_vb_inner = c(5L, 5L, 5L, 5L, 5L, 5L, 5L, 5L, 5L, 8L),
  vb_max_iter = 480L,
  adaptive_vb_max_iter_grid = "480,720",
  refit_stride = 20L,
  forecast_origin_stride = 10L,
  max_origins_per_scenario = 40L,
  rationale = c(
    "Current stronger-VB reference.",
    "Moderate stronger global RHS shrinkage.",
    "Strong global RHS shrinkage.",
    "Aggressive shrinkage stress.",
    "Light slab precision floor.",
    "Moderate slab precision floor.",
    "Moderate global shrinkage plus slab floor.",
    "Strong global shrinkage plus slab floor.",
    "Cautious tighter empirical alpha prior.",
    "Check RHS VB update accuracy/stability."
  ),
  stringsAsFactors = FALSE
)

metric_priority <- data.frame(
  metric_group = c(
    "implementation",
    "crossing",
    "crossing",
    "fit_forecast",
    "fit_forecast",
    "fit_forecast",
    "convergence",
    "runtime",
    "interpretability"
  ),
  metric = c(
    "contract_crossing_pairs",
    "raw_crossing_pairs",
    "max_raw_crossing_magnitude",
    "mean_abs_truth_error",
    "max_abs_hit_rate_error",
    "interval_score_or_wis",
    "vb_max_iter_rate",
    "runtime_ratio_to_baseline",
    "rhs_precision_and_adjacent_beta_difference"
  ),
  target_direction = c("must_be_zero", "lower", "lower", "not_worse", "not_worse", "not_worse", "not_worse", "not_excessive", "diagnostic"),
  promotion_rule = c(
    "Hard fail if nonzero.",
    "Promote if reduced by at least 50 percent or if max magnitude reduced by at least 50 percent.",
    "Promote if reduced by at least 50 percent when raw count reduction is modest.",
    "Do not promote if mean truth error worsens by more than 2 percent.",
    "Do not promote if any key tau hit-rate error worsens by more than 0.025.",
    "Review if interval quality worsens materially.",
    "Review if greater than 0.25 or worse than Phase 4e.",
    "Review if more than 2x baseline without clear metric gain.",
    "Use to decide whether Tier 2 innovation shrinkage is warranted."
  ),
  stringsAsFactors = FALSE
)

promotion_gates <- data.frame(
  gate = c("hard_fail", "review", "promote", "do_not_promote"),
  condition = c(
    "Missing artifacts/hashes, leakage, nonfinite values, or contract crossings.",
    "Raw crossings persist with limited reduction, truth metrics worsen mildly, VB max-iteration rate high, or runtime high.",
    "Raw crossing count or magnitude improves materially with neutral/improved truth and calibration metrics.",
    "Crossing reduction is achieved only by underfitting or worsening forecast metrics."
  ),
  action = c(
    "Fix implementation before more experiments.",
    "Inspect diagnostics and consider narrower follow-up.",
    "Run a 3-replicate calibration pilot before full calibration.",
    "Reject candidate and keep raw/contract policy."
  ),
  stringsAsFactors = FALSE
)

risk_register <- data.frame(
  risk = c(
    "Over-shrinking readout hides crossings but hurts dynamics.",
    "Full calibration rerun before targeted evidence wastes compute.",
    "Changing defaults silently contaminates Phase 3/4 comparisons.",
    "Feature design changes become confounded with prior changes.",
    "Raw crossing review is overinterpreted as model failure despite contract outputs being noncrossing."
  ),
  mitigation = c(
    "Rank candidates jointly on raw crossings and truth/score metrics.",
    "Run Tier 0/Tier 1 first and promote only winners.",
    "Add explicit Phase 4g flags and record controls in run configs.",
    "Defer feature changes until after prior-control screen or run a separate audit.",
    "Keep raw diagnostics transparent and contract hard gate strict."
  ),
  severity = c("high", "medium", "high", "medium", "medium"),
  stringsAsFactors = FALSE
)

workflow_plan <- data.frame(
  step = 1:7,
  phase = c(
    "plumbing",
    "smoke",
    "targeted_screen",
    "ranking",
    "diagnostic_followup",
    "calibration_pilot",
    "full_calibration"
  ),
  objective = c(
    "Expose zeta2, alpha_min_spacing, tau0, alpha_prior_sd, and rhs_vb_inner through Phase 3/Phase 4g controls without changing defaults.",
    "Run 1-2 scenarios and <=8 origins to verify control recording and manifests.",
    "Run the Tier 1 grid over the 7 frozen crossing-prone registry rows.",
    "Rank candidates by crossing, truth, score, convergence, and runtime metrics.",
    "If Tier 1 is inconclusive, add feature/readout norm audit or Tier 2 innovation shrinkage.",
    "Run at most 2-3 winners over all scenarios with 3 replicates.",
    "Only rerun full Phase 4 calibration after a pilot winner is identified."
  ),
  done_when = c(
    "Focused tests prove controls are recorded and defaults are unchanged.",
    "Artifacts complete and contract crossings are zero.",
    "All grid rows have complete output and manifests.",
    "screen_candidate_ranking.csv has an explicit promote/review/reject recommendation.",
    "Decision is made on Tier 2 or pilot promotion.",
    "Candidate generalizes beyond targeted rows.",
    "Article-candidate validation outputs can be frozen."
  ),
  stringsAsFactors = FALSE
)

readiness_summary <- data.frame(
  readiness_status = "ready_to_implement_phase4g_screening",
  optimality_assessment = "targeted_prior_design_screen_is_optimal_next_step",
  rationale = paste(
    "Stronger VB reduced max-iteration review but not raw crossings;",
    "contract outputs are already noncrossing;",
    "tau0 direction implies smaller tau0, not larger tau0, is the direct sparsity lever;",
    "zeta2 and alpha_min_spacing exist in lower-level code but need controlled Phase 3 plumbing;",
    "the frozen targeted registry preserves the exact failing seeds and avoids an unnecessary full calibration rerun."
  ),
  recommended_next_artifact = "application/scripts/85_run_joint_qvp_synthetic_dgp_phase4g_prior_design_screen.R",
  recommended_output_dir = app_prefer_repo_relative_path(file.path(baseline_dir, "phase4g_prior_design_screen")),
  stringsAsFactors = FALSE
)

readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint-QVP Phase 4g Prior/Design Screening Readiness Audit",
  "",
  "This artifact audits whether the proposed Phase 4g targeted prior/design screen is the right next step after Phase 4e/4f.",
  "",
  "Conclusion: implement the targeted Phase 4g screen before any full calibration rerun.",
  "",
  "Primary files:",
  "",
  "- `phase4g_readiness_summary.csv`: one-row decision summary.",
  "- `phase4g_control_plumbing_audit.csv`: control wiring status and required actions.",
  "- `phase4g_code_presence_audit.csv`: source-code presence checks for current controls.",
  "- `phase4g_evidence_audit.csv`: evidence supporting the next-step decision.",
  "- `phase4g_hypothesis_diagnosis.csv`: hypothesis-by-hypothesis diagnosis.",
  "- `phase4g_screen_grid.csv`: recommended first targeted screening grid.",
  "- `phase4g_metric_priority.csv`: metric ranking and promotion rules.",
  "- `phase4g_promotion_gates.csv`: pass/review/fail and promotion actions.",
  "- `phase4g_risk_register.csv`: major risks and mitigations.",
  "- `phase4g_workflow_plan.csv`: ordered implementation and validation workflow.",
  "- `artifact_manifest.csv`: SHA-256 manifest."
), readme_path, useBytes = TRUE)

paths <- c(
  readiness_summary = app_joint_qvp_write_csv(readiness_summary, file.path(out_dir, "phase4g_readiness_summary.csv")),
  control_plumbing_audit = app_joint_qvp_write_csv(plumbing_audit, file.path(out_dir, "phase4g_control_plumbing_audit.csv")),
  code_presence_audit = app_joint_qvp_write_csv(code_presence, file.path(out_dir, "phase4g_code_presence_audit.csv")),
  evidence_audit = app_joint_qvp_write_csv(evidence_audit, file.path(out_dir, "phase4g_evidence_audit.csv")),
  hypothesis_diagnosis = app_joint_qvp_write_csv(hypothesis_diagnosis, file.path(out_dir, "phase4g_hypothesis_diagnosis.csv")),
  screen_grid = app_joint_qvp_write_csv(screen_grid, file.path(out_dir, "phase4g_screen_grid.csv")),
  metric_priority = app_joint_qvp_write_csv(metric_priority, file.path(out_dir, "phase4g_metric_priority.csv")),
  promotion_gates = app_joint_qvp_write_csv(promotion_gates, file.path(out_dir, "phase4g_promotion_gates.csv")),
  risk_register = app_joint_qvp_write_csv(risk_register, file.path(out_dir, "phase4g_risk_register.csv")),
  workflow_plan = app_joint_qvp_write_csv(workflow_plan, file.path(out_dir, "phase4g_workflow_plan.csv")),
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

cat(sprintf("Joint-QVP Phase 4g screening readiness audit written to %s\n", out_dir))
cat(sprintf("Readiness: %s\n", readiness_summary$readiness_status[[1L]]))
cat(sprintf("Recommended next artifact: %s\n", readiness_summary$recommended_next_artifact[[1L]]))
cat(sprintf("Artifact manifest: %s\n", manifest_path))
