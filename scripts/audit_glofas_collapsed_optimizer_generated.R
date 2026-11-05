#!/usr/bin/env Rscript
# Source-frozen generated optimizer accuracy audit. Never reads model payloads.
gcpoa_sources <- function() c("scripts/audit_glofas_collapsed_optimizer_generated.R",
  "scripts/diagnostics/glofas_collapsed_parameter_optimizer.R",
  "scripts/diagnostics/glofas_collapsed_optimizer_reference.R",
  "scripts/diagnostics/glofas_collapsed_particle_reference.R",
  "scripts/diagnostics/glofas_collapsed_al_target.R")
gcpoa_control <- function(constructor) constructor(max_iterations = 1000L, minimum_iterations = 50L,
  batch_size = 256L, learning_rate = .02, max_evaluations = 300000L,
  max_wall_seconds = 300, max_inner_calls = 1000000L, inner_call_bound = 1L,
  gradient_tolerance = .02, gradient_mcse_tolerance = .04,
  step_tolerance = .001, objective_tolerance = .01, stable_iterations = 5L,
  seed = 2026110507L)
gcpoa_compute <- function(source_hashes, control = NULL) {
  source("scripts/diagnostics/glofas_collapsed_parameter_optimizer.R",local=TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R",local=TRUE)
  source("scripts/diagnostics/glofas_collapsed_optimizer_reference.R",local=TRUE)
  if(is.null(control)) control <- gcpoa_control(gcpopt_control)
  fixtures <- list(no_members = numeric(), moderate_51 = seq(-.3,.7,length.out=51L),
    concentrated_51 = rep(.2,51L))
  offset <- c(.1,log(.3/4)+1/8); units <- c(.2,.5)
  summaries <- histories <- list()
  for (name in names(fixtures)) {
    members <- fixtures[[name]]
    historical <- function(mean,log_sd,factor) {
      stopifnot(is.null(factor))
      h <- gcpor_h1_elbo(offset + units*mean,log_sd,factor=diag(units))
      list(value=h$value,gradient_mean=h$gradient[1:2]*units,gradient_log_sd=h$gradient[3:4])
    }
    evidence <- function(eta,seed) {
      point <- offset + units*eta; residual <- members-point[1L]
      list(log_estimate=length(members)*(log(.2*.8)-point[2L]) -
        exp(-point[2L])*sum(residual*(.2-(residual<0))),complete=TRUE,
        diagnostic_thresholds_passed=TRUE,callback_calls=0L)
    }
    contract <- gcpopt_input_contract(c("standardized_theta","standardized_log_sigma"),
      "fixed_affine_standardization_of_theta_logsigma_same_measure_ELBO_Jacobian_once",
      list(fixture=name,members=members,probability=.2,prior_mean=.1,prior_sd=.2,
        IG_shape=4,IG_rate=.3,offset=offset,units=units),source_hashes)
    fit <- gcpopt_optimize(log_evidence_estimate=evidence,initial_mean=c(0,0),
      initial_log_sd=c(0,0),control=control,input_contract=contract,analytic_historical=historical)
    mean <- offset+units*fit$mean
    reference <- gcpor_h1_optimize(offset,c(0,0),factor=diag(units),members=members,probability=.2)
    achieved <- gcpor_h1_elbo(mean,fit$log_sd,factor=diag(units),members=members,probability=.2)
    truth <- gcpor_h1_joint_moments(members,probability=.2)
    variance <- units^2*exp(2*fit$log_sd)
    gap <- reference$value-achieved$value
    mean_error <- max(abs(mean-reference$mean)/sqrt(diag(reference$covariance)))
    variance_error <- max(abs(variance/diag(reference$covariance)-1))
    histories[[name]] <- fit$history
    summaries[[name]] <- data.frame(fixture=name,members=length(members),
      iterations=fit$completed_iterations,status=fit$status,stopping_criteria_met=fit$stopping_criteria_met,
      failure=if(is.null(fit$failure)) "" else fit$failure,
      theta_mean=mean[1L],log_sigma_mean=mean[2L],theta_sd=sqrt(variance[1L]),log_sigma_sd=sqrt(variance[2L]),
      reference_theta_mean=reference$mean[1L],reference_log_sigma_mean=reference$mean[2L],
      reference_theta_sd=sqrt(reference$covariance[1L,1L]),reference_log_sigma_sd=sqrt(reference$covariance[2L,2L]),
      reference_optimizer_convergence=reference$convergence,
      exact_achieved_ELBO=achieved$value,reference_ELBO=reference$value,optimization_gap=gap,
      minimum_family_KL=truth$log_evidence-reference$value,
      mean_error_in_reference_sd=mean_error,maximum_variance_relative_error=variance_error,
      optimizer_accuracy_gate=fit$stopping_criteria_met && reference$convergence==0 &&
        gap >= -1e-7 && gap<=.02 && mean_error<=.1 && variance_error<=.1,
      exact_target_theta_mean=truth$mean[1L],exact_target_theta_variance=truth$covariance[1L,1L],
      exact_target_theta_logsigma_covariance=truth$covariance[1L,2L],
      best_diagonal_variance_ratio=reference$covariance[1L,1L]/truth$covariance[1L,1L],
      exact_target_sigma_mean=truth$sigma_mean,
      last_raw_gradient=if(is.null(fit$last_gradient)) NA_real_ else max(abs(fit$last_gradient$gradient)),
      last_standardized_gradient=if(is.null(fit$last_gradient)) NA_real_ else max(abs(fit$last_gradient$standardized_gradient)),
      elapsed_seconds=fit$elapsed_seconds,original_reads=0L,application_qualified=FALSE)
  }
  list(summary=do.call(rbind,summaries),histories=histories,control=control,
    fixture_scope="Known generated H1 Normal-coefficient/shared-AL-scale targets, not application two-scale/RHS target",
    source_parameterization="theta and logsigma; fixed affine standardization only")
}
gcpoa_main <- function(args=commandArgs(TRUE)) {
  stopifnot(length(args)==2L,identical(args[1L],"--output"))
  root <- normalizePath(".",mustWork=TRUE)
  parent <- normalizePath(dirname(args[2L]),mustWork=TRUE)
  output <- file.path(parent,basename(args[2L]))
  link <- Sys.readlink(output)
  stopifnot(startsWith(parent,paste0(root,"/local_trackers/")),!file.exists(output),
    is.na(link)||!nzchar(link),system2("git",c("check-ignore","--quiet","--",shQuote(output)))==0L)
  git <- function(args) {
    x <- system2("git",c("--no-replace-objects","-c","core.fsmonitor=false",args),stdout=TRUE)
    stopifnot(is.null(attr(x,"status")));unname(x)
  }
  stopifnot(!length(git(c("status","--porcelain","--untracked-files=all"))))
  commit <- git(c("rev-parse","HEAD"));tree <- git(c("rev-parse","HEAD^{tree}"))
  paths <- gcpoa_sources();hashes <- tools::sha256sum(paths)
  for(path in paths) stopifnot(identical(git(c("hash-object","--no-filters","--",shQuote(path))),
    git(c("rev-parse",shQuote(paste0(commit,":",path))))))
  result <- gcpoa_compute(hashes)
  stopifnot(identical(hashes,tools::sha256sum(paths)),identical(git(c("rev-parse","HEAD")),commit),
    !length(git(c("status","--porcelain","--untracked-files=all"))),dir.create(output,mode="0700"))
  write.csv(result$summary,file.path(output,"optimizer_quality.csv"),row.names=FALSE)
  for(name in names(result$histories)) write.csv(result$histories[[name]],
    file.path(output,paste0("history_",name,".csv")),row.names=FALSE)
  receipt <- list(schema_version="glofas_generated_optimizer_audit_v1",
    status="GENERATED_OPTIMIZER_AUDIT_COMPLETE_APPLICATION_NOT_QUALIFIED",
    source_commit=commit,source_tree=tree,source_sha256=as.list(hashes),R_version=R.version.string,
    control=result$control,fixture_scope=result$fixture_scope,source_parameterization=result$source_parameterization,
    optimizer_accuracy_passes=sum(result$summary$optimizer_accuracy_gate),fixtures=nrow(result$summary),
    original_RDS_reads=0L,original_RDS_hashes=0L,original_RDS_stats=0L,application_fits=0L,
    future_truth_reads=0L,forecast_score_selection=FALSE,existing_results_changed=FALSE,
    full_RHS_target_fixture_tested_separately=TRUE,
    full_application_parameter_accuracy_qualified=FALSE,native_backend_qualified=FALSE,
    production_launch_authorized=FALSE,publication_authorized=FALSE,
    remaining_gates=c("actual_destination_prior_input_binding","richer_parameter_covariance_accuracy",
      "particle_count_parameter_marginal_accuracy","two_DESN_changing_parameter_continuation",
      "native_cost_and_resource_admission","bounded_median_AL_refit","exAL_MQ_extension","coherent_article_packet"))
  jsonlite::write_json(receipt,file.path(output,"DECISION.json"),auto_unbox=TRUE,pretty=TRUE,null="null",digits=17)
  files <- sort(list.files(output))
  manifest <- data.frame(relative_path=files,size_bytes=as.numeric(file.info(file.path(output,files))$size),
    sha256=unname(tools::sha256sum(file.path(output,files))))
  write.csv(manifest,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
  cat("GLOFAS_GENERATED_OPTIMIZER_AUDIT_COMPLETE_APPLICATION_NOT_QUALIFIED\n")
  invisible(receipt)
}
if(sys.nframe()==0L)gcpoa_main()
