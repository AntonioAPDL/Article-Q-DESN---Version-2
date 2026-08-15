#!/usr/bin/env Rscript
# Purpose: create a no-refit diagnostic bundle comparing the two strongest
# p05/p50/p95 GloFAS discrepancy-smoothing gate candidates.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  runtime_dir = "local_trackers/runtime_configs/glofas_discrepancy_smoothing_gate_20260616",
  candidate_ids = "c03,c02",
  run_id = "glofas_discrepancy_smoothing_gate_20260616_c03_c02_diagnostics",
  history_days = "1000"
))

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("This diagnostic script requires ggplot2.", call. = FALSE)
}

runtime_dir <- app_path(args$runtime_dir)
health_path <- file.path(runtime_dir, "health_check_latest.csv")
ranking_path <- file.path(runtime_dir, "candidate_ranking_latest.csv")
if (!file.exists(health_path)) stop(sprintf("Missing health file: %s", health_path), call. = FALSE)
if (!file.exists(ranking_path)) stop(sprintf("Missing ranking file: %s", ranking_path), call. = FALSE)

candidate_ids <- trimws(strsplit(as.character(args$candidate_ids), ",", fixed = TRUE)[[1L]])
history_days <- as.integer(args$history_days)
if (!is.finite(history_days) || history_days < 1L) history_days <- 1000L

health <- app_read_csv(health_path)
ranking <- app_read_csv(ranking_path)
health <- health[health$candidate_id %in% candidate_ids, , drop = FALSE]
if (!nrow(health)) stop("No requested candidates found in health file.", call. = FALSE)
if (!all(health$status == "complete_scored")) {
  stop("All requested candidate rows must be complete_scored before diagnostics.", call. = FALSE)
}
health$quantile_level <- as.numeric(health$quantile_level)
health <- health[order(match(health$candidate_id, candidate_ids), health$quantile_level), , drop = FALSE]

cfg <- list(
  application_name = args$run_id,
  .__config_path__ = args$runtime_dir,
  paths = list(
    runs = "application/runs",
    generated_outputs = "application/outputs/generated"
  )
)
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("37_make_glofas_gate_candidate_diagnostics_20260616", run_dirs)
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

out_dir <- file.path(app_path("application/outputs/generated"), basename(run_dirs$run_dir))
fig_dir <- file.path(out_dir, "figures")
app_ensure_dir(fig_dir)

safe_num <- function(x) suppressWarnings(as.numeric(x))
read_optional <- function(path) if (file.exists(path)) app_read_csv(path) else data.frame()

column_draw_summary <- function(x, level = 0.80) {
  lo <- (1 - level) / 2
  hi <- 1 - lo
  data.frame(
    estimate_lo = as.numeric(apply(x, 2L, stats::quantile, probs = lo, na.rm = TRUE, names = FALSE)),
    estimate_mid = as.numeric(apply(x, 2L, stats::quantile, probs = 0.50, na.rm = TRUE, names = FALSE)),
    estimate_hi = as.numeric(apply(x, 2L, stats::quantile, probs = hi, na.rm = TRUE, names = FALSE)),
    stringsAsFactors = FALSE
  )
}

make_history_block <- function(row) {
  run_dir <- app_path(file.path("application/runs", row$run_id[[1L]]))
  model_grid <- app_read_csv(file.path(runtime_dir, paste0(row$candidate_id[[1L]], "_", gsub("[^A-Za-z0-9_.-]+", "_", tolower(row$candidate_name[[1L]]))), sprintf("model_grid_%s.csv", row$quantile_id[[1L]])))
  qfit <- model_grid$model_id[model_grid$model_family == "qdesn_glofas_discrepancy"][[1L]]
  fit_id <- model_grid$fit_id[model_grid$model_family == "qdesn_glofas_discrepancy"][[1L]]
  fit_path <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
  design_path <- file.path(run_dir, "objects", paste0(fit_id, "__design.rds"))
  if (!file.exists(fit_path) || !file.exists(design_path)) return(data.frame())
  fit <- readRDS(fit_path)
  design <- readRDS(design_path)
  theta_mean <- safe_num(fit$summary$theta_mean %||% fit$variational_state$theta_mean %||% numeric())
  alpha_idx <- as.integer(design$alpha_index %||% integer())
  X_alpha <- design$X_alpha %||% NULL
  base <- design$base_panel %||% data.frame()
  if (!length(alpha_idx) || is.null(X_alpha) || !nrow(base) || nrow(base) != nrow(X_alpha) || length(theta_mean) < max(alpha_idx)) {
    return(data.frame())
  }
  base$target_date <- as.Date(base$target_date)
  origin_date <- as.Date((design$latent_data %||% list())$origin_date %||% max(base$target_date, na.rm = TRUE))
  keep <- which(base$target_date >= origin_date - history_days & base$target_date <= origin_date)
  if (!length(keep)) return(data.frame())
  X_keep <- as.matrix(X_alpha[keep, , drop = FALSE])
  alpha_mean <- theta_mean[alpha_idx]
  out <- data.frame(
    candidate_id = row$candidate_id[[1L]],
    candidate_name = row$candidate_name[[1L]],
    quantile_id = row$quantile_id[[1L]],
    quantile_level = as.numeric(row$quantile_level[[1L]]),
    target_date = base$target_date[keep],
    observed_discrepancy = safe_num(base$g_transformed[keep]) - safe_num(base$y_transformed[keep]),
    estimate = as.numeric(X_keep %*% alpha_mean),
    qdesn_check_loss = as.numeric(row$qdesn_check_loss[[1L]]),
    raw_check_loss = as.numeric(row$raw_check_loss[[1L]]),
    stringsAsFactors = FALSE
  )
  theta_draw <- fit$draws$theta %||% NULL
  if (!is.null(theta_draw) && ncol(theta_draw) >= max(alpha_idx)) {
    alpha_draw <- theta_draw[, alpha_idx, drop = FALSE]
    out <- cbind(out, column_draw_summary(alpha_draw %*% t(X_keep), level = 0.80))
  } else {
    out$estimate_lo <- NA_real_
    out$estimate_mid <- NA_real_
    out$estimate_hi <- NA_real_
  }
  out
}

history_rows <- lapply(seq_len(nrow(health)), function(i) make_history_block(health[i, , drop = FALSE]))
history <- app_bind_rows_fill(history_rows)
if (!nrow(history)) stop("No discrepancy history rows could be reconstructed.", call. = FALSE)
app_write_csv(history, file.path(run_dirs$tables, "candidate_discrepancy_history.csv"))

score_table <- health[, c(
  "candidate_id", "candidate_name", "quantile_id", "quantile_level",
  "runtime_min", "qdesn_check_loss", "raw_check_loss", "relative_improvement"
), drop = FALSE]
app_write_csv(score_table, file.path(run_dirs$tables, "candidate_quantile_scores.csv"))
app_write_csv(ranking[ranking$candidate_id %in% candidate_ids, , drop = FALSE], file.path(run_dirs$tables, "candidate_ranking_subset.csv"))

theme_diag <- function() {
  ggplot2::theme_bw(base_size = 10) +
    ggplot2::theme(
      legend.position = "bottom",
      panel.grid.minor = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "gray94", color = "gray80")
    )
}

figures <- c()
score_plot <- ggplot2::ggplot(score_table, ggplot2::aes(x = quantile_id, y = qdesn_check_loss, fill = candidate_id)) +
  ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.72), width = 0.64) +
  ggplot2::geom_point(ggplot2::aes(y = raw_check_loss), position = ggplot2::position_dodge(width = 0.72), shape = 21, size = 2.2, fill = "white") +
  ggplot2::labs(x = "Target quantile", y = "Check loss", fill = "Candidate", title = "Gate scores for c03 and c02") +
  theme_diag()
figures[["gate_score_comparison"]] <- file.path(fig_dir, "glofas_gate_c03_c02_score_comparison.pdf")
ggplot2::ggsave(figures[["gate_score_comparison"]], score_plot, width = 7.4, height = 4.8, units = "in", device = grDevices::cairo_pdf)

hist_plot <- ggplot2::ggplot(history, ggplot2::aes(x = target_date)) +
  ggplot2::geom_ribbon(ggplot2::aes(ymin = estimate_lo, ymax = estimate_hi, fill = candidate_id), alpha = 0.16, color = NA) +
  ggplot2::geom_line(ggplot2::aes(y = observed_discrepancy), color = "#111111", linewidth = 0.45) +
  ggplot2::geom_line(ggplot2::aes(y = estimate, color = candidate_id), linewidth = 0.65) +
  ggplot2::facet_grid(quantile_id ~ candidate_id, scales = "free_y") +
  ggplot2::labs(x = NULL, y = "Transformed discrepancy", color = "Candidate", fill = "Candidate", title = "Pre-cutoff discrepancy fit over the final history window") +
  theme_diag()
figures[["discrepancy_history"]] <- file.path(fig_dir, "glofas_gate_c03_c02_discrepancy_history.pdf")
ggplot2::ggsave(figures[["discrepancy_history"]], hist_plot, width = 9.2, height = 7.0, units = "in", device = grDevices::cairo_pdf)

prov <- app_write_output_provenance(
  outputs = unlist(figures, use.names = TRUE),
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "diagnostic_figure_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "diagnostic_figure_provenance.csv"))

readiness <- data.frame(
  check = c("requested_candidates_complete", "history_rows_reconstructed", "figures_exist"),
  passed = c(all(health$status == "complete_scored"), nrow(history) > 0L, all(file.exists(unname(unlist(figures, use.names = TRUE))))),
  detail = c(paste(candidate_ids, collapse = ", "), as.character(nrow(history)), paste(unname(unlist(figures, use.names = TRUE)), collapse = "; ")),
  stringsAsFactors = FALSE
)
app_write_csv(readiness, file.path(run_dirs$tables, "diagnostic_readiness_report.csv"))
if (!all(readiness$passed)) stop("Diagnostic readiness failed.", call. = FALSE)

app_stage_done("37_make_glofas_gate_candidate_diagnostics_20260616", run_dirs)
cat(run_dirs$run_dir, "\n")
cat(out_dir, "\n")
