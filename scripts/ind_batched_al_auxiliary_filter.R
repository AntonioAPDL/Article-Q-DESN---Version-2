# Opt-in batching of the existing AL proposal transforms only.
# The scalar reference/default remains ind_aaf_step/ind_aaf_continue.
# No RNG, model/input I/O, parameter updates or production permission.
source("scripts/ind_adapted_auxiliary_filter.R")

ind_baf_al_propose <- function(y,m,S,p,sigma,u) {
  ind_gap_require(is.numeric(y)&&length(y)==1L&&is.finite(y)&&
    is.numeric(m)&&length(m)>=1L&&is.numeric(S)&&length(S)==length(m)&&
    is.numeric(p)&&length(p)==1L&&is.numeric(sigma)&&length(sigma)==1L&&
    is.matrix(u)&&is.numeric(u)&&identical(dim(u),c(length(m),4L))&&
    all(is.finite(u))&&all(u>0&u<1),"batched AL geometry and four open-unit columns required")
  a<-ind_gap_al_terms(y,m,S,p,sigma);N<-length(m)
  L<-as.numeric(m);component<-rep("degenerate_Gaussian",N)
  positive<-which(S>0)
  if(length(positive)) {
    left<-u[positive,1L]<exp(a$log_Kminus[positive]-
      ind_gap_logadd(a$log_Kminus[positive],a$log_Kplus[positive]))
    ii<-positive[left]
    if(length(ii)) {
      sd<-sqrt(S[ii]);mu<-m[ii]+p*S[ii]/sigma;upper<-(y-mu)/sd
      L[ii]<-mu+sd*stats::qnorm(log(u[ii,2L])+stats::pnorm(upper,log.p=TRUE),log.p=TRUE)
      component[ii]<-"left_tilted_truncated_Normal"
    }
    ii<-positive[!left]
    if(length(ii)) {
      sd<-sqrt(S[ii]);mu<-m[ii]-(1-p)*S[ii]/sigma;lower<-(y-mu)/sd
      L[ii]<-mu+sd*stats::qnorm(log(u[ii,2L])+
        stats::pnorm(lower,lower.tail=FALSE,log.p=TRUE),lower.tail=FALSE,log.p=TRUE)
      component[ii]<-"right_tilted_truncated_Normal"
    }
    support<-ifelse(component[positive]=="left_tilted_truncated_Normal",
      L[positive]<=y+1e-12*max(1,abs(y)),L[positive]>=y-1e-12*max(1,abs(y)))
    ind_gap_require(all(is.finite(L))&&all(support),"batched truncated location escaped support")
  }
  A<-(1-2*p)/(p*(1-p));B<-2/(p*(1-p))
  chi<-(y-L)^2/(B*sigma);psi<-A*A/(B*sigma)+2/sigma
  ind_gap_require(all(is.finite(chi))&&all(chi>=0)&&is.finite(psi)&&psi>0,
    "invalid batched native GIG parameters")
  z2<-stats::qchisq(u[,3L],df=1);c0<-sqrt(chi/psi);k<-z2/(2*psi)
  root<-c0+k+sqrt(k)*sqrt(2*c0+k)
  ind_gap_require(all(is.finite(root))&&all(root>0),"degenerate batched GIG root")
  v<-ifelse(u[,4L]<=1/(1+c0/root),root,(c0/root)*c0)
  ind_gap_require(all(is.finite(v))&&all(v>0),"batched GIG proposal lost positive support")
  list(v=v,ex_f=A*v,ex_q=B*sigma*v,log_predictive_density=a$log_density,
    temporary_L=L,temporary_L_role="proposal_only_discard_before_state_update",
    proposal_component=component,proposal="exact_local_AL_observation_guidance",
    scale=sigma,p=p,random_draws_generated=0L,production_authorized=FALSE)
}

ind_baf_step <- function(state,y,F,G,innovations,time_index) {
  ind_aaf_check_state(state)
  N<-state$particle_count;p<-nrow(state$mean);policy<-state$identity;eta<-policy$eta
  ind_cfr_require(identical(eta$family,"al")&&eta$gamma==0,
    "batched proposal backend is AL-only; exAL retains its reference")
  ind_cfr_require(is.numeric(y)&&length(y)==1L&&is.finite(y)&&is.numeric(F)&&
    length(F)==p&&all(is.finite(F))&&is.matrix(G)&&is.numeric(G)&&
    identical(dim(G),c(p,p))&&all(is.finite(G))&&is.numeric(time_index)&&
    length(time_index)==1L&&is.finite(time_index)&&time_index==state$time_index+1L,
    "next causal observation and exact F/G/time required")
  open<-function(x,n)is.numeric(x)&&length(x)==n&&all(is.finite(x))&&all(x>0&x<1)
  ind_cfr_require(is.list(innovations)&&is.matrix(innovations$proposal)&&
    identical(dim(innovations$proposal),c(N,4L))&&open(innovations$proposal,4L*N)&&
    open(innovations$ancestor,1L)&&open(innovations$residual_resampling,1L)&&
    is.null(innovations$half_normal),"independent supplied AL innovations required")
  sym<-function(x).5*(x+t(x))
  a<-matrix(0,p,N);R<-array(0,c(p,p,N));RF<-matrix(0,p,N);f<-S<-numeric(N)
  # Deliberately retain scalar matrix arithmetic and every reference PSD test.
  for(j in seq_len(N)) {
    ind_caf_psd(matrix(state$covariance[,,j],p,p),p,policy$tolerance,"adapted carried covariance")
    a[,j]<-as.numeric(G%*%state$mean[,j]);P<-G%*%matrix(state$covariance[,,j],p,p)%*%t(G)
    W<-sym(policy$df_mat*P);R[,,j]<-sym(P+policy$df_mat*P)
    ind_caf_psd(W,p,policy$tolerance,"adapted innovation covariance")
    ind_caf_psd(matrix(R[,,j],p,p),p,policy$tolerance,"adapted predictive covariance")
    RF[,j]<-as.numeric(R[,,j]%*%F);f[j]<-sum(F*a[,j]);S[j]<-sum(F*RF[,j])
  }
  ind_cfr_require(all(is.finite(c(f,S)))&&all(S>=0),"invalid adapted projected Gaussian variance")
  look<-ind_gap_al_terms(y,f,S,eta$p,eta$sigma)$log_density
  ind_cfr_require(all(is.finite(look)),"nonfinite adapted lookahead")
  lw<-log(state$weights)+look;hi<-max(lw);logZ<-hi+log(sum(exp(lw-hi)))
  ancestor_weights<-exp(lw-logZ)
  A<-ind_caf_systematic_indices(ancestor_weights,innovations$ancestor)
  proposal<-ind_baf_al_propose(y,f[A],S[A],eta$p,eta$sigma,innovations$proposal)
  mn<-matrix(0,p,N);Cn<-array(0,c(p,p,N));residual<-numeric(N)
  for(i in seq_len(N)) {
    j<-A[i];Q<-S[j]+proposal$ex_q[i]
    ind_cfr_require(is.finite(Q)&&Q>0,"nonpositive adapted observation variance")
    mn[,i]<-a[,j]+RF[,j]*((y-f[j]-proposal$ex_f[i])/Q)
    Cn[,,i]<-sym(matrix(R[,,j],p,p)-tcrossprod(RF[,j])/Q)
    ind_caf_psd(matrix(Cn[,,i],p,p),p,policy$tolerance,"adapted updated covariance")
  }
  lr<-ind_aaf_logmean(residual);weights<-exp(residual-lr)/N
  ind_cfr_require(all(is.finite(c(mn,Cn,weights)))&&abs(sum(weights)-1)<=1e-10,
    "adapted residual weights or Gaussian update failed")
  ESS<-1/sum(weights^2);post<-ESS<policy$ess_fraction*N
  B<-if(post)ind_caf_systematic_indices(weights,innovations$residual_resampling)else seq_len(N)
  state$last_report<-list(observed_prefix_length=as.integer(time_index),
    parameter_id=policy$parameter_id,eta=eta,mean=mn,covariance=Cn,weights=weights,
    representation="weighted_pre_resampling",future_outcomes_used=0L,
    conditioning="fixed_static_parameter_observed_prefix_auxiliary_mixture",
    temporary_projected_location_assimilated=FALSE,
    approximation="ancestor_first_auxiliary_particle_filter_accuracy_unqualified",
    source_draw_inventory_authenticated=FALSE,production_authorized=FALSE)
  state$last_diagnostics<-list(time_index=as.integer(time_index),
    lookahead_ESS=1/sum(ancestor_weights^2),residual_ESS=ESS,
    selected_ancestor_count=length(unique(A)),ancestor_indices=A,
    ancestor_probabilities=ancestor_weights,post_resampled=post,post_indices=B,
    distinct_initial_lineages=length(unique(state$lineage[A[B]])),
    log_lookahead_normalizer=logZ,log_mean_residual_weight=lr,
    log_predictive_increment=logZ+lr,
    residual_weight_underflow_count=sum(is.finite(residual)&weights==0),
    proposal="fully_adapted_AL_ancestor_and_v",lookahead_is_exact=TRUE,
    numerical_accuracy_qualified=FALSE)
  state$mean<-mn[,B,drop=FALSE];state$covariance<-Cn[,,B,drop=FALSE]
  state$weights<-if(post)rep(1/N,N)else weights
  state$lineage<-state$lineage[A[B]];state$time_index<-as.integer(time_index)
  state
}

ind_baf_continue <- function(state,y,FF,GG,uniforms,time_indices,checkpoint_indices) {
  ind_aaf_check_state(state);n<-length(y);p<-nrow(state$mean);N<-state$particle_count
  ind_cfr_require(identical(state$identity$eta$family,"al")&&state$identity$eta$gamma==0,
    "batched continuation is AL-only")
  ind_cfr_require(is.numeric(y)&&n>=1L&&all(is.finite(y))&&is.matrix(FF)&&is.numeric(FF)&&
    identical(dim(FF),c(p,n))&&all(is.finite(FF))&&is.numeric(time_indices)&&
    identical(as.numeric(time_indices),as.numeric(state$time_index+seq_len(n)))&&
    is.numeric(checkpoint_indices)&&!anyNA(checkpoint_indices)&&!anyDuplicated(checkpoint_indices)&&
    !is.unsorted(checkpoint_indices)&&all(checkpoint_indices%in%time_indices),
    "contiguous causal continuation times and explicit checkpoints required")
  if(is.matrix(GG)) {
    ind_cfr_require(identical(dim(GG),c(p,p)),"invalid constant continuation evolution")
    GG<-array(rep(GG,n),c(p,p,n))
  }
  ind_cfr_require(is.numeric(GG)&&identical(dim(GG),c(p,p,n))&&all(is.finite(GG))&&
    is.list(uniforms)&&is.numeric(uniforms$proposal)&&
    identical(dim(uniforms$proposal),c(N,n,4L))&&length(uniforms$ancestor)==n&&
    length(uniforms$residual_resampling)==n&&is.null(uniforms$half_normal),
    "complete AL continuation geometry and streams required")
  checkpoints<-list();diagnostics<-vector("list",n)
  for(i in seq_len(n)) {
    innovation<-list(proposal=matrix(uniforms$proposal[,i,],N,4L),ancestor=uniforms$ancestor[i],
      residual_resampling=uniforms$residual_resampling[i],half_normal=NULL)
    state<-ind_baf_step(state,y[i],FF[,i],matrix(GG[,,i],p,p),innovation,time_indices[i])
    if(time_indices[i]%in%checkpoint_indices)checkpoints[[as.character(time_indices[i])]]<-state$last_report
    diagnostics[[i]]<-state$last_diagnostics
  }
  list(state=state,checkpoints=checkpoints,diagnostics=diagnostics,
    numerical_accuracy_qualified=FALSE,production_authorized=FALSE)
}
