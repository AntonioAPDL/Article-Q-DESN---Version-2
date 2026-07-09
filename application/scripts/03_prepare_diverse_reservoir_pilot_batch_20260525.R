#!/usr/bin/env Rscript
# Purpose: prepare the screened diverse reservoir-candidate batch as tracked
# launch-ready configs/model grids. This script writes configuration artifacts
# only; it does not launch VB, MCMC, scoring, or promotion.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  template_config = "application/config/glofas_latent_path_al_vb_dec25_d1n300_tau3em3_main1000.yaml",
  shortlist_metrics = "application/outputs/generated/reservoir_screening/reservoir_shortlist_multiseed_full_20260525/pilot_triage_candidates.csv",
  shortlist_grid = "application/config/reservoir_candidate_grid_latent_path_shortlist_multiseed_20260525.csv",
  output_batch = "application/config/glofas_diverse_reservoir_pilot_batch_20260525.csv",
  output_reservoir_grid = "application/config/reservoir_candidate_grid_latent_path_diverse_pilot_batch_20260525.csv",
  config_prefix = "glofas_latent_path_al_vb_dec25_diverse8",
  model_grid_prefix = "model_grid_latent_path_al_vb_dec25_diverse8",
  max_iter = "1000",
  n_draws = "2000",
  rhs_tau0 = "0.003",
  rhs_slab_s2 = "1.0"
))

selected_ids <- c(
  "d1n300_refine_m100_a0p92_r0p97_w0p20_boundnone",
  "d1n300_refine_m100_a0p92_r0p95_w0p15_boundnone",
  "d1n400_ladder_m120_a0p92_r0p90_w0p10_boundnone",
  "d1n500_ladder_m100_a0p92_r0p93_w0p10_boundnone",
  "d1n700_ladder_m120_a0p92_r0p93_w0p10_boundnone",
  "d1n1000_ladder_m120_a0p92_r0p93_w0p15_boundnone",
  "d2n250x250_ladder_m120_a0p92_r0p90_w0p025_boundnone",
  "d2n400x300_ladder_m120_a0p92_r0p93_w0p050_boundnone"
)

pilot_roles <- c(
  d1n300_refine_m100_a0p92_r0p97_w0p20_boundnone = "current_control",
  d1n300_refine_m100_a0p92_r0p95_w0p15_boundnone = "d1_n300_lower_rho_scale",
  d1n400_ladder_m120_a0p92_r0p90_w0p10_boundnone = "d1_n400_capacity",
  d1n500_ladder_m100_a0p92_r0p93_w0p10_boundnone = "d1_n500_capacity",
  d1n700_ladder_m120_a0p92_r0p93_w0p10_boundnone = "d1_n700_capacity",
  d1n1000_ladder_m120_a0p92_r0p93_w0p15_boundnone = "d1_n1000_capacity_edge",
  d2n250x250_ladder_m120_a0p92_r0p90_w0p025_boundnone = "d2_balanced_250x250",
  d2n400x300_ladder_m120_a0p92_r0p93_w0p050_boundnone = "d2_uneven_400x300"
)

pilot_priority <- seq_along(selected_ids)
names(pilot_priority) <- selected_ids

read_optional <- function(path) {
  path <- app_resolve_path(path, must_work = FALSE)
  if (file.exists(path)) app_read_csv(path) else data.frame()
}

grid_path <- app_resolve_path(args$shortlist_grid, must_work = TRUE)
grid <- app_read_csv(grid_path)
metrics <- read_optional(args$shortlist_metrics)

if (nrow(metrics)) {
  candidates <- metrics
} else {
  candidates <- grid
}

if (!"spec_id" %in% names(candidates)) {
  stop("Candidate source is missing spec_id.", call. = FALSE)
}

missing_ids <- setdiff(selected_ids, candidates$spec_id)
if (length(missing_ids)) {
  fallback <- grid[grid$spec_id %in% missing_ids, , drop = FALSE]
  candidates <- app_bind_rows_fill(list(candidates, fallback))
  missing_ids <- setdiff(selected_ids, candidates$spec_id)
}
if (length(missing_ids)) {
  stop(sprintf("Selected candidate ids are missing: %s.", paste(missing_ids, collapse = ", ")), call. = FALSE)
}

first_present <- function(row, names, default = NA) {
  for (nm in names) {
    if (nm %in% names(row)) {
      val <- row[[nm]][[1L]]
      if (!is.na(val) && nzchar(as.character(val))) return(val)
    }
  }
  default
}

as_num_field <- function(row, names, default = NA_real_) {
  out <- suppressWarnings(as.numeric(first_present(row, names, default)))
  if (is.finite(out)) out else default
}

as_int_field <- function(row, names, default = NA_integer_) {
  out <- suppressWarnings(as.integer(as_num_field(row, names, default)))
  if (is.finite(out)) out else default
}

parse_int_vector <- function(x) {
  x <- as.character(x %||% "")
  if (!nzchar(x)) return(integer(0))
  out <- suppressWarnings(as.integer(strsplit(gsub("[[:space:]]+", "", x), "[;,|]")[[1L]]))
  out[is.finite(out)]
}

fmt_num <- function(x) {
  if (is.na(x) || !is.finite(as.numeric(x))) return("")
  format(as.numeric(x), digits = 10, scientific = FALSE, trim = TRUE)
}

short_slug <- function(spec_id) {
  x <- spec_id
  x <- sub("_boundnone$", "", x)
  x <- sub("_refine", "", x)
  x <- sub("_ladder", "", x)
  x <- gsub("a0p", "a", x, fixed = TRUE)
  x <- gsub("r0p", "r", x, fixed = TRUE)
  x <- gsub("w0p", "w", x, fixed = TRUE)
  x <- gsub("__+", "_", x)
  x
}

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
  if (!is.null((cfg$feature_contract$readout %||% list())$input_block)) {
    cfg$feature_contract$readout$input_block$output_lags <- set_lag_range(1L, m)
    readout_covariates <- names(cfg$feature_contract$readout$input_block$covariates %||% list())
    for (v in readout_covariates) {
      cfg$feature_contract$readout$input_block$covariates[[v]] <- set_lag_range(0L, m)
    }
  }
  if (!is.null((cfg$covariates %||% list())$readout)) {
    cfg$covariates$readout$lags <- set_lag_range(0L, m)
  }
  cfg
}

template_path <- app_resolve_path(args$template_config, must_work = TRUE)
template <- app_read_yaml(template_path)

max_iter <- as.integer(args$max_iter)
n_draws <- as.integer(args$n_draws)
rhs_tau0 <- as.numeric(args$rhs_tau0)
rhs_slab_s2 <- as.numeric(args$rhs_slab_s2)

if (!is.finite(max_iter) || max_iter <= 0L) stop("max_iter must be positive.", call. = FALSE)
if (!is.finite(n_draws) || n_draws <= 0L) stop("n_draws must be positive.", call. = FALSE)
if (!is.finite(rhs_tau0) || rhs_tau0 <= 0) stop("rhs_tau0 must be positive.", call. = FALSE)
if (!is.finite(rhs_slab_s2) || rhs_slab_s2 <= 0) stop("rhs_slab_s2 must be positive.", call. = FALSE)

candidate_rows <- candidates[match(selected_ids, candidates$spec_id), , drop = FALSE]
out_rows <- vector("list", length(selected_ids))
grid_rows <- vector("list", length(selected_ids))

for (i in seq_along(selected_ids)) {
  row <- candidate_rows[i, , drop = FALSE]
  spec_id <- as.character(row$spec_id[[1L]])
  slug <- short_slug(spec_id)
  app_name <- sprintf("%s_%s_tau3em3_main1000", args$config_prefix, slug)
  config_path <- file.path("application/config", sprintf("%s_%s_tau3em3_main1000.yaml", args$config_prefix, slug))
  model_grid_path <- file.path("application/config", sprintf("%s_%s_tau3em3_main1000.csv", args$model_grid_prefix, slug))

  D <- as_int_field(row, "D")
  n_vec <- parse_int_vector(first_present(row, c("n_vector", "n")))
  if (length(n_vec) == 1L && D > 1L) n_vec <- rep(n_vec, D)
  if (length(n_vec) != D) {
    stop(sprintf("%s has D=%d but n_vector=%s.", spec_id, D, paste(n_vec, collapse = ";")), call. = FALSE)
  }
  n_tilde <- parse_int_vector(first_present(row, "n_tilde", ""))
  if (D <= 1L) n_tilde <- integer(0)
  if (D > 1L && length(n_tilde) != D - 1L) {
    n_tilde <- n_vec[-D]
  }
  m <- as_int_field(row, "m")
  washout <- as_int_field(row, "washout", 500L)
  alpha <- as_num_field(row, "alpha")
  rho <- as_num_field(row, "rho")
  pi_w <- as_num_field(row, "pi_w")
  pi_in <- as_num_field(row, "pi_in")
  win_scale_global <- as_num_field(row, "win_scale_global")
  win_scale_bias <- as_num_field(row, "win_scale_bias")
  input_bound <- as.character(first_present(row, "input_bound", "none"))
  seed <- as_int_field(row, c("launch_seed", "seed"), 20260512L)

  cfg <- template
  cfg$application_name <- app_name
  cfg$description <- sprintf(
    paste(
      "Median-only Dec. 25, 2022 diverse screened reservoir-candidate launch",
      "for the latent-path ensemble-likelihood Q-DESN application model.",
      "Candidate %d/8 (%s) uses %s, m=%d, alpha=%.3f, rho=%.3f,",
      "pi_w=%.3f, pi_in=%.3f, win scales %.4f/%.4f, seed=%d, AL-VB,",
      "n_draws=%d, max_iter=%d, and independent RHS tau0=%.4g for both",
      "readout blocks. No application fit is launched by the preparation script."
    ),
    i,
    pilot_roles[[spec_id]],
    if (D == 1L) sprintf("D=1, n=%d", n_vec[[1L]]) else sprintf("D=%d, n=(%s), n_tilde=(%s)", D, paste(n_vec, collapse = ","), paste(n_tilde, collapse = ",")),
    m,
    alpha,
    rho,
    pi_w,
    pi_in,
    win_scale_global,
    win_scale_bias,
    seed,
    n_draws,
    max_iter,
    rhs_tau0
  )
  cfg$paths$model_grid <- model_grid_path
  cfg$paths$cache <- file.path("application/cache", app_name)
  cfg$reservoir$D <- D
  cfg$reservoir[["n"]] <- n_vec
  cfg$reservoir$n_tilde <- n_tilde
  cfg$reservoir$m <- m
  cfg <- apply_memory_contract(cfg, m)
  cfg$reservoir$washout <- washout
  cfg$reservoir$alpha <- rep(alpha, D)
  cfg$reservoir$rho <- rep(rho, D)
  cfg$reservoir$pi_w <- rep(pi_w, D)
  cfg$reservoir$pi_in <- rep(pi_in, D)
  cfg$reservoir$win_scale_global <- win_scale_global
  cfg$reservoir$win_scale_bias <- win_scale_bias
  cfg$reservoir$input_bound <- input_bound
  cfg$reservoir$seed <- seed
  cfg$inference$vb_ld$max_iter <- max_iter
  cfg$inference$vb_ld$max_iter_hard_cap <- max_iter
  cfg$inference$vb_ld$n_draws <- n_draws
  cfg$inference$vb_ld$rhs_tau0 <- rhs_tau0
  cfg$inference$vb_ld$rhs_alpha_tau0 <- rhs_tau0
  cfg$inference$vb_ld$rhs_slab_s2 <- rhs_slab_s2
  cfg$inference$vb_ld$rhs_alpha_slab_s2 <- rhs_slab_s2
  cfg$inference$mcmc$rhs_tau0 <- rhs_tau0
  cfg$inference$mcmc$rhs_alpha_tau0 <- rhs_tau0
  cfg$inference$mcmc$rhs_slab_s2 <- rhs_slab_s2
  cfg$inference$mcmc$rhs_alpha_slab_s2 <- rhs_slab_s2
  cfg$execution$inference_support$note <- sprintf(
    "Diverse reservoir-candidate %d/8 (%s). Required before launch: exact-seed reservoir screen with diagnostic_target=both and sampler-free design check.",
    i,
    spec_id
  )
  cfg$execution$prelaunch$enabled <- FALSE
  cfg$execution$prelaunch$purpose <- "diverse_reservoir_candidate_preparation_only"
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- sprintf(
    "Diverse candidate %d/8 %s; do not launch before reservoir validity, design preflight, and explicit confirmation.",
    i,
    spec_id
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
    reservoir_seed = c(NA, seed),
    likelihood_family = c("none", "al"),
    required = c("true", "true"),
    enabled = c("true", "true"),
    config_hash = c("TO_BE_COMPUTED", "TO_BE_COMPUTED"),
    notes = c(
      sprintf("Raw GloFAS ensemble median baseline for diverse candidate %d/8 (%s).", i, spec_id),
      sprintf(
        paste(
          "Median-only diverse screened latent-path two-block ensemble-likelihood",
          "Q-DESN candidate %d/8 (%s) with AL likelihood, VB max_iter=%d,",
          "independent beta/alpha RHS tau0=%.4g, and multiseed reservoir-screening evidence."
        ),
        i,
        spec_id,
        max_iter,
        rhs_tau0
      )
    ),
    stringsAsFactors = FALSE
  )

  app_write_yaml(cfg, app_path(config_path))
  app_write_csv(model_grid, app_path(model_grid_path))

  total_units <- sum(n_vec)
  out_rows[[i]] <- data.frame(
    pilot_rank = i,
    spec_id = spec_id,
    pilot_role = pilot_roles[[spec_id]],
    config_path = config_path,
    model_grid_path = model_grid_path,
    run_id_template = sprintf("diverse8_%02d_%s_YYYYMMDD_HHMMSS", i, slug),
    D = D,
    n_vector = paste(n_vec, collapse = ";"),
    total_units = total_units,
    n_tilde = paste(n_tilde, collapse = ";"),
    n_tilde_rule = if (D <= 1L) "none for D=1" else "identity/no-reduction pass-through from each previous layer",
    m = m,
    washout = washout,
    alpha = alpha,
    rho = rho,
    pi_w = pi_w,
    pi_in = pi_in,
    win_scale_global = win_scale_global,
    win_scale_bias = win_scale_bias,
    input_bound = input_bound,
    launch_seed = seed,
    rhs_tau0 = rhs_tau0,
    rhs_alpha_tau0 = rhs_tau0,
    rhs_slab_s2 = rhs_slab_s2,
    vb_max_iter = max_iter,
    vb_n_draws = n_draws,
    multiseed_decision = as.character(first_present(row, "decision", "")),
    multiseed_triage_class = as.character(first_present(row, "triage_class", "")),
    multiseed_fail_rate = fmt_num(first_present(row, "fail_rate", NA_real_)),
    multiseed_rejected_seeds = as.character(first_present(row, "rejected_seeds", "")),
    max_saturation_fraction = fmt_num(first_present(row, c("max_saturation_fraction", "max_saturation_fraction.y", "max_saturation_fraction.x"), NA_real_)),
    min_relative_effective_rank_entropy = fmt_num(first_present(row, c("min_relative_effective_rank_entropy", "min_relative_effective_rank_entropy.y", "min_relative_effective_rank_entropy.x"), NA_real_)),
    max_condition_cov = fmt_num(first_present(row, c("max_condition_cov", "max_condition_cov.y", "max_condition_cov.x"), NA_real_)),
    max_abs_corr = fmt_num(first_present(row, c("max_abs_corr", "max_abs_corr.y", "max_abs_corr.x"), NA_real_)),
    source_shortlist_metrics = if (nrow(metrics)) app_prefer_repo_relative_path(app_resolve_path(args$shortlist_metrics, must_work = TRUE)) else "",
    source_shortlist_grid = app_prefer_repo_relative_path(grid_path),
    launch_status = "prepared_not_launched",
    stringsAsFactors = FALSE
  )

  grid_rows[[i]] <- data.frame(
    spec_id = spec_id,
    family = as.character(first_present(row, "family", "")),
    base_case = as.character(first_present(row, "base_case", "")),
    D = D,
    n_vector = paste(n_vec, collapse = ";"),
    n_tilde = paste(n_tilde, collapse = ";"),
    m = m,
    washout = washout,
    alpha = alpha,
    rho = rho,
    pi_w = pi_w,
    pi_in = pi_in,
    win_scale_global = win_scale_global,
    win_scale_bias = win_scale_bias,
    input_bound = input_bound,
    launch_seed = seed,
    rationale = sprintf("Diverse pilot batch rank %d: %s.", i, pilot_roles[[spec_id]]),
    config_path = config_path,
    model_grid_path = model_grid_path,
    screening_only = TRUE,
    stringsAsFactors = FALSE
  )
}

batch <- app_bind_rows_fill(out_rows)
screen_grid <- app_bind_rows_fill(grid_rows)

app_write_csv(batch, app_path(args$output_batch))
app_write_csv(screen_grid, app_path(args$output_reservoir_grid))

cat(sprintf("wrote %s\n", args$output_batch))
cat(sprintf("wrote %s\n", args$output_reservoir_grid))
cat(sprintf("candidate_configs=%d\n", nrow(batch)))
