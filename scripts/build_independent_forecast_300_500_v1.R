#!/usr/bin/env Rscript
options(stringsAsFactors = FALSE, digits = 17)
Sys.setenv(OMP_NUM_THREADS = 1, OPENBLAS_NUM_THREADS = 1, MKL_NUM_THREADS = 1)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
root <- normalizePath(file.path(dirname(script), ".."))
setwd(root)
source("scripts/qdesn_evaluation_figure_style.R")
sha <- function(path) unname(tools::sha256sum(path)[[1L]])
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
  qdesn_save_vector_pdf(path, p, 7.2, 6.6)
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
    if(n == 300L) "Fit RMSE retains the original 500-observation fitting sample. " else "The fitted sources are unchanged from the primary comparison. ",
    "Lower is better; boldface marks the lowest unrounded mean within each target level and criterion. ",
    "Intervals condition on the selected specification and data; diagnostic grades are retained in the reproducibility record.")
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
  "\\caption{Unchanged VB fitting-sample quantile-path RMSE. Entries are variational means and equal-tailed 95\\% intervals on the original 500 fitted observations. Forecast results are not inferred from these fit summaries.}",
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
      if(n == 300L) "Panel scales match the 500-target sensitivity figures. " else "The last origin contributes 20 leads; earlier origins contribute 30. ",
      "The supplement documents criterion-specific selection and model-specific forecast-draw dependence.")
    lines <- c(lines, "\\begin{figure}[!htbp]", "\\centering",
      sprintf("\\includegraphics[width=0.98\\textwidth]{figures/independent_simulation/independent_train500_eval%d_mcmc_%s_v1.pdf}", n, metric),
      paste0("\\caption{", caption, "}"),
      sprintf("\\figalt{Nine panels compare four models using mean forecast %s and 95 percent intervals over %d scored targets.}", name, n),
      paste0("\\label{", label, "}"), "\\end{figure}", "")
  }
  save_text(lines, sprintf("tables/independent_train500_eval%d_mcmc_figures_v1.tex", n))
}
comparisons <- do.call(rbind, lapply(split(data, interaction(data$family, data$tau, data$metric_role, data$cutoff)), function(d) {
  best <- min(d$posterior_mean[d$model_variant %in% c("dqlm", "exdqlm")])
  data.frame(cutoff = d$cutoff, metric = d$metric_role, model = d$model_variant, beats_best_dynamic = d$posterior_mean < best)
}))
write_csv(comparisons, "tables/independent_forecast_300_500_comparisons_v1.csv")
outputs <- c(outputs, "tables/independent_forecast_300_500_comparisons_v1.csv")
primary <- comparisons[comparisons$cutoff == 300L, ]
count <- function(model, metric) sum(primary$beats_best_dynamic[primary$model == model & primary$metric == metric])
save_text(c(paste0("Over the primary 300-target evaluation, exAL Q--DESN has a lower posterior mean than both dynamic linear comparators in ",
  count("qdesn_exal_rhs_ns", "forecast_mae"), " of nine cases for forecast MAE and ", count("qdesn_exal_rhs_ns", "forecast_check"),
  " for check loss. The corresponding counts for AL Q--DESN are ", count("qdesn_al_rhs_ns", "forecast_mae"), " and ", count("qdesn_al_rhs_ns", "forecast_check"),
  ". These descriptive rankings condition on criterion-specific specifications and do not measure selection uncertainty. ",
  "The wider Q--DESN forecast-MAE intervals remain visible; a shorter evaluation period is not a change to the fitted model.")),
  "tables/independent_eval300_results_v1.tex")
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
manifest <- list(schema = "independent-forecast-300-500-article-v1", authority_id = policy$authority_id,
  primary_cutoff = 300L, sensitivity_cutoff = 500L, deprecated_reporting_cutoff = 1000L,
  retrospective_scope_change = TRUE, fit_unchanged = TRUE, vb_forecasts = "OMITTED_NO_AUTHENTIC_PREFIX_DRAWS",
  fits_launched = 0L, forecasts_launched = 0L,
  sources = as.list(setNames(vapply(sources, sha, character(1)), sources)),
  outputs = as.list(setNames(vapply(outputs, sha, character(1)), outputs)))
jsonlite::write_json(manifest, "tables/independent_forecast_300_500_article_manifest_v1.json", auto_unbox = TRUE, pretty = TRUE)
cat("IND-only publication build complete; review PDF:", normalizePath(review), "\n")
