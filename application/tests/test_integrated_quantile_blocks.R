#!/usr/bin/env Rscript
local({
  root <- if (exists("app_repo_root", mode="function")) app_repo_root() else {
    file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value=TRUE)[1L])
    normalizePath(file.path(dirname(file), "..", ".."))
  }
  source(file.path(root, "application/R/integrated_quantile_forecast.R"), local=TRUE)
  source(file.path(root, "scripts/integrated_quantile_blocks.R"), local=TRUE)
  fixture <- function(i, origin="o1") {
    q <- data.frame(model_id="m",draw_id=paste0("d",i),origin_id=origin,
      horizon=rep(1:2,each=3),probability=rep(c(.1,.5,.9),2),
      quantile=seq_len(6)/7+i/11,functional="parameter_conditional_integrated_quantile",
      outer_conditioning="parameters_and_observed_origin_reservoir_state",
      inner_paths=4096L,rng_namespace="test")
    list(schema_version="integrated_quantile_forecast_shard_v1",quantiles=q,
      paths=NULL,original_draw=list(chain_id=c("chain1","chain2"),source_draw_index=c(i,i+4L)),
      draw_id=paste0("d",i),origin_id=origin,model_id="m",rng_namespace="test",
      outer_conditioning="parameters_and_observed_origin_reservoir_state",
      identity=list(source_manifest_sha256=strrep("a",64),posterior_target_sha256=strrep("b",64)),
      integration_resolution=4096L,
      integration_diagnostic=data.frame(horizon=q$horizon,probability=q$probability,
        split_stream_absolute_difference=seq_len(6)*i/100,
        split_stream_relative_difference=seq_len(6)*i/200,left_paths=2048L,right_paths=2048L),
      integration_dkw=data.frame(horizon=q$horizon,probability=q$probability,
        lower=q$quantile-.1,upper=q$quantile+.1,max_estimate_error_bound=.1,
        empirical_cdf_epsilon=.03,alpha_per_draw_origin=.05,scope="one_draw_origin"),
      integration_status=if(i%%2L) "PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE" else "REVIEW_INNER_INTEGRATION_RESOLUTION",
      integration_accuracy_contract=list(method="dkw_response_cdf",alpha_per_shard=.05),
      integration_accuracy_contract_sha256=strrep("e",64))
  }
  shards <- lapply(1:7,fixture)
  block <- app_iqf_pack_block(shards)
  stopifnot(block$n_members==7L)
  for(i in seq_along(shards)) stopifnot(identical(app_iqf_unpack_member(block,i),shards[[i]]))
  named <- setNames(shards,paste0("member",seq_along(shards)))
  stopifnot(identical(app_iqf_unpack_member(app_iqf_pack_block(named),3L),shards[[3L]]))
  object <- unserialize(serialize(block,NULL,version=3L))
  stopifnot(identical(app_iqf_forecast_members(object,identity),shards))
  stopifnot(identical(app_iqf_forecast_members(shards[[1L]],identity),shards[1L]))
  # Arrival/storage grouping cannot change any numerical value or original ID.
  regrouped <- c(app_iqf_forecast_members(app_iqf_pack_block(shards[1:3]),identity),
    app_iqf_forecast_members(app_iqf_pack_block(shards[4:7]),identity))
  stopifnot(identical(regrouped,shards))
  short<-fixture(8L,"last_origin")
  short$quantiles<-short$quantiles[1:3,]
  short$integration_diagnostic<-short$integration_diagnostic[1:3,]
  short$integration_dkw<-short$integration_dkw[1:3,]
  stopifnot(!app_iqf_same_geometry(shards[[1L]],short),app_iqf_same_geometry(shards[[1L]],shards[[2L]]))
  # A trailing short origin gets its own block; no intended member disappears.
  stream<-c(shards,list(short));groups<-list();buffer<-list()
  for(member in stream) {
    if(length(buffer)&&!app_iqf_same_geometry(buffer[[1L]],member)) {
      groups[[length(groups)+1L]]<-app_iqf_pack_block(buffer);buffer<-list()
    }
    buffer[[length(buffer)+1L]]<-member
  }
  groups[[length(groups)+1L]]<-app_iqf_pack_block(buffer)
  stopifnot(length(groups)==2L,identical(do.call(c,lapply(groups,function(x)
    app_iqf_forecast_members(x,identity))),stream))
  rejected<-0L
  reject<-function(expr) {
    err<-tryCatch({force(expr);NULL},error=identity)
    stopifnot(inherits(err,"error"));rejected<<-rejected+1L
  }
  reject(app_iqf_pack_block(list()))
  reject(app_iqf_pack_block(rep(shards[1L],1001)))
  reject(app_iqf_pack_block(c(shards,shards[1L])))
  bad<-shards;bad[[2L]]$identity$posterior_target_sha256<-strrep("c",64);reject(app_iqf_pack_block(bad))
  bad<-shards;bad[[2L]]$quantiles$probability[1L]<-.2;reject(app_iqf_pack_block(bad))
  bad<-shards;bad[[2L]]$quantiles$origin_id<-"wrong";reject(app_iqf_pack_block(bad))
  bad<-shards;bad[[2L]]$integration_accuracy_contract$alpha_per_shard<-.01;reject(app_iqf_pack_block(bad))
  bad<-shards;bad[[2L]]$integration_dkw$scope<-"different";reject(app_iqf_pack_block(bad))
  reject(app_iqf_unpack_member(block,0L));reject(app_iqf_unpack_member(block,8L))
  reject(app_iqf_unpack_member(block,1.5))
  bad<-block;bad$quantile_values<-bad$quantile_values[-1L,,drop=FALSE];reject(app_iqf_unpack_member(bad,1L))
  bad<-block;bad$member_keys[2L]<-bad$member_keys[1L];reject(app_iqf_unpack_member(bad,1L))
  bad<-block;bad$metadata[[2L]]$draw_id<-"forged";reject(app_iqf_unpack_member(bad,2L))
  bad<-block;bad$diagnostic$values$left_paths<-matrix(1L,2,7);reject(app_iqf_unpack_member(bad,1L))
  scratch<-tempfile("iqf_block_");dir.create(scratch)
  saveRDS(block,file.path(scratch,"block.rds"))
  table<-data.frame(relative_path="block.rds",member_index=seq_along(shards),
    size_bytes=file.info(file.path(scratch,"block.rds"))$size,
    sha256=app_iqf_hash(file.path(scratch,"block.rds"),TRUE),
    integration_status=vapply(shards,`[[`,"","integration_status"),artifact_key=block$member_keys)
  request<-list(task_id="task",source_commit=strrep("a",40),source_tree=strrep("b",40),
    source_manifest_sha256=strrep("a",64),posterior_target_sha256=strrep("b",64),
    input_manifest_sha256=strrep("c",64),task_manifest_sha256=strrep("d",64),rng_namespace="test",
    routing_id="route",expected_output_keys=as.list(block$member_keys),expected_output_keys_sha256=strrep("e",64))
  claim<-list(verified=TRUE,task_id="task",routing_id="route",claim_nonce="nonce")
  app_iqf_write_output_index(table,file.path(scratch,"output_manifest.csv"),100000,0)
  envelope<-app_iqf_block_envelope(request,claim,table,scratch)
  stopifnot(length(envelope$shards)==7L,length(envelope$artifacts)==2L,!envelope$numerical_gates_pass)
  bad<-table;bad$member_index[2L]<-1L;reject(app_iqf_block_envelope(request,claim,bad,scratch))
  bad<-table;bad$integration_status[2L]<-"PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE"
  reject(app_iqf_block_envelope(request,claim,bad,scratch))
  bad<-table;bad$sha256[2L]<-strrep("f",64);reject(app_iqf_block_envelope(request,claim,bad,scratch))
  reject(app_iqf_write_output_index(table,file.path(scratch,"too_big.csv"),1,0))
  stopifnot(!file.exists(file.path(scratch,"too_big.csv")))
  reject(app_iqf_write_output_index(table,file.path(scratch,"output_manifest.csv"),100000,0))
  cat(sprintf("INTEGRATED_QUANTILE_BLOCKS_PASS exact_members=%d mutation_rejections=%d production_runs=0\n",
    length(shards),rejected))
})
