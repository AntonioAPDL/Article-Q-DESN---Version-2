# Generated in-memory fixtures only: no retained data, fit, design or truth read.
local({
  source("scripts/glofas_same_family_fitted_history.R", local = TRUE)
  checks <- 0L
  ok <- function(x) {stopifnot(isTRUE(x)); checks <<- checks + 1L; invisible(TRUE)}
  reject <- function(expr, text) {
    e <- tryCatch({force(expr); NULL}, error = function(e) e)
    ok(inherits(e, "error")); ok(grepl(text, conditionMessage(e), fixed = TRUE))
  }
  origin <- as.Date("2022-12-25"); dates <- seq(origin - 5L, origin, by = "day")
  Xb <- cbind(intercept = 1, feature = c(-2, -1, 0, 1, 2, 3))
  H <- rbind(cbind(Xb, discrepancy = 0), cbind(Xb, discrepancy = 1))
  colnames(H) <- c("beta_intercept", "beta_feature", "alpha_intercept")
  design <- list(H_fixed = H, source_fixed = factor(rep(c("Y", "G"), each = 6L)),
    row_info_fixed = data.frame(source = rep(c("Y", "G"), each = 6L),
      row_role = rep(c("historical_usgs", "historical_glofas_retrospective"), each = 6L),
      feature_row = rep(1:6, 2L), target_date = rep(dates, 2L), is_future = FALSE),
    X_beta = Xb, base_panel = data.frame(target_date = dates), beta_index = 1:2,
    alpha_index = 3L, two_block_design = TRUE,
    future_truth_policy = "physically_excluded_from_fit_objects_scoring_sidecar_only",
    ensemble_member_weight_policy = "unit_member_likelihood_v1",
    future_builder = function(...) stop("Saved callback must not run"))
  core <- function(likelihood = "al", level = .5, prior = "rhs_ns") list(
    method = "vb", likelihood_family = likelihood, prior = prior,
    summary = list(theta_mean = c(2 + level, .1, 1000)),
    draws = list(theta = matrix(0, 1L, 3L, dimnames = list(NULL, colnames(H)))),
    variational_state = list(sigma = list(shape = c(Y = 3, G = 4), rate = c(Y = 2, G = 5))),
    vb_diagnostics = list(converged = TRUE, future_y_working_likelihood_used = TRUE,
      future_gaussian_prior_used = FALSE))
  result <- function(id = "gft-al-p050") {
    mq <- startsWith(id, "gft-mq-")
    likelihood <- if (grepl("exal", id, fixed = TRUE)) "exal" else "al"
    p <- if (mq) gfh_tau() else as.numeric(sub(".*-p", "", id)) / 100
    fit <- if (mq) list(schema_version = "glofas_part4_joint_latent_v1",
      fit_structure = "joint_adjacent_rhs", likelihood_family = likelihood,
      converged = TRUE, tau = p, fits = lapply(p, function(z) core(likelihood, z))) else core(likelihood, p)
    list(schema_version = "glofas_family_transition_fit_v1", task_id = id,
      converged = TRUE, status = "converged", fit = fit,
      target_contract = list(schema_version = "glofas_family_transition_v1",
        future_truth_used_in_fit = FALSE, replacement_gaussian_path_prior = FALSE))
  }
  normal <- function(prior = "ridge") list(status = "completed", likelihood_family = "normal",
    coefficient_prior = prior, fit = core("normal", .5, prior))
  history <- gfh_reference_history(design, 3L)
  ok(identical(history$dates, tail(dates, 3L)))
  ok(identical(unname(history$H), unname(H[4:6, , drop = FALSE])))
  rng <- if (exists(".Random.seed", globalenv(), inherits = FALSE)) get(".Random.seed", globalenv()) else NULL
  fit <- result(); observed <- gfh_transition_rows(fit, design, 3L)
  ok(nrow(observed) == 3L && all(observed$tau == .5))
  ok(isTRUE(all.equal(observed$quantile_transformed, c(2.6, 2.7, 2.8), tolerance = 1e-14)))
  ok(identical(observed$quantile, expm1(observed$quantile_transformed)))
  ok(all(observed$quantile_offset_transformed == 0))
  fit$fit$summary$theta_mean[3L] <- -1e100
  ok(identical(gfh_transition_rows(fit, design, 3L), observed))
  # Covariance is not needed for a linear posterior mean; do not invent one.
  fit$fit$summary$theta_cov <- NULL
  ok(identical(gfh_transition_rows(fit, design, 3L), observed))
  fit$fit$summary$y_future_mean <- rep(1e10, 28L)
  fit$fit$summary$y_future_cov <- diag(1e8, 28L)
  ok(identical(gfh_transition_rows(fit, design, 3L), observed))
  for (family in c("al", "exal")) for (p in gfh_tau()) {
    id <- sprintf("gft-%s-p%03d", family, round(100 * p))
    z <- gfh_transition_rows(result(id), design, 3L)
    ok(nrow(z) == 3L && all(z$tau == p))
    ok(isTRUE(all.equal(z$quantile_transformed, 2 + p + .1 * 1:3, tolerance = 1e-14)))
  }
  ex <- result("gft-exal-p020"); ex$fit$summary$gamma_mean <- c(Y = 100, G = -100)
  ex$fit$summary$sigma_mean <- c(Y = 1e10, G = 1e-10)
  ok(identical(gfh_transition_rows(ex, design, 3L),
    gfh_transition_rows(result("gft-exal-p020"), design, 3L)))
  for (f in c("al", "exal")) {
    z <- gfh_transition_rows(result(paste0("gft-mq-", f)), design, 3L)
    ok(nrow(z) == 21L && identical(unique(z$tau), gfh_tau()))
  }
  conditional <- result("gft-mq-al")
  for(k in seq_len(7L))conditional$fit$fits[[k]]$prior <- "ridge"
  conditional$fit$converged_rhs <- TRUE
  conditional$fit$rhs_state_reference <- rep(list(list(prior_precision=c(1,1))),7L)
  conditional$fit$rhs_state_discrepancy <- rep(list(list(prior_precision=1)),7L)
  conditional$fit$rhs_partition_certificate <- data.frame(schema_version="glofas_part3_rhs_partition_v1",
    p_reference=2L,p_discrepancy=1L,n_quantiles=7L,overlap_count=0L,all_precision_finite=TRUE)
  ok(identical(gfh_transition_rows(conditional,design,3L),gfh_transition_rows(result("gft-mq-al"),design,3L)))
  bad <- conditional;bad$fit$converged_rhs <- FALSE
  reject(gfh_transition_rows(bad,design,3L),"outer RHS certificate")
  bad <- conditional;bad$fit$rhs_state_reference[[1L]]$prior_precision[1L] <- -1
  reject(gfh_transition_rows(bad,design,3L),"outer RHS certificate")
  bad <- result();bad$fit$prior <- "ridge"
  reject(gfh_transition_rows(bad,design,3L),"fixed-p")
  # Retain crossing fitted functionals rather than imposing order.
  crossing <- result("gft-mq-al")
  for (k in seq_along(gfh_tau())) crossing$fit$fits[[k]]$summary$theta_mean[1L] <- 10 - k
  z <- gfh_transition_rows(crossing, design, 3L)
  ok(all(diff(z$quantile_transformed[z$target_date == as.character(origin)]) < 0))
  ok(all(!z$isotonic_adjustment))

  # Independent integral confirms the IG VARIANCE half-moment.
  sigma <- list(shape = c(Y = 3, G = 4), rate = c(Y = 2, G = 5))
  analytic <- gfh_normal_sd_mean(sigma)
  integral <- integrate(function(u) u^(-.5) * dgamma(u, shape = 3, rate = 2),
    lower = 0, upper = Inf, rel.tol = 1e-11)$value
  ok(abs(analytic - integral) < 1e-10)
  ok(abs(analytic - sqrt(2 / (3 - 1))) > .01)
  # E(sqrt(variance)) exists even when E(variance) does not.
  sigma$shape[["Y"]] <- 1
  ok(abs(gfh_normal_sd_mean(sigma) - sqrt(2 * pi)) < 1e-12)
  nr <- gfh_normal_rows(normal(), design, "normal_ridge", 3L)
  ok(nrow(nr) == 21L && all(nr$family == "Normal Ridge"))
  center <- nr[nr$tau == .5, ]
  ok(identical(center$quantile_transformed, observed$quantile_transformed))
  low <- nr[nr$tau == .05, ]; high <- nr[nr$tau == .95, ]
  ok(max(abs(low$quantile_transformed + high$quantile_transformed - 2 * center$quantile_transformed)) < 1e-14)
  ok(abs(low$quantile_offset_transformed[1L] - analytic * qnorm(.05)) < 1e-14)
  ok(all(gfh_normal_rows(normal("rhs_ns"), design, "normal_rhs", 3L)$family == "Normal RHS"))
  for (name in c("future_path_factor_used", "posterior_predictive_quantile",
      "quantile_functional_credible_interval", "extra_response_noise_added", "isotonic_adjustment")) {
    ok(all(!nr[[name]]) && all(!observed[[name]]))
  }
  ok(all(nr$estimand == "VB_mean_conditional_quantile_on_log1p_scale"))
  ok(identical(nr$quantile, expm1(nr$quantile_transformed)))
  ok(identical(rng, if (exists(".Random.seed", globalenv(), inherits = FALSE)) get(".Random.seed", globalenv()) else NULL))

  bad <- design; bad$H_fixed[6L, 3L] <- 1; reject(gfh_reference_history(bad, 3L), "zero discrepancy")
  bad <- design; bad$X_beta[6L, 2L] <- 100; reject(gfh_reference_history(bad, 3L), "reference features")
  bad <- design; bad$source_fixed[1L] <- "G"; reject(gfh_reference_history(bad, 3L), "source rows")
  bad <- design; bad$row_info_fixed$row_role[6L] <- "historical_glofas_retrospective"
  reject(gfh_reference_history(bad, 3L), "alignment")
  bad <- design; bad$row_info_fixed$feature_row[6L] <- 5L; reject(gfh_reference_history(bad, 3L), "alignment")
  bad <- design; bad$row_info_fixed$target_date[6L] <- origin + 1L
  reject(gfh_reference_history(bad, 3L), "future or invalid date")
  bad <- design; bad$base_panel$target_date[6L] <- origin - 1L
  reject(gfh_reference_history(bad, 3L), "unique and pre-origin")
  bad <- design; bad$row_info_fixed$is_future[6L] <- TRUE
  reject(gfh_reference_history(bad, 3L), "source rows")
  bad <- design; bad$beta_index <- 1:3; reject(gfh_reference_history(bad, 3L), "partition")
  bad <- design; colnames(bad$H_fixed)[1L] <- ""; reject(gfh_reference_history(bad, 3L), "named historical")
  reject(gfh_reference_history(design, 0L), "one to thirty")
  reject(gfh_reference_history(design, 7L), "dates are absent")
  bad <- result(); bad$task_id <- "gft-al-p010"; reject(gfh_transition_rows(bad, design, 3L), "completed same-family")
  bad <- result(); bad$converged <- FALSE; reject(gfh_transition_rows(bad, design, 3L), "completed same-family")
  bad <- result(); bad$target_contract$replacement_gaussian_path_prior <- TRUE
  reject(gfh_transition_rows(bad, design, 3L), "completed same-family")
  bad <- result(); bad$fit$likelihood_family <- "exal"; reject(gfh_transition_rows(bad, design, 3L), "core likelihood")
  bad <- result(); bad$fit$vb_diagnostics$future_gaussian_prior_used <- TRUE
  reject(gfh_transition_rows(bad, design, 3L), "core likelihood")
  bad <- result(); bad$fit$warm_start_contract <- list(quantile_level = .2)
  reject(gfh_transition_rows(bad, design, 3L), "probability level")
  bad <- result(); bad$fit$summary$theta_mean <- 1:2
  reject(gfh_transition_rows(bad, design, 3L), "coefficient dimension")
  bad <- result(); colnames(bad$fit$draws$theta) <- rev(colnames(H))
  reject(gfh_transition_rows(bad, design, 3L), "feature order")
  bad <- result(); bad$fit$prior <- "unknown"; reject(gfh_transition_rows(bad, design, 3L), "known VB")
  bad <- result(); bad$fit$likelihood_family <- c("al", "exal")
  reject(gfh_transition_rows(bad, design, 3L), "core likelihood")
  bad <- result("gft-mq-al"); bad$fit$tau <- rev(gfh_tau())
  reject(gfh_transition_rows(bad, design, 3L), "complete multiquantile")
  bad <- normal(); bad$fit$variational_state$sigma$shape[["Y"]] <- .5
  reject(gfh_normal_rows(bad, design, "normal_ridge", 3L), "shape > 1/2")
  bad <- normal(); names(bad$fit$variational_state$sigma$shape) <- c("sigma_Y", "sigma_G")
  reject(gfh_normal_rows(bad, design, "normal_ridge", 3L), "named Normal")
  bad <- normal(); bad$fit$variational_state$sigma$rate[["Y"]] <- -1
  reject(gfh_normal_rows(bad, design, "normal_ridge", 3L), "positive rate")
  bad <- normal(); bad$fit$variational_state$sigma <- NULL
  reject(gfh_normal_rows(bad, design, "normal_ridge", 3L), "named Normal")
  reject(gfh_normal_rows(normal(), design, "raw_glofas", 3L), "known enrolled Normal")
  reject(gfh_normal_rows(normal(), design, "normal_rhs", 3L), "enrolled Normal state")
  reject(gfh_core_rows(core("normal", .5, "rhs_ns"), history, "Normal Ridge", gfh_tau()),
    "label disagrees with prior")
  cat(sprintf("GLOFAS_FITTED_HISTORY_PURE_TESTS_PASS checks=%d\n", checks))
})
