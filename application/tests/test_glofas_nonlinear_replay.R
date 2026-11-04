# Tiny deterministic retained states only; never opens an authentic RDS object.
local({
  source("scripts/glofas_nonlinear_replay_reader.R",local=TRUE)
  checks<-0L;ok<-function(x){stopifnot(isTRUE(x));checks<<-checks+1L;invisible(TRUE)}
  reject<-function(expr,pattern=NULL) {
    error<-tryCatch({force(expr);NULL},error=function(e)e)
    ok(inherits(error,"error"));if(!is.null(pattern))ok(grepl(pattern,conditionMessage(error),fixed=TRUE))
  }
  scratch<-tempfile("gnr_generated_");dir.create(scratch)
  on.exit(unlink(scratch,recursive=TRUE),add=TRUE)
  engine<-gnr_engine(getwd(),scratch,list(max_files=64L,max_file_bytes=4*1024^2,max_total_bytes=64*1024^2))
  e<-engine$env
  cfg<-list(reservoir=list(D=1L,n=2L,standardize_inputs=TRUE,add_bias=TRUE),
    covariates=list(enabled=TRUE,variables=c("ppt","soil")),
    feature_contract=list(version="0.1",reservoir_input=list(output_lags=c(1L,2L),
      covariates=list(ppt=0L,soil=0L),internal_bias=TRUE,standardize=TRUE),
      readout=list(add_intercept=TRUE,include_reservoir_state=TRUE,include_input_block=FALSE,
        include_horizon_scaled=FALSE)))
  spec<-e$app_qdesn_reservoir_input_spec(cfg);ok(spec$m_input==4L)
  hist_dates<-as.Date("2022-12-21")+0:4;origin<-tail(hist_dates,1L);future_dates<-origin+1:3
  timeline<-data.frame(date=c(hist_dates,future_dates),ppt=seq_len(8)/10,soil=.2+seq_len(8)/100,
    ppt_role="retrospective_weather_covariate",soil_role="retrospective_weather_covariate",
    ppt_source="generated",soil_source="generated",stringsAsFactors=FALSE)
  panel<-data.frame(origin_date=hist_dates,target_date=hist_dates,horizon=0L,member=NA_character_,
    is_retrospective=TRUE,is_ensemble=FALSE,y_transformed=1:5/5,g_transformed=1:5/5+.2,
    split="train",cutoff_id="generated",stringsAsFactors=FALSE)
  attr(panel,"model_covariate_timeline")<-timeline
  qfit<-list(reservoir=list(D=1L,n=2L,n_tilde=integer(),m=4L,m_input=4L,alpha=.7,
    W=list(matrix(c(.15,.02,-.03,.1),2L)),Win=list(matrix(seq_len(10)/50-.1,nrow=2L)),
    Q=list(),Q_is_identity=logical(),act_f="tanh",act_k="identity"),
    states=list(H_all=list(matrix(c(.1,-.15,.2,-.1),nrow=2L,byrow=TRUE))),
    meta=list(reservoir_input_spec=spec,history_dates=hist_dates,m_input=4L,
      standardize_inputs=TRUE,input_bound="tanh",win_scale_global=.3,win_scale_bias=.7,
      win_scale_lags=c(1,.9,.8,1.1),lag_center=c(.2,.1,.3,.2),lag_scale=c(.8,.7,.4,.6)))
  qfit2<-qfit;qfit2$reservoir$Win[[1L]]<-qfit$reservoir$Win[[1L]]*-.7
  qfit2$meta$win_scale_global<-.4;qfit2$meta$win_scale_bias<-.8
  disc_panel<-panel;disc_panel$y_transformed<-disc_panel$g_transformed-disc_panel$y_transformed
  ens<-data.frame(origin_date=origin,target_date=rep(future_dates,each=51L),horizon=rep(1:3,each=51L),
    member=rep(sprintf("member%02d",1:51),3L),g_transformed=rep(c(.9,1,1.1),each=51L)+rep(seq_len(51)/1000,3L),
    ensemble_weight=1,y_transformed=NA_real_,stringsAsFactors=FALSE)
  center<-vapply(1:3,function(h)mean(ens$g_transformed[ens$horizon==h]),numeric(1L))
  c<-list(cfg=cfg,cfg_beta=cfg,cfg_alpha=cfg,latent_data=list(origin_date=origin,cutoff_id="generated",
      future_key=data.frame(target_date=future_dates,horizon=1:3),g_ensemble=ens),
    qfit_beta=qfit,qfit_alpha=qfit2,y_history_full=panel$y_transformed,d_history_full=disc_panel$y_transformed,
    base_panel_full=panel,base_panel_disc_full=disc_panel,feature_meta_beta=list(),feature_meta_alpha=list(),
    horizon_scale=3,feature_strategy="recursive_latent_path",discrepancy_transition_strategy="recursive_level",
    discrepancy_input_stream="discrepancy",runtime_optimization=list(compiled_future_contract=TRUE,
      active_future_jacobian=TRUE),covariate_timeline=timeline,two_block_design=TRUE,
    glofas_future_center_path=center,future_discrepancy_convention="recursive_glofas_quantile_minus_latent_reference_path")
  design<-list(future_context=c,future_builder=function(...)stop("SAVED CALLBACK EXECUTED"))
  context<-gnr_context(design,engine)
  ok(nrow(context$qfit_beta$states$H_all[[1L]])==1L)
  ok(identical(as.numeric(context$qfit_beta$states$H_all[[1L]]),as.numeric(tail(qfit$states$H_all[[1L]],1L))))
  ok(is.null(context$latent_data$g_ensemble$y_transformed))
  A<-c(.5,.6,.7);full<-gnr_factory(engine,context,"compiled_active")(A)
  ok(length(full$J_y)==3L&&ncol(full$H_y)==6L)
  value<-gnr_make_value_builder(engine,context)(A)
  ok(max(gnr_compare(full,value,FALSE))<1e-12)
  betaJ<-lapply(full$J_y,function(M)M[1:3,,drop=FALSE])
  alphaJ<-lapply(full$J_g_key,function(M)M[4:6,,drop=FALSE])
  core<-list(variational_state=list(y_future_mean=A,future_linearization=list(strategy="first_order_delta",
    y_mean=A,X_beta_future=full$X_beta_future,X_alpha_future=full$X_alpha_future,J_beta=betaJ,J_alpha=alphaJ)))
  engine$audit$factory_calls<-0L;engine$audit$value_calls<-0L
  ctl<-list(max_evaluations=20L,factory_evaluations=12L,value_evaluations=8L,
    direction_steps=c(1e-4,3e-5,1e-5),perturbation=.01,parity_tolerance=1e-10,fd_tolerance=1e-6,
    pilot_safety_factor=2,minimum_tail_seconds=30,remaining_seconds=120)
  before_rng<-if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL
  result<-gnr_replay(engine,context,core,ctl)
  ok(identical(result$status,"PASS_FEATURE_REPLAY_ONLY_NOT_POSTERIOR_ACCURACY"))
  ok(all(result$parity$pass)&&all(result$directional_finite_differences$pass)&&all(result$causality$pass))
  ok(nrow(result$directional_finite_differences)==18L)
  ok(result$factory_evaluations==12L&&result$value_evaluations==8L)
  ok(result$saved_callback_calls==0L&&result$applied_updates==0L&&identical(result$future_truth_read,FALSE))
  ok(isTRUE(result$RNG_unchanged)&&identical(before_rng,
    if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL))
  ok(length(result$metadata_serializations)>0L&&all(vapply(result$metadata_serializations,
    function(x)x$size_bytes>0&&nzchar(x$sha256),logical(1L))))
  ids<-gnr_identities(context)
  ok(nrow(ids$input_scalers)==8L&&nrow(ids$initial_states)==4L)
  ok(ids$blocks$beta$actual_meta$win_scale_global==.3&&ids$blocks$alpha$actual_meta$win_scale_bias==.8)
  theta<-1:6/10
  location<-gnr_location_callback(gnr_make_value_builder(engine,context),theta,c(.1,.2,.3))(A)
  ok(max(abs(location$reference_location-as.numeric(full$H_y%*%theta)))<1e-12)
  ok(max(abs(location$ensemble_location-as.numeric(full$H_g_key%*%theta)-c(.1,.2,.3)))<1e-12)
  jac<-gnr_location_jacobian_callback(gnr_factory(engine,context,"uncompiled_full"),theta)(A)
  ok(max(abs(jac$ensemble_location-as.numeric(full$H_g_key%*%theta)))<1e-12)
  ok(identical(dim(jac$reference_jacobian),c(3L,3L))&&all(jac$ensemble_jacobian[upper.tri(jac$ensemble_jacobian,diag=TRUE)]==0))
  bad<-design;bad$future_context$qfit_beta$reservoir$act_f<-function(x)x
  reject(gnr_context(bad,engine),"supported string activation")
  bad<-design;bad$future_context$latent_data$g_ensemble$y_transformed[1L]<-1
  reject(gnr_context(bad,engine),"future USGS")
  bad<-design;bad$future_context$latent_data$g_ensemble$ensemble_weight[1L]<-1/51
  reject(gnr_context(bad,engine),"unit weights")
  bad<-design;bad$future_context$discrepancy_transition_strategy<-"persistence_anchored_innovation"
  reject(gnr_context(bad,engine),"recursive-level")
  bad<-design;bad$future_context$qfit_beta$meta$history_dates[5L]<-origin+1L
  reject(gnr_context(bad,engine),"cutoff")
  bad<-design;bad$future_context$cfg_beta$feature_contract$readout$include_input_block<-TRUE
  reject(gnr_context(bad,engine),"reservoir-only")
  bad<-design;bad$future_context$cfg_beta$callback<-function(x)x
  reject(gnr_context(bad,engine),"callback or opaque")
  for(name in c("y","y_raw","y_transformed","y_reference","usgs_raw","future_truth")) {
    bad<-design;bad$future_context$covariate_timeline[[name]]<-NA_real_
    reject(gnr_context(bad,engine),"covariate-only")
  }
  projection<-gnr_pilot_projection(1,90,ctl)
  ok(projection$remaining_calls==19L&&projection$projected_remaining_seconds==68)
  # The old factory-only estimate would have accepted this 60-second budget;
  # accounting for all eight additional value calls must reject it.
  reject(gnr_pilot_projection(1,60,ctl),"pilot projects beyond admitted time")
  bad<-ctl;bad$max_evaluations<-168L;reject(gnr_replay(engine,context,core,bad),"bounded")
  bad<-core;bad$variational_state$future_linearization$X_beta_future[2,2]<-
    bad$variational_state$future_linearization$X_beta_future[2,2]+.01
  engine$audit$factory_calls<-engine$audit$value_calls<-0L
  reject(gnr_replay(engine,context,bad,ctl),"parity failed")
  reject(engine$env$app_qdesn_engine_function("fit"),"forbidden")
  reject(engine$env$app_qdesn_build_article_design_full(NULL),"forbidden")
  reject(engine$env$readRDS("/not_admitted.rds"),"forbidden")
  reject(gnr_plain(list(callback=function(x)x)),"callback or opaque")
  pin<-function(path,size=100,sha=strrep("a",64L))list(path=path,size_bytes=size,sha256=sha)
  s<-list(schema_version="glofas_nonlinear_replay_contract_v1",
    purpose="AUTHENTIC_MEDIAN_FEATURE_REPLAY_DIRECTIONAL_ONLY_NO_INFERENCE",nonce=strrep("a",32L),
    expires_utc="2100-01-01T00:00:00Z",source_root="/generated/source",source_commit=strrep("a",40L),
    source_tree=strrep("b",40L),source_files=list(pin("/generated/source.R")),expected_identity=gsc_identity(),
    collection=pin("/generated/accepted_producers.json"),
    input_manifest=pin("/generated/runtime/manifests/input_manifest.csv",sha=gsc_identity()$input_manifest_sha256),
    design=pin("/generated/runtime/objects/shared_truth_free_design.rds",1000,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
    median_model=pin("/generated/runtime/results/gft-al-p050/fit.rds",100,
      "f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881"),
    read_budget=list(max_payload_hash_bytes=2200,max_deserialization_bytes=1100,
      max_RDS_deserializations=2L,max_metadata_bytes=32*1024^2,max_replay_output_bytes=10*1024^2),
    limits=list(cpu_seconds=1800,wall_seconds=1800,memory_bytes=32*1024^3,output_bytes=64*1024^2,logical_cpu=26L),
    output_root="/generated/source/local_trackers/replay",metadata_scratch_root="/generated/scratch",
    metadata_serialization=list(max_files=64L,max_file_bytes=4*1024^2,max_total_bytes=32*1024^2),
    replay=ctl[setdiff(names(ctl),"remaining_seconds")],allow_original_reads=TRUE,
    allow_fresh_source_feature_replay=TRUE,allow_metadata_serialization=TRUE,allow_saved_callbacks=FALSE,
    allow_applied_updates=FALSE,allow_truth_read=FALSE,allow_refit=FALSE,allow_retuning=FALSE,
    allow_forecasting=FALSE,allow_scoring=FALSE,allow_publication=FALSE,allow_derived_context_serialization=FALSE)
  s$replay$minimum_tail_seconds<-60L
  ok(isTRUE(gnrr_scope(s)));ok(gnrr_cost(s)$original_RDS_deserializations==2L)
  for(field in c("allow_saved_callbacks","allow_applied_updates","allow_truth_read","allow_refit",
    "allow_retuning","allow_forecasting","allow_scoring","allow_publication","allow_derived_context_serialization")) {
    bad<-s;bad[[field]]<-TRUE;reject(gnrr_scope(bad),"separate nonlinear replay")
  }
  bad<-s;bad$allow_fresh_source_feature_replay<-FALSE;reject(gnrr_scope(bad))
  bad<-s;bad$read_budget$max_RDS_deserializations<-3L;reject(gnrr_scope(bad),"original read")
  bad<-s;bad$read_budget$max_payload_hash_bytes<-2000;reject(gnrr_scope(bad),"before/after")
  bad<-s;bad$median_model$sha256<-strrep("f",64L);reject(gnrr_scope(bad),"frozen two-object")
  bad<-s;bad$purpose<-"TWO_AL_RETAINED_STATES_READ_ONLY_NO_TRUTH_NO_UPDATES";reject(gnrr_scope(bad))
  bad<-s;bad$replay$max_evaluations<-168L;reject(gnrr_scope(bad),"20-call")
  bad<-s;bad$metadata_serialization$max_files<-1000L;reject(gnrr_scope(bad),"serialization")
  ok(length(gnrr_sources())==13L&&all(file.exists(gnrr_sources())))
  cat(sprintf("GLOFAS_NONLINEAR_REPLAY_GENERATED_PASS checks=%d original_RDS_reads=0 saved_callbacks=0 inference_updates=0\n",checks))
})
