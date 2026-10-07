# Focused diagnostics for nested Part 4 joint-exAL inner updates.

app_glofas_part4_exal_terminal_quadrature <- function(fit, tolerance = 1.0e-6) {
  diagnostics <- as.data.frame(fit$vb_diagnostics$quadrature_trace %||% data.frame())
  required <- c("iteration", "source", "nodes_per_panel", "relative_change")
  if (!nrow(diagnostics) || !all(required %in% names(diagnostics))) {
    return(data.frame(
      source = c("Y", "G"), quadrature_iteration = NA_integer_,
      quadrature_nodes = NA_integer_, quadrature_relative_change = Inf,
      quadrature_pass = FALSE, stringsAsFactors = FALSE
    ))
  }
  terminal_iteration <- max(as.integer(diagnostics$iteration), na.rm = TRUE)
  terminal <- diagnostics[diagnostics$iteration == terminal_iteration, , drop = FALSE]
  rows <- lapply(c("Y", "G"), function(source) {
    block <- terminal[terminal$source == source, , drop = FALSE]
    if (!nrow(block)) {
      return(data.frame(
        source = source, quadrature_iteration = terminal_iteration,
        quadrature_nodes = NA_integer_, quadrature_relative_change = Inf,
        quadrature_pass = FALSE, stringsAsFactors = FALSE
      ))
    }
    row <- block[which.max(as.integer(block$nodes_per_panel)), , drop = FALSE]
    change <- as.numeric(row$relative_change[[1L]])
    data.frame(
      source = source,
      quadrature_iteration = terminal_iteration,
      quadrature_nodes = as.integer(row$nodes_per_panel[[1L]]),
      quadrature_relative_change = change,
      quadrature_pass = is.finite(change) && change <= tolerance,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_glofas_part4_exal_inner_gate <- function(
  fit,
  tau,
  parameter_tolerance = 1.0e-4,
  quadrature_tolerance = 1.0e-6
) {
  trace <- as.data.frame(fit$vb_diagnostics$iteration_trace %||% data.frame())
  if (!nrow(trace) || !all(c("iteration", "parameter_change", "convergence_eligible") %in% names(trace))) {
    stop("The exAL fit does not contain a complete inner iteration trace.", call. = FALSE)
  }
  terminal <- trace[nrow(trace), , drop = FALSE]
  parameter_change <- as.numeric(terminal$parameter_change[[1L]])
  eligible <- isTRUE(terminal$convergence_eligible[[1L]])
  parameter_pass <- eligible && is.finite(parameter_change) &&
    parameter_change < parameter_tolerance
  quadrature <- app_glofas_part4_exal_terminal_quadrature(fit, quadrature_tolerance)
  quadrature_pass <- nrow(quadrature) == 2L && all(quadrature$quadrature_pass)
  recorded <- isTRUE(fit$vb_diagnostics$converged)
  recomputed <- parameter_pass && quadrature_pass
  blocker <- if (recomputed) {
    "none"
  } else if (!parameter_pass && !quadrature_pass) {
    "parameter_and_quadrature"
  } else if (!parameter_pass) {
    "parameter_change"
  } else {
    "quadrature"
  }
  data.frame(
    quantile_level = as.numeric(tau),
    recorded_converged = recorded,
    recomputed_converged = recomputed,
    convergence_eligible = eligible,
    inner_iterations = as.integer(terminal$iteration[[1L]]),
    parameter_change = parameter_change,
    parameter_tolerance = as.numeric(parameter_tolerance),
    parameter_pass = parameter_pass,
    quadrature_tolerance = as.numeric(quadrature_tolerance),
    quadrature_pass = quadrature_pass,
    quadrature_Y_relative_change = quadrature$quadrature_relative_change[quadrature$source == "Y"],
    quadrature_G_relative_change = quadrature$quadrature_relative_change[quadrature$source == "G"],
    blocker = blocker,
    stringsAsFactors = FALSE
  )
}

app_glofas_part4_exal_inner_table <- function(
  joint_fit,
  parameter_tolerance = 1.0e-4,
  quadrature_tolerance = 1.0e-6
) {
  if (length(joint_fit$fits) != length(joint_fit$tau) || !length(joint_fit$fits)) {
    stop("The joint exAL fit has inconsistent quantile components.", call. = FALSE)
  }
  rows <- Map(
    app_glofas_part4_exal_inner_gate,
    joint_fit$fits,
    as.list(as.numeric(joint_fit$tau)),
    MoreArgs = list(
      parameter_tolerance = parameter_tolerance,
      quadrature_tolerance = quadrature_tolerance
    )
  )
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

app_glofas_part4_exal_stability_summary <- function(previous, current) {
  if (!identical(as.numeric(previous$tau), as.numeric(current$tau))) {
    stop("Checkpoint quantile grids differ.", call. = FALSE)
  }
  rows <- lapply(seq_along(current$tau), function(index) {
    old_theta <- as.numeric(previous$fits[[index]]$summary$theta_mean)
    new_theta <- as.numeric(current$fits[[index]]$summary$theta_mean)
    old_path <- as.numeric(previous$fits[[index]]$variational_state$y_future_mean)
    new_path <- as.numeric(current$fits[[index]]$variational_state$y_future_mean)
    if (length(old_theta) != length(new_theta) || length(old_path) != length(new_path)) {
      stop("Checkpoint states are dimension-incompatible.", call. = FALSE)
    }
    data.frame(
      quantile_level = as.numeric(current$tau[[index]]),
      coefficient_max_abs_change = max(abs(new_theta - old_theta)),
      coefficient_rms_change = sqrt(mean((new_theta - old_theta)^2)),
      latent_path_max_abs_change = max(abs(new_path - old_path)),
      latent_path_mean_abs_change = mean(abs(new_path - old_path)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_glofas_part4_exal_probe_decision <- function(table) {
  required <- c("quantile_level", "recorded_converged", "parameter_pass", "quadrature_pass")
  if (!all(required %in% names(table)) || !nrow(table)) {
    stop("Probe decision requires a complete inner-gate table.", call. = FALSE)
  }
  tail_rows <- table[table$quantile_level %in% c(0.05, 0.95), , drop = FALSE]
  if (nrow(tail_rows) != 2L) stop("Probe decision requires both extreme quantiles.", call. = FALSE)
  if (all(table$recorded_converged)) {
    return("READY_FOR_TARGETED_JOINT_EXAL_CORRECTION")
  }
  if (all(table$parameter_pass) && any(!table$quadrature_pass)) {
    return("QUADRATURE_CERTIFICATE_REQUIRES_NUMERICAL_REFINEMENT")
  }
  if (any(!tail_rows$parameter_pass)) {
    return("EXAL_TAIL_UPDATE_MAP_REQUIRES_CORRECTION")
  }
  "EXAL_INNER_CONVERGENCE_REMAINS_UNRESOLVED"
}

app_glofas_part4_exal_quadrature_state_vector <- function(update) {
  required <- c("log_normalizer", "branch_mass", "moments", "nodes_per_panel", "converged")
  if (!is.list(update) || !all(required %in% names(update))) {
    stop("A complete structured exAL quadrature update is required.", call. = FALSE)
  }
  values <- c(
    log_normalizer = as.numeric(update$log_normalizer),
    setNames(as.numeric(update$branch_mass), paste0("branch_mass_", names(update$branch_mass))),
    setNames(as.numeric(update$moments), paste0("moment_", names(update$moments)))
  )
  if (!length(values) || any(!is.finite(values))) {
    stop("The structured exAL quadrature state contains non-finite values.", call. = FALSE)
  }
  values
}

app_glofas_part4_exal_quadrature_certificate <- function(
  candidate,
  reference,
  tolerance = 1.0e-6,
  reference_tolerance = 1.0e-8
) {
  sources <- c("Y", "G")
  if (!all(sources %in% names(candidate)) || !all(sources %in% names(reference))) {
    stop("Candidate and reference quadrature updates require Y and G blocks.", call. = FALSE)
  }
  rows <- lapply(sources, function(source) {
    candidate_vector <- app_glofas_part4_exal_quadrature_state_vector(candidate[[source]])
    reference_vector <- app_glofas_part4_exal_quadrature_state_vector(reference[[source]])
    if (!identical(names(candidate_vector), names(reference_vector))) {
      stop(sprintf("Quadrature state fields differ for source '%s'.", source), call. = FALSE)
    }
    relative_difference <- max(
      abs(candidate_vector - reference_vector) /
        pmax(1, abs(candidate_vector), abs(reference_vector))
    )
    reference_change <- as.numeric(reference[[source]]$relative_change)
    candidate_pass <- isTRUE(candidate[[source]]$converged)
    reference_pass <- isTRUE(reference[[source]]$converged) &&
      is.finite(reference_change) && reference_change <= reference_tolerance
    comparison_pass <- is.finite(relative_difference) && relative_difference <= tolerance
    data.frame(
      source = source,
      candidate_nodes = as.integer(candidate[[source]]$nodes_per_panel),
      candidate_converged = candidate_pass,
      candidate_relative_change = as.numeric(candidate[[source]]$relative_change),
      reference_nodes = as.integer(reference[[source]]$nodes_per_panel),
      reference_converged = reference_pass,
      reference_relative_change = reference_change,
      candidate_reference_relative_difference = relative_difference,
      tolerance = as.numeric(tolerance),
      reference_tolerance = as.numeric(reference_tolerance),
      passed = candidate_pass && reference_pass && comparison_pass,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

app_glofas_part4_exal_quadrature_component_table <- function(candidate, reference) {
  sources <- c("Y", "G")
  if (!all(sources %in% names(candidate)) || !all(sources %in% names(reference))) {
    stop("Candidate and reference quadrature updates require Y and G blocks.", call. = FALSE)
  }
  rows <- lapply(sources, function(source) {
    candidate_vector <- app_glofas_part4_exal_quadrature_state_vector(candidate[[source]])
    reference_vector <- app_glofas_part4_exal_quadrature_state_vector(reference[[source]])
    if (!identical(names(candidate_vector), names(reference_vector))) {
      stop(sprintf("Quadrature state fields differ for source '%s'.", source), call. = FALSE)
    }
    data.frame(
      source = source,
      component = names(candidate_vector),
      candidate = as.numeric(candidate_vector),
      reference = as.numeric(reference_vector),
      absolute_difference = abs(candidate_vector - reference_vector),
      relative_difference = abs(candidate_vector - reference_vector) /
        pmax(1, abs(candidate_vector), abs(reference_vector)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
