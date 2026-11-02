#!/usr/bin/env Rscript
# Prospective precision extension of the frozen one-draw/origin MQ unit.
# New helpers only; old scientific/native/batch sources remain byte-identical.
source("scripts/qualify_mq_batch_acceleration.R")

mq_pe_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("MQ precision extension: ",why),call.=FALSE)
  invisible(TRUE)
}

mq_pe_baseline_identity <- function(spec) {
  req <- mq_pe_require
  expected <- c(
    baseline_contract="c1490494d4307cf29ea74f3c002e765ecb790486fe4fad24c0bf04b65a9df4e6",
    baseline_receipt="bffaeb83b8f341603542965cecb877a865f5b152d0b16ac4e872dc11c6b6a1cf",
    baseline_manifest="3cca4efe27ede0759d643b560259336c16492c3dce5b87188927f043be9053da")
  for(key in names(expected)) req(is.list(spec[[key]]) &&
    identical(spec[[key]]$sha256,unname(expected[key])),"fixed v1 baseline contract/receipt/manifest identities required")
  invisible(TRUE)
}

mq_pe_timeout_argv <- function(argv) {
  mq_pe_require(is.character(argv)&&length(argv)>=5L&&!anyNA(argv)&&
    identical(basename(argv[1L]),"timeout")&&
    identical(argv[2:4],c("--signal=TERM","--kill-after=1s","2399s"))&&
    nzchar(trimws(argv[5L]))&&!startsWith(argv[5L],"-"),
    "exact timeout TERM2399/KILL1 argv required")
  invisible(TRUE)
}

mq_pe_exact_timeout_ancestor <- function() {
  pid <- Sys.getpid()
  for(i in seq_len(8L)) {
    status <- tryCatch(readLines(sprintf("/proc/%d/status",pid),warn=FALSE),error=function(e)character())
    ppid <- suppressWarnings(as.integer(trimws(sub("^PPid:","",grep("^PPid:",status,value=TRUE)))))
    if(length(ppid)!=1L||is.na(ppid)||ppid<=1L)break
    raw <- tryCatch(readBin(sprintf("/proc/%d/cmdline",ppid),"raw",n=16384L),error=function(e)raw())
    if(length(raw)) {
      stop_at <- which(raw==as.raw(0))
      if(length(stop_at)&&tail(stop_at,1L)==length(raw)) {
        starts <- c(1L,head(stop_at,-1L)+1L)
        argv <- vapply(seq_along(stop_at),function(j) {
          if(starts[j]>=stop_at[j])"" else rawToChar(raw[seq.int(starts[j],stop_at[j]-1L)])
        },character(1L))
        if(length(argv)&&basename(argv[1L])=="timeout") {
          mq_pe_timeout_argv(argv)
          exe <- Sys.readlink(sprintf("/proc/%d/exe",ppid))
          mq_pe_require(is.character(exe)&&length(exe)==1L&&
            identical(normalizePath(exe,mustWork=TRUE),normalizePath("/usr/bin/timeout",mustWork=TRUE)),
            "timeout ancestor must be the native /usr/bin/timeout executable")
          return(list(pid=ppid,argv_prefix=argv[1:5],executable=normalizePath(exe,mustWork=TRUE),
            wall_TERM_seconds=2399L,KILL_after_seconds=1L))
        }
      }
    }
    pid <- ppid
  }
  mq_pe_require(FALSE,"exact bounded timeout ancestor missing")
}

mq_pe_parity_ids <- function(spec,candidates_frozen,split_passed) {
  mq_pe_require(is.logical(candidates_frozen)&&length(candidates_frozen)==1L&&!is.na(candidates_frozen)&&
    is.logical(split_passed)&&length(split_passed)==1L&&!is.na(split_passed)&&
    (candidates_frozen||!split_passed),"valid prospective parity phase required")
  ids <- as.integer(unlist(spec$parity_path_ids,use.names=FALSE))
  if(!candidates_frozen)return(ids[ids<=65536L])
  if(!split_passed)return(integer())
  ids[ids>65536L]
}

mq_pe_scope <- function(spec) {
  req <- mq_pe_require
  exact <- function(x,z) is.numeric(x)&&length(x)==1L&&is.finite(x)&&x==z
  vec <- function(x,z) {
    v <- unlist(x,use.names=FALSE)
    is.numeric(v)&&length(v)==length(z)&&all(is.finite(v))&&all(v==z)
  }
  req(is.list(spec)&&identical(spec$schema_version,"mq_precision_extension_qualification_v1")&&
    identical(spec$allow_qualification,TRUE)&&identical(spec$allow_refit,FALSE)&&
    identical(spec$allow_production,FALSE)&&identical(spec$allow_scoring,FALSE)&&
    identical(spec$allow_article,FALSE),"qualification-only scope required")
  req(exact(spec$training_paths,65536)&&exact(spec$validation_paths,262144)&&exact(spec$batch_size,128)&&
    vec(spec$training_path_range,c(1,65536))&&vec(spec$validation_path_range,c(65537,327680))&&
    vec(spec$validation_look_sizes,c(65536,131072,262144))&&exact(spec$total_alpha,.05)&&
    vec(spec$alpha_per_look,rep(.05/3,3))&&
    exact(spec$inversion_tolerance,1e-8)&&exact(spec$parity_absolute_tolerance,1e-10)&&
    exact(spec$parity_relative_tolerance,1e-10)&&identical(spec$rng_backend,"r46_first_step"),
    "fixed prospective paths, looks, alpha spending, RNG and numerical tolerances required")
  req(vec(spec$parity_path_ids,c(1,2,63,64,127,128,4095,4096,4097,8192,16384,32768,
    65535,65536,65537,327680)),"fixed prospective scalar/batch parity identities required")
  req(identical(spec$stop_before_validation_on_split_failure,TRUE)&&
    identical(spec$parity_ordering,
      "training_ids_before_training_validation_ids_after_candidate_freeze_and_split_pass")&&
    identical(spec$retention_policy,
      "compressed_training_arrays_and_streaming_Welford_block_receipts_no_validation_raw_matrix"),
    "prospective split-stop and explicit streaming retention policy required")
  q2_geometry(spec$original_unit)
  a <- spec$original_unit$integration_accuracy
  req(exact(a$alpha_per_shard,.05)&&exact(a$max_split_absolute,.005)&&exact(a$max_split_relative,.005)&&
    exact(a$max_quantile_abs_error,.01)&&exact(a$max_quantile_rel_error,.01),
    "original numerical thresholds must remain unchanged")
  lim <- spec$limits
  req(is.list(lim)&&exact(lim$cpu_seconds,1800)&&exact(lim$wall_term_seconds,2399)&&
    exact(lim$wall_kill_after_seconds,1)&&exact(lim$address_space_bytes,16*1024^3)&&
    exact(lim$output_bytes,256*1024^2),"fixed finite extension budgets required")
  mq_pe_baseline_identity(spec)
  invisible(TRUE)
}

mq_pe_baseline_fields <- function(spec, baseline, receipt) {
  req <- mq_pe_require
  req(identical(baseline$source_commit,"a099aba928e6d1fb01931a4b12466125bbb2bc64")&&
    identical(baseline$source_tree,"48b8baa236859f9f32969593101c75ff45bfa88c"),
    "baseline must authenticate the exact frozen v1 source and tree")
  mq_baq_scope(baseline)
  req(identical(receipt$schema_version,"mq_batch_acceleration_qualification_receipt_v1")&&
    identical(receipt$source_commit,baseline$source_commit)&&identical(receipt$source_tree,baseline$source_tree)&&
    identical(receipt$purpose_contract_sha256,spec$baseline_contract$sha256)&&
    identical(receipt$status,"QUALIFICATION_COMPLETE_NOT_PRODUCTION")&&
    identical(receipt$numerical_status,"REVIEW_NUMERICAL_ACCURACY_NOT_QUALIFIED")&&
    identical(receipt$original_legacy_numerical_status,"REVIEW_INNER_INTEGRATION_RESOLUTION")&&
    identical(receipt$old_failure_receipts_preserved,TRUE)&&identical(receipt$thresholds_loosened,FALSE)&&
    identical(receipt$production_authorized,FALSE)&&identical(receipt$article_promotion_authorized,FALSE),
    "baseline v1 completion and retained numerical REVIEW must remain explicit")
  req(is.list(receipt$parity)&&length(receipt$parity)==3L&&
    identical(unname(vapply(receipt$parity,`[[`,character(1L),"field")),
      c("recursive_responses","ordered_conditional_kernels","integrated_training_quantiles"))&&
    all(vapply(receipt$parity,function(x)isTRUE(x$pass)&&is.numeric(x$values)&&length(x$values)==1L&&
      is.numeric(x$maximum_absolute_difference)&&length(x$maximum_absolute_difference)==1L&&
      identical(as.numeric(x$maximum_absolute_difference),0),logical(1L)))&&
    identical(as.numeric(vapply(receipt$parity,`[[`,numeric(1L),"values")),c(122880,860160,210)),
    "baseline full native/batch zero-difference parity evidence required")
  for(key in c("original_unit","original_unit_contract","source_manifest","native_rng_source","rng_backend"))
    req(identical(spec[[key]],baseline[[key]])&&identical(receipt[[key]],baseline[[key]]),
      paste("original unit/target/RNG/input identity changed:",key))
  req(identical(receipt$observational_future_truth_used,FALSE)&&
    receipt$parameter_refits==0L&&receipt$score_evaluations==0L,
    "baseline must contain no refits, future truth scoring or article promotion")
  invisible(TRUE)
}

# Metadata/hash verification only. This must finish before any readRDS call.
mq_pe_verify_baseline <- function(spec,root,pin) {
  mq_pe_baseline_identity(spec)
  cp <- pin(spec$baseline_contract); rp <- pin(spec$baseline_receipt); mp <- pin(spec$baseline_manifest)
  baseline <- jsonlite::read_json(cp,simplifyVector=FALSE)
  receipt <- jsonlite::read_json(rp,simplifyVector=FALSE)
  mq_pe_baseline_fields(spec,baseline,receipt)
  old_root <- sub("/docs/reproducibility/integrated_forecast_transition_sources_20261031.csv$","",
    baseline$source_manifest$path)
  mq_pe_require(startsWith(old_root,"/")&&!identical(old_root,baseline$source_manifest$path)&&
    is.list(baseline$source_files)&&length(baseline$source_files)>=10L,
    "baseline transitive-source inventory is malformed")
  for(x in baseline$source_files) {
    mq_pe_require(startsWith(x$path,paste0(old_root,"/")),"baseline source escapes its original checkout")
    relative <- substring(x$path,nchar(old_root)+2L)
    current <- x;current$path <- file.path(root,relative)
    pin(current)
  }
  base <- spec$baseline_output_root
  mq_pe_require(is.character(base)&&length(base)==1L&&identical(base,baseline$output_root)&&
    identical(dirname(rp),base)&&identical(mp,file.path(base,"artifact_manifest.csv")),
    "baseline retained output namespace changed")
  q2_regular(base)
  m <- read.csv(mp,stringsAsFactors=FALSE,colClasses="character")
  required <- c("batch_training_result.rds","frozen_training_candidates.rds",
    "independent_cdf_certificate.rds","independent_cdf_endpoint_evidence.csv",
    "independent_validation_cdf_matrix.rds","progress.json","qualification.json",
    "scalar_training_result.rds","structural_first_horizon_evidence.rds")
  mq_pe_require(identical(names(m),c("relative_path","size_bytes","sha256"))&&nrow(m)==9L&&
    !anyDuplicated(m$relative_path)&&setequal(m$relative_path,required)&&
    setequal(list.files(base,all.files=TRUE,no..=TRUE),c(required,"artifact_manifest.csv")),
    "exact nine-file baseline artifact surface required")
  for(i in seq_len(nrow(m))) {
    mq_pe_require(!grepl("/|\\\\",m$relative_path[i]),"baseline artifact is not a direct child")
    pin(list(path=file.path(base,m$relative_path[i]),size_bytes=as.numeric(m$size_bytes[i]),sha256=m$sha256[i]))
  }
  mq_pe_require(identical(m$sha256[m$relative_path=="qualification.json"],spec$baseline_receipt$sha256),
    "baseline manifest does not bind its exact receipt")
  list(contract=baseline,receipt=receipt,manifest=m,files_verified=nrow(m),
    bytes_verified=sum(as.numeric(m$size_bytes)),historical_outputs_copied=FALSE)
}

mq_pe_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript scripts/qualify_mq_precision_extension.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  req <- mq_pe_require
  req(length(args)==5L&&args[1L]=="--contract"&&args[3L]=="--sha256"&&args[5L]=="--execute",
    "exact contract/hash/execute arguments required")
  cp <- normalizePath(args[2L],mustWork=TRUE);q2_regular(cp)
  req(file.info(cp)$size<=1024^2&&identical(unname(tools::sha256sum(cp)),args[4L]),
    "bounded external purpose contract SHA mismatch")
  spec <- jsonlite::read_json(cp,simplifyVector=FALSE);mq_pe_scope(spec)
  root <- normalizePath(getwd(),mustWork=TRUE)
  req(!startsWith(cp,paste0(root,"/")),"purpose must be external to the source checkout")
  git <- function(a) {
    z <- system2("git",c("--no-replace-objects",a),stdout=TRUE)
    req(is.null(attr(z,"status")),"Git source identity check failed");unname(z)
  }
  req(identical(git(c("rev-parse","HEAD")),spec$source_commit)&&
    identical(git(c("rev-parse","HEAD^{tree}")),spec$source_tree)&&
    length(git(c("status","--porcelain","--untracked-files=normal")))==0L,
    "clean frozen source commit/tree required")
  expiry <- as.POSIXct(spec$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  req(!is.na(expiry)&&expiry>Sys.time()+2400&&as.character(getRversion())=="4.6.0",
    "pinned R and complete bounded extension lifetime required")
  req(unname(Sys.info()[["nodename"]]) %in% c("muscat","muscat.be.ucsc.edu")&&
    Sys.getenv("LD_PRELOAD")==""&&all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1"),
    "Muscat one-thread bundled numerical environment required")
  blas <- unname(extSoftVersion()[["BLAS"]])
  req(identical(normalizePath(blas,mustWork=TRUE),normalizePath(file.path(R.home("lib"),"libRblas.so"),mustWork=TRUE)),
    "bundled BLAS identity differs")
  q2_limits(list(logical_cpu=27L,max_cpu_seconds=1800,max_wall_seconds=2400,
    max_memory_bytes=16*1024^3,max_output_bytes=256*1024^2))
  timeout_identity <- mq_pe_exact_timeout_ancestor()
  pin <- function(x) {
    req(is.list(x)&&is.character(x$path)&&length(x$path)==1L&&is.numeric(x$size_bytes)&&
      length(x$size_bytes)==1L&&is.finite(x$size_bytes)&&x$size_bytes>=0&&
      is.character(x$sha256)&&length(x$sha256)==1L&&grepl("^[a-f0-9]{64}$",x$sha256),
      "invalid pinned input schema")
    q2_regular(x$path)
    req(file.exists(x$path)&&!isTRUE(file.info(x$path)$isdir)&&file.info(x$path)$size==x$size_bytes&&
      identical(unname(tools::sha256sum(x$path)),x$sha256),"pinned source/input bytes changed")
    x$path
  }
  req(is.list(spec$source_files)&&length(spec$source_files)>=10L,"complete source pin inventory required")
  source_paths <- vapply(spec$source_files,pin,character(1L))
  required <- c("scripts/qualify_mq_precision_extension.R","scripts/qualify_mq_batch_acceleration.R",
    "scripts/qualify_integrated_quantile_forecast.R","scripts/mq_independent_cdf_certificate.R",
    "scripts/mq_streaming_cdf_certificate.R","scripts/integrated_quantile_mq_batch.R",
    "application/R/integrated_quantile_forecast.R","application/R/00_packages.R",
    "application/R/joint_qvp_qdesn.R","application/R/latent_path_design.R",
    "application/R/joint_qdesn_pure_recursive_campaign.R","application/R/joint_qdesn_recursive_mean_design.R")
  req(all(startsWith(source_paths,paste0(root,"/")))&&!anyDuplicated(source_paths)&&
    all(file.path(root,required) %in% source_paths),"every executable/native/new helper must be pinned inside this checkout")
  sm <- pin(spec$source_manifest)
  req(identical(sm,file.path(root,"docs/reproducibility/integrated_forecast_transition_sources_20261031.csv")),
    "native source-manifest path changed")
  m <- read.csv(sm,stringsAsFactors=FALSE)
  req(all(c("path","sha256","mode","blob") %in% names(m))&&!anyDuplicated(m$path)&&
    all(file.path(root,m$path) %in% source_paths),"original transitive manifest inventory required")
  for(i in seq_len(nrow(m))) {
    req(identical(unname(tools::sha256sum(app_iqf_safe_path(root,m$path[i]))),m$sha256[i]),
      "original native helper hash differs")
    stage <- git(c("ls-files","--stage","--",shQuote(m$path[i])))
    req(length(stage)==1L&&startsWith(stage,paste(m$mode[i],m$blob[i])),"original native helper Git mode/blob differs")
  }
  pin(spec$native_rng_source)
  req(identical(spec$native_rng_source$sha256,"6ef2c5d552c087cd57e0ef49386e01e0174b40433e4ad8d572461b20c958450e"),
    "exact native R4.6 RNG source required")
  old <- mq_pe_verify_baseline(spec,root,pin)
  original <- jsonlite::read_json(pin(spec$original_unit_contract),simplifyVector=FALSE)
  q2_geometry(original)
  fields <- c("schema_version","purpose","source_schema","model_cell_id","chain_id","source_row",
    "source_draw_index","origin_id","origin_time","horizons","inner_paths","readout_slopes","tau",
    "rng_namespace","posterior_target_sha256","integration_accuracy")
  req(identical(spec$original_unit[fields],original[fields]),"original source-unit geometry or target changed")
  metadata <- q2_metadata(spec$original_unit)
  req(!"exdqlm" %in% loadedNamespaces(),"no installed-package substitution is allowed")
  output <- spec$output_root
  req(is.character(output)&&length(output)==1L&&startsWith(output,paste0(root,"/local_trackers/"))&&
    !file.exists(output),"fresh ignored extension output root required")
  q2_regular(output);parent <- dirname(output)
  req(dir.exists(parent)&&identical(normalizePath(parent,mustWork=TRUE),parent)&&
    system2("git",c("check-ignore","--quiet","--",shQuote(output)))==0L,"real precreated ignored output parent required")
  req(dir.create(output),"fresh output creation failed")
  write_json <- function(x,name) {
    p <- file.path(output,name);tmp <- paste0(p,".tmp")
    jsonlite::write_json(x,tmp,pretty=TRUE,auto_unbox=TRUE,digits=17,null="null")
    req(file.rename(tmp,p),"atomic extension receipt write failed")
  }
  progress <- function(phase,...) write_json(list(schema_version="mq_precision_extension_progress_v1",
    phase=phase,timestamp_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
    source_commit=spec$source_commit,purpose_contract_sha256=args[4L],
    production_authorized=FALSE,details=list(...)),"progress.json")
  input_bytes <- sum(metadata$size_bytes)+spec$original_unit_contract$size_bytes
  admin_bytes <- 1024^2
  seal <- function() {
    paths <- list.files(output,full.names=TRUE,all.files=TRUE,no..=TRUE)
    req(all(!file.info(paths)$isdir)&&all(is.finite(file.info(paths)$size))&&
      all(!nzchar(Sys.readlink(paths))),"extension packet must contain only regular direct files")
    paths <- paths[basename(paths)!="artifact_manifest.csv"]
    rows <- data.frame(relative_path=basename(paths),size_bytes=unname(file.info(paths)$size),
      sha256=unname(tools::sha256sum(paths)))
    req(sum(rows$size_bytes)+input_bytes+admin_bytes<spec$limits$output_bytes,
      "complete extension/input/administration packet exceeds finite output budget")
    write.csv(rows,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
    req(sum(file.info(list.files(output,full.names=TRUE,all.files=TRUE,no..=TRUE))$size)+
      input_bytes+admin_bytes<=spec$limits$output_bytes,"sealed complete packet exceeds finite output budget")
    invisible(rows)
  }
  save <- function(x,name) {
    p <- file.path(output,name);req(!file.exists(p),"extension artifact overwrite forbidden")
    saveRDS(x,p,compress=TRUE);invisible(p)
  }
  rng <- function()list(kind=RNGkind(),present=exists(".Random.seed",.GlobalEnv,inherits=FALSE),
    seed=if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL)
  initial_rng <- rng();started <- proc.time()
  progress("ADMITTED_BASELINE_REVERIFIED_PAYLOAD_LOAD")
  tryCatch({
    unit <- spec$original_unit
    d <- readRDS(unit$assets$design$path);f <- readRDS(unit$assets$fixture$path)
    posterior <- read.csv(unit$assets$posterior$path,stringsAsFactors=FALSE)
    objects <- q2_payloads(d,f,posterior,unit);rm(d,f,posterior);gc(FALSE)
    for(file in c("00_packages.R","joint_qvp_qdesn.R","latent_path_design.R",
      "joint_qdesn_pure_recursive_campaign.R","joint_qdesn_recursive_mean_design.R"))source(file.path(root,"application/R",file))
    source(file.path(root,"scripts/integrated_quantile_mq_batch.R"))
    source(file.path(root,"scripts/mq_independent_cdf_certificate.R"))
    source(file.path(root,"scripts/mq_streaming_cdf_certificate.R"))
    app_set_repo_root(root)
    tau <- as.numeric(unlist(unit$tau));H <- 30L;K <- length(tau)
    draw <- objects$posterior$draw_ids;origin <- as.character(unit$origin_id)
    coupling <- list(method="native_joint_posterior",
      recipe_sha256=app_iqf_hash(list(source=unit$assets$posterior$sha256,row=1L,method="native_joint_posterior")),
      draw_mapping_sha256=objects$posterior$draw_mapping_sha256)
    scalar <- app_iqf_desn_adapter(objects$design,objects$posterior,objects$origins,tau,
      "mq_grid",coupling,unit$rng_namespace)
    batch <- app_iqf_mq_batch_adapter(objects$design,objects$posterior,objects$origins,tau,
      coupling,unit$rng_namespace,inner_paths=327680L,batch_size=128L,rng_mode="r46_first_step_qualified",
      rng_proof=list(R_version="4.6.0",RNG_c_sha256=spec$native_rng_source$sha256))
    req(identical(scalar$coupling,batch$coupling)&&identical(scalar$outer_conditioning,batch$outer_conditioning),
      "source posterior coupling/conditioning differs")
    check_parity <- function(ids,role) {
      bp <- app_iqf_mq_batch_paths(batch,draw,origin,ids)
      max_response <- max_kernel <- 0
      for(i in seq_along(ids)) {
        sp <- scalar$path(draw,origin,ids[i])
        response_delta <- abs(sp$response-bp$response[i,])
        kernel <- do.call(rbind,lapply(sp$kernels,`[[`,"q"))
        bkernel <- t(matrix(bp$ordered_quantiles[i,,],K,H))
        kernel_delta <- abs(kernel-bkernel)
        req(all(response_delta<=spec$parity_absolute_tolerance+spec$parity_relative_tolerance*
            pmax(abs(sp$response),abs(bp$response[i,])))&&
          all(kernel_delta<=spec$parity_absolute_tolerance+spec$parity_relative_tolerance*pmax(abs(kernel),abs(bkernel))),
          "prospective native/batch path parity failed")
        max_response <- max(max_response,response_delta);max_kernel <- max(max_kernel,kernel_delta)
      }
      req(identical(rng(),initial_rng),"native parity changed caller RNG")
      list(path_ids=ids,response_values=length(ids)*H,kernel_values=length(ids)*H*K,
        maximum_response_difference=max_response,maximum_kernel_difference=max_kernel,pass=TRUE,role=role)
    }
    ids <- mq_pe_parity_ids(spec,FALSE,FALSE)
    progress("PREDECLARED_TRAINING_ID_NATIVE_PARITY_RUNNING",path_count=length(ids))
    parity <- list(declared_path_ids=as.integer(unlist(spec$parity_path_ids,use.names=FALSE)),
      training_phase=check_parity(ids,"fixed_training_id_source_parity_before_training"),
      validation_phase=NULL,validation_phase_status="NOT_RUN_CANDIDATES_NOT_YET_FROZEN")
    save(parity,"predetermined_native_path_parity.rds")
    gc(FALSE)
    N <- 65536L
    q <- array(NA_real_,c(N,K,H));responses <- matrix(NA_real_,N,H)
    progress("TRAINING_PATHS_RUNNING",completed_paths=0L,total_paths=N)
    train_start <- proc.time()
    starts <- seq.int(1L,N,by=128L)
    for(block in seq_along(starts)) {
      rows <- seq.int(starts[block],min(N,starts[block]+127L))
      path <- app_iqf_mq_batch_paths(batch,draw,origin,rows)
      q[rows,,] <- path$ordered_quantiles;responses[rows,] <- path$response
      req(identical(rng(),initial_rng),"training path generation changed caller RNG")
      if(block%%8L==0L||block==length(starts))progress("TRAINING_PATHS_RUNNING",completed_paths=max(rows),
        total_paths=N,elapsed_seconds=unname((proc.time()-train_start)["elapsed"]))
    }
    training_path_time <- proc.time()-train_start
    save(list(schema_version="mq_precision_training_arrays_v1",ordered_quantiles=q,responses=responses,
      training_path_range=c(1L,N),draw_id=draw,origin_id=origin,rng_namespace=unit$rng_namespace,
      posterior_target_sha256=unit$posterior_target_sha256,source_commit=spec$source_commit,
      future_truth_used=FALSE,production_authorized=FALSE),"training_arrays.rds")
    candidates <- diagnostics <- vector("list",H)
    inverse_start <- proc.time()
    for(h in seq_len(H)) {
      kernels <- lapply(seq_len(N),function(i)list(family="mq_grid",q=as.numeric(q[i,,h]),tau=tau))
      full <- app_iqf_mq_mixture_inverse(kernels,tau,spec$inversion_tolerance)
      left <- app_iqf_mq_mixture_inverse(kernels[seq_len(N/2L)],tau,spec$inversion_tolerance)
      right <- app_iqf_mq_mixture_inverse(kernels[seq.int(N/2L+1L,N)],tau,spec$inversion_tolerance)
      candidates[[h]] <- data.frame(horizon=h,probability=tau,quantile=full)
      diagnostics[[h]] <- data.frame(horizon=h,probability=tau,
        split_stream_absolute_difference=abs(left-right),
        split_stream_relative_difference=abs(left-right)/pmax(1,abs((left+right)/2)),
        left_paths=N/2L,right_paths=N/2L,inversion_tolerance=spec$inversion_tolerance)
      progress("TRAINING_CANDIDATE_INVERSION_RUNNING",completed_horizons=h,total_horizons=H)
    }
    inversion_time <- proc.time()-inverse_start
    candidates <- do.call(rbind,candidates);diagnostics <- do.call(rbind,diagnostics)
    split_ok <- all(diagnostics$split_stream_absolute_difference<=.005|diagnostics$split_stream_relative_difference<=.005)
    save(candidates,"frozen_training_candidates.rds");save(diagnostics,"training_split_diagnostic.rds")
    write.csv(diagnostics,file.path(output,"training_split_diagnostic.csv"),row.names=FALSE)
    training_file_sha <- unname(tools::sha256sum(file.path(output,"training_arrays.rds")))
    candidate_sha <- unname(tools::sha256sum(file.path(output,"frozen_training_candidates.rds")))
    split_sha <- unname(tools::sha256sum(file.path(output,"training_split_diagnostic.rds")))
    rm(q,responses,kernels,path);gc(FALSE);seal()
    stream <- NULL;validation_paths <- 0L;validation_time <- c(user.self=0,sys.self=0,elapsed=0)
    if(split_ok) {
      ids <- mq_pe_parity_ids(spec,TRUE,TRUE)
      progress("PREDECLARED_VALIDATION_ID_NATIVE_PARITY_AFTER_FREEZE",path_count=length(ids),
        frozen_training_candidates_sha256=candidate_sha)
      parity$validation_phase <- check_parity(ids,"fixed_validation_id_parity_after_candidate_freeze_and_split_pass")
      parity$validation_phase_status <- "PASS_AFTER_FROZEN_CANDIDATES_AND_SPLIT_GATE"
      save(parity$validation_phase,"deferred_validation_native_path_parity.rds")
      grid <- mq_icc_candidates(candidates,.01,.01)
      stream_contract <- list(schema_version="mq_streaming_cdf_certificate_contract_v1",
        method="heldout_conditional_CDF_empirical_Bernstein_alpha_spending",
        conditioning="one_fixed_original_parameter_draw_and_observed_origin",
        validation_values="iid_future_path_conditional_CDF_not_particle_filter",
        candidates_from_training_paths_only=TRUE,rng_namespace=unit$rng_namespace,draw_id=draw,origin_id=origin,
        training_path_range=c(1L,65536L),validation_path_range=c(65537L,327680L),
        look_sizes=c(65536L,131072L,262144L),total_alpha=.05,alpha_per_look=rep(.05/3,3L),
        absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01,
        training_split_diagnostic=diagnostics,source_commit=spec$source_commit,
        source_manifest_sha256=spec$source_manifest$sha256,posterior_target_sha256=unit$posterior_target_sha256)
      stream <- mq_scc_init(candidates,stream_contract)
      progress("INDEPENDENT_STREAMING_VALIDATION_RUNNING",completed_paths=0L,max_paths=262144L)
      val_start <- proc.time()
      for(look in c(65536L,131072L,262144L)) {
        next_rows <- seq.int(stream$count+1L,look,by=128L)
        for(first in next_rows) {
          relative_ids <- seq.int(first,min(look,first+127L));path_ids <- 65536L+relative_ids
          paths <- app_iqf_mq_batch_paths(batch,draw,origin,path_ids)
          values <- matrix(NA_real_,length(path_ids),grid$endpoint_count,
            dimnames=list(NULL,grid$endpoints$endpoint_id))
          for(h in seq_len(H)) {
            at <- which(grid$endpoints$horizon==h)
            values[,at] <- mq_baq_cdf_rows(grid$endpoints$y[at],
              matrix(paths$ordered_quantiles[,,h],length(path_ids),K),tau)
          }
          stream <- mq_scc_update(stream,values,path_ids)
          req(identical(rng(),initial_rng),"validation path generation changed caller RNG")
          if(stream$count%%1024L==0L||stream$count==look)progress("INDEPENDENT_STREAMING_VALIDATION_RUNNING",
            completed_paths=stream$count,max_paths=262144L,next_look=look,
            elapsed_seconds=unname((proc.time()-val_start)["elapsed"]))
        }
        stream <- mq_scc_evaluate(stream);validation_paths <- stream$count
        save(stream,sprintf("validation_stream_look_%06d.rds",stream$count))
        write.csv(stream$last_evaluation$endpoint_evidence,
          file.path(output,sprintf("validation_endpoints_look_%06d.csv",stream$count)),row.names=FALSE)
        progress("PREDECLARED_VALIDATION_LOOK_EVALUATED",completed_paths=stream$count,
          look_status=stream$last_evaluation$status,all_required_gates_pass=stream$last_evaluation$all_required_gates_pass)
        seal()
        if(isTRUE(stream$terminal))break
      }
      validation_time <- proc.time()-val_start
    } else {
      parity$validation_phase_status <- "NOT_RUN_TRAINING_SPLIT_REVIEW"
      req(length(mq_pe_parity_ids(spec,TRUE,FALSE))==0L,"split failure cannot authorize validation parity")
      progress("TRAINING_SPLIT_REVIEW_VALIDATION_NOT_STARTED",split_passed=sum(
        diagnostics$split_stream_absolute_difference<=.005|diagnostics$split_stream_relative_difference<=.005),
        split_total=nrow(diagnostics),validation_paths_generated=0L,validation_parity_paths_generated=0L)
    }
    save(parity,"native_path_parity_final.rds")
    for(x in spec$source_files)pin(x)
    pin(spec$native_rng_source);pin(spec$source_manifest);pin(spec$original_unit_contract)
    final_baseline <- mq_pe_verify_baseline(spec,root,pin);q2_metadata(unit)
    req(identical(unname(tools::sha256sum(file.path(output,"training_arrays.rds"))),training_file_sha)&&
      identical(unname(tools::sha256sum(file.path(output,"frozen_training_candidates.rds"))),candidate_sha)&&
      identical(unname(tools::sha256sum(file.path(output,"training_split_diagnostic.rds"))),split_sha),
      "frozen training arrays/candidates/split evidence changed after validation admission")
    req(identical(rng(),initial_rng)&&expiry>Sys.time()&&!"exdqlm" %in% loadedNamespaces()&&
      identical(git(c("rev-parse","HEAD")),spec$source_commit)&&
      identical(git(c("rev-parse","HEAD^{tree}")),spec$source_tree)&&
      length(git(c("status","--porcelain","--untracked-files=normal")))==0L,
      "source/runtime/RNG scope changed during extension")
    passed <- split_ok&&!is.null(stream)&&isTRUE(stream$last_evaluation$all_required_gates_pass)
    status <- if(!split_ok)"REVIEW_TRAINING_SPLIT_VALIDATION_NOT_STARTED" else if(passed)
      "PASS_PREDECLARED_PRECISION_EXTENSION_ONLY" else "REVIEW_MAXIMUM_PREDECLARED_PRECISION_NOT_QUALIFIED"
    receipt <- list(schema_version="mq_precision_extension_qualification_receipt_v1",
      status="QUALIFICATION_COMPLETE_NOT_PRODUCTION",numerical_status=status,
      source_commit=spec$source_commit,source_tree=spec$source_tree,purpose_contract_sha256=args[4L],
      baseline_contract=spec$baseline_contract,baseline_receipt=spec$baseline_receipt,
      baseline_manifest=spec$baseline_manifest,baseline_outputs_reverified=final_baseline$files_verified,
      baseline_output_bytes=final_baseline$bytes_verified,baseline_outputs_copied=FALSE,
      original_unit_contract=spec$original_unit_contract,original_unit=unit,
      source_manifest=spec$source_manifest,native_rng_source=spec$native_rng_source,rng_backend=spec$rng_backend,
      original_row_mapping=objects$mapping,predetermined_parity=parity,
      parity_training_paths_checked=length(parity$training_phase$path_ids),
      parity_validation_paths_checked=if(is.null(parity$validation_phase))0L else length(parity$validation_phase$path_ids),
      validation_paths_generated_before_candidate_freeze=0L,
      original_full_4096_scalar_parity_reused_not_rerun=TRUE,
      training_paths=65536L,training_array_sha256=training_file_sha,frozen_training_candidates_sha256=candidate_sha,
      frozen_training_split_diagnostic_sha256=split_sha,
      training_split_passed=sum(diagnostics$split_stream_absolute_difference<=.005|
        diagnostics$split_stream_relative_difference<=.005),training_split_total=nrow(diagnostics),
      training_split_gate_pass=split_ok,stop_before_validation_on_split_failure=TRUE,
      validation_paths_generated=validation_paths,maximum_validation_paths=262144L,
      validation_paths_generated_scope="certificate_stream_only_separate_parity_counts_retained",
      unique_validation_path_ids_generated=validation_paths+if(is.null(parity$validation_phase))0L else
        sum(parity$validation_phase$path_ids>65536L+validation_paths),
      validation_path_range=c(65537L,327680L),predeclared_look_sizes=c(65536L,131072L,262144L),
      total_alpha=.05,alpha_per_look=rep(.05/3,3L),
      assessed_looks=if(is.null(stream))list()else stream$look_history,
      final_certificate=if(is.null(stream))NULL else stream$last_evaluation,
      retention_policy=spec$retention_policy,full_validation_matrix_retained=FALSE,
      original_failure_receipts_preserved=TRUE,thresholds_loosened=FALSE,
      training_path_CPU_seconds=sum(training_path_time[1:2]),training_path_wall_seconds=unname(training_path_time["elapsed"]),
      training_inversion_CPU_seconds=sum(inversion_time[1:2]),training_inversion_wall_seconds=unname(inversion_time["elapsed"]),
      validation_CPU_seconds=sum(validation_time[1:2]),validation_wall_seconds=unname(validation_time["elapsed"]),
      process_CPU_seconds=sum(proc.time()[1:2]),process_wall_seconds=unname(proc.time()["elapsed"]),
      numerical_phase_CPU_seconds=sum((proc.time()-started)[1:2]),
      numerical_phase_wall_seconds=unname((proc.time()-started)["elapsed"]),
      VmHWM=grep("^VmHWM:",readLines("/proc/self/status",warn=FALSE),value=TRUE),
      finite_limits=spec$limits,exact_timeout_ancestor=timeout_identity,
      staged_original_input_bytes=input_bytes,administration_reserve_bytes=admin_bytes,
      observational_future_truth_used=FALSE,parameter_refits=0L,score_evaluations=0L,
      full_campaign_enrollment=FALSE,production_authorized=FALSE,article_promotion_authorized=FALSE)
    write_json(receipt,"qualification.json")
    progress("QUALIFICATION_COMPLETE_NOT_PRODUCTION",numerical_status=status,
      training_split_gate_pass=split_ok,validation_paths_generated=validation_paths)
    seal()
    cat("MQ_PRECISION_EXTENSION_COMPLETE_NOT_PRODUCTION numerical_status=",status,
      " fits=0 scoring=0 production=FALSE\n",sep="")
    invisible(receipt)
  },error=function(e) {
    try(write_json(list(schema_version="mq_precision_extension_failure_v1",
      status="QUALIFICATION_FAILED_NOT_PRODUCTION",source_commit=spec$source_commit,
      purpose_contract_sha256=args[4L],error=conditionMessage(e),production_authorized=FALSE),"failure.json"),silent=TRUE)
    try(progress("QUALIFICATION_FAILED_NOT_PRODUCTION",error=conditionMessage(e)),silent=TRUE)
    try(seal(),silent=TRUE);stop(e)
  })
}
if(sys.nframe()==0L)mq_pe_main()
