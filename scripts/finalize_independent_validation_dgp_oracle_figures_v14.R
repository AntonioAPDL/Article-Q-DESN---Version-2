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
relative_article <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(repo_root, "/")
  if (!startsWith(path, prefix)) {
    stop("A manifest file escapes the article repository.", call. = FALSE)
  }
  substring(path, nchar(prefix) + 1L)
}

required_tools <- c("pdfinfo", "pdfimages", "pdffonts", "pdftocairo")
if (any(!nzchar(Sys.which(required_tools)))) {
  stop("pdfinfo, pdfimages, pdffonts, and pdftocairo are required.",
       call. = FALSE)
}

render_signature <- function(path) {
  hashes <- character(2L)
  for (i in seq_len(2L)) {
    prefix <- tempfile(pattern = "qdesn-v14-vector-render-")
    output <- system2(
      "pdftocairo", c("-singlefile", "-png", "-r", "96", path, prefix),
      stdout = TRUE, stderr = TRUE
    )
    rendered <- paste0(prefix, ".png")
    if (!is.null(attr(output, "status")) || !file.exists(rendered)) {
      stop(sprintf("PDF rendering failed for %s.", basename(path)), call. = FALSE)
    }
    image <- png::readPNG(rendered)
    hashes[[i]] <- sha256(rendered)
    unlink(rendered)
    rgb <- image[, , seq_len(min(3L, dim(image)[[3L]])), drop = FALSE]
    if (!any(apply(rgb, c(1L, 2L), min) < 0.98)) {
      stop(sprintf("Rendered PDF is blank: %s.", basename(path)), call. = FALSE)
    }
  }
  if (!identical(hashes[[1L]], hashes[[2L]])) {
    stop(sprintf("Repeated rendering is unstable for %s.", basename(path)),
         call. = FALSE)
  }
  hashes[[1L]]
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
if (!identical(as.character(validation_head),
               as.character(config$validation_authority_commit))) {
  stop("The validation worktree is not at the frozen oracle authority.",
       call. = FALSE)
}

oracle_source <- file.path(validation_root, config$oracle$relative_path)
oracle_asset <- article_path(config$outputs$oracle_asset)
interval_path <- article_path(config$inputs$interval_summary)
figure_data_path <- article_path(config$outputs$figure_data)
input_paths <- c(oracle_source, oracle_asset, interval_path)
input_hashes <- c(
  as.character(config$oracle$sha256), as.character(config$oracle$sha256),
  as.character(config$inputs$interval_summary_sha256)
)
if (any(!file.exists(input_paths)) ||
    !all(vapply(seq_along(input_paths), function(i) {
      identical(sha256(input_paths[[i]]), input_hashes[[i]])
    }, logical(1L)))) {
  stop("A frozen input changed before figure finalization.", call. = FALSE)
}
figure_data <- read.csv(figure_data_path, check.names = FALSE)
if (nrow(figure_data) != as.integer(config$expected$figure_rows) ||
    sum(figure_data$diagnostic_grade == "WARN") != 5L) {
  stop("The independent figure ledger failed its frozen contract.", call. = FALSE)
}

figure_paths <- article_path(file.path(
  config$outputs$figure_directory,
  c(
    "qdesn_validation_500obs_v14_mcmc_fit_rmse_intervals.pdf",
    "qdesn_validation_500obs_v14_mcmc_forecast_mae_intervals.pdf",
    "qdesn_validation_500obs_v14_mcmc_forecast_check_loss_intervals.pdf",
    "qdesn_validation_500obs_v14_vb_fit_rmse_intervals.pdf"
  )
))
for (path in figure_paths) {
  if (!file.exists(path) || file.info(path)$size <= 10000L) {
    stop(sprintf("An active figure is missing: %s.", basename(path)), call. = FALSE)
  }
  info <- system2("pdfinfo", path, stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(info, "status")) ||
      !any(grepl("^Pages:[[:space:]]+1$", info))) {
    stop(sprintf("PDF integrity failed for %s.", basename(path)), call. = FALSE)
  }
  images <- system2("pdfimages", c("-list", path), stdout = TRUE, stderr = TRUE)
  image_rows <- grep(
    "^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+image", images,
    value = TRUE
  )
  if (!is.null(attr(images, "status")) || length(image_rows) != 0L) {
    stop(sprintf("The vector PDF contains a raster image: %s.", basename(path)),
         call. = FALSE)
  }
  fonts <- system2("pdffonts", path, stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(fonts, "status")) || length(fonts) <= 2L) {
    stop(sprintf("No vector text was found in %s.", basename(path)), call. = FALSE)
  }
  render_signature(path)
}

builder_path <- file.path(
  repo_root, "scripts", "build_independent_validation_dgp_oracle_figures_v14.R"
)
checker_path <- file.path(
  repo_root, "scripts", "check_independent_validation_dgp_oracle_figures_v14.R"
)
revision_checker_path <- file.path(
  repo_root, "scripts", "check_qdesn_final_manuscript_revision.R"
)
pipeline_path <- file.path(
  repo_root, "scripts", "run_independent_validation_dgp_oracle_figures_v14.sh"
)
style_path <- article_path(config$outputs$figure_style)
renderer_path <- article_path(config$outputs$figure_renderer)
wrapper_paths <- article_path(c(
  config$outputs$mcmc_fit_wrapper,
  config$outputs$mcmc_forecast_wrapper,
  config$outputs$vb_wrapper
))

refresh_colon_manifest <- function(relative) {
  path <- article_path(relative)
  if (!file.exists(path)) {
    stop(sprintf("A dependent manifest is missing: %s.", relative), call. = FALSE)
  }
  lines <- readLines(path, warn = FALSE)
  for (i in seq_along(lines)) {
    hit <- regexec("^  (.+): ([0-9a-f]{64})$", lines[[i]])
    parts <- regmatches(lines[[i]], hit)[[1L]]
    if (length(parts) == 3L) {
      artifact <- article_path(parts[[2L]])
      if (!file.exists(artifact)) {
        stop(sprintf("A manifest target is missing: %s.", parts[[2L]]),
             call. = FALSE)
      }
      lines[[i]] <- sprintf("  %s: %s", parts[[2L]], sha256(artifact))
    }
  }
  writeLines(lines, path, useBytes = TRUE)
}
refresh_colon_manifest("tables/qdesn_validation_500obs_metric_intervals_v14_manifest.txt")
refresh_colon_manifest("tables/qdesn_validation_500obs_exdqlm_1p1p1_article_v14_manifest.txt")

manifest_files <- c(
  config_path, builder_path, script_path, checker_path, revision_checker_path,
  pipeline_path,
  style_path, renderer_path, interval_path, oracle_asset, figure_data_path,
  figure_paths, wrapper_paths,
  file.path(repo_root, "main.tex"),
  file.path(repo_root, "qdesn-supplement.tex"),
  file.path(repo_root, "overleaf", "article_files.txt")
)
if (any(!file.exists(manifest_files))) {
  stop("A manifest input is missing.", call. = FALSE)
}
manifest_lines <- c(
  paste0("projection_id=", config$projection_id),
  "evidence_date=2026-09-09",
  paste0("article_minimum_commit=", config$article_minimum_commit),
  paste0("validation_authority_commit=", config$validation_authority_commit),
  paste0("interval_rows=", config$expected$interval_rows),
  paste0("figure_rows=", nrow(figure_data)),
  paste0("oracle_rows=", config$expected$oracle_rows),
  paste0("active_figure_count=", length(figure_paths)),
  "active_figure_scope=mcmc_fit_and_forecast_plus_vb_fit",
  "inactive_vb_forecast_assets=retained_but_not_published",
  "pdf_container=cairo_vector_pdf",
  "embedded_raster_images=0",
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
  "INDEPENDENT_DGP_ORACLE_FIGURES_V14_FINALIZED figures=%d format=vector\n",
  length(figure_paths)
))
