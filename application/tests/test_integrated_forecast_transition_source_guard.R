#!/usr/bin/env Rscript
# Source-only contract mutations; no production fitting, forecasting or dispatch.
local({
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else {
    arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
    normalizePath(file.path(dirname(sub("^--file=", "", arg)), "..", ".."))
  }
  source(file.path(root, "scripts/integrated_forecast_transition_source_guard.R"), local = TRUE)
  cfg <- app_transition_source_paths()
  manifest <- read.csv(file.path(root, cfg$manifest), colClasses = "character", check.names = FALSE)
  pin <- unname(tools::sha256sum(file.path(root, cfg$manifest))[[1L]])
  guard_root <- root
  # The original launch authorization remains exact and unchanged. Later
  # diagnostic-only helpers are not a new scientific launch authorization.
  # Test that original workflow at its frozen producer, while independently
  # checking the exact additive diagnostic bytes in the current repository.
  diagnostic_head <- "dd83bfabc89000132e39ab803db4462673bcf5f9"
  diagnostic_paths <- c(
    "application/R/glofas_fixed_target_affine_diagnostics.R",
    "application/R/glofas_fixed_target_scalar_diagnostics.R",
    "application/R/glofas_fixed_target_smoothing_reference.R",
    "application/R/glofas_fixed_target_stationarity.R")
  if (any(file.exists(file.path(root, diagnostic_paths)))) {
    git <- function(args, where = root) {
      out <- system2("git", c("--no-replace-objects", "-C", shQuote(where), args),
                     stdout = TRUE, stderr = TRUE)
      stopifnot(is.null(attr(out, "status")))
      unname(out)
    }
    stopifnot(all(file.exists(file.path(root, diagnostic_paths))))
    git(c("merge-base", "--is-ancestor", diagnostic_head, "HEAD"))
    stopifnot(identical(unname(tools::sha256sum(file.path(root, manifest$path))),
                        manifest$sha256),
              all(bitwAnd(as.integer(file.info(file.path(root, manifest$path))$mode), 73L) == 0L),
              all(vapply(file.path(root, manifest$path), function(p)
                !isTRUE(file.info(p)$isdir) && identical(Sys.readlink(p), ""), logical(1L))))
    verify_index <- function(paths, expected_blobs) {
      indexed <- git(c("ls-files", "--stage", "--", vapply(paths, shQuote, "")))
      stopifnot(length(indexed) == length(paths),
                all(grepl("^100644 [a-f0-9]{40} 0\t", indexed)))
      index_paths <- sub("^[^\t]+\t", "", indexed)
      index_blobs <- sub("^100644 ([a-f0-9]{40}) 0\t.*$", "\\1", indexed)
      stopifnot(!anyNA(match(paths, index_paths)),
                identical(index_blobs[match(paths, index_paths)], expected_blobs))
    }
    verify_index(manifest$path, manifest$blob)
    diagnostic_blobs <- character()
    for (path in diagnostic_paths) {
      expected <- git(c("rev-parse", shQuote(paste0(diagnostic_head, ":", path))))
      stopifnot(identical(Sys.readlink(file.path(root, path)), ""),
                !isTRUE(file.info(file.path(root, path))$isdir),
                bitwAnd(as.integer(file.info(file.path(root, path))$mode), 73L) == 0L,
                identical(git(c("hash-object", "--no-filters", "--", shQuote(path))),
                          expected))
      diagnostic_blobs <- c(diagnostic_blobs, expected)
    }
    verify_index(diagnostic_paths, diagnostic_blobs)
    scopes <- c("application/R", "application/config", "application/scripts", "application/cpp", "validation")
    additions <- cfg$new[startsWith(cfg$new, "application/")]
    changed <- union(git(c("diff", "--no-ext-diff", "--no-renames", "--name-only", cfg$baseline, "--", scopes)),
      git(c("diff", "--cached", "--no-ext-diff", "--no-renames", "--name-only", cfg$baseline, "--", scopes)))
    stopifnot(setequal(changed, c(additions, diagnostic_paths)),
              length(changed) == length(additions) + length(diagnostic_paths))
    untracked <- git(c("ls-files", "--others", "--", scopes))
    untracked <- untracked[!grepl("(^|/)__pycache__/[^/]+[.]pyc$", untracked)]
    stopifnot(length(untracked) == 0L)
    fixture <- tempfile("transition_guard_frozen_")
    stopifnot(system2("git", c("clone", "--quiet", "--shared", "--no-checkout",
      shQuote(root), shQuote(fixture))) == 0L)
    stopifnot(system2("git", c("-C", shQuote(fixture), "checkout", "--quiet", "--detach",
      "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6")) == 0L)
    stopifnot(identical(git(c("rev-parse", "HEAD"), where = fixture),
      "fa6a4e33c6d352d65cf99dd3e59b66a1b4c498a6"))
    guard_root <- fixture
    message("Historical transition guard: frozen scientific producer; current four diagnostic modules are separately pinned, not scientifically authorized.")
  }
  checks <- app_check_integrated_forecast_transition_sources(guard_root, pin)
  stopifnot(length(attr(checks, "authorized_additions")) == 7L)
  rejected <- 0L
  reject <- function(expr) {
    err <- tryCatch({force(expr); NULL}, error = identity)
    stopifnot(inherits(err, "error"))
    rejected <<- rejected + 1L
  }
  bad <- manifest[-1L, ]; reject(app_transition_source_structure(bad))
  bad <- rbind(manifest, manifest[1L, ]); reject(app_transition_source_structure(bad))
  bad <- manifest; bad$role[[1L]] <- "broad_edit_permission"; reject(app_transition_source_structure(bad))
  bad <- manifest; bad$path[[1L]] <- "application/R/00_packages.R"; reject(app_transition_source_structure(bad))
  bad <- manifest; bad$mode[[1L]] <- "100755"; reject(app_transition_source_structure(bad))
  bad <- manifest; bad$sha256[[1L]] <- "missing"; reject(app_transition_source_structure(bad))
  bad <- manifest; bad$blob[[1L]] <- "missing"; reject(app_transition_source_structure(bad))
  for (i in seq_len(nrow(manifest))) {
    bad <- manifest; bad$sha256[[i]] <- strrep("0", 64L)
    reject(app_transition_source_bytes(manifest, bad))
  }
  reject(app_check_integrated_forecast_transition_sources(guard_root, strrep("0", 64L)))
  cat(sprintf("INTEGRATED_TRANSITION_SOURCE_GUARD_PASS checks=%d mutation_rejections=%d production_runs=0\n",
    length(checks), rejected))
})
