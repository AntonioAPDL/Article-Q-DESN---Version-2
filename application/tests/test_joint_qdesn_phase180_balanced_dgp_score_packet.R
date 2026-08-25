#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(
  root, "application/scripts/_joint_qdesn_phase180_balanced_score_bootstrap.R"
))

expect_true <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
expect_equal <- function(x, y, message, tolerance = 1e-12) {
  if (!isTRUE(all.equal(x, y, tolerance = tolerance))) stop(message, call. = FALSE)
}

contract <- app_joint_qdesn_phase180_read_contract()
expect_true(exists("app_joint_qdesn_parse_iter_grid", mode = "function"),
            "Phase180 bootstrap omitted the AL adaptive-VB parser.")
control_probe <- app_joint_qdesn_phase122_controls_from_row(data.frame(
  vb_max_iter = 4L, adaptive_vb_max_iter_grid = "4,8", vb_tol = 1e-4,
  rhs_vb_inner = 1L, tau0 = 0.5, zeta2 = 16, a_sigma = 2, b_sigma = 1,
  alpha_prior_sd = "1", alpha_min_spacing = 0, gamma_init_policy = "zero",
  review_adjustment_threshold = 1e-3, max_dense_dim = 100L,
  stringsAsFactors = FALSE
))
expect_equal(control_probe$adaptive_vb_max_iter_grid, c(4L, 8L),
             "Phase180 AL controls did not parse the adaptive-VB grid.")

cache_test <- file.path(tempdir(), paste0("phase180-init-cache-", Sys.getpid()))
dir.create(cache_test, recursive = TRUE, showWarnings = FALSE)
cache_identity <- data.frame(
  mcmc_case_id = "test_case", source_control_row_sha256 = "control_hash",
  fixture_manifest_sha256 = "fixture_hash", code_commit = "commit_hash",
  stringsAsFactors = FALSE
)
cache_readme <- file.path(cache_test, "README.md")
writeLines("Phase180 test initialization cache", cache_readme)
cache_paths <- c(
  vb_initialization = app_joint_qvp_write_csv(
    data.frame(value = 1), file.path(cache_test, "vb_initialization.csv")
  ),
  vb_initialization_audit = app_joint_qvp_write_csv(
    data.frame(status = "pass"),
    file.path(cache_test, "vb_initialization_audit.csv")
  ),
  cache_identity = app_joint_qvp_write_csv(
    cache_identity, file.path(cache_test, "cache_identity.csv")
  ),
  README = normalizePath(cache_readme, mustWork = TRUE)
)
invisible(app_joint_exqdesn_write_manifest(cache_paths, cache_test))
expect_true(app_joint_qdesn_phase180_init_cache_complete(
  cache_test, cache_identity
), "Phase180 rejected a valid initialization cache.")
cache_identity$code_commit <- "different_commit"
expect_true(!app_joint_qdesn_phase180_init_cache_complete(
  cache_test, cache_identity
), "Phase180 reused an initialization cache across code commits.")
unlink(cache_test, recursive = TRUE, force = TRUE)

expect_equal(contract$tau, c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95),
             "Phase180 tau grid changed.")
expect_equal(contract$weights_qs, c(0.025, 0.10, 0.20, 0.25, 0.20, 0.10, 0.025),
             "Phase180 quadrature weights changed.")
expect_equal(sum(contract$weights_qs), 0.90,
             "Phase180 weights were renormalized.")
expect_true(contract$expected_final_cells == 32L &&
              contract$expected_reuse_cells == 11L &&
              contract$expected_rerun_cells == 21L &&
              contract$expected_new_workers == 168L,
            "Phase180 source counts changed.")

dummy <- data.frame(
  mcmc_case_id = sprintf("case_%02d", 1:21), case_id = sprintf("case_%02d", 1:21),
  scenario_id = rep(sprintf("scenario_%02d", 1:8), length.out = 21),
  scenario_ids = rep(sprintf("scenario_%02d", 1:8), length.out = 21),
  base_scenario_id = rep(sprintf("scenario_%02d", 1:8), length.out = 21),
  source_model_id = rep(c("joint_qdesn_rhs_vb", "joint_exqdesn_rhs_vb"),
                        length.out = 21),
  model_id = "model_mcmc", display_label = "Model",
  likelihood_family = c(rep("AL", 16), rep("exAL", 5)),
  fit_structure = rep(c("joint", "independent"), length.out = 21),
  candidate_id = "candidate", phase178_template_id = "template",
  variant_id = "variant", candidate_role = "frozen",
  design_role = "frozen", design_class = "frozen",
  source_action = "rerun", source_phase = "test", source_dir = tempdir(),
  phase172_case_dir = NA_character_, cell_index = 1:21,
  dgp_replicate_id = "article_fixture", validation_partition = "article_evaluation",
  article_fixture_used_for_selection = FALSE, global_specification_selected = FALSE,
  source_control_row_sha256 = sprintf("hash_%02d", 1:21),
  gamma_slice_width = 1, gamma_slice_max_steps = 100,
  stringsAsFactors = FALSE
)
dirs <- app_joint_qdesn_phase180_dirs(tempdir())
worker_plan <- app_joint_qdesn_phase180_worker_plan(dummy, dirs, contract)
component_plan <- app_joint_qdesn_phase180_component_seed_plan(
  worker_plan, contract$tau
)
expect_true(nrow(worker_plan) == 168L && !anyDuplicated(worker_plan$chain_seed),
            "Phase180 worker plan is not 168 unique chains.")
expect_true(!anyDuplicated(component_plan$component_seed),
            "Phase180 component seeds collide.")
expect_true(all(table(worker_plan$mcmc_case_id) == 8L),
            "Phase180 does not allocate eight chains per rerun cell.")
expect_true(all(worker_plan$sigma_upper_multiplier ==
                  contract$sigma_upper_multiplier),
            "Phase180 worker rows do not freeze the sigma support multiplier.")

set.seed(180)
fake <- list(
  beta_draws = matrix(rnorm(240), 20, 12),
  alpha_draws = matrix(rnorm(40), 20, 2),
  sigma_draws = matrix(rexp(40) + 0.1, 20, 2)
)
frame <- app_joint_qdesn_phase180_draw_frame(fake)
tmp_worker <- file.path(tempdir(), paste0("phase180-read-fit-", Sys.getpid()))
dir.create(file.path(tmp_worker, "checkpoint"), recursive = TRUE, showWarnings = FALSE)
invisible(app_joint_exqdesn_phase157_write_gzip_csv(
  frame, file.path(tmp_worker, "checkpoint", "posterior_draws.csv.gz")
))
read_fit <- app_joint_qdesn_phase180_read_fit(
  tmp_worker, c(0.25, 0.75), 1801L, 1L
)
expect_true(is.null(read_fit$gamma_draws),
            "AL checkpoint incorrectly acquired gamma draws.")
expect_true(all(is.finite(c(
  read_fit$beta_draws, read_fit$alpha_draws, read_fit$sigma_draws
))) && all(read_fit$sigma_draws > 0),
"AL checkpoint round trip is nonfinite.")
unlink(tmp_worker, recursive = TRUE, force = TRUE)

fake$gamma_draws <- matrix(rnorm(40), 20, 2)
frame_exal <- app_joint_qdesn_phase180_draw_frame(fake)
expect_true(sum(grepl("^gamma_", names(frame_exal))) == 2L,
            "exAL checkpoint did not preserve gamma draws.")

# Exercise every production sampler route with a minimal deterministic fixture.
set.seed(18001)
n <- 36L
Z <- cbind(x1 = stats::rnorm(n), x2 = stats::rnorm(n))
tau <- c(0.25, 0.50, 0.75)
y <- 0.3 + 0.5 * Z[, 1L] - 0.2 * Z[, 2L] + stats::rnorm(n, sd = 0.7)
fixture <- list(y = y, Z = Z, tau = tau)
control <- data.frame(
  alpha_prior_sd = "1", tau0 = 0.5, zeta2 = 16,
  a_sigma = 2, b_sigma = 1, alpha_min_spacing = 0,
  max_dense_dim = 100L, gamma_slice_width = 1,
  gamma_slice_max_steps = 20L, stringsAsFactors = FALSE
)
base_init <- list(
  beta_mean = rep(0, length(tau) * ncol(Z)),
  alpha_mean = as.numeric(stats::quantile(y, tau, names = FALSE)),
  sigma_mean = rep(stats::sd(y), length(tau)),
  gamma_mean = rep(0, length(tau))
)
for (likelihood in c("AL", "exAL")) {
  for (fit_structure in c("joint", "independent")) {
    init <- base_init
    if (likelihood == "AL") init$gamma_mean <- NULL
    if (fit_structure == "independent") {
      init$fits <- lapply(seq_along(tau), function(k) {
        index <- ((k - 1L) * ncol(Z) + 1L):(k * ncol(Z))
        out <- list(
          beta_mean = init$beta_mean[index], alpha_mean = init$alpha_mean[[k]],
          sigma_mean = init$sigma_mean[[k]]
        )
        if (likelihood == "exAL") out$gamma_mean <- init$gamma_mean[[k]]
        out
      })
    }
    worker_id <- match(likelihood, c("AL", "exAL")) * 10L +
      match(fit_structure, c("joint", "independent"))
    job <- data.frame(
      worker_id = worker_id, mcmc_case_id = paste(likelihood, fit_structure),
      scenario_id = "synthetic", fit_structure = fit_structure,
      likelihood_family = likelihood,
      inference_method_id = if (likelihood == "exAL") {
        "M0_v_collapsed_support_logit"
      } else "AL_latent_GIG_Gibbs",
      chain_id = 1L, chain_seed = 180000L + worker_id,
      n_iter = 20L, burn = 10L, thin = 2L,
      tau_seed_stride = 1009L, sigma_upper_multiplier = 50,
      stringsAsFactors = FALSE
    )
    fit <- app_joint_qdesn_phase180_fit_chain(job, control, fixture, init)
    qhat <- app_joint_qdesn_predict_fit(fit, Z, tau)
    expect_true(
      identical(dim(qhat), c(n, length(tau))) && all(is.finite(qhat)) &&
        nrow(fit$beta_draws) == 5L &&
        ncol(fit$sigma_draws) == length(tau) &&
        all(is.finite(fit$sigma_draws)) && all(fit$sigma_draws > 0),
      sprintf("Phase180 %s/%s sampler interface failed.", likelihood, fit_structure)
    )
    if (likelihood == "exAL") {
      expect_true(!is.null(fit$gamma_draws) && all(is.finite(fit$gamma_draws)),
                  "Phase180 exact-M0 sampler did not retain finite gamma draws.")
    }
  }
}

score_cell_original <- app_joint_qdesn_phase180_score_cell
assign(
  "app_joint_qdesn_phase180_score_cell",
  function(jobs, freeze, contract, work_dir) jobs$cell_path[[1L]],
  envir = .GlobalEnv
)
named_paths <- app_joint_qdesn_phase180_run_score_cells(
  list(cell_a = data.frame(cell_path = "a"), cell_b = data.frame(cell_path = "b")),
  freeze = NULL, contract = NULL, work_dir = tempdir(), cores = 1L
)
assign("app_joint_qdesn_phase180_score_cell", score_cell_original,
       envir = .GlobalEnv)
expect_true(identical(names(named_paths), c("cell_a", "cell_b")),
            "Phase180 score-cell collection lost its case identifiers.")

article_stub <- data.frame(
  scenario_id = rep("scenario", 4), scenario_label = rep("Scenario", 4),
  source_model_id = c(
    "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
    "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
  ),
  posterior_score_mean = c(0.1, 0.2, 0.3, 0.4),
  posterior_score_q025 = c(0.09, 0.19, 0.29, 0.39),
  posterior_score_q975 = c(0.11, 0.21, 0.31, 0.41),
  numerical_winner = c(TRUE, FALSE, FALSE, FALSE), stringsAsFactors = FALSE
)
tex <- app_joint_qdesn_phase180_article_table_lines(article_stub)
expect_true(any(grepl("DGP-integrated finite-grid quantile score", tex, fixed = TRUE)),
            "Article table omits the frozen score label.")
expect_true(!any(grepl("Grid CRPS", tex, fixed = TRUE)),
            "Article table exposes the deprecated Grid CRPS label.")

cache_root <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
required <- app_joint_qdesn_phase180_dirs(cache_root)
if (all(dir.exists(unlist(required[c(
  "phase171", "phase172", "phase174", "phase179", "al_joint",
  "al_independent", "fixture_source"
)])))) {
  source <- app_joint_qdesn_phase180_build_cell_registry(cache_root, contract)
  expect_true(nrow(source$registry) == 32L &&
                sum(source$registry$source_action ==
                      "reuse_phase172_verified_draws") == 11L,
              "Real Phase180 source resolution differs from 32/11.")
  expect_true(nrow(source$phase172_reuse_checks) == 88L &&
                all(source$phase172_reuse_checks$verified),
              "Retained Phase172 worker manifests did not verify.")
}

cat("Phase180 balanced DGP-score packet tests passed.\n")
