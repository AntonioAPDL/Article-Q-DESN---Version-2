repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN article asset test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_article_assets.R"))

check_manifest <- function(dir) {
  manifest <- utils::read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  manifest
}

write_source_manifest <- function(dir, paths) {
  info <- app_joint_qdesn_write_manifest(paths, dir)
  stopifnot(file.exists(info$manifest_path))
  invisible(check_manifest(dir))
}

model_rows <- function(stage = "fit") {
  ids <- c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb", "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb")
  labels <- c("JOINT QDESN RHS", "QDESN RHS", "JOINT exQDESN RHS", "exQDESN RHS")
  lik <- c("al", "al", "exal", "exal")
  fit_structure <- c("joint", "independent_single_tau", "joint", "independent_single_tau")
  truth_mae <- if (stage == "fit") c(0.08, 0.10, 0.12, 0.13) else c(0.09, 0.11, 0.14, 0.15)
  data.frame(
    candidate_id = "rhs_tau0_0p5_alpha0p5",
    candidate_label = "RHS tau0 0.5 with alpha sd 0.5",
    candidate_role = "test_candidate",
    tau0 = 0.5,
    zeta2 = Inf,
    alpha_prior_sd = 0.5,
    alpha_min_spacing = 0,
    vb_max_iter = 4L,
    adaptive_vb_max_iter_grid = "4,8",
    rhs_vb_inner = 1L,
    stage = stage,
    model_id = ids,
    display_label = labels,
    likelihood = lik,
    fit_structure = fit_structure,
    truth_mae = truth_mae,
    truth_sq_error = truth_mae^2,
    truth_rmse = truth_mae * 1.2,
    check_loss_mean = truth_mae + 0.05,
    crps_grid_mean = truth_mae + 0.20,
    abs_hit_rate_error = c(0.01, 0.02, 0.03, 0.04),
    abs_coverage_error = c(0.02, 0.03, 0.04, 0.05),
    interval_width_mean = 1,
    interval_score_mean = 2,
    raw_crossing_pairs = if (stage == "forecast") c(0, 1, 0, 2) else 0,
    contract_crossing_pairs = 0,
    reached_max_iter = c(0, 0, 1, 1),
    elapsed_seconds = 1,
    max_abs_adjustment = if (stage == "forecast") c(0, 0.01, 0, 0.02) else 0,
    adjustment_rate = 0,
    finite_quantiles = TRUE,
    finite_scores = TRUE,
    gate_status = c("pass", "review", "review", "review"),
    stringsAsFactors = FALSE
  )
}

scenario_rows <- function(stage = "forecast") {
  out <- model_rows(stage)
  out <- out[, c(
    "candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2",
    "alpha_prior_sd", "alpha_min_spacing", "stage", "model_id", "display_label",
    "likelihood", "fit_structure", "truth_mae", "truth_sq_error", "truth_rmse",
    "check_loss_mean", "gate_status", "raw_crossing_pairs", "contract_crossing_pairs",
    "max_abs_adjustment", "adjustment_rate", "reached_max_iter"
  ), drop = FALSE]
  out$scenario_id <- "normal_bridge"
  out$status_reason <- ifelse(out$gate_status == "pass", "all gates passed", "test review")
  out[, c(
    "candidate_id", "candidate_label", "candidate_role", "tau0", "zeta2",
    "alpha_prior_sd", "alpha_min_spacing", "stage", "scenario_id", "model_id",
    "display_label", "likelihood", "fit_structure", "truth_mae", "truth_sq_error",
    "truth_rmse", "check_loss_mean", "gate_status", "raw_crossing_pairs",
    "contract_crossing_pairs", "max_abs_adjustment", "adjustment_rate",
    "reached_max_iter", "status_reason"
  ), drop = FALSE]
}

with_unselected_candidate <- function(x, multiplier = 10) {
  extra <- x
  extra$candidate_id <- "unselected_rhs_tau0_0p5_alpha0p5"
  if ("candidate_label" %in% names(extra)) extra$candidate_label <- "Unselected screening candidate"
  for (nm in intersect(c("truth_mae", "truth_sq_error", "truth_rmse", "check_loss_mean", "crps_grid_mean"), names(extra))) {
    extra[[nm]] <- extra[[nm]] * multiplier
  }
  rbind(x, extra)
}

phase107_dir <- tempfile("joint_qdesn_phase107_asset_source_")
phase109_dir <- tempfile("joint_qdesn_phase109_asset_source_")
tables_dir <- tempfile("joint_qdesn_article_tables_")
figures_dir <- tempfile("joint_qdesn_article_figures_")
out_dir <- tempfile("joint_qdesn_article_assets_")
app_ensure_dir(phase107_dir)
app_ensure_dir(phase109_dir)
app_ensure_dir(tables_dir)

phase107_paths <- c(
  selected_spec_recommendation = app_joint_qvp_write_csv(data.frame(
    candidate_id = "rhs_tau0_0p5_alpha0p5",
    candidate_label = "RHS tau0 0.5 with alpha sd 0.5",
    gate_status = "review",
    screening_score = 0.7,
    mean_fit_truth_mae = 0.10,
    mean_forecast_truth_mae = 0.12,
    joint_qdesn_forecast_truth_mae = 0.09,
    independent_exqdesn_forecast_truth_mae = 0.15,
    max_scenario_forecast_truth_mae = 0.15,
    forecast_raw_crossings = 3L,
    max_forecast_adjustment = 0.02,
    elapsed_minutes = 1,
    recommendation_class = "usable_with_review",
    rank = 1L,
    selected = TRUE,
    next_action = "test",
    stringsAsFactors = FALSE
  ), file.path(phase107_dir, "selected_spec_recommendation.csv")),
  screening_health_summary = app_joint_qvp_write_csv(data.frame(
    candidate_id = "rhs_tau0_0p5_alpha0p5",
    candidate_label = "RHS tau0 0.5 with alpha sd 0.5",
    manifest_status = "pass",
    fit_models = 4L,
    forecast_models = 4L,
    scenario_worker_failures = 0L,
    fit_worker_failures = 0L,
    forecast_worker_failures = 0L,
    fit_fail_models = 0L,
    forecast_fail_models = 0L,
    fit_raw_crossings = 0L,
    forecast_raw_crossings = 3L,
    contract_crossings = 0L,
    max_forecast_adjustment = 0.02,
    max_forecast_truth_mae = 0.15,
    catastrophic_rows = 0L,
    fit_reached_max_iter = 2L,
    forecast_reached_max_iter = 2L,
    elapsed_seconds = 1,
    gate_status = "review",
    stringsAsFactors = FALSE
  ), file.path(phase107_dir, "screening_health_summary.csv")),
  candidate_registry = app_joint_qvp_write_csv(data.frame(
    candidate_id = c("rhs_tau0_0p5_alpha0p5", "unselected_rhs_tau0_0p5_alpha0p5"),
    tau0 = c(0.5, 0.5),
    alpha_prior_sd = c(0.5, 0.5),
    vb_max_iter = c(4L, 4L),
    adaptive_vb_max_iter_grid = c("4,8", "4,8"),
    stringsAsFactors = FALSE
  ), file.path(phase107_dir, "candidate_registry.csv")),
  fit_model_metric_summary = app_joint_qvp_write_csv(with_unselected_candidate(model_rows("fit")), file.path(phase107_dir, "fit_model_metric_summary.csv")),
  forecast_model_metric_summary = app_joint_qvp_write_csv(with_unselected_candidate(model_rows("forecast")), file.path(phase107_dir, "forecast_model_metric_summary.csv")),
  fit_scenario_metric_summary = app_joint_qvp_write_csv(with_unselected_candidate(scenario_rows("fit")), file.path(phase107_dir, "fit_scenario_metric_summary.csv")),
  forecast_scenario_metric_summary = app_joint_qvp_write_csv(with_unselected_candidate(scenario_rows("forecast")), file.path(phase107_dir, "forecast_scenario_metric_summary.csv")),
  forecast_tau_metric_summary = app_joint_qvp_write_csv(with_unselected_candidate(data.frame(
    candidate_id = "rhs_tau0_0p5_alpha0p5",
    stage = "forecast",
    model_id = "joint_qdesn_rhs_vb",
    tau = 0.5,
    truth_mae = 0.09,
    stringsAsFactors = FALSE
  )), file.path(phase107_dir, "forecast_tau_metric_summary.csv"))
)
nested <- data.frame(
  artifact_label = "phase107_nested",
  label = "fit",
  relative_path = "fit_model_metric_summary.csv",
  path = phase107_paths[["fit_model_metric_summary"]],
  exists = TRUE,
  status = "pass",
  stringsAsFactors = FALSE
)
phase107_paths[["candidate_manifest_verification"]] <- app_joint_qvp_write_csv(nested, file.path(phase107_dir, "candidate_manifest_verification.csv"))
write_source_manifest(phase107_dir, phase107_paths)

mcmc_summary <- data.frame(
  scenario_id = "normal_bridge",
  scenario_class = "bridge",
  distribution_family = "gaussian",
  dynamics_class = "ar1",
  model_id = "joint_qdesn_rhs_mcmc",
  display_label = "JOINT QDESN RHS MCMC",
  likelihood = "al",
  fit_structure = "joint",
  inference = "MCMC",
  n_train = 10L,
  p = 2L,
  K = 3L,
  tau_grid = "0.05,0.50,0.95",
  vb_converged = TRUE,
  vb_reached_max_iter = FALSE,
  vb_max_iter_used = 4L,
  vb_adaptive_attempts = "4",
  mcmc_n_chains = 2L,
  mcmc_n_iter = 12L,
  mcmc_burn = 6L,
  mcmc_thin = 3L,
  mcmc_n_keep_total = 4L,
  mcmc_init_source = "provided",
  all_chain_init_source_provided = TRUE,
  mcmc_draws_all_finite = TRUE,
  sigma_lower_bound = 1e-8,
  sigma_upper_bound = 10,
  max_sigma_lower_bound_hit_fraction = 0,
  max_sigma_upper_bound_hit_fraction = 0,
  vb_raw_crossing_pairs = 0L,
  vb_contract_crossing_pairs = 0L,
  mcmc_raw_crossing_pairs = 0L,
  mcmc_contract_crossing_pairs = 0L,
  vb_max_abs_adjustment = 0,
  mcmc_max_abs_adjustment = 0,
  vb_truth_mae = 0.08,
  mcmc_truth_mae = 0.081,
  vb_check_loss_mean = 0.12,
  mcmc_check_loss_mean = 0.121,
  vb_mcmc_max_normalized_distance = 0.1,
  max_chain_to_pooled_normalized_distance = 0.11,
  vb_elapsed_seconds = 1,
  mcmc_elapsed_seconds = 2,
  total_elapsed_seconds = 3,
  stringsAsFactors = FALSE
)
hit <- rbind(
  data.frame(scenario_id = "normal_bridge", model_id = "joint_qdesn_rhs_mcmc", display_label = "JOINT QDESN RHS MCMC", likelihood = "al", fit_structure = "joint", tau = c(0.05, 0.5, 0.95), hit_rate = c(0.06, 0.51, 0.94), n_scores = 10L, hit_rate_error = c(0.01, 0.01, -0.01), abs_hit_rate_error = c(0.01, 0.01, 0.01)),
  data.frame(scenario_id = "normal_bridge", model_id = "joint_qdesn_rhs_vb", display_label = "JOINT QDESN RHS", likelihood = "al", fit_structure = "joint", tau = c(0.05, 0.5, 0.95), hit_rate = c(0.05, 0.5, 0.95), n_scores = 10L, hit_rate_error = 0, abs_hit_rate_error = 0)
)
fit_truth <- expand.grid(
  effective_index = 1:10,
  tau = c(0.05, 0.5, 0.95)
)
fit_truth$scenario_id <- "normal_bridge"
fit_truth$model_id <- "joint_qdesn_rhs_mcmc"
fit_truth$display_label <- "JOINT QDESN RHS MCMC"
fit_truth$likelihood <- "al"
fit_truth$fit_structure <- "joint"
fit_truth$y <- sin(fit_truth$effective_index / 2)
fit_truth$true_quantile <- fit_truth$y + stats::qnorm(fit_truth$tau) * 0.1
fit_truth$qhat <- fit_truth$true_quantile + 0.01

phase109_paths <- c(
  run_config = app_joint_qvp_write_csv(data.frame(
    run_id = "test",
    mcmc_n_chains = 2L,
    mcmc_n_iter = 12L,
    mcmc_burn = 6L,
    mcmc_thin = 3L,
    final_article_mcmc_table = TRUE,
    stringsAsFactors = FALSE
  ), file.path(phase109_dir, "run_config.csv")),
  mcmc_readiness_assessment = app_joint_qvp_write_csv(data.frame(
    scenario_id = "normal_bridge",
    scenario_class = "bridge",
    distribution_family = "gaussian",
    dynamics_class = "ar1",
    model_id = "joint_qdesn_rhs_mcmc",
    display_label = "JOINT QDESN RHS MCMC",
    implementation_status = "pass",
    distance_status = "pass",
    chain_status = "pass",
    gate_status = "pass",
    status_reason = "all readiness gates passed",
    stringsAsFactors = FALSE
  ), file.path(phase109_dir, "mcmc_readiness_assessment.csv")),
  mcmc_readiness_summary = app_joint_qvp_write_csv(mcmc_summary, file.path(phase109_dir, "mcmc_readiness_summary.csv")),
  truth_distance_summary = app_joint_qvp_write_csv(data.frame(scenario_id = "normal_bridge", model_id = "joint_qdesn_rhs_mcmc", display_label = "JOINT QDESN RHS MCMC", likelihood = "al", fit_structure = "joint", tau = c(0.05, 0.5, 0.95), truth_mae = 0.08, truth_rmse = 0.09, truth_bias = 0), file.path(phase109_dir, "truth_distance_summary.csv")),
  check_loss_summary = app_joint_qvp_write_csv(data.frame(scenario_id = "normal_bridge", model_id = "joint_qdesn_rhs_mcmc", display_label = "JOINT QDESN RHS MCMC", likelihood = "al", fit_structure = "joint", tau = c(0.05, 0.5, 0.95), check_loss_mean = 0.12, n_scores = 10L), file.path(phase109_dir, "check_loss_summary.csv")),
  crps_grid_summary = app_joint_qvp_write_csv(data.frame(scenario_id = "normal_bridge", model_id = "joint_qdesn_rhs_mcmc", display_label = "JOINT QDESN RHS MCMC", likelihood = "al", fit_structure = "joint", crps_grid_mean = 0.3, n_crps = 10L), file.path(phase109_dir, "crps_grid_summary.csv")),
  hit_rate_summary = app_joint_qvp_write_csv(hit, file.path(phase109_dir, "hit_rate_summary.csv")),
  interval_summary = app_joint_qvp_write_csv(data.frame(scenario_id = "normal_bridge", model_id = "joint_qdesn_rhs_mcmc", display_label = "JOINT QDESN RHS MCMC", likelihood = "al", fit_structure = "joint", lower_tau = 0.05, upper_tau = 0.95, nominal_coverage = 0.9, coverage = 0.9, interval_width_mean = 1, interval_score_mean = 2, n_intervals = 10L, coverage_error = 0, abs_coverage_error = 0), file.path(phase109_dir, "interval_summary.csv")),
  vb_mcmc_distance_summary = app_joint_qvp_write_csv(data.frame(scenario_id = "normal_bridge", model_id = "joint_qdesn_rhs_mcmc", display_label = "JOINT QDESN RHS MCMC", likelihood = "al", fit_structure = "joint", max_normalized_distance = 0.1), file.path(phase109_dir, "vb_mcmc_distance_summary.csv")),
  chain_to_pooled_distance_summary = app_joint_qvp_write_csv(data.frame(scenario_id = "normal_bridge", model_id = "joint_qdesn_rhs_mcmc", display_label = "JOINT QDESN RHS MCMC", likelihood = "al", fit_structure = "joint", max_normalized_to_pooled = 0.11), file.path(phase109_dir, "chain_to_pooled_distance_summary.csv")),
  scenario_worker_failures = app_joint_qvp_write_csv(data.frame(
    scenario_id = character(),
    worker_index = integer(),
    worker_status = character(),
    error_class = character(),
    error_message = character(),
    stringsAsFactors = FALSE
  ), file.path(phase109_dir, "scenario_worker_failures.csv")),
  fit_truth_comparison = app_joint_qvp_write_csv(fit_truth, file.path(phase109_dir, "fit_truth_comparison.csv"))
)
write_source_manifest(phase109_dir, phase109_paths)

result <- app_joint_qdesn_run_article_validation_assets(
  phase107_dir = phase107_dir,
  phase109_dir = phase109_dir,
  tables_dir = tables_dir,
  figures_dir = figures_dir,
  out_dir = out_dir
)

manifest <- check_manifest(result$out_dir)
stopifnot(all(result$source_verification$status == "pass"))
stopifnot(nrow(result$asset_manifest) >= 10L)
stopifnot(result$readiness$overall_gate[[1L]] == "review")
stopifnot(result$readiness$selected_candidate[[1L]] == "rhs_tau0_0p5_alpha0p5")
stopifnot(nrow(result$vb_summary) == 4L)
stopifnot(any(result$vb_summary$model_label == "Independent exQDESN RHS"))
stopifnot(!any(grepl("unselected", unlist(result$vb_summary), fixed = TRUE)))
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_tables.tex")))
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_provenance_tables.tex")))
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_protocol_provenance.tex")))
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_vb_model_summary.csv")))
stopifnot(file.exists(file.path(figures_dir, "joint_qdesn_article_validation_vb_fit_forecast_mae.pdf")))
stopifnot(file.exists(file.path(figures_dir, "joint_qdesn_article_validation_mcmc_overlay_normal_bridge.pdf")))
stopifnot("article_readiness_assessment" %in% manifest$label)

main_wrapper <- readLines(file.path(tables_dir, "joint_qdesn_article_validation_tables.tex"), warn = FALSE)
stopifnot(any(grepl("joint_qdesn_article_validation_protocol.tex", main_wrapper, fixed = TRUE)))
stopifnot(any(grepl("joint_qdesn_article_validation_vb_model_summary.tex", main_wrapper, fixed = TRUE)))
stopifnot(any(grepl("joint_qdesn_article_validation_vb_scenario_summary.tex", main_wrapper, fixed = TRUE)))
stopifnot(!any(grepl("gate_summary", main_wrapper, fixed = TRUE)))
stopifnot(!any(grepl("mcmc_scenario", main_wrapper, fixed = TRUE)))

main_rendered <- unlist(lapply(c(
  "joint_qdesn_article_validation_tables.tex",
  "joint_qdesn_article_validation_protocol.tex",
  "joint_qdesn_article_validation_vb_model_summary.tex",
  "joint_qdesn_article_validation_vb_scenario_summary.tex"
), function(file) readLines(file.path(tables_dir, file), warn = FALSE)), use.names = FALSE)
forbidden_main <- c(
  "Phase 107", "Phase 109", "application/cache", "rhs_tau0",
  "final article flag", "worker failure", "worker failures",
  "contract quantiles", "contract crossings", "Gate policy"
)
for (pattern in forbidden_main) {
  stopifnot(!any(grepl(pattern, main_rendered, fixed = TRUE)))
}
stopifnot(any(grepl("Raw crossings", main_rendered, fixed = TRUE)))
stopifnot(any(grepl("Grid CRPS", main_rendered, fixed = TRUE)))

vb_model_tex <- readLines(file.path(tables_dir, "joint_qdesn_article_validation_vb_model_summary.tex"), warn = FALSE)
stopifnot(!any(grepl("Likelihood", vb_model_tex, fixed = TRUE)))
stopifnot(!any(grepl("Readout", vb_model_tex, fixed = TRUE)))
stopifnot(!any(grepl("Forecast RMSE", vb_model_tex, fixed = TRUE)))
stopifnot(any(grepl("not a single empirical data set", vb_model_tex, fixed = TRUE)))
vb_scenario_tex <- readLines(file.path(tables_dir, "joint_qdesn_article_validation_vb_scenario_summary.tex"), warn = FALSE)
stopifnot(!any(grepl("Lowest MAE row", vb_scenario_tex, fixed = TRUE)))
stopifnot(!any(grepl("Scenario & Class", vb_scenario_tex, fixed = TRUE)))
stopifnot(any(grepl("Scenario-level held-out forecast distance", vb_scenario_tex, fixed = TRUE)))
vb_scenario_csv <- readLines(file.path(tables_dir, "joint_qdesn_article_validation_vb_scenario_summary.csv"), warn = FALSE)
stopifnot(!any(grepl("\\textbf{", vb_scenario_csv, fixed = TRUE)))
vb_scenario_data <- utils::read.csv(file.path(tables_dir, "joint_qdesn_article_validation_vb_scenario_summary.csv"), stringsAsFactors = FALSE)
stopifnot(sum(grepl("\\textbf{", vb_scenario_tex, fixed = TRUE)) >= nrow(vb_scenario_data))

provenance_wrapper <- readLines(file.path(tables_dir, "joint_qdesn_article_validation_provenance_tables.tex"), warn = FALSE)
stopifnot(any(grepl("joint_qdesn_article_validation_gate_summary.tex", provenance_wrapper, fixed = TRUE)))
stopifnot(any(grepl("joint_qdesn_article_validation_mcmc_scenario_summary.tex", provenance_wrapper, fixed = TRUE)))

asset_manifest <- utils::read.csv(file.path(tables_dir, "joint_qdesn_article_validation_asset_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(nchar(asset_manifest$sha256) == 64L))
stopifnot(all(c("source_vb_dir", "source_mcmc_dir") %in% names(asset_manifest)))
for (ii in seq_len(nrow(asset_manifest))) {
  path <- if (grepl("^/", asset_manifest$path[[ii]])) asset_manifest$path[[ii]] else app_path(asset_manifest$path[[ii]])
  stopifnot(file.exists(path))
  stopifnot(identical(app_sha256_file(path), asset_manifest$sha256[[ii]]))
}
