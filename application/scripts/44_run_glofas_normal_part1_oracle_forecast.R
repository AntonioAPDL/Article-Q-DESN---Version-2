#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else ""
repo_root <- if (nzchar(script_path)) {
  normalizePath(file.path(dirname(normalizePath(script_path, mustWork = TRUE)), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(file.path(getwd()), mustWork = TRUE)
}
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_p50_20260829/source/fr09_config_p50.yaml",
  score_path = "local_trackers/runtime_configs/glofas_normal_rhs_top10_vb_20260901/tables/normal_rhs_scores_latest.csv",
  runtime_root = "local_trackers/runtime_configs/glofas_normal_part1_oracle_realized_forecast_20260902",
  run_label = "part1_usgs_current_winner_oracle_realized",
  target = "usgs",
  method = "rhs",
  rank = "1",
  candidate_id = "",
  rhs_candidate_id = "normal_rhs_top10_03_part1wide_0150_D1_n3000__Y360_X180__a050_r090__tau1",
  origin_date = "",
  horizon_days = "",
  max_iter = "",
  min_iter = "",
  tol = "",
  fit_object_path = "",
  reuse_fit = "true",
  forecast_backend = "auto",
  progress_every = "",
  forecast_mode = "plugin_mean_recursive",
  n_draws = "500",
  seed = "20260903",
  retain_draws = "false"
))

cfg <- app_read_config(app_glofas_oracle_resolve_repo_path(args$config))
candidate <- app_glofas_oracle_part1_candidate_from_scores(
  score_path = args$score_path,
  rhs_candidate_id = if (nzchar(as.character(args$rhs_candidate_id))) args$rhs_candidate_id else NULL,
  candidate_id = if (nzchar(as.character(args$candidate_id))) args$candidate_id else NULL,
  rank = as.integer(args$rank)
)
origin_date <- if (nzchar(as.character(args$origin_date))) as.Date(args$origin_date) else NULL
horizon_days <- if (nzchar(as.character(args$horizon_days))) as.integer(args$horizon_days) else NULL
max_iter <- if (nzchar(as.character(args$max_iter))) as.integer(args$max_iter) else NULL
min_iter <- if (nzchar(as.character(args$min_iter))) as.integer(args$min_iter) else NULL
tol <- if (nzchar(as.character(args$tol))) as.numeric(args$tol) else NULL
fit_object_path <- if (nzchar(as.character(args$fit_object_path))) as.character(args$fit_object_path) else NULL
reuse_fit <- tolower(as.character(args$reuse_fit)) %in% c("true", "1", "yes", "y")
forecast_backend <- as.character(args$forecast_backend)
progress_every <- if (nzchar(as.character(args$progress_every))) as.integer(args$progress_every) else NULL
forecast_mode <- as.character(args$forecast_mode)
n_draws <- as.integer(args$n_draws)
seed <- as.integer(args$seed)
retain_draws <- tolower(as.character(args$retain_draws)) %in% c("true", "1", "yes", "y")

result <- app_glofas_oracle_forecast_part1_single(
  base_cfg = cfg,
  candidate_row = candidate,
  origin_date = origin_date,
  horizon_days = horizon_days,
  target = as.character(args$target),
  method = as.character(args$method),
  forecast_mode = forecast_mode,
  n_draws = n_draws,
  seed = seed,
  retain_draws = retain_draws,
  max_iter = max_iter,
  min_iter = min_iter,
  tol = tol,
  fit_object_path = fit_object_path,
  reuse_fit = reuse_fit,
  forecast_backend = forecast_backend,
  progress_every = progress_every
)
written <- app_glofas_oracle_write_result(
  result = result,
  root = args$runtime_root,
  run_label = as.character(args$run_label)
)

message("Oracle-realized forecast complete.")
message(sprintf("Runtime root: %s", written$root))
message(sprintf("Summary: %s", file.path(written$root, "tables", paste0(args$run_label, "_summary.csv"))))
message(sprintf("Figures: %s", paste(written$figures, collapse = "; ")))
