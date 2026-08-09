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
delta <- app_joint_exqdesn_phase174_old_new_diff(old, current)
stopifnot(
  all(delta$row_action[delta$case_id == "a"] == "preserved_al"),
  all(delta$delta_phase174_minus_historical[delta$case_id == "a"] == 0),
  all(delta$row_action[delta$case_id == "b"] == "replaced_exal")
)

manifest_dir <- tempfile("phase171-manifest-")
dir.create(manifest_dir)
artifact <- file.path(manifest_dir, "artifact.csv")
utils::write.csv(data.frame(value = 1), artifact, row.names = FALSE)
manifest <- app_joint_exqdesn_write_manifest(c(artifact = artifact), manifest_dir)
verified <- app_joint_exqdesn_verify_manifest(manifest_dir, "test")
stopifnot(file.exists(manifest$manifest_path), nrow(verified) == 1L, all(verified$status == "pass"))

expect_error(
  app_joint_exqdesn_phase175_promote_staged_assets(staging_dir = manifest_dir, approved = FALSE),
  "approved=TRUE"
)

unlink(c(tmp, manifest_dir), recursive = TRUE, force = TRUE)
cat("joint exQDESN Phase171-175 article confirmation tests passed\n")
