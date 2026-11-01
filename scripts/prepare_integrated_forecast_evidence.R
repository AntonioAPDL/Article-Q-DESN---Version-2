#!/usr/bin/env Rscript
# Metadata enrollment only: never fits, forecasts, copies model payloads,
# transfers runtime, submits jobs, or edits the frozen source evidence.
app_iqf_evidence_assert <- function(ok, message) {
  if (!isTRUE(ok)) stop(paste("IQF_EVIDENCE:", message), call. = FALSE)
}

app_iqf_evidence_path <- function(root, relative) {
  assert <- app_iqf_evidence_assert
  assert(is.character(relative) && length(relative) == 1L && !is.na(relative) &&
    nzchar(relative) && !grepl("(^/|^[A-Za-z]:|\\\\|[\r\n]|(^|/)\\.\\.?(/|$))", relative),
    "payload paths must be explicit safe relative names")
  parts <- strsplit(relative, "/", fixed = TRUE)[[1L]]
  assert(!any(parts %in% c("", ".git", ".ssh", ".codex")), "private or ambiguous payload path")
  path <- root
  for (part in parts) {
    path <- file.path(path, part)
    link <- Sys.readlink(path)
    assert(is.na(link) || !nzchar(link), "payload symlinks are forbidden")
  }
  assert(file.exists(path) && !isTRUE(file.info(path)$isdir), "payload is missing or not a regular file")
  path <- normalizePath(path, mustWork = TRUE)
  assert(startsWith(path, paste0(root, "/")), "payload escapes evidence root")
  path
}

app_iqf_enroll_evidence <- function(root, spec_relative, output, max_hash_bytes = 256 * 1024^2) {
  assert <- app_iqf_evidence_assert
  root <- normalizePath(root, mustWork = TRUE)
  assert(dir.exists(root) && nchar(root) > 5L && !root %in% c("/data", "/home", "/tmp"),
    "an exact task-specific evidence root is required")
  spec_file <- app_iqf_evidence_path(root, spec_relative)
  spec <- if (grepl("[.]rds$", spec_file, ignore.case = TRUE)) readRDS(spec_file) else
    jsonlite::read_json(spec_file, simplifyVector = FALSE)
  assert(identical(spec$schema_version %||% spec$schema, "integrated_quantile_forecast_bundle_v1"),
    "unknown bundle specification")
  roles <- switch(spec$adapter,
    mq_desn_native_v1 = c("design", "posterior", "origins"),
    single_qdesn_fit_native_v1 = c("object", "posterior", "origins"),
    state_space_conditional_v1 = c("model", "posterior", "origins"),
    stop("IQF_EVIDENCE: unsupported forecast adapter", call. = FALSE))
  is_path <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  assert(is.list(spec$payloads) && setequal(names(spec$payloads), roles) &&
    all(vapply(spec$payloads, is_path, logical(1))),
    "payload roles must exactly match the actual forecast adapter")
  support <- spec$supporting_evidence %||% list()
  support_roles <- names(support)
  assert(is.list(support) && !anyDuplicated(support_roles) &&
    all(grepl("^(draw_mapping|posterior_source_[A-Za-z0-9_]+|native_kernel|source_contract)$", support_roles)) &&
    all(vapply(support, is_path, logical(1))), "unsupported or ambiguous supporting evidence role")
  paths <- c(bundle_spec = spec_relative, unlist(spec$payloads[roles], use.names = TRUE),
    unlist(support, use.names = TRUE))
  assert(is.character(paths) && !anyNA(paths) && !anyDuplicated(unname(paths)),
    "payload membership must be explicit, unique and complete")
  full <- vapply(paths, function(path) app_iqf_evidence_path(root, path), "")
  bytes <- as.numeric(file.info(full)$size)
  assert(is.numeric(max_hash_bytes) && length(max_hash_bytes) == 1L &&
    is.finite(max_hash_bytes) && max_hash_bytes > 0 && sum(bytes) <= max_hash_bytes,
    "evidence hashing exceeds its explicit byte budget")
  hashes <- unname(tools::sha256sum(full))
  assert(identical(bytes, as.numeric(file.info(full)$size)), "payload changed during enrollment")
  role_map <- c(bundle_spec = "bundle_spec", design = "retained_design", object = "retained_design",
    model = "retained_design", posterior = "retained_posterior", origins = "observed_prefix")
  role_values <- names(paths)
  for (i in seq_along(role_values)) {
    if (role_values[i] %in% names(role_map)) role_values[i] <- role_map[[role_values[i]]]
    if (startsWith(role_values[i], "posterior_source_")) role_values[i] <- "retained_posterior"
  }
  manifest <- data.frame(relative_path = unname(paths), size_bytes = bytes,
    sha256 = hashes, role = role_values, stringsAsFactors = FALSE)
  manifest <- manifest[order(manifest$relative_path, method = "radix"), ]
  rownames(manifest) <- NULL
  output <- normalizePath(output, mustWork = FALSE)
  assert(!file.exists(output) && !startsWith(output, paste0(root, "/")) && output != root,
    "output must be a new directory outside the frozen evidence root")
  assert(dir.create(output, recursive = TRUE, showWarnings = FALSE), "cannot create metadata directory")
  utils::write.csv(manifest, file.path(output, "input_manifest.csv"), row.names = FALSE, quote = TRUE)
  identity <- list(schema_version = "integrated_quantile_evidence_enrollment_v1",
    status = "ENROLLED_NOT_LAUNCHED", evidence_root = root, spec_relative = spec_relative,
    input_manifest_sha256 = unname(tools::sha256sum(file.path(output, "input_manifest.csv"))[[1L]]),
    files = nrow(manifest), bytes = sum(bytes), allow_launch = FALSE,
    fitted_payloads_copied = 0L, trajectories_generated = 0L, fits_launched = 0L,
    qualification = "worker must additionally validate posterior/origin/model semantics")
  jsonlite::write_json(identity, file.path(output, "enrollment.json"), pretty = TRUE, auto_unbox = TRUE)
  invisible(identity)
}

app_iqf_catalog_ind_sources <- function(locator, output, expected_locator_sha256,
                                       max_metadata_bytes = 64 * 1024^2) {
  assert <- app_iqf_evidence_assert
  locator <- normalizePath(locator, mustWork = TRUE)
  assert(identical(unname(tools::sha256sum(locator)[[1L]]), expected_locator_sha256),
    "IND locator hash mismatch")
  tab <- utils::read.csv(locator, colClasses = "character", stringsAsFactors = FALSE)
  assert(all(c("task_id", "job_root", "contract_path", "contract_sha256") %in% names(tab)) &&
    !anyDuplicated(tab$task_id), "IND locator inventory is incomplete")
  consumed <- 0
  read_meta <- function(path, expected = NULL) {
    assert(file.exists(path) && !isTRUE(file.info(path)$isdir) &&
      identical(unname(Sys.readlink(path)), ""), "IND metadata is absent or a symlink")
    consumed <<- consumed + file.info(path)$size
    assert(consumed <= max_metadata_bytes, "IND metadata byte budget exceeded")
    if (!is.null(expected)) assert(identical(unname(tools::sha256sum(path)[[1L]]), expected),
      "IND metadata hash mismatch")
    jsonlite::read_json(path, simplifyVector = FALSE)
  }
  rows <- lapply(seq_len(nrow(tab)), function(i) {
    contract <- read_meta(tab$contract_path[[i]], tab$contract_sha256[[i]])
    capsule_path <- file.path(tab$job_root[[i]], "protected_capsule.json")
    if (!file.exists(capsule_path)) return(data.frame(task_id = tab$task_id[[i]],
      engine = contract$engine %||% "unknown", source_commit = contract$source_commit %||% "",
      fitted_payload = "", expected_payload_sha256 = "", payload_present = FALSE,
      readiness = "BLOCKED_MISSING_CAPSULE", stringsAsFactors = FALSE))
    retention_path <- file.path(tab$job_root[[i]], "retention_manifest.csv")
    assert(file.exists(retention_path), "capsule has no retained-artifact inventory")
    retention <- utils::read.csv(retention_path, stringsAsFactors = FALSE)
    assert(all(c("path", "sha256") %in% names(retention)) &&
      sum(retention$path == capsule_path) == 1L, "capsule membership is not unique")
    capsule <- read_meta(capsule_path, retention$sha256[retention$path == capsule_path])
    payload <- capsule$fitted_payload_path
    assert(is.character(payload) && length(payload) == 1L &&
      grepl("^[a-f0-9]{64}$", capsule$fitted_payload_sha256) &&
      identical(capsule$source_commit, contract$source_commit), "IND fitted source identity is incomplete")
    data.frame(task_id = tab$task_id[[i]], engine = contract$engine,
      source_commit = contract$source_commit, fitted_payload = payload,
      expected_payload_sha256 = capsule$fitted_payload_sha256,
      payload_present = file.exists(payload),
      readiness = if (file.exists(payload)) "METADATA_ONLY_REQUIRES_PAYLOAD_HASH_AND_ADAPTER_QUALIFICATION" else
        "BLOCKED_MISSING_FITTED_PAYLOAD", stringsAsFactors = FALSE)
  })
  result <- do.call(rbind, rows)
  output <- normalizePath(output, mustWork = FALSE)
  assert(!file.exists(output), "catalog output already exists")
  assert(dir.create(output, recursive = TRUE, showWarnings = FALSE), "cannot create catalog directory")
  utils::write.csv(result, file.path(output, "ind_source_catalog.csv"), row.names = FALSE)
  jsonlite::write_json(list(schema_version = "integrated_quantile_source_catalog_v1",
    status = "METADATA_AUDIT_ONLY", locator_sha256 = expected_locator_sha256,
    tasks = nrow(result), metadata_bytes = consumed, allow_launch = FALSE,
    payload_bytes_verified = FALSE, trajectories_generated = 0L, fits_launched = 0L),
    file.path(output, "catalog.json"), auto_unbox = TRUE, pretty = TRUE)
  invisible(result)
}

if (!exists("%||%", mode = "function")) `%||%` <- function(x, y) if (is.null(x)) y else x
if (sys.nframe() == 0L) {
  args <- commandArgs(TRUE)
  if (!length(args)) {
    cat("PREPARATION_ONLY: no fits, trajectories, transfers or jobs are launched.\n",
      "Usage: Rscript prepare_integrated_forecast_evidence.R --root ROOT --spec RELATIVE_SPEC --out NEW_DIR [--max-hash-bytes N]\n",
      "  or: --catalog-ind LOCATOR --locator-sha256 SHA256 --out NEW_DIR\n", sep = "")
  } else {
    app_iqf_evidence_assert(length(args) %% 2L == 0L && !anyDuplicated(args[seq(1L, length(args), 2L)]),
      "arguments are unique option/value pairs")
    opts <- as.list(args[seq(2L, length(args), 2L)])
    names(opts) <- sub("^--", "", args[seq(1L, length(args), 2L)])
    app_iqf_evidence_assert(all(names(opts) %in% c("root", "spec", "out", "max-hash-bytes", "catalog-ind", "locator-sha256")) &&
      !is.null(opts$out), "unknown or missing preparation option")
    if (!is.null(opts[["catalog-ind"]])) {
      app_iqf_catalog_ind_sources(opts[["catalog-ind"]], opts$out, opts[["locator-sha256"]])
      cat("IND_SOURCE_CATALOG_WRITTEN production_runs=0\n")
    } else {
      app_iqf_enroll_evidence(opts$root, opts$spec, opts$out,
        as.numeric(opts[["max-hash-bytes"]] %||% (256 * 1024^2)))
      cat("EVIDENCE_ENROLLED_NOT_LAUNCHED production_runs=0\n")
    }
  }
}
