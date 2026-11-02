#!/usr/bin/env Rscript
# One finite27-fit metadata enrollment; no fitter/forecast/scorer is executed.
ind_npc_enroll <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript scripts/enroll_ind_native_parameter_catalog.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  stopifnot(length(args)==5L,args[[1L]]=="--contract",args[[3L]]=="--sha256",args[[5L]]=="--execute")
  source("scripts/ind_native_parameter_catalog.R");q <- ind_npc_require
  pin <- function(x) {
    q(is.list(x) && is.character(x$path) && length(x$path)==1L && startsWith(x$path,"/") &&
      !grepl("(^|/)\\.\\.(/|$)",x$path) && file.exists(x$path) && !isTRUE(file.info(x$path)$isdir) &&
      identical(unname(Sys.readlink(x$path)),"") && identical(normalizePath(x$path,mustWork=TRUE),x$path) &&
      is.numeric(x$size_bytes) && length(x$size_bytes)==1L && is.finite(x$size_bytes) &&
      x$size_bytes>0 && file.info(x$path)$size==x$size_bytes && is.character(x$sha256) &&
      length(x$sha256)==1L && grepl("^[a-f0-9]{64}$",x$sha256) &&
      identical(unname(tools::sha256sum(x$path)),x$sha256),"exact catalog input/source binding")
    x$path
  }
  path <- normalizePath(args[[2L]],mustWork=TRUE)
  q(file.info(path)$size<=2*1024^2 && identical(unname(tools::sha256sum(path)),args[[4L]]),
    "bounded external catalog purpose contract")
  spec <- jsonlite::read_json(path,simplifyVector=FALSE)
  q(identical(spec$schema_version,"ind_native_parameter_catalog_enrollment_v1") &&
    identical(spec$allow_enrollment,TRUE) && identical(spec$allow_refit,FALSE) &&
    identical(spec$allow_forecast,FALSE) && identical(spec$allow_scoring,FALSE) &&
    identical(spec$allow_production,FALSE) && spec$chunk_id %in% c("al_c72","exal_7ace") &&
    is.list(spec$cases) && length(spec$cases)==27L && identical(spec$native_parameter_count,20000L),
    "fixed27-fit native catalog enrollment scope")
  cpu <- if(identical(spec$chunk_id,"al_c72"))26L else 29L
  q(identical(spec$logical_cpu,cpu) && is.list(spec$limits) &&
    identical(spec$limits$cpu_seconds,1200L) && identical(spec$limits$wall_term_seconds,1799L) &&
    identical(spec$limits$wall_kill_after_seconds,1L) && spec$limits$address_space_bytes==8*1024^3 &&
    spec$limits$output_bytes==64*1024^2,"finite native catalog chunk limits")
  root <- normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(path,paste0(root,"/")),"catalog contract must be outside source")
  git <- function(a) {
    z <- system2("git",c("--no-replace-objects",a),stdout=TRUE)
    q(is.null(attr(z,"status")),"catalog Git identity check failed");unname(z)
  }
  q(identical(git(c("rev-parse","HEAD")),spec$source_commit) &&
    identical(git(c("rev-parse","HEAD^{tree}")),spec$source_tree) &&
    length(git(c("status","--porcelain","--untracked-files=normal")))==0L,"clean frozen catalog source/tree")
  expiry <- as.POSIXct(spec$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry) && expiry>Sys.time()+1800 && as.character(getRversion())=="4.6.0" &&
    unname(Sys.info()[["nodename"]]) %in% c("muscat","muscat.be.ucsc.edu") &&
    identical(Sys.getenv("LD_PRELOAD"),"") &&
    all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1"),
    "source-native enrollment host/runtime/lifetime")
  q(identical(normalizePath(unname(extSoftVersion()[["BLAS"]]),mustWork=TRUE),
    normalizePath(file.path(R.home("lib"),"libRblas.so"),mustWork=TRUE)),"bundled R BLAS required")
  proc <- readLines("/proc/self/status",warn=FALSE)
  affinity <- trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",proc,value=TRUE)))
  q(identical(affinity,as.character(cpu)),"catalog exact administrative CPU boundary")
  bounds <- readLines("/proc/self/limits",warn=FALSE)
  bound <- function(prefix,ceiling) {
    a <- grep(paste0("^",prefix),bounds,value=TRUE)
    if(length(a)!=1L)return(FALSE)
    v <- suppressWarnings(as.numeric(strsplit(trimws(sub(paste0("^",prefix),"",a)),"[[:space:]]+")[[1L]][1:2]))
    all(is.finite(v) & v>0 & v<=ceiling)
  }
  q(bound("Max cpu time",1200) && bound("Max address space",8*1024^3) &&
    bound("Max file size",64*1024^2),"finite catalog process limits")
  # CPU/AS/FSIZE do not establish a wall bound. Authenticate the closest
  # actual timeout ancestor, including its forced-kill delay, independently.
  timeout_proof <- NULL;ancestor <- Sys.getpid()
  for(step in seq_len(16L)) {
    status_path <- sprintf("/proc/%d/status",ancestor)
    if(!file.exists(status_path))break
    st <- readLines(status_path,warn=FALSE)
    cmd <- sprintf("/proc/%d/cmdline",ancestor)
    if(file.exists(cmd)) {
      b <- readBin(cmd,"raw",n=65536L)
      b[b==as.raw(0)] <- as.raw(10)
      argv <- strsplit(rawToChar(b),"\n",fixed=TRUE)[[1L]]
      if(length(argv) && identical(basename(argv[[1L]]),"timeout")) {
        q(ind_npc_timeout_argv_ok(argv),"exact1799-second TERM and1-second KILL ancestor required")
        timeout_proof <- list(pid=ancestor,validated_argv_prefix=argv[1:4],
          term_seconds=1799L,kill_after_seconds=1L);break
      }
    }
    pp <- grep("^PPid:",st,value=TRUE)
    if(length(pp)!=1L)break
    ancestor <- suppressWarnings(as.integer(trimws(sub("^PPid:","",pp))))
    if(!is.finite(ancestor) || ancestor<=1L)break
  }
  q(!is.null(timeout_proof),"external exact TERM/KILL wall supervisor missing")
  q(!"exdqlm" %in% loadedNamespaces(),"installed exdqlm namespace cannot substitute native retained input")
  sources <- vapply(spec$source_files,pin,character(1L))
  q(all(file.path(root,c("scripts/ind_native_parameter_catalog.R","scripts/enroll_ind_native_parameter_catalog.R")) %in% sources) &&
    all(startsWith(sources,paste0(root,"/"))) && !anyDuplicated(sources),"catalog module and entry pins required")
  output <- spec$output_root
  q(is.character(output) && length(output)==1L && startsWith(output,paste0(root,"/local_trackers/")) &&
    !file.exists(output) && !grepl("(^|/)\\.\\.(/|$)",output) && dir.exists(dirname(output)) &&
    identical(normalizePath(dirname(output),mustWork=TRUE),dirname(output)) &&
    identical(system2("git",c("check-ignore","--quiet","--",shQuote(output))),0L),
    "fresh real ignored catalog output namespace")
  q(dir.create(output),"catalog output creation failed")
  write_json <- function(x,name) {
    target <- file.path(output,name);tmp <- paste0(target,".tmp")
    jsonlite::write_json(x,tmp,pretty=TRUE,auto_unbox=TRUE,digits=17,null="null")
    q(file.rename(tmp,target),"atomic catalog receipt write")
  }
  progress <- function(phase,...)write_json(list(schema_version="ind_native_catalog_progress_v1",
    phase=phase,timestamp_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
    source_commit=spec$source_commit,purpose_contract_sha256=args[[4L]],chunk_id=spec$chunk_id,
    production_authorized=FALSE,details=list(...)),"progress.json")
  manifest <- function() {
    f <- list.files(output,full.names=TRUE);f <- f[basename(f)!="artifact_manifest.csv"]
    a <- data.frame(relative_path=basename(f),size_bytes=unname(file.info(f)$size),sha256=unname(tools::sha256sum(f)))
    q(sum(a$size_bytes)<64*1024^2-65536,"catalog total packet budget")
    write.csv(a,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
    q(sum(file.info(list.files(output,full.names=TRUE))$size)<=64*1024^2,"catalog manifest-inclusive budget")
  }
  hadseed <- exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE)
  oldseed <- if(hadseed)get(".Random.seed",envir=.GlobalEnv)else NULL
  unchanged_rng <- function()identical(exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE),hadseed) &&
    (!hadseed || identical(get(".Random.seed",envir=.GlobalEnv),oldseed))
  progress("CATALOG_ENROLLMENT_ADMITTED")
  tryCatch({
    locator <- read.csv(pin(spec$locator),colClasses="character")
    q(nrow(locator)==132L && !anyDuplicated(locator$task_id) &&
      all(c("task_id","contract_path","contract_sha256","chain_id") %in% names(locator)),"authenticated132-entry locator required")
    isal <- identical(spec$chunk_id,"al_c72")
    source <- if(isal)"c72e19f345da88fc1a8175ed30bdde328eab88be"else"7ace6618601b7dd8d8c5fd3bd676000ba40f11e8"
    version <- if(isal)"1.0.0"else"1.1.1";variant <- if(isal)"dqlm"else"exdqlm"
    records <- list();casekeys <- character();fitbytes <- 0
    source_roles <- c("model_builder_source","polytrend_source","seas_source","generics_source",
      "mcmc_source","row_runner_source","native_cpp","native_dll")
    # Verify every small identity and source before opening any large RDS.
    seenpins <- list()
    for(entry in spec$cases) {
      q(is.character(entry$task_id) && length(entry$task_id)==1L && grepl("^[A-Za-z0-9_]+$",entry$task_id),
        "safe exact native task identifier required")
      row <- locator[locator$task_id==entry$task_id,,drop=FALSE]
      q(nrow(row)==1L && identical(row$contract_path,entry$contract$path) &&
        identical(row$contract_sha256,entry$contract$sha256),"catalog case not bound by locator")
      c <- jsonlite::read_json(pin(entry$contract),simplifyVector=FALSE)
      cap <- jsonlite::read_json(pin(entry$capsule),simplifyVector=FALSE)
      environment <- jsonlite::read_json(pin(entry$environment),simplifyVector=FALSE)
      worker_log <- readLines(pin(entry$worker_log),warn=FALSE)
      retained <- read.csv(pin(entry$retention_manifest),colClasses="character")
      q(identical(c$engine,"dqlm") && identical(c$source_commit,source) &&
        identical(c$package_version,version) && identical(c$task$model_variant,variant) &&
        identical(c$task$task_id,entry$task_id) && c$task$chain_id==as.integer(row$chain_id) &&
        identical(cap$task_id,entry$task_id) && identical(cap$source_commit,source) &&
        identical(cap$package_version,version) && identical(cap$fitted_payload_path,entry$fit$path) &&
        identical(cap$fitted_payload_sha256,entry$fit$sha256),"native case/capsule/source identity mismatch")
      q(identical(environment$source_commit,source) && identical(environment$package_version,version) &&
        any(grepl("C++ (mode=fast)",worker_log,fixed=TRUE)),"authentic native worker backend/runtime identity missing")
      q(c$config$budget$mcmc$n_burn==5000 && c$config$budget$mcmc$n_mcmc==20000 &&
        c$config$budget$mcmc$thin==1,"strict20k native posterior retention required")
      for(binding in list(entry$fit,entry$capsule,entry$environment)) {
        rr <- retained[retained$path==binding$path,,drop=FALSE]
        q(nrow(rr)==1L && identical(rr$sha256,binding$sha256) &&
          as.numeric(rr$bytes)==binding$size_bytes,"native retention manifest link mismatch")
      }
      q(identical(c$config$series_wide_path,entry$raw_series$path) &&
        identical(c$config$series_wide_sha256,entry$raw_series$sha256),"raw training-series source pin mismatch")
      pin(entry$raw_series)
      for(role in source_roles) {
        binding <- entry[[role]];q(is.list(binding),paste("missing authenticated source role",role))
        rows <- c(c$code_manifest,c$package_manifest)
        match <- Filter(function(z)identical(z$path,binding$path) && identical(z$sha256,binding$sha256) &&
          z$bytes==binding$size_bytes,rows)
        q(length(match)==1L,paste("source role not bound by original contract",role))
        if(is.null(seenpins[[binding$path]])){pin(binding);seenpins[[binding$path]] <- binding}
        else q(identical(seenpins[[binding$path]],binding),"conflicting duplicated source pin")
      }
      q(entry$native_cpp$sha256=="f6ccf41466ece60a3a63737bb434309e8bea59f5b254a086793e5cca0aba6065",
        "source-native C++ covariance policy differs")
      key <- paste(c$task$family,c$task$p,c$task$chain_id,sep="|")
      q(!(key %in% casekeys),"duplicate native family/quantile/chain")
      casekeys <- c(casekeys,key);fitbytes <- fitbytes+entry$fit$size_bytes
      records[[entry$task_id]] <- list(entry=entry,contract=c,capsule=cap)
    }
    expected <- expand.grid(family=c("normal","laplace","gausmix"),p=c(.05,.25,.5),chain=1:3,
      stringsAsFactors=FALSE)
    q(setequal(casekeys,paste(expected$family,expected$p,expected$chain,sep="|")) &&
      fitbytes<=20*1024^3,"complete27-fit cell/chain surface and finite read scope required")
    summaries <- list();i <- 0L
    for(rec in records) {
      i <- i+1L;entry <- rec$entry;c <- rec$contract;cap <- rec$capsule
      progress("CATALOG_FIT_READING",task_id=entry$task_id,case_number=i,total_cases=27L)
      started <- proc.time();pin(entry$fit)
      protected <- readRDS(entry$fit$path)
      q(!"exdqlm" %in% loadedNamespaces(),"reading retained data loaded a forbidden package namespace")
      series <- read.csv(entry$raw_series$path,stringsAsFactors=FALSE)
      ref <- ind_npc_reference(c$config,series)
      case <- list(task_id=entry$task_id,chain_id=as.integer(c$task$chain_id),family=c$task$family,
        p=c$task$p,model_variant=variant,source_commit=source,package_version=version,
        old_realization_reproduced=cap$old_realization_reproduced,
        input_hashes=lapply(entry[setdiff(names(entry),"task_id")],function(z)z$sha256))
      block <- ind_npc_extract(protected,case,ref,20000L)
      filename <- paste0(entry$task_id,".native_parameters.rds")
      target <- file.path(output,filename);saveRDS(block,target)
      check <- readRDS(target)
      q(identical(check,block),"lossless compact native block roundtrip failed")
      rm(check,protected,series,ref);gc(FALSE)
      pin(entry$fit) # independent whole-file post-read hash, no source copy.
      timing <- proc.time()-started
      summaries[[i]] <- data.frame(task_id=entry$task_id,model_variant=variant,
        family=c$task$family,p=c$task$p,chain_id=c$task$chain_id,native_columns=20000L,
        native_iteration_start=5001L,native_iteration_end=25000L,within_model_weight=1/60000,
        source_version=version,source_commit=source,fit_sha256=entry$fit$sha256,
        source_payload_bytes=entry$fit$size_bytes,block_file=filename,
        block_sha256=unname(tools::sha256sum(target)),block_bytes=file.info(target)$size,
        CPU_seconds=sum(timing[1:2]),elapsed_seconds=unname(timing[["elapsed"]]),
        old_realization_reproduced=cap$old_realization_reproduced,
        old_flag_meaning="metric_draw_reproduction_not_series_identity",production_authorized=FALSE)
      rm(block);gc(FALSE)
      write.csv(do.call(rbind,summaries),file.path(output,"native_catalog_summary.csv"),row.names=FALSE)
      progress("CATALOG_FIT_COMPLETE",task_id=entry$task_id,completed_cases=i,total_cases=27L)
      manifest()
    }
    for(binding in spec$source_files)pin(binding)
    for(binding in seenpins)pin(binding)
    pin(spec$locator)
    for(entry in spec$cases)for(role in c("contract","capsule","retention_manifest","raw_series","environment","worker_log"))pin(entry[[role]])
    q(unchanged_rng() && !"exdqlm" %in% loadedNamespaces() && expiry>Sys.time(),
      "catalog source/runtime/RNG/lifetime changed")
    q(identical(git(c("rev-parse","HEAD")),spec$source_commit) &&
      identical(git(c("rev-parse","HEAD^{tree}")),spec$source_tree) &&
      length(git(c("status","--porcelain","--untracked-files=normal")))==0L,
      "catalog Git source/tree/clean status changed during enrollment")
    receipt <- list(schema_version="ind_native_parameter_catalog_enrollment_receipt_v1",
      status="NATIVE_PARAMETER_CATALOG_CHUNK_ENROLLED_NOT_FORECAST_LAUNCH",chunk_id=spec$chunk_id,
      source_commit=spec$source_commit,source_tree=spec$source_tree,purpose_contract_sha256=args[[4L]],
      locator=spec$locator,cases=27L,native_parameters_per_case=20000L,static_parameter_rows=540000L,
      complete_model_cells=9L,chains_per_model=3L,model_parameter_rows=60000L,
      weight_policy="all_retained_native_postburn_columns_equal_1_over_60000_per_model_cell",
      new_fits=0L,forecasts=0L,scoring_cases=0L,large_source_payloads_copied=0L,
      source_payload_bytes_read_once=fitbytes,source_payloads_hashed_before_and_after=TRUE,
      original_parameter_values_and_pairing_preserved=TRUE,legacy_metric_draw_mapping_inferred=FALSE,
      posterior_target_exactness_certified=FALSE,numerical_filter_accuracy_certified=FALSE,
      production_authorized=FALSE,original_evidence_deleted=FALSE,
      original_fit_source_commit=source,source_package_version=version,logical_cpu=cpu,
      R=as.character(getRversion()),bundled_BLAS=unname(extSoftVersion()[["BLAS"]]),
      finite_external_limits=spec$limits,wall_supervisor=timeout_proof,scientific_RNG_unchanged=TRUE)
    write_json(receipt,"enrollment.json")
    progress("NATIVE_PARAMETER_CATALOG_CHUNK_ENROLLED_NOT_FORECAST_LAUNCH",completed_cases=27L)
    manifest();cat("NATIVE_PARAMETER_CATALOG_CHUNK_ENROLLED_NOT_FORECAST_LAUNCH cases=27 native_rows=540000 production=FALSE\n")
    invisible(receipt)
  },error=function(e) {
    try(write_json(list(status="NATIVE_CATALOG_ENROLLMENT_FAILED_NOT_PRODUCTION",error=conditionMessage(e),
      source_commit=spec$source_commit,purpose_contract_sha256=args[[4L]],production_authorized=FALSE),"failure.json"),silent=TRUE)
    try(progress("NATIVE_CATALOG_ENROLLMENT_FAILED_NOT_PRODUCTION",error=conditionMessage(e)),silent=TRUE)
    try(manifest(),silent=TRUE);stop(e)
  })
}
if(sys.nframe()==0L)ind_npc_enroll()
