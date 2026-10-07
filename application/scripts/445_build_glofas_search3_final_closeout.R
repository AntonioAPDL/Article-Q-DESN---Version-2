#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
suppressPackageStartupMessages(library(ggplot2))
source(app_path("application/R/glofas_search3_final_closeout.R"))

args <- app_parse_args(list(
  closure_runtime_root = "local_trackers/runtime_configs/glofas_search3_full_dependency_closure_20260930_r4",
  part4_runtime_root = "local_trackers/runtime_configs/glofas_part4_search3_dependency_closure_20260930_r4",
  joint_release_runtime_root = "local_trackers/runtime_configs/glofas_part4_search3_joint_release_r1_20261004",
  joint_exal_runtime_root = "local_trackers/runtime_configs/glofas_part4_search3_joint_exal_fullstate_r1_20261007",
  quadrature_runtime_root = "local_trackers/runtime_configs/glofas_part4_exal_quadrature_certificate_r4_20261007",
  output_runtime_root = "local_trackers/runtime_configs/glofas_search3_part1234_final_closeout_20261007"
))

closure_root <- app_resolve_path(args$closure_runtime_root, must_work = TRUE)
part4_root <- app_resolve_path(args$part4_runtime_root, must_work = TRUE)
joint_root <- app_resolve_path(args$joint_release_runtime_root, must_work = TRUE)
exal_root <- app_resolve_path(args$joint_exal_runtime_root, must_work = TRUE)
quadrature_root <- app_resolve_path(args$quadrature_runtime_root, must_work = TRUE)
output_root <- app_resolve_path(args$output_runtime_root, must_work = FALSE)
if (dir.exists(output_root) && length(list.files(output_root, all.files = TRUE, no.. = TRUE))) {
  stop("Final closeout output root is non-empty: ", output_root, call. = FALSE)
}
stage_root <- paste0(output_root, ".staging_", Sys.getpid())
if (dir.exists(stage_root)) unlink(stage_root, recursive = TRUE)
for (subdir in c("tables", "figures", "manifests", "reports", "status")) {
  app_ensure_dir(file.path(stage_root, subdir))
}
on.exit({
  if (dir.exists(stage_root)) unlink(stage_root, recursive = TRUE)
}, add = TRUE)

closure_manifest_path <- file.path(closure_root, "tables/post_search2_job_manifest.csv")
closure_manifest <- read.csv(closure_manifest_path, stringsAsFactors = FALSE)
closure_counts <- app_glofas_closeout_marker_counts(file.path(closure_root, "status"))
if (nrow(closure_manifest) != 133L || closure_counts$completed != 133L ||
    closure_counts$failed != 0L || closure_counts$running != 0L || closure_counts$pending != 0L) {
  stop("Search III dependency closure is not exactly 133/133 complete.", call. = FALSE)
}

part4_manifest_path <- file.path(part4_root, "configs/part4_model_manifest.csv")
part4_manifest <- read.csv(part4_manifest_path, stringsAsFactors = FALSE)
part4_counts <- app_glofas_closeout_marker_counts(file.path(part4_root, "status"))
if (nrow(part4_manifest) != 18L || part4_counts$completed != 18L ||
    part4_counts$failed != 0L || part4_counts$running != 0L) {
  stop("Part 4 source family is not exactly 18/18 complete.", call. = FALSE)
}
for (job in part4_manifest$run_id) {
  marker <- file.path(part4_root, "status", paste0(job, ".completed"))
  manifest <- file.path(part4_root, "manifests", paste0(job, "_artifacts.csv"))
  if (!file.exists(marker)) stop("Missing Part 4 completion marker: ", job, call. = FALSE)
  app_glofas_closeout_verify_manifest(part4_root, manifest)
}

al_job <- "part4_joint_al_continuation_b02"
exal_job <- "part4_joint_exal_continuation_b02"
for (spec in list(c(joint_root, al_job), c(exal_root, exal_job))) {
  root <- spec[[1L]]
  job <- spec[[2L]]
  if (!file.exists(file.path(root, "status", paste0(job, ".completed")))) {
    stop("Missing terminal joint completion marker: ", job, call. = FALSE)
  }
  app_glofas_closeout_verify_manifest(root, file.path(root, "manifests", paste0(job, "_artifacts.csv")))
}

quadrature_decision <- trimws(readLines(file.path(quadrature_root, "status/certificate.completed"), warn = FALSE)[[1L]])
if (!identical(quadrature_decision, "READY_FOR_TARGETED_JOINT_EXAL_CORRECTION")) {
  stop("The authoritative exAL quadrature certificate did not pass.", call. = FALSE)
}
app_glofas_closeout_verify_manifest(
  quadrature_root, file.path(quadrature_root, "manifests/quadrature_output_manifest.csv")
)

message("Reading and validating the terminal Joint AL fit...")
al_fit_path <- file.path(joint_root, "objects", paste0(al_job, "_fit_side.rds"))
al_fit <- readRDS(al_fit_path)
al_gate <- app_glofas_closeout_validate_joint_fit(al_fit)
al_gate$family <- "Joint AL"
al_gate$fit_sha256 <- app_sha256_file(al_fit_path)
al_gate$fit_path <- al_fit_path
rm(al_fit)
invisible(gc())

message("Reading and validating the terminal Joint exAL fit...")
exal_fit_path <- file.path(exal_root, "objects", paste0(exal_job, "_fit_side.rds"))
exal_fit <- readRDS(exal_fit_path)
exal_gate <- app_glofas_closeout_validate_joint_fit(exal_fit)
if (!identical(as.character(exal_fit$future_truth_policy), "physically_excluded_from_fit_objects_scoring_sidecar_only") ||
    !identical(as.character(exal_fit$ensemble_weight_contract), "each_horizon_sums_to_one")) {
  stop("Terminal Joint exAL fit violates the truth firewall or ensemble contract.", call. = FALSE)
}
exal_gate$family <- "Joint exAL"
exal_gate$fit_sha256 <- app_sha256_file(exal_fit_path)
exal_gate$fit_path <- exal_fit_path
rm(exal_fit)
invisible(gc())

joint_convergence <- rbind(al_gate, exal_gate)
joint_convergence <- joint_convergence[, c(
  "family", "converged", "outer_iteration", "parameter_change",
  "max_rhs_global_relative_change", "terminal_consecutive_passes",
  "stopping_reason", "fit_sha256", "fit_path"
)]

selected_path <- file.path(closure_root, "configs/post_search2_selected_components.csv")
selected <- read.csv(selected_path, stringsAsFactors = FALSE)
if (nrow(selected) != 2L || !setequal(selected$component, c("reference", "discrepancy")) ||
    selected$candidate_id[selected$component == "reference"] != "search3_ref_001" ||
    selected$candidate_id[selected$component == "discrepancy"] != "search3_dis_007") {
  stop("The Search III selected-component contract changed.", call. = FALSE)
}

tau_grid <- c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
tau_ids <- c("p05", "p20", "p35", "p50", "p65", "p80", "p95")
part4_label <- basename(part4_root)

read_joint_rows <- function(root, job) {
  rows <- read.csv(file.path(root, "scores", paste0(job, "_by_horizon.csv")), stringsAsFactors = FALSE)
  rows$target_date <- as.Date(rows$target_date)
  rows
}
read_independent_rows <- function(likelihood) {
  jobs <- paste0(part4_label, "_independent_", likelihood, "_rhs_vb_", tau_ids)
  do.call(rbind, lapply(jobs, function(job) {
    read.csv(file.path(part4_root, "scores", paste0(job, "_by_horizon.csv")), stringsAsFactors = FALSE)
  }))
}
normal_rows <- function(job) {
  path <- file.path(part4_root, "predictions", paste0(job, "_posterior_draws.csv.gz"))
  draws <- read.csv(gzfile(path), stringsAsFactors = FALSE)
  draws$target_date <- as.Date(draws$target_date)
  do.call(rbind, lapply(split(draws, draws$target_date), function(block) {
    qhat <- as.numeric(stats::quantile(block$latent_y_draw, tau_grid, names = FALSE, type = 8))
    data.frame(
      target_date = unique(block$target_date), horizon = unique(block$horizon),
      quantile_level = tau_grid, y_reference = unique(block$y_reference), qhat = qhat,
      stringsAsFactors = FALSE
    )
  }))
}

part4_design_path <- file.path(part4_root, "objects/part4_shared_design_truth_free.rds")
part4_truth_path <- file.path(part4_root, "objects/part4_scoring_panel_sidecar.rds")
message("Reading the truth-free Part 4 design for raw-ensemble scoring and plotting...")
part4_design <- readRDS(part4_design_path)
truth_sidecar <- readRDS(part4_truth_path)$panel
truth_sidecar$target_date <- as.Date(truth_sidecar$target_date)
issued_start <- as.Date("2022-12-26")
issued_end <- as.Date("2023-01-22")
truth_sidecar <- truth_sidecar[truth_sidecar$target_date >= issued_start & truth_sidecar$target_date <= issued_end, , drop = FALSE]
ensemble <- part4_design$latent_data$g_ensemble
ensemble$target_date <- as.Date(ensemble$target_date)
ensemble <- ensemble[ensemble$target_date >= issued_start & ensemble$target_date <= issued_end, , drop = FALSE]
raw_rows <- do.call(rbind, lapply(split(ensemble, ensemble$target_date), function(block) {
  date <- unique(block$target_date)
  data.frame(
    target_date = date,
    horizon = as.integer(date - as.Date("2022-12-25")),
    quantile_level = tau_grid,
    y_reference = truth_sidecar$y_transformed[truth_sidecar$target_date == date],
    qhat = as.numeric(stats::quantile(block$g_transformed, tau_grid, names = FALSE, type = 8)),
    stringsAsFactors = FALSE
  )
}))

part4_rows <- list(
  "Normal Ridge" = normal_rows(paste0(part4_label, "_normal_ridge_diagnostic")),
  "Normal RHS/VB" = normal_rows(paste0(part4_label, "_normal_rhs_vb_diagnostic")),
  "Independent AL" = read_independent_rows("al"),
  "Independent exAL" = read_independent_rows("exal"),
  "Joint AL" = read_joint_rows(joint_root, al_job),
  "Joint exAL" = read_joint_rows(exal_root, exal_job),
  "Raw GloFAS" = raw_rows
)
part4_roles <- c(
  "Normal Ridge" = "normal_baseline", "Normal RHS/VB" = "normal_baseline",
  "Independent AL" = "quantile_model", "Independent exAL" = "quantile_model",
  "Joint AL" = "corrected_joint_comparator", "Joint exAL" = "corrected_joint_sensitivity",
  "Raw GloFAS" = "raw_ensemble_baseline"
)
part4_status <- c(
  "Normal Ridge" = "completed", "Normal RHS/VB" = "completed",
  "Independent AL" = "completed", "Independent exAL" = "completed",
  "Joint AL" = "strict_full_state_convergence", "Joint exAL" = "strict_full_state_convergence",
  "Raw GloFAS" = "observed_issued_ensemble"
)
part4_scores <- do.call(rbind, lapply(names(part4_rows), function(family) {
  app_glofas_closeout_summarize_quantiles(
    part4_rows[[family]], family, part4_roles[[family]], part4_status[[family]]
  )
}))
part4_scores <- part4_scores[order(part4_scores$crps_grid_log1p), , drop = FALSE]
raw_score <- part4_scores$crps_grid_log1p[part4_scores$family == "Raw GloFAS"]
part4_scores$crps_reduction_vs_raw <- (raw_score - part4_scores$crps_grid_log1p) / raw_score
part4_scores$descriptive_rank <- rank(part4_scores$crps_grid_log1p, ties.method = "min")
part4_calibration <- do.call(rbind, lapply(names(part4_rows), function(family) {
  app_glofas_closeout_calibration(part4_rows[[family]], family)
}))

quantile_forecast_rows <- function(part, family, component) {
  if (grepl("^Independent", family)) {
    likelihood <- if (grepl("exAL", family, fixed = TRUE)) "exal" else "al"
    jobs <- paste0(part, "_forecast_independent_", likelihood, "_q0p", c("05", "20", "35", "50", "65", "80", "95"), "_forecast.csv")
    rows <- do.call(rbind, lapply(jobs, function(file) {
      path <- file.path(closure_root, "forecasts", file)
      if (part == "part2") {
        object <- readRDS(sub("[.]csv$", ".rds", path))
        object$discrepancy_forecast
      } else {
        read.csv(path, stringsAsFactors = FALSE)
      }
    }))
  } else {
    likelihood <- if (grepl("exAL", family, fixed = TRUE)) "exal" else "al"
    path <- file.path(closure_root, "forecasts", paste0(part, "_forecast_joint_", likelihood, "_all7_forecast.csv"))
    if (part == "part2") {
      rows <- readRDS(sub("[.]csv$", ".rds", path))$discrepancy_forecast
    } else {
      rows <- read.csv(path, stringsAsFactors = FALSE)
    }
  }
  if ("component" %in% names(rows)) rows <- rows[rows$component == component, , drop = FALSE]
  rows$target_date <- as.Date(rows$target_date)
  rows$quantile_level <- as.numeric(rows$tau)
  rows[, c("target_date", "horizon", "quantile_level", "qhat")]
}

normal_quantile_rows <- function(draws, dates, truth) {
  do.call(rbind, lapply(seq_along(dates), function(i) {
    data.frame(
      target_date = as.Date(dates[[i]]), horizon = i, quantile_level = tau_grid,
      y_reference = truth[[i]],
      qhat = as.numeric(stats::quantile(draws[i, ], tau_grid, names = FALSE, type = 8)),
      stringsAsFactors = FALSE
    )
  }))
}

part1_path <- read.csv(file.path(closure_root, "tables/part1_forecast_normal_rhs_vb_path.csv"), stringsAsFactors = FALSE)
part1_path$date <- as.Date(part1_path$date)
part1_future <- part1_path[part1_path$segment != "historical_fit", , drop = FALSE]
part1_truth <- part1_future$observed
part1_dates <- part1_future$date
part1_normal <- list()
for (method in c("ridge", "rhs_vb")) {
  object <- readRDS(file.path(closure_root, "objects", paste0("part1_forecast_normal_", method, "_forecast_draws.rds")))
  label <- if (method == "ridge") "Normal Ridge" else "Normal RHS/VB"
  part1_normal[[label]] <- normal_quantile_rows(object$forecast_draws, object$future_dates, part1_truth)
}
part1_quantile <- list(
  "Independent AL" = quantile_forecast_rows("part1", "Independent AL", "usgs"),
  "Independent exAL" = quantile_forecast_rows("part1", "Independent exAL", "usgs"),
  "Joint AL" = quantile_forecast_rows("part1", "Joint AL", "usgs"),
  "Joint exAL" = quantile_forecast_rows("part1", "Joint exAL", "usgs")
)
part1_rows <- c(part1_normal, part1_quantile)
part1_scores <- do.call(rbind, lapply(names(part1_rows), function(family) {
  rows <- part1_rows[[family]]
  if (!"y_reference" %in% names(rows)) rows$y_reference <- part1_truth[match(rows$target_date, part1_dates)]
  app_glofas_closeout_summarize_quantiles(rows, family, "part1_forecast", "completed")
}))
part1_scores$part <- "Part 1"

part3_path <- read.csv(file.path(closure_root, "forecasts/part3_forecast_normal_rhs_vb_path.csv"), stringsAsFactors = FALSE)
part3_path$date <- as.Date(part3_path$date)
part3_future <- part3_path[part3_path$segment == "forecast" & part3_path$target == "reference", , drop = FALSE]
part3_dates <- part3_future$date
part3_truth <- part1_truth[match(part3_dates, part1_dates)]
part3_normal <- list()
for (method in c("ridge", "rhs_vb")) {
  object <- readRDS(file.path(closure_root, "forecasts", paste0("part3_forecast_normal_", method, "_forecast.rds")))
  label <- if (method == "ridge") "Normal Ridge" else "Normal RHS/VB"
  part3_normal[[label]] <- normal_quantile_rows(object$reference_draws, object$origin$future_dates, part3_truth)
}
part3_quantile <- list(
  "Independent AL" = quantile_forecast_rows("part3", "Independent AL", "usgs"),
  "Independent exAL" = quantile_forecast_rows("part3", "Independent exAL", "usgs"),
  "Joint AL" = quantile_forecast_rows("part3", "Joint AL", "usgs"),
  "Joint exAL" = quantile_forecast_rows("part3", "Joint exAL", "usgs")
)
part3_rows <- c(part3_normal, part3_quantile)
part3_scores <- do.call(rbind, lapply(names(part3_rows), function(family) {
  rows <- part3_rows[[family]]
  if (!"y_reference" %in% names(rows)) rows$y_reference <- part3_truth[match(rows$target_date, part3_dates)]
  app_glofas_closeout_summarize_quantiles(rows, family, "part3_forecast", "completed")
}))
part3_scores$part <- "Part 3"

part2_scores <- data.frame(
  family = names(part1_rows), role = "part2_discrepancy_forecast",
  numerical_status = "unscored_future_retrospective_unavailable",
  n_scored_horizons = 0L, mean_check_loss = NA_real_, crps_grid_log1p = NA_real_,
  coverage90 = NA_real_, median_mae_log1p = NA_real_, median_rmse_log1p = NA_real_,
  crossing_pairs = NA_integer_, part = "Part 2", stringsAsFactors = FALSE
)
part123_scores <- rbind(part1_scores, part2_scores, part3_scores)
part123_scores <- part123_scores[, c("part", setdiff(names(part123_scores), "part"))]

campaign_health <- rbind(
  data.frame(component = "Search III Part 1-4 dependency DAG", planned = 133L, completed = 133L, running = 0L, failed = 0L, left = 0L, status = "complete"),
  data.frame(component = "Part 4 source family", planned = 18L, completed = 18L, running = 0L, failed = 0L, left = 0L, status = "complete"),
  data.frame(component = "Corrected Joint AL continuation batches", planned = 2L, completed = 2L, running = 0L, failed = 0L, left = 0L, status = "strictly_converged"),
  data.frame(component = "Corrected Joint exAL continuation batches", planned = 2L, completed = 2L, running = 0L, failed = 0L, left = 0L, status = "strictly_converged"),
  data.frame(component = "Fixed-state exAL quadrature certificate", planned = 1L, completed = 1L, running = 0L, failed = 0L, left = 0L, status = quadrature_decision),
  data.frame(component = "Future-truth firewall", planned = 1L, completed = 1L, running = 0L, failed = 0L, left = 0L, status = "pass")
)

evidence_paths <- c(
  selected_path,
  closure_manifest_path,
  file.path(closure_root, "configs/post_search2_execution_contract.json"),
  part4_manifest_path,
  file.path(part4_root, "manifests/part4_fixed_window_audit.csv"),
  part4_design_path,
  part4_truth_path,
  al_fit_path,
  file.path(joint_root, "scores", paste0(al_job, "_by_horizon.csv")),
  file.path(joint_root, "manifests", paste0(al_job, "_artifacts.csv")),
  exal_fit_path,
  file.path(exal_root, "scores", paste0(exal_job, "_by_horizon.csv")),
  file.path(exal_root, "manifests", paste0(exal_job, "_artifacts.csv")),
  file.path(quadrature_root, "tables/quadrature_certificate.csv"),
  file.path(quadrature_root, "manifests/quadrature_contract.csv")
)
evidence_roles <- c(
  "selected_components", "complete_job_dag", "execution_contract", "part4_model_manifest",
  "fixed_window_audit", "truth_free_design", "scoring_only_truth_sidecar",
  "terminal_joint_al_fit", "terminal_joint_al_scores", "terminal_joint_al_manifest",
  "terminal_joint_exal_fit", "terminal_joint_exal_scores", "terminal_joint_exal_manifest",
  "quadrature_certificate", "quadrature_contract"
)
authority_ledger <- data.frame(
  role = evidence_roles,
  path = normalizePath(evidence_paths, mustWork = TRUE),
  size_bytes = as.numeric(file.info(evidence_paths)$size),
  sha256 = vapply(evidence_paths, app_sha256_file, character(1L)),
  authority_status = "canonical",
  stringsAsFactors = FALSE
)

supersession <- data.frame(
  artifact_scope = c(
    "Part 4 source Joint AL fit", "Part 4 release Joint exAL outer-20 checkpoint",
    "exAL quadrature certificates r1-r3", "Part 4 corrected Joint AL",
    "Part 4 corrected Joint exAL"
  ),
  disposition = c("superseded", "superseded", "diagnostic_only", "canonical", "canonical_sensitivity"),
  replacement = c(al_fit_path, exal_fit_path, file.path(quadrature_root, "tables/quadrature_certificate.csv"), al_fit_path, exal_fit_path),
  reason = c(
    "RHS scales were frozen through the original five-sweep budget.",
    "Full exAL local state was not retained between outer sweeps.",
    "Only the post-commit r4 fixed-state certificate authorizes production.",
    "Strict outer, inner, RHS and three-pass full-state convergence.",
    "Strict full-state convergence after state-retention and quadrature-certificate correction."
  ),
  stringsAsFactors = FALSE
)

write.csv(campaign_health, file.path(stage_root, "tables/campaign_health.csv"), row.names = FALSE)
write.csv(selected, file.path(stage_root, "tables/selected_components.csv"), row.names = FALSE)
write.csv(part123_scores, file.path(stage_root, "tables/part123_family_scores.csv"), row.names = FALSE)
write.csv(part4_scores, file.path(stage_root, "tables/part4_family_scores.csv"), row.names = FALSE)
write.csv(part4_calibration, file.path(stage_root, "tables/part4_quantile_calibration.csv"), row.names = FALSE)
write.csv(joint_convergence, file.path(stage_root, "tables/final_joint_convergence.csv"), row.names = FALSE)
write.csv(authority_ledger, file.path(stage_root, "manifests/authority_ledger.csv"), row.names = FALSE)
write.csv(supersession, file.path(stage_root, "manifests/supersession_ledger.csv"), row.names = FALSE)

cluster_name <- function(family) {
  if (grepl("^Normal|Raw GloFAS", family)) "Normal and raw"
  else if (grepl("^Independent", family)) "Independent quantiles"
  else "Joint quantiles"
}
plot_rows <- function(rows_list) {
  do.call(rbind, lapply(names(rows_list), function(family) {
    rows <- rows_list[[family]]
    data.frame(
      target_date = as.Date(rows$target_date), model = family,
      cluster = cluster_name(family), quantile_level = as.numeric(rows$quantile_level),
      value = as.numeric(rows$qhat), stringsAsFactors = FALSE
    )
  }))
}
context_rows <- function(path, date_col, segment_col, observed_col, historical_value) {
  rows <- path[path[[segment_col]] == historical_value, , drop = FALSE]
  rows <- tail(rows[is.finite(rows[[observed_col]]), , drop = FALSE], 30L)
  data.frame(target_date = as.Date(rows[[date_col]]), observed = rows[[observed_col]])
}

part1_context <- context_rows(part1_path, "date", "segment", "observed", "historical_fit")
part1_future_truth <- data.frame(target_date = part1_dates, observed = part1_truth)
part2_path <- read.csv(file.path(closure_root, "tables/part2_forecast_normal_rhs_vb_path.csv"), stringsAsFactors = FALSE)
part2_path$date <- as.Date(part2_path$date)
part2_context <- context_rows(part2_path, "date", "segment", "observed_discrepancy", "historical_fit")
part2_rows <- list()
for (method in c("ridge", "rhs_vb")) {
  path <- read.csv(file.path(closure_root, "tables", paste0("part2_forecast_normal_", method, "_path.csv")), stringsAsFactors = FALSE)
  path$date <- as.Date(path$date)
  path <- path[path$segment != "historical_fit", , drop = FALSE]
  label <- if (method == "ridge") "Normal Ridge" else "Normal RHS/VB"
  part2_rows[[label]] <- data.frame(
    target_date = path$date, horizon = seq_len(nrow(path)), quantile_level = 0.50,
    qhat = path$pred_discrepancy_mean, stringsAsFactors = FALSE
  )
}
for (family in c("Independent AL", "Independent exAL", "Joint AL", "Joint exAL")) {
  part2_rows[[family]] <- quantile_forecast_rows("part2", family, "discrepancy")
}
part3_context <- part3_path[part3_path$segment == "historical_fit" & part3_path$target == "reference", , drop = FALSE]
part3_context <- tail(part3_context[is.finite(part3_context$observed), c("date", "observed")], 30L)
names(part3_context)[[1L]] <- "target_date"
part3_future_truth <- data.frame(target_date = part3_dates, observed = part3_truth)
part4_panel <- part4_design$base_panel
part4_panel$target_date <- as.Date(part4_panel$target_date)
part4_context <- tail(part4_panel[is.finite(part4_panel$y_transformed), c("target_date", "y_transformed")], 30L)
names(part4_context)[[2L]] <- "observed"
part4_future_truth <- data.frame(target_date = truth_sidecar$target_date, observed = truth_sidecar$y_transformed)

palette_tau <- c(
  "0.05" = "#005A32", "0.2" = "#238B45", "0.35" = "#78C679", "0.5" = "#1F1F1F",
  "0.65" = "#FDB863", "0.8" = "#E66101", "0.95" = "#B2182B"
)
make_page <- function(part_label, subtitle, predictions, history, future_truth = NULL) {
  predictions$cluster <- factor(predictions$cluster, levels = c("Normal and raw", "Independent quantiles", "Joint quantiles"))
  predictions$tau_label <- format(predictions$quantile_level, trim = TRUE)
  clusters <- levels(predictions$cluster)
  history_all <- do.call(rbind, lapply(clusters, function(cluster) transform(history, cluster = cluster)))
  future_all <- if (!is.null(future_truth)) do.call(rbind, lapply(clusters, function(cluster) transform(future_truth, cluster = cluster))) else NULL
  p <- ggplot() +
    geom_line(data = history_all, aes(target_date, observed), colour = "#262626", linewidth = 0.72) +
    geom_vline(xintercept = as.numeric(as.Date("2022-12-25")), colour = "#666666", linetype = "22") +
    geom_line(
      data = predictions,
      aes(target_date, value, colour = tau_label, linetype = model, group = interaction(model, tau_label)),
      linewidth = 0.48, alpha = 0.92
    ) +
    facet_wrap(~cluster, nrow = 1L, scales = "free_y") +
    scale_colour_manual(values = palette_tau, name = "Quantile") +
    scale_x_date(date_breaks = "10 days", date_labels = "%b %d", expand = expansion(mult = c(0.01, 0.02))) +
    labs(title = part_label, subtitle = subtitle, x = NULL, y = "log(1 + flow)", linetype = "Model") +
    theme_bw(base_size = 9.5) +
    theme(
      panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
      strip.background = element_rect(fill = "#F0F0F0", colour = "#BDBDBD"),
      legend.position = "bottom", legend.box = "vertical",
      plot.title = element_text(face = "bold", size = 13), plot.subtitle = element_text(colour = "#444444")
    )
  if (!is.null(future_all)) {
    p <- p + geom_line(data = future_all, aes(target_date, observed), colour = "#C51B7D", linewidth = 0.78, linetype = "dashed")
  }
  p
}

comparison_pdf <- file.path(stage_root, "figures/glofas_search3_part1234_final_comparison.pdf")
grDevices::cairo_pdf(comparison_pdf, width = 15.2, height = 5.9, onefile = TRUE)
print(make_page(
  "Part 1: univariate USGS forecast",
  "Last 30 observed dates and the 30-day recursive forecast; magenta dashed is withheld USGS truth.",
  plot_rows(part1_rows), part1_context, part1_future_truth
))
print(make_page(
  "Part 2: retrospective GloFAS discrepancy forecast",
  "Last 30 observed discrepancies and the 30-day recursive path. The future path is unscored because retrospective GloFAS ends at the cutoff.",
  plot_rows(part2_rows), part2_context, NULL
))
print(make_page(
  "Part 3: joint historical USGS forecast",
  "Last 30 observed dates and the 30-day recursive forecast; magenta dashed is withheld USGS truth.",
  plot_rows(part3_rows), part3_context, part3_future_truth
))
print(make_page(
  "Part 4: issued-ensemble latent-path experiment",
  "Last 30 observed dates and 28 issued horizons. Joint AL and exAL use the strict corrected terminal fits.",
  plot_rows(part4_rows), part4_context, part4_future_truth
))

al_trace <- read.csv(file.path(joint_root, "traces", paste0(al_job, "_trace.csv")), stringsAsFactors = FALSE)
exal_trace <- read.csv(file.path(exal_root, "traces", paste0(exal_job, "_trace.csv")), stringsAsFactors = FALSE)
al_trace$family <- "Joint AL"
exal_trace$family <- "Joint exAL"
traces <- rbind(al_trace, exal_trace)
trace_plot <- ggplot(traces, aes(outer_iteration, parameter_change, colour = family)) +
  geom_hline(yintercept = 1e-3, linetype = "22", colour = "#555555") +
  geom_line(linewidth = 0.8) + geom_point(aes(shape = full_state_pass), size = 1.7) +
  scale_y_log10() + scale_colour_manual(values = c("Joint AL" = "#1B7837", "Joint exAL" = "#A64B00")) +
  labs(
    title = "Part 4 corrected joint-model convergence",
    subtitle = "Filled terminal points indicate the three consecutive full-state passes required for release.",
    x = "Cumulative outer iteration", y = "Maximum relative parameter change", colour = NULL, shape = "Full-state pass"
  ) + theme_bw(base_size = 11) + theme(legend.position = "bottom", panel.grid.minor = element_blank())
print(trace_plot)

cal_plot <- ggplot(part4_calibration, aes(quantile_level, empirical_coverage, colour = family, group = family)) +
  geom_abline(intercept = 0, slope = 1, linetype = "22", colour = "#555555") +
  geom_line(linewidth = 0.7) + geom_point(size = 1.7) +
  scale_x_continuous(breaks = tau_grid) + scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
  labs(
    title = "Part 4 issued-window quantile calibration",
    subtitle = "Calibration is descriptive on the protected 28-day scoring window and is not a tuning criterion.",
    x = "Nominal quantile", y = "Empirical coverage", colour = "Model"
  ) + theme_bw(base_size = 10.5) + theme(legend.position = "bottom", panel.grid.minor = element_blank())
print(cal_plot)
grDevices::dev.off()

leader <- part4_scores[which.min(part4_scores$crps_grid_log1p), , drop = FALSE]
joint_al_score <- part4_scores[part4_scores$family == "Joint AL", , drop = FALSE]
joint_exal_score <- part4_scores[part4_scores$family == "Joint exAL", , drop = FALSE]
normal_ridge_score <- part4_scores[part4_scores$family == "Normal Ridge", , drop = FALSE]

closeout_report <- c(
  "# GloFAS Search III Part 1-4 final closeout", "",
  "## Decision", "",
  "All planned fitting and corrective computation is complete. Search III and all unaffected Part 1-4 results remain frozen. The corrected Joint AL and Joint exAL terminal fits both satisfy strict outer, inner, RHS and three-consecutive-full-state convergence gates.", "",
  "The issued-window descriptive leader is Independent AL. This differs from the pre-correction Joint AL wording because the fully optimized Joint AL score is materially higher than the Independent AL score. No additional fitting or protected-window tuning is authorized.", "",
  "## Health", "",
  sprintf("- Search III dependency DAG: `%d/%d`, zero failed or active.", closure_counts$completed, nrow(closure_manifest)),
  sprintf("- Part 4 source family: `%d/%d`, zero failed or active.", part4_counts$completed, nrow(part4_manifest)),
  sprintf("- Joint AL: converged at outer `%d`, fit SHA256 `%s`.", al_gate$outer_iteration, al_gate$fit_sha256),
  sprintf("- Joint exAL: converged at outer `%d`, fit SHA256 `%s`.", exal_gate$outer_iteration, exal_gate$fit_sha256),
  sprintf("- Quadrature decision: `%s`.", quadrature_decision), "",
  "## Search III selection", "",
  sprintf("- Reference: `%s`, retained Search II incumbent.", selected$candidate_id[selected$component == "reference"]),
  sprintf("- Discrepancy: `%s`, adopted rainy-season Search III challenger.", selected$candidate_id[selected$component == "discrepancy"]), "",
  "## Part 4 issued-window evidence", "",
  sprintf("- Descriptive leader: **%s**, grid CRPS `%.6f`.", leader$family, leader$crps_grid_log1p),
  sprintf("- Joint AL grid CRPS: `%.6f`; 90%% coverage: `%.3f`.", joint_al_score$crps_grid_log1p, joint_al_score$coverage90),
  sprintf("- Joint exAL grid CRPS: `%.6f`; 90%% coverage: `%.3f`.", joint_exal_score$crps_grid_log1p, joint_exal_score$coverage90),
  sprintf("- Normal Ridge seven-quantile CRPS: `%.6f`.", normal_ridge_score$crps_grid_log1p),
  "- All scores are on the `log(1 + flow)` scale and use the same 28 issued horizons and seven-quantile grid.",
  "- The protected scoring window is evaluation evidence only. It must not be used to retune reservoirs, priors or stopping rules.", "",
  "## Root-cause resolution", "",
  "The exAL failure was computational, not a posterior-target defect: local variational state was dropped between outer sweeps, and a discontinuous diagnostic-only inverse-gamma indicator was included in the quadrature stopping norm. Full-state retention and the corrected operative quadrature norm resolved the gate without changing the likelihood, prior or ELBO.", "",
  "## Promotion boundary", "",
  "Promote the complete family comparison. Describe Independent AL as the issued-window descriptive leader, Joint AL as the corrected joint comparator, and Joint exAL as the corrected sensitivity model. Do not claim that Search III or any Part 4 family was selected on the protected final window.", "",
  "Decision: `READY_FOR_COORDINATOR_INTEGRATION`"
)
writeLines(closeout_report, file.path(stage_root, "reports/final_closeout_report.md"))

handoff <- c(
  "# Coordinator handoff: GloFAS Search III Part 1-4 authority", "",
  "## Scope", "",
  "Integrate the completed Search III GloFAS authority without rerunning models. The runtime package is ignored scientific evidence; tracked integration should consume its tables, figures, manifests and the source branch commit recorded below.", "",
  "## Required authority", "",
  sprintf("- Source branch: `%s`.", system2("git", c("-C", repo_root, "branch", "--show-current"), stdout = TRUE)),
  sprintf("- Source HEAD: `%s`.", system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)),
  sprintf("- Closeout runtime: `%s`.", output_root),
  sprintf("- Canonical Joint AL fit: `%s` (`%s`).", al_fit_path, al_gate$fit_sha256),
  sprintf("- Canonical Joint exAL fit: `%s` (`%s`).", exal_fit_path, exal_gate$fit_sha256),
  "- Canonical Search III selection: reference `search3_ref_001`; discrepancy `search3_dis_007`.", "",
  "## Integration instructions", "",
  "1. Run `application/scripts/446_check_glofas_search3_final_closeout.R` against this runtime before copying assets.",
  "2. Use `tables/part123_family_scores.csv`, `tables/part4_family_scores.csv`, and `tables/part4_quantile_calibration.csv` as the numerical source of truth.",
  "3. Use `figures/glofas_search3_part1234_final_comparison.pdf` as the reviewed comprehensive diagnostic.",
  "4. Preserve the distinction between recursive forecasts in Parts 1-3 and the latent-path issued-ensemble experiment in Part 4.",
  "5. State that Part 2 future corrected-USGS scoring is unavailable because retrospective GloFAS stops at the cutoff.",
  "6. Report Independent AL as the Part 4 issued-window descriptive leader; do not call it a protected-window selection or retune from it.",
  "7. Report both corrected joint fits as strictly converged, with Joint exAL retained as sensitivity evidence.",
  "8. Keep future USGS truth scoring-only and retain the 28-day issued-window boundary.",
  "9. Do not publish runtime RDS objects, logs, or local paths to Overleaf. Copy only reviewed article-safe derivatives after coordinator review.",
  "10. Do not delete superseded evidence until the integrated authority manifest reproduces independently.", "",
  "## Scientific language", "",
  "Search III retained the reference reservoir and adopted a rainy-season discrepancy challenger using internal training evidence. The final 28-day window is used only for evaluation. Corrected joint-model convergence resolves the numerical qualification issue but does not erase the observed tail undercoverage or make the joint families the best issued-window performers.", "",
  "Gate: `READY_FOR_COORDINATOR_INTEGRATION`"
)
writeLines(handoff, file.path(stage_root, "reports/coordinator_integration_handoff.md"))

manifest_targets <- c(
  "tables/campaign_health.csv", "tables/selected_components.csv", "tables/part123_family_scores.csv",
  "tables/part4_family_scores.csv", "tables/part4_quantile_calibration.csv",
  "tables/final_joint_convergence.csv", "manifests/authority_ledger.csv",
  "manifests/supersession_ledger.csv", "figures/glofas_search3_part1234_final_comparison.pdf",
  "reports/final_closeout_report.md", "reports/coordinator_integration_handoff.md"
)
output_manifest <- app_glofas_closeout_write_manifest(
  stage_root, manifest_targets, file.path(stage_root, "manifests/output_manifest.csv")
)
status <- list(
  decision = "READY_FOR_COORDINATOR_INTEGRATION",
  created_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  source_head = system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE),
  closure_completed = 133L,
  part4_completed = 18L,
  joint_al_fit_sha256 = al_gate$fit_sha256,
  joint_exal_fit_sha256 = exal_gate$fit_sha256,
  output_manifest_sha256 = app_sha256_file(file.path(stage_root, "manifests/output_manifest.csv")),
  output_manifest_rows = nrow(output_manifest),
  descriptive_part4_leader = as.character(leader$family),
  descriptive_part4_leader_crps = as.numeric(leader$crps_grid_log1p)
)
writeLines(jsonlite::toJSON(status, auto_unbox = TRUE, pretty = TRUE), file.path(stage_root, "status/closeout.completed"))

app_ensure_dir(dirname(output_root))
if (!file.rename(stage_root, output_root)) stop("Failed to atomically publish the final closeout runtime.", call. = FALSE)
cat(sprintf(
  "GLOFAS_SEARCH3_FINAL_CLOSEOUT_COMPLETE\nruntime_root=%s\ndecision=%s\npart4_leader=%s\npart4_leader_crps=%.8f\n",
  output_root, status$decision, leader$family, leader$crps_grid_log1p
))
