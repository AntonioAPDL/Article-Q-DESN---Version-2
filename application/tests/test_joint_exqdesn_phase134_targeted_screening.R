repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase134 test.", call. = FALSE)
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
source(app_path("application/R/joint_exqdesn_phase134_targeted_screening.R"))

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

out_dir <- tempfile("joint_exqdesn_phase134_")
screening_dir <- tempfile("joint_exqdesn_phase134_screen_")
result <- app_joint_exqdesn_run_phase134_targeted_screening_readiness(
  out_dir = out_dir,
  screening_output_dir = screening_dir,
  workers = 3L,
  n_cores_per_worker = 1L
)

manifest <- check_manifest(result$out_dir)
expected_labels <- c(
  "phase134_run_config",
  "phase133b_source_manifest_verification",
  "phase121_source_manifest_verification",
  "phase133b_assessment",
  "phase133b_recommendations",
  "phase134_scenario_diagnosis",
  "phase134_candidate_design_by_case",
  "phase134_candidate_design_by_role",
  "phase134_targeted_exal_screening_registry",
  "phase134_launch_commands",
  "phase134_assessment",
  "provenance",
  "readme"
)
stopifnot(identical(manifest$label, expected_labels))

assessment <- utils::read.csv(file.path(result$out_dir, "phase134_assessment.csv"), stringsAsFactors = FALSE)
registry <- utils::read.csv(file.path(result$out_dir, "phase134_targeted_exal_screening_registry.csv"), stringsAsFactors = FALSE)
scenario <- utils::read.csv(file.path(result$out_dir, "phase134_scenario_diagnosis.csv"), stringsAsFactors = FALSE)
by_case <- utils::read.csv(file.path(result$out_dir, "phase134_candidate_design_by_case.csv"), stringsAsFactors = FALSE)
by_role <- utils::read.csv(file.path(result$out_dir, "phase134_candidate_design_by_role.csv"), stringsAsFactors = FALSE)
commands <- utils::read.csv(file.path(result$out_dir, "phase134_launch_commands.csv"), stringsAsFactors = FALSE)

stopifnot(assessment$implementation_gate[[1L]] == "pass")
stopifnot(assessment$audit_gate[[1L]] == "pass")
stopifnot(assessment$n_target_scenarios[[1L]] == 5L)
stopifnot(nrow(registry) == assessment$n_candidate_rows[[1L]])
stopifnot(length(unique(registry$scenario_ids)) == 5L)
stopifnot(all(registry$model_ids == "joint_exqdesn_rhs_vb"))
stopifnot(any(registry$candidate_role == "phase134_exal_sampler_geometry_candidate"))
stopifnot(any(grepl("nonlinear_reservoir_friendly", registry$scenario_ids)))
stopifnot(all(c("regime_shift", "nonlinear_reservoir_friendly", "normal_bridge", "student_t_location_scale", "laplace_bridge") %in% scenario$scenario_id))
stopifnot(all(scenario$qhat_summary_mae_spread < 0.005))
stopifnot("specification_plus_sampler_geometry" %in% scenario$phase134_primary_diagnosis)
stopifnot(sum(by_case$n_candidates) == nrow(registry))
stopifnot(sum(by_role$n_candidates) == nrow(registry))
stopifnot(any(commands$command_id == "launch_phase134_targeted_screen"))
stopifnot(grepl("123_launch_joint_qdesn_screening_parallel_chunks.sh", commands$command[commands$command_id == "launch_phase134_targeted_screen"]))

app_joint_qdesn_validate_screening_registry(registry, allow_alpha_prior_vectors = FALSE)

cat("joint_exqdesn_phase134_targeted_screening tests passed\n")
