#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/",
  mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  idx <- which(args == flag)
  if (!length(idx) || idx[[1L]] == length(args)) return(default)
  args[[idx[[1L]] + 1L]]
}

config_path <- normalizePath(
  get_arg(
    "--config",
    file.path(repo_root, "application", "config", "independent_validation_trainonly_v1.yaml")
  ),
  winslash = "/",
  mustWork = TRUE
)
config <- yaml::read_yaml(config_path)
validation_root <- normalizePath(
  get_arg("--validation-root", config$validation_root),
  winslash = "/",
  mustWork = TRUE
)

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
resolve_validation <- function(relative_path, label) {
  path <- normalizePath(file.path(validation_root, relative_path), winslash = "/", mustWork = TRUE)
  if (!startsWith(path, paste0(validation_root, "/"))) {
    stop(sprintf("%s escapes the validation root.", label), call. = FALSE)
  }
  path
}
resolve_article <- function(relative_path) {
  path <- file.path(repo_root, relative_path)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}
verify_hash <- function(path, expected, label) {
  observed <- sha256(path)
  if (!identical(observed, as.character(expected))) {
    stop(sprintf("%s SHA-256 mismatch.", label), call. = FALSE)
  }
  invisible(path)
}
as_bool <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  tolower(as.character(x)) %in% c("true", "t", "1", "yes")
}
resolve_portable_validation_path <- function(path, label) {
  if (length(path) != 1L || is.na(path) || !nzchar(path) || grepl("^/", path)) {
    stop(sprintf("%s must be a nonempty validation-relative path.", label), call. = FALSE)
  }
  resolved <- normalizePath(file.path(validation_root, path), winslash = "/", mustWork = TRUE)
  if (!startsWith(resolved, paste0(validation_root, "/"))) {
    stop(sprintf("%s escapes the validation root.", label), call. = FALSE)
  }
  resolved
}
portable_metric_source <- function(path, label) {
  marker <- "validation/fitforecast_v2/"
  at <- regexpr(marker, path, fixed = TRUE)
  if (at[[1L]] < 1L) {
    stop(sprintf("%s has no portable validation path.", label), call. = FALSE)
  }
  resolve_portable_validation_path(substring(path, at[[1L]]), label)
}

interface_path <- resolve_validation(config$interface_relative_path, "Interface")
source_manifest_path <- resolve_validation(config$manifest_relative_path, "Manifest")
source_ledger_path <- resolve_validation(config$source_ledger_relative_path, "Source ledger")
article_delta_path <- resolve_validation(config$article_delta_relative_path, "Article delta")
promotion_decision_path <- resolve_validation(
  config$promotion_decision_ledger_relative_path,
  "Promotion decision ledger"
)
remaining_gap_path <- resolve_validation(config$remaining_gap_ledger_relative_path, "Remaining-gap ledger")
verify_hash(interface_path, config$interface_sha256, "Interface")
verify_hash(source_manifest_path, config$manifest_sha256, "Manifest")
verify_hash(source_ledger_path, config$source_ledger_sha256, "Source ledger")
verify_hash(article_delta_path, config$article_delta_sha256, "Article delta")
verify_hash(promotion_decision_path, config$promotion_decision_ledger_sha256, "Promotion decision ledger")
verify_hash(remaining_gap_path, config$remaining_gap_ledger_sha256, "Remaining-gap ledger")

source_manifest <- jsonlite::read_json(source_manifest_path, simplifyVector = TRUE)
source_ledger <- read.csv(source_ledger_path, check.names = FALSE, stringsAsFactors = FALSE)
manifest_jobs <- as.integer(unlist(source_manifest$campaign_jobs, use.names = TRUE))
expected_jobs <- as.integer(unlist(config$campaign_jobs, use.names = TRUE))
names(manifest_jobs) <- names(unlist(source_manifest$campaign_jobs, use.names = TRUE))
names(expected_jobs) <- names(unlist(config$campaign_jobs, use.names = TRUE))
if (!identical(as.character(source_manifest$promotion_id), as.character(config$promotion_id)) ||
    !identical(as.character(source_manifest$promotion_status), as.character(config$promotion_status)) ||
    !identical(as.character(source_manifest$scientific_decision), as.character(config$scientific_decision)) ||
    !identical(as.character(source_manifest$base_promotion_id), as.character(config$base_promotion_id)) ||
    !identical(as.character(source_manifest$rendered_article_base_id),
               as.character(config$rendered_article_base_id)) ||
    !identical(as.character(source_manifest$exal_method_id), as.character(config$exal_method_id)) ||
    !identical(as.character(source_manifest$al_method_id), as.character(config$al_method_id)) ||
    !identical(as.character(source_manifest$run_id), as.character(config$campaign_run_id)) ||
    !identical(as.character(source_manifest$run_tag), as.character(config$campaign_run_tag)) ||
    !identical(as.character(source_manifest$scientific_design_commit),
               as.character(config$scientific_design_commit)) ||
    !identical(as.character(source_manifest$confirmation_execution_commit),
               as.character(config$confirmation_execution_commit)) ||
    !identical(as.character(source_manifest$closeout_implementation_commit),
               as.character(config$closeout_implementation_commit)) ||
    !identical(manifest_jobs, expected_jobs) ||
    !identical(as.integer(source_manifest$canonical_chains), as.integer(config$canonical_chains)) ||
    !identical(as.integer(source_manifest$promoted_metric_roles), as.integer(config$promoted_metric_roles)) ||
    !identical(as.integer(source_manifest$article_numeric_updates_from_rendered_v6),
               as.integer(config$article_numeric_updates_from_rendered_base)) ||
    !identical(as.integer(source_manifest$retained_iterations_per_chain),
               as.integer(config$retained_iterations_per_chain)) ||
    !identical(as.integer(source_manifest$observed_rows), as.integer(config$expected_rows)) ||
    !identical(as.integer(source_manifest$binary_payload_count), 0L) ||
    !isTRUE(source_manifest$storage_policy_pass) ||
    !identical(as.character(source_manifest$article_interface_sha256), as.character(config$interface_sha256)) ||
    !identical(as.character(source_manifest$source_ledger_sha256), as.character(config$source_ledger_sha256)) ||
    !identical(as.character(source_manifest$article_delta_sha256), as.character(config$article_delta_sha256)) ||
    !identical(as.character(source_manifest$promotion_decision_ledger_sha256),
               as.character(config$promotion_decision_ledger_sha256)) ||
    !identical(as.character(source_manifest$remaining_gap_ledger_sha256),
               as.character(config$remaining_gap_ledger_sha256)) ||
    !identical(as.character(source_manifest$source_registry_hash_value),
               as.character(config$source_registry_hash_value))) {
  stop("The source manifest violates the article configuration.", call. = FALSE)
}
if (!all(c("source_id", "path", "sha256", "role") %in% names(source_ledger)) ||
    anyDuplicated(source_ledger$source_id) || any(grepl("^/", source_ledger$path))) {
  stop("The validation source ledger is malformed or nonportable.", call. = FALSE)
}
source_ledger_paths <- vapply(seq_len(nrow(source_ledger)), function(i) {
  resolve_portable_validation_path(source_ledger$path[[i]], sprintf("Source ledger row %d", i))
}, character(1L))
if (!identical(unname(tools::sha256sum(source_ledger_paths)), unname(source_ledger$sha256))) {
  stop("The validation source ledger is incomplete or stale.", call. = FALSE)
}

source <- read.csv(interface_path, check.names = FALSE, stringsAsFactors = FALSE)
article_delta <- read.csv(article_delta_path, check.names = FALSE, stringsAsFactors = FALSE)
required <- c(
  "article_interface_id", "inference", "model_variant", "model_label", "family", "tau",
  "fit_size", "effective_fit_size", "comparison_eligible", "status", "signoff_grade",
  "metric_source_mixed", "fit_qtrue_rmse", "forecast_qtrue_mae_H1000",
  "forecast_check_loss_H1000", "fit_source_candidate_id", "fit_source_run_tag",
  "fit_source_signoff_grade", "fit_source_status", "fit_source_path", "fit_source_sha256",
  "forecast_mae_source_candidate_id", "forecast_mae_source_run_tag",
  "forecast_mae_source_signoff_grade", "forecast_mae_source_status",
  "forecast_mae_source_path", "forecast_mae_source_sha256",
  "forecast_check_source_candidate_id", "forecast_check_source_run_tag",
  "forecast_check_source_signoff_grade", "forecast_check_source_status",
  "forecast_check_source_path", "forecast_check_source_sha256",
  "source_registry_hash_value", "preprocessing_scope", "train_start_source_index",
  "train_end_source_index", "forecast_origin_source_index",
  "forecast_block_start_source_index", "forecast_block_end_source_index",
  "forecast_max_lead_configured", "forecast_origin_stride", "package_version",
  "validation_branch", "validation_commit", "validation_closeout_commit",
  "source_promotion_id", "forecast_metric_contract", "rolling_rebaseline_state",
  "article_consumption_allowed", "promotion_validation_branch",
  "promotion_validation_commit", "rolling_evidence_promotion_id",
  "metric_estimator_contract", "confirmation_chain_count",
  "confirmation_execution_commit", "confirmation_closeout_commit",
  "confirmation_state"
)
missing <- setdiff(required, names(source))
if (length(missing)) {
  stop(sprintf("Article interface is missing columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
}

models <- unlist(config$expected_models, use.names = FALSE)
families <- unlist(config$expected_families, use.names = FALSE)
taus <- as.numeric(unlist(config$expected_taus, use.names = FALSE))
inference <- unlist(config$expected_inference, use.names = FALSE)
expected <- expand.grid(
  inference = inference,
  model_variant = models,
  family = families,
  tau = taus,
  stringsAsFactors = FALSE
)
key <- with(source, paste(inference, model_variant, family, sprintf("%.2f", tau)))
expected_key <- with(expected, paste(inference, model_variant, family, sprintf("%.2f", tau)))
metric_cols <- c("fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000")
if (nrow(source) != as.integer(config$expected_rows) || anyDuplicated(key) ||
    !setequal(key, expected_key) || !all(as_bool(source$comparison_eligible)) ||
    !all(source$status == "SUCCESS") ||
    any(!is.finite(as.numeric(unlist(source[metric_cols], use.names = FALSE)))) ||
    any(source$source_registry_hash_value != config$source_registry_hash_value) ||
    any(source$fit_size != as.integer(config$fit_size)) ||
    any(source$train_start_source_index != as.integer(config$train_start_source_index)) ||
    any(source$train_end_source_index != as.integer(config$train_end_source_index)) ||
    any(source$forecast_origin_source_index != as.integer(config$forecast_origin_source_index)) ||
    any(source$forecast_block_start_source_index != as.integer(config$forecast_block_start_source_index)) ||
    any(source$forecast_block_end_source_index != as.integer(config$forecast_block_end_source_index)) ||
    any(source$forecast_max_lead_configured != as.integer(config$max_lead_configured)) ||
    any(source$forecast_origin_stride != as.integer(config$origin_stride)) ||
    any(source$package_version != as.character(config$package_version)) ||
    any(grepl("ridge", source$model_variant)) ||
    any(grepl("/home/jaguir26/local/src", unlist(source, use.names = FALSE), fixed = TRUE))) {
  stop("Article interface violates the fixed independent-validation contract.", call. = FALSE)
}
delta_required <- c(
  "inference", "model_variant", "family", "tau", "metric", "rendered_v6_value",
  "authoritative_v8_value", "relative_gain_pct", "source_promotion_id"
)
if (!all(delta_required %in% names(article_delta)) ||
    nrow(article_delta) != as.integer(config$article_numeric_updates_from_rendered_base) ||
    anyDuplicated(with(article_delta, paste(inference, model_variant, family, tau, metric))) ||
    any(!article_delta$metric %in% metric_cols) ||
    any(!is.finite(article_delta$rendered_v6_value)) ||
    any(!is.finite(article_delta$authoritative_v8_value)) ||
    any(article_delta$authoritative_v8_value >= article_delta$rendered_v6_value) ||
    any(article_delta$relative_gain_pct <= 0)) {
  stop("The article-delta ledger violates the strict-improvement contract.", call. = FALSE)
}
delta_matches <- vapply(seq_len(nrow(article_delta)), function(i) {
  row <- article_delta[i, , drop = FALSE]
  source_row <- source[
    source$inference == row$inference & source$model_variant == row$model_variant &
      source$family == row$family & abs(source$tau - row$tau) < 1e-12,
    ,
    drop = FALSE
  ]
  nrow(source_row) == 1L &&
    abs(as.numeric(source_row[[row$metric]][[1L]]) - row$authoritative_v8_value) < 1e-12 &&
    identical(as.character(source_row$source_promotion_id[[1L]]),
              as.character(row$source_promotion_id[[1L]]))
}, logical(1L))
if (!all(delta_matches)) {
  stop("The article-delta ledger does not match the pinned v8 interface.", call. = FALSE)
}
qdesn_rows <- grepl("^qdesn_", source$model_variant)
if (!all(source$preprocessing_scope[qdesn_rows] == "train_only")) {
  stop("A Q-DESN row does not use train-only preprocessing.", call. = FALSE)
}
if (!all(as_bool(source$article_consumption_allowed)) ||
    any(source$rolling_rebaseline_state != config$rolling_rebaseline_state) ||
    any(source$forecast_metric_contract[qdesn_rows] != config$qdesn_forecast_metric_contract) ||
    any(source$promotion_validation_branch != config$promotion_validation_branch) ||
    any(source$promotion_validation_commit != config$promotion_validation_commit) ||
    any(source$rolling_evidence_promotion_id[qdesn_rows] != config$promotion_id)) {
  stop("The rolling-origin article authority is provisional or stale.", call. = FALSE)
}

expected_state_counts <- as.integer(unlist(config$expected_confirmation_states, use.names = TRUE))
names(expected_state_counts) <- names(unlist(config$expected_confirmation_states, use.names = TRUE))
observed_state_counts <- table(factor(
  source$confirmation_state,
  levels = names(expected_state_counts)
))
names(observed_state_counts) <- names(expected_state_counts)
confirmed <- source$confirmation_state != "INHERITED_FROM_V5"
current_confirmed <- source$confirmation_state == config$current_confirmation_state
if (!identical(as.integer(observed_state_counts), unname(expected_state_counts)) ||
    sum(confirmed) != as.integer(config$confirmed_rows_total) ||
    sum(current_confirmed) != as.integer(config$current_confirmed_rows) ||
    any(source$confirmation_chain_count[confirmed] != as.integer(config$confirmation_chains_per_cell)) ||
    any(source$confirmation_chain_count[!confirmed] != 0L) ||
    any(!nzchar(source$confirmation_execution_commit[confirmed])) ||
    any(!nzchar(source$confirmation_closeout_commit[confirmed])) ||
    any(source$metric_estimator_contract[current_confirmed] != config$current_estimator_contract) ||
    any(source$confirmation_execution_commit[current_confirmed] != config$confirmation_execution_commit) ||
    any(source$confirmation_closeout_commit[current_confirmed] != config$closeout_implementation_commit) ||
    any(source$source_promotion_id[current_confirmed] != config$promotion_id)) {
  stop(
    "The cumulative confirmation estimator contract is incomplete or targets the wrong article cells.",
    call. = FALSE
  )
}

metric_sources <- unique(rbind(
  source[, c("fit_source_path", "fit_source_sha256")],
  setNames(source[, c("forecast_mae_source_path", "forecast_mae_source_sha256")],
           c("fit_source_path", "fit_source_sha256")),
  setNames(source[, c("forecast_check_source_path", "forecast_check_source_sha256")],
           c("fit_source_path", "fit_source_sha256"))
))
names(metric_sources) <- c("path", "sha256")
metric_source_paths <- vapply(seq_len(nrow(metric_sources)), function(i) {
  portable_metric_source(metric_sources$path[[i]], sprintf("Metric source row %d", i))
}, character(1L))
if (!identical(unname(tools::sha256sum(metric_source_paths)), unname(metric_sources$sha256))) {
  stop("Metric-level validation evidence is missing or has changed.", call. = FALSE)
}

family_labels <- c(normal = "Gaussian", laplace = "Laplace", gausmix = "Gaussian mixture")
model_labels <- c(
  dqlm = "DQLM",
  exdqlm = "exDQLM",
  qdesn_al_rhs_ns = "Q--DESN AL--RHS",
  qdesn_exal_rhs_ns = "Q--DESN exAL--RHS"
)
metric_labels <- c(
  fit_qtrue_rmse = "Fit RMSE",
  forecast_qtrue_mae_H1000 = "Forecast MAE",
  forecast_check_loss_H1000 = "Forecast check loss"
)

fmt <- function(value) {
  value <- as.numeric(value)
  if (!is.finite(value)) return("--")
  if (abs(value) >= 100) return(sprintf("%.1f", value))
  if (abs(value) >= 10) return(sprintf("%.2f", value))
  if (abs(value) >= 1) return(sprintf("%.3f", value))
  sprintf("%.4f", value)
}
row_for <- function(inference_value, family, tau, model) {
  rows <- source[
    source$inference == inference_value & source$family == family &
      abs(source$tau - tau) < 1e-12 & source$model_variant == model,
    ,
    drop = FALSE
  ]
  if (nrow(rows) != 1L) stop("A displayed cell is not uniquely identified.", call. = FALSE)
  rows
}
best_value <- function(inference_value, family, tau, metric) {
  values <- vapply(models, function(model) {
    as.numeric(row_for(inference_value, family, tau, model)[[metric]][[1L]])
  }, numeric(1L))
  min(values, na.rm = TRUE)
}
format_cell <- function(value, best) {
  rendered <- fmt(value)
  if (is.finite(value) && abs(value - best) < 1e-10) paste0("\\textbf{", rendered, "}") else rendered
}
row_label <- function(inference_value, family, model) {
  rows <- source[source$inference == inference_value & source$family == family &
                   source$model_variant == model, , drop = FALSE]
  label <- model_labels[[model]]
  if (any(rows$signoff_grade == "FAIL")) {
    paste0(label, "$^{\\ddagger}$")
  } else if (any(rows$signoff_grade == "WARN")) {
    paste0(label, "$^{\\dagger}$")
  } else {
    label
  }
}
header_lines <- c(
  "Model & \\multicolumn{3}{c}{$p=0.05$} & \\multicolumn{3}{c}{$p=0.25$} & \\multicolumn{3}{c}{$p=0.50$} \\\\",
  "\\cmidrule(lr){2-4} \\cmidrule(lr){5-7} \\cmidrule(lr){8-10}",
  paste(" &", paste(rep(unname(metric_labels), length(taus)), collapse = " & "), "\\\\")
)
table_rows <- function(inference_value, family) {
  vapply(models, function(model) {
    cells <- character()
    for (tau in taus) {
      row <- row_for(inference_value, family, tau, model)
      for (metric in names(metric_labels)) {
        value <- as.numeric(row[[metric]][[1L]])
        cells <- c(cells, format_cell(value, best_value(inference_value, family, tau, metric)))
      }
    }
    paste0(row_label(inference_value, family, model), " & ", paste(cells, collapse = " & "), " \\\\")
  }, character(1L))
}

write_family_table <- function(family, path) {
  lines <- c(
    "% Generated from the corrected independent-validation record.",
    "\\begin{table}[!htbp]",
    "\\centering",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{3.4pt}",
    "\\resizebox{\\textwidth}{!}{%",
    "\\begin{tabular}{@{}lrrrrrrrrr@{}}",
    "\\toprule",
    header_lines,
    "\\midrule",
    "\\multicolumn{10}{@{}l}{\\textit{VB}} \\\\",
    table_rows("vb", family),
    "\\addlinespace[2pt]",
    "\\midrule",
    "\\multicolumn{10}{@{}l}{\\textit{MCMC}} \\\\",
    table_rows("mcmc", family),
    "\\bottomrule",
    "\\end{tabular}%",
    "}",
    sprintf(
      paste0(
        "\\caption{Single-quantile fit-and-forecast comparison for the %s simulation family. ",
        "Q--DESN rows use preprocessing estimated only from observations available through the fitting origin. ",
        "Forecast criteria average rolling-origin lead-target pairs over the held-out window of length 1000, ",
        "using leads 1--30 and origin stride 30. Lower values are better; boldface marks the best displayed ",
        "value within each inference panel, target level, and criterion. A dagger or double dagger records a ",
        "contributing WARN or FAIL diagnostic, respectively.}"
      ),
      family_labels[[family]]
    ),
    sprintf("\\label{tab:simulation-500obs-final-%s}", family),
    "\\end{table}"
  )
  writeLines(lines, path, useBytes = TRUE)
}

write_mcmc_table <- function(family, path) {
  lines <- c(
    "% Generated from the corrected independent-validation record.",
    "\\begin{table}[!htbp]",
    "\\centering",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{3.4pt}",
    "\\resizebox{\\textwidth}{!}{%",
    "\\begin{tabular}{@{}lrrrrrrrrr@{}}",
    "\\toprule",
    header_lines,
    "\\midrule",
    table_rows("mcmc", family),
    "\\bottomrule",
    "\\end{tabular}%",
    "}",
    sprintf(
      paste0(
        "\\caption{MCMC single-quantile fit-and-forecast comparison for the %s simulation family. ",
        "The Q--DESN entries form a fixed case-specific metric-wise summary and can therefore draw different ",
        "criteria from different calibrated fits. A confirmed criterion may instead use its pre-specified ",
        "repeated-chain aggregate, as identified in the metric-level record. Q--DESN preprocessing is ",
        "estimated only from the training ",
        "window. Forecast criteria average rolling-origin lead-target pairs over a held-out window of length ",
        "1000 using leads 1--30 and origin stride 30. Lower values are better, and boldface marks the best ",
        "displayed value within each target level and criterion. A dagger or double dagger records a ",
        "contributing WARN or FAIL diagnostic, respectively.}"
      ),
      family_labels[[family]]
    ),
    sprintf("\\label{tab:simulation-500obs-mcmc-%s}", family),
    "\\end{table}"
  )
  writeLines(lines, path, useBytes = TRUE)
}

outputs <- config$outputs
summary_path <- resolve_article(outputs$summary_csv)
compat_summary_path <- resolve_article(outputs$compatibility_summary_csv)
write.csv(source, summary_path, row.names = FALSE, na = "")
write.csv(source, compat_summary_path, row.names = FALSE, na = "")

family_paths <- c(
  normal = resolve_article(outputs$normal_tex),
  laplace = resolve_article(outputs$laplace_tex),
  gausmix = resolve_article(outputs$gausmix_tex)
)
mcmc_paths <- c(
  normal = resolve_article(outputs$mcmc_normal_tex),
  laplace = resolve_article(outputs$mcmc_laplace_tex),
  gausmix = resolve_article(outputs$mcmc_gausmix_tex)
)
for (family in names(family_paths)) {
  write_family_table(family, family_paths[[family]])
  write_mcmc_table(family, mcmc_paths[[family]])
}

protocol_path <- resolve_article(outputs$protocol_tex)
writeLines(c(
  "% Generated from the corrected independent-validation record.",
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\small",
  "\\begin{tabular}{@{}ll@{}}",
  "\\toprule",
  "Component & Fixed protocol \\\\",
  "\\midrule",
  "Training observations & 500 (source indices 8501--9000) \\\\",
  "Forecast origin & Source index 9000 \\\\",
  "Held-out forecast window & 1000 observations (source indices 9001--10000) \\\\",
  "Rolling-origin design & Leads 1--30; origin stride 30; no refitting \\\\",
  "Target quantile levels & $p=0.05,0.25,0.50$ \\\\",
  "Displayed criteria & Fit RMSE; forecast MAE; forecast check loss \\\\",
  "\\bottomrule",
  "\\end{tabular}",
  "\\caption{Common protocol for the independent single-quantile simulation comparison.}",
  "\\label{tab:simulation-500obs-protocol}",
  "\\end{table}"
), protocol_path, useBytes = TRUE)

family_wrapper <- resolve_article(outputs$family_wrapper_tex)
writeLines(c(
  "% Corrected independent-validation companion tables.",
  "\\input{tables/qdesn_validation_tt500_final_protocol.tex}",
  "\\input{tables/qdesn_validation_tt500_final_normal.tex}",
  "\\input{tables/qdesn_validation_tt500_final_laplace.tex}",
  "\\input{tables/qdesn_validation_tt500_final_gausmix.tex}"
), family_wrapper, useBytes = TRUE)
mcmc_wrapper <- resolve_article(outputs$mcmc_wrapper_tex)
writeLines(c(
  "% Corrected independent-validation MCMC tables.",
  "\\input{tables/qdesn_validation_tt500_final_mcmc_normal.tex}",
  "\\input{tables/qdesn_validation_tt500_final_mcmc_laplace.tex}",
  "\\input{tables/qdesn_validation_tt500_final_mcmc_gausmix.tex}"
), mcmc_wrapper, useBytes = TRUE)

combined_path <- resolve_article(outputs$combined_tex)
combined <- c(
  "% Generated from the corrected independent-validation record.",
  "\\begingroup",
  "\\scriptsize",
  "\\setlength{\\tabcolsep}{2.0pt}",
  "\\begin{longtable}{@{}lrrrrrrrrr@{}}",
  paste0(
    "\\caption{Consolidated independent single-quantile fit-and-forecast comparison using 500 training observations. ",
    "Lower values are better, and boldface marks the best value within each family, inference method, target level, and criterion.}",
    "\\label{tab:simulation-fitforecast-results}\\\\"
  ),
  "\\toprule",
  header_lines,
  "\\midrule",
  "\\endfirsthead",
  "\\caption[]{Consolidated independent single-quantile fit-and-forecast comparison (continued).}\\\\",
  "\\toprule",
  header_lines,
  "\\midrule",
  "\\endhead",
  "\\bottomrule",
  "\\endlastfoot"
)
for (family in families) {
  combined <- c(
    combined,
    sprintf("\\multicolumn{10}{@{}l}{\\textbf{%s innovations}} \\\\", family_labels[[family]])
  )
  for (inf in inference) {
    combined <- c(
      combined,
      sprintf("\\multicolumn{10}{@{}l}{\\textit{%s}} \\\\", toupper(inf)),
      table_rows(inf, family),
      "\\addlinespace[2pt]"
    )
  }
}
combined <- c(combined, "\\end{longtable}", "\\endgroup")
writeLines(combined, combined_path, useBytes = TRUE)

metric_specs <- list(
  fit_qtrue_rmse = list(
    label = "Fit RMSE", candidate = "fit_source_candidate_id", run_tag = "fit_source_run_tag",
    signoff = "fit_source_signoff_grade", path = "fit_source_path", sha = "fit_source_sha256"
  ),
  forecast_qtrue_mae_H1000 = list(
    label = "Forecast MAE", candidate = "forecast_mae_source_candidate_id",
    run_tag = "forecast_mae_source_run_tag", signoff = "forecast_mae_source_signoff_grade",
    path = "forecast_mae_source_path", sha = "forecast_mae_source_sha256"
  ),
  forecast_check_loss_H1000 = list(
    label = "Forecast check loss", candidate = "forecast_check_source_candidate_id",
    run_tag = "forecast_check_source_run_tag", signoff = "forecast_check_source_signoff_grade",
    path = "forecast_check_source_path", sha = "forecast_check_source_sha256"
  )
)
relative_to_validation <- function(path) {
  marker <- "validation/fitforecast_v2/"
  at <- regexpr(marker, path, fixed = TRUE)
  if (at[[1L]] < 1L) {
    stop("A figure metric source has no portable validation path.", call. = FALSE)
  }
  relative <- substring(path, at[[1L]])
  resolve_portable_validation_path(relative, "Figure metric source")
  relative
}
mcmc <- source[source$inference == "mcmc", , drop = FALSE]
figure_rows <- list()
for (i in seq_len(nrow(mcmc))) {
  for (metric in names(metric_specs)) {
    spec <- metric_specs[[metric]]
    block <- mcmc[mcmc$family == mcmc$family[[i]] & abs(mcmc$tau - mcmc$tau[[i]]) < 1e-12, , drop = FALSE]
    best <- min(as.numeric(block[[metric]]))
    value <- as.numeric(mcmc[[metric]][[i]])
    figure_rows[[length(figure_rows) + 1L]] <- data.frame(
      model_variant = mcmc$model_variant[[i]],
      model_label = gsub("--", "-", model_labels[[mcmc$model_variant[[i]]]], fixed = TRUE),
      family = mcmc$family[[i]],
      family_label = family_labels[[mcmc$family[[i]]]],
      tau = as.numeric(mcmc$tau[[i]]),
      metric = metric,
      metric_label = spec$label,
      value = value,
      best_value = best,
      ratio_to_best = value / best,
      is_winner = abs(value - best) < 1e-10,
      source_signoff_grade = as.character(mcmc[[spec$signoff]][[i]]),
      source_candidate_id = as.character(mcmc[[spec$candidate]][[i]]),
      source_run_tag = as.character(mcmc[[spec$run_tag]][[i]]),
      source_path_relative = relative_to_validation(as.character(mcmc[[spec$path]][[i]])),
      source_sha256 = as.character(mcmc[[spec$sha]][[i]]),
      source_promotion_id = as.character(mcmc$source_promotion_id[[i]]),
      source_registry_hash_value = as.character(mcmc$source_registry_hash_value[[i]]),
      stringsAsFactors = FALSE
    )
  }
}
figure_data <- do.call(rbind, figure_rows)
figure_data_path <- resolve_article(outputs$figure_data)
write.csv(figure_data, figure_data_path, row.names = FALSE, na = "")

if (!requireNamespace("ggplot2", quietly = TRUE) || !requireNamespace("scales", quietly = TRUE)) {
  stop("ggplot2 and scales are required to build the validation figure.", call. = FALSE)
}
figure_data$model_label <- factor(
  figure_data$model_label,
  levels = rev(gsub("--", "-", unname(model_labels), fixed = TRUE))
)
figure_data$family_label <- factor(figure_data$family_label, levels = unname(family_labels[families]))
figure_data$metric_label <- factor(
  figure_data$metric_label,
  levels = c("Fit RMSE", "Forecast MAE", "Forecast check loss")
)
figure_data$tau_label <- factor(sprintf("p = %.2f", figure_data$tau), levels = sprintf("p = %.2f", taus))
marker <- ifelse(
  figure_data$source_signoff_grade == "FAIL", " x",
  ifelse(figure_data$source_signoff_grade == "WARN", " +", "")
)
figure_data$cell_label <- paste0(vapply(figure_data$value, fmt, character(1L)), marker)
fill_max <- max(figure_data$ratio_to_best, na.rm = TRUE)
legend_breaks <- c(1, 2, 4, 8, 16)
legend_breaks <- legend_breaks[legend_breaks <= fill_max]
plot <- ggplot2::ggplot(
  figure_data,
  ggplot2::aes(x = tau_label, y = model_label, fill = ratio_to_best)
) +
  ggplot2::geom_tile(ggplot2::aes(colour = is_winner), linewidth = 0.55) +
  ggplot2::geom_text(ggplot2::aes(label = cell_label), size = 2.55) +
  ggplot2::facet_grid(metric_label ~ family_label, scales = "free") +
  ggplot2::scale_colour_manual(values = c(`TRUE` = "black", `FALSE` = "white"), guide = "none") +
  ggplot2::scale_fill_gradientn(
    colours = c("#f7fbff", "#fee8c8", "#fdbb84", "#e34a33"),
    trans = "log10",
    limits = c(1, fill_max),
    oob = scales::squish,
    breaks = legend_breaks,
    labels = paste0(legend_breaks, "x"),
    name = "Relative to best"
  ) +
  ggplot2::labs(x = NULL, y = NULL) +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(
    panel.grid = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "#eeeeee", colour = "#777777"),
    axis.text.x = ggplot2::element_text(angle = 0),
    legend.position = "bottom",
    plot.margin = ggplot2::margin(6, 6, 6, 6)
  )
figure_path <- resolve_article(outputs$figure_pdf)
ggplot2::ggsave(figure_path, plot = plot, width = 11.2, height = 8.0, units = "in", device = grDevices::cairo_pdf)
normalize_pdf_creation_date <- function(path) {
  bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  marker <- charToRaw("/CreationDate (D:")
  candidates <- which(bytes == marker[[1L]])
  hits <- candidates[vapply(candidates, function(at) {
    end <- at + length(marker) - 1L
    end <= length(bytes) && identical(bytes[at:end], marker)
  }, logical(1L))]
  if (length(hits) != 1L) {
    stop("The generated PDF does not contain one creation-date field.", call. = FALSE)
  }
  closing <- which(seq_along(bytes) > hits[[1L]] & bytes == charToRaw(")")[[1L]])
  if (!length(closing)) {
    stop("The generated PDF creation-date field is unterminated.", call. = FALSE)
  }
  close_at <- closing[[1L]]
  old <- rawToChar(bytes[hits[[1L]]:close_at])
  replacement <- "/CreationDate (D:20000101000000+00'00)"
  if (nchar(old, type = "bytes") != nchar(replacement, type = "bytes")) {
    stop("The generated PDF creation-date field has an unexpected width.", call. = FALSE)
  }
  bytes[hits[[1L]]:close_at] <- charToRaw(replacement)
  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  writeBin(bytes, connection)
  invisible(path)
}
normalize_pdf_creation_date(figure_path)

artifact_paths <- c(
  summary_path, compat_summary_path, protocol_path, family_paths, family_wrapper,
  combined_path, mcmc_paths, mcmc_wrapper, figure_data_path, figure_path
)
artifact_hashes <- tools::sha256sum(artifact_paths)
relative_article <- function(path) substring(normalizePath(path, winslash = "/"), nchar(repo_root) + 2L)
manifest_lines <- c(
  "Independent single-quantile corrected article record",
  sprintf("promotion_id: %s", config$promotion_id),
  sprintf("promotion_status: %s", config$promotion_status),
  sprintf("scientific_decision: %s", config$scientific_decision),
  sprintf("source_interface: %s", config$interface_relative_path),
  sprintf("source_interface_sha256: %s", sha256(interface_path)),
  sprintf("source_manifest: %s", config$manifest_relative_path),
  sprintf("source_manifest_sha256: %s", sha256(source_manifest_path)),
  sprintf("source_ledger: %s", config$source_ledger_relative_path),
  sprintf("source_ledger_sha256: %s", sha256(source_ledger_path)),
  sprintf("article_delta: %s", config$article_delta_relative_path),
  sprintf("article_delta_sha256: %s", sha256(article_delta_path)),
  sprintf("article_numeric_updates: %d", nrow(article_delta)),
  sprintf("source_registry_hash: %s", config$source_registry_hash_value),
  sprintf("row_count: %d", nrow(source)),
  sprintf("signoff_counts: %s", paste(names(table(source$signoff_grade)), table(source$signoff_grade), collapse = ",")),
  sprintf("ridge_policy: %s", config$ridge_policy),
  "qdesn_preprocessing_scope: train_only",
  "forecast_protocol: rolling_origin_no_refit_state_update",
  sprintf("rolling_rebaseline_state: %s", config$rolling_rebaseline_state),
  sprintf("qdesn_forecast_metric_contract: %s", config$qdesn_forecast_metric_contract),
  sprintf("promotion_validation_branch: %s", config$promotion_validation_branch),
  sprintf("promotion_validation_commit: %s", config$promotion_validation_commit),
  sprintf("exal_method_id: %s", config$exal_method_id),
  sprintf("al_method_id: %s", config$al_method_id),
  sprintf("campaign_run_id: %s", config$campaign_run_id),
  sprintf("campaign_run_tag: %s", config$campaign_run_tag),
  sprintf("scientific_design_commit: %s", config$scientific_design_commit),
  sprintf("confirmation_execution_commit: %s", config$confirmation_execution_commit),
  sprintf("closeout_implementation_commit: %s", config$closeout_implementation_commit),
  sprintf("canonical_chains: %d", as.integer(config$canonical_chains)),
  sprintf("promoted_metric_roles_current_campaign: %d", as.integer(config$promoted_metric_roles)),
  "artifacts:"
)
manifest_lines <- c(
  manifest_lines,
  sprintf("  %s: %s", vapply(artifact_paths, relative_article, character(1L)), unname(artifact_hashes))
)
table_manifest_path <- resolve_article(outputs$table_manifest)
writeLines(manifest_lines, table_manifest_path, useBytes = TRUE)

mcmc_manifest_path <- resolve_article(outputs$mcmc_manifest)
writeLines(c(
  "Independent single-quantile corrected MCMC article tables",
  sprintf("promotion_id: %s", config$promotion_id),
  sprintf("source_csv: %s", config$interface_relative_path),
  sprintf("source_csv_sha256: %s", sha256(interface_path)),
  sprintf("source_manifest_sha256: %s", sha256(source_manifest_path)),
  sprintf("article_delta_sha256: %s", sha256(article_delta_path)),
  sprintf("source_registry_hash: %s", config$source_registry_hash_value),
  "selection_policy: fixed case-specific metric-wise summary; diagnostic status retained but not excluded",
  "qdesn_preprocessing_scope: train_only",
  sprintf("rolling_rebaseline_state: %s", config$rolling_rebaseline_state),
  sprintf("qdesn_forecast_metric_contract: %s", config$qdesn_forecast_metric_contract),
  sprintf("current_confirmation_state: %s", config$current_confirmation_state),
  sprintf("current_estimator_contract: %s", config$current_estimator_contract),
  sprintf("confirmation_chains_per_cell: %d", as.integer(config$confirmation_chains_per_cell)),
  sprintf("confirmed_rows_total: %d", as.integer(config$confirmed_rows_total)),
  sprintf("promoted_metric_roles_current_campaign: %d", as.integer(config$promoted_metric_roles)),
  sprintf("article_numeric_updates_from_rendered_base: %d",
          as.integer(config$article_numeric_updates_from_rendered_base)),
  sprintf("row_count_mcmc: %d", nrow(mcmc)),
  sprintf("signoff_counts_mcmc: %s", paste(names(table(mcmc$signoff_grade)), table(mcmc$signoff_grade), collapse = ",")),
  "artifact_sha256:",
  sprintf("  %s: %s", vapply(c(mcmc_paths, mcmc_wrapper), relative_article, character(1L)),
          unname(tools::sha256sum(c(mcmc_paths, mcmc_wrapper))))
), mcmc_manifest_path, useBytes = TRUE)

figure_manifest_path <- resolve_article(outputs$figure_manifest)
writeLines(c(
  "Independent single-quantile corrected MCMC performance figure",
  sprintf("promotion_id: %s", config$promotion_id),
  "source_path_base: validation_root",
  sprintf("source_csv: %s", config$interface_relative_path),
  sprintf("source_csv_sha256: %s", sha256(interface_path)),
  sprintf("figure_data: %s", relative_article(figure_data_path)),
  sprintf("figure_data_sha256: %s", sha256(figure_data_path)),
  sprintf("figure_data_csv: %s", relative_article(figure_data_path)),
  sprintf("figure_data_csv_sha256: %s", sha256(figure_data_path)),
  sprintf("figure_pdf: %s", relative_article(figure_path)),
  sprintf("figure_pdf_sha256: %s", sha256(figure_path)),
  sprintf("source_registry_hash: %s", config$source_registry_hash_value),
  sprintf("row_count: %d", nrow(figure_data)),
  "warn_marker: +",
  "fail_marker: x"
), figure_manifest_path, useBytes = TRUE)

cat(sprintf("ARTICLE_INTERFACE=%s\n", interface_path))
cat(sprintf("ROWS=%d\n", nrow(source)))
cat(sprintf("TABLES=%d\n", length(c(family_paths, mcmc_paths)) + 3L))
cat(sprintf("FIGURE=%s\n", figure_path))
cat(sprintf("RIDGE_ROWS=%d\n", sum(grepl("ridge", source$model_variant))))
