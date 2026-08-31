#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(yaml))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}

`%||%` <- function(x, y) if (is.null(x)) y else x

as_flag <- function(value, default = FALSE) {
  if (is.null(value)) return(default)
  tolower(as.character(value)) %in% c("1", "true", "yes", "y", "on")
}

find_repo_root <- function() {
  current <- normalizePath(getwd(), mustWork = TRUE)
  candidates <- c(
    current,
    normalizePath(file.path(current, ".."), mustWork = FALSE),
    normalizePath(file.path(current, "..", ".."), mustWork = FALSE),
    normalizePath(file.path(current, "..", "..", ".."), mustWork = FALSE)
  )
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "application", "config", "pricefm_data_pipeline.yaml"))) {
      return(candidate)
    }
  }
  stop("Could not locate the Article-Q-DESN repository root.", call. = FALSE)
}

r70_tau_key <- function(tau) {
  sub("\\.$", "", sub("0+$", "", sprintf("%.12f", as.numeric(tau))))
}

r70_tau_slug <- function(tau) {
  gsub("-", "m", gsub("\\.", "p", r70_tau_key(tau)))
}

r70_sha256 <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)
  output <- system2("sha256sum", path, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L
  if (!identical(as.integer(status), 0L) || !length(output)) {
    stop("Could not hash ", path, call. = FALSE)
  }
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

r70_atomic_path <- function(path) {
  paste0(path, ".tmp.", Sys.getpid())
}

r70_atomic_replace <- function(tmp, path) {
  if (!file.rename(tmp, path)) {
    if (file.exists(path)) unlink(path)
    if (!file.rename(tmp, path)) {
      unlink(tmp)
      stop("Atomic rename failed for ", path, call. = FALSE)
    }
  }
  invisible(path)
}

r70_atomic_write_csv <- function(frame, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- r70_atomic_path(path)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  utils::write.csv(frame, tmp, row.names = FALSE)
  r70_atomic_replace(tmp, path)
}

r70_atomic_write_json <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- r70_atomic_path(path)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  cat(jsonlite::toJSON(object, auto_unbox = TRUE, pretty = TRUE, null = "null"), file = tmp)
  cat("\n", file = tmp, append = TRUE)
  r70_atomic_replace(tmp, path)
}

r70_read_matrix <- function(path) {
  as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
}

r70_read_vector <- function(path) {
  as.numeric(r70_read_matrix(path)[, 1L])
}

r70_assert_runtime_manifest <- function(path, expected_sha256) {
  path <- normalizePath(path, mustWork = TRUE)
  manifest <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (!identical(as.character(manifest$status), "installed_exact_cran_exdqlm_1.1.1")) {
    stop("R70 requires the exact CRAN exdqlm 1.1.1 runtime.", call. = FALSE)
  }
  if (isTRUE(manifest$fork_source_used)) {
    stop("R70 must not use fork source for new fits.", call. = FALSE)
  }
  if (!identical(as.character(manifest$installed_package$version), "1.1.1") ||
      !identical(as.character(manifest$installed_package$repository), "CRAN")) {
    stop("R70 runtime package is not CRAN exdqlm 1.1.1.", call. = FALSE)
  }
  observed <- as.character(manifest$source_tarball$sha256)
  if (!identical(observed, expected_sha256)) {
    stop("R70 CRAN tarball SHA-256 mismatch.", call. = FALSE)
  }
  manifest
}

r70_bool_blocked <- function(stage, name) {
  isTRUE(stage[[name]] %||% FALSE)
}

r70_assert_config <- function(cfg, stage) {
  expected_quantiles <- c(0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
  quantiles <- as.numeric(unlist(cfg$quantiles, use.names = FALSE))
  if (!identical(as.character(cfg$splits), c("train", "val"))) {
    stop("R70 permits exactly train and validation splits.", call. = FALSE)
  }
  if (!identical(quantiles, expected_quantiles)) {
    stop("R70 requires the ordered seven-quantile PriceFM grid.", call. = FALSE)
  }
  if (!identical(as.character(cfg$qdesn_vb$likelihoods), c("al", "exal"))) {
    stop("R70 requires AL and exAL VB refits.", call. = FALSE)
  }
  if (!identical(as.character(cfg$package_authority), "exact_CRAN_exdqlm_1.1.1_public_API")) {
    stop("R70 requires exact CRAN exdqlm 1.1.1 public API authority.", call. = FALSE)
  }
  blocked <- c(
    "launch_authorized", "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized"
  )
  for (name in blocked) {
    if (r70_bool_blocked(stage, name)) {
      stop("R70 config must keep ", name, " declaratively false.", call. = FALSE)
    }
  }
  invisible(quantiles)
}

r70_safe_beta <- function(fit) {
  beta <- as.numeric(fit$qbeta$m %||% numeric())
  if (!length(beta) || any(!is.finite(beta))) {
    stop("Fit lacks finite qbeta means.", call. = FALSE)
  }
  beta
}

r70_safe_cov_diag <- function(fit) {
  covariance <- as.matrix(fit$qbeta$V %||% matrix(numeric(), 0L, 0L))
  if (!length(covariance)) return(numeric())
  diag(covariance)
}

r70_safe_sigma <- function(fit) {
  value <- fit$qsig$E_sigma %||% fit$qsiggam$sigma_mean %||% fit$omega2$mean %||% NA_real_
  value <- as.numeric(value)[1L]
  if (!is.null(fit$omega2$mean) && is.null(fit$qsiggam$sigma_mean) && is.null(fit$qsig$E_sigma)) {
    value <- sqrt(max(value, .Machine$double.eps))
  }
  if (!is.finite(value) || value <= 0) NA_real_ else value
}

r70_safe_gamma <- function(fit) {
  value <- as.numeric(fit$qsiggam$gamma_mean %||% fit$qgam$E_gamma %||% fit$gamma %||% NA_real_)[1L]
  if (!is.finite(value)) NA_real_ else value
}

r70_control_audit <- function(fit) {
  attr(fit, "r67_control_audit") %||% list()
}

r70_sigmagam_telemetry <- function(fit) {
  misc <- fit$misc %||% list()
  audit <- r70_control_audit(fit)
  list(
    factorization = as.character(fit$qsiggam$factorization %||% NA_character_),
    configured_factorization = as.character((misc$sigmagam %||% list())$factorization %||% NA_character_),
    update_count = as.integer(misc$sigmagam_update_count %||% 0L),
    postwarmup_update_count = as.integer(misc$sigmagam_postwarmup_update_count %||% 0L),
    required_postwarmup_updates = as.integer(misc$sigmagam_required_postwarmup_updates %||% 0L),
    first_active_iter = as.integer(misc$sigmagam_first_active_iter %||% NA_integer_),
    public_api = as.character(audit$public_api %||% "exalStaticLDVB"),
    exact_chunking_claimed = isTRUE(audit$exact_chunking_claimed),
    ignored_fork_controls = paste(as.character(audit$ignored_fork_controls %||% character()), collapse = "+"),
    gamma = r70_safe_gamma(fit),
    sigma = r70_safe_sigma(fit)
  )
}

r70_method_row <- function(fit, method_id, likelihood, tau, n_train, n_features,
                           init_source, package_contract) {
  telemetry <- r70_sigmagam_telemetry(fit)
  data.frame(
    method_id = method_id,
    model_family = "independent_qdesn_static_readout",
    likelihood_family = likelihood,
    prior_family = "rhs_ns",
    tau = as.numeric(tau),
    inference_engine = "VB",
    posterior_approximation = if (identical(likelihood, "exal")) {
      "cran111_structured_sigmagam_if_supported"
    } else {
      "cran111_al_variational"
    },
    data_target_approximation = FALSE,
    exact_chunking = FALSE,
    chunking_mode = "not_claimed_under_cran111_public_api",
    converged = isTRUE(fit$converged %||% TRUE),
    iter = as.integer(fit$iter %||% NA_integer_),
    train_seconds = as.numeric(attr(fit, "r67_elapsed_seconds") %||% fit$run.time %||% NA_real_),
    n_train = as.integer(n_train),
    n_features = as.integer(n_features),
    readout_mode = "case_specific_static_readout",
    init_source = init_source,
    package_library = package_contract$library,
    package_version = package_contract$version,
    package_repository = package_contract$repository,
    public_api = telemetry$public_api,
    sigmagam_factorization = telemetry$factorization,
    sigmagam_configured_factorization = telemetry$configured_factorization,
    sigmagam_update_count = telemetry$update_count,
    sigmagam_postwarmup_update_count = telemetry$postwarmup_update_count,
    sigmagam_required_postwarmup_updates = telemetry$required_postwarmup_updates,
    sigmagam_first_active_iter = telemetry$first_active_iter,
    exact_chunking_claimed = telemetry$exact_chunking_claimed,
    ignored_fork_controls = telemetry$ignored_fork_controls,
    binary_model_artifact_written = FALSE,
    stringsAsFactors = FALSE
  )
}

r70_warm_row <- function(fit, method_id, likelihood, tau, init_source, init_components) {
  data.frame(
    method_id = method_id,
    likelihood_family = likelihood,
    tau = as.numeric(tau),
    init_source = init_source,
    init_components = paste(init_components, collapse = "+"),
    fallback_used = FALSE,
    converged = isTRUE(fit$converged %||% TRUE),
    iter = as.integer(fit$iter %||% NA_integer_),
    stringsAsFactors = FALSE
  )
}

r70_parameter_row <- function(fit, method_id, likelihood, tau) {
  beta <- r70_safe_beta(fit)
  covariance_diag <- r70_safe_cov_diag(fit)
  data.frame(
    method_id = method_id,
    likelihood_family = likelihood,
    tau = as.numeric(tau),
    beta_l2 = sqrt(sum(beta^2)),
    beta_max_abs = max(abs(beta)),
    beta_cov_trace = if (length(covariance_diag)) sum(covariance_diag) else NA_real_,
    sigma = r70_safe_sigma(fit),
    gamma = r70_safe_gamma(fit),
    stringsAsFactors = FALSE
  )
}

r70_beta_mean_frame <- function(fit, method_id, likelihood, tau) {
  beta <- r70_safe_beta(fit)
  data.frame(
    method_id = method_id,
    likelihood_family = likelihood,
    tau = as.numeric(tau),
    feature_index = seq_along(beta),
    beta_mean = beta,
    stringsAsFactors = FALSE
  )
}

r70_beta_cov_diag_frame <- function(fit, method_id, likelihood, tau) {
  diag_values <- r70_safe_cov_diag(fit)
  if (!length(diag_values)) {
    return(data.frame(
      method_id = character(),
      likelihood_family = character(),
      tau = numeric(),
      feature_index = integer(),
      beta_cov_diag = numeric(),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    method_id = method_id,
    likelihood_family = likelihood,
    tau = as.numeric(tau),
    feature_index = seq_along(diag_values),
    beta_cov_diag = diag_values,
    stringsAsFactors = FALSE
  )
}

r70_trace_value <- function(x, i, mode = c("numeric", "logical", "character")) {
  mode <- match.arg(mode)
  if (is.null(x) || length(x) < i) {
    return(switch(mode, numeric = NA_real_, logical = NA, character = NA_character_))
  }
  switch(mode, numeric = as.numeric(x[[i]]), logical = as.logical(x[[i]]), character = as.character(x[[i]]))
}

r70_trace_frame <- function(fit, method_id, likelihood, tau) {
  misc <- fit$misc %||% list()
  n <- max(
    as.integer(fit$iter %||% 0L),
    length(misc$elbo_trace %||% numeric()),
    length(misc$sigma_trace %||% numeric()),
    length(misc$sigmagam_update_performed_trace %||% logical()),
    1L
  )
  do.call(rbind, lapply(seq_len(n), function(i) {
    data.frame(
      method_id = method_id,
      likelihood_family = likelihood,
      tau = as.numeric(tau),
      iter = i,
      elbo = r70_trace_value(misc$elbo_trace %||% misc$elbo, i),
      sigma = r70_trace_value(misc$sigma_trace, i),
      gamma = r70_trace_value(misc$gamma_trace, i),
      parameter_change = r70_trace_value(misc$new_term_trace, i),
      rhs_tau = r70_trace_value(misc$rhs_tau_trace, i),
      rhs_c2 = r70_trace_value(misc$rhs_c2_trace, i),
      rhs_lambda_mean = r70_trace_value(misc$rhs_lambda_mean_trace, i),
      sigmagam_frozen = r70_trace_value(misc$sigmagam_frozen_trace, i, "logical"),
      sigmagam_update_performed = r70_trace_value(misc$sigmagam_update_performed_trace, i, "logical"),
      sigmagam_update_reason = r70_trace_value(misc$sigmagam_update_reason_trace, i, "character"),
      stringsAsFactors = FALSE
    )
  }))
}

r70_prediction_frame <- function(fit, X, rows, method_id, tau, split = "val") {
  prediction <- as.numeric(as.matrix(X) %*% r70_safe_beta(fit))
  if (length(prediction) != nrow(rows)) {
    stop("Prediction/row mismatch for ", method_id, " at tau ", tau, call. = FALSE)
  }
  data.frame(
    method_id = method_id,
    split = split,
    origin_id = rows$origin_id,
    horizon = rows$horizon,
    tau = as.numeric(tau),
    pred_scaled = prediction,
    stringsAsFactors = FALSE
  )
}

r70_sha_or_empty <- function(path) {
  if (file.exists(path)) r70_sha256(path) else ""
}

repo_root <- find_repo_root()
config_path <- get_arg("--case-config")
python_bin_override <- get_arg("--python-bin", NULL)
force <- as_flag(get_arg("--force", "false"))
preflight_only <- as_flag(get_arg("--preflight-only", "false"))

if (is.null(config_path)) stop("--case-config is required.", call. = FALSE)
config_path <- normalizePath(config_path, mustWork = TRUE)
payload <- yaml::read_yaml(config_path)
cfg <- payload$pricefm_desn_smoke
r69b <- payload$pricefm_stage_r69b
if (is.null(cfg) || is.null(r69b)) {
  stop("Config must contain pricefm_desn_smoke and pricefm_stage_r69b blocks.", call. = FALSE)
}

quantiles <- r70_assert_config(cfg, r69b)
expected_cran_sha <- "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
runtime_manifest_path <- normalizePath(cfg$runtime_manifest, mustWork = TRUE)
runtime_manifest <- r70_assert_runtime_manifest(runtime_manifest_path, expected_cran_sha)

adapter_script <- file.path(repo_root, "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R")
source(adapter_script, local = TRUE)
package_contract <- r67_assert_cran_package(cfg$r_library, expected_version = "1.1.1")

if (isTRUE(preflight_only)) {
  cat(jsonlite::toJSON(list(
    status = "r70_case_preflight_passed",
    case_id = as.character(r69b$case_id),
    region = as.character(cfg$region),
    fold = as.integer(cfg$fold),
    configured_splits = as.character(cfg$splits),
    quantiles = quantiles,
    package_authority = as.character(cfg$package_authority),
    package_version = package_contract$version,
    package_repository = package_contract$repository,
    public_api = "exalStaticLDVB",
    fork_only_namespace_calls_authorized = FALSE,
    test_loaded = FALSE,
    binary_model_artifacts_written = FALSE
  ), auto_unbox = TRUE, pretty = TRUE), "\n")
  quit(save = "no", status = 0L)
}

config_sha256 <- r70_sha256(config_path)
adapter_dir <- normalizePath(cfg$adapter$output_dir, mustWork = FALSE)
out_dir <- normalizePath(cfg$run$output_dir, mustWork = FALSE)
if (isTRUE(force) && dir.exists(out_dir)) unlink(out_dir, recursive = TRUE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(file.path(adapter_dir, "adapter_manifest.json"))) {
  python_bin <- python_bin_override %||% cfg$python_bin
  python_bin <- normalizePath(path.expand(as.character(python_bin)), mustWork = TRUE)
  build_script <- file.path(repo_root, "application/scripts/pricefm/07_build_desn_direct_horizon_adapter.py")
  status <- system2(
    python_bin,
    c(build_script, "--smoke-config", config_path, "--force", "true")
  )
  if (!identical(status, 0L)) stop("R70 adapter build failed.", call. = FALSE)
}

for (forbidden in c("X_test.csv", "y_test.csv", "rows_test.csv")) {
  if (file.exists(file.path(adapter_dir, forbidden))) {
    stop("Test firewall violation in adapter: ", forbidden, call. = FALSE)
  }
}

X_train <- r70_read_matrix(file.path(adapter_dir, "X_train.csv"))
y_train <- r70_read_vector(file.path(adapter_dir, "y_train.csv"))
X_val <- r70_read_matrix(file.path(adapter_dir, "X_val.csv"))
rows_val <- utils::read.csv(file.path(adapter_dir, "rows_val.csv"), stringsAsFactors = FALSE)
if (nrow(X_train) != length(y_train) || nrow(X_val) != nrow(rows_val) || ncol(X_train) != ncol(X_val)) {
  stop("R70 adapter dimensions are inconsistent.", call. = FALSE)
}
if (any(!is.finite(X_train)) || any(!is.finite(y_train)) || any(!is.finite(X_val))) {
  stop("R70 adapter matrices contain non-finite values.", call. = FALSE)
}

rhs <- r67_rhs_controls(cfg$rhs_ns)
qcfg <- cfg$qdesn_vb
profile <- qcfg$sigmagam
method_al <- as.character(r69b$method_ids$al)
method_exal <- as.character(r69b$method_ids$exal)
base_seed <- as.integer(cfg$run$seed %||% 20260831L)

component_rows <- list()
pred_rows <- list()
method_rows <- list()
warm_rows <- list()
param_rows <- list()
trace_rows <- list()
beta_mean_rows <- list()
beta_cov_diag_rows <- list()

for (index in seq_along(quantiles)) {
  tau <- quantiles[[index]]
  component_dir <- file.path(out_dir, "components", paste0("tau=", r70_tau_slug(tau)))
  dir.create(component_dir, recursive = TRUE, showWarnings = FALSE)

  al_fit <- r67_fit_quantile(
    cfg$r_library,
    X_train,
    y_train,
    tau = tau,
    likelihood = "al",
    rhs = rhs,
    qcfg = qcfg,
    profile = NULL,
    init = NULL,
    seed = base_seed + index * 100L + 1L
  )
  al_prediction <- r70_prediction_frame(al_fit, X_val, rows_val, method_al, tau)
  al_method <- r70_method_row(
    al_fit, method_al, "al", tau, nrow(X_train), ncol(X_train),
    "none_cran111_public_api", package_contract
  )
  al_warm <- r70_warm_row(al_fit, method_al, "al", tau, "none_cran111_public_api", character())
  al_param <- r70_parameter_row(al_fit, method_al, "al", tau)
  al_trace <- r70_trace_frame(al_fit, method_al, "al", tau)
  al_beta <- r70_beta_mean_frame(al_fit, method_al, "al", tau)
  al_cov <- r70_beta_cov_diag_frame(al_fit, method_al, "al", tau)

  exal_init <- r67_init_from_fit(al_fit, gamma_zero = TRUE)
  exal_fit <- r67_fit_quantile(
    cfg$r_library,
    X_train,
    y_train,
    tau = tau,
    likelihood = "exal",
    rhs = rhs,
    qcfg = qcfg,
    profile = profile,
    init = exal_init,
    seed = base_seed + index * 100L + 2L
  )
  exal_prediction <- r70_prediction_frame(exal_fit, X_val, rows_val, method_exal, tau)
  exal_method <- r70_method_row(
    exal_fit, method_exal, "exal", tau, nrow(X_train), ncol(X_train),
    paste0("same_tau_al_", r70_tau_key(tau)), package_contract
  )
  exal_warm <- r70_warm_row(
    exal_fit, method_exal, "exal", tau,
    paste0("same_tau_al_", r70_tau_key(tau)),
    names(exal_init)
  )
  exal_param <- r70_parameter_row(exal_fit, method_exal, "exal", tau)
  exal_trace <- r70_trace_frame(exal_fit, method_exal, "exal", tau)
  exal_beta <- r70_beta_mean_frame(exal_fit, method_exal, "exal", tau)
  exal_cov <- r70_beta_cov_diag_frame(exal_fit, method_exal, "exal", tau)
  telemetry <- r70_sigmagam_telemetry(exal_fit)

  r70_atomic_write_csv(al_prediction, file.path(component_dir, "al_predictions_scaled.csv"))
  r70_atomic_write_csv(exal_prediction, file.path(component_dir, "exal_predictions_scaled.csv"))
  r70_atomic_write_csv(al_method, file.path(component_dir, "al_method_summary.csv"))
  r70_atomic_write_csv(exal_method, file.path(component_dir, "exal_method_summary.csv"))
  r70_atomic_write_csv(al_warm, file.path(component_dir, "al_warm_start.csv"))
  r70_atomic_write_csv(exal_warm, file.path(component_dir, "exal_warm_start.csv"))
  r70_atomic_write_csv(al_param, file.path(component_dir, "al_parameter_summary.csv"))
  r70_atomic_write_csv(exal_param, file.path(component_dir, "exal_parameter_summary.csv"))
  r70_atomic_write_csv(al_trace, file.path(component_dir, "al_trace.csv"))
  r70_atomic_write_csv(exal_trace, file.path(component_dir, "exal_trace.csv"))
  r70_atomic_write_csv(al_beta, file.path(component_dir, "al_beta_mean.csv"))
  r70_atomic_write_csv(exal_beta, file.path(component_dir, "exal_beta_mean.csv"))
  r70_atomic_write_csv(al_cov, file.path(component_dir, "al_beta_cov_diag.csv"))
  r70_atomic_write_csv(exal_cov, file.path(component_dir, "exal_beta_cov_diag.csv"))

  component_status <- list(
    case_id = as.character(r69b$case_id),
    region = as.character(cfg$region),
    fold = as.integer(cfg$fold),
    tau = as.numeric(tau),
    al_converged = isTRUE(al_fit$converged %||% TRUE),
    exal_converged = isTRUE(exal_fit$converged %||% TRUE),
    public_api = "exalStaticLDVB",
    package_version = package_contract$version,
    package_repository = package_contract$repository,
    exal_sigmagam_factorization = telemetry$factorization,
    exal_sigmagam_configured_factorization = telemetry$configured_factorization,
    exal_sigmagam_update_count = telemetry$update_count,
    exal_sigmagam_postwarmup_update_count = telemetry$postwarmup_update_count,
    exal_sigmagam_required_postwarmup_updates = telemetry$required_postwarmup_updates,
    exal_sigma = telemetry$sigma,
    exal_gamma = telemetry$gamma,
    al_prediction_sha256 = r70_sha_or_empty(file.path(component_dir, "al_predictions_scaled.csv")),
    exal_prediction_sha256 = r70_sha_or_empty(file.path(component_dir, "exal_predictions_scaled.csv")),
    terminal = TRUE,
    selection_eligible = isTRUE(al_fit$converged %||% TRUE) &&
      isTRUE(exal_fit$converged %||% TRUE) &&
      all(is.finite(al_prediction$pred_scaled)) &&
      all(is.finite(exal_prediction$pred_scaled)),
    binary_model_artifact_written = FALSE
  )
  r70_atomic_write_json(component_status, file.path(component_dir, "component_terminal.json"))
  component_rows[[length(component_rows) + 1L]] <- as.data.frame(component_status, stringsAsFactors = FALSE)
  pred_rows[[length(pred_rows) + 1L]] <- al_prediction
  pred_rows[[length(pred_rows) + 1L]] <- exal_prediction
  method_rows[[length(method_rows) + 1L]] <- al_method
  method_rows[[length(method_rows) + 1L]] <- exal_method
  warm_rows[[length(warm_rows) + 1L]] <- al_warm
  warm_rows[[length(warm_rows) + 1L]] <- exal_warm
  param_rows[[length(param_rows) + 1L]] <- al_param
  param_rows[[length(param_rows) + 1L]] <- exal_param
  trace_rows[[length(trace_rows) + 1L]] <- al_trace
  trace_rows[[length(trace_rows) + 1L]] <- exal_trace
  beta_mean_rows[[length(beta_mean_rows) + 1L]] <- al_beta
  beta_mean_rows[[length(beta_mean_rows) + 1L]] <- exal_beta
  beta_cov_diag_rows[[length(beta_cov_diag_rows) + 1L]] <- al_cov
  beta_cov_diag_rows[[length(beta_cov_diag_rows) + 1L]] <- exal_cov
  rm(al_fit, exal_fit)
  gc(verbose = FALSE)
}

component_frame <- do.call(rbind, component_rows)
r70_atomic_write_csv(do.call(rbind, pred_rows), file.path(out_dir, "model_predictions_scaled.csv"))
r70_atomic_write_csv(do.call(rbind, method_rows), file.path(out_dir, "model_method_summary.csv"))
r70_atomic_write_csv(do.call(rbind, warm_rows), file.path(out_dir, "warm_start_diagnostics.csv"))
r70_atomic_write_csv(do.call(rbind, param_rows), file.path(out_dir, "model_parameter_summary.csv"))
r70_atomic_write_csv(do.call(rbind, trace_rows), file.path(out_dir, "model_trace_summary.csv"))
r70_atomic_write_csv(do.call(rbind, beta_mean_rows), file.path(out_dir, "model_beta_mean.csv"))
r70_atomic_write_csv(do.call(rbind, beta_cov_diag_rows), file.path(out_dir, "model_beta_cov_diag.csv"))
r70_atomic_write_csv(component_frame, file.path(out_dir, "r70_component_status.csv"))

r70_atomic_write_json(list(
  status = if (all(component_frame$selection_eligible)) {
    "completed_all_components_eligible"
  } else {
    "completed_with_quarantined_components"
  },
  case_id = as.character(r69b$case_id),
  region = as.character(cfg$region),
  fold = as.integer(cfg$fold),
  quantiles = quantiles,
  terminal_components = nrow(component_frame),
  eligible_components = sum(component_frame$selection_eligible),
  likelihoods = c("al", "exal"),
  package_authority = "exact_CRAN_exdqlm_1.1.1_public_API",
  public_api = "exalStaticLDVB",
  test_loaded = FALSE,
  binary_model_artifacts_written = FALSE,
  registry_mutation_authorized = FALSE,
  article_mutation_authorized = FALSE,
  joint_model_authorized = FALSE,
  mcmc_authorized = FALSE
), file.path(out_dir, "r70_case_fit_summary.json"))

r70_atomic_write_json(list(
  stage = "R70",
  source_stage = "R69B",
  case_id = as.character(r69b$case_id),
  config = config_path,
  config_sha256 = config_sha256,
  adapter_dir = adapter_dir,
  adapter_manifest_sha256 = r70_sha_or_empty(file.path(adapter_dir, "adapter_manifest.json")),
  output_dir = out_dir,
  runtime_manifest = runtime_manifest_path,
  runtime_manifest_sha256 = r70_sha256(runtime_manifest_path),
  runtime_adapter_script = adapter_script,
  runtime_adapter_script_sha256 = r70_sha256(adapter_script),
  package_contract = package_contract[c("library", "package_path", "version", "repository", "packaged")],
  cran_tarball_sha256 = runtime_manifest$source_tarball$sha256,
  method_ids = r69b$method_ids,
  selected_family_anchor = r69b$selected_family_anchor,
  refit_priority = r69b$refit_priority,
  source_r69a_anchor_sha256 = r69b$source_r69a_anchor_sha256,
  source_r69a_component_sha256 = r69b$source_r69a_component_sha256,
  qdesn_vb = list(
    max_iter = qcfg$max_iter,
    tol = qcfg$tol,
    n_samp = qcfg$n_samp,
    n_samp_xi = qcfg$n_samp_xi,
    sigmagam = qcfg$sigmagam,
    ignored_legacy_controls_under_cran111 = qcfg$ignored_legacy_controls_under_cran111
  ),
  rhs_ns = rhs,
  quantiles = quantiles,
  configured_splits = c("train", "val"),
  evaluation_splits = c("val"),
  test_loaded = FALSE,
  binary_model_artifacts_written = FALSE
), file.path(out_dir, "run_manifest.json"))

cat(out_dir, "\n")
