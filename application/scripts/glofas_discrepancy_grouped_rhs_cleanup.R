#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(output_root = "", wave = "ALL", execute = FALSE))
output_root <- normalizePath(args$output_root, mustWork = TRUE)
owned_root <- normalizePath(app_path("local_trackers", "runtime_configs"), mustWork = FALSE)
if (!startsWith(output_root, paste0(owned_root, .Platform$file.sep))) {
  stop("Cleanup output_root is outside the task-owned runtime tree.", call. = FALSE)
}
wave <- toupper(as.character(args$wave))
if (!wave %in% c("A0", "ALL")) stop("--wave must be A0 or ALL.", call. = FALSE)
execute <- app_as_bool(args$execute)
dry_run_path <- file.path(
  output_root,
  "cleanup",
  paste0(tolower(wave), "_heavy_artifact_cleanup_dry_run.csv")
)
if (!file.exists(dry_run_path)) {
  stop("A completed scientific finalizer must create the cleanup dry run first.", call. = FALSE)
}
decision_path <- file.path(
  output_root,
  "decisions",
  if (wave == "A0") "a0_mechanism_decision.csv" else "stage_a_scientific_decision.csv"
)
if (!file.exists(decision_path)) stop("The corresponding frozen decision is missing.", call. = FALSE)

cleanup <- app_read_csv(dry_run_path)
required <- c("candidate_id", "artifact", "path", "bytes", "sha256", "protected", "action")
missing <- setdiff(required, names(cleanup))
if (!nrow(cleanup) || length(missing)) {
  stop(sprintf("Cleanup manifest is empty or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
}
cleanup$path <- vapply(cleanup$path, normalizePath, character(1L), mustWork = FALSE)
runs_root <- normalizePath(file.path(output_root, "runs"), mustWork = FALSE)
inside <- startsWith(cleanup$path, paste0(runs_root, .Platform$file.sep))
allowed_extension <- tolower(tools::file_ext(cleanup$path)) %in% c("rds", "rda", "rdata")
delete_candidate <- !app_as_bool_vec(cleanup$protected) & grepl("^delete_candidate", cleanup$action)
if (any(delete_candidate & (!inside | !allowed_extension))) {
  stop("Cleanup manifest includes an unowned or unsupported deletion candidate.", call. = FALSE)
}

status_files <- c(
  list.files(file.path(output_root, "status"), pattern = "[.]csv$", full.names = TRUE),
  file.path(output_root, "orchestration_status.csv")
)
status_files <- unique(status_files[file.exists(status_files)])
live <- character()
for (path in status_files) {
  status <- tryCatch(app_read_csv(path), error = function(e) data.frame())
  if (!nrow(status) || !"pid" %in% names(status) ||
      !any(c("status", "state") %in% names(status))) next
  row <- status[nrow(status), , drop = FALSE]
  state_field <- if ("status" %in% names(row)) "status" else if ("state" %in% names(row)) "state" else NA_character_
  if (is.na(state_field) || as.character(row[[state_field]][[1L]]) != "running") next
  pid <- suppressWarnings(as.integer(row$pid[[1L]]))
  if (is.finite(pid) && identical(system2("kill", c("-0", pid), stdout = FALSE, stderr = FALSE), 0L)) {
    live <- c(live, sprintf("%s:%d", basename(path), pid))
  }
}
if (execute && length(live)) {
  stop(sprintf("Cleanup is blocked by live campaign processes: %s.", paste(live, collapse = ", ")), call. = FALSE)
}

cleanup$exists_before <- file.exists(cleanup$path)
cleanup$hash_matches <- vapply(seq_len(nrow(cleanup)), function(i) {
  !cleanup$exists_before[[i]] || identical(
    tolower(app_sha256_file(cleanup$path[[i]])),
    tolower(as.character(cleanup$sha256[[i]]))
  )
}, logical(1L))
cleanup$executed <- FALSE
cleanup$removed <- FALSE
cleanup$result <- ifelse(delete_candidate, "dry_run_delete_candidate", "kept")

if (execute) {
  bad_hash <- delete_candidate & cleanup$exists_before & !cleanup$hash_matches
  if (any(bad_hash)) stop("Cleanup candidate hash changed after finalization; refusing deletion.", call. = FALSE)
  for (i in which(delete_candidate & cleanup$exists_before)) {
    cleanup$executed[[i]] <- TRUE
    status <- unlink(cleanup$path[[i]], force = FALSE)
    cleanup$removed[[i]] <- identical(status, 0L) && !file.exists(cleanup$path[[i]])
    cleanup$result[[i]] <- if (cleanup$removed[[i]]) "removed" else "remove_failed"
  }
  if (any(cleanup$executed & !cleanup$removed)) stop("One or more approved artifacts could not be removed.", call. = FALSE)
}

cleanup$exists_after <- file.exists(cleanup$path)
cleanup$bytes_recovered <- ifelse(cleanup$removed, as.numeric(cleanup$bytes), 0)
report_path <- file.path(
  output_root,
  "cleanup",
  sprintf("%s_heavy_artifact_cleanup_%s.csv", tolower(wave), if (execute) "executed" else "validated_dry_run")
)
app_write_csv(cleanup, report_path)
cat(sprintf(
  "%s: delete_candidates=%d, expected_gb=%.3f, recovered_gb=%.3f, live_processes=%d\n",
  report_path,
  sum(delete_candidate),
  sum(as.numeric(cleanup$bytes[delete_candidate]), na.rm = TRUE) / 1024^3,
  sum(cleanup$bytes_recovered, na.rm = TRUE) / 1024^3,
  length(live)
))
