#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_sealed_v5_bootstrap.R"))

contract <- app_joint_pht5_read_contract()
stopifnot(
  identical(contract$source_head, "beedc227c0c40b2f4b77e0130f89c90bf1adc2da"),
  identical(contract$challenger_ids, c("persistent_heavy_tail__fitfirst_v4_3242",
    "persistent_heavy_tail__fitfirst_v4_2430")),
  contract$exact_candidate_id == "persistent_heavy_tail__fitfirst_v4_0002",
  contract$sealed_replicates == 5L,
  contract$expected_workers == 15L,
  contract$physical_workers == 15L,
  contract$promote_any_strict_mean_improvement,
  !contract$interval_overlap_is_equivalence,
  !contract$automatic_downstream_launch)

ids <- c(contract$challenger_ids, contract$exact_candidate_id)
registry <- data.frame(candidate_id = ids,
  scenario_id = contract$scenario_id,
  structural_signature = paste0("signature_", seq_along(ids)),
  candidate_role = c("layered_fit", "layered_fit", "named_control"),
  source_candidate_id = c(NA, NA, "persistent_heavy_tail__targeted_0209"),
  D = c(4L, 5L, 1L), n = c("6;10;14;18", "15;15;14;14;14", "24"),
  response_lags = c(2L, 3L, 1L), rho_requested_max = c(0.61, 0.999, 0.203),
  stringsAsFactors = FALSE)
finalists <- cbind(registry, data.frame(rhs_tau0 = c(0.1, 1e-13, 1e7),
  normal_rhs_tau0 = c(1, 1e-10, 1e5), rhs_zeta2_profile = c("64", "0.01", "4"),
  rhs_zeta2_fixed = c(64, 0.01, 4), prior_spec_id = paste0("p", 1:3),
  quantile_spec_id = paste0("q", 1:3), al_tau0_multiplier = c(0.1, 0.001, 100),
  qualification_role = c("v4_qualified_challenger", "v4_qualified_challenger",
    "exact_v2_control"), stringsAsFactors = FALSE))
sealed <- data.frame(scenario_id = contract$scenario_id, replicate_id = 1:5,
  dgp_seed = 70001:70005, fixture_path = paste0("/tmp/sealed_", 1:5, ".rds"),
  protected_rows_persisted = 0L, stringsAsFactors = FALSE)
plan <- app_joint_pht5_build_plan(finalists, registry, sealed, contract, strrep("a", 64L))
stopifnot(nrow(plan) == 15L, all(table(plan$candidate_id) == 5L),
  all(table(plan$replicate_id) == 3L), identical(plan$s1_worker_id, 1:15),
  all(plan$finalists_sha256 == strrep("a", 64L)))
bad_finalists <- finalists
bad_finalists$structural_signature[[1L]] <- "changed"
stopifnot(inherits(tryCatch({
  app_joint_pht5_build_plan(bad_finalists, registry, sealed, contract); NULL
}, error = identity), "error"))

make_scores <- function(challenger_one = c(0.449, 0.456, 0.451, 0.455, 0.454),
    challenger_two = c(0.452, 0.453, 0.454, 0.455, 0.456), crossing_two = 0L,
    lower_h1_two = 0.10) {
  exact <- c(0.455, 0.454, 0.456, 0.455, 0.455)
  score <- c(challenger_one, challenger_two, exact)
  data.frame(scenario_id = contract$scenario_id,
    candidate_id = rep(ids, each = 5L), replicate_id = rep(1:5, 3L),
    qualification_role = rep(c("v4_qualified_challenger", "v4_qualified_challenger",
      "exact_v2_control"), each = 5L),
    dgp_integrated_three_level_score = score,
    realized_three_level_score = score + 0.01,
    lower_fit_mae = rep(c(0.11, 0.105, 0.115), each = 5L),
    median_fit_mae = rep(c(0.035, 0.034, 0.037), each = 5L),
    upper_fit_mae = rep(c(0.115, 0.106, 0.125), each = 5L),
    lower_horizon1_mae = c(rep(0.10, 5L), rep(lower_h1_two, 5L), rep(0.124, 5L)),
    median_horizon1_mae = rep(c(0.031, 0.030, 0.032), each = 5L),
    upper_horizon1_mae = rep(c(0.11, 0.11, 0.122), each = 5L),
    hard_functional_pass = TRUE, convergence_review_only = FALSE,
    contract_crossing_pairs = c(rep(0L, 5L), rep(crossing_two, 5L), rep(0L, 5L)),
    stringsAsFactors = FALSE)
}

result <- app_joint_pht5_evaluate(make_scores(), contract)
stopifnot(
  result$decision$status == "V5_COMPLETE_SEVEN_LEVEL_CONTINUATION_AUTHORIZED",
  result$decision$selected_candidate_id == contract$challenger_ids[[1L]],
  result$decision$selected_interval_overlaps_exact,
  !result$decision$formal_equivalence_established,
  result$decision$evidence_interpretation ==
    "descriptive_mean_improvement_with_overlapping_marginal_intervals",
  nrow(result$contrasts) == 2L,
  all(result$contrasts$matched_replicates == 5L),
  all(!result$contrasts$formal_equivalence_established),
  all(result$aggregates$fit_capable))

crossing <- app_joint_pht5_evaluate(make_scores(
  challenger_one = rep(0.46, 5L), challenger_two = rep(0.44, 5L), crossing_two = 1L), contract)
stopifnot(crossing$decision$status == "V5_COMPLETE_RETAIN_EXACT_V2_STOP",
  crossing$decision$selected_candidate_id == contract$exact_candidate_id)

h1_failure <- app_joint_pht5_evaluate(make_scores(
  challenger_one = rep(0.46, 5L), challenger_two = rep(0.44, 5L), lower_h1_two = 0.30), contract)
stopifnot(h1_failure$decision$status == "V5_COMPLETE_RETAIN_EXACT_V2_STOP",
  !h1_failure$aggregates$lower_h1_gate[
    h1_failure$aggregates$candidate_id == contract$challenger_ids[[2L]]])

bad_scores <- make_scores()[-1L, ]
stopifnot(inherits(tryCatch({ app_joint_pht5_evaluate(bad_scores, contract); NULL },
  error = identity), "error"))

launcher <- paste(readLines(file.path(repo_root, "application", "scripts",
  "launch_joint_qdesn_persistent_tail_sealed_v5.sh"), warn = FALSE), collapse = "\n")
stopifnot(grepl("exactly 15 physical cores", launcher, fixed = TRUE),
  grepl("taskset -c", launcher, fixed = TRUE),
  grepl("OMP_NUM_THREADS=1", launcher, fixed = TRUE),
  !grepl("finalize_joint_qdesn_persistent_tail_sealed_v5", launcher, fixed = TRUE))

cat("JOINT_PERSISTENT_TAIL_SEALED_V5_TEST_PASS expectations=34 production_runs=0\n")
