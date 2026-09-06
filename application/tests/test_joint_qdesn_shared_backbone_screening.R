repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
  normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg))), "..", ".."), mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "latent_path_vb_al.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "latent_path_design.R",
  "joint_exqdesn_phase151_feature_design_screening.R",
  "glofas_normal_desn_part1_screening.R",
  "joint_qdesn_shared_backbone_screening.R"
)) source(app_path("application/R", path))

contract <- app_joint_shared_read_contract()
stopifnot(contract$max_workers == 10L)
stopifnot(contract$inner_training_rows + contract$inner_calibration_rows == contract$fit_rows)
stopifnot(identical(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)))

scenarios <- app_joint_shared_read_scenarios()
stopifnot(sum(scenarios$enabled) == 1L, scenarios$scenario_id[scenarios$enabled] == "regime_shift")

universe_a <- app_joint_shared_candidate_universe()
universe_b <- app_joint_shared_candidate_universe()
stopifnot(nrow(universe_a) > contract$novel_candidate_count)
stopifnot(!anyDuplicated(universe_a$architecture_signature))
stopifnot(identical(universe_a$architecture_signature, universe_b$architecture_signature))

authority <- data.frame(
  scenario_id = rep("regime_shift", 4L),
  source_model_id = c("joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"),
  candidate_id = paste0("authority_", seq_len(4L)),
  design_role = "frozen_base_fixture", design_class = "frozen_base_fixture",
  tau0 = c(0.35, 0.20, 0.1005, 0.335), zeta2 = c(16, 16, 64, 32),
  alpha_prior_sd = c(0.5, 0.45, 1, 1.25), stringsAsFactors = FALSE
)
built <- app_joint_shared_candidates("regime_shift", authority, 12L)
stopifnot(nrow(built$candidates) == 13L)
stopifnot(sum(built$candidates$candidate_role == "mandatory_authority_anchor") == 1L)
stopifnot(nrow(built$authority_audit) == 4L)

set.seed(1)
n <- 2000L
roles <- c(rep("desn_washout", 500L), rep("fit", 500L), rep("validation", 1000L))
Z <- cbind(lag_y = stats::rnorm(n), trend = seq_len(n) / n, regime = as.numeric(seq_len(n) > 1000L))
y <- 0.4 * Z[, 1L] + 0.2 * Z[, 2L] + stats::rnorm(n, sd = 0.25)
full_fixture <- list(
  scenario_id = "regime_shift", scenario_class = "stress", distribution_family = "student_t",
  dynamics_class = "regime_shift", y = y, Z = Z, tau = contract$tau,
  true_q = outer(y, stats::qnorm(contract$tau), function(mu, q) mu + 0.25 * q),
  detailed_split = data.frame(full_time_index = seq_len(n), role = roles, stringsAsFactors = FALSE),
  seed = 1L, seed_role = "test"
)
selector <- app_joint_shared_selector_fixture(full_fixture, contract)
stopifnot(length(selector$y) == 1000L, nrow(selector$Z) == 1000L)
stopifnot(!any(selector$detailed_split$role == "validation"))
stopifnot(selector$protected_rows_persisted == 0L)

direct <- built$candidates[1L, , drop = FALSE]
direct_design <- app_joint_shared_design(selector, direct, contract)
stopifnot(nrow(direct_design$X) == 1000L)
stopifnot(length(direct_design$train_local) == 350L, length(direct_design$calibration_local) == 150L)
stopifnot(direct_design$diagnostic$protected_rows_loaded == 0L)

reservoir <- direct
reservoir$candidate_id <- "tiny_reservoir"
reservoir$candidate_role <- "novel_shared_backbone"
reservoir$design_class <- "reservoir"
reservoir$D <- 1L; reservoir$n <- "4"; reservoir$n_tilde <- ""
reservoir$retained_state_budget <- 4L; reservoir$width_shape <- "flat"
reservoir$state_reduction <- FALSE; reservoir$alpha_schedule <- "balanced"
reservoir$alpha <- "0.5"; reservoir$rho <- "0.9"; reservoir$pi_w <- "0.2"
reservoir$pi_in <- "1"; reservoir$input_scale <- 0.25; reservoir$reservoir_seed <- 42L
reservoir$architecture_signature <- app_joint_shared_architecture_signature(reservoir)
reservoir_design <- app_joint_shared_design(selector, reservoir, contract)
stopifnot(ncol(reservoir_design$X) == 5L, all(is.finite(reservoir_design$X)))

ridge <- app_joint_shared_score_ridge(selector, reservoir, contract)
stopifnot(is.finite(ridge$summary$calibration_acrps_mean), ridge$summary$protected_rows_loaded == 0L)
stopifnot(all(app_joint_shared_acrps(c(0, 1), matrix(c(0, 1), 2L, length(contract$tau)), contract$tau) == 0))

aggregate <- data.frame(
  candidate_id = paste0("c", seq_len(35L)),
  candidate_role = c("mandatory_authority_anchor", rep("novel_shared_backbone", 34L)),
  hard_gate_status = "pass", calibration_acrps_mean = c(10, seq(0.01, 0.34, length.out = 34L)),
  calibration_acrps_between_rep_sd = 0.01, calibration_exact_gaussian_crps_mean = 1,
  stringsAsFactors = FALSE
)
frontier <- app_joint_shared_select_top30(aggregate, 30L)
stopifnot(nrow(frontier$selected) == 30L, "c1" %in% frontier$selected$candidate_id)
stopifnot(!("c1" %in% frontier$pure$candidate_id))

manifest_dir <- tempfile("joint_shared_manifest_")
dir.create(manifest_dir)
one <- file.path(manifest_dir, "one.txt")
two <- file.path(manifest_dir, "two.txt")
writeLines("one", one); writeLines("two", two)
app_joint_shared_write_manifest(manifest_dir, c(one = one, two = two))
stopifnot(all(app_joint_shared_verify_manifest(manifest_dir)$verified))

cat("JOINT shared-backbone screening tests passed.\n")
