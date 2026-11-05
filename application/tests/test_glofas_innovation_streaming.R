# Generated numeric fixtures only. No authentic RDS object is opened here.
local({
  source("scripts/diagnostics/glofas_nonlinear_replay.R", local = TRUE)
  source("scripts/diagnostics/glofas_compiled_value_reference.R", local = TRUE)
  source("scripts/diagnostics/glofas_innovation_coordinates.R", local = TRUE)
  source("scripts/diagnostics/glofas_innovation_streaming.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L; invisible(TRUE) }
  near <- function(a, b, tol = 1e-11) ok(length(a) == length(b) &&
    all(is.finite(a)) && all(is.finite(b)) && max(abs(a - b)) < tol)
  reject <- function(expr, pattern) {
    error <- tryCatch({ force(expr); NULL }, error = function(e) e)
    ok(inherits(error, "error")); ok(grepl(pattern, conditionMessage(error), fixed = TRUE))
  }
  scratch <- tempfile("giv_generated_"); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  fixture <- function(depth = 1L, reducer = FALSE, H = 3L) {
    work <- tempfile("case_", tmpdir = scratch); dir.create(work)
    engine <- gnr_engine(getwd(), work,
      list(max_files = 64L, max_file_bytes = 4 * 1024^2, max_total_bytes = 64 * 1024^2))
    e <- engine$env
    cfg <- list(reservoir = list(D = depth, n = 2L, standardize_inputs = TRUE, add_bias = TRUE),
      covariates = list(enabled = TRUE, variables = c("ppt", "soil")),
      feature_contract = list(version = "0.1", reservoir_input = list(output_lags = c(1L, 2L),
        covariates = list(ppt = 0L, soil = 0L), internal_bias = TRUE, standardize = TRUE),
        readout = list(add_intercept = TRUE, include_reservoir_state = TRUE,
          include_input_block = FALSE, include_horizon_scaled = FALSE)))
    spec <- e$app_qdesn_reservoir_input_spec(cfg)
    hist_dates <- as.Date("2022-12-21") + 0:4
    origin <- tail(hist_dates, 1L); future_dates <- origin + seq_len(H)
    timeline <- data.frame(date = c(hist_dates, future_dates),
      ppt = seq_len(H + 5L) / 10, soil = .2 + seq_len(H + 5L) / 100,
      ppt_role = "retrospective_weather_covariate", soil_role = "retrospective_weather_covariate",
      ppt_source = "generated", soil_source = "generated", stringsAsFactors = FALSE)
    panel <- data.frame(origin_date = hist_dates, target_date = hist_dates, horizon = 0L,
      member = NA_character_, is_retrospective = TRUE, is_ensemble = FALSE,
      y_transformed = seq_len(5L) / 5, g_transformed = seq_len(5L) / 5 + .2,
      split = "train", cutoff_id = "generated", stringsAsFactors = FALSE)
    attr(panel, "model_covariate_timeline") <- timeline
    qfit <- list(reservoir = list(D = 1L, n = 2L, n_tilde = integer(), m = 4L,
      m_input = 4L, alpha = .7, W = list(matrix(c(.15, .02, -.03, .1), 2L)),
      Win = list(matrix(seq_len(10L) / 50 - .1, nrow = 2L)), Q = list(),
      Q_is_identity = logical(), act_f = "tanh", act_k = "identity"),
      states = list(H_all = list(matrix(c(.1, -.15, .2, -.1), 2L, byrow = TRUE))),
      meta = list(reservoir_input_spec = spec, history_dates = hist_dates, m_input = 4L,
        standardize_inputs = TRUE, input_bound = "tanh", win_scale_global = .3,
        win_scale_bias = .7, win_scale_lags = c(1, .9, .8, 1.1),
        lag_center = c(.2, .1, .3, .2), lag_scale = c(.8, .7, .4, .6)))
    if (depth == 2L) {
      reduced <- if (reducer) 1L else 2L
      qfit$reservoir$D <- 2L
      qfit$reservoir$n <- c(2L, 3L)
      qfit$reservoir$n_tilde <- reduced
      qfit$reservoir$alpha <- c(.7, .6)
      qfit$reservoir$W[[2L]] <- matrix(seq_len(9L) / 90 - .06, 3L)
      qfit$reservoir$Win[[2L]] <- matrix(seq_len(3L * reduced) / 30 - .06, 3L)
      qfit$reservoir$Q <- list(if (reducer) matrix(c(.7, -.3), 1L) else diag(2L))
      qfit$reservoir$Q_is_identity <- !reducer
      qfit$reservoir$act_k <- "tanh"
      qfit$states$H_all[[2L]] <- matrix(c(.1, .2, -.2, .15, -.12, .05), 2L, byrow = TRUE)
    }
    qfit2 <- qfit
    qfit2$reservoir$Win[[1L]] <- -.7 * qfit2$reservoir$Win[[1L]]
    qfit2$meta$win_scale_global <- .4; qfit2$meta$win_scale_bias <- .8
    disc_panel <- panel; disc_panel$y_transformed <- panel$g_transformed - panel$y_transformed
    ens <- data.frame(origin_date = origin, target_date = rep(future_dates, each = 51L),
      horizon = rep(seq_len(H), each = 51L), member = rep(sprintf("member%02d", 1:51), H),
      g_transformed = rep(.8 + seq_len(H) / 10, each = 51L) + rep(seq_len(51L) / 1000, H),
      ensemble_weight = 1, y_transformed = NA_real_, stringsAsFactors = FALSE)
    center <- vapply(seq_len(H), function(h) mean(ens$g_transformed[ens$horizon == h]), numeric(1L))
    context <- gnr_context(list(future_context = list(cfg = cfg, cfg_beta = cfg, cfg_alpha = cfg,
      latent_data = list(origin_date = origin, cutoff_id = "generated",
        future_key = data.frame(target_date = future_dates, horizon = seq_len(H)), g_ensemble = ens),
      qfit_beta = qfit, qfit_alpha = qfit2, y_history_full = panel$y_transformed,
      d_history_full = disc_panel$y_transformed, base_panel_full = panel,
      base_panel_disc_full = disc_panel, feature_meta_beta = list(), feature_meta_alpha = list(),
      horizon_scale = H, feature_strategy = "recursive_latent_path",
      discrepancy_transition_strategy = "recursive_level", discrepancy_input_stream = "discrepancy",
      runtime_optimization = list(compiled_future_contract = TRUE, active_future_jacobian = TRUE),
      covariate_timeline = timeline, two_block_design = TRUE, glofas_future_center_path = center,
      future_discrepancy_convention = "recursive_glofas_quantile_minus_latent_reference_path")), engine)
    width <- length(e$app_qdesn_readout_row_from_states(e$app_qdesn_last_states(qfit), qfit$reservoir)) + 1L
    theta <- seq_len(2L * width) / 35 - .07
    theta[1L] <- .6; theta[width + 1L] <- -.2
    list(engine = engine, context = context, theta = theta,
      known = seq_len(H) / 100, scales = list(Y = .15, G = .27), H = H)
  }
  make <- function(f, cap = 100L, ...) giv_state_factory(f$engine, f$context,
    f$theta, f$known, f$scales, cap, ...)
  rng_before <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) .Random.seed else NULL
  for (setting in list(c(1L, 0L, 3L), c(2L, 0L, 3L), c(2L, 1L, 3L), c(1L, 0L, 28L))) {
    f <- fixture(setting[1L], as.logical(setting[2L]), setting[3L])
    identity <- gnr_hash(f$context); parameter_identity <- gnr_hash(f$theta)
    a <- make(f)
    z <- seq(-.4, .6, length.out = f$H)
    fast <- a$forward(z)
    d <- a$diagnostics()
    ok(d$forward_calls == 1L && d$production_one_step_calls == 2L * f$H)
    ok(d$oracle$calls == 0L && f$engine$audit$value_calls == 0L)
    ref <- a$reference(fast$path)
    near(fast$reference_location, ref$reference_location)
    near(fast$ensemble_location, ref$ensemble_location)
    near(z, ref$base)
    ok(max(gnr_compare(fast$design, ref$design, FALSE)) < 1e-12)
    inv <- a$inverse(fast$path)
    near(inv$base, z)
    repeat_value <- a$forward(z)
    near(repeat_value$path, fast$path)
    near(repeat_value$ensemble_location, fast$ensemble_location)
    near(a$forward(inv$base)$path, fast$path)
    ok(abs(fast$identity_residual) < 1e-10)
    near(fast$log_target, fast$log_path_target + fast$log_jacobian, 1e-10)
    near(fast$log_base, sum(dnorm(z, log = TRUE)))
    member_logs <- numeric(f$H)
    for (h in seq_len(f$H)) member_logs[h] <- sum(gic_al_log_density(
      f$context$latent_data$g_ensemble$g_transformed[f$context$latent_data$g_ensemble$horizon == h],
      fast$ensemble_location[h], .5, .27))
    near(fast$log_likelihood, sum(member_logs))
    ok(fast$member_factors == f$H * 51L && fast$member_weights == 1)
    ok(identical(fast$parameter_scope, "fixed_parameter_conditional_AL_median_reference"))
    perturbed <- z; perturbed[length(z)] <- perturbed[length(z)] + .2
    changed <- a$forward(perturbed)
    near(changed$path[-length(z)], fast$path[-length(z)])
    near(changed$reference_location, fast$reference_location)
    near(changed$ensemble_location, fast$ensemble_location)
    if (f$H == 3L) {
      eps <- 1e-5
      J <- sapply(seq_len(f$H), function(i) {
        up <- down <- z; up[i] <- up[i] + eps; down[i] <- down[i] - eps
        (a$forward(up)$path - a$forward(down)$path) / (2 * eps)
      })
      ok(max(abs(J[upper.tri(J)])) < 1e-10)
      near(as.numeric(determinant(J, logarithm = TRUE)$modulus), fast$log_jacobian, 1e-7)
    }
    ok(identical(gnr_hash(f$context), identity) && identical(gnr_hash(f$theta), parameter_identity))
    d <- a$diagnostics()
    ok(d$oracle$calls == 2L && d$forward_whole_path_callbacks == 0L)
    ok(d$production_one_step_calls == 2L * f$H * d$forward_calls)
    ok(d$original_file_reads == 0L && d$parameter_updates == 0L &&
      !d$future_truth_read && !d$native_read_or_launch_authorized)
    ok(f$engine$audit$forbidden_calls == 0L)
    ok(d$generated_metadata_serializations == 4L)
  }
  f <- fixture(); a <- make(f, 3L)
  a$forward(c(0, 0, 0)); a$inverse(c(.4, .5, .6)); a$reference(c(.4, .5, .6))
  reject(a$forward(c(0, 0, 0)), "evaluation cap reached")
  reject(make(f, 0L), "evaluation cap")
  reject(make(f, probability = .1), "AL median only")
  reject(a$forward(c(NA_real_, 0, 0)), "evaluation cap reached")
  fresh <- make(f)
  reject(fresh$forward(c(0, NA_real_, 0)), "finite numeric")
  reject(fresh$forward(c(0, 0)), "finite numeric")
  reject(fresh$forward(matrix(0, nrow = 3L)), "coordinate vector")
  bad <- f; bad$scales$Y <- 0
  reject(make(bad), "positive fixed reference scale")
  bad <- f; bad$scales <- list(Y = .15, G = .27, reference = .15)
  reject(make(bad), "exact named")
  bad <- f; bad$theta <- bad$theta[-1L]
  reject(make(bad), "coefficient/feature dimension")
  bad <- f; names(bad$theta) <- paste0("wrong", seq_along(bad$theta))
  reject(make(bad), "coefficient order")
  bad <- f; bad$context$cfg_beta$feature_contract$readout$include_input_block <- TRUE
  reject(make(bad), "intercept/reservoir-only")
  bad <- f; bad$context$latent_data$g_ensemble$ensemble_weight[1L] <- 1 / 51
  reject(make(bad), "unit weights")
  bad <- f; bad$context$latent_data$g_ensemble$usgs <- 1
  reject(make(bad), "future USGS")
  # A named numeric scale pair is supported without accepting an unnamed pair.
  f$scales <- c(Y = .15, G = .27)
  numeric_scales <- make(f); ok(is.finite(numeric_scales$forward(rep(0, 3L))$log_target))
  # Stable Normal coordinates remain finite far beyond rounded ordinary CDFs.
  stress <- make(f)$forward(c(-37, 0, 37))
  ok(all(is.finite(stress$path)) && is.finite(stress$log_jacobian))
  near(make(f)$inverse(stress$path)$base, c(-37, 0, 37), 1e-10)
  rng_after <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) .Random.seed else NULL
  ok(identical(rng_before, rng_after))
  cat(sprintf("PASS: GloFAS innovation streaming (%d generated checks; zero authentic reads)\n", checks))
})
