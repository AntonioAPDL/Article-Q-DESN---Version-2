# Shared integrity contracts for GloFAS quantile fitting.

app_glofas_quantile_tau_tolerance <- function() 1.0e-12

app_glofas_quantile_initializer_policy <- function(model_family) {
  model_family <- match.arg(
    as.character(model_family),
    c("independent_al", "independent_exal", "joint_al", "joint_exal")
  )
  if (identical(model_family, "independent_al")) "single_source" else "exact_tau"
}

app_glofas_quantile_unwrap_fit <- function(x) {
  if (is.list(x) && is.list(x$fit)) x$fit else x
}

app_glofas_quantile_load_initializer <- function(x) {
  source_path <- NA_character_
  source_sha256 <- NA_character_
  if (is.character(x) && length(x) == 1L) {
    source_path <- normalizePath(x, mustWork = TRUE)
    source_sha256 <- app_sha256_file(source_path)
    x <- readRDS(source_path)
  }
  x <- app_glofas_quantile_unwrap_fit(x)
  if (!is.list(x)) stop("Quantile initializer must be a fit object or RDS path.", call. = FALSE)
  list(fit = x, source_path = source_path, source_sha256 = source_sha256)
}

app_glofas_quantile_source_tau <- function(fit) {
  fit <- app_glofas_quantile_unwrap_fit(fit)
  tau <- suppressWarnings(as.numeric(fit$tau %||% fit$quantile_level %||% NA_real_))
  tau[is.finite(tau)]
}

app_glofas_quantile_initializer_map <- function(
  initializers,
  target_tau,
  tolerance = app_glofas_quantile_tau_tolerance(),
  policy = c("exact_tau", "single_source")
) {
  policy <- match.arg(policy)
  target_tau <- as.numeric(target_tau)
  if (!length(target_tau) || any(!is.finite(target_tau)) || anyDuplicated(round(target_tau / tolerance))) {
    stop("Target quantile grid must be finite and unique.", call. = FALSE)
  }
  if (!is.list(initializers)) initializers <- as.list(initializers)
  if (!length(initializers)) stop("At least one quantile initializer is required.", call. = FALSE)
  loaded <- lapply(initializers, app_glofas_quantile_load_initializer)
  candidates <- do.call(rbind, lapply(seq_along(loaded), function(i) {
    tau <- app_glofas_quantile_source_tau(loaded[[i]]$fit)
    if (!length(tau)) {
      return(data.frame(initializer_index = i, source_column = NA_integer_, source_tau = NA_real_))
    }
    if (anyDuplicated(round(tau / tolerance))) {
      stop(sprintf("Initializer %d has duplicate or ambiguous tau metadata.", i), call. = FALSE)
    }
    data.frame(initializer_index = i, source_column = seq_along(tau), source_tau = tau)
  }))
  if (any(!is.finite(candidates$source_tau))) {
    stop("Every quantile initializer must carry finite tau metadata.", call. = FALSE)
  }
  if (identical(policy, "single_source")) {
    if (length(target_tau) != 1L) {
      stop("Single-source quantile initialization requires exactly one target tau.", call. = FALSE)
    }
    if (nrow(candidates) != 1L) {
      stop(sprintf(
        "Single-source quantile initialization requires exactly one source column; found %d.",
        nrow(candidates)
      ), call. = FALSE)
    }
    mapped <- candidates[1L, , drop = FALSE]
  } else {
    mapped <- lapply(target_tau, function(tau) {
      hit <- which(abs(candidates$source_tau - tau) <= tolerance)
      if (length(hit) != 1L) {
        stop(sprintf("Expected exactly one initializer match for tau %.12g; found %d.", tau, length(hit)), call. = FALSE)
      }
      candidates[hit, , drop = FALSE]
    })
    mapped <- do.call(rbind, mapped)
  }
  mapped$target_tau <- target_tau
  mapped$source_path <- vapply(mapped$initializer_index, function(i) loaded[[i]]$source_path, character(1L))
  mapped$source_sha256 <- vapply(mapped$initializer_index, function(i) loaded[[i]]$source_sha256, character(1L))
  mapped$mapping_status <- ifelse(
    abs(mapped$source_tau - mapped$target_tau) <= tolerance,
    "exact_tau_match",
    "adjacent_tau_warm_start"
  )
  mapped$fit <- I(lapply(seq_len(nrow(mapped)), function(i) loaded[[mapped$initializer_index[[i]]]]$fit))
  mapped
}

app_glofas_quantile_select_column <- function(fit, source_column, coefficient_block_size = NULL) {
  fit <- app_glofas_quantile_unwrap_fit(fit)
  tau <- app_glofas_quantile_source_tau(fit)
  source_column <- as.integer(source_column)
  if (!length(tau) || source_column < 1L || source_column > length(tau)) {
    stop("Quantile initializer column is outside the source tau grid.", call. = FALSE)
  }
  out <- fit
  out$tau <- tau[[source_column]]
  scalar_fields <- c("alpha_mean", "alpha", "sigma_mean", "sigma", "gamma_mean", "gamma")
  for (field in scalar_fields) {
    value <- out[[field]]
    if (!is.null(value) && length(value) == length(tau)) out[[field]] <- value[[source_column]]
  }
  matrix_fields <- c(
    "beta_reference_mean", "beta_discrepancy_mean",
    "beta_reference_var_diag", "beta_discrepancy_var_diag"
  )
  for (field in matrix_fields) {
    value <- out[[field]]
    if (!is.null(value) && is.matrix(value) && ncol(value) == length(tau)) {
      out[[field]] <- value[, source_column, drop = FALSE]
    }
  }
  beta <- out$beta_mean %||% out$beta %||% NULL
  if (!is.null(beta) && length(tau) > 1L) {
    block_size <- as.integer(coefficient_block_size %||% (length(beta) / length(tau)))
    if (!is.finite(block_size) || block_size < 1L || length(beta) != block_size * length(tau)) {
      stop("Cannot identify coefficient blocks in the multi-tau initializer.", call. = FALSE)
    }
    idx <- (source_column - 1L) * block_size + seq_len(block_size)
    if (!is.null(out$beta_mean)) out$beta_mean <- as.numeric(out$beta_mean)[idx]
    if (!is.null(out$beta)) out$beta <- as.numeric(out$beta)[idx]
  }
  out
}

app_glofas_quantile_max_relative_change <- function(current, previous, floor = 1) {
  current <- as.numeric(current)
  previous <- as.numeric(previous)
  if (!length(current) || length(current) != length(previous) || any(!is.finite(current)) || any(!is.finite(previous))) {
    return(Inf)
  }
  max(abs(current - previous) / pmax(as.numeric(floor), abs(previous)))
}

app_glofas_quantile_numeric_state <- function(x) {
  if (is.null(x)) return(numeric())
  if (is.numeric(x) || is.integer(x)) return(as.numeric(x))
  if (!is.list(x)) return(numeric())
  unlist(lapply(x, app_glofas_quantile_numeric_state), use.names = FALSE)
}

app_glofas_quantile_rhs_block_inferential_components <- function(block) {
  if (!is.list(block)) stop("RHS block state must be a list.", call. = FALSE)
  expected_inverse <- function(vb_name, latent_name, raw_name) {
    if (!is.null(block[[vb_name]])) return(as.numeric(block[[vb_name]]))
    if (!is.null(block[[latent_name]])) return(as.numeric(block[[latent_name]]))
    raw <- as.numeric(block[[raw_name]] %||% numeric())
    if (!length(raw)) return(numeric())
    1 / pmax(raw, .Machine$double.eps)
  }

  lambda_inv <- expected_inverse("lambda2_inv_mean", "e_inv_lambda2", "lambda2")
  nu_inv <- expected_inverse("nu_inv_mean", "e_inv_nu", "nu")
  tau_inv <- expected_inverse("tau2_inv_mean", "e_inv_tau2", "tau2")
  xi_inv <- expected_inverse("xi_inv_mean", "e_inv_xi", "xi")
  zeta_inv <- expected_inverse("zeta2_inv_mean", "e_inv_zeta2", "zeta2")
  precision <- as.numeric(block$prior_precision %||% numeric())
  if (!length(precision) && length(lambda_inv) && length(tau_inv)) {
    precision <- rep(as.numeric(block$intercept_prec %||% 1.0e-9), length(lambda_inv))
    penalized <- as.integer(block$penalized %||% seq_along(lambda_inv))
    penalized <- penalized[penalized >= 1L & penalized <= length(lambda_inv)]
    if (length(penalized)) {
      slab <- if (length(zeta_inv)) zeta_inv[[1L]] else 0
      precision[penalized] <- tau_inv[[1L]] * lambda_inv[penalized] + slab
    }
  }
  out <- list(
    e_inv_lambda2 = lambda_inv,
    e_inv_nu = nu_inv,
    e_inv_tau2 = tau_inv,
    e_inv_xi = xi_inv,
    e_inv_zeta2 = zeta_inv,
    prior_precision = precision
  )
  flat <- unlist(out, use.names = FALSE)
  if (!length(flat) || any(!is.finite(flat))) {
    stop("RHS inferential state is empty or non-finite.", call. = FALSE)
  }
  out
}

app_glofas_quantile_rhs_block_inferential_state <- function(
  block,
  block_name = "rhs",
  include_names = FALSE
) {
  components <- app_glofas_quantile_rhs_block_inferential_components(block)
  if (!isTRUE(include_names)) return(unlist(components, use.names = FALSE))
  unlist(unname(Map(
    function(value, suffix) {
      value <- as.numeric(value)
      names(value) <- paste0(block_name, ".", suffix, "[", seq_along(value), "]")
      value
    },
    components,
    names(components)
  )), use.names = TRUE)
}

app_glofas_quantile_rhs_inferential_components <- function(state) {
  if (!is.list(state) || !length(state)) {
    stop("RHS state must be a non-empty list.", call. = FALSE)
  }
  is_block <- any(c(
    "lambda2_inv_mean", "e_inv_lambda2", "lambda2", "tau2_inv_mean",
    "e_inv_tau2", "tau2", "prior_precision"
  ) %in% names(state))
  blocks <- if (is_block) list(rhs = state) else state
  block_names <- names(blocks)
  if (is.null(block_names) || any(!nzchar(block_names))) {
    block_names <- paste0("rhs_", seq_along(blocks))
  }
  component_blocks <- lapply(blocks, app_glofas_quantile_rhs_block_inferential_components)
  component_names <- names(component_blocks[[1L]])
  if (any(!vapply(component_blocks, function(x) identical(names(x), component_names), logical(1L)))) {
    stop("RHS blocks expose incompatible inferential coordinates.", call. = FALSE)
  }
  list(
    auxiliary = unlist(lapply(component_blocks, function(x) {
      unlist(x[setdiff(component_names, "prior_precision")], use.names = FALSE)
    }), use.names = FALSE),
    prior_precision = unlist(lapply(component_blocks, `[[`, "prior_precision"), use.names = FALSE)
  )
}

app_glofas_quantile_rhs_inferential_state <- function(state, include_names = FALSE) {
  if (!isTRUE(include_names)) {
    return(unlist(app_glofas_quantile_rhs_inferential_components(state), use.names = FALSE))
  }
  is_block <- any(c(
    "lambda2_inv_mean", "e_inv_lambda2", "lambda2", "tau2_inv_mean",
    "e_inv_tau2", "tau2", "prior_precision"
  ) %in% names(state))
  blocks <- if (is_block) list(rhs = state) else state
  block_names <- names(blocks)
  if (is.null(block_names) || any(!nzchar(block_names))) {
    block_names <- paste0("rhs_", seq_along(blocks))
  }
  unlist(unname(Map(
    function(block, block_name) {
      app_glofas_quantile_rhs_block_inferential_state(
        block, block_name, include_names = TRUE
      )
    },
    blocks,
    block_names
  )), use.names = TRUE)
}

app_glofas_quantile_rhs_change_diagnostics <- function(current, previous, floor = 1) {
  current <- app_glofas_quantile_rhs_inferential_state(current, include_names = TRUE)
  previous <- app_glofas_quantile_rhs_inferential_state(previous, include_names = TRUE)
  if (!identical(names(current), names(previous)) ||
      length(current) != length(previous) ||
      any(!is.finite(current)) || any(!is.finite(previous))) {
    stop("RHS inferential coordinates changed between iterations.", call. = FALSE)
  }
  relative <- abs(current - previous) / pmax(as.numeric(floor), abs(previous))
  controlling <- which.max(relative)
  coordinate <- names(relative)[[controlling]]
  matched <- regexec("^([^.]+)\\.([^[]+)\\[([0-9]+)\\]$", coordinate)
  parsed <- regmatches(coordinate, matched)[[1L]]
  if (length(parsed) != 4L) {
    stop(sprintf("Unable to parse named RHS coordinate: %s", coordinate), call. = FALSE)
  }
  precision <- grepl("\\.prior_precision\\[", names(relative))
  safe_max <- function(x) if (length(x)) max(x) else 0
  list(
    max_relative_change = unname(relative[[controlling]]),
    max_auxiliary_change = safe_max(relative[!precision]),
    max_precision_change = safe_max(relative[precision]),
    controlling_coordinate = coordinate,
    controlling_block = parsed[[2L]],
    controlling_component = parsed[[3L]],
    controlling_index = as.integer(parsed[[4L]])
  )
}

app_glofas_exal_v_local_quadratic <- function(r_mean, r2_mean, lambda, sigma_mean, s_mean, s2_mean) {
  out <- as.numeric(r2_mean) -
    2 * as.numeric(lambda) * as.numeric(sigma_mean) * as.numeric(r_mean) * as.numeric(s_mean) +
    as.numeric(lambda)^2 * as.numeric(sigma_mean)^2 * as.numeric(s2_mean)
  pmax(out, .Machine$double.eps)
}

app_glofas_quantile_terminal_certificate <- function(
  trace,
  required_change_columns,
  tolerance = 1.0e-4,
  consecutive = 3L,
  required_gate_columns = character()
) {
  trace <- as.data.frame(trace)
  consecutive <- as.integer(consecutive)
  missing <- setdiff(c(required_change_columns, required_gate_columns), names(trace))
  if (length(missing)) {
    return(list(
      passed = FALSE,
      reason = paste0("missing_trace_columns:", paste(missing, collapse = ",")),
      terminal_passes = 0L,
      required_consecutive = consecutive
    ))
  }
  if (nrow(trace) < consecutive || consecutive < 1L) {
    return(list(passed = FALSE, reason = "insufficient_terminal_iterations", terminal_passes = 0L,
                required_consecutive = consecutive))
  }
  terminal <- tail(trace, consecutive)
  changes <- as.matrix(terminal[, required_change_columns, drop = FALSE])
  change_ok <- all(is.finite(changes)) && all(changes <= tolerance)
  gate_ok <- if (length(required_gate_columns)) {
    all(vapply(terminal[, required_gate_columns, drop = FALSE], function(x) all(as.logical(x)), logical(1L)))
  } else TRUE
  row_pass <- apply(changes, 1L, function(x) all(is.finite(x)) && all(x <= tolerance))
  if (length(required_gate_columns)) {
    row_pass <- row_pass & apply(terminal[, required_gate_columns, drop = FALSE], 1L, function(x) all(as.logical(x)))
  }
  list(
    passed = isTRUE(change_ok && gate_ok),
    reason = if (change_ok && gate_ok) "terminal_full_state_certificate_passed" else "terminal_full_state_certificate_failed",
    terminal_passes = sum(row_pass),
    required_consecutive = consecutive,
    tolerance = tolerance,
    terminal_rows = terminal
  )
}

app_glofas_quantile_validate_production_iteration_contract <- function(
  max_iter,
  min_iter,
  fixed_iterations,
  freeze_beta_warmup_iters,
  terminal_consecutive_passes,
  expected_iterations = 200L
) {
  values <- as.integer(c(max_iter, min_iter, freeze_beta_warmup_iters, terminal_consecutive_passes))
  if (any(!is.finite(values)) || !isTRUE(fixed_iterations) ||
      as.integer(max_iter) != expected_iterations || as.integer(min_iter) != expected_iterations ||
      as.integer(freeze_beta_warmup_iters) != 20L || as.integer(terminal_consecutive_passes) < 3L) {
    stop(
      "Promotable GloFAS quantile fits require fixed 200/200 iterations, a 20-iteration beta freeze, and at least three terminal certificate rows.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}
