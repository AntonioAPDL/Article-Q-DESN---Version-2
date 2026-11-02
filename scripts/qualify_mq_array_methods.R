#!/usr/bin/env Rscript
# A new, genuine one-unit numerical experiment. No old purpose is executable
# here; no raw fixture or raw design is deserialized, no model is fitted/scored.
source("scripts/mq_array_qualification.R",local=TRUE)
mqa_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript --vanilla scripts/qualify_mq_array_methods.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  q <- mqa_require
  q(length(args)==5L&&identical(args[c(1,3,5)],c("--contract","--sha256","--execute")),
    "exact external contract/hash/execute arguments required")
  for(p in c("digest","jsonlite","tools","compiler"))q(requireNamespace(p,quietly=TRUE),paste("required package",p))
  cp <- normalizePath(args[2L],mustWork=TRUE);q2_regular(cp)
  q(file.info(cp)$size<=1024^2&&identical(unname(tools::sha256sum(cp)),args[4L]),"external purpose bytes differ")
  s <- jsonlite::read_json(cp,simplifyVector=FALSE);mqa_scope(s)
  root <- normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(cp,paste0(root,"/")),"purpose must be outside source checkout")
  expiry <- q2_time(s$expires_utc)
  q(!is.na(expiry)&&expiry>Sys.time()+1800,"purpose must cover the entire bounded experiment")
  runtime <- mqa_runtime_guard(s)
  source_check <- mqa_source_guard(s,root)
  historical <- mqa_history_bridge(s,root)
  original <- jsonlite::read_json(mqa_pin(s$original_unit_contract,1024^2),simplifyVector=FALSE)
  q(mqa_metadata_equal(s$original_unit,original),"exact immutable original unit including asset identities required")
  metadata <- q2_metadata(s$original_unit) # Streaming hashes and parameter-only CSV metadata; never readRDS.
  q(!"exdqlm"%in%loadedNamespaces(),"installed engine substitution forbidden")
  # A missing authentic observed prefix is a hard gate, not metadata success.
  prepared <- mqa_verify_prepared(s,root)
  output <- s$output_root;q2_regular(output)
  q(is.character(output)&&length(output)==1L&&startsWith(output,paste0(root,"/local_trackers/"))&&
    !file.exists(output)&&dir.exists(dirname(output))&&
    identical(normalizePath(dirname(output),mustWork=TRUE),dirname(output))&&
    system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(output)))==0L,"fresh ignored real output parent required")
  q(dir.create(output),"fresh output creation failed")
  administrative_reserve <- 1024^2;initial_rng <- mqa_rng();phase <- "ADMITTED_TRUTH_FREE_PREPARED_PAYLOAD"
  write_json <- function(x,name) {
    p <- file.path(output,name);tmp <- paste0(p,".tmp")
    jsonlite::write_json(x,tmp,pretty=TRUE,auto_unbox=TRUE,digits=17,null="null")
    q(file.rename(tmp,p),"atomic receipt write failed")
  }
  progress <- function(name,...) {
    phase <<- name
    write_json(list(schema_version="mq_array_qualification_progress_v1",phase=name,
      utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),source_commit=s$source_commit,
      purpose_contract_sha256=args[4L],production_authorized=FALSE,details=list(...)),"progress.json")
  }
  seal <- function() {
    p <- list.files(output,full.names=TRUE,all.files=TRUE,no..=TRUE)
    q(all(!dir.exists(p))&&all(!nzchar(Sys.readlink(p))),"only direct regular qualification files permitted")
    p <- p[basename(p)!="artifact_manifest.csv"]
    m <- data.frame(relative_path=basename(p),size_bytes=as.numeric(file.info(p)$size),
      sha256=unname(tools::sha256sum(p)))
    q(sum(m$size_bytes)+prepared$prepared_bytes+administrative_reserve<s$limits$output_bytes,
      "complete output/prepared-input/administration budget exceeded")
    write.csv(m,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
    invisible(m)
  }
  save <- function(x,name) {
    p <- file.path(output,name);q(!file.exists(p),"qualified evidence overwrite forbidden")
    used <- sum(file.info(list.files(output,full.names=TRUE,all.files=TRUE,no..=TRUE))$size)+
      prepared$prepared_bytes+administrative_reserve
    q2_write(x,p,used,s$limits$output_bytes);seal();invisible(p)
  }
  started <- proc.time()
  tryCatch({
    progress(phase)
    env <- new.env(parent=.GlobalEnv)
    files <- c("application/R/00_packages.R","application/R/joint_qvp_qdesn.R",
      "application/R/latent_path_design.R","application/R/joint_qdesn_pure_recursive_campaign.R",
      "application/R/joint_qdesn_recursive_mean_design.R","application/R/integrated_quantile_forecast.R",
      "scripts/integrated_quantile_mq_batch.R","scripts/mq_forecast_array_methods.R",
      "scripts/mq_independent_cdf_certificate.R","scripts/mq_streaming_cdf_certificate.R")
    for(f in files)source(file.path(root,f),local=env)
    env$app_set_repo_root(root)
    old <- new.env(parent=env)
    eval(parse(text=rawToChar(historical$old_batch_raw)),envir=old)
    historical$old_batch_raw <- NULL
    write_json(historical,"historical_source_bridge.json")
    o <- prepared$objects;unit <- s$original_unit;tau <- as.numeric(unlist(unit$tau));H <- 30L;K <- 7L
    draw <- o$posterior$draw_ids;origin <- "1"
    coupling <- list(method="native_joint_posterior",
      recipe_sha256=mqa_hash(list(source=unit$assets$posterior$sha256,row=1L,method="native_joint_posterior")),
      draw_mapping_sha256=o$posterior$draw_mapping_sha256)
    scalar <- env$app_iqf_desn_adapter(o$design,o$posterior,o$origins,tau,"mq_grid",coupling,unit$rng_namespace)
    arguments <- list(design=o$design,posterior=o$posterior,origins=o$origins,tau=tau,coupling=coupling,
      rng_namespace=unit$rng_namespace,inner_paths=327680L,batch_size=128L,
      rng_mode="r46_first_step_qualified",rng_proof=list(R_version="4.6.0",RNG_c_sha256=s$native_rng_source$sha256))
    batch <- do.call(env$app_iqf_mq_batch_adapter,arguments)
    old_batch <- do.call(old$app_iqf_mq_batch_adapter,arguments)
    q(identical(scalar$coupling,batch$coupling)&&identical(old_batch$coupling,batch$coupling)&&
      identical(scalar$outer_conditioning,batch$outer_conditioning),"native coupling or conditional target changed")
    check_parity <- function(ids,role) {
      current <- env$app_iqf_mq_batch_arrays(batch,draw,origin,ids,include_trace=TRUE)
      legacy <- old$app_iqf_mq_batch_paths(old_batch,draw,origin,ids,include_trace=TRUE)
      maximum <- 0
      compare <- function(a,b) {
        q(is.numeric(a)&&is.numeric(b)&&identical(dim(a),dim(b))&&length(a)==length(b)&&
          all(is.finite(c(a,b))),"malformed semantic parity values")
        d <- abs(a-b);maximum <<- max(maximum,d)
        q(all(d<=1e-10+1e-10*pmax(abs(a),abs(b))),"native/archived-batch/new-array parity failed")
      }
      compare(current$response,legacy$response);compare(current$ordered_quantiles,legacy$ordered_quantiles)
      for(h in 1:H)for(key in c("raw","scaled","readout","raw_quantiles","ordered_quantiles","uniform"))
        compare(current$trace[[h]][[key]],legacy$trace[[h]][[key]])
      for(h in 1:H)for(d in seq_along(current$trace[[h]]$states))
        compare(current$trace[[h]]$states[[d]],legacy$trace[[h]]$states[[d]])
      for(i in seq_along(ids)) {
        p <- scalar$path(draw,origin,ids[i]);compare(p$response,current$response[i,])
        compare(do.call(rbind,lapply(p$kernels,`[[`,"q")),t(matrix(current$ordered_quantiles[i,,],K,H)))
      }
      q(identical(mqa_rng(),initial_rng),"parity changed scientific caller RNG state")
      list(role=role,path_ids=ids,horizons=H,maximum_absolute_difference=maximum,pass=TRUE,
        references=c("unchanged_native_scalar","authenticated_archived_batch_git_blob","new_array_source"))
    }
    progress("PREDECLARED_TRAINING_PARITY")
    parity <- list(training=check_parity(mqa_parity_ids(s,FALSE,FALSE),"training_before_candidate_freeze"),validation=NULL)
    save(parity,"training_parity.rds")
    N <- 65536L;ordered <- array(NA_real_,c(N,K,H));responses <- matrix(NA_real_,N,H);coherence <- NULL
    t <- proc.time();progress("ARRAY_TRAINING",completed_paths=0L)
    for(first in seq.int(1L,N,by=128L)) {
      ids <- seq.int(first,min(N,first+127L));p <- env$app_iqf_mq_batch_arrays(batch,draw,origin,ids)
      ordered[ids,,] <- p$ordered_quantiles;responses[ids,] <- p$response
      coherence <- if(is.null(coherence))p$raw_coherence else env$mq_coherence_merge(list(coherence,p$raw_coherence))
      q(identical(mqa_rng(),initial_rng),"training changed scientific caller RNG")
      if(max(ids)%%1024L==0L)progress("ARRAY_TRAINING",completed_paths=max(ids))
    }
    training_time <- proc.time()-t
    save(list(schema_version="mq_array_qualification_training_v1",ordered_quantiles=ordered,responses=responses,
      draw_id=draw,origin_id=origin,rng_namespace=unit$rng_namespace,path_range=c(1L,N),
      source_commit=s$source_commit,production_authorized=FALSE),"training_arrays.rds")
    save(coherence,"training_raw_coherence.rds")
    candidates <- diagnostic <- vector("list",H);inverse_parity <- list();t <- proc.time()
    progress("MATRIX_INVERSION_AND_NATIVE_REFERENCE")
    for(h in 1:H) {
      mat <- ordered[,,h]
      full <- env$app_iqf_mq_matrix_inverse(mat,tau,tau,1e-8)
      left <- env$app_iqf_mq_matrix_inverse(mat[1:32768,,drop=FALSE],tau,tau,1e-8)
      right <- env$app_iqf_mq_matrix_inverse(mat[32769:65536,,drop=FALSE],tau,tau,1e-8)
      kernels <- lapply(1:N,function(i)list(family="mq_grid",q=as.numeric(mat[i,]),tau=tau))
      reference <- env$app_iqf_mq_mixture_inverse(kernels,tau,1e-8)
      q(all(abs(full-reference)<=1e-10+1e-10*pmax(abs(full),abs(reference))),"native matrix inverse parity failed")
      inverse_parity[[h]] <- list(horizon=h,maximum_absolute_difference=max(abs(full-reference)),pass=TRUE)
      candidates[[h]] <- data.frame(horizon=h,probability=tau,quantile=full)
      diagnostic[[h]] <- data.frame(horizon=h,probability=tau,
        split_stream_absolute_difference=abs(left-right),
        split_stream_relative_difference=abs(left-right)/pmax(1,abs((left+right)/2)))
      progress("MATRIX_INVERSION_AND_NATIVE_REFERENCE",completed_horizons=h)
    }
    inversion_time <- proc.time()-t;candidates <- do.call(rbind,candidates);diagnostic <- do.call(rbind,diagnostic)
    split_ok <- all(diagnostic$split_stream_absolute_difference<=.005|diagnostic$split_stream_relative_difference<=.005)
    save(candidates,"frozen_training_candidates.rds");save(diagnostic,"training_split_diagnostic.rds")
    save(inverse_parity,"native_matrix_inverse_parity.rds")
    names <- c("training_arrays.rds","training_raw_coherence.rds","frozen_training_candidates.rds",
      "training_split_diagnostic.rds","training_parity.rds","native_matrix_inverse_parity.rds")
    freeze <- data.frame(relative_path=names,size_bytes=file.info(file.path(output,names))$size,
      sha256=unname(tools::sha256sum(file.path(output,names))))
    write_json(list(schema_version="mq_array_training_freeze_v1",source_commit=s$source_commit,
      candidate_phase="BEFORE_ANY_VALIDATION_PATH",training_path_range=c(1L,N),
      split_pass=split_ok,artifacts=freeze,validation_paths_generated=0L),"CANDIDATES_FROZEN.json")
    frozen_sha <- unname(tools::sha256sum(file.path(output,"CANDIDATES_FROZEN.json")))
    rm(ordered,responses,p,mat,kernels);gc(FALSE)
    stream <- NULL;validation_coherence <- NULL;validation_time <- c(user.self=0,sys.self=0,elapsed=0)
    if(split_ok) {
      parity$validation <- check_parity(mqa_parity_ids(s,TRUE,TRUE),"validation_only_after_frozen_candidates_and_split_pass")
      save(parity$validation,"deferred_validation_parity.rds")
      contract <- list(schema_version="mq_streaming_cdf_certificate_contract_v1",
        method="heldout_conditional_CDF_empirical_Bernstein_alpha_spending",
        conditioning="one_fixed_original_parameter_draw_and_observed_origin",
        validation_values="iid_future_path_conditional_CDF_not_particle_filter",candidates_from_training_paths_only=TRUE,
        rng_namespace=unit$rng_namespace,draw_id=draw,origin_id=origin,
        training_path_range=c(1L,65536L),validation_path_range=c(65537L,327680L),
        look_sizes=c(65536L,131072L,262144L),total_alpha=.05,alpha_per_look=rep(.05/3,3L),
        absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01,training_split_diagnostic=diagnostic)
      stream <- env$mq_scc_init(candidates,contract);grid <- stream$grid;t <- proc.time()
      for(look in c(65536L,131072L,262144L)) {
        for(first in seq.int(stream$count+1L,look,by=128L)) {
          relative <- seq.int(first,min(look,first+127L));ids <- 65536L+relative
          p <- env$app_iqf_mq_batch_arrays(batch,draw,origin,ids)
          values <- matrix(NA_real_,length(ids),grid$endpoint_count,dimnames=list(NULL,grid$endpoints$endpoint_id))
          for(h in 1:H) {
            at <- which(grid$endpoints$horizon==h)
            values[,at] <- mqa_cdf_rows(grid$endpoints$y[at],matrix(p$ordered_quantiles[,,h],length(ids),K),tau)
          }
          stream <- env$mq_scc_update(stream,values,ids)
          validation_coherence <- if(is.null(validation_coherence))p$raw_coherence else
            env$mq_coherence_merge(list(validation_coherence,p$raw_coherence))
          q(identical(mqa_rng(),initial_rng),"validation changed scientific caller RNG")
          if(stream$count%%1024L==0L)progress("DISJOINT_TRAINING_FIXED_LOOK_SOURCE_REPLAY",completed_paths=stream$count,next_look=look)
        }
        stream <- env$mq_scc_evaluate(stream)
        save(stream,sprintf("validation_stream_look_%06d.rds",stream$count))
        write.csv(stream$last_evaluation$endpoint_evidence,file.path(output,sprintf("validation_endpoints_%06d.csv",stream$count)),row.names=FALSE)
        seal();if(isTRUE(stream$terminal))break
      }
      validation_time <- proc.time()-t
      save(validation_coherence,"validation_raw_coherence.rds")
    } else progress("REVIEW_TRAINING_SPLIT_VALIDATION_NOT_STARTED",validation_paths_generated=0L)
    save(parity,"final_parity.rds")
    # Freeze readback and all source/runtime/original-byte pins are rechecked.
    q(identical(unname(tools::sha256sum(file.path(output,"CANDIDATES_FROZEN.json"))),frozen_sha)&&
      all(unname(tools::sha256sum(file.path(output,freeze$relative_path)))==freeze$sha256),"candidate freeze changed after validation")
    final_source <- mqa_source_guard(s,root);final_runtime <- mqa_runtime_guard(s)
    final_history <- mqa_history_bridge(s,root);final_history$old_batch_raw <- NULL
    q2_metadata(unit);mqa_pin(s$prepared_payload,64*1024^2);mqa_pin(s$prepared_derivation,2*1024^2);mqa_pin(s$prepared_manifest,1024^2)
    q(identical(mqa_rng(),initial_rng)&&expiry>Sys.time(),"RNG or complete purpose lifetime changed")
    cpu <- sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])
    q(cpu<=1800,"whole-purpose cumulative CPU exceeded")
    passed <- split_ok&&!is.null(stream)&&isTRUE(stream$last_evaluation$all_required_gates_pass)
    status <- if(!split_ok)"REVIEW_TRAINING_SPLIT_VALIDATION_NOT_STARTED"else if(passed)
      "PASS_NEW_SOURCE_ARRAY_ONE_UNIT_ONLY"else"REVIEW_MAXIMUM_FIXED_LOOK_PRECISION_NOT_QUALIFIED"
    receipt <- list(schema_version="mq_array_source_qualification_receipt_v1",
      status="GENUINE_ONE_UNIT_EXPERIMENT_COMPLETE_NOT_PRODUCTION",numerical_status=status,
      source_commit=s$source_commit,source_tree=s$source_tree,purpose_contract_sha256=args[4L],
      source_manifest=s$source_manifest,source_files=s$source_files,source_inventory_sha256=mqa_hash(s$source_files),
      runtime=runtime,final_runtime=final_runtime,source_readback=final_source,
      original_unit_contract=s$original_unit_contract,original_unit=unit,original_row_mapping=o$mapping,
      prepared_payload=s$prepared_payload,prepared_derivation=s$prepared_derivation,prepared_manifest=s$prepared_manifest,
      original_asset_bytes_stream_hashed=sum(metadata$size_bytes),raw_fixture_deserializations=0L,raw_design_deserializations=0L,
      historical_baseline_status=historical$historical_status,historical_old_failure_preserved=TRUE,
      historical_files_reverified=final_history$historical_files_verified,historical_evidence_not_new_source_qualification=TRUE,
      parity=parity,matrix_inverse_parity=inverse_parity,training_paths=65536L,training_split_gate_pass=split_ok,
      frozen_candidate_commitment_sha256=frozen_sha,validation_paths=if(is.null(stream))0L else stream$count,
      validation_paths_generated_before_freeze=0L,validation_parity_recorded_separately_same_scientific_ids=TRUE,
      validation_parity_does_not_create_an_independent_validation_stream=TRUE,
      novel_holdout_relative_to_previous_experiments=FALSE,
      scientific_experiment_scope="source_regression_replay_original_namespace_and_path_recipe",
      final_certificate=if(is.null(stream))NULL else stream$last_evaluation,
      validation_state_files_are_compact_stats_and_block_hashes_not_raw_cdf_matrix=TRUE,
      confidence_scope="one_fixed_parameter_draw_and_observed_origin_not_campaign_familywise",
      training_CPU_seconds=sum(training_time[1:2]),training_wall_seconds=unname(training_time["elapsed"]),
      inversion_CPU_seconds=sum(inversion_time[1:2]),inversion_wall_seconds=unname(inversion_time["elapsed"]),
      validation_CPU_seconds=sum(validation_time[1:2]),validation_wall_seconds=unname(validation_time["elapsed"]),
      whole_process_CPU_seconds=cpu,whole_process_wall_seconds=unname(proc.time()["elapsed"]),
      VmHWM=grep("^VmHWM:",readLines("/proc/self/status"),value=TRUE),limits=s$limits,
      prepared_input_bytes=prepared$prepared_bytes,administrative_reserve_bytes=administrative_reserve,
      thresholds_loosened=FALSE,observational_future_truth_used=FALSE,parameter_refits=0L,score_evaluations=0L,
      full_campaign_enrollment=FALSE,production_consumer_qualified=FALSE,production_authorized=FALSE,article_promotion_authorized=FALSE)
    write_json(receipt,"qualification.json");progress("GENUINE_EXPERIMENT_COMPLETE_NOT_PRODUCTION",numerical_status=status)
    seal();cat("MQ_ARRAY_ONE_UNIT_COMPLETE_NOT_PRODUCTION numerical_status=",status,"\n",sep="")
    invisible(receipt)
  },error=function(e) {
    try(write_json(list(schema_version="mq_array_source_qualification_failure_v1",
      status="FAILED_NEW_SOURCE_QUALIFICATION_NOT_PRODUCTION",phase=phase,error=conditionMessage(e),
      source_commit=s$source_commit,purpose_contract_sha256=args[4L],production_authorized=FALSE),"failure.json"),silent=TRUE)
    try(seal(),silent=TRUE);stop(e)
  })
}
if(sys.nframe()==0L)mqa_main()
