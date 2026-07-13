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

args <- app_parse_args(list(
  output_dir = "application/cache/joint_qdesn_phase127_joint_exqdesn_exal_rhs_trace_diagnostics_20260712",
  phase122_dir = "application/cache/joint_qdesn_phase122_mcmc_case_confirmation_20260711",
  phase124c_dir = "application/cache/joint_qdesn_phase124c_mcmc_balanced_completion_20260711",
  fixture_dir = "application/cache/joint_qdesn_simulation_dgp_fixtures_20260706",
  case_ids = "",
  scenario_ids = "",
  case_limit = "",
  n_chains = "2",
  mcmc_n_iter = "1200",
  mcmc_burn = "600",
  mcmc_thin = "1",
  mcmc_seed_offset = "4100",
  chain_seed_stride = "100",
  sigma_upper_multiplier = "50",
  distance_pass = "5",
  chain_pass = "5",
  n_cores = "8",
  vb_max_iter_override = "",
  adaptive_vb_max_iter_grid_override = "",
  save_rdata = "true"
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

parse_number <- function(x) {
  x <- as.character(x)[[1L]]
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

safe_id <- function(x) {
  gsub("[^A-Za-z0-9_]+", "_", as.character(x))
}

relative_to_dir <- function(paths, root_dir) {
  root <- normalizePath(root_dir, mustWork = TRUE)
  abs_paths <- normalizePath(paths, mustWork = TRUE)
  prefix <- paste0(root, .Platform$file.sep)
  out <- ifelse(startsWith(abs_paths, prefix), substring(abs_paths, nchar(prefix) + 1L), basename(abs_paths))
  out
}

write_trace_manifest <- function(paths, out_dir) {
  labels <- names(paths)
  paths <- unname(paths)
  manifest <- data.frame(
    label = labels,
    relative_path = relative_to_dir(paths, out_dir),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(manifest = manifest, manifest_path = manifest_path)
}

exal_lambda_vector <- function(tau, gamma) {
  vapply(seq_along(tau), function(ii) {
    app_joint_qvp_exal_constants(tau[[ii]], gamma[[ii]])$lambda[[1L]]
  }, numeric(1L))
}

matrix_trace_long <- function(mat, tau, case_meta, parameter, iteration_name = "iter") {
  if (is.null(mat)) return(data.frame())
  mat <- as.matrix(mat)
  if (!length(mat)) return(data.frame())
  rows <- lapply(seq_along(tau), function(kk) {
    out <- data.frame(
      case_meta,
      trace_source = parameter,
      iter = seq_len(nrow(mat)),
      quantile_index = kk,
      tau = tau[[kk]],
      value = as.numeric(mat[, kk]),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    if (!identical(iteration_name, "iter")) {
      names(out)[names(out) == "iter"] <- iteration_name
    }
    out
  })
  app_joint_qdesn_bind_rows(rows)
}

summary_stats <- function(x) {
  x <- as.numeric(x)
  finite <- x[is.finite(x)]
  if (!length(finite)) {
    return(data.frame(
      n = length(x), n_finite = 0L, mean = NA_real_, sd = NA_real_,
      min = NA_real_, q05 = NA_real_, median = NA_real_, q95 = NA_real_,
      max = NA_real_, first = NA_real_, last = NA_real_, drift = NA_real_,
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    n = length(x),
    n_finite = length(finite),
    mean = mean(finite),
    sd = if (length(finite) > 1L) stats::sd(finite) else NA_real_,
    min = min(finite),
    q05 = as.numeric(stats::quantile(finite, 0.05, names = FALSE, type = 8)),
    median = stats::median(finite),
    q95 = as.numeric(stats::quantile(finite, 0.95, names = FALSE, type = 8)),
    max = max(finite),
    first = finite[[1L]],
    last = finite[[length(finite)]],
    drift = finite[[length(finite)]] - finite[[1L]],
    stringsAsFactors = FALSE
  )
}

rough_ess_one_chain <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 4L || stats::sd(x) == 0) return(NA_real_)
  lag_max <- min(100L, n - 1L)
  ac <- tryCatch(stats::acf(x, lag.max = lag_max, plot = FALSE, na.action = stats::na.pass)$acf[-1L], error = function(e) numeric())
  ac <- as.numeric(ac)
  ac <- ac[is.finite(ac)]
  if (!length(ac)) return(n)
  pos <- ac[seq_len(match(TRUE, ac < 0, nomatch = length(ac) + 1L) - 1L)]
  denom <- 1 + 2 * sum(pos)
  if (!is.finite(denom) || denom <= 0) return(NA_real_)
  n / denom
}

classic_rhat <- function(draw_matrix) {
  draw_matrix <- as.matrix(draw_matrix)
  draw_matrix <- draw_matrix[, colSums(is.finite(draw_matrix)) == nrow(draw_matrix), drop = FALSE]
  m <- ncol(draw_matrix)
  n <- nrow(draw_matrix)
  if (m < 2L || n < 2L) return(NA_real_)
  chain_vars <- apply(draw_matrix, 2L, stats::var)
  W <- mean(chain_vars)
  if (!is.finite(W) || W <= 0) return(NA_real_)
  B <- n * stats::var(colMeans(draw_matrix))
  var_hat <- ((n - 1) / n) * W + B / n
  sqrt(var_hat / W)
}

mcmc_chain_trace_rows <- function(fits, tau, case_meta, n_iter, burn, thin) {
  keep_idx <- seq.int(as.integer(burn) + 1L, as.integer(n_iter), by = as.integer(thin))
  rows <- list()
  for (chain_id in seq_along(fits)) {
    fit <- fits[[chain_id]]
    n_keep <- nrow(fit$sigma_draws)
    draw_index <- seq_len(n_keep)
    mcmc_iter <- keep_idx[draw_index]
    for (kk in seq_along(tau)) {
      gamma <- if (!is.null(fit$gamma_draws)) as.numeric(fit$gamma_draws[, kk]) else rep(NA_real_, n_keep)
      sigma <- as.numeric(fit$sigma_draws[, kk])
      lambda <- rep(NA_real_, n_keep)
      if (!all(is.na(gamma))) {
        lambda <- vapply(gamma, function(g) app_joint_qvp_exal_constants(tau[[kk]], g)$lambda[[1L]], numeric(1L))
      }
      rows[[length(rows) + 1L]] <- data.frame(
        case_meta,
        chain_id = chain_id,
        chain_seed = fit$seed %||% NA_integer_,
        draw_index = draw_index,
        mcmc_iter = mcmc_iter,
        quantile_index = kk,
        tau = tau[[kk]],
        sigma = sigma,
        gamma = gamma,
        exal_lambda = lambda,
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

mcmc_trace_summary_rows <- function(trace_rows) {
  if (!nrow(trace_rows)) return(data.frame())
  pieces <- list()
  parameters <- c("sigma", "gamma", "exal_lambda")
  for (param in parameters) {
    groups <- split(trace_rows, interaction(trace_rows$case_id, trace_rows$chain_id, trace_rows$quantile_index, drop = TRUE, lex.order = TRUE))
    pieces <- c(pieces, lapply(groups, function(block) {
      key <- block[1L, c("case_id", "scenario_id", "model_id", "chain_id", "chain_seed", "quantile_index", "tau"), drop = FALSE]
      cbind(key, data.frame(parameter = param, stringsAsFactors = FALSE), summary_stats(block[[param]]), stringsAsFactors = FALSE)
    }))
  }
  app_joint_qdesn_bind_rows(pieces)
}

mcmc_rhat_ess_rows <- function(fits, tau, case_meta) {
  rows <- list()
  for (param in c("sigma", "gamma")) {
    for (kk in seq_along(tau)) {
      mats <- lapply(fits, function(fit) {
        x <- if (identical(param, "sigma")) fit$sigma_draws else fit$gamma_draws
        if (is.null(x)) return(rep(NA_real_, nrow(fit$sigma_draws)))
        as.numeric(x[, kk])
      })
      n_min <- min(vapply(mats, length, integer(1L)))
      draw_matrix <- do.call(cbind, lapply(mats, function(x) x[seq_len(n_min)]))
      ess <- sum(vapply(seq_len(ncol(draw_matrix)), function(jj) rough_ess_one_chain(draw_matrix[, jj]), numeric(1L)), na.rm = TRUE)
      rows[[length(rows) + 1L]] <- data.frame(
        case_meta,
        parameter = param,
        quantile_index = kk,
        tau = tau[[kk]],
        n_chains = ncol(draw_matrix),
        n_draws_per_chain = nrow(draw_matrix),
        rhat = classic_rhat(draw_matrix),
        rough_ess_total = ess,
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

vb_exal_lambda_trace_rows <- function(vb_fit, tau, case_meta) {
  if (is.null(vb_fit$gamma_trace)) return(data.frame())
  gamma_trace <- as.matrix(vb_fit$gamma_trace)
  rows <- lapply(seq_len(nrow(gamma_trace)), function(ii) {
    lambda <- exal_lambda_vector(tau, as.numeric(gamma_trace[ii, ]))
    data.frame(
      case_meta,
      iter = ii,
      quantile_index = seq_along(tau),
      tau = tau,
      gamma = as.numeric(gamma_trace[ii, ]),
      sigma = if (!is.null(vb_fit$sigma_trace)) as.numeric(vb_fit$sigma_trace[ii, ]) else NA_real_,
      exal_lambda = lambda,
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

vb_objective_rows <- function(fit, case_meta, phase) {
  trace <- fit$trace %||% data.frame()
  if (!nrow(trace)) return(data.frame())
  cbind(case_meta, data.frame(vb_phase = phase, stringsAsFactors = FALSE), trace, stringsAsFactors = FALSE)
}

vb_monitor_rows <- function(fit, case_meta, phase) {
  monitor <- fit$monitor_terms %||% data.frame()
  if (!nrow(monitor)) return(data.frame())
  cbind(case_meta, data.frame(vb_phase = phase, stringsAsFactors = FALSE), monitor, stringsAsFactors = FALSE)
}

rhs_summary_rows <- function(vb_fit, case_meta) {
  rhs <- vb_fit$rhs_prior_summary %||% data.frame()
  if (!nrow(rhs)) return(data.frame())
  cbind(case_meta, rhs, stringsAsFactors = FALSE)
}

plot_trace_panel <- function(x, y, group, main, ylab) {
  if (!length(y) || all(!is.finite(y))) {
    plot.new()
    title(main)
    text(0.5, 0.5, "No finite trace values")
    return(invisible(NULL))
  }
  plot(x, y, type = "n", main = main, xlab = "iteration/draw", ylab = ylab)
  groups <- unique(group)
  cols <- grDevices::hcl.colors(max(3L, length(groups)), palette = "Dark 3")
  for (ii in seq_along(groups)) {
    idx <- group == groups[[ii]]
    lines(x[idx], y[idx], col = cols[[ii]], lwd = 0.8)
  }
  legend("topright", legend = groups, col = cols[seq_along(groups)], lty = 1, cex = 0.55, bty = "n")
  invisible(NULL)
}

plot_case_diagnostics <- function(case_id, scenario_id, tau, mcmc_trace, vb_trace, al_init, vb_fit, out_path) {
  grDevices::pdf(out_path, width = 12, height = 9)
  on.exit(grDevices::dev.off(), add = TRUE)
  par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
  block <- mcmc_trace[mcmc_trace$case_id == case_id, , drop = FALSE]
  group <- paste0("tau=", format(block$tau, trim = TRUE), " c", block$chain_id)
  plot_trace_panel(block$draw_index, block$gamma, group, sprintf("%s: MCMC gamma", scenario_id), "gamma")
  plot_trace_panel(block$draw_index, block$sigma, group, sprintf("%s: MCMC sigma", scenario_id), "sigma")
  plot_trace_panel(block$draw_index, block$exal_lambda, group, sprintf("%s: MCMC exAL lambda", scenario_id), "lambda")
  vb_block <- vb_trace[vb_trace$case_id == case_id, , drop = FALSE]
  vb_group <- paste0("tau=", format(vb_block$tau, trim = TRUE))
  plot_trace_panel(vb_block$iter, vb_block$gamma, vb_group, sprintf("%s: VB-LD gamma", scenario_id), "gamma")

  par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
  plot_trace_panel(vb_block$iter, vb_block$sigma, vb_group, sprintf("%s: VB-LD sigma", scenario_id), "sigma")
  plot_trace_panel(vb_block$iter, vb_block$exal_lambda, vb_group, sprintf("%s: VB-LD exAL lambda", scenario_id), "lambda")
  tr <- vb_fit$trace %||% data.frame()
  if (nrow(tr) && "monitor" %in% names(tr)) {
    plot(tr$iter, tr$monitor, type = "l", main = sprintf("%s: VB-LD monitor", scenario_id), xlab = "iteration", ylab = "monitor")
  } else {
    plot.new(); title("VB-LD monitor"); text(0.5, 0.5, "Unavailable")
  }
  atr <- al_init$trace %||% data.frame()
  if (nrow(atr) && "partial_elbo" %in% names(atr)) {
    plot(atr$iter, atr$partial_elbo, type = "l", main = sprintf("%s: AL-init partial ELBO", scenario_id), xlab = "iteration", ylab = "partial ELBO")
  } else if (nrow(atr) && "monitor" %in% names(atr)) {
    plot(atr$iter, atr$monitor, type = "l", main = sprintf("%s: AL-init monitor", scenario_id), xlab = "iteration", ylab = "monitor")
  } else {
    plot.new(); title("AL-init objective"); text(0.5, 0.5, "Unavailable")
  }
}

plot_dashboard <- function(summary, rhat, vb_trace, out_path) {
  grDevices::pdf(out_path, width = 12, height = 9)
  on.exit(grDevices::dev.off(), add = TRUE)
  par(mfrow = c(2, 2), mar = c(6, 4, 3, 1))
  if (nrow(summary)) {
    boxplot(mean ~ parameter, data = summary, main = "MCMC trace means by parameter", ylab = "mean", las = 2)
    boxplot(sd ~ parameter, data = summary, main = "MCMC trace SD by parameter", ylab = "sd", las = 2)
  } else {
    plot.new(); title("MCMC summaries unavailable")
    plot.new(); title("MCMC summaries unavailable")
  }
  if (nrow(rhat) && any(is.finite(rhat$rhat))) {
    boxplot(rhat ~ parameter, data = rhat, main = "Classic Rhat by parameter", ylab = "Rhat", las = 2)
  } else {
    plot.new(); title("Rhat unavailable")
  }
  if (nrow(vb_trace)) {
    aggregate_sigma <- aggregate(sigma ~ case_id + iter, vb_trace, mean, na.rm = TRUE)
    plot(aggregate_sigma$iter, aggregate_sigma$sigma, type = "n", main = "Mean VB sigma trace by case", xlab = "iteration", ylab = "mean sigma")
    cases <- unique(aggregate_sigma$case_id)
    cols <- grDevices::hcl.colors(max(3L, length(cases)), palette = "Dark 3")
    for (ii in seq_along(cases)) {
      block <- aggregate_sigma[aggregate_sigma$case_id == cases[[ii]], , drop = FALSE]
      lines(block$iter, block$sigma, col = cols[[ii]])
    }
    legend("topright", legend = cases, col = cols[seq_along(cases)], lty = 1, cex = 0.45, bty = "n")
  } else {
    plot.new(); title("VB traces unavailable")
  }
}

fit_joint_exal_with_retained_init <- function(fixture, controls) {
  grid <- unique(as.integer(c(controls$vb_max_iter, controls$adaptive_vb_max_iter_grid)))
  grid <- sort(grid[is.finite(grid) & grid > 0L])
  if (!length(grid)) grid <- as.integer(controls$vb_max_iter)
  attempts <- list()
  al_init <- NULL
  vb_fit <- NULL
  elapsed_al <- elapsed_exal <- 0
  for (iter in grid) {
    attempt_controls <- controls
    attempt_controls$vb_max_iter <- iter
    t0 <- proc.time()[["elapsed"]]
    al_init <- app_joint_qdesn_fit_joint_al_readiness(fixture, attempt_controls)
    elapsed_al <- proc.time()[["elapsed"]] - t0
    t1 <- proc.time()[["elapsed"]]
    vb_fit <- app_joint_qdesn_fit_joint_exal_readiness(fixture, attempt_controls, init = al_init)
    elapsed_exal <- proc.time()[["elapsed"]] - t1
    attempts[[length(attempts) + 1L]] <- data.frame(
      vb_max_iter_used = iter,
      al_converged = isTRUE(al_init$converged),
      exal_converged = isTRUE(vb_fit$converged),
      al_trace_rows = nrow(al_init$trace %||% data.frame()),
      exal_trace_rows = nrow(vb_fit$trace %||% data.frame()),
      al_elapsed_seconds = elapsed_al,
      exal_elapsed_seconds = elapsed_exal,
      stringsAsFactors = FALSE
    )
    if (isTRUE(vb_fit$converged)) break
  }
  attr(vb_fit, "adaptive_vb_attempts") <- paste(vapply(attempts, function(x) x$vb_max_iter_used[[1L]], integer(1L)), collapse = ",")
  attr(vb_fit, "adaptive_vb_max_iter_used") <- tail(vapply(attempts, function(x) x$vb_max_iter_used[[1L]], integer(1L)), 1L)
  list(al_init = al_init, vb_fit = vb_fit, attempts = app_joint_qdesn_bind_rows(attempts))
}

run_one_case <- function(row, artifacts, out_dir, mcmc_controls, save_rdata) {
  case_id <- row$case_id[[1L]]
  scenario_id <- row$scenario_ids[[1L]]
  fixture <- app_joint_qdesn_scenario_fixture(artifacts, scenario_id, role = "fit")
  spec <- app_joint_qdesn_phase122_select_spec(row$model_ids[[1L]])
  if (!identical(spec$model_id[[1L]], "joint_exqdesn_rhs_vb") ||
      !identical(spec$fit_structure[[1L]], "joint") ||
      !identical(spec$likelihood[[1L]], "exal")) {
    stop(sprintf("Case '%s' is not Joint exQDESN exAL-RHS.", case_id), call. = FALSE)
  }
  controls <- app_joint_qdesn_phase122_controls_from_row(row, n_cores = 1L)
  if (!is.null(.GlobalEnv$vb_max_iter_override)) controls$vb_max_iter <- .GlobalEnv$vb_max_iter_override
  if (!is.null(.GlobalEnv$adaptive_vb_max_iter_grid_override)) {
    controls$adaptive_vb_max_iter_grid <- .GlobalEnv$adaptive_vb_max_iter_grid_override
  }
  case_meta <- app_joint_qdesn_phase122_meta(fixture, spec, row, "MCMC", app_joint_qdesn_phase122_mcmc_model_id(spec$model_id[[1L]]))
  case_meta$diagnostic_model_label <- "Joint exQDESN exAL-RHS"

  start <- proc.time()[["elapsed"]]
  retained <- fit_joint_exal_with_retained_init(fixture, controls)
  vb_elapsed <- proc.time()[["elapsed"]] - start
  mcmc_result <- app_joint_qdesn_phase122_run_mcmc_chains(
    fixture = fixture,
    spec = spec,
    vb_fit = retained$vb_fit,
    controls = controls,
    mcmc_controls = mcmc_controls,
    row = row
  )
  total_elapsed <- proc.time()[["elapsed"]] - start

  raw_path <- file.path(out_dir, "raw_objects", paste0(safe_id(case_id), ".RData"))
  if (isTRUE(save_rdata)) {
    app_ensure_dir(dirname(raw_path))
    save(row, fixture, controls, spec, retained, mcmc_result, mcmc_controls, file = raw_path, compress = "xz")
  }

  tau <- fixture$tau
  mcmc_trace <- mcmc_chain_trace_rows(
    fits = mcmc_result$fits,
    tau = tau,
    case_meta = case_meta,
    n_iter = mcmc_controls$mcmc_n_iter,
    burn = mcmc_controls$mcmc_burn,
    thin = mcmc_controls$mcmc_thin
  )
  vb_trace <- vb_exal_lambda_trace_rows(retained$vb_fit, tau, case_meta)
  al_sigma <- matrix_trace_long(retained$al_init$sigma_trace, tau, case_meta, "al_init_sigma")
  objective <- app_joint_qdesn_bind_rows(list(
    vb_objective_rows(retained$al_init, case_meta, "al_init"),
    vb_objective_rows(retained$vb_fit, case_meta, "exal_vb_ld")
  ))
  monitor <- app_joint_qdesn_bind_rows(list(
    vb_monitor_rows(retained$al_init, case_meta, "al_init"),
    vb_monitor_rows(retained$vb_fit, case_meta, "exal_vb_ld")
  ))
  rhs <- rhs_summary_rows(retained$vb_fit, case_meta)
  mcmc_summary <- mcmc_trace_summary_rows(mcmc_trace)
  rhat <- mcmc_rhat_ess_rows(mcmc_result$fits, tau, case_meta)

  figure_path <- file.path(out_dir, "figures", paste0("trace_diagnostics_", safe_id(scenario_id), ".pdf"))
  app_ensure_dir(dirname(figure_path))
  plot_case_diagnostics(case_id, scenario_id, tau, mcmc_trace, vb_trace, retained$al_init, retained$vb_fit, figure_path)

  summary <- cbind(case_meta, data.frame(
    n_train = length(fixture$y),
    p = ncol(fixture$Z),
    K = length(fixture$tau),
    tau_grid = app_joint_qdesn_format_tau(fixture$tau),
    source_candidate_id = row$candidate_id[[1L]],
    vb_converged = isTRUE(retained$vb_fit$converged),
    vb_reached_max_iter = !isTRUE(retained$vb_fit$converged),
    vb_adaptive_attempts = attr(retained$vb_fit, "adaptive_vb_attempts") %||% as.character(controls$vb_max_iter),
    vb_max_iter_used = as.integer(attr(retained$vb_fit, "adaptive_vb_max_iter_used") %||% controls$vb_max_iter),
    vb_elapsed_seconds = vb_elapsed,
    mcmc_elapsed_seconds = mcmc_result$elapsed_seconds,
    total_elapsed_seconds = total_elapsed,
    mcmc_n_chains = mcmc_controls$n_chains,
    mcmc_n_iter = mcmc_controls$mcmc_n_iter,
    mcmc_burn = mcmc_controls$mcmc_burn,
    mcmc_thin = mcmc_controls$mcmc_thin,
    mcmc_n_keep_total = nrow(mcmc_result$pooled$beta_draws),
    sigma_lower_bound = mcmc_result$sigma_bounds[[1L]],
    sigma_upper_bound = mcmc_result$sigma_bounds[[2L]],
    gamma_trace_available = !is.null(retained$vb_fit$gamma_trace) && !is.null(mcmc_result$pooled$gamma_draws),
    sigma_trace_available = !is.null(retained$vb_fit$sigma_trace) && !is.null(mcmc_result$pooled$sigma_draws),
    al_init_sigma_trace_available = !is.null(retained$al_init$sigma_trace),
    raw_rdata_path = if (isTRUE(save_rdata)) normalizePath(raw_path, mustWork = TRUE) else NA_character_,
    raw_rdata_size_bytes = if (isTRUE(save_rdata)) as.numeric(file.info(raw_path)$size) else NA_real_,
    figure_path = normalizePath(figure_path, mustWork = TRUE),
    stringsAsFactors = FALSE
  ))

  list(
    summary = summary,
    attempts = cbind(case_meta, retained$attempts, stringsAsFactors = FALSE),
    mcmc_trace = mcmc_trace,
    mcmc_trace_summary = mcmc_summary,
    mcmc_rhat_ess = rhat,
    vb_trace = vb_trace,
    al_init_sigma_trace = al_sigma,
    vb_objective = objective,
    vb_monitor = monitor,
    rhs_prior_summary = rhs,
    mcmc_draw_summary = cbind(case_meta, mcmc_result$draw_summary, stringsAsFactors = FALSE),
    vb_mcmc_distance = cbind(case_meta, mcmc_result$distance, stringsAsFactors = FALSE),
    chain_to_pooled_distance = cbind(case_meta, mcmc_result$chain_distance, stringsAsFactors = FALSE),
    runtime = cbind(case_meta, mcmc_result$runtime, stringsAsFactors = FALSE),
    rdata_path = if (isTRUE(save_rdata)) raw_path else NA_character_,
    figure_path = figure_path
  )
}

out_dir <- resolve_path(arg_value("output_dir"), must_work = FALSE)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "raw_objects"))
app_ensure_dir(file.path(out_dir, "figures"))

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
case_ids <- parse_csv(arg_value("case_ids"))
scenario_ids <- parse_csv(arg_value("scenario_ids"))
if (length(case_ids)) selected <- selected[selected$case_id %in% case_ids, , drop = FALSE]
if (length(scenario_ids)) selected <- selected[selected$scenario_ids %in% scenario_ids, , drop = FALSE]
case_limit <- parse_integer(arg_value("case_limit"), allow_empty = TRUE)
if (!is.null(case_limit)) selected <- head(selected, case_limit)
if (!nrow(selected)) stop("No Joint exQDESN exAL-RHS cases selected.", call. = FALSE)
selected <- selected[order(selected$scenario_ids), , drop = FALSE]

vb_override <- parse_integer(arg_value("vb_max_iter_override"), allow_empty = TRUE)
vb_grid_override <- parse_csv(arg_value("adaptive_vb_max_iter_grid_override"))
.GlobalEnv$vb_max_iter_override <- vb_override
.GlobalEnv$adaptive_vb_max_iter_grid_override <- if (length(vb_grid_override)) as.integer(vb_grid_override) else NULL

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
save_rdata <- parse_bool(arg_value("save_rdata"))

row_by_case <- split(selected, selected$case_id)
results <- app_joint_qdesn_parallel_lapply(
  names(row_by_case),
  function(cid) run_one_case(row_by_case[[cid]], artifacts, out_dir, mcmc_controls, save_rdata),
  mcmc_controls$n_cores
)
worker_failures <- app_joint_qdesn_worker_failure_rows(results, "phase127_joint_exqdesn_trace_diagnostics")
successful <- app_joint_qdesn_successful_worker_results(results, "phase127_joint_exqdesn_trace_diagnostics")

summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "summary"))
attempts <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "attempts"))
mcmc_trace <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "mcmc_trace"))
mcmc_trace_summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "mcmc_trace_summary"))
mcmc_rhat_ess <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "mcmc_rhat_ess"))
vb_trace <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "vb_trace"))
al_init_sigma_trace <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "al_init_sigma_trace"))
vb_objective <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "vb_objective"))
vb_monitor <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "vb_monitor"))
rhs_prior_summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "rhs_prior_summary"))
mcmc_draw_summary <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "mcmc_draw_summary"))
vb_mcmc_distance <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "vb_mcmc_distance"))
chain_to_pooled_distance <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "chain_to_pooled_distance"))
runtime <- app_joint_qdesn_bind_rows(lapply(successful, `[[`, "runtime"))

trace_assessment <- if (nrow(summary)) {
  rows <- lapply(seq_len(nrow(summary)), function(ii) {
    x <- summary[ii, , drop = FALSE]
    rh <- mcmc_rhat_ess[mcmc_rhat_ess$case_id == x$case_id[[1L]], , drop = FALSE]
    draw <- mcmc_draw_summary[mcmc_draw_summary$case_id == x$case_id[[1L]], , drop = FALSE]
    finite_traces <- isTRUE(x$gamma_trace_available[[1L]]) &&
      isTRUE(x$sigma_trace_available[[1L]]) &&
      all(is.finite(mcmc_trace$gamma[mcmc_trace$case_id == x$case_id[[1L]]]), na.rm = TRUE) &&
      all(is.finite(mcmc_trace$sigma[mcmc_trace$case_id == x$case_id[[1L]]]), na.rm = TRUE)
    finite_rhat <- rh$rhat[is.finite(rh$rhat)]
    finite_ess <- rh$rough_ess_total[is.finite(rh$rough_ess_total)]
    max_rhat <- if (length(finite_rhat)) max(finite_rhat) else NA_real_
    min_ess <- if (length(finite_ess)) min(finite_ess) else NA_real_
    sigma_bound_hit <- if (nrow(draw) && "upper_bound_hit_fraction" %in% names(draw)) {
      hits <- draw$upper_bound_hit_fraction[draw$block == "sigma"]
      hits <- hits[is.finite(hits)]
      if (length(hits)) max(hits) else NA_real_
    } else NA_real_
    hard_fail <- !finite_traces || !is.finite(x$total_elapsed_seconds[[1L]])
    review <- !hard_fail && (
      isTRUE(x$vb_reached_max_iter[[1L]]) ||
        (is.finite(max_rhat) && max_rhat > 1.2) ||
        (is.finite(min_ess) && min_ess < 100) ||
        (is.finite(sigma_bound_hit) && sigma_bound_hit > 0)
    )
    cbind(x[, c("case_id", "scenario_id", "distribution_family", "dynamics_class", "model_id", "display_label"), drop = FALSE], data.frame(
      trace_gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
      finite_gamma_sigma_traces = finite_traces,
      max_rhat = max_rhat,
      min_rough_ess_total = min_ess,
      max_sigma_upper_bound_hit_fraction = sigma_bound_hit,
      status_reason = paste(c(
        if (!finite_traces) "missing or nonfinite gamma/sigma traces",
        if (!is.finite(x$total_elapsed_seconds[[1L]])) "missing runtime",
        if (!hard_fail && isTRUE(x$vb_reached_max_iter[[1L]])) "VB-LD reached max iterations",
        if (!hard_fail && is.finite(max_rhat) && max_rhat > 1.2) "MCMC Rhat exceeds diagnostic review threshold",
        if (!hard_fail && is.finite(min_ess) && min_ess < 100) "rough ESS below diagnostic review threshold",
        if (!hard_fail && is.finite(sigma_bound_hit) && sigma_bound_hit > 0) "sigma upper bound hit"
      ), collapse = "; "),
      stringsAsFactors = FALSE
    ))
  })
  app_joint_qdesn_bind_rows(rows)
} else {
  data.frame()
}

run_config <- data.frame(
  run_id = "joint_qdesn_phase127_joint_exqdesn_exal_rhs_trace_diagnostics",
  out_dir = out_dir,
  phase122_dir = phase122_dir,
  phase124c_dir = phase124c_dir,
  fixture_dir = artifacts$fixture_dir,
  selected_cases = paste(selected$case_id, collapse = ","),
  n_cases = nrow(selected),
  model_scope = "Joint exQDESN exAL-RHS only",
  raw_rdata_saved = save_rdata,
  mcmc_n_chains = mcmc_controls$n_chains,
  mcmc_n_iter = mcmc_controls$mcmc_n_iter,
  mcmc_burn = mcmc_controls$mcmc_burn,
  mcmc_thin = mcmc_controls$mcmc_thin,
  mcmc_seed_offset = mcmc_controls$mcmc_seed_offset,
  chain_seed_stride = mcmc_controls$chain_seed_stride,
  sigma_upper_multiplier = mcmc_controls$sigma_upper_multiplier,
  n_cores = mcmc_controls$n_cores,
  vb_max_iter_override = vb_override %||% NA_integer_,
  adaptive_vb_max_iter_grid_override = if (length(vb_grid_override)) paste(vb_grid_override, collapse = ",") else NA_character_,
  validation_contract = "diagnostic_rerun_preserves_raw_mcmc_and_vb_traces",
  scalar_predictive_density_claim = FALSE,
  stringsAsFactors = FALSE
)

dashboard_path <- file.path(out_dir, "figures", "00_joint_exqdesn_trace_health_dashboard.pdf")
plot_dashboard(mcmc_trace_summary, mcmc_rhat_ess, vb_trace, dashboard_path)

readme_path <- file.path(out_dir, "README.md")
writeLines(c(
  "# Joint exQDESN exAL-RHS Trace Diagnostics",
  "",
  "This directory reruns the eight balanced Joint exQDESN exAL-RHS MCMC confirmation cases for diagnostic inspection.",
  "It preserves compressed raw `.RData` objects per case and writes long trace tables for MCMC gamma, sigma, and the induced exAL lambda, plus VB-LD gamma/sigma/lambda traces and AL-initialization sigma traces.",
  "",
  sprintf("- Phase122 source: `%s`", phase122_dir),
  sprintf("- Phase124c source: `%s`", phase124c_dir),
  sprintf("- Fixture source: `%s`", artifacts$fixture_dir),
  sprintf("- Cases: %s", nrow(selected)),
  sprintf("- MCMC chains/iter/burn/thin: %s/%s/%s/%s", mcmc_controls$n_chains, mcmc_controls$mcmc_n_iter, mcmc_controls$mcmc_burn, mcmc_controls$mcmc_thin),
  sprintf("- Raw RData saved: %s", save_rdata),
  "",
  "These artifacts are diagnostic only and do not mutate article tables. Trace gates are conservative screening diagnostics, not publication claims.",
  "",
  "Gate counts:",
  paste(capture.output(print(table(trace_assessment$trace_gate_status))), collapse = "\n")
), readme_path, useBytes = TRUE)

paths <- c(
  run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
  phase122_source_manifest_verification = app_joint_qvp_write_csv(phase122_manifest, file.path(out_dir, "phase122_source_manifest_verification.csv")),
  phase124c_source_manifest_verification = app_joint_qvp_write_csv(phase124c_manifest, file.path(out_dir, "phase124c_source_manifest_verification.csv")),
  fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
  selected_case_controls = app_joint_qvp_write_csv(selected, file.path(out_dir, "selected_case_controls.csv")),
  scenario_worker_failures = app_joint_qvp_write_csv(worker_failures, file.path(out_dir, "scenario_worker_failures.csv")),
  trace_case_summary = app_joint_qvp_write_csv(summary, file.path(out_dir, "trace_case_summary.csv")),
  vb_adaptive_attempts = app_joint_qvp_write_csv(attempts, file.path(out_dir, "vb_adaptive_attempts.csv")),
  mcmc_gamma_sigma_lambda_trace = app_joint_qvp_write_csv(mcmc_trace, file.path(out_dir, "mcmc_gamma_sigma_lambda_trace.csv")),
  mcmc_trace_summary = app_joint_qvp_write_csv(mcmc_trace_summary, file.path(out_dir, "mcmc_trace_summary.csv")),
  mcmc_rhat_ess_summary = app_joint_qvp_write_csv(mcmc_rhat_ess, file.path(out_dir, "mcmc_rhat_ess_summary.csv")),
  vb_gamma_sigma_lambda_trace = app_joint_qvp_write_csv(vb_trace, file.path(out_dir, "vb_gamma_sigma_lambda_trace.csv")),
  vb_al_init_sigma_trace = app_joint_qvp_write_csv(al_init_sigma_trace, file.path(out_dir, "vb_al_init_sigma_trace.csv")),
  vb_objective_trace = app_joint_qvp_write_csv(vb_objective, file.path(out_dir, "vb_objective_trace.csv")),
  vb_monitor_terms = app_joint_qvp_write_csv(vb_monitor, file.path(out_dir, "vb_monitor_terms.csv")),
  rhs_prior_summary = app_joint_qvp_write_csv(rhs_prior_summary, file.path(out_dir, "rhs_prior_summary.csv")),
  mcmc_draw_summary = app_joint_qvp_write_csv(mcmc_draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
  vb_mcmc_distance_summary = app_joint_qvp_write_csv(vb_mcmc_distance, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
  chain_to_pooled_distance_summary = app_joint_qvp_write_csv(chain_to_pooled_distance, file.path(out_dir, "chain_to_pooled_distance_summary.csv")),
  runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
  trace_diagnostic_assessment = app_joint_qvp_write_csv(trace_assessment, file.path(out_dir, "trace_diagnostic_assessment.csv")),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  dashboard = normalizePath(dashboard_path, mustWork = TRUE),
  readme = normalizePath(readme_path, mustWork = TRUE)
)

figure_paths <- unlist(lapply(successful, `[[`, "figure_path"), use.names = FALSE)
figure_paths <- figure_paths[file.exists(figure_paths)]
if (length(figure_paths)) {
  names(figure_paths) <- paste0("case_figure_", seq_along(figure_paths))
  paths <- c(paths, figure_paths)
}
rdata_paths <- unlist(lapply(successful, `[[`, "rdata_path"), use.names = FALSE)
rdata_paths <- rdata_paths[file.exists(rdata_paths)]
if (length(rdata_paths)) {
  names(rdata_paths) <- paste0("raw_rdata_", seq_along(rdata_paths))
  paths <- c(paths, rdata_paths)
}

manifest_info <- write_trace_manifest(paths, out_dir)

cat(sprintf("Joint exQDESN exAL-RHS trace diagnostics written to %s\n", normalizePath(out_dir, mustWork = TRUE)))
cat("Run summary:\n")
print(run_config[, c("n_cases", "mcmc_n_chains", "mcmc_n_iter", "mcmc_burn", "mcmc_thin", "n_cores", "raw_rdata_saved")], row.names = FALSE)
cat("Trace gate counts:\n")
print(table(trace_assessment$trace_gate_status))
cat(sprintf("Worker failures: %d\n", nrow(worker_failures)))
cat(sprintf("Dashboard: %s\n", normalizePath(dashboard_path, mustWork = TRUE)))
cat(sprintf("Artifact manifest: %s\n", manifest_info$manifest_path))
