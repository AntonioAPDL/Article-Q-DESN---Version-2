# Small synthetic catalog fixtures only; never open a retained posterior.
source("scripts/ind_native_parameter_catalog.R")
source("scripts/enroll_ind_native_parameter_catalog.R")
npc_n <- 0L
npc_check <- function(x){stopifnot(isTRUE(x));npc_n <<- npc_n+1L}
npc_reject <- function(expr,text=NULL) {
  e <- tryCatch({force(expr);NULL},error=identity)
  npc_check(inherits(e,"error") && (is.null(text)||grepl(text,conditionMessage(e),fixed=TRUE)))
}
set.seed(17432);npc_rng <- .Random.seed
npc_check(ind_npc_timeout_argv_ok(c("/usr/bin/timeout","--signal=TERM","--kill-after=1s","1799s","Rscript")))
npc_check(!ind_npc_timeout_argv_ok(c("/usr/bin/timeout","--signal=TERM","--kill-after=2s","1799s","Rscript")))
npc_check(!ind_npc_timeout_argv_ok(c("/usr/bin/timeout","--signal=TERM","--kill-after=1s","1800s","Rscript")))
npc_check(!ind_npc_timeout_argv_ok(c("/usr/bin/timeout","--signal=KILL","--kill-after=1s","1799s","Rscript")))
npc_check(!ind_npc_timeout_argv_ok(c("/usr/bin/timeout","--signal=TERM","1799s","Rscript")))
npc_check(!ind_npc_timeout_argv_ok(c("/usr/bin/not_timeout","--signal=TERM","--kill-after=1s","1799s","Rscript")))
cfg <- list(train_start_source_index=8501L,train_end_source_index=9000L,
  forecast_start_source_index=9001L,forecast_end_source_index=10000L,fit_size=500L,
  period=90L,harmonics="1, 2",level0=40,slope0=.012,harmonic1_amplitude=24,
  harmonic1_phase=.35,harmonic2_amplitude=8,harmonic2_phase=-.8,
  latent_clock_start_source_index=10501L,latent_clock_mode="post_warmup_source_index",TT_warmup=2000L,
  trend_C0_scale=100,seasonal_C0_scale=1,models=list(df_value=c(.995,.99),dim_df=c(2L,4L)),
  budget=list(mcmc=list(n_burn=5000L,n_mcmc=3L,thin=1L)),
  tau=.05,model_variant="dqlm",family="normal")
series <- data.frame(t=8501:9000,y=100+sin(seq_len(500)/10))
ref <- ind_npc_reference(cfg,series)
npc_check(identical(ref$source_index,8501:9000) && identical(ref$y,series$y))
npc_check(identical(ref$FF[,1L],c(1,0,1,0,1,0)))
npc_check(identical(diag(ref$C0),c(100,100,1,1,1,1)))
npc_check(all(ref$GG[1:2,1:2]==matrix(c(1,0,1,1),2L)))
npc_check(abs(ref$m0[1L]-(40+10500*.012))<1e-9)
case <- list(task_id="synthetic_native__c02",chain_id=2L,family="normal",p=.05,
  model_variant="dqlm",source_commit="c72e19f345da88fc1a8175ed30bdde328eab88be",
  package_version="1.0.0",old_realization_reproduced=FALSE,input_hashes=list(fit="synthetic_only"))
make_payload <- function(cs=case,config=cfg) {
  list(source_commit=cs$source_commit,task=list(task_id=cs$task_id,chain_id=cs$chain_id,
    model_variant=cs$model_variant,family=cs$family,p=cs$p),config=config,
    data=list(train=data.frame(source_index=8501:9000,y=series$y)),
    fit=list(dqlm.ind=cs$model_variant=="dqlm",p0=cs$p,n.burn=5000L,n.mcmc=3L,
      y=series$y,model=list(FF=ref$FF,GG=array(rep(ref$GG,500L),c(6L,6L,500L)),
        m0=matrix(ref$m0,6L,1L),C0=ref$C0),df=ref$df,dim.df=ref$dim_df,
      samp.sigma=c(.7,1.2,2),samp.theta=array(seq_len(9000)/10000,c(6L,500L,3L)),
      samp.vts=matrix(1,500L,3L)))
}
payload <- make_payload();block <- ind_npc_extract(payload,case,ref,3L)
npc_check(identical(block$native_column,1:3) && identical(block$original_iteration,5001:5003))
npc_check(identical(block$sigma,payload$fit$samp.sigma) && all(block$gamma==0))
npc_check(all(block$within_model_weight==1/9) && abs(sum(block$within_model_weight)-1/3)<1e-15)
npc_check(block$identity$model_total_parameter_count==9L && block$identity$chains_per_model==3L)
npc_check(!block$identity$old_realization_reproduced &&
  grepl("not_DGP_series_identity",block$identity$old_realization_flag_meaning,fixed=TRUE))
npc_check(!block$old_metric_draw_mapping_inferred && !block$parameters_reestimated &&
  !block$production_authorized && !block$posterior_target_exactness_certified)
tmp <- tempfile("synthetic_native_catalog_",fileext=".rds");saveRDS(block,tmp)
npc_check(identical(readRDS(tmp),block));unlink(tmp)
excase <- case;excase$model_variant <- "exdqlm";excase$p <- .5
excase$source_commit <- "7ace6618601b7dd8d8c5fd3bd676000ba40f11e8";excase$package_version <- "1.1.1"
excfg <- cfg;excfg$model_variant <- "exdqlm";excfg$tau <- .5
ex <- make_payload(excase,excfg);ex$fit$samp.gamma <- c(-.2,0,.2)
ex$fit$samp.sts <- matrix(.5,500L,3L)
eb <- ind_npc_extract(ex,excase,ref,3L)
npc_check(identical(eb$gamma,ex$fit$samp.gamma) && identical(eb$sigma,ex$fit$samp.sigma))
npc_check(eb$identity$likelihood=="exAL" && eb$identity$source_backend=="C++ (mode=fast)")
for(mutate in list(
  function(x){x$source_commit <- "wrong";x},
  function(x){x$task$chain_id <- 1L;x},
  function(x){x$task$family <- "laplace";x},
  function(x){x$fit$dqlm.ind <- FALSE;x},
  function(x){x$config$budget$mcmc$thin <- 2L;x},
  function(x){x$fit$n.mcmc <- 2L;x},
  function(x){x$fit$y[1L] <- x$fit$y[1L]+1;x},
  function(x){x$data$train$source_index[1L] <- 8500L;x},
  function(x){x$data$train$y[1L] <- 1;x},
  function(x){x$fit$model$FF[1L] <- 2;x},
  function(x){x$fit$model$GG[1L] <- 2;x},
  function(x){x$fit$model$m0[1L] <- 2;x},
  function(x){x$fit$model$C0[1L] <- 2;x},
  function(x){x$fit$df[1L] <- .9;x},
  function(x){x$fit$samp.sigma[1L] <- -1;x},
  function(x){x$fit$samp.sigma <- c(.7,1.2);x},
  function(x){x$fit$samp.gamma <- .1;x},
  function(x){x$fit$samp.theta <- array(0,c(6L,3L,500L));x},
  function(x){x$fit$samp.theta[1L] <- NA_real_;x},
  function(x){x$fit$samp.vts <- matrix(1,3L,500L);x},
  function(x){x$fit$samp.vts[1L] <- 0;x}
))npc_reject(ind_npc_extract(mutate(payload),case,ref,3L))
bad <- ex;bad$fit$samp.gamma[1L] <- 100
npc_reject(ind_npc_extract(bad,excase,ref,3L))
bad <- ex;bad$fit$samp.sts[1L] <- -1
npc_reject(ind_npc_extract(bad,excase,ref,3L))
bad <- excase;bad$package_version <- "1.1.2"
npc_reject(ind_npc_extract(ex,bad,ref,3L))
bad <- cfg;bad$latent_clock_start_source_index <- 8501L
npc_reject(ind_npc_reference(bad,series))
bad <- series;bad$t[1L] <- 1L
npc_reject(ind_npc_reference(cfg,bad))
npc_reject(ind_npc_extract(payload,case,ref,3.1))

# Fake-purpose guard tests stop before any genuine evidence or largefile access.
help <- capture.output(ind_npc_enroll("--help"));npc_check(grepl("Usage:",help,fixed=TRUE))
npc_reject(ind_npc_enroll(character()),"length(args)")
purpose <- list(schema_version="ind_native_parameter_catalog_enrollment_v1",allow_enrollment=TRUE,
  allow_refit=FALSE,allow_forecast=FALSE,allow_scoring=FALSE,allow_production=FALSE,
  chunk_id="al_c72",cases=rep(list(list(task_id="synthetic")),27L),native_parameter_count=20000L,
  logical_cpu=26L,limits=list(cpu_seconds=1200L,wall_term_seconds=1799L,wall_kill_after_seconds=1L,
    address_space_bytes=8*1024^3,output_bytes=64*1024^2),source_commit=paste(rep("0",40),collapse=""),
  source_tree=paste(rep("0",40),collapse=""))
path <- tempfile("synthetic_native_purpose_",fileext=".json")
call <- function(x,sha=NULL) {
  jsonlite::write_json(x,path,auto_unbox=TRUE,pretty=TRUE,digits=17)
  if(is.null(sha))sha <- unname(tools::sha256sum(path))
  ind_npc_enroll(c("--contract",path,"--sha256",sha,"--execute"))
}
npc_reject(call(purpose,paste(rep("0",64),collapse="")),"bounded external catalog purpose contract")
for(mutate in list(
  function(x){x$allow_refit <- TRUE;x},function(x){x$allow_forecast <- TRUE;x},
  function(x){x$allow_scoring <- TRUE;x},function(x){x$allow_production <- TRUE;x},
  function(x){x$cases <- x$cases[1:26];x},function(x){x$native_parameter_count <- 4000L;x},
  function(x){x$chunk_id <- "qdesn";x}
))npc_reject(call(mutate(purpose)),"fixed27-fit native catalog enrollment scope")
bad <- purpose;bad$logical_cpu <- 29L
npc_reject(call(bad),"finite native catalog chunk limits")
for(k in names(purpose$limits)) {
  bad <- purpose;bad$limits[[k]] <- bad$limits[[k]]+1
  npc_reject(call(bad),"finite native catalog chunk limits")
}
npc_reject(call(purpose),"clean frozen catalog source/tree")
unlink(path)
npc_check(identical(.Random.seed,npc_rng))
cat(sprintf("IND_NATIVE_PARAMETER_CATALOG_CHECKS=%d PASS; retained_fit_reads=0 enrollments=0 fits=0\n",npc_n))
