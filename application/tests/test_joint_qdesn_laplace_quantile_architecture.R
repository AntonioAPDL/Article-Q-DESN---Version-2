#!/usr/bin/env Rscript
source("application/scripts/_joint_qdesn_recursive_mean_forecast_bootstrap.R")
source(app_path("application/R/joint_qdesn_fixed_backbone_prior_screen.R"))
source(app_path("application/R/joint_qdesn_laplace_quantile_architecture.R"))

expect_error <- function(expr) {
  failed <- tryCatch({force(expr); FALSE}, error = function(e) TRUE)
  stopifnot(failed)
}

ct <- app_joint_arch_contract()
stopifnot(ct$shortlist_count == 8L, ct$exal_mcmc_method == "M0_v_collapsed_support_logit",
  ct$exal_vb_method == "VB1_structured_v", ct$mixing_gate_policy == "review_unless_predictive_pathology")

source_root <- tempfile("joint_arch_source_"); app_ensure_dir(source_root)
candidate_rows <- lapply(seq_len(8L), function(ii) data.frame(
  scenario_id = "laplace_bridge", candidate_id = sprintf("candidate_%02d", ii),
  candidate_role = if (ii == 1L) "legacy" else "expanded_halton",
  feature_contract = "pure_recursive_v1", design_class = "reservoir", D = 1L,
  n = as.character(19L + ii), n_tilde = "", retained_state_budget = 19L + ii,
  width_shape = "flat", state_reduction = FALSE, response_lags = ii,
  exogenous_lags = 0L, alpha = as.character(.1 + ii / 20),
  rho = as.character(.3 + ii / 20), pi_w = ifelse(ii %% 2L, ".05", ".1"),
  pi_in = ifelse(ii %% 2L, ".25", ".5"), input_scale = ifelse(ii %% 2L, .1, .25),
  reservoir_seed = 202609250L, raw_inputs_in_readout = FALSE,
  full_states_all_layers = TRUE, architecture_signature = sprintf("signature_%02d", ii),
  rhs_tau0 = 10^(-((ii - 1L) %% 5L)), replicate_count = 3L,
  hard_gate_status = "pass", condition_gate_status = "pass",
  saturation_gate_status = "pass", calibration_acrps_mean = 1 + (ii - 1L) / 1000,
  calibration_acrps_between_rep_sd = .01, calibration_exact_gaussian_crps_mean = 1,
  convergence_fraction = 1, runtime_seconds_total = 1, stringsAsFactors = FALSE))
aggregate <- app_joint_qdesn_bind_rows(candidate_rows)
app_write_csv(aggregate, file.path(source_root, "rhs_candidate_aggregate.csv"))
selected <- aggregate[1L, ]
selected$selection_rank <- 1L
app_write_csv(selected, file.path(source_root, "selected_family_backbones.csv"))
plan <- app_joint_qdesn_bind_rows(lapply(seq_len(8L), function(ii) {
  x <- aggregate[ii, ]
  app_joint_qdesn_bind_rows(lapply(seq_len(3L), function(rep) cbind(x,
    data.frame(replicate_id = rep, dgp_seed = 202620099L + rep,
      fixture_path = sprintf("fixture_%02d.rds", rep),
      rhs_worker_id = (ii - 1L) * 3L + rep,
      rhs_candidate_id = sprintf("rhs_%02d_%02d", ii, rep), stringsAsFactors = FALSE))))
}))
app_write_csv(plan, file.path(source_root, "rhs_worker_plan.csv"))
for (id in plan$rhs_worker_id) {
  directory <- app_joint_pure_worker_dir(source_root, "rhs", id); app_ensure_dir(directory)
  app_write_csv(data.frame(rhs_worker_id = id), file.path(directory, "summary.csv"))
  app_joint_arch_seal(directory)
}
app_write_csv(data.frame(stage = "ridge", expected = 18432L, completed = 18432L,
  failed = 0L, remaining = 0L, completion_fraction = 1, status = "complete"),
  file.path(source_root, "ridge_final_health.csv"))
app_write_csv(data.frame(stage = "rhs", expected = 7680L, completed = 7680L,
  failed = 0L, remaining = 0L, completion_fraction = 1, status = "complete"),
  file.path(source_root, "rhs_final_health.csv"))
app_write_csv(data.frame(status = "EXPANDED_RHS_SELECTION_COMPLETE_REVIEW_REQUIRED_BEFORE_QUANTILE_CONTINUATION",
  scenarios = 8L, improvements = 2L, protected_rows_used_for_selection = 0L,
  quantile_or_mcmc_auto_launched = FALSE, completed_at_utc = "test"),
  file.path(source_root, "final_expanded_screen_status.csv"))
app_write_csv(data.frame(head = system2("git", c("rev-parse", "HEAD"), stdout = TRUE)),
  file.path(source_root, "source_git_state.csv"))
selection_files <- c("rhs_candidate_aggregate.csv", "rhs_worker_plan.csv", "selected_family_backbones.csv")
app_joint_shared_write_manifest(source_root, setNames(file.path(source_root, selection_files), selection_files),
  filename = "selection_artifact_manifest.csv")
final_files <- c("ridge_final_health.csv", "rhs_final_health.csv", "final_expanded_screen_status.csv")
app_joint_shared_write_manifest(source_root, setNames(file.path(source_root, final_files), final_files),
  filename = "expanded_screen_final_manifest.csv")

gate <- app_joint_arch_source_gate(source_root, ct)
shortlist <- app_joint_arch_shortlist(source_root, ct)
stopifnot(gate$rhs_complete == 7680L, nrow(shortlist) == 8L,
  shortlist$candidate_id[[1L]] == "candidate_01", sum(shortlist$baseline) == 1L,
  !anyDuplicated(shortlist$architecture_signature))

root <- tempfile("joint_arch_test_")
app_joint_arch_prepare(root, source_root)
stopifnot(nrow(app_read_csv(file.path(root, "vb", "datasets.csv"))) == 24L)
context <- app_joint_arch_internal_context(root,
  app_read_csv(file.path(root, "vb", "datasets.csv"))[1L, , drop = FALSE])
p <- ncol(context$design$Z); K <- length(context$design$tau)
fit <- list(beta_mean = rep(0, p * K), alpha_mean = stats::qnorm(context$design$tau))
qhat <- app_joint_arch_recursive_qhat(context$design, context$fixture, context$selected, fit)
stopifnot(nrow(qhat) == 150L, ncol(qhat) == 7L, all(is.finite(qhat)),
  all(apply(qhat, 1L, function(x) all(diff(x) >= 0))))
wide <- context$selected
wide$D <- 1L; wide$n <- "300"; wide$n_tilde <- ""; wide$retained_state_budget <- 300L
wide$architecture_signature <- "test_wide_300_state_design"
registry <- app_joint_qdesn_load_simulation_registry()
sc <- registry[registry$scenario_id == "laplace_bridge", , drop = FALSE]
sc$seed <- 999001L; sc$seed_role <- "test_only"
fixture <- app_joint_qdesn_fixture_from_registry_row(sc); fixture$registry_row <- sc
wide_design <- app_joint_arch_full_design(fixture, wide)
stopifnot(ncol(wide_design$Z) == 300L, !wide_design$raw_inputs_in_readout,
  wide_design$full_states_all_layers)

mock <- expand.grid(architecture_id = shortlist$architecture_id[1:3],
  model_id = c("independent_qdesn_rhs", "joint_qdesn_rhs",
    "independent_exqdesn_rhs", "joint_exqdesn_rhs"), replicate_id = 1:3,
  stringsAsFactors = FALSE)
mock$dgp_integrated_acrps <- 1
mock$dgp_integrated_acrps[mock$architecture_id == "arch_01"] <- .98
mock$dgp_integrated_acrps[mock$architecture_id == "arch_02"] <- 1.01
mock$raw_crossing_pairs <- mock$contract_crossing_pairs <- 0L
ranked <- app_joint_arch_rank(mock, "arch_00", 3L, "dgp_integrated_acrps")
stopifnot(ranked$decision$eligible[ranked$decision$architecture_id == "arch_01"],
  !ranked$decision$eligible[ranked$decision$architecture_id == "arch_02"])

app_write_csv(mock, file.path(root, "vb", "complete_scores.csv"))
app_write_csv(data.frame(note = "test"), file.path(root, "vb", "model_aggregate.csv"))
app_write_csv(data.frame(note = "test"), file.path(root, "vb", "architecture_decisions.csv"))
app_write_csv(data.frame(stage = "test", baseline_architecture_id = "arch_00",
  challenger_architecture_id = c("arch_01", "arch_02"), selection_rank = 1:2,
  status = "MCMC_SCREEN_CHALLENGERS_FROZEN"), file.path(root, "vb", "selection.csv"))
app_joint_arch_write_selection_manifest(root, "vb", c("complete_scores.csv", "model_aggregate.csv",
  "architecture_decisions.csv", "selection.csv"))
screen <- app_joint_arch_stage_prepare(root, "screen", c("arch_00", "arch_01", "arch_02"))
stopifnot(nrow(screen$datasets) == 6L, nrow(screen$cells) == 24L, nrow(screen$chains) == 48L,
  !anyDuplicated(screen$chains$chain_seed), !anyDuplicated(screen$chains$start_seed))

app_write_csv(data.frame(note = "test"), file.path(root, "screen", "complete_scores.csv"))
app_write_csv(data.frame(note = "test"), file.path(root, "screen", "model_aggregate.csv"))
app_write_csv(data.frame(note = "test"), file.path(root, "screen", "architecture_decisions.csv"))
app_write_csv(data.frame(stage = "test", baseline_architecture_id = "arch_00",
  selected_architecture_id = "arch_01", status = "CONFIRMATION_CHALLENGER_FROZEN"),
  file.path(root, "screen", "selection.csv"))
app_joint_arch_write_selection_manifest(root, "screen", c("complete_scores.csv", "model_aggregate.csv",
  "architecture_decisions.csv", "selection.csv"))
confirmation <- app_joint_arch_stage_prepare(root, "confirmation", c("arch_00", "arch_01"))
stopifnot(nrow(confirmation$datasets) == 4L, nrow(confirmation$cells) == 16L,
  nrow(confirmation$chains) == 48L,
  !any(confirmation$chains$chain_seed %in% screen$chains$chain_seed))

file <- file.path(root, "architectures.csv"); writeLines("tampered", file)
expect_error(app_joint_arch_verify_freeze(root))
unlink(c(root, source_root), recursive = TRUE)
cat("PASS: source authority, diverse shortlist, recursive quantile path, matched selection, and 48/48 MCMC plans.\n")
