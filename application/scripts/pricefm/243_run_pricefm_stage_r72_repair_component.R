#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(yaml))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}
`%||%` <- function(x, y) if (is.null(x)) y else x
as_flag <- function(x) tolower(as.character(x %||% "false")) %in% c("1", "true", "yes")

r72_atomic_path <- function(path) paste0(path, ".tmp.", Sys.getpid())
r72_atomic_replace <- function(tmp, path) {
  if (!file.rename(tmp, path)) {
    if (file.exists(path)) unlink(path)
    if (!file.rename(tmp, path)) stop("Atomic rename failed: ", path, call. = FALSE)
  }
}
r72_write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- r72_atomic_path(path)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  cat(jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n", file = tmp)
  r72_atomic_replace(tmp, path)
}
r72_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- r72_atomic_path(path)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  utils::write.csv(x, tmp, row.names = FALSE)
  r72_atomic_replace(tmp, path)
}
r72_sha256 <- function(path) {
  output <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
r72_read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
r72_read_vector <- function(path) as.numeric(r72_read_matrix(path)[, 1L])

find_repo_root <- function() {
  candidates <- unique(normalizePath(c(
    getwd(), file.path(getwd(), ".."), file.path(getwd(), "../.."),
    file.path(getwd(), "../../..")
  ), mustWork = FALSE))
  for (candidate in candidates) {
    if (file.exists(file.path(candidate, "application/scripts/pricefm/pricefm_stage_r72_repair_adapter.R"))) {
      return(candidate)
    }
  }
  stop("Could not locate R72 code root.", call. = FALSE)
}

task_path <- get_arg("--task-config")
preflight_only <- as_flag(get_arg("--preflight-only", "false"))
if (is.null(task_path)) stop("--task-config is required.", call. = FALSE)
task_path <- normalizePath(task_path, mustWork = TRUE)
task <- jsonlite::read_json(task_path, simplifyVector = TRUE)
output <- normalizePath(task$output_dir, mustWork = FALSE)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
started_path <- file.path(output, "started.json")
terminal_path <- file.path(output, "terminal.json")
r72_write_json(list(
  status = "started", task_id = task$task_id, pid = Sys.getpid(),
  task_config = task_path, task_config_sha256 = r72_sha256(task_path),
  test_loaded = FALSE
), started_path)

run_task <- function() {
  if (!identical(as.character(task$stage), "R72") ||
      !identical(as.character(task$selection_split), "val") ||
      isTRUE(task$test_access_authorized) || isTRUE(task$registry_mutation_authorized) ||
      isTRUE(task$article_mutation_authorized) || isTRUE(task$joint_model_authorized) ||
      isTRUE(task$mcmc_authorized)) {
    stop("R72 task firewall violation.", call. = FALSE)
  }
  likelihood <- match.arg(as.character(task$likelihood_family), c("al", "exal"))
  if (identical(likelihood, "exal") && !isTRUE(task$exal_mechanism_gate_passed)) {
    stop("R72 exAL execution is blocked until its mechanism gate passes.", call. = FALSE)
  }
  config <- yaml::read_yaml(normalizePath(task$source_case_config, mustWork = TRUE))
  cfg <- config$pricefm_desn_smoke
  if (!identical(as.character(cfg$splits), c("train", "val"))) {
    stop("R72 source config is not train/validation only.", call. = FALSE)
  }
  runtime_manifest <- jsonlite::read_json(task$runtime_manifest, simplifyVector = TRUE)
  if (!identical(runtime_manifest$status, "installed_pricefm_local_spd_repair") ||
      !identical(runtime_manifest$base_tarball_sha256,
                 "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e")) {
    stop("R72 runtime manifest is invalid.", call. = FALSE)
  }
  repo <- find_repo_root()
  source(file.path(repo, "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"), local = TRUE)
  source(file.path(repo, "application/scripts/pricefm/pricefm_stage_r72_repair_adapter.R"), local = TRUE)
  package <- r72_assert_repair_package(task$r_library)
  if (preflight_only) {
    r72_write_json(list(
      status = "preflight_passed", task_id = task$task_id,
      likelihood_family = likelihood, tau = as.numeric(task$tau),
      package = package, test_loaded = FALSE,
      binary_model_artifacts_written = FALSE
    ), terminal_path)
    return(invisible(NULL))
  }

  adapter <- normalizePath(task$adapter_dir, mustWork = TRUE)
  forbidden <- file.path(adapter, c("X_test.csv", "y_test.csv", "rows_test.csv"))
  if (any(file.exists(forbidden))) stop("R72 adapter test firewall violation.", call. = FALSE)
  X_train <- r72_read_matrix(file.path(adapter, "X_train.csv"))
  y_train <- r72_read_vector(file.path(adapter, "y_train.csv"))
  X_val <- r72_read_matrix(file.path(adapter, "X_val.csv"))
  rows_val <- utils::read.csv(file.path(adapter, "rows_val.csv"), stringsAsFactors = FALSE)
  if (nrow(X_train) != length(y_train) || ncol(X_train) != ncol(X_val) ||
      nrow(X_val) != nrow(rows_val) || any(!is.finite(X_train)) ||
      any(!is.finite(y_train)) || any(!is.finite(X_val))) {
    stop("R72 adapter dimensions/values are invalid.", call. = FALSE)
  }
  qcfg <- cfg$qdesn_vb %||% list()
  qcfg$max_iter <- as.integer(task$max_iter)
  qcfg$tol <- as.numeric(task$tol)
  qcfg$n_samp <- as.integer(task$n_samp)
  qcfg$n_samp_xi <- as.integer(task$n_samp_xi)
  qcfg$verbose <- FALSE
  rhs <- list(
    tau0 = as.numeric(task$rhs_tau0), init_tau = as.numeric(task$rhs_init_tau),
    freeze_tau_iters = as.integer(task$rhs_freeze_tau_iters),
    freeze_tau_warmup_iters = as.integer(task$rhs_freeze_tau_warmup_iters),
    shrink_intercept = FALSE
  )
  fit <- r72_fit_quantile(
    task$r_library, X_train, y_train, tau = task$tau,
    likelihood = likelihood, rhs = rhs, qcfg = qcfg,
    profile = qcfg$sigmagam %||% NULL, init = NULL, seed = task$seed
  )
  beta <- as.numeric(fit$qbeta$m)
  covariance <- as.matrix(fit$qbeta$V)
  prediction <- as.numeric(X_val %*% beta)
  if (any(!is.finite(beta)) || any(!is.finite(covariance)) || any(!is.finite(prediction))) {
    stop("R72 fit produced non-finite outputs.", call. = FALSE)
  }
  method_id <- as.character(task$method_id)
  predictions <- data.frame(
    method_id = method_id, split = "val", origin_id = rows_val$origin_id,
    horizon = rows_val$horizon, tau = as.numeric(task$tau),
    pred_scaled = prediction, stringsAsFactors = FALSE
  )
  parameter <- data.frame(
    method_id = method_id, likelihood_family = likelihood, tau = as.numeric(task$tau),
    beta_l2 = sqrt(sum(beta^2)), beta_max_abs = max(abs(beta)),
    beta_cov_trace = sum(diag(covariance)),
    sigma = as.numeric(fit$qsig$E_sigma %||% fit$qsiggam$sigma_mean %||% NA_real_),
    gamma = as.numeric(fit$qsiggam$gamma_mean %||% NA_real_),
    stringsAsFactors = FALSE
  )
  method <- data.frame(
    method_id = method_id, likelihood_family = likelihood, tau = as.numeric(task$tau),
    inference_engine = "VB", prior_family = "rhs_ns",
    converged = isTRUE(fit$converged), iter = as.integer(fit$iter),
    train_seconds = as.numeric(attr(fit, "r72_elapsed_seconds")),
    package_version = package$version, package_repository = package$repository,
    repair = package$repair, test_loaded = FALSE,
    binary_model_artifact_written = FALSE, stringsAsFactors = FALSE
  )
  r72_write_csv(predictions, file.path(output, "predictions_scaled.csv"))
  r72_write_csv(method, file.path(output, "method_summary.csv"))
  r72_write_csv(parameter, file.path(output, "parameter_summary.csv"))
  r72_write_csv(data.frame(
    feature_index = seq_along(beta), beta_mean = beta,
    beta_cov_diag = diag(covariance)
  ), file.path(output, "beta_summary.csv"))
  vb_trace <- fit$diagnostics$vb_trace %||% data.frame()
  spd_trace <- fit$diagnostics$spd_factorization %||% data.frame()
  r72_write_csv(as.data.frame(vb_trace), file.path(output, "vb_trace.csv"))
  r72_write_csv(as.data.frame(spd_trace), file.path(output, "spd_factorization_trace.csv"))
  r72_write_json(list(
    preflight = fit$diagnostics$rhs$preflight %||% list(),
    summary = fit$diagnostics$rhs$summary %||% fit$beta_prior$summary %||% list()
  ), file.path(output, "rhs_diagnostics.json"))
  files <- c(
    "predictions_scaled.csv", "method_summary.csv", "parameter_summary.csv",
    "beta_summary.csv", "vb_trace.csv", "spd_factorization_trace.csv",
    "rhs_diagnostics.json"
  )
  hashes <- setNames(lapply(file.path(output, files), r72_sha256), files)
  r72_write_json(list(
    status = "completed", task_id = task$task_id, case_id = task$case_id,
    region = task$region, fold = as.integer(task$fold), tau = as.numeric(task$tau),
    likelihood_family = likelihood, converged = isTRUE(fit$converged),
    iter = as.integer(fit$iter), artifact_sha256 = hashes,
    package = package, test_loaded = FALSE,
    binary_model_artifacts_written = FALSE,
    registry_mutated = FALSE, article_mutated = FALSE
  ), terminal_path)
}

tryCatch(
  run_task(),
  error = function(error) {
    r72_write_json(list(
      status = "failed", task_id = task$task_id, case_id = task$case_id,
      tau = task$tau, likelihood_family = task$likelihood_family,
      error_class = class(error), error_message = conditionMessage(error),
      test_loaded = FALSE, binary_model_artifacts_written = FALSE
    ), terminal_path)
    stop(error)
  }
)
