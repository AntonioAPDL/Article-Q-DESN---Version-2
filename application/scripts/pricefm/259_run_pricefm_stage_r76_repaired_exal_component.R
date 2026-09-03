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
write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  cat(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n", file = tmp)
  atomic_replace(tmp, path)
}
write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp.", Sys.getpid())
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  utils::write.csv(x, tmp, row.names = FALSE)
  atomic_replace(tmp, path)
}
sha256 <- function(path) {
  output <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])

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
dir.create(output, recursive = TRUE, showWarnings = FALSE)
terminal_path <- file.path(output, "terminal.json")
write_json(list(
  status = "started", task_id = task$task_id, pid = Sys.getpid(),
  task_config = task_path, task_config_sha256 = sha256(task_path), test_loaded = FALSE
), file.path(output, "started.json"))

run_task <- function() {
  blocked <- c("test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized",
               "joint_model_authorized", "mcmc_authorized")
  if (!identical(as.character(task$stage), "R76") ||
      !identical(as.character(task$likelihood_family), "exal") ||
      !identical(as.character(task$selection_split), "val") ||
      any(vapply(blocked, function(name) isTRUE(task[[name]]), logical(1L)))) {
    stop("R76 task firewall violation.", call. = FALSE)
  }
  if (!identical(sha256(task$source_case_config), task$source_case_config_sha256) ||
      !identical(sha256(task$runtime_manifest), task$runtime_manifest_sha256) ||
      !identical(sha256(task$al_beta_path), task$al_beta_sha256) ||
      !identical(sha256(task$al_parameter_path), task$al_parameter_sha256) ||
      !identical(sha256(task$al_source_terminal), task$al_source_terminal_sha256)) {
    stop("R76 immutable source hash mismatch.", call. = FALSE)
  }
  runtime <- jsonlite::read_json(task$runtime_manifest, simplifyVector = TRUE)
  if (!identical(runtime$status, "installed_pricefm_local_large_n_gig_repair") ||
      !identical(runtime$base_tarball_sha256,
                 "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e")) {
    stop("R76 runtime manifest is invalid.", call. = FALSE)
  }
  source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"), local = TRUE)
  source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r72_repair_adapter.R"), local = TRUE)
  source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r75_large_n_gig_adapter.R"), local = TRUE)
  package <- r75_assert_repair_package(task$r_library)
  if (preflight_only) {
    write_json(list(
      status = "preflight_passed", task_id = task$task_id, package = package,
      test_loaded = FALSE, binary_model_artifacts_written = FALSE
    ), terminal_path)
    return(invisible(NULL))
  }

  adapter <- normalizePath(task$adapter_dir, mustWork = TRUE)
  forbidden <- file.path(adapter, c("X_test.csv", "y_test.csv", "rows_test.csv"))
  if (any(file.exists(forbidden))) stop("R76 adapter test firewall violation.", call. = FALSE)
  X_train <- read_matrix(file.path(adapter, "X_train.csv"))
  y_train <- read_vector(file.path(adapter, "y_train.csv"))
  X_val <- read_matrix(file.path(adapter, "X_val.csv"))
  rows_val <- utils::read.csv(file.path(adapter, "rows_val.csv"), stringsAsFactors = FALSE)
  if (nrow(X_train) != length(y_train) || ncol(X_train) != ncol(X_val) ||
      nrow(X_val) != nrow(rows_val) || any(!is.finite(X_train)) ||
      any(!is.finite(y_train)) || any(!is.finite(X_val))) {
    stop("R76 adapter dimensions or values are invalid.", call. = FALSE)
  }
  beta_frame <- utils::read.csv(task$al_beta_path)
  parameter <- utils::read.csv(task$al_parameter_path)
  beta_init <- as.numeric(beta_frame$beta_mean)
  sigma_init <- as.numeric(parameter$sigma[[1L]])
  if (length(beta_init) != ncol(X_train) || any(!is.finite(beta_init)) ||
      !is.finite(sigma_init) || sigma_init <= 0) {
    stop("R76 AL warm start is invalid.", call. = FALSE)
  }
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
    freeze_warmup_iters = as.integer(task$sigmagam_freeze_warmup_iters),
    force_after_warmup = TRUE,
    postwarmup_damping = as.numeric(task$postwarmup_damping),
    postwarmup_damping_iters = as.integer(task$postwarmup_damping_iters),
    min_postwarmup_updates = as.integer(task$min_postwarmup_updates)
  )
  fit <- r75_fit_quantile(
    task$r_library, X_train, y_train, task$tau, rhs, qcfg, profile,
    init = list(beta = beta_init, sigma = sigma_init, gamma = 0), seed = task$seed
  )
  beta <- as.numeric(fit$qbeta$m)
  covariance <- as.matrix(fit$qbeta$V)
  sigma <- as.numeric(fit$qsiggam$sigma_mean)
  gamma <- as.numeric(fit$qsiggam$gamma_mean)
  prediction <- as.numeric(X_val %*% beta)
  trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
  spd <- as.data.frame(fit$diagnostics$spd_factorization %||% data.frame())
  grid <- as.data.frame(fit$qsiggam$structured$grid %||% data.frame())
  updates <- as.integer(fit$diagnostics$ld_block$sigmagam$update_count %||% 0L)
  required_trace <- intersect(
    c("sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s"),
    names(trace)
  )
  required <- c(beta, covariance, sigma, gamma, prediction, unlist(trace[required_trace]))
  if (any(!is.finite(required)) || updates < as.integer(task$min_postwarmup_updates)) {
    stop("R76 fit failed finite-output or structured-update contract.", call. = FALSE)
  }
  method_id <- as.character(task$method_id)
  predictions <- data.frame(
    method_id = method_id, split = "val", origin_id = rows_val$origin_id,
    horizon = rows_val$horizon, tau = as.numeric(task$tau),
    pred_scaled = prediction, stringsAsFactors = FALSE
  )
  method <- data.frame(
    method_id = method_id, model_family = "independent_qdesn_static_readout",
    likelihood_family = "exal", prior_family = "rhs_ns", tau = as.numeric(task$tau),
    inference_engine = "VB", posterior_approximation = "structured_sigma_gamma",
    converged = isTRUE(fit$converged), iter = as.integer(fit$iter),
    train_seconds = as.numeric(attr(fit, "r75_elapsed_seconds")),
    n_train = nrow(X_train), n_features = ncol(X_train),
    structured_updates = updates, package_version = package$version,
    package_repository = package$repository, repair = package$repair,
    init_source = paste0("R73_AL_", task$al_source_stage),
    test_loaded = FALSE, binary_model_artifact_written = FALSE,
    stringsAsFactors = FALSE
  )
  parameters <- data.frame(
    method_id = method_id, likelihood_family = "exal", tau = as.numeric(task$tau),
    beta_l2 = sqrt(sum(beta^2)), beta_max_abs = max(abs(beta)),
    beta_cov_trace = sum(diag(covariance)), sigma = sigma, gamma = gamma,
    al_init_beta_l2 = sqrt(sum(beta_init^2)), al_init_sigma = sigma_init,
    stringsAsFactors = FALSE
  )
  write_csv(predictions, file.path(output, "predictions_scaled.csv"))
  write_csv(method, file.path(output, "method_summary.csv"))
  write_csv(parameters, file.path(output, "parameter_summary.csv"))
  write_csv(data.frame(
    feature_index = seq_along(beta), beta_mean = beta, beta_cov_diag = diag(covariance)
  ), file.path(output, "beta_summary.csv"))
  write_csv(trace, file.path(output, "vb_trace.csv"))
  write_csv(spd, file.path(output, "spd_factorization_trace.csv"))
  write_csv(grid, file.path(output, "structured_grid.csv"))
  write_json(list(
    preflight = fit$diagnostics$rhs$preflight %||% list(),
    summary = fit$diagnostics$rhs$summary %||% fit$beta_prior$summary %||% list()
  ), file.path(output, "rhs_diagnostics.json"))
  write_json(list(
    source_al_beta = task$al_beta_path, source_al_beta_sha256 = task$al_beta_sha256,
    source_al_parameter = task$al_parameter_path,
    source_al_parameter_sha256 = task$al_parameter_sha256,
    source_al_terminal = task$al_source_terminal,
    source_al_terminal_sha256 = task$al_source_terminal_sha256
  ), file.path(output, "warm_start_manifest.json"))
  files <- c(
    "predictions_scaled.csv", "method_summary.csv", "parameter_summary.csv",
    "beta_summary.csv", "vb_trace.csv", "spd_factorization_trace.csv",
    "structured_grid.csv", "rhs_diagnostics.json", "warm_start_manifest.json"
  )
  hashes <- setNames(lapply(file.path(output, files), sha256), files)
  write_json(list(
    status = "completed", task_id = task$task_id, case_id = task$case_id,
    region = task$region, fold = as.integer(task$fold), tau = as.numeric(task$tau),
    likelihood_family = "exal", converged = isTRUE(fit$converged),
    iter = as.integer(fit$iter), structured_updates = updates,
    artifact_sha256 = hashes, package = package, test_loaded = FALSE,
    binary_model_artifacts_written = FALSE, registry_mutated = FALSE,
    article_mutated = FALSE, joint_model_fitted = FALSE, mcmc_fitted = FALSE
  ), terminal_path)
}

tryCatch(
  run_task(),
  error = function(error) {
    write_json(list(
      status = "failed", task_id = task$task_id, case_id = task$case_id,
      tau = task$tau, likelihood_family = "exal", error_class = class(error),
      error_message = conditionMessage(error), test_loaded = FALSE,
      binary_model_artifacts_written = FALSE
    ), terminal_path)
    stop(error)
  }
)
