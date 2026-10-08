# Read-only diagnostics for GloFAS joint-quantile RHS convergence.

app_glofas_rootcause_max_relative_change <- function(current, previous, floor = 1) {
  current <- as.numeric(current)
  previous <- as.numeric(previous)
  if (!length(current) || length(current) != length(previous) ||
      any(!is.finite(current)) || any(!is.finite(previous))) return(Inf)
  max(abs(current - previous) / pmax(as.numeric(floor), abs(previous)))
}

app_glofas_rootcause_max_log_change <- function(current, previous) {
  current <- as.numeric(current)
  previous <- as.numeric(previous)
  if (!length(current) || length(current) != length(previous) ||
      any(!is.finite(current)) || any(!is.finite(previous)) ||
      any(current <= 0) || any(previous <= 0)) return(Inf)
  max(abs(log(current) - log(previous)))
}

app_glofas_rootcause_named_numeric <- function(x, prefix = "state") {
  if (is.null(x)) return(numeric())
  if (is.numeric(x) || is.integer(x)) {
    out <- as.numeric(x)
    labels <- names(x)
    if (is.null(labels) || any(!nzchar(labels))) labels <- seq_along(out)
    names(out) <- paste0(prefix, "[", labels, "]")
    return(out)
  }
  if (!is.list(x)) return(numeric())
  labels <- names(x)
  if (is.null(labels) || any(!nzchar(labels))) labels <- seq_along(x)
  unlist(Map(
    function(value, label) {
      app_glofas_rootcause_named_numeric(value, paste0(prefix, ".", label))
    },
    x,
    labels
  ), use.names = TRUE)
}

app_glofas_rootcause_state_change <- function(current, previous) {
  current_raw <- app_glofas_quantile_numeric_state(current)
  previous_raw <- app_glofas_quantile_numeric_state(previous)
  raw_change <- app_glofas_rootcause_max_relative_change(current_raw, previous_raw)
  current_components <- app_glofas_quantile_rhs_inferential_components(current)
  previous_components <- app_glofas_quantile_rhs_inferential_components(previous)
  if (!identical(lengths(current_components), lengths(previous_components))) {
    stop("RHS inferential coordinates changed during a fixed-point replay.", call. = FALSE)
  }
  current_semantic <- unlist(current_components, use.names = FALSE)
  previous_semantic <- unlist(previous_components, use.names = FALSE)
  list(
    raw_relative_change = raw_change,
    inferential_relative_change = app_glofas_rootcause_max_relative_change(
      current_semantic, previous_semantic
    ),
    auxiliary_log_change = if (length(current_components$auxiliary)) {
      app_glofas_rootcause_max_log_change(
        current_components$auxiliary, previous_components$auxiliary
      )
    } else NA_real_,
    precision_log_change = if (length(current_components$prior_precision)) {
      app_glofas_rootcause_max_log_change(
        current_components$prior_precision, previous_components$prior_precision
      )
    } else NA_real_
  )
}

app_glofas_rootcause_fixed_point_replay <- function(
  state,
  update,
  iterations = 100L,
  tolerance = 1.0e-4,
  label = "rhs"
) {
  iterations <- as.integer(iterations)
  if (iterations < 1L || !is.function(update)) {
    stop("Fixed-point replay requires a positive iteration count and update function.", call. = FALSE)
  }
  current <- state
  trace <- vector("list", iterations)
  for (iteration in seq_len(iterations)) {
    previous <- current
    current <- update(current, iteration)
    change <- app_glofas_rootcause_state_change(current, previous)
    trace[[iteration]] <- data.frame(
      label = as.character(label),
      iteration = iteration,
      raw_relative_change = change$raw_relative_change,
      inferential_relative_change = change$inferential_relative_change,
      auxiliary_log_change = change$auxiliary_log_change,
      precision_log_change = change$precision_log_change,
      semantic_pass = is.finite(change$inferential_relative_change) &&
        change$inferential_relative_change <= tolerance,
      stringsAsFactors = FALSE
    )
  }
  trace <- do.call(rbind, trace)
  list(state = current, trace = trace)
}

app_glofas_rootcause_part1_replay <- function(
  fit,
  iterations = 100L,
  inner_steps = 1L,
  tolerance = 1.0e-4,
  label = "part1_joint_al"
) {
  K <- length(fit$tau)
  p <- as.integer(length(fit$beta_mean) / K)
  if (K < 1L || p < 1L || length(fit$beta_mean) != K * p ||
      length(fit$beta_cov_blocks) != K) {
    stop("Part 1/2 fit does not contain complete RHS replay moments.", call. = FALSE)
  }
  beta <- matrix(as.numeric(fit$beta_mean), nrow = p, ncol = K)
  covariance_diagonal <- lapply(fit$beta_cov_blocks, function(x) pmax(diag(as.matrix(x)), 0))
  update <- function(state, iteration) {
    app_glofas_part1_quantile_update_rhs_blockmf(
      state, beta, covariance_diagonal, K, p, n_inner = as.integer(inner_steps)
    )
  }
  app_glofas_rootcause_fixed_point_replay(
    fit$rhs_state, update, iterations, tolerance, label
  )
}

app_glofas_rootcause_partitioned_replay <- function(
  state,
  coefficient_mean,
  coefficient_var_diag,
  iteration_offset = 0L,
  iterations = 100L,
  inner_steps = 1L,
  tolerance = 1.0e-4,
  label = "partitioned_rhs"
) {
  coefficient_mean <- as.matrix(coefficient_mean)
  coefficient_var_diag <- as.matrix(coefficient_var_diag)
  if (!identical(dim(coefficient_mean), dim(coefficient_var_diag))) {
    stop("Partitioned RHS replay moments are dimension-incompatible.", call. = FALSE)
  }
  update <- function(current, iteration) {
    for (inner in seq_len(as.integer(inner_steps))) {
      current <- app_glofas_part3_rhs_update(
        current,
        coefficient_mean,
        coefficient_var_diag,
        iter = as.integer(iteration_offset) + iteration,
        update_global = if (inner == as.integer(inner_steps)) TRUE else FALSE
      )
    }
    current
  }
  app_glofas_rootcause_fixed_point_replay(
    state, update, iterations, tolerance, label
  )
}

app_glofas_rootcause_artifact_manifest <- function(paths, labels = basename(paths)) {
  paths <- normalizePath(paths, mustWork = TRUE)
  if (length(labels) != length(paths) || anyDuplicated(labels)) {
    stop("Artifact labels must be unique and aligned with paths.", call. = FALSE)
  }
  data.frame(
    label = as.character(labels),
    path = paths,
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
}

app_glofas_rootcause_terminal_trace_row <- function(fit, component) {
  trace <- as.data.frame(fit$trace)
  if (!nrow(trace)) stop(sprintf("%s has no convergence trace.", component), call. = FALSE)
  row <- trace[nrow(trace), , drop = FALSE]
  value <- function(name, default = NA) if (name %in% names(row)) row[[name]][[1L]] else default
  data.frame(
    component = component,
    completed_iterations = as.integer(max(
      as.numeric(fit$iterations_completed %||% 0),
      as.numeric(value("global_iter", 0)),
      as.numeric(value("outer_iteration", 0)),
      na.rm = TRUE
    )),
    converged = isTRUE(fit$converged),
    stopping_reason = as.character(fit$stopping_reason %||% fit$stop_reason %||% "not_recorded"),
    coefficient_change = as.numeric(max(
      value("max_beta_relative_change", 0),
      value("max_reference_relative_change", 0),
      value("max_discrepancy_relative_change", 0),
      value("parameter_change", 0),
      na.rm = TRUE
    )),
    path_change = as.numeric(max(
      value("max_path_change", 0), value("max_path_relative_change", 0), na.rm = TRUE
    )),
    latent_change = as.numeric(value("max_latent_change", NA_real_)),
    rhs_change_recorded = as.numeric(max(
      value("max_rhs_change", 0), value("max_rhs_global_relative_change", 0), na.rm = TRUE
    )),
    full_state_pass = isTRUE(value("full_state_pass", FALSE)),
    stringsAsFactors = FALSE
  )
}
