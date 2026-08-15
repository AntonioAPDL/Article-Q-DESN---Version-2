schema <- app_read_yaml(app_config_path(cfg, "schema"))
toy_panel <- data.frame(
  origin_date = as.Date(c("2026-01-01", "2026-01-01")),
  target_date = as.Date(c("2026-01-01", "2026-01-03")),
  horizon = c(0L, 2L),
  member = c(NA, "m01"),
  is_retrospective = c(TRUE, FALSE),
  is_ensemble = c(FALSE, TRUE),
  y_reference = c(1, 2),
  g_glofas = c(1.1, 2.1),
  y_transformed = c(1, 2),
  g_transformed = c(1.1, 2.1),
  split = c("train", "test"),
  cutoff_id = c("toy", "toy"),
  stringsAsFactors = FALSE
)
source(app_path("application/R/build_application_panel.R"))
app_validate_panel(toy_panel, schema)
