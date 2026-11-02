# New-source MQ qualification guards and deterministic preparation algebra.
# Defining these functions grants no permission to read an authentic payload.
source("scripts/qualify_integrated_quantile_forecast.R",local=TRUE)
source("scripts/runtime_identity_cache_observations.R",local=TRUE)
mqa_require <- function(ok,why) {
  if(!isTRUE(ok))stop(paste0("MQ_ARRAY_QUALIFICATION: ",why),call.=FALSE)
  invisible(TRUE)
}
mqa_hash <- function(x)digest::digest(x,algo="sha256",serialize=TRUE,serializeVersion=2L)
mqa_hex <- function(x,n=64L)is.character(x)&&length(x)==1L&&!is.na(x)&&
  grepl(paste0("^[a-f0-9]{",n,"}$"),x)
mqa_equal <- function(x,y) {
  x <- unlist(x,use.names=FALSE)
  is.numeric(x)&&length(x)==length(y)&&all(is.finite(x))&&all(x==y)
}
# JSON object key order and 1 versus 1.0 are metadata representation, not a
# new scientific unit. Unnamed array order and every scalar value stay exact.
# This is never used to relax hashes or feature/draw order in the RDS payload.
mqa_metadata_equal <- function(a,b) {
  if(is.list(a)&&is.list(b)&&!is.data.frame(a)&&!is.data.frame(b)) {
    if(length(a)!=length(b))return(FALSE)
    na<-names(a);nb<-names(b)
    if(is.null(na)!=is.null(nb))return(FALSE)
    if(!is.null(na)) {
      if(anyDuplicated(na)||anyDuplicated(nb)||!setequal(na,nb))return(FALSE)
      b<-b[match(na,nb)]
    }
    return(all(vapply(seq_along(a),function(i)mqa_metadata_equal(a[[i]],b[[i]]),logical(1L))))
  }
  if(is.numeric(a)&&is.numeric(b))return(length(a)==length(b)&&
    identical(dim(a),dim(b))&&isTRUE(all(as.double(a)==as.double(b))))
  identical(a,b)
}
mqa_unique_json_objects <- function(x,depth=0L) {
  mqa_require(depth<=50L,"JSON metadata nesting limit exceeded")
  if(is.list(x)) {
    n<-names(x)
    mqa_require(is.null(n)||(!anyDuplicated(n)&&all(nzchar(n))),"duplicate or empty JSON object key rejected")
    for(v in x)mqa_unique_json_objects(v,depth+1L)
  }
  invisible(TRUE)
}
# The frozen Jerez contract remains immutable. Its byte-identical six inputs
# may have a separately authenticated Muscat materialization; this is not a
# change of unit, target, parameter row, clock, role, size or content digest.
mqa_original_unit_bridge <- function(materialized,original) {
  q<-mqa_require
  mqa_unique_json_objects(materialized);mqa_unique_json_objects(original)
  q2_geometry(materialized);q2_geometry(original)
  nonasset<-setdiff(names(original),"assets")
  q(setequal(names(materialized),names(original))&&
    mqa_metadata_equal(materialized[nonasset],original[nonasset]),
    "all nonasset original-unit metadata must remain exact")
  roles<-c("design","fixture","posterior","target_contract","worker_manifest","cell_target_audit")
  q(is.list(materialized$assets)&&is.list(original$assets)&&length(materialized$assets)==6L&&
    length(original$assets)==6L&&setequal(names(materialized$assets),roles)&&setequal(names(original$assets),roles),
    "exact six original asset roles required")
  path_ok<-function(p) is.character(p)&&length(p)==1L&&!is.na(p)&&startsWith(p,"/")&&
    !grepl("//|(^|/)\\.\\.?(/|$)|/$",p)
  out<-lapply(roles,function(role) {
    old<-original$assets[[role]];new<-materialized$assets[[role]]
    for(p in list(old,new))q(is.list(p)&&setequal(names(p),c("path","size_bytes","sha256"))&&
      path_ok(p$path)&&is.numeric(p$size_bytes)&&length(p$size_bytes)==1L&&is.finite(p$size_bytes)&&
      p$size_bytes>0&&p$size_bytes==floor(p$size_bytes)&&mqa_hex(p$sha256),"canonical original/materialized asset pin required")
    q(mqa_metadata_equal(old[c("size_bytes","sha256")],new[c("size_bytes","sha256")]),
      "original/materialized asset size or SHA changed")
    # Old paths describe another host and need not exist on this one. New
    # paths must be actual canonical nonsymlink files; q2_metadata MUST hash
    # their bytes before a payload read. No archive is opened in this helper.
    q2_regular(new$path)
    q(file.exists(new$path)&&!dir.exists(new$path)&&
      identical(normalizePath(new$path,mustWork=TRUE),new$path),"canonical local materialized asset path required")
    list(role=role,original_path=old$path,materialized_path=new$path,
      size_bytes=new$size_bytes,sha256=new$sha256,path_relocated=!identical(old$path,new$path),
      content_equivalence="same_role_size_SHA256_materialized_bytes_must_be_rehashed")
  })
  names(out)<-roles
  list(schema_version="mq_original_unit_materialized_path_bridge_v1",assets=out,
    nonasset_unit_metadata_unchanged=TRUE,original_contract_rewritten=FALSE,
    materialized_content_reverification_required=TRUE)
}
mqa_pin <- function(x,max_bytes=256*1024^2) {
  q <- mqa_require
  q(is.list(x)&&!anyDuplicated(names(x))&&setequal(names(x),c("path","size_bytes","sha256"))&&
    is.character(x$path)&&length(x$path)==1L&&!is.na(x$path)&&
    is.numeric(x$size_bytes)&&length(x$size_bytes)==1L&&is.finite(x$size_bytes)&&
    x$size_bytes>0&&x$size_bytes==floor(x$size_bytes)&&x$size_bytes<=max_bytes&&mqa_hex(x$sha256),
    "complete bounded file pin required")
  q2_regular(x$path)
  q(file.exists(x$path)&&!dir.exists(x$path)&&
    identical(normalizePath(x$path,mustWork=TRUE),x$path)&&file.info(x$path)$size==x$size_bytes&&
    identical(unname(tools::sha256sum(x$path)),x$sha256),"pinned source/input bytes changed")
  x$path
}
mqa_scope <- function(s) {
  q <- mqa_require
  mqa_unique_json_objects(s)
  q(is.list(s)&&identical(s$schema_version,"mq_array_source_qualification_contract_v1")&&
    identical(s$purpose,"NEW_SOURCE_MQ_ARRAY_ONE_ORIGINAL_DRAW_ORIGIN")&&
    identical(s$allow_qualification,TRUE)&&identical(s$allow_refit,FALSE)&&
    identical(s$allow_production,FALSE)&&identical(s$allow_scoring,FALSE)&&
    identical(s$allow_article,FALSE)&&identical(s$allow_raw_fixture_deserialization,FALSE),
    "new-source one-unit qualification-only scope required; old purposes are invalid")
  q(mqa_equal(s$training_paths,65536)&&mqa_equal(s$validation_paths,262144)&&
    mqa_equal(s$batch_size,128)&&mqa_equal(s$training_path_range,c(1,65536))&&
    mqa_equal(s$validation_path_range,c(65537,327680))&&
    mqa_equal(s$validation_look_sizes,c(65536,131072,262144))&&
    mqa_equal(s$total_alpha,.05)&&mqa_equal(s$alpha_per_look,rep(.05/3,3))&&
    mqa_equal(s$inversion_tolerance,1e-8)&&mqa_equal(s$parity_absolute_tolerance,1e-10)&&
    mqa_equal(s$parity_relative_tolerance,1e-10)&&
    mqa_equal(s$parity_path_ids,c(1,2,63,64,127,128,4095,4096,4097,8192,16384,32768,
      65535,65536,65537,327680))&&identical(s$rng_backend,"r46_first_step")&&
    identical(s$stop_before_validation_on_split_failure,TRUE),"frozen paths/looks/alpha/error/RNG/parity gates required")
  q2_geometry(s$original_unit)
  a <- s$original_unit$integration_accuracy
  q(mqa_equal(a$alpha_per_shard,.05)&&mqa_equal(a$max_split_absolute,.005)&&
    mqa_equal(a$max_split_relative,.005)&&mqa_equal(a$max_quantile_abs_error,.01)&&
    mqa_equal(a$max_quantile_rel_error,.01),"original accuracy gates cannot change")
  l <- s$limits
  q(is.list(l)&&mqa_equal(l$cpu_seconds,1800)&&mqa_equal(l$wall_term_seconds,1799)&&
    mqa_equal(l$wall_kill_after_seconds,1)&&mqa_equal(l$address_space_bytes,16*1024^3)&&
    mqa_equal(l$output_bytes,256*1024^2)&&mqa_equal(l$logical_cpu,27),"finite new-source budget with tightened wall cap required")
  for(k in c("source_commit","source_tree"))q(mqa_hex(s[[k]],40),"exact candidate source commit/tree required")
  q(identical(s$origin_remote_url,"git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git")&&
    is.character(s$published_ref)&&length(s$published_ref)==1L&&
    grepl("^refs/heads/[A-Za-z0-9][A-Za-z0-9_./-]*$",s$published_ref)&&
    !grepl("\\.\\.|//|/$",s$published_ref),"explicit published source ref required")
  expected <- c(baseline_contract="c1490494d4307cf29ea74f3c002e765ecb790486fe4fad24c0bf04b65a9df4e6",
    baseline_receipt="bffaeb83b8f341603542965cecb877a865f5b152d0b16ac4e872dc11c6b6a1cf",
    baseline_manifest="3cca4efe27ede0759d643b560259336c16492c3dce5b87188927f043be9053da")
  for(k in names(expected))q(identical(s[[k]]$sha256,unname(expected[k])),"historical baseline pin changed")
  invisible(TRUE)
}
mqa_git <- function(root,args) {
  z <- system2("/usr/bin/git",c("--no-replace-objects","-c","core.fsmonitor=false","-C",shQuote(root),args),stdout=TRUE)
  mqa_require(is.null(attr(z,"status")),"Git verification failed")
  unname(z)
}
mqa_git_blob <- function(root,commit,path) {
  mqa_require(mqa_hex(commit,40)&&is.character(path)&&length(path)==1L&&
    !startsWith(path,"/")&&!grepl("(^|/)\\.\\.(/|$)",path),"safe historical Git blob identity required")
  cmd <- paste("/usr/bin/git --no-replace-objects -C",shQuote(root),"cat-file blob",shQuote(paste0(commit,":",path)))
  con <- pipe(cmd,"rb");on.exit(close(con))
  raw <- readBin(con,"raw",n=4*1024^2+1L)
  mqa_require(length(raw)>0L&&length(raw)<=4*1024^2,"bounded historical source blob required")
  raw
}
mqa_required_sources <- function(native_paths)sort(unique(c(native_paths,
  "scripts/qualify_mq_array_methods.R","scripts/mq_array_qualification.R",
  "scripts/prepare_mq_array_observed_prefix.R",
  "application/tests/test_mq_array_qualification.R",
  "scripts/runtime_identity_cache_observations.R",
  "scripts/qualify_integrated_quantile_forecast.R","scripts/integrated_quantile_mq_batch.R",
  "scripts/mq_forecast_array_methods.R","scripts/mq_independent_cdf_certificate.R",
  "scripts/mq_streaming_cdf_certificate.R","application/R/00_packages.R",
  "application/R/joint_qvp_qdesn.R","application/R/latent_path_design.R",
  "application/R/joint_qdesn_pure_recursive_campaign.R","application/R/joint_qdesn_recursive_mean_design.R")))
mqa_source_guard <- function(s,root,verify_publication=TRUE) {
  q <- mqa_require;git <- function(a)mqa_git(root,a)
  q(identical(git(c("rev-parse","HEAD")),s$source_commit)&&
    identical(git(c("rev-parse","HEAD^{tree}")),s$source_tree)&&
    !length(git(c("status","--porcelain","--untracked-files=normal"))),"clean exact candidate source required")
  sm <- mqa_pin(s$source_manifest,1024^2)
  q(identical(sm,file.path(root,"docs/reproducibility/integrated_forecast_transition_sources_20261031.csv")),
    "historical native manifest path differs")
  native <- read.csv(sm,stringsAsFactors=FALSE)
  q(all(c("path","sha256","mode","blob")%in%names(native))&&nrow(native)>0L&&
    !anyDuplicated(native$path),"complete native manifest required")
  paths <- vapply(s$source_files,mqa_pin,character(1L),max_bytes=4*1024^2)
  required <- file.path(root,mqa_required_sources(native$path))
  q(!anyDuplicated(paths)&&setequal(paths,required),"exact complete transitive source closure required")
  for(i in seq_len(nrow(native))) {
    path <- file.path(root,native$path[i])
    q(identical(unname(tools::sha256sum(path)),native$sha256[i]),"unchanged native closure differs")
    tracked <- git(c("ls-files","--stage","--",shQuote(native$path[i])))
    q(length(tracked)==1L&&startsWith(tracked,paste(native$mode[i],native$blob[i])),"native Git mode/blob differs")
  }
  for(p in paths) {
    rel <- substring(p,nchar(root)+2L)
    q(identical(digest::digest(mqa_git_blob(root,s$source_commit,rel),algo="sha256",serialize=FALSE),
      unname(tools::sha256sum(p))),"source pin is not its committed Git blob")
  }
  if(verify_publication) {
    q(identical(git(c("remote","get-url","origin")),s$origin_remote_url),"publication origin differs")
    keys <- c("GIT_TERMINAL_PROMPT","GIT_SSH_COMMAND")
    old <- Sys.getenv(keys,unset=NA_character_)
    on.exit(for(i in seq_along(keys))if(is.na(old[i]))Sys.unsetenv(keys[i])else
      do.call(Sys.setenv,setNames(list(old[i]),keys[i])),add=TRUE)
    Sys.setenv(GIT_TERMINAL_PROMPT="0")
    Sys.setenv(GIT_SSH_COMMAND=paste("/usr/bin/ssh -F /dev/null -oBatchMode=yes",
      "-oControlMaster=no -oControlPath=none -oControlPersist=no -oProxyCommand=none -oProxyJump=none -oRequestTTY=no"))
    remote <- git(c("ls-remote","--exit-code","origin",s$published_ref))
    q(length(remote)==1L&&identical(strsplit(remote,"[[:space:]]+")[[1L]],c(s$source_commit,s$published_ref)),
      "published exact source remote-ref readback differs")
  }
  list(source_files_verified=length(paths),native_files_verified=nrow(native),published_readback=verify_publication)
}

mqa_history_fields <- function(s,b,r) {
  q <- mqa_require
  q(identical(b$schema_version,"mq_batch_acceleration_qualification_v1")&&
    identical(b$source_commit,"a099aba928e6d1fb01931a4b12466125bbb2bc64")&&
    identical(b$source_tree,"48b8baa236859f9f32969593101c75ff45bfa88c")&&
    identical(r$schema_version,"mq_batch_acceleration_qualification_receipt_v1")&&
    identical(r$source_commit,b$source_commit)&&identical(r$source_tree,b$source_tree)&&
    identical(r$purpose_contract_sha256,s$baseline_contract$sha256)&&
    identical(r$status,"QUALIFICATION_COMPLETE_NOT_PRODUCTION")&&
    identical(r$numerical_status,"REVIEW_NUMERICAL_ACCURACY_NOT_QUALIFIED")&&
    identical(r$original_legacy_numerical_status,"REVIEW_INNER_INTEGRATION_RESOLUTION")&&
    identical(r$old_failure_receipts_preserved,TRUE)&&identical(r$thresholds_loosened,FALSE)&&
    identical(r$production_authorized,FALSE)&&identical(r$article_promotion_authorized,FALSE),
    "historical REVIEW evidence must not be relabelled as new-source success")
  for(k in c("original_unit","original_unit_contract","native_rng_source","rng_backend"))
    q(mqa_metadata_equal(s[[k]],b[[k]])&&mqa_metadata_equal(r[[k]],b[[k]]),paste("historical original identity changed",k))
  q(mqa_metadata_equal(r$source_manifest,b$source_manifest)&&
    mqa_metadata_equal(s$source_manifest[c("size_bytes","sha256")],b$source_manifest[c("size_bytes","sha256")]),
    "historical native manifest bytes changed; checkout path relocation alone is allowed")
  q(identical(r$observational_future_truth_used,FALSE)&&r$parameter_refits==0&&r$score_evaluations==0,
    "historical packet must remain a no-fit/no-score probe")
  invisible(TRUE)
}
mqa_history_bridge <- function(s,root) {
  q <- mqa_require
  b <- jsonlite::read_json(mqa_pin(s$baseline_contract,1024^2),simplifyVector=FALSE)
  r <- jsonlite::read_json(mqa_pin(s$baseline_receipt,4*1024^2),simplifyVector=FALSE)
  mp <- mqa_pin(s$baseline_manifest,1024^2);mqa_history_fields(s,b,r)
  out <- dirname(s$baseline_receipt$path)
  q(identical(out,b$output_root)&&identical(dirname(mp),out),"historical output namespace differs")
  m <- read.csv(mp,stringsAsFactors=FALSE)
  names <- c("batch_training_result.rds","frozen_training_candidates.rds","independent_cdf_certificate.rds",
    "independent_cdf_endpoint_evidence.csv","independent_validation_cdf_matrix.rds","progress.json",
    "qualification.json","scalar_training_result.rds","structural_first_horizon_evidence.rds")
  q(identical(names(m),c("relative_path","size_bytes","sha256"))&&nrow(m)==9L&&
    !anyDuplicated(m$relative_path)&&setequal(m$relative_path,names)&&
    setequal(list.files(out,all.files=TRUE,no..=TRUE),c(names,"artifact_manifest.csv")),"historical nine-file inventory differs")
  for(i in seq_len(nrow(m)))mqa_pin(list(path=file.path(out,m$relative_path[i]),
    size_bytes=m$size_bytes[i],sha256=m$sha256[i]))
  q(identical(m$sha256[m$relative_path=="qualification.json"],s$baseline_receipt$sha256),"historical receipt not bound")
  old_root <- sub("/docs/reproducibility/integrated_forecast_transition_sources_20261031.csv$","",b$source_manifest$path)
  q(!identical(old_root,b$source_manifest$path)&&length(b$source_files)>=10L,"historical source closure missing")
  changed <- "scripts/integrated_quantile_mq_batch.R";old_batch <- NULL;bridge <- list()
  for(pin in b$source_files) {
    q(startsWith(pin$path,paste0(old_root,"/")),"historical source escapes its recorded checkout")
    rel <- substring(pin$path,nchar(old_root)+2L);blob <- mqa_git_blob(root,b$source_commit,rel)
    old_sha <- digest::digest(blob,algo="sha256",serialize=FALSE)
    q(length(blob)==pin$size_bytes&&identical(old_sha,pin$sha256),"historical Git blob differs from old source pin")
    current <- file.path(root,rel)
    q(file.exists(current),"historical reference source missing from new closure")
    same <- identical(unname(tools::sha256sum(current)),old_sha)
    q(same||identical(rel,changed),"only explicitly reviewed batch implementation may differ in legacy closure")
    if(identical(rel,changed)) {
      q(identical(old_sha,"f87fa0deefedd0fc155645bc5977625798b7065512a429b58f536e2875387698")&&!same,
        "exact archived old batch and genuinely new batch required")
      old_batch <- blob
    }
    bridge[[length(bridge)+1L]] <- list(path=rel,legacy_sha256=old_sha,
      candidate_sha256=unname(tools::sha256sum(current)),unchanged=same)
  }
  q(!is.null(old_batch),"historical batch is absent from explicit semantic bridge")
  list(schema_version="mq_array_old_to_new_source_bridge_v1",historical_status=r$numerical_status,
    historical_only=TRUE,historical_files_verified=9L,historical_bytes_verified=sum(m$size_bytes),
    closure=bridge,old_batch_raw=old_batch,production_authorized=FALSE)
}

# Pure deterministic reduction. A separate, trusted preparation purpose must
# authenticate the full original bytes; this function does not grant that read.
mqa_reduce_original_payload <- function(design,fixture,draws,unit,preparation) {
  o <- q2_payloads(design,fixture,draws,unit)
  mqa_validate_reduced_objects(o,unit)
  receipt <- list(schema_version="mq_array_observed_prefix_derivation_v1",
    status="DETERMINISTIC_ORIGINAL_PREFIX_REDUCTION_NOT_QUALIFICATION",preparation=preparation,
    original_unit_contract_identity=unit[c("model_cell_id","chain_id","source_row","source_draw_index",
      "origin_id","origin_time","horizons","readout_slopes","rng_namespace","posterior_target_sha256")],
    original_assets=unit$assets,retained_history_count=11000L,future_responses_retained=0L,
    protected_field_sha256=lapply(o,mqa_hash),observed_prefix_sha256=mqa_hash(o$origins[[1L]]$history),
    posterior_rows=1L,source_row=1L,source_draw_index=1L,new_model_fits=0L,score_evaluations=0L,
    known_clock_and_reservoir_unchanged=TRUE,production_authorized=FALSE)
  list(objects=o,derivation=receipt)
}
mqa_validate_reduced_objects <- function(o,unit) {
  q <- mqa_require;q2_geometry(unit)
  mqa_no_callbacks(o)
  q(is.list(o)&&setequal(names(o),c("design","posterior","origins","mapping")),"exact reduced payload roles required")
  d <- o$design;p <- o$posterior;origin <- o$origins
  allowed <- c("scenario_id","design_class","feature_contract","response_lags","reservoir","scale_params",
    "state_center","state_scale","dgp_row","reservoir_meta","Z","row_meta","forecast_map")
  reservoir_fields <- c("D","n","n_tilde","m","m_input","alpha","rho","W","Win","Q","Q_is_identity",
    "act_f","act_k","pi_w","pi_in","w_dist","in_dist","seed")
  q(is.list(d)&&setequal(names(d),allowed)&&identical(d$scenario_id,"asymmetric_laplace_tail")&&
    is.list(d$reservoir)&&!anyDuplicated(names(d$reservoir))&&all(names(d$reservoir)%in%reservoir_fields)&&
    is.list(d$scale_params)&&!anyDuplicated(names(d$scale_params))&&
    all(names(d$scale_params)%in%c("columns","center","scale","standardize"))&&
    identical(d$feature_contract,"pure_recursive_v1")&&is.matrix(d$Z)&&ncol(d$Z)==20L&&
    all(is.finite(d$Z))&&is.data.frame(d$row_meta)&&identical(names(d$row_meta),"full_time_index")&&
    nrow(d$Z)==nrow(d$row_meta)&&all(is.finite(d$row_meta$full_time_index))&&
    all(d$row_meta$full_time_index<=11000)&&!anyDuplicated(d$row_meta$full_time_index)&&
    is.data.frame(d$forecast_map)&&setequal(names(d$forecast_map),c("origin_index","horizon","full_time_index"))&&
    nrow(d$forecast_map)==30L&&all(d$forecast_map$origin_index==1)&&
    identical(as.integer(d$forecast_map$horizon),1:30)&&all(d$forecast_map$full_time_index==11001:11030)&&
    is.data.frame(d$dgp_row)&&setequal(names(d$dgp_row),c("simulated_length","period","dynamics_class","regime_start_fraction"))&&
    identical(names(d$reservoir_meta),"win_scale_global"),"reduced design contains future-derived/unknown fields or changed geometry")
  q(is.list(origin)&&identical(names(origin),"1")&&is.list(origin[[1L]])&&
    setequal(names(origin[[1L]]),c("origin_time","H","history"))&&origin[[1L]]$origin_time==11000&&
    origin[[1L]]$H==30&&is.numeric(origin[[1L]]$history)&&length(origin[[1L]]$history)==11000&&
    all(is.finite(origin[[1L]]$history)),"exact observed history prefix required; future responses forbidden")
  expected_id <- sprintf("%s/chain_01/draw_000001",unit$model_cell_id)
  q(is.list(p)&&setequal(names(p),c("beta","alpha","draw_ids","chain_id","source_draw_index","draw_mapping_sha256"))&&
    identical(p$draw_ids,expected_id)&&p$chain_id==1&&p$source_draw_index==1&&
    identical(dim(p$beta),c(1L,140L))&&identical(dim(p$alpha),c(1L,7L))&&
    all(is.finite(c(p$beta,p$alpha)))&&is.data.frame(o$mapping)&&nrow(o$mapping)==7L&&
    setequal(names(o$mapping),c("draw_id","quantile_index","chain_id","source_draw_index","source_relative_path"))&&
    identical(o$mapping$source_relative_path,rep("source_posterior.csv.gz",7L))&&
    identical(o$mapping$draw_id,rep(expected_id,7L))&&identical(as.integer(o$mapping$quantile_index),1:7)&&
    all(o$mapping$chain_id==1)&&all(o$mapping$source_draw_index==1)&&
    identical(p$draw_mapping_sha256,mqa_hash(o$mapping)),"original correlated posterior row/mapping changed")
  invisible(TRUE)
}
mqa_no_callbacks <- function(x,depth=0L) {
  mqa_require(depth<=20L&&!is.function(x)&&!is.environment(x)&&!isS4(x)&&
    !is.language(x)&&!typeof(x)%in%c("externalptr","weakref","promise"),
    "callbacks, closures, environments or opaque objects forbidden in reduced payload")
  mqa_require(all(names(attributes(x))%in%c("names","dim","dimnames","class","row.names")),
    "callbacks or undeclared response-bearing attributes forbidden in reduced payload")
  if(is.list(x))for(v in x)mqa_no_callbacks(v,depth+1L)
  if(length(attributes(x)))for(v in attributes(x))mqa_no_callbacks(v,depth+1L)
  invisible(TRUE)
}
mqa_derivation_metadata <- function(r,unit,s) {
  q <- mqa_require
  mqa_unique_json_objects(r)
  keys <- c("model_cell_id","chain_id","source_row","source_draw_index","origin_id","origin_time",
    "horizons","readout_slopes","rng_namespace","posterior_target_sha256")
  q(is.list(r)&&identical(r$schema_version,"mq_array_observed_prefix_derivation_v1")&&
    identical(r$status,"DETERMINISTIC_ORIGINAL_PREFIX_REDUCTION_NOT_QUALIFICATION")&&
    mqa_metadata_equal(r$original_unit_contract_identity,unit[keys])&&mqa_metadata_equal(r$original_assets,unit$assets)&&
    r$retained_history_count==11000&&r$future_responses_retained==0&&r$posterior_rows==1&&
    r$source_row==1&&r$source_draw_index==1&&r$new_model_fits==0&&r$score_evaluations==0&&
    identical(r$known_clock_and_reservoir_unchanged,TRUE)&&identical(r$production_authorized,FALSE),
    "original-prefix derivation metadata differs")
  a <- r$preparation
  q(mqa_metadata_equal(a,s$prepared_source)&&mqa_hex(a$source_commit,40)&&mqa_hex(a$source_tree,40)&&
    mqa_hex(a$purpose_contract_sha256)&&mqa_hex(a$reducer_sha256)&&
    identical(a$reducer_relative_path,"scripts/mq_array_qualification.R")&&
    identical(a$trusted_original_byte_verification,TRUE)&&identical(a$read_permission_scope,
      "SEPARATE_TRUSTED_PREPARATION_NOT_QUALIFICATION")&&
    a$archive_design_deserializations==1&&a$archive_fixture_deserializations==1&&
    a$original_posterior_csv_reads==1&&identical(a$future_response_values_consulted,FALSE)&&
    a$model_calls==0&&a$scoring_calls==0,
    "separate authenticated preparation identity and honest archive-read accounting required")
  invisible(TRUE)
}
mqa_validate_derivation <- function(o,r,unit,s) {
  mqa_derivation_metadata(r,unit,s);mqa_validate_reduced_objects(o,unit)
  mqa_require(mqa_metadata_equal(r$protected_field_sha256,lapply(o,mqa_hash))&&
    identical(r$observed_prefix_sha256,mqa_hash(o$origins[[1L]]$history)),"fieldwise original-prefix derivation differs")
  invisible(TRUE)
}
mqa_preparation_scope <- function(s) {
  q <- mqa_require
  mqa_unique_json_objects(s)
  q(is.list(s)&&identical(s$schema_version,"mq_array_trusted_prefix_preparation_contract_v1")&&
    identical(s$purpose,"SEPARATE_TRUSTED_PREPARATION_NOT_QUALIFICATION")&&
    identical(s$allow_original_archive_prefix_preparation,TRUE)&&
    identical(s$allow_qualification,FALSE)&&identical(s$allow_refit,FALSE)&&
    identical(s$allow_scoring,FALSE)&&identical(s$allow_production,FALSE)&&identical(s$allow_article,FALSE)&&
    identical(s$allow_future_response_values,FALSE)&&identical(s$allow_builder_calls,FALSE)&&
    identical(s$selector,"UNCHANGED_Q2_OBSERVED_PREFIX_AND_NATIVE_PARAMETER_ROW_ONLY"),
    "distinct trusted-prefix preparation purpose required")
  q2_geometry(s$original_unit)
  l <- s$limits
  q(mqa_equal(l$cpu_seconds,120)&&mqa_equal(l$wall_term_seconds,119)&&mqa_equal(l$wall_kill_after_seconds,1)&&
    mqa_equal(l$address_space_bytes,2*1024^3)&&mqa_equal(l$output_bytes,64*1024^2)&&mqa_equal(l$logical_cpu,27),
    "finite separate preparation budget required")
  q(mqa_hex(s$source_commit,40)&&mqa_hex(s$source_tree,40)&&
    identical(s$baseline_contract$sha256,"c1490494d4307cf29ea74f3c002e765ecb790486fe4fad24c0bf04b65a9df4e6"),
    "prepared source and authentic historical unit binding required")
  q(identical(s$origin_remote_url,"git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git")&&
    is.character(s$published_ref)&&length(s$published_ref)==1L&&
    grepl("^refs/heads/[A-Za-z0-9][A-Za-z0-9_./-]*$",s$published_ref)&&
    !grepl("\\.\\.|//|/$",s$published_ref),"explicit prepared-source published ref required")
  invisible(TRUE)
}

mqa_timeout_argv <- function(argv,term_seconds=1799L) {
  mqa_require(is.character(argv)&&length(argv)>=5L&&!anyNA(argv)&&
    identical(basename(argv[1L]),"timeout")&&
    identical(argv[2:4],c("--signal=TERM","--kill-after=1s",paste0(term_seconds,"s")))&&
    nzchar(argv[5L])&&!startsWith(argv[5L],"-"),"native exact prospective TERM/KILL timeout required")
  invisible(TRUE)
}
mqa_proc_group <- function(stat) {
  mqa_require(is.character(stat)&&length(stat)==1L&&grepl("^[0-9]+ \\(.*\\) ",stat),"valid native process stat required")
  pid <- suppressWarnings(as.integer(sub(" .*","",stat)))
  fields <- strsplit(sub("^[0-9]+ \\(.*\\) ","",stat),"[[:space:]]+")[[1L]]
  ids <- suppressWarnings(as.integer(fields[c(3L,4L)]))
  mqa_require(length(fields)>=4L&&length(ids)==2L&&all(is.finite(c(pid,ids)))&&
    pid>0&&all(ids>0),"finite process PID/PGID/session required")
  list(pid=pid,process_group=ids[1L],session=ids[2L])
}
mqa_group_guard <- function(self_stat,timeout_stat,timeout_pid) {
  self <- mqa_proc_group(self_stat);supervisor <- mqa_proc_group(timeout_stat)
  mqa_require(identical(supervisor$pid,as.integer(timeout_pid))&&
    identical(supervisor$process_group,supervisor$pid)&&
    identical(self$process_group,supervisor$process_group)&&identical(self$session,supervisor$session),
    "R escaped timeout process group/session or timeout uses foreground scope")
  list(process=self,timeout=supervisor,whole_group_TERM_KILL_scope_verified=TRUE)
}
mqa_affinity_guard <- function(self_allowed,timeout_allowed) {
  mqa_require(identical(self_allowed,"27")&&identical(timeout_allowed,"27"),
    "R and exact timeout supervisor must both retain logical CPU27 affinity")
  list(process_allowed=self_allowed,timeout_allowed=timeout_allowed,logical_cpu=27L)
}
mqa_timeout_ancestor <- function(term_seconds=1799L) {
  pid <- Sys.getpid()
  for(i in 1:12) {
    status <- readLines(sprintf("/proc/%d/status",pid),warn=FALSE)
    pp <- as.integer(trimws(sub("^PPid:","",grep("^PPid:",status,value=TRUE))))
    if(length(pp)!=1L||is.na(pp)||pp<=1)break
    raw <- readBin(sprintf("/proc/%d/cmdline",pp),"raw",n=16384L);stops <- which(raw==as.raw(0))
    if(length(stops)&&tail(stops,1L)==length(raw)) {
      starts <- c(1L,head(stops,-1L)+1L)
      argv <- vapply(seq_along(stops),function(j)if(starts[j]>=stops[j])"" else
        rawToChar(raw[seq.int(starts[j],stops[j]-1L)]),character(1L))
      if(length(argv)&&basename(argv[1L])=="timeout") {
        mqa_timeout_argv(argv,term_seconds)
        exe <- normalizePath(Sys.readlink(sprintf("/proc/%d/exe",pp)),mustWork=TRUE)
        mqa_require(identical(exe,normalizePath("/usr/bin/timeout",mustWork=TRUE)),"timeout executable differs")
        group <- mqa_group_guard(readLines("/proc/self/stat",warn=FALSE),
          readLines(sprintf("/proc/%d/stat",pp),warn=FALSE),pp)
        affinity <- function(path)trimws(sub("^Cpus_allowed_list:","",
          grep("^Cpus_allowed_list:",readLines(path,warn=FALSE),value=TRUE)))
        cpu <- mqa_affinity_guard(affinity("/proc/self/status"),affinity(sprintf("/proc/%d/status",pp)))
        return(list(pid=pp,argv_prefix=argv[1:5],executable=exe,process_group_proof=group,affinity_proof=cpu))
      }
    };pid <- pp
  }
  mqa_require(FALSE,"exact native timeout ancestor absent")
}
mqa_runtime_paths <- function() {
  for(p in c("digest","jsonlite","tools","compiler"))mqa_require(requireNamespace(p,quietly=TRUE),paste("runtime package",p))
  allowed <- c("base","compiler","datasets","digest","graphics","grDevices","jsonlite","methods","stats","tools","utils")
  mqa_require(all(loadedNamespaces()%in%allowed),"unexpected package namespace or inference-engine substitution")
  # All file-backed mappings stay byte-pinned except the separately classified
  # exact three nonexecuting SSSD identity caches. No .so or input exemption.
  mapped <- runtime_ic_snapshot()$strict_mapped_paths
  mqa_require(all(file.exists(mapped))&&!any(dir.exists(mapped)),
    "a strict mapped runtime file disappeared; it cannot be silently excluded")
  package_files <- unlist(lapply(loadedNamespaces(),function(p) {
    base <- find.package(p)
    c(file.path(base,c("DESCRIPTION","NAMESPACE")),list.files(file.path(base,"R"),full.names=TRUE,all.files=TRUE,no..=TRUE),
      list.files(file.path(base,"libs"),full.names=TRUE,recursive=TRUE))
  }),use.names=FALSE)
  files <- c(mapped,package_files,file.path(R.home("bin"),c("Rscript","exec/R")),
    "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript",
    list.files(R.home("lib"),full.names=TRUE),"/usr/bin/timeout","/usr/bin/git","/usr/bin/ssh")
  files <- files[file.exists(files)&!dir.exists(files)]
  sort(unique(normalizePath(files,mustWork=TRUE)))
}
mqa_runtime_guard <- function(s) {
  q <- mqa_require
  q(identical(as.character(getRversion()),"4.6.0")&&
    identical(normalizePath(R.home()),"/data/jaguir26/local/opt/R/4.6.0/lib64/R")&&
    unname(Sys.info()[["nodename"]])%in%c("muscat","muscat.be.ucsc.edu")&&
    "--vanilla"%in%commandArgs(FALSE)&&Sys.getenv("LD_PRELOAD")==""&&
    all(Sys.getenv(c("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"))=="1"),
    "exact Muscat R4.6 vanilla one-thread runtime required")
  blas <- unname(extSoftVersion()[["BLAS"]])
  q(identical(normalizePath(blas,mustWork=TRUE),normalizePath(file.path(R.home("lib"),"libRblas.so"),mustWork=TRUE)),
    "bundled BLAS required")
  q2_limits(list(logical_cpu=27L,max_cpu_seconds=s$limits$cpu_seconds,
    max_wall_seconds=s$limits$wall_term_seconds+1,
    max_memory_bytes=s$limits$address_space_bytes,max_output_bytes=s$limits$output_bytes))
  timeout <- mqa_timeout_ancestor(s$limits$wall_term_seconds)
  before <- runtime_ic_snapshot()
  files <- mqa_runtime_paths();pins <- vapply(s$runtime_files,mqa_pin,character(1L),max_bytes=256*1024^2)
  q(!anyDuplicated(pins)&&setequal(pins,files),"complete exact runtime/library/package byte inventory required")
  mqa_pin(s$native_rng_source,4*1024^2)
  q(identical(s$native_rng_source$sha256,"6ef2c5d552c087cd57e0ef49386e01e0174b40433e4ad8d572461b20c958450e"),
    "exact native R4.6 RNG source required")
  list(R=as.character(getRversion()),BLAS=blas,logical_cpu=27L,timeout=timeout,
    namespaces=sort(loadedNamespaces()),runtime_files_verified=length(files),
    runtime_file_sha256=mqa_hash(s$runtime_files),
    observational_os_state_before=before$observational_os_state,
    observational_os_state_after=runtime_ic_snapshot()$observational_os_state,
    observation_role=before$observation_role,SSSD_cache_live_byte_equality_required=FALSE,
    all_other_software_packages_libraries_mappings_and_model_inputs_byte_pinned=TRUE)
}

mqa_verify_prepared <- function(s,root) {
  q <- mqa_require
  q(is.list(s$prepared_payload)&&is.list(s$prepared_derivation)&&is.list(s$prepared_manifest),
    "MISSING_AUTHENTIC_OBSERVED_PREFIX_REDUCTION: trusted preparation required")
  mp <- mqa_pin(s$prepared_manifest,1024^2);base <- dirname(mp)
  q(!startsWith(base,paste0(root,"/")),"prepared inputs must be external immutable evidence")
  m <- read.csv(mp,stringsAsFactors=FALSE)
  q(identical(names(m),c("relative_path","size_bytes","sha256","role"))&&nrow(m)==2L&&
    !anyDuplicated(m$relative_path)&&setequal(m$relative_path,c("observed_prefix_payload.rds","derivation.json"))&&
    setequal(m$role,c("truth_free_original_observed_prefix","authenticated_prefix_derivation")),
    "exact two-file truth-free preparation inventory required")
  for(k in c("prepared_payload","prepared_derivation")) {
    p <- mqa_pin(s[[k]],64*1024^2);at <- match(basename(p),m$relative_path)
    q(!is.na(at)&&identical(dirname(p),base)&&m$size_bytes[at]==s[[k]]$size_bytes&&
      identical(m$sha256[at],s[[k]]$sha256),"prepared input manifest binding differs")
  }
  q(identical(m$role[m$relative_path=="observed_prefix_payload.rds"],"truth_free_original_observed_prefix")&&
    identical(m$role[m$relative_path=="derivation.json"],"authenticated_prefix_derivation"),"prepared role relabelling")
  q(setequal(list.files(base,all.files=TRUE,no..=TRUE),c(m$relative_path,basename(mp))),
    "prepared namespace contains unmanifested or failed artifacts")
  a <- s$prepared_source
  q(is.list(a)&&mqa_hex(a$source_commit,40)&&mqa_hex(a$source_tree,40)&&
    identical(mqa_git(root,c("rev-parse",paste0(a$source_commit,"^{tree}"))),a$source_tree)&&
    identical(digest::digest(mqa_git_blob(root,a$source_commit,"scripts/mq_array_qualification.R"),
      algo="sha256",serialize=FALSE),a$reducer_sha256),"authentic preparation source/reducer blob required")
  derivation <- jsonlite::read_json(s$prepared_derivation$path,simplifyVector=FALSE)
  mqa_derivation_metadata(derivation,s$original_unit,s)
  original<-jsonlite::read_json(mqa_pin(s$original_unit_contract,1024^2),simplifyVector=FALSE)
  q(mqa_metadata_equal(derivation$original_asset_path_bridge,mqa_original_unit_bridge(s$original_unit,original)),
    "prepared derivation lost the authenticated original-to-materialized path bridge")
  q(identical(derivation$payload_sha256,s$prepared_payload$sha256)&&
    derivation$payload_size_bytes==s$prepared_payload$size_bytes&&
    identical(a$reducer_sha256,unname(tools::sha256sum(file.path(root,a$reducer_relative_path)))),
    "prepared payload bytes are not bound to this exact reviewed reducer")
  purpose <- jsonlite::read_json(mqa_pin(s$prepared_purpose,1024^2),simplifyVector=FALSE)
  mqa_preparation_scope(purpose)
  q(identical(s$prepared_purpose$sha256,a$purpose_contract_sha256)&&
    identical(purpose$source_commit,a$source_commit)&&identical(purpose$source_tree,a$source_tree)&&
    mqa_metadata_equal(purpose$original_unit,s$original_unit)&&identical(purpose$output_root,base),
    "authentic separate preparation purpose does not bind this exact prefix producer")
  old_root <- sub("/docs/reproducibility/integrated_forecast_transition_sources_20261031.csv$","",purpose$source_manifest$path)
  native <- read.csv(s$source_manifest$path,stringsAsFactors=FALSE)
  expected_sources <- file.path(old_root,mqa_required_sources(native$path))
  q(!identical(old_root,purpose$source_manifest$path)&&
    setequal(vapply(purpose$source_files,`[[`,character(1L),"path"),expected_sources)&&
    mqa_metadata_equal(purpose$source_manifest[c("size_bytes","sha256")],s$source_manifest[c("size_bytes","sha256")]),
    "complete prepared-producer source closure differs")
  for(p in purpose$source_files) {
    rel <- substring(p$path,nchar(old_root)+2L);blob <- mqa_git_blob(root,a$source_commit,rel)
    q(length(blob)==p$size_bytes&&identical(digest::digest(blob,algo="sha256",serialize=FALSE),p$sha256),
      "prepared producer transitive Git source differs")
  }
  # No raw fixture/design deserialization occurs here or in the driver.
  objects <- readRDS(s$prepared_payload$path)
  mqa_validate_derivation(objects,derivation,s$original_unit,s)
  list(objects=objects,derivation=derivation,prepared_bytes=sum(m$size_bytes)+file.info(mp)$size)
}
mqa_cdf_rows <- function(y,q,tau) {
  mqa_require(is.numeric(tau)&&length(tau)>=2L&&all(is.finite(tau))&&
    min(tau)>0&&max(tau)<1&&all(diff(tau)>0),"valid common CDF probability grid required")
  mqa_require(is.matrix(q)&&is.numeric(q)&&nrow(q)>0L&&ncol(q)==length(tau)&&
    all(is.finite(q))&&all(q[,-1L,drop=FALSE]>=q[,-ncol(q),drop=FALSE])&&
    is.numeric(y)&&length(y)>0L&&!anyNA(y),"ordered path-specific CDF input required")
  B <- nrow(q);K <- ncol(q);out <- matrix(0,B,length(y))
  for(j in seq_along(y)) {
    index <- rowSums(q<=y[j]);v <- as.numeric(index==K);rows <- which(index>0L&index<K)
    if(length(rows)) {
      k <- index[rows];lo <- q[cbind(rows,k)];hi <- q[cbind(rows,k+1L)]
      v[rows] <- tau[k]+(tau[k+1L]-tau[k])*(y[j]-lo)/(hi-lo)
    }
    mqa_require(all(is.finite(v))&&all(v>=0&v<=1),"invalid individual CDF contribution")
    out[,j] <- v
  };out
}
mqa_rng <- function()list(kind=RNGkind(),present=exists(".Random.seed",.GlobalEnv,inherits=FALSE),
  seed=if(exists(".Random.seed",.GlobalEnv,inherits=FALSE))get(".Random.seed",.GlobalEnv)else NULL)
mqa_parity_ids <- function(s,candidates_frozen,split_passed) {
  mqa_require(is.logical(candidates_frozen)&&length(candidates_frozen)==1L&&!is.na(candidates_frozen)&&
    is.logical(split_passed)&&length(split_passed)==1L&&!is.na(split_passed)&&
    (candidates_frozen||!split_passed),"invalid prospective parity phase")
  ids <- as.integer(unlist(s$parity_path_ids))
  if(!candidates_frozen)ids[ids<=65536]else if(split_passed)ids[ids>65536]else integer()
}
