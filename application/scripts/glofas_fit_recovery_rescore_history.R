#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  evidence_root = "local_trackers/runtime_configs/glofas_fit_recovery_20260730/evidence",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_20260730/no_refit_comparison",
  cutoff_date = "2022-12-25",
  windows = "all,1000,500,200,100,50"
))
resolve_repo <- function(path) if (grepl("^/", path)) path else app_path(path)
parse_windows <- function(x) {
  values <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  vapply(values, function(value) {
    if (tolower(value) == "all") NA_integer_ else as.integer(value)
  }, integer(1L))
}

evidence_root <- resolve_repo(args$evidence_root)
output_root <- resolve_repo(args$output_root)
app_ensure_dir(output_root)
candidates <- c("engine07", "memrefine11")
histories <- lapply(candidates, function(candidate_id) {
  path <- file.path(
    evidence_root,
    candidate_id,
    "tables",
    "post_fit_quantile_history_summary.csv"
  )
  app_glofas_fit_recovery_history(
    path,
    candidate_id = candidate_id,
    cutoff_date = as.Date(args$cutoff_date)
  )
})
names(histories) <- candidates
histories <- app_glofas_fit_recovery_align_histories(histories)
windows <- parse_windows(args$windows)
scores <- do.call(rbind, lapply(histories, app_glofas_fit_recovery_score_history, windows = windows))
rownames(scores) <- NULL
common_history <- do.call(rbind, histories)
rownames(common_history) <- NULL
app_write_csv(scores, file.path(output_root, "historical_common_date_scores.csv"))
app_write_csv(common_history, file.path(output_root, "historical_common_date_history.csv"))

pdf(file.path(output_root, "historical_common_scale_last200.pdf"), width = 11, height = 8.5)
old_par <- par(no.readonly = TRUE)
on.exit({
  par(old_par)
  dev.off()
}, add = TRUE)
par(mfrow = c(2, 1), mar = c(3.5, 4.5, 2.5, 1))
colors <- c(engine07 = "#2B6CB0", memrefine11 = "#C05621")
last_dates <- tail(sort(unique(common_history$target_date)), 200L)
for (scale in c("log1p", "original")) {
  subset_history <- common_history[common_history$target_date %in% last_dates, , drop = FALSE]
  y_name <- paste0("y_", scale)
  q_name <- paste0("qhat_", scale)
  y <- subset_history[subset_history$candidate_id == candidates[[1L]], , drop = FALSE]
  ylim <- range(c(subset_history[[y_name]], subset_history[[q_name]]), finite = TRUE)
  plot(y$target_date, y[[y_name]], type = "l", col = "black", lwd = 1.2, xlab = "", ylab = scale, ylim = ylim)
  for (candidate_id in candidates) {
    h <- subset_history[subset_history$candidate_id == candidate_id, , drop = FALSE]
    lines(h$target_date, h[[q_name]], col = colors[[candidate_id]], lwd = 1)
  }
  title(sprintf("Historical p50 fit: final 200 pre-cutoff observations (%s scale)", scale))
  legend("topleft", legend = c("USGS", candidates), col = c("black", colors), lty = 1, bty = "n", cex = 0.8)
}
cat(file.path(output_root, "historical_common_date_scores.csv"), "\n")
