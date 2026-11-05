# Controlled H1 shared-scale references only, not native application evidence.
local({
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_optimizer_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_optimizer_predictive_reference.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L }
  reject <- function(expr) ok(inherits(try(force(expr), silent = TRUE), "try-error"))
  scalar_al <- function(y, mu, sigma, p) {
    e <- (y - mu) / sigma
    ifelse(e < 0, p * exp((1-p)*pmin(e,0)), 1-(1-p)*exp(-p*pmax(e,0)))
  }
  # Independent split-Normal location integration checks the convolution.
  for (p in c(.2,.5,.8)) for (scale in c(.01,.2,2)) {
    y <- c(-.3,.1,.7); m <- .1; s <- .2
    direct <- vapply(y, function(value) {
      integrand <- function(theta) scalar_al(value,theta,scale,p)*stats::dnorm(theta,m,s)
      stats::integrate(integrand,-Inf,value,rel.tol=1e-10)$value +
        stats::integrate(integrand,value,Inf,rel.tol=1e-10)$value
    }, numeric(1L))
    calculated <- gopr_normal_al_cdf(y,m,s,scale,p)
    ok(max(abs(direct-calculated)) < 2e-10)
  }
  x <- c(8,12,30,100)
  literal_mills <- stats::pnorm(-x,log.p=TRUE)-stats::dnorm(x,log=TRUE)
  ok(max(abs(gopr_log_mills_positive(x)-literal_mills)) < 2e-12)
  grid <- c(-2,-.5,0,1,3)
  ok(max(abs(gopr_normal_al_cdf(grid,0,1,1e-200,.2)-stats::pnorm(grid))) < 1e-10)
  y <- c(-.1,.12,.3)
  ok(max(abs(gopr_normal_al_cdf(y,.12,1e-10,.07,.2)-scalar_al(y,.12,.07,.2))) < 1e-8)
  ok(identical(gopr_normal_al_cdf(c(-Inf,Inf),.1,.2,.1,.2),c(0,1)))
  ok(max(abs(gopr_normal_al_cdf(y,.12,0,.07,.2)-scalar_al(y,.12,.07,.2))) < 1e-14)
  extreme <- gopr_normal_al_cdf(c(-1e308,0,1e308),0,1e-12,1e-320,.2)
  ok(all(is.finite(extreme)) && extreme[1L]==0 && extreme[3L]==1)

  # Independent split theta/eta integration, including theta/eta covariance.
  m <- c(.12,-2.3); ls <- c(-2.7,-.8)
  L <- matrix(c(1,.3,-.2,1),2L)
  q <- gcpor_gaussian_contract(m,ls,L); V <- q$covariance
  conditional_sd <- sqrt(V[1L,1L]-V[1L,2L]^2/V[2L,2L])
  double <- function(y) stats::integrate(function(zeta) vapply(zeta,function(z) {
    eta <- m[2L]+sqrt(V[2L,2L])*z
    mu <- m[1L]+V[1L,2L]/sqrt(V[2L,2L])*z
    cut <- (y-mu)/conditional_sd
    f <- function(e) scalar_al(y,mu+conditional_sd*e,exp(eta),.2)*stats::dnorm(e)
    inner <- stats::integrate(f,-Inf,cut,rel.tol=1e-8)$value +
      stats::integrate(f,cut,Inf,rel.tol=1e-8)$value
    inner*stats::dnorm(z)
  },numeric(1L)),-9,9,rel.tol=1e-7)$value
  for (value in c(-.1,.12,.4)) {
    direct <- double(value)
    approx32 <- gopr_gaussian_predictive_cdf(value,m,ls,L,32L,.2)
    approx64 <- gopr_gaussian_predictive_cdf(value,m,ls,L,64L,.2)
    ok(abs(approx64-direct)<2e-7 && abs(approx64-approx32)<1e-8)
  }
  # Common positive affine transformation shifts theta/response and scales AL.
  a <- .3; b <- 2
  transformed_mean <- c(a+b*m[1L],log(b)+m[2L])
  transformed_L <- diag(c(b,1))%*%L
  ok(max(abs(gopr_gaussian_predictive_cdf(a+b*c(-.1,.12,.4),transformed_mean,ls,
    transformed_L,64L,.2)-gopr_gaussian_predictive_cdf(c(-.1,.12,.4),m,ls,L,64L,.2))) < 1e-12)
  levels <- c(.05,.2,.5,.8,.95)
  cdf <- function(y) gopr_normal_al_cdf(y,.1,.2,.07,.2)
  quants <- vapply(levels,function(p)gopr_quantile(cdf,p,.1,.01),numeric(1L))
  ok(all(diff(quants)>0) && max(abs(cdf(quants)-levels))<1e-9)
  reject(gopr_normal_al_cdf(0,0,-1,.1))
  reject(gopr_normal_al_cdf(0,0,1,0))
  reject(gopr_gaussian_predictive_cdf(0,m,ls,L,48L,.2))
  reject(gopr_quantile(function(x) .5,.2,0,1,max_expansions=2L))
  reject(gopr_quantile(function(x) 2,.2,0,1))
  reject(gopr_assess_h1(probability=.5))

  # All prespecified fixtures are retained, whether predictive gates pass or
  # fail. Parameter-family discrepancies are not used as a predictive veto.
  cases <- list(no_members=numeric(),moderate_51=seq(-.3,.7,length.out=51L),
    concentrated_51=rep(.2,51L))
  for (name in names(cases)) {
    assessment <- gopr_assess_h1(cases[[name]])
    ok(identical(assessment$quantiles$probability,levels) &&
      identical(assessment$gates$primary_quantile_absolute_error,.001) &&
      identical(assessment$gates$maximum_grid_CDF_error,.01))
    ok(all(is.finite(c(assessment$quantiles$absolute_error,assessment$maximum_grid_CDF_error,
      assessment$parameter_variance$ratio,assessment$reference_family_KL))))
    ok(assessment$member_count==length(cases[[name]]) &&
      assessment$predictive_gates_passed == (assessment$primary_quantile_absolute_error<=.001 &&
      assessment$maximum_grid_CDF_error<=.01 && assessment$quadrature_comparison_passed))
    ok(!assessment$full_posterior_accuracy_qualified && !assessment$production_qualified &&
      !assessment$native_launch_authorized && !assessment$publication_authorized &&
      assessment$original_reads==0L && assessment$application_fits==0L)
  }
  correlated_fit <- list(mean=m,log_sd=ls,covariance=V,
    value=gcpor_h1_elbo(m,ls,L,members=numeric(),probability=.2)$value)
  correlated_assessment <- gopr_assess_h1(fit=correlated_fit)
  ok(abs(correlated_assessment$theta_log_sigma_covariance_q-V[1L,2L])<1e-12 &&
    max(abs(correlated_assessment$parameter_variance$Gaussian_q-diag(V)))<1e-12)
  corrupted_fit <- correlated_fit; corrupted_fit$factor <- diag(2L)
  reject(gopr_assess_h1(fit=corrupted_fit))
  fake_objective <- correlated_fit; fake_objective$value <- fake_objective$value+100
  retained <- gopr_assess_h1(fit=fake_objective)
  ok(abs(retained$Gaussian_family_ELBO-correlated_assessment$Gaussian_family_ELBO)<1e-12 &&
    abs(retained$reference_family_KL-correlated_assessment$reference_family_KL)<1e-12 &&
    abs(retained$supplied_fit_ELBO_discrepancy-100)<1e-10 &&
    identical(retained$predictive_gates_passed,correlated_assessment$predictive_gates_passed))
  cat(sprintf("GLOFAS_OPTIMIZER_PREDICTIVE_REFERENCE_PASS checks=%d original_reads=0 application_fits=0\n",checks))
})
