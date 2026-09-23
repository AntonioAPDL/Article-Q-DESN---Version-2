#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
arg <- function(flag) {
  where <- match(flag, args)
  if (is.na(where) || where == length(args)) stop("missing ", flag, call. = FALSE)
  args[[where + 1L]]
}
flag <- function(name) {
  where <- match(name, args)
  if (is.na(where) || where == length(args)) return(FALSE)
  tolower(args[[where + 1L]]) %in% c("1", "true", "yes")
}
sha256 <- function(path) {
  value <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(value[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
write_json <- function(value, path) {
  jsonlite::write_json(value, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
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
atom_label <- function(tau) sub("\\.", "p", format(as.numeric(tau), trim = TRUE, scientific = FALSE))

contract_path <- normalizePath(arg("--contract"), mustWork = TRUE)
contract <- jsonlite::read_json(contract_path, simplifyVector = FALSE)
blocked <- c(
  "test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized",
  "mcmc_authorized", "joint_model_authorized"
)
is_r114 <- identical(contract$stage, "R114") &&
  identical(contract$phase, "training_only_driver_fit") &&
  identical(contract$selection_split, "BG_fold1_training_nested_temporal_only")
is_r116 <- identical(contract$stage, "R116") &&
  contract$phase %in% c("training_only_likelihood_fit", "outer_transfer_readout_fit") &&
  contract$selection_split %in% c(
    "BG_fold1_training_nested_temporal_only", "BG_outer_fold_training_only"
  )
if (!(is_r114 || is_r116) ||
    !(contract$family %in% c("al", "exal")) ||
    any(vapply(blocked, function(name) !identical(contract[[name]], FALSE), logical(1L)))) {
  stop("R114/R116 fit firewall violation", call. = FALSE)
}
atom_status <- if (is_r114) "completed_r114_quantile_atom" else "completed_r116_quantile_atom"
family_status <- if (is_r114) "completed_r114_quantile_family_fit" else "completed_r116_quantile_family_fit"
axis_name <- if (identical(contract$phase, "outer_transfer_readout_fit")) "fold" else "inner_fold"
axis_value <- as.integer(contract[[axis_name]])
if (!is.finite(axis_value) || !(axis_value %in% 1:3)) stop("invalid fit axis", call. = FALSE)
output_dir <- normalizePath(contract$output_dir, mustWork = FALSE)
terminal_path <- file.path(output_dir, "terminal.json")
if (file.exists(terminal_path)) {
  existing <- jsonlite::read_json(terminal_path, simplifyVector = FALSE)
  if (identical(existing$status, family_status) &&
      identical(existing$task_contract_sha256, contract$task_contract_sha256)) {
    cat(jsonlite::toJSON(existing, auto_unbox = TRUE, pretty = TRUE), "\n")
    quit(status = 0L)
  }
}
if (!identical(sha256(contract$runtime_manifest), contract$runtime_manifest_sha256) ||
    !identical(sha256(contract$split_csv_path), contract$split_csv_sha256)) {
  stop("R114/R116 frozen runtime or split hash changed", call. = FALSE)
}
source(normalizePath(contract$adapter_path, mustWork = TRUE), local = .GlobalEnv)
package <- r67_assert_cran_package(contract$runtime_library, expected_version = "1.1.1")

design_meta <- jsonlite::read_json(file.path(contract$design_dir, "design.json"), simplifyVector = FALSE)
design_terminal <- jsonlite::read_json(file.path(contract$design_dir, "terminal.json"), simplifyVector = FALSE)
if (!identical(design_terminal$status, "completed_causal_quantile_design") ||
    !identical(design_terminal$test_opened, FALSE)) stop("R114/R116 source design is invalid", call. = FALSE)
for (name in names(design_terminal$files)) {
  if (!identical(sha256(file.path(contract$design_dir, name)), design_terminal$files[[name]]$sha256)) {
    stop("R114/R116 source design changed: ", name, call. = FALSE)
  }
}
n <- as.integer(design_meta$n); p <- as.integer(design_meta$p)
X_all <- matrix(read_f64(file.path(contract$design_dir, "X.bin"), n * p), nrow = n, byrow = TRUE)
y_all <- read_f64(file.path(contract$design_dir, "y.bin"), n)
split <- utils::read.csv(contract$split_csv_path, stringsAsFactors = FALSE)
fit_index <- as.integer(split$design_index_zero_based[split$split == "train"]) + 1L
if (!length(fit_index) || any(fit_index < 1L | fit_index > n)) stop("R114/R116 fit indices are invalid", call. = FALSE)
X <- X_all[fit_index, , drop = FALSE]
y <- y_all[fit_index]
rm(X_all, y_all); gc(verbose = FALSE)

if (flag("--preflight-only")) {
  cat(jsonlite::toJSON(list(
    stage = contract$stage, status = "preflight_passed_not_fitted",
    task_id = contract$task_id, family = contract$family,
    fit_axis = axis_name, fit_axis_value = axis_value, n = nrow(X), p = ncol(X),
    package_version = package$version, package_repository = package$repository,
    public_api = "exalStaticLDVB", test_opened = FALSE
  ), auto_unbox = TRUE, pretty = TRUE), "\n")
  quit(status = 0L)
}

rhs <- lapply(contract$rhs, function(value) if (length(value) == 1L) unlist(value) else value)
qcfg <- lapply(contract$vb, function(value) if (length(value) == 1L) unlist(value) else value)
profile <- qcfg$structured_sigmagam
quantiles <- as.numeric(unlist(contract$quantiles))
warm_order <- c(0.50, 0.45, 0.25, 0.10, 0.55, 0.75, 0.90)
if (!setequal(quantiles, warm_order)) stop("R114 quantile grid changed", call. = FALSE)

read_atom_init <- function(path, gamma_zero = FALSE) {
  terminal <- jsonlite::read_json(file.path(path, "terminal.json"), simplifyVector = FALSE)
  if (!identical(terminal$status, atom_status) ||
      !identical(terminal$test_opened, FALSE) || as.integer(terminal$p) != p) {
    stop("R114/R116 warm-start atom is invalid: ", path, call. = FALSE)
  }
  parameters <- jsonlite::read_json(file.path(path, "parameter_summary.json"), simplifyVector = FALSE)
  value <- list(
    beta = read_f64(file.path(path, "beta_mean.bin"), p),
    sigma = as.numeric(parameters$sigma)
  )
  if (isTRUE(gamma_zero)) value$gamma <- 0
  value
}
parent_tau <- function(tau) {
  if (abs(tau - 0.50) < 1e-12) return(NA_real_)
  if (abs(tau - 0.45) < 1e-12) return(0.50)
  if (abs(tau - 0.25) < 1e-12) return(0.45)
  if (abs(tau - 0.10) < 1e-12) return(0.25)
  if (abs(tau - 0.55) < 1e-12) return(0.50)
  if (abs(tau - 0.75) < 1e-12) return(0.55)
  if (abs(tau - 0.90) < 1e-12) return(0.75)
  stop("unknown R114 quantile", call. = FALSE)
}

parent <- dirname(output_dir)
dir.create(parent, recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(pattern = paste0(basename(output_dir), ".tmp."), tmpdir = parent)
dir.create(temporary)
on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
atom_rows <- list()
for (position in seq_along(warm_order)) {
  tau <- warm_order[[position]]
  label <- atom_label(tau)
  atom_dir <- file.path(temporary, paste0("tau=", label))
  dir.create(atom_dir)
  if (identical(contract$family, "al")) {
    parent_value <- parent_tau(tau)
    if (is.na(parent_value)) {
      sigma <- stats::sd(y)
      if (!is.finite(sigma) || sigma <= 0) sigma <- 1
      init <- list(beta = rep(0, p), sigma = sigma)
      init_source <- "neutral_training_only"
    } else {
      init <- read_atom_init(file.path(temporary, paste0("tau=", atom_label(parent_value))))
      init_source <- paste0("same_family_tau_", parent_value)
    }
  } else {
    source_dir <- file.path(normalizePath(contract$al_initializer_dir, mustWork = TRUE), paste0("tau=", label))
    init <- read_atom_init(source_dir, gamma_zero = TRUE)
    init_source <- paste0("matching_AL_tau_", tau)
  }
  started <- proc.time()[["elapsed"]]
  fit <- r67_fit_quantile(
    contract$runtime_library, X, y, tau, contract$family, rhs, qcfg,
    profile = if (identical(contract$family, "exal")) profile else NULL,
    init = init, seed = as.integer(contract$seed) + position,
    expected_version = "1.1.1"
  )
  elapsed <- proc.time()[["elapsed"]] - started
  beta <- as.numeric(fit$qbeta$m)
  covariance <- as.matrix(fit$qbeta$V)
  sigma <- r67_safe_sigma(fit)
  gamma <- if (identical(contract$family, "exal")) {
    as.numeric(fit$qsiggam$gamma_mean %||% fit$qgam$E_gamma %||% NA_real_)[1L]
  } else 0
  finite <- length(beta) == p && all(is.finite(beta)) && all(dim(covariance) == c(p, p)) &&
    all(is.finite(covariance)) && all(diag(covariance) > 0) && is.finite(sigma) && sigma > 0 &&
    is.finite(gamma)
  trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
  write_f64(file.path(atom_dir, "beta_mean.bin"), beta)
  write_f64(file.path(atom_dir, "beta_cov.bin"), covariance, row_major = TRUE)
  if (nrow(trace)) utils::write.csv(trace, file.path(atom_dir, "vb_trace.csv"), row.names = FALSE)
  parameters <- list(
    family = contract$family, tau = tau, tau0 = as.numeric(rhs$tau0), sigma = sigma,
    gamma = gamma, n = nrow(X), p = p, train_seconds = as.numeric(elapsed),
    iterations = as.integer(fit$iter %||% nrow(trace)), formal_converged = isTRUE(fit$converged),
    finite_core = finite, init_source = init_source, initialization_only = TRUE,
    prior_center_from_initializer = FALSE, package_version = package$version,
    package_repository = package$repository, public_api = "exalStaticLDVB"
  )
  write_json(parameters, file.path(atom_dir, "parameter_summary.json"))
  artifacts <- lapply(list.files(atom_dir, full.names = FALSE), function(name) list(
    path = name, bytes = file.info(file.path(atom_dir, name))$size,
    sha256 = sha256(file.path(atom_dir, name))
  ))
  atom_terminal <- list(
    stage = contract$stage, phase = contract$phase, status = atom_status,
    task_id = contract$task_id, family = contract$family, tau = tau,
    p = p, n = nrow(X), formal_converged = isTRUE(fit$converged), finite_core = finite,
    numerically_eligible = isTRUE(fit$converged) && finite,
    initialization_only = TRUE, prior_center_from_initializer = FALSE,
    package_version = package$version, package_repository = package$repository,
    public_api = "exalStaticLDVB", artifacts = artifacts, test_opened = FALSE
  )
  write_json(atom_terminal, file.path(atom_dir, "terminal.json"))
  atom_rows[[position]] <- data.frame(
    family = contract$family, tau = tau, converged = isTRUE(fit$converged),
    finite_core = finite, numerically_eligible = isTRUE(fit$converged) && finite,
    iterations = parameters$iterations, train_seconds = elapsed,
    stringsAsFactors = FALSE
  )
}
atom_summary <- do.call(rbind, atom_rows)
utils::write.csv(atom_summary, file.path(temporary, "atom_summary.csv"), row.names = FALSE)
task_terminal <- list(
  stage = contract$stage, phase = contract$phase, status = family_status,
  task_id = contract$task_id, task_contract_sha256 = contract$task_contract_sha256,
  family = contract$family, fit_axis = axis_name, fit_axis_value = axis_value,
  atoms_complete = nrow(atom_summary), atoms_eligible = sum(atom_summary$numerically_eligible),
  all_atoms_eligible = all(atom_summary$numerically_eligible),
  package_version = package$version, package_repository = package$repository,
  public_api = "exalStaticLDVB", selection_split = contract$selection_split,
  initialization_only = TRUE, prior_center_from_initializer = FALSE,
  test_opened = FALSE, registry_mutated = FALSE, article_mutated = FALSE,
  mcmc_fitted = FALSE, joint_model_fitted = FALSE
)
write_json(task_terminal, file.path(temporary, "terminal.json"))
if (dir.exists(output_dir)) unlink(output_dir, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, output_dir)) stop("failed to install R114/R116 fit output", call. = FALSE)
cat(jsonlite::toJSON(task_terminal, auto_unbox = TRUE, pretty = TRUE), "\n")
