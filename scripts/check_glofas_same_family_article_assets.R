#!/usr/bin/env Rscript
# Reauthenticate source packets; verify exact tables, CSV values and PDF membership.
source("scripts/build_glofas_same_family_article_assets.R")

gsaa_pdf_geometry <- function(path, main = FALSE) {
  text <- system2("pdftotext", c("-bbox", shQuote(path), "-"), stdout = TRUE, stderr = TRUE)
  gsaa_require(is.null(attr(text, "status")), "PDF text bounds could not be inspected")
  page <- grep("<page width=", text, value = TRUE)
  dimensions <- regmatches(page, regexec('width="([0-9.]+)" height="([0-9.]+)"', page))[[1L]]
  gsaa_require(length(page) == 1L && length(dimensions) == 3L, "one PDF page geometry required")
  width <- as.numeric(dimensions[2L]);height <- as.numeric(dimensions[3L])
  pattern <- '<word xMin="([0-9.-]+)" yMin="([0-9.-]+)" xMax="([0-9.-]+)" yMax="([0-9.-]+)">(.*)</word>'
  matches <- lapply(grep("<word ", text, value = TRUE), function(line) regmatches(line, regexec(pattern, line))[[1L]])
  gsaa_require(length(matches) > 0L && all(lengths(matches) == 6L), "readable PDF word boxes required")
  b <- data.frame(xmin = vapply(matches, function(x) as.numeric(x[2L]), numeric(1L)),
    ymin = vapply(matches, function(x) as.numeric(x[3L]), numeric(1L)),
    xmax = vapply(matches, function(x) as.numeric(x[4L]), numeric(1L)),
    ymax = vapply(matches, function(x) as.numeric(x[5L]), numeric(1L)),
    word = vapply(matches, `[`, character(1L), 6L), stringsAsFactors = FALSE)
  gsaa_require(all(is.finite(as.matrix(b[1:4]))) && all(b$xmin >= -.05 & b$ymin >= -.05 &
    b$xmax <= width + .05 & b$ymax <= height + .05), "figure text extends outside its page")
  if (nrow(b) > 1L) for (i in seq_len(nrow(b) - 1L)) for (j in seq.int(i + 1L, nrow(b))) {
    dx <- min(b$xmax[i], b$xmax[j]) - max(b$xmin[i], b$xmin[j])
    dy <- min(b$ymax[i], b$ymax[j]) - max(b$ymin[i], b$ymin[j])
    gsaa_require(dx <= .6 || dy <= .6, paste0("figure text overlaps: ", b$word[i], " / ", b$word[j]))
  }
  # Horizontal word height follows the embedded Nimbus font point size. Exclude
  # the shared rotated ordinate label and tall rotated words, not small tick text.
  horizontal <- b$xmin >= 24 & b$ymax - b$ymin <= 20
  scale <- (if (main) .94 else .98) * 6.5 * 72 / width
  effective <- (b$ymax[horizontal] - b$ymin[horizontal]) * scale
  gsaa_require(length(effective) > 0L && all(effective >= 8),
    "figure lettering is smaller than eight points at manuscript insertion size")
  if (main) {
    legend <- b[b$word == "Quantile", ];date <- b[b$word == "Date", ]
    gsaa_require(nrow(legend) == 1L && nrow(date) == 1L && legend$ymin > date$ymax + 1.5,
      "main quantile legend overlaps the date axis")
  }
  invisible(list(width = width, height = height, effective_minimum_points = min(effective), boxes = b))
}

gsaa_check <- function(packet_root, packet_manifest_sha256, extraction_root, extraction_manifest_sha256,
    fitted_history_root, fitted_history_manifest_sha256, convergence_pin, candidate_root,
    derived_metrics_root = NULL, derived_metrics_manifest_sha256 = NULL) {
  z <- gsaa_inputs(packet_root, packet_manifest_sha256, extraction_root, extraction_manifest_sha256,
    fitted_history_root, fitted_history_manifest_sha256, convergence_pin, derived_metrics_root, derived_metrics_manifest_sha256)
  root <- normalizePath(candidate_root, mustWork = TRUE)
  m <- read.csv(file.path(root, gsaa_manifest_relative()), stringsAsFactors = FALSE)
  gsaa_require(identical(names(m), c("relative_path", "size_bytes", "sha256")) &&
    identical(m$relative_path, gsaa_expected_files()) &&
    setequal(list.files(root, recursive = TRUE, all.files = TRUE), c(gsaa_expected_files(), gsaa_manifest_relative())),
    "exact article-safe candidate membership required")
  for (i in seq_len(nrow(m))) gsc_pin(list(path = file.path(root, m$relative_path[i]),
    size_bytes = m$size_bytes[i], sha256 = m$sha256[i]), 8 * 1024^2)
  d <- jsonlite::read_json(file.path(root, gsaa_decision_relative()), simplifyVector = FALSE)
  gsaa_require(identical(d$status, "COMPLETE_ARTICLE_ASSET_CANDIDATE_NOT_AUTHORITY") &&
    identical(d$article_publication_authorized, FALSE) && d$new_fits == 0 && d$source_models_opened == 0 &&
    all(vapply(d[c("isotonic_adjustment", "clipping_or_smoothing", "added_credible_ribbons", "extra_response_noise_added")],
      identical, logical(1L), FALSE)) &&
    identical(jsonlite::toJSON(d$lineage, auto_unbox = TRUE, null = "null"),
      jsonlite::toJSON(z$lineage, auto_unbox = TRUE, null = "null")) &&
    d$forecast_rows == 1372 && d$historical_fitted_rows == 1260 && d$issued_member_rows == 1428,
    "candidate authority, source lineage or functional changed")
  t <- file.path(root, "tables", gsaa_prefix());tables <- gsaa_tables(z)
  for (name in names(tables)) gsaa_require(identical(readLines(paste0(t, "_", name, ".tex")), tables[[name]]),
    "candidate table labels or values changed")
  gsaa_require(identical(readLines(paste0(t, "_display_aliases.tex")), gsaa_aliases(z)), "candidate aliases changed")
  expected <- list(family_metrics = z$metrics$family_metrics, date_metrics = z$metrics$date_metrics,
    calibration = z$metrics$calibration, convergence = z$convergence[, c("family", "tau", "numerical_gates_pass", "iterations",
      "outer_iterations", "terminal_consecutive_passes", "wall_seconds", "cpu_seconds", "max_rss_bytes")],
    quantile_paths = z$rows[, c("family", "target_date", "horizon", "tau", "quantile_transformed", "quantile")],
    fitted_history = z$fitted, history = z$history, issued_members = z$members,
    observations = z$truth[, c("target_date", "horizon", "y_transformed")])
  for (name in names(expected)) {
    observed <- read.csv(paste0(t, "_", name, ".csv"), stringsAsFactors = FALSE, na.strings = "")
    gsaa_require(isTRUE(all.equal(observed, expected[[name]], check.attributes = FALSE, tolerance = 2e-12)),
      "candidate numerical/source CSV differs")
  }
  gsaa_require(identical(as.character(unlist(d$style$quantiles)), gsaa_style()$quantiles), "quantile color palette changed")
  gsaa_require(abs(d$style$quantile_line_mm - .15) < 1e-12 && abs(d$style$quantile_lwd - .57) < 1e-12,
    "quantile paths are no longer the requested thin lines")
  gsaa_require(all(nzchar(Sys.which(c("pdfinfo", "pdffonts", "pdfimages", "pdftotext")))),
    "Poppler PDF page/font/image checks required")
  for (relative in m$relative_path[grepl("\\.pdf$", m$relative_path)]) {
    info <- system2("pdfinfo", shQuote(file.path(root, relative)), stdout = TRUE, stderr = TRUE)
    gsaa_require(is.null(attr(info, "status")) && any(grepl("^Pages:[[:space:]]+1$", info)),
      "candidate figure must be a valid one-page PDF")
    fonts <- system2("pdffonts", shQuote(file.path(root, relative)), stdout = TRUE, stderr = TRUE)
    fonts <- fonts[seq_along(fonts) > 2L]
    gsaa_require(length(fonts) > 0L && all(vapply(fonts, function(line) {
      fields <- strsplit(trimws(line), "[[:space:]]+")[[1L]]
      length(fields) >= 8L && identical(fields[length(fields) - 4L], "yes")
    }, logical(1L))), "every figure font must be embedded")
    images <- system2("pdfimages", c("-list", shQuote(file.path(root, relative))), stdout = TRUE, stderr = TRUE)
    gsaa_require(is.null(attr(images, "status")) && !any(grepl("^[[:space:]]*[0-9]+[[:space:]]", images)),
      "article figures must remain vector graphics without embedded raster images")
    gsaa_pdf_geometry(file.path(root, relative), main = endsWith(relative, "_main.pdf"))
  }
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(TRUE)
  gsaa_require(length(a) %in% c(18L, 22L) && identical(a[seq(1L, 17L, 2L)],
    c("--packet", "--packet-manifest-sha256", "--extraction", "--extraction-manifest-sha256",
      "--fitted-history", "--fitted-history-manifest-sha256", "--convergence", "--convergence-sha256", "--candidate")),
    "exact authenticated asset-check interfaces required")
  v <- a[seq(2L, 18L, 2L)];pin <- list(path = v[7L], size_bytes = as.numeric(file.info(v[7L])$size), sha256 = v[8L])
  optional <- if (length(a) == 22L) {
    gsaa_require(identical(a[c(19L, 21L)], c("--derived-metrics", "--derived-metrics-manifest-sha256")), "derived metrics options differ")
    list(derived_metrics_root = a[20L], derived_metrics_manifest_sha256 = a[22L])
  } else list()
  do.call(gsaa_check, c(list(v[1L], v[2L], v[3L], v[4L], v[5L], v[6L], pin, v[9L]), optional))
  cat("GLOFAS_ARTICLE_ASSETS_VERIFIED_NOT_PUBLICATION\n")
}
