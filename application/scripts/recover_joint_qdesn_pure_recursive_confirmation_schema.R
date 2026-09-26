#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))),
  "_joint_qdesn_pure_recursive_bootstrap.R"))

args <- app_parse_args(list(
  campaign_root = app_joint_pure_default_root(),
  confirmation_root = app_joint_pure_confirmation_root(),
  recovery_root = app_path(
    "application/cache/joint_qdesn_pure_recursive_controller_schema_recovery_v3_20260926"
  ),
  archive_name = "failed_confirmation_preparation_20260926"
))
campaign_root <- normalizePath(args[["campaign-root"]] %||% args$campaign_root,
  mustWork = TRUE)
confirmation_root <- normalizePath(
  args[["confirmation-root"]] %||% args$confirmation_root, mustWork = TRUE)
recovery_root <- normalizePath(
  args[["recovery-root"]] %||% args$recovery_root, mustWork = FALSE)
archive_name <- args[["archive-name"]] %||% args$archive_name

health <- app_joint_pure_quantile_health(campaign_root)
if (health$expected[[1L]] != 408L || health$completed[[1L]] != 408L ||
    health$failed[[1L]] != 0L || health$remaining[[1L]] != 0L) {
  stop("Source quantile health is not the exact 408/408 failure-free state.",
    call. = FALSE)
}
quantile_manifest <- file.path(campaign_root, "quantile_artifact_manifest.csv")
verified <- app_joint_shared_verify_manifest(campaign_root, quantile_manifest)
if (!nrow(verified) || !all(verified$verified)) {
  stop("Source quantile artifact manifest does not verify.", call. = FALSE)
}

registry <- app_joint_pure_read_registry(file.path(campaign_root,
  "frozen_family_registry.csv"))
registry <- registry[order(registry$scenario_order), , drop = FALSE]
expected <- sort(c(
  "frozen_contract.csv",
  file.path("designs", sprintf("%02d_%s.rds", registry$scenario_order,
    registry$scenario_id)),
  file.path("fixtures", sprintf("%02d_%s.rds", registry$scenario_order,
    registry$scenario_id))
))
actual <- sort(list.files(confirmation_root, recursive = TRUE,
  all.files = TRUE, no.. = TRUE, include.dirs = FALSE))
if (!identical(actual, expected)) {
  stop(paste0(
    "Partial confirmation root does not match the exact 17-file failed state. ",
    "Observed: ", paste(actual, collapse = ";")
  ), call. = FALSE)
}

app_ensure_dir(recovery_root)
inventory <- data.frame(
  relative_path = actual,
  size_bytes = as.numeric(file.info(file.path(confirmation_root, actual))$size),
  sha256 = vapply(file.path(confirmation_root, actual), app_sha256_file,
    character(1L)),
  stringsAsFactors = FALSE
)
inventory_path <- app_write_csv(inventory,
  file.path(recovery_root, "partial_confirmation_inventory.csv"))

archive_parent <- file.path(recovery_root, "archives")
archive_root <- file.path(archive_parent, archive_name)
if (dir.exists(archive_root) || file.exists(archive_root)) {
  stop("Recovery archive destination already exists.", call. = FALSE)
}
app_ensure_dir(archive_parent)
app_ensure_dir(archive_root)
source_entries <- list.files(confirmation_root, all.files = TRUE, no.. = TRUE,
  full.names = TRUE)
copied <- file.copy(source_entries, archive_root, recursive = TRUE,
  copy.date = TRUE)
if (!length(copied) || !all(copied)) {
  stop("Failed to copy the partial confirmation root into the recovery archive.",
    call. = FALSE)
}
archive_files <- file.path(archive_root, inventory$relative_path)
archive_verification <- data.frame(
  relative_path = inventory$relative_path,
  exists = file.exists(archive_files),
  size_match = as.numeric(file.info(archive_files)$size) == inventory$size_bytes,
  sha256_match = vapply(archive_files, app_sha256_file, character(1L)) ==
    inventory$sha256,
  stringsAsFactors = FALSE
)
archive_verification$verified <- with(archive_verification,
  exists & size_match & sha256_match)
if (!all(archive_verification$verified)) {
  stop("Archived partial confirmation files failed verification.", call. = FALSE)
}
archive_verification_path <- app_write_csv(archive_verification,
  file.path(recovery_root, "partial_confirmation_archive_verification.csv"))

unlink(confirmation_root, recursive = TRUE, force = TRUE)
if (dir.exists(confirmation_root) || file.exists(confirmation_root)) {
  stop("Verified partial confirmation root could not be cleared.", call. = FALSE)
}
status_path <- app_write_csv(data.frame(
  status = "PARTIAL_CONFIRMATION_ARCHIVED_READY_TO_RESUME",
  source_quantile_completed = health$completed[[1L]],
  source_quantile_failed = health$failed[[1L]],
  archived_files = nrow(inventory),
  archived_bytes = sum(inventory$size_bytes),
  archive_root = normalizePath(archive_root, mustWork = TRUE),
  completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  stringsAsFactors = FALSE
), file.path(recovery_root, "schema_recovery_status.csv"))

app_joint_shared_write_manifest(recovery_root, c(
  inventory = inventory_path,
  archive_verification = archive_verification_path,
  status = status_path
), filename = "schema_recovery_manifest.csv")

cat(sprintf(
  "Archived and verified %d partial confirmation files (%d bytes); source remains 408/408.\n",
  nrow(inventory), sum(inventory$size_bytes)
))
