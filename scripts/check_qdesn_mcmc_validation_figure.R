#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(file_arg)) {
    normalizePath(sub("^--file=", "", file_arg[[1L]]), winslash = "/", mustWork = TRUE)
  } else {
    normalizePath(
      "scripts/check_qdesn_mcmc_validation_figure.R",
      winslash = "/",
      mustWork = TRUE
    )
  }
}
repo_root <- normalizePath(
  file.path(dirname(script_path), ".."),
  winslash = "/",
  mustWork = TRUE
)

figure_manifest_path <- file.path(
  repo_root,
  "tables",
  "qdesn_validation_mcmc_figure_manifest.txt"
)
figure_data_path <- file.path(
  repo_root,
  "tables",
  "qdesn_validation_mcmc_figure_data.csv"
)
figure_pdf_path <- file.path(
  repo_root,
  "figures",
  "independent_simulation",
  "qdesn_mcmc_metric_envelope_heatmap.pdf"
)

stop_if_missing <- function(path) {
  if (!file.exists(path)) stop(sprintf("Missing required artifact: %s", path), call. = FALSE)
}
invisible(lapply(
  c(figure_manifest_path, figure_data_path, figure_pdf_path),
  stop_if_missing
))

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
manifest_lines <- readLines(figure_manifest_path, warn = FALSE)
manifest_value <- function(key) {
  hits <- grep(paste0("^", key, ": "), manifest_lines, value = TRUE)
  if (length(hits) != 1L) {
    stop(sprintf("Expected exactly one '%s' entry in figure manifest.", key), call. = FALSE)
  }
  sub(paste0("^", key, ": "), "", hits[[1L]])
}

source_csv <- normalizePath(
  manifest_value("source_csv"),
  winslash = "/",
  mustWork = TRUE
)
if (
  !identical(
    manifest_value("source_path_base"),
    "/data/jaguir26/local/src"
  ) ||
  !identical(sha256(source_csv), manifest_value("source_csv_sha256")) ||
  !identical(sha256(figure_pdf_path), manifest_value("figure_pdf_sha256")) ||
  !identical(sha256(figure_data_path), manifest_value("figure_data_csv_sha256"))
) {
  stop("A source or generated artifact hash differs from the figure manifest.", call. = FALSE)
}

source <- read.csv(source_csv, check.names = FALSE, stringsAsFactors = FALSE)
figure <- read.csv(figure_data_path, check.names = FALSE, stringsAsFactors = FALSE)
source_required <- c(
  "article_interface_id", "inference", "model_variant", "family", "tau",
  "status", "source_registry_hash_value", "fit_qtrue_rmse",
  "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000",
  "fit_source_candidate_id", "fit_source_run_tag", "fit_source_signoff_grade",
  "fit_source_path", "fit_source_sha256", "forecast_mae_source_candidate_id",
  "forecast_mae_source_run_tag", "forecast_mae_source_signoff_grade",
  "forecast_mae_source_path", "forecast_mae_source_sha256",
  "forecast_check_source_candidate_id", "forecast_check_source_run_tag",
  "forecast_check_source_signoff_grade", "forecast_check_source_path",
  "forecast_check_source_sha256", "source_promotion_id"
)
missing_source <- setdiff(source_required, names(source))
if (length(missing_source)) {
  stop(
    sprintf("Authority is missing columns: %s", paste(missing_source, collapse = ", ")),
    call. = FALSE
  )
}
source <- source[source$inference == "mcmc", , drop = FALSE]
source_key <- with(source, paste(model_variant, family, sprintf("%.2f", as.numeric(tau))))
source_expected <- expand.grid(
  model_variant = c("dqlm", "exdqlm", "qdesn_al_rhs_ns", "qdesn_exal_rhs_ns"),
  family = c("normal", "laplace", "gausmix"),
  tau = c(0.05, 0.25, 0.50),
  stringsAsFactors = FALSE
)
source_expected_key <- with(
  source_expected,
  paste(model_variant, family, sprintf("%.2f", tau))
)
if (nrow(source) != 36L || anyDuplicated(source_key) ||
    !setequal(source_key, source_expected_key) ||
    any(source$status != "SUCCESS") ||
    any(source$article_interface_id != manifest_value("promotion_id"))) {
  stop("Authority does not contain the exact 36-row MCMC comparison grid.", call. = FALSE)
}
required <- c(
  "model_variant",
  "family",
  "tau",
  "metric",
  "value",
  "best_value",
  "ratio_to_best",
  "is_winner",
  "source_signoff_grade",
  "source_candidate_id",
  "source_run_tag",
  "source_path_relative",
  "source_sha256",
  "source_promotion_id",
  "source_registry_hash_value"
)
missing <- setdiff(required, names(figure))
if (length(missing)) {
  stop(
    sprintf("Figure data are missing columns: %s", paste(missing, collapse = ", ")),
    call. = FALSE
  )
}

metric_map <- list(
  fit_qtrue_rmse = c(
    value = "fit_qtrue_rmse",
    signoff = "fit_source_signoff_grade",
    candidate = "fit_source_candidate_id",
    run_tag = "fit_source_run_tag",
    path = "fit_source_path",
    sha256 = "fit_source_sha256"
  ),
  forecast_qtrue_mae_H1000 = c(
    value = "forecast_qtrue_mae_H1000",
    signoff = "forecast_mae_source_signoff_grade",
    candidate = "forecast_mae_source_candidate_id",
    run_tag = "forecast_mae_source_run_tag",
    path = "forecast_mae_source_path",
    sha256 = "forecast_mae_source_sha256"
  ),
  forecast_check_loss_H1000 = c(
    value = "forecast_check_loss_H1000",
    signoff = "forecast_check_source_signoff_grade",
    candidate = "forecast_check_source_candidate_id",
    run_tag = "forecast_check_source_run_tag",
    path = "forecast_check_source_path",
    sha256 = "forecast_check_source_sha256"
  )
)

key <- function(data) paste(
  data$model_variant,
  data$family,
  sprintf("%.2f", as.numeric(data$tau)),
  data$metric
)
expected <- do.call(
  rbind,
  lapply(names(metric_map), function(metric) {
    definition <- metric_map[[metric]]
    data.frame(
      model_variant = source$model_variant,
      family = source$family,
      tau = as.numeric(source$tau),
      metric = metric,
      value = as.numeric(source[[definition[["value"]]]]),
      source_signoff_grade = source[[definition[["signoff"]]]],
      source_candidate_id = source[[definition[["candidate"]]]],
      source_run_tag = source[[definition[["run_tag"]]]],
      source_path_relative = substring(
        normalizePath(source[[definition[["path"]]]], winslash = "/", mustWork = TRUE),
        nchar(manifest_value("source_path_base")) + 2L
      ),
      source_sha256 = source[[definition[["sha256"]]]],
      source_promotion_id = source$source_promotion_id,
      source_registry_hash_value = source$source_registry_hash_value,
      stringsAsFactors = FALSE
    )
  })
)

if (
  nrow(figure) != 108L ||
  nrow(expected) != 108L ||
  anyDuplicated(key(figure)) ||
  !setequal(key(figure), key(expected))
) {
  stop("Figure data do not contain the exact 108-cell comparison grid.", call. = FALSE)
}
figure <- figure[match(key(expected), key(figure)), , drop = FALSE]

numeric_equal <- function(lhs, rhs, tolerance = 1e-12) {
  all(is.finite(lhs)) &&
    all(is.finite(rhs)) &&
    all(abs(lhs - rhs) <= tolerance * pmax(1, abs(rhs)))
}
if (
  !numeric_equal(as.numeric(figure$value), expected$value) ||
  !identical(figure$source_signoff_grade, expected$source_signoff_grade) ||
  !identical(figure$source_candidate_id, expected$source_candidate_id) ||
  !identical(figure$source_run_tag, expected$source_run_tag) ||
  !identical(figure$source_path_relative, expected$source_path_relative) ||
  !identical(figure$source_sha256, expected$source_sha256) ||
  !identical(figure$source_promotion_id, expected$source_promotion_id) ||
  !identical(
    figure$source_registry_hash_value,
    expected$source_registry_hash_value
  )
) {
  stop("At least one plotted value or provenance field differs from authority.", call. = FALSE)
}

group <- interaction(figure$family, figure$tau, figure$metric, drop = TRUE)
expected_best <- ave(as.numeric(figure$value), group, FUN = min)
expected_ratio <- as.numeric(figure$value) / expected_best
expected_winner <- abs(as.numeric(figure$value) - expected_best) < 1e-10
if (
  !numeric_equal(as.numeric(figure$best_value), expected_best) ||
  !numeric_equal(as.numeric(figure$ratio_to_best), expected_ratio) ||
  !identical(as.logical(figure$is_winner), expected_winner) ||
  sum(expected_winner) != 27L
) {
  stop("Within-cell minima, ratios, or winner flags are inconsistent.", call. = FALSE)
}

if (
  any(grepl("^/", figure$source_path_relative)) ||
  any(grepl("/home/jaguir26/local/src", figure$source_path_relative, fixed = TRUE)) ||
  length(unique(figure$source_registry_hash_value)) != 1L ||
  unique(figure$source_registry_hash_value) != manifest_value("source_registry_hash")
) {
  stop("Figure data contain a nonportable path or registry mismatch.", call. = FALSE)
}

cat(sprintf("authority_rows_verified: %d\n", nrow(source)))
cat(sprintf("plotted_values_verified: %d\n", nrow(figure)))
cat(sprintf("within_cell_winners_verified: %d\n", sum(expected_winner)))
cat(sprintf("source_registry_hash: %s\n", unique(figure$source_registry_hash_value)))
cat("result: PASS\n")
