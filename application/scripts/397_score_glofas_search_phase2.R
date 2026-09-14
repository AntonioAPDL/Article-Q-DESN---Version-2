#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_search_phase2.R"))
args <- app_parse_args(list(runtime_root = "", job_id = ""))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
job_id <- as.character(args$job_id)
jobs <- app_read_csv(file.path(root, "configs", "job_manifest.csv"))
row <- jobs[jobs$job_id == job_id, , drop = FALSE]
if (nrow(row) != 1L) stop(sprintf("Expected one Search-II job row for %s.", job_id), call. = FALSE)
model_done <- file.path(root, "status", paste0(job_id, ".model_done"))
done <- file.path(root, "status", paste0(job_id, ".done"))
if (file.exists(done)) quit(save = "no", status = 0L)
if (!file.exists(model_done)) stop("Search-II scoring is gated on a completed unscored model forecast.", call. = FALSE)
result <- tryCatch({
  path <- app_read_csv(file.path(root, "forecasts", paste0(job_id, "_forecast.csv")))
  registry <- app_read_csv(file.path(root, "configs", "scoring_packet_registry.csv"))
  score_row <- registry[registry$target == row$target[[1L]] & registry$fold_id == row$fold_id[[1L]], , drop = FALSE]
  if (nrow(score_row) != 1L) stop("Expected one sealed scoring packet.", call. = FALSE)
  score_path <- normalizePath(score_row$scoring_packet_path[[1L]], mustWork = TRUE)
  if (!identical(app_sha256_file(score_path), as.character(score_row$scoring_packet_sha256[[1L]]))) stop("Scoring packet hash mismatch.", call. = FALSE)
  app_glofas_search2_score_forecast(path, app_read_csv(score_path))
}, error = function(e) e)
if (inherits(result, "error")) {
  writeLines(paste0("scoring: ", conditionMessage(result)), file.path(root, "status", paste0(job_id, ".failed")))
  stop(conditionMessage(result), call. = FALSE)
}
for (nm in intersect(c("prior_id", "candidate_role", "rhs_selection_role", "D", "n_state_features"), names(row))) {
  result$summary[[nm]] <- row[[nm]][[1L]]
}
app_write_csv(result$summary, file.path(root, "scores", paste0(job_id, "_summary.csv")))
app_write_csv(result$detail, file.path(root, "scores", paste0(job_id, "_detail.csv")))
writeLines(c(
  paste0("score_sha256=", app_sha256_file(file.path(root, "scores", paste0(job_id, "_summary.csv")))),
  paste0("completed_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
), done)
cat(job_id, "sealed scoring complete\n")
