#!/usr/bin/env Rscript
source("application/scripts/_joint_qdesn_recursive_mean_forecast_bootstrap.R")
source(app_path("application/R/joint_qdesn_fixed_backbone_prior_screen.R"))
source(app_path("application/R/joint_qdesn_laplace_quantile_architecture.R"))
source(app_path("application/R/joint_qdesn_laplace_architecture_article_confirmation.R"))

expect_error <- function(expr) {
  failed <- tryCatch({force(expr); FALSE}, error = function(e) TRUE)
  stopifnot(failed)
}

ct <- app_joint_laplace_article_contract()
stopifnot(
  ct$article_chains == 5L,
  ct$article_al_iterations == 4000L,
  ct$article_exal_iterations == 8000L,
  ct$exal_mcmc_method == "M0_v_collapsed_support_logit",
  ct$article_fixture_used_for_selection == "false",
  ct$publication_allowed == "false"
)

baseline <- app_read_csv(app_path("tables/joint_qdesn_pure_desn_v1_selected_backbones.csv"))
baseline <- baseline[baseline$scenario_id == "laplace_bridge", , drop = FALSE]
baseline$architecture_id <- "arch_00"
baseline$baseline <- TRUE
candidate <- baseline
candidate$architecture_id <- "arch_02"
candidate$baseline <- FALSE
candidate$candidate_id <- "laplace_bridge__pure_ridge_146"
candidate$D <- 3L
candidate$n <- "8;8;8"
candidate$n_tilde <- "8;8"
candidate$retained_state_budget <- 24L
candidate$response_lags <- 1L
candidate$alpha <- "0.2;0.2;0.2"
candidate$rho <- "0.9;0.9;0.9"
candidate$rhs_tau0 <- 1e-4
architectures <- app_joint_qdesn_bind_rows(list(baseline, candidate))
plan <- app_joint_laplace_article_plan(ct, architectures)
stopifnot(
  nrow(plan$datasets) == 2L,
  nrow(plan$warmups) == 2L,
  nrow(plan$cells) == 8L,
  nrow(plan$chains) == 40L,
  all(table(plan$chains$cell_id) == 5L),
  !anyDuplicated(plan$chains$chain_seed),
  !anyDuplicated(plan$chains$start_seed),
  all(!plan$datasets$article_fixture_used_for_selection)
)

observed <- list(y = 1:3, Z = matrix(1:6, 3), fit_local = 1:2,
  validation_local = 3L, forecast_map = data.frame(origin_index = 1L,
    horizon = 1L, full_time_index = 3L), tau = ct$tau,
  true_q = matrix(seq_len(21), 3), raw_inputs_in_readout = FALSE,
  full_states_all_layers = TRUE)
parity <- app_joint_laplace_article_design_parity(observed, observed)
stopifnot(nrow(parity) == length(observed), all(parity$identical))
changed <- observed
changed$Z[1L, 1L] <- -1
stopifnot(any(!app_joint_laplace_article_design_parity(changed, observed)$identical))

models <- data.frame(model_id = c("independent_qdesn_rhs", "joint_qdesn_rhs",
  "independent_exqdesn_rhs", "joint_exqdesn_rhs"),
  likelihood = c("AL", "AL", "exAL", "exAL"),
  structure = c("independent", "joint", "independent", "joint"),
  stringsAsFactors = FALSE)
mock <- merge(data.frame(architecture_id = c("arch_00", "arch_02")), models,
  by = NULL, sort = FALSE)
mock$posterior_score_mean <- ifelse(mock$architecture_id == "arch_00", 1, .9)
mock$posterior_score_median <- mock$posterior_score_mean
mock$posterior_score_q025 <- mock$posterior_score_mean - .05
mock$posterior_score_q975 <- mock$posterior_score_mean + .05
mock$posterior_score_interval_width <- .1
mock$fit_oracle_mae <- .2
mock$raw_crossing_pairs <- 0L
mock$contract_crossing_pairs <- 0L
mock$functional_status <- "pass"
mock$canonical_raw_crossing_pairs <- 0L
mock$replicate_id <- "article_fixture"
comparison <- app_joint_laplace_article_comparison(mock, "arch_00", "arch_02")
ranked <- app_joint_arch_rank(mock, "arch_00", 1L, "posterior_score_mean")
decision <- ranked$decision[ranked$decision$architecture_id == "arch_02", ]
stopifnot(nrow(comparison$paired) == 4L,
  all(abs(comparison$paired$score_gain_percent - 10) < 1e-12),
  isTRUE(decision$both_joint_improve), isTRUE(decision$four_model_improves),
  isTRUE(decision$eligible))

mock$posterior_score_mean[mock$architecture_id == "arch_02" & mock$model_id == "joint_exqdesn_rhs"] <- 1.1
ranked_bad <- app_joint_arch_rank(mock, "arch_00", 1L, "posterior_score_mean")
decision_bad <- ranked_bad$decision[ranked_bad$decision$architecture_id == "arch_02", ]
stopifnot(!decision_bad$both_joint_improve, !decision_bad$eligible)

tmp <- tempfile("joint_laplace_article_hash_")
writeLines("immutable", tmp)
sha <- app_sha256_file(tmp)
app_joint_laplace_article_assert_file(tmp, sha, file.info(tmp)$size, "test input")
writeLines("changed", tmp)
expect_error(app_joint_laplace_article_assert_file(tmp, sha, label = "test input"))
unlink(tmp)

cat("PASS: frozen article contract, 2/8/40 plans, parity guard, promotion rule, and hash failure closure.\n")
