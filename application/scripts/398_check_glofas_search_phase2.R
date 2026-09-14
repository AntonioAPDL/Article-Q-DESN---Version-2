#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_search_phase2.R"))
args <- app_parse_args(list(runtime_root = ""))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
jobs <- app_read_csv(file.path(root, "configs", "job_manifest.csv"))
reuse_registry_path <- file.path(root, "configs", "reused_score_registry.csv")
reuse_registry <- if (file.exists(reuse_registry_path)) app_read_csv(reuse_registry_path) else data.frame()
exists_status <- function(ext) file.exists(file.path(root, "status", paste0(jobs$job_id, ext)))
health <- data.frame(
  runtime_root = root, total = nrow(jobs), completed = sum(exists_status(".done")),
  reused_completed = nrow(reuse_registry), evaluated_total = nrow(jobs) + nrow(reuse_registry),
  model_done_unscored = sum(exists_status(".model_done") & !exists_status(".done")),
  running = sum(exists_status(".running")), failed = sum(exists_status(".failed")),
  pending = sum(!exists_status(".done") & !exists_status(".model_done") & !exists_status(".running") & !exists_status(".failed")),
  stringsAsFactors = FALSE
)
score_files <- list.files(file.path(root, "scores"), pattern = "_summary[.]csv$", full.names = TRUE)
if (nrow(reuse_registry)) score_files <- c(score_files, as.character(reuse_registry$score_summary_path))
scores <- app_bind_rows_fill(lapply(score_files, app_read_csv))
fit_files <- list.files(file.path(root, "fits"), pattern = "_summary[.]csv$", full.names = TRUE)
if (nrow(reuse_registry) && "fit_summary_path" %in% names(reuse_registry)) {
  fit_files <- c(fit_files, as.character(reuse_registry$fit_summary_path))
}
fits <- app_bind_rows_fill(lapply(fit_files, app_read_csv))
if (nrow(scores) && nrow(fits)) {
  fit_columns <- c("job_id", grep(
    "^(historical_|runtime_seconds$|fit_converged$|fit_iterations$|diagnostic_|finite_pass$|sampled_)",
    names(fits), value = TRUE
  ))
  fit_columns <- unique(intersect(fit_columns, names(fits)))
  scores <- merge(scores, fits[, fit_columns, drop = FALSE], by = "job_id", all.x = TRUE, sort = FALSE)
}
expected_folds <- length(unique(jobs$fold_id))
aggregate <- if (nrow(scores)) app_glofas_search2_aggregate_scores(scores, require_folds = expected_folds) else data.frame()
app_write_csv(health, file.path(root, "tables", "health_latest.csv"))
app_write_csv(scores, file.path(root, "tables", "score_summaries_latest.csv"))
app_write_csv(fits, file.path(root, "tables", "fit_summaries_latest.csv"))
app_write_csv(aggregate, file.path(root, "tables", "aggregate_scores_latest.csv"))
print(health)
if (nrow(aggregate)) print(utils::head(aggregate, 20L))
