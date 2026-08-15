repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
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

verify_manifest <- function(dir) {
  manifest <- app_read_csv(file.path(dir, "artifact_manifest.csv"))
  stopifnot(nrow(manifest) > 0L, all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
}

phase154_dir <- app_joint_qdesn_phase154_default_final_dir()
phase153_dir <- app_joint_qdesn_phase153_default_vb_dir()
stopifnot(dir.exists(phase154_dir), dir.exists(phase153_dir))

tables_dir <- tempfile("phase155_tables_")
out_dir <- tempfile("phase155_assets_")
dir.create(tables_dir, recursive = TRUE)
result <- app_joint_qdesn_run_phase155_article_promotion(
  phase154_dir = phase154_dir,
  phase153_dir = phase153_dir,
  tables_dir = tables_dir,
  out_dir = out_dir
)

stopifnot(identical(result$promotion$hard_implementation_gate[[1L]], "pass"))
stopifnot(identical(result$promotion$gate_status[[1L]], "review"))
stopifnot(nrow(result$case_summary) == 32L)
stopifnot(nrow(result$main_table_data) == 8L)
stopifnot(nrow(result$model_summary) == 4L)
stopifnot(nrow(result$winners) == 32L)
stopifnot(sum(result$case_summary$mcmc_forecast_raw_crossing_pairs) == 25L)
stopifnot(sum(result$case_summary$mcmc_forecast_contract_crossing_pairs) == 0L)
stopifnot(max(result$case_summary$max_chain_qhat_normalized_distance) < 0.01)

forecast_winners <- result$winners[result$winners$metric == "mcmc_forecast_truth_mae", , drop = FALSE]
winner_counts <- table(factor(
  forecast_winners$best_source_model_id,
  levels = app_joint_qdesn_phase155_model_dictionary()$source_model_id
))
stopifnot(identical(as.integer(winner_counts), c(4L, 2L, 0L, 2L)))

fit_winners <- result$winners[result$winners$metric == "mcmc_fit_truth_mae", , drop = FALSE]
fit_counts <- table(factor(
  fit_winners$best_source_model_id,
  levels = app_joint_qdesn_phase155_model_dictionary()$source_model_id
))
stopifnot(identical(as.integer(fit_counts), c(6L, 0L, 0L, 2L)))

replication <- app_read_csv(file.path(out_dir, "phase153_replication_summary.csv"))
stopifnot(nrow(replication) == 8L)
stopifnot(all(replication$Replicates == 50L))
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_model_summary.tex")))
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_phase153_replication_summary.tex")))
stopifnot(all(app_joint_qdesn_phase155_verify_article_manifest(
  file.path(out_dir, "article_asset_manifest.csv")
)$verified))
verify_manifest(out_dir)

main_tex <- tempfile("phase155_main_", fileext = ".tex")
supp_tex <- tempfile("phase155_supp_", fileext = ".tex")
writeLines(c(
  "The balanced MCMC confirmation provides posterior quantile-grid readout paths, not a scalar predictive density.",
  "The replicated VB layer uses 50 independently generated fixtures per cell.",
  "Joint AL wins four of the eight scenarios; the other rows win two scenarios each.",
  "Joint AL is best in six of the eight fit windows.",
  "Independent AL accounts for 24 of the 25 raw forecast-window crossings.",
  "There are zero crossings after the monotone reporting rule.",
  "\\input{tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.tex}"
), main_tex)
writeLines("\\input{tables/joint_qdesn_article_validation_provenance_tables.tex}", supp_tex)
audit <- app_joint_qdesn_run_phase155_article_audit(
  phase155_dir = out_dir,
  main_tex = main_tex,
  supplement_tex = supp_tex,
  out_dir = tempfile("phase155_audit_")
)
stopifnot(identical(audit$summary$audit_status[[1L]], "review"))
stopifnot(audit$summary$failed_checks[[1L]] == 0L)
verify_manifest(audit$out_dir)

cat("Joint QDESN Phase155 article-promotion tests passed.\n")
