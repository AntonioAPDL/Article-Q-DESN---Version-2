#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_search_phase2.R"))
app_glofas_search2_assert_git_state()

args <- app_parse_args(list(
  mode = "pilot", ridge_runtime_root = "", pilot_runtime_root = "", source_runtime_root = "",
  run_label = paste0("glofas_search_phase2_rhs_", format(Sys.time(), "%Y%m%d_%H%M%S")),
  top_n = "8", diverse_n = "11", finalists = "3", confirm_seeds = "20260914,20260915,20260916"
))
mode <- match.arg(as.character(args$mode), c("pilot", "screen", "confirm"))
ridge_root <- app_resolve_path(args$ridge_runtime_root, must_work = TRUE)
source_root <- if (identical(mode, "confirm")) app_resolve_path(args$source_runtime_root, must_work = TRUE) else ridge_root
folds <- app_read_csv(app_path("application/config/glofas_search_phase2_folds_20260914.csv"))
folds$origin_date <- as.Date(folds$origin_date)
app_glofas_search2_validate_folds(folds)
candidates <- app_read_csv(file.path(ridge_root, "configs", "candidate_manifest.csv"))
ridge_aggregate <- app_read_csv(file.path(ridge_root, "tables", "aggregate_scores_latest.csv"))
if (!nrow(ridge_aggregate)) stop("RHS preparation requires completed Ridge aggregate scores.", call. = FALSE)

run_label <- as.character(args$run_label)
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) stop("run_label must be path-safe.", call. = FALSE)
root <- app_path("local_trackers", "runtime_configs", run_label)
invisible(lapply(file.path(root, c("configs", "forecasts", "fits", "scores", "traces", "coefficients", "warm_starts", "diagnostics", "status", "logs", "tables", "reports")), app_ensure_dir))
model_registry <- app_read_csv(file.path(ridge_root, "configs", "model_packet_registry.csv"))
score_registry <- app_read_csv(file.path(ridge_root, "configs", "scoring_packet_registry.csv"))
app_write_csv(model_registry, file.path(root, "configs", "model_packet_registry.csv"))
app_write_csv(score_registry, file.path(root, "configs", "scoring_packet_registry.csv"))
reused <- data.frame(
  target = character(), candidate_id = character(), base_candidate_id = character(),
  seed = integer(), prior_id = character(), fold_id = character(),
  source_job_id = character(), destination_job_id = character(),
  score_summary_path = character(), score_detail_path = character(),
  fit_summary_path = character(), source_runtime_root = character(),
  score_summary_sha256 = character(), score_detail_sha256 = character(),
  fit_summary_sha256 = character(), stringsAsFactors = FALSE
)

if (identical(mode, "pilot")) {
  architectures <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    agg <- ridge_aggregate[ridge_aggregate$target == target, , drop = FALSE]
    cand <- candidates[candidates$target == target, , drop = FALSE]
    app_glofas_search2_select_rhs_architectures(agg, cand, n_top = 2L, n_diverse = 1L)
  }))
  jobs <- app_glofas_search2_rhs_manifest(architectures, folds, app_glofas_search2_prior_specs(), stage = "rhs_pilot")
} else if (identical(mode, "screen")) {
  pilot_root <- app_resolve_path(args$pilot_runtime_root, must_work = TRUE)
  pilot_scores <- app_read_csv(file.path(pilot_root, "tables", "score_summaries_latest.csv"))
  if (!nrow(pilot_scores) || !"prior_id" %in% names(pilot_scores)) stop("RHS screen requires completed prior-pilot scores.", call. = FALSE)
  primary <- pilot_scores[pilot_scores$score_window == "primary_28", , drop = FALSE]
  prior_rank <- aggregate(primary$mean_crps, list(target = primary$target, prior_id = primary$prior_id), function(x) {
    c(n = length(x), mean = mean(x), worst = max(x), finite = all(is.finite(x)))
  })
  prior_rank <- data.frame(
    target = prior_rank$target, prior_id = prior_rank$prior_id,
    n_primary_cells = prior_rank$x[, "n"], mean_primary_crps = prior_rank$x[, "mean"],
    worst_primary_crps = prior_rank$x[, "worst"], all_finite = as.logical(prior_rank$x[, "finite"]),
    stringsAsFactors = FALSE
  )
  if (any(prior_rank$n_primary_cells != 24L) || any(!prior_rank$all_finite)) {
    stop("RHS prior selection requires 24 finite primary cells for every target/prior.", call. = FALSE)
  }
  prior_rank <- prior_rank[order(
    prior_rank$target, round(prior_rank$mean_primary_crps, 4),
    prior_rank$worst_primary_crps
  ), , drop = FALSE]
  chosen <- prior_rank[!duplicated(prior_rank$target), , drop = FALSE]
  architectures <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    agg <- ridge_aggregate[ridge_aggregate$target == target, , drop = FALSE]
    cand <- candidates[candidates$target == target, , drop = FALSE]
    app_glofas_search2_select_rhs_architectures(
      agg, cand, n_top = as.integer(args$top_n), n_diverse = as.integer(args$diverse_n)
    )
  }))
  jobs <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    spec <- app_glofas_search2_prior_specs()
    spec <- spec[spec$prior_id == chosen$prior_id[chosen$target == target][[1L]], , drop = FALSE]
    app_glofas_search2_rhs_manifest(architectures[architectures$target == target, , drop = FALSE], folds, spec, stage = "rhs_screen")
  }))
  pilot_jobs <- app_read_csv(file.path(pilot_root, "configs", "job_manifest.csv"))
  pilot_keys <- paste(pilot_jobs$target, pilot_jobs$candidate_id, pilot_jobs$prior_id, pilot_jobs$fold_id, sep = "|")
  keys <- paste(jobs$target, jobs$candidate_id, jobs$prior_id, jobs$fold_id, sep = "|")
  reuse_index <- match(keys, pilot_keys)
  hit <- which(!is.na(reuse_index) & file.exists(file.path(pilot_root, "status", paste0(pilot_jobs$job_id[reuse_index], ".done"))))
  if (length(hit)) {
    reused <- data.frame(
      target = jobs$target[hit], candidate_id = jobs$candidate_id[hit], prior_id = jobs$prior_id[hit], fold_id = jobs$fold_id[hit],
      score_summary_path = file.path(pilot_root, "scores", paste0(pilot_jobs$job_id[reuse_index[hit]], "_summary.csv")),
      score_detail_path = file.path(pilot_root, "scores", paste0(pilot_jobs$job_id[reuse_index[hit]], "_detail.csv")),
      fit_summary_path = file.path(pilot_root, "fits", paste0(pilot_jobs$job_id[reuse_index[hit]], "_summary.csv")),
      source_runtime_root = pilot_root, stringsAsFactors = FALSE
    )
    reused$score_summary_sha256 <- vapply(reused$score_summary_path, app_sha256_file, character(1L))
    reused$score_detail_sha256 <- vapply(reused$score_detail_path, app_sha256_file, character(1L))
    reused$fit_summary_sha256 <- vapply(reused$fit_summary_path, app_sha256_file, character(1L))
    jobs <- jobs[-hit, , drop = FALSE]
  }
} else {
  source_aggregate <- app_read_csv(file.path(source_root, "tables", "aggregate_scores_latest.csv"))
  source_guardrail_baselines <- source_aggregate[
    as.character(source_aggregate$candidate_role) == "phase1_legacy_anchor",
    , drop = FALSE
  ]
  if (!nrow(source_guardrail_baselines)) stop("Seed confirmation requires source Phase-I guardrail baselines.", call. = FALSE)
  app_write_csv(source_guardrail_baselines, file.path(root, "configs", "confirmation_guardrail_baselines.csv"))
  if ("promotion_eligible" %in% names(source_aggregate)) {
    source_aggregate <- source_aggregate[
      !is.na(source_aggregate$promotion_eligible) & source_aggregate$promotion_eligible,
      , drop = FALSE
    ]
  }
  source_registry <- app_glofas_search2_confirmation_source_registry(source_root)
  finalists <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    available <- source_aggregate[source_aggregate$target == target, , drop = FALSE]
    available <- available[order(
      round(available$mean_primary_crps, 4), available$worst_primary_crps,
      available$mean_secondary_crps
    ), , drop = FALSE]
    utils::head(available, as.integer(args$finalists))
  }))
  resolved_sources <- app_glofas_search2_confirmation_templates(finalists, source_registry, folds)
  templates <- resolved_sources$templates
  source_cells <- resolved_sources$source_cells
  app_write_csv(source_cells, file.path(root, "configs", "confirmation_source_cell_registry.csv"))
  extra_seeds <- as.integer(strsplit(as.character(args$confirm_seeds), ",", fixed = TRUE)[[1L]])
  if (!length(extra_seeds) || anyNA(extra_seeds) || anyDuplicated(extra_seeds)) {
    stop("Confirmation seeds must be unique finite integers.", call. = FALSE)
  }
  if (any(extra_seeds %in% as.integer(templates$seed))) {
    stop("Confirmation seeds must not duplicate any finalist original seed.", call. = FALSE)
  }
  seed_rows <- app_bind_rows_fill(lapply(seq_len(nrow(templates)), function(i) {
    rows <- templates[rep(i, 1L + length(extra_seeds)), , drop = FALSE]
    rows$seed <- c(templates$seed[[i]], extra_seeds)
    rows$base_candidate_id <- templates$candidate_id[[i]]
    rows$candidate_id <- paste0(templates$candidate_id[[i]], "__seed", rows$seed)
    rows
  }))
  architectures <- seed_rows[, setdiff(names(seed_rows), c(
    "job_id", "stage", "method", "fold_id", "origin_date", "primary_horizon",
    "secondary_horizon", "retrospective_product", "primary", "model_packet_path",
    "model_packet_sha256", "source_runtime_root", "source_kind", "source_job_id",
    "score_summary_path", "score_detail_path", "fit_summary_path", "done_path",
    "score_summary_sha256", "score_detail_sha256", "fit_summary_sha256", "source_cell_key"
  )), drop = FALSE]
  architectures <- architectures[!duplicated(architectures$candidate_id), , drop = FALSE]
  idx <- expand.grid(architecture_index = seq_len(nrow(architectures)), fold_index = seq_len(nrow(folds)),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  jobs <- cbind(architectures[idx$architecture_index, , drop = FALSE], folds[idx$fold_index, , drop = FALSE])
  jobs$method <- "rhs"
  jobs$stage <- "rhs_seed_confirmation"
  jobs$job_id <- paste(jobs$stage, jobs$candidate_id, jobs$prior_id, jobs$fold_id, sep = "__")
  jobs$memory_weight <- ifelse(jobs$n_state_features <= 2500, 1L, ifelse(jobs$n_state_features <= 4000, 2L, 3L))
  jobs <- jobs[, c("job_id", "stage", "method", "memory_weight", setdiff(names(jobs), c("job_id", "stage", "method", "memory_weight"))), drop = FALSE]

  original_seed <- setNames(as.integer(templates$seed), as.character(templates$candidate_id))
  reuse_hit <- which(as.integer(jobs$seed) == original_seed[as.character(jobs$base_candidate_id)])
  if (length(reuse_hit)) {
    source_keys <- paste(source_cells$target, source_cells$candidate_id, source_cells$prior_id,
      source_cells$fold_id, source_cells$seed, sep = "|")
    reuse_keys <- paste(jobs$target[reuse_hit], jobs$base_candidate_id[reuse_hit], jobs$prior_id[reuse_hit],
      jobs$fold_id[reuse_hit], jobs$seed[reuse_hit], sep = "|")
    source_index <- match(reuse_keys, source_keys)
    if (anyNA(source_index)) stop("Seed confirmation could not match every original-seed source cell.", call. = FALSE)
    source_ids <- source_cells$source_job_id[source_index]
    required <- as.matrix(source_cells[source_index, c(
      "score_summary_path", "score_detail_path", "fit_summary_path", "done_path"
    ), drop = FALSE])
    if (any(!file.exists(required))) stop("Seed confirmation requires complete original-seed source artifacts.", call. = FALSE)
    reused <- data.frame(
      target = jobs$target[reuse_hit], candidate_id = jobs$candidate_id[reuse_hit],
      base_candidate_id = jobs$base_candidate_id[reuse_hit], seed = jobs$seed[reuse_hit],
      prior_id = jobs$prior_id[reuse_hit], candidate_role = jobs$candidate_role[reuse_hit],
      rhs_selection_role = jobs$rhs_selection_role[reuse_hit], D = jobs$D[reuse_hit],
      n_state_features = jobs$n_state_features[reuse_hit], fold_id = jobs$fold_id[reuse_hit],
      source_job_id = source_ids, destination_job_id = jobs$job_id[reuse_hit],
      score_summary_path = required[, "score_summary_path"],
      score_detail_path = required[, "score_detail_path"],
      fit_summary_path = required[, "fit_summary_path"],
      source_runtime_root = source_cells$source_runtime_root[source_index],
      source_kind = source_cells$source_kind[source_index], stringsAsFactors = FALSE
    )
    reused$score_summary_sha256 <- source_cells$score_summary_sha256[source_index]
    reused$score_detail_sha256 <- source_cells$score_detail_sha256[source_index]
    reused$fit_summary_sha256 <- source_cells$fit_summary_sha256[source_index]
    jobs <- jobs[-reuse_hit, , drop = FALSE]
  }

  expected_reused <- nrow(finalists) * nrow(folds)
  expected_new <- nrow(finalists) * length(extra_seeds) * nrow(folds)
  if (nrow(reused) != expected_reused || nrow(jobs) != expected_new) {
    stop(sprintf(
      "Confirmation preparation produced %d new/%d reused cells; expected %d/%d.",
      nrow(jobs), nrow(reused), expected_new, expected_reused
    ), call. = FALSE)
  }
  expected_per_finalist <- app_glofas_search2_confirmation_expected_cells(jobs, reused)
  expected_finalist_cells <- (1L + length(extra_seeds)) * nrow(folds)
  if (expected_per_finalist != expected_finalist_cells) {
    stop("Confirmation preparation failed the target-specific fold-by-seed completeness gate.", call. = FALSE)
  }
}

jobs$design_group_id <- paste(jobs$target, jobs$candidate_id, jobs$fold_id, sep = "__")
if (mode %in% c("pilot", "screen")) {
  ridge_job_id <- paste("ridge_screen", jobs$candidate_id, jobs$fold_id, sep = "__")
  jobs$ridge_warm_start_path <- file.path(ridge_root, "warm_starts", paste0(ridge_job_id, "_warm_start.rds"))
  missing_warm <- !file.exists(jobs$ridge_warm_start_path)
  if (any(missing_warm)) {
    stop(sprintf(
      "RHS %s preparation requires completed Ridge warm starts; %d are missing.",
      mode, sum(missing_warm)
    ), call. = FALSE)
  }
  jobs$ridge_warm_start_path <- vapply(jobs$ridge_warm_start_path, normalizePath, character(1L), mustWork = TRUE)
  jobs$ridge_warm_start_sha256 <- vapply(jobs$ridge_warm_start_path, app_sha256_file, character(1L))
} else {
  jobs$ridge_warm_start_path <- NA_character_
  jobs$ridge_warm_start_sha256 <- NA_character_
}

jobs <- merge(jobs, model_registry, by = c("target", "fold_id"), all.x = TRUE, sort = FALSE)
if (anyDuplicated(jobs$job_id) || any(is.na(jobs$model_packet_path) | !nzchar(jobs$model_packet_path))) stop("RHS jobs are not uniquely packeted.", call. = FALSE)
app_write_csv(jobs, file.path(root, "configs", "job_manifest.csv"))
app_write_csv(architectures, file.path(root, "configs", "candidate_manifest.csv"))
app_write_csv(reused, file.path(root, "configs", "reused_score_registry.csv"))
app_write_yaml(list(
  version = "glofas_search_phase2_rhs_runtime_v1", mode = mode, run_label = run_label,
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), repo_root = app_repo_root(),
  git_head = app_git_sha(short = FALSE),
  ridge_runtime_root = ridge_root, pilot_runtime_root = as.character(args$pilot_runtime_root), source_runtime_root = source_root,
  new_job_count = nrow(jobs), reused_job_count = nrow(reused),
  expected_evaluation_count = nrow(jobs) + nrow(reused),
  scientific_contract = list(final_origin_excluded = "2022-12-25", primary_horizon = 28L, secondary_horizon = 30L,
    ridge_warm_start_required_and_hashed = mode %in% c("pilot", "screen"),
    grouped_rhs_design_launch_required = identical(mode, "pilot"), beta_freeze_iterations = 20L,
    minimum_beta_updates = 30L, score_equivalence_precision = 4L)
), file.path(root, "configs", "run_manifest.yaml"))
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))
cat(root, "\n")
