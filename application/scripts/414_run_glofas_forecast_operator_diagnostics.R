#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "model_contract.R", "feature_contract.R", "covariate_design.R",
  "build_application_panel.R", "latent_path_design.R", "discrepancy_design.R",
  "glofas_normal_desn_part1_screening.R", "glofas_normal_oracle_forecast.R",
  "glofas_forecast_operator_diagnostics.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(
  source_runtime_root = "local_trackers/runtime_configs/glofas_post_search2_part14_20260916_r8",
  output_runtime_root = "local_trackers/runtime_configs/glofas_forecast_operator_diagnostics_20260920",
  n_draws = "500",
  seed = "20260920"
))
source_root <- app_resolve_path(args$source_runtime_root, must_work = TRUE)
output_root <- app_resolve_path(args$output_runtime_root, must_work = FALSE)
for (sub in c("objects", "tables", "figures", "manifests", "logs")) app_ensure_dir(file.path(output_root, sub))

cache <- readRDS(file.path(source_root, "configs", "part1_post_search2_design_cache.rds"))
future_truth <- cache$bundle$future_truth
future_dates <- as.Date(cache$bundle$future_dates)
truth <- as.numeric(future_truth$y_transformed)
if (!identical(as.Date(future_truth$date), future_dates) || any(!is.finite(truth))) {
  stop("Part 1 operator diagnosis requires the complete frozen 30-day log1p truth path.", call. = FALSE)
}
covariate_timeline <- attr(cache$bundle$panel, "model_covariate_timeline", exact = TRUE)

methods <- c(normal_ridge = "ridge", normal_rhs_vb = "rhs")
diagnostics <- lapply(names(methods), function(name) {
  fit_path <- file.path(source_root, "objects", paste0("part1_fit_", name, "_fit.rds"))
  fit_sha256 <- app_sha256_file(fit_path)
  object_path <- file.path(output_root, "objects", paste0("part1_", name, "_operator_diagnostic.rds"))
  result <- NULL
  if (file.exists(object_path)) {
    candidate <- readRDS(object_path)
    candidate_dates <- as.Date(candidate$future_dates %||% character())
    reusable <- identical(as.character(candidate$model %||% ""), name) &&
      identical(as.character(candidate$source_fit_sha256 %||% ""), fit_sha256) &&
      identical(as.integer(candidate$n_draws %||% NA_integer_), as.integer(args$n_draws)) &&
      identical(as.integer(candidate$seed %||% NA_integer_), as.integer(args$seed)) &&
      length(candidate_dates) == length(future_dates) && all(candidate_dates == future_dates) &&
      nrow(candidate$by_horizon %||% data.frame()) == 4L * length(future_dates)
    if (isTRUE(reusable)) result <- candidate
  }
  if (is.null(result)) {
    fit <- readRDS(fit_path)
    fitted <- list(method = methods[[name]], design = cache$design, fit = fit)
    result <- app_glofas_normal_operator_diagnostic(
      fitted, future_dates, truth, covariate_timeline,
      n_draws = as.integer(args$n_draws), seed = as.integer(args$seed)
    )
  }
  result$model <- name
  result$source_fit_path <- normalizePath(fit_path, mustWork = TRUE)
  result$source_fit_sha256 <- fit_sha256
  result$by_horizon$model <- name
  result$summary$model <- name
  saveRDS(result, object_path, version = 2L)
  result
})
names(diagnostics) <- names(methods)
by_horizon <- app_bind_rows_fill(lapply(diagnostics, `[[`, "by_horizon"))
summary <- app_bind_rows_fill(lapply(diagnostics, `[[`, "summary"))
app_write_csv(by_horizon, file.path(output_root, "tables", "part1_operator_diagnostics_by_horizon.csv"))
app_write_csv(summary, file.path(output_root, "tables", "part1_operator_diagnostics_summary.csv"))

part3_bank_path <- file.path(source_root, "objects", "part3_normal_rhs_driver_bank.rds")
part3_bank <- readRDS(part3_bank_path)
part3_draws <- as.matrix(part3_bank$components$usgs)
part3_dates <- as.Date(part3_bank$contract$future_dates)
if (length(part3_dates) != length(future_dates) || any(part3_dates != future_dates) ||
    nrow(part3_draws) != length(truth)) {
  stop("Part 3 Normal RHS driver bank is not aligned to the frozen Part 1 truth path.", call. = FALSE)
}
part3_score <- data.frame(
  model = "part3_normal_rhs_vb",
  target_date = future_dates,
  horizon = seq_along(future_dates),
  observed = truth,
  pred_mean = rowMeans(part3_draws),
  pred_median = apply(part3_draws, 1L, stats::median),
  pred_q025 = apply(part3_draws, 1L, stats::quantile, probs = 0.025, names = FALSE, type = 8),
  pred_q975 = apply(part3_draws, 1L, stats::quantile, probs = 0.975, names = FALSE, type = 8),
  path_sd = apply(part3_draws, 1L, stats::sd),
  stringsAsFactors = FALSE
)
part3_score$error <- part3_score$pred_mean - part3_score$observed
part3_score$absolute_error <- abs(part3_score$error)
app_write_csv(part3_score, file.path(output_root, "tables", "part3_normal_rhs_recursive_bank_by_horizon.csv"))

pdf_path <- file.path(output_root, "figures", "part1_operator_counterfactuals_and_part3_recursive_bank.pdf")
grDevices::pdf(pdf_path, width = 11, height = 7.5, onefile = TRUE)
on.exit(grDevices::dev.off(), add = TRUE)
palette <- c(
  stochastic_recursive = "#0072B2", conditional_mean_recursive = "#009E73",
  frozen_last = "#E69F00", teacher_forced = "#CC79A7"
)
history_keep <- tail(seq_along(cache$design$dates), 30L)
for (name in names(diagnostics)) {
  one <- diagnostics[[name]]$by_horizon
  ylim <- range(c(cache$design$y[history_keep], one$observed, one$pred_mean), finite = TRUE)
  graphics::plot(cache$design$dates[history_keep], cache$design$y[history_keep], type = "l", lwd = 2,
    col = "grey30", xlim = range(c(cache$design$dates[history_keep], future_dates)), ylim = ylim,
    xlab = "Date", ylab = "log1p discharge", main = paste("Part 1", name, "forecast-operator diagnosis"))
  graphics::lines(future_dates, truth, col = "black", lwd = 2.5)
  for (policy in names(palette)) {
    rows <- one$policy == policy
    graphics::lines(future_dates, one$pred_mean[rows], col = palette[[policy]], lwd = 2,
      lty = if (identical(policy, "teacher_forced")) 2 else 1)
  }
  graphics::abline(v = as.Date("2022-12-25"), lty = 3, col = "grey40")
  graphics::legend("topleft", c("observed history", "future truth", names(palette)),
    col = c("grey30", "black", unname(palette)), lty = c(1, 1, 1, 1, 1, 2), lwd = 2,
    bty = "n", cex = 0.85)
  graphics::mtext("Teacher forcing is diagnostic-only and is not a deployable forecast.", side = 1, line = 3.2, cex = 0.8)
}
graphics::plot(future_dates, truth, type = "l", lwd = 2.5, col = "black",
  ylim = range(c(truth, part3_score$pred_q025, part3_score$pred_q975), finite = TRUE),
  xlab = "Date", ylab = "log1p discharge", main = "Part 3 Normal RHS recursive driver bank")
graphics::polygon(c(future_dates, rev(future_dates)), c(part3_score$pred_q025, rev(part3_score$pred_q975)),
  col = grDevices::adjustcolor("#56B4E9", alpha.f = 0.22), border = NA)
graphics::lines(future_dates, part3_score$pred_mean, col = "#0072B2", lwd = 2)
graphics::lines(future_dates, truth, col = "black", lwd = 2.5)
graphics::legend("topleft", c("future truth", "recursive mean", "95% interval"),
  col = c("black", "#0072B2", grDevices::adjustcolor("#56B4E9", alpha.f = 0.4)),
  lty = c(1, 1, NA), pch = c(NA, NA, 15), lwd = c(2.5, 2, NA), bty = "n")
grDevices::dev.off()
on.exit(NULL, add = FALSE)

manifest <- data.frame(
  artifact = c(
    "part1_operator_diagnostics_by_horizon.csv", "part1_operator_diagnostics_summary.csv",
    "part3_normal_rhs_recursive_bank_by_horizon.csv", basename(pdf_path)
  ),
  path = c(
    file.path(output_root, "tables", "part1_operator_diagnostics_by_horizon.csv"),
    file.path(output_root, "tables", "part1_operator_diagnostics_summary.csv"),
    file.path(output_root, "tables", "part3_normal_rhs_recursive_bank_by_horizon.csv"), pdf_path
  ),
  stringsAsFactors = FALSE
)
manifest$sha256 <- vapply(manifest$path, app_sha256_file, character(1L))
manifest$role <- c("diagnostic", "diagnostic", "diagnostic", "diagnostic_figure")
app_write_csv(manifest, file.path(output_root, "manifests", "forecast_operator_diagnostic_artifacts.csv"))
app_write_csv(data.frame(
  cutoff = "2022-12-25", horizon_days = 30L, response_scale = "log1p",
  future_truth_role = "scoring_and_explicit_teacher_forced_diagnostic_only",
  teacher_forced_promotable = FALSE, part2_future_discrepancy_truth_available = FALSE,
  source_runtime_root = normalizePath(source_root, mustWork = TRUE),
  source_part3_bank_sha256 = app_sha256_file(part3_bank_path), stringsAsFactors = FALSE
), file.path(output_root, "manifests", "forecast_operator_diagnostic_contract.csv"))
message(sprintf("Forecast-operator diagnostics complete: %s", pdf_path))
