#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase182_dense_grid_crossing_bootstrap.R"
))

expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}

expect_equal <- function(x, y, message, tolerance = 1e-12) {
  if (!isTRUE(all.equal(x, y, tolerance = tolerance))) {
    stop(message, call. = FALSE)
  }
}

contract <- app_joint_qdesn_phase182_read_contract()
expect_true(contract$expected_final_cells == 32L, "Phase182 cell count changed.")
expect_true(contract$expected_new_workers == 256L, "Phase182 worker count changed.")
expect_true(length(contract$tau) == 19L, "Phase182 dense grid is not nineteen levels.")
expect_equal(contract$tau, seq(0.05, 0.95, by = 0.05),
             "Phase182 dense tau grid changed.")
expect_equal(
  contract$weights_qs,
  c(0.025, rep(0.05, 17L), 0.025),
  "Phase182 trapezoidal weights changed."
)
expect_true(
  contract$dense_grid_authorized &&
    !contract$draw_reuse_allowed_after_grid_change &&
    !contract$retuning_allowed &&
    !contract$article_fixture_selection_allowed,
  "Phase182 source and dense-grid policy changed."
)

registry <- data.frame(
  scenario_id = c("a", "b"),
  enabled = c(TRUE, TRUE),
  tau_grid = c("0.05,0.50,0.95", "0.05,0.50,0.95"),
  stringsAsFactors = FALSE
)
dense <- app_joint_qdesn_phase182_dense_registry_rows(registry, contract$tau)
expect_true(
  all(dense$tau_grid == paste(format(contract$tau, nsmall = 2L), collapse = ",")),
  "Dense registry rows do not preserve the contract tau grid."
)

models <- c(
  "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
)
cells <- app_joint_qdesn_bind_rows(lapply(seq_len(32L), function(ii) {
  model <- models[((ii - 1L) %% 4L) + 1L]
  data.frame(
    cell_index = ii, case_id = paste0("scenario_", ceiling(ii / 4), "__", model),
    mcmc_case_id = paste0("scenario_", ceiling(ii / 4), "__", model),
    scenario_id = paste0("scenario_", ceiling(ii / 4)),
    scenario_ids = paste0("scenario_", ceiling(ii / 4)),
    base_scenario_id = paste0("scenario_", ceiling(ii / 4)),
    source_model_id = model,
    model_id = sub("_vb$", "_mcmc", model),
    display_label = app_joint_qdesn_phase180_model_label(model),
    likelihood_family = if (grepl("exqdesn", model, fixed = TRUE)) "exAL" else "AL",
    fit_structure = if (grepl("independent", model, fixed = TRUE)) "independent" else "joint",
    candidate_id = paste0("candidate_", ii),
    phase178_template_id = paste0("template_", ii),
    variant_id = if (grepl("exqdesn", model, fixed = TRUE)) "exAL" else "AL",
    candidate_role = "test_control",
    design_role = "test_design",
    design_class = "test_design",
    dgp_replicate_id = "dense_test",
    validation_partition = "dense_test",
    vb_max_iter = 10L,
    adaptive_vb_max_iter_grid = "10",
    vb_tol = 1e-4,
    rhs_vb_inner = 1L,
    tau0 = 0.5,
    zeta2 = 16,
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_sd = "0.5",
    alpha_min_spacing = 0,
    gamma_init_policy = "zero",
    review_adjustment_threshold = 0.001,
    max_dense_dim = 300L,
    gamma_slice_width = 4,
    gamma_slice_max_steps = 250L,
    source_control_path = NA_character_,
    source_control_file_sha256 = NA_character_,
    source_control_row_sha256 = paste0("hash_", ii),
    source_action = "dense_grid_refit",
    source_phase = "unit_test",
    source_kind = "phase182_dense_grid_refit",
    stringsAsFactors = FALSE
  )
}))
dirs <- list(chains = file.path(tempdir(), "phase182-test-chains"))
plan_a <- app_joint_qdesn_phase182_worker_plan(cells, dirs, contract)
plan_b <- app_joint_qdesn_phase182_worker_plan(cells, dirs, contract)
expect_equal(plan_a$chain_seed, plan_b$chain_seed,
             "Phase182 chain expansion is not deterministic.")
expect_true(
  nrow(plan_a) == 256L && !anyDuplicated(plan_a$chain_seed) &&
    all(table(plan_a$mcmc_case_id) == 8L) && all(plan_a$n_keep == 5000L),
  "Phase182 worker plan has invalid counts, seeds, or retention."
)
component <- app_joint_qdesn_phase180_component_seed_plan(plan_a, contract$tau)
expect_true(!anyDuplicated(component$component_seed),
            "Phase182 component seeds collide.")
expect_true(
  sum(is.na(component$quantile_index)) ==
    8L * sum(cells$fit_structure == "joint"),
  "Joint Phase182 component seed rows should be one per chain."
)
expect_true(
  sum(!is.na(component$quantile_index)) ==
    8L * 19L * sum(cells$fit_structure == "independent"),
  "Independent Phase182 component seed rows should be one per tau per chain."
)

source_cache <- app_joint_qdesn_phase182_source_cache_root()
if (dir.exists(file.path(
  source_cache, "joint_qdesn_phase181_score_stability_extension_packet_20260826"
))) {
  source <- app_joint_qdesn_phase182_source_audit(
    app_joint_qdesn_phase182_dirs(tempdir(), source_cache), contract
  )
  expect_true(
    nrow(source$registry) == 32L &&
      all(source$control_audit$status == "pass") &&
      all(source$control_audit$desn_or_tau0_changed == FALSE),
    "Phase182 source audit did not recover the frozen 32-cell controls."
  )
}

cat("Phase182 dense-grid crossing tests passed.\n")
