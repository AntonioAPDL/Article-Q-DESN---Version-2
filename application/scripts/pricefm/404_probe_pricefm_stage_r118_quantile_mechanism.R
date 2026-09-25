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
  jsonlite::write_json(
    value, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 17
  )
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
  writeBin(payload, handle, size = 8L)
}

required_false <- c(
  "test_access_authorized", "registry_mutation_authorized", "article_mutation_authorized",
  "joint_model_authorized", "mcmc_authorized"
)
if (!identical(config$stage, "R118_probe") ||
    !identical(config$training_split, "fold1_train_only_deterministic_row_probe") ||
    any(vapply(required_false, function(name) !identical(config[[name]], FALSE), logical(1L)))) {
  stop("R118 probe firewall violation", call. = FALSE)
}
for (pair in list(
  c(config$cran_manifest, config$cran_manifest_sha256),
  c(config$cran_tarball, config$cran_tarball_sha256),
  c(config$cran_adapter, config$cran_adapter_sha256),
  c(file.path(config$design_dir, "terminal.json"), config$design_terminal_sha256),
  c(file.path(config$parent_dir, "terminal.json"), config$parent_terminal_sha256)
)) {
  if (!identical(sha256(pair[[1L]]), pair[[2L]])) stop("R118 source hash mismatch", call. = FALSE)
}
manifest <- jsonlite::read_json(config$cran_manifest, simplifyVector = FALSE)
if (!identical(manifest$status, "installed_exact_cran_exdqlm_1.1.1") ||
    !identical(manifest$installed_package$version, "1.1.1") ||
    !identical(manifest$installed_package$repository, "CRAN")) {
  stop("R118 probe requires exact CRAN exdqlm 1.1.1", call. = FALSE)
}
source(normalizePath(config$cran_adapter, mustWork = TRUE), local = .GlobalEnv)
package <- r67_assert_cran_package(config$cran_library, expected_version = "1.1.1")

design <- jsonlite::read_json(file.path(config$design_dir, "design.json"), simplifyVector = FALSE)
n <- as.integer(design$n)
p <- as.integer(design$p)
X_full <- matrix(
  read_f64(file.path(config$design_dir, "X.bin"), n * p), nrow = n, byrow = TRUE
)
y_full <- read_f64(file.path(config$design_dir, "y.bin"), n)
rows <- seq.int(1L, n, by = as.integer(config$subset_stride))
X <- X_full[rows, , drop = FALSE]
y <- y_full[rows]
rm(X_full, y_full)
invisible(gc())

parent_terminal <- jsonlite::read_json(file.path(config$parent_dir, "terminal.json"), simplifyVector = FALSE)
parent_parameters <- jsonlite::read_json(
  file.path(config$parent_dir, "parameter_summary.json"), simplifyVector = FALSE
)
beta0 <- read_f64(file.path(config$parent_dir, "beta_mean.bin"), p)
sigma0 <- as.numeric(parent_parameters$sigma)
if (length(beta0) != p || any(!is.finite(beta0)) || !is.finite(sigma0) || sigma0 <= 0) {
  stop("R118 parent initializer is invalid", call. = FALSE)
}
init <- list(beta = beta0, sigma = sigma0)
if (identical(config$family, "exal")) init$gamma <- 0

rhs <- list(
  tau0 = as.numeric(config$tau0),
  shrink_intercept = FALSE,
  freeze_tau_iters = as.integer(config$rhs_freeze_tau_warmup_iters),
  freeze_tau_warmup_iters = as.integer(config$rhs_freeze_tau_warmup_iters)
)
qcfg <- list(
  max_iter = as.integer(config$max_iter), tol = as.numeric(config$tol),
  n_samp_xi = as.integer(config$n_samp_xi), n_samp = as.integer(config$n_samp),
  prior_sigma = list(a = 1, b = 1), prior_gamma = list(mu0 = 0, s20 = 10),
  verbose = FALSE
)
profile <- list(
  factorization = "structured",
  structured_grid_size = as.integer(config$structured_grid_size),
  structured_span_sd = as.numeric(config$structured_span_sd),
  freeze_warmup_iters = as.integer(config$sigmagam_freeze_warmup_iters),
  force_after_warmup = TRUE,
  postwarmup_damping = 0.2,
  postwarmup_damping_iters = 30L,
  min_postwarmup_updates = as.integer(config$min_postwarmup_updates)
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
trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
release_iter <- max(
  as.integer(config$sigmagam_freeze_warmup_iters),
  as.integer(config$rhs_freeze_tau_warmup_iters)
)
post_release <- if (nrow(trace)) trace[trace$iter > release_iter, , drop = FALSE] else trace
tail_rows <- tail(post_release, min(25L, nrow(post_release)))
beta_scale <- max(1, max(abs(beta)))
relative_state <- if (nrow(tail_rows)) max(abs(tail_rows$delta_state), na.rm = TRUE) / beta_scale else Inf
relative_sigma <- if (nrow(tail_rows)) {
  max(abs(tail_rows$delta_sigma), na.rm = TRUE) / max(1e-12, abs(sigma))
} else Inf
relative_elbo <- if (nrow(tail_rows)) {
  max(abs(tail_rows$delta_elbo), na.rm = TRUE) /
    max(1, max(abs(tail_rows$elbo), na.rm = TRUE))
} else Inf
finite_core <- length(beta) == p && all(is.finite(beta)) &&
  all(dim(covariance) == c(p, p)) && all(is.finite(covariance)) &&
  all(diag(covariance) > 0) && is.finite(sigma) && sigma > 0 && is.finite(gamma)
bounded <- finite_core && sigma < 100 && abs(gamma) < 20
post_release_updates <- nrow(post_release)
external_gate <- bounded && post_release_updates >= as.integer(config$min_postwarmup_updates) &&
  relative_state <= 1e-3 && relative_sigma <= 1e-3 && relative_elbo <= 1e-5
prediction <- as.numeric(X %*% beta)
prediction_finite <- length(prediction) == length(y) && all(is.finite(prediction))
if (!prediction_finite) external_gate <- FALSE

output <- normalizePath(config$output_dir, mustWork = FALSE)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(pattern = paste0(basename(output), ".tmp."), tmpdir = dirname(output))
dir.create(temporary)
on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
write_f64(file.path(temporary, "beta_mean.bin"), beta)
write_f64(file.path(temporary, "beta_cov.bin"), covariance, row_major = TRUE)
if (nrow(trace)) utils::write.csv(trace, file.path(temporary, "vb_trace.csv"), row.names = FALSE)
diagnostics <- list(
  family = config$family, tau = as.numeric(config$tau), tau0 = as.numeric(config$tau0),
  n_probe = nrow(X), p = p, subset_stride = as.integer(config$subset_stride),
  sigma = sigma, gamma = gamma, beta_max_abs = max(abs(beta)),
  relative_state_tail_max = relative_state,
  relative_sigma_tail_max = relative_sigma,
  relative_elbo_tail_max = relative_elbo,
  post_release_updates = post_release_updates,
  finite_core = finite_core, bounded = bounded, prediction_finite = prediction_finite,
  formal_converged = isTRUE(fit$converged), external_gate_passed = external_gate,
  train_seconds = as.numeric(elapsed)
)
write_json(diagnostics, file.path(temporary, "diagnostics.json"))
artifact_names <- list.files(temporary, full.names = FALSE)
artifacts <- lapply(artifact_names, function(name) list(
  path = name, bytes = file.info(file.path(temporary, name))$size,
  sha256 = sha256(file.path(temporary, name))
))
terminal <- c(diagnostics, list(
  status = "completed_r118_mechanism_probe", stage = "R118_probe",
  tag = config$tag, arm_id = config$arm_id,
  sigmagam_freeze_warmup_iters = as.integer(config$sigmagam_freeze_warmup_iters),
  rhs_freeze_tau_warmup_iters = as.integer(config$rhs_freeze_tau_warmup_iters),
  posterior_target_sha256 = config$posterior_target_sha256,
  schedule_sha256 = config$schedule_sha256,
  initializer_source = normalizePath(config$parent_dir, mustWork = TRUE),
  initializer_changes_prior = FALSE,
  structured_postwarmup_damping_effective = FALSE,
  package = package[c("library", "package_path", "version", "repository", "packaged")],
  artifacts = artifacts,
  test_opened = FALSE, registry_mutated = FALSE, article_mutated = FALSE,
  joint_model_fitted = FALSE, mcmc_fitted = FALSE
))
write_json(terminal, file.path(temporary, "terminal.json"))
if (dir.exists(output)) unlink(output, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, output)) stop("R118 probe atomic install failed", call. = FALSE)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 17), "\n")
