# Generated-only guided importance-weight and exact H2 checks.
local({
  files <- c("glofas_innovation_coordinates.R", "glofas_collapsed_particle_vi.R",
    "glofas_collapsed_al_target.R", "glofas_al_future_score_projection.R",
    "glofas_al_affine_guided_proposal.R", "glofas_guided_collapsed_particle.R",
    "glofas_collapsed_particle_reference.R", "glofas_variance_particle_reference.R")
  for (file in files) source(file.path("scripts/diagnostics", file), local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  near <- function(x,y,tolerance=1e-9) ok(max(abs(x-y)) < tolerance)
  reject <- function(expr) ok(inherits(try(force(expr),silent=TRUE),"try-error"))
  kind <- RNGkind(); initial_seed <- if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
  on.exit({do.call(RNGkind,as.list(kind));if(is.null(initial_seed)){
    if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)
  }else assign(".Random.seed",initial_seed,.GlobalEnv)},add=TRUE)
  block <- function(ix) list(index=ix,intercept_index=ix[1L],tau0=.3,intercept_prec=.2,
    slab_shape=2,slab_rate=4,zeta2_fixed=NULL)
  spec <- gcat_spec(6,list(beta=block(1:3),alpha=block(4:6)),.2,
    list(Y=c(shape=2,rate=1),G=c(shape=3,rate=.8)))
  F <- rbind(c(1,.2,-.1),c(1,.4,.1)); D <- rbind(c(1,-.1,.3),c(1,.2,-.2))
  G <- rbind(seq(.08,.22,length.out=51),seq(.1,.24,length.out=51))
  eta <- seq(-.1,.1,length.out=spec$dimension)
  eta[spec$scales] <- log(c(.3,.07))
  make <- function(lag,members=G) gafsp_make_generated_al_binding(spec,F,D,members,
    reference_lag=lag,discrepancy_lag=.03,known_baseline=c(.07,.08),particles=2L)
  # Fully adapted Y1 proposals give exactly G1*I for ANY N, even N=1;
  # post-correction ESS may be low but no intervening resampling is allowed.
  for (lag in c(-.43,0,.37)) {
    binding <- make(lag); exact <- gvar_exact_h2(binding,eta)$log_evidence
    for (n in c(1L,2L,16L)) for (threshold in c(.05,1)) for (seed in c(2026110701L,2026110702L)) {
      x <- gpg_affine_h2(binding,eta,particles=n,ess_fraction=threshold,seed=seed)
      ok(x$complete && is.null(x$failure)); near(x$log_normalizer_estimate,exact)
      ok(x$member_factor_evaluations==2L*n*51L && all(x$member_weights==1))
      ok(x$diagnostics$guided_particles[1L]==n && x$diagnostics$guided_particles[2L]==0L &&
        all(!x$diagnostics$resampled_after_correction))
      near(x$weights,rep(1/n,n),1e-10)
      ok(!x$production_qualified && !x$production_launch_authorized &&
        !x$full_posterior_accuracy_qualified && !x$publication_authorized && x$original_reads==0L)
    }
  }
  binding <- make(.37); parameters <- list(coefficients=eta[seq_len(spec$p)],
    sigma=setNames(exp(eta[spec$scales]),names(spec$scales)))
  common <- list(parameters=parameters,location=binding$callbacks$location,
    scale=function(h,past,parameters)unname(parameters$sigma["Y"]),
    member_location=binding$callbacks$member_location,
    member_scale=function(h,past,parameters)unname(parameters$sigma["G"]),
    members=G,horizon=2L,probability=.2,particles=16L,seed=2026110703L,
    gates=list(min_ess=1,min_unique_ancestors=1L))
  # With no guide, the separate implementation preserves bootstrap paths,
  # normalizer and RNG exactly, without altering the original kernel.
  set.seed(824); before <- .Random.seed
  baseline <- do.call(gcpv_smc,common); plain <- do.call(gpg_smc,common)
  ok(identical(before,.Random.seed));near(plain$paths,baseline$paths,1e-15)
  near(plain$log_normalizer_estimate,baseline$log_normalizer_estimate,1e-15)
  ok(identical(plain$callback_calls,baseline$callback_calls))
  empty <- make(.37,NULL)
  no_members <- gpg_affine_h2(empty,eta,particles=1L)
  ok(no_members$complete && no_members$log_normalizer_estimate==0 &&
    no_members$normalizer_estimate==1 && no_members$callback_calls_by_role["guide_factory"]==0)
  empty_args <- common;empty_args["members"] <- list(NULL)
  empty_args$guide <- function(...)stop("no-member guide must not run")
  identity <- do.call(gpg_smc,empty_args)
  ok(identity$complete && identity$log_normalizer_estimate==0 &&
    all(identity$diagnostics$guided_particles==0L))

  mu1 <- binding$callbacks$location(1L,numeric(),parameters)
  offset2 <- sum(F[2L,]*parameters$coefficients[1:3])+sum(D[2L,]*parameters$coefficients[4:6])+.08
  proposal <- gaag_build(mu1,unname(parameters$sigma["Y"]),G[2L,],offset2,.4,
    unname(parameters$sigma["G"]),.2)
  envelope <- gaag_as_guide(proposal)
  factory <- function(h,past,parameters,prior_location,prior_scale,probability) {
    stopifnot(h==1L,length(past)==0L)
    envelope
  }
  guided_args <- common;guided_args$guide <- factory
  correct <- do.call(gpg_smc,guided_args)
  exact <- gvar_exact_h2(binding,eta)$log_evidence
  near(correct$log_normalizer_estimate,exact)
  # Negative calculation: lying about q changes the normalizer even with
  # proposal-only flags. The generic API does NOT certify arbitrary density.
  bad_factory <- function(h,past,parameters,prior_location,prior_scale,probability) {
    out <- envelope;out$log_density <- function(y)envelope$log_density(y)+log(2);out
  }
  bad_args <- common;bad_args$guide <- bad_factory
  wrong <- do.call(gpg_smc,bad_args)
  ok(wrong$complete && !wrong$generic_proposal_normalization_authenticated)
  near(wrong$log_normalizer_estimate,exact-log(2))
  ok(!wrong$production_qualified && !wrong$reference_qualified)
  # Omitting f/q effectively replaces the future law with q, and fails.
  omitted <- function(h,past,parameters,prior_location,prior_scale,probability) {
    out<-envelope;out$log_density<-function(y)gic_al_log_density(y,prior_location,probability,prior_scale);out
  }
  omitted_args <- common;omitted_args$guide <- omitted
  omitted_result <- do.call(gpg_smc,omitted_args)
  ok(omitted_result$complete && abs(omitted_result$log_normalizer_estimate-exact)>.01)
  # Negative calculation: resampling between f/q and G2 breaks their exact
  # cancellation (though proper resampling would retain unbiasedness).
  points <- gaag_quantile(proposal,c(.01,.99))
  g2 <- vapply(points,function(y)sum(gic_al_log_density(G[2L,],offset2+.4*y,.2,
    unname(parameters$sigma["G"]))),numeric(1L))
  ratio <- proposal$log_normalizer-g2
  premature_increment <- gcpv_logsumexp(ratio)-log(2)+max(g2)
  ok(abs(premature_increment-proposal$log_normalizer)>.01)

  # A guide need not equal the nonlinear true conditional. With N=1 the
  # complete pathwise importance ratio can be checked without MC tolerance:
  # G1 * [fY1/q1] * G2_nonlinear. The guide never replaces that G2 factor.
  nonlinear_args <- common; nonlinear_args$particles <- 1L
  nonlinear_args$guide <- factory
  nonlinear_args$member_location <- function(h,past,parameters) {
    if(h==1L) binding$callbacks$member_location(h,past,parameters) else
      offset2+.4*past[1L]+.05*past[1L]^2
  }
  nonlinear_errors <- numeric(6L)
  for (j in 1:6) {
    nonlinear_args$seed <- 2026110800L+j
    draw <- do.call(gpg_smc,nonlinear_args); y <- draw$paths[1L,1L]
    literal <- sum(gic_al_log_density(G[1L,],binding$callbacks$member_location(1L,numeric(),parameters),
      .2,unname(parameters$sigma["G"]))) +
      gic_al_log_density(y,mu1,.2,unname(parameters$sigma["Y"])) - envelope$log_density(y) +
      sum(gic_al_log_density(G[2L,],offset2+.4*y+.05*y^2,.2,unname(parameters$sigma["G"])))
    ok(draw$complete);near(draw$log_normalizer_estimate,literal)
    nonlinear_errors[j] <- draw$log_normalizer_estimate-exact
    ok(!draw$generic_proposal_normalization_authenticated && !draw$production_qualified)
  }
  ok(max(abs(nonlinear_errors))>.001)

  # A proper guide can be nearly flat across thousands of log-density units.
  # f/q then gives numerically zero probability weights that MUST revive at
  # G2. Carrying log weights prevents a spurious particle-count dependence.
  flat_spec <- gcat_spec(6,list(beta=block(1:3),alpha=block(4:6)),.5,
    list(Y=c(shape=2,rate=1),G=c(shape=3,rate=.8)))
  flat_eta <- numeric(flat_spec$dimension);flat_eta[flat_spec$scales] <- log(c(.5,25.5))
  flat_members <- rbind(rep(0,51L),rep(3000,51L))
  flat <- gafsp_make_generated_al_binding(flat_spec,F,D,flat_members,
    reference_lag=1,discrepancy_lag=0,known_baseline=c(0,0),particles=2L)
  flat_exact <- gvar_exact_h2(flat,flat_eta)$log_evidence
  for (n in c(1L,16L)) {
    stable <- gpg_affine_h2(flat,flat_eta,particles=n,seed=2026110901L)
    ok(stable$complete);near(stable$log_normalizer_estimate,flat_exact,1e-8)
    near(stable$weights,rep(1/n,n),1e-9)
    ok(all(is.finite(stable$log_weights)))
    if(n>1L)ok(stable$diagnostics$post_correction_ESS[1L]<1.01)
  }

  malformed <- function(h,past,parameters,prior_location,prior_scale,probability) {
    out<-envelope;out$log_density<-function(y)NA_real_;out
  }
  malformed_args<-common;malformed_args$guide<-malformed
  failed<-do.call(gpg_smc,malformed_args)
  ok(!failed$complete && is.na(failed$log_normalizer_estimate) && !is.null(failed$failure))
  rng_factory <- function(h,past,parameters,prior_location,prior_scale,probability) {
    stats::runif(1);envelope
  }
  rng_args<-common;rng_args$guide<-rng_factory
  before <- .Random.seed; rng_bad<-do.call(gpg_smc,rng_args)
  ok(!rng_bad$complete && identical(before,.Random.seed) && grepl("RNG",rng_bad$failure))
  capped<-common;capped$limits<-list(max_horizon=2L,max_particles=16L,max_calls=2L)
  limited<-do.call(gpg_smc,capped)
  ok(!limited$complete && limited$callback_calls==2L && is.na(limited$normalizer_estimate) &&
    !limited$diagnostic_thresholds_passed && !limited$production_launch_authorized)
  bad_control<-common;bad_control$limits<-list(max_horizon=2L,max_particles=16L,max_calls=1000L,trust_flags=1L)
  reject(do.call(gpg_smc,bad_control))
  reject(gpg_affine_h2(binding,eta,unknown_future_truth=1))
  reject(gpg_smc(parameters,function(...)0,1,function(...)0,1,matrix(0,2,50),2L))
  # A one-horizon target always integrates its terminal Y1 prior exactly.
  one <- common;one$horizon<-1L;one$members<-G[1L,,drop=FALSE]
  one$guide<-function(...)stop("terminal guide must not run")
  h1 <- do.call(gpg_smc,one)
  ok(h1$complete && all(h1$diagnostics$guided_particles==0))
  near(h1$log_normalizer_estimate,sum(gic_al_log_density(G[1L,],
    binding$callbacks$member_location(1L,numeric(),parameters),.2,unname(parameters$sigma["G"]))))
  cat(sprintf("GLOFAS_GUIDED_COLLAPSED_PARTICLE_PASS checks=%d original_reads=0 application_fits=0\n",checks))
})
