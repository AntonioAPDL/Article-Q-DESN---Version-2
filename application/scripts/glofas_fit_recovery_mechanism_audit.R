#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/glofas_fit_recovery.R"))
source(app_path("application/R/glofas_fit_recovery_mechanism_audit.R"))
source(app_path("application/R/glofas_fit_recovery_selection.R"))

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_fit_recovery_portability_repair_20260806",
  candidate_id = "fr09_dtau001",
  output_root = "local_trackers/runtime_configs/glofas_fit_recovery_mechanism_audit_20260807",
  history_n = 1000,
  draw_subset = 5
))
resolve_repo <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}
runtime_root <- resolve_repo(args$runtime_root, TRUE)
output_root <- resolve_repo(args$output_root, FALSE)
history_n <- as.integer(args$history_n)
draw_subset <- as.integer(args$draw_subset)
if (!is.finite(history_n) || history_n < 100L) stop("history_n must be at least 100.", call. = FALSE)
if (!is.finite(draw_subset) || draw_subset < 1L) stop("draw_subset must be positive.", call. = FALSE)
for (dir in c("tables", "figures", "manifest")) app_ensure_dir(file.path(output_root, dir))

runtime <- app_read_csv(file.path(runtime_root, "runtime_manifest.csv"))
runtime <- runtime[runtime$base_candidate_id == as.character(args$candidate_id), , drop = FALSE]
runtime <- runtime[order(runtime$origin_date), , drop = FALSE]
if (nrow(runtime) < 2L) stop("The mechanism audit requires at least two completed cutoffs.", call. = FALSE)
if (any(!file.exists(file.path(runtime$run_dir, ".fit_recovery_complete")))) {
  stop("The mechanism audit refuses incomplete source runs.", call. = FALSE)
}

source_rows <- list()
contract_rows <- list()
counterfactual_rows <- list()
counterfactual_horizon_rows <- list()
feature_shift_rows <- list()
state_shift_rows <- list()
contribution_rows <- list()
component_rows <- list()
jacobian_rows <- list()
exact_summary_rows <- list()
exact_horizon_rows <- list()
rhs_rows <- list()

for (i in seq_len(nrow(runtime))) {
  item <- runtime[i, , drop = FALSE]
  cutoff_id <- as.character(item$cutoff_id[[1L]])
  run_dir <- normalizePath(item$run_dir[[1L]], mustWork = TRUE)
  message(sprintf("[mechanism-audit] %s (%d/%d)", cutoff_id, i, nrow(runtime)))
  fit_manifest <- app_read_csv(file.path(run_dir, "manifest", "qdesn_discrepancy_fit_manifest.csv"))
  if (nrow(fit_manifest) != 1L || fit_manifest$status[[1L]] != "completed") {
    stop(sprintf("Cutoff %s lacks one completed fit manifest row.", cutoff_id), call. = FALSE)
  }
  fit_path <- resolve_repo(fit_manifest$fit_object[[1L]], TRUE)
  design_path <- resolve_repo(fit_manifest$design_object[[1L]], TRUE)
  source_rows[[length(source_rows) + 1L]] <- data.frame(
    candidate_id = args$candidate_id,
    cutoff_id = cutoff_id,
    origin_date = item$origin_date[[1L]],
    run_id = item$run_id[[1L]],
    run_dir = run_dir,
    fit_path = fit_path,
    fit_sha256 = app_sha256_file(fit_path),
    design_path = design_path,
    design_sha256 = app_sha256_file(design_path),
    config_path = item$config_path[[1L]],
    config_sha256 = item$config_sha256[[1L]],
    stringsAsFactors = FALSE
  )

  fit <- readRDS(fit_path)
  design <- readRDS(design_path)
  if (!isTRUE(design$two_block_design) || is.null(fit$variational_state$future_linearization)) {
    stop(sprintf("Cutoff %s lacks the required two-block linearized fit contract.", cutoff_id), call. = FALSE)
  }
  linearization <- fit$variational_state$future_linearization
  theta_mean <- as.numeric(fit$variational_state$theta_mean)
  y_mean <- as.numeric(fit$variational_state$y_future_mean)
  horizon <- as.integer(design$future_key$horizon)
  target_date <- as.Date(design$future_key$target_date)
  beta <- theta_mean[design$beta_index]
  alpha <- theta_mean[design$alpha_index]
  beta_info <- design$feature_info_beta %||% design$feature_info
  alpha_info <- design$feature_info_alpha %||% design$feature_info
  history_index <- tail(seq_len(nrow(design$X_beta)), min(history_n, nrow(design$X_beta)))

  contract_rows[[length(contract_rows) + 1L]] <- data.frame(
    candidate_id = args$candidate_id,
    cutoff_id = cutoff_id,
    origin_date = item$origin_date[[1L]],
    quantile_level = fit_manifest$quantile_level[[1L]],
    two_block_design = isTRUE(design$two_block_design),
    design_version = design$design_version,
    feature_strategy = design$feature_strategy,
    discrepancy_transition_strategy = design$discrepancy_transition_strategy %||% "recursive_level",
    future_update_strategy = fit$vb_diagnostics$future_update_strategy,
    future_moment_strategy = fit$vb_diagnostics$future_moment_strategy,
    n_future = length(horizon),
    n_beta_features = length(design$beta_index),
    n_alpha_features = length(design$alpha_index),
    prediction_identity = "q_y = q_g - d_g",
    stringsAsFactors = FALSE
  )

  paths <- list(vb_future_mean = y_mean)
  if (all(is.finite(as.numeric(design$y_future_oracle)))) {
    paths$observed_future_oracle_diagnostic <- as.numeric(design$y_future_oracle)
  }
  exact_designs <- list()
  for (path_name in names(paths)) {
    exact <- app_glofas_mechanism_exact_future_design(design, paths[[path_name]])
    exact_designs[[path_name]] <- exact
    X_beta <- as.matrix(exact$X_beta_future)
    X_alpha <- as.matrix(exact$X_alpha_future)
    feature_shift_rows[[length(feature_shift_rows) + 1L]] <- cbind(
      data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id),
      app_glofas_mechanism_shift(
        design$X_beta[history_index, , drop = FALSE], X_beta, beta_info,
        "beta_readout", path_name, horizon
      )
    )
    feature_shift_rows[[length(feature_shift_rows) + 1L]] <- cbind(
      data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id),
      app_glofas_mechanism_shift(
        design$X_alpha[history_index, , drop = FALSE], X_alpha, alpha_info,
        "alpha_readout", path_name, horizon
      )
    )
    if (!is.null(design$X_core_beta) && !is.null(exact$continuation_beta$X_future_core)) {
      state_shift_rows[[length(state_shift_rows) + 1L]] <- cbind(
        data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id),
        app_glofas_mechanism_state_shift(
          design$X_core_beta[history_index, , drop = FALSE], exact$continuation_beta$X_future_core,
          "beta_reservoir", path_name, horizon
        )
      )
    }
    if (!is.null(design$X_core_alpha) && !is.null(exact$continuation_alpha$X_future_core)) {
      state_shift_rows[[length(state_shift_rows) + 1L]] <- cbind(
        data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id),
        app_glofas_mechanism_state_shift(
          design$X_core_alpha[history_index, , drop = FALSE], exact$continuation_alpha$X_future_core,
          "alpha_reservoir", path_name, horizon
        )
      )
    }
    contribution_rows[[length(contribution_rows) + 1L]] <- cbind(
      data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id),
      app_glofas_mechanism_contributions(X_beta, beta, beta_info, "q_y", path_name, horizon)
    )
    contribution_rows[[length(contribution_rows) + 1L]] <- cbind(
      data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id),
      app_glofas_mechanism_contributions(X_alpha, alpha, alpha_info, "d_g", path_name, horizon)
    )
    discrepancy_baseline <- as.numeric(
      exact$discrepancy_baseline_future %||% rep(0, nrow(X_alpha))
    )
    if (any(discrepancy_baseline != 0)) {
      contribution_rows[[length(contribution_rows) + 1L]] <- data.frame(
        candidate_id = args$candidate_id,
        cutoff_id = cutoff_id,
        component = "d_g",
        path_name = path_name,
        horizon = horizon,
        feature_group = "persistence_baseline",
        contribution = discrepancy_baseline,
        stringsAsFactors = FALSE
      )
    }
    q_y <- as.numeric(X_beta %*% beta)
    d_g <- discrepancy_baseline + as.numeric(X_alpha %*% alpha)
    component_rows[[length(component_rows) + 1L]] <- data.frame(
      candidate_id = args$candidate_id,
      cutoff_id = cutoff_id,
      path_name = path_name,
      target_date = target_date,
      horizon = horizon,
      q_y_theta_mean = q_y,
      d_g_theta_mean = d_g,
      q_g_theta_mean = q_y + d_g,
      latent_y_path = paths[[path_name]],
      stringsAsFactors = FALSE
    )
  }

  jacobian_rows[[length(jacobian_rows) + 1L]] <- cbind(
    data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id),
    app_glofas_mechanism_jacobian(linearization, "beta", horizon)
  )
  jacobian_rows[[length(jacobian_rows) + 1L]] <- cbind(
    data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id),
    app_glofas_mechanism_jacobian(linearization, "alpha", horizon)
  )

  theta_draws <- as.matrix(fit$draws$theta)
  y_draws <- as.matrix(fit$draws$y_future)
  draw_indices <- app_glofas_mechanism_draw_indices(nrow(y_draws), draw_subset)
  for (draw_index in draw_indices) {
    message(sprintf("[mechanism-audit] %s exact draw %d", cutoff_id, draw_index))
    X_beta_linear <- app_glofas_mechanism_linearized_design(linearization, y_draws[draw_index, ], "beta")
    X_alpha_linear <- app_glofas_mechanism_linearized_design(linearization, y_draws[draw_index, ], "alpha")
    exact <- app_glofas_mechanism_exact_future_design(design, y_draws[draw_index, ])
    draw_beta <- theta_draws[draw_index, design$beta_index]
    draw_alpha <- theta_draws[draw_index, design$alpha_index]
    q_y_linear <- as.numeric(X_beta_linear %*% draw_beta)
    discrepancy_baseline <- as.numeric(
      exact$discrepancy_baseline_future %||% rep(0, nrow(exact$X_alpha_future))
    )
    d_g_linear <- discrepancy_baseline + as.numeric(X_alpha_linear %*% draw_alpha)
    q_y_exact <- as.numeric(exact$X_beta_future %*% draw_beta)
    d_g_exact <- discrepancy_baseline + as.numeric(exact$X_alpha_future %*% draw_alpha)
    exact_summary_rows[[length(exact_summary_rows) + 1L]] <- data.frame(
      candidate_id = args$candidate_id,
      cutoff_id = cutoff_id,
      draw_index = draw_index,
      max_abs_q_y_diff = max(abs(q_y_exact - q_y_linear)),
      mean_abs_q_y_diff = mean(abs(q_y_exact - q_y_linear)),
      max_abs_d_g_diff = max(abs(d_g_exact - d_g_linear)),
      mean_abs_d_g_diff = mean(abs(d_g_exact - d_g_linear)),
      stringsAsFactors = FALSE
    )
    exact_horizon_rows[[length(exact_horizon_rows) + 1L]] <- data.frame(
      candidate_id = args$candidate_id,
      cutoff_id = cutoff_id,
      draw_index = draw_index,
      target_date = target_date,
      horizon = horizon,
      q_y_linearized = q_y_linear,
      q_y_exact = q_y_exact,
      d_g_linearized = d_g_linear,
      d_g_exact = d_g_exact,
      stringsAsFactors = FALSE
    )
  }

  scored <- app_read_csv(file.path(run_dir, "tables", "score_by_quantile.csv"))
  q_scored <- scored[scored$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  raw_scored <- scored[scored$model_family == "raw_glofas", , drop = FALSE]
  raw_scored <- raw_scored[match(as.Date(q_scored$target_date), as.Date(raw_scored$target_date)), , drop = FALSE]
  discrepancy_history <- app_read_csv(file.path(run_dir, "tables", "post_fit_discrepancy_history_summary.csv"))
  discrepancy_history <- discrepancy_history[is.finite(discrepancy_history$observed_discrepancy), , drop = FALSE]
  discrepancy_history <- discrepancy_history[order(as.Date(discrepancy_history$target_date)), , drop = FALSE]
  last_discrepancy <- tail(discrepancy_history$observed_discrepancy, 1L)
  scores <- app_glofas_mechanism_score_paths(
    q_scored$y_reference, raw_scored$qhat, q_scored$q_g_hat, q_scored$qhat,
    last_discrepancy, tau = 0.5
  )
  counterfactual_rows[[length(counterfactual_rows) + 1L]] <- cbind(
    data.frame(candidate_id = args$candidate_id, cutoff_id = cutoff_id, last_observed_discrepancy = last_discrepancy),
    scores
  )
  path_values <- list(
    raw_glofas = as.numeric(raw_scored$qhat),
    reference_only = as.numeric(q_scored$q_g_hat),
    discrepancy_persistence = as.numeric(q_scored$q_g_hat) - last_discrepancy,
    learned_discrepancy = as.numeric(q_scored$qhat)
  )
  counterfactual_horizon_rows[[length(counterfactual_horizon_rows) + 1L]] <- app_bind_rows_fill(
    lapply(names(path_values), function(path_name) data.frame(
      candidate_id = args$candidate_id,
      cutoff_id = cutoff_id,
      target_date = as.Date(q_scored$target_date),
      horizon = as.integer(q_scored$horizon),
      path = path_name,
      prediction = path_values[[path_name]],
      observed = as.numeric(q_scored$y_reference),
      absolute_error = abs(path_values[[path_name]] - as.numeric(q_scored$y_reference)),
      stringsAsFactors = FALSE
    ))
  )

  prior_beta <- fit$variational_state$prior$blocks$beta$state
  prior_alpha <- fit$variational_state$prior$blocks$alpha$state
  rhs_rows[[length(rhs_rows) + 1L]] <- data.frame(
    candidate_id = args$candidate_id,
    cutoff_id = cutoff_id,
    beta_tau0 = prior_beta$tau0,
    alpha_tau0 = prior_alpha$tau0,
    beta_e_inv_tau2 = prior_beta$e_inv_tau2,
    alpha_e_inv_tau2 = prior_alpha$e_inv_tau2,
    beta_coefficient_norm = sqrt(sum(beta^2)),
    alpha_coefficient_norm = sqrt(sum(alpha^2)),
    alpha_max_abs_coefficient = max(abs(alpha)),
    stringsAsFactors = FALSE
  )
  rm(fit, design, exact_designs, theta_draws, y_draws)
  invisible(gc())
}

tables <- list(
  source_manifest = app_bind_rows_fill(source_rows),
  contract = app_bind_rows_fill(contract_rows),
  counterfactual_scores = app_bind_rows_fill(counterfactual_rows),
  counterfactual_by_horizon = app_bind_rows_fill(counterfactual_horizon_rows),
  feature_shift = app_bind_rows_fill(feature_shift_rows),
  state_shift = app_bind_rows_fill(state_shift_rows),
  contributions = app_bind_rows_fill(contribution_rows),
  component_paths = app_bind_rows_fill(component_rows),
  jacobian = app_bind_rows_fill(jacobian_rows),
  exact_draw_summary = app_bind_rows_fill(exact_summary_rows),
  exact_draw_by_horizon = app_bind_rows_fill(exact_horizon_rows),
  rhs_state = app_bind_rows_fill(rhs_rows)
)
decision <- app_glofas_mechanism_decision(
  tables$exact_draw_summary, tables$state_shift, tables$feature_shift,
  tables$counterfactual_scores
)
decision$next_experiment <- switch(
  decision$primary_mechanism[[1L]],
  prediction_linearization = "Validate exact-rebuild prediction, then qualify an exact future-state update.",
  discrepancy_state_or_readout_extrapolation = "Test a persistence-anchored discrepancy transition while holding the reference block fixed.",
  discrepancy_transition_misspecification = "Test a persistence-anchored discrepancy transition while holding the reference block fixed.",
  "Add blocked cutoffs before fitting another model grid."
)
tables$mechanism_decision <- decision
for (name in names(tables)) app_write_csv(tables[[name]], file.path(output_root, "tables", paste0(name, ".csv")))

path_plot <- ggplot2::ggplot(
  tables$counterfactual_by_horizon,
  ggplot2::aes(target_date, prediction, color = path, linetype = path)
) +
  ggplot2::geom_line(linewidth = 0.6) +
  ggplot2::geom_point(
    data = unique(tables$counterfactual_by_horizon[c("cutoff_id", "target_date", "observed")]),
    mapping = ggplot2::aes(x = target_date, y = observed),
    color = "#111111", inherit.aes = FALSE, size = 1.2
  ) +
  ggplot2::facet_wrap(~cutoff_id, scales = "free_x", ncol = 1L) +
  ggplot2::scale_color_manual(values = c(
    raw_glofas = "#3B6FB6", reference_only = "#2A9D6F",
    discrepancy_persistence = "#7A5195", learned_discrepancy = "#C23B32"
  )) +
  ggplot2::labs(x = NULL, y = "log(1 + streamflow)", color = NULL, linetype = NULL) +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

alpha_contributions <- tables$contributions[
  tables$contributions$component == "d_g" & tables$contributions$path_name == "vb_future_mean", , drop = FALSE
]
contribution_plot <- ggplot2::ggplot(
  alpha_contributions,
  ggplot2::aes(horizon, contribution, color = feature_group)
) +
  ggplot2::geom_hline(yintercept = 0, color = "grey70", linewidth = 0.3) +
  ggplot2::geom_line(linewidth = 0.65) +
  ggplot2::facet_wrap(~cutoff_id, ncol = 1L) +
  ggplot2::labs(x = "Forecast horizon", y = "Contribution to discrepancy", color = NULL) +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

shift_plot_data <- rbind(
  data.frame(
    tables$state_shift[c("cutoff_id", "path_name", "horizon")],
    diagnostic = tables$state_shift$block,
    max_abs_z = tables$state_shift$max_abs_z
  ),
  data.frame(
    tables$feature_shift[c("cutoff_id", "path_name", "horizon")],
    diagnostic = paste(tables$feature_shift$block, tables$feature_shift$feature_group, sep = ":"),
    max_abs_z = tables$feature_shift$max_abs_z
  )
)
shift_plot_data <- shift_plot_data[shift_plot_data$path_name == "vb_future_mean", , drop = FALSE]
shift_plot <- ggplot2::ggplot(shift_plot_data, ggplot2::aes(horizon, max_abs_z, color = diagnostic)) +
  ggplot2::geom_hline(yintercept = 5, linetype = "dashed", color = "#C23B32", linewidth = 0.4) +
  ggplot2::geom_line(linewidth = 0.55) +
  ggplot2::facet_wrap(~cutoff_id, scales = "free_y", ncol = 1L) +
  ggplot2::labs(x = "Forecast horizon", y = "Maximum absolute historical z-score", color = NULL) +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

exact_plot <- ggplot2::ggplot(
  tables$exact_draw_by_horizon,
  ggplot2::aes(horizon, abs(d_g_exact - d_g_linearized), group = factor(draw_index), color = factor(draw_index))
) +
  ggplot2::geom_hline(yintercept = 0.05, linetype = "dashed", color = "#C23B32", linewidth = 0.4) +
  ggplot2::geom_line(linewidth = 0.5) +
  ggplot2::facet_wrap(~cutoff_id, ncol = 1L) +
  ggplot2::labs(x = "Forecast horizon", y = "|exact - linearized discrepancy|", color = "Draw") +
  ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(legend.position = "bottom", panel.grid.minor = ggplot2::element_blank())

plots <- list(
  counterfactual_forecast_paths = path_plot,
  discrepancy_contributions = contribution_plot,
  future_state_and_feature_shift = shift_plot,
  exact_vs_linearized_discrepancy = exact_plot
)
for (name in names(plots)) {
  for (extension in c("pdf", "png")) {
    app_glofas_selection_save_plot(
      plots[[name]], file.path(output_root, "figures", paste0(name, ".", extension)),
      width = 9, height = 5.8
    )
  }
}

app_write_git_state(file.path(output_root, "manifest", "git_state.txt"))
app_write_session_info(file.path(output_root, "manifest", "session_info.txt"))
writeLines(c(
  "GloFAS fit-recovery mechanism audit completed.",
  paste("Candidate:", args$candidate_id),
  paste("Primary mechanism:", decision$primary_mechanism[[1L]]),
  paste("Next experiment:", decision$next_experiment[[1L]]),
  "No broad grid or full-seven fit is authorized by this audit."
), file.path(output_root, "AUDIT_COMPLETE.txt"))
artifacts <- c(
  list.files(file.path(output_root, "tables"), full.names = TRUE),
  list.files(file.path(output_root, "figures"), full.names = TRUE),
  list.files(file.path(output_root, "manifest"), full.names = TRUE),
  file.path(output_root, "AUDIT_COMPLETE.txt")
)
app_write_csv(data.frame(
  path = artifacts,
  size_bytes = as.numeric(file.info(artifacts)$size),
  sha256 = vapply(artifacts, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
), file.path(output_root, "artifact_manifest.csv"))
cat(file.path(output_root, "tables", "mechanism_decision.csv"), "\n")
