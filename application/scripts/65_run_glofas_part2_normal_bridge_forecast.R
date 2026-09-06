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
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_part2_bridge_forecast.R"))

default_source_root <- Sys.getenv(
  "APP_GLOFAS_JEREZ_SOURCE_ROOT",
  unset = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part2_rhs_jerez_20260904"
)
default_base_config <- file.path(
  default_source_root,
  "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml"
)
default_part2_rhs_runtime <- file.path(
  default_source_root,
  "local_trackers/runtime_configs/glofas_normal_part2_rhs_top50_jerez_recovery_20260904"
)

args <- app_parse_args(list(
  base_config = default_base_config,
  rhs_runtime_root = default_part2_rhs_runtime,
  runtime_root = "local_trackers/runtime_configs/glofas_part2_bridge_forecast_chain_jerez_20260904/normal_rhs_vb",
  run_label = "part2_normal_rhs_vb_bridge_forecast",
  method = "rhs",
  rhs_candidate_id = "",
  candidate_id = "",
  rank = "1",
  origin_date = "",
  horizon_days = "30",
  forecast_mode = "draw_recursive",
  n_draws = "500",
  seed = "20260904",
  retain_draws = "false",
  forecast_backend = "auto",
  progress_every = "",
  strict_winner = "true",
  require_future_retrospective = "false"
))

truthy <- function(x) tolower(as.character(x)[[1L]]) %in% c("true", "1", "yes", "y")

cfg <- app_read_config(app_glofas_part2_bridge_resolve(args$base_config, must_work = TRUE))
rhs_row <- app_glofas_part2_bridge_selected_rhs_row(
  rhs_runtime_root = args$rhs_runtime_root,
  rhs_candidate_id = if (nzchar(as.character(args$rhs_candidate_id))) as.character(args$rhs_candidate_id) else NULL,
  candidate_id = if (nzchar(as.character(args$candidate_id))) as.character(args$candidate_id) else NULL,
  rank = as.integer(args$rank)
)

origin_date <- if (nzchar(as.character(args$origin_date))) as.Date(args$origin_date) else NULL
progress_every <- if (nzchar(as.character(args$progress_every))) as.integer(args$progress_every) else NULL

result <- app_glofas_part2_bridge_normal_forecast(
  base_cfg = cfg,
  rhs_runtime_root = args$rhs_runtime_root,
  rhs_row = rhs_row,
  method = as.character(args$method),
  origin_date = origin_date,
  horizon_days = as.integer(args$horizon_days),
  forecast_mode = as.character(args$forecast_mode),
  n_draws = as.integer(args$n_draws),
  seed = as.integer(args$seed),
  retain_draws = truthy(args$retain_draws),
  forecast_backend = as.character(args$forecast_backend),
  progress_every = progress_every,
  strict_winner = truthy(args$strict_winner),
  require_future_retrospective = truthy(args$require_future_retrospective)
)

written <- app_glofas_part2_bridge_write_normal_result(
  result = result,
  root = args$runtime_root,
  run_label = as.character(args$run_label)
)

message("Part 2 Normal bridge forecast complete.")
message(sprintf("Runtime root: %s", written$root))
message(sprintf("Summary: %s", file.path(written$root, "tables", paste0(args$run_label, "_summary.csv"))))
message(sprintf("Figures: %s", paste(written$figures, collapse = "; ")))
