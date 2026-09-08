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

verify_terminal_artifacts <- function(path, task_id, pipeline_hash) {
  terminal <- jsonlite::read_json(path, simplifyVector = TRUE)
  if (!identical(as.character(terminal$task_id), as.character(task_id)) ||
      !identical(as.character(terminal$pipeline_contract_sha256), as.character(pipeline_hash)) ||
      !terminal$status %in% c("completed", "completed_numerically_ineligible") ||
      !identical(terminal$test_loaded, FALSE) || !identical(terminal$test_opened, FALSE) ||
      !identical(terminal$test_access_authorized, FALSE)) {
    stop("R95 parent terminal identity/firewall mismatch: ", path, call. = FALSE)
  }
  records <- record_rows(terminal$artifacts)
  if (is.null(records) || !length(records)) {
    stop("R95 parent terminal omits artifact provenance: ", path, call. = FALSE)
  }
  for (record in records) {
    if (!file.exists(record$path) || !identical(sha256(record$path), as.character(record$sha256))) {
      stop("R95 parent artifact hash mismatch: ", record$path, call. = FALSE)
    }
  }
  list(terminal = terminal, records = records)
}
find_record <- function(records, role) {
  matches <- Filter(function(record) identical(as.character(record$role), role), records)
  if (length(matches) != 1L) stop("R95 expected one parent artifact role: ", role, call. = FALSE)
  matches[[1L]]$path
}

run_task <- function() {
  blocked <- c(
    "test_access_authorized", "registry_mutation_authorized",
    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized"
  )
  family <- tolower(as.character(task$likelihood_family))
  if (!identical(as.character(task$stage), "R95") ||
      !family %in% c("al", "exal") ||
      !identical(as.character(task$runner_type), "quantile_atom") ||
      !identical(as.character(task$selection_split), "val") ||
      !identical(task$launch_authorized, FALSE) ||
      !identical(task$test_opened, FALSE) ||
      any(vapply(blocked, function(name) !identical(task[[name]], FALSE), logical(1L)))) {
    stop("R95 task firewall violation.", call. = FALSE)
  }
  for (pair in list(
    c("data_config", "data_config_sha256"),
    c("runtime_manifest", "runtime_manifest_sha256"),
    c("runner_script", "runner_script_sha256")
  )) {
    if (!identical(sha256(task[[pair[[1L]]]]), as.character(task[[pair[[2L]]]]))) {
      stop("R95 immutable source hash mismatch: ", pair[[1L]], call. = FALSE)
    }
  }
  adapter_scripts <- record_rows(task$adapter_scripts)
  if (length(adapter_scripts) != 3L) stop("R95 adapter-script provenance is incomplete.", call. = FALSE)
  for (record in adapter_scripts) {
    if (!file.exists(record$path) || !identical(sha256(record$path), as.character(record$sha256))) {
      stop("R95 adapter script hash mismatch: ", record$path, call. = FALSE)
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
      !identical(runtime$test_opened, FALSE) ||
      !identical(runtime$test_access_authorized, FALSE)) {
    stop("R95 coherent runtime provenance is invalid.", call. = FALSE)
  }
  options(
    pricefm.expected_exdqlm_version = "1.1.1.9005",
    pricefm.expected_exdqlm_repair = expected_repair
  )
  for (record in adapter_scripts) source(record$path, local = TRUE)
  package <- r75_assert_repair_package(task$r_library)

  normal_terminal_path <- file.path(task$normal_task_output, "terminal.json")
  normal_source <- verify_terminal_artifacts(
    normal_terminal_path, task$normal_task_id, task$pipeline_contract_sha256
  )
  if (!identical(normal_source$terminal$status, "completed") ||
      !isTRUE(normal_source$terminal$numerical_gate_passed)) {
    stop("R95 normal-RHS initializer is not eligible.", call. = FALSE)
  }
  adapter <- normalizePath(task$adapter_dir, mustWork = TRUE)
  forbidden <- file.path(adapter, c("X_test.csv", "y_test.csv", "rows_test.csv"))
  if (any(file.exists(forbidden))) stop("R95 adapter test firewall violation.", call. = FALSE)
  adapter_roles <- c(
    X_train = "adapter_X_train", y_train = "adapter_y_train", rows_train = "adapter_rows_train",
    X_val = "adapter_X_val", y_val = "adapter_y_val", rows_val = "adapter_rows_val",
    manifest = "adapter_manifest", feature_manifest = "feature_manifest", feature_map = "feature_map_matrix"
  )
  for (role in adapter_roles) find_record(normal_source$records, role)

  X_train <- read_matrix(file.path(adapter, "X_train.csv"))
  y_train <- read_vector(file.path(adapter, "y_train.csv"))
  X_val <- read_matrix(file.path(adapter, "X_val.csv"))
  rows_val <- utils::read.csv(file.path(adapter, "rows_val.csv"), stringsAsFactors = FALSE)
  if (nrow(X_train) != length(y_train) || ncol(X_train) != ncol(X_val) ||
      nrow(X_val) != nrow(rows_val) || any(!is.finite(X_train)) ||
      any(!is.finite(y_train)) || any(!is.finite(X_val))) {
    stop("R95 adapter dimensions or values are invalid.", call. = FALSE)
  }

  parent_terminal_path <- file.path(task$parent_task_output, "terminal.json")
  parent_id <- as.character(unlist(task$parent_task_ids, use.names = FALSE)[[1L]])
  parent <- verify_terminal_artifacts(parent_terminal_path, parent_id, task$pipeline_contract_sha256)
  if (!identical(parent$terminal$status, "completed") ||
      !isTRUE(parent$terminal$numerical_gate_passed)) {
    stop("R95 warm-start parent is not eligible.", call. = FALSE)
  }
  if (identical(as.character(parent$terminal$likelihood_family), "normal_rhs")) {
    beta_path <- find_record(parent$records, "normal_beta_mean")
    covariance_path <- find_record(parent$records, "normal_beta_cov_diag")
    parameter_path <- find_record(parent$records, "normal_parameter_summary")
    beta_frame <- utils::read.csv(beta_path, stringsAsFactors = FALSE)
    beta_frame <- beta_frame[beta_frame$method_id == "normal_rhs_ns", , drop = FALSE]
    covariance_frame <- utils::read.csv(covariance_path, stringsAsFactors = FALSE)
    covariance_frame <- covariance_frame[covariance_frame$method_id == "normal_rhs_ns", , drop = FALSE]
    parameter <- utils::read.csv(parameter_path, stringsAsFactors = FALSE)
    parameter <- parameter[parameter$method_id == "normal_rhs_ns", , drop = FALSE]
    init_source <- "normal_rhs_same_fold"
  } else {
    beta_path <- find_record(parent$records, "beta_summary")
    parameter_path <- find_record(parent$records, "parameter_summary")
    beta_frame <- utils::read.csv(beta_path, stringsAsFactors = FALSE)
    covariance_frame <- beta_frame
    parameter <- utils::read.csv(parameter_path, stringsAsFactors = FALSE)
    init_source <- paste0(as.character(parent$terminal$likelihood_family), "_parent_atom")
  }
  beta_init <- as.numeric(beta_frame$beta_mean)
  covariance_init <- as.numeric(covariance_frame$beta_cov_diag)
  sigma_init <- as.numeric(parameter$sigma[[1L]])
  if (length(beta_init) != ncol(X_train) || length(covariance_init) != ncol(X_train) ||
      any(!is.finite(beta_init)) || any(!is.finite(covariance_init)) ||
      any(covariance_init <= 0) || !is.finite(sigma_init) || sigma_init <= 0) {
    stop("R95 warm-start state is incomplete.", call. = FALSE)
  }
  if (preflight_only) {
    cat(jsonlite::toJSON(list(
      status = "preflight_passed_not_fitted", task_id = task$task_id,
      family = family, tau = task$tau, package = package,
      n_train = nrow(X_train), n_features = ncol(X_train),
      test_loaded = FALSE, test_opened = FALSE, test_access_authorized = FALSE,
      binary_model_artifacts_written = FALSE
    ), auto_unbox = TRUE, pretty = TRUE), "\n")
    return(invisible(NULL))
  }

  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  write_json(list(
    status = "started", task_id = task$task_id, pid = Sys.getpid(),
    task_config = task_path, task_config_sha256 = sha256(task_path),
    test_loaded = FALSE, test_opened = FALSE, test_access_authorized = FALSE
  ), file.path(output, "started.json"))
  rhs <- lapply(task$rhs, function(value) if (length(value) == 1L) unlist(value) else value)
  qcfg <- lapply(task$qdesn_vb, function(value) if (length(value) == 1L) unlist(value) else value)
  profile <- qcfg$structured_sigmagam
  init <- list(beta = beta_init, sigma = sigma_init)
  if (identical(family, "exal")) {
    init$beta_cov_diag <- covariance_init
    init$gamma <- 0
    init$warm_start_mode <- "al_qbeta_rhs_latent_first"
  }
  set.seed(as.integer(task$seed))
  started <- proc.time()[["elapsed"]]
  if (identical(family, "exal")) {
    fit <- r75_fit_quantile(
      task$r_library, X_train, y_train, task$tau, rhs, qcfg, profile,
      init = init, seed = task$seed
    )
  } else {
    control <- r67_vb_control(NULL, qcfg, "al", NULL)
    prior_sigma <- qcfg$prior_sigma %||% list(a = 1, b = 1)
    fit <- do.call(getExportedValue("exdqlm", "exalStaticLDVB"), list(
      y = y_train, X = X_train, p0 = as.numeric(task$tau),
      beta_prior = "rhs_ns", beta_prior_controls = r72_rhs_controls(rhs),
      a_sigma = as.numeric(prior_sigma$a %||% 1),
      b_sigma = as.numeric(prior_sigma$b %||% 1),
      init = init, dqlm.ind = TRUE,
      n.samp = as.integer(qcfg$n_samp %||% 200L),
      vb_control = control, verbose = FALSE
    ))
  }
  elapsed <- proc.time()[["elapsed"]] - started
  beta <- as.numeric(fit$qbeta$m)
  covariance <- as.matrix(fit$qbeta$V)
  sigma <- as.numeric(fit$qsig$E_sigma %||% fit$qsiggam$sigma_mean %||% NA_real_)[1L]
  gamma <- if (identical(family, "exal")) {
    as.numeric(fit$qsiggam$gamma_mean %||% fit$qgam$E_gamma %||% NA_real_)[1L]
  } else 0
  prediction <- as.numeric(X_val %*% beta)
  trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
  deltas <- fit$diagnostics$deltas %||% list()
  if (identical(family, "exal") && nrow(trace)) {
    if (!"delta_state_relative" %in% names(trace)) trace$delta_state_relative <- as.numeric(deltas$state_relative)
    if (!"delta_prediction_scaled" %in% names(trace)) trace$delta_prediction_scaled <- as.numeric(deltas$prediction_scaled)
  }
  finite_core <- all(is.finite(beta)) && all(is.finite(covariance)) &&
    all(diag(covariance) > 0) && is.finite(sigma) && sigma > 0 && all(is.finite(prediction))
  checks <- list(finite_core = finite_core)
  updates <- 0L
  first_state <- NA_real_
  tail_state <- NA_real_
  tail_sigma <- NA_real_
  tail_relative <- NA_real_
  tail_prediction <- NA_real_
  contraction <- NA_real_
  coherent <- NA
  if (identical(family, "exal")) {
    required <- c(
      "sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s",
      "delta_state_relative", "delta_prediction_scaled"
    )
    trace_complete <- nrow(trace) > 0L && all(required %in% names(trace))
    trace_finite <- trace_complete && all(is.finite(as.matrix(trace[, required, drop = FALSE])))
    updates <- as.integer(fit$diagnostics$ld_block$sigmagam$update_count %||% 0L)
    first_state <- if (trace_complete) abs(trace$delta_state[[1L]]) else Inf
    tail <- if (trace_complete) utils::tail(trace, 10L) else data.frame()
    tail_state <- if (nrow(tail)) max(abs(tail$delta_state)) else Inf
    tail_sigma <- if (nrow(tail)) max(abs(tail$delta_sigma)) else Inf
    tail_relative <- if (nrow(tail)) max(abs(tail$delta_state_relative)) else Inf
    tail_prediction <- if (nrow(tail)) max(abs(tail$delta_prediction_scaled)) else Inf
    contraction <- tail_state / max(first_state, .Machine$double.eps)
    beta_ratio <- sqrt(sum(beta^2)) / max(sqrt(sum(beta_init^2)), .Machine$double.eps)
    coherent <- isTRUE(fit$misc$coherent_al_init) && isTRUE(fit$misc$latent_first_initialized) &&
      identical(fit$misc$beta_covariance_source, "al_beta_cov_diag")
    checks <- c(checks, list(
      trace_complete = trace_complete,
      trace_finite = trace_finite,
      coherent_warm_start_recorded = coherent,
      structured_updates_at_least_35 = updates >= 35L,
      sigma_below_100 = is.finite(sigma) && sigma < 100,
      gamma_bounded = is.finite(gamma) && abs(gamma) < 4,
      beta_l2_ratio_below_10 = is.finite(beta_ratio) && beta_ratio < 10,
      tail_state_sigma_delta_below_2 = is.finite(max(tail_state, tail_sigma)) && max(tail_state, tail_sigma) < 2,
      tail_relative_state_below_0p01 = is.finite(tail_relative) && tail_relative < 0.01,
      tail_prediction_scaled_below_0p01 = is.finite(tail_prediction) && tail_prediction < 0.01
    ))
  }
  numerical_passed <- all(vapply(checks, isTRUE, logical(1L)))
  method_id <- as.character(task$method_id)
  write_csv(data.frame(
    method_id = method_id, split = "val", origin_id = rows_val$origin_id,
    horizon = rows_val$horizon, tau = as.numeric(task$tau), pred_scaled = prediction
  ), file.path(output, "predictions_scaled.csv"))
  write_csv(data.frame(
    method_id = method_id, model_family = "independent_qdesn_static_readout",
    likelihood_family = family, prior_family = "rhs_ns", tau = as.numeric(task$tau),
    inference_engine = "VB", posterior_approximation = ifelse(
      family == "exal", "structured_sigma_gamma", "mean_field_al"
    ),
    converged = isTRUE(fit$converged), iter = as.integer(fit$iter %||% NA_integer_),
    train_seconds = as.numeric(elapsed), n_train = nrow(X_train), n_features = ncol(X_train),
    structured_updates = updates, package_version = package$version,
    package_repository = package$repository, repair = package$repair,
    init_source = init_source, warm_start_mode = as.character(task$warm_start_mode),
    numerical_gate_passed = numerical_passed, test_loaded = FALSE,
    test_opened = FALSE, test_access_authorized = FALSE,
    binary_model_artifact_written = FALSE
  ), file.path(output, "method_summary.csv"))
  write_csv(data.frame(
    method_id = method_id, likelihood_family = family, tau = as.numeric(task$tau),
    beta_l2 = sqrt(sum(beta^2)), beta_max_abs = max(abs(beta)),
    beta_cov_trace = sum(diag(covariance)), sigma = sigma, gamma = gamma,
    init_beta_l2 = sqrt(sum(beta_init^2)), init_sigma = sigma_init,
    first_state_delta = first_state, tail_state_delta_max = tail_state,
    tail_sigma_delta_max = tail_sigma, tail_state_relative_max = tail_relative,
    tail_prediction_scaled_max = tail_prediction, tail_to_first_state_ratio = contraction
  ), file.path(output, "parameter_summary.csv"))
  write_csv(data.frame(
    method_id = method_id, tau = as.numeric(task$tau), feature_index = seq_along(beta),
    beta_mean = beta, beta_cov_diag = diag(covariance)
  ), file.path(output, "beta_summary.csv"))
  if (nrow(trace)) write_csv(trace, file.path(output, "vb_trace.csv"))
  write_json(list(
    numerical_gate_passed = numerical_passed, checks = checks,
    formal_converged = isTRUE(fit$converged),
    formal_stop_reason = fit$diagnostics$convergence$stop_reason %||% NA_character_,
    first_state_delta_role = "diagnostic_only_not_an_eligibility_gate",
    tail_to_first_state_ratio = contraction,
    tail_to_first_state_ratio_role = "diagnostic_only_not_an_eligibility_gate"
  ), file.path(output, "numerical_gate.json"))
  if (identical(family, "exal")) {
    write_json(list(
      mode = fit$misc$warm_start_mode, coherent_al_init = fit$misc$coherent_al_init,
      beta_covariance_source = fit$misc$beta_covariance_source,
      latent_first_initialized = fit$misc$latent_first_initialized,
      structured_initialization = fit$misc$sigmagam_initialization,
      package_version = package$version, package_repair = package$repair,
      test_loaded = FALSE
    ), file.path(output, "initialization_diagnostics.json"))
  }
  files <- c(
    "predictions_scaled.csv", "method_summary.csv", "parameter_summary.csv",
    "beta_summary.csv", "numerical_gate.json"
  )
  if (file.exists(file.path(output, "vb_trace.csv"))) files <- c(files, "vb_trace.csv")
  if (file.exists(file.path(output, "initialization_diagnostics.json"))) {
    files <- c(files, "initialization_diagnostics.json")
  }
  artifacts <- lapply(files, function(name) list(
    path = normalizePath(file.path(output, name), mustWork = TRUE),
    role = sub("\\.csv$|\\.json$", "", name), sha256 = sha256(file.path(output, name)),
    bytes = file.info(file.path(output, name))$size
  ))
  write_json(list(
    status = if (numerical_passed) "completed" else "completed_numerically_ineligible",
    stage = "R95", task_id = task$task_id, region = task$region,
    fold = as.integer(task$fold), tau = as.numeric(task$tau),
    likelihood_family = family, formal_converged = isTRUE(fit$converged),
    numerical_gate_passed = numerical_passed, numerical_checks = checks,
    iter = as.integer(fit$iter %||% NA_integer_), structured_updates = updates,
    artifacts = artifacts, package = package, task_config_sha256 = sha256(task_path),
    pipeline_contract_sha256 = task$pipeline_contract_sha256,
    parent_task_id = parent_id,
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
        status = "failed", stage = "R95", task_id = task$task_id,
        likelihood_family = task$likelihood_family,
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
