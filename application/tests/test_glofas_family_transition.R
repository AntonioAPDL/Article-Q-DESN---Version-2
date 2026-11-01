# Tiny synthetic fixtures only; no production source runtime or fit is read.
if (!exists("app_fit_latent_path_al_vb_core",mode="function")) {
  source("application/scripts/_glofas_unit_member_bootstrap.R")
}
source("application/R/glofas_family_transition.R")
gft_checks <- 0L
gft_check <- function(ok) {
  stopifnot(isTRUE(ok)); gft_checks <<- gft_checks+1L
}
gft_reject <- function(expr,pattern=NULL) {
  error <- tryCatch({force(expr);NULL},error=function(e)e)
  gft_check(inherits(error,"error"))
  if (!is.null(pattern)) {
    if (!grepl(pattern,conditionMessage(error))) stop("Unexpected rejection: ",conditionMessage(error))
    gft_check(TRUE)
  }
}
contract <- app_glofas_family_transition_contract()
gft_check(!contract$allow_launch && !contract$replacement_gaussian_path_prior)
gft_check(contract$future_Y_factors_per_level==28L && contract$future_G_factors_per_level==1428L)
gft_check(!contract$extra_response_noise)
tasks <- app_glofas_family_transition_tasks()
gft_check(nrow(tasks)==16L && !anyDuplicated(tasks$task_id))
gft_check(sum(tasks$model_class=="independent")==14L)
gft_check(tasks$dependencies[tasks$task_id=="gft-al-p050"]=="")
gft_check(tasks$dependencies[tasks$task_id=="gft-al-p005"]=="gft-al-p020")
gft_check(tasks$dependencies[tasks$task_id=="gft-al-p095"]=="gft-al-p080")
gft_check(tasks$dependencies[tasks$task_id=="gft-exal-p005"]=="gft-al-p005")
gft_check(length(strsplit(tasks$dependencies[tasks$task_id=="gft-mq-al"],"|",fixed=TRUE)[[1L]])==7L)

gft_builder <- local({
  dates <- as.Date("2026-01-06")+0:1
  function(y) {
    Xb <- cbind(beta_intercept=1,beta_lag=c(.4,y[1L]))
    Xa <- cbind(alpha_intercept=1,alpha_lag=c(-.2,1.2-y[1L]))
    list(H_y=cbind(Xb,matrix(0,2L,2L)),H_g_key=cbind(Xb,Xa),
      g_future_index=rep(1:2,each=2L),
      J_y=list(matrix(0,4L,2L),matrix(c(0,1,0,0,0,0,0,0),4L,2L)),
      J_g_key=list(matrix(0,4L,2L),matrix(c(0,1,0,-1,0,0,0,0),4L,2L)),
      z_g=c(1,1.2,1.1,1.3),weight_g=rep(1,4L),weight_y=rep(1,2L),
      row_info_y=data.frame(source="Y",future_index=1:2,target_date=dates,horizon=1:2),
      row_info_g=data.frame(source="G",future_index=rep(1:2,each=2L),
        target_date=rep(dates,each=2L),horizon=rep(1:2,each=2L),member=rep(c("m1","m2"),2L)),
      discrepancy_baseline_future=c(0,0))
  }
})
X <- cbind(intercept=1,lag=c(.1,.2,.3,.4))
src <- factor(rep(c("Y","G"),each=nrow(X)),levels=c("Y","G"))
toy <- list(z_fixed=c(.2,.4,.6,.8,.5,.7,.9,1.1),
  H_fixed=app_make_augmented_discrepancy_design(rbind(X,X),src,rbind(X,X)),
  weight_fixed=rep(1,8L),source_fixed=src,
  row_info_fixed=data.frame(source=src,feature_row=rep(1:4,2L)),X_beta=X,X_alpha=X,
  future_builder=gft_builder,future_key=data.frame(target_date=as.Date("2026-01-06")+0:1,horizon=1:2),
  y_future_init=c(.9,1),beta_index=1:2,alpha_index=3:4,intercept_index=c(1L,3L),
  discrepancy_baseline_fixed=rep(0,4L),
  future_truth_policy="physically_excluded_from_fit_objects_scoring_sidecar_only",
  feature_strategy="recursive_latent_path",ensemble_member_weight_policy="unit_member_likelihood_v1",
  design_version="family_transition_synthetic_v1",fit_id="synthetic",model_id="synthetic")
frozen_toy <- toy
toy <- app_glofas_family_transition_design(toy,synthetic=TRUE)
gft_check(identical(toy$H_fixed,frozen_toy$H_fixed) && identical(toy$z_fixed,frozen_toy$z_fixed))
counts <- app_glofas_family_transition_validate_design(toy,synthetic=TRUE)
gft_check(counts$future_Y==2L && counts$future_G==4L && counts$historical_Y==4L && counts$historical_G==4L)
gft_reject(app_glofas_family_transition_validate_design(toy),"H=28")
bad <- toy; bad$weight_fixed[1L]<-.5
gft_reject(app_glofas_family_transition_validate_design(bad,synthetic=TRUE),"unit")
bad <- toy; bad$future_builder <- function(y) {
  out <- gft_builder(y);out$H_y[1L,2L]<-y[1L];out$H_g_key[1L,2L]<-y[1L];out
}
gft_reject(app_glofas_family_transition_validate_design(bad,synthetic=TRUE),"Actual future builder")
bad <- toy; bad$future_builder <- function(y) {
  out <- gft_builder(y);out$J_g_key[[1L]][2L,1L]<-1;out
}
gft_reject(app_glofas_family_transition_validate_design(bad,synthetic=TRUE),"strictly causal")
bad <- toy; bad$future_builder <- function(y) {
  out <- gft_builder(y);out$H_g_key[,1L]<-out$H_g_key[,1L]+y;out
}
gft_reject(app_glofas_family_transition_validate_design(bad,synthetic=TRUE),"reference readout")

# The residual transform has a unit triangular Jacobian, even with nonlinear lags.
residual <- function(y) c(y[1L]-.4,y[2L]-sin(y[1L]))
y <- c(.2,.3);eps <- 1e-6
J <- sapply(1:2,function(j) {d<-rep(0,2);d[j]<-eps;(residual(y+d)-residual(y-d))/(2*eps)})
gft_check(abs(det(J)-1)<1e-8 && abs(J[1L,2L])<1e-12)
# Exact target algebra: normalized source-Y transitions integrate to one with
# member factors removed, so the historical parameter target is unchanged.
dal <- function(x,p=.25,sigma=.7) p*(1-p)/sigma*exp(-ifelse(x>=0,p*x,(p-1)*x)/sigma)
for (mu in c(-1,.3,2)) gft_check(abs(integrate(function(x) dal(x-mu),-Inf,Inf)$value-1)<1e-6)
for (p in c(.05,.5,.95)) gft_check(abs(integrate(function(x) dal(x,p=p),-Inf,Inf)$value-1)<1e-6)
inner <- function(y1) vapply(y1,function(a) integrate(function(b) dal(b-sin(a)),-Inf,Inf)$value,numeric(1L))
gft_check(abs(integrate(function(a) dal(a-.4)*inner(a),-Inf,Inf,subdivisions=200L)$value-1)<2e-5)
# At unit weight the ordinary AL augmentation has its original marginal.
constants <- app_latent_al_constants(.25)
for (r in c(-.8,.2,1.3)) {
  marginal <- integrate(function(v) stats::dnorm(r,constants$A*v,
    sqrt(constants$B*.7*v))*stats::dexp(v,rate=1/.7),0,Inf)$value
  gft_check(abs(marginal-dal(r))<1e-6)
}

# RHS shape is (penalized slopes+1)/2, independently of source scale counts.
rhs <- app_latent_rhs_state_init(3L,1L,list(tau0=1),list(freeze_tau_warmup_iters=0L,min_tau_updates=0L))
updated <- app_latent_rhs_state_update(rhs,c(0,.2,.3),diag(.1,3),iter=1L,update_global=TRUE)
second <- c(.14,.19)
lambda_inv <- 1/(1+.5*second)
expected <- ((2+1)/2)/(1+.5*sum(second*lambda_inv))
gft_check(abs(updated$e_inv_tau2-expected)<1e-12)
args <- list(max_iter=4L,min_iter_elbo=3L,tol=1e-10,n_draws=4L,
  prior_sigma=list(a=2,b=1),beta_rhs=list(tau0=1,a_zeta=2,b_zeta=4),
  alpha_rhs=list(tau0=.1,a_zeta=2,b_zeta=4),
  rhs=list(freeze_tau_warmup_iters=2L,update_every=1L,min_tau_updates=1L),
  freeze_beta_warmup_iters=1L,min_beta_updates=2L,
  quadrature_nodes=c(4L,6L),quadrature_tolerance=1e-4)
fresh <- app_glofas_family_transition_controls(args,controls=args[c("max_iter","min_iter_elbo")])
gft_check(identical(fresh$beta_rhs,args$beta_rhs) && identical(fresh$prior_sigma,args$prior_sigma))
gft_check(is.null(fresh$future_gaussian_prior) && is.null(fresh$warm_start) && !fresh$checkpoint$enabled)
gft_reject(app_glofas_family_transition_fit(toy,tasks[4L,],fresh),"verified source-bound")
al <- app_glofas_family_transition_fit(toy,tasks[tasks$task_id=="gft-al-p050",],fresh,
  seed=31L,synthetic=TRUE)
gft_check(al$fit$vb_diagnostics$future_y_working_likelihood_used && !al$fit$vb_diagnostics$future_gaussian_prior_used)
gft_check(al$fit$vb_diagnostics$beta_update_count==3L)
gft_check(al$fit$vb_diagnostics$freeze_beta_warmup_iters==1L)
gft_check(al$fit$variational_state$prior$blocks$beta$state$rhs_control$freeze_tau_warmup_iters==2L)
gft_check(al$fit$variational_state$prior$blocks$beta$state$first_tau_update_iter==3L)
gft_check(all(al$fit$variational_state$sigma$shape==2+1.5*c(Y=6,G=8)))
gft_check(any(abs(al$fit$summary$theta_cov[1:2,3:4])>1e-12))
init <- app_gft_moment_initializer(al$fit,toy)
gft_check(is.null(init$sigma_state) && is.null(init$prior) && is.null(init$iterations))
exal <- app_glofas_family_transition_fit(toy,tasks[tasks$task_id=="gft-exal-p050",],fresh,
  dependency_fits=list(al$fit),seed=32L,synthetic=TRUE)
gft_check(exal$fit$vb_diagnostics$future_y_working_likelihood_used && !exal$fit$vb_diagnostics$future_gaussian_prior_used)
gft_check(identical(exal$fit$vb_diagnostics$scale_shape_method,"source_partitioned_structured_v_quadrature"))
gft_check(all(is.finite(exal$fit$summary$theta_cov)))
# Full within-family MQ worker wiring is exercised on a tiny two-horizon fixture.
# Repeated moments here are initial values only, not simulated evidence.
mq_args <- modifyList(fresh,list(joint_outer_max_iter=1L,joint_outer_min_iter=1L,
  joint_inner_max_iter=2L,joint_inner_min_iter=1L,joint_outer_tol=1e-3,
  joint_rhs_tol=1e-3,joint_rhs_freeze_outer_iters=0L,joint_rhs_min_tau_updates=0L,
  joint_require_post_release=FALSE,joint_terminal_consecutive_passes=1L,
  rhs=list(freeze_tau_warmup_iters=0L,update_every=1L,min_tau_updates=0L)))
mq <- app_glofas_family_transition_fit(toy,tasks[tasks$task_id=="gft-mq-al",],mq_args,
  dependency_fits=rep(list(al$fit),7L),seed=33L,synthetic=TRUE)
gft_check(length(mq$fit$fits)==7L && nrow(mq$forecast_quantiles)==14L)
gft_check(all(vapply(mq$fit$fits,function(x) isTRUE(x$vb_diagnostics$future_y_working_likelihood_used),logical(1L))))
gft_check(mq$fit$previous_outer_iterations==0L && mq$fit$continuation_count==0L)
gft_check(mq$fit$joint_inner_workers==1L)
mq_exal <- app_glofas_family_transition_fit(toy,tasks[tasks$task_id=="gft-mq-exal",],mq_args,
  dependency_fits=rep(list(exal$fit),7L),seed=34L,synthetic=TRUE)
gft_check(length(mq_exal$fit$fits)==7L && nrow(mq_exal$forecast_quantiles)==14L)
gft_check(all(vapply(mq_exal$fit$fits,function(x) isTRUE(x$vb_diagnostics$future_y_working_likelihood_used) &&
  !isTRUE(x$vb_diagnostics$future_gaussian_prior_used),logical(1L))))
gft_check(mq_exal$counts$total_future_Y==14L && mq_exal$counts$total_future_G==28L)
q <- app_glofas_family_transition_quantiles(al$fit,.95,toy$future_key$target_date)
gft_check(max(abs(q$quantile_transformed-(al$fit$summary$y_future_mean+
  sqrt(diag(al$fit$summary$y_future_cov))*qnorm(.95))))<1e-12)
gft_check(max(abs(q$quantile-expm1(q$quantile_transformed)))<1e-12)
gft_check(!any(q$extra_response_noise_added) && !any(q$quantile_functional_credible_interval))
# Scoring the readout at the mean path is not substituted for the path marginal.
probe <- toy$future_builder(al$fit$summary$y_future_mean)
readout <- as.numeric(probe$H_y%*%al$fit$summary$theta_mean)
gft_check(max(abs(q$quantile_transformed-readout))>1e-5)
grid <- rbind(transform(q,tau=.05,quantile_transformed=c(1,2)),
  transform(q,tau=.95,quantile_transformed=c(0,3)))
crossings <- app_glofas_family_transition_crossings(grid)
gft_check(crossings$raw_crossing_pairs==1L && crossings$adjacent_comparisons==2L && !crossings$adjustment_applied)
gft_check(!app_glofas_family_transition_normal_reuse(list(),list())$reusable)
identity <- setNames(rep(list(paste(rep("a",64),collapse="")),8L),
  app_glofas_family_transition_normal_reuse(list(),list())$required_identity_fields)
gft_check(app_glofas_family_transition_normal_reuse(identity,identity)$reusable)
wrong <- identity;wrong$reporting_sha256<-paste(rep("b",64),collapse="")
gft_check(!app_glofas_family_transition_normal_reuse(identity,wrong)$reusable)

# Numerical damping is bounded on this fixture and never a hidden Gaussian prior.
mom <- app_latent_row_moments(toy,al$fit$summary$y_future_mean,al$fit$summary$y_future_cov,
  al$fit$summary$theta_mean,al$fit$summary$theta_cov,strategy="streamed_grouped")
delta <- function(jitter) app_latent_update_future_gaussian_delta(mom,
  al$fit$summary$y_future_mean,al$fit$summary$theta_mean,al$fit$summary$theta_cov,
  al$fit$variational_state$v$inv_mean,al$fit$variational_state$sigma,
  app_latent_al_constants(.5),jitter=jitter,future_gaussian_prior=NULL,
  include_future_y_working_likelihood=TRUE)
delta_a <- delta(1e-8);delta_b <- delta(1e-10)
gft_check(max(abs(delta_a$mean-delta_b$mean))<1e-6 && max(abs(delta_a$cov-delta_b$cov))<1e-6)
gft_check(max(abs(diag(delta_a$precision-delta_b$precision)-(1e-8-1e-10)))<1e-10)
# Retain the covariance contribution E[h(Y)Y], not only E[h(Y)]E[Y].
gft_check(abs(mom$future$b_y[[2L]][2L]-mom$future$H_y[2L,2L]*
  al$fit$summary$y_future_mean[2L]-al$fit$summary$y_future_cov[1L,2L])<1e-10)

tmp <- tempfile("gft_test_");dir.create(tmp)
dir.create(file.path(tmp,"results"))
nonce<-strrep("a",48L)
namespace_request<-list(input_root=tmp,output_root=file.path(tmp,"results","gft-al-p050",nonce),
  task_id="gft-al-p050",routing_id="synthetic_route",host="muscat")
namespace_claim<-c(namespace_request[c("output_root","task_id","routing_id","host")],
  list(verified=TRUE,claim_nonce=nonce))
namespace<-app_gft_output_namespace(namespace_request,namespace_claim)
gft_check(identical(namespace$path,namespace_request$output_root) && !dir.exists(namespace$parent))
wrong_namespace<-namespace_request;wrong_namespace$output_root<-file.path(tmp,"unrelated")
gft_reject(app_gft_output_namespace(wrong_namespace,namespace_claim),"OUTPUT_NAMESPACE")
outside_claim<-namespace_claim;outside_claim$output_root<-wrong_namespace$output_root
gft_reject(app_gft_output_namespace(wrong_namespace,outside_claim),"prepared task/nonce")
wrong_claim<-namespace_claim;wrong_claim$routing_id<-"stale_route"
gft_reject(app_gft_output_namespace(namespace_request,wrong_claim),"exact verified ticket")
gft_reject(app_gft_verify_claim("",list(host="not_the_actual_host"),"","",getwd(),""),"Worker host")
if (strsplit(tolower(Sys.info()[["nodename"]]),".",fixed=TRUE)[[1L]][1L] %in%
    c("muscat","jerez","hummingbird")) {
  gft_reject(app_gft_verify_claim("",list(host="hummingbird"),"","",getwd(),""),"allocated compute node")
}
budget_root<-file.path(tmp,"budget");dir.create(budget_root)
payload<-list(synthetic=TRUE,values=1:10)
blob<-serialize(payload,NULL,version=3L)
gft_reject(app_gft_output_precheck(payload,budget_root,32,list(progress_bytes=16,
  runtime_log_bytes=16,metadata_bytes=16)),"OUTPUT_BUDGET")
gft_reject(app_gft_bounded_write(blob,file.path(budget_root,"oversize.rds"),budget_root,
  length(blob)-1L),"exact serialized")
gft_check(!file.exists(file.path(budget_root,"oversize.rds")))
app_gft_bounded_write(blob,file.path(budget_root,"fixture.rds"),budget_root,length(blob)+1024L)
gft_check(identical(readRDS(file.path(budget_root,"fixture.rds")),payload))
gft_check(app_gft_output_usage(budget_root)==length(blob))
gft_reject(app_gft_bounded_write(blob,file.path(budget_root,"fixture.rds"),budget_root,
  length(blob)*3L),"overwrite")
gft_reject(app_gft_bounded_write(blob,file.path(budget_root,"second.rds"),budget_root,
  length(blob)+100L,reserve=101L),"remaining cap")
gft_check(!file.exists(file.path(budget_root,"second.rds")))
writeLines("fixture",file.path(tmp,"input.txt"))
mp <- file.path(tmp,"manifest.csv")
app_write_csv(app_gft_manifest(file.path(tmp,"input.txt"),"synthetic_fixture",root=tmp),mp)
gft_check(nrow(app_gft_verify_manifest(mp,app_sha256_file(mp),root=tmp))==1L)
if (.Platform$OS.type=="unix") {
  dir.create(file.path(tmp,"real"))
  writeLines("fixture",file.path(tmp,"real/data.txt"))
  file.symlink(file.path(tmp,"real"),file.path(tmp,"linked_parent"))
  symlink_manifest<-data.frame(relative_path="linked_parent/data.txt",size_bytes=8L,
    sha256=app_sha256_file(file.path(tmp,"real/data.txt")),role="synthetic_fixture")
  symlink_manifest_path<-file.path(tmp,"symlinks.csv")
  app_write_csv(symlink_manifest,symlink_manifest_path)
  gft_reject(app_gft_verify_manifest(symlink_manifest_path,app_sha256_file(symlink_manifest_path),root=tmp),"Symlink")
}
writeLines("changed",file.path(tmp,"input.txt"))
gft_reject(app_gft_verify_manifest(mp,app_sha256_file(mp),root=tmp),"Frozen input")
gft_reject(app_gft_check_authorization(list(),file.path(tmp,"missing.json"),"",getwd()),"authorization")
auth_path <- file.path(tmp,"authorization.json")
identity_names <- c("source_commit","source_tree","source_manifest_sha256",
  "posterior_target_sha256","input_manifest_sha256","task_manifest_sha256")
identity_values <- lapply(identity_names,function(k) paste(rep("a",if(k %in% c("source_commit","source_tree"))40L else 64L),collapse=""))
names(identity_values)<-identity_names
request <- c(identity_values,list(task_id="gft-al-p050",host="muscat",
  resource_budget=list(max_threads=1L,max_memory_mb=256L,max_wall_seconds=60L,max_output_bytes=1048576L)))
authorization <- c(identity_values,list(schema_version="forecast_transition_authorization_v1",
  allow_launch=FALSE,approved_by="synthetic_fixture_only",expires_utc="2099-01-01T00:00:00Z",
  allowed_task_ids=list("gft-al-p050"),allowed_hosts=list("muscat"),allowed_operations=list("dispatch")))
app_write_json(authorization,auth_path)
gft_reject(app_gft_check_authorization(request,auth_path,app_sha256_file(auth_path),getwd()),"disabled")
authorization$allow_launch<-TRUE
app_write_json(authorization,auth_path)
gft_check(isTRUE(app_gft_check_authorization(request,auth_path,app_sha256_file(auth_path),getwd())$allow_launch))
wrong_request<-request;wrong_request$posterior_target_sha256<-paste(rep("b",64L),collapse="")
gft_reject(app_gft_check_authorization(wrong_request,auth_path,app_sha256_file(auth_path),getwd()),"posterior_target")
authorization$expires_utc<-"2000-01-01T00:00:00Z";app_write_json(authorization,auth_path)
gft_reject(app_gft_check_authorization(request,auth_path,app_sha256_file(auth_path),getwd()),"expired")
request_path<-file.path(tmp,"template.json")
app_write_json(list(schema_version="glofas_family_transition_request_v1",allow_launch=FALSE),request_path)
gft_reject(app_glofas_family_transition_run_request(request_path,auth_path,
  app_sha256_file(auth_path),getwd()),"prepared template")
cli_output <- suppressWarnings(system2(file.path(R.home("bin"),"Rscript"),
  c("application/scripts/run_glofas_family_transition.R","--request",shQuote(request_path),
    "--authorization",shQuote(auth_path),"--authorization-sha256",app_sha256_file(auth_path)),
  stdout=TRUE,stderr=TRUE))
gft_check(identical(attr(cli_output,"status"),1L))
gft_check(any(grepl("prepared template",cli_output)))
unlink(tmp,recursive=TRUE)

# Exercise the actual preparation CLI, including mixed raw/Q-DESN model grids.
# This is a fabricated 28x51 geometry with four historical rows, not production
# evidence. It writes only an ignored temporary fixture and launches zero fits.
gft_prepare_fixture_test <- function() {
app_ensure_dir("local_trackers")
fixture <- tempfile("gft_prepare_fixture_",tmpdir=normalizePath("local_trackers"))
dir.create(fixture)
on.exit(unlink(fixture,recursive=TRUE),add=TRUE)
source_dir <- file.path(fixture,"frozen_synthetic")
app_ensure_dir(file.path(source_dir,"objects"))
app_ensure_dir(file.path(source_dir,"configs"))
origin <- as.Date("2022-12-25")
panel <- data.frame(origin_date=origin,
  target_date=c(origin-4:0,rep(origin+1:28,each=51L)),
  horizon=c(rep(0L,5L),rep(1:28,each=51L)),
  member=c(rep(NA_character_,5L),rep(sprintf("m%02d",1:51),28L)),
  is_retrospective=c(rep(TRUE,5L),rep(FALSE,1428L)),
  is_ensemble=c(rep(FALSE,5L),rep(TRUE,1428L)),
  y_transformed=c(seq(.1,.5,length.out=5L),rep(1234,1428L)),
  g_transformed=seq(.1,1,length.out=1433L),split="synthetic",cutoff_id="synthetic")
cutoff <- data.frame(cutoff_id="synthetic",origin_date=origin,train_start=origin-4L,
  train_end=origin,eval_start=origin+1L,eval_end=origin+28L,horizon_min=1L,horizon_max=28L)
cfg <- list(application_model=list(contract="latent_path_ensemble_likelihood",
  ensemble_member_weight_policy="unit_member_likelihood_v1"),
  inference=list(likelihood_family="al"),
  prediction=list(prediction_unit="posterior_draw",q_g_source="posterior_model_quantile"))
latent <- app_make_glofas_latent_path_data(panel,cfg,cutoff)
large <- frozen_toy
large$future_builder <- local({
  dates<-origin+1:28
  member_values<-as.numeric(latent$g_ensemble$g_transformed)
  function(y) {
    xb<-cbind(1,c(.4,y[1:27]));xa<-cbind(1,c(-.2,1.2-y[1:27]))
    Jy<-Jg<-lapply(1:28,function(h) matrix(0,4L,28L))
    for (h in 2:28) {Jy[[h]][2,h-1L]<-1;Jg[[h]][2,h-1L]<-1;Jg[[h]][4,h-1L]<- -1}
    list(H_y=cbind(xb,matrix(0,28L,2L)),H_g_key=cbind(xb,xa),
      g_future_index=rep(1:28,each=51L),J_y=Jy,J_g_key=Jg,z_g=member_values,
      weight_g=rep(1,1428L),row_info_y=data.frame(source="Y",future_index=1:28,
        target_date=dates,horizon=1:28),
      row_info_g=data.frame(source="G",future_index=rep(1:28,each=51L),
        target_date=rep(dates,each=51L),horizon=rep(1:28,each=51L),member=rep(sprintf("m%02d",1:51),28L)),
      discrepancy_baseline_future=rep(0,28L))
  }
})
large$future_key<-latent$future_key;large$y_future_init<-rep(.9,28L)
large$latent_data<-latent;large$future_context<-list(latent_data=latent)
large$unit_member_contract<-app_glofas_unit_member_contract()
design_file<-file.path(source_dir,"objects/part4_shared_design_truth_free.rds")
saveRDS(large,design_file)
old <- app_glofas_part4_launch_manifest("synthetic_preparation_only")
paths<-design_file
for (j in seq_len(nrow(old))) {
  p<-suppressWarnings(as.numeric(old$quantile[j]))
  if (!is.finite(p)) p<-contract$tau
  grid<-app_glofas_part4_make_model_grid("synthetic",p,old$part4_family[j],reservoir_seed=99L)
  old$model_grid_path[j]<-file.path(source_dir,"configs",paste0(j,"_models.csv"))
  app_write_csv(grid,old$model_grid_path[j])
  old$config_path[j]<-file.path(source_dir,"configs",paste0(j,"_config.yaml"))
  app_write_yaml(cfg,old$config_path[j])
  paths<-c(paths,old$model_grid_path[j],old$config_path[j])
}
old_path<-file.path(source_dir,"configs/part4_model_manifest.csv")
app_write_csv(old,old_path);paths<-c(paths,old_path)
root_file<-file.path(source_dir,"objects/synthetic_normal_initializer.rds")
root_normal<-list(fit=list(likelihood_family="normal",summary=list(theta_mean=rep(0,4L),
  theta_cov=diag(1,4L),y_future_mean=rep(.9,28L),y_future_cov=diag(1,28L))),
  state_contract_hash=app_glofas_part4_state_contract_hash(large),
  shared_design_reference=list(sha256=app_sha256_file(design_file)))
saveRDS(root_normal,root_file);paths<-c(paths,root_file)
evidence_path<-file.path(source_dir,"evidence.csv")
app_write_csv(app_gft_manifest(paths,rep("synthetic_frozen_input",length(paths)),root=source_dir),evidence_path)
source_paths<-c("application/R/glofas_family_transition.R","application/scripts/prepare_glofas_family_transition.R")
source_inventory<-data.frame(path=source_paths,role="synthetic_preparation_source",mode="100644",
  sha256=vapply(source_paths,app_sha256_file,character(1L)),blob="synthetic_not_production")
source_inventory_path<-file.path(fixture,"source_manifest.csv")
app_write_csv(source_inventory,source_inventory_path)
prepared<-file.path(fixture,"prepared")
rscript<-file.path(R.home("bin"),"Rscript")
command<-c("application/scripts/prepare_glofas_family_transition.R",
  "--source_runtime",shQuote(source_dir),"--evidence_manifest",shQuote(evidence_path),
  "--evidence_manifest_sha256",app_sha256_file(evidence_path),
  "--source_manifest",shQuote(source_inventory_path),"--source_manifest_sha256",app_sha256_file(source_inventory_path),
  "--root_initializer",shQuote(root_file),
  "--output_root",shQuote(prepared),"--plan_sha256",paste(rep("a",64L),collapse=""))
preparation_output<-system2(rscript,command,stdout=TRUE,stderr=TRUE)
if (!is.null(attr(preparation_output,"status"))) stop(paste(preparation_output,collapse="\n"))
gft_check(any(grepl("PREPARED_NOT_AUTHORIZED_NO_LAUNCH",preparation_output)))
prepared_tasks<-app_read_csv(file.path(prepared,"manifests/task_manifest.csv"))
gft_check(nrow(prepared_tasks)==16L)
gft_check(length(list.files(file.path(prepared,"requests"),pattern="template.json$"))==16L)
gft_check(length(list.files(file.path(prepared,"control_tasks"),pattern="template.json$"))==16L)
prepared_request<-app_gft_json(file.path(prepared,"requests/gft-al-p050.template.json"))
gft_check(!prepared_request$allow_launch && length(prepared_request$expected_output_keys)==6L)
prepared_config<-readRDS(prepared_request$config_path)
gft_check(is.null(prepared_config$vb_args$future_gaussian_prior))
gft_check(app_gft_json(file.path(prepared,"PREPARED_NO_LAUNCH.json"))$production_fits_launched==0L)
gft_check(all(!app_read_csv(file.path(prepared,"manifests/normal_reuse_decision.csv"))$reuse_authorized))
gft_check(!length(list.files(file.path(prepared,"results"),recursive=TRUE)))
}
gft_prepare_fixture_test()
cat(sprintf("PASS: GloFAS same-family transition (%d synthetic checks; no production work).\n",gft_checks))
