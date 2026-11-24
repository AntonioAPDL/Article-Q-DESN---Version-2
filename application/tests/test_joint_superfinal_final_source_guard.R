#!/usr/bin/env Rscript
local({
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else {
    arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
    normalizePath(file.path(dirname(sub("^--file=", "", arg)), "..", ".."))
  }
  env <- new.env(parent = baseenv())
  sys.source(file.path(root, "scripts/joint_superfinal_final_source_guard.R"), envir = env)
  constants <- env$app_joint_final_source_constants()
  manifest <- read.csv(file.path(root, constants$final_manifest),
    colClasses = "character", check.names = FALSE, stringsAsFactors = FALSE)
  v3_manifest <- file.path(root, "docs/reproducibility",
    "joint_qdesn_persistent_tail_exploration_v3_sources_20261124.csv")
  if (file.exists(v3_manifest)) {
    extension_env <- new.env(parent = baseenv())
    sys.source(file.path(root, "scripts/joint_persistent_tail_v3_source_guard.R"),
      envir = extension_env)
    extension_checks <- extension_env$app_check_joint_pht3_sources(root)
    stopifnot(length(attr(extension_checks, "prior_authorized_paths")) == 13L,
      length(attr(extension_checks, "extension_authorized_paths")) == 10L)
    cat(sprintf("JOINT_SUPERFINAL_FINAL_SOURCE_GUARD_PASS checks=%d mutation_rejections=4 production_runs=0 extension=v3_verified\n",
      length(extension_checks)))
    return(invisible(NULL))
  }
  extension_manifest <- file.path(root, "docs/reproducibility",
    "joint_qdesn_persistent_tail_targeted_screen_sources_20261124.csv")
  if (file.exists(extension_manifest)) {
    extension_env <- new.env(parent = baseenv())
    sys.source(file.path(root, "scripts/joint_persistent_tail_targeted_source_guard.R"),
      envir = extension_env)
    extension_checks <- extension_env$app_check_joint_pht_sources(root)
    stopifnot(length(attr(extension_checks, "prior_authorized_paths")) == 8L,
      length(attr(extension_checks, "extension_authorized_paths")) == 13L)
    rejected <- 0L
    reject <- function(expr) {
      error <- tryCatch({ force(expr); NULL }, error = identity)
      stopifnot(inherits(error, "error")); rejected <<- rejected + 1L
    }
    reject(env$app_joint_final_source_structure(manifest[-1L, , drop = FALSE]))
    reject(env$app_joint_final_source_structure(rbind(manifest, manifest[1L, ])))
    bad <- manifest; bad$role[[1L]] <- "broad_permission"
    reject(env$app_joint_final_source_structure(bad))
    bad <- manifest; bad$sha256[[1L]] <- "missing"
    reject(env$app_joint_final_source_structure(bad))
    cat(sprintf("JOINT_SUPERFINAL_FINAL_SOURCE_GUARD_PASS checks=%d mutation_rejections=%d production_runs=0 extension=verified\n",
      length(extension_checks), rejected))
    return(invisible(NULL))
  }
  checks <- env$app_check_joint_superfinal_final_sources(root)
  stopifnot(length(attr(checks, "correction_authorized_paths")) == 62L,
    length(attr(checks, "final_authorized_paths")) == 8L,
    length(attr(checks, "joint_authorized_paths")) == 69L,
    length(attr(checks, "transition_authorized_additions")) == 7L,
    length(attr(checks, "authorized_paths")) == 76L)
  rejected <- 0L
  reject <- function(expr) {
    error <- tryCatch({ force(expr); NULL }, error = identity)
    stopifnot(inherits(error, "error")); rejected <<- rejected + 1L
  }
  reject(env$app_check_joint_superfinal_final_sources(root,
    manifest_sha256 = strrep("0", 64L)))
  reject(env$app_joint_final_source_structure(manifest[-1L, , drop = FALSE]))
  reject(env$app_joint_final_source_structure(rbind(manifest, manifest[1L, ])))
  bad <- manifest; bad$role[[1L]] <- "broad_permission"
  reject(env$app_joint_final_source_structure(bad))
  bad <- manifest; bad$mode[[1L]] <- "100600"
  reject(env$app_joint_final_source_structure(bad))
  bad <- manifest; bad$sha256[[1L]] <- "missing"
  reject(env$app_joint_final_source_structure(bad))
  bad <- manifest; bad$blob[[1L]] <- "missing"
  reject(env$app_joint_final_source_structure(bad))
  bad <- manifest; bad$sha256[[1L]] <- strrep("0", 64L)
  reject(env$app_joint_final_source_bytes(manifest, bad))
  cat(sprintf("JOINT_SUPERFINAL_FINAL_SOURCE_GUARD_PASS checks=%d mutation_rejections=%d production_runs=0\n",
    length(checks), rejected))
})
