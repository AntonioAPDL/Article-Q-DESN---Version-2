# Phase136 matched exAL gamma-kernel packet.

app_joint_exqdesn_phase136_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase136_exal_gamma_kernel_packet_20260715")
}

app_joint_exqdesn_phase136_default_phase135_screening_dir <- function() {
  app_path("application/cache/joint_qdesn_phase135_matched_exal_screening_20260715")
}

app_joint_exqdesn_phase136_default_phase135_audit_dir <- function() {
  file.path(app_joint_exqdesn_phase136_default_phase135_screening_dir(), "phase135_result_audit")
}

app_joint_exqdesn_phase136_default_fixture_dir <- function() {
  app_joint_qdesn_default_simulation_fixture_dir()
}

app_joint_exqdesn_phase136_default_case_ids <- function() {
  c(
    "nonlinear_reservoir_friendly__joint_exqdesn_rhs_vb",
    "nonlinear_reservoir_friendly__exqdesn_rhs_independent_vb",
    "student_t_location_scale__joint_exqdesn_rhs_vb",
    "regime_shift__joint_exqdesn_rhs_vb",
    "laplace_bridge__joint_exqdesn_rhs_vb"
  )
}

app_joint_exqdesn_phase136_load_phase135 <- function(phase135_screening_dir, phase135_audit_dir = NULL) {
  phase135_screening_dir <- normalizePath(phase135_screening_dir, mustWork = TRUE)
  phase135_audit_dir <- normalizePath(phase135_audit_dir %||% file.path(phase135_screening_dir, "phase135_result_audit"), mustWork = TRUE)
  required_screen <- c("candidate_registry.csv", "artifact_manifest.csv")
  required_audit <- c(
    "phase135_matched_exal_vs_source_al_vb_comparison.csv",
    "phase135_result_decision.csv",
    "artifact_manifest.csv"
  )
  missing <- c(
    file.path(phase135_screening_dir, required_screen)[!file.exists(file.path(phase135_screening_dir, required_screen))],
    file.path(phase135_audit_dir, required_audit)[!file.exists(file.path(phase135_audit_dir, required_audit))]
  )
  if (length(missing)) {
    stop(sprintf("Phase135 source is missing required files: %s", paste(basename(missing), collapse = ", ")), call. = FALSE)
  }
  screen_manifest <- app_joint_qdesn_phase108_manifest_verify(phase135_screening_dir, "phase135_matched_exal_screening")
  audit_manifest <- app_joint_qdesn_phase108_manifest_verify(phase135_audit_dir, "phase135_result_audit")
  if (any(screen_manifest$status != "pass")) stop("Phase135 screening manifest verification failed.", call. = FALSE)
  if (any(audit_manifest$status != "pass")) stop("Phase135 audit manifest verification failed.", call. = FALSE)
  list(
    screening_dir = phase135_screening_dir,
    audit_dir = phase135_audit_dir,
    screen_manifest = screen_manifest,
    audit_manifest = audit_manifest,
    registry = app_read_csv(file.path(phase135_screening_dir, "candidate_registry.csv")),
    comparison = app_read_csv(file.path(phase135_audit_dir, "phase135_matched_exal_vs_source_al_vb_comparison.csv")),
    decision = app_read_csv(file.path(phase135_audit_dir, "phase135_result_decision.csv"))
  )
}

app_joint_exqdesn_phase136_select_cases <- function(phase135, case_ids = NULL, case_limit = NULL) {
  registry <- phase135$registry
  comparison <- phase135$comparison
  registry <- registry[registry$model_ids %in% c("joint_exqdesn_rhs_vb", "exqdesn_rhs_independent_vb"), , drop = FALSE]
  if (!nrow(registry)) stop("Phase135 registry has no exAL candidate rows.", call. = FALSE)
  registry$case_id <- as.character(registry$case_id)
  default_ids <- app_joint_exqdesn_phase136_default_case_ids()
  if (is.null(case_ids) || !length(case_ids)) case_ids <- default_ids
  selected <- registry[registry$case_id %in% case_ids, , drop = FALSE]
  if (!nrow(selected)) stop("No Phase136 case rows selected.", call. = FALSE)
  selected$phase136_priority_rank <- match(selected$case_id, case_ids)
  selected <- selected[order(selected$phase136_priority_rank, selected$case_id), , drop = FALSE]
  if (!is.null(case_limit) && is.finite(case_limit) && case_limit > 0L) {
    selected <- head(selected, as.integer(case_limit))
  }
  selected$phase136_selection_reason <- "high_phase135_matched_exal_gap_first_wave"
  selected$phase136_source_gap_rank <- NA_integer_
  selected$phase136_phase135_forecast_delta_exal_minus_al <- NA_real_
  selected$phase136_phase135_fit_delta_exal_minus_al <- NA_real_
  for (ii in seq_len(nrow(selected))) {
    comp <- comparison[
      comparison$scenario_id == selected$scenario_ids[[ii]] &
        comparison$target_exal_model_id == selected$model_ids[[ii]],
      ,
      drop = FALSE
    ]
    if (nrow(comp)) {
      selected$phase136_phase135_forecast_delta_exal_minus_al[[ii]] <- comp$forecast_delta_exal_minus_al[[1L]]
      selected$phase136_phase135_fit_delta_exal_minus_al[[ii]] <- comp$fit_delta_exal_minus_al[[1L]]
      selected$phase136_source_gap_rank[[ii]] <- match(
        paste(comp$scenario_id[[1L]], comp$target_exal_model_id[[1L]], sep = "||"),
        paste(comparison$scenario_id[order(-comparison$forecast_delta_exal_minus_al)],
              comparison$target_exal_model_id[order(-comparison$forecast_delta_exal_minus_al)],
              sep = "||")
      )
    }
  }
  selected
}

app_joint_exqdesn_phase136_variant_registry <- function(selected_cases, variant_ids = c("bounded_w4", "logit_w4"),
                                                        bounded_width_multiplier = 4, logit_eta_width = 4,
                                                        gamma_slice_max_steps = 100L) {
  variant_ids <- as.character(variant_ids)
  variant_ids <- variant_ids[nzchar(variant_ids)]
  if (!length(variant_ids)) stop("At least one Phase136 variant is required.", call. = FALSE)
  rows <- list()
  for (ii in seq_len(nrow(selected_cases))) {
    row <- selected_cases[ii, , drop = FALSE]
    for (variant in variant_ids) {
      gamma_update <- switch(
        variant,
        bounded_w4 = "bounded_slice",
        logit_w4 = "logit_slice",
        fixed_zero = "fixed",
        stop(sprintf("Unknown Phase136 variant_id '%s'.", variant), call. = FALSE)
      )
      rows[[length(rows) + 1L]] <- cbind(
        row,
        data.frame(
          phase136_variant_id = variant,
          gamma_update = gamma_update,
          bounded_width_multiplier = if (identical(gamma_update, "bounded_slice")) bounded_width_multiplier else NA_real_,
          logit_eta_width = if (identical(gamma_update, "logit_slice")) logit_eta_width else NA_real_,
          gamma_slice_max_steps = as.integer(gamma_slice_max_steps),
          phase136_variant_role = if (identical(gamma_update, "bounded_slice")) {
            "existing_gamma_slice_width4_reference"
          } else if (identical(gamma_update, "fixed")) {
            "fixed_gamma_zero_near_al_sensitivity"
          } else {
            "logit_gamma_slice_geometry_test"
          },
          stringsAsFactors = FALSE
        )
      )
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  out$phase136_case_variant_id <- paste(out$case_id, out$phase136_variant_id, sep = "__")
  out
}

app_joint_exqdesn_phase136_width_vector <- function(tau, gamma_update, bounded_width_multiplier, logit_eta_width) {
  support <- app_joint_qvp_exal_support(tau)
  if (identical(gamma_update, "fixed")) {
    rep(1, length(tau))
  } else if (identical(gamma_update, "logit_slice")) {
    rep(as.numeric(logit_eta_width), length(tau))
  } else {
    (as.numeric(support$upper) - as.numeric(support$lower)) / 20 * as.numeric(bounded_width_multiplier)
  }
}

app_joint_exqdesn_phase136_chain_init_for_gamma_update <- function(vb_fit, tau, controls,
                                                                   chain_id, n_chains,
                                                                   gamma_update,
                                                                   mode = "vb_jittered",
                                                                   jitter_fraction = 0.10) {
  if (identical(gamma_update, "fixed")) {
    init <- vb_fit
    gamma <- app_joint_qdesn_gamma_init_for_policy(tau, controls)
    if (is.null(gamma)) gamma <- rep(0, length(app_joint_qvp_validate_tau_grid(tau)))
    gamma <- app_joint_qvp_check_gamma(tau, gamma)
    init$gamma_mean <- gamma
    init$gamma <- gamma
    return(init)
  }
  app_joint_exqdesn_gamma_chain_init(
    vb_fit = vb_fit,
    tau = tau,
    chain_id = chain_id,
    n_chains = n_chains,
    mode = mode,
    jitter_fraction = jitter_fraction
  )
}

app_joint_exqdesn_phase136_fit_vb_case <- function(fixture, spec, controls) {
  if (identical(spec$model_id[[1L]], "joint_exqdesn_rhs_vb")) {
    retained <- app_joint_exqdesn_fit_with_retained_init(fixture, controls)
    return(list(
      vb_fit = retained$vb_fit,
      al_init = retained$al_init,
      attempts = retained$attempts
    ))
  }
  if (identical(spec$model_id[[1L]], "exqdesn_rhs_independent_vb")) {
    t0 <- proc.time()[["elapsed"]]
    fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
    if (is.null(fit$beta_mean) && !is.null(fit$fits)) {
      fit$beta_mean <- as.numeric(unlist(lapply(fit$fits, `[[`, "beta_mean"), use.names = FALSE))
    }
    elapsed <- proc.time()[["elapsed"]] - t0
    used <- as.integer(attr(fit, "adaptive_vb_max_iter_used") %||% controls$vb_max_iter)
    return(list(
      vb_fit = fit,
      al_init = NULL,
      attempts = data.frame(
        vb_max_iter_used = used,
        al_converged = NA,
        exal_converged = isTRUE(fit$converged),
        al_trace_rows = NA_integer_,
        exal_trace_rows = nrow(fit$trace %||% data.frame()),
        al_elapsed_seconds = NA_real_,
        exal_elapsed_seconds = elapsed,
        stringsAsFactors = FALSE
      )
    ))
  }
  stop(sprintf("Phase136 supports only exAL rows, got '%s'.", spec$model_id[[1L]]), call. = FALSE)
}

app_joint_exqdesn_phase136_vb_trace_rows <- function(fit, tau, meta) {
  if (is.null(fit$fits)) return(app_joint_exqdesn_vb_trace_rows(fit, tau, meta))
  rows <- lapply(seq_along(tau), function(kk) {
    one_meta <- meta
    one_meta$quantile_index_source <- kk
    app_joint_exqdesn_vb_trace_rows(fit$fits[[kk]], tau[[kk]], one_meta)
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase136_run_chain <- function(job, prep_by_case_variant, mcmc_controls,
                                                 gamma_init_mode, gamma_jitter_fraction) {
  prep <- prep_by_case_variant[[job$phase136_case_variant_id[[1L]]]]
  fixture <- prep$fixture
  spec <- prep$spec
  controls <- prep$controls
  variant <- prep$variant
  chain_id <- as.integer(job$chain_id[[1L]])
  chain_seed <- as.integer(job$chain_seed[[1L]])
  gamma_update <- variant$gamma_update[[1L]]
  width_vector <- prep$gamma_slice_width
  chain_start <- proc.time()[["elapsed"]]
  if (identical(spec$fit_structure[[1L]], "joint")) {
    init <- app_joint_exqdesn_phase136_chain_init_for_gamma_update(
      vb_fit = prep$vb$vb_fit,
      tau = fixture$tau,
      controls = controls,
      chain_id = chain_id,
      n_chains = mcmc_controls$n_chains,
      gamma_update = gamma_update,
      mode = gamma_init_mode,
      jitter_fraction = gamma_jitter_fraction
    )
    fit <- app_joint_qvp_fit_exal_mcmc_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = fixture$tau,
      n_iter = mcmc_controls$mcmc_n_iter,
      burn = mcmc_controls$mcmc_burn,
      thin = mcmc_controls$mcmc_thin,
      seed = chain_seed,
      kappa = 1,
      tau0 = controls$tau0,
      zeta2 = controls$zeta2,
      gamma_init = app_joint_qdesn_gamma_init_for_policy(fixture$tau, controls),
      alpha_min_spacing = controls$alpha_min_spacing,
      max_dense_dim = controls$max_dense_dim,
      sigma_bounds = prep$sigma_bounds,
      gamma_slice_width = width_vector,
      gamma_slice_max_steps = variant$gamma_slice_max_steps[[1L]],
      gamma_update = gamma_update,
      init = init
    )
  } else {
    one_tau_fits <- vector("list", length(fixture$tau))
    for (kk in seq_along(fixture$tau)) {
      one_init <- app_joint_exqdesn_phase136_chain_init_for_gamma_update(
        vb_fit = prep$vb$vb_fit$fits[[kk]],
        tau = fixture$tau[[kk]],
        controls = controls,
        chain_id = chain_id,
        n_chains = mcmc_controls$n_chains,
        gamma_update = gamma_update,
        mode = gamma_init_mode,
        jitter_fraction = gamma_jitter_fraction
      )
      one_tau_fits[[kk]] <- app_joint_qvp_fit_exal_mcmc_tiny(
        y = fixture$y,
        Z = fixture$Z,
        tau = fixture$tau[[kk]],
        n_iter = mcmc_controls$mcmc_n_iter,
        burn = mcmc_controls$mcmc_burn,
        thin = mcmc_controls$mcmc_thin,
        seed = chain_seed + kk * 1009L,
        kappa = 1,
        tau0 = controls$tau0,
        zeta2 = controls$zeta2,
        gamma_init = app_joint_qdesn_gamma_init_for_policy(fixture$tau[[kk]], controls),
        alpha_min_spacing = 0,
        max_dense_dim = controls$max_dense_dim,
        sigma_bounds = prep$sigma_bounds,
        gamma_slice_width = width_vector[[kk]],
        gamma_slice_max_steps = variant$gamma_slice_max_steps[[1L]],
        gamma_update = gamma_update,
        init = one_init
      )
    }
    fit <- app_joint_qdesn_phase122_combine_independent_chain(
      fits_by_tau = one_tau_fits,
      Z = fixture$Z,
      tau = fixture$tau,
      chain_id = chain_id,
      seed = chain_seed
    )
    fit$gamma_update <- gamma_update
  }
  elapsed <- proc.time()[["elapsed"]] - chain_start
  list(
    phase136_case_variant_id = prep$phase136_case_variant_id,
    case_id = prep$case_id,
    scenario_id = prep$scenario_id,
    phase136_variant_id = prep$phase136_variant_id,
    chain_id = chain_id,
    chain_seed = chain_seed,
    fit = fit,
    runtime = data.frame(
      prep$mcmc_meta,
      runtime_component = "mcmc_chain",
      chain_id = chain_id,
      chain_seed = chain_seed,
      elapsed_seconds = elapsed,
      sec_per_iter = elapsed / max(1L, mcmc_controls$mcmc_n_iter),
      stringsAsFactors = FALSE
    )
  )
}

app_joint_exqdesn_phase136_assess_case <- function(prep, mcmc_controls, mcmc_summary, rhat, gap, ac, draw_summary) {
  by_case_variant <- function(tbl) {
    if (!nrow(tbl)) return(tbl)
    if ("phase136_case_variant_id" %in% names(tbl)) {
      return(tbl[tbl$phase136_case_variant_id == prep$phase136_case_variant_id, , drop = FALSE])
    }
    if (all(c("case_id", "experiment_id") %in% names(tbl))) {
      return(tbl[tbl$case_id == prep$case_id & tbl$experiment_id == prep$phase136_variant_id, , drop = FALSE])
    }
    tbl[FALSE, , drop = FALSE]
  }
  rh <- by_case_variant(rhat)
  gp <- by_case_variant(gap)
  ac1 <- by_case_variant(ac)
  ac1 <- ac1[ac1$lag == 1L, , drop = FALSE]
  dr <- by_case_variant(draw_summary)
  sm <- by_case_variant(mcmc_summary)
  finite_rhat <- rh$rhat[is.finite(rh$rhat)]
  finite_ess <- rh$rough_ess_total[is.finite(rh$rough_ess_total)]
  gamma_rhat <- rh$rhat[rh$parameter == "gamma" & is.finite(rh$rhat)]
  gamma_ess <- rh$rough_ess_total[rh$parameter == "gamma" & is.finite(rh$rough_ess_total)]
  gamma_gap <- gp$chain_mean_gap[gp$parameter == "gamma" & is.finite(gp$chain_mean_gap)]
  gamma_ac <- ac1$autocorrelation[ac1$parameter == "gamma" & is.finite(ac1$autocorrelation)]
  sigma_upper_hit <- dr$upper_bound_hit_fraction[dr$block == "sigma" & is.finite(dr$upper_bound_hit_fraction)]
  contract_cross <- sum(
    sm$mcmc_fit_contract_crossing_pairs,
    sm$mcmc_forecast_contract_crossing_pairs,
    na.rm = TRUE
  )
  raw_cross <- sum(
    sm$mcmc_fit_raw_crossing_pairs,
    sm$mcmc_forecast_raw_crossing_pairs,
    na.rm = TRUE
  )
  hard_fail <- !nrow(sm) || !nrow(rh) || any(!is.finite(c(sm$mcmc_fit_truth_mae, sm$mcmc_forecast_truth_mae))) ||
    contract_cross > 0L || any(!dr$all_finite, na.rm = TRUE)
  review <- !hard_fail && (
    raw_cross > 0L ||
      (!isTRUE(prep$vb$vb_fit$converged)) ||
      (length(finite_rhat) && max(finite_rhat) > 1.2) ||
      (length(finite_ess) && min(finite_ess) < 100) ||
      (length(gamma_ac) && max(gamma_ac) > 0.98) ||
      (length(sigma_upper_hit) && max(sigma_upper_hit) > 0)
  )
  data.frame(
    prep$mcmc_meta,
    gamma_slice_width_summary = paste(format(prep$gamma_slice_width, digits = 8, trim = TRUE), collapse = ","),
    phase136_gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
    mcmc_fit_truth_mae = if (nrow(sm)) sm$mcmc_fit_truth_mae[[1L]] else NA_real_,
    mcmc_forecast_truth_mae = if (nrow(sm)) sm$mcmc_forecast_truth_mae[[1L]] else NA_real_,
    mcmc_fit_check_loss_mean = if (nrow(sm)) sm$mcmc_fit_check_loss_mean[[1L]] else NA_real_,
    mcmc_forecast_check_loss_mean = if (nrow(sm)) sm$mcmc_forecast_check_loss_mean[[1L]] else NA_real_,
    mcmc_fit_raw_crossing_pairs = if (nrow(sm)) sm$mcmc_fit_raw_crossing_pairs[[1L]] else NA_integer_,
    mcmc_forecast_raw_crossing_pairs = if (nrow(sm)) sm$mcmc_forecast_raw_crossing_pairs[[1L]] else NA_integer_,
    mcmc_fit_contract_crossing_pairs = if (nrow(sm)) sm$mcmc_fit_contract_crossing_pairs[[1L]] else NA_integer_,
    mcmc_forecast_contract_crossing_pairs = if (nrow(sm)) sm$mcmc_forecast_contract_crossing_pairs[[1L]] else NA_integer_,
    max_rhat = if (length(finite_rhat)) max(finite_rhat) else NA_real_,
    min_rough_ess_total = if (length(finite_ess)) min(finite_ess) else NA_real_,
    max_gamma_rhat = if (length(gamma_rhat)) max(gamma_rhat) else NA_real_,
    min_gamma_rough_ess_total = if (length(gamma_ess)) min(gamma_ess) else NA_real_,
    max_gamma_chain_mean_gap = if (length(gamma_gap)) max(gamma_gap) else NA_real_,
    max_gamma_lag1_autocorrelation = if (length(gamma_ac)) max(gamma_ac) else NA_real_,
    max_sigma_upper_bound_hit_fraction = if (length(sigma_upper_hit)) max(sigma_upper_hit) else NA_real_,
    status_reason = paste(c(
      if (hard_fail) "missing/nonfinite summaries, nonfinite draws, or contract crossings",
      if (!hard_fail && raw_cross > 0L) "raw MCMC qhat crossings before contract step",
      if (!hard_fail && !isTRUE(prep$vb$vb_fit$converged)) "VB initialization reached max iterations",
      if (!hard_fail && length(finite_rhat) && max(finite_rhat) > 1.2) "MCMC Rhat exceeds review threshold",
      if (!hard_fail && length(finite_ess) && min(finite_ess) < 100) "rough ESS below review threshold",
      if (!hard_fail && length(gamma_ac) && max(gamma_ac) > 0.98) "gamma lag-1 autocorrelation remains high",
      if (!hard_fail && length(sigma_upper_hit) && max(sigma_upper_hit) > 0) "sigma upper bound hit"
    ), collapse = "; "),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase136_readme <- function(run_config, assessment) {
  c(
    "# Joint exQDESN Phase136 Gamma-Kernel MCMC Packet",
    "",
    "This directory contains the first-wave matched exAL MCMC gamma-kernel packet after Phase135.",
    "It compares the existing bounded gamma slice sampler against a logit-scale gamma slice update on high-priority cases.",
    "",
    sprintf("- Phase135 screening source: `%s`", run_config$phase135_screening_dir[[1L]]),
    sprintf("- Phase135 audit source: `%s`", run_config$phase135_audit_dir[[1L]]),
    sprintf("- Fixture source: `%s`", run_config$fixture_dir[[1L]]),
    sprintf("- Cases: `%s`", run_config$n_cases[[1L]]),
    sprintf("- Variants: `%s`", run_config$variant_ids[[1L]]),
    sprintf("- Chains per case/variant: `%s`", run_config$n_chains[[1L]]),
    sprintf("- MCMC iterations/burn/thin: `%s/%s/%s`", run_config$mcmc_n_iter[[1L]], run_config$mcmc_burn[[1L]], run_config$mcmc_thin[[1L]]),
    sprintf("- Cores: `%s`", run_config$n_cores[[1L]]),
    sprintf("- Save raw RData: `%s`", run_config$save_rdata[[1L]]),
    "",
    "The validation contract remains quantile-grid based. Raw qhat crossings are diagnostic; contract qhat is monotone and used for scoring.",
    "This is not an article-table promotion layer. It decides whether the logit gamma update should be propagated to broader exAL MCMC confirmation.",
    "",
    "Gate counts:",
    paste(capture.output(print(table(assessment$phase136_gate_status))), collapse = "\n")
  )
}

app_joint_exqdesn_run_phase136_gamma_kernel_packet <- function(
  out_dir = app_joint_exqdesn_phase136_default_dir(),
  phase135_screening_dir = app_joint_exqdesn_phase136_default_phase135_screening_dir(),
  phase135_audit_dir = app_joint_exqdesn_phase136_default_phase135_audit_dir(),
  fixture_dir = app_joint_exqdesn_phase136_default_fixture_dir(),
  case_ids = NULL,
  case_limit = NULL,
  variant_ids = c("bounded_w4", "logit_w4"),
  bounded_width_multiplier = 4,
  logit_eta_width = 4,
  gamma_slice_max_steps = 100L,
  n_chains = 8L,
  mcmc_n_iter = 8000L,
  mcmc_burn = 2000L,
  mcmc_thin = 1L,
  mcmc_seed_offset = 7600L,
  chain_seed_stride = 100L,
  sigma_upper_multiplier = 50,
  distance_pass = 5,
  chain_pass = 5,
  n_cores = 32L,
  vb_n_cores = 5L,
  gamma_init_mode = "vb_jittered",
  gamma_jitter_fraction = 0.10,
  trace_write_stride = 50L,
  save_rdata = FALSE,
  dry_run = FALSE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  app_ensure_dir(file.path(out_dir, "figures"))
  if (isTRUE(save_rdata)) app_ensure_dir(file.path(out_dir, "raw_objects"))

  phase135 <- app_joint_exqdesn_phase136_load_phase135(phase135_screening_dir, phase135_audit_dir)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  selected <- app_joint_exqdesn_phase136_select_cases(phase135, case_ids = case_ids, case_limit = case_limit)
  variant_registry <- app_joint_exqdesn_phase136_variant_registry(
    selected,
    variant_ids = variant_ids,
    bounded_width_multiplier = bounded_width_multiplier,
    logit_eta_width = logit_eta_width,
    gamma_slice_max_steps = gamma_slice_max_steps
  )
  mcmc_controls <- app_joint_qdesn_mcmc_readiness_controls(
    n_chains = n_chains,
    mcmc_n_iter = mcmc_n_iter,
    mcmc_burn = mcmc_burn,
    mcmc_thin = mcmc_thin,
    mcmc_seed_offset = mcmc_seed_offset,
    chain_seed_stride = chain_seed_stride,
    sigma_upper_multiplier = sigma_upper_multiplier,
    distance_pass = distance_pass,
    chain_pass = chain_pass,
    n_cores = n_cores
  )

  run_config <- data.frame(
    run_id = "joint_qdesn_phase136_exal_gamma_kernel_packet",
    out_dir = out_dir,
    phase135_screening_dir = phase135$screening_dir,
    phase135_audit_dir = phase135$audit_dir,
    fixture_dir = artifacts$fixture_dir,
    selected_case_ids = paste(selected$case_id, collapse = ","),
    n_cases = nrow(selected),
    variant_ids = paste(unique(variant_registry$phase136_variant_id), collapse = ","),
    n_case_variants = nrow(variant_registry),
    n_chains = mcmc_controls$n_chains,
    total_chain_jobs = nrow(variant_registry) * mcmc_controls$n_chains,
    mcmc_n_iter = mcmc_controls$mcmc_n_iter,
    mcmc_burn = mcmc_controls$mcmc_burn,
    mcmc_thin = mcmc_controls$mcmc_thin,
    mcmc_seed_offset = mcmc_controls$mcmc_seed_offset,
    chain_seed_stride = mcmc_controls$chain_seed_stride,
    sigma_upper_multiplier = mcmc_controls$sigma_upper_multiplier,
    bounded_width_multiplier = bounded_width_multiplier,
    logit_eta_width = logit_eta_width,
    gamma_slice_max_steps = gamma_slice_max_steps,
    gamma_init_mode = gamma_init_mode,
    gamma_jitter_fraction = gamma_jitter_fraction,
    trace_write_stride = trace_write_stride,
    n_cores = mcmc_controls$n_cores,
    vb_n_cores = as.integer(vb_n_cores),
    save_rdata = isTRUE(save_rdata),
    dry_run = isTRUE(dry_run),
    validation_contract = "quantile_grid_fit_and_forecast_scoring_with_raw_contract_qhat",
    scalar_predictive_density_claim = FALSE,
    stringsAsFactors = FALSE
  )

  if (isTRUE(dry_run)) {
    readme_path <- file.path(out_dir, "README.md")
    writeLines(c(
      "# Joint exQDESN Phase136 Dry Run",
      "",
      "Dry run only: selected cases and variant registry were materialized; no VB or MCMC fitting was launched."
    ), readme_path, useBytes = TRUE)
    paths <- c(
      run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
      phase135_screening_manifest_verification = app_joint_qvp_write_csv(phase135$screen_manifest, file.path(out_dir, "phase135_screening_manifest_verification.csv")),
      phase135_audit_manifest_verification = app_joint_qvp_write_csv(phase135$audit_manifest, file.path(out_dir, "phase135_audit_manifest_verification.csv")),
      fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
      phase136_selected_cases = app_joint_qvp_write_csv(selected, file.path(out_dir, "phase136_selected_cases.csv")),
      phase136_variant_registry = app_joint_qvp_write_csv(variant_registry, file.path(out_dir, "phase136_variant_registry.csv")),
      provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
      readme = normalizePath(readme_path, mustWork = TRUE)
    )
    manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
    return(list(out_dir = out_dir, paths = c(paths, artifact_manifest = manifest_info$manifest_path), manifest = manifest_info$manifest))
  }

  row_by_case_variant <- split(variant_registry, variant_registry$phase136_case_variant_id)
  prep_start <- proc.time()[["elapsed"]]
  prep_results <- app_joint_qdesn_parallel_lapply(names(row_by_case_variant), function(id) {
    variant <- row_by_case_variant[[id]]
    fixture <- app_joint_qdesn_scenario_fixture(artifacts, variant$scenario_ids[[1L]], role = "fit")
    spec <- app_joint_qdesn_phase122_select_spec(variant$model_ids[[1L]])
    controls <- app_joint_qdesn_phase122_controls_from_row(variant, n_cores = 1L)
    vb_start <- proc.time()[["elapsed"]]
    vb <- app_joint_exqdesn_phase136_fit_vb_case(fixture, spec, controls)
    vb_elapsed <- proc.time()[["elapsed"]] - vb_start
    sigma_upper <- max(1, mcmc_controls$sigma_upper_multiplier * max(vb$vb_fit$sigma_mean, na.rm = TRUE))
    sigma_bounds <- c(1.0e-8, sigma_upper)
    vb_meta <- app_joint_qdesn_phase122_meta(fixture, spec, variant, spec$inference[[1L]], spec$model_id[[1L]])
    mcmc_meta <- app_joint_qdesn_phase122_meta(fixture, spec, variant, "MCMC", app_joint_qdesn_phase122_mcmc_model_id(spec$model_id[[1L]]))
    common <- data.frame(
      experiment_id = variant$phase136_variant_id[[1L]],
      variant_id = variant$phase136_variant_id[[1L]],
      phase136_variant_id = variant$phase136_variant_id[[1L]],
      phase136_case_variant_id = variant$phase136_case_variant_id[[1L]],
      gamma_update = variant$gamma_update[[1L]],
      width_multiplier = ifelse(variant$gamma_update[[1L]] == "bounded_slice", bounded_width_multiplier, NA_real_),
      logit_eta_width = ifelse(variant$gamma_update[[1L]] == "logit_slice", logit_eta_width, NA_real_),
      stringsAsFactors = FALSE
    )
    vb_meta <- cbind(vb_meta, common, stringsAsFactors = FALSE)
    mcmc_meta <- cbind(mcmc_meta, common, stringsAsFactors = FALSE)
    list(
      phase136_case_variant_id = variant$phase136_case_variant_id[[1L]],
      phase136_variant_id = variant$phase136_variant_id[[1L]],
      case_id = variant$case_id[[1L]],
      scenario_id = variant$scenario_ids[[1L]],
      gamma_update = variant$gamma_update[[1L]],
      variant = variant,
      fixture = fixture,
      spec = spec,
      controls = controls,
      vb = vb,
      vb_elapsed = vb_elapsed,
      vb_meta = vb_meta,
      mcmc_meta = mcmc_meta,
      sigma_bounds = sigma_bounds,
      gamma_slice_width = app_joint_exqdesn_phase136_width_vector(
        fixture$tau,
        variant$gamma_update[[1L]],
        bounded_width_multiplier,
        logit_eta_width
      )
    )
  }, vb_n_cores)
  prep_elapsed <- proc.time()[["elapsed"]] - prep_start
  prep_failures <- app_joint_qdesn_worker_failure_rows(prep_results, "phase136_case_variant_preparation")
  preps <- app_joint_qdesn_successful_worker_results(prep_results, "phase136_case_variant_preparation")
  prep_by_case_variant <- stats::setNames(preps, vapply(preps, `[[`, character(1L), "phase136_case_variant_id"))

  base_jobs <- app_joint_qdesn_bind_rows(lapply(preps, function(prep) {
    base_seed <- as.integer(prep$fixture$scenario_meta$seed[[1L]])
    case_offset <- sum(utf8ToInt(prep$phase136_case_variant_id)) %% 100000L
    app_joint_qdesn_bind_rows(lapply(seq_len(mcmc_controls$n_chains), function(chain_id) {
      data.frame(
        job_id = sprintf("%s__chain_%02d", prep$phase136_case_variant_id, chain_id),
        phase136_case_variant_id = prep$phase136_case_variant_id,
        case_id = prep$case_id,
        scenario_id = prep$scenario_id,
        phase136_variant_id = prep$phase136_variant_id,
        chain_id = chain_id,
        chain_seed = base_seed + mcmc_controls$mcmc_seed_offset + case_offset +
          (chain_id - 1L) * mcmc_controls$chain_seed_stride,
        stringsAsFactors = FALSE
      )
    }))
  }))
  job_by_id <- split(base_jobs, base_jobs$job_id)
  mcmc_start <- proc.time()[["elapsed"]]
  chain_results <- app_joint_qdesn_parallel_lapply(
    names(job_by_id),
    function(jid) app_joint_exqdesn_phase136_run_chain(
      job_by_id[[jid]],
      prep_by_case_variant = prep_by_case_variant,
      mcmc_controls = mcmc_controls,
      gamma_init_mode = gamma_init_mode,
      gamma_jitter_fraction = gamma_jitter_fraction
    ),
    mcmc_controls$n_cores
  )
  mcmc_elapsed <- proc.time()[["elapsed"]] - mcmc_start
  chain_failures <- app_joint_qdesn_worker_failure_rows(chain_results, "phase136_mcmc_chain")
  successful_chains <- app_joint_qdesn_successful_worker_results(chain_results, "phase136_mcmc_chain")
  chains_by_case_variant <- split(successful_chains, vapply(successful_chains, `[[`, character(1L), "phase136_case_variant_id"))

  case_results <- lapply(names(chains_by_case_variant), function(id) {
    prep <- prep_by_case_variant[[id]]
    results <- chains_by_case_variant[[id]]
    results <- results[order(vapply(results, `[[`, integer(1L), "chain_id"))]
    fits <- lapply(results, `[[`, "fit")
    pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(fits, prep$fixture$Z, length(prep$fixture$tau), ncol(prep$fixture$Z), prep$fixture$tau)
    vb_fit_scores <- app_joint_qdesn_phase122_score_qhat(
      prep$vb_meta,
      prep$fixture,
      app_joint_qdesn_predict_fit(prep$vb$vb_fit, prep$fixture$Z, prep$fixture$tau),
      "qhat",
      "phase136_vb_fit_quantiles"
    )
    mcmc_fit_scores <- app_joint_qdesn_phase122_score_qhat(
      prep$mcmc_meta,
      prep$fixture,
      app_joint_qdesn_predict_fit(pooled, prep$fixture$Z, prep$fixture$tau),
      "qhat",
      "phase136_mcmc_fit_quantiles"
    )
    vb_forecast_scores <- app_joint_qdesn_phase122_forecast_scores(prep$vb_meta, artifacts, prep$scenario_id, prep$fixture, prep$vb$vb_fit, "qhat", "phase136_vb_forecast_quantiles")
    mcmc_forecast_scores <- app_joint_qdesn_phase122_forecast_scores(prep$mcmc_meta, artifacts, prep$scenario_id, prep$fixture, pooled, "qhat", "phase136_mcmc_forecast_quantiles")
    trace <- app_joint_exqdesn_mcmc_chain_trace_rows(fits, prep$fixture$tau, prep$mcmc_meta, mcmc_controls$mcmc_n_iter, mcmc_controls$mcmc_burn, mcmc_controls$mcmc_thin)
    rhat <- app_joint_exqdesn_mcmc_rhat_ess_rows(fits, prep$fixture$tau, prep$mcmc_meta)
    draw <- app_joint_qdesn_bind_rows(lapply(seq_along(fits), function(chain_id) {
      cbind(
        prep$mcmc_meta,
        data.frame(chain_id = chain_id, chain_seed = fits[[chain_id]]$seed %||% NA_integer_, stringsAsFactors = FALSE),
        app_joint_qdesn_phase122_draw_summary(fits[[chain_id]], prep$case_id, "phase136_gamma_kernel_packet", prep$fixture$scenario_id, sigma_bounds = prep$sigma_bounds),
        stringsAsFactors = FALSE
      )
    }))
    distance <- app_joint_qvp_vb_mcmc_distance_summary(
      prep$vb$vb_fit,
      pooled,
      prep$case_id,
      "phase136_gamma_kernel_packet",
      prep$fixture$scenario_id,
      length(prep$fixture$y),
      ncol(prep$fixture$Z),
      length(prep$fixture$tau)
    )
    if (!is.null(prep$vb$vb_fit$gamma_mean) && !is.null(pooled$gamma_mean)) {
      gamma_l2 <- app_joint_qvp_l2_distance(prep$vb$vb_fit$gamma_mean, pooled$gamma_mean)
      distance$gamma_l2_to_mcmc <- gamma_l2
      distance$gamma_normalized_distance <- gamma_l2 / (sqrt(length(prep$fixture$tau)) * (1 + sqrt(mean(prep$vb$vb_fit$gamma_mean^2))))
      distance$max_normalized_distance <- pmax(distance$max_normalized_distance, distance$gamma_normalized_distance, na.rm = TRUE)
    } else {
      distance$gamma_l2_to_mcmc <- NA_real_
      distance$gamma_normalized_distance <- NA_real_
    }
    chain_distance <- app_joint_qvp_chain_to_pooled_summary(
      fits,
      pooled,
      prep$fixture$Z,
      prep$case_id,
      "phase136_gamma_kernel_packet",
      prep$fixture$scenario_id,
      length(prep$fixture$y),
      ncol(prep$fixture$Z),
      length(prep$fixture$tau)
    )
    mcmc_summary <- cbind(
      prep$mcmc_meta,
      data.frame(
        n_train = length(prep$fixture$y),
        p = ncol(prep$fixture$Z),
        K = length(prep$fixture$tau),
        tau_grid = app_joint_qdesn_format_tau(prep$fixture$tau),
        vb_converged = isTRUE(prep$vb$vb_fit$converged),
        vb_reached_max_iter = !isTRUE(prep$vb$vb_fit$converged),
        vb_adaptive_attempts = attr(prep$vb$vb_fit, "adaptive_vb_attempts") %||% as.character(prep$controls$vb_max_iter),
        vb_max_iter_used = as.integer(attr(prep$vb$vb_fit, "adaptive_vb_max_iter_used") %||% prep$controls$vb_max_iter),
        mcmc_n_chains = mcmc_controls$n_chains,
        mcmc_n_iter = mcmc_controls$mcmc_n_iter,
        mcmc_burn = mcmc_controls$mcmc_burn,
        mcmc_thin = mcmc_controls$mcmc_thin,
        mcmc_n_keep_total = nrow(pooled$beta_draws),
        mcmc_init_source = pooled$init_source,
        all_chain_init_source_provided = all(vapply(fits, function(x) grepl("provided", x$init_source %||% "", fixed = TRUE), logical(1L))),
        mcmc_draws_all_finite = all(draw$all_finite),
        sigma_lower_bound = prep$sigma_bounds[[1L]],
        sigma_upper_bound = prep$sigma_bounds[[2L]],
        mcmc_fit_truth_mae = mean(mcmc_fit_scores$scored$truth_abs_error, na.rm = TRUE),
        mcmc_forecast_truth_mae = mean(mcmc_forecast_scores$scored$truth_abs_error, na.rm = TRUE),
        mcmc_fit_check_loss_mean = mean(mcmc_fit_scores$scored$check_loss, na.rm = TRUE),
        mcmc_forecast_check_loss_mean = mean(mcmc_forecast_scores$scored$check_loss, na.rm = TRUE),
        mcmc_fit_raw_crossing_pairs = sum(mcmc_fit_scores$contract_info$raw_crossing$n_crossing_pairs),
        mcmc_forecast_raw_crossing_pairs = sum(mcmc_forecast_scores$raw_crossing$n_crossing_pairs),
        mcmc_fit_contract_crossing_pairs = sum(mcmc_fit_scores$contract_info$contract_crossing$n_crossing_pairs),
        mcmc_forecast_contract_crossing_pairs = sum(mcmc_forecast_scores$contract_crossing$n_crossing_pairs),
        mcmc_fit_max_abs_adjustment = max(abs(mcmc_fit_scores$adjustment$adjustment), na.rm = TRUE),
        mcmc_forecast_max_abs_adjustment = max(abs(mcmc_forecast_scores$adjustment$adjustment), na.rm = TRUE),
        vb_mcmc_max_normalized_distance = distance$max_normalized_distance[[1L]],
        max_chain_to_pooled_normalized_distance = max(chain_distance$max_normalized_to_pooled, na.rm = TRUE),
        vb_elapsed_seconds = prep$vb_elapsed,
        mcmc_elapsed_seconds = sum(vapply(results, function(x) x$runtime$elapsed_seconds[[1L]], numeric(1L))),
        stringsAsFactors = FALSE
      )
    )
    figure_path <- file.path(out_dir, "figures", paste0("phase136_trace_", app_joint_exqdesn_trace_safe_id(id), ".pdf"))
    app_joint_exqdesn_plot_variant_diagnostics(prep$phase136_variant_id, trace, app_joint_exqdesn_phase136_vb_trace_rows(prep$vb$vb_fit, prep$fixture$tau, prep$vb_meta), figure_path)
    if (isTRUE(save_rdata)) {
      saveRDS(list(fits = fits, pooled = pooled), file.path(out_dir, "raw_objects", paste0(app_joint_exqdesn_trace_safe_id(id), ".rds")))
    }
    list(
      prep = prep,
      mcmc_summary = mcmc_summary,
      fit_quantiles_raw = app_joint_qdesn_bind_rows(list(vb_fit_scores$raw, mcmc_fit_scores$raw)),
      fit_quantiles = app_joint_qdesn_bind_rows(list(vb_fit_scores$scored, mcmc_fit_scores$scored)),
      fit_adjustment = app_joint_qdesn_bind_rows(list(vb_fit_scores$adjustment, mcmc_fit_scores$adjustment)),
      forecast_quantiles_raw = app_joint_qdesn_bind_rows(list(vb_forecast_scores$raw, mcmc_forecast_scores$raw)),
      forecast_quantiles = app_joint_qdesn_bind_rows(list(vb_forecast_scores$scored, mcmc_forecast_scores$scored)),
      forecast_adjustment = app_joint_qdesn_bind_rows(list(vb_forecast_scores$adjustment, mcmc_forecast_scores$adjustment)),
      crossing = app_joint_qdesn_bind_rows(list(vb_fit_scores$contract_crossing, mcmc_fit_scores$contract_crossing, vb_forecast_scores$contract_crossing, mcmc_forecast_scores$contract_crossing)),
      raw_crossing = app_joint_qdesn_bind_rows(list(vb_fit_scores$raw_crossing, mcmc_fit_scores$raw_crossing, vb_forecast_scores$raw_crossing, mcmc_forecast_scores$raw_crossing)),
      vb_convergence = app_joint_qdesn_vb_convergence_row(prep$vb$vb_fit, prep$vb_meta, prep$controls),
      objective = app_joint_qdesn_objective_row(prep$vb$vb_fit, prep$vb_meta),
      rhs = app_joint_qdesn_rhs_rows(prep$vb$vb_fit, prep$vb_meta),
      draw_summary = draw,
      distance = cbind(prep$mcmc_meta, distance, stringsAsFactors = FALSE),
      chain_distance = cbind(prep$mcmc_meta, chain_distance, stringsAsFactors = FALSE),
      trace_compact = trace[trace$draw_index == 1L | trace$draw_index == max(trace$draw_index, na.rm = TRUE) | (trace$draw_index %% as.integer(trace_write_stride) == 0L), , drop = FALSE],
      trace_summary = app_joint_exqdesn_mcmc_trace_summary_rows(trace),
      rhat = rhat,
      gap = app_joint_exqdesn_chain_mean_gap_rows(trace),
      autocorrelation = app_joint_exqdesn_autocorrelation_rows(trace),
      runtime = app_joint_qdesn_bind_rows(lapply(results, `[[`, "runtime")),
      figure_path = figure_path
    )
  })
  names(case_results) <- names(chains_by_case_variant)

  mcmc_summary <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "mcmc_summary"))
  fit_raw <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "fit_quantiles_raw"))
  fit_quantiles <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "fit_quantiles"))
  fit_adjustment <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "fit_adjustment"))
  forecast_raw <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "forecast_quantiles_raw"))
  forecast_quantiles <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "forecast_quantiles"))
  forecast_adjustment <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "forecast_adjustment"))
  crossing <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "crossing"))
  raw_crossing <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "raw_crossing"))
  vb_convergence <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "vb_convergence"))
  objective <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "objective"))
  rhs <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "rhs"))
  draw_summary <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "draw_summary"))
  distance <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "distance"))
  chain_distance <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "chain_distance"))
  trace_compact <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "trace_compact"))
  trace_summary <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "trace_summary"))
  rhat <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "rhat"))
  gap <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "gap"))
  autocorrelation <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "autocorrelation"))
  runtime <- app_joint_qdesn_bind_rows(lapply(case_results, `[[`, "runtime"))
  runtime <- app_joint_qdesn_bind_rows(list(
    runtime,
    data.frame(
      runtime_component = "case_variant_preparation_total",
      elapsed_seconds = prep_elapsed,
      stringsAsFactors = FALSE
    ),
    data.frame(
      runtime_component = "mcmc_chain_parallel_total",
      elapsed_seconds = mcmc_elapsed,
      stringsAsFactors = FALSE
    )
  ))

  assessment <- app_joint_qdesn_bind_rows(lapply(preps, app_joint_exqdesn_phase136_assess_case,
    mcmc_controls = mcmc_controls,
    mcmc_summary = mcmc_summary,
    rhat = rhat,
    gap = gap,
    ac = autocorrelation,
    draw_summary = draw_summary
  ))
  best_by_case <- app_joint_qdesn_bind_rows(lapply(split(assessment, assessment$case_id), function(block) {
    block <- block[order(block$phase136_gate_status != "pass", block$mcmc_forecast_truth_mae, block$max_gamma_rhat, -block$min_gamma_rough_ess_total), , drop = FALSE]
    out <- block[1L, , drop = FALSE]
    out$phase136_recommendation <- if (out$gamma_update[[1L]] == "logit_slice" && out$phase136_gate_status[[1L]] != "fail") {
      "candidate_logit_gamma_update_for_next_packet"
    } else if (out$phase136_gate_status[[1L]] == "fail") {
      "do_not_promote_until_failure_resolved"
    } else {
      "retain_bounded_slice_reference_or_compare_with_longer_run"
    }
    out
  }))

  readme_path <- file.path(out_dir, "README.md")
  writeLines(app_joint_exqdesn_phase136_readme(run_config, assessment), readme_path, useBytes = TRUE)
  figure_paths <- unlist(lapply(case_results, `[[`, "figure_path"), use.names = FALSE)
  names(figure_paths) <- paste0("figure_", seq_along(figure_paths))
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    phase135_screening_manifest_verification = app_joint_qvp_write_csv(phase135$screen_manifest, file.path(out_dir, "phase135_screening_manifest_verification.csv")),
    phase135_audit_manifest_verification = app_joint_qvp_write_csv(phase135$audit_manifest, file.path(out_dir, "phase135_audit_manifest_verification.csv")),
    fixture_source_manifest = app_joint_qvp_write_csv(artifacts$manifest_verification, file.path(out_dir, "fixture_source_manifest.csv")),
    phase136_selected_cases = app_joint_qvp_write_csv(selected, file.path(out_dir, "phase136_selected_cases.csv")),
    phase136_variant_registry = app_joint_qvp_write_csv(variant_registry, file.path(out_dir, "phase136_variant_registry.csv")),
    phase136_chain_jobs = app_joint_qvp_write_csv(base_jobs, file.path(out_dir, "phase136_chain_jobs.csv")),
    phase136_case_variant_prep_failures = app_joint_qvp_write_csv(prep_failures, file.path(out_dir, "phase136_case_variant_prep_failures.csv")),
    phase136_chain_worker_failures = app_joint_qvp_write_csv(chain_failures, file.path(out_dir, "phase136_chain_worker_failures.csv")),
    phase136_mcmc_case_summary = app_joint_qvp_write_csv(mcmc_summary, file.path(out_dir, "phase136_mcmc_case_summary.csv")),
    phase136_case_assessment = app_joint_qvp_write_csv(assessment, file.path(out_dir, "phase136_case_assessment.csv")),
    phase136_best_variant_by_case = app_joint_qvp_write_csv(best_by_case, file.path(out_dir, "phase136_best_variant_by_case.csv")),
    fit_quantiles_raw = app_joint_qvp_write_csv(fit_raw, file.path(out_dir, "fit_quantiles_raw.csv")),
    fit_quantiles = app_joint_qvp_write_csv(fit_quantiles, file.path(out_dir, "fit_quantiles.csv")),
    fit_monotone_adjustment = app_joint_qvp_write_csv(fit_adjustment, file.path(out_dir, "fit_monotone_adjustment.csv")),
    forecast_quantiles_raw = app_joint_qvp_write_csv(forecast_raw, file.path(out_dir, "forecast_quantiles_raw.csv")),
    forecast_quantiles = app_joint_qvp_write_csv(forecast_quantiles, file.path(out_dir, "forecast_quantiles.csv")),
    forecast_monotone_adjustment = app_joint_qvp_write_csv(forecast_adjustment, file.path(out_dir, "forecast_monotone_adjustment.csv")),
    fit_truth_distance_summary = app_joint_qvp_write_csv(app_joint_qdesn_truth_summary(fit_quantiles), file.path(out_dir, "fit_truth_distance_summary.csv")),
    forecast_truth_distance_summary = app_joint_qvp_write_csv(app_joint_qdesn_truth_summary(forecast_quantiles), file.path(out_dir, "forecast_truth_distance_summary.csv")),
    fit_check_loss_summary = app_joint_qvp_write_csv(app_joint_qdesn_check_loss_summary(fit_quantiles), file.path(out_dir, "fit_check_loss_summary.csv")),
    forecast_check_loss_summary = app_joint_qvp_write_csv(app_joint_qdesn_check_loss_summary(forecast_quantiles), file.path(out_dir, "forecast_check_loss_summary.csv")),
    fit_hit_rate_summary = app_joint_qvp_write_csv(app_joint_qdesn_hit_rate_summary(fit_quantiles), file.path(out_dir, "fit_hit_rate_summary.csv")),
    forecast_hit_rate_summary = app_joint_qvp_write_csv(app_joint_qdesn_hit_rate_summary(forecast_quantiles), file.path(out_dir, "forecast_hit_rate_summary.csv")),
    fit_crps_grid_summary = app_joint_qvp_write_csv(app_joint_qdesn_crps_grid_summary(fit_quantiles, "qhat"), file.path(out_dir, "fit_crps_grid_summary.csv")),
    forecast_crps_grid_summary = app_joint_qvp_write_csv(app_joint_qdesn_crps_grid_summary(forecast_quantiles, "qhat"), file.path(out_dir, "forecast_crps_grid_summary.csv")),
    fit_interval_summary = app_joint_qvp_write_csv(app_joint_qdesn_interval_summary(fit_quantiles, "qhat"), file.path(out_dir, "fit_interval_summary.csv")),
    forecast_interval_summary = app_joint_qvp_write_csv(app_joint_qdesn_interval_summary(forecast_quantiles, "qhat"), file.path(out_dir, "forecast_interval_summary.csv")),
    crossing_summary = app_joint_qvp_write_csv(crossing, file.path(out_dir, "crossing_summary.csv")),
    raw_crossing_summary = app_joint_qvp_write_csv(raw_crossing, file.path(out_dir, "raw_crossing_summary.csv")),
    vb_convergence_audit = app_joint_qvp_write_csv(vb_convergence, file.path(out_dir, "vb_convergence_audit.csv")),
    objective_diagnostics = app_joint_qvp_write_csv(objective, file.path(out_dir, "objective_diagnostics.csv")),
    rhs_prior_summary = app_joint_qvp_write_csv(rhs, file.path(out_dir, "rhs_prior_summary.csv")),
    mcmc_draw_summary = app_joint_qvp_write_csv(draw_summary, file.path(out_dir, "mcmc_draw_summary.csv")),
    vb_mcmc_distance_summary = app_joint_qvp_write_csv(distance, file.path(out_dir, "vb_mcmc_distance_summary.csv")),
    chain_to_pooled_distance_summary = app_joint_qvp_write_csv(chain_distance, file.path(out_dir, "chain_to_pooled_distance_summary.csv")),
    mcmc_trace_compact = app_joint_qvp_write_csv(trace_compact, file.path(out_dir, "mcmc_trace_compact.csv")),
    mcmc_trace_summary = app_joint_qvp_write_csv(trace_summary, file.path(out_dir, "mcmc_trace_summary.csv")),
    mcmc_rhat_ess_summary = app_joint_qvp_write_csv(rhat, file.path(out_dir, "mcmc_rhat_ess_summary.csv")),
    chain_mean_gap_summary = app_joint_qvp_write_csv(gap, file.path(out_dir, "chain_mean_gap_summary.csv")),
    autocorrelation_summary = app_joint_qvp_write_csv(autocorrelation, file.path(out_dir, "autocorrelation_summary.csv")),
    runtime_summary = app_joint_qvp_write_csv(runtime, file.path(out_dir, "runtime_summary.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(readme_path, mustWork = TRUE),
    figure_paths
  )
  manifest_info <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_info$manifest_path),
    manifest = manifest_info$manifest,
    run_config = run_config,
    selected = selected,
    variant_registry = variant_registry,
    assessment = assessment,
    best_by_case = best_by_case,
    prep_failures = prep_failures,
    chain_failures = chain_failures
  )
}
