# Shared diagnostics for joint exQDESN exAL MCMC trace experiments.

app_joint_exqdesn_trace_safe_id <- function(x) {
  gsub("[^A-Za-z0-9_]+", "_", as.character(x))
}

app_joint_exqdesn_trace_relative_to_dir <- function(paths, root_dir) {
  root <- normalizePath(root_dir, mustWork = TRUE)
  abs_paths <- normalizePath(paths, mustWork = TRUE)
  prefix <- paste0(root, .Platform$file.sep)
  ifelse(startsWith(abs_paths, prefix), substring(abs_paths, nchar(prefix) + 1L), basename(abs_paths))
}

app_joint_exqdesn_trace_manifest <- function(paths, out_dir, path = file.path(out_dir, "artifact_manifest.csv")) {
  labels <- names(paths)
  paths <- unname(paths)
  manifest <- data.frame(
    label = labels,
    relative_path = app_joint_exqdesn_trace_relative_to_dir(paths, out_dir),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, path)
  list(manifest = manifest, manifest_path = manifest_path)
}

app_joint_exqdesn_lambda_vector <- function(tau, gamma) {
  vapply(seq_along(tau), function(ii) {
    app_joint_qvp_exal_constants(tau[[ii]], gamma[[ii]])$lambda[[1L]]
  }, numeric(1L))
}

app_joint_exqdesn_matrix_trace_long <- function(mat, tau, meta, parameter, iteration_name = "iter") {
  if (is.null(mat)) return(data.frame())
  mat <- as.matrix(mat)
  if (!length(mat)) return(data.frame())
  rows <- lapply(seq_along(tau), function(kk) {
    out <- data.frame(
      meta,
      trace_source = parameter,
      iter = seq_len(nrow(mat)),
      quantile_index = kk,
      tau = tau[[kk]],
      value = as.numeric(mat[, kk]),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    if (!identical(iteration_name, "iter")) names(out)[names(out) == "iter"] <- iteration_name
    out
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_summary_stats <- function(x) {
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

app_joint_exqdesn_rough_ess_one_chain <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 4L || stats::sd(x) == 0) return(NA_real_)
  lag_max <- min(200L, n - 1L)
  ac <- tryCatch(stats::acf(x, lag.max = lag_max, plot = FALSE, na.action = stats::na.pass)$acf[-1L], error = function(e) numeric())
  ac <- as.numeric(ac)
  ac <- ac[is.finite(ac)]
  if (!length(ac)) return(n)
  n_pos <- match(TRUE, ac < 0, nomatch = length(ac) + 1L) - 1L
  pos <- if (n_pos > 0L) ac[seq_len(n_pos)] else numeric()
  denom <- 1 + 2 * sum(pos)
  if (!is.finite(denom) || denom <= 0) return(NA_real_)
  n / denom
}

app_joint_exqdesn_classic_rhat <- function(draw_matrix) {
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

app_joint_exqdesn_mcmc_chain_trace_rows <- function(fits, tau, meta, n_iter, burn, thin) {
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
        meta,
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

app_joint_exqdesn_mcmc_trace_summary_rows <- function(trace_rows) {
  if (!nrow(trace_rows)) return(data.frame())
  rows <- list()
  group <- interaction(
    trace_rows$case_id,
    trace_rows$experiment_id,
    trace_rows$chain_id,
    trace_rows$quantile_index,
    drop = TRUE,
    lex.order = TRUE
  )
  groups <- split(trace_rows, group)
  for (param in c("sigma", "gamma", "exal_lambda")) {
    rows <- c(rows, lapply(groups, function(block) {
      key <- block[1L, c(
        "case_id", "scenario_id", "model_id", "experiment_id", "variant_id",
        "width_multiplier", "chain_id", "chain_seed", "quantile_index", "tau"
      ), drop = FALSE]
      cbind(key, data.frame(parameter = param, stringsAsFactors = FALSE),
            app_joint_exqdesn_summary_stats(block[[param]]), stringsAsFactors = FALSE)
    }))
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_mcmc_rhat_ess_rows <- function(fits, tau, meta) {
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
      ess <- sum(vapply(seq_len(ncol(draw_matrix)), function(jj) {
        app_joint_exqdesn_rough_ess_one_chain(draw_matrix[, jj])
      }, numeric(1L)), na.rm = TRUE)
      rows[[length(rows) + 1L]] <- data.frame(
        meta,
        parameter = param,
        quantile_index = kk,
        tau = tau[[kk]],
        n_chains = ncol(draw_matrix),
        n_draws_per_chain = nrow(draw_matrix),
        rhat = app_joint_exqdesn_classic_rhat(draw_matrix),
        rough_ess_total = ess,
        stringsAsFactors = FALSE
      )
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_chain_mean_gap_rows <- function(trace_rows) {
  if (!nrow(trace_rows)) return(data.frame())
  rows <- list()
  groups <- split(trace_rows, interaction(trace_rows$case_id, trace_rows$experiment_id, trace_rows$quantile_index, drop = TRUE, lex.order = TRUE))
  for (param in c("sigma", "gamma", "exal_lambda")) {
    rows <- c(rows, lapply(groups, function(block) {
      means <- stats::aggregate(block[[param]], list(chain_id = block$chain_id), mean, na.rm = TRUE)
      finite <- means$x[is.finite(means$x)]
      gap <- if (length(finite)) max(finite) - min(finite) else NA_real_
      key <- block[1L, c(
        "case_id", "scenario_id", "model_id", "experiment_id", "variant_id",
        "width_multiplier", "quantile_index", "tau"
      ), drop = FALSE]
      cbind(key, data.frame(
        parameter = param,
        n_chains = length(finite),
        chain_mean_gap = gap,
        chain_mean_sd = if (length(finite) > 1L) stats::sd(finite) else NA_real_,
        chain_mean_min = if (length(finite)) min(finite) else NA_real_,
        chain_mean_max = if (length(finite)) max(finite) else NA_real_,
        stringsAsFactors = FALSE
      ))
    }))
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_autocorrelation_rows <- function(trace_rows, lags = c(1L, 5L, 10L, 25L, 50L)) {
  if (!nrow(trace_rows)) return(data.frame())
  rows <- list()
  groups <- split(trace_rows, interaction(trace_rows$case_id, trace_rows$experiment_id, trace_rows$chain_id, trace_rows$quantile_index, drop = TRUE, lex.order = TRUE))
  for (param in c("sigma", "gamma", "exal_lambda")) {
    rows <- c(rows, lapply(groups, function(block) {
      x <- as.numeric(block[[param]])
      out <- lapply(as.integer(lags), function(lag) {
        ac <- if (sum(is.finite(x)) > lag + 2L && stats::sd(x, na.rm = TRUE) > 0) {
          suppressWarnings(stats::acf(x, lag.max = lag, plot = FALSE, na.action = stats::na.pass)$acf[lag + 1L])
        } else {
          NA_real_
        }
        cbind(block[1L, c(
          "case_id", "scenario_id", "model_id", "experiment_id", "variant_id",
          "width_multiplier", "chain_id", "chain_seed", "quantile_index", "tau"
        ), drop = FALSE], data.frame(parameter = param, lag = lag, autocorrelation = as.numeric(ac), stringsAsFactors = FALSE))
      })
      app_joint_qdesn_bind_rows(out)
    }))
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_vb_trace_rows <- function(vb_fit, tau, meta) {
  if (is.null(vb_fit$gamma_trace)) return(data.frame())
  gamma_trace <- as.matrix(vb_fit$gamma_trace)
  rows <- lapply(seq_len(nrow(gamma_trace)), function(ii) {
    lambda <- app_joint_exqdesn_lambda_vector(tau, as.numeric(gamma_trace[ii, ]))
    data.frame(
      meta,
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

app_joint_exqdesn_vb_objective_rows <- function(fit, meta, phase) {
  trace <- fit$trace %||% data.frame()
  if (!nrow(trace)) return(data.frame())
  cbind(meta, data.frame(vb_phase = phase, stringsAsFactors = FALSE), trace, stringsAsFactors = FALSE)
}

app_joint_exqdesn_vb_monitor_rows <- function(fit, meta, phase) {
  monitor <- fit$monitor_terms %||% data.frame()
  if (!nrow(monitor)) return(data.frame())
  cbind(meta, data.frame(vb_phase = phase, stringsAsFactors = FALSE), monitor, stringsAsFactors = FALSE)
}

app_joint_exqdesn_rhs_summary_rows <- function(vb_fit, meta) {
  rhs <- vb_fit$rhs_prior_summary %||% data.frame()
  if (!nrow(rhs)) return(data.frame())
  cbind(meta, rhs, stringsAsFactors = FALSE)
}

app_joint_exqdesn_fit_with_retained_init <- function(fixture, controls) {
  grid <- unique(as.integer(c(controls$vb_max_iter, controls$adaptive_vb_max_iter_grid)))
  grid <- sort(grid[is.finite(grid) & grid > 0L])
  if (!length(grid)) grid <- as.integer(controls$vb_max_iter)
  attempts <- list()
  al_init <- NULL
  vb_fit <- NULL
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

app_joint_exqdesn_gamma_chain_init <- function(vb_fit, tau, chain_id, n_chains, mode = "vb_jittered", jitter_fraction = 0.10) {
  init <- vb_fit
  if (is.null(init$gamma_mean)) return(init)
  mode <- as.character(mode)[[1L]]
  support <- app_joint_qvp_exal_support(tau)
  lower <- as.numeric(support$lower) + 1.0e-7
  upper <- as.numeric(support$upper) - 1.0e-7
  base <- as.numeric(init$gamma_mean)
  if (identical(mode, "vb")) {
    gamma <- base
  } else if (identical(mode, "vb_jittered")) {
    centered <- if (n_chains <= 1L) 0 else ((chain_id - 1L) / (n_chains - 1L) - 0.5)
    width <- upper - lower
    gamma <- base + centered * 2 * jitter_fraction * width
  } else if (identical(mode, "support_grid")) {
    frac <- if (n_chains <= 1L) 0.5 else chain_id / (n_chains + 1L)
    gamma <- lower + frac * (upper - lower)
  } else {
    stop(sprintf("Unknown gamma_init_mode '%s'.", mode), call. = FALSE)
  }
  gamma <- pmin(pmax(gamma, lower), upper)
  init$gamma_mean <- gamma
  init$gamma <- gamma
  init
}

app_joint_exqdesn_plot_trace_panel <- function(x, y, group, main, ylab) {
  if (!length(y) || all(!is.finite(y))) {
    plot.new(); title(main); text(0.5, 0.5, "No finite trace values")
    return(invisible(NULL))
  }
  plot(x, y, type = "n", main = main, xlab = "draw", ylab = ylab)
  groups <- unique(group)
  cols <- grDevices::hcl.colors(max(3L, length(groups)), palette = "Dark 3")
  for (ii in seq_along(groups)) {
    idx <- group == groups[[ii]]
    lines(x[idx], y[idx], col = cols[[ii]], lwd = 0.8)
  }
  legend("topright", legend = groups, col = cols[seq_along(groups)], lty = 1, cex = 0.55, bty = "n")
  invisible(NULL)
}

app_joint_exqdesn_plot_variant_diagnostics <- function(variant_id, trace_rows, vb_trace, out_path) {
  block <- trace_rows[trace_rows$variant_id == variant_id, , drop = FALSE]
  vb_block <- vb_trace
  grDevices::pdf(out_path, width = 12, height = 9)
  on.exit(grDevices::dev.off(), add = TRUE)
  par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
  group <- paste0("tau=", format(block$tau, trim = TRUE), " c", block$chain_id)
  app_joint_exqdesn_plot_trace_panel(block$draw_index, block$gamma, group, sprintf("%s: MCMC gamma", variant_id), "gamma")
  app_joint_exqdesn_plot_trace_panel(block$draw_index, block$sigma, group, sprintf("%s: MCMC sigma", variant_id), "sigma")
  app_joint_exqdesn_plot_trace_panel(block$draw_index, block$exal_lambda, group, sprintf("%s: MCMC exAL lambda", variant_id), "lambda")
  vb_group <- paste0("tau=", format(vb_block$tau, trim = TRUE))
  app_joint_exqdesn_plot_trace_panel(vb_block$iter, vb_block$gamma, vb_group, "VB-LD gamma", "gamma")
  par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
  app_joint_exqdesn_plot_trace_panel(vb_block$iter, vb_block$sigma, vb_group, "VB-LD sigma", "sigma")
  app_joint_exqdesn_plot_trace_panel(vb_block$iter, vb_block$exal_lambda, vb_group, "VB-LD exAL lambda", "lambda")
  plot(stats::density(block$gamma[is.finite(block$gamma)]), main = sprintf("%s: pooled gamma density", variant_id), xlab = "gamma")
  plot(stats::density(block$sigma[is.finite(block$sigma)]), main = sprintf("%s: pooled sigma density", variant_id), xlab = "sigma")
}

app_joint_exqdesn_plot_phase128_dashboard <- function(assessment, rhat, gap, out_path) {
  grDevices::pdf(out_path, width = 12, height = 9)
  on.exit(grDevices::dev.off(), add = TRUE)
  par(mfrow = c(2, 2), mar = c(6, 4, 3, 1))
  if (nrow(assessment)) {
    plot(assessment$width_multiplier, assessment$max_rhat, type = "b", log = "x",
         main = "Worst Rhat by slice-width multiplier", xlab = "width multiplier", ylab = "max Rhat")
    abline(h = 1.2, col = "red", lty = 2)
    plot(assessment$width_multiplier, assessment$min_rough_ess_total, type = "b", log = "x",
         main = "Worst rough ESS by width multiplier", xlab = "width multiplier", ylab = "min ESS")
    abline(h = 100, col = "red", lty = 2)
  } else {
    plot.new(); title("Assessment unavailable")
    plot.new(); title("Assessment unavailable")
  }
  if (nrow(rhat)) {
    boxplot(rhat ~ interaction(parameter, width_multiplier), data = rhat,
            main = "Rhat by parameter and width", ylab = "Rhat", las = 2)
  } else {
    plot.new(); title("Rhat unavailable")
  }
  if (nrow(gap)) {
    boxplot(chain_mean_gap ~ interaction(parameter, width_multiplier), data = gap,
            main = "Chain mean gaps by parameter and width", ylab = "gap", las = 2)
  } else {
    plot.new(); title("Chain gaps unavailable")
  }
}
