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
  "glofas_normal_desn_part1_screening.R",
  "glofas_part3_partitioned_rhs.R", "latent_path_vb_joint.R", "fit_qdesn_latent_path.R",
  "glofas_part4_ensemble_likelihood_contract.R", "glofas_part4_latent_family.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(runtime_root = "", job_id = ""))
runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
job_id <- as.character(args$job_id)[[1L]]
if (!nzchar(job_id)) stop("--job_id is required.", call. = FALSE)
manifest_path <- file.path(runtime_root, "configs", "part4_model_manifest.csv")
manifest <- app_read_csv(manifest_path)
job <- manifest[manifest$run_id == job_id, , drop = FALSE]
if (nrow(job) != 1L) stop(sprintf("Expected one manifest row for job %s.", job_id), call. = FALSE)

for (sub in c("objects", "predictions", "scores", "traces", "coefficients", "logs", "status", "manifests")) {
  app_ensure_dir(file.path(runtime_root, sub))
}

blas_manifest <- app_latent_runtime_backend_manifest(fail_closed = TRUE)
blas_manifest$job_id <- job_id
app_write_csv(blas_manifest, file.path(runtime_root, "manifests", paste0(job_id, "_blas_runtime.csv")))
running <- file.path(runtime_root, "status", paste0(job_id, ".running"))
completed <- file.path(runtime_root, "status", paste0(job_id, ".completed"))
failed <- file.path(runtime_root, "status", paste0(job_id, ".failed"))
if (file.exists(completed)) stop(sprintf("Part 4 job already completed: %s.", job_id), call. = FALSE)
dependencies <- app_glofas_part4_parse_dependencies(job$dependencies[[1L]])
missing_dependencies <- if (length(dependencies)) {
  dependencies[!file.exists(file.path(runtime_root, "status", paste0(dependencies, ".completed")))]
} else {
  character()
}
if (length(missing_dependencies)) {
  stop(sprintf("Part 4 job dependencies are incomplete: %s.", paste(missing_dependencies, collapse = ", ")), call. = FALSE)
}
writeLines(c(sprintf("job_id=%s", job_id), sprintf("pid=%d", Sys.getpid()),
  sprintf("started_at=%s", format(Sys.time(), tz = "UTC", usetz = TRUE))), running)

run_job <- function() {
  cfg <- app_read_config(app_resolve_path(job$config_path[[1L]], must_work = TRUE))
  model_grid <- app_validate_model_grid(
    app_resolve_path(job$model_grid_path[[1L]], must_work = TRUE),
    app_config_path(cfg, "schema")
  )
  model_rows <- model_grid[model_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  cutoff <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))[1L, , drop = FALSE]
  design_path <- file.path(runtime_root, "objects", "part4_shared_design_truth_free.rds")
  panel_path <- file.path(runtime_root, "objects", "part4_scoring_panel_sidecar.rds")
  audit_path <- file.path(runtime_root, "manifests", "part4_fixed_window_audit.csv")
  family <- as.character(job$part4_family[[1L]])
  inverse_response <- as.character(((cfg$data %||% list())$transform %||% list())$inverse_response %||% "expm1")[[1L]]

  if (!file.exists(design_path)) {
    if (!identical(family, "normal_ridge_diagnostic")) {
      stop("The truth-free Part 4 shared design must be created by the Normal Ridge root job.", call. = FALSE)
    }
    panel <- app_glofas_part4_build_panel(cfg)
    audit <- app_glofas_part4_window_audit(panel, cutoff)
    app_write_csv(audit, audit_path)
    design <- app_make_glofas_latent_path_design(panel, cfg, model_rows[1L, , drop = FALSE], cutoff_row = cutoff)
    app_validate_glofas_latent_path_design(design)
    app_glofas_part4_atomic_save_rds(app_latent_path_drop_runtime_cache(design, compact = FALSE), design_path)
    scoring_truth <- app_make_glofas_latent_path_scoring_truth(panel, design$future_key)
    app_glofas_part4_atomic_save_rds(
      list(
        panel = data.frame(
          target_date = scoring_truth$target_date,
          y_transformed = scoring_truth$y_reference,
          stringsAsFactors = FALSE
        ),
        role = "post_fit_scoring_sidecar",
        future_truth_used_in_fit = FALSE,
        future_truth_rows = nrow(scoring_truth)
      ),
      panel_path
    )
  }
  if (!file.exists(panel_path)) stop("Part 4 scoring sidecar is missing.", call. = FALSE)
  design <- readRDS(design_path)
  scoring_sidecar <- readRDS(panel_path)
  panel <- scoring_sidecar$panel
  stopifnot(identical(scoring_sidecar$role, "post_fit_scoring_sidecar"))
  app_validate_glofas_latent_path_design(design)
  if (!identical(design$future_truth_policy, "physically_excluded_from_fit_objects_scoring_sidecar_only")) {
    stop("Part 4 fit design does not enforce the future-truth firewall.", call. = FALSE)
  }

  vb_args <- app_make_qdesn_discrepancy_vb_args(
    cfg,
    prior = app_map_qdesn_prior(model_rows$coefficient_prior[[1L]]),
    seed = as.integer(model_rows$reservoir_seed[[1L]]),
    likelihood_family = as.character(model_rows$likelihood_family[[1L]])
  )
  vb_args$normal_exact_optimization <- TRUE
  vb_args$diagnostics <- modifyList(
    vb_args$diagnostics %||% list(),
    list(profile_substeps = TRUE)
  )
  vb_args$progress_path <- file.path(runtime_root, "traces", paste0(job_id, "_live.csv"))
  dependency_paths <- app_glofas_part4_dependency_artifact_paths(runtime_root, dependencies)
  dependency_results <- lapply(dependency_paths, readRDS)
  started <- Sys.time()

  if (family %in% c("joint_al_rhs_vb", "joint_exal_rhs_vb")) {
    likelihood <- if (identical(family, "joint_exal_rhs_vb")) "exal" else "al"
    joint <- app_glofas_part4_fit_joint(
      design, model_rows, likelihood, dependency_results, vb_args,
      seed = as.integer(model_rows$reservoir_seed[[1L]])
    )
    fit_side_path <- file.path(runtime_root, "objects", paste0(job_id, "_fit_side.rds"))
    app_glofas_part4_atomic_save_rds(joint, fit_side_path)
    materialized <- app_glofas_part4_materialize_joint(
      joint, design, model_rows, panel, cfg, likelihood, job_id, inverse_response
    )
    prediction_rows <- materialized$prediction_rows
    score_rows <- materialized$score_rows
    grid_score <- materialized$grid_score
    score_summary <- cbind(
      data.frame(job_id = job_id, family = family, runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))),
      grid_score$summary
    )
    app_write_csv(grid_score$by_date, file.path(runtime_root, "scores", paste0(job_id, "_grid_crps_by_date.csv")))
    coefficient_path <- file.path(runtime_root, "coefficients", paste0(job_id, "_coefficients.csv"))
    app_write_csv(materialized$coefficient_rows, coefficient_path)
    trace <- joint$trace
  } else {
    initializer <- if (length(dependency_results)) {
      app_glofas_part4_initializer(dependency_results[[1L]], design, dependency_paths[[1L]])
    } else {
      anchor_path <- file.path(runtime_root, "configs", "selected_anchor_manifest.csv")
      if (file.exists(anchor_path)) {
        app_glofas_part4_root_initializer_from_manifest(app_read_csv(anchor_path), design)
      } else {
        NULL
      }
    }
    result <- app_glofas_part4_fit_independent(
      design, model_rows[1L, , drop = FALSE], vb_args, initializer,
      seed = as.integer(model_rows$reservoir_seed[[1L]])
    )
    fit_side_path <- file.path(runtime_root, "objects", paste0(job_id, "_fit_side.rds"))
    app_glofas_part4_atomic_save_rds(
      app_glofas_part4_fit_side_artifact(result, design_path),
      fit_side_path
    )
    pred <- app_predict_qdesn_latent_path_draws(result, panel, cfg, model_rows[1L, , drop = FALSE])
    scored <- app_glofas_part4_score_prediction(
      pred,
      result$likelihood_family,
      inverse_response = inverse_response
    )
    prediction_rows <- pred$draws
    score_rows <- scored$by_horizon
    score_summary <- cbind(
      data.frame(job_id = job_id, family = family, runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))),
      scored$summary
    )
    trace <- result$fit$vb_diagnostics$iteration_trace %||%
      data.frame(iteration = seq_along(result$fit$vb_diagnostics$parameter_change_trace),
        parameter_change = result$fit$vb_diagnostics$parameter_change_trace)
    coefficients <- app_glofas_part4_coefficient_summary(result)
    coefficient_path <- file.path(runtime_root, "coefficients", paste0(job_id, "_coefficients.csv"))
    app_write_csv(coefficients, coefficient_path)
  }

  iteration_timing <- if (family %in% c("joint_al_rhs_vb", "joint_exal_rhs_vb")) {
    materialized$iteration_timing
  } else {
    result$fit$vb_diagnostics$iteration_timing %||% data.frame()
  }

  prediction_path <- file.path(runtime_root, "predictions", paste0(job_id, "_posterior_draws.csv.gz"))
  score_path <- file.path(runtime_root, "scores", paste0(job_id, "_by_horizon.csv"))
  summary_path <- file.path(runtime_root, "scores", paste0(job_id, "_summary.csv"))
  trace_path <- file.path(runtime_root, "traces", paste0(job_id, "_trace.csv"))
  local({
    prediction_connection <- gzfile(prediction_path, open = "wt")
    on.exit(close(prediction_connection), add = TRUE)
    utils::write.csv(prediction_rows, prediction_connection, row.names = FALSE)
  })
  app_write_csv(score_rows, score_path)
  app_write_csv(score_summary, summary_path)
  app_write_csv(trace, trace_path)
  timing_path <- file.path(runtime_root, "traces", paste0(job_id, "_iteration_timing.csv"))
  if (nrow(iteration_timing)) app_write_csv(iteration_timing, timing_path)
  artifacts <- c(
    fit_side_path,
    prediction_path,
    score_path,
    summary_path,
    trace_path,
    coefficient_path,
    file.path(runtime_root, "manifests", paste0(job_id, "_blas_runtime.csv")),
    if (file.exists(timing_path)) timing_path else character(),
    if (exists("grid_score", inherits = FALSE)) {
      file.path(runtime_root, "scores", paste0(job_id, "_grid_crps_by_date.csv"))
    } else {
      character()
    }
  )
  artifact_manifest <- app_glofas_part4_artifact_manifest(artifacts, runtime_root)
  artifact_manifest$job_id <- job_id
  app_write_csv(artifact_manifest, file.path(runtime_root, "manifests", paste0(job_id, "_artifacts.csv")))
  unlink(running)
  writeLines(c(sprintf("job_id=%s", job_id),
    sprintf("completed_at=%s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    sprintf("fit_side_sha256=%s", app_sha256_file(fit_side_path))), completed)
  invisible(TRUE)
}

tryCatch(
  run_job(),
  error = function(e) {
    unlink(running)
    writeLines(c(sprintf("job_id=%s", job_id),
      sprintf("failed_at=%s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
      sprintf("message=%s", conditionMessage(e))), failed)
    stop(e)
  }
)
