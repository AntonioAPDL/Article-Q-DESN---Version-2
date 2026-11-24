#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts", "_joint_qdesn_persistent_tail_targeted_bootstrap.R"))
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) normalizePath(args[[1L]], mustWork = TRUE) else app_joint_pht_default_root()
target <- app_joint_pht_read_contract(file.path(root, "frozen_target_contract.csv"))
manifest <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
candidates <- app_read_csv(file.path(root, "candidate_registry.csv"))
fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
if (!all(manifest$verified) || nrow(candidates) != target$candidate_count ||
    any(candidates$scenario_id != target$scenario_id) || max(candidates$rho_requested_max) > 1.2 ||
    sum(candidates$rho_requested_max >= 1) != target$supercritical_count ||
    any(candidates$rho_requested_max[candidates$candidate_role != "supercritical_rho"] >= 1) ||
    nrow(app_read_csv(file.path(root, "r1a_worker_plan.csv"))) !=
      target$candidate_count * target$calibration_replicates ||
    any(fixtures$protected_rows_persisted != 0L)) {
  stop("Persistent-tail targeted preparation check failed.", call. = FALSE)
}
health <- app_joint_pht_health(root)
if (any(health$failed > 0L)) stop("A targeted worker stage contains failures.", call. = FALSE)
print(health)
cat("Persistent-tail targeted preparation and health checks passed.\n")
