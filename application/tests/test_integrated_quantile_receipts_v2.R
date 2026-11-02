#!/usr/bin/env Rscript
local({
  root <- if (exists("app_repo_root", mode="function")) app_repo_root() else {
    file <- sub("^--file=", "", grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
    normalizePath(file.path(dirname(file),"..",".."),mustWork=TRUE)
  }
  source(file.path(root,"scripts/mq_independent_cdf_certificate.R"),local=TRUE)
  source(file.path(root,"scripts/mq_streaming_cdf_certificate.R"),local=TRUE)
  source(file.path(root,"scripts/integrated_quantile_receipts_v2.R"),local=TRUE)
  checks <- 0L
  check <- function(x) {stopifnot(isTRUE(x));checks <<- checks+1L}
  reject <- function(expr) {
    error <- tryCatch({force(expr);NULL},error=base::identity)
    check(inherits(error,"error"))
  }
  candidate <- data.frame(horizon=rep(1:2,each=3),probability=rep(c(.25,.5,.75),2),
    quantile=rep(qnorm(c(.25,.5,.75)),2))
  split <- transform(candidate[c("horizon","probability")],
    split_stream_absolute_difference=0,split_stream_relative_difference=0)
  contract <- list(schema_version="mq_streaming_cdf_certificate_contract_v1",
    method="heldout_conditional_CDF_empirical_Bernstein_alpha_spending",
    conditioning="one_fixed_original_parameter_draw_and_observed_origin",
    validation_values="iid_future_path_conditional_CDF_not_particle_filter",
    candidates_from_training_paths_only=TRUE,rng_namespace="synthetic-v2",draw_id="d1",origin_id="o1",
    training_path_range=c(1,65536),validation_path_range=c(65537,327680),
    look_sizes=c(65536,131072,262144),total_alpha=.05,alpha_per_look=rep(.05/3,3),
    absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01,
    training_split_diagnostic=split)
  identity <- list(source_commit=strrep("a",40),source_tree=strrep("b",40),
    source_manifest_sha256=strrep("c",64),posterior_target_sha256=strrep("d",64),
    input_manifest_sha256=strrep("e",64),task_manifest_sha256=strrep("f",64),
    task_id="synthetic",rng_namespace="synthetic-v2",
    outer_conditioning="parameters_and_observed_origin_reservoir_state")
  before <- if (exists(".Random.seed",.GlobalEnv,inherits=FALSE)) get(".Random.seed",.GlobalEnv) else NULL
  state <- mq_scc_init(candidate,contract)
  values <- matrix(rep(pnorm(state$grid$endpoints$y),each=65536L),65536L,
    dimnames=list(NULL,state$grid$endpoints$endpoint_id))
  state <- mq_scc_update(state,values,65537:131072)
  state <- mq_scc_evaluate(state)
  check(state$last_evaluation$all_required_gates_pass)
  receipt <- iqr2_from_stream_state(state,identity)
  checked <- iqr2_validate(receipt,candidate,identity)
  check(!checked$production_authorized && !checked$source_authentication_provided)
  check(max(abs(checked$radius-state$last_evaluation$endpoint_evidence$radius)) < 1e-14)
  check(identical(checked$quantile_error,pmax(.01,.01*abs(candidate$quantile))))
  check(as.numeric(object.size(receipt)) < as.numeric(object.size(state)))
  reseal <- function(x) {x$integrity_sha256<-NULL;x$integrity_sha256<-iqr2_hash(x);x}
  mutate <- list(
    function(x) {x$schema_version<-"unknown";x},
    function(x) {x$method<-"dkw_response_cdf";x},
    function(x) {x$look_index<-4L;x},
    function(x) {x$validation_count<-65535L;x},
    function(x) {x$validation_first_path_id<-65536L;x},
    function(x) {x$validation_last_path_id<-131073L;x},
    function(x) {x$stream_contract$look_sizes[1]<-65535L;x},
    function(x) {x$stream_contract$total_alpha<-.06;x},
    function(x) {x$stream_contract$alpha_per_look[1]<-.05;x},
    function(x) {x$stream_contract$conditioning<-"particle_filter";x},
    function(x) {x$stream_contract$training_path_range<-c(2,65537);x},
    function(x) {x$stream_contract$absolute_quantile_tolerance<-.011;x},
    function(x) {x$stream_contract$production_authorized<-TRUE;x},
    function(x) {x$cdf_mean[1]<-1.1;x},
    function(x) {x$cdf_mean[]<-.5;x},
    function(x) {x$cdf_M2[1]<--1;x},
    function(x) {x$cdf_M2[1]<-x$validation_count;x},
    function(x) {x$stream_contract$training_split_diagnostic$split_stream_absolute_difference[1]<-.006;
      x$stream_contract$training_split_diagnostic$split_stream_relative_difference[1]<-.006;x},
    function(x) {x$stream_contract$training_split_diagnostic$probability[1]<-.2;x},
    function(x) {x$origin_id<-"o2";x},
    function(x) {x$identity$input_manifest_sha256<-strrep("0",64);x},
    function(x) {x$candidates_sha256<-strrep("0",64);x},
    function(x) {x$validation_chain_sha256<-"invalid";x})
  for (f in mutate) reject(iqr2_validate(reseal(f(receipt)),candidate,identity))
  wrong <- candidate;wrong$quantile[1]<-wrong$quantile[1]+.001
  reject(iqr2_validate(receipt,wrong,identity))
  bad <- receipt;bad$cdf_mean[1]<-bad$cdf_mean[1]+.001
  reject(iqr2_validate(bad,candidate,identity))
  make_shard <- function(draw) {
    r <- receipt;r$draw_id<-draw;r$stream_contract$draw_id<-draw;r<-reseal(r)
    q <- transform(candidate,model_id="synthetic_mq",draw_id=draw,origin_id="o1",
      functional="parameter_conditional_integrated_quantile",
      outer_conditioning="parameters_and_observed_origin_reservoir_state",rng_namespace="synthetic-v2")
    list(schema_version="integrated_quantile_forecast_shard_v2",model_id="synthetic_mq",draw_id=draw,origin_id="o1",
      forecast_functional="parameter_conditional_integrated_quantile",
      outer_conditioning="parameters_and_observed_origin_reservoir_state",identity=identity,
      quantiles=q,numerical_receipt=r)
  }
  shards <- lapply(c("d1","d2"),make_shard)
  block <- iqr2_pack(shards)
  for (i in 1:2) check(identical(iqr2_unpack(block,i),shards[[i]]))
  check(identical(unserialize(serialize(block,NULL,version=3L)),block))
  reject(iqr2_pack(c(shards,shards[1L])))
  mixed <- shards; mixed[[2L]]$model_id <- "another_model"
  mixed[[2L]]$quantiles$model_id <- "another_model"
  reject(iqr2_pack(mixed))
  reject(iqr2_unpack(block,0));reject(iqr2_unpack(block,1.5))
  bad <- block;bad$members[[1]]$quantiles$quantile[1]<-0
  reject(iqr2_unpack(bad,1))
  bad <- block;bad$members[[2]]$model_id <- "another_model"
  bad$members[[2]]$quantiles$model_id <- "another_model"
  bad$integrity_sha256 <- NULL; bad$integrity_sha256 <- iqr2_hash(bad)
  reject(iqr2_unpack(bad,1))
  check(!identical(iqr2_member_key("a|origin:b", "c"),
    iqr2_member_key("a", "b|origin:c")))
  for (f in list(
    function(x) {x$quantiles$functional<-"mean_feature";x},
    function(x) {x$identity$outer_conditioning<-"parameters_only_integrate_filtered_origin_state";x},
    function(x) {x$quantiles$draw_id<-"d3";x},
    function(x) {x$schema_version<-"integrated_quantile_forecast_shard_v1";x}
  )) reject(iqr2_validate_shard(f(shards[[1L]])))
  after <- if (exists(".Random.seed",.GlobalEnv,inherits=FALSE)) get(".Random.seed",.GlobalEnv) else NULL
  check(identical(before,after))
  cat(sprintf("INTEGRATED_QUANTILE_RECEIPTS_V2_CHECKS=%d PASS; source authentication/production not provided\n",checks))
})
