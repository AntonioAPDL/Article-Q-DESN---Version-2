# Generated metadata/negative checks only. No real evidence/runtime/actor read.
local({
  source("scripts/mq_native_source_qualification.R",local=TRUE)
  source("scripts/qualify_mq_native_composed.R",local=TRUE)
  n<-0L;ok<-function(x){stopifnot(isTRUE(x));n<<-n+1L}
  reject<-function(expr)ok(inherits(tryCatch({force(expr);NULL},error=identity),"error"))
  pin<-function()list(path="/synthetic_only/no_actual_read",size_bytes=1,sha256=strrep("a",64L))
  unit<-list(schema_version="integrated_quantile_qualification_contract_v1",purpose="MQ_Q2_ONE_DRAW_ORIGIN",
    source_schema="mq_native_worker_v1",model_cell_id="asymmetric_laplace_tail__joint_qdesn_rhs",chain_id=1,
    source_row=1,source_draw_index=1,origin_id=1,origin_time=11000,horizons=30,inner_paths=4096,readout_slopes=20,
    tau=c(.05,.1,.25,.5,.75,.9,.95),posterior_target_sha256="45ffff64921e5985546d174cb28f44441c161fac3d13de3e8f4d65e67a17ab1c",
    rng_namespace="integrated_quantile_forecast_v1/asymmetric_laplace_tail__joint_qdesn_rhs/chain_01",
    integration_accuracy=list(method="dkw_response_cdf",alpha_per_shard=.05,max_split_absolute=.005,
      max_split_relative=.005,max_quantile_abs_error=.01,max_quantile_rel_error=.01))
  s<-list(schema_version="mq_native_source_replay_v1",purpose="NATIVE_COMPOSED_ONE_ORIGINAL_DRAW_ORIGIN",
    allow_qualification=TRUE,allow_refit=FALSE,allow_scoring=FALSE,allow_production=FALSE,allow_article=FALSE,
    allow_raw_fixture_deserialization=FALSE,allow_future_truth=FALSE,C_ABI_qualified=FALSE,
    training_paths=65536,validation_paths=262144,batch_size=128,training_path_range=c(1,65536),
    validation_path_range=c(65537,327680),validation_look_sizes=c(65536,131072,262144),total_alpha=.05,
    alpha_per_look=rep(.05/3,3),inversion_tolerance=1e-8,parity_absolute_tolerance=1e-10,
    parity_relative_tolerance=1e-10,parity_path_ids=c(1,2,63,64,127,128,4095,4096,4097,8192,16384,32768,65535,65536,65537,327680),
    rng_backend="r46_first_step",stop_before_validation_on_split_failure=TRUE,original_unit=unit,
    limits=list(cpu_seconds=1800,wall_term_seconds=1799,wall_kill_after_seconds=1,address_space_bytes=16*1024^3,
      output_bytes=256*1024^2,logical_cpu=27),source_commit=strrep("a",40),source_tree=strrep("b",40),
    origin_remote_url="git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git",published_ref="refs/heads/synthetic_only",
    actor_nonce="synthetic_only_nonce",administrative_unit_name="qdesn-synthetic-only.service",
    allow_historical_training_array_read=FALSE,prepared_reader_role="truth_free_retained_observed_prefix",
    historical_reader_role="NOT_GRANTED",expires_utc="1970-01-01T00:00:00Z")
  # Passing the pure metadata shape below is explicitly NOT execution admission.
  ok(mqns_scope(s))
  for(k in c("allow_refit","allow_scoring","allow_production","allow_article",
    "allow_raw_fixture_deserialization","allow_future_truth","C_ABI_qualified")) {
    b<-s;b[[k]]<-TRUE;reject(mqns_scope(b))
  }
  for(k in c("schema_version","purpose","rng_backend","prepared_reader_role","historical_reader_role","published_ref")) {
    b<-s;b[[k]]<-"changed";reject(mqns_scope(b))
  }
  for(k in c("training_paths","validation_paths","batch_size","total_alpha","inversion_tolerance",
    "parity_absolute_tolerance","parity_relative_tolerance")) {
    b<-s;b[[k]]<-b[[k]]*2;reject(mqns_scope(b))
  }
  for(k in c("training_path_range","validation_path_range","validation_look_sizes","alpha_per_look","parity_path_ids")) {
    b<-s;b[[k]][1L]<-b[[k]][1L]+1;reject(mqns_scope(b))
  }
  for(k in names(s$limits)){b<-s;b$limits[[k]]<-b$limits[[k]]+1;reject(mqns_scope(b))}
  for(k in c("chain_id","source_row","source_draw_index","origin_id","origin_time","horizons","readout_slopes")) {
    b<-s;b$original_unit[[k]]<-b$original_unit[[k]]+1;reject(mqns_scope(b))
  }
  b<-s;b$original_unit$rng_namespace<-"different";reject(mqns_scope(b))
  b<-s;b$original_unit$tau[1]<-.01;reject(mqns_scope(b))
  b<-s;b$allow_historical_training_array_read<-TRUE;reject(mqns_scope(b))
  b<-s;b$allow_qualification<-FALSE;reject(mqns_scope(b))
  b<-s;b$stop_before_validation_on_split_failure<-FALSE;reject(mqns_scope(b))
  b<-s;b$expires_utc<-"invalid";reject(mqns_scope(b))
  # Pure external-gate metadata cannot read an input, enroll a runtime or mint
  # an execution context. Every actor/source/reader/resource binding is exact.
  s$retained_build_receipt<-pin();s$retained_build_terminal<-pin();s$runtime_files<-list(pin())
  s$prepared_manifest<-pin();s$original_unit_contract<-pin()
  gate<-list(schema_version="mq_native_external_execution_gate_v1",
    mode="native_source_regression_qualification_v1",execution_authorized=TRUE,
    actor_nonce=s$actor_nonce,unit_name=s$administrative_unit_name,
    source_commit=s$source_commit,source_tree=s$source_tree,
    build_receipt_sha256=s$retained_build_receipt$sha256,
    retained_build_terminal_sha256=s$retained_build_terminal$sha256,runtime_inventory_sha256=mqa_hash(s$runtime_files),
    prepared_manifest_sha256=s$prepared_manifest$sha256,
    original_unit_contract_sha256=s$original_unit_contract$sha256,
    allow_historical_training_array_read=FALSE,expires_utc=s$expires_utc,limits=s$limits,
    production_authorized=FALSE,refit_authorized=FALSE,scoring_authorized=FALSE,
    article_authorized=FALSE,C_ABI_qualified=FALSE)
  ok(identical(mqns_gate_metadata(s,gate),gate))
  for(k in c("schema_version","mode","actor_nonce","unit_name","source_commit","source_tree",
    "build_receipt_sha256","retained_build_terminal_sha256","runtime_inventory_sha256","prepared_manifest_sha256",
    "original_unit_contract_sha256","expires_utc")) {
    g<-gate;g[[k]]<-"changed";reject(mqns_gate_metadata(s,g))
  }
  for(k in c("production_authorized","refit_authorized","scoring_authorized","article_authorized","C_ABI_qualified",
    "allow_historical_training_array_read")) {
    g<-gate;g[[k]]<-TRUE;reject(mqns_gate_metadata(s,g))
  }
  g<-gate;g$execution_authorized<-FALSE;reject(mqns_gate_metadata(s,g))
  g<-gate;g$limits$cpu_seconds<-g$limits$cpu_seconds+1;reject(mqns_gate_metadata(s,g))
  build<-list(source_commit=s$source_commit,source_tree=s$source_tree,purpose_sha256=strrep("d",64))
  terminal<-list(schema_version="mq_native_external_terminal_receipt_v1",actor="mq-native-build",phase="final",
    status="EXECUTION_COMPLETE_NOT_PRODUCTION",failures=list(),production_authorized=FALSE,
    article_promotion_authorized=FALSE,independently_linked_successful_stop_post=TRUE,
    stop_post_receipt_sha256=strrep("e",64),source_commit=build$source_commit,source_tree=build$source_tree,
    purpose_sha256=build$purpose_sha256,outputs=list(list(relative_path="BUILD_RECEIPT.json",
      size_bytes=s$retained_build_receipt$size_bytes,sha256=s$retained_build_receipt$sha256)))
  ok(mqns_build_terminal_metadata(s,build,terminal))
  for(k in c("schema_version","actor","phase","status","source_commit","source_tree","purpose_sha256",
    "stop_post_receipt_sha256")){t<-terminal;t[[k]]<-"changed";reject(mqns_build_terminal_metadata(s,build,t))}
  for(k in c("production_authorized","article_promotion_authorized")) {
    t<-terminal;t[[k]]<-TRUE;reject(mqns_build_terminal_metadata(s,build,t))
  }
  t<-terminal;t$failures<-list("failed");reject(mqns_build_terminal_metadata(s,build,t))
  t<-terminal;t$independently_linked_successful_stop_post<-FALSE;reject(mqns_build_terminal_metadata(s,build,t))
  t<-terminal;t$outputs[[1]]$sha256<-strrep("f",64);reject(mqns_build_terminal_metadata(s,build,t))
  t<-terminal;t$outputs[[1]]$size_bytes<-2;reject(mqns_build_terminal_metadata(s,build,t))
  t<-terminal;t$outputs<-c(t$outputs,t$outputs);reject(mqns_build_terminal_metadata(s,build,t))
  before<-mqa_rng();ok(mqns_lapack_warmup());ok(identical(before,mqa_rng()))
  # Pure phase geometry does not mint a sealed context or permit a real read.
  ctx<-list(phase="training",parity_path_ids=s$parity_path_ids)
  ok(mqns_phase_geometry(ctx,"training",1:128));ok(mqns_phase_geometry(ctx,"parity_training",c(1L,65536L)))
  for(p in c("validation","parity_validation","generated_fixture_only"))reject(mqns_phase_geometry(ctx,p,65537L))
  reject(mqns_phase_geometry(ctx,"training",65537L));reject(mqns_phase_geometry(ctx,"training",1:129))
  reject(mqns_phase_geometry(ctx,"parity_training",3L));reject(mqns_phase_geometry(ctx,"training",c(1,1)))
  ctx$phase<-"validation";ok(mqns_phase_geometry(ctx,"validation",65537:65664))
  ok(mqns_phase_geometry(ctx,"parity_validation",c(65537L,327680L)))
  reject(mqns_phase_geometry(ctx,"validation",65536L));reject(mqns_phase_geometry(ctx,"parity_validation",65538L))
  reject(mqns_context_check(ctx));reject(mqns_enrollment_context_check(ctx))
  # Old mqa source closure remains unchanged; new closure is independent.
  old<-mqa_required_sources(c("application/R/integrated_quantile_forecast.R"))
  fresh<-mqns_required_sources(c("application/R/integrated_quantile_forecast.R"))
  ok(all(old%in%fresh));ok(!"scripts/mq_native_qualification_backend.R"%in%old)
  ok(all(c("scripts/mq_native_source_qualification.R","scripts/qualify_mq_native_composed.R",
    "scripts/build_mq_native_replay.py","scripts/mq_native_external_terminal.py",
    "scripts/enroll_mq_native_runtime.R")%in%fresh))
  ok(identical(old,mqa_required_sources(c("application/R/integrated_quantile_forecast.R"))))
  # Pure pointwise regression predicate: exact .005 scientific criteria are
  # elsewhere; this does not change scalar/array parity tolerances.
  ok(mqns_compare(c(1,2),c(1,2))==0);reject(mqns_compare(c(1,2),c(1,2.01)))
  reject(mqns_compare(c(1,Inf),c(1,2)));reject(mqns_compare(matrix(1,1),1))
  # AST-only ordering proof: no authentic payload can precede fresh output,
  # while both the metadata enroller and actual actor see warmed native code.
  calls<-function(x) {
    if(!is.call(x)&&!is.expression(x))return(character())
    if(is.call(x)&&is.symbol(x[[1L]])&&as.character(x[[1L]])%in%c("[","[["))return(character())
    if(is.call(x)&&identical(x[[1L]],as.name("function")))return(calls(x[[3L]]))
    c(if(is.call(x)&&is.symbol(x[[1L]]))as.character(x[[1L]])else character(),
      unlist(lapply(as.list(x),calls),use.names=FALSE))
  }
  heads<-calls(body(mqns_main));pos<-function(x)which(heads==x)[1L]
  ok(pos("mqns_source_guard")<pos("mqnk_enroll"));ok(pos("mqnk_enroll")<pos("mqns_lapack_warmup"))
  ok(pos("mqns_lapack_warmup")<pos("mqa_runtime_guard"));ok(pos("mqa_runtime_guard")<pos("dir.create"))
  ok(pos("dir.create")<pos("mqa_verify_prepared"));ok(pos("mqa_verify_prepared")<pos("mqns_reference_arrays"))
  ok(pos("mqns_context_validation")<pos("mq_scc_init"));ok(pos("mqnk_cdf_values")<pos("mq_scc_update"))
  # Real CLI help and missing-execute paths must not reach source/runtime/input gates.
  script<-normalizePath("scripts/qualify_mq_native_composed.R",mustWork=TRUE)
  help<-system2(file.path(R.home("bin"),"Rscript"),c("--vanilla",shQuote(script),"--help"),stdout=TRUE,stderr=TRUE)
  ok(is.null(attr(help,"status"))&&any(grepl("--contract FILE --sha256 SHA --execute",help,fixed=TRUE)))
  missing<-suppressWarnings(system2(file.path(R.home("bin"),"Rscript"),c("--vanilla",shQuote(script)),stdout=TRUE,stderr=TRUE))
  ok(identical(attr(missing,"status"),1L)&&any(grepl("exact external contract/hash/execute",missing,fixed=TRUE)))
  cat(sprintf("MQ_NATIVE_SOURCE_QUALIFICATION_GUARDS_PASS checks=%d authentic_reads=0 actors=0 builds=0\n",n))
})
