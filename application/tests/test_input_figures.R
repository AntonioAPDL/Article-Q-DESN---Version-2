tmp_root <- tempfile("qdesn_figures_")
dir.create(tmp_root, recursive = TRUE)
tmp_cache <- file.path(tmp_root, "cache")
tmp_runs <- file.path(tmp_root, "runs")
dir.create(tmp_cache, recursive = TRUE)
dir.create(tmp_runs, recursive = TRUE)

toy_panel <- data.frame(
  origin_date = c(as.Date("2021-01-01") + 0:11, rep(as.Date("2021-01-10"), 6), rep(as.Date("2021-01-11"), 6)),
  target_date = c(as.Date("2021-01-01") + 0:11, rep(as.Date("2021-01-11") + 0:2, each = 2), rep(as.Date("2021-01-12") + 0:2, each = 2)),
  horizon = c(rep(0L, 12), rep(1:3, each = 2), rep(1:3, each = 2)),
  member = c(rep(NA_character_, 12), rep(c("m01", "m02"), 6)),
  is_retrospective = c(rep(TRUE, 12), rep(FALSE, 12)),
  is_ensemble = c(rep(FALSE, 12), rep(TRUE, 12)),
  y_reference = c(seq(10, 21), seq(20, 25), seq(21, 26)),
  g_glofas = c(seq(9, 20), seq(19, 24), seq(20, 25)),
  y_transformed = log1p(c(seq(10, 21), seq(20, 25), seq(21, 26))),
  g_transformed = log1p(c(seq(9, 20), seq(19, 24), seq(20, 25))),
  split = "toy",
  cutoff_id = "toy",
  stringsAsFactors = FALSE
)
panel_path <- file.path(tmp_cache, "application_panel.rds")
saveRDS(toy_panel, panel_path)

figure_specs <- list(
  version = 0.1,
  graphics = list(width = 5, height = 3.5),
  figures = list(
    input_coverage_timeline = list(enabled = TRUE, filename = "input_coverage_timeline.pdf", title = "Input coverage"),
    reference_glofas_retrospective_series = list(enabled = TRUE, filename = "reference_glofas_retrospective_series.pdf", title = "Series"),
    glofas_ensemble_fan_selected_origins = list(enabled = TRUE, filename = "glofas_ensemble_fan_selected_origins.pdf", title = "Fan", max_origins = 2),
    horizon_member_availability_heatmap = list(enabled = TRUE, filename = "horizon_member_availability_heatmap.pdf", title = "Availability"),
    reference_glofas_retrospective_scatter = list(enabled = TRUE, filename = "reference_glofas_retrospective_scatter.pdf", title = "Scatter"),
    retrospective_discrepancy_by_month = list(enabled = TRUE, filename = "retrospective_discrepancy_by_month.pdf", title = "Discrepancy"),
    cutoff_source_diagnostic = list(
      enabled = TRUE,
      cutoff_id = "toy_cutoff",
      filename = "cutoff_source_diagnostic.pdf",
      title = "Cutoff source",
      window_before_days = 9,
      window_after_days = 3,
      max_members = 2
    )
  )
)
figure_specs_path <- file.path(tmp_root, "figure_specs.yaml")
app_write_yaml(figure_specs, figure_specs_path)
cutoffs_path <- file.path(tmp_root, "cutoffs.csv")
app_write_csv(data.frame(
  cutoff_id = "toy_cutoff",
  origin_date = "2021-01-10",
  train_start = "2021-01-01",
  train_end = "2021-01-10",
  eval_start = "2021-01-11",
  eval_end = "2021-01-13",
  horizon_min = 1L,
  horizon_max = 3L,
  split = "toy",
  enabled = "true",
  notes = "toy cutoff",
  stringsAsFactors = FALSE
), cutoffs_path)

tmp_cfg <- cfg
tmp_cfg$paths$cache <- tmp_cache
tmp_cfg$paths$runs <- tmp_runs
tmp_cfg$paths$figure_specs <- figure_specs_path
tmp_cfg$paths$cutoffs <- cutoffs_path
tmp_cfg$paths$input_manifest <- tempfile("qdesn_fig_input_manifest_", fileext = ".csv")
tmp_cfg$.__config_path__ <- cfg$.__config_path__
app_write_csv(data.frame(
  input_id = "reference_gauge",
  source_name = "toy",
  source_type = "observation",
  local_path = tempfile(),
  upstream_reference = "toy",
  date_min = "2021-01-01",
  date_max = "2021-01-12",
  cutoff_date = NA,
  row_count = 12,
  column_count = 3,
  sha256 = NA,
  created_at = as.character(Sys.time()),
  notes = "toy",
  stringsAsFactors = FALSE
), tmp_cfg$paths$input_manifest)

run_dirs <- app_create_run_dirs(tmp_cfg, run_id = "test_input_figures")
manifest <- app_make_input_diagnostic_figures(tmp_cfg, toy_panel, run_dirs, source_script = "test_input_figures.R")
stopifnot(nrow(manifest) == 7L)
figure_paths <- ifelse(grepl("^/", manifest$output_path), manifest$output_path, file.path(app_repo_root(), manifest$output_path))
stopifnot(all(file.exists(figure_paths)))
stopifnot(file.exists(file.path(run_dirs$tables, "figure_manifest.csv")))
cutoff_summary <- app_read_csv(file.path(run_dirs$tables, "cutoff_source_figure_summary.csv"))
stopifnot(nrow(cutoff_summary) == 1L)
stopifnot(cutoff_summary$n_members[[1L]] == 2L)
stopifnot(cutoff_summary$origin_date[[1L]] == "2021-01-10")
