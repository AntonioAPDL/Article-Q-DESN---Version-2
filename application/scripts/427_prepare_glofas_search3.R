#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "model_contract.R", "feature_contract.R", "covariate_design.R",
  "latent_path_design.R", "discrepancy_design.R", "glofas_normal_desn_part1_screening.R",
  "glofas_normal_oracle_forecast.R", "glofas_search_phase2.R", "glofas_search3_rainy_season.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(
  campaign_root = "", stage = "stage0", data_root = "", search2_ridge_root = ""
))
stage <- match.arg(as.character(args$stage), c(
  "stage0", "ridge_a", "ridge_b", "ridge_guard", "rhs_pilot", "rhs_screen", "confirmation"
))
campaign_root <- app_resolve_path(args$campaign_root, must_work = FALSE)
app_glofas_search2_assert_git_state()

ensure_stage_dirs <- function(root) {
  invisible(lapply(file.path(root, c(
    "configs", "model_inputs", "scoring_inputs", "forecasts", "fits", "scores", "traces",
    "coefficients", "warm_starts", "diagnostics", "status", "logs", "tables", "reports"
  )), app_ensure_dir))
}

if (stage == "stage0") {
  existing <- if (dir.exists(campaign_root)) list.files(campaign_root, all.files = TRUE, no.. = TRUE) else character()
  if (length(setdiff(existing, "logs"))) {
    stop("Search III campaign root already contains non-controller artifacts.", call. = FALSE)
  }
  invisible(lapply(file.path(campaign_root, c("configs", "model_inputs", "scoring_inputs", "stages", "tables", "reports", "logs")), app_ensure_dir))
  data_root <- if (nzchar(as.character(args$data_root))) normalizePath(args$data_root, mustWork = TRUE) else app_glofas_search2_default_data_root()
  ridge_root <- normalizePath(as.character(args$search2_ridge_root), mustWork = TRUE)
  source_candidate_path <- file.path(ridge_root, "configs", "candidate_manifest.csv")
  source_score_path <- file.path(ridge_root, "tables", "aggregate_scores_latest.csv")
  if (!file.exists(source_candidate_path) || !file.exists(source_score_path)) {
    stop("Search III requires the sealed Search II Ridge candidate and aggregate tables.", call. = FALSE)
  }
  folds <- app_glofas_search3_fold_registry()
  candidates <- app_glofas_search3_candidates(app_read_csv(source_candidate_path), app_read_csv(source_score_path))
  master <- app_glofas_search2_load_master(data_root)
  packet_registry <- list()
  for (target in c("reference", "discrepancy")) {
    for (i in seq_len(nrow(folds))) {
      packets <- app_glofas_search2_make_fold_packets(master, folds[i, , drop = FALSE], target)
      app_glofas_search2_validate_model_packet(packets$model)
      stem <- paste(target, folds$fold_id[[i]], sep = "__")
      model_path <- file.path(campaign_root, "model_inputs", paste0(stem, ".rds"))
      score_path <- file.path(campaign_root, "scoring_inputs", paste0(stem, ".csv"))
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
  app_write_csv(folds, file.path(campaign_root, "configs", "fold_registry.csv"))
  app_write_csv(candidates, file.path(campaign_root, "configs", "candidate_manifest.csv"))
  app_write_csv(packet_registry, file.path(campaign_root, "configs", "packet_registry.csv"))
  source_registry <- data.frame(
    role = c("search2_candidates", "search2_ridge_scores", names(master$paths)),
    path = c(normalizePath(source_candidate_path), normalizePath(source_score_path), unname(master$paths)),
    sha256 = c(app_sha256_file(source_candidate_path), app_sha256_file(source_score_path), unname(master$sha256)),
    stringsAsFactors = FALSE
  )
  app_write_csv(source_registry, file.path(campaign_root, "configs", "source_registry.csv"))
  app_write_yaml(list(
    version = app_glofas_search3_version(), created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    git_head = app_git_sha(short = FALSE), data_root = data_root, final_origin_excluded = "2022-12-25",
    season = "October-March", candidates = nrow(candidates), folds = nrow(folds),
    contract = list(
      response_scale = "log1p", primary_horizon = 28L, secondary_horizon = 30L,
      oracle_covariates = c("PRISM precipitation", "ERA5 soil moisture"),
      future_truth_scoring_only = TRUE, exact_rhs_iterations = 200L,
      beta_freeze_iterations = 20L, confirmation_lockbox = TRUE
    )
  ), file.path(campaign_root, "configs", "campaign_manifest.yaml"))
  app_write_git_state(file.path(campaign_root, "configs", "git_state.txt"))
  app_write_session_info(file.path(campaign_root, "configs", "session_info.txt"))
  cat(campaign_root, "\n")
  quit(save = "no", status = 0L)
}

if (!file.exists(file.path(campaign_root, "configs", "campaign_manifest.yaml"))) {
  stop("Search III stage preparation requires a completed Stage 0 campaign root.", call. = FALSE)
}
campaign_manifest <- app_read_yaml(file.path(campaign_root, "configs", "campaign_manifest.yaml"))
if (!identical(as.character(campaign_manifest$git_head), app_git_sha(short = FALSE))) {
  stop("Search III campaign source HEAD drifted after Stage 0.", call. = FALSE)
}
folds <- app_read_csv(file.path(campaign_root, "configs", "fold_registry.csv")); folds$origin_date <- as.Date(folds$origin_date)
candidates <- app_read_csv(file.path(campaign_root, "configs", "candidate_manifest.csv"))
packets <- app_read_csv(file.path(campaign_root, "configs", "packet_registry.csv"))
stage_root <- file.path(campaign_root, "stages", stage)
if (dir.exists(stage_root) && length(list.files(stage_root, all.files = TRUE, no.. = TRUE))) {
  stop(sprintf("Search III stage '%s' already exists and is non-empty.", stage), call. = FALSE)
}
ensure_stage_dirs(stage_root)

read_table <- function(stage_name, file) {
  path <- file.path(campaign_root, "stages", stage_name, "tables", file)
  if (!file.exists(path)) stop(sprintf("Required upstream Search III table is missing: %s", path), call. = FALSE)
  app_read_csv(path)
}

candidate_subset <- candidates
stage_folds <- app_glofas_search3_folds(folds, stage)
reused <- data.frame()
if (stage == "ridge_a") {
  jobs <- app_glofas_search2_expand_jobs(candidates, stage_folds, "ridge", "search3_ridge_a")
} else if (stage == "ridge_b") {
  candidate_subset <- read_table("ridge_a", "advanced_candidates.csv")
  jobs <- app_glofas_search2_expand_jobs(candidate_subset, stage_folds, "ridge", "search3_ridge_b")
} else if (stage == "ridge_guard") {
  candidate_subset <- read_table("ridge_b", "guard_pool.csv")
  jobs <- app_glofas_search2_expand_jobs(candidate_subset, stage_folds, "ridge", "search3_ridge_guard")
} else if (stage == "rhs_pilot") {
  candidate_subset <- read_table("ridge_guard", "pilot_architectures.csv")
  jobs <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    app_glofas_search3_rhs_jobs(
      candidate_subset[candidate_subset$target == target, , drop = FALSE], stage_folds,
      app_glofas_search3_rhs_priors(target), "search3_rhs_pilot"
    )
  }))
} else if (stage == "rhs_screen") {
  candidate_subset <- read_table("ridge_guard", "rhs_shortlist.csv")
  selected_prior <- read_table("rhs_pilot", "selected_priors.csv")
  jobs <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    prior <- app_glofas_search3_rhs_priors(target)
    prior <- prior[prior$prior_id == selected_prior$prior_id[selected_prior$target == target], , drop = FALSE]
    app_glofas_search3_rhs_jobs(
      candidate_subset[candidate_subset$target == target, , drop = FALSE], stage_folds,
      prior, "search3_rhs_screen"
    )
  }))
} else {
  candidate_subset <- read_table("rhs_screen", "confirmation_finalists.csv")
  selected_prior <- read_table("rhs_pilot", "selected_priors.csv")
  jobs <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    prior <- app_glofas_search3_rhs_priors(target)
    prior <- prior[prior$prior_id == selected_prior$prior_id[selected_prior$target == target], , drop = FALSE]
    app_glofas_search3_rhs_jobs(
      candidate_subset[candidate_subset$target == target, , drop = FALSE], stage_folds,
      prior, "search3_confirmation", app_glofas_search3_seeds(target)
    )
  }))
}

ridge_registry <- list()
for (ridge_stage in c("ridge_a", "ridge_b", "ridge_guard")) {
  manifest_path <- file.path(campaign_root, "stages", ridge_stage, "configs", "job_manifest.csv")
  if (!file.exists(manifest_path)) next
  x <- app_read_csv(manifest_path)
  x$ridge_warm_start_path <- file.path(
    campaign_root, "stages", ridge_stage, "warm_starts", paste0(x$job_id, "_warm_start.rds")
  )
  ridge_registry[[length(ridge_registry) + 1L]] <- x[, c("target", "candidate_id", "fold_id", "ridge_warm_start_path")]
}
ridge_registry <- app_bind_rows_fill(ridge_registry)
if (stage %in% c("rhs_pilot", "rhs_screen")) {
  key <- paste(jobs$target, jobs$candidate_id, jobs$fold_id, sep = "|")
  ridge_key <- paste(ridge_registry$target, ridge_registry$candidate_id, ridge_registry$fold_id, sep = "|")
  idx <- match(key, ridge_key)
  if (any(is.na(idx))) stop("Search III RHS development jobs lack matching Ridge warm starts.", call. = FALSE)
  jobs$ridge_warm_start_path <- ridge_registry$ridge_warm_start_path[idx]
  if (any(!file.exists(jobs$ridge_warm_start_path))) stop("Search III matching Ridge warm-start artifacts are missing.", call. = FALSE)
  jobs$ridge_warm_start_path <- vapply(jobs$ridge_warm_start_path, normalizePath, character(1L), mustWork = TRUE)
  jobs$ridge_warm_start_sha256 <- vapply(jobs$ridge_warm_start_path, app_sha256_file, character(1L))
}
if (stage == "confirmation") {
  jobs$ridge_warm_start_path <- NA_character_
  jobs$ridge_warm_start_sha256 <- NA_character_
}

jobs <- merge(
  jobs, packets[, c("target", "fold_id", "model_packet_path", "model_packet_sha256")],
  by = c("target", "fold_id"), all.x = TRUE, sort = FALSE
)
if (anyDuplicated(jobs$job_id) || any(is.na(jobs$model_packet_path))) stop("Search III jobs are not uniquely packeted.", call. = FALSE)

expected <- c(ridge_a = 960L, ridge_b = 160L, ridge_guard = 48L, rhs_pilot = 144L, rhs_screen = 288L, confirmation = 432L)[[stage]]
if (nrow(jobs) != expected) stop(sprintf("Search III %s produced %d jobs; expected %d.", stage, nrow(jobs), expected), call. = FALSE)

if (stage == "rhs_screen") {
  pilot_root <- file.path(campaign_root, "stages", "rhs_pilot")
  pilot_jobs <- app_read_csv(file.path(pilot_root, "configs", "job_manifest.csv"))
  key <- paste(jobs$target, jobs$candidate_id, jobs$fold_id, jobs$prior_id, sep = "|")
  pilot_key <- paste(pilot_jobs$target, pilot_jobs$candidate_id, pilot_jobs$fold_id, pilot_jobs$prior_id, sep = "|")
  hit <- match(key, pilot_key)
  reuse_rows <- which(!is.na(hit))
  if (length(reuse_rows) != 48L) stop(sprintf("Search III RHS screen found %d reusable pilot cells; expected 48.", length(reuse_rows)), call. = FALSE)
  reused <- app_bind_rows_fill(lapply(reuse_rows, function(i) {
    source_job <- pilot_jobs$job_id[[hit[[i]]]]
    destination_job <- jobs$job_id[[i]]
    paths <- c(
      fit_summary = file.path(pilot_root, "fits", paste0(source_job, "_summary.csv")),
      score_summary = file.path(pilot_root, "scores", paste0(source_job, "_summary.csv")),
      score_detail = file.path(pilot_root, "scores", paste0(source_job, "_detail.csv"))
    )
    if (any(!file.exists(paths))) stop("Search III pilot reuse artifact is missing.", call. = FALSE)
    data.frame(
      destination_job_id = destination_job, source_job_id = source_job,
      source_runtime_root = normalizePath(pilot_root),
      fit_summary_path = normalizePath(paths[["fit_summary"]]), fit_summary_sha256 = app_sha256_file(paths[["fit_summary"]]),
      score_summary_path = normalizePath(paths[["score_summary"]]), score_summary_sha256 = app_sha256_file(paths[["score_summary"]]),
      score_detail_path = normalizePath(paths[["score_detail"]]), score_detail_sha256 = app_sha256_file(paths[["score_detail"]]),
      stringsAsFactors = FALSE
    )
  }))
  for (job_id in reused$destination_job_id) writeLines("reused_from_rhs_pilot", file.path(stage_root, "status", paste0(job_id, ".done")))
}

stage_packets <- packets[packets$fold_id %in% stage_folds$fold_id, , drop = FALSE]
app_write_csv(jobs, file.path(stage_root, "configs", "job_manifest.csv"))
app_write_csv(candidate_subset, file.path(stage_root, "configs", "candidate_manifest.csv"))
app_write_csv(stage_folds, file.path(stage_root, "configs", "fold_registry.csv"))
app_write_csv(stage_packets[, c("target", "fold_id", "model_packet_path", "model_packet_sha256")], file.path(stage_root, "configs", "model_packet_registry.csv"))
app_write_csv(stage_packets[, c("target", "fold_id", "scoring_packet_path", "scoring_packet_sha256")], file.path(stage_root, "configs", "scoring_packet_registry.csv"))
app_write_csv(reused, file.path(stage_root, "configs", "reused_score_registry.csv"))
app_write_yaml(list(
  version = app_glofas_search3_version(), stage = stage, mode = ifelse(grepl("ridge", stage), "ridge", "rhs"),
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), git_head = app_git_sha(short = FALSE),
  campaign_root = normalizePath(campaign_root), job_count = nrow(jobs), reused_job_count = nrow(reused),
  exact_rhs_iterations = ifelse(grepl("rhs|confirmation", stage), 200L, NA_integer_),
  confirmation_aggregate_locked_until_complete = identical(stage, "confirmation")
), file.path(stage_root, "configs", "run_manifest.yaml"))
cat(stage_root, "\n")
