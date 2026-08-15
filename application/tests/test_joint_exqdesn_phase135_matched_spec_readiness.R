repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase135 test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_phase135_matched_spec_readiness.R"))

check_manifest <- function(dir) {
  manifest <- utils::read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  manifest
}

out_dir <- tempfile("joint_exqdesn_phase135_")
screening_dir <- tempfile("joint_exqdesn_phase135_screen_")
result <- app_joint_exqdesn_run_phase135_matched_spec_readiness(
  out_dir = out_dir,
  screening_output_dir = screening_dir,
  workers = 2L,
  n_cores_per_worker = 1L
)

manifest <- check_manifest(result$out_dir)
expected_labels <- c(
  "phase135_run_config",
  "phase134_source_manifest_verification",
  "phase121_source_manifest_verification",
  "phase124c_source_manifest_verification",
  "phase125_source_manifest_verification",
  "phase134_per_scenario_winners",
  "phase135_matched_spec_parity_audit",
  "phase135_matched_exal_screening_registry",
  "phase135_launch_commands",
  "phase135_assessment",
  "provenance",
  "readme"
)
stopifnot(identical(manifest$label, expected_labels))

assessment <- utils::read.csv(file.path(result$out_dir, "phase135_assessment.csv"), stringsAsFactors = FALSE)
registry <- utils::read.csv(file.path(result$out_dir, "phase135_matched_exal_screening_registry.csv"), stringsAsFactors = FALSE)
parity <- utils::read.csv(file.path(result$out_dir, "phase135_matched_spec_parity_audit.csv"), stringsAsFactors = FALSE)
winners <- utils::read.csv(file.path(result$out_dir, "phase134_per_scenario_winners.csv"), stringsAsFactors = FALSE)
commands <- utils::read.csv(file.path(result$out_dir, "phase135_launch_commands.csv"), stringsAsFactors = FALSE)

stopifnot(assessment$implementation_gate[[1L]] == "pass")
stopifnot(assessment$audit_gate[[1L]] == "pass")
stopifnot(assessment$n_matched_exal_registry_rows[[1L]] == 16L)
stopifnot(nrow(registry) == 16L)
stopifnot(all(registry$model_ids %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")))
stopifnot(!any(registry$model_ids %in% c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb")))
stopifnot(sum(registry$model_ids == "joint_exqdesn_rhs_vb") == 8L)
stopifnot(sum(registry$model_ids == "exqdesn_rhs_independent_vb") == 8L)
stopifnot(all(c("joint_matched_to_joint_al", "independent_matched_to_independent_al") %in% registry$phase135_pair_id))
stopifnot(any(!parity$current_tau0_same))
stopifnot(any(!parity$current_all_compared_controls_same))
stopifnot(all(parity$phase135_matched_registry_will_copy_al_controls))
stopifnot(nrow(winners) == 5L)
stopifnot(any(winners$phase135_decision_class == "promote_to_mcmc_candidate"))
stopifnot(any(winners$phase135_decision_class == "retain_reference"))
stopifnot(any(grepl("123_launch_joint_qdesn_screening_parallel_chunks.sh", commands$command, fixed = TRUE)))
stopifnot(any(grepl("106_run_joint_qdesn_vb_spec_screening.R", commands$command, fixed = TRUE)))

controls <- result$controls$controls
pair_map <- app_joint_exqdesn_phase135_pair_map()
for (ii in seq_len(nrow(registry))) {
  row <- registry[ii, , drop = FALSE]
  pair <- pair_map[pair_map$target_exal_model_id == row$model_ids[[1L]] & pair_map$pair_id == row$phase135_pair_id[[1L]], , drop = FALSE]
  stopifnot(nrow(pair) == 1L)
  source <- controls[controls$scenario_ids == row$scenario_ids[[1L]] & controls$model_ids == pair$source_al_model_id[[1L]], , drop = FALSE]
  stopifnot(nrow(source) == 1L)
  stopifnot(identical(as.numeric(row$tau0[[1L]]), as.numeric(source$tau0[[1L]])))
  stopifnot(identical(as.numeric(row$zeta2[[1L]]), as.numeric(source$zeta2[[1L]])))
  stopifnot(identical(as.character(row$alpha_prior_sd[[1L]]), as.character(source$alpha_prior_sd[[1L]])))
  stopifnot(identical(as.integer(row$rhs_vb_inner[[1L]]), as.integer(source$rhs_vb_inner[[1L]])))
  stopifnot(identical(as.integer(row$vb_max_iter[[1L]]), as.integer(source$vb_max_iter[[1L]])))
}

app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)

if (dir.exists(app_joint_exqdesn_phase135_default_screening_dir())) {
  result_audit_dir <- tempfile("joint_exqdesn_phase135_result_audit_")
  audit <- app_joint_exqdesn_run_phase135_matched_spec_result_audit(
    out_dir = result_audit_dir,
    screening_dir = app_joint_exqdesn_phase135_default_screening_dir()
  )
  audit_manifest <- check_manifest(audit$out_dir)
  expected_audit_labels <- c(
    "phase135_result_run_config",
    "phase135_screening_manifest_verification",
    "phase135_candidate_manifest_verification",
    "phase121_source_manifest_verification",
    "phase124c_source_manifest_verification",
    "phase135_matched_exal_vs_source_al_vb_comparison",
    "phase135_matched_exal_model_summary",
    "phase135_result_decision",
    "phase135_gamma_mcmc_policy",
    "provenance",
    "readme"
  )
  stopifnot(identical(audit_manifest$label, expected_audit_labels))
  comparison <- utils::read.csv(
    file.path(audit$out_dir, "phase135_matched_exal_vs_source_al_vb_comparison.csv"),
    stringsAsFactors = FALSE
  )
  decision <- utils::read.csv(file.path(audit$out_dir, "phase135_result_decision.csv"), stringsAsFactors = FALSE)
  mcmc_policy <- utils::read.csv(file.path(audit$out_dir, "phase135_gamma_mcmc_policy.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(comparison) == 16L)
  stopifnot(sum(comparison$comparison_class == "joint") == 8L)
  stopifnot(sum(comparison$comparison_class == "independent") == 8L)
  stopifnot(all(comparison$target_exal_model_id %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")))
  stopifnot(all(comparison$source_al_model_id %in% c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb")))
  stopifnot(all(is.finite(comparison$fit_delta_exal_minus_al)))
  stopifnot(all(is.finite(comparison$forecast_delta_exal_minus_al)))
  stopifnot(all(comparison$exal_forecast_raw_crossings == 0L))
  stopifnot(all(comparison$exal_forecast_contract_crossings == 0L))
  stopifnot(decision$audit_gate[[1L]] == "pass")
  stopifnot(decision$article_promotion_gate[[1L]] == "review")
  stopifnot(decision$article_update_recommendation[[1L]] == "do_not_update_article_tables_from_phase135_vb")
  stopifnot(grepl("gamma_mixing", decision$mcmc_promotion_recommendation[[1L]], fixed = TRUE))
  stopifnot(nrow(mcmc_policy) >= 4L)
  stopifnot(!any(mcmc_policy$launched_in_phase135))
}

cat("joint_exqdesn_phase135_matched_spec_readiness tests passed\n")
