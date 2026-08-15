repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for readiness audit test.", call. = FALSE)
  }
}
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))

out_dir <- tempfile("joint_qdesn_vb_readiness_")
result <- app_joint_qdesn_run_vb_readiness_audit(
  out_dir = out_dir,
  Tn = 24L,
  washout_length = 6L,
  tau = c(0.1, 0.5, 0.9),
  seed = 2026070611L,
  vb_max_iter = 3L,
  rhs_vb_inner = 1L,
  review_adjustment_threshold = 1.0e-4
)

expected_labels <- c(
  "run_config",
  "readiness_checklist",
  "toy_fixture_summary",
  "model_scope_readiness",
  "raw_contract_quantile_diagnostics",
  "k1_reduction_readiness",
  "oracle_policy_readiness",
  "simulation_design_readiness",
  "launch_blockers",
  "next_phase_plan",
  "provenance",
  "readme"
)

manifest <- utils::read.csv(file.path(result$out_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(identical(manifest$label, expected_labels))
stopifnot(all(nchar(manifest$sha256) == 64L))
for (ii in seq_len(nrow(manifest))) {
  artifact_path <- file.path(result$out_dir, manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), manifest$sha256[[ii]]))
}

run_config <- utils::read.csv(file.path(result$out_dir, "run_config.csv"), stringsAsFactors = FALSE)
checklist <- utils::read.csv(file.path(result$out_dir, "readiness_checklist.csv"), stringsAsFactors = FALSE)
fixture_summary <- utils::read.csv(file.path(result$out_dir, "toy_fixture_summary.csv"), stringsAsFactors = FALSE)
model_scope <- utils::read.csv(file.path(result$out_dir, "model_scope_readiness.csv"), stringsAsFactors = FALSE)
raw_contract <- utils::read.csv(file.path(result$out_dir, "raw_contract_quantile_diagnostics.csv"), stringsAsFactors = FALSE)
k1 <- utils::read.csv(file.path(result$out_dir, "k1_reduction_readiness.csv"), stringsAsFactors = FALSE)
oracle_policy <- utils::read.csv(file.path(result$out_dir, "oracle_policy_readiness.csv"), stringsAsFactors = FALSE)
design <- utils::read.csv(file.path(result$out_dir, "simulation_design_readiness.csv"), stringsAsFactors = FALSE)
blockers <- utils::read.csv(file.path(result$out_dir, "launch_blockers.csv"), stringsAsFactors = FALSE)
next_plan <- utils::read.csv(file.path(result$out_dir, "next_phase_plan.csv"), stringsAsFactors = FALSE)

stopifnot(all(c("run_id", "audit_scope", "overall_status", "long_fixture_generation_launched") %in% names(run_config)))
stopifnot(identical(run_config$long_fixture_generation_launched[[1L]], FALSE))
stopifnot(run_config$Tn[[1L]] == 24L)
stopifnot(run_config$washout_length[[1L]] == 6L)
stopifnot(run_config$retained_length[[1L]] == 18L)
stopifnot(run_config$overall_status[[1L]] %in% c("pass", "review", "fail"))

stopifnot(all(c("check_id", "gate_status", "evidence") %in% names(checklist)))
stopifnot(all(checklist$check_id %in% c(
  "model_labels",
  "joint_al_vb_available",
  "joint_exal_vb_ld_available",
  "independent_comparators_available",
  "k1_reduction",
  "rhs_prior_finite",
  "raw_contract_quantiles",
  "oracle_policy",
  "long_series_geometry",
  "mcmc_deferred",
  "artifact_manifest",
  "no_long_fixture_launch"
)))
stopifnot(all(checklist$gate_status %in% c("pass", "review", "fail")))

stopifnot(all(c("fixture_id", "finite_y", "finite_Z", "finite_true_q", "positive_scale_path") %in% names(fixture_summary)))
stopifnot(isTRUE(fixture_summary$finite_y[[1L]]))
stopifnot(isTRUE(fixture_summary$finite_Z[[1L]]))
stopifnot(isTRUE(fixture_summary$finite_true_q[[1L]]))
stopifnot(isTRUE(fixture_summary$positive_scale_path[[1L]]))
stopifnot(fixture_summary$true_quantile_crossing_pairs[[1L]] == 0L)

expected_models <- c(
  "joint_qdesn_rhs_vb",
  "joint_exqdesn_rhs_vb",
  "qdesn_rhs_independent_vb",
  "exqdesn_rhs_independent_vb"
)
stopifnot(identical(model_scope$model_id, expected_models))
stopifnot(identical(model_scope$display_label, c("JOINT QDESN RHS", "JOINT exQDESN RHS", "QDESN RHS", "exQDESN RHS")))
stopifnot(all(model_scope$implementation_status %in% c("pass", "fail")))
stopifnot(all(model_scope$gate_status %in% c("pass", "review", "fail")))
stopifnot(all(model_scope$finite_qhat))
stopifnot(all(model_scope$finite_sigma))
stopifnot(all(model_scope$finite_trace))
stopifnot(all(model_scope$finite_rhs_prior))
stopifnot(all(model_scope$contract_crossing_pairs == 0L))
stopifnot(all(is.finite(model_scope$truth_mae_contract)))
stopifnot(all(is.finite(model_scope$truth_rmse_contract)))

stopifnot(nrow(raw_contract) == length(expected_models) * 3L)
stopifnot(all(c("model_id", "tau", "max_abs_adjustment", "total_raw_crossing_pairs", "total_contract_crossing_pairs") %in% names(raw_contract)))
stopifnot(all(is.finite(raw_contract$max_abs_adjustment)))
stopifnot(all(raw_contract$total_contract_crossing_pairs == 0L))

stopifnot(nrow(k1) == 2L)
stopifnot(identical(k1$model_id, c("qdesn_rhs_independent_vb", "exqdesn_rhs_independent_vb")))
stopifnot(all(k1$all_single_tau_fits_finite))
stopifnot(all(k1$combined_contract_crossing_pairs == 0L))

stopifnot(all(oracle_policy$readiness_status == "pass"))
stopifnot("long_fixture_launch" %in% design$design_component)
stopifnot(identical(design$value[design$design_component == "long_fixture_launch"], "not launched by readiness audit"))
stopifnot(all(c("severity", "blocker", "detail", "action") %in% names(blockers)))
stopifnot(all(c("step_order", "step_id", "recommended_action", "current_status") %in% names(next_plan)))
stopifnot("introduce_mcmc_reference" %in% next_plan$step_id)
