#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}
`%||%` <- function(x, y) if (is.null(x)) y else x
as_flag <- function(x) tolower(as.character(x %||% "false")) %in% c("1", "true", "yes")

atomic_replace <- function(tmp, path) {
  if (!file.rename(tmp, path)) {
    if (file.exists(path)) unlink(path)
    if (!file.rename(tmp, path)) stop("Atomic rename failed: ", path, call. = FALSE)
  }
}
write_json <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  cat(jsonlite::toJSON(value, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n", file = tmp)
  atomic_replace(tmp, path)
}
write_csv <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  utils::write.csv(value, tmp, row.names = FALSE)
  atomic_replace(tmp, path)
}
sha256 <- function(path) {
  output <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])
record_rows <- function(records) {
  if (is.data.frame(records)) {
    return(lapply(seq_len(nrow(records)), function(index) as.list(records[index, , drop = FALSE])))
  }
  records
}

task_path <- get_arg("--task-config")
code_root <- get_arg("--code-root")
preflight_only <- as_flag(get_arg("--preflight-only", "false"))
if (is.null(task_path) || is.null(code_root)) {
  stop("--task-config and --code-root are required.", call. = FALSE)
}
task_path <- normalizePath(task_path, mustWork = TRUE)
code_root <- normalizePath(code_root, mustWork = TRUE)
task <- jsonlite::read_json(task_path, simplifyVector = TRUE)
output <- normalizePath(task$output_dir, mustWork = FALSE)
terminal_path <- file.path(output, "terminal.json")

run_task <- function() {
  blocked <- c(
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized"
  )
  if (!identical(as.character(task$stage), "R94") ||
      !identical(as.character(task$likelihood_family), "exal") ||
      !identical(as.character(task$selection_split), "val") ||
      !identical(as.character(task$warm_start_mode), "al_qbeta_rhs_latent_first") ||
      !identical(task$test_opened, FALSE) ||
      !identical(task$test_access_authorized, FALSE) ||
      any(vapply(blocked, function(name) isTRUE(task[[name]]), logical(1L)))) {
    stop("R94 task firewall violation.", call. = FALSE)
  }
  sources <- list(
    c("source_r93_task", "source_r93_task_sha256"),
    c("runtime_manifest", "runtime_manifest_sha256"),
    c("audit_summary", "audit_summary_sha256"),
    c("al_beta_path", "al_beta_sha256"),
    c("al_parameter_path", "al_parameter_sha256"),
    c("al_prediction_path", "al_prediction_sha256"),
    c("al_source_terminal", "al_source_terminal_sha256"),
    c("runner_script", "runner_script_sha256")
  )
  for (pair in sources) {
    if (!identical(sha256(task[[pair[[1L]]]]), as.character(task[[pair[[2L]]]]))) {
      stop("R94 immutable source hash mismatch: ", pair[[1L]], call. = FALSE)
    }
  }
  adapter_file_count <- if (is.data.frame(task$adapter_files)) nrow(task$adapter_files) else length(task$adapter_files)
  if (is.null(task$adapter_files) || adapter_file_count < 9L) {
    stop("R94 adapter-file provenance is incomplete.", call. = FALSE)
  }
  adapter_file_records <- record_rows(task$adapter_files)
  for (record in adapter_file_records) {
    if (!identical(sha256(record$path), as.character(record$sha256))) {
      stop("R94 adapter hash mismatch: ", record$path, call. = FALSE)
    }
  }
  adapter_script_count <- if (is.data.frame(task$adapter_scripts)) nrow(task$adapter_scripts) else length(task$adapter_scripts)
  if (is.null(task$adapter_scripts) || adapter_script_count != 3L) {
    stop("R94 public-API adapter-script provenance is incomplete.", call. = FALSE)
  }
  adapter_script_records <- record_rows(task$adapter_scripts)
  for (record in adapter_script_records) {
    if (!identical(sha256(record$path), as.character(record$sha256))) {
      stop("R94 public-API adapter-script hash mismatch: ", record$path, call. = FALSE)
    }
  }
  runtime <- jsonlite::read_json(task$runtime_manifest, simplifyVector = TRUE)
  expected_repair <- paste0(
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-",
    "plus-structured-plugin-init-plus-coherent-al-latent-init"
  )
  if (!identical(runtime$status, "installed_coherent_exal_initialization_runtime") ||
      !identical(runtime$version, "1.1.1.9005") ||
      !identical(runtime$repair, expected_repair) ||
      !identical(runtime$warm_start_mode, "al_qbeta_rhs_latent_first") ||
      isTRUE(runtime$launch_authorized) || isTRUE(runtime$test_access_authorized)) {
    stop("R94 runtime provenance is invalid.", call. = FALSE)
  }
  audit <- jsonlite::read_json(task$audit_summary, simplifyVector = TRUE)
  if (!isTRUE(audit$production_refit_preparation_authorized) || isTRUE(audit$test_opened)) {
    stop("R94 audit has not authorized production refit preparation.", call. = FALSE)
  }
  options(
    pricefm.expected_exdqlm_version = "1.1.1.9005",
    pricefm.expected_exdqlm_repair = expected_repair
  )
  for (record in adapter_script_records) source(record$path, local = TRUE)
  package <- r75_assert_repair_package(task$r_library)

  adapter <- normalizePath(task$adapter_dir, mustWork = TRUE)
  forbidden <- file.path(adapter, c("X_test.csv", "y_test.csv", "rows_test.csv"))
  if (any(file.exists(forbidden))) stop("R94 adapter test firewall violation.", call. = FALSE)
  X_train <- read_matrix(file.path(adapter, "X_train.csv"))
  y_train <- read_vector(file.path(adapter, "y_train.csv"))
  X_val <- read_matrix(file.path(adapter, "X_val.csv"))
  rows_val <- utils::read.csv(file.path(adapter, "rows_val.csv"), stringsAsFactors = FALSE)
  if (nrow(X_train) != length(y_train) || ncol(X_train) != ncol(X_val) ||
      nrow(X_val) != nrow(rows_val) || any(!is.finite(X_train)) ||
      any(!is.finite(y_train)) || any(!is.finite(X_val))) {
    stop("R94 adapter dimensions or values are invalid.", call. = FALSE)
  }
  beta_frame <- utils::read.csv(task$al_beta_path, stringsAsFactors = FALSE)
  parameter <- utils::read.csv(task$al_parameter_path, stringsAsFactors = FALSE)
  beta_init <- as.numeric(beta_frame$beta_mean)
  beta_cov_diag_init <- as.numeric(beta_frame$beta_cov_diag)
  sigma_init <- as.numeric(parameter$sigma[[1L]])
  if (length(beta_init) != ncol(X_train) || length(beta_cov_diag_init) != ncol(X_train) ||
      any(!is.finite(beta_init)) || any(!is.finite(beta_cov_diag_init)) ||
      any(beta_cov_diag_init <= 0) || !is.finite(sigma_init) || sigma_init <= 0) {
    stop("R94 coherent AL warm start is incomplete.", call. = FALSE)
  }
  if (preflight_only) {
    cat(jsonlite::toJSON(list(
      status = "preflight_passed_not_fitted", task_id = task$task_id,
      package = package, n_train = nrow(X_train), n_features = ncol(X_train),
      warm_start_mode = task$warm_start_mode, test_loaded = FALSE,
      test_opened = FALSE, test_access_authorized = FALSE,
      binary_model_artifacts_written = FALSE
    ), auto_unbox = TRUE, pretty = TRUE), "\n")
    return(invisible(NULL))
  }

  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  write_json(list(
    status = "started", task_id = task$task_id, pid = Sys.getpid(),
    task_config = task_path, task_config_sha256 = sha256(task_path), test_loaded = FALSE,
    test_opened = FALSE, test_access_authorized = FALSE
  ), file.path(output, "started.json"))
  rhs <- list(
    tau0 = as.numeric(task$rhs_tau0), init_tau = as.numeric(task$rhs_init_tau),
    freeze_tau_iters = as.integer(task$rhs_freeze_tau_iters),
    freeze_tau_warmup_iters = as.integer(task$rhs_freeze_tau_warmup_iters),
    shrink_intercept = FALSE
  )
  qcfg <- list(
    max_iter = as.integer(task$max_iter), tol = as.numeric(task$tol),
    n_samp = as.integer(task$n_samp), n_samp_xi = as.integer(task$n_samp_xi),
    verbose = FALSE, prior_sigma = list(a = 1, b = 1),
    prior_gamma = list(mu0 = 0, s20 = 10)
  )
  profile <- list(
    factorization = "structured",
    structured_grid_size = as.integer(task$structured_grid_size),
    structured_span_sd = as.numeric(task$structured_span_sd),
    freeze_warmup_iters = 0L, force_after_warmup = TRUE,
    postwarmup_damping = as.numeric(task$postwarmup_damping),
    postwarmup_damping_iters = as.integer(task$postwarmup_damping_iters),
    min_postwarmup_updates = as.integer(task$min_postwarmup_updates)
  )
  fit <- r75_fit_quantile(
    task$r_library, X_train, y_train, task$tau, rhs, qcfg, profile,
    init = list(
      beta = beta_init, beta_cov_diag = beta_cov_diag_init,
      sigma = sigma_init, gamma = 0,
      warm_start_mode = "al_qbeta_rhs_latent_first"
    ),
    seed = task$seed
  )
  beta <- as.numeric(fit$qbeta$m)
  covariance <- as.matrix(fit$qbeta$V)
  sigma <- as.numeric(fit$qsiggam$sigma_mean)
  gamma <- as.numeric(fit$qsiggam$gamma_mean)
  prediction <- as.numeric(X_val %*% beta)
  trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
  deltas <- fit$diagnostics$deltas %||% list()
  if (nrow(trace)) {
    trace$delta_state_relative <- as.numeric(deltas$state_relative)
    trace$delta_prediction_scaled <- as.numeric(deltas$prediction_scaled)
  }
  updates <- as.integer(fit$diagnostics$ld_block$sigmagam$update_count %||% 0L)
  required <- c(
    "sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s",
    "delta_state_relative", "delta_prediction_scaled"
  )
  trace_complete <- nrow(trace) > 0L && all(required %in% names(trace))
  trace_finite <- trace_complete && all(is.finite(as.matrix(trace[, required, drop = FALSE])))
  init_l2 <- sqrt(sum(beta_init^2))
  beta_ratio <- sqrt(sum(beta^2)) / max(init_l2, .Machine$double.eps)
  first_state <- if (trace_complete) abs(trace$delta_state[[1L]]) else Inf
  tail <- if (trace_complete) utils::tail(trace, 10L) else data.frame()
  tail_state <- if (nrow(tail)) max(abs(tail$delta_state)) else Inf
  tail_sigma <- if (nrow(tail)) max(abs(tail$delta_sigma)) else Inf
  tail_relative <- if (nrow(tail)) max(abs(tail$delta_state_relative)) else Inf
  tail_prediction <- if (nrow(tail)) max(abs(tail$delta_prediction_scaled)) else Inf
  contraction <- tail_state / max(first_state, .Machine$double.eps)
  finite_core <- all(is.finite(beta)) && all(is.finite(covariance)) &&
    is.finite(sigma) && sigma > 0 && is.finite(gamma) && all(is.finite(prediction))
  checks <- list(
    finite_core = finite_core,
    trace_complete = trace_complete,
    trace_finite = trace_finite,
    coherent_warm_start_recorded = isTRUE(fit$misc$coherent_al_init) &&
      isTRUE(fit$misc$latent_first_initialized) &&
      identical(fit$misc$beta_covariance_source, "al_beta_cov_diag"),
    structured_updates_at_least_35 = updates >= 35L,
    sigma_below_100 = is.finite(sigma) && sigma < 100,
    gamma_bounded = is.finite(gamma) && abs(gamma) < 4,
    beta_l2_ratio_below_10 = is.finite(beta_ratio) && beta_ratio < 10,
    tail_state_sigma_delta_below_2 = is.finite(max(tail_state, tail_sigma)) &&
      max(tail_state, tail_sigma) < 2,
    tail_relative_state_below_0p01 = is.finite(tail_relative) && tail_relative < 0.01,
    tail_prediction_scaled_below_0p01 = is.finite(tail_prediction) && tail_prediction < 0.01
  )
  numerical_passed <- all(vapply(checks, isTRUE, logical(1L)))
  method_id <- as.character(task$method_id)
  write_csv(data.frame(
    method_id = method_id, split = "val", origin_id = rows_val$origin_id,
    horizon = rows_val$horizon, tau = as.numeric(task$tau), pred_scaled = prediction
  ), file.path(output, "predictions_scaled.csv"))
  write_csv(data.frame(
    method_id = method_id, model_family = "independent_qdesn_static_readout",
    likelihood_family = "exal", prior_family = "rhs_ns", tau = as.numeric(task$tau),
    inference_engine = "VB", posterior_approximation = "structured_sigma_gamma",
    converged = isTRUE(fit$converged), iter = as.integer(fit$iter),
    train_seconds = as.numeric(attr(fit, "r75_elapsed_seconds")), n_train = nrow(X_train),
    n_features = ncol(X_train), structured_updates = updates,
    package_version = package$version, package_repository = package$repository,
    repair = package$repair, init_source = "R93_AL_same_tau_coherent_qbeta",
    warm_start_mode = "al_qbeta_rhs_latent_first",
    numerical_gate_passed = numerical_passed, first_delta_gate_used = FALSE,
    test_loaded = FALSE, test_opened = FALSE, test_access_authorized = FALSE,
    binary_model_artifact_written = FALSE
  ), file.path(output, "method_summary.csv"))
  write_csv(data.frame(
    method_id = method_id, likelihood_family = "exal", tau = as.numeric(task$tau),
    beta_l2 = sqrt(sum(beta^2)), beta_max_abs = max(abs(beta)),
    beta_cov_trace = sum(diag(covariance)), sigma = sigma, gamma = gamma,
    al_init_beta_l2 = init_l2, al_init_sigma = sigma_init,
    first_state_delta = first_state, first_state_delta_below_100 = first_state < 100,
    tail_state_delta_max = tail_state, tail_sigma_delta_max = tail_sigma,
    tail_state_relative_max = tail_relative,
    tail_prediction_scaled_max = tail_prediction,
    tail_to_first_state_ratio = contraction
  ), file.path(output, "parameter_summary.csv"))
  write_csv(data.frame(
    feature_index = seq_along(beta), beta_mean = beta, beta_cov_diag = diag(covariance)
  ), file.path(output, "beta_summary.csv"))
  write_csv(trace, file.path(output, "vb_trace.csv"))
  write_json(list(
    mode = fit$misc$warm_start_mode,
    coherent_al_init = fit$misc$coherent_al_init,
    beta_covariance_source = fit$misc$beta_covariance_source,
    latent_first_initialized = fit$misc$latent_first_initialized,
    structured_initialization = fit$misc$sigmagam_initialization,
    al_beta_sha256 = task$al_beta_sha256, al_parameter_sha256 = task$al_parameter_sha256,
    package_version = package$version, package_repair = package$repair, test_loaded = FALSE
  ), file.path(output, "initialization_diagnostics.json"))
  write_json(list(
    numerical_gate_passed = numerical_passed, checks = checks,
    formal_converged = isTRUE(fit$converged), formal_stop_reason = fit$diagnostics$convergence$stop_reason,
    first_state_delta_below_100 = first_state < 100,
    first_state_delta_role = "diagnostic_only_not_an_eligibility_gate",
    tail_to_first_state_ratio = contraction,
    tail_to_first_state_ratio_role = "diagnostic_only_not_an_eligibility_gate"
  ), file.path(output, "numerical_gate.json"))
  files <- c(
    "predictions_scaled.csv", "method_summary.csv", "parameter_summary.csv",
    "beta_summary.csv", "vb_trace.csv", "initialization_diagnostics.json", "numerical_gate.json"
  )
  hashes <- setNames(lapply(file.path(output, files), sha256), files)
  write_json(list(
    status = if (numerical_passed) "completed" else "completed_numerically_ineligible",
    stage = "R94", task_id = task$task_id, case_id = task$case_id,
    region = task$region, fold = as.integer(task$fold), tau = as.numeric(task$tau),
    likelihood_family = "exal", formal_converged = isTRUE(fit$converged),
    numerical_gate_passed = numerical_passed, numerical_checks = checks,
    iter = as.integer(fit$iter), structured_updates = updates,
    artifact_sha256 = hashes, package = package,
    task_config_sha256 = sha256(task_path),
    pipeline_contract_sha256 = task$pipeline_contract_sha256,
    test_loaded = FALSE, test_opened = FALSE, test_access_authorized = FALSE,
    binary_model_artifacts_written = FALSE, registry_mutated = FALSE,
    article_mutated = FALSE, joint_model_fitted = FALSE, mcmc_fitted = FALSE
  ), terminal_path)
}

tryCatch(
  run_task(),
  error = function(error) {
    if (!preflight_only) {
      dir.create(output, recursive = TRUE, showWarnings = FALSE)
      write_json(list(
        status = "failed", stage = "R94", task_id = task$task_id,
        error_class = class(error), error_message = conditionMessage(error),
        task_config_sha256 = sha256(task_path),
        pipeline_contract_sha256 = task$pipeline_contract_sha256,
        test_loaded = FALSE, test_opened = FALSE, test_access_authorized = FALSE,
        binary_model_artifacts_written = FALSE
      ), terminal_path)
    }
    stop(error)
  }
)
