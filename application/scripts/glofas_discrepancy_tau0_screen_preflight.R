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
  "fit_qdesn_discrepancy.R", "fit_qdesn_latent_path.R", "glofas_discrepancy_tau0_screen.R"
)) source(app_path("application", "R", file))

args <- app_parse_args(list(
  manifest = "local_trackers/runtime_configs/glofas_discrepancy_tau0_relax_p50_20260831/candidate_registry.csv",
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_tau0_relax_p50_20260831"
))
resolve_path <- function(path, must_work = TRUE) {
  normalizePath(if (grepl("^/", path)) path else file.path(repo_root, path), mustWork = must_work)
}

manifest_path <- resolve_path(as.character(args$manifest), must_work = TRUE)
output_root <- resolve_path(as.character(args$output_root), must_work = TRUE)
preflight_root <- file.path(output_root, "preflight")
app_ensure_dir(preflight_root)
manifest <- app_read_csv(manifest_path)
required_manifest <- c(
  "candidate_id", "candidate_role", "discrepancy_tau0", "reference_tau0",
  "warm_start_enabled", "config_path", "config_sha256", "model_grid_path",
  "model_grid_sha256", "run_id", "run_dir", "log_path",
  "warm_start_source_fit_object", "warm_start_source_sha256"
)
missing <- setdiff(required_manifest, names(manifest))
if (length(missing) || nrow(manifest) != 5L) {
  stop(sprintf("Campaign manifest is invalid or missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
}
if (!identical(sort(unique(as.numeric(manifest$discrepancy_tau0))), c(0.3, 1, 3, 10))) {
  stop("Campaign discrepancy tau0 support is not exactly 0.3, 1, 3, 10.", call. = FALSE)
}
if (sum(!app_as_bool_vec(manifest$warm_start_enabled)) != 1L ||
    sum(as.character(manifest$candidate_role) == "cold_canary") != 1L) {
  stop("Campaign must contain four warm fits and one cold canary.", call. = FALSE)
}

base_config_path <- file.path(output_root, "source", "campaign_base_config.yaml")
base_cfg <- app_read_config(base_config_path)
config_audit <- vector("list", nrow(manifest))
configs <- vector("list", nrow(manifest))
grids <- vector("list", nrow(manifest))
for (i in seq_len(nrow(manifest))) {
  config_path <- normalizePath(manifest$config_path[[i]], mustWork = TRUE)
  grid_path <- normalizePath(manifest$model_grid_path[[i]], mustWork = TRUE)
  if (!identical(app_sha256_file(config_path), as.character(manifest$config_sha256[[i]])) ||
      !identical(app_sha256_file(grid_path), as.character(manifest$model_grid_sha256[[i]]))) {
    stop(sprintf("Prepared hashes changed for %s.", manifest$candidate_id[[i]]), call. = FALSE)
  }
  cfg <- app_read_config(config_path)
  app_validate_application_model_contract(cfg)
  app_qdesn_validate_block_configs(cfg)
  warm <- app_as_bool(manifest$warm_start_enabled[[i]])
  app_glofas_discrepancy_tau0_assert_one_axis(
    base_cfg, cfg, as.numeric(manifest$discrepancy_tau0[[i]]), 400L, warm
  )
  grid <- app_validate_model_grid(grid_path, app_config_path(cfg, "schema"))
  qrow <- grid$model_family == "qdesn_glofas_discrepancy" & app_as_bool_vec(grid$enabled)
  if (sum(qrow) != 1L || abs(as.numeric(grid$quantile_level[qrow]) - 0.5) > 1.0e-12) {
    stop(sprintf("%s does not contain exactly one enabled p50 Q-DESN.", manifest$candidate_id[[i]]), call. = FALSE)
  }
  configs[[i]] <- cfg
  grids[[i]] <- grid[qrow, , drop = FALSE]
  config_audit[[i]] <- data.frame(
    candidate_id = manifest$candidate_id[[i]],
    discrepancy_tau0 = as.numeric(cfg$inference$vb_ld$rhs_alpha_tau0),
    reference_tau0 = as.numeric(cfg$inference$vb_ld$rhs_tau0),
    max_iter = as.integer(cfg$inference$vb_ld$max_iter),
    max_iter_hard_cap = as.integer(cfg$inference$vb_ld$max_iter_hard_cap),
    warm_start_enabled = app_as_bool(cfg$inference$vb_ld$warm_start$enabled),
    checkpoint_enabled = app_as_bool(cfg$inference$vb_ld$checkpoint$enabled),
    one_axis_contract_passed = TRUE,
    stringsAsFactors = FALSE
  )
}
config_audit <- do.call(rbind, config_audit)

panel_path <- file.path(output_root, "common_cache", "application_panel.rds")
panel <- readRDS(panel_path)
design <- app_make_glofas_latent_path_design(panel, configs[[1L]], grids[[1L]])
design_summary <- app_latent_path_design_summary(design)
target_contract <- app_latent_path_warm_start_contract(
  design, design_hash = design_summary$design_hash[[1L]]
)
warm_rows <- which(app_as_bool_vec(manifest$warm_start_enabled))
source_fit_paths <- unique(as.character(manifest$warm_start_source_fit_object[warm_rows]))
source_fit_hashes <- unique(as.character(manifest$warm_start_source_sha256[warm_rows]))
if (length(source_fit_paths) != 1L || length(source_fit_hashes) != 1L ||
    !file.exists(source_fit_paths) || !identical(app_sha256_file(source_fit_paths), source_fit_hashes)) {
  stop("Warm candidates do not share one verified immutable source fit.", call. = FALSE)
}
source <- app_latent_path_warm_start_fit(source_fit_paths)
source_contract <- app_latent_path_warm_start_contract_from_fit(source_fit_paths)
compatibility <- app_latent_path_warm_start_compatibility(
  source_contract, target_contract, mode = "exact_design"
)
if (!isTRUE(compatibility$accepted) || !identical(compatibility$class, "exact_design")) {
  stop(sprintf("Exact-design warm start was rejected: %s.", compatibility$message), call. = FALSE)
}
theta_mean <- source$fit$variational_state$theta_mean %||% source$fit$summary$theta_mean
theta_cov <- source$fit$variational_state$theta_cov %||% source$fit$summary$theta_cov
if (is.null(theta_mean) || is.null(theta_cov) || length(theta_mean) != ncol(design$H_fixed)) {
  stop("Source coefficient state is unavailable or dimension-mismatched.", call. = FALSE)
}

warm_audit <- lapply(warm_rows, function(i) {
  vb_args <- app_make_qdesn_discrepancy_vb_args(
    configs[[i]], prior = "rhs_ns", seed = as.integer(configs[[i]]$reservoir$seed), likelihood_family = "al"
  )
  prepared <- app_latent_path_warm_start_prepare(
    design, vb_args, p = ncol(design$H_fixed), H_future = nrow(design$future_key)
  )
  diag <- prepared$diagnostics
  data.frame(
    candidate_id = manifest$candidate_id[[i]],
    source_sha256 = diag$source_sha256,
    compatibility_mode = diag$compatibility_mode,
    compatibility_class = diag$compatibility_class,
    theta_used = isTRUE(diag$theta_used),
    future_used = isTRUE(diag$future_used),
    sigma_used = isTRUE(diag$sigma_used),
    accepted = isTRUE(diag$used) && isTRUE(diag$theta_used) && isTRUE(diag$future_used),
    message = diag$message,
    stringsAsFactors = FALSE
  )
})
warm_audit <- do.call(rbind, warm_audit)
if (!all(warm_audit$accepted)) stop("At least one strict warm initialization failed.", call. = FALSE)

prior_reset <- do.call(rbind, lapply(seq_len(nrow(manifest)), function(i) {
  out <- app_glofas_discrepancy_tau0_prior_reset_summary(design, configs[[i]], theta_mean, theta_cov)
  out$candidate_id <- manifest$candidate_id[[i]]
  out$warm_start_enabled <- app_as_bool(manifest$warm_start_enabled[[i]])
  out[, c("candidate_id", "warm_start_enabled", setdiff(names(out), c("candidate_id", "warm_start_enabled")))]
}))
if (!all(prior_reset$prior_reset_passed)) {
  stop("Candidate prior-state reset audit failed.", call. = FALSE)
}

design_audit <- data.frame(
  source_design_hash = as.character(source_contract$design_hash),
  target_design_hash = as.character(target_contract$design_hash),
  exact_design = identical(as.character(source_contract$design_hash), as.character(target_contract$design_hash)),
  source_quantile = as.numeric(source_contract$quantile_level),
  target_quantile = as.numeric(target_contract$quantile_level),
  source_n_theta = as.integer(source_contract$n_theta),
  target_n_theta = as.integer(target_contract$n_theta),
  source_n_future = as.integer(source_contract$n_future),
  target_n_future = as.integer(target_contract$n_future),
  compatibility_class = compatibility$class,
  compatibility_message = compatibility$message,
  stringsAsFactors = FALSE
)
if (!isTRUE(design_audit$exact_design[[1L]])) stop("Source and target design hashes differ.", call. = FALSE)

paths <- c(
  candidate_config_audit = file.path(preflight_root, "candidate_config_audit.csv"),
  exact_design_audit = file.path(preflight_root, "exact_design_audit.csv"),
  warm_start_audit = file.path(preflight_root, "warm_start_audit.csv"),
  prior_reset_audit = file.path(preflight_root, "prior_reset_audit.csv"),
  design_summary = file.path(preflight_root, "design_summary.csv")
)
app_write_csv(config_audit, paths[["candidate_config_audit"]])
app_write_csv(design_audit, paths[["exact_design_audit"]])
app_write_csv(warm_audit, paths[["warm_start_audit"]])
app_write_csv(prior_reset, paths[["prior_reset_audit"]])
app_write_csv(design_summary, paths[["design_summary"]])
artifact_manifest <- data.frame(
  role = c(names(paths), "candidate_registry", "source_fit", "application_panel"),
  path = c(unname(paths), manifest_path, source_fit_paths, panel_path),
  size_bytes = as.numeric(file.info(c(unname(paths), manifest_path, source_fit_paths, panel_path))$size),
  sha256 = vapply(c(unname(paths), manifest_path, source_fit_paths, panel_path), app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(artifact_manifest, file.path(preflight_root, "artifact_manifest.csv"))
writeLines(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), file.path(preflight_root, ".preflight_complete"))
cat(normalizePath(preflight_root, mustWork = TRUE), "\n")
