# Phase151 case-specific frozen-feature reservoir screening for Joint exQDESN.
#
# This stage changes only the deterministic readout design. It preserves the
# Phase150 scenario-specific exAL/RHS controls and the formal fixture/scoring
# contract. Candidate artifacts are checkpointed independently so interrupted
# runs can resume without repeating completed fits.

app_joint_exqdesn_phase151_default_dir <- function() {
  app_path("application/cache/joint_qdesn_phase151_case_specific_feature_screening_20260728")
}

app_joint_exqdesn_phase151_default_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_phase151_case_specific_feature_screening_readiness_20260728")
}

app_joint_exqdesn_phase151_default_orchestration_dir <- function() {
  app_path("application/cache/joint_qdesn_phase151_case_specific_feature_screening_20260728_orchestration")
}

app_joint_exqdesn_phase151_default_fixture_dir <- function() {
  app_path("application/cache/joint_qdesn_simulation_dgp_fixtures_20260706")
}

app_joint_exqdesn_phase151_default_phase150_freeze_dir <- function() {
  app_path("application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_freeze_20260727")
}

app_joint_exqdesn_phase151_default_phase150_audit_dir <- function() {
  app_path(
    "application/cache/joint_qdesn_phase150_case_specific_exal_mcmc_confirmation_20260727",
    "phase150_result_audit"
  )
}

app_joint_exqdesn_phase151_prior_experiment_audit <- function() {
  data.frame(
    prior_stage = c(
      "Phase4n", "Phases128-132", "Phase133B", "Phases134-135",
      "Phases136-143", "Phases144-148", "Phase149", "Phase150"
    ),
    dimension_already_tested = c(
      "AL-only engineered feature maps on an earlier crossing-heavy registry",
      "gamma slice widths, stepping limits, chain length, thinning, and chain count",
      "posterior mean, median, and trimmed quantile summaries",
      "RHS tau0/zeta2/intercept fan/gamma initialization and matched-AL controls",
      "bounded/logit/fixed gamma kernels, gamma priors, and narrow geometry",
      "sampler root cause, sigma-gamma geometry, hybrid updates, and target invariance",
      "scenario-specific exAL readout, RHS, fan, initialization, and VB effort",
      "eight-chain MCMC confirmation of the Phase149 scenario winners"
    ),
    evidence = c(
      "Script 94 and its plan exist, but the default artifact was never materialized; no reservoir states were generated.",
      "Longer or differently tuned gamma updates did not consistently improve quantile-grid performance.",
      "Posterior summaries were nearly tied and did not explain the exAL performance gap.",
      "Matched controls and local prior perturbations did not broadly close the AL gap.",
      "Gamma geometry changed diagnostics more than forecast accuracy.",
      "The implemented target was verified; improved sampler mechanics did not solve model performance.",
      "All eight scenario-specific VB winners passed, but gains over prior exAL rows were modest.",
      "All eight cases passed implementation gates; only Persistent Heavy Tail beat the article Joint AL row."
    ),
    phase151_decision = c(
      "Do not repeat z-score/winsor/interaction/lag-proxy maps; use actual reservoir states.",
      "Hold sampler controls fixed.",
      "Hold posterior summary policy fixed.",
      "Hold scenario-specific Phase150 readout controls fixed.",
      "Do not screen gamma geometry.",
      "Do not modify the validated MCMC target.",
      "Use the selected controls as the readout anchor.",
      "Use direct-feature VB parity anchors; reserve MCMC for new design winners."
    ),
    repeated_in_phase151 = FALSE,
    novelty_status = c(
      "new_reservoir_state_design", rep("excluded_as_already_tested", 6L),
      "intentional_parity_anchor_only"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase151_source_manifest <- function(
  fixture_dir,
  phase150_freeze_dir,
  phase150_audit_dir
) {
  fixture <- app_joint_qdesn_verify_artifact_manifest(fixture_dir)
  fixture$source_id <- "formal_phase1_fixture"
  freeze <- app_joint_exqdesn_phase149_manifest_verification(
    phase150_freeze_dir, "phase150_case_specific_freeze"
  )
  names(freeze)[names(freeze) == "hash_verified"] <- "verified"
  audit <- app_joint_exqdesn_phase149_manifest_verification(
    phase150_audit_dir, "phase150_result_audit"
  )
  names(audit)[names(audit) == "hash_verified"] <- "verified"
  fixture_out <- data.frame(
    source_id = fixture$source_id,
    label = fixture$label,
    relative_path = fixture$relative_path,
    exists = fixture$exists,
    declared_sha256 = fixture$declared_sha256,
    actual_sha256 = fixture$actual_sha256,
    verified = fixture$status == "pass",
    stringsAsFactors = FALSE
  )
  keep <- c(
    "source_id", "label", "relative_path", "exists",
    "declared_sha256", "actual_sha256", "verified"
  )
  app_joint_qdesn_bind_rows(list(
    fixture_out,
    freeze[, intersect(keep, names(freeze)), drop = FALSE],
    audit[, intersect(keep, names(audit)), drop = FALSE]
  ))
}

app_joint_exqdesn_phase151_design_rows <- function(scenario_id, scenario_index, optimize = TRUE) {
  baseline <- data.frame(
    design_role = "direct_phase150_parity",
    design_class = "direct",
    reservoir_width = 0L,
    reservoir_alpha = NA_real_,
    reservoir_rho = NA_real_,
    reservoir_pi_w = NA_real_,
    reservoir_pi_in = NA_real_,
    input_scale = NA_real_,
    reservoir_seed = NA_integer_,
    design_purpose = if (optimize) "parity_anchor" else "frozen_success_control",
    stringsAsFactors = FALSE
  )
  if (!isTRUE(optimize)) return(baseline)

  seed_a <- 202607280L + as.integer(scenario_index) * 100L
  common <- data.frame(
    design_role = c(
      "reservoir_compact", "hybrid_compact", "hybrid_balanced"
    ),
    design_class = c("reservoir", "hybrid", "hybrid"),
    reservoir_width = c(12L, 8L, 12L),
    reservoir_alpha = c(0.92, 0.92, 0.86),
    reservoir_rho = c(0.90, 0.90, 0.95),
    reservoir_pi_w = c(0.20, 0.25, 0.20),
    reservoir_pi_in = 1,
    input_scale = c(0.20, 0.18, 0.20),
    reservoir_seed = seed_a + c(11L, 21L, 31L),
    design_purpose = c(
      "compact reservoir-only nonlinear state map",
      "low-dimensional direct-plus-state map",
      "balanced direct-plus-state memory map"
    ),
    stringsAsFactors = FALSE
  )
  tailored <- switch(
    scenario_id,
    asymmetric_laplace_tail = c(16, 0.90, 0.95, 0.15, 0.16),
    gaussian_mixture_bridge = c(16, 0.86, 0.97, 0.15, 0.20),
    laplace_bridge = c(12, 0.92, 0.93, 0.20, 0.16),
    nonlinear_reservoir_friendly = c(20, 0.86, 0.97, 0.15, 0.25),
    normal_bridge = c(12, 0.94, 0.90, 0.20, 0.15),
    regime_shift = c(20, 0.75, 0.98, 0.15, 0.18),
    student_t_location_scale = c(16, 0.84, 0.97, 0.15, 0.16),
    stop(sprintf("No Phase151 tailored design is defined for '%s'.", scenario_id), call. = FALSE)
  )
  tailored <- data.frame(
    design_role = "hybrid_scenario_tailored",
    design_class = "hybrid",
    reservoir_width = as.integer(tailored[[1L]]),
    reservoir_alpha = tailored[[2L]],
    reservoir_rho = tailored[[3L]],
    reservoir_pi_w = tailored[[4L]],
    reservoir_pi_in = 1,
    input_scale = tailored[[5L]],
    reservoir_seed = seed_a + 41L,
    design_purpose = sprintf("scenario-tailored memory/capacity map for %s", scenario_id),
    stringsAsFactors = FALSE
  )
  rbind(baseline, common, tailored)
}

app_joint_exqdesn_phase151_build_registry <- function(
  phase150_controls,
  phase150_comparison,
  success_scenario = "persistent_heavy_tail"
) {
  required_controls <- c(
    "case_id", "scenario_ids", "model_ids", "candidate_id", "vb_max_iter",
    "adaptive_vb_max_iter_grid", "vb_tol", "rhs_vb_inner", "tau0", "zeta2",
    "a_sigma", "b_sigma", "alpha_prior_sd", "alpha_min_spacing",
    "gamma_init_policy", "review_adjustment_threshold", "max_dense_dim",
    "selected_forecast_truth_mae", "selected_fit_truth_mae"
  )
  app_check_required_columns(phase150_controls, required_controls, "Phase150 winner controls")
  app_check_required_columns(
    phase150_comparison,
    c(
      "scenario_id", "mcmc_forecast_truth_mae", "mcmc_fit_truth_mae",
      "article_joint_al_forecast_truth_mae", "article_joint_al_fit_truth_mae"
    ),
    "Phase150 article comparison"
  )
  scenarios <- sort(unique(as.character(phase150_controls$scenario_ids)))
  if (length(scenarios) != 8L || !success_scenario %in% scenarios) {
    stop("Phase151 requires the eight Phase150 scenario controls and the frozen success scenario.", call. = FALSE)
  }
  rows <- list()
  for (ss in seq_along(scenarios)) {
    scenario_id <- scenarios[[ss]]
    control <- phase150_controls[phase150_controls$scenario_ids == scenario_id, , drop = FALSE]
    comparison <- phase150_comparison[phase150_comparison$scenario_id == scenario_id, , drop = FALSE]
    if (nrow(control) != 1L || nrow(comparison) != 1L) {
      stop(sprintf("Phase151 requires one control/comparison row for '%s'.", scenario_id), call. = FALSE)
    }
    designs <- app_joint_exqdesn_phase151_design_rows(
      scenario_id, ss, optimize = scenario_id != success_scenario
    )
    for (ii in seq_len(nrow(designs))) {
      design <- designs[ii, , drop = FALSE]
      candidate_id <- paste(
        scenario_id, "joint_exqdesn_rhs_vb", "phase151", design$design_role[[1L]],
        if (design$design_class[[1L]] == "direct") "frozen" else paste0("seed", design$reservoir_seed[[1L]]),
        sep = "__"
      )
      rows[[length(rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        case_id = control$case_id[[1L]],
        scenario_id = scenario_id,
        scenario_role = if (scenario_id == success_scenario) {
          "frozen_success_control"
        } else {
          "optimization_target"
        },
        model_id = "joint_exqdesn_rhs_vb",
        source_phase150_candidate_id = control$candidate_id[[1L]],
        design,
        vb_max_iter = as.integer(control$vb_max_iter[[1L]]),
        adaptive_vb_max_iter_grid = as.character(control$adaptive_vb_max_iter_grid[[1L]]),
        vb_tol = as.numeric(control$vb_tol[[1L]]),
        rhs_vb_inner = as.integer(control$rhs_vb_inner[[1L]]),
        tau0 = as.numeric(control$tau0[[1L]]),
        zeta2 = as.numeric(control$zeta2[[1L]]),
        a_sigma = as.numeric(control$a_sigma[[1L]]),
        b_sigma = as.numeric(control$b_sigma[[1L]]),
        alpha_prior_sd = as.character(control$alpha_prior_sd[[1L]]),
        alpha_min_spacing = as.numeric(control$alpha_min_spacing[[1L]]),
        gamma_init_policy = as.character(control$gamma_init_policy[[1L]]),
        review_adjustment_threshold = as.numeric(control$review_adjustment_threshold[[1L]]),
        max_dense_dim = as.integer(control$max_dense_dim[[1L]]),
        phase149_vb_forecast_truth_mae = as.numeric(control$selected_forecast_truth_mae[[1L]]),
        phase149_vb_fit_truth_mae = as.numeric(control$selected_fit_truth_mae[[1L]]),
        phase150_mcmc_forecast_truth_mae = as.numeric(comparison$mcmc_forecast_truth_mae[[1L]]),
        phase150_mcmc_fit_truth_mae = as.numeric(comparison$mcmc_fit_truth_mae[[1L]]),
        article_joint_al_forecast_truth_mae = as.numeric(comparison$article_joint_al_forecast_truth_mae[[1L]]),
        article_joint_al_fit_truth_mae = as.numeric(comparison$article_joint_al_fit_truth_mae[[1L]]),
        no_global_specification = TRUE,
        frozen_target_design_contract = TRUE,
        scoring_contract = "monotone_quantile_grid",
        stringsAsFactors = FALSE
      )
    }
  }
  registry <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(registry$candidate_id)) stop("Phase151 candidate ids must be unique.", call. = FALSE)
  expected <- ifelse(registry$scenario_id == success_scenario, 1L, 5L)
  observed <- as.integer(table(registry$scenario_id)[registry$scenario_id])
  if (any(observed != expected)) stop("Phase151 scenario candidate counts are malformed.", call. = FALSE)
  if (any(registry$model_id != "joint_exqdesn_rhs_vb") ||
      any(!registry$no_global_specification) ||
      any(!registry$frozen_target_design_contract)) {
    stop("Phase151 registry violates its model or interpretation contract.", call. = FALSE)
  }
  registry
}

app_joint_exqdesn_phase151_validate_dense_dimensions <- function(registry, scenario_summary) {
  p_base <- setNames(as.integer(scenario_summary$p), scenario_summary$scenario_id)
  K <- setNames(as.integer(scenario_summary$K), scenario_summary$scenario_id)
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    x <- registry[ii, , drop = FALSE]
    p0 <- p_base[[x$scenario_id[[1L]]]]
    p <- switch(
      x$design_class[[1L]],
      direct = p0,
      reservoir = as.integer(x$reservoir_width[[1L]]),
      hybrid = p0 + as.integer(x$reservoir_width[[1L]])
    )
    kp <- p * K[[x$scenario_id[[1L]]]]
    data.frame(
      candidate_id = x$candidate_id[[1L]],
      scenario_id = x$scenario_id[[1L]],
      base_feature_count = p0,
      readout_feature_count = p,
      quantile_count = K[[x$scenario_id[[1L]]]],
      dense_dimension = kp,
      max_dense_dim = as.integer(x$max_dense_dim[[1L]]),
      status = if (kp <= as.integer(x$max_dense_dim[[1L]])) "pass" else "fail",
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase151_preflight_designs <- function(registry, artifacts) {
  quantile_count <- setNames(
    as.integer(artifacts$scenario_summary$K),
    artifacts$scenario_summary$scenario_id
  )
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    candidate <- registry[ii, , drop = FALSE]
    transformed <- tryCatch(
      app_joint_exqdesn_phase151_transform_design(artifacts, candidate),
      error = function(e) e
    )
    if (inherits(transformed, "error")) {
      return(data.frame(
        candidate_id = candidate$candidate_id[[1L]],
        scenario_id = candidate$scenario_id[[1L]],
        design_class = candidate$design_class[[1L]],
        finite_design = FALSE,
        readout_feature_count = NA_integer_,
        dense_dimension = NA_integer_,
        max_dense_dim = as.integer(candidate$max_dense_dim[[1L]]),
        state_dead_fraction = NA_real_,
        state_live_feature_count = NA_integer_,
        state_effective_rank = NA_integer_,
        state_rank_fraction = NA_real_,
        state_condition_number = NA_real_,
        preflight_status = "fail",
        preflight_reason = conditionMessage(transformed),
        stringsAsFactors = FALSE
      ))
    }
    diagnostic <- transformed$diagnostic
    K <- quantile_count[[candidate$scenario_id[[1L]]]]
    if (is.null(K) || !is.finite(K) || K < 2L) {
      stop("Phase151 could not resolve the scenario quantile count during design preflight.", call. = FALSE)
    }
    dense_dimension <- diagnostic$readout_feature_count[[1L]] * K
    hard_fail <- !isTRUE(diagnostic$finite_design[[1L]]) ||
      diagnostic$state_dead_fraction[[1L]] > 0.30 ||
      dense_dimension > as.integer(candidate$max_dense_dim[[1L]])
    rank_review <- diagnostic$state_rank_fraction[[1L]] < 1 - 1.0e-10 ||
      !is.finite(diagnostic$state_condition_number[[1L]]) ||
      diagnostic$state_condition_number[[1L]] > 1.0e6
    diagnostic$dense_dimension <- dense_dimension
    diagnostic$max_dense_dim <- as.integer(candidate$max_dense_dim[[1L]])
    diagnostic$preflight_status <- if (hard_fail) "fail" else if (rank_review) "review" else "pass"
    diagnostic$preflight_reason <- if (hard_fail) {
      "nonfinite, excessively inactive, or oversized design"
    } else if (rank_review) {
      "rank-deficient or ill-conditioned training design; retain under regularized-readout review"
    } else {
      "finite, dimension-safe, full-rank training design"
    }
    diagnostic
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase151_controls <- function(row) {
  app_joint_qdesn_simulation_controls(
    vb_max_iter = as.integer(row$vb_max_iter[[1L]]),
    adaptive_vb_max_iter_grid = app_joint_qdesn_parse_numeric_vector(
      row$adaptive_vb_max_iter_grid[[1L]], "Phase151 adaptive VB grid", allow_inf = FALSE
    ),
    vb_tol = as.numeric(row$vb_tol[[1L]]),
    rhs_vb_inner = as.integer(row$rhs_vb_inner[[1L]]),
    tau0 = as.numeric(row$tau0[[1L]]),
    zeta2 = as.numeric(row$zeta2[[1L]]),
    a_sigma = as.numeric(row$a_sigma[[1L]]),
    b_sigma = as.numeric(row$b_sigma[[1L]]),
    alpha_prior_sd = row$alpha_prior_sd[[1L]],
    alpha_min_spacing = as.numeric(row$alpha_min_spacing[[1L]]),
    gamma_init_policy = row$gamma_init_policy[[1L]],
    review_adjustment_threshold = as.numeric(row$review_adjustment_threshold[[1L]]),
    max_dense_dim = as.integer(row$max_dense_dim[[1L]]),
    n_cores = 1L
  )
}

app_joint_exqdesn_phase151_scale_params <- function(X, reference) {
  center <- colMeans(X[reference, , drop = FALSE])
  scale <- apply(X[reference, , drop = FALSE], 2L, stats::sd)
  scale[!is.finite(scale) | scale <= 1.0e-10] <- 1
  names(center) <- colnames(X)
  names(scale) <- colnames(X)
  list(columns = colnames(X), center = center, scale = scale, standardize = TRUE)
}

app_joint_exqdesn_phase151_matrix_diagnostics <- function(Z) {
  Z <- as.matrix(Z)
  storage.mode(Z) <- "double"
  finite <- all(is.finite(Z))
  sds <- if (finite && ncol(Z)) apply(Z, 2L, stats::sd) else numeric()
  live <- is.finite(sds) & sds > 1.0e-8
  singular <- if (finite && any(live)) {
    tryCatch(svd(scale(Z[, live, drop = FALSE], center = TRUE, scale = TRUE), nu = 0, nv = 0)$d,
      error = function(e) numeric()
    )
  } else {
    numeric()
  }
  singular <- singular[is.finite(singular)]
  max_s <- if (length(singular)) max(singular) else NA_real_
  min_s <- if (length(singular)) min(singular) else NA_real_
  rank <- if (length(singular) && max_s > 0) sum(singular > 1.0e-8 * max_s) else 0L
  condition <- if (is.finite(min_s) && min_s > 1.0e-12) max_s / min_s else Inf
  list(
    finite = finite,
    dead_fraction = if (length(sds)) mean(!live) else 1,
    live_feature_count = sum(live),
    effective_rank = rank,
    rank_fraction = if (sum(live)) rank / sum(live) else 0,
    condition_number = condition
  )
}

app_joint_exqdesn_phase151_transform_design <- function(artifacts, candidate) {
  scenario_id <- candidate$scenario_id[[1L]]
  block <- artifacts$design[artifacts$design$scenario_id == scenario_id, , drop = FALSE]
  block <- block[order(block$full_time_index), , drop = FALSE]
  feature_cols <- app_joint_qdesn_feature_cols(block)
  X <- as.matrix(block[, feature_cols, drop = FALSE])
  storage.mode(X) <- "double"
  if (!all(is.finite(X))) stop("Phase151 base design contains nonfinite values.", call. = FALSE)
  reference <- block$role %in% c("desn_washout", "fit")
  fit_idx <- block$role == "fit"
  if (sum(reference) != 1000L || sum(fit_idx) != 500L) {
    stop("Phase151 scaling reference does not match the frozen 500/500 washout-fit contract.", call. = FALSE)
  }

  design_class <- candidate$design_class[[1L]]
  if (identical(design_class, "direct")) {
    diagnostic <- app_joint_exqdesn_phase151_matrix_diagnostics(X[fit_idx, , drop = FALSE])
    return(list(
      design = block,
      diagnostic = data.frame(
        candidate_id = candidate$candidate_id[[1L]],
        scenario_id = scenario_id,
        design_class = design_class,
        base_feature_count = ncol(X),
        reservoir_width = 0L,
        readout_feature_count = ncol(X),
        scaling_reference_rows = sum(reference),
        fit_diagnostic_rows = sum(fit_idx),
        target_spectral_radius = NA_real_,
        actual_spectral_radius = NA_real_,
        leaky_effective_radius = NA_real_,
        state_saturation_fraction = NA_real_,
        state_dead_fraction = diagnostic$dead_fraction,
        state_live_feature_count = diagnostic$live_feature_count,
        state_effective_rank = diagnostic$effective_rank,
        state_rank_fraction = diagnostic$rank_fraction,
        state_condition_number = diagnostic$condition_number,
        finite_design = diagnostic$finite,
        feature_names = paste(feature_cols, collapse = ","),
        stringsAsFactors = FALSE
      )
    ))
  }

  scale_params <- app_joint_exqdesn_phase151_scale_params(X, reference)
  X_scaled <- app_qdesn_reservoir_scale_inputs(X, scale_params = scale_params)$X
  width <- as.integer(candidate$reservoir_width[[1L]])
  cfg <- list(reservoir = list(
    D = 1L,
    n = width,
    n_tilde = integer(0),
    m = ncol(X),
    alpha = as.numeric(candidate$reservoir_alpha[[1L]]),
    rho = as.numeric(candidate$reservoir_rho[[1L]]),
    pi_w = as.numeric(candidate$reservoir_pi_w[[1L]]),
    pi_in = as.numeric(candidate$reservoir_pi_in[[1L]]),
    w_dist = "uniform",
    in_dist = "uniform",
    act_f = "tanh",
    act_k = "identity"
  ))
  reservoir <- app_qdesn_generate_article_reservoir(
    cfg,
    seed = as.integer(candidate$reservoir_seed[[1L]]),
    m_input = ncol(X_scaled)
  )
  meta <- list(
    standardize_inputs = FALSE,
    lag_center = rep(0, ncol(X_scaled)),
    lag_scale = rep(1, ncol(X_scaled)),
    input_bound = "none",
    win_scale_global = as.numeric(candidate$input_scale[[1L]]),
    win_scale_bias = as.numeric(candidate$input_scale[[1L]])
  )
  states_raw <- app_qdesn_roll_article_reservoir(X_scaled, reservoir, meta)$X_all
  state_center <- colMeans(states_raw[fit_idx, , drop = FALSE])
  state_scale <- apply(states_raw[fit_idx, , drop = FALSE], 2L, stats::sd)
  state_scale[!is.finite(state_scale) | state_scale <= 1.0e-10] <- 1
  states <- sweep(sweep(states_raw, 2L, state_center, "-"), 2L, state_scale, "/")
  colnames(states) <- paste0("reservoir_", sprintf("%03d", seq_len(ncol(states))))
  Z <- if (identical(design_class, "reservoir")) {
    states
  } else if (identical(design_class, "hybrid")) {
    cbind(X, states)
  } else {
    stop(sprintf("Unsupported Phase151 design class '%s'.", design_class), call. = FALSE)
  }
  colnames(Z) <- make.unique(colnames(Z))
  meta_cols <- app_joint_qdesn_metadata_columns()
  design <- cbind(block[, meta_cols, drop = FALSE], as.data.frame(Z, check.names = FALSE))
  diagnostic <- app_joint_exqdesn_phase151_matrix_diagnostics(Z[fit_idx, , drop = FALSE])
  W <- reservoir$W[[1L]]
  alpha <- as.numeric(reservoir$alpha[[1L]])
  leaky <- (1 - alpha) * diag(nrow(W)) + alpha * W
  list(
    design = design,
    diagnostic = data.frame(
      candidate_id = candidate$candidate_id[[1L]],
      scenario_id = scenario_id,
      design_class = design_class,
      base_feature_count = ncol(X),
      reservoir_width = width,
      readout_feature_count = ncol(Z),
      scaling_reference_rows = sum(reference),
      fit_diagnostic_rows = sum(fit_idx),
      target_spectral_radius = as.numeric(candidate$reservoir_rho[[1L]]),
      actual_spectral_radius = app_qdesn_spectral_radius(W),
      leaky_effective_radius = app_qdesn_spectral_radius(leaky),
      state_saturation_fraction = mean(abs(states_raw[fit_idx, , drop = FALSE]) > 0.99),
      state_dead_fraction = diagnostic$dead_fraction,
      state_live_feature_count = diagnostic$live_feature_count,
      state_effective_rank = diagnostic$effective_rank,
      state_rank_fraction = diagnostic$rank_fraction,
      state_condition_number = diagnostic$condition_number,
      finite_design = diagnostic$finite,
      feature_names = paste(colnames(Z), collapse = ","),
      stringsAsFactors = FALSE
    )
  )
}

app_joint_exqdesn_phase151_window_summary <- function(
  scored,
  raw_crossing_pairs,
  contract_crossing_pairs,
  adjustments,
  window
) {
  hit <- aggregate(hit ~ tau, scored, mean)
  crps <- app_joint_qdesn_crps_grid_summary(scored, "qhat")
  data.frame(
    validation_window = window,
    n_quantile_scores = nrow(scored),
    truth_mae = mean(scored$truth_abs_error),
    truth_rmse = sqrt(mean(scored$truth_sq_error)),
    truth_bias = mean(scored$truth_error),
    check_loss_mean = mean(scored$check_loss),
    crps_grid_mean = if (nrow(crps)) crps$crps_grid_mean[[1L]] else NA_real_,
    max_abs_hit_rate_error = max(abs(hit$hit - hit$tau)),
    raw_crossing_pairs = as.integer(raw_crossing_pairs),
    contract_crossing_pairs = as.integer(contract_crossing_pairs),
    max_abs_adjustment = if (length(adjustments)) max(abs(adjustments)) else 0,
    adjustment_rate = if (length(adjustments)) mean(abs(adjustments) > 1.0e-10) else 0,
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase151_tau_summary <- function(scored, candidate_id, window) {
  rows <- lapply(split(scored, scored$tau), function(block) {
    data.frame(
      candidate_id = candidate_id,
      scenario_id = block$scenario_id[[1L]],
      validation_window = window,
      tau = block$tau[[1L]],
      n_scores = nrow(block),
      truth_mae = mean(block$truth_abs_error),
      truth_rmse = sqrt(mean(block$truth_sq_error)),
      truth_bias = mean(block$truth_error),
      check_loss_mean = mean(block$check_loss),
      hit_rate = mean(block$hit),
      hit_rate_error = mean(block$hit) - block$tau[[1L]],
      abs_hit_rate_error = abs(mean(block$hit) - block$tau[[1L]]),
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase151_evaluate_candidate <- function(artifacts, candidate) {
  transformed <- app_joint_exqdesn_phase151_transform_design(artifacts, candidate)
  local_artifacts <- artifacts
  local_artifacts$design <- transformed$design
  fixture <- app_joint_qdesn_scenario_fixture(
    local_artifacts, candidate$scenario_id[[1L]], role = "fit"
  )
  controls <- app_joint_exqdesn_phase151_controls(candidate)
  spec <- app_joint_qdesn_filter_model_specs("joint_exqdesn_rhs_vb")
  meta <- data.frame(
    scenario_id = candidate$scenario_id[[1L]],
    scenario_class = fixture$scenario_meta$scenario_class[[1L]],
    distribution_family = fixture$scenario_meta$distribution_family[[1L]],
    dynamics_class = fixture$scenario_meta$dynamics_class[[1L]],
    model_id = spec$model_id[[1L]],
    display_label = spec$display_label[[1L]],
    likelihood = spec$likelihood[[1L]],
    fit_structure = spec$fit_structure[[1L]],
    inference = spec$inference[[1L]],
    experiment_id = candidate$candidate_id[[1L]],
    stringsAsFactors = FALSE
  )

  start <- proc.time()[["elapsed"]]
  fit <- app_joint_qdesn_fit_model_adaptive(fixture, spec, controls)
  fit_seconds <- proc.time()[["elapsed"]] - start
  fit_raw <- app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau)
  fit_contract <- app_joint_qdesn_apply_monotone_contract(fit_raw, fixture$tau)
  fit_rows <- app_joint_qdesn_quantile_long_rows(
    meta, fixture$row_meta, fixture$tau, fixture$y, fixture$true_q,
    fit_contract$qhat_contract, "qhat"
  )
  fit_scored <- app_joint_qdesn_quantile_scores(fit_rows, "qhat")
  fit_summary <- app_joint_exqdesn_phase151_window_summary(
    fit_scored,
    sum(fit_contract$raw_crossing$n_crossing_pairs),
    sum(fit_contract$contract_crossing$n_crossing_pairs),
    fit_contract$adjustment,
    "fit"
  )

  origin_plan <- local_artifacts$forecast_origin_plan[
    local_artifacts$forecast_origin_plan$scenario_id == candidate$scenario_id[[1L]], ,
    drop = FALSE
  ]
  origin_plan <- origin_plan[order(origin_plan$origin_index), , drop = FALSE]
  forecast_scored <- list()
  forecast_adjustments <- numeric()
  raw_pairs <- contract_pairs <- 0L
  forecast_start <- proc.time()[["elapsed"]]
  for (jj in seq_len(nrow(origin_plan))) {
    target <- app_joint_qdesn_forecast_target_fixture(
      local_artifacts, candidate$scenario_id[[1L]], origin_plan[jj, , drop = FALSE]
    )
    if (!identical(fixture$feature_cols, target$feature_cols)) {
      stop("Phase151 feature columns changed between fit and forecast.", call. = FALSE)
    }
    raw <- app_joint_qdesn_predict_fit(fit, target$Z, target$tau)
    contract <- app_joint_qdesn_apply_monotone_contract(raw, target$tau)
    rows <- app_joint_qdesn_quantile_long_rows(
      meta, target$row_meta, target$tau, target$y, target$true_q,
      contract$qhat_contract, "qhat"
    )
    forecast_scored[[jj]] <- app_joint_qdesn_quantile_scores(rows, "qhat")
    forecast_adjustments <- c(forecast_adjustments, as.numeric(contract$adjustment))
    raw_pairs <- raw_pairs + sum(contract$raw_crossing$n_crossing_pairs)
    contract_pairs <- contract_pairs + sum(contract$contract_crossing$n_crossing_pairs)
  }
  forecast_seconds <- proc.time()[["elapsed"]] - forecast_start
  forecast_scored <- app_joint_qdesn_bind_rows(forecast_scored)
  forecast_summary <- app_joint_exqdesn_phase151_window_summary(
    forecast_scored, raw_pairs, contract_pairs, forecast_adjustments, "forecast"
  )

  trace <- fit$trace %||% data.frame()
  rhs <- fit$rhs_prior_summary %||% data.frame()
  trace_numeric <- trace[vapply(trace, is.numeric, logical(1L))]
  rhs_numeric <- rhs[vapply(rhs, is.numeric, logical(1L))]
  finite_trace <- nrow(trace) > 0L && all(is.finite(as.matrix(trace_numeric)))
  finite_rhs <- nrow(rhs) > 0L && all(is.finite(as.matrix(rhs_numeric)))
  finite_sigma <- all(is.finite(fit$sigma_mean)) && all(fit$sigma_mean > 0)
  finite_gamma <- !is.null(fit$gamma_mean) && all(is.finite(fit$gamma_mean))
  finite_scores <- all(is.finite(c(
    fit_scored$qhat, fit_scored$check_loss, fit_scored$truth_error,
    forecast_scored$qhat, forecast_scored$check_loss, forecast_scored$truth_error
  )))
  dimension <- ncol(fixture$Z) * length(fixture$tau)
  design_diag <- transformed$diagnostic
  design_fail <- !isTRUE(design_diag$finite_design[[1L]]) ||
    design_diag$state_dead_fraction[[1L]] > 0.30 ||
    dimension > controls$max_dense_dim
  design_rank_review <- design_diag$state_rank_fraction[[1L]] < 1 - 1.0e-10 ||
    !is.finite(design_diag$state_condition_number[[1L]]) ||
    design_diag$state_condition_number[[1L]] > 1.0e6
  hard_fail <- !finite_trace || !finite_rhs || !finite_sigma || !finite_gamma ||
    !finite_scores || design_fail ||
    fit_summary$contract_crossing_pairs[[1L]] > 0L ||
    forecast_summary$contract_crossing_pairs[[1L]] > 0L
  review <- !hard_fail && (
    !isTRUE(fit$converged) ||
      fit_summary$raw_crossing_pairs[[1L]] > 0L ||
      forecast_summary$raw_crossing_pairs[[1L]] > 0L ||
      max(fit_summary$max_abs_adjustment, forecast_summary$max_abs_adjustment) >
        controls$review_adjustment_threshold ||
      design_diag$state_dead_fraction[[1L]] > 0.10 ||
      design_rank_review
  )
  reasons <- c(
    if (!finite_trace) "nonfinite or missing VB trace",
    if (!finite_rhs) "nonfinite or missing RHS summary",
    if (!finite_sigma) "nonfinite or nonpositive sigma",
    if (!finite_gamma) "nonfinite gamma",
    if (!finite_scores) "nonfinite quantiles or scores",
    if (design_fail) "feature design failed finite/rank/dimension gates",
    if (fit_summary$contract_crossing_pairs[[1L]] > 0L) "fit contract quantiles cross",
    if (forecast_summary$contract_crossing_pairs[[1L]] > 0L) "forecast contract quantiles cross",
    if (!hard_fail && !isTRUE(fit$converged)) "VB reached its adaptive iteration limit",
    if (!hard_fail && (fit_summary$raw_crossing_pairs[[1L]] +
      forecast_summary$raw_crossing_pairs[[1L]]) > 0L) "raw quantiles required monotone repair",
    if (!hard_fail && design_diag$state_dead_fraction[[1L]] > 0.10) "readout feature dead fraction is review-level",
    if (!hard_fail && design_rank_review) "feature rank or conditioning is review-level"
  )

  names(fit_summary)[-1L] <- paste0("fit_", names(fit_summary)[-1L])
  names(forecast_summary)[-1L] <- paste0("forecast_", names(forecast_summary)[-1L])
  candidate_summary <- cbind(
    candidate[, c(
      "candidate_id", "scenario_id", "scenario_role", "model_id",
      "source_phase150_candidate_id", "design_role", "design_class",
      "reservoir_width", "reservoir_alpha", "reservoir_rho",
      "reservoir_pi_w", "input_scale", "reservoir_seed",
      "tau0", "zeta2", "alpha_prior_sd", "gamma_init_policy"
    ), drop = FALSE],
    data.frame(
      readout_feature_count = ncol(fixture$Z),
      quantile_count = length(fixture$tau),
      dense_dimension = dimension,
      gate_status = if (hard_fail) "fail" else if (review) "review" else "pass",
      implementation_status = if (hard_fail) "fail" else "pass",
      vb_converged = isTRUE(fit$converged),
      vb_reached_max_iter = !isTRUE(fit$converged),
      finite_trace = finite_trace,
      finite_rhs = finite_rhs,
      finite_sigma = finite_sigma,
      finite_gamma = finite_gamma,
      finite_scores = finite_scores,
      stringsAsFactors = FALSE
    ),
    fit_summary[, setdiff(names(fit_summary), "validation_window"), drop = FALSE],
    forecast_summary[, setdiff(names(forecast_summary), "validation_window"), drop = FALSE],
    data.frame(
      fit_elapsed_seconds = fit_seconds,
      forecast_scoring_seconds = forecast_seconds,
      total_elapsed_seconds = fit_seconds + forecast_seconds,
      status_reason = if (length(reasons)) paste(unique(reasons), collapse = "; ") else "all Phase151 candidate gates passed",
      stringsAsFactors = FALSE
    )
  )
  vb_diagnostics <- data.frame(
    candidate_id = candidate$candidate_id[[1L]],
    scenario_id = candidate$scenario_id[[1L]],
    converged = isTRUE(fit$converged),
    reached_max_iter = !isTRUE(fit$converged),
    adaptive_vb_attempts = attr(fit, "adaptive_vb_attempts") %||% as.character(controls$vb_max_iter),
    adaptive_vb_max_iter_used = attr(fit, "adaptive_vb_max_iter_used") %||% controls$vb_max_iter,
    trace_rows = nrow(trace),
    final_iter = if (nrow(trace) && "iter" %in% names(trace)) max(trace$iter) else NA_integer_,
    final_monitor = if (nrow(trace) && "monitor" %in% names(trace)) tail(trace$monitor, 1L) else NA_real_,
    sigma_min = min(fit$sigma_mean),
    sigma_median = stats::median(fit$sigma_mean),
    sigma_max = max(fit$sigma_mean),
    gamma_min = min(fit$gamma_mean),
    gamma_median = stats::median(fit$gamma_mean),
    gamma_max = max(fit$gamma_mean),
    finite_trace = finite_trace,
    finite_rhs = finite_rhs,
    stringsAsFactors = FALSE
  )
  tau_summary <- rbind(
    app_joint_exqdesn_phase151_tau_summary(fit_scored, candidate$candidate_id[[1L]], "fit"),
    app_joint_exqdesn_phase151_tau_summary(forecast_scored, candidate$candidate_id[[1L]], "forecast")
  )
  interval_summary <- app_joint_qdesn_bind_rows(list(
    transform(
      app_joint_qdesn_interval_summary(fit_scored, "qhat"),
      candidate_id = candidate$candidate_id[[1L]], validation_window = "fit"
    ),
    transform(
      app_joint_qdesn_interval_summary(forecast_scored, "qhat"),
      candidate_id = candidate$candidate_id[[1L]], validation_window = "forecast"
    )
  ))
  list(
    candidate_summary = candidate_summary,
    tau_summary = tau_summary,
    interval_summary = interval_summary,
    design_diagnostics = transformed$diagnostic,
    vb_diagnostics = vb_diagnostics
  )
}

app_joint_exqdesn_phase151_candidate_dir <- function(out_dir, candidate_id) {
  file.path(out_dir, "candidates", candidate_id)
}

app_joint_exqdesn_phase151_verify_candidate_dir <- function(candidate_dir) {
  manifest_path <- file.path(candidate_dir, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) return(FALSE)
  manifest <- tryCatch(app_read_csv(manifest_path), error = function(e) data.frame())
  if (!all(c("relative_path", "size_bytes", "sha256") %in% names(manifest)) || !nrow(manifest)) {
    return(FALSE)
  }
  all(vapply(seq_len(nrow(manifest)), function(ii) {
    path <- file.path(candidate_dir, manifest$relative_path[[ii]])
    file.exists(path) &&
      identical(as.numeric(file.info(path)$size), as.numeric(manifest$size_bytes[[ii]])) &&
      identical(tolower(app_sha256_file(path)), tolower(manifest$sha256[[ii]]))
  }, logical(1L)))
}

app_joint_exqdesn_phase151_write_candidate <- function(result, out_dir, candidate_id) {
  final_dir <- app_joint_exqdesn_phase151_candidate_dir(out_dir, candidate_id)
  app_ensure_dir(dirname(final_dir))
  if (app_joint_exqdesn_phase151_verify_candidate_dir(final_dir)) return(final_dir)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".invalid.", format(Sys.time(), "%Y%m%d%H%M%S"))
    if (!file.rename(final_dir, quarantine)) {
      stop(sprintf("Could not quarantine incomplete candidate directory: %s", final_dir), call. = FALSE)
    }
  }
  tmp_dir <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp_dir)) unlink(tmp_dir, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp_dir)
  readme_path <- file.path(tmp_dir, "README.md")
  writeLines(c(
    "# Phase151 Candidate Checkpoint",
    "",
    sprintf("- Candidate: `%s`", candidate_id),
    sprintf("- Scenario: `%s`", result$candidate_summary$scenario_id[[1L]]),
    sprintf("- Design: `%s`", result$candidate_summary$design_role[[1L]]),
    sprintf("- Gate: `%s`", result$candidate_summary$gate_status[[1L]]),
    "",
    "This compact checkpoint contains summary evidence only. It does not retain raw fit objects."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    candidate_summary = app_joint_qvp_write_csv(
      result$candidate_summary, file.path(tmp_dir, "candidate_summary.csv")
    ),
    tau_summary = app_joint_qvp_write_csv(
      result$tau_summary, file.path(tmp_dir, "tau_summary.csv")
    ),
    interval_summary = app_joint_qvp_write_csv(
      result$interval_summary, file.path(tmp_dir, "interval_summary.csv")
    ),
    design_diagnostics = app_joint_qvp_write_csv(
      result$design_diagnostics, file.path(tmp_dir, "design_diagnostics.csv")
    ),
    vb_diagnostics = app_joint_qvp_write_csv(
      result$vb_diagnostics, file.path(tmp_dir, "vb_diagnostics.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(manifest, file.path(tmp_dir, "artifact_manifest.csv"))
  if (!file.rename(tmp_dir, final_dir)) {
    stop(sprintf("Could not atomically promote candidate checkpoint: %s", candidate_id), call. = FALSE)
  }
  if (!app_joint_exqdesn_phase151_verify_candidate_dir(final_dir)) {
    stop(sprintf("Candidate checkpoint verification failed after promotion: %s", candidate_id), call. = FALSE)
  }
  final_dir
}

app_joint_exqdesn_phase151_load_completed <- function(out_dir, registry) {
  rows <- lapply(seq_len(nrow(registry)), function(ii) {
    candidate_id <- registry$candidate_id[[ii]]
    dir <- app_joint_exqdesn_phase151_candidate_dir(out_dir, candidate_id)
    if (!app_joint_exqdesn_phase151_verify_candidate_dir(dir)) return(NULL)
    list(
      candidate_summary = app_read_csv(file.path(dir, "candidate_summary.csv")),
      tau_summary = app_read_csv(file.path(dir, "tau_summary.csv")),
      interval_summary = app_read_csv(file.path(dir, "interval_summary.csv")),
      design_diagnostics = app_read_csv(file.path(dir, "design_diagnostics.csv")),
      vb_diagnostics = app_read_csv(file.path(dir, "vb_diagnostics.csv"))
    )
  })
  rows[!vapply(rows, is.null, logical(1L))]
}

app_joint_exqdesn_phase151_rank_candidates <- function(candidate_summary) {
  rows <- lapply(split(candidate_summary, candidate_summary$scenario_id), function(block) {
    baseline <- block[block$design_role == "direct_phase150_parity", , drop = FALSE]
    if (nrow(baseline) != 1L) stop("Phase151 ranking requires one direct parity anchor per scenario.", call. = FALSE)
    block$delta_forecast_mae_vs_direct_vb <-
      block$forecast_truth_mae - baseline$forecast_truth_mae[[1L]]
    block$delta_fit_mae_vs_direct_vb <-
      block$fit_truth_mae - baseline$fit_truth_mae[[1L]]
    block$delta_check_loss_vs_direct_vb <-
      block$forecast_check_loss_mean - baseline$forecast_check_loss_mean[[1L]]
    block$parity_forecast_abs_error <-
      abs(baseline$forecast_truth_mae[[1L]] - baseline$phase149_vb_forecast_truth_mae[[1L]])
    block$parity_fit_abs_error <-
      abs(baseline$fit_truth_mae[[1L]] - baseline$phase149_vb_fit_truth_mae[[1L]])
    block$practical_gain_threshold <- max(0.0025, 0.02 * baseline$forecast_truth_mae[[1L]])
    block$material_forecast_gain <- block$delta_forecast_mae_vs_direct_vb <=
      -block$practical_gain_threshold
    block$fit_guard_pass <- block$fit_truth_mae <=
      1.05 * baseline$fit_truth_mae[[1L]] + 1.0e-8
    block$score_guard_pass <- block$forecast_check_loss_mean <=
      1.02 * baseline$forecast_check_loss_mean[[1L]] + 1.0e-8
    block$eligible_for_mcmc <- block$design_role != "direct_phase150_parity" &
      block$implementation_status == "pass" &
      block$material_forecast_gain &
      block$fit_guard_pass &
      block$score_guard_pass
    block$stability_penalty <- as.integer(block$gate_status != "pass") +
      as.integer(block$vb_reached_max_iter) +
      as.integer(block$forecast_raw_crossing_pairs > 0)
    block <- block[order(
      block$implementation_status == "fail",
      !block$eligible_for_mcmc,
      block$stability_penalty,
      block$forecast_truth_mae,
      block$forecast_check_loss_mean,
      block$fit_truth_mae,
      block$candidate_id
    ), , drop = FALSE]
    block$phase151_rank <- seq_len(nrow(block))
    block
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase151_selection <- function(ranking) {
  scenario_rows <- list()
  mcmc_rows <- list()
  for (scenario_id in sort(unique(ranking$scenario_id))) {
    block <- ranking[ranking$scenario_id == scenario_id, , drop = FALSE]
    baseline <- block[block$design_role == "direct_phase150_parity", , drop = FALSE]
    eligible <- block[block$eligible_for_mcmc, , drop = FALSE]
    if (nrow(eligible)) {
      eligible <- eligible[order(
        eligible$stability_penalty, eligible$forecast_truth_mae,
        eligible$forecast_check_loss_mean, eligible$fit_truth_mae
      ), , drop = FALSE]
      selected <- eligible[1L, , drop = FALSE]
      decision <- "new_design_ready_for_mcmc_confirmation"
      mcmc_rows[[length(mcmc_rows) + 1L]] <- data.frame(
        scenario_id = scenario_id,
        candidate_id = selected$candidate_id[[1L]],
        design_role = selected$design_role[[1L]],
        design_class = selected$design_class[[1L]],
        reservoir_width = selected$reservoir_width[[1L]],
        reservoir_alpha = selected$reservoir_alpha[[1L]],
        reservoir_rho = selected$reservoir_rho[[1L]],
        reservoir_seed = selected$reservoir_seed[[1L]],
        forecast_truth_mae = selected$forecast_truth_mae[[1L]],
        fit_truth_mae = selected$fit_truth_mae[[1L]],
        delta_forecast_mae_vs_direct_vb = selected$delta_forecast_mae_vs_direct_vb[[1L]],
        n_chains_recommended = 8L,
        initialization = "phase151_candidate_specific_vb",
        launch_status = "not_launched_phase151_vb_only",
        stringsAsFactors = FALSE
      )
    } else {
      selected <- baseline
      decision <- if (baseline$scenario_role[[1L]] == "frozen_success_control") {
        "retain_phase150_success_control"
      } else {
        "no_new_design_cleared_practical_gain_and_guard_gates"
      }
    }
    scenario_rows[[length(scenario_rows) + 1L]] <- data.frame(
      scenario_id = scenario_id,
      scenario_role = baseline$scenario_role[[1L]],
      candidates_evaluated = nrow(block),
      implementation_failures = sum(block$implementation_status == "fail"),
      eligible_new_designs = nrow(eligible),
      selected_candidate_id = selected$candidate_id[[1L]],
      selected_design_role = selected$design_role[[1L]],
      selected_forecast_truth_mae = selected$forecast_truth_mae[[1L]],
      direct_vb_forecast_truth_mae = baseline$forecast_truth_mae[[1L]],
      phase150_exal_mcmc_forecast_truth_mae = baseline$phase150_mcmc_forecast_truth_mae[[1L]],
      article_joint_al_forecast_truth_mae = baseline$article_joint_al_forecast_truth_mae[[1L]],
      selection_decision = decision,
      stringsAsFactors = FALSE
    )
  }
  list(
    scenario_summary = app_joint_qdesn_bind_rows(scenario_rows),
    mcmc_plan = if (length(mcmc_rows)) {
      app_joint_qdesn_bind_rows(mcmc_rows)
    } else {
      data.frame(
        scenario_id = character(), candidate_id = character(),
        design_role = character(), design_class = character(),
        reservoir_width = integer(), reservoir_alpha = numeric(),
        reservoir_rho = numeric(), reservoir_seed = integer(),
        forecast_truth_mae = numeric(), fit_truth_mae = numeric(),
        delta_forecast_mae_vs_direct_vb = numeric(),
        n_chains_recommended = integer(), initialization = character(),
        launch_status = character(), stringsAsFactors = FALSE
      )
    }
  )
}

app_joint_exqdesn_run_phase151_readiness <- function(
  out_dir = app_joint_exqdesn_phase151_default_readiness_dir(),
  screening_dir = app_joint_exqdesn_phase151_default_dir(),
  fixture_dir = app_joint_exqdesn_phase151_default_fixture_dir(),
  phase150_freeze_dir = app_joint_exqdesn_phase151_default_phase150_freeze_dir(),
  phase150_audit_dir = app_joint_exqdesn_phase151_default_phase150_audit_dir()
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  source_manifest <- app_joint_exqdesn_phase151_source_manifest(
    fixture_dir, phase150_freeze_dir, phase150_audit_dir
  )
  controls <- app_read_csv(file.path(phase150_freeze_dir, "case_winner_controls.csv"))
  comparison <- app_read_csv(file.path(phase150_audit_dir, "phase150_mcmc_article_comparison.csv"))
  scenario_summary <- app_read_csv(file.path(fixture_dir, "scenario_summary.csv"))
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  registry <- app_joint_exqdesn_phase151_build_registry(controls, comparison)
  dense <- app_joint_exqdesn_phase151_validate_dense_dimensions(registry, scenario_summary)
  design_preflight <- app_joint_exqdesn_phase151_preflight_designs(registry, artifacts)
  novelty <- app_joint_exqdesn_phase151_prior_experiment_audit()
  source_fail <- any(!source_manifest$verified)
  dense_fail <- any(dense$status == "fail")
  design_fail <- any(design_preflight$preflight_status == "fail")
  assessment <- data.frame(
    readiness_id = "phase151_case_specific_feature_design_screening",
    gate_status = if (source_fail || dense_fail || design_fail) "fail" else "pass",
    candidate_count = nrow(registry),
    scenario_count = length(unique(registry$scenario_id)),
    optimization_scenarios = length(unique(registry$scenario_id[registry$scenario_role == "optimization_target"])),
    frozen_success_controls = sum(registry$scenario_role == "frozen_success_control"),
    source_hash_failures = sum(!source_manifest$verified),
    dense_dimension_failures = sum(dense$status == "fail"),
    design_preflight_failures = sum(design_preflight$preflight_status == "fail"),
    design_preflight_reviews = sum(design_preflight$preflight_status == "review"),
    prior_dimensions_repeated = sum(novelty$repeated_in_phase151),
    global_specification_selected = FALSE,
    mcmc_launched = FALSE,
    recommendation = if (source_fail || dense_fail || design_fail) {
      "fix_readiness_failures_before_launch"
    } else {
      "launch_full_phase151_case_specific_vb_feature_screen"
    },
    stringsAsFactors = FALSE
  )
  run_config <- data.frame(
    run_id = "joint_qdesn_phase151_case_specific_feature_screening",
    screening_dir = app_prefer_repo_relative_path(screening_dir),
    fixture_dir = app_prefer_repo_relative_path(fixture_dir),
    phase150_freeze_dir = app_prefer_repo_relative_path(phase150_freeze_dir),
    phase150_audit_dir = app_prefer_repo_relative_path(phase150_audit_dir),
    candidate_count = nrow(registry),
    workers_recommended = 8L,
    candidate_checkpointing = TRUE,
    actual_fixture_design_preflight = TRUE,
    incomplete_only_resume = TRUE,
    raw_fit_objects_retained = FALSE,
    forecast_protocol = "single_fit_no_refit_frozen_target_design",
    selection_scope = "within_scenario",
    stringsAsFactors = FALSE
  )
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase151 Readiness",
    "",
    "Phase151 is a case-specific frozen-feature reservoir screen. It does not repeat gamma, RHS, tau0, initialization, chain-count, or posterior-summary experiments.",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Candidates: %d across eight scenarios", nrow(registry)),
    "- Seven losing scenarios receive one direct parity anchor and four new reservoir designs.",
    "- Persistent Heavy Tail is retained as a direct-feature success control.",
    sprintf(
      "- Full-fixture design preflight: %d failures and %d review-level rank/conditioning flags.",
      sum(design_preflight$preflight_status == "fail"),
      sum(design_preflight$preflight_status == "review")
    ),
    "- No MCMC or article update occurs in this phase."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    candidate_registry = app_joint_qvp_write_csv(
      registry, file.path(out_dir, "phase151_candidate_registry.csv")
    ),
    prior_experiment_novelty_audit = app_joint_qvp_write_csv(
      novelty, file.path(out_dir, "phase151_prior_experiment_novelty_audit.csv")
    ),
    source_manifest_verification = app_joint_qvp_write_csv(
      source_manifest, file.path(out_dir, "phase151_source_manifest_verification.csv")
    ),
    dense_dimension_audit = app_joint_qvp_write_csv(
      dense, file.path(out_dir, "phase151_dense_dimension_audit.csv")
    ),
    design_preflight = app_joint_qvp_write_csv(
      design_preflight, file.path(out_dir, "phase151_design_preflight.csv")
    ),
    readiness_assessment = app_joint_qvp_write_csv(
      assessment, file.path(out_dir, "phase151_readiness_assessment.csv")
    ),
    run_config = app_joint_qvp_write_csv(
      run_config, file.path(out_dir, "phase151_run_config.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    registry = registry,
    assessment = assessment,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_phase151_aggregate <- function(
  out_dir,
  readiness_dir = app_joint_exqdesn_phase151_default_readiness_dir()
) {
  registry <- app_read_csv(file.path(readiness_dir, "phase151_candidate_registry.csv"))
  completed <- app_joint_exqdesn_phase151_load_completed(out_dir, registry)
  if (!length(completed)) stop("No complete Phase151 candidate checkpoints are available.", call. = FALSE)
  candidate_summary <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "candidate_summary"))
  candidate_summary <- merge(
    candidate_summary,
    registry[, c(
      "candidate_id", "phase149_vb_forecast_truth_mae", "phase149_vb_fit_truth_mae",
      "phase150_mcmc_forecast_truth_mae", "phase150_mcmc_fit_truth_mae",
      "article_joint_al_forecast_truth_mae", "article_joint_al_fit_truth_mae"
    ), drop = FALSE],
    by = "candidate_id", all.x = TRUE, sort = FALSE
  )
  tau_summary <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "tau_summary"))
  interval_summary <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "interval_summary"))
  design_diagnostics <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "design_diagnostics"))
  vb_diagnostics <- app_joint_qdesn_bind_rows(lapply(completed, `[[`, "vb_diagnostics"))
  ranking <- app_joint_exqdesn_phase151_rank_candidates(candidate_summary)
  selection <- app_joint_exqdesn_phase151_selection(ranking)
  expected <- nrow(registry)
  observed <- nrow(candidate_summary)
  parity <- ranking[ranking$design_role == "direct_phase150_parity", , drop = FALSE]
  parity_fail <- any(parity$parity_forecast_abs_error > 1.0e-6) ||
    any(parity$parity_fit_abs_error > 1.0e-6)
  coverage_fail <- observed != expected ||
    length(unique(candidate_summary$candidate_id)) != expected
  source_manifest <- app_read_csv(file.path(readiness_dir, "phase151_source_manifest_verification.csv"))
  source_fail <- any(!source_manifest$verified)
  scenario_fail <- any(selection$scenario_summary$implementation_failures >=
    selection$scenario_summary$candidates_evaluated)
  assessment <- data.frame(
    audit_id = "phase151_case_specific_feature_screening",
    gate_status = if (coverage_fail || source_fail || parity_fail || scenario_fail) "fail" else "pass",
    expected_candidates = expected,
    completed_candidates = observed,
    remaining_candidates = expected - observed,
    candidate_implementation_failures = sum(candidate_summary$implementation_status == "fail"),
    direct_parity_failures = sum(
      parity$parity_forecast_abs_error > 1.0e-6 |
        parity$parity_fit_abs_error > 1.0e-6
    ),
    scenarios_with_new_mcmc_candidate = nrow(selection$mcmc_plan),
    global_specification_selected = FALSE,
    article_assets_modified = FALSE,
    recommendation = if (coverage_fail || source_fail || parity_fail || scenario_fail) {
      "fix_phase151_integrity_before_interpretation"
    } else if (nrow(selection$mcmc_plan)) {
      "review_scenario_specific_design_winners_then_freeze_for_mcmc"
    } else {
      "retain_phase150_and_do_not_repeat_feature_or_gamma_screens"
    },
    stringsAsFactors = FALSE
  )
  runtime <- candidate_summary[, c(
    "candidate_id", "scenario_id", "design_role",
    "fit_elapsed_seconds", "forecast_scoring_seconds", "total_elapsed_seconds"
  ), drop = FALSE]
  readme_path <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase151 Case-Specific Feature Screen",
    "",
    "This is the complete VB/VB-LD design-screening layer over the formal frozen fixtures.",
    "Candidate selection is performed independently within scenario; no global specification is selected.",
    sprintf("- Gate: `%s`", assessment$gate_status[[1L]]),
    sprintf("- Completed candidates: %d/%d", observed, expected),
    sprintf("- Scenarios with a new design clearing MCMC gates: %d", nrow(selection$mcmc_plan)),
    "",
    "The target rows use the frozen conditional design supplied by the formal fixtures. This is not a recursive operational forecast experiment.",
    "Raw fit objects are not retained. MCMC and manuscript promotion remain separate, explicit later stages."
  ), readme_path, useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(data.frame(
      run_id = "joint_qdesn_phase151_case_specific_feature_screening",
      readiness_dir = app_prefer_repo_relative_path(readiness_dir),
      candidates_expected = expected,
      candidates_completed = observed,
      candidate_checkpointing = TRUE,
      selection_scope = "within_scenario",
      stringsAsFactors = FALSE
    ), file.path(out_dir, "run_config.csv")),
    source_manifest_verification = app_joint_qvp_write_csv(
      source_manifest, file.path(out_dir, "source_manifest_verification.csv")
    ),
    candidate_summary = app_joint_qvp_write_csv(
      candidate_summary, file.path(out_dir, "candidate_summary.csv")
    ),
    candidate_tau_summary = app_joint_qvp_write_csv(
      tau_summary, file.path(out_dir, "candidate_tau_summary.csv")
    ),
    candidate_interval_summary = app_joint_qvp_write_csv(
      interval_summary, file.path(out_dir, "candidate_interval_summary.csv")
    ),
    design_diagnostics = app_joint_qvp_write_csv(
      design_diagnostics, file.path(out_dir, "design_diagnostics.csv")
    ),
    vb_diagnostics = app_joint_qvp_write_csv(
      vb_diagnostics, file.path(out_dir, "vb_diagnostics.csv")
    ),
    runtime_summary = app_joint_qvp_write_csv(
      runtime, file.path(out_dir, "runtime_summary.csv")
    ),
    candidate_ranking = app_joint_qvp_write_csv(
      ranking, file.path(out_dir, "candidate_ranking.csv")
    ),
    scenario_selection_summary = app_joint_qvp_write_csv(
      selection$scenario_summary, file.path(out_dir, "scenario_selection_summary.csv")
    ),
    mcmc_confirmation_plan = app_joint_qvp_write_csv(
      selection$mcmc_plan, file.path(out_dir, "mcmc_confirmation_plan.csv")
    ),
    result_assessment = app_joint_qvp_write_csv(
      assessment, file.path(out_dir, "phase151_result_assessment.csv")
    ),
    provenance = app_joint_qvp_write_csv(
      app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")
    ),
    readme = normalizePath(readme_path, mustWork = TRUE)
  )
  manifest <- app_joint_qdesn_write_manifest(paths, out_dir)
  list(
    out_dir = out_dir,
    assessment = assessment,
    ranking = ranking,
    selection = selection,
    paths = c(paths, artifact_manifest = manifest$manifest_path)
  )
}

app_joint_exqdesn_run_phase151 <- function(
  out_dir = app_joint_exqdesn_phase151_default_dir(),
  readiness_dir = app_joint_exqdesn_phase151_default_readiness_dir(),
  fixture_dir = app_joint_exqdesn_phase151_default_fixture_dir(),
  candidate_ids = NULL,
  n_cores = 8L,
  incomplete_only = TRUE
) {
  out_dir <- normalizePath(out_dir, mustWork = FALSE)
  app_ensure_dir(out_dir)
  readiness <- app_read_csv(file.path(readiness_dir, "phase151_readiness_assessment.csv"))
  if (nrow(readiness) != 1L || readiness$gate_status[[1L]] != "pass") {
    stop("Phase151 launch is blocked because readiness is not pass.", call. = FALSE)
  }
  registry <- app_read_csv(file.path(readiness_dir, "phase151_candidate_registry.csv"))
  if (!is.null(candidate_ids) && length(candidate_ids)) {
    missing <- setdiff(candidate_ids, registry$candidate_id)
    if (length(missing)) stop("Unknown Phase151 candidate ids: ", paste(missing, collapse = ", "), call. = FALSE)
    registry <- registry[match(candidate_ids, registry$candidate_id), , drop = FALSE]
  }
  if (isTRUE(incomplete_only)) {
    complete <- vapply(registry$candidate_id, function(id) {
      app_joint_exqdesn_phase151_verify_candidate_dir(
        app_joint_exqdesn_phase151_candidate_dir(out_dir, id)
      )
    }, logical(1L))
    registry_run <- registry[!complete, , drop = FALSE]
  } else {
    registry_run <- registry
  }
  artifacts <- app_joint_qdesn_load_fixture_artifacts(fixture_dir)
  if (nrow(registry_run)) {
    jobs <- split(registry_run, seq_len(nrow(registry_run)))
    results <- app_joint_qdesn_parallel_lapply(
      jobs,
      function(candidate) {
        result <- app_joint_exqdesn_phase151_evaluate_candidate(artifacts, candidate)
        dir <- app_joint_exqdesn_phase151_write_candidate(
          result, out_dir, candidate$candidate_id[[1L]]
        )
        list(candidate_id = candidate$candidate_id[[1L]], candidate_dir = dir)
      },
      n_cores = n_cores
    )
    failures <- app_joint_qdesn_worker_failure_rows(results, "phase151_feature_design_screen")
  } else {
    failures <- app_joint_qdesn_worker_failure_rows(list(), "phase151_feature_design_screen")
  }
  app_joint_qvp_write_csv(failures, file.path(out_dir, "worker_failures.csv"))
  all_registry <- app_read_csv(file.path(readiness_dir, "phase151_candidate_registry.csv"))
  complete_all <- vapply(all_registry$candidate_id, function(id) {
    app_joint_exqdesn_phase151_verify_candidate_dir(
      app_joint_exqdesn_phase151_candidate_dir(out_dir, id)
    )
  }, logical(1L))
  progress <- data.frame(
    expected_candidates = nrow(all_registry),
    completed_candidates = sum(complete_all),
    remaining_candidates = sum(!complete_all),
    worker_failures_this_invocation = nrow(failures),
    n_cores = as.integer(n_cores),
    incomplete_only = isTRUE(incomplete_only),
    status = if (all(complete_all) && !nrow(failures)) "complete" else "incomplete",
    stringsAsFactors = FALSE
  )
  app_joint_qvp_write_csv(progress, file.path(out_dir, "progress_summary.csv"))
  if (nrow(failures)) {
    stop(sprintf("Phase151 encountered %d candidate worker failure(s).", nrow(failures)), call. = FALSE)
  }
  if (!all(complete_all)) {
    stop(sprintf(
      "Phase151 is incomplete: %d/%d candidate checkpoints are complete.",
      sum(complete_all), length(complete_all)
    ), call. = FALSE)
  }
  app_joint_exqdesn_phase151_aggregate(out_dir, readiness_dir)
}

app_joint_exqdesn_phase151_health <- function(
  out_dir = app_joint_exqdesn_phase151_default_dir(),
  readiness_dir = app_joint_exqdesn_phase151_default_readiness_dir(),
  session_alive = FALSE,
  runner_process_count = 0L
) {
  registry_path <- file.path(readiness_dir, "phase151_candidate_registry.csv")
  if (!file.exists(registry_path)) {
    return(data.frame(
      phase_id = "phase151_case_specific_feature_screening",
      lifecycle_state = "not_prepared",
      expected_candidates = NA_integer_,
      completed_candidates = 0L,
      remaining_candidates = NA_integer_,
      session_alive = isTRUE(session_alive),
      runner_process_count = as.integer(runner_process_count),
      recommendation = "run_phase151_readiness",
      stringsAsFactors = FALSE
    ))
  }
  registry <- app_read_csv(registry_path)
  complete <- vapply(registry$candidate_id, function(id) {
    app_joint_exqdesn_phase151_verify_candidate_dir(
      app_joint_exqdesn_phase151_candidate_dir(out_dir, id)
    )
  }, logical(1L))
  root_complete <- file.exists(file.path(out_dir, "artifact_manifest.csv")) &&
    file.exists(file.path(out_dir, "phase151_result_assessment.csv"))
  active <- isTRUE(session_alive) || as.integer(runner_process_count) > 0L
  state <- if (active && !all(complete)) {
    "running"
  } else if (all(complete) && root_complete) {
    "complete"
  } else if (all(complete)) {
    "completed_pending_aggregation"
  } else if (any(complete)) {
    "interrupted_resumable"
  } else {
    "prepared_not_started"
  }
  recommendation <- switch(
    state,
    running = "preserve_active_run",
    complete = "review_phase151_selection_and_mcmc_plan",
    completed_pending_aggregation = "run_phase151_aggregation_only",
    interrupted_resumable = "resume_incomplete_candidates_only",
    prepared_not_started = "launch_full_phase151_screen"
  )
  data.frame(
    phase_id = "phase151_case_specific_feature_screening",
    lifecycle_state = state,
    expected_candidates = nrow(registry),
    completed_candidates = sum(complete),
    remaining_candidates = sum(!complete),
    completion_percent = round(100 * mean(complete), 1),
    session_alive = isTRUE(session_alive),
    runner_process_count = as.integer(runner_process_count),
    recommendation = recommendation,
    stringsAsFactors = FALSE
  )
}
