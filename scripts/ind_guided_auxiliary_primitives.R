# Qualification-only scalar Gaussian/AL convolutions and guided auxiliaries.
# Native AL scale: v ~ Exp(scale=sigma), y|L,v ~ N(L+A*v,B*sigma*v).
# No RNG, fitted-input I/O, parameter updating, or production enrollment.

ind_gap_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste0("IND guided auxiliary: ", message), call. = FALSE)
  invisible(TRUE)
}

ind_gap_inputs <- function(y, m, S, p, sigma) {
  xs <- list(y = y, m = m, S = S, p = p, sigma = sigma)
  ind_gap_require(all(vapply(xs, function(x) is.numeric(x) && length(x) >= 1L &&
    !anyNA(x), logical(1L))), "numeric, nonmissing arguments required")
  n <- max(lengths(xs))
  ind_gap_require(all(lengths(xs) %in% c(1L, n)), "partial recycling is forbidden")
  xs <- lapply(xs, rep_len, length.out = n)
  ind_gap_require(all(is.finite(c(xs$m, xs$S, xs$p, xs$sigma))) &&
    all(xs$S >= 0) && all(xs$p > 0 & xs$p < 1) && all(xs$sigma > 0),
    "invalid Gaussian covariance, quantile level or native scale")
  xs
}

ind_gap_logadd <- function(a, b) {
  top <- pmax(a, b)
  out <- top + log1p(exp(-abs(a - b)))
  out[is.infinite(top) & top < 0] <- -Inf
  out
}

# log(Phi(-t)) + t^2/2, avoiding cancellation in very remote Normal tails.
ind_gap_log_mills <- function(t) {
  ind_gap_require(is.numeric(t) && all(is.finite(t)) && all(t >= 0),
    "nonnegative finite Mills argument required")
  out <- numeric(length(t)); ordinary <- t < 30
  out[ordinary] <- stats::pnorm(-t[ordinary], log.p = TRUE) + .5*t[ordinary]^2
  if (any(!ordinary)) {
    z <- t[!ordinary]; inv2 <- (1 / z)^2
    term <- total <- rep(1, length(z))
    for (k in seq_len(24L)) {
      term <- -term * (2*k - 1) * inv2; total <- total + term
      if (all(abs(term) <= .Machine$double.eps * abs(total))) break
    }
    ind_gap_require(all(total > 0), "Mills expansion lost positive support")
    out[!ordinary] <- -.5*log(2*pi) - log(z) + log(total)
  }
  out
}

ind_gap_al_terms <- function(y, m, S, p, sigma) {
  q <- ind_gap_inputs(y, m, S, p, sigma)
  y <- q$y; m <- q$m; S <- q$S; p <- q$p; sigma <- q$sigma
  n <- length(y); d <- y-m
  km <- kp <- ld <- rep(-Inf, n)
  ratio_minus <- ratio_plus <- rep(NA_real_, n)
  finite <- is.finite(y)
  zero <- S == 0 & finite
  if (any(zero)) {
    ii <- which(zero); dd <- d[ii]
    km[ii] <- ifelse(dd >= 0, -p[ii]*dd/sigma[ii], -Inf)
    kp[ii] <- ifelse(dd < 0, (1-p[ii])*dd/sigma[ii], -Inf)
    ld[ii] <- log(p[ii]) + log1p(-p[ii]) - log(sigma[ii]) -
      ifelse(dd >= 0, p[ii]*dd/sigma[ii], (p[ii]-1)*dd/sigma[ii])
  }
  ii <- which(S > 0 & finite)
  if (length(ii)) {
    sd <- sqrt(S[ii]); z <- d[ii]/sd
    u <- p[ii]*sd/sigma[ii]; v <- (1-p[ii])*sd/sigma[ii]
    ind_gap_require(all(is.finite(c(z,u,v))), "Gaussian/AL geometry exceeds numerical range")
    log_k <- function(z, u) {
      x <- z-u; out <- numeric(length(x)); tail <- x < -10
      out[!tail] <- -u[!tail]*z[!tail] + .5*u[!tail]^2 +
        stats::pnorm(x[!tail], log.p = TRUE)
      out[tail] <- -.5*z[tail]^2 + ind_gap_log_mills(-x[tail])
      out
    }
    km[ii] <- log_k(z, u); kp[ii] <- log_k(-z, v)
    lm <- km[ii] - stats::pnorm(z, log.p = TRUE)
    use <- z <= 0
    lm[use] <- ind_gap_log_mills(u[use]-z[use]) - ind_gap_log_mills(-z[use])
    lp <- kp[ii] - stats::pnorm(-z, log.p = TRUE)
    use <- z >= 0
    lp[use] <- ind_gap_log_mills(v[use]+z[use]) - ind_gap_log_mills(z[use])
    # These are log expectations of a variable in (0,1]. Only floating-point
    # roundoff at zero may be normalized; material probability errors stop.
    ind_gap_require(all(is.finite(c(lm,lp))) && all(c(lm,lp) <= 64*.Machine$double.eps),
      "invalid exponential-tilt probability ratio")
    ratio_minus[ii] <- pmin(lm,0); ratio_plus[ii] <- pmin(lp,0)
    ld[ii] <- log(p[ii])+log1p(-p[ii])-log(sigma[ii]) + ind_gap_logadd(km[ii],kp[ii])
  }
  list(log_Kminus = km, log_Kplus = kp, log_density = ld,
    log_ratio_minus = ratio_minus, log_ratio_plus = ratio_plus,
    y = y, m = m, S = S, p = p, sigma = sigma,
    production_authorized = FALSE, random_draws_generated = 0L)
}

ind_gap_al_cdf <- function(y, m, S, p, sigma, lower.tail = TRUE, log.p = FALSE) {
  ind_gap_require(is.logical(lower.tail) && length(lower.tail)==1L && !is.na(lower.tail) &&
    is.logical(log.p) && length(log.p)==1L && !is.na(log.p), "scalar tail/log flags required")
  a <- ind_gap_al_terms(y,m,S,p,sigma)
  n <- length(a$y); lf <- ls <- numeric(n)
  atneg <- is.infinite(a$y) & a$y < 0; atpos <- is.infinite(a$y) & a$y > 0
  lf[atneg] <- -Inf; ls[atneg] <- 0; lf[atpos] <- 0; ls[atpos] <- -Inf
  ii <- which(is.finite(a$y) & a$S == 0)
  if (length(ii)) {
    d <- a$y[ii]-a$m[ii]; p <- a$p[ii]; sigma <- a$sigma[ii]
    left <- d < 0
    v <- log(p)+(1-p)*d/sigma
    w <- log1p(-p)-p*d/sigma
    lf[ii[left]] <- v[left]; ls[ii[left]] <- log(-expm1(v[left]))
    lf[ii[!left]] <- log(-expm1(w[!left])); ls[ii[!left]] <- w[!left]
  }
  ii <- which(is.finite(a$y) & a$S > 0)
  if (length(ii)) {
    z <- (a$y[ii]-a$m[ii])/sqrt(a$S[ii]); p <- a$p[ii]
    # All summands are positive. This avoids subtracting nearly equal CDF
    # terms in F=Phi(z)-(1-p)Kminus+p*Kplus.
    first <- stats::pnorm(z,log.p=TRUE) +
      log(p + (1-p)*(-expm1(a$log_ratio_minus[ii])))
    lf[ii] <- ind_gap_logadd(first,log(p)+a$log_Kplus[ii])
    first <- stats::pnorm(-z,log.p=TRUE) +
      log((1-p) + p*(-expm1(a$log_ratio_plus[ii])))
    ls[ii] <- ind_gap_logadd(first,log1p(-p)+a$log_Kminus[ii])
  }
  ind_gap_require(!anyNA(c(lf,ls)) && all(c(lf,ls) <= 128*.Machine$double.eps),
    "material CDF or survival probability error")
  lf <- pmin(lf,0); ls <- pmin(ls,0)
  requested <- if (lower.tail) lf else ls
  opposite <- if (lower.tail) ls else lf
  use_requested <- requested <= log(.5)
  if (log.p) {
    out <- requested
    out[!use_requested] <- log(-expm1(opposite[!use_requested]))
  } else {
    out <- exp(requested)
    out[!use_requested] <- -expm1(opposite[!use_requested])
  }
  ind_gap_require(!anyNA(out), "CDF calculation produced NaN")
  out
}

ind_gap_gig_half <- function(chi, psi, u_chisq, u_branch) {
  ind_gap_require(is.numeric(chi) && is.numeric(psi) && length(chi)==1L &&
    length(psi)==1L && is.finite(chi) && is.finite(psi) && chi>=0 && psi>0 &&
    all(is.finite(c(u_chisq,u_branch))) && length(u_chisq)==1L && length(u_branch)==1L &&
    u_chisq>0 && u_chisq<1 && u_branch>0 && u_branch<1,
    "invalid GIG(1/2,chi,psi) or supplied innovations")
  z2 <- stats::qchisq(u_chisq,df=1); c <- sqrt(chi/psi); k <- z2/(2*psi)
  root <- c + k + sqrt(k)*sqrt(2*c+k)
  ind_gap_require(is.finite(root) && root>0, "degenerate GIG proposal is not representable")
  # Reciprocal Michael--Schucany--Haas inverse-Gaussian draw. chi=0 gives
  # Gamma(1/2, rate=psi/2) directly through ChiSquared(1)/psi. A chi-square
  # inverse transform avoids the artificial qnorm(.5)^2=0 midpoint.
  v <- if (u_branch <= 1/(1+c/root)) root else (c/root)*c
  ind_gap_require(is.finite(v) && v>0, "GIG proposal lost positive support")
  v
}

ind_gap_propose <- function(y,m,S,p,sigma,u) {
  ind_gap_require(length(y)==1L && length(m)==1L && length(S)==1L && length(p)==1L &&
    length(sigma)==1L && is.finite(y) && is.numeric(u) && length(u)==4L &&
    all(is.finite(u)) && all(u>0 & u<1), "scalar proposal and four open-unit innovations required")
  a <- ind_gap_al_terms(y,m,S,p,sigma)
  if (S == 0) {
    L <- m; component <- "degenerate_Gaussian"
  } else {
    sd <- sqrt(S)
    choose_left <- u[1L] < exp(a$log_Kminus - ind_gap_logadd(a$log_Kminus,a$log_Kplus))
    if (choose_left) {
      mu <- m+p*S/sigma; upper <- (y-mu)/sd
      L <- mu+sd*stats::qnorm(log(u[2L])+stats::pnorm(upper,log.p=TRUE),log.p=TRUE)
      component <- "left_tilted_truncated_Normal"
    } else {
      mu <- m-(1-p)*S/sigma; lower <- (y-mu)/sd
      L <- mu+sd*stats::qnorm(log(u[2L])+stats::pnorm(lower,lower.tail=FALSE,log.p=TRUE),
        lower.tail=FALSE,log.p=TRUE)
      component <- "right_tilted_truncated_Normal"
    }
    ind_gap_require(is.finite(L) && if (choose_left) L<=y+1e-12*max(1,abs(y)) else
      L>=y-1e-12*max(1,abs(y)), "truncated scalar location escaped its support")
  }
  A <- (1-2*p)/(p*(1-p)); B <- 2/(p*(1-p))
  chi <- (y-L)^2/(B*sigma); psi <- A*A/(B*sigma)+2/sigma
  v <- ind_gap_gig_half(chi,psi,u[3L],u[4L])
  list(v=v,ex_f=A*v,ex_q=B*sigma*v,log_predictive_density=a$log_density,
    temporary_L=L,temporary_L_role="proposal_only_discard_before_state_update",
    proposal_component=component, proposal="exact_local_AL_observation_guidance",
    scale=sigma,p=p,random_draws_generated=0L,production_authorized=FALSE)
}

ind_gap_exal_propose <- function(y,m,S,p,sigma,gamma,s,u) {
  ind_gap_require(exists("ind_cfr_augmentation",mode="function"),
    "source-native exAL augmentation helper must be loaded")
  a <- ind_cfr_augmentation("exal",p,sigma,1,s,gamma)
  r <- a$native_r
  shift <- sigma * (as.numeric(gamma>0)-r)^(-1) * abs(gamma) * s
  out <- ind_gap_propose(y-shift,m,S,r,sigma,u)
  out$ex_f <- out$ex_f+shift;out$p <- p;out$native_r <- r;out$gamma <- gamma;out$s <- s
  out$proposal <- "native_prior_s_conditionally_exact_AL_v_guidance"
  out$log_weight_role <- "conditional_predictive_density_given_prior_s"
  out
}

ind_gap_weights <- function(weight) {
  ind_gap_require(is.numeric(weight) && length(weight)>=1L && all(is.finite(weight)) &&
    all(weight>=0) && max(weight)>0, "nonnegative nonzero finite mixture weights required")
  positive <- weight>0; w <- weight/max(weight);w <- w/sum(w)
  ind_gap_require(all(w[positive]>0), "positive mixture weight underflow")
  w
}

ind_gap_mixture_cdf <- function(y,m,S,p,sigma,weight) {
  ind_gap_require(is.numeric(m) && length(m)>=1L && length(S)==length(m) &&
    length(weight)==length(m) && length(p)==1L && length(sigma)==1L &&
    is.numeric(y) && length(y)>=1L && !anyNA(y), "invalid Gaussian/AL origin mixture")
  w <- ind_gap_weights(weight)
  vapply(y,function(z)sum(w*ind_gap_al_cdf(z,m,S,p,sigma)),numeric(1L))
}

ind_gap_mixture_quantile <- function(probability,m,S,p,sigma,weight,
    absolute_tolerance,relative_tolerance=0,max_iterations=256L) {
  ind_gap_require(is.numeric(probability) && length(probability)>=1L &&
    all(is.finite(probability)) && all(probability>0 & probability<1) &&
    is.numeric(absolute_tolerance) && length(absolute_tolerance)==1L &&
    is.finite(absolute_tolerance) && absolute_tolerance>0 &&
    is.numeric(relative_tolerance) && length(relative_tolerance)==1L &&
    is.finite(relative_tolerance) && relative_tolerance>=0 &&
    length(max_iterations)==1L && is.finite(max_iterations) && max_iterations>=1 &&
    max_iterations==as.integer(max_iterations), "explicit finite inversion contract required")
  ind_gap_mixture_cdf(0,m,S,p,sigma,weight)
  w <- ind_gap_weights(weight);active <- w>0
  m <- m[active];S <- S[active];w <- w[active]
  qal <- function(v) ifelse(v<p,sigma/(1-p)*log(v/p),-sigma/p*log((1-v)/(1-p)))
  cdf <- function(v)ind_gap_mixture_cdf(v,m,S,p,sigma,w)
  rows <- lapply(probability,function(prob) {
    lo <- min(m+sqrt(S)*stats::qnorm(prob/2)+qal(prob/2))
    hi <- max(m+sqrt(S)*stats::qnorm((1+prob)/2)+qal((1+prob)/2))
    ind_gap_require(all(is.finite(c(lo,hi))), "nonfinite convolution quantile bracket")
    span <- max(1,hi-lo);expansions <- 0L
    while(cdf(lo)>prob || cdf(hi)<prob) {
      if(cdf(lo)>prob)lo <- lo-span
      if(cdf(hi)<prob)hi <- hi+span
      span <- span*2;expansions <- expansions+1L
      ind_gap_require(expansions<=max_iterations && all(is.finite(c(lo,hi,span))),
        "convolution quantile bracket failed")
    }
    iter <- 0L
    repeat {
      tol <- absolute_tolerance+relative_tolerance*max(abs(c(lo,hi)))
      ind_gap_require(is.finite(tol),"nonfinite computed inversion tolerance")
      if(hi-lo<=tol)break
      ind_gap_require(iter<max_iterations,"convolution quantile inversion exhausted limit")
      mid <- lo/2+hi/2
      ind_gap_require(mid>lo && mid<hi,"inversion tolerance below floating-point resolution")
      if(cdf(mid)>=prob)hi <- mid else lo <- mid
      iter <- iter+1L
    }
    data.frame(probability=prob,quantile=hi,lower=lo,upper=hi,cdf_lower=cdf(lo),
      cdf_upper=cdf(hi),iterations=iter,bracket_expansions=expansions,width_tolerance=tol)
  })
  list(result=do.call(rbind,rows),accuracy_scope="finite_origin_mixture_and_exact_terminal_AL_inversion",
    origin_filter_accuracy_qualified=FALSE,random_draws_generated=0L,production_authorized=FALSE)
}

# Terminal exAL half-Normal shift is independent of future covariance history.
# This is one-dimensional numerical integration, with an explicit error report.
ind_gap_exal_cdf <- function(y,m,S,p,sigma,gamma,absolute_tolerance,
    relative_tolerance=1e-8,subdivisions=1000L) {
  ind_gap_require(length(y)==1L && is.finite(y) && length(m)==1L && length(S)==1L &&
    length(p)==1L && length(sigma)==1L && length(gamma)==1L &&
    is.numeric(absolute_tolerance) && length(absolute_tolerance)==1L &&
    is.finite(absolute_tolerance) && absolute_tolerance>0 &&
    is.numeric(relative_tolerance) && length(relative_tolerance)==1L &&
    is.finite(relative_tolerance) && relative_tolerance>=0 &&
    length(subdivisions)==1L && is.finite(subdivisions) && subdivisions>=1 &&
    subdivisions==as.integer(subdivisions), "explicit exAL quadrature contract required")
  ind_gap_require(exists("ind_cfr_augmentation",mode="function"),"native exAL helper required")
  a <- ind_cfr_augmentation("exal",p,sigma,1,1,gamma)
  r <- a$native_r
  shift <- sigma * (as.numeric(gamma>0)-r)^(-1) * abs(gamma)
  if(gamma==0) return(list(value=ind_gap_al_cdf(y,m,S,p,sigma),absolute_error=0,
    subintervals=0L,message="exact_AL_limit",production_authorized=FALSE))
  z <- stats::integrate(function(s)2*stats::dnorm(s)*ind_gap_al_cdf(y-shift*s,m,S,r,sigma),
    lower=0,upper=Inf,abs.tol=absolute_tolerance,rel.tol=relative_tolerance,
    subdivisions=as.integer(subdivisions),stop.on.error=FALSE)
  ind_gap_require(identical(z$message,"OK") && is.finite(z$value) &&
    z$value>=0 && z$value<=1 && is.finite(z$abs.error) &&
    z$abs.error<=max(absolute_tolerance,relative_tolerance*abs(z$value)),
    "terminal exAL quadrature failed its declared error gate")
  list(value=z$value,absolute_error=z$abs.error,subintervals=z$subdivisions,
    message=z$message,accuracy_scope="terminal_half_Normal_quadrature_not_origin_filter",
    production_authorized=FALSE)
}
