#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R", "build_qdesn_features.R",
  "latent_path_design.R", "discrepancy_design.R", "forecast_contract.R",
  "fit_qdesn_discrepancy.R", "latent_path_runtime_backend.R", "latent_path_checkpoint.R",
  "latent_path_vb_al.R", "latent_path_vb_normal.R", "joint_qvp_qdesn.R",
  "joint_exqdesn_exact_structured_inference.R", "latent_path_vb_exal.R",
  "glofas_normal_desn_part1_screening.R", "glofas_part3_partitioned_rhs.R",
  "latent_path_vb_joint.R", "fit_qdesn_latent_path.R",
  "glofas_part4_ensemble_likelihood_contract.R", "glofas_part4_latent_family.R",
  "glofas_part4_exal_inner_audit.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  source_runtime_root = "local_trackers/runtime_configs/glofas_part4_search3_dependency_closure_20260930_r4",
  probe_runtime_root = "local_trackers/runtime_configs/glofas_part4_exal_inner_probe_r1_20261006",
  output_runtime_root = "local_trackers/runtime_configs/glofas_part4_exal_quadrature_certificate_r1_20261007",
  source_job_id = "glofas_part4_search3_dependency_closure_20260930_r4_joint_exal_rhs_vb",
  probe_fit_name = "extended_full_state_p50_fit_compact.rds",
  expected_probe_fit_sha256 = "9b25695afde6f337ea2a39170aec70a7369e5541368597bbbdf5a5dd403050e0",
  expected_design_sha256 = "a2fbcec6523802f01c98ec272253e58a598a5adc5c7b0f9063b615b36c07bcf9",
  candidate_nodes = "4,8,12,16,24",
  reference_nodes = "16,24,32,48",
  tolerance = 1.0e-6,
  reference_tolerance = 1.0e-8
))

parse_nodes <- function(value, label) {
  nodes <- as.integer(strsplit(as.character(value)[[1L]], ",", fixed = TRUE)[[1L]])
  if (!length(nodes) || anyNA(nodes) || any(nodes < 2L) || any(diff(nodes) <= 0L)) {
    stop(sprintf("%s must be a strictly increasing comma-separated integer grid.", label), call. = FALSE)
  }
  nodes
}

verify_hash <- function(path, expected, label) {
  path <- normalizePath(path, mustWork = TRUE)
  expected <- tolower(trimws(as.character(expected)[[1L]]))
  observed <- tolower(app_sha256_file(path))
  if (!grepl("^[0-9a-f]{64}$", expected) || !identical(observed, expected)) {
    stop(sprintf("%s SHA256 mismatch: expected %s, observed %s.", label, expected, observed), call. = FALSE)
  }
  observed
}

source_root <- app_resolve_path(args$source_runtime_root, must_work = TRUE)
probe_root <- app_resolve_path(args$probe_runtime_root, must_work = TRUE)
output_root <- app_resolve_path(args$output_runtime_root, must_work = FALSE)
if (dir.exists(output_root) && length(list.files(output_root, all.files = TRUE, no.. = TRUE))) {
  stop(sprintf("Quadrature certificate output root is non-empty: %s", output_root), call. = FALSE)
}
invisible(lapply(file.path(output_root, c("tables", "manifests", "reports", "status")), app_ensure_dir))

probe_decision_path <- file.path(probe_root, "status", "probe.completed")
probe_contract_path <- file.path(probe_root, "manifests", "probe_contract.csv")
probe_gate_path <- file.path(probe_root, "tables", "final_probe_gate.csv")
probe_fit_path <- file.path(probe_root, "objects", as.character(args$probe_fit_name)[[1L]])
for (path in c(probe_decision_path, probe_contract_path, probe_gate_path, probe_fit_path)) {
  if (!file.exists(path)) stop(sprintf("Missing required probe artifact: %s", path), call. = FALSE)
}
probe_decision <- trimws(readLines(probe_decision_path, warn = FALSE)[[1L]])
if (!identical(probe_decision, "QUADRATURE_CERTIFICATE_REQUIRES_NUMERICAL_REFINEMENT")) {
  stop(sprintf("Unexpected probe decision: %s", probe_decision), call. = FALSE)
}
probe_gate <- app_read_csv(probe_gate_path)
median_gate <- probe_gate[abs(as.numeric(probe_gate$quantile_level) - 0.5) < 1.0e-12, , drop = FALSE]
if (nrow(median_gate) != 1L || !isTRUE(median_gate$parameter_pass[[1L]]) ||
    isTRUE(median_gate$quadrature_pass[[1L]]) || !identical(as.character(median_gate$blocker[[1L]]), "quadrature")) {
  stop("The frozen probe does not contain the expected parameter-stable median quadrature blocker.", call. = FALSE)
}

fit_sha <- verify_hash(probe_fit_path, args$expected_probe_fit_sha256, "probe median fit")
design_path <- file.path(source_root, "objects", "part4_shared_design_truth_free.rds")
design_sha <- verify_hash(design_path, args$expected_design_sha256, "truth-free design")
manifest_path <- file.path(source_root, "configs", "part4_model_manifest.csv")
manifest <- app_read_csv(manifest_path)
source_job <- as.character(args$source_job_id)[[1L]]
job <- manifest[manifest$run_id == source_job, , drop = FALSE]
if (nrow(job) != 1L || !identical(as.character(job$part4_family[[1L]]), "joint_exal_rhs_vb")) {
  stop("The source manifest does not contain the requested joint exAL model.", call. = FALSE)
}
cfg_path <- app_resolve_path(job$config_path[[1L]], must_work = TRUE)
grid_path <- app_resolve_path(job$model_grid_path[[1L]], must_work = TRUE)
cfg <- app_read_config(cfg_path)
grid <- app_validate_model_grid(grid_path, app_config_path(cfg, "schema"))
model_rows <- grid[grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
model_rows <- model_rows[order(as.numeric(model_rows$quantile_level)), , drop = FALSE]
if (!identical(as.numeric(model_rows$quantile_level), c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95))) {
  stop("The quadrature certificate requires the frozen seven-quantile grid.", call. = FALSE)
}

candidate_nodes <- parse_nodes(args$candidate_nodes, "candidate_nodes")
reference_nodes <- parse_nodes(args$reference_nodes, "reference_nodes")
tolerance <- as.numeric(args$tolerance)
reference_tolerance <- as.numeric(args$reference_tolerance)
if (!is.finite(tolerance) || tolerance <= 0 || !is.finite(reference_tolerance) ||
    reference_tolerance <= 0 || reference_tolerance >= tolerance) {
  stop("Quadrature tolerances must satisfy 0 < reference_tolerance < tolerance.", call. = FALSE)
}

design <- readRDS(design_path)
fit <- readRDS(probe_fit_path)
app_validate_glofas_latent_path_design(design)
if (!identical(design$future_truth_policy, "physically_excluded_from_fit_objects_scoring_sidecar_only") ||
    !identical(fit$vb_diagnostics$future_truth_policy, design$future_truth_policy) ||
    !isTRUE(fit$vb_diagnostics$future_y_working_likelihood_used)) {
  stop("The fixed-state certificate requires the truth-free Part 4 likelihood contract.", call. = FALSE)
}

required_summary <- c("theta_mean", "theta_cov", "y_future_mean", "y_future_cov")
required_state <- c("latent_mean", "latent_inv_mean", "s_mean", "s2_mean")
if (!all(required_summary %in% names(fit$summary)) || !all(required_state %in% names(fit$variational_state))) {
  stop("The retained median fit lacks the terminal moments required for certification.", call. = FALSE)
}
row_moments <- app_latent_row_moments(
  design,
  as.numeric(fit$summary$y_future_mean), as.matrix(fit$summary$y_future_cov),
  as.numeric(fit$summary$theta_mean), as.matrix(fit$summary$theta_cov)
)
row_moments <- app_latent_apply_future_y_weight_policy(row_moments, include = TRUE)
source <- app_latent_all_source(row_moments)
residual <- app_latent_all_e(row_moments)
residual_second <- app_latent_all_R(row_moments)
weight <- app_latent_all_weight(row_moments)
n_rows <- length(residual)
state <- fit$variational_state
if (length(source) != n_rows || length(residual_second) != n_rows || length(weight) != n_rows ||
    any(vapply(required_state, function(name) length(state[[name]]) != n_rows, logical(1L)))) {
  stop("The fixed row moments and retained local exAL state are not aligned.", call. = FALSE)
}

vb_args <- app_make_qdesn_discrepancy_vb_args(
  cfg,
  prior = app_map_qdesn_prior(model_rows$coefficient_prior[[1L]]),
  seed = as.integer(model_rows$reservoir_seed[[1L]]),
  likelihood_family = "exal"
)
prior_sigma <- vb_args$prior_sigma %||% list()
run_rule <- function(nodes, rule_tolerance) {
  out <- list()
  for (src in c("Y", "G")) {
    idx <- which(source == src & weight > 0)
    if (!length(idx)) stop(sprintf("No active '%s' likelihood rows.", src), call. = FALSE)
    out[[src]] <- app_joint_exqdesn_structured_scale_shape_update(
      tau = 0.5,
      augmentation = "v",
      r_mean = residual[idx], r2_mean = residual_second[idx],
      latent_mean = state$latent_mean[idx], latent_inv_mean = state$latent_inv_mean[idx],
      s_mean = state$s_mean[idx], s2_mean = state$s2_mean[idx],
      a_sigma = as.numeric(prior_sigma$a %||% 2),
      b_sigma = as.numeric(prior_sigma$b %||% 1),
      observation_weight = weight[idx],
      quadrature_nodes = nodes,
      quadrature_tolerance = rule_tolerance
    )
  }
  out
}

started <- Sys.time()
candidate <- run_rule(candidate_nodes, tolerance)
reference <- run_rule(reference_nodes, reference_tolerance)
elapsed_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
certificate <- app_glofas_part4_exal_quadrature_certificate(
  candidate, reference, tolerance = tolerance, reference_tolerance = reference_tolerance
)
component_comparison <- app_glofas_part4_exal_quadrature_component_table(candidate, reference)
decision <- if (all(certificate$passed)) {
  "READY_FOR_TARGETED_JOINT_EXAL_CORRECTION"
} else {
  "QUADRATURE_REFINEMENT_REQUIRES_FURTHER_WORK"
}

diagnostics <- do.call(rbind, c(
  lapply(c("Y", "G"), function(src) transform(candidate[[src]]$diagnostics, rule = "candidate", source = src)),
  lapply(c("Y", "G"), function(src) transform(reference[[src]]$diagnostics, rule = "reference", source = src))
))
app_write_csv(diagnostics, file.path(output_root, "tables", "quadrature_diagnostics.csv"))
app_write_csv(certificate, file.path(output_root, "tables", "quadrature_certificate.csv"))
app_write_csv(component_comparison, file.path(output_root, "tables", "quadrature_component_comparison.csv"))

contract <- data.frame(
  decision = decision,
  source_job_id = source_job,
  probe_decision = probe_decision,
  probe_fit_sha256 = fit_sha,
  design_sha256 = design_sha,
  probe_gate_sha256 = app_sha256_file(probe_gate_path),
  probe_contract_sha256 = app_sha256_file(probe_contract_path),
  source_manifest_sha256 = app_sha256_file(manifest_path),
  config_sha256 = app_sha256_file(cfg_path),
  model_grid_sha256 = app_sha256_file(grid_path),
  code_head = trimws(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE)),
  exact_exal_core_sha256 = app_sha256_file(app_path("application/R/joint_exqdesn_exact_structured_inference.R")),
  latent_exal_core_sha256 = app_sha256_file(app_path("application/R/latent_path_vb_exal.R")),
  audit_module_sha256 = app_sha256_file(app_path("application/R/glofas_part4_exal_inner_audit.R")),
  certificate_worker_sha256 = app_sha256_file(app_path("application/scripts/443_certify_glofas_part4_exal_quadrature.R")),
  candidate_nodes = paste(candidate_nodes, collapse = ","),
  reference_nodes = paste(reference_nodes, collapse = ","),
  tolerance = tolerance,
  reference_tolerance = reference_tolerance,
  elapsed_seconds = elapsed_seconds,
  future_truth_policy = design$future_truth_policy,
  stringsAsFactors = FALSE
)
app_write_csv(contract, file.path(output_root, "manifests", "quadrature_contract.csv"))

report <- c(
  "# Part 4 Joint exAL Fixed-State Quadrature Certificate",
  "",
  sprintf("Generated: %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "",
  sprintf("Decision: `%s`", decision),
  "",
  sprintf("Candidate nodes: `%s`", paste(candidate_nodes, collapse = ",")),
  sprintf("Reference nodes: `%s`", paste(reference_nodes, collapse = ",")),
  sprintf("Candidate tolerance: `%.3g`", tolerance),
  sprintf("Reference tolerance: `%.3g`", reference_tolerance),
  "",
  "The certificate holds the parameter and latent state fixed, reconstructs the truth-free row moments,",
  "and changes only deterministic numerical quadrature resolution. It is not a model fit and uses no scoring truth."
)
writeLines(report, file.path(output_root, "reports", "quadrature_findings.md"), useBytes = TRUE)

files <- list.files(output_root, recursive = TRUE, full.names = TRUE)
files <- files[file.info(files)$isdir %in% FALSE]
manifest_out <- data.frame(
  relative_path = substring(files, nchar(normalizePath(output_root, mustWork = TRUE)) + 2L),
  size_bytes = as.numeric(file.info(files)$size),
  sha256 = vapply(files, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
app_write_csv(manifest_out, file.path(output_root, "manifests", "quadrature_output_manifest.csv"))
writeLines(decision, file.path(output_root, "status", "certificate.completed"))
cat(sprintf("decision=%s\nelapsed_seconds=%.3f\n", decision, elapsed_seconds))
print(certificate, row.names = FALSE)
