local({
  source("scripts/diagnostics/glofas_innovation_coordinates.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_vi.R", local = TRUE)
  source("scripts/diagnostics/glofas_guided_collapsed_particle.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_al_target.R", local = TRUE)
  source("scripts/diagnostics/glofas_native_parameter_optimizer.R", local = TRUE)
  source("scripts/diagnostics/glofas_particle_marginal_quantiles.R", local = TRUE)
  source("scripts/diagnostics/glofas_native_stage_e.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  reject <- function(x) ok(inherits(try(force(x), silent = TRUE), "try-error"))
  budget <- jsonlite::read_json(
    "scripts/diagnostics/glofas_native_stage_e_acceptance_budget.json",
    simplifyVector = FALSE)
  ok(isTRUE(gnse_validate_budget(budget)))
  bad <- budget; bad$native_fit_authorized <- TRUE
  reject(gnse_validate_budget(bad))
  bad <- budget; bad$particle_grid$maximum_conditional_evaluations <- 145L
  reject(gnse_validate_budget(bad))
  rhs <- function(tau0) list(tau0 = tau0, intercept_prec = 1e-9,
    slab = list(learned = TRUE, zeta2_fixed = NULL, a_zeta = 2,
      b_zeta = 4, slab_s2_initial = 4,
      slab_s2_role = "variational_state_initializer_not_prior_hyperparameter"),
    rhs_hierarchy = list(global_conditional_shape =
      "(r+1)/2 with intercept excluded", local_conditional_shape = 1))
  prior_export <- list(schema_version = "glofas_native_prior_export_v1",
    task_id = budget$task_id, probability = .5,
    posterior_target_sha256 = budget$posterior_target_sha256,
    declared_prior_sha256 = budget$declared_prior_sha256,
    effective_prior_sha256 = budget$effective_prior_sha256,
    effective_prior = list(beta = rhs(5.2043087e-5), alpha = rhs(.0001159),
      source_scale = list(Y = c(2, 1), G = c(2, 1)),
      coordinate_measure = "coefficients_and_log_positive_parameters",
      jacobian_count = 1L, prior_addition = NULL,
      prior_addition_allowed = FALSE))
  design <- list(H_fixed = matrix(0, 4L, 2502L), beta_index = 1:1501,
    alpha_index = 1502:2502, weight_fixed = rep(1, 4L))
  spec <- gnse_spec(design, prior_export, budget)
  low_prior <- prior_export
  low_prior$task_id <- "gft-al-p005"
  low_prior$probability <- .05
  low_spec <- gnse_spec_task(design, low_prior, budget, "gft-al-p005", .05)
  stopifnot(low_spec$probability == .05)
  bad_probability <- try(gnse_spec_task(design, low_prior, budget,
    "gft-al-p005", .95), silent = TRUE)
  stopifnot(inherits(bad_probability, "try-error"))
  ok(spec$p == 2502L && spec$dimension == 7510L)
  roles <- gnse_role_indices(spec)
  ok(identical(names(roles), unlist(budget$historical_derivatives$roles)) &&
    length(unique(unlist(roles))) == spec$dimension)
  for (i in seq_along(roles)) {
    direction <- gnse_direction(roles[[i]], spec$dimension, i / 10)
    ok(abs(sqrt(sum(direction^2)) - 1) < 1e-12 &&
      all(direction[-roles[[i]]] == 0))
  }
  make_state <- function(size) list(penalized = 2:size, update_zeta = TRUE,
    e_inv_tau2 = .7, e_inv_xi = .9,
    e_inv_lambda2 = rep(.8, size), e_inv_nu = rep(1.1, size),
    e_inv_zeta2 = .6)
  theta_cov <- matrix(0, 2502L, 2502L); diag(theta_cov) <- .01
  core <- list(method = "vb", likelihood_family = "al", prior = "rhs_ns",
    variational_state = list(theta_mean = rep(0, 2502L), theta_cov = theta_cov,
      sigma = list(shape = c(Y = 4, G = 5), rate = c(Y = 3, G = 4)),
      prior = list(prior = "block_rhs_ns", blocks = list(
        beta = list(global_index = 1:1501, state = make_state(1501L)),
        alpha = list(global_index = 1502:2502, state = make_state(1001L))),
        prior_addition = NULL)))
  init <- gnse_initializer(core, spec, design, budget)
  ok(length(init$mean) == 7510L && length(init$log_sd) == 7510L &&
    all(is.finite(init$mean)) && all(is.finite(init$log_sd)) &&
    !init$identity$initializer_is_prior_defining)
  ok(identical(names(init$mean), spec$coordinate_names) &&
    grepl("^[a-f0-9]{64}$", init$identity$mean_sha256))
  rm(theta_cov, core, init); gc(FALSE)
  contexts <- unlist(budget$particle_grid$contexts)
  counts <- as.integer(unlist(budget$particle_grid$particle_counts))
  reps <- seq_len(16L)
  rows <- do.call(rbind, lapply(contexts, function(context)
    do.call(rbind, lapply(counts, function(particles)
      data.frame(context = context, particles = particles, replicate = reps,
        complete = TRUE, log_evidence = rep(-10, length(reps)),
        elapsed_seconds = rep(.1, length(reps)))))))
  quantiles <- do.call(rbind, lapply(contexts, function(context)
    do.call(rbind, lapply(counts, function(particles)
      expand.grid(context = context, particles = particles, replicate = reps,
        horizon = 1:28, probability = c(.05, .5, .95),
        stringsAsFactors = FALSE)))))
  quantiles$quantile <- 1
  precision <- gnse_grid_precision(list(rows = rows, quantiles = quantiles), budget)
  ok(precision$all_complete && precision$all_inner_mcse_pass &&
    precision$all_drift_pass && precision$all_reporting_mcse_pass &&
    precision$all_reporting_stability_pass &&
    precision$particle_count_selected && precision$selected_N_fit == 64L)
  shifted <- quantiles
  shifted$quantile[shifted$particles == 256L & shifted$horizon == 28L &
    shifted$probability == .95] <- 1.02
  precision_bad <- gnse_grid_precision(list(rows = rows, quantiles = shifted), budget)
  ok(!precision_bad$all_reporting_stability_pass &&
    !all(precision_bad$adjacent_pair_decisions$admissible))
  cat(sprintf("GLOFAS_NATIVE_STAGE_E_GENERATED_PASS checks=%d authentic_reads=0 model_runs=0\n", n))
})
