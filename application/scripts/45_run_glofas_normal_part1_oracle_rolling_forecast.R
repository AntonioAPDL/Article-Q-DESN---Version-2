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
  runtime_root = "local_trackers/runtime_configs/glofas_normal_part1_oracle_realized_rolling_20260902",
  run_label = "part1_usgs_current_winner_oracle_rolling",
  target = "usgs",
  method = "rhs",
  rank = "1",
  candidate_id = "",
  rhs_candidate_id = "normal_rhs_top10_03_part1wide_0150_D1_n3000__Y360_X180__a050_r090__tau1",
  horizons = "1,7,14,30,60,90",
  tail_days = "365",
  stride_days = "30",
  max_origins = "Inf",
  max_iter = "",
  min_iter = "",
  tol = "",
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
horizons <- as.integer(strsplit(as.character(args$horizons), ",", fixed = TRUE)[[1L]])
max_origins <- suppressWarnings(as.numeric(args$max_origins))
max_iter <- if (nzchar(as.character(args$max_iter))) as.integer(args$max_iter) else NULL
min_iter <- if (nzchar(as.character(args$min_iter))) as.integer(args$min_iter) else NULL
tol <- if (nzchar(as.character(args$tol))) as.numeric(args$tol) else NULL
forecast_mode <- as.character(args$forecast_mode)
n_draws <- as.integer(args$n_draws)
seed <- as.integer(args$seed)
retain_draws <- tolower(as.character(args$retain_draws)) %in% c("true", "1", "yes", "y")

result <- app_glofas_oracle_forecast_part1_rolling(
  base_cfg = cfg,
  candidate_row = candidate,
  horizons = horizons,
  tail_days = as.integer(args$tail_days),
  stride_days = as.integer(args$stride_days),
  max_origins = max_origins,
  target = as.character(args$target),
  method = as.character(args$method),
  forecast_mode = forecast_mode,
  n_draws = n_draws,
  seed = seed,
  retain_draws = retain_draws,
  max_iter = max_iter,
  min_iter = min_iter,
  tol = tol
)

root <- normalizePath(args$runtime_root, mustWork = FALSE)
app_ensure_dir(file.path(root, "tables"))
app_ensure_dir(file.path(root, "objects"))
app_write_csv(result$plan, file.path(root, "tables", paste0(args$run_label, "_origin_plan.csv")))
app_write_csv(result$details, file.path(root, "tables", paste0(args$run_label, "_forecast_detail.csv")))
app_write_csv(result$summary, file.path(root, "tables", paste0(args$run_label, "_forecast_summary.csv")))
saveRDS(result, file.path(root, "objects", paste0(args$run_label, "_rolling_result.rds")), version = 2L)

message("Oracle-realized rolling-origin forecast complete.")
message(sprintf("Runtime root: %s", root))
message(sprintf("Summary: %s", file.path(root, "tables", paste0(args$run_label, "_forecast_summary.csv"))))
