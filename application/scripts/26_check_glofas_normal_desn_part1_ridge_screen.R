#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))

args <- app_parse_args(list(runtime_root = ""))
runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
manifest <- app_read_csv(file.path(runtime_root, "configs", "candidate_manifest.csv"))
candidate_ids <- as.character(manifest$candidate_id)
count_status <- function(ext) {
  sum(file.exists(file.path(runtime_root, "status", paste0(candidate_ids, ext))))
}
summary <- data.frame(
  runtime_root = runtime_root,
  total = length(candidate_ids),
  completed = count_status(".done"),
  running = count_status(".running"),
  failed = count_status(".failed"),
  pending = length(candidate_ids) - count_status(".done") - count_status(".running") - count_status(".failed"),
  stringsAsFactors = FALSE
)
scores <- app_glofas_normal_part1_collect_scores(runtime_root)
app_write_csv(summary, file.path(runtime_root, "tables", "health_latest.csv"))
print(summary)
if (nrow(scores)) {
  cols <- intersect(
    c("rank_valid_crps", "candidate_id", "geometry_id", "lag_id", "dynamics_id",
      "n_state_features", "output_lag_max", "covariate_lag_max", "alpha", "rho",
      "valid_mean_crps", "valid_mae", "valid_rmse", "runtime_seconds", "status"),
    names(scores)
  )
  print(utils::head(scores[, cols, drop = FALSE], 10L))
}
