#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
candidate_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
repo_root <- if (file.exists(file.path(candidate_root, "main.tex"))) {
  candidate_root
} else {
  normalizePath(getwd(), mustWork = TRUE)
}
prefix <- "joint_qdesn_pure_desn_v1_"
table_dir <- file.path(repo_root, "tables")
checks <- 0L
expect <- function(value, message) {
  checks <<- checks + 1L
  if (!isTRUE(value)) stop(paste("JOINT_PURE_DESN_CHECK_FAILED:", message), call. = FALSE)
}
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
read_table <- function(name) read.csv(file.path(table_dir, paste0(prefix, name)),
  stringsAsFactors = FALSE, check.names = FALSE)
read_text <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")
truth <- function(x) tolower(as.character(x)) %in% c("true", "t", "1")
close <- function(x, y, tolerance = 1e-12) {
  length(x) == length(y) && all(is.finite(x)) && all(is.finite(y)) &&
    all(abs(x - y) <= tolerance)
}

# These immutable hashes are copied from the authenticated 54-file integration
# inventory, SHA-256 e14362daf92ad2b8b750fef3519e21fc4a968e7fbb3edc010ddadfcf2603ad9e.
# They verify the complete packet, including regressions and the bounded review.
source_sha <- c(
  "forecast_score_summary.csv" = "a0be319e4486d5be122ad6dfe5ee9e2a470cd09ce5dfafc5d0af3925aecf2d1c",
  "crossing_summary.csv" = "80c929b6f94fefde8ed0a18126c538467759eca093aafae9fbef9eb33afb2e67",
  "posterior_contrast_summary.csv" = "d17c30c73a1a775eb032cc30cc4661d4686d6a1dbfc067033ecc4389fd4a9010",
  "scenario_winner_summary.csv" = "b378e0433efd9a04944f062e2a4edf70f17c187b63b287f51aea4daa30c2f509",
  "fit_oracle_diagnostics.csv" = "8ddcfe7740f3f58274f2517b148daa8a149a85d660dcfc73745f64ac303a0280",
  "complete_packet_comparison.csv" = "dc4024cc183097bf888f39c703b14c2db6db4e3a4eb7a27c5e5c50e8fc37275e",
  "recursive_policy_comparison.csv" = "1b38d1bb588138c1df230699f9c84554c897863c02b1dc4530dcb1839b4dfa11",
  "selected_backbones.csv" = "17856f23b4878eea6e0f5aa46ead8e31a315d2d11285f483674043db8e2f4129",
  "frozen_contract.csv" = "bbf8b12dd05d352eb0cfa84ffc71b9510ff667a68cecc897a29991f85cd683c7",
  "review_closeout_receipt.csv" = "1c2b99d2336636f0b5b55666620ca410a0e8137f8cf2dc9b435667da7bb4b903",
  "cell_plan.csv" = "bdd9b9406d0d0dedc468795797e9f96ca9fdb15e035eb2e4ef837634caf7dc72",
  "source_hashes.csv" = "9becc3a48616aecaff813ae230387faa24354de944e782b0b2cbca7058cc10b7",
  "manifest_audit.csv" = "396c3373772279885fd092d11ca5ff695faf56cf66dbe177d345d685ec2776ce",
  "mcmc_posterior_target_hash_audit.csv" = "fe477ae3769a40244505cd3d85a22364a52c11e58fc08770b05a11e1ac660ec1",
  "sampler_audit.csv" = "175eb77f3410546682aac1f1af9c3e8633e8805743d5b964f5783246971a8fc1"
)
for (name in names(source_sha)) {
  path <- file.path(table_dir, paste0(prefix, name))
  expect(file.exists(path), paste("Missing frozen source", name))
  expect(identical(sha256(path), unname(source_sha[[name]])),
    paste("Frozen source changed", name))
}

all_scores <- read_table("forecast_score_summary.csv")
score <- all_scores[all_scores$inference_method == "mcmc", , drop = FALSE]
crossing <- read_table("crossing_summary.csv")
crossing <- crossing[crossing$inference_method == "mcmc", , drop = FALSE]
contrasts <- read_table("posterior_contrast_summary.csv")
contrasts <- contrasts[contrasts$inference_method == "mcmc" &
  contrasts$contrast_type == "joint_minus_independent" &
  contrasts$recursive_policy == "mean_state", , drop = FALSE]
winners <- read_table("scenario_winner_summary.csv")
winners <- winners[winners$inference_method == "mcmc", , drop = FALSE]
fit <- read_table("fit_oracle_diagnostics.csv")
fit <- fit[fit$inference_method == "mcmc", , drop = FALSE]
comparison <- read_table("complete_packet_comparison.csv")
comparison <- comparison[comparison$inference_method == "mcmc", , drop = FALSE]
policy <- read_table("recursive_policy_comparison.csv")
policy <- policy[policy$inference_method == "mcmc", , drop = FALSE]
backbones <- read_table("selected_backbones.csv")
contract <- read_table("frozen_contract.csv")
review <- read_table("review_closeout_receipt.csv")
plan <- read_table("cell_plan.csv")
manifest_audit <- read_table("manifest_audit.csv")
target_audit <- read_table("mcmc_posterior_target_hash_audit.csv")
sampler_audit <- read_table("sampler_audit.csv")
provenance <- read_table("projection_provenance.csv")

scenarios <- c("asymmetric_laplace_tail", "gaussian_mixture_bridge",
  "laplace_bridge", "nonlinear_reservoir_friendly", "normal_bridge",
  "persistent_heavy_tail", "regime_shift", "student_t_location_scale")
models <- c("joint_qdesn_rhs_mcmc", "qdesn_rhs_independent_mcmc",
  "joint_exqdesn_rhs_mcmc", "exqdesn_rhs_independent_mcmc")
expect(nrow(all_scores) == 64L && nrow(score) == 32L &&
  all(table(all_scores$inference_method) == 32L), "Complete VB/MCMC packet cardinality")
expect(setequal(score$scenario_id, scenarios) && setequal(score$model_id, models) &&
  all(table(score$scenario_id, score$model_id) == 1L),
  "Eight scenarios and four model families must remain intact")
expect(all(is.finite(score$posterior_score_mean)) &&
  all(is.finite(score$posterior_score_median)) &&
  all(score$posterior_score_q025 <= score$posterior_score_median) &&
  all(score$posterior_score_median <= score$posterior_score_q975) &&
  close(score$posterior_score_interval_width,
    score$posterior_score_q975 - score$posterior_score_q025), "Score interval definitions")
expect(all(score$interval_scope == "mcmc_readout_uncertainty_conditional_on_mean_design") &&
  all(score$path_interval_scope == "mcmc_readout_and_recursive_state_path_uncertainty"),
  "Conditional averaged-feature and draw-specific recursive intervals remain distinct")
expect(sum(score$score_stability_status == "pass") == 31L &&
  sum(score$score_stability_status == "review") == 1L &&
  score$worker_id[score$score_stability_status == "review"] == 41L &&
  score$model_cell_id[score$score_stability_status == "review"] ==
    "laplace_bridge__joint_qdesn_rhs", "31 strict MCMC passes and original worker-41 review")
expect(nrow(review) == 1L && review$worker_id == 41L &&
  !truth(review$strict_score_gate_pass) && truth(review$review_eligible) &&
  review$status == "complete_with_score_stability_review" &&
  review$original_failure_manifest_sha256 ==
    "0f33c471f28ebf3051697557f426eec1913ca76ca97bf4f728183fdb33296fbd" &&
  review$strict_recovery_failure_manifest_sha256 ==
    "9a98668a29ea1ac2bdbcf5a2244dc10a4b262a3a997e8e348563170255b4dd94",
  "Bounded review retains original strict failure evidence")
expect(nrow(backbones) == 8L && setequal(backbones$scenario_id, scenarios) &&
  !anyDuplicated(backbones$scenario_id) &&
  all(truth(backbones$shared_across_four_quantile_rows)) &&
  all(truth(backbones$full_states_all_layers)) &&
  !any(truth(backbones$raw_inputs_in_readout)) &&
  all(backbones$protected_rows_used_for_selection == 0L) &&
  all(is.finite(backbones$rhs_tau0) & backbones$rhs_tau0 > 0),
  "One protected, pure-DESN backbone per scenario across four models")
expect(nrow(plan) == 64L && all(plan$fit_rows == 500L) &&
  all(plan$scored_forecast_rows == 990L) &&
  !any(truth(plan$article_fixture_used_for_selection)) &&
  all(vapply(split(plan, plan$scenario_id), function(x) {
    length(unique(x$architecture_signature)) == 1L &&
      length(unique(x$rhs_tau0)) == 1L &&
      length(unique(x$design_fingerprint)) == 1L
  }, logical(1L))), "Cell plan shares selected design and RHS specification within each scenario")
expect(nrow(target_audit) == 32L && all(target_audit$n_chains == 5L) &&
  all(truth(target_audit$verified)) &&
  setequal(target_audit$model_cell_id, score$model_cell_id),
  "Every five-chain cell has an audited common posterior target")
expect(nrow(manifest_audit) == 232L && all(manifest_audit$status == "pass") &&
  sum(manifest_audit$verified_payloads) == 4808L &&
  nrow(sampler_audit) == 1L && sampler_audit$exal_M0_workers == 80L &&
  sampler_audit$max_relative_jitter <= 1e-12,
  "Frozen manifest and exact-M0 sampler audits")
get_contract <- function(name) {
  x <- contract$value[contract$name == name]
  expect(length(x) == 1L, paste("Contract key", name))
  x[[1L]]
}
expect(identical(get_contract("tau_grid"), "0.05;0.10;0.25;0.50;0.75;0.90;0.95") &&
  identical(get_contract("trapezoidal_weights"), "0.025;0.100;0.200;0.250;0.200;0.100;0.025") &&
  as.integer(get_contract("origins")) == 33L &&
  as.integer(get_contract("horizons")) == 30L &&
  as.integer(get_contract("score_rows")) == 990L &&
  identical(get_contract("inverse_cdf_tail_rule"), "endpoint_clamp"),
  "Frozen quadrature, origin-horizon geometry, and tail rule")
expect(nrow(crossing) == 32L && !anyDuplicated(crossing$model_cell_id) &&
  all(score$contract_crossing_pairs == 0L) &&
  all(score$path_contract_crossing_pairs == 0L) &&
  all(score$canonical_contract_crossing_pairs == 0L) &&
  all(crossing$posterior_contract_crossing_pairs_max == 0L) &&
  all(crossing$path_posterior_contract_crossing_pairs_max == 0L),
  "Every retained grid satisfies the specified reporting transform")
crossing <- crossing[match(score$model_cell_id, crossing$model_cell_id), , drop = FALSE]
expect(close(crossing$canonical_raw_crossing_pairs, score$canonical_raw_crossing_pairs) &&
  close(crossing$posterior_raw_crossing_pairs_mean * 3750,
    score$raw_crossing_pairs, tolerance = 1e-6),
  "Posterior-mean and posterior-draw crossing summaries agree with source counts")
totals <- vapply(models, function(id)
  sum(score$canonical_raw_crossing_pairs[score$model_id == id]), numeric(1L))
expect(close(totals, c(11, 2645, 0, 288)) && 8L * 990L * 6L == 47520L,
  "Canonical raw crossings and denominators")
expect(close(totals / 47520 * 100,
  c(0.0231481481481481, 5.56607744107744, 0, 0.606060606060606)),
  "Crossing percentages use the full 47,520 opportunities per model")

computed_winners <- do.call(rbind, lapply(split(score, score$scenario_id), function(x) {
  x <- x[order(x$posterior_score_mean), , drop = FALSE]
  expect(max(x$posterior_score_q025[1:2]) <= min(x$posterior_score_q975[1:2]),
    paste("Winner/runner-up marginal intervals overlap", x$scenario_id[[1L]]))
  x[1L, , drop = FALSE]
}))
expect(nrow(winners) == 8L && sum(computed_winners$fit_structure == "joint") == 2L &&
  sum(computed_winners$fit_structure == "independent") == 6L &&
  identical(computed_winners$model_cell_id,
    winners$model_cell_id[match(computed_winners$scenario_id, winners$scenario_id)]),
  "Frozen 2-joint/6-independent numerical winner pattern")
expect(nrow(contrasts) == 16L &&
  sum(contrasts$q025_difference <= 0 & contrasts$q975_difference >= 0) == 12L &&
  all(contrasts$q975_difference[contrasts$scenario_id == "asymmetric_laplace_tail"] < 0) &&
  all(contrasts$q025_difference[contrasts$scenario_id == "laplace_bridge"] > 0) &&
  all(contrasts$coupling == "deterministic_index_coupling_for_descriptive_contrast"),
  "Descriptive contrasts preserve twelve overlaps and four directional intervals")
expect(nrow(fit) == 32L && all(is.finite(fit$fit_oracle_rmse)) &&
  all(fit$fit_oracle_rmse >= 0) &&
  all(fit$scope == "canonical_posterior_mean_action_oracle_diagnostic") &&
  !any(grepl("q025|q975|interval", names(fit))),
  "Fit recovery source contains point diagnostics only")
changed <- comparison[truth(comparison$specification_changed), , drop = FALSE]
expect(nrow(comparison) == 32L && nrow(changed) == 8L &&
  sum(changed$mean_difference < 0) == 3L &&
  sum(changed$mean_difference > 0) == 5L &&
  all(truth(changed$intervals_overlap_baseline)) &&
  all(comparison$mean_difference[!truth(comparison$specification_changed)] == 0),
  "All gains, regressions, reused rows and prior-narrow comparison retained")
expect(nrow(policy) == 32L &&
  sum(policy$mean_state_to_path_width_ratio < 1) == 28L &&
  abs(median(policy$mean_state_to_path_width_ratio) - 0.7364) < 0.00005,
  "Mean-design interval sensitivity remains accurately summarized")
rates <- read_table("crossing_rates.csv")
rates <- rates[match(models, rates$model_id), , drop = FALSE]
expect(nrow(rates) == 4L && close(rates$forecast_raw_pairs, totals) &&
  all(rates$forecast_opportunities == 47520L) &&
  all(rates$posterior_forecast_opportunities == 178200000L) &&
  all(rates$fit_opportunities == 24000L) &&
  close(rates$forecast_raw_percent, totals / 47520 * 100) &&
  close(rates$posterior_forecast_raw_percent,
    rates$posterior_forecast_raw_pairs / 178200000 * 100) &&
  all(rates$contract_pairs == 0L), "Generated crossing table uses complete denominators")
expected_provenance <- c(
  source_lane_head = "de83993e89fc085df8799a5f43ca71fd64dcb77b",
  handoff_sha256 = "16047c001451e6f14a5319e9e6942ed8829d861a237761fe8c413dc8ee695301",
  transfer_inventory_sha256 = "e14362daf92ad2b8b750fef3519e21fc4a968e7fbb3edc010ddadfcf2603ad9e",
  compact_verified_files = "54", compact_verified_bytes = "2256689",
  verified_manifests = "232", verified_payload_records = "4808",
  mcmc_cells = "32", mcmc_strict_pass = "31", mcmc_bounded_review = "1",
  bounded_review_worker = "41", score_draws_per_cell = "3750",
  forecast_adjacent_pairs_per_cell = "5940",
  main_interval_scope = "readout_uncertainty_conditional_on_each_models_averaged_recursive_design",
  baseline_scope = "previous_frozen_narrow_pure_DESN_packet_not_previous_published_article"
)
expect(!anyDuplicated(provenance$field) &&
  identical(as.character(provenance$value[match(names(expected_provenance), provenance$field)]),
    unname(expected_provenance)), "Projection identifies exact frozen inventory and baseline scope")

manifest_path <- file.path(table_dir, paste0(prefix, "article_asset_manifest.csv"))
expect(file.exists(manifest_path), "Article asset manifest exists")
manifest <- read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
expect(all(c("relative_path", "size_bytes", "sha256", "source_lane_head",
  "handoff_sha256", "transfer_inventory_sha256", "role", "metric", "interval_scope") %in%
  names(manifest)), "Manifest content and scientific provenance schema")
expect(all(manifest$source_lane_head == expected_provenance[["source_lane_head"]]) &&
  all(manifest$handoff_sha256 == expected_provenance[["handoff_sha256"]]) &&
  all(manifest$transfer_inventory_sha256 == expected_provenance[["transfer_inventory_sha256"]]),
  "Every generated asset identifies the same frozen source")
expect(nrow(manifest) > 10L && !anyDuplicated(manifest$relative_path) &&
  all(grepl("^(tables|figures)/", manifest$relative_path)) &&
  !any(grepl("(^|/)(cache|local_trackers|logs)(/|$)|\\.(rds|rda|RData|log|gz)$",
    manifest$relative_path)), "Manifest contains article-safe assets only")
for (i in seq_len(nrow(manifest))) {
  path <- file.path(repo_root, manifest$relative_path[[i]])
  expect(file.exists(path), paste("Manifest asset exists", manifest$relative_path[[i]]))
  expect(as.numeric(file.info(path)$size) == manifest$size_bytes[[i]] &&
    identical(sha256(path), as.character(manifest$sha256[[i]])),
    paste("Manifest asset hash", manifest$relative_path[[i]]))
}
for (name in names(source_sha)) {
  expect(paste0("tables/", prefix, name) %in% manifest$relative_path,
    paste("Manifest retains complete scientific source", name))
}
figures <- manifest[manifest$role == "figure", , drop = FALSE]
expect(nrow(figures) == 2L && setequal(figures$metric,
  c("posterior_score_mean", "fit_oracle_rmse")) &&
  figures$interval_scope[figures$metric == "posterior_score_mean"] ==
    "posterior_score_q025_q975_conditional_on_mean_design" &&
  figures$interval_scope[figures$metric == "fit_oracle_rmse"] == "point_diagnostic_no_intervals",
  "Forecast figure uses score means and intervals; fitting figure uses point RMSE only")
builder_path <- file.path(repo_root, "scripts/build_joint_qdesn_pure_desn_article_projection.R")
expect(file.exists(builder_path), "Reproducible article figure builder is present")
builder <- read_text(builder_path)
plot_start <- regexpr("plot_data <- data.frame", builder, fixed = TRUE)[[1L]]
plot_end <- regexpr("protocol <- table_start", builder, fixed = TRUE)[[1L]]
expect(plot_start > 0L && plot_end > plot_start, "Figure construction is explicitly bounded")
plot_code <- substring(builder, plot_start, plot_end - 1L)
expect(grepl("mean = mcmc$posterior_score_mean", plot_code, fixed = TRUE) &&
  grepl("lo = mcmc$posterior_score_q025", plot_code, fixed = TRUE) &&
  grepl("hi = mcmc$posterior_score_q975", plot_code, fixed = TRUE) &&
  !grepl("canonical_origin_marginal_dgp_integrated_acrps", plot_code, fixed = TRUE) &&
  !grepl("geom_vline|geom_point|geom_segment", plot_code),
  "Forecast plot has only the common style's posterior means and interval layers")
expect(grepl("fit_plot_data$mean <- fit_mcmc$fit_oracle_rmse", plot_code, fixed = TRUE) &&
  grepl("fit_plot$layers <- fit_plot$layers[-1L]", plot_code, fixed = TRUE),
  "Fit plotting code removes the unavailable interval layer")

main <- read_text(file.path(repo_root, "main.tex"))
supplement <- read_text(file.path(repo_root, "qdesn-supplement.tex"))
expect(grepl(paste0("tables/", prefix, "forecast_figure.tex"), main, fixed = TRUE) &&
  !grepl(paste0("tables/", prefix, "fit_figure.tex"), main, fixed = TRUE) &&
  grepl(paste0("tables/", prefix, "fit_figure.tex"), supplement, fixed = TRUE) &&
  grepl(paste0("tables/", prefix, "score_table.tex"), supplement, fixed = TRUE),
  "Forecast figure in main; fitting figure and complete score table in supplement")
expect(!grepl("\\\\input\\{tables/joint_qdesn_corrected_v4_", paste(main, supplement)),
  "Earlier corrected-v4 wrappers are no longer live article inputs")
expect(grepl("numerical quadrature", main, fixed = TRUE) &&
  grepl("q(\\gamma_k)q(\\sigma_k\\mid\\gamma_k)", supplement, fixed = TRUE) &&
  grepl("no additional latent baseline", main, fixed = TRUE) &&
  grepl("joint intercepts are ordered", supplement, fixed = TRUE) &&
  grepl("fixed intercept priors are calibrated", main, fixed = TRUE),
  "Executed structured-VB, anchored hierarchy and fixed intercept calibration are disclosed")
for (pdf in figures$relative_path) {
  path <- file.path(repo_root, pdf)
  info <- system2("pdfinfo", shQuote(path), stdout = TRUE, stderr = TRUE)
  expect(is.null(attr(info, "status")) &&
    any(grepl("^Pages:[[:space:]]+1$", info)), paste("One-page vector figure", pdf))
  images <- system2("pdfimages", c("-list", shQuote(path)), stdout = TRUE, stderr = TRUE)
  expect(is.null(attr(images, "status")) &&
    !any(grepl("^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+image", images)),
    paste("No raster model figure", pdf))
  visible <- system2("pdftotext", c("-layout", shQuote(path), "-"),
    stdout = TRUE, stderr = TRUE)
  label <- if (grepl("forecast", pdf, fixed = TRUE)) "DGP-integrated aCRPS" else
    "Fitting-sample quantile-path RMSE"
  expect(is.null(attr(visible, "status")) && any(grepl(label, visible, fixed = TRUE)) &&
    sum(lengths(regmatches(visible, gregexpr("c = ", visible, fixed = TRUE)))) == 32L,
    paste("Visible metric and all 32 crossing labels", pdf))
}
figure_wrapper_paths <- manifest$relative_path[
  grepl("_(forecast|fit)_figure\\.tex$", manifest$relative_path)]
expect(length(figure_wrapper_paths) == 2L, "Exactly two current JOINT figure wrappers")
wrappers <- paste(vapply(file.path(repo_root, figure_wrapper_paths), read_text,
  character(1L)), collapse = "\n")
expect(!grepl("canonical.action|black vertical|vertical marks|black marks",
  wrappers, ignore.case = TRUE), "Reader-facing figure captions contain no canonical-action markers")
overleaf <- trimws(readLines(file.path(repo_root, "overleaf/article_files.txt"), warn = FALSE))
overleaf <- overleaf[nzchar(overleaf) & !startsWith(overleaf, "#")]
expect(all(manifest$relative_path %in% overleaf) &&
  paste0("tables/", prefix, "article_asset_manifest.csv") %in% overleaf,
  "Overleaf includes all current reader outputs, source CSVs and manifest")
expect(!any(grepl("(^|/)(cache|local_trackers|logs)(/|$)|\\.(rds|rda|RData|log|gz)$",
  overleaf)), "Overleaf includes no scientific runtime payload")

# Compare protected application assets to the recorded main authority using Git
# object content, independent of any mutable ignored runtime evidence.
baseline <- "757522db0f85815244370ec92a194de132268883"
git <- function(args) system2("git", c("-C", shQuote(repo_root), args),
  stdout = TRUE, stderr = TRUE)
baseline_files <- git(c("ls-tree", "-r", "--name-only", baseline))
expect(is.null(attr(baseline_files, "status")), "Recorded baseline Git tree exists")
protected <- baseline_files[grepl("^tables/(pricefm|glofas)_|^figures/(pricefm|glofas)",
  baseline_files)]
expect(length(protected) > 20L, "Protected PriceFM/GloFAS article assets found")
changes <- git(c("diff", "--name-only", baseline, "--", shQuote(protected)))
expect(is.null(attr(changes, "status")) && !length(changes),
  "PriceFM and GloFAS article asset hashes remain unchanged")

cat(sprintf(paste0("JOINT_PURE_DESN_ARTICLE_PROJECTION_CHECK=PASS checks=%d ",
  "mcmc_cells=32 strict_pass=31 review=1 frozen_sources=15 assets=%d ",
  "protected_application_assets=%d\n"), checks, nrow(manifest), length(protected)))
