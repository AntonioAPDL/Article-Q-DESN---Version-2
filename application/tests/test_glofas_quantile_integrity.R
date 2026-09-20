#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_quantile_integrity.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/latent_path_vb_joint.R"))

tmp <- tempfile("glofas_quantile_integrity_")
dir.create(tmp)
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

tau <- c(0.05, 0.20, 0.50, 0.95)
paths <- vapply(seq_along(tau), function(i) {
  path <- file.path(tmp, sprintf("q%02d.rds", i))
  saveRDS(list(tau = tau[[i]], beta_mean = c(i, -i), alpha_mean = i), path)
  path
}, character(1L))

permuted <- paths[c(4, 2, 1, 3)]
mapping <- app_glofas_quantile_initializer_map(as.list(permuted), tau)
stopifnot(
  identical(as.numeric(mapping$source_tau), tau),
  identical(as.numeric(mapping$target_tau), tau),
  all(mapping$mapping_status == "exact_tau_match")
)

duplicate <- c(paths[[1]], paths[[1]], paths[[3]], paths[[4]])
duplicate_error <- tryCatch({
  app_glofas_quantile_initializer_map(as.list(duplicate), tau)
  FALSE
}, error = function(e) TRUE)
stopifnot(duplicate_error)

multi <- list(
  tau = tau,
  beta_mean = unlist(lapply(seq_along(tau), function(i) c(i, -i))),
  alpha_mean = seq_along(tau),
  sigma_mean = rep(1, length(tau))
)
selected <- app_glofas_quantile_select_column(multi, 3L, coefficient_block_size = 2L)
stopifnot(selected$tau == tau[[3]], identical(selected$beta_mean, c(3, -3)), selected$alpha_mean == 3)

trace <- data.frame(
  iter = 1:5,
  change_a = c(1, 0.1, 1e-5, 1e-6, 1e-7),
  change_b = c(1, 0.1, 2e-5, 2e-6, 2e-7),
  eligible = c(FALSE, FALSE, TRUE, TRUE, TRUE)
)
certificate <- app_glofas_quantile_terminal_certificate(
  trace, c("change_a", "change_b"), tolerance = 1e-4,
  consecutive = 3L, required_gate_columns = "eligible"
)
stopifnot(certificate$passed, certificate$terminal_passes == 3L)
trace$change_b[[5L]] <- 1e-2
stopifnot(!app_glofas_quantile_terminal_certificate(
  trace, c("change_a", "change_b"), 1e-4, 3L, "eligible"
)$passed)

r <- c(-2, 0.5, 3)
r2 <- r^2 + c(0.2, 0.3, 0.4)
lambda <- 0.7
sigma <- 1.2
s <- c(0.4, 0.8, 1.1)
s2 <- s^2 + 0.25
expected <- r2 - 2 * lambda * sigma * r * s + lambda^2 * sigma^2 * s2
stopifnot(max(abs(app_glofas_exal_v_local_quadratic(r, r2, lambda, sigma, s, s2) - expected)) < 1e-12)

contract_error <- tryCatch({
  app_glofas_quantile_validate_production_iteration_contract(200, 30, TRUE, 20, 3)
  FALSE
}, error = function(e) TRUE)
stopifnot(contract_error)
app_glofas_quantile_validate_production_iteration_contract(200, 200, TRUE, 20, 3)

schedule <- app_latent_joint_rhs_control(list(
  rhs = list(freeze_tau_warmup_iters = 50L, update_every = 1L, min_tau_updates = 1L),
  joint_inner_min_iter = 10L
))
stopifnot(schedule$effective$freeze_tau_warmup_iters == 5L)
state <- list(
  rhs_control = schedule$effective, tau_update_count = 0L,
  first_tau_update_iter = NA_integer_, last_global_relative_change = 0
)
stopifnot(!app_latent_joint_rhs_gate(list(anchor = state), 5L, "reference")$passed)
state$tau_update_count <- 1L
state$first_tau_update_iter <- 6L
stopifnot(!app_latent_joint_rhs_gate(list(anchor = state), 6L, "reference")$passed)
stopifnot(app_latent_joint_rhs_gate(list(anchor = state), 7L, "reference")$passed)

cat("GLOFAS_QUANTILE_INTEGRITY_TEST_PASS\n")

