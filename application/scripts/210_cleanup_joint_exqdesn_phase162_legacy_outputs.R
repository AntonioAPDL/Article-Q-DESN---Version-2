#!/usr/bin/env Rscript
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R")); source(app_path("application/R/joint_qvp_qdesn.R"))
args <- app_parse_args(list(execute = "false"))
execute <- tolower(as.character(args$execute)) %in% c("true", "1", "yes")
root <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
phase162 <- file.path(root, "joint_qdesn_phase162_exal_scenario_classification_20260805")
cleanup_dir <- file.path(phase162, "legacy_cleanup"); app_ensure_dir(cleanup_dir)
phase135 <- file.path(root, "joint_qdesn_phase135_matched_exal_screening_20260715")
phase136 <- file.path(root, "joint_qdesn_phase136_exal_gamma_kernel_packet_20260715")
phase140 <- file.path(root, "joint_qdesn_phase140_exal_fixed_gamma_zero_sensitivity_recovery_20260718")
protected <- c(
  file.path(root, "joint_qdesn_phase149_case_specific_exal_screening_20260726"),
  file.path(root, "joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727"),
  file.path(root, "joint_qdesn_phase154_mcmc_joint_al_20260730"),
  file.path(root, "joint_qdesn_phase157b_collapsed_gamma_sigma_mcmc_20260802"),
  file.path(root, "joint_qdesn_phase160_split_rhs_independent_confirmation_mcmc_20260805"))
if (any(!dir.exists(protected))) stop("A protected evidence directory is missing; cleanup aborted.", call. = FALSE)
all135 <- list.files(file.path(phase135, "cases"), recursive = TRUE, full.names = TRUE)
info135 <- file.info(all135)
files135 <- all135[!info135$isdir & info135$size >= 5e5]
files136 <- list.files(file.path(phase136, "figures"), pattern = "\\.pdf$", full.names = TRUE)
files140 <- list.files(file.path(phase140, "figures"), pattern = "\\.pdf$", full.names = TRUE)
files <- unique(c(files135, files136, files140)); files <- files[file.exists(files)]
if (!length(files)) stop("No eligible Phase162 legacy payloads remain.", call. = FALSE)
if (any(vapply(protected, function(p) any(startsWith(files, paste0(p, "/"))), logical(1L)))) {
  stop("Cleanup selection intersects protected evidence.", call. = FALSE)
}
phase <- ifelse(startsWith(files, phase135), "phase135_superseded_screen",
  ifelse(startsWith(files, phase136), "phase136_superseded_kernel_figures", "phase140_fixed_gamma_sensitivity_figures"))
inventory <- data.frame(path = files, relative_to_cache = substring(files, nchar(root) + 2L), phase = phase,
  size_bytes = as.numeric(file.info(files)$size), sha256 = vapply(files, app_sha256_file, character(1L)),
  status = if (execute) "pending" else "dry_run",
  rationale = ifelse(phase == "phase135_superseded_screen",
    "bulky per-origin screen payload; compact summaries retained and later Phase149/150 evidence supersedes it",
    "diagnostic PDF from a closed sampler sensitivity direction; CSV diagnostics retained"), stringsAsFactors = FALSE)
if (any(inventory$size_bytes <= 0) || any(!nzchar(inventory$sha256))) stop("Cleanup hash inventory failed.", call. = FALSE)
if (execute) {
  deleted <- vapply(files, unlink, integer(1L)) == 0L
  inventory$status <- ifelse(deleted & !file.exists(files), "deleted_verified", "delete_failed")
  if (any(inventory$status != "deleted_verified")) stop("Legacy deletion failed.", call. = FALSE)
}
summary <- data.frame(mode = if (execute) "execute" else "dry_run", files = nrow(inventory),
  bytes_selected = sum(inventory$size_bytes), gib_selected = sum(inventory$size_bytes) / 1024^3,
  files_deleted = sum(inventory$status == "deleted_verified"),
  bytes_freed = sum(inventory$size_bytes[inventory$status == "deleted_verified"]),
  protected_directories_verified = length(protected), article_assets_touched = FALSE,
  retained_compact_summaries = TRUE, stringsAsFactors = FALSE)
writeLines(c("# Phase162 legacy cleanup", "",
  "This cleanup removes only bulky outputs from closed, superseded experiments.",
  "Phase135 compact screening summaries and Phase136/140 CSV diagnostics remain.",
  "Phase149, Phase150, Phase154, Phase157b, Phase160, fixtures, and article assets are protected.",
  "The inventory records the original SHA-256 hash and byte size of every removed file."), file.path(cleanup_dir, "README.md"))
app_joint_qvp_write_csv(inventory, file.path(cleanup_dir, "cleanup_inventory.csv"))
app_joint_qvp_write_csv(summary, file.path(cleanup_dir, "cleanup_summary.csv"))
paths <- list.files(cleanup_dir, full.names = TRUE)
manifest <- data.frame(relative_path = basename(paths), size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)), stringsAsFactors = FALSE)
app_joint_qvp_write_csv(manifest, file.path(cleanup_dir, "artifact_manifest.csv"))
print(summary, row.names = FALSE)
