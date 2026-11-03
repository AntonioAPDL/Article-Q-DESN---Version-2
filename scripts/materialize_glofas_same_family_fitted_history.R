#!/usr/bin/env Rscript
# Separate historical reporting purpose. No saved callback, fitter or truth route.
source("scripts/glofas_same_family_closeout.R")
source("scripts/glofas_same_family_truth_bridge.R") # Shared native group/limit checks only.
source("scripts/glofas_same_family_fitted_history.R")

gfm_selection <- function(name) {
  gsc_require(is.character(name)&&length(name)==1L&&name%in%c("main_figure_v1","all_six_families_v1"),
    "explicit fixed historical presentation scope required")
  if(name=="main_figure_v1")return(c(gsc_tasks()[1:7],"normal_ridge"))
  c(gsc_tasks(),"normal_ridge","normal_rhs")
}

gfm_fresh_output <- function(path) {
  # R returns NA for a path that does not exist; a broken symlink instead has
  # a nonempty target and must still be rejected.
  link <- Sys.readlink(path)
  !file.exists(path) && length(link)==1L && (is.na(link)||!nzchar(link))
}

gfm_scope <- function(s) {
  q<-gsc_require;gst_unique_objects(s)
  fields<-c("schema_version","purpose","nonce","expires_utc","source_root","source_commit","source_tree",
    "source_files","selection","days","origin_date","transform","collection_contract","expected_identity",
    "design","input_manifest","normal_manifest","normal_receipt","normal_quantiles","models",
    "read_budget","limits","output_root","allow_history_read","allow_truth_read","allow_refit",
    "allow_retuning","allow_forecasting","allow_scoring","allow_publication")
  q(is.list(s)&&setequal(names(s),fields)&&identical(s$schema_version,"glofas_same_family_fitted_history_contract_v1")&&
    identical(s$purpose,"AUTHENTIC_PREORIGIN_FITTED_QUANTILE_MATERIALIZATION_ONLY")&&
    isTRUE(s$allow_history_read)&&all(vapply(s[c("allow_truth_read","allow_refit","allow_retuning",
      "allow_forecasting","allow_scoring","allow_publication")],identical,logical(1L),FALSE)),
    "separate history-only purpose and no expanded permissions required")
  q(is.character(s$nonce)&&length(s$nonce)==1L&&grepl("^[a-f0-9]{32,64}$",s$nonce)&&
    all(vapply(s[c("source_commit","source_tree")],function(x)is.character(x)&&length(x)==1L&&
      grepl("^[a-f0-9]{40}$",x),logical(1L))),"full source identities and fresh nonce required")
  ids<-gfm_selection(s$selection)
  gfm_metadata_interfaces(s)
  q(identical(as.numeric(s$days),30)&&identical(s$origin_date,"2022-12-25")&&identical(s$transform,"log1p")&&
    is.list(s$models)&&setequal(names(s$models),ids),"fixed thirty-day window and exact selected model set required")
  b<-s$limits;keys<-c("cpu_seconds","wall_seconds","memory_bytes","output_bytes","logical_cpu")
  scalar<-function(v)is.numeric(v)&&length(v)==1L&&is.finite(v)&&v==floor(v)
  q(is.list(b)&&setequal(names(b),keys)&&all(vapply(b,scalar,logical(1L)))&&
    b$cpu_seconds>=60&&b$cpu_seconds<=1800&&b$wall_seconds==b$cpu_seconds&&
    b$memory_bytes>0&&b$memory_bytes<=32*1024^3&&b$output_bytes>0&&b$output_bytes<=16*1024^2&&
    b$logical_cpu%in%0:63&&!b$logical_cpu%in%c(24,25,48,50,56,57,16,18,31,63),
    "finite one-core historical-reader scope required")
  r<-s$read_budget
  q(is.list(r)&&setequal(names(r),c("max_collector_hash_bytes","max_payload_hash_bytes",
      "max_deserialization_bytes","max_RDS_deserializations","max_metadata_bytes"))&&
    all(vapply(r,scalar,logical(1L)))&&all(unlist(r)>0)&&
    r$max_collector_hash_bytes<=44*1024^3&&r$max_payload_hash_bytes<=128*1024^3&&
    r$max_deserialization_bytes<=64*1024^3&&r$max_RDS_deserializations==length(ids)+1L&&
    r$max_metadata_bytes<=256*1024^2,"finite complete read roles and deserialize count required")
  invisible(ids)
}

gfm_metadata_interfaces <- function(s) {
  paths<-vapply(s[c("collection_contract","input_manifest","normal_manifest","normal_receipt","normal_quantiles")],
    function(p) {gsc_require(is.list(p)&&is.character(p$path)&&length(p$path)==1L&&!is.na(p$path),
      "explicit metadata role paths required");p$path},character(1L))
  gsc_require(grepl("\\.json$",paths[["collection_contract"]])&&grepl("\\.csv$",paths[["input_manifest"]])&&
    identical(basename(paths[["normal_receipt"]]),"normal_reuse_enrollment.json")&&
    identical(basename(paths[["normal_manifest"]]),"artifact_manifest.csv")&&
    identical(basename(paths[["normal_quantiles"]]),"normal_response_quantiles.csv"),
    "exact metadata role interfaces required before any role read")
  invisible(TRUE)
}

gfm_sources <- function()c("scripts/materialize_glofas_same_family_fitted_history.R",
  "scripts/glofas_same_family_fitted_history.R","scripts/glofas_same_family_closeout.R",
  "scripts/glofas_same_family_truth_bridge.R","scripts/glofas_same_family_plot_inputs.R",
  "scripts/collect_glofas_same_family_producers.py","application/scripts/forecast_transition_control.py",
  "application/R/glofas_family_transition.R","scripts/glofas_normal_reuse_enrollment.R",
  "scripts/enroll_glofas_normal_baselines.R")

gfm_source_guard <- function(s) {
  q<-gsc_require;root<-normalizePath(getwd(),mustWork=TRUE)
  git<-function(a) {z<-system2("/usr/bin/git",c("--no-replace-objects","-c","core.fsmonitor=false",a),stdout=TRUE)
    q(is.null(attr(z,"status")),"historical source Git check failed");unname(z)}
  q(identical(root,s$source_root)&&identical(git(c("rev-parse","--show-toplevel")),root)&&
    identical(git(c("rev-parse","HEAD")),s$source_commit)&&identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=all"))),"exact clean committed historical source required")
  paths<-vapply(s$source_files,function(p)p$path,character(1L))
  q(!anyDuplicated(paths)&&setequal(paths,file.path(root,gfm_sources())),"exact reader/validator/source-constructor closure required")
  for(pin in s$source_files)gsc_pin(pin,1024^2)
  for(rel in gfm_sources())q(identical(git(c("hash-object","--no-filters","--",shQuote(rel))),
    git(c("rev-parse",shQuote(paste0(s$source_commit,":",rel))))),"historical source differs from committed blob")
  invisible(root)
}

gfm_bind_models <- function(s,collection,normal) {
  q<-gsc_require;gsc_validate_collection(collection,gsc_identity())
  q(identical(normal$prepared_design,s$design),"Normal enrollment binds a different prepared design")
  ids<-gfm_selection(s$selection);out<-list()
  for(id in ids) {
    supplied<-s$models[[id]]
    q(is.list(supplied)&&setequal(names(supplied),c("path","size_bytes","sha256")),"exact model role pin required")
    if(id%in%gsc_tasks()) {
      z<-Filter(function(p)identical(p$task_id,id),collection$producers)
      q(length(z)==1L,"accepted model identity absent")
      a<-Filter(function(p)identical(p$relative_path,"fit.rds"),z[[1L]]$artifacts)
      q(length(a)==1L,"accepted fit artifact absent");expected<-a[[1L]][c("path","size_bytes","sha256")]
    } else {
      z<-normal$models[[id]];expected<-z$original_fit
      q(identical(z$status,"FIT_REUSE_AND_NEW_ANALYTIC_REPORT_VERIFIED")&&
        identical(normal$input_bindings[[id]]$fit,expected),"Normal model is not the enrolled original fit")
    }
    q(identical(supplied,expected),"model pin does not match its accepted/enrolled role")
    q(is.numeric(supplied$size_bytes)&&length(supplied$size_bytes)==1L&&
      is.finite(supplied$size_bytes)&&supplied$size_bytes>0&&supplied$size_bytes<=8*1024^3&&
      gsc_hash_string(supplied$sha256),"bounded accepted model identity required")
    out[[id]]<-supplied
  };out
}

gfm_read_cost <- function(s,collection,models) {
  q<-gsc_require;r<-s$read_budget
  bytes<-as.numeric(s$design$size_bytes)+sum(vapply(models,`[[`,numeric(1L),"size_bytes"))
  hashed<-collection$artifact_hash_read_bytes+2*bytes
  q(is.numeric(collection$artifact_hash_read_bytes)&&length(collection$artifact_hash_read_bytes)==1L&&
    is.finite(collection$artifact_hash_read_bytes)&&collection$artifact_hash_read_bytes>0&&
    collection$artifact_hash_read_bytes<=r$max_collector_hash_bytes&&hashed<=r$max_payload_hash_bytes&&
    bytes<=r$max_deserialization_bytes&&length(models)+1L==r$max_RDS_deserializations,
    "collector plus before/after payload hashes and one-time deserializations exceed grant")
  list(collector_artifact_hash_bytes=collection$artifact_hash_read_bytes,
    payload_hash_bytes=hashed,deserialized_bytes=bytes,RDS_deserializations=length(models)+1L)
}

gfm_precollect_read_cost <- function(s,cscope) {
  # Resolve the entire prospective ceiling before the collector can hash its
  # first model. Pins are role-authenticated later; rejected/small false pins
  # cannot cause extra deserializations, and collector reads remain below this
  # separately bounded complete-artifact ceiling.
  q<-gsc_require;r<-s$read_budget
  pins<-c(list(s$design),s$models[gfm_selection(s$selection)])
  sizes<-vapply(pins,function(p) {
    q(is.list(p)&&setequal(names(p),c("path","size_bytes","sha256"))&&
      is.character(p$path)&&length(p$path)==1L&&is.numeric(p$size_bytes)&&length(p$size_bytes)==1L&&
      is.finite(p$size_bytes)&&p$size_bytes==floor(p$size_bytes)&&p$size_bytes>0&&p$size_bytes<=8*1024^3&&
      gsc_hash_string(p$sha256),"complete prospective model/design role pins required")
    as.numeric(p$size_bytes)
  },numeric(1L))
  collector<-cscope$read_budget$max_total_artifact_bytes
  q(is.numeric(collector)&&length(collector)==1L&&is.finite(collector)&&collector==floor(collector)&&
    collector>0&&collector<=44*1024^3&&collector<=r$max_collector_hash_bytes&&
    collector+2*sum(sizes)<=r$max_payload_hash_bytes&&sum(sizes)<=r$max_deserialization_bytes&&
    length(pins)==r$max_RDS_deserializations,"prospective complete read ceiling exceeds grant before collection")
  list(prospective_collector_hash_bytes=collector,
    prospective_payload_hash_bytes_upper_bound=collector+2*sum(sizes),
    prospective_deserialized_bytes=sum(sizes),prospective_RDS_deserializations=length(pins))
}

gfm_metadata_cost <- function(s,cscope) {
  # Conservative complete upper bound, not measured filesystem I/O. Include
  # collector sidecars (16 at its4MiB limit), repeated source/metadata pins,
  # Git source checks, purpose parsing and small /proc reads. Payload hashes
  # and RDS deserializations have separate exact role/count calculations.
  pins<-c(s$source_files,s[c("collection_contract","normal_manifest","normal_receipt",
    "normal_quantiles","input_manifest")],cscope[c("ledger_snapshot","complete","controller_source")])
  sizes<-vapply(pins,function(p) {
    gsc_require(is.list(p)&&is.numeric(p$size_bytes)&&length(p$size_bytes)==1L&&
      is.finite(p$size_bytes)&&p$size_bytes>0&&p$size_bytes<=32*1024^2,"bounded metadata role size required")
    as.numeric(p$size_bytes)
  },numeric(1L))
  bound<-8*sum(sizes)+16*4*1024^2+2*1024^2
  gsc_require(bound<=s$read_budget$max_metadata_bytes,"complete conservative metadata read budget exceeded")
  list(metadata_read_bytes_upper_bound=bound,metadata_meter="conservative_code_path_bound_not_OS_IO_meter")
}

gfm_rows <- function(object,design,id,producer=NULL,normal=NULL) {
  if(id%in%gsc_tasks()) {
    gsc_validate_target(object,producer)
    gfh_transition_rows(object,design,30L)
  } else {
    q<-gsc_require;z<-normal$models[[id]]
    q(identical(object$state_contract_hash,z$original_state_contract_hash)&&
      identical(object$shared_design_reference$state_contract_hash,z$original_state_contract_hash)&&
      identical(object$shared_design_reference$sha256,normal$original_design$sha256),
      "Normal original state/design identity differs from enrollment")
    gfh_normal_rows(object,design,id,30L)
  }
}

gfm_crossings <- function(rows) {
  do.call(rbind,lapply(unique(rows$family),function(f) {
    x<-rows[rows$family==f,];dates<-sort(unique(x$target_date));counts<-integer(length(dates))
    for(i in seq_along(dates)) {
      a<-x[x$target_date==dates[i],];a<-a[order(a$tau),]
      gsc_require(identical(as.numeric(a$tau),gsc_tau()),"historical crossing grid incomplete")
      counts[i]<-sum(diff(a$quantile_transformed)<0)
    }
    data.frame(family=f,target_date=dates,raw_crossings=counts,adjacent_exposure=6L,
      raw_crossing_rate=counts/6,isotonic_adjustment=FALSE,stringsAsFactors=FALSE)
  }))
}

gfm_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript --vanilla scripts/materialize_glofas_same_family_fitted_history.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  q<-gsc_require
  q(length(args)==5L&&identical(args[c(1L,3L,5L)],c("--contract","--sha256","--execute")),"exact separate history purpose required")
  purpose<-normalizePath(args[2L],mustWork=TRUE)
  q(grepl("\\.json$",purpose)&&file.info(purpose)$size<=1024^2&&gsc_hash_string(args[4L])&&
    identical(unname(tools::sha256sum(purpose)),args[4L]),"bounded exact historical purpose digest required")
  s<-jsonlite::read_json(purpose,simplifyVector=FALSE);ids<-gfm_scope(s)
  q(!startsWith(purpose,paste0(normalizePath(getwd()),"/")),"external private history purpose required")
  gst_runtime(s);root<-gfm_source_guard(s)
  expiry<-as.POSIXct(s$expires_utc,format="%Y-%m-%dT%H:%M:%SZ",tz="UTC")
  q(!is.na(expiry)&&expiry>Sys.time()+s$limits$wall_seconds,"purpose must cover complete bounded history read")
  out<-s$output_root
  q(is.character(out)&&length(out)==1L&&startsWith(out,paste0(root,"/local_trackers/"))&&
    gfm_fresh_output(out)&&dir.exists(dirname(out))&&
    identical(normalizePath(dirname(out)),dirname(out))&&!grepl("(^|/)\\.\\.(/|$)",out)&&
    system2("/usr/bin/git",c("check-ignore","--quiet","--",shQuote(out)))==0L,"fresh ignored historical output required")
  # Collection is the first payload operation. It authenticates every accepted
  # fit byte but deserializes none; no model/design read can precede this gate.
  collection_path<-gsc_pin(s$collection_contract,1024^2)
  cscope<-jsonlite::read_json(collection_path,simplifyVector=FALSE)
  q(identical(basename(s$normal_receipt$path),"normal_reuse_enrollment.json")&&
    identical(basename(s$normal_manifest$path),"artifact_manifest.csv")&&
    identical(basename(s$normal_quantiles$path),"normal_response_quantiles.csv")&&
    grepl("\\.csv$",s$input_manifest$path)&&grepl("\\.json$",collection_path)&&
    grepl("\\.sqlite$",cscope$ledger_snapshot$path)&&
    identical(basename(cscope$complete$path),"COMPLETE.json"),"exact metadata role interfaces required")
  metadata_cost<-gfm_metadata_cost(s,cscope)
  prospective_cost<-gfm_precollect_read_cost(s,cscope)
  q(identical(cscope$expected_identity,gsc_identity())&&identical(s$expected_identity,gsc_identity())&&
    identical(cscope$schema_version,"glofas_same_family_collection_contract_v1")&&
    identical(cscope$allow_ledger_mutation,FALSE)&&identical(cscope$allow_refit,FALSE)&&identical(cscope$allow_truth,FALSE)&&
    identical(cscope$controller_source$path,file.path(root,"application/scripts/forecast_transition_control.py"))&&
    cscope$read_budget$max_total_artifact_bytes<=s$read_budget$max_collector_hash_bytes&&
    !startsWith(cscope$ledger_snapshot$path,"/home/jaguir26/.local/state/qdesn_forecast_transition/"),
    "closed destination snapshot and bounded complete producer collection required")
  collected<-system2("/usr/bin/python3.11",c("-I","-S","-B",shQuote(file.path(root,"scripts/collect_glofas_same_family_producers.py")),
    "--contract",shQuote(collection_path),"--sha256",s$collection_contract$sha256),stdout=TRUE)
  q(is.null(attr(collected,"status"))&&sum(nchar(collected,type="bytes"))<4*1024^2,"sixteen-producer historical prerequisite failed")
  collection<-jsonlite::fromJSON(paste(collected,collapse="\n"),simplifyVector=FALSE)
  gsc_validate_collection(collection,gsc_identity())
  normal<-jsonlite::read_json(gsc_pin(s$normal_receipt,2*1024^2),simplifyVector=FALSE)
  nm<-read.csv(gsc_pin(s$normal_manifest,1024^2),stringsAsFactors=FALSE)
  for(pin in s[c("normal_receipt","normal_quantiles")]) {
    at<-which(nm$relative_path==basename(pin$path))
    q(length(at)==1L&&nm$size_bytes[at]==pin$size_bytes&&nm$sha256[at]==pin$sha256,"Normal manifest role binding differs")
  }
  normal_rows<-read.csv(gsc_pin(s$normal_quantiles,1024^2),stringsAsFactors=FALSE)
  gsc_normal_rows(normal_rows,normal,s$design$sha256)
  q(identical(s$design$sha256,"193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3")&&
    identical(s$input_manifest$sha256,gsc_identity()$input_manifest_sha256),"exact truth-free prepared design and input roles required")
  manifest<-read.csv(gsc_pin(s$input_manifest,1024^2),stringsAsFactors=FALSE)
  at<-which(manifest$role=="truth_free_shared_design")
  q(length(at)==1L&&manifest$size_bytes[at]==s$design$size_bytes&&manifest$sha256[at]==s$design$sha256&&
    identical(normalizePath(file.path(dirname(dirname(s$input_manifest$path)),manifest$relative_path[at]),mustWork=FALSE),
      s$design$path),"design differs from frozen truth-free role")
  models<-gfm_bind_models(s,collection,normal);cost<-c(gfm_read_cost(s,collection,models),prospective_cost,metadata_cost)
  # Every allowed RDS identity and count is now resolved, prior to deserialize.
  design<-readRDS(gsc_pin(s$design,8*1024^3))
  gfh_reference_history(design,30L)
  tables<-list()
  for(id in ids) {
    object<-readRDS(gsc_pin(models[[id]],8*1024^3))
    producer<-if(id%in%gsc_tasks())Filter(function(z)identical(z$task_id,id),collection$producers)[[1L]] else NULL
    tables[[id]]<-gfm_rows(object,design,id,producer,normal)
    rm(object);gc(FALSE);gsc_pin(models[[id]],8*1024^3)
  }
  gsc_pin(s$design,8*1024^3);rm(design);gc(FALSE)
  rows<-do.call(rbind,tables);rownames(rows)<-NULL
  expected_families<-if(s$selection=="main_figure_v1")c("Independent AL","Normal Ridge") else gsc_families()[-1L]
  q(nrow(rows)==30L*7L*length(expected_families)&&setequal(unique(rows$family),expected_families)&&
    !anyDuplicated(paste(rows$family,rows$target_date,rows$tau)),"complete historical presentation grid required")
  gfm_source_guard(s)
  for(pin in s[c("collection_contract","normal_manifest","normal_receipt","normal_quantiles","input_manifest")])gsc_pin(pin,2*1024^2)
  q(expiry>Sys.time()&&sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])<=s$limits$cpu_seconds,
    "complete historical purpose lifetime/CPU budget exceeded")
  q(dir.create(out),"historical output creation failed")
  write.csv(rows,file.path(out,"fitted_conditional_quantiles.csv"),row.names=FALSE)
  write.csv(gfm_crossings(rows),file.path(out,"raw_fitted_crossings.csv"),row.names=FALSE)
  jsonlite::write_json(list(schema_version="glofas_same_family_fitted_history_receipt_v1",
    status="AUTHENTIC_FITTED_HISTORY_MATERIALIZED_NOT_FORECAST_OR_ARTICLE_RELEASE",source_commit=s$source_commit,
    source_tree=s$source_tree,purpose_sha256=args[4L],selection=s$selection,model_bindings=models,
    design=s$design,input_manifest=s$input_manifest,collection_contract=s$collection_contract,
    normal_enrollment=s$normal_receipt,read_cost=cost,producer_count=16L,history_start="2022-11-26",
    history_end="2022-12-25",origin=s$origin_date,probabilities=gsc_tau(),rows=nrow(rows),
    fitted_functional="VB_mean_conditional_quantile_on_log1p_scale",inverse_transform="expm1_not_original_scale_mean",
    future_truth_read=FALSE,saved_callback_calls=0L,new_fits=0L,forecast_calls=0L,scoring_calls=0L,
    isotonic_adjustment=FALSE,publication_authorized=FALSE,
    CPU_seconds=sum(proc.time()[c("user.self","sys.self","user.child","sys.child")]),
    independent_supervisor_closure_still_required=TRUE),file.path(out,"FITTED_HISTORY_DECISION.json"),
    pretty=TRUE,auto_unbox=TRUE,digits=17)
  files<-list.files(out,full.names=TRUE)
  q(sum(file.info(files)$size)+65536<s$limits$output_bytes,"historical output budget exceeded")
  write.csv(data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,
    sha256=unname(tools::sha256sum(files))),file.path(out,"artifact_manifest.csv"),row.names=FALSE)
  cat("GLOFAS_AUTHENTIC_FITTED_HISTORY_COMPLETE_NOT_PUBLICATION\n")
  invisible(rows)
}

if(sys.nframe()==0L)gfm_main()
