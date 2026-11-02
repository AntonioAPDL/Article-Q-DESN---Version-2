#!/usr/bin/env Rscript
# Separately authorized archive-to-prefix isolation. This actor is NOT the
# qualifier and honestly records the complete archive deserializations.
source("scripts/mq_array_qualification.R",local=TRUE)
mqa_preparation_main <- function(args=commandArgs(TRUE)) {
  if(identical(args,"--help")) {
    cat("Usage: Rscript --vanilla scripts/prepare_mq_array_observed_prefix.R --contract FILE --sha256 SHA --execute\n")
    return(invisible(NULL))
  }
  q <- mqa_require
  q(length(args)==5L&&identical(args[c(1,3,5)],c("--contract","--sha256","--execute")),
    "exact separate preparation contract/hash/execute arguments required")
  for(p in c("digest","jsonlite","tools","compiler"))q(requireNamespace(p,quietly=TRUE),paste("required package",p))
  cp <- normalizePath(args[2L],mustWork=TRUE);q2_regular(cp)
  q(file.info(cp)$size<=1024^2&&identical(unname(tools::sha256sum(cp)),args[4L]),"preparation purpose bytes changed")
  s <- jsonlite::read_json(cp,simplifyVector=FALSE);mqa_preparation_scope(s)
  root <- normalizePath(getwd(),mustWork=TRUE)
  q(!startsWith(cp,paste0(root,"/")),"external preparation purpose required")
  expiry <- q2_time(s$expires_utc);q(!is.na(expiry)&&expiry>Sys.time()+120,"full preparation lifetime required")
  runtime <- mqa_runtime_guard(s);mqa_source_guard(s,root)
  historical <- jsonlite::read_json(mqa_pin(s$baseline_contract,1024^2),simplifyVector=FALSE)
  original <- jsonlite::read_json(mqa_pin(s$original_unit_contract,1024^2),simplifyVector=FALSE)
  q(mqa_metadata_equal(s$original_unit,historical$original_unit)&&
    mqa_metadata_equal(s$original_unit_contract,historical$original_unit_contract),"authentic original unit/assets may not be substituted")
  unit<-s$original_unit;asset_bridge<-mqa_original_unit_bridge(unit,original)
  metadata <- q2_metadata(unit)
  output <- s$output_root;q2_regular(output)
  state <- normalizePath(file.path(Sys.getenv("HOME"),".local/state/qdesn_forecast_transition"),mustWork=TRUE)
  q(is.character(output)&&length(output)==1L&&startsWith(output,paste0(state,"/mq_array_prefix_preparation_"))&&
    identical(dirname(output),state)&&!file.exists(output),"fresh private external preparation namespace required")
  q(dir.create(output,mode="0700"),"preparation output creation failed")
  reads <- list(design=0L,fixture=0L,posterior=0L)
  tryCatch({
    # Deserialize only in this separately scoped actor. The immutable selector
    # below accesses f$y[1:11000], never future response values or callbacks.
    reads$design <- 1L;d <- readRDS(unit$assets$design$path)
    reads$fixture <- 1L;f <- readRDS(unit$assets$fixture$path)
    reads$posterior <- 1L;p <- read.csv(unit$assets$posterior$path,stringsAsFactors=FALSE)
    source("application/R/integrated_quantile_forecast.R",local=environment(q2_payloads))
    preparation <- list(source_commit=s$source_commit,source_tree=s$source_tree,
      purpose_contract_sha256=args[4L],reducer_relative_path="scripts/mq_array_qualification.R",
      reducer_sha256=unname(tools::sha256sum(file.path(root,"scripts/mq_array_qualification.R"))),
      trusted_original_byte_verification=TRUE,read_permission_scope="SEPARATE_TRUSTED_PREPARATION_NOT_QUALIFICATION",
      archive_design_deserializations=reads$design,archive_fixture_deserializations=reads$fixture,
      original_posterior_csv_reads=reads$posterior,future_response_values_consulted=FALSE,
      model_calls=0L,scoring_calls=0L,runtime_file_inventory_sha256=mqa_hash(s$runtime_files),
      source_invariance_argument="unchanged_Q2_fixed_prefix_selector_no_future_response_or_future_Z_access",
      synthetic_invariance_test="application/tests/test_mq_array_qualification.R",
      synthetic_invariance_test_sha256=unname(tools::sha256sum(file.path(root,"application/tests/test_mq_array_qualification.R"))))
    reduced <- mqa_reduce_original_payload(d,f,p,unit,preparation)
    reduced$derivation$original_asset_path_bridge<-asset_bridge
    rm(d,f,p);gc(FALSE)
    ss <- list(prepared_source=preparation)
    mqa_validate_derivation(reduced$objects,reduced$derivation,unit,ss)
    q2_metadata(unit);mqa_source_guard(s,root);mqa_runtime_guard(s)
    cpu <- sum(proc.time()[c("user.self","sys.self","user.child","sys.child")])
    q(cpu<=120&&expiry>Sys.time(),"complete preparation CPU/wall budget exceeded")
    payload <- file.path(output,"observed_prefix_payload.rds")
    q2_write(reduced$objects,payload,1024^2,s$limits$output_bytes)
    reduced$derivation$payload_sha256 <- unname(tools::sha256sum(payload))
    reduced$derivation$payload_size_bytes <- as.numeric(file.info(payload)$size)
    jsonlite::write_json(reduced$derivation,file.path(output,"derivation.json"),pretty=TRUE,auto_unbox=TRUE,digits=17)
    names <- c("observed_prefix_payload.rds","derivation.json")
    files <- file.path(output,names)
    write.csv(data.frame(relative_path=names,size_bytes=as.numeric(file.info(files)$size),
      sha256=unname(tools::sha256sum(files)),role=c("truth_free_original_observed_prefix","authenticated_prefix_derivation")),
      file.path(output,"input_manifest.csv"),row.names=FALSE)
    q(sum(file.info(list.files(output,full.names=TRUE))$size)+1024^2<s$limits$output_bytes,
      "complete preparation output cap exceeded")
    cat("TRUSTED_PREFIX_PREPARATION_COMPLETE_NOT_QUALIFICATION design_archive_deserializations=1 fixture_archive_deserializations=1 future_response_access=0 fits=0 scores=0\n")
    invisible(reduced$derivation)
  },error=function(e) {
    try(jsonlite::write_json(list(status="TRUSTED_PREPARATION_FAILED_NOT_QUALIFICATION",error=conditionMessage(e),
      source_commit=s$source_commit,purpose_contract_sha256=args[4L],archive_read_attempts=reads,
      production_authorized=FALSE),file.path(output,"failure.json"),pretty=TRUE,auto_unbox=TRUE),silent=TRUE)
    stop(e)
  })
}
if(sys.nframe()==0L)mqa_preparation_main()
