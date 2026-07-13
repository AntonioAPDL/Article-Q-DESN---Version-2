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
  output_dir = "application/cache/joint_qdesn_phase129_joint_exqdesn_gamma_width4_packet_20260713",
  phase122_dir = "application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711",
  phase124c_dir = "application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711",
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  scenario_ids = "",
  case_ids = "",
  case_limit = "",
  width_multiplier = "4",
  n_chains = "8",
  mcmc_n_iter = "8000",
  mcmc_burn = "2000",
  mcmc_thin = "1",
  mcmc_seed_offset = "6100",
  chain_seed_stride = "100",
  sigma_upper_multiplier = "50",
  distance_pass = "5",
  chain_pass = "5",
  n_cores = "24",
  vb_n_cores = "4",
  gamma_init_mode = "vb_jittered",
  gamma_jitter_fraction = "0.10",
  trace_write_stride = "50",
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

thin_trace_rows <- function(trace, stride) {
  stride <- as.integer(stride)
  if (!nrow(trace) || stride <= 1L) return(trace)
  max_draw <- max(trace$draw_index, na.rm = TRUE)
  keep <- trace$draw_index == 1L | trace$draw_index == max_draw | (trace$draw_index %% stride == 0L)
  trace[keep, , drop = FALSE]
}

plot_phase129_dashboard <- function(assessment, rhat, out_path) {
  grDevices::pdf(out_path, width = 12, height = 9)
  on.exit(grDevices::dev.off(), add = TRUE)
  par(mfrow = c(2, 2), mar = c(8, 4, 3, 1))
  if (nrow(assessment)) {
    labels <- assessment$scenario_id
    barplot(assessment$max_gamma_rhat, names.arg = labels, las = 2, main = "Max gamma Rhat by scenario", ylab = "Rhat")
    abline(h = 1.2, col = "red", lty = 2)
    barplot(assessment$min_gamma_rough_ess_total, names.arg = labels, las = 2, main = "Min gamma rough ESS by scenario", ylab = "ESS")
    abline(h = 100, col = "red", lty = 2)
    barplot(assessment$max_gamma_lag1_autocorrelation, names.arg = labels, las = 2, main = "Max gamma lag-1 autocorrelation", ylab = "ACF(1)")
    abline(h = 0.98, col = "red", lty = 2)
  } else {
    plot.new(); title("Assessment unavailable")
    plot.new(); title("Assessment unavailable")
    plot.new(); title("Assessment unavailable")
  }
  if (nrow(rhat)) {
    boxplot(rhat ~ interaction(parameter, scenario_id), data = rhat, las = 2,
            main = "Rhat by parameter and scenario", ylab = "Rhat")
  } else {
    plot.new(); title("Rhat unavailable")
  }
}

prepare_one_case <- function(row) {
  scenario_id <- row$scenario_ids[[1L]]
  case_id <- row$case_id[[1L]]
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  spec <- app_joint_qdesn_phase122_select_spec(row$model_ids[[1L]])
  if (!identical(spec$model_id[[1L]], "joint_exqdesn_rhs_vb") ||
      !identical(spec$fit_structure[[1L]], "joint") ||
      !identical(spec$likelihood[[1L]], "exal")) {
    stop(sprintf("Case '%s' is not the Joint exQDESN exAL-RHS case.", case_id), call. = FALSE)
  }
  controls <- app_joint_qdesn_phase122_controls_from_row(row, n_cores = 1L)
  if (!is.null(vb_max_iter_override)) controls$vb_max_iter <- vb_max_iter_override
  if (length(vb_grid_override)) controls$adaptive_vb_max_iter_grid <- as.integer(vb_grid_override)
  meta <- app_joint_qdesn_phase122_meta(
    fixture,
    spec,
    row,
    "MCMC",
    app_joint_qdesn_phase122_mcmc_model_id(spec$model_id[[1L]])
  )
  meta$diagnostic_model_label <- "Joint exQDESN exAL-RHS"
  meta$phase129_case_role <- "gamma_width4_packet"
  vb_start <- proc.time()[["elapsed"]]
  retained <- app_joint_exqdesn_fit_with_retained_init(fixture, controls)
  vb_elapsed <- proc.time()[["elapsed"]] - vb_start
  sigma_upper <- max(1, mcmc_controls$sigma_upper_multiplier * max(retained$vb_fit$sigma_mean, na.rm = TRUE))
  sigma_bounds <- c(1.0e-8, sigma_upper)
  support <- app_joint_qvp_exal_support(fixture$tau)
  width_default <- (as.numeric(support$upper) - as.numeric(support$lower)) / 20
  width_vector <- width_default * width_multiplier
  list(
    row = row,
    scenario_id = scenario_id,
    case_id = case_id,
    fixture = fixture,
    spec = spec,
    controls = controls,
    meta = meta,
    retained = retained,
    vb_elapsed = vb_elapsed,
    sigma_bounds = sigma_bounds,
    width_default = width_default,
    width_vector = width_vector
  )
}

run_one_chain <- function(job) {
  prep <- prep_by_case[[job$case_id[[1L]]]]
  fixture <- prep$fixture
  controls <- prep$controls
  chain_id <- as.integer(job$chain_id[[1L]])
  chain_seed <- as.integer(job$chain_seed[[1L]])
  init <- app_joint_exqdesn_gamma_chain_init(
    vb_fit = prep$retained$vb_fit,
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
    sigma_bounds = prep$sigma_bounds,
    gamma_slice_width = prep$width_vector,
    init = init
  )
  chain_elapsed <- proc.time()[["elapsed"]] - chain_start
  list(
    case_id = prep$case_id,
    scenario_id = prep$scenario_id,
    chain_id = chain_id,
    chain_seed = chain_seed,
    gamma_init = paste(format(as.numeric(init$gamma_mean %||% init$gamma), digits = 8, trim = TRUE), collapse = ","),
    fit = fit,
    runtime = data.frame(
      prep$meta,
      experiment_id = experiment_id,
      variant_id = experiment_id,
      width_multiplier = width_multiplier,
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
phase124c_dir <- resolve_path(arg_value("phase124c_dir"), must_work = TRUE)
fixture_dir <- resolve_path(arg_value("fixture_dir"), must_work = TRUE)
phase122_manifest <- app_joint_qdesn_phase108_manifest_verify(phase122_dir, "phase122_mcmc_case_confirmation")
phase124c_manifest <- app_joint_qdesn_phase108_manifest_verify(phase124c_dir, "phase124c_mcmc_balanced_completion")
artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)

controls122 <- app_read_csv(file.path(phase122_dir, "case_winner_controls.csv"))
controls124c <- app_read_csv(file.path(phase124c_dir, "case_winner_controls.csv"))
controls122$source_mcmc_phase <- "phase122"
controls124c$source_mcmc_phase <- "phase124c"
selected <- app_joint_qdesn_bind_rows(list(
  controls122[controls122$model_ids == "joint_exqdesn_rhs_vb", , drop = FALSE],
  controls124c[controls124c$model_ids == "joint_exqdesn_rhs_vb", , drop = FALSE]
))
selected <- selected[!duplicated(selected$case_id), , drop = FALSE]
scenario_ids <- parse_csv(arg_value("scenario_ids"))
case_ids <- parse_csv(arg_value("case_ids"))
if (length(scenario_ids)) selected <- selected[selected$scenario_ids %in% scenario_ids, , drop = FALSE]
if (length(case_ids)) selected <- selected[selected$case_id %in% case_ids, , drop = FALSE]
case_limit <- parse_integer(arg_value("case_limit"), allow_empty = TRUE)
selected <- selected[order(selected$scenario_ids), , drop = FALSE]
if (!is.null(case_limit)) selected <- head(selected, case_limit)
if (!nrow(selected)) stop("No Joint exQDESN exAL-RHS cases selected.", call. = FALSE)

width_multiplier <- parse_number(arg_value("width_multiplier"))
if (!is.finite(width_multiplier) || width_multiplier <= 0) stop("width_multiplier must be positive.", call. = FALSE)
experiment_id <- paste0("gamma_width_multiplier_", gsub("[^0-9]+", "p", format(width_multiplier, trim = TRUE, scientific = FALSE)))
vb_max_iter_override <- parse_integer(arg_value("vb_max_iter_override"), allow_empty = TRUE)
vb_grid_override <- parse_csv(arg_value("adaptive_vb_max_iter_grid_override"))
gamma_init_mode <- as.character(arg_value("gamma_init_mode"))[[1L]]
gamma_jitter_fraction <- parse_number(arg_value("gamma_jitter_fraction"))
trace_write_stride <- parse_integer(arg_value("trace_write_stride"))
save_rdata <- parse_bool(arg_value("save_rdata"))

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
vb_n_cores <- parse_integer(arg_value("vb_n_cores"))

row_by_case <- split(selected, selected$case_id)
prep_start <- proc.time()[["elapsed"]]
prep_results <- app_joint_qdesn_parallel_lapply(names(row_by_case), function(cid) prepare_one_case(row_by_case[[cid]]), vb_n_cores)
prep_elapsed <- proc.time()[["elapsed"]] - prep_start
case_prep_failures <- app_joint_qdesn_worker_failure_rows(prep_results, "phase129_case_preparation")
case_preps <- app_joint_qdesn_successful_worker_results(prep_results, "phase129_case_preparation")
prep_by_case <- stats::setNames(case_preps, vapply(case_preps, `[[`, character(1L), "case_id"))

base_jobs <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) {
  base_seed <- as.integer(prep$fixture$scenario_meta$seed[[1L]])
  case_offset <- sum(utf8ToInt(prep$case_id)) %% 100000L
  app_joint_qdesn_bind_rows(lapply(seq_len(mcmc_controls$n_chains), function(chain_id) {
    data.frame(
      job_id = sprintf("%s_chain_%02d", prep$case_id, chain_id),
      case_id = prep$case_id,
      scenario_id = prep$scenario_id,
      chain_id = chain_id,
      chain_seed = base_seed + mcmc_controls$mcmc_seed_offset + case_offset +
        (chain_id - 1L) * mcmc_controls$chain_seed_stride,
      stringsAsFactors = FALSE
    )
  }))
}))

job_by_id <- split(base_jobs, base_jobs$job_id)
mcmc_start <- proc.time()[["elapsed"]]
chain_results <- app_joint_qdesn_parallel_lapply(names(job_by_id), function(jid) run_one_chain(job_by_id[[jid]]), mcmc_controls$n_cores)
mcmc_elapsed <- proc.time()[["elapsed"]] - mcmc_start
chain_worker_failures <- app_joint_qdesn_worker_failure_rows(chain_results, "phase129_gamma_width4_chain")
successful_chains <- app_joint_qdesn_successful_worker_results(chain_results, "phase129_gamma_width4_chain")
chains_by_case <- split(successful_chains, vapply(successful_chains, `[[`, character(1L), "case_id"))

chain_initialization <- app_joint_qdesn_bind_rows(lapply(successful_chains, function(x) {
  prep <- prep_by_case[[x$case_id]]
  data.frame(
    prep$meta,
    experiment_id = experiment_id,
    variant_id = experiment_id,
    width_multiplier = width_multiplier,
    chain_id = x$chain_id,
    chain_seed = x$chain_seed,
    gamma_init_mode = gamma_init_mode,
    gamma_init = x$gamma_init,
    stringsAsFactors = FALSE
  )
}))

case_results <- lapply(names(chains_by_case), function(cid) {
  prep <- prep_by_case[[cid]]
  results <- chains_by_case[[cid]]
  results <- results[order(vapply(results, `[[`, integer(1L), "chain_id"))]
  fits <- lapply(results, `[[`, "fit")
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(fits, prep$fixture$Z, length(prep$fixture$tau), ncol(prep$fixture$Z), prep$fixture$tau)
  meta <- cbind(prep$meta, data.frame(experiment_id = experiment_id, variant_id = experiment_id, width_multiplier = width_multiplier, stringsAsFactors = FALSE))
  trace <- app_joint_exqdesn_mcmc_chain_trace_rows(
    fits,
    prep$fixture$tau,
    meta,
    mcmc_controls$mcmc_n_iter,
    mcmc_controls$mcmc_burn,
    mcmc_controls$mcmc_thin
  )
  rhat <- app_joint_exqdesn_mcmc_rhat_ess_rows(fits, prep$fixture$tau, meta)
  draw <- app_joint_qdesn_bind_rows(lapply(seq_along(fits), function(chain_id) {
    cbind(
      meta,
      data.frame(chain_id = chain_id, chain_seed = fits[[chain_id]]$seed %||% NA_integer_, stringsAsFactors = FALSE),
      app_joint_qdesn_phase122_draw_summary(fits[[chain_id]], prep$case_id, "phase129_gamma_width4_packet", prep$fixture$scenario_id, sigma_bounds = prep$sigma_bounds),
      stringsAsFactors = FALSE
    )
  }))
  distance <- app_joint_qvp_vb_mcmc_distance_summary(
    prep$retained$vb_fit,
    pooled,
    prep$case_id,
    "phase129_gamma_width4_packet",
    prep$fixture$scenario_id,
    length(prep$fixture$y),
    ncol(prep$fixture$Z),
    length(prep$fixture$tau)
  )
  if (!is.null(prep$retained$vb_fit$gamma_mean) && !is.null(pooled$gamma_mean)) {
    gamma_l2 <- app_joint_qvp_l2_distance(prep$retained$vb_fit$gamma_mean, pooled$gamma_mean)
    distance$gamma_l2_to_mcmc <- gamma_l2
    distance$gamma_normalized_distance <- gamma_l2 / (sqrt(length(prep$fixture$tau)) * (1 + sqrt(mean(prep$retained$vb_fit$gamma_mean^2))))
    distance$max_normalized_distance <- pmax(distance$max_normalized_distance, distance$gamma_normalized_distance, na.rm = TRUE)
  } else {
    distance$gamma_l2_to_mcmc <- NA_real_
    distance$gamma_normalized_distance <- NA_real_
  }
  chain_distance <- app_joint_qvp_chain_to_pooled_summary(
    fits,
    pooled,
    prep$fixture$Z,
    prep$case_id,
    "phase129_gamma_width4_packet",
    prep$fixture$scenario_id,
    length(prep$fixture$y),
    ncol(prep$fixture$Z),
    length(prep$fixture$tau)
  )
  figure_path <- file.path(out_dir, "figures", paste0("trace_diagnostics_", app_joint_exqdesn_trace_safe_id(prep$scenario_id), ".pdf"))
  app_joint_exqdesn_plot_variant_diagnostics(experiment_id, trace, app_joint_exqdesn_vb_trace_rows(prep$retained$vb_fit, prep$fixture$tau, prep$meta), figure_path)
  list(
    meta = meta,
    prep = prep,
    trace_compact = thin_trace_rows(trace, trace_write_stride),
    trace_summary = app_joint_exqdesn_mcmc_trace_summary_rows(trace),
    rhat = rhat,
    gap = app_joint_exqdesn_chain_mean_gap_rows(trace),
    autocorrelation = app_joint_exqdesn_autocorrelation_rows(trace),
    draw = draw,
    distance = cbind(meta, distance, stringsAsFactors = FALSE),
    chain_distance = cbind(meta, chain_distance, stringsAsFactors = FALSE),
    runtime = app_joint_qdesn_bind_rows(lapply(results, `[[`, "runtime")),
    figure_path = figure_path
  )
})
names(case_results) <- vapply(case_results, function(x) x$prep$case_id, character(1L))

mcmc_trace_compact <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "trace_compact"))
mcmc_trace_summary <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "trace_summary"))
mcmc_rhat_ess <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "rhat"))
chain_mean_gap <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "gap"))
autocorrelation <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "autocorrelation"))
mcmc_draw_summary <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "draw"))
vb_mcmc_distance <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "distance"))
chain_to_pooled_distance <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "chain_distance"))
runtime <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "runtime"))

vb_case_summary <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) {
  cbind(prep$meta, data.frame(
    experiment_id = experiment_id,
    variant_id = experiment_id,
    width_multiplier = width_multiplier,
    n_train = length(prep$fixture$y),
    p = ncol(prep$fixture$Z),
    K = length(prep$fixture$tau),
    tau_grid = app_joint_qdesn_format_tau(prep$fixture$tau),
    source_candidate_id = prep$row$candidate_id[[1L]],
    source_mcmc_phase = prep$row$source_mcmc_phase[[1L]],
    vb_converged = isTRUE(prep$retained$vb_fit$converged),
    vb_reached_max_iter = !isTRUE(prep$retained$vb_fit$converged),
    vb_adaptive_attempts = attr(prep$retained$vb_fit, "adaptive_vb_attempts") %||% as.character(prep$controls$vb_max_iter),
    vb_max_iter_used = as.integer(attr(prep$retained$vb_fit, "adaptive_vb_max_iter_used") %||% prep$controls$vb_max_iter),
    vb_elapsed_seconds = prep$vb_elapsed,
    sigma_lower_bound = prep$sigma_bounds[[1L]],
    sigma_upper_bound = prep$sigma_bounds[[2L]],
    default_gamma_slice_width_by_tau = paste(format(prep$width_default, digits = 8, trim = TRUE), collapse = ","),
    gamma_slice_width_by_tau = paste(format(prep$width_vector, digits = 8, trim = TRUE), collapse = ","),
    stringsAsFactors = FALSE
  ))
}))
vb_attempts <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) cbind(prep$meta, prep$retained$attempts, stringsAsFactors = FALSE)))
vb_trace <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) app_joint_exqdesn_vb_trace_rows(prep$retained$vb_fit, prep$fixture$tau, prep$meta)))
al_sigma <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) app_joint_exqdesn_matrix_trace_long(prep$retained$al_init$sigma_trace, prep$fixture$tau, prep$meta, "al_init_sigma")))
vb_objective <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) {
  app_joint_qdesn_bind_rows(list(
    app_joint_exqdesn_vb_objective_rows(prep$retained$al_init, prep$meta, "al_init"),
    app_joint_exqdesn_vb_objective_rows(prep$retained$vb_fit, prep$meta, "exal_vb_ld")
  ))
}))
vb_monitor <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) {
  app_joint_qdesn_bind_rows(list(
    app_joint_exqdesn_vb_monitor_rows(prep$retained$al_init, prep$meta, "al_init"),
    app_joint_exqdesn_vb_monitor_rows(prep$retained$vb_fit, prep$meta, "exal_vb_ld")
  ))
}))
rhs_prior <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) app_joint_exqdesn_rhs_summary_rows(prep$retained$vb_fit, prep$meta)))

case_assessment <- app_joint_qdesn_bind_rows(lapply(case_preps, function(prep) {
  rh <- mcmc_rhat_ess[mcmc_rhat_ess$case_id == prep$case_id, , drop = FALSE]
  gap <- chain_mean_gap[chain_mean_gap$case_id == prep$case_id, , drop = FALSE]
  ac <- autocorrelation[autocorrelation$case_id == prep$case_id & autocorrelation$lag == 1L, , drop = FALSE]
  draw <- mcmc_draw_summary[mcmc_draw_summary$case_id == prep$case_id, , drop = FALSE]
  finite_rhat <- rh$rhat[is.finite(rh$rhat)]
  finite_ess <- rh$rough_ess_total[is.finite(rh$rough_ess_total)]
  gamma_rhat <- rh$rhat[rh$parameter == "gamma" & is.finite(rh$rhat)]
  gamma_ess <- rh$rough_ess_total[rh$parameter == "gamma" & is.finite(rh$rough_ess_total)]
  gamma_gap <- gap$chain_mean_gap[gap$parameter == "gamma" & is.finite(gap$chain_mean_gap)]
  gamma_ac1 <- ac$autocorrelation[ac$parameter == "gamma" & is.finite(ac$autocorrelation)]
  sigma_upper_hit <- draw$upper_bound_hit_fraction[draw$block == "sigma" & is.finite(draw$upper_bound_hit_fraction)]
  max_rhat <- if (length(finite_rhat)) max(finite_rhat) else NA_real_
  min_ess <- if (length(finite_ess)) min(finite_ess) else NA_real_
  max_gamma_rhat <- if (length(gamma_rhat)) max(gamma_rhat) else NA_real_
  min_gamma_ess <- if (length(gamma_ess)) min(gamma_ess) else NA_real_
  max_gamma_gap <- if (length(gamma_gap)) max(gamma_gap) else NA_real_
  max_gamma_ac1 <- if (length(gamma_ac1)) max(gamma_ac1) else NA_real_
  max_sigma_upper_hit <- if (length(sigma_upper_hit)) max(sigma_upper_hit) else NA_real_
  hard_fail <- nrow(case_prep_failures) > 0L || nrow(chain_worker_failures) > 0L ||
    !nrow(rh) || !all(rh$n_chains == mcmc_controls$n_chains) ||
    any(!is.finite(c(max_rhat, min_ess, max_gamma_rhat, min_gamma_ess)))
  review <- !hard_fail && (
    isTRUE(!prep$retained$vb_fit$converged) ||
      (is.finite(max_rhat) && max_rhat > 1.2) ||
      (is.finite(min_ess) && min_ess < 100) ||
      (is.finite(max_gamma_ac1) && max_gamma_ac1 > 0.98) ||
      (is.finite(max_sigma_upper_hit) && max_sigma_upper_hit > 0)
  )
  cbind(prep$meta, data.frame(
    experiment_id = experiment_id,
    variant_id = experiment_id,
    width_multiplier = width_multiplier,
    case_gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    max_rhat = max_rhat,
    min_rough_ess_total = min_ess,
    max_gamma_rhat = max_gamma_rhat,
    min_gamma_rough_ess_total = min_gamma_ess,
    max_gamma_chain_mean_gap = max_gamma_gap,
    max_gamma_lag1_autocorrelation = max_gamma_ac1,
    max_sigma_upper_bound_hit_fraction = max_sigma_upper_hit,
    status_reason = paste(c(
      if (hard_fail) "worker failure or missing/nonfinite diagnostics",
      if (!hard_fail && isTRUE(!prep$retained$vb_fit$converged)) "VB-LD reached max iterations",
      if (!hard_fail && is.finite(max_rhat) && max_rhat > 1.2) "MCMC Rhat exceeds diagnostic review threshold",
      if (!hard_fail && is.finite(min_ess) && min_ess < 100) "rough ESS below diagnostic review threshold",
      if (!hard_fail && is.finite(max_gamma_ac1) && max_gamma_ac1 > 0.98) "gamma lag-1 autocorrelation remains high",
      if (!hard_fail && is.finite(max_sigma_upper_hit) && max_sigma_upper_hit > 0) "sigma upper bound hit"
    ), collapse = "; "),
    stringsAsFactors = FALSE
  ))
}))
case_ranking <- case_assessment[order(
  case_assessment$case_gate_status != "pass",
  case_assessment$max_gamma_rhat,
  -case_assessment$min_gamma_rough_ess_total,
  case_assessment$max_gamma_lag1_autocorrelation
), , drop = FALSE]
case_ranking$rank <- seq_len(nrow(case_ranking))

dashboard_path <- file.path(out_dir, "figures", "00_phase129_gamma_width4_packet_dashboard.pdf")
plot_phase129_dashboard(case_assessment, mcmc_rhat_ess, dashboard_path)
figure_paths <- unlist(lapply(case_results, `[[`, "figure_path"), use.names = FALSE)
figure_paths <- c(dashboard_path, figure_paths)

run_config <- data.frame(
  run_id = "joint_qdesn_phase129_joint_exqdesn_gamma_width4_packet",
  out_dir = out_dir,
  phase122_dir = phase122_dir,
  phase124c_dir = phase124c_dir,
  fixture_dir = artifacts$fixture_dir,
  selected_cases = paste(selected$case_id, collapse = ","),
  n_cases = nrow(selected),
  width_multiplier = width_multiplier,
  trace_write_stride = trace_write_stride,
  n_chains = mcmc_controls$n_chains,
  mcmc_n_iter = mcmc_controls$mcmc_n_iter,
  mcmc_burn = mcmc_controls$mcmc_burn,
  mcmc_thin = mcmc_controls$mcmc_thin,
  mcmc_seed_offset = mcmc_controls$mcmc_seed_offset,
  chain_seed_stride = mcmc_controls$chain_seed_stride,
  sigma_upper_multiplier = mcmc_controls$sigma_upper_multiplier,
  n_cores = mcmc_controls$n_cores,
  vb_n_cores = vb_n_cores,
  gamma_init_mode = gamma_init_mode,
  gamma_jitter_fraction = gamma_jitter_fraction,
  raw_rdata_saved = save_rdata,
  case_preparation_elapsed_seconds = prep_elapsed,
  mcmc_elapsed_seconds = mcmc_elapsed,
  validation_contract = "fixed_width4_joint_exqdesn_exal_rhs_trace_packet_no_article_table_mutation",
  scalar_predictive_density_claim = FALSE,
  stringsAsFactors = FALSE
)

readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint exQDESN exAL-RHS Phase129 Gamma Width-x4 Packet",
  "",
  "This artifact propagates the Phase128-selected gamma slice-width multiplier to the full eight-scenario Joint exQDESN exAL-RHS packet.",
  "It is a sampler-health confirmation layer, not an article-table promotion layer.",
  "",
  sprintf("- Phase122 source: `%s`", phase122_dir),
  sprintf("- Phase124c source: `%s`", phase124c_dir),
  sprintf("- Fixture source: `%s`", artifacts$fixture_dir),
  sprintf("- Cases: `%s`", nrow(selected)),
  sprintf("- Width multiplier: `%s`", width_multiplier),
  sprintf("- Chains per case: `%s`", mcmc_controls$n_chains),
  sprintf("- MCMC iterations/burn/thin: `%s/%s/%s`", mcmc_controls$mcmc_n_iter, mcmc_controls$mcmc_burn, mcmc_controls$mcmc_thin),
  sprintf("- Gamma initialisation mode: `%s`", gamma_init_mode),
  sprintf("- Trace write stride: `%s`", trace_write_stride),
  sprintf("- Raw RData saved: `%s`", save_rdata),
  "",
  "Full traces are used in memory for diagnostics and figures; the written trace table is compacted by `trace_write_stride`.",
  "Promotion requires clean worker/manifests, acceptable Rhat/ESS, no sigma bound sensitivity, and a case-level review of residual gamma autocorrelation.",
  "",
  "Case gate counts:",
  paste(capture.output(print(table(case_assessment$case_gate_status))), collapse = "\n")
), readme_path, useBytes = TRUE)

paths <- c(
  run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
  phase122_source_manifest_verification = app_joint_qvp_write_csv(phase122_manifest, file.path(out_dir, "phase122_source_manifest_verification.csv")),
  phase124c_source_manifest_verification = app_joint_qvp_write_csv(phase124c_manifest, file.path(out_dir, "phase124c_source_manifest_verification.csv")),
  fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
  selected_case_controls = app_joint_qvp_write_csv(selected, file.path(out_dir, "selected_case_controls.csv")),
  case_preparation_failures = app_joint_qvp_write_csv(case_prep_failures, file.path(out_dir, "case_preparation_failures.csv")),
  chain_worker_failures = app_joint_qvp_write_csv(chain_worker_failures, file.path(out_dir, "chain_worker_failures.csv")),
  chain_initialization = app_joint_qvp_write_csv(chain_initialization, file.path(out_dir, "chain_initialization.csv")),
  vb_case_summary = app_joint_qvp_write_csv(vb_case_summary, file.path(out_dir, "vb_case_summary.csv")),
  vb_adaptive_attempts = app_joint_qvp_write_csv(vb_attempts, file.path(out_dir, "vb_adaptive_attempts.csv")),
  vb_gamma_sigma_lambda_trace = app_joint_qvp_write_csv(vb_trace, file.path(out_dir, "vb_gamma_sigma_lambda_trace.csv")),
  vb_al_init_sigma_trace = app_joint_qvp_write_csv(al_sigma, file.path(out_dir, "vb_al_init_sigma_trace.csv")),
  vb_objective_trace = app_joint_qvp_write_csv(vb_objective, file.path(out_dir, "vb_objective_trace.csv")),
  vb_monitor_terms = app_joint_qvp_write_csv(vb_monitor, file.path(out_dir, "vb_monitor_terms.csv")),
  rhs_prior_summary = app_joint_qvp_write_csv(rhs_prior, file.path(out_dir, "rhs_prior_summary.csv")),
  mcmc_gamma_sigma_lambda_trace_compact = app_joint_qvp_write_csv(mcmc_trace_compact, file.path(out_dir, "mcmc_gamma_sigma_lambda_trace_compact.csv")),
  mcmc_trace_summary = app_joint_qvp_write_csv(mcmc_trace_summary, file.path(out_dir, "mcmc_trace_summary.csv")),
  mcmc_rhat_ess_summary = app_joint_qvp_write_csv(mcmc_rhat_ess, file.path(out_dir, "mcmc_rhat_ess_summary.csv")),
  chain_mean_gap_summary = app_joint_qvp_write_csv(chain_mean_gap, file.path(out_dir, "chain_mean_gap_summary.csv")),
  autocorrelation_summary = app_joint_qvp_write_csv(autocorrelation, file.path(out_dir, "autocorrelation_summary.csv")),
  mcmc_draw_summary = app_joint_qvp_write_csv(mcmc_draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
  vb_mcmc_distance_summary = app_joint_qvp_write_csv(vb_mcmc_distance, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
  chain_to_pooled_distance_summary = app_joint_qvp_write_csv(chain_to_pooled_distance, file.path(out_dir, "chain_to_pooled_distance_summary.csv")),
  runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
  case_assessment = app_joint_qvp_write_csv(case_assessment, file.path(out_dir, "case_assessment.csv")),
  case_ranking = app_joint_qvp_write_csv(case_ranking, file.path(out_dir, "case_ranking.csv")),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE)
)
names(figure_paths) <- paste0("figure_", seq_along(figure_paths))
paths <- c(paths, figure_paths)

if (isTRUE(save_rdata)) {
  raw_path <- file.path(out_dir, "raw_objects", "phase129_gamma_width4_packet_objects.RData")
  save(selected, case_preps, case_results, run_config, file = raw_path, compress = "xz")
  paths <- c(paths, raw_rdata = raw_path)
}

manifest_info <- app_joint_exqdesn_trace_manifest(paths, out_dir)

cat(sprintf("Phase129 gamma-width packet written to %s\n", normalizePath(out_dir, mustWork = TRUE)))
cat("Run summary:\n")
print(run_config[, c("n_cases", "width_multiplier", "n_chains", "mcmc_n_iter", "mcmc_burn", "mcmc_thin", "n_cores", "vb_n_cores", "trace_write_stride", "raw_rdata_saved")], row.names = FALSE)
cat("Case gate counts:\n")
print(table(case_assessment$case_gate_status))
cat(sprintf("Case preparation failures: %d\n", nrow(case_prep_failures)))
cat(sprintf("Chain worker failures: %d\n", nrow(chain_worker_failures)))
cat(sprintf("Dashboard: %s\n", normalizePath(dashboard_path, mustWork = TRUE)))
cat(sprintf("Artifact manifest: %s\n", manifest_info$manifest_path))
