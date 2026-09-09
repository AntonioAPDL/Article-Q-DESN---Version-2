#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- match(flag, args)
  if (is.na(at) || at == length(args)) default else args[[at + 1L]]
}

runtime_root <- normalizePath(arg_value(
  "--runtime-root",
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_article_confirmation_jerez_review_20260908/application/cache/joint_qdesn_shared_backbone_article_confirmation_jerez_20260907"
), mustWork = TRUE)
fit_cores <- as.integer(arg_value("--fit-cores", "4"))
if (!is.finite(fit_cores) || fit_cores < 1L) stop("--fit-cores must be positive.")
reuse_fit_summary <- tolower(arg_value("--reuse-fit-summary", "false")) %in%
  c("true", "t", "1", "yes")

Sys.setenv(
  OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1", NUMEXPR_NUM_THREADS = "1"
)

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("The ggplot2 package is required.", call. = FALSE)
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "latent_path_vb_al.R", "joint_qvp_qdesn.R",
  "joint_qdesn_simulation_readiness.R", "joint_qdesn_simulation_fixtures.R",
  "joint_qdesn_simulation_validation.R", "joint_qdesn_mcmc_readiness.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R",
  "glofas_normal_desn_part1_screening.R", "joint_exqdesn_trace_tools.R",
  "joint_exqdesn_phase156_collapsed_gamma_sigma.R",
  "joint_exqdesn_exact_structured_inference.R",
  "joint_exqdesn_inference_dispatch.R", "joint_qdesn_dgp_integrated_acrps.R",
  "joint_qdesn_shared_backbone_screening.R",
  "joint_qdesn_shared_backbone_quantile_fit.R",
  "joint_qdesn_shared_backbone_family_campaign.R",
  "joint_qdesn_shared_backbone_article_confirmation.R",
  "joint_qdesn_shared_backbone_article_score_packet.R"
)) source(app_path("application/R", path))

packet_root <- file.path(runtime_root, "score_packet")
table_dir <- file.path(repo_root, "tables")
figure_dir <- file.path(repo_root, "figures", "joint_qdesn_simulation")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
read_packet <- function(name) {
  path <- file.path(packet_root, name)
  if (!file.exists(path)) stop("Missing frozen packet file: ", name, call. = FALSE)
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}
write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, na = "")
q8 <- function(x, p) unname(stats::quantile(x, p, type = 8, names = FALSE))

expected_contract_sha <-
  "473c0754c9a1c9a873c4db3b7e61912b57b18c1cac1e146dfd16079185f70600"
if (!identical(sha256(file.path(packet_root, "score_contract.csv")),
               expected_contract_sha)) {
  stop("Frozen Jerez score-contract hash changed.", call. = FALSE)
}
packet_manifest <- read_packet("artifact_manifest.csv")
for (ii in seq_len(nrow(packet_manifest))) {
  path <- file.path(packet_root, packet_manifest$relative_path[[ii]])
  if (!file.exists(path) || file.info(path)$size != packet_manifest$size_bytes[[ii]] ||
      !identical(sha256(path), packet_manifest$sha256[[ii]])) {
    stop("Frozen packet manifest failed for ",
         packet_manifest$relative_path[[ii]], call. = FALSE)
  }
}

score <- read_packet("posterior_dgp_integrated_acrps_summary.csv")
winners <- read_packet("scenario_winner_summary.csv")
contrasts <- read_packet("joint_independent_contrast_summary.csv")
canonical <- read_packet("canonical_action_dgp_integrated_acrps.csv")
oracle <- read_packet("oracle_recovery_summary.csv")
crossings <- read_packet("crossing_and_adjustment_summary.csv")
diagnostics <- read_packet("score_functional_diagnostics.csv")
gamma_sigma <- read_packet("gamma_sigma_diagnostics.csv")
precision <- read_packet("precision_repair_summary.csv")
health <- read_packet("packet_health_summary.csv")

scenario_order <- c(
  "asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
  "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail",
  "regime_shift", "student_t_location_scale"
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
scenario_tex <- c(
  asymmetric_laplace_tail = "Asymmetric-Laplace tail",
  gaussian_mixture_bridge = "Gaussian-mixture innovations",
  laplace_bridge = "Laplace innovations",
  nonlinear_reservoir_friendly = "Nonlinear reservoir dynamics",
  normal_bridge = "Gaussian innovations",
  persistent_heavy_tail = "Persistent heavy tails",
  regime_shift = "Regime shift",
  student_t_location_scale = "Student-\\(t\\) location--scale"
)
model_order <- c(
  "joint_qdesn_rhs_vb", "qdesn_rhs_independent_vb",
  "joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"
)
model_short <- c(
  joint_qdesn_rhs_vb = "Joint AL",
  qdesn_rhs_independent_vb = "Independent AL",
  joint_exqdesn_rhs_vb = "Joint exAL",
  exqdesn_rhs_independent_vb = "Independent exAL"
)
model_tex <- c(
  joint_qdesn_rhs_vb = "Joint Q--DESN \\(\\AL\\)--\\(\\RHS\\)",
  qdesn_rhs_independent_vb = "Independent Q--DESN \\(\\AL\\)--\\(\\RHS\\)",
  joint_exqdesn_rhs_vb = "Joint exQDESN \\(\\exAL\\)--\\(\\RHS\\)",
  exqdesn_rhs_independent_vb = "Independent exQDESN \\(\\exAL\\)--\\(\\RHS\\)"
)

stopifnot(
  nrow(score) == 32L, nrow(winners) == 8L, nrow(contrasts) == 16L,
  setequal(score$scenario_id, scenario_order),
  setequal(score$source_model_id, model_order),
  all(table(score$scenario_id) == 4L),
  all(score$contract_crossing_pairs == 0L),
  all(is.finite(score$posterior_score_mean)),
  sum(winners$winner_source_model_id == "exqdesn_rhs_independent_vb") == 7L,
  sum(winners$winner_source_model_id == "joint_exqdesn_rhs_vb") == 1L,
  sum(contrasts$score_delta_q025 > 0) == 5L,
  sum(contrasts$score_delta_q025 <= 0 & contrasts$score_delta_q975 >= 0) == 11L,
  all(contrasts$score_delta_q975 >= 0),
  sum(score$score_functional_status == "pass") == 21L,
  sum(score$score_functional_status == "review") == 11L,
  sum(score$coherence_status == "pass") == 4L,
  sum(score$coherence_status == "review") == 28L,
  all(gamma_sigma$diagnostic_status == "review_level_retained"),
  health$status[[1L]] == "READY_FOR_MUSCAT_TRANSFER_AND_INTEGRATION_REVIEW"
)

contract <- app_joint_article_score_read_contract(
  file.path(packet_root, "score_contract.csv")
)
plan <- read.csv(file.path(runtime_root, "mcmc_worker_plan.csv"),
                 stringsAsFactors = FALSE, check.names = FALSE)
plan <- plan[order(plan$cell_index, plan$chain_id), , drop = FALSE]
plan$design_path <- file.path(
  runtime_root, "designs",
  sprintf("%02d_%s.rds", plan$scenario_order, plan$scenario_id)
)
groups <- split(plan, factor(plan$model_cell_id,
                             levels = unique(plan$model_cell_id)))
if (length(groups) != 32L || nrow(plan) != 160L) {
  stop("Jerez MCMC plan is not the expected 32-cell, 160-worker design.")
}

fit_draws_one_chain <- function(root, job, contract, design) {
  fit <- app_joint_article_score_read_fit(root, job, contract)
  selected <- app_joint_qdesn_postscore_even_indices(
    nrow(fit$beta_draws), contract$score_draws_per_chain
  )
  index_by_tau <- app_joint_qdesn_postscore_per_tau_indices(
    selected, length(design$tau), job$fit_structure[[1L]],
    contract$primary_pairing_seed, job$chain_id[[1L]]
  )
  Z <- design$Z[design$fit_local, , drop = FALSE]
  truth <- design$true_q[design$fit_local, , drop = FALSE]
  n <- nrow(Z)
  K <- length(design$tau)
  p <- ncol(Z)
  B <- length(selected)
  rmse <- mae <- numeric(B)
  chunks <- split(seq_len(B), ceiling(seq_len(B) / 75L))
  for (chunk in chunks) {
    q_raw <- matrix(NA_real_, nrow = n * length(chunk), ncol = K)
    for (kk in seq_len(K)) {
      source_index <- index_by_tau[[kk]][chunk]
      beta_index <- ((kk - 1L) * p + 1L):(kk * p)
      theta <- cbind(
        fit$alpha_draws[source_index, kk],
        fit$beta_draws[source_index, beta_index, drop = FALSE]
      )
      q_raw[, kk] <- as.vector(cbind(1, Z) %*% t(theta))
    }
    q_contract <- app_joint_qdesn_postscore_contract_rows(
      q_raw, design$tau
    )$q_contract
    sq <- ab <- numeric(length(chunk))
    for (kk in seq_len(K)) {
      q_mat <- matrix(q_contract[, kk], nrow = n, ncol = length(chunk))
      err <- q_mat - truth[, kk]
      sq <- sq + colSums(err^2)
      ab <- ab + colSums(abs(err))
    }
    rmse[chunk] <- sqrt(sq / (n * K))
    mae[chunk] <- ab / (n * K)
  }
  data.frame(
    chain_id = job$chain_id[[1L]], draw_position = seq_len(B),
    fit_rmse = rmse, fit_mae = mae, stringsAsFactors = FALSE
  )
}

fit_summary_one_cell <- function(jobs) {
  design <- readRDS(jobs$design_path[[1L]])
  draw_rows <- lapply(seq_len(nrow(jobs)), function(ii) {
    fit_draws_one_chain(runtime_root, jobs[ii, , drop = FALSE], contract, design)
  })
  draws <- do.call(rbind, draw_rows)
  cross <- crossings[
    crossings$mcmc_case_id == jobs$model_cell_id[[1L]] &
      crossings$window == "fit", , drop = FALSE
  ]
  if (nrow(cross) != 1L) stop("Missing fit crossing row for ",
                               jobs$model_cell_id[[1L]])
  data.frame(
    mcmc_case_id = jobs$model_cell_id[[1L]],
    scenario_id = jobs$scenario_id[[1L]],
    source_model_id = app_joint_article_score_model_source_id(
      jobs$model_id[[1L]]
    ),
    likelihood_family = jobs$likelihood_family[[1L]],
    fit_structure = jobs$fit_structure[[1L]],
    n_chains = nrow(jobs), n_draws = nrow(draws),
    posterior_mean = mean(draws$fit_rmse),
    posterior_median = q8(draws$fit_rmse, 0.50),
    posterior_q025 = q8(draws$fit_rmse, 0.025),
    posterior_q975 = q8(draws$fit_rmse, 0.975),
    posterior_mean_mae = mean(draws$fit_mae),
    canonical_raw_crossing_pairs = cross$raw_crossing_pairs[[1L]],
    canonical_contract_crossing_pairs = cross$contract_crossing_pairs[[1L]],
    stringsAsFactors = FALSE
  )
}

fit_summary_path <- file.path(
  table_dir, "joint_qdesn_shared_backbone_fit_interval_summary.csv"
)
if (reuse_fit_summary && file.exists(fit_summary_path)) {
  fit_summary <- read.csv(fit_summary_path, stringsAsFactors = FALSE,
                          check.names = FALSE)
} else {
  fit_results <- if (.Platform$OS.type != "windows" && fit_cores > 1L) {
    parallel::mclapply(groups, fit_summary_one_cell,
                       mc.cores = min(fit_cores, length(groups)),
                       mc.preschedule = FALSE)
  } else lapply(groups, fit_summary_one_cell)
  failed <- vapply(fit_results, inherits, logical(1L), "try-error")
  if (any(failed)) stop(paste(unlist(fit_results[failed]), collapse = " | "))
  fit_summary <- do.call(rbind, fit_results)
}
if (nrow(fit_summary) != 32L ||
    any(fit_summary$canonical_contract_crossing_pairs != 0L) ||
    !setequal(fit_summary$n_draws, c(3000L, 4500L))) {
  stop("Fit posterior interval reconstruction failed its contract.")
}

score_out <- score[, c(
  "mcmc_case_id", "scenario_id", "source_model_id", "model_id",
  "likelihood_family", "fit_structure", "selected_candidate_id",
  "article_seed", "design_fingerprint", "posterior_score_mean",
  "posterior_score_median", "posterior_score_q025", "posterior_score_q975",
  "posterior_regret_mean", "score_rank_rhat", "score_bulk_ess",
  "score_tail_ess", "score_mcse_mean", "score_functional_status",
  "canonical_raw_crossing_pairs", "canonical_contract_crossing_pairs",
  "raw_crossing_rate", "coherence_status"
)]
write_csv(score_out, file.path(table_dir,
  "joint_qdesn_shared_backbone_score_summary.csv"))
write_csv(fit_summary, fit_summary_path)
write_csv(contrasts, file.path(table_dir,
  "joint_qdesn_shared_backbone_contrast_summary.csv"))
write_csv(oracle, file.path(table_dir,
  "joint_qdesn_shared_backbone_oracle_recovery_summary.csv"))
write_csv(crossings, file.path(table_dir,
  "joint_qdesn_shared_backbone_crossing_summary.csv"))
write_csv(diagnostics, file.path(table_dir,
  "joint_qdesn_shared_backbone_score_diagnostics.csv"))

fmt <- function(mean, lo, hi) sprintf("%.4f [%.4f, %.4f]", mean, lo, hi)
score_table <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\scriptsize",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}rrrr@{}}",
  "\\toprule",
  paste0("Simulation setting & \\shortstack{Joint Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Independent Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Joint exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Independent exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} \\\\"),
  "\\midrule"
)
for (sid in scenario_order) {
  block <- score[score$scenario_id == sid, , drop = FALSE]
  block <- block[match(model_order, block$source_model_id), , drop = FALSE]
  values <- mapply(fmt, block$posterior_score_mean,
                   block$posterior_score_q025, block$posterior_score_q975,
                   USE.NAMES = FALSE)
  values[which.min(block$posterior_score_mean)] <- paste0(
    "\\textbf{", values[which.min(block$posterior_score_mean)], "}"
  )
  score_table <- c(score_table,
    paste(c(scenario_tex[[sid]], values), collapse = " & ") |> paste0(" \\\\"))
}
score_table <- c(
  score_table, "\\bottomrule", "\\end{tabular}", "}%",
  paste0("\\caption{Posterior data-generating-process-integrated finite-grid ",
    "quantile scores for the shared-backbone joint simulation. Entries are ",
    "posterior means with equal-tailed 95\\% intervals from the complete ",
    "shared-backbone evaluation. All four models use the same selected feature ",
    "design within a simulation setting. Lower values are better; boldface ",
    "marks the numerical minimum within a setting. The winner and runner-up ",
    "marginal intervals overlap in every setting, so the rankings are descriptive.}"),
  "\\label{tab:joint-qdesn-shared-backbone-score}", "\\end{table}"
)
writeLines(score_table, file.path(table_dir,
  "joint_qdesn_shared_backbone_score_table.tex"), useBytes = TRUE)

contrast_table <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\small",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.39\\textwidth}rr@{}}",
  "\\toprule", "Simulation setting & \\(\\AL\\) & \\(\\exAL\\) \\\\",
  "\\midrule"
)
for (sid in scenario_order) {
  block <- contrasts[contrasts$base_scenario_id == sid, , drop = FALSE]
  block <- block[match(c("AL", "exAL"), block$variant_id), , drop = FALSE]
  values <- mapply(fmt, block$score_delta_mean,
                   block$score_delta_q025, block$score_delta_q975,
                   USE.NAMES = FALSE)
  values[block$score_delta_q025 > 0] <- paste0(
    "\\textbf{", values[block$score_delta_q025 > 0], "}"
  )
  contrast_table <- c(contrast_table,
    paste(c(scenario_tex[[sid]], values), collapse = " & ") |> paste0(" \\\\"))
}
contrast_table <- c(
  contrast_table, "\\bottomrule", "\\end{tabular}",
  paste0("\\caption{Joint-minus-independent posterior contrasts in the ",
    "DGP-integrated finite-grid quantile score. Entries are means with ",
    "equal-tailed 95\\% intervals under the pre-specified chain-balanced ",
    "pairing. Positive values favor independent estimation. Boldface marks the ",
    "five intervals lying entirely above zero; the other eleven include zero.}"),
  "\\label{tab:supp-joint-qdesn-shared-backbone-contrasts}", "\\end{table}"
)
writeLines(contrast_table, file.path(table_dir,
  "joint_qdesn_shared_backbone_contrast_table.tex"), useBytes = TRUE)

cross_model <- aggregate(
  cbind(raw_crossing_pairs, contract_crossing_pairs) ~ window + source_model_id,
  data = crossings, FUN = sum
)
draw_rates <- aggregate(raw_crossing_rate ~ source_model_id, score, mean)
cross_table <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\small",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.42\\textwidth}rrrr@{}}",
  "\\toprule",
  paste0("Model & \\shortstack{Fit\\\\raw} & \\shortstack{Forecast\\\\raw} & ",
         "\\shortstack{After\\\\rearrangement} & ",
         "\\shortstack{Mean forecast draw\\\\crossing rate (\\%)} \\\\"),
  "\\midrule"
)
expected_forecast_cross <- c(1426L, 4705L, 0L, 281L)
for (jj in seq_along(model_order)) {
  mid <- model_order[[jj]]
  fit_n <- cross_model$raw_crossing_pairs[
    cross_model$source_model_id == mid & cross_model$window == "fit"]
  forecast_n <- cross_model$raw_crossing_pairs[
    cross_model$source_model_id == mid & cross_model$window == "forecast"]
  after_n <- sum(cross_model$contract_crossing_pairs[cross_model$source_model_id == mid])
  rate <- 100 * draw_rates$raw_crossing_rate[draw_rates$source_model_id == mid]
  if (forecast_n != expected_forecast_cross[[jj]]) stop("Crossing totals changed.")
  cross_table <- c(cross_table, sprintf(
    "%s & %d & %d & %d & %.2f \\\\", model_tex[[mid]], fit_n,
    forecast_n, after_n, rate
  ))
}
cross_table <- c(
  cross_table, "\\bottomrule", "\\end{tabular}",
  paste0("\\caption{Adjacent-level crossings for posterior-mean quantile grids, ",
    "summed over the eight simulation settings. Raw counts are reported before ",
    "monotone rearrangement; all 32 grids are ordered afterward. The final ",
    "column averages the draw-level forecast crossing rate across settings.}"),
  "\\label{tab:supp-joint-qdesn-shared-backbone-crossings}", "\\end{table}"
)
writeLines(cross_table, file.path(table_dir,
  "joint_qdesn_shared_backbone_crossing_table.tex"), useBytes = TRUE)

oracle_forecast <- oracle[oracle$window == "forecast", , drop = FALSE]
oracle_table <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\scriptsize",
  "\\resizebox{\\textwidth}{!}{%",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}rrrr@{}}",
  "\\toprule",
  paste0("Simulation setting & \\shortstack{Joint Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Independent Q--DESN\\\\\\(\\AL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Joint exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} & ",
         "\\shortstack{Independent exQDESN\\\\\\(\\exAL\\)--\\(\\RHS\\)} \\\\"),
  "\\midrule"
)
for (sid in scenario_order) {
  block <- oracle_forecast[oracle_forecast$scenario_id == sid, , drop = FALSE]
  block <- block[match(model_order, block$source_model_id), , drop = FALSE]
  values <- sprintf("%.3f (%.3f)", block$oracle_quantile_mae,
                    block$oracle_quantile_rmse)
  oracle_table <- c(oracle_table,
    paste(c(scenario_tex[[sid]], values), collapse = " & ") |> paste0(" \\\\"))
}
oracle_table <- c(
  oracle_table, "\\bottomrule", "\\end{tabular}", "}%",
  paste0("\\caption{Forecast recovery of the known conditional quantile paths. ",
    "Entries are mean absolute error with root-mean-square error in parentheses ",
    "for the monotonically rearranged posterior-mean forecast grids. All four ",
    "models use the same selected feature design within each setting.}"),
  "\\label{tab:supp-joint-qdesn-shared-backbone-oracle}", "\\end{table}"
)
writeLines(oracle_table, file.path(table_dir,
  "joint_qdesn_shared_backbone_oracle_recovery_table.tex"), useBytes = TRUE)

protocol <- c(
  "\\begin{table}[!htbp]", "\\centering", "\\small",
  "\\begin{tabular}{@{}>{\\raggedright\\arraybackslash}p{0.25\\textwidth}>{\\raggedright\\arraybackslash}p{0.65\\textwidth}@{}}",
  "\\toprule", "Item & Value \\\\", "\\midrule",
  "Feature design & One scenario-specific DESN/RHS specification selected from independent source realizations and then shared by all four model classes; the evaluation realization was not used for selection. \\\\",
  "Quantile grid & 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, and 0.95. \\\\",
  "Sequential initialization & Gaussian ridge to Gaussian RHS--VB; then median-centered independent AL continuation, matching AL-to-exAL initialization, complete independent grids to the corresponding joint fit, and matching VB-to-MCMC initialization. \\\\",
  "VB calculation & 136 components: 8 Gaussian RHS, 56 independent AL, 56 independent exAL, 8 joint AL, and 8 joint exAL fits. \\\\",
  "MCMC calculation & 160 independently seeded chains. Each AL cell uses four chains of 4,000 iterations with 1,000 burn-in and thinning by 4; each exAL cell uses six chains of 8,000 iterations with 2,000 burn-in and thinning by 4. \\\\",
  "Posterior score summary & 3,000 chain-balanced draws per AL cell and 4,500 per exAL cell; entries are posterior means with equal-tailed 95\\% intervals. \\\\",
  "Forecast evaluation & 990 aligned, sequentially conditional origin--horizon rows per comparison. The DGP-integrated seven-level score is computed after monotone rearrangement. \\\\",
  "\\bottomrule", "\\end{tabular}",
  "\\caption{Design of the shared-backbone joint multi-quantile evaluation. Initialization transfers starting values only; each destination retains its own likelihood, prior, and posterior target.}",
  "\\label{tab:joint-qdesn-shared-backbone-protocol}", "\\end{table}"
)
writeLines(protocol, file.path(table_dir,
  "joint_qdesn_shared_backbone_protocol.tex"), useBytes = TRUE)

plot_data <- function(x, mean_name, lo_name, hi_name, crossing_name) {
  data.frame(
    scenario_id = factor(x$scenario_id, levels = scenario_order),
    source_model_id = factor(x$source_model_id, levels = rev(model_order)),
    likelihood_family = x$likelihood_family,
    fit_structure = x$fit_structure,
    mean = x[[mean_name]], lo = x[[lo_name]], hi = x[[hi_name]],
    crossing = x[[crossing_name]], stringsAsFactors = FALSE
  )
}
make_interval_plot <- function(data, path, xlab, oracle_lines = NULL) {
  ranges <- aggregate(cbind(lo, hi) ~ scenario_id, data, function(z) range(z))
  limits <- lapply(split(data, data$scenario_id), function(block) {
    span <- max(block$hi) - min(block$lo)
    if (!is.finite(span) || span <= 0) span <- max(abs(block$hi), 1) * 0.1
    data.frame(scenario_id = block$scenario_id[[1L]],
               label_x = max(block$hi) + 0.18 * span)
  })
  limits <- do.call(rbind, limits)
  data <- merge(data, limits, by = "scenario_id", all.x = TRUE, sort = FALSE)
  data$scenario_id <- factor(data$scenario_id, levels = scenario_order)
  data$source_model_id <- factor(data$source_model_id, levels = rev(model_order))
  p <- ggplot2::ggplot(data, ggplot2::aes(y = source_model_id)) +
    ggplot2::geom_segment(
      ggplot2::aes(x = lo, xend = hi, yend = source_model_id,
                   colour = likelihood_family), linewidth = 0.55
    ) +
    ggplot2::geom_point(
      ggplot2::aes(x = mean, colour = likelihood_family,
                   shape = interaction(fit_structure, likelihood_family)),
      size = 2.1, stroke = 0.75
    ) +
    ggplot2::geom_text(
      ggplot2::aes(x = label_x, label = paste0("c = ", crossing)),
      hjust = 1, size = 2.35, colour = "#404040"
    ) +
    ggplot2::facet_wrap(~scenario_id, ncol = 2, scales = "free_x",
      labeller = ggplot2::as_labeller(scenario_labels)) +
    ggplot2::scale_y_discrete(labels = model_short) +
    ggplot2::scale_colour_manual(values = c(AL = "#1F4E79", exAL = "#8B4A3C")) +
    ggplot2::scale_shape_manual(values = c(
      "joint.AL" = 16, "independent.AL" = 1,
      "joint.exAL" = 17, "independent.exAL" = 2
    )) +
    ggplot2::scale_x_continuous(
      breaks = function(limits) pretty(limits, n = 3),
      labels = function(x) formatC(x, format = "f", digits = 2)
    ) +
    ggplot2::labs(x = xlab, y = NULL) +
    ggplot2::coord_cartesian(clip = "on") +
    ggplot2::theme_bw(base_size = 8.5) +
    ggplot2::theme(
      legend.position = "none", panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "#F0F1F2", colour = "#777777"),
      strip.text = ggplot2::element_text(face = "bold", size = 8),
      axis.text.y = ggplot2::element_text(size = 7.4),
      plot.margin = ggplot2::margin(5.5, 7, 5.5, 5.5)
    )
  if (!is.null(oracle_lines)) {
    oracle_lines$scenario_id <- factor(oracle_lines$scenario_id,
                                       levels = scenario_order)
    p <- p + ggplot2::geom_vline(
      data = oracle_lines, ggplot2::aes(xintercept = oracle),
      linetype = "22", linewidth = 0.4, colour = "#555555",
      inherit.aes = FALSE
    )
  }
  ggplot2::ggsave(path, p, device = grDevices::cairo_pdf,
                  width = 7.0, height = 8.15, units = "in")
}

fit_plot <- plot_data(fit_summary, "posterior_mean", "posterior_q025",
                      "posterior_q975", "canonical_raw_crossing_pairs")
forecast_plot <- plot_data(score, "posterior_score_mean", "posterior_score_q025",
                           "posterior_score_q975", "canonical_raw_crossing_pairs")
oracle_lines <- data.frame(
  scenario_id = score$scenario_id,
  oracle = score$posterior_score_mean - score$posterior_regret_mean
)
oracle_lines <- aggregate(oracle ~ scenario_id, oracle_lines, mean)
make_interval_plot(
  fit_plot,
  file.path(figure_dir, "joint_qdesn_shared_backbone_fit_oracle_rmse_intervals.pdf"),
  "Fitting-sample quantile-path RMSE"
)
make_interval_plot(
  forecast_plot,
  file.path(figure_dir, "joint_qdesn_shared_backbone_forecast_dgp_score_intervals.pdf"),
  "DGP-integrated finite-grid quantile score", oracle_lines
)

fit_wrapper <- c(
  "\\begin{figure}[!htbp]", "\\centering",
  "\\includegraphics[width=0.94\\textwidth]{figures/joint_qdesn_simulation/joint_qdesn_shared_backbone_fit_oracle_rmse_intervals.pdf}",
  paste0("\\caption{Posterior fitting-sample recovery of the known conditional ",
    "quantile paths under the shared-backbone design. Points are posterior ",
    "means and horizontal bars are equal-tailed 95\\% intervals after monotone ",
    "rearrangement. Filled symbols denote joint fits and open symbols independent ",
    "fits; blue denotes \\(\\AL\\) and red \\(\\exAL\\). Labels \\(c\\) give ",
    "raw crossings in the posterior-mean grid; all counts after rearrangement are zero.}"),
  "\\label{fig:joint-qdesn-shared-backbone-fit-rmse}", "\\end{figure}"
)
forecast_wrapper <- c(
  "\\begin{figure}[!htbp]", "\\centering",
  "\\includegraphics[width=0.94\\textwidth]{figures/joint_qdesn_simulation/joint_qdesn_shared_backbone_forecast_dgp_score_intervals.pdf}",
  paste0("\\caption{Posterior DGP-integrated finite-grid quantile scores under ",
    "the shared-backbone design. Points are posterior means and horizontal bars ",
    "are equal-tailed 95\\% intervals; lower is better. Dashed lines mark the ",
    "oracle finite-grid score. Filled symbols denote joint fits and open symbols ",
    "independent fits; blue denotes \\(\\AL\\) and red \\(\\exAL\\). Labels ",
    "\\(c\\) give raw crossings in the posterior-mean forecast grid; all counts ",
    "after rearrangement are zero.}"),
  "\\label{fig:joint-qdesn-shared-backbone-forecast-score}", "\\end{figure}"
)
writeLines(fit_wrapper, file.path(table_dir,
  "joint_qdesn_shared_backbone_fit_figure.tex"), useBytes = TRUE)
writeLines(forecast_wrapper, file.path(table_dir,
  "joint_qdesn_shared_backbone_forecast_figure.tex"), useBytes = TRUE)

generated <- c(
  "tables/joint_qdesn_shared_backbone_score_summary.csv",
  "tables/joint_qdesn_shared_backbone_fit_interval_summary.csv",
  "tables/joint_qdesn_shared_backbone_contrast_summary.csv",
  "tables/joint_qdesn_shared_backbone_oracle_recovery_summary.csv",
  "tables/joint_qdesn_shared_backbone_crossing_summary.csv",
  "tables/joint_qdesn_shared_backbone_score_diagnostics.csv",
  "tables/joint_qdesn_shared_backbone_score_table.tex",
  "tables/joint_qdesn_shared_backbone_contrast_table.tex",
  "tables/joint_qdesn_shared_backbone_crossing_table.tex",
  "tables/joint_qdesn_shared_backbone_oracle_recovery_table.tex",
  "tables/joint_qdesn_shared_backbone_protocol.tex",
  "tables/joint_qdesn_shared_backbone_fit_figure.tex",
  "tables/joint_qdesn_shared_backbone_forecast_figure.tex",
  "figures/joint_qdesn_simulation/joint_qdesn_shared_backbone_fit_oracle_rmse_intervals.pdf",
  "figures/joint_qdesn_simulation/joint_qdesn_shared_backbone_forecast_dgp_score_intervals.pdf"
)
manifest <- data.frame(
  artifact_id = sub("[.][^.]+$", "", basename(generated)),
  tracked_path = generated,
  tracked_sha256 = vapply(file.path(repo_root, generated), sha256, character(1L)),
  source_runtime = basename(runtime_root),
  source_score_contract_sha256 = expected_contract_sha,
  source_execution_commit = "fd48499308d613341274717b53643bece977fb39",
  stringsAsFactors = FALSE
)
write_csv(manifest, file.path(table_dir,
  "joint_qdesn_shared_backbone_article_asset_manifest.csv"))

cat(sprintf(
  paste0("JOINT_SHARED_BACKBONE_ARTICLE_PROJECTION=PASS ",
         "cells=%d fit_draws=%d contrasts=%d directional_independent=%d\n"),
  nrow(score), sum(fit_summary$n_draws), nrow(contrasts),
  sum(contrasts$score_delta_q025 > 0)
))
