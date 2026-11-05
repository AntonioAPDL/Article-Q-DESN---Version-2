# Generated pCN balance, RNG, adaptation and incomplete-state checks only.
local({
  source("scripts/diagnostics/glofas_innovation_sampler.R", local = TRUE)
  source("scripts/diagnostics/glofas_innovation_coordinates.R", local = TRUE)
  n <- 0L
  ok <- function(value) {stopifnot(isTRUE(value)); n <<- n + 1L}
  reject <- function(expr) {e <- tryCatch({force(expr); NULL}, error = identity); ok(inherits(e,"error"))}
  ctl <- list(warmup=100L,samples=1000L,max_evaluations=1101L,max_wall_seconds=60,
    delta_initial=.5,delta_min=.001,delta_max=.9,target_accept=.234,adapt_warmup=TRUE,
    seeds=as.numeric(2026110501:2026110504),progress_every=100L,
    rhat_max=1.01,min_ess=400,max_quantile_mcse=.001)
  for (d in c(.01,.2,.8)) for (x in c(-2,.3,4)) for (y in c(-1,.7,3)) {
    a <- stats::dnorm(x,log=TRUE)+gis_pcn_log_proposal(y,x,d)
    b <- stats::dnorm(y,log=TRUE)+gis_pcn_log_proposal(x,y,d)
    ok(abs(a-b)<1e-8)
    ll <- function(z) -.5*(z-1)^2/.4
    ok(abs((b+ll(y))-(a+ll(x))-(ll(y)-ll(x)))<1e-8)
  }
  # Compose the AL Jacobian and the actual member-only acceptance ratio.
  # This guards against inadvertently counting the Normal base twice.
  transformed_target <- function(z) gic_al_member_target(z,parameters=.3,
    location=function(h,past,b) b + if(length(past)) .2*tail(past,1) else 0,
    scale=.4,probability=.05,members=matrix(seq(-.2,.4,length.out=102),2,51),
    member_location=function(h,path,b) b+.1*path[h],member_scale=.3,log_historical=0)
  x <- c(-.3,.7); y <- c(.2,-.1); tx <- transformed_target(x); ty <- transformed_target(y)
  logx <- tx$transformed$log_path_density + tx$log_member_likelihood + tx$transformed$log_abs_jacobian
  logy <- ty$transformed$log_path_density + ty$log_member_likelihood + ty$transformed$log_abs_jacobian
  ratio <- ty$log_member_likelihood-tx$log_member_likelihood
  ok(abs(logx+gis_pcn_log_proposal(y,x,.3)+min(0,ratio)-
    (logy+gis_pcn_log_proposal(x,y,.3)+min(0,-ratio)))<1e-10)
  old_kind <- RNGkind(); set.seed(641L); old <- .Random.seed
  zero <- function(z) list(path=z,log_likelihood=0)
  progress <- list()
  a <- gis_sample_chain(zero,c(0,.5),ctl,1L,function(x) progress[[length(progress)+1L]] <<- x)
  ok(identical(old,.Random.seed)&&identical(old_kind,RNGkind()))
  b <- gis_sample_chain(zero,c(0,.5),ctl,1L)
  deterministic <- function(x) {x$elapsed_seconds <- NULL; x}
  ok(identical(deterministic(a),deterministic(b)))
  ok(isTRUE(a$fully_completed)); ok(a$callback_evaluations==1101L)
  ok(a$accepted_warmup==100L&&a$accepted_retained==1000L)
  ok(identical(a$frozen_delta,a$final_delta)&&a$frozen_delta<=ctl$delta_max)
  ok(length(progress)==11L&&isTRUE(tail(progress,1)[[1]]$fully_completed))
  ok(!a$reference_qualified&&!a$full_posterior_accuracy_qualified&&!a$production_launch_authorized)
  # Progress must consume no RNG; path draws and final RNG remain identical.
  ok(identical(a$draws,b$draws)&&identical(a$final_rng_state,b$final_rng_state))
  ctl2 <- ctl; ctl2$adapt_warmup <- FALSE; ctl2$warmup <- 2000L
  ctl2$samples <- 12000L; ctl2$max_evaluations <- 14001L
  v <- gis_sample_chain(zero,c(0,0),ctl2,2L)
  ok(max(abs(colMeans(v$draws)))<.20)
  ok(max(abs(apply(v$draws,2,stats::var)-1))<.25)
  ok(abs(stats::cor(v$draws[-1,1],v$draws[-nrow(v$draws),1])-sqrt(1-.5^2))<.04)
  # A nonconstant generated likelihood exercises the actual MH rejection.
  c <- gis_sample_chain(function(z) list(path=z,log_likelihood=-20*sum((z-.7)^2)),c(0,0),ctl,3L)
  ok(c$accepted_retained>0L&&c$accepted_retained<ctl$samples)
  ok(max(abs(colMeans(c$draws)-40*.7/41))<.12)
  # Exhaustion preserves a partial state; no implicit extension or resume.
  k <- 0L
  partial <- gis_sample_chain(function(z) {k<<-k+1L
    if(k==10L) gis_require(FALSE,"generated budget stop","gis_budget_exhausted")
    zero(z)}, c(0,0),ctl,4L)
  ok(identical(partial$status,"INCONCLUSIVE_BUDGET_LIMITED"))
  ok(!partial$fully_completed&&partial$retained_iterations==0L&&all(is.na(partial$draws)))
  ok(!partial$exact_resume_qualified)
  # A terminal progress failure does not turn a failed chain into success.
  failed_progress <- gis_sample_chain(zero,c(0,0),ctl,1L,function(x) {
    if (isTRUE(x$fully_completed)) stop("generated terminal progress failure")
  })
  ok(!failed_progress$fully_completed && failed_progress$retained_iterations==ctl$samples)
  ok(identical(failed_progress$status,"FAILED_OR_PARTIAL_CHAIN_NOT_PROMOTABLE"))
  parts <- lapply(1:4,function(i) {z<-a;z$chain_id<-i;z$seed<-as.integer(ctl$seeds[i]);z})
  parts[[1]] <- failed_progress
  combined <- gis_combine_chains(parts,list(horizon=2L),ctl)
  ok(identical(combined$status,"PILOT_PARTIAL_RETAINED_NOT_PROMOTABLE") &&
    !combined$diagnostic_thresholds_passed && !combined$reference_qualified)
  # Check the declared per-chain wall budget after, not only before, callbacks.
  tiny <- ctl; tiny$max_wall_seconds <- .001
  exhausted <- gis_sample_chain(function(z) {Sys.sleep(.01); zero(z)},c(0,0),tiny,1L)
  ok(!exhausted$fully_completed && exhausted$callback_evaluations==1L &&
    identical(exhausted$status,"INCONCLUSIVE_BUDGET_LIMITED"))
  bad <- ctl; bad$delta_initial <- 1; reject(gis_validate_control(bad))
  bad <- ctl; bad$seeds[2] <- bad$seeds[1]; reject(gis_validate_control(bad))
  bad <- ctl; bad$max_evaluations <- 1; reject(gis_validate_control(bad))
  reject(gis_sample_chain(zero,c(0,0),ctl,5L))
  reject(gis_combine_chains(list(a,b),list(horizon=2L),ctl))
  cat(sprintf("GLOFAS_INNOVATION_SAMPLER_GENERATED_PASS checks=%d original_reads=0 production_qualified=FALSE\n",n))
})
