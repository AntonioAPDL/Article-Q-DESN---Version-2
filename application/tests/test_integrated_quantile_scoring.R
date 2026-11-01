#!/usr/bin/env Rscript
local({
  root <- if (exists("app_repo_root",mode="function")) app_repo_root() else {
    arg <- grep("^--file=",commandArgs(FALSE),value=TRUE)[[1L]]
    normalizePath(file.path(dirname(sub("^--file=","",arg)),"..",".."))
  }
  source(file.path(root,"application/R/integrated_quantile_forecast.R"),local=TRUE)
  source(file.path(root,"scripts/integrated_quantile_blocks.R"),local=TRUE)
  source(file.path(root,"scripts/score_integrated_quantile_forecasts.R"),local=TRUE)
  p <- c(.1,.5,.9); q <- c(-.5,.5,1.5); w <- c(.2,.4,.2)
  contract <- list(method="dkw_response_cdf",alpha_per_shard=.05,max_split_absolute=.1,
    max_split_relative=.1,max_quantile_abs_error=.1,max_quantile_rel_error=.1)
  shard <- list(schema_version="integrated_quantile_forecast_shard_v1",
    quantiles=data.frame(model_id="m",draw_id="d1",origin_id="o",horizon=1L,
      probability=p,quantile=q,functional="parameter_conditional_integrated_quantile",
      outer_conditioning="parameters_and_observed_origin_reservoir_state"),
    outer_conditioning="parameters_and_observed_origin_reservoir_state",
    identity=list(source_manifest_sha256=strrep("a",64),posterior_target_sha256=strrep("b",64),
      outer_conditioning="parameters_and_observed_origin_reservoir_state"),
    integration_status="PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE",
    integration_resolution=10000L,integration_accuracy_contract=contract,
    integration_accuracy_contract_sha256=app_iqf_hash(contract),
    integration_diagnostic=data.frame(horizon=1L, probability=p,split_stream_absolute_difference=rep(.01,3),
      split_stream_relative_difference=rep(.01,3)),
    integration_dkw=data.frame(horizon=1L,probability=p,lower=q-.01,upper=q+.01,max_estimate_error_bound=rep(.01,3),
      empirical_cdf_epsilon=sqrt(log(40)/20000),alpha_per_draw_origin=.05))
  oracle <- list(forecast_map=data.frame(origin_id="o",horizon=1L),
    observed_y=1,sorted_response=matrix(c(-1,0,1,2)),prefix_response=matrix(c(-1,-1,0,2)),
    diagnostics=data.frame(status="pass"))
  result <- app_iqf_score_shard(shard,oracle,p,w)
  first<-shard;first$draw_id<-"d1";first$origin_id<-"o"
  second<-first;second$draw_id<-"d2";second$quantiles$draw_id<-"d2"
  packed<-app_iqf_pack_block(list(first,second))
  decoded_scores<-app_iqf_forecast_members(packed,function(s)app_iqf_score_shard(s,oracle,p,w))
  original_scores<-lapply(list(first,second),function(s)app_iqf_score_shard(s,oracle,p,w))
  stopifnot(identical(decoded_scores,original_scores))
  direct <- sum(2*w*vapply(seq_along(p),function(k) mean((c(-1,0,1,2)-q[k])*
    (p[k]-(c(-1,0,1,2)<q[k]))),numeric(1L)))
  stopifnot(abs(result$score_sum-direct)<1e-12,result$score_count==1L,
    result$score_label=="DGP_integrated_finite_grid_acrps")
  blocks <- list(result,transform(result,origin_id="o2",score_sum=result$score_sum*3))
  keys <- c("m|d1|o|1","m|d1|o2|1")
  agg <- app_iqf_aggregate_scores(blocks,keys)
  stopifnot(abs(agg$draw_scores$score-result$score_sum*2)<1e-12)
  ref <- data.frame(origin_id="o",horizon=1L,probability=p,reference_quantile=q+.2,
    reference_kind="realized_DGP_quantile_path")
  rec <- app_iqf_quantile_recovery(shard,ref)
  stopifnot(max(abs(rec$absolute_error-.2))<1e-12,max(abs(rec$squared_error-.04))<1e-12)
  rejected <- 0L
  reject <- function(expr) {
    error <- tryCatch({force(expr);NULL},error=identity)
    stopifnot(inherits(error,"error"));rejected<<-rejected+1L
  }
  producer_identity <- list(task_id="forecast-accepted",source_commit=strrep("1",40),
    source_tree=strrep("2",40),source_manifest_sha256=strrep("a",64),
    posterior_target_sha256=strrep("b",64),input_manifest_sha256=strrep("c",64),
    task_manifest_sha256=strrep("d",64),rng_namespace="original-scientific-draws")
  producer <- list(task_id=producer_identity$task_id,
    task_manifest_sha256=producer_identity$task_manifest_sha256,
    posterior_target_sha256=producer_identity$posterior_target_sha256,
    output_manifest_sha256=strrep("e",64),identity=producer_identity,
    artifacts=list(list(relative_path="block_001.rds",sha256=strrep("f",64),bytes=1234L)))
  input <- data.frame(relative_path="copied/block_001.rds",size_bytes=1234L,
    sha256=strrep("f",64),role="accepted_forecast_shard")
  producer_binding <- list(input_relative_path=input$relative_path,
    producer_task_id=producer$task_id,producer_relative_path="block_001.rds",
    producer_output_manifest_sha256=producer$output_manifest_sha256)
  score_spec <- list(forecast_shards=list(input$relative_path),producer_bindings=list(producer_binding))
  claim <- list(verified=TRUE,accepted_prerequisites=list(producer))
  score_request <- list(task_id="score-new")
  resolved <- app_iqf_score_bind_producers(score_request,score_spec,input,claim,"score")
  stopifnot(identical(names(resolved),input$relative_path),
    identical(resolved[[1]]$sha256,input$sha256),resolved[[1]]$size_bytes==1234L,
    identical(resolved[[1]]$identity,producer_identity))
  producer_member <- shard;producer_member$identity <- c(producer_identity,
    list(outer_conditioning=shard$outer_conditioning))
  stopifnot(isTRUE(app_iqf_score_member_producer(producer_member,resolved[[1]])))
  wire_claim <- jsonlite::fromJSON(jsonlite::toJSON(claim,auto_unbox=TRUE),simplifyVector=FALSE)
  wire_spec <- jsonlite::fromJSON(jsonlite::toJSON(score_spec,auto_unbox=TRUE),simplifyVector=FALSE)
  wire_bound <- app_iqf_score_bind_producers(score_request,wire_spec,input,wire_claim,"score")
  stopifnot(wire_bound[[1]]$size_bytes==resolved[[1]]$size_bytes,
    identical(wire_bound[[1]]$sha256,resolved[[1]]$sha256),
    isTRUE(app_iqf_score_member_producer(producer_member,wire_bound[[1]])))
  bad <- score_spec;bad$producer_bindings <- NULL
  reject(app_iqf_score_bind_producers(score_request,bad,input,claim,"score"))
  bad <- claim;bad$accepted_prerequisites <- NULL
  reject(app_iqf_score_bind_producers(score_request,score_spec,input,bad,"score"))
  bad <- claim;bad$verified <- FALSE
  reject(app_iqf_score_bind_producers(score_request,score_spec,input,bad,"score"))
  for (field in c("producer_task_id","producer_relative_path","producer_output_manifest_sha256")) {
    bad <- score_spec;bad$producer_bindings[[1]][[field]] <- "different"
    reject(app_iqf_score_bind_producers(score_request,bad,input,claim,"score"))
  }
  bad <- claim;bad$accepted_prerequisites <- rep(list(producer),2L)
  reject(app_iqf_score_bind_producers(score_request,score_spec,input,bad,"score"))
  bad <- input;bad$size_bytes <- 1235L
  reject(app_iqf_score_bind_producers(score_request,score_spec,bad,claim,"score"))
  bad <- input;bad$sha256 <- strrep("0",64)
  reject(app_iqf_score_bind_producers(score_request,score_spec,bad,claim,"score"))
  for (field in c("task_manifest_sha256","posterior_target_sha256")) {
    bad <- claim;bad$accepted_prerequisites[[1]][[field]] <- strrep("0",64)
    reject(app_iqf_score_bind_producers(score_request,score_spec,input,bad,"score"))
  }
  bad <- claim;bad$accepted_prerequisites[[1]]$artifacts <- rep(producer$artifacts,2L)
  reject(app_iqf_score_bind_producers(score_request,score_spec,input,bad,"score"))
  bad <- score_spec;bad$producer_bindings <- rep(list(producer_binding),2L)
  reject(app_iqf_score_bind_producers(score_request,bad,input,claim,"score"))
  twice <- rbind(input,transform(input,relative_path="copied/again.rds"))
  bad <- score_spec;bad$forecast_shards <- as.list(twice$relative_path)
  duplicate <- producer_binding;duplicate$input_relative_path <- twice$relative_path[2L]
  bad$producer_bindings <- list(producer_binding,duplicate)
  reject(app_iqf_score_bind_producers(score_request,bad,twice,claim,"score"))
  bad <- score_spec;bad$producer_bindings[[1]]$input_relative_path <- "unused.rds"
  reject(app_iqf_score_bind_producers(score_request,bad,input,claim,"score"))
  bad <- score_spec;bad$forecast_shards <- rep(score_spec$forecast_shards,2L)
  reject(app_iqf_score_bind_producers(score_request,bad,input,claim,"score"))
  bad <- rbind(input,transform(input,relative_path="unused.rds"))
  reject(app_iqf_score_bind_producers(score_request,score_spec,bad,claim,"score"))
  bad <- input;bad$role <- "accepted_score_block"
  reject(app_iqf_score_bind_producers(score_request,score_spec,bad,claim,"score"))
  reject(app_iqf_score_bind_producers(list(task_id=producer$task_id),score_spec,input,claim,"score"))
  bad <- score_spec;bad$producer_bindings[[1]]$producer_relative_path <- "../block_001.rds"
  reject(app_iqf_score_bind_producers(score_request,bad,input,claim,"score"))
  bad <- score_spec;bad$producer_bindings[[1]]$unverified_extra <- TRUE
  reject(app_iqf_score_bind_producers(score_request,bad,input,claim,"score"))
  bad <- score_spec;bad$producer_bindings[[1]] <- c(producer_binding,
    list(producer_task_id=producer$task_id))
  reject(app_iqf_score_bind_producers(score_request,bad,input,claim,"score"))
  bad <- producer_member;bad$identity$task_id <- "different-producer"
  reject(app_iqf_score_member_producer(bad,resolved[[1]]))
  bad <- producer_member;bad$identity$source_manifest_sha256 <- NULL
  reject(app_iqf_score_member_producer(bad,resolved[[1]]))
  aggregate_spec <- list(score_blocks=score_spec$forecast_shards,producer_bindings=score_spec$producer_bindings)
  aggregate_input <- transform(input,role="accepted_score_block")
  aggregate_bound <- app_iqf_score_bind_producers(score_request,aggregate_spec,aggregate_input,claim,"aggregate")
  stopifnot(identical(aggregate_bound,resolved))
  reject(app_iqf_score_bind_producers(score_request,aggregate_spec,aggregate_input,
    list(verified=TRUE),"aggregate"))
  bad <- shard;bad$integration_status <- "REVIEW";reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$integration_dkw <- NULL;reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$integration_accuracy_contract$method <- "split_stream_diagnostic";reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$integration_dkw$upper[1] <- Inf;reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$integration_dkw$probability <- rev(p);reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$integration_diagnostic$horizon[1] <- 2;reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$integration_resolution <- 1.5;reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$quantiles$functional <- "averaged_feature_location";reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$outer_conditioning <- "parameters_and_joint_retained_origin_state";reject(app_iqf_score_shard(bad,oracle,p,w))
  bad <- shard;bad$quantiles$outer_conditioning[1] <- "unspecified";reject(app_iqf_score_shard(bad,oracle,p,w))
  reject(app_iqf_score_shard(shard,oracle,p,w/sum(w)))
  bad <- oracle;bad$prefix_response[1,1] <- 99;reject(app_iqf_score_shard(shard,bad,p,w))
  bad <- oracle;bad$diagnostics$status <- "extend";reject(app_iqf_score_shard(shard,bad,p,w))
  reject(app_iqf_aggregate_scores(c(blocks,blocks[1]),keys))
  reject(app_iqf_aggregate_scores(blocks,keys[1]))
  bad <- ref;bad$reference_kind <- "response_accuracy";reject(app_iqf_quantile_recovery(shard,bad))
  reject(app_iqf_quantile_recovery(shard,ref[-1,]))
  scratch <- tempfile("iqf_score_bytes_");dir.create(scratch)
  written <- app_iqf_score_write(result,file.path(scratch,"scores.csv"),"csv",10000,0)
  stopifnot(written==file.info(file.path(scratch,"scores.csv"))$size)
  reject(app_iqf_score_write(result,file.path(scratch,"too_large.csv"),"csv",1,0))
  stopifnot(!file.exists(file.path(scratch,"too_large.csv")))
  reject(app_iqf_score_write(result,file.path(scratch,"cumulative.csv"),"csv",written,written))
  reject(app_iqf_score_write(result,file.path(scratch,"scores.csv"),"csv",10000,0))
  stopifnot(identical(app_iqf_score_key_hash(c("b","a")),digest::digest('["a","b"]',algo="sha256",serialize=FALSE)))
  cat(sprintf("INTEGRATED_QUANTILE_SCORING_PASS mutation_rejections=%d production_runs=0\n",rejected))
})
