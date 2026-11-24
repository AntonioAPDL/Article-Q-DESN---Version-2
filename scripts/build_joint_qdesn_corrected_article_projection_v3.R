#!/usr/bin/env Rscript
# Deterministic projection of frozen scientific summaries; no fit or rescore.
v3_prefix <- "joint_qdesn_corrected_v3_"
v3_generator <- "scripts/build_joint_qdesn_corrected_article_projection_v3.R"
v3_source <- "5ad779121e44330e5a08baee1a44d77ba722b5cd"
v3_selected_sha <- "69aced9bbd37ee506a382ed85a7fe2aba116ed296ae4285890540e572122f5f3"
v3_inventory_sha <- "c31239215160edb179eae5fefc6a4f25efda201edffd3d832b9afe2bcdacbf56"
v3_handoff_sha <- "42356182180f2c5fe252b9de8b0b59e1301ce8230b01befdeaae32b6499c527d"
v3_supp_inventory_sha <- "8a0d469bd923754b814db7215247a30c3585fd033cfcf48d89619d861dd751fa"
v3_supp_handoff_sha <- "df0998340780ee1b4ccc22e9ccd71bec43886aecef694afd3c94b420b022b32e"
v3_models <- c("joint_qdesn_rhs", "independent_qdesn_rhs", "joint_exqdesn_rhs", "independent_exqdesn_rhs")
v3_labels <- setNames(c("MQ--DESN (AL)", "Q--DESN (AL)", "MQ--DESN (exAL)", "Q--DESN (exAL)"), v3_models)
v3_expect <- function(ok, message) if (!isTRUE(ok)) stop(paste("JOINT_V3_PROJECTION_FAILED:", message), call. = FALSE)
v3_sha <- function(path) unname(tools::sha256sum(path)[[1L]])
v3_read <- function(path) utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
v3_key <- function(x) paste(x$scenario_id, x$specification_role, x$model_id, sep = "|")
v3_path <- function(root, suffix) file.path(root, "tables", paste0(v3_prefix, suffix))
v3_write <- function(x, root, suffix) utils::write.csv(x, v3_path(root, suffix), row.names = FALSE, na = "")
v3_fmt <- function(x, digits = 4L) formatC(x, format = "f", digits = digits)
v3_interval <- function(x, prefix = "posterior_score_") paste0(v3_fmt(x[[paste0(prefix, "mean")]]), " [",
  v3_fmt(x[[paste0(prefix, "q025")]]), ", ", v3_fmt(x[[paste0(prefix, "q975")]]), "]")
v3_table <- function(root, suffix, header, rows, caption, labels, align) {
  writeLines(c("% Deterministic projection of frozen corrected summaries.", "\\begin{table}[!htbp]", "\\centering", "\\footnotesize",
    "\\setlength{\\tabcolsep}{3pt}", "\\renewcommand{\\arraystretch}{1.08}", paste0("\\begin{tabular}{@{}", align, "@{}}"), "\\toprule",
    paste0(paste(header, collapse = " & "), " \\\\"), "\\midrule", rows, "\\bottomrule", "\\end{tabular}",
    paste0("\\caption{", caption, "}"), paste0("\\label{", labels, "}"), "\\end{table}"), v3_path(root, suffix), useBytes = TRUE)
}
v3_normalize_pdf_date <- function(path) {
  bytes <- readBin(path, "raw", n = file.info(path)$size); marker <- charToRaw("/CreationDate (D:")
  candidates <- which(bytes == marker[[1L]])
  hits <- candidates[vapply(candidates, function(at) at + length(marker) - 1L <= length(bytes) &&
    identical(bytes[at:(at + length(marker) - 1L)], marker), logical(1L))]
  v3_expect(length(hits) == 1L, "One Cairo creation date")
  closing <- which(seq_along(bytes) > hits[[1L]] & bytes == charToRaw(")")[[1L]])[[1L]]
  fixed <- charToRaw("/CreationDate (D:20000101000000+00'00)")
  v3_expect(length(fixed) == closing - hits[[1L]] + 1L, "Fixed-width PDF metadata normalization")
  bytes[hits[[1L]]:closing] <- fixed; writeBin(bytes, path)
}

v3_build <- function(root, runtime, supplement) {
  root <- normalizePath(root, mustWork = TRUE); runtime <- normalizePath(runtime, mustWork = TRUE)
  supplement <- normalizePath(supplement, mustWork = TRUE)
  v3_expect(getRversion() == numeric_version("4.6.0"), "Pinned R 4.6.0")
  v3_expect(requireNamespace("ggplot2", quietly = TRUE), "ggplot2 available")
  inv_path <- file.path(runtime, "integration_handoff/runtime_transfer_inventory.csv")
  handoff_path <- file.path(runtime, "integration_handoff/handoff_manifest.csv")
  supp_inv_path <- file.path(supplement, "integration_handoff/runtime_transfer_inventory.csv")
  supp_hand_path <- file.path(supplement, "integration_handoff/handoff_manifest.csv")
  v3_expect(v3_sha(inv_path) == v3_inventory_sha && v3_sha(handoff_path) == v3_handoff_sha, "Frozen current evidence pins")
  v3_expect(v3_sha(supp_inv_path) == v3_supp_inventory_sha && v3_sha(supp_hand_path) == v3_supp_handoff_sha, "Frozen eight-chain source pins")
  inventory <- v3_read(inv_path); handoff <- v3_read(handoff_path); supp_inventory <- v3_read(supp_inv_path)
  v3_expect(nrow(inventory) == 2805L && sum(inventory$size_bytes) == 3264047763, "Runtime inventory count and bytes")
  bindings <- list()
  bind <- function(relative, context = "current") {
    base <- if (context == "supplement") supplement else runtime
    inv <- if (context == "supplement") supp_inventory else inventory
    row <- inv[inv$relative_path == relative, , drop = FALSE]
    if (nrow(row) == 0L && context == "current" && startsWith(relative, "integration_handoff/"))
      row <- handoff[handoff$relative_path == sub("^integration_handoff/", "", relative), , drop = FALSE]
    path <- file.path(base, relative)
    v3_expect(nrow(row) == 1L && file.exists(path) && file.info(path)$size == row$size_bytes && v3_sha(path) == row$sha256,
      paste("Frozen source payload", context, relative))
    bindings[[paste(context, relative, sep = "|")]] <<- data.frame(source_context = context, relative_artifact = relative,
      size_bytes = row$size_bytes, sha256 = row$sha256, stringsAsFactors = FALSE)
    path
  }
  read_bound <- function(relative, context = "current") v3_read(bind(relative, context))
  selected_path <- bind("corrected_superfinal_selected_score_summary.csv")
  selected <- v3_read(selected_path)
  v3_expect(v3_sha(selected_path) == v3_selected_sha && nrow(selected) == 32L && !anyDuplicated(v3_key(selected)) &&
    all(selected$inference_method == "mcmc") && all(table(selected$scenario_id) == 4L) &&
    all(is.finite(selected$posterior_score_mean)) && all(selected$canonical_contract_crossing_pairs == 0), "Exact complete selected32")
  full <- read_bound("full_confirmation/score_packet/score_summary.csv")
  plan <- read_bound("full_confirmation/score_packet/score_worker_plan.csv")
  decisions <- read_bound("full_confirmation/score_packet/scenario_packet_decisions.csv")
  workers <- read_bound("full_confirmation/corrected_mcmc_worker_summary.csv")
  identities <- read_bound("full_confirmation/corrected_chain_identity_audit.csv")
  gates <- read_bound("integration_handoff/final_gate_summary.csv")
  contrasts <- read_bound("integration_handoff/joint_independent_contrasts.csv")
  winners <- read_bound("integration_handoff/scenario_winners.csv")
  score_contract <- read_bound("full_confirmation/score_packet/score_contract.csv")
  supplemental <- read_bound("supplemental_score_summary.csv", "supplement")
  supp_plan <- read_bound("full_confirmation/mcmc_worker_plan.csv", "supplement")
  v3_expect(nrow(full) == 128L && all(gates$status == "pass") && nrow(contrasts) == 16L && nrow(winners) == 8L,
    "Completed scientific gates and comparisons")
  v3_expect(all(identities$verified) && nrow(identities) == 64L, "Complete target and sampler-control identities")
  v3_expect(all(selected$specification_role[selected$scenario_id == "persistent_heavy_tail"] == "new_geometry_parity"), "Whole-scenario fallback")
  matched <- full[full$inference_method == "vb", , drop = FALSE]
  matched <- matched[match(v3_key(selected), v3_key(matched)), , drop = FALSE]
  v3_expect(nrow(matched) == 32L && !anyNA(matched$model_cell_id) && identical(v3_key(matched), v3_key(selected)), "Matched selected-role VB32")
  matched$promote_complete_challenger_packet <- selected$promote_complete_challenger_packet
  all_selected <- rbind(selected, matched)
  v3_expect(file.copy(selected_path, v3_path(root, "selected_mcmc_score_summary.csv"), overwrite = TRUE), "Copy exact selected CSV")
  v3_expect(v3_sha(v3_path(root, "selected_mcmc_score_summary.csv")) == v3_selected_sha, "Selected CSV byte identity")
  v3_write(matched, root, "selected_vb_score_summary.csv"); v3_write(all_selected, root, "selected_64_score_summary.csv")
  selected_plan <- plan[match(paste(v3_key(all_selected), all_selected$inference_method),
    paste(v3_key(plan), plan$inference_method)), , drop = FALSE]
  v3_expect(!anyNA(selected_plan$model_cell_id), "Selected score-plan join")
  design_meta <- list()
  for (path in unique(selected_plan$design_path)) {
    artifact <- v3_read(file.path(dirname(path), "artifact_manifest.csv"))
    row <- artifact[basename(artifact$relative_path) == "design.rds", , drop = FALSE]
    v3_expect(nrow(row) == 1L && v3_sha(path) == row$sha256 && file.info(path)$size == row$size_bytes, "Saved design source hash")
    design <- readRDS(path); times <- design$row_meta$full_time_index[design$train_local]
    v3_expect(length(times) == 1300L && identical(as.integer(times), 9701:11000) && nrow(design$forecast_map) == 990L &&
      length(unique(design$forecast_map$origin_index)) == 33L && max(design$forecast_map$horizon) == 30L && length(design$tau) == 7L,
      "Executed fitting and forecast design")
    relative <- paste0("full_confirmation/vb_workers/", basename(dirname(path)), "/design.rds")
    bindings[[paste("design", relative)]] <- data.frame(source_context = "stronger_window_source", relative_artifact = relative,
      size_bytes = row$size_bytes, sha256 = row$sha256)
    design_meta[[path]] <- data.frame(fit_observations = length(times), fit_first_full_time = min(times), fit_last_full_time = max(times),
      forecast_origins = 33L, horizons_per_origin = 30L, origin_horizon_pairs = 990L, levels = 7L, design_sha256 = row$sha256)
  }
  backbone_fields <- c("scenario_id", "specification_role", "candidate_id", "rhs_tau0", "D", "n", "n_tilde", "retained_state_budget",
    "response_lags", "exogenous_lags", "alpha", "rho", "pi_w", "pi_in", "input_scale", "reservoir_seed", "raw_inputs_in_readout",
    "full_states_all_layers", "structural_signature", "architecture_signature", "execution_signature", "article_seed")
  backbone <- unique(selected_plan[backbone_fields])
  v3_expect(nrow(backbone) == 8L && !anyDuplicated(backbone$scenario_id), "One shared selected backbone per scenario")
  v3_write(backbone, root, "selected_backbones.csv")
  fit <- cbind(all_selected[c("scenario_id", "specification_role", "model_cell_id", "model_id", "inference_method")],
    do.call(rbind, lapply(selected_plan$design_path, function(path) design_meta[[path]])),
    all_selected[c("fit_oracle_quantile_mae", "fit_oracle_quantile_rmse")])
  fit$curve_definition <- "equal_weight_PAVA_of_posterior_mean_fitted_quantile_grid"
  fit$oracle_definition <- "saved_design_in_sample_DGP_quantiles"
  v3_write(fit, root, "fit_oracle_diagnostics.csv")
  # Further projection and rendering below.
  v3_finish(root, runtime, supplement, selected, matched, all_selected, selected_plan, workers, supp_plan, supplemental,
    gates, contrasts, winners, decisions, fit, bind, read_bound, function() bindings)
}

v3_finish <- function(root, runtime, supplement, selected, matched, all_selected, selected_plan, workers, supp_plan, supplemental,
  gates, contrasts, winners, decisions, fit, bind, read_bound, get_bindings) {
  count_rows <- function(path) {
    con <- gzfile(path, "rt"); on.exit(close(con)); count <- 0L
    repeat { x <- readLines(con, n = 10000L, warn = FALSE); count <- count + length(x); if (!length(x)) break }
    count - 1L
  }
  draw_counts <- all_selected[c("scenario_id", "model_cell_id", "model_id", "inference_method")]
  draw_counts$score_draws <- draw_counts$path_score_draws <- draw_counts$score_chains <- draw_counts$path_score_chains <- 0L
  for (i in seq_len(nrow(all_selected))) {
    row <- all_selected[i, ]
    relative <- sprintf("full_confirmation/score_packet/cells/worker_%04d/posterior_score_draws.csv.gz", row$score_worker_id)
    draw_counts$score_draws[i] <- count_rows(bind(relative))
    draw_counts$path_score_draws[i] <- count_rows(bind(sub("posterior_score_draws", "path_posterior_score_draws", relative, fixed = TRUE)))
    draw_counts$score_chains[i] <- draw_counts$path_score_chains[i] <- if (row$inference_method == "mcmc") 3L else 0L
    if (row$scenario_id == "laplace_bridge" && row$model_id == "joint_exqdesn_rhs" && row$inference_method == "mcmc") {
      draw_counts$score_draws[i] <- count_rows(bind("score_cells/target_01/posterior_score_draws.csv.gz", "supplement"))
      draw_counts$score_chains[i] <- 8L
      v3_expect(supplemental$stable[supplemental$target_id == 1L] && draw_counts$score_draws[i] == 12000L,
        "Stabilized Laplace eight-chain primary evidence")
    }
  }
  draw_counts$path_sensitivity_scope <- ifelse(draw_counts$score_chains == 8L,
    "archived_three_chain_sensitivity_not_eight_chain_extension", "matched_selected_three_chain_or_VB_source")
  v3_write(draw_counts, root, "draw_counts.csv")
  chain <- workers[workers$model_cell_id %in% selected$model_cell_id, ]; chain$source_context <- "corrected_confirmation"
  fields <- c("model_cell_id", "model_id", "likelihood_family", "chain_id", "n_iter", "burn", "thin", "n_keep", "posterior_target_sha256",
    "complete_posterior_target_sha256", "effective_sampler_control_sha256", "sigma_support", "sigma_update_id", "source_context")
  chain <- chain[fields]
  for (id in supp_plan$worker_id[supp_plan$target_id == 1L]) {
    one <- read_bound(sprintf("full_confirmation/mcmc_workers/worker_%04d/summary.csv", id), "supplement")
    one$source_context <- "laplace_supplement"
    for (field in setdiff(fields, names(one))) one[[field]] <- ""
    chain <- rbind(chain, one[fields])
  }
  chain$identity_scope <- ifelse(chain$source_context == "laplace_supplement",
    "historical_exact_M0_target_and_recorded_iteration_controls", "complete_target_and_sampler_control_hashes")
  v3_expect(nrow(chain) == 101L && sum(chain$n_keep) == sum(draw_counts$score_draws[draw_counts$inference_method == "mcmc"]),
    "Selected chains and primary-score draws agree")
  v3_write(chain, root, "chain_identity.csv")
  v3_write(contrasts, root, "numerical_contrasts.csv"); v3_write(winners, root, "scenario_winners.csv")
  v3_write(gates, root, "scientific_gates.csv"); v3_write(decisions, root, "scenario_selection_decisions.csv")
  diagnostics <- selected[c("scenario_id", "model_cell_id", "model_id", "score_mcse_mean", "score_rank_rhat", "score_folded_rhat", "score_bulk_ess",
    "score_tail_ess", "state_half_standardized_rms")]
  diagnostics$half_difference_source <- "selected_three_chain_mean_design"
  laplace <- diagnostics$scenario_id == "laplace_bridge" & diagnostics$model_id == "joint_exqdesn_rhs"
  actual <- read_bound("score_cells/target_01/mean_design_diagnostics.csv", "supplement")
  diagnostics$state_half_standardized_rms[laplace] <- actual$standardized_rms_half_difference
  diagnostics$half_difference_source[laplace] <- "retained_eight_chain_mean_design_receipt"
  v3_write(diagnostics, root, "score_diagnostics.csv")
  crossing <- selected[c("scenario_id", "model_cell_id", "model_id", "canonical_raw_crossing_pairs", "canonical_contract_crossing_pairs", "raw_crossing_pairs",
    "contract_crossing_pairs", "canonical_mean_abs_monotone_adjustment", "canonical_max_abs_monotone_adjustment")]
  crossing$mean_grid_comparisons <- 5940L
  crossing$mean_grid_crossing_percent <- 100 * crossing$canonical_raw_crossing_pairs / crossing$mean_grid_comparisons
  crossing$posterior_draws <- draw_counts$score_draws[draw_counts$inference_method == "mcmc"]
  crossing$posterior_draw_comparisons <- crossing$posterior_draws * crossing$mean_grid_comparisons
  crossing$posterior_draw_crossing_percent <- 100 * crossing$raw_crossing_pairs / crossing$posterior_draw_comparisons
  v3_expect(sum(crossing$canonical_raw_crossing_pairs) == 9L &&
    all(crossing$canonical_raw_crossing_pairs[crossing$model_id != "independent_qdesn_rhs"] == 0L), "Frozen nine raw mean-grid crossings")
  v3_write(crossing, root, "crossing_summary.csv")
  totals <- do.call(rbind, lapply(v3_models, function(model) {
    x <- crossing[crossing$model_id == model, ]
    data.frame(model_id = model, raw_mean_grid_pairs = sum(x$canonical_raw_crossing_pairs), comparisons = sum(x$mean_grid_comparisons),
      mean_grid_percent = 100 * sum(x$canonical_raw_crossing_pairs) / sum(x$mean_grid_comparisons),
      equal_scenario_draw_percent = mean(x$posterior_draw_crossing_percent),
      mean_adjustment = mean(x$canonical_mean_abs_monotone_adjustment), max_adjustment = max(x$canonical_max_abs_monotone_adjustment))
  }))
  v3_write(totals, root, "crossing_totals.csv")
  protocol <- data.frame(field = c("scientific_source_commit", "fitting_observations", "fitting_full_times", "selection_train_observations",
    "selection_validation_observations", "forecast_origins", "horizons_per_origin", "origin_horizon_pairs", "probability_levels", "trapezoidal_weights",
    "primary_score", "primary_interval_scope", "primary_chains", "AL_retained_per_chain", "exAL_retained_per_chain",
    "Laplace_MQ_exAL_primary_chains", "Laplace_MQ_exAL_sensitivity_chains", "AL_scale_update", "exAL_inference", "historical_comparison_scope",
    "protected_evaluation_use"),
    value = c(v3_source, "1300", "9701:11000", "1000", "300", "33", "30", "990", "0.05;0.10;0.25;0.50;0.75;0.90;0.95",
      "0.025;0.100;0.200;0.250;0.200;0.100;0.025", "DGP_integrated_finite_grid_aCRPS", "readout_uncertainty_conditional_on_saved_mean_future_design",
      "3", "750", "1500", "8", "3", "direct_inverse_gamma_on_(0,Inf)", "M0_v_collapsed_support_logit",
      "new1300_vs_published500_plus_revised_screening_not_a_controlled_kernel_comparison",
      "final_evaluation_scores_select_complete_challenger_or_parity_then_functional_stability_fallback"))
  protocol <- rbind(protocol, data.frame(field = c("intercept_prior_calibration", "RHS_slab", "AL_iterations", "AL_burn", "exAL_iterations",
    "exAL_burn", "MCMC_thinning", "VB_score_draws", "MCMC_path_draws", "VB_path_draws", "Laplace_supplement_identity_scope",
    "scenario_selection_rule"),
    value = c("Gaussian_reference_mean_and_sd_4_times_Gaussian_residual_scale", "learned_not_fixed", "2000", "500", "4000", "1000", "2",
      "2000", "120", "40", "historical_exact_M0_target_and_recorded_iteration_controls_not_new_complete_ID_guard",
      "at_least_one_lower_evaluation_mean_and_all_four_within_1percent_then_frozen_functional_stability")))
  v3_write(protocol, root, "protocol.csv")
  v3_render(root, selected, matched, fit, crossing, totals)
  v3_write(do.call(rbind, get_bindings()), root, "provenance_bindings.csv")
  provenance <- data.frame(name = c("schema", "source_lane_head", "runtime_id", "selected_packet_sha256", "runtime_inventory_sha256", "handoff_manifest_sha256",
    "supplement_inventory_sha256", "supplement_handoff_sha256", "generator", "generator_sha256", "style_sha256", "MCMC_rows", "VB_rows",
    "fitting_observations", "fitting", "posterior_sampling", "forecasting", "rescoring", "Laplace_MQ_exAL_scope", "fit_metric", "contrast_intervals"),
    value = c("joint-qdesn-corrected-article-v3", v3_source, "joint_qdesn_superfinal_al_kernel_rerun_20261123", v3_selected_sha,
      v3_inventory_sha, v3_handoff_sha, v3_supp_inventory_sha, v3_supp_handoff_sha, v3_generator, v3_sha(file.path(root, v3_generator)),
      v3_sha(file.path(root, "scripts/qdesn_evaluation_figure_style.R")), "32", "32", "1300", "FALSE", "FALSE", "FALSE", "FALSE",
      "eight_chain_primary_and_fit_with_archived_three_chain_path_sensitivity",
      "RMSE_of_PAVA_posterior_mean_fit_grid_against_saved_in_sample_DGP_quantiles", "only_source_marginal_intervals_no_invented_paired_intervals"))
  v3_write(provenance, root, "projection_provenance.csv")
  paths <- c(paste0("tables/", list.files(file.path(root, "tables"), pattern = paste0("^", v3_prefix, ".*\\.(csv|tex)$"))),
    paste0("figures/joint_qdesn_simulation/", v3_prefix, c("forecast_dgp_acrps.pdf", "fit_oracle_rmse.pdf")))
  paths <- paths[!endsWith(paths, "article_asset_manifest.csv")]
  for (relative in paths[endsWith(paths, ".csv") | endsWith(paths, ".tex")])
    v3_expect(!any(grepl("/data/|/home/|application/cache/|local_trackers/", readLines(file.path(root, relative), warn = FALSE))), "Portable article assets")
  manifest <- data.frame(relative_path = paths, size_bytes = file.info(file.path(root, paths))$size,
    sha256 = vapply(file.path(root, paths), v3_sha, character(1L)), role = ifelse(endsWith(paths, ".pdf"), "figure", ifelse(endsWith(paths, ".tex"), "table_or_wrapper", "scientific_summary")),
    source_lane_head = v3_source)
  v3_write(manifest, root, "article_asset_manifest.csv")
  cat("JOINT_V3_ARTICLE_PROJECTION=PASS\nMCMC_ROWS=32\nVB_ROWS=32\nFITTING_OBSERVATIONS=1300\n")
  invisible(manifest)
}

v3_render <- function(root, selected, matched, fit, crossing, totals) {
  style <- new.env(parent = globalenv()); source(file.path(root, "scripts/qdesn_evaluation_figure_style.R"), local = style)
  scenario_tex <- style$qdesn_scenario_labels
  scenario_tex["student_t_location_scale"] <- "Student-\\(t\\) location--scale"
  ordered <- function(x) x[order(match(x$scenario_id, style$qdesn_scenario_order), match(x$model_id, v3_models)), , drop = FALSE]
  rows_for <- function(data, values) {
    data <- ordered(data); output <- character()
    for (i in seq_len(nrow(data))) {
      first <- i == 1L || data$scenario_id[i] != data$scenario_id[i-1L]
      if (first && i > 1L) output <- c(output, "\\addlinespace[2pt]")
      output <- c(output, paste0(paste(c(if (first) scenario_tex[[data$scenario_id[i]]] else "", v3_labels[[data$model_id[i]]],
        values(data[i, , drop = FALSE])), collapse = " & "), " \\\\"))
    }
    output
  }
  v3_table(root, "compact_scores.tex", c("Simulation setting", "Model", "Averaged predictors", "Recursive trajectories"),
    rows_for(selected, function(x) c(v3_interval(x), v3_interval(x, "path_posterior_score_"))),
    paste0("Oracle finite-grid \\(\\aCRPS\\). Entries are posterior means and equal-tailed 95\\% intervals. Primary scores condition on averaged future predictors; trajectory-specific scores use recursively generated predictors for individual draws. ",
      "The Laplace MQ--DESN (exAL) primary summary uses eight chains; its trajectory-specific sensitivity retains the original three chains. These intervals describe score uncertainty, not future-response coverage. Q--DESN fits levels independently; MQ--DESN estimates their coefficients jointly."),
    c("tab:joint-qdesn-pure-desn-v2-recursive-policy", "tab:joint-qdesn-pure-desn-v2-score"), ">{\\raggedright\\arraybackslash}p{0.24\\textwidth}lrr")
  v3_table(root, "vb_scores.tex", c("Simulation setting", "Model", "VB", "MCMC"),
    rows_for(matched, function(x) { m <- selected[match(v3_key(x), v3_key(selected)), ]; c(v3_interval(x), v3_interval(m)) }),
    "Oracle finite-grid \\(\\aCRPS\\) under variational and MCMC inference for the same selected reservoir specification. Entries are means and equal-tailed 95\\% intervals. Both condition on averaged future predictors. Joint VB additionally treats intercepts as point estimates.",
    "tab:joint-qdesn-corrected-v3-vb", ">{\\raggedright\\arraybackslash}p{0.24\\textwidth}lrr")
  v3_table(root, "secondary_scores.tex", c("Simulation setting", "Model", "Realized aCRPS", "Oracle-path MAE", "Oracle-path RMSE"),
    rows_for(selected, function(x) v3_fmt(unlist(x[c("posterior_realized_acrps_mean", "canonical_origin_marginal_oracle_quantile_mae", "canonical_origin_marginal_oracle_quantile_rmse")]))),
    "Secondary forecast summaries. Realized \\(\\aCRPS\\) is averaged across posterior draws. MAE and RMSE compare the monotone posterior-mean forecast grid with the known DGP quantiles and describe oracle quantile-path recovery, not response prediction errors.",
    "tab:joint-qdesn-pure-desn-v2-secondary", ">{\\raggedright\\arraybackslash}p{0.26\\textwidth}lrrr")
  rows <- vapply(seq_len(nrow(totals)), function(i) {
    x <- totals[i, ]
    adjustment <- function(value) if (abs(value) < 1e-12) "0" else {
      if (abs(value) >= 1e-4) v3_fmt(value) else {
        pieces <- strsplit(formatC(value, format = "e", digits = 2), "e", fixed = TRUE)[[1L]]
        paste0("\\(", pieces[[1L]], "\\times10^{", as.integer(pieces[[2L]]), "}\\)")
      }
    }
    paste0(paste(c(v3_labels[[x$model_id]], x$raw_mean_grid_pairs, v3_fmt(x$mean_grid_percent, 3),
      v3_fmt(x$equal_scenario_draw_percent, 3), adjustment(x$mean_adjustment), adjustment(x$max_adjustment)), collapse = " & "), " \\\\")
  }, character(1L))
  v3_table(root, "compact_crossings.tex", c("Model", "Raw pairs", "Mean grid (\\%)", "Posterior draws (\\%)", "Mean adjustment", "Max. adjustment"), rows,
    "Forecast quantile crossings before monotone projection. Each model has 47,520 adjacent-level comparisons across eight mechanisms. Posterior-draw percentages are first calculated within each mechanism using its retained draw count, then averaged with equal mechanism weights. Adjustments are the equal-mechanism mean and overall maximum for posterior-mean grids on the response scale; values below \\(10^{-12}\\) are displayed as zero. All projected grids are ordered.",
    "tab:joint-qdesn-pure-desn-v2-crossings", "lrrrrr")
  v3_table(root, "protocol.tex", c("Quantity", "Specification"), c(
    "Fitting sample & 1,300 observations (full times 9,701--11,000) \\\\",
    "Internal selection & 1,000 fitting and 300 validation observations \\\\",
    "Forecast assessment & 33 origins, 30 horizons, 990 common pairs \\\\",
    "Probability levels & 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95 \\\\",
    "MCMC & Three chains; 750 AL or 1,500 exAL draws per chain \\\\",
    "Laplace MQ--DESN (exAL) & Eight chains, 12,000 primary score draws \\\\"),
    "Multiquantile simulation design and retained MCMC draws. All four regression classes share one selected reservoir specification within each mechanism. The persistent-heavy-tail comparison retains its complete reference specification after the alternative failed the predefined functional-stability criterion.",
    "tab:joint-qdesn-pure-desn-v2-protocol", "ll")
  keys <- setNames(style$qdesn_joint_model_order, v3_models)
  style$qdesn_joint_model_labels <- setNames(gsub("--", "-", v3_labels, fixed = TRUE), unname(keys))
  data <- data.frame(scenario_id = selected$scenario_id, source_model_id = unname(keys[selected$model_id]),
    likelihood_family = selected$likelihood_family, mean = selected$posterior_score_mean, lo = selected$posterior_score_q025,
    hi = selected$posterior_score_q975, crossing = paste0(v3_fmt(crossing$mean_grid_crossing_percent, 3), "%"))
  make_plot <- function(block, xlab, fitting = FALSE) {
    p <- style$qdesn_joint_interval_plot(block, xlab) +
      ggplot2::theme(text = ggplot2::element_text(size = 10.4), strip.text = ggplot2::element_text(face = "bold", size = 10.4, lineheight = .98),
        axis.text.x = ggplot2::element_text(size = 10.4), axis.text.y = ggplot2::element_text(size = 10.4, colour = "#242424"),
        axis.title.x = ggplot2::element_text(size = 10.4), plot.margin = ggplot2::margin(7, 16, 7, 7), panel.spacing = grid::unit(1, "lines"))
    p$layers[[3L]]$aes_params$size <- 3.45
    for (scenario in levels(p$data$scenario_id)) {
      at <- which(p$data$scenario_id == scenario)
      upper <- max(p$data$hi[at], p$data$mean[at]); lower <- min(p$data$lo[at], p$data$mean[at])
      span <- upper - lower; if (!is.finite(span) || span <= 0) span <- max(abs(upper), 1) * .1
      p$data$label_x[at] <- upper + .80 * span
    }
    xscale <- p$scales$get_scales("x")
    xscale$labels <- function(x) formatC(x, format = "f", digits = if (diff(range(x, na.rm = TRUE)) < .04) 3 else 2)
    if (fitting) {
      p$layers <- p$layers[c(2L)]
      xscale$labels <- function(x) formatC(x, format = "f", digits = 2)
      xscale$breaks <- function(limits) pretty(limits, n = 2L)
      p <- p + ggplot2::theme(panel.spacing.x = grid::unit(1.8, "lines"))
    }
    p
  }
  forecast_name <- paste0("figures/joint_qdesn_simulation/", v3_prefix, "forecast_dgp_acrps.pdf")
  fit_name <- paste0("figures/joint_qdesn_simulation/", v3_prefix, "fit_oracle_rmse.pdf")
  style$qdesn_save_vector_pdf(file.path(root, forecast_name), make_plot(data, "Oracle aCRPS"), 7, 8.1)
  v3_normalize_pdf_date(file.path(root, forecast_name))
  fit_mcmc <- fit[fit$inference_method == "mcmc", ]; data$mean <- data$lo <- data$hi <- fit_mcmc$fit_oracle_quantile_rmse
  style$qdesn_save_vector_pdf(file.path(root, fit_name), make_plot(data, "Fitting-sample quantile-path RMSE", TRUE), 7, 8.1)
  v3_normalize_pdf_date(file.path(root, fit_name))
  writeLines(c("\\begin{figure}[!htbp]", "\\centering", paste0("\\includegraphics[width=0.94\\textwidth]{", forecast_name, "}"),
    "\\caption{Oracle finite-grid \\(\\aCRPS\\) for independent Q--DESN and coupled multiquantile MQ--DESN regressions. Points are posterior means and segments are equal-tailed 95\\% intervals, conditional on averaged future predictors. The annotation \\(c\\) is the percentage of adjacent-level crossings in each raw posterior-mean forecast grid before projection. All scored grids are ordered. AL and exAL use blue and brown, respectively.}",
    "\\label{fig:joint-qdesn-pure-desn-v2-forecast-acrps}", "\\end{figure}"), v3_path(root, "forecast_figure.tex"))
  writeLines(c("\\begin{figure}[!htbp]", "\\centering", paste0("\\includegraphics[width=0.94\\textwidth]{", fit_name, "}"),
    "\\caption{Fitting-sample oracle quantile-path RMSE over 1,300 observations. Each point compares the equal-weight monotone projection of the posterior-mean fitted grid with the known in-sample DGP quantiles. These are point-path diagnostics, not posterior intervals or forecast errors.}",
    "\\label{fig:joint-qdesn-pure-desn-v2-fit-rmse}", "\\end{figure}"), v3_path(root, "fit_figure.tex"))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  value <- function(flag, fallback) if (flag %in% args) args[[match(flag, args) + 1L]] else fallback
  v3_build(value("--root", getwd()),
    value("--runtime", "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_superfinal_al_kernel_rerun_20261123/application/cache/joint_qdesn_superfinal_al_kernel_rerun_20261123"),
    value("--supplement", "/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_superfinal_predictive_stability_20261122/application/cache/joint_qdesn_superfinal_predictive_stability_20261122"))
}
