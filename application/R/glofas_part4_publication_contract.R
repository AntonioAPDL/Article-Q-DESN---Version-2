app_glofas_part4_validate_cap_qualified_joint <- function(
    trace,
    convergence,
    rhs_certificate,
    expected_outer_iterations = 10L,
    expected_rhs_updates = 5L,
    response_tolerance = 1.0e-12) {
  required_trace <- c(
    "outer_iteration", "parameter_change", "all_inner_converged",
    "outer_tolerance_met", "rhs_convergence_gate_passed"
  )
  missing_trace <- setdiff(required_trace, names(trace))
  if (length(missing_trace)) {
    stop(sprintf("Joint AL trace is missing: %s.", paste(missing_trace, collapse = ", ")), call. = FALSE)
  }
  required_convergence <- c(
    "converged", "outer_converged", "inner_converged", "rhs_converged",
    "outer_iterations", "stopping_reason"
  )
  missing_convergence <- setdiff(required_convergence, names(convergence))
  if (length(missing_convergence)) {
    stop(sprintf("Joint AL convergence record is missing: %s.", paste(missing_convergence, collapse = ", ")), call. = FALSE)
  }
  required_rhs <- c(
    "component", "rhs_block", "passed", "tau_update_count",
    "coefficient_response_after_release", "schedule_rebased",
    "source_freeze_iters", "effective_freeze_outer_iters",
    "max_abs_block_mean_change_from_source"
  )
  missing_rhs <- setdiff(required_rhs, names(rhs_certificate))
  if (length(missing_rhs)) {
    stop(sprintf("Joint AL RHS certificate is missing: %s.", paste(missing_rhs, collapse = ", ")), call. = FALSE)
  }

  expected_iterations <- seq_len(as.integer(expected_outer_iterations))
  if (!identical(as.integer(trace$outer_iteration), expected_iterations) ||
      any(!is.finite(as.numeric(trace$parameter_change))) ||
      !all(trace$all_inner_converged) ||
      isTRUE(tail(trace$outer_tolerance_met, 1L)) ||
      !isTRUE(tail(trace$rhs_convergence_gate_passed, 1L))) {
    stop("Joint AL did not complete the audited ten-sweep cap with valid inner/RHS gates.", call. = FALSE)
  }
  if (nrow(convergence) != 1L || isTRUE(convergence$converged) ||
      isTRUE(convergence$outer_converged) || !isTRUE(convergence$inner_converged) ||
      !isTRUE(convergence$rhs_converged) ||
      as.integer(convergence$outer_iterations) != as.integer(expected_outer_iterations) ||
      !identical(
        as.character(convergence$stopping_reason),
        "max_outer_iterations_outer_tolerance_not_met"
      )) {
    stop("Joint AL cap qualification must preserve its nonconverged outer status.", call. = FALSE)
  }
  if (nrow(rhs_certificate) != 14L ||
      !setequal(rhs_certificate$component, c("reference", "discrepancy")) ||
      !all(rhs_certificate$passed) ||
      !all(rhs_certificate$coefficient_response_after_release) ||
      !all(rhs_certificate$schedule_rebased) ||
      any(as.integer(rhs_certificate$tau_update_count) != as.integer(expected_rhs_updates)) ||
      !identical(unique(as.integer(rhs_certificate$source_freeze_iters)), 50L) ||
      !identical(unique(as.integer(rhs_certificate$effective_freeze_outer_iters)), 5L) ||
      anyNA(rhs_certificate$max_abs_block_mean_change_from_source) ||
      any(rhs_certificate$max_abs_block_mean_change_from_source <= response_tolerance)) {
    stop("Joint AL RHS release or numerical-response certificate failed.", call. = FALSE)
  }

  data.frame(
    numerical_status = "cap_stabilized_after_rhs_release",
    selection_eligible = TRUE,
    strict_outer_converged = FALSE,
    all_inner_converged = TRUE,
    rhs_release_qualified = TRUE,
    outer_iterations = as.integer(expected_outer_iterations),
    final_parameter_change = tail(as.numeric(trace$parameter_change), 1L),
    stringsAsFactors = FALSE
  )
}

app_glofas_part4_sweep_stability <- function(source_rows, final_rows) {
  keys <- c("target_date", "horizon", "quantile_level")
  required <- c(keys, "qhat", "check_loss")
  if (!all(required %in% names(source_rows)) || !all(required %in% names(final_rows))) {
    stop("Sweep stability inputs do not share the required scoring schema.", call. = FALSE)
  }
  joined <- merge(
    source_rows[required], final_rows[required], by = keys,
    suffixes = c("_source", "_final"), sort = TRUE
  )
  if (nrow(joined) != nrow(source_rows) || nrow(joined) != nrow(final_rows)) {
    stop("Sweep stability rows do not match one-to-one.", call. = FALSE)
  }
  joined$path_change <- joined$qhat_final - joined$qhat_source
  by_quantile <- do.call(rbind, lapply(split(joined, joined$quantile_level), function(block) {
    data.frame(
      scope = sprintf("quantile_%s", unique(block$quantile_level)),
      quantile_level = unique(block$quantile_level),
      n_rows = nrow(block),
      mean_abs_path_change = mean(abs(block$path_change)),
      median_abs_path_change = median(abs(block$path_change)),
      max_abs_path_change = max(abs(block$path_change)),
      mean_check_loss_source = mean(block$check_loss_source),
      mean_check_loss_final = mean(block$check_loss_final),
      stringsAsFactors = FALSE
    )
  }))
  overall <- data.frame(
    scope = "all_quantiles",
    quantile_level = NA_real_,
    n_rows = nrow(joined),
    mean_abs_path_change = mean(abs(joined$path_change)),
    median_abs_path_change = median(abs(joined$path_change)),
    max_abs_path_change = max(abs(joined$path_change)),
    mean_check_loss_source = mean(joined$check_loss_source),
    mean_check_loss_final = mean(joined$check_loss_final),
    stringsAsFactors = FALSE
  )
  rbind(overall, by_quantile)
}
