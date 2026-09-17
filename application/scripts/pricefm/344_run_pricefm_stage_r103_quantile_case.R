#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
arg <- function(flag, default = NULL) {
  index <- match(flag, args)
  if (is.na(index) || index == length(args)) return(default)
  args[[index + 1L]]
}
as_flag <- function(value) tolower(as.character(value %||% "false")) %in% c("1", "true", "yes")

config_path <- arg("--case-config")
preflight_only <- as_flag(arg("--preflight-only", "false"))
if (is.null(config_path)) stop("--case-config is required", call. = FALSE)
config_path <- normalizePath(config_path, mustWork = TRUE)
config <- jsonlite::read_json(config_path, simplifyVector = FALSE)
output <- normalizePath(config$output_dir, mustWork = FALSE)

sha256 <- function(path) {
  value <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(value[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
write_json <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".tmp.", Sys.getpid())
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)
  jsonlite::write_json(value, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (!file.rename(temporary, path)) stop("atomic JSON rename failed", call. = FALSE)
}
read_f64 <- function(path, n) {
  handle <- file(path, open = "rb")
  on.exit(close(handle), add = TRUE)
  value <- readBin(handle, what = "double", n = n, size = 8L, endian = "little")
  if (length(value) != n || any(!is.finite(value))) stop("invalid float64 artifact: ", path, call. = FALSE)
  value
}
write_f64 <- function(path, value, row_major = FALSE) {
  handle <- file(path, open = "wb")
  on.exit(close(handle), add = TRUE)
  payload <- if (row_major) as.double(t(value)) else as.double(value)
  writeBin(payload, handle, size = 8L, endian = "little")
}
records <- function(value) {
  if (is.data.frame(value)) lapply(seq_len(nrow(value)), function(i) as.list(value[i, , drop = FALSE])) else value
}

blocked <- c(
  "test_access_authorized", "joint_model_authorized", "mcmc_authorized",
  "registry_mutation_authorized", "article_mutation_authorized"
)
if (!identical(config$stage, "R103") || !identical(config$selection_split, "validation_only") ||
    !identical(config$training_split, "train_only_causal_teacher_forced") ||
    !identical(config$test_opened, FALSE) ||
    any(vapply(blocked, function(name) !identical(config[[name]], FALSE), logical(1L)))) {
  stop("R103 case firewall violation", call. = FALSE)
}
runtime_manifest <- jsonlite::read_json(config$runtime_manifest, simplifyVector = FALSE)
expected_repair <- paste0(
  "scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-",
  "plus-structured-plugin-init-plus-coherent-al-latent-init"
)
if (!identical(sha256(config$runtime_manifest), config$runtime_manifest_sha256) ||
    !identical(runtime_manifest$version, "1.1.1.9005") ||
    !identical(runtime_manifest$repair, expected_repair) ||
    !identical(runtime_manifest$test_opened, FALSE)) {
  stop("R103 runtime provenance mismatch", call. = FALSE)
}
for (record in records(config$adapters)) {
  if (!identical(sha256(record$path), record$sha256)) stop("R103 adapter hash mismatch", call. = FALSE)
  source(record$path, local = TRUE)
}
options(
  pricefm.expected_exdqlm_version = "1.1.1.9005",
  pricefm.expected_exdqlm_repair = expected_repair
)
package <- r75_assert_repair_package(config$runtime_library)

design <- jsonlite::read_json(file.path(config$design_dir, "design.json"), simplifyVector = FALSE)
design_terminal <- jsonlite::read_json(file.path(config$design_dir, "terminal.json"), simplifyVector = FALSE)
if (!identical(design_terminal$status, "completed_causal_quantile_design") ||
    !identical(design_terminal$test_opened, FALSE)) {
  stop("R103 causal design terminal is invalid", call. = FALSE)
}
for (name in names(design_terminal$files)) {
  if (!identical(sha256(file.path(config$design_dir, name)), design_terminal$files[[name]]$sha256)) {
    stop("R103 causal design hash mismatch: ", name, call. = FALSE)
  }
}
n <- as.integer(design$n)
p <- as.integer(design$p)
X <- matrix(read_f64(file.path(config$design_dir, "X.bin"), n * p), nrow = n, byrow = TRUE)
y <- read_f64(file.path(config$design_dir, "y.bin"), n)
if (nrow(X) != length(y) || any(!is.finite(X)) || any(!is.finite(y))) {
  stop("R103 causal design is invalid", call. = FALSE)
}

artifact_ok <- function(path, atom_id) {
  terminal_path <- file.path(path, "terminal.json")
  if (!file.exists(terminal_path)) return(FALSE)
  value <- tryCatch(jsonlite::read_json(terminal_path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(value) || !identical(value$status, "completed_recursive_quantile_atom") ||
      !identical(value$atom_id, atom_id) || !identical(value$test_opened, FALSE)) return(FALSE)
  all(vapply(records(value$artifacts), function(record) {
    file.exists(record$path) && identical(sha256(record$path), record$sha256)
  }, logical(1L)))
}

read_parent <- function(atom) {
  family <- atom$parent_family
  tau <- atom$parent_tau
  if (identical(family, "normal_rhs")) {
    terminal <- jsonlite::read_json(file.path(config$normal_fit_dir, "terminal.json"), simplifyVector = FALSE)
    if (!identical(terminal$status, "completed_recursive_normal_fit") ||
        !identical(terminal$prior_type, "rhs_ns") || !isTRUE(terminal$converged) ||
        !identical(terminal$test_opened, FALSE)) {
      stop("R103 Normal-RHS initializer is invalid", call. = FALSE)
    }
    for (record in records(terminal$artifacts)) {
      path <- file.path(config$normal_fit_dir, record$path)
      if (!identical(sha256(path), record$sha256)) stop("R103 Normal-RHS artifact changed", call. = FALSE)
    }
    beta <- read_f64(file.path(config$normal_fit_dir, "beta_mean.bin"), p)
    covariance <- matrix(read_f64(file.path(config$normal_fit_dir, "beta_cov.bin"), p * p), nrow = p, byrow = TRUE)
    variance <- as.numeric(terminal$omega_rate) / max(as.numeric(terminal$omega_shape) - 1, 1e-8)
    return(list(beta = beta, covariance = covariance, sigma = sqrt(variance), source = "normal_rhs_same_case"))
  }
  matches <- Filter(function(candidate) {
    identical(candidate$family, family) && isTRUE(all.equal(as.numeric(candidate$tau), as.numeric(tau)))
  }, records(config$atoms))
  if (length(matches) != 1L) stop("R103 warm parent is missing or duplicated", call. = FALSE)
  parent <- matches[[1L]]
  if (!artifact_ok(parent$output_dir, parent$atom_id)) stop("R103 warm parent is incomplete", call. = FALSE)
  parent_terminal <- jsonlite::read_json(file.path(parent$output_dir, "terminal.json"), simplifyVector = FALSE)
  beta <- read_f64(file.path(parent$output_dir, "beta_mean.bin"), p)
  covariance <- matrix(read_f64(file.path(parent$output_dir, "beta_cov.bin"), p * p), nrow = p, byrow = TRUE)
  parameters <- jsonlite::read_json(file.path(parent$output_dir, "parameter_summary.json"), simplifyVector = FALSE)
  list(
    beta = beta,
    covariance = covariance,
    sigma = as.numeric(parameters$sigma),
    source = paste0(family, "_", format(as.numeric(tau), nsmall = 2), "_same_case"),
    terminal = parent_terminal
  )
}

if (preflight_only) {
  first <- records(config$atoms)[[1L]]
  init <- read_parent(first)
  cat(jsonlite::toJSON(list(
    status = "preflight_passed_not_fitted", case_id = config$case_id,
    n = n, p = p, first_parent = init$source, package = package,
    test_opened = FALSE
  ), auto_unbox = TRUE, pretty = TRUE), "\n")
  quit(status = 0L)
}

fit_atom <- function(atom) {
  cached <- artifact_ok(atom$output_dir, atom$atom_id)
  cached_terminal <- if (cached) {
    jsonlite::read_json(file.path(atom$output_dir, "terminal.json"), simplifyVector = FALSE)
  } else NULL
  if (cached && (identical(atom$family, "exal") || isTRUE(cached_terminal$numerical_gate_passed))) {
    return(cached_terminal)
  }
  parent <- read_parent(atom)
  init <- list(beta = parent$beta, sigma = parent$sigma)
  if (identical(atom$family, "exal")) {
    init$beta_cov_diag <- diag(parent$covariance)
    init$gamma <- 0
    init$warm_start_mode <- "al_qbeta_rhs_latent_first"
  }
  rhs <- lapply(config$rhs, function(value) if (length(value) == 1L) unlist(value) else value)
  qcfg <- lapply(config$qdesn_vb, function(value) if (length(value) == 1L) unlist(value) else value)
  profile <- qcfg$structured_sigmagam
  set.seed(as.integer(atom$seed))
  started <- proc.time()[["elapsed"]]
  if (identical(atom$family, "exal")) {
    fit <- r75_fit_quantile(
      config$runtime_library, X, y, atom$tau, rhs, qcfg, profile,
      init = init, seed = atom$seed
    )
  } else {
    prior_sigma <- qcfg$prior_sigma %||% list(a = 1, b = 1)
    configured_max_iter <- as.integer(qcfg$max_iter %||% 500L)
    retry_max_iter <- max(configured_max_iter, 750L)
    effective_max_iter <- if (cached && !isTRUE(cached_terminal$numerical_gate_passed)) {
      retry_max_iter
    } else configured_max_iter
    fit_al <- function(max_iter) {
      fit_qcfg <- qcfg
      fit_qcfg$max_iter <- as.integer(max_iter)
      control <- r67_vb_control(NULL, fit_qcfg, "al", NULL)
      set.seed(as.integer(atom$seed))
      do.call(getExportedValue("exdqlm", "exalStaticLDVB"), list(
        y = y, X = X, p0 = as.numeric(atom$tau),
        beta_prior = "rhs_ns", beta_prior_controls = r72_rhs_controls(rhs),
        a_sigma = as.numeric(prior_sigma$a %||% 1),
        b_sigma = as.numeric(prior_sigma$b %||% 1),
        init = init, dqlm.ind = TRUE,
        n.samp = as.integer(qcfg$n_samp %||% 200L),
        vb_control = control, verbose = FALSE
      ))
    }
    fit <- fit_al(effective_max_iter)
    if (!isTRUE(fit$converged) && effective_max_iter < retry_max_iter) {
      effective_max_iter <- retry_max_iter
      fit <- fit_al(effective_max_iter)
    }
  }
  elapsed <- proc.time()[["elapsed"]] - started
  beta <- as.numeric(fit$qbeta$m)
  covariance <- as.matrix(fit$qbeta$V)
  sigma <- as.numeric(fit$qsig$E_sigma %||% fit$qsiggam$sigma_mean %||% NA_real_)[1L]
  gamma <- if (identical(atom$family, "exal")) {
    as.numeric(fit$qsiggam$gamma_mean %||% fit$qgam$E_gamma %||% NA_real_)[1L]
  } else 0
  trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
  deltas <- fit$diagnostics$deltas %||% list()
  if (identical(atom$family, "exal") && nrow(trace)) {
    if (!"delta_state_relative" %in% names(trace)) {
      value <- as.numeric(deltas$state_relative)
      if (length(value) != nrow(trace)) stop("R103 relative-state trace length mismatch", call. = FALSE)
      trace$delta_state_relative <- value
    }
    if (!"delta_prediction_scaled" %in% names(trace)) {
      value <- as.numeric(deltas$prediction_scaled)
      if (length(value) != nrow(trace)) stop("R103 prediction-scale trace length mismatch", call. = FALSE)
      trace$delta_prediction_scaled <- value
    }
  }
  finite_core <- length(beta) == p && all(is.finite(beta)) &&
    all(dim(covariance) == c(p, p)) && all(is.finite(covariance)) &&
    all(diag(covariance) > 0) && is.finite(sigma) && sigma > 0
  checks <- list(finite_core = finite_core, formal_converged = isTRUE(fit$converged))
  updates <- 0L
  if (identical(atom$family, "exal")) {
    required <- c(
      "sigma", "gamma", "delta_state", "delta_sigma", "delta_gamma", "delta_s",
      "delta_state_relative", "delta_prediction_scaled"
    )
    complete <- nrow(trace) > 0L && all(required %in% names(trace))
    finite_trace <- complete && all(is.finite(as.matrix(trace[, required, drop = FALSE])))
    tail <- if (complete) utils::tail(trace, 10L) else data.frame()
    updates <- as.integer(fit$diagnostics$ld_block$sigmagam$update_count %||% 0L)
    coherent <- isTRUE(fit$misc$coherent_al_init) && isTRUE(fit$misc$latent_first_initialized) &&
      identical(fit$misc$beta_covariance_source, "al_beta_cov_diag")
    checks <- c(checks, list(
      trace_complete = complete,
      trace_finite = finite_trace,
      coherent_warm_start_recorded = coherent,
      structured_updates_at_least_35 = updates >= 35L,
      sigma_below_100 = is.finite(sigma) && sigma < 100,
      gamma_bounded = is.finite(gamma) && abs(gamma) < 4,
      tail_relative_state_below_0p01 = nrow(tail) > 0L && max(abs(tail$delta_state_relative)) < 0.01,
      tail_prediction_scaled_below_0p01 = nrow(tail) > 0L && max(abs(tail$delta_prediction_scaled)) < 0.01
    ))
  }
  numerical_passed <- all(vapply(checks, isTRUE, logical(1L)))
  parent_dir <- dirname(atom$output_dir)
  dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = paste0(basename(atom$output_dir), ".tmp."), tmpdir = parent_dir)
  dir.create(temporary)
  on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
  write_f64(file.path(temporary, "beta_mean.bin"), beta)
  write_f64(file.path(temporary, "beta_cov.bin"), covariance, row_major = TRUE)
  parameters <- list(
    family = atom$family, tau = as.numeric(atom$tau), sigma = sigma, gamma = gamma,
    train_seconds = as.numeric(elapsed), iterations = as.integer(fit$iter %||% nrow(trace)),
    formal_converged = isTRUE(fit$converged), structured_updates = updates,
    configured_max_iter = as.integer(qcfg$max_iter %||% 500L),
    effective_max_iter = if (identical(atom$family, "al")) effective_max_iter else as.integer(qcfg$max_iter %||% 500L),
    extended_nonconvergence_retry = identical(atom$family, "al") && effective_max_iter > as.integer(qcfg$max_iter %||% 500L),
    init_source = parent$source, initialization_only = TRUE,
    prior_center_from_initializer = FALSE
  )
  write_json(parameters, file.path(temporary, "parameter_summary.json"))
  write_json(list(checks = checks, passed = numerical_passed), file.path(temporary, "numerical_gate.json"))
  if (nrow(trace)) utils::write.csv(trace, file.path(temporary, "vb_trace.csv"), row.names = FALSE)
  names <- list.files(temporary, full.names = FALSE)
  artifacts <- lapply(names, function(name) list(
    path = normalizePath(file.path(atom$output_dir, name), mustWork = FALSE),
    role = sub("\\.bin$|\\.json$|\\.csv$", "", name),
    bytes = file.info(file.path(temporary, name))$size,
    sha256 = sha256(file.path(temporary, name))
  ))
  terminal <- list(
    status = "completed_recursive_quantile_atom",
    stage = "R103", atom_id = atom$atom_id, case_id = config$case_id,
    region = config$region, fold = as.integer(config$fold),
    family = atom$family, tau = as.numeric(atom$tau),
    posterior_target_sha256 = atom$posterior_target_sha256,
    numerical_gate_passed = numerical_passed,
    numerical_checks = checks,
    diagnostic_gate_method = if (identical(atom$family, "exal")) {
      "exact_runtime_diagnostics"
    } else {
      "not_applicable_al"
    },
    formal_converged = isTRUE(fit$converged),
    configured_max_iter = as.integer(qcfg$max_iter %||% 500L),
    effective_max_iter = if (identical(atom$family, "al")) effective_max_iter else as.integer(qcfg$max_iter %||% 500L),
    extended_nonconvergence_retry = identical(atom$family, "al") && effective_max_iter > as.integer(qcfg$max_iter %||% 500L),
    train_seconds = as.numeric(elapsed), iterations = as.integer(fit$iter %||% nrow(trace)),
    n = n, p = p, init_source = parent$source,
    initialization_only = TRUE, prior_center_from_initializer = FALSE,
    package = package, artifacts = artifacts,
    test_opened = FALSE, test_access_authorized = FALSE,
    joint_model_fitted = FALSE, mcmc_fitted = FALSE,
    registry_mutated = FALSE, article_mutated = FALSE
  )
  write_json(terminal, file.path(temporary, "terminal.json"))
  if (dir.exists(atom$output_dir)) unlink(atom$output_dir, recursive = TRUE, force = TRUE)
  if (!file.rename(temporary, atom$output_dir)) stop("R103 atom atomic install failed", call. = FALSE)
  terminal
}

dir.create(output, recursive = TRUE, showWarnings = FALSE)
write_json(list(
  status = "started", stage = "R103", case_id = config$case_id,
  pid = Sys.getpid(), case_config = config_path,
  case_config_sha256 = sha256(config_path), test_opened = FALSE
), file.path(output, "fit_started.json"))
atom_terminals <- lapply(records(config$atoms), fit_atom)
if (length(atom_terminals) != 14L || any(!vapply(atom_terminals, function(value) {
  identical(value$status, "completed_recursive_quantile_atom")
}, logical(1L)))) {
  stop("R103 case did not complete all 14 atoms", call. = FALSE)
}
summary <- list(
  status = "completed_recursive_quantile_fits",
  stage = "R103", case_id = config$case_id, region = config$region,
  fold = as.integer(config$fold), atoms_complete = 14L,
  atoms_numerically_eligible = sum(vapply(atom_terminals, function(value) isTRUE(value$numerical_gate_passed), logical(1L))),
  atom_terminals = lapply(atom_terminals, function(value) list(
    atom_id = value$atom_id,
    path = normalizePath(file.path(Filter(function(atom) identical(atom$atom_id, value$atom_id), records(config$atoms))[[1L]]$output_dir, "terminal.json"), mustWork = TRUE),
    sha256 = sha256(file.path(Filter(function(atom) identical(atom$atom_id, value$atom_id), records(config$atoms))[[1L]]$output_dir, "terminal.json"))
  )),
  package = package, test_opened = FALSE,
  registry_mutated = FALSE, article_mutated = FALSE,
  joint_model_fitted = FALSE, mcmc_fitted = FALSE
)
write_json(summary, file.path(output, "fit_terminal.json"))
cat(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n")
