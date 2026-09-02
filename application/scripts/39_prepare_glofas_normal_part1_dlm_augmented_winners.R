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
source(app_path("application/R/glofas_structural_normal_dlm.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))

parse_numeric_values <- function(x, label) {
  x <- gsub("[[:space:]]+", "", as.character(x)[[1L]])
  out <- suppressWarnings(as.numeric(strsplit(x, "[,;|]", perl = TRUE)[[1L]]))
  if (!length(out) || any(!is.finite(out))) {
    stop(sprintf("%s must contain finite numeric values.", label), call. = FALSE)
  }
  out
}

tau_label <- function(x) {
  x <- as.numeric(x)
  if (!is.finite(x) || x <= 0) stop("tau0 values must be positive.", call. = FALSE)
  if (abs(x - 1) < .Machine$double.eps) return("tau1")
  sx <- format(x, scientific = TRUE, digits = 15)
  sx <- sub("e\\+?0*", "e", sx)
  sx <- sub("e-0*", "em", sx)
  sx <- gsub("\\.", "p", sx)
  paste0("tau", sx)
}

alpha_label <- function(x) {
  x <- as.numeric(x)
  if (!is.finite(x) || x <= 0 || x > 1) {
    stop("alpha values must be in (0, 1].", call. = FALSE)
  }
  sx <- format(x, scientific = FALSE, trim = TRUE, digits = 12)
  sx <- sub("^0\\.", "0p", sx)
  sx <- gsub("\\.", "p", sx)
  paste0("alpha", sx)
}

score_column_from_table <- function(x, requested = "auto") {
  requested <- as.character(requested %||% "auto")[[1L]]
  if (!identical(requested, "auto")) {
    if (!requested %in% names(x)) stop(sprintf("Missing requested score column: %s", requested), call. = FALSE)
    return(requested)
  }
  candidates <- c("valid_mean_crps", "ridge_valid_mean_crps")
  hit <- candidates[candidates %in% names(x)]
  if (!length(hit)) stop("Could not infer a winner score column.", call. = FALSE)
  hit[[1L]]
}

rename_source_result_columns <- function(x) {
  source_cols <- unique(c(
    grep("^(rhs_|valid_|train_)", names(x), value = TRUE),
    intersect(
      c(
        "status", "error_message", "runtime_seconds", "rank_valid_crps",
        "converged", "iterations", "final_delta", "sigma2_mean",
        "effective_tau", "e_inv_tau2", "e_inv_zeta2", "warm_start_path"
      ),
      names(x)
    )
  ))
  source_cols <- setdiff(source_cols, c("ridge_tau2", "intercept_var", "sigma_a", "sigma_b"))
  if (length(source_cols)) {
    names(x)[match(source_cols, names(x))] <- paste0("source_", source_cols)
  }
  x
}

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  source_score_path = "local_trackers/runtime_configs/glofas_normal_rhs_depth_budget_20260902/tables/normal_rhs_scores_latest.csv",
  score_column = "auto",
  run_label = paste0("glofas_normal_part1_dlm_augmented_winners_", format(Sys.time(), "%Y%m%d_%H%M%S")),
  top_n = "3",
  unique_candidate_ids = "true",
  tau0_values = "source",
  alpha_values = "source",
  max_iter = "100",
  min_iter = "30",
  tol = "1e-4",
  workers = "20",
  dlm_timing = "smoothed",
  dlm_allow_smoothed_predictive = "true",
  dlm_covariate_mode = "transfer_plus_readout",
  dlm_backend = "cpp",
  dlm_feature_families = paste(app_glofas_normal_part1_default_dlm_families(), collapse = ";"),
  dlm_lag_policy = "match_output_lag_max"
))

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
source_score_path <- app_resolve_path(args$source_score_path, must_work = TRUE)
top_n <- as.integer(args$top_n)
unique_candidate_ids <- app_as_bool(args$unique_candidate_ids)
max_iter <- as.integer(args$max_iter)
min_iter <- as.integer(args$min_iter)
tol <- as.numeric(args$tol)
workers <- as.integer(args$workers)
if (!is.finite(top_n) || top_n < 1L) stop("--top_n must be positive.", call. = FALSE)
if (!is.finite(max_iter) || max_iter < 1L) stop("--max_iter must be positive.", call. = FALSE)
if (!is.finite(min_iter) || min_iter < 1L || min_iter > max_iter) {
  stop("--min_iter must be positive and no larger than --max_iter.", call. = FALSE)
}
if (!is.finite(tol) || tol < 0) stop("--tol must be finite and nonnegative.", call. = FALSE)
if (!is.finite(workers) || workers < 1L) stop("--workers must be positive.", call. = FALSE)

run_label <- as.character(args$run_label)[[1L]]
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) {
  stop("run_label must be path-safe.", call. = FALSE)
}
root <- app_path("local_trackers", "runtime_configs", run_label)
dirs <- file.path(root, c(
  "configs", "logs", "scores", "status", "tables", "objects", "figures",
  "traces", "coefficients", "warm_starts", "components"
))
invisible(lapply(dirs, app_ensure_dir))

base_cfg <- app_read_config(base_config)
panel_bundle <- app_glofas_normal_part1_prepare_panel(base_cfg)
dlm_fit <- app_glofas_structural_dlm_fit_from_glofas_config(
  base_cfg = base_cfg,
  mode = args$dlm_covariate_mode,
  backend = args$dlm_backend,
  panel_bundle = panel_bundle
)
dlm_timing <- tolower(trimws(as.character(args$dlm_timing)[[1L]]))
dlm_components <- app_glofas_structural_dlm_components(dlm_fit, timing = dlm_timing)
component_path <- file.path(root, "components", sprintf("structural_dlm_components_%s.csv", dlm_timing))
app_write_csv(dlm_components, component_path)
app_write_csv(dlm_fit$score, file.path(root, "components", "structural_dlm_score.csv"))

source_scores <- app_read_csv(source_score_path)
score_col <- score_column_from_table(source_scores, args$score_column)
source_scores[[score_col]] <- suppressWarnings(as.numeric(source_scores[[score_col]]))
status_col <- if ("status" %in% names(source_scores)) "status" else if ("ridge_status" %in% names(source_scores)) "ridge_status" else NA_character_
completed <- source_scores[is.finite(source_scores[[score_col]]), , drop = FALSE]
if (!is.na(status_col)) completed <- completed[completed[[status_col]] == "completed", , drop = FALSE]
if (!nrow(completed)) stop("No completed finite source candidates found.", call. = FALSE)
tie_cols <- intersect(c("valid_mae", "valid_rmse", "ridge_valid_mae", "ridge_valid_rmse"), names(completed))
completed <- completed[do.call(order, c(list(completed[[score_col]]), completed[tie_cols])), , drop = FALSE]
n_completed_finite <- nrow(completed)
if (isTRUE(unique_candidate_ids)) {
  if (!"candidate_id" %in% names(completed)) {
    stop("unique_candidate_ids requires a candidate_id column.", call. = FALSE)
  }
  completed <- completed[!duplicated(as.character(completed$candidate_id)), , drop = FALSE]
}
if (nrow(completed) < top_n) stop("Not enough completed source candidates for requested top_n.", call. = FALSE)
selected <- completed[seq_len(top_n), , drop = FALSE]
selected$source_score_column <- score_col
selected$source_selection_rank <- seq_len(nrow(selected))
selected$source_selection_score <- selected[[score_col]]
selected$source_candidate_id <- as.character(selected$candidate_id)
selected$source_alpha <- if ("alpha" %in% names(selected)) suppressWarnings(as.numeric(selected$alpha)) else NA_real_
selected$source_dynamics_id <- if ("dynamics_id" %in% names(selected)) as.character(selected$dynamics_id) else NA_character_
selected$source_rhs_candidate_id <- if ("rhs_candidate_id" %in% names(selected)) {
  as.character(selected$rhs_candidate_id)
} else {
  NA_character_
}
selected$source_rhs_tau0 <- if ("rhs_tau0" %in% names(selected)) {
  suppressWarnings(as.numeric(selected$rhs_tau0))
} else {
  NA_real_
}

alpha_arg <- tolower(trimws(as.character(args$alpha_values)[[1L]]))
if (identical(alpha_arg, "source")) {
  selected$alpha_override <- FALSE
  selected$alpha_override_label <- "source"
  selected$alpha_sweep_rank <- 1L
} else {
  alpha_values <- parse_numeric_values(args$alpha_values, "alpha_values")
  if (any(alpha_values <= 0 | alpha_values > 1)) {
    stop("alpha_values must all be in (0, 1].", call. = FALSE)
  }
  expanded <- vector("list", nrow(selected))
  for (i in seq_len(nrow(selected))) {
    rows <- selected[rep(i, length(alpha_values)), , drop = FALSE]
    rows$alpha <- alpha_values
    rows$alpha_override <- TRUE
    rows$alpha_override_label <- vapply(alpha_values, alpha_label, character(1))
    rows$alpha_sweep_rank <- seq_along(alpha_values)
    if ("rho" %in% names(rows)) {
      rows$dynamics_id <- mapply(
        app_glofas_normal_part1_dynamics_label,
        rows$alpha,
        rows$rho,
        USE.NAMES = FALSE
      )
    }
    expanded[[i]] <- rows
  }
  selected <- app_bind_rows_fill(expanded)
  selected$source_selection_rank <- as.integer(selected$source_selection_rank)
  rownames(selected) <- NULL
}
selected <- rename_source_result_columns(selected)
candidate_suffix <- ifelse(
  app_as_bool_vec(selected$alpha_override),
  paste0("__", selected$alpha_override_label),
  ""
)
selected$candidate_id <- sprintf(
  "dlmaug_%02d_%02d_%s%s",
  selected$source_selection_rank,
  as.integer(selected$alpha_sweep_rank),
  gsub("[^A-Za-z0-9_.-]", "_", selected$source_candidate_id),
  candidate_suffix
)
selected$warm_start_path <- file.path(root, "objects", paste0(selected$candidate_id, "_ridge_warm_start.rds"))
selected$dlm_extension_enabled <- TRUE
selected$dlm_timing <- dlm_timing
selected$dlm_source <- "structural_normal_dlm"
selected$dlm_covariate_mode <- as.character(args$dlm_covariate_mode)
selected$dlm_backend <- as.character(args$dlm_backend)
selected$dlm_components_path <- component_path
selected$dlm_feature_families <- as.character(args$dlm_feature_families)
selected$dlm_allow_smoothed_predictive <- app_as_bool(args$dlm_allow_smoothed_predictive)
selected$dlm_lag_min <- 1L
lag_policy <- tolower(trimws(as.character(args$dlm_lag_policy)[[1L]]))
if (!identical(lag_policy, "match_output_lag_max")) {
  stop("Only --dlm_lag_policy match_output_lag_max is currently supported.", call. = FALSE)
}
selected$dlm_lag_max <- as.integer(selected$output_lag_max)
selected$screen_role <- "dlm_augmented_normal_rhs_vb_winner_refit"
selected$priority <- seq_len(nrow(selected))

required_cols <- c(
  "candidate_id", "n_vector", "m", "output_lag_max", "covariate_lag_max",
  "washout", "alpha", "rho", "seed", "ridge_tau2", "intercept_var",
  "sigma_a", "sigma_b", "validation_n", "warm_start_path"
)
missing_required <- setdiff(required_cols, names(selected))
if (length(missing_required)) {
  stop(sprintf("Selected winner rows are missing required columns: %s.", paste(missing_required, collapse = ", ")), call. = FALSE)
}

front <- intersect(
  c(
    "priority", "candidate_id", "source_candidate_id", "source_rhs_candidate_id",
    "source_selection_rank", "source_score_column", "source_selection_score",
    "source_alpha", "source_dynamics_id", "source_rhs_tau0", "alpha_override",
    "alpha_override_label", "alpha_sweep_rank", "D", "n_vector", "n_tilde", "lag_id", "m",
    "output_lag_max", "covariate_lag_max", "alpha", "rho", "seed",
    "ridge_tau2", "intercept_var", "sigma_a", "sigma_b", "validation_n",
    "dlm_extension_enabled", "dlm_timing", "dlm_feature_families",
    "dlm_lag_min", "dlm_lag_max", "dlm_covariate_mode", "dlm_backend",
    "dlm_allow_smoothed_predictive", "dlm_components_path", "warm_start_path"
  ),
  names(selected)
)
candidate_manifest <- selected[, c(front, setdiff(names(selected), front)), drop = FALSE]
app_write_csv(candidate_manifest, file.path(root, "configs", "candidate_manifest.csv"))
app_write_csv(candidate_manifest, file.path(root, "configs", "top10_ridge_candidates.csv"))
app_write_csv(candidate_manifest, file.path(root, "configs", "dlm_augmented_winner_candidates.csv"))
writeLines(as.character(candidate_manifest$candidate_id), file.path(root, "configs", "warm_start_candidate_ids.txt"))

tau_arg <- tolower(trimws(as.character(args$tau0_values)[[1L]]))
rhs_rows <- list()
k <- 0L
for (i in seq_len(nrow(candidate_manifest))) {
  tau_values <- if (identical(tau_arg, "source")) {
    tau <- as.numeric(candidate_manifest$source_rhs_tau0[[i]])
    if (!is.finite(tau) || tau <= 0) tau <- 1
    tau
  } else {
    parse_numeric_values(args$tau0_values, "tau0_values")
  }
  for (tau0 in tau_values) {
    k <- k + 1L
    label <- tau_label(tau0)
    rhs_rows[[k]] <- cbind(
      data.frame(
        rhs_candidate_id = sprintf(
          "normal_rhs_dlmaug_%02d_%s__%s",
          k,
          candidate_manifest$candidate_id[[i]],
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
        warm_start_source = "rebuild_exact_dlm_augmented_ridge_from_usgs_only_design",
        stringsAsFactors = FALSE
      ),
      candidate_manifest[i, , drop = FALSE]
    )
  }
}
rhs_manifest <- app_bind_rows_fill(rhs_rows)
app_write_csv(rhs_manifest, file.path(root, "configs", "top10_rhs_tau0_manifest.csv"))
app_write_csv(rhs_manifest, file.path(root, "configs", "dlm_augmented_rhs_manifest.csv"))
writeLines(as.character(rhs_manifest$rhs_candidate_id), file.path(root, "configs", "rhs_candidate_ids.txt"))

selection_summary <- data.frame(
  metric = c(
    "source_score_path", "source_score_column", "source_completed_finite",
    "unique_candidate_ids", "source_top_n", "candidate_fit_count", "rhs_fit_count",
    "tau0_values", "max_iter", "min_iter", "alpha_values",
    "alpha_override_fit_count", "tol", "workers_planned", "dlm_timing", "dlm_covariate_mode",
    "dlm_backend", "dlm_feature_families", "dlm_lag_policy",
    "dlm_allow_smoothed_predictive", "components_path", "best_source_candidate",
    "best_source_score"
  ),
  value = c(
    source_score_path,
    score_col,
    n_completed_finite,
    unique_candidate_ids,
    top_n,
    nrow(candidate_manifest),
    nrow(rhs_manifest),
    as.character(args$tau0_values),
    max_iter,
    min_iter,
    as.character(args$alpha_values),
    nrow(candidate_manifest),
    tol,
    workers,
    dlm_timing,
    as.character(args$dlm_covariate_mode),
    as.character(args$dlm_backend),
    as.character(args$dlm_feature_families),
    lag_policy,
    app_as_bool(args$dlm_allow_smoothed_predictive),
    component_path,
    candidate_manifest$source_candidate_id[[1L]],
    sprintf("%.9f", candidate_manifest$source_selection_score[[1L]])
  ),
  stringsAsFactors = FALSE
)
app_write_csv(selection_summary, file.path(root, "configs", "dlm_augmented_selection_summary.csv"))
app_write_csv(selection_summary, file.path(root, "configs", "top10_rhs_selection_summary.csv"))

launch_command <- sprintf(
  "Rscript application/scripts/34_launch_glofas_normal_rhs_top10_vb.R --runtime_root %s --workers %d",
  shQuote(root),
  workers
)
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
    source_score_path = source_score_path,
    source_score_sha256 = app_sha256_file(source_score_path),
    structural_dlm_components_path = component_path,
    structural_dlm_components_sha256 = app_sha256_file(component_path),
    structural_dlm_score_sha256 = app_sha256_file(file.path(root, "components", "structural_dlm_score.csv")),
    candidate_manifest_sha256 = app_sha256_file(file.path(root, "configs", "dlm_augmented_winner_candidates.csv")),
    rhs_manifest_sha256 = app_sha256_file(file.path(root, "configs", "dlm_augmented_rhs_manifest.csv")),
    selection_summary_sha256 = app_sha256_file(file.path(root, "configs", "dlm_augmented_selection_summary.csv")),
    screen = list(
      scientific_scope = "USGS-only observed history up to cutoff",
      likelihood = "normal",
      prior = "regularized_horseshoe_rhs_vb",
      readout = "intercept_plus_reservoir_states_only",
      direct_readout_inputs = FALSE,
      purpose = "refit existing Part 1 winners with structural-DLM augmented reservoir inputs",
      dlm_extension = list(
        placement = "reservoir_input_only",
        timing = dlm_timing,
        allow_smoothed_predictive = app_as_bool(args$dlm_allow_smoothed_predictive),
        feature_families = strsplit(as.character(args$dlm_feature_families), "[,;|]", perl = TRUE)[[1L]],
        lag_policy = lag_policy,
        covariate_mode = as.character(args$dlm_covariate_mode),
        backend = as.character(args$dlm_backend)
      ),
      source_top_n = top_n,
      unique_candidate_ids = unique_candidate_ids,
      candidate_fits = nrow(candidate_manifest),
      total_rhs_fits = nrow(rhs_manifest),
      alpha_values = as.character(args$alpha_values),
      alpha_override_fits = nrow(candidate_manifest),
      max_iter = max_iter,
      min_iter = min_iter,
      tol = tol,
      workers_planned = workers,
      launch_command = launch_command
    )
  ),
  file.path(root, "configs", "run_manifest.yaml")
)
writeLines(
  c("#!/usr/bin/env bash", "set -euo pipefail", launch_command),
  file.path(root, "configs", "launch_command.sh")
)
Sys.chmod(file.path(root, "configs", "launch_command.sh"), mode = "0755")
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))

cat(root, "\n")
