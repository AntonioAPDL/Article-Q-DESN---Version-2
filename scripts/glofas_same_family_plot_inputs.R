# Truth-free extraction only. Never call a saved feature builder or open a sidecar.
gsc_plot_input_tables <- function(design) {
  q <- gsc_require;origin <- as.Date("2022-12-25")
  q(is.list(design)&&identical(design$future_truth_policy,
    "physically_excluded_from_fit_objects_scoring_sidecar_only")&&
    identical(design$ensemble_member_weight_policy,"unit_member_likelihood_v1")&&
    identical(design$family_transition_contract$schema_version,"glofas_family_transition_v1")&&
    identical(design$family_transition_contract$future_truth_used_in_fit,FALSE)&&
    isTRUE(design$two_block_design),"authenticated truth-free same-family design required")
  forbidden <- c("future_truth","future_y_truth","scoring_truth","scoring_sidecar","usgs_future")
  blocks <- list(design,design$latent_data,design$future_context,design$future_context$latent_data)
  for(b in blocks)q(is.list(b)&&!any(forbidden %in% names(b)),"unsafe embedded truth field; extraction blocked")
  for(data in list(design$latent_data,design$future_context$latent_data)) {
    q(identical(data$future_truth_policy,"physically_excluded_from_fit_objects_scoring_sidecar_only"),
      "nested truth boundary differs")
    for(name in c("historical_panel","y_history","g_retro")) {
      p <- data[[name]]
      q(is.data.frame(p)&&"target_date" %in% names(p)&&!anyNA(as.Date(p$target_date))&&
        all(as.Date(p$target_date)<=origin),"historical source contains post-origin rows")
    }
    p <- data$g_ensemble
    truth <- intersect(c("y","y_raw","y_transformed","y_reference","usgs","usgs_raw","usgs_transformed"),names(p))
    q(is.data.frame(p)&&!any(vapply(p[truth],function(x)any(is.finite(as.numeric(x))),logical(1L))),
      "unsafe unredacted future USGS; extraction blocked")
  }
  history <- design$base_panel
  q(is.data.frame(history)&&all(c("target_date","y_transformed","g_transformed") %in% names(history))&&
    !anyNA(as.Date(history$target_date))&&all(as.Date(history$target_date)<=origin),
    "historical base panel is not pre-origin only")
  history <- history[,c("target_date","y_transformed","g_transformed")]
  history$target_date <- as.Date(history$target_date)
  history <- history[history$target_date>=origin-29,];history <- history[order(history$target_date),]
  q(nrow(history)==30L&&!anyDuplicated(history$target_date)&&
    identical(history$target_date,seq(origin-29,origin,by="day"))&&
    all(is.finite(c(history$y_transformed,history$g_transformed))),
    "thirty consecutive finite historical dates required; no interpolation permitted")
  issued <- design$latent_data$g_ensemble
  fields <- c("origin_date","target_date","horizon","member","g_transformed","ensemble_weight")
  q(all(fields %in% names(issued))&&nrow(issued)==1428L&&
    all(as.Date(issued$origin_date)==origin)&&all(issued$ensemble_weight==1),"authentic unit-weight issued members required")
  issued <- issued[order(issued$horizon,issued$member),fields]
  members <- issued[,c("target_date","horizon","member","g_transformed")]
  gsc_raw_rows(members) # Exact 28 dates, 51 original member identities; no reconstruction.
  other <- design$future_context$latent_data$g_ensemble
  q(isTRUE(all.equal(issued,other[order(other$horizon,other$member),fields],
    check.attributes=FALSE,tolerance=0)),"nested issued-member source differs")
  q(is.data.frame(design$future_key)&&identical(as.integer(design$future_key$horizon),1:28)&&
    identical(as.Date(design$future_key$target_date),gsc_dates()),"issued forecast window differs")
  list(history=history,issued_members=issued,raw_members=members)
}

gsc_extract_authorized <- function(s,collection,normal,check_source,expiry,contract_sha256) {
  q <- gsc_require
  # This must remain before any source-design hash/read or deserialization.
  gsc_validate_collection(collection,gsc_identity())
  q(identical(s$mode,"extract")&&isTRUE(s$allow_design_read)&&
    identical(s$allow_assembly,FALSE)&&identical(s$allow_scoring,FALSE)&&
    identical(s$allow_refit,FALSE)&&identical(s$allow_retuning,FALSE)&&identical(s$allow_publication,FALSE),
    "explicit truth-free extraction-only purpose required")
  q(identical(s$prepared_design_sha256,"193056d66ae9f004d909eab6161adcdc696b5243587f3bee74396def452381f3")&&
    setequal(names(s$design),c("path","size_bytes","sha256"))&&
    all(vapply(names(s$design),function(k)identical(s$design[[k]],normal$prepared_design[[k]]),logical(1L)))&&
    identical(s$design$sha256,s$prepared_design_sha256)&&
    identical(s$input_manifest$sha256,gsc_identity()$input_manifest_sha256),"frozen prepared design and input provenance required")
  manifest <- read.csv(gsc_pin(s$input_manifest,1024^2),stringsAsFactors=FALSE)
  at <- which(manifest$role=="truth_free_shared_design")
  q(length(at)==1L&&manifest$sha256[at]==s$design$sha256&&manifest$size_bytes[at]==s$design$size_bytes&&
    identical(normalizePath(file.path(dirname(dirname(s$input_manifest$path)),manifest$relative_path[at]),mustWork=FALSE),
      s$design$path),"design must be the exact truth-free role in the frozen input manifest")
  design_path <- gsc_pin(s$design,8*1024^3)
  design <- readRDS(design_path) # First and only design read, after sixteen accepted identities.
  tables <- gsc_plot_input_tables(design)
  rm(design)
  gsc_pin(s$design,8*1024^3);gsc_pin(s$input_manifest,1024^2);check_source()
  root <- normalizePath(getwd(),mustWork=TRUE);out <- s$output_root
  q(is.character(out)&&length(out)==1L&&startsWith(out,paste0(root,"/local_trackers/"))&&
    !file.exists(out)&&dir.exists(dirname(out))&&identical(normalizePath(dirname(out)),dirname(out))&&
    !grepl("(^|/)\\.\\.(/|$)",out)&&system2("git",c("check-ignore","--quiet","--",shQuote(out)))==0L,
    "fresh ignored extraction output required")
  q(expiry>Sys.time(),"extraction purpose expired")
  q(dir.create(out),"extraction output creation failed")
  for(pair in list(c("history","history.csv"),c("issued_members","issued_member_paths.csv"),c("raw_members","raw_members.csv")))
    write.csv(tables[[pair[1L]]],file.path(out,pair[2L]),row.names=FALSE)
  jsonlite::write_json(list(schema_version="glofas_same_family_raw_members_v1",
    source_design_sha256=s$design$sha256,artifact_sha256=unname(tools::sha256sum(file.path(out,"raw_members.csv"))),
    members=51L,horizons=28L,transform="log1p",future_truth_read=FALSE,
    history_rows=30L,history_start="2022-11-26",history_end="2022-12-25",
    source_fields=list(history=c("base_panel.target_date","base_panel.y_transformed","base_panel.g_transformed"),
      ensemble="latent_data.g_ensemble"),synthetic_members_created=0L,builder_calls=0L,model_calls=0L),
    file.path(out,"raw_member_derivation.json"),pretty=TRUE,auto_unbox=TRUE,digits=17)
  for(b in s$source_files)gsc_pin(b,1024^2)
  cpu <- sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])
  q(cpu<=s$limits$cpu_seconds&&expiry>Sys.time(),"complete extraction CPU/wall budget exceeded")
  check_source()
  jsonlite::write_json(list(schema_version="glofas_same_family_extraction_receipt_v1",
    status="TRUTH_FREE_PLOT_INPUTS_EXTRACTED_NOT_SCIENTIFIC_RELEASE",source_commit=s$source_commit,
    source_tree=s$source_tree,contract_sha256=contract_sha256,prepared_design=s$design,
    input_manifest=s$input_manifest,producer_count=16L,producer_target=gsc_identity(),
    members=51L,issued_rows=1428L,history_rows=30L,future_truth_read=FALSE,scoring_calls=0L,
    builder_calls=0L,new_fits=0L,article_publication_authorized=FALSE,CPU_seconds=cpu),
    file.path(out,"EXTRACTION_DECISION.json"),pretty=TRUE,auto_unbox=TRUE,digits=17)
  files <- list.files(out,full.names=TRUE)
  q(sum(file.info(files)$size)+65536<s$limits$output_bytes,"extraction output budget exceeded")
  write.csv(data.frame(relative_path=basename(files),size_bytes=file.info(files)$size,
    sha256=unname(tools::sha256sum(files))),file.path(out,"artifact_manifest.csv"),row.names=FALSE)
  cat("GLOFAS_TRUTH_FREE_PLOT_INPUTS_EXTRACTED_NOT_SCIENTIFIC_RELEASE\n")
  invisible(tables)
}
