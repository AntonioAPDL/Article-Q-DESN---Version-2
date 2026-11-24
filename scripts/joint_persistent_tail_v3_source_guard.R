# Compose the frozen persistent-tail v2 source contract with the v3 extension.

app_joint_pht3_source_constants <- function() {
  list(
    parent_head = "a097b01df88496cacb75b86027aaa0dfe9e18825",
    prior_guard = "scripts/joint_persistent_tail_targeted_source_guard.R",
    prior_guard_sha256 =
      "e4c20ad0695db139b4be56e36a9495b4b2b850a55dd0f983bdebcc9be70fab07",
    prior_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_persistent_tail_targeted_screen_sources_20261124.csv"),
    prior_manifest_sha256 =
      "c0ea49b1f0f7446681f0c63bfd52d36146b179ac93c6be607ddd430c28d0e306",
    extension_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_persistent_tail_exploration_v3_sources_20261124.csv"),
    extension_manifest_sha256 =
      "ebef9183651099b269192886ff201edac9ebe9838b4bcac5f07299b89a0bd80f",
    scopes = c("application/R", "application/config", "application/scripts",
      "application/cpp", "validation")
  )
}

app_joint_pht3_source_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("JOINT_PHT3_SOURCE_GUARD:", message), call. = FALSE)
}

app_joint_pht3_source_structure <- function(manifest) {
  require <- app_joint_pht3_source_require
  require(identical(names(manifest), c("path", "role", "mode", "sha256", "blob")),
    "extension manifest schema is exact")
  require(nrow(manifest) == 10L && !anyNA(manifest) && !anyDuplicated(manifest$path) &&
    identical(manifest$path, sort(manifest$path, method = "radix")),
    "extension manifest contains exactly ten sorted unique scientific paths")
  require(all(manifest$role == "joint_persistent_tail_exploration_v3"),
    "extension roles cannot broaden authorization")
  require(all(manifest$mode %in% c("100644", "100755")) &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)) &&
    all(grepl("^[a-f0-9]{40}$", manifest$blob)),
    "extension source modes and hashes are complete")
  invisible(TRUE)
}

app_joint_pht3_source_bytes <- function(manifest, observed) {
  app_joint_pht3_source_structure(manifest)
  app_joint_pht3_source_require(identical(names(observed), names(manifest)) &&
    identical(observed, manifest), "every v3 source byte and mode matches")
  invisible(TRUE)
}

app_check_joint_pht3_sources <- function(repo_root,
    manifest_sha256 = app_joint_pht3_source_constants()$extension_manifest_sha256) {
  root <- normalizePath(repo_root, mustWork = TRUE)
  constants <- app_joint_pht3_source_constants()
  require <- app_joint_pht3_source_require
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
    "v3 descends from the frozen persistent-tail v2 head")
  prior_guard <- file.path(root, constants$prior_guard)
  prior_manifest <- file.path(root, constants$prior_manifest)
  check(regular(prior_guard) && regular(prior_manifest) &&
    identical(unname(tools::sha256sum(prior_guard)[[1L]]), constants$prior_guard_sha256) &&
    identical(unname(tools::sha256sum(prior_manifest)[[1L]]), constants$prior_manifest_sha256),
    "frozen v2 guard and manifest retain exact pins")
  prior_env <- new.env(parent = baseenv())
  sys.source(prior_guard, envir = prior_env)
  prior <- utils::read.csv(prior_manifest, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  prior_env$app_joint_pht_source_structure(prior)

  manifest_file <- file.path(root, constants$extension_manifest)
  check(regular(manifest_file) && identical(manifest_sha256,
    constants$extension_manifest_sha256) && identical(
      unname(tools::sha256sum(manifest_file)[[1L]]), constants$extension_manifest_sha256),
    "v3 manifest matches immutable internal and caller pins")
  manifest <- utils::read.csv(manifest_file, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  app_joint_pht3_source_structure(manifest)
  files <- file.path(root, manifest$path)
  check(all(vapply(files, regular, logical(1L))), "v3 sources remain regular files")
  observed <- manifest
  observed$sha256 <- unname(tools::sha256sum(files))
  observed$blob <- git(c("hash-object", "--no-filters", "--",
    vapply(manifest$path, shQuote, character(1L))))
  observed$mode <- ifelse(bitwAnd(as.integer(file.info(files)$mode), 73L) == 0L,
    "100644", "100755")
  app_joint_pht3_source_bytes(manifest, observed)

  changes <- union(git(c("diff", "--no-ext-diff", "--no-renames", "--name-only",
    constants$parent_head, "--", constants$scopes)),
    git(c("diff", "--cached", "--no-ext-diff", "--no-renames", "--name-only",
      constants$parent_head, "--", constants$scopes)))
  check(setequal(changes, manifest$path) && length(changes) == nrow(manifest),
    "scientific delta from frozen v2 is exactly ten paths")
  untracked <- git(c("ls-files", "--others", "--", constants$scopes))
  untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
  check(length(untracked) == 0L, "untracked scientific implementations are not authorized")
  indexed <- git(c("ls-files", "--stage", "--",
    vapply(manifest$path, shQuote, character(1L))))
  check(length(indexed) == nrow(manifest) &&
    all(grepl("^(100644|100755) [a-f0-9]{40} 0\t", indexed)),
    "all v3 sources are tracked without conflicts")
  indexed_paths <- sub("^[^\t]+\t", "", indexed)
  indexed_modes <- sub("^([0-9]{6}) .*$", "\\1", indexed)
  indexed_blobs <- sub("^[0-9]{6} ([a-f0-9]{40}) 0\t.*$", "\\1", indexed)
  check(identical(unname(indexed_modes[match(manifest$path, indexed_paths)]), manifest$mode) &&
    identical(unname(indexed_blobs[match(manifest$path, indexed_paths)]), manifest$blob),
    "index matches every v3 source authorization")
  attr(checks, "prior_authorized_paths") <- prior$path
  attr(checks, "extension_authorized_paths") <- manifest$path
  attr(checks, "authorized_paths") <- unique(c(prior$path, manifest$path))
  invisible(checks)
}
