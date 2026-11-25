# Compose the frozen V3 source contract with the fit-first extension.

app_joint_phtff_source_constants <- function() {
  list(
    parent_head = "4f54ea14d58a3d1caacf244ae525f1bb8a8dd648",
    prior_guard = "scripts/joint_persistent_tail_v3_source_guard.R",
    prior_guard_sha256 =
      "0078ea0ec7f31b07efb426fe9bbdb7e0fe364d2956968e34c096b0183b47d36c",
    prior_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_persistent_tail_exploration_v3_sources_20261124.csv"),
    prior_manifest_sha256 =
      "d0638c34af9b2514e283ca9f86bccbd58abca52f16fc084bcfeda4b8a0c4946f",
    extension_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_persistent_tail_fit_first_sources_20261125.csv"),
    extension_manifest_sha256 =
      "d43d5442fe8a55e440a8da58bd2978539f1057b9295e8ad3a5af6270c734e7f7",
    scopes = c("application/R", "application/config", "application/scripts",
      "application/cpp", "validation")
  )
}

app_joint_phtff_source_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("JOINT_PHTFF_SOURCE_GUARD:", message), call. = FALSE)
}

app_joint_phtff_source_structure <- function(manifest) {
  require <- app_joint_phtff_source_require
  require(identical(names(manifest), c("path", "role", "mode", "sha256", "blob")),
    "extension manifest schema is exact")
  require(nrow(manifest) == 8L && !anyNA(manifest) && !anyDuplicated(manifest$path) &&
    identical(manifest$path, sort(manifest$path, method = "radix")),
    "extension manifest contains exactly eight sorted unique scientific paths")
  require(all(manifest$role == "joint_persistent_tail_fit_first"),
    "extension roles cannot broaden authorization")
  require(all(manifest$mode %in% c("100644", "100755")) &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)) &&
    all(grepl("^[a-f0-9]{40}$", manifest$blob)),
    "extension source modes and hashes are complete")
  invisible(TRUE)
}

app_joint_phtff_source_bytes <- function(manifest, observed) {
  app_joint_phtff_source_structure(manifest)
  app_joint_phtff_source_require(identical(names(observed), names(manifest)) &&
    identical(observed, manifest), "every fit-first source byte and mode matches")
  invisible(TRUE)
}

app_check_joint_phtff_sources <- function(repo_root,
    manifest_sha256 = app_joint_phtff_source_constants()$extension_manifest_sha256) {
  root <- normalizePath(repo_root, mustWork = TRUE)
  constants <- app_joint_phtff_source_constants()
  require <- app_joint_phtff_source_require
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

  check(git_run(c("merge-base", "--is-ancestor", constants$parent_head, "HEAD"), TRUE)$status == 0L,
    "fit-first lane descends from the frozen V3 head")
  prior_guard <- file.path(root, constants$prior_guard)
  prior_manifest <- file.path(root, constants$prior_manifest)
  check(regular(prior_guard) && regular(prior_manifest) &&
    identical(unname(tools::sha256sum(prior_guard)[[1L]]), constants$prior_guard_sha256) &&
    identical(unname(tools::sha256sum(prior_manifest)[[1L]]),
      constants$prior_manifest_sha256),
    "frozen V3 guard and manifest retain exact pins")
  prior_env <- new.env(parent = baseenv())
  sys.source(prior_guard, envir = prior_env)
  prior <- utils::read.csv(prior_manifest, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  prior_env$app_joint_pht3_source_structure(prior)

  manifest_file <- file.path(root, constants$extension_manifest)
  check(regular(manifest_file) && identical(manifest_sha256,
    constants$extension_manifest_sha256) && identical(
      unname(tools::sha256sum(manifest_file)[[1L]]), constants$extension_manifest_sha256),
    "fit-first manifest matches immutable internal and caller pins")
  manifest <- utils::read.csv(manifest_file, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  app_joint_phtff_source_structure(manifest)
  files <- file.path(root, manifest$path)
  check(all(vapply(files, regular, logical(1L))), "fit-first sources remain regular files")
  observed <- manifest
  observed$sha256 <- unname(tools::sha256sum(files))
  observed$blob <- git(c("hash-object", "--no-filters", "--",
    vapply(manifest$path, shQuote, character(1L))))
  observed$mode <- ifelse(bitwAnd(as.integer(file.info(files)$mode), 73L) == 0L,
    "100644", "100755")
  app_joint_phtff_source_bytes(manifest, observed)

  changes <- union(git(c("diff", "--no-ext-diff", "--no-renames", "--name-only",
    constants$parent_head, "--", constants$scopes)),
    git(c("diff", "--cached", "--no-ext-diff", "--no-renames", "--name-only",
      constants$parent_head, "--", constants$scopes)))
  check(setequal(changes, manifest$path) && length(changes) == nrow(manifest),
    "scientific delta from frozen V3 is exactly eight paths")
  untracked <- git(c("ls-files", "--others", "--", constants$scopes))
  untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
  check(length(untracked) == 0L, "untracked scientific implementations are not authorized")
  indexed <- git(c("ls-files", "--stage", "--",
    vapply(manifest$path, shQuote, character(1L))))
  check(length(indexed) == nrow(manifest) &&
    all(grepl("^(100644|100755) [a-f0-9]{40} 0\t", indexed)),
    "all fit-first sources are tracked without conflicts")
  indexed_paths <- sub("^[^\t]+\t", "", indexed)
  indexed_modes <- sub("^([0-9]{6}) .*$", "\\1", indexed)
  indexed_blobs <- sub("^[0-9]{6} ([a-f0-9]{40}) 0\t.*$", "\\1", indexed)
  check(identical(unname(indexed_modes[match(manifest$path, indexed_paths)]), manifest$mode) &&
    identical(unname(indexed_blobs[match(manifest$path, indexed_paths)]), manifest$blob),
    "index matches every fit-first source authorization")
  attr(checks, "prior_authorized_paths") <- prior$path
  attr(checks, "extension_authorized_paths") <- manifest$path
  attr(checks, "authorized_paths") <- unique(c(prior$path, manifest$path))
  invisible(checks)
}
