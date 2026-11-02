#!/usr/bin/env Rscript
# New, source-bound closeout only; never invoke the legacy fitter/finalizer.
source("scripts/glofas_same_family_closeout.R")
source("scripts/glofas_same_family_truth_bridge.R")

gsc_closeout_scope <- function(s,mode) {
  q <- gsc_require
  q(is.list(s)&&identical(s$schema_version,"glofas_same_family_closeout_contract_v1")&&
    mode %in% c("extract","assemble","score")&&identical(s$mode,mode)&&
    identical(s$allow_refit,FALSE)&&identical(s$allow_retuning,FALSE)&&
    identical(s$allow_publication,FALSE)&&identical(s$allow_assembly,mode!="extract")&&
    identical(s$allow_scoring,mode=="score")&&identical(isTRUE(s$allow_design_read),mode=="extract"),
    "explicit extraction/assembly/scoring-only authority required")
  b <- s$limits
  if(mode=="score")gst_truth_interface(s)
  q(is.list(b)&&all(vapply(b[c("cpu_seconds","wall_seconds","memory_bytes","output_bytes","logical_cpu")],
    function(v)is.numeric(v)&&length(v)==1L&&is.finite(v)&&v>=0,logical(1L)))&&
    b$cpu_seconds>0&&b$cpu_seconds<=1200&&b$wall_seconds>=60&&b$wall_seconds<=1800&&
    b$memory_bytes>0&&b$memory_bytes<=32*1024^3&&b$output_bytes>0&&b$output_bytes<=64*1024^2&&
    !b$logical_cpu %in% c(24,25,48,50,56,57,16,18),"finite separate closeout budget required")
  invisible(TRUE)
}

gsc_closeout_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript scripts/finalize_glofas_same_family_transition.R --contract FILE --sha256 SHA --mode extract|assemble|score --execute\n")
    return(invisible(NULL))
  }
  q <- gsc_require
  q(length(args)==7L&&args[1L]=="--contract"&&args[3L]=="--sha256"&&
    args[5L]=="--mode"&&args[7L]=="--execute","exact contract, digest, mode and execute arguments required")
  path <- normalizePath(args[2L],mustWork=TRUE)
  q(file.info(path)$size<=1024^2&&identical(unname(tools::sha256sum(path)),args[4L]),"external purpose digest")
  s <- jsonlite::read_json(path,simplifyVector=FALSE);mode <- args[6L];gsc_closeout_scope(s,mode)
  root <- normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(path,paste0(root,"/")),"purpose must be outside source checkout")
  git <- function(a) {z <- system2("git",a,stdout=TRUE);q(is.null(attr(z,"status")),"Git check failed");unname(z)}
  check_source <- function() q(identical(git(c("rev-parse","HEAD")),s$source_commit)&&
    identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=normal"))),"clean frozen source required")
  check_source()
  expiry <- as.POSIXct(s$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry)&&expiry>Sys.time()+s$limits$wall_seconds&&as.character(getRversion())=="4.6.0"&&
    Sys.info()[["nodename"]] %in% c("muscat","muscat.be.ucsc.edu")&&
    all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1"),"exact runtime and complete lifetime required")
  st <- readLines("/proc/self/status");aff <- trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",st,value=TRUE)))
  q(identical(aff,as.character(s$limits$logical_cpu)),"administrative CPU scope differs")
  limits <- readLines("/proc/self/limits")
  for(pair in list(c("Max cpu time",s$limits$cpu_seconds),c("Max address space",s$limits$memory_bytes),
    c("Max file size",s$limits$output_bytes))) {
    v <- suppressWarnings(as.numeric(strsplit(trimws(sub(paste0("^",pair[1L]),"",
      grep(paste0("^",pair[1L]),limits,value=TRUE))),"[[:space:]]+")[[1L]][1:2]))
    q(all(is.finite(v))&&all(v<=as.numeric(pair[2L])),"finite external process limits required")
  }
  # A native whole-process timeout, not only R's evaluator clock, is required.
  ancestor <- Sys.getpid();wall_proof <- FALSE
  for(i in seq_len(12L)) {
    st <- readLines(sprintf("/proc/%d/status",ancestor),warn=FALSE)
    pp <- as.integer(trimws(sub("^PPid:","",grep("^PPid:",st,value=TRUE))))
    if(length(pp)!=1L||is.na(pp)||pp<=1)break
    raw <- readBin(sprintf("/proc/%d/cmdline",pp),"raw",n=16384L);raw[raw==as.raw(0)] <- as.raw(10)
    a <- strsplit(rawToChar(raw),"\n",fixed=TRUE)[[1L]]
    if(length(a)>=5L&&basename(a[1L])=="timeout") {
      wall_proof <- identical(a[2:4],c("--signal=TERM","--kill-after=1s",paste0(s$limits$wall_seconds-1,"s")))&&
        identical(normalizePath(Sys.readlink(sprintf("/proc/%d/exe",pp))),normalizePath("/usr/bin/timeout"));break
    };ancestor <- pp
  }
  q(wall_proof,"whole-purpose exact TERM/KILL supervisor required")
  required <- c("scripts/glofas_same_family_closeout.R","scripts/finalize_glofas_same_family_transition.R",
    "scripts/collect_glofas_same_family_producers.py","application/scripts/forecast_transition_control.py",
    "scripts/glofas_same_family_truth_bridge.R")
  if(mode=="extract")required <- c(required,"scripts/glofas_same_family_plot_inputs.R")
  source_paths <- vapply(s$source_files,gsc_pin,character(1L),max_bytes=1024^2)
  q(all(file.path(root,required) %in% source_paths)&&all(startsWith(source_paths,paste0(root,"/")))&&
    !anyDuplicated(source_paths),"complete reviewed closeout source closure required")
  gsc_pin(s$collection_contract,1024^2)
  # This is the only ledger interface: native query-only snapshot verification.
  cp <- system2("/usr/bin/python3.11",c(shQuote(file.path(root,required[3L])),"--contract",
    shQuote(s$collection_contract$path),"--sha256",s$collection_contract$sha256),stdout=TRUE)
  q(is.null(attr(cp,"status"))&&sum(nchar(cp,type="bytes"))<4*1024^2,"complete accepted producer verification failed")
  collection <- jsonlite::fromJSON(paste(cp,collapse="\n"),simplifyVector=FALSE)
  gsc_validate_collection(collection,s$expected_identity)
  quantiles <- list();targets <- list()
  for(z in collection$producers) {
    paths <- stats::setNames(z$artifacts,vapply(z$artifacts,`[[`,character(1L),"relative_path"))
    target <- jsonlite::read_json(gsc_pin(paths[["target_receipt.json"]],16*1024^2),simplifyVector=FALSE)
    gsc_validate_target(target,z);targets[[z$task_id]] <- target
    quantiles[[z$task_id]] <- read.csv(gsc_pin(paths[["forecast_quantiles.csv"]],1024^2),stringsAsFactors=FALSE)
  }
  normal <- jsonlite::read_json(gsc_pin(s$normal_receipt,2*1024^2),simplifyVector=FALSE)
  nm <- read.csv(gsc_pin(s$normal_manifest,1024^2),stringsAsFactors=FALSE)
  for(b in s[c("normal_receipt","normal_quantiles")]) {
    at <- which(nm$relative_path==basename(b$path))
    q(length(at)==1L&&nm$sha256[at]==b$sha256&&nm$size_bytes[at]==b$size_bytes,"Normal artifact-manifest binding differs")
  }
  normal_rows <- read.csv(gsc_pin(s$normal_quantiles,1024^2),stringsAsFactors=FALSE)
  normal_rows <- gsc_normal_rows(normal_rows,normal,s$prepared_design_sha256)
  if(mode=="extract") {
    source("scripts/glofas_same_family_plot_inputs.R")
    return(gsc_extract_authorized(s,collection,normal,check_source,expiry,args[4L]))
  }
  derivation <- jsonlite::read_json(gsc_pin(s$raw_member_derivation,1024^2),simplifyVector=FALSE)
  q(identical(derivation$schema_version,"glofas_same_family_raw_members_v1")&&
    identical(derivation$source_design_sha256,s$prepared_design_sha256)&&
    identical(derivation$artifact_sha256,s$raw_members$sha256)&&derivation$members==51L&&
    derivation$horizons==28L&&identical(derivation$transform,"log1p")&&
    identical(derivation$future_truth_read,FALSE),"authenticated truth-free raw-member derivation required")
  raw <- read.csv(gsc_pin(s$raw_members,2*1024^2),stringsAsFactors=FALSE)
  rows <- gsc_assemble(quantiles,normal_rows,raw) # no truth has been opened
  out <- s$output_root
  q(is.character(out)&&length(out)==1L&&startsWith(out,paste0(root,"/local_trackers/"))&&
    !file.exists(out)&&dir.exists(dirname(out))&&identical(normalizePath(dirname(out)),dirname(out))&&
    !grepl("(^|/)\\.\\.(/|$)",out)&&system2("git",c("check-ignore","--quiet","--",shQuote(out)))==0L,
    "fresh ignored output root required")
  q(dir.create(out),"output creation failed")
  write_json <- function(v,name)jsonlite::write_json(v,file.path(out,name),pretty=TRUE,auto_unbox=TRUE,digits=17,null="null")
  write_json(list(status="COMPATIBILITY_AND_COMPLETE_GRID_VERIFIED_NO_TRUTH_READ",source_commit=s$source_commit),"progress.json")
  tryCatch({
    write.csv(rows,file.path(out,"quantile_paths.csv"),row.names=FALSE)
    write.csv(gsc_crossings(rows),file.path(out,"raw_crossings.csv"),row.names=FALSE)
    write_json(collection,"accepted_producers.json")
    bindings <- s[c("normal_manifest","normal_receipt","normal_quantiles","raw_member_derivation","raw_members")]
    for(b in bindings)gsc_pin(b,2*1024^2)
    check_source()
    write_json(gsc_make_forecast_seal(out,bindings,s$prepared_design_sha256),"FORECAST_SEAL.json")
    forecast_seal_sha256 <- unname(tools::sha256sum(file.path(out,"FORECAST_SEAL.json")))
    gsc_verify_forecast_seal(out,forecast_seal_sha256)
    if(mode=="score") {
      q(identical(s$truth_role,"post_fit_scoring_only")&&isFALSE(s$model_selection_or_retuning),"truth is scoring-only")
      if(identical(gst_truth_interface(s),"authenticated_truth_bridge_v2")) {
        gst_validate_score_truth(s,gsc_verify_forecast_seal(out,forecast_seal_sha256))
      }
      truth <- read.csv(gsc_pin(s$truth,1024^2),stringsAsFactors=FALSE)
      scored <- gsc_score(rows,truth)
      if(identical(gst_truth_interface(s),"authenticated_truth_bridge_v2")) {
        q(file.copy(s$truth$path,file.path(out,"scoring_truth.csv"),overwrite=FALSE),"exact derived scoring truth retention failed")
      } else write.csv(truth,file.path(out,"scoring_truth.csv"),row.names=FALSE)
      for(pair in list(c("summary","family_scores.csv"),c("by_date","scores_by_date.csv"),
        c("calibration","quantile_calibration.csv")))write.csv(scored[[pair[1L]]],file.path(out,pair[2L]),row.names=FALSE)
      write_json(scored$score_contract,"score_contract.json")
      if(identical(gst_truth_interface(s),"authenticated_truth_bridge_v2")) {
        q(file.copy(s$truth_derivation$path,file.path(out,"TRUTH_DERIVATION.json"),overwrite=FALSE)&&
          file.copy(s$truth_adapter_purpose$path,file.path(out,"TRUTH_PURPOSE.json"),overwrite=FALSE),
          "truth provenance retention failed")
      }
    }
    for(b in s$source_files)gsc_pin(b,1024^2)
    for(b in s[c("collection_contract","normal_manifest","normal_receipt","normal_quantiles","raw_member_derivation","raw_members")])gsc_pin(b,2*1024^2)
    for(z in collection$producers)for(b in z$artifacts) {
      if(b$relative_path %in% c("forecast_quantiles.csv","target_receipt.json","progress.csv")) {
        b$relative_path <- NULL;gsc_pin(b,16*1024^2)
      }
    }
    if(mode=="score") {
      gsc_pin(s$truth,1024^2)
      if(identical(gst_truth_interface(s),"authenticated_truth_bridge_v2"))
        gst_validate_score_truth(s,gsc_verify_forecast_seal(out,forecast_seal_sha256))
    }
    gsc_verify_forecast_seal(out,forecast_seal_sha256)
    check_source();q(expiry>Sys.time(),"purpose expired")
    cpu <- sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])
    q(cpu<=s$limits$cpu_seconds,"whole-purpose CPU charge exceeded")
    write_json(list(schema_version="glofas_same_family_closeout_receipt_v1",
      status=if(mode=="score")"READY_FOR_SCIENTIFIC_REVIEW_NOT_AUTOMATIC_PUBLICATION" else
        "ASSEMBLED_COMPLETE_GRID_NO_TRUTH_READ",mode=mode,source_commit=s$source_commit,source_tree=s$source_tree,
      contract_sha256=args[4L],expected_identity=s$expected_identity,forecast_rows=1372L,families=7L,
      forecast_seal_sha256=forecast_seal_sha256,
      truth_interface_version=if(mode=="score")gst_truth_interface(s)else NULL,
      future_truth_read=mode=="score",model_selection_or_retuning=FALSE,new_fits=0L,
      artifact_scope="new_ignored_closeout_only",article_publication_authorized=FALSE,
      CPU_seconds=cpu,input_bindings=s[c("normal_manifest","normal_receipt","normal_quantiles","raw_member_derivation","raw_members",
        if(mode=="score")"truth",if(mode=="score"&&identical(gst_truth_interface(s),"authenticated_truth_bridge_v2"))
          c("truth_rds","truth_provenance_manifest","assembly_root","assembly_manifest","assembly_forecast_seal",
            "truth_derivation","truth_adapter_purpose"))]),"DECISION.json")
    write_json(list(status="CLOSEOUT_TERMINAL_NOT_PUBLICATION",mode=mode,future_truth_read=mode=="score"),"progress.json")
    files <- list.files(out,full.names=TRUE,all.files=TRUE,no..=TRUE)
    q(all(!file.info(files)$isdir)&&sum(file.info(files)$size)+65536<s$limits$output_bytes,"complete output budget")
    write.csv(data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,
      sha256=unname(tools::sha256sum(files))),file.path(out,"artifact_manifest.csv"),row.names=FALSE)
    cat("GLOFAS_SAME_FAMILY_CLOSEOUT_COMPLETE_NOT_PUBLICATION\n")
  },error=function(e) {write_json(list(status="CLOSEOUT_FAILED_NOT_PUBLICATION",error=conditionMessage(e)),"failure.json");stop(e)})
  invisible(rows)
}
if(sys.nframe()==0L)gsc_closeout_main()
