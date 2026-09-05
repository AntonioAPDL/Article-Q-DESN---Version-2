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
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))
source(app_path("application/R/glofas_normal_desn_part3_joint_bridge.R"))
source(app_path("application/R/glofas_part3_partitioned_rhs.R"))
source(app_path("application/R/glofas_part3_quantile_bridge.R"))
source(app_path("application/R/glofas_normal_oracle_forecast.R"))
source(app_path("application/R/glofas_part3_historical_forecast.R"))

args <- app_parse_args(list(
  base_config = "",
  winner_manifest = "",
  normal_runtime_root = "",
  runtime_root = "",
  horizon_days = "30"
))

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
winner_manifest <- app_resolve_path(args$winner_manifest, must_work = TRUE)
normal_runtime_root <- app_resolve_path(args$normal_runtime_root, must_work = TRUE)
runtime_root <- app_resolve_path(args$runtime_root, must_work = FALSE)
horizon_days <- as.integer(args$horizon_days)
dirs <- file.path(runtime_root, c("configs", "objects", "scores", "forecasts", "traces", "coefficients", "tables", "logs", "status", "scripts"))
invisible(lapply(dirs, app_ensure_dir))

normal_families <- c("normal_ridge_joint", "normal_rhs_vb_joint")
normal_rows <- lapply(normal_families, function(family) {
  completed <- file.path(normal_runtime_root, "status", paste0(family, ".completed"))
  fit_path <- file.path(normal_runtime_root, "objects", paste0(family, "_fit.rds"))
  contract_path <- file.path(normal_runtime_root, "logs", paste0(family, "_execution_contract.csv"))
  if (!file.exists(completed) || !file.exists(fit_path) || !file.exists(contract_path)) {
    stop(sprintf("Part 3 Normal prerequisite is incomplete: %s", family), call. = FALSE)
  }
  contract <- app_read_csv(contract_path)
  if (nrow(contract) != 1L || !identical(tolower(contract$output_fit_sha256[[1L]]), tolower(app_sha256_file(fit_path)))) {
    stop(sprintf("Part 3 Normal prerequisite hash check failed: %s", family), call. = FALSE)
  }
  data.frame(
    model_family = family,
    fit_path = normalizePath(fit_path, mustWork = TRUE),
    fit_sha256 = app_sha256_file(fit_path),
    execution_contract_path = normalizePath(contract_path, mustWork = TRUE),
    execution_contract_sha256 = app_sha256_file(contract_path),
    stringsAsFactors = FALSE
  )
})
normal_inventory <- app_bind_rows_fill(normal_rows)

manifest <- app_glofas_normal_part3_validate_winner_manifest(winner_manifest, require_frozen = TRUE)
candidate <- app_glofas_normal_part3_candidate_from_winners(
  manifest,
  candidate_id = "part3_frozen_g1_g2_joint_historical",
  require_frozen = TRUE
)
design <- app_glofas_normal_part3_build_design(app_read_config(base_config), candidate)
split <- app_glofas_normal_part3_validation_split(design, candidate)
origin <- app_glofas_part3_forecast_origin(design, split, horizon_days)
app_glofas_part3_validate_quantile_design(design)

for (ii in seq_len(nrow(normal_inventory))) {
  fit <- readRDS(normal_inventory$fit_path[[ii]])
  if (length(fit$beta_mean %||% numeric()) != ncol(design$H)) {
    stop(sprintf("Part 3 Normal fit dimension mismatch: %s", normal_inventory$model_family[[ii]]), call. = FALSE)
  }
}

cache <- list(
  schema_version = "glofas_part3_quantile_forecast_design_cache_v1",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  base_config = base_config,
  base_config_sha256 = app_sha256_file(base_config),
  winner_manifest = winner_manifest,
  winner_manifest_sha256 = app_sha256_file(winner_manifest),
  candidate = candidate,
  design = design,
  split = split,
  origin = origin,
  design_hash = design$design_hash,
  normal_inventory = normal_inventory,
  scientific_contract = list(
    model = "USGS=q_reference+error; retrospective_GloFAS=q_reference+q_discrepancy+error",
    discrepancy_sign = "retrospective_glofas_minus_usgs",
    forecast = "fixed_origin_30_day_oracle_realized_prism_era5",
    prohibited = c("future_usgs", "future_discrepancy", "CEFS", "GEFS", "forecast_ensembles", "rolling_origin", "synthesis")
  )
)
cache_path <- file.path(runtime_root, "configs", "part3_design_cache.rds")
saveRDS(cache, cache_path, version = 2L)
cache_sha256 <- app_sha256_file(cache_path)
app_write_csv(normal_inventory, file.path(runtime_root, "configs", "part3_normal_fit_inventory.csv"))

certificate <- data.frame(
  schema_version = cache$schema_version,
  base_config = base_config,
  base_config_sha256 = cache$base_config_sha256,
  winner_manifest = winner_manifest,
  winner_manifest_sha256 = cache$winner_manifest_sha256,
  design_cache = normalizePath(cache_path, mustWork = TRUE),
  design_cache_sha256 = cache_sha256,
  reference_design_hash = as.character(design$design_hash[["reference_full"]]),
  discrepancy_design_hash = as.character(design$design_hash[["discrepancy_full"]]),
  stacked_design_hash = as.character(design$design_hash[["part3_stacked_full"]]),
  n_dates = design$n_dates,
  p_reference = design$p_beta,
  p_discrepancy = design$p_alpha,
  train_end = as.character(origin$origin_date),
  forecast_start = as.character(min(origin$future_dates)),
  forecast_end = as.character(max(origin$future_dates)),
  horizon_days = horizon_days,
  sign_gap = max(abs(design$y_reference + design$d_g - design$g_retrospective)),
  normal_prerequisites = nrow(normal_inventory),
  status = "ready_for_part3_quantile_forecast_chain",
  stringsAsFactors = FALSE
)
certificate_path <- app_write_csv(certificate, file.path(runtime_root, "configs", "part3_preflight_certificate.csv"))
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), file.path(runtime_root, "status", "part3_quantile_forecast_preflight.completed"))
cat(sprintf("design_cache=%s\n", cache_path))
cat(sprintf("design_cache_sha256=%s\n", cache_sha256))
cat(sprintf("certificate=%s\n", certificate_path))
