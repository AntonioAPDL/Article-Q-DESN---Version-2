repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
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
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))
source(app_path("application/R/glofas_part3_partitioned_rhs.R"))
source(app_path("application/R/glofas_part3_quantile_bridge.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_part1_quantile_oracle_forecast.R"))
source(app_path("application/R/glofas_dec25_final_refit_workflow.R"))

source_root <- Sys.getenv(
  "APP_GLOFAS_JEREZ_SOURCE_ROOT",
  unset = "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__glofas_part2_rhs_jerez_20260904"
)
base_config <- file.path(
  source_root,
  "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml"
)
if (!file.exists(base_config)) {
  cat("test_glofas_dec25_real_data_smoke: SKIP missing Jerez local input config\n")
  quit(status = 0L, save = "no")
}

cfg <- app_read_config(base_config)
bundle <- app_glofas_oracle_prepare_panel_bundle(
  cfg = cfg,
  origin_date = as.Date("2022-12-25"),
  horizon_days = 30L,
  target = "discrepancy"
)
app_glofas_dec25_assert_window("2022-12-25", 30L, bundle$future_dates, label = "real-data smoke")
stopifnot(bundle$max_score_horizon == 0L)
stopifnot(sum(is.finite(bundle$future_truth$y_transformed)) == 0L)

panel <- bundle$panel
idx <- which(
  as.Date(panel$date) <= as.Date("2022-12-25") &
    is.finite(panel$y_transformed) &
    is.finite(panel$original_y_transformed) &
    is.finite(panel$g_transformed) &
    is.finite(panel$ppt_scaled) &
    is.finite(panel$soil_scaled)
)
idx <- utils::tail(idx, 80L)
stopifnot(length(idx) == 80L)
dates <- as.Date(panel$date[idx])
stopifnot(max(dates) == as.Date("2022-12-25"))
usgs <- as.numeric(panel$original_y_transformed[idx])
glofas <- as.numeric(panel$g_transformed[idx])
disc <- as.numeric(panel$y_transformed[idx])
stopifnot(max(abs(glofas - usgs - disc)) < 1.0e-10)

scale_vec <- function(x) as.numeric(scale(x))
X <- cbind(
  readout_intercept = 1,
  ppt_scaled = scale_vec(panel$ppt_scaled[idx]),
  soil_scaled = scale_vec(panel$soil_scaled[idx])
)
X[!is.finite(X)] <- 0
Z <- X[, -1L, drop = FALSE]

ridge <- app_glofas_normal_ridge_fit(X, disc)
warm <- list(
  type = "glofas_normal_part1_ridge_warm_start",
  version = "0.1",
  candidate_id = "real_data_smoke",
  design = list(colnames = colnames(X)),
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
  X = X,
  y = disc,
  ridge_warm_start = warm,
  tau0 = 1,
  max_iter = 4L,
  min_iter = 1L,
  tol = 1.0e9,
  freeze_beta_warmup_iters = 2L,
  min_beta_updates = 2L
)
stopifnot(rhs$trace$beta_update_count[[4L]] == 2L)

controls <- app_glofas_part1_quantile_default_controls(
  max_iter = 4L,
  min_iter = 1L,
  tol = 1.0e9,
  tau0 = 1,
  rhs_vb_inner = 1L,
  exal_prefit_max_iter = 2L,
  progress_every = 0L,
  freeze_beta_warmup_iters = 2L,
  min_beta_updates = 2L
)
fit_al <- app_glofas_part1_quantile_fit_readout(disc, Z, tau = 0.5, model_family = "independent_al", controls = controls)
fit_exal <- app_glofas_part1_quantile_fit_readout(disc, Z, tau = 0.5, model_family = "independent_exal", controls = modifyList(controls, list(init = fit_al)))
fit_joint_al <- app_glofas_part1_quantile_fit_readout(disc, Z, tau = c(0.2, 0.5, 0.8), model_family = "joint_al", controls = controls)
fit_joint_exal <- app_glofas_part1_quantile_fit_readout(disc, Z, tau = c(0.2, 0.5, 0.8), model_family = "joint_exal", controls = modifyList(controls, list(init = fit_joint_al)))
stopifnot(all(c(fit_al$converged, fit_exal$converged, fit_joint_al$converged, fit_joint_exal$converged)))

R <- cbind(readout_intercept = 1, usgs_state = scale_vec(usgs), ppt_state = X[, "ppt_scaled"])
D <- cbind(readout_intercept = 1, discrepancy_state = scale_vec(disc), soil_state = X[, "soil_scaled"])
R[!is.finite(R)] <- 0
D[!is.finite(D)] <- 0
design3 <- list(
  dates = dates,
  H = rbind(cbind(R, matrix(0, nrow(R), ncol(D))), cbind(R, D)),
  z = c(usgs, glofas),
  source = c(rep("Y", length(usgs)), rep("G", length(glofas))),
  n_dates = length(dates),
  reference = list(X = R),
  discrepancy = list(X = D),
  y_reference = usgs,
  g_retrospective = glofas,
  d_g = disc,
  beta_index = seq_len(ncol(R)),
  alpha_index = ncol(R) + seq_len(ncol(D)),
  p_beta = ncol(R),
  p_alpha = ncol(D),
  design_hash = list(reference_full = "real_smoke_r", discrepancy_full = "real_smoke_d", part3_stacked_full = "real_smoke_h")
)
split3 <- list(train_idx = 1:64, valid_idx = 65:80)
controls3 <- app_glofas_part3_quantile_default_controls(
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
fit3_al <- app_glofas_part3_quantile_fit(design3, split3, tau = 0.5, likelihood = "AL", fit_structure = "independent", controls = controls3, fit_id = "real_p3_al")
fit3_exal <- app_glofas_part3_quantile_fit(design3, split3, tau = 0.5, likelihood = "exAL", fit_structure = "independent", controls = controls3, init = fit3_al, fit_id = "real_p3_exal")
stopifnot(fit3_al$trace$beta_update_count[[4L]] == 2L)
stopifnot(fit3_exal$trace$beta_update_count[[4L]] == 2L)

cat("test_glofas_dec25_real_data_smoke: OK\n")
