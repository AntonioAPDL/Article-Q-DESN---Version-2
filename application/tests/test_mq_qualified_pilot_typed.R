#!/usr/bin/env Rscript
# All files below are newly generated fixtures, never actual pilot evidence.
local({
  source("scripts/consume_mq_qualified_pilot.R",local=TRUE)
  n<-0L;ok<-function(x){stopifnot(isTRUE(x));n<<-n+1L}
  reject<-function(x)ok(inherits(tryCatch({force(x);NULL},error=identity),"error"))
  root<-tempfile("mq_typed_own_generated_");stopifnot(dir.create(root))
  out<-file.path(root,"pilot");admin<-file.path(root,"admin");stopifnot(dir.create(out),dir.create(admin))
  pin<-function(p)list(path=normalizePath(p),size_bytes=as.numeric(file.info(p)$size),sha256=mqp2_sha(p))
  json<-function(x,p){jsonlite::write_json(x,p,auto_unbox=TRUE,pretty=TRUE,digits=17,null="null");pin(p)}
  rds<-function(x,p){saveRDS(x,p,compress=FALSE,version=3);pin(p)}
  tau<-c(.05,.1,.25,.5,.75,.9,.95);model<-"asymmetric_laplace_tail__joint_qdesn_rhs"
  draw<-paste0(model,"/chain_01/draw_000001");namespace<-paste0("integrated_quantile_forecast_v1/",model,"/chain_01")
  unit<-list(schema_version="integrated_quantile_qualification_contract_v1",purpose="MQ_Q2_ONE_DRAW_ORIGIN",source_schema="mq_native_worker_v1",
    model_cell_id=model,chain_id=1L,source_row=1L,source_draw_index=1L,origin_id=1L,origin_time=11000L,horizons=30L,
    inner_paths=4096L,readout_slopes=20L,tau=tau,rng_namespace=namespace,
    posterior_target_sha256="45ffff64921e5985546d174cb28f44441c161fac3d13de3e8f4d65e67a17ab1c",
    integration_accuracy=list(method="dkw_response_cdf",alpha_per_shard=.05,max_split_absolute=.005,max_split_relative=.005,
      max_quantile_abs_error=.01,max_quantile_rel_error=.01))
  candidates<-data.frame(horizon=rep(1:30,each=7),probability=rep(tau,30),quantile=rep(2*tau-1,30))
  split<-transform(candidates[c("horizon","probability")],split_stream_absolute_difference=0,split_stream_relative_difference=0)
  contract<-list(schema_version="mq_streaming_cdf_certificate_contract_v1",method="heldout_conditional_CDF_empirical_Bernstein_alpha_spending",
    conditioning="one_fixed_original_parameter_draw_and_observed_origin",validation_values="iid_future_path_conditional_CDF_not_particle_filter",
    candidates_from_training_paths_only=TRUE,rng_namespace=namespace,draw_id=draw,origin_id="1",training_path_range=c(1L,65536L),
    validation_path_range=c(65537L,327680L),look_sizes=c(65536L,131072L,262144L),total_alpha=.05,alpha_per_look=rep(.05/3,3),
    absolute_quantile_tolerance=.01,relative_quantile_tolerance=.01,training_split_diagnostic=split)
  state<-mq_scc_init(candidates,contract)
  means<-pmax(0,pmin(1,(state$grid$endpoints$y+1)/2))
  values<-matrix(rep(means,each=128L),128L,dimnames=list(NULL,state$grid$endpoints$endpoint_id))
  for(first in seq.int(65537L,131072L,by=128L))state<-mq_scc_update(state,values,first:(first+127L))
  state<-mq_scc_evaluate(state);ok(state$last_evaluation$all_required_gates_pass)
  pins<-list(candidates=rds(candidates,file.path(out,"frozen_training_candidates.rds")),
    split=rds(split,file.path(out,"training_split_diagnostic.rds")),stream=rds(state,file.path(out,"validation_stream_look_065536.rds")))
  parity_pin<-rds(list(generated_only=TRUE),file.path(out,"training_parity.rds"))
  p<-list(schema_version="mq_native_source_replay_v1",purpose="NATIVE_COMPOSED_ONE_ORIGINAL_DRAW_ORIGIN",allow_qualification=TRUE,
    allow_refit=FALSE,allow_scoring=FALSE,allow_production=FALSE,allow_article=FALSE,allow_future_truth=FALSE,allow_raw_fixture_deserialization=FALSE,C_ABI_qualified=FALSE,
    source_commit=strrep("a",40),source_tree=strrep("b",40),original_unit=unit,output_root=out,administrative_unit_name="generated-unit.service",
    source_manifest=list(sha256=strrep("c",64)),prepared_manifest=list(sha256=strrep("d",64)),original_unit_contract=list(sha256=strrep("e",64)))
  pins$pilot_purpose<-json(p,file.path(admin,"purpose.json"));p<-jsonlite::read_json(pins$pilot_purpose$path,simplifyVector=FALSE)
  f<-list(schema_version="mq_native_training_freeze_v1",source_commit=p$source_commit,purpose_contract_sha256=pins$pilot_purpose$sha256,
    candidate_phase="BEFORE_ANY_VALIDATION_PATH",split_pass=TRUE,training_path_range=c(1,65536),validation_paths_generated=0,
    artifacts=list(pins$candidates,pins$split,parity_pin))
  pins$freeze<-json(f,file.path(out,"CANDIDATES_FROZEN.json"));f<-jsonlite::read_json(pins$freeze$path,simplifyVector=FALSE)
  r<-list(schema_version="mq_native_source_replay_receipt_v1",status="GENUINE_NATIVE_SOURCE_REPLAY_COMPLETE_NOT_PRODUCTION",
    numerical_status="PASS_NATIVE_ONE_ORIGINAL_UNIT_SOURCE_REGRESSION_ONLY",source_commit=p$source_commit,source_tree=p$source_tree,
    purpose_contract_sha256=pins$pilot_purpose$sha256,original_unit=unit,training_paths=65536,training_split_gate_pass=TRUE,validation_paths=65536,
    validation_paths_generated_before_freeze=0,freeze_sha256=pins$freeze$sha256,full_campaign_enrollment=FALSE,production_consumer_qualified=FALSE,
    C_ABI_qualified=FALSE,observational_future_truth_used=FALSE,production_authorized=FALSE,article_promotion_authorized=FALSE,
    parameter_refits=0,score_evaluations=0,raw_fixture_deserializations=0,raw_design_deserializations=0,final_certificate=state$last_evaluation)
  pins$qualification<-json(r,file.path(out,"qualification.json"));r<-jsonlite::read_json(pins$qualification$path,simplifyVector=FALSE)
  files<-list.files(out,full.names=TRUE)
  manifest<-data.frame(relative_path=basename(files),size_bytes=as.numeric(file.info(files)$size),sha256=unname(tools::sha256sum(files)))
  write.csv(manifest,file.path(out,"artifact_manifest.csv"),row.names=FALSE);pins$manifest<-pin(file.path(out,"artifact_manifest.csv"))
  outputs<-c(lapply(seq_len(nrow(manifest)),function(i)as.list(manifest[i,])),list(c(list(relative_path="artifact_manifest.csv"),pins$manifest[c("size_bytes","sha256")])))
  h<-list(status="EXECUTION_PENDING_FINAL_INACTIVE_READBACK",failures=list(),successful_actual_stop_post_proof=TRUE,
    schema_version="mq_native_external_terminal_receipt_v1",actor="mq-native-replay",phase="stop-post",
    unit=p$administrative_unit_name,source_commit=p$source_commit,source_tree=p$source_tree,purpose_sha256=pins$pilot_purpose$sha256,
    grant_sha256=strrep("f",64),outputs=outputs,
    payload_native_time=list(exit_code=0,user_cpu_seconds=2,system_cpu_seconds=1,wall_seconds=4,peak_rss_kib=1000),
    unit_state=list(Id=p$administrative_unit_name,MainPID="0",Result="success",ExecMainStatus="0",ActiveState="deactivating",
      SubState="stop-post",ExecMainCode="1",ControlGroup=paste0("/user.slice/",p$administrative_unit_name)))
  pins$stop_post<-json(h,file.path(admin,"STOP_POST_RECEIPT.json"));h<-jsonlite::read_json(pins$stop_post$path,simplifyVector=FALSE)
  t<-h;t$phase<-"final";t$independently_linked_successful_stop_post<-TRUE;t$stop_post_receipt_sha256<-pins$stop_post$sha256
  t$numerical_status<-r$numerical_status;t$production_authorized<-FALSE;t$article_promotion_authorized<-FALSE
  t$status<-"EXECUTION_COMPLETE_NOT_PRODUCTION";t$unit_state$ActiveState<-"inactive";t$unit_state$SubState<-"dead"
  t$unit_state$ExecMainCode<-"0";t$unit_state$ControlGroup<-""
  pins$terminal<-json(t,file.path(admin,"FINAL_SUPERVISOR_READBACK.json"));t<-jsonlite::read_json(pins$terminal$path,simplifyVector=FALSE)
  time<-c("User time (seconds): 0.01","System time (seconds): 0.01","Elapsed (wall clock) time (h:mm:ss or m:ss): 0:00.02",
    "Maximum resident set size (kbytes): 1000","Exit status: 0")
  writeLines(time,file.path(admin,"finalizer.time.txt"));pins$finalizer_time<-pin(file.path(admin,"finalizer.time.txt"))
  meta<-list(pilot_purpose=p,qualification=r,freeze=f,terminal=t,stop_post=h,finalizer_time=time)
  ok(mqp2_roles(pins)>0);ok(mqp2_links(meta,pins,manifest))
  cost<-mqp2_read_cost(pins);ok(cost$selected_input_hash_bytes_before_and_after==2*cost$selected_distinct_evidence_bytes&&cost$RDS_deserializations==3L)
  ci<-list(source_commit=strrep("1",40),source_tree=strrep("2",40),purpose_sha256=strrep("3",64))
  made<-mqp2_make(meta,pins,manifest,candidates,split,state,ci)
  packet<-file.path(root,"typed");sha<-mqp2_write(made,packet)
  proof<-mqp2_readback(packet,sha);ok(proof$independent_bound_recomputation&&!proof$production_authorized)
  consumer<-list(schema_version="mq_qualified_pilot_consumer_purpose_v1",purpose="OWN_EVIDENCE_TYPED_QUALIFICATION_ONLY",
    mode="convert",nonce=strrep("1",32),expires_utc="2100-01-01T00:00:00Z",source_root="/generated/source",
    source_commit=strrep("1",40),source_tree=strrep("2",40),source_files=list(),evidence_pins=pins,
    output_root="/generated/source/local_trackers/output",expected_provenance_sha256=NULL,
    limits=list(cpu_seconds=120,wall_term_seconds=119,wall_kill_after_seconds=1,address_space_bytes=2*1024^3,output_bytes=16*1024^2,logical_cpu=30),
    allow_own_pilot_read=TRUE,allow_compact_packet_read=FALSE,allow_model_read=FALSE,allow_future_truth=FALSE,
    allow_refit=FALSE,allow_scoring=FALSE,allow_ledger_mutation=FALSE,allow_production=FALSE,allow_article=FALSE)
  ok(mqp2_scope(consumer))
  scope_pin<-json(consumer,file.path(root,"generated_consumer.json"))
  ok(mqp2_scope(jsonlite::read_json(scope_pin$path,simplifyVector=FALSE)))
  rb<-consumer;rb$mode<-"readback";rb$allow_own_pilot_read<-FALSE;rb$allow_compact_packet_read<-TRUE;rb$expected_provenance_sha256<-sha
  ok(mqp2_scope(rb))
  for(k in c("allow_model_read","allow_future_truth","allow_refit","allow_scoring","allow_ledger_mutation","allow_production","allow_article")) {
    bad<-consumer;bad[[k]]<-TRUE;reject(mqp2_scope(bad))
  }
  bad<-consumer;bad$limits$logical_cpu<-31;reject(mqp2_scope(bad))
  bad<-consumer;bad$allow_compact_packet_read<-TRUE;reject(mqp2_scope(bad))
  bad<-consumer;bad$evidence_pins$stream$path<-"/generated/model.rds";reject(mqp2_scope(bad))
  # Independent standalone R process decodes only the new generated block.
  expression<-sprintf("source(%s);x<-mqp2_readback(%s,%s);stopifnot(x$independent_bound_recomputation,!x$production_authorized);cat('INDEPENDENT_GENERATED_TYPED_READBACK_PASS\\n')",
    dQuote(normalizePath("scripts/mq_qualified_pilot_typed.R"),FALSE),dQuote(packet,FALSE),dQuote(sha,FALSE))
  result<-system2(file.path(R.home("bin"),"Rscript"),c("--vanilla","-e",shQuote(expression)),stdout=TRUE,stderr=TRUE)
  ok(is.null(attr(result,"status"))&&any(grepl("INDEPENDENT_GENERATED_TYPED_READBACK_PASS",result,fixed=TRUE)))
  for(k in c("numerical_status","source_commit","freeze_sha256","production_authorized")) {
    bad<-meta;bad$qualification[[k]]<-if(k=="production_authorized")TRUE else "wrong"
    reject(mqp2_make(bad,pins,manifest,candidates,split,state,ci))
  }
  for(k in c("status","source_tree","purpose_sha256","independently_linked_successful_stop_post")) {
    bad<-meta;bad$terminal[[k]]<-if(k=="independently_linked_successful_stop_post")FALSE else "wrong"
    reject(mqp2_make(bad,pins,manifest,candidates,split,state,ci))
  }
  for(k in c("schema_version","actor","phase")) {
    bad<-meta;bad$stop_post[[k]]<-"wrong";reject(mqp2_make(bad,pins,manifest,candidates,split,state,ci))
  }
  bad<-meta;bad$terminal$unit_state$MainPID<-"123";reject(mqp2_make(bad,pins,manifest,candidates,split,state,ci))
  bad<-meta;bad$stop_post$unit_state$ExecMainCode<-"0";reject(mqp2_make(bad,pins,manifest,candidates,split,state,ci))
  bad<-meta;bad$terminal$payload_native_time$exit_code<-1;reject(mqp2_make(bad,pins,manifest,candidates,split,state,ci))
  bad<-pins;bad$finalizer_time$path<-"/different/admin/finalizer.time.txt"
  reject(mqp2_make(meta,bad,manifest,candidates,split,state,ci))
  bad<-meta;bad$freeze$validation_paths_generated<-1;reject(mqp2_make(bad,pins,manifest,candidates,split,state,ci))
  bad<-candidates;bad$quantile[1]<-0;reject(mqp2_make(meta,pins,manifest,bad,split,state,ci))
  bad<-state;bad$mean[1]<-1;reject(mqp2_make(meta,pins,manifest,candidates,split,bad,ci))
  bad<-state;bad$blocks$count[1]<-129L;bad<-mq_scc_seal(bad)
  reject(mqp2_make(meta,pins,manifest,candidates,split,bad,ci))
  bad<-state;bad$mean[]<-.5;bad<-mq_scc_seal(bad)
  reject(mqp2_make(meta,pins,manifest,candidates,split,bad,ci))
  bad<-state;bad$builder<-function()stop("must never execute")
  reject(mqp2_make(meta,pins,manifest,candidates,split,bad,ci))
  bad<-split;bad$split_stream_absolute_difference[]<-.1;reject(mqp2_make(meta,pins,manifest,candidates,bad,state,ci))
  reject(mqp2_readback(packet,strrep("0",64)))
  forged<-file.path(root,"forged");dir.create(forged);stopifnot(all(file.copy(list.files(packet,full.names=TRUE),forged)))
  block<-readRDS(file.path(forged,"typed_block.rds"));block$storage_interpretation<-"changed"
  block$integrity_sha256<-NULL;block$integrity_sha256<-iqr2_hash(block)
  saveRDS(block,file.path(forged,"typed_block.rds"),compress=FALSE,version=3)
  fm<-read.csv(file.path(forged,"artifact_manifest.csv"));at<-which(fm$relative_path=="typed_block.rds")
  fm$size_bytes[at]<-file.info(file.path(forged,"typed_block.rds"))$size;fm$sha256[at]<-mqp2_sha(file.path(forged,"typed_block.rds"))
  write.csv(fm,file.path(forged,"artifact_manifest.csv"),row.names=FALSE)
  reject(mqp2_readback(forged,sha))
  reject(mqp2_finalizer_time(sub("0:00.02","0:30.00",time,fixed=TRUE)))
  reject(mqp2_main(character()));reject(mqp2_main(c("--execute")))
  ok(is.null(mqp2_main("--help")))
  cat(sprintf("MQ_QUALIFIED_PILOT_TYPED_GENERATED_PASS checks=%d real_pilot_reads=0\n",n))
})
