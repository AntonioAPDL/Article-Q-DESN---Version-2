#!/usr/bin/env Rscript
# A new, separate four-object diagnostic purpose. The earlier three-object
# contract remains closed and unchanged. No coordinate step is applied here.
source("scripts/glofas_fixed_target_forensic_reader.R")
source("application/R/glofas_fixed_target_stationarity.R")

gfs_sources <- function() c(gfr_sources(), "scripts/glofas_fixed_target_stationarity_reader.R",
  "application/R/glofas_fixed_target_stationarity.R", "application/R/latent_path_vb_al.R")
gfs_scope <- function(s) {
  q <- gfr_require; gst_unique_objects(s)
  fields <- c("schema_version","purpose","nonce","expires_utc","source_root","source_commit",
    "source_tree","source_files","expected_identity","collection","input_manifest","design",
    "median_model","configs","prior_export_receipt","prior_export_manifest","prior_export_terminal",
    "prior_summaries","read_budget","limits","output_root","allow_original_reads",
    "allow_coordinate_equation_evaluation","allow_applied_updates","allow_truth_read","allow_callbacks",
    "allow_refit","allow_retuning","allow_forecasting","allow_scoring","allow_publication")
  forbidden <- c("allow_applied_updates","allow_truth_read","allow_callbacks","allow_refit",
    "allow_retuning","allow_forecasting","allow_scoring","allow_publication")
  q(is.list(s) && length(s)==length(fields) && setequal(names(s),fields) &&
    identical(s$schema_version,"glofas_fixed_target_stationarity_contract_v1") &&
    identical(s$purpose,"MEDIAN_AL_COORDINATE_EQUATIONS_AND_TWO_CONFIGS_NO_APPLIED_UPDATES") &&
    isTRUE(s$allow_original_reads) && isTRUE(s$allow_coordinate_equation_evaluation) &&
    all(vapply(s[forbidden],identical,logical(1L),FALSE)), "exact separate stationarity purpose required")
  q(is.character(s$nonce) && length(s$nonce)==1L && grepl("^[a-f0-9]{32,64}$",s$nonce) &&
    all(vapply(s[c("source_commit","source_tree")],function(x)is.character(x)&&length(x)==1L&&
      grepl("^[a-f0-9]{40}$",x),logical(1L))) && gst_same(s$expected_identity,gsc_identity()),
    "full diagnostic and producer identities required")
  q(is.list(s$configs) && setequal(names(s$configs),gfr_ids()) && length(s$configs)==2L &&
    is.list(s$prior_summaries) && setequal(names(s$prior_summaries),gfr_ids()) &&
    length(s$prior_summaries)==2L, "exact two config and original-summary roles required")
  for(pin in c(list(s$design,s$median_model),s$configs))gfr_pin_shape(pin,8*1024^3)
  metadata <- c(s[c("collection","input_manifest","prior_export_receipt","prior_export_manifest",
    "prior_export_terminal")],s$prior_summaries)
  for(pin in metadata)gfr_pin_shape(pin,4*1024^2)
  q(identical(s$design$sha256,"193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3") &&
    identical(s$input_manifest$sha256,gsc_identity()$input_manifest_sha256) &&
    identical(basename(s$design$path),"shared_truth_free_design.rds") &&
    identical(basename(s$median_model$path),"fit.rds") &&
    identical(basename(s$collection$path),"accepted_producers.json") &&
    identical(basename(s$prior_export_receipt$path),"FORENSIC_READ_RECEIPT.json") &&
    identical(basename(s$prior_export_manifest$path),"artifact_manifest.csv") &&
    grepl("\\.json$",s$prior_export_terminal$path), "exact payload and prior closed-export interfaces required")
  for(id in gfr_ids())q(identical(basename(s$configs[[id]]$path),paste0(id,".rds")) &&
    s$configs[[id]]$size_bytes<=1024^2 &&
    identical(basename(s$prior_summaries[[id]]$path),paste0(id,"_summary.json")),
    "config and summary names must identify the admitted fixed task")
  b<-s$limits;keys<-c("cpu_seconds","wall_seconds","memory_bytes","output_bytes","logical_cpu")
  q(is.list(b)&&setequal(names(b),keys)&&all(vapply(b,gfr_scalar_integer,logical(1L)))&&
    b$cpu_seconds>=60&&b$cpu_seconds<=1800&&b$wall_seconds==b$cpu_seconds&&
    b$memory_bytes>0&&b$memory_bytes<=32*1024^3&&b$output_bytes>0&&b$output_bytes<=64*1024^2&&
    b$logical_cpu%in%0:63&&!b$logical_cpu%in%c(16,18,24,25,31,48,50,56,57,63),
    "finite one-core stationarity-reader allocation required")
  r<-s$read_budget;keys<-c("max_payload_hash_bytes","max_deserialization_bytes",
    "max_RDS_deserializations","max_metadata_bytes","max_equation_output_bytes")
  q(is.list(r)&&setequal(names(r),keys)&&all(vapply(r,gfr_scalar_integer,logical(1L)))&&
    all(unlist(r)>0)&&r$max_RDS_deserializations==4L&&r$max_deserialization_bytes<=24*1024^3&&
    r$max_payload_hash_bytes<=48*1024^3&&r$max_metadata_bytes<=32*1024^2&&
    r$max_equation_output_bytes<=10*1024^2,"finite four-object diagnostic allowance required")
  gfs_cost(s);invisible(TRUE)
}
gfs_cost <- function(s) {
  bytes<-sum(vapply(c(list(s$design,s$median_model),s$configs),function(p)p$size_bytes,numeric(1L)))
  gfr_require(bytes<=s$read_budget$max_deserialization_bytes &&
    2*bytes<=s$read_budget$max_payload_hash_bytes && s$read_budget$max_RDS_deserializations==4L,
    "four-object before/after hash and read allowance exceeded")
  list(payload_hash_bytes=2*bytes,deserialization_bytes=bytes,RDS_deserializations=4L)
}
gfs_source <- function(s) {
  q<-gfr_require;root<-normalizePath(getwd(),mustWork=TRUE)
  git<-function(a){z<-system2("/usr/bin/git",c("--no-replace-objects","-c","core.fsmonitor=false",a),stdout=TRUE)
    q(is.null(attr(z,"status")),"stationarity source Git check failed");unname(z)}
  q(identical(root,s$source_root)&&identical(git(c("rev-parse","--show-toplevel")),root)&&
    identical(git(c("rev-parse","HEAD")),s$source_commit)&&
    identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=all"))),
    "exact clean committed stationarity source required")
  paths<-vapply(s$source_files,function(p){gfr_pin_shape(p,1024^2);p$path},character(1L))
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,gfs_sources())),
    "exact new wrapper, inherited guards, equation helper and prior-definition source closure required")
  for(pin in s$source_files)gsc_pin(pin,1024^2)
  for(rel in gfs_sources())q(identical(git(c("hash-object","--no-filters","--",shQuote(rel))),
    git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel))))),"source differs from committed blob")
  invisible(root)
}
gfs_metadata_bind <- function(s,collection,manifest,receipt,export_manifest,terminal,summaries) {
  q<-gfr_require;gsc_validate_collection(collection,gsc_identity())
  q(is.data.frame(manifest)&&all(c("relative_path","size_bytes","sha256","role")%in%names(manifest))&&
    !anyDuplicated(manifest$relative_path),"frozen input manifest schema required")
  base<-dirname(dirname(s$input_manifest$path))
  expected<-c(list(truth_free_shared_design=s$design),s$configs)
  for(role in names(expected)) {
    pin<-expected[[role]];path_role<-if(role=="truth_free_shared_design")role else "transition_task_configuration"
    at<-which(manifest$role==path_role & manifest$relative_path==substring(pin$path,nchar(base)+2L))
    q(length(at)==1L && manifest$size_bytes[at]==pin$size_bytes &&
      identical(manifest$sha256[at],pin$sha256)&&
      identical(normalizePath(file.path(base,manifest$relative_path[at]),mustWork=FALSE),pin$path),
      "design/config payload is not its authenticated manifest role")
  }
  q(identical(receipt$schema_version,"glofas_fixed_target_forensic_receipt_v1")&&
    identical(receipt$status,"TWO_AL_STATES_EXPORTED_NOT_STABILITY_OR_ACCURACY_CERTIFICATE")&&
    gst_same(receipt$producer_identity,gsc_identity())&&receipt$RDS_deserializations==3L&&
    receipt$saved_callback_calls==0L&&receipt$coordinate_updates==0L&&
    identical(receipt$future_truth_read,FALSE)&&receipt$new_fits==0L&&
    identical(receipt$publication_authorized,FALSE)&&
    gst_same(receipt$input_bindings$design,s$design)&&
    gst_same(receipt$input_bindings$`gft-al-p050`,s$median_model)&&
    gst_same(receipt$accepted_collection,s$collection)&&gst_same(receipt$input_manifest,s$input_manifest),
    "genuine earlier three-read receipt and exact original inputs required")
  q(identical(terminal$schema_version,"glofas_fixed_target_native_terminal_v1")&&
    identical(terminal$purpose_sha256,receipt$purpose_sha256)&&
    identical(terminal$source_commit,receipt$source_commit)&&terminal$native_exit_code==0&&
    isTRUE(terminal$owner_terminated)&&isTRUE(terminal$worker_terminated)&&!isTRUE(terminal$timed_out)&&
    terminal$original_RDS_deserializations==3L&&terminal$saved_callback_calls==0L&&
    terminal$coordinate_updates==0L&&identical(terminal$future_truth_read,FALSE)&&
    terminal$new_scientific_fits==0L,"closed successful native terminal receipt required")
  q(is.data.frame(export_manifest)&&identical(names(export_manifest),c("relative_path","size_bytes","sha256"))&&
    !anyDuplicated(export_manifest$relative_path),"earlier export manifest required")
  for(pin in c(list(s$prior_export_receipt),s$prior_summaries)) {
    at<-which(export_manifest$relative_path==basename(pin$path))
    q(length(at)==1L&&export_manifest$size_bytes[at]==pin$size_bytes&&
      identical(export_manifest$sha256[at],pin$sha256)&&
      identical(dirname(pin$path),dirname(s$prior_export_manifest$path)),
      "earlier receipt/summary is not hash-bound to its original export manifest")
  }
  for(id in gfr_ids()) {
    producer<-Filter(function(p)identical(p$task_id,id),collection$producers)[[1L]]
    fit<-Filter(function(p)identical(p$relative_path,"fit.rds"),producer$artifacts)[[1L]]
    q(gst_same(receipt$input_bindings[[id]],fit[c("path","size_bytes","sha256")])&&
      identical(summaries[[id]]$task_id,id)&&gst_same(summaries[[id]]$producer_identity,producer$identity)&&
      identical(summaries[[id]]$source_model_target_sha256,gsc_identity()$posterior_target_sha256)&&
      identical(summaries[[id]]$future_truth_read,FALSE)&&summaries[[id]]$coordinate_updates==0L,
      "original actual-prior summary does not bind to its accepted immutable fit")
  }
  invisible(TRUE)
}
gfs_prior_compare <- function(config,summary,id) {
  q<-gfr_require
  q(identical(config$task_id,id)&&id%in%gfr_ids()&&
    identical(config$posterior_target_sha256,gsc_identity()$posterior_target_sha256)&&
    is.list(config$vb_args)&&is.list(summary$actual_prior_state)&&
    identical(summary$actual_prior_state$prior,"block_rhs_ns"),"matching frozen config and actual block-RHS state required")
  a<-config$vb_args
  digest<-digest::digest(jsonlite::toJSON(a[c("beta_rhs","alpha_rhs","beta_ridge","prior_sigma")],
    auto_unbox=TRUE,null="null",digits=17),algo="sha256",serialize=FALSE)
  q(identical(digest,config$prior_sha256),"config protected-prior hash differs from serialized request")
  or<-function(x,y)if(is.null(x))y else x
  beta<-or(a$beta_rhs,list());alpha<-modifyList(beta,or(a$alpha_rhs,list()))
  rows<-list();add<-function(block,field,expected,observed) {
    agree<-if(is.numeric(expected)&&is.numeric(observed))
      isTRUE(all.equal(as.numeric(expected),as.numeric(observed),tolerance=1e-12)) else gst_same(expected,observed)
    rows[[length(rows)+1L]]<<-data.frame(task_id=id,block=block,field=field,
      expected=jsonlite::toJSON(expected,auto_unbox=TRUE,null="null",digits=17),
      observed=jsonlite::toJSON(observed,auto_unbox=TRUE,null="null",digits=17),pass=agree,
      interpretation="checked_field_only_not_full_prior_or_posterior_identity",stringsAsFactors=FALSE)
  }
  for(block in c("beta","alpha")) {
    args<-if(block=="beta")beta else alpha
    state<-summary$actual_prior_state$blocks[[block]]$state
    for(field in c("tau0","a_zeta","b_zeta","intercept_prec")) {
      defaults<-list(tau0=1,a_zeta=2,b_zeta=4,intercept_prec=1e-9)
      expected<-or(args[[field]],defaults[[field]])
      q(is.numeric(expected)&&length(expected)==1L&&is.finite(expected)&&expected>0,
        "positive scalar constructor hyperparameters required")
      add(block,field,as.numeric(expected),as.numeric(state[[field]]))
    }
    add(block,"zeta2_fixed",args$zeta2_fixed,state$zeta2_fixed)
    add(block,"update_zeta",is.null(args$zeta2_fixed),state$update_zeta)
    control<-or(a$rhs,list());freeze<-as.numeric(or(control$freeze_tau_warmup_iters,0L))
    minimum<-as.numeric(or(control$min_tau_updates,0L));if(freeze>0)minimum<-max(1,minimum)
    for(field in c("freeze_tau_warmup_iters","update_every","min_tau_updates")) {
      expected<-switch(field,freeze_tau_warmup_iters=freeze,
        update_every=as.numeric(or(control$update_every,1L)),min_tau_updates=minimum)
      add(block,paste0("rhs_control.",field),expected,as.numeric(state$rhs_control[[field]]))
    }
  }
  prior_sigma<-or(a$prior_sigma,list());a0<-as.numeric(or(prior_sigma$a,2))
  q(length(a0)==1L&&is.finite(a0)&&a0>0,"one source-shared prior scale shape required")
  shapes<-as.numeric(unlist(summary$source_scale_state$shape))
  q(length(shapes)==2L,"Y/G source shape export required")
  add("source_Y","scale_shape_a_plus_1.5n",a0+1.5*(12455+28),shapes[1L])
  add("source_G","scale_shape_a_plus_1.5n",a0+1.5*(12455+1428),shapes[2L])
  q(is.null(a$prior_addition),"non-null additional-prior request needs a separately specified comparison")
  linear<-summary$actual_prior_state$prior_linear
  add("all","zero_prior_linear_range",c(0,0),as.numeric(unlist(linear$range)))
  add("all","prior_linear_length",2502,as.numeric(linear$length))
  out<-do.call(rbind,rows);rownames(out)<-NULL;out
}
gfs_main <- function(args=commandArgs(TRUE)) {
  q<-gfr_require
  if(identical(args,"--help")){cat("Usage: Rscript --vanilla scripts/glofas_fixed_target_stationarity_reader.R --contract FILE --sha256 SHA --execute\n");return(invisible(NULL))}
  q(length(args)==5L&&identical(args[c(1L,3L,5L)],c("--contract","--sha256","--execute")),
    "explicit new external stationarity purpose required")
  purpose<-normalizePath(args[2L],mustWork=TRUE)
  q(grepl("\\.json$",purpose)&&file.info(purpose)$size<=1024^2&&gsc_hash_string(args[4L])&&
    identical(unname(tools::sha256sum(purpose)),args[4L]),"exact bounded external purpose digest required")
  s<-jsonlite::read_json(purpose,simplifyVector=FALSE);gfs_scope(s)
  root<-normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(purpose,paste0(root,"/")),"stationarity purpose must be external")
  gst_runtime(s);gfs_source(s)
  expiry<-as.POSIXct(s$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry)&&expiry>Sys.time()+s$limits$wall_seconds,"new purpose must cover whole bounded read")
  out<-s$output_root;link<-Sys.readlink(out)
  q(is.character(out)&&length(out)==1L&&startsWith(out,paste0(root,"/local_trackers/"))&&
    !file.exists(out)&&(is.na(link)||!nzchar(link))&&dir.exists(dirname(out))&&
    identical(normalizePath(dirname(out)),dirname(out))&&!grepl("(^|/)\\.\\.(/|$)",out)&&
    system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(out)))==0L,"fresh ignored output required")
  meta<-c(s$source_files,s[c("collection","input_manifest","prior_export_receipt","prior_export_manifest",
    "prior_export_terminal")],s$prior_summaries)
  metadata_bytes<-8*sum(vapply(meta,function(p)p$size_bytes,numeric(1L)))+16*1024^2
  q(metadata_bytes<=s$read_budget$max_metadata_bytes,"conservative new metadata allowance exceeded")
  collection<-jsonlite::read_json(gsc_pin(s$collection,4*1024^2),simplifyVector=FALSE)
  manifest<-read.csv(gsc_pin(s$input_manifest,4*1024^2),stringsAsFactors=FALSE)
  previous<-jsonlite::read_json(gsc_pin(s$prior_export_receipt,4*1024^2),simplifyVector=FALSE)
  previous_manifest<-read.csv(gsc_pin(s$prior_export_manifest,4*1024^2),stringsAsFactors=FALSE)
  terminal<-jsonlite::read_json(gsc_pin(s$prior_export_terminal,4*1024^2),simplifyVector=FALSE)
  summaries<-lapply(s$prior_summaries,function(p)jsonlite::read_json(gsc_pin(p,4*1024^2),simplifyVector=FALSE))
  gfs_metadata_bind(s,collection,manifest,previous,previous_manifest,terminal,summaries)
  cost<-gfs_cost(s);q(dir.create(out),"exclusive diagnostic output creation failed")
  attempts<-list();finished<-FALSE
  on.exit(if(!finished)try(gfr_write(gfr_json_raw(list(status="FAILED_PARTIAL_STATIONARITY_READ_RETAINED",
    attempted_reads=attempts,future_truth_read=FALSE,coordinate_updates_applied=0L,new_fits=0L)),
    file.path(out,"FAILED_READ_RECEIPT.json"),out,s$limits$output_bytes),silent=TRUE),add=TRUE)
  read_one<-function(pin,role) {
    path<-gsc_pin(pin,8*1024^3);at<-length(attempts)+1L
    attempts[[at]]<<-list(role=role,path=path,size_bytes=pin$size_bytes,sha256=pin$sha256,status="DESERIALIZATION_ATTEMPTED")
    value<-readRDS(path);attempts[[at]]$status<<-"DESERIALIZED";value
  }
  comparisons<-list()
  for(id in gfr_ids()) {
    cfg<-read_one(s$configs[[id]],paste0(id,"_config"))
    comparisons[[id]]<-gfs_prior_compare(cfg,summaries[[id]],id)
    rm(cfg);gc(FALSE);gsc_pin(s$configs[[id]],1024^2)
    attempts[[length(attempts)]]$post_read_sha256<-s$configs[[id]]$sha256
  }
  prior_rows<-do.call(rbind,comparisons);rownames(prior_rows)<-NULL
  gfr_write(gfr_csv_raw(prior_rows),file.path(out,"checked_prior_fields.csv"),out,s$limits$output_bytes)
  q(all(prior_rows$pass),"PRIOR_FIELD_MISMATCH: stop before large design/median reads; checked-field evidence retained")
  design<-read_one(s$design,"truth_free_design");gfh_reference_history(design,30L)
  object<-read_one(s$median_model,"gft-al-p050")
  producer<-Filter(function(p)identical(p$task_id,"gft-al-p050"),collection$producers)[[1L]]
  gsc_validate_target(object,producer)
  q(identical(object$task_id,"gft-al-p050"),"only authenticated median task may enter coordinate evaluation")
  equations<-gfst_future_equations(object$fit,design,p0=gsc_task_tau(object$task_id),jitter=1e-8)
  q(equations$coordinate_equation_evaluations==1L&&equations$coordinate_updates_applied==0L&&
    equations$saved_callback_calls==0L&&equations$original_file_reads==0L&&identical(equations$future_truth_read,FALSE),
    "pure no-applied-step equation contract violated")
  payloads<-list(median_coordinate_equations=gfr_csv_raw(equations$per_horizon),
    median_coordinate_summary=gfr_json_raw(equations))
  q(sum(vapply(payloads,length,integer(1L)))<=s$read_budget$max_equation_output_bytes,"equation output cap exceeded")
  for(name in names(payloads))gfr_write(payloads[[name]],file.path(out,paste0(name,
    if(name=="median_coordinate_summary")".json" else ".csv")),out,s$limits$output_bytes)
  rm(object,design,equations,payloads);gc(FALSE)
  for(pin in list(s$design,s$median_model)) {
    gsc_pin(pin,8*1024^3)
    at<-which(vapply(attempts,function(p)identical(p$path,pin$path),logical(1L)))
    attempts[[at]]$post_read_sha256<-pin$sha256
  }
  for(pin in meta)gsc_pin(pin,4*1024^2)
  gfs_source(s)
  q(expiry>Sys.time()&&length(attempts)==4L&&
    sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])<=s$limits$cpu_seconds,
    "new read count/lifetime/CPU limit exceeded")
  receipt<-list(schema_version="glofas_fixed_target_stationarity_receipt_v1",
    status="MEDIAN_COORDINATE_EQUATIONS_AND_SPECIFIED_PRIOR_FIELDS_ONLY_NO_APPLIED_UPDATE",
    purpose_sha256=args[4L],source_commit=s$source_commit,source_tree=s$source_tree,producer_identity=gsc_identity(),
    input_bindings=c(list(design=s$design,median_model=s$median_model),s$configs),
    earlier_three_read_receipt=s$prior_export_receipt,earlier_export_manifest=s$prior_export_manifest,
    earlier_native_terminal=s$prior_export_terminal,earlier_summary_bindings=s$prior_summaries,
    read_cost=c(cost,list(metadata_bytes_upper_bound=metadata_bytes)),attempted_reads=attempts,
    RDS_deserializations=4L,coordinate_equation_evaluations=1L,coordinate_updates_applied=0L,
    saved_callback_calls=0L,future_truth_read=FALSE,new_fits=0L,scoring_calls=0L,publication_authorized=FALSE,
    checked_prior_fields=nrow(prior_rows),checked_prior_fields_pass=all(prior_rows$pass),
    prior_identity_scope="Only named scalar RHS/slab/intercept/control fields, source-scale conditional shapes, and zero linear prior term checked; not complete prior/posterior identity or initialization equivalence.",
    unchecked_prior_fields=c("source_scale_rate_data_terms","all_unlisted_config_fields","MQ_priors",
      "RHS_conditional_shape_execution","intercept_and_feature_coordinate_history","complete_inferential_target_equivalence"),
    full_state_stability_qualified=FALSE,approximation_accuracy_qualified=FALSE,exact_resume_qualified=FALSE,
    CPU_seconds=sum(proc.time()[c("user.self","sys.self","user.child","sys.child")]),
    independent_supervisor_closure_still_required=TRUE)
  gfr_write(gfr_json_raw(receipt),file.path(out,"STATIONARITY_READ_RECEIPT.json"),out,s$limits$output_bytes)
  files<-list.files(out,full.names=TRUE)
  inventory<-data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,sha256=unname(tools::sha256sum(files)))
  gfr_write(gfr_csv_raw(inventory),file.path(out,"artifact_manifest.csv"),out,s$limits$output_bytes)
  finished<-TRUE;cat("GLOFAS_MEDIAN_COORDINATE_EQUATIONS_CHECKED_NO_APPLIED_UPDATE\n")
  invisible(receipt)
}

if(sys.nframe()==0L)gfs_main()
