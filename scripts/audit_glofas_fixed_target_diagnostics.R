#!/usr/bin/env Rscript
# Generated references only. This entry point has no retained-model read route.

gftd_generated_report <- function(repo_root = getwd()) {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  paths <- c("application/R/glofas_fixed_target_scalar_diagnostics.R",
             "application/R/glofas_fixed_target_affine_diagnostics.R",
             "application/R/glofas_fixed_target_smoothing_reference.R")
  ns <- new.env(parent = globalenv())
  for (path in paths) sys.source(file.path(repo_root, path), envir = ns)
  scalar <- ns$gfts_run_scalar_diagnostics(repo_root = repo_root)
  affine <- ns$gfta_run_affine_diagnostics(root = repo_root)
  smoothing <- ns$gftsr_run_smoothing_diagnostics(root = repo_root)
  parts <- list(scalar = scalar, affine = affine)
  required <- c("test_id", "reference_validity", "implementation_parity",
                "numerical_stability", "approximation_accuracy",
                "production_relevance", "error", "tolerance", "detail")
  for (part in parts) {
    stopifnot(is.data.frame(part$checks),
              all(required %in% names(part$checks)),
              identical(part$scientific_runs, 0L),
              identical(part$authentic_reads, 0L))
  }
  checks <- do.call(rbind, lapply(names(parts), function(name) {
    data.frame(stream = name, parts[[name]]$checks[, required],
               stringsAsFactors = FALSE, row.names = NULL)
  }))
  stopifnot(!anyDuplicated(checks$test_id), nrow(checks) > 0L)
  software_columns <- c("reference_validity", "implementation_parity",
                        "numerical_stability")
  software_fail <- any(vapply(checks[software_columns], function(x)
    anyNA(x) || any(x != "PASS"), logical(1L)))
  software_fail <- software_fail ||
    any(smoothing$checks$reference_validity != "PASS") ||
    any(smoothing$checks$numerical_stability != "PASS")
  accuracy_fail <- any(checks$approximation_accuracy == "FAIL") ||
    any(smoothing$checks$approximation_accuracy == "FAIL")
  list(
    schema_version = "glofas_fixed_target_generated_diagnostic_v1",
    generated_checks = checks,
    scalar_results = scalar$results,
    smoothing_reference_checks = smoothing$checks,
    smoothing_cases = smoothing$cases,
    smoothing_quantiles = smoothing$quantiles,
    smoothing_reference_qualification = "Exact small-model reference; implementation parity is not independently established by those cases",
    smoothing_implementation_parity_status = "NOT_ASSESSED_BY_SMOOTHING_CASES",
    no_information_reference = scalar$no_information_reference,
    software_status = if (software_fail) "FAIL" else "PASS",
    approximation_accuracy_status = if (accuracy_fail) "FAIL" else "NOT_FAILED_IN_TESTED_CASES",
    scientific_campaign_authorized = FALSE,
    classification = if (software_fail) "IMPLEMENTATION_OR_REFERENCE_REVIEW_REQUIRED" else
      if (accuracy_fail) "AL_APPROXIMATION_LIMITATION_REPRODUCED_NOT_CAMPAIGN_ATTRIBUTION" else
        "GENERATED_CASES_ONLY_NOT_PRODUCTION_QUALIFICATION",
    scientific_runs = 0L,
    authentic_reads = 0L,
    future_truth_read = FALSE,
    source_files = paths
  )
}

gftd_generated_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  if (length(args) != 3L || !identical(args[c(1L, 3L)], c("--out-dir", "--generated-only"))) {
    stop("Use --out-dir NEW_DIRECTORY --generated-only; no model-read mode exists.", call. = FALSE)
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required.", call. = FALSE)
  out <- args[[2L]]
  if (file.exists(out) || (!is.na(Sys.readlink(out)) && nzchar(Sys.readlink(out)))) {
    stop("Output must be fresh and not a symlink.", call. = FALSE)
  }
  out <- normalizePath(out, mustWork = FALSE)
  repo <- normalizePath(getwd(), mustWork = TRUE)
  if (!startsWith(out, paste0(repo, "/local_trackers/")) ||
      !dir.exists(dirname(out)) ||
      !identical(normalizePath(dirname(out)), dirname(out)) ||
      grepl("(^|/)\\.\\.(/|$)", out) ||
      system2("git", c("check-ignore", "--quiet", "--", shQuote(out))) != 0L) {
    stop("Generated output must be a fresh ignored local_trackers directory.", call. = FALSE)
  }
  before <- proc.time()
  started <- format(Sys.time(), tz = "UTC", usetz = TRUE)
  report <- gftd_generated_report()
  if (!dir.create(out, recursive = TRUE)) stop("Cannot create fresh diagnostic output.", call. = FALSE)
  utils::write.csv(report$generated_checks, file.path(out, "generated_checks.csv"), row.names = FALSE)
  utils::write.csv(report$scalar_results, file.path(out, "scalar_results.csv"), row.names = FALSE)
  utils::write.csv(report$smoothing_reference_checks,
    file.path(out, "smoothing_reference_checks.csv"), row.names = FALSE)
  utils::write.csv(report$smoothing_cases, file.path(out, "smoothing_cases.csv"), row.names = FALSE)
  utils::write.csv(report$smoothing_quantiles, file.path(out, "smoothing_quantiles.csv"), row.names = FALSE)
  jsonlite::write_json(report$no_information_reference,
    file.path(out, "no_information_reference.json"), auto_unbox = TRUE, pretty = TRUE, digits = 17)
  files <- c(report$source_files, "application/R/latent_path_vb_al.R",
             "scripts/audit_glofas_fixed_target_diagnostics.R")
  report$source_files <- lapply(files, function(path) list(
    relative_path = path, sha256 = unname(tools::sha256sum(path))))
  report$generated_checks <- NULL
  report$scalar_results <- NULL
  report$smoothing_reference_checks <- NULL
  report$smoothing_cases <- NULL
  report$smoothing_quantiles <- NULL
  report$no_information_reference <- NULL
  report$source_commit <- unname(system2("git", c("rev-parse", "HEAD"), stdout = TRUE))
  report$source_dirty <- length(system2("git", c("status", "--porcelain"), stdout = TRUE)) > 0L
  report$r_version <- R.version.string
  report$started_utc <- started
  timing <- proc.time() - before
  report$wall_seconds <- unname(timing[["elapsed"]])
  report$cpu_seconds <- unname(sum(timing[c("user.self", "sys.self")]))
  jsonlite::write_json(report, file.path(out, "DECISION.json"), auto_unbox = TRUE,
                      pretty = TRUE, digits = 17)
  entries <- sort(list.files(out))
  manifest <- data.frame(relative_path = entries,
    size_bytes = unname(file.info(file.path(out, entries))$size),
    sha256 = unname(tools::sha256sum(file.path(out, entries))))
  utils::write.csv(manifest, file.path(out, "artifact_manifest.csv"), row.names = FALSE)
  message("GENERATED_SOFTWARE_STATUS=", report$software_status)
  message("APPROXIMATION_ACCURACY_STATUS=", report$approximation_accuracy_status)
  message("SCIENTIFIC_CAMPAIGN_AUTHORIZED=FALSE")
  if (!identical(report$software_status, "PASS")) quit(status = 1L)
  invisible(report)
}

if (sys.nframe() == 0L) gftd_generated_main()
