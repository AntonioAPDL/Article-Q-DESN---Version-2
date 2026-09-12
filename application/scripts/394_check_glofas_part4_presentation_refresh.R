#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- sub("^--file=", "", script_arg[[1L]])
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  source_tag = "glofas_part4_joint_al_sweep10_20260911",
  output_tag = "glofas_part4_joint_al_sweep10_presentation_v2_20260911"
))
source_tag <- trimws(as.character(args$source_tag)[[1L]])
output_tag <- trimws(as.character(args$output_tag)[[1L]])
table_path <- function(stem, tag = output_tag, ext = "csv") {
  app_path("tables", paste0(stem, "__", tag, ".", ext))
}
figure_path <- function(stem, diagnostics = FALSE) {
  pieces <- c("figures", "glofas_application")
  if (diagnostics) pieces <- c(pieces, "diagnostics")
  do.call(app_path, as.list(c(pieces, paste0(stem, "__", output_tag, ".pdf"))))
}

paths <- c(
  source_scores = table_path("glofas_application_part4_forecast_scores", source_tag),
  source_manifest = table_path("glofas_application_part4_publication_manifest", source_tag),
  main_table = table_path("glofas_application_part4_main_scores", ext = "tex"),
  supplement_table = table_path("glofas_application_part4_supplementary_scores", ext = "tex"),
  historical_table = table_path("glofas_application_part4_historical_guardrail", ext = "tex"),
  output_registry = table_path("glofas_application_part4_current_outputs", ext = "tex"),
  main_figure = figure_path("glofas_part4_joint_al_last30_issued28"),
  normal_figure = figure_path("glofas_part4_normal_comparison", TRUE),
  independent_figure = figure_path("glofas_part4_independent_quantile_comparison", TRUE),
  joint_figure = figure_path("glofas_part4_joint_quantile_comparison", TRUE),
  manifest = table_path("glofas_application_part4_presentation_manifest")
)
missing <- paths[!file.exists(paths)]
if (length(missing)) {
  stop("Missing presentation files: ", paste(missing, collapse = ", "), call. = FALSE)
}

expected_score_hash <- "829d4467e4b734d4cd7a0dbab40ba72fe9b9c91c328908461f82f3093167d498"
if (!identical(tolower(app_sha256_file(paths[["source_scores"]])), expected_score_hash)) {
  stop("The frozen score ledger hash changed.", call. = FALSE)
}

manifest <- read.csv(paths[["manifest"]], stringsAsFactors = FALSE)
if (nrow(manifest) != 12L || anyDuplicated(manifest$relative_path) ||
    any(!manifest$article_safe) ||
    any(grepl("(^|/)local_trackers/|application/cache/|\\.(rds|rda|RData|log)$", manifest$relative_path))) {
  stop("The presentation manifest violates its article-only contract.", call. = FALSE)
}
reproduction_rows <- manifest$publication_role == "reproduction_code"
if (sum(reproduction_rows) != 2L || any(manifest$overleaf_publish[reproduction_rows]) ||
    any(!manifest$overleaf_publish[!reproduction_rows])) {
  stop("The presentation manifest has invalid reproduction/publication flags.", call. = FALSE)
}
manifest_paths <- file.path(repo_root, manifest$relative_path)
if (any(!file.exists(manifest_paths))) stop("A presentation manifest target is missing.", call. = FALSE)
observed_hashes <- vapply(manifest_paths, app_sha256_file, character(1L))
if (any(tolower(observed_hashes) != tolower(manifest$sha256))) {
  stop("The presentation manifest hashes do not verify.", call. = FALSE)
}

scores <- read.csv(paths[["source_scores"]], stringsAsFactors = FALSE)
main_families <- c(
  "Joint AL", "Independent AL", "Independent exAL",
  "Normal Ridge", "Normal RHS/VB", "Raw GloFAS"
)
if (!all(main_families %in% scores$family) || any(scores$n_scored_horizons != 28L)) {
  stop("The main comparison families or common horizon count changed.", call. = FALSE)
}

read_text <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")
main_table <- read_text(paths[["main_table"]])
supplement_table <- read_text(paths[["supplement_table"]])
historical_table <- read_text(paths[["historical_table"]])
registry <- read_text(paths[["output_registry"]])

for (label in c(
  "Joint AL Q--DESN (selected)", "Independent AL Q--DESN",
  "Independent exAL Q--DESN", "Normal Ridge DESN", "Normal RHS/VB DESN",
  "Raw GloFAS"
)) {
  if (!grepl(label, main_table, fixed = TRUE)) stop("Main table omits: ", label, call. = FALSE)
}
if (grepl("Joint exAL", main_table, fixed = TRUE) || !grepl("\\aCRPS", main_table, fixed = TRUE) ||
    grepl(" & CRPS & ", main_table, fixed = TRUE) || grepl("dagger|\\\\dagger", main_table)) {
  stop("The main table has an invalid family, score label, or marker.", call. = FALSE)
}
if (!grepl("Joint exAL", supplement_table, fixed = TRUE) ||
    !grepl("Sensitivity; fit not qualified", supplement_table, fixed = TRUE) ||
    !grepl("\\aCRPS", supplement_table, fixed = TRUE) ||
    grepl("CPU|runtime|source_fit_not_qualified", supplement_table)) {
  stop("The supplementary score table does not preserve the reader-facing sensitivity boundary.", call. = FALSE)
}
if (!grepl("FR09 \\(\\aCRPS\\)", historical_table, fixed = TRUE) ||
    !grepl("Part 4 Joint AL \\(\\aCRPS\\)", historical_table, fixed = TRUE) ||
    grepl(" CRPS", historical_table, fixed = TRUE)) {
  stop("The historical guardrail has inconsistent score terminology.", call. = FALSE)
}

expected_values <- list(
  "Joint AL" = c(0.4180, 5.3889, 0.8374, 0.929, 41.7),
  "Independent AL" = c(0.4292, 5.4239, 0.8606, 0.929, 40.1),
  "Independent exAL" = c(0.5227, 6.6540, 1.0478, 0.750, 27.0),
  "Normal Ridge" = c(0.4334, 13.8539, 0.8062, 0.250, 43.9),
  "Normal RHS/VB" = c(0.5077, 16.6741, 0.9412, 0.179, 34.5),
  "Raw GloFAS" = c(0.7713, 24.5037, 1.4360, 0.000, NA_real_)
)
for (family in names(expected_values)) {
  row <- scores[scores$family == family, , drop = FALSE]
  observed <- c(
    round(row$mean_check_loss, 4), round(row$interval_score, 4),
    round(row$crps_grid_log1p, 4), round(row$coverage90, 3),
    if (family == "Raw GloFAS") NA_real_ else round(100 * row$crps_reduction_vs_raw, 1)
  )
  if (!isTRUE(all.equal(observed, expected_values[[family]], check.attributes = FALSE))) {
    stop("Unexpected displayed values for ", family, call. = FALSE)
  }
}
if (any(scores$n_scored_horizons != 28L) ||
    !identical(scores$numerical_status[scores$family == "Joint AL"], "cap_stabilized_after_rhs_release") ||
    !identical(scores$numerical_status[scores$family == "Joint exAL"], "source_fit_not_qualified")) {
  stop("The score horizon or numerical qualification changed.", call. = FALSE)
}

required_registry_macros <- c(
  "GlofasApplicationCurrentScoreTable", "GlofasApplicationCurrentForecastWindowFigure",
  "GlofasApplicationCurrentSupplementScoreTable", "GlofasApplicationCurrentHistoricalGuardrailTable",
  "GlofasApplicationCurrentNormalComparisonFigure",
  "GlofasApplicationCurrentIndependentComparisonFigure", "GlofasApplicationCurrentJointComparisonFigure"
)
for (macro in required_registry_macros) {
  if (length(gregexpr(paste0("\\\\newcommand\\{\\\\", macro, "\\}"), registry, perl = TRUE)[[1L]]) != 1L ||
      gregexpr(paste0("\\\\newcommand\\{\\\\", macro, "\\}"), registry, perl = TRUE)[[1L]][[1L]] < 0L) {
    stop("Output registry is missing or duplicates: ", macro, call. = FALSE)
  }
}
if (grepl("local_trackers", registry, fixed = TRUE)) {
  stop("The output registry exposes a runtime path.", call. = FALSE)
}

for (path in paths[c("main_figure", "normal_figure", "independent_figure", "joint_figure")]) {
  info <- suppressWarnings(system2("pdfinfo", path, stdout = TRUE, stderr = TRUE))
  if (!any(grepl("^Pages:[[:space:]]+1$", info))) {
    stop("A presentation figure is not a one-page PDF: ", path, call. = FALSE)
  }
  images <- suppressWarnings(system2("pdfimages", c("-list", path), stdout = TRUE, stderr = TRUE))
  image_rows <- grep("^[[:space:]]*[0-9]+[[:space:]]+[0-9]+", images, value = TRUE)
  if (length(image_rows)) stop("A presentation figure contains raster images: ", path, call. = FALSE)
}

builder <- read_text(app_path("application/scripts/393_build_glofas_part4_presentation_refresh.R"))
for (token in c(
  'forest <- "#1B5E3C"', 'orange <- "#A64B00"',
  '"USGS observed through origin" = 16', '"USGS withheld for scoring" = 1',
  'linetype = "dashed"', 'linetype = "22"', 'name = "Probability level"',
  'alpha = "Issued GloFAS members"', 'alpha = "Retrospective GloFAS"'
)) {
  if (!grepl(token, builder, fixed = TRUE)) stop("Builder omits visual contract token: ", token, call. = FALSE)
}

health <- data.frame(
  check = c(
    "frozen_score_hash", "presentation_manifest", "main_six_family_table",
    "joint_exal_supplement_boundary", "acrps_visible_terminology",
    "displayed_score_values", "twenty_eight_horizon_contract",
    "output_registry", "one_page_vector_figures", "source_visual_grammar"
  ),
  status = "pass",
  stringsAsFactors = FALSE
)
print(health, row.names = FALSE)
cat("GLOFAS_PART4_PRESENTATION_REFRESH_VERIFY_PASS 10/10\n")
