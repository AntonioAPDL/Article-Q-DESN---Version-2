#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application", "R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application", "scripts",
  "_joint_qdesn_persistent_tail_v7_bootstrap.R"))

contract <- app_joint_pht7_read_contract()
stopifnot(
  contract$version == "joint_qdesn_persistent_tail_v7_full_confirmation",
  contract$v6_head == "770be4f5c6c8d80b4b600f65390652e49571c06d",
  contract$candidate_id == "persistent_heavy_tail__fitfirst_v4_2430",
  identical(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)),
  identical(contract$model_ids, c("independent_qdesn_rhs", "joint_qdesn_rhs",
    "independent_exqdesn_rhs", "joint_exqdesn_rhs")),
  contract$expected_components == 17L,
  contract$chains_per_cell == 3L,
  contract$al_n_iter == 2000L,
  contract$exal_n_iter == 4000L,
  contract$exal_method == "M0_v_collapsed_support_logit",
  contract$practical_margin == 0.01,
  !contract$interval_overlap_is_equivalence,
  !contract$automatic_downstream_launch)

candidate <- data.frame(
  lower_rhs_tau0 = 1e-7, lower_rhs_zeta2_fixed = 0.01,
  median_rhs_tau0 = 1e-13, median_rhs_zeta2_fixed = 0.01,
  upper_rhs_tau0 = 3e-9, upper_rhs_zeta2_fixed = 0.03,
  lower_normal_rhs_tau0 = 1e-10, median_normal_rhs_tau0 = 1e-10,
  upper_normal_rhs_tau0 = 1e-10, stringsAsFactors = FALSE)
stopifnot(
  app_joint_pht6_prior_row(candidate, 0.05)$rhs_tau0 == 1e-7,
  app_joint_pht6_prior_row(candidate, 0.10)$rhs_tau0 == 1e-7,
  app_joint_pht6_prior_row(candidate, 0.25)$rhs_tau0 == 1e-13,
  app_joint_pht6_prior_row(candidate, 0.75)$rhs_tau0 == 1e-13,
  app_joint_pht6_prior_row(candidate, 0.90)$rhs_tau0 == 3e-9,
  app_joint_pht6_prior_row(candidate, 0.95)$rhs_zeta2_fixed == 0.03)

profile <- data.frame(tau = contract$tau,
  rhs_tau0 = c(1e-7, 1e-7, rep(1e-13, 3L), 3e-9, 3e-9),
  rhs_zeta2 = c(0.01, 0.01, rep(0.01, 3L), 0.03, 0.03),
  stringsAsFactors = FALSE)
packet <- list(prior_profile = profile,
  joint_prior = data.frame(anchor_tau0 = 1e-7, innovation_tau0 = 1e-13,
    anchor_zeta2 = 0.01, innovation_zeta2 = 0.01, stringsAsFactors = FALSE))
design <- list(tau = contract$tau,
  posterior_data_design_fingerprint = strrep("a", 64L))
row <- data.frame(scenario_id = contract$scenario_id, candidate_id = contract$candidate_id,
  model_id = "joint_exqdesn_rhs", likelihood_family = "exAL", fit_structure = "joint",
  inference_method_id = contract$exal_method, n_iter = contract$exal_n_iter,
  burn = contract$exal_burn, thin = contract$exal_thin, tau_seed_stride = 1009L,
  stringsAsFactors = FALSE)
target <- app_joint_pht7_target_contract(row, packet, design)
sampler <- app_joint_pht7_sampler_contract(row)
stopifnot(
  grepl("^[0-9a-f]{64}$", target$hash),
  grepl("^[0-9a-f]{64}$", sampler$hash),
  target$fields$value[target$fields$field == "sigma_support"] == "(0,Inf)",
  target$fields$value[target$fields$field == "coefficient_hierarchy"] ==
    "first_quantile_anchor_adjacent_differences",
  target$fields$value[target$fields$field == "exal_method"] == contract$exal_method,
  sampler$fields$value[sampler$fields$field == "scale_update_id"] ==
    "exact_M0_v_collapsed_scale_shape")

# Starting values are sampler state, not target support or target identity.
start_a <- list(sigma = rep(0.1, 7L), gamma = rep(-0.5, 7L))
start_b <- list(sigma = rep(100, 7L), gamma = rep(0.5, 7L))
stopifnot(!identical(start_a, start_b),
  identical(app_joint_pht7_target_contract(row, packet, design)$hash, target$hash))

row_al <- row
row_al$model_id <- "joint_qdesn_rhs"
row_al$likelihood_family <- "AL"
row_al$inference_method_id <- "AL_MCMC"
row_al$n_iter <- contract$al_n_iter
row_al$burn <- contract$al_burn
target_al <- app_joint_pht7_target_contract(row_al, packet, design)
sampler_al <- app_joint_pht7_sampler_contract(row_al)
stopifnot(target_al$hash != target$hash, sampler_al$hash != sampler$hash,
  sampler_al$fields$value[sampler_al$fields$field == "scale_update_id"] ==
    "direct_inverse_gamma_unbounded_v1")

chain_identity <- data.frame(model_cell_id = rep("cell", 3L),
  model_id = rep(row$model_id, 3L), likelihood_family = rep("exAL", 3L),
  complete_posterior_target_sha256 = rep(target$hash, 3L),
  effective_sampler_control_sha256 = rep(sampler$hash, 3L),
  stringsAsFactors = FALSE)
audit <- app_joint_swcf_chain_identity_audit(chain_identity, expected_chains = 3L)
stopifnot(nrow(audit) == 1L, audit$verified, audit$n_chains == 3L)
bad <- chain_identity
bad$effective_sampler_control_sha256[[3L]] <- sampler_al$hash
error <- tryCatch({ app_joint_swcf_chain_identity_audit(bad, expected_chains = 3L); NULL },
  error = base::identity)
stopifnot(inherits(error, "error"))

stopifnot(
  app_joint_pht7_interval_overlap(0, 1, 0.5, 2),
  !app_joint_pht7_interval_overlap(0, 1, 1.1, 2),
  app_joint_pht7_model_metadata("joint_exqdesn_rhs")$fit_structure == "joint",
  app_joint_pht7_model_metadata("joint_exqdesn_rhs")$likelihood_family == "exAL",
  app_joint_pht7_model_metadata("independent_qdesn_rhs")$fit_structure == "independent")

cell_candidate <- data.frame(scenario_id = contract$scenario_id,
  candidate_id = contract$candidate_id, architecture_signature = "unit_architecture",
  feature_contract = "pure_recursive_v1", input_scale = 0.075,
  response_lags = 12L, stringsAsFactors = FALSE)
cells <- app_joint_pht7_model_cells(cell_candidate, contract,
  "/tmp/vb_packet.rds", "/tmp/design.rds", "/tmp/fixture.rds")
stopifnot(nrow(cells) == 4L, !anyDuplicated(cells$model_cell_id),
  all(cells$input_scale == 0.075), all(cells$response_lags == 12L),
  all(cells$feature_contract == "pure_recursive_v1"),
  setequal(cells$model_id, contract$model_ids))

launcher <- paste(readLines(file.path(repo_root, "application", "scripts",
  "launch_joint_qdesn_persistent_tail_v7_stage.sh"), warn = FALSE), collapse = "\n")
stopifnot(
  grepl("jerez.be.ucsc.edu", launcher, fixed = TRUE),
  grepl("<= 15", launcher, fixed = TRUE),
  grepl("taskset -c", launcher, fixed = TRUE),
  grepl("OMP_NUM_THREADS=1", launcher, fixed = TRUE),
  grepl("branch == work/joint-qdesn-persistent-tail-v7-full-confirmation-20261126",
    launcher, fixed = TRUE),
  !grepl("finalize_joint_qdesn_persistent_tail_v7_stage", launcher, fixed = TRUE))

cat("JOINT_PERSISTENT_TAIL_V7_TEST_PASS expectations=49 production_runs=0\n")
