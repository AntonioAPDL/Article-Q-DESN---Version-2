# Compose the corrected JOINT authority with the exact persistent-tail screen.

app_joint_pht_source_constants <- function() {
  list(
    baseline = "ce54c280153723f97a2ad46dce33cedefbd8a505",
    prior_guard = "scripts/joint_superfinal_final_source_guard.R",
    prior_guard_sha256 =
      "6e566bf7bab9193414e76a881bc05fff15c8d9c978c4cdd7ce5d5081850411ef",
    prior_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_superfinal_al_kernel_rerun_sources_20261123.csv"),
    prior_manifest_sha256 =
      "8526909fdb43f520ac0f593185db4c8988c4ee7f7e2a03b2c7360894c98f02a3",
    extension_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_persistent_tail_targeted_screen_sources_20261124.csv"),
    extension_manifest_sha256 =
      "c3a7d0a57e3e54d867c3379bc5ccfcc39c6bc7625eec03746ad8d772501b1d9f",
    scopes = c("application/R", "application/config", "application/scripts",
      "application/cpp", "validation")
  )
}

app_joint_pht_source_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("JOINT_PHT_SOURCE_GUARD:", message), call. = FALSE)
}

app_joint_pht_source_structure <- function(manifest) {
  require <- app_joint_pht_source_require
  require(identical(names(manifest), c("path", "role", "mode", "sha256", "blob")),
    "extension manifest schema is exact")
  require(nrow(manifest) == 11L && !anyNA(manifest) &&
    !anyDuplicated(manifest$path) &&
    identical(manifest$path, sort(manifest$path, method = "radix")),
    "extension manifest contains exactly eleven sorted unique paths")
  require(all(manifest$role == "joint_persistent_tail_targeted_screen"),
    "extension roles cannot broaden authorization")
  require(all(manifest$mode %in% c("100644", "100755")) &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)) &&
    all(grepl("^[a-f0-9]{40}$", manifest$blob)),
    "extension source modes and hashes are complete")
  invisible(TRUE)
}

app_joint_pht_source_bytes <- function(manifest, observed) {
  app_joint_pht_source_structure(manifest)
  app_joint_pht_source_require(identical(names(observed), names(manifest)) &&
    identical(observed, manifest), "every extension source byte and mode matches")
  invisible(TRUE)
}

app_check_joint_pht_sources <- function(repo_root,
    manifest_sha256 = app_joint_pht_source_constants()$extension_manifest_sha256) {
  root <- normalizePath(repo_root, mustWork = TRUE)
  constants <- app_joint_pht_source_constants()
  require <- app_joint_pht_source_require
  checks <- character()
  check <- function(ok, message) {
    require(ok, message); checks <<- c(checks, message)
  }
  git_run <- function(args, allow_failure = FALSE) {
    out <- suppressWarnings(system2("git", c("--no-replace-objects", "-C",
      shQuote(root), args), stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status"); status <- if (is.null(status)) 0L else as.integer(status)
    if (!allow_failure) check(status == 0L, paste("Git check", paste(args, collapse = " ")))
    list(out = unname(as.character(out)), status = status)
  }
  git <- function(args) git_run(args)$out
  regular <- function(path) file.exists(path) && !isTRUE(file.info(path)$isdir) &&
    identical(unname(Sys.readlink(path)), "")

  check(git_run(c("merge-base", "--is-ancestor", constants$baseline, "HEAD"), TRUE)$status == 0L,
    "extension descends from the corrected JOINT authority")
  prior_guard <- file.path(root, constants$prior_guard)
  prior_manifest <- file.path(root, constants$prior_manifest)
  check(regular(prior_guard) && regular(prior_manifest) &&
    identical(unname(tools::sha256sum(prior_guard)[[1L]]), constants$prior_guard_sha256) &&
    identical(unname(tools::sha256sum(prior_manifest)[[1L]]), constants$prior_manifest_sha256),
    "prior JOINT guard and source manifest retain their exact pins")
  prior_env <- new.env(parent = baseenv())
  sys.source(prior_guard, envir = prior_env)
  prior <- utils::read.csv(prior_manifest, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  prior_env$app_joint_final_source_structure(prior)

  manifest_file <- file.path(root, constants$extension_manifest)
  check(regular(manifest_file) && identical(manifest_sha256,
    constants$extension_manifest_sha256) && identical(
      unname(tools::sha256sum(manifest_file)[[1L]]), constants$extension_manifest_sha256),
    "extension manifest matches its immutable internal and caller pins")
  manifest <- utils::read.csv(manifest_file, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  app_joint_pht_source_structure(manifest)
  files <- file.path(root, manifest$path)
  check(all(vapply(files, regular, logical(1L))), "extension sources remain regular files")
  observed <- manifest
  observed$sha256 <- unname(tools::sha256sum(files))
  observed$blob <- git(c("hash-object", "--no-filters", "--",
    vapply(manifest$path, shQuote, character(1L))))
  observed$mode <- ifelse(bitwAnd(as.integer(file.info(files)$mode), 73L) == 0L,
    "100644", "100755")
  app_joint_pht_source_bytes(manifest, observed)

  changes <- union(git(c("diff", "--no-ext-diff", "--no-renames", "--name-only",
    constants$baseline, "--", constants$scopes)),
    git(c("diff", "--cached", "--no-ext-diff", "--no-renames", "--name-only",
      constants$baseline, "--", constants$scopes)))
  check(setequal(changes, manifest$path) && length(changes) == nrow(manifest),
    "scientific delta from corrected authority is exactly eleven paths")
  untracked <- git(c("ls-files", "--others", "--", constants$scopes))
  untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
  check(length(untracked) == 0L, "untracked scientific implementations are not authorized")
  indexed <- git(c("ls-files", "--stage", "--",
    vapply(manifest$path, shQuote, character(1L))))
  check(length(indexed) == nrow(manifest) &&
    all(grepl("^(100644|100755) [a-f0-9]{40} 0\t", indexed)),
    "all extension sources are tracked without conflicts")
  indexed_paths <- sub("^[^\t]+\t", "", indexed)
  indexed_modes <- sub("^([0-9]{6}) .*$", "\\1", indexed)
  indexed_blobs <- sub("^[0-9]{6} ([a-f0-9]{40}) 0\t.*$", "\\1", indexed)
  check(identical(unname(indexed_modes[match(manifest$path, indexed_paths)]), manifest$mode) &&
    identical(unname(indexed_blobs[match(manifest$path, indexed_paths)]), manifest$blob),
    "index matches every extension source authorization")
  attr(checks, "prior_authorized_paths") <- prior$path
  attr(checks, "extension_authorized_paths") <- manifest$path
  attr(checks, "authorized_paths") <- unique(c(prior$path, manifest$path))
  invisible(checks)
}
