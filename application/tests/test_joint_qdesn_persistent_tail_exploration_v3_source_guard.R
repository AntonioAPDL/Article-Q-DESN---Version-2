#!/usr/bin/env Rscript

local({
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else {
    arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
    normalizePath(file.path(dirname(sub("^--file=", "", arg)), "..", ".."))
  }
  env <- new.env(parent = baseenv())
  sys.source(file.path(root, "scripts/joint_persistent_tail_v3_source_guard.R"), envir = env)
  constants <- env$app_joint_pht3_source_constants()
  manifest <- read.csv(file.path(root, constants$extension_manifest),
    colClasses = "character", check.names = FALSE, stringsAsFactors = FALSE)
  checks <- env$app_check_joint_pht3_sources(root)
  stopifnot(length(attr(checks, "prior_authorized_paths")) == 13L,
    length(attr(checks, "extension_authorized_paths")) == 10L,
    length(attr(checks, "authorized_paths")) == 23L)
  rejected <- 0L
  reject <- function(expr) {
    error <- tryCatch({ force(expr); NULL }, error = identity)
    stopifnot(inherits(error, "error")); rejected <<- rejected + 1L
  }
  reject(env$app_check_joint_pht3_sources(root, manifest_sha256 = strrep("0", 64L)))
  reject(env$app_joint_pht3_source_structure(manifest[-1L, , drop = FALSE]))
  reject(env$app_joint_pht3_source_structure(rbind(manifest, manifest[1L, ])))
  bad <- manifest; bad$role[[1L]] <- "broad_permission"
  reject(env$app_joint_pht3_source_structure(bad))
  bad <- manifest; bad$sha256[[1L]] <- strrep("0", 64L)
  reject(env$app_joint_pht3_source_bytes(manifest, bad))
  cat(sprintf("JOINT_PHT3_SOURCE_GUARD_PASS checks=%d mutation_rejections=%d production_runs=0\n",
    length(checks), rejected))
})
