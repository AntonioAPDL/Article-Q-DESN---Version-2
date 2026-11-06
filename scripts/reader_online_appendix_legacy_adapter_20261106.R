# Compatibility for dated prose assertions, never scientific inputs.
# The successor independently validates the ACTUAL current documents, public
# assets, authority and role routing before returning any historical prose.
app_reader_appendix_adapter <- function(root) {
  root <- normalizePath(root, mustWork = TRUE)
  path <- file.path(root, "tables/independent_forecast_300_500_article_manifest_v1.json")
  receipt <- jsonlite::read_json(path, simplifyVector = FALSE)
  active <- !is.null(receipt$reader_appendix_20261106)
  allowed <- c("main.tex", "qdesn-supplement.tex", "refs.bib",
    "tables/qdesn_multiquantile_forecast_figure_display.tex",
    "tables/independent_train500_eval300_mcmc_figures_v1.tex",
    "tables/independent_train500_eval300_mcmc_mae_figure_v1.tex",
    "tables/independent_train500_eval500_mcmc_figures_v1.tex")
  if (active) {
    result <- system2("/usr/bin/python3.11", c("-I", "-B", shQuote(file.path(root,
      "scripts/refresh_reader_online_appendix_receipts_20261106.py")), "--root", shQuote(root), "--check"),
      stdout = TRUE, stderr = TRUE)
    if (!is.null(attr(result, "status"))) stop(paste(result, collapse = "\n"), call. = FALSE)
    message("READER_APPENDIX_CURRENT_SEMANTICS_VERIFIED; dated prose assertions use authenticated 637 fixtures; scientific inputs stay live.")
  }
  read <- function(relative) {
    if (active && relative %in% allowed) {
      result <- system2("git", c("--no-replace-objects", "-C", shQuote(root), "show",
        shQuote(paste0("6370677bf37204dd494db1b7f649d2ceb288f36b:", relative))), stdout = TRUE, stderr = TRUE)
      if (!is.null(attr(result, "status"))) stop("Authenticated historical prose fixture unavailable.", call. = FALSE)
      return(paste(result, collapse = "\n"))
    }
    paste(readLines(file.path(root, relative), warn = FALSE), collapse = "\n")
  }
  list(active = active, read = read)
}
