#!/usr/bin/env Rscript

cache <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
readiness <- file.path(cache, "joint_qdesn_phase163_tail_calibration_readiness_20260806")
screening <- file.path(cache, "joint_qdesn_phase163_tail_calibration_vb_20260806")
closure <- file.path(cache, "joint_qdesn_phase163b_corrected_closure_20260806")
registry <- read.csv(file.path(readiness, "phase163_candidate_registry.csv"), stringsAsFactors = FALSE)
done <- file.exists(file.path(registry$fit_dir, "artifact_manifest.csv")) &
  file.exists(file.path(registry$forecast_dir, "artifact_manifest.csv"))
cat(sprintf("Phase163 candidates complete: %d/%d; remaining: %d\n", sum(done), nrow(registry), sum(!done)))
if (file.exists(file.path(closure, "phase163b_assessment.csv"))) {
  cat("Authoritative decision: Phase163b inference-matched closure\n")
  print(read.csv(file.path(closure, "phase163b_assessment.csv")), row.names = FALSE)
} else if (file.exists(file.path(screening, "phase163_result_assessment.csv"))) {
  cat("WARNING: legacy Phase163 assessment is superseded; run script 215.\n")
  print(read.csv(file.path(screening, "phase163_result_assessment.csv")), row.names = FALSE)
}
