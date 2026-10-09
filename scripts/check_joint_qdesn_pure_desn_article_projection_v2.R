#!/usr/bin/env Rscript

# Read-only verification of the coherent Laplace replacement. Historical
# scientific inputs are immutable; only eight Laplace method--model rows change.
options(stringsAsFactors = FALSE, digits = 17)
arguments <- commandArgs(trailingOnly = TRUE)
argument <- function(flag, default) {
  at <- match(flag, arguments)
  if (is.na(at)) return(default)
  if (at == length(arguments)) stop(paste("Missing value for", flag), call. = FALSE)
  arguments[[at + 1L]]
}
script_argument <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", script_argument), mustWork = TRUE)
repo_root <- normalizePath(argument("--repo-root", file.path(dirname(script_path), "..")),
                           mustWork = TRUE)
data_only <- "--data-only" %in% arguments
checks <- 0L
expect <- function(value, message) {
  checks <<- checks + 1L
  if (!isTRUE(value)) stop(paste("JOINT_PURE_DESN_V2_CHECK_FAILED:", message), call. = FALSE)
}
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
path <- function(relative) file.path(repo_root, relative)
read_text <- function(relative) paste(readLines(path(relative), warn = FALSE), collapse = "\n")
read_table <- function(suffix, version = "v2") {
  relative <- paste0("tables/joint_qdesn_pure_desn_", version, "_", suffix, ".csv")
  expect(file.exists(path(relative)), paste("Missing projection table", relative))
  read.csv(path(relative), check.names = FALSE, stringsAsFactors = FALSE)
}
truth <- function(x) tolower(as.character(x)) %in% c("true", "t", "1")
close <- function(x, y, tolerance = 1e-12) {
  length(x) == length(y) && all(is.finite(x)) && all(is.finite(y)) &&
    all(abs(x - y) <= tolerance)
}
key <- function(x, fields = c("scenario_id", "model_cell_id", "inference_method")) {
  expect(all(fields %in% names(x)), paste("Missing semantic key", paste(fields, collapse = ",")))
  do.call(paste, c(x[fields], sep = "|"))
}
models <- c("joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
            "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc")
scenario_ids <- c("asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
                  "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
                  "regime_shift", "student_t_location_scale")
frozen_sha <- c(
  forecast_score_summary = "a0be319e4486d5be122ad6dfe5ee9e2a470cd09ce5dfafc5d0af3925aecf2d1c",
  crossing_summary = "80c929b6f94fefde8ed0a18126c538467759eca093aafae9fbef9eb33afb2e67",
  posterior_contrast_summary = "d17c30c73a1a775eb032cc30cc4661d4686d6a1dbfc067033ecc4389fd4a9010",
  scenario_winner_summary = "b378e0433efd9a04944f062e2a4edf70f17c187b63b287f51aea4daa30c2f509",
  fit_oracle_diagnostics = "8ddcfe7740f3f58274f2517b148daa8a149a85d660dcfc73745f64ac303a0280",
  complete_packet_comparison = "dc4024cc183097bf888f39c703b14c2db6db4e3a4eb7a27c5e5c50e8fc37275e",
  recursive_policy_comparison = "1b38d1bb588138c1df230699f9c84554c897863c02b1dc4530dcb1839b4dfa11",
  selected_backbones = "17856f23b4878eea6e0f5aa46ead8e31a315d2d11285f483674043db8e2f4129",
  frozen_contract = "bbf8b12dd05d352eb0cfa84ffc71b9510ff667a68cecc897a29991f85cd683c7",
  review_closeout_receipt = "1c2b99d2336636f0b5b55666620ca410a0e8137f8cf2dc9b435667da7bb4b903",
  cell_plan = "bdd9b9406d0d0dedc468795797e9f96ca9fdb15e035eb2e4ef837634caf7dc72",
  source_hashes = "9becc3a48616aecaff813ae230387faa24354de944e782b0b2cbca7058cc10b7",
  manifest_audit = "396c3373772279885fd092d11ca5ff695faf56cf66dbe177d345d685ec2776ce",
  mcmc_posterior_target_hash_audit = "fe477ae3769a40244505cd3d85a22364a52c11e58fc08770b05a11e1ac660ec1",
  sampler_audit = "175eb77f3410546682aac1f1af9c3e8633e8805743d5b964f5783246971a8fc1"
)
for (suffix in names(frozen_sha)) {
  relative <- paste0("tables/joint_qdesn_pure_desn_v1_", suffix, ".csv")
  expect(file.exists(path(relative)) && identical(sha256(path(relative)), unname(frozen_sha[[suffix]])),
         paste("Immutable historical scientific source", relative))
}

# This comparison is deliberately exact after CSV parsing. Re-serializing a
# retained number with fewer significant digits is not an authorized change.
unchanged_non_laplace <- function(suffix, fields = c("scenario_id", "model_cell_id", "inference_method")) {
  old <- read_table(suffix, "v1")
  new <- read_table(suffix)
  expect(all(names(old) %in% names(new)), paste("Retained schema", suffix))
  old <- old[old$scenario_id != "laplace_bridge", , drop = FALSE]
  new <- new[new$scenario_id != "laplace_bridge", , drop = FALSE]
  old_key <- key(old, fields); new_key <- key(new, fields)
  expect(!anyDuplicated(old_key) && !anyDuplicated(new_key) && setequal(old_key, new_key),
         paste("Unchanged seven-scenario row set", suffix))
  new <- new[match(old_key, new_key), names(old), drop = FALSE]
  for (column in names(old)) {
    expect(isTRUE(all.equal(old[[column]], new[[column]], tolerance = 0,
                           check.attributes = FALSE)),
           paste("Unchanged seven-scenario values", suffix, column))
  }
}
for (suffix in c("forecast_score_summary", "crossing_summary", "fit_oracle_diagnostics",
                 "recursive_policy_comparison", "cell_plan", "scenario_winner_summary")) {
  unchanged_non_laplace(suffix)
}
unchanged_non_laplace("selected_backbones", "scenario_id")
old_target <- read_table("mcmc_posterior_target_hash_audit", "v1")
new_target <- read_table("mcmc_posterior_target_hash_audit")
keep <- !startsWith(old_target$model_cell_id, "laplace_bridge__")
target_match <- match(old_target$model_cell_id[keep], new_target$model_cell_id)
expect(!anyNA(target_match), "Retained posterior-target rows")
for (column in names(old_target)) {
  expect(isTRUE(all.equal(old_target[[column]][keep], new_target[[column]][target_match],
                         tolerance = 0, check.attributes = FALSE)),
         paste("Unchanged seven-scenario target audit", column))
}
old_contrast <- read_table("posterior_contrast_summary", "v1")
contrasts <- read_table("posterior_contrast_summary")
contrast_fields <- c("scenario_id", "inference_method", "recursive_policy", "contrast_type", "contrast_label")
old_keep <- old_contrast$scenario_id != "laplace_bridge"
new_keep <- contrasts$scenario_id != "laplace_bridge"
old_keys <- key(old_contrast[old_keep, ], contrast_fields)
new_keys <- key(contrasts[new_keep, ], contrast_fields)
expect(setequal(old_keys, new_keys) && !anyDuplicated(new_keys), "Retained non-Laplace contrasts")
matched_contrasts <- contrasts[new_keep, ][match(old_keys, new_keys), names(old_contrast)]
for (column in names(old_contrast)) {
  expect(isTRUE(all.equal(old_contrast[[column]][old_keep], matched_contrasts[[column]],
                         tolerance = 0, check.attributes = FALSE)),
         paste("Unchanged seven-scenario contrasts", column))
}

all_scores <- read_table("forecast_score_summary")
all_crossings <- read_table("crossing_summary")
all_fit <- read_table("fit_oracle_diagnostics")
policy <- read_table("recursive_policy_comparison")
plan <- read_table("cell_plan")
cardinality <- read_table("draw_cardinality")
for (object in list(all_scores, all_crossings, all_fit, policy, plan, cardinality)) {
  expect(nrow(object) == 64L && !anyDuplicated(key(object)) &&
           setequal(key(object), key(all_scores)), "Complete coherent 64-row method--model surface")
}
expect(setequal(all_scores$scenario_id, scenario_ids) && setequal(all_scores$model_id, models) &&
         all(table(all_scores$scenario_id, all_scores$inference_method) == 4L) &&
         all(table(all_scores$inference_method) == 32L), "Eight scenarios and four models per inference method")
expect(all(is.finite(as.matrix(all_scores[c("posterior_score_mean", "posterior_score_median",
         "posterior_score_q025", "posterior_score_q975", "path_posterior_score_mean",
         "path_posterior_score_q025", "path_posterior_score_q975")]))), "Every forecast and path score is finite")
expect(all(all_scores$posterior_score_q025 <= all_scores$posterior_score_median) &&
         all(all_scores$posterior_score_median <= all_scores$posterior_score_q975) &&
         close(all_scores$posterior_score_interval_width,
               all_scores$posterior_score_q975 - all_scores$posterior_score_q025) &&
         all(all_scores$path_posterior_score_q025 <= all_scores$path_posterior_score_median) &&
         all(all_scores$path_posterior_score_median <= all_scores$path_posterior_score_q975) &&
         close(all_scores$path_posterior_score_interval_width,
               all_scores$path_posterior_score_q975 - all_scores$path_posterior_score_q025),
       "Ordered credible limits and exact interval widths")
expect(all(all_scores$contract_crossing_pairs == 0L) &&
         all(all_scores$path_contract_crossing_pairs == 0L) &&
         all(all_scores$canonical_contract_crossing_pairs == 0L) &&
         all(all_crossings$posterior_contract_crossing_pairs_max == 0L) &&
         all(all_crossings$path_posterior_contract_crossing_pairs_max == 0L) &&
         all(all_fit$fit_contract_crossing_pairs == 0L), "Every reported grid satisfies its contract")
expect(all(is.finite(all_fit$fit_oracle_mae)) && all(is.finite(all_fit$fit_oracle_rmse)) &&
         all(all_fit$fit_oracle_rmse >= all_fit$fit_oracle_mae - 1e-12) &&
         all(all_fit$scope == "canonical_posterior_mean_action_oracle_diagnostic"),
       "Fit diagnostics contain genuine MAE and RMSE, not substituted quantities")
expect(all(plan$fit_rows == 500L) && all(plan$scored_forecast_rows == 990L) &&
         all(!truth(plan$raw_inputs_in_readout)) && all(truth(plan$shared_across_four_quantile_rows)) &&
         all(plan$protected_rows_used_for_selection == 0L) &&
         all(!truth(plan$article_fixture_used_for_selection)), "Protected evaluation and shared reservoir-only design")
expect(all(vapply(split(plan, plan$scenario_id), function(block) {
  length(unique(block$architecture_signature)) == 1L &&
    length(unique(block$rhs_tau0)) == 1L && length(unique(block$design_fingerprint)) == 1L
}, logical(1L))), "Every scenario shares one specification across its four models")

cardinality <- cardinality[match(key(all_scores), key(cardinality)), ]
expected_draws <- ifelse(all_scores$inference_method == "vb", 4000L,
  ifelse(all_scores$scenario_id == "laplace_bridge" & all_scores$likelihood_family == "exAL", 7500L, 3750L))
expect(identical(as.integer(cardinality$n_score_draws), as.integer(expected_draws)) &&
         all(cardinality$forecast_opportunities == 5940L) &&
         close(cardinality$posterior_forecast_opportunities, expected_draws * 5940),
       "Exact per-cell draw cardinalities, including all 7,500 Laplace exAL draws")
mcmc <- all_scores[all_scores$inference_method == "mcmc", ]
mcmc_count <- cardinality[all_scores$inference_method == "mcmc", ]
expect(all(mcmc_count$chains == 5L) &&
         all(mcmc_count$draws_per_chain * mcmc_count$chains == mcmc_count$n_score_draws),
       "Five-chain retained-draw cardinality")
expect(all(mcmc$score_stability_status == "pass"), "All 32 MCMC score-stability assessments pass")
expect(all(mcmc$interval_scope == "mcmc_readout_uncertainty_conditional_on_mean_design") &&
         all(all_scores$interval_scope[all_scores$inference_method == "vb"] ==
           "partial_vb_readout_uncertainty_conditional_on_point_intercepts_and_mean_design") &&
         all(!truth(all_scores$vb_alpha_uncertainty_included[all_scores$inference_method == "vb"])),
       "Conditional MCMC and partial VB uncertainty scopes remain explicit")
matched_crossing <- all_crossings[match(key(all_scores), key(all_crossings)), ]
expect(close(all_scores$raw_crossing_pairs,
             matched_crossing$posterior_raw_crossing_pairs_mean * cardinality$n_score_draws,
             tolerance = 1e-6) &&
         close(all_scores$canonical_raw_crossing_pairs, matched_crossing$canonical_raw_crossing_pairs),
       "Draw-wise and posterior-mean crossing summaries have consistent denominators")
global_crossing <- vapply(models, function(model) sum(mcmc$canonical_raw_crossing_pairs[
  mcmc$model_id == model]), numeric(1L))
expect(close(global_crossing, c(10, 2608, 0, 288)), "Corrected addendum global crossing totals")
laplace <- mcmc[mcmc$scenario_id == "laplace_bridge", ]
laplace <- laplace[match(models, laplace$model_id), ]
expect(close(laplace$posterior_score_mean, c(.362709, .361286, .362622, .362678), 5.1e-7) &&
         close(laplace$posterior_score_q025, c(.360626, .358934, .359978, .359731), 5.1e-7) &&
         close(laplace$posterior_score_q975, c(.365118, .364147, .365344, .366038), 5.1e-7) &&
         close(laplace$canonical_raw_crossing_pairs, c(0, 4, 0, 0)), "Frozen candidate Laplace means, intervals and crossings")
expect(all(is.finite(laplace$score_rank_rhat)) && max(laplace$score_rank_rhat) < 1.0047 &&
         all(is.finite(laplace$score_bulk_ess)) && min(laplace$score_bulk_ess) > 996.4,
       "Candidate score-functional diagnostics reproduce their frozen bounds")
fit_laplace <- all_fit[all_fit$scenario_id == "laplace_bridge" & all_fit$inference_method == "mcmc", ]
fit_laplace <- fit_laplace[match(laplace$model_cell_id, fit_laplace$model_cell_id), ]
expect(close(fit_laplace$fit_oracle_mae, c(.118775, .130753, .137552, .139525), 5.1e-7),
       "Fit MAE independently reconstructs the frozen candidate evidence")
expect(nrow(new_target) == 32L && !anyDuplicated(new_target$model_cell_id) &&
         all(new_target$n_chains == 5L) && all(truth(new_target$verified)) &&
         setequal(new_target$model_cell_id, mcmc$model_cell_id) &&
         all(grepl("^[[:xdigit:]]{64}$", new_target$posterior_target_sha256)),
       "All 32 five-chain posterior targets are verified")

within_family <- contrasts[contrasts$inference_method == "mcmc" &
  contrasts$recursive_policy == "mean_state" & contrasts$contrast_type == "joint_minus_independent", ]
expect(nrow(within_family) == 16L &&
         sum(within_family$q025_difference <= 0 & within_family$q975_difference >= 0) == 14L &&
         sum(within_family$q975_difference < 0) == 2L &&
         sum(within_family$q025_difference > 0) == 0L &&
         all(within_family$scenario_id[within_family$q975_difference < 0] == "asymmetric_laplace_tail"),
       "Fourteen contrast intervals include zero; only two asymmetric-tail intervals favor joint estimation")
laplace_contrast <- within_family[within_family$scenario_id == "laplace_bridge", ]
laplace_contrast <- laplace_contrast[match(c("AL joint minus independent", "exAL joint minus independent"),
  laplace_contrast$contrast_label), ]
expect(close(laplace_contrast$mean_difference, c(.001423, -.000056), 6e-7) &&
         close(laplace_contrast$q025_difference, c(-.002133, -.004372), 6e-7) &&
         close(laplace_contrast$q975_difference, c(.004879, .004134), 6e-7),
       "Frozen same-family deterministic-index Laplace contrasts")
winner <- do.call(rbind, lapply(split(mcmc, mcmc$scenario_id), function(block) {
  block <- block[order(block$posterior_score_mean), ]
  expect(max(block$posterior_score_q025[1:2]) <= min(block$posterior_score_q975[1:2]),
         paste("Winner and runner-up intervals overlap", block$scenario_id[[1L]]))
  block[1L, ]
}))
expect(sum(winner$fit_structure == "joint") == 2L &&
         sum(winner$fit_structure == "independent") == 6L &&
         winner$model_id[winner$scenario_id == "laplace_bridge"] == "qdesn_rhs_independent_mcmc",
       "Two joint and six independent descriptive winners")
winners <- read_table("scenario_winner_summary")
published_winners <- winners[winners$inference_method == "mcmc", ]
expect(identical(winner$model_cell_id, published_winners$model_cell_id[
  match(winner$scenario_id, published_winners$scenario_id)]), "Regenerated scenario-winner ledger agrees")
policy <- policy[match(key(all_scores), key(policy)), ]
expect(close(policy$posterior_score_mean, all_scores$posterior_score_mean) &&
         close(policy$path_posterior_score_mean, all_scores$path_posterior_score_mean) &&
         close(policy$mean_state_minus_path_mean,
               all_scores$posterior_score_mean - all_scores$path_posterior_score_mean) &&
         close(policy$mean_state_to_path_width_ratio,
               all_scores$posterior_score_interval_width / all_scores$path_posterior_score_interval_width),
       "Recursive-path sensitivity was reconstructed, not silently inherited for Laplace")
sampler <- read_table("sampler_audit")
expect("scope" %in% names(sampler) &&
         all(c("historical_v1_complete_packet_not_current_aggregate", "candidate_laplace_only") %in% sampler$scope),
       "Repair audits distinguish immutable historical aggregate from the candidate")
historical_sampler <- sampler[sampler$scope == "historical_v1_complete_packet_not_current_aggregate", ]
candidate_sampler <- sampler[sampler$scope == "candidate_laplace_only", ]
old_sampler <- read_table("sampler_audit", "v1")
expect(nrow(historical_sampler) == 1L && nrow(candidate_sampler) == 1L &&
         isTRUE(all.equal(historical_sampler[names(old_sampler)], old_sampler,
                         tolerance = 0, check.attributes = FALSE)) &&
         candidate_sampler$exal_M0_workers == 10L &&
         candidate_sampler$workers_with_repairs == 8L && candidate_sampler$total_repairs == 55L &&
         candidate_sampler$max_relative_jitter <= 1e-12,
       "All candidate exAL workers use exact M0; unreconstructable historical repair counts are not relabeled")
source_hashes <- read_table("source_hashes")
expect(all(c("role", "relative_path", "size_bytes", "sha256") %in% names(source_hashes)) &&
         all(grepl("^[[:xdigit:]]{64}$", source_hashes$sha256)), "Frozen source-hash ledger schema")
expect("b670b1deadd7fc056605780893b910c2480fec9f7eec9e48ee768ae112f3882b" %in% source_hashes$sha256 &&
         "13ea15c3b45e1cd373134b7e90bf643ccbf463bd703cff079f126ddb3f22efd3" %in% source_hashes$sha256,
       "Candidate scores and nested closeout manifest identify their frozen sources")
expect("53e33187f324d27f673986a12b79c36014e5f285a70f50673e61370c10ceb01a" %in% source_hashes$sha256 &&
         "f1df687cc2035fe75f5e527f189200a34196d5bf9daabf92765a82b1aa9e520e" %in% source_hashes$sha256,
       "The protected realization and known-DGP oracle retain their frozen identities")
context_source <- source_hashes[source_hashes$relative_path == "article/datasets/dataset_02/context.rds", ]
expect(nrow(context_source) == 1L && context_source$sha256 ==
         "1700e08d0caaa9dabd71d5318c068cf5dc9925fc6933df80c3b98da3562e3960",
       "The candidate retained-fit context has its authenticated frozen identity")
replacement <- read_table("replacement_ledger")
expect(nrow(replacement) == 8L && !anyDuplicated(key(replacement)) &&
         all(replacement$scenario_id == "laplace_bridge") &&
         setequal(key(replacement), key(all_scores[all_scores$scenario_id == "laplace_bridge", ])),
       "Exactly eight complete Laplace method--model replacements")
postprocessing <- read_table("postprocessing_provenance")
expect(all(c("name", "value") %in% names(postprocessing)) && !anyDuplicated(postprocessing$name),
       "Deterministic post-processing provenance schema")
proof_value <- function(name) {
  value <- postprocessing$value[postprocessing$name == name]
  expect(length(value) == 1L, paste("Unique post-processing provenance", name))
  as.character(value[[1L]])
}
expect(proof_value("source_lane_head") == "6ff88298d7f10814071a9fec4a9a6d32804cdfb1" &&
         proof_value("score_draw_policy") == "all_retained_candidate_MCMC_draws_AL3750_exAL7500" &&
         as.integer(proof_value("vb_score_draws")) == 4000L &&
         !truth(proof_value("vb_alpha_uncertainty_included")) &&
         proof_value("recursive_path_draws") == "all_final_score_draws" &&
         as.numeric(proof_value("native_path_reference_max_difference")) < 1e-10 &&
         proof_value("projection_arithmetic") == "10_2608_0_288",
       "Frozen fit reuse, complete draws, partial VB and native path equivalence are documented")
expect(grepl("^[[:xdigit:]]{64}$", proof_value("reconstruction_script_sha256")) &&
         identical(proof_value("candidate_context_sha256"), context_source$sha256) &&
         all(replacement$context_sha256 == context_source$sha256) &&
         grepl("R version 4[.]6[.]0", proof_value("R_version")) &&
         as.integer(proof_value("reconstructed_cells")) == 8L &&
         as.integer(proof_value("preserved_cells")) == 56L &&
         proof_value("strict_stability_half_score_denominator") == "absolute_mean_of_half_canonical_scores",
       "Pinned reconstruction engine, unchanged cells and original stability normalization are recorded")
expect(as.integer(proof_value("contrast_percentile_type")) == 7L &&
         as.integer(proof_value("score_percentile_type")) == 8L &&
         proof_value("historical_non_laplace_contrast_convention") == "preserved_unchanged_type8" &&
         proof_value("contrast_percentile_scope") == "reconstructed_Laplace_rows_only_matching_frozen_handoff",
       "Frozen Laplace contrast percentiles are distinguished from score and historical percentile conventions")
runtime_audit <- read_table("runtime_manifest_audit")
expect(nrow(runtime_audit) == 57L && sum(runtime_audit$verified_payloads) == 230L &&
         all(runtime_audit$status == "pass") &&
         as.integer(proof_value("runtime_verified_manifests")) == nrow(runtime_audit) &&
         as.integer(proof_value("runtime_verified_payloads")) == sum(runtime_audit$verified_payloads),
       "All owned nested runtime manifests verify; copied historical manifests remain source evidence")
state_stability <- read_table("state_stability_audit")
expect(nrow(state_stability) == 8L && !anyDuplicated(key(state_stability)) &&
         setequal(key(state_stability), key(replacement)) &&
         all(state_stability$rms_gate == .10) && all(state_stability$score_gate == .005) &&
         all(truth(state_stability$finite)) && all(truth(state_stability$pass)) &&
         all(state_stability$standardized_rms_half_difference <= state_stability$rms_gate) &&
         all(state_stability$half_canonical_score_relative_difference <= state_stability$score_gate),
       "All eight replacements meet the original finite/RMS/canonical-half-score stability criteria")

if (!data_only) {
  expect(identical(sha256(path("scripts/reconstruct_joint_qdesn_laplace_article_projection_v2.R")),
                   proof_value("reconstruction_script_sha256")),
         "Reconstruction provenance matches the committed post-processing engine")
  prefix <- "joint_qdesn_pure_desn_v2_"
  manifest <- read_table("article_asset_manifest")
  expect(all(c("relative_path", "size_bytes", "sha256", "role", "metric", "interval_scope") %in%
    names(manifest)) && !anyDuplicated(manifest$relative_path), "Versioned article-asset manifest schema")
  expect("source_lane_head" %in% names(manifest) &&
           all(manifest$source_lane_head == "6ff88298d7f10814071a9fec4a9a6d32804cdfb1"),
         "Every versioned article asset identifies the frozen scientific lane")
  expect(all(grepl("^(tables|figures)/", manifest$relative_path)) &&
           !any(grepl("(^|/)(cache|local_trackers|logs|\\.\\.)(/|$)|\\.(rds|rda|RData|log|gz)$",
                      manifest$relative_path)), "Only article-safe summary and vector assets are registered")
  for (i in seq_len(nrow(manifest))) {
    asset <- path(manifest$relative_path[[i]])
    expect(file.exists(asset) && file.info(asset)$size == manifest$size_bytes[[i]] &&
             identical(sha256(asset), manifest$sha256[[i]]),
           paste("Registered asset hash", manifest$relative_path[[i]]))
  }
  rates <- read_table("crossing_rates")
  rates <- rates[match(models, rates$model_id), ]
  posterior_opportunities <- vapply(models, function(model) sum(
    mcmc_count$posterior_forecast_opportunities[mcmc$model_id == model]), numeric(1L))
  posterior_pairs <- vapply(models, function(model) sum(mcmc$raw_crossing_pairs[
    mcmc$model_id == model]), numeric(1L))
  equal_scenario_percent <- vapply(models, function(model) {
    at <- mcmc$model_id == model
    mean(100 * mcmc$raw_crossing_pairs[at] / mcmc_count$posterior_forecast_opportunities[at])
  }, numeric(1L))
  expect(nrow(rates) == 4L && close(rates$forecast_raw_pairs, global_crossing) &&
           all(rates$forecast_opportunities == 47520L) && all(rates$fit_opportunities == 24000L) &&
           close(rates$posterior_forecast_opportunities, posterior_opportunities) &&
           close(rates$posterior_forecast_raw_pairs, posterior_pairs) &&
           close(rates$forecast_raw_percent, global_crossing / 47520 * 100) &&
           close(rates$posterior_forecast_raw_percent, posterior_pairs / posterior_opportunities * 100),
         "Global crossing rates sum actual likelihood-specific draw denominators")
  expect("posterior_forecast_raw_percent_equal_scenario" %in% names(rates) &&
           close(rates$posterior_forecast_raw_percent_equal_scenario, equal_scenario_percent),
         "Reader-facing posterior-draw rates weight the eight scenarios equally across model classes")
  expect(close(posterior_opportunities, c(178200000, 178200000, 200475000, 200475000)),
         "The complete exAL denominator includes all frozen Laplace draws")
  main <- read_text("main.tex"); supplement <- read_text("qdesn-supplement.tex")
  mcmc_policy <- policy[all_scores$inference_method == "mcmc", ]
  narrower_count <- sum(mcmc_policy$mean_state_to_path_width_ratio < 1)
  rounded_width_ratio <- sprintf("%.4f", median(mcmc_policy$mean_state_to_path_width_ratio))
  expect(grepl(sprintf("narrower in %d of %d comparisons", narrower_count, nrow(mcmc_policy)),
               supplement, fixed = TRUE) &&
           grepl(paste0("width ratio ", rounded_width_ratio), supplement, fixed = TRUE),
         "Supplementary interval-width count and median reproduce the complete recomposed packet")
  expect(grepl(paste0("tables/", prefix, "forecast_figure.tex"), main, fixed = TRUE) &&
           grepl(paste0("tables/", prefix, "fit_figure.tex"), supplement, fixed = TRUE) &&
           !grepl(paste0("tables/", prefix, "fit_figure.tex"), main, fixed = TRUE),
         "Forecast figure remains in main and fitting figure in supplement")
  expect(!grepl("\\\\input\\{tables/joint_qdesn_(pure_desn_v1|pro_review)_", paste(main, supplement)) &&
           !grepl("joint-qdesn-pure-desn-v1-", paste(main, supplement), fixed = TRUE),
         "No historical v1 wrappers or references remain live")
  required_tables <- paste0("tables/", prefix, c("protocol", "score_table", "secondary_score_table",
    "recursive_policy_table", "vb_score_table", "contrast_table", "crossing_table", "oracle_recovery_table"), ".tex")
  expect(all(vapply(required_tables, function(relative) grepl(relative, supplement, fixed = TRUE),
                    logical(1L))), "All dependent supplementary tables use the new complete packet")
  reader_assets <- manifest$relative_path[grepl("\\.tex$", manifest$relative_path)]
  reader_text <- paste(c(main, supplement, vapply(reader_assets, read_text, character(1L))), collapse = "\n")
  prohibited <- "arch_0[02]|\\b(Jerez|Muscat|branch|commit|runtime|candidate|tweak|screen|recovery launch|phase[0-9]+)\\b"
  # The generic methodological word 'screening' is not an internal identifier;
  # the prohibition concerns explicit campaign labels and article asset captions.
  expect(!grepl(prohibited, paste(vapply(reader_assets, read_text, character(1L)), collapse = "\n"),
                ignore.case = TRUE, perl = TRUE), "Reader-facing assets contain no internal scientific campaign labels")
  expect(!grepl("0\\.5194|0\\.525|one recursive-design stability|other twelve|both likelihoods for Laplace innovations",
                paste(main, supplement), ignore.case = TRUE), "Obsolete Laplace review and directional claims are removed")
  expect(!grepl("canonical.action|black vertical|vertical marks", reader_text, ignore.case = TRUE),
         "No internal canonical-action marker terminology is reader-facing")
  figures <- manifest[manifest$role == "figure", ]
  expect(nrow(figures) == 2L && setequal(figures$metric, c("posterior_score_mean", "fit_oracle_rmse")),
         "Exactly two vector figures retain the intended score and fitting metrics")
  expect(figures$interval_scope[figures$metric == "posterior_score_mean"] ==
           "posterior_score_q025_q975_conditional_on_mean_design" &&
           figures$interval_scope[figures$metric == "fit_oracle_rmse"] == "point_diagnostic_no_intervals",
         "Forecast figures show conditional score intervals; fitting figures show point RMSE only")
  for (i in seq_len(nrow(figures))) {
    relative <- figures$relative_path[[i]]
    info <- system2("pdfinfo", shQuote(path(relative)), stdout = TRUE, stderr = TRUE)
    expect(is.null(attr(info, "status")) && any(grepl("^Pages:[[:space:]]+1$", info)),
           paste("One-page vector PDF", relative))
    images <- system2("pdfimages", c("-list", shQuote(path(relative))), stdout = TRUE, stderr = TRUE)
    expect(is.null(attr(images, "status")) &&
             !any(grepl("^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+image", images)),
           paste("No raster model panels", relative))
    visible <- system2("pdftotext", c("-layout", shQuote(path(relative)), "-"), stdout = TRUE, stderr = TRUE)
    metric_label <- if (figures$metric[[i]] == "posterior_score_mean") "DGP-integrated aCRPS" else
      "Fitting-sample quantile-path RMSE"
    expect(is.null(attr(visible, "status")) && any(grepl(metric_label, visible, fixed = TRUE)) &&
             sum(lengths(regmatches(visible, gregexpr("c = ", visible, fixed = TRUE)))) == 32L &&
             !grepl(prohibited, paste(visible, collapse = "\n"), ignore.case = TRUE, perl = TRUE),
           paste("Visible metric, all 32 crossing labels and public wording", relative))
  }
  allowlist <- trimws(readLines(path("overleaf/article_files.txt"), warn = FALSE))
  allowlist <- allowlist[nzchar(allowlist) & !startsWith(allowlist, "#")]
  expect(!any(grepl("joint_qdesn_pure_desn_v1_|joint_qdesn_pro_review_", allowlist)),
         "Historical JOINT article outputs are excluded from the active Overleaf projection")
  expect(all(c(required_tables, figures$relative_path, paste0("tables/", prefix,
    c("forecast_figure.tex", "fit_figure.tex", "article_asset_manifest.csv"))) %in% allowlist),
    "Overleaf contains every new active reader asset")
  expect(!any(grepl("(^|/)(cache|local_trackers|logs)(/|$)|\\.(rds|rda|RData|log|gz)$", allowlist)),
         "No scientific runtime payload enters Overleaf")
  for (relative in allowlist[grepl("\\.(tex|csv|json|bib)$", allowlist)]) {
    expect(!grepl("/data/|/home/|/tmp/|local_trackers|application/cache|\\.(rds|rda|RData)([\"[:space:]]|$)",
      read_text(relative), ignore.case = TRUE), paste("No private/runtime path in public source", relative))
  }
}
cat(sprintf(paste0("JOINT_PURE_DESN_ARTICLE_PROJECTION_V2_CHECK=PASS checks=%d mode=%s ",
  "cells=64 mcmc_cells=32 strict_pass=32 review=0 frozen_v1_sources=15 ",
  "crossings=10/2608/0/288 unchanged_scenarios=7\n"), checks,
  if (data_only) "data_only" else "complete_article"))
