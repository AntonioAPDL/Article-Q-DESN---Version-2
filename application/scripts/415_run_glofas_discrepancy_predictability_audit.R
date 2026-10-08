#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  confirmation_root = "local_trackers/runtime_configs/glofas_search_phase2_rhs_confirm_muscat_20260915_r2",
  packet_root = "local_trackers/runtime_configs/glofas_search_phase2_gate_controller_20260915_r2/staging/confirmation_packaging_recovery_a8d707b",
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_predictability_audit_20260920",
  candidate_id = "search2_dis_009",
  primary_horizon = "28"
))
confirmation_root <- app_resolve_path(args$confirmation_root, must_work = TRUE)
packet_root <- app_resolve_path(args$packet_root, must_work = TRUE)
output_root <- app_resolve_path(args$output_root, must_work = FALSE)
for (sub in c("tables", "figures", "manifests")) app_ensure_dir(file.path(output_root, sub))

normal_crps <- function(observed, mean, sd) {
  sd <- pmax(as.numeric(sd), .Machine$double.eps)
  z <- (observed - mean) / sd
  sd * (z * (2 * stats::pnorm(z) - 1) + 2 * stats::dnorm(z) - 1 / sqrt(pi))
}

ridge_arx <- function(y, ppt, soil, lambda = 1.0e-6) {
  rows <- seq.int(2L, length(y))
  X <- cbind(1, y[rows - 1L], ppt[rows], soil[rows])
  yy <- y[rows]
  keep <- is.finite(yy) & apply(X, 1L, function(x) all(is.finite(x)))
  X <- X[keep, , drop = FALSE]
  yy <- yy[keep]
  penalty <- diag(c(0, rep(lambda, ncol(X) - 1L)))
  as.numeric(solve(crossprod(X) + penalty, crossprod(X, yy)))
}

forecast_files <- Sys.glob(file.path(
  confirmation_root, "forecasts",
  paste0("rhs_seed_confirmation__", args$candidate_id, "__seed*__cal_m100_fixed16__fold_*_forecast.csv")
))
generated <- data.frame(
  source_path = forecast_files,
  source_kind = "confirmation_generated_forecast",
  seed = as.integer(sub(".*__seed([0-9]+)__.*", "\\1", basename(forecast_files))),
  stringsAsFactors = FALSE
)
reused_registry_path <- file.path(confirmation_root, "configs", "reused_score_registry.csv")
reused_registry <- app_read_csv(reused_registry_path)
reused_registry <- reused_registry[
  reused_registry$target == "discrepancy" &
    sub("__seed[0-9]+$", "", reused_registry$candidate_id) == args$candidate_id,
  , drop = FALSE
]
reused <- data.frame(
  source_path = as.character(reused_registry$score_detail_path),
  source_kind = "confirmation_reused_authoritative_score_detail",
  seed = as.integer(reused_registry$seed),
  stringsAsFactors = FALSE
)
sources <- rbind(generated, reused)
if (nrow(sources) != 24L || any(!file.exists(sources$source_path))) {
  stop(sprintf(
    "Expected 24 available confirmation paths (18 generated plus 6 reused); found %d available of %d.",
    sum(file.exists(sources$source_path)), nrow(sources)
  ), call. = FALSE)
}

rows <- lapply(seq_len(nrow(sources)), function(source_row) {
  forecast_path <- sources$source_path[[source_row]]
  forecast <- app_read_csv(forecast_path)
  if (nrow(forecast) != 30L || any(forecast$target != "discrepancy")) {
    stop(sprintf("Invalid frozen discrepancy forecast: %s", forecast_path), call. = FALSE)
  }
  fold_id <- as.character(forecast$fold_id[[1L]])
  packet_path <- file.path(packet_root, "model_inputs", paste0("discrepancy__", fold_id, ".rds"))
  score_path <- file.path(packet_root, "scoring_inputs", paste0("discrepancy__", fold_id, ".csv"))
  packet <- readRDS(packet_path)
  score <- app_read_csv(score_path)
  panel <- packet$panel_bundle$panel
  timeline <- attr(panel, "model_covariate_timeline", exact = TRUE)
  if (!identical(as.Date(score$date), as.Date(forecast$date)) || any(!is.finite(score$observed))) {
    stop(sprintf("Forecast/scoring alignment failed for %s.", fold_id), call. = FALSE)
  }
  if ("observed" %in% names(forecast) &&
      max(abs(as.numeric(forecast$observed) - as.numeric(score$observed))) > 1.0e-12) {
    stop(sprintf("Reused score truth disagrees with the frozen scoring packet for %s.", fold_id), call. = FALSE)
  }
  idx <- match(as.Date(forecast$date), as.Date(timeline$date))
  if (anyNA(idx)) stop(sprintf("Missing oracle covariates for %s.", fold_id), call. = FALSE)
  y_history <- as.numeric(panel$y_reference)
  beta <- ridge_arx(y_history, as.numeric(panel$ppt_scaled), as.numeric(panel$soil_scaled))
  arx <- numeric(nrow(forecast))
  previous <- tail(y_history, 1L)
  for (h in seq_len(nrow(forecast))) {
    arx[[h]] <- sum(beta * c(1, previous, timeline$ppt_scaled[idx[[h]]], timeline$soil_scaled[idx[[h]]]))
    previous <- arx[[h]]
  }
  persistence <- rep(tail(y_history, 1L), nrow(forecast))
  data.frame(
    job_id = forecast$job_id,
    candidate_id = args$candidate_id,
    fold_id = fold_id,
    seed = sources$seed[[source_row]],
    origin_date = as.Date(forecast$origin_date),
    date = as.Date(forecast$date),
    horizon = as.integer(forecast$horizon),
    primary_28 = as.integer(forecast$horizon) <= as.integer(args$primary_horizon),
    observed = as.numeric(score$observed),
    desn_mean = as.numeric(forecast$pred_mean),
    desn_sd = as.numeric(forecast$pred_sd),
    persistence = persistence,
    arx1_oracle_covariates = arx,
    desn_crps = normal_crps(score$observed, forecast$pred_mean, forecast$pred_sd),
    desn_abs_error = abs(forecast$pred_mean - score$observed),
    persistence_abs_error = abs(persistence - score$observed),
    arx_abs_error = abs(arx - score$observed),
    source_kind = sources$source_kind[[source_row]],
    source_path = normalizePath(forecast_path, mustWork = TRUE),
    packet_sha256 = app_sha256_file(packet_path),
    forecast_sha256 = app_sha256_file(forecast_path),
    stringsAsFactors = FALSE
  )
})
detail <- app_bind_rows_fill(rows)
cell_grid <- unique(detail[, c("fold_id", "seed")])
if (length(unique(cell_grid$fold_id)) != 6L || length(unique(cell_grid$seed)) != 4L ||
    nrow(cell_grid) != 24L || any(table(cell_grid$fold_id) != 4L) || any(table(cell_grid$seed) != 6L)) {
  stop("The discrepancy predictability audit does not form the required 6-origin x 4-seed grid.", call. = FALSE)
}
primary <- detail[detail$primary_28, , drop = FALSE]
cell_summary <- app_bind_rows_fill(lapply(split(primary, interaction(primary$fold_id, primary$seed, drop = TRUE)), function(x) data.frame(
  fold_id = x$fold_id[[1L]], seed = x$seed[[1L]], origin_date = x$origin_date[[1L]], n = nrow(x),
  desn_mae = mean(x$desn_abs_error), persistence_mae = mean(x$persistence_abs_error),
  arx_mae = mean(x$arx_abs_error), desn_mean_crps = mean(x$desn_crps),
  desn_gain_vs_persistence = 1 - mean(x$desn_abs_error) / mean(x$persistence_abs_error),
  desn_gain_vs_arx = 1 - mean(x$desn_abs_error) / mean(x$arx_abs_error),
  stringsAsFactors = FALSE
)))
fold_summary <- app_bind_rows_fill(lapply(split(cell_summary, cell_summary$fold_id), function(x) data.frame(
  fold_id = x$fold_id[[1L]], origin_date = x$origin_date[[1L]], seeds = nrow(x),
  desn_mae_mean = mean(x$desn_mae), desn_mae_worst = max(x$desn_mae),
  persistence_mae_mean = mean(x$persistence_mae), arx_mae_mean = mean(x$arx_mae),
  desn_gain_vs_persistence_mean = mean(x$desn_gain_vs_persistence),
  desn_gain_vs_arx_mean = mean(x$desn_gain_vs_arx),
  stringsAsFactors = FALSE
)))
overall <- data.frame(
  candidate_id = args$candidate_id, folds = length(unique(cell_summary$fold_id)), cells = nrow(cell_summary),
  desn_mae_mean = mean(cell_summary$desn_mae), persistence_mae_mean = mean(cell_summary$persistence_mae),
  arx_mae_mean = mean(cell_summary$arx_mae),
  cells_beating_persistence = sum(cell_summary$desn_mae < cell_summary$persistence_mae),
  cells_beating_arx = sum(cell_summary$desn_mae < cell_summary$arx_mae),
  incremental_skill_gate = mean(cell_summary$desn_gain_vs_persistence) > 0 & mean(cell_summary$desn_gain_vs_arx) > 0,
  decision = if (mean(cell_summary$desn_gain_vs_persistence) > 0 & mean(cell_summary$desn_gain_vs_arx) > 0) {
    "retain_search2_discrepancy_geometry_no_search3"
  } else "search3_may_be_considered_after_correction_closeout",
  stringsAsFactors = FALSE
)

app_write_csv(detail, file.path(output_root, "tables", "discrepancy_predictability_detail.csv"))
app_write_csv(cell_summary, file.path(output_root, "tables", "discrepancy_predictability_cell_summary.csv"))
app_write_csv(fold_summary, file.path(output_root, "tables", "discrepancy_predictability_fold_summary.csv"))
app_write_csv(overall, file.path(output_root, "tables", "discrepancy_predictability_overall.csv"))

pdf_path <- file.path(output_root, "figures", "discrepancy_predictability_frozen_origins.pdf")
grDevices::pdf(pdf_path, width = 10.5, height = 7.2, onefile = TRUE)
graphics::matplot(
  seq_len(nrow(fold_summary)),
  cbind(fold_summary$desn_mae_mean, fold_summary$persistence_mae_mean, fold_summary$arx_mae_mean),
  type = "b", pch = c(16, 17, 15), lty = 1, lwd = 2,
  col = c("#0072B2", "#E69F00", "#009E73"), xaxt = "n",
  xlab = "Frozen historical origin", ylab = "Primary 28-day MAE",
  main = "Discrepancy predictability at frozen Search-II origins"
)
graphics::axis(1, at = seq_len(nrow(fold_summary)), labels = sub("fold_", "", fold_summary$fold_id), las = 2, cex.axis = 0.8)
graphics::legend("topright", c("Search-II RHS DESN", "persistence", "ARX(1) + oracle covariates"),
  col = c("#0072B2", "#E69F00", "#009E73"), pch = c(16, 17, 15), lty = 1, lwd = 2, bty = "n")
graphics::mtext("Final 2022-12-25 test window is not used in this decision.", side = 1, line = 4.5, cex = 0.8)
grDevices::dev.off()

contract <- data.frame(
  candidate_id = args$candidate_id,
  selection_data = "six_frozen_historical_origins_x_four_predeclared_seeds",
  primary_horizon = as.integer(args$primary_horizon),
  final_2022_12_25_test_used = FALSE,
  persistence_definition = "last_observed_discrepancy_at_origin",
  arx_definition = "ridge_AR1_plus_oracle_ppt_soil_lambda_1e-6_recursive_output",
  response_scale = "frozen_Search_II_discrepancy_score_scale",
  source_grid = "18_generated_confirmation_forecasts_plus_6_reused_authoritative_score_details",
  reused_score_registry_sha256 = app_sha256_file(reused_registry_path),
  stringsAsFactors = FALSE
)
app_write_csv(contract, file.path(output_root, "manifests", "discrepancy_predictability_contract.csv"))
message(sprintf("Discrepancy predictability audit complete: %s", pdf_path))
