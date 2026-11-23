# Compose the reviewed AL-kernel correction with its exact execution surface.

app_joint_final_source_constants <- function() {
  list(
    correction_base = "555880087b765a6fef0434e01366a2a570bc5cee",
    correction_baseline = "d49b08e025056020cb12bbdcf85f046fac3f2f88",
    correction_guard = "scripts/composable_scientific_source_guard.R",
    correction_guard_sha256 =
      "5168cb4f3b4a0e6741bc74aaeda2528cce3acdbe5c84bf6c987bf8bc59b71c2c",
    correction_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_superfinal_al_kernel_correction_sources_20261123.csv"),
    correction_manifest_sha256 =
      "331437cf5a22dbb61f7d29374c9db356b68265e09ed5dd2adfe2e4e3b436a11d",
    final_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_superfinal_al_kernel_rerun_sources_20261123.csv"),
    final_manifest_sha256 =
      "8526909fdb43f520ac0f593185db4c8988c4ee7f7e2a03b2c7360894c98f02a3",
    scopes = c("application/R", "application/config", "application/scripts",
      "application/cpp", "validation")
  )
}

app_joint_final_source_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("JOINT_FINAL_SOURCE_GUARD:", message), call. = FALSE)
}

app_joint_final_source_structure <- function(manifest) {
  require <- app_joint_final_source_require
  require(identical(names(manifest), c("path", "role", "mode", "sha256", "blob")),
    "final manifest schema is exact")
  require(nrow(manifest) == 8L && !anyNA(manifest) && !anyDuplicated(manifest$path) &&
    identical(manifest$path, sort(manifest$path, method = "radix")),
    "final manifest contains exactly eight sorted unique paths")
  require(all(manifest$role == "joint_superfinal_al_kernel_rerun"),
    "final roles cannot broaden authorization")
  require(all(manifest$mode %in% c("100644", "100755")) &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)) &&
    all(grepl("^[a-f0-9]{40}$", manifest$blob)),
    "final source modes and hashes are complete")
  invisible(TRUE)
}

app_joint_final_source_bytes <- function(manifest, observed) {
  app_joint_final_source_structure(manifest)
  app_joint_final_source_require(identical(names(observed), names(manifest)) &&
    identical(observed, manifest), "every final source byte, role and mode must match")
  invisible(TRUE)
}

app_check_joint_superfinal_final_sources <- function(repo_root,
    manifest_sha256 = app_joint_final_source_constants()$final_manifest_sha256) {
  root <- normalizePath(repo_root, mustWork = TRUE)
  constants <- app_joint_final_source_constants()
  require <- app_joint_final_source_require
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
  check(git_run(c("merge-base", "--is-ancestor", constants$correction_base,
    "HEAD"), TRUE)$status == 0L, "final source descends from the reviewed correction")
  correction_guard <- file.path(root, constants$correction_guard)
  correction_manifest_file <- file.path(root, constants$correction_manifest)
  check(regular(correction_guard) && regular(correction_manifest_file) &&
    identical(unname(tools::sha256sum(correction_guard)[[1L]]),
      constants$correction_guard_sha256) &&
    identical(unname(tools::sha256sum(correction_manifest_file)[[1L]]),
      constants$correction_manifest_sha256),
    "reviewed correction guard and manifest retain their exact pins")
  correction_env <- new.env(parent = baseenv())
  sys.source(correction_guard, envir = correction_env)
  composed_constants <- correction_env$app_composable_source_constants()
  transition_guard <- file.path(root, composed_constants$transition_guard)
  transition_env <- new.env(parent = baseenv())
  check(regular(transition_guard) && identical(
    unname(tools::sha256sum(transition_guard)[[1L]]),
    composed_constants$transition_guard_sha256),
    "historical transition guard retains its exact pin")
  sys.source(transition_guard, envir = transition_env)
  transition_paths <- transition_env$app_transition_source_paths()
  transition_manifest_file <- file.path(root, transition_paths$manifest)
  check(regular(transition_manifest_file) && identical(
    unname(tools::sha256sum(transition_manifest_file)[[1L]]),
    composed_constants$transition_manifest_sha256),
    "historical transition manifest retains its exact pin")
  transition <- utils::read.csv(transition_manifest_file, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  transition_env$app_transition_source_structure(transition)
  correction <- utils::read.csv(correction_manifest_file, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  correction_env$app_joint_correction_source_structure(correction)

  final_file <- file.path(root, constants$final_manifest)
  check(regular(final_file) && identical(manifest_sha256,
    constants$final_manifest_sha256) && identical(
      unname(tools::sha256sum(final_file)[[1L]]), constants$final_manifest_sha256),
    "final manifest matches its immutable internal and caller pins")
  final <- utils::read.csv(final_file, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  app_joint_final_source_structure(final)
  files <- file.path(root, final$path)
  check(all(vapply(files, regular, logical(1L))), "final sources remain regular files")
  observed <- final
  observed$sha256 <- unname(tools::sha256sum(files))
  observed$blob <- git(c("hash-object", "--no-filters", "--",
    vapply(final$path, shQuote, character(1L))))
  observed$mode <- ifelse(bitwAnd(as.integer(file.info(files)$mode), 73L) == 0L,
    "100644", "100755")
  app_joint_final_source_bytes(final, observed)

  changes <- union(git(c("diff", "--no-ext-diff", "--no-renames", "--name-only",
    constants$correction_base, "--", constants$scopes)),
    git(c("diff", "--cached", "--no-ext-diff", "--no-renames", "--name-only",
      constants$correction_base, "--", constants$scopes)))
  check(setequal(changes, final$path) && length(changes) == nrow(final),
    "scientific delta from the reviewed correction is exactly eight paths")
  untracked <- git(c("ls-files", "--others", "--", constants$scopes))
  untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
  check(length(untracked) == 0L, "untracked scientific implementations are not authorized")
  indexed <- git(c("ls-files", "--stage", "--", vapply(final$path, shQuote, character(1L))))
  check(length(indexed) == nrow(final) &&
    all(grepl("^(100644|100755) [a-f0-9]{40} 0\t", indexed)),
    "all final sources are tracked without conflicts")
  indexed_paths <- sub("^[^\t]+\t", "", indexed)
  indexed_modes <- sub("^([0-9]{6}) .*$", "\\1", indexed)
  indexed_blobs <- sub("^[0-9]{6} ([a-f0-9]{40}) 0\t.*$", "\\1", indexed)
  check(identical(unname(indexed_modes[match(final$path, indexed_paths)]), final$mode) &&
    identical(unname(indexed_blobs[match(final$path, indexed_paths)]), final$blob),
    "index matches every final source authorization")
  transition_additions <- transition_paths$new[startsWith(transition_paths$new,
    "application/")]
  joint_paths <- unique(c(correction$path, final$path))
  attr(checks, "transition_authorized_additions") <- transition_additions
  attr(checks, "correction_authorized_paths") <- correction$path
  attr(checks, "final_authorized_paths") <- final$path
  attr(checks, "joint_authorized_paths") <- joint_paths
  attr(checks, "authorized_paths") <- unique(c(transition_additions, joint_paths))
  invisible(checks)
}
