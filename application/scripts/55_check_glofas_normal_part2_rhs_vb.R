#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))

args <- app_parse_args(list(runtime_root = ""))
runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
rhs_manifest <- app_read_csv(file.path(runtime_root, "configs", "part2_rhs_tau0_manifest.csv"))
top <- app_read_csv(file.path(runtime_root, "configs", "top_ridge_candidates.csv"))
rhs_ids <- as.character(rhs_manifest$rhs_candidate_id)
warm_ids <- as.character(top$candidate_id)

count_status <- function(ids, suffix) {
  sum(file.exists(file.path(runtime_root, "status", paste0(ids, suffix))))
}
warm_summary <- data.frame(
  phase = "part2_ridge_warm_start",
  total = length(warm_ids),
  completed = count_status(warm_ids, ".warm.done"),
  running = count_status(warm_ids, ".warm.running"),
  failed = count_status(warm_ids, ".warm.failed"),
  stringsAsFactors = FALSE
)
warm_summary$pending <- warm_summary$total - warm_summary$completed - warm_summary$running - warm_summary$failed
rhs_summary <- data.frame(
  phase = "part2_normal_rhs_vb",
  total = length(rhs_ids),
  completed = count_status(rhs_ids, ".done"),
  running = count_status(rhs_ids, ".running"),
  failed = count_status(rhs_ids, ".failed"),
  stringsAsFactors = FALSE
)
rhs_summary$pending <- rhs_summary$total - rhs_summary$completed - rhs_summary$running - rhs_summary$failed
health <- rbind(warm_summary, rhs_summary)
health$checked_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
app_write_csv(health, file.path(runtime_root, "tables", "part2_rhs_health_latest.csv"))

scores <- app_glofas_normal_part2_collect_rhs_scores(runtime_root)
print(health)
if (nrow(scores)) {
  cols <- intersect(
    c(
      "rank_corrected_valid_crps", "rank_discrepancy_valid_crps",
      "rhs_candidate_id", "candidate_id", "disc_input_contract",
      "disc_geometry_id", "disc_dynamics_id", "rhs_tau0_reference",
      "rhs_tau0_discrepancy", "corrected_valid_mean_crps",
      "corrected_valid_mae", "corrected_valid_rmse",
      "discrepancy_valid_mean_crps", "discrepancy_valid_mae",
      "discrepancy_valid_rmse", "corrected_valid_last200_mean_crps",
      "discrepancy_valid_last200_mean_crps", "reference_iterations",
      "discrepancy_iterations", "reference_converged",
      "discrepancy_converged", "runtime_seconds", "status"
    ),
    names(scores)
  )
  print(utils::head(scores[, cols, drop = FALSE], 10L))
}
