repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/glofas_part3_historical_forecast.R"))

make_context <- function(n, alpha, static, future_index) {
  list(
    reservoir = list(W = list(diag(0.15, n)), Win = list(matrix(seq_len(n * (ncol(static) + 1L)) / 100, n)), alpha = list(alpha), act_f = "tanh"),
    state0 = seq_len(n) / 20,
    meta = list(lag_center = rep(0, ncol(static)), lag_scale = rep(1, ncol(static)), standardize_inputs = FALSE, input_bound = "none", win_scale_global = 1, win_scale_bias = 1),
    compiled = list(static_values = static, future_index = future_index)
  )
}
H <- 4L
ref <- make_context(3L, 0.5, matrix(c(1, 2, 3, 4, 0.2, 0, 0, 0), H), matrix(c(0, 0, 0, 0, 0, 1, 2, 3), H))
disc <- make_context(2L, 0.8, matrix(c(-1, -2, -3, -4, 0.1, 0, 0, 0), H), matrix(c(0, 0, 0, 0, 0, 1, 2, 3), H))
beta_ref <- rbind(c(0.2, 0.3, -0.1, 0.4), c(0.5, -0.2, 0.1, 0.2))
beta_disc <- rbind(c(-0.1, 0.2, 0.1), c(0.1, -0.3, 0.2))
r_quantile <- app_glofas_part3_quantile_forecast_r(ref, disc, beta_ref, beta_disc)
stopifnot(app_glofas_part3_load_forecast_cpp(TRUE))
cpp_quantile <- do.call(glofas_part3_d1_quantile_recursive_cpp, c(
  app_glofas_part3_component_cpp_args(ref, "reference"), list(beta_reference = beta_ref),
  app_glofas_part3_component_cpp_args(disc, "discrepancy"), list(beta_discrepancy = beta_disc)
))
stopifnot(isTRUE(all.equal(r_quantile$reference, cpp_quantile$reference, tolerance = 1.0e-12)))
stopifnot(isTRUE(all.equal(r_quantile$discrepancy, cpp_quantile$discrepancy, tolerance = 1.0e-12)))
stopifnot(isTRUE(all.equal(cpp_quantile$glofas, cpp_quantile$reference + cpp_quantile$discrepancy, tolerance = 0)))

beta_ref_draw <- rbind(beta_ref[1, ], beta_ref[2, ], beta_ref[1, ] + 0.05)
beta_disc_draw <- rbind(beta_disc[1, ], beta_disc[2, ], beta_disc[1, ] - 0.03)
sigma <- c(0.1, 0.2, 0.15)
z_ref <- matrix(seq_len(H * 3L) / 10, H, 3L)
z_g <- -z_ref
r_normal <- app_glofas_part3_normal_forecast_r(ref, disc, beta_ref_draw, beta_disc_draw, sigma, z_ref, z_g)
cpp_normal <- do.call(glofas_part3_d1_normal_draw_recursive_cpp, c(
  app_glofas_part3_component_cpp_args(ref, "reference"), list(beta_reference_draws = beta_ref_draw),
  app_glofas_part3_component_cpp_args(disc, "discrepancy"),
  list(beta_discrepancy_draws = beta_disc_draw, sigma_draws = sigma, z_reference = z_ref, z_glofas = z_g)
))
for (nm in c("reference_mean_draws", "discrepancy_mean_draws", "glofas_mean_draws", "reference_draws", "discrepancy_draws", "glofas_draws")) {
  stopifnot(isTRUE(all.equal(r_normal[[nm]], cpp_normal[[nm]], tolerance = 1.0e-12)))
}
stopifnot(isTRUE(all.equal(cpp_normal$discrepancy_draws, cpp_normal$glofas_draws - cpp_normal$reference_draws, tolerance = 0)))

dates <- as.Date("2022-01-01") + 0:9
design <- list(
  dates = dates,
  y_reference = seq(0.1, 1, length.out = 10),
  d_g = seq(-0.2, 0.2, length.out = 10)
)
design$g_retrospective <- design$y_reference + design$d_g
cpp_normal$origin <- list(origin_index = 6L, origin_date = dates[[6L]], future_index = 7:10, future_dates = dates[7:10], horizon_days = 4L)
cpp_normal$historical <- list(
  reference = matrix(design$y_reference + 0.01, ncol = 1L),
  discrepancy = matrix(design$d_g - 0.01, ncol = 1L),
  glofas = matrix(design$g_retrospective, ncol = 1L)
)
path_table <- app_glofas_part3_forecast_path_table(cpp_normal, design)
stopifnot(all(c("historical_fit", "forecast") %in% path_table$segment))
pdf_path <- tempfile(fileext = ".pdf")
app_glofas_part3_plot_forecast(cpp_normal, design, pdf_path, last_history = 4L)
stopifnot(file.exists(pdf_path), file.info(pdf_path)$size > 1000)
unlink(pdf_path)
cat("test_glofas_part3_historical_forecast: OK\n")
