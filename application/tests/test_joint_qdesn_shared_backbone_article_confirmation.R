#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "..", "scripts", "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))

legacy_contract_table <- app_read_csv(app_joint_article_contract_path())
muscat_contract <- app_joint_article_read_contract(
  app_joint_article_muscat_corrected_contract_path()
)
legacy_contract_table$value[legacy_contract_table$name == "source_worktree"] <-
  muscat_contract$source_worktree
legacy_contract_table <- rbind(legacy_contract_table, data.frame(
  section = "identity",
  name = "execution_branch",
  value = app_joint_article_git_value(c("rev-parse", "--abbrev-ref", "HEAD")),
  type = "character",
  description = "Portable test fixture execution branch.",
  stringsAsFactors = FALSE
))
contract_path <- tempfile("joint_article_confirmation_contract_", fileext = ".csv")
app_write_csv(legacy_contract_table, contract_path)
contract <- app_joint_article_read_contract(contract_path)
source_root <- app_joint_article_default_source_runtime(contract)

# Host and capacity behavior has dedicated contract tests. This legacy planning
# fixture exercises the scientific graph against the immutable Muscat evidence.
original_host_preflight <- app_joint_article_host_preflight
app_joint_article_host_preflight <- function(contract, profile = NULL, ...) {
  data.frame(host = "portable_test_fixture", production_launched = FALSE,
    stringsAsFactors = FALSE)
}
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

source <- app_joint_article_verify_source(source_root = source_root, contract = contract)
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
prep <- app_joint_article_prepare(
  out_dir = root, source_root = source_root, contract_path = contract_path,
  force = TRUE, dry_run = TRUE
)
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

prep_reuse <- app_joint_article_prepare(
  out_dir = root, source_root = source_root, contract_path = contract_path,
  dry_run = TRUE
)
stopifnot(isTRUE(prep_reuse$reused))
app_joint_article_host_preflight <- original_host_preflight

manifest_check <- app_joint_shared_verify_manifest(root, file.path(root, "artifact_manifest.csv"))
stopifnot(all(manifest_check$verified))
status_path <- file.path(root, "atomic_status_test.csv")
app_joint_article_atomic_write_csv(data.frame(a = 1L, status = "pass"), status_path)
stopifnot(file.exists(status_path), app_read_csv(status_path)$status[[1L]] == "pass")
refreshed_health <- app_joint_article_refresh_mcmc_queue_health(root)$summary
queue_health <- app_read_csv(file.path(root, "mcmc_queue_health.csv"))
stopifnot(
  identical(refreshed_health$expected_workers, queue_health$expected_workers),
  identical(refreshed_health$completed_workers, queue_health$completed_workers),
  identical(refreshed_health$failed_workers, queue_health$failed_workers),
  identical(refreshed_health$remaining_workers, queue_health$remaining_workers)
)

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
  length(start1$fits[[1L]]$beta_mean) == 2L,
  length(start1$fits[[1L]]$alpha_mean) == 1L,
  length(start1$fits[[1L]]$sigma_mean) == 1L,
  all(start1$sigma_mean > 0),
  all(is.finite(start1$gamma_mean))
)

audit_job <- exal_jobs[exal_jobs$fit_structure == "joint", , drop = FALSE][1, ,
  drop = FALSE]
audit_design <- readRDS(audit_job$design_path[[1L]])
audit_p <- ncol(audit_design$Z)
audit_K <- length(audit_design$tau)
audit_rows <- app_joint_qdesn_bind_rows(list(
  data.frame(
    model_cell_id = audit_job$model_cell_id[[1L]],
    parameter_block = "beta",
    parameter_index = seq_len(audit_K * audit_p),
    value = rep(0.05, audit_K * audit_p),
    stringsAsFactors = FALSE
  ),
  data.frame(
    model_cell_id = audit_job$model_cell_id[[1L]],
    parameter_block = "alpha",
    parameter_index = seq_len(audit_K),
    value = seq(-0.5, 0.5, length.out = audit_K),
    stringsAsFactors = FALSE
  ),
  data.frame(
    model_cell_id = audit_job$model_cell_id[[1L]],
    parameter_block = "sigma",
    parameter_index = seq_len(audit_K),
    value = rep(1, audit_K),
    stringsAsFactors = FALSE
  ),
  data.frame(
    model_cell_id = audit_job$model_cell_id[[1L]],
    parameter_block = "gamma",
    parameter_index = seq_len(audit_K),
    value = rep(0, audit_K),
    stringsAsFactors = FALSE
  )
))
al_audit_job <- mcmc_plan[
  mcmc_plan$likelihood_family == "AL" & mcmc_plan$fit_structure == "joint",
  , drop = FALSE
][1, , drop = FALSE]
al_audit_rows <- app_joint_qdesn_bind_rows(list(
  data.frame(
    model_cell_id = al_audit_job$model_cell_id[[1L]],
    parameter_block = "beta", parameter_index = seq_len(audit_K * audit_p),
    value = rep(0.05, audit_K * audit_p), stringsAsFactors = FALSE
  ),
  data.frame(
    model_cell_id = al_audit_job$model_cell_id[[1L]],
    parameter_block = "alpha", parameter_index = seq_len(audit_K),
    value = seq(-0.5, 0.5, length.out = audit_K), stringsAsFactors = FALSE
  ),
  data.frame(
    model_cell_id = al_audit_job$model_cell_id[[1L]],
    parameter_block = "sigma", parameter_index = seq_len(audit_K),
    value = rep(1, audit_K), stringsAsFactors = FALSE
  )
))
app_write_csv(app_joint_qdesn_bind_rows(list(audit_rows, al_audit_rows)),
  file.path(root, "vb_initialization_rows.csv"))
gaussian_job <- app_joint_article_find_job(
  vb_plan, audit_job$scenario_id[[1L]], "gaussian_rhs_initializer"
)
gaussian_worker_dir <- app_joint_article_vb_worker_dir(
  root, gaussian_job$job_id[[1L]]
)
app_ensure_dir(gaussian_worker_dir)
saveRDS(list(initializer = list(
  zeta2 = 1,
  alpha_mean = seq(-1, 1, length.out = audit_K),
  alpha_prior_sd = rep(1, audit_K)
)), file.path(gaussian_worker_dir, "fit_initializer.rds"), version = 3L)
start_preflight <- app_joint_article_mcmc_start_preflight(
  root, audit_job$worker_id[[1L]]
)
initial_precision <- app_joint_article_mcmc_initial_precision_audit(
  root, audit_job$worker_id[[1L]]
)
stopifnot(
  nrow(start_preflight) == audit_K,
  all(start_preflight$status == "pass"),
  nrow(initial_precision) == 1L,
  initial_precision$status[[1L]] == "pass"
)
al_start_preflight <- app_joint_article_mcmc_start_preflight(
  root, al_audit_job$worker_id[[1L]]
)
al_initial_precision <- app_joint_article_mcmc_initial_precision_audit(
  root, al_audit_job$worker_id[[1L]]
)
stopifnot(
  nrow(al_start_preflight) == audit_K,
  all(al_start_preflight$likelihood_family == "AL"),
  all(is.na(al_start_preflight$gamma_start)),
  all(al_start_preflight$status == "pass"),
  nrow(al_initial_precision) == 1L,
  al_initial_precision$likelihood_family[[1L]] == "AL",
  al_initial_precision$status[[1L]] == "pass"
)
fake_attempt <- file.path(root, "fake_mcmc_attempt")
fake_worker <- file.path(fake_attempt, "mcmc_workers",
  sprintf("worker_%04d", audit_job$worker_id[[1L]]))
app_ensure_dir(fake_worker)
fake_failure <- cbind(audit_job, data.frame(
  status = "failed",
  error_message = "leading principal minor of order 99 is not positive",
  runtime_seconds = 1,
  recorded_at = "2026-09-08 00:00:00 UTC",
  stringsAsFactors = FALSE
))
app_write_csv(fake_failure, file.path(fake_worker, "failure.csv"))
writeLines("failed", file.path(fake_worker, "FAILED"))
failure_audit <- app_joint_article_write_mcmc_failure_audit(
  root, attempt_dir = fake_attempt
)
stopifnot(
  nrow(failure_audit$failure_inventory) == 1L,
  failure_audit$failure_inventory$failure_class[[1L]] ==
    "numerical_precision_factorization",
  failure_audit$assessment$audit_status[[1L]] ==
    "numerical_precision_failure_localized",
  failure_audit$assessment$numerical_precision_failures[[1L]] == 1L,
  failure_audit$assessment$infrastructure_host_preflight_failures[[1L]] == 0L,
  failure_audit$assessment$failed_joint_exal_workers[[1L]] == 1L,
  failure_audit$assessment$failed_joint_al_workers[[1L]] == 0L,
  failure_audit$assessment$failed_al_workers[[1L]] == 0L,
  failure_audit$assessment$failed_exal_workers[[1L]] == 1L,
  failure_audit$assessment$precision_repair_recommendation[[1L]] ==
    "enable_strict_scale_aware_precision_draw_repair_for_affected_likelihood_paths",
  failure_audit$assessment$start_preflight_failures[[1L]] == 0L,
  isTRUE(failure_audit$assessment$initial_precision_all_pass[[1L]]),
  all(failure_audit$manifest_verification$verified)
)
stopifnot(identical(
  app_joint_article_classify_mcmc_failure(c(
    "Host preflight failed host/profile",
    "leading principal minor is not positive",
    "posterior draw frame contains nonfinite values",
    "artifact manifest hash mismatch",
    "unknown worker error"
  )),
  c(
    "infrastructure_host_preflight",
    "numerical_precision_factorization",
    "nonfinite_model_output",
    "manifest_or_provenance",
    "unclassified"
  )
))

repair_controls <- app_joint_article_mcmc_precision_repair_controls()
stopifnot(
  identical(repair_controls$precision_repair, TRUE),
  repair_controls$precision_repair_start_rel == 1.0e-12,
  repair_controls$precision_repair_max_rel == 1.0e-8,
  repair_controls$precision_repair_growth == 10
)
empty_precision <- data.frame(
  status = character(), backend = character(), dimension = integer(),
  attempt = integer(), jitter_relative = numeric(), jitter_absolute = numeric(),
  diagonal_scale = numeric(), error_message = character(), iteration = integer(),
  min_weight = numeric(), max_weight = numeric(), min_sigma = numeric(),
  max_sigma = numeric(), min_gamma = numeric(), max_gamma = numeric(),
  stringsAsFactors = FALSE
)
repaired_precision <- data.frame(
  status = "repaired", backend = "sparse", dimension = 2L, attempt = 1L,
  jitter_relative = 1.0e-12, jitter_absolute = 1.0e-6,
  diagonal_scale = 1.0e6, error_message = "test", iteration = 4L,
  min_weight = 1, max_weight = 2, min_sigma = 0.5, max_sigma = 1,
  min_gamma = NA_real_, max_gamma = NA_real_, stringsAsFactors = FALSE
)
component_fit <- function(offset, repaired = FALSE) list(
  beta_draws = matrix(c(0.1, 0.2) + offset, ncol = 1L),
  alpha_draws = matrix(c(0, 0.1) + offset, ncol = 1L),
  sigma_draws = matrix(c(1, 1.1), ncol = 1L),
  precision_repair_enabled = TRUE,
  precision_repair_count = if (repaired) 1L else 0L,
  precision_repair_max_rel_used = if (repaired) 1.0e-12 else 0,
  precision_repair_diagnostics = if (repaired) repaired_precision else empty_precision,
  init_source = "test"
)
combined_al <- app_joint_qdesn_phase122_combine_independent_chain(
  list(component_fit(0, TRUE), component_fit(0.1, FALSE)),
  Z = matrix(c(-1, 0, 1), ncol = 1L), tau = c(0.25, 0.75),
  chain_id = 1L, seed = 9L
)
stopifnot(
  isTRUE(combined_al$precision_repair_enabled),
  combined_al$precision_repair_count == 1L,
  combined_al$precision_repair_max_rel_used == 1.0e-12,
  nrow(combined_al$precision_repair_diagnostics) == 1L,
  combined_al$precision_repair_diagnostics$quantile_index[[1L]] == 1L
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
  abs(parity$al_beta_sum[[1L]] - 0.153580785083) < 1e-12,
  abs(parity$al_alpha[[1L]] - 0.234872232129) < 1e-12,
  abs(parity$al_sigma[[1L]] - 0.150875048006) < 1e-12,
  parity$qhat_sha12[[1L]] == "bb2ce98a737d",
  parity$monotone_contract_crossings[[1L]] == 0L,
  parity$primary_score[[1L]] == "dgp_integrated_finite_grid_acrps",
  all(is.finite(as.numeric(unlist(
    parity[, c("al_beta_sum", "al_alpha", "al_sigma")], use.names = FALSE
  ))))
)

cat("JOINT shared-backbone article confirmation tests passed\n")
