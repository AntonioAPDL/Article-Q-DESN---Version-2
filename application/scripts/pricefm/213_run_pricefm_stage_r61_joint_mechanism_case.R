#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(yaml)
  library(jsonlite)
  library(data.table)
})

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
args <- commandArgs(trailingOnly = TRUE)
arg <- function(flag, default = NULL) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) default else args[[index + 1L]]
}
bool_arg <- function(flag, default = FALSE) {
  tolower(as.character(arg(flag, default))) %in% c("1", "true", "yes", "y")
}

config_path <- arg("--config")
if (is.null(config_path)) stop("--config is required", call. = FALSE)
resume <- bool_arg("--resume", TRUE)
force <- bool_arg("--force", FALSE)
cfg <- yaml::read_yaml(config_path)$pricefm_stage_r61_joint_mechanism
out <- normalizePath(cfg$output_dir, mustWork = FALSE)
adapter <- normalizePath(cfg$adapter_dir, mustWork = FALSE)
summary_path <- file.path(out, "job_summary.json")

write_json <- function(path, payload) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(payload, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  cat("\n", file = path, append = TRUE)
}

if (resume && !force && file.exists(summary_path)) {
  existing <- tryCatch(jsonlite::read_json(summary_path, simplifyVector = TRUE), error = function(e) NULL)
  if (!is.null(existing) && identical(existing$status, "completed") && file.exists(file.path(out, "metric_summary.csv"))) {
    cat(jsonlite::toJSON(existing, auto_unbox = TRUE, pretty = TRUE), "\n")
    quit(status = 0L)
  }
}
if (dir.exists(out) && (force || !resume)) {
  keep_log <- file.path(out, "worker.log")
  paths <- setdiff(list.files(out, full.names = TRUE, all.files = TRUE, no.. = TRUE), keep_log)
  if (length(paths)) unlink(paths, recursive = TRUE, force = TRUE)
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)

fail <- function(message) {
  write_json(summary_path, list(
    status = "failed", stage = "R61", case_id = cfg$case_id,
    source_case_id = cfg$source_case_id, region = cfg$region, fold = as.integer(cfg$fold),
    error = as.character(message), test_accessed = FALSE,
    registry_mutation_authorized = FALSE, article_mutation_authorized = FALSE
  ))
  stop(message, call. = FALSE)
}

main <- function() {
  allowed_splits <- as.character(unlist(cfg$allowed_splits, use.names = FALSE))
  if (!identical(allowed_splits, c("train", "val")) || isTRUE(cfg$test_access_authorized)) {
    fail("Stage-R61 permits exactly train and validation.")
  }
  smoke <- yaml::read_yaml(cfg$smoke_config)$pricefm_desn_smoke
  if (!identical(as.character(unlist(smoke$splits, use.names = FALSE)), c("train", "val"))) {
    fail("Adapter config attempted to open a split outside train/validation.")
  }
  if (!identical(as.character(smoke$region), as.character(cfg$region)) ||
      as.integer(smoke$fold) != as.integer(cfg$fold)) {
    fail("Runtime and adapter region/fold contracts disagree.")
  }
  quantiles <- as.numeric(unlist(cfg$quantiles, use.names = FALSE))
  paper_quantiles <- c(0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
  if (!identical(round(quantiles, 12), round(paper_quantiles, 12))) {
    fail("Stage-R61 quantile ladder changed.")
  }

  adapter_manifest_path <- file.path(adapter, "adapter_manifest.json")
  required_files <- unlist(lapply(allowed_splits, function(split) {
    file.path(adapter, paste0(c("X_", "y_", "rows_"), split, ".csv"))
  }), use.names = FALSE)
  rebuild <- !file.exists(adapter_manifest_path) || !all(file.exists(required_files))
  if (file.exists(file.path(adapter, "X_test.csv")) || file.exists(file.path(adapter, "rows_test.csv"))) {
    fail("A test adapter exists inside the Stage-R61 workspace.")
  }
  if (rebuild) {
    if (dir.exists(adapter)) unlink(adapter, recursive = TRUE, force = TRUE)
    status <- system2(
      cfg$python_bin,
      c(cfg$adapter_builder, "--smoke-config", cfg$smoke_config, "--force", "true"),
      stdout = file.path(out, "adapter_build.log"), stderr = file.path(out, "adapter_build.log")
    )
    if (!identical(status, 0L)) fail(sprintf("Adapter build failed with status %s.", status))
  }
  if (file.exists(file.path(adapter, "X_test.csv")) || file.exists(file.path(adapter, "rows_test.csv"))) {
    fail("Test material was created despite the split firewall.")
  }

  source_root <- normalizePath(cfg$source_root, mustWork = TRUE)
  source(file.path(source_root, "application/R/00_packages.R"))
  app_set_repo_root(source_root)
  source(file.path(source_root, "application/R/joint_qvp_qdesn.R"))
  source(file.path(source_root, "application/R/joint_exqdesn_exact_structured_inference.R"))
  source(file.path(source_root, "application/R/joint_exqdesn_inference_dispatch.R"))
  source(file.path(source_root, "application/R/pricefm_joint_quantile_inference.R"))

  read_matrix <- function(path) {
    value <- as.matrix(data.table::fread(path, header = FALSE, showProgress = FALSE))
    storage.mode(value) <- "double"
    value
  }
  X_train <- read_matrix(file.path(adapter, "X_train.csv"))
  y_train <- as.numeric(read_matrix(file.path(adapter, "y_train.csv"))[, 1L])
  X_val <- read_matrix(file.path(adapter, "X_val.csv"))
  rows_val <- data.table::fread(file.path(adapter, "rows_val.csv"), showProgress = FALSE)
  if (nrow(X_train) != length(y_train) || nrow(X_val) != nrow(rows_val)) {
    fail("Adapter row dimensions are inconsistent.")
  }
  Z_train <- app_pricefm_joint_strip_intercept(X_train)
  if (ncol(Z_train) * length(quantiles) > as.integer(cfg$max_dense_dim)) {
    fail("Joint coefficient dimension exceeds the declared dense VB bound.")
  }

  initialization <- cfg$initialization %||% list(mode = "controlled_cold")
  initialization_mode <- as.character(initialization$mode %||% "controlled_cold")
  allowed_initializers <- c("controlled_cold", "training_only_independent_quantiles")
  if (!(initialization_mode %in% allowed_initializers)) {
    fail(sprintf("Unsupported Stage-R61 initialization mode '%s'.", initialization_mode))
  }
  fit_init <- NULL
  initializer_path <- ""
  initializer_diagnostics_path <- ""
  if (identical(initialization_mode, "training_only_independent_quantiles")) {
    package_path <- normalizePath(smoke$package_path, mustWork = TRUE)
    suppressPackageStartupMessages(pkgload::load_all(package_path, quiet = TRUE))
    initializer <- app_pricefm_joint_fit_independent_initializer(
      X = X_train, y = y_train, tau = quantiles,
      likelihood_family = cfg$likelihood_family, smoke_cfg = smoke,
      seed = as.integer(smoke$run$seed)
    )
    fit_init <- initializer$init
    initializer_path <- file.path(out, "training_only_independent_initializer.rds")
    initializer_diagnostics_path <- file.path(out, "training_only_independent_initializer.csv")
    saveRDS(fit_init, initializer_path, compress = "xz")
    utils::write.csv(initializer$diagnostics, initializer_diagnostics_path, row.names = FALSE)
  }

  rhs_control <- cfg$rhs_control
  required_rhs <- c(
    "anchor_tau0", "innovation_tau0", "anchor_init_tau", "innovation_init_tau",
    "freeze_iters", "vb_inner"
  )
  if (!all(required_rhs %in% names(rhs_control))) fail("Stage-R61 RHS control is incomplete.")
  started <- proc.time()[["elapsed"]]
  common <- list(
    y = y_train, Z = Z_train, tau = quantiles,
    max_iter = as.integer(cfg$max_iter), tol = as.numeric(cfg$tol),
    tau0 = as.numeric(rhs_control$anchor_tau0),
    anchor_tau0 = as.numeric(rhs_control$anchor_tau0),
    innovation_tau0 = as.numeric(rhs_control$innovation_tau0),
    anchor_init_tau = as.numeric(rhs_control$anchor_init_tau),
    innovation_init_tau = as.numeric(rhs_control$innovation_init_tau),
    rhs_freeze_iters = as.integer(rhs_control$freeze_iters),
    rhs_vb_inner = as.integer(rhs_control$vb_inner),
    a_sigma = as.numeric(cfg$a_sigma), b_sigma = as.numeric(cfg$b_sigma),
    alpha_min_spacing = 0, max_dense_dim = as.integer(cfg$max_dense_dim),
    init = fit_init
  )
  fit <- if (identical(cfg$likelihood_family, "al")) {
    do.call(app_joint_qvp_fit_al_vb_tiny, common)
  } else if (identical(cfg$likelihood_family, "exal")) {
    do.call(app_joint_exqdesn_fit_vb_dispatch, c(list(
      method_id = "VB1_structured_v",
      inherit_al_bootstrap_rhs = isTRUE(cfg$inherit_al_bootstrap_rhs)
    ), common))
  } else fail(sprintf("Unsupported likelihood family '%s'.", cfg$likelihood_family))
  elapsed <- proc.time()[["elapsed"]] - started

  beta <- as.numeric(fit$beta_mean)
  alpha <- as.numeric(fit$alpha_mean)
  sigma <- as.numeric(fit$sigma_mean)
  gamma <- if (is.null(fit$gamma_mean)) rep(NA_real_, length(quantiles)) else as.numeric(fit$gamma_mean)
  if (any(!is.finite(beta)) || any(!is.finite(alpha)) || any(!is.finite(sigma)) || any(sigma <= 0)) {
    fail("Joint VB returned nonfinite core summaries.")
  }
  pred_val <- app_pricefm_joint_predict(X_val, beta, alpha, quantiles)
  crossing <- app_joint_qvp_crossing_diagnostics(pred_val, quantiles)
  prediction_rows <- do.call(rbind, lapply(seq_along(quantiles), function(k) {
    data.frame(
      method_id = cfg$method_id, split = "val", origin_id = rows_val$origin_id,
      horizon = as.integer(rows_val$horizon), tau = quantiles[[k]],
      pred_scaled = as.numeric(pred_val[, k]), stringsAsFactors = FALSE
    )
  }))
  utils::write.csv(prediction_rows, file.path(out, "model_predictions_scaled.csv"), row.names = FALSE)
  utils::write.csv(fit$trace, file.path(out, "model_trace_summary.csv"), row.names = FALSE)
  utils::write.csv(fit$rhs_diagnostics, file.path(out, "rhs_block_diagnostics.csv"), row.names = FALSE)
  utils::write.csv(crossing, file.path(out, "crossing_diagnostics.csv"), row.names = FALSE)
  p <- ncol(Z_train)
  parameter_summary <- data.frame(
    method_id = cfg$method_id, tau = quantiles, alpha = alpha, sigma = sigma, gamma = gamma,
    beta_l2 = vapply(seq_along(quantiles), function(k) {
      idx <- ((k - 1L) * p + 1L):(k * p)
      sqrt(sum(beta[idx]^2))
    }, numeric(1L)), stringsAsFactors = FALSE
  )
  utils::write.csv(parameter_summary, file.path(out, "model_parameter_summary.csv"), row.names = FALSE)
  utils::write.csv(data.frame(
    method_id = cfg$method_id, model_family = "joint_qdesn_readout",
    likelihood_family = cfg$likelihood_family, prior_family = "rhs_ns",
    target_label = "joint_seven_quantile_validation", preserves_full_data_target = TRUE,
    approximate = TRUE, chunking_mode = "joint_vb_dense", converged = isTRUE(fit$converged),
    iter = nrow(fit$trace), train_seconds = as.numeric(elapsed), n_train = length(y_train),
    n_features = p, warm_start_enabled = !identical(initialization_mode, "controlled_cold"),
    warm_start_strategy = initialization_mode, stringsAsFactors = FALSE
  ), file.path(out, "model_method_summary.csv"), row.names = FALSE)

  state_fields <- intersect(c(
    "beta_mean", "beta_cov", "alpha_mean", "sigma_mean", "sigma_shape", "sigma_rate",
    "gamma_mean", "v_mean", "v_inv_mean", "u_mean", "u_inv_mean", "s_mean", "s2_mean",
    "block_moments", "rhs_state", "iterations_completed"
  ), names(fit))
  checkpoint <- list(
    format = "pricefm_joint_vb_checkpoint_v2", stage = "R61", case_id = cfg$case_id,
    source_case_id = cfg$source_case_id, likelihood_family = cfg$likelihood_family,
    method_id = cfg$method_id, beta = beta, alpha = alpha, sigma = sigma, gamma = gamma,
    rhs_state = fit$rhs_state, fit_state = fit[state_fields], tau = quantiles, p = p,
    intercept_removed = TRUE, source_config_sha256 = cfg$source_config_sha256,
    initialization_mode = initialization_mode, rhs_control = rhs_control
  )
  checkpoint_path <- file.path(out, "joint_vb_initialization.rds")
  saveRDS(checkpoint, checkpoint_path, compress = "xz")

  status <- system2(
    cfg$python_bin,
    c(cfg$summarizer, "--smoke-config", cfg$smoke_config, "--run-dir", out),
    stdout = file.path(out, "validation_summary.log"), stderr = file.path(out, "validation_summary.log")
  )
  if (!identical(status, 0L)) fail(sprintf("Validation summarizer failed with status %s.", status))
  metric <- utils::read.csv(file.path(out, "metric_summary.csv"), stringsAsFactors = FALSE)
  if (!any(metric$method_id == cfg$method_id & metric$split == "val")) {
    fail("Validation metric summary lacks the Stage-R61 method.")
  }

  source_manifest <- data.frame(
    label = c(
      "runtime_config", "source_config", "adapter_manifest", "vb_checkpoint_v2",
      "validation_metrics", "rhs_block_diagnostics"
    ),
    path = c(
      config_path, cfg$source_config, adapter_manifest_path, checkpoint_path,
      file.path(out, "metric_summary.csv"), file.path(out, "rhs_block_diagnostics.csv")
    ), stringsAsFactors = FALSE
  )
  if (nzchar(initializer_path)) {
    source_manifest <- rbind(source_manifest, data.frame(
      label = c("independent_initializer", "independent_initializer_diagnostics"),
      path = c(initializer_path, initializer_diagnostics_path), stringsAsFactors = FALSE
    ))
  }
  source_manifest$sha256 <- vapply(source_manifest$path, app_sha256_file, character(1L))
  source_manifest$bytes <- as.numeric(file.info(source_manifest$path)$size)
  source_manifest_path <- file.path(out, "source_manifest.csv")
  utils::write.csv(source_manifest, source_manifest_path, row.names = FALSE)

  change_columns <- grep("^max_.*_change$", names(fit$trace), value = TRUE)
  changes <- if (length(change_columns)) {
    apply(fit$trace[, change_columns, drop = FALSE], 1L, max, na.rm = TRUE)
  } else rep(NA_real_, nrow(fit$trace))
  valid_changes <- changes[is.finite(changes)]
  final_change <- if (length(valid_changes)) utils::tail(valid_changes, 1L) else NA_real_
  last5 <- utils::tail(valid_changes, 5L)
  slope <- if (length(last5) >= 2L) stats::coef(stats::lm(last5 ~ seq_along(last5)))[[2L]] else NA_real_
  payload <- list(
    status = "completed", stage = "R61", case_id = cfg$case_id,
    source_case_id = cfg$source_case_id, arm_id = cfg$arm_id,
    region = cfg$region, fold = as.integer(cfg$fold), likelihood_family = cfg$likelihood_family,
    method_id = cfg$method_id, initialization_mode = initialization_mode,
    rhs_control = rhs_control, n_train = length(y_train), n_validation = nrow(X_val),
    n_slopes = p, joint_dimension = length(beta), quantiles = quantiles,
    converged = isTRUE(fit$converged), iterations = nrow(fit$trace),
    iterations_completed = as.integer(fit$iterations_completed %||% nrow(fit$trace)),
    final_max_change = final_change, last5_change_slope = unname(slope),
    elapsed_seconds = as.numeric(elapsed), validation_crossing_rows = sum(crossing$n_crossing_pairs > 0),
    validation_crossing_pairs = sum(crossing$n_crossing_pairs), checkpoint = checkpoint_path,
    checkpoint_sha256 = app_sha256_file(checkpoint_path), output_checkpoint_format = checkpoint$format,
    source_manifest = source_manifest_path, source_manifest_sha256 = app_sha256_file(source_manifest_path),
    postfit_contract_pending = TRUE, split_firewall = "train_validation_only", test_accessed = FALSE,
    launch_origin = "user_authorization_required", registry_mutation_authorized = FALSE,
    article_mutation_authorized = FALSE
  )
  write_json(summary_path, payload)
  cat(jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE), "\n")
}

tryCatch(main(), error = function(e) fail(conditionMessage(e)))
