#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

`%||%` <- function(lhs, rhs) {
  if (is.null(lhs) || !length(lhs) || all(is.na(lhs))) rhs else lhs
}

script_path <- {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg)) {
    normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = TRUE)
  } else {
    normalizePath("scripts/build_qdesn_mcmc_current_best_validation_tables.R", winslash = "/", mustWork = TRUE)
  }
}
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  idx <- which(args == flag)
  if (!length(idx) || idx[[1L]] >= length(args)) return(default)
  args[[idx[[1L]] + 1L]]
}

validation_root <- normalizePath(
  get_arg(
    "--validation-root",
    "/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0"
  ),
  winslash = "/",
  mustWork = TRUE
)
promotion_id <- "qdesn_dqlm_500obs_mcmc_metric_envelope_20260727"
source_dir <- get_arg(
  "--source-dir",
  file.path(
    validation_root,
    "validation", "fitforecast_v2", "promotions", promotion_id
  )
)
source_csv <- get_arg(
  "--source-csv",
  file.path(source_dir, paste0(promotion_id, "_article_envelope.csv"))
)
source_manifest <- get_arg(
  "--source-manifest",
  file.path(source_dir, paste0(promotion_id, "_manifest.json"))
)
source_confirmation <- get_arg(
  "--source-confirmation",
  file.path(source_dir, paste0(promotion_id, "_coherent_confirmation.csv"))
)
authority_freeze_id <- paste0(
  "qdesn_500obs_mcmc_nested_final_origin9000_v1_",
  "evidence_freeze_20260730"
)
authority_freeze_dir <- get_arg(
  "--authority-freeze-dir",
  file.path(
    validation_root,
    "validation", "fitforecast_v2", "promotions", authority_freeze_id
  )
)
authority_freeze_manifest_path <- get_arg(
  "--authority-freeze-manifest",
  file.path(authority_freeze_dir, "evidence_freeze_manifest.json")
)
authority_ledger_path <- get_arg(
  "--authority-ledger",
  file.path(authority_freeze_dir, "frozen_evidence_ledger.csv")
)

out_dir <- file.path(repo_root, "tables")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

stop_if_missing <- function(path, label) {
  if (!file.exists(path)) stop(sprintf("Missing %s: %s", label, path), call. = FALSE)
}
stop_if_missing(source_csv, "current-best clean evidence table")
stop_if_missing(source_manifest, "current-best manifest")
stop_if_missing(source_confirmation, "coherent-confirmation ledger")
stop_if_missing(authority_freeze_manifest_path, "article-authority freeze manifest")
stop_if_missing(authority_ledger_path, "article-authority evidence ledger")

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
as_bool <- function(value) {
  if (is.logical(value)) return(value)
  toupper(trimws(as.character(value))) %in% c("TRUE", "T", "1", "YES")
}
verify_manifest_files <- function(entries, label) {
  if (!is.data.frame(entries) ||
      !all(c("path", "sha256") %in% names(entries)) ||
      !nrow(entries)) {
    stop(sprintf("%s has no verifiable path/hash entries.", label), call. = FALSE)
  }
  if (any(!file.exists(entries$path))) {
    stop(sprintf("%s references a missing file.", label), call. = FALSE)
  }
  observed <- unname(tools::sha256sum(entries$path))
  if (any(observed != entries$sha256)) {
    stop(sprintf("%s contains a source hash mismatch.", label), call. = FALSE)
  }
  invisible(TRUE)
}
normalize_within_validation <- function(path_relative, label) {
  candidate <- normalizePath(
    file.path(validation_root, path_relative),
    winslash = "/",
    mustWork = TRUE
  )
  prefix <- paste0(validation_root, "/")
  if (!startsWith(candidate, prefix)) {
    stop(sprintf("%s escapes the validation root.", label), call. = FALSE)
  }
  candidate
}
verify_authority_entry <- function(entry, label) {
  if (is.null(entry$path_relative) || is.null(entry$sha256)) {
    stop(sprintf("%s is missing path/hash metadata.", label), call. = FALSE)
  }
  path <- normalize_within_validation(entry$path_relative, label)
  if (!identical(sha256(path), entry$sha256)) {
    stop(sprintf("%s has a SHA-256 mismatch.", label), call. = FALSE)
  }
  path
}
git_last_commit_for <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(validation_root, "/")
  if (!startsWith(path, prefix)) {
    stop("Cannot resolve authority commit outside validation root.", call. = FALSE)
  }
  relative <- substring(path, nchar(prefix) + 1L)
  out <- system2(
    "git",
    c("-C", validation_root, "log", "-1", "--format=%H", "--", relative),
    stdout = TRUE,
    stderr = TRUE
  )
  if (!length(out) || !grepl("^[0-9a-f]{40}$", out[[1L]])) {
    stop("Could not resolve the validation authority commit.", call. = FALSE)
  }
  out[[1L]]
}

authority_freeze <- jsonlite::read_json(
  authority_freeze_manifest_path,
  simplifyVector = TRUE
)
expected_latest_decision <- "NO_CONFIRMED_COHERENT_ARTICLE_REFRESH"
expected_valid_run_tag <- paste0(
  "qdesn-500obs-mcmc-nested-final-o9000-v1-full-",
  "20260730__git-bd4da62"
)
expected_rejected_run_tag <- paste0(
  "qdesn-500obs-mcmc-nested-final-o9000-v1-full-",
  "20260730__git-6582f87"
)
if (!identical(authority_freeze$freeze_id, authority_freeze_id) ||
    !identical(authority_freeze$scope,
      "independent_qdesn_exqdesn_mcmc_validation_only") ||
    !identical(authority_freeze$git_branch,
      "validation/shared-fitforecast-v2-1.0.0") ||
    !identical(authority_freeze$package_version, "1.0.0") ||
    !identical(authority_freeze$authority_contract_version, "1.0.0") ||
    !identical(authority_freeze$authoritative_numeric_promotion_id,
      promotion_id) ||
    as.integer(authority_freeze$authoritative_numeric_row_count) != 36L ||
    as.integer(authority_freeze$authoritative_candidate_row_count) != 129L ||
    as.integer(authority_freeze$authoritative_displayed_metric_count) != 108L ||
    !identical(authority_freeze$scientific_decision,
      expected_latest_decision) ||
    as.integer(authority_freeze$coherent_promotion_cells) != 0L ||
    as.integer(authority_freeze$article_refresh_metric_rows) != 0L ||
    isTRUE(authority_freeze$origin_9000_untouched_confirmation_eligible) ||
    !identical(authority_freeze$article_update_policy,
      "KEEP_CURRENT_ARTICLE_PARENT_ROWS_UNCHANGED") ||
    !identical(authority_freeze$article_numeric_state,
      "UNCHANGED_FROM_20260727_AUTHORITY") ||
    !identical(
      unname(authority_freeze$consumable_scientific_run_tags),
      expected_valid_run_tag
    ) ||
    !identical(
      unname(authority_freeze$permanently_rejected_run_tags),
      expected_rejected_run_tag
    ) ||
    !identical(
      as.integer(unname(authority_freeze$exposed_confirmation_origins)),
      9000L
    )) {
  stop("Article-authority freeze does not satisfy the no-change contract.", call. = FALSE)
}

authority_source_csv <- verify_authority_entry(
  authority_freeze$authoritative_numeric_article_envelope,
  "Authoritative numerical envelope"
)
authority_source_manifest <- verify_authority_entry(
  authority_freeze$authoritative_numeric_manifest,
  "Authoritative numerical manifest"
)
authority_source_confirmation <- verify_authority_entry(
  authority_freeze$authoritative_coherent_confirmation,
  "Authoritative coherent confirmation"
)
expected_authority_paths <- c(
  authority_source_csv,
  authority_source_manifest,
  authority_source_confirmation
)
requested_authority_paths <- normalizePath(
  c(source_csv, source_manifest, source_confirmation),
  winslash = "/",
  mustWork = TRUE
)
if (!identical(requested_authority_paths, expected_authority_paths)) {
  stop("Requested article inputs differ from the authority freeze.", call. = FALSE)
}

authority_ledger <- read.csv(
  authority_ledger_path,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
if (!all(c("role", "path_relative", "sha256", "consume_policy") %in%
         names(authority_ledger)) ||
    anyDuplicated(authority_ledger$role)) {
  stop("Article-authority evidence ledger has an invalid schema.", call. = FALSE)
}
authority_ledger_files <- data.frame(
  path = vapply(
    seq_len(nrow(authority_ledger)),
    function(index) normalize_within_validation(
      authority_ledger$path_relative[[index]],
      paste0("Authority ledger row ", index)
    ),
    character(1L)
  ),
  sha256 = authority_ledger$sha256,
  stringsAsFactors = FALSE
)
verify_manifest_files(authority_ledger_files, "Article-authority evidence ledger")
expected_authority_roles <- c(
  "article_numeric_envelope",
  "article_numeric_manifest",
  "article_coherent_confirmation"
)
if (!setequal(
  authority_ledger$role[grepl("^article_", authority_ledger$role)],
  expected_authority_roles
)) {
  stop("Article-authority ledger is missing required article roles.", call. = FALSE)
}
bundle_paths <- c(
  file.path(authority_freeze_dir, "README.md"),
  file.path(authority_freeze_dir, "run_disposition.csv"),
  file.path(authority_freeze_dir, "origin_disposition.csv"),
  authority_ledger_path
)
bundle_hashes <- c(
  authority_freeze$bundle_hashes$readme_sha256,
  authority_freeze$bundle_hashes$run_disposition_sha256,
  authority_freeze$bundle_hashes$origin_disposition_sha256,
  authority_freeze$bundle_hashes$frozen_evidence_ledger_sha256
)
if (!all(file.exists(bundle_paths)) ||
    !identical(unname(tools::sha256sum(bundle_paths)), unname(bundle_hashes))) {
  stop("Article-authority bundle hash verification failed.", call. = FALSE)
}
validation_authority_commit <- git_last_commit_for(
  authority_freeze_manifest_path
)

promotion_manifest <- jsonlite::read_json(source_manifest, simplifyVector = TRUE)
expected_decision <- "ELIGIBLE_FOR_SCIENTIFIC_PROMOTION_PENDING_ARTICLE_REVIEW"
if (!identical(promotion_manifest$promotion_id, promotion_id) ||
    !identical(promotion_manifest$validation_branch,
      "validation/shared-fitforecast-v2-1.0.0") ||
    !identical(promotion_manifest$package_version, "1.0.0") ||
    !identical(promotion_manifest$confirmation_decision, expected_decision) ||
    !identical(promotion_manifest$confirmation_signoff_grade, "WARN") ||
    as.integer(promotion_manifest$coherent_confirmation_rows) != 1L ||
    as.integer(promotion_manifest$n_candidates) != 129L ||
    as.integer(promotion_manifest$n_envelope_rows) != 36L ||
    as.integer(promotion_manifest$n_metric_promotions) != 0L ||
    as_bool(promotion_manifest$displayed_envelope_changed) ||
    as_bool(promotion_manifest$tracked_source_dirty_before_materialization) ||
    length(promotion_manifest$untracked_before_materialization) != 0L ||
    !identical(
      promotion_manifest$source_registry_hash_value,
      authority_freeze$source_registry_hash_value
    )) {
  stop("Current-best promotion manifest does not satisfy the frozen article gate.", call. = FALSE)
}
verify_manifest_files(promotion_manifest$source_manifest, "Promotion source manifest")
verify_manifest_files(promotion_manifest$files, "Promotion output manifest")
if (any(grepl(
  "/home/jaguir26/local/src",
  c(promotion_manifest$source_manifest$path, promotion_manifest$files$path),
  fixed = TRUE
))) {
  stop("Promotion manifest contains a stale /home/jaguir26/local/src path.", call. = FALSE)
}

clean <- read.csv(source_csv, check.names = FALSE, stringsAsFactors = FALSE)
required <- c(
  "model_variant", "family", "tau", "fit_size", "comparison_eligible", "status",
  "signoff_grade", "fit_qtrue_rmse", "forecast_qtrue_mae_H1000",
  "forecast_check_loss_H1000", "source_key", "source_promotion_id",
  "source_table_sha256", "source_registry_hash_value", "metric_source_mixed",
  "fit_source_candidate_id", "fit_source_run_tag", "fit_source_signoff_grade",
  "forecast_mae_source_candidate_id", "forecast_mae_source_run_tag",
  "forecast_mae_source_signoff_grade", "forecast_check_source_candidate_id",
  "forecast_check_source_run_tag", "forecast_check_source_signoff_grade"
)
missing <- setdiff(required, names(clean))
if (length(missing)) {
  stop(sprintf("Current-best clean table is missing required columns: %s", paste(missing, collapse = ", ")), call. = FALSE)
}

if (!all(clean$comparison_eligible == "STATUS_AGNOSTIC")) {
  stop("Metric-envelope rows must declare comparison_eligible=STATUS_AGNOSTIC.", call. = FALSE)
}
if (!all(clean$status %in% c("SUCCESS", "done"))) {
  stop("Metric-envelope rows must derive from completed runs.", call. = FALSE)
}
if (length(unique(clean$source_registry_hash_value)) != 1L) {
  stop("Current-best rows do not share one source registry hash.", call. = FALSE)
}
if (nrow(clean) != 36L ||
    any(as.integer(clean$fit_size) != 500L) ||
    anyDuplicated(paste(clean$model_variant, clean$family, clean$tau)) ||
    !all(clean$source_promotion_id == promotion_id) ||
    !identical(
      unique(clean$source_registry_hash_value),
      promotion_manifest$source_registry_hash_value
    )) {
  stop("Current-best table does not match the complete frozen promotion.", call. = FALSE)
}

manifest_source_row <- promotion_manifest$files[
  normalizePath(promotion_manifest$files$path, winslash = "/", mustWork = TRUE) ==
    normalizePath(source_csv, winslash = "/", mustWork = TRUE),
  ,
  drop = FALSE
]
if (nrow(manifest_source_row) != 1L ||
    !identical(manifest_source_row$sha256[[1L]], sha256(source_csv))) {
  stop("Article envelope hash does not match the promotion manifest.", call. = FALSE)
}

confirmation <- read.csv(
  source_confirmation,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
required_confirmation <- c(
  "candidate_id", "model_variant", "family", "tau", "fit_size", "spec_id",
  "run_tag", "fit_qtrue_rmse", "forecast_qtrue_mae_H1000",
  "forecast_check_loss_H1000", "envelope_fit_qtrue_rmse",
  "envelope_forecast_qtrue_mae_H1000",
  "envelope_forecast_check_loss_H1000", "fit_envelope_winner",
  "forecast_mae_envelope_winner", "forecast_check_envelope_winner",
  "all_external_metrics_within_1p05", "all_metrics_stable_within_1p10",
  "signoff_grade", "signoff_reason", "decision",
  "source_registry_hash_value"
)
missing_confirmation <- setdiff(required_confirmation, names(confirmation))
if (nrow(confirmation) != 1L || length(missing_confirmation) ||
    confirmation$candidate_id[[1L]] != "mgv3_16_exal_local__full_5787212" ||
    confirmation$model_variant[[1L]] != "qdesn_exal_rhs_ns" ||
    confirmation$family[[1L]] != "laplace" ||
    abs(as.numeric(confirmation$tau[[1L]]) - 0.25) > 1e-12 ||
    as.integer(confirmation$fit_size[[1L]]) != 500L ||
    confirmation$run_tag[[1L]] != promotion_manifest$confirmation_run_tag ||
    confirmation$spec_id[[1L]] != promotion_manifest$confirmation_spec_id ||
    confirmation$decision[[1L]] != expected_decision ||
    confirmation$signoff_grade[[1L]] != "WARN" ||
    confirmation$signoff_reason[[1L]] != "chain_marginal_but_usable" ||
    !as_bool(confirmation$all_external_metrics_within_1p05[[1L]]) ||
    !as_bool(confirmation$all_metrics_stable_within_1p10[[1L]]) ||
    any(vapply(
      confirmation[c(
        "fit_envelope_winner",
        "forecast_mae_envelope_winner",
        "forecast_check_envelope_winner"
      )],
      function(value) as_bool(value[[1L]]),
      logical(1L)
    )) ||
    confirmation$source_registry_hash_value[[1L]] !=
      promotion_manifest$source_registry_hash_value) {
  stop("Coherent-confirmation ledger does not satisfy the article contract.", call. = FALSE)
}

target_envelope <- clean[
  clean$model_variant == "qdesn_exal_rhs_ns" &
    clean$family == "laplace" &
    abs(as.numeric(clean$tau) - 0.25) <= 1e-12,
  ,
  drop = FALSE
]
if (nrow(target_envelope) != 1L ||
    any(abs(c(
      target_envelope$fit_qtrue_rmse -
        confirmation$envelope_fit_qtrue_rmse,
      target_envelope$forecast_qtrue_mae_H1000 -
        confirmation$envelope_forecast_qtrue_mae_H1000,
      target_envelope$forecast_check_loss_H1000 -
        confirmation$envelope_forecast_check_loss_H1000
    )) > 1e-12)) {
  stop("Coherent-confirmation envelope context does not match the article table.", call. = FALSE)
}

families <- c(normal = "Gaussian", laplace = "Laplace", gausmix = "Gaussian-mixture")
family_order <- names(families)
taus <- c(0.05, 0.25, 0.50)
models <- c(
  dqlm_c13_mcmc = "DQLM",
  exdqlm_c13_mcmc = "exDQLM",
  qdesn_al_rhs_ns = "Q-DESN AL--RHS",
  qdesn_exal_rhs_ns = "Q-DESN exAL--RHS"
)
expected_cells <- expand.grid(
  model_variant = names(models),
  family = family_order,
  tau = taus,
  stringsAsFactors = FALSE
)
observed_cells <- paste(
  clean$model_variant,
  clean$family,
  sprintf("%.2f", as.numeric(clean$tau))
)
expected_cell_keys <- paste(
  expected_cells$model_variant,
  expected_cells$family,
  sprintf("%.2f", expected_cells$tau)
)
if (!setequal(observed_cells, expected_cell_keys)) {
  stop("Current-best table is not the exact complete 4 x 3 x 3 article grid.", call. = FALSE)
}

num <- function(x) suppressWarnings(as.numeric(x))
fmt <- function(x) {
  x <- num(x)
  if (!is.finite(x)) return("--")
  if (abs(x) >= 10) formatC(x, format = "f", digits = 2) else formatC(x, format = "f", digits = 3)
}
latex_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("([#$%&_{}])", "\\\\\\1", x, perl = TRUE)
  x
}
metric_cols <- c(
  fit = "fit_qtrue_rmse",
  forecast = "forecast_qtrue_mae_H1000",
  check = "forecast_check_loss_H1000"
)
metric_headers <- c("Fit RMSE", "Forecast MAE", "Forecast check")

row_for <- function(family, tau, model_variant) {
  hit <- clean[
    clean$family == family &
      abs(num(clean$tau) - tau) < 1e-9 &
      clean$model_variant == model_variant,
    ,
    drop = FALSE
  ]
  if (nrow(hit) > 1L) {
    hit <- hit[order(num(hit$decision_objective)), , drop = FALSE]
  }
  if (nrow(hit)) hit[1L, , drop = FALSE] else NULL
}

best_values <- function(family, tau, metric_col) {
  vals <- vapply(names(models), function(model_variant) {
    row <- row_for(family, tau, model_variant)
    if (is.null(row)) NA_real_ else num(row[[metric_col]][[1L]])
  }, numeric(1L))
  if (all(!is.finite(vals))) return(NA_real_)
  min(vals, na.rm = TRUE)
}

format_metric <- function(value, best) {
  value <- num(value)
  out <- fmt(value)
  if (is.finite(value) && is.finite(best) && abs(value - best) < 1e-10) {
    return(paste0("\\textbf{", out, "}"))
  }
  out
}

model_label_for_family <- function(family, model_variant) {
  rows <- clean[clean$family == family & clean$model_variant == model_variant, , drop = FALSE]
  label <- models[[model_variant]]
  if (nrow(rows) && any(rows$signoff_grade == "FAIL")) {
    label <- paste0(label, "$^{\\ddagger}$")
  } else if (nrow(rows) && any(rows$signoff_grade == "WARN")) {
    label <- paste0(label, "$^{\\dagger}$")
  }
  label
}

write_family_table <- function(family) {
  path <- file.path(out_dir, sprintf("qdesn_validation_tt500_final_mcmc_%s.tex", family))
  lines <- c(
    "% Article-facing independent simulation MCMC table.",
    "\\begin{table}[!htbp]",
    "\\centering",
    "\\scriptsize",
    "\\setlength{\\tabcolsep}{3.4pt}",
    "\\resizebox{\\textwidth}{!}{%",
    "\\begin{tabular}{@{}lrrrrrrrrr@{}}",
    "\\toprule",
    "Model & \\multicolumn{3}{c}{$p=0.05$} & \\multicolumn{3}{c}{$p=0.25$} & \\multicolumn{3}{c}{$p=0.50$} \\\\",
    "\\cmidrule(lr){2-4} \\cmidrule(lr){5-7} \\cmidrule(lr){8-10}",
    paste(" &", paste(rep(metric_headers, length(taus)), collapse = " & "), "\\\\"),
    "\\midrule"
  )
  for (model_variant in names(models)) {
    cells <- character(0)
    for (tau in taus) {
      row <- row_for(family, tau, model_variant)
      for (metric_col in metric_cols) {
        if (is.null(row)) {
          cells <- c(cells, "--")
        } else {
          cells <- c(cells, format_metric(row[[metric_col]][[1L]], best_values(family, tau, metric_col)))
        }
      }
    }
    lines <- c(lines, paste0(model_label_for_family(family, model_variant), " & ", paste(cells, collapse = " & "), " \\\\"))
  }
  caption <- sprintf(
    "MCMC single-quantile fit-and-forecast comparison for the %s simulation family. Each entry is the best observed value for that model, quantile level, and metric in the fixed case-specific calibration record; entries within one model row may therefore come from different calibrated specifications or replicate seeds. Forecast entries average scored rolling-origin lead-target pairs over the held-out forecast window of length 1000 using leads 1--30 with origin stride 30. Lower values are better, and boldface marks the lowest displayed value within each quantile level and metric. A dagger indicates that at least one contributing metric source has a WARN signoff, while a double dagger indicates at least one FAIL source. Diagnostic status is retained in the reproducibility record and is not used as a metric-exclusion rule.",
    families[[family]]
  )
  lines <- c(
    lines,
    "\\bottomrule",
    "\\end{tabular}%",
    "}",
    sprintf("\\caption{%s}", caption),
    sprintf("\\label{tab:simulation-500obs-mcmc-%s}", family),
    "\\end{table}"
  )
  writeLines(lines, path, useBytes = TRUE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

written <- vapply(family_order, write_family_table, character(1L))

wrapper <- file.path(out_dir, "qdesn_validation_tt500_final_mcmc_tables.tex")
writeLines(c(
  "% Article-facing independent simulation MCMC tables.",
  "\\input{tables/qdesn_validation_tt500_final_mcmc_normal.tex}",
  "\\input{tables/qdesn_validation_tt500_final_mcmc_laplace.tex}",
  "\\input{tables/qdesn_validation_tt500_final_mcmc_gausmix.tex}"
), wrapper, useBytes = TRUE)

manifest_path <- file.path(out_dir, "qdesn_validation_tt500_mcmc_current_best_manifest.txt")
artifact_paths <- c(written, wrapper)
artifact_hashes <- tools::sha256sum(artifact_paths)
manifest_lines <- c(
  "Q-DESN/DQLM 500-observation MCMC metric-wise calibrated article tables",
  sprintf("authority_as_of: %s", authority_freeze$freeze_date),
  sprintf("authority_freeze_id: %s", authority_freeze$freeze_id),
  sprintf(
    "authority_freeze_manifest: %s",
    normalizePath(
      authority_freeze_manifest_path,
      winslash = "/",
      mustWork = TRUE
    )
  ),
  sprintf(
    "authority_freeze_manifest_sha256: %s",
    sha256(authority_freeze_manifest_path)
  ),
  sprintf(
    "validation_authority_commit: %s",
    validation_authority_commit
  ),
  sprintf(
    "latest_evidence_closeout_id: %s",
    authority_freeze$closeout_id
  ),
  sprintf(
    "latest_evidence_decision: %s",
    authority_freeze$scientific_decision
  ),
  sprintf(
    "latest_evidence_coherent_promotion_cells: %d",
    as.integer(authority_freeze$coherent_promotion_cells)
  ),
  sprintf(
    "latest_evidence_article_refresh_metric_rows: %d",
    as.integer(authority_freeze$article_refresh_metric_rows)
  ),
  sprintf(
    "latest_evidence_consumable_run_tag: %s",
    unname(authority_freeze$consumable_scientific_run_tags)
  ),
  sprintf(
    "latest_evidence_rejected_run_tag: %s",
    unname(authority_freeze$permanently_rejected_run_tags)
  ),
  sprintf(
    "exposed_confirmation_origins: %s",
    paste(
      as.integer(unname(authority_freeze$exposed_confirmation_origins)),
      collapse = ","
    )
  ),
  sprintf(
    "article_numeric_state: %s",
    authority_freeze$article_numeric_state
  ),
  "article_numeric_update: FALSE",
  sprintf("source_promotion_id: %s", promotion_manifest$promotion_id),
  sprintf("source_csv: %s", normalizePath(source_csv, winslash = "/", mustWork = TRUE)),
  sprintf("source_manifest: %s", normalizePath(source_manifest, winslash = "/", mustWork = TRUE)),
  sprintf("source_confirmation: %s", normalizePath(source_confirmation, winslash = "/", mustWork = TRUE)),
  sprintf("source_csv_sha256: %s", sha256(source_csv)),
  sprintf("source_manifest_sha256: %s", sha256(source_manifest)),
  sprintf("source_confirmation_sha256: %s", sha256(source_confirmation)),
  sprintf("source_registry_hash: %s", unique(clean$source_registry_hash_value)),
  sprintf("validation_branch: %s", promotion_manifest$validation_branch),
  sprintf(
    "validation_materialization_commit: %s",
    promotion_manifest$validation_commit_at_materialization
  ),
  sprintf("validation_package_version: %s", promotion_manifest$package_version),
  sprintf("row_count_metric_envelope: %d", nrow(clean)),
  sprintf("row_count_candidate_ledger: %d", promotion_manifest$n_candidates),
  sprintf(
    "displayed_envelope_changed_by_confirmation: %s",
    toupper(as.character(promotion_manifest$displayed_envelope_changed))
  ),
  sprintf("coherent_confirmation_run_tag: %s", confirmation$run_tag[[1L]]),
  sprintf("coherent_confirmation_spec_id: %s", confirmation$spec_id[[1L]]),
  sprintf("coherent_confirmation_decision: %s", confirmation$decision[[1L]]),
  sprintf("coherent_confirmation_signoff_grade: %s", confirmation$signoff_grade[[1L]]),
  sprintf("coherent_confirmation_signoff_reason: %s", confirmation$signoff_reason[[1L]]),
  sprintf("coherent_confirmation_fit_rmse: %.15g", confirmation$fit_qtrue_rmse[[1L]]),
  sprintf(
    "coherent_confirmation_forecast_mae_H1000: %.15g",
    confirmation$forecast_qtrue_mae_H1000[[1L]]
  ),
  sprintf(
    "coherent_confirmation_forecast_check_H1000: %.15g",
    confirmation$forecast_check_loss_H1000[[1L]]
  ),
  "selection_policy: minimum observed finite value by model_variant x family x tau x metric; diagnostic status retained but not excluded",
  "interpretation: metric-wise calibrated envelope plus a separately identified coherent full-budget confirmation",
  sprintf("table_normal: %s", file.path("tables", basename(written[["normal"]]))),
  sprintf("table_laplace: %s", file.path("tables", basename(written[["laplace"]]))),
  sprintf("table_gausmix: %s", file.path("tables", basename(written[["gausmix"]]))),
  sprintf("wrapper: %s", file.path("tables", basename(wrapper))),
  "artifact_sha256:",
  sprintf("  %s: %s", basename(names(artifact_hashes)), unname(artifact_hashes))
)
writeLines(manifest_lines, manifest_path, useBytes = TRUE)

cat(sprintf("wrote %d family tables\n", length(written)))
cat(sprintf("manifest: %s\n", normalizePath(manifest_path, winslash = "/", mustWork = TRUE)))
