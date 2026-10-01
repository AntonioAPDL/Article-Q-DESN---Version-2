#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "..", "scripts", "_joint_qdesn_pure_recursive_bootstrap.R"))

empty_process_table <- data.frame(
  pid = integer(), ppid = integer(), command = character(),
  stringsAsFactors = FALSE
)
test_contract <- list(
  version = "test_host_preflight_v1",
  run_tag = "test_host_preflight",
  source_worktree = app_repo_root(),
  initial_concurrency = 1L,
  maximum_concurrency = 1L,
  min_data_free_gib = 0,
  blas_threads = 1L,
  allowed_competing_process_patterns = character(),
  cpu_affinity_list = "",
  required_physical_cores = NA_integer_,
  shared_capacity_mode = "",
  pricefm_reserved_cpu_list = "",
  glofas_spare_cpu_list = "",
  spare_cpu_list = ""
)

topology_root <- tempfile("joint_disjoint_process_topology_")
for (cpu in 0:3) {
  topology <- file.path(topology_root, sprintf("cpu%d", cpu), "topology")
  dir.create(topology, recursive = TRUE)
  writeLines(as.character(cpu %% 2L), file.path(topology,
    "physical_package_id"))
  writeLines(as.character(cpu %/% 2L), file.path(topology, "core_id"))
}
shared_contract <- test_contract
shared_contract$shared_capacity_mode <- "pricefm_r120_jerez_partition"
shared_contract$cpu_affinity_list <- "1,3"
shared_contract$allowed_competing_process_patterns <- "pricefm_frozen_stage"
shared_processes <- data.frame(
  pid = c(10L, 11L, 12L),
  ppid = c(1L, 10L, 1L),
  command = c(
    "python application/scripts/pricefm/427_run_pricefm_stage.py --cpu-list 0,2",
    "R --file=application/scripts/pricefm/420_fit_pricefm_atom.R",
    "R --file=application/scripts/pricefm/orphan_worker.R"
  ),
  stringsAsFactors = FALSE
)
shared_affinity <- data.frame(
  pid = shared_processes$pid,
  cpu_affinity_list = c("0-3", "2", "3"),
  cpu_affinity_read_ok = TRUE,
  stringsAsFactors = FALSE
)
shared_audit <- app_joint_article_disjoint_competing_process_audit(
  shared_processes, shared_contract, process_affinity = shared_affinity,
  sysfs_root = topology_root)
stopifnot(
  nrow(shared_audit) == 3L,
  all(shared_audit$approved[shared_audit$pid %in% c(10L, 11L)]),
  !shared_audit$approved[shared_audit$pid == 12L],
  shared_audit$approval_reason[shared_audit$pid == 10L] ==
    "disjoint_pricefm_controller_declared_cpu_list",
  shared_audit$approval_reason[shared_audit$pid == 11L] ==
    "disjoint_pricefm_worker_kernel_affinity",
  shared_audit$joint_physical_overlap[shared_audit$pid == 11L] == 0L
)
shared_competing <- app_joint_article_competing_processes(
  shared_processes, current_pid = 999L,
  allowed_patterns = shared_contract$allowed_competing_process_patterns,
  allowed_pids = shared_audit$pid[shared_audit$approved])
stopifnot(
  length(shared_competing) == 1L,
  grepl("12 .*orphan", shared_competing[[1L]])
)
overlap_processes <- shared_processes[1:2, , drop = FALSE]
overlap_processes$command[[1L]] <-
  "python application/scripts/pricefm/427_run_pricefm_stage.py --cpu-list 1"
overlap_affinity <- shared_affinity[1:2, , drop = FALSE]
overlap_affinity$cpu_affinity_list <- c("0-3", "1")
overlap_audit <- app_joint_article_disjoint_competing_process_audit(
  overlap_processes, shared_contract, process_affinity = overlap_affinity,
  sysfs_root = topology_root)
stopifnot(
  !any(overlap_audit$approved),
  all(grepl("overlap", overlap_audit$approval_reason))
)
unlink(topology_root, recursive = TRUE, force = TRUE)

test_profile <- data.frame(
  profile_id = "test_host_preflight",
  host = "impossible.invalid.test.host",
  required_rscript = file.path(R.home("bin"), "Rscript"),
  r_library_root = .libPaths()[[1L]],
  runtime_root = file.path("application", "cache", test_contract$run_tag),
  source_worktree = test_contract$source_worktree,
  initial_concurrency = 1L,
  maximum_concurrency = 1L,
  min_data_free_gib = 0,
  blas_threads = 1L,
  production_launched = FALSE,
  stringsAsFactors = FALSE
)
host_error <- tryCatch(
  app_joint_article_host_preflight(test_contract, profile = test_profile,
    processes = empty_process_table),
  error = function(e) e
)
stopifnot(
  inherits(host_error, "joint_article_host_preflight_error"),
  grepl("Host preflight failed gates: .*host", conditionMessage(host_error)),
  is.data.frame(host_error$preflight),
  !host_error$preflight$host_ok[[1L]],
  is.data.frame(host_error$processes)
)

retry_fixture <- tempfile("joint_article_infrastructure_retry_")
app_ensure_dir(file.path(retry_fixture, "mcmc_workers"))
retry_job <- data.frame(
  worker_id = 1L,
  scenario_id = "unit_scenario",
  model_id = "joint_qdesn_rhs_mcmc",
  chain_id = 1L,
  likelihood_family = "AL",
  fit_structure = "joint",
  stringsAsFactors = FALSE
)
app_write_csv(retry_job, file.path(retry_fixture, "mcmc_worker_plan.csv"))
preflight_condition <- structure(list(
  message = "Host preflight failed gates: competing_processes.",
  call = NULL,
  preflight = data.frame(
    host_ok = TRUE, profile_contract_ok = TRUE, rscript_ok = TRUE,
    library_root_ok = TRUE, data_free_ok = TRUE, logical_cores_ok = TRUE,
    physical_affinity_ok = TRUE, competing_processes_ok = FALSE,
    one_thread_policy = TRUE,
    competing_processes = "99999 competing_test_process",
    stringsAsFactors = FALSE
  ),
  processes = data.frame(
    pid = 99999L, ppid = 1L, command = "competing_test_process",
    stringsAsFactors = FALSE
  ),
  cpu_affinity_mapping = data.frame(
    logical_cpu = 1L, verified = TRUE, stringsAsFactors = FALSE),
  shared_capacity_mapping = data.frame(
    allocation_verified = TRUE, stringsAsFactors = FALSE)
), class = c("joint_article_host_preflight_error", "error", "condition"))
retry_worker <- app_joint_article_record_mcmc_failure(
  retry_fixture, 1L, preflight_condition, started = Sys.time()
)
stopifnot(
  file.exists(file.path(retry_worker, "failure.csv")),
  file.exists(file.path(retry_worker, "host_preflight_snapshot.csv")),
  file.exists(file.path(retry_worker, "host_preflight_processes.csv")),
  file.exists(file.path(retry_worker, "host_preflight_cpu_affinity.csv")),
  file.exists(file.path(retry_worker, "host_preflight_shared_capacity.csv"))
)
retry_failure_row <- app_read_csv(file.path(retry_worker, "failure.csv"))
stopifnot(
  "error_message" %in% names(retry_failure_row),
  app_joint_article_classify_mcmc_failure(
    retry_failure_row$error_message[[1L]]) == "infrastructure_host_preflight"
)

capacity_fixture <- tempfile("joint_article_capacity_wait_")
app_ensure_dir(capacity_fixture)
capacity_index <- 0L
capacity_sequence <- function() {
  capacity_index <<- capacity_index + 1L
  if (capacity_index <= 2L) stop(preflight_condition)
  list(
    preflight = data.frame(
      host_ok = TRUE, profile_contract_ok = TRUE, rscript_ok = TRUE,
      library_root_ok = TRUE, data_free_ok = TRUE, logical_cores_ok = TRUE,
      physical_affinity_ok = TRUE, competing_processes_ok = TRUE,
      one_thread_policy = TRUE, stringsAsFactors = FALSE
    ),
    processes = empty_process_table,
    affinity = data.frame(
      logical_cpu = 1L, verified = TRUE, stringsAsFactors = FALSE),
    shared_capacity = data.frame(
      allocation_verified = TRUE, stringsAsFactors = FALSE)
  )
}
capacity_ready <- app_joint_article_wait_for_mcmc_capacity(
  capacity_fixture, test_contract, queue_pid = Sys.getpid(),
  poll_seconds = 0, required_clean_polls = 2L, max_polls = 4L,
  preflight_fn = capacity_sequence, sleep_fn = function(seconds) NULL
)
capacity_history <- app_read_csv(file.path(capacity_fixture,
  "mcmc_capacity_wait_history.csv"))
stopifnot(
  capacity_ready$status[[1L]] == "CAPACITY_READY",
  nrow(capacity_history) == 4L,
  identical(capacity_history$status, c(
    "WAITING_FOR_DISJOINT_CAPACITY",
    "WAITING_FOR_DISJOINT_CAPACITY",
    "CAPACITY_CLEAN_POLL_PENDING_CONFIRMATION",
    "CAPACITY_READY"
  )),
  all(file.exists(file.path(capacity_fixture, "mcmc_capacity_wait",
    sprintf("attempt_%06d", seq_len(4L)), "artifact_manifest.csv"))),
  !dir.exists(file.path(capacity_fixture, "mcmc_workers"))
)

nonwaitable_fixture <- tempfile("joint_article_nonwaitable_preflight_")
app_ensure_dir(nonwaitable_fixture)
nonwaitable_condition <- preflight_condition
nonwaitable_condition$message <- "Host preflight failed gates: data_free."
nonwaitable_condition$preflight$competing_processes_ok <- TRUE
nonwaitable_condition$preflight$data_free_ok <- FALSE
nonwaitable_error <- tryCatch(
  app_joint_article_wait_for_mcmc_capacity(
    nonwaitable_fixture, test_contract, queue_pid = Sys.getpid(),
    poll_seconds = 0, required_clean_polls = 1L, max_polls = 1L,
    preflight_fn = function() stop(nonwaitable_condition),
    sleep_fn = function(seconds) NULL
  ),
  error = function(e) e
)
stopifnot(
  inherits(nonwaitable_error, "joint_article_host_preflight_error"),
  app_read_csv(file.path(nonwaitable_fixture,
    "mcmc_capacity_wait_status.csv"))$status[[1L]] ==
      "NONWAITABLE_PREFLIGHT_FAILURE"
)

failure_audit_fixture <- file.path(retry_fixture, "failure_audit")
resume_audit_fixture <- file.path(retry_fixture, "resume_compatibility")
app_ensure_dir(failure_audit_fixture)
app_ensure_dir(resume_audit_fixture)
app_write_csv(data.frame(
  audit_status = "infrastructure_host_preflight_failure_localized",
  stringsAsFactors = FALSE
), file.path(failure_audit_fixture, "audit_assessment.csv"))
app_write_csv(data.frame(
  status = "COMPLETED_WORKERS_SAFE_TO_RETAIN", stringsAsFactors = FALSE
), file.path(resume_audit_fixture, "resume_compatibility_assessment.csv"))
retry_archive <- app_joint_article_archive_infrastructure_failures(
  retry_fixture,
  failure_audit_dir = failure_audit_fixture,
  resume_compatibility_dir = resume_audit_fixture,
  out_dir = file.path(retry_fixture, "infrastructure_retry_archive")
)
stopifnot(
  retry_archive$status$status[[1L]] ==
    "INFRASTRUCTURE_FAILURES_ARCHIVED_READY_TO_RESUME",
  retry_archive$status$infrastructure_failures_archived[[1L]] == 1L,
  retry_archive$status$completed_workers_retained[[1L]] == 0L,
  retry_archive$status$pending_workers_after_recovery[[1L]] == 1L,
  !dir.exists(retry_worker),
  all(retry_archive$inventory$verified),
  all(retry_archive$manifest_verification$verified),
  !any(retry_archive$state_after$failed)
)

cat("JOINT pure-recursive MCMC preflight recovery tests passed.\n")
