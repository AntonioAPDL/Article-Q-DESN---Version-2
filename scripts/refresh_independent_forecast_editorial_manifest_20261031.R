#!/usr/bin/env Rscript

# Refresh live document provenance only. Immutable historical receipts,
# scientific CSVs, table derivatives and PDFs are neither written nor regenerated.
app_ind_editorial_baseline <- "8b28ba51176c25624b638fac54fce2699b9af078"
app_ind_editorial_original_manifest_sha256 <-
  "687d5531300c8c42eb8a2499ad88f3adbb5d3aa318e6b50b277b282db1d30b1c"
app_ind_editorial_receipt_path <- "tables/independent_forecast_300_500_article_manifest_v1.json"
app_ind_editorial_refresh_path <- "scripts/refresh_independent_forecast_editorial_manifest_20261031.R"
app_ind_editorial_document_paths <- c("main.tex", "qdesn-supplement.tex")

app_ind_editorial_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("IND_EDITORIAL_MANIFEST_FAILED:", message), call. = FALSE)
}

app_ind_editorial_refresh_plan <- function(baseline, current, hash_file, refresher_sha256) {
  require <- app_ind_editorial_require
  docs <- app_ind_editorial_document_paths
  require(identical(baseline$schema, "independent-forecast-300-500-article-v1") &&
    identical(baseline$authority_id, "independent_forecast_300_primary_500_sensitivity_v1") &&
    all(docs %in% names(baseline$sources)), "original reporting schema and document roles")
  require(identical(setdiff(names(current), "editorial_source_refresh"), names(baseline)),
    "only the named editorial provenance field may be added")
  unchanged <- current
  unchanged$editorial_source_refresh <- NULL
  # Replace only the two document digests before comparing the entire remaining
  # structure. No scientific pin, output pin, reporting policy or cardinality
  # can be changed by this refresher.
  unchanged$sources[docs] <- baseline$sources[docs]
  require(identical(unchanged, baseline),
    "all noneditorial sources, outputs, scientific policy and counts remain identical")
  paths <- c(setdiff(names(baseline$sources), docs), names(baseline$outputs))
  expected_hashes <- c(baseline$sources[setdiff(names(baseline$sources), docs)], baseline$outputs)
  for (path in paths) {
    require(identical(hash_file(path), expected_hashes[[path]]),
      paste("immutable source/output digest", path))
  }
  provenance <- function(document_hashes) list(
    schema = "independent-forecast-editorial-source-refresh-v1",
    baseline_commit = app_ind_editorial_baseline,
    original_manifest_sha256 = app_ind_editorial_original_manifest_sha256,
    updated_paths = as.list(docs),
    original_document_sha256 = baseline$sources[docs],
    updated_document_sha256 = document_hashes,
    refresher = app_ind_editorial_refresh_path,
    refresher_sha256 = refresher_sha256,
    scientific_outputs_regenerated = FALSE,
    scientific_values_changed = FALSE,
    fits_launched = 0L, forecasts_launched = 0L)
  if (!is.null(current$editorial_source_refresh)) {
    require(identical(current$editorial_source_refresh, provenance(current$sources[docs])),
      "previous refresh is authentic and has no broader permissions")
  } else {
    require(identical(current, baseline), "unrefreshed receipt is the exact original structure")
  }
  actual <- lapply(docs, hash_file)
  names(actual) <- docs
  require(all(vapply(actual, function(value) {
    is.character(value) && length(value) == 1L && grepl("^[a-f0-9]{64}$", value)
  }, logical(1L))), "current document digests are complete")
  result <- baseline
  result$sources[docs] <- actual
  result$editorial_source_refresh <- provenance(actual)
  result
}

app_ind_editorial_refresh <- function(root, refresh = FALSE) {
  root <- normalizePath(root, mustWork = TRUE)
  sha <- function(path) unname(tools::sha256sum(file.path(root, path))[[1L]])
  require <- app_ind_editorial_require
  for (tip in c("HEAD", "refs/remotes/origin/main")) {
    code <- system2("git", c("-C", shQuote(root), "merge-base", "--is-ancestor",
      app_ind_editorial_baseline, tip), stdout = FALSE, stderr = FALSE)
    require(identical(code, 0L), paste("approved baseline ancestry", tip))
  }
  original <- system2("git", c("-C", shQuote(root), "show",
    shQuote(paste0(app_ind_editorial_baseline, ":", app_ind_editorial_receipt_path))),
    stdout = TRUE, stderr = TRUE)
  require(is.null(attr(original, "status")), "original live receipt exists at fixed baseline")
  # Git's text output drops the final newline; restore it before digesting the
  # exact original JSON bytes. This is a fixed commit lookup, not an object search.
  original_text <- paste0(paste(original, collapse = "\n"), "\n")
  require(identical(digest::digest(original_text, algo = "sha256", serialize = FALSE),
    app_ind_editorial_original_manifest_sha256), "original receipt byte identity")
  baseline <- jsonlite::fromJSON(original_text, simplifyVector = FALSE)
  current <- jsonlite::read_json(file.path(root, app_ind_editorial_receipt_path),
    simplifyVector = FALSE)
  # Refuse to certify a different scientific or text scope merely by refreshing
  # hashes. Existing scientific/source invariance and the exact PriceFM text
  # authorization remain independent required gates.
  style <- new.env(parent = baseenv())
  style$tail <- utils::tail
  sys.source(file.path(root, "scripts/check_qdesn_statistical_language_revision.R"),
    envir = style)
  style$app_check_statistical_language_revision(root)
  exposition <- new.env(parent = baseenv())
  sys.source(file.path(root, "scripts/check_forecast_application_exposition_20261031.R"),
    envir = exposition)
  exposition$app_check_forecast_application_exposition(root)
  result <- app_ind_editorial_refresh_plan(baseline, current, sha,
    sha(app_ind_editorial_refresh_path))
  if (isTRUE(refresh)) {
    # This is generated metadata, not a figure/table/model regeneration.
    jsonlite::write_json(result, file.path(root, app_ind_editorial_receipt_path),
      auto_unbox = TRUE, pretty = TRUE)
    observed <- jsonlite::read_json(file.path(root, app_ind_editorial_receipt_path),
      simplifyVector = FALSE)
    require(identical(observed, result), "written metadata readback")
  } else {
    require(identical(current, result), "live document metadata needs --refresh")
  }
  cat(sprintf(paste0("IND_EDITORIAL_MANIFEST_%s sources=%d outputs=%d ",
    "updated_documents=2 scientific_files_regenerated=0 fits_launched=0 forecasts_launched=0\n"),
    if (refresh) "REFRESHED" else "CHECK_PASS", length(baseline$sources), length(baseline$outputs)))
  invisible(result)
}

if (sys.nframe() == 0L) {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
  script <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  args <- commandArgs(TRUE)
  if (length(args) > 1L || (length(args) == 1L && !args %in% c("--check", "--refresh"))) {
    stop("Usage: Rscript refresh_independent_forecast_editorial_manifest_20261031.R [--check|--refresh]")
  }
  app_ind_editorial_refresh(normalizePath(file.path(dirname(script), "..")),
    refresh = identical(args, "--refresh"))
}
