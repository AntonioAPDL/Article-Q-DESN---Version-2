#!/usr/bin/env Rscript
# New admission only: two original reads and one generated numeric-array read.
# Reuse old pure/read helpers explicitly; never override a historical reader.
source("scripts/glofas_al_conditional_reference_reader.R")
source("scripts/diagnostics/glofas_reference_recovery_kernels.R")

grrr_sources <- function() unique(c(gacr_sources(),
  "scripts/glofas_reference_recovery_reader.R", "scripts/diagnostics/glofas_reference_recovery_kernels.R",
  "scripts/run_glofas_reference_recovery.py"))
grrr_kernels <- function() c("calibrated_random_walk", "mixture_random_walk_student_t")
grrr_no_link <- function(path) {link<-Sys.readlink(path);is.na(link)||!nzchar(link)}
grrr_cost <- function(s) {
  original<-sum(vapply(s[c("design","median_model")],function(p)p$size_bytes,numeric(1L)))
  generated<-s$calibration_draws$size_bytes;total<-original+generated;r<-s$read_budget
  gfr_require(r$max_RDS_deserializations==2L&&r$max_generated_RDS_deserializations==1L&&
    total<=r$max_deserialization_bytes&&2*total<=r$max_payload_hash_bytes,
    "exact two-original plus one-generated read and before/after hash allowance required")
  list(original_RDS_deserializations=2L,generated_numeric_array_deserializations=1L,
    original_deserialization_bytes=original,generated_deserialization_bytes=generated,
    deserialization_bytes=total,payload_hash_bytes=2*total)
}
grrr_scope <- function(s) {
  q<-gfr_require;gst_unique_objects(s)
  yes<-c("allow_original_reads","allow_generated_numeric_array_read","allow_fresh_source_feature_evaluation",
    "allow_metadata_serialization","allow_proposal_calibration","allow_fixed_parameter_path_sampling","allow_raw_draw_export")
  no<-c("allow_saved_callbacks","allow_parameter_updates","allow_prior_updates","allow_full_parameter_refit",
    "allow_truth_read","allow_retuning","allow_scoring","allow_article_changes","allow_publication",
    "allow_derived_context_serialization")
  fields<-c("schema_version","purpose","mode","execution_mode","nonce","expires_utc","source_root",
    "source_commit","source_tree","source_files","expected_identity","collection","input_manifest",
    "design","median_model","prior_replay","baseline","calibration_draws","diagnostic_dependencies",
    "read_budget","limits","output_root","metadata_scratch_root","metadata_serialization","recovery","draw_export",yes,no)
  q(is.list(s)&&length(s)==length(fields)&&setequal(names(s),fields)&&
    identical(s$schema_version,"glofas_reference_recovery_contract_v1")&&
    identical(s$purpose,"MEDIAN_AL_FIXED_PARAMETER_TWO_ARM_KERNEL_RECOVERY_PILOT_NO_FULL_REFIT")&&
    identical(s$mode,"computational_pilot")&&identical(s$execution_mode,"fork_eight")&&
    all(vapply(s[yes],isTRUE,logical(1L)))&&all(vapply(s[no],identical,logical(1L),FALSE)),
    "exact separate recovery pilot purpose and prohibitions required")
  q(is.character(s$nonce)&&length(s$nonce)==1L&&grepl("^[a-f0-9]{32,64}$",s$nonce)&&
    all(vapply(s[c("source_commit","source_tree")],function(x)is.character(x)&&length(x)==1L&&
      grepl("^[a-f0-9]{40}$",x),logical(1L)))&&gst_same(s$expected_identity,gsc_identity()),
    "complete recovery/frozen producer identities required")
  for(p in s[c("design","median_model","calibration_draws")])gfr_pin_shape(p,8*1024^3)
  for(p in s[c("collection","input_manifest")])gfr_pin_shape(p,4*1024^2)
  q(s$design$size_bytes==4014834693&&s$median_model$size_bytes==137820489&&
    identical(s$design$sha256,"193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3")&&
    identical(s$median_model$sha256,"f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881")&&
    identical(basename(s$design$path),"shared_truth_free_design.rds")&&
    identical(basename(s$median_model$path),"fit.rds")&&
    identical(s$input_manifest$sha256,gsc_identity()$input_manifest_sha256)&&
    s$calibration_draws$size_bytes==17920074&&
    identical(s$calibration_draws$sha256,"41d4ad60c62f130e7cc03ecd2c4cdeafedd8671688c20ba371147bbf471060be")&&
    identical(basename(s$calibration_draws$path),"conditional_reference_draws.rds"),
    "exact frozen original inputs and generated calibration array required")
  gacr_pin_list(s$prior_replay,c("receipt","manifest","summary","terminal"))
  gacr_pin_list(s$baseline,c("receipt","manifest","summary","terminal"))
  q(identical(s$baseline$terminal$sha256,"239fab60c9590315d753a4d743fd830e276921f2d5cc78ab3f4902d1c9cf51d7"),
    "exact independently closed unqualified baseline required")
  dep<-s$diagnostic_dependencies
  q(is.list(dep)&&setequal(names(dep),c("library_root","versions","sources"))&&
    is.character(dep$library_root)&&length(dep$library_root)==1L&&startsWith(dep$library_root,"/"),
    "isolated diagnostic dependency library required")
  for(p in dep[c("versions","sources")])gfr_pin_shape(p,4*1024^2)
  b<-s$limits;keys<-c("cpu_seconds","wall_seconds","memory_bytes","output_bytes","logical_cpu","max_workers",
    "child_logical_cpus","child_cpu_seconds","aggregate_cpu_seconds","aggregate_memory_bytes",
    "memory_headroom_bytes","max_draw_memory_bytes")
  q(is.list(b)&&setequal(names(b),keys)&&all(vapply(b[setdiff(keys,"child_logical_cpus")],gfr_scalar_integer,logical(1L)))&&
    b$cpu_seconds>=60&&b$cpu_seconds<=3600&&b$wall_seconds>=b$cpu_seconds&&b$wall_seconds<=3600&&
    b$memory_bytes==16*1024^3&&b$output_bytes>0&&b$output_bytes<=64*1024^2&&b$logical_cpu%in%c(20,26)&&
    b$max_workers==8L&&identical(as.numeric(unlist(b$child_logical_cpus)),c(20,21,22,23,26,27,28,29))&&
    b$child_cpu_seconds==b$cpu_seconds&&
    b$aggregate_cpu_seconds>=b$cpu_seconds+8*b$child_cpu_seconds&&
    b$aggregate_memory_bytes>=9*b$memory_bytes&&b$memory_headroom_bytes>=180*1024^3&&
    b$max_draw_memory_bytes>=8*1000*4*28*8&&b$max_draw_memory_bytes<=128*1024^2,
    "explicit eight-child native CPU and 144GiB aggregate/180GiB headroom allocation required")
  r<-s$read_budget;keys<-c("max_payload_hash_bytes","max_deserialization_bytes","max_RDS_deserializations",
    "max_generated_RDS_deserializations","max_metadata_bytes","max_recovery_output_bytes")
  q(is.list(r)&&setequal(names(r),keys)&&all(vapply(r,gfr_scalar_integer,logical(1L)))&&all(unlist(r)>0)&&
    r$max_payload_hash_bytes<=48*1024^3&&r$max_deserialization_bytes<=24*1024^3&&
    r$max_metadata_bytes<=64*1024^2&&r$max_recovery_output_bytes<=10*1024^2,
    "finite read and compact recovery output caps required")
  d<-s$draw_export;m<-s$metadata_serialization
  q(is.list(d)&&setequal(names(d),c("filenames","role","max_bytes","serialization_version","numeric_array_only"))&&
    identical(as.character(unlist(d$filenames)),paste0(grrr_kernels(),"_draws.rds"))&&
    identical(d$role,"generated_fixed_parameter_conditional_path_draws_not_full_posterior")&&
    gfr_scalar_integer(d$max_bytes)&&d$max_bytes>=1000*4*28*8+1024&&d$max_bytes<=16*1024^2&&
    d$serialization_version==3L&&isTRUE(d$numeric_array_only)&&is.list(m)&&
    setequal(names(m),c("max_files","max_file_bytes","max_total_bytes"))&&
    all(vapply(m,gfr_scalar_integer,logical(1L)))&&all(unlist(m)>0)&&m$max_files<=64L&&
    m$max_file_bytes<=4*1024^2&&m$max_total_bytes<=32*1024^2&&
    m$max_total_bytes+r$max_recovery_output_bytes+2*d$max_bytes+131072<=b$output_bytes,
    "two bounded numeric pilot arrays and metadata budget required")
  c<-s$recovery;keys<-c("likelihood_family","tau","parameter_rule","scale_rule","calibration_role","proposal_rule",
    "start_rule","value_backend","max_total_value_evaluations","max_jacobian_evaluations","parity_evaluations",
    "setup_value_evaluations","minimum_tail_seconds","progress_every","qualification_scope","sampler","kernels","timing_basis")
  v<-c$sampler;vk<-c("warmup","samples","max_evaluations","max_wall_seconds","adapt_warmup","rhat_max","min_ess","max_quantile_mcse")
  timing<-c$timing_basis
  q(is.list(c)&&setequal(names(c),keys)&&identical(c$likelihood_family,"al")&&c$tau==.5&&
    identical(c$parameter_rule,"retained_theta_mean_fixed_coefficient_covariance_zero")&&
    identical(c$scale_rule,"reciprocal_retained_inverse_scale_means_not_scale_means")&&
    identical(c$calibration_role,"PROPOSAL_CALIBRATION_ONLY_NOT_QUALIFIED_REFERENCE")&&
    identical(c$proposal_rule,"pooled_baseline_path_draws_spd_calibration_only")&&
    identical(c$start_rule,"retained_m_minus_sd_plus_sd_and_reference_at_m_minus_sd_plus_sd")&&
    identical(c$value_backend,"compiled_input_reference")&&c$parity_evaluations==6L&&c$setup_value_evaluations==1L&&
    c$max_jacobian_evaluations==1L&&c$progress_every==250L&&c$minimum_tail_seconds>=120&&
    c$minimum_tail_seconds<=300&&identical(as.character(unlist(c$kernels)),grrr_kernels())&&
    identical(c$qualification_scope,"two_arm_computational_pilot_only_not_production_qualification")&&
    is.list(v)&&setequal(names(v),vk)&&v$warmup==500L&&v$samples==1000L&&
    v$max_evaluations==1501L&&v$max_wall_seconds>0&&v$max_wall_seconds+c$minimum_tail_seconds<b$wall_seconds&&
    isTRUE(v$adapt_warmup)&&v$rhat_max==1.01&&v$min_ess>=400&&v$max_quantile_mcse==.001&&
    gfr_scalar_integer(c$max_total_value_evaluations)&&c$max_total_value_evaluations>=7+8*v$max_evaluations&&
    c$max_total_value_evaluations<=20000,"fixed AL point and two-arm 500+1000 computational pilot only required")
  q(is.list(timing)&&setequal(names(timing),c("baseline_max_elapsed_seconds","baseline_callback_evaluations","safety_factor"))&&
    timing$baseline_max_elapsed_seconds>=17200&&timing$baseline_callback_evaluations==24001&&
    timing$safety_factor>=2&&timing$safety_factor<=4&&
    v$max_wall_seconds>=v$max_evaluations*timing$baseline_max_elapsed_seconds/
      timing$baseline_callback_evaluations*timing$safety_factor,
    "prospective completed-chain average-cost projection required, not a hard latency bound or warm timing alone")
  grrr_cost(s);invisible(TRUE)
}
grrr_source <- function(s) {
  root<-normalizePath(getwd(),mustWork=TRUE);q<-gfr_require
  git<-function(a){z<-system2("/usr/bin/git",c("--no-replace-objects","-c","core.fsmonitor=false",a),stdout=TRUE)
    q(is.null(attr(z,"status")),"recovery source Git check failed");unname(z)}
  q(identical(root,s$source_root)&&identical(git(c("rev-parse","--show-toplevel")),root)&&
    identical(git(c("rev-parse","HEAD")),s$source_commit)&&identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=all"))),"exact clean committed recovery source required")
  paths<-vapply(s$source_files,function(p){gfr_pin_shape(p,1024^2);p$path},character(1L))
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,grrr_sources())),"complete recovery runtime source closure required")
  for(p in s$source_files)gsc_pin(p,1024^2)
  for(rel in grrr_sources())q(identical(git(c("hash-object","--no-filters","--",shQuote(rel))),
    git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel))))),"recovery source differs from committed blob")
  for(rel in gnr_production_sources())q(identical(git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel)))),
    git(c("rev-parse",shQuote(paste0(gsc_identity()$source_commit,":",rel))))),"production blobs changed from frozen producer")
  invisible(root)
}
grrr_baseline_bind <- function(s,p) {
  q<-gfr_require;r<-p$receipt;t<-p$terminal;m<-p$manifest
  q(is.data.frame(m)&&identical(names(m),c("relative_path","size_bytes","sha256"))&&!anyDuplicated(m$relative_path)&&
    all(basename(m$relative_path)==m$relative_path),"bounded baseline manifest required")
  for(pin in c(s$baseline[c("receipt","summary")],list(s$calibration_draws))) {
    at<-which(m$relative_path==basename(pin$path))
    q(length(at)==1L&&m$size_bytes[at]==pin$size_bytes&&identical(m$sha256[at],pin$sha256)&&
      identical(dirname(pin$path),dirname(s$baseline$manifest$path)),"baseline artifacts/calibration are not manifest-bound")
  }
  q(identical(r$schema_version,"glofas_al_conditional_reference_receipt_v1")&&
    identical(t$schema_version,"glofas_al_conditional_reference_native_terminal_v1")&&
    identical(r$status,"INCONCLUSIVE_CONDITIONAL_REFERENCE")&&identical(p$summary$status,r$status)&&
    identical(r$mode,"sample")&&identical(r$reference_qualified,FALSE)&&
    identical(r$full_posterior_accuracy_qualified,FALSE)&&identical(r$publication_authorized,FALSE)&&
    identical(t$purpose_sha256,r$purpose_sha256)&&identical(t$source_commit,r$source_commit)&&
    identical(t$source_tree,r$source_tree)&&t$native_exit_code==0&&isTRUE(t$owner_terminated)&&
    isTRUE(t$worker_terminated)&&identical(t$timed_out,FALSE)&&isTRUE(t$output_manifest_verified)&&
    identical(t$output_manifest_sha256,s$baseline$manifest$sha256)&&r$original_RDS_deserializations==2&&
    t$original_RDS_deserializations==2&&r$conditional_reference_chains_attempted==4&&
    r$saved_callback_calls==0&&t$saved_callback_calls==0&&r$full_parameter_refits==0&&t$full_parameter_refits==0&&
    identical(r$future_truth_read,FALSE)&&identical(t$future_truth_read,FALSE)&&
    gst_same(r$input_bindings,s[c("design","median_model")])&&gst_same(r$producer_identity,gsc_identity())&&
    gst_same(r$accepted_collection,s$collection)&&gst_same(r$input_manifest,s$input_manifest),
    "closed baseline must remain INCONCLUSIVE; calibration is not scientific promotion")
  for(a in r$attempted_reads)q(identical(a$status,"DESERIALIZED")&&identical(a$post_read_sha256,a$sha256),
    "baseline original before/after hashes did not close")
  d<-r$generated_draw_export
  q(isTRUE(d$generated_array_only)&&identical(d$full_parameter_posterior_draws,FALSE)&&
    identical(d$sha256,s$calibration_draws$sha256)&&d$size_bytes==s$calibration_draws$size_bytes&&
    identical(d$path,s$calibration_draws$path)&&
    identical(as.integer(unlist(d$dimensions)),c(20000L,4L,28L)),"typed completed baseline path-array binding required")
  invisible(TRUE)
}
grrr_progress <- function(output_root,worker,kernel,chain) {
  force(output_root);force(worker);force(kernel);force(chain)
  function(p) {
    q<-gfr_require;keys<-c("schema_version","chain_id","completed_iterations","retained_iterations","callback_evaluations",
      "elapsed_seconds","kernel_attempted","kernel_accepted","fully_completed")
    q(is.list(p)&&setequal(names(p),keys)&&identical(p$schema_version,"recovery_progress_metadata_v1")&&
      p$chain_id==chain&&p$completed_iterations>=0&&p$completed_iterations<=1500&&
      all(is.finite(unlist(p[setdiff(keys,c("schema_version","fully_completed"))]))),
      "bounded numeric progress metadata required")
    p$schema_version<-NULL
    raw<-gfr_json_raw(c(list(schema_version="glofas_reference_recovery_progress_v1",worker=worker,kernel=kernel),p))
    q(length(raw)<=4096,"progress metadata exceeds atomic per-chain cap")
    path<-file.path(output_root,sprintf("progress_worker_%02d.json",worker));tmp<-paste0(path,".new")
    q(!file.exists(tmp),"unexpected progress temporary file")
    con<-file(tmp,"wb");tryCatch(writeBin(raw,con),finally=close(con))
    q(file.rename(tmp,path),"atomic progress replacement failed");invisible(NULL)
  }
}
grrr_fork_dispatch <- function(worker,s) {
  q<-gfr_require;parent<-gacr_process();cpus<-as.numeric(unlist(s$limits$child_logical_cpus));b<-s$limits
  parts<-parallel::mclapply(1:8,function(i) {
    proof<-gacr_process();started<-proc.time()
    result<-tryCatch({
      q(proof$ppid==parent$pid&&proof$pgrp==parent$pgrp&&identical(proof$cpus,as.character(cpus[i]))&&
        all(is.finite(proof$native_cpu_limits))&&all(proof$native_cpu_limits>0)&&
        all(proof$native_cpu_limits<=b$child_cpu_seconds)&&all(is.finite(proof$native_address_space_limits))&&
        all(proof$native_address_space_limits>0)&&all(proof$native_address_space_limits<=b$memory_bytes),
        "native child CPU/PGID/parent/address-space proof failed")
      worker(i)
    },error=function(e)list(status="FAIL_RECOVERY_CHILD",qualified=FALSE,error=conditionMessage(e)))
    list(proof=proof,result=result,CPU_seconds=sum((proc.time()-started)[c("user.self","sys.self")]))
  },mc.cores=8L,mc.preschedule=FALSE,mc.set.seed=FALSE,mc.cleanup=TRUE,
    affinity.list=lapply(cpus,function(cpu)as.integer(cpu+1L)))
  q(length(parts)==8L&&all(vapply(parts,function(p)is.list(p)&&is.list(p$proof)&&is.numeric(p$proof$pid),logical(1L))),
    "all eight worker receipts required")
  gone<-function(p){path<-sprintf("/proc/%d/stat",p$proof$pid)
    if(!file.exists(path))return(TRUE)
    raw<-tryCatch(suppressWarnings(readLines(path,warn=FALSE)),error=function(e)character())
    if(!length(raw))return(!file.exists(path))
    f<-strsplit(sub("^.*\\) ","",raw),"[[:space:]]+")[[1L]];!identical(f[20L],p$proof$starttime)}
  for(i in 1:200){if(all(vapply(parts,gone,logical(1L))))break;Sys.sleep(.01)}
  q(all(vapply(parts,gone,logical(1L))),"task-owned children have not exited");parts
}
grrr_write_draws <- function(draws,s,arm) {
  q<-gfr_require;d<-s$draw_export
  q(arm%in%1:2&&typeof(draws)=="double"&&!is.object(draws)&&identical(dim(draws),c(1000L,4L,28L))&&
    all(is.finite(draws)|is.na(draws))&&!any(is.nan(draws))&&
    all(names(attributes(draws))%in%c("dim","dimnames")),"bounded numeric per-arm pilot draws required")
  path<-file.path(s$output_root,as.character(unlist(d$filenames))[arm])
  q(!file.exists(path)&&grrr_no_link(path),"fresh pilot draw output required")
  base::saveRDS(draws,path,version=3L,compress=FALSE);size<-as.numeric(file.info(path)$size)
  q(size<=d$max_bytes,"pilot draw byte cap exceeded")
  list(path=path,relative_path=basename(path),size_bytes=size,sha256=unname(tools::sha256sum(path)),
    role=d$role,dimensions=dim(draws),finite_values=sum(is.finite(draws)),missing_values=sum(is.na(draws)),
    generated_array_only=TRUE,full_parameter_posterior_draws=FALSE)
}
grrr_pilot_arm <- function(result) {
  # The condition is needed for in-memory combination, not output. Do not copy
  # its issued-member matrix or other input/context values into metadata.
  result$condition<-NULL
  result$diagnostic_status<-result$status;result$diagnostic_thresholds_passed<-isTRUE(result$qualified)
  result$status<-"COMPUTATIONAL_PILOT_ARM_RETAINED_NOT_QUALIFIED_REFERENCE"
  result$qualified<-FALSE;result$reference_qualified<-FALSE;result$production_qualification<-FALSE
  result$scope<-"Computational efficiency pilot only: both arms and all chains retained; 500 warmup + 1000 retained iterations never establish a qualified reference"
  result
}
grrr_main <- function(args=commandArgs(TRUE)) {
  q<-gfr_require
  if(identical(args,"--help")){cat("Usage: Rscript --vanilla scripts/glofas_reference_recovery_reader.R --contract FILE --sha256 SHA --dry-run|--execute\n");return(invisible(NULL))}
  q(length(args)==5L&&identical(args[c(1,3)],c("--contract","--sha256"))&&args[5]%in%c("--dry-run","--execute"),
    "explicit separate recovery admission required")
  purpose<-normalizePath(args[2],mustWork=TRUE)
  q(file.info(purpose)$size<=1024^2&&gsc_hash_string(args[4])&&
    identical(unname(tools::sha256sum(purpose)),args[4]),"bounded external purpose digest required")
  s<-jsonlite::read_json(purpose,simplifyVector=FALSE);grrr_scope(s)
  if(args[5]=="--dry-run"){cat("GLOFAS_REFERENCE_RECOVERY_PURPOSE_VALID_NO_PAYLOAD_READS\n");return(invisible(grrr_cost(s)))}
  root<-normalizePath(getwd(),mustWork=TRUE);q(!startsWith(purpose,paste0(root,"/")),"purpose must be external")
  gst_runtime(s);grrr_source(s);available<-gacr_memory_admission(s)
  expiry<-as.POSIXct(s$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry)&&expiry>Sys.time()+s$limits$wall_seconds,"purpose must cover full native lifetime")
  out<-s$output_root;scratch<-s$metadata_scratch_root
  q(startsWith(out,paste0(root,"/local_trackers/"))&&!file.exists(out)&&grrr_no_link(out)&&
    dir.exists(dirname(out))&&identical(normalizePath(dirname(out)),dirname(out))&&
    !grepl("(^|/)\\.\\.(/|$)",out)&&system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(out)))==0L,
    "fresh exclusive ignored recovery output required")
  q(dir.exists(scratch)&&grrr_no_link(scratch)&&identical(normalizePath(scratch),scratch)&&
    identical(list.files(scratch,all.files=TRUE,no..=TRUE),basename(tempdir()))&&
    !length(list.files(tempdir(),all.files=TRUE,no..=TRUE))&&identical(Sys.getenv("TMPDIR"),scratch)&&
    startsWith(normalizePath(tempdir()),paste0(scratch,"/")),"owned native empty metadata scratch required")
  meta<-c(s$source_files,s[c("collection","input_manifest")],s$prior_replay,s$baseline,
    s$diagnostic_dependencies[c("versions","sources")])
  q(8*sum(vapply(meta,function(p)p$size_bytes,numeric(1L)))+8*1024^2<=s$read_budget$max_metadata_bytes,
    "metadata cap exceeded")
  for(p in meta)gsc_pin(p,4*1024^2)
  load_prior<-function(p)list(receipt=jsonlite::read_json(p$receipt$path,simplifyVector=FALSE),
    summary=jsonlite::read_json(p$summary$path,simplifyVector=FALSE),manifest=read.csv(p$manifest$path,stringsAsFactors=FALSE),
    terminal=jsonlite::read_json(p$terminal$path,simplifyVector=FALSE))
  replay<-load_prior(s$prior_replay);baseline<-load_prior(s$baseline)
  gacr_prior_bind(s,replay$receipt,replay$manifest,replay$summary,replay$terminal);grrr_baseline_bind(s,baseline)
  q(identical(normalizePath(Sys.getenv("R_LIBS_USER"),mustWork=TRUE),
    normalizePath(s$diagnostic_dependencies$library_root,mustWork=TRUE)),"private diagnostic library required")
  gacr_library(s$diagnostic_dependencies$library_root,read.csv(s$diagnostic_dependencies$versions$path,stringsAsFactors=FALSE))
  collection<-jsonlite::read_json(s$collection$path,simplifyVector=FALSE);manifest<-read.csv(s$input_manifest$path,stringsAsFactors=FALSE)
  producer<-gnrr_bind(s,collection,manifest);q(dir.create(out),"exclusive output creation failed")
  attempts<-list();post_attempted<-logical();finished<-FALSE;engine<-NULL;started<-proc.time()[["elapsed"]]
  post_hash<-function(){errors<-character()
    for(i in seq_along(attempts))if(!isTRUE(post_attempted[i])) {
      post_attempted[i]<<-TRUE
      if(is.null(attempts[[i]]$pre_read_sha256))next
      tryCatch({gsc_pin(attempts[[i]][c("path","size_bytes","sha256")],8*1024^3)
        attempts[[i]]$post_read_sha256<<-attempts[[i]]$sha256;attempts[[i]]$post_hash_status<<-"PASS"},
        error=function(e){attempts[[i]]$post_hash_status<<-"FAIL_NO_AUTOMATIC_REHASH";errors<<-c(errors,conditionMessage(e))})
    };q(!length(errors),paste(errors,collapse="; "))}
  on.exit(if(!finished){try(post_hash(),silent=TRUE);try(gfr_write(gfr_json_raw(list(
    schema_version="glofas_reference_recovery_failure_v1",status="FAILED_OR_PARTIAL_PILOT_NOT_PROMOTABLE",
    attempted_reads=attempts,post_hash_attempted=post_attempted,reference_qualified=FALSE,
    production_launch_authorized=FALSE,publication_authorized=FALSE)),file.path(out,"FAILED_RECOVERY_RECEIPT.json"),
    out,s$limits$output_bytes),silent=TRUE)},add=TRUE)
  read_one<-function(pin,role){i<-length(attempts)+1L;q(i<=3L,"read allowance exhausted")
    attempts[[i]]<<-c(list(role=role),pin,list(status="PRE_READ_HASH_ATTEMPTED"));post_attempted[i]<<-FALSE
    path<-gsc_pin(pin,8*1024^3);attempts[[i]]$pre_read_sha256<<-pin$sha256
    attempts[[i]]$status<<-"DESERIALIZATION_ATTEMPTED";value<-base::readRDS(path)
    attempts[[i]]$status<<-"DESERIALIZED";value}
  design<-read_one(s$design,"design");history<-gfh_reference_history(design,30L)
  object<-read_one(s$median_model,"median_model");gsc_validate_target(object,producer);core<-object$fit;v<-core$variational_state
  q(identical(object$task_id,"gft-al-p050")&&identical(core$likelihood_family,"al")&&identical(core$method,"vb")&&
    identical(colnames(core$draws$theta),history$columns)&&isTRUE(core$vb_diagnostics$future_y_working_likelihood_used)&&
    identical(core$vb_diagnostics$future_gaussian_prior_used,FALSE),"fixed median AL source/order required")
  theta<-as.numeric(gnr_number(v$theta_mean,length(history$columns)));m<-as.numeric(gnr_number(v$y_future_mean,28L))
  V<-as.matrix(gnr_number(v$y_future_cov));q(identical(dim(V),c(28L,28L))&&max(abs(V-t(V)))<=1e-12&&
    !is.null(tryCatch(chol(V),error=function(e)NULL)),"retained SPD future covariance required for starts only")
  inverse<-v$sigma$inv_mean;q(all(c("Y","G")%in%names(inverse))&&all(is.finite(inverse))&&all(inverse>0),"inverse scale means required")
  scales<-c(Y=1/as.numeric(inverse[["Y"]]),G=1/as.numeric(inverse[["G"]]))
  known<-if(is.null(design$discrepancy_baseline_future))rep(0,28L)else as.numeric(design$discrepancy_baseline_future)
  q(length(known)==28L&&all(is.finite(known)),"known baseline required")
  child<-file.path(scratch,"contract_metadata");q(!file.exists(child)&&dir.create(child),"fresh metadata child required")
  engine<-gnr_engine(root,child,s$metadata_serialization);context<-gnr_context(design,engine)
  identities<-gnr_identities(context);identities$input_scalers<-identities$initial_states<-NULL
  q(gacr_same_json(identities,replay$summary$actual_context_identity),"fresh context differs from closed replay")
  point<-list(parameter_id=gnr_hash(list(theta=theta,sigma_fixed=scales,known_baseline=known)),feature_id=identities$context_sha256,
    sigma_y=scales[["Y"]],sigma_g=scales[["G"]],coefficient_covariance_zero=TRUE,theta_mean_sha256=gnr_hash(theta),
    scale_rule=s$recovery$scale_rule,source_scale_mean_not_used=TRUE,source_model=s$median_model,likelihood_family="al",p=.5)
  q(gacr_same_json(point,baseline$summary$fixed_point),"recovery fixed mathematical point differs from baseline")
  ens<-context$latent_data$g_ensemble;issued<-do.call(rbind,lapply(1:28,function(h)as.numeric(ens$g_transformed[ens$horizon==h])))
  q(identical(dim(issued),c(28L,51L)),"all 51 issued members at all 28 horizons required")
  builder<-gcv_make_value_builder(engine,context,s$recovery$max_total_value_evaluations)
  value<-gnr_location_callback(builder,theta,known)
  contract<-list(mode="authentic",likelihood_family="al",p=.5,sigma_y=scales[["Y"]],sigma_g=scales[["G"]],
    issued=issued,member_weights=matrix(1,28L,51L),forecast_dates=gsc_dates(),origin_date=as.Date("2022-12-25"),
    known_baseline=known,parameter_id=point$parameter_id,feature_id=point$feature_id,coefficient_covariance=matrix(0,1L,1L),
    truth_access="forbidden",max_callback_calls=1+s$recovery$sampler$max_evaluations,max_jacobian_calls=1L,
    ensemble_location_convention="total_reference_plus_discrepancy_plus_known_baseline")
  target<-gapr_new_target(value,contract);uncached<-gnr_make_value_builder(engine,context);parity<-list();first<-NULL
  paths<-cbind(m,m+.001*rep(c(1,-1),14L)/sqrt(28),m)
  for(i in 1:3){a<-builder(paths[,i]);b<-uncached(paths[,i]);difference<-gnr_compare(a,b,FALSE)
    q(all(difference<=1e-10),"compiled/uncached fresh feature parity failed")
    if(i==1L)first<-a
    if(i==3L)q(all(gnr_compare(first,a,FALSE)<=1e-10),"compiled A/B/A parity failed")
    parity[[i]]<-data.frame(path=c("A","B","A")[i],quantity=names(difference),error=as.numeric(difference),tolerance=1e-10)}
  draws<-read_one(s$calibration_draws,"calibration_draws");calibration<-grr_calibrate_proposal(draws,require_authentic_shape=TRUE)
  setup<-gapr_log_target(target,m,components=TRUE);q(is.finite(setup$value),"nonfinite parent setup density")
  starts<-gacr_start_paths(m,V,setup$locations$reference_location)
  rm(draws,design,object,core,v,history,collection,manifest,ens,inverse,uncached,a,b,first,paths);gc(FALSE)
  remaining<-s$limits$wall_seconds-(proc.time()[["elapsed"]]-started)
  q(s$recovery$sampler$max_wall_seconds+s$recovery$minimum_tail_seconds<remaining,"insufficient sampling plus closure time")
  available_fork<-gacr_memory_admission(s)
  parts<-grrr_fork_dispatch(function(i){arm<-1L+(i-1L)%/%4L;chain<-1L+(i-1L)%%4L
    ctl<-s$recovery$sampler;ctl$kernel<-grrr_kernels()[arm];ctl$chain_ids<-chain
    before<-engine$audit$value_calls
    result<-grr_sample_reference(target,starts,calibration,ctl,
      progress_callback=grrr_progress(out,i,ctl$kernel,chain))
    result$engine_value_evaluations<-engine$audit$value_calls-before;result},s)
  arms<-list();exports<-list();worker_proofs<-lapply(parts,function(p)c(p$proof,list(CPU_seconds=p$CPU_seconds)))
  for(arm in 1:2){ctl<-s$recovery$sampler;ctl$kernel<-grrr_kernels()[arm];idx<-(1:4)+4*(arm-1)
    result<-grr_combine_chains(lapply(parts[idx],function(p)p$result),target,ctl)
    q(!is.null(result$draws),"all pilot arms/chains must retain their draws, including incomplete results")
    exports[[arm]]<-grrr_write_draws(result$draws,s,arm)
    if(!is.null(result$diagnostics))gfr_write(gfr_csv_raw(result$diagnostics),
      file.path(out,paste0(ctl$kernel,"_diagnostics.csv")),out,s$limits$output_bytes)
    result$draws<-NULL;arms[[ctl$kernel]]<-grrr_pilot_arm(result)}
  child_calls<-sum(vapply(parts,function(p)if(is.null(p$result$engine_value_evaluations))0 else p$result$engine_value_evaluations,numeric(1L)))
  values<-engine$audit$value_calls+child_calls
  q(values<=s$recovery$max_total_value_evaluations&&engine$audit$factory_calls<=1L&&engine$audit$forbidden_calls==0L,
    "callback/prohibited-operation accounting failed")
  status<-"PILOT_COMPLETE_NOT_PRODUCTION_QUALIFICATION"
  summary<-list(schema_version="glofas_reference_recovery_summary_v1",status=status,mode=s$mode,
    fixed_point=point,baseline_status=baseline$receipt$status,calibration_role=s$recovery$calibration_role,
    calibration=calibration,arms=arms,generated_draw_exports=exports,worker_proofs=worker_proofs,
    timing_basis=s$recovery$timing_basis,
    value_evaluations=values,jacobian_evaluations=engine$audit$factory_calls,compiled_value_parent=gcv_diagnostics(builder),
    pre_read_MemAvailable_bytes=available,pre_fork_MemAvailable_bytes=available_fork,
    reference_qualified=FALSE,full_posterior_accuracy_qualified=FALSE,production_launch_authorized=FALSE,
    publication_authorized=FALSE,arm_selection_by_truth_or_loss=FALSE,
    interpretation="500 warmup + 1000 retained iterations is an efficiency pilot, never a production gate; retain both arms and every chain")
  raw<-gfr_json_raw(summary);q(length(raw)<=s$read_budget$max_recovery_output_bytes,"summary cap exceeded")
  gfr_write(raw,file.path(out,"recovery_summary.json"),out,s$limits$output_bytes)
  gfr_write(gfr_csv_raw(do.call(rbind,parity)),file.path(out,"compiled_uncached_parity.csv"),out,s$limits$output_bytes)
  post_hash();for(p in meta)gsc_pin(p,4*1024^2);grrr_source(s)
  cpu<-sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])
  q(cpu<=s$limits$aggregate_cpu_seconds&&expiry>Sys.time()&&length(attempts)==3L,"CPU/lifetime/read closure failed")
  receipt<-list(schema_version="glofas_reference_recovery_receipt_v1",status=status,mode=s$mode,purpose_sha256=args[4],
    source_commit=s$source_commit,source_tree=s$source_tree,producer_identity=gsc_identity(),
    input_bindings=s[c("design","median_model")],accepted_collection=s$collection,input_manifest=s$input_manifest,
    prior_replay=s$prior_replay,baseline=s$baseline,baseline_status=baseline$receipt$status,
    calibration_draws=s$calibration_draws,calibration_role=s$recovery$calibration_role,read_cost=grrr_cost(s),
    original_RDS_deserializations=2L,generated_numeric_array_deserializations=1L,attempted_reads=attempts,
    conditional_reference_chains_attempted=8L,full_parameter_refits=0L,saved_callback_calls=0L,future_truth_read=FALSE,
    value_evaluations=values,jacobian_evaluations=engine$audit$factory_calls,metadata_serializations=engine$audit$metadata,
    worker_proofs=worker_proofs,generated_draw_exports=exports,aggregate_cpu_seconds=cpu,
    conservative_aggregate_address_space_cap=s$limits$aggregate_memory_bytes,aggregate_peak_RSS_not_measured_here=TRUE,
    reference_qualified=FALSE,full_posterior_accuracy_qualified=FALSE,production_launch_authorized=FALSE,
    publication_authorized=FALSE,independent_supervisor_closure_still_required=TRUE)
  gfr_write(gfr_json_raw(receipt),file.path(out,"REFERENCE_RECOVERY_RECEIPT.json"),out,s$limits$output_bytes)
  files<-list.files(out,full.names=TRUE);inventory<-data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,
    sha256=unname(tools::sha256sum(files)))
  gfr_write(gfr_csv_raw(inventory),file.path(out,"artifact_manifest.csv"),out,s$limits$output_bytes)
  finished<-TRUE;cat("GLOFAS_REFERENCE_RECOVERY_PILOT_CLOSED_NO_PRODUCTION_QUALIFICATION\n");invisible(receipt)
}
if(sys.nframe()==0L)grrr_main()
