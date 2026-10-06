#!/usr/bin/env Rscript

# Exact-CRAN independent AL/exAL VB atom for the frozen R120 design.
args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
arg <- function(flag) {
  at <- match(flag, args)
  if (is.na(at) || at == length(args)) stop(sprintf("%s is required", flag), call. = FALSE)
  args[[at + 1L]]
}
config_path <- normalizePath(arg("--config"), mustWork = TRUE)
config <- jsonlite::read_json(config_path, simplifyVector = FALSE)

sha256 <- function(path) {
  value <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(value[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
read_f64 <- function(path, n) {
  handle <- file(path, open = "rb"); on.exit(close(handle), add = TRUE)
  value <- readBin(handle, what = "double", n = n, size = 8L, endian = "little")
  if (length(value) != n || any(!is.finite(value))) stop("invalid float64 artifact", call. = FALSE)
  value
}
write_f64 <- function(path, value, row_major = FALSE) {
  handle <- file(path, open = "wb"); on.exit(close(handle), add = TRUE)
  writeBin(if (row_major) as.double(t(value)) else as.double(value), handle, size = 8L, endian = "little")
}
write_json <- function(value, path) {
  temporary <- paste0(path, ".tmp.", Sys.getpid())
  jsonlite::write_json(value, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 17)
  if (!file.rename(temporary, path)) stop("atomic JSON rename failed", call. = FALSE)
}

required_false <- c("test_access_authorized", "registry_mutation_authorized",
                    "article_mutation_authorized", "joint_model_authorized", "mcmc_authorized")
if (!identical(config$stage, "R120_production") ||
    !config$family %in% c("al", "exal") ||
    !config$readout %in% c("pure_all_layers", "extended_all_layers") ||
    !identical(config$training_split, "train_only_explicit_lag_teacher_forced") ||
    any(vapply(required_false, function(name) !identical(config[[name]], FALSE), logical(1L)))) {
  stop("R120 production firewall violation", call. = FALSE)
}
for (pair in list(c(config$cran_manifest, config$cran_manifest_sha256),
                  c(config$cran_adapter, config$cran_adapter_sha256),
                  c(file.path(config$design_dir, "terminal.json"), config$design_terminal_sha256),
                  c(file.path(config$parent_dir, "terminal.json"), config$parent_terminal_sha256))) {
  if (!identical(sha256(pair[[1L]]), pair[[2L]])) stop("R120 source hash mismatch", call. = FALSE)
}
manifest <- jsonlite::read_json(config$cran_manifest, simplifyVector = FALSE)
if (!identical(manifest$status, "installed_exact_cran_exdqlm_1.1.1") ||
    !identical(manifest$installed_package$version, "1.1.1") ||
    !identical(manifest$installed_package$repository, "CRAN")) {
  stop("R120 requires exact CRAN exdqlm 1.1.1", call. = FALSE)
}
source(normalizePath(config$cran_adapter, mustWork = TRUE), local = .GlobalEnv)
package <- r67_assert_cran_package(config$cran_library, expected_version = "1.1.1")

design <- jsonlite::read_json(file.path(config$design_dir, "design.json"), simplifyVector = FALSE)
terminal <- jsonlite::read_json(file.path(config$design_dir, "terminal.json"), simplifyVector = FALSE)
if (!identical(terminal$status, "completed_r120_quantile_design") || isTRUE(terminal$test_opened)) {
  stop("invalid R120 design terminal", call. = FALSE)
}
n <- as.integer(design$n); p <- as.integer(design$p)
features <- unlist(design$feature_names, use.names = FALSE)
if (length(features) != p || !identical(features[[1L]], "intercept") ||
    !all(vapply(seq_len(as.integer(design$depth)), function(layer) {
      any(startsWith(features, paste0("layer", layer, "::")))
    }, logical(1L)))) stop("R120 all-layer identity failed", call. = FALSE)
if (identical(config$readout, "pure_all_layers") && any(startsWith(features, "input::"))) {
  stop("R120 pure design contains direct inputs", call. = FALSE)
}
if (identical(config$readout, "extended_all_layers") && !any(startsWith(features, "input::"))) {
  stop("R120 extended design lacks direct inputs", call. = FALSE)
}
X <- matrix(read_f64(file.path(config$design_dir, "X.bin"), n * p), nrow = n, byrow = TRUE)
y <- read_f64(file.path(config$design_dir, "y.bin"), n)
parent_terminal <- jsonlite::read_json(file.path(config$parent_dir, "terminal.json"), simplifyVector = FALSE)
beta0 <- read_f64(file.path(config$parent_dir, "beta_mean.bin"), p)
if (identical(config$parent_type, "normal_rhs")) {
  sigma0 <- sqrt(as.numeric(parent_terminal$omega_rate) / max(as.numeric(parent_terminal$omega_shape) - 1, 1e-8))
} else {
  params <- jsonlite::read_json(file.path(config$parent_dir, "parameter_summary.json"), simplifyVector = FALSE)
  sigma0 <- as.numeric(params$sigma)
}
if (any(!is.finite(beta0)) || !is.finite(sigma0) || sigma0 <= 0) stop("invalid R120 initializer", call. = FALSE)

init <- list(beta = beta0, sigma = sigma0)
if (identical(config$family, "exal")) init$gamma <- 0
rhs <- list(tau0 = as.numeric(config$tau0), shrink_intercept = FALSE,
            freeze_tau_iters = 0L, freeze_tau_warmup_iters = 0L)
qcfg <- list(max_iter = as.integer(config$max_iter), tol = as.numeric(config$tol),
             n_samp_xi = as.integer(config$n_samp_xi), n_samp = as.integer(config$n_samp),
             prior_sigma = list(a = 1, b = 1), prior_gamma = list(mu0 = 0, s20 = 10), verbose = FALSE)
profile <- list(factorization = "structured", structured_grid_size = 151L,
                structured_span_sd = 6, freeze_warmup_iters = if (identical(config$family, "exal")) 10L else 0L,
                force_after_warmup = TRUE, postwarmup_damping = 0.2,
                postwarmup_damping_iters = 30L, min_postwarmup_updates = 35L)
set.seed(as.integer(config$seed)); started <- proc.time()[["elapsed"]]
fit <- r67_fit_quantile(config$cran_library, X, y, as.numeric(config$tau), config$family,
                        rhs, qcfg, profile = profile, init = init,
                        seed = as.integer(config$seed), expected_version = "1.1.1")
elapsed <- proc.time()[["elapsed"]] - started
beta <- as.numeric(fit$qbeta$m); covariance <- as.matrix(fit$qbeta$V)
sigma <- r67_safe_sigma(fit)
gamma <- if (identical(config$family, "exal")) as.numeric(fit$qsiggam$gamma_mean %||% fit$qgam$E_gamma %||% 0)[1L] else 0
trace <- as.data.frame(fit$diagnostics$vb_trace %||% data.frame())
finite <- length(beta) == p && all(is.finite(beta)) && all(is.finite(covariance)) &&
  all(diag(covariance) > 0) && is.finite(sigma) && sigma > 0 && is.finite(gamma)

output <- normalizePath(config$output_dir, mustWork = FALSE)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(pattern = paste0(basename(output), ".tmp."), tmpdir = dirname(output)); dir.create(temporary)
on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
write_f64(file.path(temporary, "beta_mean.bin"), beta)
write_f64(file.path(temporary, "beta_cov.bin"), covariance, row_major = TRUE)
if (nrow(trace)) utils::write.csv(trace, file.path(temporary, "vb_trace.csv"), row.names = FALSE)
parameters <- list(family = config$family, tau = as.numeric(config$tau), tau0 = as.numeric(config$tau0),
                   sigma = sigma, gamma = gamma, train_seconds = as.numeric(elapsed),
                   iterations = as.integer(fit$iter %||% nrow(trace)), converged = isTRUE(fit$converged),
                   init_source = config$parent_label, initialization_only = TRUE,
                   prior_center_from_initializer = FALSE, package_version = package$version,
                   package_repository = package$repository)
write_json(parameters, file.path(temporary, "parameter_summary.json"))
result <- c(parameters, list(status = "completed_r120_quantile_atom", stage = "R120_production",
  tag = config$tag, atom_id = config$atom_id, readout = config$readout,
  fold = as.integer(config$fold), n = n, p = p, finite_core = finite,
  numerically_eligible = finite && isTRUE(fit$converged),
  posterior_target_sha256 = config$posterior_target_sha256,
  initializer_changes_prior = FALSE, package = package[c("library", "package_path", "version", "repository", "packaged")],
  test_opened = FALSE, test_access_authorized = FALSE, registry_mutated = FALSE,
  article_mutated = FALSE, joint_model_fitted = FALSE, mcmc_fitted = FALSE))
write_json(result, file.path(temporary, "terminal.json"))
if (dir.exists(output)) unlink(output, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, output)) stop("R120 atom atomic install failed", call. = FALSE)
cat(jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 17), "\n")
