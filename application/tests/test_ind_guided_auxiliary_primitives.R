# Independent synthetic integration checks. No retained fit or forecast read.
source("scripts/ind_conditional_filter_replay.R")
source("scripts/ind_guided_auxiliary_primitives.R")
gap_n <- 0L
gap_check <- function(ok) { stopifnot(isTRUE(ok)); gap_n <<- gap_n+1L }
gap_close <- function(x,y,tol=1e-9)isTRUE(all.equal(x,y,tolerance=tol,check.attributes=FALSE))
gap_reject <- function(expr)gap_check(inherits(tryCatch({force(expr);NULL},error=identity),"error"))
set.seed(91362);gap_seed <- .Random.seed
dal <- function(e,p,sigma) p*(1-p)/sigma*exp(-ifelse(e>=0,p*e,(p-1)*e)/sigma)
pal <- function(e,p,sigma) ifelse(e<0,p*exp((1-p)*e/sigma),1-(1-p)*exp(-p*e/sigma))

# Direct one-dimensional Gaussian convolution, split at its likelihood kink.
for(p in c(.05,.5,.95)) for(S in c(.1,1,7)) for(y in c(-3,.2,4)) {
  m <- .3;sigma <- .7
  f <- function(l)dnorm(l,m,sqrt(S))*dal(y-l,p,sigma)
  refd <- integrate(f,-Inf,y,abs.tol=1e-12,rel.tol=1e-11)$value+integrate(f,y,Inf,abs.tol=1e-12,rel.tol=1e-11)$value
  f <- function(l)dnorm(l,m,sqrt(S))*pal(y-l,p,sigma)
  refp <- integrate(f,-Inf,y,abs.tol=1e-12,rel.tol=1e-11)$value+integrate(f,y,Inf,abs.tol=1e-12,rel.tol=1e-11)$value
  a <- ind_gap_al_terms(y,m,S,p,sigma)
  gap_check(gap_close(exp(a$log_density),refd,1e-9))
  gap_check(gap_close(ind_gap_al_cdf(y,m,S,p,sigma),refp,1e-9))
  gap_check(gap_close(ind_gap_al_cdf(y,m,S,p,sigma)+
    ind_gap_al_cdf(y,m,S,p,sigma,lower.tail=FALSE),1,1e-12))
  eps <- 1e-5
  derivative <- (ind_gap_al_cdf(y+eps,m,S,p,sigma)-ind_gap_al_cdf(y-eps,m,S,p,sigma))/(2*eps)
  gap_check(gap_close(derivative,refd,1e-7))
}
for(p in c(.05,.5,.95)) {
  y <- c(-10,-1,0,1,10)
  gap_check(gap_close(ind_gap_al_cdf(y,0,0,p,.8),pal(y,p,.8),1e-12))
  gap_check(gap_close(exp(ind_gap_al_terms(y,0,0,p,.8)$log_density),dal(y,p,.8),1e-12))
  gap_check(gap_close(ind_gap_al_cdf(y,0,0,p,.8,lower.tail=FALSE),1-pal(y,p,.8),1e-12))
}
gap_check(identical(ind_gap_al_cdf(c(-Inf,Inf),0,1,.05,1),c(0,1)))
gap_check(identical(ind_gap_al_cdf(c(-Inf,Inf),0,1,.05,1,lower.tail=FALSE),c(1,0)))
gap_check(identical(ind_gap_al_terms(c(-Inf,Inf),0,1,.05,1)$log_density,c(-Inf,-Inf)))
for(p in c(.01,.05,.5,.95,.99)) {
  y <- c(-1e3,-100,-10,0,10,100,1e3)
  for(S in c(1e-8,1,1e6)) {
    cdf <- ind_gap_al_cdf(y,0,S,p,.01)
    gap_check(all(is.finite(cdf)) && all(cdf>=0 & cdf<=1) && all(diff(cdf)>=0))
    gap_check(!anyNA(ind_gap_al_cdf(y,0,S,p,.01,log.p=TRUE)))
    gap_check(gap_close(exp(ind_gap_al_cdf(y,0,S,p,.01,log.p=TRUE)),cdf,1e-11))
  }
}
gap_check(gap_close(ind_gap_al_cdf(2,1,3,.5,.7),1-ind_gap_al_cdf(0,1,3,.5,.7),1e-12))
gap_check(gap_close(ind_gap_log_mills(c(0,10,29,30,100)),
  pnorm(-c(0,10,29,30,100),log.p=TRUE)+.5*c(0,10,29,30,100)^2,1e-10))

# Exact proposal density identity: p(v)*Normal(y;m+A*v,S+B*sigma*v)/g(y).
# Numerical integration checks its first two moments independently; deterministic
# midpoint-uniform designs exercise allfour inverse transforms without RNG.
N <- 12000L
u1 <- (seq_len(N)-.5)/N
u <- cbind(u1,((seq_len(N)*7919L)%%N+.5)/N,
  ((seq_len(N)*3571L)%%N+.5)/N,((seq_len(N)*4967L)%%N+.5)/N)
for(p in c(.05,.5,.95)) {
  sigma <- .7;m <- .3;S <- .8;y <- -.4
  draws <- vapply(seq_len(N),function(i)ind_gap_propose(y,m,S,p,sigma,u[i,])$v,numeric(1L))
  A <- (1-2*p)/(p*(1-p)); B <- 2/(p*(1-p));g <- exp(ind_gap_al_terms(y,m,S,p,sigma)$log_density)
  f <- function(v) dexp(v,rate=1/sigma)*dnorm(y,m+A*v,sqrt(S+B*sigma*v))/g
  refnorm <- integrate(f,0,Inf,abs.tol=1e-12,rel.tol=1e-11)$value
  refmean <- integrate(function(v)v*f(v),0,Inf,abs.tol=1e-12,rel.tol=1e-11)$value
  refsecond <- integrate(function(v)v*v*f(v),0,Inf,abs.tol=1e-12,rel.tol=1e-11)$value
  gap_check(gap_close(refnorm,1,1e-9))
  gap_check(abs(mean(draws)-refmean)<.02*max(1,refmean))
  gap_check(abs(mean(draws^2)-refsecond)<.04*max(1,refsecond))
  gap_check(all(is.finite(draws)) && all(draws>0))
}

for(uu in list(c(.1,.2,.3,.4),c(.9,.8,.7,.6))) {
  a <- ind_gap_propose(.4,.1,.8,.05,.7,uu)
  gap_check(a$ex_q>0 && a$v>0 && is.finite(a$temporary_L))
  gap_check(a$random_draws_generated==0L && !a$production_authorized)
  gap_check(a$temporary_L_role=="proposal_only_discard_before_state_update")
  gap_check(identical(a,ind_gap_propose(.4,.1,.8,.05,.7,uu)))
}
# Zero residual has the Gamma half limit; no changingchi to an arbitraryepsilon.
uu <- c(.2,.4,.8,.7)
a <- ind_gap_propose(0,0,0,.5,1,uu)
psi <- 2
gap_check(gap_close(a$v,qchisq(uu[3L],1)/psi,1e-12))
gap_check(a$temporary_L==0 && a$proposal_component=="degenerate_Gaussian")
gap_check(ind_gap_gig_half(0,1,.5,.3)>0)
for(chi in c(0,.2,10)) {
  # Deterministic GIG-half moment checks against the analytic mean
  # E[V]=sqrt(chi/psi)+1/psi, valid also atchi0.
  ps <- 3
  v <- vapply(seq_len(N),function(i)ind_gap_gig_half(chi,ps,u[i,3],u[i,4]),numeric(1L))
  gap_check(abs(mean(v)-(sqrt(chi/ps)+1/ps))<.02*max(1,sqrt(chi/ps)+1/ps))
}

for(gamma in c(-.2,0,.2)) {
  p <- .5;sigma <- .7;s <- .4;y <- .3
  x <- ind_gap_exal_propose(y,.1,.8,p,sigma,gamma,s,uu)
  ob <- ind_cfr_augmentation("exal",p,sigma,1,s,gamma)
  r <- ob$native_r;A <- (1-2*r)/(r*(1-r));shift <- ob$ex_f-A
  z <- ind_gap_propose(y-shift,.1,.8,r,sigma,uu)
  gap_check(gap_close(x$ex_f,z$ex_f+shift))
  gap_check(identical(x$ex_q,z$ex_q) && identical(x$v,z$v))
  gap_check(identical(x$log_predictive_density,z$log_predictive_density))
  ec <- ind_gap_exal_cdf(y,.1,.8,p,sigma,gamma,1e-9,1e-8)
  if(gamma==0)gap_check(gap_close(ec$value,ind_gap_al_cdf(y,.1,.8,p,sigma),1e-12)) else {
    # Independent two-auxiliary numerical mixtureCDF, v then s. TheNormal
    # state is integrated but no Normal+ALanalyticCDF is used in thisreference.
    B <- 2/(r*(1-r));shift_unit <- shift/s
    ref <- integrate(function(ss)vapply(ss,function(st) {
      integrate(function(v)dexp(v,rate=1/sigma)*
        pnorm(y,.1+A*v+shift_unit*st,sqrt(.8+B*sigma*v)),0,Inf,
        abs.tol=1e-8,rel.tol=1e-7)$value * 2*dnorm(st)
    },numeric(1L)),0,Inf,abs.tol=1e-7,rel.tol=1e-7)$value
    gap_check(gap_close(ec$value,ref,3e-7))
    gap_check(ec$absolute_error<=max(1e-9,1e-8*abs(ec$value)))
  }
  gap_check(!ec$production_authorized)
}

# Weighted origin mixture remainsaCDF mixture, notanaverageofquantiles.
m <- c(-2,1,5);S <- c(.2,.8,1.2);w <- c(.2,.5,.3)
y <- c(-Inf,-3,0,3,10,Inf)
ref <- vapply(y,function(v)sum(w*vapply(seq_along(m),function(j)
  ind_gap_al_cdf(v,m[j],S[j],.25,.5),numeric(1L))),numeric(1L))
gap_check(gap_close(ind_gap_mixture_cdf(y,m,S,.25,.5,w),ref,1e-12))
gap_check(gap_close(ind_gap_mixture_cdf(y,m,S,.25,.5,w*1e300),ref,1e-12))
pp <- c(.05,.25,.5,.75,.95)
q <- ind_gap_mixture_quantile(pp,m,S,.25,.5,w,1e-9,1e-11)
gap_check(all(q$result$cdf_lower<=pp & q$result$cdf_upper>=pp))
gap_check(all(q$result$upper-q$result$lower<=q$result$width_tolerance))
gap_check(all(diff(q$result$quantile)>0) && !q$production_authorized && !q$origin_filter_accuracy_qualified)
refq <- ind_gap_mixture_quantile(pp,1,0,.25,.5,1,1e-9)
qal <- function(p)ifelse(p<.25,.5/.75*log(p/.25),-.5/.25*log((1-p)/.75))
gap_check(gap_close(refq$result$quantile,1+qal(pp),1e-8))

for(expr in list(
 quote(ind_gap_al_cdf(0,0,-1,.5,1)),quote(ind_gap_al_cdf(0,0,1,0,1)),
 quote(ind_gap_al_cdf(0,0,1,.5,0)),quote(ind_gap_al_cdf(c(0,1,2),c(0,1),1,.5,1)),
 quote(ind_gap_al_cdf(NA_real_,0,1,.5,1)),quote(ind_gap_gig_half(-1,1,.2,.3)),
 quote(ind_gap_gig_half(1,0,.2,.3)),quote(ind_gap_gig_half(0,1,0,.3)),
 quote(ind_gap_propose(0,0,1,.5,1,c(.2,.3,.4,1))),
 quote(ind_gap_propose(0,0,1,.5,1,c(.2,.3))),
 quote(ind_gap_exal_propose(0,0,1,.05,1,100,.3,uu)),
 quote(ind_gap_exal_cdf(0,0,1,.5,1,.2,0)),
 quote(ind_gap_mixture_cdf(0,m,S,.5,1,c(0,0,0))),
 quote(ind_gap_mixture_quantile(0,m,S,.5,1,w,1e-9)),
 quote(ind_gap_mixture_quantile(.5,m,S,.5,1,w,0)),
 quote(ind_gap_mixture_quantile(.5,m,S,.5,1,w,1e-16,0,1))
))gap_reject(eval(expr))
gap_check(identical(.Random.seed,gap_seed))
cat(sprintf("IND_GUIDED_AUXILIARY_PRIMITIVE_CHECKS=%d PASS; protected_reads=0 fits=0 production_launches=0\n",gap_n))
