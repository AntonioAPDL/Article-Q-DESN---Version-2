#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/glofas_discrepancy_tau0_screen.R"))

args <- app_parse_args(list(
  source_root = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829",
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_tau0_relax_p50_20260831",
  run_date = "20260831",
  max_iter = 400L,
  plan = "local_trackers/glofas_discrepancy_tau0_relaxation_ultimate_plan_20260831.md"
))

resolve_path <- function(path, must_work = TRUE) {
  normalizePath(if (grepl("^/", path)) path else file.path(repo_root, path), mustWork = must_work)
}
copy_verified <- function(source, destination) {
  source <- normalizePath(source, mustWork = TRUE)
  app_ensure_dir(dirname(destination))
  if (file.exists(destination)) {
    if (!identical(app_sha256_file(source), app_sha256_file(destination))) {
      stop(sprintf("Existing snapshot differs from source: %s.", destination), call. = FALSE)
    }
  } else if (!file.copy(source, destination, copy.mode = TRUE, copy.date = TRUE)) {
    stop(sprintf("Could not snapshot %s.", source), call. = FALSE)
  }
  normalizePath(destination, mustWork = TRUE)
}
one_file <- function(path, pattern, label, exclude = NULL) {
  files <- list.files(path, pattern = pattern, full.names = TRUE)
  if (!is.null(exclude)) files <- files[!grepl(exclude, basename(files))]
  if (length(files) != 1L) {
    stop(sprintf("Expected one %s in %s; found %d.", label, path, length(files)), call. = FALSE)
  }
  normalizePath(files, mustWork = TRUE)
}

source_root <- resolve_path(as.character(args$source_root), must_work = TRUE)
output_root <- resolve_path(as.character(args$output_root), must_work = FALSE)
run_date <- as.character(args$run_date)
max_iter <- as.integer(args$max_iter)
if (!grepl("^[0-9]{8}$", run_date)) stop("run_date must use YYYYMMDD.", call. = FALSE)
if (!is.finite(max_iter) || max_iter < 51L) stop("max_iter must exceed 50.", call. = FALSE)

source_runtime_path <- file.path(source_root, "runtime_manifest.csv")
source_runtime <- app_read_csv(source_runtime_path)
if (nrow(source_runtime) != 1L) stop("Source runtime manifest must contain one row.", call. = FALSE)
source_run_dir <- normalizePath(source_runtime$run_dir[[1L]], mustWork = TRUE)
if (!file.exists(file.path(source_run_dir, ".fit_recovery_complete"))) {
  stop("The retained tau0=0.1 source run is not complete.", call. = FALSE)
}
source_config_path <- normalizePath(source_runtime$config_path[[1L]], mustWork = TRUE)
source_grid_path <- normalizePath(source_runtime$model_grid_path[[1L]], mustWork = TRUE)
source_fit_path <- one_file(file.path(source_run_dir, "objects"), "[.]rds$", "source fit", "__(design|prediction_design|vb_checkpoint)[.]rds$")
source_design_path <- one_file(file.path(source_run_dir, "objects"), "__design[.]rds$", "source design")
source_history_path <- file.path(source_run_dir, "tables", "post_fit_discrepancy_history_summary.csv")
source_forecast_path <- file.path(source_run_dir, "tables", "post_fit_forecast_window_summary.csv")
source_score_path <- file.path(source_root, "scores", paste0(source_runtime$candidate_id[[1L]], "_observed_fit_scores.csv"))
source_run_score_path <- file.path(source_run_dir, "tables", "score_summary.csv")
for (path in c(source_history_path, source_forecast_path, source_score_path, source_run_score_path)) {
  if (!file.exists(path)) stop(sprintf("Missing source evidence: %s.", path), call. = FALSE)
}

source_fit <- readRDS(source_fit_path)
source_fit_inner <- source_fit$fit %||% source_fit
source_warm_contract <- source_fit_inner$warm_start_contract %||% source_fit_inner$summary$warm_start_contract %||% NULL
if (is.null(source_warm_contract)) stop("Source fit lacks a warm-start semantic contract.", call. = FALSE)
source_cfg <- app_read_config(source_config_path)
if (!isTRUE(all.equal(as.numeric(source_cfg$inference$vb_ld$rhs_tau0), 0.1, tolerance = 1.0e-15)) ||
    !isTRUE(all.equal(as.numeric(source_cfg$inference$vb_ld$rhs_alpha_tau0), 0.1, tolerance = 1.0e-15))) {
  stop("The source fit is not the frozen shared=0.1/discrepancy=0.1 candidate.", call. = FALSE)
}
if (!identical(app_qdesn_block_input_stream(source_cfg, "reference"), "reference") ||
    !identical(app_qdesn_block_input_stream(source_cfg, "discrepancy"), "reference")) {
  stop("The retained source does not use the shared reference input contract.", call. = FALSE)
}

for (dir in c("source", "configs", "model_grids", "common_cache", "runs", "logs", "generated", "scores", "status", "tables", "manifest", "preflight")) {
  app_ensure_dir(file.path(output_root, dir))
}

source_asset_paths <- list(
  source_config = source_config_path,
  source_model_grid = source_grid_path,
  input_bundle = normalizePath(source_cfg$paths$input_bundle, mustWork = TRUE),
  input_bundle_manifest = normalizePath(source_cfg$paths$input_bundle_manifest, mustWork = TRUE),
  input_manifest = normalizePath(source_cfg$paths$input_manifest, mustWork = TRUE),
  quantile_grid = normalizePath(source_cfg$paths$quantile_grid, mustWork = TRUE),
  application_panel = file.path(source_cfg$paths$cache, "application_panel.rds"),
  source_fit = source_fit_path,
  source_design = source_design_path,
  source_history = source_history_path,
  source_forecast = source_forecast_path,
  source_observed_scores = source_score_path,
  source_forecast_scores = source_run_score_path
)
source_asset_paths$application_panel <- normalizePath(source_asset_paths$application_panel, mustWork = TRUE)

snapshots <- list(
  source_config = copy_verified(source_config_path, file.path(output_root, "source", "source_config_tau0_0p1.yaml")),
  source_model_grid = copy_verified(source_grid_path, file.path(output_root, "source", "source_model_grid_tau0_0p1.csv")),
  input_bundle = copy_verified(source_asset_paths$input_bundle, file.path(output_root, "source", "input_bundle.yaml")),
  input_bundle_manifest = copy_verified(source_asset_paths$input_bundle_manifest, file.path(output_root, "source", "input_bundle_manifest.csv")),
  input_manifest = copy_verified(source_asset_paths$input_manifest, file.path(output_root, "source", "input_manifest.csv")),
  quantile_grid = copy_verified(source_asset_paths$quantile_grid, file.path(output_root, "source", "quantile_grid_p50.csv")),
  application_panel = copy_verified(source_asset_paths$application_panel, file.path(output_root, "common_cache", "application_panel.rds"))
)

base_cfg <- source_cfg
base_cfg$paths$input_bundle <- snapshots$input_bundle
base_cfg$paths$input_bundle_manifest <- snapshots$input_bundle_manifest
base_cfg$paths$input_manifest <- snapshots$input_manifest
base_cfg$paths$quantile_grid <- snapshots$quantile_grid
base_cfg$paths$model_grid <- snapshots$source_model_grid
base_cfg$paths$cache <- file.path(output_root, "common_cache")
base_cfg$paths$runs <- file.path(output_root, "runs")
base_cfg$paths$logs <- file.path(output_root, "logs")
base_cfg$paths$generated_outputs <- file.path(output_root, "generated")
base_config_path <- file.path(output_root, "source", "campaign_base_config.yaml")
app_write_yaml(base_cfg, base_config_path)

base_grid <- app_read_csv(source_grid_path)
qrow <- base_grid$model_family == "qdesn_glofas_discrepancy"
rrow <- base_grid$model_family == "raw_glofas"
if (sum(qrow) != 1L || sum(rrow) != 1L ||
    abs(as.numeric(base_grid$quantile_level[qrow]) - 0.5) > 1.0e-12) {
  stop("Source model grid must contain one p50 Q-DESN and one raw comparator.", call. = FALSE)
}

treatments <- data.frame(
  discrepancy_tau0 = c(app_glofas_discrepancy_tau0_values(), 1),
  warm_start = c(rep(TRUE, length(app_glofas_discrepancy_tau0_values())), FALSE),
  candidate_role = c(rep("warm_screen", length(app_glofas_discrepancy_tau0_values())), "cold_canary"),
  priority = seq_len(length(app_glofas_discrepancy_tau0_values()) + 1L),
  stringsAsFactors = FALSE
)

rows <- vector("list", nrow(treatments))
contracts <- vector("list", nrow(treatments))
for (i in seq_len(nrow(treatments))) {
  tau0 <- treatments$discrepancy_tau0[[i]]
  warm <- treatments$warm_start[[i]]
  candidate_id <- app_glofas_discrepancy_tau0_candidate_id(tau0, warm = warm)
  fit_id <- paste0("qdesn_", candidate_id)
  run_id <- paste0("glofas_", candidate_id, "_", run_date)
  grid <- base_grid
  grid$fit_id[qrow] <- fit_id
  grid$model_id[qrow] <- fit_id
  grid$fit_id[rrow] <- paste0("raw_glofas_", candidate_id)
  grid$model_id[rrow] <- grid$fit_id[rrow]
  grid$config_hash <- "RUNTIME_CONFIG_HASH_RECORDED_IN_MANIFEST"
  grid$notes[qrow] <- paste(
    "Exact-design discrepancy tau0 relaxation; shared tau0=0.1; discrepancy tau0=",
    format(tau0, scientific = TRUE), ";", if (warm) "strict warm start" else "cold canary"
  )
  grid_path <- file.path(output_root, "model_grids", paste0(candidate_id, ".csv"))
  app_write_csv(grid, grid_path)

  cfg <- app_glofas_discrepancy_tau0_apply_config(
    source_cfg = base_cfg,
    candidate_id = candidate_id,
    model_grid_path = grid_path,
    output_root = output_root,
    discrepancy_tau0 = tau0,
    max_iter = max_iter,
    warm_start_fit = if (warm) source_fit_path else NULL,
    warm_start_contract = if (warm) source_warm_contract else NULL
  )
  app_qdesn_validate_block_configs(cfg)
  app_glofas_discrepancy_tau0_assert_one_axis(base_cfg, cfg, tau0, max_iter, warm)
  config_path <- file.path(output_root, "configs", paste0(candidate_id, ".yaml"))
  app_write_yaml(cfg, config_path)
  run_dir <- file.path(output_root, "runs", run_id)
  checkpoint_path <- file.path(run_dir, "objects", paste0(fit_id, "__vb_checkpoint.rds"))
  rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    priority = treatments$priority[[i]],
    candidate_role = treatments$candidate_role[[i]],
    discrepancy_tau0 = tau0,
    reference_tau0 = 0.1,
    warm_start_enabled = warm,
    config_path = normalizePath(config_path, mustWork = TRUE),
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = normalizePath(grid_path, mustWork = TRUE),
    model_grid_sha256 = app_sha256_file(grid_path),
    run_id = run_id,
    run_dir = normalizePath(run_dir, mustWork = FALSE),
    log_path = normalizePath(file.path(output_root, "logs", paste0(candidate_id, ".log")), mustWork = FALSE),
    warm_start_source_fit_object = if (warm) source_fit_path else "",
    warm_start_source_sha256 = if (warm) app_sha256_file(source_fit_path) else "",
    checkpoint_resume_enabled = TRUE,
    checkpoint_path = normalizePath(checkpoint_path, mustWork = FALSE),
    reservoir_preflight_enabled = FALSE,
    status = "prepared",
    stringsAsFactors = FALSE
  )
  contracts[[i]] <- data.frame(
    candidate_id = candidate_id,
    treatment_field = "inference.vb_ld.rhs_alpha_tau0",
    treatment_value = tau0,
    warm_start = warm,
    shared_tau0 = 0.1,
    max_iter = max_iter,
    architecture = "D1_n300_m360_alpha0.1_rho0.95",
    reference_input_stream = "reference",
    discrepancy_input_stream = "reference",
    reference_direct_input = TRUE,
    discrepancy_direct_input = FALSE,
    automatic_promotion = FALSE,
    automatic_full7 = FALSE,
    stringsAsFactors = FALSE
  )
}
manifest <- do.call(rbind, rows)
contract <- do.call(rbind, contracts)
app_write_csv(manifest, file.path(output_root, "candidate_registry.csv"))
app_write_csv(manifest, file.path(output_root, "runtime_manifest.csv"))
app_write_csv(contract, file.path(output_root, "manifest", "candidate_contract.csv"))
app_write_csv(treatments, file.path(output_root, "manifest", "treatment_registry.csv"))

source_manifest <- do.call(rbind, lapply(names(source_asset_paths), function(role) {
  path <- normalizePath(source_asset_paths[[role]], mustWork = TRUE)
  data.frame(role = role, path = path, size_bytes = file.info(path)$size, sha256 = app_sha256_file(path), stringsAsFactors = FALSE)
}))
app_write_csv(source_manifest, file.path(output_root, "manifest", "source_evidence_manifest.csv"))

plan_path <- resolve_path(as.character(args$plan), must_work = FALSE)
provenance <- data.frame(
  field = c(
    "prepared_at", "repo_head", "repo_branch", "prepare_script_sha256", "module_sha256",
    "source_fit_sha256", "source_design_sha256", "source_design_contract_hash",
    "campaign_base_config_sha256", "plan_path", "plan_sha256", "candidate_count",
    "new_scientific_levels", "intentional_duplicate_count"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    system2("git", c("-C", repo_root, "branch", "--show-current"), stdout = TRUE)[[1L]],
    app_sha256_file(app_path("application/scripts/glofas_discrepancy_tau0_screen_prepare.R")),
    app_sha256_file(app_path("application/R/glofas_discrepancy_tau0_screen.R")),
    app_sha256_file(source_fit_path), app_sha256_file(source_design_path),
    as.character(source_warm_contract$design_hash), app_sha256_file(base_config_path),
    plan_path, if (file.exists(plan_path)) app_sha256_file(plan_path) else NA_character_,
    nrow(manifest), length(app_glofas_discrepancy_tau0_values()), 1L
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "manifest", "preparation_provenance.csv"))
writeLines(c(
  "GloFAS p50 discrepancy tau0 relaxation campaign.",
  "Existing discrepancy tau0=0.1 evidence is reused and is not refit.",
  "New warm levels: 0.3, 1, 3, 10; one cold tau0=1 canary validates warm equivalence.",
  "All scientific fields except discrepancy tau0 are frozen; max_iter/hard cap are 400.",
  "No automatic promotion, full7 launch, article update, or cleanup is permitted."
), file.path(output_root, "README.txt"))

cat(normalizePath(file.path(output_root, "candidate_registry.csv"), mustWork = TRUE), "\n")
