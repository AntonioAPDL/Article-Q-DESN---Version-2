#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))

args <- app_parse_args(list(
  root = NA_character_, source_root = NA_character_, contract_path = NA_character_,
  review_contract_path = app_joint_recursive_review_contract_path()
))
authorization <- Sys.getenv("JOINT_RECURSIVE_MEAN_ALLOW_PRODUCTION")
if (!identical(authorization, "JEREZ_PURE_RECURSIVE_SCORE_REVIEW_V2")) {
  stop("Score review closeout lacks the exact Jerez authorization.", call. = FALSE)
}

root <- normalizePath(args$root, mustWork = TRUE)
source_root <- normalizePath(args[["source-root"]] %||% args$source_root,
  mustWork = TRUE)
contract <- app_joint_recursive_read_contract(
  args[["contract-path"]] %||% args$contract_path
)
review <- app_joint_recursive_read_review_contract(
  args[["review-contract-path"]] %||% args$review_contract_path
)
if (!identical(contract$version, "joint_qdesn_pure_recursive_score_packet_v1") ||
    app_sha256_file(contract$path) != review$parent_contract_sha256 ||
    app_sha256_file(file.path(root, "cell_plan.csv")) != review$cell_plan_sha256) {
  stop("Score review parent contract or cell plan differs from the addendum.",
    call. = FALSE)
}

prior_recovery_path <- app_joint_recursive_recovery_contract_path()
if (app_sha256_file(prior_recovery_path) != review$prior_recovery_contract_sha256) {
  stop("Strict recovery contract differs from the review addendum.", call. = FALSE)
}
plan <- app_read_csv(file.path(root, "cell_plan.csv"))
target <- plan[plan$worker_id == review$recovery_worker_id, , drop = FALSE]
if (nrow(target) != 1L ||
    target$model_cell_id[[1L]] != review$recovery_model_cell_id ||
    target$inference_method[[1L]] != "mcmc" ||
    target$likelihood_family[[1L]] != "AL") {
  stop("Score review target identity differs from the addendum.", call. = FALSE)
}

cell_dir <- app_joint_recursive_cell_dir(root, review$recovery_worker_id)
strict_root <- file.path(root, "score_recovery_v1")
review_root <- file.path(root, "score_recovery_v2")
archive_dir <- file.path(review_root, "strict_recovery_v1_failure")
original_failure_dir <- file.path(strict_root, "original_worker_0041_failure")
original_inventory_path <- file.path(
  strict_root, "original_worker_0041_failure_manifest.csv"
)
worker56_manifest <- file.path(
  app_joint_recursive_cell_dir(root, 56L), "artifact_manifest.csv"
)
app_ensure_dir(review_root)

if (app_sha256_file(original_inventory_path) !=
      review$original_failure_manifest_sha256 ||
    app_sha256_file(worker56_manifest) != review$completed_worker_manifest_sha256 ||
    !app_joint_recursive_manifest_ok(app_joint_recursive_cell_dir(root, 56L))) {
  stop("Preserved score evidence or completed worker 56 differs from the addendum.",
    call. = FALSE)
}

verify_strict_failure <- function(directory) {
  expected <- c(
    FAILED = review$failed_marker_sha256,
    failure_diagnostics.csv = review$failure_diagnostics_sha256,
    stability_progress.csv = review$stability_progress_sha256
  )
  paths <- file.path(directory, names(expected))
  if (any(!file.exists(paths))) {
    stop("Strict worker-41 recovery evidence is incomplete.", call. = FALSE)
  }
  observed <- vapply(paths, app_sha256_file, character(1L))
  if (!identical(unname(observed), unname(expected))) {
    stop("Strict worker-41 recovery hashes differ from the review addendum.",
      call. = FALSE)
  }
  data.frame(
    relative_path = names(expected),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = observed, stringsAsFactors = FALSE
  )
}

if (app_joint_recursive_manifest_ok(cell_dir)) {
  cat(sprintf("Score review target is already complete: %s\n", cell_dir))
  quit(status = 0L)
}
if (!dir.exists(archive_dir)) {
  strict_inventory <- verify_strict_failure(cell_dir)
  if (!file.rename(cell_dir, archive_dir)) {
    stop("Could not atomically archive the strict worker-41 recovery failure.",
      call. = FALSE)
  }
} else {
  strict_inventory <- verify_strict_failure(archive_dir)
  if (dir.exists(cell_dir)) {
    stop("A nonfinal review target exists beside the archived strict failure.",
      call. = FALSE)
  }
}
strict_inventory_path <- app_write_csv(
  strict_inventory,
  file.path(review_root, "strict_recovery_v1_failure_manifest.csv")
)

prior_failure <- app_read_csv(file.path(
  original_failure_dir, "failure_diagnostics.csv"
))
review_reference <- app_read_csv(file.path(
  archive_dir, "failure_diagnostics.csv"
))
state_rescue <- list(
  recovery_version = review$version,
  recovery_contract_sha256 = app_sha256_file(review$path),
  original_failure_manifest_sha256 = app_sha256_file(original_inventory_path),
  strict_recovery_failure_manifest_sha256 = app_sha256_file(strict_inventory_path),
  prior_failure_diagnostics = prior_failure,
  review_reference_diagnostics = review_reference,
  antithetic_pair_counts = review$antithetic_pair_count,
  seed_stride = review$pair_seed_stride,
  allow_score_stability_review = TRUE,
  score_gate_multiplier = review$score_gate_multiplier,
  max_pooled_score_relative_drift = review$max_pooled_score_relative_drift,
  max_rms_gate_fraction = review$max_rms_gate_fraction,
  max_chain_score_relative_deviation = review$max_chain_score_relative_deviation,
  required_unique_posterior_draws = review$required_unique_posterior_draws,
  required_state_trajectory_draws = review$required_state_trajectory_draws
)

result <- tryCatch(
  app_joint_recursive_run_cell(
    root, source_root, review$recovery_worker_id, contract,
    state_rescue = state_rescue
  ),
  error = function(error) {
    app_ensure_dir(cell_dir)
    failure_path <- file.path(cell_dir, "failure_diagnostics.csv")
    if (!file.exists(failure_path)) {
      progress_path <- file.path(cell_dir, "stability_progress.csv")
      diagnostics <- if (file.exists(progress_path)) {
        app_read_csv(progress_path)
      } else data.frame(tier = "antithetic_uniform_rescue_2pair",
        stringsAsFactors = FALSE)
      app_joint_recursive_write_failure_diagnostics(
        cell_dir, diagnostics, contract, conditionMessage(error)
      )
    }
    writeLines(conditionMessage(error), file.path(cell_dir, "FAILED"))
    stop(error)
  }
)

diagnostics <- app_read_csv(file.path(result, "mean_design_diagnostics.csv"))
if (diagnostics$score_stability_status[[1L]] != "review" ||
    !app_as_bool_vec(diagnostics$score_stability_review_eligible)[[1L]]) {
  stop("Published worker 41 is not an eligible score-stability review.",
    call. = FALSE)
}
receipt <- data.frame(
  review_version = review$version,
  worker_id = review$recovery_worker_id,
  model_cell_id = review$recovery_model_cell_id,
  output_directory = result,
  output_manifest_sha256 = app_sha256_file(file.path(result, "artifact_manifest.csv")),
  original_failure_manifest_sha256 = app_sha256_file(original_inventory_path),
  strict_recovery_failure_manifest_sha256 = app_sha256_file(strict_inventory_path),
  parent_contract_sha256 = review$parent_contract_sha256,
  review_contract_sha256 = app_sha256_file(review$path),
  strict_score_gate_pass = FALSE,
  review_eligible = TRUE,
  git_head = system("git rev-parse HEAD", intern = TRUE),
  completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  status = "complete_with_score_stability_review",
  stringsAsFactors = FALSE
)
app_write_csv(receipt, file.path(review_root, "review_closeout_receipt.csv"))
cat(sprintf("Completed bounded score review at %s\n", result))
