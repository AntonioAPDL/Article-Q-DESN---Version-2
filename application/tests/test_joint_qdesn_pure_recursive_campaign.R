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
  identical(contract$cpu_affinity_list, "2-16"), nrow(registry) == 8L,
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
dense_candidate <- candidate
dense_candidate$scenario_id <- "asymmetric_laplace_tail"
dense_candidate$D <- 1L
dense_candidate$n <- "48"
dense_candidate$n_tilde <- ""
dense_candidate$retained_state_budget <- 48L
dense_plan <- app_joint_pure_dense_dimension_audit(
  dense_candidate, contract$tau, base_limit = 300L
)
stopifnot(
  dense_plan$required_joint_beta_dimension == 336L,
  dense_plan$resolved_max_dense_dim == 336L,
  dense_plan$dense_covariance_bytes_estimate == 336^2 * 8
)
dense_contract <- app_joint_pure_apply_dense_dimension_contract(
  app_read_csv(app_joint_shared_quantile_contract_path()), dense_candidate, contract$tau
)
stopifnot(
  as.integer(dense_contract$value[dense_contract$name == "max_dense_dim"]) == 336L,
  as.integer(dense_contract$value[dense_contract$name == "required_joint_beta_dimension"]) == 336L,
  dense_contract$value[dense_contract$name == "dense_dimension_policy"] ==
    "max(base_max_dense_dim,K_times_state_dimension)"
)
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

rhs_candidate <- cbind(candidate, data.frame(
  calibration_acrps_mean = 999, calibration_acrps_between_rep_sd = 0,
  hard_gate_status = "pass", condition_gate_status = "pass", saturation_gate_status = "pass",
  rhs_tau0 = 0.1, replicate_id = 1L, dgp_seed = 9025L, fixture_path = "unit_fixture.rds",
  rhs_worker_id = 1L, rhs_candidate_id = "normal_bridge__unit__tau0_1e-01__rep1",
  advancement_rank = 1L, stringsAsFactors = FALSE
))
rhs <- app_joint_pure_score_fit(selector, rhs_candidate, contract, "rhs")
stopifnot(
  !anyDuplicated(names(rhs$summary)),
  rhs$summary$calibration_acrps_mean != 999,
  rhs$summary$rhs_worker_id == 1L,
  rhs$summary$rhs_tau0 == 0.1
)
legacy_rhs <- cbind(
  rhs$summary[, app_joint_pure_worker_identity_columns("rhs"), drop = FALSE],
  data.frame(hard_gate_status = "pass", condition_gate_status = "review",
    saturation_gate_status = "review", calibration_acrps_mean = 999, stringsAsFactors = FALSE),
  rhs$summary[, app_joint_pure_result_columns(), drop = FALSE]
)
normalized_rhs <- app_joint_pure_normalize_worker_summary(legacy_rhs, "rhs")
stopifnot(
  !anyDuplicated(names(normalized_rhs)),
  identical(names(normalized_rhs), c(app_joint_pure_worker_identity_columns("rhs"), app_joint_pure_result_columns())),
  normalized_rhs$calibration_acrps_mean == rhs$summary$calibration_acrps_mean,
  normalized_rhs$condition_gate_status == rhs$summary$condition_gate_status
)

queue_root <- file.path(tempdir(), paste0("pure_recursive_quantile_queue_", paste(rep("long_path", 12L), collapse = "_")))
dir.create(queue_root, recursive = TRUE, showWarnings = FALSE)
family_rows <- vector("list", 8L)
stage_counts <- app_joint_pure_quantile_stage_counts()
for (family_index in seq_len(8L)) {
  quantile_root <- file.path(queue_root, sprintf("family_%02d", family_index), "quantile_vb")
  dir.create(quantile_root, recursive = TRUE, showWarnings = FALSE)
  worker_plan <- do.call(rbind, lapply(seq_along(stage_counts), function(stage_index) {
    jobs_per_family <- as.integer(stage_counts[[stage_index]]) / 8L
    data.frame(stage_order = stage_index, job_id = seq_len(jobs_per_family) + (stage_index * 100L), stringsAsFactors = FALSE)
  }))
  app_write_csv(worker_plan, file.path(quantile_root, "worker_plan.csv"))
  family_rows[[family_index]] <- data.frame(
    scenario_id = sprintf("family_%02d", family_index), quantile_root = quantile_root,
    stringsAsFactors = FALSE
  )
}
app_write_csv(app_bind_rows_fill(family_rows), file.path(queue_root, "quantile_family_plan.csv"))
queues <- lapply(seq_len(8L), function(stage) app_joint_pure_quantile_job_queue(queue_root, stage))
stopifnot(
  identical(vapply(queues, nrow, integer(1L)), unname(stage_counts)),
  sum(vapply(queues, nrow, integer(1L))) == 408L,
  all(vapply(queues, function(x) all(nchar(x$quantile_root) > 80L), logical(1L))),
  !any(vapply(queues, function(x) anyNA(x$job_id) || any(!nzchar(x$quantile_root)), logical(1L)))
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

confirmation_fixture <- file.path(tempdir(), "pure_recursive_dense_confirmation_contract")
unlink(confirmation_fixture, recursive = TRUE, force = TRUE)
dir.create(confirmation_fixture, recursive = TRUE)
app_write_csv(dense_candidate, file.path(confirmation_fixture, "selected_family_backbones.csv"))
writeLines("fixture", file.path(confirmation_fixture, "quantile_artifact_manifest.csv"))
confirmation_contract <- app_joint_pure_confirmation_contract(confirmation_fixture)
stopifnot(
  as.integer(confirmation_contract$value[confirmation_contract$name == "max_dense_dim"]) == 336L,
  as.integer(confirmation_contract$value[
    confirmation_contract$name == "required_joint_beta_dimension"
  ]) == 336L
)

cell_scenarios <- sprintf("scenario_%02d", seq_len(8L))
cell_map <- app_joint_article_model_map()
ordered_future <- merge(
  data.frame(
    scenario_id = cell_scenarios,
    scenario_order = seq_along(cell_scenarios),
    article_fixture_used_for_selection = FALSE,
    stringsAsFactors = FALSE
  ),
  cell_map[, "model_id", drop = FALSE],
  by = NULL
)
cell_designs <- data.frame(
  scenario_order = seq_along(cell_scenarios), scenario_id = cell_scenarios,
  design_path = paste0("design_", seq_along(cell_scenarios), ".rds"),
  design_fingerprint = paste0("fingerprint_", seq_along(cell_scenarios)),
  p = 6L, fit_rows = 500L, validation_rows = 1000L,
  scored_forecast_rows = 990L, stringsAsFactors = FALSE
)
ordered_cells <- app_joint_article_build_model_cells(
  ordered_future, cell_designs,
  list(expected_top_level_initializers = 32L)
)
legacy_future <- ordered_future
legacy_future$scenario_order <- NULL
legacy_cells <- app_joint_article_build_model_cells(
  legacy_future, cell_designs,
  list(expected_top_level_initializers = 32L)
)
stopifnot(
  nrow(ordered_cells) == 32L,
  identical(sort(unique(ordered_cells$scenario_order)), seq_len(8L)),
  !any(grepl("^scenario_order\\.", names(ordered_cells))),
  nrow(legacy_cells) == 32L,
  identical(sort(unique(legacy_cells$scenario_order)), seq_len(8L))
)
bad_ordered_future <- ordered_future
bad_ordered_future$scenario_order[bad_ordered_future$scenario_id == cell_scenarios[[1L]]] <- 8L
order_mismatch <- tryCatch({
  app_joint_article_build_model_cells(
    bad_ordered_future, cell_designs,
    list(expected_top_level_initializers = 32L)
  )
  ""
}, error = function(e) conditionMessage(e))
stopifnot(grepl("scenario ordering disagree", order_mismatch, fixed = TRUE))

cat("Pure-recursive JOINT campaign tests passed.\n")
