# Compose the immutable transition authorization with the exact JOINT lane.
# Neither component may broaden the other component's source inventory.

app_composable_source_constants <- function() {
  list(
    transition_guard = "scripts/integrated_forecast_transition_source_guard.R",
    transition_guard_sha256 =
      "c8369d81b1c56b9cd7829040398b4d689a330dd1c500c0eb4f8eb05d25a1771b",
    transition_manifest_sha256 =
      "cd6684a6933de85f23d942a538c1efd241e66821b974467afb108379c068887b",
    joint_baseline = "d49b08e025056020cb12bbdcf85f046fac3f2f88",
    joint_manifest = paste0("docs/reproducibility/",
      "joint_qdesn_superfinal_al_kernel_correction_sources_20261123.csv"),
    joint_manifest_sha256 =
      "331437cf5a22dbb61f7d29374c9db356b68265e09ed5dd2adfe2e4e3b436a11d",
    scopes = c("application/R", "application/config", "application/scripts",
      "application/cpp", "validation")
  )
}

app_composable_source_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("COMPOSABLE_SOURCE_GUARD:", message), call. = FALSE)
}

app_joint_correction_source_structure <- function(manifest) {
  require <- app_composable_source_require
  require(identical(names(manifest), c("path", "role", "mode", "sha256", "blob")),
    "JOINT manifest schema is exact")
  require(nrow(manifest) == 62L && !anyNA(manifest) &&
    !anyDuplicated(manifest$path) &&
    identical(manifest$path, sort(manifest$path, method = "radix")),
    "JOINT manifest contains exactly 62 sorted unique source paths")
  require(all(manifest$role == "joint_superfinal_science"),
    "JOINT manifest roles cannot broaden authorization")
  require(all(manifest$mode %in% c("100644", "100755")) &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)) &&
    all(grepl("^[a-f0-9]{40}$", manifest$blob)),
    "JOINT source modes and hashes are complete")
  invisible(TRUE)
}

app_joint_correction_source_bytes <- function(manifest, observed) {
  app_joint_correction_source_structure(manifest)
  app_composable_source_require(identical(names(observed), names(manifest)) &&
    identical(observed, manifest),
    "every JOINT source byte, role and mode must match")
  invisible(TRUE)
}

app_check_composable_scientific_sources <- function(repo_root,
    joint_manifest_sha256 = app_composable_source_constants()$joint_manifest_sha256) {
  root <- normalizePath(repo_root, mustWork = TRUE)
  constants <- app_composable_source_constants()
  require <- app_composable_source_require
  checks <- character()
  check <- function(ok, message) {
    require(ok, message)
    checks <<- c(checks, message)
  }
  git_run <- function(args, allow_failure = FALSE) {
    out <- suppressWarnings(system2("git", c("--no-replace-objects", "-C",
      shQuote(root), args), stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status")
    status <- if (is.null(status)) 0L else as.integer(status)
    if (!allow_failure) check(status == 0L,
      paste("Git check", paste(args, collapse = " ")))
    list(out = unname(as.character(out)), status = status)
  }
  git <- function(args) git_run(args)$out
  regular <- function(path) file.exists(path) && !isTRUE(file.info(path)$isdir) &&
    identical(unname(Sys.readlink(path)), "")

  transition_guard <- file.path(root, constants$transition_guard)
  check(regular(transition_guard) &&
    identical(unname(tools::sha256sum(transition_guard)[[1L]]),
      constants$transition_guard_sha256),
    "historical transition guard retains its exact implementation")
  transition_env <- new.env(parent = baseenv())
  sys.source(transition_guard, envir = transition_env)
  transition <- transition_env$app_transition_source_paths()
  transition_manifest_file <- file.path(root, transition$manifest)
  check(regular(transition_manifest_file) &&
    identical(unname(tools::sha256sum(transition_manifest_file)[[1L]]),
      constants$transition_manifest_sha256),
    "historical transition manifest retains its exact pin")
  transition_manifest <- utils::read.csv(transition_manifest_file,
    colClasses = "character", check.names = FALSE, stringsAsFactors = FALSE)
  transition_env$app_transition_source_structure(transition_manifest)
  transition_files <- file.path(root, transition_manifest$path)
  check(all(vapply(transition_files, regular, logical(1L))),
    "historical transition sources remain regular files")
  transition_observed <- transition_manifest
  transition_observed$sha256 <- unname(tools::sha256sum(transition_files))
  transition_observed$blob <- git(c("hash-object", "--no-filters", "--",
    vapply(transition_manifest$path, shQuote, character(1L))))
  transition_observed$mode <- ifelse(bitwAnd(
    as.integer(file.info(transition_files)$mode), 73L) == 0L, "100644", "100755")
  transition_env$app_transition_source_bytes(
    transition_manifest, transition_observed)
  for (path in transition$frozen) {
    expected <- git(c("rev-parse", shQuote(paste0(transition$baseline, ":", path))))
    check(identical(expected,
      transition_manifest$blob[transition_manifest$path == path]),
      paste("historical dependency stays frozen:", path))
  }
  for (path in transition$new) {
    check(git_run(c("cat-file", "-e", shQuote(paste0(
      transition$baseline, ":", path))), TRUE)$status != 0L,
      paste("historical transition source remains additive:", path))
  }

  joint_file <- file.path(root, constants$joint_manifest)
  check(regular(joint_file), "JOINT source manifest is a regular file")
  check(is.character(joint_manifest_sha256) &&
    length(joint_manifest_sha256) == 1L &&
    identical(joint_manifest_sha256, constants$joint_manifest_sha256) &&
    identical(unname(tools::sha256sum(joint_file)[[1L]]),
      constants$joint_manifest_sha256),
    "JOINT source manifest matches its immutable internal and caller pins")
  joint_manifest <- utils::read.csv(joint_file, colClasses = "character",
    check.names = FALSE, stringsAsFactors = FALSE)
  app_joint_correction_source_structure(joint_manifest)
  check(git_run(c("merge-base", "--is-ancestor", constants$joint_baseline,
    "HEAD"), TRUE)$status == 0L,
    "JOINT source descends from its approved main baseline")
  joint_files <- file.path(root, joint_manifest$path)
  check(all(vapply(joint_files, regular, logical(1L))),
    "JOINT sources remain regular files")
  joint_observed <- joint_manifest
  joint_observed$sha256 <- unname(tools::sha256sum(joint_files))
  joint_observed$blob <- git(c("hash-object", "--no-filters", "--",
    vapply(joint_manifest$path, shQuote, character(1L))))
  joint_observed$mode <- ifelse(bitwAnd(
    as.integer(file.info(joint_files)$mode), 73L) == 0L, "100644", "100755")
  app_joint_correction_source_bytes(joint_manifest, joint_observed)

  all_paths <- unique(c(transition_manifest$path, joint_manifest$path))
  indexed <- git(c("ls-files", "--stage", "--",
    vapply(all_paths, shQuote, character(1L))))
  check(length(indexed) == length(all_paths) &&
    all(grepl("^(100644|100755) [a-f0-9]{40} 0\t", indexed)),
    "all composed scientific sources are tracked without conflicts")
  indexed_paths <- sub("^[^\t]+\t", "", indexed)
  indexed_modes <- sub("^([0-9]{6}) .*$", "\\1", indexed)
  indexed_blobs <- sub("^[0-9]{6} ([a-f0-9]{40}) 0\t.*$", "\\1", indexed)
  expected_blobs <- c(stats::setNames(transition_manifest$blob,
    transition_manifest$path), stats::setNames(joint_manifest$blob,
    joint_manifest$path))
  expected_blobs <- expected_blobs[!duplicated(names(expected_blobs), fromLast = TRUE)]
  expected_modes <- c(stats::setNames(transition_manifest$mode,
    transition_manifest$path), stats::setNames(joint_manifest$mode,
    joint_manifest$path))
  expected_modes <- expected_modes[!duplicated(names(expected_modes), fromLast = TRUE)]
  check(!anyNA(match(all_paths, indexed_paths)) &&
    identical(unname(indexed_blobs[match(all_paths, indexed_paths)]),
      unname(expected_blobs[all_paths])) &&
    identical(unname(indexed_modes[match(all_paths, indexed_paths)]),
      unname(expected_modes[all_paths])),
    "the index matches every composed source authorization")

  untracked <- git(c("ls-files", "--others", "--", constants$scopes))
  untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
  check(length(untracked) == 0L,
    "untracked scientific implementations are not authorized")
  joint_changes <- union(git(c("diff", "--no-ext-diff", "--no-renames",
    "--name-only", constants$joint_baseline, "--", constants$scopes)),
    git(c("diff", "--cached", "--no-ext-diff", "--no-renames",
      "--name-only", constants$joint_baseline, "--", constants$scopes)))
  check(setequal(joint_changes, joint_manifest$path) &&
    length(joint_changes) == nrow(joint_manifest),
    "JOINT scientific delta is exactly its 62 authorized paths")
  transition_changes <- union(git(c("diff", "--no-ext-diff", "--no-renames",
    "--name-only", transition$baseline, "--", constants$scopes)),
    git(c("diff", "--cached", "--no-ext-diff", "--no-renames",
      "--name-only", transition$baseline, "--", constants$scopes)))
  transition_additions <- transition$new[startsWith(transition$new, "application/")]
  composed <- unique(c(transition_additions, joint_manifest$path))
  check(setequal(transition_changes, composed) &&
    length(transition_changes) == length(composed),
    "transition-baseline delta is exactly the composed authorization")
  attr(checks, "transition_authorized_additions") <- transition_additions
  attr(checks, "joint_authorized_paths") <- joint_manifest$path
  attr(checks, "authorized_additions") <- composed
  invisible(checks)
}
