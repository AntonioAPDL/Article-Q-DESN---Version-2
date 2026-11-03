#!/usr/bin/env Rscript
# Explicit genuine source-regression entrypoint. No refit/scoring/production.
source("scripts/mq_native_source_qualification.R",local=TRUE)
source("scripts/mq_native_qualification_backend.R",local=TRUE)
mqns_compare <- function(a,b,tolerance=1e-10) {
  mqns_require(is.numeric(a)&&is.numeric(b)&&identical(dim(a),dim(b))&&length(a)==length(b)&&
    all(is.finite(c(a,b))),"typed finite numerical-regression operands required")
  d<-abs(a-b);mqns_require(all(d<=tolerance+tolerance*pmax(abs(a),abs(b))),"pointwise numerical parity failed")
  if(length(d))max(d)else 0
}
mqns_reference_arrays <- function(s,ctx) {
  mqns_context_check(ctx)
  q<-mqns_require
  if(!s$allow_historical_training_array_read)return(NULL)
  q(identical(s$historical_reader_role,"retained_numerical_regression_arrays_not_model_or_truth"),
    "historical numerical-array reader role missing")
  expected<-c(historical_manifest="4fd56dad0d46b541da4b0d0511f6f25001896e5539f2812644864e3bccb0f805",
    historical_receipt="bff4d096d577e3f7d26c89dd489fdf9ac97731b877461cbe9fd1b3b38ace5cbf",
    historical_freeze="9f18cc49d6ed5ff6c761c636deb23e1d137b4b6734754842d0a16c620f557ca5")
  for(k in names(expected))q(identical(s[[k]]$sha256,unname(expected[k])),"authentic accepted historical metadata pin changed")
  m<-read.csv(mqa_pin(s$historical_manifest,1024^2),stringsAsFactors=FALSE)
  r<-jsonlite::read_json(mqa_pin(s$historical_receipt,1024^2),simplifyVector=FALSE)
  f<-jsonlite::read_json(mqa_pin(s$historical_freeze,1024^2),simplifyVector=FALSE)
  t<-jsonlite::read_json(mqa_pin(s$historical_terminal,1024^2),simplifyVector=FALSE)
  q(identical(r$source_commit,"56275f93f78911159ee39f2c234becda236bf43f")&&
    identical(r$numerical_status,"PASS_NEW_SOURCE_ARRAY_ONE_UNIT_ONLY")&&
    identical(t$status,"EXECUTION_COMPLETE_NOT_PRODUCTION")&&
    identical(t$source_commit,r$source_commit)&&identical(t$purpose_sha256,r$purpose_contract_sha256)&&
    identical(r$production_authorized,FALSE)&&identical(t$production_authorized,FALSE)&&
    identical(f$source_commit,r$source_commit)&&identical(f$split_pass,TRUE)&&
    identical(f$candidate_phase,"BEFORE_ANY_VALIDATION_PATH")&&f$validation_paths_generated==0,
    "retained reference is not the accepted historical one-unit source replay")
  pin<-s$historical_training_array
  q(identical(pin$sha256,"5d4e13c0228aded44bccd237971d1fa754b63a59b25bde90584e16808445b91c")&&
    pin$size_bytes==125829790&&identical(dirname(pin$path),dirname(s$historical_manifest$path))&&
    identical(basename(pin$path),"training_arrays.rds"),"explicit historical array identity changed")
  row<-m[m$relative_path=="training_arrays.rds",]
  q(nrow(row)==1L&&row$size_bytes==pin$size_bytes&&identical(row$sha256,pin$sha256),"historical array absent from accepted manifest")
  # Only this explicitly granted numerical regression artifact is deserialized.
  x<-readRDS(mqa_pin(pin,256*1024^2));mqa_no_callbacks(x)
  q(is.list(x)&&setequal(names(x),c("schema_version","ordered_quantiles","responses","draw_id","origin_id",
      "rng_namespace","path_range","source_commit","production_authorized"))&&
    identical(x$schema_version,"mq_array_qualification_training_v1")&&
    identical(dim(x$ordered_quantiles),c(65536L,7L,30L))&&identical(dim(x$responses),c(65536L,30L))&&
    all(is.finite(c(x$ordered_quantiles,x$responses)))&&identical(x$draw_id,ctx$unit_identity$draw_id)&&
    identical(x$origin_id,"1")&&identical(x$rng_namespace,ctx$unit_identity$rng_namespace)&&
    mqa_equal(x$path_range,c(1,65536))&&identical(x$source_commit,r$source_commit)&&
    identical(x$production_authorized,FALSE),"historical numerical artifact schema/unit differs")
  x
}
mqns_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript --vanilla scripts/qualify_mq_native_composed.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  q<-mqns_require
  q(length(args)==5L&&identical(args[c(1,3,5)],c("--contract","--sha256","--execute")),
    "exact external contract/hash/execute arguments required")
  for(p in c("digest","jsonlite","tools","compiler"))q(requireNamespace(p,quietly=TRUE),paste("required package",p))
  root<-normalizePath(getwd(),mustWork=TRUE);cp<-normalizePath(args[2L],mustWork=TRUE)
  q2_regular(cp)
  q(!startsWith(cp,paste0(root,"/"))&&file.info(cp)$size<=1024^2&&
    identical(unname(tools::sha256sum(cp)),args[4L]),"external exact purpose bytes required")
  s<-jsonlite::read_json(cp,simplifyVector=FALSE);mqns_scope(s)
  q(q2_time(s$expires_utc)>Sys.time()+1800,"purpose must cover the whole bounded replay")
  gate<-mqns_live_gate(s,args[4L])
  source_gate<-mqns_source_guard(s,root)
  prepared_metadata<-mqns_prepared_metadata(s,root)
  build<-mqns_build_receipt(s,root)
  for(f in mqns_native_files())source(file.path(root,f),local=.GlobalEnv)
  app_set_repo_root(root)
  load_ctx<-mqns_make_enrollment_context(s,cp,args[4L],gate)
  load_handle<-mqnk_enroll(build,load_ctx) # LOAD_ONLY, no numeric method permitted.
  mqns_lapack_warmup()                  # Deterministic; forces lazy LAPACK mappings.
  runtime<-mqa_runtime_guard(s)          # Actual retained3DLLs are now mapped.
  ctx<-mqns_make_context(s,cp,args[4L],gate);mqns_context_check(ctx)
  output<-s$output_root;q2_regular(output)
  q(is.character(output)&&length(output)==1L&&startsWith(output,paste0(root,"/local_trackers/"))&&
    !file.exists(output)&&dir.exists(dirname(output))&&identical(dirname(output),normalizePath(dirname(output),mustWork=TRUE))&&
    system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(output)))==0L,"fresh ignored exact output required")
  q(dir.create(output),"output creation failed")
  phase<-"ADMITTED_GENUINE_NATIVE_REPLAY";initial_rng<-mqa_rng();reserve<-1024^2;prepared_bytes<-0
  write_json<-function(x,name) {
    p<-file.path(output,name);tmp<-paste0(p,".tmp")
    jsonlite::write_json(x,tmp,auto_unbox=TRUE,pretty=TRUE,digits=17,null="null")
    q(file.rename(tmp,p),"atomic metadata write failed")
  }
  progress<-function(name,...) {
    phase<<-name;write_json(list(schema_version="mq_native_source_replay_progress_v1",phase=name,
      utc=format(Sys.time(),"%Y-%m-%dT%H:%M:%SZ",tz="UTC"),source_commit=s$source_commit,
      purpose_contract_sha256=args[4L],production_authorized=FALSE,details=list(...)),"progress.json")
  }
  seal<-function() {
    files<-list.files(output,full.names=TRUE,all.files=TRUE,no..=TRUE)
    q(all(!dir.exists(files))&&all(!nzchar(Sys.readlink(files))),"direct regular output files only")
    files<-files[basename(files)!="artifact_manifest.csv"]
    sizes<-as.numeric(file.info(files)$size)
    q(all(is.finite(sizes))&&all(sizes>=0)&&sum(sizes)+prepared_bytes+reserve<s$limits$output_bytes,
      "complete output/prepared/admin cap exceeded")
    write.csv(data.frame(relative_path=basename(files),size_bytes=sizes,
      sha256=unname(tools::sha256sum(files))),file.path(output,"artifact_manifest.csv"),row.names=FALSE)
  }
  save<-function(x,name) {
    p<-file.path(output,name);q(!file.exists(p),"immutable output overwrite forbidden")
    used<-sum(file.info(list.files(output,full.names=TRUE,all.files=TRUE,no..=TRUE))$size)+prepared_bytes+reserve
    q2_write(x,p,used,s$limits$output_bytes);seal()
    list(path=p,size_bytes=as.numeric(file.info(p)$size),sha256=unname(tools::sha256sum(p)))
  }
  tryCatch({
    progress(phase)
    # No authentic numerical payload is read until the fresh owned output and
    # its failure/progress writers exist under all source/runtime/live gates.
    prepared<-mqa_verify_prepared(prepared_metadata$old_context,root)
    prepared_bytes<-prepared$prepared_bytes
    reference<-mqns_reference_arrays(s,ctx)
    o<-prepared$objects;unit<-s$original_unit;draw<-o$posterior$draw_ids;origin<-"1"
    tau<-as.numeric(unlist(unit$tau));H<-30L;K<-7L
    coupling<-list(method="native_joint_posterior",recipe_sha256=mqa_hash(list(source=unit$assets$posterior$sha256,
      row=1L,method="native_joint_posterior")),draw_mapping_sha256=o$posterior$draw_mapping_sha256)
    scalar<-app_iqf_desn_adapter(o$design,o$posterior,o$origins,tau,"mq_grid",coupling,unit$rng_namespace)
    batch<-app_iqf_mq_batch_adapter(o$design,o$posterior,o$origins,tau,coupling,unit$rng_namespace,
      inner_paths=327680L,batch_size=128L,rng_mode="r46_first_step_qualified",
      rng_proof=list(R_version="4.6.0",RNG_c_sha256=s$native_rng_source$sha256))
    handle<-mqnk_load(build,ctx)
    parity<-function(ids,stage) {
      new<-mqnk_arrays(handle,batch,draw,origin,ids,include_trace=TRUE,phase=stage)
      old<-app_iqf_mq_batch_arrays(batch,draw,origin,ids,include_trace=TRUE)
      errors<-c(mqns_compare(new$response,old$response),mqns_compare(new$ordered_quantiles,old$ordered_quantiles))
      for(h in 1:H) {
        for(key in c("raw","scaled","readout","raw_quantiles","ordered_quantiles","uniform"))
          errors<-c(errors,mqns_compare(new$trace[[h]][[key]],old$trace[[h]][[key]]))
        q(identical(new$trace[[h]]$uniform,old$trace[[h]]$uniform),"scientific uniform bits changed")
        for(d in seq_along(new$trace[[h]]$states))errors<-c(errors,
          mqns_compare(new$trace[[h]]$states[[d]],old$trace[[h]]$states[[d]]))
      }
      for(i in seq_along(ids)) {
        x<-scalar$path(draw,origin,ids[i]);errors<-c(errors,mqns_compare(x$response,new$response[i,]),
          mqns_compare(do.call(rbind,lapply(x$kernels,`[[`,"q")),t(matrix(new$ordered_quantiles[i,,],K,H))))
      }
      q(identical(mqa_rng(),initial_rng),"parity changed caller RNG")
      list(path_ids=ids,phase=stage,maximum_absolute_difference=max(errors),pass=TRUE)
    }
    pre<-parity(as.integer(unlist(s$parity_path_ids)[unlist(s$parity_path_ids)<=65536]),"parity_training")
    parity_pin<-save(pre,"training_parity.rds")
    ordered<-array(NA_real_,c(65536L,K,H));coherence<-NULL;blocks<-list();t<-proc.time()
    progress("NATIVE_TRAINING",completed_paths=0L)
    for(first in seq.int(1L,65536L,by=128L)) {
      ids<-seq.int(first,min(65536L,first+127L));new<-mqnk_arrays(handle,batch,draw,origin,ids,phase="training")
      old<-if(is.null(reference))app_iqf_mq_batch_arrays(batch,draw,origin,ids)else NULL
      er<-if(is.null(reference))c(mqns_compare(new$response,old$response),mqns_compare(new$ordered_quantiles,old$ordered_quantiles))else
        c(mqns_compare(new$response,reference$responses[ids,,drop=FALSE]),
          mqns_compare(new$ordered_quantiles,reference$ordered_quantiles[ids,,,drop=FALSE]))
      blocks[[length(blocks)+1L]]<-data.frame(first=min(ids),last=max(ids),maximum_absolute_difference=max(er),
        candidate_response_sha256=mqa_hash(new$response),candidate_kernel_sha256=mqa_hash(new$ordered_quantiles))
      ordered[ids,,]<-new$ordered_quantiles
      coherence<-if(is.null(coherence))new$raw_coherence else mq_coherence_merge(list(coherence,new$raw_coherence))
      q(identical(mqa_rng(),initial_rng),"training changed RNG")
      if(max(ids)%%1024L==0L)progress("NATIVE_TRAINING",completed_paths=max(ids))
    }
    training_time<-proc.time()-t
    write.csv(do.call(rbind,blocks),file.path(output,"training_block_parity.csv"),row.names=FALSE)
    save(coherence,"training_raw_coherence.rds")
    candidates<-diagnostic<-inverse_check<-vector("list",H);t<-proc.time()
    for(h in 1:H) {
      mat<-ordered[,,h];full<-mqnk_inverse(handle,mat,tau,tau,1e-8)
      left<-mqnk_inverse(handle,mat[1:32768,,drop=FALSE],tau,tau,1e-8)
      right<-mqnk_inverse(handle,mat[32769:65536,,drop=FALSE],tau,tau,1e-8)
      native<-app_iqf_mq_matrix_inverse(mat,tau,tau,1e-8)
      inverse_check[[h]]<-list(horizon=h,maximum_absolute_difference=mqns_compare(full,native),pass=TRUE)
      candidates[[h]]<-data.frame(horizon=h,probability=tau,quantile=full)
      diagnostic[[h]]<-data.frame(horizon=h,probability=tau,split_stream_absolute_difference=abs(left-right),
        split_stream_relative_difference=abs(left-right)/pmax(1,abs((left+right)/2)))
    }
    inversion_time<-proc.time()-t;candidates<-do.call(rbind,candidates);diagnostic<-do.call(rbind,diagnostic)
    split_ok<-all(diagnostic$split_stream_absolute_difference<=.005|diagnostic$split_stream_relative_difference<=.005)
    candidate_pin<-save(candidates,"frozen_training_candidates.rds")
    split_pin<-save(diagnostic,"training_split_diagnostic.rds")
    save(inverse_check,"native_matrix_inverse_parity.rds")
    write_json(list(schema_version="mq_native_training_freeze_v1",source_commit=s$source_commit,
      purpose_contract_sha256=args[4L],candidate_phase="BEFORE_ANY_VALIDATION_PATH",training_path_range=c(1L,65536L),
      split_pass=split_ok,validation_paths_generated=0L,artifacts=list(candidate_pin,split_pin,parity_pin)),"CANDIDATES_FROZEN.json")
    freeze_pin<-list(path=file.path(output,"CANDIDATES_FROZEN.json"),size_bytes=as.numeric(file.info(file.path(output,"CANDIDATES_FROZEN.json"))$size),
      sha256=unname(tools::sha256sum(file.path(output,"CANDIDATES_FROZEN.json"))))
    rm(ordered,reference,new,old,mat);gc(FALSE)
    stream<-NULL;validation_parity<-NULL;cdf_parity<-NULL;validation_coherence<-NULL;t<-proc.time()
    if(split_ok) {
      ctx<-mqns_context_validation(ctx,freeze_pin);handle<-mqnk_load(build,ctx)
      validation_parity<-parity(as.integer(unlist(s$parity_path_ids)[unlist(s$parity_path_ids)>65536]),"parity_validation")
      save(validation_parity,"deferred_validation_parity.rds")
      contract<-list(schema_version="mq_streaming_cdf_certificate_contract_v1",method="heldout_conditional_CDF_empirical_Bernstein_alpha_spending",
        conditioning="one_fixed_original_parameter_draw_and_observed_origin",validation_values="iid_future_path_conditional_CDF_not_particle_filter",
        candidates_from_training_paths_only=TRUE,rng_namespace=unit$rng_namespace,draw_id=draw,origin_id=origin,
        training_path_range=c(1L,65536L),validation_path_range=c(65537L,327680L),look_sizes=c(65536L,131072L,262144L),
        total_alpha=.05,alpha_per_look=rep(.05/3,3),absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01,
        training_split_diagnostic=diagnostic)
      stream<-mq_scc_init(candidates,contract);grid<-stream$grid
      # Only the two originally declared deferred IDs are used. These values
      # do not update the certificate, choose candidates or change any stream.
      cdf_ids<-as.integer(unlist(s$parity_path_ids)[unlist(s$parity_path_ids)>65536])
      cdf_paths<-mqnk_arrays(handle,batch,draw,origin,cdf_ids,phase="parity_validation")
      cdf_parity<-lapply(1:H,function(h) {
        at<-which(grid$endpoints$horizon==h);mat<-matrix(cdf_paths$ordered_quantiles[,,h],length(cdf_ids),K)
        native<-mqnk_cdf_values(handle,grid$endpoints$y[at],mat,tau)
        reference<-mqa_cdf_rows(grid$endpoints$y[at],mat,tau)
        list(horizon=h,path_ids=cdf_ids,endpoint_count=length(at),
          maximum_absolute_difference=mqns_compare(native,reference),pass=TRUE)
      })
      q(identical(mqa_rng(),initial_rng),"deferred CDF parity changed RNG")
      save(cdf_parity,"deferred_individual_cdf_parity.rds");rm(cdf_paths)
      for(look in c(65536L,131072L,262144L)) {
        for(first in seq.int(stream$count+1L,look,by=128L)) {
          ids<-65536L+seq.int(first,min(look,first+127L))
          z<-mqnk_arrays(handle,batch,draw,origin,ids,phase="validation")
          values<-matrix(NA_real_,length(ids),grid$endpoint_count,dimnames=list(NULL,grid$endpoints$endpoint_id))
          for(h in 1:H) {
            at<-which(grid$endpoints$horizon==h)
            values[,at]<-mqnk_cdf_values(handle,grid$endpoints$y[at],matrix(z$ordered_quantiles[,,h],length(ids),K),tau)
          }
          stream<-mq_scc_update(stream,values,ids)
          validation_coherence<-if(is.null(validation_coherence))z$raw_coherence else mq_coherence_merge(list(validation_coherence,z$raw_coherence))
          q(identical(mqa_rng(),initial_rng),"validation changed RNG")
          if(stream$count%%1024L==0L)progress("NATIVE_FIXED_LOOK_VALIDATION",completed_paths=stream$count,next_look=look)
        }
        stream<-mq_scc_evaluate(stream)
        save(stream,sprintf("validation_stream_look_%06d.rds",stream$count))
        write.csv(stream$last_evaluation$endpoint_evidence,file.path(output,sprintf("validation_endpoints_%06d.csv",stream$count)),row.names=FALSE)
        seal();if(isTRUE(stream$terminal))break
      }
      save(validation_coherence,"validation_raw_coherence.rds")
    }else progress("REVIEW_TRAINING_SPLIT_VALIDATION_NOT_STARTED",validation_paths_generated=0L)
    validation_time<-proc.time()-t
    mqa_pin(freeze_pin,4*1024^2)
    for(pin in list(candidate_pin,split_pin,parity_pin))mqa_pin(pin,256*1024^2)
    final_source<-mqns_source_guard(s,root);final_build<-mqns_build_receipt(s,root)
    final_runtime<-mqa_runtime_guard(s);mqns_external_gate(s);mqns_context_check(ctx)
    q(q2_time(s$expires_utc)>Sys.time()&&identical(mqa_rng(),initial_rng),"final expiry/RNG changed")
    cpu<-sum(proc.time()[c("user.self","sys.self","user.child","sys.child")]);q(cpu<=1800,"whole replay CPU exceeded")
    passed<-split_ok&&!is.null(stream)&&isTRUE(stream$last_evaluation$all_required_gates_pass)
    numerical<-if(!split_ok)"REVIEW_TRAINING_SPLIT_VALIDATION_NOT_STARTED"else if(passed)
      "PASS_NATIVE_ONE_ORIGINAL_UNIT_SOURCE_REGRESSION_ONLY"else"REVIEW_MAXIMUM_FIXED_LOOK_PRECISION_NOT_QUALIFIED"
    receipt<-list(schema_version="mq_native_source_replay_receipt_v1",status="GENUINE_NATIVE_SOURCE_REPLAY_COMPLETE_NOT_PRODUCTION",
      numerical_status=numerical,source_commit=s$source_commit,source_tree=s$source_tree,purpose_contract_sha256=args[4L],
      source_readback=source_gate,final_source_readback=final_source,retained_build_receipt=s$retained_build_receipt,
      runtime=runtime,final_runtime=final_runtime,prepared_old_producer=prepared_metadata[c("producer_source_commit","old_source_files_verified")],
      prepared_payload=s$prepared_payload,historical_training_array_read=s$allow_historical_training_array_read,
      original_unit=unit,parity=pre,deferred_validation_parity=validation_parity,
      deferred_individual_cdf_parity=cdf_parity,training_paths=65536L,
      training_split_gate_pass=split_ok,validation_paths=if(is.null(stream))0L else stream$count,
      validation_paths_generated_before_freeze=0L,freeze_sha256=freeze_pin$sha256,
      final_certificate=if(is.null(stream))NULL else stream$last_evaluation,
      training_CPU_seconds=sum(training_time[1:2]),inversion_CPU_seconds=sum(inversion_time[1:2]),
      validation_CPU_seconds=sum(validation_time[1:2]),whole_process_CPU_seconds=cpu,
      novel_holdout_relative_to_previous_experiments=FALSE,scientific_experiment_scope="one_original_draw_origin_source_regression",
      full_campaign_enrollment=FALSE,production_consumer_qualified=FALSE,C_ABI_qualified=FALSE,
      observational_future_truth_used=FALSE,raw_fixture_deserializations=0L,raw_design_deserializations=0L,
      parameter_refits=0L,score_evaluations=0L,production_authorized=FALSE,article_promotion_authorized=FALSE)
    write_json(receipt,"qualification.json");progress("GENUINE_NATIVE_REPLAY_COMPLETE_NOT_PRODUCTION",numerical_status=numerical)
    seal();cat("MQ_NATIVE_SOURCE_REPLAY_COMPLETE numerical_status=",numerical," production=FALSE\n",sep="")
    invisible(receipt)
  },error=function(e){
    try(write_json(list(status="FAILED_NATIVE_SOURCE_REPLAY_NOT_PRODUCTION",phase=phase,error=conditionMessage(e),
      source_commit=s$source_commit,purpose_contract_sha256=args[4L],production_authorized=FALSE),"failure.json"),silent=TRUE)
    try(seal(),silent=TRUE);stop(e)
  })
}
if(sys.nframe()==0L)mqns_main()
