#!/usr/bin/env Rscript
# Bounded training-only guided-filter diagnostic; never a production certificate.
ind_gaf_qualify <- function(args = commandArgs(TRUE)) {
  if (identical(args,"--help")) {
    cat("Usage: Rscript scripts/qualify_ind_guided_filter.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  stopifnot(length(args)==5L,args[[1L]]=="--contract",args[[3L]]=="--sha256",args[[5L]]=="--execute")
  source("scripts/ind_guided_auxiliary_filter.R")
  require <- ind_cfr_require
  pin <- function(x) {
    require(is.list(x) && is.character(x$path) && length(x$path)==1L &&
      startsWith(x$path,"/") && !grepl("(^|/)\\.\\.(/|$)",x$path) &&
      file.exists(x$path) && !isTRUE(file.info(x$path)$isdir) &&
      identical(unname(Sys.readlink(x$path)),"") &&
      identical(normalizePath(x$path,mustWork=TRUE),x$path) &&
      identical(as.numeric(file.info(x$path)$size),as.numeric(x$size_bytes)) &&
      is.character(x$sha256) && length(x$sha256)==1L && grepl("^[a-f0-9]{64}$",x$sha256) &&
      identical(unname(tools::sha256sum(x$path)),x$sha256),"exact guided input/source binding")
    x$path
  }
  contract_path <- normalizePath(args[[2L]],mustWork=TRUE)
  require(file.info(contract_path)$size<=1024^2 &&
    identical(unname(tools::sha256sum(contract_path)),args[[4L]]),"bounded external guided purpose contract")
  spec <- jsonlite::read_json(contract_path,simplifyVector=FALSE)
  exact <- function(x,expected) {
    z <- unlist(x,use.names=FALSE)
    is.numeric(z) && length(z)==length(expected) && all(is.finite(z)) && all(z==expected)
  }
  require(identical(spec$schema_version,"ind_guided_filter_qualification_v1") &&
    identical(spec$allow_qualification,TRUE) && identical(spec$allow_refit,FALSE) &&
    identical(spec$allow_production,FALSE) && identical(spec$allow_scoring,FALSE) &&
    identical(spec$allow_article_promotion,FALSE) &&
    identical(spec$allow_training_only_h1_diagnostics,TRUE) &&
    identical(spec$posterior_column,1L) && identical(spec$observed_prefix_length,500L) &&
    exact(spec$particle_resolutions,c(64L,256L,1024L)) &&
    exact(spec$seeds,c(71521L,71522L)) && exact(spec$checkpoint_indices,c(100L,250L,500L)) &&
    exact(spec$probabilities,c(.05,.5,.95)) && identical(spec$ess_fraction,.5) &&
    identical(spec$inversion_absolute_tolerance,1e-8) &&
    identical(spec$agreement_absolute_tolerance,.005) &&
    identical(spec$agreement_relative_tolerance,.005),"fixed prospective guided training-only diagnostic")
  require(is.list(spec$limits) && identical(spec$limits$cpu_seconds,1200L) &&
    identical(spec$limits$wall_term_seconds,1199L) && identical(spec$limits$wall_kill_after_seconds,1L) &&
    spec$limits$address_space_bytes==16*1024^3 && spec$limits$output_bytes==96*1024^2,
    "unchanged externally enforced finite guided limits")
  root <- normalizePath(getwd(),mustWork=TRUE)
  require(!startsWith(contract_path,paste0(root,"/")),"guided purpose contract must be outside source")
  git <- function(a) {
    z <- system2("git",c("--no-replace-objects",a),stdout=TRUE)
    require(is.null(attr(z,"status")),"guided Git identity check failed");unname(z)
  }
  require(identical(git(c("rev-parse","HEAD")),spec$source_commit) &&
    length(git(c("status","--porcelain","--untracked-files=normal")))==0L,
    "clean frozen guided qualification source")
  expiry <- as.POSIXct(spec$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  require(!is.na(expiry) && expiry>Sys.time()+1200 && as.character(getRversion())=="4.6.0",
    "pinned R and complete bounded guided lifetime")
  require(unname(Sys.info()[["nodename"]]) %in% c("muscat","muscat.be.ucsc.edu") &&
    identical(Sys.getenv("LD_PRELOAD"),"") &&
    all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1"),
    "local one-thread bundled guided environment")
  blas <- unname(extSoftVersion()[["BLAS"]])
  require(is.character(blas) && length(blas)==1L &&
    identical(normalizePath(blas,mustWork=TRUE),
      normalizePath(file.path(R.home("lib"),"libRblas.so"),mustWork=TRUE)),
    "guided diagnostic requires R's bundled BLAS")
  status <- readLines("/proc/self/status",warn=FALSE)
  affinity <- trimws(sub("^Cpus_allowed_list:","",grep("^Cpus_allowed_list:",status,value=TRUE)))
  require(identical(affinity,"26"),"guided diagnostic requires separate administrative CPU26")
  limits <- readLines("/proc/self/limits",warn=FALSE)
  finite_limit <- function(prefix,ceiling) {
    row <- grep(paste0("^",prefix),limits,value=TRUE)
    if(length(row)!=1L)return(FALSE)
    x <- suppressWarnings(as.numeric(strsplit(trimws(sub(paste0("^",prefix),"",row)),"[[:space:]]+")[[1L]][1:2]))
    all(is.finite(x) & x>0 & x<=ceiling)
  }
  require(finite_limit("Max cpu time",1200) && finite_limit("Max address space",16*1024^3) &&
    finite_limit("Max file size",96*1024^2),"finite guided process limits")
  require(is.list(spec$source_files) && length(spec$source_files)>=5L,
    "complete guided executable source pins required")
  source_paths <- vapply(spec$source_files,pin,character(1L))
  required_sources <- file.path(root,c("scripts/qualify_ind_guided_filter.R",
    "scripts/ind_conditional_filter_replay.R","scripts/ind_conditional_auxiliary_filter.R",
    "scripts/ind_guided_auxiliary_primitives.R","scripts/ind_guided_auxiliary_filter.R"))
  require(all(startsWith(source_paths,paste0(root,"/"))) && all(required_sources %in% source_paths) &&
    !anyDuplicated(source_paths),"guided CLI and all transitive kernels must be pinned")
  require(spec$native_cpp$sha256==ind_cfr_policy()$source_sha256,"authentic native covariance policy required")
  require(!"exdqlm" %in% loadedNamespaces(),"installed package namespace substitution is forbidden")
  output <- spec$output_root
  require(is.character(output) && length(output)==1L && startsWith(output,paste0(root,"/local_trackers/")) &&
    !file.exists(output) && !grepl("(^|/)\\.\\.(/|$)",output),"fresh ignored guided output namespace required")
  parent <- dirname(output)
  require(dir.exists(parent) && identical(normalizePath(parent,mustWork=TRUE),parent),
    "precreated real guided output parent required")
  require(identical(system2("git",c("check-ignore","--quiet","--",shQuote(output))),0L),
    "guided artifacts must remain ignored by Git")
  require(dir.create(output),"fresh guided output creation failed")
  write_json <- function(value,name) {
    target <- file.path(output,name);temporary <- paste0(target,".tmp")
    jsonlite::write_json(value,temporary,pretty=TRUE,auto_unbox=TRUE,digits=17,null="null")
    require(file.rename(temporary,target),"atomic guided receipt write")
  }
  progress <- function(phase,...)write_json(list(schema_version="ind_guided_qualification_progress_v1",
    phase=phase,timestamp_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
    source_commit=spec$source_commit,purpose_contract_sha256=args[[4L]],production_authorized=FALSE,
    details=list(...)),"progress.json")
  manifest <- function() {
    files <- list.files(output,full.names=TRUE);files <- files[basename(files)!="artifact_manifest.csv"]
    rows <- data.frame(relative_path=basename(files),size_bytes=unname(file.info(files)$size),
      sha256=unname(tools::sha256sum(files)))
    require(sum(rows$size_bytes)<96*1024^2-65536,"guided packet budget including manifest reserve")
    write.csv(rows,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
    require(sum(file.info(list.files(output,full.names=TRUE))$size)<=96*1024^2,"complete guided packet budget")
  }
  had_seed <- exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE)
  old_seed <- if(had_seed)get(".Random.seed",envir=.GlobalEnv)else NULL
  old_kind <- RNGkind()
  on.exit({
    do.call(RNGkind,as.list(old_kind))
    if(had_seed)assign(".Random.seed",old_seed,envir=.GlobalEnv)
    else if(exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)
  },add=TRUE)
  progress("GUIDED_DIAGNOSTIC_ADMITTED_INPUT_VERIFICATION")
  tryCatch({
    pin(spec$original_fit);pin(spec$native_cpp)
    native <- jsonlite::read_json(pin(spec$native_forward_receipt),simplifyVector=FALSE)
    old <- jsonlite::read_json(pin(spec$bootstrap_receipt),simplifyVector=FALSE)
    input_path <- pin(spec$training_input)
    prior_manifest <- read.csv(pin(spec$native_forward_manifest),colClasses="character")
    require(all(c("relative_path","size_bytes","sha256") %in% names(prior_manifest)) &&
      !anyDuplicated(prior_manifest$relative_path),"original conditional replay manifest structure")
    for(binding in list(spec$training_input,spec$native_forward_receipt)) {
      row <- prior_manifest[prior_manifest$relative_path==basename(binding$path),,drop=FALSE]
      require(nrow(row)==1L && as.numeric(row$size_bytes)==binding$size_bytes && row$sha256==binding$sha256,
        "training input and native receipt must match original parity manifest")
    }
    same_fit <- function(x)identical(x$path,spec$original_fit$path) &&
      x$size_bytes==spec$original_fit$size_bytes && identical(x$sha256,spec$original_fit$sha256)
    c72 <- "c72e19f345da88fc1a8175ed30bdde328eab88be"
    require(identical(native$schema_version,"ind_native_forward_qualification_receipt_v1") &&
      identical(native$status,"NATIVE_FORWARD_PARITY_PASS") &&
      identical(old$schema_version,"ind_auxiliary_filter_qualification_receipt_v1") &&
      identical(old$status,"QUALIFICATION_PROBE_COMPLETE_ACCURACY_NOT_CERTIFIED") &&
      same_fit(native$original_fit) && same_fit(old$original_fit) &&
      identical(native$original_fit_source,c72) && identical(old$original_fit_source,c72) &&
      native$original_native_posterior_column==1L && old$original_native_posterior_column==1L &&
      native$native_posterior_columns_present==20000L && old$native_posterior_columns_present==20000L &&
      native$observed_training_rows==500L && old$training_rows==500L &&
      identical(old$likelihood,"AL") && old$p0==.05 && is.finite(old$sigma) && old$sigma>0 &&
      identical(native$native_cpp$sha256,spec$native_cpp$sha256) &&
      identical(old$native_cpp$sha256,spec$native_cpp$sha256),
      "both authentic receipts must bind the same original AL training parameter")
    # The full protected fit is HASHED ONLY. Only the 13-KiB training input is
    # read; the original large RDS and any held-out values never enter this R process.
    input <- readRDS(input_path);n <- spec$observed_prefix_length;p <- length(input$m0)
    require(is.list(input) && input$observed_prefix_length==n && length(input$y)==n &&
      identical(dim(input$FF),c(p,n)) && all(is.finite(c(input$y,input$FF,input$m0))) &&
      (identical(dim(input$GG),c(p,p)) || identical(dim(input$GG),c(p,p,n))),
      "original training-only input geometry")
    eta <- list(family="al",p=old$p0,sigma=old$sigma,gamma=0)
    ind_gaf_eta(eta)
    B <- 2/(eta$p*(1-eta$p));A <- (1-2*eta$p)/(eta$p*(1-eta$p))
    paired_v <- input$ex_q/(B*eta$sigma)
    require(length(paired_v)==n && all(is.finite(paired_v)) && all(paired_v>0) &&
      length(input$ex_f)==n && all(abs(input$ex_f-A*paired_v)<=1e-12*pmax(1,abs(input$ex_f))),
      "native scale/level do not match authenticated conditional replay input")
    GG <- if(is.matrix(input$GG))array(rep(input$GG,n),c(p,p,n))else input$GG
    constant_F <- identical(as.numeric(input$FF),as.numeric(matrix(rep(input$FF[,1L],n),p,n)))
    constant_G <- all(vapply(seq_len(n),function(t)identical(matrix(GG[,,t],p,p),matrix(GG[,,1L],p,p)),logical(1L)))
    require(constant_F && constant_G,"endpoint H1 diagnostic requires exactly constant original F/G through all500 rows")
    checkpoints <- as.integer(unlist(spec$checkpoint_indices));resolutions <- as.integer(unlist(spec$particle_resolutions))
    seeds <- as.integer(unlist(spec$seeds));probs <- as.numeric(unlist(spec$probabilities));maxN <- max(resolutions)
    parameter_id <- paste0(c72,":native_column:1")
    rows <- list();runs <- list();quantile_records <- list();streams <- list();row_id <- 0L
    RNGkind("Mersenne-Twister","Inversion","Rejection")
    progress("GUIDED_TRAINING_INPUT_AUTHENTICATED",training_rows=n,states=p,static_parameter_id=parameter_id)
    for(seed in seeds) {
      set.seed(seed);rng_before <- .Random.seed
      # time major; four independent supplied channels, smallerN uses the same
      # firstN rows of every time/channel, never a fresh resolution-specificseed.
      proposal <- array(stats::runif(maxN*n*4L),c(maxN,n,4L));resampling <- stats::runif(n)
      rng_after <- .Random.seed
      uniforms <- list(proposal=proposal,resampling=resampling)
      stream_name <- sprintf("guided_uniform_stream_seed_%d.rds",seed)
      saveRDS(list(seed=seed,RNGkind=RNGkind(),uniforms=uniforms,
        order="time_major_maximum_particle_rows_with_four_separate_channels",
        RNGstate_before=rng_before,RNGstate_after=rng_after),file.path(output,stream_name))
      streams[[as.character(seed)]] <- list(seed=seed,file=stream_name,
        scientific_uniform_count=maxN*n*4L+n,sha256=unname(tools::sha256sum(file.path(output,stream_name))))
      for(N in resolutions) {
        key <- sprintf("seed_%d_particles_%04d",seed,N)
        progress("GUIDED_FILTER_RUNNING",seed=seed,particles=N,completed_runs=length(runs),total_runs=6L)
        start <- proc.time()
        fit <- ind_gaf_filter(input$y,input$FF,input$GG,input$m0,input$C0,input$df_mat,eta,
          list(proposal=proposal[seq_len(N),,,drop=FALSE],resampling=resampling),n,parameter_id,
          checkpoints,ess_fraction=spec$ess_fraction)
        timing <- proc.time()-start
        require(identical(.Random.seed,rng_after),"guided filter mutated supplied scientific RNG stream")
        moments <- h1 <- list()
        for(origin in checkpoints) {
          cp <- fit$checkpoints[[as.character(origin)]]
          w <- cp$weights;mu <- as.numeric(cp$mean%*%w);centered <- cp$mean-mu;cov <- matrix(0,p,p)
          for(j in seq_along(w))cov <- cov+w[j]*(matrix(cp$covariance[,,j],p,p)+tcrossprod(centered[,j]))
          ind_caf_psd(cov,p,1e-10,"guided checkpoint total mixture covariance")
          next_index <- if(origin<n)origin+1L else n
          comp <- ind_gaf_origin_components(cp,input$FF[,next_index],matrix(GG[,,next_index],p,p),
            input$df_mat,"known_deterministic")
          qi <- ind_gap_mixture_quantile(probs,comp$mean,comp$variance,eta$p,eta$sigma,comp$weight,
            spec$inversion_absolute_tolerance,0)
          moments[[as.character(origin)]] <- list(observed_prefix_length=origin,mean=mu,covariance=cov,
            covariance_includes_within_and_between_components=TRUE)
          h1[[as.character(origin)]] <- list(origin=origin,feature_row_used=next_index,
            endpoint_extension=origin==n,constant_original_FG_verified=TRUE,quantile=qi,
            future_response_or_scoring_value_used=FALSE)
          qkey <- paste(seed,N,origin,sep=":");quantile_records[[qkey]] <- qi$result$quantile
          row_id <- row_id+1L
          rows[[row_id]] <- data.frame(seed=seed,particles=N,observed_prefix_length=origin,
            filter_CPU_seconds=sum(timing[1:2]),filter_elapsed_seconds=unname(timing[["elapsed"]]),
            minimum_ESS=min(fit$ESS),median_ESS=stats::median(fit$ESS),resampling_count=sum(fit$resampled),
            log_weight_underflow_count=sum(fit$log_weight_underflow_count),
            quantile_p005=qi$result$quantile[1L],quantile_p050=qi$result$quantile[2L],
            quantile_p095=qi$result$quantile[3L],weighted_mean=paste(sprintf("%.17g",mu),collapse=";"),
            total_covariance_column_major=paste(sprintf("%.17g",as.numeric(cov)),collapse=";"),
            filter_accuracy_certified=FALSE,production_authorized=FALSE)
        }
        fit$qualification_summary <- list(seed=seed,particles=N,
          filter_CPU_seconds=sum(timing[1:2]),filter_elapsed_seconds=unname(timing[["elapsed"]]),
          checkpoint_mixture_moments=moments,training_only_h1_diagnostics=h1)
        name <- paste0("guided_filter_",key,".rds");saveRDS(fit,file.path(output,name))
        runs[[key]] <- list(seed=seed,particles=N,file=name,
          sha256=unname(tools::sha256sum(file.path(output,name))),filter_CPU_seconds=sum(timing[1:2]),
          filter_elapsed_seconds=unname(timing[["elapsed"]]),minimum_ESS=min(fit$ESS),
          median_ESS=stats::median(fit$ESS),resampling_count=sum(fit$resampled),
          log_weight_underflow_count=sum(fit$log_weight_underflow_count))
        write.csv(do.call(rbind,rows),file.path(output,"guided_filter_probe_summary.csv"),row.names=FALSE)
        progress("GUIDED_FILTER_COMPLETE",seed=seed,particles=N,completed_runs=length(runs),total_runs=6L)
        manifest();rm(fit);gc(FALSE)
      }
    }
    comparisons <- list();ci <- 0L
    compare <- function(seedA,particlesA,seedB,particlesB,label) {
      for(origin in checkpoints) {
        qa <- quantile_records[[paste(seedA,particlesA,origin,sep=":")]]
        qb <- quantile_records[[paste(seedB,particlesB,origin,sep=":")]]
        for(k in seq_along(probs)) {
          scale <- max(1,abs((qa[k]+qb[k])/2))
          tolerance <- max(spec$agreement_absolute_tolerance,spec$agreement_relative_tolerance*scale)
          ci <<- ci+1L
          comparisons[[ci]] <<- data.frame(comparison=label,seed_A=seedA,particles_A=particlesA,
            seed_B=seedB,particles_B=particlesB,observed_prefix_length=origin,probability=probs[k],
            quantile_A=qa[k],quantile_B=qb[k],absolute_difference=abs(qa[k]-qb[k]),
            scale=scale,tolerance=tolerance,agreement=abs(qa[k]-qb[k])<=tolerance,
            role="prospective_descriptive_agreement_not_filter_accuracy_certificate")
        }
      }
    }
    for(seed in seeds)compare(seed,256L,seed,1024L,"within_seed_256_vs_1024")
    compare(seeds[1L],1024L,seeds[2L],1024L,"between_seeds_at_1024")
    comparisons <- do.call(rbind,comparisons)
    require(nrow(comparisons)==27L,"complete predeclared guided comparison keys")
    write.csv(comparisons,file.path(output,"guided_predictive_quantile_agreement.csv"),row.names=FALSE)
    for(x in spec$source_files)pin(x)
    for(x in list(spec$original_fit,spec$native_cpp,spec$training_input,spec$native_forward_receipt,
      spec$native_forward_manifest,spec$bootstrap_receipt))pin(x)
    require(!"exdqlm" %in% loadedNamespaces() && expiry>Sys.time(),"guided diagnostic stayed within source/runtime lifetime")
    receipt <- list(schema_version="ind_guided_filter_qualification_receipt_v1",
      status="QUALIFICATION_PROBE_COMPLETE_FILTER_ACCURACY_NOT_CERTIFIED",
      descriptive_agreement_status=if(all(comparisons$agreement))"PASS"else"REVIEW",
      descriptive_agreement_rows=nrow(comparisons),descriptive_agreement_passes=sum(comparisons$agreement),
      agreement_role="prospectively_fixed_absolute_OR_relative_quantile_agreement_not_error_bound",
      agreement_absolute_tolerance=spec$agreement_absolute_tolerance,
      agreement_relative_tolerance=spec$agreement_relative_tolerance,
      source_commit=spec$source_commit,purpose_contract_sha256=args[[4L]],original_fit=spec$original_fit,
      original_fit_read=FALSE,native_cpp=spec$native_cpp,training_input=spec$training_input,
      native_forward_receipt=spec$native_forward_receipt,bootstrap_receipt=spec$bootstrap_receipt,
      original_native_posterior_column=1L,training_rows=n,states=p,parameter_id=parameter_id,eta=eta,
      particle_resolutions=resolutions,seeds=seeds,checkpoints=checkpoints,probabilities=probs,
      filter_probes=runs,random_streams=streams,scientific_uniform_draw_count=length(seeds)*(maxN*n*4L+n),
      caller_RNG_restored_on_exit=TRUE,constant_original_FG_verified=TRUE,
      training_only_h1_diagnostic_cases=18L,current_future_auxiliary_integration="exact_Normal_AL_convolution",
      future_response_values_used=0L,held_out_scoring_cases=0L,new_parameter_fits=0L,
      parameter_weights_updated=FALSE,filter_accuracy_certified=FALSE,forecast_accuracy_certified=FALSE,
      production_authorized=FALSE,article_promotion_authorized=FALSE,finite_external_limits=spec$limits,
      numerical_environment=list(R=as.character(getRversion()),BLAS=blas,logical_cpus=affinity,
        LD_PRELOAD=Sys.getenv("LD_PRELOAD"),threads=1L),
      scope="one_retained_AL_parameter_training_filter_H1_diagnostic_not_complete_reconstruction")
    write_json(receipt,"qualification.json")
    progress("QUALIFICATION_PROBE_COMPLETE_FILTER_ACCURACY_NOT_CERTIFIED",completed_runs=length(runs),
      agreement_status=receipt$descriptive_agreement_status)
    manifest()
    cat(sprintf("QUALIFICATION_PROBE_COMPLETE_FILTER_ACCURACY_NOT_CERTIFIED runs=6 agreement=%s/%d production=FALSE\n",
      sum(comparisons$agreement),nrow(comparisons)))
    invisible(receipt)
  },error=function(e) {
    try(write_json(list(schema_version="ind_guided_filter_qualification_failure_v1",
      status="GUIDED_QUALIFICATION_FAILED_NOT_PRODUCTION",error=conditionMessage(e),
      source_commit=spec$source_commit,purpose_contract_sha256=args[[4L]],production_authorized=FALSE,
      filter_accuracy_certified=FALSE),"failure.json"),silent=TRUE)
    try(progress("GUIDED_QUALIFICATION_FAILED_NOT_PRODUCTION",error=conditionMessage(e)),silent=TRUE)
    try(manifest(),silent=TRUE)
    stop(e)
  })
}
if(sys.nframe()==0L)ind_gaf_qualify()
