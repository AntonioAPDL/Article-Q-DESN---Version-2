repo_root <- normalizePath(Sys.getenv("APP_REPO_ROOT", unset = getwd()), mustWork = TRUE)
if (!exists("app_path", mode = "function")) {
  source(file.path(repo_root, "application/R/00_packages.R"))
  app_set_repo_root(repo_root)
}
for (file in c(
  "joint_qvp_qdesn.R", "joint_exqdesn_exact_structured_inference.R",
  "glofas_quantile_integrity.R", "glofas_part1_quantile_oracle_forecast.R",
  "glofas_quantile_certification_restart.R"
)) source(app_path("application/R", file))

set.seed(20260921)
n <- 24L
p <- 4L
tau <- c(0.20, 0.80)
Z <- matrix(stats::rnorm(n * p), n, p)
y <- as.numeric(0.4 + Z %*% c(0.5, -0.2, 0.1, 0.3) + stats::rnorm(n, sd = 0.25))

fresh_controls <- app_glofas_part1_quantile_default_controls(
  max_iter = 3L, min_iter = 3L, tol = 0,
  tau0 = 0.1, zeta2 = 2, slab_fixed = FALSE,
  joint_backend = "blockmf", freeze_beta_warmup_iters = 0L,
  min_beta_updates = 0L, fixed_iterations = TRUE,
  full_state_convergence = TRUE, convergence_tolerance = 1,
  terminal_consecutive_passes = 1L
)
fresh <- app_glofas_part1_quantile_fit_readout(y, Z, tau, "joint_al", fresh_controls)
stopifnot(nrow(fresh$trace) == 3L)
stopifnot(identical(as.integer(fresh$iterations_completed), 3L))
stopifnot(isTRUE(fresh$checkpoint_state$complete_local_state))
stopifnot(!is.null(fresh$v_mean), !is.null(fresh$v_inv_mean))

restart <- app_glofas_part12_build_restart_state(
  fresh, "joint_al", tau, p, n,
  source_path = "synthetic_source.rds", source_sha256 = paste(rep("a", 64), collapse = "")
)
stopifnot(identical(restart$restart_kind, "exact_local_state_available"))
restart_controls <- fresh$part1_quantile_controls
restart_controls$max_iter <- 2L
restart_controls$min_iter <- 2L
restart_controls$fixed_iterations <- TRUE
restart_controls$full_state_convergence <- TRUE
restart_controls$convergence_tolerance <- 1
restart_controls$terminal_consecutive_passes <- 1L
restart_controls$restart_state <- restart
prior_identity <- app_glofas_restart_assert_prior_identity(
  fresh$part1_quantile_controls, restart_controls, "part12"
)
resumed <- app_glofas_part1_quantile_fit_readout(y, Z, tau, "joint_al", restart_controls)
stopifnot(identical(as.integer(resumed$trace$global_iter), 4:5))
stopifnot(identical(as.integer(resumed$iterations_completed), 5L))
stopifnot(is.null(resumed$part1_quantile_controls$restart_state))
combined <- app_glofas_restart_combine_traces(fresh$trace, resumed$trace)
stopifnot(nrow(combined) == 5L)
stopifnot(identical(as.integer(combined$global_iter), 1:5))
certificate <- app_glofas_restart_certificate_row(
  resumed, paste(rep("a", 64), collapse = ""), restart$source_state_sha256,
  prior_identity, expected_segment_iterations = 2L, expected_source_iterations = 3L
)
stopifnot(isTRUE(certificate$segment_length_ok))
stopifnot(isTRUE(certificate$global_iteration_sequence_ok))
stopifnot(isTRUE(certificate$prior_identity_ok))
stopifnot(isTRUE(certificate$complete_checkpoint_state))

reconstructed_source <- fresh
reconstructed_source$v_mean <- NULL
reconstructed_source$v_inv_mean <- NULL
reconstructed <- app_glofas_part12_build_restart_state(
  reconstructed_source, "joint_al", tau, p, n
)
stopifnot(identical(reconstructed$restart_kind, "same_target_reconstructed_local_state"))

init_changed <- fresh$part1_quantile_controls
init_changed$init <- list(beta_mean = rep(99, p * length(tau)))
stopifnot(identical(
  app_glofas_restart_prior_signature(fresh$part1_quantile_controls, "part12")$sha256,
  app_glofas_restart_prior_signature(init_changed, "part12")$sha256
))
prior_changed <- fresh$part1_quantile_controls
prior_changed$tau0 <- 0.2
stopifnot(!identical(
  app_glofas_restart_prior_signature(fresh$part1_quantile_controls, "part12")$sha256,
  app_glofas_restart_prior_signature(prior_changed, "part12")$sha256
))

bad_tau <- try(
  app_glofas_part12_build_restart_state(fresh, "joint_al", c(0.20, 0.95), p, n),
  silent = TRUE
)
stopifnot(inherits(bad_tau, "try-error"))

message("test_glofas_quantile_certification_restart: OK")
