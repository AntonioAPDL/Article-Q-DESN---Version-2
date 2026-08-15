repo_root <- normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_exqdesn_phase136_gamma_kernel_packet.R",
  "joint_exqdesn_phase148_target_invariance.R",
  "joint_exqdesn_phase149_case_specific_screening.R"
)) source(app_path("application/R", path))

registry <- app_joint_exqdesn_phase149_build_registry(
  screening_dir = tempfile("phase149_screen_")
)
stopifnot(length(unique(registry$scenario_ids)) == 8L)
stopifnot(nrow(registry) == 96L)
stopifnot(all(table(registry$scenario_ids) == 12L))
stopifnot(all(registry$model_ids == "joint_exqdesn_rhs_vb"))
stopifnot(all(registry$phase149_no_global_specification))
stopifnot(!anyDuplicated(registry$candidate_id))
app_joint_qdesn_validate_screening_registry(registry)

for (scenario_id in unique(registry$scenario_ids)) {
  block <- registry[registry$scenario_ids == scenario_id, , drop = FALSE]
  stopifnot(all(c(
    "phase121_reference", "prior_best_reference", "matched_al_reference",
    "tau0_lower", "tau0_upper", "zeta2_lower", "zeta2_upper",
    "alpha_sd_lower", "alpha_sd_upper", "gamma_init_zero",
    "gamma_init_half", "gamma_init_default"
  ) %in% block$phase149_role))
}

toy_forecast <- data.frame(
  candidate_id = paste0("c", 1:4),
  scenario_id = rep(c("s1", "s2"), each = 2),
  gate_status = "pass",
  truth_mae = c(0.10, 0.101, 0.20, 0.24),
  truth_rmse = c(0.11, 0.111, 0.21, 0.25),
  check_loss_mean = c(0.2, 0.19, 0.3, 0.31),
  raw_crossing_pairs = 0,
  contract_crossing_pairs = 0,
  reached_max_iter = c(0, 1, 0, 0),
  max_abs_adjustment = 0,
  stringsAsFactors = FALSE
)
toy_fit <- toy_forecast
toy_model <- data.frame(
  candidate_id = paste0("c", 1:4),
  crps_grid_mean = 1:4,
  abs_hit_rate_error = 0,
  abs_coverage_error = 0,
  elapsed_seconds = 1,
  stringsAsFactors = FALSE
)
ranking <- app_joint_exqdesn_phase149_rank_candidates(toy_forecast, toy_fit, toy_model)
shortlist <- app_joint_exqdesn_phase149_shortlist(ranking)
stopifnot(all(c("s1", "s2") %in% shortlist$scenario_id))
stopifnot("c1" %in% shortlist$candidate_id)
stopifnot(!"c4" %in% shortlist$candidate_id)

cat("Joint exQDESN Phase149 case-specific screening tests passed.\n")
