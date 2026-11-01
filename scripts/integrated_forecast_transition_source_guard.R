# Exact additive source authorization. This does not authorize scientific runs,
# replace historical result authority, or relax the original twelve-file gate.
app_transition_source_paths <- function() {
  list(
    baseline = "48cb1bdc95f28ba7c38591b4a09df5266af2c2ad",
    manifest = "docs/reproducibility/integrated_forecast_transition_sources_20261031.csv",
    new = c(
      "application/R/glofas_family_transition.R",
      "application/R/integrated_quantile_forecast.R",
      "application/config/forecast_transition_multihost_v1.json",
      "application/scripts/forecast_transition_control.py",
      "application/scripts/prepare_glofas_family_transition.R",
      "application/scripts/run_glofas_family_transition.R",
      "application/scripts/run_integrated_quantile_forecast.R",
      "scripts/integrated_forecast_transition_source_guard.R",
      "scripts/prepare_integrated_forecast_evidence.R",
      "scripts/score_integrated_quantile_forecasts.R"),
    frozen = c(
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
      "application/scripts/prepare_glofas_unit_member_correction.R"))
}

app_transition_source_require <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("TRANSITION_SOURCE_GUARD:", message), call. = FALSE)
}

app_transition_source_structure <- function(manifest) {
  require <- app_transition_source_require
  paths <- app_transition_source_paths()
  expected <- sort(c(paths$new, paths$frozen), method = "radix")
  require(identical(names(manifest), c("path", "role", "mode", "sha256", "blob")),
    "source manifest schema is exact")
  require(!anyNA(manifest) && !anyDuplicated(manifest$path) &&
    identical(manifest$path, expected), "source manifest inventory is exact and sorted")
  require(identical(manifest$role, ifelse(manifest$path %in% paths$new,
    "new_workflow", "frozen_dependency")), "source roles cannot broaden the original authorization")
  require(all(manifest$mode == "100644") &&
    all(grepl("^[a-f0-9]{64}$", manifest$sha256)) &&
    all(grepl("^[a-f0-9]{40}$", manifest$blob)), "source modes and hashes are complete")
  invisible(TRUE)
}

app_transition_source_bytes <- function(manifest, observed) {
  app_transition_source_structure(manifest)
  app_transition_source_require(identical(names(observed), names(manifest)) &&
    identical(observed, manifest), "every source byte, role and non-executable mode must match")
  invisible(TRUE)
}

app_check_integrated_forecast_transition_sources <- function(repo_root, manifest_sha256) {
  root <- normalizePath(repo_root, mustWork = TRUE)
  paths <- app_transition_source_paths()
  require <- app_transition_source_require
  checks <- character()
  check <- function(ok, message) {
    require(ok, message)
    checks <<- c(checks, message)
  }
  git_run <- function(args, allow_missing = FALSE) {
    out <- suppressWarnings(system2("git", c("--no-replace-objects", "-C",
      shQuote(root), args), stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status")
    status <- if (is.null(status)) 0L else as.integer(status)
    if (!allow_missing) require(status == 0L, paste("Git check", paste(args, collapse = " ")))
    list(out = unname(as.character(out)), status = status)
  }
  git <- function(args) git_run(args)$out
  relative <- paths$manifest
  filename <- file.path(root, relative)
  regular <- function(path) file.exists(path) && !isTRUE(file.info(path)$isdir) &&
    identical(unname(Sys.readlink(path)), "")
  check(regular(filename), "new source authorization is a regular file")
  check(is.character(manifest_sha256) && length(manifest_sha256) == 1L &&
    grepl("^[a-f0-9]{64}$", manifest_sha256) &&
    identical(unname(tools::sha256sum(filename)[[1L]]), manifest_sha256),
    "new source authorization matches its caller's exact SHA256 pin")
  manifest <- utils::read.csv(filename, colClasses = "character", check.names = FALSE,
    stringsAsFactors = FALSE)
  app_transition_source_structure(manifest)
  check(git_run(c("merge-base", "--is-ancestor", paths$baseline, "HEAD"), TRUE)$status == 0L,
    "current source descends from the approved current-method main")
  files <- file.path(root, manifest$path)
  check(all(vapply(files, regular, logical(1))), "source files cannot be absent or symlinks")
  observed <- manifest
  observed$sha256 <- unname(tools::sha256sum(files))
  observed$blob <- git(c("hash-object", "--no-filters", "--", vapply(manifest$path, shQuote, "")))
  observed$mode <- ifelse(bitwAnd(as.integer(file.info(files)$mode), 73L) == 0L,
    "100644", "100755")
  app_transition_source_bytes(manifest, observed)
  for (path in paths$frozen) {
    expected <- git(c("rev-parse", shQuote(paste0(paths$baseline, ":", path))))
    check(identical(expected, manifest$blob[manifest$path == path]),
      paste("original dependency stays frozen:", path))
  }
  for (path in paths$new) {
    check(git_run(c("cat-file", "-e", shQuote(paste0(paths$baseline, ":", path))), TRUE)$status != 0L,
      paste("new workflow is additive, not a hidden replacement:", path))
  }
  indexed <- git(c("ls-files", "--stage", "--", vapply(manifest$path, shQuote, "")))
  check(length(indexed) == nrow(manifest) &&
    all(grepl("^100644 [a-f0-9]{40} 0\t", indexed)), "all workflow sources are tracked without conflicts")
  ipath <- sub("^[^\t]+\t", "", indexed)
  iblob <- sub("^100644 ([a-f0-9]{40}) 0\t.*$", "\\1", indexed)
  check(!anyNA(match(manifest$path, ipath)) &&
    identical(iblob[match(manifest$path, ipath)], manifest$blob),
    "staged bytes cannot differ from the exact authorized current sources")
  scopes <- c("application/R", "application/config", "application/scripts", "application/cpp", "validation")
  untracked <- git(c("ls-files", "--others", "--", scopes))
  untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
  check(length(untracked) == 0L, "untracked or ignored scientific implementations are not allowed")
  changes <- union(git(c("diff", "--no-ext-diff", "--no-renames", "--name-only", paths$baseline,
    "--", scopes)), git(c("diff", "--cached", "--no-ext-diff", "--no-renames", "--name-only",
      paths$baseline, "--", scopes)))
  additions <- paths$new[startsWith(paths$new, "application/")]
  check(setequal(changes, additions) && length(changes) == length(additions),
    "the new scientific surface contains only its exact additive paths")
  attr(checks, "authorized_additions") <- additions
  invisible(checks)
}
