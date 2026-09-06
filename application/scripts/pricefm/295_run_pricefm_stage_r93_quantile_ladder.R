#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}
`%||%` <- function(x, y) if (is.null(x)) y else x
as_flag <- function(x) tolower(as.character(x %||% "false")) %in% c("1", "true", "yes")

task_path <- normalizePath(get_arg("--task"), mustWork = TRUE)
task <- jsonlite::read_json(task_path, simplifyVector = FALSE)
preflight_only <- as_flag(get_arg("--preflight-only", "false"))

sha256 <- function(path) {
  path <- normalizePath(path, mustWork = TRUE)
  output <- as.character(system2("sha256sum", path, stdout = TRUE))
  strsplit(output[[1L]], "[[:space:]]+")[[1L]][[1L]]
}

atomic_path <- function(path) paste0(path, ".tmp.", Sys.getpid())
write_json <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- atomic_path(path)
  jsonlite::write_json(value, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (!file.rename(tmp, path)) stop("atomic JSON rename failed: ", path, call. = FALSE)
}
write_csv <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- atomic_path(path)
  utils::write.csv(value, tmp, row.names = FALSE)
  if (!file.rename(tmp, path)) stop("atomic CSV rename failed: ", path, call. = FALSE)
}
read_matrix <- function(path) as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])
as_bool <- function(x) isTRUE(x)
as_num <- function(x) as.numeric(unlist(x, use.names = FALSE))
as_int <- function(x) as.integer(unlist(x, use.names = FALSE))

blocked <- c(
  "test_access_authorized", "registry_mutation_authorized",
  "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized"
)
if (!identical(as.character(task$stage), "R93") ||
    !identical(as.character(task$selection_split), "val") ||
    any(vapply(blocked, function(name) isTRUE(task[[name]]), logical(1L)))) {
  stop("R93 quantile task firewall violation.", call. = FALSE)
}
for (pair in list(
  c("config", "config_sha256"),
  c("data_config", "data_config_sha256"),
  c("normal_beta_path", "normal_beta_sha256"),
  c("normal_parameter_path", "normal_parameter_sha256"),
  c("runtime_manifest", "runtime_manifest_sha256"),
  c("runner_script", "runner_script_sha256")
)) {
  if (!identical(sha256(task[[pair[[1L]]]]), as.character(task[[pair[[2L]]]]))) {
    stop("R93 source hash mismatch: ", pair[[1L]], call. = FALSE)
  }
}
for (item in task$adapter_scripts) {
  if (!identical(sha256(item$path), as.character(item$sha256))) {
    stop("R93 public-API adapter hash mismatch: ", item$path, call. = FALSE)
  }
}

expected_quantiles <- c(0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90)
expected_order <- c(0.50, 0.45, 0.25, 0.10, 0.55, 0.75, 0.90)
expected_parents <- c(
  "0.50" = "outer_normal_rhs", "0.45" = "0.50", "0.25" = "0.45",
  "0.10" = "0.25", "0.55" = "0.50", "0.75" = "0.55", "0.90" = "0.75"
)
quantiles <- as_num(task$quantiles)
warm_order <- as_num(task$warm_order)
warm_parents <- unlist(task$warm_parent_by_tau, use.names = TRUE)
if (!isTRUE(all.equal(quantiles, expected_quantiles, tolerance = 0)) ||
    !isTRUE(all.equal(warm_order, expected_order, tolerance = 0)) ||
    !identical(as.character(warm_parents[names(expected_parents)]),
               as.character(expected_parents))) {
  stop("R93 quantile or warm-start order changed.", call. = FALSE)
}

config <- yaml::read_yaml(task$config)$pricefm_desn_smoke
if (!identical(as.character(unlist(config$splits)), c("train", "val")) ||
    any(grepl("test", names(yaml::read_yaml(config$data_config)$pricefm$splits[[1L]])))) {
  stop("R93 quantile config contains a test split.", call. = FALSE)
}
adapter <- normalizePath(task$adapter_dir, mustWork = TRUE)
forbidden <- file.path(adapter, c("X_test.csv", "y_test.csv", "rows_test.csv"))
if (any(file.exists(forbidden))) stop("R93 adapter test firewall violation.", call. = FALSE)

X_train <- read_matrix(file.path(adapter, "X_train.csv"))
y_train <- read_vector(file.path(adapter, "y_train.csv"))
X_val <- read_matrix(file.path(adapter, "X_val.csv"))
rows_val <- utils::read.csv(file.path(adapter, "rows_val.csv"), stringsAsFactors = FALSE)
if (nrow(X_train) != length(y_train) || ncol(X_train) != ncol(X_val) ||
    nrow(X_val) != nrow(rows_val) || any(!is.finite(X_train)) ||
    any(!is.finite(y_train)) || any(!is.finite(X_val))) {
  stop("R93 adapter dimensions or values are invalid.", call. = FALSE)
}

code_root <- normalizePath(task$code_root, mustWork = TRUE)
source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R"), local = TRUE)
source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r72_repair_adapter.R"), local = TRUE)
source(file.path(code_root, "application/scripts/pricefm/pricefm_stage_r75_large_n_gig_adapter.R"), local = TRUE)
options(
  pricefm.expected_exdqlm_version = "1.1.1.9004",
  pricefm.expected_exdqlm_repair = paste0(
    "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-",
    "plus-structured-plugin-init"
  )
)
package <- r75_assert_repair_package(task$r_library)

normal_beta <- utils::read.csv(task$normal_beta_path, stringsAsFactors = FALSE)
normal_beta <- normal_beta[normal_beta$method_id == "normal_rhs_ns", , drop = FALSE]
normal_parameter <- utils::read.csv(task$normal_parameter_path, stringsAsFactors = FALSE)
normal_parameter <- normal_parameter[normal_parameter$method_id == "normal_rhs_ns", , drop = FALSE]
if (nrow(normal_parameter) != 1L || nrow(normal_beta) != ncol(X_train) ||
    any(!is.finite(normal_beta$beta_mean))) {
  stop("R93 normal-RHS warm start is incomplete.", call. = FALSE)
}
normal_sigma <- if ("sigma" %in% names(normal_parameter) &&
                    is.finite(normal_parameter$sigma[[1L]])) {
  as.numeric(normal_parameter$sigma[[1L]])
} else if ("omega2" %in% names(normal_parameter) &&
           is.finite(normal_parameter$omega2[[1L]]) && normal_parameter$omega2[[1L]] > 0) {
  sqrt(as.numeric(normal_parameter$omega2[[1L]]))
} else {
  NA_real_
}
if (!is.finite(normal_sigma) || normal_sigma <= 0) {
  stop("R93 normal-RHS warm-start scale is invalid.", call. = FALSE)
}

if (preflight_only) {
  cat(jsonlite::toJSON(list(
    status = "preflight_passed_not_fitted", task_id = task$task_id,
    package = package, n_train = nrow(X_train), n_features = ncol(X_train),
    quantiles = quantiles, warm_order = warm_order,
    warm_parent_by_tau = expected_parents, public_api = "exalStaticLDVB",
    test_loaded = FALSE, binary_model_artifacts_written = FALSE
  ), auto_unbox = TRUE, pretty = TRUE), "\n")
  quit(save = "no", status = 0L)
}

output <- normalizePath(task$output_dir, mustWork = FALSE)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
atoms_root <- file.path(output, "atoms")
dir.create(atoms_root, recursive = TRUE, showWarnings = FALSE)
semantic_sha <- as.character(task$semantic_contract_sha256)
method_ids <- lapply(task$method_ids, as.character)
rhs <- lapply(task$rhs, function(x) if (length(x) == 1L) unlist(x) else x)
qcfg <- lapply(task$qdesn_vb, function(x) if (length(x) == 1L) unlist(x) else x)
profile <- qcfg$structured_sigmagam

safe_sigma <- function(fit) {
  value <- fit$qsig$E_sigma %||% fit$qsiggam$sigma_mean %||% NA_real_
  as.numeric(value)[1L]
}
safe_gamma <- function(fit) {
  as.numeric(fit$qsiggam$gamma_mean %||% fit$qgam$E_gamma %||% fit$gamma %||% NA_real_)[1L]
}
structured_updates <- function(fit) {
  as.integer(fit$diagnostics$ld_block$sigmagam$update_count %||% 0L)[1L]
}
fit_public <- function(likelihood, tau, init, seed) {
  likelihood <- match.arg(likelihood, c("al", "exal"))
  control <- r67_vb_control(
    NULL, qcfg, likelihood,
    if (identical(likelihood, "exal")) profile else NULL
  )
  prior_sigma <- qcfg$prior_sigma %||% list(a = 1, b = 1)
  fit_args <- list(
    y = y_train, X = X_train, p0 = tau,
    beta_prior = "rhs_ns", beta_prior_controls = r72_rhs_controls(rhs),
    a_sigma = as.numeric(prior_sigma$a %||% 1),
    b_sigma = as.numeric(prior_sigma$b %||% 1),
    init = init, dqlm.ind = identical(likelihood, "al"),
    n.samp = as.integer(qcfg$n_samp %||% 200L),
    vb_control = control, verbose = FALSE
  )
  if (identical(likelihood, "exal")) {
    prior_gamma <- qcfg$prior_gamma %||% list(mu0 = 0, s20 = 10)
    mu0 <- as.numeric(prior_gamma$mu0 %||% 0)
    s20 <- as.numeric(prior_gamma$s20 %||% 10)
    fit_args$log_prior_gamma <- function(gamma) {
      stats::dnorm(gamma, mean = mu0, sd = sqrt(s20), log = TRUE)
    }
  }
  set.seed(as.integer(seed))
  started <- proc.time()[["elapsed"]]
  fit <- do.call(getExportedValue("exdqlm", "exalStaticLDVB"), fit_args)
  attr(fit, "r93_elapsed_seconds") <- proc.time()[["elapsed"]] - started
  fit
}

atom_dir <- function(tau, family) {
  token <- gsub("\\.", "p", sprintf("%.2f", tau))
  file.path(atoms_root, paste0("tau=", token), family)
}
read_atom <- function(tau, family) {
  root <- atom_dir(tau, family)
  terminal_path <- file.path(root, "terminal.json")
  required <- c(
    "beta_summary.csv", "parameter_summary.csv", "method_summary.csv",
    "predictions_scaled.csv", "terminal.json"
  )
  if (!all(file.exists(file.path(root, required)))) return(NULL)
  terminal <- jsonlite::read_json(terminal_path, simplifyVector = TRUE)
  if (!identical(as.character(terminal$semantic_contract_sha256), semantic_sha) ||
      !terminal$status %in% c("completed", "completed_numerically_ineligible")) return(NULL)
  beta <- utils::read.csv(file.path(root, "beta_summary.csv"))
  parameter <- utils::read.csv(file.path(root, "parameter_summary.csv"))
  if (nrow(beta) != ncol(X_train) || nrow(parameter) != 1L ||
      any(!is.finite(beta$beta_mean)) || !is.finite(parameter$sigma[[1L]])) return(NULL)
  list(
    root = root, beta = as.numeric(beta$beta_mean),
    sigma = as.numeric(parameter$sigma[[1L]]),
    gamma = as.numeric(parameter$gamma[[1L]]),
    terminal = terminal
  )
}

numerical_contract <- function(fit, family, beta, covariance, sigma, gamma,
                               prediction, init_beta_l2) {
  finite_core <- all(is.finite(beta)) && all(is.finite(covariance)) &&
    is.finite(sigma) && sigma > 0 && all(is.finite(prediction))
  checks <- list(finite_core = finite_core)
  if (identical(family, "exal")) {
    trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
    required <- c("sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s")
    trace_complete <- all(required %in% names(trace)) && nrow(trace) > 0L
    trace_finite <- trace_complete && all(is.finite(as.matrix(trace[, required, drop = FALSE])))
    updates <- structured_updates(fit)
    beta_ratio <- sqrt(sum(beta^2)) / max(init_beta_l2, .Machine$double.eps)
    first_delta <- if (trace_complete) abs(trace$delta_state[[1L]]) else Inf
    tail <- if (trace_complete) utils::tail(trace, 10L) else data.frame()
    tail_delta <- if (nrow(tail)) max(abs(c(tail$delta_state, tail$delta_sigma))) else Inf
    checks <- c(checks, list(
      trace_complete = trace_complete, trace_finite = trace_finite,
      structured_updates = updates >= 35L, sigma_below_100 = sigma < 100,
      gamma_bounded = is.finite(gamma) && abs(gamma) < 4,
      beta_l2_ratio_below_10 = is.finite(beta_ratio) && beta_ratio < 10,
      first_state_delta_below_100 = is.finite(first_delta) && first_delta < 100,
      tail_state_sigma_delta_below_2 = is.finite(tail_delta) && tail_delta < 2
    ))
  }
  list(passed = all(vapply(checks, isTRUE, logical(1L))), checks = checks)
}

write_atom <- function(fit, tau, family, method_id, init_label, init_beta_l2) {
  root <- atom_dir(tau, family)
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  beta <- as.numeric(fit$qbeta$m)
  covariance <- as.matrix(fit$qbeta$V)
  sigma <- safe_sigma(fit)
  gamma <- if (identical(family, "exal")) safe_gamma(fit) else 0
  prediction <- as.numeric(X_val %*% beta)
  contract <- numerical_contract(
    fit, family, beta, covariance, sigma, gamma, prediction, init_beta_l2
  )
  updates <- if (identical(family, "exal")) structured_updates(fit) else 0L
  method <- data.frame(
    method_id = method_id, model_family = "independent_qdesn_static_readout",
    likelihood_family = family, prior_family = "rhs_ns", tau = tau,
    inference_engine = "VB", posterior_approximation = ifelse(
      family == "exal", "structured_sigma_gamma", "mean_field_al"
    ),
    converged = isTRUE(fit$converged), iter = as.integer(fit$iter %||% NA_integer_),
    train_seconds = as.numeric(attr(fit, "r93_elapsed_seconds")),
    n_train = nrow(X_train), n_features = ncol(X_train),
    structured_updates = updates, package_version = package$version,
    package_repository = package$repository, repair = package$repair,
    init_source = init_label, numerical_gate_passed = contract$passed,
    test_loaded = FALSE, binary_model_artifact_written = FALSE,
    stringsAsFactors = FALSE
  )
  parameter <- data.frame(
    method_id = method_id, likelihood_family = family, tau = tau,
    beta_l2 = sqrt(sum(beta^2)), beta_max_abs = max(abs(beta)),
    beta_cov_trace = sum(diag(covariance)), sigma = sigma, gamma = gamma,
    init_beta_l2 = init_beta_l2, stringsAsFactors = FALSE
  )
  predictions <- data.frame(
    method_id = method_id, split = "val", origin_id = rows_val$origin_id,
    horizon = rows_val$horizon, tau = tau, pred_scaled = prediction,
    stringsAsFactors = FALSE
  )
  trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
  if (nrow(trace)) {
    trace$method_id <- method_id
    trace$likelihood_family <- family
    trace$tau <- tau
  }
  write_csv(data.frame(
    method_id = method_id, tau = tau, feature_index = seq_along(beta),
    beta_mean = beta, beta_cov_diag = diag(covariance)
  ), file.path(root, "beta_summary.csv"))
  write_csv(parameter, file.path(root, "parameter_summary.csv"))
  write_csv(method, file.path(root, "method_summary.csv"))
  write_csv(predictions, file.path(root, "predictions_scaled.csv"))
  if (nrow(trace)) write_csv(trace, file.path(root, "vb_trace.csv"))
  write_json(list(
    status = if (contract$passed) "completed" else "completed_numerically_ineligible",
    task_id = task$task_id, family = family, tau = tau,
    semantic_contract_sha256 = semantic_sha,
    numerical_gate_passed = contract$passed, numerical_checks = contract$checks,
    formal_converged = isTRUE(fit$converged), structured_updates = updates,
    test_loaded = FALSE, binary_model_artifact_written = FALSE
  ), file.path(root, "terminal.json"))
  read_atom(tau, family)
}

fit_or_resume <- function(tau, family, init, init_label, seed) {
  existing <- read_atom(tau, family)
  if (!is.null(existing)) return(existing)
  root <- atom_dir(tau, family)
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  init_beta_l2 <- sqrt(sum(as.numeric(init$beta)^2))
  fit <- tryCatch(
    fit_public(family, tau, init, seed),
    error = function(error) {
      write_json(list(
        status = "failed", task_id = task$task_id, family = family, tau = tau,
        semantic_contract_sha256 = semantic_sha,
        error_class = class(error), error_message = conditionMessage(error),
        test_loaded = FALSE, binary_model_artifact_written = FALSE
      ), file.path(root, "terminal.json"))
      stop(error)
    }
  )
  write_atom(fit, tau, family, task$method_ids[[family]], init_label, init_beta_l2)
}

normal_state <- list(beta = as.numeric(normal_beta$beta_mean), sigma = normal_sigma)
al_states <- list()
atom_rows <- list()
warm_rows <- list()
for (order_index in seq_along(warm_order)) {
  tau <- warm_order[[order_index]]
  tau_key <- sprintf("%.2f", tau)
  parent <- as.character(expected_parents[[tau_key]])
  if (identical(parent, "outer_normal_rhs")) {
    al_init <- normal_state
    al_label <- parent
  } else {
    al_init <- al_states[[parent]]
    al_label <- paste0("al_tau_", parent)
    if (is.null(al_init)) stop("R93 AL warm parent is unavailable: ", parent, call. = FALSE)
  }
  al <- fit_or_resume(
    tau, "al", al_init, al_label,
    as.integer(task$semantic_contract$seed) + order_index * 10L
  )
  if (!isTRUE(al$terminal$numerical_gate_passed)) {
    stop("R93 AL atom failed its finite numerical contract at tau=", tau, call. = FALSE)
  }
  warm_rows[[length(warm_rows) + 1L]] <- data.frame(
    method_id = task$method_ids$al, likelihood_family = "al", tau = tau,
    fit_order = order_index, init_source = al_label,
    fallback_used = FALSE, numerical_gate_passed = TRUE
  )
  al_states[[tau_key]] <- list(beta = al$beta, sigma = al$sigma)
  atom_rows[[length(atom_rows) + 1L]] <- data.frame(
    family = "al", tau = tau, status = al$terminal$status,
    numerical_gate_passed = al$terminal$numerical_gate_passed,
    formal_converged = al$terminal$formal_converged,
    root = al$root, stringsAsFactors = FALSE
  )
  exal_init <- list(beta = al$beta, sigma = al$sigma, gamma = 0)
  exal <- tryCatch(
    fit_or_resume(
      tau, "exal", exal_init, paste0("al_same_tau_", tau),
      as.integer(task$semantic_contract$seed) + order_index * 10L + 1L
    ),
    error = function(error) NULL
  )
  if (is.null(exal)) {
    atom_rows[[length(atom_rows) + 1L]] <- data.frame(
      family = "exal", tau = tau, status = "failed",
      numerical_gate_passed = FALSE, formal_converged = FALSE,
      root = atom_dir(tau, "exal"), stringsAsFactors = FALSE
    )
  } else {
    atom_rows[[length(atom_rows) + 1L]] <- data.frame(
      family = "exal", tau = tau, status = exal$terminal$status,
      numerical_gate_passed = exal$terminal$numerical_gate_passed,
      formal_converged = exal$terminal$formal_converged,
      root = exal$root, stringsAsFactors = FALSE
    )
    warm_rows[[length(warm_rows) + 1L]] <- data.frame(
      method_id = task$method_ids$exal, likelihood_family = "exal", tau = tau,
      fit_order = order_index, init_source = paste0("al_same_tau_", tau),
      fallback_used = FALSE,
      numerical_gate_passed = exal$terminal$numerical_gate_passed
    )
  }
}

atoms <- do.call(rbind, atom_rows)
write_csv(atoms, file.path(output, "exal_atom_status.csv"))
write_csv(do.call(rbind, warm_rows), file.path(output, "warm_start_diagnostics.csv"))
al_complete <- nrow(atoms[atoms$family == "al" & atoms$numerical_gate_passed, ]) == 7L
exal_complete <- nrow(atoms[atoms$family == "exal" & atoms$numerical_gate_passed, ]) == 7L
if (!al_complete) stop("R93 complete finite AL surface is absent.", call. = FALSE)

included <- atoms[atoms$family == "al" | (atoms$family == "exal" & exal_complete), ]
bind_atom_file <- function(name) {
  values <- lapply(included$root, function(root) {
    path <- file.path(root, name)
    if (file.exists(path)) utils::read.csv(path, stringsAsFactors = FALSE) else NULL
  })
  values <- Filter(Negate(is.null), values)
  if (length(values)) do.call(rbind, values) else data.frame()
}
write_csv(bind_atom_file("predictions_scaled.csv"), file.path(output, "model_predictions_scaled.csv"))
write_csv(bind_atom_file("method_summary.csv"), file.path(output, "model_method_summary.csv"))
write_csv(bind_atom_file("parameter_summary.csv"), file.path(output, "model_parameter_summary.csv"))
traces <- bind_atom_file("vb_trace.csv")
if (nrow(traces)) write_csv(traces, file.path(output, "model_trace_summary.csv"))
write_json(list(
  status = "completed_validation_surface",
  task_id = task$task_id, semantic_contract_sha256 = semantic_sha,
  al_surface_complete = al_complete,
  exal_surface_complete = nrow(atoms[atoms$family == "exal" & atoms$status != "failed", ]) == 7L,
  exal_surface_numerically_eligible = exal_complete,
  al_formal_convergence_count = sum(atoms$family == "al" & atoms$formal_converged),
  exal_formal_convergence_count = sum(atoms$family == "exal" & atoms$formal_converged),
  package = package, public_api = "exalStaticLDVB",
  warm_start_chain = "outer_normal_rhs_to_al_adjacent_then_exal_same_tau",
  test_loaded = FALSE, binary_model_artifacts_written = FALSE,
  registry_mutated = FALSE, article_mutated = FALSE,
  joint_or_mcmc_authorized = FALSE
), file.path(output, "pricefm_stage_r93_quantile_run_summary.json"))
cat(jsonlite::toJSON(list(
  status = "completed_validation_surface", al_complete = al_complete,
  exal_numerically_eligible = exal_complete, output_dir = output,
  test_loaded = FALSE
), auto_unbox = TRUE, pretty = TRUE), "\n")
