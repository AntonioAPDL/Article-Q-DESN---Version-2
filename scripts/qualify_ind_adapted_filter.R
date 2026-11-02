#!/usr/bin/env Rscript
# One separately admitted AL training-only numerical purpose; no production.
source("scripts/runtime_identity_cache_observations.R",local=TRUE)
ind_aq_require <- function(x,message) {
  if(!isTRUE(x))stop(paste0("IND ancestor-first qualification: ",message),call.=FALSE)
  invisible(TRUE)
}
ind_aq_scope <- function(s) {
  q <- ind_aq_require
  eq <- function(x,y)is.numeric(unlist(x))&&identical(as.numeric(unlist(x)),as.numeric(y))
  q(is.list(s)&&identical(s$schema_version,"ind_ancestor_first_filter_qualification_v1")&&
    identical(s$allow_qualification,TRUE)&&identical(s$allow_refit,FALSE)&&
    identical(s$allow_production,FALSE)&&identical(s$allow_scoring,FALSE)&&
    identical(s$allow_article_promotion,FALSE),"qualification-only scope required")
  q(identical(s$method,"ancestor_first_AL_exact_v_v1")&&
    identical(s$rng_namespace,"ind_ancestor_first_AL_training_H1_v1")&&
    identical(s$rng_layout,"Mersenne_Twister_time_major_proposal4_then_ancestor_then_residual_v1")&&
    eq(s$posterior_column,1)&&eq(s$observed_prefix_length,500)&&
    eq(s$particle_resolutions,c(64,256,1024))&&eq(s$seeds,c(71521,71522))&&
    eq(s$checkpoint_indices,c(100,250,500))&&eq(s$probabilities,c(.05,.5,.95))&&
    eq(s$ess_fraction,.5)&&eq(s$inversion_absolute_tolerance,1e-8)&&
    eq(s$agreement_absolute_tolerance,.005)&&eq(s$agreement_relative_tolerance,.005),
    "fixed new-purpose method, streams, native column, training geometry and thresholds required")
  l <- s$limits
  q(is.list(l)&&eq(l$cpu_seconds,1800)&&eq(l$wall_term_seconds,1799)&&eq(l$wall_kill_after_seconds,1)&&
    eq(l$address_space_bytes,16*1024^3)&&eq(l$output_bytes,96*1024^2),"fixed finite purpose limits required")
  fixed <- c(training_input="d38bd5f49744c67861908f8fd960781bf97efdf1c43473829b46894574252496",
    native_forward_receipt="440da6c4d71554952947b128c77758f86aea385c7cb3ceb203ddad5ff5737bff",
    bootstrap_receipt="b14b6ea359d6f48f37134d40e87ca2d37f8dd33d954c5c59f479352fa495e599",
    historical_guided_receipt="ce2b82b96b57de42cedd3f856f5f630e4f9387d70d9219edb47db28b64a1a2b2",
    original_fit="1e8ba3de4a6c9e9e0f6bd900be7801e8c80fe0fdff4b6ca24804bdc62e3ff17f",
    native_cpp="f6ccf41466ece60a3a63737bb434309e8bea59f5b254a086793e5cca0aba6065")
  for(k in names(fixed))q(is.list(s[[k]])&&identical(s[[k]]$sha256,unname(fixed[k])),
    paste("frozen original input/proof identity required:",k))
  q(eq(s$training_input$size_bytes,13728)&&eq(s$original_fit$size_bytes,611287756),
    "exact truth-free input and hash-only original fit sizes required")
  invisible(TRUE)
}
ind_aq_regular <- function(path) {
  ind_aq_require(is.character(path)&&length(path)==1L&&!is.na(path)&&startsWith(path,"/")&&
    !grepl("(^|/)\\.\\.(/|$)",path)&&file.exists(path)&&!isTRUE(file.info(path)$isdir)&&
    identical(Sys.readlink(path),"")&&identical(normalizePath(path,mustWork=TRUE),path),
    "absolute nonsymlink regular file required")
  path
}
ind_aq_pin <- function(x,max_bytes=2*1024^2) {
  q <- ind_aq_require
  q(is.list(x)&&length(x)==3L&&!anyDuplicated(names(x))&&setequal(names(x),c("path","size_bytes","sha256"))&&is.numeric(x$size_bytes)&&
    length(x$size_bytes)==1L&&is.finite(x$size_bytes)&&x$size_bytes>=0&&x$size_bytes<=max_bytes&&
    x$size_bytes==as.integer(x$size_bytes)&&is.character(x$sha256)&&length(x$sha256)==1L&&
    grepl("^[a-f0-9]{64}$",x$sha256),"bounded exact file pin required")
  path <- ind_aq_regular(x$path)
  q(file.info(path)$size==x$size_bytes&&identical(unname(tools::sha256sum(path)),x$sha256),"pinned file bytes changed")
  path
}
ind_aq_timeout_argv <- function(x) {
  ind_aq_require(is.character(x)&&length(x)>=5L&&!anyNA(x)&&basename(x[1L])=="timeout"&&
    identical(x[2:4],c("--signal=TERM","--kill-after=1s","1799s"))&&!startsWith(x[5L],"-"),
    "exact native timeout TERM1799/KILL1 argv required")
  invisible(TRUE)
}
ind_aq_proc_stat <- function(x) {
  q <- ind_aq_require
  q(is.character(x)&&length(x)==1L&&!is.na(x),"one Linux process stat record required")
  # The parenthesized command can contain spaces and closing parentheses.
  # Match its final closing delimiter before state/ppid/pgrp/session.
  m <- regmatches(x,regexec("^([0-9]+) \\((.*)\\) ([[:alpha:]]) ([0-9]+) ([0-9]+) ([0-9]+)( |$)",x))[[1L]]
  q(length(m)==8L,"malformed Linux process stat record")
  v <- suppressWarnings(as.numeric(m[c(2L,5L,6L,7L)]))
  q(all(is.finite(v))&&all(v==floor(v))&&all(v<=.Machine$integer.max)&&
    v[1L]>0&&v[2L]>=0&&all(v[3:4]>0),"invalid Linux process identities")
  as.list(setNames(as.integer(v),c("pid","ppid","pgid","sid")))
}
ind_aq_process_group_proof <- function(self_stat,timeout_stat) {
  q <- ind_aq_require
  self <- ind_aq_proc_stat(self_stat);timeout <- ind_aq_proc_stat(timeout_stat)
  q(timeout$pgid==timeout$pid,"native timeout must lead its controlled process group")
  q(self$pid!=timeout$pid&&self$pgid==timeout$pgid&&self$sid==timeout$sid,
    "R must remain in the native timeout process group and session")
  list(payload_pid=self$pid,payload_pgid=self$pgid,payload_session=self$sid,
    timeout_pid=timeout$pid,timeout_pgid=timeout$pgid,timeout_session=timeout$sid,
    timeout_process_group_leader=TRUE,payload_same_timeout_group_and_session=TRUE)
}
ind_aq_process_limits <- function() {
  q <- ind_aq_require
  affinity <- function(pid="self") {
    z <- readLines(sprintf("/proc/%s/status",pid),warn=FALSE)
    trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",z,value=TRUE)))
  }
  q(identical(affinity(),"26"),"one granted logical CPU26 required")
  lines <- readLines("/proc/self/limits",warn=FALSE)
  for(p in list(c("Max cpu time",1800),c("Max address space",16*1024^3),c("Max file size",96*1024^2))) {
    row <- grep(paste0("^",p[1]),lines,value=TRUE)
    q(length(row)==1L,"missing OS limit")
    v <- suppressWarnings(as.numeric(strsplit(trimws(sub(paste0("^",p[1]),"",row)),"[[:space:]]+")[[1]][1:2]))
    q(all(is.finite(v))&&all(v>0)&&all(v<=as.numeric(p[2])),"finite CPU/address/file OS limits required")
  }
  pid <- Sys.getpid()
  for(i in 1:8) {
    status <- readLines(sprintf("/proc/%d/status",pid),warn=FALSE)
    parent <- suppressWarnings(as.integer(trimws(sub("^PPid:","",grep("^PPid:",status,value=TRUE)))))
    if(length(parent)!=1L||is.na(parent)||parent<=1L)break
    raw <- readBin(sprintf("/proc/%d/cmdline",parent),"raw",n=16384L)
    ends <- which(raw==as.raw(0));starts <- c(1L,head(ends,-1L)+1L)
    if(length(ends)&&tail(ends,1L)==length(raw)) {
      argv <- vapply(seq_along(ends),function(j)if(starts[j]>=ends[j])"" else
        rawToChar(raw[seq.int(starts[j],ends[j]-1L)]),character(1L))
      if(basename(argv[1L])=="timeout") {
        ind_aq_timeout_argv(argv)
        exe <- normalizePath(Sys.readlink(sprintf("/proc/%d/exe",parent)),mustWork=TRUE)
        q(identical(exe,normalizePath("/usr/bin/timeout",mustWork=TRUE))&&identical(affinity(parent),"26"),
          "native timeout ancestor must itself be confined to CPU26")
        group <- ind_aq_process_group_proof(readLines("/proc/self/stat",warn=FALSE),
          readLines(sprintf("/proc/%d/stat",parent),warn=FALSE))
        q(group$payload_pid==Sys.getpid()&&group$timeout_pid==parent,
          "process-group proof must bind the actual payload and timeout ancestor")
        return(list(pid=parent,argv=argv[1:5],executable=exe,affinity="26",
          process_group=group,aggregate_single_CPU_wall_bound_seconds=1800L))
      }
    }
    pid <- parent
  }
  q(FALSE,"bounded native timeout ancestor missing")
}

ind_aq_strict_mappings_present <- function(paths,present,is_directory) {
  ind_aq_require(is.character(paths)&&!anyNA(paths)&&!anyDuplicated(paths)&&
    is.logical(present)&&length(present)==length(paths)&&!anyNA(present)&&all(present)&&
    is.logical(is_directory)&&length(is_directory)==length(paths)&&!anyNA(is_directory)&&
    !any(is_directory),"every strict mapped file must remain present and non-directory")
  invisible(TRUE)
}
ind_aq_runtime_inventory <- function() {
  q <- ind_aq_require
  packages <- c("base","compiler","datasets","graphics","grDevices","methods","stats","utils","tools","digest","jsonlite")
  for(p in packages)q(requireNamespace(p,quietly=TRUE),paste("required pinned package unavailable",p))
  q(all(loadedNamespaces() %in% packages),"unlisted namespace or installed model substitution")
  roots <- vapply(packages,function(p)find.package(p,quiet=TRUE),character(1L))
  files <- unlist(lapply(roots,function(p)list.files(p,recursive=TRUE,full.names=TRUE,all.files=TRUE,no..=TRUE)),use.names=FALSE)
  os <- runtime_ic_snapshot()
  ind_aq_strict_mappings_present(os$strict_mapped_paths,file.exists(os$strict_mapped_paths),
    file.info(os$strict_mapped_paths,extra_cols=FALSE)$isdir)
  files <- c(files,os$strict_mapped_paths,Sys.readlink("/proc/self/exe"),file.path(R.home("bin"),"Rscript"),
    Sys.which("git"),"/usr/bin/timeout")
  files <- files[file.exists(files)&!file.info(files)$isdir]
  files <- sort(unique(normalizePath(files,mustWork=TRUE)))
  q(length(files)>0L,"complete runtime closure required")
  result <- data.frame(path=files,size_bytes=as.numeric(file.info(files)$size),
    sha256=unname(tools::sha256sum(files)),stringsAsFactors=FALSE)
  attr(result,"observational_os_state") <- os$observational_os_state
  attr(result,"observational_os_state_role") <- os$observation_role
  result
}
ind_aq_runtime_match <- function(expected,actual) {
  fields <- c("path","size_bytes","sha256")
  ind_aq_require(is.data.frame(expected)&&identical(names(expected),fields)&&
    is.data.frame(actual)&&identical(names(actual),fields)&&!anyDuplicated(expected$path)&&
    identical(expected$path,actual$path)&&identical(as.numeric(expected$size_bytes),as.numeric(actual$size_bytes))&&
    identical(expected$sha256,actual$sha256),"complete runtime/package/shared-mapping bytes changed")
  invisible(TRUE)
}

ind_aq_truth_free_input <- function(input,eta) {
  q <- ind_aq_require
  fields <- c("y","FF","GG","m0","C0","ex_f","ex_q","df_mat","observed_prefix_length")
  q(is.list(input)&&length(input)==length(fields)&&!anyDuplicated(names(input))&&
    setequal(names(input),fields)&&input$observed_prefix_length==500L&&
    is.numeric(input$y)&&length(input$y)==500L&&all(is.finite(input$y))&&
    is.numeric(input$m0)&&length(input$m0)==6L&&all(is.finite(input$m0))&&
    is.matrix(input$FF)&&identical(dim(input$FF),c(6L,500L))&&all(is.finite(input$FF))&&
    is.numeric(input$GG)&&(identical(dim(input$GG),c(6L,6L))||identical(dim(input$GG),c(6L,6L,500L))),
    "exact physically training-only500-row input required; full fixtures are forbidden")
  q(identical(as.numeric(input$FF),as.numeric(matrix(rep(input$FF[,1L],500L),6L,500L))),
    "H1 endpoint extension requires verified constant training F")
  if(length(dim(input$GG))==3L)q(all(vapply(seq_len(500L),function(t)
    identical(matrix(input$GG[,,t],6L,6L),matrix(input$GG[,,1L],6L,6L)),logical(1L))),
    "H1 endpoint extension requires verified constant training G")
  ind_caf_psd(input$C0,6L,1e-10,"qualification C0")
  ind_caf_psd(input$df_mat,6L,1e-10,"qualification discount")
  q(all(input$df_mat>=0)&&all(is.finite(input$GG)),"invalid source discount/evolution")
  A <- (1-2*eta$p)/(eta$p*(1-eta$p));B <- 2/(eta$p*(1-eta$p))
  v <- input$ex_q/(B*eta$sigma)
  q(is.numeric(input$ex_q)&&length(v)==500L&&all(is.finite(v))&&all(v>0)&&
    is.numeric(input$ex_f)&&length(input$ex_f)==500L&&all(is.finite(input$ex_f))&&
    all(abs(input$ex_f-A*v)<=1e-12*pmax(1,abs(input$ex_f))),
    "native scale/probability mismatches paired-input proof")
  invisible(TRUE)
}

ind_aq_main <- function(args=commandArgs(TRUE)) {
  entered <- proc.time()
  oldkind <- RNGkind();had <- exists(".Random.seed",.GlobalEnv,inherits=FALSE)
  oldseed <- if(had)get(".Random.seed",.GlobalEnv)else NULL
  restore <- function() {
    do.call(RNGkind,as.list(oldkind))
    if(had)assign(".Random.seed",oldseed,.GlobalEnv)else if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)
  }
  on.exit(restore(),add=TRUE)
  if(identical(args,"--help")) {
    cat("Usage: Rscript --vanilla scripts/qualify_ind_adapted_filter.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  q <- ind_aq_require
  q(length(args)==5L&&identical(args[c(1,3,5)],c("--contract","--sha256","--execute")),"exact contract/hash/execute arguments required")
  cp <- ind_aq_regular(args[2]);q(file.info(cp)$size<=512*1024&&
    identical(unname(tools::sha256sum(cp)),args[4]),"bounded external purpose contract SHA mismatch")
  spec <- jsonlite::read_json(cp,simplifyVector=FALSE);ind_aq_scope(spec)
  root <- normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(cp,paste0(root,"/")),"external purpose must be outside source checkout")
  git <- function(a) {
    z <- system2("git",c("--no-optional-locks","--no-replace-objects",a),stdout=TRUE)
    q(is.null(attr(z,"status")),"read-only Git source check failed");unname(z)
  }
  q(identical(git(c("rev-parse","HEAD")),spec$source_commit)&&
    identical(git(c("rev-parse","HEAD^{tree}")),spec$source_tree)&&
    length(git(c("status","--porcelain","--untracked-files=normal")))==0L,"clean frozen source/tree required")
  expiry <- as.POSIXct(spec$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry)&&expiry>Sys.time()+1800&&as.character(getRversion())=="4.6.0"&&
    "--vanilla" %in% commandArgs(FALSE)&&Sys.info()[["nodename"]] %in% c("muscat","muscat.be.ucsc.edu"),
    "complete bounded lifetime and native vanilla Muscat R4.6 required")
  q(Sys.getenv("LD_PRELOAD")==""&&all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1")&&
    Sys.getenv("R_LIBS_USER")=="/dev/null"&&Sys.getenv("R_LIBS_SITE")=="/dev/null"&&
    identical(normalizePath(.libPaths(),mustWork=TRUE),normalizePath(file.path(R.home(),"library"),mustWork=TRUE)),
    "explicit core-only one-thread runtime environment required")
  blas <- normalizePath(unname(extSoftVersion()[["BLAS"]]),mustWork=TRUE)
  q(identical(blas,normalizePath(file.path(R.home("lib"),"libRblas.so"),mustWork=TRUE)),"bundled BLAS required")
  timeout <- ind_aq_process_limits()
  sources <- c("scripts/qualify_ind_adapted_filter.R","scripts/ind_adapted_auxiliary_filter.R",
    "scripts/ind_guided_auxiliary_filter.R","scripts/ind_guided_auxiliary_primitives.R",
    "scripts/ind_conditional_auxiliary_filter.R","scripts/ind_conditional_filter_replay.R",
    "scripts/qualify_ind_guided_filter.R","scripts/runtime_identity_cache_observations.R")
  q(is.list(spec$source_files)&&length(spec$source_files)==length(sources),"complete exact source/reference inventory required")
  paths <- vapply(spec$source_files,ind_aq_pin,character(1L))
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,sources)),"unlisted or missing transitive source")
  verify_source_blobs <- function()for(rel in sources) {
    q(identical(git(c("hash-object","--no-filters","--",shQuote(file.path(root,rel)))),
      git(c("rev-parse",shQuote(paste0("HEAD:",rel))))),"source bytes differ from the named commit blob")
  }
  verify_source_blobs()
  runtime_manifest <- read.csv(ind_aq_pin(spec$runtime_manifest),stringsAsFactors=FALSE)
  runtime <- ind_aq_runtime_inventory();ind_aq_runtime_match(runtime_manifest,runtime)
  source("scripts/ind_adapted_auxiliary_filter.R")
  for(k in c("training_input","native_forward_receipt","native_forward_manifest","bootstrap_receipt",
    "historical_guided_receipt","native_cpp"))ind_aq_pin(spec[[k]])
  ind_aq_pin(spec$original_fit,max_bytes=611287756) # HASH ONLY: never readRDS.
  native <- jsonlite::read_json(spec$native_forward_receipt$path,simplifyVector=FALSE)
  old <- jsonlite::read_json(spec$bootstrap_receipt$path,simplifyVector=FALSE)
  historical <- jsonlite::read_json(spec$historical_guided_receipt$path,simplifyVector=FALSE)
  same_fit <- function(x)identical(x$path,spec$original_fit$path)&&x$size_bytes==611287756&&
    identical(x$sha256,spec$original_fit$sha256)
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
    identical(native$native_cpp$sha256,spec$native_cpp$sha256)&&identical(old$native_cpp$sha256,spec$native_cpp$sha256),
    "authentic original source/column/scale and retained13of27REVIEW proof required")
  m <- read.csv(spec$native_forward_manifest$path,stringsAsFactors=FALSE)
  q(all(c("relative_path","size_bytes","sha256") %in% names(m))&&!anyDuplicated(m$relative_path),"native proof manifest malformed")
  for(k in c("training_input","native_forward_receipt")) {
    r <- m[m$relative_path==basename(spec[[k]]$path),,drop=FALSE]
    q(nrow(r)==1L&&r$size_bytes==spec[[k]]$size_bytes&&r$sha256==spec[[k]]$sha256,"input/proof does not bind original native manifest")
  }
  output <- spec$output_root;parent <- dirname(output)
  q(is.character(output)&&length(output)==1L&&startsWith(output,paste0(root,"/local_trackers/"))&&
    !grepl("(^|/)\\.\\.(/|$)",output)&&!file.exists(output)&&dir.exists(parent)&&
    identical(normalizePath(parent,mustWork=TRUE),parent)&&
    system2("git",c("--no-optional-locks","check-ignore","--quiet","--",shQuote(output)))==0L,
    "fresh ignored output with real precreated parent required")
  q(dir.create(output),"output creation failed")
  write_json <- function(x,name) {
    p <- file.path(output,name);tmp <- paste0(p,".tmp")
    jsonlite::write_json(x,tmp,pretty=TRUE,auto_unbox=TRUE,digits=17,null="null")
    q(file.rename(tmp,p),"atomic receipt write failed")
  }
  reserve <- 4*1024^2
  seal <- function() {
    paths <- list.files(output,all.files=TRUE,no..=TRUE,full.names=TRUE)
    q(all(!file.info(paths)$isdir)&&all(!nzchar(Sys.readlink(paths))),"only regular direct output artifacts allowed")
    paths <- paths[basename(paths)!="artifact_manifest.csv"]
    rows <- data.frame(relative_path=basename(paths),size_bytes=as.numeric(file.info(paths)$size),sha256=unname(tools::sha256sum(paths)))
    q(sum(rows$size_bytes)+reserve<96*1024^2,"complete purpose packet exceeds96MiB including administration reserve")
    write.csv(rows,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
    q(sum(file.info(list.files(output,all.files=TRUE,no..=TRUE,full.names=TRUE))$size)+reserve<=96*1024^2,"sealed packet budget exceeded")
  }
  progress <- function(phase,...)write_json(list(schema_version="ind_ancestor_first_progress_v1",phase=phase,
    timestamp_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),source_commit=spec$source_commit,
    purpose_contract_sha256=args[4],production_authorized=FALSE,details=list(...)),"progress.json")
  started <- proc.time()
  progress("ADMITTED_PINNED_TRAINING_ONLY_INPUT")
  write_json(list(role=attr(runtime,"observational_os_state_role"),
    observation_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
    observations=attr(runtime,"observational_os_state"),live_byte_equality_required=FALSE,
    numerical_inputs_and_software_remain_strictly_pinned=TRUE),"runtime_OS_identity_cache_before.json")
  tryCatch({
    input <- readRDS(spec$training_input$path) # The sole scientific RDS read.
    eta <- list(family="al",p=.05,sigma=old$sigma,gamma=0)
    ind_aq_truth_free_input(input,eta)
    constant_G <- if(is.matrix(input$GG))input$GG else matrix(input$GG[,,1L],6L,6L)
    checkpoints <- c(100L,250L,500L);probs <- c(.05,.5,.95);records <- list();runs <- list();quantiles <- list()
    for(seed in c(71521L,71522L)) {
      RNGkind("Mersenne-Twister","Inversion","Rejection");set.seed(seed)
      uniforms <- list(proposal=array(runif(1024L*500L*4L),c(1024L,500L,4L)),ancestor=runif(500L),residual_resampling=runif(500L))
      after <- .Random.seed
      saveRDS(list(rng_namespace=spec$rng_namespace,layout=spec$rng_layout,seed=seed,kind=RNGkind(),
        uniforms=uniforms),file.path(output,sprintf("supplied_stream_%d.rds",seed)),compress=TRUE)
      for(N in c(64L,256L,1024L)) {
        key <- sprintf("seed_%d_N_%04d",seed,N);progress("FILTER_RUNNING",seed=seed,N=N,completed_runs=length(runs))
        initial <- ind_aaf_initialize(input$m0,input$C0,input$df_mat,eta,N,
          "c72e19f345da88fc1a8175ed30bdde328eab88be:native_column:1",ess_fraction=.5)
        before <- proc.time()
        fit <- ind_aaf_continue(initial,input$y,input$FF,input$GG,
          list(proposal=uniforms$proposal[seq_len(N),,,drop=FALSE],ancestor=uniforms$ancestor,
            residual_resampling=uniforms$residual_resampling),1:500,checkpoints)
        timing <- proc.time()-before
        q(identical(.Random.seed,after),"supplied-stream filter mutated caller RNG")
        for(t in checkpoints) {
          cp0 <- fit$checkpoints[[as.character(t)]]
          components <- ind_gaf_origin_components(cp0,input$FF[,min(t+1L,500L)],constant_G,input$df_mat,"known_deterministic")
          qi <- ind_gap_mixture_quantile(probs,components$mean,components$variance,eta$p,eta$sigma,components$weight,1e-8,0)
          quantiles[[paste(seed,N,t,sep=":")]] <- qi$result$quantile
          records[[length(records)+1L]] <- data.frame(seed=seed,particles=N,observed_prefix_length=t,
            probability=probs,quantile=qi$result$quantile,training_only_diagnostic=TRUE,
            filter_accuracy_certified=FALSE,production_authorized=FALSE)
        }
        name <- paste0(key,".rds");saveRDS(fit,file.path(output,name),compress=TRUE)
        runs[[key]] <- list(seed=seed,particles=N,file=name,sha256=unname(tools::sha256sum(file.path(output,name))),
          CPU_seconds=sum(timing[c(1,2,4,5)]),wall_seconds=unname(timing["elapsed"]),
          min_lookahead_ESS=min(vapply(fit$diagnostics,`[[`,numeric(1L),"lookahead_ESS")),
          minimum_selected_ancestors=min(vapply(fit$diagnostics,`[[`,integer(1L),"selected_ancestor_count")))
        write.csv(do.call(rbind,records),file.path(output,"training_H1_quantiles.csv"),row.names=FALSE)
        seal();rm(fit);gc(FALSE)
      }
    }
    comparisons <- list()
    pairs <- list(c(71521L,256L,71521L,1024L),c(71522L,256L,71522L,1024L),c(71521L,1024L,71522L,1024L))
    for(pair in pairs)for(t in checkpoints) {
      a <- quantiles[[paste(pair[1],pair[2],t,sep=":")]];b <- quantiles[[paste(pair[3],pair[4],t,sep=":")]]
      scale <- pmax(1,abs((a+b)/2));tol <- pmax(.005,.005*scale)
      comparisons[[length(comparisons)+1L]] <- data.frame(seed_A=pair[1],N_A=pair[2],seed_B=pair[3],N_B=pair[4],
        checkpoint=t,probability=probs,quantile_A=a,quantile_B=b,tolerance=tol,
        absolute_difference=abs(a-b),agreement=abs(a-b)<=tol)
    }
    comparisons <- do.call(rbind,comparisons);q(nrow(comparisons)==27L,"all27 predefined agreement rows required")
    write.csv(comparisons,file.path(output,"predeclared_quantile_agreements.csv"),row.names=FALSE)
    for(x in spec$source_files)ind_aq_pin(x)
    verify_source_blobs()
    for(k in c("training_input","native_forward_receipt","native_forward_manifest","bootstrap_receipt",
      "historical_guided_receipt","native_cpp"))ind_aq_pin(spec[[k]])
    ind_aq_pin(spec$original_fit,max_bytes=611287756);ind_aq_pin(spec$runtime_manifest)
    final_runtime <- ind_aq_runtime_inventory();ind_aq_runtime_match(runtime_manifest,final_runtime)
    write_json(list(role=attr(final_runtime,"observational_os_state_role"),
      observation_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
      observations=attr(final_runtime,"observational_os_state"),live_byte_equality_required=FALSE,
      numerical_inputs_and_software_remain_strictly_pinned=TRUE),"runtime_OS_identity_cache_after.json")
    q(expiry>Sys.time()&&identical(git(c("rev-parse","HEAD")),spec$source_commit)&&
      identical(git(c("rev-parse","HEAD^{tree}")),spec$source_tree)&&
      length(git(c("status","--porcelain","--untracked-files=normal")))==0L,"source/lifetime drift")
    restore()
    receipt <- list(schema_version="ind_ancestor_first_filter_qualification_receipt_v1",
      status="BOUNDED_AL_TRAINING_DIAGNOSTIC_COMPLETE_FILTER_ACCURACY_NOT_CERTIFIED",
      source_commit=spec$source_commit,source_tree=spec$source_tree,purpose_contract_sha256=args[4],
      method=spec$method,rng_namespace=spec$rng_namespace,rng_layout=spec$rng_layout,
      original_fit=spec$original_fit,original_fit_deserialized=FALSE,training_input=spec$training_input,
      posterior_column=1L,observed_prefix_length=500L,eta=eta,
      historical_guided_receipt=spec$historical_guided_receipt,historical_13of27_preserved=TRUE,
      predeclared_agreements=27L,agreements_passed=sum(comparisons$agreement),
      agreement_status=if(all(comparisons$agreement))"PASS_DESCRIPTIVE_AGREEMENT_ONLY"else"REVIEW",
      run_receipts=runs,one_parameter_only=TRUE,full_IF01_or_production_qualified=FALSE,
      runtime_manifest=spec$runtime_manifest,timeout_boundary=timeout,finite_limits=spec$limits,
      observational_OS_identity_cache_before=attr(runtime,"observational_os_state"),
      observational_OS_identity_cache_after=attr(final_runtime,"observational_os_state"),
      identity_cache_observation_role=attr(runtime,"observational_os_state_role"),
      administration_and_contract_reserve_bytes=reserve,caller_RNG_restored=TRUE,
      process_CPU_seconds_before_terminal_receipt=sum(proc.time()[c(1,2,4,5)]),
      process_wall_seconds_before_terminal_receipt=unname(proc.time()["elapsed"]),
      numerical_phase_CPU_seconds=sum((proc.time()-started)[c(1,2,4,5)]),
      main_entry_phase_CPU_seconds=sum((proc.time()-entered)[c(1,2,4,5)]),
      whole_purpose_terminal_supervisor_accounting_required=TRUE,
      filter_accuracy_certified=FALSE,future_integration_accuracy_certified=FALSE,
      outer_parameter_weights_updated=FALSE,future_truth_deserialized=FALSE,scoring_cases=0L,new_fits=0L,
      production_authorized=FALSE,article_promotion_authorized=FALSE)
    write_json(receipt,"qualification.json");progress("BOUNDED_DIAGNOSTIC_COMPLETE",agreement_status=receipt$agreement_status)
    seal();cat("IND_ANCESTOR_FIRST_BOUNDED_DIAGNOSTIC_COMPLETE_NOT_PRODUCTION\n")
    invisible(receipt)
  },error=function(e) {
    try(write_json(list(status="DIAGNOSTIC_FAILED_NOT_PRODUCTION",error=conditionMessage(e),
      source_commit=spec$source_commit,purpose_contract_sha256=args[4],production_authorized=FALSE),"failure.json"),silent=TRUE)
    try(progress("DIAGNOSTIC_FAILED_NOT_PRODUCTION",error=conditionMessage(e)),silent=TRUE)
    try(seal(),silent=TRUE);stop(e)
  })
}
if(sys.nframe()==0L)ind_aq_main()
