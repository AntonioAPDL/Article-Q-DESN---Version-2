#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R"))
app_set_repo_root(root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R",
  "joint_exqdesn_phase166_168_structured_vb.R"
)) source(app_path("application/R", file))

# Named paths must survive normalization and remain independently verifiable.
manifest_dir <- tempfile("joint_exqdesn_manifest_")
dir.create(manifest_dir)
writeLines("alpha", file.path(manifest_dir, "alpha.txt"))
writeLines("beta", file.path(manifest_dir, "beta.txt"))
manifest_result <- app_joint_exqdesn_write_manifest(c(
  alpha = file.path(manifest_dir, "alpha.txt"),
  beta = file.path(manifest_dir, "beta.txt")
), manifest_dir)
stopifnot(identical(manifest_result$manifest$label, c("alpha", "beta")))
verified <- app_joint_exqdesn_verify_manifest(manifest_dir, "test_manifest")
stopifnot(nrow(verified) == 2L, all(verified$status == "pass"))

# The full registry expands 160 scenario-structure groups into 480 rows.
selected <- expand.grid(
  scenario_number = seq_len(80L),
  model_id = c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
selected$scenario_ids <- sprintf("scenario_%03d", selected$scenario_number)
selected$candidate_id <- paste(selected$scenario_ids, selected$model_id, sep = "__")
selected$fit_structure <- ifelse(
  selected$model_id == "joint_exqdesn_rhs_vb", "joint", "independent"
)
registry <- app_joint_exqdesn_phase164_method_development_registry(
  selected,
  dirs = list(phase153_vb = "/verified/phase153")
)
stopifnot(nrow(registry) == 480L, !anyDuplicated(registry$phase166_candidate_id))

# All three inference methods for one scenario-structure group stay together.
assignments <- integer(nrow(registry))
for (worker_id in seq_len(20L)) {
  index <- app_joint_exqdesn_phase166_worker_row_indices(registry, worker_id, 20L)
  stopifnot(!any(assignments[index]))
  assignments[index] <- worker_id
}
stopifnot(all(assignments > 0L))
group_key <- paste(registry$scenario_ids, registry$fit_structure, sep = "::")
stopifnot(all(vapply(split(assignments, group_key), function(x) length(unique(x)) == 1L, logical(1L))))
stopifnot(all(vapply(split(registry$inference_method_id, group_key), length, integer(1L)) == 3L))

# A small full-API state confirms the explicit VB0 warm-start contract.
fixture <- app_joint_qvp_simulate_ts_toy_synthetic(
  Tn = 20L, tau = c(0.25, 0.75), seed = 2026080641L, innovation = "gaussian"
)
candidate <- data.frame(
  fit_structure = "joint", vb_max_iter = 2L,
  adaptive_vb_max_iter_grid = "2", vb_tol = 1.0e-4,
  rhs_vb_inner = 1L, tau0 = 0.5, zeta2 = 4,
  a_sigma = 0.1, b_sigma = 0.1, alpha_prior_sd = "Inf",
  alpha_min_spacing = 0, gamma_init_policy = "zero",
  review_adjustment_threshold = 0.1, max_dense_dim = 100L,
  stringsAsFactors = FALSE
)
warm <- app_joint_exqdesn_phase166_vb0_warm_start(candidate, fixture)
stopifnot(identical(warm$inference_method_id, "VB0_point_v"))
stopifnot(all(is.finite(warm$qhat_mean)), all(warm$sigma_mean > 0))

unlink(manifest_dir, recursive = TRUE, force = TRUE)
cat("Phase164/166 orchestration tests passed.\n")
