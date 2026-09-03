#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))

args <- app_parse_args(list(runtime_root = ""))
runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
manifest <- app_read_csv(file.path(runtime_root, "configs", "candidate_manifest.csv"))
candidate_ids <- as.character(manifest$candidate_id)

count_status <- function(ext) {
  sum(file.exists(file.path(runtime_root, "status", paste0(candidate_ids, ext))))
}
completed <- count_status(".done")
running <- count_status(".running")
failed <- count_status(".failed")
pending <- length(candidate_ids) - completed - running - failed
summary <- data.frame(
  runtime_root = runtime_root,
  total = length(candidate_ids),
  completed = completed,
  running = running,
  failed = failed,
  pending = pending,
  percent_complete = round(100 * completed / max(1L, length(candidate_ids)), 2),
  percent_finished = round(100 * (completed + failed) / max(1L, length(candidate_ids)), 2),
  checked_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  stringsAsFactors = FALSE
)
scores <- app_glofas_normal_part2_collect_scores(runtime_root)
app_write_csv(summary, file.path(runtime_root, "tables", "health_latest.csv"))
print(summary)
if (nrow(scores)) {
  cols <- intersect(
    c(
      "rank_corrected_valid_crps", "rank_discrepancy_valid_crps", "candidate_id",
      "disc_input_contract", "disc_geometry_id", "disc_dynamics_id",
      "disc_n_state_features", "disc_alpha", "disc_rho",
      "corrected_valid_mean_crps", "corrected_valid_mae", "corrected_valid_rmse",
      "discrepancy_valid_mean_crps", "discrepancy_valid_mae", "discrepancy_valid_rmse",
      "raw_valid_mae", "corrected_lag1_valid_mae", "runtime_seconds", "status"
    ),
    names(scores)
  )
  print(utils::head(scores[, cols, drop = FALSE], 10L))
}
