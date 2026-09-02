#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))

args <- app_parse_args(list(runtime_root = ""))
runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
rhs_manifest <- app_read_csv(file.path(runtime_root, "configs", "top10_rhs_tau0_manifest.csv"))
top10 <- app_read_csv(file.path(runtime_root, "configs", "top10_ridge_candidates.csv"))
rhs_ids <- as.character(rhs_manifest$rhs_candidate_id)
warm_ids <- as.character(top10$candidate_id)

count_status <- function(ids, suffix) {
  sum(file.exists(file.path(runtime_root, "status", paste0(ids, suffix))))
}
warm_summary <- data.frame(
  phase = "ridge_warm_start",
  total = length(warm_ids),
  completed = count_status(warm_ids, ".warm.done"),
  running = count_status(warm_ids, ".warm.running"),
  failed = count_status(warm_ids, ".warm.failed"),
  stringsAsFactors = FALSE
)
warm_summary$pending <- warm_summary$total - warm_summary$completed - warm_summary$running - warm_summary$failed
rhs_summary <- data.frame(
  phase = "normal_rhs_vb",
  total = length(rhs_ids),
  completed = count_status(rhs_ids, ".done"),
  running = count_status(rhs_ids, ".running"),
  failed = count_status(rhs_ids, ".failed"),
  stringsAsFactors = FALSE
)
rhs_summary$pending <- rhs_summary$total - rhs_summary$completed - rhs_summary$running - rhs_summary$failed
health <- rbind(warm_summary, rhs_summary)
app_write_csv(health, file.path(runtime_root, "tables", "normal_rhs_health_latest.csv"))

scores <- app_glofas_normal_part1_collect_rhs_scores(runtime_root)
print(health)
if (nrow(scores)) {
  cols <- intersect(
    c(
      "rank_valid_crps", "rhs_candidate_id", "candidate_id", "rhs_tau0",
      "D", "n_vector", "lag_id", "alpha", "rho", "valid_mean_crps",
      "valid_mae", "valid_rmse", "valid_last200_mean_crps",
      "valid_last50_mean_crps", "converged", "iterations",
      "runtime_seconds", "status"
    ),
    names(scores)
  )
  print(utils::head(scores[, cols, drop = FALSE], 10L))
}
