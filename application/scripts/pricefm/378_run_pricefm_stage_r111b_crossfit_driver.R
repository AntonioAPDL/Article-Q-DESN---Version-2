#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
arg <- function(flag) {
  where <- match(flag, args)
  if (is.na(where) || where == length(args)) stop("missing ", flag, call. = FALSE)
  args[[where + 1L]]
}

contract_path <- normalizePath(arg("--contract"), mustWork = TRUE)
contract <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
if (!identical(contract$stage, "R111B") ||
    !identical(contract$phase, "crossfit_normal_driver") ||
    !identical(contract$region, "BG") ||
    !identical(contract$selection_split, "outer_fold_training_inner_only") ||
    isTRUE(contract$test_access_authorized)) {
  stop("R111B crossfit-driver firewall violation", call. = FALSE)
}
if (!identical(contract$readout, "block24") ||
    !identical(contract$prior_type, "rhs_ns") ||
    abs(as.numeric(contract$tau0) - 2.5e-5) > 1e-15 ||
    as.integer(contract$n_paths) != 500L) {
  stop("R111B frozen normal-driver policy changed", call. = FALSE)
}

sha256 <- function(path) {
  value <- system2("sha256sum", normalizePath(path, mustWork = TRUE), stdout = TRUE)
  strsplit(value[[1L]], "[[:space:]]+")[[1L]][[1L]]
}
write_json <- function(value, path) {
  jsonlite::write_json(value, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
}
read_matrix <- function(path) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    return(as.matrix(data.table::fread(path, header = FALSE, showProgress = FALSE)))
  }
  as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
}
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])

output_dir <- normalizePath(contract$output_dir, mustWork = FALSE)
terminal_path <- file.path(output_dir, "terminal.json")
if (file.exists(terminal_path)) {
  terminal <- jsonlite::read_json(terminal_path, simplifyVector = TRUE)
  if (identical(terminal$status, "completed_r111b_crossfit_driver") &&
      identical(terminal$task_contract_sha256, contract$task_contract_sha256)) {
    cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE), "\n")
    quit(status = 0L)
  }
}

source(normalizePath(contract$helper_path, mustWork = TRUE), local = .GlobalEnv)
source(normalizePath(contract$horizon_helper_path, mustWork = TRUE), local = .GlobalEnv)
pkgload::load_all(normalizePath(contract$package_path, mustWork = TRUE), quiet = TRUE, export_all = TRUE)
beta_prior_factory <- get("beta_prior", envir = asNamespace("exdqlm"), inherits = FALSE)

adapter <- normalizePath(contract$adapter_dir, mustWork = TRUE)
X <- read_matrix(file.path(adapter, "X_train.csv"))
y <- read_vector(file.path(adapter, "y_train.csv"))
rows <- utils::read.csv(file.path(adapter, "rows_train.csv"), stringsAsFactors = FALSE)
if (nrow(X) != length(y) || length(y) != nrow(rows) || any(!is.finite(X)) || any(!is.finite(y))) {
  stop("R111B driver input is invalid", call. = FALSE)
}
nested <- pricefm_build_nested_temporal_folds(
  rows, n_folds = 3L, initial_train_fraction = 0.55,
  validation_fraction = 0.15, min_train_origins = 120L,
  min_validation_origins = 30L
)
inner <- as.integer(contract$inner_fold)
selected <- nested$folds[[inner]]
summary <- nested$summary[nested$summary$inner_fold == inner, , drop = FALSE]
if (!isTRUE(summary$embargo_passed[[1L]])) stop("R111B inner embargo failed", call. = FALSE)
X_fit <- X[selected$train_index, , drop = FALSE]
y_fit <- y[selected$train_index]
X_eval <- X[selected$validation_index, , drop = FALSE]
y_eval <- y[selected$validation_index]
rows_eval <- rows[selected$validation_index, , drop = FALSE]

fit_one <- function(X_block, y_block) {
  fit <- app_pricefm_fit_rhs_stats(
    app_pricefm_normal_stats_from_design(X_block, y_block),
    tau0 = as.numeric(contract$tau0), beta_prior_factory = beta_prior_factory,
    max_iter = as.integer(contract$max_iter), min_iter = as.integer(contract$min_iter),
    tol = as.numeric(contract$tol)
  )
  if (!isTRUE(fit$converged)) stop("R111B normal driver failed convergence", call. = FALSE)
  fit
}
fits <- pricefm_fit_horizon_block_models(
  X_fit, y_fit, rows$horizon[selected$train_index], 24L,
  function(X_block, y_block, block_name, idx) fit_one(X_block, y_block)
)

n_paths <- as.integer(contract$n_paths)
paths <- matrix(NA_real_, nrow(X_eval), n_paths)
labels <- pricefm_horizon_block_labels(rows_eval$horizon, 24L)
for (block_index in seq_along(unique(labels))) {
  block <- unique(labels)[[block_index]]
  idx <- which(labels == block)
  fit <- fits[[block]]
  set.seed(as.integer(contract$seed) + 1009L * block_index)
  omega2 <- 1 / stats::rgamma(n_paths, shape = fit$omega2$a, rate = fit$omega2$b)
  z <- matrix(stats::rnorm(n_paths * ncol(X_eval)), nrow = n_paths)
  root <- chol(0.5 * (fit$beta$cov + t(fit$beta$cov)))
  beta <- sweep(z %*% root, 2L, fit$beta$mean, `+`)
  location <- X_eval[idx, , drop = FALSE] %*% t(beta)
  innovation <- matrix(stats::rnorm(length(idx) * n_paths), nrow = length(idx))
  paths[idx, ] <- location + sweep(innovation, 2L, sqrt(omega2), `*`)
}
if (any(!is.finite(paths))) stop("R111B generated nonfinite driver paths", call. = FALSE)

parent <- dirname(output_dir)
dir.create(parent, recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(pattern = paste0(basename(output_dir), ".tmp."), tmpdir = parent)
dir.create(temporary)
on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
con <- file(file.path(temporary, "prediction_paths_scaled.bin"), open = "wb")
writeBin(as.double(t(paths)), con, size = 8L, endian = "little")
close(con)
utils::write.csv(rows_eval, file.path(temporary, "evaluation_rows.csv"), row.names = FALSE)
utils::write.csv(summary, file.path(temporary, "embargo_summary.csv"), row.names = FALSE)
utils::write.csv(data.frame(y_scaled = y_eval), file.path(temporary, "truth_scaled.csv"), row.names = FALSE)
utils::write.csv(do.call(rbind, lapply(names(fits), function(name) data.frame(
  block = name, converged = isTRUE(fits[[name]]$converged),
  iterations = nrow(fits[[name]]$trace), omega_shape = fits[[name]]$omega2$a,
  omega_rate = fits[[name]]$omega2$b
))), file.path(temporary, "fit_summary.csv"), row.names = FALSE)
write_json(list(
  n_rows = nrow(paths), n_paths = ncol(paths), dtype = "float64_little_endian",
  storage_order = "row_major", region = "BG", outer_fold = as.integer(contract$outer_fold),
  inner_fold = inner
), file.path(temporary, "prediction_paths_manifest.json"))

names <- list.files(temporary, full.names = FALSE)
artifacts <- lapply(names, function(name) list(
  path = name, bytes = file.info(file.path(temporary, name))$size,
  sha256 = sha256(file.path(temporary, name))
))
terminal <- list(
  stage = "R111B", status = "completed_r111b_crossfit_driver",
  task_id = contract$task_id, task_contract_sha256 = contract$task_contract_sha256,
  region = "BG", outer_fold = as.integer(contract$outer_fold), inner_fold = inner,
  n_rows = nrow(paths), n_origins = length(unique(rows_eval$origin_id)), n_paths = n_paths,
  readout = "block24", prior_type = "rhs_ns", tau0 = as.numeric(contract$tau0),
  all_blocks_converged = TRUE, selection_split = contract$selection_split,
  artifacts = artifacts, test_opened = FALSE, registry_mutated = FALSE,
  article_mutated = FALSE
)
write_json(terminal, file.path(temporary, "terminal.json"))
if (dir.exists(output_dir)) unlink(output_dir, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, output_dir)) stop("failed to install R111B driver output", call. = FALSE)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE), "\n")
