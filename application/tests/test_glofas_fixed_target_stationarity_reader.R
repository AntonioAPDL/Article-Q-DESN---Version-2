# Generated metadata and prior settings only. No authentic object reads.
local({
  source("scripts/glofas_fixed_target_stationarity_reader.R",local=TRUE)
  n<-0L;ok<-function(x){stopifnot(isTRUE(x));n<<-n+1L;invisible(TRUE)}
  reject<-function(expr,pattern=NULL){e<-tryCatch({force(expr);NULL},error=function(e)e)
    ok(inherits(e,"error"));if(!is.null(pattern))ok(grepl(pattern,conditionMessage(e),fixed=TRUE))}
  pin<-function(path,size=100,hash=strrep("a",64L))list(path=path,size_bytes=size,sha256=hash)
  producer<-function(id)list(task_id=id,state="accepted",numerical_gates_pass=TRUE,
    identity=c(list(task_id=id),gsc_identity(),list(rng_namespace=id,routing_id=paste0("route-",id))),
    claim_nonce=paste0("nonce-",id),output_manifest_sha256=strrep("b",64L),
    terminal=list(exit_code=0L,accounting_complete=TRUE,owner_terminated=TRUE,worker_terminated=TRUE,timed_out=FALSE),
    artifacts=lapply(c("fit.rds","forecast_quantiles.csv","raw_crossings.csv","target_receipt.json",
      "progress.csv","artifact_manifest.csv"),function(p)c(list(relative_path=p),pin(paste0("/generated/",id,"/",p)))))
  collection<-list(schema_version="glofas_same_family_accepted_collection_v1",
    status="SIXTEEN_ACCEPTED_PRODUCERS_REVERIFIED",producers=lapply(gsc_tasks(),producer),
    ledger_mutations=0L,fit_objects_loaded=0L,future_truth_read=FALSE,article_publication_authorized=FALSE)
  models<-setNames(lapply(gfr_ids(),function(id)producer(id)$artifacts[[1L]][c("path","size_bytes","sha256")]),gfr_ids())
  s<-list(schema_version="glofas_fixed_target_stationarity_contract_v1",
    purpose="MEDIAN_AL_COORDINATE_EQUATIONS_AND_TWO_CONFIGS_NO_APPLIED_UPDATES",
    nonce=strrep("a",32),expires_utc="2100-01-01T00:00:00Z",source_root="/generated/source",
    source_commit=strrep("a",40),source_tree=strrep("b",40),source_files=list(pin("/generated/source.R")),
    expected_identity=gsc_identity(),collection=pin("/generated/accepted_producers.json"),
    input_manifest=pin("/generated/runtime/manifests/input_manifest.csv",hash=gsc_identity()$input_manifest_sha256),
    design=pin("/generated/runtime/objects/shared_truth_free_design.rds",1000,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
    median_model=models$`gft-al-p050`,
    configs=setNames(lapply(gfr_ids(),function(id)pin(paste0("/generated/runtime/configs/",id,".rds"))),gfr_ids()),
    prior_export_receipt=pin("/generated/previous/FORENSIC_READ_RECEIPT.json"),
    prior_export_manifest=pin("/generated/previous/artifact_manifest.csv"),
    prior_export_terminal=pin("/generated/native_reader_v1_terminal.json"),
    prior_summaries=setNames(lapply(gfr_ids(),function(id)pin(paste0("/generated/previous/",id,"_summary.json"))),gfr_ids()),
    read_budget=list(max_payload_hash_bytes=2600,max_deserialization_bytes=1300,
      max_RDS_deserializations=4L,max_metadata_bytes=32*1024^2,max_equation_output_bytes=10*1024^2),
    limits=list(cpu_seconds=1800,wall_seconds=1800,memory_bytes=32*1024^3,output_bytes=64*1024^2,logical_cpu=26L),
    output_root="/generated/source/local_trackers/stationarity",allow_original_reads=TRUE,
    allow_coordinate_equation_evaluation=TRUE,allow_applied_updates=FALSE,allow_truth_read=FALSE,
    allow_callbacks=FALSE,allow_refit=FALSE,allow_retuning=FALSE,allow_forecasting=FALSE,allow_scoring=FALSE,
    allow_publication=FALSE)
  ok(isTRUE(gfs_scope(s)));ok(gfs_cost(s)$RDS_deserializations==4L)
  for(field in c("allow_applied_updates","allow_truth_read","allow_callbacks","allow_refit",
    "allow_retuning","allow_forecasting","allow_scoring","allow_publication")){
    bad<-s;bad[[field]]<-TRUE;reject(gfs_scope(bad),"separate stationarity purpose")}
  bad<-s;bad$allow_coordinate_equation_evaluation<-FALSE;reject(gfs_scope(bad))
  bad<-s;bad$purpose<-"TWO_AL_RETAINED_STATES_READ_ONLY_NO_TRUTH_NO_UPDATES";reject(gfs_scope(bad))
  bad<-s;bad$read_budget$max_RDS_deserializations<-3;reject(gfs_scope(bad),"four-object")
  bad<-s;bad$configs$`gft-al-p095`<-bad$configs[[1L]];reject(gfs_scope(bad),"two config")
  bad<-s;bad$configs[[1L]]$path<-"/generated/runtime/configs/protected_truth.rds";reject(gfs_scope(bad),"config and summary")
  bad<-s;bad$median_model$path<-"/generated/protected_truth.rds";reject(gfs_scope(bad),"payload")
  bad<-s;bad$read_budget$max_payload_hash_bytes<-1;reject(gfs_scope(bad),"hash and read allowance")
  manifest<-data.frame(relative_path=c("objects/shared_truth_free_design.rds",paste0("configs/",gfr_ids(),".rds")),
    size_bytes=c(1000,100,100),sha256=c(s$design$sha256,strrep("a",64),strrep("a",64)),
    role=c("truth_free_shared_design",rep("transition_task_configuration",2L)))
  summaries<-setNames(lapply(gfr_ids(),function(id)list(task_id=id,producer_identity=producer(id)$identity,
    source_model_target_sha256=gsc_identity()$posterior_target_sha256,future_truth_read=FALSE,coordinate_updates=0L)),gfr_ids())
  receipt<-list(schema_version="glofas_fixed_target_forensic_receipt_v1",
    status="TWO_AL_STATES_EXPORTED_NOT_STABILITY_OR_ACCURACY_CERTIFICATE",producer_identity=gsc_identity(),
    RDS_deserializations=3L,saved_callback_calls=0L,coordinate_updates=0L,future_truth_read=FALSE,new_fits=0L,
    publication_authorized=FALSE,input_bindings=c(list(design=s$design),models),accepted_collection=s$collection,
    input_manifest=s$input_manifest,purpose_sha256=strrep("c",64L),source_commit=strrep("d",40L))
  terminal<-list(schema_version="glofas_fixed_target_native_terminal_v1",purpose_sha256=receipt$purpose_sha256,
    source_commit=receipt$source_commit,native_exit_code=0L,owner_terminated=TRUE,worker_terminated=TRUE,
    timed_out=FALSE,original_RDS_deserializations=3L,saved_callback_calls=0L,coordinate_updates=0L,
    future_truth_read=FALSE,new_scientific_fits=0L)
  pins<-c(list(s$prior_export_receipt),s$prior_summaries)
  export_manifest<-data.frame(relative_path=vapply(pins,function(p)basename(p$path),character(1L)),
    size_bytes=100,sha256=strrep("a",64L))
  ok(isTRUE(gfs_metadata_bind(s,collection,manifest,receipt,export_manifest,terminal,summaries)))
  bad<-terminal;bad$native_exit_code<-1L;reject(gfs_metadata_bind(s,collection,manifest,receipt,export_manifest,bad,summaries),"closed successful")
  bad<-terminal;bad$purpose_sha256<-strrep("f",64L);reject(gfs_metadata_bind(s,collection,manifest,receipt,export_manifest,bad,summaries),"closed successful")
  bad<-export_manifest;bad$sha256[2L]<-strrep("f",64L);reject(gfs_metadata_bind(s,collection,manifest,receipt,bad,terminal,summaries),"hash-bound")
  bad<-manifest;bad$role[2L]<-"scoring_truth";reject(gfs_metadata_bind(s,collection,bad,receipt,export_manifest,terminal,summaries),"manifest role")
  bad<-summaries;bad[[1L]]$producer_identity$posterior_target_sha256<-strrep("f",64L)
  reject(gfs_metadata_bind(s,collection,manifest,receipt,export_manifest,terminal,bad),"accepted immutable")
  bad<-s;bad$median_model$sha256<-strrep("f",64L)
  reject(gfs_metadata_bind(bad,collection,manifest,receipt,export_manifest,terminal,summaries),"exact original inputs")
  prior_hash<-function(a)digest::digest(jsonlite::toJSON(a[c("beta_rhs","alpha_rhs","beta_ridge","prior_sigma")],
    auto_unbox=TRUE,null="null",digits=17),algo="sha256",serialize=FALSE)
  a<-list(beta_rhs=list(tau0=.02),alpha_rhs=list(tau0=.03),beta_ridge=NULL,prior_sigma=list(a=2,b=1),
    rhs=list(freeze_tau_warmup_iters=50,update_every=1,min_tau_updates=0))
  actual_state<-function(tau0)list(tau0=tau0,a_zeta=2,b_zeta=4,intercept_prec=1e-9,zeta2_fixed=NULL,update_zeta=TRUE,
    rhs_control=list(freeze_tau_warmup_iters=50,update_every=1,min_tau_updates=1))
  actual<-list(actual_prior_state=list(prior="block_rhs_ns",blocks=list(beta=list(state=actual_state(.02)),
    alpha=list(state=actual_state(.03))),prior_linear=list(length=2502,range=c(0,0))),
    source_scale_state=list(shape=c(18726.5,20826.5)))
  for(id in gfr_ids()) {
    cfg<-list(task_id=id,vb_args=a,posterior_target_sha256=gsc_identity()$posterior_target_sha256,prior_sha256=prior_hash(a))
    rows<-gfs_prior_compare(cfg,actual,id);ok(nrow(rows)==22L && all(rows$pass))
    changed<-actual;changed$actual_prior_state$blocks$alpha$state$tau0<-.04
    rows<-gfs_prior_compare(cfg,changed,id);ok(sum(!rows$pass)==1L && rows$field[!rows$pass]=="tau0")
    changed<-actual;changed$source_scale_state$shape[1L]<-2+.5*(12455+28)
    rows<-gfs_prior_compare(cfg,changed,id);ok(sum(!rows$pass)==1L)
    changed<-cfg;changed$prior_sha256<-strrep("f",64L);reject(gfs_prior_compare(changed,actual,id),"protected-prior hash")
    changed<-cfg;changed$posterior_target_sha256<-strrep("f",64L);reject(gfs_prior_compare(changed,actual,id),"frozen config")
  }
  # Omitted alpha fields inherit beta settings before constructor defaults.
  cfg<-list(task_id=gfr_ids()[1L],vb_args=a,posterior_target_sha256=gsc_identity()$posterior_target_sha256)
  cfg$vb_args$alpha_rhs<-list();cfg$prior_sha256<-prior_hash(cfg$vb_args)
  changed<-actual;changed$actual_prior_state$blocks$alpha$state$tau0<-.02
  ok(all(gfs_prior_compare(cfg,changed,cfg$task_id)$pass))
  cat(sprintf("GLOFAS_STATIONARITY_READER_GENERATED_PASS checks=%d original_RDS_reads=0 applied_updates=0\n",n))
})
