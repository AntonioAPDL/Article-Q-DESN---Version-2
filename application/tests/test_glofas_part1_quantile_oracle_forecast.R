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
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))
source(app_path("application/R/joint_exqdesn_inference_dispatch.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_part1_quantile_oracle_forecast.R"))

oracle_cfg <- list(
  data = list(transform = list(response = "identity", forecast = "identity")),
  covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
  feature_contract = list(),
  reservoir = list()
)

origin <- as.Date("2020-04-30")
history_dates <- seq.Date(as.Date("2020-01-01"), origin, by = "day")
future_dates <- seq.Date(origin + 1L, origin + 4L, by = "day")
all_cov_dates <- seq.Date(min(history_dates) - 5L, origin + 10L, by = "day")
toy_cov <- data.frame(
  date = all_cov_dates,
  ppt = cos(seq_along(all_cov_dates) / 9),
  soil = sin(seq_along(all_cov_dates) / 13),
  stringsAsFactors = FALSE
)
toy_timeline <- app_glofas_oracle_covariate_timeline(
  toy_cov,
  origin_date = origin,
  train_start = min(history_dates)
)
toy_y <- sin(seq_along(history_dates) / 5) + seq_along(history_dates) / 120
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
  future_dates = future_dates,
  future_truth = data.frame(
    date = future_dates,
    y_reference = sin((length(history_dates) + seq_along(future_dates)) / 5) +
      (length(history_dates) + seq_along(future_dates)) / 120,
    y_transformed = sin((length(history_dates) + seq_along(future_dates)) / 5) +
      (length(history_dates) + seq_along(future_dates)) / 120,
    stringsAsFactors = FALSE
  )
)

toy_candidate <- data.frame(
  rhs_candidate_id = "toy_rhs",
  candidate_id = "toy_quantile",
  n_vector = "5",
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

toy_normal_fit <- app_glofas_oracle_fit_part1(
  base_cfg = oracle_cfg,
  candidate_row = toy_candidate,
  panel_bundle = toy_bundle,
  method = "ridge"
)
toy_fitted <- list(
  candidate_row = toy_candidate,
  bundle = toy_bundle,
  design = toy_normal_fit$design,
  Z = as.matrix(toy_normal_fit$design$X[, -1L, drop = FALSE])
)

run_family <- function(model_family, tau, max_dense_dim = 50L, joint_backend = "auto", init_fit_path = NULL) {
  progress_path <- file.path(tempdir(), paste0("glofas_quantile_progress_", model_family, "_", Sys.getpid(), ".csv"))
  controls <- app_glofas_part1_quantile_default_controls(
    max_iter = 2L,
    tol = 0,
    min_iter = 1L,
    tau0 = 1,
    max_dense_dim = max_dense_dim,
    rhs_vb_inner = 1L,
    exal_method_id = "VB1_structured_v",
    joint_backend = joint_backend,
    init_fit_path = init_fit_path,
    progress_path = progress_path,
    progress_every = 1L
  )
  fit <- app_glofas_part1_quantile_fit_readout(
    y = toy_fitted$design$y,
    Z = toy_fitted$Z,
    tau = tau,
    model_family = model_family,
    controls = controls
  )
  forecast <- app_glofas_part1_quantile_recursive_forecast(
    fitted = toy_fitted,
    fit = fit,
    tau = tau,
    future_dates = future_dates,
    covariate_timeline = toy_timeline,
    forecast_backend = "auto"
  )
  path <- app_glofas_part1_quantile_path_table(
    fitted = toy_fitted,
    fit = fit,
    tau = tau,
    forecast = forecast,
    future_truth = toy_bundle$future_truth
  )
  scores <- app_glofas_part1_quantile_score_forecast(path)
  stopifnot(nrow(forecast$forecast) == length(future_dates) * length(tau))
  stopifnot(all(is.finite(forecast$forecast$qhat)))
  stopifnot(nrow(scores$aggregate) == length(tau))
  stopifnot(all(is.finite(scores$aggregate$forecast_check_loss_mean)))
  stopifnot(!any(grepl("synthesis", names(forecast), fixed = TRUE)))
  stopifnot(file.exists(progress_path))
  list(fit = fit, forecast = forecast, path_table = path, scores = scores, controls = controls)
}

one_al <- run_family("independent_al", 0.50)
init_path <- file.path(tempdir(), paste0("toy_al_init_", Sys.getpid(), ".rds"))
saveRDS(one_al$fit, init_path, version = 2L)
one_exal <- run_family("independent_exal", 0.50, init_fit_path = init_path)
stopifnot(grepl("toy_al_init", one_exal$fit$init_source_path, fixed = TRUE))
joint_al <- run_family("joint_al", c(0.20, 0.50, 0.80), max_dense_dim = 100L)
joint_al_blockmf <- run_family("joint_al", c(0.20, 0.50, 0.80), max_dense_dim = 2L)
joint_exal_blockmf <- run_family("joint_exal", c(0.20, 0.50, 0.80), max_dense_dim = 2L)
stopifnot(identical(joint_al_blockmf$fit$joint_backend_used, "blockmf"))
stopifnot(identical(joint_exal_blockmf$fit$joint_backend_used, "blockmf"))

tmp <- file.path(tempdir(), paste0("glofas_part1_quantile_test_", Sys.getpid()))
written <- app_glofas_part1_quantile_write_result(
  result = c(
    list(
      target = "usgs",
      model_family = "independent_al",
      likelihood = "AL",
      fit_structure = "independent_single_tau",
      tau = 0.50,
      origin_date = origin,
      candidate_row = toy_candidate,
      trace = app_glofas_part1_quantile_trace_rows(one_al$fit, "independent_al", 0.50),
      coefficients = app_glofas_part1_quantile_coefficient_rows(one_al$fit, toy_fitted$Z, 0.50)
    ),
    one_al
  ),
  root = tmp,
  run_label = "toy_part1_quantile"
)
stopifnot(file.exists(file.path(tmp, "tables", "toy_part1_quantile_summary.csv")))
stopifnot(file.exists(file.path(tmp, "figures", "toy_part1_quantile_forecast_last200_history.pdf")))
stopifnot(all(file.exists(written$figures)))

blocked <- tryCatch(
  run_family("joint_exal", c(0.20, 0.50, 0.80), max_dense_dim = 2L, joint_backend = "dense"),
  error = function(e) conditionMessage(e)
)
stopifnot(is.character(blocked))
stopifnot(grepl("max_dense_dim", blocked, fixed = TRUE))

message("GloFAS Part 1 quantile oracle forecast tests passed.")
