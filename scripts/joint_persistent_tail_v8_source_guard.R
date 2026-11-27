# Exact additive source guard for the persistent-heavy-tail V8 calibration lane.

app_joint_pht8_source_constants <- function() {
  list(parent_head = "6aa48ea681df6fe2e32636fb70ed9ff5176085f3",
    manifest = paste0("docs/reproducibility/",
      "joint_qdesn_persistent_tail_v8_sources_20261126.csv"),
    manifest_sha256 = "03e002eeeb55678dc270ad1cc487d195e61a0de54229d17a6b8a7ff93a2a909e",
    expected_paths = 8L,
    scopes = c("application/R", "application/config", "application/scripts",
      "application/cpp", "validation"))
}

app_joint_pht8_source_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("JOINT_PHT8_SOURCE_GUARD:", message), call. = FALSE)
}

app_joint_pht8_source_structure <- function(manifest) {
  constants <- app_joint_pht8_source_constants()
  require <- app_joint_pht8_source_require
  require(identical(names(manifest), c("path", "role", "mode", "sha256", "blob")),
    "manifest schema is exact")
  require(nrow(manifest) == constants$expected_paths && !anyNA(manifest) &&
    !anyDuplicated(manifest$path) && identical(manifest$path,
      sort(manifest$path, method = "radix")),
    "manifest contains exactly eight sorted unique scientific paths")
  require(all(manifest$role == "joint_persistent_tail_v8"),
    "roles cannot broaden authorization")
  require(all(manifest$mode %in% c("100644", "100755")) &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)) &&
    all(grepl("^[a-f0-9]{40}$", manifest$blob)),
    "source modes and hashes are complete")
  invisible(TRUE)
}

app_joint_pht8_source_bytes <- function(manifest, observed) {
  app_joint_pht8_source_structure(manifest)
  app_joint_pht8_source_require(identical(names(observed), names(manifest)) &&
    identical(observed, manifest), "every V8 source byte and mode matches")
  invisible(TRUE)
}

app_check_joint_pht8_sources <- function(repo_root,
    manifest_sha256 = app_joint_pht8_source_constants()$manifest_sha256) {
  root <- normalizePath(repo_root, mustWork = TRUE)
  constants <- app_joint_pht8_source_constants()
  require <- app_joint_pht8_source_require
  checks <- character()
  check <- function(ok, message) {
    require(ok, message)
    checks <<- c(checks, message)
  }
  git_run <- function(args, allow_failure = FALSE) {
    out <- suppressWarnings(system2("git",
      c("--no-replace-objects", "-C", shQuote(root), args),
      stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status")
    status <- if (is.null(status)) 0L else as.integer(status)
    if (!allow_failure) check(status == 0L,
      paste("Git check", paste(args, collapse = " ")))
    list(out = unname(as.character(out)), status = status)
  }
  git <- function(args) git_run(args)$out
  regular <- function(path) file.exists(path) && !isTRUE(file.info(path)$isdir) &&
    identical(unname(Sys.readlink(path)), "")
  check(git_run(c("merge-base", "--is-ancestor", constants$parent_head, "HEAD"),
    TRUE)$status == 0L, "V8 lane descends from the frozen V7 closeout")
  manifest_file <- file.path(root, constants$manifest)
  check(regular(manifest_file) && identical(manifest_sha256,
    constants$manifest_sha256) && identical(
      unname(tools::sha256sum(manifest_file)[[1L]]), constants$manifest_sha256),
    "V8 manifest matches immutable internal and caller pins")
  manifest <- utils::read.csv(manifest_file, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  app_joint_pht8_source_structure(manifest)
  files <- file.path(root, manifest$path)
  check(all(vapply(files, regular, logical(1L))), "V8 sources remain regular files")
  observed <- manifest
  observed$sha256 <- unname(tools::sha256sum(files))
  observed$blob <- vapply(manifest$path, function(path) git(c("hash-object",
    "--no-filters", "--", shQuote(path)))[[1L]], character(1L))
  observed$mode <- ifelse(bitwAnd(as.integer(file.info(files)$mode), 73L) == 0L,
    "100644", "100755")
  app_joint_pht8_source_bytes(manifest, observed)
  changes <- union(git(c("diff", "--no-ext-diff", "--no-renames", "--name-only",
    constants$parent_head, "--", constants$scopes)),
    git(c("diff", "--cached", "--no-ext-diff", "--no-renames", "--name-only",
      constants$parent_head, "--", constants$scopes)))
  check(setequal(changes, manifest$path) && length(changes) == nrow(manifest),
    "scientific delta from the frozen V7 parent is exactly eight additive paths")
  untracked <- git(c("ls-files", "--others", "--", constants$scopes))
  untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
  check(length(untracked) == 0L, "untracked scientific implementations are absent")
  indexed <- git(c("ls-files", "--stage", "--",
    vapply(manifest$path, shQuote, character(1L))))
  check(length(indexed) == nrow(manifest) &&
    all(grepl("^(100644|100755) [a-f0-9]{40} 0\\t", indexed)),
    "all V8 sources are tracked without conflicts")
  indexed_paths <- sub("^[^\\t]+\\t", "", indexed)
  indexed_modes <- sub("^([0-9]{6}) .*$", "\\1", indexed)
  indexed_blobs <- sub("^[0-9]{6} ([a-f0-9]{40}) 0\\t.*$", "\\1", indexed)
  check(identical(unname(indexed_modes[match(manifest$path, indexed_paths)]),
    manifest$mode) && identical(
      unname(indexed_blobs[match(manifest$path, indexed_paths)]), manifest$blob),
    "index matches every V8 source authorization")
  attr(checks, "authorized_paths") <- manifest$path
  invisible(checks)
}
