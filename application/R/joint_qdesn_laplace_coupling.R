# Dedicated experiment adapter; source only after the frozen prior-screen module.
app_joint_coupling_parent_context <- app_joint_prior_context
app_joint_coupling_parent_controls <- app_joint_prior_controls
app_joint_coupling_parent_warmup <- app_joint_prior_warmup
app_joint_coupling_parent_collect <- app_joint_prior_collect
app_joint_coupling_parent_vb <- app_joint_prior_vb

app_joint_coupling_contract <- function() {
  tab <- app_read_csv(app_path("application/config/joint_qdesn_laplace_coupling_contract_v1.csv"))
  stopifnot(!anyDuplicated(tab$name))
  out <- as.list(setNames(as.character(tab$value), tab$name))
  for (key in names(out)) if (grepl("^[0-9.]+$", out[[key]])) out[[key]] <- as.numeric(out[[key]])
  out$scenarios <- strsplit(out$scenarios, ";", fixed = TRUE)[[1L]]
  stopifnot(identical(out$scenarios, "laplace_bridge"), out$max_workers == 15,
    out$screen_replicates == 2, out$confirmation_replicates == 2,
    out$screen_chains == 2, out$confirmation_chains == 3,
    out$exal_mcmc_method == "M0_v_collapsed_support_logit",
    out$exal_vb_method == "VB1_structured_v", out$publication_allowed == "false",
    out$anchor_budget_min_share > 0, out$anchor_budget_max_share < 1,
    out$anchor_budget_min_share < out$anchor_budget_max_share,
    out$innovation_slab_min_multiplier > 1,
    out$innovation_slab_max_multiplier >= out$innovation_slab_min_multiplier)
  out$tau <- c(.05, .10, .25, .50, .75, .90, .95)
  out$weights <- c(.025, .1, .2, .25, .2, .1, .025)
  out
}

app_joint_coupling_arms <- function(contract = app_joint_coupling_contract()) {
  data.frame(arm_id = c("baseline", "relaxed_innovation_slab", "conditional_variance_budget"),
    baseline = c(TRUE, FALSE, FALSE), anchor_multiplier = 1, innovation_multiplier = 1,
    rule = c("unchanged", "training_energy_bounded_slab", "training_energy_conditional_budget"))
}

app_joint_coupling_calibrated_arms <- function(context, ct) {
  d <- context$design; p <- ncol(d$Z); K <- length(d$tau)
  init <- context$independent_al
  stopifnot(K == 7L, length(init$beta_mean) == K * p,
    identical(dim(init$beta_cov), c(K * p, K * p)))
  beta <- matrix(init$beta_mean, p, K)
  variance <- matrix(diag(init$beta_cov), p, K)
  energy_weights <- colMeans(d$Z[d$fit_local, , drop = FALSE]^2)
  stopifnot(all(is.finite(c(beta, variance, energy_weights))),
    all(variance >= -1e-10), sum(energy_weights) > 0)
  energy_weights <- energy_weights / sum(energy_weights)
  energy <- colSums((beta^2 + pmax(variance, 0)) * energy_weights)
  delta_energy <- colSums(((beta[, -1L, drop = FALSE] - beta[, -K, drop = FALSE])^2 +
    pmax(variance[, -1L, drop = FALSE], 0) + pmax(variance[, -K, drop = FALSE], 0)) * energy_weights)
  eps <- .Machine$double.eps
  share <- energy[[1L]] / max(energy[[1L]] + sum(delta_energy), eps)
  share <- max(ct$anchor_budget_min_share, min(ct$anchor_budget_max_share, share))
  ratio <- mean(delta_energy) / max(mean(energy), eps)
  slab_multiplier <- max(ct$innovation_slab_min_multiplier,
    min(ct$innovation_slab_max_multiplier, 1 + ratio))
  tau0 <- context$selected$rhs_tau0[[1L]]; slab <- context$vc$rhs_slab_variance
  reference <- 1 / (1 / tau0^2 + 1 / slab)
  anchor_budget <- share * reference; innovation_budget <- (1 - share) * reference / (K - 1L)
  inverse_variance <- function(v) sqrt(1 / (1 / v - 1 / slab))
  out <- app_joint_coupling_arms(ct)
  out$anchor_tau0 <- tau0; out$innovation_tau0 <- tau0
  out$anchor_zeta2 <- slab; out$innovation_zeta2 <- slab
  out$innovation_zeta2[out$arm_id == "relaxed_innovation_slab"] <- slab * slab_multiplier
  budget <- out$arm_id == "conditional_variance_budget"
  out$anchor_tau0[budget] <- inverse_variance(anchor_budget)
  out$innovation_tau0[budget] <- inverse_variance(innovation_budget)
  out$anchor_multiplier <- out$anchor_tau0 / tau0
  out$innovation_multiplier <- out$innovation_tau0 / tau0
  out$training_anchor_share <- share
  out$training_delta_to_marginal_energy_ratio <- ratio
  out$conditional_reference_variance <- reference
  out$conditional_terminal_variance <- 1 / (1 / out$anchor_tau0^2 + 1 / out$anchor_zeta2) +
    (K - 1L) / (1 / out$innovation_tau0^2 + 1 / out$innovation_zeta2)
  stopifnot(abs(out$conditional_terminal_variance[budget] - reference) < 1e-10,
    all(is.finite(as.matrix(out[c("anchor_tau0", "innovation_tau0", "anchor_zeta2", "innovation_zeta2")]))))
  list(arms = out, energy = data.frame(tau = d$tau, coefficient_second_moment_energy = energy,
    adjacent_second_moment_energy = c(NA_real_, delta_energy)))
}

app_joint_coupling_prepare <- function(root) {
  if (dir.exists(root)) stop("Use a new experiment root; overwrite forbidden.")
  ct <- app_joint_coupling_contract(); arms <- app_joint_coupling_arms(ct)
  app_ensure_dir(root); saveRDS(ct, file.path(root, "contract.rds"))
  app_write_csv(arms, file.path(root, "arms.csv"))
  backbones <- app_read_csv(app_path("tables/joint_qdesn_pure_desn_v1_selected_backbones.csv"))
  backbones <- backbones[match(ct$scenarios, backbones$scenario_id), , drop = FALSE]
  stopifnot(nrow(backbones) == 1L, !anyNA(backbones$scenario_id),
    !any(backbones$raw_inputs_in_readout), all(backbones$full_states_all_layers))
  app_write_csv(backbones, file.path(root, "backbones.csv"))
  source <- unique(c(list.files(app_path("application/R"), "\\.R$", full.names = TRUE),
    list.files(app_path("application/scripts"), "joint.*\\.(R|sh)$", full.names = TRUE),
    list.files(app_path("application/config"), "joint.*\\.csv$", full.names = TRUE),
    app_path("tables/joint_qdesn_pure_desn_v1_selected_backbones.csv")))
  app_write_csv(data.frame(relative_path = substring(source, nchar(app_path()) + 2L),
    sha256 = vapply(source, app_sha256_file, character(1L))), file.path(root, "source_manifest.csv"))
  writeLines(system2("git", c("rev-parse", "HEAD"), stdout = TRUE), file.path(root, "source_head.txt"))
  writeLines(capture.output(sessionInfo()), file.path(root, "session_info.txt"))
  files <- list.files(root, full.names = TRUE)
  app_joint_shared_write_manifest(root, setNames(files, basename(files)), filename = "freeze_manifest.csv")
  app_joint_coupling_stage_prepare(root, "screen")
}

app_joint_coupling_stage_prepare <- function(root, stage) {
  stopifnot(stage %in% c("screen", "confirmation"))
  app_joint_prior_verify_freeze(root)
  ct <- readRDS(file.path(root, "contract.rds")); arms <- app_read_csv(file.path(root, "arms.csv"))
  dest <- file.path(root, stage); if (dir.exists(dest)) stop("Stage already prepared.")
  if (stage == "confirmation") {
    stopifnot(file.exists(file.path(root, "screen", "SELECTION_FROZEN")))
    app_joint_prior_verify_selection(root)
    selection <- app_read_csv(file.path(root, "screen", "selection.csv"))
    stopifnot(nrow(selection) == 2L, setequal(selection$likelihood, c("AL", "exAL")),
      all(selection$scenario_id == "laplace_bridge"), !anyDuplicated(selection$likelihood),
      all(selection$arm_id %in% arms$arm_id), all(selection$baseline_arm_id == "baseline"))
  }
  app_ensure_dir(dest)
  datasets <- data.frame(scenario_id = ct$scenarios,
    replicate_id = seq_len(ct[[paste0(stage, "_replicates")]]))
  datasets$dataset_id <- seq_len(nrow(datasets))
  datasets$dgp_seed <- ct[[paste0(stage, "_seed_base")]] + datasets$dataset_id * 100L
  cells <- list()
  for (d in seq_len(nrow(datasets))) for (likelihood in c("AL", "exAL")) {
    chosen <- if (stage == "screen") arms$arm_id else unique(c("baseline",
      selection$arm_id[selection$likelihood == likelihood]))
    for (arm in chosen) cells[[length(cells) + 1L]] <- data.frame(dataset_id = d,
      scenario_id = ct$scenarios, replicate_id = d, likelihood = likelihood,
      structure = "joint", arm_id = arm, long_budget = FALSE)
    cells[[length(cells) + 1L]] <- data.frame(dataset_id = d,
      scenario_id = ct$scenarios, replicate_id = d, likelihood = likelihood,
      structure = "independent", arm_id = "baseline", long_budget = FALSE)
  }
  cells <- do.call(rbind, cells); cells$cell_id <- seq_len(nrow(cells))
  nchain <- as.integer(ct[[paste0(stage, "_chains")]])
  jobs <- cells[rep(seq_len(nrow(cells)), each = nchain), , drop = FALSE]
  jobs$chain_id <- rep(seq_len(nchain), nrow(cells)); jobs$worker_id <- seq_len(nrow(jobs))
  offset <- if (stage == "screen") 0L else 1000000L
  jobs$chain_seed <- ct$chain_seed_base + offset + jobs$worker_id * 1009L
  jobs$start_seed <- ct$initialization_seed_base + offset + jobs$worker_id * 1009L
  for (k in seq_along(ct$tau)) jobs[[paste0("component_seed_", k)]] <- jobs$chain_seed + 100000L + k * 7919L
  warm <- unique(cells[cells$structure == "joint", c("dataset_id", "arm_id")])
  warm$worker_id <- seq_len(nrow(warm))
  app_write_csv(datasets, file.path(dest, "datasets.csv"))
  app_write_csv(cells, file.path(dest, "cells.csv")); app_write_csv(jobs, file.path(dest, "chains.csv"))
  app_write_csv(warm, file.path(dest, "warmups.csv"))
  paths <- list.files(dest, full.names = TRUE)
  app_joint_shared_write_manifest(dest, setNames(paths, basename(paths)), filename = "plan_manifest.csv")
}

app_joint_coupling_controls <- function(context, arm, independent = FALSE) {
  base <- app_joint_coupling_arms()[1L, ]
  controls <- app_joint_coupling_parent_controls(context, base, independent)
  if (!independent && arm$arm_id[[1L]] != "baseline") {
    if (is.null(context$calibrated_arms)) stop("Challenger controls are not frozen.")
    row <- context$calibrated_arms[context$calibrated_arms$arm_id == arm$arm_id[[1L]], ]
    stopifnot(nrow(row) == 1L)
    for (key in c("anchor_tau0", "innovation_tau0", "anchor_zeta2", "innovation_zeta2")) controls[[key]] <- row[[key]]
  }
  controls
}

app_joint_coupling_vb <- function(context, arm) {
  d <- context$design; vc <- context$vc; p <- ncol(d$Z); K <- length(d$tau)
  controls <- app_joint_coupling_controls(context, arm); controls$sigma_bounds <- NULL
  init <- context$independent_al
  init$rhs_state <- app_joint_qvp_initialize_rhs_state(K, p, tau0 = controls$tau0,
    zeta2 = controls$zeta2, anchor_tau0 = controls$anchor_tau0,
    innovation_tau0 = controls$innovation_tau0, anchor_zeta2 = controls$anchor_zeta2,
    innovation_zeta2 = controls$innovation_zeta2, slab_fixed = controls$slab_fixed)
  common <- c(list(y = d$y[d$fit_local], Z = d$Z[d$fit_local, , drop = FALSE],
    tau = d$tau, max_iter = vc$al_max_iter, tol = vc$vb_tolerance,
    rhs_vb_inner = vc$rhs_vb_inner, rhs_freeze_iters = 0L), controls)
  al <- do.call(app_joint_qvp_fit_al_vb_tiny,
    c(common, list(init = app_joint_shared_quantile_reset_init(init))))
  exinit <- context$independent_exal; exinit$rhs_state <- al$rhs_state
  exal <- do.call(app_joint_exqdesn_fit_vb_dispatch, c(common, list(method_id = vc$coupling_vb_method %||% "VB1_structured_v",
    gamma_init = rep(0, K), diagnostic_stride = 20L, quadrature_nodes = c(4L, 8L, 12L),
    quadrature_tolerance = 1e-5, init = app_joint_shared_quantile_reset_init(exinit))))
  fits <- list(AL = al, exAL = exal)
  for (fit in fits) {
    stopifnot(fit$rhs_state$anchor$tau0 == controls$anchor_tau0,
      fit$rhs_state$anchor$zeta2 == controls$anchor_zeta2)
    for (block in fit$rhs_state[-1L]) stopifnot(block$tau0 == controls$innovation_tau0,
      block$zeta2 == controls$innovation_zeta2)
  }
  fits
}

app_joint_coupling_calibrate <- function(root, stage, dataset_id) {
  ct <- readRDS(file.path(root, "contract.rds"))
  context <- app_joint_coupling_parent_context(root, stage, dataset_id)
  result <- app_joint_coupling_calibrated_arms(context, ct)
  context$calibrated_arms <- result$arms
  baseline <- app_joint_coupling_vb(context, app_joint_coupling_arms()[1L, ])
  d <- context$design; p <- ncol(d$Z); K <- length(d$tau)
  diagnostics <- list()
  for (family in c("AL", "exAL")) {
    reference <- context[[paste0("independent_", tolower(family))]]
    for (k in seq_len(K)) {
      cols <- ((k - 1L) * p + 1L):(k * p)
      contrib <- d$Z[d$fit_local, , drop = FALSE] %*%
        cbind(reference$beta_mean[cols], baseline[[family]]$beta_mean[cols])
      q <- sweep(contrib, 2L, c(reference$alpha_mean[k], baseline[[family]]$alpha_mean[k]), "+")
      residual <- d$y[d$fit_local] - q
      diagnostics[[length(diagnostics) + 1L]] <- data.frame(likelihood = family, tau = d$tau[k],
        training_readout_rms_difference = sqrt(mean((contrib[, 1L] - contrib[, 2L])^2)),
        independent_training_check_loss = mean(residual[, 1L] * (d$tau[k] - (residual[, 1L] < 0))),
        joint_training_check_loss = mean(residual[, 2L] * (d$tau[k] - (residual[, 2L] < 0))),
        independent_training_level_error = mean(d$y[d$fit_local] <= q[, 1L]) - d$tau[k],
        joint_training_level_error = mean(d$y[d$fit_local] <= q[, 2L]) - d$tau[k])
    }
  }
  folder <- file.path(root, stage, "calibrations", sprintf("dataset_%02d", dataset_id))
  app_ensure_dir(folder)
  app_write_csv(result$arms, file.path(folder, "calibrated_arms.csv"))
  app_write_csv(result$energy, file.path(folder, "training_coefficient_energy.csv"))
  app_write_csv(do.call(rbind, diagnostics), file.path(folder, "training_readout_diagnostics.csv"))
  saveRDS(baseline, file.path(folder, "baseline_initializers.rds"))
  app_write_csv(data.frame(stage = stage, dataset_id = dataset_id,
    fit_rows = length(d$fit_local), max_fit_time = max(d$row_meta$full_time_index[d$fit_local]),
    first_scored_time = min(d$forecast_map$full_time_index),
    training_data_hash = context$data_hash,
    calibration_input_hash = digest::digest(list(Z = d$Z[d$fit_local, ],
      beta = context$independent_al$beta_mean, cov = context$independent_al$beta_cov), algo = "sha256"),
    component_manifest_sha256 = app_sha256_file(file.path(root, stage, "datasets",
      sprintf("dataset_%02d", dataset_id), "component_manifest.csv"))), file.path(folder, "calibration_provenance.csv"))
  stopifnot(max(d$row_meta$full_time_index[d$fit_local]) < min(d$forecast_map$full_time_index))
  app_joint_prior_seal(folder)
}

app_joint_coupling_context <- function(root, stage, dataset_id) {
  context <- app_joint_coupling_parent_context(root, stage, dataset_id)
  folder <- file.path(root, stage, "calibrations", sprintf("dataset_%02d", dataset_id))
  if (!app_joint_prior_done(folder)) stop("Training-derived control freeze is incomplete.")
  context$calibrated_arms <- app_read_csv(file.path(folder, "calibrated_arms.csv"))
  context
}

app_joint_coupling_warmup <- function(root, stage, worker_id) {
  row <- app_read_csv(file.path(root, stage, "warmups.csv"))[worker_id, , drop = FALSE]
  if (row$arm_id != "baseline") return(app_joint_coupling_parent_warmup(root, stage, worker_id))
  app_joint_coupling_context(root, stage, row$dataset_id)
  source <- file.path(root, stage, "calibrations", sprintf("dataset_%02d", row$dataset_id), "baseline_initializers.rds")
  folder <- file.path(root, stage, "warmups", sprintf("worker_%03d", worker_id))
  app_ensure_dir(folder)
  destination <- file.path(folder, "initializers.rds")
  if (file.exists(destination)) {
    stopifnot(app_sha256_file(source) == app_sha256_file(destination))
  } else stopifnot(file.copy(source, destination, overwrite = FALSE))
  fits <- readRDS(source)
  app_write_csv(data.frame(likelihood = c("AL", "exAL"),
    converged = vapply(fits, function(x) isTRUE(x$converged), logical(1L)),
    source_sha256 = app_sha256_file(source)), file.path(folder, "vb_health.csv"))
  app_joint_prior_seal(folder)
}

app_joint_coupling_eligible <- function(rows, ct) {
  required <- c("posterior_score_mean", "canonical_origin_marginal_dgp_integrated_acrps",
    "score_rank_rhat", "quantile_functional_max_rhat", "state_half_score_relative_difference", "chain_score_relative_range")
  stopifnot(all(required %in% names(rows)))
  finite <- apply(rows[required], 1L, function(x) all(is.finite(x)))
  finite & rows$contract_crossing_pairs == 0 &
    rows$canonical_contract_crossing_pairs == 0 &
    rows$score_rank_rhat <= ct$functional_hard_rhat &
    rows$quantile_functional_max_rhat <= ct$functional_hard_rhat &
    rows$state_half_score_relative_difference <= ct$functional_hard_relative_difference &
    rows$chain_score_relative_range <= ct$functional_hard_relative_difference
}

app_joint_coupling_collect <- function(root, stage) {
  plan <- app_read_csv(file.path(root, stage, "datasets.csv"))
  for (id in plan$dataset_id) app_joint_coupling_context(root, stage, id)
  app_joint_coupling_parent_collect(root, stage)
}

app_joint_coupling_select_rows <- function(rows, ct, baseline) {
  rows$eligible <- app_joint_coupling_eligible(rows, ct)
  groups <- split(rows, rows$arm_id)
  expected <- app_joint_coupling_arms(ct)$arm_id
  if (!setequal(names(groups), expected)) stop("Missing or unexpected selector arm.")
  aggregate <- do.call(rbind, lapply(groups, function(x) {
    if (nrow(x) != ct$screen_replicates || anyDuplicated(x$replicate_id) ||
      !setequal(x$replicate_id, seq_len(ct$screen_replicates))) stop("Incomplete matched selector replicates.")
    data.frame(arm_id = x$arm_id[1L], mean = mean(x$posterior_score_mean), eligible = all(x$eligible))
  }))
  base <- aggregate[aggregate$arm_id == baseline, ]
  if (!is.finite(base$mean) || !base$eligible || any(!is.finite(aggregate$mean))) stop("Invalid selector baseline or scores.")
  eligible <- aggregate[aggregate$eligible & aggregate$mean < base$mean - ct$selection_epsilon, ]
  selected <- if (nrow(eligible)) eligible[order(eligible$mean, eligible$arm_id), ][1L, ] else base
  data.frame(scenario_id = rows$scenario_id[1L], likelihood = rows$likelihood[1L],
    arm_id = selected$arm_id, baseline_arm_id = baseline, selector_mean = selected$mean,
    baseline_mean = base$mean, improvement = base$mean - selected$mean,
    interpretation = "training_rule_internal_selection_not_article_promotion")
}

app_joint_coupling_finalize <- function(root) {
  app_joint_prior_verify_freeze(root); app_joint_prior_verify_selection(root)
  ct <- readRDS(file.path(root, "contract.rds")); tab <- app_joint_prior_collect(root, "confirmation")
  for (id in unique(tab$dataset_id)) app_joint_coupling_context(root, "confirmation", id)
  selection <- app_read_csv(file.path(root, "screen", "selection.csv"))
  verdict <- list(); contrasts <- list()
  for (i in seq_len(nrow(selection))) {
    s <- selection[i, ]; rows <- tab[tab$likelihood == s$likelihood, ]
    baseline <- rows[rows$structure == "joint" & rows$arm_id == "baseline", ]
    candidate <- rows[rows$structure == "joint" & rows$arm_id == s$arm_id, ]
    independent <- rows[rows$structure == "independent", ]
    baseline <- baseline[order(baseline$replicate_id), ]; candidate <- candidate[order(candidate$replicate_id), ]
    independent <- independent[order(independent$replicate_id), ]
    stopifnot(nrow(candidate) == ct$confirmation_replicates,
      identical(candidate$replicate_id, baseline$replicate_id), identical(candidate$replicate_id, independent$replicate_id))
    delta <- candidate$posterior_score_mean - baseline$posterior_score_mean
    verdict[[i]] <- data.frame(scenario_id = ct$scenarios, likelihood = s$likelihood, arm_id = s$arm_id,
      baseline_mean = mean(baseline$posterior_score_mean), candidate_mean = mean(candidate$posterior_score_mean),
      independent_mean = mean(independent$posterior_score_mean), candidate_minus_baseline = mean(delta),
      replicate_improvement_count = sum(delta < 0), confirmation_replicates = length(delta),
      candidate_mean_interval_width = mean(candidate$posterior_score_interval_width),
      baseline_mean_interval_width = mean(baseline$posterior_score_interval_width),
      independent_mean_interval_width = mean(independent$posterior_score_interval_width),
      canonical_mean_change = mean(candidate$canonical_origin_marginal_dgp_integrated_acrps - baseline$canonical_origin_marginal_dgp_integrated_acrps),
      functional_review_count = sum(candidate$functional_status == "review"),
      decision = if (s$arm_id == "baseline") "retain_baseline" else if (mean(delta) < 0 &&
        all(app_joint_coupling_eligible(candidate, ct))) "descriptive_mean_gain_integration_review" else "retain_baseline_review",
      claim = "fresh_seed_confirmation_not_article_fixture_supersession")
    for (replicate in candidate$replicate_id) for (reference in c("baseline", "independent")) {
      c <- candidate[candidate$replicate_id == replicate, ]
      r <- if (reference == "baseline") baseline[baseline$replicate_id == replicate, ] else independent[independent$replicate_id == replicate, ]
      load <- function(id) app_read_csv(file.path(root, "confirmation/scores", sprintf("cell_%04d", id), "score_draws.csv.gz"))$origin_marginal_dgp_integrated_acrps
      left <- load(c$cell_id); right <- load(r$cell_id); n <- min(length(left), length(right))
      set.seed(as.integer(ct$score_seed_base + i * 100L + replicate * 10L + match(reference, c("baseline", "independent"))))
      diff <- if (c$cell_id == r$cell_id) rep(0, n) else left[sample.int(length(left), n)] - right[sample.int(length(right), n)]
      contrasts[[length(contrasts) + 1L]] <- data.frame(likelihood = s$likelihood, replicate_id = replicate,
        reference = reference, mean_difference = mean(left) - mean(right), q025 = quantile(diff, .025, names = FALSE),
        q975 = quantile(diff, .975, names = FALSE), coupling = "independent_product_between_fitted_models")
    }
  }
  packet <- file.path(root, "closeout"); if (app_joint_prior_done(packet)) return(invisible(packet))
  app_ensure_dir(packet)
  app_write_csv(tab, file.path(packet, "confirmation_scores.csv"))
  app_write_csv(do.call(rbind, verdict), file.path(packet, "decisions.csv"))
  app_write_csv(do.call(rbind, contrasts), file.path(packet, "posterior_score_contrasts.csv"))
  grDevices::pdf(file.path(packet, "laplace_coupling_confirmation.pdf"), width = 11, height = 7)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (family in c("AL", "exAL")) {
    x <- tab[tab$likelihood == family, ]; at <- seq_len(nrow(x))
    graphics::par(mar = c(5, 16, 4, 2))
    graphics::plot(x$posterior_score_mean, at, xlim = range(x$posterior_score_q025, x$posterior_score_q975),
      pch = 19, yaxt = "n", ylab = "", xlab = "DGP-integrated forecast score; mean and 95% credible interval",
      main = paste("Laplace Bridge", family, "fresh confirmation"))
    graphics::segments(x$posterior_score_q025, at, x$posterior_score_q975, at)
    graphics::axis(2, at, labels = paste(x$structure, x$arm_id, "rep", x$replicate_id), las = 1, cex.axis = .7)
  }
  grDevices::dev.off(); on.exit(NULL)
  counts <- do.call(rbind, lapply(c("screen", "confirmation"), function(stage) data.frame(stage = stage,
    workers = nrow(app_read_csv(file.path(root, stage, "chains.csv"))),
    cells = nrow(app_read_csv(file.path(root, stage, "cells.csv"))))))
  app_write_csv(counts, file.path(packet, "completion_counts.csv"))
  writeLines(c("# JOINT Laplace coupling closeout", "",
    "READY_FOR_INTEGRATION applies to scientific evidence/code only after independent verification.",
    "NOT_READY_FOR_ARTICLE_PROMOTION: fresh confirmation is not an article fixture.",
    "No more rounds, DESN screens, scalar-mixing gates or automatic publication.",
    paste("Run:", root), paste("HEAD:", system2("git", c("rev-parse", "HEAD"), stdout = TRUE)),
    "Evidence: freeze/source/plan/selection/calibration/worker/score manifests, decisions.csv, posterior_score_contrasts.csv.",
    "Excluded: runtime, posterior/model objects, figures, local trackers and transcripts.",
    "Risks: two realizations; data-calibrated empirical-Bayes rule; conditional initialization budget is not full prior matching.",
    "Posterior score intervals are not MCSE or frequentist sampling intervals; overlaps are not a promotion veto.",
    "Match the article fixture before proposing an authoritative article replacement."), file.path(packet, "HANDOFF.md"))
  app_joint_prior_seal(packet)
  writeLines("COMPLETE_READY_FOR_SCIENTIFIC_REVIEW", file.path(root, "COMPLETE"))
}

# Bind the adapter only in this dedicated bootstrap, not in production defaults.
app_joint_prior_contract <- app_joint_coupling_contract
app_joint_prior_arms <- app_joint_coupling_arms
app_joint_prior_prepare <- app_joint_coupling_prepare
app_joint_prior_stage_prepare <- app_joint_coupling_stage_prepare
app_joint_prior_context <- app_joint_coupling_context
app_joint_prior_controls <- app_joint_coupling_controls
app_joint_prior_vb <- app_joint_coupling_vb
app_joint_prior_warmup <- app_joint_coupling_warmup
app_joint_prior_select_rows <- app_joint_coupling_select_rows
app_joint_prior_collect <- app_joint_coupling_collect
app_joint_prior_finalize <- app_joint_coupling_finalize
