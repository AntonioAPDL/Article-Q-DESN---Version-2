#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R",
  "joint_qdesn_phase155_article_promotion.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  phase154_dir = "application/cache/joint_qdesn_phase154_balanced_mcmc_final_20260730",
  phase153_dir = "application/cache/joint_qdesn_phase153_balanced_independent_replication_vb_20260729",
  tables_dir = "tables",
  output_dir = "application/cache/joint_qdesn_phase155_article_promotion_20260731"
))

value <- function(name) {
  hyphen <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen]])) args[[hyphen]] else args[[name]]
}
resolve <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, winslash = "/", mustWork = must_work)
}

result <- app_joint_qdesn_run_phase155_article_promotion(
  phase154_dir = resolve(value("phase154_dir"), TRUE),
  phase153_dir = resolve(value("phase153_dir"), TRUE),
  tables_dir = resolve(value("tables_dir"), TRUE),
  out_dir = resolve(value("output_dir"), FALSE)
)

cat(sprintf("Joint QDESN Phase 155 article assets written to %s\n", result$out_dir))
cat(sprintf("Article tables written to %s\n", result$tables_dir))
print(result$promotion, row.names = FALSE)
cat("Forecast-MAE winners:\n")
print(
  result$winners[result$winners$metric == "mcmc_forecast_truth_mae",
    c("scenario_label", "best_model_label", "best_value", "best_margin"),
    drop = FALSE
  ],
  row.names = FALSE
)
