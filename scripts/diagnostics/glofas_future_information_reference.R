# Generated no-new-information references. No original data, RDS, callbacks,
# fitting entry point, scientific scheduler or production implementation here.

gfir_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("Future information reference: ", message), call. = FALSE)
}
gfir_norm <- function(x) sqrt(sum(as.numeric(x)^2))
gfir_integrate <- function(fun, lower = 0, upper = Inf) {
  a <- stats::integrate(fun, lower, upper, rel.tol = 1e-10, abs.tol = 1e-12, subdivisions = 600L)
  b <- stats::integrate(fun, lower, upper, rel.tol = 1e-12, abs.tol = 1e-13, subdivisions = 1000L)
  list(value = b$value, tightening_difference = abs(a$value-b$value), estimated_error = b$abs.error)
}

gfir_normal_contract <- function(horizon = 2L, unknown_scale = TRUE) {
  gfir_require(length(horizon)==1L && horizon %in% 1:2 && is.logical(unknown_scale) &&
    length(unknown_scale)==1L && !is.na(unknown_scale), "one/two-horizon generated contract required")
  H <- as.integer(horizon); L <- diag(H)
  if (H==2L) L[2,1] <- -.3
  X <- rbind(c(1,.4),c(.8,-.6))[seq_len(H),,drop=FALSE]
  Li <- solve(L)
  list(H=H,L=L,X=X,F=Li%*%X,M=tcrossprod(Li),
    mean0=c(.4,-.3),covariance0=matrix(c(1,.2,.2,.7),2,2),
    unknown_scale=unknown_scale,a=3,b=2,fixed_variance=.8,
    scale_role="Normal observation variance, not AL scale",ensemble_factors=0L)
}

gfir_normal_mf_reference <- function(contract) {
  c <- contract; Q0 <- solve(c$covariance0); XX <- crossprod(c$X)
  get_cov <- function(k) solve(Q0+k*XX)
  k <- if (c$unknown_scale) {
    stats::uniroot(function(k) c$b*k+.5*k*sum(diag(c$X%*%get_cov(k)%*%t(c$X)))-c$a,
      c(.Machine$double.eps,c$a/c$b),tol=1e-13)$root
  } else 1/c$fixed_variance
  shape <- if(c$unknown_scale)c$a+c$H/2 else NA_real_
  list(theta_mean=c$mean0,theta_covariance=get_cov(k),future_mean=as.numeric(c$F%*%c$mean0),
    future_covariance=c$M/k,precision_mean=k,scale_shape=shape,
    scale_rate=if(c$unknown_scale)shape/k else NA_real_)
}

gfir_normal_mf_prototype <- function(contract, max_iter = 3000L, tol = 1e-12) {
  c <- contract; Q0 <- solve(c$covariance0); XX <- crossprod(c$X)
  mt <- c$mean0+.2; St <- c$covariance0; my <- rep(-.2,c$H); Vy <- diag(c$H)
  shape <- c$a; rate <- c$b
  k <- if(c$unknown_scale)shape/rate else 1/c$fixed_variance
  old <- c(mt,St,my,Vy,k); converged <- FALSE
  for(i in seq_len(max_iter)) {
    St <- solve(Q0+k*XX)
    mt <- as.numeric(St%*%(Q0%*%c$mean0+k*crossprod(c$X,c$L%*%my)))
    my <- as.numeric(c$F%*%mt); Vy <- c$M/k
    if(c$unknown_scale) {
      e <- as.numeric(c$L%*%my-c$X%*%mt)
      shape <- c$a+c$H/2
      rate <- c$b+.5*(sum(e^2)+sum(diag(c$L%*%Vy%*%t(c$L)))+
        sum(diag(c$X%*%St%*%t(c$X))))
      k <- shape/rate
    }
    now <- c(mt,St,my,Vy,k)
    if(max(abs(now-old))<tol) {converged<-TRUE;break}
    old <- now
  }
  list(theta_mean=mt,theta_covariance=St,future_mean=my,future_covariance=Vy,
    precision_mean=k,scale_shape=if(c$unknown_scale)shape else NA_real_,
    scale_rate=if(c$unknown_scale)rate else NA_real_,iterations=i,converged=converged)
}

gfir_normal_exact_cdf <- function(y, contract, h = contract$H) {
  c <- contract; gfir_require(h %in% seq_len(c$H),"valid generated horizon required")
  mu <- sum(c$F[h,]*c$mean0)
  coefficient_variance <- as.numeric(c$F[h,,drop=FALSE]%*%c$covariance0%*%c$F[h,])
  noise <- c$M[h,h]
  if(!c$unknown_scale) return(list(value=stats::pnorm(y,mu,
    sqrt(coefficient_variance+noise*c$fixed_variance)),tightening_difference=0,estimated_error=0))
  # Integrate the Gamma precision density. The Normal coefficient integral is
  # analytic, so coefficient uncertainty is retained rather than set to a mean.
  gfir_integrate(function(u) stats::pnorm((y-mu)/sqrt(coefficient_variance+noise/u))*
    stats::dgamma(u,shape=c$a,rate=c$b))
}

gfir_conditional_log_gap <- function(y, theta, variance, contract) {
  c <- contract; gfir_require(length(y)==c$H&&length(theta)==ncol(c$X)&&
    is.finite(variance)&&variance>0,"valid generated conditional arguments required")
  # Independent implementations: structural innovation product versus a full
  # Gaussian conditional block with the corresponding non-diagonal covariance.
  innovations <- as.numeric(c$L%*%y-c$X%*%theta)
  target <- sum(stats::dnorm(innovations,0,sqrt(variance),log=TRUE))
  delta <- y-as.numeric(c$F%*%theta); V <- variance*c$M; C <- chol(V)
  block <- -.5*(c$H*log(2*pi)+2*sum(log(diag(C)))+
    sum(forwardsolve(t(C),delta)^2))
  target-block
}

gfir_joint_block_kl <- function(theta, variance, future_mean, future_covariance, contract) {
  c <- contract; P <- solve(variance*c$M)
  delta <- as.numeric(c$F%*%theta)-future_mean
  .5*(sum(P*t(future_covariance))+as.numeric(crossprod(delta,P%*%delta))-c$H+
    as.numeric(determinant(variance*c$M,logarithm=TRUE)$modulus)-
    as.numeric(determinant(future_covariance,logarithm=TRUE)$modulus))
}

gfir_normal_transition_integral <- function(theta, variance, contract) {
  c <- contract; mu <- as.numeric(c$X%*%theta); sd <- sqrt(variance)
  if(c$H==1L) return(gfir_integrate(function(y)stats::dnorm(y,mu[1],sd),-Inf,Inf))
  # Integrate in response coordinates, not the innovation-coordinate oracle.
  gfir_integrate(function(y1) vapply(y1,function(a) {
    stats::dnorm(a,mu[1],sd)*stats::integrate(function(y2)
      stats::dnorm(y2,.3*a+mu[2],sd),-Inf,Inf,rel.tol=1e-10,abs.tol=1e-12)$value
  },numeric(1L)),-Inf,Inf)
}

gfir_al_cdf <- function(y,p,sigma=1) {
  gfir_require(length(p)==1L&&is.finite(p)&&p>0&&p<1&&
    length(sigma)==1L&&is.finite(sigma)&&sigma>0,"valid fixed AL parameters required")
  u <- as.numeric(y)/sigma
  ifelse(u<0,p*exp((1-p)*u),1-(1-p)*exp(-p*u))
}

gfir_al_intercept_reference <- function(p,sigma=.7,mean0=.4,variance0=1.1) {
  gfir_al_cdf(0,p,sigma)
  A<-(1-2*p)/(p*(1-p));B<-2/(p*(1-p))
  Vt<-function(lambda)1/(1/variance0+lambda/(B*sigma))
  lambda<-stats::uniroot(function(lambda)lambda+lambda^2*Vt(lambda)/(B*sigma)-2/sigma,
    c(.Machine$double.eps,2/sigma),tol=1e-13)$root
  list(theta_mean=mean0,theta_variance=Vt(lambda),future_mean=mean0+A/lambda,
    future_variance=B*sigma/lambda,lambda=lambda,A=A,B=B,
    exact_theta_variance=variance0,scale_role="fixed AL scale")
}

gfir_al_intercept_prototype <- function(p,sigma=.7,mean0=.4,variance0=1.1,
                                        max_iter=5000L,tol=1e-12) {
  A<-(1-2*p)/(p*(1-p));B<-2/(p*(1-p))
  mt<-mean0+.1;Vt<-variance0;my<--.2;Vy<-.6;lambda<-1/sigma
  old<-c(mt,Vt,my,Vy,lambda);converged<-FALSE
  for(i in seq_len(max_iter)) {
    Vt<-1/(1/variance0+lambda/(B*sigma))
    mt<-Vt*(mean0/variance0+(lambda*my-A)/(B*sigma))
    my<-mt+A/lambda;Vy<-B*sigma/lambda
    R<-(my-mt)^2+Vt+Vy
    lambda<-sqrt((A^2+2*B)/R)
    now<-c(mt,Vt,my,Vy,lambda)
    if(max(abs(now-old))<tol){converged<-TRUE;break};old<-now
  }
  list(theta_mean=mt,theta_variance=Vt,future_mean=my,future_variance=Vy,
    lambda=lambda,iterations=i,converged=converged)
}

gfir_al_intercept_cdf <- function(y,p,sigma=.7,mean0=.4,variance0=1.1) {
  fun<-function(theta)stats::dnorm(theta,mean0,sqrt(variance0))*gfir_al_cdf(y-theta,p,sigma)
  left<-gfir_integrate(fun,-Inf,y);right<-gfir_integrate(fun,y,Inf)
  list(value=left$value+right$value,
    tightening_difference=left$tightening_difference+right$tightening_difference,
    estimated_error=left$estimated_error+right$estimated_error)
}

gfir_al_scale_reference <- function(p,horizon=1L,a=3,b=2) {
  gfir_al_cdf(0,p)
  gfir_require(horizon %in% 1:2&&a>2&&b>0,"generated scale prior requires a>2,b>0,H=1/2")
  A<-(1-2*p)/(p*(1-p));B<-2/(p*(1-p));k<-a/b
  L<-diag(as.integer(horizon));if(horizon==2L)L[2,1]<- -.3
  Li<-solve(L);shape<-a+1.5*horizon;rate<-b*shape/a
  list(A=A,B=B,precision_mean=k,lambda=2*k,
    future_mean=as.numeric(Li%*%rep(A/(2*k),horizon)),
    future_covariance=B/(2*k^2)*tcrossprod(Li),
    prior_shape=a,prior_rate=b,scale_shape=shape,scale_rate=rate,
    exact_scale_mean=b/(a-1),mf_scale_mean=rate/(shape-1),
    exact_inverse_scale_mean=a/b,mf_inverse_scale_mean=shape/rate,
    scale_role="AL scale, not Normal variance",L=L)
}

gfir_al_scale_prototype <- function(p,horizon=1L,a=3,b=2,max_iter=5000L,tol=1e-12) {
  ref<-gfir_al_scale_reference(p,horizon,a,b);A<-ref$A;B<-ref$B;L<-ref$L;Li<-solve(L)
  H<-as.integer(horizon);k<-a/b;lambda<-rep(1,H);ev<-rep(1,H)
  old<-c(k,lambda,ev);converged<-FALSE
  for(i in seq_len(max_iter)) {
    precision<-k/B*crossprod(L,L*lambda)
    covariance<-solve(precision)
    mean<-as.numeric(covariance%*%(k*A/B*crossprod(L,rep(1,H))))
    e<-as.numeric(L%*%mean);R<-e^2+diag(L%*%covariance%*%t(L))
    chi<-k*R/B;psi<-rep(k*(A^2/B+2),H)
    lambda<-sqrt(psi/chi);ev<-sqrt(chi/psi)+1/psi
    shape<-a+1.5*H
    rate<-b+sum(ev+(lambda*R-2*A*e+A^2*ev)/(2*B))
    k<-shape/rate
    now<-c(k,lambda,ev)
    if(max(abs(now-old))<tol){converged<-TRUE;break};old<-now
  }
  list(precision_mean=k,lambda=lambda,future_mean=mean,future_covariance=covariance,
    scale_shape=shape,scale_rate=rate,iterations=i,converged=converged)
}

gfir_al_scale_mixture_cdf <- function(y,p,a=3,b=2) {
  # One-step exact marginal: integrate over the Gamma inverse-AL-scale prior.
  gfir_integrate(function(u) {
    z<-y*u
    f<-ifelse(z<0,p*exp((1-p)*z),1-(1-p)*exp(-p*z))
    f*stats::dgamma(u,a,rate=b)
  })
}

gfir_al_augmented_conditional_log_gap <- function(y,v,theta,sigma,p,contract) {
  c<-contract;gfir_al_cdf(0,p,sigma)
  gfir_require(length(y)==c$H&&length(v)==c$H&&all(is.finite(c(y,v,theta)))&&
    all(v>0)&&length(theta)==ncol(c$X),"valid generated full-future conditional required")
  A<-(1-2*p)/(p*(1-p));B<-2/(p*(1-p))
  residual<-as.numeric(c$L%*%y-c$X%*%theta)
  # Target: product of conditional Normal and Exponential densities.
  target<-sum(stats::dexp(v,rate=1/sigma,log=TRUE)+
    stats::dnorm(residual,A*v,sqrt(B*sigma*v),log=TRUE))
  # Conditional variational block: independent unit exponentials and standard
  # normals transformed to (v,Y). det(L)=1; all parameter-dependent Jacobian
  # factors must be retained. This is not an independent q(Y,v) block.
  s<-v/sigma;z<-(residual-A*v)/sqrt(B*sigma*v)
  block<-sum(-s+stats::dnorm(z,log=TRUE))-c$H*log(sigma)-.5*sum(log(B*sigma*v))
  target-block
}

gfir_run_information_diagnostics <- function() {
  checks<-list();cases<-list()
  record<-function(id,error,tolerance,accuracy_error=NA_real_,accuracy_tolerance=.005,detail="") {
    checks[[length(checks)+1L]]<<-data.frame(test_id=id,reference_validity="PASS",
      implementation_parity=if(is.finite(error)&&error<=tolerance)"PASS"else"FAIL",
      numerical_stability=if(is.finite(error))"PASS"else"FAIL",
      approximation_accuracy=if(is.na(accuracy_error))"NOT_ASSESSED"else
        if(accuracy_error<=accuracy_tolerance)"PASS"else"FAIL",
      production_relevance="generated_uncertain_parameter_reference_not_production_qualification",
      error=error,tolerance=tolerance,approximation_error=accuracy_error,detail=detail,
      stringsAsFactors=FALSE)
  }
  for(H in 1:2)for(unknown in c(FALSE,TRUE)) {
    c<-gfir_normal_contract(H,unknown);ref<-gfir_normal_mf_reference(c);mf<-gfir_normal_mf_prototype(c)
    id<-paste0("normal_h",H,"_",if(unknown)"unknown_variance"else"fixed_variance")
    err<-max(abs(c(mf$theta_mean-ref$theta_mean,mf$theta_covariance-ref$theta_covariance,
      mf$future_mean-ref$future_mean,mf$future_covariance-ref$future_covariance,
      mf$precision_mean-ref$precision_mean)))
    if(!mf$converged)err<-Inf
    record(paste0(id,"_mf_equations"),err,1e-9,
      gfir_norm(mf$theta_covariance-c$covariance0)/gfir_norm(c$covariance0),1e-3,
      "Algorithm parity uses the mean-field reference; target accuracy requires unchanged parameter marginal.")
    for(p in c(.05,.5,.95)) {
      quantile<-mf$future_mean[H]+stats::qnorm(p)*sqrt(mf$future_covariance[H,H])
      exact<-gfir_normal_exact_cdf(quantile,c,H)
      record(paste0(id,"_cdf_p",p),max(exact$tightening_difference,exact$estimated_error),1e-8,
        abs(exact$value-p),detail="Exact coefficient/scale uncertainty retained in the marginal CDF.")
    }
    for(variance in c(.4,1.3)) {
      integral<-gfir_normal_transition_integral(c$mean0,variance,c)
      record(paste0(id,"_normalized_future_",variance),abs(integral$value-1),1e-8,
        detail="Direct response-coordinate integration of the normalized future density.")
      gap<-gfir_conditional_log_gap(rep(.2,H),c$mean0+c(.1,-.1),variance,c)
      record(paste0(id,"_conditional_entropy_cancel_",variance),abs(gap),1e-11,
        detail="Exact full-future conditional factor cancels the future log target pointwise.")
    }
    kl0<-gfir_joint_block_kl(c$mean0,1,mf$future_mean,mf$future_covariance,c)
    kl1<-gfir_joint_block_kl(c$mean0+c(1,-.5),1,mf$future_mean,mf$future_covariance,c)
    record(paste0(id,"_joint_but_parameter_independent"),if(abs(kl1-kl0)>1e-4) 0 else 1,0,
      detail="A full joint future block independent of parameters still has parameter-dependent conditional KL.")
    cases[[id]]<-list(exact_theta_mean=c$mean0,exact_theta_covariance=c$covariance0,
      exact_scale_prior=if(unknown) c(a=c$a,b=c$b) else NULL,mean_field=mf,
      conditional_block_KL_changes_with_parameters=abs(kl1-kl0))
  }
  for(p in c(.05,.5,.95)) {
    ref<-gfir_al_intercept_reference(p);mf<-gfir_al_intercept_prototype(p)
    err<-max(abs(c(mf$theta_mean-ref$theta_mean,mf$theta_variance-ref$theta_variance,
      mf$future_mean-ref$future_mean,mf$future_variance-ref$future_variance,mf$lambda-ref$lambda)))
    if(!mf$converged)err<-Inf
    record(paste0("AL_uncertain_intercept_p",p),err,1e-9,
      abs(mf$theta_variance-ref$exact_theta_variance)/ref$exact_theta_variance,1e-3,
      "No data were observed, but factorization narrows the coefficient marginal.")
    quantile<-mf$future_mean+stats::qnorm(p)*sqrt(mf$future_variance)
    exact<-gfir_al_intercept_cdf(quantile,p)
    record(paste0("AL_uncertain_intercept_cdf_p",p),
      max(exact$tightening_difference,exact$estimated_error),1e-8,abs(exact$value-p),
      detail="Exact AL--Normal convolution, not a fixed-parameter AL CDF.")
    cases[[paste0("AL_uncertain_intercept_p",p)]]<-list(reference=ref,mean_field=mf,exact_cdf_at_report=exact$value)
  }
  for(H in 1:2)for(p in c(.05,.5,.95)) {
    ref<-gfir_al_scale_reference(p,H);mf<-gfir_al_scale_prototype(p,H)
    err<-max(abs(c(mf$precision_mean-ref$precision_mean,mf$lambda-ref$lambda,
      mf$future_mean-ref$future_mean,mf$future_covariance-ref$future_covariance,
      mf$scale_shape-ref$scale_shape,mf$scale_rate-ref$scale_rate)))
    if(!mf$converged)err<-Inf
    locations<-c(.3,.7,1.5)
    cdf_prior<-stats::pgamma(1/locations,ref$prior_shape,rate=ref$prior_rate,lower.tail=FALSE)
    cdf_mf<-stats::pgamma(1/locations,mf$scale_shape,rate=mf$scale_rate,lower.tail=FALSE)
    record(paste0("AL_unknown_scale_h",H,"_p",p),err,1e-8,max(abs(cdf_mf-cdf_prior)),.005,
      "a+1.5H is the correct augmented conditional shape; altered marginal scale is factorization pseudo-information.")
    record(paste0("AL_unknown_scale_precision_mean_h",H,"_p",p),
      abs(mf$precision_mean-ref$exact_inverse_scale_mean),1e-9,
      detail="A correct unchanged inverse-scale mean does not prove an unchanged scale distribution.")
    if(H==1L) {
      quantile<-mf$future_mean+stats::qnorm(p)*sqrt(mf$future_covariance[1,1])
      exact<-gfir_al_scale_mixture_cdf(quantile,p)
      record(paste0("AL_unknown_scale_future_cdf_p",p),
        max(exact$tightening_difference,exact$estimated_error),1e-8,abs(exact$value-p),
        detail="One-step response accuracy uses the exact scale mixture, not an AL density at a mean scale.")
    }
    if(H==1L)for(y in c(-.8,0,.8)) {
      exact<-gfir_al_scale_mixture_cdf(y,p)
      analytic<-if(y<0)p*(2/(2-(1-p)*y))^3 else 1-(1-p)*(2/(2+p*y))^3
      record(paste0("AL_scale_mixture_p",p,"_y",y),abs(exact$value-analytic),1e-9,
        detail="Independent Gamma-precision quadrature agrees with the analytic one-step AL scale mixture.")
    }
    cases[[paste0("AL_unknown_scale_h",H,"_p",p)]]<-list(reference=ref,mean_field=mf,
      prior_cdf=cdf_prior,mean_field_cdf=cdf_mf)
    c<-gfir_normal_contract(H)
    for(sigma in c(.4,1.3)) {
      gap<-gfir_al_augmented_conditional_log_gap(rep(.2,H),seq(.3,.8,length.out=H),
        c$mean0+c(.1,-.1),sigma,p,c)
      record(paste0("AL_full_future_conditional_h",H,"_p",p,"_s",sigma),abs(gap),1e-11,
        detail="Conditional q(Y_F,v_F | all coefficients and AL scale) cancels the normalized future target; all Jacobians retained.")
    }
  }
  list(schema_version="glofas_future_information_reference_v1",checks=do.call(rbind,checks),cases=cases,
    scientific_runs=0L,authentic_reads=0L,future_truth_read=FALSE,
    scope="Generated no-ensemble qualification only; no production inference candidate is certified.")
}
