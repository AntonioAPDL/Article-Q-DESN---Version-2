#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_search_phase2.R"))

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
invisible(lapply(file.path(root, c("configs", "forecasts", "fits", "scores", "traces", "coefficients", "diagnostics", "status", "logs", "tables", "reports")), app_ensure_dir))
model_registry <- app_read_csv(file.path(ridge_root, "configs", "model_packet_registry.csv"))
score_registry <- app_read_csv(file.path(ridge_root, "configs", "scoring_packet_registry.csv"))
app_write_csv(model_registry, file.path(root, "configs", "model_packet_registry.csv"))
app_write_csv(score_registry, file.path(root, "configs", "scoring_packet_registry.csv"))
reused <- data.frame()

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
  prior_rank <- aggregate(primary$mean_crps, list(target = primary$target, prior_id = primary$prior_id), mean)
  names(prior_rank)[[3L]] <- "mean_primary_crps"
  prior_rank <- prior_rank[order(prior_rank$target, prior_rank$mean_primary_crps), , drop = FALSE]
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
    jobs <- jobs[-hit, , drop = FALSE]
  }
} else {
  source_aggregate <- app_read_csv(file.path(source_root, "tables", "aggregate_scores_latest.csv"))
  if ("promotion_eligible" %in% names(source_aggregate)) {
    source_aggregate <- source_aggregate[
      !is.na(source_aggregate$promotion_eligible) & source_aggregate$promotion_eligible,
      , drop = FALSE
    ]
  }
  source_jobs <- app_read_csv(file.path(source_root, "configs", "job_manifest.csv"))
  finalists <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    utils::head(source_aggregate[source_aggregate$target == target, , drop = FALSE], as.integer(args$finalists))
  }))
  templates <- app_bind_rows_fill(lapply(seq_len(nrow(finalists)), function(i) {
    hit <- source_jobs$target == finalists$target[[i]] & source_jobs$candidate_id == finalists$candidate_id[[i]]
    if ("prior_id" %in% names(finalists)) hit <- hit & source_jobs$prior_id == finalists$prior_id[[i]]
    source_jobs[which(hit)[[1L]], , drop = FALSE]
  }))
  extra_seeds <- as.integer(strsplit(as.character(args$confirm_seeds), ",", fixed = TRUE)[[1L]])
  seed_rows <- app_bind_rows_fill(lapply(seq_len(nrow(templates)), function(i) {
    rows <- templates[rep(i, length(unique(c(templates$seed[[i]], extra_seeds)))), , drop = FALSE]
    rows$seed <- unique(c(templates$seed[[i]], extra_seeds))
    rows$base_candidate_id <- templates$candidate_id[[i]]
    rows$candidate_id <- paste0(templates$candidate_id[[i]], "__seed", rows$seed)
    rows
  }))
  architectures <- seed_rows[, setdiff(names(seed_rows), c("job_id", "stage", "method", "fold_id", "origin_date", "primary_horizon", "secondary_horizon", "retrospective_product", "primary", "model_packet_path", "model_packet_sha256")), drop = FALSE]
  architectures <- architectures[!duplicated(architectures$candidate_id), , drop = FALSE]
  idx <- expand.grid(architecture_index = seq_len(nrow(architectures)), fold_index = seq_len(nrow(folds)),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  jobs <- cbind(architectures[idx$architecture_index, , drop = FALSE], folds[idx$fold_index, , drop = FALSE])
  jobs$method <- "rhs"
  jobs$stage <- "rhs_seed_confirmation"
  jobs$job_id <- paste(jobs$stage, jobs$candidate_id, jobs$prior_id, jobs$fold_id, sep = "__")
  jobs$memory_weight <- ifelse(jobs$n_state_features <= 2500, 1L, ifelse(jobs$n_state_features <= 4000, 2L, 3L))
  jobs <- jobs[, c("job_id", "stage", "method", "memory_weight", setdiff(names(jobs), c("job_id", "stage", "method", "memory_weight"))), drop = FALSE]
}

jobs <- merge(jobs, model_registry, by = c("target", "fold_id"), all.x = TRUE, sort = FALSE)
if (anyDuplicated(jobs$job_id) || any(is.na(jobs$model_packet_path) | !nzchar(jobs$model_packet_path))) stop("RHS jobs are not uniquely packeted.", call. = FALSE)
app_write_csv(jobs, file.path(root, "configs", "job_manifest.csv"))
app_write_csv(reused, file.path(root, "configs", "reused_score_registry.csv"))
app_write_yaml(list(
  version = "glofas_search_phase2_rhs_runtime_v1", mode = mode, run_label = run_label,
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), git_head = app_git_sha(short = FALSE),
  ridge_runtime_root = ridge_root, pilot_runtime_root = as.character(args$pilot_runtime_root), source_runtime_root = source_root,
  new_job_count = nrow(jobs), reused_job_count = nrow(reused),
  scientific_contract = list(final_origin_excluded = "2022-12-25", primary_horizon = 28L, secondary_horizon = 30L,
    ridge_warm_start_rebuilt_exactly_per_candidate_fold = TRUE, beta_freeze_iterations = 20L,
    minimum_beta_updates = 30L, score_equivalence_precision = 4L)
), file.path(root, "configs", "run_manifest.yaml"))
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))
cat(root, "\n")
