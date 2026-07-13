#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_exqdesn_trace_tools.R"))

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase128_laplace_bridge_gamma_mixing_pilot_20260712",
  phase122_dir = "application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711",
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  case_id = "laplace_bridge__joint_exqdesn_rhs_vb",
  width_multipliers = "1,2,4,8",
  n_chains = "8",
  mcmc_n_iter = "6000",
  mcmc_burn = "1500",
  mcmc_thin = "1",
  mcmc_seed_offset = "5100",
  chain_seed_stride = "100",
  variant_seed_stride = "10000",
  sigma_upper_multiplier = "50",
  distance_pass = "5",
  chain_pass = "5",
  n_cores = "16",
  gamma_init_mode = "vb_jittered",
  gamma_jitter_fraction = "0.10",
  vb_max_iter_override = "",
  adaptive_vb_max_iter_grid_override = "",
  save_rdata = "false"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(trimws(x))) return(character())
  vals <- trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
  vals[nzchar(vals)]
}

parse_integer <- function(x, allow_empty = FALSE) {
  x <- as.character(x)[[1L]]
  if (allow_empty && !nzchar(trimws(x))) return(NULL)
  out <- as.integer(suppressWarnings(as.numeric(x)))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", x), call. = FALSE)
  out
}

parse_number <- function(x, allow_empty = FALSE) {
  x <- as.character(x)[[1L]]
  if (allow_empty && !nzchar(trimws(x))) return(NULL)
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) stop(sprintf("Expected numeric value, got '%s'.", x), call. = FALSE)
  out
}

parse_bool <- function(x) {
  tolower(as.character(x)[[1L]]) %in% c("true", "t", "yes", "y", "1")
}

resolve_path <- function(path, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

run_one_chain <- function(job) {
  variant <- width_registry[width_registry$variant_id == job$variant_id[[1L]], , drop = FALSE]
  if (nrow(variant) != 1L) stop("Could not find width variant.", call. = FALSE)
  chain_id <- as.integer(job$chain_id[[1L]])
  chain_seed <- as.integer(job$chain_seed[[1L]])
  init <- app_joint_exqdesn_gamma_chain_init(
    vb_fit = retained$vb_fit,
    tau = fixture$tau,
    chain_id = chain_id,
    n_chains = mcmc_controls$n_chains,
    mode = gamma_init_mode,
    jitter_fraction = gamma_jitter_fraction
  )
  chain_start <- proc.time()[["elapsed"]]
  fit <- app_joint_qvp_fit_exal_mcmc_tiny(
    y = fixture$y,
    Z = fixture$Z,
    tau = fixture$tau,
    n_iter = mcmc_controls$mcmc_n_iter,
    burn = mcmc_controls$mcmc_burn,
    thin = mcmc_controls$mcmc_thin,
    seed = chain_seed,
    kappa = 1,
    tau0 = controls$tau0,
    zeta2 = controls$zeta2,
    gamma_init = app_joint_qdesn_gamma_init_for_policy(fixture$tau, controls),
    alpha_min_spacing = controls$alpha_min_spacing,
    max_dense_dim = controls$max_dense_dim,
    sigma_bounds = sigma_bounds,
    gamma_slice_width = width_default * as.numeric(variant$width_multiplier[[1L]]),
    init = init
  )
  chain_elapsed <- proc.time()[["elapsed"]] - chain_start
  list(
    variant_id = variant$variant_id[[1L]],
    experiment_id = variant$experiment_id[[1L]],
    width_multiplier = as.numeric(variant$width_multiplier[[1L]]),
    gamma_slice_width = paste(format(width_default * as.numeric(variant$width_multiplier[[1L]]), digits = 8, trim = TRUE), collapse = ","),
    chain_id = chain_id,
    chain_seed = chain_seed,
    gamma_init_mode = gamma_init_mode,
    gamma_init = paste(format(as.numeric(init$gamma_mean %||% init$gamma), digits = 8, trim = TRUE), collapse = ","),
    fit = fit,
    runtime = data.frame(
      case_meta,
      experiment_id = variant$experiment_id[[1L]],
      variant_id = variant$variant_id[[1L]],
      width_multiplier = as.numeric(variant$width_multiplier[[1L]]),
      runtime_component = "mcmc_chain",
      chain_id = chain_id,
      chain_seed = chain_seed,
      elapsed_seconds = chain_elapsed,
      sec_per_iter = chain_elapsed / max(1L, mcmc_controls$mcmc_n_iter),
      stringsAsFactors = FALSE
    )
  )
}

out_dir <- resolve_path(arg_value("output_dir"), must_work = FALSE)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "figures"))
if (parse_bool(arg_value("save_rdata"))) app_ensure_dir(file.path(out_dir, "raw_objects"))

phase122_dir <- resolve_path(arg_value("phase122_dir"), must_work = TRUE)
fixture_dir <- resolve_path(arg_value("fixture_dir"), must_work = TRUE)
phase122_manifest <- app_joint_qdesn_phase108_manifest_verify(phase122_dir, "phase122_mcmc_case_confirmation")
artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
controls122 <- app_read_csv(file.path(phase122_dir, "case_winner_controls.csv"))
case_id <- as.character(arg_value("case_id"))[[1L]]
selected <- controls122[controls122$case_id == case_id, , drop = FALSE]
if (nrow(selected) != 1L) stop(sprintf("Expected one Phase122 row for case_id '%s'.", case_id), call. = FALSE)

scenario_id <- selected$scenario_ids[[1L]]
fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
spec <- app_joint_qdesn_phase122_select_spec(selected$model_ids[[1L]])
if (!identical(spec$model_id[[1L]], "joint_exqdesn_rhs_vb") ||
    !identical(spec$fit_structure[[1L]], "joint") ||
    !identical(spec$likelihood[[1L]], "exal")) {
  stop(sprintf("Case '%s' is not the Joint exQDESN exAL-RHS case.", case_id), call. = FALSE)
}

controls <- app_joint_qdesn_phase122_controls_from_row(selected, n_cores = 1L)
vb_override <- parse_integer(arg_value("vb_max_iter_override"), allow_empty = TRUE)
vb_grid_override <- parse_csv(arg_value("adaptive_vb_max_iter_grid_override"))
if (!is.null(vb_override)) controls$vb_max_iter <- vb_override
if (length(vb_grid_override)) controls$adaptive_vb_max_iter_grid <- as.integer(vb_grid_override)

mcmc_controls <- app_joint_qdesn_mcmc_readiness_controls(
  n_chains = parse_integer(arg_value("n_chains")),
  mcmc_n_iter = parse_integer(arg_value("mcmc_n_iter")),
  mcmc_burn = parse_integer(arg_value("mcmc_burn")),
  mcmc_thin = parse_integer(arg_value("mcmc_thin")),
  mcmc_seed_offset = parse_integer(arg_value("mcmc_seed_offset")),
  chain_seed_stride = parse_integer(arg_value("chain_seed_stride")),
  sigma_upper_multiplier = parse_number(arg_value("sigma_upper_multiplier")),
  distance_pass = parse_number(arg_value("distance_pass")),
  chain_pass = parse_number(arg_value("chain_pass")),
  n_cores = parse_integer(arg_value("n_cores"))
)
variant_seed_stride <- parse_integer(arg_value("variant_seed_stride"))
width_multipliers <- as.numeric(parse_csv(arg_value("width_multipliers")))
if (!length(width_multipliers) || any(!is.finite(width_multipliers)) || any(width_multipliers <= 0)) {
  stop("width_multipliers must be positive finite numbers.", call. = FALSE)
}
gamma_init_mode <- as.character(arg_value("gamma_init_mode"))[[1L]]
gamma_jitter_fraction <- parse_number(arg_value("gamma_jitter_fraction"))
save_rdata <- parse_bool(arg_value("save_rdata"))

case_meta <- app_joint_qdesn_phase122_meta(
  fixture,
  spec,
  selected,
  "MCMC",
  app_joint_qdesn_phase122_mcmc_model_id(spec$model_id[[1L]])
)
case_meta$diagnostic_model_label <- "Joint exQDESN exAL-RHS"
case_meta$phase128_case_role <- "single_case_gamma_mixing_pilot"

vb_start <- proc.time()[["elapsed"]]
retained <- app_joint_exqdesn_fit_with_retained_init(fixture, controls)
vb_elapsed <- proc.time()[["elapsed"]] - vb_start
sigma_upper <- max(1, mcmc_controls$sigma_upper_multiplier * max(retained$vb_fit$sigma_mean, na.rm = TRUE))
sigma_bounds <- c(1.0e-8, sigma_upper)
support <- app_joint_qvp_exal_support(fixture$tau)
width_default <- (as.numeric(support$upper) - as.numeric(support$lower)) / 20
width_registry <- data.frame(
  experiment_id = paste0("gamma_width_x", gsub("[^0-9]+", "p", format(width_multipliers, trim = TRUE, scientific = FALSE))),
  variant_id = paste0("gamma_width_multiplier_", gsub("[^0-9]+", "p", format(width_multipliers, trim = TRUE, scientific = FALSE))),
  width_multiplier = width_multipliers,
  default_width_by_tau = paste(format(width_default, digits = 8, trim = TRUE), collapse = ","),
  gamma_slice_width_by_tau = vapply(width_multipliers, function(x) paste(format(width_default * x, digits = 8, trim = TRUE), collapse = ","), character(1L)),
  stringsAsFactors = FALSE
)

base_seed <- as.integer(fixture$scenario_meta$seed[[1L]])
case_offset <- sum(utf8ToInt(case_id)) %% 100000L
jobs <- app_joint_qdesn_bind_rows(lapply(seq_len(nrow(width_registry)), function(vv) {
  app_joint_qdesn_bind_rows(lapply(seq_len(mcmc_controls$n_chains), function(chain_id) {
    data.frame(
      job_id = sprintf("%s_chain_%02d", width_registry$variant_id[[vv]], chain_id),
      experiment_id = width_registry$experiment_id[[vv]],
      variant_id = width_registry$variant_id[[vv]],
      width_multiplier = width_registry$width_multiplier[[vv]],
      chain_id = chain_id,
      chain_seed = base_seed + mcmc_controls$mcmc_seed_offset + case_offset +
        (vv - 1L) * variant_seed_stride + (chain_id - 1L) * mcmc_controls$chain_seed_stride,
      stringsAsFactors = FALSE
    )
  }))
}))

job_by_id <- split(jobs, jobs$job_id)
mcmc_start <- proc.time()[["elapsed"]]
chain_results <- app_joint_qdesn_parallel_lapply(
  names(job_by_id),
  function(jid) run_one_chain(job_by_id[[jid]]),
  mcmc_controls$n_cores
)
mcmc_elapsed <- proc.time()[["elapsed"]] - mcmc_start
worker_failures <- app_joint_qdesn_worker_failure_rows(chain_results, "phase128_gamma_mixing_chain")
successful <- app_joint_qdesn_successful_worker_results(chain_results, "phase128_gamma_mixing_chain")

chain_initialization <- app_joint_qdesn_bind_rows(lapply(successful, function(x) {
  data.frame(
    case_meta,
    experiment_id = x$experiment_id,
    variant_id = x$variant_id,
    width_multiplier = x$width_multiplier,
    chain_id = x$chain_id,
    chain_seed = x$chain_seed,
    gamma_init_mode = x$gamma_init_mode,
    gamma_init = x$gamma_init,
    stringsAsFactors = FALSE
  )
}))
runtime <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "runtime"))

variant_results <- lapply(split(successful, vapply(successful, `[[`, character(1L), "variant_id")), function(results) {
  first <- results[[1L]]
  variant_meta <- cbind(
    case_meta,
    data.frame(
      experiment_id = first$experiment_id,
      variant_id = first$variant_id,
      width_multiplier = first$width_multiplier,
      stringsAsFactors = FALSE
    )
  )
  fits <- lapply(results[order(vapply(results, `[[`, integer(1L), "chain_id"))], `[[`, "fit")
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau)
  trace <- app_joint_exqdesn_mcmc_chain_trace_rows(
    fits,
    fixture$tau,
    variant_meta,
    mcmc_controls$mcmc_n_iter,
    mcmc_controls$mcmc_burn,
    mcmc_controls$mcmc_thin
  )
  rhat <- app_joint_exqdesn_mcmc_rhat_ess_rows(fits, fixture$tau, variant_meta)
  draw <- app_joint_qdesn_bind_rows(lapply(seq_along(fits), function(chain_id) {
    cbind(
      variant_meta,
      data.frame(chain_id = chain_id, chain_seed = fits[[chain_id]]$seed %||% NA_integer_, stringsAsFactors = FALSE),
      app_joint_qdesn_phase122_draw_summary(fits[[chain_id]], case_id, "phase128_gamma_mixing_pilot", fixture$scenario_id, sigma_bounds = sigma_bounds),
      stringsAsFactors = FALSE
    )
  }))
  distance <- app_joint_qvp_vb_mcmc_distance_summary(
    retained$vb_fit,
    pooled,
    case_id,
    "phase128_gamma_mixing_pilot",
    fixture$scenario_id,
    length(fixture$y),
    ncol(fixture$Z),
    length(fixture$tau)
  )
  if (!is.null(retained$vb_fit$gamma_mean) && !is.null(pooled$gamma_mean)) {
    gamma_l2 <- app_joint_qvp_l2_distance(retained$vb_fit$gamma_mean, pooled$gamma_mean)
    distance$gamma_l2_to_mcmc <- gamma_l2
    distance$gamma_normalized_distance <- gamma_l2 / (sqrt(length(fixture$tau)) * (1 + sqrt(mean(retained$vb_fit$gamma_mean^2))))
    distance$max_normalized_distance <- pmax(distance$max_normalized_distance, distance$gamma_normalized_distance, na.rm = TRUE)
  } else {
    distance$gamma_l2_to_mcmc <- NA_real_
    distance$gamma_normalized_distance <- NA_real_
  }
  chain_distance <- app_joint_qvp_chain_to_pooled_summary(
    fits,
    pooled,
    fixture$Z,
    case_id,
    "phase128_gamma_mixing_pilot",
    fixture$scenario_id,
    length(fixture$y),
    ncol(fixture$Z),
    length(fixture$tau)
  )
  list(
    variant_meta = variant_meta,
    fits = fits,
    pooled = pooled,
    trace = trace,
    trace_summary = app_joint_exqdesn_mcmc_trace_summary_rows(trace),
    rhat = rhat,
    gap = app_joint_exqdesn_chain_mean_gap_rows(trace),
    autocorrelation = app_joint_exqdesn_autocorrelation_rows(trace),
    draw = draw,
    distance = cbind(variant_meta, distance, stringsAsFactors = FALSE),
    chain_distance = cbind(variant_meta, chain_distance, stringsAsFactors = FALSE)
  )
})

mcmc_trace <- app_joint_qdesn_bind_rows(lapply(variant_results, `[[`, "trace"))
mcmc_trace_summary <- app_joint_qdesn_bind_rows(lapply(variant_results, `[[`, "trace_summary"))
mcmc_rhat_ess <- app_joint_qdesn_bind_rows(lapply(variant_results, `[[`, "rhat"))
chain_mean_gap <- app_joint_qdesn_bind_rows(lapply(variant_results, `[[`, "gap"))
autocorrelation <- app_joint_qdesn_bind_rows(lapply(variant_results, `[[`, "autocorrelation"))
mcmc_draw_summary <- app_joint_qdesn_bind_rows(lapply(variant_results, `[[`, "draw"))
vb_mcmc_distance <- app_joint_qdesn_bind_rows(lapply(variant_results, `[[`, "distance"))
chain_to_pooled_distance <- app_joint_qdesn_bind_rows(lapply(variant_results, `[[`, "chain_distance"))

vb_trace <- app_joint_exqdesn_vb_trace_rows(retained$vb_fit, fixture$tau, case_meta)
al_sigma <- app_joint_exqdesn_matrix_trace_long(retained$al_init$sigma_trace, fixture$tau, case_meta, "al_init_sigma")
vb_objective <- app_joint_qdesn_bind_rows(list(
  app_joint_exqdesn_vb_objective_rows(retained$al_init, case_meta, "al_init"),
  app_joint_exqdesn_vb_objective_rows(retained$vb_fit, case_meta, "exal_vb_ld")
))
vb_monitor <- app_joint_qdesn_bind_rows(list(
  app_joint_exqdesn_vb_monitor_rows(retained$al_init, case_meta, "al_init"),
  app_joint_exqdesn_vb_monitor_rows(retained$vb_fit, case_meta, "exal_vb_ld")
))
rhs_prior <- app_joint_exqdesn_rhs_summary_rows(retained$vb_fit, case_meta)
attempts <- cbind(case_meta, retained$attempts, stringsAsFactors = FALSE)

variant_assessment <- app_joint_qdesn_bind_rows(lapply(split(width_registry, width_registry$variant_id), function(vrow) {
  rh <- mcmc_rhat_ess[mcmc_rhat_ess$variant_id == vrow$variant_id[[1L]], , drop = FALSE]
  gap <- chain_mean_gap[chain_mean_gap$variant_id == vrow$variant_id[[1L]], , drop = FALSE]
  ac <- autocorrelation[autocorrelation$variant_id == vrow$variant_id[[1L]] & autocorrelation$lag == 1L, , drop = FALSE]
  draw <- mcmc_draw_summary[mcmc_draw_summary$variant_id == vrow$variant_id[[1L]], , drop = FALSE]
  finite_rhat <- rh$rhat[is.finite(rh$rhat)]
  finite_ess <- rh$rough_ess_total[is.finite(rh$rough_ess_total)]
  gamma_rhat <- rh$rhat[rh$parameter == "gamma" & is.finite(rh$rhat)]
  gamma_ess <- rh$rough_ess_total[rh$parameter == "gamma" & is.finite(rh$rough_ess_total)]
  gamma_gap <- gap$chain_mean_gap[gap$parameter == "gamma" & is.finite(gap$chain_mean_gap)]
  gamma_ac1 <- ac$autocorrelation[ac$parameter == "gamma" & is.finite(ac$autocorrelation)]
  sigma_upper_hit <- draw$upper_bound_hit_fraction[draw$block == "sigma" & is.finite(draw$upper_bound_hit_fraction)]
  hard_fail <- nrow(worker_failures) > 0L ||
    !nrow(rh) ||
    !all(is.finite(mcmc_trace$gamma[mcmc_trace$variant_id == vrow$variant_id[[1L]]]), na.rm = TRUE) ||
    !all(is.finite(mcmc_trace$sigma[mcmc_trace$variant_id == vrow$variant_id[[1L]]]), na.rm = TRUE)
  max_rhat <- if (length(finite_rhat)) max(finite_rhat) else NA_real_
  min_ess <- if (length(finite_ess)) min(finite_ess) else NA_real_
  max_gamma_rhat <- if (length(gamma_rhat)) max(gamma_rhat) else NA_real_
  min_gamma_ess <- if (length(gamma_ess)) min(gamma_ess) else NA_real_
  max_gamma_gap <- if (length(gamma_gap)) max(gamma_gap) else NA_real_
  max_gamma_ac1 <- if (length(gamma_ac1)) max(gamma_ac1) else NA_real_
  max_sigma_upper_hit <- if (length(sigma_upper_hit)) max(sigma_upper_hit) else NA_real_
  review <- !hard_fail && (
    isTRUE(!retained$vb_fit$converged) ||
      (is.finite(max_rhat) && max_rhat > 1.2) ||
      (is.finite(min_ess) && min_ess < 100) ||
      (is.finite(max_gamma_ac1) && max_gamma_ac1 > 0.98) ||
      (is.finite(max_sigma_upper_hit) && max_sigma_upper_hit > 0)
  )
  cbind(case_meta, data.frame(
    experiment_id = vrow$experiment_id[[1L]],
    variant_id = vrow$variant_id[[1L]],
    width_multiplier = as.numeric(vrow$width_multiplier[[1L]]),
    variant_gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    max_rhat = max_rhat,
    min_rough_ess_total = min_ess,
    max_gamma_rhat = max_gamma_rhat,
    min_gamma_rough_ess_total = min_gamma_ess,
    max_gamma_chain_mean_gap = max_gamma_gap,
    max_gamma_lag1_autocorrelation = max_gamma_ac1,
    max_sigma_upper_bound_hit_fraction = max_sigma_upper_hit,
    status_reason = paste(c(
      if (hard_fail) "worker failure or nonfinite trace",
      if (!hard_fail && isTRUE(!retained$vb_fit$converged)) "VB-LD reached max iterations",
      if (!hard_fail && is.finite(max_rhat) && max_rhat > 1.2) "MCMC Rhat exceeds diagnostic review threshold",
      if (!hard_fail && is.finite(min_ess) && min_ess < 100) "rough ESS below diagnostic review threshold",
      if (!hard_fail && is.finite(max_gamma_ac1) && max_gamma_ac1 > 0.98) "gamma lag-1 autocorrelation remains high",
      if (!hard_fail && is.finite(max_sigma_upper_hit) && max_sigma_upper_hit > 0) "sigma upper bound hit"
    ), collapse = "; "),
    stringsAsFactors = FALSE
  ))
}))

variant_ranking <- variant_assessment[order(
  variant_assessment$variant_gate_status != "pass",
  variant_assessment$max_gamma_rhat,
  -variant_assessment$min_gamma_rough_ess_total,
  variant_assessment$max_gamma_lag1_autocorrelation
), , drop = FALSE]
variant_ranking$rank <- seq_len(nrow(variant_ranking))

figure_paths <- character()
for (variant_id in unique(mcmc_trace$variant_id)) {
  pth <- file.path(out_dir, "figures", paste0("trace_diagnostics_", app_joint_exqdesn_trace_safe_id(variant_id), ".pdf"))
  app_joint_exqdesn_plot_variant_diagnostics(variant_id, mcmc_trace, vb_trace, pth)
  figure_paths <- c(figure_paths, pth)
}
dashboard_path <- file.path(out_dir, "figures", "00_phase128_gamma_mixing_dashboard.pdf")
app_joint_exqdesn_plot_phase128_dashboard(variant_assessment, mcmc_rhat_ess, chain_mean_gap, dashboard_path)
figure_paths <- c(dashboard_path, figure_paths)

run_config <- data.frame(
  run_id = "joint_qdesn_phase128_laplace_bridge_gamma_mixing_pilot",
  out_dir = out_dir,
  phase122_dir = phase122_dir,
  fixture_dir = artifacts$fixture_dir,
  case_id = case_id,
  scenario_id = scenario_id,
  source_candidate_id = selected$candidate_id[[1L]],
  model_scope = "single_case_joint_exqdesn_exal_rhs_gamma_mixing_pilot",
  width_multipliers = paste(width_multipliers, collapse = ","),
  n_width_variants = nrow(width_registry),
  n_chains = mcmc_controls$n_chains,
  mcmc_n_iter = mcmc_controls$mcmc_n_iter,
  mcmc_burn = mcmc_controls$mcmc_burn,
  mcmc_thin = mcmc_controls$mcmc_thin,
  mcmc_seed_offset = mcmc_controls$mcmc_seed_offset,
  chain_seed_stride = mcmc_controls$chain_seed_stride,
  variant_seed_stride = variant_seed_stride,
  gamma_init_mode = gamma_init_mode,
  gamma_jitter_fraction = gamma_jitter_fraction,
  raw_rdata_saved = save_rdata,
  n_cores = mcmc_controls$n_cores,
  vb_elapsed_seconds = vb_elapsed,
  mcmc_elapsed_seconds = mcmc_elapsed,
  total_elapsed_seconds = vb_elapsed + mcmc_elapsed,
  validation_contract = "single_case_sampler_tuning_no_article_table_mutation",
  scalar_predictive_density_claim = FALSE,
  stringsAsFactors = FALSE
)

readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint exQDESN exAL-RHS Phase128 Gamma-Mixing Pilot",
  "",
  "This artifact tests whether the poor gamma mixing observed in Phase127 is improved by a targeted sampler experiment on the worst single case.",
  "",
  sprintf("- Case: `%s`", case_id),
  sprintf("- Scenario: `%s`", scenario_id),
  sprintf("- Source Phase122 artifact: `%s`", phase122_dir),
  sprintf("- Fixture source: `%s`", artifacts$fixture_dir),
  sprintf("- Width multipliers: `%s`", paste(width_multipliers, collapse = ",")),
  sprintf("- Chains per width: `%s`", mcmc_controls$n_chains),
  sprintf("- MCMC iterations/burn/thin: `%s/%s/%s`", mcmc_controls$mcmc_n_iter, mcmc_controls$mcmc_burn, mcmc_controls$mcmc_thin),
  sprintf("- Gamma initialisation mode: `%s`", gamma_init_mode),
  sprintf("- Raw RData saved: `%s`", save_rdata),
  "",
  "The pilot preserves CSV trace diagnostics and figures only by default. It does not regenerate article tables and does not promote any model.",
  "Promotion requires a meaningful reduction in gamma Rhat, higher rough ESS, smaller chain mean gaps, and stable finite sigma/gamma traces.",
  "",
  "Variant gate counts:",
  paste(capture.output(print(table(variant_assessment$variant_gate_status))), collapse = "\n")
), readme_path, useBytes = TRUE)

paths <- c(
  run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
  phase122_source_manifest_verification = app_joint_qvp_write_csv(phase122_manifest, file.path(out_dir, "phase122_source_manifest_verification.csv")),
  fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
  selected_case_control = app_joint_qvp_write_csv(selected, file.path(out_dir, "selected_case_control.csv")),
  width_experiment_registry = app_joint_qvp_write_csv(width_registry, file.path(out_dir, "width_experiment_registry.csv")),
  chain_initialization = app_joint_qvp_write_csv(chain_initialization, file.path(out_dir, "chain_initialization.csv")),
  chain_worker_failures = app_joint_qvp_write_csv(worker_failures, file.path(out_dir, "chain_worker_failures.csv")),
  vb_adaptive_attempts = app_joint_qvp_write_csv(attempts, file.path(out_dir, "vb_adaptive_attempts.csv")),
  vb_gamma_sigma_lambda_trace = app_joint_qvp_write_csv(vb_trace, file.path(out_dir, "vb_gamma_sigma_lambda_trace.csv")),
  vb_al_init_sigma_trace = app_joint_qvp_write_csv(al_sigma, file.path(out_dir, "vb_al_init_sigma_trace.csv")),
  vb_objective_trace = app_joint_qvp_write_csv(vb_objective, file.path(out_dir, "vb_objective_trace.csv")),
  vb_monitor_terms = app_joint_qvp_write_csv(vb_monitor, file.path(out_dir, "vb_monitor_terms.csv")),
  rhs_prior_summary = app_joint_qvp_write_csv(rhs_prior, file.path(out_dir, "rhs_prior_summary.csv")),
  mcmc_gamma_sigma_lambda_trace = app_joint_qvp_write_csv(mcmc_trace, file.path(out_dir, "mcmc_gamma_sigma_lambda_trace.csv")),
  mcmc_trace_summary = app_joint_qvp_write_csv(mcmc_trace_summary, file.path(out_dir, "mcmc_trace_summary.csv")),
  mcmc_rhat_ess_summary = app_joint_qvp_write_csv(mcmc_rhat_ess, file.path(out_dir, "mcmc_rhat_ess_summary.csv")),
  chain_mean_gap_summary = app_joint_qvp_write_csv(chain_mean_gap, file.path(out_dir, "chain_mean_gap_summary.csv")),
  autocorrelation_summary = app_joint_qvp_write_csv(autocorrelation, file.path(out_dir, "autocorrelation_summary.csv")),
  mcmc_draw_summary = app_joint_qvp_write_csv(mcmc_draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
  vb_mcmc_distance_summary = app_joint_qvp_write_csv(vb_mcmc_distance, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
  chain_to_pooled_distance_summary = app_joint_qvp_write_csv(chain_to_pooled_distance, file.path(out_dir, "chain_to_pooled_distance_summary.csv")),
  runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
  variant_assessment = app_joint_qvp_write_csv(variant_assessment, file.path(out_dir, "variant_assessment.csv")),
  variant_ranking = app_joint_qvp_write_csv(variant_ranking, file.path(out_dir, "variant_ranking.csv")),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE)
)
names(figure_paths) <- paste0("figure_", seq_along(figure_paths))
paths <- c(paths, figure_paths)

if (isTRUE(save_rdata)) {
  raw_path <- file.path(out_dir, "raw_objects", "phase128_gamma_mixing_objects.RData")
  save(selected, fixture, controls, retained, variant_results, run_config, file = raw_path, compress = "xz")
  paths <- c(paths, raw_rdata = raw_path)
}

manifest_info <- app_joint_exqdesn_trace_manifest(paths, out_dir)

cat(sprintf("Phase128 gamma-mixing pilot written to %s\n", normalizePath(out_dir, mustWork = TRUE)))
cat("Run summary:\n")
print(run_config[, c("case_id", "n_width_variants", "n_chains", "mcmc_n_iter", "mcmc_burn", "mcmc_thin", "n_cores", "raw_rdata_saved")], row.names = FALSE)
cat("Variant gate counts:\n")
print(table(variant_assessment$variant_gate_status))
cat(sprintf("Chain worker failures: %d\n", nrow(worker_failures)))
cat(sprintf("Dashboard: %s\n", normalizePath(dashboard_path, mustWork = TRUE)))
cat(sprintf("Artifact manifest: %s\n", manifest_info$manifest_path))
