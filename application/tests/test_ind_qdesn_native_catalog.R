source("scripts/ind_qdesn_native_catalog.R")
source("scripts/check_ind_qdesn_feature_replay.R")
qnc_n <- 0L
qnc_check <- function(x){stopifnot(isTRUE(x));qnc_n <<- qnc_n+1L}
qnc_reject <- function(x)qnc_check(inherits(tryCatch({force(x);NULL},error=identity),"error"))
had_rng <- exists(".Random.seed",.GlobalEnv,inherits=FALSE)
if(had_rng)old_rng <- .Random.seed
c72 <- "c72e19f345da88fc1a8175ed30bdde328eab88be"
d6 <- "d6bc4c5e47a922ea0255f3ad8d73e58f374827a0"
grid <- expand.grid(model=c("qdesn_al_rhs_ns","qdesn_exal_rhs_ns"),p=c(.05,.25,.5),
  family=c("normal","laplace","gausmix"),stringsAsFactors=FALSE)
groups <- rbind(grid,grid[1:8,])
contracts <- list()
for(g in 1:26)for(chain in 1:3) {
  row <- groups[g,];role <- if(g<=18)"forecast_mae"else"forecast_check"
  replay <- paste0("synthetic_spec_",g)
  contracts[[length(contracts)+1L]] <- list(engine="qdesn",source_commit=if(g==1)d6 else c72,
    package_version="1.0.0",refit_authorized=TRUE,
    task=list(task_id=paste0(replay,"__c",chain),replay_id=replay,chain_id=chain,
      family=row$family,p=row$p,model_variant=row$model,refit_authorized=FALSE,
      n_draws=if(g==1)1000L else 4000L,key=paste(row$family,row$p,row$model,role,sep="|")),
    config=list(inference=list(method="mcmc",likelihood_family=if(row$model=="qdesn_al_rhs_ns")"al"else"exal",
      mcmc=list(n_mcmc=20000L,n_burn=5000L,thin=1L,priors=list(beta=list(type="rhs_ns"))))))
}
inventory <- ind_qnc_requests(contracts)
qnc_check(nrow(inventory)==78L&&length(unique(inventory$replay_id))==26L)
qnc_check(attr(inventory,"native_rows_requested_not_payload_verified")==1560000L)
qnc_check(sum(inventory$source_commit==d6)==3L&&sum(inventory$historical_metric_draws==1000)==3L)
qnc_check(all(inventory$root_refit_authorized_historical)&&!any(inventory$current_refit_authorized))
for(m in list(function(x){x<-x[-1L];x},function(x){x[[1]]$task$chain_id<-2L;x},
  function(x){x[[1]]$task$refit_authorized<-TRUE;x},function(x){x[[1]]$config$inference$mcmc$n_mcmc<-4000;x},
  function(x){x[[1]]$source_commit<-c72;x},function(x){x[[1]]$task$n_draws<-4000;x},
  function(x){x[[1]]$config$inference$likelihood_family<-"exal";x}))qnc_reject(ind_qnc_requests(m(contracts)))

contract <- contracts[[1L]]
case <- as.list(inventory[1L,])
N <- 20000L
fit <- structure(list(method="mcmc",p0=.05,likelihood_family="al",
  control=list(n_mcmc=N,n_burn=5000L,thin=1L),
  samp.beta=matrix(seq(-.3,.7,length.out=N*2L),N,2L),
  samp.sigma=seq(.2,1,length.out=N),samp.gamma=rep(0,N),
  X=matrix(c(1,1,1,1,.1,.3,-.2,.7),4L,dimnames=list(NULL,c("intercept","state"))),
  beta_prior=list(type="rhs_ns",hypers=list(tau0=.01,s2=1))),class="exal_mcmc")
payload <- list(fits_fc=list(list(fit_train=list(fit=fit,
  meta=list(keep_idx=101:104,fit_meta=list(readout_spec=list(include_input=TRUE)))))))
block <- ind_qnc_extract(payload,case,contract)
qnc_check(nrow(block$beta)==N&&identical(block$beta,fit$samp.beta))
qnc_check(identical(block$sigma,fit$samp.sigma)&&identical(block$gamma,fit$samp.gamma))
qnc_check(identical(block$native_column,seq_len(N))&&identical(block$original_iteration,5000L+seq_len(N)))
qnc_check(all(block$within_model_weight==1/60000)&&abs(sum(block$within_model_weight)-1/3)<1e-12)
qnc_check(is.null(block$native_readout_names)&&identical(block$native_design_column_names,colnames(fit$X)))
qnc_check(!block$source_identity_authenticated&&!block$feature_replay_authenticated&&
  !block$posterior_target_exactness_certified&&!block$production_authorized&&!block$legacy_metric_draw_mapping_inferred)
qnc_check(block$feature_context_status=="REPLAY_FIXTURE_STILL_REQUIRED")
for(m in list(function(x){x$fits_fc[[1]]$fit_train$fit$samp.beta<-x$fits_fc[[1]]$fit_train$fit$samp.beta[1:4000,,drop=FALSE];x},
  function(x){x$fits_fc[[1]]$fit_train$fit$samp.sigma[1]<-0;x},
  function(x){x$fits_fc[[1]]$fit_train$fit$samp.gamma[1]<-.1;x},
  function(x){x$fits_fc[[1]]$fit_train$fit$control$thin<-2L;x},
  function(x){x$fits_fc[[1]]$fit_train$fit$beta_prior$type<-"ridge";x},
  function(x){x$fits_fc[[1]]$fit_train$meta$keep_idx<-1:3;x},
  function(x){x$fits_fc[[1]]$fit_train$meta$keep_idx<-c(101,102,102,104);x},
  function(x){colnames(x$fits_fc[[1]]$fit_train$fit$samp.beta)<-c("state","intercept");x},
  function(x){x$fits_fc[[2]]<-x$fits_fc[[1]];x}))qnc_reject(ind_qnc_extract(m(payload),case,contract))
missing <- payload;missing$fits_fc[[1]]$fit_train$meta$fit_meta <- NULL
qnc_check(ind_qnc_extract(missing,case,contract)$feature_context_status=="BLOCKED_MISSING_NATIVE_FEATURE_METADATA")

ref <- list(schema_version="ind_qdesn_feature_values_v1",source_commit=d6,
  fit_sha256=paste(rep("a",64),collapse=""),X_fit=fit$X,y_fit=c(.2,.3,.1,.9),keep_idx=101:104,
  fit_meta=list(readout_spec=list(include_input=TRUE,decomposition="native")),
  origin_states=list(origin_104=list(prefix_source_end=104L,layers=list(layer1=matrix(c(.1,.3),1L)))))
replay <- ref
comparison <- ind_qnc_feature_replay(ref,replay)
qnc_check(comparison$maximum_absolute_difference==0&&comparison$values_compared==14L)
qnc_check(!comparison$source_identity_authenticated&&!comparison$feature_reference_provenance_authenticated&&
  !comparison$source_reservoir_reconstructed_here&&!comparison$production_authorized)
for(m in list(function(x){x$X_fit[1]<-x$X_fit[1]+.01;x},
  function(x){x$X_fit<-x$X_fit[,2:1,drop=FALSE];x},
  function(x){x$fit_meta$readout_spec$include_input<-FALSE;x},
  function(x){x$origin_states<-list();x},
  function(x){x$origin_states[[1]]$prefix_source_end<-100L;x},
  function(x){x$origin_states[[1]]$layers[[1]][1]<-.8;x},
  function(x){x$source_commit<-c72;x},function(x){x$keep_idx<-102:105;x},
  function(x){x$forecast_truth<-1;x}))qnc_reject(ind_qnc_feature_replay(ref,m(replay)))
qnc_reject(ind_qnc_feature_replay(ref,replay,absolute_tolerance=.01))
qnc_reject(ind_qnc_feature_cli(character()))
help <- capture.output(ind_qnc_feature_cli("--help"))
qnc_check(length(help)==1L&&grepl("Usage:",help,fixed=TRUE))
fixture_dir <- tempfile("ind-qnc-synthetic-fixtures-");dir.create(fixture_dir)
rf <- file.path(fixture_dir,"reference.rds");rp <- file.path(fixture_dir,"replay.rds")
saveRDS(ref,rf);saveRDS(replay,rp)
rsha <- unname(tools::sha256sum(rf));psha <- unname(tools::sha256sum(rp))
stdout <- capture.output(cli <- ind_qnc_feature_cli(c("--reference",rf,"--reference-sha256",rsha,
  "--replay",rp,"--replay-sha256",psha)))
qnc_check(length(stdout)==1L&&!cli$production_authorized&&cli$reference_file_sha256==rsha)
qnc_reject(ind_qnc_feature_cli(c("--reference",rf,"--reference-sha256",paste(rep("0",64),collapse=""),
  "--replay",rp,"--replay-sha256",psha)))
link <- file.path(fixture_dir,"linked.rds");file.symlink(rf,link)
qnc_reject(ind_qnc_feature_cli(c("--reference",link,"--reference-sha256",rsha,
  "--replay",rp,"--replay-sha256",psha)))
unlink(fixture_dir,recursive=TRUE)
qnc_check(identical(exists(".Random.seed",.GlobalEnv,inherits=FALSE),had_rng))
if(had_rng)qnc_check(identical(.Random.seed,old_rng))
cat(sprintf("IND_QDESN_NATIVE_CATALOG_CHECKS=%d PASS; protected_reads=0 fits=0 production=FALSE\n",qnc_n))
