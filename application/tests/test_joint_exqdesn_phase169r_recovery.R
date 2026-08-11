#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R",
  "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_phase164_165_readiness.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R",
  "joint_exqdesn_phase169r_recovery.R"
)) source(app_path("application/R", file))

job <- data.frame(
  worker_id = 1L,
  mcmc_case_id = "normal_bridge__phase153_dgp_r001__joint",
  scenario_id = "normal_bridge__phase153_dgp_r001",
  base_scenario_id = "normal_bridge",
  fit_structure = "joint",
  inference_method_id = "M1_u_collapsed_p_logit",
  chain_id = 1L,
  chain_seed = 202608071L,
  n_iter = 12000L,
  burn = 3000L,
  thin = 3L,
  stringsAsFactors = FALSE
)

# The corrected metadata must satisfy the complete shared scoring schema. The
# original reduced metadata is rejected before any expensive sampler call.
meta <- app_joint_exqdesn_phase169_score_meta(job)
stopifnot(all(c(
  "scenario_id", "model_id", "display_label", "likelihood",
  "fit_structure", "inference_method_id"
) %in% names(meta)))
stopifnot(identical(meta$display_label[[1L]], "Joint exQDESN RHS"))
stopifnot(identical(meta$likelihood[[1L]], "exAL"))
stopifnot(isTRUE(app_joint_exqdesn_phase169_validate_score_meta(meta)))
bad_meta <- meta[, setdiff(names(meta), c("display_label", "likelihood")), drop = FALSE]
stopifnot(inherits(
  try(app_joint_exqdesn_phase169_validate_score_meta(bad_meta), silent = TRUE),
  "try-error"
))

# Exercise the exact CRPS path that failed in the original campaign.
tau <- c(0.25, 0.75)
fixture <- list(
  tau = tau,
  y = c(-0.5, 0, 0.5, 1),
  Z = cbind(1, c(-1, 0, 1, 2)),
  true_q = cbind(c(-0.8, -0.3, 0.2, 0.7), c(-0.2, 0.3, 0.8, 1.3)),
  row_meta = data.frame(full_time_index = seq_len(4L), stringsAsFactors = FALSE)
)
qhat <- fixture$true_q + 0.01
scored <- app_joint_qdesn_phase122_score_qhat(
  meta, fixture, qhat, "qhat", "phase169r_test"
)
crps <- app_joint_qdesn_crps_grid_summary(scored$scored)
stopifnot(nrow(crps) == 1L, is.finite(crps$crps_grid_mean[[1L]]))

# A complete posterior is checkpointed before scoring and can be reconstructed
# without rerunning MCMC. The checkpoint is bound to the frozen seed and hash.
set.seed(1691L)
n_draw <- 12L
K <- length(tau)
p <- ncol(fixture$Z)
fit <- list(
  beta_draws = matrix(stats::rnorm(n_draw * K * p), n_draw, K * p),
  alpha_draws = matrix(stats::rnorm(n_draw * K), n_draw, K),
  sigma_draws = matrix(stats::rexp(n_draw * K) + 0.2, n_draw, K),
  gamma_draws = do.call(cbind, lapply(tau, function(level) {
    support <- app_joint_exqdesn_support(level)
    stats::runif(
      n_draw,
      0.2 * support$lower[[1L]],
      0.2 * support$upper[[1L]]
    )
  })),
  tau = tau,
  init_source = "provided"
)
fit$beta_mean <- colMeans(fit$beta_draws)
fit$alpha_mean <- colMeans(fit$alpha_draws)
fit$sigma_mean <- colMeans(fit$sigma_draws)
fit$gamma_mean <- colMeans(fit$gamma_draws)
fit$qhat_mean <- fixture$Z %*% app_joint_qvp_beta_matrix(fit$beta_mean, K, p) +
  matrix(fit$alpha_mean, nrow(fixture$Z), K, byrow = TRUE)

temp_root <- tempfile("phase169r_test_")
dir.create(temp_root, recursive = TRUE)
freeze_dir <- file.path(temp_root, "freeze")
worker_dir <- file.path(temp_root, "worker")
dir.create(freeze_dir)
dir.create(worker_dir)
invisible(app_joint_qvp_write_csv(
  data.frame(label = "test", stringsAsFactors = FALSE),
  file.path(freeze_dir, "artifact_manifest.csv")
))
checkpoint <- app_joint_exqdesn_phase169_write_checkpoint(
  fit, fixture, job, elapsed_seconds = 1.25,
  freeze_dir = freeze_dir, worker_dir = worker_dir
)
stopifnot(app_joint_exqdesn_phase169_checkpoint_complete(worker_dir))
recovered <- app_joint_exqdesn_phase169_load_checkpoint(
  worker_dir, fixture, job, freeze_dir = freeze_dir
)
stopifnot(nrow(recovered$fit$beta_draws) == n_draw)
stopifnot(all(recovered$fit$sigma_draws > 0))
stopifnot(identical(
  checkpoint$metadata$freeze_manifest_sha256[[1L]],
  recovered$metadata$freeze_manifest_sha256[[1L]]
))

# Corrected plans may change only output locations and repair annotations.
plan <- data.frame(
  worker_id = 1:2,
  mcmc_case_id = c("case_a", "case_b"),
  inference_method_id = c("M0_v_collapsed_support_logit", "M1_u_collapsed_p_logit"),
  chain_id = c(1L, 2L),
  chain_seed = c(101L, 202L),
  worker_output_dir = c("old/a", "old/b"),
  stringsAsFactors = FALSE
)
corrected <- app_joint_exqdesn_phase169r_corrected_plan(
  plan, file.path(temp_root, "corrected")
)
stopifnot(identical(plan$chain_seed, corrected$chain_seed))
stopifnot(identical(plan$worker_id, corrected$worker_id))
stopifnot(all(corrected$original_worker_output_dir == plan$worker_output_dir))
stopifnot(all(corrected$worker_output_dir != plan$worker_output_dir))

unlink(temp_root, recursive = TRUE, force = TRUE)
cat("Phase169R recovery tests passed.\n")
