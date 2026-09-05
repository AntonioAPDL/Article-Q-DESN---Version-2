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
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_part1_quantile_oracle_forecast.R"))

args <- app_parse_args(list(
  config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_p50_20260829/source/fr09_config_p50.yaml",
  score_path = "local_trackers/runtime_configs/glofas_normal_rhs_top10_vb_20260901/tables/normal_rhs_scores_latest.csv",
  runtime_root = "local_trackers/runtime_configs/glofas_part1_quantile_oracle_forecast_20260903",
  run_label = "part1_usgs_quantile_oracle_forecast",
  target = "usgs",
  model_family = "independent_al",
  quantile = "0.50",
  rank = "1",
  candidate_id = "",
  rhs_candidate_id = "normal_rhs_top10_03_part1wide_0150_D1_n3000__Y360_X180__a050_r090__tau1",
  origin_date = "",
  horizon_days = "30",
  max_iter = "100",
  tol = "0",
  min_iter = "1",
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
  progress_every = "0",
  forecast_backend = "auto"
))

parse_numeric_csv <- function(x) {
  x <- trimws(as.character(x)[[1L]])
  if (!nzchar(x) || identical(tolower(x), "all7")) return(app_glofas_part1_quantile_grid())
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

cfg <- app_read_config(app_glofas_oracle_resolve_repo_path(args$config))
candidate <- app_glofas_oracle_part1_candidate_from_scores(
  score_path = args$score_path,
  rhs_candidate_id = if (nzchar(as.character(args$rhs_candidate_id))) args$rhs_candidate_id else NULL,
  candidate_id = if (nzchar(as.character(args$candidate_id))) args$candidate_id else NULL,
  rank = as.integer(args$rank)
)

tau <- parse_numeric_csv(args$quantile)
origin_date <- if (nzchar(as.character(args$origin_date))) as.Date(args$origin_date) else NULL
horizon_days <- if (nzchar(as.character(args$horizon_days))) as.integer(args$horizon_days) else NULL
max_iter <- as.integer(args$max_iter)
tol <- as.numeric(args$tol)
min_iter <- as.integer(args$min_iter)
tau0 <- parse_optional_numeric(args$tau0, default = NULL)
zeta2 <- parse_optional_numeric(args$zeta2, default = Inf)
a_sigma <- parse_optional_numeric(args$a_sigma, default = 2)
b_sigma <- parse_optional_numeric(args$b_sigma, default = 1)
alpha_prior_sd <- parse_optional_numeric(args$alpha_prior_sd, default = Inf)
max_dense_dim <- if (nzchar(as.character(args$max_dense_dim))) as.integer(args$max_dense_dim) else NULL
rhs_vb_inner <- as.integer(args$rhs_vb_inner)
exal_prefit_max_iter <- as.integer(args$exal_prefit_max_iter)
progress_every <- as.integer(args$progress_every)

if (!is.finite(max_iter) || max_iter < 1L) stop("--max_iter must be positive.", call. = FALSE)
if (!is.finite(tol) || tol < 0) stop("--tol must be finite and nonnegative.", call. = FALSE)
if (!is.finite(min_iter) || min_iter < 1L) stop("--min_iter must be positive.", call. = FALSE)
if (!is.finite(rhs_vb_inner) || rhs_vb_inner < 1L) stop("--rhs_vb_inner must be positive.", call. = FALSE)
if (!is.finite(exal_prefit_max_iter) || exal_prefit_max_iter < 0L) {
  stop("--exal_prefit_max_iter must be nonnegative.", call. = FALSE)
}
if (!is.finite(progress_every) || progress_every < 0L) {
  stop("--progress_every must be nonnegative.", call. = FALSE)
}

init_fit_path <- if (nzchar(as.character(args$init_fit_path))) as.character(args$init_fit_path) else NULL
init_fit_paths <- if (nzchar(as.character(args$init_fit_paths))) as.character(args$init_fit_paths) else NULL
progress_path <- if (nzchar(as.character(args$progress_path))) as.character(args$progress_path) else NULL

result <- app_glofas_part1_quantile_oracle_forecast(
  base_cfg = cfg,
  candidate_row = candidate,
  model_family = as.character(args$model_family),
  tau = tau,
  origin_date = origin_date,
  horizon_days = horizon_days,
  target = as.character(args$target),
  max_iter = max_iter,
  tol = tol,
  min_iter = min_iter,
  tau0 = tau0,
  zeta2 = zeta2,
  a_sigma = a_sigma,
  b_sigma = b_sigma,
  alpha_prior_sd = alpha_prior_sd,
  max_dense_dim = max_dense_dim,
  rhs_vb_inner = rhs_vb_inner,
  exal_method_id = as.character(args$exal_method_id),
  exal_prefit_max_iter = exal_prefit_max_iter,
  joint_backend = as.character(args$joint_backend),
  init_fit_path = init_fit_path,
  init_fit_paths = init_fit_paths,
  progress_path = progress_path,
  progress_every = progress_every,
  forecast_backend = as.character(args$forecast_backend)
)

written <- app_glofas_part1_quantile_write_result(
  result = result,
  root = args$runtime_root,
  run_label = as.character(args$run_label)
)

message("Part 1 quantile oracle forecast complete.")
message(sprintf("Runtime root: %s", written$root))
message(sprintf("Summary: %s", file.path(written$root, "tables", paste0(args$run_label, "_summary.csv"))))
message(sprintf("Figures: %s", paste(written$figures, collapse = "; ")))
