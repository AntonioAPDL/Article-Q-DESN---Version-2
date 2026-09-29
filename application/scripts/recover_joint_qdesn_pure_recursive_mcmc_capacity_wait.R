#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_pure_recursive_bootstrap.R"))

args <- app_parse_args(list(
  root = app_joint_pure_confirmation_root(),
  recovery_root = app_path("application/cache",
    "joint_qdesn_pure_recursive_mcmc_capacity_wait_recovery_v2_20260929")
))
root <- normalizePath(args$root, mustWork = TRUE)
recovery_root <- normalizePath(
  args[["recovery-root"]] %||% args$recovery_root, mustWork = FALSE)
if (dir.exists(recovery_root) || file.exists(recovery_root)) {
  stop("MCMC capacity-wait recovery root already exists.", call. = FALSE)
}
if (dir.exists(file.path(root, "mcmc_queue.lock"))) {
  stop("MCMC capacity-wait recovery requires an inactive queue.",
    call. = FALSE)
}

contract <- app_joint_article_read_contract(file.path(root,
  "frozen_contract.csv"))
app_joint_article_assert_clean_execution(contract, require_synced = TRUE)
app_joint_article_assert_capacity_authorized(contract)

processes <- app_joint_article_process_table()
host_observation <- tryCatch(
  app_joint_article_host_preflight(contract, processes = processes),
  error = function(e) e
)
if (inherits(host_observation, "condition")) {
  failed_gates <- app_joint_article_host_preflight_failed_gates(
    host_observation)
  if (!inherits(host_observation, "joint_article_host_preflight_error") ||
      !identical(failed_gates, "competing_processes")) {
    stop(host_observation)
  }
  capacity_status <- "WAITING_FOR_DISJOINT_CAPACITY"
  host <- host_observation$preflight
  affinity <- host_observation$cpu_affinity_mapping
  capacity <- host_observation$shared_capacity_mapping
  host_error <- conditionMessage(host_observation)
} else {
  failed_gates <- character()
  capacity_status <- "CAPACITY_READY"
  host <- host_observation
  affinity <- attr(host_observation, "cpu_affinity_mapping")
  capacity <- attr(host_observation, "shared_capacity_mapping")
  host_error <- ""
}

completed <- app_joint_article_mcmc_completed_inventory(root)
compatible_commits <- unique(c(
  as.character(completed$execution_code_commit),
  app_joint_article_git_value(c("rev-parse", "HEAD"))
))

app_ensure_dir(recovery_root)
host_path <- app_write_csv(host, file.path(recovery_root,
  "recovery_host_preflight.csv"))
process_path <- app_write_csv(processes, file.path(recovery_root,
  "recovery_process_snapshot.csv"))
capacity_status_path <- app_write_csv(data.frame(
  status = capacity_status,
  failed_gates = paste(failed_gates, collapse = ";"),
  error_message = host_error,
  checked_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  stringsAsFactors = FALSE
), file.path(recovery_root, "recovery_capacity_status.csv"))
affinity_path <- capacity_path <- character()
if (is.data.frame(affinity)) {
  affinity_path <- app_write_csv(affinity, file.path(recovery_root,
    "recovery_cpu_affinity.csv"))
}
if (is.data.frame(capacity)) {
  capacity_path <- app_write_csv(capacity, file.path(recovery_root,
    "recovery_shared_capacity.csv"))
}

failure <- app_joint_article_write_mcmc_failure_audit(
  root,
  out_dir = file.path(recovery_root, "failure_audit")
)
resume <- app_joint_article_mcmc_resume_compatibility_audit(
  root,
  compatible_execution_commits = compatible_commits,
  out_dir = file.path(recovery_root, "resume_compatibility")
)
archive <- app_joint_article_archive_infrastructure_failures(
  root,
  failure_audit_dir = failure$out_dir,
  resume_compatibility_dir = resume$out_dir,
  out_dir = file.path(recovery_root, "retry_archive")
)

summary <- data.frame(
  status = archive$status$status[[1L]],
  capacity_status = capacity_status,
  failed_workers_audited = failure$assessment$failed_workers[[1L]],
  completed_workers_compatibility_audited =
    resume$assessment$completed_workers_audited[[1L]],
  completed_workers_retained = archive$status$completed_workers_retained[[1L]],
  pending_workers_ready = archive$status$pending_workers_after_recovery[[1L]],
  current_failures = archive$status$failed_workers_after_recovery[[1L]],
  frozen_contract_sha256 = app_sha256_file(file.path(root,
    "frozen_contract.csv")),
  recovery_root = recovery_root,
  execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
  completed_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  stringsAsFactors = FALSE
)
summary_path <- app_write_csv(summary, file.path(recovery_root,
  "recovery_summary.csv"))
top_paths <- c(
  recovery_host_preflight = host_path,
  recovery_process_snapshot = process_path,
  recovery_capacity_status = capacity_status_path,
  recovery_summary = summary_path,
  failure_audit_manifest = file.path(failure$out_dir,
    "artifact_manifest.csv"),
  resume_compatibility_manifest = file.path(resume$out_dir,
    "artifact_manifest.csv"),
  retry_archive_manifest = file.path(archive$out_dir,
    "artifact_manifest.csv")
)
if (length(affinity_path)) {
  top_paths <- c(top_paths, recovery_cpu_affinity = affinity_path)
}
if (length(capacity_path)) {
  top_paths <- c(top_paths, recovery_shared_capacity = capacity_path)
}
top_manifest <- app_joint_shared_write_manifest(recovery_root, top_paths,
  filename = "recovery_top_manifest.csv")
top_verification <- app_joint_shared_verify_manifest(recovery_root,
  top_manifest)
app_write_csv(top_verification, file.path(recovery_root,
  "recovery_top_manifest_verification.csv"))
if (any(!top_verification$verified)) {
  stop("Top-level MCMC capacity-wait recovery manifest failed verification.",
    call. = FALSE)
}

print(summary)
cat(sprintf("MCMC capacity-wait recovery is ready at: %s\n", recovery_root))
