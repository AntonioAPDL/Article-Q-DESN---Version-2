# Production-path policy, exclusion, moment and small-fit regression checks.
local({
  source("application/scripts/_glofas_unit_member_bootstrap.R")
  checks <- 0L
  check <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  rejects <- function(expr) inherits(tryCatch(force(expr), error = identity), "error")
  cfg <- list(application_model = list(contract = "latent_path_ensemble_likelihood"),
    inference = list(likelihood_family = "al"),
    prediction = list(prediction_unit = "posterior_draw", q_g_source = "posterior_model_quantile"))
  origin <- as.Date("2022-12-25")
  panel <- data.frame(origin_date = origin,
    target_date = c(origin - 4:0, rep(origin + 1:28, each = 51L)),
    horizon = c(rep(0L, 5L), rep(1:28, each = 51L)),
    member = c(rep(NA_character_, 5L), rep(sprintf("m%02d", 1:51), 28L)),
    is_retrospective = c(rep(TRUE, 5L), rep(FALSE, 1428L)),
    is_ensemble = c(rep(FALSE, 5L), rep(TRUE, 1428L)),
    y_transformed = c(seq(.1, .5, length.out = 5L), rep(1000, 1428L)),
    g_transformed = seq(.1, 1, length.out = 1433L), split = "toy", cutoff_id = "toy")
  cutoff <- data.frame(cutoff_id = "toy", origin_date = origin,
    train_start = origin-4L, train_end = origin, eval_start = origin+1L,
    eval_end = origin+28L, horizon_min = 1L, horizon_max = 28L)
  legacy <- app_make_glofas_latent_path_data(panel, cfg, cutoff)
  cfg$application_model$ensemble_member_weight_policy <- "unit_member_likelihood_v1"
  unit <- app_make_glofas_latent_path_data(panel, cfg, cutoff)
  check(all(abs(legacy$g_ensemble$ensemble_weight-1/51) < 1e-15))
  check(all(unit$g_ensemble$ensemble_weight == 1))
  check(nrow(unit$g_ensemble) == 1428L)
  check(all(tapply(unit$g_ensemble$ensemble_weight, unit$g_ensemble$horizon, sum) == 51))
  check(all(!is.finite(unit$g_ensemble$y_transformed)))
  check(identical(unit$y_history, legacy$y_history))
  check(identical(unit$g_retro, legacy$g_retro))
  bad <- unit; bad$g_ensemble$ensemble_weight[[1L]] <- 1/51
  check(rejects(app_validate_glofas_latent_path_data(bad)))
  bad <- unit; bad$g_ensemble$y_transformed[[1L]] <- 12
  check(rejects(app_validate_glofas_latent_path_data(bad)))
  check(rejects(app_glofas_latent_path_weight_policy("unit-ish")))
  check(identical(app_latent_ensemble_weight_contract(list()), "each_horizon_sums_to_one"))
  check(identical(app_latent_ensemble_weight_contract(list(ensemble_member_weight_policy =
    "unit_member_likelihood_v1")), "each_included_member_weight_one"))

  builder <- function(y) {
    xb <- cbind(1, c(.4, y[[1L]], y[[2L]]))
    xa <- cbind(1, c(-.2, 1.2-y[[1L]], 1.3-y[[2L]]))
    Jy <- Jg <- lapply(1:3, function(h) matrix(0, 4L, 3L))
    for (h in 2:3) { Jy[[h]][2L, h-1L] <- 1; Jg[[h]][2L, h-1L] <- 1; Jg[[h]][4L, h-1L] <- -1 }
    index <- rep(1:3, each = 51L)
    list(H_y = cbind(xb, matrix(0, 3L, 2L)), H_g_key = cbind(xb, xa),
      g_future_index = index, J_y = Jy, J_g_key = Jg,
      z_g = rep(c(1, 1.1, 1.2), each = 51L)+rep(seq(-.1, .1, length.out = 51L), 3L),
      weight_g = rep(1, 153L), row_info_y = data.frame(source = "Y", future_index = 1:3),
      row_info_g = data.frame(source = "G", future_index = index),
      discrepancy_baseline_future = rep(0, 3L))
  }
  X <- cbind(intercept = 1, lag = c(.1, .2, .3, .4))
  src <- factor(rep(c("Y", "G"), each = 4L), levels = c("Y", "G"))
  design <- list(z_fixed = c(.2, .4, .6, .8, .5, .7, .9, 1.1),
    H_fixed = app_make_augmented_discrepancy_design(rbind(X, X), src, rbind(X, X)),
    X_beta = X, X_alpha = X, source_fixed = src, weight_fixed = rep(1, 8L),
    row_info_fixed = data.frame(source = src), future_builder = builder,
    future_key = data.frame(target_date = origin+1:3, horizon = 1:3),
    beta_index = 1:2, alpha_index = 3:4, intercept_index = c(1L, 3L),
    y_future_init = c(.9, 1, 1.1), feature_strategy = "recursive_latent_path",
    future_truth_policy = "physically_excluded_from_fit_objects_scoring_sidecar_only",
    ensemble_member_weight_policy = "unit_member_likelihood_v1", design_version = "unit_toy")
  app_validate_glofas_latent_path_design(design)
  ycov <- matrix(c(.3, .1, .05, .1, .4, .1, .05, .1, .3), 3L)
  tcov <- diag(c(.2, .3, .2, .4))
  tm <- c(.2, .5, .1, -.2)
  stream <- app_latent_row_moments(design, design$y_future_init, ycov, tm, tcov)
  dense_design <- design
  dense_design$future_builder <- function(y) {
    out <- builder(y)
    out$H_g <- out$H_g_key[out$g_future_index, , drop = FALSE]
    out$J_g <- out$J_g_key[out$g_future_index]
    out
  }
  dense <- app_latent_row_moments(dense_design, design$y_future_init, ycov, tm, tcov, "dense_debug")
  check(max(abs(app_latent_all_R(stream)-app_latent_all_R(dense))) < 1e-10)
  check(max(abs(app_latent_all_e(stream)-app_latent_all_e(dense))) < 1e-10)
  check(all(app_latent_all_weight(stream) == 1))
  excluded <- app_latent_apply_future_y_weight_policy(stream, include = FALSE)
  check(all(excluded$future$weight_y == 0))
  check(all(excluded$future$weight_g == 1))
  check(sum(app_latent_all_weight(excluded)) == 8+153)
  check(sum(app_latent_all_weight(stream)) == 8+3+153)
  # The future-Y cross moment contains the covariance derivative, not only E(h)E(Y).
  check(abs(stream$future$b_y[[2L]][[2L]]-
    stream$future$H_y[2L, 2L]*design$y_future_init[[2L]]-ycov[1L, 2L]) < 1e-12)
  probe <- builder(design$y_future_init)
  for (h in 1:3) check(all(probe$J_g_key[[h]][, h:3, drop = FALSE] == 0))
  # Permuting members preserves an ordinary product; duplicating them need not.
  perm <- rev(seq_along(probe$z_g))
  direct <- sum((probe$z_g-as.numeric(probe$H_g_key %*% tm)[probe$g_future_index])^2)
  permuted <- sum((probe$z_g[perm]-as.numeric(probe$H_g_key %*% tm)[probe$g_future_index[perm]])^2)
  check(abs(direct-permuted) < 1e-12)
  check(abs(2*direct-sum(rep((probe$z_g-as.numeric(probe$H_g_key %*% tm)[probe$g_future_index])^2, 2L))) < 1e-12)

  controls <- app_glofas_unit_member_default_controls()
  args <- app_glofas_unit_member_vb_controls(list(warm_start = list(x=1), checkpoint = list(x=1)),
    list(unit_member_execution = controls))
  check(is.null(args$warm_start) && is.null(args$checkpoint))
  check(args$joint_inner_workers == 1L && args$joint_require_post_release)
  controls$joint_inner_workers <- 7L
  check(rejects(app_glofas_unit_member_vb_controls(list(), list(unit_member_execution=controls))))
  fitargs <- list(max_iter = 3L, min_iter_elbo = 2L, tol = 1e-4,
    n_draws = 5L, prior_sigma = list(a=2, b=1),
    rhs = list(freeze_tau_warmup_iters=0L, min_tau_updates=0L))
  normal <- app_fit_latent_path_normal_vb_core(design, "ridge", fitargs, seed=32L)
  al <- app_fit_latent_path_al_vb_core(design, .5, "ridge", fitargs, seed=33L)
  prior <- list(mean=rep(0, 3L), covariance=diag(1, 3L),
    precision=diag(1, 3L), replace_future_y_working_likelihood=TRUE)
  fitargs$future_gaussian_prior <- prior
  al_replaced <- app_fit_latent_path_al_vb_core(design, .5, "ridge", fitargs, seed=35L)
  exal <- app_fit_latent_path_exal_vb_core(design, .5, "ridge", fitargs, seed=34L)
  check(all(is.finite(normal$summary$theta_cov)))
  check(all(is.finite(al$summary$theta_cov)))
  check(all(is.finite(exal$summary$theta_cov)))
  for (fit in list(normal, al, exal)) check(identical(fit$vb_diagnostics$ensemble_weight_contract,
    "each_included_member_weight_one"))
  check(!exal$vb_diagnostics$future_y_working_likelihood_used)
  check(!al_replaced$vb_diagnostics$future_y_working_likelihood_used)
  check(abs(al_replaced$variational_state$sigma$shape[["Y"]]-(2+1.5*4)) < 1e-12)
  check(abs(al_replaced$variational_state$sigma$shape[["G"]]-(2+1.5*(4+153))) < 1e-12)
  check(abs(normal$variational_state$sigma$shape[["Y"]]-(2+(4+3)/2)) < 1e-12)
  check(identical(exal$vb_diagnostics$weighted_local_factor_contract, "ordinary_augmented_likelihood"))
  jq <- c(.25, .75)
  jd <- lapply(jq, function(p) app_glofas_part4_design_for_quantile(design, p))
  ji <- lapply(seq_along(jq), function(k) app_fit_latent_path_al_vb_core(
    jd[[k]], jq[[k]], "ridge", fitargs, seed=40L+k))
  ja <- modifyList(fitargs, list(joint_outer_max_iter=2L, joint_outer_min_iter=1L,
    joint_inner_max_iter=2L, joint_inner_min_iter=1L, joint_inner_workers=1L,
    joint_rhs_freeze_outer_iters=0L, joint_rhs_min_tau_updates=0L))
  joint <- app_fit_latent_path_joint_vb_core(jd, jq, "al", ji, ja, seed=48L)
  check(identical(joint$ensemble_weight_contract, "each_included_member_weight_one"))
  check(length(joint$unit_member_state_contract_hashes) == 2L)
  bad_joint <- joint; bad_joint$ensemble_weight_contract <- "each_horizon_sums_to_one"
  check(rejects(app_fit_latent_path_joint_vb_core(jd, jq, "al", vb_args=ja,
    initial_joint_fit=bad_joint)))
  cat(sprintf("PASS: GloFAS unit-member policy and production path (%d checks)\n", checks))
})
