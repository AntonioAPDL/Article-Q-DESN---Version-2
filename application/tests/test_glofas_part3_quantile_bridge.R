repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))
source(app_path("application/R/glofas_part3_partitioned_rhs.R"))
source(app_path("application/R/glofas_part3_quantile_bridge.R"))

set.seed(31)
n <- 30L
R <- cbind(readout_intercept = 1, reference__reservoir_0001 = sin(seq_len(n) / 5), reference__reservoir_0002 = rnorm(n))
D <- cbind(readout_intercept = 1, discrepancy__reservoir_0001 = cos(seq_len(n) / 4))
y <- as.numeric(0.4 + R[, 2] - 0.2 * R[, 3] + rnorm(n, sd = 0.08))
d <- as.numeric(-0.1 + 0.5 * D[, 2] + rnorm(n, sd = 0.05))
g <- y + d
H <- rbind(cbind(R, matrix(0, n, ncol(D))), cbind(R, D))
design <- list(
  H = H, z = c(y, g), source = c(rep("Y", n), rep("G", n)), n_dates = n,
  dates = as.Date("2020-01-01") + seq_len(n) - 1L,
  reference = list(X = R), discrepancy = list(X = D),
  y_reference = y, g_retrospective = g, d_g = d,
  beta_index = seq_len(ncol(R)), alpha_index = ncol(R) + seq_len(ncol(D)),
  p_beta = ncol(R), p_alpha = ncol(D), design_hash = list(reference_full = "r", discrepancy_full = "d", part3_stacked_full = "h")
)
split <- list(train_idx = 1:24, valid_idx = 25:30)
normal_init <- list(
  beta_mean = c(0.4, 1, -0.2, -0.1, 0.5),
  beta_var_diag = rep(0.01, 5), sigma2_mean = 0.01,
  sigma_a = 4, sigma_b = 0.03
)
controls <- app_glofas_part3_quantile_default_controls(
  max_iter = 3L, min_iter = 2L, tol = 1.0e-12,
  tau0_reference = 1, tau0_discrepancy = 1.0e-3,
  rhs_vb_inner = 1L, progress_every = 0L,
  quadrature_nodes = c(4L, 6L), diagnostic_stride = 1L
)
fit_al <- app_glofas_part3_quantile_fit(
  design, split, tau = 0.5, likelihood = "AL", fit_structure = "independent",
  controls = controls, init = normal_init, fit_id = "test_al"
)
stopifnot(identical(dim(fit_al$beta_reference_mean), c(3L, 1L)))
stopifnot(identical(dim(fit_al$beta_discrepancy_mean), c(2L, 1L)))
stopifnot(fit_al$iterations >= 2L)
stopifnot(fit_al$rhs_partition_certificate$overlap_count == 0L)
stopifnot(all(is.finite(fit_al$qhat_reference_train)))

controls_exal <- controls
controls_exal$max_iter <- 1L
controls_exal$min_iter <- 1L
fit_exal <- app_glofas_part3_quantile_fit(
  design, split, tau = 0.5, likelihood = "exAL", fit_structure = "independent",
  controls = controls_exal, init = fit_al, fit_id = "test_exal"
)
stopifnot(identical(fit_exal$inference_method_id, "VB1_structured_v"))
stopifnot(length(fit_exal$gamma_mean) == 1L)
stopifnot(all(is.finite(fit_exal$gamma_mean)))

joint_init <- list(fits = rep(list(fit_al), 3L))
fit_joint <- app_glofas_part3_quantile_fit(
  design, split, tau = c(0.2, 0.5, 0.8), likelihood = "AL", fit_structure = "joint",
  controls = controls_exal, init = joint_init, fit_id = "test_joint"
)
stopifnot(identical(dim(fit_joint$beta_reference_mean), c(3L, 3L)))
stopifnot(identical(dim(fit_joint$beta_discrepancy_mean), c(2L, 3L)))
stopifnot(length(fit_joint$rhs_state_reference) == 3L)
scores <- app_glofas_part3_score_quantile_fit(fit_joint, design, split)
stopifnot(all(c("usgs_valid", "glofas_valid", "discrepancy_diagnostic_valid") %in% scores$summary$metric_block))
cat("test_glofas_part3_quantile_bridge: OK\n")
