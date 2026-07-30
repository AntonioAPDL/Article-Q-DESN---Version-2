#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

script_path <- {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg)) {
    normalizePath(
      sub("^--file=", "", file_arg[[1L]]),
      winslash = "/",
      mustWork = TRUE
    )
  } else {
    normalizePath(
      "scripts/check_qdesn_mcmc_current_best_validation_tables.R",
      winslash = "/",
      mustWork = TRUE
    )
  }
}
repo_root <- normalizePath(
  file.path(dirname(script_path), ".."),
  winslash = "/",
  mustWork = TRUE
)
manifest_path <- file.path(
  repo_root,
  "tables",
  "qdesn_validation_tt500_mcmc_current_best_manifest.txt"
)
if (!file.exists(manifest_path)) {
  stop("Missing independent-validation article manifest.", call. = FALSE)
}

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
manifest_lines <- readLines(manifest_path, warn = FALSE)
scalar_lines <- grep(
  "^[A-Za-z][A-Za-z0-9_]*: ",
  manifest_lines,
  value = TRUE
)
scalar_keys <- sub(": .*", "", scalar_lines)
if (anyDuplicated(scalar_keys)) {
  stop("Article manifest contains duplicate scalar keys.", call. = FALSE)
}
manifest <- setNames(sub("^[^:]+: ", "", scalar_lines), scalar_keys)

expected <- c(
  authority_as_of = "2026-07-30",
  authority_freeze_id = paste0(
    "qdesn_500obs_mcmc_nested_final_origin9000_v1_",
    "evidence_freeze_20260730"
  ),
  validation_authority_commit =
    "b24cb53f34863f1ca7a6df95c8508d341de5692d",
  latest_evidence_decision = "NO_CONFIRMED_COHERENT_ARTICLE_REFRESH",
  latest_evidence_coherent_promotion_cells = "0",
  latest_evidence_article_refresh_metric_rows = "0",
  latest_evidence_consumable_run_tag = paste0(
    "qdesn-500obs-mcmc-nested-final-o9000-v1-full-",
    "20260730__git-bd4da62"
  ),
  latest_evidence_rejected_run_tag = paste0(
    "qdesn-500obs-mcmc-nested-final-o9000-v1-full-",
    "20260730__git-6582f87"
  ),
  exposed_confirmation_origins = "9000",
  article_numeric_state = "UNCHANGED_FROM_20260727_AUTHORITY",
  article_numeric_update = "FALSE",
  source_promotion_id = "qdesn_dqlm_500obs_mcmc_metric_envelope_20260727",
  source_csv_sha256 =
    "aa4399576453ec0e9eeb21fa2166a1aaeed977c976064b13c4dc27f963cbb9a1",
  source_manifest_sha256 =
    "64fe0d174b203f041b9047589a84345089106b20757755549662f82c5f301ba3",
  source_confirmation_sha256 =
    "a1ba1a9c25d2e0e3ee0c77958e23fca5beeb1fdbed89f6f09ff5a9f3a9a640f3",
  source_registry_hash =
    "edddb56fc2b30e49ac99fdd08b53dad468ed53e05d0fe1fe16426ee9d9ffe275",
  validation_branch = "validation/shared-fitforecast-v2-1.0.0",
  validation_package_version = "1.0.0",
  row_count_metric_envelope = "36",
  row_count_candidate_ledger = "129",
  displayed_envelope_changed_by_confirmation = "FALSE"
)
missing_keys <- setdiff(names(expected), names(manifest))
if (length(missing_keys)) {
  stop(
    sprintf(
      "Article manifest is missing required keys: %s",
      paste(missing_keys, collapse = ", ")
    ),
    call. = FALSE
  )
}
wrong <- names(expected)[manifest[names(expected)] != expected]
if (length(wrong)) {
  stop(
    sprintf(
      "Article manifest has incorrect frozen values: %s",
      paste(wrong, collapse = ", ")
    ),
    call. = FALSE
  )
}

input_keys <- c(
  source_csv = "source_csv_sha256",
  source_manifest = "source_manifest_sha256",
  source_confirmation = "source_confirmation_sha256",
  authority_freeze_manifest = "authority_freeze_manifest_sha256"
)
for (path_key in names(input_keys)) {
  hash_key <- input_keys[[path_key]]
  if (!path_key %in% names(manifest) || !hash_key %in% names(manifest)) {
    stop(sprintf("Missing input path/hash pair for %s.", path_key), call. = FALSE)
  }
  path <- manifest[[path_key]]
  if (!file.exists(path) || !identical(sha256(path), manifest[[hash_key]])) {
    stop(sprintf("Input verification failed for %s.", path_key), call. = FALSE)
  }
}

artifact_start <- match("artifact_sha256:", manifest_lines)
if (is.na(artifact_start) || artifact_start == length(manifest_lines)) {
  stop("Article manifest has no artifact hash section.", call. = FALSE)
}
artifact_lines <- manifest_lines[seq.int(artifact_start + 1L, length(manifest_lines))]
artifact_match <- regexec(
  "^  ([^:]+): ([0-9a-f]{64})$",
  artifact_lines,
  perl = TRUE
)
artifact_parts <- regmatches(artifact_lines, artifact_match)
artifact_parts <- artifact_parts[lengths(artifact_parts) == 3L]
artifact_names <- vapply(artifact_parts, `[[`, character(1L), 2L)
artifact_hashes <- vapply(artifact_parts, `[[`, character(1L), 3L)
expected_artifacts <- c(
  "qdesn_validation_tt500_final_mcmc_normal.tex",
  "qdesn_validation_tt500_final_mcmc_laplace.tex",
  "qdesn_validation_tt500_final_mcmc_gausmix.tex",
  "qdesn_validation_tt500_final_mcmc_tables.tex"
)
if (!setequal(artifact_names, expected_artifacts)) {
  stop("Article manifest does not pin the exact four table artifacts.", call. = FALSE)
}
artifact_paths <- file.path(repo_root, "tables", artifact_names)
if (!all(file.exists(artifact_paths)) ||
    !identical(unname(tools::sha256sum(artifact_paths)), artifact_hashes)) {
  stop("Article table artifact hash verification failed.", call. = FALSE)
}

source <- read.csv(
  manifest[["source_csv"]],
  check.names = FALSE,
  stringsAsFactors = FALSE
)
if (nrow(source) != 36L ||
    anyDuplicated(source[c("model_variant", "family", "tau")])) {
  stop("Numerical authority is not the complete 36-cell grid.", call. = FALSE)
}
models <- c(
  dqlm_c13_mcmc = "DQLM",
  exdqlm_c13_mcmc = "exDQLM",
  qdesn_al_rhs_ns = "Q-DESN AL--RHS",
  qdesn_exal_rhs_ns = "Q-DESN exAL--RHS"
)
metrics <- c(
  "fit_qtrue_rmse",
  "forecast_qtrue_mae_H1000",
  "forecast_check_loss_H1000"
)
taus <- c(0.05, 0.25, 0.50)
format_value <- function(value) {
  value <- as.numeric(value)
  if (abs(value) >= 10) sprintf("%.2f", value) else sprintf("%.3f", value)
}

checked <- 0L
for (family in c("normal", "laplace", "gausmix")) {
  table_path <- file.path(
    repo_root,
    "tables",
    paste0("qdesn_validation_tt500_final_mcmc_", family, ".tex")
  )
  lines <- readLines(table_path, warn = FALSE)
  if (!identical(
    lines[[1L]],
    "% Article-facing independent simulation MCMC table."
  ) ||
      !any(grepl("fixed case-specific calibration record", lines, fixed = TRUE)) ||
      !any(grepl("reproducibility record", lines, fixed = TRUE)) ||
      any(grepl("/home/jaguir26/local/src", lines, fixed = TRUE))) {
    stop(sprintf("Publication wording check failed for %s.", family), call. = FALSE)
  }
  for (variant in names(models)) {
    row <- lines[startsWith(lines, models[[variant]])]
    if (length(row) != 1L) {
      stop(sprintf("Expected one %s row for %s.", variant, family), call. = FALSE)
    }
    observed <- regmatches(
      row,
      gregexpr("[0-9]+(?:[.][0-9]+)?", row, perl = TRUE)
    )[[1L]]
    expected_values <- unname(unlist(lapply(taus, function(tau) {
      hit <- source[
        source$model_variant == variant &
          source$family == family &
          abs(as.numeric(source$tau) - tau) < 1e-12,
        ,
        drop = FALSE
      ]
      if (nrow(hit) != 1L) {
        stop("Numerical authority contains an incomplete table cell.", call. = FALSE)
      }
      vapply(
        hit[metrics],
        function(value) format_value(value[[1L]]),
        character(1L)
      )
    })))
    checked <- checked + length(expected_values)
    if (!identical(unname(observed), expected_values)) {
      stop(
        sprintf("Displayed values differ for %s/%s.", variant, family),
        call. = FALSE
      )
    }
  }
}
if (checked != 108L) {
  stop("Did not verify exactly 108 displayed values.", call. = FALSE)
}

active_text <- c(manifest_lines, unlist(lapply(artifact_paths, readLines)))
if (any(grepl("/home/jaguir26/local/src", active_text, fixed = TRUE))) {
  stop("Article authority contains a stale /home source path.", call. = FALSE)
}

cat("authority_inputs_verified: 4\n")
cat("article_artifacts_verified: 4\n")
cat("displayed_numeric_values_verified: 108\n")
cat("article_numeric_update: FALSE\n")
cat("result: PASS\n")
