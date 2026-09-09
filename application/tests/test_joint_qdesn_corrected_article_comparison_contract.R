#!/usr/bin/env Rscript

if (!exists("app_joint_article_read_contract", mode = "function") ||
    !exists("app_joint_article_score_read_contract", mode = "function")) {
  file_arg <- sub(
    "^--file=", "",
    commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(trailingOnly = FALSE))]
  )
  repo_root <- normalizePath(file.path(dirname(file_arg), "..", ".."),
    mustWork = TRUE)
  source(file.path(repo_root, "application", "scripts",
    "_joint_qdesn_shared_backbone_article_confirmation_bootstrap.R"))
}

old_contract <- app_joint_article_read_contract(app_joint_article_contract_path())
contract <- app_joint_article_read_contract(
  app_joint_article_corrected_contract_path())
old_score <- app_joint_article_score_read_contract(
  app_joint_article_score_contract_path())
score <- app_joint_article_score_read_contract(
  app_joint_article_corrected_score_contract_path())

stopifnot(
  identical(old_contract$version,
    "joint_shared_backbone_article_confirmation_v1"),
  identical(old_score$version,
    "joint_qdesn_shared_backbone_article_score_packet_v1"),
  identical(contract$version,
    "joint_shared_backbone_article_confirmation_v2"),
  identical(contract$run_tag,
    "joint_qdesn_corrected_article_comparison_jerez_20260909"),
  identical(contract$execution_branch,
    "work/joint-qdesn-corrected-article-comparison-jerez-20260909"),
  identical(contract$host_profile_id, "jerez_corrected_20260909"),
  contract$expected_total_components == 136L,
  contract$expected_top_level_initializers == 32L,
  contract$total_chain_workers == 160L,
  contract$al_chains_per_cell == 5L,
  contract$exal_chains_per_cell == 5L,
  contract$initial_concurrency == 50L,
  contract$maximum_concurrency == 50L,
  contract$rhs_slab_variance == 1,
  isTRUE(contract$rhs_slab_fixed),
  isTRUE(contract$ordered_intercepts),
  identical(contract$coefficient_hierarchy,
    "first_quantile_anchor_adjacent_differences"),
  identical(contract$alpha_prior_center_policy,
    "gaussian_location_quantiles"),
  identical(contract$alpha_prior_sd_policy,
    "gaussian_residual_scale_multiplier"),
  contract$sigma_lower_bound == 0,
  is.infinite(contract$sigma_upper_bound),
  isTRUE(contract$posterior_target_hash_required),
  !contract$production_launched,
  !contract$desn_or_tau0_screen_allowed
)

# Materialize the complete dependency and seed plans without accessing runtime
# evidence or fitting a model.
scenario_id <- sprintf("scenario_%02d", seq_len(8L))
selected <- data.frame(
  scenario_order = seq_len(8L), scenario_id = scenario_id,
  article_seed = 7000L + seq_len(8L),
  candidate_id = paste0("candidate_", seq_len(8L)),
  architecture_signature = paste0("architecture_", seq_len(8L)),
  design_class = "shared_backbone",
  rhs_tau0 = rep(0.1, 8L), stringsAsFactors = FALSE
)
design_manifest <- data.frame(
  scenario_order = seq_len(8L), scenario_id = scenario_id,
  design_path = file.path(tempdir(), paste0(scenario_id, ".rds")),
  design_fingerprint = vapply(scenario_id, app_joint_qvp_sha256_text,
    character(1L)),
  p = 3L, fit_rows = 500L, validation_rows = 500L,
  scored_forecast_rows = 1000L, stringsAsFactors = FALSE
)
vb_plan <- app_joint_article_build_vb_plan(selected, design_manifest, contract)
stopifnot(
  nrow(vb_plan) == 136L,
  sum(vb_plan$model_id == "gaussian_rhs_initializer") == 8L,
  sum(vb_plan$model_id == "independent_qdesn_rhs") == 56L,
  sum(vb_plan$model_id == "independent_exqdesn_rhs") == 56L,
  sum(vb_plan$model_id == "joint_qdesn_rhs") == 8L,
  sum(vb_plan$model_id == "joint_exqdesn_rhs") == 8L,
  !anyDuplicated(vb_plan$component_seed),
  min(vb_plan$component_seed) > contract$vb_component_seed_base
)
model_map <- app_joint_article_model_map()
future <- merge(data.frame(scenario_id = scenario_id, stringsAsFactors = FALSE),
  data.frame(model_id = model_map$model_id, stringsAsFactors = FALSE),
  by = NULL)
future$fit_structure <- ifelse(grepl("independent", future$model_id),
  "independent", "joint")
future$likelihood_family <- ifelse(grepl("exqdesn", future$model_id),
  "exAL", "AL")
future$article_fixture_used_for_selection <- FALSE
cells <- app_joint_article_build_model_cells(future, design_manifest, contract)
mcmc_plan <- app_joint_article_build_mcmc_plan(cells, contract)
component_seeds <- app_joint_article_component_seed_plan(mcmc_plan, contract$tau)
stopifnot(
  nrow(cells) == 32L,
  nrow(mcmc_plan) == 160L,
  all(table(mcmc_plan$model_cell_id) == 5L),
  max(mcmc_plan$wave_id) == 4L,
  !anyDuplicated(mcmc_plan$chain_seed),
  !anyDuplicated(mcmc_plan$chain_start_seed),
  !anyDuplicated(component_seeds$component_seed)
)

stopifnot(
  identical(score$version,
    "joint_qdesn_corrected_article_score_packet_v2"),
  identical(score$runtime_root, file.path(
    "application", "cache",
    "joint_qdesn_corrected_article_comparison_jerez_20260909")),
  score$expected_vb_components == 136L,
  score$expected_initializers == 32L,
  score$expected_mcmc_workers == 160L,
  score$expected_model_cells == 32L,
  score$expected_contrasts == 16L,
  identical(score$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  identical(score$weights_qs,
    c(0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025)),
  abs(sum(score$weights_qs) - 0.90) < 1e-15,
  identical(score$joint_draw_coupling,
    "preserve_retained_joint_draw_identity"),
  identical(score$independent_draw_coupling,
    "within_chain_seeded_per_tau_permutation"),
  isTRUE(score$posterior_target_hash_required),
  isTRUE(score$historical_packets_separate),
  isTRUE(score$phase182_separate)
)

profile <- app_joint_article_read_host_profile(contract$host_profile_id)
stopifnot(
  nrow(profile) == 1L,
  profile$host[[1L]] == "jerez.be.ucsc.edu",
  profile$runtime_root[[1L]] == score$runtime_root,
  as.integer(profile$initial_concurrency[[1L]]) == 50L,
  as.integer(profile$maximum_concurrency[[1L]]) == 50L,
  !app_as_bool_vec(profile$production_launched)[[1L]]
)
capacity_guard <- Sys.getenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED",
  unset = NA_character_)
Sys.unsetenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED")
stopifnot(inherits(try(app_joint_article_assert_capacity_authorized(contract),
  silent = TRUE), "try-error"))
Sys.setenv(JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED = "JEREZ_50_IDLE")
stopifnot(isTRUE(app_joint_article_assert_capacity_authorized(contract)))
if (is.na(capacity_guard)) {
  Sys.unsetenv("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED")
} else {
  Sys.setenv(JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED = capacity_guard)
}
git_value_original <- app_joint_article_git_value
app_joint_article_git_value <- function(args, root = app_repo_root()) {
  if (identical(args, c("rev-parse", "--abbrev-ref", "HEAD"))) {
    return(contract$execution_branch)
  }
  git_value_original(args, root)
}
stopifnot(isTRUE(app_joint_article_assert_execution_branch(contract)))
wrong_branch_contract <- contract
wrong_branch_contract$execution_branch <- "work/not-the-corrected-branch"
stopifnot(inherits(try(app_joint_article_assert_execution_branch(
  wrong_branch_contract), silent = TRUE), "try-error"))
app_joint_article_git_value <- git_value_original

# Five chains must identify one target for every one of the 32 model cells.
cell_id <- sprintf("cell_%02d", seq_len(32L))
likelihood <- rep(c("AL", "exAL"), each = 16L)
hash <- vapply(cell_id, function(id) app_joint_qvp_sha256_text(
  paste("corrected-target", id, sep = "|")), character(1L))
posterior <- data.frame(
  model_cell_id = rep(cell_id, each = 5L),
  likelihood_family = rep(likelihood, each = 5L),
  posterior_target_sha256 = rep(hash, each = 5L),
  stringsAsFactors = FALSE
)
target_audit <- app_joint_article_target_hash_audit(posterior, contract)
stopifnot(
  nrow(target_audit) == 32L,
  all(target_audit$n_chains == 5L),
  all(target_audit$verified)
)
posterior$posterior_target_sha256[[2L]] <- hash[[2L]]
stopifnot(inherits(try(app_joint_article_target_hash_audit(
  posterior, contract), silent = TRUE), "try-error"))

# Contract mutation must fail closed rather than silently change the target.
bad_confirmation <- tempfile(fileext = ".csv")
bad <- contract$table
bad$value[bad$name == "rhs_slab_variance"] <- "2"
app_write_csv(bad, bad_confirmation)
stopifnot(inherits(try(app_joint_article_read_contract(bad_confirmation),
  silent = TRUE), "try-error"))

bad_score <- tempfile(fileext = ".csv")
bad <- score$table
bad$value[bad$name == "posterior_target_hashes"] <- "optional"
app_write_csv(bad, bad_score)
stopifnot(inherits(try(app_joint_article_score_read_contract(bad_score),
  silent = TRUE), "try-error"))

launcher <- readLines(app_path("application/scripts",
  "launch_joint_qdesn_corrected_article_comparison.sh"), warn = FALSE)
launcher_text <- paste(launcher, collapse = "\n")
stopifnot(
  grepl("joint_qdesn_shared_backbone_article_confirmation_contract_v2.csv",
    launcher_text, fixed = TRUE),
  grepl("joint_qdesn_corrected_article_score_contract_v2.csv",
    launcher_text, fixed = TRUE),
  grepl("--max-workers 50", launcher_text, fixed = TRUE),
  grepl("JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION", launcher_text,
    fixed = TRUE),
  grepl("JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED", launcher_text,
    fixed = TRUE),
  grepl("JEREZ_50_IDLE", launcher_text, fixed = TRUE),
  grepl("--preflight|--launch-vb|--launch-mcmc|--finalize-score",
    launcher_text, fixed = TRUE),
  !grepl("joint_qdesn_shared_backbone_article_confirmation_jerez_20260907",
    launcher_text, fixed = TRUE)
)

cat("Corrected JOINT article-comparison contract tests passed.\n")
