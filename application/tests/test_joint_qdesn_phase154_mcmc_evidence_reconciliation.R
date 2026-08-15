repo_root <- normalizePath(file.path(dirname(normalizePath(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
))), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R"
)) source(app_path("application/R", path))

targets <- app_read_csv(file.path(
  app_joint_qdesn_phase154_default_phase153_readiness_dir(),
  "frozen_case_model_controls.csv"
))
sources <- list(
  phase122_existing = app_joint_qdesn_phase154_load_mcmc_source(
    "phase122_existing",
    app_joint_qdesn_phase154_default_phase122_dir()
  ),
  phase124c_completion = app_joint_qdesn_phase154_load_mcmc_source(
    "phase124c_completion",
    app_joint_qdesn_phase154_default_phase124c_dir()
  ),
  phase150_joint_exal = app_joint_qdesn_phase154_load_mcmc_source(
    "phase150_joint_exal",
    app_joint_qdesn_phase154_default_phase150_dir()
  )
)
evidence_a <- app_joint_qdesn_phase154_build_coverage(targets, sources)
evidence_b <- app_joint_qdesn_phase154_build_coverage(targets, sources)
stopifnot(identical(evidence_a$coverage, evidence_b$coverage))
stopifnot(nrow(evidence_a$coverage) == 32L)
stopifnot(all(evidence_a$coverage$exact_control_match))
stopifnot(all(evidence_a$coverage$implementation_reusable))
stopifnot(sum(evidence_a$coverage$action == "reuse_article_grade") == 8L)
stopifnot(sum(evidence_a$coverage$action == "rerun_article_grade") == 24L)
stopifnot(all(
  evidence_a$coverage$model_id[
    evidence_a$coverage$action == "reuse_article_grade"
  ] == "joint_exqdesn_rhs_vb"
))

policy <- app_joint_qdesn_phase154_model_policy()
stopifnot(nrow(policy) == 4L)
stopifnot(
  policy$required_n_chains[policy$model_id == "joint_qdesn_rhs_vb"] == 4L
)
stopifnot(
  policy$required_n_chains[policy$model_id == "joint_exqdesn_rhs_vb"] == 8L
)

tmp_readiness <- tempfile("phase154_readiness_")
tmp_freeze <- tempfile("phase154_freeze_")
prepared <- app_joint_qdesn_phase154_prepare(
  out_dir = tmp_readiness,
  freeze_dir = tmp_freeze,
  verify_source_manifests = FALSE
)
stopifnot(prepared$readiness$gate_status[[1L]] == "pass")
stopifnot(prepared$readiness$article_grade_reuse_cells[[1L]] == 8L)
stopifnot(prepared$readiness$article_grade_rerun_cells[[1L]] == 24L)
stopifnot(nrow(app_read_csv(file.path(
  tmp_freeze,
  "case_winner_controls.csv"
))) == 24L)
stopifnot(all(app_joint_qdesn_phase154_verify_source(
  tmp_readiness,
  "phase154_test_readiness"
)$verified))
stopifnot(all(app_joint_qdesn_phase154_verify_source(
  tmp_freeze,
  "phase154_test_freeze"
)$verified))

loaded_freeze <- app_joint_qdesn_phase122_load_phase121(tmp_freeze)
stopifnot(nrow(loaded_freeze$controls) == 24L)
stopifnot(all(loaded_freeze$manifest_verification$status == "pass"))

launch_plan <- app_joint_qdesn_phase154_launch_plan(
  freeze_dir = tmp_freeze,
  fixture_dir = app_joint_qdesn_default_simulation_fixture_dir()
)
stopifnot(nrow(launch_plan) == 3L)
stopifnot(sum(launch_plan$n_cases) == 24L)
stopifnot(
  launch_plan$n_chains[
    launch_plan$model_id == "exqdesn_rhs_independent_vb"
  ] == 8L
)
stopifnot(all(grepl(
  "125_run_joint_qdesn_phase122_mcmc_case_confirmation",
  launch_plan$command,
  fixed = TRUE
)))

tmp_orchestration <- tempfile("phase154_health_")
test_session_names <- paste0(
  "joint_qdesn_phase154_test_",
  Sys.getpid(),
  "_",
  c("joint_al", "independent_al", "independent_exal")
)
health <- app_joint_qdesn_phase154_health(
  orchestration_dir = tmp_orchestration,
  final_dir = tempfile("phase154_final_"),
  session_names = test_session_names
)
stopifnot(health$summary$lifecycle_state[[1L]] == "prepared_not_running")
stopifnot(health$summary$cases_remaining[[1L]] == 24L)

cat("Joint QDESN Phase154 MCMC evidence-reconciliation tests passed.\n")
