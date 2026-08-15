repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase142 test.", call. = FALSE)
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
source(app_path("application/R/joint_exqdesn_trace_tools.R"))
source(app_path("application/R/joint_exqdesn_phase136_gamma_kernel_packet.R"))
source(app_path("application/R/joint_exqdesn_phase142_post_geometry_synthesis.R"))

prior <- app_joint_exqdesn_phase136_variant_spec("logit_prior_sd_0p25")
stopifnot(identical(prior$gamma_update[[1L]], "logit_slice"))
stopifnot(identical(prior$gamma_prior_type[[1L]], "logit_normal"))
stopifnot(abs(prior$gamma_prior_sd_eta[[1L]] - 0.25) < 1.0e-12)
stopifnot(abs(prior$gamma_prior_center[[1L]]) < 1.0e-12)

required_dirs <- c(
  app_path("application/cache/joint_qdesn_phase135_matched_exal_screening_20260715"),
  app_path("application/cache/joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718"),
  app_path("application/cache/joint_qdesn_phase141_primary_narrow_gamma_geometry_screen_20260719"),
  app_path("application/cache/joint_qdesn_phase141_focus_width_sensitivity_screen_20260719")
)
if (!all(dir.exists(required_dirs))) {
  cat("Skipping real-artifact Phase142 synthesis test because local Phase135/140/141 artifacts are absent.\n")
  quit(status = 0)
}

out_dir <- tempfile("joint_exqdesn_phase142_")
regularized_dir <- tempfile("joint_exqdesn_phase142_regularized_")
result <- app_joint_exqdesn_run_phase142_post_geometry_synthesis(
  out_dir = out_dir,
  regularized_out_dir = regularized_dir,
  n_cores = 2L
)

stopifnot(dir.exists(result$out_dir))
stopifnot(identical(result$decision$sampled_gamma_geometry_decision[[1L]], "reject_geometry_only_for_article_promotion"))
stopifnot(identical(result$decision$next_stage_decision[[1L]], "prepare_regularized_gamma_screen"))
stopifnot(nrow(result$packet_summary) == 3L)
stopifnot(nrow(result$comparison) == 4L)
stopifnot(sum(result$comparison$focus_beats_fixed_forecast_mae, na.rm = TRUE) == 0L)
stopifnot(nrow(result$registry) == 12L)
stopifnot(all(c("logit_prior_sd_0p25", "logit_prior_sd_0p5", "logit_prior_sd_1p0") %in% result$registry$phase142_variant_id))
stopifnot(grepl("145_run_joint_exqdesn_phase136_gamma_kernel_packet.R", result$launch_plan$command[[1L]], fixed = TRUE))
stopifnot(grepl("logit_prior_sd_0p25,logit_prior_sd_0p5,logit_prior_sd_1p0", result$launch_plan$command[[1L]], fixed = TRUE))

required_outputs <- c(
  "run_config.csv",
  "phase135_manifest_verification.csv",
  "phase140_141_packet_summary.csv",
  "gamma_geometry_decision_table.csv",
  "phase142_decision_summary.csv",
  "phase142_regularized_gamma_registry.csv",
  "phase142_regularized_gamma_launch_plan.csv",
  "phase142_regularized_gamma_launch_command.txt",
  "provenance.csv",
  "README.md",
  "artifact_manifest.csv"
)
stopifnot(all(file.exists(file.path(result$out_dir, required_outputs))))
manifest <- app_joint_qdesn_phase108_manifest_verify(result$out_dir, "phase142")
stopifnot(all(manifest$status == "pass"))

cat("Joint exQDESN Phase142 post-geometry synthesis tests passed.\n")
