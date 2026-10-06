#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
arg <- function(flag, default = NULL) {
  position <- match(flag, args)
  if (is.na(position) || position == length(args)) return(default)
  args[[position + 1L]]
}

config_path <- arg("--config")
if (is.null(config_path)) stop("--config is required", call. = FALSE)
config_path <- normalizePath(config_path, mustWork = TRUE)
config <- jsonlite::read_json(config_path, simplifyVector = FALSE)

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
  if (length(value) != n || any(!is.finite(value))) stop("invalid float64 artifact", call. = FALSE)
  value
}
write_f64 <- function(path, value, row_major = FALSE) {
  handle <- file(path, open = "wb")
  on.exit(close(handle), add = TRUE)
  payload <- if (row_major) as.double(t(value)) else as.double(value)
  writeBin(payload, handle, size = 8L, endian = "little")
}

required_false <- c(
  "test_access_authorized", "joint_model_authorized", "mcmc_authorized",
  "registry_mutation_authorized", "article_mutation_authorized"
)
if (!identical(config$stage, "R117") ||
    !identical(config$training_split, "train_only_corrected_teacher_forced") ||
    any(vapply(required_false, function(name) !identical(config[[name]], FALSE), logical(1L)))) {
  stop("R117 quantile firewall violation", call. = FALSE)
}
manifest <- jsonlite::read_json(config$cran_manifest, simplifyVector = FALSE)
if (!identical(manifest$status, "installed_exact_cran_exdqlm_1.1.1") ||
    !identical(manifest$installed_package$version, "1.1.1") ||
    !identical(manifest$installed_package$repository, "CRAN") ||
    !identical(sha256(config$cran_manifest), config$cran_manifest_sha256)) {
  stop("R117 requires the hash-sealed exact CRAN exdqlm 1.1.1 runtime", call. = FALSE)
}
source(normalizePath(config$cran_adapter, mustWork = TRUE), local = .GlobalEnv)
package <- r67_assert_cran_package(config$cran_library, expected_version = "1.1.1")

design_meta <- jsonlite::read_json(file.path(config$design_dir, "design.json"), simplifyVector = FALSE)
design_terminal <- jsonlite::read_json(file.path(config$design_dir, "terminal.json"), simplifyVector = FALSE)
if (!identical(design_terminal$status, "completed_r117_quantile_design") ||
    !identical(design_terminal$test_opened, FALSE)) {
  stop("invalid R117 design terminal", call. = FALSE)
}
for (name in names(design_terminal$files)) {
  if (!identical(sha256(file.path(config$design_dir, name)), design_terminal$files[[name]]$sha256)) {
    stop("R117 design hash mismatch: ", name, call. = FALSE)
  }
}
n <- as.integer(design_meta$n)
p <- as.integer(design_meta$p)
X <- matrix(read_f64(file.path(config$design_dir, "X.bin"), n * p), nrow = n, byrow = TRUE)
y <- read_f64(file.path(config$design_dir, "y.bin"), n)

read_initializer <- function(path, source_label) {
  terminal <- jsonlite::read_json(file.path(path, "terminal.json"), simplifyVector = FALSE)
  beta <- read_f64(file.path(path, "beta_mean.bin"), p)
  covariance <- matrix(read_f64(file.path(path, "beta_cov.bin"), p * p), nrow = p, byrow = TRUE)
  sigma <- if (identical(source_label, "normal_rhs")) {
    sqrt(as.numeric(terminal$omega_rate) / max(as.numeric(terminal$omega_shape) - 1, 1e-8))
  } else {
    parameters <- jsonlite::read_json(file.path(path, "parameter_summary.json"), simplifyVector = FALSE)
    as.numeric(parameters$sigma)
  }
  if (!all(is.finite(beta)) || !all(is.finite(covariance)) || !is.finite(sigma) || sigma <= 0) {
    stop("R117 initializer is not finite", call. = FALSE)
  }
  list(beta = beta, covariance = covariance, sigma = sigma, source = source_label)
}

parent <- read_initializer(config$parent_dir, config$parent_label)
init <- list(beta = parent$beta, sigma = parent$sigma)
if (identical(config$family, "exal")) {
  init$gamma <- 0
  init$beta_cov_diag <- diag(parent$covariance)
}
rhs <- list(
  tau0 = as.numeric(config$tau0), shrink_intercept = FALSE,
  freeze_tau_iters = 0L, freeze_tau_warmup_iters = 0L
)
qcfg <- list(
  max_iter = as.integer(config$max_iter), tol = as.numeric(config$tol),
  n_samp_xi = as.integer(config$n_samp_xi), n_samp = as.integer(config$n_samp),
  prior_sigma = list(a = 1, b = 1), prior_gamma = list(mu0 = 0, s20 = 10),
  verbose = FALSE
)
profile <- list(
  factorization = "structured", structured_grid_size = 151L,
  structured_span_sd = 6, freeze_warmup_iters = 10L,
  force_after_warmup = TRUE, postwarmup_damping = 0.2,
  postwarmup_damping_iters = 30L, min_postwarmup_updates = 35L
)
set.seed(as.integer(config$seed))
started <- proc.time()[["elapsed"]]
fit <- r67_fit_quantile(
  config$cran_library, X, y, as.numeric(config$tau), config$family,
  rhs, qcfg, profile = profile, init = init, seed = as.integer(config$seed),
  expected_version = "1.1.1"
)
elapsed <- proc.time()[["elapsed"]] - started
beta <- as.numeric(fit$qbeta$m)
covariance <- as.matrix(fit$qbeta$V)
sigma <- r67_safe_sigma(fit)
gamma <- as.numeric(fit$qsiggam$gamma_mean %||% fit$qgam$E_gamma %||% 0)[1L]
if (identical(config$family, "al")) gamma <- 0
finite <- length(beta) == p && all(is.finite(beta)) &&
  all(dim(covariance) == c(p, p)) && all(is.finite(covariance)) &&
  all(diag(covariance) > 0) && is.finite(sigma) && sigma > 0 && is.finite(gamma)
trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())

output <- normalizePath(config$output_dir, mustWork = FALSE)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(pattern = paste0(basename(output), ".tmp."), tmpdir = dirname(output))
dir.create(temporary)
on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
write_f64(file.path(temporary, "beta_mean.bin"), beta)
write_f64(file.path(temporary, "beta_cov.bin"), covariance, row_major = TRUE)
if (nrow(trace)) utils::write.csv(trace, file.path(temporary, "vb_trace.csv"), row.names = FALSE)
parameters <- list(
  family = config$family, tau = as.numeric(config$tau), tau0 = as.numeric(config$tau0),
  sigma = sigma, gamma = gamma, train_seconds = as.numeric(elapsed),
  iterations = as.integer(fit$iter %||% nrow(trace)), converged = isTRUE(fit$converged),
  init_source = parent$source, initialization_only = TRUE,
  prior_center_from_initializer = FALSE, package_version = package$version,
  package_repository = package$repository
)
write_json(parameters, file.path(temporary, "parameter_summary.json"))
artifact_names <- list.files(temporary, full.names = FALSE)
artifacts <- lapply(artifact_names, function(name) list(
  path = name, bytes = file.info(file.path(temporary, name))$size,
  sha256 = sha256(file.path(temporary, name))
))
terminal <- list(
  status = "completed_r117_quantile_atom", stage = "R117",
  atom_id = config$atom_id, family = config$family, tau = as.numeric(config$tau),
  tau0 = as.numeric(config$tau0), n = n, p = p,
  finite_core = finite, formal_converged = isTRUE(fit$converged),
  numerically_eligible = finite && isTRUE(fit$converged),
  train_seconds = as.numeric(elapsed), init_source = parent$source,
  initialization_only = TRUE, prior_center_from_initializer = FALSE,
  posterior_target_sha256 = config$posterior_target_sha256,
  package = package[c("library", "package_path", "version", "repository", "packaged")],
  artifacts = artifacts, test_opened = FALSE, test_access_authorized = FALSE,
  joint_model_fitted = FALSE, mcmc_fitted = FALSE,
  registry_mutated = FALSE, article_mutated = FALSE
)
write_json(terminal, file.path(temporary, "terminal.json"))
if (dir.exists(output)) unlink(output, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, output)) stop("R117 atom atomic install failed", call. = FALSE)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n")
