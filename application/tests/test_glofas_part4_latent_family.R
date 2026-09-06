if (!exists("app_set_repo_root", mode = "function")) {
  source("application/R/00_packages.R")
  app_set_repo_root(getwd())
}
for (path in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R", "build_qdesn_features.R",
  "latent_path_design.R", "discrepancy_design.R", "forecast_contract.R",
  "fit_qdesn_discrepancy.R", "latent_path_runtime_backend.R", "latent_path_checkpoint.R",
  "latent_path_vb_al.R", "latent_path_vb_normal.R", "joint_qvp_qdesn.R",
  "joint_exqdesn_exact_structured_inference.R", "latent_path_vb_exal.R",
  "glofas_normal_desn_part1_screening.R",
  "glofas_part3_partitioned_rhs.R", "latent_path_vb_joint.R", "fit_qdesn_latent_path.R",
  "glofas_part4_ensemble_likelihood_contract.R", "glofas_part4_latent_family.R"
)) source(app_path("application/R", path))

toy_future_builder <- local({
  future_key <- data.frame(target_date = as.Date("2026-01-06") + 0:1, horizon = 1:2)
  ensemble_index <- rep(1:2, each = 2L)
  function(y_future) {
    y_future <- as.numeric(y_future)
    X_beta <- cbind(beta_intercept = 1, beta_lag = c(0.4, y_future[[1L]]))
    X_alpha <- cbind(alpha_intercept = 1, alpha_lag = c(-0.2, 1.2 - y_future[[1L]]))
    H_y <- cbind(X_beta, matrix(0, 2L, 2L))
    H_g_key <- cbind(X_beta, X_alpha)
    J_y <- list(matrix(0, 4L, 2L), matrix(c(0, 1, 0, 0, 0, 0, 0, 0), 4L, 2L))
    J_g_key <- list(matrix(0, 4L, 2L), matrix(c(0, 1, 0, -1, 0, 0, 0, 0), 4L, 2L))
    list(
      H_y = H_y,
      H_g_key = H_g_key,
      g_future_index = ensemble_index,
      J_y = J_y,
      J_g_key = J_g_key,
      z_g = c(1.0, 1.2, 1.1, 1.3),
      weight_g = rep(0.5, 4L),
      row_info_y = data.frame(source = "Y", future_index = 1:2, target_date = future_key$target_date, horizon = 1:2),
      row_info_g = data.frame(source = "G", future_index = ensemble_index,
        target_date = rep(future_key$target_date, each = 2L), horizon = rep(1:2, each = 2L),
        member = rep(c("m1", "m2"), 2L)),
      discrepancy_baseline_future = c(0, 0)
    )
  }
})

X <- cbind(intercept = 1, lag = c(0.1, 0.2, 0.3, 0.4))
source <- factor(rep(c("Y", "G"), each = nrow(X)), levels = c("Y", "G"))
toy_design <- list(
  z_fixed = c(0.2, 0.4, 0.6, 0.8, 0.5, 0.7, 0.9, 1.1),
  H_fixed = app_make_augmented_discrepancy_design(rbind(X, X), source, rbind(X, X)),
  weight_fixed = rep(1, 8L),
  source_fixed = source,
  row_info_fixed = data.frame(source = source, feature_row = rep(1:4, 2L)),
  X_beta = X,
  X_alpha = X,
  future_builder = toy_future_builder,
  future_key = data.frame(target_date = as.Date("2026-01-06") + 0:1, horizon = 1:2),
  y_future_init = c(0.9, 1.0),
  beta_index = 1:2,
  alpha_index = 3:4,
  intercept_index = c(1L, 3L),
  discrepancy_baseline_fixed = rep(0, 4L),
  future_truth_policy = "physically_excluded_from_fit_objects_scoring_sidecar_only",
  feature_strategy = "recursive_latent_path",
  design_version = "part4_toy_v1",
  fit_id = "part4_toy",
  model_id = "part4_toy"
)
app_validate_glofas_latent_path_design(toy_design)
probe <- toy_design$future_builder(toy_design$y_future_init)
stopifnot(all(abs(tapply(probe$weight_g, probe$g_future_index, sum) - 1) < 1.0e-12))
stopifnot(nzchar(app_glofas_part4_state_contract_hash(toy_design)))

set.seed(20260906L)
batch_theta_cov <- crossprod(matrix(rnorm(16L), 4L, 4L)) / 10
batch_theta_mean <- rnorm(4L)
batch_y_cov <- crossprod(matrix(rnorm(4L), 2L, 2L)) / 10
batch_J <- probe$J_g_key
batch_coeff <- c(0.7, 1.3)
legacy_precision <- matrix(0, 4L, 4L)
for (h in seq_along(batch_J)) {
  legacy_precision <- app_latent_add_J_precision(
    legacy_precision, batch_coeff[[h]], batch_J[[h]], batch_y_cov
  )
}
batched_precision <- matrix(0, 4L, 4L)
batched_block <- app_latent_weighted_jacobian_precision(batch_J, batch_coeff, batch_y_cov)
batched_precision[batched_block$index, batched_block$index] <- batched_block$value
stopifnot(max(abs(legacy_precision - batched_precision)) < 1.0e-10)
legacy_trace <- vapply(batch_J, function(J) {
  app_latent_jacobian_trace_theta(J, batch_y_cov, batch_theta_mean, batch_theta_cov)
}, numeric(1L))
batched_trace <- app_latent_jacobian_trace_theta_batch(
  batch_J, batch_y_cov, batch_theta_mean, batch_theta_cov
)
stopifnot(max(abs(legacy_trace - batched_trace)) < 1.0e-10)
draw_cov_probe <- crossprod(matrix(rnorm(16L), 4L, 4L)) + diag(0.1, 4L)
draws_checked <- app_latent_mvn_draws_exact(
  rep(0, 4L), draw_cov_probe, 8L, seed = 101L, assume_symmetric = FALSE
)
draws_certified <- app_latent_mvn_draws_exact(
  rep(0, 4L), draw_cov_probe, 8L, seed = 101L, assume_symmetric = TRUE
)
stopifnot(max(abs(as.numeric(draws_checked) - as.numeric(draws_certified))) < 1.0e-12)
stopifnot(identical(attr(draws_certified, "backend", exact = TRUE), "chol"))

gig_half <- app_latent_gig_half_moments(c(0.5, 2), c(3, 4))
gig_general <- app_latent_gig_moments(0.5, c(0.5, 2), c(3, 4))
stopifnot(max(abs(gig_half$mean - gig_general$mean)) < 1.0e-10)
stopifnot(max(abs(gig_half$inv_mean - gig_general$inv_mean)) < 1.0e-10)

structured_args <- list(
  tau = 0.5,
  gamma = c(-0.1, 0, 0.1),
  augmentation = "v",
  r_mean = c(0.2, -0.1),
  r2_mean = c(0.3, 0.4),
  latent_mean = c(1.1, 0.9),
  latent_inv_mean = c(1.2, 1.3),
  s_mean = c(0.5, 0.6),
  s2_mean = c(0.8, 0.9)
)
structured_once <- do.call(app_joint_exqdesn_structured_terms_grid, structured_args)
structured_duplicated <- do.call(
  app_joint_exqdesn_structured_terms_grid,
  modifyList(structured_args, list(
    r_mean = rep(structured_args$r_mean, each = 2L),
    r2_mean = rep(structured_args$r2_mean, each = 2L),
    latent_mean = rep(structured_args$latent_mean, each = 2L),
    latent_inv_mean = rep(structured_args$latent_inv_mean, each = 2L),
    s_mean = rep(structured_args$s_mean, each = 2L),
    s2_mean = rep(structured_args$s2_mean, each = 2L),
    observation_weight = rep(0.5, 4L)
  ))
)
stopifnot(max(abs(structured_once$log_collapsed - structured_duplicated$log_collapsed)) < 1.0e-10)

base_args <- list(
  max_iter = 3L, min_iter_elbo = 2L, tol = 0, n_draws = 6L,
  prior_sigma = list(a = 2, b = 1), freeze_beta_warmup_iters = 1L,
  min_beta_updates = 2L, rhs = list(freeze_tau_warmup_iters = 0L, update_every = 1L, min_tau_updates = 0L)
)
normal_ridge <- app_fit_latent_path_normal_vb_core(toy_design, "ridge", base_args, seed = 11L)
normal_cache_probe <- app_latent_normal_fixed_cache(toy_design)
stopifnot(isTRUE(normal_cache_probe$paired_beta_crossproduct))
stopifnot(identical(normal_cache_probe$Y$Pbb, normal_cache_probe$G$Pbb))
stopifnot(normal_ridge$vb_diagnostics$iterations == 3L)
stopifnot(normal_ridge$vb_diagnostics$beta_update_count == 2L)
normal_legacy <- app_fit_latent_path_normal_vb_core(
  toy_design,
  "ridge",
  modifyList(base_args, list(normal_exact_optimization = FALSE)),
  seed = 11L
)
stopifnot(isTRUE(normal_ridge$vb_diagnostics$normal_exact_optimization))
stopifnot(!isTRUE(normal_legacy$vb_diagnostics$normal_exact_optimization))
stopifnot(identical(normal_ridge$vb_diagnostics$fixed_cache_schema, "latent_normal_fixed_cache_v1"))
stopifnot(nrow(normal_ridge$vb_diagnostics$iteration_timing) > 0L)
stopifnot(nrow(normal_ridge$vb_diagnostics$stage_timing) == 3L)
stopifnot(isTRUE(all.equal(
  normal_ridge$summary$theta_mean,
  normal_legacy$summary$theta_mean,
  tolerance = 1.0e-9
)))
stopifnot(isTRUE(all.equal(
  normal_ridge$summary$theta_cov,
  normal_legacy$summary$theta_cov,
  tolerance = 1.0e-9
)))
stopifnot(isTRUE(all.equal(
  normal_ridge$summary$y_future_mean,
  normal_legacy$summary$y_future_mean,
  tolerance = 1.0e-9
)))
stopifnot(isTRUE(all.equal(
  normal_ridge$summary$sigma_mean,
  normal_legacy$summary$sigma_mean,
  tolerance = 1.0e-9
)))
normal_init <- app_glofas_part4_initializer(normal_ridge, toy_design)
normal_rhs <- app_fit_latent_path_normal_vb_core(
  toy_design, "rhs_ns", modifyList(base_args, list(initial_state = normal_init)), seed = 12L
)
stopifnot(all(is.finite(normal_rhs$summary$theta_mean)))

prior_probe <- app_latent_prior_state_init(
  p = ncol(toy_design$H_fixed), prior = "rhs_ns",
  intercept_index = toy_design$intercept_index, vb_args = base_args,
  beta_index = toy_design$beta_index, alpha_index = toy_design$alpha_index
)
addition_probe <- list(
  diagonal = rep(0.25, ncol(toy_design$H_fixed)),
  linear = seq_len(ncol(toy_design$H_fixed)) / 10
)
prior_probe <- app_latent_prior_apply_addition(prior_probe, addition_probe)
prior_probe <- app_latent_prior_state_update(
  prior_probe, normal_rhs$summary$theta_mean, normal_rhs$summary$theta_cov, iter = 1L
)
base_precision <- app_latent_prior_state_combine_precision(prior_probe, ncol(toy_design$H_fixed))
stopifnot(max(abs(prior_probe$prior_precision - base_precision - addition_probe$diagonal)) < 1.0e-12)
stopifnot(identical(prior_probe$prior_linear, addition_probe$linear))

al_args <- modifyList(base_args, list(likelihood_family = "al"))
al_fit <- app_fit_latent_path_al_vb_core(toy_design, 0.5, "ridge", al_args, seed = 13L)
stopifnot(al_fit$vb_diagnostics$beta_update_count == 2L)
exal_args <- modifyList(base_args, list(
  tol = 1.0e-12,
  initial_state = app_glofas_part4_initializer(al_fit, toy_design),
  quadrature_nodes = c(4L, 6L),
  quadrature_tolerance = 1.0e-4
))
exal_fit <- app_fit_latent_path_exal_vb_core(toy_design, 0.5, "ridge", exal_args, seed = 14L)
stopifnot(all(is.finite(exal_fit$summary$theta_mean)))
stopifnot(identical(names(exal_fit$summary$gamma_mean), c("Y", "G")))
stopifnot(nrow(exal_fit$vb_diagnostics$iteration_timing) > 0L)
stopifnot(nrow(exal_fit$vb_diagnostics$stage_timing) == 3L)

joint_args <- modifyList(base_args, list(
  tol = 1.0e-6, joint_outer_max_iter = 1L, joint_outer_min_iter = 1L,
  joint_inner_max_iter = 2L, joint_inner_min_iter = 1L, n_draws = 4L,
  beta_rhs = list(tau0 = 1, slab_s2 = 1, a_zeta = 2, b_zeta = 4),
  alpha_rhs = list(tau0 = 0.001, slab_s2 = 1, a_zeta = 2, b_zeta = 4)
))
joint_fit <- app_fit_latent_path_joint_vb_core(
  designs = list(toy_design, toy_design), tau = c(0.35, 0.65), likelihood = "al",
  independent_fits = list(al_fit, al_fit), vb_args = joint_args, seed = 15L
)
stopifnot(identical(joint_fit$fit_structure, "joint_adjacent_rhs"))
stopifnot(nrow(joint_fit$trace) == 1L)

g <- data.frame(
  target_date = rep(as.Date("2026-02-01") + 0:1, each = 2L),
  horizon = rep(1:2, each = 2L),
  g_transformed = c(1, 3, 2, 4)
)
g$ensemble_weight <- app_glofas_latent_path_ensemble_weights(g)
latent <- list(future_key = unique(g[c("target_date", "horizon")]), g_ensemble = g)
center <- app_latent_path_glofas_center_path(latent)
g2 <- g[rep(seq_len(nrow(g)), each = 2L), , drop = FALSE]
g2$ensemble_weight <- app_glofas_latent_path_ensemble_weights(g2)
latent2 <- list(future_key = latent$future_key, g_ensemble = g2)
stopifnot(isTRUE(all.equal(center, app_latent_path_glofas_center_path(latent2), tolerance = 1.0e-12)))

future_truth_a <- data.frame(
  target_date = as.Date("2026-02-01") + 0:1,
  horizon = 1:2,
  y_transformed = c(10, 20),
  g_transformed = c(1, 2)
)
future_truth_b <- future_truth_a
future_truth_b$y_transformed <- c(-999, 999)
stopifnot(identical(
  app_redact_glofas_latent_path_future_truth(future_truth_a),
  app_redact_glofas_latent_path_future_truth(future_truth_b)
))
truth_key <- future_truth_a[c("target_date", "horizon")]
stopifnot(!identical(
  app_make_glofas_latent_path_scoring_truth(future_truth_a, truth_key)$y_reference,
  app_make_glofas_latent_path_scoring_truth(future_truth_b, truth_key)$y_reference
))

prediction_probe <- list(
  draws = data.frame(
    target_date = rep(as.Date("2026-02-01"), 3L),
    horizon = 1L,
    y_reference = 0.5,
    quantile_level = 0.5,
    q_y_draw = c(0.3, 0.4, 0.5),
    latent_y_draw = c(0.2, 0.4, 0.6)
  ),
  summary = data.frame()
)
normal_score <- app_glofas_part4_score_prediction(prediction_probe, "normal")
outer_crps <- mean(abs(c(0.2, 0.4, 0.6) - 0.5)) -
  mean(abs(outer(c(0.2, 0.4, 0.6), c(0.2, 0.4, 0.6), "-"))) / 2
stopifnot(abs(normal_score$by_horizon$empirical_crps - outer_crps) < 1.0e-12)
stopifnot(identical(
  app_glofas_part4_score_prediction(prediction_probe, "normal", "identity")$by_horizon$y_reference_original,
  0.5
))
prediction_probe$draws$y_reference <- 2
stopifnot(!identical(
  normal_score$by_horizon$empirical_crps,
  app_glofas_part4_score_prediction(prediction_probe, "normal")$by_horizon$empirical_crps
))

cold_args <- app_glofas_part4_vb_args_for_initializer(base_args, initializer = NULL)
stopifnot(cold_args$freeze_beta_warmup_iters == 0L)
stopifnot(is.null(cold_args$initial_state))
warm_args <- app_glofas_part4_vb_args_for_initializer(base_args, initializer = normal_init)
stopifnot(warm_args$freeze_beta_warmup_iters == base_args$freeze_beta_warmup_iters)
stopifnot(identical(warm_args$initial_state, normal_init))

fit_side_probe_path <- tempfile(fileext = ".rds")
saveRDS(toy_design, fit_side_probe_path)
compact_probe <- app_glofas_part4_fit_side_artifact(
  list(
    fit_id = "probe",
    fit = normal_rhs,
    design = toy_design,
    state_contract_hash = app_glofas_part4_state_contract_hash(toy_design)
  ),
  fit_side_probe_path
)
stopifnot(!"design" %in% names(compact_probe))
stopifnot(identical(compact_probe$shared_design_reference$storage_contract,
  "single_shared_truth_free_design_not_duplicated_per_fit"))
stopifnot(nzchar(compact_probe$shared_design_reference$sha256))
unlink(fit_side_probe_path)

historical_fit_path <- tempfile(fileext = ".rds")
historical_beta <- normal_rhs$summary$theta_mean
names(historical_beta) <- colnames(toy_design$H_fixed)
saveRDS(list(
  beta_mean = historical_beta,
  beta_var_diag = diag(normal_rhs$summary$theta_cov)
), historical_fit_path)
historical_init <- app_glofas_part4_historical_initializer(
  historical_fit_path,
  app_sha256_file(historical_fit_path),
  toy_design,
  source_design_hash = "part3_probe"
)
stopifnot(identical(historical_init$theta_mean, as.numeric(historical_beta)))
stopifnot(identical(historical_init$y_future_mean, toy_design$y_future_init))
stopifnot(identical(
  historical_init$provenance$type,
  "validated_part3_historical_coefficient_initializer"
))
bad_historical_hash <- tryCatch({
  app_glofas_part4_historical_initializer(
    historical_fit_path, paste(rep("0", 64L), collapse = ""), toy_design
  )
  FALSE
}, error = function(e) TRUE)
stopifnot(isTRUE(bad_historical_hash))
unlink(historical_fit_path)

stopifnot(is.null(app_glofas_part4_root_initializer_from_manifest(
  data.frame(role = c("reference_anchor", "discrepancy_anchor"), stringsAsFactors = FALSE),
  toy_design
)))

graph <- app_glofas_part4_launch_manifest("part4_graph_test")
stopifnot(identical(app_glofas_part4_parse_dependencies(NA_character_), character()))
stopifnot(identical(app_glofas_part4_parse_dependencies(""), character()))
stopifnot(identical(app_glofas_part4_parse_dependencies("root|median"), c("root", "median")))
empty_dependencies <- app_glofas_part4_parse_dependencies("")
empty_missing <- if (length(empty_dependencies)) {
  empty_dependencies[!file.exists(file.path(tempdir(), paste0(empty_dependencies, ".completed")))]
} else {
  character()
}
stopifnot(identical(empty_missing, character()))
stopifnot(identical(
  app_glofas_part4_dependency_artifact_paths(tempdir(), character()),
  character()
))
stopifnot(identical(
  basename(app_glofas_part4_dependency_artifact_paths(tempdir(), c("ridge", "rhs"))),
  c("ridge_fit_side.rds", "rhs_fit_side.rds")
))
stopifnot(nrow(graph) == 18L)
stopifnot(sum(graph$part4_family == "normal_ridge_diagnostic") == 1L)
stopifnot(sum(graph$part4_family == "normal_rhs_vb_diagnostic") == 1L)
stopifnot(sum(graph$part4_family == "independent_al_rhs_vb") == 7L)
stopifnot(sum(graph$part4_family == "independent_exal_rhs_vb") == 7L)
stopifnot(sum(graph$part4_family == "joint_al_rhs_vb") == 1L)
stopifnot(sum(graph$part4_family == "joint_exal_rhs_vb") == 1L)
normal_rhs_row <- graph[graph$part4_family == "normal_rhs_vb_diagnostic", , drop = FALSE]
stopifnot(grepl("normal_ridge_diagnostic", normal_rhs_row$dependencies, fixed = TRUE))
exal_rows <- graph[graph$part4_family == "independent_exal_rhs_vb", , drop = FALSE]
stopifnot(all(grepl("independent_al_rhs_vb", exal_rows$dependencies, fixed = TRUE)))
