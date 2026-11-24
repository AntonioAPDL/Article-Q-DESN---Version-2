#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/R"))) normalizePath(getwd()) else {
  file_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
source(file.path(repo_root, "application/scripts",
  "_joint_qdesn_persistent_tail_exploration_v3_bootstrap.R"))
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) normalizePath(args[[1L]], mustWork = TRUE) else
  app_joint_pht3_default_root()
contract <- app_joint_pht3_read_contract(file.path(root, "frozen_v3_contract.csv"))
manifest <- app_joint_shared_verify_manifest(root, file.path(root, "preparation_manifest.csv"))
candidates <- app_read_csv(file.path(root, "candidate_registry.csv"))
fixtures <- app_read_csv(file.path(root, "fixture_manifest.csv"))
expected <- app_read_csv(file.path(root, "expected_work.csv"))
if (!all(manifest$verified) || nrow(candidates) != contract$candidate_count ||
    any(candidates$scenario_id != contract$scenario_id) ||
    any(candidates$retained_state_budget > 80L) ||
    any(candidates$joint_dense_dimension > contract$maximum_joint_dense_dimension) ||
    any(vapply(candidates$alpha,
      function(x) any(app_joint_shared_parse_num_vec(x) >= 1), logical(1L))) ||
    nrow(app_read_csv(file.path(root, "n0_worker_plan.csv"))) != expected$n0_workers ||
    nrow(app_read_csv(file.path(root, "a1_worker_plan.csv"))) != expected$a1_workers ||
    any(fixtures$protected_rows_persisted != 0L) ||
    any(app_as_bool_vec(fixtures$materialized[fixtures$panel == "confirmation"]))) {
  stop("Persistent-tail v3 preparation check failed.", call. = FALSE)
}
health <- app_joint_pht3_all_health(root)
if (any(health$failed > 0L)) stop("A persistent-tail v3 worker stage contains failures.", call. = FALSE)
print(health)
cat("Persistent-tail v3 preparation and health checks passed.\n")
