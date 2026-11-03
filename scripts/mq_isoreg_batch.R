# Explicit generated-only candidate; never loaded by a canonical worker.
mqi_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("MQ isoreg batch candidate: ", why), call. = FALSE)
  invisible(TRUE)
}
mqi_context <- function(scope) {
  mqi_require(identical(scope, "generated_fixture_only"),
    "production/native-worker ABI, source and runtime qualification remain unapproved")
}
mqi_contract <- function() list(schema_version = "mq_isoreg_batch_candidate_v1",
  scope = "generated_fixture_only", algorithm = "native_double_cumulative_convex_minorant",
  weights = "equal_per_probability_level_not_probability_spacing", sorting = FALSE,
  ordered_rows = "unchanged_before_cumulative_sum", tie_rule = "strict_less_earliest_endpoint",
  native_reference = "R_4.6.0_stats_isoreg_conditional_on_row_crossing",
  production_authorized = FALSE, source_authentication_provided = FALSE,
  authentic_full_unit_speedup_demonstrated = FALSE, default_backend_changed = FALSE)
mqi_load <- function(path, sha256, scope = "NOT_ADMITTED") {
  mqi_context(scope)
  mqi_require(is.character(path) && length(path) == 1L && startsWith(path, "/") &&
    file.exists(path) && identical(normalizePath(path, mustWork = TRUE), path) &&
    !nzchar(Sys.readlink(path)) && file.info(path)$size > 0 && file.info(path)$size < 64 * 1024^2 &&
    is.character(sha256) && length(sha256) == 1L && grepl("^[a-f0-9]{64}$", sha256) &&
    identical(unname(tools::sha256sum(path)), sha256), "pinned bounded generated DLL required")
  dll <- dyn.load(path, local = TRUE, now = TRUE)
  loaded <- FALSE
  on.exit(if (!loaded) dyn.unload(path), add = TRUE)
  mqi_require(identical(dll[["dynamicLookup"]], FALSE), "registered native routines required")
  symbol <- getNativeSymbolInfo("mqi_project", PACKAGE = dll)
  mqi_require(inherits(symbol, "NativeSymbolInfo") && identical(symbol$numParameters, 1L),
    "one-argument registered native entry required")
  loaded <- TRUE
  structure(list(dll = dll, symbol = symbol, sha256 = sha256, scope = scope),
    class = "mq_isoreg_batch_generated_v1")
}
mqi_project <- function(q, candidate, scope = "NOT_ADMITTED") {
  mqi_context(scope)
  mqi_require(inherits(candidate, "mq_isoreg_batch_generated_v1") &&
    identical(candidate$scope, "generated_fixture_only") &&
    inherits(candidate$symbol, "NativeSymbolInfo"), "explicit generated candidate handle required")
  mqi_require(is.matrix(q) && typeof(q) %in% c("double", "integer") && nrow(q) >= 1L && nrow(q) <= 1000000L &&
    ncol(q) >= 2L && ncol(q) <= 64L, "finite real matrix with 2-64 levels required")
  if (typeof(q) != "double") storage.mode(q) <- "double"
  .Call(candidate$symbol, q)
}
