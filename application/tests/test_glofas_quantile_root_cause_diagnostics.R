#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_quantile_integrity.R"))
source(app_path("application/R/latent_path_vb_joint.R"))
source(app_path("application/R/glofas_quantile_root_cause_diagnostics.R"))

block <- list(
  penalized = 2:3,
  intercept_prec = 1.0e-9,
  e_inv_lambda2 = c(1, 2, 3),
  e_inv_nu = c(1, 0.5, 0.25),
  e_inv_tau2 = 4,
  e_inv_xi = 0.2,
  e_inv_zeta2 = 0.1,
  prior_precision = c(1.0e-9, 8.1, 12.1),
  tau_update_count = 399L,
  last_update_iteration = 399L
)
state_a <- list(anchor = block)
state_b <- state_a
state_b$anchor$tau_update_count <- 400L
state_b$anchor$last_update_iteration <- 400L
stopifnot(
  identical(
    app_glofas_quantile_rhs_inferential_state(state_a),
    app_glofas_quantile_rhs_inferential_state(state_b)
  ),
  app_glofas_quantile_max_relative_change(
    app_glofas_quantile_numeric_state(state_b),
    app_glofas_quantile_numeric_state(state_a)
  ) > 1.0e-3
)
named_semantic <- app_glofas_quantile_rhs_inferential_state(state_a, include_names = TRUE)
stopifnot(
  length(named_semantic) == length(app_glofas_quantile_rhs_inferential_state(state_a)),
  all(nzchar(names(named_semantic))),
  any(grepl("prior_precision", names(named_semantic), fixed = TRUE))
)

counter_only <- app_glofas_quantile_rhs_change_diagnostics(state_b, state_a)
stopifnot(
  identical(counter_only$max_relative_change, 0),
  identical(counter_only$max_auxiliary_change, 0),
  identical(counter_only$max_precision_change, 0)
)

state_c <- state_b
state_c$anchor$e_inv_tau2 <- 4.4
state_c$anchor$prior_precision[2:3] <- c(8.9, 13.3)
semantic_change <- app_glofas_quantile_max_relative_change(
  app_glofas_quantile_rhs_inferential_state(state_c),
  app_glofas_quantile_rhs_inferential_state(state_b)
)
stopifnot(semantic_change > 0.09)
named_change <- app_glofas_quantile_rhs_change_diagnostics(state_c, state_b)
stopifnot(
  isTRUE(all.equal(named_change$max_relative_change, semantic_change)),
  identical(named_change$controlling_block, "anchor"),
  named_change$controlling_component %in% c("e_inv_tau2", "prior_precision"),
  nzchar(named_change$controlling_coordinate),
  named_change$max_auxiliary_change > 0,
  named_change$max_precision_change > 0
)

update <- function(state, iteration) {
  state$anchor$tau_update_count <- state$anchor$tau_update_count + 1L
  state$anchor$last_update_iteration <- state$anchor$last_update_iteration + 1L
  state$anchor$e_inv_tau2 <- 4 + (state$anchor$e_inv_tau2 - 4) / 2
  state$anchor$prior_precision[2:3] <-
    state$anchor$e_inv_tau2 * state$anchor$e_inv_lambda2[2:3] + state$anchor$e_inv_zeta2
  state
}
replay <- app_glofas_rootcause_fixed_point_replay(
  state_c, update, iterations = 20L, tolerance = 1.0e-4, label = "toy"
)
stopifnot(
  tail(replay$trace$inferential_relative_change, 1L) < 1.0e-4,
  tail(replay$trace$raw_relative_change, 1L) > 1.0e-4,
  isTRUE(tail(replay$trace$semantic_pass, 1L))
)

stopifnot(
  app_latent_joint_trailing_true_count(logical()) == 0L,
  app_latent_joint_trailing_true_count(c(TRUE, TRUE, FALSE, TRUE, TRUE)) == 2L,
  app_latent_joint_trailing_true_count(c(TRUE, NA, TRUE)) == 1L
)

cat("GLOFAS_QUANTILE_ROOT_CAUSE_DIAGNOSTICS_TEST_PASS\n")
