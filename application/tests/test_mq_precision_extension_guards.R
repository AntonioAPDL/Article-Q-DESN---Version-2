# Synthetic early admission and baseline metadata failures; no model/RDS read.
source("scripts/qualify_mq_precision_extension.R")
pe_n <- 0L
pe_check <- function(x){stopifnot(isTRUE(x));pe_n <<- pe_n+1L}
pe_reject <- function(expr,text=NULL){e<-tryCatch({force(expr);NULL},error=identity)
  pe_check(inherits(e,"error")&&(is.null(text)||grepl(text,conditionMessage(e),fixed=TRUE)))}
set.seed(742280);pe_rng <- .Random.seed
help <- capture.output(mq_pe_main("--help"))
pe_check(length(help)==1L&&grepl("Usage:",help,fixed=TRUE))
pe_reject(mq_pe_main(character()),"exact contract/hash/execute arguments required")
unit <- list(schema_version="integrated_quantile_qualification_contract_v1",purpose="MQ_Q2_ONE_DRAW_ORIGIN",
  source_schema="mq_native_worker_v1",model_cell_id="asymmetric_laplace_tail__joint_qdesn_rhs",
  chain_id=1L,source_row=1L,source_draw_index=1L,origin_id=1L,origin_time=11000L,
  horizons=30L,inner_paths=4096L,readout_slopes=20L,tau=c(.05,.10,.25,.50,.75,.90,.95),
  posterior_target_sha256="45ffff64921e5985546d174cb28f44441c161fac3d13de3e8f4d65e67a17ab1c",
  rng_namespace="synthetic_original_scientific_identity",
  integration_accuracy=list(method="dkw_response_cdf",alpha_per_shard=.05,
    max_split_absolute=.005,max_split_relative=.005,max_quantile_abs_error=.01,max_quantile_rel_error=.01))
zero <- paste(rep("0",64),collapse="")
pin <- function(path,sha=zero)list(path=path,size_bytes=0,sha256=sha)
root <- tempfile("synthetic_mq_precision_");dir.create(root)
base <- file.path(root,"old_output");dir.create(base)
source_manifest <- pin(file.path(root,"docs/reproducibility/integrated_forecast_transition_sources_20261031.csv"))
original_contract <- pin(file.path(root,"original.json"))
native_rng <- pin(file.path(root,"RNG.c"),"6ef2c5d552c087cd57e0ef49386e01e0174b40433e4ad8d572461b20c958450e")
baseline <- list(schema_version="mq_batch_acceleration_qualification_v1",allow_qualification=TRUE,
  allow_refit=FALSE,allow_production=FALSE,allow_scoring=FALSE,allow_article=FALSE,
  training_paths=4096L,validation_paths=32768L,batch_size=128L,inversion_tolerance=1e-8,
  parity_absolute_tolerance=1e-10,parity_relative_tolerance=1e-10,rng_backend="r46_first_step",
  original_unit=unit,original_unit_contract=original_contract,native_rng_source=native_rng,source_manifest=source_manifest,
  source_commit="a099aba928e6d1fb01931a4b12466125bbb2bc64",source_tree="48b8baa236859f9f32969593101c75ff45bfa88c",
  output_root=base,source_files=lapply(1:10,function(i)pin(file.path(root,paste0("source_",i,".R")))),
  limits=list(cpu_seconds=600L,wall_term_seconds=899L,wall_kill_after_seconds=1L,
    address_space_bytes=16*1024^3,output_bytes=256*1024^2))
spec <- list(schema_version="mq_precision_extension_qualification_v1",allow_qualification=TRUE,
  allow_refit=FALSE,allow_production=FALSE,allow_scoring=FALSE,allow_article=FALSE,
  training_paths=65536L,validation_paths=262144L,batch_size=128L,
  training_path_range=c(1L,65536L),validation_path_range=c(65537L,327680L),
  validation_look_sizes=c(65536L,131072L,262144L),total_alpha=.05,alpha_per_look=rep(.05/3,3),
  parity_path_ids=c(1,2,63,64,127,128,4095,4096,4097,8192,16384,32768,65535,65536,65537,327680),
  stop_before_validation_on_split_failure=TRUE,
  parity_ordering="training_ids_before_training_validation_ids_after_candidate_freeze_and_split_pass",
  retention_policy="compressed_training_arrays_and_streaming_Welford_block_receipts_no_validation_raw_matrix",
  inversion_tolerance=1e-8,parity_absolute_tolerance=1e-10,parity_relative_tolerance=1e-10,
  rng_backend="r46_first_step",original_unit=unit,original_unit_contract=original_contract,
  native_rng_source=native_rng,source_manifest=source_manifest,
  source_commit=paste(rep("0",40),collapse=""),source_tree=paste(rep("0",40),collapse=""),
  baseline_contract=pin(file.path(root,"baseline.json"),"c1490494d4307cf29ea74f3c002e765ecb790486fe4fad24c0bf04b65a9df4e6"),
  baseline_receipt=pin(file.path(base,"qualification.json"),"bffaeb83b8f341603542965cecb877a865f5b152d0b16ac4e872dc11c6b6a1cf"),
  baseline_manifest=pin(file.path(base,"artifact_manifest.csv"),"3cca4efe27ede0759d643b560259336c16492c3dce5b87188927f043be9053da"),
  baseline_output_root=base,
  limits=list(cpu_seconds=1800L,wall_term_seconds=2399L,wall_kill_after_seconds=1L,
    address_space_bytes=16*1024^3,output_bytes=256*1024^2))
pe_check(isTRUE(mq_pe_scope(spec)))
pe_check(identical(mq_pe_parity_ids(spec,FALSE,FALSE),as.integer(spec$parity_path_ids[1:14])))
pe_check(all(mq_pe_parity_ids(spec,FALSE,FALSE)<=65536L))
pe_check(identical(mq_pe_parity_ids(spec,TRUE,TRUE),c(65537L,327680L)))
pe_check(identical(mq_pe_parity_ids(spec,TRUE,FALSE),integer()))
pe_reject(mq_pe_parity_ids(spec,FALSE,TRUE),"valid prospective parity phase")
pe_reject(mq_pe_parity_ids(spec,NA,FALSE),"valid prospective parity phase")
# The literal timeout parser independently enforces the complete external
# TERM/KILL envelope; q2_limits' weaker duration-only check is not substituted.
good_timeout<-c("/usr/bin/timeout","--signal=TERM","--kill-after=1s","2399s","taskset","-c","27","Rscript")
pe_check(isTRUE(mq_pe_timeout_argv(good_timeout)))
good_timeout[1L]<-"timeout";pe_check(isTRUE(mq_pe_timeout_argv(good_timeout)))
for(bad in list(
  c("timeout","--kill-after=1s","2399s","taskset"),
  c("timeout","--signal=TERM","2399s","taskset"),
  c("timeout","--signal=KILL","--kill-after=1s","2399s","taskset"),
  c("timeout","--signal=TERM","--kill-after=2s","2399s","taskset"),
  c("timeout","--signal=TERM","--kill-after=1s","2400s","taskset"),
  c("timeout","--signal=TERM","--kill-after=1s","2399","taskset"),
  c("timeout","--signal=TERM","--kill-after=1s","2399s","--foreground"),
  c("sleep","--signal=TERM","--kill-after=1s","2399s","taskset")
))pe_reject(mq_pe_timeout_argv(bad),"exact timeout TERM2399/KILL1 argv")
for(key in c("allow_refit","allow_production","allow_scoring","allow_article")){
  x<-spec;x[[key]]<-TRUE;pe_reject(mq_pe_scope(x),"qualification-only scope required")}
for(key in c("training_paths","validation_paths","batch_size","inversion_tolerance",
  "parity_absolute_tolerance","parity_relative_tolerance","total_alpha")){
  x<-spec;x[[key]]<-x[[key]]+.5;pe_reject(mq_pe_scope(x),"fixed prospective paths")}
for(key in c("training_path_range","validation_path_range","validation_look_sizes","alpha_per_look")){
  x<-spec;x[[key]][1L]<-x[[key]][1L]+1e-5;pe_reject(mq_pe_scope(x),"fixed prospective paths")}
x<-spec;x$validation_look_sizes<-c(65536L,262144L);pe_reject(mq_pe_scope(x),"fixed prospective paths")
x<-spec;x$rng_backend<-"native_different";pe_reject(mq_pe_scope(x),"fixed prospective paths")
x<-spec;x$parity_path_ids[16L]<-327681L;pe_reject(mq_pe_scope(x),"fixed prospective scalar/batch parity identities")
x<-spec;x$stop_before_validation_on_split_failure<-FALSE;pe_reject(mq_pe_scope(x),"prospective split-stop")
x<-spec;x$parity_ordering<-"all_validation_ids_before_training";pe_reject(mq_pe_scope(x),"prospective split-stop")
x<-spec;x$retention_policy<-"drop_old_evidence";pe_reject(mq_pe_scope(x),"prospective split-stop")
for(key in names(spec$limits)){
  x<-spec;x$limits[[key]]<-x$limits[[key]]+1;pe_reject(mq_pe_scope(x),"fixed finite extension budgets")}
for(key in c("alpha_per_shard","max_split_absolute","max_split_relative","max_quantile_abs_error","max_quantile_rel_error")){
  x<-spec;x$original_unit$integration_accuracy[[key]]<-x$original_unit$integration_accuracy[[key]]+1e-5
  pe_reject(mq_pe_scope(x),"original numerical thresholds must remain unchanged")}
for(key in c("baseline_contract","baseline_receipt","baseline_manifest")){
  x<-spec;x[[key]]$sha256<-zero;pe_reject(mq_pe_scope(x),"fixed v1 baseline")}

parity <- Map(function(field,n)list(field=field,values=n,maximum_absolute_difference=0,
  maximum_scaled_difference=0,pass=TRUE),
  c("recursive_responses","ordered_conditional_kernels","integrated_training_quantiles"),c(122880,860160,210))
receipt <- list(schema_version="mq_batch_acceleration_qualification_receipt_v1",
  source_commit=baseline$source_commit,source_tree=baseline$source_tree,
  purpose_contract_sha256=spec$baseline_contract$sha256,status="QUALIFICATION_COMPLETE_NOT_PRODUCTION",
  numerical_status="REVIEW_NUMERICAL_ACCURACY_NOT_QUALIFIED",
  original_legacy_numerical_status="REVIEW_INNER_INTEGRATION_RESOLUTION",
  old_failure_receipts_preserved=TRUE,thresholds_loosened=FALSE,
  production_authorized=FALSE,article_promotion_authorized=FALSE,parity=parity,
  original_unit=unit,original_unit_contract=original_contract,native_rng_source=native_rng,
  source_manifest=source_manifest,rng_backend="r46_first_step",
  observational_future_truth_used=FALSE,parameter_refits=0L,score_evaluations=0L)
pe_check(isTRUE(mq_pe_baseline_fields(spec,baseline,receipt)))
for(key in c("source_commit","source_tree")){
  b<-baseline;b[[key]]<-paste(rep("0",40),collapse="")
  pe_reject(mq_pe_baseline_fields(spec,b,receipt),"exact frozen v1 source")}
for(key in c("source_commit","source_tree","purpose_contract_sha256","status","numerical_status",
  "original_legacy_numerical_status")){
  r<-receipt;r[[key]]<-"wrong";pe_reject(mq_pe_baseline_fields(spec,baseline,r),"retained numerical REVIEW")}
for(key in c("old_failure_receipts_preserved","thresholds_loosened","production_authorized","article_promotion_authorized")){
  r<-receipt;r[[key]]<-!r[[key]];pe_reject(mq_pe_baseline_fields(spec,baseline,r),"retained numerical REVIEW")}
r<-receipt;r$parity[[1L]]$maximum_absolute_difference<-1e-16
pe_reject(mq_pe_baseline_fields(spec,baseline,r),"zero-difference parity")
r<-receipt;r$parity[[1L]]$values<-1
pe_reject(mq_pe_baseline_fields(spec,baseline,r),"zero-difference parity")
for(key in c("original_unit","original_unit_contract","native_rng_source","source_manifest","rng_backend")){
  x<-spec;x[[key]]<-NULL;pe_reject(mq_pe_baseline_fields(x,baseline,receipt),"identity changed")}
r<-receipt;r$observational_future_truth_used<-TRUE
pe_reject(mq_pe_baseline_fields(spec,baseline,r),"no refits")
r<-receipt;r$score_evaluations<-1L;pe_reject(mq_pe_baseline_fields(spec,baseline,r),"no refits")

# Wrong hash and source are rejected before any protected/RDS path is needed.
contract_path<-file.path(root,"extension.json")
jsonlite::write_json(spec,contract_path,auto_unbox=TRUE,pretty=TRUE,digits=17)
pe_reject(mq_pe_main(c("--contract",contract_path,"--sha256",zero,"--execute")),"bounded external purpose contract")
sha<-unname(tools::sha256sum(contract_path))
pe_reject(mq_pe_main(c("--contract",contract_path,"--sha256",sha,"--execute")),"clean frozen source commit/tree")

# Reach structural baseline checks using a cryptographic-pin mock and only
# synthetic text files. None of the .rds-named placeholders is ever decoded.
jsonlite::write_json(baseline,spec$baseline_contract$path,auto_unbox=TRUE,pretty=TRUE,digits=17)
jsonlite::write_json(receipt,spec$baseline_receipt$path,auto_unbox=TRUE,pretty=TRUE,digits=17)
names_out<-c("batch_training_result.rds","frozen_training_candidates.rds","independent_cdf_certificate.rds",
  "independent_cdf_endpoint_evidence.csv","independent_validation_cdf_matrix.rds","progress.json",
  "qualification.json","scalar_training_result.rds","structural_first_horizon_evidence.rds")
for(name in setdiff(names_out,"qualification.json"))writeLines("synthetic metadata placeholder",file.path(base,name))
artifact<-data.frame(relative_path=names_out,size_bytes=file.info(file.path(base,names_out))$size,sha256=zero)
artifact$sha256[artifact$relative_path=="qualification.json"]<-spec$baseline_receipt$sha256
write.csv(artifact,spec$baseline_manifest$path,row.names=FALSE)
mock_pin<-function(x)x$path
verify<-mq_pe_verify_baseline
guard_env<-new.env(parent=environment(verify));guard_env$readRDS<-function(...)stop("forbidden synthetic RDS read")
environment(verify)<-guard_env
# Actual CLI compares two parsed JSON contracts. Use the same representation
# here; json arrays are lists under simplifyVector=FALSE, not R vectors.
parsed_spec<-jsonlite::read_json(contract_path,simplifyVector=FALSE)
proof<-verify(parsed_spec,root,mock_pin)
pe_check(proof$files_verified==9L&&!proof$historical_outputs_copied)
x<-parsed_spec;x$baseline_output_root<-file.path(root,"elsewhere")
pe_reject(verify(x,root,mock_pin),"baseline retained output namespace")
bad<-artifact;bad$relative_path[1L]<-bad$relative_path[2L]
write.csv(bad,spec$baseline_manifest$path,row.names=FALSE)
pe_reject(verify(parsed_spec,root,mock_pin),"exact nine-file baseline artifact surface")
write.csv(artifact,spec$baseline_manifest$path,row.names=FALSE)
writeLines("unrelated",file.path(base,"extra.txt"))
pe_reject(verify(parsed_spec,root,mock_pin),"exact nine-file baseline artifact surface")
unlink(file.path(base,"extra.txt"))
bad<-artifact;bad$sha256[bad$relative_path=="qualification.json"]<-zero
write.csv(bad,spec$baseline_manifest$path,row.names=FALSE)
pe_reject(verify(parsed_spec,root,mock_pin),"manifest does not bind its exact receipt")
unlink(root,recursive=TRUE)
pe_check(identical(.Random.seed,pe_rng))
cat(sprintf("MQ_PRECISION_EXTENSION_GUARD_CHECKS=%d PASS; protected_reads=0 scientific_runs=0\n",pe_n))
