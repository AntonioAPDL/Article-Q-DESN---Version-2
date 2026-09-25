#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))
args <- app_parse_args(list(root = app_joint_pure_default_root()))
root <- normalizePath(args$root, mustWork = TRUE)
if (basename(root) != "joint_qdesn_pure_recursive_campaign_jerez_15core_20260925") {
  stop("Recovery is restricted to the dedicated Jerez pure-recursive campaign root.", call. = FALSE)
}

quantile_done <- list.files(file.path(root, "families"), pattern = "^(DONE|FAILED)$",
  recursive = TRUE, full.names = TRUE)
if (length(quantile_done)) {
  stop("Recovery refuses to replace quantile staging after any quantile worker marker exists.", call. = FALSE)
}

incident <- file.path(root, "recovery_incident_20260925")
archive <- file.path(incident, "superseded_derived_selection")
app_ensure_dir(archive)
selection_files <- c(
  "rhs_scores_by_replicate.csv", "rhs_candidate_aggregate.csv", "selected_family_backbones.csv",
  "selection_decision.csv", "rhs_final_health.csv", "selection_artifact_manifest.csv",
  "selection_manifest_verification.csv", "quantile_family_plan.csv", "quantile_launch_readiness.csv"
)
for (name in selection_files) {
  source <- file.path(root, name)
  target <- file.path(archive, name)
  if (file.exists(source) && !file.exists(target) && !file.copy(source, target, copy.mode = TRUE)) {
    stop(sprintf("Could not archive superseded file %s.", source), call. = FALSE)
  }
}
log_files <- list.files(file.path(root, "logs"), pattern = "^quantile_stage_", full.names = TRUE)
for (source in log_files) {
  target <- file.path(archive, basename(source))
  if (!file.exists(target) && !file.copy(source, target, copy.mode = TRUE)) {
    stop(sprintf("Could not archive quantile launch log %s.", source), call. = FALSE)
  }
}

staged_paths <- c(
  list.files(file.path(root, "contracts"), pattern = "__quantile[.]csv$", full.names = TRUE),
  unlist(lapply(list.dirs(file.path(root, "families"), recursive = FALSE, full.names = TRUE), function(family) {
    c(list.files(file.path(family, "selection_parent"), recursive = TRUE, full.names = TRUE),
      list.files(file.path(family, "quantile_vb"), recursive = TRUE, full.names = TRUE))
  }), use.names = FALSE)
)
staged_paths <- unique(staged_paths[file.exists(staged_paths) & !dir.exists(staged_paths)])
inventory <- if (length(staged_paths)) data.frame(
  relative_path = substring(staged_paths, nchar(root) + 2L),
  size_bytes = as.numeric(file.info(staged_paths)$size),
  sha256 = unname(tools::sha256sum(staged_paths)), stringsAsFactors = FALSE
) else data.frame(relative_path = character(), size_bytes = numeric(), sha256 = character())
app_write_csv(inventory, file.path(incident, "superseded_quantile_staging_inventory.csv"))

repair <- app_joint_pure_repair_rhs_summaries(root)
app_write_csv(repair, file.path(incident, "rhs_summary_schema_repair_audit.csv"))
old_selected <- app_read_csv(file.path(archive, "selected_family_backbones.csv"))
app_joint_pure_finalize_rhs(root)
new_selected <- app_read_csv(file.path(root, "selected_family_backbones.csv"))
comparison <- merge(
  old_selected[, c("scenario_id", "candidate_id", "rhs_tau0", "calibration_acrps_mean")],
  new_selected[, c("scenario_id", "candidate_id", "rhs_tau0", "calibration_acrps_mean",
    "calibration_acrps_between_rep_sd", "convergence_fraction", "selection_metric")],
  by = "scenario_id", suffixes = c("_superseded", "_corrected")
)
comparison$candidate_changed <- comparison$candidate_id_superseded != comparison$candidate_id_corrected
comparison$tau0_changed <- comparison$rhs_tau0_superseded != comparison$rhs_tau0_corrected
app_write_csv(comparison, file.path(incident, "selection_correction_impact.csv"))

registry <- app_joint_pure_read_registry(file.path(root, "frozen_family_registry.csv"))
for (scenario in registry$scenario_id) {
  family <- file.path(root, "families", scenario)
  unlink(file.path(family, "selection_parent"), recursive = TRUE, force = TRUE)
  unlink(file.path(family, "quantile_vb"), recursive = TRUE, force = TRUE)
  unlink(file.path(root, "contracts", paste0(scenario, "__quantile.csv")), force = TRUE)
}
unlink(file.path(root, c("quantile_family_plan.csv", "quantile_launch_readiness.csv", "quantile_final_health.csv")), force = TRUE)
unlink(log_files, force = TRUE)

plan <- app_joint_pure_prepare_quantiles(root)
stage_counts <- do.call(rbind, lapply(seq_len(8L), function(stage) data.frame(
  stage_order = stage, jobs = nrow(app_joint_pure_quantile_job_queue(root, stage)), stringsAsFactors = FALSE
)))
expected_counts <- unname(app_joint_pure_quantile_stage_counts())
if (!identical(as.integer(stage_counts$jobs), as.integer(expected_counts)) || sum(stage_counts$jobs) != 408L) {
  stop("Regenerated quantile queues violate frozen stage cardinalities.", call. = FALSE)
}
app_write_csv(stage_counts, file.path(incident, "regenerated_quantile_stage_counts.csv"))
provenance <- cbind(app_joint_shared_git_state(), data.frame(
  recovery_status = "READY_TO_RESUME_AT_QUANTILE_VB",
  rhs_summaries_repaired = sum(repair$changed), selected_families = nrow(new_selected),
  quantile_jobs = sum(stage_counts$jobs), protected_rows_used_for_selection = max(new_selected$protected_rows_used_for_selection),
  recorded_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE), stringsAsFactors = FALSE
))
app_write_csv(provenance, file.path(incident, "recovery_status.csv"))
incident_outputs <- c(
  staging_inventory = file.path(incident, "superseded_quantile_staging_inventory.csv"),
  repair_audit = file.path(incident, "rhs_summary_schema_repair_audit.csv"),
  selection_impact = file.path(incident, "selection_correction_impact.csv"),
  stage_counts = file.path(incident, "regenerated_quantile_stage_counts.csv"),
  recovery_status = file.path(incident, "recovery_status.csv")
)
manifest <- app_joint_shared_write_manifest(incident, incident_outputs, filename = "recovery_artifact_manifest.csv")
verification <- app_joint_shared_verify_manifest(incident, manifest)
if (!all(verification$verified)) stop("Recovery artifact manifest failed verification.", call. = FALSE)
app_write_csv(verification, file.path(incident, "recovery_manifest_verification.csv"))
print(provenance)
