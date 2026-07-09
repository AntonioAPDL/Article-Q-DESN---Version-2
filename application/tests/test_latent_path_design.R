bridge_cfg <- cfg
bridge_cfg$application_model <- list(contract = "origin_state_bridge")
stopifnot(identical(app_application_model_contract(bridge_cfg), "origin_state_bridge"))
stopifnot(!app_is_latent_path_contract(bridge_cfg))

latent_cfg <- cfg
latent_cfg$application_model <- list(contract = "latent_path_ensemble_likelihood")
latent_cfg$prediction$prediction_unit <- "posterior_draw"
latent_cfg$prediction$q_g_source <- "posterior_model_quantile"
latent_cfg$prediction$discrepancy_feature_strategy <- "recursive_latent_path"
stopifnot(identical(app_application_model_contract(latent_cfg), "latent_path_ensemble_likelihood"))
stopifnot(isTRUE(app_is_latent_path_contract(latent_cfg)))
stopifnot(identical(app_validate_application_model_contract(latent_cfg), "latent_path_ensemble_likelihood"))

bad_latent <- latent_cfg
bad_latent$prediction$q_g_source <- "ensemble_bayesian_bootstrap_quantile"
bad_msg <- tryCatch(
  {
    app_validate_application_model_contract(bad_latent)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("posterior_model_quantile", bad_msg, fixed = TRUE))

contract_row <- app_application_model_contract_row(latent_cfg)
stopifnot(identical(contract_row$issued_glofas_role, "likelihood_rows"))
stopifnot(identical(contract_row$glofas_scale_scope, "retrospective_and_issued_glofas"))

latent_bridge_msg <- tryCatch(
  {
    app_fit_qdesn_discrepancy(data.frame(), latent_cfg, data.frame())
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("origin-state bridge", latent_bridge_msg, fixed = TRUE))

latent_panel <- data.frame(
  origin_date = as.Date(c(rep("2026-01-05", 5L), rep("2026-01-05", 6L))),
  target_date = c(as.Date("2026-01-01") + 0:4, rep(as.Date("2026-01-06") + 0:1, each = 3L)),
  horizon = c(rep(0L, 5L), rep(1:2, each = 3L)),
  member = c(rep(NA_character_, 5L), sprintf("m%02d", 1:6)),
  is_retrospective = c(rep(TRUE, 5L), rep(FALSE, 6L)),
  is_ensemble = c(rep(FALSE, 5L), rep(TRUE, 6L)),
  y_transformed = c(10:14, rep(c(15, 16), each = 3L)),
  g_transformed = c(9:13, 20:25),
  split = c(rep("train", 5L), rep("eval", 6L)),
  cutoff_id = "toy",
  stringsAsFactors = FALSE
)
latent_cutoff <- data.frame(
  cutoff_id = "toy",
  origin_date = as.Date("2026-01-05"),
  train_start = as.Date("2026-01-01"),
  train_end = as.Date("2026-01-05"),
  eval_start = as.Date("2026-01-06"),
  eval_end = as.Date("2026-01-07"),
  horizon_min = 1L,
  horizon_max = 2L,
  split = "toy",
  enabled = TRUE,
  notes = "",
  stringsAsFactors = FALSE
)
latent_data <- app_make_glofas_latent_path_data(latent_panel, latent_cfg, latent_cutoff)
stopifnot(inherits(latent_data, "glofas_latent_path_data"))
stopifnot(nrow(latent_data$y_history) == 5L)
stopifnot(nrow(latent_data$g_retro) == 5L)
stopifnot(nrow(latent_data$g_ensemble) == 6L)
stopifnot(nrow(latent_data$future_key) == 2L)
stopifnot(isTRUE(all.equal(latent_data$y_future_oracle, c(15, 16), check.attributes = FALSE)))
stopifnot(identical(latent_data$source_parameter_scope$glofas_scale_scope, "retrospective_and_issued_glofas"))
latent_summary <- app_latent_path_data_summary(latent_data, data.frame(fit_id = "fit1", model_id = "mod1"))
stopifnot(identical(latent_summary$application_model_contract, "latent_path_ensemble_likelihood"))
stopifnot(latent_summary$n_glofas_ensemble == 6L)
stopifnot(latent_summary$horizon_max == 2L)
stopifnot(latent_summary$requested_horizon_max == 2L)

latent_cutoff_requested_long <- latent_cutoff
latent_cutoff_requested_long$horizon_max <- 3L
latent_data_short <- app_make_glofas_latent_path_data(latent_panel, latent_cfg, latent_cutoff_requested_long)
stopifnot(latent_data_short$horizon_max == 2L)
stopifnot(latent_data_short$requested_horizon_max == 3L)
stopifnot(identical(latent_data_short$horizon_scope, "available_issued_ensemble_horizon"))

latent_fit_msg <- tryCatch(
  {
    app_fit_qdesn_latent_path()
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("argument", latent_fit_msg, ignore.case = TRUE) || grepl("missing", latent_fit_msg, ignore.case = TRUE))

sim <- app_simulate_glofas_latent_path_al(
  n_history = 24L,
  horizon = 4L,
  n_members = 5L,
  p0 = 0.5,
  seed = 42L
)
stopifnot(nrow(sim$panel[sim$panel$is_retrospective, , drop = FALSE]) == 24L)
stopifnot(nrow(sim$panel[sim$panel$is_ensemble, , drop = FALSE]) == 20L)
stopifnot(all(c("ppt", "soil") %in% names(sim$panel)))
stopifnot(nrow(sim$truth) == 28L)
stopifnot(isTRUE(all.equal(sim$truth$q_g, sim$truth$q_y + sim$truth$delta, tolerance = 1.0e-12)))

sim_cfg <- latent_cfg
sim_cutoff <- sim$cutoff
sim_cutoff$horizon_max <- 6L
sim_data <- app_make_glofas_latent_path_data(sim$panel, sim_cfg, sim_cutoff, sim$model_row)
stopifnot(sim_data$horizon_max == 4L)
stopifnot(sim_data$requested_horizon_max == 6L)
stopifnot(identical(sim_data$horizon_scope, "available_issued_ensemble_horizon"))
stopifnot(nrow(sim_data$g_ensemble) == 20L)
stopifnot(isTRUE(all.equal(sim_data$y_future_oracle, sim$truth$y[sim$truth$is_future], tolerance = 1.0e-12)))

toy_reservoir <- list(
  D = 1L,
  n = 1L,
  n_tilde = integer(0),
  m = 2L,
  m_input = 2L,
  alpha = 1,
  W = list(matrix(0.25, 1L, 1L)),
  Win = list(matrix(c(0.10, 0.50, -0.20), nrow = 1L)),
  Q = list(),
  Q_is_identity = logical(0),
  act_f = "identity",
  act_k = "identity"
)
toy_meta <- list(
  m_input = 2L,
  standardize_inputs = FALSE,
  input_bound = "none",
  win_scale_global = 1,
  win_scale_bias = 1,
  lag_center = c(0, 0),
  lag_scale = c(1, 1)
)

direct_roll <- function(y) {
  states <- list(0)
  lag_buf <- c(0, 0)
  H <- matrix(NA_real_, nrow = length(y), ncol = 1L)
  for (i in seq_along(y)) {
    states <- app_qdesn_continue_one_step(states, lag_buf, toy_reservoir, toy_meta)
    H[i, ] <- states[[1L]]
    lag_buf <- c(y[[i]], lag_buf[[1L]])
  }
  H
}

y_hist <- c(1, 2, 3, 4, 5)
y_future <- c(6, 7, 8)
y_full <- c(y_hist, y_future)
H_full <- direct_roll(y_full)
qfit <- list(
  reservoir = toy_reservoir,
  states = list(H_all = list(H_full[seq_along(y_hist), , drop = FALSE])),
  meta = toy_meta
)
cont <- app_qdesn_continue_latent_path(qfit, y_history = y_hist, y_future = y_future, return_jacobian = TRUE)
stopifnot(inherits(cont, "qdesn_latent_path_continuation"))
stopifnot(isTRUE(all.equal(cont$X_future_core[, 1], H_full[(length(y_hist) + 1L):length(y_full), 1], tolerance = 1.0e-12)))
stopifnot(isTRUE(all.equal(cont$input_lag_matrix[1L, ], c(5, 4), check.attributes = FALSE)))
stopifnot(isTRUE(all.equal(cont$input_lag_matrix[2L, ], c(6, 5), check.attributes = FALSE)))
stopifnot(isTRUE(all.equal(cont$input_lag_matrix[3L, ], c(7, 6), check.attributes = FALSE)))
stopifnot(length(cont$J_future_core) == length(y_future))
stopifnot(abs(cont$J_future_core[[1L]][1L, 1L]) < 1.0e-12)
stopifnot(abs(cont$J_future_core[[2L]][1L, 2L]) < 1.0e-12)
finite_diff <- function(k, eps = 1.0e-6) {
  y_plus <- y_future
  y_minus <- y_future
  y_plus[[k]] <- y_plus[[k]] + eps
  y_minus[[k]] <- y_minus[[k]] - eps
  plus <- app_qdesn_continue_latent_path(qfit, y_history = y_hist, y_future = y_plus)$X_future_core
  minus <- app_qdesn_continue_latent_path(qfit, y_history = y_hist, y_future = y_minus)$X_future_core
  (plus - minus) / (2 * eps)
}
for (k in seq_along(y_future)) {
  fd <- finite_diff(k)
  analytic <- vapply(cont$J_future_core, function(Jh) Jh[1L, k], numeric(1L))
  stopifnot(isTRUE(all.equal(as.numeric(fd[, 1]), analytic, tolerance = 1.0e-6)))
}

cov_dates <- as.Date("2026-02-01") + 0:12
cov_timeline <- data.frame(
  date = cov_dates,
  ppt = seq_along(cov_dates) / 10,
  soil = 0.20 + seq_along(cov_dates) / 100,
  ppt_role = ifelse(cov_dates <= as.Date("2026-02-10"), "realized_history", "forecast_blended"),
  soil_role = ifelse(cov_dates <= as.Date("2026-02-10"), "realized_history", "forecast_blended"),
  stringsAsFactors = FALSE
)
cov_panel <- data.frame(
  origin_date = cov_dates[1:10],
  target_date = cov_dates[1:10],
  horizon = 0L,
  member = NA_character_,
  is_retrospective = TRUE,
  is_ensemble = FALSE,
  y_transformed = seq_len(10),
  g_transformed = seq_len(10) + 0.1,
  split = "train",
  cutoff_id = "toy_cov",
  stringsAsFactors = FALSE
)
attr(cov_panel, "model_covariate_timeline") <- cov_timeline
cov_latent_cfg <- latent_cfg
cov_latent_cfg$covariates <- list(enabled = TRUE, variables = c("ppt", "soil"))
cov_latent_cfg$feature_contract <- list(
  version = "latent_path_cov_test",
  two_block_design = FALSE,
  reservoir_input = list(
    internal_bias = TRUE,
    output_lags = list(range = c(1L, 2L)),
    covariates = list(ppt = list(range = c(0L, 1L)), soil = list(range = c(0L, 1L))),
    standardize = TRUE
  ),
  readout = list(
    add_intercept = TRUE,
    include_reservoir_state = TRUE,
    reservoir_state_lags = list(),
    include_input_block = FALSE,
    input_block = list(output_lags = list(), covariates = list(), include_internal_bias = FALSE),
    include_horizon_scaled = FALSE
  ),
  forecast_alignment = list(output_lags_anchor = "target_date", covariate_lags_anchor = "target_date")
)
cov_latent_cfg$reservoir <- list(
  D = 1L,
  n = 2L,
  n_tilde = integer(0),
  m = 2L,
  washout = 2L,
  alpha = 0.4,
  rho = 0.5,
  pi_w = 1,
  pi_in = 1,
  act_f = "tanh",
  act_k = "identity",
  standardize_inputs = TRUE,
  add_bias = TRUE,
  seed = 20260514L
)
qfit_cov_article <- app_qdesn_build_article_design_full(cov_panel, cov_latent_cfg, seed = 20260514L, drop = 2L)
stopifnot(inherits(qfit_cov_article, "qdesn_fit"))
stopifnot(isTRUE(qfit_cov_article$meta$reservoir_covariates_enabled))
stopifnot(identical(
  qfit_cov_article$meta$reservoir_input_columns,
  c("y_lag_1", "y_lag_2", "ppt_lag_0", "ppt_lag_1", "soil_lag_0", "soil_lag_1")
))
cov_future_dates <- as.Date("2026-02-11") + 0:2
cov_y_future <- c(11, 12, 13)
cont_cov <- app_qdesn_continue_latent_path(
  qfit_cov_article,
  y_history = cov_panel$y_transformed,
  y_future = cov_y_future,
  future_dates = cov_future_dates,
  covariate_timeline = cov_timeline,
  return_jacobian = TRUE
)
stopifnot(isTRUE(cont_cov$covariate_jacobian_zero))
stopifnot(isTRUE(all.equal(cont_cov$input_lag_matrix[1L, c("y_lag_1", "y_lag_2")], c(10, 9), check.attributes = FALSE)))
stopifnot(isTRUE(all.equal(cont_cov$input_lag_matrix[2L, c("y_lag_1", "y_lag_2")], c(11, 10), check.attributes = FALSE)))
stopifnot(any(cont_cov$future_input_audit$role == "forecast_blended"))
stopifnot(any(cont_cov$future_input_audit$role == "latent_future_usgs"))
app_latent_path_validate_no_usgs_leakage(
  data.frame(date = cont_cov$future_input_audit$input_date, role = cont_cov$future_input_audit$role),
  as.Date("2026-02-10")
)
finite_diff_cov <- function(k, eps = 1.0e-6) {
  y_plus <- cov_y_future
  y_minus <- cov_y_future
  y_plus[[k]] <- y_plus[[k]] + eps
  y_minus[[k]] <- y_minus[[k]] - eps
  plus <- app_qdesn_continue_latent_path(
    qfit_cov_article,
    y_history = cov_panel$y_transformed,
    y_future = y_plus,
    future_dates = cov_future_dates,
    covariate_timeline = cov_timeline
  )$X_future_core
  minus <- app_qdesn_continue_latent_path(
    qfit_cov_article,
    y_history = cov_panel$y_transformed,
    y_future = y_minus,
    future_dates = cov_future_dates,
    covariate_timeline = cov_timeline
  )$X_future_core
  (plus - minus) / (2 * eps)
}
for (k in seq_along(cov_y_future)) {
  fd <- finite_diff_cov(k)
  analytic <- do.call(rbind, lapply(cont_cov$J_future_core, function(Jh) Jh[, k]))
  stopifnot(isTRUE(all.equal(fd, analytic, tolerance = 1.0e-5, check.attributes = FALSE)))
}

qfit_cov <- qfit
qfit_cov$meta$reservoir_covariate_columns <- "ppt_lag_0"
cov_guard_msg <- tryCatch(
  {
    app_qdesn_continue_latent_path(qfit_cov, y_history = y_hist, y_future = y_future)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("output-lag reservoir inputs only", cov_guard_msg, fixed = TRUE))

scaled_meta <- toy_meta
scaled_meta$standardize_inputs <- TRUE
scaled_meta$lag_center <- c(5, 5)
scaled_meta$lag_scale <- c(2, 4)
scaled_meta$input_bound <- "tanh"
u_scaled <- app_qdesn_make_input_vector(c(7, 1), scaled_meta)
stopifnot(abs(u_scaled[[1L]] - 1) < 1.0e-12)
stopifnot(isTRUE(all.equal(u_scaled[-1L], tanh(c(1, -1)), tolerance = 1.0e-12)))

future_inputs_ok <- data.frame(
  date = as.Date("2026-01-10") + 1:3,
  role = c("latent_usgs", "forecast_covariate", "issued_glofas"),
  stringsAsFactors = FALSE
)
app_latent_path_validate_no_usgs_leakage(future_inputs_ok, as.Date("2026-01-10"))

future_inputs_bad <- future_inputs_ok
future_inputs_bad$role[[2L]] <- "heldout_usgs"
leak_msg <- tryCatch(
  {
    app_latent_path_validate_no_usgs_leakage(future_inputs_bad, as.Date("2026-01-10"))
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("post-cutoff observed USGS", leak_msg, fixed = TRUE))

simple_future_builder <- local({
  y_hist0 <- c(0.3, 0.5, 0.8)
  future_key0 <- data.frame(
    target_date = as.Date("2026-01-06") + 0:2,
    horizon = 1:3,
    stringsAsFactors = FALSE
  )
  g_ens0 <- data.frame(
    target_date = rep(future_key0$target_date, each = 3L),
    horizon = rep(future_key0$horizon, each = 3L),
    member = sprintf("m%02d", 1:9),
    g_transformed = c(1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8),
    stringsAsFactors = FALSE
  )
  function(y_future) {
    y_all <- c(y_hist0, as.numeric(y_future))
    H <- length(y_future)
    X <- matrix(NA_real_, nrow = H, ncol = 2L)
    Jx <- vector("list", H)
    for (h in seq_len(H)) {
      lag_value <- y_all[length(y_hist0) + h - 1L]
      X[h, ] <- c(1, lag_value)
      Jh <- matrix(0, nrow = 2L, ncol = H)
      if (h > 1L) Jh[2L, h - 1L] <- 1
      Jx[[h]] <- Jh
    }
    H_y <- cbind(X, matrix(0, nrow = H, ncol = 2L))
    H_g_key <- cbind(X, X)
    J_y <- lapply(Jx, function(Jh) rbind(Jh, matrix(0, nrow = 2L, ncol = H)))
    J_g_key <- lapply(Jx, function(Jh) rbind(Jh, Jh))
    key_id <- paste(future_key0$target_date, future_key0$horizon)
    ens_id <- paste(g_ens0$target_date, g_ens0$horizon)
    idx <- match(ens_id, key_id)
    list(
      X_future = X,
      H_y = H_y,
      H_g_key = H_g_key,
      H_g = H_g_key[idx, , drop = FALSE],
      g_future_index = idx,
      J_y = J_y,
      J_g_key = J_g_key,
      J_g = lapply(idx, function(i) J_g_key[[i]]),
      z_g = g_ens0$g_transformed,
      row_info_y = data.frame(source = "Y", future_index = seq_len(H), target_date = future_key0$target_date, horizon = future_key0$horizon),
      row_info_g_key = data.frame(source = "G", future_index = seq_len(H), target_date = future_key0$target_date, horizon = future_key0$horizon),
      row_info_g = data.frame(source = "G", future_index = idx, target_date = g_ens0$target_date, horizon = g_ens0$horizon, member = g_ens0$member)
    )
  }
})
simple_X <- cbind(readout_intercept = 1, y_lag_1 = c(0.1, 0.2, 0.3, 0.5))
simple_source <- factor(rep(c("Y", "G"), each = nrow(simple_X)), levels = c("Y", "G"))
simple_design <- list(
  z_fixed = c(c(0.3, 0.5, 0.8, 1.0), c(0.7, 0.9, 1.1, 1.3)),
  H_fixed = app_make_augmented_discrepancy_design(rbind(simple_X, simple_X), simple_source, rbind(simple_X, simple_X)),
  source_fixed = simple_source,
  row_info_fixed = data.frame(source = simple_source),
  future_builder = simple_future_builder,
  future_key = data.frame(target_date = as.Date("2026-01-06") + 0:2, horizon = 1:3),
  y_future_init = c(1.0, 1.1, 1.2),
  beta_index = 1:2,
  alpha_index = 3:4,
  intercept_index = c(1L, 3L)
)
simple_probe <- simple_design$future_builder(simple_design$y_future_init)
stopifnot(isTRUE(all.equal(simple_probe$H_g, simple_probe$H_g_key[simple_probe$g_future_index, , drop = FALSE], tolerance = 1.0e-12)))
stopifnot(length(simple_probe$J_g) == length(simple_probe$g_future_index))
for (i in seq_along(simple_probe$J_g)) {
  stopifnot(isTRUE(all.equal(simple_probe$J_g[[i]], simple_probe$J_g_key[[simple_probe$g_future_index[[i]]]], tolerance = 1.0e-12)))
}

two_block_future_builder <- local({
  future_key0 <- data.frame(
    target_date = as.Date("2026-03-01") + 0:2,
    horizon = 1:3,
    stringsAsFactors = FALSE
  )
  qg_path0 <- c(2.0, 2.2, 2.4)
  g_ens0 <- data.frame(
    target_date = rep(future_key0$target_date, each = 2L),
    horizon = rep(future_key0$horizon, each = 2L),
    member = sprintf("m%02d", 1:6),
    g_transformed = c(1.9, 2.1, 2.1, 2.3, 2.3, 2.5),
    stringsAsFactors = FALSE
  )
  function(y_future) {
    y_future <- as.numeric(y_future)
    H <- length(y_future)
    d_future <- qg_path0 - y_future
    X_beta <- cbind(readout_intercept = 1, beta_lag = c(0.7, y_future[-H]))
    X_alpha <- cbind(readout_intercept = 1, alpha_lag = c(-0.2, d_future[-H]))
    J_beta_core <- vector("list", H)
    J_alpha_core <- vector("list", H)
    for (h in seq_len(H)) {
      Jb <- matrix(0, nrow = ncol(X_beta), ncol = H)
      Ja <- matrix(0, nrow = ncol(X_alpha), ncol = H)
      if (h > 1L) {
        Jb[2L, h - 1L] <- 1
        Ja[2L, h - 1L] <- -1
      }
      J_beta_core[[h]] <- Jb
      J_alpha_core[[h]] <- Ja
    }
    H_y <- cbind(X_beta, matrix(0, nrow = H, ncol = ncol(X_alpha)))
    H_g_key <- cbind(X_beta, X_alpha)
    J_y <- lapply(J_beta_core, function(Jb) rbind(Jb, matrix(0, nrow = ncol(X_alpha), ncol = H)))
    J_g_key <- Map(rbind, J_beta_core, J_alpha_core)
    key_id <- paste(future_key0$target_date, future_key0$horizon)
    ens_id <- paste(g_ens0$target_date, g_ens0$horizon)
    idx <- match(ens_id, key_id)
    list(
      X_future = X_beta,
      X_beta_future = X_beta,
      X_alpha_future = X_alpha,
      H_y = H_y,
      H_g_key = H_g_key,
      H_g = H_g_key[idx, , drop = FALSE],
      g_future_index = idx,
      J_y = J_y,
      J_g_key = J_g_key,
      J_g = lapply(idx, function(i) J_g_key[[i]]),
      z_g = g_ens0$g_transformed,
      row_info_y = data.frame(source = "Y", future_index = seq_len(H), target_date = future_key0$target_date, horizon = future_key0$horizon),
      row_info_g_key = data.frame(source = "G", future_index = seq_len(H), target_date = future_key0$target_date, horizon = future_key0$horizon),
      row_info_g = data.frame(source = "G", future_index = idx, target_date = g_ens0$target_date, horizon = g_ens0$horizon, member = g_ens0$member),
      two_block_design = TRUE,
      future_discrepancy_convention = "glofas_quantile_path_minus_latent_reference_path"
    )
  }
})
two_block_X_beta <- cbind(readout_intercept = 1, beta_lag = c(0.2, 0.4, 0.6, 0.8))
two_block_X_alpha <- cbind(readout_intercept = 1, alpha_lag = c(-0.5, -0.4, -0.3, -0.2))
two_block_source <- factor(rep(c("Y", "G"), each = nrow(two_block_X_beta)), levels = c("Y", "G"))
two_block_design <- list(
  z_fixed = c(c(0.9, 1.0, 1.1, 1.2), c(1.3, 1.4, 1.5, 1.6)),
  H_fixed = app_make_augmented_discrepancy_design(
    rbind(two_block_X_beta, two_block_X_beta),
    two_block_source,
    rbind(two_block_X_alpha, two_block_X_alpha)
  ),
  source_fixed = two_block_source,
  row_info_fixed = data.frame(source = two_block_source),
  X_beta = two_block_X_beta,
  X_alpha = two_block_X_alpha,
  X_base = two_block_X_beta,
  feature_info = data.frame(block = c("intercept", "direct_output_lag"), stringsAsFactors = FALSE),
  feature_info_beta = data.frame(block = c("intercept", "direct_output_lag"), stringsAsFactors = FALSE),
  feature_info_alpha = data.frame(block = c("intercept", "direct_output_lag"), stringsAsFactors = FALSE),
  future_builder = two_block_future_builder,
  future_key = data.frame(target_date = as.Date("2026-03-01") + 0:2, horizon = 1:3),
  y_future_init = c(1.0, 1.1, 1.2),
  y_future_oracle = c(1.05, 1.15, 1.25),
  latent_data = list(
    origin_date = as.Date("2026-02-28"),
    future_key = data.frame(target_date = as.Date("2026-03-01") + 0:2, horizon = 1:3),
    g_ensemble = data.frame(
      target_date = rep(as.Date("2026-03-01") + 0:2, each = 2L),
      horizon = rep(1:3, each = 2L),
      member = sprintf("m%02d", 1:6),
      g_transformed = c(1.9, 2.1, 2.1, 2.3, 2.3, 2.5),
      stringsAsFactors = FALSE
    )
  ),
  beta_index = 1:2,
  alpha_index = 3:4,
  intercept_index = c(1L, 3L),
  p0 = 0.5,
  design_version = "latent_path_two_block_test",
  two_block_design = TRUE,
  future_discrepancy_convention = "glofas_quantile_path_minus_latent_reference_path",
  fit_id = "two_block_fit",
  model_id = "two_block_model"
)
app_validate_glofas_latent_path_design(two_block_design)
two_block_probe <- two_block_design$future_builder(two_block_design$y_future_init)
two_block_cached <- two_block_design
attr(two_block_cached, "future_probe_init") <- two_block_probe
two_block_cached$future_builder <- function(...) stop("Cached future probe was not reused.", call. = FALSE)
app_validate_glofas_latent_path_design(two_block_cached)
stopifnot(nzchar(app_hash_latent_path_design(two_block_cached)))
stopifnot(is.null(attr(app_latent_path_drop_runtime_cache(two_block_cached), "future_probe_init", exact = TRUE)))
stopifnot(!isTRUE(all.equal(two_block_probe$X_beta_future, two_block_probe$X_alpha_future)))
stopifnot(identical(two_block_probe$future_discrepancy_convention, "glofas_quantile_path_minus_latent_reference_path"))

theta_mean_eq <- c(0.2, -0.1, 0.05, 0.03)
theta_cov_eq <- matrix(c(
  0.40, 0.02, 0.01, 0.00,
  0.02, 0.30, 0.00, 0.01,
  0.01, 0.00, 0.25, 0.02,
  0.00, 0.01, 0.02, 0.20
), nrow = 4L, byrow = TRUE)
y_mean_eq <- simple_design$y_future_init + c(0.05, -0.02, 0.03)
y_cov_eq <- matrix(c(0.20, 0.03, 0.01, 0.03, 0.18, 0.02, 0.01, 0.02, 0.16), nrow = 3L)
dense_eq <- app_latent_row_moments(
  simple_design, y_mean_eq, y_cov_eq, theta_mean_eq, theta_cov_eq,
  strategy = "dense_debug"
)
stream_eq <- app_latent_row_moments(
  simple_design, y_mean_eq, y_cov_eq, theta_mean_eq, theta_cov_eq,
  strategy = "streamed_grouped"
)
stopifnot(identical(as.character(app_latent_all_source(dense_eq)), as.character(app_latent_all_source(stream_eq))))
stopifnot(isTRUE(all.equal(app_latent_all_R(dense_eq), app_latent_all_R(stream_eq), tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(app_latent_all_e(dense_eq), app_latent_all_e(stream_eq), tolerance = 1.0e-8)))
constants_eq <- app_latent_al_constants(0.5)
sigma_eq <- app_latent_source_sigma_init(stream_eq$source, list(a = 2, b = 1))
e_inv_eq <- rep(1.15, length(stream_eq$source))
e_v_eq <- rep(0.95, length(stream_eq$source))
prior_eq <- app_latent_prior_state_init(
  p = ncol(simple_design$H_fixed),
  prior = "ridge",
  intercept_index = simple_design$intercept_index,
  vb_args = list(beta_ridge = list(precision = 0.7), beta_rhs = list(intercept_prec = 1.0e-9))
)
theta_dense_eq <- app_latent_update_theta(dense_eq, e_inv_eq, sigma_eq, constants_eq, prior_eq)
theta_stream_eq <- app_latent_update_theta(stream_eq, e_inv_eq, sigma_eq, constants_eq, prior_eq)
theta_stream_chunk_eq <- app_latent_update_theta(
  stream_eq,
  e_inv_eq,
  sigma_eq,
  constants_eq,
  prior_eq,
  chunking = list(enabled = TRUE, mode = "exact", chunk_size = 3L)
)
stopifnot(isTRUE(all.equal(theta_dense_eq$precision, theta_stream_eq$precision, tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(theta_dense_eq$mean, theta_stream_eq$mean, tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(theta_dense_eq$cov, theta_stream_eq$cov, tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(theta_stream_eq$precision, theta_stream_chunk_eq$precision, tolerance = 1.0e-10)))
stopifnot(isTRUE(all.equal(theta_stream_eq$mean, theta_stream_chunk_eq$mean, tolerance = 1.0e-10)))
stopifnot(isTRUE(all.equal(theta_stream_eq$cov, theta_stream_chunk_eq$cov, tolerance = 1.0e-10)))
v_dense_eq <- app_latent_update_v(dense_eq, sigma_eq, constants_eq)
v_stream_eq <- app_latent_update_v(stream_eq, sigma_eq, constants_eq)
stopifnot(isTRUE(all.equal(v_dense_eq$chi, v_stream_eq$chi, tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(v_dense_eq$psi, v_stream_eq$psi, tolerance = 1.0e-8)))
sigma_dense_eq <- app_latent_update_sigma(dense_eq, e_v_eq, e_inv_eq, constants_eq, list(a = 2, b = 1))
sigma_stream_eq <- app_latent_update_sigma(stream_eq, e_v_eq, e_inv_eq, constants_eq, list(a = 2, b = 1))
sigma_stream_chunk_eq <- app_latent_update_sigma(
  stream_eq,
  e_v_eq,
  e_inv_eq,
  constants_eq,
  list(a = 2, b = 1),
  chunking = list(enabled = TRUE, mode = "exact", chunk_size = 3L)
)
stopifnot(isTRUE(all.equal(sigma_dense_eq$shape, sigma_stream_eq$shape, tolerance = 1.0e-10)))
stopifnot(isTRUE(all.equal(sigma_dense_eq$rate, sigma_stream_eq$rate, tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(sigma_stream_eq$shape, sigma_stream_chunk_eq$shape, tolerance = 1.0e-10)))
stopifnot(isTRUE(all.equal(sigma_stream_eq$rate, sigma_stream_chunk_eq$rate, tolerance = 1.0e-10)))
obj_dense_eq <- app_latent_approx_objective(dense_eq, e_v_eq, e_inv_eq, sigma_eq, constants_eq, theta_mean_eq, theta_cov_eq, prior_eq)
obj_stream_eq <- app_latent_approx_objective(stream_eq, e_v_eq, e_inv_eq, sigma_eq, constants_eq, theta_mean_eq, theta_cov_eq, prior_eq)
stopifnot(isTRUE(all.equal(obj_dense_eq, obj_stream_eq, tolerance = 1.0e-8)))
two_block_theta_mean <- c(0.20, -0.10, 0.30, 0.40)
two_block_theta_cov <- diag(c(0.05, 0.04, 0.03, 0.02))
two_block_y_mean <- c(1.0, 1.1, 1.2)
two_block_y_cov <- diag(c(0.02, 0.02, 0.02))
two_block_dense <- app_latent_row_moments(
  two_block_design, two_block_y_mean, two_block_y_cov, two_block_theta_mean, two_block_theta_cov,
  strategy = "dense_debug"
)
two_block_stream <- app_latent_row_moments(
  two_block_design, two_block_y_mean, two_block_y_cov, two_block_theta_mean, two_block_theta_cov,
  strategy = "streamed_grouped"
)
stopifnot(isTRUE(all.equal(app_latent_all_R(two_block_dense), app_latent_all_R(two_block_stream), tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(app_latent_all_e(two_block_dense), app_latent_all_e(two_block_stream), tolerance = 1.0e-8)))
stopifnot(!is.null(two_block_stream$fixed$block))
two_block_fixed_block <- app_latent_fixed_block_design(design = two_block_design)
stopifnot(!is.null(two_block_fixed_block))
two_block_design_named_stacks <- two_block_design
two_block_design_named_stacks$X_beta_stack <- rbind(two_block_X_beta, two_block_X_beta)
two_block_design_named_stacks$X_alpha_stack <- rbind(two_block_X_alpha, two_block_X_alpha)
stopifnot(!identical(colnames(two_block_design_named_stacks$H_fixed)[two_block_design_named_stacks$beta_index],
                    colnames(two_block_design_named_stacks$X_beta_stack)))
stopifnot(!is.null(app_latent_fixed_block_design(design = two_block_design_named_stacks)))
two_block_fixed_moments <- app_latent_fixed_row_moments_block(
  two_block_fixed_block,
  two_block_design$z_fixed,
  two_block_theta_mean,
  two_block_theta_cov
)
stopifnot(isTRUE(all.equal(two_block_fixed_moments$R, two_block_dense$fixed$R, tolerance = 1.0e-10)))
stopifnot(isTRUE(all.equal(two_block_fixed_moments$e, two_block_dense$fixed$e, tolerance = 1.0e-10)))
two_block_constants <- app_latent_al_constants(0.5)
two_block_sigma <- app_latent_source_sigma_init(two_block_stream$source, list(a = 2, b = 1))
two_block_e_inv <- seq(0.9, 1.3, length.out = length(two_block_stream$source))
two_block_theta_stats_dense <- app_latent_fixed_theta_stats_chunks(
  two_block_stream,
  e_inv_v = two_block_e_inv,
  sigma_state = two_block_sigma,
  constants = two_block_constants
)
two_block_theta_stats_block <- app_latent_fixed_theta_stats_block(
  two_block_stream,
  e_inv_v = two_block_e_inv,
  sigma_state = two_block_sigma,
  constants = two_block_constants
)
stopifnot(!is.null(two_block_theta_stats_block))
stopifnot(isTRUE(all.equal(two_block_theta_stats_block$precision, two_block_theta_stats_dense$precision, tolerance = 1.0e-10)))
stopifnot(isTRUE(all.equal(two_block_theta_stats_block$rhs, two_block_theta_stats_dense$rhs, tolerance = 1.0e-10)))
two_block_stream_no_block <- two_block_stream
two_block_stream_no_block$fixed$block <- NULL
stopifnot(is.null(app_latent_fixed_theta_stats_block(
  two_block_stream_no_block,
  e_inv_v = two_block_e_inv,
  sigma_state = two_block_sigma,
  constants = two_block_constants
)))
two_block_design_bad <- two_block_design
two_block_design_bad$H_fixed[which(two_block_design_bad$source_fixed == "Y")[1L], two_block_design_bad$alpha_index[1L]] <- 0.01
stopifnot(is.null(app_latent_fixed_block_design(design = two_block_design_bad)))
two_block_lin <- app_latent_extract_future_linearization(two_block_stream, two_block_design)
stopifnot(identical(two_block_lin$strategy, "first_order_delta"))
stopifnot(!isTRUE(all.equal(two_block_lin$X_beta_future, two_block_lin$X_alpha_future)))
stopifnot(two_block_lin$J_alpha[[2L]][2L, 1L] < 0)

block_rhs_prior <- app_latent_prior_state_init(
  p = ncol(two_block_design$H_fixed),
  prior = "rhs_ns",
  intercept_index = two_block_design$intercept_index,
  beta_index = two_block_design$beta_index,
  alpha_index = two_block_design$alpha_index,
  vb_args = list(
    beta_rhs = list(tau0 = 1.0e-3, s2 = 1.0, a_zeta = 2, b_zeta = 4, intercept_prec = 1.0e-9),
    alpha_rhs = list(tau0 = 1.0e-5, s2 = 1.0, a_zeta = 2, b_zeta = 4, intercept_prec = 1.0e-9)
  )
)
stopifnot(identical(block_rhs_prior$prior, "block_rhs_ns"))
stopifnot(abs(block_rhs_prior$blocks$beta$state$tau0 - 1.0e-3) < 1.0e-15)
stopifnot(abs(block_rhs_prior$blocks$alpha$state$tau0 - 1.0e-5) < 1.0e-15)
block_rhs_prior <- app_latent_prior_state_update(block_rhs_prior, two_block_theta_mean, two_block_theta_cov)
stopifnot(length(block_rhs_prior$prior_precision) == ncol(two_block_design$H_fixed))
stopifnot(all(is.finite(block_rhs_prior$prior_precision)))

two_block_result <- list(
  fit_id = "two_block_fit",
  model_id = "two_block_model",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.5,
  fit = list(
    draws = list(
      theta = matrix(c(0.2, -0.1, 0.3, 0.4, 0.1, 0.2, 0.5, -0.2), nrow = 2L, byrow = TRUE),
      y_future = matrix(c(1.0, 1.1, 1.2, 1.2, 1.0, 0.9), nrow = 2L, byrow = TRUE)
    ),
    variational_state = list(future_linearization = two_block_lin)
  ),
  design = two_block_design,
  design_summary = data.frame(design_hash = "two_block_test_hash", stringsAsFactors = FALSE)
)
two_block_pred <- app_predict_qdesn_latent_path_draws(two_block_result, latent_panel, latent_cfg, sim$model_row)
stopifnot(nrow(two_block_pred$draws) == 6L)
stopifnot(all(abs(two_block_pred$draws$q_y_draw - (two_block_pred$draws$q_g_draw - two_block_pred$draws$d_g_draw)) < 1.0e-8))
stopifnot(identical(unique(two_block_pred$draws$prediction_state_strategy), "first_order_delta"))

future_obj_grouped <- app_latent_future_objective(
  y_mean_eq, simple_design, theta_mean_eq, theta_cov_eq, e_inv_eq, sigma_eq, constants_eq,
  strategy = "grouped"
)
future_obj_ungrouped <- app_latent_future_objective(
  y_mean_eq, simple_design, theta_mean_eq, theta_cov_eq, e_inv_eq, sigma_eq, constants_eq,
  strategy = "ungrouped_debug"
)
stopifnot(isTRUE(all.equal(future_obj_grouped, future_obj_ungrouped, tolerance = 1.0e-8)))
future_delta_eq <- app_latent_update_future_gaussian_delta(
  row_moments = stream_eq,
  y_start = y_mean_eq,
  theta_mean = theta_mean_eq,
  theta_cov = theta_cov_eq,
  e_inv_v = e_inv_eq,
  sigma_state = sigma_eq,
  constants = constants_eq
)
stopifnot(length(future_delta_eq$mean) == nrow(simple_design$future_key))
stopifnot(all(is.finite(future_delta_eq$mean)))
stopifnot(all(is.finite(future_delta_eq$cov)))
stopifnot(nrow(future_delta_eq$cov) == nrow(simple_design$future_key))

mvn_chol <- app_latent_mvn_draws_exact(
  mean = c(0.1, -0.2),
  cov = matrix(c(1.0, 0.15, 0.15, 0.7), nrow = 2L),
  n_draws = 6L,
  seed = 991L
)
stopifnot(nrow(mvn_chol) == 6L)
stopifnot(ncol(mvn_chol) == 2L)
stopifnot(all(is.finite(mvn_chol)))
stopifnot(identical(attr(mvn_chol, "backend", exact = TRUE), "chol"))
stopifnot(nrow(attr(mvn_chol, "substep_timing", exact = TRUE)) >= 4L)
mvn_fallback <- app_latent_mvn_draws_exact(
  mean = c(0, 0),
  cov = matrix(c(1, 1, 1, 1), nrow = 2L),
  n_draws = 6L,
  seed = 992L
)
stopifnot(nrow(mvn_fallback) == 6L)
stopifnot(all(is.finite(mvn_fallback)))
stopifnot(identical(attr(mvn_fallback, "backend", exact = TRUE), "eigen_fallback"))

vb_smoke <- app_fit_latent_path_al_vb_core(
  design = simple_design,
  p0 = 0.5,
  coefficient_prior = "ridge",
  vb_args = list(max_iter = 8L, min_iter_elbo = 2L, tol = 0, n_draws = 12L, prior_sigma = list(a = 2, b = 1), likelihood_family = "al"),
  seed = 123
)
vb_smoke_chunked <- app_fit_latent_path_al_vb_core(
  design = simple_design,
  p0 = 0.5,
  coefficient_prior = "ridge",
  vb_args = list(
    max_iter = 8L,
    min_iter_elbo = 2L,
    tol = 0,
    n_draws = 12L,
    prior_sigma = list(a = 2, b = 1),
    likelihood_family = "al",
    chunking = list(enabled = TRUE, mode = "exact", chunk_size = 3L)
  ),
  seed = 123
)
vb_smoke_profile <- app_fit_latent_path_al_vb_core(
  design = simple_design,
  p0 = 0.5,
  coefficient_prior = "ridge",
  vb_args = list(
    max_iter = 4L,
    min_iter_elbo = 2L,
    tol = 0,
    n_draws = 8L,
    prior_sigma = list(a = 2, b = 1),
    likelihood_family = "al",
    diagnostics = list(profile_substeps = TRUE),
    draw_backend = "chol_eigen_fallback"
  ),
  seed = 321
)
stopifnot(identical(vb_smoke$method, "vb"))
stopifnot(nrow(vb_smoke$draws$theta) == 12L)
stopifnot(nrow(vb_smoke$draws$y_future) == 12L)
stopifnot(all(is.finite(vb_smoke$vb_diagnostics$elbo_trace)))
stopifnot(all(c("prior_initialization", "initial_row_moments", "theta_draw_generation") %in% vb_smoke$vb_diagnostics$iteration_timing$step))
stopifnot(isTRUE(all.equal(vb_smoke$summary$theta_mean, vb_smoke_chunked$summary$theta_mean, tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(vb_smoke$summary$sigma_mean, vb_smoke_chunked$summary$sigma_mean, tolerance = 1.0e-8)))
stopifnot(isTRUE(all.equal(vb_smoke$vb_diagnostics$elbo_trace, vb_smoke_chunked$vb_diagnostics$elbo_trace, tolerance = 1.0e-8)))
stopifnot(nrow(vb_smoke_profile$vb_diagnostics$substep_timing) > 0L)
stopifnot(all(c("initial_row_moments", "theta_update", "theta_draw_generation", "future_draw_generation") %in%
  vb_smoke_profile$vb_diagnostics$substep_timing$parent_step))
stopifnot(vb_smoke_profile$vb_diagnostics$theta_draw_backend %in% c("chol", "eigen_fallback"))
stopifnot(vb_smoke_profile$vb_diagnostics$future_draw_backend %in% c("chol", "eigen_fallback"))
