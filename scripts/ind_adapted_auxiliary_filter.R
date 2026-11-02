# Opt-in ancestor-first auxiliary filtering, without file I/O or RNG calls.
# Retains the frozen guided reference unchanged. Not an accuracy certificate.
source("scripts/ind_guided_auxiliary_filter.R")

ind_aaf_hash <- function(x) {
  ind_cfr_require(requireNamespace("digest", quietly = TRUE), "digest is required")
  digest::digest(x, algo="sha256", serialize=TRUE, serializeVersion=2L)
}
ind_aaf_logmean <- function(x) {
  ind_cfr_require(is.numeric(x) && length(x)>0L && !anyNA(x) && any(is.finite(x)),
    "finite positive log mass required")
  hi <- max(x); hi+log(mean(exp(x-hi)))
}
ind_aaf_initialize <- function(m0,C0,df_mat,eta,particle_count,parameter_id,
    ess_fraction=.5,tolerance=1e-10,exal_lookahead_nodes=16L) {
  ind_gaf_eta(eta)
  ind_cfr_require(is.numeric(m0) && length(m0)>=1L && all(is.finite(m0)) &&
    is.numeric(particle_count) && length(particle_count)==1L && is.finite(particle_count) &&
    particle_count>=1 && particle_count==as.integer(particle_count) &&
    is.character(parameter_id) && length(parameter_id)==1L && !is.na(parameter_id) && nzchar(parameter_id) &&
    is.numeric(ess_fraction) && length(ess_fraction)==1L && is.finite(ess_fraction) &&
    ess_fraction>=0 && ess_fraction<=1 && is.numeric(tolerance) && length(tolerance)==1L &&
    is.finite(tolerance) && tolerance>0 && is.numeric(exal_lookahead_nodes) &&
    length(exal_lookahead_nodes)==1L && is.finite(exal_lookahead_nodes) &&
    exal_lookahead_nodes>=1 && exal_lookahead_nodes<=128 &&
    exal_lookahead_nodes==as.integer(exal_lookahead_nodes), "explicit adapted-filter initialization required")
  p <- length(m0);N <- as.integer(particle_count)
  ind_caf_psd(C0,p,tolerance,"adapted initial covariance")
  ind_caf_psd(df_mat,p,tolerance,"adapted discount matrix")
  ind_cfr_require(all(df_mat>=0),"negative adapted discount inflation")
  identity <- list(eta=eta,parameter_id=parameter_id,m0=m0,C0=C0,df_mat=df_mat,
    ess_fraction=ess_fraction,tolerance=tolerance,exal_lookahead_nodes=as.integer(exal_lookahead_nodes))
  structure(list(schema_version="ind_ancestor_first_auxiliary_filter_state_v1",
    identity=identity,identity_sha256=ind_aaf_hash(identity),time_index=0L,
    mean=matrix(rep(m0,N),p,N),covariance=array(rep(C0,N),c(p,p,N)),
    weights=rep(1/N,N),lineage=seq_len(N),particle_count=N,
    last_report=NULL,last_diagnostics=NULL,parameter_weights_updated=FALSE,
    numerical_accuracy_qualified=FALSE,source_identity_authenticated=FALSE,
    production_authorized=FALSE,random_draws_generated=0L,new_model_fits=0L),
    class=c("ind_ancestor_first_auxiliary_filter_state","list"))
}

ind_aaf_check_state <- function(state) {
  ind_cfr_require(inherits(state,"ind_ancestor_first_auxiliary_filter_state") &&
    identical(state$schema_version,"ind_ancestor_first_auxiliary_filter_state_v1") &&
    identical(state$identity_sha256,ind_aaf_hash(state$identity)),
    "adapted static parameters or policy changed")
  ind_gaf_eta(state$identity$eta)
  N <- state$particle_count;p <- nrow(state$mean)
  ind_cfr_require(is.matrix(state$mean) && is.numeric(state$mean) && ncol(state$mean)==N &&
    all(is.finite(state$mean)) && identical(dim(state$covariance),c(p,p,N)) &&
    all(is.finite(state$covariance)) && is.numeric(state$weights) && length(state$weights)==N &&
    all(is.finite(state$weights)) && all(state$weights>=0) && abs(sum(state$weights)-1)<=1e-10 &&
    length(state$lineage)==N && all(state$lineage>=1L & state$lineage<=N) &&
    length(state$time_index)==1L && is.finite(state$time_index) && state$time_index>=0 &&
    state$time_index==as.integer(state$time_index) && !state$parameter_weights_updated &&
    !state$production_authorized,"invalid adapted continuation state")
  invisible(TRUE)
}

ind_aaf_step <- function(state,y,F,G,innovations,time_index) {
  ind_aaf_check_state(state)
  N <- state$particle_count;p <- nrow(state$mean);policy <- state$identity;eta <- policy$eta
  ind_cfr_require(is.numeric(y) && length(y)==1L && is.finite(y) && is.numeric(F) &&
    length(F)==p && all(is.finite(F)) && is.matrix(G) && is.numeric(G) &&
    identical(dim(G),c(p,p)) && all(is.finite(G)) && is.numeric(time_index) &&
    length(time_index)==1L && is.finite(time_index) && time_index==state$time_index+1L,
    "next causal observation and exact F/G/time required")
  open <- function(x,n) is.numeric(x) && length(x)==n && all(is.finite(x)) && all(x>0 & x<1)
  ind_cfr_require(is.list(innovations) && is.matrix(innovations$proposal) &&
    identical(dim(innovations$proposal),c(N,4L)) && open(innovations$proposal,4L*N) &&
    open(innovations$ancestor,1L) && open(innovations$residual_resampling,1L),
    "independent supplied ancestor/proposal/residual innovations required")
  if(eta$family=="exal") ind_cfr_require(open(innovations$half_normal,N),"native exAL half-Normal innovations required")
  else ind_cfr_require(is.null(innovations$half_normal),"AL cannot inherit half-Normal innovations")
  sym <- function(x).5*(x+t(x))
  a <- matrix(0,p,N);R <- array(0,c(p,p,N));RF <- matrix(0,p,N);f <- S <- numeric(N)
  for(j in seq_len(N)) {
    ind_caf_psd(matrix(state$covariance[,,j],p,p),p,policy$tolerance,"adapted carried covariance")
    a[,j] <- as.numeric(G%*%state$mean[,j]);P <- G%*%matrix(state$covariance[,,j],p,p)%*%t(G)
    W <- sym(policy$df_mat*P);R[,,j] <- sym(P+policy$df_mat*P)
    ind_caf_psd(W,p,policy$tolerance,"adapted innovation covariance")
    ind_caf_psd(matrix(R[,,j],p,p),p,policy$tolerance,"adapted predictive covariance")
    RF[,j] <- as.numeric(R[,,j]%*%F);f[j] <- sum(F*a[,j]);S[j] <- sum(F*RF[,j])
  }
  ind_cfr_require(all(is.finite(c(f,S))) && all(S>=0),"invalid adapted projected Gaussian variance")
  if(eta$family=="al" || eta$gamma==0) {
    look <- ind_gap_al_terms(y,f,S,eta$p,eta$sigma)$log_density
  } else {
    aug <- ind_cfr_augmentation("exal",eta$p,eta$sigma,1,1,eta$gamma)
    shift <- eta$sigma*(as.numeric(eta$gamma>0)-aug$native_r)^(-1)*abs(eta$gamma)
    nodes <- stats::qnorm((1-(seq_len(policy$exal_lookahead_nodes)-.5)/policy$exal_lookahead_nodes)/2,
      lower.tail=FALSE)
    look <- rep(-Inf,N)
    for(s in nodes)look <- ind_gap_logadd(look,ind_gap_al_terms(y-shift*s,f,S,aug$native_r,eta$sigma)$log_density)
    look <- look-log(length(nodes))
  }
  ind_cfr_require(all(is.finite(look)),"nonfinite positive adapted lookahead")
  lw <- log(state$weights)+look;hi <- max(lw);logZ <- hi+log(sum(exp(lw-hi)))
  ancestor_weights <- exp(lw-logZ)
  A <- ind_caf_systematic_indices(ancestor_weights,innovations$ancestor)
  mn <- matrix(0,p,N);Cn <- array(0,c(p,p,N));residual <- numeric(N)
  for(i in seq_len(N)) {
    j <- A[i];u <- as.numeric(innovations$proposal[i,])
    prop <- if(eta$family=="al")ind_gap_propose(y,f[j],S[j],eta$p,eta$sigma,u) else
      ind_gap_exal_propose(y,f[j],S[j],eta$p,eta$sigma,eta$gamma,
        stats::qnorm((1-innovations$half_normal[i])/2,lower.tail=FALSE),u)
    Q <- S[j]+prop$ex_q
    ind_cfr_require(is.finite(Q)&&Q>0,"nonpositive adapted observation variance")
    mn[,i] <- a[,j]+RF[,j]*((y-f[j]-prop$ex_f)/Q)
    Cn[,,i] <- sym(matrix(R[,,j],p,p)-tcrossprod(RF[,j])/Q)
    ind_caf_psd(matrix(Cn[,,i],p,p),p,policy$tolerance,"adapted updated covariance")
    # Prior-s cancels q(s); conditional-v cancels its density. The temporary
    # projected location has been integrated out, never assimilated twice.
    residual[i] <- if(eta$family=="al" || eta$gamma==0)0 else prop$log_predictive_density-look[j]
  }
  lr <- ind_aaf_logmean(residual);weights <- exp(residual-lr)/N
  ind_cfr_require(all(is.finite(c(mn,Cn,weights))) && abs(sum(weights)-1)<=1e-10,
    "adapted residual weights or Gaussian update failed")
  ESS <- 1/sum(weights^2);post <- ESS<policy$ess_fraction*N
  B <- if(post)ind_caf_systematic_indices(weights,innovations$residual_resampling)else seq_len(N)
  state$last_report <- list(observed_prefix_length=as.integer(time_index),
    parameter_id=policy$parameter_id,eta=eta,mean=mn,covariance=Cn,weights=weights,
    representation="weighted_pre_resampling",future_outcomes_used=0L,
    conditioning="fixed_static_parameter_observed_prefix_auxiliary_mixture",
    temporary_projected_location_assimilated=FALSE,
    approximation="ancestor_first_auxiliary_particle_filter_accuracy_unqualified",
    source_draw_inventory_authenticated=FALSE,production_authorized=FALSE)
  state$last_diagnostics <- list(time_index=as.integer(time_index),
    lookahead_ESS=1/sum(ancestor_weights^2),residual_ESS=ESS,
    selected_ancestor_count=length(unique(A)),ancestor_indices=A,
    ancestor_probabilities=ancestor_weights,post_resampled=post,post_indices=B,
    distinct_initial_lineages=length(unique(state$lineage[A[B]])),
    log_lookahead_normalizer=logZ,log_mean_residual_weight=lr,
    log_predictive_increment=logZ+lr,
    residual_weight_underflow_count=sum(is.finite(residual)&weights==0),
    proposal=if(eta$family=="al" || eta$gamma==0)"fully_adapted_AL_ancestor_and_v" else
      "positive_midpoint_lookahead_prior_s_exact_residual_correction",
    lookahead_is_exact=eta$family=="al" || eta$gamma==0,
    numerical_accuracy_qualified=FALSE)
  state$mean <- mn[,B,drop=FALSE];state$covariance <- Cn[,,B,drop=FALSE]
  state$weights <- if(post)rep(1/N,N)else weights
  state$lineage <- state$lineage[A[B]];state$time_index <- as.integer(time_index)
  state
}

ind_aaf_continue <- function(state,y,FF,GG,uniforms,time_indices,checkpoint_indices) {
  ind_aaf_check_state(state);n <- length(y);p <- nrow(state$mean);N <- state$particle_count
  ind_cfr_require(is.numeric(y)&&n>=1L&&all(is.finite(y))&&is.matrix(FF)&&is.numeric(FF)&&
    identical(dim(FF),c(p,n))&&all(is.finite(FF))&&is.numeric(time_indices)&&
    identical(as.numeric(time_indices),as.numeric(state$time_index+seq_len(n)))&&
    is.numeric(checkpoint_indices)&&!anyNA(checkpoint_indices)&&!anyDuplicated(checkpoint_indices)&&
    !is.unsorted(checkpoint_indices)&&all(checkpoint_indices %in% time_indices),
    "contiguous causal continuation times and explicit checkpoints required")
  if(is.matrix(GG)) {
    ind_cfr_require(identical(dim(GG),c(p,p)),"invalid constant continuation evolution")
    GG <- array(rep(GG,n),c(p,p,n))
  }
  ind_cfr_require(is.numeric(GG)&&identical(dim(GG),c(p,p,n))&&all(is.finite(GG))&&
    is.list(uniforms)&&is.numeric(uniforms$proposal)&&
    identical(dim(uniforms$proposal),c(N,n,4L))&&length(uniforms$ancestor)==n&&
    length(uniforms$residual_resampling)==n,"complete continuation geometry/streams required")
  if(state$identity$eta$family=="exal")ind_cfr_require(is.matrix(uniforms$half_normal)&&
    identical(dim(uniforms$half_normal),c(N,n)),"paired exAL continuation innovations required")
  else ind_cfr_require(is.null(uniforms$half_normal),"AL continuation cannot inherit half-Normal streams")
  checkpoints <- list();diagnostics <- vector("list",n)
  for(i in seq_len(n)) {
    innovation <- list(proposal=matrix(uniforms$proposal[,i,],N,4L),ancestor=uniforms$ancestor[i],
      residual_resampling=uniforms$residual_resampling[i],
      half_normal=if(is.null(uniforms$half_normal))NULL else uniforms$half_normal[,i])
    state <- ind_aaf_step(state,y[i],FF[,i],matrix(GG[,,i],p,p),innovation,time_indices[i])
    if(time_indices[i] %in% checkpoint_indices)checkpoints[[as.character(time_indices[i])]] <- state$last_report
    diagnostics[[i]] <- state$last_diagnostics
  }
  list(state=state,checkpoints=checkpoints,diagnostics=diagnostics,
    numerical_accuracy_qualified=FALSE,production_authorized=FALSE)
}
