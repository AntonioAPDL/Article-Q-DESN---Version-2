#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
config_path <- file.path(
  repo_root, "application", "config",
  "independent_validation_dgp_oracle_figures_v14.yaml"
)
if (!requireNamespace("yaml", quietly = TRUE) ||
    !requireNamespace("png", quietly = TRUE)) {
  stop("The yaml and png packages are required.", call. = FALSE)
}
config <- yaml::read_yaml(config_path)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
article_path <- function(relative) file.path(repo_root, relative)
check_count <- 0L
check <- function(condition, label) {
  check_count <<- check_count + 1L
  if (!isTRUE(condition)) stop(sprintf("CHECK_FAILED: %s", label), call. = FALSE)
  invisible(TRUE)
}

required_tools <- c("pdfinfo", "pdfimages", "pdffonts", "pdftocairo")
check(all(nzchar(Sys.which(required_tools))), "PDF inspection tools are available")

render_once <- function(path) {
  prefix <- tempfile(pattern = "qdesn-v14-check-")
  output <- system2(
    "pdftocairo", c("-singlefile", "-png", "-r", "96", path, prefix),
    stdout = TRUE, stderr = TRUE
  )
  rendered <- paste0(prefix, ".png")
  if (!is.null(attr(output, "status")) || !file.exists(rendered)) {
    stop(sprintf("PDF rendering failed for %s.", basename(path)), call. = FALSE)
  }
  image <- png::readPNG(rendered)
  hash <- sha256(rendered)
  unlink(rendered)
  rgb <- image[, , seq_len(min(3L, dim(image)[[3L]])), drop = FALSE]
  check(any(apply(rgb, c(1L, 2L), min) < 0.98),
        paste(basename(path), "renders as a nonblank page"))
  hash
}

validation_setting <- Sys.getenv("QDESN_VALIDATION_ROOT", unset = config$validation_root)
validation_candidate <- if (grepl("^/", validation_setting)) {
  validation_setting
} else {
  file.path(repo_root, validation_setting)
}
validation_root <- normalizePath(validation_candidate, winslash = "/", mustWork = TRUE)
validation_head <- system2(
  "git", c("-C", validation_root, "rev-parse", "HEAD"), stdout = TRUE
)
check(identical(as.character(validation_head),
                as.character(config$validation_authority_commit)),
      "validation authority commit")
check(identical(system2(
  "git", c("-C", repo_root, "merge-base", "--is-ancestor",
           as.character(config$article_minimum_commit), "HEAD")
), 0L), "article baseline ancestry")

oracle_source <- file.path(validation_root, config$oracle$relative_path)
oracle_asset <- article_path(config$outputs$oracle_asset)
interval_path <- article_path(config$inputs$interval_summary)
figure_data_path <- article_path(config$outputs$figure_data)
check(file.exists(oracle_source) &&
        identical(sha256(oracle_source), as.character(config$oracle$sha256)),
      "validation oracle hash")
check(file.exists(oracle_asset) &&
        identical(sha256(oracle_asset), as.character(config$oracle$sha256)),
      "article oracle hash")
check(identical(sha256(interval_path),
                as.character(config$inputs$interval_summary_sha256)),
      "interval-summary hash")
check(identical(readBin(oracle_source, "raw", file.info(oracle_source)$size),
                readBin(oracle_asset, "raw", file.info(oracle_asset)$size)),
      "oracle projection is byte-identical")

interval <- read.csv(interval_path, check.names = FALSE)
oracle <- read.csv(oracle_asset, check.names = FALSE)
figure_data <- read.csv(figure_data_path, check.names = FALSE)
expected <- config$expected
models <- unlist(expected$models, use.names = FALSE)
families <- unlist(expected$families, use.names = FALSE)
taus <- as.numeric(unlist(expected$taus, use.names = FALSE))
metric_roles <- unlist(expected$metric_roles, use.names = FALSE)
check(nrow(interval) == as.integer(expected$interval_rows), "interval row count")
check(nrow(oracle) == as.integer(expected$oracle_rows), "oracle row count")
check(nrow(figure_data) == as.integer(expected$figure_rows), "figure row count")
figure_key <- with(
  figure_data,
  paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role,
        sep = "|")
)
check(!anyDuplicated(figure_key), "figure key uniqueness")
check(setequal(unique(figure_data$model_variant), models), "model surface")
check(setequal(unique(figure_data$family), families), "family surface")
check(setequal(unique(figure_data$tau), taus), "probability-level surface")
check(setequal(unique(figure_data$metric_role), metric_roles), "metric surface")
check(all(is.finite(figure_data$posterior_mean)) &&
        all(is.finite(figure_data$cri_lower)) &&
        all(is.finite(figure_data$cri_upper)), "finite intervals")
check(all(figure_data$cri_lower <= figure_data$posterior_mean &
          figure_data$posterior_mean <= figure_data$cri_upper),
      "posterior means inside intervals")
check(all(figure_data$plot_reference_value[
  figure_data$metric_role %in% c("fit_rmse", "forecast_mae")
] == 0), "path-error oracle")
check(all(figure_data$plot_reference_value[
  figure_data$metric_role == "forecast_check"
] > 0), "check-loss oracle")
check(all(figure_data$forecast_origins == 34L) &&
        all(figure_data$forecast_pairs == 1000L), "forecast design")

warning_keys <- sort(figure_key[figure_data$diagnostic_grade == "WARN"])
expected_warning_keys <- sort(c(
  "mcmc|qdesn_al_rhs_ns|normal|0.05|forecast_mae",
  "mcmc|exdqlm|laplace|0.05|forecast_mae",
  "mcmc|exdqlm|gausmix|0.25|forecast_mae",
  "mcmc|qdesn_al_rhs_ns|normal|0.05|forecast_check",
  "mcmc|qdesn_exal_rhs_ns|gausmix|0.25|forecast_check"
))
check(identical(warning_keys, expected_warning_keys),
      "exact five diagnostic-warning roles")

active_figures <- file.path(
  config$outputs$figure_directory,
  c(
    "qdesn_validation_500obs_v14_mcmc_fit_rmse_intervals.pdf",
    "qdesn_validation_500obs_v14_mcmc_forecast_mae_intervals.pdf",
    "qdesn_validation_500obs_v14_mcmc_forecast_check_loss_intervals.pdf",
    "qdesn_validation_500obs_v14_vb_fit_rmse_intervals.pdf"
  )
)
for (relative in active_figures) {
  path <- article_path(relative)
  check(file.exists(path) && file.info(path)$size > 10000L,
        paste(relative, "is substantive"))
  info <- system2("pdfinfo", path, stdout = TRUE, stderr = TRUE)
  check(is.null(attr(info, "status")) &&
          any(grepl("^Pages:[[:space:]]+1$", info)),
        paste(relative, "is a one-page PDF"))
  images <- system2("pdfimages", c("-list", path), stdout = TRUE, stderr = TRUE)
  image_rows <- grep(
    "^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+image", images,
    value = TRUE
  )
  check(is.null(attr(images, "status")) && length(image_rows) == 0L,
        paste(relative, "contains no raster image"))
  fonts <- system2("pdffonts", path, stdout = TRUE, stderr = TRUE)
  check(is.null(attr(fonts, "status")) && length(fonts) > 2L,
        paste(relative, "contains vector text"))
  first <- render_once(path)
  second <- render_once(path)
  check(identical(first, second), paste(relative, "renders repeatably"))
}

wrapper_relatives <- c(
  config$outputs$mcmc_fit_wrapper,
  config$outputs$mcmc_forecast_wrapper,
  config$outputs$vb_wrapper
)
wrappers <- lapply(wrapper_relatives, function(relative) {
  path <- article_path(relative)
  check(file.exists(path), paste(relative, "exists"))
  paste(readLines(path, warn = FALSE), collapse = "\n")
})
check(all(vapply(wrappers, grepl, logical(1L), pattern = "\\figalt{", fixed = TRUE)),
      "active wrappers include alternative descriptions")
check(grepl("mcmc-fit-rmse-intervals", wrappers[[1L]], fixed = TRUE),
      "MCMC fitting wrapper has the fitting figure")
check(grepl("mcmc-forecast-mae-intervals", wrappers[[2L]], fixed = TRUE) &&
        grepl("mcmc-forecast-check-loss-intervals", wrappers[[2L]], fixed = TRUE),
      "MCMC forecast wrapper has both forecast figures")
check(grepl("vb-fit-rmse-intervals", wrappers[[3L]], fixed = TRUE) &&
        !grepl("vb-forecast-", wrappers[[3L]], fixed = TRUE),
      "VB wrapper contains fitting recovery only")

main_text <- paste(readLines(article_path("main.tex"), warn = FALSE), collapse = "\n")
supp_text <- paste(
  readLines(article_path("qdesn-supplement.tex"), warn = FALSE), collapse = "\n"
)
article_files <- readLines(article_path("overleaf/article_files.txt"), warn = FALSE)
check(grepl(config$outputs$mcmc_forecast_wrapper, main_text, fixed = TRUE),
      "main article uses the MCMC forecast wrapper")
check(grepl(config$outputs$mcmc_fit_wrapper, supp_text, fixed = TRUE) &&
        grepl(config$outputs$vb_wrapper, supp_text, fixed = TRUE),
      "supplement uses both fitting wrappers")
check(all(active_figures %in% article_files), "active figures are in article snapshot")
check(!any(grepl("v14_vb_forecast_", article_files, fixed = TRUE)),
      "inactive VB forecast figures are excluded from article snapshot")

manifest_path <- article_path(config$outputs$manifest)
manifest <- readLines(manifest_path, warn = FALSE)
check(any(manifest == "pdf_container=cairo_vector_pdf"),
      "manifest records vector PDF contract")
check(any(manifest == "embedded_raster_images=0"),
      "manifest records zero embedded raster images")
check(any(manifest == "active_figure_count=4"),
      "manifest records four active independent figures")
hash_lines <- grep("\\|sha256=", manifest, value = TRUE)
check(length(hash_lines) >= 20L, "manifest covers the complete active pipeline")
for (line in hash_lines) {
  fields <- strsplit(line, "\\|sha256=")[[1L]]
  check(length(fields) == 2L, paste(line, "manifest syntax"))
  path <- article_path(fields[[1L]])
  check(file.exists(path), paste(fields[[1L]], "manifest file exists"))
  check(identical(sha256(path), fields[[2L]]),
        paste(fields[[1L]], "manifest hash"))
}

cat(sprintf(
  paste0("INDEPENDENT_DGP_ORACLE_FIGURES_V14_CHECK=PASS checks=%d ",
         "active_figures=4 warnings=5 format=vector\n"),
  check_count
))
