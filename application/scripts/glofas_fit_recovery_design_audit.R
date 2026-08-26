#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/glofas_discrepancy_transition.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/fit_qdesn_reference.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/latent_path_runtime_backend.R"))
source(app_path("application/R/latent_path_checkpoint.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))
source(app_path("application/R/glofas_fit_recovery.R"))

args <- app_parse_args(list(
  config = "",
  expected_design_hash = "",
  expected_n_block_features = "",
  output_dir = "local_trackers/runtime_configs/glofas_fit_recovery_20260730/design_audit"
))
if (!nzchar(args$config)) stop("--config is required.", call. = FALSE)
resolve_repo <- function(path) if (grepl("^/", path)) path else app_path(path)
cfg <- app_read_config(resolve_repo(args$config))
panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
if (!file.exists(panel_path)) stop(sprintf("Shared panel is missing: %s.", panel_path), call. = FALSE)
panel <- readRDS(panel_path)
model_grid <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
model_row <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
if (nrow(model_row) != 1L) stop("Expected one Q-DESN model row.", call. = FALSE)
app_check_qdesn_engine_api(cfg, require_discrepancy = FALSE, stop_on_failure = TRUE)
design <- app_make_glofas_latent_path_design(panel, cfg, model_row)
summary <- app_latent_path_design_summary(design)
expected_n <- as.integer(args$expected_n_block_features)
expected <- list(
  design_hash = args$expected_design_hash,
  n_beta_features = expected_n,
  n_alpha_features = expected_n,
  n_beta_reservoir_features = 300L,
  n_alpha_reservoir_features = 300L,
  reference_reservoir_seed = 20260512L,
  discrepancy_reservoir_seed = 20261521L,
  discrepancy_reservoir_seed_offset = 1009L,
  two_block_design = TRUE,
  feature_contract_version = "latent_path_v0.3",
  design_version = "latent_path_two_block_v0.3"
)
if (!nzchar(args$expected_design_hash)) expected$design_hash <- summary$design_hash[[1L]]
audit <- app_glofas_fit_recovery_contract_audit(summary, expected)
output_dir <- resolve_repo(args$output_dir)
app_ensure_dir(output_dir)
app_write_csv(summary, file.path(output_dir, "design_summary.csv"))
app_write_csv(audit, file.path(output_dir, "design_contract_audit.csv"))
app_write_csv(
  data.frame(
    block = c(rep("reference", nrow(design$feature_info_beta)), rep("discrepancy", nrow(design$feature_info_alpha))),
    rbind(design$feature_info_beta, design$feature_info_alpha),
    stringsAsFactors = FALSE
  ),
  file.path(output_dir, "design_feature_ledger.csv")
)
if (!all(audit$equal)) {
  stop("Historical design parity gate failed; see design_contract_audit.csv.", call. = FALSE)
}
cat(file.path(output_dir, "design_contract_audit.csv"), "\n")
