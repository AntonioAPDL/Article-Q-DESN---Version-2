#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase181_score_stability_bootstrap.R"
))

expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_equal <- function(x, y, message, tolerance = 1e-12) {
  if (!isTRUE(all.equal(x, y, tolerance = tolerance))) {
    stop(message, call. = FALSE)
  }
}

contract <- app_joint_qdesn_phase181_read_contract()
expect_true(
  contract$expected_total_cells == 32L &&
    contract$expected_extension_cells == 19L &&
    contract$expected_workers == 152L,
  "Phase181 frozen counts changed."
)
expect_true(
  identical(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  "Phase181 changed the current seven-level grid."
)
expect_true(
  !contract$mixing_blocks_promotion && !contract$coherence_blocks_promotion &&
    !contract$retuning_allowed,
  "Phase181 promotion or retuning policy changed."
)
expect_true(
  identical(formals(app_joint_qdesn_phase180_write_checkpoint)$checkpoint_role,
            "phase180_balanced_postfit_prescore"),
  "Phase180 checkpoint role did not retain its backward-compatible default."
)

set.seed(181)
loo_draws <- app_joint_qdesn_bind_rows(lapply(seq_len(8L), function(chain_id) {
  value <- rep(1, 20L)
  if (chain_id == 2L) value <- rep(9, 20L)
  data.frame(
    case_id = "unstable_case", chain_id = chain_id,
    dgp_integrated_acrps = value, stringsAsFactors = FALSE
  )
}))
loo <- app_joint_qdesn_phase181_chain_loo_audit(loo_draws)
expect_true(
  nrow(loo) == 1L && loo$dominant_chain_id[[1L]] == 2L &&
    loo$max_relative_loo_mean_shift[[1L]] > 0.05,
  "Phase181 leave-one-chain-out audit missed a dominant chain."
)

case_id <- sprintf("case_%02d", seq_len(32L))
likelihood <- c(rep("AL", 16L), rep("exAL", 16L))
status <- rep("pass", 32L)
status[c(seq_len(7L), 17:26)] <- "review"
score <- data.frame(
  case_id = case_id, scenario_id = rep(sprintf("scenario_%02d", 1:8), each = 4L),
  source_model_id = rep(c("joint_al", "independent_al", "joint_exal", "independent_exal"), 8L),
  likelihood_family = likelihood,
  fit_structure = rep(c("joint", "independent"), 16L),
  score_functional_status = status,
  posterior_score_mean = seq(0.2, 0.51, length.out = 32L),
  stringsAsFactors = FALSE
)
loo_table <- data.frame(
  case_id = case_id, chains = 8L, posterior_draws = 8000L,
  full_score_mean = score$posterior_score_mean,
  dominant_chain_id = 1L,
  dominant_chain_score_mean = score$posterior_score_mean,
  dominant_chain_loo_mean = score$posterior_score_mean,
  max_absolute_loo_mean_shift = 0,
  max_relative_loo_mean_shift = 0.001,
  minimum_chain_score_mean = score$posterior_score_mean,
  maximum_chain_score_mean = score$posterior_score_mean,
  stringsAsFactors = FALSE
)
loo_table$max_relative_loo_mean_shift[27:28] <- c(0.73, 0.08)
selection <- app_joint_qdesn_phase181_extension_selection(
  score, loo_table, contract
)
selected <- selection[selection$extension_selected, , drop = FALSE]
expect_true(
  nrow(selected) == 19L &&
    sum(selected$likelihood_family == "AL") == 7L &&
    sum(selected$likelihood_family == "exAL") == 12L,
  "Phase181 did not reproduce the frozen 7 AL plus 12 exAL scope."
)
expect_true(
  all(selection$extension_reason[27:28] == "chain_mean_instability"),
  "Phase181 did not retain the two additional chain-instability triggers."
)

cells <- data.frame(
  case_id = selected$case_id, mcmc_case_id = selected$case_id,
  scenario_id = selected$scenario_id, scenario_ids = selected$scenario_id,
  base_scenario_id = selected$scenario_id,
  source_model_id = selected$source_model_id,
  model_id = paste0(selected$source_model_id, "_mcmc"),
  display_label = selected$source_model_id,
  likelihood_family = selected$likelihood_family,
  fit_structure = selected$fit_structure,
  source_control_row_sha256 = paste0("hash_", seq_len(nrow(selected))),
  stringsAsFactors = FALSE
)
test_dirs <- list(chains = file.path(tempdir(), "phase181-test-chains"))
plan_a <- app_joint_qdesn_phase181_worker_plan(cells, test_dirs, contract)
plan_b <- app_joint_qdesn_phase181_worker_plan(cells, test_dirs, contract)
expect_equal(plan_a$chain_seed, plan_b$chain_seed,
             "Phase181 chain expansion is not deterministic.")
expect_true(
  nrow(plan_a) == 152L && !anyDuplicated(plan_a$chain_seed) &&
    all(table(plan_a$mcmc_case_id) == 8L) && all(plan_a$n_keep == 5000L),
  "Phase181 worker plan has invalid counts, seeds, or retention."
)
component <- app_joint_qdesn_phase180_component_seed_plan(plan_a, contract$tau)
expect_true(!anyDuplicated(component$component_seed),
            "Phase181 component seed plan contains collisions.")

baseline <- data.frame(
  case_id = c("improved_review", "worse_pass", "hard_fail"),
  posterior_score_mean = c(1, 1, 1),
  posterior_score_median = c(1, 1, 1),
  posterior_score_q025 = c(0.9, 0.9, 0.9),
  posterior_score_q975 = c(1.1, 1.1, 1.1),
  score_functional_status = "pass", coherence_status = "pass",
  contract_crossing_pairs = 0L, stringsAsFactors = FALSE
)
extension <- data.frame(
  case_id = baseline$case_id, scenario_id = paste0("s", 1:3),
  source_model_id = paste0("m", 1:3), likelihood_family = "exAL",
  fit_structure = "joint",
  posterior_score_mean = c(0.99, 1.01, 0.98),
  posterior_score_median = c(0.98, 1.00, 0.97),
  posterior_score_q025 = c(0.8, 0.8, 0.8),
  posterior_score_q975 = c(1.2, 1.2, 1.2),
  score_rank_rhat = c(1.20, 1.01, 1.01),
  score_bulk_ess = c(50, 1000, 1000), score_tail_ess = c(40, 900, 900),
  score_functional_status = c("review", "pass", "pass"),
  coherence_status = c("review", "pass", "pass"),
  contract_crossing_pairs = c(0L, 0L, 1L),
  stringsAsFactors = FALSE
)
triggers <- data.frame(
  case_id = baseline$case_id, extension_reason = "test",
  max_relative_loo_mean_shift = 0.1, stringsAsFactors = FALSE
)
source_status <- data.frame(
  case_id = baseline$case_id, source_status = "pass", stringsAsFactors = FALSE
)
decision <- app_joint_qdesn_phase181_promotion_decisions(
  baseline, extension, triggers, source_status
)
expect_true(
  decision$promotion_decision[decision$case_id == "improved_review"] ==
    "promote_phase181_extension",
  "Phase181 incorrectly let mixing/coherence review veto a lower hard-eligible mean."
)
expect_true(
  decision$promotion_decision[decision$case_id == "worse_pass"] ==
    "retain_phase180_baseline",
  "Phase181 promoted a non-improving mean."
)
expect_true(
  decision$promotion_decision[decision$case_id == "hard_fail"] ==
    "retain_phase180_baseline",
  "Phase181 promoted a contract-crossing hard failure."
)

source_rows <- function(prefix, cases, source_kind) {
  app_joint_qdesn_bind_rows(lapply(cases, function(id) {
    data.frame(
      worker_id = seq_len(8L), case_id = id, mcmc_case_id = id,
      chain_id = seq_len(8L), source_kind = source_kind,
      worker_output_dir = file.path(tempdir(), prefix, id, seq_len(8L)),
      stringsAsFactors = FALSE
    )
  }))
}
parent_plan <- source_rows("parent", baseline$case_id, "phase180_rerun")
extension_plan <- source_rows("extension", baseline$case_id, "phase181_extension")
selected_plan <- app_joint_qdesn_phase181_selected_source_plan(
  parent_plan, extension_plan, decision, baseline$case_id,
  n_chains = 8L, verify_workers = FALSE
)
expect_true(
  all(selected_plan$source_kind[selected_plan$case_id == "improved_review"] ==
        "phase181_extension") &&
    all(selected_plan$source_kind[selected_plan$case_id != "improved_review"] ==
        "phase180_rerun"),
  "Phase181 selected source recomposition ignored promotion decisions."
)

article_stub <- expand.grid(
  scenario_id = paste0("scenario_", 1:8),
  source_model_id = c(
    "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
  ), stringsAsFactors = FALSE
)
article_stub$scenario_label <- article_stub$scenario_id
article_stub$posterior_score_mean <- seq_len(nrow(article_stub)) / 100
article_stub$posterior_score_q025 <- article_stub$posterior_score_mean - 0.01
article_stub$posterior_score_q975 <- article_stub$posterior_score_mean + 0.01
article_stub$numerical_winner <- ave(
  article_stub$posterior_score_mean, article_stub$scenario_id,
  FUN = function(x) x == min(x)
) > 0
lines <- app_joint_qdesn_phase181_article_table_lines(article_stub)
expect_true(
  any(grepl("DGP-integrated finite-grid quantile score", lines, fixed = TRUE)) &&
    !any(grepl("Grid CRPS", lines, fixed = TRUE)),
  "Phase181 article table uses the wrong headline metric label."
)

real_cache_root <-
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
real_dirs <- app_joint_qdesn_phase181_dirs(real_cache_root)
if (dir.exists(real_dirs$parent_freeze) && dir.exists(real_dirs$parent_packet)) {
  real_parent <- app_joint_qdesn_phase181_verify_parent(real_dirs, contract)
  real_summary <- app_read_csv(file.path(
    real_dirs$parent_packet, "posterior_dgp_integrated_acrps_summary.csv"
  ))
  real_draws <- app_read_csv(file.path(
    real_dirs$parent_packet, "posterior_dgp_integrated_acrps_draws.csv.gz"
  ))
  real_loo <- app_joint_qdesn_phase181_chain_loo_audit(real_draws)
  real_selection <- app_joint_qdesn_phase181_extension_selection(
    real_summary, real_loo, contract
  )
  real_selected <- real_selection[
    real_selection$extension_selected, , drop = FALSE
  ]
  extra <- real_selected[
    real_selected$extension_reason == "chain_mean_instability",
    c("scenario_id", "source_model_id"), drop = FALSE
  ]
  expect_true(
    nrow(real_parent$freeze$registry) == 32L && nrow(real_selected) == 19L &&
      nrow(extra) == 2L &&
      setequal(
        extra$scenario_id, c("persistent_heavy_tail", "regime_shift")
      ) &&
      all(extra$source_model_id == "exqdesn_rhs_independent_vb"),
    "The real Phase180 packet no longer reproduces the frozen Phase181 scope."
  )
}
if (dir.exists(real_dirs$freeze) && dir.exists(real_dirs$packet)) {
  real_freeze <- app_joint_qdesn_phase181_load_freeze(real_dirs$freeze)
  real_contrast_draws <- app_read_csv(file.path(
    real_dirs$packet, "joint_independent_score_contrast_draws.csv.gz"
  ))
  expect_true(
    identical(
      sort(unique(real_contrast_draws$contrast_seed)),
      real_freeze$contract$contrast_pairing_seed + seq_len(16L)
    ),
    "The real Phase181 packet does not use the frozen contrast-seed rule."
  )
}

manifest_dir <- file.path(tempdir(), paste0("phase181-manifest-", Sys.getpid()))
dir.create(manifest_dir, recursive = TRUE, showWarnings = FALSE)
probe <- app_joint_qvp_write_csv(
  data.frame(status = "pass"), file.path(manifest_dir, "probe.csv")
)
invisible(app_joint_exqdesn_write_manifest(c(probe = probe), manifest_dir))
manifest_check <- app_joint_exqdesn_verify_manifest(
  manifest_dir, "phase181_test_manifest"
)
expect_true(nrow(manifest_check) == 1L && all(manifest_check$status == "pass"),
            "Phase181 manifest verification failed.")
unlink(manifest_dir, recursive = TRUE, force = TRUE)

cat("Phase181 score-stability extension tests passed.\n")
