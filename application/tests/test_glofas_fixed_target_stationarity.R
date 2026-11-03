# Generated numeric fixtures only. No RDS, callback execution, applied update,
# authentic inference, held-out scoring, or scientific launch.
local({
  source("application/R/glofas_fixed_target_affine_diagnostics.R", local = TRUE)
  source("application/R/glofas_fixed_target_stationarity.R", local = TRUE)
  engine <- gfta_engine()
  checks <- 0L
  ok <- function(x) {stopifnot(isTRUE(x)); checks <<- checks + 1L}
  rejects <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  make <- function(p0, nonlinear = FALSE) {
    f <- gfta_fixture(2L, nonlinear = nonlinear); m <- c(.4, -.1)
    parts <- gfta_features(f, m); columns <- c("ref0", "ref1", "disc0", "disc1")
    constants <- list(A = (1 - 2*p0)/(p0*(1-p0)), B = 2/(p0*(1-p0)))
    inverse_v <- gfta_inverse_v(f, constants$B)
    S <- matrix(c(.12,.01,0,.005, .01,.08,.004,0,
                  0,.004,.06,.008, .005,0,.008,.04),4L,4L)
    design <- list(H_fixed = matrix(0, 3L, 4L, dimnames = list(NULL, columns)),
      beta_index = 1:2, alpha_index = 3:4, p0 = .95,
      ensemble_member_weight_policy = "unit_member_likelihood_v1",
      future_truth_policy = "physically_excluded_from_fit_objects_scoring_sidecar_only",
      future_key = data.frame(target_date=as.Date("2022-12-25")+1:2,horizon=1:2),
      discrepancy_baseline_future = c(.2,-.3),
      latent_data = list(g_ensemble = data.frame(target_date=rep(as.Date("2022-12-25")+1:2,each=51L),
        horizon=rep(1:2,each=51L),g_transformed=as.numeric(f$members)+rep(c(.2,-.3),each=51L),
        ensemble_weight=1)))
    core <- list(method="vb",likelihood_family="al",vb_diagnostics=list(
      future_y_working_likelihood_used=TRUE,future_gaussian_prior_used=FALSE),draws=list(theta=matrix(0,1,4,
      dimnames=list(NULL,columns))),variational_state=list(theta_mean=f$theta_mean,theta_cov=S,
      y_future_mean=m,y_future_cov=diag(.5,2L),sigma=list(inv_mean=1/f$sigma),
      v=list(inv_mean=c(rep(99,3L),inverse_v)),
      future_linearization=list(strategy="first_order_delta",y_mean=m,
        X_beta_future=parts$H_y[,1:2,drop=FALSE],X_alpha_future=parts$H_g_key[,3:4,drop=FALSE],
        J_beta=lapply(parts$J_y,function(J)J[1:2,,drop=FALSE]),
        J_alpha=lapply(parts$J_g_key,function(J)J[3:4,,drop=FALSE]))))
    list(f=f,m=m,S=S,constants=constants,inverse_v=inverse_v,core=core,design=design)
  }
  for (p0 in c(.2,.5)) for (nonlinear in c(FALSE,TRUE)) {
    z <- make(p0,nonlinear)
    result <- gfst_future_equations(z$core,z$design,p0=p0)
    production <- gfta_update(engine,z$f,z$m,z$inverse_v,z$constants,z$S,jitter=1e-8)
    production_gradient <- -as.numeric(production$precision %*% (production$mean-z$m))
    literal <- gfta_literal(z$f,z$m,z$inverse_v,z$constants,z$S)
    ok(max(abs(result$gradient-production_gradient)) < 1e-10)
    ok(max(abs(result$gradient-literal$gradient)) < 1e-10)
    ok(max(abs(result$precision_without_jitter-literal$GN)) < 1e-10)
    ok(max(abs(result$operational_covariance-production$cov)) < 1e-10)
    ok(max(abs(result$per_horizon$diagnostic_preconditioned_step_not_applied-(production$mean-z$m))) < 1e-10)
    ok(result$normalized_solve_residual < 1e-12)
    ok(result$coordinate_equation_evaluations==1L && result$coordinate_updates_applied==0L)
    ok(result$saved_callback_calls==0L && result$original_file_reads==0L && !result$future_truth_read)
    ok(result$factor_counts$historical_rows_skipped==3L && result$factor_counts$future_G==102L)
    ok(result$all_retained_jacobians_causal && result$p0==p0)
    # Plug-in input objects are never updated by this evaluation.
    ok(identical(z$core$variational_state$y_future_mean,z$m))
  }
  z <- make(.5)
  rejects(gfst_future_equations(z$core,z$design)) # shared design p0 must not silently win
  bad <- z$core;bad$vb_diagnostics$future_gaussian_prior_used <- TRUE
  rejects(gfst_future_equations(bad,z$design,p0=.5))
  bad <- z$design;bad$latent_data$g_ensemble$ensemble_weight[1L] <- 1/51
  rejects(gfst_future_equations(z$core,bad,p0=.5))
  bad <- z$design;bad$latent_data$g_ensemble$horizon[1L] <- 3L
  rejects(gfst_future_equations(z$core,bad,p0=.5))
  bad <- z$core;bad$variational_state$v$inv_mean <- bad$variational_state$v$inv_mean[-1L]
  rejects(gfst_future_equations(bad,z$design,p0=.5))
  bad <- z$core;bad$draws$theta <- bad$draws$theta[,4:1,drop=FALSE]
  rejects(gfst_future_equations(bad,z$design,p0=.5))
  bad <- z$design;bad$latent_data$g_ensemble$y_transformed <- rep(2,102L)
  rejects(gfst_future_equations(z$core,bad,p0=.5))
  bad <- z$core;bad$variational_state$future_linearization$J_beta[[1]][1,1] <- .1
  r <- gfst_future_equations(bad,z$design,p0=.5)
  ok(!r$all_retained_jacobians_causal) # retain adverse diagnostic; do not mask it
  # Saved callbacks present in an authenticated object are not called.
  called <- 0L
  z$design$future_builder <- function(...) {called <<- called+1L;stop("forbidden callback")}
  gfst_future_equations(z$core,z$design,p0=.5);ok(called==0L)
  cat(sprintf("GLOFAS_FIXED_TARGET_STATIONARITY_GENERATED_PASS checks=%d original_RDS_reads=0 applied_updates=0\n",checks))
})
