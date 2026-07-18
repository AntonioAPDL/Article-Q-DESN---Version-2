repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for Joint exQDESN Phase140 test.", call. = FALSE)
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
source(app_path("application/R/joint_exqdesn_phase140_gamma_redesign_readiness.R"))

write_phase139_like_manifest <- function(paths, dir) {
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(manifest, file.path(dir, "artifact_manifest.csv"))
}

make_phase139_like_artifact <- function(dir) {
  app_ensure_dir(dir)
  run_config <- data.frame(
    run_id = "fake_phase139",
    phase135_screening_dir = "application/cache/fake_phase135_screening",
    phase135_audit_dir = "application/cache/fake_phase135_audit",
    stringsAsFactors = FALSE
  )
  decision <- data.frame(
    phase139_decision = "review_do_not_promote_exal_as_article_winner",
    article_promotion_gate = "review",
    stringsAsFactors = FALSE
  )
  health <- data.frame(
    check = c("manifest_verification", "worker_failures", "contract_crossings"),
    status = c("pass", "pass", "pass"),
    observed = c("all pass", "0", "0"),
    stringsAsFactors = FALSE
  )
  exal_vs_al <- data.frame(
    case_id = c("case_a", "case_b", "case_c"),
    scenario_id = c("normal_bridge", "regime_shift", "persistent_heavy_tail"),
    comparison_class = c("joint", "joint", "independent"),
    source_model_id = c("joint_exqdesn_rhs_vb", "joint_exqdesn_rhs_vb", "indep_exqdesn_rhs_vb"),
    phase138_model_id = c("joint_exqdesn_rhs_mcmc", "joint_exqdesn_rhs_mcmc", "indep_exqdesn_rhs_mcmc"),
    phase138_group_id = c("logit_w4", "logit_w4", "bounded_w4"),
    gamma_update = c("logit_slice", "logit_slice", "bounded_slice"),
    phase138_mcmc_minus_matched_al_forecast_mae = c(0.12, 0.05, -0.02),
    phase138_mcmc_minus_matched_al_fit_mae = c(0.04, 0.01, -0.01),
    stringsAsFactors = FALSE
  )
  vs136 <- data.frame(
    case_id = c("case_a", "case_b"),
    delta_forecast_mae_phase138_minus_phase136 = c(-0.01, 0.02),
    stringsAsFactors = FALSE
  )
  sampler <- data.frame(
    case_id = c("case_a", "case_b", "case_c"),
    max_gamma_rhat = c(1.22, 1.05, 1.01),
    min_gamma_rough_ess_total = c(30, 180, 240),
    max_gamma_lag1_autocorrelation = c(0.98, 0.90, 0.70),
    sampler_gate = c("review", "review", "pass"),
    stringsAsFactors = FALSE
  )
  redesign <- data.frame(
    step = "fixed_gamma_zero_sensitivity",
    status = "recommended",
    stringsAsFactors = FALSE
  )
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(dir, "run_config.csv")),
    phase139_decision_summary = app_joint_qvp_write_csv(decision, file.path(dir, "phase139_decision_summary.csv")),
    phase139_health_summary = app_joint_qvp_write_csv(health, file.path(dir, "phase139_health_summary.csv")),
    phase139_exal_vs_matched_al = app_joint_qvp_write_csv(exal_vs_al, file.path(dir, "phase139_exal_vs_matched_al.csv")),
    phase139_phase138_vs_phase136 = app_joint_qvp_write_csv(vs136, file.path(dir, "phase139_phase138_vs_phase136.csv")),
    phase139_sampler_diagnostic_summary = app_joint_qvp_write_csv(sampler, file.path(dir, "phase139_sampler_diagnostic_summary.csv")),
    phase139_next_model_redesign_plan = app_joint_qvp_write_csv(redesign, file.path(dir, "phase139_next_model_redesign_plan.csv"))
  )
  write_phase139_like_manifest(paths, dir)
  invisible(dir)
}

set.seed(140)
y <- sin(seq_len(24) / 3) + stats::rnorm(24, sd = 0.03)
Z <- cbind(x = scale(seq_len(24))[, 1])
tau <- c(0.10, 0.50, 0.90)
fit <- app_joint_qvp_fit_exal_mcmc_tiny(
  y = y,
  Z = Z,
  tau = tau,
  n_iter = 18,
  burn = 8,
  thin = 2,
  seed = 1401,
  gamma_update = "fixed",
  gamma_init = rep(0, length(tau)),
  init = list(
    gamma = rep(0, length(tau)),
    sigma = rep(max(stats::sd(y), 0.1), length(tau)),
    alpha = as.numeric(stats::quantile(y, probs = tau, names = FALSE, type = 8)),
    beta = rep(0, length(tau) * ncol(Z))
  )
)
stopifnot(identical(fit$gamma_update, "fixed"))
stopifnot(all(is.finite(fit$gamma_draws)))
stopifnot(max(abs(fit$gamma_draws)) < 1.0e-12)
stopifnot(all(is.finite(fit$qhat_mean)))

selected_cases <- data.frame(
  case_id = "case_a",
  scenario_id = "normal_bridge",
  source_model_id = "joint_exqdesn_rhs_vb",
  stringsAsFactors = FALSE
)
variants <- app_joint_exqdesn_phase136_variant_registry(selected_cases, variant_ids = "fixed_zero")
stopifnot(nrow(variants) == 1L)
stopifnot(identical(variants$phase136_variant_id[[1L]], "fixed_zero"))
stopifnot(identical(variants$gamma_update[[1L]], "fixed"))
stopifnot(identical(variants$phase136_variant_role[[1L]], "fixed_gamma_zero_near_al_sensitivity"))

root <- tempfile("joint_exqdesn_phase140_")
phase139_dir <- file.path(root, "phase139")
out_dir <- file.path(root, "phase140")
make_phase139_like_artifact(phase139_dir)

result <- app_joint_exqdesn_run_phase140_gamma_redesign_readiness(
  out_dir = out_dir,
  phase139_dir = phase139_dir,
  n_chains = 2,
  mcmc_n_iter = 60,
  mcmc_burn = 20,
  mcmc_thin = 2,
  mcmc_seed_offset = 14000
)

stopifnot(dir.exists(result$out_dir))
stopifnot(identical(result$decision$phase140_decision[[1L]], "ready_to_launch_fixed_gamma_zero_sensitivity"))
stopifnot(identical(result$launch_plan$variant_ids[[1L]], "fixed_zero"))
stopifnot(identical(result$launch_plan$gamma_update[[1L]], "fixed"))
stopifnot(result$launch_plan$n_cases[[1L]] == 2L)
stopifnot(result$launch_plan$total_chain_jobs[[1L]] == 4L)
stopifnot(grepl("--variant-ids fixed_zero", result$launch_plan$command[[1L]], fixed = TRUE))
stopifnot(grepl("--dry-run false", result$launch_plan$command[[1L]], fixed = TRUE))

required_outputs <- c(
  "run_config.csv",
  "phase139_manifest_verification.csv",
  "phase140_case_priority.csv",
  "phase140_method_feasibility.csv",
  "phase140_fixed_gamma_launch_plan.csv",
  "phase140_decision_summary.csv",
  "phase140_launch_commands.txt",
  "provenance.csv",
  "README.md",
  "artifact_manifest.csv"
)
stopifnot(all(file.exists(file.path(result$out_dir, required_outputs))))
manifest <- app_joint_qdesn_phase108_manifest_verify(result$out_dir, "phase140")
stopifnot(nrow(manifest) >= length(required_outputs) - 1L)
stopifnot(all(manifest$status == "pass"))

cat("Joint exQDESN Phase140 gamma-redesign readiness tests passed.\n")
