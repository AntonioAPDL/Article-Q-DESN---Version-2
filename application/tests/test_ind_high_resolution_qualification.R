source("scripts/qualify_ind_high_resolution_filter.R")
ncheck<-0L
check<-function(x){stopifnot(isTRUE(x));ncheck<<-ncheck+1L}
reject<-function(expr) {
 e<-tryCatch({force(expr);NULL},error=identity)
 check(inherits(e,"error"))
}
toy<-list(mean=c(0,1),covariance=diag(2),checkpoints=list("8"=list(weights=c(.25,.75))),
 ancestry=1:2,scope="arithmetic_only")
check(ind_hq_arithmetic_parity(toy,toy))
near<-toy;near$mean[2]<-near$mean[2]+1e-12;check(ind_hq_arithmetic_parity(toy,near))
bad<-toy;bad$mean[2]<-bad$mean[2]+1e-5;reject(ind_hq_arithmetic_parity(toy,bad))
bad<-toy;bad$covariance[2,1]<-1e-5;reject(ind_hq_arithmetic_parity(toy,bad))
bad<-toy;bad$checkpoints[[1]]$weights[1]<-.3;reject(ind_hq_arithmetic_parity(toy,bad))
bad<-toy;bad$ancestry<-2:1;reject(ind_hq_arithmetic_parity(toy,bad))
bad<-toy;names(bad$mean)<-c("a","b");reject(ind_hq_arithmetic_parity(toy,bad))
bad<-toy;bad$extra<-TRUE;reject(ind_hq_arithmetic_parity(toy,bad))
check(ind_hq_arithmetic_parity(list(value=c(Inf,-Inf,NA_real_)),list(value=c(Inf,-Inf,NA_real_))))
reject(ind_hq_arithmetic_parity(list(value=Inf),list(value=-Inf)))
# Exercise the same recursive comparator over actual generated filter objects.
nu<-list(proposal=array(seq(.01,.99,length.out=16L*3L*4L),c(16L,3L,4L)),
 ancestor=rep(.5,3L),residual_resampling=rep(.5,3L))
st<-ind_aaf_initialize(c(0,0),diag(2),diag(rep(.2,2)),
 list(family="al",p=.05,sigma=.7,gamma=0),16L,"generated_native_prefix_parity")
ref<-ind_aaf_continue(st,c(1,-4,2),matrix(rep(c(1,0),3L),2L),diag(2),nu,1:3,c(1L,3L))
bat<-ind_baf_continue(st,c(1,-4,2),matrix(rep(c(1,0),3L),2L),diag(2),nu,1:3,c(1L,3L))
check(ind_hq_arithmetic_parity(ref,bat))
bad<-bat;bad$checkpoints[["3"]]$covariance[1,1,1]<-bad$checkpoints[["3"]]$covariance[1,1,1]+1e-5
reject(ind_hq_arithmetic_parity(ref,bad))
pin<-function(sha,n=0)list(path="/not-an-authentic-input",size_bytes=n,sha256=sha)
s<-list(schema_version="ind_high_resolution_AL_filter_contract_v1",
 purpose="ONE_PREDECLARED_SEED_TWO_HIGHER_RESOLUTIONS_NO_REFIT",allow_diagnostic=TRUE,
 allow_refit=FALSE,allow_production=FALSE,allow_scoring=FALSE,allow_article=FALSE,
 particle_resolutions=c(4096L,8192L),maximum_stream_particles=8192L,seed=71521L,
 posterior_column=1L,observed_prefix_length=500L,checkpoint_indices=c(100L,250L,500L),
 probabilities=c(.05,.5,.95),ess_fraction=.5,inversion_absolute_tolerance=1e-8,
 agreement_absolute_tolerance=.005,agreement_relative_tolerance=.005,
 method="ancestor_first_AL_exact_v_v1",arithmetic_backend="batched_AL_scalar_equivalent_v1",
 rng_namespace="ind_ancestor_first_AL_high_resolution_max8192_v1",
 rng_layout="Mersenne_Twister_max8192_time_major_proposal4_then_ancestor_then_residual_v1",
 limits=list(cpu_seconds=5400L,wall_term_seconds=5399L,wall_kill_after_seconds=1L,
  address_space_bytes=2*1024^3,output_bytes=256*1024^2,logical_cpu=26L),
 training_input=pin("d38bd5f49744c67861908f8fd960781bf97efdf1c43473829b46894574252496",13728),
 native_forward_receipt=pin("440da6c4d71554952947b128c77758f86aea385c7cb3ceb203ddad5ff5737bff"),
 bootstrap_receipt=pin("b14b6ea359d6f48f37134d40e87ca2d37f8dd33d954c5c59f479352fa495e599"),
 historical_guided_receipt=pin("ce2b82b96b57de42cedd3f856f5f630e4f9387d70d9219edb47db28b64a1a2b2"),
 original_fit=pin("1e8ba3de4a6c9e9e0f6bd900be7801e8c80fe0fdff4b6ca24804bdc62e3ff17f",611287756),
 native_cpp=pin("f6ccf41466ece60a3a63737bb434309e8bea59f5b254a086793e5cca0aba6065"),
 previous_attempt_terminal=pin("d3d188cf8bb796594702c5464b2816f2092d7bddbd81bb4bcbf7282af0783e29"),
 previous_attempt_manifest=pin("91430b6e8a68ae0ecbcd4cfdcb15d1dadaf7991311ec09f7d9a16b3168218f29"),
 previous_attempt_agreements=pin("33afc10cec68c77fddd6b5998e26c3be5ff67d3ca5105f1f8e72e4a0234a2978"),
 source_commit=strrep("a",40L),source_tree=strrep("b",40L),
 origin_remote_url="git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git",
 published_ref="refs/heads/work/ind-filter-qualification-followup-20261102")
check(ind_hq_scope(s))
b<-s;b$seed<-71522L;b$limits$logical_cpu<-27L;check(ind_hq_scope(b))
for(k in c("allow_refit","allow_production","allow_scoring","allow_article")) {
 b<-s;b[[k]]<-TRUE;reject(ind_hq_scope(b))
}
for(k in c("particle_resolutions","maximum_stream_particles","posterior_column","observed_prefix_length",
 "checkpoint_indices","probabilities","ess_fraction","inversion_absolute_tolerance",
 "agreement_absolute_tolerance","agreement_relative_tolerance")) {
 b<-s;b[[k]]<-b[[k]]+1;reject(ind_hq_scope(b))
}
for(k in c("method","arithmetic_backend","rng_namespace","rng_layout","schema_version","purpose","origin_remote_url")) {
 b<-s;b[[k]]<-"undeclared";reject(ind_hq_scope(b))
}
for(k in names(s$limits)) {
 b<-s;b$limits[[k]]<-b$limits[[k]]+1;reject(ind_hq_scope(b))
}
b<-s;b$seed<-12345L;reject(ind_hq_scope(b))
b<-s;b$seed<-71522L;reject(ind_hq_scope(b))
for(k in c("training_input","native_forward_receipt","bootstrap_receipt","historical_guided_receipt","original_fit","native_cpp",
 "previous_attempt_terminal","previous_attempt_manifest","previous_attempt_agreements")) {
 b<-s;b[[k]]$sha256<-strrep("0",64L);reject(ind_hq_scope(b))
}
for(ref in c("HEAD","refs/heads/a..b","refs/heads/a//b","refs/heads/a/")) {
 b<-s;b$published_ref<-ref;reject(ind_hq_scope(b))
}
check(ind_hq_timeout_argv(c("/usr/bin/timeout","--signal=TERM","--kill-after=1s","5399s","Rscript")))
for(argv in list(c("timeout","--signal=KILL","--kill-after=1s","5399s","Rscript"),
 c("timeout","--signal=TERM","--kill-after=2s","5399s","Rscript"),
 c("timeout","--signal=TERM","--kill-after=1s","5400s","Rscript"),
 c("timeout","--signal=TERM","--kill-after=1s","5399s","--foreground")))reject(ind_hq_timeout_argv(argv))
check(length(ind_hq_required_sources())==11L&&!anyDuplicated(ind_hq_required_sources()))
q<-expand.grid(seed=c(71521,71522),particles=c(4096,8192),observed_prefix_length=c(100,250,500),
 probability=c(.05,.5,.95),KEEP.OUT.ATTRS=FALSE)
q$quantile<-200+q$probability*100+q$observed_prefix_length/100+
 (q$seed-71521)*.001+as.numeric(q$particles==8192)*.002
check(ind_hq_quantile_rows(q,TRUE))
a<-ind_hq_comparisons(q,TRUE)
check(nrow(a)==27L&&all(a$agreement))
check(sum(a$seed_A!=a$seed_B)==9L&&all(a$N_A[a$seed_A!=a$seed_B]==8192))
check(nrow(ind_hq_comparisons(q[q$seed==71521,],FALSE))==9L)
for(mut in list(function(x)x[-1L,],function(x)rbind(x,x[1L,]),
 function(x){x$particles[1L]<-1024;x},function(x){x$seed[1L]<-12345;x},
 function(x){x$probability[1L]<-.1;x},function(x){x$quantile[1L]<-NA_real_;x},
 function(x){x$quantile<-as.character(x$quantile);x}))reject(ind_hq_quantile_rows(mut(q),TRUE))
bad<-q;bad$quantile[bad$probability==.05]<-999;reject(ind_hq_quantile_rows(bad,TRUE))
bad<-q;at<-bad$seed==71522&bad$particles==8192&bad$observed_prefix_length==500&bad$probability==.05
bad$quantile[at]<-bad$quantile[at]+10
check(sum(!ind_hq_comparisons(bad,TRUE)$agreement)==2L)
reject(ind_hq_quantile_rows(q,FALSE));reject(ind_hq_quantile_rows(q,NA))

receipt<-list(schema_version="ind_high_resolution_filter_receipt_v1",
 status="BOUNDED_HIGH_RESOLUTION_AL_DIAGNOSTIC_COMPLETE_NOT_PRODUCTION",seed=71521L,
 source_commit=s$source_commit,source_tree=s$source_tree,purpose_contract_sha256=strrep("c",64L),
 method=s$method,arithmetic_backend=s$arithmetic_backend,rng_namespace=s$rng_namespace,rng_layout=s$rng_layout,
 maximum_stream_particles=8192L,posterior_column=1L,observed_prefix_length=500L,
 predeclared_within_seed_agreements=9L,within_seed_passes=9L,
 run_receipts=list(`4096`=list(),`8192`=list()),training_input=s$training_input,original_fit=s$original_fit,
 eta=list(family="al",p=.05,sigma=.7,gamma=0),original_scalar_reference_unchanged=TRUE,
 native_prefix_parity_pass=TRUE,runtime_verified=TRUE,caller_RNG_restored=TRUE,
 original_fit_deserialized=FALSE,filter_accuracy_certified=FALSE,future_integration_accuracy_certified=FALSE,
 full_IF01_or_production_qualified=FALSE,outer_parameter_weights_updated=FALSE,future_truth_deserialized=FALSE,
 production_authorized=FALSE,article_promotion_authorized=FALSE)
terminal<-list(status="EXECUTION_COMPLETE_NOT_PRODUCTION",source_commit=s$source_commit,source_tree=s$source_tree,
 purpose_sha256=receipt$purpose_contract_sha256,payload_exit_code=0,payload_user_cpu_seconds=100,
 payload_system_cpu_seconds=1,production_authorized=FALSE,article_promotion_authorized=FALSE)
r2<-receipt;r2$seed<-71522L;r2$purpose_contract_sha256<-strrep("d",64L)
t2<-terminal;t2$purpose_sha256<-r2$purpose_contract_sha256
aggregate<-ind_hq_aggregate_metadata(q,list(receipt,r2),list(terminal,t2))
check(identical(aggregate$status,"PASS_27_DESCRIPTIVE_AGREEMENTS_ONLY")&&aggregate$passed==27L&&
 !aggregate$filter_accuracy_certified&&!aggregate$production_authorized)
for(field in c("runtime_verified","native_prefix_parity_pass","caller_RNG_restored")) {
 b<-r2;b[[field]]<-FALSE;reject(ind_hq_aggregate_metadata(q,list(receipt,b),list(terminal,t2)))
}
for(field in c("filter_accuracy_certified","future_integration_accuracy_certified","production_authorized",
 "outer_parameter_weights_updated","original_fit_deserialized","future_truth_deserialized")) {
 b<-r2;b[[field]]<-TRUE;reject(ind_hq_aggregate_metadata(q,list(receipt,b),list(terminal,t2)))
}
b<-r2;b$source_commit<-strrep("f",40L);reject(ind_hq_aggregate_metadata(q,list(receipt,b),list(terminal,t2)))
b<-r2;b$seed<-71521L;reject(ind_hq_aggregate_metadata(q,list(receipt,b),list(terminal,t2)))
b<-r2;b$within_seed_passes<-8L;reject(ind_hq_aggregate_metadata(q,list(receipt,b),list(terminal,t2)))
b<-t2;b$payload_exit_code<-1;reject(ind_hq_aggregate_metadata(q,list(receipt,r2),list(terminal,b)))
b<-t2;b$payload_user_cpu_seconds<-5400;reject(ind_hq_aggregate_metadata(q,list(receipt,r2),list(terminal,b)))
b<-t2;b$status<-"EXECUTION_NOT_ACCEPTED";reject(ind_hq_aggregate_metadata(q,list(receipt,r2),list(terminal,b)))
b<-t2;b$purpose_sha256<-strrep("e",64L);reject(ind_hq_aggregate_metadata(q,list(receipt,r2),list(terminal,b)))
reject(ind_hq_main(character()))
help<-capture.output(ind_hq_main("--help"));check(length(help)==1L&&grepl("--vanilla",help,fixed=TRUE))
cat(sprintf("IND_HIGH_RESOLUTION_GUARDS=%d PASS; generated_only=TRUE actual_purposes=0 authentic_reads=0\n",ncheck))
