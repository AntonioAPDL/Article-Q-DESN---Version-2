# Original opt-in generated-test candidate. No compilation, discovery, source
# authentication, scientific execution or production permission is implicit.
mqk_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("MQ native key candidate: ",why),call.=FALSE)
  invisible(TRUE)
}

mqk_load_candidate <- function(path, expected_sha256) {
  mqk_require(identical(as.character(getRversion()),"4.6.0") &&
    requireNamespace("digest",quietly=TRUE) &&
    identical(as.character(utils::packageVersion("digest")),"0.6.39"),
    "candidate requires declared R4.6.0/digest0.6.39 semantics")
  mqk_require(identical(get(".hasNoSharing",asNamespace("digest"))(),FALSE) &&
    identical(get("set_skip",asNamespace("digest"))(as.raw(1:20),FALSE),14),
    "digest serialization/sharing/header-skip semantics changed")
  mqk_require(is.character(path) && length(path)==1L && !is.na(path) &&
    startsWith(path,"/") && file.exists(path) && !dir.exists(path) &&
    !nzchar(Sys.readlink(path)) && identical(path,normalizePath(path,mustWork=TRUE)) &&
    file.info(path)$size<=8*1024^2 && is.character(expected_sha256) &&
    length(expected_sha256)==1L && !is.na(expected_sha256) &&
    grepl("^[0-9a-f]{64}$",expected_sha256) &&
    identical(digest::digest(file=path,algo="sha256",serialize=FALSE),expected_sha256),
    "explicit existing candidate DLL and matching SHA256 required")
  path <- normalizePath(path,mustWork=TRUE)
  dll <- dyn.load(path,local=TRUE,now=TRUE)
  entries <- getDLLRegisteredRoutines(dll)$.Call
  mqk_require(identical(dll[["dynamicLookup"]],FALSE) &&
    identical(names(entries),"mq_key_hash_batch") &&
    identical(entries[[1L]]$numParameters,4L) &&
    identical(digest::digest(file=path,algo="sha256",serialize=FALSE),expected_sha256),
    "candidate registration, symbol arity or post-load SHA changed")
  symbol <- getNativeSymbolInfo("mq_key_hash_batch",PACKAGE=dll)
  structure(list(dll=dll,symbol=symbol,path=path,sha256=expected_sha256,
    source_runtime_authenticated=FALSE,numerical_accuracy_qualified=FALSE,
    production_authorized=FALSE),class="mq_native_key_candidate")
}

mqk_candidate_uniforms <- function(backend,rng_namespace,draw_id,origin_id,inner_ids,H,
    rng_proof,audit=FALSE) {
  req <- mqk_require
  req(inherits(backend,"mq_native_key_candidate") &&
    identical(backend$production_authorized,FALSE) &&
    identical(backend$source_runtime_authenticated,FALSE),"explicit nonauthorizing candidate required")
  req(exists("app_iqf_mqb_rng_proof",mode="function"),"load the unchanged RNG reference helpers first")
  app_iqf_mqb_rng_proof(rng_proof)
  identities <- list(rng_namespace,draw_id,origin_id)
  req(all(vapply(identities,function(x)is.character(x)&&length(x)==1L&&!is.na(x)&&
    !is.object(x)&&nzchar(x)&&nchar(x,type="bytes")<=1048576,logical(1L))),
    "plain nonempty scalar identities within the explicit byte bound required")
  req(is.numeric(inner_ids)&&!is.object(inner_ids)&&length(inner_ids)>=1L&&
    all(is.finite(inner_ids))&&all(inner_ids>=1&inner_ids<=.Machine$integer.max)&&
    all(inner_ids==as.integer(inner_ids))&&!anyDuplicated(inner_ids)&&
    is.numeric(H)&&!is.object(H)&&length(H)==1L&&is.finite(H)&&
    H>=1&H<=.Machine$integer.max&&H==as.integer(H),"distinct positive path IDs and finite integer horizon required")
  req(length(inner_ids)<=.Machine$integer.max/as.double(H),"matrix dimensions overflow")
  req(is.logical(audit)&&length(audit)==1L&&!is.na(audit)&&
    (!audit||length(inner_ids)*as.double(H)<=1024),"explicit audit bounded to1024 tuples required")
  # vapply produces ordinary materialized character vectors, preserving each
  # scalar's R as.character formatting and encoding, without identity classes.
  inner <- vapply(seq_along(inner_ids),function(i)as.character(inner_ids[i]),"")
  horizons <- vapply(seq_len(as.integer(H)),function(h)as.character(h),"")
  key <- list(version=1L,scientific_identity=as.character(rng_namespace),
    draw=as.character(draw_id),origin=as.character(origin_id),inner="",horizon="",purpose="response")
  value <- .Call(backend$symbol,key,inner,horizons,audit)
  req(identical(dim(value$uniforms),c(as.integer(length(inner_ids)),as.integer(H)))&&
    all(is.finite(value$uniforms))&&all(value$uniforms>0&value$uniforms<1),
    "native candidate returned an invalid uniform matrix")
  if (audit) value else value$uniforms
}

# Explicit candidate route: clone only the function environment, not any model
# or input. Existing canonical helpers/defaults remain untouched. This is not
# source/ABI qualification or production dispatch.
mqk_candidate_arrays <- function(backend,adapter,draw_id,origin_id,inner_ids,
    collect_coherence=TRUE,crossing_tolerance=0,include_trace=FALSE) {
  mqk_require(inherits(adapter,"app_iqf_mq_batch_adapter") &&
    identical(adapter$rng_mode,"r46_first_step_qualified") &&
    all(inner_ids<=adapter$inner_paths),"explicit existing first-step-mode batch adapter required")
  kernel <- app_iqf_mqb_paths_context
  private <- new.env(parent=environment(kernel))
  private$app_iqf_mqb_uniforms <- function(rng_namespace,draw_id,origin_id,inner_ids,H,
      rng_mode,rng_proof) {
    mqk_require(identical(rng_mode,"r46_first_step_qualified"),"no RNG-mode substitution permitted")
    mqk_candidate_uniforms(backend,rng_namespace,draw_id,origin_id,inner_ids,H,rng_proof)
  }
  environment(kernel) <- private
  result <- kernel(adapter$batch_context,draw_id,origin_id,inner_ids,
    include_trace=include_trace,include_paths=FALSE,collect_coherence=collect_coherence,
    crossing_tolerance=crossing_tolerance)
  result$numerical_adapter <- "opt_in_unqualified_native_Rserialize_SHA_candidate_v1"
  result
}
