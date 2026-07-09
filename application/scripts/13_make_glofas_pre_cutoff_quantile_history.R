#!/usr/bin/env Rscript
# Purpose: plot the last pre-cutoff retrospective USGS path together with the
# fitted Q-DESN quantile dynamics from completed per-quantile application fits.
# This script is no-refit: it reads saved fit/design objects and writes
# diagnostic tables and figures.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/make_manuscript_outputs.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_config.yaml",
  source_manifest = "local_trackers/runtime_configs/glofas_multiquantile_dec25_20260603/synthesis_source_manifest.csv",
  run_id = "glofas_multiquantile_dec25_20260603_pre_cutoff_history",
  history_n = 1000
))

cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
app_stage_start("13_make_glofas_pre_cutoff_quantile_history", run_dirs)
app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

resolve_path <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

manifest <- app_read_csv(app_path(args$source_manifest))
if ("enabled" %in% names(manifest)) manifest <- manifest[app_as_bool_vec(manifest$enabled), , drop = FALSE]
required <- c("quantile_id", "quantile_level", "run_dir", "qdesn_fit_id")
app_check_required_columns(manifest, required, "synthesis source manifest")
manifest$quantile_level <- as.numeric(manifest$quantile_level)
manifest <- manifest[order(manifest$quantile_level), , drop = FALSE]

history_n <- as.integer(args$history_n)
if (!is.finite(history_n) || history_n <= 0L) stop("--history_n must be a positive integer.", call. = FALSE)

rows <- list()
fit_paths <- character()
reference_panel <- NULL
cutoff_date <- NULL

for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  run_dir <- resolve_path(row$run_dir[[1L]])
  fit_id <- row$qdesn_fit_id[[1L]]
  fit_path <- file.path(run_dir, "objects", paste0(fit_id, ".rds"))
  design_path <- file.path(run_dir, "objects", paste0(fit_id, "__design.rds"))
  if (!file.exists(fit_path)) stop(sprintf("Missing fit object: %s", fit_path), call. = FALSE)
  if (!file.exists(design_path)) stop(sprintf("Missing design object: %s", design_path), call. = FALSE)
  fit_paths <- c(fit_paths, fit_path, design_path)

  fit <- readRDS(fit_path)
  design <- readRDS(design_path)
  theta <- fit$draws$theta %||% fit$samp.theta %||% NULL
  if (is.null(theta)) stop(sprintf("Fit object does not contain theta draws: %s", fit_path), call. = FALSE)
  theta <- as.matrix(theta)
  storage.mode(theta) <- "double"
  beta_mean <- colMeans(theta[, design$beta_index, drop = FALSE], na.rm = TRUE)
  X_beta <- as.matrix(design$X_beta %||% design$X_base)
  storage.mode(X_beta) <- "double"

  base <- design$base_panel
  base$target_date <- as.Date(base$target_date)
  origin <- as.Date(design$latent_data$origin_date %||% max(base$target_date, na.rm = TRUE))
  cutoff_date <- cutoff_date %||% origin
  hist_idx <- which(base$target_date < origin & is.finite(base$y_transformed))
  if (!length(hist_idx)) stop(sprintf("No retrospective rows before %s for %s.", origin, fit_id), call. = FALSE)
  hist_idx <- tail(hist_idx[order(base$target_date[hist_idx])], history_n)
  qhat <- as.numeric(X_beta[hist_idx, , drop = FALSE] %*% beta_mean)

  if (is.null(reference_panel)) {
    reference_panel <- data.frame(
      target_date = base$target_date[hist_idx],
      y_reference = as.numeric(base$y_transformed[hist_idx]),
      g_retrospective = as.numeric(base$g_transformed[hist_idx]),
      stringsAsFactors = FALSE
    )
  }

  rows[[length(rows) + 1L]] <- data.frame(
    quantile_id = row$quantile_id[[1L]],
    quantile_level = row$quantile_level[[1L]],
    fit_id = fit_id,
    target_date = base$target_date[hist_idx],
    y_reference = as.numeric(base$y_transformed[hist_idx]),
    qhat = qhat,
    cutoff_date = origin,
    stringsAsFactors = FALSE
  )
  rm(fit, design, theta, X_beta)
  gc()
}

history <- do.call(rbind, rows)
history <- history[order(history$target_date, history$quantile_level), , drop = FALSE]
mono <- app_synthesize_quantile_grid(data.frame(
  model_id = "qdesn_history",
  origin_date = as.Date(cutoff_date),
  target_date = history$target_date,
  horizon = as.integer(history$target_date - min(history$target_date) + 1L),
  quantile_level = history$quantile_level,
  qhat = history$qhat,
  y_reference = history$y_reference,
  stringsAsFactors = FALSE
))
history$qhat_monotone <- mono$qhat_monotone
history$monotone_adjustment <- history$qhat_monotone - history$qhat

spread_rows <- lapply(split(history, history$target_date), function(block) {
  block <- block[order(block$quantile_level), , drop = FALSE]
  data.frame(
    target_date = block$target_date[[1L]],
    y_reference = block$y_reference[[1L]],
    width_90_independent = block$qhat[block$quantile_level == 0.95] - block$qhat[block$quantile_level == 0.05],
    width_65_independent = block$qhat[block$quantile_level == 0.80] - block$qhat[block$quantile_level == 0.15],
    width_30_independent = block$qhat[block$quantile_level == 0.65] - block$qhat[block$quantile_level == 0.35],
    width_90_monotone = block$qhat_monotone[block$quantile_level == 0.95] - block$qhat_monotone[block$quantile_level == 0.05],
    width_65_monotone = block$qhat_monotone[block$quantile_level == 0.80] - block$qhat_monotone[block$quantile_level == 0.15],
    width_30_monotone = block$qhat_monotone[block$quantile_level == 0.65] - block$qhat_monotone[block$quantile_level == 0.35],
    n_crossing_pairs = sum(diff(block$qhat) < -1.0e-10, na.rm = TRUE),
    n_zero_gaps_monotone = sum(abs(diff(block$qhat_monotone)) < 1.0e-8, na.rm = TRUE),
    n_distinct_monotone = length(unique(round(block$qhat_monotone, 8))),
    stringsAsFactors = FALSE
  )
})
spread <- do.call(rbind, spread_rows)
spread <- spread[order(spread$target_date), , drop = FALSE]

app_write_csv(history, file.path(run_dirs$tables, "pre_cutoff_quantile_history.csv"))
app_write_csv(spread, file.path(run_dirs$tables, "pre_cutoff_quantile_spread_by_date.csv"))
app_write_csv(history, file.path(run_dirs$tables, sprintf("pre_cutoff_quantile_history_last%d.csv", history_n)))
app_write_csv(spread, file.path(run_dirs$tables, sprintf("pre_cutoff_quantile_spread_by_date_last%d.csv", history_n)))

out_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
fig_dir <- file.path(out_dir, "figures")
app_ensure_dir(fig_dir)

plot_pdf <- function(name, width = 9, height = 5.2, expr) {
  path <- file.path(fig_dir, name)
  grDevices::pdf(path, width = width, height = height)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  path
}

plot_history <- function(value_col, title, ylab = "Transformed streamflow") {
  q_levels <- sort(unique(history$quantile_level))
  cols <- grDevices::hcl.colors(length(q_levels), "Dark 3")
  names(cols) <- as.character(q_levels)
  yr <- range(c(history[[value_col]], history$y_reference), na.rm = TRUE)
  plot(
    range(history$target_date),
    yr + c(-0.05, 0.05) * diff(yr),
    type = "n",
    xlab = "Target date",
    ylab = ylab,
    main = title
  )
  grid(col = "gray90")
  for (q in q_levels) {
    block <- history[abs(history$quantile_level - q) < 1.0e-12, , drop = FALSE]
    lines(
      block$target_date,
      block[[value_col]],
      col = cols[[as.character(q)]],
      lwd = if (abs(q - 0.5) < 1.0e-12) 2.1 else 1.25
    )
  }
  lines(reference_panel$target_date, reference_panel$y_reference, col = "#111111", lwd = 1.4)
  legend(
    "topleft",
    legend = c(paste0("p=", q_levels), "USGS"),
    col = c(cols, "#111111"),
    lty = 1,
    lwd = c(rep(1.4, length(q_levels)), 1.8),
    bty = "n",
    cex = 0.76,
    ncol = 2
  )
}

figures <- c(
  independent_history = plot_pdf(sprintf("glofas_pre_cutoff_last%d_qdesn_quantile_history_independent.pdf", history_n), expr = {
    plot_history(
      "qhat",
      sprintf("Q-DESN fitted quantile dynamics, last %d dates before cutoff", history_n)
    )
  }),
  monotone_history = plot_pdf(sprintf("glofas_pre_cutoff_last%d_qdesn_quantile_history_monotone.pdf", history_n), expr = {
    plot_history(
      "qhat_monotone",
      sprintf("Monotone-projected Q-DESN fitted quantile dynamics, last %d dates before cutoff", history_n)
    )
  }),
  spread_history = plot_pdf(sprintf("glofas_pre_cutoff_last%d_quantile_spread_diagnostics.pdf", history_n), 9, 5.4, {
    yr <- range(c(spread$width_90_independent, spread$width_90_monotone, spread$width_65_monotone, spread$width_30_monotone), na.rm = TRUE)
    plot(
      range(spread$target_date),
      yr + c(-0.05, 0.05) * diff(yr),
      type = "n",
      xlab = "Target date",
      ylab = "Quantile width",
      main = "Pre-cutoff quantile spread diagnostics"
    )
    grid(col = "gray90")
    lines(spread$target_date, spread$width_90_independent, col = "#b91c1c", lwd = 1.1, lty = 2)
    lines(spread$target_date, spread$width_90_monotone, col = "#2563eb", lwd = 1.6)
    lines(spread$target_date, spread$width_65_monotone, col = "#059669", lwd = 1.4)
    lines(spread$target_date, spread$width_30_monotone, col = "#7c3aed", lwd = 1.4)
    legend(
      "topleft",
      legend = c("90% independent", "90% monotone", "65% monotone", "30% monotone"),
      col = c("#b91c1c", "#2563eb", "#059669", "#7c3aed"),
      lty = c(2, 1, 1, 1),
      lwd = c(1.1, 1.6, 1.4, 1.4),
      bty = "n",
      cex = 0.78
    )
  })
)

prov <- app_write_output_provenance(
  outputs = figures,
  run_dirs = run_dirs,
  cfg = cfg,
  path = file.path(run_dirs$tables, "pre_cutoff_history_figure_provenance.csv")
)
app_write_csv(prov, file.path(out_dir, "pre_cutoff_history_figure_provenance.csv"))

readiness <- data.frame(
  category = c("sources", "history", "figures"),
  check = c("all_fit_and_design_objects_exist", "history_rows_written", "figures_exist"),
  passed = c(
    all(file.exists(fit_paths)),
    nrow(history) == nrow(manifest) * min(history_n, length(unique(history$target_date))),
    all(file.exists(unname(figures)))
  ),
  detail = c(
    paste(manifest$quantile_id, basename(fit_paths[seq(1L, length(fit_paths), by = 2L)]), sep = "=", collapse = "; "),
    sprintf("dates=%d; rows=%d; cutoff=%s", length(unique(history$target_date)), nrow(history), cutoff_date),
    paste(unname(figures), collapse = "; ")
  ),
  stringsAsFactors = FALSE
)
app_write_csv(readiness, file.path(run_dirs$tables, "pre_cutoff_history_readiness_report.csv"))
writeLines(
  c(
    sprintf("run_id: %s", basename(run_dirs$run_dir)),
    sprintf("history_n: %d", history_n),
    sprintf("cutoff_date_excluded: %s", cutoff_date),
    sprintf("all_checks_passed: %s", all(readiness$passed)),
    sprintf("generated_outputs: %s", out_dir)
  ),
  file.path(run_dirs$tables, "pre_cutoff_history_readiness_summary.txt")
)

app_stage_done("13_make_glofas_pre_cutoff_quantile_history", run_dirs)
cat(run_dirs$run_dir, "\n")
