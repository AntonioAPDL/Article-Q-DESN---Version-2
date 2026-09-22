#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x)) y else x
value_after <- function(flag) {
  where <- match(flag, args)
  if (is.na(where) || where == length(args)) stop("missing ", flag, call. = FALSE)
  args[[where + 1L]]
}

contract_path <- normalizePath(value_after("--contract"), mustWork = TRUE)
contract <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
required <- c(
  "task_id", "phase", "region", "outer_fold", "adapter_dir", "output_dir",
  "readout", "prior_type", "selection_split", "package_path", "helper_path",
  "horizon_helper_path", "seed"
)
missing <- setdiff(required, names(contract))
if (length(missing)) stop("R111A contract missing: ", paste(missing, collapse = ", "), call. = FALSE)
if (!identical(contract$stage, "R111A")) stop("R111A stage identity mismatch", call. = FALSE)
if (isTRUE(contract$test_access_authorized) || grepl("test", contract$selection_split, fixed = TRUE)) {
  stop("R111A forbids test access", call. = FALSE)
}
if (!contract$phase %in% c("ridge_selection", "rhs_selection", "outer_validation")) {
  stop("unsupported R111A phase", call. = FALSE)
}
if (!contract$region %in% c("FI", "LV")) stop("R111A region is out of scope", call. = FALSE)
if (!contract$readout %in% c("shared", "block24")) stop("unsupported readout", call. = FALSE)
if (!contract$prior_type %in% c("scaled_ridge", "rhs_ns")) stop("unsupported prior", call. = FALSE)

adapter_dir <- normalizePath(contract$adapter_dir, mustWork = TRUE)
output_dir <- normalizePath(dirname(contract$output_dir), mustWork = TRUE)
output_dir <- file.path(output_dir, basename(contract$output_dir))
terminal_path <- file.path(output_dir, "terminal.json")
if (file.exists(terminal_path)) {
  terminal <- jsonlite::read_json(terminal_path, simplifyVector = TRUE)
  if (identical(terminal$status, "completed_r111a_direct_case") &&
      identical(terminal$task_contract_sha256, contract$task_contract_sha256)) {
    cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE), "\n")
    quit(status = 0L)
  }
}

read_matrix <- function(path) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    return(as.matrix(data.table::fread(path, header = FALSE, showProgress = FALSE)))
  }
  as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
}
read_vector <- function(path) as.numeric(read_matrix(path)[, 1L])
read_rows <- function(split) utils::read.csv(
  file.path(adapter_dir, paste0("rows_", split, ".csv")), stringsAsFactors = FALSE
)

source(normalizePath(contract$helper_path, mustWork = TRUE), local = .GlobalEnv)
source(normalizePath(contract$horizon_helper_path, mustWork = TRUE), local = .GlobalEnv)
if (identical(contract$prior_type, "rhs_ns")) {
  pkgload::load_all(normalizePath(contract$package_path, mustWork = TRUE), quiet = TRUE, export_all = TRUE)
  beta_prior_factory <- get("beta_prior", envir = asNamespace("exdqlm"), inherits = FALSE)
} else {
  beta_prior_factory <- NULL
}

X_train_all <- read_matrix(file.path(adapter_dir, "X_train.csv"))
y_train_all <- read_vector(file.path(adapter_dir, "y_train.csv"))
rows_train_all <- read_rows("train")
if (nrow(X_train_all) != length(y_train_all) || length(y_train_all) != nrow(rows_train_all)) {
  stop("train adapter dimensions disagree", call. = FALSE)
}
if (any(!is.finite(X_train_all)) || any(!is.finite(y_train_all))) {
  stop("R111A train design must be finite", call. = FALSE)
}

if (identical(contract$phase, "outer_validation")) {
  X_fit <- X_train_all
  y_fit <- y_train_all
  rows_fit <- rows_train_all
  X_eval <- read_matrix(file.path(adapter_dir, "X_val.csv"))
  y_eval <- read_vector(file.path(adapter_dir, "y_val.csv"))
  rows_eval <- read_rows("val")
  if (nrow(X_eval) != length(y_eval) || length(y_eval) != nrow(rows_eval)) {
    stop("validation adapter dimensions disagree", call. = FALSE)
  }
  embargo_summary <- data.frame(
    inner_fold = NA_integer_, n_train_origins = length(unique(rows_fit$origin_id)),
    n_validation_origins = length(unique(rows_eval$origin_id)),
    n_train_rows = nrow(rows_fit), n_validation_rows = nrow(rows_eval),
    embargo_passed = TRUE
  )
} else {
  nested <- pricefm_build_nested_temporal_folds(
    rows_train_all,
    n_folds = as.integer(contract$n_inner_folds %||% 3L),
    initial_train_fraction = as.numeric(contract$initial_train_fraction %||% 0.55),
    validation_fraction = as.numeric(contract$validation_fraction %||% 0.15),
    min_train_origins = as.integer(contract$min_train_origins %||% 120L),
    min_validation_origins = as.integer(contract$min_validation_origins %||% 30L)
  )
  inner_fold <- as.integer(contract$inner_fold)
  selected <- nested$folds[[inner_fold]]
  X_fit <- X_train_all[selected$train_index, , drop = FALSE]
  y_fit <- y_train_all[selected$train_index]
  rows_fit <- rows_train_all[selected$train_index, , drop = FALSE]
  X_eval <- X_train_all[selected$validation_index, , drop = FALSE]
  y_eval <- y_train_all[selected$validation_index]
  rows_eval <- rows_train_all[selected$validation_index, , drop = FALSE]
  embargo_summary <- nested$summary[nested$summary$inner_fold == inner_fold, , drop = FALSE]
  if (!isTRUE(embargo_summary$embargo_passed[[1L]])) stop("inner embargo failed", call. = FALSE)
}

fit_one <- function(X, y) {
  stats <- app_pricefm_normal_stats_from_design(X, y)
  if (identical(contract$prior_type, "scaled_ridge")) {
    app_pricefm_fit_scaled_ridge_stats(stats)
  } else {
    app_pricefm_fit_rhs_stats(
      stats,
      tau0 = as.numeric(contract$tau0),
      beta_prior_factory = beta_prior_factory,
      max_iter = as.integer(contract$max_iter %||% 300L),
      min_iter = as.integer(contract$min_iter %||% 50L),
      tol = as.numeric(contract$tol %||% 1e-5)
    )
  }
}

if (identical(contract$readout, "shared")) {
  fits <- list(shared = fit_one(X_fit, y_fit))
} else {
  fits <- pricefm_fit_horizon_block_models(
    X_fit, y_fit, rows_fit$horizon, 24L,
    function(X, y, block_name, idx) fit_one(X, y)
  )
}
if (identical(contract$prior_type, "rhs_ns") && any(!vapply(fits, function(x) isTRUE(x$converged), logical(1)))) {
  stop("R111A RHS fit did not satisfy the frozen convergence criterion", call. = FALSE)
}

quantiles <- as.numeric(contract$quantiles %||% c(0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90))
analytic_quantiles <- function(fit, X) {
  location <- as.numeric(X %*% fit$beta$mean)
  if (identical(contract$prior_type, "scaled_ridge")) {
    leverage <- rowSums((X %*% fit$beta$precision_inv) * X)
    scale <- sqrt(pmax((fit$omega2$b / fit$omega2$a) * (1 + leverage), .Machine$double.eps))
    offsets <- stats::qt(quantiles, df = 2 * fit$omega2$a)
  } else {
    variance <- rowSums((X %*% fit$beta$cov) * X) + fit$omega2$mean
    scale <- sqrt(pmax(variance, .Machine$double.eps))
    offsets <- stats::qnorm(quantiles)
  }
  sweep(outer(scale, offsets), 1L, location, `+`)
}

predict_quantiles <- function() {
  if (identical(contract$readout, "shared")) return(analytic_quantiles(fits$shared, X_eval))
  labels <- pricefm_horizon_block_labels(rows_eval$horizon, 24L)
  out <- matrix(NA_real_, nrow(X_eval), length(quantiles))
  for (block in unique(labels)) {
    idx <- which(labels == block)
    out[idx, ] <- analytic_quantiles(fits[[block]], X_eval[idx, , drop = FALSE])
  }
  out
}

q_eval <- predict_quantiles()
if (any(!is.finite(q_eval))) stop("nonfinite R111A quantile prediction", call. = FALSE)
pinball <- sapply(seq_along(quantiles), function(j) {
  error <- y_eval - q_eval[, j]
  pmax(quantiles[[j]] * error, (quantiles[[j]] - 1) * error)
})
metric <- data.frame(
  task_id = contract$task_id,
  phase = contract$phase,
  region = contract$region,
  outer_fold = as.integer(contract$outer_fold),
  inner_fold = as.integer(contract$inner_fold %||% NA_integer_),
  readout = contract$readout,
  prior_type = contract$prior_type,
  tau0 = if (identical(contract$prior_type, "rhs_ns")) as.numeric(contract$tau0) else NA_real_,
  n_fit_rows = nrow(X_fit),
  n_eval_rows = nrow(X_eval),
  AQL_scaled = mean(pinball),
  coverage_10_90 = mean(y_eval >= q_eval[, 1L] & y_eval <= q_eval[, length(quantiles)]),
  mean_width_10_90_scaled = mean(q_eval[, length(quantiles)] - q_eval[, 1L]),
  median_MAE_scaled = mean(abs(y_eval - q_eval[, which.min(abs(quantiles - 0.5))])),
  converged = all(vapply(fits, function(x) isTRUE(x$converged), logical(1))),
  max_iterations = max(vapply(fits, function(x) nrow(x$trace), integer(1))),
  stringsAsFactors = FALSE
)
horizon_metric <- do.call(rbind, lapply(sort(unique(rows_eval$horizon)), function(horizon) {
  idx <- which(rows_eval$horizon == horizon)
  data.frame(
    task_id = contract$task_id, region = contract$region,
    outer_fold = as.integer(contract$outer_fold), horizon = as.integer(horizon),
    n_rows = length(idx), AQL_scaled = mean(pinball[idx, , drop = FALSE]),
    coverage_10_90 = mean(y_eval[idx] >= q_eval[idx, 1L] & y_eval[idx] <= q_eval[idx, length(quantiles)]),
    stringsAsFactors = FALSE
  )
}))

sample_one <- function(fit, X, seed, n_paths) {
  set.seed(as.integer(seed))
  omega2 <- 1 / stats::rgamma(n_paths, shape = fit$omega2$a, rate = fit$omega2$b)
  z <- matrix(stats::rnorm(n_paths * ncol(X)), nrow = n_paths)
  if (identical(contract$prior_type, "scaled_ridge")) {
    root <- chol(fit$beta$precision_inv)
    beta <- sweep(z %*% root, 1L, sqrt(omega2), `*`)
  } else {
    root <- chol(0.5 * (fit$beta$cov + t(fit$beta$cov)))
    beta <- z %*% root
  }
  beta <- sweep(beta, 2L, fit$beta$mean, `+`)
  location <- X %*% t(beta)
  innovation <- matrix(stats::rnorm(nrow(X) * n_paths), nrow = nrow(X))
  location + sweep(innovation, 2L, sqrt(omega2), `*`)
}

paths <- NULL
if (identical(contract$phase, "outer_validation")) {
  n_paths <- as.integer(contract$n_paths %||% 500L)
  if (n_paths != 500L) stop("R111A final prediction requires exactly 500 paths", call. = FALSE)
  if (identical(contract$readout, "shared")) {
    paths <- sample_one(fits$shared, X_eval, as.integer(contract$seed), n_paths)
  } else {
    labels <- pricefm_horizon_block_labels(rows_eval$horizon, 24L)
    paths <- matrix(NA_real_, nrow(X_eval), n_paths)
    for (block_index in seq_along(unique(labels))) {
      block <- unique(labels)[[block_index]]
      idx <- which(labels == block)
      paths[idx, ] <- sample_one(
        fits[[block]], X_eval[idx, , drop = FALSE],
        as.integer(contract$seed) + 1009L * block_index, n_paths
      )
    }
  }
  if (any(!is.finite(paths))) stop("nonfinite R111A predictive path", call. = FALSE)
}

parent <- dirname(output_dir)
dir.create(parent, recursive = TRUE, showWarnings = FALSE)
tmp <- tempfile(pattern = paste0(basename(output_dir), ".tmp."), tmpdir = parent)
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
on.exit(if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
utils::write.csv(metric, file.path(tmp, "metric_summary.csv"), row.names = FALSE)
utils::write.csv(horizon_metric, file.path(tmp, "horizon_metrics.csv"), row.names = FALSE)
utils::write.csv(embargo_summary, file.path(tmp, "embargo_summary.csv"), row.names = FALSE)
utils::write.csv(rows_eval, file.path(tmp, "evaluation_rows.csv"), row.names = FALSE)
utils::write.csv(
  data.frame(y_scaled = y_eval, setNames(as.data.frame(q_eval), paste0("q", quantiles))),
  file.path(tmp, "prediction_quantiles_scaled.csv"), row.names = FALSE
)
utils::write.csv(
  do.call(rbind, lapply(names(fits), function(name) data.frame(
    block = name, converged = isTRUE(fits[[name]]$converged),
    iterations = nrow(fits[[name]]$trace), omega_shape = fits[[name]]$omega2$a,
    omega_rate = fits[[name]]$omega2$b, stringsAsFactors = FALSE
  ))),
  file.path(tmp, "fit_summary.csv"), row.names = FALSE
)
if (!is.null(paths)) {
  con <- file(file.path(tmp, "prediction_paths_scaled.bin"), open = "wb")
  writeBin(as.double(paths), con, size = 8L, endian = "little")
  close(con)
  jsonlite::write_json(list(
    n_rows = nrow(paths), n_paths = ncol(paths), storage_order = "R_column_major",
    dtype = "float64_little_endian"
  ), file.path(tmp, "prediction_paths_manifest.json"), auto_unbox = TRUE, pretty = TRUE)
}
artifacts <- list.files(tmp, full.names = FALSE)
records <- lapply(artifacts, function(name) list(
  path = name, bytes = file.info(file.path(tmp, name))$size,
  sha256 = digest::digest(file.path(tmp, name), algo = "sha256", file = TRUE)
))
terminal <- list(
  status = "completed_r111a_direct_case", stage = "R111A", task_id = contract$task_id,
  phase = contract$phase, region = contract$region, outer_fold = as.integer(contract$outer_fold),
  readout = contract$readout, prior_type = contract$prior_type,
  tau0 = if (identical(contract$prior_type, "rhs_ns")) as.numeric(contract$tau0) else NULL,
  paths = if (is.null(paths)) 0L else ncol(paths),
  task_contract_sha256 = contract$task_contract_sha256,
  test_opened = FALSE, registry_mutated = FALSE, article_mutated = FALSE,
  artifacts = records
)
jsonlite::write_json(terminal, file.path(tmp, "terminal.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
if (dir.exists(output_dir)) unlink(output_dir, recursive = TRUE, force = TRUE)
if (!file.rename(tmp, output_dir)) stop("failed to install R111A task output", call. = FALSE)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE, null = "null"), "\n")
