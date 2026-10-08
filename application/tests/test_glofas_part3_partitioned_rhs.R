repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_part3_partitioned_rhs.R"))

controls <- app_glofas_part3_rhs_default_controls(
  tau0_reference = 1, tau0_discrepancy = 1.0e-3, slab_s2 = 4,
  a_zeta = 2, b_zeta = 4
)
app_glofas_part3_rhs_validate_controls(controls)
reference <- app_glofas_part3_rhs_initialize(3L, 5L, 1, controls)
discrepancy <- app_glofas_part3_rhs_initialize(3L, 4L, 1.0e-3, controls)
stopifnot(reference[[1L]]$slab_s2_initial == 4)
stopifnot(discrepancy[[1L]]$slab_s2_initial == 4)
stopifnot(reference[[1L]]$prior_precision[[1L]] == controls$intercept_prec)
stopifnot(discrepancy[[1L]]$prior_precision[[1L]] == controls$intercept_prec)

reference <- app_glofas_part3_rhs_update(
  reference,
  coefficient_mean = matrix(seq_len(15) / 100, 5, 3),
  coefficient_var_diag = matrix(0.01, 5, 3),
  iter = 1L
)
discrepancy <- app_glofas_part3_rhs_update(
  discrepancy,
  coefficient_mean = matrix(seq_len(12) / 100, 4, 3),
  coefficient_var_diag = matrix(0.02, 4, 3),
  iter = 1L
)
certificate <- app_glofas_part3_rhs_partition_certificate(5L, 4L, reference, discrepancy)
stopifnot(certificate$overlap_count == 0L)
stopifnot(certificate$all_precision_finite)
stopifnot(certificate$n_quantiles == 3L)

prior <- app_glofas_part3_rhs_prior_terms(reference, matrix(seq_len(15) / 100, 5, 3))
stopifnot(length(prior$diagonal) == 3L)
stopifnot(all(vapply(prior$diagonal, function(x) length(x) == 5L && all(is.finite(x)) && all(x > 0), logical(1L))))

solver_mean <- matrix(seq_len(15) / 100, 5, 3)
solver_var <- matrix(0.01, 5, 3)
solver_start <- app_glofas_part3_rhs_initialize(3L, 5L, 1, controls)
explicit <- solver_start
for (inner in 1:4) {
  explicit <- app_glofas_part3_rhs_update(
    explicit,
    solver_mean,
    solver_var,
    iter = 1L,
    update_global = if (inner == 1L) NULL else TRUE
  )
}
bounded_four <- app_glofas_part3_rhs_solve_fixed_moments(
  solver_start,
  solver_mean,
  solver_var,
  iter = 1L,
  min_iter = 4L,
  max_iter = 4L,
  tolerance = 1.0e-30,
  consecutive_passes = 5L
)
stopifnot(
  bounded_four$iterations == 4L,
  !bounded_four$converged,
  max(abs(
    app_glofas_part3_rhs_inferential_state(bounded_four$state) -
      app_glofas_part3_rhs_inferential_state(explicit)
  )) < 1.0e-14
)

bounded_converged <- app_glofas_part3_rhs_solve_fixed_moments(
  solver_start,
  solver_mean,
  solver_var,
  iter = 1L,
  min_iter = 2L,
  max_iter = 100L,
  tolerance = 1.0e-6,
  consecutive_passes = 2L
)
stopifnot(
  bounded_converged$converged,
  bounded_converged$iterations <= 100L,
  bounded_converged$relative_change <= 1.0e-6,
  all(c(
    "rhs_inner_iteration", "inferential_relative_change",
    "auxiliary_relative_change", "precision_relative_change",
    "controlling_block", "controlling_component", "controlling_coordinate",
    "global_update_enabled", "convergence_pass", "trailing_consecutive_passes"
  ) %in% names(bounded_converged$trace)),
  nzchar(bounded_converged$controlling_block),
  nzchar(bounded_converged$controlling_component),
  grepl("\\[[0-9]+\\]$", bounded_converged$controlling_coordinate)
)
cat("test_glofas_part3_partitioned_rhs: OK\n")
