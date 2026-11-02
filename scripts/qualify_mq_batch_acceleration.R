#!/usr/bin/env Rscript
# One frozen MQ draw/origin: speed/parity plus independent-CDF qualification.
# No parameter fit, protected-truth score, production acceptance or publication.
source("scripts/qualify_integrated_quantile_forecast.R")
source("application/R/integrated_quantile_forecast.R")

mq_baq_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("MQ batch qualification: ", why), call. = FALSE)
  invisible(TRUE)
}

mq_baq_scope <- function(spec) {
  req <- mq_baq_require
  exact <- function(x, z) is.numeric(x) && length(x) == 1L && is.finite(x) && x == z
  req(is.list(spec) && identical(spec$schema_version, "mq_batch_acceleration_qualification_v1") &&
    identical(spec$allow_qualification, TRUE) && identical(spec$allow_refit, FALSE) &&
    identical(spec$allow_production, FALSE) && identical(spec$allow_scoring, FALSE) &&
    identical(spec$allow_article, FALSE), "qualification-only scope required")
  req(exact(spec$training_paths,4096) && exact(spec$validation_paths,32768) &&
    exact(spec$batch_size,128) && exact(spec$inversion_tolerance,1e-8) &&
    exact(spec$parity_absolute_tolerance,1e-10) && exact(spec$parity_relative_tolerance,1e-10) &&
    identical(spec$rng_backend,"r46_first_step"), "fixed prospective geometry, RNG backend and parity tolerances required")
  q2_geometry(spec$original_unit)
  a <- spec$original_unit$integration_accuracy
  req(exact(a$alpha_per_shard,.05) && exact(a$max_split_absolute,.005) &&
    exact(a$max_split_relative,.005) && exact(a$max_quantile_abs_error,.01) &&
    exact(a$max_quantile_rel_error,.01), "original numerical thresholds must remain unchanged")
  lim <- spec$limits
  req(is.list(lim) && exact(lim$cpu_seconds,600) && exact(lim$wall_term_seconds,899) &&
    exact(lim$wall_kill_after_seconds,1) && exact(lim$address_space_bytes,16*1024^3) &&
    exact(lim$output_bytes,256*1024^2), "fixed finite qualification budgets required")
  invisible(TRUE)
}

# Individual path CDFs, not their mean. This preserves flat segments and the
# native endpoint atoms and avoids millions of one-scalar helper calls.
mq_baq_cdf_rows <- function(y, q, tau) {
  req <- mq_baq_require; q <- as.matrix(q); B <- nrow(q); K <- length(tau)
  req(is.numeric(q) && B >= 1L && K >= 2L && ncol(q) == K && all(is.finite(q)) &&
    all(q[,-1L,drop=FALSE] >= q[,-K,drop=FALSE]) && is.numeric(y) && length(y) >= 1L &&
    !anyNA(y), "ordered path-specific MQ kernels and nonmissing CDF arguments required")
  app_iqf_grid(rep(0,K),tau)
  out <- matrix(0,B,length(y))
  for (jj in seq_along(y)) {
    index <- rowSums(q <= y[jj]); value <- as.numeric(index == K)
    rows <- which(index > 0L & index < K)
    if(length(rows)) {
      k <- index[rows]; lo <- q[cbind(rows,k)]; hi <- q[cbind(rows,k+1L)]
      value[rows] <- tau[k]+(tau[k+1L]-tau[k])*(y[jj]-lo)/(hi-lo)
    }
    req(all(is.finite(value)) && all(value >= 0 & value <= 1), "invalid native individual-path CDF value")
    out[,jj] <- value
  }
  out
}

mq_baq_main <- function(args = commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript scripts/qualify_mq_batch_acceleration.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  req <- mq_baq_require
  req(length(args)==5L && args[1L]=="--contract" && args[3L]=="--sha256" &&
    args[5L]=="--execute", "exact contract/hash/execute arguments required")
  cp <- normalizePath(args[2L],mustWork=TRUE); q2_regular(cp)
  req(file.info(cp)$size <= 1024^2 && identical(unname(tools::sha256sum(cp)),args[4L]),
    "bounded external purpose contract SHA mismatch")
  spec <- jsonlite::read_json(cp,simplifyVector=FALSE); mq_baq_scope(spec)
  root <- normalizePath(getwd(),mustWork=TRUE)
  req(!startsWith(cp,paste0(root,"/")),"purpose must be outside the source checkout")
  git <- function(a) {
    z <- system2("git",c("--no-replace-objects",a),stdout=TRUE)
    req(is.null(attr(z,"status")),"Git source identity check failed");unname(z)
  }
  req(identical(git(c("rev-parse","HEAD")),spec$source_commit) &&
    identical(git(c("rev-parse","HEAD^{tree}")),spec$source_tree) &&
    length(git(c("status","--porcelain","--untracked-files=normal")))==0L,
    "clean frozen source commit/tree required")
  expiry <- as.POSIXct(spec$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  req(!is.na(expiry) && expiry > Sys.time()+900 && as.character(getRversion())=="4.6.0",
    "pinned R and complete purpose lifetime required")
  req(unname(Sys.info()[["nodename"]]) %in% c("muscat","muscat.be.ucsc.edu") &&
    Sys.getenv("LD_PRELOAD")=="" && all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1"),
    "Muscat single-thread bundled runtime required")
  blas <- unname(extSoftVersion()[["BLAS"]])
  req(identical(normalizePath(blas,mustWork=TRUE),
    normalizePath(file.path(R.home("lib"),"libRblas.so"),mustWork=TRUE)),"bundled BLAS identity differs")
  q2_limits(list(logical_cpu=27L,max_cpu_seconds=600,max_memory_bytes=16*1024^3,
    max_output_bytes=256*1024^2,max_wall_seconds=900))
  pin <- function(x) {
    req(is.list(x) && is.character(x$path) && length(x$path)==1L &&
      is.numeric(x$size_bytes) && length(x$size_bytes)==1L && is.finite(x$size_bytes) &&
      x$size_bytes>=0 && is.character(x$sha256) && length(x$sha256)==1L &&
      grepl("^[a-f0-9]{64}$",x$sha256),"invalid pinned input schema")
    q2_regular(x$path)
    req(file.exists(x$path) && !isTRUE(file.info(x$path)$isdir) &&
      file.info(x$path)$size==x$size_bytes &&
      identical(unname(tools::sha256sum(x$path)),x$sha256),"pinned input/source bytes changed")
    x$path
  }
  req(is.list(spec$source_files) && length(spec$source_files)>=10L,
    "complete transitive source pins required")
  source_paths <- vapply(spec$source_files,pin,character(1L))
  required <- c("scripts/qualify_mq_batch_acceleration.R","scripts/qualify_integrated_quantile_forecast.R",
    "scripts/mq_independent_cdf_certificate.R","scripts/integrated_quantile_mq_batch.R",
    "application/R/integrated_quantile_forecast.R","application/R/00_packages.R",
    "application/R/joint_qvp_qdesn.R","application/R/latent_path_design.R",
    "application/R/joint_qdesn_pure_recursive_campaign.R","application/R/joint_qdesn_recursive_mean_design.R")
  req(all(startsWith(source_paths,paste0(root,"/"))) && !anyDuplicated(source_paths) &&
    all(file.path(root,required) %in% source_paths),"all executable helper paths must be pinned inside this checkout")
  manifest_path <- pin(spec$source_manifest)
  req(identical(manifest_path,file.path(root,"docs/reproducibility/integrated_forecast_transition_sources_20261031.csv")),
    "unchanged native source-manifest path required")
  manifest <- read.csv(manifest_path,stringsAsFactors=FALSE)
  req(all(c("path","sha256","mode","blob") %in% names(manifest)) &&
    !anyDuplicated(manifest$path) && all(file.path(root,manifest$path) %in% source_paths),
    "source pins must include every original transitive-manifest row")
  for(i in seq_len(nrow(manifest))) {
    path <- app_iqf_safe_path(root,manifest$path[i])
    req(identical(unname(tools::sha256sum(path)),manifest$sha256[i]),"original native helper hash differs")
    stage <- git(c("ls-files","--stage","--",shQuote(manifest$path[i])))
    req(length(stage)==1L && startsWith(stage,paste(manifest$mode[i],manifest$blob[i])),
      "original native helper Git mode/blob differs")
  }
  pin(spec$native_rng_source)
  req(identical(spec$native_rng_source$sha256,
    "6ef2c5d552c087cd57e0ef49386e01e0174b40433e4ad8d572461b20c958450e"),
    "exact R4.6 CMRG source identity required")
  original_path <- pin(spec$original_unit_contract)
  original <- jsonlite::read_json(original_path,simplifyVector=FALSE)
  q2_geometry(original)
  unchanged <- c("schema_version","purpose","source_schema","model_cell_id","chain_id","source_row",
    "source_draw_index","origin_id","origin_time","horizons","inner_paths","readout_slopes","tau",
    "rng_namespace","posterior_target_sha256","integration_accuracy")
  req(identical(spec$original_unit[unchanged],original[unchanged]),
    "original unit geometry, RNG namespace, target or thresholds changed")
  for(role in names(original$assets)) req(identical(spec$original_unit$assets[[role]][c("size_bytes","sha256")],
    original$assets[[role]][c("size_bytes","sha256")]),"original six asset sizes/hashes changed")
  metadata <- q2_metadata(spec$original_unit)
  req(!"exdqlm" %in% loadedNamespaces(),"installed package namespace substitution is not permitted")
  output <- spec$output_root
  req(is.character(output) && length(output)==1L && startsWith(output,paste0(root,"/local_trackers/")) &&
    !file.exists(output),"fresh ignored output root required")
  q2_regular(output); parent <- dirname(output)
  req(dir.exists(parent) && identical(normalizePath(parent,mustWork=TRUE),parent) &&
    system2("git",c("check-ignore","--quiet","--",shQuote(output)))==0L,
    "real precreated ignored output parent required")
  req(dir.create(output),"fresh output creation failed")
  write_json <- function(x,name) {
    target <- file.path(output,name);tmp <- paste0(target,".tmp")
    jsonlite::write_json(x,tmp,pretty=TRUE,auto_unbox=TRUE,digits=17,null="null")
    req(file.rename(tmp,target),"atomic receipt write failed")
  }
  progress <- function(phase,...) write_json(list(schema_version="mq_batch_qualification_progress_v1",
    phase=phase,timestamp_utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),
    source_commit=spec$source_commit,purpose_contract_sha256=args[4L],
    production_authorized=FALSE,details=list(...)),"progress.json")
  staged_bytes <- sum(metadata$size_bytes)+spec$original_unit_contract$size_bytes
  reserved_admin <- 1024^2
  seal_manifest <- function() {
    files <- list.files(output,full.names=TRUE)
    files <- files[basename(files)!="artifact_manifest.csv"]
    rows <- data.frame(relative_path=basename(files),size_bytes=unname(file.info(files)$size),
      sha256=unname(tools::sha256sum(files)))
    req(sum(rows$size_bytes)+staged_bytes+reserved_admin < spec$limits$output_bytes,
      "whole packet exceeds admitted artifact/input/administration budget")
    write.csv(rows,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
    invisible(rows)
  }
  save <- function(object,name) {
    path <- file.path(output,name);req(!file.exists(path),"qualification artifact already exists")
    saveRDS(object,path,compress=TRUE);seal_manifest();invisible(path)
  }
  rng <- function() list(kind=RNGkind(),present=exists(".Random.seed",.GlobalEnv,inherits=FALSE),
    seed=if(exists(".Random.seed",.GlobalEnv,inherits=FALSE)) get(".Random.seed",.GlobalEnv) else NULL)
  original_rng <- rng(); started <- proc.time()
  progress("ADMITTED_TRAINING_ONLY_PAYLOAD_LOAD")
  tryCatch({
    unit <- spec$original_unit
    raw_design <- readRDS(unit$assets$design$path); raw_fixture <- readRDS(unit$assets$fixture$path)
    raw_posterior <- read.csv(unit$assets$posterior$path,stringsAsFactors=FALSE)
    objects <- q2_payloads(raw_design,raw_fixture,raw_posterior,unit)
    rm(raw_design,raw_fixture,raw_posterior);gc(FALSE)
    # Only the observed prefix and retained parameters returned by q2_payloads
    # reach either adapter; held-out fixture responses have been discarded.
    for(file in c("00_packages.R","joint_qvp_qdesn.R","latent_path_design.R",
      "joint_qdesn_pure_recursive_campaign.R","joint_qdesn_recursive_mean_design.R"))
      source(file.path(root,"application/R",file))
    source(file.path(root,"scripts/integrated_quantile_mq_batch.R"))
    source(file.path(root,"scripts/mq_independent_cdf_certificate.R"))
    app_set_repo_root(root)
    tau <- as.numeric(unlist(unit$tau));H <- 30L;K <- length(tau)
    draw <- objects$posterior$draw_ids; origin <- as.character(unit$origin_id)
    coupling <- list(method="native_joint_posterior",
      recipe_sha256=app_iqf_hash(list(source=unit$assets$posterior$sha256,row=1L,method="native_joint_posterior")),
      draw_mapping_sha256=objects$posterior$draw_mapping_sha256)
    scalar <- app_iqf_desn_adapter(objects$design,objects$posterior,objects$origins,tau,
      "mq_grid",coupling,unit$rng_namespace)
    batch <- app_iqf_mq_batch_adapter(objects$design,objects$posterior,objects$origins,tau,
      coupling,unit$rng_namespace,inner_paths=spec$training_paths+spec$validation_paths,
      batch_size=spec$batch_size,rng_mode="r46_first_step_qualified",
      rng_proof=list(R_version="4.6.0",RNG_c_sha256=spec$native_rng_source$sha256))
    req(identical(scalar$coupling,batch$coupling) && identical(scalar$outer_conditioning,batch$outer_conditioning),
      "original posterior coupling or conditioning changed")
    run <- function(adapter) app_iqf_run_task(adapter,draw,origin,4096L,tau,unit$model_cell_id,
      tolerance=spec$inversion_tolerance,include_paths=TRUE,diagnose_integration=TRUE,
      mc_confidence_alpha=.05,max_kernel_bytes=8*1024^3)
    progress("SCALAR_REFERENCE_4096_RUNNING")
    t <- proc.time();sr <- run(scalar); scalar_time <- proc.time()-t
    req(identical(rng(),original_rng),"scalar calculation changed caller RNG state")
    progress("BATCH_TRAINING_4096_RUNNING")
    t <- proc.time();br <- run(batch); batch_time <- proc.time()-t
    req(identical(rng(),original_rng),"batch calculation changed caller RNG state")
    kernels <- function(result) {
      out <- array(NA_real_,c(4096L,K,H))
      for(h in seq_len(H)) out[,,h] <- do.call(rbind,lapply(result$cdf_components[[h]],`[[`,"q"))
      out
    }
    sq <- kernels(sr);bq <- kernels(br)
    compare <- function(a,b,label) {
      req(is.numeric(a) && is.numeric(b) && identical(dim(a),dim(b)) &&
        length(a)==length(b) && all(is.finite(c(a,b))),paste("malformed parity arrays",label))
      delta <- abs(a-b)
      req(all(delta<=spec$parity_absolute_tolerance+
        spec$parity_relative_tolerance*pmax(abs(a),abs(b))),paste("scalar/batch parity failed",label))
      list(field=label,values=length(a),maximum_absolute_difference=max(delta),
        maximum_scaled_difference=max(delta/pmax(1,abs(a),abs(b))),pass=TRUE)
    }
    parity <- list(compare(sr$paths,br$paths,"recursive_responses"),
      compare(sq,bq,"ordered_conditional_kernels"),
      compare(sr$quantiles$quantile,br$quantiles$quantile,"integrated_training_quantiles"))
    keys <- setdiff(names(sr$quantiles),"quantile")
    req(identical(sr$quantiles[keys],br$quantiles[keys]) &&
      identical(sr$original_draw,br$original_draw) && identical(sr$identity,br$identity) &&
      identical(sr$draw_id,br$draw_id) && identical(sr$origin_id,br$origin_id),
      "forecast identity, row keys or native posterior row changed")
    legacy_status <- q2_accuracy(sr,unit$integration_accuracy)
    req(identical(legacy_status,"REVIEW_INNER_INTEGRATION_RESOLUTION"),
      "historical frozen unit no longer reproduces its original numerical REVIEW")
    # Training candidates are frozen before any validation path is generated.
    candidates <- br$quantiles[,c("horizon","probability","quantile")]
    grid <- mq_icc_candidates(candidates,.01,.01)
    save(candidates,"frozen_training_candidates.rds")
    first_q <- as.numeric(bq[1L,,1L])
    req(all(abs(bq[,,1L]-matrix(rep(first_q,each=4096L),4096L,K))<=1e-10),
      "first-horizon kernels differ despite deterministic observed-prefix construction")
    first_time <- objects$origins[[origin]]$origin_time+1L
    req(all(first_time-seq_len(objects$design$response_lags)<=objects$origins[[origin]]$origin_time),
      "first-horizon lag features would use an unknown response")
    first_proof <- list(schema_version="mq_identical_first_kernel_source_proof_v1",horizon=1L,
      construction="deterministic_observed_prefix_no_future_response_in_first_features",
      all_first_path_kernels_identical_by_source=TRUE,source_commit=spec$source_commit,
      source_manifest_sha256=spec$source_manifest$sha256,posterior_target_sha256=unit$posterior_target_sha256,
      kernel_sha256=app_iqf_hash(list(family="mq_grid",q=first_q,tau=tau)),
      draw_id=draw,origin_id=origin)
    exact_h1 <- mq_icc_exact_first_horizon(first_q,tau,tau,first_proof)
    sr$cdf_components <- NULL;br$cdf_components <- NULL
    sr$ordered_kernel_array <- sq;br$ordered_kernel_array <- bq
    save(sr,"scalar_training_result.rds");save(br,"batch_training_result.rds")
    save(exact_h1,"structural_first_horizon_evidence.rds")
    rm(sr,br,sq,bq);gc(FALSE)
    validation_ids <- 4096L+seq_len(32768L)
    validation <- matrix(NA_real_,32768L,grid$endpoint_count,
      dimnames=list(NULL,grid$endpoints$endpoint_id))
    progress("INDEPENDENT_VALIDATION_RUNNING",completed_paths=0L,total_paths=32768L)
    t <- proc.time()
    starts <- seq.int(1L,32768L,by=128L)
    for(block in seq_along(starts)) {
      rows <- seq.int(starts[block],min(32768L,starts[block]+127L))
      paths <- app_iqf_mq_batch_paths(batch,draw,origin,validation_ids[rows])
      for(h in seq_len(H)) {
        at <- which(grid$endpoints$horizon==h)
        q <- matrix(paths$ordered_quantiles[,,h],length(rows),K)
        validation[rows,at] <- mq_baq_cdf_rows(grid$endpoints$y[at],q,tau)
      }
      req(identical(rng(),original_rng),"validation path generation changed caller RNG state")
      if(block %% 8L==0L || block==length(starts)) progress("INDEPENDENT_VALIDATION_RUNNING",
        completed_paths=max(rows),total_paths=32768L,elapsed_seconds=unname((proc.time()-t)["elapsed"]))
    }
    validation_time <- proc.time()-t
    cert_contract <- list(schema_version="mq_independent_cdf_certificate_contract_v1",
      method="heldout_conditional_CDF_empirical_Bernstein",
      conditioning="one_fixed_original_parameter_draw_and_observed_origin",
      validation_values="iid_future_path_conditional_CDF_not_particle_filter",
      candidates_from_training_paths_only=TRUE,rng_namespace=unit$rng_namespace,draw_id=draw,origin_id=origin,
      training_path_indices=1:4096,validation_path_indices=validation_ids,alpha=.05,
      absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01)
    certificate <- mq_icc_certify(candidates,validation,cert_contract)
    save(validation,"independent_validation_cdf_matrix.rds")
    save(certificate,"independent_cdf_certificate.rds")
    write.csv(certificate$endpoint_evidence,file.path(output,"independent_cdf_endpoint_evidence.csv"),row.names=FALSE)
    # Source and original bytes are rechecked after all calculations. The
    # separate exact-H1 receipt NEVER overrides an all-endpoint REVIEW.
    for(x in spec$source_files) pin(x)
    pin(spec$source_manifest);pin(spec$native_rng_source);pin(spec$original_unit_contract)
    q2_metadata(unit)
    req(identical(rng(),original_rng) && expiry>Sys.time() &&
      !"exdqlm" %in% loadedNamespaces() &&
      identical(git(c("rev-parse","HEAD")),spec$source_commit) &&
      identical(git(c("rev-parse","HEAD^{tree}")),spec$source_tree) &&
      length(git(c("status","--porcelain","--untracked-files=normal")))==0L,
      "source/runtime/RNG scope changed during probe")
    split_pass <- readRDS(file.path(output,"batch_training_result.rds"))$integration_diagnostic
    split_ok <- all(split_pass$split_stream_absolute_difference<=.005|
      split_pass$split_stream_relative_difference<=.005)
    status <- if(split_ok && all(certificate$result$pass))
      "PASS_PREDECLARED_BATCH_QUALIFICATION_ONLY" else "REVIEW_NUMERICAL_ACCURACY_NOT_QUALIFIED"
    receipt <- list(schema_version="mq_batch_acceleration_qualification_receipt_v1",
      status="QUALIFICATION_COMPLETE_NOT_PRODUCTION",numerical_status=status,
      source_commit=spec$source_commit,source_tree=spec$source_tree,purpose_contract_sha256=args[4L],
      original_unit_contract=spec$original_unit_contract,original_unit=unit,
      native_rng_source=spec$native_rng_source,rng_backend=spec$rng_backend,
      source_manifest=spec$source_manifest,original_row_mapping=objects$mapping,
      parity=parity,original_legacy_numerical_status=legacy_status,
      old_failure_receipts_preserved=TRUE,thresholds_loosened=FALSE,
      training_paths=4096L,validation_paths=32768L,horizons=30L,probabilities=tau,
      split_checks_pass=split_ok,independent_cdf_status=certificate$status,
      independent_cdf_passed=sum(certificate$result$pass),independent_cdf_total=nrow(certificate$result),
      structural_h1_separate_not_used_to_override_certificate=TRUE,
      scalar_CPU_seconds=sum(scalar_time[1:2]),scalar_wall_seconds=unname(scalar_time["elapsed"]),
      batch_CPU_seconds=sum(batch_time[1:2]),batch_wall_seconds=unname(batch_time["elapsed"]),
      validation_CPU_seconds=sum(validation_time[1:2]),validation_wall_seconds=unname(validation_time["elapsed"]),
      training_wall_speedup=unname(scalar_time["elapsed"])/unname(batch_time["elapsed"]),
      process_CPU_seconds=sum(proc.time()[1:2]),
      process_wall_seconds=unname(proc.time()["elapsed"]),
      numerical_phase_CPU_seconds=sum((proc.time()-started)[1:2]),
      numerical_phase_wall_seconds=unname((proc.time()-started)["elapsed"]),
      VmHWM=grep("^VmHWM:",readLines("/proc/self/status",warn=FALSE),value=TRUE),
      observational_future_truth_used=FALSE,parameter_refits=0L,score_evaluations=0L,
      full_campaign_enrollment=FALSE,particle_filter_accuracy_certified=FALSE,
      production_authorized=FALSE,article_promotion_authorized=FALSE,
      numerical_environment=list(R=as.character(getRversion()),BLAS=blas,logical_cpu=27L,
        digest=as.character(utils::packageVersion("digest")),
        jsonlite=as.character(utils::packageVersion("jsonlite")),
        OMP_NUM_THREADS=Sys.getenv("OMP_NUM_THREADS"),
        OPENBLAS_NUM_THREADS=Sys.getenv("OPENBLAS_NUM_THREADS"),
        MKL_NUM_THREADS=Sys.getenv("MKL_NUM_THREADS"),LD_PRELOAD=Sys.getenv("LD_PRELOAD")),
      finite_limits=spec$limits,staged_input_bytes=staged_bytes,administration_reserve_bytes=reserved_admin)
    write_json(receipt,"qualification.json")
    progress("QUALIFICATION_COMPLETE_NOT_PRODUCTION",numerical_status=status,
      independent_cdf_passed=sum(certificate$result$pass),independent_cdf_total=nrow(certificate$result))
    seal_manifest()
    cat("MQ_BATCH_QUALIFICATION_COMPLETE_NOT_PRODUCTION numerical_status=",status,
      " fits=0 scoring=0 production=FALSE\n",sep="")
    invisible(receipt)
  },error=function(e) {
    try(write_json(list(schema_version="mq_batch_qualification_failure_v1",status="QUALIFICATION_FAILED_NOT_PRODUCTION",
      source_commit=spec$source_commit,purpose_contract_sha256=args[4L],error=conditionMessage(e),
      production_authorized=FALSE),"failure.json"),silent=TRUE)
    try(progress("QUALIFICATION_FAILED_NOT_PRODUCTION",error=conditionMessage(e)),silent=TRUE)
    try(seal_manifest(),silent=TRUE)
    stop(e)
  })
}
if(sys.nframe()==0L) mq_baq_main()
