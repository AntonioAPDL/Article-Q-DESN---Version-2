#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))

args <- app_parse_args(list(
  legacy_root = NA_character_, current_root = NA_character_,
  audit_dir = NA_character_, mode = "audit"
))
legacy_root <- normalizePath(
  args[["legacy-root"]] %||% args$legacy_root, mustWork = TRUE
)
current_root <- normalizePath(
  args[["current-root"]] %||% args$current_root, mustWork = TRUE
)
audit_dir <- args[["audit-dir"]] %||% args$audit_dir
mode <- tolower(args$mode)
if (!mode %in% c("audit", "apply") || is.na(audit_dir) || !nzchar(audit_dir)) {
  stop("Use --mode audit|apply and provide --audit-dir.", call. = FALSE)
}
app_ensure_dir(audit_dir)

verify_manifest <- function(root, manifest_path) {
  manifest <- app_read_csv(manifest_path)
  app_check_required_columns(manifest,
    c("relative_path", "size_bytes", "sha256"), manifest_path)
  paths <- file.path(root, manifest$relative_path)
  if (any(!file.exists(paths))) {
    stop(sprintf("Manifest has missing payloads: %s", manifest_path), call. = FALSE)
  }
  sizes <- as.numeric(file.info(paths)$size)
  hashes <- unname(tools::sha256sum(paths))
  if (any(sizes != as.numeric(manifest$size_bytes)) ||
      any(tolower(hashes) != tolower(manifest$sha256))) {
    stop(sprintf("Manifest verification failed: %s", manifest_path), call. = FALSE)
  }
  invisible(TRUE)
}

legacy_oracle_manifest <- file.path(legacy_root, "dgp_oracle_manifest.csv")
current_oracle_manifest <- file.path(current_root, "dgp_oracle_manifest.csv")
verify_manifest(legacy_root, legacy_oracle_manifest)
verify_manifest(current_root, current_oracle_manifest)

legacy_banks <- sort(list.files(file.path(legacy_root, "oracle_banks"),
  pattern = "[.]rds$", full.names = TRUE))
current_banks <- file.path(current_root, "oracle_banks", basename(legacy_banks))
legacy_shards <- sort(list.files(file.path(legacy_root, "oracle_shards"),
  pattern = "^oracle_shard[.]rds$", full.names = TRUE, recursive = TRUE))
shard_rel <- substring(legacy_shards, nchar(file.path(legacy_root,
  "oracle_shards")) + 2L)
current_shards <- file.path(current_root, "oracle_shards", shard_rel)
if (length(legacy_banks) != 8L || length(legacy_shards) != 16L ||
    any(!file.exists(c(current_banks, current_shards)))) {
  stop("Expected exactly 8 legacy banks and 16 legacy shards with current copies.",
    call. = FALSE)
}

for (directory in dirname(legacy_shards)) {
  verify_manifest(directory, file.path(directory, "artifact_manifest.csv"))
}
for (directory in dirname(current_shards)) {
  verify_manifest(directory, file.path(directory, "artifact_manifest.csv"))
}

legacy_paths <- c(legacy_banks, legacy_shards)
current_paths <- c(current_banks, current_shards)
legacy_hashes <- unname(tools::sha256sum(legacy_paths))
current_hashes <- unname(tools::sha256sum(current_paths))
if (!identical(tolower(legacy_hashes), tolower(current_hashes))) {
  stop("Legacy oracle payloads are not byte-identical to the current packet.",
    call. = FALSE)
}
inventory <- data.frame(
  class = c(rep("legacy_oracle_bank", length(legacy_banks)),
    rep("legacy_oracle_shard", length(legacy_shards))),
  legacy_path = legacy_paths,
  current_duplicate_path = current_paths,
  size_bytes = as.numeric(file.info(legacy_paths)$size),
  sha256 = legacy_hashes,
  current_duplicate_sha256 = current_hashes,
  retained_evidence = c(rep("legacy dgp manifest; current bank and manifest", 8L),
    rep("legacy shard manifest and summary; current shard and manifest", 16L)),
  reason = "byte-identical duplicate superseded by current expanded packet",
  stringsAsFactors = FALSE
)
inventory_path <- app_write_csv(inventory,
  file.path(audit_dir, "cleanup_candidate_inventory.csv"))
if (mode == "audit") {
  cat(sprintf("AUDIT_ONLY candidates=%d bytes=%.0f inventory=%s\n",
    nrow(inventory), sum(inventory$size_bytes), inventory_path))
  quit(status = 0L)
}

if (!identical(Sys.getenv("JOINT_PURE_STORAGE_CLEANUP_APPROVED"),
    "JEREZ_JOINT_LEGACY_STORAGE_CLEANUP_V1")) {
  stop("Cleanup apply lacks the exact authorization.", call. = FALSE)
}
processes <- system("ps -eo pid=,args=", intern = TRUE)
active <- processes[grepl(paste0(
  "run_joint_qdesn_pure_recursive_(article_vb|article_mcmc)|",
  "run_joint_qdesn_recursive_(dgp_oracle_worker|mean_forecast_worker)|",
  "finalize_joint_qdesn_recursive_mean_forecast|",
  "closeout_joint_qdesn_pure_recursive_score_review"
), processes)]
if (length(active)) {
  stop("JOINT workers or finalizers are active; cleanup is blocked.", call. = FALSE)
}
final_done <- file.path(current_root, "final_packet", "DONE")
status_path <- file.path(current_root, "final_packet", "packet_status.csv")
if (!file.exists(final_done) || !file.exists(status_path)) {
  stop("The current 64-cell final packet is not frozen.", call. = FALSE)
}
status <- app_read_csv(status_path)
if (nrow(status) != 1L || status$completed_cells[[1L]] != 64L) {
  stop("The current packet does not certify 64 completed cells.", call. = FALSE)
}

disk_before <- as.numeric(system(sprintf("df -Pk %s | awk 'NR==2 {print $4}'",
  shQuote(legacy_root)), intern = TRUE))
removed <- vapply(legacy_paths, unlink, integer(1L))
if (any(removed != 0L) || any(file.exists(legacy_paths))) {
  stop("At least one approved legacy payload could not be removed.", call. = FALSE)
}
post_hashes <- unname(tools::sha256sum(current_paths))
if (!identical(tolower(post_hashes), tolower(current_hashes))) {
  stop("A retained current duplicate changed during cleanup.", call. = FALSE)
}
disk_after <- as.numeric(system(sprintf("df -Pk %s | awk 'NR==2 {print $4}'",
  shQuote(legacy_root)), intern = TRUE))
receipt <- data.frame(
  cleanup_version = "joint_pure_recursive_legacy_oracle_cleanup_v1",
  legacy_root = legacy_root,
  current_root = current_root,
  candidate_inventory_sha256 = app_sha256_file(inventory_path),
  files_removed = nrow(inventory),
  bytes_removed = sum(inventory$size_bytes),
  current_duplicates_verified = length(current_paths),
  disk_free_kib_before = disk_before,
  disk_free_kib_after = disk_after,
  git_head = system("git rev-parse HEAD", intern = TRUE),
  completed_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  status = "complete",
  stringsAsFactors = FALSE
)
receipt_path <- app_write_csv(receipt, file.path(audit_dir, "cleanup_receipt.csv"))
app_write_csv(receipt, file.path(legacy_root, "LEGACY_ORACLE_PAYLOADS_COMPACTED.csv"))
cat(sprintf("CLEANUP_COMPLETE files=%d bytes=%.0f receipt=%s\n",
  nrow(inventory), sum(inventory$size_bytes), receipt_path))
