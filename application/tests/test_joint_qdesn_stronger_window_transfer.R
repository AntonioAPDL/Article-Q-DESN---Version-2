#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."))
source(file.path(repo_root, "application/scripts/_joint_qdesn_stronger_window_bootstrap.R"))

stopifnot(identical(app_joint_swtx_parse_ids("1;7;11"), c(1L, 7L, 11L)))

contract <- app_joint_sw_read_contract()
controls <- app_joint_swq_controls(contract)
design <- list(Z = matrix(0, nrow = 3L, ncol = 2L), tau = c(0.25, 0.75))
normal <- list(rhs_tau0 = 0.1, initializer = list(zeta2 = 1))
fits <- list(
  list(beta_mean = c(1, 2), beta_cov = diag(c(0.1, 0.2)),
    alpha_mean = -1, sigma_mean = 0.5, gamma_mean = -0.2),
  list(beta_mean = c(3, 4), beta_cov = diag(c(0.3, 0.4)),
    alpha_mean = 1, sigma_mean = 0.8, gamma_mean = 0.2)
)
stacked <- app_joint_swtx_stack(fits, normal, design, controls)
stopifnot(
  identical(stacked$beta_mean, c(1, 2, 3, 4)),
  identical(stacked$alpha_mean, c(-1, 1)),
  identical(stacked$sigma_mean, c(0.5, 0.8)),
  identical(stacked$gamma_mean, c(-0.2, 0.2)),
  identical(dim(stacked$beta_cov), c(4L, 4L)),
  all(is.finite(stacked$beta_cov))
)

independent_prediction <- app_joint_swtx_predict_grid(fits, c(2, 1), design$tau)
stopifnot(identical(independent_prediction, c(3, 11)))

location_scale_design <- list(
  tau = c(0.05, 0.20, 0.50, 0.80, 0.95),
  dgp_row = data.frame(distribution_family = "asymmetric_laplace", al_tau = 0.20),
  true_q = NULL
)
standardized_q <- app_joint_qvp_registry_standardized_quantile(
  location_scale_design$tau, location_scale_design$dgp_row
)
expected_mu <- c(-2, 0.5, 4)
expected_sigma <- c(0.25, 1.5, 3)
location_scale_design$true_q <- outer(expected_mu, rep(1, length(standardized_q))) +
  outer(expected_sigma, standardized_q)
recovered <- app_joint_swtx_location_scale(location_scale_design)
stopifnot(
  max(abs(recovered$mu - expected_mu)) < 1.0e-12,
  max(abs(recovered$sigma - expected_sigma)) < 1.0e-12,
  recovered$max_reconstruction_error < 1.0e-12
)

prepare_body <- paste(deparse(app_joint_swtx_prepare), collapse = "\n")
worker_body <- paste(deparse(app_joint_swtx_run_worker), collapse = "\n")
finalize_body <- paste(deparse(app_joint_swtx_finalize), collapse = "\n")
stopifnot(
  grepl("joint_backend_eligible", prepare_body, fixed = TRUE),
  grepl("seven_al_manifest.csv", prepare_body, fixed = TRUE),
  grepl("protected_rows_loaded", worker_body, fixed = TRUE),
  grepl("contract_crossing_pairs", finalize_body, fixed = TRUE),
  grepl("downstream_launched = FALSE", finalize_body, fixed = TRUE)
)

launcher <- paste(readLines(file.path(repo_root,
  "application/scripts/launch_joint_qdesn_stronger_window_transfer.sh"), warn = FALSE),
  collapse = "\n")
stopifnot(
  grepl("JOINT_SWTX_CONFIRM_STAGE", launcher, fixed = TRUE),
  grepl("for transfer_stage in 1 2 3", launcher, fixed = TRUE),
  grepl("cpu_fifo", launcher, fixed = TRUE)
)

cat("Stronger-window transfer tests passed.\n")
