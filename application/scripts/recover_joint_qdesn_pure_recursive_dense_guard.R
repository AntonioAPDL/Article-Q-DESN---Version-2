#!/usr/bin/env Rscript
source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))

args <- app_parse_args(list(
  root = app_joint_pure_default_root(),
  controller_root = app_path(
    "application/cache/joint_qdesn_pure_recursive_controller_recovery_20260925"
  )
))
root <- normalizePath(args$root, mustWork = TRUE)
controller_root <- normalizePath(
  args[["controller-root"]] %||% args$controller_root, mustWork = TRUE
)
if (basename(root) != "joint_qdesn_pure_recursive_campaign_jerez_15core_20260925") {
  stop("Dense-guard recovery is restricted to the dedicated Jerez campaign root.", call. = FALSE)
}
if (file.exists(file.path(root, "quantile_final_health.csv"))) {
  stop("Dense-guard recovery refuses a finalized quantile campaign.", call. = FALSE)
}

incident <- file.path(root, "dense_guard_incident_20260925")
status_path <- file.path(incident, "dense_guard_recovery_status.csv")
if (file.exists(status_path)) {
  status <- app_read_csv(status_path)
  if (identical(status$status[[1L]], "READY_TO_RESUME_36_QUANTILE_JOBS")) {
    print(status)
    quit(save = "no", status = 0L)
  }
  stop("An incomplete dense-guard incident directory already exists.", call. = FALSE)
}

health <- app_joint_pure_quantile_health(root)
if (health$expected[[1L]] != 408L || health$completed[[1L]] != 372L ||
    health$failed[[1L]] != 6L || health$remaining[[1L]] != 30L) {
  stop("Dense-guard recovery requires the audited 372 complete / 6 failed / 30 pending state.", call. = FALSE)
}

family_plan <- app_read_csv(file.path(root, "quantile_family_plan.csv"))
selected <- app_read_csv(file.path(root, "selected_family_backbones.csv"))
registry <- app_joint_pure_read_registry(file.path(root, "frozen_family_registry.csv"))
if (nrow(family_plan) != 8L || nrow(selected) != 8L || anyDuplicated(selected$scenario_id)) {
  stop("Dense-guard recovery source cardinality is malformed.", call. = FALSE)
}

app_ensure_dir(incident)
archive <- file.path(incident, "pre_amendment_archive")
app_ensure_dir(archive)

copy_one <- function(path, destination) {
  if (!file.exists(path)) return(invisible(FALSE))
  app_ensure_dir(dirname(destination))
  if (!file.copy(path, destination, copy.mode = TRUE, copy.date = TRUE)) {
    stop(sprintf("Could not archive %s.", path), call. = FALSE)
  }
  invisible(TRUE)
}

pre_rows <- completed_rows <- failure_rows <- list()
for (ii in seq_len(nrow(family_plan))) {
  scenario <- family_plan$scenario_id[[ii]]
  qroot <- normalizePath(family_plan$quantile_root[[ii]], mustWork = TRUE)
  contract_path <- file.path(qroot, "frozen_contract.csv")
  contract <- app_joint_shared_quantile_read_contract(contract_path)
  candidate <- selected[selected$scenario_id == scenario, , drop = FALSE]
  audit <- app_joint_pure_dense_dimension_audit(candidate, contract$tau, contract$max_dense_dim)
  plan <- app_read_csv(file.path(qroot, "worker_plan.csv"))
  dirs <- vapply(plan$job_id, function(id) app_joint_shared_quantile_worker_dir(qroot, id), character(1L))
  done <- file.exists(file.path(dirs, "DONE")) & file.exists(file.path(dirs, "artifact_manifest.csv"))
  failed <- file.exists(file.path(dirs, "FAILED")) | file.exists(file.path(dirs, "failure.csv"))

  preparation_verification <- app_joint_shared_verify_manifest(
    qroot, file.path(qroot, "artifact_manifest.csv")
  )
  if (!all(preparation_verification$verified)) {
    stop(sprintf("Pre-amendment preparation manifest failed for %s.", scenario), call. = FALSE)
  }
  for (job_index in which(done)) {
    worker_verification <- app_joint_shared_verify_manifest(
      dirs[[job_index]], file.path(dirs[[job_index]], "artifact_manifest.csv")
    )
    if (!all(worker_verification$verified)) {
      stop(sprintf("Completed worker manifest failed for %s job %d.",
        scenario, plan$job_id[[job_index]]), call. = FALSE)
    }
    job_K <- if (plan$model_id[[job_index]] %in% c("joint_qdesn_rhs", "joint_exqdesn_rhs")) {
      length(contract$tau)
    } else 1L
    required <- job_K * audit$reservoir_state_dimension[[1L]]
    completed_rows[[length(completed_rows) + 1L]] <- data.frame(
      scenario_id = scenario, job_id = plan$job_id[[job_index]],
      model_id = plan$model_id[[job_index]], required_beta_dimension = required,
      old_max_dense_dim = contract$max_dense_dim,
      old_limit_was_nonbinding = required <= contract$max_dense_dim,
      stringsAsFactors = FALSE
    )
  }
  if (any(failed)) {
    for (job_index in which(failed)) {
      failure_path <- file.path(dirs[[job_index]], "failure.csv")
      failure <- app_read_csv(failure_path)
      failure_rows[[length(failure_rows) + 1L]] <- data.frame(
        scenario_id = scenario, job_id = plan$job_id[[job_index]],
        stage_order = plan$stage_order[[job_index]], model_id = plan$model_id[[job_index]],
        error_message = failure$error_message[[1L]], stringsAsFactors = FALSE
      )
    }
  }
  pre_rows[[length(pre_rows) + 1L]] <- data.frame(
    scenario_id = scenario, quantile_root = qroot,
    old_max_dense_dim = contract$max_dense_dim,
    required_joint_beta_dimension = audit$required_joint_beta_dimension[[1L]],
    resolved_max_dense_dim = audit$resolved_max_dense_dim[[1L]],
    dense_covariance_bytes_estimate = audit$dense_covariance_bytes_estimate[[1L]],
    completed_jobs = sum(done), failed_jobs = sum(failed), pending_jobs = sum(!done & !failed),
    stringsAsFactors = FALSE
  )
}
pre_audit <- app_bind_rows_fill(pre_rows)
completed_audit <- app_bind_rows_fill(completed_rows)
failures <- app_bind_rows_fill(failure_rows)
affected <- pre_audit$scenario_id[pre_audit$required_joint_beta_dimension > pre_audit$old_max_dense_dim]
expected_affected <- c("asymmetric_laplace_tail", "laplace_bridge")
if (!identical(sort(affected), sort(expected_affected)) || nrow(failures) != 6L ||
    any(failures$stage_order != 7L) || any(failures$model_id != "joint_qdesn_rhs") ||
    any(!completed_audit$old_limit_was_nonbinding)) {
  stop("Dense-guard failure surface differs from the audited incident.", call. = FALSE)
}

copy_one(file.path(root, "quantile_launch_readiness.csv"),
  file.path(archive, "quantile_launch_readiness.csv"))
for (path in list.files(file.path(root, "logs"), pattern = "^quantile_stage_7_", full.names = TRUE)) {
  copy_one(path, file.path(archive, "logs", basename(path)))
}
for (path in list.files(controller_root, full.names = TRUE)) {
  if (!dir.exists(path)) copy_one(path, file.path(archive, "controller", basename(path)))
}
for (scenario in affected) {
  qroot <- pre_audit$quantile_root[pre_audit$scenario_id == scenario]
  copy_one(file.path(root, "contracts", paste0(scenario, "__quantile.csv")),
    file.path(archive, "contracts", paste0(scenario, "__quantile.csv")))
  copy_one(file.path(qroot, "frozen_contract.csv"),
    file.path(archive, "families", scenario, "frozen_contract.csv"))
  copy_one(file.path(qroot, "artifact_manifest.csv"),
    file.path(archive, "families", scenario, "artifact_manifest.csv"))
  copy_one(file.path(qroot, "launch_readiness.csv"),
    file.path(archive, "families", scenario, "launch_readiness.csv"))
  failed_dirs <- unique(dirname(c(
    Sys.glob(file.path(qroot, "workers", "worker_*", "FAILED")),
    Sys.glob(file.path(qroot, "workers", "worker_*", "failure.csv"))
  )))
  for (worker_dir in failed_dirs) {
    target_parent <- file.path(archive, "families", scenario, "failed_workers")
    app_ensure_dir(target_parent)
    if (!file.copy(worker_dir, target_parent, recursive = TRUE, copy.mode = TRUE, copy.date = TRUE)) {
      stop(sprintf("Could not archive failed worker %s.", worker_dir), call. = FALSE)
    }
  }
}

archive_files <- list.files(archive, recursive = TRUE, full.names = TRUE)
archive_files <- archive_files[file.exists(archive_files) & !dir.exists(archive_files)]
archive_inventory <- data.frame(
  relative_path = substring(archive_files, nchar(incident) + 2L),
  size_bytes = as.numeric(file.info(archive_files)$size),
  sha256 = unname(tools::sha256sum(archive_files)),
  stringsAsFactors = FALSE
)
if (!nrow(archive_inventory)) stop("Dense-guard archive is empty.", call. = FALSE)
app_write_csv(archive_inventory, file.path(incident, "pre_amendment_archive_inventory.csv"))

amendments <- list()
for (scenario in affected) {
  candidate <- selected[selected$scenario_id == scenario, , drop = FALSE]
  qroot <- pre_audit$quantile_root[pre_audit$scenario_id == scenario]
  top_contract_path <- file.path(root, "contracts", paste0(scenario, "__quantile.csv"))
  qroot_contract_path <- file.path(qroot, "frozen_contract.csv")
  old_contract <- app_joint_shared_quantile_read_contract(qroot_contract_path)
  new_table <- app_joint_pure_apply_dense_dimension_contract(
    old_contract$table, candidate, old_contract$tau
  )
  new_table <- app_joint_pure_append_contract_value(
    new_table, "provenance", "dense_guard_amendment_head",
    app_joint_article_git_value(c("rev-parse", "HEAD")), "character",
    "Code commit that applied the post-failure computational-guard amendment."
  )
  app_write_csv(new_table, qroot_contract_path)
  app_write_csv(new_table, top_contract_path)
  new_contract <- app_joint_shared_quantile_read_contract(qroot_contract_path)
  design_manifest <- app_read_csv(file.path(qroot, "design_manifest.csv"))
  dense_audit <- app_joint_shared_quantile_dense_dimension_audit(design_manifest, new_contract)
  dense_audit_path <- app_write_csv(
    dense_audit, file.path(qroot, "dense_dimension_audit.csv")
  )
  readiness <- app_read_csv(file.path(qroot, "launch_readiness.csv"))
  readiness$required_joint_beta_dimension <- max(dense_audit$joint_beta_dimension)
  readiness$max_dense_dim <- new_contract$max_dense_dim
  readiness$dense_guard_recovery_status <- "amended_before_joint_vb"
  app_write_csv(readiness, file.path(qroot, "launch_readiness.csv"))

  old_manifest <- app_read_csv(file.path(qroot, "artifact_manifest.csv"))
  manifest_paths <- file.path(qroot, old_manifest$relative_path)
  names(manifest_paths) <- old_manifest$label
  manifest_paths <- c(manifest_paths[names(manifest_paths) != "dense_dimension_audit"],
    dense_dimension_audit = dense_audit_path)
  app_joint_shared_write_manifest(qroot, manifest_paths, filename = "artifact_manifest.csv")
  verification <- app_joint_shared_verify_manifest(qroot, file.path(qroot, "artifact_manifest.csv"))
  if (!all(verification$verified)) {
    stop(sprintf("Amended preparation manifest failed for %s.", scenario), call. = FALSE)
  }
  amendments[[length(amendments) + 1L]] <- data.frame(
    scenario_id = scenario,
    old_max_dense_dim = old_contract$max_dense_dim,
    new_max_dense_dim = new_contract$max_dense_dim,
    required_joint_beta_dimension = max(dense_audit$joint_beta_dimension),
    posterior_target_changed = FALSE,
    stringsAsFactors = FALSE
  )
}

for (scenario in affected) {
  qroot <- pre_audit$quantile_root[pre_audit$scenario_id == scenario]
  failed_dirs <- unique(dirname(c(
    Sys.glob(file.path(qroot, "workers", "worker_*", "FAILED")),
    Sys.glob(file.path(qroot, "workers", "worker_*", "failure.csv"))
  )))
  unlink(failed_dirs, recursive = TRUE, force = TRUE)
}

global_readiness <- app_read_csv(file.path(root, "quantile_launch_readiness.csv"))
global_readiness$required_joint_beta_dimension <- max(pre_audit$required_joint_beta_dimension)
global_readiness$resolved_max_dense_dim <- max(pre_audit$resolved_max_dense_dim)
global_readiness$dense_guard_recovery_status <- "READY_TO_RESUME_36_QUANTILE_JOBS"
app_write_csv(global_readiness, file.path(root, "quantile_launch_readiness.csv"))

post_health <- app_joint_pure_quantile_health(root)
if (post_health$completed[[1L]] != 372L || post_health$failed[[1L]] != 0L ||
    post_health$remaining[[1L]] != 36L) {
  stop("Dense-guard recovery did not produce the expected resumable state.", call. = FALSE)
}

app_write_csv(pre_audit, file.path(incident, "dense_dimension_pre_audit.csv"))
app_write_csv(completed_audit, file.path(incident, "completed_worker_nonbinding_audit.csv"))
app_write_csv(failures, file.path(incident, "failed_worker_audit.csv"))
app_write_csv(app_bind_rows_fill(amendments), file.path(incident, "contract_amendments.csv"))
app_write_csv(post_health, file.path(incident, "post_recovery_quantile_health.csv"))
status <- cbind(app_joint_shared_git_state(), data.frame(
  status = "READY_TO_RESUME_36_QUANTILE_JOBS",
  completed_jobs_preserved = post_health$completed[[1L]],
  failed_jobs_cleared = 6L,
  jobs_to_execute = post_health$remaining[[1L]],
  affected_families = paste(sort(affected), collapse = ";"),
  posterior_target_changed = FALSE,
  recorded_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  stringsAsFactors = FALSE
))
app_write_csv(status, status_path)

incident_outputs <- c(
  archive_inventory = file.path(incident, "pre_amendment_archive_inventory.csv"),
  dense_pre_audit = file.path(incident, "dense_dimension_pre_audit.csv"),
  completed_nonbinding_audit = file.path(incident, "completed_worker_nonbinding_audit.csv"),
  failed_worker_audit = file.path(incident, "failed_worker_audit.csv"),
  contract_amendments = file.path(incident, "contract_amendments.csv"),
  post_recovery_health = file.path(incident, "post_recovery_quantile_health.csv"),
  recovery_status = status_path
)
manifest <- app_joint_shared_write_manifest(
  incident, incident_outputs, filename = "dense_guard_recovery_manifest.csv"
)
verification <- app_joint_shared_verify_manifest(incident, manifest)
if (!all(verification$verified)) {
  stop("Dense-guard recovery manifest failed verification.", call. = FALSE)
}
app_write_csv(verification, file.path(incident, "dense_guard_recovery_manifest_verification.csv"))
print(status)
