# Phase161 decision freeze and posterior gamma/sigma audit.

app_joint_exqdesn_phase161_default_phase160_dir <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase160_split_rhs_independent_confirmation_mcmc_20260805"
}

app_joint_exqdesn_phase161_default_output_dir <- function() {
  "/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache/joint_qdesn_phase161_split_rhs_decision_gamma_audit_20260805"
}

app_joint_exqdesn_phase161_draw_files <- function(phase160_dir) {
  inventory <- app_joint_exqdesn_phase156_read_csv(file.path(phase160_dir, "chain_inventory.csv"))
  inventory$draw_path <- file.path(inventory$worker_output_dir, "posterior_draws.csv.gz")
  if (any(!file.exists(inventory$draw_path))) stop("Phase161 requires every Phase160 posterior draw file.", call. = FALSE)
  inventory
}

app_joint_exqdesn_phase161_summarize_draws <- function(inventory) {
  rows <- list(); chain_rows <- list(); correlations <- list()
  for (ii in seq_len(nrow(inventory))) {
    meta <- inventory[ii, , drop = FALSE]
    draws <- app_joint_exqdesn_phase156_read_csv(meta$draw_path[[1L]])
    for (block in c("gamma", "sigma")) {
      cols <- grep(paste0("^", block, "_"), names(draws), value = TRUE)
      for (jj in seq_along(cols)) {
        x <- draws[[cols[[jj]]]]
        chain_rows[[length(chain_rows) + 1L]] <- data.frame(
          scenario_id = meta$scenario_id, candidate_id = meta$candidate_id,
          chain_id = meta$chain_id, parameter = block, quantile_index = jj,
          mean = mean(x), median = median(x), sd = sd(x),
          q025 = unname(quantile(x, .025)), q975 = unname(quantile(x, .975)),
          near_zero_005 = mean(abs(x) <= .05), near_zero_010 = mean(abs(x) <= .10),
          near_zero_025 = mean(abs(x) <= .25), stringsAsFactors = FALSE
        )
      }
    }
    gcols <- grep("^gamma_", names(draws), value = TRUE)
    scols <- grep("^sigma_", names(draws), value = TRUE)
    for (jj in seq_len(min(length(gcols), length(scols)))) {
      correlations[[length(correlations) + 1L]] <- data.frame(
        scenario_id = meta$scenario_id, candidate_id = meta$candidate_id,
        chain_id = meta$chain_id, quantile_index = jj,
        gamma_sigma_correlation = cor(draws[[gcols[[jj]]]], draws[[scols[[jj]]]]),
        stringsAsFactors = FALSE
      )
    }
  }
  chain <- app_joint_qdesn_bind_rows(chain_rows)
  keys <- unique(chain[c("scenario_id", "candidate_id", "parameter", "quantile_index")])
  for (ii in seq_len(nrow(keys))) {
    key <- keys[ii, ]; x <- chain[chain$scenario_id == key$scenario_id & chain$candidate_id == key$candidate_id &
      chain$parameter == key$parameter & chain$quantile_index == key$quantile_index, ]
    rows[[ii]] <- data.frame(key, chains = nrow(x), mean_of_chain_means = mean(x$mean),
      between_chain_sd = sd(x$mean), median_of_chain_medians = median(x$median),
      min_q025 = min(x$q025), max_q975 = max(x$q975),
      mean_near_zero_005 = mean(x$near_zero_005), mean_near_zero_010 = mean(x$near_zero_010),
      mean_near_zero_025 = mean(x$near_zero_025), stringsAsFactors = FALSE)
  }
  list(summary = app_joint_qdesn_bind_rows(rows), chain = chain,
       correlation = app_joint_qdesn_bind_rows(correlations))
}

app_joint_exqdesn_phase161_article_rows <- function(article_table) {
  x <- app_joint_exqdesn_phase156_read_csv(article_table)
  x <- x[x$scenario_id %in% c("nonlinear_reservoir_friendly", "student_t_location_scale") &
           x$model_label == "Joint exQDESN RHS", , drop = FALSE]
  if (nrow(x) != 2L) stop("Could not identify the two current article Joint exQDESN rows.", call. = FALSE)
  out <- x[c("scenario_id", "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae",
             "mcmc_forecast_check_loss_mean", "mcmc_forecast_crps_grid",
             "mcmc_forecast_raw_crossing_pairs", "mcmc_forecast_contract_crossing_pairs",
             "source_block_id", "source_dir")]
  names(out) <- c("scenario_id", "fit_truth_mae", "forecast_truth_mae", "forecast_check_loss",
                  "forecast_crps_grid", "raw_crossing_pairs", "contract_crossing_pairs",
                  "source_phase", "source_dir")
  out
}

app_joint_exqdesn_phase161_run <- function(
  phase160_dir = app_joint_exqdesn_phase161_default_phase160_dir(),
  output_dir = app_joint_exqdesn_phase161_default_output_dir(),
  article_table = app_path("tables/joint_qdesn_article_validation_mcmc_balanced_scenario_summary.csv")
) {
  phase160_dir <- normalizePath(phase160_dir, mustWork = TRUE)
  output_dir <- normalizePath(output_dir, mustWork = FALSE); app_ensure_dir(output_dir)
  source_verification <- app_joint_exqdesn_phase158_verify_source(phase160_dir, "phase160_confirmation")
  if (any(source_verification$status != "pass")) stop("Phase160 source manifest verification failed.", call. = FALSE)
  confirmation <- app_joint_exqdesn_phase156_read_csv(file.path(phase160_dir, "confirmation_summary.csv"))
  comparison <- app_joint_exqdesn_phase156_read_csv(file.path(phase160_dir, "phase157b_comparison.csv"))
  diagnostics <- app_joint_exqdesn_phase156_read_csv(file.path(phase160_dir, "modern_mcmc_diagnostics.csv"))
  article <- app_joint_exqdesn_phase161_article_rows(article_table)
  audit <- app_joint_exqdesn_phase161_summarize_draws(app_joint_exqdesn_phase161_draw_files(phase160_dir))
  decision <- merge(confirmation, article, by = "scenario_id", suffixes = c("_phase160", "_article"), all.x = TRUE)
  decision$forecast_delta_vs_article <- decision$forecast_truth_mae_phase160 - decision$forecast_truth_mae_article
  decision$article_replacement <- FALSE
  decision$decision <- ifelse(decision$scenario_id == "nonlinear_reservoir_friendly",
    "retain_phase157b_baseline", "confirmed_vs_phase157b_retain_as_diagnostic")
  decision$rationale <- ifelse(decision$scenario_id == "nonlinear_reservoir_friendly",
    "independent confirmation did not reproduce the screening gain",
    "independent confirmation improved on Phase157b but did not improve the current article forecast row")
  gate <- data.frame(
    gate_status = if (all(source_verification$status == "pass") && all(confirmation$all_finite) &&
      all(confirmation$contract_crossing_pairs == 0) && all(diagnostics$rank_rhat <= 1.05, na.rm = TRUE)) "pass" else "fail",
    source_manifest_failures = sum(source_verification$status != "pass"),
    nonfinite_candidates = sum(!confirmation$all_finite), contract_crossings = sum(confirmation$contract_crossing_pairs),
    max_rank_rhat = max(diagnostics$rank_rhat, na.rm = TRUE), min_bulk_ess = min(diagnostics$bulk_ess, na.rm = TRUE),
    article_rows_replaced = sum(decision$article_replacement),
    recommendation = "stop_split_rhs_screening_no_article_promotion", stringsAsFactors = FALSE)
  readme <- file.path(output_dir, "README.md")
  writeLines(c("# Phase161 split-RHS decision and gamma audit", "",
    "This no-new-sampling audit freezes the Phase160 decisions and evaluates chain-level gamma/sigma geometry.",
    "Neither candidate replaces the current article row. The Student-t candidate is retained as diagnostic evidence only.",
    "Healthy rank diagnostics do not establish that the exAL extension should outperform the AL working likelihood."), readme)
  paths <- c(
    source_manifest_verification = app_joint_qvp_write_csv(source_verification, file.path(output_dir, "source_manifest_verification.csv")),
    phase160_confirmation = app_joint_qvp_write_csv(confirmation, file.path(output_dir, "phase160_confirmation.csv")),
    phase157b_comparison = app_joint_qvp_write_csv(comparison, file.path(output_dir, "phase157b_comparison.csv")),
    current_article_rows = app_joint_qvp_write_csv(article, file.path(output_dir, "current_article_rows.csv")),
    decision_freeze = app_joint_qvp_write_csv(decision, file.path(output_dir, "decision_freeze.csv")),
    posterior_parameter_summary = app_joint_qvp_write_csv(audit$summary, file.path(output_dir, "posterior_parameter_summary.csv")),
    chain_parameter_summary = app_joint_qvp_write_csv(audit$chain, file.path(output_dir, "chain_parameter_summary.csv")),
    gamma_sigma_correlation = app_joint_qvp_write_csv(audit$correlation, file.path(output_dir, "gamma_sigma_correlation.csv")),
    phase161_assessment = app_joint_qvp_write_csv(gate, file.path(output_dir, "phase161_assessment.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(output_dir, "provenance.csv")),
    readme = normalizePath(readme, mustWork = TRUE))
  manifest <- app_joint_exqdesn_trace_manifest(paths, output_dir)
  list(output_dir = output_dir, decision = decision, gate = gate,
       paths = c(paths, artifact_manifest = manifest$manifest_path))
}
