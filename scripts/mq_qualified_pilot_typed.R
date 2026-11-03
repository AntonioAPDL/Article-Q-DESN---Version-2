# A closed one-unit qualification consumer, not a generated or production route.
source("scripts/mq_streaming_cdf_certificate.R")
source("scripts/integrated_quantile_receipts_v2.R")
source("scripts/qualify_integrated_quantile_forecast.R")
mqp2_require <- function(x, why) if (!isTRUE(x)) stop(paste0("MQ_PILOT_TYPED: ", why), call. = FALSE)
mqp2_sha <- function(path) unname(tools::sha256sum(path))
mqp2_norm <- function(x) jsonlite::fromJSON(jsonlite::toJSON(x, auto_unbox = TRUE,
  dataframe = "rows", null = "null", digits = 17), simplifyVector = FALSE)
mqp2_pin <- function(x, cap = 8*1024^2) {
  mqp2_require(is.list(x) && identical(sort(names(x)), sort(c("path","size_bytes","sha256"))) &&
    is.character(x$path) && length(x$path) == 1L && !is.na(x$path) &&
    is.numeric(x$size_bytes) && length(x$size_bytes) == 1L && is.finite(x$size_bytes) &&
    x$size_bytes > 0 && x$size_bytes <= cap && x$size_bytes == floor(x$size_bytes) &&
    is.character(x$sha256) && length(x$sha256) == 1L && grepl("^[a-f0-9]{64}$", x$sha256), "bounded exact file pin required")
  q2_regular(x$path)
  mqp2_require(file.exists(x$path) && !dir.exists(x$path) && identical(normalizePath(x$path), x$path) &&
    file.info(x$path)$size == x$size_bytes && identical(mqp2_sha(x$path), x$sha256), "own-evidence bytes changed")
  x$path
}
mqp2_no_opaque <- function(x, depth = 0L) {
  mqp2_require(depth <= 30L && !is.function(x) && !is.environment(x) && !isS4(x) && !is.language(x) &&
    !typeof(x) %in% c("externalptr","weakref","promise") &&
    all(names(attributes(x)) %in% c("names","class","row.names","dim","dimnames")), "opaque/callback evidence forbidden")
  if (is.list(x)) for (z in x) mqp2_no_opaque(z, depth+1L)
  for (z in attributes(x)) mqp2_no_opaque(z, depth+1L)
  invisible(TRUE)
}
mqp2_roles <- function(pins) {
  names <- c("pilot_purpose","qualification","manifest","freeze","stop_post","terminal",
    "finalizer_time","candidates","split","stream")
  mqp2_require(is.list(pins) && identical(sort(names(pins)), sort(names)) &&
    !anyDuplicated(vapply(pins, `[[`, "", "path")), "exact distinct own-evidence roles required")
  expected <- c(pilot_purpose="purpose.json", qualification="qualification.json", manifest="artifact_manifest.csv",
    freeze="CANDIDATES_FROZEN.json", stop_post="STOP_POST_RECEIPT.json", terminal="FINAL_SUPERVISOR_READBACK.json",
    finalizer_time="finalizer.time.txt", candidates="frozen_training_candidates.rds", split="training_split_diagnostic.rds")
  for (k in names(expected)) mqp2_require(identical(basename(pins[[k]]$path), unname(expected[k])), "incorrect own-evidence role basename")
  mqp2_require(grepl("^validation_stream_look_(065536|131072|262144)\\.rds$", basename(pins$stream$path)),
    "one final declared-look stream role required")
  sum(vapply(pins, function(x) {
    mqp2_require(is.numeric(x$size_bytes) && length(x$size_bytes) == 1L &&
      is.finite(x$size_bytes) && x$size_bytes > 0 && x$size_bytes <= 8*1024^2, "bounded role sizes required")
    x$size_bytes
  }, numeric(1L)))
}
mqp2_read_cost <- function(pins) {
  total<-mqp2_roles(pins)
  rds<-sum(vapply(pins[c("candidates","split","stream")],`[[`,numeric(1L),"size_bytes"))
  mqp2_require(total<=32*1024^2&&rds<=24*1024^2,"finite selected reader inventory required")
  list(selected_distinct_evidence_bytes=total,selected_input_hash_bytes_before_and_after=2*total,
    selected_serialized_RDS_bytes=rds,RDS_deserializations=3L,selected_metadata_parse_bytes=total-rds,
    interpretation="bounded_code_path_counts_not_measured_OS_IO; software_source_and_new_packet_IO_separate")
}
mqp2_finalizer_time <- function(text) {
  get <- function(key) {
    line<-grep(paste0("^[[:space:]]*",key,":"),text,value=TRUE)
    mqp2_require(length(line)==1L,"missing/duplicate finalizer accounting field")
    trimws(sub("^[^:]+:","",line))
  }
  scalar<-function(key) {v<-suppressWarnings(as.numeric(get(key)));mqp2_require(length(v)==1L&&is.finite(v)&&v>=0,"invalid finalizer accounting");v}
  cpu<-scalar("User time \\(seconds\\)")+scalar("System time \\(seconds\\)")
  wall_line<-grep("Elapsed \\(wall clock\\) time",text,value=TRUE)
  mqp2_require(length(wall_line)==1L,"missing finalizer wall accounting")
  parts<-strsplit(trimws(sub("^.*time \\(h:mm:ss or m:ss\\):","",wall_line)),":",fixed=TRUE)[[1L]]
  value<-suppressWarnings(as.numeric(parts));wall<-sum(rev(value)*60^(seq_along(value)-1L))
  mqp2_require(length(value)%in%c(2L,3L)&&all(is.finite(value))&&all(value>=0)&&wall<=20&&cpu<=20&&
    scalar("Exit status")==0&&scalar("Maximum resident set size \\(kbytes\\)")<=512*1024,
    "finalizer did not close within its administrative budget")
  invisible(TRUE)
}
mqp2_links <- function(meta, pins, manifest) {
  q <- mqp2_require; p <- meta$pilot_purpose; r <- meta$qualification; f <- meta$freeze
  t <- meta$terminal; h <- meta$stop_post
  q(identical(p$schema_version,"mq_native_source_replay_v1") && identical(p$purpose,"NATIVE_COMPOSED_ONE_ORIGINAL_DRAW_ORIGIN") &&
    identical(p$allow_qualification,TRUE), "a genuine new-source replay purpose is required")
  for (k in c("allow_refit","allow_scoring","allow_production","allow_article","allow_future_truth","allow_raw_fixture_deserialization","C_ABI_qualified"))
    q(identical(p[[k]],FALSE), "pilot purpose has expanded permissions")
  q2_geometry(p$original_unit)
  q(identical(r$schema_version,"mq_native_source_replay_receipt_v1") &&
    identical(r$status,"GENUINE_NATIVE_SOURCE_REPLAY_COMPLETE_NOT_PRODUCTION") &&
    identical(r$numerical_status,"PASS_NATIVE_ONE_ORIGINAL_UNIT_SOURCE_REGRESSION_ONLY") &&
    identical(r$source_commit,p$source_commit) && identical(r$source_tree,p$source_tree) &&
    identical(r$purpose_contract_sha256,pins$pilot_purpose$sha256) &&
    identical(mqp2_norm(r$original_unit),mqp2_norm(p$original_unit)) &&
    r$training_paths == 65536 && identical(r$training_split_gate_pass,TRUE) && r$validation_paths %in% c(65536,131072,262144) &&
    r$validation_paths_generated_before_freeze == 0 && identical(r$freeze_sha256,pins$freeze$sha256),
    "pilot source, unit, numerical status or freeze differs")
  for (k in c("full_campaign_enrollment","production_consumer_qualified","C_ABI_qualified","observational_future_truth_used",
    "production_authorized","article_promotion_authorized")) q(identical(r[[k]],FALSE), "pilot grants forbidden campaign authority")
  for (k in c("parameter_refits","score_evaluations","raw_fixture_deserializations","raw_design_deserializations"))
    q(identical(as.numeric(r[[k]]),0), "pilot is not the own-evidence-only no-fit source replay")
  q(identical(t$schema_version,"mq_native_external_terminal_receipt_v1") && identical(t$actor,"mq-native-replay") &&
    identical(t$phase,"final") && identical(t$status,"EXECUTION_COMPLETE_NOT_PRODUCTION") && length(t$failures)==0L &&
    identical(t$source_commit,p$source_commit) && identical(t$source_tree,p$source_tree) &&
    identical(t$purpose_sha256,pins$pilot_purpose$sha256) && identical(t$numerical_status,r$numerical_status) &&
    identical(t$independently_linked_successful_stop_post,TRUE) &&
    identical(t$stop_post_receipt_sha256,pins$stop_post$sha256) &&
    identical(h$schema_version,"mq_native_external_terminal_receipt_v1") && identical(h$actor,"mq-native-replay") &&
    identical(h$phase,"stop-post") && identical(h$status,"EXECUTION_PENDING_FINAL_INACTIVE_READBACK") && length(h$failures)==0L &&
    identical(h$successful_actual_stop_post_proof,TRUE) && identical(t$unit,h$unit) && identical(t$unit,p$administrative_unit_name) &&
    identical(h$source_commit,t$source_commit) && identical(h$source_tree,t$source_tree) &&
    identical(t$grant_sha256,h$grant_sha256) && identical(t$purpose_sha256,h$purpose_sha256) &&
    identical(mqp2_norm(t$payload_native_time),mqp2_norm(h$payload_native_time)) &&
    identical(mqp2_norm(t$outputs),mqp2_norm(h$outputs)) && identical(t$production_authorized,FALSE) &&
    identical(t$article_promotion_authorized,FALSE), "independently closed pilot terminal proof required")
  admin<-dirname(pins$pilot_purpose$path)
  q(all(vapply(pins[c("stop_post","terminal","finalizer_time")],function(z)identical(dirname(z$path),admin),logical(1L))),
    "terminal accounting must belong to the same original administrative namespace")
  hs<-h$unit_state;ts<-t$unit_state
  for(z in list(hs,ts))q(identical(z$Id,p$administrative_unit_name)&&identical(z$MainPID,"0")&&
    identical(z$Result,"success")&&identical(z$ExecMainStatus,"0"),"unsuccessful/live supervisor state")
  q(identical(hs$ActiveState,"deactivating")&&identical(hs$SubState,"stop-post")&&identical(hs$ExecMainCode,"1")&&
    is.character(hs$ControlGroup)&&endsWith(hs$ControlGroup,paste0("/",p$administrative_unit_name))&&
    identical(ts$ActiveState,"inactive")&&identical(ts$SubState,"dead")&&
    ((identical(ts$ExecMainCode,"1")&&identical(ts$ControlGroup,hs$ControlGroup))||
     (identical(ts$ExecMainCode,"0")&&identical(ts$ControlGroup,""))),"actual successful stop-post and linked inactive state required")
  metrics<-t$payload_native_time
  q(is.list(metrics)&&all(vapply(metrics[c("exit_code","user_cpu_seconds","system_cpu_seconds","wall_seconds","peak_rss_kib")],
    function(z)is.numeric(z)&&length(z)==1L&&is.finite(z)&&z>=0,logical(1L)))&&
    metrics$exit_code==0&&metrics$user_cpu_seconds+metrics$system_cpu_seconds<=1800&&
    metrics$wall_seconds<=1800&&metrics$peak_rss_kib*1024<=16*1024^3,"native payload accounting exceeds original scope")
  mqp2_finalizer_time(meta$finalizer_time)
  q(is.data.frame(manifest) && identical(names(manifest),c("relative_path","size_bytes","sha256")) &&
    !anyDuplicated(manifest$relative_path), "pilot artifact manifest required")
  outputs <- t$outputs; paths <- vapply(outputs, `[[`, "", "relative_path")
  q(!anyDuplicated(paths) && setequal(paths,c(manifest$relative_path,"artifact_manifest.csv")), "terminal output membership differs")
  for (k in c("qualification","manifest","freeze","candidates","split","stream")) {
    pin <- pins[[k]]; j <- match(basename(pin$path),paths)
    q(!is.na(j) && identical(outputs[[j]]$sha256,pin$sha256) && outputs[[j]]$size_bytes==pin$size_bytes &&
      identical(dirname(pin$path),p$output_root), "selected evidence is not the exact terminal-bound output")
    if (k!="manifest") {i<-match(basename(pin$path),manifest$relative_path)
      q(!is.na(i) && manifest$sha256[i]==pin$sha256 && manifest$size_bytes[i]==pin$size_bytes, "manifest evidence binding differs")}
  }
  q(identical(f$schema_version,"mq_native_training_freeze_v1") && identical(f$source_commit,p$source_commit) &&
    identical(f$purpose_contract_sha256,pins$pilot_purpose$sha256) &&
    identical(f$candidate_phase,"BEFORE_ANY_VALIDATION_PATH") && identical(f$split_pass,TRUE) &&
    identical(as.numeric(unlist(f$training_path_range)),c(1,65536)) && f$validation_paths_generated==0 &&
    length(f$artifacts)==3L, "original pre-validation training commitment required")
  fp <- vapply(f$artifacts, `[[`, "", "path")
  q(setequal(fp,file.path(p$output_root,c("frozen_training_candidates.rds","training_split_diagnostic.rds","training_parity.rds"))),
    "freeze artifact roles differ")
  for (k in c("candidates","split")) q(identical(mqp2_norm(f$artifacts[[match(pins[[k]]$path,fp)]]),mqp2_norm(pins[[k]])), "freeze role pin changed")
  invisible(TRUE)
}
mqp2_make <- function(meta, pins, manifest, candidates, split, state, converter_identity) {
  mqp2_links(meta,pins,manifest)
  for (x in list(candidates,split,state)) mqp2_no_opaque(x)
  mq_scc_check_state(state)
  q <- mqp2_require; p <- meta$pilot_purpose; r <- meta$qualification; u <- p$original_unit
  q(identical(names(candidates),c("horizon","probability","quantile")) && nrow(candidates)==210L &&
    identical(as.numeric(candidates$horizon),as.numeric(rep(1:30,each=7))) &&
    identical(as.numeric(candidates$probability),rep(c(.05,.1,.25,.5,.75,.9,.95),30)) &&
    identical(state$candidates,candidates) && identical(state$contract$training_split_diagnostic,split) &&
    identical(state$contract$rng_namespace,u$rng_namespace) &&
    identical(state$contract$draw_id,paste0(u$model_cell_id,"/chain_01/draw_000001")) &&
    identical(state$contract$origin_id,"1") && state$count==r$validation_paths &&
    identical(basename(pins$stream$path),sprintf("validation_stream_look_%06d.rds",state$count)) &&
    identical(mqp2_norm(state$last_evaluation),mqp2_norm(r$final_certificate)), "candidate/stream/source/receipt association differs")
  previous <- state$genesis_chain_sha256; next_id <- 65537L
  q(nrow(state$blocks)==state$count/128 && all(state$blocks$count==128), "original128-ID validation blocks required")
  for (i in seq_len(nrow(state$blocks))) {
    rec <- as.list(state$blocks[i,,drop=FALSE]); seal<-rec$chain_sha256;rec$chain_sha256<-NULL
    q(rec$block==i && rec$first_path_id==next_id && rec$last_path_id==next_id+127L &&
      identical(rec$previous_chain_sha256,previous) && identical(seal,mq_scc_hash(rec)), "validation replay-chain changed")
    previous<-seal;next_id<-rec$last_path_id+1L
  }
  q(identical(previous,state$last_chain_sha256), "validation chain root changed")
  identity <- list(source_commit=r$source_commit,source_tree=r$source_tree,
    source_manifest_sha256=p$source_manifest$sha256,posterior_target_sha256=u$posterior_target_sha256,
    input_manifest_sha256=p$prepared_manifest$sha256,task_manifest_sha256=p$original_unit_contract$sha256,
    task_id=paste0("qualified-pilot/",u$model_cell_id,"/chain_01/draw_000001/origin_1"),rng_namespace=u$rng_namespace,
    outer_conditioning="parameters_and_observed_origin_reservoir_state",
    identity_domain="qualification_only_single_unit_not_campaign_manifest_v1",
    input_manifest_role="truth_free_original_prefix_manifest",task_manifest_role="original_one_unit_contract")
  receipt <- iqr2_from_stream_state(state,identity) # Independently recomputes every bound.
  quantiles <- transform(candidates,model_id=u$model_cell_id,draw_id=state$contract$draw_id,origin_id="1",
    functional="parameter_conditional_integrated_quantile",outer_conditioning=identity$outer_conditioning,rng_namespace=u$rng_namespace)
  shard <- list(schema_version="integrated_quantile_forecast_shard_v2",model_id=u$model_cell_id,
    draw_id=state$contract$draw_id,origin_id="1",forecast_functional="parameter_conditional_integrated_quantile",
    outer_conditioning=identity$outer_conditioning,identity=identity,quantiles=quantiles,numerical_receipt=receipt)
  iqr2_validate_shard(shard);block<-iqr2_pack(list(shard))
  provenance <- list(schema_version="mq_qualified_pilot_provenance_v1",converter_identity=converter_identity,
    pilot_source_commit=r$source_commit,pilot_source_tree=r$source_tree,pilot_purpose=pins$pilot_purpose,
    original_unit=u,evidence_pins=pins,training_freeze_sha256=pins$freeze$sha256,
    terminal_sha256=pins$terminal$sha256,validation_chain_sha256=state$last_chain_sha256,
    validation_count=state$count,member_keys=unname(block$member_keys),read_accounting=mqp2_read_cost(pins),
    novel_statistical_replication=FALSE,canonical_ledger_mutations=0L,score_evaluations=0L,
    production_authorized=FALSE,article_authorized=FALSE,source_identity_authenticated_here=FALSE)
  provenance$integrity_sha256<-iqr2_hash(mqp2_norm(provenance))
  list(block=block,provenance=provenance)
}
mqp2_write <- function(value, output, prepared_empty = FALSE) {
  mqp2_require(is.logical(prepared_empty)&&length(prepared_empty)==1L&&!is.na(prepared_empty),"explicit output state required")
  mqp2_require(dir.exists(dirname(output)) && if(prepared_empty)
    dir.exists(output)&&length(list.files(output,all.files=TRUE,no..=TRUE))==0L else !file.exists(output),
    "fresh typed qualification output required")
  if(!prepared_empty)dir.create(output)
  saveRDS(value$block,file.path(output,"typed_block.rds"),compress=FALSE,version=3L)
  provenance<-value$provenance;provenance$integrity_sha256<-NULL
  provenance$typed_block_sha256<-mqp2_sha(file.path(output,"typed_block.rds"))
  provenance$integrity_sha256<-iqr2_hash(mqp2_norm(provenance))
  jsonlite::write_json(provenance,file.path(output,"PROVENANCE.json"),auto_unbox=TRUE,pretty=TRUE,digits=17)
  paths<-file.path(output,c("typed_block.rds","PROVENANCE.json"))
  write.csv(data.frame(relative_path=basename(paths),size_bytes=as.numeric(file.info(paths)$size),sha256=unname(tools::sha256sum(paths))),
    file.path(output,"artifact_manifest.csv"),row.names=FALSE)
  invisible(mqp2_sha(file.path(output,"PROVENANCE.json")))
}
mqp2_readback <- function(output, expected_provenance_sha256) {
  # Only the just-created, compact typed block is decoded; no fit/old pilot read.
  mqp2_require(identical(output,normalizePath(output,mustWork=TRUE)), "canonical compact packet required")
  q2_regular(output)
  all_paths<-file.path(output,c("artifact_manifest.csv","PROVENANCE.json","typed_block.rds"))
  mqp2_require(all(file.exists(all_paths))&&!any(dir.exists(all_paths))&&!any(nzchar(Sys.readlink(all_paths)))&&
    file.info(all_paths[1L])$size<=65536&&all(file.info(all_paths[-1L])$size<=8*1024^2),"bounded compact roles required before any read")
  m<-read.csv(file.path(output,"artifact_manifest.csv"),stringsAsFactors=FALSE)
  mqp2_require(identical(names(m),c("relative_path","size_bytes","sha256")) && nrow(m)==2L &&
    setequal(m$relative_path,c("typed_block.rds","PROVENANCE.json")) && !anyDuplicated(m$relative_path) &&
    setequal(list.files(output,all.files=TRUE,no..=TRUE),c(m$relative_path,"artifact_manifest.csv")), "compact packet membership differs")
  for (i in 1:2) mqp2_pin(list(path=file.path(output,m$relative_path[i]),size_bytes=m$size_bytes[i],sha256=m$sha256[i]))
  pp<-file.path(output,"PROVENANCE.json")
  mqp2_require(identical(mqp2_sha(pp),expected_provenance_sha256), "prospectively pinned provenance changed")
  p<-jsonlite::read_json(pp,simplifyVector=FALSE)
  plain<-p;plain$integrity_sha256<-NULL
  mqp2_require(identical(p$integrity_sha256,iqr2_hash(mqp2_norm(plain))), "provenance content seal changed")
  mqp2_require(identical(p$typed_block_sha256,mqp2_sha(file.path(output,"typed_block.rds"))),
    "typed block is not the prospectively pinned provenance's block")
  for (k in c("novel_statistical_replication","production_authorized","article_authorized","source_identity_authenticated_here"))
    mqp2_require(identical(p[[k]],FALSE), "qualification packet grants forbidden authority")
  block<-readRDS(file.path(output,"typed_block.rds"));mqp2_no_opaque(block)
  mqp2_require(length(block$members)==1L, "one complete original member required")
  shard<-iqr2_unpack(block,1L)
  mqp2_require(identical(unname(block$member_keys),as.character(unlist(p$member_keys))) &&
    identical(shard$identity$source_commit,p$pilot_source_commit) && identical(shard$identity$source_tree,p$pilot_source_tree) &&
    identical(shard$numerical_receipt$validation_chain_sha256,p$validation_chain_sha256) &&
    shard$numerical_receipt$validation_count==p$validation_count, "typed block/provenance identity differs")
  invisible(list(status="QUALIFIED_PILOT_TYPED_READBACK_NOT_PRODUCTION",member_keys=unname(block$member_keys),
    endpoints=420L,independent_bound_recomputation=TRUE,production_authorized=FALSE,canonical_ledger_mutations=0L))
}
