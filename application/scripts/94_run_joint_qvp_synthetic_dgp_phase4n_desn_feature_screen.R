#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))

args <- app_parse_args(list(
  source_launch_dir = "application/cache/joint_qvp_synthetic_dgp_forecast_phase4j_tau0_candidate_launch_20260704",
  output_dir = "application/cache/joint_qvp_synthetic_dgp_forecast_phase4n_desn_feature_screen_20260706",
  reference_arm = "tau0_0p15_comparator",
  screen_ids = "",
  scenario_ids = "",
  max_targeted_scenarios = "",
  vb_max_iter = "720",
  adaptive_vb_max_iter_grid = "720,960",
  refit_stride = "30",
  forecast_origin_stride = "10",
  max_origins_per_scenario = "100",
  vb_tol = "1e-4",
  kappa = "1",
  a_sigma = "2",
  b_sigma = "1",
  alpha_prior_mean = "empirical_quantile",
  baseline_screen_id = "baseline_current_tau0_0p15"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  out <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  out[nzchar(out)]
}

parse_number_or_inf <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(Inf)
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) stop(sprintf("Expected numeric or Inf, got '%s'.", x), call. = FALSE)
  out
}

parse_int <- function(x, default = NULL) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(default)
  out <- suppressWarnings(as.integer(x))
  if (is.na(out)) stop(sprintf("Expected integer, got '%s'.", x), call. = FALSE)
  out
}

parse_num <- function(x, default = NULL) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(default)
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) stop(sprintf("Expected numeric, got '%s'.", x), call. = FALSE)
  out
}

parse_int_grid <- function(x) {
  out <- suppressWarnings(as.integer(parse_csv(x)))
  out <- out[is.finite(out) & out > 0L]
  if (!length(out)) stop(sprintf("Expected a positive integer grid, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

phase4n_resolve_path <- function(path, must_work = TRUE) {
  path <- as.character(path)[[1L]]
  if (grepl("^/", path)) normalizePath(path, mustWork = must_work) else normalizePath(app_path(path), mustWork = must_work)
}

phase4n_meta_cols <- c("scenario_id", "time_index", "split", "split_index", "retained_time_index")

phase4n_screen_grid <- function(screen_ids = character()) {
  grid <- data.frame(
    screen_id = c(
      "baseline_current_tau0_0p15",
      "baseline_current_tau0_0p10",
      "zscore_tau0_0p15",
      "zscore_tau0_0p10",
      "winsor_zscore_tau0_0p15",
      "winsor_zscore_tau0_0p10",
      "compact_core_tau0_0p15",
      "compact_core_tau0_0p10",
      "tail_robust_tau0_0p15",
      "tail_robust_tau0_0p10",
      "rich_interaction_tau0_0p15",
      "rich_interaction_tau0_0p10",
      "memory_augmented_tau0_0p15",
      "memory_augmented_tau0_0p10"
    ),
    feature_spec_id = rep(
      c("current", "zscore", "winsor_zscore", "compact_core", "tail_robust", "rich_interaction", "memory_augmented"),
      each = 2L
    ),
    screen_class = rep("desn_feature_spec", 14L),
    tau0 = rep(c(0.15, 0.10), 7L),
    zeta2 = Inf,
    alpha_prior_sd = 1,
    rhs_vb_inner = 5L,
    alpha_min_spacing = 0,
    rationale = c(
      "Current Phase 4k reported fit-side design with tau0 0.15.",
      "Current fit-side design with the Phase 4g/4h lower raw-crossing tau0 0.10 reference.",
      "Train-split centered and scaled current design with tau0 0.15.",
      "Train-split centered and scaled current design with tau0 0.10.",
      "Train-split winsorized, centered, and scaled current design with tau0 0.15.",
      "Train-split winsorized, centered, and scaled current design with tau0 0.10.",
      "Compact low-noise core design with tau0 0.15.",
      "Compact low-noise core design with tau0 0.10.",
      "Tail-robust tanh/absolute-lag proxy design with tau0 0.15.",
      "Tail-robust tanh/absolute-lag proxy design with tau0 0.10.",
      "Rich nonlinear interaction design with tau0 0.15.",
      "Rich nonlinear interaction design with tau0 0.10.",
      "Memory-augmented lag proxy design with tau0 0.15.",
      "Memory-augmented lag proxy design with tau0 0.10."
    ),
    stringsAsFactors = FALSE
  )
  if (length(screen_ids)) {
    screen_ids <- unique(as.character(screen_ids))
    missing <- setdiff(screen_ids, grid$screen_id)
    if (length(missing)) stop("Unknown Phase 4n screen id(s): ", paste(missing, collapse = ", "), call. = FALSE)
    grid <- grid[match(screen_ids, grid$screen_id), , drop = FALSE]
  }
  rownames(grid) <- NULL
  app_joint_qvp_validate_phase4_screen_grid(grid, "Phase 4n DESN/feature screen grid")
}

phase4n_select_target_registry <- function(source_launch_dir, reference_arm, scenario_ids = character(), max_targeted_scenarios = Inf) {
  source_launch_dir <- phase4n_resolve_path(source_launch_dir, must_work = TRUE)
  crossing <- app_read_csv(file.path(source_launch_dir, "launch_crossing_by_scenario.csv"))
  registry <- app_read_csv(file.path(source_launch_dir, "launch_registry.csv"))
  app_check_required_columns(crossing, c("screen_id", "scenario_id", "raw_crossing_pairs", "raw_max_crossing_magnitude"), "launch_crossing_by_scenario")
  app_check_required_columns(registry, c("scenario_id", "seed", "tau_grid", "train_length", "test_length"), "launch_registry")
  crossing <- crossing[crossing$screen_id == reference_arm & crossing$raw_crossing_pairs > 0L, , drop = FALSE]
  crossing <- crossing[order(-crossing$raw_crossing_pairs, -crossing$raw_max_crossing_magnitude, crossing$scenario_id), , drop = FALSE]
  if (length(scenario_ids)) {
    scenario_ids <- unique(as.character(scenario_ids))
    crossing <- crossing[crossing$scenario_id %in% scenario_ids | crossing$base_scenario_id %in% scenario_ids, , drop = FALSE]
  }
  if (is.finite(max_targeted_scenarios)) crossing <- head(crossing, as.integer(max_targeted_scenarios))
  if (!nrow(crossing)) stop("No crossing-heavy Phase 4n target rows were selected.", call. = FALSE)
  target_registry <- registry[match(crossing$scenario_id, registry$scenario_id), , drop = FALSE]
  if (any(is.na(target_registry$scenario_id))) stop("Could not match every crossing-heavy row to the launch registry.", call. = FALSE)
  app_joint_qvp_validate_synthetic_dgp_registry(target_registry)
  rownames(target_registry) <- NULL
  rownames(crossing) <- NULL
  list(source_launch_dir = source_launch_dir, crossing = crossing, registry = target_registry)
}

phase4n_train_idx <- function(block) {
  idx <- block$split == "train"
  if (!any(idx)) stop("Feature transform requires at least one train row per scenario.", call. = FALSE)
  idx
}

phase4n_feature_cols <- function(block) {
  setdiff(names(block), phase4n_meta_cols)
}

phase4n_all_na <- function(x) all(!is.finite(as.numeric(x)))

phase4n_safe_scale <- function(x) {
  sx <- stats::sd(x[is.finite(x)])
  if (!is.finite(sx) || sx < 1.0e-8) 1 else sx
}

phase4n_clip_train <- function(x, train, probs = c(0.01, 0.99)) {
  xv <- as.numeric(x)
  tv <- xv[train & is.finite(xv)]
  if (!length(tv)) return(xv)
  qs <- as.numeric(stats::quantile(tv, probs = probs, na.rm = TRUE, names = FALSE, type = 8))
  if (any(!is.finite(qs)) || qs[[1L]] >= qs[[2L]]) return(xv)
  pmin(pmax(xv, qs[[1L]]), qs[[2L]])
}

phase4n_standardize_df <- function(df, train, winsor = FALSE) {
  out <- df
  for (nm in names(out)) {
    x <- as.numeric(out[[nm]])
    if (phase4n_all_na(x)) {
      out[[nm]] <- x
      next
    }
    if (isTRUE(winsor)) x <- phase4n_clip_train(x, train)
    center <- mean(x[train & is.finite(x)], na.rm = TRUE)
    scale <- phase4n_safe_scale(x[train])
    out[[nm]] <- (x - center) / scale
  }
  out
}

phase4n_lag_proxy <- function(x, k = 1L) {
  x <- as.numeric(x)
  if (!length(x)) return(x)
  if (k <= 0L) return(x)
  c(rep(x[[1L]], k), head(x, -k))
}

phase4n_base_numeric <- function(block) {
  out <- block[, phase4n_feature_cols(block), drop = FALSE]
  for (nm in names(out)) out[[nm]] <- as.numeric(out[[nm]])
  out
}

phase4n_keep_nonempty <- function(df) {
  keep <- vapply(df, function(x) any(is.finite(as.numeric(x))), logical(1L))
  df[, keep, drop = FALSE]
}

phase4n_transform_block <- function(block, feature_spec_id) {
  train <- phase4n_train_idx(block)
  base <- phase4n_base_numeric(block)
  lag <- if ("lag_y" %in% names(base)) as.numeric(base$lag_y) else rep(0, nrow(block))
  lag_scale <- phase4n_safe_scale(lag[train])
  abs_lag <- abs(lag)
  spec <- as.character(feature_spec_id)[[1L]]
  if (identical(spec, "current")) {
    return(phase4n_keep_nonempty(base))
  }
  if (identical(spec, "zscore")) {
    return(phase4n_keep_nonempty(phase4n_standardize_df(base, train, winsor = FALSE)))
  }
  if (identical(spec, "winsor_zscore")) {
    return(phase4n_keep_nonempty(phase4n_standardize_df(base, train, winsor = TRUE)))
  }
  if (identical(spec, "compact_core")) {
    cols <- intersect(c("lag_y", "trend", "sin_season", "cos_season", "regime", "post_regime_trend"), names(base))
    return(phase4n_keep_nonempty(phase4n_standardize_df(base[, cols, drop = FALSE], train, winsor = TRUE)))
  }
  if (identical(spec, "tail_robust")) {
    out <- data.frame(
      lag_y_tanh = tanh(lag / lag_scale),
      abs_lag_tanh = abs(tanh(lag / lag_scale)),
      trend = if ("trend" %in% names(base)) base$trend else 0,
      sin_season = if ("sin_season" %in% names(base)) base$sin_season else 0,
      cos_season = if ("cos_season" %in% names(base)) base$cos_season else 0,
      abs_lag_scaled = if ("abs_lag_scaled" %in% names(base)) base$abs_lag_scaled else abs_lag / (1 + abs_lag),
      regime = if ("regime" %in% names(base)) base$regime else NA_real_,
      post_regime_trend = if ("post_regime_trend" %in% names(base)) base$post_regime_trend else NA_real_,
      stringsAsFactors = FALSE
    )
    return(phase4n_keep_nonempty(phase4n_standardize_df(out, train, winsor = TRUE)))
  }
  if (identical(spec, "rich_interaction")) {
    out <- base
    sin <- if ("sin_season" %in% names(base)) base$sin_season else rep(0, nrow(block))
    cos <- if ("cos_season" %in% names(base)) base$cos_season else rep(0, nrow(block))
    trend <- if ("trend" %in% names(base)) base$trend else rep(0, nrow(block))
    out$lag_y_sq_proxy <- (lag / lag_scale)^2
    out$lag_y_tanh <- tanh(lag / lag_scale)
    out$lag_y_sin <- lag * sin
    out$lag_y_cos <- lag * cos
    out$abs_lag_sin <- abs_lag * sin
    out$abs_lag_cos <- abs_lag * cos
    out$lag_y_trend <- lag * trend
    if ("regime" %in% names(base) && any(is.finite(base$regime))) out$regime_lag <- base$regime * lag
    return(phase4n_keep_nonempty(phase4n_standardize_df(out, train, winsor = TRUE)))
  }
  if (identical(spec, "memory_augmented")) {
    out <- base
    lag1 <- phase4n_lag_proxy(lag, 1L)
    lag2 <- phase4n_lag_proxy(lag, 2L)
    out$lag_y_tanh <- tanh(lag / lag_scale)
    out$lag_y_lag1 <- lag1
    out$lag_y_lag2 <- lag2
    out$lag_y_delta <- lag - lag1
    out$lag_y_ma3 <- (lag + lag1 + lag2) / 3
    return(phase4n_keep_nonempty(phase4n_standardize_df(out, train, winsor = TRUE)))
  }
  stop("Unsupported Phase 4n feature_spec_id: ", spec, call. = FALSE)
}

phase4n_bind_rows_fill <- function(rows) {
  cols <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(x) {
    missing <- setdiff(cols, names(x))
    for (nm in missing) x[[nm]] <- NA
    x[, cols, drop = FALSE]
  })
  do.call(rbind, rows)
}

phase4n_transform_design <- function(design, feature_spec_id) {
  app_check_required_columns(design, phase4n_meta_cols, "design_matrix")
  ids <- unique(as.character(design$scenario_id))
  rows <- vector("list", length(ids))
  for (ii in seq_along(ids)) {
    block <- design[design$scenario_id == ids[[ii]], , drop = FALSE]
    block <- block[order(block$time_index), , drop = FALSE]
    meta <- block[, phase4n_meta_cols, drop = FALSE]
    feat <- phase4n_transform_block(block, feature_spec_id)
    rows[[ii]] <- cbind(meta, feat, stringsAsFactors = FALSE)
  }
  out <- phase4n_bind_rows_fill(rows)
  out[order(out$scenario_id, out$time_index), , drop = FALSE]
}

phase4n_feature_diagnostics <- function(design, screen_row) {
  rows <- list()
  for (scenario_id in unique(as.character(design$scenario_id))) {
    block <- design[design$scenario_id == scenario_id, , drop = FALSE]
    train <- block$split == "train"
    feat_cols <- app_joint_qvp_phase3_feature_columns(block)
    Z <- as.matrix(block[train, feat_cols, drop = FALSE])
    storage.mode(Z) <- "double"
    finite <- all(is.finite(Z))
    kappa_val <- NA_real_
    min_sv <- NA_real_
    max_sv <- NA_real_
    rank_val <- NA_integer_
    if (finite && nrow(Z) && ncol(Z)) {
      s <- tryCatch(svd(scale(Z, center = TRUE, scale = FALSE), nu = 0, nv = 0)$d, error = function(e) numeric())
      s <- s[is.finite(s)]
      if (length(s)) {
        min_sv <- min(s)
        max_sv <- max(s)
        rank_val <- sum(s > 1.0e-8 * max(s))
        kappa_val <- if (min_sv > 1.0e-12) max_sv / min_sv else Inf
      }
    }
    rows[[length(rows) + 1L]] <- data.frame(
      screen_id = screen_row$screen_id[[1L]],
      feature_spec_id = screen_row$feature_spec_id[[1L]],
      tau0 = screen_row$tau0[[1L]],
      scenario_id = scenario_id,
      n_train_rows = sum(train),
      n_features = length(feat_cols),
      finite_train_design = finite,
      train_design_rank = rank_val,
      train_design_min_singular_value = min_sv,
      train_design_max_singular_value = max_sv,
      train_design_condition_number = kappa_val,
      max_abs_feature = if (finite && length(Z)) max(abs(Z)) else NA_real_,
      feature_names = paste(feat_cols, collapse = ","),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

phase4n_write_fixture_manifest <- function(fixture_dir, original_manifest_path) {
  manifest <- app_read_csv(original_manifest_path)
  files <- manifest$relative_path
  if (file.exists(file.path(fixture_dir, "feature_spec_metadata.csv")) && !"feature_spec_metadata.csv" %in% files) {
    manifest <- rbind(
      manifest,
      data.frame(label = "feature_spec_metadata", relative_path = "feature_spec_metadata.csv", size_bytes = NA_real_, sha256 = NA_character_, stringsAsFactors = FALSE)
    )
  }
  for (ii in seq_len(nrow(manifest))) {
    p <- file.path(fixture_dir, manifest$relative_path[[ii]])
    if (!file.exists(p)) stop("Missing fixture artifact while rebuilding manifest: ", p, call. = FALSE)
    manifest$size_bytes[[ii]] <- as.numeric(file.info(p)$size)
    manifest$sha256[[ii]] <- app_sha256_file(p)
  }
  app_joint_qvp_write_csv(manifest, file.path(fixture_dir, "artifact_manifest.csv"))
}

phase4n_prepare_feature_fixture <- function(base_fixture_dir, fixture_dir, screen_row) {
  dir.create(fixture_dir, recursive = TRUE, showWarnings = FALSE)
  base_files <- list.files(base_fixture_dir, all.files = FALSE, full.names = TRUE, no.. = TRUE)
  for (src in base_files) {
    nm <- basename(src)
    if (nm %in% c("design_matrix.csv", "artifact_manifest.csv")) next
    ok <- file.copy(src, file.path(fixture_dir, nm), overwrite = TRUE)
    if (!ok) stop("Could not copy fixture artifact: ", src, call. = FALSE)
  }
  design <- app_read_csv(file.path(base_fixture_dir, "design_matrix.csv"))
  transformed <- phase4n_transform_design(design, screen_row$feature_spec_id[[1L]])
  app_joint_qvp_write_csv(transformed, file.path(fixture_dir, "design_matrix.csv"))
  metadata <- data.frame(
    screen_id = screen_row$screen_id[[1L]],
    feature_spec_id = screen_row$feature_spec_id[[1L]],
    tau0 = screen_row$tau0[[1L]],
    transformation = screen_row$rationale[[1L]],
    scaling_policy = "all centering, scaling, and winsorization parameters are estimated from the declared train split only",
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(metadata, file.path(fixture_dir, "feature_spec_metadata.csv"))
  manifest_path <- phase4n_write_fixture_manifest(fixture_dir, file.path(base_fixture_dir, "artifact_manifest.csv"))
  list(
    fixture_dir = fixture_dir,
    design_matrix = transformed,
    artifact_manifest = manifest_path
  )
}

phase4n_recommendation <- function(candidate_ranking, baseline_screen_id) {
  failing_contract <- candidate_ranking[candidate_ranking$contract_crossing_pairs > 0, , drop = FALSE]
  baseline <- candidate_ranking[candidate_ranking$screen_id == baseline_screen_id, , drop = FALSE]
  if (!nrow(baseline)) baseline <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE][1L, , drop = FALSE]
  ordered <- candidate_ranking[order(candidate_ranking$ranking_score), , drop = FALSE]
  best <- ordered[1L, , drop = FALSE]
  raw_improved <- is.finite(best$raw_crossing_pairs[[1L]]) &&
    is.finite(baseline$raw_crossing_pairs[[1L]]) &&
    best$raw_crossing_pairs[[1L]] < baseline$raw_crossing_pairs[[1L]]
  truth_ok <- is.finite(best$truth_mae_mean[[1L]]) &&
    is.finite(baseline$truth_mae_mean[[1L]]) &&
    best$truth_mae_mean[[1L]] <= 1.02 * baseline$truth_mae_mean[[1L]]
  status <- if (nrow(failing_contract)) {
    "blocked_contract_crossing"
  } else if (!identical(best$screen_id[[1L]], baseline$screen_id[[1L]]) && raw_improved && truth_ok) {
    "best_feature_spec_ready_for_full_calibration_rerun"
  } else {
    "review_keep_current_or_expand_feature_screen"
  }
  data.frame(
    scope = "phase4n_desn_feature_screen",
    gate_status = if (nrow(failing_contract)) "fail" else "review",
    recommendation_status = status,
    baseline_screen_id = baseline$screen_id[[1L]],
    best_screen_id = best$screen_id[[1L]],
    best_feature_spec_id = best$feature_spec_id[[1L]],
    best_tau0 = best$tau0[[1L]],
    baseline_raw_crossing_pairs = baseline$raw_crossing_pairs[[1L]],
    best_raw_crossing_pairs = best$raw_crossing_pairs[[1L]],
    best_contract_crossing_pairs = best$contract_crossing_pairs[[1L]],
    baseline_truth_mae_mean = baseline$truth_mae_mean[[1L]],
    best_truth_mae_mean = best$truth_mae_mean[[1L]],
    best_vb_max_iter_rate = best$vb_max_iter_rate[[1L]],
    best_runtime_total_sec = best$runtime_total_sec[[1L]],
    note = app_joint_qvp_ts_assessment_note(c(
      if (nrow(failing_contract)) "at least one feature specification produced contract crossings",
      if (!nrow(failing_contract)) "all feature specifications preserved the monotone reported forecast contract",
      if (raw_improved) "best feature specification reduced raw crossing count relative to baseline",
      if (!truth_ok) "best feature specification has truth-distance review relative to baseline",
      "recommendation is a screening recommendation, not an article-default replacement"
    )),
    stringsAsFactors = FALSE
  )
}

phase4n_readme <- function(run_config, recommendation) {
  c(
    "# Joint-QVP Synthetic DGP Phase 4n DESN/Feature-Spec Screen",
    "",
    "This artifact screens fit-side feature specifications on the Phase 4j crossing-heavy replicated rows.",
    "The synthetic DGP, observed data, truth quantiles, seeds, train/test splits, and raw/contract forecast policy are unchanged.",
    "",
    sprintf("- Source launch directory: `%s`", run_config$source_launch_dir[[1L]]),
    sprintf("- Reference arm for target selection: `%s`", run_config$reference_arm[[1L]]),
    sprintf("- Targeted scenario rows: %s", run_config$n_targeted_scenarios[[1L]]),
    sprintf("- Feature/spec screens: %s", run_config$n_screens[[1L]]),
    sprintf("- Recommendation: %s", recommendation$recommendation_status[[1L]]),
    "",
    "Primary files:",
    "",
    "- `targeted_registry.csv`: exact frozen target rows and seeds.",
    "- `target_source_crossing_rows.csv`: source crossing rows used to select the targets.",
    "- `feature_spec_grid.csv`: fit-feature specifications and tau0 controls.",
    "- `feature_diagnostics.csv`: train-design feature counts and conditioning diagnostics.",
    "- `screen_metric_summary.csv`: raw/contract crossings, truth scores, forecast scores, convergence, and runtime by screen.",
    "- `screen_candidate_ranking.csv`: conservative ranking relative to the current tau0 0.15 feature design.",
    "- `screen_crossing_by_scenario.csv`: scenario-level crossing diagnostics.",
    "- `screen_crossing_by_tau_pair.csv`: adjacent tau-pair crossing diagnostics.",
    "- `screen_truth_by_tau.csv`: truth-distance diagnostics by tau.",
    "- `screen_vb_runtime_summary.csv`: VB refit and runtime diagnostics.",
    "- `screen_recommendation.csv`: recommended next action.",
    "- `screen_run_manifest.csv`: nested Phase 3 manifest verification.",
    "- `artifact_manifest.csv`: SHA-256 hashes for root artifacts."
  )
}

source_launch_dir <- phase4n_resolve_path(arg_value("source_launch_dir"), must_work = TRUE)
out_dir <- phase4n_resolve_path(arg_value("output_dir"), must_work = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
reference_arm <- as.character(arg_value("reference_arm"))[[1L]]
screen_ids <- parse_csv(arg_value("screen_ids"))
scenario_ids <- parse_csv(arg_value("scenario_ids"))
max_targeted_scenarios <- parse_number_or_inf(arg_value("max_targeted_scenarios"))
vb_max_iter <- parse_int(arg_value("vb_max_iter"), 720L)
adaptive_vb_max_iter_grid <- app_joint_qvp_normalize_vb_max_iter_grid(
  vb_max_iter,
  parse_int_grid(arg_value("adaptive_vb_max_iter_grid"))
)
refit_stride <- parse_int(arg_value("refit_stride"), 30L)
forecast_origin_stride <- parse_int(arg_value("forecast_origin_stride"), 10L)
max_origins_per_scenario <- parse_number_or_inf(arg_value("max_origins_per_scenario"))
vb_tol <- parse_num(arg_value("vb_tol"), 1.0e-4)
kappa <- parse_num(arg_value("kappa"), 1)
a_sigma <- parse_num(arg_value("a_sigma"), 2)
b_sigma <- parse_num(arg_value("b_sigma"), 1)
alpha_prior_mean <- as.character(arg_value("alpha_prior_mean"))[[1L]]
baseline_screen_id <- as.character(arg_value("baseline_screen_id"))[[1L]]

target <- phase4n_select_target_registry(
  source_launch_dir = source_launch_dir,
  reference_arm = reference_arm,
  scenario_ids = scenario_ids,
  max_targeted_scenarios = max_targeted_scenarios
)
screen_grid <- phase4n_screen_grid(screen_ids = screen_ids)
if (!baseline_screen_id %in% screen_grid$screen_id) {
  stop("baseline_screen_id must be included in the selected Phase 4n screen grid.", call. = FALSE)
}

base_fixture_dir <- file.path(out_dir, "phase1_fixtures_targeted_base")
base_materialization <- app_joint_qvp_materialize_synthetic_dgp_registry(out_dir = base_fixture_dir, registry = target$registry)
base_fixture_manifest <- app_joint_qvp_phase4_manifest_with_hashes(base_fixture_dir)
if (!all(base_fixture_manifest$hash_verified)) stop("Base targeted fixture manifest failed verification.", call. = FALSE)

run_rows <- list()
metric_rows <- list()
manifest_rows <- list()
feature_diag_rows <- list()

for (ii in seq_len(nrow(screen_grid))) {
  screen <- screen_grid[ii, , drop = FALSE]
  fixture_dir <- file.path(out_dir, "feature_fixtures", screen$screen_id[[1L]])
  prepared <- phase4n_prepare_feature_fixture(base_fixture_dir, fixture_dir, screen)
  feature_diag_rows[[length(feature_diag_rows) + 1L]] <- phase4n_feature_diagnostics(prepared$design_matrix, screen)
  fixture_manifest <- app_joint_qvp_phase4_manifest_with_hashes(fixture_dir)
  if (!all(fixture_manifest$hash_verified)) stop("Feature fixture manifest failed verification for ", screen$screen_id[[1L]], call. = FALSE)
  phase3_dir <- file.path(out_dir, "screen_runs", screen$screen_id[[1L]])
  phase3_result <- app_joint_qvp_run_synthetic_dgp_forecast_validation(
    out_dir = phase3_dir,
    fixture_dir = fixture_dir,
    scenario_ids = target$registry$scenario_id,
    kappa = kappa,
    tau0 = screen$tau0[[1L]],
    zeta2 = screen$zeta2[[1L]],
    a_sigma = a_sigma,
    b_sigma = b_sigma,
    alpha_prior_mean = alpha_prior_mean,
    alpha_prior_sd = screen$alpha_prior_sd[[1L]],
    alpha_min_spacing = screen$alpha_min_spacing[[1L]],
    vb_max_iter = vb_max_iter,
    adaptive_vb_max_iter_grid = adaptive_vb_max_iter_grid,
    rhs_vb_inner = as.integer(screen$rhs_vb_inner[[1L]]),
    refit_stride = refit_stride,
    forecast_origin_stride = forecast_origin_stride,
    max_origins_per_scenario = max_origins_per_scenario,
    vb_tol = vb_tol
  )
  phase3_manifest <- app_joint_qvp_phase4_manifest_with_hashes(phase3_result$out_dir)
  metric_rows[[length(metric_rows) + 1L]] <- app_joint_qvp_phase4g_screen_metrics(phase3_result$out_dir, screen)
  manifest_rows[[length(manifest_rows) + 1L]] <- data.frame(
    screen_id = screen$screen_id[[1L]],
    feature_spec_id = screen$feature_spec_id[[1L]],
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    fixture_artifact_manifest = app_prefer_repo_relative_path(prepared$artifact_manifest),
    fixture_manifest_hashes_verified = all(fixture_manifest$hash_verified),
    phase3_out_dir = app_prefer_repo_relative_path(phase3_result$out_dir),
    phase3_artifact_manifest = app_prefer_repo_relative_path(phase3_result$paths[["artifact_manifest"]]),
    phase3_manifest_hashes_verified = all(phase3_manifest$hash_verified),
    phase3_manifest_sha256 = app_sha256_file(phase3_result$paths[["artifact_manifest"]]),
    stringsAsFactors = FALSE
  )
  run_rows[[length(run_rows) + 1L]] <- data.frame(
    screen_id = screen$screen_id[[1L]],
    feature_spec_id = screen$feature_spec_id[[1L]],
    tau0 = screen$tau0[[1L]],
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    phase3_out_dir = app_prefer_repo_relative_path(phase3_result$out_dir),
    stringsAsFactors = FALSE
  )
}

screen_run_manifest <- do.call(rbind, manifest_rows)
screen_metric_summary <- do.call(rbind, metric_rows)
screen_metric_summary <- merge(
  screen_metric_summary,
  screen_grid[, c("screen_id", "feature_spec_id", "rationale"), drop = FALSE],
  by = "screen_id",
  all.x = TRUE,
  sort = FALSE
)
screen_candidate_ranking <- app_joint_qvp_phase4g_compare_to_baseline(
  screen_metric_summary,
  baseline_screen_id = baseline_screen_id
)
screen_candidate_ranking <- merge(
  screen_candidate_ranking,
  screen_grid[, c("screen_id", "feature_spec_id", "rationale"), drop = FALSE],
  by = "screen_id",
  all.x = TRUE,
  sort = FALSE,
  suffixes = c("", "_grid")
)
if ("feature_spec_id_grid" %in% names(screen_candidate_ranking)) {
  screen_candidate_ranking$feature_spec_id <- screen_candidate_ranking$feature_spec_id %||% screen_candidate_ranking$feature_spec_id_grid
  screen_candidate_ranking$feature_spec_id_grid <- NULL
}
screen_run_manifest_for_phase4h <- screen_run_manifest[, c("screen_id", "phase3_out_dir"), drop = FALSE]
screen_crossing_by_scenario <- app_joint_qvp_phase4h_crossing_by_scenario(
  screen_run_manifest_for_phase4h,
  screen_grid,
  target$registry
)
screen_crossing_by_scenario <- merge(
  screen_crossing_by_scenario,
  screen_grid[, c("screen_id", "feature_spec_id"), drop = FALSE],
  by = "screen_id",
  all.x = TRUE,
  sort = FALSE
)
screen_crossing_by_tau_pair <- app_joint_qvp_phase4h_crossing_by_tau_pair(screen_run_manifest_for_phase4h, screen_grid)
screen_crossing_by_tau_pair <- merge(
  screen_crossing_by_tau_pair,
  screen_grid[, c("screen_id", "feature_spec_id"), drop = FALSE],
  by = "screen_id",
  all.x = TRUE,
  sort = FALSE
)
screen_truth_by_tau <- app_joint_qvp_phase4h_truth_by_tau(screen_run_manifest_for_phase4h, screen_grid)
screen_truth_by_tau <- merge(
  screen_truth_by_tau,
  screen_grid[, c("screen_id", "feature_spec_id"), drop = FALSE],
  by = "screen_id",
  all.x = TRUE,
  sort = FALSE
)
screen_vb_runtime_summary <- screen_candidate_ranking[, c(
  "screen_id", "feature_spec_id", "screen_class", "tau0", "zeta2", "alpha_prior_sd",
  "rhs_vb_inner", "vb_refit_count", "vb_max_iter_count", "vb_max_iter_rate",
  "vb_max_iter_rate_delta", "runtime_total_sec", "runtime_refit_sec", "runtime_ratio",
  "screen_status"
), drop = FALSE]
feature_diagnostics <- do.call(rbind, feature_diag_rows)
screen_recommendation <- phase4n_recommendation(screen_candidate_ranking, baseline_screen_id)
screen_run_config <- data.frame(
  phase = "phase4n_desn_feature_screen",
  source_launch_dir = app_prefer_repo_relative_path(source_launch_dir),
  source_launch_registry_sha256 = app_sha256_file(file.path(source_launch_dir, "launch_registry.csv")),
  source_crossing_sha256 = app_sha256_file(file.path(source_launch_dir, "launch_crossing_by_scenario.csv")),
  reference_arm = reference_arm,
  base_fixture_dir = app_prefer_repo_relative_path(base_fixture_dir),
  base_fixture_manifest_sha256 = app_sha256_file(file.path(base_fixture_dir, "artifact_manifest.csv")),
  n_targeted_scenarios = nrow(target$registry),
  n_screens = nrow(screen_grid),
  baseline_screen_id = baseline_screen_id,
  vb_max_iter = vb_max_iter,
  adaptive_vb_max_iter_grid = paste(adaptive_vb_max_iter_grid, collapse = ","),
  refit_stride = refit_stride,
  forecast_origin_stride = forecast_origin_stride,
  max_origins_per_scenario = if (is.finite(max_origins_per_scenario)) as.integer(max_origins_per_scenario) else NA_integer_,
  vb_tol = vb_tol,
  kappa = kappa,
  a_sigma = a_sigma,
  b_sigma = b_sigma,
  alpha_prior_mean = alpha_prior_mean,
  all_fixture_manifest_hashes_verified = all(screen_run_manifest$fixture_manifest_hashes_verified),
  all_phase3_manifest_hashes_verified = all(screen_run_manifest$phase3_manifest_hashes_verified),
  stringsAsFactors = FALSE
)

readme_path <- file.path(out_dir, "README.md")
writeLines(phase4n_readme(screen_run_config, screen_recommendation), readme_path, useBytes = TRUE)
paths <- c(
  targeted_registry = app_joint_qvp_write_csv(target$registry, file.path(out_dir, "targeted_registry.csv")),
  target_source_crossing_rows = app_joint_qvp_write_csv(target$crossing, file.path(out_dir, "target_source_crossing_rows.csv")),
  feature_spec_grid = app_joint_qvp_write_csv(screen_grid, file.path(out_dir, "feature_spec_grid.csv")),
  screen_run_config = app_joint_qvp_write_csv(screen_run_config, file.path(out_dir, "screen_run_config.csv")),
  feature_diagnostics = app_joint_qvp_write_csv(feature_diagnostics, file.path(out_dir, "feature_diagnostics.csv")),
  screen_metric_summary = app_joint_qvp_write_csv(screen_metric_summary, file.path(out_dir, "screen_metric_summary.csv")),
  screen_candidate_ranking = app_joint_qvp_write_csv(screen_candidate_ranking, file.path(out_dir, "screen_candidate_ranking.csv")),
  screen_crossing_by_scenario = app_joint_qvp_write_csv(screen_crossing_by_scenario, file.path(out_dir, "screen_crossing_by_scenario.csv")),
  screen_crossing_by_tau_pair = app_joint_qvp_write_csv(screen_crossing_by_tau_pair, file.path(out_dir, "screen_crossing_by_tau_pair.csv")),
  screen_truth_by_tau = app_joint_qvp_write_csv(screen_truth_by_tau, file.path(out_dir, "screen_truth_by_tau.csv")),
  screen_vb_runtime_summary = app_joint_qvp_write_csv(screen_vb_runtime_summary, file.path(out_dir, "screen_vb_runtime_summary.csv")),
  screen_run_manifest = app_joint_qvp_write_csv(screen_run_manifest, file.path(out_dir, "screen_run_manifest.csv")),
  screen_recommendation = app_joint_qvp_write_csv(screen_recommendation, file.path(out_dir, "screen_recommendation.csv")),
  provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
  readme = normalizePath(readme_path, mustWork = TRUE)
)
manifest <- data.frame(
  label = names(paths),
  relative_path = basename(paths),
  size_bytes = as.numeric(file.info(paths)$size),
  sha256 = vapply(paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))

cat(sprintf("Joint-QVP Phase 4n DESN/feature-spec screen artifacts written to %s\n", out_dir))
cat(sprintf("Targeted scenario rows: %s\n", nrow(target$registry)))
cat(sprintf("Screen rows: %s\n", nrow(screen_grid)))
cat("Screen statuses:\n")
print(table(screen_candidate_ranking$screen_status))
cat(sprintf("Recommendation: %s\n", screen_recommendation$recommendation_status[[1L]]))
cat(sprintf("Artifact manifest: %s\n", manifest_path))
