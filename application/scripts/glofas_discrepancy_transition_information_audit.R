#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_qdesn_features.R", "latent_path_design.R",
  "latent_path_runtime_backend.R", "latent_path_checkpoint.R", "latent_path_vb_al.R",
  "discrepancy_design.R", "forecast_contract.R", "fit_qdesn_latent_path.R",
  "glofas_discrepancy_transition_information_audit.R"
)) {
  source(app_path(file.path("application/R", file)))
}

args <- app_parse_args(list(
  source_root = paste0(
    "/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/",
    "glofas_discrepancy_rhs_plan_20260827/local_trackers/runtime_configs/",
    "glofas_discrepancy_grouped_rhs_stage_a_20260828"
  ),
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_transition_information_audit_20260828",
  candidate_ids = "grhs_a0_01,grhs_a0_04,grhs_a0_06",
  overwrite = FALSE
))

resolve_path <- function(path, must_work = FALSE) {
  normalizePath(if (grepl("^/", path)) path else app_path(path), mustWork = must_work)
}

source_root <- resolve_path(args$source_root, TRUE)
output_root <- resolve_path(args$output_root, FALSE)
candidate_ids <- trimws(unlist(strsplit(as.character(args$candidate_ids), "[,;]")))
candidate_ids <- unique(candidate_ids[nzchar(candidate_ids)])
if (!length(candidate_ids)) stop("At least one candidate ID is required.", call. = FALSE)
if (dir.exists(output_root) && length(list.files(output_root, all.files = TRUE, no.. = TRUE)) &&
    !app_as_bool(args$overwrite)) {
  stop(sprintf("Output root is not empty: %s. Use --overwrite true to rebuild it.", output_root), call. = FALSE)
}
if (dir.exists(output_root) && app_as_bool(args$overwrite)) {
  unlink(output_root, recursive = TRUE, force = TRUE)
}
for (dir in c("tables", "figures", "manifest")) app_ensure_dir(file.path(output_root, dir))

decision_path <- file.path(source_root, "decisions", "stage_a_scientific_decision.csv")
ranking_path <- file.path(source_root, "tables", "all_ranking.csv")
cleanup_path <- file.path(source_root, "cleanup", "all_heavy_artifact_cleanup_dry_run.csv")
for (path in c(decision_path, ranking_path, cleanup_path)) {
  if (!file.exists(path)) stop(sprintf("Required frozen source evidence is missing: %s", path), call. = FALSE)
}
decision <- app_read_csv(decision_path)
ranking <- app_read_csv(ranking_path)
cleanup <- app_read_csv(cleanup_path)
if (nrow(decision) != 1L || as.integer(decision$completed[[1L]]) != 18L ||
    as.integer(decision$failed[[1L]]) != 0L ||
    as.integer(decision$scientific_success_count[[1L]]) != 0L ||
    isTRUE(as.logical(decision$proceed_to_stage_b[[1L]]))) {
  stop("Grouped-RHS source decision differs from the frozen 18/0/0/stop contract.", call. = FALSE)
}

source_evidence <- data.frame(
  candidate_id = NA_character_,
  artifact_role = c("stage_a_decision", "stage_a_ranking", "cleanup_dry_run"),
  path = normalizePath(c(decision_path, ranking_path, cleanup_path), mustWork = TRUE),
  bytes = as.numeric(file.info(c(decision_path, ranking_path, cleanup_path))$size),
  sha256 = vapply(c(decision_path, ranking_path, cleanup_path), app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(decision, file.path(output_root, "tables", "source_stage_a_decision.csv"))
app_write_csv(ranking, file.path(output_root, "tables", "source_stage_a_ranking.csv"))

resolve_candidate <- function(candidate_id) {
  run_id <- paste0("glofas_discrepancy_grouped_rhs_stage_a_20260828_", candidate_id)
  run_dir <- file.path(source_root, "runs", run_id)
  object_dir <- file.path(run_dir, "objects")
  design_path <- list.files(object_dir, pattern = "__design\\.rds$", full.names = TRUE)
  fit_path <- setdiff(list.files(object_dir, pattern = "\\.rds$", full.names = TRUE), design_path)
  prediction_path <- file.path(run_dir, "tables", "prediction_quantiles.csv")
  if (!dir.exists(run_dir) || length(design_path) != 1L || length(fit_path) != 1L ||
      !file.exists(prediction_path) || !file.exists(file.path(run_dir, ".fit_recovery_complete"))) {
    stop(sprintf("Candidate %s does not have one complete retained run bundle.", candidate_id), call. = FALSE)
  }
  list(
    candidate_id = candidate_id,
    run_dir = normalizePath(run_dir, mustWork = TRUE),
    design_path = normalizePath(design_path, mustWork = TRUE),
    fit_path = normalizePath(fit_path, mustWork = TRUE),
    prediction_path = normalizePath(prediction_path, mustWork = TRUE)
  )
}

message("[transition-information-audit] reading retained candidate evidence")
candidate_contracts <- list()
identifiability <- list()
counterfactual_paths <- list()
counterfactual_metrics <- list()
forecast_paths <- list()
signal_panels <- list()
signal_correlations <- list()
artifact_rows <- list()
provenance <- NULL

for (i in seq_along(candidate_ids)) {
  item <- resolve_candidate(candidate_ids[[i]])
  message(sprintf(
    "[transition-information-audit] %s (%d/%d)",
    item$candidate_id, i, length(candidate_ids)
  ))
  design <- readRDS(item$design_path)
  prediction <- app_read_csv(item$prediction_path)
  future <- design$future_builder(design$y_future_init)
  candidate_contracts[[i]] <- cbind(
    data.frame(candidate_id = item$candidate_id, stringsAsFactors = FALSE),
    app_glofas_transition_historical_contract(design)
  )
  identifiability[[i]] <- cbind(
    data.frame(candidate_id = item$candidate_id, stringsAsFactors = FALSE),
    app_glofas_transition_future_identifiability(
      future$X_beta_future,
      future$X_alpha_future
    )
  )
  last_discrepancy <- as.numeric(design$discrepancy_baseline_future[[1L]])
  counterfactual <- app_glofas_transition_counterfactual(
    prediction,
    last_discrepancy = last_discrepancy
  )
  counterfactual$paths$candidate_id <- item$candidate_id
  counterfactual$metrics$candidate_id <- item$candidate_id
  counterfactual_paths[[i]] <- counterfactual$paths
  counterfactual_metrics[[i]] <- counterfactual$metrics
  selected_prediction <- app_glofas_transition_prediction_rows(prediction)
  forecast_paths[[i]] <- data.frame(
    candidate_id = item$candidate_id,
    target_date = selected_prediction$target_date,
    horizon = as.integer(selected_prediction$horizon),
    observed_usgs = as.numeric(selected_prediction$y_reference),
    raw_glofas_p50 = as.numeric(selected_prediction$raw_glofas_quantile),
    observed_discrepancy = as.numeric(selected_prediction$raw_glofas_quantile) -
      as.numeric(selected_prediction$y_reference),
    predicted_discrepancy = as.numeric(selected_prediction$discrepancy_hat),
    last_observed_discrepancy = last_discrepancy,
    discrepancy_error = as.numeric(selected_prediction$discrepancy_hat) -
      (as.numeric(selected_prediction$raw_glofas_quantile) -
        as.numeric(selected_prediction$y_reference)),
    stringsAsFactors = FALSE
  )
  signal_panels[[i]] <- app_glofas_transition_signal_panel(design, prediction)
  signal_panels[[i]]$candidate_id <- item$candidate_id
  signal_correlations[[i]] <- app_glofas_transition_signal_correlations(signal_panels[[i]])
  signal_correlations[[i]]$candidate_id <- item$candidate_id
  if (is.null(provenance)) provenance <- app_glofas_transition_covariate_provenance(design)
  artifact_rows[[i]] <- data.frame(
    candidate_id = item$candidate_id,
    artifact_role = c("retained_fit", "retained_design", "prediction_quantiles"),
    path = c(item$fit_path, item$design_path, item$prediction_path),
    bytes = as.numeric(file.info(c(item$fit_path, item$design_path, item$prediction_path))$size),
    sha256 = vapply(c(item$fit_path, item$design_path, item$prediction_path), app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  rm(design, prediction, future)
  invisible(gc())
}

candidate_contracts <- do.call(rbind, candidate_contracts)
identifiability <- do.call(rbind, identifiability)
counterfactual_paths <- do.call(rbind, counterfactual_paths)
counterfactual_metrics <- do.call(rbind, counterfactual_metrics)
forecast_paths <- do.call(rbind, forecast_paths)
signal_panels <- do.call(rbind, signal_panels)
signal_correlations <- do.call(rbind, signal_correlations)
artifact_manifest <- rbind(source_evidence, do.call(rbind, artifact_rows))

pair_ids <- if (length(candidate_ids) >= 2L) {
  combn(candidate_ids, 2L, simplify = FALSE)
} else {
  list()
}
pairwise <- if (length(pair_ids)) do.call(rbind, lapply(pair_ids, function(ids) {
  left <- forecast_paths[forecast_paths$candidate_id == ids[[1L]], ]
  right <- forecast_paths[forecast_paths$candidate_id == ids[[2L]], ]
  left <- left[order(left$horizon), ]
  right <- right[order(right$horizon), ]
  difference <- left$predicted_discrepancy - right$predicted_discrepancy
  data.frame(
    candidate_a = ids[[1L]],
    candidate_b = ids[[2L]],
    mean_abs_path_difference = mean(abs(difference)),
    max_abs_path_difference = max(abs(difference)),
    path_correlation = stats::cor(left$predicted_discrepancy, right$predicted_discrepancy),
    stringsAsFactors = FALSE
  )
})) else data.frame(
  candidate_a = character(), candidate_b = character(),
  mean_abs_path_difference = numeric(), max_abs_path_difference = numeric(),
  path_correlation = numeric(), stringsAsFactors = FALSE
)

draft_registry <- app_glofas_transition_draft_registry()
pre_screen_decision <- data.frame(
  audit_status = "completed",
  grouped_rhs_completed = as.integer(decision$completed[[1L]]),
  grouped_rhs_failed = as.integer(decision$failed[[1L]]),
  grouped_rhs_scientific_successes = as.integer(decision$scientific_success_count[[1L]]),
  historical_future_target_semantics_match = all(candidate_contracts$target_semantics_match),
  future_component_allocation_identified = all(identifiability$future_sum_identifies_components),
  current_covariates_use_realized_future = any(provenance$uses_realized_future),
  no_refit_counterfactual_is_promotable = FALSE,
  production_screen_launched = FALSE,
  production_screen_authorized = FALSE,
  article_update_authorized = FALSE,
  next_gate = "user_review_of_transition_context_and_scoring_contract",
  reason = paste(
    "Grouped RHS failed; historical one-step and future static-origin targets differ;",
    "future GloFAS identifies only the component sum; refitted transition/context models require approval."
  ),
  stringsAsFactors = FALSE
)

tables <- list(
  transition_contract_audit = candidate_contracts,
  future_identifiability_audit = identifiability,
  forecast_discrepancy_paths = forecast_paths,
  no_refit_transition_paths = counterfactual_paths,
  no_refit_transition_metrics = counterfactual_metrics,
  current_event_signal_panel = signal_panels,
  current_event_signal_correlations = signal_correlations,
  covariate_provenance_audit = provenance,
  candidate_path_equivalence = pairwise,
  draft_screening_registry = draft_registry,
  pre_screen_decision = pre_screen_decision,
  source_artifact_manifest = artifact_manifest
)
for (name in names(tables)) {
  app_write_csv(tables[[name]], file.path(output_root, "tables", paste0(name, ".csv")))
}

message("[transition-information-audit] writing diagnostic figures")
candidate_colors <- stats::setNames(c("#1B4F72", "#117864", "#B03A2E", "#7D3C98")[seq_along(candidate_ids)], candidate_ids)
first <- forecast_paths[forecast_paths$candidate_id == candidate_ids[[1L]], ]
pdf(file.path(output_root, "figures", "forecast_discrepancy_paths.pdf"), width = 10.5, height = 6.5)
forecast_ylim <- range(c(
  forecast_paths$observed_discrepancy,
  forecast_paths$predicted_discrepancy,
  forecast_paths$last_observed_discrepancy
), finite = TRUE)
plot(
  first$target_date,
  first$observed_discrepancy,
  type = "o",
  pch = 16,
  col = "black",
  ylim = forecast_ylim,
  xlab = "Target date",
  ylab = "Transformed GloFAS minus USGS discrepancy",
  main = "Retained discrepancy paths at the fixed forecast origin"
)
abline(h = first$last_observed_discrepancy[[1L]], lty = 2, col = "gray45")
for (candidate_id in candidate_ids) {
  path <- forecast_paths[forecast_paths$candidate_id == candidate_id, ]
  lines(path$target_date, path$predicted_discrepancy, lwd = 2, col = candidate_colors[[candidate_id]])
}
legend(
  "bottomright",
  legend = c("Observed held-out discrepancy", "Last observed discrepancy", candidate_ids),
  col = c("black", "gray45", unname(candidate_colors)),
  lty = c(1, 2, rep(1, length(candidate_ids))),
  lwd = c(1, 1, rep(2, length(candidate_ids))),
  pch = c(16, NA, rep(NA, length(candidate_ids))),
  bty = "n",
  cex = 0.82
)
dev.off()

control_paths <- counterfactual_paths[counterfactual_paths$candidate_id == candidate_ids[[1L]], ]
pdf(file.path(output_root, "figures", "no_refit_transition_counterfactuals.pdf"), width = 10.5, height = 6.5)
counterfactual_ylim <- range(c(
  control_paths$observed_discrepancy,
  control_paths$estimated_discrepancy
), finite = TRUE)
plot(
  first$target_date,
  first$observed_discrepancy,
  type = "o",
  pch = 16,
  col = "black",
  ylim = counterfactual_ylim,
  xlab = "Target date",
  ylab = "Transformed discrepancy",
  main = paste("Diagnostic only: no-refit transition mappings for", candidate_ids[[1L]])
)
phi_values <- sort(unique(control_paths$phi))
phi_colors <- grDevices::hcl.colors(length(phi_values), "Dark 3")
for (i in seq_along(phi_values)) {
  path <- control_paths[control_paths$phi == phi_values[[i]], ]
  lines(path$target_date, path$estimated_discrepancy, lwd = 2, col = phi_colors[[i]])
}
legend(
  "bottomright",
  legend = c("Observed held-out discrepancy", paste0("phi=", format(phi_values, trim = TRUE))),
  col = c("black", phi_colors),
  lty = 1,
  lwd = c(1, rep(2, length(phi_values))),
  pch = c(16, rep(NA, length(phi_values))),
  bty = "n",
  cex = 0.82
)
mtext("Counterfactual curves are not refitted models and cannot support selection.", side = 1, line = 4, cex = 0.8)
dev.off()

control_signal <- signal_panels[signal_panels$candidate_id == candidate_ids[[1L]], ]
signal_names <- c("required_departure", "predicted_innovation", "ppt", "ppt_gefs_reduced_value", "glofas_member_sd")
scaled <- scale(control_signal[, signal_names, drop = FALSE])
pdf(file.path(output_root, "figures", "current_event_information_signals.pdf"), width = 10.5, height = 6.5)
matplot(
  control_signal$target_date,
  scaled,
  type = "l",
  lty = 1,
  lwd = 2,
  col = grDevices::hcl.colors(length(signal_names), "Set 2"),
  xlab = "Target date",
  ylab = "Within-window standardized value",
  main = "Current-event information audit (descriptive, not causal)"
)
legend(
  "topright",
  legend = signal_names,
  col = grDevices::hcl.colors(length(signal_names), "Set 2"),
  lty = 1,
  lwd = 2,
  bty = "n",
  cex = 0.82
)
dev.off()

writeLines(capture.output(sessionInfo()), file.path(output_root, "manifest", "session_info.txt"))
git_state <- c(
  paste("worktree", repo_root),
  paste("branch", system2("git", c("rev-parse", "--abbrev-ref", "HEAD"), stdout = TRUE)),
  paste("head", system2("git", c("rev-parse", "HEAD"), stdout = TRUE)),
  paste("source_root", source_root),
  paste("production_screen_launched", FALSE)
)
writeLines(git_state, file.path(output_root, "manifest", "git_state.txt"))

output_files <- list.files(output_root, recursive = TRUE, full.names = TRUE)
output_files <- output_files[file.info(output_files)$isdir %in% FALSE]
manifest_path <- file.path(output_root, "manifest", "output_manifest.csv")
output_files <- setdiff(output_files, manifest_path)
output_manifest <- data.frame(
  relative_path = substring(output_files, nchar(output_root) + 2L),
  bytes = as.numeric(file.info(output_files)$size),
  sha256 = vapply(output_files, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(output_manifest, manifest_path)

message(sprintf(
  "[transition-information-audit] complete: %s (%d files; production screen not launched)",
  output_root,
  nrow(output_manifest) + 1L
))
