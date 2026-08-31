#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/", mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."),
                           winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- which(args == flag)
  if (!length(at) || at[[1L]] == length(args)) return(default)
  args[[at[[1L]] + 1L]]
}

resolve_path <- function(path, must_work = TRUE) {
  path <- as.character(path)[[1L]]
  if (!grepl("^/", path)) path <- file.path(repo_root, path)
  normalizePath(path, winslash = "/", mustWork = must_work)
}

article_path <- function(relative, must_work = FALSE) {
  if (length(relative) != 1L || is.na(relative) || !nzchar(relative) ||
      grepl("^/", relative) || grepl("(^|/)\\.\\.(/|$)", relative)) {
    stop("Article path must be a portable path inside the repository.",
         call. = FALSE)
  }
  path <- file.path(repo_root, relative)
  if (must_work) return(normalizePath(path, winslash = "/", mustWork = TRUE))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, na = "")

if (!requireNamespace("ggplot2", quietly = TRUE) ||
    !requireNamespace("grid", quietly = TRUE)) {
  stop("The ggplot2 and grid packages are required.", call. = FALSE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_mcmc_readiness.R", "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_qdesn_phase153_balanced_independent_replication.R",
  "joint_qdesn_phase154_mcmc_evidence_reconciliation.R",
  "joint_qdesn_phase155_article_promotion.R", "latent_path_design.R",
  "joint_exqdesn_phase151_feature_design_screening.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R",
  "joint_exqdesn_phase164_165_readiness.R",
  "joint_exqdesn_phase166_168_structured_vb.R",
  "joint_exqdesn_phase167_169_mcmc_method_selection.R",
  "joint_exqdesn_phase169r_recovery.R",
  "joint_exqdesn_phase170_default_promotion.R",
  "joint_exqdesn_phase171_175_article_confirmation.R",
  "joint_exqdesn_phase176_180_post_m0_recovery.R",
  "joint_qdesn_dgp_integrated_acrps.R",
  "joint_qdesn_phase179_dgp_score_confirmation.R",
  "joint_qdesn_vb_spec_screening.R",
  "joint_qdesn_phase180_balanced_dgp_score_packet.R",
  "joint_qdesn_phase181_score_stability_extension.R"
)) source(app_path("application/R", file))

default_packet_root <- file.path(
  repo_root, "application/cache",
  "joint_qdesn_phase181_score_stability_extension_packet_20260826"
)
if (!dir.exists(default_packet_root)) {
  default_packet_root <- file.path(
    "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache",
    "joint_qdesn_phase181_score_stability_extension_packet_20260826"
  )
}
default_fixture_root <- file.path(
  repo_root, "application/cache",
  "joint_qdesn_phase180_article_fixture_shards_20260824"
)
if (!dir.exists(default_fixture_root)) {
  default_fixture_root <- file.path(
    "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache",
    "joint_qdesn_phase180_article_fixture_shards_20260824"
  )
}

packet_root <- resolve_path(arg_value("--packet-root", default_packet_root))
fixture_root <- resolve_path(arg_value("--fixture-root", default_fixture_root))
out_dir <- article_path(arg_value(
  "--figure-dir", "figures/joint_qdesn_simulation"
))

score_contract <- app_joint_qdesn_postscore_read_contract(
  app_path("application/config/joint_qdesn_post_phase178_dgp_score_contract_v1.csv")
)
extension_contract <- app_joint_qdesn_phase181_read_contract()
draws_per_chain <- as.integer(arg_value(
  "--draws-per-chain", extension_contract$score_draws_per_chain
))
if (draws_per_chain != score_contract$score_draws_per_chain ||
    draws_per_chain != 1000L) {
  stop("The figure builder must use the 1000-draw Phase181 score convention.",
       call. = FALSE)
}
pairing_seed <- score_contract$primary_pairing_seed

required_packet_files <- c(
  final_selected_source_registry = "final_selected_source_registry.csv",
  posterior_dgp_integrated_acrps_summary =
    "posterior_dgp_integrated_acrps_summary.csv",
  oracle_recovery_diagnostics = "oracle_recovery_diagnostics.csv",
  artifact_manifest = "artifact_manifest.csv"
)
for (path in required_packet_files) {
  if (!file.exists(file.path(packet_root, path))) {
    stop("Missing Phase181 packet file: ", path, call. = FALSE)
  }
}

packet_manifest_sha <- sha256(file.path(packet_root, "artifact_manifest.csv"))
fixture_manifest <- file.path(fixture_root, "manifest.csv")
fixture_manifest_sha <- if (file.exists(fixture_manifest)) {
  sha256(fixture_manifest)
} else {
  NA_character_
}

source_registry <- read.csv(
  file.path(packet_root, "final_selected_source_registry.csv"),
  stringsAsFactors = FALSE, check.names = FALSE
)
forecast_summary <- read.csv(
  file.path(packet_root, "posterior_dgp_integrated_acrps_summary.csv"),
  stringsAsFactors = FALSE, check.names = FALSE
)
oracle_point <- read.csv(
  file.path(packet_root, "oracle_recovery_diagnostics.csv"),
  stringsAsFactors = FALSE, check.names = FALSE
)

required_registry <- c(
  "mcmc_case_id", "scenario_id", "source_model_id", "likelihood_family",
  "fit_structure", "chain_id", "chain_seed", "worker_output_dir",
  "source_kind"
)
required_forecast <- c(
  "mcmc_case_id", "scenario_id", "source_model_id", "likelihood_family",
  "fit_structure", "posterior_score_mean", "posterior_score_median",
  "posterior_score_q025", "posterior_score_q975", "expected_oracle_acrps",
  "canonical_action_dgp_integrated_acrps", "canonical_raw_crossing_pairs",
  "canonical_contract_crossing_pairs", "raw_crossing_opportunities",
  "display_label"
)
required_oracle <- c(
  "case_id", "scenario_id", "source_model_id", "likelihood_family",
  "fit_structure", "window", "oracle_quantile_rmse", "raw_crossing_pairs",
  "contract_crossing_pairs"
)
if (!all(required_registry %in% names(source_registry)) ||
    !all(required_forecast %in% names(forecast_summary)) ||
    !all(required_oracle %in% names(oracle_point))) {
  stop("Phase181 packet files do not contain the expected columns.",
       call. = FALSE)
}

model_order <- c(
  "joint_qdesn_rhs_vb",
  "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb",
  "exqdesn_rhs_independent_vb"
)
model_labels <- c(
  joint_qdesn_rhs_vb = "Joint Q--DESN (AL--RHS)",
  qdesn_rhs_independent_vb = "Independent Q--DESN (AL--RHS)",
  joint_exqdesn_rhs_vb = "Joint exQDESN (exAL--RHS)",
  exqdesn_rhs_independent_vb = "Independent exQDESN (exAL--RHS)"
)
scenario_order <- c(
  "asymmetric_laplace_tail",
  "gaussian_mixture_bridge",
  "laplace_bridge",
  "nonlinear_reservoir_friendly",
  "normal_bridge",
  "persistent_heavy_tail",
  "regime_shift",
  "student_t_location_scale"
)
scenario_labels <- c(
  asymmetric_laplace_tail = "Asymmetric-Laplace tail",
  gaussian_mixture_bridge = "Gaussian-mixture innovations",
  laplace_bridge = "Laplace innovations",
  nonlinear_reservoir_friendly = "Nonlinear reservoir dynamics",
  normal_bridge = "Gaussian innovations",
  persistent_heavy_tail = "Persistent heavy tails",
  regime_shift = "Regime shift",
  student_t_location_scale = "Student-t location-scale"
)

if (nrow(forecast_summary) != 32L ||
    !setequal(forecast_summary$scenario_id, scenario_order) ||
    !setequal(forecast_summary$source_model_id, model_order) ||
    any(table(forecast_summary$scenario_id) != 4L) ||
    any(table(forecast_summary$source_model_id) != 8L) ||
    nrow(source_registry) != 256L ||
    any(table(source_registry$mcmc_case_id) != 8L)) {
  stop("The Phase181 model-by-scenario surface is not the expected 32-cell grid.",
       call. = FALSE)
}

source_case_ids <- unique(source_registry$mcmc_case_id)
score_case_ids <- unique(forecast_summary$mcmc_case_id)
if (!setequal(source_case_ids, score_case_ids)) {
  stop("Source registry and score summary case identifiers differ.",
       call. = FALSE)
}

fit_draw_summary_one <- function(jobs) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  if (!identical(as.integer(jobs$chain_id), seq_len(nrow(jobs)))) {
    stop("Each Phase181 cell must have chain ids 1 through 8.", call. = FALSE)
  }
  loaded <- app_joint_qdesn_phase180_load_fixture(
    jobs$scenario_id[[1L]], fixture_root
  )
  fixture <- loaded$fixture
  K <- length(fixture$tau)
  p <- ncol(fixture$Z)
  if (!identical(as.numeric(fixture$tau), as.numeric(score_contract$tau))) {
    stop("Fixture quantile grid does not match the score contract.",
         call. = FALSE)
  }
  fits <- app_joint_qdesn_phase180_score_fit_loader(jobs, fixture, list())
  X <- cbind(intercept = 1, fixture$Z)
  truth <- as.matrix(fixture$true_q)
  if (nrow(truth) != nrow(X) || ncol(truth) != K) {
    stop("Fixture truth and design dimensions do not align.", call. = FALSE)
  }
  draw_rows <- lapply(seq_along(fits), function(ii) {
    fit <- fits[[ii]]
    chain_id <- as.integer(jobs$chain_id[[ii]])
    if (ncol(fit$beta_draws) != K * p || ncol(fit$alpha_draws) != K) {
      stop("Posterior draw dimensions do not match the fixture.",
           call. = FALSE)
    }
    n_keep <- nrow(fit$beta_draws)
    selected <- app_joint_qdesn_postscore_even_indices(n_keep, draws_per_chain)
    index_by_tau <- app_joint_qdesn_postscore_per_tau_indices(
      selected, K, jobs$fit_structure[[1L]], pairing_seed, chain_id
    )
    B <- length(selected)
    q_raw <- matrix(NA_real_, nrow = nrow(X) * B, ncol = K)
    for (kk in seq_len(K)) {
      source_index <- index_by_tau[[kk]]
      beta_index <- ((kk - 1L) * p + 1L):(kk * p)
      theta <- cbind(
        fit$alpha_draws[source_index, kk],
        fit$beta_draws[source_index, beta_index, drop = FALSE]
      )
      q_raw[, kk] <- as.vector(X %*% t(theta))
    }
    monotone <- app_joint_qdesn_postscore_contract_rows(q_raw, fixture$tau)
    q_contract <- monotone$q_contract
    sq_sum <- abs_sum <- signed_sum <- numeric(B)
    for (kk in seq_len(K)) {
      q_mat <- matrix(q_contract[, kk], nrow = nrow(X), ncol = B)
      err <- q_mat - truth[, kk]
      sq_sum <- sq_sum + colSums(err^2)
      abs_sum <- abs_sum + colSums(abs(err))
      signed_sum <- signed_sum + colSums(err)
    }
    data.frame(
      chain_id = chain_id,
      draw_position = seq_len(B),
      retained_draw_index = selected,
      fit_rmse = sqrt(sq_sum / (nrow(X) * K)),
      fit_mae = abs_sum / (nrow(X) * K),
      fit_bias = signed_sum / (nrow(X) * K),
      stringsAsFactors = FALSE
    )
  })
  draw_data <- do.call(rbind, draw_rows)
  data.frame(
    mcmc_case_id = jobs$mcmc_case_id[[1L]],
    scenario_id = jobs$scenario_id[[1L]],
    source_model_id = jobs$source_model_id[[1L]],
    likelihood_family = jobs$likelihood_family[[1L]],
    fit_structure = jobs$fit_structure[[1L]],
    posterior_mean = mean(draw_data$fit_rmse),
    posterior_median = unname(stats::quantile(draw_data$fit_rmse, 0.50,
                                              type = 8)),
    posterior_q025 = unname(stats::quantile(draw_data$fit_rmse, 0.025,
                                            type = 8)),
    posterior_q975 = unname(stats::quantile(draw_data$fit_rmse, 0.975,
                                            type = 8)),
    n_draws = nrow(draw_data),
    n_chains = length(unique(draw_data$chain_id)),
    draws_per_chain = draws_per_chain,
    stringsAsFactors = FALSE
  )
}

summary_path <- article_path("tables/joint_qdesn_phase181_metric_interval_summary.csv")
reuse_summary <- tolower(arg_value("--reuse-summary", "false")) %in%
  c("true", "t", "1", "yes")

if (reuse_summary && file.exists(summary_path)) {
  metric_summary <- read.csv(
    summary_path, stringsAsFactors = FALSE, check.names = FALSE
  )
} else {
  groups <- split(source_registry, source_registry$mcmc_case_id)
  groups <- groups[score_case_ids]
  fit_summary <- do.call(rbind, lapply(groups, fit_draw_summary_one))
  row.names(fit_summary) <- NULL

  fit_point <- oracle_point[oracle_point$window == "fit", , drop = FALSE]
  forecast_point <- oracle_point[oracle_point$window == "forecast", , drop = FALSE]
  merge_key <- c("scenario_id", "source_model_id", "likelihood_family", "fit_structure")

  fit_summary <- merge(
    fit_summary,
    fit_point[c(merge_key, "oracle_quantile_rmse", "raw_crossing_pairs",
                "contract_crossing_pairs")],
    by = merge_key, all.x = TRUE, sort = FALSE
  )
  forecast_rows <- merge(
    forecast_summary,
    forecast_point[c(merge_key, "oracle_quantile_rmse", "raw_crossing_pairs",
                     "contract_crossing_pairs")],
    by = merge_key, all.x = TRUE, sort = FALSE
  )

  make_metric_rows <- function(data, window) {
    if (identical(window, "fit")) {
      out <- data.frame(
        scenario_id = data$scenario_id,
        source_model_id = data$source_model_id,
        likelihood_family = data$likelihood_family,
        fit_structure = data$fit_structure,
        metric_window = "fit",
        metric_role = "oracle_fit_rmse",
        metric_label = "Fit RMSE against known quantile paths",
        posterior_mean = data$posterior_mean,
        posterior_median = data$posterior_median,
        posterior_q025 = data$posterior_q025,
        posterior_q975 = data$posterior_q975,
        n_draws = data$n_draws,
        n_chains = data$n_chains,
        draws_per_chain = data$draws_per_chain,
        point_reference_value = 0,
        canonical_metric_value = data$oracle_quantile_rmse,
        canonical_raw_crossing_pairs = data$raw_crossing_pairs,
        canonical_rearranged_crossing_pairs = data$contract_crossing_pairs,
        crossing_opportunities_per_scenario = 500L * 6L,
        primary_pairing_seed = pairing_seed,
        packet_manifest_sha256 = packet_manifest_sha,
        fixture_manifest_sha256 = fixture_manifest_sha,
        stringsAsFactors = FALSE
      )
    } else {
      out <- data.frame(
        scenario_id = data$scenario_id,
        source_model_id = data$source_model_id,
        likelihood_family = data$likelihood_family,
        fit_structure = data$fit_structure,
        metric_window = "forecast",
        metric_role = "dgp_integrated_acrps",
        metric_label = "Forecast DGP-integrated aCRPS",
        posterior_mean = data$posterior_score_mean,
        posterior_median = data$posterior_score_median,
        posterior_q025 = data$posterior_score_q025,
        posterior_q975 = data$posterior_score_q975,
        n_draws = 8000L,
        n_chains = 8L,
        draws_per_chain = draws_per_chain,
        point_reference_value = data$expected_oracle_acrps,
        canonical_metric_value = data$canonical_action_dgp_integrated_acrps,
        canonical_raw_crossing_pairs = data$canonical_raw_crossing_pairs,
        canonical_rearranged_crossing_pairs = data$canonical_contract_crossing_pairs,
        crossing_opportunities_per_scenario = 990L * 6L,
        primary_pairing_seed = pairing_seed,
        packet_manifest_sha256 = packet_manifest_sha,
        fixture_manifest_sha256 = fixture_manifest_sha,
        stringsAsFactors = FALSE
      )
    }
    out$model_label <- unname(model_labels[out$source_model_id])
    out$scenario_label <- unname(scenario_labels[out$scenario_id])
    out
  }

  metric_summary <- rbind(
    make_metric_rows(fit_summary, "fit"),
    make_metric_rows(forecast_rows, "forecast")
  )
  metric_summary <- metric_summary[order(
    match(metric_summary$metric_window, c("fit", "forecast")),
    match(metric_summary$scenario_id, scenario_order),
    match(metric_summary$source_model_id, model_order)
  ), , drop = FALSE]
  row.names(metric_summary) <- NULL
  write_csv(metric_summary, summary_path)
}

if (nrow(metric_summary) != 64L ||
    any(!is.finite(metric_summary$posterior_mean)) ||
    any(metric_summary$posterior_q025 > metric_summary$posterior_median) ||
    any(metric_summary$posterior_median > metric_summary$posterior_q975) ||
    any(metric_summary$n_draws != 8000L) ||
    any(metric_summary$n_chains != 8L) ||
    any(metric_summary$canonical_rearranged_crossing_pairs != 0L)) {
  stop("Metric interval summary failed internal validation.", call. = FALSE)
}

expected_crossings <- data.frame(
  metric_window = rep(c("fit", "forecast"), each = length(model_order)),
  source_model_id = rep(model_order, times = 2L),
  raw_total = c(0L, 7L, 0L, 0L, 1L, 25L, 0L, 0L),
  stringsAsFactors = FALSE
)
actual_crossings <- aggregate(
  canonical_raw_crossing_pairs ~ metric_window + source_model_id,
  metric_summary,
  sum
)
actual_crossings <- merge(
  actual_crossings, expected_crossings,
  by = c("metric_window", "source_model_id"), all = TRUE, sort = FALSE
)
if (any(actual_crossings$canonical_raw_crossing_pairs != actual_crossings$raw_total)) {
  stop("Canonical raw crossing totals do not match Phase181 authority.",
       call. = FALSE)
}

plot_interval_figure <- function(data, figure_path, title, x_label, x_digits) {
  data$scenario_label <- factor(
    data$scenario_label, levels = unname(scenario_labels[scenario_order])
  )
  data$model_label <- factor(
    data$model_label, levels = rev(unname(model_labels[model_order]))
  )
  data$cross_label <- paste0("c=", data$canonical_raw_crossing_pairs)
  reference <- unique(data[c("scenario_label", "point_reference_value")])
  palette <- c(
    "Joint Q--DESN (AL--RHS)" = "#0072B2",
    "Independent Q--DESN (AL--RHS)" = "#56B4E9",
    "Joint exQDESN (exAL--RHS)" = "#D55E00",
    "Independent exQDESN (exAL--RHS)" = "#E69F00"
  )
  plot <- ggplot2::ggplot(data, ggplot2::aes(y = model_label)) +
    ggplot2::geom_vline(
      data = reference,
      ggplot2::aes(xintercept = point_reference_value),
      inherit.aes = FALSE, linewidth = 0.30, linetype = "dashed",
      color = "#4A5568"
    ) +
    ggplot2::geom_segment(
      ggplot2::aes(
        x = posterior_q025, xend = posterior_q975,
        yend = model_label, color = model_label
      ),
      linewidth = 1.10, lineend = "round"
    ) +
    ggplot2::geom_point(
      ggplot2::aes(x = posterior_mean, color = model_label),
      shape = 4, stroke = 0.95, size = 2.15
    ) +
    ggplot2::geom_text(
      ggplot2::aes(
        x = Inf, label = cross_label,
        color = model_label
      ),
      hjust = 1.06, size = 2.35, fontface = "plain",
      show.legend = FALSE
    ) +
    ggplot2::facet_wrap(~ scenario_label, ncol = 2, scales = "free_x") +
    ggplot2::scale_color_manual(values = palette, guide = "none") +
    ggplot2::scale_x_continuous(
      breaks = function(lims) pretty(lims, n = 3L),
      labels = function(x) formatC(x, format = "f", digits = x_digits)
    ) +
    ggplot2::labs(
      title = title,
      subtitle = "Posterior means are shown by crosses; horizontal intervals are equal-tailed 95% credible intervals.",
      x = x_label, y = NULL
    ) +
    ggplot2::theme_minimal(base_size = 9.5) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12.5,
                                         color = "#1F252B"),
      plot.subtitle = ggplot2::element_text(size = 8.7, color = "#4A5568",
                                            margin = ggplot2::margin(b = 4)),
      strip.text = ggplot2::element_text(face = "bold", color = "#1F252B",
                                         size = 8.5),
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(linewidth = 0.22,
                                                 color = "#E5E7EB"),
      axis.text.y = ggplot2::element_text(size = 7.3, color = "#1F252B"),
      axis.text.x = ggplot2::element_text(size = 7.2, color = "#374151"),
      axis.title.x = ggplot2::element_text(size = 8.5, color = "#1F252B",
                                           margin = ggplot2::margin(t = 5)),
      panel.spacing.x = grid::unit(0.72, "lines"),
      panel.spacing.y = grid::unit(0.82, "lines"),
      plot.margin = ggplot2::margin(8, 9, 8, 8)
    )
  ggplot2::ggsave(
    filename = figure_path, plot = plot, device = grDevices::cairo_pdf,
    width = 7.2, height = 8.25, units = "in", bg = "white"
  )
  invisible(figure_path)
}

fit_fig <- file.path(
  out_dir, "joint_qdesn_phase181_fit_oracle_rmse_intervals.pdf"
)
forecast_fig <- file.path(
  out_dir, "joint_qdesn_phase181_forecast_dgp_score_intervals.pdf"
)

plot_interval_figure(
  metric_summary[metric_summary$metric_window == "fit", , drop = FALSE],
  fit_fig,
  "Joint simulation: fit-period quantile-path recovery",
  "RMSE against the known conditional quantile paths",
  x_digits = 2L
)
plot_interval_figure(
  metric_summary[metric_summary$metric_window == "forecast", , drop = FALSE],
  forecast_fig,
  "Joint simulation: forecast finite-grid quantile score",
  "DGP-integrated aCRPS",
  x_digits = 3L
)

tex_path <- article_path("tables/joint_qdesn_phase181_interval_figures.tex")
writeLines(c(
  "\\begin{figure}[!htbp]",
  "\\centering",
  "\\includegraphics[width=0.98\\textwidth]{figures/joint_qdesn_simulation/joint_qdesn_phase181_fit_oracle_rmse_intervals.pdf}",
  "\\caption{Posterior fit-period recovery of the known conditional quantile paths in the joint multi-quantile simulation. Each panel uses the same four model classes and the same seven quantile levels. Crosses show posterior means and horizontal bars show equal-tailed 95\\% credible intervals computed from 8,000 retained MCMC draws per comparison after monotone rearrangement. Lower RMSE is better. The labels at the right of each panel report raw adjacent-level crossing counts in the posterior-mean fitted grid before monotone rearrangement; all corresponding counts after rearrangement are zero. Panel-specific x-scales are used for readability.}",
  "\\label{fig:joint-qdesn-phase181-fit-rmse-intervals}",
  "\\end{figure}",
  "",
  "\\begin{figure}[!htbp]",
  "\\centering",
  "\\includegraphics[width=0.98\\textwidth]{figures/joint_qdesn_simulation/joint_qdesn_phase181_forecast_dgp_score_intervals.pdf}",
  "\\caption{Posterior DGP-integrated finite-grid quantile scores for the joint multi-quantile simulation. Each panel uses the same four model classes, the same held-out forecast design, and the same seven evaluation levels as Table~\\ref{tab:joint-qdesn-dgp-integrated-score}. Crosses show posterior means and horizontal bars show equal-tailed 95\\% credible intervals from 8,000 retained MCMC draws per comparison. Lower \\(\\aCRPS\\) is better. Dashed vertical lines mark the oracle finite-grid score in each simulation setting. The labels at the right of each panel report raw adjacent-level crossing counts in the posterior-mean forecast grid before monotone rearrangement; all corresponding counts after rearrangement are zero. The numerical rankings remain descriptive because all paired joint-minus-independent contrast intervals include zero. Panel-specific x-scales are used for readability.}",
  "\\label{fig:joint-qdesn-phase181-forecast-acrps-intervals}",
  "\\end{figure}"
), tex_path)

article_files_path <- article_path("overleaf/article_files.txt", must_work = TRUE)
article_files <- readLines(article_files_path, warn = FALSE)
article_files <- unique(c(
  article_files,
  "figures/joint_qdesn_simulation/joint_qdesn_phase181_fit_oracle_rmse_intervals.pdf",
  "figures/joint_qdesn_simulation/joint_qdesn_phase181_forecast_dgp_score_intervals.pdf",
  "tables/joint_qdesn_phase181_interval_figures.tex"
))
header <- article_files[grepl("^#", article_files)]
body <- setdiff(article_files[nzchar(article_files) & !grepl("^#", article_files)], header)
writeLines(c(header, sort(body)), article_files_path)

main_path <- article_path("main.tex", must_work = TRUE)
main_text <- paste(readLines(main_path, warn = FALSE), collapse = "\n")
old <- "\\input{tables/joint_qdesn_phase181_dgp_integrated_score_table.tex}\n\nTable~\\ref{tab:joint-qdesn-dgp-integrated-score}"
new <- "\\input{tables/joint_qdesn_phase181_dgp_integrated_score_table.tex}\n\nFigures~\\ref{fig:joint-qdesn-phase181-fit-rmse-intervals} and\n\\ref{fig:joint-qdesn-phase181-forecast-acrps-intervals} give the corresponding\nposterior uncertainty summaries for fit-period path recovery and forecast\nfinite-grid scoring, using the same model classes and simulation settings as\nTable~\\ref{tab:joint-qdesn-dgp-integrated-score}.\n\n\\input{tables/joint_qdesn_phase181_interval_figures.tex}\n\nTable~\\ref{tab:joint-qdesn-dgp-integrated-score}"
if (!grepl(old, main_text, fixed = TRUE)) {
  if (!grepl("\\\\input\\{tables/joint_qdesn_phase181_interval_figures.tex\\}",
             main_text)) {
    stop("Could not locate insertion point in main.tex.", call. = FALSE)
  }
} else {
  main_text <- sub(old, new, main_text, fixed = TRUE)
  writeLines(strsplit(main_text, "\n", fixed = TRUE)[[1L]], main_path)
}

manifest_path <- article_path(
  "tables/joint_qdesn_phase181_article_asset_manifest.csv", must_work = TRUE
)
manifest <- read.csv(manifest_path, stringsAsFactors = FALSE, check.names = FALSE)
new_manifest <- data.frame(
  artifact_id = c(
    "metric_interval_summary",
    "fit_rmse_interval_figure",
    "forecast_acrps_interval_figure",
    "joint_phase181_interval_figures_tex"
  ),
  role = c("article_source", "main_text_figure", "main_text_figure",
           "main_text_figure_wrapper"),
  source_artifact = c(
    "retained_phase181_posterior_draws_and_scores",
    "joint_qdesn_phase181_metric_interval_summary.csv",
    "joint_qdesn_phase181_metric_interval_summary.csv",
    "joint_qdesn_phase181_interval_figures.tex"
  ),
  tracked_path = c(
    "tables/joint_qdesn_phase181_metric_interval_summary.csv",
    "figures/joint_qdesn_simulation/joint_qdesn_phase181_fit_oracle_rmse_intervals.pdf",
    "figures/joint_qdesn_simulation/joint_qdesn_phase181_forecast_dgp_score_intervals.pdf",
    "tables/joint_qdesn_phase181_interval_figures.tex"
  ),
  source_sha256 = c(
    sha256(summary_path), sha256(summary_path), sha256(summary_path),
    sha256(tex_path)
  ),
  tracked_sha256 = c(
    sha256(summary_path), sha256(fit_fig), sha256(forecast_fig),
    sha256(tex_path)
  ),
  source_commit = rep("3def2d70d6cc71b6a7a72c6fc875d557edb54b9a", 4L),
  scientific_closeout_commit =
    rep("4104f696f4410bbcab49f8d3efd6fef0a7532648", 4L),
  integration_source_commit =
    rep("6655408c3f3829075dc166affe802f4d1b6930df", 4L),
  derivation_note = c(
    "Fit intervals are recomputed from retained Phase181 MCMC coefficient draws; forecast intervals reuse the DGP-integrated score summary.",
    "Generated from joint_qdesn_phase181_metric_interval_summary.csv.",
    "Generated from joint_qdesn_phase181_metric_interval_summary.csv.",
    "Main-text wrapper for the two Phase181 interval figures."
  ),
  stringsAsFactors = FALSE
)
manifest <- manifest[!manifest$artifact_id %in% new_manifest$artifact_id, , drop = FALSE]
manifest <- rbind(manifest, new_manifest)
manifest <- manifest[order(match(manifest$artifact_id, c(
  "scenario_model_summary", "numerical_winner_summary",
  "mean_metric_decisions", "joint_independent_contrasts",
  "supplemental_diagnostics", "crossing_provenance", "wording_guidance",
  "dgp_integrated_score_table", "joint_independent_contrast_table",
  "crossing_summary", "oracle_recovery_table", "metric_interval_summary",
  "fit_rmse_interval_figure", "forecast_acrps_interval_figure",
  "joint_phase181_interval_figures_tex"
))), , drop = FALSE]
write_csv(manifest, manifest_path)

cat(
  "JOINT_QDESN_PHASE181_INTERVAL_FIGURES_BUILT=PASS",
  "rows=64 fit_raw_crossings=0,7,0,0 forecast_raw_crossings=1,25,0,0",
  paste0("summary_sha256=", sha256(summary_path)),
  paste0("fit_pdf_sha256=", sha256(fit_fig)),
  paste0("forecast_pdf_sha256=", sha256(forecast_fig)),
  "\n"
)
