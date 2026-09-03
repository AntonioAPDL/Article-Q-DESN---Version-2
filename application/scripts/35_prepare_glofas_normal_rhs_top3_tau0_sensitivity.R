#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  run_label = "glofas_normal_rhs_top3_tau0_sensitivity_20260901",
  source_rhs_score_path = "local_trackers/runtime_configs/glofas_normal_rhs_top10_vb_20260901/tables/normal_rhs_scores_latest.csv",
  top_unique_geometries = "3",
  tau0_values = "1e-4,1e-6,1e-9,1e-12",
  max_iter = "100",
  min_iter = "30",
  tol = "1e-4",
  workers = "20"
))

parse_numeric_csv <- function(x) {
  vals <- suppressWarnings(as.numeric(strsplit(gsub("[[:space:]]+", "", as.character(x)), "[,;|]")[[1L]]))
  vals <- vals[is.finite(vals)]
  if (!length(vals)) stop("Expected at least one numeric value.", call. = FALSE)
  vals
}

tau0_label <- function(x) {
  paste0("tau", gsub("\\+", "", gsub("-", "m", gsub("[.]", "p", format(x, scientific = TRUE, trim = TRUE)))))
}

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
source_rhs_score_path <- app_resolve_path(args$source_rhs_score_path, must_work = TRUE)
top_unique_geometries <- as.integer(args$top_unique_geometries)
tau0_values <- parse_numeric_csv(args$tau0_values)
max_iter <- as.integer(args$max_iter)
min_iter <- as.integer(args$min_iter)
tol <- as.numeric(args$tol)
workers <- as.integer(args$workers)
if (!is.finite(top_unique_geometries) || top_unique_geometries < 1L) {
  stop("--top_unique_geometries must be positive.", call. = FALSE)
}
if (!is.finite(max_iter) || max_iter < 1L) stop("--max_iter must be positive.", call. = FALSE)
if (!is.finite(min_iter) || min_iter < 1L) stop("--min_iter must be positive.", call. = FALSE)
if (min_iter > max_iter) stop("--min_iter cannot exceed --max_iter.", call. = FALSE)
if (!is.finite(tol) || tol < 0) stop("--tol must be finite and nonnegative.", call. = FALSE)
if (!is.finite(workers) || workers < 1L) stop("--workers must be positive.", call. = FALSE)

run_label <- as.character(args$run_label)[[1L]]
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) {
  stop("run_label must be path-safe.", call. = FALSE)
}
root <- app_path("local_trackers", "runtime_configs", run_label)
dirs <- file.path(root, c(
  "configs", "logs", "scores", "status", "tables", "objects", "figures",
  "traces", "coefficients", "warm_starts"
))
invisible(lapply(dirs, app_ensure_dir))

rhs_scores <- app_read_csv(source_rhs_score_path)
rhs_numeric_cols <- intersect(
  c(
    "rhs_tau0", "valid_mean_crps", "valid_mae", "valid_rmse",
    "valid_last50_mean_crps", "valid_last200_mean_crps",
    "runtime_seconds", "iterations", "ridge_valid_mean_crps"
  ),
  names(rhs_scores)
)
for (nm in rhs_numeric_cols) rhs_scores[[nm]] <- suppressWarnings(as.numeric(rhs_scores[[nm]]))
completed <- rhs_scores[rhs_scores$status == "completed" & is.finite(rhs_scores$valid_mean_crps), , drop = FALSE]
completed <- completed[order(completed$valid_mean_crps, completed$valid_mae, completed$valid_rmse), , drop = FALSE]
completed <- completed[!duplicated(completed$candidate_id), , drop = FALSE]
if (nrow(completed) < top_unique_geometries) {
  stop("Not enough completed unique RHS geometries to select.", call. = FALSE)
}
selected <- completed[seq_len(top_unique_geometries), , drop = FALSE]
selected$top3_rhs_geometry_rank <- seq_len(nrow(selected))

candidate_keep <- intersect(
  c(
    "top3_rhs_geometry_rank", "source_screen", "candidate_id", "D", "n_vector",
    "n_tilde", "lag_id", "m", "output_lag_max", "covariate_lag_max",
    "alpha", "rho", "seed", "ridge_tau2", "intercept_var", "sigma_a",
    "sigma_b", "validation_n", "ridge_valid_mean_crps", "ridge_valid_mae",
    "ridge_valid_rmse", "ridge_valid_last200_mean_crps",
    "ridge_valid_last50_mean_crps", "ridge_runtime_seconds",
    "source_score_path", "geometry_id", "dynamics_id", "n_state_features",
    "washout", "n_readout_features", "expensive_frontier", "priority",
    "ridge_status", "ridge_n_rows_design", "ridge_n_train", "ridge_n_valid",
    "ridge_n_readout_features_actual", "ridge_design_start_date",
    "ridge_design_end_date", "ridge_valid_start_date", "ridge_valid_end_date",
    "ridge_train_mean_crps", "ridge_train_mae", "ridge_train_rmse",
    "ridge_train_mean_sd", "ridge_train_mean_abs_error",
    "ridge_valid_mean_sd", "ridge_valid_mean_abs_error",
    "ridge_valid_last50_mae", "ridge_valid_last50_rmse",
    "ridge_valid_last50_mean_sd", "ridge_valid_last50_mean_abs_error",
    "ridge_valid_last200_mae", "ridge_valid_last200_rmse",
    "ridge_valid_last200_mean_sd", "ridge_valid_last200_mean_abs_error",
    "ridge_rank_valid_crps"
  ),
  names(selected)
)
top3 <- selected[candidate_keep]
top3$selection_source_rhs_candidate_id <- as.character(selected$rhs_candidate_id)
top3$selection_source_rhs_tau0 <- as.numeric(selected$rhs_tau0)
top3$selection_source_rhs_valid_mean_crps <- as.numeric(selected$valid_mean_crps)
top3$selection_source_rhs_valid_mae <- as.numeric(selected$valid_mae)
top3$selection_source_rhs_valid_rmse <- as.numeric(selected$valid_rmse)
top3$selection_source_rhs_iterations <- as.integer(selected$iterations)
top3$selection_source_rhs_runtime_seconds <- as.numeric(selected$runtime_seconds)
top3$warm_start_path <- file.path(root, "objects", paste0(top3$candidate_id, "_ridge_warm_start.rds"))
app_write_csv(top3, file.path(root, "configs", "top10_ridge_candidates.csv"))
writeLines(as.character(top3$candidate_id), file.path(root, "configs", "warm_start_candidate_ids.txt"))

rhs_rows <- vector("list", nrow(top3) * length(tau0_values))
k <- 0L
for (i in seq_len(nrow(top3))) {
  for (tau0 in tau0_values) {
    k <- k + 1L
    label <- tau0_label(tau0)
    rhs_rows[[k]] <- cbind(
      data.frame(
        rhs_candidate_id = sprintf(
          "normal_rhs_top3tau_%02d_%s__%s",
          top3$top3_rhs_geometry_rank[[i]],
          top3$candidate_id[[i]],
          label
        ),
        rhs_tau0 = tau0,
        rhs_tau0_label = label,
        rhs_max_iter = max_iter,
        rhs_min_iter = min_iter,
        rhs_tol = tol,
        rhs_update_every = 1L,
        rhs_freeze_tau_warmup_iters = 0L,
        rhs_min_tau_updates = 0L,
        warm_start_source = "rebuild_exact_ridge_from_usgs_only_design",
        stringsAsFactors = FALSE
      ),
      top3[i, , drop = FALSE]
    )
  }
}
rhs_manifest <- app_bind_rows_fill(rhs_rows)
app_write_csv(rhs_manifest, file.path(root, "configs", "top10_rhs_tau0_manifest.csv"))
writeLines(as.character(rhs_manifest$rhs_candidate_id), file.path(root, "configs", "rhs_candidate_ids.txt"))

selection_summary <- data.frame(
  metric = c(
    "source_rhs_completed", "source_rhs_unique_geometries", "top_unique_geometries",
    "tau0_values", "rhs_fit_count", "rhs_max_iter", "rhs_min_iter",
    "rhs_tol", "workers_planned", "best_previous_rhs_candidate",
    "best_previous_rhs_valid_mean_crps", "elbo_trace"
  ),
  value = c(
    sum(rhs_scores$status == "completed", na.rm = TRUE),
    length(unique(completed$candidate_id)),
    nrow(top3),
    paste(tau0_values, collapse = ";"),
    nrow(rhs_manifest),
    max_iter,
    min_iter,
    tol,
    workers,
    selected$rhs_candidate_id[[1L]],
    sprintf("%.9f", selected$valid_mean_crps[[1L]]),
    "normal_rhs_partial_elbo"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(selection_summary, file.path(root, "configs", "top10_rhs_selection_summary.csv"))

base_cfg <- app_read_config(base_config)
app_write_yaml(
  list(
    run_label = run_label,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    repo_root = app_repo_root(),
    git_head = app_git_sha(short = FALSE),
    base_config = base_config,
    base_config_sha256 = app_sha256_file(base_config),
    input_manifest = app_config_path(base_cfg, "input_manifest"),
    input_manifest_sha256 = app_sha256_file(app_config_path(base_cfg, "input_manifest")),
    cutoff_path = app_config_path(base_cfg, "cutoffs"),
    cutoff_sha256 = app_sha256_file(app_config_path(base_cfg, "cutoffs")),
    source_rhs_score_path = source_rhs_score_path,
    source_rhs_score_sha256 = app_sha256_file(source_rhs_score_path),
    selected_candidates_sha256 = app_sha256_file(file.path(root, "configs", "top10_ridge_candidates.csv")),
    rhs_manifest_sha256 = app_sha256_file(file.path(root, "configs", "top10_rhs_tau0_manifest.csv")),
    selection_summary_sha256 = app_sha256_file(file.path(root, "configs", "top10_rhs_selection_summary.csv")),
    screen = list(
      scientific_scope = "USGS-only observed history up to cutoff",
      likelihood = "normal",
      prior = "regularized_horseshoe_rhs_vb",
      readout = "intercept_plus_reservoir_states_only",
      direct_readout_inputs = FALSE,
      selection_basis = "best_3_unique_geometries_by_previous_rhs_valid_mean_crps",
      top_unique_geometries = top_unique_geometries,
      tau0_values = tau0_values,
      total_rhs_fits = nrow(rhs_manifest),
      max_iter = max_iter,
      min_iter = min_iter,
      tol = tol,
      workers_planned = workers,
      trace_columns = c(
        "normal_rhs_partial_elbo",
        "normal_rhs_partial_elbo_delta",
        "normal_rhs_partial_elbo_relative_delta"
      ),
      elbo_accounting_label = "normal_rhs_partial_mean_field_accounting_log_precision_approx"
    )
  ),
  file.path(root, "configs", "run_manifest.yaml")
)
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))

cat(root, "\n")
