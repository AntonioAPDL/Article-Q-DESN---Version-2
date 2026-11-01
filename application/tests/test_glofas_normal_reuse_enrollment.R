# Synthetic retained-object fixtures only: no real evidence, feature map or fit.
if (!exists("app_make_qdesn_discrepancy_vb_args", mode = "function")) {
  source("application/scripts/_glofas_unit_member_bootstrap.R")
}
if (!exists("app_glofas_family_transition_contract", mode = "function")) {
  source("application/R/glofas_family_transition.R")
}
source("scripts/glofas_normal_reuse_enrollment.R")
source("scripts/enroll_glofas_normal_baselines.R")
gnr_checks <- 0L
gnr_check <- function(ok) { stopifnot(isTRUE(ok)); gnr_checks <<- gnr_checks + 1L }
gnr_reject <- function(expr) {
  out <- tryCatch({ force(expr); NULL }, error = identity)
  gnr_check(inherits(out, "error"))
}
gnr_check(gnr_local_reporting_host("muscat"))
gnr_check(gnr_local_reporting_host("muscat.be.ucsc.edu"))
gnr_check(!gnr_local_reporting_host("jerez.be.ucsc.edu"))
gnr_check(!gnr_local_reporting_host("muscat.example.org"))
gnr_closure <- function() {
  env <- new.env(parent = globalenv())
  env$context <- list(lags = 1L, future_covariates = matrix(seq_len(28L), 28L, 1L))
  env$compiled <- new.env(parent = emptyenv())
  env$compiled$enabled <- TRUE
  env$compiled$input <- list(fixed = 3, future = 1:28)
  eval(quote(function(y_future) context$lags + y_future), env)
}
gnr_original <- list(unit_member_contract = app_glofas_unit_member_contract(),
  design_version = "synthetic_unit_member", H_fixed = matrix(1:16, 4L, 4L,
    dimnames = list(NULL, c("b0", "b1", "a0", "a1"))),
  weight_fixed = rep(1, 4L), source_fixed = factor(c("Y", "Y", "G", "G")),
  future_builder = gnr_closure(), future_context = list(lag = 1L),
  future_key = data.frame(target_date = as.Date("2022-12-26") + 0:27, horizon = 1:28),
  beta_index = 1:2, alpha_index = 3:4, intercept_index = c(1L, 3L),
  future_truth_policy = "physically_excluded_from_fit_objects_scoring_sidecar_only")
attr(gnr_original, "future_probe_init") <- list(derived_cache = "not invoked")
gnr_prepared <- unserialize(serialize(gnr_original, NULL))
gnr_prepared$historical_unit_member_contract <- gnr_prepared$unit_member_contract
gnr_prepared$unit_member_contract <- NULL
gnr_prepared$family_transition_contract <- app_glofas_family_transition_contract()
gnr_prepared$design_version <- paste0(gnr_prepared$design_version, "__same_family_transition_v1")
attr(gnr_prepared, "future_probe_init") <- NULL
gnr_map <- app_gnr_compare_designs(gnr_original, gnr_prepared, app_glofas_family_transition_contract())
gnr_check(gnr_map$status == "EXACT_PROTECTED_DESIGN_MATCH")
gnr_check(gnr_map$builder_calls == 0L && gnr_map$new_model_fits == 0L && !gnr_map$scoring_truth_read)
gnr_check(length(gnr_map$protected_fields) == length(gnr_original) - 2L)
for (mutate in list(
  function(x) { x$H_fixed[1L] <- 5; x },
  function(x) { x$weight_fixed[1L] <- 1/51; x },
  function(x) { x$design_version <- "unrelated"; x },
  function(x) { x$family_transition_contract$allow_launch <- TRUE; x },
  function(x) { x$historical_unit_member_contract$members <- 50L; x },
  function(x) { x$future_key$target_date[1L] <- as.Date("2020-01-01"); x },
  function(x) { x$future_truth <- seq_len(28L); x },
  function(x) { x$extra_metadata <- TRUE; x },
  function(x) { x$future_context$lag <- 2L; x },
  function(x) { x$future_builder <- function(y) y + 1; x }
)) gnr_reject(app_gnr_compare_designs(gnr_original, mutate(gnr_prepared), app_glofas_family_transition_contract()))
bad <- unserialize(serialize(gnr_prepared, NULL)); environment(bad$future_builder)$compiled$enabled <- FALSE
gnr_reject(app_gnr_compare_designs(gnr_original, bad, app_glofas_family_transition_contract()))
bad <- unserialize(serialize(gnr_prepared, NULL)); environment(bad$future_builder)$context$lags <- 2L
gnr_reject(app_gnr_compare_designs(gnr_original, bad, app_glofas_family_transition_contract()))

gnr_temp <- tempfile("gnr_synthetic_"); dir.create(gnr_temp)
on.exit_cleanup <- function() unlink(gnr_temp, recursive = TRUE)
gnr_pin <- function(object, name) {
  path <- file.path(gnr_temp, paste0(name, ".rds")); saveRDS(object, path)
  list(path = path, size_bytes = unname(file.info(path)$size), sha256 = unname(tools::sha256sum(path)[[1L]]))
}
gnr_old_pin <- gnr_pin(gnr_original, "original")
gnr_old <- app_gnr_read_pinned_rds(gnr_old_pin)
gnr_check(inherits(gnr_old, "gnr_verified_rds"))
wrong <- gnr_old_pin; wrong$size_bytes <- wrong$size_bytes + 1
gnr_reject(app_gnr_read_pinned_rds(wrong))
wrong <- gnr_old_pin; wrong$sha256 <- strrep("0", 64)
gnr_reject(app_gnr_read_pinned_rds(wrong))
wrong <- gnr_old_pin; wrong$path <- paste0(dirname(wrong$path), "/../", basename(wrong$path))
gnr_reject(app_gnr_read_pinned_rds(wrong))

gnr_cfg <- list(reservoir = list(seed = 20260512L), inference = list(vb_ld = list(
  max_iter = 200L, max_iter_hard_cap = 500L, min_iter_elbo = 200L, tol = 1e-4,
  rhs_tau0 = 5.2043087e-5, rhs_alpha_tau0 = .0001159, rhs_a_zeta = 2, rhs_b_zeta = 4,
  rhs_freeze_tau_warmup_iters = 50L, rhs_update_every = 1L, rhs_min_tau_updates = 1L,
  intercept_prec = 1e-9, sigma_a = 2, sigma_b = 1, freeze_beta_warmup_iters = 20L,
  min_beta_updates = 180L)), unit_member_execution = app_glofas_unit_member_default_controls())
gnr_runtime <- data.frame(backend = "bundled_rblas", backend_verified = "TRUE",
  ld_preload = "", engine_source_dirty = "FALSE", source_head = strrep("a", 40),
  omp_num_threads = "1", openblas_num_threads = "1", mkl_num_threads = "1", job_id = "synthetic_normal")
gnr_fixture <- function(model) {
  prior <- if (model == "normal_ridge") "ridge" else "rhs_ns"
  args <- app_glofas_unit_member_vb_controls(app_make_qdesn_discrepancy_vb_args(gnr_cfg,
    prior, 20260512L, "normal"), gnr_cfg)
  ps <- app_latent_prior_state_init(4L, prior, c(1L, 3L), args, 1:2, 3:4)
  ps$prior_linear <- numeric(4L)
  if (prior == "rhs_ns") for (k in c("beta", "alpha")) {
    ps$blocks[[k]]$state$tau_update_count <- 150L
    ps$blocks[[k]]$state$first_tau_update_iter <- 51L
    ps$blocks[[k]]$state$last_tau_update_iter <- 200L
    ps$blocks[[k]]$state$has_post_warmup_tau_update <- TRUE
  }
  m <- seq(-.1, 1.2, length.out = 28L); V <- diag(rep(.2, 28L))
  summary <- list(theta_mean = numeric(4L), theta_cov = diag(4L), sigma_mean = c(.2, .3),
    y_future_mean = m, y_future_cov = V)
  state <- c(summary[c("theta_mean", "theta_cov", "y_future_mean", "y_future_cov")], list(prior = ps,
    sigma = list(shape = c(17, 717), rate = c(3, 4), mean = c(.2, .3))))
  freeze <- if (prior == "ridge") 0L else 20L
  core <- list(method = "vb", likelihood_family = "normal", prior = prior, summary = summary,
    variational_state = state, vb_diagnostics = list(converged = TRUE, iterations = 200L,
      freeze_beta_warmup_iters = freeze, beta_update_count = 200L - freeze,
      initialization = list(type = if (prior == "ridge") "cold" else "validated_dependency_fit"),
      ensemble_weight_contract = "each_included_member_weight_one",
      future_truth_policy = "physically_excluded_from_fit_objects_scoring_sidecar_only",
      normal_exact_optimization = TRUE, objective_type = "normal_mean_field_expected_log_joint",
      iteration_trace = data.frame(iteration = 1:200, convergence_eligible = TRUE, parameter_change = 1e-6)))
  object <- list(status = "completed", model_id = "synthetic_model", fit_id = "synthetic_model_p05",
    coefficient_prior = prior, state_contract_hash = strrep("b", 64), fit = core,
    shared_design_reference = list(state_contract_hash = strrep("b", 64), sha256 = gnr_old_pin$sha256))
  grid <- data.frame(model_family = "qdesn_glofas_discrepancy", model_id = "synthetic_model",
    fit_id = paste0("synthetic_model_p", sprintf("%02d", round(100 * app_gnr_reporting_contract()$tau))),
    quantile_level = app_gnr_reporting_contract()$tau, likelihood_family = "normal",
    coefficient_prior = prior, reservoir_seed = 20260512L)
  target <- list(schema_version = "glofas_unit_member_part4_v1", policy = "unit_member_likelihood_v1",
    horizons = 28L, members = 51L, job_id = "synthetic_normal",
    family = if (prior == "ridge") "normal_ridge_diagnostic" else "normal_rhs_vb_diagnostic",
    shared_design_sha256 = gnr_old_pin$sha256, state_contract_hash = strrep("b", 64),
    future_path_prior_hash = NULL, future_truth_used_in_fit = FALSE,
    included_historical_Y = 2L, included_historical_G = 2L, included_future_Y = 28L,
    included_issued_G = 1428L, quantile_blocks = 1L, included_issued_G_across_blocks = 1428L)
  list(verified_fit = app_gnr_read_pinned_rds(gnr_pin(object, model)), design_identity = gnr_map,
    original_design_binding = gnr_old_pin, config = gnr_cfg, model_grid = grid,
    target_receipt = target, runtime_receipt = gnr_runtime,
    expected = list(model = model, source_commit = strrep("a", 40), state_contract_hash = strrep("b", 64)))
}
set.seed(913); gnr_rng <- .Random.seed
gnr_results <- lapply(c("normal_ridge", "normal_rhs"), function(model) {
  out <- do.call(app_gnr_enroll_fit, gnr_fixture(model))
  gnr_check(out$receipt$status == "FIT_REUSE_AND_NEW_ANALYTIC_REPORT_VERIFIED")
  gnr_check(out$receipt$fit_reused && out$receipt$new_model_fits == 0L && !out$receipt$article_publication_authorized)
  gnr_check(nrow(out$rows) == 196L && all(out$rows$fit_reused))
  gnr_check(!any(out$rows$extra_response_noise_added) && !any(out$rows$quantile_functional_credible_interval))
  gnr_check(all(out$rows$quantile == expm1(out$rows$quantile_transformed)))
  gnr_check(identical(out$rows$quantile_transformed[out$rows$tau == .5], seq(-.1, 1.2, length.out = 28L)))
  gnr_check(all(vapply(split(out$rows, out$rows$horizon), function(z) all(diff(z$quantile_transformed) > 0), logical(1L))))
  out
})
gnr_check(identical(.Random.seed, gnr_rng))
for (mutate in list(
  function(x) { x$verified_fit$object$fit$likelihood_family <- "al"; x },
  function(x) { x$verified_fit$object$fit$vb_diagnostics$converged <- FALSE; x },
  function(x) { x$verified_fit$object$fit$vb_diagnostics$iteration_trace$parameter_change[200L] <- .01; x },
  function(x) { x$verified_fit$object$fit$variational_state$prior$prior_linear[1L] <- .1; x },
  function(x) { x$verified_fit$object$fit$variational_state$prior$blocks$beta$state$tau0 <- .1; x },
  function(x) { x$verified_fit$object$fit$variational_state$prior$blocks$alpha$state$has_post_warmup_tau_update <- FALSE; x },
  function(x) { x$verified_fit$object$fit$variational_state$sigma$shape[1L] <- 16.5; x },
  function(x) { x$verified_fit$object$shared_design_reference$sha256 <- strrep("0", 64); x },
  function(x) { x$model_grid$reservoir_seed[7L] <- 1L; x },
  function(x) { x$model_grid$fit_id[7L] <- "wrong"; x },
  function(x) { x$model_grid$inference_method <- rep("vb", 7L); x$model_grid$inference_method[7L] <- "mcmc"; x },
  function(x) { x$target_receipt$future_path_prior_hash <- strrep("0", 64); x },
  function(x) { x$target_receipt$future_truth_used_in_fit <- NULL; x },
  function(x) { x$target_receipt$future_truth_used_in_fit <- NA; x },
  function(x) { x$target_receipt$members <- 50L; x },
  function(x) { x$target_receipt$job_id <- "wrong"; x },
  function(x) { x$target_receipt$included_issued_G <- 28L; x },
  function(x) { x$runtime_receipt$backend <- "openblas"; x },
  function(x) { x$runtime_receipt$engine_source_dirty <- NA_character_; x },
  function(x) { x$runtime_receipt$openblas_num_threads <- "2"; x },
  function(x) { x$verified_fit$object$fit$summary$y_future_cov[1L, 1L] <- -1; x },
  function(x) { x$verified_fit$object$fit$summary$y_future_mean[1L] <- Inf; x }
)) gnr_reject(do.call(app_gnr_enroll_fit, mutate(gnr_fixture("normal_rhs"))))
core <- gnr_fixture("normal_rhs")$verified_fit$object$fit
core$summary$y_future_cov[1L, 2L] <- .1
gnr_reject(app_gnr_response_quantiles(core, gnr_map$future_key$target_date, "normal_rhs"))
core <- gnr_fixture("normal_rhs")$verified_fit$object$fit
core$summary$y_future_mean[] <- 1000
gnr_reject(app_gnr_response_quantiles(core, gnr_map$future_key$target_date, "normal_rhs"))
on.exit_cleanup()
cat(sprintf("GLOFAS_NORMAL_REUSE_ENROLLMENT_CHECKS=%d PASS; real_fit_reads=0 new_model_fits=0\n", gnr_checks))
