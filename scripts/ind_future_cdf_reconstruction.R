# Known-F/G horizon marginals; not a joint-path simulator or accuracy grant.
source("scripts/ind_guided_auxiliary_filter.R")
source("scripts/ind_conditional_future_marginals.R")

ind_fcm_components <- function(checkpoint,FF,GG,df_mat,eta,v_paths,origin_component,
    future_features,future_auxiliary_role,tolerance=1e-10) {
  ind_gaf_eta(eta)
  ind_cfr_require(identical(future_features,"known_deterministic") &&
    identical(future_auxiliary_role,"native_prior_Exp_scale_sigma_supplied_paths") &&
    is.list(checkpoint)&&identical(checkpoint$representation,"weighted_pre_resampling")&&
    identical(checkpoint$eta,eta)&&is.matrix(checkpoint$mean)&&is.numeric(checkpoint$mean)&&
    is.character(checkpoint$parameter_id)&&length(checkpoint$parameter_id)==1L&&
    !is.na(checkpoint$parameter_id)&&nzchar(checkpoint$parameter_id)&&
    is.numeric(checkpoint$observed_prefix_length)&&length(checkpoint$observed_prefix_length)==1L&&
    is.finite(checkpoint$observed_prefix_length)&&checkpoint$observed_prefix_length>=1&&
    checkpoint$observed_prefix_length==as.integer(checkpoint$observed_prefix_length),
    "explicit source-compatible known features, fixed eta and prior-v role required")
  p <- nrow(checkpoint$mean);N <- ncol(checkpoint$mean)
  ind_cfr_require(is.matrix(FF)&&is.numeric(FF)&&nrow(FF)==p&&ncol(FF)>=1L&&all(is.finite(FF))&&
    is.matrix(v_paths)&&is.numeric(v_paths)&&nrow(v_paths)>=1L&&ncol(v_paths)==ncol(FF)&&
    all(is.finite(v_paths))&&all(v_paths>0)&&is.numeric(origin_component)&&
    length(origin_component)==nrow(v_paths),"complete fixed-feature future auxiliary geometry required")
  H <- ncol(FF);B <- nrow(v_paths)
  if(is.matrix(GG)) {
    ind_cfr_require(identical(dim(GG),c(p,p)),"invalid future evolution matrix")
    GG <- array(rep(GG,H),c(p,p,H))
  }
  ind_cfr_require(is.numeric(GG)&&identical(dim(GG),c(p,p,H))&&all(is.finite(GG))&&
    identical(dim(checkpoint$covariance),c(p,p,N))&&is.numeric(checkpoint$weights)&&length(checkpoint$weights)==N&&
    all(is.finite(checkpoint$weights))&&all(checkpoint$weights>=0)&&
    abs(sum(checkpoint$weights)-1)<=1e-10&&
    all(is.finite(checkpoint$mean))&&all(is.finite(checkpoint$covariance)),"invalid origin/future dimensions")
  weights <- ind_cfm_origin_path_weights(checkpoint$weights,origin_component)
  mean <- variance <- matrix(0,B,H)
  a <- ind_cfr_augmentation(eta$family,eta$p,eta$sigma,1,
    if(eta$family=="exal")0 else NULL,eta$gamma)
  Bnative <- a$ex_q/eta$sigma
  for(i in seq_len(B)) {
    j <- as.integer(origin_component[i])
    f <- ind_cfm_future(as.numeric(checkpoint$mean[,j]),matrix(checkpoint$covariance[,,j],p,p),
      FF,GG,ex_f=numeric(H),ex_q=Bnative*eta$sigma*v_paths[i,],df_mat,
      future_features,tolerance)
    # No auxiliary mean offset is propagated as a state observation. The
    # terminal observation law is integrated separately at every horizon.
    for(h in seq_len(H)) {
      mean[i,h] <- sum(FF[,h]*f$state_mean[,h])
      variance[i,h] <- as.numeric(t(FF[,h])%*%matrix(f$state_covariance[,,h],p,p)%*%FF[,h])
    }
  }
  ind_cfr_require(all(is.finite(c(mean,variance)))&&all(variance>=0),"nonfinite future Gaussian components")
  structure(list(schema_version="ind_known_feature_terminal_cdf_components_v1",
    mean=mean,variance=variance,weight=weights,eta=eta,H=H,
    origin_component=as.integer(origin_component),parameter_id=checkpoint$parameter_id,
    observed_prefix_length=checkpoint$observed_prefix_length,future_features=future_features,
    future_auxiliary_role=future_auxiliary_role,
    Gaussian_states_and_intermediate_responses_integrated=TRUE,
    intermediate_half_Normal_shifts_required=FALSE,terminal_v_integrated=TRUE,
    original_origin_weights_preserved=TRUE,joint_future_path_law_returned=FALSE,
    future_auxiliary_integration_qualified=FALSE,origin_filter_accuracy_qualified=FALSE,
    source_identity_authenticated=FALSE,random_draws_generated=0L,new_model_fits=0L,
    production_authorized=FALSE),class=c("ind_known_feature_terminal_cdf_components","list"))
}

ind_fcm_cdf <- function(y,horizon,components,quadrature_absolute_tolerance=1e-10,
    quadrature_relative_tolerance=1e-10,quadrature_subdivisions=1000L) {
  ind_cfr_require(inherits(components,"ind_known_feature_terminal_cdf_components")&&
    is.numeric(y)&&length(y)>=1L&&all(is.finite(y))&&is.numeric(horizon)&&
    length(horizon)==1L&&is.finite(horizon)&&horizon==as.integer(horizon)&&
    horizon>=1&&horizon<=components$H,"finite marginal CDF arguments and horizon required")
  eta <- components$eta;ind_gaf_eta(eta)
  w <- ind_gap_weights(components$weight);m <- components$mean[,horizon];S <- components$variance[,horizon]
  if(eta$family=="al" || eta$gamma==0) {
    value <- ind_gap_mixture_cdf(y,m,S,eta$p,eta$sigma,w);error <- numeric(length(y))
    kind <- "analytic_Normal_AL_no_terminal_quadrature"
  } else {
    z <- lapply(y,function(v) {
      a <- lapply(seq_along(w),function(j)ind_gap_exal_cdf(v,m[j],S[j],eta$p,eta$sigma,eta$gamma,
        quadrature_absolute_tolerance,quadrature_relative_tolerance,quadrature_subdivisions))
      c(value=sum(w*vapply(a,`[[`,numeric(1L),"value")),
        error=sum(w*vapply(a,`[[`,numeric(1L),"absolute_error")))
    })
    value <- vapply(z,`[[`,numeric(1L),"value");error <- vapply(z,`[[`,numeric(1L),"error")
    kind <- "weighted_QUADPACK_error_estimate_not_rigorous_bound"
  }
  ind_cfr_require(all(is.finite(c(value,error)))&&all(value>=0&value<=1)&&all(error>=0),
    "invalid terminal CDF calculation")
  list(value=value,terminal_quadrature_error_estimate=error,error_kind=kind,
    horizon=as.integer(horizon),parameter_id=components$parameter_id,
    accuracy_scope="supplied_finite_origin_and_future_auxiliary_mixture_only",
    origin_filter_accuracy_qualified=FALSE,future_auxiliary_integration_qualified=FALSE,
    rigorous_quadrature_error_bound=FALSE,particle_filter_accuracy_certified=FALSE,
    random_draws_generated=0L,production_authorized=FALSE)
}

ind_fcm_quantile <- function(probability,horizon,components,absolute_tolerance=1e-8,
    relative_tolerance=0,max_iterations=256L,quadrature_absolute_tolerance=1e-10,
    quadrature_relative_tolerance=1e-10,quadrature_subdivisions=1000L) {
  ind_cfr_require(is.numeric(probability)&&length(probability)>=1L&&all(is.finite(probability))&&
    all(probability>0&probability<1)&&length(absolute_tolerance)==1L&&is.finite(absolute_tolerance)&&
    absolute_tolerance>0&&length(relative_tolerance)==1L&&is.finite(relative_tolerance)&&relative_tolerance>=0&&
    length(max_iterations)==1L&&is.finite(max_iterations)&&max_iterations>=1&&max_iterations==as.integer(max_iterations),
    "explicit finite marginal inversion contract required")
  cdf <- function(x)ind_fcm_cdf(x,horizon,components,quadrature_absolute_tolerance,
    quadrature_relative_tolerance,quadrature_subdivisions)
  cdf(0);eta <- components$eta
  if(eta$family=="al" || eta$gamma==0) {
    out <- ind_gap_mixture_quantile(probability,components$mean[,horizon],components$variance[,horizon],
      eta$p,eta$sigma,components$weight,absolute_tolerance,relative_tolerance,max_iterations)
    out$finite_mixture_bracket_is_analytic <- TRUE
  } else {
    scale <- max(1,eta$sigma,sqrt(components$variance[,horizon]),abs(components$mean[,horizon]))
    rows <- lapply(probability,function(prob) {
      lo <- min(components$mean[,horizon])-scale;hi <- max(components$mean[,horizon])+scale
      span <- scale;expand <- 0L
      while(cdf(lo)$value>prob || cdf(hi)$value<prob) {
        if(cdf(lo)$value>prob)lo <- lo-span
        if(cdf(hi)$value<prob)hi <- hi+span
        span <- 2*span;expand <- expand+1L
        ind_cfr_require(expand<=max_iterations&&all(is.finite(c(lo,hi,span))),"exAL CDF bracket failed")
      }
      iter <- 0L
      repeat {
        tol <- absolute_tolerance+relative_tolerance*max(abs(c(lo,hi)))
        if(hi-lo<=tol)break
        ind_cfr_require(iter<max_iterations,"exAL CDF inversion exhausted finite iteration budget")
        mid <- lo/2+hi/2
        ind_cfr_require(mid>lo&&mid<hi,"exAL inversion below floating-point resolution")
        at <- cdf(mid)
        ind_cfr_require(abs(at$value-prob)>at$terminal_quadrature_error_estimate,
          "exAL inversion comparison unresolved at declared quadrature precision")
        if(at$value>=prob)hi <- mid else lo <- mid
        iter <- iter+1L
      }
      low <- cdf(lo);high <- cdf(hi)
      ind_cfr_require(low$value+low$terminal_quadrature_error_estimate<=prob&&
        high$value-high$terminal_quadrature_error_estimate>=prob,
        "exAL endpoint bracket unresolved at declared quadrature precision")
      data.frame(probability=prob,quantile=hi,lower=lo,upper=hi,cdf_lower=low$value,cdf_upper=high$value,
        terminal_quadrature_error_estimate=max(low$terminal_quadrature_error_estimate,
          high$terminal_quadrature_error_estimate),iterations=iter,bracket_expansions=expand)
    })
    out <- list(result=do.call(rbind,rows),finite_mixture_bracket_is_analytic=FALSE)
  }
  out$accuracy_scope <- "numerical_inversion_of_supplied_finite_future_CDF_only"
  out$origin_filter_accuracy_qualified <- FALSE;out$future_auxiliary_integration_qualified <- FALSE
  out$rigorous_quadrature_error_bound <- FALSE;out$production_authorized <- FALSE
  out$random_draws_generated <- 0L;out$new_model_fits <- 0L
  out
}
