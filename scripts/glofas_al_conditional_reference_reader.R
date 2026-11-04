#!/usr/bin/env Rscript
# Separately admitted fixed-parameter diagnostics after authentic replay closes.
# Original read authority, source, callbacks and worker allocation are explicit;
# this is never a full-parameter fit or an article/scoring/publication action.
source("scripts/glofas_nonlinear_replay_reader.R")
source("scripts/diagnostics/glofas_al_path_reference.R")
source("scripts/diagnostics/glofas_compiled_value_reference.R")

gacr_sources <- function() unique(c(gnrr_sources(),
  "scripts/glofas_al_conditional_reference_reader.R", "scripts/diagnostics/glofas_al_path_reference.R",
  "scripts/diagnostics/glofas_compiled_value_reference.R"))
gacr_cost <- function(s) gnrr_cost(s)
gacr_pin_list <- function(x,names_expected) {
  gfr_require(is.list(x)&&length(x)==length(names_expected)&&setequal(names(x),names_expected),
    "exact prerequisite metadata roles required")
  for(pin in x)gfr_pin_shape(pin,4*1024^2)
  invisible(TRUE)
}
gacr_scope <- function(s) {
  q<-gfr_require;gst_unique_objects(s)
  fields<-c("schema_version","purpose","mode","execution_mode","nonce","expires_utc",
    "source_root","source_commit","source_tree","source_files","expected_identity",
    "collection","input_manifest","design","median_model","prior_replay","prior_pilot","draw_export",
    "diagnostic_dependencies","read_budget","limits","output_root","metadata_scratch_root",
    "metadata_serialization","conditional","allow_original_reads","allow_fresh_source_feature_evaluation",
    "allow_metadata_serialization","allow_matched_fixed_parameter_vb","allow_fixed_parameter_path_sampling",
    "allow_saved_callbacks","allow_parameter_updates","allow_prior_updates","allow_full_parameter_refit",
    "allow_truth_read","allow_retuning","allow_scoring","allow_article_changes","allow_publication",
    "allow_derived_context_serialization","allow_raw_draw_export")
  forbidden<-c("allow_saved_callbacks","allow_parameter_updates","allow_prior_updates","allow_full_parameter_refit",
    "allow_truth_read","allow_retuning","allow_scoring","allow_article_changes","allow_publication",
    "allow_derived_context_serialization")
  q(is.list(s)&&length(s)==length(fields)&&setequal(names(s),fields)&&
    identical(s$schema_version,"glofas_al_conditional_reference_contract_v2")&&
    s$mode%in%c("pilot","sample")&&
    identical(s$purpose,if(s$mode=="pilot")"MEDIAN_AL_FIXED_PARAMETER_CONDITIONAL_PILOT_NO_FULL_REFIT" else
      "MEDIAN_AL_FIXED_PARAMETER_FOUR_CHAIN_REFERENCE_NO_FULL_REFIT")&&
    isTRUE(s$allow_original_reads)&&isTRUE(s$allow_fresh_source_feature_evaluation)&&
    isTRUE(s$allow_metadata_serialization)&&
    identical(s$allow_matched_fixed_parameter_vb,s$mode=="pilot")&&
    identical(s$allow_fixed_parameter_path_sampling,s$mode=="sample")&&
    identical(s$allow_raw_draw_export,s$mode=="sample")&&
    all(vapply(s[forbidden],identical,logical(1L),FALSE)),"exact separate conditional diagnostic purpose required")
  q(is.character(s$nonce)&&length(s$nonce)==1L&&grepl("^[a-f0-9]{32,64}$",s$nonce)&&
    all(vapply(s[c("source_commit","source_tree")],function(x)is.character(x)&&length(x)==1L&&
      grepl("^[a-f0-9]{40}$",x),logical(1L)))&&gst_same(s$expected_identity,gsc_identity()),
    "full diagnostic/producer identities required")
  for(pin in s[c("design","median_model")])gfr_pin_shape(pin,8*1024^3)
  for(pin in s[c("collection","input_manifest")])gfr_pin_shape(pin,4*1024^2)
  q(identical(s$design$sha256,"193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3")&&
    identical(s$median_model$sha256,"f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881")&&
    identical(s$input_manifest$sha256,gsc_identity()$input_manifest_sha256)&&
    identical(basename(s$design$path),"shared_truth_free_design.rds")&&
    identical(basename(s$median_model$path),"fit.rds"),"exact frozen truth-free design and median AL only")
  gacr_pin_list(s$prior_replay,c("receipt","manifest","summary","terminal"))
  if(s$mode=="sample")gacr_pin_list(s$prior_pilot,c("receipt","manifest","summary","terminal")) else
    q(is.null(s$prior_pilot),"a pilot must not import another unbound diagnostic")
  if(s$mode=="sample") {
    d<-s$draw_export
    q(is.list(d)&&setequal(names(d),c("filename","role","max_bytes","serialization_version","numeric_array_only"))&&
      identical(d$filename,"conditional_reference_draws.rds")&&
      identical(d$role,"generated_fixed_parameter_conditional_path_draws_not_full_posterior")&&
      gfr_scalar_integer(d$max_bytes)&&d$max_bytes>0&&d$max_bytes<=32*1024^2&&
      d$serialization_version==3L&&isTRUE(d$numeric_array_only),"typed diagnostic-draw export role required")
  } else q(is.null(s$draw_export),"pilot draw export is forbidden")
  dep<-s$diagnostic_dependencies
  q(is.list(dep)&&setequal(names(dep),c("library_root","versions","sources"))&&
    is.character(dep$library_root)&&length(dep$library_root)==1L&&startsWith(dep$library_root,"/"),
    "isolated diagnostic dependency library required")
  for(pin in dep[c("versions","sources")])gfr_pin_shape(pin,4*1024^2)
  b<-s$limits;keys<-c("cpu_seconds","wall_seconds","memory_bytes","output_bytes","logical_cpu",
    "max_workers","child_logical_cpus","child_cpu_seconds","aggregate_cpu_seconds",
    "aggregate_memory_bytes","memory_headroom_bytes","max_draw_memory_bytes")
  q(is.list(b)&&setequal(names(b),keys)&&
    all(vapply(b[setdiff(keys,"child_logical_cpus")],gfr_scalar_integer,logical(1L)))&&
    b$cpu_seconds>=60&&b$cpu_seconds<=28800&&b$wall_seconds>=b$cpu_seconds&&b$wall_seconds<=28800&&
    b$memory_bytes>0&&b$memory_bytes<=32*1024^3&&b$output_bytes>0&&b$output_bytes<=64*1024^2&&
    b$logical_cpu%in%26:29&&b$max_draw_memory_bytes>0&&b$max_draw_memory_bytes<=128*1024^2&&
    b$memory_headroom_bytes>=180*1024^3,"bounded native Muscat conditional allocation required")
  cpus<-as.numeric(unlist(b$child_logical_cpus,use.names=FALSE))
  if(identical(s$execution_mode,"fork_four")) {
    q(s$mode=="sample"&&b$max_workers==4L&&identical(sort(cpus),as.numeric(26:29))&&
      b$child_cpu_seconds>=60&&b$child_cpu_seconds<=b$cpu_seconds&&
      b$aggregate_cpu_seconds>=b$cpu_seconds+4*b$child_cpu_seconds&&
      b$aggregate_memory_bytes>=5*b$memory_bytes,"explicit four-worker aggregate allocation required")
  } else q(identical(s$execution_mode,"sequential")&&b$max_workers==1L&&!length(cpus)&&
      b$child_cpu_seconds==0L&&b$aggregate_cpu_seconds>=b$cpu_seconds&&
      b$aggregate_memory_bytes>=b$memory_bytes,"explicit sequential purpose required; no fallback")
  r<-s$read_budget;keys<-c("max_payload_hash_bytes","max_deserialization_bytes","max_RDS_deserializations",
    "max_metadata_bytes","max_conditional_output_bytes")
  q(is.list(r)&&setequal(names(r),keys)&&all(vapply(r,gfr_scalar_integer,logical(1L)))&&
    all(unlist(r)>0)&&r$max_RDS_deserializations==2L&&r$max_deserialization_bytes<=24*1024^3&&
    r$max_payload_hash_bytes<=48*1024^3&&r$max_metadata_bytes<=64*1024^2&&
    r$max_conditional_output_bytes<=10*1024^2,"finite two-read and compact diagnostic allowance required")
  m<-s$metadata_serialization
  q(is.list(m)&&setequal(names(m),c("max_files","max_file_bytes","max_total_bytes"))&&
    all(vapply(m,gfr_scalar_integer,logical(1L)))&&all(unlist(m)>0)&&m$max_files<=64L&&
    m$max_file_bytes<=4*1024^2&&m$max_total_bytes<=32*1024^2&&
    m$max_total_bytes+r$max_conditional_output_bytes+(if(s$mode=="sample")s$draw_export$max_bytes else 0)+65536<=b$output_bytes,
    "bounded generated contract metadata/output required")
  c<-s$conditional;keys<-c("likelihood_family","tau","parameter_rule","scale_rule",
    "max_total_value_evaluations","max_jacobian_evaluations","timing_evaluations",
    "value_backend","parity_evaluations","setup_value_evaluations",
    "timing_perturbation","matched_vb","sampler","proposal_rule","start_rule",
    "minimum_tail_seconds","pilot_safety_factor","qualification_scope")
  q(is.list(c)&&setequal(names(c),keys)&&identical(c$likelihood_family,"al")&&c$tau==.5&&
    all(vapply(c[c("max_total_value_evaluations","max_jacobian_evaluations","timing_evaluations",
      "parity_evaluations","setup_value_evaluations")],gfr_scalar_integer,logical(1L)))&&
    identical(c$parameter_rule,"retained_theta_mean_fixed_coefficient_covariance_zero")&&
    identical(c$scale_rule,"reciprocal_retained_inverse_scale_means_not_scale_means")&&
    identical(c$proposal_rule,"retained_future_covariance_preconditioner")&&
    identical(c$start_rule,"retained_m_minus_sd_plus_sd_and_reference_at_m_minus_sd_plus_sd")&&
    c$minimum_tail_seconds>=120&&c$minimum_tail_seconds<=300&&
    c$pilot_safety_factor>=2&&c$pilot_safety_factor<=4&&
    c$max_total_value_evaluations>=3&&c$max_total_value_evaluations<=1000000&&
    c$max_jacobian_evaluations>=1&&c$max_jacobian_evaluations<=1000&&
    c$value_backend%in%c("compiled_input_reference","uncached_reference"),
    "fixed median AL diagnostic convention/callback bounds required")
  if(s$mode=="pilot") {
    v<-c$matched_vb
    q(c$timing_evaluations==3L&&c$timing_perturbation>0&&c$timing_perturbation<=.01&&
      is.null(c$sampler)&&is.list(v)&&setequal(names(v),c("max_iterations","max_wall_seconds","tolerance","jitter"))&&
      v$max_iterations>=1&&v$max_iterations<=300&&v$max_iterations==floor(v$max_iterations)&&
      v$max_wall_seconds>=1&&v$max_wall_seconds<=1200&&v$tolerance>0&&v$tolerance<=1e-6&&
      v$jitter==1e-8&&c$max_jacobian_evaluations>=v$max_iterations+1&&
      c$setup_value_evaluations==0L&&
      c$parity_evaluations==(if(c$value_backend=="compiled_input_reference")6L else 0L)&&
      c$max_total_value_evaluations>=c$parity_evaluations+3L&&
      identical(c$qualification_scope,"timing_and_matched_fixed_parameter_VB_only"),"bounded pilot, not sampling, required")
  } else {
    v<-c$sampler;needed<-c("warmup","samples","max_evaluations","max_wall_seconds","adapt_warmup",
      "rhat_max","min_ess","max_quantile_mcse","proposal_kind")
    q(c$timing_evaluations==0L&&c$timing_perturbation==0&&c$parity_evaluations==0L&&
      c$setup_value_evaluations==1L&&is.null(c$matched_vb)&&
      is.list(v)&&setequal(names(v),needed)&&v$warmup>=0&&v$warmup==floor(v$warmup)&&
      v$samples>=20&&v$samples<=20000&&v$samples==floor(v$samples)&&
      v$max_evaluations>=(1+v$warmup+v$samples)*(if(s$execution_mode=="fork_four")1 else 4)&&v$max_wall_seconds>0&&
      identical(v$adapt_warmup,TRUE)&&v$rhat_max==1.01&&v$min_ess>=400&&
      v$max_quantile_mcse%in%c(.001,.005)&&identical(v$proposal_kind,"blocked_preconditioned")&&
      c$max_total_value_evaluations>=1+v$max_evaluations*b$max_workers&&
      c$max_total_value_evaluations<=1000000&&
      v$samples*4*28*8*(if(s$execution_mode=="fork_four")5 else 1)<=b$max_draw_memory_bytes&&
      identical(c$qualification_scope,if(v$max_quantile_mcse==.001)"strict_conditional_reference_not_full_posterior" else
        "coarse_path_mechanism_only_not_production_qualification"),"explicit four-chain conditional scope/thresholds required")
  }
  gacr_cost(s);invisible(TRUE)
}

gacr_source <- function(s) {
  q<-gfr_require;root<-normalizePath(getwd(),mustWork=TRUE)
  git<-function(a){z<-system2("/usr/bin/git",c("--no-replace-objects","-c","core.fsmonitor=false",a),stdout=TRUE)
    q(is.null(attr(z,"status")),"conditional source Git check failed");unname(z)}
  q(identical(root,s$source_root)&&identical(git(c("rev-parse","--show-toplevel")),root)&&
    identical(git(c("rev-parse","HEAD")),s$source_commit)&&identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=all"))),"exact clean committed conditional source required")
  paths<-vapply(s$source_files,function(p){gfr_pin_shape(p,1024^2);p$path},character(1L))
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,gacr_sources())),"complete new/transitive source closure required")
  for(pin in s$source_files)gsc_pin(pin,1024^2)
  for(rel in gacr_sources())q(identical(git(c("hash-object","--no-filters","--",shQuote(rel))),
    git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel))))),"conditional source differs from committed blob")
  for(rel in gnr_production_sources())q(identical(git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel)))),
    git(c("rev-parse",shQuote(paste0(gsc_identity()$source_commit,":",rel))))),"production source changed from fa6a4e33")
  invisible(root)
}

gacr_prior_bind <- function(s,receipt,manifest,summary,terminal,kind="replay") {
  q<-gfr_require;pins<-if(kind=="replay")s$prior_replay else s$prior_pilot
  q(is.data.frame(manifest)&&identical(names(manifest),c("relative_path","size_bytes","sha256"))&&
    !anyDuplicated(manifest$relative_path)&&all(basename(manifest$relative_path)==manifest$relative_path),
    "bounded prerequisite artifact manifest required")
  for(pin in pins[c("receipt","summary")]) {
    at<-which(manifest$relative_path==basename(pin$path))
    q(length(at)==1L&&manifest$size_bytes[at]==pin$size_bytes&&identical(manifest$sha256[at],pin$sha256)&&
      identical(dirname(pin$path),dirname(pins$manifest$path)),"prerequisite receipt/summary not manifest-bound")
  }
  q(identical(terminal$purpose_sha256,receipt$purpose_sha256)&&
    identical(terminal$source_commit,receipt$source_commit)&&identical(terminal$source_tree,receipt$source_tree)&&
    terminal$native_exit_code==0&&isTRUE(terminal$owner_terminated)&&isTRUE(terminal$worker_terminated)&&
    identical(terminal$timed_out,FALSE)&&isTRUE(terminal$output_manifest_verified)&&
    identical(terminal$output_manifest_sha256,pins$manifest$sha256)&&
    terminal$original_RDS_deserializations==2L&&terminal$saved_callback_calls==0L&&
    identical(terminal$future_truth_read,FALSE)&&terminal$full_parameter_refits==0L,
    "independently closed native prerequisite is required before original reads")
  q(gst_same(receipt$producer_identity,gsc_identity())&&
    gst_same(receipt$input_bindings$design,s$design)&&gst_same(receipt$input_bindings$median_model,s$median_model)&&
    gst_same(receipt$accepted_collection,s$collection)&&gst_same(receipt$input_manifest,s$input_manifest)&&
    receipt$original_RDS_deserializations==2L&&receipt$saved_callback_calls==0L&&
    identical(receipt$future_truth_read,FALSE),"prerequisite exact producer/input/truth identity differs")
  if(kind=="replay") {
    q(identical(receipt$schema_version,"glofas_nonlinear_replay_receipt_v1")&&
      identical(terminal$schema_version,"glofas_nonlinear_replay_native_terminal_v1")&&
      identical(receipt$status,"PASS_FEATURE_REPLAY_ONLY_NOT_POSTERIOR_ACCURACY")&&
      identical(summary$status,receipt$status)&&receipt$factory_evaluations==12L&&receipt$value_evaluations==8L&&
      terminal$factory_evaluations==12L&&terminal$value_evaluations==8L&&terminal$applied_updates==0L&&
      receipt$applied_updates==0L&&isTRUE(summary$context_unchanged)&&isTRUE(summary$RNG_unchanged)&&
      summary$forbidden_calls==0L,"passed authentic nonlinear replay is a hard prerequisite")
    q(receipt$new_fits==0L&&identical(receipt$production_launch_authorized,FALSE)&&
      identical(receipt$publication_authorized,FALSE),"replay was not a no-fit/nonpublication closeout")
  } else {
    q(identical(receipt$schema_version,"glofas_al_conditional_reference_receipt_v1")&&
      identical(terminal$schema_version,"glofas_al_conditional_reference_native_terminal_v1")&&
      identical(receipt$mode,"pilot")&&identical(receipt$status,"PILOT_COMPLETE_NOT_MCMC_OR_FULL_POSTERIOR_QUALIFICATION")&&
      identical(receipt$source_commit,s$source_commit)&&identical(receipt$source_tree,s$source_tree)&&
      identical(summary$mode,"pilot")&&summary$timing$value_evaluations==3L&&
      summary$timing$maximum_seconds_per_evaluation>0&&
      receipt$conditional_reference_chains_attempted==0L,"a closed measured conditional pilot is required for sampling")
  }
  for(a in receipt$attempted_reads)q(identical(a$status,"DESERIALIZED")&&
    identical(a$post_read_sha256,a$sha256),"prerequisite original before/after pins did not close")
  invisible(TRUE)
}

gacr_library <- function(library_root,versions) {
  q<-gfr_require;root<-normalizePath(library_root,mustWork=TRUE)
  expected<-c(checkmate="2.3.4",distributional="0.9.0",posterior="1.6.1",tensorA="0.36.2.1")
  q(is.data.frame(versions)&&setequal(names(versions),c("Package","Version","LibPath"))&&
    !anyDuplicated(versions$Package)&&setequal(versions$Package,names(expected)),"exact diagnostic package inventory required")
  for(pkg in names(expected)) {
    at<-which(versions$Package==pkg)
    q(identical(versions$Version[at],expected[[pkg]])&&
      identical(normalizePath(versions$LibPath[at],mustWork=TRUE),root)&&
      dir.exists(file.path(root,pkg))&&requireNamespace(pkg,quietly=TRUE,lib.loc=root),
      "required diagnostic dependency is absent from its private library")
    loaded<-normalizePath(getNamespaceInfo(asNamespace(pkg),"path"),mustWork=TRUE)
    q(identical(loaded,normalizePath(file.path(root,pkg),mustWork=TRUE))&&
      identical(as.character(utils::packageVersion(pkg,lib.loc=root)),expected[[pkg]]),
      "diagnostic namespace fell back outside its authenticated private library")
  }
  invisible(TRUE)
}

gacr_process <- function() {
  line<-readLines("/proc/self/stat",warn=FALSE);fields<-strsplit(sub("^.*\\) ","",line),"[[:space:]]+")[[1L]]
  limits<-readLines("/proc/self/limits",warn=FALSE)
  limit<-function(name)suppressWarnings(as.numeric(strsplit(trimws(sub(paste0("^",name),"",
    grep(paste0("^",name),limits,value=TRUE))),"[[:space:]]+")[[1L]][1:2]))
  list(pid=Sys.getpid(),ppid=as.integer(fields[2L]),pgrp=as.integer(fields[3L]),
    starttime=fields[20L],cpus=trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",
      readLines("/proc/self/status",warn=FALSE),value=TRUE))),
    native_cpu_limits=limit("Max cpu time"),native_address_space_limits=limit("Max address space"))
}
gacr_fork_dispatch <- function(worker,cpus,child_cpu_seconds) {
  q<-gfr_require;parent<-gacr_process()
  q(is.function(worker)&&length(cpus)==4L&&!anyDuplicated(cpus)&&
    all(cpus%in%0:63)&&child_cpu_seconds>=1,"explicit four-worker dispatch required")
  parts<-parallel::mclapply(1:4,function(chain) {
    proof<-gacr_process();started<-proc.time()
    result<-tryCatch({
      q(identical(proof$cpus,as.character(cpus[chain]))&&proof$ppid==parent$pid&&proof$pgrp==parent$pgrp,
        "child CPU/parent/process-group proof failed")
      q(all(is.finite(proof$native_cpu_limits))&&all(proof$native_cpu_limits>0)&&
        all(proof$native_cpu_limits<=child_cpu_seconds)&&
        all(is.finite(proof$native_address_space_limits))&&all(proof$native_address_space_limits>0),
        "inherited child CPU/address-space native hard caps differ")
      worker(chain)
    },error=function(e)list(status="FAIL_CHILD_EXECUTION",qualified=FALSE,error=conditionMessage(e)))
    list(proof=proof,result=result,CPU_seconds=sum((proc.time()-started)[c("user.self","sys.self")]))
  },mc.cores=4L,mc.preschedule=FALSE,mc.set.seed=FALSE,
    affinity.list=lapply(cpus,function(cpu)as.integer(cpu+1L)),mc.cleanup=TRUE)
  q(length(parts)==4L&&all(vapply(parts,is.list,logical(1L)))&&
    all(vapply(parts,function(p)is.list(p$proof)&&is.numeric(p$proof$pid),logical(1L))),
    "four native worker receipts did not return")
  gone<-function(p) {
    path<-sprintf("/proc/%d/stat",p$proof$pid)
    if(!file.exists(path))return(TRUE)
    raw<-tryCatch(suppressWarnings(readLines(path,warn=FALSE)),error=function(e)character())
    if(!length(raw))return(!file.exists(path))
    f<-strsplit(sub("^.*\\) ","",raw),"[[:space:]]+")[[1L]]
    !identical(f[20L],p$proof$starttime)
  }
  # Result-pipe delivery can precede the child's final exit by a few ms.
  # This bounded closure wait never accepts an alive/zombie owned PID.
  for(i in 1:200) {
    if(all(vapply(parts,gone,logical(1L))))break
    Sys.sleep(.01)
  }
  q(all(vapply(parts,gone,logical(1L))),"a task-owned worker is not closed")
  parts
}

gacr_memory_admission <- function(s) {
  available<-as.numeric(strsplit(trimws(sub("^MemAvailable:","",grep("^MemAvailable:",
    readLines("/proc/meminfo"),value=TRUE))),"[[:space:]]+")[[1L]][1L])*1024
  gfr_require(is.finite(available)&&available>=s$limits$aggregate_memory_bytes+s$limits$memory_headroom_bytes,
    "fresh aggregate memory/headroom admission failed")
  available
}

gacr_same_json <- function(a,b) {
  plain<-function(x)jsonlite::fromJSON(jsonlite::toJSON(x,auto_unbox=TRUE,
    null="null",na="null",digits=17),simplifyVector=FALSE)
  gst_same(plain(a),plain(b))
}

gacr_start_paths <- function(m,V,reference_at_m) {
  q<-gfr_require
  q(is.numeric(m)&&is.matrix(V)&&identical(dim(V),c(length(m),length(m)))&&
    length(reference_at_m)==length(m)&&all(is.finite(c(m,V,reference_at_m)))&&all(diag(V)>0),
    "finite retained/prospective conditional starting paths required")
  sd<-sqrt(diag(V))
  out<-cbind(m-sd,m+sd,reference_at_m-sd,reference_at_m+sd)
  colnames(out)<-paste0("chain",1:4);out
}

gacr_write_draws <- function(draws,s) {
  q<-gfr_require;d<-s$draw_export
  q(identical(s$mode,"sample")&&isTRUE(s$allow_raw_draw_export)&&is.list(d)&&
    identical(d$filename,"conditional_reference_draws.rds")&&isTRUE(d$numeric_array_only)&&
    identical(d$role,"generated_fixed_parameter_conditional_path_draws_not_full_posterior")&&
    d$serialization_version==3L,"separate sample-only draw serialization required")
  q(typeof(draws)=="double"&&!is.object(draws)&&
    identical(dim(draws),c(as.integer(s$conditional$sampler$samples),4L,28L))&&
    all(is.finite(draws)|is.na(draws))&&!any(is.nan(draws))&&
    all(names(attributes(draws))%in%c("dim","dimnames"))&&
    as.numeric(object.size(draws))<=d$max_bytes,"only bounded numeric conditional-path arrays may be exported")
  path<-file.path(s$output_root,d$filename);link<-Sys.readlink(path)
  q(!file.exists(path)&&(is.na(link)||!nzchar(link))&&dir.exists(s$output_root)&&
    identical(normalizePath(s$output_root),s$output_root),"fresh owned diagnostic-draw output required")
  used<-sum(file.info(list.files(s$output_root,full.names=TRUE))$size)
  q(used+d$max_bytes+65536<=s$limits$output_bytes,"draw output would exceed combined file budget")
  base::saveRDS(draws,file=path,version=3L,compress=FALSE)
  size<-as.numeric(file.info(path)$size)
  q(is.finite(size)&&size>0&&size<=d$max_bytes,"serialized conditional draws exceed cap")
  list(path=path,relative_path=d$filename,size_bytes=size,sha256=unname(tools::sha256sum(path)),
    role=d$role,dimensions=dim(draws),finite_values=sum(is.finite(draws)),missing_values=sum(is.na(draws)),
    generated_array_only=TRUE,full_parameter_posterior_draws=FALSE)
}

gacr_main <- function(args=commandArgs(TRUE)) {
  q<-gfr_require
  if(identical(args,"--help")){cat("Usage: Rscript --vanilla scripts/glofas_al_conditional_reference_reader.R --contract FILE --sha256 SHA --execute\n");return(invisible(NULL))}
  q(length(args)==5L&&identical(args[c(1L,3L,5L)],c("--contract","--sha256","--execute")),
    "explicit new external conditional-reference admission required")
  purpose<-normalizePath(args[2L],mustWork=TRUE)
  q(grepl("\\.json$",purpose)&&file.info(purpose)$size<=1024^2&&gsc_hash_string(args[4L])&&
    identical(unname(tools::sha256sum(purpose)),args[4L]),"bounded external purpose digest required")
  s<-jsonlite::read_json(purpose,simplifyVector=FALSE);gacr_scope(s)
  root<-normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(purpose,paste0(root,"/")),"purpose must be external")
  gst_runtime(s);gacr_source(s)
  expiry<-as.POSIXct(s$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry)&&expiry>Sys.time()+s$limits$wall_seconds,"purpose must outlive the whole native job")
  available<-gacr_memory_admission(s)
  q(identical(normalizePath(Sys.getenv("R_LIBS_USER"),mustWork=TRUE),
    normalizePath(s$diagnostic_dependencies$library_root,mustWork=TRUE))&&
    isTRUE(gapr_posterior_dependency()$available),"exact isolated posterior1.6.1 library required")
  out<-s$output_root;link<-Sys.readlink(out)
  q(startsWith(out,paste0(root,"/local_trackers/"))&&!file.exists(out)&&(is.na(link)||!nzchar(link))&&
    dir.exists(dirname(out))&&identical(normalizePath(dirname(out)),dirname(out))&&
    !grepl("(^|/)\\.\\.(/|$)",out)&&system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(out)))==0L,
    "fresh ignored diagnostic output required")
  scratch<-s$metadata_scratch_root;link<-Sys.readlink(scratch)
  q(dir.exists(scratch)&&(is.na(link)||!nzchar(link))&&identical(normalizePath(scratch),scratch)&&
    identical(list.files(scratch,all.files=TRUE,no..=TRUE),basename(tempdir()))&&
    !length(list.files(tempdir(),all.files=TRUE,no..=TRUE))&&identical(Sys.getenv("TMPDIR"),scratch)&&
    startsWith(normalizePath(tempdir()),paste0(scratch,"/")),"owned native empty metadata scratch required")
  prerequisites<-c(s$prior_replay,if(s$mode=="sample")s$prior_pilot else list())
  meta<-c(s$source_files,s[c("collection","input_manifest")],prerequisites,
    s$diagnostic_dependencies[c("versions","sources")])
  metadata_bytes<-8*sum(vapply(meta,function(p)p$size_bytes,numeric(1L)))+8*1024^2
  q(metadata_bytes<=s$read_budget$max_metadata_bytes,"conservative metadata cap exceeded")
  for(pin in meta)gsc_pin(pin,4*1024^2)
  load_prior<-function(pins)list(receipt=jsonlite::read_json(pins$receipt$path,simplifyVector=FALSE),
    manifest=read.csv(pins$manifest$path,stringsAsFactors=FALSE),
    summary=jsonlite::read_json(pins$summary$path,simplifyVector=FALSE),
    terminal=jsonlite::read_json(pins$terminal$path,simplifyVector=FALSE))
  replay<-load_prior(s$prior_replay)
  gacr_prior_bind(s,replay$receipt,replay$manifest,replay$summary,replay$terminal)
  pilot<-if(s$mode=="sample")load_prior(s$prior_pilot)else NULL
  if(!is.null(pilot))gacr_prior_bind(s,pilot$receipt,pilot$manifest,pilot$summary,pilot$terminal,"pilot")
  gacr_library(s$diagnostic_dependencies$library_root,
    read.csv(s$diagnostic_dependencies$versions$path,stringsAsFactors=FALSE))
  if(!is.null(pilot)) {
    q(identical(pilot$summary$value_backend,s$conditional$value_backend),"reference backend differs from closed pilot")
    projected<-pilot$summary$timing$maximum_seconds_per_evaluation*
      (s$conditional$sampler$warmup+s$conditional$sampler$samples+1)*
      (if(s$execution_mode=="fork_four")1 else 4)*s$conditional$pilot_safety_factor
    q(projected+s$conditional$minimum_tail_seconds<s$limits$wall_seconds,
      "measured pilot makes this sample infeasible before original reads")
  }
  collection<-jsonlite::read_json(s$collection$path,simplifyVector=FALSE)
  manifest<-read.csv(s$input_manifest$path,stringsAsFactors=FALSE)
  producer<-gnrr_bind(s,collection,manifest);cost<-gacr_cost(s)
  q(dir.create(out),"exclusive conditional output creation failed")
  attempts<-list();post_attempted<-logical();finished<-FALSE;engine<-NULL;counts<-list(chains=0L,vb=0L)
  child_accounting_complete<-s$execution_mode!="fork_four"
  started<-proc.time()[["elapsed"]]
  post_hash<-function() {
    failures<-character()
    for(i in seq_along(attempts))if(!isTRUE(post_attempted[i])) {
      post_attempted[i]<<-TRUE
      if(is.null(attempts[[i]]$pre_read_sha256)) {
        attempts[[i]]$post_hash_status<<-"NOT_REQUIRED_PREHASH_FAILED_NO_DESERIALIZATION"
      } else {
        attempts[[i]]$post_hash_status<<-"ATTEMPTED_ONCE"
        tryCatch({
          gsc_pin(attempts[[i]][c("path","size_bytes","sha256")],8*1024^3)
          attempts[[i]]$post_read_sha256<<-attempts[[i]]$sha256
          attempts[[i]]$post_hash_status<<-"PASS"
        },error=function(e) {
          attempts[[i]]$post_hash_status<<-"FAIL_NO_AUTOMATIC_REHASH"
          failures<<-c(failures,conditionMessage(e))
        })
      }
    }
    q(!length(failures),paste(failures,collapse="; "))
  }
  on.exit(if(!finished){
    try(post_hash(),silent=TRUE)
    try(gfr_write(gfr_json_raw(list(schema_version="glofas_al_conditional_reference_failure_v1",
      status="FAILED_OR_PARTIAL_CONDITIONAL_DIAGNOSTIC_NOT_PROMOTABLE",mode=s$mode,
      attempted_reads=attempts,post_hash_attempted=post_attempted,
      conditional_reference_chains_attempted=counts$chains,conditional_vb_optimizations_attempted=counts$vb,
      value_evaluations_parent_only=if(is.null(engine))0L else engine$audit$value_calls,
      child_execution_accounting_complete=child_accounting_complete,
      jacobian_evaluations=if(is.null(engine))0L else engine$audit$factory_calls,
      saved_callback_calls=0L,future_truth_read=FALSE,full_parameter_refits=0L,
      independent_supervisor_closure_still_required=TRUE)),
      file.path(out,"FAILED_CONDITIONAL_RECEIPT.json"),out,s$limits$output_bytes),silent=TRUE)
  },add=TRUE)
  read_one<-function(pin,role) {
    i<-length(attempts)+1L;q(i<=2L,"original read allowance exhausted")
    attempts[[i]]<<-c(list(role=role),pin,list(status="PRE_READ_HASH_ATTEMPTED"));post_attempted[i]<<-FALSE
    path<-gsc_pin(pin,8*1024^3)
    attempts[[i]]$pre_read_sha256<<-pin$sha256
    attempts[[i]]$status<<-"DESERIALIZATION_ATTEMPTED"
    value<-readRDS(path);attempts[[i]]$status<<-"DESERIALIZED";value
  }
  design<-read_one(s$design,"design");history<-gfh_reference_history(design,30L)
  object<-read_one(s$median_model,"median_model");gsc_validate_target(object,producer)
  core<-object$fit;v<-core$variational_state
  q(identical(object$task_id,"gft-al-p050")&&identical(core$likelihood_family,"al")&&
    identical(core$method,"vb")&&identical(colnames(core$draws$theta),history$columns)&&
    isTRUE(core$vb_diagnostics$future_y_working_likelihood_used)&&
    identical(core$vb_diagnostics$future_gaussian_prior_used,FALSE),"fixed median AL source and feature order required")
  theta<-as.numeric(gnr_number(v$theta_mean,length(history$columns)))
  m<-as.numeric(gnr_number(v$y_future_mean,28L));V<-as.matrix(gnr_number(v$y_future_cov))
  q(identical(dim(V),c(28L,28L))&&max(abs(V-t(V)))<=1e-12&&!is.null(tryCatch(chol(V),error=function(e)NULL)),
    "retained future covariance must be an SPD proposal, not a new prior")
  inverse<-v$sigma$inv_mean
  q(all(c("Y","G")%in%names(inverse))&&all(is.finite(inverse))&&all(inverse>0),"retained inverse-scale means required")
  scales<-c(Y=1/as.numeric(inverse[["Y"]]),G=1/as.numeric(inverse[["G"]]))
  baseline<-if(is.null(design$discrepancy_baseline_future))rep(0,28L)else as.numeric(design$discrepancy_baseline_future)
  q(length(baseline)==28L&&all(is.finite(baseline)),"explicit known baseline required")
  child<-file.path(scratch,"contract_metadata");q(!file.exists(child)&&dir.create(child),"fresh metadata child required")
  engine<-gnr_engine(root,child,s$metadata_serialization);context<-gnr_context(design,engine)
  identities<-gnr_identities(context);identities$input_scalers<-identities$initial_states<-NULL
  q(gacr_same_json(identities,replay$summary$actual_context_identity),"fresh numeric context differs from passed replay")
  parameter_id<-gnr_hash(list(theta=theta,sigma_fixed=scales,known_baseline=baseline))
  point<-list(parameter_id=parameter_id,feature_id=identities$context_sha256,sigma_y=scales[["Y"]],
    sigma_g=scales[["G"]],coefficient_covariance_zero=TRUE,
    theta_mean_sha256=gnr_hash(theta),scale_rule=s$conditional$scale_rule,
    source_scale_mean_not_used=TRUE,source_model=s$median_model,likelihood_family="al",p=.5)
  if(!is.null(pilot))q(gst_same(point,pilot$summary$fixed_point),"sampling point differs from the measured pilot")
  ens<-context$latent_data$g_ensemble
  issued<-do.call(rbind,lapply(1:28,function(h)as.numeric(ens$g_transformed[ens$horizon==h])))
  q(identical(dim(issued),c(28L,51L)),"28 by 51 issued matrix required")
  value_builder<-if(s$conditional$value_backend=="compiled_input_reference")
    gcv_make_value_builder(engine,context,s$conditional$max_total_value_evaluations) else gnr_make_value_builder(engine,context)
  value<-gnr_location_callback(value_builder,theta,baseline)
  contract<-list(mode="authentic",likelihood_family="al",p=.5,sigma_y=scales[["Y"]],sigma_g=scales[["G"]],
    issued=issued,member_weights=matrix(1,28L,51L),forecast_dates=gsc_dates(),origin_date=as.Date("2022-12-25"),
    known_baseline=baseline,parameter_id=parameter_id,feature_id=point$feature_id,
    coefficient_covariance=matrix(0,1L,1L),truth_access="forbidden",
    max_callback_calls=if(s$execution_mode=="fork_four")1+s$conditional$sampler$max_evaluations else s$conditional$max_total_value_evaluations,
    max_jacobian_calls=s$conditional$max_jacobian_evaluations,
    ensemble_location_convention="total_reference_plus_discrepancy_plus_known_baseline")
  target<-gapr_new_target(value,contract)
  rm(design,object,core,v,history,collection,manifest,ens,inverse);gc(FALSE)
  payload<-list(mode=s$mode,value_backend=s$conditional$value_backend,fixed_point=point,prior_replay=s$prior_replay,
    full_parameter_refits=0L,truth_read=FALSE,qualification_scope=s$conditional$qualification_scope)
  outputs<-list();worker_proofs<-list();reference_qualified<-FALSE
  if(s$mode=="pilot") {
    direction<-rep(c(1,-1),14L)/sqrt(28)
    paths<-cbind(m,m+s$conditional$timing_perturbation*direction,m)
    if(s$conditional$value_backend=="compiled_input_reference") {
      uncached<-gnr_make_value_builder(engine,context);parity<-list();first<-NULL
      for(i in 1:3) {
        a<-value_builder(paths[,i]);b<-uncached(paths[,i]);difference<-gnr_compare(a,b,FALSE)
        q(all(difference<=1e-10),"compiled/uncached value parity failed")
        if(i==1L)first<-a
        if(i==3L)q(all(gnr_compare(first,a,FALSE)<=1e-10),"compiled A/B/A cache parity failed")
        parity[[i]]<-data.frame(path=c("A","B","A")[i],quantity=names(difference),error=as.numeric(difference),tolerance=1e-10)
      }
      outputs$compiled_uncached_parity.csv<-gfr_csv_raw(do.call(rbind,parity))
      rm(a,b,first,uncached)
    }
    timings<-lapply(1:3,function(i)gapr_callback_timing(target,paths[,i,drop=FALSE]))
    payload$timing<-list(value_evaluations=3L,seconds=vapply(timings,function(t)t$elapsed_seconds,numeric(1L)),
      maximum_seconds_per_evaluation=max(1e-3,max(vapply(timings,function(t)t$seconds_per_evaluation,numeric(1L)))))
    payload$parity_value_evaluations<-s$conditional$parity_evaluations
    remaining<-s$limits$wall_seconds-(proc.time()[["elapsed"]]-started)
    ctl<-s$conditional$matched_vb
    q(remaining>ctl$max_wall_seconds+s$conditional$minimum_tail_seconds,"insufficient time for bounded VB plus post-hash closure")
    callback<-gnr_location_jacobian_callback(gnr_factory(engine,context,"compiled_active"),theta,baseline)
    counts$vb<-1L
    vb<-gapr_matched_fixed_vb(target,callback,engine$env,m,V,
      max_iterations=ctl$max_iterations,max_wall_seconds=ctl$max_wall_seconds,tolerance=ctl$tolerance,jitter=ctl$jitter)
    payload$matched_vb<-vb[c("status","iterations","max_scaled_change","repaired","jacobian_evaluations","comparison_type")]
    outputs$matched_vb_quantiles.csv<-gfr_csv_raw(vb$quantiles)
    outputs$matched_vb_path.csv<-gfr_csv_raw(data.frame(horizon=1:28,mean=vb$mean,sd=sqrt(diag(vb$covariance))))
    status<-"PILOT_COMPLETE_NOT_MCMC_OR_FULL_POSTERIOR_QUALIFICATION"
  } else {
    control<-s$conditional$sampler
    q(identical(pilot$summary$value_backend,s$conditional$value_backend),"sampling backend differs from its qualified pilot")
    projected<-pilot$summary$timing$maximum_seconds_per_evaluation*(control$warmup+control$samples+1)*
      (if(s$execution_mode=="fork_four")1 else 4)*s$conditional$pilot_safety_factor
    remaining<-s$limits$wall_seconds-(proc.time()[["elapsed"]]-started)
    q(projected+s$conditional$minimum_tail_seconds<remaining&&
      control$max_wall_seconds+s$conditional$minimum_tail_seconds<remaining,
      "measured pilot projects beyond native conditional budget; no sampling admitted")
    setup<-gapr_log_target(target,m,components=TRUE)
    q(is.finite(setup$value),"parent setup path has nonfinite density")
    starts<-gacr_start_paths(m,V,setup$locations$reference_location)
    if(s$execution_mode=="fork_four") {
      payload$pre_fork_MemAvailable_bytes<-gacr_memory_admission(s)
      counts$chains<-4L
      parts<-gacr_fork_dispatch(function(chain) {
        ctl<-control;ctl$chain_ids<-chain
        before<-engine$audit$value_calls
        tryCatch(gapr_sample_reference(target,starts,control=ctl,proposal_covariance=V),
          error=function(e)list(status="FAIL_CONDITIONAL_CHAIN",qualified=FALSE,
            callback_evaluations=engine$audit$value_calls-before,
            conditional_reference_chains_attempted=as.integer(engine$audit$value_calls>before),
            conditional_reference_chains_completed=0L,error=conditionMessage(e)))
      },as.numeric(unlist(s$limits$child_logical_cpus)),s$limits$child_cpu_seconds)
      worker_proofs<-lapply(parts,function(p)c(p$proof,list(CPU_seconds=p$CPU_seconds)))
      result<-gapr_combine_chains(lapply(parts,function(p)p$result),target,control)
      child_evaluations<-sum(vapply(parts,function(p)if(is.null(p$result$callback_evaluations))0 else
        p$result$callback_evaluations,numeric(1L)))
      payload$worker_status<-vapply(parts,function(p)p$result$status,character(1L))
      counts$chains<-sum(vapply(parts,function(p)if(is.null(p$result$conditional_reference_chains_attempted))0 else
        p$result$conditional_reference_chains_attempted,numeric(1L)))
      child_accounting_complete<-TRUE
    } else {
      counts$chains<-4L;result<-gapr_sample_reference(target,starts,control=control,proposal_covariance=V)
      counts$chains<-result$conditional_reference_chains_attempted
      child_evaluations<-0L
    }
    payload$reference<-result[intersect(c("status","qualified","diagnostics","dependency","callback_evaluations",
      "conditional_reference_chains_requested","conditional_reference_chains_attempted",
      "conditional_reference_chains_completed","scope","interpretation"),names(result))]
    payload$sampler_controls<-control
    payload$proposal_covariance<-V
    payload$chain_transition_states<-result$chain_states
    diagnostic_draws<-result$draws
    if(is.null(diagnostic_draws)&&s$execution_mode=="fork_four") {
      diagnostic_draws<-array(NA_real_,c(control$samples,4L,28L))
      payload$chain_transition_states<-stats::setNames(vector("list",4L),paste0("chain",1:4))
      for(i in 1:4) {
        p<-parts[[i]]$result
        if(!is.null(p$draws)&&identical(dim(p$draws),dim(diagnostic_draws)))diagnostic_draws[,i,]<-p$draws[,i,]
        if(!is.null(p$chain_states[[i]]))payload$chain_transition_states[[i]]<-p$chain_states[[i]]
      }
    }
    if(!is.null(diagnostic_draws)&&any(is.finite(diagnostic_draws)))
      payload$generated_draw_export<-gacr_write_draws(diagnostic_draws,s) else
      payload$generated_draw_export<-list(status="NO_RETAINED_DRAWS_BEFORE_FAILURE")
    if(!is.null(result$quantiles))outputs$conditional_reference_quantiles.csv<-gfr_csv_raw(result$quantiles)
    if(!is.null(result$diagnostics))outputs$conditional_reference_diagnostics.csv<-gfr_csv_raw(result$diagnostics)
    reference_qualified<-isTRUE(result$qualified)
    status<-if(reference_qualified)"CONDITIONAL_REFERENCE_DIAGNOSTICS_PASSED_NOT_FULL_POSTERIOR" else "INCONCLUSIVE_CONDITIONAL_REFERENCE"
    rm(result,diagnostic_draws);gc(FALSE)
  }
  payload$status<-status;payload$worker_proofs<-worker_proofs
  payload$conditional_reference_chains_attempted<-counts$chains
  payload$conditional_vb_optimizations_attempted<-counts$vb
  payload$value_evaluations<-engine$audit$value_calls+if(exists("child_evaluations"))child_evaluations else 0L
  payload$jacobian_evaluations<-engine$audit$factory_calls
  if(s$conditional$value_backend=="compiled_input_reference")payload$compiled_value_parent<-gcv_diagnostics(value_builder)
  q(payload$value_evaluations<=s$conditional$max_total_value_evaluations&&
    payload$jacobian_evaluations<=s$conditional$max_jacobian_evaluations&&engine$audit$forbidden_calls==0L,
    "conditional callback/prohibited-operation accounting failed")
  outputs$conditional_summary.json<-gfr_json_raw(payload)
  q(sum(vapply(outputs,length,integer(1L)))<=s$read_budget$max_conditional_output_bytes,"compact conditional output cap exceeded")
  for(name in names(outputs))gfr_write(outputs[[name]],file.path(out,name),out,s$limits$output_bytes)
  post_hash();for(pin in meta)gsc_pin(pin,4*1024^2);gacr_source(s)
  cpu<-sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])
  q(cpu<=s$limits$aggregate_cpu_seconds&&expiry>Sys.time()&&length(attempts)==2L,
    "native aggregate CPU/lifetime/read closure failed")
  receipt<-list(schema_version="glofas_al_conditional_reference_receipt_v1",status=status,mode=s$mode,
    purpose_sha256=args[4L],source_commit=s$source_commit,source_tree=s$source_tree,
    producer_identity=gsc_identity(),input_bindings=s[c("design","median_model")],
    accepted_collection=s$collection,input_manifest=s$input_manifest,prior_replay=s$prior_replay,prior_pilot=s$prior_pilot,
    original_RDS_deserializations=2L,read_cost=cost,attempted_reads=attempts,
    conditional_reference_chains_attempted=counts$chains,conditional_vb_optimizations_attempted=counts$vb,
    full_parameter_refits=0L,saved_callback_calls=0L,future_truth_read=FALSE,retuning=FALSE,
    value_evaluations=payload$value_evaluations,jacobian_evaluations=payload$jacobian_evaluations,
    metadata_serializations=engine$audit$metadata,worker_proofs=worker_proofs,
    generated_draw_export=payload$generated_draw_export,
    aggregate_cpu_seconds=cpu,conservative_aggregate_address_space_cap=s$limits$aggregate_memory_bytes,
    aggregate_peak_RSS_not_measured_here=TRUE,reference_qualified=reference_qualified,
    full_posterior_accuracy_qualified=FALSE,publication_authorized=FALSE,
    independent_supervisor_closure_still_required=TRUE)
  gfr_write(gfr_json_raw(receipt),file.path(out,"CONDITIONAL_REFERENCE_RECEIPT.json"),out,s$limits$output_bytes)
  files<-list.files(out,full.names=TRUE)
  inventory<-data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,
    sha256=unname(tools::sha256sum(files)))
  gfr_write(gfr_csv_raw(inventory),file.path(out,"artifact_manifest.csv"),out,s$limits$output_bytes)
  finished<-TRUE;cat("GLOFAS_MEDIAN_AL_CONDITIONAL_DIAGNOSTIC_CLOSED_NO_FULL_REFIT_NO_TRUTH\n")
  invisible(receipt)
}
if(sys.nframe()==0L)gacr_main()
