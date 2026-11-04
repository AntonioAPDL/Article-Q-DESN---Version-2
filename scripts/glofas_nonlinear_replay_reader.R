#!/usr/bin/env Rscript
# Separate two-object, truth-free feature replay. Closed earlier read contracts
# are not converted or reused. No fitting or numerical target update is allowed.
source("scripts/glofas_fixed_target_forensic_reader.R")
source("scripts/diagnostics/glofas_nonlinear_replay.R")

gnrr_sources <- function() unique(c(gfr_sources(),"scripts/glofas_nonlinear_replay_reader.R",
  "scripts/diagnostics/glofas_nonlinear_replay.R",gnr_production_sources()))
gnrr_cost <- function(s) {
  bytes<-sum(vapply(s[c("design","median_model")],function(p)p$size_bytes,numeric(1L)))
  gfr_require(bytes<=s$read_budget$max_deserialization_bytes&&2*bytes<=s$read_budget$max_payload_hash_bytes&&
    s$read_budget$max_RDS_deserializations==2L,"two-object read and before/after hash allowance exceeded")
  list(original_RDS_deserializations=2L,deserialization_bytes=bytes,payload_hash_bytes=2*bytes)
}
gnrr_scope <- function(s) {
  q<-gfr_require;gst_unique_objects(s)
  fields<-c("schema_version","purpose","nonce","expires_utc","source_root","source_commit","source_tree",
    "source_files","expected_identity","collection","input_manifest","design","median_model",
    "read_budget","limits","output_root","metadata_scratch_root","metadata_serialization","replay",
    "allow_original_reads","allow_fresh_source_feature_replay","allow_metadata_serialization",
    "allow_saved_callbacks","allow_applied_updates","allow_truth_read","allow_refit","allow_retuning",
    "allow_forecasting","allow_scoring","allow_publication","allow_derived_context_serialization")
  forbidden<-c("allow_saved_callbacks","allow_applied_updates","allow_truth_read","allow_refit","allow_retuning",
    "allow_forecasting","allow_scoring","allow_publication","allow_derived_context_serialization")
  q(is.list(s)&&length(s)==length(fields)&&setequal(names(s),fields)&&
    identical(s$schema_version,"glofas_nonlinear_replay_contract_v1")&&
    identical(s$purpose,"AUTHENTIC_MEDIAN_FEATURE_REPLAY_DIRECTIONAL_ONLY_NO_INFERENCE")&&
    isTRUE(s$allow_original_reads)&&isTRUE(s$allow_fresh_source_feature_replay)&&isTRUE(s$allow_metadata_serialization)&&
    all(vapply(s[forbidden],identical,logical(1L),FALSE)),"exact separate nonlinear replay purpose required")
  q(is.character(s$nonce)&&length(s$nonce)==1L&&grepl("^[a-f0-9]{32,64}$",s$nonce)&&
    all(vapply(s[c("source_commit","source_tree")],function(x)is.character(x)&&length(x)==1L&&
      grepl("^[a-f0-9]{40}$",x),logical(1L)))&&gst_same(s$expected_identity,gsc_identity()),
    "full diagnostic/producer identities required")
  for(pin in s[c("design","median_model")])gfr_pin_shape(pin,8*1024^3)
  for(pin in s[c("collection","input_manifest")])gfr_pin_shape(pin,4*1024^2)
  q(identical(s$design$sha256,"193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3")&&
    identical(s$median_model$sha256,"f56b4b7792ab04bd431838c8ef94ff88dd859d16cd70cb68116eecf6fade5881")&&
    identical(s$input_manifest$sha256,gsc_identity()$input_manifest_sha256)&&
    identical(basename(s$design$path),"shared_truth_free_design.rds")&&
    identical(basename(s$median_model$path),"fit.rds")&&
    identical(basename(s$collection$path),"accepted_producers.json"),"exact frozen two-object/metadata roles required")
  b<-s$limits;keys<-c("cpu_seconds","wall_seconds","memory_bytes","output_bytes","logical_cpu")
  q(is.list(b)&&setequal(names(b),keys)&&all(vapply(b,gfr_scalar_integer,logical(1L)))&&
    b$cpu_seconds>=60&&b$cpu_seconds<=1800&&b$wall_seconds==b$cpu_seconds&&
    b$memory_bytes>0&&b$memory_bytes<=32*1024^3&&b$output_bytes>0&&b$output_bytes<=64*1024^2&&
    b$logical_cpu%in%0:63&&!b$logical_cpu%in%c(16,18,24,25,31,48,50,56,57,63),
    "finite one-core native replay allocation required")
  r<-s$read_budget;keys<-c("max_payload_hash_bytes","max_deserialization_bytes","max_RDS_deserializations",
    "max_metadata_bytes","max_replay_output_bytes")
  q(is.list(r)&&setequal(names(r),keys)&&all(vapply(r,gfr_scalar_integer,logical(1L)))&&all(unlist(r)>0)&&
    r$max_RDS_deserializations==2L&&r$max_deserialization_bytes<=24*1024^3&&
    r$max_payload_hash_bytes<=48*1024^3&&r$max_metadata_bytes<=32*1024^2&&
    r$max_replay_output_bytes<=10*1024^2,"finite original read/output allowance required")
  m<-s$metadata_serialization;keys<-c("max_files","max_file_bytes","max_total_bytes")
  q(is.list(m)&&setequal(names(m),keys)&&all(vapply(m,gfr_scalar_integer,logical(1L)))&&
    all(unlist(m)>0)&&m$max_files<=64L&&m$max_file_bytes<=4*1024^2&&m$max_total_bytes<=64*1024^2&&
    m$max_total_bytes+r$max_replay_output_bytes+65536<=b$output_bytes,
    "bounded generated contract serialization required")
  c<-s$replay;keys<-c("max_evaluations","factory_evaluations","value_evaluations","direction_steps",
    "perturbation","parity_tolerance","fd_tolerance","pilot_safety_factor","minimum_tail_seconds")
  q(is.list(c)&&setequal(names(c),keys)&&c$max_evaluations==20L&&c$factory_evaluations==12L&&
    c$value_evaluations==8L&&identical(as.numeric(unlist(c$direction_steps)),c(1e-4,3e-5,1e-5))&&
    c$perturbation==.01&&c$parity_tolerance==1e-10&&c$fd_tolerance==1e-6&&
    c$pilot_safety_factor>=2&&c$pilot_safety_factor<=4&&c$minimum_tail_seconds>=60&&
    c$minimum_tail_seconds<=120,"fixed 20-call replay, not a full-coordinate test, required")
  gnrr_cost(s);invisible(TRUE)
}
gnrr_source <- function(s) {
  q<-gfr_require;root<-normalizePath(getwd(),mustWork=TRUE)
  git<-function(a){z<-system2("/usr/bin/git",c("--no-replace-objects","-c","core.fsmonitor=false",a),stdout=TRUE)
    q(is.null(attr(z,"status")),"nonlinear replay source Git check failed");unname(z)}
  q(identical(root,s$source_root)&&identical(git(c("rev-parse","--show-toplevel")),root)&&
    identical(git(c("rev-parse","HEAD")),s$source_commit)&&identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=all"))),"clean exact committed replay source required")
  paths<-vapply(s$source_files,function(p){gfr_pin_shape(p,1024^2);p$path},character(1L))
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,gnrr_sources())),
    "exact replay/transitive production source closure required")
  for(pin in s$source_files)gsc_pin(pin,1024^2)
  for(rel in gnrr_sources())q(identical(git(c("hash-object","--no-filters","--",shQuote(rel))),
    git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel))))),"source differs from committed blob")
  for(rel in gnr_production_sources())q(identical(git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel)))),
    git(c("rev-parse",shQuote(paste0(gsc_identity()$source_commit,":",rel))))),
    "production evaluator source differs from the authenticated frozen producer")
  invisible(root)
}
gnrr_bind <- function(s,collection,manifest) {
  q<-gfr_require;gsc_validate_collection(collection,gsc_identity())
  q(is.data.frame(manifest)&&all(c("relative_path","role","size_bytes","sha256")%in%names(manifest))&&
    !anyDuplicated(manifest$relative_path),"frozen manifest schema required")
  at<-which(manifest$role=="truth_free_shared_design")
  q(length(at)==1L&&manifest$size_bytes[at]==s$design$size_bytes&&
    identical(manifest$sha256[at],s$design$sha256)&&
    identical(normalizePath(file.path(dirname(dirname(s$input_manifest$path)),manifest$relative_path[at]),
      mustWork=FALSE),s$design$path),"design not bound to truth-free manifest role")
  producer<-Filter(function(p)identical(p$task_id,"gft-al-p050"),collection$producers)
  q(length(producer)==1L,"one accepted median task required")
  fit<-Filter(function(p)identical(p$relative_path,"fit.rds"),producer[[1L]]$artifacts)
  q(length(fit)==1L&&gst_same(fit[[1L]][c("path","size_bytes","sha256")],s$median_model),
    "median model is not its authenticated accepted artifact")
  producer[[1L]]
}
gnrr_main <- function(args=commandArgs(TRUE)) {
  q<-gfr_require
  if(identical(args,"--help")){cat("Usage: Rscript --vanilla scripts/glofas_nonlinear_replay_reader.R --contract FILE --sha256 SHA --execute\n");return(invisible(NULL))}
  q(length(args)==5L&&identical(args[c(1L,3L,5L)],c("--contract","--sha256","--execute")),
    "explicit new external replay admission required")
  purpose<-normalizePath(args[2L],mustWork=TRUE)
  q(grepl("\\.json$",purpose)&&file.info(purpose)$size<=1024^2&&gsc_hash_string(args[4L])&&
    identical(unname(tools::sha256sum(purpose)),args[4L]),"bounded external replay digest required")
  s<-jsonlite::read_json(purpose,simplifyVector=FALSE);gnrr_scope(s)
  root<-normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(purpose,paste0(root,"/")),"replay purpose must be external")
  gst_runtime(s);gnrr_source(s)
  expiry<-as.POSIXct(s$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry)&&expiry>Sys.time()+s$limits$wall_seconds,"purpose expiry must cover whole replay")
  out<-s$output_root;link<-Sys.readlink(out)
  q(is.character(out)&&length(out)==1L&&startsWith(out,paste0(root,"/local_trackers/"))&&
    !file.exists(out)&&(is.na(link)||!nzchar(link))&&dir.exists(dirname(out))&&
    identical(normalizePath(dirname(out)),dirname(out))&&!grepl("(^|/)\\.\\.(/|$)",out)&&
    system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(out)))==0L,"fresh ignored output required")
  scratch<-s$metadata_scratch_root;link<-Sys.readlink(scratch)
  q(is.character(scratch)&&length(scratch)==1L&&startsWith(scratch,"/")&&dir.exists(scratch)&&
    (is.na(link)||!nzchar(link))&&identical(normalizePath(scratch),scratch)&&
    identical(list.files(scratch,all.files=TRUE,no..=TRUE),basename(tempdir()))&&
    !length(list.files(tempdir(),all.files=TRUE,no..=TRUE))&&!startsWith(out,paste0(scratch,"/"))&&
    identical(Sys.getenv("TMPDIR"),scratch)&&startsWith(normalizePath(tempdir()),paste0(scratch,"/")),
    "native TMPDIR must be the admitted owned empty scratch (apart from R session tempdir)")
  # R creates its session tempdir before this script. It is the only admitted
  # initial child; no original payload is accessed through that directory.
  meta<-c(s$source_files,s[c("collection","input_manifest")])
  metadata_bytes<-8*sum(vapply(meta,function(p)p$size_bytes,numeric(1L)))+8*1024^2
  q(metadata_bytes<=s$read_budget$max_metadata_bytes,"conservative metadata-read cap exceeded")
  collection<-jsonlite::read_json(gsc_pin(s$collection,4*1024^2),simplifyVector=FALSE)
  manifest<-read.csv(gsc_pin(s$input_manifest,4*1024^2),stringsAsFactors=FALSE)
  producer<-gnrr_bind(s,collection,manifest);cost<-gnrr_cost(s)
  q(dir.create(out),"exclusive replay output creation failed")
  attempts<-list();finished<-FALSE;engine<-NULL;started<-proc.time()[["elapsed"]]
  on.exit(if(!finished)try(gfr_write(gfr_json_raw(list(schema_version="glofas_nonlinear_replay_failure_v1",
    status="FAILED_PARTIAL_REPLAY_RETAINED_NO_INFERENCE",attempted_reads=attempts,
    factory_evaluations=if(is.null(engine))0L else engine$audit$factory_calls,
    value_evaluations=if(is.null(engine))0L else engine$audit$value_calls,
    generated_metadata=if(is.null(engine))list()else engine$audit$metadata,
    saved_callback_calls=0L,applied_updates=0L,future_truth_read=FALSE,new_fits=0L)),
    file.path(out,"FAILED_REPLAY_RECEIPT.json"),out,s$limits$output_bytes),silent=TRUE),add=TRUE)
  read_one<-function(pin,role) {
    path<-gsc_pin(pin,8*1024^3);at<-length(attempts)+1L
    q(at<=2L,"two-read admission exhausted")
    attempts[[at]]<<-list(role=role,path=path,size_bytes=pin$size_bytes,sha256=pin$sha256,status="DESERIALIZATION_ATTEMPTED")
    value<-readRDS(path);attempts[[at]]$status<<-"DESERIALIZED";value
  }
  design<-read_one(s$design,"truth_free_design");history<-gfh_reference_history(design,30L)
  object<-read_one(s$median_model,"gft-al-p050");gsc_validate_target(object,producer)
  q(identical(object$task_id,"gft-al-p050")&&nrow(design$future_key)==28L&&
    identical(as.numeric(as.Date(design$future_key$target_date)),as.numeric(gsc_dates())),
    "only frozen median AL/H28 role admitted")
  q(isTRUE(object$fit$vb_diagnostics$future_y_working_likelihood_used)&&
    identical(object$fit$vb_diagnostics$future_gaussian_prior_used,FALSE),"retained same-family path flags required")
  # Use a new empty child rather than R's own pre-existing session directory.
  scratch_child<-file.path(scratch,"contract_metadata")
  q(!file.exists(scratch_child)&&dir.create(scratch_child),"exclusive metadata scratch creation failed")
  engine<-gnr_engine(root,scratch_child,s$metadata_serialization)
  context<-gnr_context(design,engine);identities<-gnr_identities(context)
  q(identical(as.character(colnames(object$fit$draws$theta)),history$columns),"coefficient column identity mismatch")
  control<-s$replay;control$direction_steps<-as.numeric(unlist(control$direction_steps))
  elapsed<-proc.time()[["elapsed"]]-started
  control$remaining_seconds<-s$limits$wall_seconds-elapsed
  result<-gnr_replay(engine,context,object$fit,control)
  q(identical(result$feature_columns,history$columns),"fresh feature order differs from retained coefficient order")
  outputs<-list(feature_parity.csv=gfr_csv_raw(result$parity),
    directional_finite_differences.csv=gfr_csv_raw(result$directional_finite_differences),
    strict_causality.csv=gfr_csv_raw(result$causality),
    actual_input_scalers.csv=gfr_csv_raw(identities$input_scalers),
    actual_initial_states.csv=gfr_csv_raw(identities$initial_states))
  identities$input_scalers<-identities$initial_states<-NULL
  result$parity<-result$directional_finite_differences<-result$causality<-NULL
  result$actual_context_identity<-identities
  outputs$replay_summary.json<-gfr_json_raw(result)
  q(sum(vapply(outputs,length,integer(1L)))<=s$read_budget$max_replay_output_bytes,"compact replay output cap exceeded")
  for(name in names(outputs))gfr_write(outputs[[name]],file.path(out,name),out,s$limits$output_bytes)
  rm(design,object,context,history,outputs);gc(FALSE)
  for(pin in s[c("design","median_model")]) {
    gsc_pin(pin,8*1024^3);at<-which(vapply(attempts,function(p)identical(p$path,pin$path),logical(1L)))
    attempts[[at]]$post_read_sha256<-pin$sha256
  }
  for(pin in meta)gsc_pin(pin,4*1024^2)
  gnrr_source(s)
  cpu<-sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])
  q(length(attempts)==2L&&expiry>Sys.time()&&cpu<=s$limits$cpu_seconds&&
    identical(result$status,"PASS_FEATURE_REPLAY_ONLY_NOT_POSTERIOR_ACCURACY"),
    "replay failed a final numerical/lifetime/source gate; artifacts retained")
  receipt<-list(schema_version="glofas_nonlinear_replay_receipt_v1",status=result$status,
    purpose_sha256=args[4L],source_commit=s$source_commit,source_tree=s$source_tree,
    producer_identity=gsc_identity(),input_bindings=s[c("design","median_model")],
    accepted_collection=s$collection,input_manifest=s$input_manifest,read_cost=cost,attempted_reads=attempts,
    original_RDS_deserializations=2L,metadata_serializations=result$metadata_serializations,
    factory_evaluations=result$factory_evaluations,value_evaluations=result$value_evaluations,
    saved_callback_calls=0L,applied_updates=0L,future_truth_read=FALSE,new_fits=0L,
    retuning=FALSE,scoring=FALSE,publication_authorized=FALSE,production_launch_authorized=FALSE,
    posterior_accuracy_qualified=FALSE,CPU_seconds=cpu,independent_supervisor_closure_still_required=TRUE)
  gfr_write(gfr_json_raw(receipt),file.path(out,"NONLINEAR_REPLAY_RECEIPT.json"),out,s$limits$output_bytes)
  files<-list.files(out,full.names=TRUE)
  inventory<-data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,
    sha256=unname(tools::sha256sum(files)))
  gfr_write(gfr_csv_raw(inventory),file.path(out,"artifact_manifest.csv"),out,s$limits$output_bytes)
  finished<-TRUE;cat("GLOFAS_AUTHENTIC_NONLINEAR_REPLAY_PASS_NO_INFERENCE_NO_TRUTH\n")
  invisible(receipt)
}
if(sys.nframe()==0L)gnrr_main()
