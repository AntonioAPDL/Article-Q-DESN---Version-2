#!/usr/bin/env Rscript
arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(root, "application/R/glofas_search3_promotion_reconciliation.R"))
td <- tempfile("glofas-promotion-reconciliation-"); dir.create(td)
on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)
decision <- data.frame(status = "STRUCTURAL_INDEPENDENT_TAIL_PATH_TARGET_INCOHERENCE",
  local_delta_crossings = 13L, global_same_family_unit_crossings = 12L,
  maximum_local_global_mae = .041, convergence_or_monte_carlo_failure = FALSE,
  broad_refit_authorized = FALSE)
summary <- data.frame(status = "COHERENT_NORMAL_DRIVER_AUTHORITY_CONTRACT_PASS",
  banks = 3L, part123_forecasts = 48L, part123_fits_with_covariance = 48L,
  part4_fit_artifacts = 16L, part4_fit_cores = 28L, scoring_truth_reads = 0L,
  model_fits = 0L)
write.csv(decision, file.path(td, "decision.csv"), row.names = FALSE)
write.csv(summary, file.path(td, "summary.csv"), row.names = FALSE)
gpr_validate_root_cause(file.path(td, "decision.csv"), file.path(td, "summary.csv"))
bad <- decision; bad$broad_refit_authorized <- TRUE
write.csv(bad, file.path(td, "bad.csv"), row.names = FALSE)
stopifnot(inherits(try(gpr_validate_root_cause(file.path(td, "bad.csv"),
  file.path(td, "summary.csv")), silent = TRUE), "try-error"))
aliases <- paste(gpr_compatibility_aliases(), collapse = "\n")
stopifnot(all(vapply(c("CurrentFullComparisonFigure", "CurrentIssuedSupplementScoreTable",
  "CurrentNormalRidgeAcrps", "CurrentNormalRhsAcrps"), grepl, logical(1L),
  x = aliases, fixed = TRUE)))
writeLines("alpha", file.path(td, "a.txt"))
manifest <- data.frame(relative_path = "a.txt", size_bytes = file.info(file.path(td, "a.txt"))$size,
  sha256 = gpr_sha(file.path(td, "a.txt")))
write.csv(manifest, file.path(td, "manifest.csv"), row.names = FALSE)
gpr_verify_manifest(td, file.path(td, "manifest.csv"))
cat("GLOFAS_SEARCH3_PROMOTION_RECONCILIATION_TEST_PASS\n")
