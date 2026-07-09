#!/usr/bin/env Rscript
# Purpose: prepare the next GloFAS Q-DESN application grid centered on the
# best engine73c relaunch candidate. This script writes configs/model grids and
# a launch manifest only; it does not launch fitting.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  template_config = "application/config/glofas_latent_path_al_vb_dec25_flex8_d1n300_m360_a92_r95_w018_bt3em02_at3em02_skip_main1000_engine73c.yaml",
  batch_id = "engine73c_memory_refine16_20260529",
  run_stamp = format(Sys.time(), "%Y%m%d_%H%M"),
  core_start = "24",
  config_prefix = "glofas_latent_path_al_vb_dec25_memrefine16",
  model_grid_prefix = "model_grid_latent_path_al_vb_dec25_memrefine16",
  max_iter = "1000",
  n_draws = "2000",
  engine_path = "/data/jaguir26/local/src/exdqlm__wt__article_app_engine_73c043f",
  engine_branch = "article/app-engine-73c043f",
  engine_commit = "73c043f0436b508808366f312350fd44c2d06771"
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
  gsub("\\.", "p", out)
}

slug_win <- function(x) {
  gsub("\\.", "", sprintf("%.2f", x))
}

as_seed_label <- function(seed) {
  if (is.na(seed)) "" else sprintf("_s%d", as.integer(seed))
}

max_iter <- as.integer(args$max_iter)
n_draws <- as.integer(args$n_draws)
batch_id <- as.character(args$batch_id)[[1L]]
run_stamp <- as.character(args$run_stamp)[[1L]]
core_start <- as.integer(args$core_start)
engine_path <- normalizePath(as.character(args$engine_path)[[1L]], mustWork = TRUE)
engine_branch <- as.character(args$engine_branch)[[1L]]
engine_commit <- as.character(args$engine_commit)[[1L]]

engine_sha <- system2("git", c("-C", engine_path, "rev-parse", "HEAD"), stdout = TRUE)
engine_head_branch <- system2("git", c("-C", engine_path, "rev-parse", "--abbrev-ref", "HEAD"), stdout = TRUE)
engine_so <- file.path(engine_path, "src", "exdqlm.so")
if (!identical(engine_sha[[1L]], engine_commit)) {
  stop(sprintf("Frozen engine SHA mismatch: expected %s, found %s", engine_commit, engine_sha[[1L]]), call. = FALSE)
}
if (!identical(engine_head_branch[[1L]], engine_branch)) {
  stop(sprintf("Frozen engine branch mismatch: expected %s, found %s", engine_branch, engine_head_branch[[1L]]), call. = FALSE)
}
if (!file.exists(engine_so)) {
  stop(sprintf("Frozen engine is missing compiled shared object: %s", engine_so), call. = FALSE)
}

template <- app_read_yaml(app_resolve_path(args$template_config, must_work = TRUE))

candidates <- app_bind_rows_fill(list(
  data.frame(
    rank = 1:4,
    block = "memory_expansion",
    role = c("m300_w18_both_tau3em2", "m420_w18_both_tau3em2", "m540_w18_both_tau3em2", "m720_w18_both_tau3em2"),
    m = c(300L, 420L, 540L, 720L),
    win_scale = 0.18,
    rhs_tau0 = 0.03,
    rhs_alpha_tau0 = 0.03,
    seed = 20260512L,
    stringsAsFactors = FALSE
  ),
  data.frame(
    rank = 5:7,
    block = "input_scale",
    role = c("m360_w14_both_tau3em2", "m360_w22_both_tau3em2", "m360_w26_both_tau3em2"),
    m = 360L,
    win_scale = c(0.14, 0.22, 0.26),
    rhs_tau0 = 0.03,
    rhs_alpha_tau0 = 0.03,
    seed = 20260512L,
    stringsAsFactors = FALSE
  ),
  data.frame(
    rank = 8:11,
    block = "prior_refinement",
    role = c("m360_w18_beta1em2_alpha3em2", "m360_w18_beta3em2_alpha1em2", "m360_w18_beta1em2_alpha1em2", "m360_w18_beta1em1_alpha3em2"),
    m = 360L,
    win_scale = 0.18,
    rhs_tau0 = c(0.01, 0.03, 0.01, 0.10),
    rhs_alpha_tau0 = c(0.03, 0.01, 0.01, 0.03),
    seed = 20260512L,
    stringsAsFactors = FALSE
  ),
  data.frame(
    rank = 12:16,
    block = "seed_panel",
    role = c("m360_w18_both_tau3em2_seed20260527", "m360_w18_both_tau3em2_seed20260528", "m360_w18_both_tau3em2_seed20260529", "m360_w18_both_tau3em2_seed20260530", "m360_w18_both_tau3em2_seed20260531"),
    m = 360L,
    win_scale = 0.18,
    rhs_tau0 = 0.03,
    rhs_alpha_tau0 = 0.03,
    seed = 20260527:20260531,
    stringsAsFactors = FALSE
  )
))

rows <- vector("list", nrow(candidates))

for (i in seq_len(nrow(candidates))) {
  cand <- candidates[i, , drop = FALSE]
  slug <- sprintf(
    "d1n300_m%d_a92_r95_w%s_bt%s_at%s_skip%s",
    cand$m,
    slug_win(cand$win_scale),
    slug_tau(cand$rhs_tau0),
    slug_tau(cand$rhs_alpha_tau0),
    if (cand$block == "seed_panel") as_seed_label(cand$seed) else ""
  )
  app_name <- sprintf("%s_%s_main1000_engine73c", args$config_prefix, slug)
  config_path <- file.path("application/config", sprintf("%s.yaml", app_name))
  model_grid_path <- file.path("application/config", sprintf("%s_%s_main1000_engine73c.csv", args$model_grid_prefix, slug))

  cfg <- template
  cfg$application_name <- app_name
  cfg$description <- sprintf(
    paste(
      "Median-only Dec. 25, 2022 memory-refinement latent-path ensemble-likelihood",
      "Q-DESN application candidate %d/16 (%s; %s). Uses D=1, n=300,",
      "m=%d, alpha=0.92, rho=0.95, pi_w=0.03, pi_in=1.00, win scales",
      "%.2f/%.2f, raw input readout skip enabled, AL-VB, n_draws=%d,",
      "max_iter=%d, beta RHS tau0=%.4g, discrepancy RHS tau0=%.4g,",
      "and reservoir seed %d. This preparation script does not launch fitting."
    ),
    i,
    cand$block,
    cand$role,
    cand$m,
    cand$win_scale,
    cand$win_scale,
    n_draws,
    max_iter,
    cand$rhs_tau0,
    cand$rhs_alpha_tau0,
    cand$seed
  )
  cfg$paths$model_grid <- model_grid_path
  cfg$paths$cache <- file.path("application/cache", app_name)
  cfg$dependencies$qdesn_engine_repo_hint <- engine_path
  cfg$dependencies$qdesn_engine_expected_repo_hint <- engine_path
  cfg$dependencies$qdesn_engine_required_branch <- engine_branch
  cfg$dependencies$qdesn_engine_required_commit <- engine_commit

  cfg$reservoir$D <- 1L
  cfg$reservoir[["n"]] <- 300L
  cfg$reservoir$n_tilde <- list()
  cfg$reservoir$m <- as.integer(cand$m)
  cfg <- apply_memory_contract(cfg, cand$m)
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- 0.92
  cfg$reservoir$rho <- 0.95
  cfg$reservoir$pi_w <- 0.03
  cfg$reservoir$pi_in <- 1.0
  cfg$reservoir$win_scale_global <- cand$win_scale
  cfg$reservoir$win_scale_bias <- cand$win_scale
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$seed <- as.integer(cand$seed)

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
    "Memory-refinement candidate %d/16 (%s): generated from current best engine73c relaunch candidate; requires preflight before explicit launch.",
    i,
    cand$role
  )
  cfg$execution$prelaunch$enabled <- FALSE
  cfg$execution$prelaunch$purpose <- "memory_refinement_candidate_preparation_only"
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- sprintf(
    "Memory-refinement candidate %d/16 %s; launch only after explicit confirmation.",
    i,
    cand$role
  )

  raw_fit_id <- sprintf("raw_glofas_latent_path_%s_p50_engine73c", slug)
  qdesn_fit_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s_p50_engine73c", slug)
  model_grid <- data.frame(
    fit_id = c(raw_fit_id, qdesn_fit_id),
    model_id = c(raw_fit_id, qdesn_fit_id),
    model_family = c("raw_glofas", "qdesn_glofas_discrepancy"),
    quantile_level = c(0.5, 0.5),
    inference_method = c("none", "vb_ld"),
    coefficient_prior = c("none", "rhs"),
    reservoir_seed = c(NA, as.integer(cand$seed)),
    likelihood_family = c("none", "al"),
    required = c("true", "true"),
    enabled = c("true", "true"),
    config_hash = c("TO_BE_COMPUTED", "TO_BE_COMPUTED"),
    notes = c(
      sprintf("Raw GloFAS ensemble median baseline for memory-refinement candidate %d/16 (%s).", i, cand$role),
      sprintf(
        paste(
          "Median-only memory-refinement latent-path two-block ensemble-likelihood",
          "Q-DESN candidate %d/16 (%s; %s) with input readout skip, beta RHS",
          "tau0=%.4g, discrepancy RHS tau0=%.4g, reservoir seed %d,",
          "frozen engine73c, and AL-VB max_iter=%d."
        ),
        i,
        cand$block,
        cand$role,
        cand$rhs_tau0,
        cand$rhs_alpha_tau0,
        cand$seed,
        max_iter
      )
    ),
    stringsAsFactors = FALSE
  )

  app_write_yaml(cfg, app_path(config_path))
  app_write_csv(model_grid, app_path(model_grid_path))

  rows[[i]] <- data.frame(
    batch_id = batch_id,
    run_index = i,
    relaunch_group = cand$block,
    source_config = as.character(args$template_config)[[1L]],
    target_config = config_path,
    source_model_grid = as.character(template$paths$model_grid)[[1L]],
    target_model_grid = model_grid_path,
    engine_path = engine_path,
    engine_branch = engine_branch,
    engine_commit = engine_commit,
    run_id = sprintf("engine73c_memrefine16_%02d_%s_%s", i, slug, run_stamp),
    core = core_start + i - 1L,
    role = cand$role,
    D = 1L,
    n = 300L,
    m = cand$m,
    alpha = 0.92,
    rho = 0.95,
    pi_w = 0.03,
    pi_in = 1.0,
    win_scale_global = cand$win_scale,
    win_scale_bias = cand$win_scale,
    rhs_tau0 = cand$rhs_tau0,
    rhs_alpha_tau0 = cand$rhs_alpha_tau0,
    seed = as.integer(cand$seed),
    launch_status = "prepared_not_launched",
    stringsAsFactors = FALSE
  )
}

manifest <- app_bind_rows_fill(rows)
manifest_path <- file.path("application/config", paste0("glofas_", batch_id, "_launch_manifest.csv"))
app_write_csv(manifest, app_path(manifest_path))

cat(sprintf("wrote %s\n", manifest_path))
cat(sprintf("candidate_configs=%d\n", nrow(manifest)))
