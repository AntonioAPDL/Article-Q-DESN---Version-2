#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "launch_control.R", "artifact_hygiene.R", "engine_contract.R",
  "model_contract.R", "feature_contract.R", "covariate_design.R", "build_qdesn_features.R",
  "latent_path_design.R", "discrepancy_design.R", "forecast_contract.R",
  "latent_path_runtime_backend.R", "latent_path_checkpoint.R", "latent_path_vb_al.R",
  "fit_qdesn_latent_path.R"
)) source(app_path("application", "R", file))

args <- app_parse_args(list(config = NULL, output = NULL))
if (is.null(args$config) || is.null(args$output)) {
  stop("Usage: glofas_shared_input_p50_validate.R --config CONFIG --output OUTPUT_DIR", call. = FALSE)
}
config_path <- normalizePath(args$config, mustWork = TRUE)
output <- normalizePath(args$output, mustWork = FALSE)
app_ensure_dir(output)
cfg <- app_read_config(config_path)
app_validate_application_model_contract(cfg)
app_qdesn_validate_block_configs(cfg)

model_grid <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
qrows <- model_grid$model_family == "qdesn_glofas_discrepancy" & app_as_bool_vec(model_grid$enabled)
if (sum(qrows) != 1L || abs(as.numeric(model_grid$quantile_level[qrows]) - 0.5) > 1e-12) {
  stop("Validation requires exactly one enabled p50 Q-DESN candidate.", call. = FALSE)
}
model_row <- model_grid[qrows, , drop = FALSE]
panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
if (!file.exists(panel_path)) stop(sprintf("Missing application panel: %s.", panel_path), call. = FALSE)
panel <- readRDS(panel_path)

reference_cfg <- app_qdesn_block_config(cfg, "reference")
discrepancy_cfg <- app_qdesn_block_config(cfg, "discrepancy")
reference_contract <- app_feature_contract(reference_cfg)
discrepancy_contract <- app_feature_contract(discrepancy_cfg)
if (!identical(app_qdesn_block_input_stream(cfg, "reference"), "reference") ||
    !identical(app_qdesn_block_input_stream(cfg, "discrepancy"), "reference")) {
  stop("Both reservoirs must consume the reference input stream.", call. = FALSE)
}
if (!isTRUE(reference_contract$readout$include_input_block) ||
    isTRUE(discrepancy_contract$readout$include_input_block)) {
  stop("Exactly the reference readout must contain the common direct input block.", call. = FALSE)
}

design <- app_make_glofas_latent_path_design(panel, cfg, model_row)
probe <- app_latent_path_future_probe(design)
summary <- app_latent_path_design_summary(design, probe = probe)
expected <- c(
  n_beta_features = 843L,
  n_alpha_features = 301L,
  n_augmented_features = 1144L,
  n_beta_reservoir_features = 300L,
  n_alpha_reservoir_features = 300L,
  n_beta_direct_output_lag_features = 180L,
  n_alpha_direct_output_lag_features = 0L,
  n_beta_direct_covariate_lag_features = 362L,
  n_alpha_direct_covariate_lag_features = 0L
)
for (field in names(expected)) {
  observed <- as.integer(summary[[field]][[1L]])
  if (!identical(observed, expected[[field]])) {
    stop(sprintf("%s must equal %d; observed %d.", field, expected[[field]], observed), call. = FALSE)
  }
}
if (!identical(design$discrepancy_input_stream, "reference") ||
    !identical(probe$discrepancy_input_stream, "reference") ||
    !identical(design$design_version, "latent_path_two_block_shared_reference_input_v0.1")) {
  stop("The materialized design does not declare the shared reference input contract.", call. = FALSE)
}
if (!identical(as.integer(app_discrepancy_block_seed(model_row, cfg, "reference")), 20260512L) ||
    !identical(as.integer(app_discrepancy_block_seed(model_row, cfg, "discrepancy")), 20261521L)) {
  stop("The separate reservoir seeds do not match the frozen candidate contract.", call. = FALSE)
}
if (isTRUE(all.equal(design$X_core_beta, design$X_core_alpha, tolerance = 0))) {
  stop("Separate reservoir seeds unexpectedly produced identical reservoir states.", call. = FALSE)
}

beta_meta <- design$future_context$qfit_beta$meta
alpha_meta <- design$future_context$qfit_alpha$meta
for (field in c("reservoir_input_columns", "lag_center", "lag_scale")) {
  if (!isTRUE(all.equal(beta_meta[[field]], alpha_meta[[field]], tolerance = 1e-12, check.attributes = FALSE))) {
    stop(sprintf("Reference and discrepancy reservoirs do not share the same %s contract.", field), call. = FALSE)
  }
}

epsilon <- 1e-6
y0 <- as.numeric(design$y_future_init)
y1 <- y0
y1[[1L]] <- y1[[1L]] + epsilon
probe1 <- design$future_builder(y1)
finite_difference <- (probe1$H_g_key - probe$H_g_key) / epsilon
analytic <- do.call(rbind, lapply(probe$J_g_key, function(J) as.numeric(J[, 1L])))
max_abs_error <- max(abs(finite_difference - analytic))
alpha_columns <- design$alpha_index
max_alpha_sensitivity <- max(abs(analytic[, alpha_columns, drop = FALSE]))
if (!is.finite(max_abs_error) || max_abs_error > 2e-5) {
  stop(sprintf("Shared-input future Jacobian finite-difference error is %.6g.", max_abs_error), call. = FALSE)
}
if (!is.finite(max_alpha_sensitivity) || max_alpha_sensitivity <= 1e-10) {
  stop("The discrepancy reservoir is not sensitive to the latent future reference path.", call. = FALSE)
}

summary$config_path <- config_path
summary$config_sha256 <- app_sha256_file(config_path)
summary$reference_input_stream <- app_qdesn_block_input_stream(cfg, "reference")
summary$discrepancy_input_stream <- app_qdesn_block_input_stream(cfg, "discrepancy")
summary$reference_direct_input_block <- reference_contract$readout$include_input_block
summary$discrepancy_direct_input_block <- discrepancy_contract$readout$include_input_block
summary$reference_seed <- app_discrepancy_block_seed(model_row, cfg, "reference")
summary$discrepancy_seed <- app_discrepancy_block_seed(model_row, cfg, "discrepancy")
app_write_csv(summary, file.path(output, "shared_input_design_audit.csv"))
app_write_csv(data.frame(
  perturbation_index = 1L,
  epsilon = epsilon,
  max_abs_error = max_abs_error,
  max_alpha_sensitivity = max_alpha_sensitivity,
  passed = TRUE,
  stringsAsFactors = FALSE
), file.path(output, "shared_input_future_jacobian_audit.csv"))
writeLines(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), file.path(output, ".preflight_complete"))
cat(normalizePath(output, mustWork = TRUE), "\n")
