candidate_path <- app_path(
  "application/config/glofas_context_prior_repair_candidates_20260826.csv"
)
prior_candidates <- app_glofas_context_prior_validate_candidates(
  app_read_csv(candidate_path)
)
stopifnot(nrow(prior_candidates) == 6L)
stopifnot(identical(
  prior_candidates$context_prior_sd,
  c(0.005, 0.010, 0.025, 0.050, 0.100, 0.200)
))
stopifnot(all(prior_candidates$warm_start_source_candidate == "t01_last"))
stopifnot(all(!prior_candidates$warm_start_use_theta))
declared_precision <- vapply(prior_candidates$context_prior_sd, function(sd) {
  group <- app_latent_normalize_fixed_gaussian_groups(
    list(list(name = "declared", global_index = 2L, sd = sd)),
    p = 3L
  )
  group[[1L]]$precision
}, numeric(1L))
stopifnot(isTRUE(all.equal(
  declared_precision,
  1 / prior_candidates$context_prior_sd^2
)))

base_args <- list(
  beta_rhs = list(tau0 = 0.1, a_zeta = 2, b_zeta = 4),
  alpha_rhs = list(tau0 = 0.001, a_zeta = 2, b_zeta = 4),
  rhs = list(freeze_tau_warmup_iters = 0L, update_every = 1L, min_tau_updates = 1L)
)
plain <- app_latent_prior_state_init(
  p = 8L,
  prior = "rhs",
  intercept_index = c(1L, 5L),
  vb_args = base_args,
  beta_index = 1:4,
  alpha_index = 5:8
)
plain_repeat <- app_latent_prior_state_init(
  p = 8L,
  prior = "rhs",
  intercept_index = c(1L, 5L),
  vb_args = base_args,
  beta_index = 1:4,
  alpha_index = 5:8,
  fixed_gaussian_groups = NULL
)
stopifnot(identical(plain, plain_repeat))

hybrid <- app_latent_prior_state_init(
  p = 8L,
  prior = "rhs",
  intercept_index = c(1L, 5L),
  vb_args = base_args,
  beta_index = 1:4,
  alpha_index = 5:8,
  fixed_gaussian_groups = list(list(
    name = "alpha_context",
    global_index = 8L,
    sd = 0.05
  ))
)
stopifnot(isTRUE(all.equal(hybrid$prior_precision[[8L]], 400)))
stopifnot(!4L %in% hybrid$blocks$alpha$state$penalized)
updated <- app_latent_prior_state_update(
  hybrid,
  theta_mean = rep(0.1, 8L),
  theta_cov = diag(0.01, 8L),
  iter = 1L
)
stopifnot(isTRUE(all.equal(updated$prior_precision[[8L]], 400)))
fixed_diag <- app_latent_prior_fixed_gaussian_diagnostics(
  updated, rep(0.1, 8L), diag(0.01, 8L)
)
stopifnot(nrow(fixed_diag) == 1L, fixed_diag$n_coefficients[[1L]] == 1L)

overlap <- list(
  list(name = "a", global_index = 8L, sd = 0.1),
  list(name = "b", global_index = 8L, sd = 0.2)
)
stopifnot(inherits(try(
  app_latent_normalize_fixed_gaussian_groups(overlap, 8L),
  silent = TRUE
), "try-error"))
stopifnot(inherits(try(
  app_latent_normalize_fixed_gaussian_groups(
    list(list(name = "bad", global_index = 1L, sd = 0.1)),
    8L,
    intercept_index = 1L
  ),
  silent = TRUE
), "try-error"))

make_design <- function(order = 1:3) {
  info <- data.frame(
    block = c("intercept", "reservoir_state", "direct_covariate_lag"),
    variable = c(NA, NA, "glofas_level"),
    lag = c(NA, NA, 0L),
    column_name = c("intercept", "reservoir_0001", "glofas_level_lag_0"),
    stringsAsFactors = FALSE
  )[order, , drop = FALSE]
  list(
    feature_info_alpha = info,
    alpha_index = 4L + seq_len(nrow(info)),
    H_fixed = matrix(0, nrow = 2L, ncol = 4L + nrow(info))
  )
}
spec <- list(
  enabled = TRUE,
  name = "alpha_context",
  variables = list("glofas_level"),
  lags = list(0L),
  sd = 0.025
)
contract_a <- app_latent_path_context_fixed_gaussian_contract(make_design(), spec)
contract_b <- app_latent_path_context_fixed_gaussian_contract(make_design(c(3, 1, 2)), spec)
stopifnot(contract_a$groups[[1L]]$column_name == "glofas_level_lag_0")
stopifnot(contract_b$groups[[1L]]$column_name == "glofas_level_lag_0")
stopifnot(contract_a$groups[[1L]]$sd == 0.025)
stopifnot(!app_latent_path_context_fixed_gaussian_contract(
  make_design(),
  list(enabled = FALSE)
)$enabled)
invalid_variable_spec <- spec
invalid_variable_spec$variables <- list("ppt")
stopifnot(inherits(try(
  app_latent_path_context_fixed_gaussian_contract(
    make_design(),
    invalid_variable_spec
  ),
  silent = TRUE
), "try-error"))
incomplete_spec <- spec
incomplete_spec$variables <- list("glofas_level", "glofas_anomaly")
stopifnot(inherits(try(
  app_latent_path_context_fixed_gaussian_contract(
    make_design(),
    incomplete_spec
  ),
  silent = TRUE
), "try-error"))

checkpoint_design <- list(
  H_fixed = matrix(0, nrow = 4L, ncol = 8L),
  future_key = data.frame(
    target_date = as.Date("2026-01-01") + 0:1,
    stringsAsFactors = FALSE
  ),
  design_version = "fixture",
  warm_start_design_hash = "fixture_design_hash"
)
colnames(checkpoint_design$H_fixed) <- paste0("theta_", seq_len(8L))
checkpoint_base <- modifyList(
  base_args,
  list(
    max_iter = 5L,
    fixed_gaussian_groups = contract_a$groups
  )
)
checkpoint_other <- checkpoint_base
checkpoint_other$fixed_gaussian_groups[[1L]]$sd <- 0.050
checkpoint_other$fixed_gaussian_groups[[1L]]$precision <- 400
checkpoint_a <- app_latent_checkpoint_contract(
  checkpoint_design,
  p0 = 0.5,
  coefficient_prior = "rhs",
  vb_args = checkpoint_base,
  seed = 1L,
  backend_fail_closed = FALSE
)
checkpoint_b <- app_latent_checkpoint_contract(
  checkpoint_design,
  p0 = 0.5,
  coefficient_prior = "rhs",
  vb_args = checkpoint_other,
  seed = 1L,
  backend_fail_closed = FALSE
)
stopifnot(!identical(checkpoint_a$contract_hash, checkpoint_b$contract_hash))

cfg_hybrid_core <- list(
  inference = list(
    vb_ld = list(
      max_iter = 4L,
      min_iter_elbo = 1L,
      tol = 1.0e-8,
      tol_par = 1.0e-8,
      n_draws = 6L,
      rhs_tau0 = 0.5,
      rhs_freeze_tau_warmup_iters = 0L,
      rhs_min_tau_updates = 0L,
      intercept_prec = 1.0e-9,
      sigma_a = 2,
      sigma_b = 1
    ),
    mcmc = list(rhs_tau0 = 0.5, intercept_prec = 1.0e-9),
    likelihood_family = "al"
  ),
  synthetic_recovery = list(
    n_history = 24L,
    horizon = 2L,
    n_members = 5L,
    seed = 20260826L,
    p0 = 0.5
  ),
  reservoir = list(seed = 20260826L)
)
sim_hybrid_core <- app_latent_path_recovery_simulate(cfg_hybrid_core)
design_hybrid_core <- app_make_latent_path_recovery_design(
  sim_hybrid_core,
  cfg_hybrid_core
)
fixed_index_core <- utils::tail(setdiff(
  design_hybrid_core$alpha_index,
  design_hybrid_core$intercept_index
), 1L)
vb_hybrid_core <- app_make_qdesn_discrepancy_vb_args(
  cfg_hybrid_core,
  prior = "rhs_ns",
  seed = sim_hybrid_core$seed,
  likelihood_family = "al"
)
vb_hybrid_core$diagnostics <- modifyList(
  vb_hybrid_core$diagnostics %||% list(),
  list(fixed_iterations = TRUE)
)
vb_hybrid_core$fixed_gaussian_groups <- list(list(
  name = "fixture_context",
  global_index = fixed_index_core,
  sd = 0.05
))
fit_hybrid_reference <- app_fit_latent_path_al_vb_core(
  design_hybrid_core,
  p0 = sim_hybrid_core$p0,
  coefficient_prior = "rhs_ns",
  vb_args = vb_hybrid_core,
  seed = sim_hybrid_core$seed
)
stopifnot(nrow(fit_hybrid_reference$vb_diagnostics$fixed_gaussian_prior) == 1L)
stopifnot(isTRUE(all.equal(
  fit_hybrid_reference$variational_state$prior$prior_precision[[fixed_index_core]],
  400
)))

checkpoint_dir_hybrid <- tempfile("glofas_context_prior_checkpoint_")
dir.create(checkpoint_dir_hybrid, recursive = TRUE)
checkpoint_path_hybrid <- file.path(checkpoint_dir_hybrid, "hybrid.rds")
vb_hybrid_stop <- vb_hybrid_core
vb_hybrid_stop$checkpoint <- list(
  enabled = TRUE,
  resume = FALSE,
  path = checkpoint_path_hybrid,
  every_iterations = 1L,
  every_minutes = Inf,
  keep_previous = TRUE,
  keep_on_success = TRUE,
  compress = FALSE
)
vb_hybrid_stop$diagnostics$stop_after_iteration <- 2L
controlled_hybrid_stop <- tryCatch(
  app_fit_latent_path_al_vb_core(
    design_hybrid_core,
    p0 = sim_hybrid_core$p0,
    coefficient_prior = "rhs_ns",
    vb_args = vb_hybrid_stop,
    seed = sim_hybrid_core$seed
  ),
  latent_path_checkpoint_stop = function(e) e
)
stopifnot(inherits(controlled_hybrid_stop, "latent_path_checkpoint_stop"))
vb_hybrid_resume <- vb_hybrid_core
vb_hybrid_resume$checkpoint <- modifyList(
  vb_hybrid_stop$checkpoint,
  list(resume = TRUE)
)
fit_hybrid_resumed <- app_fit_latent_path_al_vb_core(
  design_hybrid_core,
  p0 = sim_hybrid_core$p0,
  coefficient_prior = "rhs_ns",
  vb_args = vb_hybrid_resume,
  seed = sim_hybrid_core$seed
)
stopifnot(isTRUE(fit_hybrid_resumed$vb_diagnostics$checkpoint$resumed))
stopifnot(max(abs(
  fit_hybrid_reference$summary$theta_mean -
    fit_hybrid_resumed$summary$theta_mean
)) < 1.0e-12)
stopifnot(max(abs(
  fit_hybrid_reference$summary$y_future_mean -
    fit_hybrid_resumed$summary$y_future_mean
)) < 1.0e-12)
unlink(checkpoint_dir_hybrid, recursive = TRUE)

x <- c(-2, -0.5, 0, 0.5, 2)
coefficient <- 0.3
scale <- 0.2
stopifnot(isTRUE(all.equal(x * coefficient, (x * scale) * (coefficient / scale))))

identity_scores <- app_glofas_transition_metric_row(
  candidate_id = "fixture",
  cutoff_id = "fixture",
  selection_role = "primary_v31",
  y = c(1, 2),
  q_y = c(1.1, 2.1),
  raw_q_g = c(1.5, 2.5),
  d_hat = c(0.4, 0.4),
  q_g_hat = c(1.5, 2.5)
)
stopifnot(identity_scores$reconstruction_identity_max_abs[[1L]] < 1.0e-12)

cat("GloFAS context-prior repair tests passed.\n")
