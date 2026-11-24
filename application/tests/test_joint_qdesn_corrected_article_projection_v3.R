# Complete current projection, plus portable summary/route mutation rejection.
local({
  root <- normalizePath(getwd(), mustWork = TRUE)
  checker <- file.path(root, "scripts/check_joint_qdesn_corrected_article_projection_v3.R")
  rscript <- file.path(R.home("bin"), "Rscript")
  marker <- "JOINT_CORRECTED_ARTICLE_PROJECTION_V3_CHECK=PASS"
  run <- function(directory, data_only = FALSE) {
    result <- suppressWarnings(system2(rscript,
      c(shQuote(checker), "--repo-root", shQuote(directory), if (data_only) "--data-only"),
      stdout = TRUE, stderr = TRUE))
    status <- attr(result, "status"); if (is.null(status)) status <- 0L
    list(status = as.integer(status), output = result)
  }
  passed <- run(root)
  if (passed$status != 0L || !any(startsWith(passed$output, marker)))
    stop(paste(c("Current corrected v3 authority failed:", passed$output), collapse = "\n"))
  temporary <- tempfile("joint_corrected_v3_mutations_")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
  csv <- list.files(file.path(root, "tables"), pattern = "^joint_qdesn_corrected_v3_.*[.]csv$", full.names = TRUE)
  fresh <- function(label) {
    directory <- file.path(temporary, label)
    dir.create(file.path(directory, "tables"), recursive = TRUE)
    stopifnot(all(file.copy(csv, file.path(directory, "tables"))))
    directory
  }
  pristine <- fresh("pristine")
  positive <- run(pristine, TRUE)
  stopifnot(positive$status == 0L, any(startsWith(positive$output, marker)))
  mutations <- 0L
  write <- function(x, target) {
    encoded <- x
    for (name in names(encoded)) if (is.numeric(encoded[[name]]))
      encoded[[name]] <- ifelse(is.na(encoded[[name]]), NA_character_, sprintf("%.17g", encoded[[name]]))
    write.csv(encoded, target, row.names = FALSE, na = "")
  }
  reject <- function(result, label, expected) {
    stopifnot(result$status != 0L, !any(startsWith(result$output, marker)),
      any(grepl("JOINT_CORRECTED_V3_CHECK_FAILED:", result$output, fixed = TRUE)),
      any(grepl(expected, result$output, fixed = TRUE)))
    mutations <<- mutations + 1L
    cat(paste0("V3_MUTATION_REJECTED=", label, "\n"))
  }
  mutate <- function(label, suffix, change, expected) {
    directory <- fresh(label)
    target <- file.path(directory, "tables", paste0("joint_qdesn_corrected_v3_", suffix, ".csv"))
    x <- read.csv(target, stringsAsFactors = FALSE, check.names = FALSE)
    write(change(x), target)
    reject(run(directory, TRUE), label, expected)
  }
  mutate("lost_selected_cell", "selected_mcmc_score_summary", function(x) x[-1L, ], "Exact complete eight-scenario")
  mutate("changed_frozen_source", "selected_mcmc_score_summary", function(x) {
    x$posterior_score_mean[1L] <- x$posterior_score_mean[1L] + .001; x
  }, "Immutable selected32 packet")
  mutate("lost_vb_row", "selected_64_score_summary", function(x) x[-64L, ], "Complete coherent selected64")
  mutate("mixed_old_cell", "selected_64_score_summary", function(x) {
    x$posterior_score_mean[1L] <- 999; x
  }, "Selected64 reproduces exact")
  mutate("independent_role_vb_substitution", "selected_vb_score_summary", function(x) {
    x$specification_role[x$scenario_id == "persistent_heavy_tail"][1L] <- "challenger"; x
  }, "Selected64 reproduces exact")
  mutate("missing_shared_backbone", "selected_backbones", function(x) x[-1L, ], "One retained pure-DESN backbone")
  mutate("stale_fit500", "fit_oracle_diagnostics", function(x) { x$fit_observations[1L] <- 500L; x }, "Executed 1300-observation")
  mutate("changed_fit_recovery_metric", "fit_oracle_diagnostics", function(x) {
    x$fit_oracle_quantile_rmse[1L] <- x$fit_oracle_quantile_rmse[1L] + .01; x
  }, "Fit diagnostics preserve")
  mutate("lost_eight_chain_extension", "draw_counts", function(x) {
    at <- x$scenario_id == "laplace_bridge" & x$model_id == "joint_exqdesn_rhs" & x$inference_method == "mcmc"
    x$score_draws[at] <- 4500; x$score_chains[at] <- 3L; x
  }, "Exact AL/exAL retained draws")
  mutate("false_matching_path_extension", "draw_counts", function(x) {
    at <- x$scenario_id == "laplace_bridge" & x$model_id == "joint_exqdesn_rhs" & x$inference_method == "mcmc"
    x$path_score_chains[at] <- 8L; x
  }, "Exact AL/exAL retained draws")
  mutate("different_chain_target", "chain_identity", function(x) {
    x$posterior_target_sha256[1L] <- paste(rep("0", 64L), collapse = ""); x
  }, "Common recorded posterior target")
  mutate("invented_supplemental_hardened_identity", "chain_identity", function(x) {
    x$complete_posterior_target_sha256[x$source_context == "laplace_supplement"] <- paste(rep("0", 64L), collapse = ""); x
  }, "Historical five-chain extension records actual legacy identity")
  mutate("old_truncated_AL_support", "chain_identity", function(x) {
    x$sigma_support[x$likelihood_family == "AL"] <- "start_defined_bounds"; x
  }, "Corrected AL unbounded inverse-gamma")
  mutate("wrong_crossing_denominator", "crossing_summary", function(x) {
    x$mean_grid_comparisons[1L] <- 47520L; x
  }, "Mean-grid and posterior-draw crossing denominators")
  mutate("stale_v2_crossing_count", "crossing_totals", function(x) {
    x$raw_mean_grid_pairs[x$model_id == "joint_qdesn_rhs"] <- 10L; x
  }, "Correct current 47520-comparison")
  mutate("false_marginal_superiority", "scenario_winners", function(x) {
    x$winner_runner_intervals_overlap[1L] <- FALSE; x
  }, "All eight descriptive minima")
  mutate("changed_contrast_arithmetic", "numerical_contrasts", function(x) {
    x$joint_minus_independent_mean[1L] <- 9; x
  }, "Six of sixteen joint means")
  mutate("failed_scientific_gate", "scientific_gates", function(x) { x$status[1L] <- "fail"; x }, "Frozen scientific completion gates")
  mutate("wrong_score_weights", "protocol", function(x) {
    x$value[x$field == "trapezoidal_weights"] <- "1;1;1;1;1;1;1"; x
  }, "Frozen level/weight/target/fit contract")
  mutate("misrepresented_final_selection", "protocol", function(x) {
    x$value[x$field == "protected_evaluation_use"] <- "untouched_final_test"; x
  }, "Frozen level/weight/target/fit contract")
  mutate("false_refit_claim", "projection_provenance", function(x) {
    x$value[x$name == "fitting"] <- "TRUE"; x
  }, "Projection preserves scientific source")
  # Public article fixture requires only the new registered projection, its
  # authenticated generator/style, and current manuscript/allowlist. It never
  # reads ignored fits or copies unrelated application runtime.
  manifest <- read.csv(file.path(root, "tables/joint_qdesn_corrected_v3_article_asset_manifest.csv"))
  article <- file.path(temporary, "article_pristine")
  required <- c(manifest$relative_path, "tables/joint_qdesn_corrected_v3_article_asset_manifest.csv",
    "scripts/build_joint_qdesn_corrected_article_projection_v3.R", "scripts/joint_qdesn_corrected_article_authority_v3.py",
    "scripts/qdesn_evaluation_figure_style.R", "main.tex", "qdesn-supplement.tex", "overleaf/article_files.txt")
  for (relative in required) {
    target <- file.path(article, relative); dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(file.path(root, relative), target))
  }
  complete <- run(article)
  stopifnot(complete$status == 0L, any(startsWith(complete$output, marker)))
  original <- readLines(file.path(article, "main.tex"), warn = FALSE)
  changed <- gsub("tables/joint_qdesn_corrected_v3_forecast_figure.tex",
    "tables/qdesn_multiquantile_forecast_figure_display.tex", original, fixed = TRUE)
  stopifnot(!identical(original, changed)); writeLines(changed, file.path(article, "main.tex"))
  reject(run(article), "stale_active_v2_wrapper", "Current v3 figure and both appendix tables")
  writeLines(original, file.path(article, "main.tex"))
  altered <- gsub("chosen after reviewing evaluation scores and sampling stability",
    "selected without using evaluation scores", paste(original, collapse = "\n"), fixed = TRUE)
  stopifnot(!identical(paste(original, collapse = "\n"), altered))
  writeLines(altered, file.path(article, "main.tex"))
  reject(run(article), "hidden_evaluation_informed_packet_choice", "Final score-informed complete-packet choice")
  writeLines(original, file.path(article, "main.tex"))
  asset <- file.path(article, "tables/joint_qdesn_corrected_v3_compact_scores.tex")
  connection <- file(asset, open = "at"); writeLines("% changed projection", connection); close(connection)
  reject(run(article), "stale_current_asset_hash", "Current asset size/hash")
  cat(paste(passed$output, collapse = "\n"), "\n")
  cat(sprintf("test_joint_qdesn_corrected_article_projection_v3: PASS mutations=%d runtime_reads=0\n", mutations))
})
