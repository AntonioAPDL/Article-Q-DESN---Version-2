# Synthetic metadata and forecast algebra only. No actual fit or truth is read.
local({
source("scripts/glofas_same_family_closeout.R")
source("scripts/finalize_glofas_same_family_transition.R")
source("scripts/check_glofas_same_family_article_projection.R")
source("scripts/glofas_same_family_plot_inputs.R")
source("application/R/glofas_family_transition.R")
gsc_test_checks <- 0L
ok <- function(x) {stopifnot(isTRUE(x));gsc_test_checks <<- gsc_test_checks+1L;invisible(TRUE)}
reject <- function(expr,pattern=NULL) {
  error <- tryCatch({force(expr);NULL},error=function(e)e)
  ok(inherits(error,"error"))
  if(!is.null(pattern)) {
    if(!grepl(pattern,conditionMessage(error),fixed=TRUE))stop("Expected rejection '",pattern,"'; got '",conditionMessage(error),"'.")
    ok(TRUE)
  }
}
clone <- function(x)unserialize(serialize(x,NULL))
tmp <- tempfile("glofas_synthetic_closeout_");dir.create(tmp)
write_json <- function(x,path)jsonlite::write_json(x,path,auto_unbox=TRUE,pretty=TRUE,digits=17)
roundtrip <- function(x)jsonlite::fromJSON(jsonlite::toJSON(x,auto_unbox=TRUE,digits=17),simplifyVector=FALSE)
identity <- gsc_identity()
producer <- function(id)list(task_id=id,state="accepted",numerical_gates_pass=TRUE,
  identity=c(list(task_id=id),identity,list(rng_namespace=id,routing_id=paste0("route-",id))),
  claim_nonce=paste0("nonce-",id),output_manifest_sha256=strrep("a",64L),
  terminal=list(exit_code=0L,accounting_complete=TRUE,owner_terminated=TRUE,worker_terminated=TRUE,timed_out=FALSE),
  artifacts=lapply(c("fit.rds","forecast_quantiles.csv","raw_crossings.csv","target_receipt.json",
    "progress.csv","artifact_manifest.csv"),function(p)list(relative_path=p,path=p,size_bytes=1L,sha256=strrep("b",64L))))
collection <- list(schema_version="glofas_same_family_accepted_collection_v1",
  status="SIXTEEN_ACCEPTED_PRODUCERS_REVERIFIED",producers=lapply(gsc_tasks(),producer),
  ledger_mutations=0L,fit_objects_loaded=0L,future_truth_read=FALSE,article_publication_authorized=FALSE)
ok(gsc_validate_collection(roundtrip(collection),identity))
bad <- clone(collection);bad$producers <- bad$producers[-16L]
reject(gsc_validate_collection(bad,identity),"sixteen")
bad <- clone(collection);bad$producers[[2L]] <- bad$producers[[1L]]
reject(gsc_validate_collection(bad,identity),"sixteen")
bad <- identity;bad$posterior_target_sha256 <- strrep("0",64L)
reject(gsc_validate_collection(collection,bad),"fitting-source")
for(field in c("source_tree","posterior_target_sha256","rng_namespace")) {
  bad <- clone(collection);bad$producers[[1L]]$identity[[field]] <- "wrong"
  reject(gsc_validate_collection(bad,identity),"identity")
}
for(field in c("accounting_complete","owner_terminated","worker_terminated")) {
  bad <- clone(collection);bad$producers[[1L]]$terminal[[field]] <- FALSE
  reject(gsc_validate_collection(bad,identity),"accounting")
}
bad <- clone(collection);bad$producers[[1L]]$artifacts[[1L]]$relative_path <- "weighted_fit.rds"
reject(gsc_validate_collection(bad,identity),"artifact set")

receipt <- function(id) {
  blocks <- if(startsWith(id,"gft-mq-"))7L else 1L
  list(schema_version="glofas_family_transition_fit_v1",task_id=id,converged=TRUE,status="converged",
    claim_nonce=paste0("nonce-",id),identity=producer(id)$identity,
    target_contract=app_glofas_family_transition_contract(),
    counts=list(horizons=28L,members=51L,historical_Y=12455L,historical_G=12455L,
      residual_jacobian_determinant=1L,future_Y=28L,future_G=1428L,quantile_blocks=blocks,
      total_future_Y=28L*blocks,total_future_G=1428L*blocks,replacement_gaussian_path_prior=FALSE),
    feature_contract=list(two_block_design=TRUE,discrepancy_input_stream="discrepancy",
      discrepancy_transition_strategy="recursive_level",reference_coefficients=1501L,discrepancy_coefficients=1001L))
}
for(id in gsc_tasks())ok(gsc_validate_target(roundtrip(receipt(id)),producer(id)))
for(field in c("reference_future_law","product_location","ensemble_factorization","response_summary","initializer_role")) {
  bad <- receipt(gsc_tasks()[1L]);bad$target_contract[[field]] <- "legacy_target"
  reject(gsc_validate_target(bad,producer(bad$task_id)),"target rejected")
}
for(field in c("future_truth_used_in_fit","replacement_gaussian_path_prior","extra_response_noise","isotonic_adjustment")) {
  bad <- receipt(gsc_tasks()[1L]);bad$target_contract[[field]] <- TRUE
  reject(gsc_validate_target(bad,producer(bad$task_id)),"target rejected")
}
bad <- receipt("gft-mq-al");bad$counts$future_Y <- 0L
reject(gsc_validate_target(bad,producer(bad$task_id)),"factor counts")
bad <- receipt("gft-mq-al");bad$counts$total_future_Y <- 28L
reject(gsc_validate_target(bad,producer(bad$task_id)),"factor counts")
bad <- receipt("gft-mq-al");bad$converged <- FALSE
reject(gsc_validate_target(bad,producer(bad$task_id)),"convergence")
bad <- receipt("gft-mq-al");bad$feature_contract$discrepancy_input_stream <- "reference"
reject(gsc_validate_target(bad,producer(bad$task_id)),"feature contract")

quantile_rows <- function(id) {
  r <- expand.grid(horizon=1:28,tau=gsc_task_tau(id));r <- r[order(r$horizon,r$tau),]
  r$target_date <- as.character(gsc_dates()[r$horizon]);r$path_factor_mean <- 3+.005*r$horizon
  r$path_factor_sd <- .4;r$quantile_transformed <- r$path_factor_mean+r$path_factor_sd*qnorm(r$tau)
  r$quantile <- expm1(r$quantile_transformed);r$task_id <- id
  r$estimand <- "marginal_future_response_quantile_under_ensemble_conditioned_VB"
  r$approximation <- "Gaussian_path_factor_with_local_Delta_and_coefficient_factorization"
  r$extra_response_noise_added <- FALSE;r$quantile_functional_credible_interval <- FALSE;r
}
quantiles <- setNames(lapply(gsc_tasks(),quantile_rows),gsc_tasks())
nr <- do.call(rbind,lapply(c("normal_ridge","normal_rhs"),function(m) {
  r <- quantile_rows("gft-mq-al");r$task_id <- NULL;r$model <- m;r$fit_reused <- TRUE;r
}))
prepared_sha <- strrep("e",64L)
normal <- list(schema_version="glofas_normal_reporting_enrollment_receipt_v1",
  status="TWO_BASELINES_ENROLLED_NOT_ARTICLE_AUTHORITY",
  source_commit="cfa50ff3f4eebbdbf36c03c50b04bf2bed39c437",new_model_fits=0L,scoring_calls=0L,
  source_tree="13090d12f6de3551e8f49f1f862e4a4f621ffda7",
  design_identity=list(schema_version="glofas_normal_design_mapping_v2",status="EXACT_PROTECTED_DESIGN_MATCH",
    exact_comparison=TRUE,closure_context_and_all_compiled_bindings_identical=TRUE,scoring_truth_read=FALSE,
    new_model_fits=0L,builder_calls=0L,historical_Y=12455L,historical_G=12455L,future_Y=28L,future_G=1428L),
  publication_performed=FALSE,prepared_design=list(sha256=prepared_sha),
  models=setNames(lapply(1:2,function(i)list(status="FIT_REUSE_AND_NEW_ANALYTIC_REPORT_VERIFIED",
    fit_reused=TRUE,new_model_fits=0L,model_calls=0L,builder_calls=0L,expected_rows=196L,scoring_truth_read=FALSE,
    new_reporting=list(schema_version="glofas_normal_analytic_reporting_v1",
      tau=gsc_tau(),horizons=28L,response_factor="full_ensemble_conditioned_q_U_Normal",
      transformed_quantile="m_U_h+sqrt(V_U_hh)*qnorm(p)",inverse_transform="expm1",isotonic_adjustment=FALSE,
      fit_reused=TRUE,new_model_fits=0L,scoring_truth_read=FALSE,
      historical_reporting="latent_future_path_empirical_quantiles_type8",
      extra_response_noise_added=FALSE,quantile_functional_credible_interval=FALSE))),c("normal_ridge","normal_rhs")))
normal_rows <- gsc_normal_rows(nr,roundtrip(normal),prepared_sha)
ok(nrow(normal_rows)==392L)
bad <- clone(normal);bad$models$normal_rhs$new_reporting$schema_version <- "empirical_type8"
reject(gsc_normal_rows(nr,bad,prepared_sha),"analytic fit reuse")
reject(gsc_normal_rows(nr,normal,strrep("f",64L)),"enrollment")
bad <- nr;bad$path_factor_mean[1L] <- bad$path_factor_mean[1L]+1
reject(gsc_normal_rows(bad,normal,prepared_sha),"analytic quantiles")
members <- expand.grid(horizon=1:28,member=sprintf("member%02d",1:51),stringsAsFactors=FALSE)
members$target_date <- as.character(gsc_dates()[members$horizon])
members$g_transformed <- 2+members$horizon*.01+rep(seq(-.5,.5,length.out=51L),each=28L)
rows <- gsc_assemble(quantiles,normal_rows,members)
ok(nrow(rows)==1372L&&nrow(gsc_raw_rows(members))==196L)
ok(all(gsc_crossings(rows)$adjacent_comparisons==168L)&&all(gsc_crossings(rows)$raw_crossing_pairs==0))
reject(gsc_assemble(quantiles[-1L],normal_rows,members),"all quantile tasks")
bad <- members[-1L,];reject(gsc_raw_rows(bad),"member grid")
bad <- members;bad$member[1L] <- bad$member[29L];bad$horizon[1L] <- bad$horizon[29L]
reject(gsc_raw_rows(bad),"member grid")
bad <- rows;bad$tau[1L] <- .1;reject(gsc_validate_grid(bad),"forecast key")
bad <- rows;bad$target_date[1L] <- "2022-12-25";reject(gsc_validate_grid(bad),"dates")
bad <- rows;bad$quantile[1L] <- Inf;reject(gsc_validate_grid(bad),"transformation")
bad <- rows;bad$quantile[1L] <- bad$quantile[1L]+1;reject(gsc_validate_grid(bad),"transformation")
bad <- quantiles[[1L]];bad$extra_response_noise_added <- TRUE
reject(gsc_quantile_rows(bad,gsc_tasks()[1L]),"report functional")
truth <- data.frame(target_date=as.character(gsc_dates()),horizon=1:28,y_transformed=rep(3.2,28L))
score <- gsc_score(rows,truth)
ok(nrow(score$summary)==7L&&nrow(score$by_date)==196L&&nrow(score$calibration)==49L)
ok(abs(sum(score$score_contract$weights)-.9)<1e-15&&!score$score_contract$weights_renormalized)
manual <- vapply(1:28,function(h) {
  z <- rows[rows$family=="Independent AL"&rows$horizon==h,];z <- z[order(z$tau),]
  l <- ifelse(3.2>=z$quantile_transformed,z$tau*(3.2-z$quantile_transformed),
    (1-z$tau)*(z$quantile_transformed-3.2))
  sum(diff(z$tau)*(head(l,-1L)+tail(l,-1L)))
},numeric(1L))
ok(abs(mean(manual)-score$summary$grid_acrps_log1p[score$summary$family=="Independent AL"])<1e-14)
bad <- truth;bad$horizon[1L] <- 2L;reject(gsc_score(rows,bad),"scoring-only")
bad <- rows;i <- which(bad$family=="MQ AL"&bad$horizon==1L)
bad$quantile_transformed[i[c(1L,7L)]] <- bad$quantile_transformed[i[c(7L,1L)]]
bad$quantile <- expm1(bad$quantile_transformed)
inverted <- gsc_score(bad,truth)
ok(inverted$summary$inverted_intervals[inverted$summary$family=="MQ AL"]==1L)
ok(inverted$crossings$raw_crossing_pairs[inverted$crossings$family=="MQ AL"]==2L)
ok(identical(bad$quantile_transformed,rows$quantile_transformed)==FALSE) # Never silently project.

scope <- list(schema_version="glofas_same_family_closeout_contract_v1",mode="assemble",allow_refit=FALSE,
  allow_retuning=FALSE,allow_publication=FALSE,allow_assembly=TRUE,allow_scoring=FALSE,
  limits=list(cpu_seconds=120,wall_seconds=120,memory_bytes=2*1024^3,output_bytes=2*1024^2,logical_cpu=28))
ok(gsc_closeout_scope(scope,"assemble"))
bad <- clone(scope);bad$allow_publication <- TRUE;reject(gsc_closeout_scope(bad,"assemble"),"authority")
bad <- clone(scope);bad$limits$logical_cpu <- 24;reject(gsc_closeout_scope(bad,"assemble"),"budget")
bad <- clone(scope);bad$limits$wall_seconds <- Inf;reject(gsc_closeout_scope(bad,"assemble"),"budget")
reject(gsc_closeout_main(c("--contract","missing","--sha256",strrep("a",64),"--mode","score")),"execute")

# A complete synthetic score packet exercises independent projection readback.
packet <- file.path(tmp,"packet");dir.create(packet)
write.csv(rows,file.path(packet,"quantile_paths.csv"),row.names=FALSE)
write.csv(truth,file.path(packet,"scoring_truth.csv"),row.names=FALSE)
write.csv(score$summary,file.path(packet,"family_scores.csv"),row.names=FALSE)
write.csv(score$by_date,file.path(packet,"scores_by_date.csv"),row.names=FALSE)
write.csv(score$calibration,file.path(packet,"quantile_calibration.csv"),row.names=FALSE)
write.csv(score$crossings,file.path(packet,"raw_crossings.csv"),row.names=FALSE)
write_json(score$score_contract,file.path(packet,"score_contract.json"))
write_json(collection,file.path(packet,"accepted_producers.json"))
bindings <- setNames(lapply(1:5,function(i)list(path=paste0("/synthetic/not-read/",i),
  size_bytes=1L,sha256=strrep("d",64L))),c("normal_manifest","normal_receipt","normal_quantiles",
    "raw_member_derivation","raw_members"))
write_json(gsc_make_forecast_seal(packet,bindings,prepared_sha),file.path(packet,"FORECAST_SEAL.json"))
forecast_seal <- unname(tools::sha256sum(file.path(packet,"FORECAST_SEAL.json")))
ok(is.list(gsc_verify_forecast_seal(packet,forecast_seal)))
write_json(list(schema_version="glofas_same_family_closeout_receipt_v1",
  status="READY_FOR_SCIENTIFIC_REVIEW_NOT_AUTOMATIC_PUBLICATION",mode="score",future_truth_read=TRUE,
  model_selection_or_retuning=FALSE,new_fits=0L,article_publication_authorized=FALSE,expected_identity=identity,
  forecast_seal_sha256=forecast_seal),
  file.path(packet,"DECISION.json"))
write_json(list(status="CLOSEOUT_TERMINAL_NOT_PUBLICATION"),file.path(packet,"progress.json"))
seal <- function() {
  paths <- list.files(packet,full.names=TRUE);paths <- paths[basename(paths)!="artifact_manifest.csv"]
  write.csv(data.frame(relative_path=basename(paths),size_bytes=file.info(paths)$size,
    sha256=unname(tools::sha256sum(paths))),file.path(packet,"artifact_manifest.csv"),row.names=FALSE)
  unname(tools::sha256sum(file.path(packet,"artifact_manifest.csv")))
}
digest <- seal();ok(is.list(gsc_check_packet(packet,digest)))
candidate <- file.path(tmp,"candidate");gsc_build_candidate(packet,digest,candidate)
ok(gsc_check_candidate(packet,digest,candidate))
ok(any(grepl("MQ--DESN",readLines(file.path(candidate,"candidate_score_table.tex")),fixed=TRUE)))
writeLines("wrong labels",file.path(candidate,"candidate_score_table.tex"))
reject(gsc_check_candidate(packet,digest,candidate),"labels")
# Re-sealing is intentional: these checks test semantic mutations, not just hashes.
changed <- score$summary;changed$coverage90[1L] <- .123
write.csv(changed,file.path(packet,"family_scores.csv"),row.names=FALSE)
digest <- seal();reject(gsc_check_packet(packet,digest),"summary check loss or coverage")
write.csv(score$summary,file.path(packet,"family_scores.csv"),row.names=FALSE)
changed <- score$score_contract;changed$weights_renormalized <- TRUE
write_json(changed,file.path(packet,"score_contract.json"))
digest <- seal();reject(gsc_check_packet(packet,digest),"score definition")
write_json(score$score_contract,file.path(packet,"score_contract.json"))
changed <- score$calibration;changed$empirical_coverage[1L] <- .123
write.csv(changed,file.path(packet,"quantile_calibration.csv"),row.names=FALSE)
digest <- seal();reject(gsc_check_packet(packet,digest),"calibration values")
write.csv(score$calibration,file.path(packet,"quantile_calibration.csv"),row.names=FALSE)
# Updating the final artifact manifest cannot legitimize changed pre-truth rows.
changed <- rows;changed$quantile_transformed[1L] <- changed$quantile_transformed[1L]+.01
changed$quantile <- expm1(changed$quantile_transformed)
write.csv(changed,file.path(packet,"quantile_paths.csv"),row.names=FALSE)
digest <- seal();reject(gsc_check_packet(packet,digest),"pinned regular input")
write.csv(rows,file.path(packet,"quantile_paths.csv"),row.names=FALSE)
writeLines("not allowed",file.path(packet,"fit.rds"))
digest <- seal();reject(gsc_check_packet(packet,digest),"inventory")

f <- file.path(tmp,"pinned.csv");writeLines("synthetic",f)
pin <- list(path=f,size_bytes=file.info(f)$size,sha256=unname(tools::sha256sum(f)))
ok(identical(gsc_pin(pin),f));bad <- pin;bad$sha256 <- strrep("0",64L);reject(gsc_pin(bad),"bytes changed")
link <- file.path(tmp,"linked.csv");ok(file.symlink(f,link));bad <- pin;bad$path <- link
reject(gsc_pin(bad),"symlink")

# The extraction code sees only tiny, generated historical/member fixtures.
hist <- data.frame(target_date=seq(as.Date("2022-11-26"),as.Date("2022-12-25"),by="day"),
  y_transformed=seq(2,3,length.out=30),g_transformed=seq(2.1,3.1,length.out=30))
ens <- members;ens$origin_date <- "2022-12-25";ens$ensemble_weight <- 1;ens$y_transformed <- NA_real_
data <- list(future_truth_policy="physically_excluded_from_fit_objects_scoring_sidecar_only",
  historical_panel=hist,y_history=hist,g_retro=hist,g_ensemble=ens)
design <- list(future_truth_policy="physically_excluded_from_fit_objects_scoring_sidecar_only",
  ensemble_member_weight_policy="unit_member_likelihood_v1",family_transition_contract=app_glofas_family_transition_contract(),
  two_block_design=TRUE,latent_data=data,future_context=list(latent_data=data),base_panel=hist,
  future_key=data.frame(target_date=gsc_dates(),horizon=1:28),
  future_builder=function(...)stop("This extraction must never call a feature builder."))
extracted <- gsc_plot_input_tables(design)
ok(nrow(extracted$history)==30L&&nrow(extracted$issued_members)==1428L&&nrow(extracted$raw_members)==1428L)
ok(identical(names(extracted$raw_members),c("target_date","horizon","member","g_transformed")))
bad <- clone(design);bad$latent_data$g_ensemble$y_transformed[1L] <- 9
reject(gsc_plot_input_tables(bad),"unredacted future USGS")
bad <- clone(design);bad$future_context$future_truth <- 9
reject(gsc_plot_input_tables(bad),"unsafe embedded truth")
bad <- clone(design);bad$latent_data$historical_panel$target_date[1L] <- as.Date("2022-12-26")
reject(gsc_plot_input_tables(bad),"post-origin")
bad <- clone(design);bad$base_panel <- bad$base_panel[-1L,]
reject(gsc_plot_input_tables(bad),"thirty consecutive")
bad <- clone(design);bad$latent_data$g_ensemble$ensemble_weight[1L] <- 1/51
reject(gsc_plot_input_tables(bad),"unit-weight")
bad <- clone(collection);bad$producers <- bad$producers[-16L]
reject(gsc_extract_authorized(list(),bad,NULL,NULL,NULL,NULL),"sixteen")
extract_scope <- scope;extract_scope$mode <- "extract";extract_scope$allow_assembly <- FALSE
extract_scope$allow_design_read <- TRUE
ok(gsc_closeout_scope(extract_scope,"extract"))
extract_scope$allow_design_read <- FALSE
reject(gsc_closeout_scope(extract_scope,"extract"),"authority")
unlink(tmp,recursive=TRUE) # Only this test-created, uniquely named fixture directory.
cat("GloFAS same-family closeout synthetic tests PASS:",gsc_test_checks,"checks\n")
})
