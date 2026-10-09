#!/usr/bin/env Rscript

# Portable positive and fail-closed mutation checks. All mutations are confined
# to disposable temporary copies; no scientific source or runtime is edited.
local({
  root <- normalizePath(getwd(), mustWork = TRUE)
  checker <- file.path(root, "scripts/check_joint_qdesn_pure_desn_article_projection_v2.R")
  rscript <- file.path(R.home("bin"), "Rscript")
  marker <- "JOINT_PURE_DESN_ARTICLE_PROJECTION_V2_CHECK=PASS"
  run <- function(directory, data_only = FALSE) {
    output <- suppressWarnings(system2(rscript,
      c(shQuote(checker), "--repo-root", shQuote(directory), if (data_only) "--data-only"),
      stdout = TRUE, stderr = TRUE))
    status <- attr(output, "status")
    if (is.null(status)) status <- 0L
    list(status = as.integer(status), output = output)
  }
  passed <- run(root)
  if (passed$status != 0L || !any(startsWith(passed$output, marker))) {
    stop(paste(c("Current v2 projection failed its complete validation:", passed$output), collapse = "\n"))
  }
  receipt <- passed$output[startsWith(passed$output, marker)]
  temporary <- tempfile("joint_projection_v2_mutations_")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
  files <- list.files(file.path(root, "tables"), pattern = "^joint_qdesn_pure_desn_v[12]_.*[.]csv$",
                      full.names = TRUE)
  pristine <- file.path(temporary, "unmodified_copy")
  dir.create(file.path(pristine, "tables"), recursive = TRUE)
  stopifnot(all(file.copy(files, file.path(pristine, "tables"))))
  pristine_result <- run(pristine, data_only = TRUE)
  stopifnot(pristine_result$status == 0L,
            any(startsWith(pristine_result$output, marker)))
  mutate <- function(label, suffix, version = "v2", change, expected_failure) {
    directory <- file.path(temporary, label)
    dir.create(file.path(directory, "tables"), recursive = TRUE)
    stopifnot(all(file.copy(files, file.path(directory, "tables"))))
    target <- file.path(directory, "tables", paste0("joint_qdesn_pure_desn_", version, "_", suffix, ".csv"))
    x <- read.csv(target, check.names = FALSE, stringsAsFactors = FALSE)
    x <- change(x)
    # Preserve double round trips in all unaffected rows, so a rejection must
    # arise from the intended mutation rather than accidental CSV rounding.
    encoded <- x
    for (column in names(encoded)) if (is.numeric(encoded[[column]])) {
      encoded[[column]] <- ifelse(is.na(encoded[[column]]), NA_character_,
                                 sprintf("%.17g", encoded[[column]]))
    }
    write.csv(encoded, target, row.names = FALSE, na = "")
    result <- run(directory, data_only = TRUE)
    stopifnot(result$status != 0L, !any(startsWith(result$output, marker)),
              any(grepl("JOINT_PURE_DESN_V2_CHECK_FAILED:", result$output, fixed = TRUE)),
              any(grepl(expected_failure, result$output, fixed = TRUE)))
    cat(sprintf("V2_MUTATION_REJECTED=%s\n", label))
  }
  mutate("immutable_v1_tamper", "forecast_score_summary", "v1", function(x) {
    x$posterior_score_mean[[1L]] <- x$posterior_score_mean[[1L]] + .01; x
  }, expected_failure = "Immutable historical scientific source")
  mutate("non_laplace_target_change", "forecast_score_summary", change = function(x) {
    x$posterior_score_mean[x$scenario_id != "laplace_bridge"][1L] <- 999; x
  }, expected_failure = "Unchanged seven-scenario values forecast_score_summary posterior_score_mean")
  mutate("lost_laplace_method_row", "forecast_score_summary", change = function(x) {
    x[-which(x$scenario_id == "laplace_bridge")[[1L]], , drop = FALSE]
  }, expected_failure = "Complete coherent 64-row method--model surface")
  mutate("exal_silent_thinning", "draw_cardinality", change = function(x) {
    at <- x$scenario_id == "laplace_bridge" & x$inference_method == "mcmc" &
      grepl("exqdesn", x$model_cell_id)
    x$n_score_draws[at] <- 3750L; x
  }, expected_failure = "Exact per-cell draw cardinalities")
  mutate("wrong_handoff_arithmetic", "forecast_score_summary", change = function(x) {
    at <- x$scenario_id == "laplace_bridge" & x$inference_method == "mcmc" &
      x$model_id == "qdesn_rhs_independent_mcmc"
    x$canonical_raw_crossing_pairs[at] <- 2L; x
  }, expected_failure = "Draw-wise and posterior-mean crossing summaries")
  mutate("stale_laplace_rmse", "fit_oracle_diagnostics", change = function(x) {
    at <- x$scenario_id == "laplace_bridge" & x$inference_method == "mcmc"
    x$fit_oracle_rmse[at] <- x$fit_oracle_mae[at] - .01; x
  }, expected_failure = "Fit diagnostics contain genuine MAE and RMSE")
  mutate("changed_prior_target_hash", "mcmc_posterior_target_hash_audit", change = function(x) {
    at <- startsWith(x$model_cell_id, "laplace_bridge__")
    x$verified[at] <- FALSE; x
  }, expected_failure = "All 32 five-chain posterior targets are verified")
  mutate("stale_stability_review", "forecast_score_summary", change = function(x) {
    at <- x$scenario_id == "laplace_bridge" & x$inference_method == "mcmc"
    x$score_stability_status[at] <- "review"; x
  }, expected_failure = "All 32 MCMC score-stability assessments pass")
  mutate("relaxed_original_stability_gate", "state_stability_audit", change = function(x) {
    x$half_canonical_score_relative_difference[[1L]] <- .006; x
  }, expected_failure = "All eight replacements meet the original finite/RMS/canonical-half-score stability criteria")
  mutate("unvalidated_path_reconstruction", "postprocessing_provenance", change = function(x) {
    x$value[x$name == "native_path_reference_max_difference"] <- "0.01"; x
  }, expected_failure = "Frozen fit reuse, complete draws, partial VB and native path equivalence are documented")
  mutate("changed_frozen_contrast_percentiles", "postprocessing_provenance", change = function(x) {
    x$value[x$name == "contrast_percentile_type"] <- "8"; x
  }, expected_failure = "Frozen Laplace contrast percentiles are distinguished from score and historical percentile conventions")
  # Complete-article mutations additionally prove that numerical checks alone
  # cannot authorize a stale asset receipt or historical Overleaf projection.
  manifest_path <- "tables/joint_qdesn_pure_desn_v2_article_asset_manifest.csv"
  manifest <- read.csv(file.path(root, manifest_path), stringsAsFactors = FALSE)
  allowlist <- trimws(readLines(file.path(root, "overleaf/article_files.txt"), warn = FALSE))
  allowlist <- allowlist[nzchar(allowlist) & !startsWith(allowlist, "#")]
  additional_files <- unique(c("main.tex", "qdesn-supplement.tex", "overleaf/article_files.txt",
    "scripts/reconstruct_joint_qdesn_laplace_article_projection_v2.R",
    manifest$relative_path, allowlist))
  for (relative in additional_files) {
    target <- file.path(pristine, relative)
    if (!file.exists(target)) {
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      stopifnot(file.copy(file.path(root, relative), target))
    }
  }
  full_pristine <- run(pristine)
  stopifnot(full_pristine$status == 0L, any(startsWith(full_pristine$output, marker)))
  copied_manifest <- file.path(pristine, manifest_path)
  original_manifest_lines <- readLines(copied_manifest, warn = FALSE)
  bad_manifest <- manifest
  bad_manifest$sha256[[1L]] <- paste(rep("0", 64), collapse = "")
  write.csv(bad_manifest, copied_manifest, row.names = FALSE, na = "")
  bad_receipt <- run(pristine)
  stopifnot(bad_receipt$status != 0L, !any(startsWith(bad_receipt$output, marker)),
            any(grepl("Registered asset hash", bad_receipt$output, fixed = TRUE)))
  cat("V2_MUTATION_REJECTED=stale_article_asset_manifest\n")
  writeLines(original_manifest_lines, copied_manifest, useBytes = TRUE)
  copied_allowlist <- file.path(pristine, "overleaf/article_files.txt")
  original_allowlist_lines <- readLines(copied_allowlist, warn = FALSE)
  writeLines(c(original_allowlist_lines, "tables/joint_qdesn_pure_desn_v1_forecast_figure.tex"),
             copied_allowlist, useBytes = TRUE)
  bad_projection <- run(pristine)
  stopifnot(bad_projection$status != 0L, !any(startsWith(bad_projection$output, marker)),
            any(grepl("Historical JOINT article outputs are excluded", bad_projection$output, fixed = TRUE)))
  cat("V2_MUTATION_REJECTED=stale_overleaf_projection\n")
  cat(paste(receipt, collapse = "\n"), "\n")
  cat("test_joint_qdesn_pure_desn_article_projection_v2: PASS mutations=13 runtime_reads=0\n")
})
