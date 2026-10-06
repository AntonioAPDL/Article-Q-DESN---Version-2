joint_width_score_gradient <- function(Z, beta_mean, alpha_mean, oracle, tau, weights) {
  H <- nrow(Z); p <- ncol(Z); K <- length(tau)
  raw <- sapply(seq_len(K), function(k) {
    columns <- ((k - 1L) * p + 1L):(k * p)
    as.vector(Z %*% beta_mean[columns]) + alpha_mean[k]
  })
  contracted <- app_joint_recursive_contract_draw_rows(raw, tau)
  q <- contracted$q_contract
  cdf <- matrix(NA_real_, H, K)
  for (h in seq_len(H)) {
    cdf[h, ] <- findInterval(q[h, ], oracle$sorted_response[, h]) /
      nrow(oracle$sorted_response)
  }
  gradient_q <- sweep(sweep(cdf, 2L, tau, "-"), 2L, 2 * weights / H, "*")
  # The frozen unweighted isotonic projection averages derivatives within pools.
  for (h in contracted$adjusted_rows) {
    group <- cumsum(c(TRUE, abs(diff(q[h, ])) > 1e-12))
    for (index in split(seq_len(K), group)) {
      gradient_q[h, index] <- mean(gradient_q[h, index])
    }
  }
  X <- cbind(1, Z)
  gradient <- sapply(seq_len(K), function(k) {
    as.vector(crossprod(X, gradient_q[, k]))
  })
  list(gradient = gradient, cdf = cdf, q = q,
    mean_abs_cdf_error = colMeans(abs(sweep(cdf, 2L, tau, "-"))))
}

joint_width_sensitivity_main <- function(source_root, output) {
  stopifnot(!dir.exists(output))
  app_joint_prior_verify_freeze(source_root)
  ct <- readRDS(file.path(source_root, "contract.rds"))
  cells <- app_joint_prior_collect(source_root, "confirmation")
  cells <- cells[cells$scenario_id == "laplace_bridge" & cells$arm_id == "prior_08", ]
  stopifnot(nrow(cells) == 8L)
  plan <- app_read_csv(file.path(source_root, "confirmation/chains.csv"))
  summaries <- levels <- list()
  app_ensure_dir(output)
  for (i in seq_len(nrow(cells))) {
    cell <- cells[i, ]; id <- cell$cell_id
    jobs <- plan[plan$cell_id == id, ]; jobs <- jobs[order(jobs$chain_id), ]
    frames <- lapply(jobs$worker_id, function(worker) app_read_csv(file.path(source_root,
      "confirmation/chains", sprintf("worker_%04d", worker), "posterior_draws.csv.gz")))
    beta <- do.call(rbind, lapply(frames, app_joint_recursive_select_block, "beta"))
    alpha <- do.call(rbind, lapply(frames, app_joint_recursive_select_block, "alpha"))
    Z <- readRDS(file.path(source_root, "confirmation/scores",
      sprintf("cell_%04d", id), "mean_design.rds"))$mean_design
    p <- ncol(Z); K <- length(ct$tau)
    if (cell$structure == "independent") {
      offset <- 0L
      seed <- ct$score_seed_base + cell$dataset_id * 1000L + 1000000L
      for (j in seq_along(frames)) {
        rows <- offset + seq_len(nrow(frames[[j]])); offset <- max(rows)
        coupled <- app_joint_recursive_couple_independent(beta[rows, , drop = FALSE],
          alpha[rows, , drop = FALSE], p, as.integer(seed + j))
        beta[rows, ] <- coupled$beta; alpha[rows, ] <- coupled$alpha
      }
    }
    oracle <- readRDS(file.path(source_root, "confirmation/datasets",
      sprintf("dataset_%02d", cell$dataset_id), "oracle.rds"))
    bm <- colMeans(beta); am <- colMeans(alpha)
    derivative <- joint_width_score_gradient(Z, bm, am, oracle, ct$tau, ct$weights)
    set.seed(2300L + id)
    direction_b <- rnorm(length(bm)); direction_a <- rnorm(K)
    analytic <- 0
    for (k in seq_len(K)) {
      columns <- ((k - 1L) * p + 1L):(k * p)
      analytic <- analytic + sum(derivative$gradient[, k] *
        c(direction_a[k], direction_b[columns]))
    }
    evaluate <- function(eps) app_joint_recursive_canonical_metrics(Z,
      bm + eps * direction_b, am + eps * direction_a, oracle, ct$tau, ct$weights)$
      origin_marginal_dgp_integrated_acrps
    numeric <- (evaluate(1e-6) - evaluate(-1e-6)) / 2e-6
    error <- abs(analytic - numeric)
    stopifnot(is.finite(error), error <= 1e-4)
    influence <- matrix(NA_real_, nrow(beta), K)
    for (k in seq_len(K)) {
      columns <- ((k - 1L) * p + 1L):(k * p)
      coefficients <- cbind(alpha[, k], beta[, columns, drop = FALSE])
      influence[, k] <- sweep(coefficients, 2L, colMeans(coefficients), "-") %*%
        derivative$gradient[, k]
    }
    actual <- app_read_csv(file.path(source_root, "confirmation/scores",
      sprintf("cell_%04d", id), "score_draws.csv.gz"))$origin_marginal_dgp_integrated_acrps
    linear <- rowSums(influence)
    summaries[[i]] <- cbind(cell, weighted_cdf_miscalibration =
      sum(ct$weights * derivative$mean_abs_cdf_error) / sum(ct$weights),
      score_delta_variance = stats::var(linear), actual_score_variance = stats::var(actual),
      delta_actual_variance_ratio = stats::var(linear) / stats::var(actual),
      delta_actual_correlation = stats::cor(linear, actual),
      delta_actual_correlation_squared = stats::cor(linear, actual)^2,
      derivative_finite_difference_error = error)
    levels[[i]] <- cbind(cell[c("cell_id", "replicate_id", "structure", "likelihood")],
      data.frame(tau = ct$tau, mean_abs_cdf_miscalibration = derivative$mean_abs_cdf_error,
        canonical_quantile_rmse = sqrt(colMeans((derivative$q - oracle$true_q)^2)),
        linear_loss_variance = apply(influence, 2L, stats::var)))
  }
  summary <- do.call(rbind, summaries)
  app_write_csv(summary, file.path(output, "laplace_loss_sensitivity.csv"))
  app_write_csv(do.call(rbind, levels), file.path(output, "quantile_loss_sensitivity.csv"))
  script <- app_path("local_trackers/joint_score_width_audit_20261006/loss_sensitivity.R")
  app_write_csv(data.frame(path = script, sha256 = app_sha256_file(script)),
    file.path(output, "analysis_source.csv"))
  writeLines(c("First-order DGP expected-loss sensitivity, not a replacement score or posterior approximation.",
    "Canonical reported-action derivatives include the frozen isotonic pool Jacobian.",
    "Every directional derivative is checked against the frozen scorer at +/- 1e-6.",
    "Native joint dependence and frozen independent product coupling are preserved.",
    "Delta variance and squared correlation are descriptive approximation diagnostics, not causal variance shares.",
    capture.output(sessionInfo())), file.path(output, "METHODS.txt"))
  app_joint_shared_write_manifest(output, setNames(list.files(output, full.names = TRUE), list.files(output)))
  stopifnot(all(app_joint_shared_verify_manifest(output)$verified))
  print(summary[c("replicate_id", "structure", "likelihood", "weighted_cdf_miscalibration",
    "delta_actual_variance_ratio", "delta_actual_correlation_squared",
    "derivative_finite_difference_error")], row.names = FALSE, digits = 6)
  cat("LOSS_SENSITIVITY_COMPLETE\n")
}
