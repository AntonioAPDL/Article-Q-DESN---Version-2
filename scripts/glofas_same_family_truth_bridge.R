#!/usr/bin/env Rscript
# A separate post-seal truth interface. No fit, forecast selection or publication.
source("scripts/glofas_same_family_closeout.R")

gst_truth_identity <- function()list(size_bytes=862,
  sha256="24be9fa631bca346a04a7a855bff5ef3ebc7bf5c748fbade7a213d88fdfe63e6",
  role="post_fit_scoring_sidecar")
gst_unique_objects <- function(x,depth=0L) {
  gsc_require(depth<=40L,"truth metadata nesting limit")
  if(is.list(x)&&!is.data.frame(x)) {
    n<-names(x)
    gsc_require(is.null(n)||(!anyDuplicated(n)&&all(nzchar(n))),"duplicate or empty truth metadata object key")
    for(v in x)gst_unique_objects(v,depth+1L)
  }
  invisible(TRUE)
}
gst_same <- function(a,b) {
  if(is.list(a)&&is.list(b)&&!is.data.frame(a)&&!is.data.frame(b)) {
    if(length(a)!=length(b)||is.null(names(a))!=is.null(names(b)))return(FALSE)
    if(!is.null(names(a))) {
      if(anyDuplicated(names(a))||anyDuplicated(names(b))||!setequal(names(a),names(b)))return(FALSE)
      b<-b[match(names(a),names(b))]
    }
    return(all(vapply(seq_along(a),function(i)gst_same(a[[i]],b[[i]]),logical(1L))))
  }
  if(is.numeric(a)&&is.numeric(b))return(identical(dim(a),dim(b))&&length(a)==length(b)&&
    isTRUE(all(as.double(a)==as.double(b))))
  identical(a,b)
}
gst_truth_pin_identity <- function(x) {
  fixed<-gst_truth_identity()
  gsc_require(is.list(x)&&length(x)==3L&&!anyDuplicated(names(x))&&setequal(names(x),c("path","size_bytes","sha256"))&&
    is.character(x$path)&&length(x$path)==1L&&startsWith(x$path,"/")&&
    identical(basename(x$path),"part4_scoring_panel_sidecar.rds")&&
    x$size_bytes==fixed$size_bytes&&identical(x$sha256,fixed$sha256),
    "the frozen original scoring-only truth identity is required")
  invisible(TRUE)
}
gst_no_callbacks <- function(x,depth=0L) {
  gsc_require(depth<=12L&&!is.function(x)&&!is.environment(x)&&!isS4(x)&&!is.language(x)&&
    !typeof(x)%in%c("externalptr","weakref","promise"),"truth object contains a callback or opaque object")
  gsc_require(all(names(attributes(x))%in%c("names","class","row.names","dim","dimnames")),
    "unknown truth-object attributes")
  if(is.list(x))for(v in x)gst_no_callbacks(v,depth+1L)
  for(v in attributes(x))gst_no_callbacks(v,depth+1L)
  invisible(TRUE)
}
gst_truth_rows <- function(x,issued_dates=gsc_dates()) {
  q<-gsc_require;gst_no_callbacks(x)
  q(is.list(x)&&!anyDuplicated(names(x))&&setequal(names(x),
      c("panel","role","future_truth_used_in_fit","future_truth_rows"))&&
    identical(x$role,"post_fit_scoring_sidecar")&&identical(x$future_truth_used_in_fit,FALSE),
    "original source-constructed post-fit truth schema required")
  p<-x$panel
  q(is.data.frame(p)&&identical(class(p),"data.frame")&&identical(names(p),c("target_date","y_transformed"))&&
    nrow(p)%in%c(28L,30L)&&x$future_truth_rows==nrow(p)&&
    (identical(class(p$target_date),"Date")||(is.character(p$target_date)&&is.null(attributes(p$target_date))))&&
    is.numeric(p$y_transformed)&&is.null(attributes(p$y_transformed))&&all(is.finite(p$y_transformed)),
    "source truth panel schema or length differs")
  dates<-as.Date(p$target_date)
  q(!anyNA(dates)&&!anyDuplicated(dates)&&identical(as.Date(issued_dates),gsc_dates())&&
    setequal(dates,as.Date("2022-12-25")+seq_len(nrow(p))),"source truth dates are not the declared complete post-origin window")
  at<-match(issued_dates,dates)
  q(length(at)==28L&&!anyNA(at),"issued-window truth must match all sealed dates, not a truncated prefix")
  data.frame(target_date=as.character(issued_dates),horizon=seq_len(28L),
    y_transformed=p$y_transformed[at],stringsAsFactors=FALSE)
}

gst_assembly <- function(root,manifest_pin,seal_pin) {
  q<-gsc_require;root<-normalizePath(root,mustWork=TRUE)
  q(identical(manifest_pin$path,file.path(root,"artifact_manifest.csv"))&&
    identical(seal_pin$path,file.path(root,"FORECAST_SEAL.json")),"exact original pre-truth assembly pins required")
  m<-read.csv(gsc_pin(manifest_pin,1024^2),stringsAsFactors=FALSE)
  names<-c("quantile_paths.csv","raw_crossings.csv","accepted_producers.json","FORECAST_SEAL.json","DECISION.json","progress.json")
  q(identical(colnames(m),c("relative_path","size_bytes","sha256"))&&
    !anyDuplicated(m$relative_path)&&setequal(m$relative_path,names)&&
    setequal(list.files(root,all.files=TRUE,no..=TRUE),c(names,"artifact_manifest.csv")),"complete original assembly membership required")
  for(i in seq_len(nrow(m)))gsc_pin(list(path=file.path(root,m$relative_path[i]),size_bytes=m$size_bytes[i],sha256=m$sha256[i]),8*1024^2)
  gsc_pin(seal_pin,2*1024^2)
  q(identical(m$sha256[m$relative_path=="FORECAST_SEAL.json"],seal_pin$sha256),"original forecast seal is not bound to its assembly")
  decision<-jsonlite::read_json(file.path(root,"DECISION.json"),simplifyVector=FALSE)
  q(identical(decision$schema_version,"glofas_same_family_closeout_receipt_v1")&&
    identical(decision$status,"ASSEMBLED_COMPLETE_GRID_NO_TRUTH_READ")&&identical(decision$mode,"assemble")&&
    identical(decision$future_truth_read,FALSE)&&identical(decision$model_selection_or_retuning,FALSE)&&
    decision$new_fits==0&&identical(decision$article_publication_authorized,FALSE)&&
    identical(decision$forecast_seal_sha256,seal_pin$sha256),"genuine complete truth-free assembly decision required")
  seal<-gsc_verify_forecast_seal(root,seal_pin$sha256)
  for(pin in seal$input_bindings)gsc_pin(pin,2*1024^2)
  list(seal=seal,decision=decision,manifest=manifest_pin,seal_pin=seal_pin,root=root)
}
gst_forecasts_equal <- function(a,b) {
  q<-gsc_require
  # Hashes cover all quantile values, crossings and all sixteen accepted producers.
  q(gst_same(a$expected_identity,b$expected_identity)&&
    identical(a$prepared_design_sha256,b$prepared_design_sha256)&&
    gst_same(a$input_bindings,b$input_bindings)&&gst_same(a$artifacts,b$artifacts),
    "forecasts or producer/input bindings changed after the first pre-truth seal")
  invisible(TRUE)
}
gst_provenance_row <- function(pin,truth_pin) {
  gst_truth_pin_identity(truth_pin)
  p<-read.csv(gsc_pin(pin,1024^2),stringsAsFactors=FALSE)
  q<-gsc_require
  q(all(c("path","size_bytes","sha256")%in%names(p)),"original truth provenance-manifest schema required")
  at<-which(basename(p$path)=="part4_scoring_panel_sidecar.rds"&
    p$size_bytes==truth_pin$size_bytes&p$sha256==truth_pin$sha256)
  q(length(at)==1L,"one frozen original truth provenance row required")
  list(recorded_path=p$path[at],materialized_path=truth_pin$path,
    size_bytes=truth_pin$size_bytes,sha256=truth_pin$sha256,
    relocation_rule="same_original_role_size_SHA256_no_value_or_transform_change")
}

gst_scope <- function(s) {
  q<-gsc_require
  gst_unique_objects(s)
  q(is.list(s)&&identical(s$schema_version,"glofas_same_family_truth_bridge_contract_v1")&&
    identical(s$mode,"extract_scoring_truth_after_forecast_seal")&&identical(s$allow_truth_read,TRUE)&&
    identical(s$allow_refit,FALSE)&&identical(s$allow_retuning,FALSE)&&
    identical(s$allow_forecast_changes,FALSE)&&identical(s$allow_publication,FALSE)&&
    identical(s$truth_role,"post_fit_scoring_only"),"separate post-seal truth-only authority required")
  gst_truth_pin_identity(s$truth_rds)
  b<-s$limits
  q(is.list(b)&&all(vapply(b[c("cpu_seconds","wall_seconds","memory_bytes","output_bytes","logical_cpu")],
    function(v)is.numeric(v)&&length(v)==1L&&is.finite(v)&&v==floor(v),logical(1L)))&&
    b$cpu_seconds>=10&&b$cpu_seconds<=120&&b$wall_seconds==b$cpu_seconds&&
    b$memory_bytes>0&&b$memory_bytes<=2*1024^3&&b$output_bytes>0&&b$output_bytes<=8*1024^2&&
    b$logical_cpu>=0&&b$logical_cpu<=63&&!b$logical_cpu%in%c(24,25,48,50,56,57,16,18),
    "finite one-core separately admitted truth-bridge budget required")
  invisible(TRUE)
}
gst_timeout_argv <- function(argv,wall_seconds) {
  gsc_require(is.character(argv)&&!anyNA(argv)&&length(argv)>=5L&&
    is.numeric(wall_seconds)&&length(wall_seconds)==1L&&is.finite(wall_seconds)&&wall_seconds>=10&&
    identical(basename(argv[1L]),"timeout")&&
    identical(argv[2:4],c("--signal=TERM","--kill-after=1s",paste0(wall_seconds-1L,"s")))&&
    !startsWith(argv[5L],"-"),"exact native whole-group truth-bridge timeout required")
  invisible(TRUE)
}
gst_process_ids <- function(line) {
  q<-gsc_require;m<-regmatches(line,regexec("^([0-9]+) \\((.*)\\) [[:alpha:]] ([0-9]+) ([0-9]+) ([0-9]+) ",line))[[1L]]
  q(length(m)==6L,"native process identity required")
  ids<-setNames(as.numeric(m[c(2L,4L,5L,6L)]),c("pid","ppid","pgid","sid"))
  q(all(is.finite(ids))&&ids[["pid"]]>0&&ids[["ppid"]]>=0&&all(ids[c("pgid","sid")]>0),
    "finite positive native process identities required")
  ids
}
gst_group <- function(self,timeout) {
  a<-gst_process_ids(self);b<-gst_process_ids(timeout)
  gsc_require(b[["pid"]]==b[["pgid"]]&&a[["pid"]]!=b[["pid"]]&&
    a[["pgid"]]==b[["pgid"]]&&a[["sid"]]==b[["sid"]],"truth bridge escaped its timeout group/session")
  invisible(TRUE)
}
gst_runtime <- function(s) {
  q<-gsc_require;b<-s$limits
  q(as.character(getRversion())=="4.6.0"&&"--vanilla"%in%commandArgs(FALSE)&&
    Sys.info()[["nodename"]]%in%c("muscat","muscat.be.ucsc.edu")&&Sys.getenv("LD_PRELOAD")==""&&
    all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1"),"native vanilla Muscat R4.6 one-thread truth runtime required")
  affinity<-function(pid="self")trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",
    readLines(sprintf("/proc/%s/status",pid),warn=FALSE),value=TRUE)))
  q(identical(affinity(),as.character(b$logical_cpu)),"truth bridge CPU differs")
  limits<-readLines("/proc/self/limits",warn=FALSE)
  for(p in list(c("Max cpu time",b$cpu_seconds),c("Max address space",b$memory_bytes),c("Max file size",b$output_bytes))) {
    line<-grep(paste0("^",p[1L]),limits,value=TRUE)
    q(length(line)==1L,"missing native truth-bridge limit")
    v<-suppressWarnings(as.numeric(strsplit(trimws(sub(paste0("^",p[1L]),"",line)),"[[:space:]]+")[[1L]][1:2]))
    q(all(is.finite(v))&&all(v>0)&&all(v<=as.numeric(p[2L])),"finite native truth-bridge limits required")
  }
  pid<-Sys.getpid()
  for(i in 1:12) {
    x<-gst_process_ids(readLines(sprintf("/proc/%d/stat",pid),warn=FALSE));parent<-x[["ppid"]]
    if(parent<=1)break
    raw<-readBin(sprintf("/proc/%d/cmdline",parent),"raw",n=16384L);raw[raw==as.raw(0)]<-as.raw(10)
    argv<-strsplit(rawToChar(raw),"\n",fixed=TRUE)[[1L]]
    if(length(argv)&&basename(argv[1L])=="timeout") {
      gst_timeout_argv(argv,b$wall_seconds)
      q(identical(normalizePath(Sys.readlink(sprintf("/proc/%d/exe",parent))),normalizePath("/usr/bin/timeout"))&&
        identical(affinity(as.character(parent)),as.character(b$logical_cpu)),"truth timeout executable/affinity differs")
      gst_group(readLines("/proc/self/stat",warn=FALSE),readLines(sprintf("/proc/%d/stat",parent),warn=FALSE))
      return(invisible(TRUE))
    };pid<-parent
  }
  q(FALSE,"native truth-bridge timeout ancestor missing")
}
gst_source <- function(s,root) {
  q<-gsc_require
  git<-function(a) {v<-system2("/usr/bin/git",c("--no-replace-objects","-C",shQuote(root),a),stdout=TRUE);q(is.null(attr(v,"status")),"truth-source Git check failed");unname(v)}
  q(identical(git(c("rev-parse","HEAD")),s$source_commit)&&identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=normal"))),"clean frozen truth-bridge source required")
  required<-c("scripts/glofas_same_family_truth_bridge.R","scripts/glofas_same_family_closeout.R",
    "application/scripts/386_run_glofas_part4_latent_family_job.R")
  paths<-vapply(s$source_files,gsc_pin,character(1L),max_bytes=1024^2)
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,required)),"exact bridge/validator/source-constructor closure required")
  for(rel in required)q(identical(git(c("hash-object","--no-filters","--",shQuote(file.path(root,rel)))),
    git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel))))),"truth source is not its committed blob")
  invisible(TRUE)
}

gst_truth_interface <- function(s) {
  version<-s$truth_interface_version
  # Existing exact-CSV purposes remain historical v1. New purposes should
  # always spell out the version; the RDS-derived route must explicitly be v2.
  if(is.null(version))version<-"legacy_pinned_csv_v1"
  gsc_require(is.character(version)&&length(version)==1L&&
    version%in%c("legacy_pinned_csv_v1","authenticated_truth_bridge_v2"),"unknown scoring-truth interface version")
  version
}
gst_validate_score_truth <- function(s,current_seal) {
  q<-gsc_require
  q(identical(gst_truth_interface(s),"authenticated_truth_bridge_v2"),"authenticated truth-bridge v2 required")
  d<-jsonlite::read_json(gsc_pin(s$truth_derivation,2*1024^2),simplifyVector=FALSE)
  p<-jsonlite::read_json(gsc_pin(s$truth_adapter_purpose,1024^2),simplifyVector=FALSE)
  gst_scope(p)
  gst_unique_objects(d)
  q(identical(d$schema_version,"glofas_same_family_scoring_truth_derivation_v1")&&
    identical(d$status,"SCORING_TRUTH_EXTRACTED_AFTER_COMPLETE_FORECAST_SEAL")&&
    identical(d$source_commit,s$source_commit)&&identical(d$source_tree,s$source_tree)&&
    identical(p$source_commit,s$source_commit)&&identical(p$source_tree,s$source_tree)&&
    identical(d$contract_sha256,s$truth_adapter_purpose$sha256)&&
    d$original_RDS_deserializations==1&&d$retained_rows==28&&d$source_panel_rows%in%c(28L,30L)&&
    identical(d$transform,"log1p")&&identical(d$new_transform_applied,FALSE)&&
    identical(d$selection_rule,"exact_match_to_all_28_sealed_issued_dates_not_blind_truncation")&&
    gst_same(d$retained_dates,as.list(as.character(gsc_dates())))&&
    identical(as.numeric(unlist(d$horizons)),as.numeric(1:28))&&
    d$model_calls==0&&d$new_fits==0&&identical(d$model_selection_or_retuning,FALSE)&&
    identical(d$forecast_changes,FALSE)&&identical(d$publication_authorized,FALSE),
    "truth derivation scope, issued dates or source identity differs")
  gst_truth_pin_identity(d$truth_rds);gst_truth_pin_identity(s$truth_rds)
  q(gst_same(d$truth_rds,p$truth_rds)&&gst_same(d$truth_rds,s$truth_rds)&&
    gst_same(d$truth_provenance_manifest,p$truth_provenance_manifest)&&
    gst_same(d$truth_provenance_manifest,s$truth_provenance_manifest)&&
    gst_same(d$source_files,p$source_files)&&gst_same(d$csv,s$truth)&&
    identical(dirname(d$csv$path),p$output_root)&&identical(basename(d$csv$path),"scoring_truth.csv"),
    "truth CSV is not bound to the exact original input and separately approved producer")
  provenance<-gst_provenance_row(s$truth_provenance_manifest,s$truth_rds)
  q(gst_same(provenance,d$original_materialization)&&gst_same(d$assembly_manifest,p$assembly_manifest)&&
    gst_same(d$assembly_forecast_seal,p$assembly_forecast_seal)&&identical(d$assembly_root,p$assembly_root)&&
    gst_same(d$assembly_manifest,s$assembly_manifest)&&gst_same(d$assembly_forecast_seal,s$assembly_forecast_seal)&&
    identical(d$assembly_root,s$assembly_root),"original pre-truth assembly binding differs")
  a<-gst_assembly(d$assembly_root,d$assembly_manifest,d$assembly_forecast_seal)
  q(gst_same(d$sealed_forecast_artifacts,a$seal$artifacts)&&
    gst_same(d$sealed_forecast_input_bindings,a$seal$input_bindings),"truth derivation no longer matches its pre-truth seal")
  gst_forecasts_equal(a$seal,current_seal)
  source_path<-vapply(p$source_files,`[[`,character(1L),"path")
  source_path<-source_path[basename(source_path)=="glofas_same_family_truth_bridge.R"]
  q(length(source_path)==1L,"truth producer source namespace missing")
  gst_source(p,dirname(dirname(source_path)))
  # Deliberately do not reopen the original RDS or CSV here. Original RDS
  # bytes were authenticated by the separately admitted producer; the caller
  # may read the exact derived CSV only after all of these gates pass.
  d
}

gst_bridge_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript --vanilla scripts/glofas_same_family_truth_bridge.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  q<-gsc_require
  q(length(args)==5L&&identical(args[c(1L,3L,5L)],c("--contract","--sha256","--execute")),"exact separate truth contract/digest/execute arguments required")
  cp<-normalizePath(args[2L],mustWork=TRUE)
  q(file.info(cp)$size<=1024^2&&identical(unname(tools::sha256sum(cp)),args[4L]),"truth purpose digest differs")
  s<-jsonlite::read_json(cp,simplifyVector=FALSE);gst_scope(s);root<-normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(cp,paste0(root,"/")),"external truth authority required")
  expiry<-as.POSIXct(s$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry)&&expiry>Sys.time()+s$limits$wall_seconds,"complete finite truth-purpose lifetime required")
  gst_runtime(s);gst_source(s,root)
  # No original scoring truth is opened until the immutable complete forecast
  # surface, all sixteen accepted producers and source proof have passed.
  a<-gst_assembly(s$assembly_root,s$assembly_manifest,s$assembly_forecast_seal)
  provenance<-gst_provenance_row(s$truth_provenance_manifest,s$truth_rds)
  out<-s$output_root
  q(is.character(out)&&length(out)==1L&&startsWith(out,paste0(root,"/local_trackers/"))&&
    !file.exists(out)&&dir.exists(dirname(out))&&identical(normalizePath(dirname(out)),dirname(out))&&
    !grepl("(^|/)\\.\\.(/|$)",out)&&system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(out)))==0L,
    "fresh ignored truth output required")
  q(dir.create(out),"truth output creation failed")
  read_attempts<-0L;completed_deserializations<-0L;phase<-"COMPLETE_FORECAST_SEAL_VERIFIED_NO_TRUTH_READ"
  progress<-function(status)jsonlite::write_json(list(status=status,phase=phase,source_commit=s$source_commit,
    contract_sha256=args[4L],original_RDS_read_attempts=read_attempts,
    completed_RDS_deserializations=completed_deserializations,publication_authorized=FALSE),
    file.path(out,"progress.json"),auto_unbox=TRUE,pretty=TRUE)
  seal_output<-function() {
    files<-list.files(out,full.names=TRUE);files<-files[basename(files)!="artifact_manifest.csv"]
    q(all(!file.info(files)$isdir)&&all(!nzchar(Sys.readlink(files)))&&
      sum(file.info(files)$size)+65536<s$limits$output_bytes,"complete truth output budget exceeded")
    write.csv(data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,
      sha256=unname(tools::sha256sum(files))),file.path(out,"artifact_manifest.csv"),row.names=FALSE)
  }
  progress("TRUTH_BRIDGE_ADMITTED_AFTER_FORECAST_SEAL")
  tryCatch({
  truth_path<-gsc_pin(s$truth_rds,1024^2)
  phase<-"ORIGINAL_TRUTH_RDS_DESERIALIZATION";read_attempts<-1L
  progress("TRUTH_BRIDGE_RUNNING")
  object<-readRDS(truth_path);completed_deserializations<-1L
  rows<-gst_truth_rows(object);source_rows<-nrow(object$panel)
  rm(object)
  gsc_pin(s$truth_rds,1024^2);gsc_pin(s$truth_provenance_manifest,1024^2)
  gst_assembly(s$assembly_root,s$assembly_manifest,s$assembly_forecast_seal);gst_source(s,root)
  phase<-"EXACT_ISSUED_WINDOW_VALIDATED_AND_ORIGINAL_SEAL_RECHECKED"
  write.csv(rows,file.path(out,"scoring_truth.csv"),row.names=FALSE)
  csv_pin<-list(path=file.path(out,"scoring_truth.csv"),size_bytes=as.numeric(file.info(file.path(out,"scoring_truth.csv"))$size),
    sha256=unname(tools::sha256sum(file.path(out,"scoring_truth.csv"))))
  d<-list(schema_version="glofas_same_family_scoring_truth_derivation_v1",status="SCORING_TRUTH_EXTRACTED_AFTER_COMPLETE_FORECAST_SEAL",
    source_commit=s$source_commit,source_tree=s$source_tree,contract_sha256=args[4L],
    source_files=s$source_files,truth_rds=s$truth_rds,truth_provenance_manifest=s$truth_provenance_manifest,
    original_materialization=provenance,assembly_root=s$assembly_root,assembly_manifest=s$assembly_manifest,
    assembly_forecast_seal=s$assembly_forecast_seal,sealed_forecast_artifacts=a$seal$artifacts,
    sealed_forecast_input_bindings=a$seal$input_bindings,csv=csv_pin,
    original_RDS_deserializations=1L,source_panel_rows=source_rows,retained_rows=28L,
    retained_dates=as.character(gsc_dates()),horizons=seq_len(28L),transform="log1p",new_transform_applied=FALSE,
    selection_rule="exact_match_to_all_28_sealed_issued_dates_not_blind_truncation",
    model_calls=0L,new_fits=0L,model_selection_or_retuning=FALSE,forecast_changes=FALSE,publication_authorized=FALSE)
  jsonlite::write_json(d,file.path(out,"TRUTH_DERIVATION.json"),auto_unbox=TRUE,pretty=TRUE,digits=17)
  q(file.copy(cp,file.path(out,"TRUTH_PURPOSE.json"),overwrite=FALSE),"truth purpose retention failed")
  gst_assembly(s$assembly_root,s$assembly_manifest,s$assembly_forecast_seal);gst_source(s,root)
  cpu<-sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])
  q(cpu<=s$limits$cpu_seconds&&expiry>Sys.time(),"whole truth-purpose CPU/wall budget exceeded")
  phase<-"TRUTH_BRIDGE_COMPLETE_NOT_PUBLICATION";progress(phase);seal_output()
  cat("GLOFAS_SCORING_TRUTH_BRIDGE_COMPLETE_NOT_PUBLICATION\n")
  invisible(d)
  },error=function(e) {
    try(jsonlite::write_json(list(status="TRUTH_BRIDGE_FAILED_NOT_PUBLICATION",error=conditionMessage(e),
      source_commit=s$source_commit,contract_sha256=args[4L],phase=phase,
      original_RDS_read_attempts=read_attempts,completed_RDS_deserializations=completed_deserializations,
      publication_authorized=FALSE),file.path(out,"failure.json"),auto_unbox=TRUE,pretty=TRUE),silent=TRUE)
    try(progress("TRUTH_BRIDGE_FAILED_NOT_PUBLICATION"),silent=TRUE);try(seal_output(),silent=TRUE)
    stop(e)
  })
}

if(sys.nframe()==0L)gst_bridge_main()
