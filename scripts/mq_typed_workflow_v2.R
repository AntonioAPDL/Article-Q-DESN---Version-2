# Opt-in generated-only wiring. No source, host or production admission.
# The unchanged v1 DKW worker/controller/scorer and receipt modules remain valid.
for(f in c("application/R/integrated_quantile_forecast.R","scripts/mq_forecast_array_methods.R",
 "scripts/mq_independent_cdf_certificate.R","scripts/mq_streaming_cdf_certificate.R",
 "scripts/integrated_quantile_receipts_v2.R","scripts/score_integrated_quantile_forecasts.R"))source(f)
mqw2_require<-function(ok,why)if(!isTRUE(ok))stop(paste0("MQ_TYPED_V2: ",why),call.=FALSE)
mqw2_context<-function(scope) {
 mqw2_require(identical(scope,"generated_fixture_only"),
  "production is not admitted: native measure/coupling, confidence/score precision, retention, method/source/host and full cost gates remain open")
 invisible(TRUE)
}
mqw2_preflight<-function()list(schema_version="mq_typed_workflow_preflight_v2",
 status="MQ_PRODUCTION_NOT_ADMITTED",allow_launch=FALSE,
 unresolved=c("authenticated_native_inventory_weights_and_coupling","production_confidence_and_score_error_contract",
 "production_retention_and_pricing","production_worker_method_source_requalification_MP01",
 "host_and_full_campaign_cost_admission","canonical_ledger_v2_authorization_protocol"))
mqw2_cdf_rows<-function(y,q,tau) {
 mqw2_require(is.matrix(q)&&is.numeric(q)&&nrow(q)>0&&ncol(q)==length(tau)&&
  all(is.finite(q))&&all(q[,-1L,drop=FALSE]>=q[,-ncol(q),drop=FALSE]),"ordered individual kernels required")
 app_iqf_grid(q[1L,],tau);out<-matrix(0,nrow(q),length(y));K<-length(tau)
 for(j in seq_along(y)) {
  index<-rowSums(q<=y[j]);v<-as.numeric(index==K);rows<-which(index>0&index<K)
  if(length(rows)) {k<-index[rows];lo<-q[cbind(rows,k)];hi<-q[cbind(rows,k+1L)]
   v[rows]<-tau[k]+(tau[k+1L]-tau[k])*(y[j]-lo)/(hi-lo)}
  out[,j]<-v
 }
 mqw2_require(all(is.finite(out))&&all(out>=0&out<=1),"invalid path-specific CDF")
 out
}
mqw2_run_unit<-function(provider,draw_id,origin_id,model_id,identity,tau,H,scope="NOT_ADMITTED") {
 mqw2_context(scope);iqr2_identity(identity)
 mqw2_require(is.function(provider)&&is.numeric(H)&&length(H)==1L&&H%in%1:30,
  "explicit generated path provider and finite geometry required")
 app_iqf_grid(rep(0,length(tau)),tau);K<-length(tau);N<-65536L
 fetch<-function(ids) {
  z<-provider(ids)
  mqw2_require(is.numeric(z)&&identical(dim(z),c(length(ids),K,as.integer(H)))&&all(is.finite(z)),
   "provider changed path count/grid/horizon or returned nonfinite kernels")
  for(h in seq_len(H))mqw2_require(all(z[,-1L,h,drop=FALSE]>=z[,-K,h,drop=FALSE]),"provider kernels must retain native ordering")
  z
 }
 training<-array(NA_real_,c(N,K,as.integer(H)))
 for(first in seq.int(1L,N,by=128L)) {ids<-first:min(N,first+127L);training[ids,,]<-fetch(ids)}
 candidates<-split<-vector("list",H)
 for(h in seq_len(H)) {
  q<-matrix(training[,,h],N,K)
  full<-app_iqf_mq_matrix_inverse(q,tau,tau,1e-8)
  left<-app_iqf_mq_matrix_inverse(q[1:32768,,drop=FALSE],tau,tau,1e-8)
  right<-app_iqf_mq_matrix_inverse(q[32769:65536,,drop=FALSE],tau,tau,1e-8)
  candidates[[h]]<-data.frame(horizon=h,probability=tau,quantile=full)
  split[[h]]<-data.frame(horizon=h,probability=tau,split_stream_absolute_difference=abs(left-right),
   split_stream_relative_difference=abs(left-right)/pmax(1,abs((left+right)/2)))
 }
 candidates<-do.call(rbind,candidates);split<-do.call(rbind,split);rm(training)
 freeze<-iqr2_candidate_hash(candidates)
 if(!all(split$split_stream_absolute_difference<=.005|split$split_stream_relative_difference<=.005))
  return(list(status="REVIEW_TRAINING_SPLIT_NO_VALIDATION",candidates=candidates,training_split=split,
   production_authorized=FALSE,validation_paths_generated=0L))
 contract<-list(schema_version="mq_streaming_cdf_certificate_contract_v1",
  method="heldout_conditional_CDF_empirical_Bernstein_alpha_spending",
  conditioning="one_fixed_original_parameter_draw_and_observed_origin",
  validation_values="iid_future_path_conditional_CDF_not_particle_filter",candidates_from_training_paths_only=TRUE,
  rng_namespace=identity$rng_namespace,draw_id=draw_id,origin_id=origin_id,
  training_path_range=c(1L,65536L),validation_path_range=c(65537L,327680L),
  look_sizes=c(65536L,131072L,262144L),total_alpha=.05,alpha_per_look=rep(.05/3,3),
  absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01,training_split_diagnostic=split)
 state<-mq_scc_init(candidates,contract)
 for(look in contract$look_sizes) {
  for(first in seq.int(state$count+1L,look,by=128L)) {
   relative<-first:min(look,first+127L);ids<-65536L+relative;kernels<-fetch(ids)
   values<-matrix(NA_real_,length(ids),state$grid$endpoint_count,
    dimnames=list(NULL,state$grid$endpoints$endpoint_id))
   for(h in seq_len(H)) {at<-which(state$grid$endpoints$horizon==h)
    values[,at]<-mqw2_cdf_rows(state$grid$endpoints$y[at],matrix(kernels[,,h],length(ids),K),tau)}
   state<-mq_scc_update(state,values,ids)
  }
  state<-mq_scc_evaluate(state);if(state$terminal)break
 }
 mqw2_require(identical(freeze,iqr2_candidate_hash(candidates)),"training candidates changed")
 if(!state$last_evaluation$all_required_gates_pass)return(list(status="REVIEW_VALIDATION_PRECISION",
  candidates=candidates,stream_state=state,production_authorized=FALSE))
 receipt<-iqr2_from_stream_state(state,identity)
 quantiles<-transform(candidates,model_id=model_id,draw_id=draw_id,origin_id=origin_id,
  functional="parameter_conditional_integrated_quantile",
  outer_conditioning="parameters_and_observed_origin_reservoir_state",rng_namespace=identity$rng_namespace)
 shard<-list(schema_version="integrated_quantile_forecast_shard_v2",model_id=model_id,draw_id=draw_id,origin_id=origin_id,
  forecast_functional="parameter_conditional_integrated_quantile",outer_conditioning=identity$outer_conditioning,
  identity=identity,quantiles=quantiles,numerical_receipt=receipt)
 iqr2_validate_shard(shard)
 list(status="GENERATED_TYPED_MEMBER_NUMERICALLY_VALID_NOT_PRODUCTION",shard=shard,
  source_authentication_provided=FALSE,production_authorized=FALSE)
}
mqw2_normalize<-function(x)jsonlite::fromJSON(jsonlite::toJSON(x,auto_unbox=TRUE,dataframe="rows",digits=17,null="null"),simplifyVector=FALSE)
mqw2_equal_metadata<-function(a,b) {
 if(is.list(a)&&is.list(b)) {
  if(length(a)!=length(b)||is.null(names(a))!=is.null(names(b)))return(FALSE)
  if(!is.null(names(a))) {if(anyDuplicated(names(a))||anyDuplicated(names(b))||!setequal(names(a),names(b)))return(FALSE);b<-b[names(a)]}
  return(all(vapply(seq_along(a),function(i)mqw2_equal_metadata(a[[i]],b[[i]]),logical(1L))))
 }
 if(is.numeric(a)&&is.numeric(b))return(length(a)==length(b)&&isTRUE(all(as.double(a)==as.double(b))))
 identical(a,b)
}
mqw2_wire<-function(block,block_sha256) {
 members<-lapply(seq_along(block$members),function(i) {
  s<-iqr2_unpack(block,i)
  list(member_key=block$member_keys[i],model_id=s$model_id,draw_id=s$draw_id,origin_id=s$origin_id,
   quantiles=s$quantiles[c("horizon","probability","quantile")],receipt=s$numerical_receipt)
 })
 list(schema_version="mq_typed_numerical_wire_v2",execution_scope="generated_fixture_only",production_authorized=FALSE,
  identity=block$members[[1]]$identity,expected_member_keys=block$member_keys,
  block_file_sha256=block_sha256,members=members)
}
mqw2_write_packet<-function(shards,output,scope="NOT_ADMITTED") {
 mqw2_context(scope);mqw2_require(is.character(output)&&length(output)==1L&&startsWith(output,"/")&&
  !file.exists(output)&&dir.exists(dirname(output))&&identical(normalizePath(dirname(output),mustWork=TRUE),dirname(output)),
  "fresh canonical generated output required")
 block<-iqr2_pack(shards);bytes<-serialize(block,NULL,version=3L)
 mqw2_require(length(bytes)<8*1024^2,"generated-only block cap8MiB exceeded; production retention remains undecided")
 dir.create(output);path<-file.path(output,"typed_block.rds");writeBin(bytes,path)
 wire<-mqw2_wire(block,app_iqf_hash(path,TRUE))
 jsonlite::write_json(wire,file.path(output,"numerical_wire.json"),auto_unbox=TRUE,dataframe="rows",pretty=TRUE,digits=17,null="null")
 paths<-file.path(output,c("typed_block.rds","numerical_wire.json"))
 manifest<-data.frame(relative_path=basename(paths),size_bytes=as.numeric(file.info(paths)$size),sha256=unname(tools::sha256sum(paths)))
 write.csv(manifest,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
 invisible(list(block=block,wire=wire,manifest=manifest))
}
mqw2_validate_packet<-function(output) {
 mqw2_require(is.character(output)&&length(output)==1L&&identical(normalizePath(output,mustWork=TRUE),output)&&
  !nzchar(Sys.readlink(output)),"canonical packet directory required")
 path<-file.path(output,"typed_block.rds");wire_path<-file.path(output,"numerical_wire.json")
 mqw2_require(file.exists(path)&&!nzchar(Sys.readlink(path))&&file.info(path)$size<8*1024^2&&
  file.exists(wire_path)&&!nzchar(Sys.readlink(wire_path))&&file.info(wire_path)$size<4*1024^2,"bounded generated packet required")
 manifest_path<-file.path(output,"artifact_manifest.csv")
 mqw2_require(file.exists(manifest_path)&&!nzchar(Sys.readlink(manifest_path))&&file.info(manifest_path)$size<65536,
  "bounded exact artifact manifest required")
 m<-read.csv(manifest_path,stringsAsFactors=FALSE)
 mqw2_require(identical(names(m),c("relative_path","size_bytes","sha256"))&&nrow(m)==2L&&
  !anyDuplicated(m$relative_path)&&setequal(m$relative_path,c("typed_block.rds","numerical_wire.json"))&&
  setequal(list.files(output,all.files=TRUE,no..=TRUE),c(m$relative_path,"artifact_manifest.csv")),"packet manifest membership changed")
 for(i in 1:2) {p<-file.path(output,m$relative_path[i]);mqw2_require(file.info(p)$size==m$size_bytes[i]&&
  identical(app_iqf_hash(p,TRUE),m$sha256[i]),"packet artifact bytes changed")}
 wire<-jsonlite::read_json(wire_path,simplifyVector=FALSE)
 mqw2_context(wire$execution_scope);mqw2_require(identical(wire$production_authorized,FALSE),"invalid production scope")
 block<-readRDS(path) # Newly generated compact block only, never a fit/cache.
 expected<-mqw2_normalize(mqw2_wire(block,app_iqf_hash(path,TRUE)))
 mqw2_require(mqw2_equal_metadata(expected,wire),"wire values/identity are not bound to independently decoded block")
 list(block=block,wire=wire)
}
mqw2_score_member<-function(shard,oracle,probabilities,weights,scope="NOT_ADMITTED") {
 mqw2_context(scope);iqr2_validate_shard(shard) # Before examining any oracle value.
 p<-as.numeric(probabilities);weights<-as.numeric(weights)
 mqw2_require(length(p)>=2&&all(is.finite(p))&&all(diff(p)>0)&&p[1]>0&&tail(p,1)<1,
  "finite ordered score probabilities required")
 expected<-c(diff(p)[1]/2,if(length(p)>2)(p[3:length(p)]-p[1:(length(p)-2)])/2 else numeric(),tail(diff(p),1)/2)
 mqw2_require(length(p)>=2&&length(weights)==length(p)&&all(is.finite(weights))&&all(weights>0)&&
  all(abs(weights-expected)<1e-12),"unchanged unnormalized trapezoidal weights required")
 q<-shard$quantiles
 for(h in unique(q$horizon))mqw2_require(identical(as.numeric(q$probability[q$horizon==h]),p),
  "score probability membership differs")
 keys<-app_iqf_score_oracle(oracle,"oracle_acrps")
 out<-lapply(sort(unique(q$horizon)),function(h) {
  rows<-q[q$horizon==h,];rows<-rows[order(rows$probability),]
  mqw2_require(identical(as.numeric(rows$probability),p),"score probability membership differs")
  at<-match(paste(shard$origin_id,h,sep="|"),keys);mqw2_require(!is.na(at),"missing oracle key")
  loss<-vapply(seq_along(p),function(k)app_iqf_score_expected_check(rows$quantile[k],p[k],
   oracle$sorted_response[,at],oracle$prefix_response[,at]),numeric(1L))
  error<-2*sum(weights*pmax(p,1-p)*pmax(.01,.01*abs(rows$quantile)))
  data.frame(draw_id=shard$draw_id,origin_id=shard$origin_id,horizon=h,score_sum=2*sum(weights*loss),
   score_count=1L,numerical_quantile_error_score_bound=error,production_authorized=FALSE)
 })
 do.call(rbind,out)
}
mqw2_score_accepted<-function(packet,acceptance,oracle,probabilities,weights,scope="NOT_ADMITTED") {
 mqw2_context(scope);p<-mqw2_validate_packet(packet);a<-acceptance
 mqw2_require(is.list(a)&&identical(a$schema_version,"mq_generated_central_acceptance_v2")&&
  identical(a$status,"GENERATED_TYPED_V2_ACCEPTED_NOT_PRODUCTION")&&identical(a$production_authorized,FALSE)&&
  mqw2_equal_metadata(mqw2_normalize(p$wire$identity),a$identity)&&
  identical(a$block_file_sha256,p$wire$block_file_sha256)&&
  identical(a$wire_sha256,app_iqf_hash(file.path(packet,"numerical_wire.json"),TRUE))&&
  identical(as.character(unlist(a$expected_member_keys)),as.character(unlist(p$wire$expected_member_keys))),
  "accepted producer identity/keys/block/wire differ")
 # Every numerical member is independently validated before forcing the
 # separately supplied oracle promise; acceptance booleans never waive this.
 shards<-lapply(seq_along(p$block$members),function(i)iqr2_unpack(p$block,i))
 do.call(rbind,lapply(shards,function(s)mqw2_score_member(s,oracle,probabilities,weights,scope)))
}
mqw2_generated_fixture<-function(output) {
 mqw2_require(!file.exists(paste0(output,".request.json")),"generated request must be fresh")
 tau<-c(.1,.5,.9)
 identity<-list(source_commit=strrep("a",40),source_tree=strrep("b",40),source_manifest_sha256=strrep("c",64),
  posterior_target_sha256=strrep("d",64),input_manifest_sha256=strrep("e",64),task_manifest_sha256=strrep("f",64),
  task_id="generated_v2_worker_fixture",rng_namespace="generated_degenerate_iid_CDF_fixture_v2",
  outer_conditioning="parameters_and_observed_origin_reservoir_state")
 draws<-c("generated_d1","generated_d2");origin<-"generated_o1"
 keys<-unname(vapply(draws,function(d)iqr2_member_key(d,origin),""))
 request<-list(schema_version="mq_generated_workflow_request_v2",execution_scope="generated_fixture_only",
  production_authorized=FALSE,identity=identity,expected_member_keys=as.list(keys),
  model_id="generated_constant_MQ",probabilities=tau,horizons=1L)
 jsonlite::write_json(request,paste0(output,".request.json"),auto_unbox=TRUE,pretty=TRUE,digits=17)
 shards<-lapply(seq_along(draws),function(i) {
  values<-if(i==1L)c(-1,0,1)else c(-25,0,25)
  provider<-function(ids)array(rep(values,each=length(ids)),c(length(ids),3L,1L))
  run<-mqw2_run_unit(provider,draws[i],origin,"generated_constant_MQ",identity,tau,1L,"generated_fixture_only")
  mqw2_require(identical(run$status,"GENERATED_TYPED_MEMBER_NUMERICALLY_VALID_NOT_PRODUCTION"),"generated numerical example failed")
  run$shard
 })
 mqw2_write_packet(shards,output,"generated_fixture_only")
 invisible(request)
}
