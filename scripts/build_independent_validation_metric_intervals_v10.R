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
validation_root <- normalizePath(
  arg_value("--validation-root", config$validation_root),
  winslash = "/", mustWork = TRUE
)
promotion_root <- normalizePath(
  file.path(validation_root, config$promotion_relative_path),
  winslash = "/", mustWork = TRUE
)
if (!startsWith(promotion_root, paste0(validation_root, "/"))) {
  stop("The promotion path escapes the validation root.", call. = FALSE)
}

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
verify_hash <- function(path, expected, label) {
  if (!identical(sha256(path), as.character(expected))) {
    stop(sprintf("%s SHA-256 mismatch.", label), call. = FALSE)
  }
}
source_path <- function(relative) {
  if (length(relative) != 1L || is.na(relative) || !nzchar(relative) ||
      grepl("^/", relative) || grepl("(^|/)\\.\\.(/|$)", relative)) {
    stop("The promotion ledger contains a nonportable path.", call. = FALSE)
  }
  path <- normalizePath(file.path(promotion_root, relative), winslash = "/", mustWork = TRUE)
  if (!startsWith(path, paste0(promotion_root, "/"))) {
    stop("A promotion artifact escapes the promotion root.", call. = FALSE)
  }
  path
}
article_path <- function(relative) {
  if (length(relative) != 1L || is.na(relative) || !nzchar(relative) ||
      grepl("^/", relative) || grepl("(^|/)\\.\\.(/|$)", relative)) {
    stop("An article destination is not portable.", call. = FALSE)
  }
  path <- file.path(repo_root, relative)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}

manifest_path <- file.path(promotion_root, "promotion_manifest.json")
ledger_path <- file.path(promotion_root, "promotion_file_ledger.csv")
interface_path <- file.path(
  promotion_root, "qdesn_dqlm_500obs_metric_intervals_v10_interface.csv"
)
asset_manifest_path <- file.path(promotion_root, "article_asset_manifest.csv")
verify_hash(manifest_path, config$promotion_manifest_sha256, "Promotion manifest")
verify_hash(ledger_path, config$promotion_file_ledger_sha256, "Promotion file ledger")
verify_hash(interface_path, config$interface_sha256, "v10 interface")
verify_hash(asset_manifest_path, config$article_asset_manifest_sha256, "Article asset manifest")

manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
expected <- config$expected
required_manifest <- c(
  status = "READY_FOR_INTEGRATION",
  promotion_id = config$promotion_id,
  run_id = config$run_id,
  rollback_authority = config$rollback_authority,
  estimator_id = config$estimator_id,
  scientific_execution_commit = config$scientific_execution_commit
)
for (field in names(required_manifest)) {
  if (!identical(as.character(manifest[[field]]), as.character(required_manifest[[field]]))) {
    stop(sprintf("Promotion manifest field %s is inconsistent.", field), call. = FALSE)
  }
}
count_fields <- c(
  jobs = "jobs", sources = "sources", source_metric_rows = "source_metric_rows",
  metric_roles = "metric_roles", interface_rows = "interface_rows",
  vb_rows = "vb_rows", mcmc_rows = "mcmc_rows",
  mcmc_diagnostic_pass_rows = "mcmc_diagnostic_pass_rows",
  mcmc_diagnostic_warn_rows = "mcmc_diagnostic_warn_rows",
  article_assets = "article_assets"
)
for (field in names(count_fields)) {
  if (!identical(as.integer(manifest[[field]]), as.integer(expected[[count_fields[[field]]]]))) {
    stop(sprintf("Promotion manifest count %s is inconsistent.", field), call. = FALSE)
  }
}
if (!identical(as.integer(manifest$heavy_binary_count), 0L) ||
    !identical(as.character(manifest$file_ledger_sha256),
               as.character(config$promotion_file_ledger_sha256))) {
  stop("The promotion storage or ledger contract is inconsistent.", call. = FALSE)
}

ledger <- read.csv(ledger_path, check.names = FALSE)
if (nrow(ledger) != 16L || anyDuplicated(ledger$relative_path)) {
  stop("The promotion file ledger has the wrong cardinality.", call. = FALSE)
}
ledger_paths <- vapply(ledger$relative_path, source_path, character(1L))
if (!identical(unname(tools::sha256sum(ledger_paths)), unname(ledger$sha256))) {
  stop("A promotion artifact hash is stale.", call. = FALSE)
}

interface <- read.csv(interface_path, check.names = FALSE)
models <- unlist(expected$models, use.names = FALSE)
families <- unlist(expected$families, use.names = FALSE)
taus <- as.numeric(unlist(expected$taus, use.names = FALSE))
inference <- unlist(expected$inference, use.names = FALSE)
grid <- expand.grid(
  inference = inference, model_variant = models, family = families, tau = taus,
  stringsAsFactors = FALSE
)
key <- with(interface, paste(inference, model_variant, family, sprintf("%.2f", tau)))
grid_key <- with(grid, paste(inference, model_variant, family, sprintf("%.2f", tau)))
if (nrow(interface) != as.integer(expected$interface_rows) || anyDuplicated(key) ||
    !setequal(key, grid_key) ||
    any(interface$metric_estimator_contract != config$estimator_id) ||
    any(grepl("ridge", interface$model_variant, ignore.case = TRUE))) {
  stop("The v10 interface does not match the predeclared article grid.", call. = FALSE)
}

metric_stems <- c("fit", "forecast_mae", "forecast_check")
point_columns <- c("fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000")
for (i in seq_along(metric_stems)) {
  stem <- metric_stems[[i]]
  point <- as.numeric(interface[[point_columns[[i]]]])
  lower <- as.numeric(interface[[paste0(stem, "_cri_lower")]])
  median <- as.numeric(interface[[paste0(stem, "_posterior_median")]])
  upper <- as.numeric(interface[[paste0(stem, "_cri_upper")]])
  if (any(!is.finite(c(point, lower, median, upper))) ||
      any(lower > median) || any(median > upper) || any(point < lower) || any(point > upper)) {
    stop(sprintf("The %s interval contract failed.", stem), call. = FALSE)
  }
  draws <- as.integer(interface[[paste0(stem, "_n_draws")]])
  chains <- as.integer(interface[[paste0(stem, "_n_chains")]])
  if (any(draws[interface$inference == "vb"] != as.integer(expected$vb_draws)) ||
      any(chains[interface$inference == "vb"] != 1L) ||
      any(draws[interface$inference == "mcmc"] != as.integer(expected$mcmc_draws)) ||
      any(chains[interface$inference == "mcmc"] != as.integer(expected$mcmc_chains))) {
    stop(sprintf("The %s draw contract failed.", stem), call. = FALSE)
  }
}
displayed_grades <- unlist(interface[paste0(metric_stems, "_diagnostic_grade")], use.names = FALSE)
if (sum(displayed_grades == "WARN") != as.integer(expected$displayed_warning_metrics) ||
    any(!displayed_grades %in% c("PASS", "WARN", "APPROX"))) {
  stop("Displayed diagnostic grades violate the disclosure contract.", call. = FALSE)
}

diagnostics_path <- file.path(promotion_root, "mcmc_metric_diagnostics.csv")
diagnostics <- read.csv(diagnostics_path, check.names = FALSE)
if (nrow(diagnostics) != as.integer(expected$mcmc_diagnostic_rows) ||
    sum(diagnostics$diagnostic_grade == "PASS") != as.integer(expected$mcmc_diagnostic_pass_rows) ||
    sum(diagnostics$diagnostic_grade == "WARN") != as.integer(expected$mcmc_diagnostic_warn_rows)) {
  stop("MCMC diagnostic counts violate the disclosure contract.", call. = FALSE)
}

asset_manifest <- read.csv(asset_manifest_path, check.names = FALSE)
if (nrow(asset_manifest) != as.integer(expected$article_assets) ||
    anyDuplicated(asset_manifest$file) ||
    any(!startsWith(asset_manifest$article_destination, "tables/"))) {
  stop("The article asset manifest is malformed.", call. = FALSE)
}
polish_family_table <- function(path, file) {
  family <- if (endsWith(file, "_normal.tex")) {
    "Gaussian"
  } else if (endsWith(file, "_laplace.tex")) {
    "Laplace"
  } else if (endsWith(file, "_gausmix.tex")) {
    "Gaussian mixture"
  } else {
    return(invisible(FALSE))
  }
  is_vb <- grepl("_vb_", file, fixed = TRUE)
  prefix <- if (is_vb) "Approximate posterior" else "Posterior"
  interval <- if (is_vb) {
    "variational posterior means with equal-tailed 95\\% intervals"
  } else {
    "posterior means with equal-tailed 95\\% credible intervals"
  }
  disclosure <- if (is_vb) {
    ""
  } else {
    " A dagger marks a metric-level diagnostic warning."
  }
  caption <- sprintf(
    paste0(
      "\\caption{%s metric intervals for the %s single-quantile simulation family. ",
      "Entries are %s; lower is better, and boldface marks the lowest mean ",
      "by target and criterion.%s}"
    ),
    prefix, family, interval, disclosure
  )
  lines <- readLines(path, warn = FALSE)
  lines <- sub("\\begin{table}[!htbp]", "\\begin{table}[!ht]", lines, fixed = TRUE)
  size_at <- which(lines == "\\scriptsize")
  if (length(size_at) != 1L) {
    stop(sprintf("Could not identify the table size in %s.", file), call. = FALSE)
  }
  lines <- append(lines, "\\setstretch{1}", after = size_at)
  caption_at <- which(startsWith(lines, "\\caption{"))
  if (length(caption_at) != 1L) {
    stop(sprintf("Could not identify one caption in %s.", file), call. = FALSE)
  }
  lines[[caption_at]] <- caption
  writeLines(lines, path, useBytes = TRUE)
  invisible(TRUE)
}
polish_table_wrapper <- function(path, file) {
  if (!file %in% c(
    "qdesn_validation_500obs_mcmc_metric_interval_tables.tex",
    "qdesn_validation_500obs_vb_metric_interval_tables.tex"
  )) {
    return(invisible(FALSE))
  }
  lines <- readLines(path, warn = FALSE)
  inputs <- lines[grepl("^\\\\input\\{tables/qdesn_validation_500obs_", lines)]
  if (length(inputs) != 3L) {
    stop(sprintf("Could not identify three family panels in %s.", file), call. = FALSE)
  }
  writeLines(c(
    "\\clearpage", inputs[[1L]],
    "\\clearpage", inputs[[2L]],
    "\\clearpage", inputs[[3L]],
    "\\clearpage"
  ), path, useBytes = TRUE)
  invisible(TRUE)
}
for (i in seq_len(nrow(asset_manifest))) {
  source <- source_path(file.path("article_assets", asset_manifest$file[[i]]))
  verify_hash(source, asset_manifest$sha256[[i]], asset_manifest$file[[i]])
  destination <- article_path(asset_manifest$article_destination[[i]])
  if (!file.copy(source, destination, overwrite = TRUE, copy.mode = TRUE)) {
    stop(sprintf("Could not write %s.", asset_manifest$article_destination[[i]]), call. = FALSE)
  }
  polish_family_table(destination, asset_manifest$file[[i]])
  polish_table_wrapper(destination, asset_manifest$file[[i]])
}

summary_columns <- c(
  "inference", "model_variant", "model_label", "family", "tau",
  "fit_qtrue_rmse", "fit_cri_lower", "fit_posterior_median", "fit_cri_upper",
  "fit_n_draws", "fit_n_chains", "fit_diagnostic_grade", "fit_replay_id",
  "forecast_qtrue_mae_H1000", "forecast_mae_cri_lower",
  "forecast_mae_posterior_median", "forecast_mae_cri_upper",
  "forecast_mae_n_draws", "forecast_mae_n_chains",
  "forecast_mae_diagnostic_grade", "forecast_mae_replay_id",
  "forecast_check_loss_H1000", "forecast_check_cri_lower",
  "forecast_check_posterior_median", "forecast_check_cri_upper",
  "forecast_check_n_draws", "forecast_check_n_chains",
  "forecast_check_diagnostic_grade", "forecast_check_replay_id"
)
portable <- interface[summary_columns]
portable <- portable[order(
  match(portable$inference, inference), match(portable$family, families),
  portable$tau, match(portable$model_variant, models)
), , drop = FALSE]
summary_path <- article_path(config$outputs$portable_summary)
write.csv(portable, summary_path, row.names = FALSE, na = "")
diagnostic_output <- article_path(config$outputs$mcmc_diagnostics)
if (!file.copy(diagnostics_path, diagnostic_output, overwrite = TRUE, copy.mode = TRUE)) {
  stop("Could not write the portable MCMC diagnostic summary.", call. = FALSE)
}

metric_contract <- data.frame(
  metric = c("fit_rmse", "forecast_mae", "forecast_check_loss"),
  mean_column = c(
    "fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000"
  ),
  lower_column = c(
    "fit_cri_lower", "forecast_mae_cri_lower", "forecast_check_cri_lower"
  ),
  upper_column = c(
    "fit_cri_upper", "forecast_mae_cri_upper", "forecast_check_cri_upper"
  ),
  stringsAsFactors = FALSE
)
mcmc <- portable[portable$inference == "mcmc", , drop = FALSE]
comparison_rows <- list()
at <- 0L
for (family in families) {
  for (tau in taus) {
    cell <- mcmc[mcmc$family == family & abs(mcmc$tau - tau) < 1e-12, , drop = FALSE]
    if (nrow(cell) != length(models)) {
      stop("An MCMC comparison cell does not contain all four models.", call. = FALSE)
    }
    for (j in seq_len(nrow(metric_contract))) {
      contract <- metric_contract[j, , drop = FALSE]
      means <- as.numeric(cell[[contract$mean_column]])
      ord <- order(means, match(cell$model_variant, models))
      winner <- cell[ord[[1L]], , drop = FALSE]
      runner <- cell[ord[[2L]], , drop = FALSE]
      winner_lower <- as.numeric(winner[[contract$lower_column]])
      winner_upper <- as.numeric(winner[[contract$upper_column]])
      runner_lower <- as.numeric(runner[[contract$lower_column]])
      runner_upper <- as.numeric(runner[[contract$upper_column]])
      at <- at + 1L
      comparison_rows[[at]] <- data.frame(
        family = family,
        tau = tau,
        metric = contract$metric,
        winner_model_variant = winner$model_variant,
        winner_model_label = winner$model_label,
        winner_posterior_mean = means[ord[[1L]]],
        winner_cri_lower = winner_lower,
        winner_cri_upper = winner_upper,
        runner_up_model_variant = runner$model_variant,
        runner_up_model_label = runner$model_label,
        runner_up_posterior_mean = means[ord[[2L]]],
        runner_up_cri_lower = runner_lower,
        runner_up_cri_upper = runner_upper,
        posterior_mean_gap = means[ord[[2L]]] - means[ord[[1L]]],
        winner_runner_intervals_overlap =
          max(winner_lower, runner_lower) <= min(winner_upper, runner_upper),
        stringsAsFactors = FALSE
      )
    }
  }
}
comparison <- do.call(rbind, comparison_rows)
winner_counts <- table(factor(comparison$winner_model_variant, levels = models))
expected_winner_counts <- c(
  dqlm = as.integer(expected$mcmc_winner_dqlm),
  exdqlm = as.integer(expected$mcmc_winner_exdqlm),
  qdesn_al_rhs_ns = as.integer(expected$mcmc_winner_qdesn_al_rhs_ns),
  qdesn_exal_rhs_ns = as.integer(expected$mcmc_winner_qdesn_exal_rhs_ns)
)
if (nrow(comparison) != as.integer(expected$mcmc_metric_cells) ||
    !identical(as.integer(winner_counts), unname(expected_winner_counts)) ||
    sum(comparison$winner_runner_intervals_overlap) !=
      as.integer(expected$mcmc_winner_interval_overlaps) ||
    sum(grepl("^qdesn_", comparison$winner_model_variant)) !=
      as.integer(expected$qdesn_mcmc_winner_cells)) {
  stop("The MCMC winner and interval-overlap audit is stale.", call. = FALSE)
}
comparison_path <- article_path(config$outputs$mcmc_comparison)
write.csv(comparison, comparison_path, row.names = FALSE, na = "")

results_prose_path <- article_path(config$outputs$results_prose)
writeLines(c(
  sprintf(
    paste0(
      "Across the %d family--quantile--criterion comparisons in the MCMC panels, ",
      "Q--DESN exAL--RHS has the lowest posterior mean in %d comparisons and ",
      "Q--DESN AL--RHS in %d; DQLM and exDQLM each have the lowest mean in %d. ",
      "The two Q--DESN variants therefore account for %d of the %d lowest posterior means."
    ),
    nrow(comparison), expected_winner_counts[["qdesn_exal_rhs_ns"]],
    expected_winner_counts[["qdesn_al_rhs_ns"]],
    expected_winner_counts[["dqlm"]],
    as.integer(expected$qdesn_mcmc_winner_cells), nrow(comparison)
  ),
  "",
  sprintf(
    paste0(
      "For all %d comparisons, the equal-tailed intervals of the lowest and ",
      "second-lowest posterior means overlap. The boldface rankings are ",
      "conditional posterior-mean summaries under the pre-specified case- and ",
      "criterion-specific model specifications. The interval overlap limits ",
      "inference about separation between the two lowest-scoring methods."
    ),
    sum(comparison$winner_runner_intervals_overlap)
  )
), results_prose_path, useBytes = TRUE)

article_artifacts <- c(
  asset_manifest$article_destination,
  config$outputs$portable_summary,
  config$outputs$mcmc_diagnostics,
  config$outputs$mcmc_comparison,
  config$outputs$results_prose
)
article_artifact_paths <- vapply(article_artifacts, article_path, character(1L))
article_hashes <- unname(tools::sha256sum(article_artifact_paths))
article_manifest_path <- article_path(config$outputs$article_manifest)
writeLines(c(
  paste0("promotion_id: ", config$promotion_id),
  paste0("run_id: ", config$run_id),
  paste0("validation_handoff_commit: ", config$validation_handoff_commit),
  paste0("scientific_execution_commit: ", config$scientific_execution_commit),
  paste0("rollback_authority: ", config$rollback_authority),
  paste0("estimator_id: ", config$estimator_id),
  paste0("promotion_manifest_sha256: ", config$promotion_manifest_sha256),
  paste0("promotion_file_ledger_sha256: ", config$promotion_file_ledger_sha256),
  paste0("interface_sha256: ", config$interface_sha256),
  paste0("article_asset_manifest_sha256: ", config$article_asset_manifest_sha256),
  "article_artifacts:",
  paste0("  ", article_artifacts, ": ", article_hashes)
), article_manifest_path, useBytes = TRUE)
if (length(article_artifacts) != as.integer(expected$article_generated_artifacts)) {
  stop("The generated article artifact count is stale.", call. = FALSE)
}

cat("INDEPENDENT_METRIC_INTERVAL_BUILD=PASS\n")
cat(sprintf("ROWS=%d VB=%d MCMC=%d WARN_SOURCE_METRICS=%d WARN_DISPLAYED=%d\n",
            nrow(interface), sum(interface$inference == "vb"),
            sum(interface$inference == "mcmc"),
            sum(diagnostics$diagnostic_grade == "WARN"),
            sum(displayed_grades == "WARN")))
