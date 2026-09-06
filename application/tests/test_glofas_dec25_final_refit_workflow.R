repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_exqdesn_exact_structured_inference.R"))
source(app_path("application/R/joint_exqdesn_inference_dispatch.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))
source(app_path("application/R/glofas_part3_partitioned_rhs.R"))
source(app_path("application/R/glofas_part3_quantile_bridge.R"))
source(app_path("application/R/glofas_part1_quantile_oracle_forecast.R"))
source(app_path("application/R/glofas_dec25_final_refit_workflow.R"))

c <- app_glofas_dec25_contract()
future_dates <- app_glofas_dec25_expected_future_dates()
stopifnot(length(future_dates) == 30L)
stopifnot(min(future_dates) == as.Date("2022-12-26"))
stopifnot(max(future_dates) == as.Date("2023-01-24"))
stopifnot(isTRUE(app_glofas_dec25_assert_window("2022-12-25", 30L, future_dates)))

bad_origin <- tryCatch({
  app_glofas_dec25_assert_window("2022-11-25", 30L, future_dates)
  FALSE
}, error = function(e) grepl("2022-12-25", conditionMessage(e), fixed = TRUE))
bad_horizon <- tryCatch({
  app_glofas_dec25_assert_window("2022-12-25", 29L, future_dates[1:29])
  FALSE
}, error = function(e) grepl("horizon_days=30", conditionMessage(e), fixed = TRUE))
stopifnot(isTRUE(bad_origin), isTRUE(bad_horizon))

dates <- seq.Date(c$train_end - (c$part2_final_train_rows - 1L), c$train_end, by = "day")
y <- sin(seq_along(dates) / 40)
d <- cos(seq_along(dates) / 55)
g <- y + d
X <- cbind(readout_intercept = 1, reservoir_0001 = y / 10, reservoir_0002 = d / 10)
design2 <- list(
  dates = dates,
  y_reference = y,
  g_retrospective = g,
  d_g = d,
  discrepancy = list(X = X, y = d, feature_info = data.frame(feature = colnames(X), stringsAsFactors = FALSE)),
  design_hash = list(discrepancy_full = "synthetic")
)
split2 <- app_glofas_dec25_validate_part2_design(design2)
stopifnot(length(split2$train_idx) == 12495L, length(split2$valid_idx) == 0L)
wrong2 <- design2
wrong2$d_g <- -wrong2$d_g
bad_sign2 <- tryCatch({
  app_glofas_dec25_validate_part2_design(wrong2)
  FALSE
}, error = function(e) grepl("GloFAS_t - USGS_t", conditionMessage(e), fixed = TRUE))
stopifnot(isTRUE(bad_sign2))

R <- cbind(readout_intercept = 1, reference_state = y / 5)
D <- cbind(readout_intercept = 1, discrepancy_state = d / 5)
design3 <- list(
  dates = dates,
  H = rbind(cbind(R, matrix(0, nrow(R), ncol(D))), cbind(R, D)),
  z = c(y, g),
  source = c(rep("Y", length(y)), rep("G", length(g))),
  n_dates = length(dates),
  reference = list(X = R),
  discrepancy = list(X = D),
  y_reference = y,
  g_retrospective = g,
  d_g = d,
  beta_index = seq_len(ncol(R)),
  alpha_index = ncol(R) + seq_len(ncol(D)),
  p_beta = ncol(R),
  p_alpha = ncol(D),
  design_hash = list(reference_full = "r", discrepancy_full = "d", part3_stacked_full = "h")
)
split3 <- app_glofas_dec25_validate_part3_design(design3)
stopifnot(length(split3$train_idx) == 12495L, nrow(design3$H) == 24990L)

x_raw <- matrix(c(1, 2, 3, 4, 2, 3, 4, 5), ncol = 2)
beta_old <- c(0.3, 1.2, -0.7)
beta_new <- app_glofas_dec25_affine_remap_coefficients(
  beta_old,
  old_center = c(2, 3),
  old_scale = c(1.5, 2.5),
  new_center = c(1, 4),
  new_scale = c(2, 3)
)
app_glofas_dec25_assert_affine_prediction_equivalence(
  beta_old,
  beta_new,
  x_raw,
  old_center = c(2, 3),
  old_scale = c(1.5, 2.5),
  new_center = c(1, 4),
  new_scale = c(2, 3)
)

set.seed(19)
small_X <- cbind(readout_intercept = 1, x1 = rnorm(40), x2 = rnorm(40))
small_y <- as.numeric(0.2 + small_X[, "x1"] - 0.5 * small_X[, "x2"] + rnorm(40, sd = 0.1))
ridge <- app_glofas_normal_ridge_fit(small_X, small_y)
warm <- list(
  type = "glofas_normal_part1_ridge_warm_start",
  version = "0.1",
  candidate_id = "freeze_test",
  design = list(colnames = colnames(small_X)),
  fit = list(
    beta_mean = as.numeric(ridge$beta_mean),
    beta_var_diag = as.numeric(ridge$beta_var_diag),
    sigma_a = ridge$sigma_a,
    sigma_b = ridge$sigma_b,
    sigma2_mean = ridge$sigma2_mean,
    ridge_tau2 = ridge$ridge_tau2,
    intercept_var = ridge$intercept_var,
    n_train = ridge$n_train,
    p = ridge$p
  )
)
class(warm) <- c("glofas_normal_part1_ridge_warm_start", "list")
rhs <- app_glofas_normal_rhs_fit(
  X = small_X,
  y = small_y,
  ridge_warm_start = warm,
  tau0 = 1,
  max_iter = 25L,
  min_iter = 1L,
  tol = 1.0e9,
  freeze_beta_warmup_iters = 20L,
  min_beta_updates = 3L
)
stopifnot(nrow(rhs$trace) == 23L)
stopifnot(!any(rhs$trace$beta_updated[rhs$trace$iter <= 20L]))
stopifnot(all(rhs$trace$beta_updated[rhs$trace$iter >= 21L]))
stopifnot(rhs$trace$beta_update_count[[23L]] == 3L)
stopifnot(!any(rhs$trace$convergence_eligible[rhs$trace$iter < 23L]))
stopifnot(isTRUE(rhs$converged))

controls_q <- app_glofas_part1_quantile_default_controls(
  max_iter = 4L,
  min_iter = 1L,
  tol = 1.0e9,
  tau0 = 1,
  rhs_vb_inner = 1L,
  progress_every = 0L,
  freeze_beta_warmup_iters = 2L,
  min_beta_updates = 2L
)
fit_q <- app_glofas_part1_quantile_fit_readout(
  y = small_y,
  Z = small_X[, -1L, drop = FALSE],
  tau = 0.5,
  model_family = "independent_al",
  controls = controls_q
)
stopifnot(nrow(fit_q$trace) == 4L)
stopifnot(!any(fit_q$trace$beta_updated[1:2]))
stopifnot(all(fit_q$trace$beta_updated[3:4]))
stopifnot(fit_q$trace$beta_update_count[[4L]] == 2L)
stopifnot(isTRUE(fit_q$trace$convergence_eligible[[4L]]))

tiny3 <- design3
tiny3$dates <- as.Date("2020-01-01") + 0:39
tiny3$y_reference <- small_y
tiny3$d_g <- as.numeric(0.1 + small_X[, "x2"] / 4)
tiny3$g_retrospective <- tiny3$y_reference + tiny3$d_g
tiny3$reference <- list(X = small_X[, 1:2, drop = FALSE])
tiny3$discrepancy <- list(X = small_X[, c(1, 3), drop = FALSE])
tiny3$p_beta <- ncol(tiny3$reference$X)
tiny3$p_alpha <- ncol(tiny3$discrepancy$X)
tiny3$H <- rbind(
  cbind(tiny3$reference$X, matrix(0, 40L, tiny3$p_alpha)),
  cbind(tiny3$reference$X, tiny3$discrepancy$X)
)
tiny3$z <- c(tiny3$y_reference, tiny3$g_retrospective)
tiny3$source <- c(rep("Y", 40L), rep("G", 40L))
tiny3$n_dates <- 40L
tiny3$beta_index <- seq_len(tiny3$p_beta)
tiny3$alpha_index <- tiny3$p_beta + seq_len(tiny3$p_alpha)
split_tiny3 <- list(train_idx = 1:32, valid_idx = 33:40)
controls_p3 <- app_glofas_part3_quantile_default_controls(
  max_iter = 4L,
  min_iter = 1L,
  tol = 1.0e9,
  rhs_vb_inner = 1L,
  progress_every = 0L,
  quadrature_nodes = c(4L, 6L),
  diagnostic_stride = 1L,
  freeze_beta_warmup_iters = 2L,
  min_beta_updates = 2L
)
fit_p3 <- app_glofas_part3_quantile_fit(
  tiny3,
  split_tiny3,
  tau = 0.5,
  likelihood = "AL",
  fit_structure = "independent",
  controls = controls_p3,
  init = NULL,
  fit_id = "p3_freeze_test"
)
stopifnot(nrow(fit_p3$trace) == 4L)
stopifnot(!any(fit_p3$trace$beta_updated[1:2]))
stopifnot(all(fit_p3$trace$beta_updated[3:4]))
stopifnot(fit_p3$trace$beta_update_count[[4L]] == 2L)
stopifnot(isTRUE(fit_p3$trace$convergence_eligible[[4L]]))

cat("test_glofas_dec25_final_refit_workflow: OK\n")
