#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
value_after <- function(flag) {
  where <- match(flag, args)
  if (is.na(where) || where == length(args)) stop(sprintf("missing %s", flag), call. = FALSE)
  args[[where + 1L]]
}

contract_path <- normalizePath(value_after("--contract"), mustWork = TRUE)
contract <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
required <- c("fit_id", "stats_dir", "output_dir", "prior_type", "package_path", "helper_path")
missing <- setdiff(required, names(contract))
if (length(missing)) stop(sprintf("contract missing: %s", paste(missing, collapse = ", ")), call. = FALSE)
if (!identical(contract$selection_split, "train_validation_only") || isTRUE(contract$test_access_authorized)) {
  stop("R102 fit contract attempted to open a forbidden split", call. = FALSE)
}

stats_dir <- normalizePath(contract$stats_dir, mustWork = TRUE)
output_dir <- normalizePath(dirname(contract$output_dir), mustWork = TRUE)
output_dir <- file.path(output_dir, basename(contract$output_dir))
if (dir.exists(output_dir) && file.exists(file.path(output_dir, "terminal.json"))) {
  existing <- jsonlite::read_json(file.path(output_dir, "terminal.json"), simplifyVector = TRUE)
  if (identical(existing$status, "completed_recursive_normal_fit")) {
    cat(jsonlite::toJSON(existing, auto_unbox = TRUE, pretty = TRUE), "\n")
    quit(status = 0L)
  }
}

stats_meta <- jsonlite::read_json(file.path(stats_dir, "statistics.json"), simplifyVector = FALSE)
stats_terminal <- jsonlite::read_json(file.path(stats_dir, "terminal.json"), simplifyVector = TRUE)
if (!identical(stats_terminal$status, "completed_causal_sufficient_statistics") || isTRUE(stats_meta$test_opened)) {
  stop("R102 sufficient-statistic terminal is invalid", call. = FALSE)
}
p <- as.integer(stats_meta$p)
read_f64 <- function(path, n) {
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  values <- readBin(con, what = "double", n = n, size = 8L, endian = "little")
  if (length(values) != n || any(!is.finite(values))) stop(sprintf("invalid binary array: %s", path), call. = FALSE)
  values
}
XtX <- matrix(read_f64(file.path(stats_dir, "XtX.bin"), p * p), nrow = p, byrow = TRUE)
Xty <- read_f64(file.path(stats_dir, "Xty.bin"), p)
stats <- list(n = as.integer(stats_meta$n), p = p, XtX = XtX, Xty = Xty, yty = as.numeric(stats_meta$yty))

source(normalizePath(contract$helper_path, mustWork = TRUE), local = .GlobalEnv)
prior_type <- as.character(contract$prior_type)
if (identical(prior_type, "scaled_ridge")) {
  fit <- app_pricefm_fit_scaled_ridge_stats(stats)
} else if (identical(prior_type, "rhs_ns")) {
  package_path <- normalizePath(contract$package_path, mustWork = TRUE)
  pkgload::load_all(package_path, quiet = TRUE, export_all = TRUE)
  beta_prior_factory <- get("beta_prior", envir = asNamespace("exdqlm"), inherits = FALSE)
  fit <- app_pricefm_fit_rhs_stats(
    stats,
    tau0 = as.numeric(contract$tau0),
    beta_prior_factory = beta_prior_factory,
    max_iter = as.integer(contract$max_iter),
    min_iter = as.integer(contract$min_iter),
    tol = as.numeric(contract$tol)
  )
} else {
  stop(sprintf("unsupported prior_type: %s", prior_type), call. = FALSE)
}

if (any(!is.finite(fit$beta$mean)) || any(!is.finite(fit$beta$cov)) ||
    !is.finite(fit$omega2$a) || !is.finite(fit$omega2$b)) {
  stop("R102 fit contains non-finite posterior quantities", call. = FALSE)
}
if (identical(prior_type, "rhs_ns") && !isTRUE(fit$converged)) {
  stop("R102 RHS fit did not meet its frozen convergence criterion", call. = FALSE)
}

parent <- dirname(output_dir)
dir.create(parent, recursive = TRUE, showWarnings = FALSE)
tmp <- tempfile(pattern = paste0(basename(output_dir), ".tmp."), tmpdir = parent)
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
on.exit(if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
saveRDS(fit, file.path(tmp, "fit.rds"), compress = "xz")
write_f64 <- function(path, value, matrix_row_major = FALSE) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  payload <- if (matrix_row_major) as.double(t(value)) else as.double(value)
  writeBin(payload, con, size = 8L, endian = "little")
}
write_f64(file.path(tmp, "beta_mean.bin"), fit$beta$mean)
write_f64(file.path(tmp, "beta_cov.bin"), fit$beta$cov, matrix_row_major = TRUE)
if (!is.null(fit$beta$precision_inv)) {
  write_f64(file.path(tmp, "beta_precision_inv.bin"), fit$beta$precision_inv, matrix_row_major = TRUE)
}
utils::write.csv(fit$trace, file.path(tmp, "convergence_trace.csv"), row.names = FALSE)
summary <- list(
  stage = "R102",
  fit_id = contract$fit_id,
  prior_type = prior_type,
  tau0 = if (identical(prior_type, "rhs_ns")) as.numeric(contract$tau0) else NULL,
  n = stats$n,
  p = stats$p,
  converged = isTRUE(fit$converged),
  iterations = nrow(fit$trace),
  omega_shape = fit$omega2$a,
  omega_rate = fit$omega2$b,
  posterior_target_sha256 = contract$posterior_target_sha256,
  initialization_contract = fit$initialization_contract %||% "exact_closed_form_no_warm_start",
  test_opened = FALSE,
  registry_mutated = FALSE,
  article_mutated = FALSE
)
jsonlite::write_json(summary, file.path(tmp, "fit_summary.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
artifact_names <- list.files(tmp, all.files = FALSE, full.names = FALSE)
artifact_rows <- lapply(artifact_names, function(name) list(
  path = name,
  bytes = file.info(file.path(tmp, name))$size,
  sha256 = digest::digest(file.path(tmp, name), algo = "sha256", file = TRUE)
))
terminal <- c(summary, list(status = "completed_recursive_normal_fit", artifacts = artifact_rows))
jsonlite::write_json(terminal, file.path(tmp, "terminal.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
if (dir.exists(output_dir)) unlink(output_dir, recursive = TRUE, force = TRUE)
if (!file.rename(tmp, output_dir)) stop("failed to atomically install R102 fit directory", call. = FALSE)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n")
