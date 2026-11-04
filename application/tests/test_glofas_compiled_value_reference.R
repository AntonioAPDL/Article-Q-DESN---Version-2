# Deterministic D=1/D=2 numerical contexts only. No authentic payload is opened.
local({
  source("scripts/glofas_fixed_target_forensic_reader.R",local=TRUE)
  source("scripts/diagnostics/glofas_nonlinear_replay.R",local=TRUE)
  source("scripts/diagnostics/glofas_compiled_value_reference.R",local=TRUE)
  n<-0L;ok<-function(x){stopifnot(isTRUE(x));n<<-n+1L;invisible(TRUE)}
  reject<-function(expr,pattern=NULL){z<-tryCatch({force(expr);NULL},error=function(e)e)
    ok(inherits(z,"error"));if(!is.null(pattern))ok(grepl(pattern,conditionMessage(z),fixed=TRUE))}
  scratch<-tempfile("gcv_toy_");dir.create(scratch);on.exit(unlink(scratch,recursive=TRUE),add=TRUE)
  engine<-gnr_engine(getwd(),scratch,list(max_files=64L,max_file_bytes=4*1024^2,max_total_bytes=32*1024^2));e<-engine$env
  fixture<-function(D) {
    cfg<-list(reservoir=list(D=D,n=rep(2L,D),standardize_inputs=TRUE,add_bias=TRUE),
      covariates=list(enabled=TRUE,variables=c("ppt","soil")),
      feature_contract=list(version="0.1",reservoir_input=list(output_lags=1:2,
        covariates=list(ppt=0L,soil=0L),standardize=TRUE),
        readout=list(add_intercept=TRUE,include_reservoir_state=TRUE,include_input_block=FALSE,include_horizon_scaled=FALSE)))
    spec<-e$app_qdesn_reservoir_input_spec(cfg)
    dates<-as.Date("2022-12-21")+0:4;origin<-tail(dates,1L);future<-origin+1:3
    timeline<-data.frame(date=c(dates,future),ppt=seq_len(8)/10,soil=.2+seq_len(8)/100,
      ppt_role="retrospective_weather",soil_role="retrospective_weather",stringsAsFactors=FALSE)
    panel<-data.frame(origin_date=dates,target_date=dates,horizon=0L,member=NA_character_,
      is_retrospective=TRUE,is_ensemble=FALSE,y_transformed=1:5/5,g_transformed=1:5/5+.2,
      split="train",cutoff_id="generated",stringsAsFactors=FALSE)
    attr(panel,"model_covariate_timeline")<-timeline
    disc<-panel;disc$y_transformed<-disc$g_transformed-disc$y_transformed
    reservoir<-list(D=D,n=rep(2L,D),n_tilde=if(D==2L)1L else integer(),m=4L,m_input=4L,
      alpha=rep(.7,D),W=rep(list(matrix(c(.15,.02,-.03,.1),2L)),D),
      Win=c(list(matrix(seq_len(10)/50-.1,2L)),if(D==2L)list(matrix(c(.2,-.1),2L))else list()),
      Q=if(D==2L)list(matrix(c(1,-.5),1L))else list(),Q_is_identity=if(D==2L)FALSE else logical(),
      act_f="tanh",act_k="tanh")
    qfit<-list(reservoir=reservoir,states=list(H_all=rep(list(matrix(c(.2,-.1),1L)),D)),
      meta=list(reservoir_input_spec=spec,history_dates=dates,m_input=4L,standardize_inputs=TRUE,
        input_bound="tanh",win_scale_global=.3,win_scale_bias=.7,win_scale_lags=c(1,.9,.8,1.1),
        lag_center=c(.2,.1,.3,.2),lag_scale=c(.8,.7,.4,.6)))
    qfit2<-qfit;qfit2$reservoir$Win[[1L]]<-qfit$reservoir$Win[[1L]]*-.7
    ens<-data.frame(origin_date=origin,target_date=rep(future,each=51L),horizon=rep(1:3,each=51L),
      member=rep(sprintf("m%02d",1:51),3L),g_transformed=rep(c(.9,1,1.1),each=51L),ensemble_weight=1,
      y_transformed=NA_real_,stringsAsFactors=FALSE)
    context<-list(cfg=cfg,cfg_beta=cfg,cfg_alpha=cfg,latent_data=list(origin_date=origin,cutoff_id="generated",
        future_key=data.frame(target_date=future,horizon=1:3),g_ensemble=ens),
      qfit_beta=qfit,qfit_alpha=qfit2,y_history_full=panel$y_transformed,d_history_full=disc$y_transformed,
      base_panel_full=panel,base_panel_disc_full=disc,feature_meta_beta=list(),feature_meta_alpha=list(),
      horizon_scale=3,feature_strategy="recursive_latent_path",discrepancy_transition_strategy="recursive_level",
      discrepancy_input_stream="discrepancy",runtime_optimization=list(),covariate_timeline=timeline,
      two_block_design=TRUE,glofas_future_center_path=c(.9,1,1.1),
      future_discrepancy_convention="recursive_glofas_quantile_minus_latent_reference_path")
    gnr_context(list(future_context=context),engine)
  }
  for(D in c(1L,2L)) {
    context<-fixture(D);context_hash<-gnr_hash(context)
    A<-c(.5,.6,.7);B<-A+c(.02,-.01,.03)
    compiled<-gcv_make_value_builder(engine,context,max_evaluations=9L)
    uncached<-gnr_make_value_builder(engine,context)
    full<-gnr_factory(engine,context,"compiled_active")
    first<-NULL
    for(i in 1:3) {
      y<-list(A,B,A)[[i]];v<-compiled(y);u<-uncached(y);f<-full(y)
      ok(max(gnr_compare(v,u,FALSE))<1e-12)
      ok(max(gnr_compare(v,f,FALSE))<1e-12)
      if(i==1L)first<-v
      if(i==3L)ok(max(gnr_compare(first,v,FALSE))==0)
    }
    meta<-gcv_diagnostics(compiled)
    ok(meta$calls==3L&&meta$cache_builds==2L&&meta$cache_reuses==4L)
    ok(meta$path_dependent_values_checked>0L&&meta$static_values_checked>0L)
    ok(meta$saved_callback_calls==0L&&meta$original_file_reads==0L&&meta$random_weight_generations==0L)
    ok(identical(gnr_hash(context),context_hash)&&!isTRUE(meta$production_default_changed))
    # Independent fresh private caches and the existing total-location adapter.
    fresh<-gcv_make_value_builder(engine,context,max_evaluations=1L)
    ok(max(gnr_compare(first,fresh(A),FALSE))==0)
    reject(fresh(B),"evaluation cap")
    theta<-seq_len(ncol(first$H_y))/10
    loc<-gnr_location_callback(compiled,theta)(A)
    ok(max(abs(loc$reference_location-as.numeric(first$H_y%*%theta)))<1e-12)
    ok(max(abs(loc$ensemble_location-as.numeric(first$H_g_key%*%theta)))<1e-12)
    pilot_builder<-gcv_make_value_builder(engine,context,max_evaluations=5L)
    pilot<-gcv_performance_pilot(pilot_builder,A,B,remaining_seconds=60,remaining_evaluations=2L)
    ok(pilot$calls==3L&&pilot$diagnostics$calls==3L&&pilot$A_B_A_max_abs_difference==0)
    ok(length(pilot$latency_seconds)==3L&&all(pilot$latency_seconds>=0)&&isTRUE(pilot$remaining_budget_sufficient))
    ok(!pilot$production_launch_authorized&&!pilot$future_truth_read&&pilot$coordinate_updates==0L)
    reject(gcv_performance_pilot(pilot_builder,A,B,60,1L),"fresh builder")
    reject(gcv_performance_pilot(gcv_make_value_builder(engine,context,3L),A,B,60,1L),"allowance")
    reject(gcv_make_value_builder(engine,context,Inf),"finite compiled-value")
    bad<-context;bad$qfit_beta$reservoir$act_f<-function(x)x
    reject(gcv_make_value_builder(engine,bad,3L),"string activation")
    bad<-context;bad$covariate_timeline$y_transformed<-NA_real_
    reject(gcv_make_value_builder(engine,bad,3L),"covariate-only")
  }
  ok(engine$audit$forbidden_calls==0L&&!length(list.files(scratch,all.files=TRUE,no..=TRUE)))
  cat(sprintf("GLOFAS_COMPILED_VALUE_GENERATED_PASS checks=%d original_RDS_reads=0 production_default_changes=0\n",n))
})
