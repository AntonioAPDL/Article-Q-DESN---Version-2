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
    host_ok = TRUE, competing_processes_ok = FALSE,
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
