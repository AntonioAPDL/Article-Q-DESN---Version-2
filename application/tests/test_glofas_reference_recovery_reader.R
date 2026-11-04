# Generated metadata and generated output arrays only; no authentic RDS access.
local({
  source("scripts/glofas_reference_recovery_reader.R",local=TRUE)
  checks<-0L;ok<-function(x){stopifnot(isTRUE(x));checks<<-checks+1L;invisible(TRUE)}
  reject<-function(expr,pattern=NULL){e<-tryCatch({force(expr);NULL},error=function(e)e)
    ok(inherits(e,"error"));if(!is.null(pattern))ok(grepl(pattern,conditionMessage(e),fixed=TRUE))}
  pin<-function(path,size=100,sha=strrep("a",64))list(path=path,size_bytes=size,sha256=sha)
  prior<-function(path)list(receipt=pin(file.path(path,"receipt.json")),manifest=pin(file.path(path,"artifact_manifest.csv")),
    summary=pin(file.path(path,"summary.json")),terminal=pin(paste0(path,"_native_terminal.json")))
  s<-list(schema_version="glofas_reference_recovery_contract_v1",
    purpose="MEDIAN_AL_FIXED_PARAMETER_TWO_ARM_KERNEL_RECOVERY_PILOT_NO_FULL_REFIT",mode="computational_pilot",
    execution_mode="fork_eight",nonce=strrep("a",32),expires_utc="2100-01-01T00:00:00Z",
    source_root="/generated/source",source_commit=strrep("a",40),source_tree=strrep("b",40),
    source_files=list(pin("/generated/source.R")),expected_identity=gsc_identity(),collection=pin("/generated/accepted_producers.json"),
    input_manifest=pin("/generated/input_manifest.csv",sha=gsc_identity()$input_manifest_sha256),
    design=pin("/generated/shared_truth_free_design.rds",4014834693,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
    median_model=pin("/generated/fit.rds",137820489,"f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881"),
    prior_replay=prior("/generated/replay"),baseline=prior("/generated/baseline"),
    calibration_draws=pin("/generated/baseline/conditional_reference_draws.rds",17920074,
      "41d4ad60c62f130e7cc03ecd2c4cdeafedd8671688c20ba371147bbf471060be"),
    diagnostic_dependencies=list(library_root="/generated/library",versions=pin("/generated/versions.csv"),sources=pin("/generated/sources.csv")),
    read_budget=list(max_payload_hash_bytes=2*4170575256,max_deserialization_bytes=4170575256,
      max_RDS_deserializations=2L,max_generated_RDS_deserializations=1L,max_metadata_bytes=64*1024^2,max_recovery_output_bytes=10*1024^2),
    limits=list(cpu_seconds=3600L,wall_seconds=3600L,memory_bytes=16*1024^3,output_bytes=64*1024^2,
      logical_cpu=26L,max_workers=8L,child_logical_cpus=as.list(c(20,21,22,23,26,27,28,29)),
      child_cpu_seconds=3600L,aggregate_cpu_seconds=32400L,aggregate_memory_bytes=144*1024^3,
      memory_headroom_bytes=180*1024^3,max_draw_memory_bytes=64*1024^2),
    output_root="/generated/source/local_trackers/recovery",metadata_scratch_root="/generated/scratch",
    metadata_serialization=list(max_files=64L,max_file_bytes=4*1024^2,max_total_bytes=16*1024^2),
    recovery=list(likelihood_family="al",tau=.5,parameter_rule="retained_theta_mean_fixed_coefficient_covariance_zero",
      scale_rule="reciprocal_retained_inverse_scale_means_not_scale_means",
      calibration_role="PROPOSAL_CALIBRATION_ONLY_NOT_QUALIFIED_REFERENCE",proposal_rule="pooled_baseline_path_draws_spd_calibration_only",
      start_rule="retained_m_minus_sd_plus_sd_and_reference_at_m_minus_sd_plus_sd",value_backend="compiled_input_reference",
      max_total_value_evaluations=12015L,max_jacobian_evaluations=1L,parity_evaluations=6L,setup_value_evaluations=1L,
      minimum_tail_seconds=120L,progress_every=250L,qualification_scope="two_arm_computational_pilot_only_not_production_qualification",
      kernels=as.list(grrr_kernels()),sampler=list(warmup=500L,samples=1000L,max_evaluations=1501L,max_wall_seconds=2600,
        adapt_warmup=TRUE,rhat_max=1.01,min_ess=400,max_quantile_mcse=.001),
      timing_basis=list(baseline_max_elapsed_seconds=17200,baseline_callback_evaluations=24001,safety_factor=2)),
    draw_export=list(filenames=as.list(paste0(grrr_kernels(),"_draws.rds")),
      role="generated_fixed_parameter_conditional_path_draws_not_full_posterior",max_bytes=2*1024^2,
      serialization_version=3L,numeric_array_only=TRUE),
    allow_original_reads=TRUE,allow_generated_numeric_array_read=TRUE,allow_fresh_source_feature_evaluation=TRUE,
    allow_metadata_serialization=TRUE,allow_proposal_calibration=TRUE,allow_fixed_parameter_path_sampling=TRUE,allow_raw_draw_export=TRUE,
    allow_saved_callbacks=FALSE,allow_parameter_updates=FALSE,allow_prior_updates=FALSE,allow_full_parameter_refit=FALSE,
    allow_truth_read=FALSE,allow_retuning=FALSE,allow_scoring=FALSE,allow_article_changes=FALSE,allow_publication=FALSE,
    allow_derived_context_serialization=FALSE)
  s$baseline$terminal$sha256<-"239fab60c9590315d753a4d743fd830e276921f2d5cc78ab3f4902d1c9cf51d7"
  ok(isTRUE(grrr_scope(s)));cost<-grrr_cost(s);ok(cost$original_RDS_deserializations==2L&&cost$generated_numeric_array_deserializations==1L)
  ok(cost$payload_hash_bytes==8341150512&&cost$deserialization_bytes==4170575256)
  for(field in names(s)[startsWith(names(s),"allow_")]) {
    bad<-s;bad[[field]]<-!s[[field]];reject(grrr_scope(bad),"separate recovery")
  }
  bad<-s;bad$schema_version<-"glofas_al_conditional_reference_contract_v2";reject(grrr_scope(bad))
  bad<-s;bad$mode<-"full_reference";reject(grrr_scope(bad))
  bad<-s;bad$design$size_bytes<-1000;reject(grrr_scope(bad),"exact frozen")
  bad<-s;bad$calibration_draws$sha256<-strrep("f",64);reject(grrr_scope(bad),"exact frozen")
  bad<-s;bad$baseline$terminal$sha256<-strrep("f",64);reject(grrr_scope(bad),"closed unqualified")
  for(field in c("max_RDS_deserializations","max_generated_RDS_deserializations","max_payload_hash_bytes","max_deserialization_bytes")) {
    bad<-s;bad$read_budget[[field]]<-s$read_budget[[field]]-1;reject(grrr_scope(bad))
  }
  bad<-s;bad$limits$child_logical_cpus<-as.list(c(20,21,22,23,26,27,28,28));reject(grrr_scope(bad),"eight-child")
  bad<-s;bad$limits$memory_bytes<-32*1024^3;reject(grrr_scope(bad),"eight-child")
  bad<-s;bad$limits$aggregate_memory_bytes<-143*1024^3;reject(grrr_scope(bad))
  bad<-s;bad$limits$aggregate_cpu_seconds<-32399;reject(grrr_scope(bad))
  bad<-s;bad$limits$child_cpu_seconds<-1800;reject(grrr_scope(bad),"eight-child")
  bad<-s;bad$recovery$sampler$samples<-20000;reject(grrr_scope(bad),"computational pilot")
  bad<-s;bad$recovery$scale_rule<-"posterior_scale_mean";reject(grrr_scope(bad))
  bad<-s;bad$recovery$timing_basis$baseline_max_elapsed_seconds<-.372*24001;reject(grrr_scope(bad),"average-cost")
  bad<-s;bad$recovery$sampler$max_wall_seconds<-2000;reject(grrr_scope(bad),"average-cost")
  bad<-s;bad$recovery$max_total_value_evaluations<-12014;reject(grrr_scope(bad))
  bad<-s;bad$draw_export$filenames[[1]]<-"fit.rds";reject(grrr_scope(bad),"two bounded")
  bad<-s;bad$unexpected_permission<-TRUE;reject(grrr_scope(bad))
  ok(grrr_no_link("/nonexistent/generated/path"));ok(length(grrr_sources())==19L)
  arm<-grrr_pilot_arm(list(status="QUALIFIED_CONDITIONAL_REFERENCE",qualified=TRUE,diagnostics="preserved",condition=list(issued=matrix(0,28,51))))
  ok(!arm$qualified&&!arm$reference_qualified&&!arm$production_qualification&&arm$diagnostic_thresholds_passed)
  ok(identical(arm$diagnostic_status,"QUALIFIED_CONDITIONAL_REFERENCE")&&identical(arm$diagnostics,"preserved"))
  ok(is.null(arm$condition))
  arm<-grrr_pilot_arm(list(status="INCONCLUSIVE_CHAIN_EXECUTION",qualified=FALSE))
  ok(!arm$diagnostic_thresholds_passed&&identical(arm$diagnostic_status,"INCONCLUSIVE_CHAIN_EXECUTION"))

  # Baseline keeps its INCONCLUSIVE status despite admitting its array for C.
  r<-list(schema_version="glofas_al_conditional_reference_receipt_v1",status="INCONCLUSIVE_CONDITIONAL_REFERENCE",mode="sample",
    reference_qualified=FALSE,full_posterior_accuracy_qualified=FALSE,publication_authorized=FALSE,
    purpose_sha256=strrep("c",64),source_commit=strrep("d",40),source_tree=strrep("e",40),
    original_RDS_deserializations=2L,conditional_reference_chains_attempted=4L,saved_callback_calls=0L,
    full_parameter_refits=0L,future_truth_read=FALSE,input_bindings=s[c("design","median_model")],
    producer_identity=gsc_identity(),accepted_collection=s$collection,input_manifest=s$input_manifest,
    attempted_reads=lapply(s[c("design","median_model")],function(p)c(p,list(status="DESERIALIZED",post_read_sha256=p$sha256))),
    generated_draw_export=c(s$calibration_draws,list(generated_array_only=TRUE,full_parameter_posterior_draws=FALSE,
      dimensions=c(20000L,4L,28L))))
  t<-list(schema_version="glofas_al_conditional_reference_native_terminal_v1",purpose_sha256=r$purpose_sha256,
    source_commit=r$source_commit,source_tree=r$source_tree,native_exit_code=0L,owner_terminated=TRUE,worker_terminated=TRUE,
    timed_out=FALSE,output_manifest_verified=TRUE,output_manifest_sha256=s$baseline$manifest$sha256,
    original_RDS_deserializations=2L,saved_callback_calls=0L,full_parameter_refits=0L,future_truth_read=FALSE)
  pins<-c(s$baseline[c("receipt","summary")],list(s$calibration_draws))
  m<-data.frame(relative_path=vapply(pins,function(p)basename(p$path),character(1L)),
    size_bytes=vapply(pins,function(p)p$size_bytes,numeric(1L)),sha256=vapply(pins,function(p)p$sha256,character(1L)))
  p<-list(receipt=r,terminal=t,summary=list(status=r$status),manifest=m)
  ok(isTRUE(grrr_baseline_bind(s,p)))
  bad<-p;bad$receipt$reference_qualified<-TRUE;reject(grrr_baseline_bind(s,bad),"remain INCONCLUSIVE")
  bad<-p;bad$terminal$worker_terminated<-FALSE;reject(grrr_baseline_bind(s,bad))
  bad<-p;bad$receipt$status<-"CONDITIONAL_REFERENCE_DIAGNOSTICS_PASSED_NOT_FULL_POSTERIOR";reject(grrr_baseline_bind(s,bad))
  bad<-p;bad$manifest$sha256[3]<-strrep("f",64);reject(grrr_baseline_bind(s,bad),"manifest-bound")
  bad<-p;bad$receipt$generated_draw_export$dimensions<-c(1000L,4L,28L);reject(grrr_baseline_bind(s,bad),"typed completed")
  bad<-p;bad$receipt$attempted_reads[[1]]$post_read_sha256<-strrep("f",64);reject(grrr_baseline_bind(s,bad),"before/after")

  # Test only newly generated arrays/progress, never the pinned authentic array.
  output<-tempfile("grrr_generated_output_");dir.create(output);ss<-s;ss$output_root<-normalizePath(output)
  draws<-array(0,c(1000L,4L,28L));draws[1,1,1]<-NA_real_
  exported<-grrr_write_draws(draws,ss,1L);ok(exported$missing_values==1L&&exported$generated_array_only)
  ok(identical(readRDS(exported$path),draws));reject(grrr_write_draws(draws,ss,1L),"fresh pilot")
  reject(grrr_write_draws(list(draws),ss,2L),"numeric per-arm")
  progress<-grrr_progress(output,1L,grrr_kernels()[1],1L)
  event<-list(schema_version="recovery_progress_metadata_v1",chain_id=1L,completed_iterations=250L,retained_iterations=0L,callback_evaluations=251L,
    elapsed_seconds=1,kernel_attempted=c(250,0),kernel_accepted=c(50,0),fully_completed=FALSE)
  progress(event);event$completed_iterations<-500L;progress(event)
  progress_path<-file.path(output,"progress_worker_01.json")
  ok(file.info(progress_path)$size<4096&&!file.exists(paste0(progress_path,".new")))
  ok(jsonlite::read_json(progress_path)$completed_iterations==500L)
  bad<-event;bad$path<-rep(0,28);reject(progress(bad),"bounded numeric")
  purpose<-tempfile("grrr_generated_purpose_",fileext=".json")
  jsonlite::write_json(s,purpose,auto_unbox=TRUE,null="null",digits=17)
  validated<-grrr_main(c("--contract",purpose,"--sha256",unname(tools::sha256sum(purpose)),"--dry-run"))
  ok(validated$original_RDS_deserializations==2L)
  reject(grrr_main(c("--contract",purpose,"--sha256",strrep("f",64),"--dry-run")),"purpose digest")
  grrr_main("--help");unlink(purpose);unlink(output,recursive=TRUE)
  cat(sprintf("GLOFAS_REFERENCE_RECOVERY_READER_GENERATED_PASS checks=%d original_RDS_reads=0 authentic_generated_array_reads=0\n",checks))
})
