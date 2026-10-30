# Complete tiny artifact-contract fixture; no scientific model is fitted.
local({
  source("application/scripts/_glofas_unit_member_bootstrap.R")
  source("application/R/glofas_search3_final_closeout.R")
  app_ensure_dir("local_trackers")
  root <- tempfile("unit_member_finalizer_test_", tmpdir=app_path("local_trackers"))
  for (dir in c("configs", "objects", "status", "manifests", "scores", "predictions", "logs")) {
    app_ensure_dir(file.path(root, dir))
  }
  origin <- as.Date("2022-12-25")
  dates <- origin+1:28
  tau <- app_glofas_part4_quantile_grid()
  panel <- data.frame(origin_date=origin,
    target_date=c(origin-1:0, rep(dates, each=51L)),
    horizon=c(0L, 0L, rep(1:28, each=51L)),
    member=c(NA_character_, NA_character_, rep(sprintf("m%02d", 1:51), 28L)),
    is_retrospective=c(TRUE, TRUE, rep(FALSE, 1428L)),
    is_ensemble=c(FALSE, FALSE, rep(TRUE, 1428L)),
    y_transformed=c(.1, .2, rep(NA_real_, 1428L)),
    g_transformed=c(.2, .3, rep(seq(.5, 1, length.out=28L), each=51L)),
    split="fixture", cutoff_id="fixture")
  cfg <- list(application_model=list(contract="latent_path_ensemble_likelihood",
      ensemble_member_weight_policy="unit_member_likelihood_v1"),
    inference=list(likelihood_family="al"))
  cutoff <- data.frame(origin_date=origin, train_start=origin-1L, train_end=origin,
    eval_start=dates[[1L]], eval_end=tail(dates,1L), horizon_min=1L, horizon_max=28L)
  data <- app_make_glofas_latent_path_data(panel, cfg, cutoff)
  builder <- function(y) {
    index <- rep(1:28, each=51L)
    list(H_y=cbind(1, rep(0,28L)), H_g_key=matrix(1,28L,2L),
      g_future_index=index, J_y=lapply(1:28,function(i)matrix(0,2L,28L)),
      J_g_key=lapply(1:28,function(i)matrix(0,2L,28L)),
      z_g=data$g_ensemble$g_transformed, weight_g=rep(1,1428L),
      row_info_y=data.frame(source="Y",future_index=1:28),
      row_info_g=data.frame(source="G",future_index=index),
      discrepancy_baseline_future=rep(0,28L))
  }
  design <- list(H_fixed=matrix(c(1,0,1,0,1,1,1,1),4L,2L,byrow=TRUE),
    z_fixed=c(.1,.2,.2,.3), source_fixed=c("Y","Y","G","G"), weight_fixed=rep(1,4L),
    row_info_fixed=data.frame(source=c("Y","Y","G","G")),
    X_beta=matrix(1,2L,1L), X_alpha=matrix(1,2L,1L), beta_index=1L,alpha_index=2L,
    future_builder=builder, future_key=data$future_key, y_future_init=rep(.5,28L),
    future_truth_policy="physically_excluded_from_fit_objects_scoring_sidecar_only",
    ensemble_member_weight_policy="unit_member_likelihood_v1",
    unit_member_contract=app_glofas_unit_member_contract(),
    latent_data=data, future_context=list(latent_data=data), design_version="fixture")
  app_glofas_unit_member_validate_design(design)
  dpath <- file.path(root,"objects/part4_shared_design_truth_free.rds")
  saveRDS(design,dpath)
  truth <- list(role="post_fit_scoring_sidecar",future_truth_used_in_fit=FALSE,
    panel=data.frame(target_date=dates,y_transformed=seq(.5,1,length.out=28L)))
  saveRDS(truth,file.path(root,"objects/part4_scoring_panel_sidecar.rds"))
  families <- c("normal_ridge_diagnostic","normal_rhs_vb_diagnostic",
    rep("independent_al_rhs_vb",7L), rep("independent_exal_rhs_vb",7L),
    "joint_al_rhs_vb","joint_exal_rhs_vb")
  jobs <- data.frame(run_id=paste0("fixture_",1:18),part4_family=families)
  app_write_csv(jobs,file.path(root,"configs/part4_model_manifest.csv"))
  quadratic <- data.frame(iteration=1L,source=c("Y","G"),nodes_per_panel=48L,relative_change=1e-10)
  core <- list(vb_diagnostics=list(converged=TRUE,quadrature_trace=quadratic))
  for(i in 1:18) {
    job <- jobs$run_id[[i]]
    family <- families[[i]]
    joint <- startsWith(family,"joint_")
    if (joint) {
      object <- list(converged=TRUE,converged_outer=TRUE,converged_inner=TRUE,converged_rhs=TRUE,
        stopping_reason="fixture_gate", fits=rep(list(core),7L),
        unit_member_contract=app_glofas_unit_member_contract(),
        trace=data.frame(outer_iteration=10L,parameter_change=1e-5,all_inner_converged=TRUE,
          rhs_convergence_gate_passed=TRUE,full_state_pass=TRUE,terminal_consecutive_passes=3L,
          max_rhs_global_relative_change=1e-5))
    } else {
      object <- app_glofas_part4_fit_side_artifact(list(fit=core,design=design,
        unit_member_contract=app_glofas_unit_member_contract()), dpath)
      stopifnot(identical(object$unit_member_contract$policy,"unit_member_likelihood_v1"),
        is.null(object$design))
    }
    fit_path <- file.path(root,"objects",paste0(job,"_fit_side.rds"))
    saveRDS(object,fit_path)
    target_path <- file.path(root,"manifests",paste0(job,"_target.json"))
    app_write_json(list(policy="unit_member_likelihood_v1",included_issued_G=1428L,
      included_future_Y=if(startsWith(family,"normal_"))28L else 0L),target_path)
    if(startsWith(family,"normal_")) {
      path <- file.path(root,"predictions",paste0(job,"_posterior_draws.csv.gz"))
      draws <- data.frame(target_date=rep(dates,each=20L),horizon=rep(1:28,each=20L),
        y_reference=rep(truth$panel$y_transformed,each=20L),
        latent_y_draw=rep(truth$panel$y_transformed,each=20L)+rep(seq(-.2,.2,length.out=20L),28L))
      con <- gzfile(path,"wt"); write.csv(draws,con,row.names=FALSE);close(con)
    } else {
      q <- if(joint)tau else if(i<=9L)tau[[i-2L]] else tau[[i-9L]]
      score <- do.call(rbind,lapply(q,function(p)data.frame(target_date=dates,horizon=1:28,
        quantile_level=p,y_reference=truth$panel$y_transformed,
        qhat=truth$panel$y_transformed+qnorm(p)/10)))
      path <- file.path(root,"scores",paste0(job,"_by_horizon.csv"))
      write.csv(score,path,row.names=FALSE)
    }
    artifact <- app_glofas_part4_artifact_manifest(c(fit_path,target_path,path),root)
    app_write_csv(artifact,file.path(root,"manifests",paste0(job,"_artifacts.csv")))
    writeLines("fixture only",file.path(root,"status",paste0(job,".completed")))
  }
  rscript <- file.path(R.home("bin"),"Rscript")
  command <- c("application/scripts/finalize_glofas_unit_member_correction.R","--runtime_root",shQuote(root))
  log <- file.path(root,"logs/finalizer.log")
  code <- system2(rscript, command, stdout=log,stderr=log)
  if(code!=0L)stop(paste(readLines(log),collapse="\n"))
  result <- app_read_csv(file.path(root,"final_packet/family_scores.csv"))
  stopifnot(nrow(result)==7L,all(result$n_scored_horizons==28L),all(is.finite(result$crps_grid_log1p)))
  forecasts <- app_read_csv(file.path(root,"final_packet/quantile_paths.csv"))
  stopifnot(nrow(forecasts)==7L*28L*7L)
  decision <- jsonlite::read_json(file.path(root,"final_packet/DECISION.json"),simplifyVector=TRUE)
  stopifnot(identical(decision$status,"READY_FOR_SCIENTIFIC_REVIEW_NOT_AUTOMATIC_PUBLICATION"),
    decision$numerical_pass==18L,!decision$article_changed)
  app_glofas_closeout_verify_manifest(root,file.path(root,"final_packet/artifact_manifest.csv"))
  # A frozen packet cannot be overwritten by running the finalizer twice.
  code2 <- suppressWarnings(system2(rscript,command,stdout=log,stderr=log))
  stopifnot(code2!=0L)
  copy_fixture <- function(suffix) {
    target <- paste0(root,suffix)
    app_ensure_dir(target)
    for(dir in c("configs","objects","status","manifests","scores","predictions","logs")) {
      if(!file.copy(file.path(root,dir),target,recursive=TRUE))stop("Fixture copy failed.")
    }
    target
  }
  refresh_manifest <- function(target,job) {
    path <- file.path(target,"manifests",paste0(job,"_artifacts.csv"))
    rows <- app_read_csv(path)
    paths <- file.path(target,rows$relative_path)
    app_write_csv(app_glofas_part4_artifact_manifest(paths,target),path)
  }
  capped <- copy_fixture("_cap_review")
  fitpath <- file.path(capped,"objects/fixture_3_fit_side.rds")
  cap <- readRDS(fitpath);cap$fit$vb_diagnostics$converged <- FALSE;saveRDS(cap,fitpath)
  refresh_manifest(capped,"fixture_3")
  command_cap <- c("application/scripts/finalize_glofas_unit_member_correction.R","--runtime_root",shQuote(capped))
  stopifnot(system2(rscript,command_cap,stdout=log,stderr=log)==0L)
  cap_decision <- jsonlite::read_json(file.path(capped,"final_packet/DECISION.json"),simplifyVector=TRUE)
  stopifnot(identical(cap_decision$status,"NOT_READY_BOUNDED_FITS_REQUIRE_REVIEW"),
    cap_decision$numerical_review==1L,nrow(app_read_csv(file.path(capped,"final_packet/family_scores.csv")))==7L)
  legacy <- copy_fixture("_legacy_rejected")
  targetpath <- file.path(legacy,"manifests/fixture_3_target.json")
  wrong <- jsonlite::read_json(targetpath,simplifyVector=TRUE)
  wrong$policy <- "fractional_per_horizon_v1";app_write_json(wrong,targetpath)
  refresh_manifest(legacy,"fixture_3")
  command_legacy <- c("application/scripts/finalize_glofas_unit_member_correction.R","--runtime_root",shQuote(legacy))
  stopifnot(suppressWarnings(system2(rscript,command_legacy,stdout=log,stderr=log))!=0L)
  cat("PASS: complete 18-artifact, 7-family unit-member finalizer fixture; wrapper contract retained; overwrite rejected\n")
  cat("PASS: capped fit retained and quarantined; legacy target rejected\n")
})
