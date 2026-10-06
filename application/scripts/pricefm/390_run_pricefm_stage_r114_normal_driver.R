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
read_matrix <- function(path) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    return(as.matrix(data.table::fread(path, header = FALSE, showProgress = FALSE)))
  }
  as.matrix(utils::read.csv(path, header = FALSE, check.names = FALSE))
}
canonical_utc <- function(value) {
  parsed <- as.POSIXct(value, tz = "UTC")
  if (any(is.na(parsed))) stop("calendar timestamps must parse as UTC", call. = FALSE)
  format(parsed, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}
validate_origin_surface <- function(rows, index, requested_times, label) {
  selected <- rows[index, , drop = FALSE]
  selected_time <- canonical_utc(selected$origin_market_time)
  if (!setequal(unique(selected_time), requested_times)) {
    stop(label, " calendar coverage changed", call. = FALSE)
  }
  key <- paste(selected_time, selected$horizon, sep = "::")
  if (anyDuplicated(key)) stop(label, " has duplicate origin/horizon rows", call. = FALSE)
  for (origin_time in requested_times) {
    horizons <- sort(as.integer(selected$horizon[selected_time == origin_time]))
    if (!identical(horizons, seq_len(96L))) {
      stop(label, " does not contain horizons 1--96 exactly once", call. = FALSE)
    }
  }
  invisible(TRUE)
}

contract_path <- normalizePath(arg("--contract"), mustWork = TRUE)
contract <- jsonlite::read_json(contract_path, simplifyVector = TRUE)
calendar_alignment_mode <- contract$calendar_alignment_mode %||% "region_local_nested_temporal"
if (!identical(contract$stage, "R114") ||
    !identical(contract$phase, "training_only_normal_driver") ||
    !(contract$region %in% c("BG", "GR", "RO")) ||
    !identical(contract$selection_split, "BG_fold1_training_nested_temporal_only") ||
    !identical(contract$readout, "block24") || !identical(contract$prior_type, "rhs_ns") ||
    abs(as.numeric(contract$tau0) - 2.5e-5) > 1e-15 || as.integer(contract$n_paths) != 500L ||
    !(calendar_alignment_mode %in% c(
      "region_local_nested_temporal", "reference_region_shared_origin_times"
    )) ||
    isTRUE(contract$test_access_authorized) || isTRUE(contract$registry_mutation_authorized) ||
    isTRUE(contract$article_mutation_authorized)) {
  stop("R114 Normal-driver firewall violation", call. = FALSE)
}
output_dir <- normalizePath(contract$output_dir, mustWork = FALSE)
terminal_path <- file.path(output_dir, "terminal.json")
if (file.exists(terminal_path)) {
  terminal <- jsonlite::read_json(terminal_path, simplifyVector = TRUE)
  if (identical(terminal$status, "completed_r114_normal_driver") &&
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
y <- as.numeric(read_matrix(file.path(adapter, "y_train.csv"))[, 1L])
rows <- utils::read.csv(file.path(adapter, "rows_train.csv"), stringsAsFactors = FALSE)
if (nrow(X) != length(y) || length(y) != nrow(rows) || any(!is.finite(X)) || any(!is.finite(y))) {
  stop("R114 Normal-driver input is invalid", call. = FALSE)
}
inner <- as.integer(contract$inner_fold)
calendar_manifest <- NULL
if (identical(calendar_alignment_mode, "reference_region_shared_origin_times")) {
  if (!identical(contract$reference_region, "BG") ||
      !identical(contract$calendar_key, "origin_market_time_utc") ||
      is.null(contract$shared_calendar_path) || is.null(contract$shared_calendar_sha256)) {
    stop("R114 shared-calendar contract is incomplete", call. = FALSE)
  }
  calendar_path <- normalizePath(contract$shared_calendar_path, mustWork = TRUE)
  if (!identical(sha256(calendar_path), contract$shared_calendar_sha256)) {
    stop("R114 shared calendar hash changed", call. = FALSE)
  }
  calendar <- utils::read.csv(calendar_path, stringsAsFactors = FALSE)
  required_calendar <- c("split", "origin_market_time", "calendar_order")
  if (!all(required_calendar %in% names(calendar)) ||
      !setequal(unique(calendar$split), c("train", "validation"))) {
    stop("R114 shared calendar schema is invalid", call. = FALSE)
  }
  calendar$origin_market_time <- canonical_utc(calendar$origin_market_time)
  if (anyDuplicated(paste(calendar$split, calendar$origin_market_time)) ||
      anyDuplicated(paste(calendar$split, calendar$calendar_order))) {
    stop("R114 shared calendar contains duplicate keys", call. = FALSE)
  }
  calendar <- calendar[order(calendar$split, calendar$calendar_order), , drop = FALSE]
  train_times <- calendar$origin_market_time[calendar$split == "train"]
  validation_times <- calendar$origin_market_time[calendar$split == "validation"]
  if (!length(train_times) || !length(validation_times)) {
    stop("R114 shared calendar has an empty split", call. = FALSE)
  }
  row_origin_time <- canonical_utc(rows$origin_market_time)
  response_time <- as.POSIXct(rows$response_market_time, tz = "UTC")
  if (any(is.na(response_time))) stop("R114 response timestamps do not parse", call. = FALSE)
  validation_start <- min(as.POSIXct(validation_times, tz = "UTC"))
  train_index <- which(row_origin_time %in% train_times & response_time < validation_start)
  validation_index <- which(row_origin_time %in% validation_times)
  validate_origin_surface(rows, train_index, train_times, "R114 training split")
  validate_origin_surface(rows, validation_index, validation_times, "R114 validation split")
  train_index <- train_index[order(
    match(row_origin_time[train_index], train_times), as.integer(rows$horizon[train_index])
  )]
  validation_index <- validation_index[order(
    match(row_origin_time[validation_index], validation_times),
    as.integer(rows$horizon[validation_index])
  )]
  selected <- list(train_index = train_index, validation_index = validation_index)
  summary <- data.frame(
    inner_fold = inner, n_train_origins = length(train_times),
    n_validation_origins = length(validation_times), n_train_rows = length(train_index),
    n_validation_rows = length(validation_index),
    train_response_end = format(max(response_time[train_index]), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    validation_origin_start = validation_times[[1L]],
    validation_origin_end = validation_times[[length(validation_times)]],
    embargo_passed = max(response_time[train_index]) < validation_start,
    stringsAsFactors = FALSE
  )
  calendar_manifest <- data.frame(
    split = c("train", "validation"), reference_region = "BG",
    target_region = contract$region,
    requested_origins = c(length(train_times), length(validation_times)),
    matched_origins = c(
      length(unique(row_origin_time[train_index])),
      length(unique(row_origin_time[validation_index]))
    ),
    first_origin_market_time = c(train_times[[1L]], validation_times[[1L]]),
    last_origin_market_time = c(
      train_times[[length(train_times)]], validation_times[[length(validation_times)]]
    ),
    horizons_per_origin = 96L, exact_match = TRUE, stringsAsFactors = FALSE
  )
} else {
  nested <- pricefm_build_nested_temporal_folds(
    rows, n_folds = 3L, initial_train_fraction = 0.55,
    validation_fraction = 0.15, min_train_origins = 120L,
    min_validation_origins = 30L
  )
  selected <- nested$folds[[inner]]
  summary <- nested$summary[nested$summary$inner_fold == inner, , drop = FALSE]
}
if (!isTRUE(summary$embargo_passed[[1L]])) stop("R114 Normal-driver embargo failed", call. = FALSE)
X_fit <- X[selected$train_index, , drop = FALSE]
y_fit <- y[selected$train_index]
X_eval <- X[selected$validation_index, , drop = FALSE]
y_eval <- y[selected$validation_index]
rows_eval <- rows[selected$validation_index, , drop = FALSE]

if (flag("--preflight-only")) {
  cat(jsonlite::toJSON(list(
    stage = "R114", status = "preflight_passed_not_fitted",
    task_id = contract$task_id, region = contract$region,
    inner_fold = inner, n_fit = nrow(X_fit), p = ncol(X_fit),
    n_eval = nrow(X_eval), n_paths = as.integer(contract$n_paths),
    test_opened = FALSE
  ), auto_unbox = TRUE, pretty = TRUE), "\n")
  quit(status = 0L)
}

fit_one <- function(X_block, y_block) {
  fit <- app_pricefm_fit_rhs_stats(
    app_pricefm_normal_stats_from_design(X_block, y_block),
    tau0 = as.numeric(contract$tau0), beta_prior_factory = beta_prior_factory,
    max_iter = as.integer(contract$max_iter), min_iter = as.integer(contract$min_iter),
    tol = as.numeric(contract$tol)
  )
  if (!isTRUE(fit$converged)) stop("R114 Normal driver failed convergence", call. = FALSE)
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
if (any(!is.finite(paths))) stop("R114 generated nonfinite Normal paths", call. = FALSE)

parent <- dirname(output_dir)
dir.create(parent, recursive = TRUE, showWarnings = FALSE)
temporary <- tempfile(pattern = paste0(basename(output_dir), ".tmp."), tmpdir = parent)
dir.create(temporary)
on.exit(if (dir.exists(temporary)) unlink(temporary, recursive = TRUE, force = TRUE), add = TRUE)
handle <- file(file.path(temporary, "prediction_paths_scaled.bin"), open = "wb")
writeBin(as.double(t(paths)), handle, size = 8L, endian = "little")
close(handle)
utils::write.csv(rows_eval, file.path(temporary, "evaluation_rows.csv"), row.names = FALSE)
utils::write.csv(summary, file.path(temporary, "embargo_summary.csv"), row.names = FALSE)
if (!is.null(calendar_manifest)) {
  utils::write.csv(
    calendar_manifest, file.path(temporary, "calendar_alignment_manifest.csv"),
    row.names = FALSE
  )
}
utils::write.csv(data.frame(y_scaled = y_eval), file.path(temporary, "truth_scaled.csv"), row.names = FALSE)
utils::write.csv(do.call(rbind, lapply(names(fits), function(name) data.frame(
  block = name, converged = isTRUE(fits[[name]]$converged),
  iterations = nrow(fits[[name]]$trace), omega_shape = fits[[name]]$omega2$a,
  omega_rate = fits[[name]]$omega2$b
))), file.path(temporary, "fit_summary.csv"), row.names = FALSE)
write_json(list(
  n_rows = nrow(paths), n_paths = ncol(paths), dtype = "float64_little_endian",
  storage_order = "row_major", region = contract$region, inner_fold = inner
), file.path(temporary, "prediction_paths_manifest.json"))
artifacts <- lapply(list.files(temporary, full.names = FALSE), function(name) list(
  path = name, bytes = file.info(file.path(temporary, name))$size,
  sha256 = sha256(file.path(temporary, name))
))
terminal <- list(
  stage = "R114", status = "completed_r114_normal_driver",
  task_id = contract$task_id, task_contract_sha256 = contract$task_contract_sha256,
  region = contract$region, inner_fold = inner, n_rows = nrow(paths),
  n_origins = length(unique(rows_eval$origin_id)), n_paths = n_paths,
  readout = "block24", prior_type = "rhs_ns", tau0 = as.numeric(contract$tau0),
  calendar_alignment_mode = calendar_alignment_mode,
  reference_region = contract$reference_region %||% contract$region,
  calendar_key = contract$calendar_key %||% "region_local_origin_id",
  shared_calendar_sha256 = contract$shared_calendar_sha256 %||% NULL,
  all_blocks_converged = TRUE, selection_split = contract$selection_split,
  artifacts = artifacts, test_opened = FALSE, registry_mutated = FALSE,
  article_mutated = FALSE
)
write_json(terminal, file.path(temporary, "terminal.json"))
if (dir.exists(output_dir)) unlink(output_dir, recursive = TRUE, force = TRUE)
if (!file.rename(temporary, output_dir)) stop("failed to install R114 Normal-driver output", call. = FALSE)
cat(jsonlite::toJSON(terminal, auto_unbox = TRUE, pretty = TRUE), "\n")
