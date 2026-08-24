#!/usr/bin/env Rscript
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R")); app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R")); source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_trace_tools.R"))
source(app_path("application/R/joint_exqdesn_phase156_collapsed_gamma_sigma.R"))
args <- app_parse_args(list(execute = "false"))
execute <- tolower(as.character(args$execute)) %in% c("true", "1", "yes")
root <- "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache"
phase159 <- file.path(root, "joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804")
phase160 <- file.path(root, "joint_qdesn_phase160_split_rhs_independent_confirmation_mcmc_20260805")
phase161 <- file.path(root, "joint_qdesn_phase161_split_rhs_decision_gamma_audit_20260805")
cleanup_dir <- file.path(phase161, "legacy_cleanup"); app_ensure_dir(cleanup_dir)
files159 <- list.files(phase159, "^posterior_draws\\.csv\\.gz$", recursive = TRUE, full.names = TRUE)
files160 <- list.files(file.path(phase160, "candidates", "nonlinear_reservoir_friendly"),
                       "^posterior_draws\\.csv\\.gz$", recursive = TRUE, full.names = TRUE)
files <- unique(c(files159, files160)); files <- files[file.exists(files)]
if (!length(files)) stop("No eligible legacy posterior draws remain; cleanup was already applied or paths changed.", call. = FALSE)
inventory <- data.frame(
  path = files, relative_to_cache = substring(files, nchar(root) + 2L),
  phase = ifelse(startsWith(files, phase159), "phase159_screening", "phase160_rejected_nonlinear"),
  size_bytes = as.numeric(file.info(files)$size), sha256 = vapply(files, app_sha256_file, character(1L)),
  decision = "delete_heavy_draws_keep_compact_evidence", status = if (execute) "pending" else "dry_run",
  rationale = ifelse(startsWith(files, phase159),
    "screening draws superseded by independent Phase160 confirmation",
    "candidate rejected by independent confirmation and frozen by Phase161"), stringsAsFactors = FALSE)
if (any(!nzchar(inventory$sha256)) || any(inventory$size_bytes <= 0)) stop("Cleanup inventory integrity check failed.", call. = FALSE)
before <- sum(inventory$size_bytes)
if (execute) {
  deleted <- vapply(files, unlink, integer(1L)) == 0L
  inventory$status <- ifelse(deleted & !file.exists(files), "deleted_verified", "delete_failed")
  if (any(inventory$status != "deleted_verified")) stop("At least one cleanup deletion failed.", call. = FALSE)
}
summary <- data.frame(mode = if (execute) "execute" else "dry_run", files = nrow(inventory),
  bytes_selected = before, gib_selected = before / 1024^3,
  files_deleted = sum(inventory$status == "deleted_verified"),
  bytes_freed = sum(inventory$size_bytes[inventory$status == "deleted_verified"]),
  retained_phase160_student_draws = length(list.files(file.path(phase160, "candidates", "student_t_location_scale"),
    "^posterior_draws\\.csv\\.gz$", recursive = TRUE)),
  retained_article_and_fixture_artifacts = TRUE, stringsAsFactors = FALSE)
notice <- c("# Phase161 legacy-output cleanup", "",
  "Only posterior-draw payloads from the superseded Phase159 screen and rejected Phase160 nonlinear candidate were removed.",
  "Their SHA-256 hashes, sizes, paths, decisions, and rationales are retained in cleanup_inventory.csv.",
  "Compact summaries and original manifests remain as pre-cleanup provenance; those historical worker manifests intentionally reference archived draw payloads.",
  "Phase160 Student-t draws, Phase157b references, fixtures, and every article-facing artifact were retained.")
writeLines(notice, file.path(cleanup_dir, "README.md"))
app_joint_qvp_write_csv(inventory, file.path(cleanup_dir, "cleanup_inventory.csv"))
app_joint_qvp_write_csv(summary, file.path(cleanup_dir, "cleanup_summary.csv"))
paths <- list.files(cleanup_dir, full.names = TRUE)
manifest <- data.frame(relative_path = basename(paths), size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)), stringsAsFactors = FALSE)
app_joint_qvp_write_csv(manifest, file.path(cleanup_dir, "artifact_manifest.csv"))
print(summary, row.names = FALSE)
