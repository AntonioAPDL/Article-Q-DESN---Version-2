#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/latent_path_runtime_backend.R"))
source(app_path("application/R/latent_path_checkpoint.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/glofas_constrained_median_screening.R"))
source(app_path("application/R/glofas_discrepancy_grouped_rhs_campaign.R"))

args <- app_parse_args(list(
  campaign = "application/config/glofas_discrepancy_grouped_rhs_stage_a_20260827.yaml",
  output_root = "",
  authorize_launch = FALSE
))

resolve_path <- function(path, must_work = FALSE) {
  if (grepl("^/", path)) normalizePath(path, mustWork = must_work) else app_resolve_path(path, must_work = must_work)
}

verify_artifact <- function(path, expected_sha, label) {
  path <- resolve_path(as.character(path), must_work = TRUE)
  actual <- tolower(app_sha256_file(path))
  expected <- tolower(as.character(expected_sha))
  if (!nzchar(expected) || !identical(actual, expected)) {
    stop(sprintf("%s SHA-256 mismatch: expected %s, observed %s.", label, expected, actual), call. = FALSE)
  }
  data.frame(label = label, path = path, sha256 = actual, verified = TRUE, stringsAsFactors = FALSE)
}

git_value <- function(...) {
  value <- system2("git", c("-C", repo_root, ...), stdout = TRUE, stderr = TRUE)
  if (!length(value) || any(grepl("^fatal:", value))) NA_character_ else value[[1L]]
}

campaign_path <- resolve_path(args$campaign, must_work = TRUE)
campaign <- app_read_yaml(campaign_path)
app_glofas_grouped_rhs_validate_campaign(campaign)
authorized <- app_as_bool(args$authorize_launch) && app_as_bool(campaign$launch_authorized %||% FALSE)
if (app_as_bool(args$authorize_launch) && !app_as_bool(campaign$launch_authorized %||% FALSE)) {
  stop("Launch authorization was requested but the reviewed campaign is not authorized.", call. = FALSE)
}
if (authorized) {
  branch <- git_value("rev-parse", "--abbrev-ref", "HEAD")
  head <- git_value("rev-parse", "HEAD")
  upstream <- git_value("rev-parse", "@{upstream}")
  dirty <- system2(
    "git",
    c("-C", repo_root, "status", "--porcelain", "--untracked-files=no"),
    stdout = TRUE,
    stderr = TRUE
  )
  forbidden <- c("main", "overleaf/article-snapshot", "overleaf-direct/main")
  if (is.na(branch) || !nzchar(branch) || branch %in% forbidden || length(dirty) ||
      is.na(upstream) || !identical(head, upstream)) {
    stop(
      "Authorized launch requires a clean, pushed, dedicated task branch synchronized with its upstream.",
      call. = FALSE
    )
  }
}
output_value <- as.character(args$output_root %||% "")
if (!nzchar(output_value)) output_value <- as.character(campaign$execution$output_root)
output_root <- resolve_path(output_value, must_work = FALSE)
owned_root <- normalizePath(app_path("local_trackers", "runtime_configs"), mustWork = FALSE)
if (!identical(output_root, owned_root) && !startsWith(output_root, paste0(owned_root, .Platform$file.sep))) {
  stop("Grouped-RHS output_root must remain under this worktree's local_trackers/runtime_configs.", call. = FALSE)
}
if (dir.exists(output_root)) {
  active_payload <- c(
    list.files(file.path(output_root, "runs"), recursive = TRUE, all.files = TRUE, no.. = TRUE),
    list.files(file.path(output_root, "status"), recursive = TRUE, all.files = TRUE, no.. = TRUE)
  )
  if (length(active_payload)) {
    stop("Prepared output_root already contains run/status state; resume it through the orchestrator.", call. = FALSE)
  }
}
for (name in c("candidates", "runs", "logs", "scores", "status", "common_cache", "decisions", "figures", "tables", "cleanup")) {
  app_ensure_dir(file.path(output_root, name))
}

source_cfg <- campaign$source
baseline_cfg <- campaign$baselines
source_audit <- rbind(
  verify_artifact(source_cfg$config, source_cfg$config_sha256, "retained_d16_config"),
  verify_artifact(source_cfg$model_grid, source_cfg$model_grid_sha256, "retained_d16_model_grid"),
  verify_artifact(source_cfg$application_panel, source_cfg$application_panel_sha256, "application_panel"),
  verify_artifact(source_cfg$fit_object, source_cfg$fit_object_sha256, "retained_d16_fit"),
  verify_artifact(source_cfg$design_object, source_cfg$design_object_sha256, "retained_d16_design"),
  verify_artifact(source_cfg$forecast_summary, source_cfg$forecast_summary_sha256, "retained_d16_forecast_summary"),
  verify_artifact(source_cfg$observed_scores, source_cfg$observed_scores_sha256, "retained_d16_observed_scores"),
  verify_artifact(
    baseline_cfg$current_engine_fr09_observed_scores,
    baseline_cfg$current_engine_fr09_observed_scores_sha256,
    "current_engine_fr09_observed_scores"
  ),
  verify_artifact(
    baseline_cfg$current_engine_fr09_forecast_summary,
    baseline_cfg$current_engine_fr09_forecast_summary_sha256,
    "current_engine_fr09_forecast_summary"
  ),
  verify_artifact(
    baseline_cfg$discrepancy_equivalence_paths,
    baseline_cfg$discrepancy_equivalence_paths_sha256,
    "discrepancy_equivalence_paths"
  ),
  verify_artifact(
    baseline_cfg$discrepancy_equivalence_complete,
    baseline_cfg$discrepancy_equivalence_complete_sha256,
    "discrepancy_equivalence_complete"
  ),
  verify_artifact(
    campaign$execution$backend_library,
    campaign$execution$backend_library_sha256,
    "openblas_serial_library"
  )
)
app_write_csv(source_audit, file.path(output_root, "source_artifact_audit.csv"))

base_cfg <- app_read_config(source_audit$path[source_audit$label == "retained_d16_config"])
base_grid <- app_read_csv(source_audit$path[source_audit$label == "retained_d16_model_grid"])
source_fit_path <- source_audit$path[source_audit$label == "retained_d16_fit"]
source_contract <- app_latent_path_warm_start_contract_from_fit(source_fit_path)
if (is.null(source_contract)) stop("Retained D16 fit lacks a semantic warm-start contract.", call. = FALSE)
app_write_yaml(source_contract, file.path(output_root, "retained_d16_warm_start_contract.yaml"))

panel_target <- file.path(output_root, "common_cache", "application_panel.rds")
if (!file.exists(panel_target) && !file.copy(
  source_audit$path[source_audit$label == "application_panel"],
  panel_target,
  copy.mode = TRUE,
  copy.date = TRUE
)) {
  stop("Could not copy the verified application panel into the campaign cache.", call. = FALSE)
}
if (!identical(app_sha256_file(panel_target), source_cfg$application_panel_sha256)) {
  stop("Campaign application-panel copy failed its SHA-256 check.", call. = FALSE)
}

engine <- app_check_qdesn_engine_api(
  base_cfg,
  require_discrepancy = app_qdesn_engine_requires_discrepancy_export(base_cfg, base_grid),
  stop_on_failure = TRUE
)
app_write_csv(app_qdesn_engine_contract_row(engine), file.path(output_root, "qdesn_engine_contract.csv"))

quantile_grid <- data.frame(
  quantile_id = "p50", quantile_level = 0.5, role = "grouped_rhs_mechanism",
  enabled = TRUE, stringsAsFactors = FALSE
)
quantile_path <- file.path(output_root, "quantile_grid_p50.csv")
app_write_csv(quantile_grid, quantile_path)

candidates <- app_glofas_grouped_rhs_stage_a_candidates()
runtime_rows <- list()
contract_rows <- list()
ledger_rows <- list()
for (i in seq_len(nrow(candidates))) {
  row <- candidates[i, , drop = FALSE]
  candidate_id <- row$candidate_id[[1L]]
  candidate_root <- file.path(output_root, "candidates", candidate_id)
  app_ensure_dir(candidate_root)
  cfg <- app_glofas_grouped_rhs_apply_candidate(base_cfg, row)
  cfg$application_name <- paste0("glofas_discrepancy_grouped_rhs_", candidate_id)
  cfg$description <- sprintf("Frozen grouped-RHS Stage A candidate %s", candidate_id)
  cfg$paths$quantile_grid <- quantile_path
  cfg$paths$model_grid <- file.path(candidate_root, "model_grid_p50.csv")
  cfg$paths$cache <- file.path(output_root, "common_cache")
  cfg$paths$runs <- file.path(output_root, "runs")
  cfg$paths$logs <- file.path(output_root, "logs")
  cfg$paths$generated_outputs <- file.path(output_root, "generated")
  cfg$post_analysis$enabled <- TRUE
  cfg$post_analysis$run_after_outputs <- TRUE
  cfg$post_analysis$recent_history_n <- 200L
  cfg$post_analysis$storage$write_history_draws_rds <- FALSE
  cfg$post_analysis$storage$write_history_draws_csv <- FALSE
  cfg$execution$artifacts <- app_qdesn_deep_merge(
    cfg$execution$artifacts %||% list(),
    list(
      retain_fit_object = TRUE,
      retain_design_object = TRUE,
      compact_latent_path_design = TRUE,
      retain_prediction_design_object = FALSE,
      retain_reference_fit_object = FALSE
    )
  )
  cfg$execution$final_launch$enabled <- authorized
  cfg$execution$final_launch$note <- sprintf(
    "A0 authorized and A1 conditionally gated for %s", campaign$campaign_id
  )

  warm <- app_glofas_median_screen_warm_start_plan(
    base_cfg,
    cfg,
    source_fit = source_fit_path,
    source_contract = source_contract
  )
  if (identical(row$warm_start_policy[[1L]], "warm")) {
    if (!isTRUE(warm$enabled) || !identical(warm$compatibility_mode, "exact_design") || !isTRUE(warm$use_theta)) {
      stop(sprintf("Candidate %s did not pass exact-design coefficient warm-start compatibility.", candidate_id), call. = FALSE)
    }
    cfg$inference$vb_ld$warm_start <- list(
      enabled = TRUE,
      fit_object = source_fit_path,
      use_theta = TRUE,
      use_future = TRUE,
      use_sigma = TRUE,
      require_theta = TRUE,
      require_future = TRUE,
      require_sigma = FALSE,
      require_contract = TRUE,
      compatibility_mode = "exact_design",
      source_contract = source_contract,
      covariance_jitter = 1e-8
    )
  } else {
    cfg$inference$vb_ld$warm_start <- list(enabled = FALSE)
    warm <- list(enabled = FALSE, compatibility_mode = "cold", reason = "prospectively frozen cold start")
  }

  model_grid <- base_grid
  quantile <- suppressWarnings(as.numeric(model_grid$quantile_level))
  keep <- (model_grid$model_family == "qdesn_glofas_discrepancy" & abs(quantile - 0.5) < 1e-12) |
    (model_grid$model_family == "raw_glofas" & (is.na(quantile) | abs(quantile - 0.5) < 1e-12))
  model_grid <- model_grid[keep, , drop = FALSE]
  q_idx <- model_grid$model_family == "qdesn_glofas_discrepancy"
  if (sum(q_idx) != 1L) stop("Each grouped-RHS candidate requires exactly one p50 Q-DESN row.", call. = FALSE)
  fit_id <- paste0("qdesn_grouped_rhs_", candidate_id, "_p50")
  model_grid$fit_id[q_idx] <- fit_id
  model_grid$model_id[q_idx] <- fit_id
  model_grid$quantile_level[q_idx] <- 0.5
  model_grid$notes[q_idx] <- sprintf("Grouped-RHS Stage A %s", candidate_id)
  raw_idx <- model_grid$model_family == "raw_glofas"
  if (any(raw_idx)) {
    model_grid$fit_id[raw_idx] <- paste0("raw_glofas_", candidate_id, "_p50")
    model_grid$model_id[raw_idx] <- paste0("raw_glofas_", candidate_id, "_p50")
    model_grid$quantile_level[raw_idx] <- 0.5
  }
  model_grid$config_hash <- "RUNTIME_CONFIG_HASH_RECORDED_IN_MANIFEST"
  app_write_csv(model_grid, cfg$paths$model_grid)

  run_id <- paste0(campaign$campaign_id, "_", candidate_id)
  run_dir <- file.path(output_root, "runs", run_id)
  checkpoint_path <- file.path(run_dir, "checkpoints", paste0(fit_id, ".rds"))
  cfg$inference$vb_ld$checkpoint <- list(
    enabled = TRUE,
    resume = FALSE,
    path = checkpoint_path,
    every_iterations = as.integer(campaign$execution$checkpoint_every_iterations),
    every_minutes = as.numeric(campaign$execution$checkpoint_every_minutes),
    keep_previous = TRUE,
    keep_on_success = FALSE,
    compress = FALSE
  )
  hashes <- app_glofas_grouped_rhs_candidate_hashes(cfg, row)
  config_path <- file.path(candidate_root, "config_p50.yaml")
  app_write_yaml(cfg, config_path)
  vb_args <- app_make_qdesn_discrepancy_vb_args(cfg, "rhs_ns", 20260512L, "al")
  ledger <- vb_args$prior_contract$field_ledger
  ledger$candidate_id <- candidate_id
  ledger$prior_declared_hash <- hashes$prior_declared_hash
  ledger$prior_effective_hash <- hashes$prior_effective_hash
  ledger_rows[[i]] <- ledger

  runtime_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    wave = row$wave[[1L]],
    priority = row$priority[[1L]],
    config_path = normalizePath(config_path, mustWork = TRUE),
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = normalizePath(cfg$paths$model_grid, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(cfg$paths$model_grid),
    run_id = run_id,
    run_dir = run_dir,
    log_path = file.path(output_root, "logs", paste0(candidate_id, ".log")),
    checkpoint_path = checkpoint_path,
    checkpoint_resume_enabled = TRUE,
    reservoir_preflight_enabled = FALSE,
    warm_start_source_fit_object = if (isTRUE(warm$enabled)) source_fit_path else "",
    warm_start_source_sha256 = if (isTRUE(warm$enabled)) source_cfg$fit_object_sha256 else "",
    scientific_model_hash = hashes$scientific_model_hash,
    treatment_hash = hashes$treatment_hash,
    prior_declared_hash = hashes$prior_declared_hash,
    prior_effective_hash_pre_layout = hashes$prior_effective_hash,
    status = if (authorized && row$wave[[1L]] == "A0") "prepared_authorized" else "prepared_conditional",
    stringsAsFactors = FALSE
  )
  contract_rows[[i]] <- data.frame(
    row,
    scientific_model_hash = hashes$scientific_model_hash,
    treatment_hash = hashes$treatment_hash,
    reference_design_signature = app_glofas_median_screen_design_signature(cfg, "reference"),
    discrepancy_design_signature = app_glofas_median_screen_design_signature(cfg, "discrepancy"),
    source_fit_sha256 = source_cfg$fit_object_sha256,
    warm_start_compatibility = warm$compatibility_mode,
    max_iter = 200L,
    full7_authorized = FALSE,
    article_update_authorized = FALSE,
    stringsAsFactors = FALSE
  )
}

runtime_manifest <- app_bind_rows_fill(runtime_rows)
candidate_contract <- app_bind_rows_fill(contract_rows)
if (nrow(runtime_manifest) != 18L || sum(runtime_manifest$wave == "A0") != 8L || sum(runtime_manifest$wave == "A1") != 10L) {
  stop("Materialized runtime manifest violates the frozen 8/10 Stage A contract.", call. = FALSE)
}
if (anyDuplicated(runtime_manifest$treatment_hash)) {
  stop("Materialized runtime manifest contains duplicated numerical treatments.", call. = FALSE)
}
app_write_csv(candidates, file.path(output_root, "candidate_manifest.csv"))
app_write_csv(candidate_contract, file.path(output_root, "candidate_contracts.csv"))
app_write_csv(runtime_manifest, file.path(output_root, "runtime_manifest_all.csv"))
app_write_csv(runtime_manifest[runtime_manifest$wave == "A0", , drop = FALSE], file.path(output_root, "runtime_manifest_a0.csv"))
app_write_csv(runtime_manifest[runtime_manifest$wave == "A1", , drop = FALSE], file.path(output_root, "runtime_manifest_a1.csv"))
app_write_csv(app_bind_rows_fill(ledger_rows), file.path(output_root, "prior_field_ledger.csv"))
campaign_snapshot_path <- file.path(output_root, "campaign_snapshot.yaml")
app_write_yaml(campaign, campaign_snapshot_path)
app_write_git_state(file.path(output_root, "git_state.txt"))
app_write_session_info(file.path(output_root, "session_info.txt"))

provenance <- data.frame(
  field = c(
    "prepared_at", "repo_root", "branch", "head", "origin_main", "campaign_path",
    "campaign_sha256", "output_root", "candidate_count", "a0_count", "a1_count",
    "launch_authorized", "source_contract_hash", "engine_repo", "engine_branch", "engine_commit"
  ),
  value = c(
    format(Sys.time(), tz = "UTC", usetz = TRUE), repo_root,
    git_value("rev-parse", "--abbrev-ref", "HEAD"), git_value("rev-parse", "HEAD"),
    git_value("rev-parse", "origin/main"), campaign_path, app_sha256_file(campaign_path),
    output_root, nrow(runtime_manifest), sum(runtime_manifest$wave == "A0"),
    sum(runtime_manifest$wave == "A1"), authorized,
    app_latent_path_contract_hash(source_contract, "source_contract_"),
    engine$repo_hint, engine$repo_branch, engine$repo_git_sha
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "provenance.csv"))

execution_values <- c(
  CAMPAIGN_ID = as.character(campaign$campaign_id),
  CAMPAIGN_SHA256 = app_sha256_file(campaign_path),
  CAMPAIGN_SNAPSHOT_SHA256 = app_sha256_file(campaign_snapshot_path),
  LAUNCH_AUTHORIZED = tolower(as.character(authorized)),
  PREPARED_HEAD = git_value("rev-parse", "HEAD"),
  MAX_WORKERS = as.character(campaign$execution$max_workers),
  A0_CALIBRATION_JOBS = as.character(campaign$execution$a0_calibration_jobs),
  CALIBRATION_ITERATIONS = as.character(campaign$execution$calibration_iterations),
  MEMORY_RESERVE_GB = as.character(campaign$execution$memory_reserve_gb),
  MINIMUM_FREE_DISK_GB = as.character(campaign$execution$minimum_free_disk_gb),
  MAXIMUM_LOAD = as.character(campaign$execution$maximum_load),
  POLL_SECONDS = as.character(campaign$execution$poll_seconds),
  NUMERICAL_BACKEND = as.character(campaign$execution$numerical_backend),
  BACKEND_THREADS = as.character(campaign$execution$backend_threads),
  BACKEND_LIBRARY = as.character(campaign$execution$backend_library),
  BACKEND_LIBRARY_SHA256 = as.character(campaign$execution$backend_library_sha256)
)
execution_lines <- sprintf(
  "%s=%s",
  names(execution_values),
  vapply(execution_values, shQuote, character(1L), type = "sh")
)
writeLines(execution_lines, file.path(output_root, "orchestration_contract.env"), useBytes = TRUE)

launch_path <- file.path(output_root, "launch_stage_a.sh")
launch_lines <- c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  "",
  if (authorized) sprintf(
    "bash application/scripts/glofas_discrepancy_grouped_rhs_orchestrate.sh %s %s",
    shQuote(campaign_path), shQuote(output_root)
  ) else "echo 'Launch blocked: preparation was not explicitly authorized.' >&2; exit 2"
)
writeLines(launch_lines, launch_path)
Sys.chmod(launch_path, "0750")
cat(sprintf("Prepared %d candidates at %s; A0 launch authorized=%s.\n", nrow(runtime_manifest), output_root, authorized))
