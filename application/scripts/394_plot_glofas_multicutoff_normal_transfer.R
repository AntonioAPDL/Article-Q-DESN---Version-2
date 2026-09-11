#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(ggplot2))

args <- commandArgs(trailingOnly = TRUE)
value_after <- function(flag, default = "") {
  idx <- match(flag, args)
  if (is.na(idx) || idx == length(args)) default else args[[idx + 1L]]
}
runtime_arg <- value_after("--runtime_root")
if (!nzchar(runtime_arg)) stop("--runtime_root is required.", call. = FALSE)
runtime_root <- normalizePath(runtime_arg, mustWork = TRUE)
run_label <- basename(runtime_root)
cutoff_arg <- value_after("--cutoff_date")
cutoff_path <- file.path(runtime_root, "configs", "cutoff.csv")
if (nzchar(cutoff_arg)) {
  cutoff <- as.Date(cutoff_arg)
  if (is.na(cutoff)) stop("--cutoff_date must use YYYY-MM-DD format.", call. = FALSE)
} else {
  if (!file.exists(cutoff_path)) {
    stop("configs/cutoff.csv is absent; provide --cutoff_date YYYY-MM-DD.", call. = FALSE)
  }
  cutoff_table <- read.csv(cutoff_path, stringsAsFactors = FALSE)
  if (nrow(cutoff_table) != 1L) stop("Expected one cutoff row.", call. = FALSE)
  cutoff <- as.Date(cutoff_table$origin_date[[1L]])
}
issued_end <- cutoff + 28L
history_start <- cutoff - 29L
tau_grid <- c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)

manifest <- read.csv(file.path(runtime_root, "configs", "part4_model_manifest.csv"), stringsAsFactors = FALSE)
normal_families <- c("normal_ridge_diagnostic", "normal_rhs_vb_diagnostic")
manifest <- manifest[manifest$part4_family %in% normal_families, , drop = FALSE]
if (nrow(manifest) != 2L || !identical(sort(manifest$part4_family), sort(normal_families))) {
  stop("Normal transfer plot requires one Ridge and one RHS/VB job.", call. = FALSE)
}
if (!all(file.exists(file.path(runtime_root, "status", paste0(manifest$run_id, ".completed"))))) {
  stop("Both Normal transfer jobs must be complete before plotting.", call. = FALSE)
}

design_path <- file.path(runtime_root, "objects", "part4_shared_design_truth_free.rds")
message("Reading the shared truth-free design and retaining the plotted window...")
design <- readRDS(design_path)
panel <- design$base_panel
panel$target_date <- as.Date(panel$target_date)
history_rows <- which(panel$target_date >= history_start & panel$target_date <= cutoff)
if (length(history_rows) != 30L) stop("Expected exactly 30 historical dates.", call. = FALSE)
history <- panel[history_rows, , drop = FALSE]
X_beta <- as.matrix(design$X_beta[history_rows, , drop = FALSE])
X_alpha <- as.matrix(design$X_alpha[history_rows, , drop = FALSE])
ensemble <- design$latent_data$g_ensemble
ensemble$target_date <- as.Date(ensemble$target_date)
ensemble <- ensemble[ensemble$target_date > cutoff & ensemble$target_date <= issued_end, , drop = FALSE]
if (length(unique(ensemble$member)) != 51L || length(unique(ensemble$target_date)) != 28L) {
  stop("Issued ensemble must contain 51 members for 28 dates.", call. = FALSE)
}
ensemble_mean <- aggregate(g_transformed ~ target_date, ensemble, mean)
rm(design)
invisible(gc())

path_for <- function(directory, stem, suffix) {
  file.path(runtime_root, directory, paste0(run_label, "_", stem, "_", suffix))
}
read_prediction <- function(stem) {
  out <- read.csv(gzfile(path_for("predictions", stem, "posterior_draws.csv.gz")), stringsAsFactors = FALSE)
  out$target_date <- as.Date(out$target_date)
  out
}
coefficient_fit <- function(stem) {
  coef <- read.csv(path_for("coefficients", stem, "coefficients.csv"), stringsAsFactors = FALSE)
  beta <- coef[startsWith(coef$coefficient, "beta__"), , drop = FALSE]
  alpha <- coef[startsWith(coef$coefficient, "alpha__"), , drop = FALSE]
  if (nrow(beta) != ncol(X_beta) || nrow(alpha) != ncol(X_alpha)) {
    stop("Coefficient/design dimension mismatch for ", stem, call. = FALSE)
  }
  list(
    usgs = as.numeric(X_beta %*% as.numeric(beta$mean)),
    discrepancy = as.numeric(X_alpha %*% as.numeric(alpha$mean))
  )
}
summarize_draws <- function(draws, column) {
  blocks <- split(as.numeric(draws[[column]]), draws$target_date)
  do.call(rbind, lapply(names(blocks), function(date) {
    values <- blocks[[date]]
    data.frame(
      target_date = as.Date(date), center = mean(values),
      lower = unname(quantile(values, 0.025, type = 8)),
      upper = unname(quantile(values, 0.975, type = 8)),
      stringsAsFactors = FALSE
    )
  }))
}
empirical_crps <- function(y, draws) {
  x <- sort(as.numeric(draws))
  n <- length(x)
  mean(abs(x - y)) - sum((2 * seq_len(n) - n - 1) * x) / n^2
}
normal_data <- function(stem, short_label) {
  fit <- coefficient_fit(stem)
  draws <- read_prediction(stem)
  if (nrow(draws) != 500L * 28L) stop("Unexpected posterior draw count for ", stem, call. = FALSE)
  latent <- split(as.numeric(draws$latent_y_draw), draws$target_date)
  truth <- vapply(split(as.numeric(draws$y_reference), draws$target_date), function(x) unique(x)[[1L]], numeric(1L))
  crps <- mean(vapply(seq_along(latent), function(i) empirical_crps(truth[[i]], latent[[i]]), numeric(1L)))
  q05 <- vapply(latent, quantile, numeric(1L), probs = 0.05, type = 8, names = FALSE)
  q95 <- vapply(latent, quantile, numeric(1L), probs = 0.95, type = 8, names = FALSE)
  coverage <- mean(truth >= q05 & truth <= q95)
  label <- sprintf("%s\nCRPS %.4f | 90%% cover %.1f%%", short_label, crps, 100 * coverage)
  list(
    label = label,
    historical = rbind(
      data.frame(model = label, target = "USGS latent path", target_date = history$target_date, value = fit$usgs),
      data.frame(model = label, target = "GloFAS - USGS discrepancy", target_date = history$target_date, value = fit$discrepancy)
    ),
    forecast = rbind(
      transform(summarize_draws(draws, "q_y_draw"), model = label, target = "USGS latent path"),
      transform(summarize_draws(draws, "d_g_draw"), model = label, target = "GloFAS - USGS discrepancy")
    ),
    score = data.frame(model = short_label, empirical_crps_log1p = crps, coverage90 = coverage)
  )
}

models <- list(
  normal_data("normal_ridge_diagnostic", "Normal Ridge"),
  normal_data("normal_rhs_vb_diagnostic", "Normal RHS/VB")
)
historical_fit <- do.call(rbind, lapply(models, `[[`, "historical"))
forecast_fit <- do.call(rbind, lapply(models, `[[`, "forecast"))
model_levels <- vapply(models, `[[`, character(1L), "label")
ridge_draws <- read_prediction("normal_ridge_diagnostic")
future_truth <- unique(ridge_draws[c("target_date", "y_reference", "raw_glofas_center")])
future_truth$usgs <- future_truth$y_reference
future_truth$discrepancy <- future_truth$raw_glofas_center - future_truth$y_reference
target_levels <- c("USGS latent path", "GloFAS - USGS discrepancy")

historical_context <- do.call(rbind, lapply(model_levels, function(model) rbind(
  data.frame(model = model, target = target_levels[[1L]], target_date = history$target_date, value = history$y_transformed, series = "Observed history"),
  data.frame(model = model, target = target_levels[[1L]], target_date = history$target_date, value = history$g_transformed, series = "GloFAS retrospective"),
  data.frame(model = model, target = target_levels[[2L]], target_date = history$target_date, value = history$g_transformed - history$y_transformed, series = "Observed history")
)))
future_context <- do.call(rbind, lapply(model_levels, function(model) rbind(
  data.frame(model = model, target = target_levels[[1L]], target_date = future_truth$target_date, value = future_truth$usgs, series = "Withheld truth (scoring only)"),
  data.frame(model = model, target = target_levels[[2L]], target_date = future_truth$target_date, value = future_truth$discrepancy, series = "Withheld truth (scoring only)")
)))
ensemble_context <- do.call(rbind, lapply(model_levels, function(model) transform(ensemble, model = model, target = target_levels[[1L]])))
ensemble_mean_context <- do.call(rbind, lapply(model_levels, function(model) transform(ensemble_mean, model = model, target = target_levels[[1L]])))

colors <- c(
  "Observed history" = "#181818", "Withheld truth (scoring only)" = "#7B2C83",
  "GloFAS retrospective" = "#00839B", "Issued GloFAS members (51)" = "#A8CCD2",
  "Issued GloFAS mean" = "#005D6A", "Model fit / latent path" = "#C44E24"
)
plot <- ggplot() +
  geom_ribbon(data = forecast_fit, aes(target_date, ymin = lower, ymax = upper, group = interaction(model, target), fill = "95% credible interval"), alpha = 0.18, color = NA) +
  geom_line(data = ensemble_context, aes(target_date, g_transformed, group = interaction(model, member), color = "Issued GloFAS members (51)"), linewidth = 0.23, alpha = 0.26) +
  geom_line(data = historical_context, aes(target_date, value, color = series, linetype = series), linewidth = 0.82) +
  geom_line(data = ensemble_mean_context, aes(target_date, g_transformed, color = "Issued GloFAS mean", linetype = "Issued GloFAS mean"), linewidth = 0.92) +
  geom_line(data = future_context, aes(target_date, value, color = series, linetype = series), linewidth = 0.92) +
  geom_line(data = historical_fit, aes(target_date, value, color = "Model fit / latent path"), linewidth = 1.0, linetype = "dashed") +
  geom_line(data = forecast_fit, aes(target_date, center, color = "Model fit / latent path"), linewidth = 1.1) +
  geom_vline(xintercept = cutoff, color = "#66727A", linetype = "dotted", linewidth = 0.55) +
  facet_grid(rows = vars(factor(target, levels = target_levels)), cols = vars(factor(model, levels = model_levels)), scales = "free_y") +
  scale_color_manual(values = colors, name = NULL) +
  scale_linetype_manual(values = c("Observed history" = "solid", "Withheld truth (scoring only)" = "longdash", "GloFAS retrospective" = "solid", "Issued GloFAS mean" = "solid"), name = NULL) +
  scale_fill_manual(values = c("95% credible interval" = "#D98B6A"), name = NULL) +
  scale_x_date(date_breaks = "14 days", date_labels = "%b %d", limits = c(history_start, issued_end), expand = expansion(mult = c(0.01, 0.02))) +
  labs(
    title = sprintf("GloFAS winner transfer at the %s cutoff", cutoff),
    subtitle = "Normal Ridge and Normal RHS/VB; historical fits and 28-day issued-window latent paths on the fitted log1p scale",
    x = "Date", y = NULL
  ) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE), linetype = "none", fill = guide_legend(order = 2)) +
  theme_minimal(base_size = 10.5) +
  theme(
    plot.title = element_text(face = "bold", size = 15, hjust = 0.5),
    plot.subtitle = element_text(size = 10, color = "#4A5560", hjust = 0.5),
    strip.text.x = element_text(face = "bold", size = 10.5, lineheight = 1.1),
    strip.text.y = element_text(face = "bold", size = 10),
    strip.background = element_rect(fill = "#EEF2F4", color = "#CBD4D9", linewidth = 0.4),
    panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(color = "#D8E0E4", linewidth = 0.32, linetype = "dotted"),
    panel.spacing = grid::unit(0.75, "lines"), legend.position = "top",
    legend.justification = "left", legend.key.width = grid::unit(1.2, "cm"),
    axis.title = element_text(size = 10.5), plot.margin = margin(8, 12, 8, 8)
  )

output_dir <- file.path(runtime_root, "figures", "diagnostics")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_path <- file.path(output_dir, sprintf("glofas_normal_transfer_%s_ridge_rhs_last30_plus_issued28.pdf", format(cutoff, "%Y%m%d")))
score_path <- file.path(output_dir, sprintf("glofas_normal_transfer_%s_ridge_rhs_scores.csv", format(cutoff, "%Y%m%d")))
script_path <- file.path(output_dir, sprintf("glofas_normal_transfer_%s_plot_reproduction.R", format(cutoff, "%Y%m%d")))
ggsave(output_path, plot, width = 13.5, height = 9.0, device = cairo_pdf)
write.csv(do.call(rbind, lapply(models, `[[`, "score")), score_path, row.names = FALSE)
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(file_arg) == 1L) file.copy(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE), script_path, overwrite = TRUE)
cat(sprintf("pdf=%s\n", normalizePath(output_path, mustWork = TRUE)))
cat(sprintf("scores=%s\n", normalizePath(score_path, mustWork = TRUE)))
