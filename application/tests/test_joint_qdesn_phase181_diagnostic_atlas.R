#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_phase180_balanced_dgp_score_packet.R"))
source(app_path("application/R/joint_qdesn_phase181_score_stability_extension.R"))
source(app_path("application/R/joint_qdesn_phase181_diagnostic_atlas.R"))

config <- app_joint_qdesn_atlas_read_config(app_path(
  "application/config/joint_qdesn_phase181_diagnostic_atlas_v1.csv"
))
stopifnot(
  nrow(app_joint_qdesn_atlas_model_dictionary()) == 4L,
  nrow(app_joint_qdesn_atlas_scenario_dictionary()) == 8L,
  nrow(app_joint_qdesn_atlas_page_plan()) == 40L,
  identical(app_joint_qdesn_atlas_page_plan()$page_number, 1:40),
  length(config$tau_grid) == 7L,
  abs(sum(config$trapezoidal_weights) - 0.9) < 1e-12,
  identical(config$path_display_tau, c(0.05, 0.50, 0.95))
)

q <- app_joint_qdesn_atlas_row_quantiles(matrix(1:40, nrow = 4))
stopifnot(nrow(q) == 4L, ncol(q) == 3L, all(q[, 1] <= q[, 2]),
          all(q[, 2] <= q[, 3]))

source_root <- Sys.getenv(
  "JOINT_QDESN_PHASE181_SOURCE_ROOT",
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2"
)
if (dir.exists(file.path(source_root, config$packet_relative_path))) {
  audit <- app_joint_qdesn_atlas_validate_sources(config, source_root)
  stopifnot(
    nrow(audit$registry) == 256L,
    length(unique(audit$registry$case_id)) == 32L,
    all(table(audit$registry$case_id) == 8L),
    nrow(audit$score_summary) == 32L,
    nrow(audit$contrasts) == 16L,
    all(audit$gates$status == "pass")
  )
  jobs <- audit$registry[
    audit$registry$scenario_id == "asymmetric_laplace_tail" &
      audit$registry$source_model_id == "joint_qdesn_rhs_vb", , drop = FALSE
  ]
  loaded <- app_joint_qdesn_phase180_load_fixture(
    "asymmetric_laplace_tail", audit$paths$fixtures
  )
  fits <- app_joint_qdesn_atlas_load_fits(jobs, loaded$fixture)
  band <- app_joint_qdesn_atlas_path_bands(
    fits, loaded$fixture$Z[1:10, , drop = FALSE], loaded$fixture$tau,
    "joint", config$primary_pairing_seed, 5L, config$path_display_tau
  )
  stopifnot(
    nrow(band) == 30L,
    all(is.finite(as.matrix(band[, c(
      "posterior_mean", "posterior_median", "posterior_q025", "posterior_q975"
    )]))),
    all(band$posterior_q025 <= band$posterior_median),
    all(band$posterior_median <= band$posterior_q975)
  )
}

cat("joint_qdesn_phase181_diagnostic_atlas: PASS\n")
