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

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  runtime_root = "",
  winner_manifest = "",
  model_family = "",
  allow_unfrozen = "false",
  ridge_warm_start_path = "",
  ridge_warm_start_sha256 = "",
  progress_every = "1"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
winner_manifest <- app_resolve_path(args$winner_manifest, must_work = TRUE)
model_family <- as.character(args$model_family)[[1L]]
allowed_normal <- c("normal_ridge_joint", "normal_rhs_vb_joint")
if (!model_family %in% allowed_normal) {
  stop(
    sprintf(
      "Part 3 worker currently runs only %s. Requested '%s' remains blocked.",
      paste(allowed_normal, collapse = " or "),
      model_family
    ),
    call. = FALSE
  )
}

dirs <- file.path(runtime_root, c("scores", "details", "traces", "coefficients", "objects", "status", "logs"))
invisible(lapply(dirs, app_ensure_dir))
status_path <- file.path(runtime_root, "status", paste0(model_family, ".running"))
completed_path <- file.path(runtime_root, "status", paste0(model_family, ".completed"))
failed_path <- file.path(runtime_root, "status", paste0(model_family, ".failed"))
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), status_path)

tryCatch({
  base_config <- app_resolve_path(args$base_config, must_work = TRUE)
  base_cfg <- app_read_config(base_config)
  candidate <- app_glofas_normal_part3_candidate_from_winners(
    winner_manifest,
    candidate_id = paste0("part3_", model_family),
    require_frozen = !app_as_bool(args$allow_unfrozen)
  )
  initializer <- list(
    required = identical(model_family, "normal_rhs_vb_joint"),
    loaded = FALSE,
    path = NA_character_,
    declared_sha256 = NA_character_,
    actual_sha256 = NA_character_,
    part3_stacked_train_hash = NA_character_
  )
  warm_start <- NULL
  if (identical(model_family, "normal_rhs_vb_joint")) {
    if (!nzchar(trimws(as.character(args$ridge_warm_start_path)))) {
      stop("Part 3 Normal RHS/VB requires --ridge_warm_start_path; implicit Ridge refitting is forbidden.", call. = FALSE)
    }
    if (!nzchar(trimws(as.character(args$ridge_warm_start_sha256)))) {
      stop("Part 3 Normal RHS/VB requires --ridge_warm_start_sha256.", call. = FALSE)
    }
    initializer$path <- app_resolve_path(args$ridge_warm_start_path, must_work = TRUE)
    initializer$declared_sha256 <- tolower(trimws(as.character(args$ridge_warm_start_sha256)))
    warm_start <- app_glofas_normal_part3_load_warm_start(
      initializer$path,
      initializer$declared_sha256
    )
    initializer$actual_sha256 <- as.character(attr(warm_start, "source_sha256"))
    initializer$part3_stacked_train_hash <- as.character(
      warm_start$design_hash$part3_stacked_train %||% NA_character_
    )
    initializer$loaded <- TRUE
  }
  progress_path <- file.path(runtime_root, "traces", paste0(model_family, "_progress.csv"))
  result <- switch(
    model_family,
    normal_ridge_joint = app_glofas_normal_part3_fit_ridge(
      base_cfg = base_cfg,
      candidate_row = candidate
    ),
    normal_rhs_vb_joint = app_glofas_normal_part3_fit_rhs(
      base_cfg = base_cfg,
      candidate_row = candidate,
      warm_start = warm_start,
      progress_path = progress_path,
      progress_every = as.integer(args$progress_every)
    )
  )
  result$summary$initializer_required <- initializer$required
  result$summary$initializer_loaded <- initializer$loaded
  result$summary$initializer_path <- initializer$path
  result$summary$initializer_declared_sha256 <- initializer$declared_sha256
  result$summary$initializer_actual_sha256 <- initializer$actual_sha256
  result$summary$initializer_part3_stacked_train_hash <- initializer$part3_stacked_train_hash
  app_write_csv(result$summary, file.path(runtime_root, "scores", paste0(model_family, "_summary.csv")))
  app_write_csv(result$detail, file.path(runtime_root, "details", paste0(model_family, "_validation_detail.csv")))
  app_write_csv(result$trace, file.path(runtime_root, "traces", paste0(model_family, "_trace.csv")))
  app_write_csv(result$coefficients, file.path(runtime_root, "coefficients", paste0(model_family, "_coefficients.csv")))
  fit_path <- file.path(runtime_root, "objects", paste0(model_family, "_fit.rds"))
  saveRDS(result$fit, fit_path, version = 2L)
  warm_start_path <- NA_character_
  warm_start_sha256 <- NA_character_
  if (!is.null(result$warm_start)) {
    warm_start_path <- file.path(runtime_root, "objects", paste0(model_family, "_warm_start.rds"))
    saveRDS(result$warm_start, warm_start_path, version = 2L)
    warm_start_sha256 <- app_sha256_file(warm_start_path)
  }
  execution_contract <- data.frame(
    model_family = model_family,
    candidate_id = as.character(candidate$candidate_id[[1L]]),
    winner_manifest = winner_manifest,
    winner_manifest_sha256 = app_sha256_file(winner_manifest),
    base_config = base_config,
    base_config_sha256 = app_sha256_file(base_config),
    initializer_required = initializer$required,
    initializer_loaded = initializer$loaded,
    initializer_path = initializer$path,
    initializer_declared_sha256 = initializer$declared_sha256,
    initializer_actual_sha256 = initializer$actual_sha256,
    initializer_part3_stacked_train_hash = initializer$part3_stacked_train_hash,
    output_fit_path = fit_path,
    output_fit_sha256 = app_sha256_file(fit_path),
    output_warm_start_path = warm_start_path,
    output_warm_start_sha256 = warm_start_sha256,
    completed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
  app_write_csv(
    execution_contract,
    file.path(runtime_root, "logs", paste0(model_family, "_execution_contract.csv"))
  )
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), completed_path)
  if (file.exists(status_path)) unlink(status_path)
  cat(file.path(runtime_root, "scores", paste0(model_family, "_summary.csv")), "\n")
}, error = function(e) {
  writeLines(conditionMessage(e), failed_path)
  if (file.exists(status_path)) unlink(status_path)
  stop(e)
})
