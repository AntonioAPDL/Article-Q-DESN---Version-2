# Generated metadata and tiny numeric in-memory fixtures only. No original RDS.
local({
  source("scripts/glofas_fixed_target_forensic_reader.R", local = TRUE)
  source("application/R/glofas_family_transition.R", local = TRUE)
  n <- 0L
  ok <- function(x) {stopifnot(isTRUE(x)); n <<- n+1L; invisible(TRUE)}
  reject <- function(expr, pattern = NULL) {
    e <- tryCatch({force(expr); NULL}, error = function(e) e)
    ok(inherits(e, "error")); if (!is.null(pattern)) ok(grepl(pattern, conditionMessage(e), fixed = TRUE))
  }
  pin <- function(path, size = 100, hash = strrep("a",64L)) list(path=path,size_bytes=size,sha256=hash)
  producer <- function(id) list(task_id=id,state="accepted",numerical_gates_pass=TRUE,
    identity=c(list(task_id=id),gsc_identity(),list(rng_namespace=id,routing_id=paste0("route-",id))),
    claim_nonce=paste0("nonce-",id),output_manifest_sha256=strrep("b",64L),
    terminal=list(exit_code=0L,accounting_complete=TRUE,owner_terminated=TRUE,worker_terminated=TRUE,timed_out=FALSE),
    artifacts=lapply(c("fit.rds","forecast_quantiles.csv","raw_crossings.csv","target_receipt.json",
      "progress.csv","artifact_manifest.csv"),function(p)c(list(relative_path=p),pin(paste0("/generated/",id,"/",p)))))
  collection <- list(schema_version="glofas_same_family_accepted_collection_v1",
    status="SIXTEEN_ACCEPTED_PRODUCERS_REVERIFIED",producers=lapply(gsc_tasks(),producer),
    ledger_mutations=0L,fit_objects_loaded=0L,future_truth_read=FALSE,article_publication_authorized=FALSE)
  selected <- setNames(lapply(gfr_ids(),function(id)producer(id)$artifacts[[1L]][c("path","size_bytes","sha256")]),gfr_ids())
  s <- list(schema_version="glofas_fixed_target_forensic_contract_v1",
    purpose="TWO_AL_RETAINED_STATES_READ_ONLY_NO_TRUTH_NO_UPDATES",nonce=strrep("a",32L),
    expires_utc="2100-01-01T00:00:00Z",source_root="/generated/source",source_commit=strrep("a",40L),
    source_tree=strrep("b",40L),source_files=list(pin("/generated/source.R")),expected_identity=gsc_identity(),
    collection=pin("/generated/accepted_producers.json"),
    input_manifest=pin("/generated/runtime/manifests/input_manifest.csv",hash=gsc_identity()$input_manifest_sha256),
    design=pin("/generated/runtime/objects/shared_truth_free_design.rds",1000,
      "193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3"),
    models=selected,read_budget=list(max_payload_hash_bytes=2400,max_deserialization_bytes=1200,
      max_RDS_deserializations=3L,max_metadata_bytes=8*1024^2,max_fit_output_bytes=10*1024^2),
    limits=list(cpu_seconds=1800,wall_seconds=1800,memory_bytes=32*1024^3,output_bytes=64*1024^2,logical_cpu=26L),
    output_root="/generated/source/local_trackers/forensics",allow_original_reads=TRUE,
    allow_truth_read=FALSE,allow_callbacks=FALSE,allow_coordinate_updates=FALSE,allow_refit=FALSE,
    allow_retuning=FALSE,allow_forecasting=FALSE,allow_scoring=FALSE,allow_publication=FALSE)
  ok(isTRUE(gfr_scope(s))); ok(gfr_read_cost(s)$RDS_deserializations==3L)
  for (field in c("allow_truth_read","allow_callbacks","allow_coordinate_updates","allow_refit",
    "allow_retuning","allow_forecasting","allow_scoring","allow_publication")) {
    bad <- s; bad[[field]] <- TRUE; reject(gfr_scope(bad),"no-expanded-permission")
  }
  bad <- s; bad$extra <- TRUE; reject(gfr_scope(bad))
  bad <- c(s,list(allow_truth_read=FALSE)); reject(gfr_scope(bad),"duplicate")
  bad <- s; bad$models$`gft-al-p095` <- selected[[1L]]; reject(gfr_scope(bad),"pair required")
  bad <- s; bad$read_budget$max_RDS_deserializations <- 4L; reject(gfr_scope(bad),"three-object")
  for (field in c("max_payload_hash_bytes","max_deserialization_bytes")) {
    bad <- s; bad$read_budget[[field]] <- 1L; reject(gfr_scope(bad),"grant exceeded")
  }
  for (cpu in c(16,18,24,25,31,48,50,56,57,63)) {
    bad <- s; bad$limits$logical_cpu <- cpu; reject(gfr_scope(bad),"single-core")
  }
  bad <- s; bad$design$path <- "/generated/runtime/objects/part4_scoring_panel_sidecar.rds"
  reject(gfr_scope(bad),"truth-free payload")
  bad <- s; bad$design$sha256 <- strrep("f",64L); reject(gfr_scope(bad),"truth-free payload")
  manifest <- data.frame(relative_path="objects/shared_truth_free_design.rds",role="truth_free_shared_design",
    size_bytes=s$design$size_bytes,sha256=s$design$sha256)
  ok(isTRUE(gfr_bind(s,collection,manifest)))
  bad <- s; bad$models[[1L]]$sha256 <- strrep("f",64L); reject(gfr_bind(bad,collection,manifest),"accepted producer")
  bad <- collection; bad$producers[[1L]]$terminal$exit_code <- 1L
  reject(gfr_bind(s,bad,manifest),"closed accounting")
  bad <- manifest; bad$role <- "scoring_truth"; reject(gfr_bind(s,collection,bad),"truth-free input role")

  dates <- seq(as.Date("2022-11-26"),as.Date("2022-12-25"),by="day")
  xb <- cbind(intercept=1,feature=seq_len(30L)/30)
  H <- rbind(cbind(xb,discrepancy=0),cbind(xb,discrepancy=1)); colnames(H) <- c("b0","b1","a0")
  callback_calls <- 0L
  design <- list(H_fixed=H,X_beta=xb,source_fixed=rep(c("Y","G"),each=30L),
    row_info_fixed=data.frame(source=rep(c("Y","G"),each=30L),
      row_role=rep(c("historical_usgs","historical_glofas_retrospective"),each=30L),
      feature_row=rep(1:30,2L),target_date=rep(dates,2L),is_future=FALSE),
    base_panel=data.frame(target_date=dates),beta_index=1:2,alpha_index=3L,two_block_design=TRUE,
    future_truth_policy="physically_excluded_from_fit_objects_scoring_sidecar_only",
    ensemble_member_weight_policy="unit_member_likelihood_v1",
    future_key=data.frame(target_date=gsc_dates(),horizon=1:28),
    future_builder=function(...) {callback_calls <<- callback_calls+1L;stop("Never execute saved callback")})
  object <- function(id) {
    tau <- gsc_task_tau(id); m <- rep(2,28L); V <- diag(.5,28L)
    Jb <- lapply(1:28,function(h) {J<-matrix(0,2,28);if(h>1L)J[2,h-1L]<-.1;J})
    Ja <- lapply(1:28,function(h) {J<-matrix(0,1,28);if(h>1L)J[1,h-1L]<- -.2;J})
    state <- list(theta_mean=c(2,.1,-.4),theta_cov=diag(.2,3),y_future_mean=m,y_future_cov=V,
      sigma=list(shape=c(Y=3,G=4),rate=c(Y=2,G=5)),
      v=list(mean=rep(1,100L),inv_mean=rep(2,100L)),
      prior=list(prior="block_rhs_ns",blocks=list(beta=list(global_index=1:2,state=list(tau0=.1)),
        alpha=list(global_index=3L,state=list(tau0=.01)))),
      future_linearization=list(strategy="first_order_delta",y_mean=m,
        X_beta_future=cbind(1,seq_len(28)/28),X_alpha_future=matrix(1,28,1),J_beta=Jb,J_alpha=Ja))
    list(schema_version="glofas_family_transition_fit_v1",task_id=id,converged=TRUE,status="converged",
      claim_nonce=producer(id)$claim_nonce,identity=producer(id)$identity,target_contract=app_glofas_family_transition_contract(),
      counts=list(horizons=28L,members=51L,historical_Y=12455L,historical_G=12455L,
        residual_jacobian_determinant=1L,future_Y=28L,future_G=1428L,quantile_blocks=1L,
        total_future_Y=28L,total_future_G=1428L,replacement_gaussian_path_prior=FALSE),
      feature_contract=list(two_block_design=TRUE,discrepancy_input_stream="discrepancy",
        discrepancy_transition_strategy="recursive_level",reference_coefficients=1501L,discrepancy_coefficients=1001L),
      fit=list(method="vb",likelihood_family="al",prior="rhs_ns",variational_state=state,
        draws=list(theta=matrix(0,1,3,dimnames=list(NULL,colnames(H)))),
        summary=list(y_future_mean=m,y_future_cov=V),
        vb_diagnostics=list(converged=TRUE,future_y_working_likelihood_used=TRUE,
          future_gaussian_prior_used=FALSE,parameter_change_trace=rep(1e-5,300),
          iteration_timing=data.frame(step=rep("update",300),elapsed_seconds=rep(.1,300)))))
  }
  for (id in gfr_ids()) {
    result <- gfr_state(object(id),design,producer(id))
    ok(nrow(result$paths)==28L && nrow(result$future_covariance)==784L && nrow(result$causality)==56L)
    ok(all(result$causality$strict_causality_pass));ok(callback_calls==0L)
    ok(all(abs(result$paths$reference_plugin_at_path_mean-(2+.1*seq_len(28)/28))<1e-14))
    ok(all(result$paths$discrepancy_plugin_at_path_mean== -.4))
    ok(result$summary$requested_vs_executed_prior_status=="NOT_RUN_CONFIG_RDS_NOT_ADMITTED")
    ok(result$summary$stability_status=="NOT_RUN_NO_COORDINATE_UPDATES_ADMITTED")
    ok(!result$summary$coefficient_covariance$full_spectrum_evaluated)
    ok(result$summary$future_covariance$full_spectrum_evaluated)
    ok(length(gfr_json_raw(result$summary))<10*1024^2)
  }
  bad <- object(gfr_ids()[1L]);bad$fit$variational_state$future_linearization$J_beta[[1L]][1,1] <- .1
  result <- gfr_state(bad,design,producer(bad$task_id))
  ok(!result$summary$current_forecast_causality_pass)
  ok(!result$causality$strict_causality_pass[1L]) # Report diagnostic FAIL, do not discard evidence.
  bad <- object(gfr_ids()[1L]);bad$fit$variational_state$future_linearization$y_mean[1L] <- 3
  reject(gfr_state(bad,design,producer(bad$task_id)),"linearization")
  bad <- object(gfr_ids()[1L]);bad$fit$draws$theta <- bad$fit$draws$theta[,3:1,drop=FALSE]
  reject(gfr_state(bad,design,producer(bad$task_id)),"dimensions/order")
  bad <- design;bad$base_panel$target_date[30L] <- as.Date("2022-12-26")
  reject(gfr_state(object(gfr_ids()[1L]),bad,producer(gfr_ids()[1L])),"pre-origin")
  reject(gfr_summary(function()stop("callback")),"non-callback")
  reject(gfr_numeric(1i,"complex rejected"),"complex rejected")
  ok(gfr_summary(rep("update",1000L))$unique_count==1L)
  ok(gfr_covariance(diag(1,3),FALSE)$full_spectrum_evaluated==FALSE)
  out <- tempfile("generated_glofas_forensic_");dir.create(out)
  path <- file.path(out,"small.json")
  gfr_write(gfr_json_raw(list(only_generated=TRUE)),path,out,1024^2)
  ok(file.exists(path));reject(gfr_write(charToRaw("x"),path,out,1024^2),"fresh output")
  reject(gfr_write(raw(10L),file.path(out,"too_big"),out,1L),"budget")
  unlink(path);unlink(out) # Only this test's own tiny generated fixture.
  cat(sprintf("GLOFAS_FIXED_TARGET_FORENSIC_GENERATED_PASS checks=%d original_RDS_reads=0 saved_callback_calls=%d\n",n,callback_calls))
})
