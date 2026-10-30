#!/usr/bin/env Rscript
options(stringsAsFactors = FALSE, digits = 17)
Sys.setenv(OMP_NUM_THREADS = 1, OPENBLAS_NUM_THREADS = 1, MKL_NUM_THREADS = 1)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
root <- normalizePath(file.path(dirname(script), ".."))
setwd(root)
source("scripts/qdesn_evaluation_figure_style.R")
render_forecast_figures <- "--render-forecast-figures" %in% commandArgs(TRUE)
sha <- function(path) unname(tools::sha256sum(path)[[1L]])
pdf_creation_entry <- function(bytes) {
  marker <- charToRaw("/CreationDate (D:")
  positions <- which(bytes == marker[1L])
  positions <- positions[vapply(positions, function(at) {
    end <- at + length(marker) - 1L
    end <= length(bytes) && identical(bytes[at:end], marker)
  }, logical(1L))]
  stopifnot(length(positions) == 1L)
  closing <- which(seq_along(bytes) > positions[1L] & bytes == charToRaw(")")[1L])[1L]
  seq.int(positions[1L], closing)
}
set_pdf_creation_date <- function(path, date_entry) {
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  index <- pdf_creation_entry(bytes)
  stopifnot(length(index) == length(date_entry))
  bytes[index] <- date_entry
  connection <- file(path, "wb"); writeBin(bytes, connection); close(connection)
}
write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, na = "")
policy <- jsonlite::read_json("application/config/independent_forecast_300_500_v1.json", simplifyVector = TRUE)
stopifnot(policy$primary_cutoff == 300L, policy$sensitivity_cutoff == 500L,
  policy$deprecated_status == "DEPRECATED_FOR_REPORTING", !policy$allow_refit,
  !policy$allow_forecast_resimulation, policy$retrospective_scope_change)
data <- read.csv("tables/independent_forecast_300_500_v1.csv")
fit <- read.csv("tables/independent_fit_preserved_300_500_v1.csv")
stopifnot(nrow(data) == 144L, nrow(fit) == 72L, all(data$cutoff %in% c(300L, 500L)),
  all(data$inference == "mcmc"), all(data$n_chains == 3L), all(fit$metric_role == "fit_rmse"))
keys <- function(x, window = TRUE) do.call(paste, c(x[c("inference", "family", "tau", "model_variant", "metric_role", if(window) "cutoff")], sep="|"))
stopifnot(!anyDuplicated(keys(data)))
baseline <- read.csv("tables/qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv")
old_fit <- baseline[baseline$metric_role == "fit_rmse", ]
old_fit <- old_fit[match(keys(fit, FALSE), keys(old_fit, FALSE)), ]
numeric_fields <- c("posterior_mean", "cri_lower", "posterior_median", "cri_upper", "n_draws", "n_chains")
stopifnot(identical(unname(as.matrix(fit[numeric_fields])), unname(as.matrix(old_fit[numeric_fields]))))
fit_assets <- c("figures/independent_simulation/qdesn_pro_review_mcmc_fit_rmse.pdf",
  "figures/independent_simulation/qdesn_pro_review_vb_fit_rmse.pdf")
fit_hashes <- vapply(fit_assets, sha, character(1))
outputs <- character()
save_text <- function(lines, path) {
  while (length(lines) && identical(tail(lines, 1L), "")) lines <- head(lines, -1L)
  writeLines(lines, path, useBytes = TRUE); outputs <<- c(outputs, path)
}
theme <- ggplot2::theme(text = ggplot2::element_text(size = 10.4),
  strip.text = ggplot2::element_text(size = 10.4, face = "bold", lineheight = .98),
  axis.text.x = ggplot2::element_text(size = 10.4), axis.text.y = ggplot2::element_text(size = 10.4),
  axis.title.x = ggplot2::element_text(size = 10.4),
  panel.spacing = grid::unit(1, "lines"), plot.margin = ggplot2::margin(7, 16, 7, 7))
plots <- list()
frozen_forecast_pdfs <- c(
  "independent_train500_eval300_mcmc_forecast_mae_v1.pdf" = "44f0e8ba6aea98a6ae47f1625eaebf0011d6e506a162064ef67fbd96afd41399",
  "independent_train500_eval300_mcmc_forecast_check_v1.pdf" = "4b91d61a9ff0991c58d6714b8f89b2c39e68bd46c4643f4e5f421c5c48d157ba",
  "independent_train500_eval500_mcmc_forecast_mae_v1.pdf" = "3519c01b61a6e2273a10dec7b92d0fe3fccc93bf01cd6d4bea9d39bcd2d921a8",
  "independent_train500_eval500_mcmc_forecast_check_v1.pdf" = "a7b60666a23d8e992d79aa877852a8b10202ec991c0d3b20cd22ebb5527e97a5"
)
for (n in c(300L, 500L)) for (metric in c("forecast_mae", "forecast_check")) {
  d <- data[data$cutoff == n, ]
  p <- qdesn_independent_interval_plot(d, "mcmc", metric) + theme
  xscale <- p$scales$get_scales("x")
  xscale$labels <- function(x) formatC(x, format = "fg", digits = 3)
  b <- data[data$metric_role == metric, ]
  b$panel_key <- factor(paste(b$family, sprintf("%.2f", b$tau), sep = "|"), levels = levels(p$data$panel_key))
  limits <- rbind(data.frame(panel_key = b$panel_key, x = b$cri_lower),
    data.frame(panel_key = b$panel_key, x = b$cri_upper),
    data.frame(panel_key = b$panel_key, x = b$plot_reference_value))
  p <- p + ggplot2::geom_blank(data = limits, ggplot2::aes(x = x), inherit.aes = FALSE)
  path <- sprintf("figures/independent_simulation/independent_train500_eval%d_mcmc_%s_v1.pdf", n, metric)
  stopifnot(file.exists(path), sha(path) == frozen_forecast_pdfs[[basename(path)]])
  if (render_forecast_figures) {
    original <- readBin(path, "raw", n = file.info(path)$size)
    candidate <- tempfile("ind-reproduction-", tmpdir = "local_trackers", fileext = ".pdf")
    qdesn_save_vector_pdf(candidate, p, 7.2, 6.6)
    set_pdf_creation_date(candidate, original[pdf_creation_entry(original)])
    stopifnot(sha(candidate) == frozen_forecast_pdfs[[basename(path)]])
    unlink(candidate)
  }
  outputs <- c(outputs, path); plots[[paste(n, metric)]] <- p
}
fmt <- function(x) formatC(x, format = "fg", digits = 4, flag = "#")
cell <- function(d, best) {
  center <- fmt(d$posterior_mean)
  if (d$posterior_mean == best) center <- paste0("\\textbf{", center, "}")
  paste0("\\shortstack{", center, "\\\\{\\scriptsize [", fmt(d$cri_lower), ", ", fmt(d$cri_upper), "]}}")
}
model_label <- c(dqlm = "DQLM", exdqlm = "exDQLM", qdesn_al_rhs_ns = "Q--DESN AL--RHS", qdesn_exal_rhs_ns = "Q--DESN exAL--RHS")
for (n in c(300L, 500L)) for (family in names(qdesn_family_labels)) {
  metrics <- if (n == 300L) c("fit_rmse", "forecast_mae", "forecast_check") else c("forecast_mae", "forecast_check")
  d <- data[data$cutoff == n & data$family == family, ]
  lines <- c("\\begin{table}[!htbp]", "\\centering", "\\scriptsize", "\\setstretch{1}",
    "\\setlength{\\tabcolsep}{4pt}", paste0("\\begin{tabular}{@{}cl", paste(rep("c", length(metrics)), collapse = ""), "@{}}"),
    "\\toprule", paste0("Target & Model & ", if(n == 300L) "Fit RMSE & " else "",
      "Forecast MAE & Forecast check loss \\\\"), "\\midrule")
  for (tau in c(.05, .25, .5)) for (j in seq_along(model_label)) {
    model <- names(model_label)[j]
    cells <- vapply(metrics, function(metric) {
      block <- if (metric == "fit_rmse") fit[fit$inference == "mcmc" & fit$family == family & fit$tau == tau, ] else
        d[d$tau == tau & d$metric_role == metric, ]
      stopifnot(nrow(block) == 4L)
      cell(block[block$model_variant == model, ], min(block$posterior_mean))
    }, character(1))
    lines <- c(lines, paste0(if(j == 1L) sprintf("$p=%.2f$", tau) else "", " & ", model_label[j], " & ",
      paste(cells, collapse = " & "), " \\\\"))
    if (j == 4L && tau != .5) lines <- c(lines, "\\addlinespace[2pt]")
  }
  caption <- paste0(if (n == 300L) "Primary" else "Sensitivity", " MCMC metric summaries for the ",
    qdesn_family_labels[[family]], " family. Forecast criteria use the first ", n,
    " scored targets; entries are posterior means with equal-tailed 95\\% intervals. ",
    if(n == 300L) "Fit RMSE uses the 500-observation fitting sample. " else "The models and posterior draws are the same as in the primary comparison. ",
    "Lower is better; boldface marks the lowest unrounded mean within each target level and criterion. ",
    "Intervals condition on the selected specification and data.")
  lines <- c(lines, "\\bottomrule", "\\end{tabular}", paste0("\\caption{", caption, "}"),
    sprintf("\\label{tab:independent-eval%d-mcmc-%s}", n, family), "\\end{table}")
  save_text(lines, sprintf("tables/independent_train500_eval%d_mcmc_%s_v1.tex", n, family))
}
for (n in c(300L, 500L)) save_text(vapply(names(qdesn_family_labels), function(family)
  sprintf("\\input{tables/independent_train500_eval%d_mcmc_%s_v1.tex}", n, family), character(1)),
  sprintf("tables/independent_train500_eval%d_mcmc_tables_v1.tex", n))
vb <- fit[fit$inference == "vb", ]
lines <- c("\\begin{table}[!htbp]", "\\centering", "\\scriptsize", "\\setstretch{1}",
  "\\begin{tabular}{@{}llccc@{}}", "\\toprule", "Family & Model & $p=0.05$ & $p=0.25$ & $p=0.50$ \\\\", "\\midrule")
for (f in names(qdesn_family_labels)) for (j in seq_along(model_label)) {
  cells <- vapply(c(.05, .25, .5), function(p) {
    b <- vb[vb$family == f & vb$tau == p, ]; cell(b[b$model_variant == names(model_label)[j], ], min(b$posterior_mean))
  }, character(1))
  lines <- c(lines, paste0(if(j == 1L) qdesn_family_labels[f] else "", " & ", model_label[j], " & ", paste(cells, collapse=" & "), " \\\\"))
  if(j == 4L && f != "gausmix") lines <- c(lines, "\\addlinespace[2pt]")
}
save_text(c(lines, "\\bottomrule", "\\end{tabular}",
  "\\caption{VB fitting-sample quantile-path RMSE for 500 observations. Entries are variational means and equal-tailed 95\\% intervals.}",
  "\\label{tab:independent-vb-fit-preserved}", "\\end{table}"), "tables/independent_vb_fit_preserved_v1.tex")
for (n in c(300L, 500L)) {
  lines <- character()
  for (metric in c("forecast_mae", "forecast_check")) {
    name <- if(metric == "forecast_mae") "quantile-path MAE" else "check loss"
    label <- if(n == 300L) {
      if(metric == "forecast_mae") "fig:simulation-500obs-mcmc-forecast-mae-intervals" else "fig:simulation-500obs-mcmc-forecast-check-loss-intervals"
    } else paste0("fig:independent-eval500-", metric)
    caption <- paste0("MCMC forecast ", name, " over the first ", n, " evaluation targets (", if(n == 300L) "10" else "17",
      " origins). Points and equal-tailed 95\\% intervals summarize the draw-wise criterion averaged over scored pairs; lower is better. ",
      "Navy circles identify \\(\\AL\\) models and muted-brick triangles \\(\\exAL\\) models; filled symbols denote Q--DESN and open symbols their dynamic linear comparators. ",
      "Panels A--I identify the observation-error family and probability level. ",
      if(metric == "forecast_mae") "The dashed line marks exact recovery of the state-conditional quantile path. " else
        "The dashed line marks population expected check loss at the true conditional quantile, not a finite-sample lower bound. ",
      if(n == 300L) "Corresponding panels in the 500-target sensitivity figure use the same horizontal limits. " else "The last origin contributes 20 leads; earlier origins contribute 30. ",
      "The supplement documents criterion-specific selection and model-specific forecast-draw dependence.")
    block <- c("\\begin{figure}[!htbp]", "\\centering",
      sprintf("\\includegraphics[width=0.98\\textwidth]{figures/independent_simulation/independent_train500_eval%d_mcmc_%s_v1.pdf}", n, metric),
      paste0("\\caption{", caption, "}"),
      sprintf("\\figalt{Nine panels compare four models using mean forecast %s and 95 percent intervals over %d scored targets.}", name, n),
      paste0("\\label{", label, "}"), "\\end{figure}", "")
    if (n == 300L && metric == "forecast_mae") {
      save_text(block, "tables/independent_train500_eval300_mcmc_mae_figure_v1.tex")
    } else {
      lines <- c(lines, block)
    }
  }
  save_text(lines, sprintf("tables/independent_train500_eval%d_mcmc_figures_v1.tex", n))
}
comparisons <- do.call(rbind, lapply(split(data, interaction(data$family, data$tau, data$metric_role, data$cutoff)), function(d) {
  best <- min(d$posterior_mean[d$model_variant %in% c("dqlm", "exdqlm")])
  data.frame(cutoff = d$cutoff, metric = d$metric_role, model = d$model_variant, beats_best_dynamic = d$posterior_mean < best)
}))
write_csv(comparisons, "tables/independent_forecast_300_500_comparisons_v1.csv")
outputs <- c(outputs, "tables/independent_forecast_300_500_comparisons_v1.csv")
primary_check <- data[data$cutoff == 300L & data$metric_role == "forecast_check", ]
for (family in names(qdesn_family_labels)) for (tau in c(.25, .5)) {
  block <- primary_check[primary_check$family == family & primary_check$tau == tau, ]
  stopifnot(max(block$posterior_mean[grepl("^qdesn", block$model_variant)]) <
    min(block$posterior_mean[!grepl("^qdesn", block$model_variant)]))
}
save_text(c("At the lower quartile and median, both Q--DESN likelihoods have lower posterior mean check loss than both dynamic linear comparators across all three observation-error families.",
  "At the 5\\% level, exAL Q--DESN has the lowest mean for Gaussian and Laplace errors, whereas DQLM has the lowest mean for Gaussian-mixture errors. AL Q--DESN has higher mean loss than both dynamic comparators in the Gaussian and Laplace lower-tail cases."),
  "tables/independent_eval300_results_v1.tex")
calibration <- read.csv("tables/independent_forecast_calibration_v1.csv")
calibration_receipt <- jsonlite::read_json("tables/independent_forecast_calibration_manifest_v1.json", simplifyVector = TRUE)
stopifnot(nrow(calibration) == 72L, all(calibration$point_summary == "posterior_median"),
  all(calibration$n_chains == 3L), all(calibration$cutoff %in% c(300L, 500L)),
  all(abs(calibration$empirical_frequency - calibration$n_hits / calibration$n_targets) < 1e-12),
  calibration_receipt$point_summary == "posterior_median",
  calibration_receipt$fits_launched == 0L, calibration_receipt$forecasts_launched == 0L)
for (path in names(calibration_receipt$outputs))
  stopifnot(sha(file.path("tables", path)) == calibration_receipt$outputs[[path]])
calibration$family_label <- factor(calibration$family, levels = names(qdesn_family_labels), labels = qdesn_family_labels)
calibration$window <- factor(calibration$cutoff, levels = c(300L, 500L),
  labels = c("Primary: 300 targets", "Sensitivity: 500 targets"))
calibration$model <- factor(calibration$model_variant, levels = qdesn_independent_model_order)
colours <- setNames(unname(qdesn_figure_palette[qdesn_independent_model_family]), qdesn_independent_model_order)
limit <- min(1, max(.55, ceiling((max(calibration$empirical_frequency) + .025) * 10) / 10))
calibration_plot <- ggplot2::ggplot(calibration,
    ggplot2::aes(x = tau, y = empirical_frequency, colour = model, shape = model)) +
  ggplot2::geom_abline(intercept = 0, slope = 1, colour = "#62676B", linewidth = .4, linetype = "dashed") +
  ggplot2::geom_point(size = 2.4, stroke = .65) +
  ggplot2::facet_grid(window ~ family_label) +
  ggplot2::scale_colour_manual(values = colours, labels = qdesn_independent_model_labels, name = NULL) +
  ggplot2::scale_shape_manual(values = qdesn_independent_model_shape, labels = qdesn_independent_model_labels, name = NULL) +
  ggplot2::scale_x_continuous(breaks = c(.05, .25, .5), labels = c("0.05", "0.25", "0.50"), limits = c(0, limit)) +
  ggplot2::scale_y_continuous(limits = c(0, limit), labels = function(x) formatC(x, format = "f", digits = 2)) +
  ggplot2::labs(x = "Nominal quantile level", y = "Empirical frequency") +
  ggplot2::theme_bw(base_size = 10.4, base_family = "sans") +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "#F0F1F1", colour = "#8E9294", linewidth = .3),
    strip.text = ggplot2::element_text(size = 10.4, face = "bold"),
    axis.text = ggplot2::element_text(size = 10.4, colour = "#242424"),
    axis.title = ggplot2::element_text(size = 10.4),
    legend.position = "bottom", legend.text = ggplot2::element_text(size = 10.4),
    panel.spacing = grid::unit(.8, "lines"), plot.margin = ggplot2::margin(7, 9, 7, 7)) +
  ggplot2::guides(colour = ggplot2::guide_legend(nrow = 2), shape = ggplot2::guide_legend(nrow = 2))
calibration_pdf <- "figures/independent_simulation/independent_forecast_calibration_v1.pdf"
qdesn_save_vector_pdf(calibration_pdf, calibration_plot, 7.2, 5.5)
# Preserve byte offsets while fixing only Cairo's creation-date metadata.
set_pdf_creation_date(calibration_pdf, charToRaw("/CreationDate (D:20000101000000+00'00)"))
outputs <- c(outputs, calibration_pdf)
save_text(c("\\begin{figure}[!htbp]", "\\centering",
  paste0("\\includegraphics[width=0.98\\textwidth]{", calibration_pdf, "}"),
  "\\caption{Empirical quantile frequencies over the 300-target primary period and its 500-target extension. Each model uses the same specification as in the check-loss comparison. At each target, the quantile forecast is the posterior median, pooling the three chains. Points give the fractions of responses at or below these forecasts; the dashed diagonal marks the nominal probability. Colours and symbols follow the forecast-score figures. Each probability level uses its corresponding quantile-centred response series. No sampling confidence bands are shown.}",
  "\\figalt{Six panels compare empirical response frequencies below posterior-median quantile forecasts with the nominal levels 0.05, 0.25 and 0.50, for four models, three error families and two evaluation periods.}",
  "\\label{fig:supp-independent-quantile-calibration}", "\\end{figure}"),
  "tables/independent_forecast_calibration_figure_v1.tex")
lines <- c("\\begin{table}[!htbp]", "\\centering", "\\footnotesize", "\\setstretch{1}",
  "\\setlength{\\tabcolsep}{3.5pt}", "\\begin{tabular}{@{}llcrrrr@{}}", "\\toprule",
  "Targets & Error family & $p$ & DQLM & exDQLM & \\shortstack{Q--DESN\\\\AL} & \\shortstack{Q--DESN\\\\exAL} \\\\",
  "\\midrule")
for (n in c(300L, 500L)) for (family in names(qdesn_family_labels)) for (tau in c(.05, .25, .5)) {
  block <- calibration[calibration$cutoff == n & calibration$family == family & calibration$tau == tau, ]
  block <- block[match(names(model_label), block$model_variant), ]
  stopifnot(nrow(block) == 4L, !anyNA(block$model_variant))
  cells <- sprintf("%.1f (%d)", 100 * block$empirical_frequency, block$n_hits)
  lines <- c(lines, paste0(if(family == "normal" && tau == .05) n else "", " & ",
    if(tau == .05) qdesn_family_labels[[family]] else "", " & ", sprintf("%.2f", tau), " & ",
    paste(cells, collapse = " & "), " \\\\"))
  if(tau == .5 && !(n == 500L && family == "gausmix")) lines <- c(lines, "\\addlinespace[3pt]")
}
save_text(c(lines, "\\bottomrule", "\\end{tabular}",
  "\\caption{Empirical quantile frequencies in percent, followed by the number of responses at or below the forecast in parentheses. The target count is the denominator. Forecasts are posterior-median quantile locations from the existing check-loss specifications; no model is selected using these frequencies.}",
  "\\label{tab:supp-independent-quantile-calibration}", "\\end{table}"),
  "tables/independent_forecast_calibration_table_v1.tex")
review <- "local_trackers/independent_forecast_300_500_v1/independent_forecast_300_500_review.pdf"
dir.create(dirname(review), recursive = TRUE, showWarnings = FALSE)
grDevices::cairo_pdf(review, width = 8.4, height = 7.4, onefile = TRUE)
for (n in c(300L, 500L)) for (metric in c("forecast_mae", "forecast_check"))
  print(plots[[paste(n, metric)]] + ggplot2::labs(title = paste(if(n == 300L) "Primary:" else "Sensitivity:", n, "scored targets"),
    subtitle = "Posterior means and equal-tailed 95% metric intervals; unchanged selected specifications"))
grDevices::dev.off()
stopifnot(identical(fit_hashes, vapply(fit_assets, sha, character(1))))
sources <- c("application/config/independent_forecast_300_500_v1.json", "tables/independent_forecast_300_500_v1.csv",
  "tables/independent_fit_preserved_300_500_v1.csv", "tables/independent_forecast_300_500_vb_coverage.csv",
  "scripts/qdesn_evaluation_figure_style.R", "scripts/build_independent_forecast_300_500_v1.R",
  "main.tex", "qdesn-supplement.tex", "overleaf/article_files.txt",
  "tables/independent_forecast_dependence_v1.tex",
  "docs/implementation_notes/independent_forecast_300_500_reporting_20261015.md", fit_assets)
sources <- c(sources, "application/config/independent_forecast_calibration_v1.json",
  "docs/implementation_notes/statistical_language_reader_revision_20261019.md",
  "docs/implementation_notes/independent_forecast_focus_and_calibration_20261015.md",
  "tables/independent_forecast_calibration_v1.csv", "tables/independent_forecast_calibration_sources_v1.csv",
  "tables/independent_forecast_calibration_manifest_v1.json")
manifest <- list(schema = "independent-forecast-300-500-article-v1", authority_id = policy$authority_id,
  primary_cutoff = 300L, sensitivity_cutoff = 500L, deprecated_reporting_cutoff = 1000L,
  retrospective_scope_change = TRUE, fit_unchanged = TRUE, vb_forecasts = "OMITTED_NO_AUTHENTIC_PREFIX_DRAWS",
  fits_launched = 0L, forecasts_launched = 0L,
  primary_plot_placement = list(forecast_check = "main", forecast_mae = "supplement"),
  sources = as.list(setNames(vapply(sources, sha, character(1)), sources)),
  outputs = as.list(setNames(vapply(outputs, sha, character(1)), outputs)))
jsonlite::write_json(manifest, "tables/independent_forecast_300_500_article_manifest_v1.json", auto_unbox = TRUE, pretty = TRUE)
cat("IND-only publication build complete; review PDF:", normalizePath(review), "\n")
