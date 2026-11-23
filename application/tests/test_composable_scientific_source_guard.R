#!/usr/bin/env Rscript

local({
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else {
    arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
    normalizePath(file.path(dirname(sub("^--file=", "", arg)), "..", ".."))
  }
  final_manifest <- file.path(root, "docs/reproducibility",
    "joint_qdesn_superfinal_al_kernel_rerun_sources_20261123.csv")
  if (file.exists(final_manifest)) {
    env <- new.env(parent = baseenv())
    sys.source(file.path(root, "scripts/joint_superfinal_final_source_guard.R"),
      envir = env)
    checks <- env$app_check_joint_superfinal_final_sources(root)
    stopifnot(length(attr(checks, "final_authorized_paths")) == 8L)
    cat(sprintf(paste0("COMPOSABLE_SCIENTIFIC_SOURCE_GUARD_PASS checks=%d ",
      "mutation_rejections=8 production_runs=0 final_overlay=TRUE\n"),
      length(checks)))
    return(invisible(NULL))
  }
  env <- new.env(parent = baseenv())
  sys.source(file.path(root, "scripts/composable_scientific_source_guard.R"),
    envir = env)
  constants <- env$app_composable_source_constants()
  manifest <- read.csv(file.path(root, constants$joint_manifest),
    colClasses = "character", check.names = FALSE, stringsAsFactors = FALSE)
  checks <- env$app_check_composable_scientific_sources(root)
  stopifnot(
    length(attr(checks, "transition_authorized_additions")) == 7L,
    length(attr(checks, "joint_authorized_paths")) == 62L,
    length(attr(checks, "authorized_additions")) == 69L)

  rejected <- 0L
  reject <- function(expr) {
    error <- tryCatch({ force(expr); NULL }, error = identity)
    stopifnot(inherits(error, "error"))
    rejected <<- rejected + 1L
  }
  reject(env$app_check_composable_scientific_sources(root,
    joint_manifest_sha256 = strrep("0", 64L)))
  bad <- manifest[-1L, , drop = FALSE]
  reject(env$app_joint_correction_source_structure(bad))
  bad <- rbind(manifest, manifest[1L, , drop = FALSE])
  reject(env$app_joint_correction_source_structure(bad))
  bad <- manifest
  bad$role[[1L]] <- "broad_edit_permission"
  reject(env$app_joint_correction_source_structure(bad))
  bad <- manifest
  bad$path[[1L]] <- bad$path[[2L]]
  bad <- bad[order(bad$path), , drop = FALSE]
  reject(env$app_joint_correction_source_structure(bad))
  bad <- manifest
  bad$mode[[1L]] <- "100600"
  reject(env$app_joint_correction_source_structure(bad))
  bad <- manifest
  bad$sha256[[1L]] <- "missing"
  reject(env$app_joint_correction_source_structure(bad))
  bad <- manifest
  bad$blob[[1L]] <- "missing"
  reject(env$app_joint_correction_source_structure(bad))
  bad <- manifest
  bad$sha256[[1L]] <- strrep("0", 64L)
  reject(env$app_joint_correction_source_bytes(manifest, bad))

  cat(sprintf(paste0("COMPOSABLE_SCIENTIFIC_SOURCE_GUARD_PASS checks=%d ",
    "mutation_rejections=%d production_runs=0\n"), length(checks), rejected))
})
