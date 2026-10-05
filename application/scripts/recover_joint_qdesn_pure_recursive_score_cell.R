#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))

args <- app_parse_args(list(
  root = NA_character_, source_root = NA_character_, contract_path = NA_character_,
  recovery_contract_path = app_joint_recursive_recovery_contract_path()
))
authorization <- Sys.getenv("JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION")
if (!authorization %in% c(
    "JEREZ_PURE_RECURSIVE_15_PHYSICAL",
    "JEREZ_PURE_RECURSIVE_15_PHYSICAL_SHARED"
)) {
  stop("Score recovery lacks an approved Jerez authorization.", call. = FALSE)
}

root <- normalizePath(args$root, mustWork = TRUE)
source_root <- normalizePath(args[["source-root"]] %||% args$source_root,
  mustWork = TRUE)
contract <- app_joint_recursive_read_contract(
  args[["contract-path"]] %||% args$contract_path
)
recovery <- app_joint_recursive_read_recovery_contract(
  args[["recovery-contract-path"]] %||% args$recovery_contract_path
)
if (!identical(contract$version, "joint_qdesn_pure_recursive_score_packet_v1") ||
    app_sha256_file(contract$path) != recovery$parent_contract_sha256 ||
    app_sha256_file(file.path(root, "cell_plan.csv")) != recovery$cell_plan_sha256) {
  stop("Score recovery parent contract or cell plan differs from the frozen addendum.",
    call. = FALSE)
}

plan <- app_read_csv(file.path(root, "cell_plan.csv"))
target <- plan[plan$worker_id == recovery$recovery_worker_id, , drop = FALSE]
if (nrow(target) != 1L ||
    target$model_cell_id[[1L]] != recovery$recovery_model_cell_id ||
    target$inference_method[[1L]] != "mcmc") {
  stop("Score recovery target identity differs from the frozen addendum.", call. = FALSE)
}

cell_dir <- app_joint_recursive_cell_dir(root, recovery$recovery_worker_id)
recovery_dir <- file.path(root, "score_recovery_v1")
archive_dir <- file.path(recovery_dir, "original_worker_0041_failure")
app_ensure_dir(recovery_dir)

verify_original_failure <- function(directory) {
  expected <- c(
    FAILED = recovery$failed_marker_sha256,
    failure_diagnostics.csv = recovery$failure_diagnostics_sha256,
    stability_progress.csv = recovery$stability_progress_sha256
  )
  paths <- file.path(directory, names(expected))
  if (any(!file.exists(paths))) {
    stop("Original worker-41 failure evidence is incomplete.", call. = FALSE)
  }
  observed <- vapply(paths, app_sha256_file, character(1L))
  if (!identical(unname(observed), unname(expected))) {
    stop("Original worker-41 failure hashes differ from the frozen addendum.",
      call. = FALSE)
  }
  data.frame(
    relative_path = names(expected), size_bytes = as.numeric(file.info(paths)$size),
    sha256 = observed, stringsAsFactors = FALSE
  )
}

if (app_joint_recursive_manifest_ok(cell_dir)) {
  cat(sprintf("Recovery target is already complete: %s\n", cell_dir))
  quit(status = 0L)
}
if (!dir.exists(archive_dir)) {
  original_inventory <- verify_original_failure(cell_dir)
  if (!file.rename(cell_dir, archive_dir)) {
    stop("Could not atomically archive the original worker-41 failure.", call. = FALSE)
  }
} else {
  original_inventory <- verify_original_failure(archive_dir)
  if (dir.exists(cell_dir)) {
    stop("A nonfinal recovery target exists beside the archived original failure.",
      call. = FALSE)
  }
}
inventory_path <- app_write_csv(
  original_inventory,
  file.path(recovery_dir, "original_worker_0041_failure_manifest.csv")
)
prior <- app_read_csv(file.path(archive_dir, "failure_diagnostics.csv"))
state_rescue <- list(
  recovery_version = recovery$version,
  recovery_contract_sha256 = app_sha256_file(recovery$path),
  original_failure_manifest_sha256 = app_sha256_file(inventory_path),
  prior_failure_diagnostics = prior,
  antithetic_pair_counts = recovery$antithetic_pair_counts,
  seed_stride = recovery$pair_seed_stride
)

result <- tryCatch(
  app_joint_recursive_run_cell(
    root, source_root, recovery$recovery_worker_id, contract,
    state_rescue = state_rescue
  ),
  error = function(error) {
    app_ensure_dir(cell_dir)
    failure_path <- file.path(cell_dir, "failure_diagnostics.csv")
    if (!file.exists(failure_path)) {
      progress_path <- file.path(cell_dir, "stability_progress.csv")
      diagnostics <- if (file.exists(progress_path)) {
        app_read_csv(progress_path)
      } else data.frame(tier = "antithetic_uniform_rescue", stringsAsFactors = FALSE)
      app_joint_recursive_write_failure_diagnostics(
        cell_dir, diagnostics, contract, conditionMessage(error)
      )
    }
    writeLines(conditionMessage(error), file.path(cell_dir, "FAILED"))
    stop(error)
  }
)

receipt <- data.frame(
  recovery_version = recovery$version,
  worker_id = recovery$recovery_worker_id,
  model_cell_id = recovery$recovery_model_cell_id,
  output_directory = result,
  output_manifest_sha256 = app_sha256_file(file.path(result, "artifact_manifest.csv")),
  original_failure_manifest_sha256 = app_sha256_file(inventory_path),
  parent_contract_sha256 = recovery$parent_contract_sha256,
  recovery_contract_sha256 = app_sha256_file(recovery$path),
  git_head = system("git rev-parse HEAD", intern = TRUE),
  completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  status = "complete", stringsAsFactors = FALSE
)
app_write_csv(receipt, file.path(recovery_dir, "recovery_receipt.csv"))
cat(sprintf("Completed score-only recovery at %s\n", result))
