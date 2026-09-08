#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "..", "scripts", "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

contract <- app_joint_article_read_contract()
stopifnot(
  identical(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  contract$expected_total_components == 136L,
  contract$expected_top_level_initializers == 32L,
  contract$total_chain_workers == 160L,
  identical(contract$exal_vb_method, "VB1_structured_v"),
  identical(contract$exal_mcmc_method, "M0_v_collapsed_support_logit"),
  identical(contract$primary_score, "dgp_integrated_finite_grid_acrps"),
  !contract$production_launched,
  !contract$desn_or_tau0_screen_allowed,
  !contract$global_specification_selected
)

source <- app_joint_article_verify_source(contract = contract)
stopifnot(
  source$source_git$head[[1L]] == contract$source_head,
  source$source_git$detached[[1L]],
  source$source_git$tracked_status_clean[[1L]],
  all(source$top_hashes$hash_verified),
  all(source$nested$all_verified),
  sum(as.integer(source$health$completed)) == 7560L,
  sum(as.integer(source$health$failed)) == 0L,
  nrow(source$selected) == 8L,
  length(unique(source$selected$architecture_signature)) == 8L,
  nrow(source$aggregate) == 56L,
  nrow(source$contrasts) == 14L,
  nrow(source$future) == 32L,
  !any(app_as_bool_vec(source$future$article_fixture_used_for_selection))
)

root <- tempfile("joint_article_confirmation_test_")
prep <- app_joint_article_prepare(out_dir = root, force = TRUE, dry_run = TRUE)
vb_plan <- prep$vb_plan
cells <- prep$cells
mcmc_plan <- prep$mcmc_plan
component_plan <- app_read_csv(file.path(root, "component_seed_plan.csv"))
stopifnot(
  prep$readiness$production_launched[[1L]] == FALSE,
  nrow(vb_plan) == 136L,
  sum(vb_plan$model_id == "gaussian_rhs_initializer") == 8L,
  sum(vb_plan$model_id == "independent_qdesn_rhs") == 56L,
  sum(vb_plan$model_id == "independent_exqdesn_rhs") == 56L,
  sum(vb_plan$model_id == "joint_qdesn_rhs") == 8L,
  sum(vb_plan$model_id == "joint_exqdesn_rhs") == 8L,
  nrow(cells) == 32L,
  length(unique(cells$scenario_id)) == 8L,
  all(!app_as_bool_vec(cells$article_fixture_used_for_selection)),
  nrow(mcmc_plan) == 160L,
  sum(mcmc_plan$likelihood_family == "AL") == 64L,
  sum(mcmc_plan$likelihood_family == "exAL") == 96L,
  all(mcmc_plan$inference_method_id[mcmc_plan$likelihood_family == "exAL"] ==
    "M0_v_collapsed_support_logit"),
  !anyDuplicated(vb_plan$component_seed),
  !anyDuplicated(mcmc_plan$chain_seed),
  !anyDuplicated(mcmc_plan$chain_start_seed),
  !anyDuplicated(component_plan$component_seed)
)

for (ii in seq_len(nrow(vb_plan))) {
  deps <- app_joint_article_dependency_rows(vb_plan, vb_plan[ii, , drop = FALSE])
  stopifnot(!nrow(deps) || all(deps$stage_order < vb_plan$stage_order[[ii]]))
}
for (scenario_id in unique(vb_plan$scenario_id)) {
  block <- vb_plan[vb_plan$scenario_id == scenario_id, , drop = FALSE]
  stopifnot(
    nrow(block) == 17L,
    sum(block$model_id == "gaussian_rhs_initializer") == 1L,
    sum(block$model_id == "independent_qdesn_rhs") == 7L,
    sum(block$model_id == "independent_exqdesn_rhs") == 7L,
    sum(block$model_id == "joint_qdesn_rhs") == 1L,
    sum(block$model_id == "joint_exqdesn_rhs") == 1L
  )
}
by_scenario <- split(cells, cells$scenario_id)
stopifnot(all(vapply(by_scenario, function(x) {
  length(unique(x$design_fingerprint)) == 1L &&
    length(unique(x$candidate_id)) == 1L &&
    length(unique(x$rhs_tau0)) == 1L
}, logical(1L))))

check <- app_joint_article_check_vb(root)
stopifnot(
  check$summary$gate_status[[1L]] == "pass",
  check$summary$completed_vb_components[[1L]] == 0L,
  check$summary$expected_vb_components[[1L]] == 136L,
  check$summary$mcmc_launch_blocked[[1L]]
)
ready_jobs <- app_joint_article_ready_vb_jobs(root)
stopifnot(length(ready_jobs) == 8L, all(ready_jobs == 1:8))
initial_mcmc_state <- app_joint_article_mcmc_worker_state(root)
stopifnot(
  nrow(initial_mcmc_state) == 160L,
  !any(initial_mcmc_state$done),
  !any(initial_mcmc_state$failed)
)
queue_guard_failed <- inherits(try(app_joint_article_run_vb_queue(root, max_workers = 1L),
  silent = TRUE), "try-error")
stopifnot(queue_guard_failed)
mcmc_queue_guard_failed <- inherits(try(app_joint_article_run_mcmc_queue(root,
  max_workers = 1L), silent = TRUE), "try-error")
stopifnot(mcmc_queue_guard_failed)
guard_failed <- inherits(try(app_joint_article_mcmc_launch_guard(root), silent = TRUE),
  "try-error")
stopifnot(guard_failed)

prep_reuse <- app_joint_article_prepare(out_dir = root, dry_run = TRUE)
stopifnot(isTRUE(prep_reuse$reused))

manifest_check <- app_joint_shared_verify_manifest(root, file.path(root, "artifact_manifest.csv"))
stopifnot(all(manifest_check$verified))
status_path <- file.path(root, "atomic_status_test.csv")
app_joint_article_atomic_write_csv(data.frame(a = 1L, status = "pass"), status_path)
stopifnot(file.exists(status_path), app_read_csv(status_path)$status[[1L]] == "pass")

bad_contract <- contract
bad_contract$source_hashes[["final_decision.csv"]] <- paste(rep("0", 64), collapse = "")
source_failed <- inherits(try(app_joint_article_verify_source(contract = bad_contract),
  silent = TRUE), "try-error")
stopifnot(source_failed)

K <- length(contract$tau)
toy_init <- list(
  beta_mean = rep(0.1, K * 2L),
  alpha_mean = seq(-1, 1, length.out = K),
  sigma_mean = rep(1, K),
  gamma_mean = rep(0, K),
  fits = lapply(seq_len(K), function(k) list(
    beta_mean = c(0.1, 0.1), alpha_mean = seq(-1, 1, length.out = K)[[k]],
    sigma_mean = 1, gamma_mean = 0))
)
exal_jobs <- mcmc_plan[mcmc_plan$likelihood_family == "exAL", , drop = FALSE]
start1 <- app_joint_article_overdispersed_start(toy_init, exal_jobs[1, , drop = FALSE],
  contract$tau)
start2 <- app_joint_article_overdispersed_start(toy_init, exal_jobs[1, , drop = FALSE],
  contract$tau)
start3 <- app_joint_article_overdispersed_start(toy_init, exal_jobs[2, , drop = FALSE],
  contract$tau)
stopifnot(
  identical(start1$beta_mean, start2$beta_mean),
  identical(start1$gamma_mean, start2$gamma_mean),
  !identical(start1$beta_mean, start3$beta_mean),
  all(start1$sigma_mean > 0),
  all(is.finite(start1$gamma_mean))
)

scoring <- app_read_csv(file.path(root, "scoring_contract.csv"))
stopifnot(
  scoring$primary_score[[1L]] == "dgp_integrated_finite_grid_acrps",
  grepl("raw_before_contract", scoring$crossing_diagnostics[[1L]], fixed = TRUE),
  grepl("contract_after_monotone", scoring$crossing_diagnostics[[1L]], fixed = TRUE),
  scoring$gamma_sigma_diagnostics[[1L]] == "retained_for_exal"
)

runtime_paths <- c(
  app_read_csv(file.path(root, "fixture_manifest.csv"))$fixture_path,
  app_read_csv(file.path(root, "design_manifest.csv"))$design_path,
  app_read_csv(file.path(root, "vb_worker_plan.csv"))$design_path
)
stopifnot(
  !any(grepl("/home/", runtime_paths, fixed = TRUE)),
  !any(grepl("tables/", runtime_paths, fixed = TRUE)),
  !any(grepl("figures/", runtime_paths, fixed = TRUE)),
  !any(grepl("manuscript", runtime_paths, fixed = TRUE)),
  !any(grepl("GloFAS", runtime_paths, fixed = TRUE)),
  !any(grepl("PriceFM", runtime_paths, fixed = TRUE))
)

parity <- app_joint_article_parity_fixture()
stopifnot(
  parity$fixture_id[[1L]] == "tiny_api_parity_20260907",
  parity$design_fingerprint[[1L]] ==
    "d65bccb0e0f074b4e251505aa55e22958dade61e20e940c455b5701f4bf0a170",
  parity$beta_length[[1L]] == length(contract$tau) * 2L,
  parity$beta_cov_nrow[[1L]] == length(contract$tau) * 2L,
  parity$alpha_length[[1L]] == length(contract$tau),
  parity$sigma_length[[1L]] == length(contract$tau),
  abs(parity$al_beta_sum[[1L]] - 0.152213091439) < 1e-12,
  abs(parity$al_alpha[[1L]] - 0.235467134628) < 1e-12,
  abs(parity$al_sigma[[1L]] - 0.150980779259) < 1e-12,
  parity$qhat_sha12[[1L]] == "3456dbca657c",
  parity$monotone_contract_crossings[[1L]] == 0L,
  parity$primary_score[[1L]] == "dgp_integrated_finite_grid_acrps",
  all(is.finite(as.numeric(unlist(
    parity[, c("al_beta_sum", "al_alpha", "al_sigma")], use.names = FALSE
  ))))
)

cat("JOINT shared-backbone article confirmation tests passed\n")
