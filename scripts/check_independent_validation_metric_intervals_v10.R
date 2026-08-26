#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/", mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- which(args == flag)
  if (!length(at) || at[[1L]] == length(args)) return(default)
  args[[at[[1L]] + 1L]]
}
config_path <- normalizePath(
  arg_value("--config", file.path(
    repo_root, "application", "config", "independent_validation_metric_intervals_v10.yaml"
  )),
  winslash = "/", mustWork = TRUE
)
config <- yaml::read_yaml(config_path)

summary_path <- file.path(repo_root, config$outputs$portable_summary)
diagnostics_path <- file.path(repo_root, config$outputs$mcmc_diagnostics)
comparison_path <- file.path(repo_root, config$outputs$mcmc_comparison)
results_prose_path <- file.path(repo_root, config$outputs$results_prose)
manifest_path <- file.path(repo_root, config$outputs$article_manifest)
required <- c(summary_path, diagnostics_path, comparison_path, results_prose_path, manifest_path)
if (any(!file.exists(required))) stop("A generated v10 article artifact is missing.", call. = FALSE)

summary <- read.csv(summary_path, check.names = FALSE)
diagnostics <- read.csv(diagnostics_path, check.names = FALSE)
comparison <- read.csv(comparison_path, check.names = FALSE)
expected <- config$expected
if (nrow(summary) != as.integer(expected$interface_rows) ||
    sum(summary$inference == "vb") != as.integer(expected$vb_rows) ||
    sum(summary$inference == "mcmc") != as.integer(expected$mcmc_rows) ||
    nrow(diagnostics) != as.integer(expected$mcmc_diagnostic_rows) ||
    sum(diagnostics$diagnostic_grade == "WARN") != as.integer(expected$mcmc_diagnostic_warn_rows)) {
  stop("The generated v10 article summaries have stale counts.", call. = FALSE)
}
winner_counts <- table(factor(
  comparison$winner_model_variant,
  levels = unlist(expected$models, use.names = FALSE)
))
expected_winner_counts <- c(
  as.integer(expected$mcmc_winner_dqlm),
  as.integer(expected$mcmc_winner_exdqlm),
  as.integer(expected$mcmc_winner_qdesn_al_rhs_ns),
  as.integer(expected$mcmc_winner_qdesn_exal_rhs_ns)
)
if (nrow(comparison) != as.integer(expected$mcmc_metric_cells) ||
    !identical(as.integer(winner_counts), expected_winner_counts) ||
    sum(comparison$winner_runner_intervals_overlap) !=
      as.integer(expected$mcmc_winner_interval_overlaps) ||
    sum(grepl("^qdesn_", comparison$winner_model_variant)) !=
      as.integer(expected$qdesn_mcmc_winner_cells)) {
  stop("The generated MCMC winner audit is stale.", call. = FALSE)
}

manifest <- readLines(manifest_path, warn = FALSE)
required_manifest_values <- c(
  config$promotion_id, config$run_id, config$validation_handoff_commit,
  config$scientific_execution_commit, config$rollback_authority,
  config$estimator_id, config$promotion_manifest_sha256,
  config$promotion_file_ledger_sha256, config$interface_sha256,
  config$article_asset_manifest_sha256
)
if (any(!vapply(required_manifest_values, function(value) {
  any(grepl(as.character(value), manifest, fixed = TRUE))
}, logical(1L)))) {
  stop("The generated article manifest is missing pinned provenance.", call. = FALSE)
}

entries <- grep("^  tables/[^:]+: [[:xdigit:]]{64}$", manifest, value = TRUE)
paths <- sub("^  ([^:]+): [[:xdigit:]]{64}$", "\\1", entries)
hashes <- sub("^  [^:]+: ([[:xdigit:]]{64})$", "\\1", entries)
artifact_paths <- file.path(repo_root, paths)
if (length(entries) != as.integer(expected$article_generated_artifacts) ||
    any(!file.exists(artifact_paths)) ||
    !identical(unname(tools::sha256sum(artifact_paths)), unname(hashes))) {
  stop("A generated interval-table artifact hash is stale.", call. = FALSE)
}

main <- paste(readLines(file.path(repo_root, "main.tex"), warn = FALSE), collapse = "\n")
supplement <- paste(readLines(file.path(repo_root, "qdesn-supplement.tex"), warn = FALSE), collapse = "\n")
main_required <- c(
  "tables/qdesn_validation_500obs_metric_intervals_prose.tex",
  "tables/qdesn_validation_500obs_metric_interval_contract_clarification.tex",
  "tables/qdesn_validation_500obs_metric_interval_results_v10.tex",
  "tables/qdesn_validation_500obs_mcmc_metric_interval_figures.tex",
  "fig:simulation-500obs-mcmc-fit-rmse-intervals",
  "fig:simulation-500obs-mcmc-forecast-check-loss-intervals",
  "draw-wise criteria",
  "empirical 0.025 and 0.975"
)
supp_required <- c(
  "tables/qdesn_validation_500obs_mcmc_metric_interval_tables.tex",
  "tables/qdesn_validation_500obs_vb_metric_interval_figures.tex",
  "tables/qdesn_validation_500obs_vb_metric_interval_tables.tex",
  "draw-wise fit RMSE",
  "approximate"
)
if (any(!vapply(main_required, grepl, logical(1L), x = main, fixed = TRUE)) ||
    any(!vapply(supp_required, grepl, logical(1L), x = supplement, fixed = TRUE)) ||
    grepl("tables/qdesn_validation_tt500_final_mcmc_tables.tex", main, fixed = TRUE) ||
    grepl("tables/qdesn_validation_tt500_final_tables.tex", supplement, fixed = TRUE) ||
    grepl("Two case-specific repeated-chain confirmations yielded", main, fixed = TRUE) ||
    grepl("deterministic criterion values", main, fixed = TRUE)) {
  stop("The manuscripts are not consistently wired to v10.", call. = FALSE)
}

results_prose <- paste(readLines(results_prose_path, warn = FALSE), collapse = "\n")
if (!grepl("19 of the 27", results_prose, fixed = TRUE) ||
    !grepl("all 27 cells", tolower(results_prose), fixed = TRUE)) {
  stop("The generated interpretation is stale.", call. = FALSE)
}

mcmc_tables <- paste(readLines(file.path(
  repo_root, "tables", "qdesn_validation_500obs_mcmc_metric_interval_tables.tex"
)), collapse = "\n")
vb_tables <- paste(readLines(file.path(
  repo_root, "tables", "qdesn_validation_500obs_vb_metric_interval_tables.tex"
)), collapse = "\n")
if (lengths(regmatches(mcmc_tables, gregexpr("qdesn_validation_500obs_mcmc_metric_intervals_", mcmc_tables, fixed = TRUE))) != 3L ||
    lengths(regmatches(vb_tables, gregexpr("qdesn_validation_500obs_vb_metric_intervals_", vb_tables, fixed = TRUE))) != 3L) {
  stop("The family-table wrappers do not contain three panels each.", call. = FALSE)
}
wrapper_lines <- lapply(c(
  file.path(repo_root, "tables", "qdesn_validation_500obs_mcmc_metric_interval_tables.tex"),
  file.path(repo_root, "tables", "qdesn_validation_500obs_vb_metric_interval_tables.tex")
), readLines, warn = FALSE)
if (any(vapply(wrapper_lines, function(lines) {
  length(lines) != 7L ||
    !identical(lines[c(1L, 3L, 5L, 7L)], rep("\\clearpage", 4L))
}, logical(1L)))) {
  stop("The family-table page-boundary contract failed.", call. = FALSE)
}
family_tables <- file.path(repo_root, "tables", c(
  "qdesn_validation_500obs_mcmc_metric_intervals_normal.tex",
  "qdesn_validation_500obs_mcmc_metric_intervals_laplace.tex",
  "qdesn_validation_500obs_mcmc_metric_intervals_gausmix.tex",
  "qdesn_validation_500obs_vb_metric_intervals_normal.tex",
  "qdesn_validation_500obs_vb_metric_intervals_laplace.tex",
  "qdesn_validation_500obs_vb_metric_intervals_gausmix.tex"
))
family_table_text <- vapply(
  family_tables,
  function(path) paste(readLines(path, warn = FALSE), collapse = "\n"),
  character(1L)
)
if (any(!grepl("\\begin{table}[!ht]", family_table_text, fixed = TRUE)) ||
    any(!grepl("\\setstretch{1}", family_table_text, fixed = TRUE)) ||
    any(grepl("oracle training path", family_table_text, fixed = TRUE)) ||
    any(nchar(sub(".*(\\\\caption\\{[^\n]+).*", "\\1", family_table_text)) > 700L)) {
  stop("The compact family-table presentation contract failed.", call. = FALSE)
}

figure_files <- file.path(repo_root, "figures", "independent_simulation", c(
  "qdesn_validation_500obs_mcmc_fit_rmse_intervals.pdf",
  "qdesn_validation_500obs_mcmc_forecast_mae_intervals.pdf",
  "qdesn_validation_500obs_mcmc_forecast_check_loss_intervals.pdf",
  "qdesn_validation_500obs_vb_fit_rmse_intervals.pdf",
  "qdesn_validation_500obs_vb_forecast_mae_intervals.pdf",
  "qdesn_validation_500obs_vb_forecast_check_loss_intervals.pdf"
))
figure_wrappers <- file.path(repo_root, "tables", c(
  "qdesn_validation_500obs_mcmc_metric_interval_figures.tex",
  "qdesn_validation_500obs_vb_metric_interval_figures.tex",
  "qdesn_validation_500obs_metric_interval_contract_clarification.tex"
))
if (any(!file.exists(figure_files)) ||
    any(file.info(figure_files)$size <= 10000L) ||
    any(!file.exists(figure_wrappers))) {
  stop("The metric-interval figure presentation is incomplete.", call. = FALSE)
}

cat("INDEPENDENT_METRIC_INTERVAL_CHECK=PASS\n")
cat(sprintf("ROWS=%d VB=%d MCMC=%d SOURCE_WARN=%d\n",
            nrow(summary), sum(summary$inference == "vb"),
            sum(summary$inference == "mcmc"),
            sum(diagnostics$diagnostic_grade == "WARN")))
