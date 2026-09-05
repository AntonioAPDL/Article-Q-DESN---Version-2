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
cat("test_glofas_part3_partitioned_rhs: OK\n")
