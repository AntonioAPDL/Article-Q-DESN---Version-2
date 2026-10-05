#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_pure_recursive_bootstrap.R"))

args <- app_parse_args(list(
  root = app_joint_pure_confirmation_root(),
  recovery_root = app_path("application/cache",
    "joint_qdesn_pure_recursive_mcmc_preflight_recovery_v1_20260928")
))
root <- normalizePath(args$root, mustWork = TRUE)
recovery_root <- normalizePath(
  args[["recovery-root"]] %||% args$recovery_root, mustWork = FALSE)
if (dir.exists(recovery_root) || file.exists(recovery_root)) {
  stop("MCMC preflight recovery root already exists.", call. = FALSE)
}

contract <- app_joint_article_read_contract(file.path(root,
  "frozen_contract.csv"))
app_joint_article_assert_clean_execution(contract, require_synced = TRUE)
app_joint_article_assert_capacity_authorized(contract)
host <- app_joint_article_host_preflight(contract)
completed <- app_joint_article_mcmc_completed_inventory(root)
compatible_commits <- unique(c(
  as.character(completed$execution_code_commit),
  app_joint_article_git_value(c("rev-parse", "HEAD"))
))

app_ensure_dir(recovery_root)
host_path <- app_write_csv(host, file.path(recovery_root,
  "recovery_host_preflight.csv"))
affinity <- attr(host, "cpu_affinity_mapping")
capacity <- attr(host, "shared_capacity_mapping")
if (is.data.frame(affinity)) {
  app_write_csv(affinity, file.path(recovery_root,
    "recovery_cpu_affinity.csv"))
}
if (is.data.frame(capacity)) {
  app_write_csv(capacity, file.path(recovery_root,
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
  failed_workers_audited = failure$assessment$failed_workers[[1L]],
  completed_workers_compatibility_audited =
    resume$assessment$completed_workers_audited[[1L]],
  completed_workers_retained = archive$status$completed_workers_retained[[1L]],
  pending_workers_ready = archive$status$pending_workers_after_recovery[[1L]],
  current_failures = archive$status$failed_workers_after_recovery[[1L]],
  recovery_root = recovery_root,
  execution_code_commit = app_joint_article_git_value(c("rev-parse", "HEAD")),
  completed_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  stringsAsFactors = FALSE
)
summary_path <- app_write_csv(summary, file.path(recovery_root,
  "recovery_summary.csv"))
top_paths <- c(recovery_host_preflight = host_path,
  recovery_summary = summary_path)
top_manifest <- app_joint_shared_write_manifest(recovery_root, top_paths,
  filename = "recovery_top_manifest.csv")
top_verification <- app_joint_shared_verify_manifest(recovery_root,
  top_manifest)
app_write_csv(top_verification, file.path(recovery_root,
  "recovery_top_manifest_verification.csv"))
if (any(!top_verification$verified)) {
  stop("Top-level MCMC preflight recovery manifest failed verification.",
    call. = FALSE)
}

print(summary)
cat(sprintf("MCMC preflight recovery is ready at: %s\n", recovery_root))
