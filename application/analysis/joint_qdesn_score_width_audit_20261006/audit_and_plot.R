# Read-only post-processing of the closed prior experiment; no sampler calls.

joint_width_decompose <- function(loss, chain_id) {
  loss <- as.matrix(loss)
  stopifnot(nrow(loss) == length(chain_id), all(is.finite(loss)))
  score <- rowSums(loss)
  covariance <- stats::cov(loss)
  total <- stats::var(score)
  marginal <- sum(diag(covariance))
  within_ss <- between_ss <- 0
  for (index in split(seq_along(score), chain_id)) {
    within_ss <- within_ss + sum((score[index] - mean(score[index]))^2)
    between_ss <- between_ss + length(index) * (mean(score[index]) - mean(score))^2
  }
  within <- within_ss / (length(score) - 1)
  between <- between_ss / (length(score) - 1)
  stopifnot(abs(total - sum(covariance)) < 1e-10 * (1 + total),
    abs(total - within - between) < 1e-10 * (1 + total))
  list(summary = data.frame(total_variance = total, marginal_variance = marginal,
    covariance_contribution = total - marginal,
    covariance_fraction = (total - marginal) / total,
    between_chain_variance_fraction = between / total,
    within_chain_variance_fraction = within / total,
    covariance_sd_multiplier = sqrt(total / marginal)), covariance = covariance)
}

joint_width_reconstruct <- function(Z, beta, alpha, oracle, tau, weights,
    forecast_map, chunk_size = 1500L) {
  n <- nrow(beta); H <- nrow(Z); p <- ncol(Z); K <- length(tau)
  stopifnot(ncol(beta) == p * K, nrow(alpha) == n, ncol(alpha) == K,
    nrow(forecast_map) == H)
  loss <- raw_loss <- matrix(NA_real_, n, K)
  lead <- matrix(0, n, max(forecast_map$horizon))
  first <- which(forecast_map$origin_index == min(forecast_map$origin_index))
  origin_q <- array(NA_real_, dim = c(length(first), n, K))
  for (index in split(seq_len(n), ceiling(seq_len(n) / chunk_size))) {
    B <- length(index)
    raw <- matrix(NA_real_, H * B, K)
    for (k in seq_len(K)) {
      columns <- ((k - 1L) * p + 1L):(k * p)
      raw[, k] <- as.vector(sweep(Z %*% t(beta[index, columns, drop = FALSE]),
        2L, alpha[index, k], "+"))
    }
    contracted <- app_joint_recursive_contract_draw_rows(raw, tau)
    for (k in seq_len(K)) {
      q <- matrix(contracted$q_contract[, k], H, B)
      expected <- app_joint_recursive_oracle_expected_matrix(oracle, q, tau[k])
      loss[index, k] <- 2 * weights[k] * colMeans(expected)
      for (h in seq_len(ncol(lead))) {
        rows <- which(forecast_map$horizon == h)
        lead[index, h] <- lead[index, h] + 2 * weights[k] *
          colMeans(expected[rows, , drop = FALSE])
      }
      if (!length(contracted$adjusted_rows)) {
        raw_loss[index, k] <- loss[index, k]
      } else {
        raw_q <- matrix(raw[, k], H, B)
        raw_loss[index, k] <- 2 * weights[k] * colMeans(
          app_joint_recursive_oracle_expected_matrix(oracle, raw_q, tau[k]))
      }
      origin_q[, index, k] <- q[first, , drop = FALSE]
    }
  }
  list(loss = loss, raw_loss = raw_loss, lead = lead, origin_q = origin_q,
    first_origin_rows = first)
}

joint_width_projection <- function(Zfit, Zforecast, Zcommon, beta, alpha, tau) {
  Xfit <- cbind(1, Zfit); Xforecast <- cbind(1, Zforecast)
  Xcommon <- cbind(1, Zcommon)
  p <- ncol(Zfit)
  sv <- svd(Xfit, nu = 0L)
  weak <- which(sv$d / max(sv$d) < 0.01)
  Vweak <- sv$v[, weak, drop = FALSE]
  qvar <- function(X, covariance) pmax(rowSums((X %*% covariance) * X), 0)
  do.call(rbind, lapply(seq_along(tau), function(k) {
    columns <- ((k - 1L) * p + 1L):(k * p)
    coefficients <- cbind(alpha[, k], beta[, columns, drop = FALSE])
    covariance <- stats::cov(coefficients)
    vf <- qvar(Xfit, covariance); vp <- qvar(Xforecast, covariance)
    vc <- qvar(Xcommon, covariance)
    weak_fit <- weak_forecast <- 0
    if (length(weak)) {
      cw <- crossprod(Vweak, covariance %*% Vweak)
      weak_fit <- mean(qvar(Xfit %*% Vweak, cw))
      weak_forecast <- mean(qvar(Xforecast %*% Vweak, cw))
    }
    shifted <- as.vector(beta[, columns, drop = FALSE] %*% colMeans(Zfit))
    data.frame(tau = tau[k], fit_quantile_variance = mean(vf),
      forecast_quantile_variance = mean(vp), common_design_quantile_variance = mean(vc),
      forecast_fit_variance_ratio = mean(vp) / mean(vf),
      native_common_variance_ratio = mean(vp) / mean(vc),
      weak_design_dimensions = length(weak),
      weak_direction_fit_variance = weak_fit,
      weak_direction_forecast_variance = weak_forecast,
      fit_condition_number = max(sv$d) / min(sv$d),
      intercept_fit_offset_correlation = if (stats::sd(shifted) > 1e-10)
        stats::cor(alpha[, k], shifted) else NA_real_)
  }))
}

joint_width_loss_chain_rows <- function(loss, chain_id) {
  score <- rowSums(loss)
  result <- lapply(sort(unique(chain_id)), function(id) {
    summarize <- function(values, group) {
      qs <- stats::quantile(values, c(.025, .975), type = 8, names = FALSE)
      data.frame(chain = id, allocation = group, score_mean = mean(values),
        q025 = qs[1L], q975 = qs[2L], width = diff(qs))
    }
    rows <- which(chain_id == id)
    rbind(summarize(score[rows], "single_chain"),
      summarize(score[-rows], "leave_one_chain_out"),
      summarize(score[rows[seq_len(floor(length(rows) / 2))]], "first_half"),
      summarize(score[rows[-seq_len(floor(length(rows) / 2))]], "second_half"))
  })
  do.call(rbind, result)
}

joint_width_plot <- function(output) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("ggplot2 required.")
  g <- asNamespace("ggplot2")
  colors <- c("Joint AL" = "#007C83", "Independent AL" = "#4769B1",
    "Joint exAL" = "#B23A68", "Independent exAL" = "#70822F")
  theme <- g$theme_minimal(base_size = 12) + g$theme(
    panel.grid.minor = g$element_blank(), panel.grid.major.x = g$element_blank(),
    plot.title = g$element_text(face = "bold", size = 19),
    plot.subtitle = g$element_text(size = 11, color = "#4B5563"),
    strip.text = g$element_text(face = "bold", size = 11),
    legend.position = "bottom", plot.margin = g$margin(15, 20, 15, 15))
  caption <- "Frozen fresh-seed confirmation; no refitting or article promotion. Intervals are posterior 95% credible intervals, not MCSE."
  cells <- app_read_csv(file.path(output, "cell_audit.csv"))
  cells$model <- ifelse(cells$structure == "joint", "Joint", "Independent")
  cells$model <- paste(cells$model, cells$likelihood)
  cells$role <- ifelse(cells$arm_id == "prior_08", "Baseline", "Prior challenger")
  cells$replicate <- paste("Matched replicate", cells$replicate_id)
  c <- cells[cells$scenario_id == "laplace_bridge", ]
  c$display <- paste(c$model, ifelse(c$role == "Baseline", "baseline", "challenger"))
  c$display <- factor(c$display, levels = rev(c("Joint AL baseline", "Joint AL challenger",
    "Independent AL baseline", "Joint exAL baseline", "Joint exAL challenger",
    "Independent exAL baseline")))
  pages <- list()
  pages[[1L]] <- g$ggplot(c, g$aes(x = posterior_score_mean, y = display, color = model)) +
    g$geom_segment(g$aes(x = posterior_score_q025, xend = posterior_score_q975,
      yend = display), linewidth = 1.1) +
    g$geom_point(g$aes(shape = role), size = 3.2) +
    g$geom_point(g$aes(x = canonical_origin_marginal_dgp_integrated_acrps),
      shape = 4, size = 2.8, stroke = 1) +
    g$facet_wrap(~replicate, nrow = 1) + g$scale_color_manual(values = colors) +
    g$scale_shape_manual(values = c(Baseline = 16, "Prior challenger" = 1)) +
    g$labs(title = "Laplace Bridge | forecast score comparison",
      subtitle = "Dot: posterior mean; line: 95% interval; cross: score of the reported mean quantile action. C-AL challenger is rejected.",
      x = "DGP-integrated finite-grid forecast score (lower is better)", y = NULL,
      color = NULL, shape = NULL, caption = caption) + theme
  leads <- app_read_csv(file.path(output, "lead_score_bands.csv"))
  leads$model <- paste(ifelse(leads$structure == "joint", "Joint", "Independent"), leads$likelihood)
  leads$replicate <- paste("Matched replicate", leads$replicate_id)
  lp <- leads[leads$scenario_id == "laplace_bridge" & leads$arm_id == "prior_08", ]
  lp$model <- factor(lp$model, levels = names(colors))
  pages[[2L]] <- g$ggplot(lp, g$aes(horizon, score_mean, color = model, fill = model)) +
    g$geom_ribbon(g$aes(ymin = q025, ymax = q975), alpha = .16, color = NA) +
    g$geom_line(linewidth = .9) + g$facet_grid(replicate ~ model) +
    g$scale_color_manual(values = colors) + g$scale_fill_manual(values = colors) +
    g$labs(title = "Laplace Bridge | score versus forecast lead",
      subtitle = "Each lead averages the same 33 origins. Four baseline models use the same DESN and protected realization.",
      x = "Recursive forecast lead", y = "DGP-integrated forecast score",
      color = NULL, fill = NULL, caption = caption) + theme +
    g$theme(legend.position = "none")
  bands <- app_read_csv(file.path(output, "first_origin_quantile_bands.csv"))
  bands$model <- paste(ifelse(bands$structure == "joint", "Joint", "Independent"), bands$likelihood)
  bands$model <- factor(bands$model, levels = names(colors))
  bands$tau_label <- factor(paste0(round(100 * bands$tau), "% quantile"),
    levels = paste0(c(5, 10, 25, 50, 75, 90, 95), "% quantile"))
  for (replicate in 1:2) {
    b <- bands[bands$scenario_id == "laplace_bridge" & bands$replicate_id == replicate &
      bands$arm_id == "prior_08", ]
    pages[[length(pages) + 1L]] <- g$ggplot(b, g$aes(horizon, posterior_mean, color = model, fill = model)) +
      g$geom_ribbon(g$aes(ymin = q025, ymax = q975), alpha = .18, color = NA) +
      g$geom_line(linewidth = .7) + g$geom_line(g$aes(y = true_quantile),
        color = "#252525", linetype = "dashed", linewidth = .7) +
      g$geom_point(g$aes(y = observed_y), color = "#7A7A7A", alpha = .4, size = .8) +
      g$facet_grid(tau_label ~ model, scales = "free_y") +
      g$scale_color_manual(values = colors) + g$scale_fill_manual(values = colors) +
      g$labs(title = paste("Laplace Bridge | quantile forecasts | replicate", replicate),
        subtitle = "First predeclared origin. Colored curve/band: posterior forecast quantile; dashed: DGP origin-marginal quantile; dots: observations.",
        x = "Recursive forecast lead", y = "Response", color = NULL, fill = NULL,
        caption = "Common scales across models within each quantile row. Bands describe quantile uncertainty, not predictive intervals for observations.") +
      theme + g$theme(legend.position = "none", strip.text.y = g$element_text(size = 9))
  }
  variance <- rbind(data.frame(c, part = "Within-level variance", value = c$marginal_variance),
    data.frame(c, part = "Cross-level covariance", value = c$covariance_contribution))
  pages[[length(pages) + 1L]] <- g$ggplot(variance, g$aes(display, value, fill = part)) +
    g$geom_col(width = .65) + g$facet_wrap(~replicate, nrow = 1) +
    g$coord_flip() + g$scale_fill_manual(values = c("Within-level variance" = "#4769B1",
      "Cross-level covariance" = "#B23A68")) +
    g$labs(title = "Laplace Bridge | where score variance comes from",
      subtitle = "Exact empirical identity: variance of the weighted sum = marginal variances + all cross-level covariance terms.",
      x = NULL, y = "Posterior score variance", fill = NULL,
      caption = "Native posterior dependence is preserved. No joint draws are shuffled to manufacture narrower intervals.") + theme
  covariance <- app_read_csv(file.path(output, "loss_correlation.csv"))
  covariance$model <- paste(ifelse(covariance$structure == "joint", "Joint", "Independent"), covariance$likelihood)
  covariance$model <- factor(covariance$model, levels = names(colors))
  covariance$replicate <- paste("Matched replicate", covariance$replicate_id)
  cov <- covariance[covariance$scenario_id == "laplace_bridge" & covariance$arm_id == "prior_08", ]
  pages[[length(pages) + 1L]] <- g$ggplot(cov, g$aes(factor(tau_x), factor(tau_y), fill = correlation)) +
    g$geom_tile() + g$facet_grid(replicate ~ model) +
    g$scale_fill_gradient2(low = "#4769B1", mid = "white", high = "#B23A68", limits = c(-1, 1)) +
    g$coord_equal() + g$labs(title = "Laplace Bridge | quantile-loss dependence",
      subtitle = "Correlations of DGP-integrated loss contributions after the reporting contract, using the native posterior.",
      x = "Quantile level", y = "Quantile level", fill = "Correlation") + theme +
    g$theme(axis.text.x = g$element_text(angle = 45, hjust = 1))
  grDevices::cairo_pdf(file.path(output, "laplace_forecast_and_uncertainty_audit.pdf"), width = 14, height = 11)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (plot in pages) print(plot)
  grDevices::dev.off(); on.exit(NULL)
  g$ggsave(file.path(output, "laplace_forecast_score_comparison.png"), pages[[1L]],
    width = 14, height = 7, dpi = 160, bg = "white")
  g$ggsave(file.path(output, "laplace_quantile_forecast_replicate1.png"), pages[[3L]],
    width = 14, height = 13, dpi = 140, bg = "white")
  invisible(pages)
}

joint_width_main <- function(source_root, output) {
  if (dir.exists(output)) stop("Use a new output directory; no audit overwrite.")
  source_root <- normalizePath(source_root)
  stopifnot(file.exists(file.path(source_root, "COMPLETE")))
  app_joint_prior_verify_freeze(source_root); app_joint_prior_verify_selection(source_root)
  stopifnot(app_joint_prior_done(file.path(source_root, "closeout")))
  ct <- readRDS(file.path(source_root, "contract.rds"))
  cells <- app_joint_prior_collect(source_root, "confirmation")
  plan <- app_read_csv(file.path(source_root, "confirmation/chains.csv"))
  app_ensure_dir(output)
  inputs <- file.path(source_root, c("contract.rds", "source_head.txt",
    "source_manifest.csv", "confirmation/chains.csv", "closeout/artifact_manifest.csv"))
  all_cells <- all_losses <- all_chain <- all_projection <- all_cor <- all_leads <- all_bands <- list()
  for (dataset in unique(cells$dataset_id)) {
    context <- app_joint_prior_context(source_root, "confirmation", dataset)
    inputs <- c(inputs, file.path(source_root, "confirmation/datasets",
      sprintf("dataset_%02d", dataset), c("context.rds", "oracle.rds", "artifact_manifest.csv")))
    oracle <- readRDS(file.path(source_root, "confirmation/datasets", sprintf("dataset_%02d", dataset), "oracle.rds"))
    subset <- cells[cells$dataset_id == dataset, ]
    reference <- subset$cell_id[subset$structure == "independent" & subset$likelihood == "AL"]
    common <- readRDS(file.path(source_root, "confirmation/scores", sprintf("cell_%04d", reference), "mean_design.rds"))$mean_design
    for (j in seq_len(nrow(subset))) {
      cell <- subset[j, ]; id <- cell$cell_id
      jobs <- plan[plan$cell_id == id, ]; jobs <- jobs[order(jobs$chain_id), ]
      inputs <- c(inputs, file.path(source_root, "confirmation/chains",
        sprintf("worker_%04d", jobs$worker_id), "posterior_draws.csv.gz"),
        file.path(source_root, "confirmation/scores", sprintf("cell_%04d", id),
          c("mean_design.rds", "score_draws.csv.gz", "artifact_manifest.csv")))
      frames <- lapply(jobs$worker_id, function(worker) app_read_csv(file.path(source_root,
        "confirmation/chains", sprintf("worker_%04d", worker), "posterior_draws.csv.gz")))
      beta <- do.call(rbind, lapply(frames, app_joint_recursive_select_block, "beta"))
      alpha <- do.call(rbind, lapply(frames, app_joint_recursive_select_block, "alpha"))
      chain_id <- rep(jobs$chain_id, vapply(frames, nrow, integer(1L)))
      original_beta <- beta; original_alpha <- alpha
      p <- ncol(context$design$Z)
      seed <- ct$score_seed_base + dataset * 1000L + 1000000L
      if (cell$structure == "independent") {
        offset <- 0L
        for (i in seq_along(frames)) {
          rows <- offset + seq_len(nrow(frames[[i]])); offset <- max(rows)
          coupled <- app_joint_recursive_couple_independent(beta[rows, , drop = FALSE],
            alpha[rows, , drop = FALSE], p, as.integer(seed + i))
          beta[rows, ] <- coupled$beta; alpha[rows, ] <- coupled$alpha
        }
      }
      design <- readRDS(file.path(source_root, "confirmation/scores", sprintf("cell_%04d", id), "mean_design.rds"))
      parts <- joint_width_reconstruct(design$mean_design, beta, alpha, oracle,
        ct$tau, ct$weights, context$design$forecast_map)
      recorded <- app_read_csv(file.path(source_root, "confirmation/scores", sprintf("cell_%04d", id), "score_draws.csv.gz"))
      score <- rowSums(parts$loss)
      error <- max(abs(score - recorded$origin_marginal_dgp_integrated_acrps))
      stopifnot(error <= 1e-8, identical(as.integer(chain_id), as.integer(recorded$chain_id)))
      weighted <- rowSums(sweep(parts$lead, 2L,
        tabulate(context$design$forecast_map$horizon) / nrow(context$design$forecast_map), "*"))
      stopifnot(max(abs(score - weighted)) <= 1e-8)
      meta <- cell[c("cell_id", "scenario_id", "replicate_id", "structure", "likelihood", "arm_id")]
      decomp <- joint_width_decompose(parts$loss, chain_id)
      raw <- joint_width_decompose(parts$raw_loss, chain_id)
      all_cells[[length(all_cells) + 1L]] <- cbind(cell, decomp$summary,
        raw_covariance_fraction = raw$summary$covariance_fraction,
        raw_total_variance = raw$summary$total_variance,
        reconstruction_max_error = error)
      all_chain[[length(all_chain) + 1L]] <- cbind(meta, joint_width_loss_chain_rows(parts$loss, chain_id))
      all_projection[[length(all_projection) + 1L]] <- cbind(meta,
        joint_width_projection(context$design$Z[context$design$fit_local, , drop = FALSE],
          design$mean_design, common, original_beta, original_alpha, ct$tau))
      corr <- stats::cor(parts$loss)
      idx <- expand.grid(tau_x = ct$tau, tau_y = ct$tau)
      all_cor[[length(all_cor) + 1L]] <- cbind(meta, idx, correlation = as.vector(corr),
        covariance = as.vector(decomp$covariance))
      all_losses[[length(all_losses) + 1L]] <- cbind(meta,
        data.frame(draw_index = seq_len(nrow(beta)), chain_id = chain_id,
          setNames(as.data.frame(parts$loss), paste0("weighted_loss_", seq_along(ct$tau)))))
      h <- lapply(seq_len(ncol(parts$lead)), function(lead) {
        q <- stats::quantile(parts$lead[, lead], c(.025, .975), type = 8, names = FALSE)
        data.frame(horizon = lead, score_mean = mean(parts$lead[, lead]), q025 = q[1], q975 = q[2])
      })
      all_leads[[length(all_leads) + 1L]] <- cbind(meta, do.call(rbind, h))
      rows <- parts$first_origin_rows
      bands <- lapply(seq_along(ct$tau), function(k) {
        values <- parts$origin_q[, , k]
        q <- t(apply(values, 1L, stats::quantile, c(.025, .975), type = 8, names = FALSE))
        data.frame(horizon = context$design$forecast_map$horizon[rows], tau = ct$tau[k],
          posterior_mean = rowMeans(values), q025 = q[, 1], q975 = q[, 2],
          true_quantile = oracle$true_q[rows, k], observed_y = oracle$observed_y[rows])
      })
      all_bands[[length(all_bands) + 1L]] <- cbind(meta, do.call(rbind, bands))
      cat("AUDITED cell", id, cell$scenario_id, cell$likelihood, cell$structure,
        cell$arm_id, "score identity error", format(error), "covariance fraction",
        format(decomp$summary$covariance_fraction), "between-chain fraction",
        format(decomp$summary$between_chain_variance_fraction), "\n")
      flush.console()
    }
  }
  write <- function(x, name) app_write_csv(do.call(rbind, x), file.path(output, name))
  write(all_cells, "cell_audit.csv"); write(all_chain, "chain_sensitivity.csv")
  write(all_projection, "readout_projection_variance.csv"); write(all_cor, "loss_correlation.csv")
  write(all_leads, "lead_score_bands.csv"); write(all_bands, "first_origin_quantile_bands.csv")
  app_joint_article_write_gzip_csv(do.call(rbind, all_losses), file.path(output, "weighted_loss_draws.csv.gz"))
  scripts <- file.path(app_path(), "local_trackers/joint_score_width_audit_20261006",
    c("audit_and_plot.R", "test_audit.R"))
  inputs <- unique(c(inputs, scripts))
  stopifnot(all(file.exists(inputs)))
  app_write_csv(data.frame(path = inputs, size_bytes = as.numeric(file.info(inputs)$size),
    sha256 = vapply(inputs, app_sha256_file, character(1L))), file.path(output, "input_manifest.csv"))
  joint_width_plot(output)
  writeLines(c("Read-only JOINT uncertainty attribution; no changes to frozen scores or fits.",
    paste("Source root:", source_root), paste("Frozen HEAD:", readLines(file.path(source_root, "source_head.txt"))),
    "All 24 confirmation cells and all retained posterior draws were used.",
    "Native joint dependence preserved; independent coupling exactly reproduces the frozen seed rule.",
    "Loss and horizon decompositions reproduce the frozen score within 1e-8.",
    "Common-design and weak-design projections are diagnostics, not alternative forecasts or scores.",
    "Weak-direction projected variances are not additive variance shares: cross-direction covariance remains.",
    "Forecast-band truth is origin-marginal DGP truth; bands are quantile-function uncertainty.",
    "First origin chosen before inspection. No source model or challenger has been promoted.",
    "Main forecast plots use all four baseline model types; challengers are labeled separately in the score comparison.",
    "Between-chain fractions after independent permutation are descriptive allocations, not temporal convergence proof.",
    "Independent score-draw temporal halves are also descriptive only after product-posterior permutation.",
    paste("Analysis UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    capture.output(sessionInfo())),
    file.path(output, "METHODS.txt"))
  paths <- list.files(output, full.names = TRUE)
  app_joint_shared_write_manifest(output, setNames(paths, basename(paths)))
  stopifnot(all(app_joint_shared_verify_manifest(output, file.path(output, "artifact_manifest.csv"))$verified))
  cat("AUDIT_AND_PLOTS_COMPLETE\n")
  invisible(output)
}
