repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase145 test.", call. = FALSE)
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
source(app_path("application/R/joint_exqdesn_phase145_gamma_sampler_root_cause.R"))

specs <- app_joint_exqdesn_phase145_variant_specs()
stopifnot(nrow(specs) == 6L)
stopifnot(any(specs$gamma_refresh_block == "sigma"))
stopifnot(any(specs$gamma_refresh_block == "sigma_s"))
stopifnot(any(specs$gamma_init_mode == "support_grid"))
stopifnot(any(specs$gamma_slice_max_steps == 500L))
subset_specs <- app_joint_exqdesn_phase145_select_variant_specs(c(
  "phase145_logit_w4_vb_local",
  "phase145_logit_w4_vb_refresh3_sigma_s"
))
stopifnot(nrow(subset_specs) == 2L)
stopifnot(identical(subset_specs$phase136_variant_id, c(
  "phase145_logit_w4_vb_local",
  "phase145_logit_w4_vb_refresh3_sigma_s"
)))

selected <- data.frame(
  case_id = "student_t_location_scale__joint_exqdesn_rhs_vb",
  scenario_ids = "student_t_location_scale",
  model_ids = "joint_exqdesn_rhs_vb",
  stringsAsFactors = FALSE
)
registry <- app_joint_exqdesn_phase145_variant_registry(selected)
stopifnot(nrow(registry) == 6L)
stopifnot(any(registry$phase136_variant_id == "phase145_logit_w4_vb_refresh5_sigma"))
stopifnot(any(registry$gamma_refresh_repeats == 5L))
stopifnot(!anyDuplicated(registry$phase136_case_variant_id))

trace_summary <- data.frame(
  case_id = rep("case_a", 8L),
  scenario_id = rep("student_t_location_scale", 8L),
  model_id = rep("joint_exqdesn_rhs_mcmc", 8L),
  phase136_variant_id = rep("variant_a", 8L),
  gamma_update = rep("logit_slice", 8L),
  gamma_refresh_repeats = rep(3L, 8L),
  gamma_refresh_block = rep("sigma", 8L),
  gamma_init_mode = rep("vb_jittered", 8L),
  gamma_jitter_fraction = rep(0.02, 8L),
  chain_id = rep(1:4, 2L),
  tau = rep(0.05, 8L),
  parameter = rep(c("gamma", "sigma"), each = 4L),
  mean = c(4, 5, 6, 7, 0.20, 0.15, 0.10, 0.05),
  sd = rep(0.1, 8L),
  first = c(4, 5, 6, 7, 0.20, 0.15, 0.10, 0.05),
  last = c(4.1, 5.1, 6.1, 7.1, 0.19, 0.14, 0.09, 0.04),
  stringsAsFactors = FALSE
)
memory <- app_joint_exqdesn_phase145_gamma_chain_memory_summary(trace_summary)
ridge <- app_joint_exqdesn_phase145_gamma_sigma_ridge_summary(trace_summary)
tail <- app_joint_exqdesn_phase145_tail_region_summary(trace_summary)
stopifnot(nrow(memory) == 1L)
stopifnot(abs(memory$gamma_mean_gap[[1L]] - 3) < 1.0e-12)
stopifnot(nrow(ridge) == 1L)
stopifnot(ridge$gamma_sigma_chain_mean_cor[[1L]] < -0.99)
stopifnot(nrow(tail) == 1L)

lean_trace <- trace_summary[, c(
  "case_id", "scenario_id", "model_id", "phase136_variant_id", "chain_id",
  "tau", "parameter", "mean", "sd", "first", "last"
), drop = FALSE]
names(lean_trace)[names(lean_trace) == "phase136_variant_id"] <- "variant_id"
lean_memory <- app_joint_exqdesn_phase145_gamma_chain_memory_summary(lean_trace)
lean_ridge <- app_joint_exqdesn_phase145_gamma_sigma_ridge_summary(lean_trace)
stopifnot(nrow(lean_memory) == 1L)
stopifnot(identical(lean_memory$phase136_variant_id[[1L]], "variant_a"))
stopifnot(nrow(lean_ridge) == 1L)

required_dirs <- c(
  app_path("application/cache/joint_qdesn_phase135_matched_exal_screening_20260715"),
  app_path("application/cache/joint_qdesn_phase135_matched_exal_screening_20260715/phase135_result_audit"),
  app_path("application/cache/joint_qdesn_simulation_dgp_fixtures_20260706")
)
if (!all(dir.exists(required_dirs))) {
  cat("Skipping real-artifact Phase145 dry-run test because local Phase135/fixture artifacts are absent.\n")
  quit(status = 0)
}

out_dir <- tempfile("joint_exqdesn_phase145_")
result <- app_joint_exqdesn_run_phase145_gamma_sampler_root_cause_screen(
  out_dir = out_dir,
  n_chains = 2L,
  mcmc_n_iter = 20L,
  mcmc_burn = 10L,
  mcmc_thin = 2L,
  n_cores = 2L,
  vb_n_cores = 1L,
  dry_run = TRUE
)

stopifnot(dir.exists(result$out_dir))
stopifnot(identical(result$decision$gate_status[[1L]], "dry_run"))
stopifnot(nrow(result$variant_registry) == 6L)
required_outputs <- c(
  "run_config.csv",
  "phase136_variant_registry.csv",
  "phase145_variant_registry.csv",
  "gamma_chain_memory_summary.csv",
  "gamma_sigma_ridge_summary.csv",
  "tail_gamma_region_summary.csv",
  "phase145_decision_summary.csv",
  "README_phase145.md",
  "artifact_manifest.csv"
)
stopifnot(all(file.exists(file.path(result$out_dir, required_outputs))))
manifest <- app_joint_qdesn_phase108_manifest_verify(result$out_dir, "phase145")
stopifnot(all(manifest$status == "pass"))

cat("Joint exQDESN Phase145 gamma sampler root-cause tests passed.\n")
