# Frozen candidate construction for the discrepancy-first GloFAS p50 campaign.

app_glofas_richer_geometry <- function(D, n, m, fan_in_target = 16, alpha = 0.075,
                                       rho = 0.95, tau0 = 1e-4, role = "geometry") {
  D <- as.integer(D)
  list(
    role = role, D = D, n = as.integer(n),
    n_tilde = if (D > 1L) as.integer(n) else NULL,
    m = as.integer(m), fan_in_target = as.numeric(fan_in_target),
    alpha = as.numeric(alpha), rho = as.numeric(rho), tau0 = as.numeric(tau0)
  )
}

app_glofas_richer_initial_geometries <- function() {
  specs <- list(
    c(2, 200, 720), c(2, 400, 1080), c(3, 200, 720), c(3, 300, 1080),
    c(4, 100, 720), c(4, 150, 720), c(4, 200, 1080), c(4, 300, 1440),
    c(8, 75, 720), c(8, 100, 1080), c(8, 125, 1440),
    c(16, 64, 1080), c(16, 96, 1440), c(32, 40, 1080), c(32, 50, 1440)
  )
  lapply(specs, function(x) app_glofas_richer_geometry(x[[1L]], x[[2L]], x[[3L]]))
}

app_glofas_richer_candidate <- function(id, geometry, warm = "cold") {
  discrepancy <- list(
    D = geometry$D, n = geometry$n, m = geometry$m,
    reservoir_output_lag_max = geometry$m,
    reservoir_covariate_lag_max = geometry$m,
    alpha = geometry$alpha, rho = geometry$rho,
    fan_in_target = geometry$fan_in_target,
    rhs_tau0 = geometry$tau0
  )
  if (geometry$D > 1L) discrepancy$n_tilde <- geometry$n_tilde
  list(
    set_id = "richer_discrepancy_initial",
    candidate_label = id,
    parameters = list(discrepancy = discrepancy),
    metadata = list(candidate_role = geometry$role, warm_start_policy = warm)
  )
}

app_glofas_richer_initial_candidates <- function() {
  controls <- list(
    app_glofas_richer_candidate(
      "cold_fr09_control",
      app_glofas_richer_geometry(1, 300, 360, fan_in_target = 1082, alpha = 0.1,
        rho = 0.95, tau0 = 1e-3, role = "cold_fr09_control")
    ),
    app_glofas_richer_candidate(
      "cold_d2_anchor",
      app_glofas_richer_geometry(2, 200, 720, fan_in_target = 2162, alpha = 0.075,
        rho = 0.95, tau0 = 1e-4, role = "cold_d2_anchor")
    )
  )
  centers <- Map(function(g, i) {
    app_glofas_richer_candidate(sprintf("geometry_%02d", i), g)
  }, app_glofas_richer_initial_geometries(), seq_len(15L))
  low_alpha_indices <- c(8L, 11L, 13L, 15L)
  low_alpha <- Map(function(g, i) {
    g$alpha <- 0.025
    g$role <- "low_alpha_health_canary"
    app_glofas_richer_candidate(sprintf("low_alpha_%02d", i), g)
  }, app_glofas_richer_initial_geometries()[low_alpha_indices], low_alpha_indices)
  c(controls, centers, low_alpha)
}

app_glofas_richer_screen_space <- function(screen_id, output_root, cores) {
  candidates <- app_glofas_richer_initial_candidates()
  list(
    version = "2.0", screen_id = screen_id, launch_authorized = TRUE,
    output_root = output_root,
    base = list(
      baseline_contract = "application/config/glofas_constrained_median_baseline_fr09.yaml",
      candidate_id = "fr09_persistence_innovation"
    ),
    fixed = list(
      quantile_level = 0.5,
      inference = list(max_iter = 150L, max_iter_hard_cap = 150L, min_iter_elbo = 20L,
        tol = 1e-4, tol_par = 1e-4, n_draws = 2000L, n_samp_xi = 500L,
        rhs_freeze_tau_warmup_iters = 50L, rhs_update_every = 1L, rhs_min_tau_updates = 1L),
      parameters = list(
        reference = list(washout = 500L, pi_w = 0.03, pi_in = 1,
          win_scale_global = 0.18, win_scale_bias = 0.18, seed = 20260512L,
          include_input_block = TRUE),
        discrepancy = list(washout = 500L, pi_w = 0.03,
          win_scale_global = 0.18, win_scale_bias = 0.18, seed = 20261521L,
          direct_output_lag_max = 180L, direct_covariate_lag_max = 180L,
          include_input_block = TRUE)
      )
    ),
    explicit_candidates = candidates,
    selection = list(
      require_vb_converged = FALSE,
      policy = list(max_observed_ratio_all = 1.03, max_observed_ratio_last1000 = 1.03,
        max_observed_ratio_last200 = 1.05, max_observed_ratio_last50 = 1.10,
        last50_is_hard_gate = TRUE, min_forecast_improvement_fraction = 0.05)
    ),
    confirmation = list(require_cold_p50_refit_for_transferred_state = TRUE,
      require_full7_before_promotion = TRUE, auto_launch_full7 = FALSE),
    contracts = list(require_same_desn_by_default = FALSE),
    reservoir_preflight = list(enabled = TRUE, diagnostic_target = "reservoir",
      reject_decision = "reject", max_corr_features_full = 5000L,
      corr_block_size = 512L, spectral_radius_exact_max_n = 512L, cheap_validation = FALSE),
    finalization = list(run_after_scheduler = TRUE, cleanup_after_complete_batch = TRUE),
    execution = list(expected_candidates = length(candidates), max_candidates = length(candidates)),
    scheduler = list(max_parallel = 20L, cores = as.integer(cores), max_load = 63,
      min_memory_gb = 96, min_disk_gb = 150)
  )
}
