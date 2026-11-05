#!/usr/bin/env Rscript
# Generated evidence only. No authentic payloads, fitting or publication.
gcga_compute <- function() {
  source("scripts/diagnostics/glofas_innovation_coordinates.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_vi.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  rows <- list()
  for (h in 1:2) for (p in c(.05,.5,.95)) for (m in c(0L,1L,51L)) {
    members <- if (!m) NULL else matrix(rep(c(.08,.22)[seq_len(h)],m),h,m)
    a <- gcpr_conditional(.11,.2,members,p,.8,.35,h)
    b <- gcpr_conditional_numeric(.11,.2,members,p,.8,.35,h)
    stopifnot(is.finite(b), abs(a$log_evidence-b)<1e-8)
    rows[[length(rows)+1L]] <- data.frame(horizon=h,probability=p,members=m,
      log_evidence=a$log_evidence,integration_error=abs(a$log_evidence-b),
      comparison=if(h==2&&m>0) "independent_numerical_quadrature" else "closed_form_identity")
  }
  joint <- lapply(c(0L,1L,51L),function(m) {
    a <- gcpr_one_horizon_joint_scale(if(m)seq(.08,.22,length.out=m)else numeric())
    stopifnot(abs(a$normalization-1)<1e-8)
    data.frame(members=m,log_evidence=a$log_evidence,theta_mean=a$theta_mean,
      theta_variance=a$theta_variance,sigma_mean=a$sigma_mean,sigma_variance=a$sigma_variance,
      theta_sigma_covariance=a$theta_sigma_covariance,future_CDF_at_0p1=a$future_cdf(.1),
      scale_scope="one_horizon_shared_future_and_member_scale_Normal_prior_not_application_RHS")
  })
  members <- rbind(seq(-.08,.08,length.out=51L),seq(.08,.2,length.out=51L))
  exact <- gcpr_conditional(.1,.3,members,.5,.8,.35,2L)$log_evidence
  args <- list(location=function(h,past,p)p$theta+if(h>1).2*tail(past,1)else 0,
    scale=function(h,past,p)p$sigma,
    member_location=function(h,past,p)p$theta+if(h>1).35*tail(past,1)else 0,
    member_scale=.8,members=members,horizon=2L,probability=.5,ess_fraction=.8,
    limits=list(max_horizon=2L,max_particles=256L,max_calls=10000L),
    gates=list(min_ess=2,min_unique_ancestors=2L))
  particles <- list()
  for(n in c(64L,256L))for(j in 1:4) {
    a <- do.call(gcpv_smc,c(list(parameters=list(theta=.1,sigma=.3),particles=n,seed=2026110700L+j),args))
    stopifnot(a$complete,!a$production_launch_authorized,a$original_reads==0L)
    particles[[length(particles)+1L]] <- data.frame(particles=n,replicate=j,seed=2026110700L+j,
      log_normalizer=a$log_normalizer_estimate,exact_log_normalizer=exact,
      relative_normalizer=exp(a$log_normalizer_estimate-exact),
      min_ess=min(a$diagnostics$effective_sample_size),
      min_unique_ancestors=min(a$diagnostics$unique_initial_ancestors),
      diagnostic_thresholds_passed=a$diagnostic_thresholds_passed,
      callback_calls=a$callback_calls,production_qualified=FALSE)
  }
  params <- list(list(theta=-.2,sigma=.2),list(theta=.1,sigma=.3),list(theta=.4,sigma=.7),list(theta=.2,sigma=1.1))
  historical <- function(p)stats::dnorm(p$theta,0,.5,log=TRUE)+gcpr_log_ig(p$sigma,3,.6)
  args["members"] <- list(NULL); args$particles <- 32L
  obj <- gcpv_joint_objective(params,historical,historical,args,2026110801:2026110804)
  stopifnot(obj$complete,identical(obj$value,0),!obj$parameters_frozen,!obj$optimizer_implemented)
  list(conditional_references=do.call(rbind,rows),joint_parameter_references=do.call(rbind,joint),
    particle_diagnostics=do.call(rbind,particles),no_member_varying_parameter_objective=obj$value)
}

gcga_main <- function(args=commandArgs(TRUE)) {
  stopifnot(length(args)==2L,identical(args[1L],"--output"))
  root <- normalizePath(".",mustWork=TRUE);parent<-normalizePath(dirname(args[2L]),mustWork=TRUE)
  output <- file.path(parent,basename(args[2L]));link<-Sys.readlink(output)
  stopifnot(startsWith(parent,paste0(root,"/local_trackers/")),!file.exists(output),
    is.na(link)||!nzchar(link),system2("git",c("check-ignore","--quiet","--",shQuote(output)))==0L)
  git <- function(a) {x<-system2("git",c("--no-replace-objects","-c","core.fsmonitor=false",a),stdout=TRUE)
    stopifnot(is.null(attr(x,"status")));unname(x)}
  stopifnot(!length(git(c("status","--porcelain","--untracked-files=all"))))
  sources<-c("scripts/audit_glofas_collapsed_inference_generated.R","scripts/diagnostics/glofas_innovation_coordinates.R",
    "scripts/diagnostics/glofas_collapsed_particle_vi.R","scripts/diagnostics/glofas_collapsed_particle_reference.R")
  commit<-git(c("rev-parse","HEAD"));tree<-git(c("rev-parse","HEAD^{tree}"))
  hashes<-as.list(tools::sha256sum(sources))
  for(path in sources)stopifnot(identical(git(c("hash-object","--no-filters","--",shQuote(path))),
    git(c("rev-parse",shQuote(paste0(commit,":",path))))))
  result <- gcga_compute();stopifnot(dir.create(output,mode="0700"))
  for(name in c("conditional_references","joint_parameter_references","particle_diagnostics"))
    write.csv(result[[name]],file.path(output,paste0(name,".csv")),row.names=FALSE)
  gaps<-data.frame(gate=c("full_application_parameter_optimizer","resampling_gradient_or_declared_approximation",
    "application_RHS_all_parameter_accuracy","nonlinear_batched_DESN_particle_backend",
    "finite_particle_parameter_marginal_accuracy","exAL_and_MQ_support",
    "authentic_precision_and_native_cost","application_refit","article_promotion"),
    status="NOT_QUALIFIED")
  write.csv(gaps,file.path(output,"remaining_gates.csv"),row.names=FALSE)
  receipt<-list(schema_version="glofas_collapsed_inference_generated_receipt_v1",
    status="GENERATED_BUILDING_BLOCK_COMPLETE_APPLICATION_NOT_READY",
    source_commit=commit,source_tree=tree,
    source_files_sha256=hashes,R_version=R.version.string,generated_particle_evaluations=8L,
    original_RDS_reads=0L,model_fits=0L,future_truth_reads=0L,forecast_scoring=FALSE,
    no_member_varying_parameter_objective=result$no_member_varying_parameter_objective,
    parameters_frozen=FALSE,optimizer_implemented=FALSE,resampling_gradient_implemented=FALSE,
    reference_qualified=FALSE,full_posterior_accuracy_qualified=FALSE,
    production_launch_authorized=FALSE,publication_authorized=FALSE,
    scope="Controlled Normal-prior examples and particle objective, not a qualified application correction")
  jsonlite::write_json(receipt,file.path(output,"DECISION.json"),auto_unbox=TRUE,pretty=TRUE,digits=17,null="null")
  stopifnot(identical(hashes,as.list(tools::sha256sum(sources))),
    identical(git(c("rev-parse","HEAD")),commit),identical(git(c("rev-parse","HEAD^{tree}")),tree),
    !length(git(c("status","--porcelain","--untracked-files=all"))))
  entries<-sort(list.files(output));manifest<-data.frame(relative_path=entries,
    size_bytes=as.numeric(file.info(file.path(output,entries))$size),
    sha256=unname(tools::sha256sum(file.path(output,entries))))
  write.csv(manifest,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
  cat("GLOFAS_COLLAPSED_INFERENCE_GENERATED_AUDIT_COMPLETE_NO_PRODUCTION_AUTHORIZATION\n")
  invisible(receipt)
}
if(sys.nframe()==0L)gcga_main()
