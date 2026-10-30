#!/usr/bin/env Rscript

# Read-only authorization for one frozen scientific merge, not an exemption for
# application source edits. The caller pins the manifest's complete SHA256.
app_check_glofas_unit_member_integration_sources <- function(repo_root,
                                                            manifest_sha256) {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  baseline <- "a96e661613ec7e733196a0b994f45350a3078332"
  source_commit <- "60daab261d52eec0ae24060babe186d618303e2b"
  source_parent <- "483e6edbec72ec76e48f2259e943e674b76e5041"
  manifest_relative <- paste0("docs/reproducibility/",
    "glofas_unit_member_integration_source_contract_20261029.csv")
  scopes <- c("application/R", "application/config", "application/scripts",
    "application/cpp", "validation")
  authorized_paths <- c(
    "application/R/fit_qdesn_latent_path.R",
    "application/R/glofas_unit_member_correction.R",
    "application/R/latent_path_vb_al.R",
    "application/R/latent_path_vb_exal.R",
    "application/R/latent_path_vb_joint.R",
    "application/R/latent_path_vb_normal.R",
    "application/config/glofas_unit_member_source_contract_v1.csv",
    "application/scripts/386_run_glofas_part4_latent_family_job.R",
    "application/scripts/_glofas_unit_member_bootstrap.R",
    "application/scripts/finalize_glofas_unit_member_correction.R",
    "application/scripts/launch_glofas_unit_member_correction.py",
    "application/scripts/prepare_glofas_unit_member_correction.R")
  worker <- "application/scripts/386_run_glofas_part4_latent_family_job.R"
  checks <- character()
  require_check <- function(value, message) {
    if (!isTRUE(value)) stop(message, call. = FALSE)
    checks <<- c(checks, message)
  }
  git_run <- function(arguments) {
    output <- suppressWarnings(system2("git",
      c("--no-replace-objects", "-C", shQuote(repo_root), arguments),
      stdout = TRUE, stderr = TRUE))
    status <- attr(output, "status")
    list(output = unname(as.character(output)),
      status = if (is.null(status)) 0L else as.integer(status))
  }
  git <- function(arguments) {
    result <- git_run(arguments)
    require_check(result$status == 0L,
      paste("Git source authorization verification:", paste(arguments, collapse = " ")))
    result$output
  }
  ancestor <- function(older, newer) {
    result <- git_run(c("merge-base", "--is-ancestor", older, newer))
    require_check(result$status %in% c(0L, 1L),
      "Frozen source ancestry must be readable without Git errors.")
    identical(result$status, 0L)
  }
  regular_file <- function(path) {
    info <- file.info(path)
    isTRUE(file.exists(path)) && !isTRUE(info$isdir) &&
      identical(unname(Sys.readlink(path)), "")
  }
  tree_entries <- function(revision, paths) {
    rows <- git(c("ls-tree", "-r", revision, "--", vapply(paths, shQuote, character(1))))
    require_check(length(rows) == length(paths) &&
      all(grepl("^[0-9]{6} blob [a-f0-9]{40}\t", rows)),
      "Frozen source entries must be regular Git blobs with complete inventory.")
    data.frame(path = sub("^[^\t]+\t", "", rows),
      mode = sub("^([0-9]{6}) .*$", "\\1", rows),
      blob = sub("^[0-9]{6} blob ([a-f0-9]{40})\t.*$", "\\1", rows),
      stringsAsFactors = FALSE)
  }
  # Include ignored source additions; only generated Python bytecode is not a
  # source implementation. In particular, an ignore rule cannot hide new R,
  # Python, C++, configuration, or validation sources from this guard.
  untracked <- git(c("ls-files", "--others", "--", scopes))
  untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
  require_check(length(untracked) == 0L,
    "No untracked scientific source implementations are authorized.")
  changes <- union(
    git(c("diff", "--no-ext-diff", "--no-renames", "--name-only",
      baseline, "--", scopes)),
    git(c("diff", "--cached", "--no-ext-diff", "--no-renames", "--name-only",
      baseline, "--", scopes)))
  manifest_path <- file.path(repo_root, manifest_relative)
  manifest_link <- Sys.readlink(manifest_path)
  manifest_present <- file.exists(manifest_path) ||
    (!is.na(manifest_link) && nzchar(manifest_link))
  if (!manifest_present) {
    require_check(length(changes) == 0L,
      "An editorial revision may not change scientific source implementations.")
    return(invisible(c(checks,
      "Editorial source authorization: no scientific source changes.")))
  }
  require_check(regular_file(manifest_path),
    "The scientific source authorization manifest must be a regular file.")
  require_check(is.character(manifest_sha256) && length(manifest_sha256) == 1L &&
    !is.na(manifest_sha256) && grepl("^[a-f0-9]{64}$", manifest_sha256) &&
    identical(unname(tools::sha256sum(manifest_path)[[1L]]), manifest_sha256),
    "The scientific source authorization manifest SHA256 must match its checker pin.")
  manifest <- utils::read.csv(manifest_path, colClasses = "character", check.names = FALSE,
    stringsAsFactors = FALSE)
  require_check(identical(names(manifest), c("path", "source_mode", "source_blob",
    "authorized_mode", "authorized_blob", "sha256")) &&
    nrow(manifest) == 12L && !anyNA(manifest) && !anyDuplicated(manifest$path) &&
    identical(manifest$path, authorized_paths),
    "The scientific source authorization inventory must contain exactly the twelve frozen paths.")
  require_check(all(manifest$source_mode == "100644") &&
    all(manifest$authorized_mode == "100644") &&
    all(grepl("^[a-f0-9]{40}$", manifest$source_blob)) &&
    all(grepl("^[a-f0-9]{40}$", manifest$authorized_blob)) &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)),
    "Scientific source manifest modes and hashes must be complete and bounded.")
  require_check(identical(manifest$path[
    manifest$source_blob != manifest$authorized_blob], worker),
    "Only the operational worker engine-binding correction may differ from the frozen scientific source.")
  parents <- git(c("rev-list", "--parents", "-n", "1", source_commit))
  require_check(identical(parents, paste(source_commit, source_parent)),
    "The frozen scientific source must retain its exact original parent.")
  require_check(ancestor(baseline, source_parent),
    "The editorial protection baseline must precede the frozen scientific parent.")
  original_changes <- git(c("diff", "--no-ext-diff", "--no-renames", "--name-only",
    baseline, source_commit, "--", scopes))
  require_check(length(original_changes) == 12L &&
    setequal(original_changes, authorized_paths),
    "The frozen science commit must change exactly the twelve authorized source paths.")
  original <- tree_entries(source_commit, authorized_paths)
  original <- original[match(authorized_paths, original$path), , drop = FALSE]
  require_check(identical(original$path, manifest$path) &&
    identical(original$mode, manifest$source_mode) &&
    identical(original$blob, manifest$source_blob),
    "Original scientific source blobs and modes must match the immutable source commit.")
  integrated <- ancestor(source_commit, "HEAD")
  if (!integrated) {
    merge_path <- git(c("rev-parse", "--path-format=absolute", "--git-path", "MERGE_HEAD"))
    merge_heads <- if (length(merge_path) == 1L && file.exists(merge_path)) {
      readLines(merge_path, warn = FALSE)
    } else character()
    integrated <- identical(merge_heads, source_commit) && ancestor(source_parent, "HEAD")
  }
  require_check(integrated,
    "The exact frozen scientific source must be merged or be the sole pending MERGE_HEAD.")
  require_check(length(changes) == 12L && setequal(changes, authorized_paths),
    "Integrated scientific source changes must be exactly the twelve authorized paths.")
  full_paths <- file.path(repo_root, authorized_paths)
  require_check(all(vapply(full_paths, regular_file, logical(1))),
    "No authorized scientific source may be missing, a directory, or a symlink.")
  # Check filesystem mode directly, even if core.filemode=false masks a chmod
  # from git diff. All twelve authorized files are non-executable regular files.
  modes <- as.integer(file.info(full_paths)$mode)
  require_check(all(bitwAnd(modes, 73L) == 0L),
    "Authorized scientific source executable modes must remain unchanged.")
  current_sha256 <- unname(tools::sha256sum(full_paths))
  current_blobs <- git(c("hash-object", "--no-filters", "--",
    vapply(authorized_paths, shQuote, character(1))))
  require_check(identical(current_sha256, manifest$sha256) &&
    identical(current_blobs, manifest$authorized_blob),
    "Scientific source bytes must equal the frozen commit plus the sole pinned operational worker correction.")
  staged <- git(c("ls-files", "--stage", "--",
    vapply(authorized_paths, shQuote, character(1))))
  require_check(length(staged) == 12L &&
    all(grepl("^100644 [a-f0-9]{40} 0\t", staged)),
    "Authorized scientific source index entries must have the frozen mode and no conflicts.")
  staged_paths <- sub("^[^\t]+\t", "", staged)
  staged_blobs <- sub("^100644 ([a-f0-9]{40}) 0\t.*$", "\\1", staged)
  positions <- match(authorized_paths, staged_paths)
  require_check(!anyNA(positions) &&
    all(staged_blobs[positions] == manifest$source_blob |
      staged_blobs[positions] == manifest$authorized_blob),
    "Staged source bytes must be frozen science or the sole authorized worker correction.")
  invisible(c(checks,
    "Integrated source authorization: twelve exact paths; eleven frozen blobs and one operational worker correction."))
}
