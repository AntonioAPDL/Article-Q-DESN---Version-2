#!/usr/bin/env Rscript

repo_root <- if (dir.exists(file.path(getwd(), "application/scripts"))) {
  normalizePath(getwd())
} else {
  file_arg <- sub("^--file=", "", grep(
    "^--file=", commandArgs(FALSE), value = TRUE
  )[1L])
  normalizePath(file.path(dirname(file_arg), "..", ".."))
}
helper <- file.path(
  repo_root, "application/scripts", "_joint_qdesn_score_queue.sh"
)
stopifnot(file.exists(helper))

root <- tempfile("joint_score_queue_test_")
dir.create(root)
receipt_dir <- file.path(root, "receipts")
calls <- file.path(root, "calls.txt")
harness <- file.path(root, "harness.sh")
writeLines(c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  sprintf("source %s", shQuote(helper)),
  sprintf("calls=%s", shQuote(calls)),
  "callback() {",
  "  printf '%s\\n' \"$1\" >>\"$calls\"",
  "  [[ \"$1\" != 2 ]]",
  "}",
  "set +e",
  sprintf(
    "joint_qdesn_run_fail_isolated_jobs %s callback 1 2 3",
    shQuote(receipt_dir)
  ),
  "code=$?",
  "set -e",
  "[[ \"$code\" == 1 ]]"
), harness)
Sys.chmod(harness, mode = "0755")
status <- system2("bash", harness)
stopifnot(
  status == 0L,
  identical(readLines(calls), c("1", "2", "3")),
  readLines(file.path(receipt_dir, "worker_0001.exit")) == "0",
  readLines(file.path(receipt_dir, "worker_0002.exit")) == "1",
  readLines(file.path(receipt_dir, "worker_0003.exit")) == "0"
)

launcher <- readLines(file.path(
  repo_root, "application/scripts",
  "launch_joint_qdesn_pure_recursive_expanded_continuation_jerez.sh"
))
stopifnot(
  any(grepl("_joint_qdesn_score_queue[.]sh", launcher)),
  any(grepl("queue_receipts", launcher)),
  any(grepl("joint_qdesn_run_fail_isolated_jobs", launcher))
)

source(file.path(
  repo_root, "application/scripts",
  "_joint_qdesn_recursive_mean_forecast_bootstrap.R"
))
recovery_path <- file.path(
  repo_root, "application/config",
  "joint_qdesn_pure_recursive_expanded_score_recovery_v1_20261004.csv"
)
recovery <- app_joint_recursive_read_recovery_contract(recovery_path)
stopifnot(
  recovery$recovery_worker_id == 41L,
  recovery$unchanged_worker_id == 56L,
  identical(recovery$antithetic_pair_counts, c(1L, 2L)),
  recovery$parent_contract_sha256 ==
    "bbf8b12dd05d352eb0cfa84ffc71b9510ff667a68cecc897a29991f85cd683c7",
  recovery$cell_plan_sha256 ==
    "bdd9b9406d0d0dedc468795797e9f96ca9fdb15e035eb2e4ef837634caf7dc72"
)

recovery_launcher <- readLines(file.path(
  repo_root, "application/scripts",
  "launch_joint_qdesn_pure_recursive_expanded_score_recovery_jerez.sh"
))
stopifnot(
  any(grepl("expanded_score_recovery_v1_20261004", recovery_launcher)),
  any(grepl("62,1,1,41,56", recovery_launcher, fixed = TRUE)),
  any(grepl("Another JOINT confirmation or score worker is active", recovery_launcher)),
  any(grepl("expanded-score-closeout-20261004", recovery_launcher))
)

cat("JOINT score-queue failure-isolation tests passed.\n")
