app_glofas_closeout_marker_counts <- function(status_dir) {
  files <- list.files(status_dir, full.names = FALSE)
  suffix_count <- function(suffix) sum(grepl(paste0("\\.", suffix, "$"), files))
  data.frame(
    completed = suffix_count("completed"),
    running = suffix_count("running"),
    failed = suffix_count("failed"),
    pending = suffix_count("pending"),
    total = length(files),
    stringsAsFactors = FALSE
  )
}

app_glofas_closeout_verify_manifest <- function(root, manifest_path) {
  root <- normalizePath(root, mustWork = TRUE)
  manifest <- read.csv(manifest_path, stringsAsFactors = FALSE)
  required <- c("relative_path", "sha256")
  if (!nrow(manifest) || !all(required %in% names(manifest))) {
    stop("Artifact manifest is empty or malformed: ", manifest_path, call. = FALSE)
  }
  unsafe <- vapply(manifest$relative_path, function(path) {
    parts <- strsplit(gsub("\\\\", "/", path), "/", fixed = TRUE)[[1L]]
    grepl("^/", path) || ".." %in% parts
  }, logical(1L))
  if (any(unsafe)) stop("Artifact manifest contains an unsafe relative path.", call. = FALSE)
  paths <- file.path(root, manifest$relative_path)
  if (any(!file.exists(paths))) {
    stop("Artifact manifest has missing targets: ", paste(manifest$relative_path[!file.exists(paths)], collapse = ", "), call. = FALSE)
  }
  observed <- vapply(paths, app_sha256_file, character(1L))
  if (any(tolower(observed) != tolower(manifest$sha256))) {
    stop("Artifact manifest hash verification failed: ", manifest_path, call. = FALSE)
  }
  manifest
}

app_glofas_closeout_check_loss <- function(y, q, tau) {
  (tau - as.numeric(y < q)) * (y - q)
}

app_glofas_closeout_grid_crps_by_date <- function(rows) {
  required <- c("target_date", "quantile_level", "check_loss")
  if (!all(required %in% names(rows))) stop("Quantile rows are missing score columns.", call. = FALSE)
  rows$target_date <- as.Date(rows$target_date)
  vapply(split(rows, rows$target_date), function(block) {
    block <- block[order(as.numeric(block$quantile_level)), , drop = FALSE]
    tau <- as.numeric(block$quantile_level)
    if (length(tau) < 2L || anyDuplicated(tau) || any(diff(tau) <= 0)) {
      stop("Each date must have a strictly increasing quantile grid.", call. = FALSE)
    }
    2 * sum(diff(tau) * (head(block$check_loss, -1L) + tail(block$check_loss, -1L)) / 2)
  }, numeric(1L))
}

app_glofas_closeout_summarize_quantiles <- function(rows, family, role, numerical_status) {
  required <- c("target_date", "horizon", "quantile_level", "y_reference", "qhat")
  if (!all(required %in% names(rows))) stop("Quantile rows are missing required fields.", call. = FALSE)
  rows$target_date <- as.Date(rows$target_date)
  rows$quantile_level <- as.numeric(rows$quantile_level)
  if (anyNA(rows[, required]) || any(!is.finite(rows$y_reference)) || any(!is.finite(rows$qhat))) {
    stop("Quantile rows contain missing or non-finite scoring values.", call. = FALSE)
  }
  key <- paste(rows$target_date, format(rows$quantile_level, digits = 15), sep = "::")
  if (anyDuplicated(key)) stop("Quantile rows contain duplicate date/level pairs.", call. = FALSE)
  rows$check_loss <- app_glofas_closeout_check_loss(rows$y_reference, rows$qhat, rows$quantile_level)
  tau <- sort(unique(rows$quantile_level))
  expected <- c(0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95)
  if (!isTRUE(all.equal(tau, expected, tolerance = 1e-12))) stop("Unexpected seven-quantile grid.", call. = FALSE)
  truth_counts <- vapply(split(rows$y_reference, rows$target_date), function(x) length(unique(x)), integer(1L))
  if (any(truth_counts != 1L)) stop("Reference truth is inconsistent within a target date.", call. = FALSE)
  wide <- reshape(
    rows[c("target_date", "y_reference", "quantile_level", "qhat")],
    idvar = c("target_date", "y_reference"), timevar = "quantile_level", direction = "wide"
  )
  wide <- wide[order(wide$target_date), , drop = FALSE]
  qmat <- do.call(cbind, lapply(expected, function(q) wide[[paste0("qhat.", q)]]))
  if (anyNA(qmat)) stop("Quantile grid is incomplete for at least one date.", call. = FALSE)
  p50 <- rows[abs(rows$quantile_level - 0.50) < 1e-12, , drop = FALSE]
  data.frame(
    family = family,
    role = role,
    numerical_status = numerical_status,
    n_scored_horizons = length(unique(rows$target_date)),
    mean_check_loss = mean(rows$check_loss),
    crps_grid_log1p = mean(app_glofas_closeout_grid_crps_by_date(rows)),
    coverage90 = mean(wide$y_reference >= wide$qhat.0.05 & wide$y_reference <= wide$qhat.0.95),
    median_mae_log1p = mean(abs(p50$qhat - p50$y_reference)),
    median_rmse_log1p = sqrt(mean((p50$qhat - p50$y_reference)^2)),
    crossing_pairs = sum(qmat[, -ncol(qmat), drop = FALSE] > qmat[, -1L, drop = FALSE]),
    stringsAsFactors = FALSE
  )
}

app_glofas_closeout_calibration <- function(rows, family) {
  rows$quantile_level <- as.numeric(rows$quantile_level)
  blocks <- split(rows, rows$quantile_level)
  do.call(rbind, lapply(blocks, function(block) {
    tau <- unique(block$quantile_level)
    data.frame(
      family = family,
      quantile_level = tau,
      empirical_coverage = mean(block$y_reference <= block$qhat),
      coverage_error = mean(block$y_reference <= block$qhat) - tau,
      mean_qhat = mean(block$qhat),
      mean_check_loss = mean(app_glofas_closeout_check_loss(block$y_reference, block$qhat, tau)),
      stringsAsFactors = FALSE
    )
  }))
}

app_glofas_closeout_validate_joint_fit <- function(fit, outer_tolerance = 1e-3, rhs_tolerance = 1e-3) {
  required <- c("converged", "converged_outer", "converged_inner", "converged_rhs", "trace", "stopping_reason")
  if (!all(required %in% names(fit))) stop("Terminal joint fit is missing convergence fields.", call. = FALSE)
  trace <- fit$trace
  terminal <- tail(trace, 1L)
  required_trace <- c(
    "outer_iteration", "parameter_change", "all_inner_converged", "rhs_convergence_gate_passed",
    "full_state_pass", "terminal_consecutive_passes"
  )
  if (!all(required_trace %in% names(trace))) stop("Terminal joint trace is incomplete.", call. = FALSE)
  passed <- isTRUE(fit$converged) && isTRUE(fit$converged_outer) && isTRUE(fit$converged_inner) &&
    isTRUE(fit$converged_rhs) && isTRUE(terminal$all_inner_converged) &&
    isTRUE(terminal$rhs_convergence_gate_passed) && isTRUE(terminal$full_state_pass) &&
    terminal$parameter_change < outer_tolerance && terminal$terminal_consecutive_passes >= 3L
  max_rhs <- if ("max_rhs_global_relative_change" %in% names(terminal)) terminal$max_rhs_global_relative_change else NA_real_
  if (is.finite(max_rhs)) passed <- passed && max_rhs < rhs_tolerance
  if (!passed) stop("Terminal joint fit did not satisfy the strict full-state contract.", call. = FALSE)
  data.frame(
    converged = TRUE,
    outer_iteration = as.integer(terminal$outer_iteration),
    parameter_change = as.numeric(terminal$parameter_change),
    max_rhs_global_relative_change = as.numeric(max_rhs),
    terminal_consecutive_passes = as.integer(terminal$terminal_consecutive_passes),
    stopping_reason = as.character(fit$stopping_reason),
    stringsAsFactors = FALSE
  )
}

app_glofas_closeout_write_manifest <- function(root, relative_paths, manifest_path) {
  root <- normalizePath(root, mustWork = TRUE)
  relative_paths <- sort(unique(as.character(relative_paths)))
  paths <- file.path(root, relative_paths)
  if (!length(paths) || any(!file.exists(paths))) stop("Cannot manifest missing closeout outputs.", call. = FALSE)
  manifest <- data.frame(
    relative_path = relative_paths,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  write.csv(manifest, manifest_path, row.names = FALSE)
  manifest
}
