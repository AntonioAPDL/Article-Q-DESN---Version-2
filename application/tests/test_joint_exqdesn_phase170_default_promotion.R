#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_exqdesn_inference_dispatch.R"))
source(app_path("application/R/joint_exqdesn_phase170_default_promotion.R"))

methods <- app_joint_exqdesn_phase170_methods()
grid <- expand.grid(
  base_scenario_id = paste0("scenario_", seq_len(5L)),
  fit_structure = c("joint", "independent"),
  parameter = c("gamma", "sigma", "p_gamma", "actual_sd", "sigma_lambda"),
  quantile_index = seq_len(7L),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
grid$scenario_id <- paste0(grid$base_scenario_id, "__r001")
grid$tau <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)[grid$quantile_index]
diagnostic_rows <- lapply(unname(methods), function(method) {
  offset <- if (method == methods[["winner"]]) 0.02 else 0
  data.frame(
    grid,
    inference_method_id = method,
    posterior_mean = 1 + offset,
    posterior_sd = 1,
    q05 = -0.65 + offset,
    median = 1 + offset,
    q95 = 2.65 + offset,
    rank_rhat = 1.01,
    folded_rhat = 1.01,
    bulk_ess = if (method == methods[["winner"]]) 700 else if (
      method == methods[["excluded"]]
    ) 150 else 650,
    tail_ess = 800,
    mcse_mean = 0.01,
    stringsAsFactors = FALSE
  )
})
diagnostics <- do.call(rbind, diagnostic_rows)
invariance <- app_joint_exqdesn_phase170_parameter_invariance(diagnostics)
stopifnot(nrow(invariance) == 350L)
stopifnot(all(invariance$target_invariance_status == "pass"))

summary_grid <- expand.grid(
  base_scenario_id = paste0("scenario_", seq_len(5L)),
  fit_structure = c("joint", "independent"),
  inference_method_id = unname(methods),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
summary_grid$scenario_id <- paste0(summary_grid$base_scenario_id, "__r001")
method_rank <- match(summary_grid$inference_method_id, unname(methods))
summary_grid$n_chains <- 8L
summary_grid$forecast_truth_mae <- 0.10 + c(0, -0.0005, 0.001)[method_rank]
summary_grid$forecast_crps_grid_mean <- 0.30 + c(0, -0.0001, 0.0001)[method_rank]
summary_grid$runtime_seconds_total <- 36000 * c(1, 1.02, 1.20)[method_rank]
summary_grid$raw_crossing_pairs <- 0L
summary_grid$contract_crossing_pairs <- 0L
summary_grid$all_draws_finite <- TRUE
evidence <- app_joint_exqdesn_phase170_method_evidence(summary_grid, diagnostics)
stopifnot(nrow(evidence) == 3L)

qhat_summary <- data.frame(
  q99_standardized_qhat_delta = rep(0.10, 20L),
  q01_central90_overlap_fraction = rep(0.90, 20L),
  target_invariance_status = rep("pass", 20L)
)
phase169 <- data.frame(
  completed_workers = 240L,
  expected_workers = 240L,
  implementation_failures = 0L,
  contract_crossing_pairs = 0L
)
decision <- app_joint_exqdesn_phase170_decision(
  phase169, invariance, qhat_summary, evidence
)
stopifnot(all(decision$gates$status == "pass"))
stopifnot(identical(decision$decision$decision_status, "pass_promoted_M1b"))
stopifnot(identical(
  decision$decision$production_default_method_id,
  methods[["winner"]]
))

bad <- invariance
bad$standardized_mean_delta[[1L]] <- 0.5
blocked <- app_joint_exqdesn_phase170_decision(
  phase169, bad, qhat_summary, evidence
)
stopifnot(identical(
  blocked$decision$decision_status,
  "pass_promoted_M0_with_M1b_review"
))
stopifnot(identical(
  blocked$decision$production_default_method_id,
  methods[["baseline"]]
))

cat("Phase170 default-promotion tests passed.\n")
