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
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))
source(app_path("application/R/joint_exqdesn_inference_dispatch.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_part1_quantile_oracle_forecast.R"))
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
  runtime_root = "local_trackers/runtime_configs/glofas_part2_bridge_forecast_chain_jerez_20260904/independent_al_q0p50",
  run_label = "part2_independent_al_q0p50_bridge_forecast",
  model_family = "independent_al",
  quantile = "0.50",
  rhs_candidate_id = "",
  candidate_id = "",
  rank = "1",
  origin_date = "",
  horizon_days = "30",
  max_iter = "100",
  min_iter = "30",
  tol = "0.01",
  tau0 = "",
  zeta2 = "Inf",
  a_sigma = "2",
  b_sigma = "1",
  alpha_prior_sd = "Inf",
  max_dense_dim = "",
  rhs_vb_inner = "5",
  exal_method_id = "VB1_structured_v",
  exal_prefit_max_iter = "25",
  joint_backend = "auto",
  init_fit_path = "",
  init_fit_paths = "",
  progress_path = "",
  progress_every = "1",
  freeze_beta_warmup_iters = "0",
  min_beta_updates = "0",
  forecast_backend = "auto",
  strict_winner = "true"
))

truthy <- function(x) tolower(as.character(x)[[1L]]) %in% c("true", "1", "yes", "y")

parse_numeric_csv <- function(x) {
  x <- trimws(as.character(x)[[1L]])
  if (!nzchar(x) || identical(tolower(x), "all7")) return(app_glofas_part2_bridge_quantile_grid())
  vals <- suppressWarnings(as.numeric(strsplit(gsub("[[:space:]]+", "", x), "[,;|]")[[1L]]))
  vals <- vals[is.finite(vals)]
  if (!length(vals)) stop("Could not parse --quantile.", call. = FALSE)
  vals
}

parse_optional_numeric <- function(x, default = NULL) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(default)
  if (identical(tolower(x), "inf")) return(Inf)
  val <- suppressWarnings(as.numeric(x))
  if (!is.finite(val) && !identical(val, Inf)) stop(sprintf("Expected finite numeric argument, got '%s'.", x), call. = FALSE)
  val
}

cfg <- app_read_config(app_glofas_part2_bridge_resolve(args$base_config, must_work = TRUE))
rhs_row <- app_glofas_part2_bridge_selected_rhs_row(
  rhs_runtime_root = args$rhs_runtime_root,
  rhs_candidate_id = if (nzchar(as.character(args$rhs_candidate_id))) as.character(args$rhs_candidate_id) else NULL,
  candidate_id = if (nzchar(as.character(args$candidate_id))) as.character(args$candidate_id) else NULL,
  rank = as.integer(args$rank)
)

origin_date <- if (nzchar(as.character(args$origin_date))) as.Date(args$origin_date) else NULL
max_dense_dim <- if (nzchar(as.character(args$max_dense_dim))) as.integer(args$max_dense_dim) else NULL
init_fit_path <- if (nzchar(as.character(args$init_fit_path))) as.character(args$init_fit_path) else NULL
init_fit_paths <- if (nzchar(as.character(args$init_fit_paths))) as.character(args$init_fit_paths) else NULL
progress_path <- if (nzchar(as.character(args$progress_path))) as.character(args$progress_path) else NULL

result <- app_glofas_part2_bridge_quantile_forecast(
  base_cfg = cfg,
  rhs_runtime_root = args$rhs_runtime_root,
  rhs_row = rhs_row,
  model_family = as.character(args$model_family),
  tau = parse_numeric_csv(args$quantile),
  origin_date = origin_date,
  horizon_days = as.integer(args$horizon_days),
  max_iter = as.integer(args$max_iter),
  min_iter = as.integer(args$min_iter),
  tol = as.numeric(args$tol),
  tau0 = parse_optional_numeric(args$tau0, default = NULL),
  zeta2 = parse_optional_numeric(args$zeta2, default = Inf),
  a_sigma = parse_optional_numeric(args$a_sigma, default = 2),
  b_sigma = parse_optional_numeric(args$b_sigma, default = 1),
  alpha_prior_sd = parse_optional_numeric(args$alpha_prior_sd, default = Inf),
  max_dense_dim = max_dense_dim,
  rhs_vb_inner = as.integer(args$rhs_vb_inner),
  exal_method_id = as.character(args$exal_method_id),
  exal_prefit_max_iter = as.integer(args$exal_prefit_max_iter),
  joint_backend = as.character(args$joint_backend),
  freeze_beta_warmup_iters = as.integer(args$freeze_beta_warmup_iters),
  min_beta_updates = as.integer(args$min_beta_updates),
  init_fit_path = init_fit_path,
  init_fit_paths = init_fit_paths,
  progress_path = progress_path,
  progress_every = as.integer(args$progress_every),
  forecast_backend = as.character(args$forecast_backend),
  strict_winner = truthy(args$strict_winner)
)

written <- app_glofas_part2_bridge_write_quantile_result(
  result = result,
  root = args$runtime_root,
  run_label = as.character(args$run_label)
)

message("Part 2 quantile bridge forecast complete.")
message(sprintf("Runtime root: %s", written$root))
message(sprintf("Summary: %s", file.path(written$root, "tables", paste0(args$run_label, "_summary.csv"))))
message(sprintf("Fit: %s", written$fit_path))
message(sprintf("Figures: %s", paste(written$figures, collapse = "; ")))
