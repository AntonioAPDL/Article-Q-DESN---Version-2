#!/usr/bin/env Rscript

if (!exists("app_joint_recursive_mean_design", mode = "function")) {
  file_arg <- sub("^--file=", "", commandArgs(FALSE)[grep(
    "^--file=", commandArgs(FALSE))])
  source(file.path(dirname(file_arg), "..", "scripts",
    "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
}

tau <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
q <- c(-2, -1.5, -0.5, 0, 0.7, 1.4, 2.2)
stopifnot(
  all.equal(app_joint_recursive_inverse_cdf(q, tau, 0), q[[1L]]),
  all.equal(app_joint_recursive_inverse_cdf(q, tau, 1), q[[length(q)]]),
  all.equal(app_joint_recursive_inverse_cdf(q, tau, tau[[4L]]), q[[4L]]),
  all.equal(app_joint_recursive_inverse_cdf(q, tau, 0.625), 0.35),
  all(diff(app_joint_recursive_contract_vector(rev(q), tau)) >= -1e-12)
)

# Tail completion and isotonic repair are deterministic under ties/crossings.
stopifnot(
  identical(app_joint_recursive_inverse_cdf(rep(3, 7L), tau, 0.73), 3),
  identical(
    app_joint_recursive_inverse_cdf(q, tau, 0, "truncated_grid"), q[[1L]])
)

source_candidates <- c(
  Sys.getenv("JOINT_RECURSIVE_SOURCE_ROOT", unset = ""),
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_corrected_article_comparison_muscat_11core_20260909/application/cache/joint_qdesn_corrected_article_comparison_muscat_11core_20260909",
  app_joint_recursive_default_source()
)
source_root <- source_candidates[dir.exists(source_candidates)][1L]
if (length(source_root) && !is.na(source_root)) {
  plans <- app_joint_recursive_build_plans(
    source_root, app_joint_recursive_read_contract())
  audits <- lapply(unique(plans$cells$scenario_id), function(id) {
    row <- plans$cells[plans$cells$scenario_id == id, , drop = FALSE][1L, ]
    app_joint_recursive_teacher_forced_audit(
      readRDS(file.path(source_root, row$design_relative_path)),
      readRDS(file.path(source_root, row$fixture_relative_path)),
      app_joint_recursive_selected_row(plans$selected, id)
    )
  })
  audits <- app_joint_qdesn_bind_rows(audits)
  stopifnot(nrow(audits) == 8L, all(audits$status == "pass"))

  # Exercise direct, reservoir-only, and hybrid recursive paths against real
  # corrected-v4 designs without performing any fit.
  cases <- list(
    c("regime_shift", "joint", "vb"),
    c("asymmetric_laplace_tail", "joint", "mcmc"),
    c("nonlinear_reservoir_friendly", "independent", "vb")
  )
  for (case in cases) {
    row <- plans$cells[
      plans$cells$scenario_id == case[[1L]] &
        plans$cells$fit_structure == case[[2L]] &
        plans$cells$inference_method == case[[3L]], , drop = FALSE][1L, ]
    design <- readRDS(file.path(source_root, row$design_relative_path))
    fixture <- readRDS(file.path(source_root, row$fixture_relative_path))
    selected <- app_joint_recursive_selected_row(plans$selected, row$scenario_id)
    posterior <- if (row$inference_method == "mcmc") {
      app_joint_recursive_mcmc_draws(source_root, row, 1L, 991L)
    } else app_joint_recursive_vb_draws(source_root, row, 5L, 991L)
    set.seed(332L)
    uniforms <- matrix(
      stats::runif(nrow(posterior$beta) * nrow(design$forecast_map)),
      nrow = nrow(posterior$beta)
    )
    recursive <- app_joint_recursive_mean_design(
      design, fixture, selected, posterior$beta, posterior$alpha, uniforms
    )
    stopifnot(
      identical(dim(recursive$mean_design), c(990L, as.integer(row$p))),
      all(is.finite(recursive$mean_design)),
      all(recursive$minimum <= recursive$maximum)
    )
  }
}

cat("test_joint_qdesn_recursive_mean_design: PASS\n")
