#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts/_joint_qdesn_pure_recursive_bootstrap.R"))

contract <- app_joint_pure_read_contract()
axes <- app_joint_pure_read_axes()
registry <- app_joint_pure_read_registry()
anchors <- app_joint_pure_read_anchors()
stopifnot(
  contract$scenario_count == 8L, contract$max_workers == 15L,
  identical(contract$cpu_affinity_list, "0-14"), nrow(registry) == 8L,
  identical(axes$response_lags, c(1L, 2L, 3L, 5L, 10L)),
  identical(axes$input_scale, c(0.10, 0.25, 0.50)),
  identical(axes$pi_w, c(0.05, 0.10, 0.20)),
  identical(axes$pi_in, c(0.25, 0.50, 1.00)),
  length(axes$reservoir_seed) == 1L,
  sum(anchors$translatable) == 7L,
  !anchors$translatable[anchors$scenario_id == "regime_shift"]
)

translated_anchor <- app_joint_pure_anchor_candidate("normal_bridge", axes, anchors)
stopifnot(
  translated_anchor$D == 3L,
  translated_anchor$n == "16;16;8",
  translated_anchor$retained_state_budget == 40L,
  translated_anchor$alpha == "0.5;0.5;0.5",
  translated_anchor$reservoir_seed == axes$reservoir_seed[[1L]],
  is.null(app_joint_pure_anchor_candidate("regime_shift", axes, anchors))
)

stopifnot(
  identical(app_joint_pure_widths(1L, 24L, "flat"), 24L),
  sum(app_joint_pure_widths(3L, 48L, "flat")) == 48L,
  sum(app_joint_pure_widths(3L, 48L, "tapered")) == 48L
)

dgp <- app_joint_qdesn_load_simulation_registry()
sc <- dgp[dgp$scenario_id == "normal_bridge", , drop = FALSE]
sc$seed <- registry$calibration_seed_base[registry$scenario_id == "normal_bridge"]
sc$seed_role <- "pure_recursive_unit_test"
fixture <- app_joint_qdesn_fixture_from_registry_row(sc)
fixture$registry_row <- sc
selector <- app_joint_pure_selector_fixture(fixture, contract)
stopifnot(
  length(selector$y) == 1000L,
  !any(selector$detailed_split$role == "validation"),
  selector$protected_rows_persisted == 0L
)

candidate <- data.frame(
  candidate_id = "normal_bridge__unit", candidate_role = "unit", scenario_id = "normal_bridge",
  feature_contract = "pure_recursive_v1", design_class = "reservoir", D = 2L,
  n = "4;2", n_tilde = "4", retained_state_budget = 6L, width_shape = "tapered",
  state_reduction = FALSE, response_lags = 3L, exogenous_lags = 0L,
  alpha = "0.5;0.5", rho = "0.9;0.9", pi_w = "0.2;0.2", pi_in = "0.5;0.5",
  input_scale = 0.25, reservoir_seed = axes$reservoir_seed[[1L]], raw_inputs_in_readout = FALSE,
  full_states_all_layers = TRUE, stringsAsFactors = FALSE)
candidate$architecture_signature <- app_joint_pure_architecture_signature(candidate)
design <- app_joint_pure_build_design(selector, candidate, contract, selector = TRUE)
stopifnot(
  ncol(design$X) == 7L, ncol(design$Z) == 6L,
  identical(colnames(design$X)[[1L]], "(Intercept)"),
  all(grepl("^reservoir_", colnames(design$X)[-1L])),
  design$diagnostic$raw_readout_columns == 0L,
  design$diagnostic$protected_rows_loaded == 0L,
  length(design$train_local) == 350L,
  length(design$calibration_local) == 150L
)

ridge <- app_joint_pure_score_fit(selector, candidate, contract, "ridge")
stopifnot(
  ridge$summary$status == "completed",
  ridge$summary$observational_selector == "rolling_origin_recursive_realized_finite_grid_acrps",
  is.finite(ridge$summary$calibration_acrps_mean),
  nrow(ridge$detail) == 150L,
  identical(sort(unique(ridge$detail$horizon)), seq_len(30L)),
  length(unique(ridge$detail$origin_index)) == 5L
)

full <- fixture
full$registry_row <- sc
full_design <- app_joint_pure_full_design(full, candidate, contract)
stopifnot(
  ncol(full_design$Z) == 6L,
  length(full_design$fit_local) == 500L,
  length(full_design$validation_local) == 1000L,
  nrow(full_design$forecast_map) == 990L,
  identical(full_design$feature_contract, "pure_recursive_v1")
)

set.seed(9025L)
n_score <- nrow(full_design$forecast_map)
oracle_response <- matrix(stats::rnorm(20L * n_score), nrow = 20L)
oracle_sorted <- apply(oracle_response, 2L, sort)
oracle_prefix <- apply(oracle_sorted, 2L, cumsum)
toy_oracle <- list(
  sorted_response = oracle_sorted,
  prefix_response = oracle_prefix,
  observed_y = full$y[full_design$forecast_map$full_time_index]
)
path_draws <- app_joint_pure_recursive_path_score_draws(
  full_design, full,
  beta = matrix(0, nrow = 2L, ncol = ncol(full_design$Z) * length(contract$tau)),
  alpha = matrix(rep(stats::qnorm(contract$tau), each = 2L), nrow = 2L),
  uniforms = matrix(stats::runif(2L * n_score), nrow = 2L),
  oracle = toy_oracle, tau = contract$tau,
  weights = c(0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025)
)
stopifnot(
  nrow(path_draws) == 2L,
  all(is.finite(path_draws$origin_marginal_dgp_integrated_acrps)),
  all(path_draws$contract_crossing_pairs == 0L)
)

inventory_path <- tempfile("pure_recursive_inventory_", fileext = ".csv")
app_write_csv(data.frame(
  relative_path = "placeholder", size_bytes = 1,
  sha256 = paste(rep("0", 64L), collapse = ""), stringsAsFactors = FALSE
), inventory_path)
score_contract_path <- tempfile("pure_recursive_score_contract_", fileext = ".csv")
app_write_csv(app_joint_pure_score_contract(repo_root, inventory_path),
  score_contract_path)
score_contract <- app_joint_recursive_read_contract(score_contract_path)
stopifnot(
  score_contract$version == "joint_qdesn_pure_recursive_score_packet_v1",
  score_contract$workers == 15L,
  score_contract$parent_contract_sha256 == app_sha256_file(app_path(
    "application/config/joint_qdesn_recursive_mean_forecast_contract_v3.csv"
  ))
)

profile <- app_joint_article_read_host_profile("jerez_pure_recursive_15core_20260925")
stopifnot(
  profile$initial_concurrency == 15L,
  profile$maximum_concurrency == 15L,
  grepl("joint_pure_desn_recursive_selection_20260925", profile$source_worktree, fixed = TRUE)
)

cat("Pure-recursive JOINT campaign tests passed.\n")
