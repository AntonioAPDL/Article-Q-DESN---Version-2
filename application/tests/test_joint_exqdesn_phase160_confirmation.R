repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
}
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R", "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_phase158_fan_audit.R", "joint_exqdesn_phase159_split_rhs_screening.R",
  "joint_exqdesn_phase160_independent_confirmation.R"
)) source(app_path("application/R", file))

registry <- data.frame(
  candidate_id = c("candidate_a", "candidate_b"),
  scenario_ids = c("scenario_a", "scenario_b"), stringsAsFactors = FALSE
)
plan_a <- app_joint_exqdesn_phase160_seed_plan(registry, n_chains = 8L)
plan_b <- app_joint_exqdesn_phase160_seed_plan(registry, n_chains = 8L)
stopifnot(identical(plan_a, plan_b), nrow(plan_a) == 16L, !anyDuplicated(plan_a$chain_seed))
stopifnot(all(table(plan_a$candidate_id) == 8L), all(plan_a$seed_role == "phase160_independent_mcmc_chain"))

tmp <- tempfile("phase160-freeze-")
dir.create(tmp)
freeze_dir <- file.path(tmp, "freeze")
output_dir <- file.path(tmp, "output")
result <- app_joint_exqdesn_phase160_prepare(freeze_dir = freeze_dir, output_dir = output_dir)
stopifnot(result$readiness$gate_status[[1L]] == "pass")
stopifnot(nrow(result$registry) == 2L, nrow(result$plan) == 16L)
stopifnot(all(result$registry$confirmation_role == "independent_eight_chain_candidate"))
stopifnot(all(result$plan$n_iter == 12000L), all(result$plan$burn == 3000L))
stopifnot(all(result$plan$thin == 3L), all(result$plan$n_keep == 3000L))
seed_audit <- read.csv(file.path(freeze_dir, "seed_independence_audit.csv"), check.names = FALSE)
stopifnot(seed_audit$overlaps_with_historical[[1L]] == 0L)
verification <- app_joint_exqdesn_phase158_verify_source(freeze_dir, "phase160_test")
stopifnot(nrow(verification) > 0L, all(verification$status == "pass"))
stopifnot(all(c(
  "run_config.csv", "selected_candidate_registry.csv", "vb_initialization.csv",
  "chain_start_values.csv", "chain_plan.csv", "seed_independence_audit.csv",
  "phase157b_reference.csv", "readiness_assessment.csv", "source_code_snapshot.csv",
  "artifact_manifest.csv"
) %in% list.files(freeze_dir)))
unlink(tmp, recursive = TRUE)

cat("Phase160 independent-confirmation tests passed.\n")
