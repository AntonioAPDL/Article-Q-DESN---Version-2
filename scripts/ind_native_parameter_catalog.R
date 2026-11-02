# Pure extraction of retained native static parameters. No file I/O or fits.
ind_npc_require <- function(ok,message) {
  if(!isTRUE(ok))stop(paste0("IND native catalog: ",message),call.=FALSE)
  invisible(TRUE)
}

ind_npc_number <- function(x,label) {
  y <- suppressWarnings(as.numeric(unlist(x,use.names=FALSE)))
  ind_npc_require(length(y)>=1L && all(is.finite(y)),paste("invalid",label));y
}

ind_npc_timeout_argv_ok <- function(argv) {
  is.character(argv) && length(argv)>=5L && !anyNA(argv) &&
    identical(basename(argv[[1L]]),"timeout") &&
    identical(argv[2:4],c("--signal=TERM","--kill-after=1s","1799s"))
}

ind_npc_reference <- function(config,series) {
  q <- ind_npc_require
  q(is.list(config) && is.data.frame(series) && all(c("y","t") %in% names(series)),
    "explicit native configuration and raw series required")
  start <- ind_npc_number(config$train_start_source_index,"training start")
  end <- ind_npc_number(config$train_end_source_index,"training end")
  q(length(start)==1L && length(end)==1L && start==8501 && end==9000 &&
    config$fit_size==500 && config$forecast_start_source_index==9001 &&
    config$forecast_end_source_index==10000,"frozen training/evaluation boundaries changed")
  indices <- if("source_index" %in% names(series))as.integer(series$source_index)else as.integer(series$t)
  q(length(indices)==nrow(series) && !anyNA(indices) && !anyDuplicated(indices),"raw source indices must be unique")
  index <- match(seq.int(start,end),indices)
  y <- as.numeric(series$y[index])
  q(length(y)==500L && !anyNA(index) && all(is.finite(y)),"complete raw training response required")
  harmonics <- if(is.character(config$harmonics))as.numeric(strsplit(config$harmonics,",",fixed=TRUE)[[1L]])else
    ind_npc_number(config$harmonics,"harmonics")
  period <- ind_npc_number(config$period,"period")
  q(length(period)==1L && period==90 && identical(harmonics,c(1,2)),"frozen trend/harmonic specification changed")
  getscalar <- function(name) {
    x <- ind_npc_number(config[[name]],name);q(length(x)==1L,paste("scalar",name,"required"));x
  }
  m0 <- c(getscalar("level0"),getscalar("slope0"),
    getscalar("harmonic1_amplitude")*cos(getscalar("harmonic1_phase")),
    getscalar("harmonic1_amplitude")*sin(getscalar("harmonic1_phase")),
    getscalar("harmonic2_amplitude")*cos(getscalar("harmonic2_phase")),
    getscalar("harmonic2_amplitude")*sin(getscalar("harmonic2_phase")))
  G <- matrix(0,6L,6L);G[1:2,1:2] <- matrix(c(1,0,1,1),2L)
  for(h in 1:2) {
    w <- harmonics[h]*2*pi/period
    k <- (2*h+1):(2*h+2)
    G[k,k] <- matrix(c(cos(w),-sin(w),sin(w),cos(w)),2L)
  }
  clock <- getscalar("latent_clock_start_source_index")
  q(identical(config$latent_clock_mode,"post_warmup_source_index") && clock==10501 &&
    config$TT_warmup==2000 && clock==start+config$TT_warmup,
    "frozen source-native initial-state clock changed")
  # Match the actual source builder's repeated propagation, not a different
  # closed-form phase convention or a differently initialized latent state.
  for(i in seq_len(as.integer(clock)-1L))m0 <- as.numeric(G%*%m0)
  C0 <- diag(c(rep(getscalar("trend_C0_scale"),2L),rep(getscalar("seasonal_C0_scale"),4L)),6L)
  q(all(diag(C0)>0),"positive source initial covariance required")
  models <- config$models
  q(is.list(models),"native discount blocks required")
  df <- ind_npc_number(models$df_value,"discount factors")
  dims <- ind_npc_number(models$dim_df,"discount dimensions")
  q(length(df)==2L && identical(dims,c(2,4)) && all(df>0 & df<=1),"invalid native discount blocks")
  D <- matrix(0,6L,6L);D[1:2,1:2] <- (1-df[1L])/df[1L];D[3:6,3:6] <- (1-df[2L])/df[2L]
  list(y=y,FF=matrix(rep(c(1,0,1,0,1,0),500L),6L,500L),GG=G,m0=m0,C0=C0,
    df=df,dim_df=as.integer(dims),df_mat=D,source_index=8501:9000,
    observed_prefix_length=500L,data_transformation="raw_y_no_scale_transform",
    builder="authenticated_polytrend2_plus_period90_harmonics1_2_repeated_clock_propagation",
    production_authorized=FALSE)
}

ind_npc_extract <- function(protected,case,reference,parameter_count=20000L,tolerance=1e-10) {
  q <- ind_npc_require
  q(is.list(protected) && is.list(case) && is.list(reference) && is.numeric(parameter_count) &&
    length(parameter_count)==1L && is.finite(parameter_count) && parameter_count>=1 &&
    parameter_count==as.integer(parameter_count) && is.numeric(tolerance) && length(tolerance)==1L &&
    is.finite(tolerance) && tolerance>0,"explicit protected fit, case and extraction geometry required")
  N <- as.integer(parameter_count)
  q(is.character(case$task_id) && length(case$task_id)==1L && nzchar(case$task_id) &&
    is.numeric(case$chain_id) && length(case$chain_id)==1L && case$chain_id %in% 1:3 &&
    is.character(case$family) && case$family %in% c("normal","laplace","gausmix") &&
    is.numeric(case$p) && length(case$p)==1L && case$p %in% c(.05,.25,.5) &&
    case$model_variant %in% c("dqlm","exdqlm"),"invalid frozen model/chain identity")
  isal <- identical(case$model_variant,"dqlm")
  expected_source <- if(isal)"c72e19f345da88fc1a8175ed30bdde328eab88be"else"7ace6618601b7dd8d8c5fd3bd676000ba40f11e8"
  version <- if(isal)"1.0.0"else"1.1.1"
  q(identical(case$source_commit,expected_source) && identical(case$package_version,version) &&
    identical(protected$source_commit,expected_source),"native source/version identity mismatch")
  task <- protected$task;cfg <- protected$config;fit <- protected$fit
  q(is.list(task) && is.list(cfg) && is.list(fit) && identical(task$task_id,case$task_id) &&
    task$chain_id==case$chain_id && identical(task$model_variant,case$model_variant) &&
    identical(task$family,case$family) && task$p==case$p && cfg$tau==case$p &&
    identical(cfg$model_variant,case$model_variant) && identical(cfg$family,case$family) &&
    identical(isTRUE(fit$dqlm.ind),isal) && fit$p0==case$p,
    "payload task, configuration or likelihood family differs from frozen case")
  q(cfg$budget$mcmc$n_burn==5000 && cfg$budget$mcmc$n_mcmc==N &&
    cfg$budget$mcmc$thin==1 && fit$n.burn==5000 && fit$n.mcmc==N,
    "burn, retention or thinning policy differs from native fit")
  same <- function(actual,expected,label,dimensions=FALSE) {
    q(is.numeric(actual) && is.numeric(expected) && length(actual)==length(expected) &&
      all(is.finite(actual)) && all(is.finite(expected)) &&
      (!dimensions || identical(dim(actual),dim(expected))) &&
      all(abs(as.numeric(actual)-as.numeric(expected))<=tolerance*pmax(1,abs(as.numeric(expected)))),
      paste("native",label,"does not match authenticated reference"))
  }
  q(length(reference$y)==500L && identical(reference$source_index,8501:9000) &&
    identical(reference$data_transformation,"raw_y_no_scale_transform"),"explicit raw training reference required")
  same(fit$y,reference$y,"training response")
  q(is.list(protected$data) && is.data.frame(protected$data$train) &&
    nrow(protected$data$train)==500L && all(c("source_index","y") %in% names(protected$data$train)),
    "native training data identity missing")
  same(as.numeric(protected$data$train$source_index),as.numeric(reference$source_index),"training indices")
  same(protected$data$train$y,reference$y,"retained training response")
  model <- fit$model;q(is.list(model),"native state-space model missing")
  same(model$FF,reference$FF,"observation vectors",TRUE)
  actual_G <- model$GG
  if(length(dim(actual_G))==3L) {
    q(identical(dim(actual_G),c(6L,6L,500L)),"native evolution-array geometry mismatch")
    for(t in 1:500)same(matrix(actual_G[,,t],6L,6L),reference$GG,"evolution matrix",TRUE)
  } else same(actual_G,reference$GG,"evolution matrix",TRUE)
  same(as.numeric(model$m0),reference$m0,"initial mean")
  same(model$C0,reference$C0,"initial covariance",TRUE)
  same(as.numeric(fit$df),reference$df,"discount factors")
  same(as.numeric(fit$dim.df),as.numeric(reference$dim_df),"discount block dimensions")
  sigma <- as.numeric(fit$samp.sigma)
  q(is.numeric(fit$samp.sigma) && length(sigma)==N && all(is.finite(sigma)) && all(sigma>0),
    "native sigma columns are incomplete or invalid")
  if(isal) {
    q(is.null(fit$samp.gamma) || (is.numeric(fit$samp.gamma) &&
      length(fit$samp.gamma) %in% c(1L,N) && all(is.finite(fit$samp.gamma)) && all(fit$samp.gamma==0)),
      "AL cannot inherit an estimated asymmetry parameter")
    gamma <- rep(0,N)
  } else {
    gamma <- as.numeric(fit$samp.gamma)
    q(is.numeric(fit$samp.gamma) && length(gamma)==N && all(is.finite(gamma)),
      "native paired gamma columns are incomplete or invalid")
    logg <- log(2)+stats::pnorm(-abs(gamma),log.p=TRUE)+.5*gamma^2
    r <- (case$p-as.numeric(gamma<0))/exp(logg)+as.numeric(gamma<0)
    q(all(is.finite(r)) && all(r>0 & r<1),"native gamma outside quantile-fixed support")
  }
  q(is.numeric(fit$samp.theta) && identical(dim(fit$samp.theta),c(6L,500L,N)) &&
    all(is.finite(fit$samp.theta)),"native state/sample pairing is incomplete or nonfinite")
  q(is.numeric(fit$samp.vts) && identical(dim(fit$samp.vts),c(500L,N)) &&
    all(is.finite(fit$samp.vts)) && all(fit$samp.vts>0),"native exponential-auxiliary pairing is invalid")
  if(!isal)q(is.numeric(fit$samp.sts) && identical(dim(fit$samp.sts),c(500L,N)) &&
    all(is.finite(fit$samp.sts)) && all(fit$samp.sts>=0),"native half-Normal pairing is invalid")
  q(is.logical(case$old_realization_reproduced) && length(case$old_realization_reproduced)==1L &&
    !is.na(case$old_realization_reproduced),"historical metric-reproduction flag must be retained")
  structure(list(schema_version="ind_native_static_parameter_catalog_block_v1",
    identity=list(task_id=case$task_id,chain_id=as.integer(case$chain_id),DGP_family=case$family,
      p=case$p,likelihood=if(isal)"AL"else"exAL",model_variant=case$model_variant,
      source_commit=expected_source,package_version=version,source_backend="C++ (mode=fast)",
      parameter_draw_identity="task_id_and_original_native_column_not_legacy_metric_label",
      native_parameter_count=N,burn_in=5000L,thin=1L,chains_per_model=3L,
      model_total_parameter_count=3L*N,within_model_equal_weight=1/(3*N),
      old_realization_reproduced=case$old_realization_reproduced,
      old_realization_flag_meaning="historical_metric_draws_agree_within_1e-6_not_DGP_series_identity",
      input_hashes=case$input_hashes),
    native_column=seq_len(N),original_iteration=5000L+seq_len(N),sigma=sigma,gamma=gamma,
    within_model_weight=rep(1/(3*N),N),observed_prefix=reference,
    old_metric_draw_mapping_inferred=FALSE,parameters_reestimated=FALSE,
    posterior_target_exactness_certified=FALSE,numerical_filter_accuracy_certified=FALSE,
    production_authorized=FALSE),class=c("ind_native_static_parameter_catalog_block","list"))
}
