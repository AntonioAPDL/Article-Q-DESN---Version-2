#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_search_phase2.R"))
args <- app_parse_args(list(runtime_root = ""))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
run_manifest <- app_read_yaml(file.path(root, "configs", "run_manifest.yaml"))
jobs <- app_read_csv(file.path(root, "configs", "job_manifest.csv"))
reuse_registry_path <- file.path(root, "configs", "reused_score_registry.csv")
reuse_registry <- if (file.exists(reuse_registry_path)) app_read_csv(reuse_registry_path) else data.frame()
read_reused <- function(path_column, hash_column) {
  if (!nrow(reuse_registry) || !path_column %in% names(reuse_registry)) return(list())
  lapply(seq_len(nrow(reuse_registry)), function(i) {
    path <- normalizePath(as.character(reuse_registry[[path_column]][[i]]), mustWork = TRUE)
    if (hash_column %in% names(reuse_registry)) {
      expected <- as.character(reuse_registry[[hash_column]][[i]])
      if (!is.na(expected) && nzchar(expected) && !identical(app_sha256_file(path), expected)) {
        stop(sprintf("Reused artifact hash mismatch: %s", path), call. = FALSE)
      }
    }
    out <- app_read_csv(path)
    if ("destination_job_id" %in% names(reuse_registry)) {
      destination <- as.character(reuse_registry$destination_job_id[[i]])
      if (!is.na(destination) && nzchar(destination)) {
        out$source_job_id <- out$job_id
        out$job_id <- destination
        for (nm in intersect(c(
          "candidate_id", "base_candidate_id", "seed", "prior_id", "candidate_role",
          "rhs_selection_role", "D", "n_state_features"
        ), names(reuse_registry))) out[[nm]] <- reuse_registry[[nm]][[i]]
      }
    }
    out
  })
}
exists_status <- function(ext) file.exists(file.path(root, "status", paste0(jobs$job_id, ext)))
health <- data.frame(
  runtime_root = root, total = nrow(jobs), completed = sum(exists_status(".done")),
  reused_completed = nrow(reuse_registry), evaluated_total = nrow(jobs) + nrow(reuse_registry),
  model_done_unscored = sum(exists_status(".model_done") & !exists_status(".done")),
  running = sum(exists_status(".running")), failed = sum(exists_status(".failed")),
  pending = sum(!exists_status(".done") & !exists_status(".model_done") & !exists_status(".running") & !exists_status(".failed")),
  stringsAsFactors = FALSE
)
score_files <- list.files(file.path(root, "scores"), pattern = "_summary[.]csv$", full.names = TRUE)
scores <- app_bind_rows_fill(c(
  lapply(score_files, app_read_csv),
  read_reused("score_summary_path", "score_summary_sha256")
))
fit_files <- list.files(file.path(root, "fits"), pattern = "_summary[.]csv$", full.names = TRUE)
fits <- app_bind_rows_fill(c(
  lapply(fit_files, app_read_csv),
  read_reused("fit_summary_path", "fit_summary_sha256")
))
if (nrow(scores) && nrow(fits)) {
  fit_columns <- c("job_id", grep(
    "^(historical_|runtime_seconds$|fit_converged$|fit_iterations$|diagnostic_|finite_pass$|sampled_)",
    names(fits), value = TRUE
  ))
  fit_columns <- unique(intersect(fit_columns, names(fits)))
  scores <- merge(scores, fits[, fit_columns, drop = FALSE], by = "job_id", all.x = TRUE, sort = FALSE)
}
fold_values <- unique(c(as.character(jobs$fold_id), as.character(reuse_registry$fold_id %||% character())))
expected_cells <- length(fold_values)
if (identical(as.character(run_manifest$mode), "confirm")) {
  seed_values <- unique(c(as.character(jobs$seed), as.character(reuse_registry$seed %||% character())))
  seed_values <- seed_values[!is.na(seed_values) & nzchar(seed_values)]
  expected_cells <- expected_cells * length(seed_values)
}
aggregate <- if (nrow(scores)) app_glofas_search2_aggregate_scores(scores, require_folds = expected_cells) else data.frame()
baseline_path <- file.path(root, "configs", "confirmation_guardrail_baselines.csv")
if (identical(as.character(run_manifest$mode), "confirm") && nrow(aggregate)) {
  if (!file.exists(baseline_path)) stop("Confirmation guardrail baselines are missing.", call. = FALSE)
  aggregate <- app_glofas_search2_apply_external_guardrails(aggregate, app_read_csv(baseline_path))
}
app_write_csv(health, file.path(root, "tables", "health_latest.csv"))
app_write_csv(scores, file.path(root, "tables", "score_summaries_latest.csv"))
app_write_csv(fits, file.path(root, "tables", "fit_summaries_latest.csv"))
app_write_csv(aggregate, file.path(root, "tables", "aggregate_scores_latest.csv"))
print(health)
if (nrow(aggregate)) print(utils::head(aggregate, 20L))
