#!/usr/bin/env Rscript
# One externally admitted seed; all original failed evidence stays immutable.
source("scripts/ind_high_resolution_qualification.R",local=TRUE)
ind_hq_main <- function(args=commandArgs(TRUE)) {
 if(identical(args,"--help")) {
  cat("Usage: Rscript --vanilla scripts/qualify_ind_high_resolution_filter.R --contract FILE --sha256 SHA --execute\n")
  return(invisible(NULL))
 }
 q<-ind_hq_require
 q(length(args)==5L&&identical(args[c(1L,3L,5L)],c("--contract","--sha256","--execute")),
  "exact external purpose/hash/execute arguments required")
 for(p in c("digest","jsonlite","tools","compiler"))q(requireNamespace(p,quietly=TRUE),paste("required package",p))
 cp<-ind_aq_regular(args[2L]);q(file.info(cp)$size<=1024^2&&
  identical(unname(tools::sha256sum(cp)),args[4L]),"external purpose bytes differ")
 s<-jsonlite::read_json(cp,simplifyVector=FALSE);ind_hq_scope(s)
 root<-normalizePath(getwd(),mustWork=TRUE)
 q(!startsWith(cp,paste0(root,"/")),"purpose must be outside source checkout")
 expiry<-as.POSIXct(s$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
 q(!is.na(expiry)&&expiry>Sys.time()+5400,"purpose must cover full finite lifetime")
 q(identical(as.character(getRversion()),"4.6.0")&&"--vanilla"%in%commandArgs(FALSE)&&
  unname(Sys.info()[["nodename"]])%in%c("muscat","muscat.be.ucsc.edu")&&
  identical(normalizePath(R.home()),"/data/jaguir26/local/opt/R/4.6.0/lib64/R")&&
  Sys.getenv("LD_PRELOAD")==""&&all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1")&&
  Sys.getenv("R_LIBS_USER")=="/dev/null"&&Sys.getenv("R_LIBS_SITE")=="/dev/null"&&
  identical(normalizePath(.libPaths(),mustWork=TRUE),normalizePath(file.path(R.home(),"library"),mustWork=TRUE)),
  "native vanilla Muscat R4.6 core-only one-thread runtime required")
 q(identical(normalizePath(unname(extSoftVersion()[["BLAS"]]),mustWork=TRUE),
  normalizePath(file.path(R.home("lib"),"libRblas.so"),mustWork=TRUE)),"bundled BLAS required")
 timeout<-ind_hq_process_scope(s$limits);source_check<-ind_hq_source(s,root)
 runtime_manifest<-read.csv(ind_aq_pin(s$runtime_manifest),stringsAsFactors=FALSE)
 runtime<-ind_hq_runtime_inventory();ind_aq_runtime_match(runtime_manifest,runtime)
 previous_history<-ind_hq_previous_history(s)
 for(k in c("training_input","native_forward_receipt","native_forward_manifest","bootstrap_receipt",
  "historical_guided_receipt","native_cpp"))ind_aq_pin(s[[k]])
 ind_aq_pin(s$original_fit,max_bytes=611287756) # Hash only, never deserialize.
 native<-jsonlite::read_json(s$native_forward_receipt$path,simplifyVector=FALSE)
 old<-jsonlite::read_json(s$bootstrap_receipt$path,simplifyVector=FALSE)
 historical<-jsonlite::read_json(s$historical_guided_receipt$path,simplifyVector=FALSE)
 same_fit<-function(x)identical(x$path,s$original_fit$path)&&x$size_bytes==611287756&&
  identical(x$sha256,s$original_fit$sha256)
 q(identical(native$status,"NATIVE_FORWARD_PARITY_PASS")&&native$original_native_posterior_column==1L&&
  native$observed_training_rows==500L&&native$native_posterior_columns_present==20000L&&same_fit(native$original_fit)&&
  identical(native$original_fit_source,"c72e19f345da88fc1a8175ed30bdde328eab88be")&&
  identical(old$status,"QUALIFICATION_PROBE_COMPLETE_ACCURACY_NOT_CERTIFIED")&&same_fit(old$original_fit)&&
  identical(old$original_fit_source,"c72e19f345da88fc1a8175ed30bdde328eab88be")&&
  old$original_native_posterior_column==1L&&old$training_rows==500L&&old$native_posterior_columns_present==20000L&&
  identical(old$likelihood,"AL")&&old$p0==.05&&is.finite(old$sigma)&&old$sigma>0&&
  identical(historical$status,"QUALIFICATION_PROBE_COMPLETE_FILTER_ACCURACY_NOT_CERTIFIED")&&
  historical$descriptive_agreement_passes==13L&&historical$descriptive_agreement_rows==27L&&
  same_fit(historical$original_fit)&&historical$original_native_posterior_column==1L&&
  identical(native$native_cpp$sha256,s$native_cpp$sha256)&&identical(old$native_cpp$sha256,s$native_cpp$sha256),
  "frozen original static target and historical REVIEW evidence required")
 manifest<-read.csv(s$native_forward_manifest$path,stringsAsFactors=FALSE)
 q(all(c("relative_path","size_bytes","sha256")%in%names(manifest))&&!anyDuplicated(manifest$relative_path),
  "native proof manifest malformed")
 for(k in c("training_input","native_forward_receipt")) {
  row<-manifest[manifest$relative_path==basename(s[[k]]$path),,drop=FALSE]
  q(nrow(row)==1L&&row$size_bytes==s[[k]]$size_bytes&&row$sha256==s[[k]]$sha256,
   "source input/proof lacks native manifest binding")
 }
 output<-s$output_root;parent<-dirname(output)
 q(is.character(output)&&length(output)==1L&&!is.na(output)&&startsWith(output,paste0(root,"/local_trackers/"))&&
  !grepl("(^|/)\\.\\.(/|$)",output)&&!file.exists(output)&&dir.exists(parent)&&
  identical(normalizePath(parent,mustWork=TRUE),parent)&&
  system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(output)))==0L,
  "fresh ignored output namespace required")
 q(dir.create(output),"new output creation failed")
 oldkind<-RNGkind();had<-exists(".Random.seed",.GlobalEnv,inherits=FALSE)
 oldseed<-if(had)get(".Random.seed",.GlobalEnv)else NULL
 restore<-function() {
  do.call(RNGkind,as.list(oldkind))
  if(had)assign(".Random.seed",oldseed,.GlobalEnv)else if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)
 }
 on.exit(restore(),add=TRUE)
 reserve<-4*1024^2
 used<-function()sum(file.info(list.files(output,full.names=TRUE,all.files=TRUE,no..=TRUE))$size)
 write_json<-function(x,name) {
  file<-file.path(output,name);tmp<-paste0(file,".tmp")
  jsonlite::write_json(x,tmp,pretty=TRUE,auto_unbox=TRUE,digits=17,null="null")
  q(file.rename(tmp,file),"atomic JSON write failed")
 }
 seal<-function() {
  files<-list.files(output,full.names=TRUE,all.files=TRUE,no..=TRUE)
  q(all(!dir.exists(files))&&all(!nzchar(Sys.readlink(files))),"only direct regular output files allowed")
  files<-files[basename(files)!="artifact_manifest.csv"]
  m<-data.frame(relative_path=basename(files),size_bytes=as.numeric(file.info(files)$size),
   sha256=unname(tools::sha256sum(files)))
  q(sum(m$size_bytes)+reserve<s$limits$output_bytes,"complete packet exceeds finite output price")
  write.csv(m,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
  q(used()+reserve<=s$limits$output_bytes,"sealed packet exceeds finite output price")
  invisible(m)
 }
 save<-function(x,name) {
  file<-file.path(output,name);q(!file.exists(file),"existing evidence cannot be overwritten")
  # Conservative uncompressed bound before writing; gzip output is rechecked.
  raw_bytes<-length(serialize(x,NULL,version=3L))
  q(used()+raw_bytes+reserve+65536<s$limits$output_bytes,"reserved uncompressed output exceeds packet price")
  saveRDS(x,file,compress=TRUE,version=3L);seal();invisible(file)
 }
 progress<-function(phase,...)write_json(list(schema_version="ind_high_resolution_progress_v1",phase=phase,
  utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),seed=s$seed,
  source_commit=s$source_commit,purpose_contract_sha256=args[4L],production_authorized=FALSE,details=list(...)),"progress.json")
 before<-proc.time()
 progress("ADMITTED_ONE_STATIC_COLUMN_TRAINING_ONLY")
 write.csv(runtime,file.path(output,"runtime_strict_inventory_before.csv"),row.names=FALSE)
 write_json(list(role=attr(runtime,"observational_os_state_role"),
  observations=attr(runtime,"observational_os_state"),live_byte_equality_required=FALSE),"runtime_OS_before.json")
 tryCatch({
  input<-readRDS(s$training_input$path) # Sole original scientific RDS read.
  eta<-list(family="al",p=.05,sigma=old$sigma,gamma=0);ind_aq_truth_free_input(input,eta)
  constant_G<-if(is.matrix(input$GG))input$GG else matrix(input$GG[,,1L],6L,6L)
  RNGkind("Mersenne-Twister","Inversion","Rejection");set.seed(as.integer(s$seed))
  uniforms<-list(proposal=array(runif(8192L*500L*4L),c(8192L,500L,4L)),
   ancestor=runif(500L),residual_resampling=runif(500L))
  after_rng<-.Random.seed
  save(list(rng_namespace=s$rng_namespace,layout=s$rng_layout,seed=s$seed,kind=RNGkind(),
   uniforms=uniforms),"supplied_stream_max8192.rds")
  progress("NATIVE_PREFIX_SCALAR_BATCH_PARITY")
  small_u<-list(proposal=uniforms$proposal[1:64,1:8,,drop=FALSE],
   ancestor=uniforms$ancestor[1:8],residual_resampling=uniforms$residual_resampling[1:8])
  initial<-ind_aaf_initialize(input$m0,input$C0,input$df_mat,eta,64L,
   "c72e19f345da88fc1a8175ed30bdde328eab88be:native_column:1",ess_fraction=.5)
  tiny_G<-if(is.matrix(input$GG))input$GG else input$GG[,,1:8,drop=FALSE]
  scalar<-ind_aaf_continue(initial,input$y[1:8],input$FF[,1:8,drop=FALSE],tiny_G,small_u,1:8,8L)
  batch<-ind_baf_continue(initial,input$y[1:8],input$FF[,1:8,drop=FALSE],tiny_G,small_u,1:8,8L)
  q(isTRUE(ind_hq_arithmetic_parity(scalar,batch))&&
   identical(lapply(scalar$diagnostics,`[[`,"ancestor_indices"),lapply(batch$diagnostics,`[[`,"ancestor_indices"))&&
   identical(.Random.seed,after_rng),"native-prefix scalar/batch parity or RNG failed")
  write_json(list(status="PASS_NATIVE_PREFIX_ARITHMETIC_PARITY_ONLY",particles=64L,observations=8L,
   comparison_policy="elementwise_all_numeric_leaves_structure_exact",
   absolute_plus_relative_parity_tolerance=1e-10,ancestry_exact=TRUE,caller_RNG_unchanged=TRUE,
   numerical_accuracy_certified=FALSE,production_authorized=FALSE),"native_prefix_parity.json")
  rm(scalar,batch,small_u);gc(FALSE)
  records<-list();runs<-list()
  for(N in c(4096L,8192L)) {
   progress("FILTER_RUNNING",particles=N,completed_runs=length(runs))
   initial<-ind_aaf_initialize(input$m0,input$C0,input$df_mat,eta,N,
    "c72e19f345da88fc1a8175ed30bdde328eab88be:native_column:1",ess_fraction=.5)
   t0<-proc.time()
   fit<-ind_baf_continue(initial,input$y,input$FF,input$GG,
    list(proposal=uniforms$proposal[seq_len(N),,,drop=FALSE],ancestor=uniforms$ancestor,
     residual_resampling=uniforms$residual_resampling),1:500,c(100L,250L,500L))
   timing<-proc.time()-t0
   q(identical(.Random.seed,after_rng),"supplied-stream arithmetic changed caller RNG")
   for(tt in c(100L,250L,500L)) {
    components<-ind_gaf_origin_components(fit$checkpoints[[as.character(tt)]],
     input$FF[,min(tt+1L,500L)],constant_G,input$df_mat,"known_deterministic")
    qi<-ind_gap_mixture_quantile(c(.05,.5,.95),components$mean,components$variance,
     eta$p,eta$sigma,components$weight,1e-8,0)
    records[[length(records)+1L]]<-data.frame(seed=as.numeric(s$seed),particles=as.numeric(N),
     observed_prefix_length=as.numeric(tt),probability=c(.05,.5,.95),quantile=qi$result$quantile)
   }
   name<-sprintf("seed_%d_N_%05d.rds",s$seed,N);save(fit,name)
   runs[[as.character(N)]]<-list(seed=s$seed,particles=N,file=name,sha256=unname(tools::sha256sum(file.path(output,name))),
    CPU_seconds=sum(timing[c(1L,2L,4L,5L)]),wall_seconds=unname(timing["elapsed"]),
    minimum_lookahead_ESS=min(vapply(fit$diagnostics,`[[`,numeric(1L),"lookahead_ESS")),
    median_lookahead_ESS=median(vapply(fit$diagnostics,`[[`,numeric(1L),"lookahead_ESS")),
    minimum_selected_ancestors=min(vapply(fit$diagnostics,`[[`,integer(1L),"selected_ancestor_count")),
    residual_ESS_is_not_an_accuracy_certificate=TRUE)
   write.csv(do.call(rbind,records),file.path(output,"training_H1_quantiles.csv"),row.names=FALSE)
   seal();rm(fit);gc(FALSE)
  }
  quantiles<-do.call(rbind,records);comparisons<-ind_hq_comparisons(quantiles,FALSE)
  q(nrow(comparisons)==9L,"all nine predefined within-seed comparisons required")
  write.csv(comparisons,file.path(output,"within_seed_agreements.csv"),row.names=FALSE)
  final_source<-ind_hq_source(s,root)
  final_history<-ind_hq_previous_history(s)
  for(k in c("training_input","native_forward_receipt","native_forward_manifest","bootstrap_receipt",
   "historical_guided_receipt","native_cpp"))ind_aq_pin(s[[k]])
  ind_aq_pin(s$original_fit,max_bytes=611287756);ind_aq_pin(s$runtime_manifest)
  final_runtime<-ind_hq_runtime_inventory()
  write.csv(final_runtime,file.path(output,"runtime_strict_inventory_after.csv"),row.names=FALSE)
  write_json(list(role=attr(final_runtime,"observational_os_state_role"),
   observations=attr(final_runtime,"observational_os_state"),live_byte_equality_required=FALSE),"runtime_OS_after.json")
  ind_aq_runtime_match(runtime_manifest,final_runtime)
  q(expiry>Sys.time()&&sum(proc.time()[c(1L,2L,4L,5L)])<=5400,
   "complete process CPU or purpose lifetime exceeded")
  restore()
  receipt<-list(schema_version="ind_high_resolution_filter_receipt_v1",
   status="BOUNDED_HIGH_RESOLUTION_AL_DIAGNOSTIC_COMPLETE_NOT_PRODUCTION",seed=s$seed,
   source_commit=s$source_commit,source_tree=s$source_tree,purpose_contract_sha256=args[4L],
   source_files=s$source_files,source_readback=final_source,method=s$method,arithmetic_backend=s$arithmetic_backend,
   rng_namespace=s$rng_namespace,rng_layout=s$rng_layout,maximum_stream_particles=8192L,
   original_fit=s$original_fit,original_fit_deserialized=FALSE,training_input=s$training_input,
   posterior_column=1L,observed_prefix_length=500L,eta=eta,run_receipts=runs,
   original_scalar_reference_unchanged=TRUE,native_prefix_parity_pass=TRUE,
   predeclared_within_seed_agreements=9L,within_seed_passes=sum(comparisons$agreement),
   within_seed_status=if(all(comparisons$agreement))"PASS_DESCRIPTIVE_AGREEMENT_ONLY"else"REVIEW",
   between_seed_largest_resolution_comparison_required=TRUE,
   historical_failed_attempts_relabelled=FALSE,old_20of27_still_REVIEW=TRUE,
   previous_failed_history=previous_history,final_previous_failed_history=final_history,
   runtime_manifest=s$runtime_manifest,runtime_verified=TRUE,timeout_boundary=timeout,limits=s$limits,
   process_CPU_seconds_before_terminal_receipt=sum(proc.time()[c(1L,2L,4L,5L)]),
   numerical_phase_CPU_seconds=sum((proc.time()-before)[c(1L,2L,4L,5L)]),
   caller_RNG_restored=TRUE,whole_purpose_external_accounting_required=TRUE,
   filter_accuracy_certified=FALSE,future_integration_accuracy_certified=FALSE,
   full_IF01_or_production_qualified=FALSE,outer_parameter_weights_updated=FALSE,
   future_truth_deserialized=FALSE,new_parameter_fits=0L,score_evaluations=0L,
   production_authorized=FALSE,article_promotion_authorized=FALSE)
  write_json(receipt,"qualification.json");progress("COMPLETE_NOT_PRODUCTION",within_seed_status=receipt$within_seed_status)
  seal();cat("IND_HIGH_RESOLUTION_DIAGNOSTIC_COMPLETE_NOT_PRODUCTION\n")
  invisible(receipt)
 },error=function(e) {
  try(write_json(list(status="FAILED_HIGH_RESOLUTION_DIAGNOSTIC_NOT_PRODUCTION",error=conditionMessage(e),
   source_commit=s$source_commit,purpose_contract_sha256=args[4L],production_authorized=FALSE),"failure.json"),silent=TRUE)
  try(progress("FAILED_NOT_PRODUCTION",error=conditionMessage(e)),silent=TRUE)
  try(seal(),silent=TRUE);stop(e)
 })
}
if(sys.nframe()==0L)ind_hq_main()
