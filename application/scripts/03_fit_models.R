#!/usr/bin/env Rscript
# Purpose: fit raw GloFAS and Q-DESN model-grid entries for the application.
# Inputs: application_panel.rds, model_grid.csv, quantile_grid.csv.
# Outputs: fit_status.csv, prediction_quantiles.csv, and model objects when
# supported by the installed Q-DESN engine.
# Failure behavior: required model failures stop the stage when configured.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/launch_control.R"))
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_qdesn_features.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/forecast_contract.R"))
source(app_path("application/R/fit_qdesn_reference.R"))
source(app_path("application/R/fit_qdesn_discrepancy.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/fit_qdesn_latent_path.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_application.yaml",
  run_id = NULL,
  confirm_final_launch = FALSE
))
cfg <- app_read_config(app_path(args$config))
app_validate_application_model_contract(cfg)
artifact_policy <- app_fit_artifact_policy(cfg)
app_validate_fit_artifact_policy(cfg, artifact_policy)
run_id <- args$run_id %||% app_run_id(cfg)
app_validate_fit_stage_launch_request(
  cfg,
  run_id = run_id,
  confirm_final_launch = args$confirm_final_launch
)
run_dirs <- app_create_run_dirs(cfg, run_id = run_id)
app_stage_start("03_fit_models", run_dirs)

panel_path <- file.path(app_config_path(cfg, "cache"), "application_panel.rds")
if (!file.exists(panel_path)) stop(sprintf("Missing application panel: %s", panel_path), call. = FALSE)
panel <- readRDS(panel_path)
model_grid <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
seed_contract <- tryCatch(
  app_validate_qdesn_seed_contract(cfg, model_grid),
  error = function(e) {
    msg <- conditionMessage(e)
    app_write_csv(data.frame(issue = msg), file.path(run_dirs$logs, "qdesn_seed_contract_issues.csv"))
    app_stage_done("03_fit_models", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)
app_write_csv(seed_contract, file.path(run_dirs$manifest, "qdesn_seed_contract.csv"))
support_report <- tryCatch(
  app_require_qdesn_inference_support_for_fit(cfg, model_grid, run_dirs = run_dirs),
  error = function(e) {
    msg <- conditionMessage(e)
    app_stage_done("03_fit_models", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)
fit_stage_engine_report <- app_check_qdesn_engine_api(
  cfg,
  require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, model_grid),
  stop_on_failure = TRUE
)
fit_stage_engine_sha <- fit_stage_engine_report$repo_git_sha %||% NA_character_
fit_stage_engine_branch <- fit_stage_engine_report$repo_branch %||% NA_character_

fit_rows <- list()
prediction_rows <- list()
posterior_draw_rows <- list()
discrepancy_design_rows <- list()
discrepancy_prediction_design_rows <- list()
discrepancy_fit_rows <- list()
discrepancy_fit_diagnostic_rows <- list()
discrepancy_draw_check_rows <- list()
vb_iteration_timing_rows <- list()
vb_stage_timing_rows <- list()
vb_substep_timing_rows <- list()
k_fit <- 1L
k_pred <- 1L
k_draw <- 1L
k_disc_design <- 1L
k_disc_pred_design <- 1L
k_disc_fit <- 1L
k_disc_diag <- 1L
k_disc_draw_check <- 1L
k_vb_timing <- 1L
k_vb_stage_timing <- 1L
k_vb_substep_timing <- 1L

append_qdesn_stage_timing <- function(timing, result, stage_prefix = NULL) {
  if (!is.data.frame(timing) || !nrow(timing)) return(invisible(NULL))
  if (!is.null(stage_prefix) && nzchar(stage_prefix)) {
    timing$stage <- paste(stage_prefix, timing$stage, sep = ":")
  }
  timing$fit_id <- result$fit_id
  timing$model_id <- result$model_id
  timing$quantile_level <- result$quantile_level
  timing$likelihood_family <- result$likelihood_family
  timing$coefficient_prior <- result$coefficient_prior
  vb_stage_timing_rows[[k_vb_stage_timing]] <<- timing
  k_vb_stage_timing <<- k_vb_stage_timing + 1L
  invisible(NULL)
}

append_qdesn_substep_timing <- function(timing, result) {
  if (!is.data.frame(timing) || !nrow(timing)) return(invisible(NULL))
  timing$fit_id <- result$fit_id
  timing$model_id <- result$model_id
  timing$quantile_level <- result$quantile_level
  timing$likelihood_family <- result$likelihood_family
  timing$coefficient_prior <- result$coefficient_prior
  vb_substep_timing_rows[[k_vb_substep_timing]] <<- timing
  k_vb_substep_timing <<- k_vb_substep_timing + 1L
  invisible(NULL)
}

for (i in seq_len(nrow(model_grid))) {
  row <- model_grid[i, , drop = FALSE]
  start <- proc.time()[["elapsed"]]
  status <- "completed"
  msg <- ""
  result <- NULL
  try_result <- tryCatch({
    if (identical(row$model_family[[1L]], "raw_glofas")) {
      ens <- panel[panel$is_ensemble & is.finite(panel$g_transformed), , drop = FALSE]
      if (!nrow(ens)) stop("No ensemble rows available for raw GloFAS baseline.", call. = FALSE)
      p0 <- as.numeric(row$quantile_level[[1L]])
      keys <- unique(ens[, c("origin_date", "target_date", "horizon"), drop = FALSE])
      pred <- vector("list", nrow(keys))
      for (j in seq_len(nrow(keys))) {
        idx <- ens$origin_date == keys$origin_date[[j]] &
          ens$target_date == keys$target_date[[j]] &
          ens$horizon == keys$horizon[[j]]
        block <- ens[idx, , drop = FALSE]
        pred[[j]] <- app_make_raw_glofas_prediction_row(
          row = row,
          key_row = keys[j, , drop = FALSE],
          block = block,
          p0 = p0,
          cfg = cfg
        )
      }
      raw_pred <- do.call(rbind, pred)
      app_validate_prediction_table_contract(raw_pred, final_launch = FALSE)
      prediction_rows[[k_pred]] <- raw_pred
      k_pred <- k_pred + 1L
      list(status = "completed")
    } else if (identical(row$model_family[[1L]], "qdesn_reference_only")) {
      result <- app_fit_qdesn_reference(panel, cfg, row)
      app_maybe_save_rds(
        result$fit,
        file.path(run_dirs$objects, paste0(row$fit_id[[1L]], ".rds")),
        retained = app_fit_artifact_retained(artifact_policy, "retain_reference_fit_object")
      )
      list(status = "completed")
    } else if (identical(row$model_family[[1L]], "qdesn_glofas_discrepancy")) {
      if (app_is_latent_path_contract(cfg, row)) {
        result <- app_fit_qdesn_latent_path(panel, cfg, row)
      } else {
        result <- app_fit_qdesn_discrepancy(panel, cfg, row)
      }
      discrepancy_fit_diagnostic_rows[[k_disc_diag]] <- if (app_is_latent_path_contract(cfg, row)) {
        app_latent_path_fit_diagnostics(result)
      } else {
        app_discrepancy_fit_diagnostics(result)
      }
      k_disc_diag <- k_disc_diag + 1L
      timing <- result$fit$vb_diagnostics$iteration_timing %||% data.frame()
      if (is.data.frame(timing) && nrow(timing)) {
        timing$fit_id <- result$fit_id
        timing$model_id <- result$model_id
        timing$quantile_level <- result$quantile_level
        timing$likelihood_family <- result$likelihood_family
        timing$coefficient_prior <- result$coefficient_prior
        vb_iteration_timing_rows[[k_vb_timing]] <- timing
        k_vb_timing <- k_vb_timing + 1L
      }
      append_qdesn_stage_timing(result$fit$vb_diagnostics$stage_timing %||% data.frame(), result)
      append_qdesn_substep_timing(result$fit$vb_diagnostics$substep_timing %||% data.frame(), result)
      fit_path <- file.path(run_dirs$objects, paste0(row$fit_id[[1L]], ".rds"))
      design_path <- file.path(run_dirs$objects, paste0(row$fit_id[[1L]], "__design.rds"))
      retain_fit_object <- app_fit_artifact_retained(artifact_policy, "retain_fit_object")
      retain_design_object <- app_fit_artifact_retained(artifact_policy, "retain_design_object")
      retain_prediction_design_object <- app_fit_artifact_retained(artifact_policy, "retain_prediction_design_object")
      save_start <- proc.time()[["elapsed"]]
      fit_object_path <- app_maybe_save_rds(result$fit, fit_path, retained = retain_fit_object)
      append_qdesn_stage_timing(
        data.frame(stage = "save_fit_object", elapsed_seconds = proc.time()[["elapsed"]] - save_start, stringsAsFactors = FALSE),
        result
      )
      save_start <- proc.time()[["elapsed"]]
      design_for_save <- if (app_is_latent_path_contract(cfg, row)) app_latent_path_drop_runtime_cache(result$design) else result$design
      design_object_path <- app_maybe_save_rds(design_for_save, design_path, retained = retain_design_object)
      append_qdesn_stage_timing(
        data.frame(stage = "save_design_object", elapsed_seconds = proc.time()[["elapsed"]] - save_start, stringsAsFactors = FALSE),
        result
      )
      contract <- app_prediction_contract(cfg, model_family = "qdesn_glofas_discrepancy")
      prediction_design_path <- NA_character_
      prediction_design_object_path <- NA_character_
      posterior_draw_count <- NA_integer_
      pdsum <- NULL
      if (identical(contract$prediction_unit, "posterior_draw")) {
        prediction_start <- proc.time()[["elapsed"]]
        pred_result <- if (app_is_latent_path_contract(cfg, row)) {
          app_predict_qdesn_latent_path_draws(result, panel, cfg, row)
        } else {
          app_predict_qdesn_discrepancy_draws(result, panel, cfg, row)
        }
        append_qdesn_stage_timing(
          data.frame(stage = "posterior_draw_prediction", elapsed_seconds = proc.time()[["elapsed"]] - prediction_start, stringsAsFactors = FALSE),
          result
        )
        pred <- pred_result$summary
        posterior_draw_rows[[k_draw]] <- pred_result$draws
        discrepancy_draw_check_rows[[k_disc_draw_check]] <- app_discrepancy_prediction_draw_checks(pred_result$draws)
        k_disc_draw_check <- k_disc_draw_check + 1L
        posterior_draw_count <- nrow(pred_result$draws)
        k_draw <- k_draw + 1L
        prediction_design_path <- file.path(run_dirs$objects, paste0(row$fit_id[[1L]], "__prediction_design.rds"))
        save_start <- proc.time()[["elapsed"]]
        prediction_design_object_path <- app_maybe_save_rds(
          pred_result$prediction_design,
          prediction_design_path,
          retained = retain_prediction_design_object
        )
        append_qdesn_stage_timing(
          data.frame(stage = "save_prediction_design_object", elapsed_seconds = proc.time()[["elapsed"]] - save_start, stringsAsFactors = FALSE),
          result
        )
        pdsum <- pred_result$prediction_design_summary
        pdsum$prediction_design_object <- prediction_design_object_path
        pdsum$prediction_design_object_retained <- retain_prediction_design_object
        discrepancy_prediction_design_rows[[k_disc_pred_design]] <- pdsum
        k_disc_pred_design <- k_disc_pred_design + 1L
      } else {
        prediction_start <- proc.time()[["elapsed"]]
        pred <- app_predict_qdesn_discrepancy(result, panel, cfg, row)
        append_qdesn_stage_timing(
          data.frame(stage = "summary_prediction", elapsed_seconds = proc.time()[["elapsed"]] - prediction_start, stringsAsFactors = FALSE),
          result
        )
      }
      prediction_rows[[k_pred]] <- pred
      k_pred <- k_pred + 1L

      dsum <- result$design_summary
      dsum$fit_object <- fit_object_path
      dsum$design_object <- design_object_path
      dsum$fit_object_retained <- retain_fit_object
      dsum$design_object_retained <- retain_design_object
      discrepancy_design_rows[[k_disc_design]] <- dsum
      k_disc_design <- k_disc_design + 1L

      engine_report <- app_check_qdesn_engine_api(
        cfg,
        require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, model_grid),
        stop_on_failure = TRUE
      )
      if (!identical(engine_report$repo_git_sha %||% NA_character_, fit_stage_engine_sha) ||
          !identical(engine_report$repo_branch %||% NA_character_, fit_stage_engine_branch)) {
        stop(
          sprintf(
            paste(
              "Q-DESN engine repository changed during 03_fit_models.",
              "started_branch=%s started_sha=%s ended_branch=%s ended_sha=%s"
            ),
            fit_stage_engine_branch,
            fit_stage_engine_sha,
            engine_report$repo_branch %||% NA_character_,
            engine_report$repo_git_sha %||% NA_character_
          ),
          call. = FALSE
        )
      }
      input_manifest_path <- app_config_path(cfg, "input_manifest")
      cfg_path <- cfg$.__config_path__ %||% args$config
      discrepancy_fit_rows[[k_disc_fit]] <- data.frame(
        fit_id = result$fit_id,
        model_id = result$model_id,
        quantile_level = result$quantile_level,
        method = result$method,
        likelihood_family = result$likelihood_family,
        coefficient_prior = result$coefficient_prior,
        engine = engine_report$engine,
        engine_load_mode = engine_report$load_mode %||% NA_character_,
        engine_version = engine_report$version %||% NA_character_,
        engine_repo_hint = engine_report$repo_hint %||% NA_character_,
        engine_repo_hint_exists = engine_report$repo_hint_exists %||% NA,
        engine_repo_sha = engine_report$repo_git_sha %||% NA_character_,
        engine_repo_branch = engine_report$repo_branch %||% NA_character_,
        engine_source_policy_ok = engine_report$source_policy_ok %||% NA,
        engine_source_policy_message = engine_report$source_policy_message %||% NA_character_,
        engine_expected_repo_hint = engine_report$expected_repo_hint %||% NA_character_,
        engine_required_branch = engine_report$required_branch %||% NA_character_,
        engine_required_commit = engine_report$required_commit %||% NA_character_,
        engine_required_load_mode = engine_report$required_load_mode %||% NA_character_,
        engine_min_version = engine_report$min_version %||% NA_character_,
        engine_required_exports = paste(engine_report$required_exports, collapse = ";"),
        engine_missing_exports = paste(engine_report$missing_exports, collapse = ";"),
        engine_require_discrepancy = engine_report$require_discrepancy %||% NA,
        engine_api_ok = engine_report$ok %||% NA,
        engine_api_message = engine_report$message %||% NA_character_,
        article_git_sha = app_git_sha(short = FALSE) %||% NA_character_,
        input_manifest_hash = if (file.exists(input_manifest_path)) app_sha256_file(input_manifest_path) else NA_character_,
        config_hash = app_sha256_file(cfg_path),
        design_hash = dsum$design_hash,
        prediction_design_hash = if (!is.null(pdsum)) pdsum$prediction_design_hash %||% NA_character_ else NA_character_,
        covariate_future_policy = dsum$covariate_future_policy %||% NA_character_,
        covariate_source_provider = dsum$covariate_source_provider %||% NA_character_,
        covariate_uses_realized_future = dsum$covariate_uses_realized_future %||% NA,
        covariate_source_manifest_hash = dsum$covariate_source_manifest_hash %||% NA_character_,
        n_stacked_rows = dsum$n_stacked_rows,
        n_augmented_features = dsum$n_augmented_features,
        n_burn = result$mcmc_args$n_burn %||% NA_integer_,
        n_mcmc = result$mcmc_args$n_mcmc %||% NA_integer_,
        thin = result$mcmc_args$thin %||% NA_integer_,
        vb_max_iter = result$vb_args$max_iter %||% NA_integer_,
        vb_tol = result$vb_args$tol %||% NA_real_,
        vb_n_draws = result$vb_args$n_draws %||% NA_integer_,
        vb_ld_block_active = result$vb_args$ld_block_active %||% NA,
        vb_draw_backend_requested = result$fit$vb_diagnostics$draw_backend_requested %||% NA_character_,
        vb_theta_draw_backend = result$fit$vb_diagnostics$theta_draw_backend %||% NA_character_,
        vb_future_draw_backend = result$fit$vb_diagnostics$future_draw_backend %||% NA_character_,
        fit_object = fit_object_path,
        design_object = design_object_path,
        prediction_design_object = prediction_design_object_path,
        fit_object_retained = retain_fit_object,
        design_object_retained = retain_design_object,
        prediction_design_object_retained = if (identical(contract$prediction_unit, "posterior_draw")) retain_prediction_design_object else NA,
        posterior_draw_rows = posterior_draw_count,
        status = result$status,
        message = if (identical(contract$prediction_unit, "posterior_draw")) {
          sprintf("%s; wrote %d posterior-draw rows and %d summary prediction rows", result$message, posterior_draw_count, nrow(pred))
        } else {
          sprintf("%s; wrote %d pilot prediction rows", result$message, nrow(pred))
        },
        stringsAsFactors = FALSE
      )
      k_disc_fit <- k_disc_fit + 1L
      list(
        status = result$status,
        message = if (identical(contract$prediction_unit, "posterior_draw")) {
          sprintf("%s; wrote %d posterior-draw rows and %d summary prediction rows", result$message, posterior_draw_count, nrow(pred))
        } else {
          sprintf("%s; wrote %d pilot prediction rows", result$message, nrow(pred))
        }
      )
    } else {
      list(status = "skipped", message = "baseline adapter not implemented")
    }
  }, error = function(e) {
    status <<- if (app_as_bool(row$required[[1L]])) "failed" else "not_run"
    msg <<- conditionMessage(e)
    NULL
  })
  if (!is.null(try_result) && !is.null(try_result$status) && identical(status, "completed")) {
    status <- try_result$status
    msg <- try_result$message %||% msg
  }

  elapsed <- proc.time()[["elapsed"]] - start
  fit_rows[[k_fit]] <- data.frame(
    fit_id = row$fit_id[[1L]],
    model_id = row$model_id[[1L]],
    model_family = row$model_family[[1L]],
    quantile_level = as.numeric(row$quantile_level[[1L]]),
    inference_method = row$inference_method[[1L]],
    coefficient_prior = row$coefficient_prior[[1L]],
    required = app_as_bool(row$required[[1L]]),
    status = status,
    message = msg,
    runtime_seconds = elapsed,
    stringsAsFactors = FALSE
  )
  k_fit <- k_fit + 1L

  if (identical(status, "failed") && isTRUE(cfg$execution$stop_on_failed_required_model)) {
    break
  }
}

fit_status <- do.call(rbind, fit_rows)
app_write_csv(fit_status, file.path(run_dirs$tables, "fit_status.csv"))
if (length(prediction_rows)) {
  predictions <- app_bind_rows_fill(prediction_rows)
  app_write_csv(predictions, file.path(run_dirs$tables, "prediction_quantiles.csv"))
}
if (length(posterior_draw_rows)) {
  posterior_draws <- app_bind_rows_fill(posterior_draw_rows)
  app_write_csv(posterior_draws, file.path(run_dirs$tables, "posterior_draw_predictions.csv"))
}
if (length(discrepancy_design_rows)) {
  app_write_csv(
    app_bind_rows_fill(discrepancy_design_rows),
    file.path(run_dirs$tables, "qdesn_discrepancy_design_summary.csv")
  )
}
if (length(discrepancy_prediction_design_rows)) {
  app_write_csv(
    app_bind_rows_fill(discrepancy_prediction_design_rows),
    file.path(run_dirs$tables, "qdesn_discrepancy_prediction_design_summary.csv")
  )
}
if (length(discrepancy_fit_rows)) {
  app_write_csv(
    app_bind_rows_fill(discrepancy_fit_rows),
    file.path(run_dirs$manifest, "qdesn_discrepancy_fit_manifest.csv")
  )
}
if (length(discrepancy_fit_diagnostic_rows)) {
  app_write_csv(
    app_bind_rows_fill(discrepancy_fit_diagnostic_rows),
    file.path(run_dirs$tables, "qdesn_discrepancy_fit_diagnostics.csv")
  )
}
if (length(vb_iteration_timing_rows)) {
  app_write_csv(
    app_bind_rows_fill(vb_iteration_timing_rows),
    file.path(run_dirs$tables, "qdesn_discrepancy_vb_iteration_timing.csv")
  )
}
if (length(vb_stage_timing_rows)) {
  app_write_csv(
    app_bind_rows_fill(vb_stage_timing_rows),
    file.path(run_dirs$tables, "qdesn_discrepancy_fit_stage_timing.csv")
  )
}
if (length(vb_substep_timing_rows)) {
  app_write_csv(
    app_bind_rows_fill(vb_substep_timing_rows),
    file.path(run_dirs$tables, "qdesn_discrepancy_vb_substep_timing.csv")
  )
}
if (length(discrepancy_draw_check_rows)) {
  app_write_csv(
    app_bind_rows_fill(discrepancy_draw_check_rows),
    file.path(run_dirs$tables, "qdesn_discrepancy_draw_checks.csv")
  )
}

failed_required <- fit_status$status == "failed" & fit_status$required
if (any(failed_required)) {
  app_stage_done("03_fit_models", run_dirs, status = "failed", message = paste(fit_status$message[failed_required], collapse = "; "))
  stop("One or more required model fits failed. See fit_status.csv.", call. = FALSE)
}

app_stage_done("03_fit_models", run_dirs)
cat(run_dirs$run_dir, "\n")
