#!/usr/bin/env Rscript
local({
  root <- if (exists("app_repo_root",mode="function")) app_repo_root() else {
    arg <- grep("^--file=",commandArgs(FALSE),value=TRUE)[[1L]]
    normalizePath(file.path(dirname(sub("^--file=","",arg)),"..",".."))
  }
  source(file.path(root,"application/R/integrated_quantile_forecast.R"),local=TRUE)
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
