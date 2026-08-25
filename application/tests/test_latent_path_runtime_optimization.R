# Exact runtime controls must preserve the latent-path scientific state.

runtime_manifest_unit <- app_latent_runtime_backend_manifest(fail_closed = TRUE)
stopifnot(nrow(runtime_manifest_unit) == 1L)
stopifnot(identical(runtime_manifest_unit$backend[[1L]], "bundled_rblas"))
stopifnot(isTRUE(runtime_manifest_unit$backend_verified[[1L]]))
stopifnot(nzchar(app_latent_runtime_backend_fingerprint()))
stopifnot(nzchar(runtime_manifest_unit$engine_source_hash[[1L]]))
stopifnot(nzchar(runtime_manifest_unit$source_head[[1L]]))
stopifnot(nzchar(runtime_manifest_unit$source_commit_tree[[1L]]))
stopifnot(identical(
  app_latent_checkpoint_config(list())$every_iterations,
  100L
))
stopifnot(identical(
  app_latent_checkpoint_config(list(checkpoint = list(every_iterations = 0)))$every_iterations,
  100L
))

cfg_checkpoint_unit <- list(
  inference = list(
    vb_ld = list(
      max_iter = 6L,
      min_iter_elbo = 1L,
      tol = 1.0e-4,
      n_draws = 8L,
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
    horizon = 3L,
    n_members = 5L,
    seed = 20260824L,
    p0 = 0.5
  ),
  reservoir = list(seed = 20260824L)
)

sim_checkpoint_unit <- app_latent_path_recovery_simulate(cfg_checkpoint_unit)
design_checkpoint_unit <- app_make_latent_path_recovery_design(
  sim_checkpoint_unit,
  cfg_checkpoint_unit
)
design_checkpoint_paired <- design_checkpoint_unit
design_checkpoint_paired$X_beta_stack <- rbind(
  design_checkpoint_paired$X_beta,
  design_checkpoint_paired$X_beta
)
design_checkpoint_paired$X_alpha_stack <- rbind(
  design_checkpoint_paired$X_alpha,
  design_checkpoint_paired$X_alpha
)
design_checkpoint_paired$fixed_pairing_certificate <- app_latent_pairing_certificate(
  X_beta_stack = design_checkpoint_paired$X_beta_stack,
  source = design_checkpoint_paired$source_fixed,
  beta_index = design_checkpoint_paired$beta_index,
  alpha_index = design_checkpoint_paired$alpha_index,
  feature_names = colnames(design_checkpoint_paired$H_fixed)
)
stopifnot(isTRUE(design_checkpoint_paired$fixed_pairing_certificate$paired_beta_rows))
paired_block_unit <- app_latent_fixed_block_design(
  design = design_checkpoint_paired,
  verify_dense = FALSE
)
stopifnot(app_latent_pairing_certificate_matches_block(
  design_checkpoint_paired$fixed_pairing_certificate,
  paired_block_unit
))
corrupt_certificate_unit <- design_checkpoint_paired$fixed_pairing_certificate
corrupt_certificate_unit$n_y <- corrupt_certificate_unit$n_y + 1L
paired_block_corrupt_unit <- paired_block_unit
paired_block_corrupt_unit$pairing_certificate <- corrupt_certificate_unit
stopifnot(!app_latent_pairing_certificate_valid(
  corrupt_certificate_unit,
  block = paired_block_unit
))
stopifnot(!app_latent_fixed_block_has_paired_beta_rows(
  paired_block_corrupt_unit
))
stale_pairing_block_unit <- paired_block_unit
stale_pairing_block_unit$X_beta_stack[
  stale_pairing_block_unit$g_index[[1L]], 1L
] <- stale_pairing_block_unit$X_beta_stack[
  stale_pairing_block_unit$g_index[[1L]], 1L
] + 1
stopifnot(!app_latent_pairing_certificate_matches_block(
  design_checkpoint_paired$fixed_pairing_certificate,
  stale_pairing_block_unit
))
design_checkpoint_unfused <- design_checkpoint_paired
design_checkpoint_unfused$fixed_pairing_certificate <- app_latent_pairing_certificate(
  X_beta_stack = design_checkpoint_unfused$X_beta_stack,
  source = design_checkpoint_unfused$source_fixed,
  beta_index = design_checkpoint_unfused$beta_index,
  alpha_index = design_checkpoint_unfused$alpha_index,
  feature_names = colnames(design_checkpoint_unfused$H_fixed),
  optimization_enabled = FALSE
)
stopifnot(!app_latent_fixed_block_has_paired_beta_rows(
  app_latent_fixed_block_design(design = design_checkpoint_unfused)
))

paired_future_design_unit <- design_checkpoint_paired
paired_future_builder_unit <- paired_future_design_unit$future_builder
paired_future_design_unit$future_builder <- function(y_future) {
  out <- paired_future_builder_unit(y_future)
  out$J_g_key <- lapply(out$J_y, identity)
  out$J_g <- lapply(out$g_future_index, function(h) out$J_g_key[[h]])
  out$paired_future_jacobian <- TRUE
  out
}
fallback_future_design_unit <- paired_future_design_unit
fallback_future_builder_unit <- fallback_future_design_unit$future_builder
fallback_future_design_unit$future_builder <- function(y_future) {
  out <- fallback_future_builder_unit(y_future)
  out$paired_future_jacobian <- FALSE
  out
}
p_checkpoint_unit <- ncol(design_checkpoint_paired$H_fixed)
theta_mean_pair_unit <- seq_len(p_checkpoint_unit) / (10 * p_checkpoint_unit)
theta_cov_pair_unit <- diag(seq(0.1, 0.2, length.out = p_checkpoint_unit))
y_mean_pair_unit <- as.numeric(design_checkpoint_paired$y_future_init)
y_cov_pair_unit <- diag(seq(0.05, 0.08, length.out = length(y_mean_pair_unit)))
moments_paired_future_unit <- app_latent_row_moments(
  paired_future_design_unit,
  y_mean_pair_unit,
  y_cov_pair_unit,
  theta_mean_pair_unit,
  theta_cov_pair_unit,
  strategy = "streamed_grouped"
)
moments_fallback_future_unit <- app_latent_row_moments(
  fallback_future_design_unit,
  y_mean_pair_unit,
  y_cov_pair_unit,
  theta_mean_pair_unit,
  theta_cov_pair_unit,
  strategy = "streamed_grouped"
)
stopifnot(isTRUE(moments_paired_future_unit$future$paired_future_jacobian))
stopifnot(!isTRUE(moments_fallback_future_unit$future$paired_future_jacobian))
stopifnot(max(abs(
  app_latent_all_R(moments_paired_future_unit) -
    app_latent_all_R(moments_fallback_future_unit)
)) < 1.0e-12)
stopifnot(max(abs(
  app_latent_all_e(moments_paired_future_unit) -
    app_latent_all_e(moments_fallback_future_unit)
)) < 1.0e-12)

constants_pair_unit <- app_latent_al_constants(0.5)
sigma_pair_unit <- app_latent_source_sigma_init(
  moments_paired_future_unit$source,
  list(a = 2, b = 1)
)
e_inv_pair_unit <- seq(0.9, 1.1, length.out = length(moments_paired_future_unit$source))
prior_pair_unit <- app_latent_prior_state_init(
  p = p_checkpoint_unit,
  prior = "ridge",
  intercept_index = design_checkpoint_paired$intercept_index,
  vb_args = list(
    beta_ridge = list(precision = 0.7),
    beta_rhs = list(intercept_prec = 1.0e-9)
  )
)
theta_paired_future_unit <- app_latent_update_theta(
  moments_paired_future_unit,
  e_inv_pair_unit,
  sigma_pair_unit,
  constants_pair_unit,
  prior_pair_unit
)
theta_fallback_future_unit <- app_latent_update_theta(
  moments_fallback_future_unit,
  e_inv_pair_unit,
  sigma_pair_unit,
  constants_pair_unit,
  prior_pair_unit
)
stopifnot(max(abs(
  theta_paired_future_unit$precision - theta_fallback_future_unit$precision
)) < 1.0e-12)
stopifnot(max(abs(
  as.numeric(theta_paired_future_unit$precision %*% theta_paired_future_unit$mean) -
    as.numeric(theta_fallback_future_unit$precision %*% theta_fallback_future_unit$mean)
)) < 1.0e-12)
stopifnot(max(abs(
  theta_paired_future_unit$mean - theta_fallback_future_unit$mean
)) < 1.0e-12)
stopifnot(max(abs(
  theta_paired_future_unit$cov - theta_fallback_future_unit$cov
)) < 1.0e-12)

legacy_hash_unit <- app_hash_latent_path_design(design_checkpoint_paired)
compact_design_unit <- app_latent_path_drop_runtime_cache(
  design_checkpoint_paired,
  compact = TRUE
)
stopifnot(is.null(compact_design_unit$X_beta_stack))
stopifnot(is.null(compact_design_unit$X_alpha_stack))
stopifnot(identical(
  compact_design_unit$serialization_contract$schema_version,
  "glofas_latent_path_compact_v2"
))
stopifnot(identical(
  compact_design_unit$serialization_contract$semantic_design_hash,
  legacy_hash_unit
))
stopifnot(identical(app_hash_latent_path_design(compact_design_unit), legacy_hash_unit))
restored_design_unit <- app_latent_path_restore_legacy_view(compact_design_unit)
stopifnot(identical(restored_design_unit$X_base, design_checkpoint_paired$X_base))
stopifnot(identical(
  restored_design_unit$feature_meta,
  design_checkpoint_paired$feature_meta
))
stopifnot(identical(
  restored_design_unit$feature_info,
  design_checkpoint_paired$feature_info
))
stopifnot(identical(
  unname(restored_design_unit$X_beta_stack),
  unname(design_checkpoint_paired$X_beta_stack)
))
stopifnot(identical(
  unname(restored_design_unit$X_alpha_stack),
  unname(design_checkpoint_paired$X_alpha_stack)
))

vb_checkpoint_base <- app_make_qdesn_discrepancy_vb_args(
  cfg_checkpoint_unit,
  prior = "rhs_ns",
  seed = sim_checkpoint_unit$seed,
  likelihood_family = "al"
)
vb_checkpoint_base$diagnostics <- modifyList(
  vb_checkpoint_base$diagnostics %||% list(),
  list(fixed_iterations = TRUE, profile_substeps = TRUE)
)

fit_checkpoint_reference <- app_fit_latent_path_al_vb_core(
  design = design_checkpoint_unit,
  p0 = sim_checkpoint_unit$p0,
  coefficient_prior = "rhs_ns",
  vb_args = vb_checkpoint_base,
  seed = sim_checkpoint_unit$seed
)
stopifnot(identical(fit_checkpoint_reference$vb_diagnostics$iterations, 6L))
stopifnot(!isTRUE(fit_checkpoint_reference$vb_diagnostics$converged))
fit_checkpoint_paired <- app_fit_latent_path_al_vb_core(
  design = design_checkpoint_paired,
  p0 = sim_checkpoint_unit$p0,
  coefficient_prior = "rhs_ns",
  vb_args = vb_checkpoint_base,
  seed = sim_checkpoint_unit$seed
)
fit_checkpoint_compact <- app_fit_latent_path_al_vb_core(
  design = compact_design_unit,
  p0 = sim_checkpoint_unit$p0,
  coefficient_prior = "rhs_ns",
  vb_args = vb_checkpoint_base,
  seed = sim_checkpoint_unit$seed
)
stopifnot(max(abs(
  fit_checkpoint_reference$summary$theta_mean - fit_checkpoint_paired$summary$theta_mean
)) < 1.0e-10)
stopifnot(max(abs(
  fit_checkpoint_reference$summary$theta_cov - fit_checkpoint_paired$summary$theta_cov
)) < 1.0e-10)
stopifnot(identical(
  fit_checkpoint_paired$vb_diagnostics$elbo_trace,
  fit_checkpoint_compact$vb_diagnostics$elbo_trace
))
stopifnot(identical(
  fit_checkpoint_paired$vb_diagnostics$parameter_change_trace,
  fit_checkpoint_compact$vb_diagnostics$parameter_change_trace
))
stopifnot(max(abs(
  fit_checkpoint_paired$summary$theta_mean - fit_checkpoint_compact$summary$theta_mean
)) < 1.0e-12)
stopifnot(max(abs(
  fit_checkpoint_paired$summary$theta_cov - fit_checkpoint_compact$summary$theta_cov
)) < 1.0e-12)
stopifnot(max(abs(
  fit_checkpoint_paired$summary$y_future_mean -
    fit_checkpoint_compact$summary$y_future_mean
)) < 1.0e-12)
paired_steps_unit <- fit_checkpoint_paired$vb_diagnostics$substep_timing$step
stopifnot(any(grepl("fixed_theta_paired_beta_fused", paired_steps_unit, fixed = TRUE)))

checkpoint_dir_unit <- tempfile("latent_checkpoint_unit_")
dir.create(checkpoint_dir_unit, recursive = TRUE)
checkpoint_path_unit <- file.path(checkpoint_dir_unit, "fit.checkpoint.rds")
vb_checkpoint_stop <- vb_checkpoint_base
vb_checkpoint_stop$checkpoint <- list(
  enabled = TRUE,
  resume = FALSE,
  path = checkpoint_path_unit,
  every_iterations = 2L,
  every_minutes = Inf,
  keep_previous = TRUE,
  keep_on_success = TRUE,
  compress = FALSE
)
vb_checkpoint_stop$diagnostics$stop_after_iteration <- 3L

controlled_stop_unit <- tryCatch(
  {
    app_fit_latent_path_al_vb_core(
      design = design_checkpoint_unit,
      p0 = sim_checkpoint_unit$p0,
      coefficient_prior = "rhs_ns",
      vb_args = vb_checkpoint_stop,
      seed = sim_checkpoint_unit$seed
    )
    NULL
  },
  latent_path_checkpoint_stop = function(e) e
)
stopifnot(inherits(controlled_stop_unit, "latent_path_checkpoint_stop"))
stopifnot(identical(controlled_stop_unit$iteration, 3L))
stopifnot(file.exists(checkpoint_path_unit))
stopifnot(file.exists(app_latent_checkpoint_hash_path(checkpoint_path_unit)))

vb_checkpoint_resume <- vb_checkpoint_base
vb_checkpoint_resume$checkpoint <- modifyList(
  vb_checkpoint_stop$checkpoint,
  list(resume = TRUE)
)
fit_checkpoint_resumed <- app_fit_latent_path_al_vb_core(
  design = design_checkpoint_unit,
  p0 = sim_checkpoint_unit$p0,
  coefficient_prior = "rhs_ns",
  vb_args = vb_checkpoint_resume,
  seed = sim_checkpoint_unit$seed
)
stopifnot(isTRUE(fit_checkpoint_resumed$vb_diagnostics$checkpoint$resumed))
stopifnot(identical(fit_checkpoint_resumed$vb_diagnostics$checkpoint$iteration_loaded, 3L))
stopifnot(identical(
  fit_checkpoint_reference$vb_diagnostics$elbo_trace,
  fit_checkpoint_resumed$vb_diagnostics$elbo_trace
))
stopifnot(identical(
  fit_checkpoint_reference$vb_diagnostics$parameter_change_trace,
  fit_checkpoint_resumed$vb_diagnostics$parameter_change_trace
))
stopifnot(max(abs(
  fit_checkpoint_reference$summary$theta_mean - fit_checkpoint_resumed$summary$theta_mean
)) < 1.0e-12)
stopifnot(max(abs(
  fit_checkpoint_reference$summary$theta_cov - fit_checkpoint_resumed$summary$theta_cov
)) < 1.0e-12)
stopifnot(max(abs(
  fit_checkpoint_reference$summary$y_future_mean - fit_checkpoint_resumed$summary$y_future_mean
)) < 1.0e-12)
stopifnot(all(vapply(
  names(fit_checkpoint_reference$draws),
  function(name) identical(
    as.numeric(fit_checkpoint_reference$draws[[name]]),
    as.numeric(fit_checkpoint_resumed$draws[[name]])
  ),
  logical(1L)
)))

valid_checkpoint_unit <- app_latent_checkpoint_read(checkpoint_path_unit)
contract_checkpoint_unit <- valid_checkpoint_unit$contract
writeBin(charToRaw("truncated checkpoint"), checkpoint_path_unit)
recovered_checkpoint_unit <- app_latent_checkpoint_read(
  checkpoint_path_unit,
  expected_contract = contract_checkpoint_unit,
  allow_previous = TRUE
)
stopifnot(isTRUE(attr(
  recovered_checkpoint_unit,
  "checkpoint_recovered_previous",
  exact = TRUE
)))

wrong_contract_unit <- contract_checkpoint_unit
wrong_contract_unit$contract_hash <- paste0(contract_checkpoint_unit$contract_hash, "_wrong")
wrong_contract_error_unit <- tryCatch(
  {
    app_latent_checkpoint_read(
      checkpoint_path_unit,
      expected_contract = wrong_contract_unit,
      allow_previous = TRUE
    )
    NULL
  },
  error = function(e) e
)
stopifnot(inherits(wrong_contract_error_unit, "error"))

app_latent_checkpoint_remove(checkpoint_path_unit)
stopifnot(!any(file.exists(c(
  checkpoint_path_unit,
  app_latent_checkpoint_hash_path(checkpoint_path_unit),
  paste0(checkpoint_path_unit, ".previous"),
  app_latent_checkpoint_hash_path(paste0(checkpoint_path_unit, ".previous"))
))))
unlink(checkpoint_dir_unit, recursive = TRUE)

reference_cache_env_dir_unit <- tempfile("latent_reference_cache_env_unit_")
dir.create(reference_cache_env_dir_unit, recursive = TRUE)
reference_cache_env_old_unit <- Sys.getenv(
  "QDESN_REFERENCE_FEATURE_CACHE_ROOT",
  unset = NA_character_
)
Sys.setenv(QDESN_REFERENCE_FEATURE_CACHE_ROOT = reference_cache_env_dir_unit)
reference_cache_env_cfg_unit <- app_latent_reference_feature_cache_config(list(
  runtime_optimization = list(reference_feature_cache = list(root = ""))
))
stopifnot(isTRUE(reference_cache_env_cfg_unit$enabled))
stopifnot(identical(
  reference_cache_env_cfg_unit$root,
  normalizePath(reference_cache_env_dir_unit, mustWork = TRUE)
))
if (is.na(reference_cache_env_old_unit)) {
  Sys.unsetenv("QDESN_REFERENCE_FEATURE_CACHE_ROOT")
} else {
  Sys.setenv(QDESN_REFERENCE_FEATURE_CACHE_ROOT = reference_cache_env_old_unit)
}
unlink(reference_cache_env_dir_unit, recursive = TRUE)

reference_cache_dir_unit <- tempfile("latent_reference_cache_unit_")
dir.create(reference_cache_dir_unit, recursive = TRUE)
reference_cache_cfg_unit <- list(
  enabled = TRUE,
  root = reference_cache_dir_unit,
  wait_seconds = 0.05,
  poll_seconds = 0.01,
  schema_version = "glofas_reference_feature_cache_v1"
)
reference_cache_contract_unit <- list(
  contract_hash = app_latent_path_contract_hash(
    list(panel = "unit", seed = 1L),
    prefix = "reference_cache_unit_"
  )
)
reference_cache_builds_unit <- 0L
reference_cache_builder_unit <- function() {
  reference_cache_builds_unit <<- reference_cache_builds_unit + 1L
  list(feature = list(X = diag(2L)), qfit = list(seed = 1L))
}
reference_cache_first_unit <- app_latent_reference_feature_cache_get_or_build(
  reference_cache_cfg_unit,
  reference_cache_contract_unit,
  reference_cache_builder_unit
)
reference_cache_second_unit <- app_latent_reference_feature_cache_get_or_build(
  reference_cache_cfg_unit,
  reference_cache_contract_unit,
  reference_cache_builder_unit
)
stopifnot(identical(reference_cache_builds_unit, 1L))
stopifnot(!isTRUE(reference_cache_first_unit$diagnostics$hit))
stopifnot(isTRUE(reference_cache_second_unit$diagnostics$hit))
stopifnot(identical(
  reference_cache_first_unit$beta_block,
  reference_cache_second_unit$beta_block
))
reference_cache_changed_contract_unit <- list(
  contract_hash = app_latent_path_contract_hash(
    list(panel = "unit", seed = 2L),
    prefix = "reference_cache_unit_"
  )
)
reference_cache_changed_unit <- app_latent_reference_feature_cache_get_or_build(
  reference_cache_cfg_unit,
  reference_cache_changed_contract_unit,
  reference_cache_builder_unit
)
stopifnot(identical(reference_cache_builds_unit, 2L))
stopifnot(!isTRUE(reference_cache_changed_unit$diagnostics$hit))
stopifnot(!identical(
  reference_cache_changed_unit$diagnostics$contract_hash,
  reference_cache_second_unit$diagnostics$contract_hash
))
reference_cache_path_unit <- app_latent_reference_feature_cache_path(
  reference_cache_cfg_unit,
  reference_cache_contract_unit
)
writeBin(charToRaw("corrupt"), reference_cache_path_unit)
reference_cache_corrupt_error_unit <- tryCatch(
  {
    app_latent_reference_feature_cache_read(
      reference_cache_path_unit,
      reference_cache_contract_unit
    )
    NULL
  },
  error = function(e) e
)
stopifnot(inherits(reference_cache_corrupt_error_unit, "error"))
unlink(c(reference_cache_path_unit, paste0(reference_cache_path_unit, ".sha256")), force = TRUE)
dir.create(paste0(reference_cache_path_unit, ".lock"))
reference_cache_lock_error_unit <- tryCatch(
  {
    app_latent_reference_feature_cache_get_or_build(
      reference_cache_cfg_unit,
      reference_cache_contract_unit,
      reference_cache_builder_unit
    )
    NULL
  },
  error = function(e) e
)
stopifnot(inherits(reference_cache_lock_error_unit, "error"))
stopifnot(grepl("Timed out", conditionMessage(reference_cache_lock_error_unit), fixed = TRUE))
unlink(reference_cache_dir_unit, recursive = TRUE)
