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
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  ridge_runtime_root = "local_trackers/runtime_configs/glofas_normal_part2_ridge_input_arch_screen_20260902_r2",
  ridge_scores_path = "",
  ridge_health_path = "",
  run_label = "glofas_normal_part2_rhs_top10_vb_20260903",
  top_n = "10",
  tau0_reference_values = "1",
  tau0_discrepancy_values = "1,0.1,0.01,0.001",
  max_iter = "100",
  min_iter = "30",
  tol = "1e-4",
  workers = "20"
))

parse_numeric_csv <- function(x, label) {
  vals <- suppressWarnings(as.numeric(strsplit(gsub("[[:space:]]+", "", as.character(x)), "[,;|]")[[1L]]))
  vals <- vals[is.finite(vals)]
  if (!length(vals)) stop(sprintf("Expected at least one numeric value for %s.", label), call. = FALSE)
  if (any(vals <= 0)) stop(sprintf("%s values must be positive.", label), call. = FALSE)
  vals
}

tau0_label <- function(x) {
  raw <- format(as.numeric(x), scientific = TRUE, trim = TRUE)
  paste0("tau", gsub("\\+", "", gsub("-", "m", gsub("[.]", "p", raw))))
}

prefix_existing_metrics <- function(x) {
  metric_cols <- grep(
    "(^rank_|^status$|_crps$|_mae$|_rmse$|_mean_sd$|_abs_error$|runtime_seconds$|iterations$|converged$|effective_tau$|primary_score_contract$)",
    names(x),
    value = TRUE
  )
  rename <- intersect(metric_cols, names(x))
  names(x)[match(rename, names(x))] <- paste0("ridge_", rename)
  x
}

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
ridge_runtime_root <- app_resolve_path(args$ridge_runtime_root, must_work = TRUE)
ridge_scores_path <- as.character(args$ridge_scores_path)[[1L]]
if (nzchar(ridge_scores_path)) {
  ridge_scores_path <- app_resolve_path(ridge_scores_path, must_work = TRUE)
} else {
  ridge_scores_path <- file.path(ridge_runtime_root, "tables", "part2_ridge_scores_latest.csv")
}
ridge_health_path <- as.character(args$ridge_health_path)[[1L]]
if (nzchar(ridge_health_path)) {
  ridge_health_path <- app_resolve_path(ridge_health_path, must_work = TRUE)
} else {
  ridge_health_path <- file.path(ridge_runtime_root, "tables", "health_latest.csv")
}
top_n <- as.integer(args$top_n)
tau0_reference_values <- parse_numeric_csv(args$tau0_reference_values, "tau0_reference_values")
tau0_discrepancy_values <- parse_numeric_csv(args$tau0_discrepancy_values, "tau0_discrepancy_values")
max_iter <- as.integer(args$max_iter)
min_iter <- as.integer(args$min_iter)
tol <- as.numeric(args$tol)
workers <- as.integer(args$workers)
if (!is.finite(top_n) || top_n < 1L) stop("--top_n must be positive.", call. = FALSE)
if (!is.finite(max_iter) || max_iter < 1L) stop("--max_iter must be positive.", call. = FALSE)
if (!is.finite(min_iter) || min_iter < 1L || min_iter > max_iter) {
  stop("--min_iter must be between 1 and max_iter.", call. = FALSE)
}
if (!is.finite(tol) || tol < 0) stop("--tol must be finite and nonnegative.", call. = FALSE)
if (!is.finite(workers) || workers < 1L) stop("--workers must be positive.", call. = FALSE)

run_label <- as.character(args$run_label)[[1L]]
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) {
  stop("run_label must be path-safe.", call. = FALSE)
}
root <- app_path("local_trackers", "runtime_configs", run_label)
dirs <- file.path(root, c(
  "configs", "logs", "scores", "status", "tables", "objects",
  "traces", "coefficients", "figures"
))
invisible(lapply(dirs, app_ensure_dir))

if (!file.exists(ridge_health_path)) {
  stop(sprintf("Missing Part 2 ridge health table: %s", ridge_health_path), call. = FALSE)
}
ridge_health <- utils::tail(app_read_csv(ridge_health_path), 1L)
if (!identical(as.integer(ridge_health$completed[[1L]]), as.integer(ridge_health$total[[1L]])) ||
    as.integer(ridge_health$running[[1L]]) != 0L ||
    as.integer(ridge_health$pending[[1L]]) != 0L ||
    as.integer(ridge_health$failed[[1L]]) != 0L) {
  stop("Part 2 ridge screen is not complete and clean; refusing to prepare RHS screen.", call. = FALSE)
}

if (!file.exists(ridge_scores_path)) {
  stop(sprintf("Missing Part 2 ridge scores table: %s", ridge_scores_path), call. = FALSE)
}
ridge_scores <- if (nzchar(as.character(args$ridge_scores_path)[[1L]])) {
  app_read_csv(ridge_scores_path)
} else {
  app_glofas_normal_part2_collect_scores(ridge_runtime_root)
}
numeric_cols <- intersect(
  grep("(_crps|_mae|_rmse|_mean_sd|_abs_error|runtime_seconds|n_|alpha|rho|tau0)", names(ridge_scores), value = TRUE),
  names(ridge_scores)
)
for (nm in numeric_cols) ridge_scores[[nm]] <- suppressWarnings(as.numeric(ridge_scores[[nm]]))
score_col <- if ("corrected_valid_mean_crps" %in% names(ridge_scores)) {
  "corrected_valid_mean_crps"
} else {
  "valid_mean_crps"
}
mae_col <- if ("corrected_valid_mae" %in% names(ridge_scores)) "corrected_valid_mae" else "valid_mae"
rmse_col <- if ("corrected_valid_rmse" %in% names(ridge_scores)) "corrected_valid_rmse" else "valid_rmse"
completed <- ridge_scores[
  ridge_scores$status == "completed" & is.finite(ridge_scores[[score_col]]),
  ,
  drop = FALSE
]
completed <- completed[order(completed[[score_col]], completed[[mae_col]], completed[[rmse_col]]), , drop = FALSE]
if (nrow(completed) < top_n) stop("Not enough completed ridge candidates to select top_n.", call. = FALSE)

template_cols <- names(app_glofas_normal_part2_ridge_candidate_manifest(candidate_prefix = "template"))
top_raw <- completed[seq_len(top_n), , drop = FALSE]
top_config <- top_raw[, intersect(names(top_raw), template_cols), drop = FALSE]
top_scores <- prefix_existing_metrics(top_raw[, setdiff(names(top_raw), names(top_config)), drop = FALSE])
top <- cbind(data.frame(overall_rank = seq_len(nrow(top_config)), stringsAsFactors = FALSE), top_config, top_scores)
top$warm_start_path <- file.path(root, "objects", paste0(top$candidate_id, "_part2_ridge_warm_start.rds"))
app_write_csv(top, file.path(root, "configs", "top_ridge_candidates.csv"))
writeLines(as.character(top$candidate_id), file.path(root, "configs", "warm_start_candidate_ids.txt"))

safe_metric <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  x
}
diversity_summary <- data.frame(
  grouping = c(
    "top_n",
    "score_column",
    "score_min",
    "score_max",
    "score_spread",
    "score_spread_percent",
    "unique_input_contracts",
    "unique_D",
    "unique_n_vector",
    "unique_alpha",
    "unique_rho",
    "unique_lag_contracts"
  ),
  value = c(
    as.character(top_n),
    score_col,
    sprintf("%.12g", min(safe_metric(top_raw[[score_col]]), na.rm = TRUE)),
    sprintf("%.12g", max(safe_metric(top_raw[[score_col]]), na.rm = TRUE)),
    sprintf("%.12g", max(safe_metric(top_raw[[score_col]]), na.rm = TRUE) - min(safe_metric(top_raw[[score_col]]), na.rm = TRUE)),
    sprintf("%.4f", 100 * (max(safe_metric(top_raw[[score_col]]), na.rm = TRUE) / min(safe_metric(top_raw[[score_col]]), na.rm = TRUE) - 1)),
    as.character(length(unique(as.character(top_raw$disc_input_contract)))),
    as.character(length(unique(as.character(top_raw$disc_D)))),
    as.character(length(unique(as.character(top_raw$disc_n_vector)))),
    as.character(length(unique(as.character(top_raw$disc_alpha)))),
    as.character(length(unique(as.character(top_raw$disc_rho)))),
    as.character(length(unique(paste(top_raw$disc_output_lag_max, top_raw$disc_covariate_lag_max, top_raw$disc_auxiliary_lag_max, sep = "/"))))
  ),
  stringsAsFactors = FALSE
)
app_write_csv(diversity_summary, file.path(root, "configs", "top_ridge_diversity_summary.csv"))

rhs_rows <- vector("list", nrow(top) * length(tau0_reference_values) * length(tau0_discrepancy_values))
k <- 0L
for (i in seq_len(nrow(top))) {
  for (tau_ref in tau0_reference_values) {
    for (tau_disc in tau0_discrepancy_values) {
      k <- k + 1L
      rhs_rows[[k]] <- cbind(
        data.frame(
          rhs_candidate_id = sprintf(
            "normal_part2_rhs_top%02d_%s__ref%s_disc%s",
            top$overall_rank[[i]],
            top$candidate_id[[i]],
            tau0_label(tau_ref),
            tau0_label(tau_disc)
          ),
          rhs_tau0_reference = tau_ref,
          rhs_tau0_discrepancy = tau_disc,
          rhs_tau0_reference_label = tau0_label(tau_ref),
          rhs_tau0_discrepancy_label = tau0_label(tau_disc),
          rhs_max_iter = max_iter,
          rhs_min_iter = min_iter,
          rhs_tol = tol,
          rhs_update_every = 1L,
          rhs_freeze_tau_warmup_iters = 0L,
          rhs_min_tau_updates = 0L,
          warm_start_source = "rebuild_exact_part2_ridge_components",
          stringsAsFactors = FALSE
        ),
        top[i, , drop = FALSE]
      )
    }
  }
}
rhs_manifest <- app_bind_rows_fill(rhs_rows)
app_write_csv(rhs_manifest, file.path(root, "configs", "part2_rhs_tau0_manifest.csv"))
writeLines(as.character(rhs_manifest$rhs_candidate_id), file.path(root, "configs", "rhs_candidate_ids.txt"))

selection_summary <- data.frame(
  metric = c(
    "ridge_runtime_root", "ridge_total", "ridge_completed", "ridge_failed",
    "top_n", "tau0_reference_values", "tau0_discrepancy_values",
    "rhs_fit_count", "rhs_max_iter", "rhs_min_iter",
    "ridge_scores_path", "ridge_score_column", "best_ridge_candidate",
    "best_ridge_score"
  ),
  value = c(
    ridge_runtime_root,
    as.character(ridge_health$total[[1L]]),
    as.character(ridge_health$completed[[1L]]),
    as.character(ridge_health$failed[[1L]]),
    nrow(top),
    paste(format(tau0_reference_values, scientific = TRUE), collapse = ";"),
    paste(format(tau0_discrepancy_values, scientific = TRUE), collapse = ";"),
    nrow(rhs_manifest),
    max_iter,
    min_iter,
    ridge_scores_path,
    score_col,
    top$candidate_id[[1L]],
    sprintf("%.9f", top_raw[[score_col]][[1L]])
  ),
  stringsAsFactors = FALSE
)
app_write_csv(selection_summary, file.path(root, "configs", "part2_rhs_selection_summary.csv"))

base_cfg <- app_read_config(base_config)
app_write_yaml(
  list(
    run_label = run_label,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    repo_root = app_repo_root(),
    git_head = app_git_sha(short = FALSE),
    base_config = base_config,
    base_config_sha256 = app_sha256_file(base_config),
    ridge_runtime_root = ridge_runtime_root,
    ridge_scores_path = ridge_scores_path,
    ridge_score_column = score_col,
    ridge_scores_sha256 = app_sha256_file(ridge_scores_path),
    ridge_health_path = ridge_health_path,
    ridge_health_sha256 = app_sha256_file(ridge_health_path),
    input_manifest = app_config_path(base_cfg, "input_manifest"),
    input_manifest_sha256 = app_sha256_file(app_config_path(base_cfg, "input_manifest")),
    cutoff_path = app_config_path(base_cfg, "cutoffs"),
    cutoff_sha256 = app_sha256_file(app_config_path(base_cfg, "cutoffs")),
    top_ridge_candidates_sha256 = app_sha256_file(file.path(root, "configs", "top_ridge_candidates.csv")),
    rhs_manifest_sha256 = app_sha256_file(file.path(root, "configs", "part2_rhs_tau0_manifest.csv")),
    selection_summary_sha256 = app_sha256_file(file.path(root, "configs", "part2_rhs_selection_summary.csv")),
    screen = list(
      scientific_scope = "historical paired USGS and retrospective GloFAS up to cutoff",
      likelihood = "normal",
      prior = "regularized_horseshoe_rhs_vb",
      target = "corrected USGS path = retrospective GloFAS minus predicted discrepancy",
      reference_component = app_glofas_normal_part2_fixed_reference_winner(),
      discrepancy_component = "selected from clean Part 2 ridge ranking",
      top_n = top_n,
      tau0_reference_values = as.list(tau0_reference_values),
      tau0_discrepancy_values = as.list(tau0_discrepancy_values),
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
