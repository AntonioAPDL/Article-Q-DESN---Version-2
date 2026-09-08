#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- sub("^--file=", "", script_arg[[1L]])
repo_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
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
  "glofas_part4_ensemble_likelihood_contract.R", "glofas_part4_latent_family.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  source_runtime_root = "",
  output_runtime_root = "",
  source_job_id = "",
  output_job_id = "",
  likelihood = "",
  expected_source_fit_sha256 = "",
  expected_design_sha256 = "",
  expected_scoring_sidecar_sha256 = "",
  additional_outer_max_iter = 5L,
  inner_max_iter = 30L,
  inner_min_iter = 10L,
  outer_tol = 1.0e-3,
  n_draws = 500L
))

source_root <- app_resolve_path(args$source_runtime_root, must_work = TRUE)
output_root <- app_resolve_path(args$output_runtime_root, must_work = FALSE)
source_job_id <- trimws(as.character(args$source_job_id)[[1L]])
output_job_id <- trimws(as.character(args$output_job_id)[[1L]])
likelihood <- match.arg(tolower(trimws(as.character(args$likelihood)[[1L]])), c("al", "exal"))
if (!nzchar(source_job_id) || !nzchar(output_job_id)) {
  stop("--source_job_id and --output_job_id are required.", call. = FALSE)
}

verify_hash <- function(path, expected, label) {
  path <- normalizePath(path, mustWork = TRUE)
  expected <- tolower(trimws(as.character(expected)[[1L]]))
  if (!grepl("^[0-9a-f]{64}$", expected)) {
    stop(sprintf("%s requires an explicit SHA256 digest.", label), call. = FALSE)
  }
  observed <- tolower(app_sha256_file(path))
  if (!identical(observed, expected)) {
    stop(sprintf("%s SHA256 mismatch: expected %s, observed %s.", label, expected, observed), call. = FALSE)
  }
  observed
}

for (sub in c("objects", "predictions", "scores", "traces", "coefficients", "logs", "status", "manifests")) {
  app_ensure_dir(file.path(output_root, sub))
}
running <- file.path(output_root, "status", paste0(output_job_id, ".running"))
completed <- file.path(output_root, "status", paste0(output_job_id, ".completed"))
failed <- file.path(output_root, "status", paste0(output_job_id, ".failed"))
if (file.exists(completed)) stop(sprintf("Continuation already completed: %s.", output_job_id), call. = FALSE)
writeLines(c(
  sprintf("job_id=%s", output_job_id),
  sprintf("pid=%d", Sys.getpid()),
  sprintf("started_at=%s", format(Sys.time(), tz = "UTC", usetz = TRUE))
), running)

run_continuation <- function() {
  source_manifest_path <- file.path(source_root, "configs", "part4_model_manifest.csv")
  source_manifest <- app_read_csv(source_manifest_path)
  source_job <- source_manifest[source_manifest$run_id == source_job_id, , drop = FALSE]
  if (nrow(source_job) != 1L) stop("The source Part 4 manifest must contain exactly one requested joint job.", call. = FALSE)
  expected_family <- paste0("joint_", likelihood, "_rhs_vb")
  if (!identical(as.character(source_job$part4_family[[1L]]), expected_family)) {
    stop("The source job family does not match the requested continuation likelihood.", call. = FALSE)
  }

  source_fit_path <- file.path(source_root, "objects", paste0(source_job_id, "_fit_side.rds"))
  design_path <- file.path(source_root, "objects", "part4_shared_design_truth_free.rds")
  sidecar_path <- file.path(source_root, "objects", "part4_scoring_panel_sidecar.rds")
  source_fit_sha <- verify_hash(source_fit_path, args$expected_source_fit_sha256, "source joint fit")
  design_sha <- verify_hash(design_path, args$expected_design_sha256, "source truth-free design")
  sidecar_sha <- verify_hash(sidecar_path, args$expected_scoring_sidecar_sha256, "source scoring sidecar")

  cfg_path <- app_resolve_path(source_job$config_path[[1L]], must_work = TRUE)
  model_grid_path <- app_resolve_path(source_job$model_grid_path[[1L]], must_work = TRUE)
  cfg <- app_read_config(cfg_path)
  model_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
  model_rows <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  model_rows <- model_rows[order(as.numeric(model_rows$quantile_level)), , drop = FALSE]
  if (!identical(as.numeric(model_rows$quantile_level), c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95))) {
    stop("The continuation requires the frozen seven-quantile Part 4 grid.", call. = FALSE)
  }

  fixed_audit <- app_read_csv(file.path(source_root, "manifests", "part4_fixed_window_audit.csv"))
  required_audit <- c(
    origin = "2022-12-25", train_end = "2022-12-25",
    eval_start = "2022-12-26", eval_end = "2023-01-24",
    requested_horizon = "30", issued_horizons = "1:28",
    issued_dates = "2022-12-26:2023-01-22", member_count = "51:51",
    scoring_truth_available = "28/28"
  )
  observed_audit <- setNames(as.character(fixed_audit$detail), as.character(fixed_audit$check))
  if (!all(names(required_audit) %in% names(observed_audit)) ||
      !identical(unname(observed_audit[names(required_audit)]), unname(required_audit)) ||
      any(fixed_audit$status[match(names(required_audit), fixed_audit$check)] != "pass")) {
    stop("The source runtime does not satisfy the frozen Dec. 25 Part 4 window contract.", call. = FALSE)
  }

  design <- readRDS(design_path)
  sidecar <- readRDS(sidecar_path)
  source_joint <- readRDS(source_fit_path)
  app_validate_glofas_latent_path_design(design)
  if (!identical(design$future_truth_policy, "physically_excluded_from_fit_objects_scoring_sidecar_only") ||
      !identical(sidecar$role, "post_fit_scoring_sidecar") ||
      !identical(sidecar$future_truth_used_in_fit, FALSE)) {
    stop("The continuation source violates the Part 4 future-truth firewall.", call. = FALSE)
  }

  vb_args <- app_make_qdesn_discrepancy_vb_args(
    cfg,
    prior = app_map_qdesn_prior(model_rows$coefficient_prior[[1L]]),
    seed = as.integer(model_rows$reservoir_seed[[1L]]),
    likelihood_family = likelihood
  )
  vb_args$joint_outer_max_iter <- as.integer(args$additional_outer_max_iter)
  vb_args$joint_outer_min_iter <- 1L
  vb_args$joint_outer_tol <- as.numeric(args$outer_tol)
  vb_args$joint_inner_max_iter <- as.integer(args$inner_max_iter)
  vb_args$joint_inner_min_iter <- as.integer(args$inner_min_iter)
  vb_args$n_draws <- as.integer(args$n_draws)
  if (vb_args$joint_outer_max_iter < 1L || vb_args$joint_inner_max_iter < 2L ||
      vb_args$joint_inner_min_iter < 1L || vb_args$joint_inner_min_iter > vb_args$joint_inner_max_iter ||
      !is.finite(vb_args$joint_outer_tol) || vb_args$joint_outer_tol <= 0) {
    stop("Invalid continuation controls.", call. = FALSE)
  }

  blas_manifest <- app_latent_runtime_backend_manifest(fail_closed = TRUE)
  blas_manifest$job_id <- output_job_id
  app_write_csv(blas_manifest, file.path(output_root, "manifests", paste0(output_job_id, "_blas_runtime.csv")))
  started <- Sys.time()
  joint <- app_glofas_part4_fit_joint(
    design = design,
    model_rows = model_rows,
    likelihood = likelihood,
    vb_args = vb_args,
    seed = as.integer(model_rows$reservoir_seed[[1L]]),
    initial_joint_fit = source_joint
  )
  continuation_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  fit_path <- file.path(output_root, "objects", paste0(output_job_id, "_fit_side.rds"))
  app_glofas_part4_atomic_save_rds(joint, fit_path)

  inverse_response <- as.character(((cfg$data %||% list())$transform %||% list())$inverse_response %||% "expm1")[[1L]]
  materialized <- app_glofas_part4_materialize_joint(
    joint = joint,
    design = design,
    model_rows = model_rows,
    panel = sidecar$panel,
    cfg = cfg,
    likelihood = likelihood,
    job_id = output_job_id,
    inverse_response = inverse_response
  )
  prediction_path <- file.path(output_root, "predictions", paste0(output_job_id, "_posterior_draws.csv.gz"))
  local({
    con <- gzfile(prediction_path, open = "wt")
    on.exit(close(con), add = TRUE)
    utils::write.csv(materialized$prediction_rows, con, row.names = FALSE)
  })
  score_path <- file.path(output_root, "scores", paste0(output_job_id, "_by_horizon.csv"))
  grid_path <- file.path(output_root, "scores", paste0(output_job_id, "_grid_crps_by_date.csv"))
  summary_path <- file.path(output_root, "scores", paste0(output_job_id, "_summary.csv"))
  trace_path <- file.path(output_root, "traces", paste0(output_job_id, "_trace.csv"))
  timing_path <- file.path(output_root, "traces", paste0(output_job_id, "_iteration_timing.csv"))
  coefficient_path <- file.path(output_root, "coefficients", paste0(output_job_id, "_coefficients.csv"))
  convergence_path <- file.path(output_root, "traces", paste0(output_job_id, "_convergence.csv"))
  app_write_csv(materialized$score_rows, score_path)
  app_write_csv(materialized$grid_score$by_date, grid_path)
  app_write_csv(cbind(
    data.frame(
      job_id = output_job_id,
      family = expected_family,
      continuation_runtime_seconds = continuation_seconds,
      cumulative_runtime_seconds = joint$runtime_seconds,
      converged = joint$converged,
      converged_outer = joint$converged_outer,
      converged_inner = joint$converged_inner,
      stopping_reason = joint$stopping_reason,
      stringsAsFactors = FALSE
    ),
    materialized$grid_score$summary
  ), summary_path)
  app_write_csv(joint$trace, trace_path)
  if (nrow(materialized$iteration_timing)) app_write_csv(materialized$iteration_timing, timing_path)
  app_write_csv(materialized$coefficient_rows, coefficient_path)
  app_write_csv(data.frame(
    quantile_level = as.numeric(joint$tau),
    inner_converged = vapply(joint$fits, function(x) isTRUE(x$vb_diagnostics$converged), logical(1L)),
    inner_iterations = vapply(joint$fits, function(x) as.integer(x$vb_diagnostics$iterations %||% NA_integer_), integer(1L)),
    final_parameter_change = vapply(joint$fits, function(x) {
      trace <- as.numeric(x$vb_diagnostics$parameter_change_trace %||% numeric())
      if (length(trace)) tail(trace, 1L) else NA_real_
    }, numeric(1L)),
    stringsAsFactors = FALSE
  ), convergence_path)

  provenance_path <- file.path(output_root, "manifests", paste0(output_job_id, "_continuation_provenance.csv"))
  code_head <- trimws(system2("git", c("-C", repo_root, "rev-parse", "HEAD"), stdout = TRUE))
  app_write_csv(data.frame(
    output_job_id = output_job_id,
    source_job_id = source_job_id,
    source_runtime_root = normalizePath(source_root, mustWork = TRUE),
    source_fit_sha256 = source_fit_sha,
    design_sha256 = design_sha,
    scoring_sidecar_sha256 = sidecar_sha,
    source_manifest_sha256 = app_sha256_file(source_manifest_path),
    config_sha256 = app_sha256_file(cfg_path),
    model_grid_sha256 = app_sha256_file(model_grid_path),
    code_head = code_head,
    joint_core_sha256 = app_sha256_file(app_path("application/R/latent_path_vb_joint.R")),
    part4_family_sha256 = app_sha256_file(app_path("application/R/glofas_part4_latent_family.R")),
    continuation_worker_sha256 = app_sha256_file(app_path("application/scripts/389_continue_glofas_part4_joint_fit.R")),
    state_contract_hash = app_glofas_part4_state_contract_hash(design),
    likelihood = likelihood,
    quantile_grid = paste(format(as.numeric(model_rows$quantile_level), trim = TRUE), collapse = ","),
    previous_outer_iterations = joint$previous_outer_iterations,
    additional_outer_max_iter = vb_args$joint_outer_max_iter,
    inner_max_iter = vb_args$joint_inner_max_iter,
    inner_min_iter = vb_args$joint_inner_min_iter,
    outer_tol = vb_args$joint_outer_tol,
    n_draws = vb_args$n_draws,
    cutoff = "2022-12-25",
    issued_window = "2022-12-26:2023-01-22",
    future_truth_policy = joint$future_truth_policy,
    created_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stringsAsFactors = FALSE
  ), provenance_path)

  artifacts <- c(
    fit_path, prediction_path, score_path, grid_path, summary_path, trace_path,
    if (file.exists(timing_path)) timing_path else character(),
    coefficient_path, convergence_path, provenance_path,
    file.path(output_root, "manifests", paste0(output_job_id, "_blas_runtime.csv"))
  )
  artifact_manifest_path <- file.path(output_root, "manifests", paste0(output_job_id, "_artifacts.csv"))
  artifact_manifest <- app_glofas_part4_artifact_manifest(artifacts, output_root)
  artifact_manifest$job_id <- output_job_id
  app_write_csv(artifact_manifest, artifact_manifest_path)
  unlink(running)
  writeLines(c(
    sprintf("job_id=%s", output_job_id),
    sprintf("completed_at=%s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    sprintf("fit_side_sha256=%s", app_sha256_file(fit_path)),
    sprintf("converged=%s", joint$converged),
    sprintf("stopping_reason=%s", joint$stopping_reason)
  ), completed)
  invisible(joint)
}

tryCatch(
  run_continuation(),
  error = function(e) {
    unlink(running)
    writeLines(c(
      sprintf("job_id=%s", output_job_id),
      sprintf("failed_at=%s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
      sprintf("message=%s", conditionMessage(e))
    ), failed)
    stop(e)
  }
)
