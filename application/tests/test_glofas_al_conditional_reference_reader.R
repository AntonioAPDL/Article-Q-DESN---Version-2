# Generated purpose/metadata fixtures only. Never opens an original model RDS.
local({
  source("scripts/glofas_al_conditional_reference_reader.R",local=TRUE)
  checks<-0L;ok<-function(x){stopifnot(isTRUE(x));checks<<-checks+1L;invisible(TRUE)}
  reject<-function(expr,pattern=NULL){e<-tryCatch({force(expr);NULL},error=function(e)e)
    ok(inherits(e,"error"));if(!is.null(pattern))ok(grepl(pattern,conditionMessage(e),fixed=TRUE))}
  pin<-function(path,size=100,sha=strrep("a",64L))list(path=path,size_bytes=size,sha256=sha)
  prior<-function(path,receipt,summary)list(receipt=pin(file.path(path,receipt)),
    manifest=pin(file.path(path,"artifact_manifest.csv")),summary=pin(file.path(path,summary)),
    terminal=pin(paste0(path,"_native_terminal.json")))
  s<-list(schema_version="glofas_al_conditional_reference_contract_v2",
    purpose="MEDIAN_AL_FIXED_PARAMETER_CONDITIONAL_PILOT_NO_FULL_REFIT",mode="pilot",execution_mode="sequential",
    nonce=strrep("a",32L),expires_utc="2100-01-01T00:00:00Z",source_root="/generated/source",
    source_commit=strrep("a",40L),source_tree=strrep("b",40L),source_files=list(pin("/generated/source.R")),
    expected_identity=gsc_identity(),collection=pin("/generated/accepted_producers.json"),
    input_manifest=pin("/generated/runtime/manifests/input_manifest.csv",sha=gsc_identity()$input_manifest_sha256),
    design=pin("/generated/runtime/objects/shared_truth_free_design.rds",1000,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
    median_model=pin("/generated/runtime/results/gft-al-p050/fit.rds",100,
      "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881"),
    prior_replay=prior("/generated/replay","NONLINEAR_REPLAY_RECEIPT.json","replay_summary.json"),prior_pilot=NULL,
    draw_export=NULL,
    diagnostic_dependencies=list(library_root="/generated/library",versions=pin("/generated/versions.csv"),
      sources=pin("/generated/archives.csv")),
    read_budget=list(max_payload_hash_bytes=2200,max_deserialization_bytes=1100,max_RDS_deserializations=2L,
      max_metadata_bytes=64*1024^2,max_conditional_output_bytes=10*1024^2),
    limits=list(cpu_seconds=1800L,wall_seconds=1800L,memory_bytes=32*1024^3,output_bytes=64*1024^2,
      logical_cpu=26L,max_workers=1L,child_logical_cpus=list(),child_cpu_seconds=0L,
      aggregate_cpu_seconds=1800L,aggregate_memory_bytes=32*1024^3,memory_headroom_bytes=180*1024^3,
      max_draw_memory_bytes=64*1024^2),output_root="/generated/source/local_trackers/conditional",
    metadata_scratch_root="/generated/scratch",metadata_serialization=list(max_files=64L,
      max_file_bytes=4*1024^2,max_total_bytes=32*1024^2),
    conditional=list(likelihood_family="al",tau=.5,
      parameter_rule="retained_theta_mean_fixed_coefficient_covariance_zero",
      scale_rule="reciprocal_retained_inverse_scale_means_not_scale_means",
      max_total_value_evaluations=12L,max_jacobian_evaluations=301L,timing_evaluations=3L,
      value_backend="compiled_input_reference",parity_evaluations=6L,setup_value_evaluations=0L,
      timing_perturbation=.001,matched_vb=list(max_iterations=300L,max_wall_seconds=900L,tolerance=1e-8,jitter=1e-8),
      sampler=NULL,proposal_rule="retained_future_covariance_preconditioner",
      start_rule="retained_m_minus_sd_plus_sd_and_reference_at_m_minus_sd_plus_sd",
      minimum_tail_seconds=120L,pilot_safety_factor=2,
      qualification_scope="timing_and_matched_fixed_parameter_VB_only"),
    allow_original_reads=TRUE,allow_fresh_source_feature_evaluation=TRUE,allow_metadata_serialization=TRUE,
    allow_matched_fixed_parameter_vb=TRUE,allow_fixed_parameter_path_sampling=FALSE,
    allow_saved_callbacks=FALSE,allow_parameter_updates=FALSE,allow_prior_updates=FALSE,
    allow_full_parameter_refit=FALSE,allow_truth_read=FALSE,allow_retuning=FALSE,allow_scoring=FALSE,
    allow_article_changes=FALSE,allow_publication=FALSE,allow_derived_context_serialization=FALSE,
    allow_raw_draw_export=FALSE)
  ok(isTRUE(gacr_scope(s)));ok(gacr_cost(s)$original_RDS_deserializations==2L)
  for(field in c("allow_saved_callbacks","allow_parameter_updates","allow_prior_updates","allow_full_parameter_refit",
    "allow_truth_read","allow_retuning","allow_scoring","allow_article_changes","allow_publication",
    "allow_derived_context_serialization","allow_raw_draw_export")) {
    bad<-s;bad[[field]]<-TRUE;reject(gacr_scope(bad),"separate conditional")
  }
  bad<-s;bad$purpose<-"AUTHENTIC_MEDIAN_FEATURE_REPLAY_DIRECTIONAL_ONLY_NO_INFERENCE";reject(gacr_scope(bad))
  bad<-s;bad$median_model$sha256<-strrep("f",64);reject(gacr_scope(bad),"frozen truth-free")
  bad<-s;bad$conditional$likelihood_family<-"exal";reject(gacr_scope(bad))
  bad<-s;bad$conditional$tau<-.05;reject(gacr_scope(bad))
  bad<-s;bad$conditional$scale_rule<-"posterior_mean_sigma";reject(gacr_scope(bad))
  bad<-s;bad$conditional$value_backend<-"automatic";reject(gacr_scope(bad))
  bad<-s;bad$conditional$parity_evaluations<-0L;reject(gacr_scope(bad))
  bad<-s;bad$conditional$max_total_value_evaluations<-8L;reject(gacr_scope(bad))
  bad<-s;bad$conditional$max_total_value_evaluations<-12.5;reject(gacr_scope(bad))
  bad<-s;bad$conditional$max_jacobian_evaluations<-300L;reject(gacr_scope(bad))
  bad<-s;bad$read_budget$max_RDS_deserializations<-3L;reject(gacr_scope(bad))
  bad<-s;bad$read_budget$max_payload_hash_bytes<-2100;reject(gacr_scope(bad))

  sample<-s;sample$mode<-"sample";sample$purpose<-"MEDIAN_AL_FIXED_PARAMETER_FOUR_CHAIN_REFERENCE_NO_FULL_REFIT"
  sample$execution_mode<-"fork_four";sample$allow_matched_fixed_parameter_vb<-FALSE
  sample$allow_fixed_parameter_path_sampling<-TRUE
  sample$allow_raw_draw_export<-TRUE
  sample$draw_export<-list(filename="conditional_reference_draws.rds",
    role="generated_fixed_parameter_conditional_path_draws_not_full_posterior",
    max_bytes=1024^2,serialization_version=3L,numeric_array_only=TRUE)
  sample$prior_pilot<-prior("/generated/pilot","CONDITIONAL_REFERENCE_RECEIPT.json","conditional_summary.json")
  sample$limits$max_workers<-4L;sample$limits$child_logical_cpus<-as.list(26:29)
  sample$limits$child_cpu_seconds<-1800L;sample$limits$aggregate_cpu_seconds<-9000L
  sample$limits$aggregate_memory_bytes<-160*1024^3
  sample$conditional$timing_evaluations<-0L;sample$conditional$parity_evaluations<-0L
  sample$conditional$setup_value_evaluations<-1L;sample$conditional$timing_perturbation<-0
  sample$conditional["matched_vb"]<-list(NULL)
  sample$conditional$sampler<-list(warmup=500L,samples=500L,max_evaluations=1001L,max_wall_seconds=1000,
    adapt_warmup=TRUE,rhat_max=1.01,min_ess=400,max_quantile_mcse=.005,proposal_kind="blocked_preconditioned")
  sample$conditional$max_total_value_evaluations<-4005L
  sample$conditional$qualification_scope<-"coarse_path_mechanism_only_not_production_qualification"
  ok(isTRUE(gacr_scope(sample)))
  bad<-sample;bad$limits$aggregate_cpu_seconds<-8999L;reject(gacr_scope(bad),"aggregate allocation")
  bad<-sample;bad$limits$aggregate_memory_bytes<-159*1024^3;reject(gacr_scope(bad),"aggregate allocation")
  bad<-sample;bad$limits$child_logical_cpus<-as.list(c(26,26,28,29));reject(gacr_scope(bad))
  bad<-sample;bad$execution_mode<-"automatic_fallback";reject(gacr_scope(bad))
  bad<-sample;bad$conditional$max_total_value_evaluations<-4004L;reject(gacr_scope(bad))
  bad<-sample;bad$conditional$sampler$max_quantile_mcse<-.01;reject(gacr_scope(bad))
  bad<-sample;bad$prior_pilot<-NULL;reject(gacr_scope(bad))
  sequential<-sample;sequential$execution_mode<-"sequential";sequential$limits$max_workers<-1L
  sequential$limits$child_logical_cpus<-list();sequential$limits$child_cpu_seconds<-0L
  reject(gacr_scope(sequential),"four-chain conditional")
  sequential$conditional$sampler$max_evaluations<-4004L
  ok(isTRUE(gacr_scope(sequential)))
  bad<-sample;bad$allow_raw_draw_export<-FALSE;reject(gacr_scope(bad))
  bad<-sample;bad$draw_export$filename<-"fit.rds";reject(gacr_scope(bad))
  bad<-sample;bad$draw_export$numeric_array_only<-FALSE;reject(gacr_scope(bad))
  draw_dir<-tempfile("gacr_generated_draws_");dir.create(draw_dir)
  draw_scope<-sample;draw_scope$output_root<-normalizePath(draw_dir)
  draw_array<-array(0,c(500L,4L,28L));draw_array[1,1,1]<-NA_real_
  exported<-gacr_write_draws(draw_array,draw_scope)
  ok(exported$generated_array_only&&exported$missing_values==1L&&exported$size_bytes<=1024^2)
  ok(identical(readRDS(exported$path),draw_array))
  reject(gacr_write_draws(draw_array,draw_scope),"fresh owned")
  reject(gacr_write_draws(list(fit=draw_array),draw_scope),"numeric conditional-path")
  reject(gacr_write_draws(draw_array,s),"sample-only")
  unlink(draw_dir,recursive=TRUE)

  replay_receipt<-list(schema_version="glofas_nonlinear_replay_receipt_v1",
    status="PASS_FEATURE_REPLAY_ONLY_NOT_POSTERIOR_ACCURACY",purpose_sha256=strrep("c",64),
    source_commit=strrep("d",40),source_tree=strrep("e",40),producer_identity=gsc_identity(),
    input_bindings=s[c("design","median_model")],accepted_collection=s$collection,input_manifest=s$input_manifest,
    original_RDS_deserializations=2L,saved_callback_calls=0L,future_truth_read=FALSE,
    factory_evaluations=12L,value_evaluations=8L,applied_updates=0L,new_fits=0L,
    production_launch_authorized=FALSE,publication_authorized=FALSE,
    attempted_reads=lapply(s[c("design","median_model")],function(p)c(p,
      list(status="DESERIALIZED",post_read_sha256=p$sha256))))
  replay_summary<-list(status=replay_receipt$status,context_unchanged=TRUE,RNG_unchanged=TRUE,forbidden_calls=0L)
  terminal<-list(schema_version="glofas_nonlinear_replay_native_terminal_v1",
    purpose_sha256=replay_receipt$purpose_sha256,source_commit=replay_receipt$source_commit,
    source_tree=replay_receipt$source_tree,native_exit_code=0L,owner_terminated=TRUE,worker_terminated=TRUE,
    timed_out=FALSE,output_manifest_verified=TRUE,output_manifest_sha256=s$prior_replay$manifest$sha256,
    original_RDS_deserializations=2L,saved_callback_calls=0L,future_truth_read=FALSE,full_parameter_refits=0L,
    factory_evaluations=12L,value_evaluations=8L,applied_updates=0L)
  inventory<-data.frame(relative_path=c(basename(s$prior_replay$receipt$path),basename(s$prior_replay$summary$path)),
    size_bytes=c(100,100),sha256=c(strrep("a",64),strrep("a",64)))
  ok(isTRUE(gacr_prior_bind(s,replay_receipt,inventory,replay_summary,terminal)))
  bad<-terminal;bad$worker_terminated<-FALSE
  reject(gacr_prior_bind(s,replay_receipt,inventory,replay_summary,bad),"independently closed")
  bad<-terminal;bad$output_manifest_sha256<-strrep("b",64)
  reject(gacr_prior_bind(s,replay_receipt,inventory,replay_summary,bad))
  bad<-replay_summary;bad$status<-"FAIL_FEATURE_DERIVATIVE_OR_CAUSALITY"
  reject(gacr_prior_bind(s,replay_receipt,inventory,bad,terminal),"hard prerequisite")
  bad<-replay_receipt;bad$attempted_reads[[1]]$post_read_sha256<-strrep("f",64)
  reject(gacr_prior_bind(s,bad,inventory,replay_summary,terminal),"before/after")
  bad<-replay_receipt;bad$new_fits<-1L
  reject(gacr_prior_bind(s,bad,inventory,replay_summary,terminal),"no-fit")
  bad<-inventory;bad$sha256[1]<-strrep("f",64)
  reject(gacr_prior_bind(s,replay_receipt,bad,replay_summary,terminal),"manifest-bound")
  pr<-replay_receipt;pr$schema_version<-"glofas_al_conditional_reference_receipt_v1"
  pr$mode<-"pilot";pr$status<-"PILOT_COMPLETE_NOT_MCMC_OR_FULL_POSTERIOR_QUALIFICATION"
  pr$source_commit<-sample$source_commit;pr$source_tree<-sample$source_tree
  pr$conditional_reference_chains_attempted<-0L
  pt<-terminal;pt$schema_version<-"glofas_al_conditional_reference_native_terminal_v1"
  pt$source_commit<-pr$source_commit;pt$source_tree<-pr$source_tree
  pm<-inventory;pm$relative_path<-c(basename(sample$prior_pilot$receipt$path),basename(sample$prior_pilot$summary$path))
  ps<-list(mode="pilot",timing=list(value_evaluations=3L,maximum_seconds_per_evaluation=.01))
  ok(isTRUE(gacr_prior_bind(sample,pr,pm,ps,pt,"pilot")))
  pr$source_commit<-pt$source_commit<-strrep("f",40)
  reject(gacr_prior_bind(sample,pr,pm,ps,pt,"pilot"),"closed measured conditional pilot")

  lib<-Sys.getenv("R_LIBS_USER")
  versions_path<-file.path(dirname(lib),"diagnostic_library_versions.csv")
  if(nzchar(lib)&&file.exists(versions_path)) {
    versions<-read.csv(versions_path,stringsAsFactors=FALSE)
    ok(isTRUE(gacr_library(lib,versions)))
    empty<-tempfile("gacr_missing_private_");dir.create(empty)
    altered<-versions;altered$LibPath<-empty
    reject(gacr_library(empty,altered),"absent from its private library")
    unlink(empty,recursive=TRUE)
  } else message("Private dependency-path fixture NOT RUN: task-owned library not supplied.")
  ok(length(gacr_sources())==16L&&all(file.exists(gacr_sources())))
  identity<-list(blocks=list(beta=list(layer_widths=c(500L,500L,500L),
    actual_meta=list(win_scale_lags=c(.5,1,1.5))),alpha=list(layer_widths=c(500L,500L))))
  as_json<-jsonlite::fromJSON(jsonlite::toJSON(identity,auto_unbox=TRUE,digits=17),simplifyVector=FALSE)
  ok(!gst_same(identity,as_json)&&gacr_same_json(identity,as_json))
  changed<-as_json;changed$blocks$beta$layer_widths[[2L]]<-501L
  ok(!gacr_same_json(identity,changed))
  starts<-gacr_start_paths(c(4,5),diag(c(1,4)),c(1,2))
  ok(identical(unname(starts),matrix(c(3,3,5,7,0,0,2,4),2,4)))
  ok(is.list(gacr_process())&&nzchar(gacr_process()$cpus))
  if(identical(Sys.getenv("QDESN_TEST_FORK_CPU_PROBE"),"1")) {
    # Separately authorized root-only probe: four trivial workers on CPUs0:3,
    # not the authentic26:29 allocation and never payload/context readers.
    proof<-gacr_fork_dispatch(function(chain)list(status="GENERATED_PROBE_NO_PAYLOAD",chain=chain),
      cpus=0:3,child_cpu_seconds=30L)
    ok(length(proof)==4L&&length(unique(vapply(proof,function(x)x$proof$pid,integer(1L))))==4L)
    ok(all(vapply(1:4,function(i)identical(proof[[i]]$proof$cpus,as.character(i-1L)),logical(1L))))
    ok(all(vapply(proof,function(x)identical(x$result$status,"GENERATED_PROBE_NO_PAYLOAD"),logical(1L))))
  } else message("Four-worker native-affinity probe NOT RUN without explicit generated allocation.")
  gacr_main("--help")
  cat(sprintf("GLOFAS_AL_CONDITIONAL_READER_GENERATED_PASS checks=%d original_RDS_reads=0 conditional_chains=0\n",checks))
})
