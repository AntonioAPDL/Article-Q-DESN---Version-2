#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_search_phase2.R"))
source(app_path("application/R/glofas_search3_rainy_season.R"))
source(app_path("application/R/glofas_search3_runtime_contract.R"))
args <- app_parse_args(list(runtime_root = ""))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
run_manifest <- app_read_yaml(file.path(root, "configs", "run_manifest.yaml"))
stage <- as.character(run_manifest$stage)
campaign_root <- normalizePath(as.character(run_manifest$campaign_root), mustWork = TRUE)
jobs <- app_read_csv(file.path(root, "configs", "job_manifest.csv"))
folds <- app_read_csv(file.path(campaign_root, "configs", "fold_registry.csv")); folds$origin_date <- as.Date(folds$origin_date)
candidates <- app_read_csv(file.path(campaign_root, "configs", "candidate_manifest.csv"))

exists_status <- function(ext) file.exists(file.path(root, "status", paste0(jobs$job_id, ext)))
health <- data.frame(
  stage = stage, total = nrow(jobs), reused = as.integer(run_manifest$reused_job_count %||% 0L),
  completed = sum(exists_status(".done")), model_done_unscored = sum(exists_status(".model_done") & !exists_status(".done")),
  running = sum(exists_status(".running")), failed = sum(exists_status(".failed")),
  pending = sum(!exists_status(".done") & !exists_status(".model_done") & !exists_status(".running") & !exists_status(".failed")),
  left = sum(!exists_status(".done")), stringsAsFactors = FALSE
)

read_csvs <- function(dir, suffix) {
  files <- list.files(file.path(root, dir), pattern = suffix, full.names = TRUE)
  app_bind_rows_fill(lapply(files, app_read_csv))
}
scores <- read_csvs("scores", "_summary[.]csv$")
fits <- read_csvs("fits", "_summary[.]csv$")
reuse_path <- file.path(root, "configs", "reused_score_registry.csv")
reuse <- app_glofas_search3_read_reuse_registry(reuse_path, required = FALSE)
if (nrow(reuse)) {
  read_reuse <- function(path_column, hash_column) {
    app_bind_rows_fill(lapply(seq_len(nrow(reuse)), function(i) {
      path <- normalizePath(reuse[[path_column]][[i]], mustWork = TRUE)
      if (!identical(app_sha256_file(path), reuse[[hash_column]][[i]])) stop("Search III reused artifact hash mismatch.", call. = FALSE)
      x <- app_read_csv(path)
      destination <- reuse$destination_job_id[[i]]
      source <- x$job_id
      row <- jobs[jobs$job_id == destination, , drop = FALSE]
      x$source_job_id <- source; x$job_id <- destination
      for (nm in intersect(c("candidate_id", "base_candidate_id", "target", "method", "prior_id", "seed", "fold_id"), names(row))) x[[nm]] <- row[[nm]][[1L]]
      x
    }))
  }
  scores <- app_bind_rows_fill(list(scores, read_reuse("score_summary_path", "score_summary_sha256")))
  fits <- app_bind_rows_fill(list(fits, read_reuse("fit_summary_path", "fit_summary_sha256")))
}
if (nrow(scores) && nrow(fits)) {
  fit_cols <- unique(c("job_id", intersect(c(
    "fit_completed", "terminal_certificate_pass", "fit_converged", "fit_iterations",
    "runtime_seconds", "diagnostic_decision", "finite_pass", "sampled_saturation_fraction",
    "sampled_relative_effective_rank", "historical_all_rmse", "historical_last200_rmse"
  ), names(fits))))
  scores <- merge(scores, fits[, fit_cols, drop = FALSE], by = "job_id", all.x = TRUE, sort = FALSE)
}
app_write_csv(health, file.path(root, "tables", "health_latest.csv"))
app_write_csv(scores, file.path(root, "tables", "score_summaries_latest.csv"))
app_write_csv(fits, file.path(root, "tables", "fit_summaries_latest.csv"))
checker_path <- normalizePath(app_path("application/scripts/431_check_glofas_search3.R"), mustWork = TRUE)
transition_path <- file.path(campaign_root, "configs", "source_transition_registry.csv")
app_write_csv(data.frame(
  stage = stage,
  fit_source_head = as.character(run_manifest$git_head),
  aggregation_source_head = app_git_sha(short = FALSE),
  checker_path = checker_path,
  checker_sha256 = app_sha256_file(checker_path),
  reuse_registry_path = normalizePath(reuse_path, mustWork = TRUE),
  reuse_registry_sha256 = app_sha256_file(reuse_path),
  source_transition_path = if (file.exists(transition_path)) normalizePath(transition_path) else NA_character_,
  source_transition_sha256 = if (file.exists(transition_path)) app_sha256_file(transition_path) else NA_character_,
  stringsAsFactors = FALSE
), file.path(root, "tables", "aggregation_provenance.csv"))
print(health)

complete <- health$completed[[1L]] == health$total[[1L]] && health$failed[[1L]] == 0L
if (!complete) {
  if (stage == "confirmation" && file.exists(file.path(root, "tables", "aggregate_scores_latest.csv"))) {
    stop("Incomplete Search III confirmation must not expose an aggregate table.", call. = FALSE)
  }
  quit(save = "no", status = ifelse(health$failed[[1L]] > 0L, 2L, 0L))
}

write_selection_hash <- function(paths) {
  paths <- normalizePath(paths, mustWork = TRUE)
  table <- data.frame(path = paths, sha256 = vapply(paths, app_sha256_file, character(1L)), stringsAsFactors = FALSE)
  provenance_path <- normalizePath(file.path(root, "tables", "aggregation_provenance.csv"), mustWork = TRUE)
  table <- rbind(table, data.frame(path = provenance_path, sha256 = app_sha256_file(provenance_path), stringsAsFactors = FALSE))
  app_write_csv(table, file.path(root, "tables", "selection_artifact_hashes.csv"))
}

if (stage == "ridge_a") {
  aggregate <- app_glofas_search3_phase_aggregate(scores, folds[folds$fold_id %in% jobs$fold_id, ], fits)
  selected <- app_glofas_search3_select_pass_a(aggregate, candidates)
  app_write_csv(aggregate, file.path(root, "tables", "aggregate_scores_latest.csv"))
  app_write_csv(selected, file.path(root, "tables", "advanced_candidates.csv"))
  write_selection_hash(file.path(root, "tables", c("aggregate_scores_latest.csv", "advanced_candidates.csv")))
} else if (stage == "ridge_b") {
  a_root <- file.path(campaign_root, "stages", "ridge_a")
  all_scores <- app_bind_rows_fill(list(app_read_csv(file.path(a_root, "tables", "score_summaries_latest.csv")), scores))
  all_fits <- app_bind_rows_fill(list(app_read_csv(file.path(a_root, "tables", "fit_summaries_latest.csv")), fits))
  dev_folds <- folds[folds$panel == "development" & folds$primary, , drop = FALSE]
  aggregate <- app_glofas_search3_phase_aggregate(all_scores, dev_folds, all_fits)
  guard_pool <- app_glofas_search3_select_guard_pool(aggregate, candidates)
  app_write_csv(aggregate, file.path(root, "tables", "aggregate_scores_latest.csv"))
  app_write_csv(guard_pool, file.path(root, "tables", "guard_pool.csv"))
  write_selection_hash(file.path(root, "tables", c("aggregate_scores_latest.csv", "guard_pool.csv")))
} else if (stage == "ridge_guard") {
  b_root <- file.path(campaign_root, "stages", "ridge_b")
  full_aggregate <- app_read_csv(file.path(b_root, "tables", "aggregate_scores_latest.csv"))
  primary_guard <- scores[scores$score_window == "primary_28", , drop = FALSE]
  shortlist <- app_glofas_search3_select_rhs_shortlist(full_aggregate, primary_guard, candidates)
  pilot <- app_glofas_search3_select_pilot_architectures(full_aggregate, shortlist, candidates)
  app_write_csv(primary_guard, file.path(root, "tables", "guardrail_scores.csv"))
  app_write_csv(shortlist, file.path(root, "tables", "rhs_shortlist.csv"))
  app_write_csv(pilot, file.path(root, "tables", "pilot_architectures.csv"))
  write_selection_hash(file.path(root, "tables", c("guardrail_scores.csv", "rhs_shortlist.csv", "pilot_architectures.csv")))
} else if (stage == "rhs_pilot") {
  selected_prior <- app_glofas_search3_select_prior(scores)
  app_write_csv(selected_prior, file.path(root, "tables", "selected_priors.csv"))
  write_selection_hash(file.path(root, "tables", "selected_priors.csv"))
} else if (stage == "rhs_screen") {
  dev_folds <- folds[folds$panel == "development" & folds$primary, , drop = FALSE]
  aggregate <- app_glofas_search3_phase_aggregate(scores, dev_folds, fits)
  finalists <- app_glofas_search3_select_finalists(aggregate, candidates)
  app_write_csv(aggregate, file.path(root, "tables", "aggregate_scores_latest.csv"))
  app_write_csv(finalists, file.path(root, "tables", "confirmation_finalists.csv"))
  write_selection_hash(file.path(root, "tables", c("aggregate_scores_latest.csv", "confirmation_finalists.csv")))
} else if (stage == "confirmation") {
  conf_folds <- folds[folds$panel == "confirmation" & folds$primary, , drop = FALSE]
  aggregate <- app_glofas_search3_phase_aggregate(scores, conf_folds, fits)
  app_write_csv(aggregate, file.path(root, "tables", "aggregate_scores_latest.csv"))
  write_selection_hash(file.path(root, "tables", "aggregate_scores_latest.csv"))
  writeLines("SEARCH3_RAINY_SEASON_COMPLETE_PENDING_SCIENTIFIC_ADOPTION", file.path(root, "status", "CAMPAIGN_COMPLETE"))
}
