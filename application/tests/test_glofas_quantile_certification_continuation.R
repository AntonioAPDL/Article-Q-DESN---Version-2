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

set.seed(20260922)
n <- 20L
p <- 3L
tau <- 0.50
Z <- matrix(stats::rnorm(n * p), n, p)
y <- as.numeric(0.3 + Z %*% c(0.4, -0.2, 0.1) + stats::rnorm(n, sd = 0.2))

controls <- app_glofas_part1_quantile_default_controls(
  max_iter = 3L, min_iter = 3L, tol = 0,
  tau0 = 0.1, zeta2 = 2, slab_fixed = FALSE,
  joint_backend = "blockmf", freeze_beta_warmup_iters = 0L,
  min_beta_updates = 0L, fixed_iterations = TRUE,
  full_state_convergence = TRUE, convergence_tolerance = 1,
  terminal_consecutive_passes = 1L
)
fresh <- app_glofas_part1_quantile_fit_readout(y, Z, tau, "independent_al", controls)
stopifnot(identical(as.integer(fresh$trace$global_iter), 1:3))
stopifnot(isTRUE(fresh$checkpoint_state$complete_local_state))

restart_one <- app_glofas_part12_build_restart_state(fresh, "independent_al", tau, p, n)
stopifnot(identical(restart_one$restart_kind, "exact_local_state_available"))
controls_one <- fresh$part1_quantile_controls
controls_one$max_iter <- 2L
controls_one$min_iter <- 2L
controls_one$fixed_iterations <- TRUE
controls_one$full_state_convergence <- TRUE
controls_one$convergence_tolerance <- 1
controls_one$terminal_consecutive_passes <- 1L
controls_one$restart_state <- restart_one
prior_one <- app_glofas_restart_assert_prior_identity(fresh$part1_quantile_controls, controls_one, "part12")
first <- app_glofas_part1_quantile_fit_readout(y, Z, tau, "independent_al", controls_one)
stopifnot(identical(as.integer(first$trace$global_iter), 4:5))
first_cumulative <- app_glofas_restart_combine_traces(fresh$trace, first$trace)
stopifnot(identical(as.integer(first_cumulative$global_iter), 1:5))
stopifnot(isTRUE(first$checkpoint_state$complete_local_state))

restart_two <- app_glofas_part12_build_restart_state(first, "independent_al", tau, p, n)
stopifnot(identical(restart_two$restart_kind, "exact_local_state_available"))
controls_two <- first$part1_quantile_controls
controls_two$max_iter <- 2L
controls_two$min_iter <- 2L
controls_two$fixed_iterations <- TRUE
controls_two$full_state_convergence <- TRUE
controls_two$convergence_tolerance <- 1
controls_two$terminal_consecutive_passes <- 1L
controls_two$restart_state <- restart_two
prior_two <- app_glofas_restart_assert_prior_identity(first$part1_quantile_controls, controls_two, "part12")
second <- app_glofas_part1_quantile_fit_readout(y, Z, tau, "independent_al", controls_two)
stopifnot(identical(as.integer(second$trace$global_iter), 6:7))
second_cumulative <- app_glofas_restart_combine_traces(first_cumulative, second$trace)
stopifnot(nrow(second_cumulative) == 7L)
stopifnot(identical(as.integer(second_cumulative$global_iter), 1:7))
stopifnot(isTRUE(second$checkpoint_state$complete_local_state))

certificate <- app_glofas_restart_certificate_row(
  second, paste(rep("a", 64), collapse = ""), restart_two$source_state_sha256,
  prior_two, expected_segment_iterations = 2L, expected_source_iterations = 5L
)
stopifnot(isTRUE(certificate$segment_length_ok))
stopifnot(isTRUE(certificate$global_iteration_sequence_ok))
stopifnot(isTRUE(certificate$prior_identity_ok))
stopifnot(isTRUE(certificate$complete_checkpoint_state))
stopifnot(identical(prior_one$source$sha256, prior_one$restart$sha256))
stopifnot(identical(prior_two$source$sha256, prior_two$restart$sha256))

message("test_glofas_quantile_certification_continuation: OK")
