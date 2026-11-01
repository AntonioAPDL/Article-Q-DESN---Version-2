#!/usr/bin/env Rscript
# Pure receipt mutations; no scientific files, model work or historical writes.
local({
  if (exists("app_repo_root", mode = "function")) root <- app_repo_root() else {
    file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
    root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
  }
  source(file.path(root, "scripts/refresh_independent_forecast_editorial_manifest_20261031.R"),
    local = TRUE)
  original_text <- system2("git", c("-C", shQuote(root), "show",
    shQuote(paste0(app_ind_editorial_baseline, ":", app_ind_editorial_receipt_path))), stdout = TRUE)
  baseline <- jsonlite::fromJSON(paste(original_text, collapse = "\n"), simplifyVector = FALSE)
  sha <- function(path) unname(tools::sha256sum(file.path(root, path))[[1L]])
  script_sha <- sha(app_ind_editorial_refresh_path)
  good <- app_ind_editorial_refresh_plan(baseline, baseline, sha, script_sha)
  stopifnot(identical(good$outputs, baseline$outputs),
    identical(good$sources[setdiff(names(good$sources), app_ind_editorial_document_paths)],
      baseline$sources[setdiff(names(baseline$sources), app_ind_editorial_document_paths)]),
    identical(app_ind_editorial_refresh_plan(baseline, good, sha, script_sha), good))
  rejected <- 0L
  reject <- function(current, hash_file = sha) {
    error <- tryCatch({
      app_ind_editorial_refresh_plan(baseline, current, hash_file, script_sha)
      NULL
    }, error = identity)
    stopifnot(inherits(error, "error"))
    rejected <<- rejected + 1L
  }
  wrong <- paste(rep("0", 64L), collapse = "")
  altered <- baseline; altered$sources[["tables/independent_forecast_300_500_v1.csv"]] <- wrong
  reject(altered)
  altered <- baseline; altered$outputs[[names(altered$outputs)[[1L]]]] <- wrong
  reject(altered)
  altered <- baseline; altered$sources[["unapproved/main.tex"]] <- wrong
  reject(altered)
  altered <- baseline; altered$fits_launched <- 1L; reject(altered)
  altered <- baseline; altered$forecasts_launched <- 1L; reject(altered)
  altered <- baseline; altered$primary_cutoff <- 1000L; reject(altered)
  altered <- baseline; altered$authority_id <- "unapproved"; reject(altered)
  reject(baseline, function(path) if (identical(path, "tables/independent_forecast_300_500_v1.csv")) wrong else sha(path))
  output <- names(baseline$outputs)[[1L]]
  reject(baseline, function(path) if (identical(path, output)) wrong else sha(path))
  altered <- good; altered$editorial_source_refresh$scientific_outputs_regenerated <- TRUE; reject(altered)
  altered <- good; altered$editorial_source_refresh$updated_paths <- as.list(c(app_ind_editorial_document_paths, output)); reject(altered)
  altered <- good; altered$editorial_source_refresh$original_manifest_sha256 <- wrong; reject(altered)
  altered <- good; altered$editorial_source_refresh$updated_document_sha256[["main.tex"]] <- wrong; reject(altered)
  app_ind_editorial_refresh(root, refresh = FALSE)
  cat(sprintf("IND_EDITORIAL_MANIFEST_TEST_PASS expected_mutation_rejections=%d scientific_files_regenerated=0\n", rejected))
})
