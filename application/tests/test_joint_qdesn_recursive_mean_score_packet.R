#!/usr/bin/env Rscript

if (!exists("app_joint_recursive_read_contract", mode = "function")) {
  file_arg <- sub("^--file=", "", commandArgs(FALSE)[grep(
    "^--file=", commandArgs(FALSE))])
  source(file.path(dirname(file_arg), "..", "scripts",
    "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
}

contract <- app_joint_recursive_read_contract()
contract_v2 <- app_joint_recursive_read_contract(app_path(
  "application/config/joint_qdesn_recursive_mean_forecast_contract_v2.csv"
))
contract_v3 <- app_joint_recursive_read_contract(app_path(
  "application/config/joint_qdesn_recursive_mean_forecast_contract_v3.csv"
))
recovery_contract <- app_joint_recursive_read_recovery_contract()
review_contract <- app_joint_recursive_read_review_contract()
stopifnot(
  contract$workers == 8L,
  contract$score_rows == 990L,
  identical(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  identical(contract$weights, c(0.025, 0.100, 0.200, 0.250, 0.200, 0.100, 0.025)),
  identical(contract_v2$state_half_split_method, "within_chain_alternating"),
  identical(contract_v2$state_extension_trigger, "either_stability_gate"),
  contract_v2$mcmc_state_rescue_draws_per_chain == 750L,
  contract_v2$vb_state_rescue_draws == 4000L,
  identical(contract_v3$state_half_split_method, "within_chain_alternating"),
  identical(contract_v3$state_extension_trigger, "either_stability_gate"),
  contract_v3$mcmc_available_draws_per_chain_al == 750L,
  contract_v3$mcmc_available_draws_per_chain_exal == 1500L,
  identical(contract_v3$mcmc_state_rescue_policy,
    "all_available_by_likelihood"),
  contract_v3$mcmc_score_draws_per_chain == 750L,
  recovery_contract$recovery_worker_id == 41L,
  recovery_contract$unchanged_worker_id == 56L,
  identical(recovery_contract$antithetic_pair_counts, c(1L, 2L)),
  recovery_contract$pair_seed_stride == 104729L,
  review_contract$recovery_worker_id == 41L,
  review_contract$antithetic_pair_count == 2L,
  review_contract$score_gate_multiplier == 1.05,
  review_contract$required_unique_posterior_draws == 3750L,
  review_contract$required_state_trajectory_draws == 15000L
)

chain_id <- rep(1:5, each = 8L)
balanced_half <- app_joint_recursive_half_assignment(
  chain_id, "within_chain_alternating"
)
stopifnot(
  all(table(chain_id, balanced_half) == 4L),
  identical(
    app_joint_recursive_half_assignment(rep(NA_integer_, 6L),
      "within_chain_alternating"),
    c(1L, 2L, 1L, 2L, 1L, 2L)
  )
)

toy_state_draws <- list(
  beta = matrix(seq_len(24L), nrow = 4L),
  alpha = matrix(seq_len(12L), nrow = 4L),
  chain_id = c(1L, 1L, 2L, 2L),
  source_draw_index = c(11L, 12L, 21L, 22L)
)
antithetic_one <- app_joint_recursive_antithetic_state_expansion(
  toy_state_draws, uniform_seed = 9025L, score_rows = 7L,
  pair_count = 1L
)
antithetic_two <- app_joint_recursive_antithetic_state_expansion(
  toy_state_draws, uniform_seed = 9025L, score_rows = 7L,
  pair_count = 2L
)
stopifnot(
  nrow(antithetic_one$beta) == 8L,
  nrow(antithetic_two$beta) == 16L,
  antithetic_one$unique_posterior_draws == 4L,
  antithetic_one$state_trajectory_draws == 8L,
  max(abs(antithetic_one$uniforms[seq(1L, 8L, 2L), ] +
    antithetic_one$uniforms[seq(2L, 8L, 2L), ] - 1)) < 1e-15,
  identical(antithetic_one$half_assignment,
    rep(c(1L, 2L, 1L, 2L), each = 2L)),
  identical(antithetic_one$source_draw_index,
    rep(toy_state_draws$source_draw_index, each = 2L)),
  identical(antithetic_two$beta[seq(1L, 16L, 4L), , drop = FALSE],
    toy_state_draws$beta)
)

fake_mcmc_cell <- data.frame(inference_method = "mcmc")
fake_vb_cell <- data.frame(inference_method = "vb")
fake_mcmc_al_cell <- data.frame(
  inference_method = "mcmc", likelihood_family = "AL"
)
fake_mcmc_exal_cell <- data.frame(
  inference_method = "mcmc", likelihood_family = "exAL"
)
stopifnot(
  identical(app_joint_recursive_state_tiers(fake_mcmc_cell, contract_v2)$draws,
    c(1000L, 2000L, 3750L)),
  identical(app_joint_recursive_state_tiers(fake_vb_cell, contract_v2)$draws,
    c(1000L, 2000L, 4000L)),
  identical(app_joint_recursive_state_tiers(fake_mcmc_al_cell, contract_v3)$draws,
    c(1000L, 2000L, 3750L)),
  identical(app_joint_recursive_state_tiers(fake_mcmc_exal_cell, contract_v3)$draws,
    c(1000L, 2000L, 7500L)),
  identical(app_joint_recursive_state_tiers(fake_vb_cell, contract_v3)$draws,
    c(1000L, 2000L, 4000L)),
  app_joint_recursive_should_extend(data.frame(
    finite_pass = TRUE, rms_pass = TRUE, score_pass = FALSE
  ), contract_v2),
  !app_joint_recursive_should_extend(data.frame(
    finite_pass = TRUE, rms_pass = TRUE, score_pass = FALSE
  ), contract)
)

declared_tiers <- app_joint_recursive_state_tiers(
  fake_mcmc_al_cell, contract_v3
)
prior_failure <- data.frame(
  tier_index = seq_len(nrow(declared_tiers)), tier = declared_tiers$tier,
  finite_pass = TRUE, rms_pass = TRUE, score_pass = FALSE,
  all_stability_pass = FALSE,
  contract_sha256 = app_sha256_file(contract_v3$path),
  contract_version = contract_v3$version,
  failure_message = "expected unit-test failure", stringsAsFactors = FALSE
)
validated_prior <- app_joint_recursive_validate_prior_failure(
  prior_failure, declared_tiers, contract_v3
)
stopifnot(
  nrow(validated_prior) == 3L,
  !"contract_sha256" %in% names(validated_prior),
  grepl("does not match", tryCatch({
    bad <- prior_failure
    bad$score_pass[[3L]] <- TRUE
    app_joint_recursive_validate_prior_failure(bad, declared_tiers, contract_v3)
    ""
  }, error = function(error) conditionMessage(error)), fixed = TRUE)
)

review_tiers <- data.frame(
  tier_index = 1:4,
  tier = c("initial", "extension", "full_posterior_rescue",
    "antithetic_uniform_rescue_2pair"),
  finite_pass = TRUE,
  rms_pass = TRUE,
  score_pass = FALSE,
  half_score_relative_difference = c(0.011, 0.010, 0.005135, 0.005194),
  pooled_canonical_score = c(0.5245, 0.5203, 0.5203745, 0.5201091),
  standardized_rms_half_difference = c(0.056, 0.042, 0.030, 0.0106),
  chain_score_max_relative_deviation = c(0.046, 0.027, 0.028, 0.0282),
  antithetic_pair_count = c(NA, NA, NA, 2),
  unique_posterior_draws = c(NA, NA, NA, 3750),
  state_trajectory_draws = c(NA, NA, NA, 15000),
  stringsAsFactors = FALSE
)
review_rescue <- list(
  allow_score_stability_review = TRUE,
  review_reference_diagnostics = review_tiers[1:3, ],
  score_gate_multiplier = review_contract$score_gate_multiplier,
  max_pooled_score_relative_drift =
    review_contract$max_pooled_score_relative_drift,
  max_rms_gate_fraction = review_contract$max_rms_gate_fraction,
  max_chain_score_relative_deviation =
    review_contract$max_chain_score_relative_deviation,
  required_unique_posterior_draws =
    review_contract$required_unique_posterior_draws,
  required_state_trajectory_draws =
    review_contract$required_state_trajectory_draws
)
review_decision <- app_joint_recursive_score_review_decision(
  review_tiers, review_rescue, contract_v3
)
stopifnot(
  app_as_bool_vec(review_decision$score_stability_review_eligible)[[1L]],
  review_decision$score_stability_review_ceiling[[1L]] == 0.00525,
  review_decision$score_stability_gate_excess[[1L]] > 0,
  review_decision$pooled_score_relative_drift[[1L]] < 0.001
)
bad_review_tiers <- review_tiers
bad_review_tiers$half_score_relative_difference[[4L]] <- 0.0053
stopifnot(!app_as_bool_vec(app_joint_recursive_score_review_decision(
  bad_review_tiers, review_rescue, contract_v3
)$score_stability_review_eligible)[[1L]])

final_review <- data.frame(
  worker_id = 1:64,
  half_score_relative_difference = rep(0.004, 64L),
  score_stability_status = c(rep(NA_character_, 63L), "review"),
  score_stability_review_eligible = c(rep(NA, 63L), TRUE),
  score_stability_review_ceiling = c(rep(NA_real_, 63L), 0.00525),
  pooled_score_relative_drift = c(rep(NA_real_, 63L), 0.00051),
  recovery_contract_sha256 = c(rep(NA_character_, 63L),
    app_sha256_file(app_joint_recursive_review_contract_path())),
  selected_tier = c(rep(NA_character_, 63L),
    "antithetic_uniform_rescue_2pair"),
  chain_score_max_relative_deviation = c(rep(NA_real_, 63L), 0.0282),
  stringsAsFactors = FALSE
)
final_review$worker_id[[64L]] <- 41L
final_review$half_score_relative_difference[[64L]] <- 0.005194
final_decision <- app_joint_recursive_final_score_stability(
  final_review, contract_v3
)
stopifnot(
  all(final_decision$accepted),
  sum(final_decision$strict_pass) == 63L,
  sum(final_decision$review_valid) == 1L,
  identical(final_decision$packet_status,
    "COMPLETE_WITH_ONE_SCORE_STABILITY_REVIEW")
)
bad_review_hash <- final_review
bad_review_hash$recovery_contract_sha256[[64L]] <- paste(rep("a", 64L), collapse = "")
stopifnot(!app_joint_recursive_final_score_stability(
  bad_review_hash, contract_v3
)$review_valid[[64L]])
expanded_review_decision <- app_joint_recursive_final_score_stability(
  bad_review_hash, contract_v3,
  allowed_review_contract_sha256 = bad_review_hash$recovery_contract_sha256[[64L]]
)
stopifnot(
  all(expanded_review_decision$accepted),
  sum(expanded_review_decision$review_valid) == 1L
)

failure_dir <- tempfile("joint_recursive_failure_")
on.exit(unlink(failure_dir, recursive = TRUE, force = TRUE), add = TRUE)
failure_diagnostics <- data.frame(
  tier = c("initial", "extension"), rms_pass = c(TRUE, TRUE),
  score_pass = c(FALSE, FALSE)
)
app_joint_recursive_write_failure_diagnostics(
  failure_dir, failure_diagnostics, contract_v2, "test failure"
)
persisted_failure <- app_read_csv(file.path(
  failure_dir, "failure_diagnostics.csv"
))
stopifnot(
  nrow(persisted_failure) == 2L,
  all(persisted_failure$contract_version == contract_v2$version),
  all(persisted_failure$failure_message == "test failure")
)

progress_dir <- tempfile("joint_recursive_progress_")
on.exit(unlink(progress_dir, recursive = TRUE, force = TRUE), add = TRUE)
app_joint_recursive_write_stability_progress(
  progress_dir, failure_diagnostics, contract_v3
)
persisted_progress <- app_read_csv(file.path(
  progress_dir, "stability_progress.csv"
))
stopifnot(
  nrow(persisted_progress) == 2L,
  all(persisted_progress$contract_version == contract_v3$version),
  all(persisted_progress$contract_sha256 == app_sha256_file(contract_v3$path))
)

mean <- c(-0.5, 0.3, 1.2)
covariance <- matrix(c(1, .2, 0, .2, .5, .1, 0, .1, .8), 3L)
draws <- app_joint_recursive_mvn_draws(mean, covariance, 50000L, 712L)
stopifnot(
  max(abs(colMeans(draws) - mean)) < 0.02,
  max(abs(stats::cov(draws) - covariance)) < 0.03,
  attr(draws, "covariance_repair")$material_negative[[1L]] == FALSE
)

beta <- matrix(seq_len(120), nrow = 20L, ncol = 6L)
alpha <- matrix(seq_len(60), nrow = 20L, ncol = 3L)
coupled_a <- app_joint_recursive_couple_independent(beta, alpha, 2L, 101L)
coupled_b <- app_joint_recursive_couple_independent(beta, alpha, 2L, 101L)
stopifnot(
  identical(coupled_a, coupled_b),
  !identical(coupled_a$beta, beta),
  identical(dim(coupled_a$beta), dim(beta))
)

set.seed(77L)
truth <- matrix(stats::rnorm(800L * 4L), nrow = 800L, ncol = 4L)
sorted_truth <- apply(truth, 2L, sort)
toy_oracle <- list(
  sorted_response = sorted_truth,
  prefix_response = apply(sorted_truth, 2L, cumsum),
  observed_y = truth[1L, ],
  true_q = t(apply(truth, 2L, stats::quantile,
    probs = contract$tau, names = FALSE, type = 8))
)
toy_design <- cbind(1, seq(-1, 1, length.out = 4L))
toy_beta <- matrix(0, nrow = 12L, ncol = 14L)
toy_alpha <- matrix(rep(stats::qnorm(contract$tau), each = 12L), nrow = 12L)
toy_scores <- app_joint_recursive_score_draws(
  toy_design, toy_beta, toy_alpha, toy_oracle,
  contract$tau, contract$weights, chunk_size = 5L
)
stopifnot(
  nrow(toy_scores) == 12L,
  all(is.finite(toy_scores$origin_marginal_dgp_integrated_acrps)),
  all(toy_scores$contract_crossing_pairs == 0L)
)

source_candidates <- c(
  Sys.getenv("JOINT_RECURSIVE_SOURCE_ROOT", unset = ""),
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_corrected_article_comparison_muscat_11core_20260909/application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909",
  app_joint_recursive_default_source()
)
source_root <- source_candidates[dir.exists(source_candidates)][1L]
if (length(source_root) && !is.na(source_root)) {
  plans <- app_joint_recursive_build_plans(source_root, contract)
  stopifnot(
    nrow(plans$cells) == 64L,
    sum(plans$cells$inference_method == "vb") == 32L,
    sum(plans$cells$inference_method == "mcmc") == 32L,
    nrow(plans$oracle) == 32L,
    sum(app_as_bool_vec(plans$oracle$is_primary)) == 16L,
    sum(app_as_bool_vec(plans$cells$sentinel)) == 3L
  )
  independent <- plans$cells[
    plans$cells$fit_structure == "independent" &
      plans$cells$inference_method == "vb", , drop = FALSE][1L, ]
  vb <- app_joint_recursive_vb_draws(source_root, independent, 100L, 991L)
  stopifnot(
    nrow(vb$beta) == 100L,
    nrow(vb$covariance_repair) == length(contract$tau),
    !vb$alpha_uncertainty_included
  )
  for (family in c("AL", "exAL")) {
    mcmc <- plans$cells[
      plans$cells$inference_method == "mcmc" &
        plans$cells$likelihood_family == family, , drop = FALSE
    ][1L, ]
    available <- if (family == "AL") {
      contract_v3$mcmc_available_draws_per_chain_al
    } else contract_v3$mcmc_available_draws_per_chain_exal
    score_draws <- app_joint_recursive_mcmc_draws(
      source_root, mcmc, contract_v3$mcmc_score_draws_per_chain, 992L,
      use_all = FALSE
    )
    rescue_draws <- app_joint_recursive_mcmc_draws(
      source_root, mcmc, available, 993L, use_all = TRUE
    )
    stopifnot(
      nrow(score_draws$beta) == 5L * contract_v3$mcmc_score_draws_per_chain,
      nrow(rescue_draws$beta) == 5L * available,
      all(table(score_draws$chain_id) == contract_v3$mcmc_score_draws_per_chain),
      all(table(rescue_draws$chain_id) == available)
    )
  }
  cardinality <- app_joint_recursive_mcmc_cardinality_audit(
    source_root, contract_v3
  )
  stopifnot(
    nrow(cardinality) == 160L,
    all(cardinality$pass),
    identical(
      sort(unique(cardinality$observed_retained_draws)), c(750L, 1500L)
    )
  )
}

cat("test_joint_qdesn_recursive_mean_score_packet: PASS\n")
