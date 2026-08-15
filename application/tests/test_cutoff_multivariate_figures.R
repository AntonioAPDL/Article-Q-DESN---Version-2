if (!exists("app_repo_root", mode = "function")) {
  args_all <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args_all, value = TRUE)
  repo_root <- if (length(file_arg)) {
    normalizePath(file.path(dirname(sub("^--file=", "", file_arg[[1L]])), "..", ".."), mustWork = TRUE)
  } else {
    normalizePath(".", mustWork = TRUE)
  }
  source(file.path(repo_root, "application/R/00_packages.R"))
  app_set_repo_root(repo_root)
}
if (!exists("app_make_glofas_multivariate_cutoff_figures", mode = "function")) {
  source(app_path("application/R/cutoff_multivariate_figures.R"))
}

tmp_root <- tempfile("qdesn_cutoff_multivariate_figures_")
source_root <- file.path(tmp_root, "frozen_inputs")
output_root <- file.path(tmp_root, "outputs")
dir.create(source_root, recursive = TRUE)

make_cutoff_bundle <- function(cutoff_date) {
  cutoff_date <- as.Date(cutoff_date)
  cutoff_dir <- file.path(source_root, app_cutoff_figure_slug(cutoff_date))
  dir.create(file.path(cutoff_dir, "retros"), recursive = TRUE)
  dir.create(file.path(cutoff_dir, "forecasts"), recursive = TRUE)
  dir.create(file.path(cutoff_dir, "inputs"), recursive = TRUE)

  hist_dates <- cutoff_date - 8:0
  retros <- data.frame(
    Date = hist_dates,
    USGS = seq(10, 18),
    GloFAS = seq(9, 17),
    `NWS3.0` = seq(8, 16),
    check.names = FALSE
  )
  app_write_csv(retros, file.path(cutoff_dir, "retros", "retros.csv"))

  future_dates <- cutoff_date + 1:6
  glofas <- data.frame(
    target_date = future_dates,
    member_001 = seq(18, 23),
    member_002 = seq(19, 24),
    member_003 = seq(20, 25),
    check.names = FALSE
  )
  nws <- data.frame(
    target_date = cutoff_date + 1:3,
    member_001 = c(18, 18.5, 19),
    member_002 = c(19, 19.5, 20),
    check.names = FALSE
  )
  app_write_csv(glofas, file.path(cutoff_dir, "forecasts", "glofas_forecast.csv"))
  app_write_csv(nws, file.path(cutoff_dir, "forecasts", "nws_forecast.csv"))
  app_write_csv(data.frame(
    date = cutoff_date + 1:10,
    discharge_cfs = seq(100, 109),
    discharge_cms = seq(18, 27),
    qualifiers = "",
    stringsAsFactors = FALSE
  ), file.path(cutoff_dir, "inputs", "usgs_daily.csv"))
  invisible(cutoff_dir)
}

make_cutoff_bundle("2021-01-10")
make_cutoff_bundle("2021-02-10")

cutoffs <- app_discover_multivariate_cutoff_dirs(source_root)
stopifnot(nrow(cutoffs) == 2L)
stopifnot(all(cutoffs$cutoff_date == as.Date(c("2021-01-10", "2021-02-10"))))

bundle <- app_load_multivariate_cutoff_bundle(cutoffs$cutoff_dir[[1L]])
stopifnot(nrow(bundle$forecast_long) == 24L)
stopifnot(all(c("GloFAS", "NWS") %in% unique(bundle$forecast_long$product)))
stopifnot(isTRUE(all.equal(bundle$retros$usgs[[1L]], log1p(10))))

result <- app_make_glofas_multivariate_cutoff_figures(
  source_root = source_root,
  output_root = output_root,
  prediction_run_id = NULL,
  before_days = 8,
  after_days = 6,
  transform = "log1p"
)

stopifnot(nrow(result$manifest) == 6L)
stopifnot(nrow(result$validation) == 2L)
stopifnot(all(file.exists(file.path(output_root, "tables", c("cutoff_figure_manifest.csv", "cutoff_figure_validation.csv")))))
figure_paths <- ifelse(
  grepl("^/", result$manifest$output_path),
  result$manifest$output_path,
  file.path(app_repo_root(), result$manifest$output_path)
)
stopifnot(all(file.exists(figure_paths)))
stopifnot(all(!result$validation$qdesn_overlay_available))
stopifnot(all(!result$validation$pre_cutoff_quantile_history_available))
stopifnot(all(result$validation$max_glofas_horizon == 6L))
stopifnot(all(result$validation$max_nws_horizon == 3L))
