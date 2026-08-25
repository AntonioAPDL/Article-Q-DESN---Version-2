#!/usr/bin/env Rscript
# Purpose: prepare a higher-flexibility D1 n300 application batch after the
# diverse8 runs showed visible underfitting. This writes configs/model grids
# only; it does not launch fitting, scoring, or promotion.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  template_config = "application/config/glofas_latent_path_al_vb_dec25_diverse8_d1n300_m100_a92_r95_w15_tau3em3_main1000.yaml",
  output_batch = "application/config/glofas_flex_reservoir_pilot_batch_20260526.csv",
  config_prefix = "glofas_latent_path_al_vb_dec25_flex8",
  model_grid_prefix = "model_grid_latent_path_al_vb_dec25_flex8",
  max_iter = "1000",
  n_draws = "2000"
))

set_lag_range <- function(lo, hi) {
  list(range = c(as.integer(lo), as.integer(hi)))
}

apply_memory_contract <- function(cfg, m) {
  m <- as.integer(m)
  cfg$feature_contract$reservoir_input$output_lags <- set_lag_range(1L, m)
  covariates <- names(cfg$feature_contract$reservoir_input$covariates %||% list())
  for (v in covariates) {
    cfg$feature_contract$reservoir_input$covariates[[v]] <- set_lag_range(0L, m)
  }
  cfg$feature_contract$readout$input_block$output_lags <- set_lag_range(1L, m)
  readout_covariates <- names(cfg$feature_contract$readout$input_block$covariates %||% list())
  for (v in readout_covariates) {
    cfg$feature_contract$readout$input_block$covariates[[v]] <- set_lag_range(0L, m)
  }
  cfg$covariates$readout$lags <- set_lag_range(0L, m)
  cfg
}

slug_tau <- function(x) {
  out <- format(x, scientific = TRUE, digits = 1)
  out <- gsub("\\+", "", out)
  out <- gsub("-", "m", out)
  out <- gsub("\\.", "p", out)
  out
}

fmt <- function(x) {
  format(x, scientific = FALSE, trim = TRUE)
}

max_iter <- as.integer(args$max_iter)
n_draws <- as.integer(args$n_draws)
template <- app_read_yaml(app_resolve_path(args$template_config, must_work = TRUE))

candidates <- data.frame(
  rank = seq_len(8L),
  role = c(
    "m180_alpha_tau1em2_skip",
    "m180_alpha_tau3em2_skip",
    "m180_alpha_tau1em1_skip",
    "m360_alpha_tau3em2_skip",
    "m360_alpha_tau1em1_skip",
    "m360_w18_both_tau3em2_skip",
    "m180_w22_alpha_tau1em1_skip",
    "m360_w22_alpha_tau1em1_skip"
  ),
  m = c(180L, 180L, 180L, 360L, 360L, 360L, 180L, 360L),
  rho = c(0.95, 0.95, 0.95, 0.95, 0.95, 0.95, 0.95, 0.95),
  alpha = c(0.92, 0.92, 0.92, 0.92, 0.92, 0.92, 0.92, 0.92),
  win_scale = c(0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.22, 0.22),
  rhs_tau0 = c(0.003, 0.003, 0.003, 0.003, 0.003, 0.03, 0.003, 0.003),
  rhs_alpha_tau0 = c(0.01, 0.03, 0.1, 0.03, 0.1, 0.03, 0.1, 0.1),
  stringsAsFactors = FALSE
)

rows <- vector("list", nrow(candidates))

for (i in seq_len(nrow(candidates))) {
  cand <- candidates[i, , drop = FALSE]
  slug <- sprintf(
    "d1n300_m%d_a92_r95_w%s_bt%s_at%s_skip",
    cand$m,
    gsub("\\.", "", sprintf("%.2f", cand$win_scale)),
    slug_tau(cand$rhs_tau0),
    slug_tau(cand$rhs_alpha_tau0)
  )
  app_name <- sprintf("%s_%s_main1000", args$config_prefix, slug)
  config_path <- file.path("application/config", sprintf("%s_%s_main1000.yaml", args$config_prefix, slug))
  model_grid_path <- file.path("application/config", sprintf("%s_%s_main1000.csv", args$model_grid_prefix, slug))

  cfg <- template
  cfg$application_name <- app_name
  cfg$description <- sprintf(
    paste(
      "Median-only Dec. 25, 2022 higher-flexibility latent-path",
      "ensemble-likelihood Q-DESN application candidate %d/8 (%s).",
      "Uses D=1, n=300, m=%d, alpha=%.2f, rho=%.2f, pi_w=0.03,",
      "pi_in=1.00, win scales %.2f/%.2f, raw input readout skip enabled,",
      "AL-VB, n_draws=%d, max_iter=%d, beta RHS tau0=%.4g, and",
      "discrepancy RHS tau0=%.4g. This preparation script does not launch",
      "application fitting."
    ),
    i,
    cand$role,
    cand$m,
    cand$alpha,
    cand$rho,
    cand$win_scale,
    cand$win_scale,
    n_draws,
    max_iter,
    cand$rhs_tau0,
    cand$rhs_alpha_tau0
  )
  cfg$paths$model_grid <- model_grid_path
  cfg$paths$cache <- file.path("application/cache", app_name)

  cfg$reservoir$D <- 1L
  cfg$reservoir[["n"]] <- 300L
  cfg$reservoir$n_tilde <- list()
  cfg$reservoir$m <- as.integer(cand$m)
  cfg <- apply_memory_contract(cfg, cand$m)
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- cand$alpha
  cfg$reservoir$rho <- cand$rho
  cfg$reservoir$pi_w <- 0.03
  cfg$reservoir$pi_in <- 1.0
  cfg$reservoir$win_scale_global <- cand$win_scale
  cfg$reservoir$win_scale_bias <- cand$win_scale
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$seed <- 20260512L

  cfg$feature_contract$readout$include_input_block <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$include_horizon_scaled <- FALSE

  cfg$inference$vb_ld$max_iter <- max_iter
  cfg$inference$vb_ld$max_iter_hard_cap <- max_iter
  cfg$inference$vb_ld$n_draws <- n_draws
  cfg$inference$vb_ld$rhs_tau0 <- cand$rhs_tau0
  cfg$inference$vb_ld$rhs_alpha_tau0 <- cand$rhs_alpha_tau0
  cfg$inference$vb_ld$rhs_slab_s2 <- 1.0
  cfg$inference$vb_ld$rhs_alpha_slab_s2 <- 1.0
  cfg$inference$mcmc$rhs_tau0 <- cand$rhs_tau0
  cfg$inference$mcmc$rhs_alpha_tau0 <- cand$rhs_alpha_tau0
  cfg$inference$mcmc$rhs_slab_s2 <- 1.0
  cfg$inference$mcmc$rhs_alpha_slab_s2 <- 1.0

  cfg$execution$inference_support$note <- sprintf(
    "Flex candidate %d/8 (%s): no new reservoir screen requested; requires sampler-free design/preflight before any explicit launch.",
    i,
    cand$role
  )
  cfg$execution$prelaunch$enabled <- FALSE
  cfg$execution$prelaunch$purpose <- "higher_flexibility_candidate_preparation_only"
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- sprintf(
    "Flex candidate %d/8 %s; launch only after explicit confirmation.",
    i,
    cand$role
  )

  raw_fit_id <- sprintf("raw_glofas_latent_path_%s_p50", slug)
  qdesn_fit_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s_p50", slug)
  model_grid <- data.frame(
    fit_id = c(raw_fit_id, qdesn_fit_id),
    model_id = c(raw_fit_id, qdesn_fit_id),
    model_family = c("raw_glofas", "qdesn_glofas_discrepancy"),
    quantile_level = c(0.5, 0.5),
    inference_method = c("none", "vb_ld"),
    coefficient_prior = c("none", "rhs"),
    reservoir_seed = c(NA, 20260512L),
    likelihood_family = c("none", "al"),
    required = c("true", "true"),
    enabled = c("true", "true"),
    config_hash = c("TO_BE_COMPUTED", "TO_BE_COMPUTED"),
    notes = c(
      sprintf("Raw GloFAS ensemble median baseline for flex candidate %d/8 (%s).", i, cand$role),
      sprintf(
        paste(
          "Median-only higher-flexibility latent-path two-block",
          "ensemble-likelihood Q-DESN candidate %d/8 (%s) with input",
          "readout skip, beta RHS tau0=%.4g, discrepancy RHS tau0=%.4g,",
          "and AL-VB max_iter=%d."
        ),
        i,
        cand$role,
        cand$rhs_tau0,
        cand$rhs_alpha_tau0,
        max_iter
      )
    ),
    stringsAsFactors = FALSE
  )

  app_write_yaml(cfg, app_path(config_path))
  app_write_csv(model_grid, app_path(model_grid_path))

  rows[[i]] <- data.frame(
    rank = i,
    role = cand$role,
    config_path = config_path,
    model_grid_path = model_grid_path,
    run_id_template = sprintf("flex8_%02d_%s_YYYYMMDD_HHMMSS", i, slug),
    D = 1L,
    n = 300L,
    n_tilde = "",
    m = cand$m,
    washout = 500L,
    alpha = cand$alpha,
    rho = cand$rho,
    pi_w = 0.03,
    pi_in = 1.0,
    win_scale_global = cand$win_scale,
    win_scale_bias = cand$win_scale,
    include_input_block = TRUE,
    rhs_tau0 = cand$rhs_tau0,
    rhs_alpha_tau0 = cand$rhs_alpha_tau0,
    rhs_slab_s2 = 1.0,
    rhs_alpha_slab_s2 = 1.0,
    vb_max_iter = max_iter,
    vb_n_draws = n_draws,
    seed = 20260512L,
    launch_status = "prepared_not_launched",
    stringsAsFactors = FALSE
  )
}

batch <- app_bind_rows_fill(rows)
app_write_csv(batch, app_path(args$output_batch))

cat(sprintf("wrote %s\n", args$output_batch))
cat(sprintf("candidate_configs=%d\n", nrow(batch)))
