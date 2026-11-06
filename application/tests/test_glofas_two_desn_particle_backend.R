local({
  source("scripts/diagnostics/glofas_nonlinear_replay.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_particle_vi.R", local = TRUE)
  source("scripts/diagnostics/glofas_innovation_coordinates.R", local = TRUE)
  source("scripts/diagnostics/glofas_guided_collapsed_particle.R", local = TRUE)
  source("scripts/diagnostics/glofas_collapsed_al_target.R", local = TRUE)
  source("scripts/diagnostics/glofas_two_desn_particle_backend.R", local = TRUE)
  n <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); n <<- n + 1L }
  near <- function(x, y, tol = 1e-10) {
    gap <- if (length(x) == length(y)) max(abs(as.numeric(x) - as.numeric(y))) else Inf
    if (!is.finite(gap) || gap > tol) stop(sprintf("numeric gap %.17g exceeds %.17g", gap, tol))
    ok(TRUE)
  }
  reject <- function(x) ok(inherits(try(force(x), silent = TRUE), "try-error"))
  scratch <- tempfile("gtdpb_"); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  fixture <- function(H = 2L) {
    work <- tempfile("engine_", tmpdir = scratch); dir.create(work)
    engine <- gnr_engine(getwd(), work,
      list(max_files = 64L, max_file_bytes = 4 * 1024^2, max_total_bytes = 64 * 1024^2))
    e <- engine$env
    cfg <- list(reservoir = list(D = 1L, n = 2L, standardize_inputs = TRUE, add_bias = TRUE),
      covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
      feature_contract = list(version = "0.1", reservoir_input = list(
        output_lags = c(1L, 2L), covariates = list(ppt = 0L, soil = 0L),
        internal_bias = TRUE, standardize = TRUE), readout = list(add_intercept = TRUE,
        include_reservoir_state = TRUE, include_input_block = FALSE,
        include_horizon_scaled = FALSE)))
    input_spec <- e$app_qdesn_reservoir_input_spec(cfg)
    hist_dates <- as.Date("2022-12-21") + 0:4
    future_dates <- tail(hist_dates, 1L) + seq_len(H)
    timeline <- data.frame(date = c(hist_dates, future_dates),
      ppt = seq_len(H + 5L) / 10, soil = .2 + seq_len(H + 5L) / 100,
      ppt_role = "retrospective_weather_covariate",
      soil_role = "retrospective_weather_covariate", stringsAsFactors = FALSE)
    panel <- data.frame(origin_date = hist_dates, target_date = hist_dates,
      horizon = 0L, member = NA_character_, is_retrospective = TRUE,
      is_ensemble = FALSE, y_transformed = seq_len(5L) / 5,
      g_transformed = seq_len(5L) / 5 + .2, split = "train",
      cutoff_id = "generated", stringsAsFactors = FALSE)
    attr(panel, "model_covariate_timeline") <- timeline
    make_fit <- function(gain, sign = 1) list(reservoir = list(D = 1L, n = 2L,
      n_tilde = integer(), m = 4L, m_input = 4L, alpha = .7,
      W = list(matrix(c(.15, .02, -.03, .1), 2L)),
      Win = list(sign * matrix(seq_len(10L) / 50 - .1, nrow = 2L)),
      Q = list(), Q_is_identity = logical(), act_f = "tanh", act_k = "identity"),
      states = list(H_all = list(matrix(c(.1, -.15, .2, -.1), 2L, byrow = TRUE))),
      meta = list(reservoir_input_spec = input_spec, history_dates = hist_dates,
        m_input = 4L, standardize_inputs = TRUE, input_bound = "tanh",
        win_scale_global = gain, win_scale_bias = 1,
        win_scale_lags = c(1, .9, .8, 1.1), lag_center = c(.2, .1, .3, .2),
        lag_scale = c(.8, .7, .4, .6)))
    beta_fit <- make_fit(.5); alpha_fit <- make_fit(.35, -1)
    disc <- panel; disc$y_transformed <- panel$g_transformed - panel$y_transformed
    ens <- data.frame(origin_date = tail(hist_dates, 1L),
      target_date = rep(future_dates, each = 51L),
      horizon = rep(seq_len(H), each = 51L),
      member = rep(sprintf("m%02d", 1:51), H),
      g_transformed = rep(.8 + seq_len(H) / 10, each = 51L) +
        rep(seq_len(51L) / 1000, H), ensemble_weight = 1,
      y_transformed = NA_real_, stringsAsFactors = FALSE)
    center <- vapply(seq_len(H), function(h) mean(ens$g_transformed[ens$horizon == h]), numeric(1L))
    context <- list(cfg = cfg, cfg_beta = cfg, cfg_alpha = cfg,
      latent_data = list(origin_date = tail(hist_dates, 1L), cutoff_id = "generated",
        future_key = data.frame(target_date = future_dates, horizon = seq_len(H)),
        g_ensemble = ens), qfit_beta = beta_fit, qfit_alpha = alpha_fit,
      y_history_full = panel$y_transformed, d_history_full = disc$y_transformed,
      base_panel_full = panel, base_panel_disc_full = disc,
      feature_meta_beta = list(), feature_meta_alpha = list(), horizon_scale = H,
      feature_strategy = "recursive_latent_path",
      discrepancy_transition_strategy = "recursive_level",
      discrepancy_input_stream = "discrepancy",
      runtime_optimization = list(compiled_future_contract = TRUE,
        active_future_jacobian = TRUE), covariate_timeline = timeline,
      two_block_design = TRUE, glofas_future_center_path = center,
      future_discrepancy_convention = "recursive_glofas_quantile_minus_latent_reference_path")
    block <- function(ix, tau0) list(index = ix, intercept_index = ix[1L],
      tau0 = tau0, intercept_prec = 1e-9, slab_shape = 2, slab_rate = 4,
      zeta2_fixed = NULL)
    spec <- gcat_spec(6L, list(beta = block(1:3, 5.2043087e-5),
      alpha = block(4:6, .0001159)), .5,
      list(Y = c(shape = 2, rate = 1), G = c(shape = 2, rate = 1)))
    id <- list(task_id = "gft-al-p050",
      posterior_target_sha256 = paste(rep("7", 64), collapse = ""),
      prior_sha256 = paste(rep("8", 64), collapse = ""))
    binding <- gtdpb_bind(engine, context, spec, seq_len(H) / 100,
      c(beta = .5, alpha = .35), id)
    eta <- rep(-.3, spec$dimension); eta[seq_len(6L)] <- c(.6, .1, -.2, -.15, .05, .12)
    list(binding = binding, eta = eta)
  }
  for (H in c(2L, 28L)) {
    f <- fixture(H); decoded <- gcat_decode(f$eta, f$binding$spec)
    pars <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
    path <- seq(-.2, .4, length.out = H)
    backend <- gtdpb_state_backend(f$binding)
    state <- backend$initial(2L, pars)
    paths <- matrix(NA_real_, 2L, H)
    for (h in seq_len(H)) {
      if (h > 1L) paths[, h - 1L] <- path[h - 1L]
      stepped <- backend$step(state, h, paths, pars); state <- stepped$state
      reference <- gtdpb_reference_locations(f$binding, path, pars)
      near(stepped$reference, rep(reference$reference[h], 2L))
      near(stepped$ensemble, rep(reference$ensemble[h], 2L))
    }
    d <- backend$diagnostics()
    ok(d$cache_hits >= H && d$cache_misses == H && d$both_desn_states_carried)
    resampled <- backend$resample(state, c(2L, 2L))
    ok(identical(resampled$ancestor_ids, rep(state$ancestor_ids[2L], 2L)))
    ok(f$binding$member_factors_per_path == 51L * H &&
      all(f$binding$member_weights == 1))
  }
  f <- fixture(2L)
  decoded <- gcat_decode(f$eta, f$binding$spec)
  pars <- list(coefficients = decoded$coefficients, sigma = decoded$sigma)
  retained <- gtdpb_state_backend(f$binding, retain_features = TRUE)
  retained_state <- retained$initial(1L, pars)
  retained_paths <- matrix(NA_real_, 1L, 2L)
  retained_first <- retained$step(retained_state, 1L, retained_paths, pars)
  retained_repeat <- retained$step(retained_state, 1L, retained_paths, pars)
  near(retained_first$beta_features, retained_repeat$beta_features, 0)
  near(retained_first$alpha_features, retained_repeat$alpha_features, 0)
  changed_pars <- pars; changed_pars$coefficients[2L] <-
    changed_pars$coefficients[2L] + .25
  retained_changed <- retained$step(retained_state, 1L, retained_paths, changed_pars)
  ok(retained_changed$reference[[1L]] != retained_first$reference[[1L]])
  retained_again <- retained$step(retained_state, 1L, retained_paths, pars)
  near(retained_again$reference, retained_first$reference, 0)
  ok(retained$diagnostics()$feature_rows_retained &&
    retained$diagnostics()$cache_hits == 2L &&
    retained$diagnostics()$cache_misses == 2L)
  ev <- gtdpb_make_evidence(f$binding, particles = 16L,
    gates = list(min_ess = 1, min_unique_ancestors = 1L), retain_particles = TRUE)
  rng <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) .Random.seed else NULL
  a1 <- ev(f$eta, 2026110601L)
  b <- f$eta; b[2L] <- b[2L] + .2
  ev(b, 2026110602L)
  a2 <- ev(f$eta, 2026110601L)
  ok(a1$complete && a1$diagnostic_thresholds_passed)
  near(a1$log_estimate, a2$log_estimate, 0)
  near(a1$particle_output$paths, a2$particle_output$paths, 0)
  ok(a1$particle_output$member_factor_evaluations == 2L * 16L * 51L)
  ok(a1$backend_diagnostics$cache_reset_scope == "one_parameter_evaluation")
  ok(identical(rng, if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) .Random.seed else NULL))
  bad <- f$binding; bad$member_policy <- "fractional"
  reject(gtdpb_bind(bad$engine, bad$context, bad$spec, bad$known_baseline,
    bad$gains, bad$target_identity, "fractional"))
  bad <- f$binding$context; bad$latent_data$g_ensemble$ensemble_weight[1L] <- 1 / 51
  reject(gtdpb_bind(f$binding$engine, bad, f$binding$spec, f$binding$known_baseline,
    f$binding$gains, f$binding$target_identity))
  cat(sprintf("GLOFAS_TWO_DESN_PARTICLE_BACKEND_PASS checks=%d authentic_reads=0 model_runs=0\n", n))
})
