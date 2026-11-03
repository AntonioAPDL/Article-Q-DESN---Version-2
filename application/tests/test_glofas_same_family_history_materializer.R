# Generated metadata/in-memory objects only. No retained RDS or real ledger read.
local({
  source("scripts/materialize_glofas_same_family_fitted_history.R",local=TRUE)
  source("application/R/glofas_family_transition.R",local=TRUE)
  n<-0L
  ok<-function(x) {stopifnot(isTRUE(x));n<<-n+1L;invisible(TRUE)}
  reject<-function(expr,pattern=NULL) {
    e<-tryCatch({force(expr);NULL},error=function(e)e)
    ok(inherits(e,"error"));if(!is.null(pattern))ok(grepl(pattern,conditionMessage(e),fixed=TRUE))
  }
  pin<-function(path,size=100)list(path=path,size_bytes=size,sha256=strrep("a",64L))
  producer<-function(id)list(task_id=id,state="accepted",numerical_gates_pass=TRUE,
    identity=c(list(task_id=id),gsc_identity(),list(rng_namespace=id,routing_id=paste0("route-",id))),
    claim_nonce=paste0("nonce-",id),output_manifest_sha256=strrep("b",64L),
    terminal=list(exit_code=0L,accounting_complete=TRUE,owner_terminated=TRUE,worker_terminated=TRUE,timed_out=FALSE),
    artifacts=lapply(c("fit.rds","forecast_quantiles.csv","raw_crossings.csv","target_receipt.json",
      "progress.csv","artifact_manifest.csv"),function(p)c(list(relative_path=p),pin(paste0("/generated/",id,"/",p)))))
  collection<-list(schema_version="glofas_same_family_accepted_collection_v1",
    status="SIXTEEN_ACCEPTED_PRODUCERS_REVERIFIED",producers=lapply(gsc_tasks(),producer),
    ledger_mutations=0L,fit_objects_loaded=0L,future_truth_read=FALSE,article_publication_authorized=FALSE,
    artifact_hash_read_bytes=1600)
  models<-setNames(lapply(collection$producers,function(p)p$artifacts[[1L]][c("path","size_bytes","sha256")]),gsc_tasks())
  models$normal_ridge<-pin("/generated/normal_ridge.rds",50)
  models$normal_rhs<-pin("/generated/normal_rhs.rds",50)
  normal<-list(prepared_design=pin("/generated/design.rds",1000),original_design=pin("/generated/original.rds",1000),
    models=setNames(lapply(c("normal_ridge","normal_rhs"),function(id)list(
      status="FIT_REUSE_AND_NEW_ANALYTIC_REPORT_VERIFIED",original_fit=models[[id]],
      original_state_contract_hash=strrep("c",64L))),c("normal_ridge","normal_rhs")),
    input_bindings=list(normal_ridge=list(fit=models$normal_ridge),normal_rhs=list(fit=models$normal_rhs)))
  scope<-function(selection="all_six_families_v1") {
    ids<-gfm_selection(selection)
    list(schema_version="glofas_same_family_fitted_history_contract_v1",
      purpose="AUTHENTIC_PREORIGIN_FITTED_QUANTILE_MATERIALIZATION_ONLY",nonce=strrep("a",32L),
      expires_utc="2100-01-01T00:00:00Z",source_root="/generated/source",source_commit=strrep("a",40L),
      source_tree=strrep("b",40L),source_files=list(pin("/generated/source.R")),selection=selection,days=30L,
      origin_date="2022-12-25",transform="log1p",collection_contract=pin("/generated/collection.json"),
      expected_identity=gsc_identity(),design=normal$prepared_design,input_manifest=pin("/generated/input.csv"),
      normal_manifest=pin("/generated/artifact_manifest.csv"),normal_receipt=pin("/generated/normal_reuse_enrollment.json"),
      normal_quantiles=pin("/generated/normal_response_quantiles.csv"),models=models[ids],
      read_budget=list(max_collector_hash_bytes=2000,max_payload_hash_bytes=10000,
        max_deserialization_bytes=10000,max_RDS_deserializations=length(ids)+1L,max_metadata_bytes=128*1024^2),
      limits=list(cpu_seconds=180,wall_seconds=180,memory_bytes=2*1024^3,output_bytes=8*1024^2,logical_cpu=28L),
      output_root="/generated/source/local_trackers/history",allow_history_read=TRUE,
      allow_truth_read=FALSE,allow_refit=FALSE,allow_retuning=FALSE,allow_forecasting=FALSE,
      allow_scoring=FALSE,allow_publication=FALSE)
  }
  s<-scope();ok(identical(gfm_scope(s),names(models)))
  fresh_test <- tempfile("glofas_history_fresh_")
  ok(gfm_fresh_output(fresh_test))
  dir.create(fresh_test);ok(!gfm_fresh_output(fresh_test))
  broken_test <- paste0(fresh_test,"_broken")
  ok(file.symlink(paste0(fresh_test,"_absent_target"),broken_test))
  ok(!gfm_fresh_output(broken_test))
  unlink(broken_test);unlink(fresh_test) # Only this test-created empty fixture.
  ok(length(gfm_scope(scope("main_figure_v1")))==8L)
  for(key in c("allow_truth_read","allow_refit","allow_retuning","allow_forecasting","allow_scoring","allow_publication")) {
    bad<-s;bad[[key]]<-TRUE;reject(gfm_scope(bad),"history-only")
  }
  for(pair in list(c("selection","best_score"),c("days",29),c("origin_date","2022-12-26"),
      c("transform","identity"),c("purpose","REFIT"),c("nonce","used"))) {
    bad<-s;bad[[pair[1L]]]<-pair[2L];reject(gfm_scope(bad))
  }
  bad<-s;bad$models<-bad$models[-1L];reject(gfm_scope(bad),"exact selected model")
  bad<-s;bad$extra<-TRUE;reject(gfm_scope(bad),"history-only")
  bad<-c(s,list(allow_truth_read=FALSE));reject(gfm_scope(bad),"duplicate")
  for(key in c("collection_contract","input_manifest","normal_manifest","normal_receipt","normal_quantiles")) {
    bad<-s;bad[[key]]$path<-"/generated/protected_truth.rds"
    reject(gfm_scope(bad),"metadata role interfaces")
  }
  for(cpu in c(24,56,48,16,50,18,31,63)) {bad<-s;bad$limits$logical_cpu<-cpu;reject(gfm_scope(bad),"one-core")}
  for(key in c("cpu_seconds","memory_bytes","output_bytes")) {
    bad<-s;bad$limits[[key]]<-Inf;reject(gfm_scope(bad),"one-core")
  }
  bound<-gfm_bind_models(s,collection,normal);ok(identical(bound,models))
  cost<-gfm_read_cost(s,collection,bound)
  ok(cost$RDS_deserializations==19L&&cost$deserialized_bytes==2700&&cost$payload_hash_bytes==7000)
  main<-scope("main_figure_v1");ok(length(gfm_bind_models(main,collection,normal))==8L)
  for(field in c("state","numerical_gates_pass")) {
    bad<-collection;bad$producers[[1L]][[field]]<-if(field=="state")"submitted" else FALSE
    reject(gfm_bind_models(s,bad,normal),"identity")
  }
  for(field in c("accounting_complete","owner_terminated","worker_terminated")) {
    bad<-collection;bad$producers[[1L]]$terminal[[field]]<-FALSE
    reject(gfm_bind_models(s,bad,normal),"accounting")
  }
  bad<-collection;bad$producers<-bad$producers[-16L];reject(gfm_bind_models(s,bad,normal),"sixteen")
  bad<-s;bad$models[[1L]]$sha256<-strrep("f",64L);reject(gfm_bind_models(bad,collection,normal),"accepted/enrolled")
  bad<-normal;bad$models$normal_ridge$original_fit<-models$normal_rhs
  reject(gfm_bind_models(s,collection,bad),"enrolled original")
  bad<-normal;bad$prepared_design$sha256<-strrep("f",64L);reject(gfm_bind_models(s,collection,bad),"prepared design")
  for(field in c("max_collector_hash_bytes","max_payload_hash_bytes","max_deserialization_bytes","max_RDS_deserializations")) {
    bad<-s;bad$read_budget[[field]]<-1;reject(gfm_read_cost(bad,collection,models),"exceed grant")
  }
  cs<-list(ledger_snapshot=pin("/generated/ledger.sqlite"),complete=pin("/generated/COMPLETE.json"),
    controller_source=pin("/generated/controller.py"),read_budget=list(max_total_artifact_bytes=2000))
  prospective<-gfm_precollect_read_cost(s,cs)
  ok(prospective$prospective_payload_hash_bytes_upper_bound==7400&&prospective$prospective_RDS_deserializations==19L)
  # Collector's own grant fits, but its hash ceiling plus selected payloads
  # exceeds the combined grant. Rejection is pure, BEFORE any collector call.
  bad<-s;bad$read_budget$max_collector_hash_bytes<-10000
  too_large<-cs;too_large$read_budget$max_total_artifact_bytes<-8000
  reject(gfm_precollect_read_cost(bad,too_large),"before collection")
  for(field in c("max_collector_hash_bytes","max_payload_hash_bytes","max_deserialization_bytes","max_RDS_deserializations")) {
    bad<-s;bad$read_budget[[field]]<-1;reject(gfm_precollect_read_cost(bad,cs),"before collection")
  }
  ok(gfm_metadata_cost(s,cs)$metadata_read_bytes_upper_bound>64*1024^2)
  bad<-s;bad$read_budget$max_metadata_bytes<-1;reject(gfm_metadata_cost(bad,cs),"metadata read budget")

  dates<-seq(as.Date("2022-11-26"),as.Date("2022-12-25"),by="day")
  xb<-cbind(intercept=1,feature=seq_len(30L)/30)
  H<-rbind(cbind(xb,discrepancy=0),cbind(xb,discrepancy=1));colnames(H)<-c("b0","b1","a0")
  design<-list(H_fixed=H,X_beta=xb,source_fixed=rep(c("Y","G"),each=30L),
    row_info_fixed=data.frame(source=rep(c("Y","G"),each=30L),
      row_role=rep(c("historical_usgs","historical_glofas_retrospective"),each=30L),
      feature_row=rep(1:30,2L),target_date=rep(dates,2L),is_future=FALSE),
    base_panel=data.frame(target_date=dates),beta_index=1:2,alpha_index=3L,two_block_design=TRUE,
    future_truth_policy="physically_excluded_from_fit_objects_scoring_sidecar_only",
    ensemble_member_weight_policy="unit_member_likelihood_v1",
    future_builder=function(...)stop("Saved callback must never execute"))
  core<-function(f,p,prior="rhs_ns")list(method="vb",likelihood_family=f,prior=prior,
    summary=list(theta_mean=c(2+p,.1,1000)),draws=list(theta=matrix(0,1,3,dimnames=list(NULL,colnames(H)))),
    variational_state=list(sigma=list(shape=c(Y=3,G=4),rate=c(Y=2,G=5))),
    vb_diagnostics=list(converged=TRUE,future_y_working_likelihood_used=TRUE,future_gaussian_prior_used=FALSE))
  result<-function(id) {
    mq<-startsWith(id,"gft-mq-");f<-if(grepl("exal",id,fixed=TRUE))"exal" else "al"
    p<-gsc_task_tau(id);blocks<-length(p)
    fit<-if(mq)list(schema_version="glofas_part4_joint_latent_v1",fit_structure="joint_adjacent_rhs",
      likelihood_family=f,converged=TRUE,tau=p,fits=lapply(p,function(z)core(f,z))) else core(f,p)
    list(schema_version="glofas_family_transition_fit_v1",task_id=id,converged=TRUE,status="converged",
      claim_nonce=producer(id)$claim_nonce,identity=producer(id)$identity,target_contract=app_glofas_family_transition_contract(),
      counts=list(horizons=28L,members=51L,historical_Y=12455L,historical_G=12455L,
        residual_jacobian_determinant=1L,future_Y=28L,future_G=1428L,quantile_blocks=blocks,
        total_future_Y=28L*blocks,total_future_G=1428L*blocks,replacement_gaussian_path_prior=FALSE),
      feature_contract=list(two_block_design=TRUE,discrepancy_input_stream="discrepancy",
        discrepancy_transition_strategy="recursive_level",reference_coefficients=1501L,discrepancy_coefficients=1001L),fit=fit)
  }
  rows<-lapply(gsc_tasks(),function(id)gfm_rows(result(id),design,id,producer(id)))
  for(id in c("normal_ridge","normal_rhs")) {
    prior<-if(id=="normal_ridge")"ridge" else "rhs_ns"
    object<-list(status="completed",likelihood_family="normal",coefficient_prior=prior,fit=core("normal",.5,prior),
      state_contract_hash=strrep("c",64L),shared_design_reference=list(state_contract_hash=strrep("c",64L),sha256=normal$original_design$sha256))
    rows[[length(rows)+1L]]<-gfm_rows(object,design,id,normal=normal)
    bad<-object;bad$shared_design_reference$sha256<-strrep("f",64L)
    reject(gfm_rows(bad,design,id,normal=normal),"state/design")
  }
  full<-do.call(rbind,rows);ok(nrow(full)==1260L&&length(unique(full$family))==6L)
  ok(all(full$quantile==expm1(full$quantile_transformed)))
  ok(all(full$time_role=="historical_fitted_conditional_quantile")&&all(!full$isotonic_adjustment))
  ok(nrow(gfm_crossings(full))==180L)
  crossing<-result("gft-mq-al")
  for(k in 1:7)crossing$fit$fits[[k]]$summary$theta_mean[1L]<-10-k
  r<-gfm_rows(crossing,design,"gft-mq-al",producer("gft-mq-al"))
  raw<-gfm_crossings(r);ok(sum(raw$raw_crossings)==180L&&all(raw$adjacent_exposure==6L))
  bad<-result("gft-al-p005");bad$claim_nonce<-"other";reject(gfm_rows(bad,design,bad$task_id,producer(bad$task_id)),"receipt")
  bad<-design;bad$H_fixed[30L,3L]<-1;reject(gfm_rows(result("gft-al-p005"),bad,"gft-al-p005",producer("gft-al-p005")),"zero discrepancy")
  cat(sprintf("GLOFAS_FITTED_HISTORY_MATERIALIZER_GENERATED_PASS checks=%d\n",n))
})
