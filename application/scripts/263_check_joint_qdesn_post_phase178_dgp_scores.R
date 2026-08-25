#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."))
source(file.path(root, "application/R/00_packages.R")); app_set_repo_root(root)
source(app_path("application/scripts/_joint_exqdesn_phase176_180_bootstrap.R"))

cache_root <- app_joint_exqdesn_phase176_180_arg(
  "--cache-root", app_path("application/cache")
)
dirs <- app_joint_qdesn_postscore_dirs(cache_root)
contract_dir <- app_joint_exqdesn_phase176_180_arg(
  "--contract-dir", dirs$postscore_contract
)
audit_dir <- app_joint_exqdesn_phase176_180_arg(
  "--audit-dir", dirs$postscore_audit
)
contract_check <- app_joint_exqdesn_verify_manifest(contract_dir, "postscore_contract")
audit_check <- app_joint_exqdesn_verify_manifest(audit_dir, "postscore_audit")
assessment <- app_read_csv(file.path(audit_dir, "assessment.csv"))
decision <- app_read_csv(file.path(audit_dir, "decision_audit.csv"))
cat(sprintf(
  paste0(
    "Contract manifest: %d/%d pass\nAudit manifest: %d/%d pass\n",
    "Gate: %s\nDecisions: %d\nSelected non-parity: %d\n"
  ),
  sum(contract_check$status == "pass"), nrow(contract_check),
  sum(audit_check$status == "pass"), nrow(audit_check),
  assessment$gate_status[[1L]], nrow(decision), sum(!decision$selected_is_parity)
))
