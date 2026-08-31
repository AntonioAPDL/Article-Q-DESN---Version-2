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
check_count <- 0L
check <- function(condition, label) {
  check_count <<- check_count + 1L
  if (!isTRUE(condition)) stop(sprintf("CHECK_FAILED: %s", label), call. = FALSE)
  invisible(TRUE)
}
if (!requireNamespace("png", quietly = TRUE)) {
  stop("The png package is required for PDF render verification.", call. = FALSE)
}
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
  ink <- apply(rgb, c(1L, 2L), min) < 0.98
  if (!any(ink)) stop(sprintf("Rendered PDF is blank: %s.", basename(path)), call. = FALSE)
  at <- which(ink, arr.ind = TRUE)
  list(
    hash = hash,
    margins = c(
      min(at[, 1L]) - 1L, nrow(ink) - max(at[, 1L]),
      min(at[, 2L]) - 1L, ncol(ink) - max(at[, 2L])
    )
  )
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
check(identical(as.character(validation_head), as.character(config$validation_authority_commit)),
      "validation authority commit")
check(identical(system2(
  "git", c("-C", repo_root, "merge-base", "--is-ancestor",
           as.character(config$article_minimum_commit), "HEAD")
), 0L), "article baseline ancestry")

oracle_source <- file.path(validation_root, config$oracle$relative_path)
oracle_asset <- article_path(config$outputs$oracle_asset)
interval_path <- article_path(config$inputs$interval_summary)
check(file.exists(oracle_source), "validation oracle exists")
check(identical(sha256(oracle_source), as.character(config$oracle$sha256)),
      "validation oracle hash")
check(file.exists(oracle_asset), "article oracle exists")
check(identical(sha256(oracle_asset), as.character(config$oracle$sha256)),
      "article oracle hash")
check(identical(readBin(oracle_source, "raw", file.info(oracle_source)$size),
                readBin(oracle_asset, "raw", file.info(oracle_asset)$size)),
      "oracle projection is byte-identical")
check(identical(sha256(interval_path), as.character(config$inputs$interval_summary_sha256)),
      "v12 interval summary hash")

interval <- read.csv(interval_path, check.names = FALSE)
oracle <- read.csv(oracle_asset, check.names = FALSE)
figure_data_path <- article_path(config$outputs$figure_data)
figure_data <- read.csv(figure_data_path, check.names = FALSE)
expected <- config$expected
models <- unlist(expected$models, use.names = FALSE)
families <- unlist(expected$families, use.names = FALSE)
taus <- as.numeric(unlist(expected$taus, use.names = FALSE))
inference_levels <- unlist(expected$inference, use.names = FALSE)
metric_roles <- unlist(expected$metric_roles, use.names = FALSE)
check(nrow(interval) == as.integer(expected$interval_rows), "interval row count")
check(nrow(oracle) == as.integer(expected$oracle_rows), "oracle row count")
check(nrow(figure_data) == as.integer(expected$figure_rows), "figure row count")
figure_key <- with(
  figure_data,
  paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role, sep = "|")
)
check(!anyDuplicated(figure_key), "figure key uniqueness")
check(setequal(unique(figure_data$model_variant), models), "model surface")
check(setequal(unique(figure_data$family), families), "family surface")
check(setequal(unique(figure_data$tau), taus), "quantile surface")
check(setequal(unique(figure_data$inference), inference_levels), "inference surface")
check(setequal(unique(figure_data$metric_role), metric_roles), "metric surface")
check(all(is.finite(figure_data$posterior_mean)), "finite posterior means")
check(all(is.finite(figure_data$cri_lower)), "finite interval lower bounds")
check(all(is.finite(figure_data$cri_upper)), "finite interval upper bounds")
check(all(figure_data$cri_lower <= figure_data$posterior_mean &
            figure_data$posterior_mean <= figure_data$cri_upper),
      "posterior means inside intervals")
check(all(figure_data$plot_reference_value[
  figure_data$metric_role %in% c("fit_rmse", "forecast_mae")
] == 0), "path-error oracle is zero")
check(all(figure_data$plot_reference_value[
  figure_data$metric_role == "forecast_check"
] > 0), "check-loss oracle is positive")
check(all(figure_data$forecast_origins == 34L), "forecast origin contract")
check(all(figure_data$forecast_pairs == 1000L), "forecast pair contract")

oracle_key <- with(oracle, paste(family, sprintf("%.2f", tau), metric_role, sep = "|"))
figure_oracle_key <- with(
  figure_data, paste(family, sprintf("%.2f", tau), metric_role, sep = "|")
)
oracle_at <- match(figure_oracle_key, oracle_key)
check(!anyNA(oracle_at), "oracle join complete")
check(isTRUE(all.equal(
  figure_data$plot_reference_value, oracle$plot_reference_value[oracle_at], tolerance = 0
)), "oracle values map exactly")

figure_paths <- unlist(lapply(inference_levels, function(inference) {
  file.path(
    config$outputs$figure_directory,
    sprintf("%s_%s_%s_intervals.pdf", config$outputs$figure_prefix, inference,
            c("fit_rmse", "forecast_mae", "forecast_check_loss"))
  )
}), use.names = FALSE)
check(length(figure_paths) == 6L, "six figures declared")
for (relative in figure_paths) {
  path <- article_path(relative)
  check(file.exists(path) && file.info(path)$size > 10000L,
        paste(relative, "is substantive"))
  info <- system2("pdfinfo", path, stdout = TRUE, stderr = TRUE)
  check(is.null(attr(info, "status")), paste(relative, "pdfinfo succeeds"))
  page_line <- grep("^Pages:", info, value = TRUE)
  check(length(page_line) == 1L && grepl("Pages:[[:space:]]+1$", page_line),
        paste(relative, "has one page"))
  images <- system2("pdfimages", c("-list", path), stdout = TRUE, stderr = TRUE)
  image_rows <- grep("^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+image", images,
                     value = TRUE)
  check(is.null(attr(images, "status")) && length(image_rows) == 1L,
        paste(relative, "contains one image"))
  check(grepl("[[:space:]]300[[:space:]]+300[[:space:]]", image_rows),
        paste(relative, "uses 300 dpi"))
  first_render <- render_once(path)
  second_render <- render_once(path)
  check(identical(first_render$hash, second_render$hash),
        paste(relative, "renders repeatably"))
  check(all(is.finite(first_render$margins)) && all(is.finite(second_render$margins)),
        paste(relative, "renders as a nonblank bounded page"))
}

for (inference in inference_levels) {
  wrapper_path <- article_path(config$outputs[[paste0(inference, "_wrapper")]])
  check(file.exists(wrapper_path), paste(inference, "wrapper exists"))
  wrapper <- paste(readLines(wrapper_path, warn = FALSE), collapse = "\n")
  check(lengths(regmatches(wrapper, gregexpr("black dashed line", wrapper,
                                             fixed = TRUE)))[[1L]] == 3L,
        paste(inference, "wrapper explains oracle lines"))
  for (label_id in c("fit-rmse", "forecast-mae", "forecast-check-loss")) {
    label <- sprintf("\\label{fig:simulation-500obs-%s-%s-intervals}",
                     inference, label_id)
    check(grepl(label, wrapper, fixed = TRUE), paste(label, "present"))
  }
}

main_text <- paste(readLines(article_path("main.tex"), warn = FALSE), collapse = "\n")
supplement_text <- paste(
  readLines(article_path("qdesn-supplement.tex"), warn = FALSE), collapse = "\n"
)
check(grepl(config$outputs$mcmc_wrapper, main_text, fixed = TRUE),
      "main article uses v14 MCMC wrapper")
check(grepl(config$outputs$vb_wrapper, supplement_text, fixed = TRUE),
      "supplement uses v14 VB wrapper")
check(!grepl("v12_mcmc_metric_interval_figures", main_text, fixed = TRUE),
      "main article no longer uses v12 MCMC wrapper")
check(!grepl("v12_vb_metric_interval_figures", supplement_text, fixed = TRUE),
      "supplement no longer uses v12 VB wrapper")

manifest_path <- article_path(config$outputs$manifest)
check(file.exists(manifest_path), "manifest exists")
manifest <- readLines(manifest_path, warn = FALSE)
check(any(manifest == "pdf_container=cairo_png_300dpi_image_pdf"),
      "manifest records the image-PDF contract")
check(any(manifest == "pdf_render_process_isolation=one_r_process_per_figure"),
      "manifest records process-isolated rendering")
check(any(manifest == "pdf_repeat_renderer=pdftocairo"),
      "manifest records stable repeat renderer")
check(any(manifest == "pdf_repeat_render_hash_stable=true"),
      "manifest records repeat-render gate")
hash_lines <- grep("\\|sha256=", manifest, value = TRUE)
check(length(hash_lines) == 18L, "manifest file count")
for (line in hash_lines) {
  fields <- strsplit(line, "\\|sha256=")[[1L]]
  check(length(fields) == 2L, paste(line, "manifest syntax"))
  path <- article_path(fields[[1L]])
  check(file.exists(path), paste(fields[[1L]], "manifest file exists"))
  check(identical(sha256(path), fields[[2L]]), paste(fields[[1L]], "manifest hash"))
}

cat(sprintf("INDEPENDENT_DGP_ORACLE_FIGURES_V14_CHECK=PASS checks=%d\n", check_count))
