if (!exists("app_glofas_oracle_forecast_part1_single", mode = "function", inherits = TRUE)) {
  script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else ""
  repo_root <- if (nzchar(script_path)) {
    normalizePath(file.path(dirname(normalizePath(script_path, mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    path <- normalizePath(getwd(), mustWork = TRUE)
    repeat {
      if (file.exists(file.path(path, "main.tex")) && dir.exists(file.path(path, "application"))) break
      parent <- dirname(path)
      if (identical(parent, path)) stop("Could not locate Article-Q-DESN repository root.", call. = FALSE)
      path <- parent
    }
    path
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
}

oracle_cfg <- list(
  data = list(transform = list(response = "identity", forecast = "identity")),
  covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
  feature_contract = list(),
  reservoir = list()
)

origin <- as.Date("2020-04-30")
history_dates <- seq.Date(as.Date("2020-01-01"), origin, by = "day")
future_dates <- seq.Date(origin + 1L, origin + 5L, by = "day")
all_cov_dates <- seq.Date(min(history_dates) - 5L, origin + 10L, by = "day")
toy_cov <- data.frame(
  date = all_cov_dates,
  ppt = cos(seq_along(all_cov_dates) / 7),
  soil = sin(seq_along(all_cov_dates) / 11),
  stringsAsFactors = FALSE
)
toy_timeline <- app_glofas_oracle_covariate_timeline(
  toy_cov,
  origin_date = origin,
  train_start = min(history_dates)
)
toy_y <- sin(seq_along(history_dates) / 5) + seq_along(history_dates) / 100
toy_panel <- data.frame(
  origin_date = history_dates,
  target_date = history_dates,
  horizon = 0L,
  member = NA_character_,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_reference = toy_y,
  g_glofas = toy_y + 0.1,
  y_transformed = toy_y,
  g_transformed = toy_y + 0.1,
  split = "train",
  cutoff_id = "toy",
  stringsAsFactors = FALSE
)
toy_panel <- app_attach_model_covariates(toy_panel, toy_timeline)
toy_bundle <- list(
  panel = toy_panel,
  cutoff = data.frame(
    cutoff_id = "toy",
    origin_date = origin,
    train_start = min(history_dates),
    train_end = origin,
    stringsAsFactors = FALSE
  ),
  future_dates = future_dates
)

toy_candidate <- data.frame(
  rhs_candidate_id = "toy_rhs",
  candidate_id = "toy_oracle",
  n_vector = "6",
  m = 3L,
  output_lag_max = 3L,
  covariate_lag_max = 2L,
  washout = 5L,
  alpha = 0.3,
  rho = 0.8,
  seed = 11L,
  ridge_tau2 = 100,
  intercept_var = 1e6,
  sigma_a = 2,
  sigma_b = 1,
  validation_n = 10L,
  rhs_tau0 = 1,
  rhs_max_iter = 5L,
  rhs_min_iter = 2L,
  rhs_tol = 0,
  rhs_update_every = 1L,
  rhs_freeze_tau_warmup_iters = 0L,
  rhs_min_tau_updates = 0L,
  stringsAsFactors = FALSE
)

toy_fit <- app_glofas_oracle_fit_part1(
  base_cfg = oracle_cfg,
  candidate_row = toy_candidate,
  panel_bundle = toy_bundle,
  method = "ridge"
)
toy_forecast <- app_glofas_oracle_recursive_forecast(
  fitted = toy_fit,
  future_dates = future_dates,
  covariate_timeline = toy_timeline
)
toy_forecast_r <- app_glofas_oracle_recursive_forecast(
  fitted = toy_fit,
  future_dates = future_dates,
  covariate_timeline = toy_timeline,
  forecast_backend = "r"
)
stopifnot(length(toy_forecast$pred_mean) == length(future_dates))
stopifnot(all(is.finite(toy_forecast$pred_mean)))
stopifnot(all(is.finite(toy_forecast$pred_sd)), all(toy_forecast$pred_sd > 0))
stopifnot(isTRUE(all.equal(
  as.numeric(toy_forecast$input_lag_matrix[1L, "y_lag_1"]),
  as.numeric(tail(toy_fit$design$y, 1L)),
  tolerance = 1e-10
)))
stopifnot(isTRUE(all.equal(
  as.numeric(toy_forecast$input_lag_matrix[2L, "y_lag_1"]),
  as.numeric(toy_forecast$pred_mean[[1L]]),
  tolerance = 1e-10
)))
stopifnot(any(toy_forecast$future_input_audit$role == "latent_future_usgs"))
stopifnot(any(toy_forecast$future_input_audit$role == "oracle_realized_future"))
stopifnot(!any(grepl(app_glofas_oracle_forbidden_source_regex(), unlist(toy_forecast$future_input_audit), perl = TRUE)))
if (app_glofas_oracle_load_cpp(required = FALSE)) {
  toy_forecast_cpp <- app_glofas_oracle_recursive_forecast(
    fitted = toy_fit,
    future_dates = future_dates,
    covariate_timeline = toy_timeline,
    forecast_backend = "cpp"
  )
  stopifnot(identical(toy_forecast_cpp$forecast_backend, "cpp_d1_plugin_recursive"))
  stopifnot(isTRUE(all.equal(toy_forecast_cpp$pred_mean, toy_forecast_r$pred_mean, tolerance = 1e-12)))
  stopifnot(isTRUE(all.equal(toy_forecast_cpp$input_lag_matrix, toy_forecast_r$input_lag_matrix, tolerance = 1e-12)))
}

saved_fit_path <- file.path(tempdir(), paste0("toy_oracle_fit_", Sys.getpid(), ".rds"))
saveRDS(toy_fit$fit, saved_fit_path, version = 2L)
toy_fit_reused <- app_glofas_oracle_prepare_part1_fitted(
  base_cfg = oracle_cfg,
  candidate_row = toy_candidate,
  panel_bundle = toy_bundle,
  method = "ridge",
  fit_object_path = saved_fit_path,
  reuse_fit = TRUE
)
stopifnot(isTRUE(toy_fit_reused$fit_reused))
stopifnot(identical(toy_fit_reused$fit_reuse_contract, "deterministic_design_rebuilt_and_saved_fit_moments_reused"))
stopifnot(isTRUE(all.equal(unname(toy_fit_reused$fit$beta_mean), unname(toy_fit$fit$beta_mean), tolerance = 0)))

toy_draw_forecast <- app_glofas_oracle_draw_recursive_forecast(
  fitted = toy_fit,
  future_dates = future_dates,
  covariate_timeline = toy_timeline,
  n_draws = 12L,
  seed = 20260903L
)
toy_draw_forecast_repeat <- app_glofas_oracle_draw_recursive_forecast(
  fitted = toy_fit,
  future_dates = future_dates,
  covariate_timeline = toy_timeline,
  n_draws = 12L,
  seed = 20260903L
)
stopifnot(identical(dim(toy_draw_forecast$forecast_draws), c(length(future_dates), 12L)))
stopifnot(all(is.finite(toy_draw_forecast$forecast_draws)))
stopifnot(all(is.finite(toy_draw_forecast$conditional_mean_draws)))
stopifnot(all(is.finite(toy_draw_forecast$pred_mean)))
stopifnot(all(is.finite(toy_draw_forecast$pred_sd)))
stopifnot(all(toy_draw_forecast$pred_sd > 0))
stopifnot(isTRUE(all.equal(
  toy_draw_forecast$forecast_draws,
  toy_draw_forecast_repeat$forecast_draws,
  tolerance = 0
)))
stopifnot(isTRUE(all.equal(
  as.numeric(toy_draw_forecast$input_lag_matrix[1L, "y_lag_1"]),
  as.numeric(tail(toy_fit$design$y, 1L)),
  tolerance = 1e-10
)))
stopifnot(isTRUE(all.equal(
  as.numeric(toy_draw_forecast$input_lag_matrix[2L, "y_lag_1"]),
  mean(toy_draw_forecast$forecast_draws[1L, ]),
  tolerance = 1e-10
)))
stopifnot(identical(toy_draw_forecast$forecast_mode, "draw_recursive"))
stopifnot(identical(toy_draw_forecast$n_draws, 12L))
stopifnot(any(toy_draw_forecast$future_input_audit$role == "latent_future_usgs"))
stopifnot(!any(grepl(app_glofas_oracle_forbidden_source_regex(), unlist(toy_draw_forecast$future_input_audit), perl = TRUE)))
if (app_glofas_oracle_load_cpp(required = FALSE)) {
  toy_draw_forecast_r <- app_glofas_oracle_draw_recursive_forecast(
    fitted = toy_fit,
    future_dates = future_dates,
    covariate_timeline = toy_timeline,
    n_draws = 12L,
    seed = 20260903L,
    forecast_backend = "r",
    progress_every = 0L
  )
  toy_draw_forecast_cpp <- app_glofas_oracle_draw_recursive_forecast(
    fitted = toy_fit,
    future_dates = future_dates,
    covariate_timeline = toy_timeline,
    n_draws = 12L,
    seed = 20260903L,
    forecast_backend = "cpp"
  )
  stopifnot(identical(toy_draw_forecast_cpp$forecast_backend, "cpp_d1_draw_recursive"))
  stopifnot(isTRUE(all.equal(as.numeric(toy_draw_forecast_cpp$forecast_draws), as.numeric(toy_draw_forecast_r$forecast_draws), tolerance = 1e-12)))
  stopifnot(isTRUE(all.equal(as.numeric(toy_draw_forecast_cpp$conditional_mean_draws), as.numeric(toy_draw_forecast_r$conditional_mean_draws), tolerance = 1e-12)))
  stopifnot(isTRUE(all.equal(toy_draw_forecast_cpp$input_lag_matrix, toy_draw_forecast_r$input_lag_matrix, tolerance = 1e-12)))
}

future_truth <- data.frame(
  date = future_dates,
  y_reference = sin((length(history_dates) + seq_along(future_dates)) / 5) +
    (length(history_dates) + seq_along(future_dates)) / 100,
  stringsAsFactors = FALSE
)
future_truth$y_transformed <- future_truth$y_reference
path_table <- app_glofas_oracle_path_table(toy_fit, toy_forecast, future_truth = future_truth)
scores <- app_glofas_oracle_score_forecast(path_table)
stopifnot(nrow(scores$aggregate) == 1L)
stopifnot(is.finite(scores$aggregate$future_mean_crps[[1L]]))
stopifnot(nrow(scores$by_block) >= 1L)

draw_path_table <- app_glofas_oracle_path_table(toy_fit, toy_draw_forecast, future_truth = future_truth)
draw_scores <- app_glofas_oracle_score_forecast(draw_path_table, forecast = toy_draw_forecast)
stopifnot(nrow(draw_scores$aggregate) == 1L)
stopifnot(nrow(draw_scores$pointwise) == length(future_dates))
stopifnot(is.finite(draw_scores$aggregate$future_mean_crps[[1L]]))
stopifnot(draw_scores$aggregate$future_mean_sd[[1L]] > 0)
stopifnot(all(draw_scores$pointwise$horizon == seq_along(future_dates)))

fixture_root <- tempfile("oracle_forecast_fixture_")
dir.create(fixture_root, recursive = TRUE)
fixture_ref <- data.frame(
  date = seq.Date(as.Date("2020-01-01"), origin + 5L, by = "day"),
  streamflow = seq_len(length(seq.Date(as.Date("2020-01-01"), origin + 5L, by = "day"))) / 100,
  stringsAsFactors = FALSE
)
fixture_ret <- data.frame(
  date = seq.Date(as.Date("2020-01-01"), origin + 2L, by = "day"),
  glofas_streamflow = fixture_ref$streamflow[seq_len(length(seq.Date(as.Date("2020-01-01"), origin + 2L, by = "day")))] + 0.25,
  stringsAsFactors = FALSE
)
fixture_cov <- data.frame(
  date = seq.Date(as.Date("2019-12-20"), origin + 8L, by = "day"),
  ppt = 1 + seq_along(seq.Date(as.Date("2019-12-20"), origin + 8L, by = "day")) / 100,
  soil = 2 + seq_along(seq.Date(as.Date("2019-12-20"), origin + 8L, by = "day")) / 200,
  stringsAsFactors = FALSE
)
ref_path <- file.path(fixture_root, "reference.csv")
ret_path <- file.path(fixture_root, "glofas_retrospective.csv")
cov_path <- file.path(fixture_root, "ppt_soil_covariates.csv")
app_write_csv(fixture_ref, ref_path)
app_write_csv(fixture_ret, ret_path)
app_write_csv(fixture_cov, cov_path)
manifest_path <- file.path(fixture_root, "input_manifest.csv")
manifest_fixture <- data.frame(
  input_id = c("reference_gauge", "glofas_retrospective", "ppt_soil_covariates"),
  source_name = "fixture",
  source_type = "csv",
  local_path = c(ref_path, ret_path, cov_path),
  upstream_reference = NA_character_,
  date_min = NA_character_,
  date_max = NA_character_,
  cutoff_date = as.character(origin),
  row_count = NA_integer_,
  column_count = NA_integer_,
  sha256 = NA_character_,
  created_at = NA_character_,
  notes = "oracle forecast fixture",
  stringsAsFactors = FALSE
)
app_write_csv(manifest_fixture, manifest_path)
cutoff_path <- file.path(fixture_root, "cutoffs.csv")
app_write_csv(
  data.frame(
    cutoff_id = "toy",
    origin_date = as.character(origin),
    train_start = "2020-01-01",
    train_end = as.character(origin),
    eval_start = as.character(origin + 1L),
    eval_end = as.character(origin + 5L),
    horizon_min = 1L,
    horizon_max = 5L,
    split = "toy",
    enabled = TRUE,
    notes = "fixture",
    stringsAsFactors = FALSE
  ),
  cutoff_path
)
fixture_cfg <- oracle_cfg
fixture_cfg$paths <- list(input_manifest = manifest_path, cutoffs = cutoff_path)
disc_bundle <- app_glofas_oracle_prepare_panel_bundle(
  cfg = fixture_cfg,
  origin_date = origin,
  horizon_days = 5L,
  target = "discrepancy",
  root_candidates = fixture_root
)
stopifnot(disc_bundle$effective_horizon == 5L)
stopifnot(disc_bundle$max_score_horizon == 2L)
stopifnot(isTRUE(all.equal(
  as.numeric(disc_bundle$future_truth$y_transformed[[1L]]),
  0.25,
  tolerance = 1e-10
)))
stopifnot(sum(is.finite(disc_bundle$future_truth$y_transformed)) == 2L)

bad_cov <- toy_cov
bad_cov$ppt[bad_cov$date == origin + 4L] <- NA_real_
stopifnot(app_glofas_oracle_contiguous_horizon(
  bad_cov$date,
  origin,
  is.finite(bad_cov$ppt) & is.finite(bad_cov$soil)
) == 3L)

bad_timeline <- toy_timeline
bad_timeline$ppt_source <- "gefs_handoff"
bad_source_msg <- tryCatch(
  {
    app_glofas_oracle_validate_no_forbidden_sources(bad_timeline, label = "bad")
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("forbidden GEFS/CEFS", bad_source_msg))

aux_msg <- tryCatch(
  {
    app_glofas_oracle_validate_forecastable_qfit(list(meta = list(
      reservoir_input_spec = list(uses_auxiliary_lags = TRUE, uses_dlm_components = FALSE)
    )))
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("Auxiliary-lag", aux_msg, fixed = TRUE))

dlm_msg <- tryCatch(
  {
    app_glofas_oracle_validate_forecastable_qfit(list(meta = list(
      reservoir_input_spec = list(uses_auxiliary_lags = FALSE, uses_dlm_components = TRUE)
    )))
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("DLM-augmented", dlm_msg, fixed = TRUE))

tmp_dir <- tempfile("oracle_forecast_write_")
write_result <- app_glofas_oracle_write_result(
  result = list(
    target = "usgs",
    origin_date = origin,
    effective_horizon = length(future_dates),
    max_covariate_horizon = 10L,
    max_score_horizon = 5L,
    fitted = toy_fit,
    forecast = toy_forecast,
    path_table = path_table,
    scores = scores,
    forecast_runtime_seconds = 0.01
  ),
  root = tmp_dir,
  run_label = "toy"
)
stopifnot(file.exists(file.path(tmp_dir, "tables", "toy_summary.csv")))
stopifnot(file.exists(file.path(tmp_dir, "figures", "toy_forecast_full_history.pdf")))
stopifnot(length(write_result$figures) == 3L)
toy_summary <- app_read_csv(file.path(tmp_dir, "tables", "toy_summary.csv"))
stopifnot("forecast_backend" %in% names(toy_summary))
stopifnot("fit_reused" %in% names(toy_summary))
stopifnot("fit_reuse_contract" %in% names(toy_summary))

tmp_draw_dir <- tempfile("oracle_forecast_draw_write_")
write_draw_result <- app_glofas_oracle_write_result(
  result = list(
    target = "usgs",
    forecast_mode = "draw_recursive",
    retain_draws = FALSE,
    origin_date = origin,
    effective_horizon = length(future_dates),
    max_covariate_horizon = 10L,
    max_score_horizon = 5L,
    fitted = toy_fit,
    forecast = toy_draw_forecast,
    path_table = draw_path_table,
    scores = draw_scores,
    forecast_runtime_seconds = 0.01
  ),
  root = tmp_draw_dir,
  run_label = "toy_draw"
)
stopifnot(file.exists(file.path(tmp_draw_dir, "tables", "toy_draw_draw_summary.csv")))
stopifnot(file.exists(file.path(tmp_draw_dir, "tables", "toy_draw_forecast_scores_by_horizon.csv")))
stopifnot(file.exists(file.path(tmp_draw_dir, "logs", "toy_draw_forecast_timing.csv")))
stopifnot(!file.exists(file.path(tmp_draw_dir, "objects", "toy_draw_forecast_draws.rds")))
stopifnot(length(write_draw_result$figures) == 3L)
