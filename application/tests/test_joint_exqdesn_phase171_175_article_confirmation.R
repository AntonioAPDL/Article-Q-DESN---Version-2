#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)

for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R",
  "joint_qdesn_phase155_article_promotion.R",
  "joint_exqdesn_exact_structured_inference.R", "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R", "joint_exqdesn_phase166_168_structured_vb.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R", "joint_exqdesn_phase169r_recovery.R",
  "joint_exqdesn_phase170_default_promotion.R", "joint_exqdesn_phase171_175_article_confirmation.R"
)) source(app_path("application/R", file))

expect_error <- function(expr, pattern = NULL) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"))
  if (!is.null(pattern)) stopifnot(grepl(pattern, conditionMessage(error), fixed = TRUE))
  invisible(error)
}

registry <- app_joint_exqdesn_phase171_load_registry()
stopifnot(
  nrow(registry) == 16L,
  length(unique(registry$scenario_id)) == 8L,
  setequal(registry$fit_structure, c("joint", "independent")),
  all(registry$inference_method_id == "M0_v_collapsed_support_logit"),
  all(registry$n_chains == 8L),
  all(registry$n_iter == 24000L),
  all(registry$burn == 4000L),
  all(registry$thin == 4L),
  all((registry$n_iter - registry$burn) / registry$thin == 5000L)
)

tmp <- tempfile("phase171-plan-")
dir.create(tmp)
seeds_a <- app_joint_exqdesn_phase171_seed_plan(registry, tmp)
seeds_b <- app_joint_exqdesn_phase171_seed_plan(registry, tmp)
stopifnot(
  identical(seeds_a$plan, seeds_b$plan),
  identical(seeds_a$components, seeds_b$components),
  nrow(seeds_a$plan) == 128L,
  nrow(seeds_a$components) == 512L,
  !anyDuplicated(seeds_a$plan$chain_seed),
  !anyDuplicated(seeds_a$components$component_seed),
  all(table(seeds_a$plan$mcmc_case_id) == 8L),
  all(table(seeds_a$plan$wave_id) == 32L),
  max(seeds_a$components$component_seed) < .Machine$integer.max
)
waves <- app_joint_exqdesn_phase171_wave_plan(seeds_a$plan)
stopifnot(nrow(waves) == 4L, all(waves$status == "pass"), all(waves$worker_count == 32L))
historical <- app_joint_exqdesn_phase171_historical_seed_audit()
stopifnot(
  historical$component_jobs_per_independent_cell[[1L]] == 56L,
  historical$unique_component_seeds_per_independent_cell[[1L]] < 56L,
  historical$duplicated_component_jobs_per_independent_cell[[1L]] > 0L,
  historical$fixed_tau_chain_seeds_unique[[1L]]
)

dirs <- app_joint_exqdesn_phase171_175_dirs()
controls <- app_joint_exqdesn_phase171_load_controls(registry, dirs$cache_root)
control_audit <- app_joint_exqdesn_phase171_control_audit(registry, controls)
stopifnot(nrow(controls) == 16L, !anyDuplicated(controls$mcmc_case_id), all(control_audit$status == "pass"))

artifacts <- app_joint_qdesn_load_fixture_artifacts(dirs$fixture_dir)
fixture_audit <- app_joint_exqdesn_phase171_fixture_audit(artifacts)
stopifnot(
  nrow(fixture_audit) == 9L,
  setequal(fixture_audit$scenario_id[fixture_audit$article_scope == "included"], app_joint_exqdesn_phase171_scenarios()),
  identical(fixture_audit$scenario_id[fixture_audit$article_scope == "excluded"], "heteroskedastic_seasonal"),
  all(fixture_audit$status == "pass")
)

stopifnot(
  identical(app_joint_exqdesn_default_method_id("mcmc"), "M0_v_collapsed_support_logit"),
  identical(app_joint_exqdesn_method_row("M0_v_collapsed_support_logit", "mcmc")$method_id[[1L]], "M0_v_collapsed_support_logit")
)

tau <- c(0.05, 0.5, 0.95)
raw <- matrix(c(0, -1, 2, 0, 1, 2), nrow = 2L, byrow = TRUE)
contract <- app_joint_qdesn_apply_monotone_contract(raw, tau)
stopifnot(
  any(apply(raw, 1L, function(x) any(diff(x) < 0))),
  all(apply(contract$qhat_contract, 1L, function(x) all(diff(x) >= 0)))
)

starts <- app_joint_exqdesn_phase156_chain_starts(
  list(sigma_mean = rep(1, length(tau)), gamma_mean = rep(0, length(tau))),
  tau, "test_case", 8L
)
support <- app_joint_qvp_exal_support(tau)
for (chain_id in seq_len(8L)) {
  gamma <- starts$gamma_init[starts$chain_id == chain_id]
  sigma <- starts$sigma_init[starts$chain_id == chain_id]
  stopifnot(all(is.finite(gamma)), all(is.finite(sigma)), all(sigma > 0), all(gamma > support$lower), all(gamma < support$upper))
}

summary <- data.frame(
  case_id = "scenario__joint_exqdesn_rhs_vb", scenario_id = "scenario",
  fit_structure = "joint", source_model_id = "joint_exqdesn_rhs_vb",
  mcmc_draws_all_finite = TRUE, all_chain_init_source_provided = TRUE,
  mcmc_fit_truth_mae = 0.08, mcmc_forecast_truth_mae = 0.09,
  mcmc_fit_check_loss_mean = 0.10, mcmc_forecast_check_loss_mean = 0.11,
  mcmc_fit_crps_grid_mean = 0.20, mcmc_forecast_crps_grid_mean = 0.21,
  mcmc_fit_raw_crossing_pairs = 0L, mcmc_forecast_raw_crossing_pairs = 0L,
  mcmc_fit_contract_crossing_pairs = 0L, mcmc_forecast_contract_crossing_pairs = 0L,
  stringsAsFactors = FALSE
)
diagnostics <- data.frame(
  case_id = rep(summary$case_id, 2L), parameter = c("beta", "gamma"), tau = c(0.5, 0.5),
  rank_rhat = c(1.00, 1.00), folded_rhat = c(1.00, 1.00),
  bulk_ess = c(1000, 1000), tail_ess = c(800, 800), stringsAsFactors = FALSE
)
partitions <- data.frame(
  case_id = rep(summary$case_id, 4L), status = rep("pass", 4L), stringsAsFactors = FALSE
)
jackknife <- data.frame(
  case_id = summary$case_id, metric = "forecast_truth_mae",
  maximum_absolute_loo_delta = 0.0005, stringsAsFactors = FALSE
)
gate <- app_joint_exqdesn_phase173_assess_cells(summary, diagnostics, partitions, jackknife)
stopifnot(gate$gate_status[[1L]] == "pass")
diagnostics$rank_rhat[diagnostics$parameter == "gamma"] <- 1.06
gate <- app_joint_exqdesn_phase173_assess_cells(summary, diagnostics, partitions, jackknife)
stopifnot(gate$gate_status[[1L]] == "qualified_article_ready")
partitions$status[[1L]] <- "review"
gate <- app_joint_exqdesn_phase173_assess_cells(summary, diagnostics, partitions, jackknife)
stopifnot(gate$gate_status[[1L]] == "review_hold")
partitions$status <- "pass"
summary$mcmc_forecast_contract_crossing_pairs <- 1L
gate <- app_joint_exqdesn_phase173_assess_cells(summary, diagnostics, partitions, jackknife)
stopifnot(gate$gate_status[[1L]] == "fail")

policy <- app_joint_exqdesn_phase173b_load_policy()
stopifnot(
  policy$policy_id[[1L]] == "phase173b_metric_qualified_v1",
  policy$selection_policy[[1L]] == "prospective_M0_with_historical_fallback_only_for_functional_hold_or_hard_fail"
)
assessment173b <- data.frame(
  implementation_status = "pass", leave_one_chain_out_status = "pass",
  readout_severity_status = "pass", multi_tau_shape_severity_status = "pass",
  scalar_mixing_status = "review", raw_crossing_status = "pass",
  stringsAsFactors = FALSE
)
qhat173b <- data.frame(
  q99_standardized_qhat_delta = rep(0.20, 4L),
  q01_central90_overlap_fraction = rep(0.85, 4L),
  stringsAsFactors = FALSE
)
sensitivity173b <- data.frame(
  summary_type = c("mean", "median", "trimmed_mean"),
  forecast_truth_mae = c(0.0900, 0.0905, 0.0902),
  stringsAsFactors = FALSE
)
decision <- app_joint_exqdesn_phase173b_case_decision(
  assessment173b, qhat173b, sensitivity173b,
  historical_forecast_mae = 0.10, m0_forecast_mae = 0.09,
  jackknife_mcse = 0.001, policy = policy
)
stopifnot(
  decision$action[[1L]] == "promote_with_mixing_qualification",
  decision$functional_stability_status[[1L]] == "pass",
  decision$primary_metric_direction[[1L]] == "clear_improvement"
)

qhat_hold <- qhat173b
qhat_hold$q99_standardized_qhat_delta[[1L]] <- 0.60
decision_qhat_hold <- app_joint_exqdesn_phase173b_case_decision(
  assessment173b, qhat_hold, sensitivity173b, 0.10, 0.09, 0.001, policy
)
stopifnot(
  decision_qhat_hold$action[[1L]] == "retain_historical_functional_hold",
  decision_qhat_hold$qhat_functional_status[[1L]] == "hold"
)

sensitivity_reversal <- sensitivity173b
sensitivity_reversal$forecast_truth_mae <- c(0.09, 0.11, 0.10)
decision_summary_hold <- app_joint_exqdesn_phase173b_case_decision(
  assessment173b, qhat173b, sensitivity_reversal, 0.10, 0.09, 0.001, policy
)
stopifnot(
  decision_summary_hold$action[[1L]] == "retain_historical_functional_hold",
  !decision_summary_hold$posterior_summary_direction_consistent[[1L]]
)

assessment_readout <- assessment173b
assessment_readout$readout_severity_status <- "hold"
decision_readout <- app_joint_exqdesn_phase173b_case_decision(
  assessment_readout, qhat173b, sensitivity173b, 0.10, 0.09, 0.001, policy
)
stopifnot(
  decision_readout$action[[1L]] == "promote_with_mixing_qualification",
  decision_readout$readout_functional_status[[1L]] == "review_accepted"
)
qhat_review <- qhat173b
qhat_review$q99_standardized_qhat_delta <- 0.35
qhat_review$q01_central90_overlap_fraction <- 0.75
decision_readout_review <- app_joint_exqdesn_phase173b_case_decision(
  assessment_readout, qhat_review, sensitivity173b, 0.10, 0.09, 0.001, policy
)
stopifnot(
  decision_readout_review$action[[1L]] == "promote_with_mixing_qualification",
  decision_readout_review$qhat_functional_status[[1L]] == "review_accepted",
  decision_readout_review$readout_functional_status[[1L]] == "review_accepted"
)

assessment_fail <- assessment173b
assessment_fail$implementation_status <- "fail"
decision_fail <- app_joint_exqdesn_phase173b_case_decision(
  assessment_fail, qhat173b, sensitivity173b, 0.10, 0.09, 0.001, policy
)
stopifnot(decision_fail$action[[1L]] == "retain_historical_candidate_fail")

decision_worsened <- app_joint_exqdesn_phase173b_case_decision(
  assessment173b, qhat173b,
  transform(sensitivity173b, forecast_truth_mae = forecast_truth_mae + 0.02),
  0.10, 0.11, 0.001, policy
)
stopifnot(
  decision_worsened$action[[1L]] == "promote_with_mixing_qualification",
  decision_worsened$primary_metric_direction[[1L]] == "worsened"
)

old <- data.frame(
  case_id = c("a", "b"), scenario_id = c("s", "s"),
  source_model_id = c("joint_qdesn_rhs_vb", "joint_exqdesn_rhs_vb"),
  mcmc_fit_truth_mae = c(1, 2), mcmc_forecast_truth_mae = c(1, 2),
  mcmc_forecast_check_loss_mean = c(1, 2), mcmc_forecast_crps_grid = c(1, 2),
  mcmc_fit_raw_crossing_pairs = c(0, 0), mcmc_forecast_raw_crossing_pairs = c(0, 0),
  stringsAsFactors = FALSE
)
current <- old
current$mcmc_forecast_truth_mae[[2L]] <- 1.5
current$source_block_id <- c("phase154_joint_al", "phase173_m0_exal")
delta <- app_joint_exqdesn_phase174_old_new_diff(old, current)
stopifnot(
  all(delta$row_action[delta$case_id == "a"] == "preserved_al"),
  all(delta$delta_phase174_minus_historical[delta$case_id == "a"] == 0),
  all(delta$row_action[delta$case_id == "b"] == "replaced_exal_with_qualified_m0")
)

manifest_dir <- tempfile("phase171-manifest-")
dir.create(manifest_dir)
artifact <- file.path(manifest_dir, "artifact.csv")
utils::write.csv(data.frame(value = 1), artifact, row.names = FALSE)
manifest <- app_joint_exqdesn_write_manifest(c(artifact = artifact), manifest_dir)
verified <- app_joint_exqdesn_verify_manifest(manifest_dir, "test")
stopifnot(file.exists(manifest$manifest_path), nrow(verified) == 1L, all(verified$status == "pass"))

wrapper <- file.path(tmp, "portable-wrapper.tex")
writeLines(c(
  "% Generated by application/scripts/187_build_joint_qdesn_phase155_article_assets.R.",
  "\\input{/tmp/phase174-staging/tables/model-summary.tex}"
), wrapper)
invisible(app_joint_exqdesn_phase174_relabel_generated_file(wrapper))
wrapper_lines <- readLines(wrapper, warn = FALSE)
stopifnot(
  any(wrapper_lines == "\\input{tables/model-summary.tex}"),
  !any(grepl("/tmp/phase174-staging", wrapper_lines, fixed = TRUE))
)

expect_error(
  app_joint_exqdesn_phase175_promote_staged_assets(staging_dir = manifest_dir, approved = FALSE),
  "approved=TRUE"
)

launcher_path <- app_path("application/scripts/234_launch_joint_exqdesn_phase172_m0_confirmation.sh")
launcher <- readLines(launcher_path, warn = FALSE)
stopifnot(
  any(grepl("JOINT_EXQDESN_CACHE_ROOT", launcher, fixed = TRUE)),
  any(grepl("--cache-root", launcher, fixed = TRUE)),
  any(grepl('FREEZE="$CACHE_ROOT/', launcher, fixed = TRUE)),
  !any(grepl('FREEZE="$ROOT/application/cache/', launcher, fixed = TRUE))
)

stopifnot(
  file.exists(app_path("application/scripts/238_audit_joint_exqdesn_phase173b_metric_qualified_promotion.R")),
  file.exists(app_path("application/scripts/239_freeze_joint_exqdesn_phase174_integration_handoff.R"))
)

unlink(c(tmp, manifest_dir), recursive = TRUE, force = TRUE)
cat("joint exQDESN Phase171-175 article confirmation tests passed\n")
