#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase180_balanced_score_bootstrap.R"
))

expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}

contract <- app_joint_qdesn_phase180_read_contract()
case <- data.frame(
  mcmc_case_id = "recovery_case", case_id = "recovery_case",
  scenario_id = "recovery_scenario", source_model_id = "joint_exqdesn_rhs_vb",
  likelihood_family = "exAL", fit_structure = "joint",
  stringsAsFactors = FALSE
)
init <- app_joint_qdesn_bind_rows(list(
  data.frame(
    mcmc_case_id = "recovery_case", parameter_block = "sigma",
    parameter_index = seq_along(contract$tau), value = rep(1, length(contract$tau)),
    stringsAsFactors = FALSE
  ),
  data.frame(
    mcmc_case_id = "recovery_case", parameter_block = "gamma",
    parameter_index = seq_along(contract$tau), value = rep(0, length(contract$tau)),
    stringsAsFactors = FALSE
  )
))
plan <- app_joint_qdesn_bind_rows(lapply(seq_len(contract$n_chains), function(chain_id) {
  out <- case
  out$worker_id <- chain_id
  out$chain_id <- chain_id
  out
}))
starts <- app_joint_qdesn_phase180_chain_starts(init, case, contract)
preflight <- app_joint_qdesn_phase180_m0_start_preflight(
  starts, plan, contract$tau
)
expect_true(all(preflight$status == "pass"),
            "Support-logit Phase180 starts failed the actual M0 preflight.")
expect_true(max(abs(preflight$support_eta)) <= 4 + 1e-12,
            "Support-logit Phase180 starts exceed the frozen numerical interior.")
gamma_starts <- starts[starts$parameter == "gamma", , drop = FALSE]
expect_true(all(table(gamma_starts$quantile_index) == contract$n_chains),
            "Phase180 recovery lost gamma chain coverage.")
expect_true(all(vapply(
  split(gamma_starts$value, gamma_starts$quantile_index),
  function(x) length(unique(x)) == contract$n_chains, logical(1L)
)), "Phase180 support-logit starts are not chain-distinct.")

unsafe <- starts
support_025 <- app_joint_exqdesn_support(0.25)
support_075 <- app_joint_exqdesn_support(0.75)
unsafe$value[
  unsafe$parameter == "gamma" & unsafe$chain_id == 1L &
    unsafe$quantile_index == 3L
] <- support_025$lower[[1L]] + 1e-6
unsafe$value[
  unsafe$parameter == "gamma" & unsafe$chain_id == contract$n_chains &
    unsafe$quantile_index == 5L
] <- support_075$upper[[1L]] - 1e-6
unsafe_preflight <- app_joint_qdesn_phase180_m0_start_preflight(
  unsafe, plan, contract$tau
)
expect_true(setequal(
  unique(unsafe_preflight$worker_id[unsafe_preflight$status == "fail"]),
  c(1L, contract$n_chains)
), "The recovery preflight did not isolate the two historical endpoint failures.")
corrected <- app_joint_qdesn_phase180_replace_gamma_starts(unsafe, starts)
non_gamma <- unsafe$parameter != "gamma"
expect_true(
  identical(corrected$value[non_gamma], unsafe$value[non_gamma]) &&
    identical(corrected$start_role[non_gamma], unsafe$start_role[non_gamma]),
  "Gamma recovery changed a non-gamma parent start value."
)
corrected_preflight <- app_joint_qdesn_phase180_m0_start_preflight(
  corrected, plan, contract$tau
)
expect_true(all(corrected_preflight$status == "pass"),
            "Gamma-only parent-start replacement failed M0 preflight.")

checkpoint_root <- file.path(
  tempdir(), paste0("phase180-recovery-checkpoint-", Sys.getpid())
)
freeze_root <- file.path(checkpoint_root, "freeze")
worker_root <- file.path(checkpoint_root, "worker")
dir.create(freeze_root, recursive = TRUE, showWarnings = FALSE)
writeLines("test freeze manifest", file.path(freeze_root, "artifact_manifest.csv"))
set.seed(18025)
fit <- list(
  beta_draws = matrix(rnorm(40), 10L, 4L),
  alpha_draws = matrix(rnorm(20), 10L, 2L),
  sigma_draws = matrix(rexp(20) + 0.1, 10L, 2L),
  init_source = "provided"
)
fixture <- list(tau = c(0.25, 0.75))
job <- data.frame(
  worker_id = 1L, mcmc_case_id = "case", case_id = "case",
  scenario_id = "scenario", source_model_id = "joint_qdesn_rhs_vb",
  likelihood_family = "AL", fit_structure = "joint",
  inference_method_id = "AL_latent_GIG_Gibbs", chain_id = 1L,
  chain_seed = 18025L, source_control_row_sha256 = "control",
  fixture_manifest_sha256 = "fixture", code_commit = "parent_commit",
  n_iter = 12L, burn = 2L, thin = 1L, stringsAsFactors = FALSE
)
component <- data.frame(component_seed = 18025L)
context <- list(
  execution_code_commit = "recovery_commit", recovery_id = "recovery_v1",
  amendment_manifest_sha256 = "amendment_hash",
  start_row_sha256 = "start_hash"
)
checkpoint <- app_joint_qdesn_phase180_write_checkpoint(
  fit, fixture, job, component, 1.5, freeze_root, worker_root, context
)
metadata <- checkpoint$metadata
expect_true(
  metadata$execution_code_commit[[1L]] == context$execution_code_commit &&
    metadata$recovery_id[[1L]] == context$recovery_id &&
    metadata$recovery_amendment_manifest_sha256[[1L]] ==
      context$amendment_manifest_sha256 &&
    metadata$recovery_start_row_sha256[[1L]] == context$start_row_sha256,
  "Recovered checkpoint omitted its amendment identity."
)
invisible(app_joint_qdesn_phase180_load_checkpoint(
  worker_root, fixture, job, component, freeze_root, context
))
unlink(checkpoint_root, recursive = TRUE, force = TRUE)

cache_root <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
dirs <- app_joint_qdesn_phase180_dirs(cache_root)
if (dir.exists(dirs$freeze) && dir.exists(dirs$orchestration)) {
  frozen <- app_joint_qdesn_phase180_load_freeze(dirs$freeze)
  inventory <- app_joint_qdesn_phase180_recovery_inventory(
    frozen, dirs$orchestration
  )
  expect_true(
    nrow(inventory$preserved) == 158L && nrow(inventory$failures) == 10L &&
      all(inventory$failures$failure_message == "weights must be positive."),
    "Real Phase180 recovery inventory differs from the frozen 158/10 diagnosis."
  )
}

cat("Phase180 endpoint-start recovery tests passed.\n")
