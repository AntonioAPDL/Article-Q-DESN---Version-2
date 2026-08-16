#!/usr/bin/env Rscript

script_file <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_file), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))

args <- app_parse_args(list(
  input_csv = app_path("tables/qdesn_validation_tt500_final_summary.csv"),
  out_csv = app_path("tables/qdesn_validation_tt500_vb_competitiveness_audit.csv"),
  require_all_cells = "false"
))

as_bool <- function(x) {
  if (is.logical(x)) return(isTRUE(x[1L]))
  tolower(as.character(x)[1L]) %in% c("true", "t", "1", "yes")
}

metrics <- c(
  "fit_qtrue_rmse",
  "fit_pinball_mean",
  "forecast_qtrue_mae_lead_weighted",
  "forecast_pinball_mean_lead_weighted"
)

summary <- read.csv(args$input_csv, stringsAsFactors = FALSE, check.names = FALSE)
missing_metrics <- setdiff(metrics, names(summary))
if (length(missing_metrics)) {
  stop(sprintf("Summary table is missing required metric(s): %s", paste(missing_metrics, collapse = ", ")), call. = FALSE)
}

vb <- summary[summary$inference == "vb", , drop = FALSE]
qdesn <- vb[
  vb$model_family == "qdesn" &
    vb$model_key == "qdesn_exal_rhs_ns" &
    vb$qdesn_likelihood == "exal",
  ,
  drop = FALSE
]
baselines <- vb[vb$model_family == "exdqlm_dqlm", , drop = FALSE]

if (nrow(qdesn) != 9L) {
  stop(sprintf("Expected 9 Q-DESN exAL RHS VB rows; found %d.", nrow(qdesn)), call. = FALSE)
}
if (nrow(baselines) != 18L) {
  stop(sprintf("Expected 18 DQLM/exDQLM VB baseline rows; found %d.", nrow(baselines)), call. = FALSE)
}

audit_rows <- lapply(seq_len(nrow(qdesn)), function(i) {
  row <- qdesn[i, , drop = FALSE]
  base <- baselines[
    baselines$family == row$family[[1L]] &
      abs(as.numeric(baselines$tau) - as.numeric(row$tau[[1L]])) < 1.0e-12,
    ,
    drop = FALSE
  ]
  if (nrow(base) != 2L) {
    stop(sprintf("Expected two VB baseline rows for %s tau %.2f.", row$family[[1L]], as.numeric(row$tau[[1L]])), call. = FALSE)
  }
  best <- vapply(metrics, function(metric) min(as.numeric(base[[metric]]), na.rm = TRUE), numeric(1L))
  qvals <- vapply(metrics, function(metric) as.numeric(row[[metric]][[1L]]), numeric(1L))
  ratios <- qvals / best
  data.frame(
    family = row$family[[1L]],
    tau = as.numeric(row$tau[[1L]]),
    qdesn_validation_commit = row$validation_commit[[1L]],
    qdesn_article_interface_ids = row$article_interface_ids[[1L]],
    qdesn_fit_qtrue_rmse = qvals[["fit_qtrue_rmse"]],
    best_dqlm_exdqlm_vb_fit_qtrue_rmse = best[["fit_qtrue_rmse"]],
    ratio_fit_qtrue_rmse = ratios[["fit_qtrue_rmse"]],
    qdesn_fit_pinball_mean = qvals[["fit_pinball_mean"]],
    best_dqlm_exdqlm_vb_fit_pinball_mean = best[["fit_pinball_mean"]],
    ratio_fit_pinball_mean = ratios[["fit_pinball_mean"]],
    qdesn_forecast_qtrue_mae_lead_weighted = qvals[["forecast_qtrue_mae_lead_weighted"]],
    best_dqlm_exdqlm_vb_forecast_qtrue_mae_lead_weighted = best[["forecast_qtrue_mae_lead_weighted"]],
    ratio_forecast_qtrue_mae_lead_weighted = ratios[["forecast_qtrue_mae_lead_weighted"]],
    qdesn_forecast_pinball_mean_lead_weighted = qvals[["forecast_pinball_mean_lead_weighted"]],
    best_dqlm_exdqlm_vb_forecast_pinball_mean_lead_weighted = best[["forecast_pinball_mean_lead_weighted"]],
    ratio_forecast_pinball_mean_lead_weighted = ratios[["forecast_pinball_mean_lead_weighted"]],
    beats_best_dqlm_exdqlm_vb_all_four = all(qvals < best),
    stringsAsFactors = FALSE
  )
})

audit <- do.call(rbind, audit_rows)
family_order <- c(normal = 1L, laplace = 2L, gausmix = 3L)
audit <- audit[order(family_order[audit$family], audit$tau), , drop = FALSE]
row.names(audit) <- NULL

if (as_bool(args$require_all_cells) && !all(audit$beats_best_dqlm_exdqlm_vb_all_four)) {
  failed <- audit[!audit$beats_best_dqlm_exdqlm_vb_all_four, c("family", "tau"), drop = FALSE]
  stop(sprintf(
    "Q-DESN exAL RHS VB does not beat all DQLM/exDQLM VB baselines for: %s",
    paste(paste(failed$family, failed$tau, sep = " tau "), collapse = "; ")
  ), call. = FALSE)
}

dir.create(dirname(args$out_csv), recursive = TRUE, showWarnings = FALSE)
write.csv(audit, args$out_csv, row.names = FALSE)

ratio_cols <- grep("^ratio_", names(audit), value = TRUE)
if (any(!is.finite(as.numeric(unlist(audit[ratio_cols], use.names = FALSE))))) {
  stop("500-observation VB competitiveness audit contains non-finite ratios.", call. = FALSE)
}
cat("500-observation VB competitiveness audit: PASS\n")
cat(sprintf("cells: %d\n", nrow(audit)))
cat(sprintf("cells_beating_best_dqlm_exdqlm_vb_all_four: %d\n", sum(audit$beats_best_dqlm_exdqlm_vb_all_four)))
cat(sprintf("cells_not_beating_best_dqlm_exdqlm_vb_all_four: %d\n", sum(!audit$beats_best_dqlm_exdqlm_vb_all_four)))
for (col in ratio_cols) {
  cat(sprintf("max_%s: %.6f\n", col, max(audit[[col]], na.rm = TRUE)))
}
cat(sprintf("csv: %s\n", normalizePath(args$out_csv, winslash = "/", mustWork = TRUE)))
