#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_search_phase2.R"))
args <- app_parse_args(list(runtime_root = "", job_id = ""))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
run_manifest <- app_read_yaml(file.path(root, "configs", "run_manifest.yaml"))
app_glofas_search2_assert_git_state(expected_head = run_manifest$git_head)
jobs <- app_read_csv(file.path(root, "configs", "job_manifest.csv"))
row <- jobs[jobs$job_id == as.character(args$job_id), , drop = FALSE]
if (nrow(row) != 1L) stop("Expected exactly one Search III scoring row.", call. = FALSE)
job_id <- as.character(row$job_id[[1L]])
if (file.exists(file.path(root, "status", paste0(job_id, ".done")))) quit(save = "no", status = 0L)
if (!file.exists(file.path(root, "status", paste0(job_id, ".model_done")))) {
  stop("Search III scoring requires a completed model forecast.", call. = FALSE)
}
result <- tryCatch({
  path <- app_read_csv(file.path(root, "forecasts", paste0(job_id, "_forecast.csv")))
  registry <- app_read_csv(file.path(root, "configs", "scoring_packet_registry.csv"))
  score_row <- registry[registry$target == row$target[[1L]] & registry$fold_id == row$fold_id[[1L]], , drop = FALSE]
  if (nrow(score_row) != 1L) stop("Expected one sealed Search III scoring packet.", call. = FALSE)
  score_path <- normalizePath(score_row$scoring_packet_path[[1L]], mustWork = TRUE)
  if (!identical(app_sha256_file(score_path), score_row$scoring_packet_sha256[[1L]])) stop("Search III scoring packet hash mismatch.", call. = FALSE)
  app_glofas_search2_score_forecast(path, app_read_csv(score_path))
}, error = function(e) e)
if (inherits(result, "error")) {
  writeLines(paste0("scoring: ", conditionMessage(result)), file.path(root, "status", paste0(job_id, ".failed")))
  stop(conditionMessage(result), call. = FALSE)
}
for (nm in intersect(c("prior_id", "candidate_role", "D", "n_state_features", "base_candidate_id", "seed"), names(row))) {
  result$summary[[nm]] <- row[[nm]][[1L]]
}
app_write_csv(result$summary, file.path(root, "scores", paste0(job_id, "_summary.csv")))
app_write_csv(result$detail, file.path(root, "scores", paste0(job_id, "_detail.csv")))
writeLines(c(
  paste0("score_sha256=", app_sha256_file(file.path(root, "scores", paste0(job_id, "_summary.csv")))),
  paste0("completed_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
), file.path(root, "status", paste0(job_id, ".done")))
cat(job_id, "sealed scoring complete\n")
