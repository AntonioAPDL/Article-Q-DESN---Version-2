if (!exists("app_set_repo_root", mode = "function")) {
  source("application/R/00_packages.R")
  app_set_repo_root(getwd())
}
source(app_path("application/R/glofas_part4_publication_contract.R"))

trace <- data.frame(
  outer_iteration = 1:10,
  parameter_change = c(0.006, 0.003, 0.0026, 0.0017, 0.0016, 0.00102, 0.0086, 0.0067, 0.0062, 0.0041),
  all_inner_converged = TRUE,
  outer_tolerance_met = FALSE,
  rhs_convergence_gate_passed = c(rep(NA, 5), FALSE, rep(TRUE, 4))
)
convergence <- data.frame(
  converged = FALSE, outer_converged = FALSE, inner_converged = TRUE,
  rhs_converged = TRUE, outer_iterations = 10L,
  stopping_reason = "max_outer_iterations_outer_tolerance_not_met"
)
rhs <- expand.grid(
  component = c("reference", "discrepancy"),
  rhs_block = c("anchor", paste0("delta_", 2:7)),
  stringsAsFactors = FALSE
)
rhs$passed <- TRUE
rhs$tau_update_count <- 5L
rhs$coefficient_response_after_release <- TRUE
rhs$schedule_rebased <- TRUE
rhs$source_freeze_iters <- 50L
rhs$effective_freeze_outer_iters <- 5L
rhs$max_abs_block_mean_change_from_source <- 1.0e-6

qualified <- app_glofas_part4_validate_cap_qualified_joint(trace, convergence, rhs)
stopifnot(
  identical(qualified$numerical_status, "cap_stabilized_after_rhs_release"),
  isTRUE(qualified$selection_eligible),
  !isTRUE(qualified$strict_outer_converged),
  qualified$outer_iterations == 10L
)

expect_error <- function(expr) {
  inherits(try(force(expr), silent = TRUE), "try-error")
}
bad_convergence <- convergence
bad_convergence$converged <- TRUE
stopifnot(expect_error(app_glofas_part4_validate_cap_qualified_joint(trace, bad_convergence, rhs)))
bad_rhs <- rhs
bad_rhs$max_abs_block_mean_change_from_source[[1L]] <- 0
stopifnot(expect_error(app_glofas_part4_validate_cap_qualified_joint(trace, convergence, bad_rhs)))
bad_trace <- trace
bad_trace$all_inner_converged[[10L]] <- FALSE
stopifnot(expect_error(app_glofas_part4_validate_cap_qualified_joint(bad_trace, convergence, rhs)))

source_rows <- expand.grid(
  target_date = as.Date("2022-12-26") + 0:1,
  horizon = 1:2,
  quantile_level = c(0.05, 0.50),
  KEEP.OUT.ATTRS = FALSE
)
source_rows <- source_rows[source_rows$horizon == as.integer(source_rows$target_date - as.Date("2022-12-25")), ]
source_rows$qhat <- seq_len(nrow(source_rows)) / 10
source_rows$check_loss <- seq_len(nrow(source_rows)) / 100
final_rows <- source_rows
final_rows$qhat <- final_rows$qhat + 0.01
final_rows$check_loss <- final_rows$check_loss - 0.001
stability <- app_glofas_part4_sweep_stability(source_rows, final_rows)
stopifnot(
  nrow(stability) == 3L,
  stability$scope[[1L]] == "all_quantiles",
  isTRUE(all.equal(stability$mean_abs_path_change[[1L]], 0.01, tolerance = 1.0e-12))
)
