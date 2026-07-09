#!/usr/bin/env Rscript

script_file <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_file), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))

args <- app_parse_args(list(
  input_csv = app_path("tables/qdesn_validation_tt500_final_summary.csv"),
  out_csv = app_path("tables/qdesn_validation_tt500_pathology_audit.csv"),
  out_md = app_path("tables/qdesn_validation_tt500_pathology_audit.md"),
  strict = "false",
  catastrophic_mae_vs_external = "5",
  catastrophic_pinball_vs_external = "2.5",
  catastrophic_mae_vs_cell_best = "8",
  catastrophic_pinball_vs_cell_best = "3",
  review_mae_vs_external = "2",
  review_pinball_vs_external = "1.5",
  review_mae_vs_cell_best = "3",
  review_pinball_vs_cell_best = "2"
))

as_bool <- function(x) {
  if (is.logical(x)) return(isTRUE(x[1L]))
  tolower(as.character(x)[1L]) %in% c("true", "t", "1", "yes")
}
num_arg <- function(name) as.numeric(args[[name]])[1L]
ratio <- function(num, den) {
  out <- as.numeric(num) / as.numeric(den)
  out[!is.finite(out)] <- NA_real_
  out
}

summary <- read.csv(args$input_csv, stringsAsFactors = FALSE, check.names = FALSE)
required <- c(
  "model_family", "model_key", "model_label", "qdesn_likelihood",
  "inference", "family", "tau", "fit_size", "fit_qtrue_rmse",
  "forecast_qtrue_mae_lead_weighted", "forecast_pinball_mean_lead_weighted",
  "validation_commit", "article_interface_ids"
)
missing <- setdiff(required, names(summary))
if (length(missing)) {
  stop(sprintf("TT500 summary missing required column(s): %s", paste(missing, collapse = ", ")), call. = FALSE)
}

summary$tau <- as.numeric(summary$tau)
summary$fit_size <- as.integer(summary$fit_size)
cell_key <- paste(summary$family, summary$inference, sprintf("%.8f", summary$tau), sep = "\r")

cell_best <- do.call(rbind, lapply(split(summary, cell_key), function(block) {
  baselines <- block[block$model_key %in% c("dqlm", "exdqlm"), , drop = FALSE]
  data.frame(
    family = block$family[[1L]],
    inference = block$inference[[1L]],
    tau = block$tau[[1L]],
    external_best_mae = min(as.numeric(baselines$forecast_qtrue_mae_lead_weighted), na.rm = TRUE),
    external_best_pinball = min(as.numeric(baselines$forecast_pinball_mean_lead_weighted), na.rm = TRUE),
    cell_best_mae = min(as.numeric(block$forecast_qtrue_mae_lead_weighted), na.rm = TRUE),
    cell_best_pinball = min(as.numeric(block$forecast_pinball_mean_lead_weighted), na.rm = TRUE),
    stringsAsFactors = FALSE
  )
}))

qdesn <- merge(
  summary[summary$model_family == "qdesn", , drop = FALSE],
  cell_best,
  by = c("family", "inference", "tau"),
  all.x = TRUE,
  sort = FALSE
)
qdesn$mae_vs_external <- ratio(qdesn$forecast_qtrue_mae_lead_weighted, qdesn$external_best_mae)
qdesn$pinball_vs_external <- ratio(qdesn$forecast_pinball_mean_lead_weighted, qdesn$external_best_pinball)
qdesn$mae_vs_cell_best <- ratio(qdesn$forecast_qtrue_mae_lead_weighted, qdesn$cell_best_mae)
qdesn$pinball_vs_cell_best <- ratio(qdesn$forecast_pinball_mean_lead_weighted, qdesn$cell_best_pinball)

cat_mae_ext <- num_arg("catastrophic_mae_vs_external")
cat_pin_ext <- num_arg("catastrophic_pinball_vs_external")
cat_mae_best <- num_arg("catastrophic_mae_vs_cell_best")
cat_pin_best <- num_arg("catastrophic_pinball_vs_cell_best")
rev_mae_ext <- num_arg("review_mae_vs_external")
rev_pin_ext <- num_arg("review_pinball_vs_external")
rev_mae_best <- num_arg("review_mae_vs_cell_best")
rev_pin_best <- num_arg("review_pinball_vs_cell_best")

qdesn$severity <- "ok"
qdesn$severity[
  qdesn$mae_vs_external >= rev_mae_ext |
    qdesn$pinball_vs_external >= rev_pin_ext |
    qdesn$mae_vs_cell_best >= rev_mae_best |
    qdesn$pinball_vs_cell_best >= rev_pin_best
] <- "needs_review"
qdesn$severity[
  qdesn$mae_vs_external >= cat_mae_ext |
    qdesn$pinball_vs_external >= cat_pin_ext |
    qdesn$mae_vs_cell_best >= cat_mae_best |
    qdesn$pinball_vs_cell_best >= cat_pin_best
] <- "catastrophic"

qdesn$pathology_reason <- vapply(seq_len(nrow(qdesn)), function(i) {
  reasons <- character()
  if (isTRUE(qdesn$mae_vs_external[[i]] >= rev_mae_ext)) reasons <- c(reasons, sprintf("forecast_mae %.2fx external", qdesn$mae_vs_external[[i]]))
  if (isTRUE(qdesn$pinball_vs_external[[i]] >= rev_pin_ext)) reasons <- c(reasons, sprintf("check_loss %.2fx external", qdesn$pinball_vs_external[[i]]))
  if (isTRUE(qdesn$mae_vs_cell_best[[i]] >= rev_mae_best)) reasons <- c(reasons, sprintf("forecast_mae %.2fx cell_best", qdesn$mae_vs_cell_best[[i]]))
  if (isTRUE(qdesn$pinball_vs_cell_best[[i]] >= rev_pin_best)) reasons <- c(reasons, sprintf("check_loss %.2fx cell_best", qdesn$pinball_vs_cell_best[[i]]))
  paste(reasons, collapse = "; ")
}, character(1L))

out <- qdesn[, c(
  "family", "tau", "inference", "model_key", "model_label",
  "fit_qtrue_rmse", "forecast_qtrue_mae_lead_weighted",
  "forecast_pinball_mean_lead_weighted", "external_best_mae",
  "external_best_pinball", "cell_best_mae", "cell_best_pinball",
  "mae_vs_external", "pinball_vs_external", "mae_vs_cell_best",
  "pinball_vs_cell_best", "severity", "pathology_reason",
  "validation_commit", "article_interface_ids"
)]
family_order <- c(normal = 1L, laplace = 2L, gausmix = 3L)
inference_order <- c(vb = 1L, mcmc = 2L)
out <- out[order(inference_order[out$inference], out$model_key, family_order[out$family], out$tau), , drop = FALSE]
row.names(out) <- NULL

dir.create(dirname(args$out_csv), recursive = TRUE, showWarnings = FALSE)
write.csv(out, args$out_csv, row.names = FALSE)

counts <- as.data.frame.matrix(table(out$model_key, out$severity))
for (col in c("ok", "needs_review", "catastrophic")) {
  if (!col %in% names(counts)) counts[[col]] <- 0L
}
counts$model_key <- rownames(counts)
counts <- counts[, c("model_key", "ok", "needs_review", "catastrophic")]
rownames(counts) <- NULL

flagged <- out[out$severity != "ok", , drop = FALSE]
flagged_display <- flagged[, c(
  "family", "tau", "inference", "model_label",
  "forecast_qtrue_mae_lead_weighted", "forecast_pinball_mean_lead_weighted",
  "mae_vs_external", "pinball_vs_external", "mae_vs_cell_best",
  "pinball_vs_cell_best", "severity", "article_interface_ids"
), drop = FALSE]
names(flagged_display) <- c(
  "family", "tau", "inference", "model_label",
  "forecast_qtrue_mae_lead_weighted", "forecast_check_loss_lead_weighted",
  "mae_vs_external", "check_loss_vs_external", "mae_vs_cell_best",
  "check_loss_vs_cell_best", "severity", "article_interface_ids"
)
md <- c(
  "# 500-Observation Validation Pathology Audit",
  "",
  sprintf("- input_csv: `%s`", normalizePath(args$input_csv, winslash = "/", mustWork = TRUE)),
  sprintf("- output_csv: `%s`", normalizePath(args$out_csv, winslash = "/", mustWork = FALSE)),
  sprintf("- generated_at: `%s`", as.character(Sys.time())),
  "",
  "## Thresholds",
  "",
  sprintf("- catastrophic: MAE >= %.2fx external OR check loss >= %.2fx external OR MAE >= %.2fx cell-best OR check loss >= %.2fx cell-best", cat_mae_ext, cat_pin_ext, cat_mae_best, cat_pin_best),
  sprintf("- needs_review: MAE >= %.2fx external OR check loss >= %.2fx external OR MAE >= %.2fx cell-best OR check loss >= %.2fx cell-best", rev_mae_ext, rev_pin_ext, rev_mae_best, rev_pin_best),
  "",
  "## Severity Counts",
  "",
  paste(capture.output(print(counts, row.names = FALSE)), collapse = "\n"),
  "",
  "## Flagged Rows",
  "",
  if (nrow(flagged)) {
    paste(capture.output(print(flagged_display, row.names = FALSE)), collapse = "\n")
  } else {
    "No flagged Q-DESN rows."
  }
)
writeLines(md, args$out_md, useBytes = TRUE)

cat("500-observation pathology audit: PASS\n")
cat(sprintf("qdesn_rows: %d\n", nrow(out)))
cat(sprintf("flagged_rows: %d\n", nrow(flagged)))
cat(sprintf("catastrophic_rows: %d\n", sum(out$severity == "catastrophic")))
cat(sprintf("csv: %s\n", normalizePath(args$out_csv, winslash = "/", mustWork = TRUE)))
cat(sprintf("md: %s\n", normalizePath(args$out_md, winslash = "/", mustWork = TRUE)))
if (as_bool(args$strict) && any(out$severity == "catastrophic")) {
  quit(status = 1L, save = "no")
}
