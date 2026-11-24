#!/usr/bin/env Rscript
# Current complete-packet admission. Frozen v1/v2 checks remain historical.
# Public summary CSVs only: no fitting, posterior sampling or score runtime.
local({
  options(stringsAsFactors = FALSE, digits = 17)
  args <- commandArgs(trailingOnly = TRUE)
  flag <- function(name, default) {
    at <- match(name, args)
    if (is.na(at)) return(default)
    if (at == length(args)) stop(paste("Missing", name), call. = FALSE)
    args[[at + 1L]]
  }
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
  script <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  root <- normalizePath(flag("--repo-root", file.path(dirname(script), "..")), mustWork = TRUE)
  data_only <- "--data-only" %in% args
  count <- 0L
  expect <- function(ok, message) {
    count <<- count + 1L
    if (!isTRUE(ok)) stop(paste("JOINT_CORRECTED_V3_CHECK_FAILED:", message), call. = FALSE)
  }
  sha <- function(path) unname(tools::sha256sum(path)[[1L]])
  prefix <- "tables/joint_qdesn_corrected_v3_"
  path <- function(suffix) file.path(root, paste0(prefix, suffix))
  read <- function(suffix) {
    expect(file.exists(path(suffix)), paste("Missing current projection", suffix))
    read.csv(path(suffix), check.names = FALSE, stringsAsFactors = FALSE)
  }
  text <- function(relative) paste(readLines(file.path(root, relative), warn = FALSE), collapse = "\n")
  truth <- function(x) tolower(as.character(x)) %in% c("true", "1", "t")
  close <- function(a, b, tolerance = 1e-11) length(a) == length(b) &&
    all(is.finite(a)) && all(is.finite(b)) && all(abs(a - b) <= tolerance * pmax(1, abs(a), abs(b)))
  same <- function(a, b) identical(names(a), names(b)) && nrow(a) == nrow(b) &&
    all(vapply(names(a), function(name) {
      x <- a[[name]]; y <- b[[name]]
      if (all(is.na(x)) && all(is.na(y))) return(TRUE)
      isTRUE(all.equal(x, y, tolerance = 0, check.attributes = FALSE))
    }, logical(1L)))
  key <- function(x) paste(x$scenario_id, x$model_id, x$inference_method, sep = "|")
  scenarios <- c("asymmetric_laplace_tail", "gaussian_mixture_bridge", "laplace_bridge",
    "nonlinear_reservoir_friendly", "normal_bridge", "persistent_heavy_tail", "regime_shift", "student_t_location_scale")
  models <- c("joint_qdesn_rhs", "independent_qdesn_rhs", "joint_exqdesn_rhs", "independent_exqdesn_rhs")
  source_head <- "5ad779121e44330e5a08baee1a44d77ba722b5cd"
  frozen <- "69aced9bbd37ee506a382ed85a7fe2aba116ed296ae4285890540e572122f5f3"
  selected <- read("selected_mcmc_score_summary.csv")
  vb <- read("selected_vb_score_summary.csv")
  all <- read("selected_64_score_summary.csv")
  expect(nrow(selected) == 32L && !anyDuplicated(key(selected)) &&
      setequal(selected$scenario_id, scenarios) && setequal(selected$model_id, models) &&
      all(selected$inference_method == "mcmc") && all(table(selected$scenario_id, selected$model_id) == 1L),
    "Exact complete eight-scenario four-model selected MCMC surface")
  expect(identical(sha(path("selected_mcmc_score_summary.csv")), frozen), "Immutable selected32 packet SHA256")
  expect(nrow(vb) == 32L && all(vb$inference_method == "vb") &&
      nrow(all) == 64L && !anyDuplicated(key(all)) &&
      setequal(key(all), c(key(selected), key(vb))), "Complete coherent selected64 MCMC and VB surface")
  for (x in list(selected, vb)) {
    mapped <- all[match(key(x), key(all)), names(x), drop = FALSE]
    expect(same(x, mapped), "Selected64 reproduces exact selected-method numerical rows")
  }
  expect(all(vb$specification_role[match(paste(selected$scenario_id, selected$model_id),
      paste(vb$scenario_id, vb$model_id))] == selected$specification_role), "VB uses the matching selected scenario role")
  expect(all(vapply(split(all, all$scenario_id), function(x) length(unique(x$specification_role)) == 1L, logical(1L))) &&
      all(all$specification_role[all$scenario_id == "persistent_heavy_tail"] == "new_geometry_parity"),
    "Coherent whole-scenario selection and complete persistent-heavy-tail parity fallback")
  finite_columns <- c("posterior_score_mean", "posterior_score_median", "posterior_score_q025", "posterior_score_q975",
    "posterior_score_interval_width", "path_posterior_score_mean", "path_posterior_score_median", "path_posterior_score_q025",
    "path_posterior_score_q975", "path_posterior_score_interval_width", "fit_oracle_quantile_mae", "fit_oracle_quantile_rmse")
  expect(all(is.finite(as.matrix(all[finite_columns]))), "All 64 primary/path/fit summaries are finite")
  expect(all(all$posterior_score_q025 <= all$posterior_score_median) && all(all$posterior_score_median <= all$posterior_score_q975) &&
      close(all$posterior_score_interval_width, all$posterior_score_q975 - all$posterior_score_q025) &&
      close(all$path_posterior_score_interval_width, all$path_posterior_score_q975 - all$path_posterior_score_q025),
    "Ordered medians/limits and exact score interval widths; means need not lie inside central intervals")
  expect(all(all$canonical_contract_crossing_pairs == 0) && all(all$contract_crossing_pairs == 0) &&
      all(all$path_contract_crossing_pairs == 0), "Zero canonical and draw-path contract crossings")
  expect(all(selected$interval_scope == "mcmc_readout_uncertainty_conditional_on_mean_design"),
    "Primary intervals retain the executed conditional averaged-feature functional")
  backbone <- read("selected_backbones.csv")
  expect(nrow(backbone) == 8L && !anyDuplicated(backbone$scenario_id) && setequal(backbone$scenario_id, scenarios) &&
      all(!truth(backbone$raw_inputs_in_readout)) && all(truth(backbone$full_states_all_layers)),
    "One retained pure-DESN backbone per scenario without direct raw inputs")
  expect(all(backbone$specification_role[match(all$scenario_id, backbone$scenario_id)] == all$specification_role),
    "All four models and both inference methods use the same scenario backbone")
  fit <- read("fit_oracle_diagnostics.csv")
  expect(nrow(fit) == 64L && !anyDuplicated(key(fit)) && setequal(key(fit), key(all)) &&
      all(fit$fit_observations == 1300L) && all(fit$fit_first_full_time == 9701L) && all(fit$fit_last_full_time == 11000L) &&
      all(fit$forecast_origins == 33L) && all(fit$horizons_per_origin == 30L) && all(fit$origin_horizon_pairs == 990L) && all(fit$levels == 7L),
    "Executed 1300-observation fitting window and common 33 by 30 forecast design")
  fit <- fit[match(key(all), key(fit)), ]
  expect(close(fit$fit_oracle_quantile_mae, all$fit_oracle_quantile_mae) &&
      close(fit$fit_oracle_quantile_rmse, all$fit_oracle_quantile_rmse) &&
      all(fit$fit_oracle_quantile_rmse >= fit$fit_oracle_quantile_mae - 1e-12) &&
      all(fit$curve_definition == "equal_weight_PAVA_of_posterior_mean_fitted_quantile_grid"),
    "Fit diagnostics preserve canonical mean-path oracle MAE/RMSE, not draw-wise intervals")
  draws <- read("draw_counts.csv")
  expect(nrow(draws) == 64L && !anyDuplicated(key(draws)) && setequal(key(draws), key(all)), "Complete selected draw ledger")
  draws <- draws[match(key(all), key(draws)), ]
  laplace <- all$scenario_id == "laplace_bridge" & all$model_id == "joint_exqdesn_rhs" & all$inference_method == "mcmc"
  base <- ifelse(all$likelihood_family == "AL", 2250L, 4500L)
  expected <- ifelse(all$inference_method == "vb", 2000L, ifelse(laplace, 12000L, base))
  expect(close(draws$score_draws, expected) && close(draws$path_score_draws, ifelse(all$inference_method == "vb", 40L, 120L)) &&
      all(draws$score_chains == ifelse(all$inference_method == "vb", 0L, ifelse(laplace, 8L, 3L))) &&
      all(draws$path_score_chains == ifelse(all$inference_method == "vb", 0L, 3L)),
    "Exact AL/exAL retained draws and eight-chain Laplace primary versus three-chain path probe")
  chain <- read("chain_identity.csv")
  expect(nrow(chain) == 101L && sum(chain$n_keep) == sum(draws$score_draws[all$inference_method == "mcmc"]),
    "All 101 selected chains account for every primary MCMC score draw")
  for (cell in unique(selected$model_cell_id)) {
    rows <- chain[chain$model_cell_id == cell, ]
    expect(nrow(rows) == draws$score_chains[match(cell, draws$model_cell_id)] &&
        length(unique(rows$posterior_target_sha256)) == 1L &&
        all(grepl("^[0-9a-f]{64}$", rows$posterior_target_sha256)), "Common recorded posterior target across selected chains")
    full <- rows[rows$source_context == "corrected_confirmation", ]
    expect(nrow(full) == 3L && length(unique(full$complete_posterior_target_sha256)) == 1L &&
        all(grepl("^[0-9a-f]{64}$", full$complete_posterior_target_sha256)) &&
        all(grepl("^[0-9a-f]{64}$", full$effective_sampler_control_sha256)),
      "Three base chains retain their authenticated full-target/control identities")
  }
  historical <- chain[chain$source_context == "laplace_supplement", ]
  expect(nrow(historical) == 5L && all(historical$complete_posterior_target_sha256 == "") &&
      all(historical$effective_sampler_control_sha256 == "") &&
      all(historical$identity_scope == "historical_exact_M0_target_and_recorded_iteration_controls"),
    "Historical five-chain extension records actual legacy identity, never invented hardened hashes")
  al <- chain$likelihood_family == "AL"
  expect(all(chain$sigma_support[al] == "(0,Inf)") && all(chain$sigma_update_id[al] == "direct_inverse_gamma_unbounded_v1") &&
      all(chain$n_iter[al] == 2000L) && all(chain$burn[al] == 500L) && all(chain$thin[al] == 2L) && all(chain$n_keep[al] == 750L),
    "Corrected AL unbounded inverse-gamma conditional and retained-chain controls")
  crossing <- read("crossing_summary.csv")
  expect(nrow(crossing) == 32L && !anyDuplicated(crossing$model_cell_id) && setequal(crossing$model_cell_id, selected$model_cell_id),
    "Complete crossing ledger")
  crossing <- crossing[match(selected$model_cell_id, crossing$model_cell_id), ]
  selected_draws <- draws$score_draws[match(key(selected), key(all))]
  expect(all(crossing$mean_grid_comparisons == 990L * 6L) && close(crossing$posterior_draws, selected_draws) &&
      close(crossing$posterior_draw_comparisons, selected_draws * 5940L) &&
      close(crossing$canonical_raw_crossing_pairs, selected$canonical_raw_crossing_pairs) &&
      close(crossing$raw_crossing_pairs, selected$raw_crossing_pairs) &&
      close(crossing$posterior_draw_crossing_percent, 100 * selected$raw_crossing_pairs / (selected_draws * 5940L)),
    "Mean-grid and posterior-draw crossing denominators use actual per-cell draw counts")
  totals <- read("crossing_totals.csv")
  totals <- totals[match(models, totals$model_id), ]
  expect(nrow(totals) == 4L && all(totals$comparisons == 47520L) && close(totals$raw_mean_grid_pairs, c(0, 9, 0, 0)) &&
      close(totals$mean_grid_percent, c(0, 9, 0, 0) / 47520 * 100), "Correct current 47520-comparison raw crossing totals")
  for (model in models) {
    block <- crossing[crossing$model_id == model, ]
    total <- totals[totals$model_id == model, ]
    expect(close(total$equal_scenario_draw_percent, mean(block$posterior_draw_crossing_percent)) &&
        close(total$mean_adjustment, mean(block$canonical_mean_abs_monotone_adjustment)) &&
        close(total$max_adjustment, max(block$canonical_max_abs_monotone_adjustment)), "Correct equal-scenario draw-rate and adjustment aggregates")
  }
  winner <- read("scenario_winners.csv")
  expect(nrow(winner) == 8L && all(truth(winner$winner_runner_intervals_overlap)), "All eight descriptive minima retain marginal-interval overlap")
  calculated <- do.call(rbind, lapply(split(selected, selected$scenario_id), function(x) x[which.min(x$posterior_score_mean), ]))
  expect(all(calculated$model_id == winner$winner_model_id[match(calculated$scenario_id, winner$scenario_id)]) &&
      sum(calculated$fit_structure == "joint") == 3L, "Three joint and five independent descriptive minima reproduce")
  contrasts <- read("numerical_contrasts.csv")
  expect(nrow(contrasts) == 16L && all(truth(contrasts$marginal_intervals_overlap)) &&
      close(contrasts$joint_minus_independent_mean, contrasts$joint_mean - contrasts$independent_mean) &&
      sum(contrasts$joint_minus_independent_mean < 0) == 6L,
    "Six of sixteen joint means are lower; marginal overlap is not a paired-difference credible interval")
  gates <- read("scientific_gates.csv")
  expect(nrow(gates) > 0 && all(gates$status == "pass"), "Frozen scientific completion gates pass")
  protocol <- read("protocol.csv"); values <- setNames(protocol$value, protocol$field)
  expect(!anyDuplicated(protocol$field) && values[["scientific_source_commit"]] == source_head &&
      values[["fitting_observations"]] == "1300" && values[["fitting_full_times"]] == "9701:11000" &&
      values[["probability_levels"]] == "0.05;0.10;0.25;0.50;0.75;0.90;0.95" &&
      values[["trapezoidal_weights"]] == "0.025;0.100;0.200;0.250;0.200;0.100;0.025" &&
      values[["exAL_inference"]] == "M0_v_collapsed_support_logit" &&
      values[["intercept_prior_calibration"]] == "Gaussian_reference_mean_and_sd_4_times_Gaussian_residual_scale" &&
      values[["RHS_slab"]] == "learned_not_fixed" &&
      values[["VB_score_draws"]] == "2000" && values[["MCMC_path_draws"]] == "120" && values[["VB_path_draws"]] == "40" &&
      values[["protected_evaluation_use"]] == "final_evaluation_scores_select_complete_challenger_or_parity_then_functional_stability_fallback",
    "Frozen level/weight/target/fit contract and honest evaluation-informed packet choice")
  proof <- read("projection_provenance.csv"); proof <- setNames(proof$value, proof$name)
  expect(proof[["source_lane_head"]] == source_head && proof[["selected_packet_sha256"]] == frozen &&
      all(proof[c("fitting", "posterior_sampling", "forecasting", "rescoring")] == "FALSE"),
    "Projection preserves scientific source and explicitly records zero new numerical campaigns")
  if (!data_only) {
    expect(sha(file.path(root, proof[["generator"]])) == proof[["generator_sha256"]] &&
        sha(file.path(root, "scripts/qdesn_evaluation_figure_style.R")) == proof[["style_sha256"]], "Committed builder and style identity")
    manifest <- read("article_asset_manifest.csv")
    expect(!anyDuplicated(manifest$relative_path) && all(manifest$source_lane_head == source_head), "Unique frozen-source asset manifest")
    for (i in seq_len(nrow(manifest))) {
      asset <- file.path(root, manifest$relative_path[i])
      expect(file.exists(asset) && file.info(asset)$size == manifest$size_bytes[i] && sha(asset) == manifest$sha256[i],
        paste("Current asset size/hash", manifest$relative_path[i]))
    }
    # This explicit helper binds the reviewed manifest bytes, not a mutable
    # receipt that could be rehashed to authorize a different numerical packet.
    helper <- file.path(root, "scripts/joint_qdesn_corrected_article_authority_v3.py")
    command <- "import importlib.util,sys; s=importlib.util.spec_from_file_location('v3',sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); m.admit(sys.argv[2])"
    result <- system2("/usr/bin/python3.11", c("-I", "-B", "-c", shQuote(command), shQuote(helper), shQuote(root)), stdout = TRUE, stderr = TRUE)
    expect(is.null(attr(result, "status")), paste("Explicit authority manifest admission", paste(result, collapse = " ")))
    main <- text("main.tex"); supp <- text("qdesn-supplement.tex")
    active <- function(value) gsub("(?<!\\\\)%[^\n]*", "", value, perl = TRUE)
    expect(grepl("\\input{tables/joint_qdesn_corrected_v3_forecast_figure.tex}", active(main), fixed = TRUE) &&
        grepl("\\input{tables/joint_qdesn_corrected_v3_compact_scores.tex}", active(supp), fixed = TRUE) &&
        grepl("\\input{tables/joint_qdesn_corrected_v3_compact_crossings.tex}", active(supp), fixed = TRUE),
      "Current v3 figure and both appendix tables must be selected")
    expect(!grepl("\\input{tables/qdesn_multiquantile_forecast_figure_display.tex}", active(main), fixed = TRUE) &&
        !grepl("\\input{tables/appendix_compact_20261106_mq_scores.tex}", active(supp), fixed = TRUE), "Historical v2 routes cannot remain current")
    normalized <- gsub("[[:space:]]+", " ", paste(main, supp))
    expect(grepl("1,300", normalized, fixed = TRUE) && grepl("three chains", normalized, fixed = TRUE) &&
        grepl("eight chains", normalized, fixed = TRUE) && grepl("0.4491", normalized, fixed = TRUE) &&
        grepl("31", normalized, fixed = TRUE) && grepl("(4s_G)^2", gsub("[[:space:]]+", "", supp), fixed = TRUE) &&
        grepl("The slab scale is learned", normalized, fixed = TRUE),
      "Current fit/chain/path-sensitivity and calibrated prior description agree")
    mq_design <- strsplit(strsplit(main, "\\label{subsec:simulation-mq-design}", fixed = TRUE)[[1L]][2L], "\\subsection{", fixed = TRUE)[[1L]][1L]
    selection <- gsub("[[:space:]]+", " ", supp)
    expect(grepl("chosen after reviewing evaluation scores and sampling stability", gsub("[[:space:]]+", " ", mq_design), fixed = TRUE) &&
        grepl("at least one mean oracle score improves", selection, fixed = TRUE) &&
        grepl("none increases by more than 1\\%", selection, fixed = TRUE) &&
        grepl("not an untouched-test design", selection, fixed = TRUE),
      "Final score-informed complete-packet choice is distinguished from development screening")
    allowed <- readLines(file.path(root, "overleaf/article_files.txt"), warn = FALSE)
    expect(all(c(manifest$relative_path, paste0(prefix, "article_asset_manifest.csv")) %in% allowed), "Complete current projection is authorized for article-only publication")
    expect(!any(grepl("joint_qdesn_pure_desn_v[12]_", allowed)), "Historical JOINT assets stay outside the active publication projection")
  }
  cat(sprintf("JOINT_CORRECTED_ARTICLE_PROJECTION_V3_CHECK=PASS checks=%d selected=32 methods=64 runtime_reads=0 scope=%s\n",
    count, if (data_only) "public_summary_data" else "current_article_authority"))
})
