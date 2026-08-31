#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/", mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
config_path <- file.path(
  repo_root, "application", "config", "independent_validation_dgp_oracle_figures_v14.yaml"
)
config <- yaml::read_yaml(config_path)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
article_path <- function(relative) file.path(repo_root, relative)
relative_article <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(repo_root, "/")
  if (!startsWith(path, prefix)) stop("A manifest file escapes the article repository.", call. = FALSE)
  substring(path, nchar(prefix) + 1L)
}
if (!requireNamespace("png", quietly = TRUE)) {
  stop("The png package is required for PDF render verification.", call. = FALSE)
}
required_tools <- c("pdfinfo", "pdfimages", "pdftocairo")
if (any(!nzchar(Sys.which(required_tools)))) {
  stop("pdfinfo, pdfimages, and pdftocairo are required for PDF verification.",
       call. = FALSE)
}
render_signature <- function(path) {
  hashes <- character(2L)
  margins <- matrix(NA_integer_, nrow = 2L, ncol = 4L)
  for (i in seq_len(2L)) {
    prefix <- tempfile(pattern = paste0("qdesn-v14-render-", i, "-"))
    output <- system2(
      "pdftocairo",
      c("-singlefile", "-png", "-r", "96", path, prefix),
      stdout = TRUE, stderr = TRUE
    )
    rendered <- paste0(prefix, ".png")
    if (!is.null(attr(output, "status")) || !file.exists(rendered)) {
      stop(sprintf("PDF rendering failed for %s.", basename(path)), call. = FALSE)
    }
    image <- png::readPNG(rendered)
    hashes[[i]] <- unname(tools::sha256sum(rendered)[[1L]])
    unlink(rendered)
    rgb <- image[, , seq_len(min(3L, dim(image)[[3L]])), drop = FALSE]
    ink <- apply(rgb, c(1L, 2L), min) < 0.98
    if (!any(ink)) stop(sprintf("Rendered PDF is blank: %s.", basename(path)), call. = FALSE)
    at <- which(ink, arr.ind = TRUE)
    margins[i, ] <- c(
      min(at[, 1L]) - 1L, nrow(ink) - max(at[, 1L]),
      min(at[, 2L]) - 1L, ncol(ink) - max(at[, 2L])
    )
  }
  if (!identical(hashes[[1L]], hashes[[2L]])) {
    stop(sprintf("Repeated rendering is unstable for %s.", basename(path)), call. = FALSE)
  }
  list(hash = hashes[[1L]], margins = margins[1L, ])
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
if (!identical(as.character(validation_head), as.character(config$validation_authority_commit))) {
  stop("The validation worktree is not at the frozen oracle authority.", call. = FALSE)
}
oracle_source <- file.path(validation_root, config$oracle$relative_path)
oracle_asset <- article_path(config$outputs$oracle_asset)
interval_path <- article_path(config$inputs$interval_summary)
figure_data_path <- article_path(config$outputs$figure_data)
if (!file.exists(oracle_source) ||
    !identical(sha256(oracle_source), as.character(config$oracle$sha256)) ||
    !file.exists(oracle_asset) ||
    !identical(sha256(oracle_asset), as.character(config$oracle$sha256)) ||
    !file.exists(interval_path) ||
    !identical(sha256(interval_path), as.character(config$inputs$interval_summary_sha256))) {
  stop("A frozen input changed before PDF finalization.", call. = FALSE)
}
figure_data <- read.csv(figure_data_path, check.names = FALSE)
if (nrow(figure_data) != as.integer(config$expected$figure_rows) ||
    any(!is.finite(figure_data$plot_reference_value))) {
  stop("The figure ledger is incomplete.", call. = FALSE)
}

inference_levels <- unlist(config$expected$inference, use.names = FALSE)
figure_paths <- unlist(lapply(inference_levels, function(inference) {
  article_path(file.path(
    config$outputs$figure_directory,
    sprintf(
      "%s_%s_%s_intervals.pdf", config$outputs$figure_prefix, inference,
      c("fit_rmse", "forecast_mae", "forecast_check_loss")
    )
  ))
}), use.names = FALSE)
for (path in figure_paths) {
  if (!file.exists(path) || file.info(path)$size <= 50000L) {
    stop(sprintf("A finalized figure is missing: %s", basename(path)), call. = FALSE)
  }
  info <- system2("pdfinfo", path, stdout = TRUE, stderr = TRUE)
  page_line <- grep("^Pages:", info, value = TRUE)
  if (!is.null(attr(info, "status")) || length(page_line) != 1L ||
      !grepl("Pages:[[:space:]]+1$", page_line)) {
    stop(sprintf("Final PDF integrity failed for %s.", basename(path)), call. = FALSE)
  }
  images <- system2("pdfimages", c("-list", path), stdout = TRUE, stderr = TRUE)
  image_rows <- grep("^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+image", images,
                     value = TRUE)
  if (!is.null(attr(images, "status")) || length(image_rows) != 1L ||
      !grepl("[[:space:]]300[[:space:]]+300[[:space:]]", image_rows)) {
    stop(sprintf("Final 300-dpi image contract failed for %s.", basename(path)), call. = FALSE)
  }
  render_signature(path)
}

builder_path <- file.path(repo_root, "scripts", "build_independent_validation_dgp_oracle_figures_v14.R")
checker_path <- file.path(repo_root, "scripts", "check_independent_validation_dgp_oracle_figures_v14.R")
pipeline_path <- file.path(repo_root, "scripts", "run_independent_validation_dgp_oracle_figures_v14.sh")
wrapper_paths <- c(
  article_path(config$outputs$mcmc_wrapper), article_path(config$outputs$vb_wrapper)
)
refresh_colon_manifest <- function(relative) {
  path <- article_path(relative)
  if (!file.exists(path)) stop(sprintf("A dependent manifest is missing: %s", relative), call. = FALSE)
  lines <- readLines(path, warn = FALSE)
  for (i in seq_along(lines)) {
    hit <- regexec("^  (.+): ([0-9a-f]{64})$", lines[[i]])
    parts <- regmatches(lines[[i]], hit)[[1L]]
    if (length(parts) == 3L) {
      artifact <- article_path(parts[[2L]])
      if (!file.exists(artifact)) stop(sprintf("A manifest target is missing: %s", parts[[2L]]), call. = FALSE)
      lines[[i]] <- sprintf("  %s: %s", parts[[2L]], sha256(artifact))
    }
  }
  writeLines(lines, path, useBytes = TRUE)
}
refresh_colon_manifest("tables/qdesn_validation_500obs_metric_intervals_v14_manifest.txt")
refresh_colon_manifest("tables/qdesn_validation_500obs_exdqlm_1p1p1_article_v14_manifest.txt")
manifest_files <- c(
  config_path, builder_path, script_path, checker_path, pipeline_path,
  interval_path, oracle_asset, figure_data_path, figure_paths, wrapper_paths,
  file.path(repo_root, "main.tex"), file.path(repo_root, "qdesn-supplement.tex")
)
if (any(!file.exists(manifest_files))) stop("A manifest input is missing.", call. = FALSE)
manifest_lines <- c(
  paste0("projection_id=", config$projection_id),
  "evidence_date=2026-08-29",
  paste0("article_minimum_commit=", config$article_minimum_commit),
  paste0("validation_authority_commit=", config$validation_authority_commit),
  paste0("interval_rows=", config$expected$interval_rows),
  paste0("figure_rows=", nrow(figure_data)),
  paste0("oracle_rows=", config$expected$oracle_rows),
  paste0("figure_count=", length(figure_paths)),
  "pdf_container=cairo_png_300dpi_image_pdf",
  "pdf_render_process_isolation=one_r_process_per_figure",
  "pdf_repeat_renderer=pdftocairo",
  "pdf_repeat_render_dpi=96",
  "pdf_repeat_render_hash_stable=true",
  "fit_and_forecast_path_error_oracle=0",
  "forecast_check_oracle=population_expected_check_loss",
  vapply(manifest_files, function(path) {
    paste0(relative_article(path), "|sha256=", sha256(path))
  }, character(1L))
)
writeLines(manifest_lines, article_path(config$outputs$manifest), useBytes = TRUE)

cat(sprintf(
  "INDEPENDENT_DGP_ORACLE_FIGURES_V14_FINALIZED figures=%d dpi=300\n",
  length(figure_paths)
))
