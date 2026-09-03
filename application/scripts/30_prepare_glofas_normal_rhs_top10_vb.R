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
  run_label = "glofas_normal_rhs_top10_vb_20260901",
  initial_score_path = "local_trackers/runtime_configs/glofas_normal_part1_ridge_n300_1000_20260901/tables/ridge_scores_latest.csv",
  wide_score_path = "local_trackers/runtime_configs/glofas_normal_part1_wide_frontier_20260901/tables/ridge_scores_latest.csv",
  top_n = "10",
  tau0_values = "1,0.1,0.01,0.001",
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

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
score_paths <- c(
  initial_n300_1000 = app_resolve_path(args$initial_score_path, must_work = TRUE),
  wide_frontier = app_resolve_path(args$wide_score_path, must_work = TRUE)
)
top_n <- as.integer(args$top_n)
tau0_values <- parse_numeric_csv(args$tau0_values)
max_iter <- as.integer(args$max_iter)
min_iter <- as.integer(args$min_iter)
tol <- as.numeric(args$tol)
workers <- as.integer(args$workers)
if (!is.finite(top_n) || top_n < 1L) stop("--top_n must be positive.", call. = FALSE)
if (!is.finite(max_iter) || max_iter < 1L) stop("--max_iter must be positive.", call. = FALSE)
if (!is.finite(min_iter) || min_iter < 1L) stop("--min_iter must be positive.", call. = FALSE)
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

scores <- lapply(names(score_paths), function(nm) {
  x <- app_read_csv(score_paths[[nm]])
  x$source_screen <- nm
  x$source_score_path <- score_paths[[nm]]
  x
})
all_scores <- app_bind_rows_fill(scores)
completed <- all_scores[all_scores$status == "completed" & is.finite(all_scores$valid_mean_crps), , drop = FALSE]
completed <- completed[order(completed$valid_mean_crps, completed$valid_mae, completed$valid_rmse), , drop = FALSE]
if (nrow(completed) < top_n) stop("Not enough completed ridge candidates to select top_n.", call. = FALSE)

top10_raw <- completed[seq_len(top_n), , drop = FALSE]
top10_raw$overall_rank <- seq_len(nrow(top10_raw))
top10 <- app_bind_rows_fill(lapply(seq_len(nrow(top10_raw)), function(i) {
  app_glofas_normal_part1_prefix_existing_score_columns(top10_raw[i, , drop = FALSE])
}))
front <- intersect(
  c(
    "overall_rank", "source_screen", "candidate_id", "D", "n_vector", "n_tilde",
    "lag_id", "m", "output_lag_max", "covariate_lag_max", "alpha", "rho",
    "seed", "ridge_tau2", "intercept_var", "sigma_a", "sigma_b",
    "validation_n", "n_readout_features_actual", "ridge_valid_mean_crps",
    "ridge_valid_mae", "ridge_valid_rmse", "ridge_valid_last200_mean_crps",
    "ridge_valid_last50_mean_crps", "ridge_runtime_seconds", "source_score_path"
  ),
  names(top10)
)
top10 <- top10[c(front, setdiff(names(top10), front))]
top10$warm_start_path <- file.path(root, "objects", paste0(top10$candidate_id, "_ridge_warm_start.rds"))
app_write_csv(top10, file.path(root, "configs", "top10_ridge_candidates.csv"))
writeLines(as.character(top10$candidate_id), file.path(root, "configs", "warm_start_candidate_ids.txt"))

rhs_rows <- vector("list", nrow(top10) * length(tau0_values))
k <- 0L
for (i in seq_len(nrow(top10))) {
  for (tau0 in tau0_values) {
    k <- k + 1L
    label <- paste0("tau", gsub("-", "m", gsub("[.]", "p", format(tau0, scientific = FALSE, trim = TRUE))))
    rhs_rows[[k]] <- cbind(
      data.frame(
        rhs_candidate_id = sprintf("normal_rhs_top10_%02d_%s__%s", top10$overall_rank[[i]], top10$candidate_id[[i]], label),
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
      top10[i, , drop = FALSE]
    )
  }
}
rhs_manifest <- app_bind_rows_fill(rhs_rows)
app_write_csv(rhs_manifest, file.path(root, "configs", "top10_rhs_tau0_manifest.csv"))
writeLines(as.character(rhs_manifest$rhs_candidate_id), file.path(root, "configs", "rhs_candidate_ids.txt"))

selection_summary <- data.frame(
  metric = c(
    "initial_completed", "wide_completed", "combined_completed", "combined_failed",
    "top_n", "tau0_values", "rhs_fit_count", "rhs_max_iter",
    "best_ridge_candidate", "best_ridge_valid_mean_crps"
  ),
  value = c(
    sum(scores[[1L]]$status == "completed"),
    sum(scores[[2L]]$status == "completed"),
    nrow(completed),
    sum(all_scores$status != "completed", na.rm = TRUE),
    nrow(top10),
    paste(tau0_values, collapse = ";"),
    nrow(rhs_manifest),
    max_iter,
    top10$candidate_id[[1L]],
    sprintf("%.9f", top10$ridge_valid_mean_crps[[1L]])
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
    source_score_paths = as.list(score_paths),
    source_score_sha256 = as.list(vapply(score_paths, app_sha256_file, character(1L))),
    top10_candidates_sha256 = app_sha256_file(file.path(root, "configs", "top10_ridge_candidates.csv")),
    rhs_manifest_sha256 = app_sha256_file(file.path(root, "configs", "top10_rhs_tau0_manifest.csv")),
    selection_summary_sha256 = app_sha256_file(file.path(root, "configs", "top10_rhs_selection_summary.csv")),
    screen = list(
      scientific_scope = "USGS-only observed history up to cutoff",
      likelihood = "normal",
      prior = "regularized_horseshoe_rhs_vb",
      readout = "intercept_plus_reservoir_states_only",
      direct_readout_inputs = FALSE,
      top_n = top_n,
      tau0_values = tau0_values,
      total_rhs_fits = nrow(rhs_manifest),
      max_iter = max_iter,
      min_iter = min_iter,
      tol = tol,
      workers_planned = workers
    )
  ),
  file.path(root, "configs", "run_manifest.yaml")
)
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))

cat(root, "\n")
