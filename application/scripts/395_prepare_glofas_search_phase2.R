#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_search_phase2.R"))

args <- app_parse_args(list(
  run_label = paste0("glofas_search_phase2_ridge_", format(Sys.time(), "%Y%m%d_%H%M%S")),
  mode = "ridge",
  data_root = "",
  n_space_filling = "64"
))
mode <- match.arg(as.character(args$mode), c("benchmark", "ridge"))
run_label <- as.character(args$run_label)
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) stop("run_label must be path-safe.", call. = FALSE)
data_root <- if (nzchar(as.character(args$data_root))) normalizePath(args$data_root, mustWork = TRUE) else app_glofas_search2_default_data_root()
folds <- app_read_csv(app_path("application/config/glofas_search_phase2_folds_20260914.csv"))
folds$origin_date <- as.Date(folds$origin_date)
app_glofas_search2_validate_folds(folds)
master <- app_glofas_search2_load_master(data_root)

root <- app_path("local_trackers", "runtime_configs", run_label)
dirs <- file.path(root, c(
  "configs", "model_inputs", "scoring_inputs", "forecasts", "fits", "scores", "traces",
  "coefficients", "diagnostics", "status", "logs", "tables", "reports"
))
invisible(lapply(dirs, app_ensure_dir))

packet_registry <- list()
for (target in c("reference", "discrepancy")) {
  for (i in seq_len(nrow(folds))) {
    packets <- app_glofas_search2_make_fold_packets(master, folds[i, , drop = FALSE], target)
    app_glofas_search2_validate_model_packet(packets$model)
    stem <- paste(target, folds$fold_id[[i]], sep = "__")
    model_path <- file.path(root, "model_inputs", paste0(stem, ".rds"))
    score_path <- file.path(root, "scoring_inputs", paste0(stem, ".csv"))
    saveRDS(packets$model, model_path, version = 2L)
    app_write_csv(packets$scoring, score_path)
    packet_registry[[length(packet_registry) + 1L]] <- data.frame(
      target = target, fold_id = folds$fold_id[[i]],
      model_packet_path = normalizePath(model_path), model_packet_sha256 = app_sha256_file(model_path),
      scoring_packet_path = normalizePath(score_path), scoring_packet_sha256 = app_sha256_file(score_path),
      stringsAsFactors = FALSE
    )
  }
}
packet_registry <- app_bind_rows_fill(packet_registry)
app_write_csv(packet_registry[, setdiff(names(packet_registry), c("scoring_packet_path", "scoring_packet_sha256")), drop = FALSE],
  file.path(root, "configs", "model_packet_registry.csv"))
app_write_csv(packet_registry[, c("target", "fold_id", "scoring_packet_path", "scoring_packet_sha256"), drop = FALSE],
  file.path(root, "configs", "scoring_packet_registry.csv"))

candidates <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
  app_glofas_search2_candidate_manifest(target, n_space_filling = as.integer(args$n_space_filling))
}))
app_write_csv(candidates, file.path(root, "configs", "candidate_manifest.csv"))
if (identical(mode, "ridge")) {
  jobs <- app_glofas_search2_expand_jobs(candidates, folds, method = "ridge", stage = "ridge_screen")
} else {
  benchmark_candidates <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    x <- candidates[candidates$target == target & candidates$candidate_role == "phase1_standardized_anchor", , drop = FALSE]
    x[1L, , drop = FALSE]
  }))
  fold <- folds[folds$fold_id == "fold_2021_12_21", , drop = FALSE]
  ridge_jobs <- app_glofas_search2_expand_jobs(benchmark_candidates, fold, method = "ridge", stage = "benchmark_ridge")
  prior <- app_glofas_search2_prior_specs()
  prior <- prior[prior$prior_id == "phase1_legacy_tau0", , drop = FALSE]
  rhs_jobs <- app_glofas_search2_rhs_manifest(benchmark_candidates, fold, prior, stage = "benchmark_rhs")
  jobs <- app_bind_rows_fill(list(ridge_jobs, rhs_jobs))
}
jobs <- merge(jobs, packet_registry[, c("target", "fold_id", "model_packet_path", "model_packet_sha256")],
  by = c("target", "fold_id"), all.x = TRUE, sort = FALSE)
if (any(!nzchar(jobs$model_packet_path)) || anyDuplicated(jobs$job_id)) stop("Prepared Search-II jobs are not uniquely packeted.", call. = FALSE)
jobs <- jobs[order(jobs$priority, jobs$target, jobs$fold_id, jobs$method), , drop = FALSE]
app_write_csv(jobs, file.path(root, "configs", "job_manifest.csv"))

manifest <- list(
  version = "glofas_search_phase2_runtime_v1",
  run_label = run_label, mode = mode, created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  repo_root = app_repo_root(), git_head = app_git_sha(short = FALSE),
  scientific_contract = list(
    tuning_target = c("USGS log1p", "GloFAS log1p minus USGS log1p"),
    folds = as.character(folds$origin_date), primary_horizon = 28L, secondary_horizon = 30L,
    final_origin_excluded = as.character(app_glofas_search2_final_origin()),
    forecast = "fixed-origin recursive plugin mean with oracle realized PRISM/ERA5 covariates",
    no_future_truth_in_model_packets = TRUE, score_equivalence_precision = 4L
  ),
  source_paths = as.list(master$paths), source_sha256 = as.list(master$sha256),
  job_count = nrow(jobs), candidate_count = nrow(candidates)
)
app_write_yaml(manifest, file.path(root, "configs", "run_manifest.yaml"))
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))
cat(root, "\n")
