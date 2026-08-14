#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  candidate_id = "",
  run_dir = "",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_20260730/scores",
  cutoff_date = "2022-12-25",
  windows = "all,1000,500,200,100,50"
))
if (!nzchar(args$candidate_id) || !nzchar(args$run_dir)) {
  stop("--candidate_id and --run_dir are required.", call. = FALSE)
}
resolve_repo <- function(path) if (grepl("^/", path)) path else app_path(path)
run_dir <- resolve_repo(args$run_dir)
history_path <- file.path(run_dir, "tables", "post_fit_quantile_history_summary.csv")
if (!file.exists(history_path)) {
  stop(sprintf("Completed run lacks observed-fit history: %s.", history_path), call. = FALSE)
}
windows <- trimws(strsplit(as.character(args$windows), ",", fixed = TRUE)[[1L]])
windows <- vapply(windows, function(x) if (tolower(x) == "all") NA_integer_ else as.integer(x), integer(1L))
raw_history <- app_read_csv(history_path)
if (!"quantile_level" %in% names(raw_history)) {
  stop(sprintf("Observed-fit history lacks quantile_level: %s.", history_path), call. = FALSE)
}
quantile_levels <- unique(as.numeric(raw_history$quantile_level[is.finite(as.numeric(raw_history$quantile_level))]))
if (length(quantile_levels) != 1L || quantile_levels[[1L]] <= 0 || quantile_levels[[1L]] >= 1) {
  stop("Observed-fit scoring requires exactly one valid quantile level.", call. = FALSE)
}
quantile_level <- quantile_levels[[1L]]
history <- app_glofas_fit_recovery_history(
  raw_history,
  candidate_id = args$candidate_id,
  cutoff_date = as.Date(args$cutoff_date)
)
history$quantile_level <- quantile_level
scores <- app_glofas_fit_recovery_score_history(history, windows = windows, tau = quantile_level)
output_root <- resolve_repo(args$output_root)
app_ensure_dir(output_root)
app_write_csv(scores, file.path(output_root, paste0(args$candidate_id, "_observed_fit_scores.csv")))
app_write_csv(tail(history, 200L), file.path(output_root, paste0(args$candidate_id, "_history_last200.csv")))
cat(file.path(output_root, paste0(args$candidate_id, "_observed_fit_scores.csv")), "\n")
