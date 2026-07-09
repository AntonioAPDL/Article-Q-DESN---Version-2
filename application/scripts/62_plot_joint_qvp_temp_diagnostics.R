#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
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
source(app_path("application/R/joint_qvp_qdesn.R"))

out_dir <- if (length(args) >= 1L && nzchar(args[[1L]])) {
  args[[1L]]
} else {
  app_path("application/cache/joint_qvp_temp_diagnostics_20260701")
}
out_dir <- normalizePath(out_dir, mustWork = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

app_joint_qvp_plot_colors <- function(K) {
  rep(c("#0072B2", "#D55E00", "#009E73", "#CC79A7", "#56B4E9"), length.out = K)
}

app_joint_qvp_plot_elbo_trace <- function(vb_fit, path, title) {
  grDevices::png(path, width = 1200, height = 900, res = 140, type = "cairo")
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(2, 1), mar = c(4, 4, 3, 1))
  graphics::plot(
    vb_fit$trace$iter,
    vb_fit$trace$partial_elbo,
    type = "l",
    lwd = 2,
    col = "#0072B2",
    xlab = "VB iteration",
    ylab = "Accounted partial ELBO",
    main = paste(title, "ELBO trace")
  )
  graphics::grid(col = "grey85")
  graphics::plot(
    vb_fit$trace$iter,
    pmax(vb_fit$trace$max_beta_change, .Machine$double.eps),
    type = "l",
    lwd = 2,
    log = "y",
    col = "#D55E00",
    xlab = "VB iteration",
    ylab = "max beta change (log scale)",
    main = "Coordinate-change diagnostic"
  )
  graphics::abline(h = 1.0e-4, lty = 2, col = "grey40")
  graphics::grid(col = "grey85")
  invisible(path)
}

app_joint_qvp_plot_parameter_traces <- function(mcmc_fits, tau, path, title) {
  K <- length(tau)
  cols <- app_joint_qvp_plot_colors(K)
  grDevices::png(path, width = 1300, height = 1100, res = 140, type = "cairo")
  on.exit(grDevices::dev.off(), add = TRUE)
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE)
  graphics::par(mfrow = c(3, 1), mar = c(4, 4, 3, 1))
  draw_x <- seq_len(nrow(mcmc_fits[[1L]]$sigma_draws))
  y_range <- range(unlist(lapply(mcmc_fits, `[[`, "sigma_draws")), finite = TRUE)
  graphics::plot(draw_x, mcmc_fits[[1L]]$sigma_draws[, 1L], type = "n",
    ylim = y_range, xlab = "Kept MCMC draw", ylab = "sigma",
    main = paste(title, "MCMC sigma traces"))
  for (chain_id in seq_along(mcmc_fits)) {
    for (k in seq_len(K)) {
      graphics::lines(draw_x, mcmc_fits[[chain_id]]$sigma_draws[, k],
        col = cols[[k]], lty = chain_id, lwd = 1.5)
    }
  }
  graphics::grid(col = "grey85")
  graphics::legend("topright", legend = paste0("tau=", tau), col = cols, lty = 1, bty = "n", cex = 0.85)

  y_range <- range(unlist(lapply(mcmc_fits, `[[`, "alpha_draws")), finite = TRUE)
  graphics::plot(draw_x, mcmc_fits[[1L]]$alpha_draws[, 1L], type = "n",
    ylim = y_range, xlab = "Kept MCMC draw", ylab = "alpha",
    main = "MCMC ordered-intercept traces")
  for (chain_id in seq_along(mcmc_fits)) {
    for (k in seq_len(K)) {
      graphics::lines(draw_x, mcmc_fits[[chain_id]]$alpha_draws[, k],
        col = cols[[k]], lty = chain_id, lwd = 1.5)
    }
  }
  graphics::grid(col = "grey85")

  beta_norms <- lapply(mcmc_fits, function(fit) sqrt(rowSums(fit$beta_draws^2)))
  y_range <- range(unlist(beta_norms), finite = TRUE)
  graphics::plot(draw_x, beta_norms[[1L]], type = "n",
    ylim = y_range, xlab = "Kept MCMC draw", ylab = "||beta||2",
    main = "MCMC readout-norm traces")
  for (chain_id in seq_along(beta_norms)) {
    graphics::lines(draw_x, beta_norms[[chain_id]], col = "#009E73", lty = chain_id, lwd = 1.5)
  }
  graphics::grid(col = "grey85")
  invisible(path)
}

app_joint_qvp_plot_fit_overlay <- function(fixture, vb_fit, pooled_mcmc, path, title) {
  app_joint_qvp_plot_ts_fit_overlay(fixture, vb_fit, pooled_mcmc, path, title)
}

scenarios <- app_joint_qvp_default_objective_stress_scenarios()
scenarios <- scenarios[scenarios$stress_case %in% c("wide_tau_parallel", "strong_shrinkage"), , drop = FALSE]
get_cell <- function(sc, name, default) {
  if (!name %in% names(sc) || is.na(sc[[name]][[1L]])) return(default)
  sc[[name]][[1L]]
}

figure_rows <- list()
summary_rows <- list()
for (ii in seq_len(nrow(scenarios))) {
  sc <- scenarios[ii, , drop = FALSE]
  tau <- app_joint_qvp_parse_tau_spec(sc$tau[[1L]])
  case_id <- sprintf("%s_seed%s_K%s", sc$stress_case[[1L]], sc$seed[[1L]], length(tau))
  fixture <- app_joint_qvp_simulate_synthetic(
    Tn = sc$Tn[[1L]],
    p = sc$p[[1L]],
    tau = tau,
    scenario = sc$scenario[[1L]],
    seed = sc$seed[[1L]],
    noise_sd = sc$noise_sd[[1L]]
  )
  vb_fit <- app_joint_qvp_fit_al_vb_tiny(
    y = fixture$y,
    Z = fixture$Z,
    tau = fixture$tau,
    max_iter = sc$max_iter[[1L]],
    tol = 1.0e-4,
    kappa = sc$kappa[[1L]],
    tau0 = sc$tau0[[1L]],
    a_sigma = 2,
    b_sigma = 1,
    alpha_prior_mean = "empirical_quantile",
    alpha_prior_sd = 1,
    rhs_vb_inner = sc$rhs_vb_inner[[1L]]
  )
  sigma_upper_bound <- max(1, 50 * max(vb_fit$sigma_mean))
  n_chains <- 2L
  mcmc_fits <- vector("list", n_chains)
  for (chain_id in seq_len(n_chains)) {
    mcmc_fits[[chain_id]] <- app_joint_qvp_fit_al_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = 120L,
      burn = 60L,
      thin = 5L,
      seed = sc$seed[[1L]] + 1000L + (chain_id - 1L) * 10000L,
      kappa = sc$kappa[[1L]],
      tau0 = sc$tau0[[1L]],
      a_sigma = 2,
      b_sigma = 1,
      alpha_prior_mean = "empirical_quantile",
      alpha_prior_sd = 1,
      init = vb_fit,
      max_dense_dim = 50L,
      sigma_bounds = c(1.0e-8, sigma_upper_bound)
    )
  }
  pooled <- app_joint_qvp_pool_mcmc_chains(mcmc_fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau)
  distance <- app_joint_qvp_vb_mcmc_distance_summary(
    vb_fit = vb_fit,
    mcmc_fit = pooled,
    case_id = case_id,
    stress_case = sc$stress_case[[1L]],
    scenario = sc$scenario[[1L]],
    Tn = sc$Tn[[1L]],
    p = sc$p[[1L]],
    K = length(fixture$tau)
  )
  title <- paste0(sc$stress_case[[1L]], " (K=", length(fixture$tau), ")")
  paths <- c(
    elbo_trace = file.path(out_dir, paste0(case_id, "_elbo_trace.png")),
    parameter_traces = file.path(out_dir, paste0(case_id, "_parameter_traces.png")),
    fit_overlay = file.path(out_dir, paste0(case_id, "_fit_overlay.png"))
  )
  app_joint_qvp_plot_elbo_trace(vb_fit, paths[["elbo_trace"]], title)
  app_joint_qvp_plot_parameter_traces(mcmc_fits, fixture$tau, paths[["parameter_traces"]], title)
  app_joint_qvp_plot_fit_overlay(fixture, vb_fit, pooled, paths[["fit_overlay"]], title)
  for (label in names(paths)) {
    figure_rows[[length(figure_rows) + 1L]] <- data.frame(
      case_id = case_id,
      stress_case = sc$stress_case[[1L]],
      figure_label = label,
      relative_path = basename(paths[[label]]),
      size_bytes = as.numeric(file.info(paths[[label]])$size),
      sha256 = app_sha256_file(paths[[label]]),
      stringsAsFactors = FALSE
    )
  }
  summary_rows[[length(summary_rows) + 1L]] <- data.frame(
    case_id = case_id,
    stress_case = sc$stress_case[[1L]],
    scenario = sc$scenario[[1L]],
    K = length(fixture$tau),
    alpha_prior_mean = "empirical_quantile",
    alpha_prior_sd = 1,
    vb_converged = isTRUE(vb_fit$converged),
    vb_n_iter = nrow(vb_fit$trace),
    final_partial_elbo = tail(vb_fit$trace$partial_elbo, 1L),
    objective_status = vb_fit$objective_diagnostics$objective_status[[1L]],
    n_chains = n_chains,
    mcmc_n_keep_total = nrow(pooled$beta_draws),
    pooled_max_normalized_distance = distance$max_normalized_distance[[1L]],
    total_vb_crossing_pairs = sum(vb_fit$crossing_diagnostics$n_crossing_pairs),
    total_pooled_mcmc_crossing_pairs = sum(pooled$crossing_diagnostics$n_crossing_pairs),
    sigma_upper_bound = sigma_upper_bound,
    stringsAsFactors = FALSE
  )
}

figure_manifest <- do.call(rbind, figure_rows)
summary <- do.call(rbind, summary_rows)
manifest_path <- app_joint_qvp_write_csv(figure_manifest, file.path(out_dir, "figure_manifest.csv"))
summary_path <- app_joint_qvp_write_csv(summary, file.path(out_dir, "diagnostic_summary.csv"))

cat(sprintf("Joint-QVP temporary diagnostic figures written to %s\n", out_dir))
cat(sprintf("Figure manifest: %s\n", manifest_path))
cat(sprintf("Diagnostic summary: %s\n", summary_path))
