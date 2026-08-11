#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_20260730",
  cleanup = FALSE
))
resolve_repo <- function(path) if (grepl("^/", path)) path else app_path(path)
output_root <- resolve_repo(args$output_root)
manifest <- app_read_csv(file.path(output_root, "runtime_manifest.csv"))
score_paths <- list.files(file.path(output_root, "scores"), pattern = "_observed_fit_scores[.]csv$", full.names = TRUE)
scores <- app_bind_rows_fill(lapply(score_paths, app_read_csv))
if (!nrow(scores)) stop("No completed observed-fit scores are available.", call. = FALSE)
all_scores <- scores[scores$window == "all", , drop = FALSE]
last200 <- scores[scores$window == "last200", c("candidate_id", "log1p_mae", "original_mae", "peak95_original_mae"), drop = FALSE]
names(last200)[-1L] <- paste0(names(last200)[-1L], "_last200")
ranking <- merge(all_scores, last200, by = "candidate_id", all.x = TRUE)
ranking <- merge(ranking, manifest, by = "candidate_id", all.x = TRUE)
ranking <- ranking[order(ranking$p50_check_loss_mean, ranking$original_rmse, ranking$priority), , drop = FALSE]
ranking$rank <- seq_len(nrow(ranking))
app_write_csv(ranking, file.path(output_root, "observed_fit_ranking.csv"))

if (app_as_bool(args$cleanup)) {
  winner <- ranking$candidate_id[[1L]]
  cleanup_rows <- list()
  for (i in seq_len(nrow(manifest))) {
    candidate_id <- manifest$candidate_id[[i]]
    run_dir <- manifest$run_dir[[i]]
    if (!dir.exists(run_dir)) next
    protected <- isTRUE(app_as_bool(manifest$retain_heavy[[i]])) || identical(candidate_id, winner)
    cleanup <- app_glofas_fit_recovery_cleanup(
      run_dir,
      runs_root = file.path(output_root, "runs"),
      execute = TRUE,
      protected = protected
    )
    if (nrow(cleanup)) {
      cleanup$candidate_id <- candidate_id
      cleanup_rows[[length(cleanup_rows) + 1L]] <- cleanup
    }
  }
  cleanup_report <- app_bind_rows_fill(cleanup_rows)
  app_write_csv(cleanup_report, file.path(output_root, "cleanup", "cleanup_report.csv"))
}
cat(file.path(output_root, "observed_fit_ranking.csv"), "\n")
