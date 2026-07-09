#!/usr/bin/env Rscript
# Purpose: evaluate no-refit hybrid quantile-synthesis candidates from a
# completed GloFAS multi-quantile synthesis run.
# Inputs: prediction_quantiles_synthesized.csv from a completed synthesis run.
# Outputs: candidate predictions, consistent scores, crossing diagnostics, and
# figures. This script does not fit models.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/hybrid_quantile_synthesis.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_config.yaml",
  source_run_id = "glofas_multiquantile_dec25_20260603_synthesis_final",
  run_id = NULL
))

cfg <- app_read_config(app_path(args$config))
run_id <- args$run_id %||% sprintf("%s_hybrid_eval", args$source_run_id)
run_dirs <- app_create_run_dirs(cfg, run_id = run_id)
app_stage_start("11_evaluate_glofas_hybrid_synthesis", run_dirs)

source_run_dir <- file.path(app_config_path(cfg, "runs"), args$source_run_id)
source_pred_path <- file.path(source_run_dir, "tables", "prediction_quantiles_synthesized.csv")
if (!file.exists(source_pred_path)) {
  stop(sprintf("Missing completed synthesis prediction table: %s", source_pred_path), call. = FALSE)
}

app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

source_pred <- app_read_csv(source_pred_path)
rules <- app_default_hybrid_synthesis_rules()
hybrid_pred <- app_build_hybrid_quantile_candidates(source_pred, rules)
hybrid_mono <- app_synthesize_quantile_grid(hybrid_pred)
hybrid_mono$monotone_adjustment <- hybrid_mono$qhat_monotone - hybrid_mono$qhat

cross_before <- app_quantile_crossing_diagnostics(hybrid_mono, "qhat", "before_isotonic")
cross_after <- app_quantile_crossing_diagnostics(hybrid_mono, "qhat_monotone", "after_isotonic")
cross_diag <- rbind(cross_before, cross_after)
cross_summary <- app_quantile_crossing_summary(cross_diag)
adjust_summary <- app_monotone_adjustment_summary(hybrid_mono)

score_q <- app_score_quantile_predictions_dual(hybrid_mono, cfg)
score_i <- app_score_intervals(score_q, cfg)
score_c <- app_score_crps_grid(score_q)
summary <- app_score_summary(score_q, score_i, score_c)

score_q_summary <- aggregate(
  cbind(check_loss_independent, check_loss_monotone) ~ model_id + quantile_level,
  score_q,
  mean,
  na.rm = TRUE
)
score_q_summary <- score_q_summary[order(score_q_summary$model_id, score_q_summary$quantile_level), , drop = FALSE]
score_c_h <- aggregate(crps_quantile_grid ~ model_id + horizon, score_c, mean, na.rm = TRUE)

source_diag_path <- file.path(source_run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv")
source_diag <- if (file.exists(source_diag_path)) app_read_csv(source_diag_path) else data.frame()

app_write_csv(rules, file.path(run_dirs$tables, "hybrid_candidate_rules.csv"))
app_write_csv(source_pred, file.path(run_dirs$tables, "source_prediction_quantiles_synthesized.csv"))
app_write_csv(hybrid_pred, file.path(run_dirs$tables, "hybrid_candidate_predictions.csv"))
app_write_csv(hybrid_mono, file.path(run_dirs$tables, "hybrid_candidate_predictions_synthesized.csv"))
app_write_csv(score_q, file.path(run_dirs$tables, "hybrid_score_by_quantile.csv"))
app_write_csv(score_q_summary, file.path(run_dirs$tables, "hybrid_score_by_quantile_summary.csv"))
app_write_csv(score_i, file.path(run_dirs$tables, "hybrid_score_by_interval.csv"))
app_write_csv(score_c, file.path(run_dirs$tables, "hybrid_score_by_crps.csv"))
app_write_csv(score_c_h, file.path(run_dirs$tables, "hybrid_score_by_crps_horizon.csv"))
app_write_csv(summary, file.path(run_dirs$tables, "hybrid_score_summary.csv"))
app_write_csv(cross_diag, file.path(run_dirs$tables, "hybrid_crossing_diagnostics.csv"))
app_write_csv(cross_summary, file.path(run_dirs$tables, "hybrid_crossing_summary.csv"))
app_write_csv(adjust_summary, file.path(run_dirs$tables, "hybrid_monotone_adjustment_summary.csv"))
if (nrow(source_diag)) app_write_csv(source_diag, file.path(run_dirs$tables, "source_qdesn_fit_diagnostics.csv"))

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
fig_dir <- file.path(out_dir, "figures")
app_ensure_dir(fig_dir)

plot_pdf <- function(name, width = 8, height = 4.8, expr) {
  path <- file.path(fig_dir, name)
  grDevices::pdf(path, width = width, height = height)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  path
}

ordered_summary <- summary[order(summary$crps_quantile_grid_mean, summary$check_loss_monotone_mean), , drop = FALSE]
figures <- c()

figures <- c(figures, score_comparison = plot_pdf("glofas_hybrid_candidate_score_comparison.pdf", 9, 5.2, {
  par(mar = c(8, 4, 2, 1))
  vals <- ordered_summary$crps_quantile_grid_mean
  cols <- ifelse(grepl("^raw_all$", ordered_summary$model_id), "#6b7280",
    ifelse(grepl("^qdesn_all$", ordered_summary$model_id), "#b91c1c", "#2563eb")
  )
  barplot(vals, names.arg = ordered_summary$model_id, las = 2, cex.names = 0.68,
    col = cols, border = NA, ylab = "Mean quantile-grid CRPS")
  grid(nx = NA, ny = NULL, col = "gray88")
}))

figures <- c(figures, quantile_check_loss = plot_pdf("glofas_hybrid_per_quantile_check_loss.pdf", 9, 5.4, {
  keep <- score_q_summary$model_id %in% head(ordered_summary$model_id, 6L)
  dat <- score_q_summary[keep, , drop = FALSE]
  qs <- sort(unique(dat$quantile_level))
  mids <- unique(dat$model_id)
  mat <- matrix(NA_real_, nrow = length(qs), ncol = length(mids), dimnames = list(paste0("p=", qs), mids))
  for (i in seq_len(nrow(dat))) {
    mat[paste0("p=", dat$quantile_level[[i]]), dat$model_id[[i]]] <- dat$check_loss_monotone[[i]]
  }
  par(mar = c(8, 4, 2, 1))
  barplot(mat, beside = TRUE, las = 2, cex.names = 0.72,
    col = grDevices::hcl.colors(nrow(mat), "Dark 3"),
    ylab = "Mean monotone check loss")
  legend("topright", legend = rownames(mat), fill = grDevices::hcl.colors(nrow(mat), "Dark 3"), bty = "n", cex = 0.78)
}))

figures <- c(figures, crps_by_horizon = plot_pdf("glofas_hybrid_crps_by_horizon.pdf", 8.4, 5.2, {
  keep_ids <- head(ordered_summary$model_id, 5L)
  dat <- score_c_h[score_c_h$model_id %in% keep_ids, , drop = FALSE]
  ylim <- range(dat$crps_quantile_grid, na.rm = TRUE)
  plot(range(dat$horizon), ylim + c(-0.05, 0.05) * diff(ylim), type = "n",
    xlab = "Forecast horizon", ylab = "Quantile-grid CRPS")
  grid(col = "gray90")
  cols <- grDevices::hcl.colors(length(keep_ids), "Dark 3")
  for (i in seq_along(keep_ids)) {
    block <- dat[dat$model_id == keep_ids[[i]], , drop = FALSE]
    block <- block[order(block$horizon), , drop = FALSE]
    lines(block$horizon, block$crps_quantile_grid, col = cols[[i]], lwd = 1.8)
  }
  legend("topleft", legend = keep_ids, col = cols, lty = 1, lwd = 1.8, bty = "n", cex = 0.68)
}))

figures <- c(figures, monotone_adjustments = plot_pdf("glofas_hybrid_monotone_adjustments.pdf", 8.6, 5.2, {
  keep_ids <- c("qdesn_all", "qdesn_center_35_80_raw_tails", "raw_all", "blend_tail_raw_center50")
  dat <- adjust_summary[adjust_summary$model_id %in% keep_ids, , drop = FALSE]
  qs <- sort(unique(dat$quantile_level))
  mat <- matrix(NA_real_, nrow = length(keep_ids), ncol = length(qs), dimnames = list(keep_ids, paste0("p=", qs)))
  for (i in seq_len(nrow(dat))) {
    mat[dat$model_id[[i]], paste0("p=", dat$quantile_level[[i]])] <- dat$mean_abs_adjustment[[i]]
  }
  image(seq_len(ncol(mat)), seq_len(nrow(mat)), t(mat[nrow(mat):1, , drop = FALSE]),
    axes = FALSE, xlab = "Quantile level", ylab = "Candidate", col = grDevices::hcl.colors(30, "YlOrRd", rev = FALSE))
  axis(1, at = seq_len(ncol(mat)), labels = colnames(mat), las = 2, cex.axis = 0.8)
  axis(2, at = seq_len(nrow(mat)), labels = rev(rownames(mat)), las = 2, cex.axis = 0.68)
  box()
  title("Mean absolute isotonic adjustment")
}))

hybrid_score_tex <- file.path(out_dir, "glofas_hybrid_synthesis_score_summary.tex")
app_make_score_table_tex(ordered_summary, hybrid_score_tex)

outputs <- c(score_summary_table = hybrid_score_tex, figures)
prov <- app_write_output_provenance(
  outputs = outputs,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "manuscript_output_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "manuscript_output_provenance.csv"))

readiness_report <- data.frame(
  category = c("source", "candidates", "scores", "synthesis", "figures"),
  check = c(
    "source_prediction_table_exists",
    "hybrid_candidates_created",
    "monotone_scores_created",
    "post_synthesis_crossings_absent",
    "diagnostic_figures_exist"
  ),
  passed = c(
    file.exists(source_pred_path),
    length(unique(hybrid_mono$model_id)) == nrow(rules),
    all(c("check_loss_independent", "check_loss_monotone") %in% names(score_q)),
    sum(cross_after$n_crossing_pairs, na.rm = TRUE) == 0,
    all(file.exists(unname(figures)))
  ),
  detail = c(
    source_pred_path,
    paste(unique(hybrid_mono$model_id), collapse = "; "),
    file.path(run_dirs$tables, "hybrid_score_summary.csv"),
    sprintf("crossing_pairs_after=%d", sum(cross_after$n_crossing_pairs, na.rm = TRUE)),
    paste(unname(figures), collapse = "; ")
  ),
  stringsAsFactors = FALSE
)
app_write_csv(readiness_report, file.path(run_dirs$tables, "launch_readiness_report.csv"))
writeLines(
  c(
    sprintf("run_id: %s", basename(run_dirs$run_dir)),
    sprintf("source_run_id: %s", args$source_run_id),
    sprintf("all_checks_passed: %s", all(readiness_report$passed)),
    sprintf("best_by_crps: %s", ordered_summary$model_id[[1L]]),
    sprintf("generated_outputs: %s", out_dir)
  ),
  file.path(run_dirs$tables, "launch_readiness_summary.txt")
)

app_stage_done("11_evaluate_glofas_hybrid_synthesis", run_dirs)
cat(run_dirs$run_dir, "\n")
