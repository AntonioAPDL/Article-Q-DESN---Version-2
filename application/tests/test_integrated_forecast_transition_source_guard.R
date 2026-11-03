#!/usr/bin/env Rscript
# Source-only contract mutations; no production fitting, forecasting or dispatch.
local({
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else {
    arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
    normalizePath(file.path(dirname(sub("^--file=", "", arg)), "..", ".."))
  }
  source(file.path(root, "scripts/integrated_forecast_transition_source_guard.R"), local = TRUE)
  cfg <- app_transition_source_paths()
  manifest <- read.csv(file.path(root, cfg$manifest), colClasses = "character", check.names = FALSE)
  pin <- unname(tools::sha256sum(file.path(root, cfg$manifest))[[1L]])
  checks <- app_check_integrated_forecast_transition_sources(root, pin)
  stopifnot(length(attr(checks, "authorized_additions")) == 7L)
  rejected <- 0L
  reject <- function(expr) {
    err <- tryCatch({force(expr); NULL}, error = identity)
    stopifnot(inherits(err, "error"))
    rejected <<- rejected + 1L
  }
  bad <- manifest[-1L, ]; reject(app_transition_source_structure(bad))
  bad <- rbind(manifest, manifest[1L, ]); reject(app_transition_source_structure(bad))
  bad <- manifest; bad$role[[1L]] <- "broad_edit_permission"; reject(app_transition_source_structure(bad))
  bad <- manifest; bad$path[[1L]] <- "application/R/00_packages.R"; reject(app_transition_source_structure(bad))
  bad <- manifest; bad$mode[[1L]] <- "100755"; reject(app_transition_source_structure(bad))
  bad <- manifest; bad$sha256[[1L]] <- "missing"; reject(app_transition_source_structure(bad))
  bad <- manifest; bad$blob[[1L]] <- "missing"; reject(app_transition_source_structure(bad))
  for (i in seq_len(nrow(manifest))) {
    bad <- manifest; bad$sha256[[i]] <- strrep("0", 64L)
    reject(app_transition_source_bytes(manifest, bad))
  }
  reject(app_check_integrated_forecast_transition_sources(root, strrep("0", 64L)))
  cat(sprintf("INTEGRATED_TRANSITION_SOURCE_GUARD_PASS checks=%d mutation_rejections=%d production_runs=0\n",
    length(checks), rejected))
})
