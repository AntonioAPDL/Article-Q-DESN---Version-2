#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))

args <- app_parse_args(list(
  root = NA_character_, contract_path = NA_character_,
  recovery_contract_path = NA_character_, output_path = NA_character_
))
if (!identical(Sys.getenv("JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION"),
    "JEREZ_PURE_RECURSIVE_SCORE_REVIEW_V2")) {
  stop("Review-contract materialization lacks the exact authorization.",
    call. = FALSE)
}
root <- normalizePath(args$root, mustWork = TRUE)
contract_path <- normalizePath(
  args[["contract-path"]] %||% args$contract_path, mustWork = TRUE
)
recovery_path <- normalizePath(
  args[["recovery-contract-path"]] %||% args$recovery_contract_path,
  mustWork = TRUE
)
output_path <- args[["output-path"]] %||% args$output_path
if (is.na(output_path) || !nzchar(output_path)) {
  stop("--output-path is required.", call. = FALSE)
}

contract <- app_joint_recursive_read_contract(contract_path)
recovery <- app_joint_recursive_read_recovery_contract(recovery_path)
plan_path <- file.path(root, "cell_plan.csv")
plan <- app_read_csv(plan_path)
state <- vapply(plan$worker_id, function(worker_id) {
  directory <- app_joint_recursive_cell_dir(root, worker_id)
  if (file.exists(file.path(directory, "DONE"))) "complete" else
    if (file.exists(file.path(directory, "FAILED"))) "failed" else "pending"
}, character(1L))
if (!identical(c(sum(state == "complete"), sum(state == "failed"),
    sum(state == "pending")), c(63L, 1L, 0L)) ||
    !identical(plan$worker_id[state == "failed"], 41L)) {
  stop("Review contract requires exactly 63 complete and worker 41 failed.",
    call. = FALSE)
}
if (app_sha256_file(contract_path) != recovery$parent_contract_sha256 ||
    app_sha256_file(plan_path) != recovery$cell_plan_sha256) {
  stop("Strict recovery contract does not bind the current score packet.",
    call. = FALSE)
}
cell41 <- app_joint_recursive_cell_dir(root, 41L)
cell56 <- app_joint_recursive_cell_dir(root, 56L)
strict_root <- file.path(root, "score_recovery_v1")
paths <- c(
  failed_marker_sha256 = file.path(cell41, "FAILED"),
  failure_diagnostics_sha256 = file.path(cell41, "failure_diagnostics.csv"),
  stability_progress_sha256 = file.path(cell41, "stability_progress.csv"),
  original_failure_manifest_sha256 = file.path(
    strict_root, "original_worker_0041_failure_manifest.csv"),
  completed_worker_manifest_sha256 = file.path(cell56, "artifact_manifest.csv")
)
if (any(!file.exists(paths)) || !app_joint_recursive_manifest_ok(cell56)) {
  stop("Strict failure evidence or completed worker 56 is incomplete.",
    call. = FALSE)
}
hashes <- vapply(paths, app_sha256_file, character(1L))
rows <- list(
  c("identity", "review_version", "joint_qdesn_pure_recursive_score_review_closeout_v2", "character", "One-cell bounded review closeout after strict expanded recovery remained narrowly outside tolerance."),
  c("identity", "parent_contract_sha256", app_sha256_file(contract_path), "character", "SHA-256 of the unchanged expanded score contract."),
  c("identity", "cell_plan_sha256", app_sha256_file(plan_path), "character", "SHA-256 of the frozen expanded 64-cell score plan."),
  c("identity", "prior_recovery_contract_sha256", app_sha256_file(recovery_path), "character", "SHA-256 of the strict expanded antithetic recovery contract."),
  c("target", "recovery_worker_id", "41", "integer", "Laplace Bridge joint AL MCMC score cell."),
  c("target", "recovery_model_cell_id", "laplace_bridge__joint_qdesn_rhs", "character", "Exact frozen model-cell identity."),
  c("evidence", "failed_marker_sha256", hashes[["failed_marker_sha256"]], "character", "SHA-256 of the failed strict-recovery marker."),
  c("evidence", "failure_diagnostics_sha256", hashes[["failure_diagnostics_sha256"]], "character", "SHA-256 of strict-recovery failure diagnostics."),
  c("evidence", "stability_progress_sha256", hashes[["stability_progress_sha256"]], "character", "SHA-256 of strict-recovery stability progress."),
  c("evidence", "original_failure_manifest_sha256", hashes[["original_failure_manifest_sha256"]], "character", "SHA-256 of the archived original failure inventory."),
  c("evidence", "completed_worker_manifest_sha256", hashes[["completed_worker_manifest_sha256"]], "character", "SHA-256 of completed unchanged worker 56."),
  c("integration", "state_uniform_policy", "antithetic_uniform_pairs", "character", "Retain the two-pair antithetic state integration used by strict recovery."),
  c("integration", "antithetic_pair_count", "2", "integer", "Run only the strongest declared antithetic tier."),
  c("integration", "pair_seed_stride", "104729", "integer", "Preserve deterministic strict-recovery uniforms."),
  c("review", "score_gate_multiplier", "1.05", "numeric", "Review ceiling is at most five percent above the unchanged strict gate."),
  c("review", "max_pooled_score_relative_drift", "0.001", "numeric", "Maximum pooled canonical-score drift from the full-posterior reference."),
  c("review", "max_rms_gate_fraction", "0.25", "numeric", "Review RMS is at most one quarter of the unchanged RMS gate."),
  c("review", "max_chain_score_relative_deviation", "0.05", "numeric", "Maximum chain-specific score deviation from pooled."),
  c("review", "required_unique_posterior_draws", "3750", "integer", "Use every retained AL posterior draw from five chains."),
  c("review", "required_state_trajectory_draws", "15000", "integer", "Require two antithetic pairs per retained posterior draw."),
  c("policy", "strict_gate_remains_failed", "true", "logical", "Do not relabel the frozen 0.005 gate as passed."),
  c("policy", "posterior_draws_changed", "false", "logical", "Do not refit or extend MCMC."),
  c("policy", "model_specification_changed", "false", "logical", "Do not change DESN RHS fixture oracle or score definition."),
  c("policy", "packet_status", "COMPLETE_WITH_ONE_SCORE_STABILITY_REVIEW", "character", "Required transparent final packet status."),
  c("runtime", "workers", "1", "integer", "Only worker 41 is rerun."),
  c("runtime", "rscript", "/data/jaguir26/local/opt/R/4.6.0/bin/Rscript", "character", "Pinned Jerez R executable.")
)
tab <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
names(tab) <- c("section", "name", "value", "type", "description")
if (file.exists(output_path)) {
  prior <- app_read_csv(output_path)
  if (!identical(prior, tab)) stop("Existing review contract differs.", call. = FALSE)
} else {
  app_write_csv(tab, output_path)
}
app_joint_recursive_read_review_contract(output_path)
cat(sprintf("Wrote %s\nSHA-256 %s\n", normalizePath(output_path),
  app_sha256_file(output_path)))
