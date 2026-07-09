# VB-first readiness audit for the new joint QDESN simulation study.

app_joint_qdesn_default_vb_readiness_dir <- function() {
  app_path("application/cache/joint_qdesn_simulation_vb_readiness_audit_20260706")
}

app_joint_qdesn_format_tau <- function(tau) {
  paste(format(as.numeric(tau), trim = TRUE, scientific = FALSE), collapse = ",")
}

app_joint_qdesn_quantile_slug <- function(tau) {
  paste0("tau_", gsub("[^0-9]+", "p", format(as.numeric(tau), trim = TRUE, scientific = FALSE)))
}

app_joint_qdesn_bind_rows <- function(rows) {
  if (exists("app_bind_rows_fill", mode = "function")) {
    app_bind_rows_fill(rows)
  } else {
    rows <- rows[!vapply(rows, is.null, logical(1L))]
    if (!length(rows)) return(data.frame())
    all_names <- unique(unlist(lapply(rows, names), use.names = FALSE))
    rows <- lapply(rows, function(x) {
      missing <- setdiff(all_names, names(x))
      for (nm in missing) x[[nm]] <- NA
      x[, all_names, drop = FALSE]
    })
    do.call(rbind, rows)
  }
}

app_joint_qdesn_parse_numeric_vector <- function(x, label = "numeric vector", allow_inf = TRUE) {
  if (length(x) == 1L && is.character(x)) {
    vals <- trimws(strsplit(x, ",", fixed = TRUE)[[1L]])
  } else {
    vals <- as.character(unlist(x, use.names = FALSE))
  }
  vals <- vals[nzchar(vals)]
  if (!length(vals)) stop(sprintf("%s must not be empty.", label), call. = FALSE)
  out <- suppressWarnings(as.numeric(vals))
  bad <- is.na(out) & !tolower(vals) %in% c("na", "nan")
  if (any(bad) || any(is.nan(out))) {
    stop(sprintf("%s must contain numeric values.", label), call. = FALSE)
  }
  if (!allow_inf && any(!is.finite(out))) {
    stop(sprintf("%s must contain finite values.", label), call. = FALSE)
  }
  out
}

app_joint_qdesn_format_numeric_vector <- function(x) {
  x <- as.numeric(x)
  paste(format(x, digits = 8, trim = TRUE, scientific = FALSE), collapse = ",")
}

app_joint_qdesn_gamma_init_policy_choices <- function() {
  c("default", "zero", "half_default", "quarter_default")
}

app_joint_qdesn_gamma_init_for_policy <- function(tau, controls) {
  policy <- controls$gamma_init_policy %||% "default"
  policy <- as.character(policy)[[1L]]
  if (!policy %in% app_joint_qdesn_gamma_init_policy_choices()) {
    stop(sprintf("Unknown gamma_init_policy '%s'.", policy), call. = FALSE)
  }
  if (identical(policy, "default")) return(NULL)
  tau <- app_joint_qvp_validate_tau_grid(tau)
  if (identical(policy, "zero")) return(app_joint_qvp_check_gamma(tau, rep(0, length(tau))))
  scale <- switch(
    policy,
    half_default = 0.5,
    quarter_default = 0.25,
    stop(sprintf("Unknown gamma_init_policy '%s'.", policy), call. = FALSE)
  )
  app_joint_qvp_check_gamma(tau, scale * app_joint_qvp_default_gamma(tau))
}

app_joint_qdesn_alpha_prior_sd_for_tau <- function(alpha_prior_sd, kk, K) {
  alpha_prior_sd <- as.numeric(alpha_prior_sd)
  if (length(alpha_prior_sd) == 1L) return(alpha_prior_sd)
  if (length(alpha_prior_sd) != K) {
    stop("alpha_prior_sd must have length 1 or length(tau).", call. = FALSE)
  }
  alpha_prior_sd[[kk]]
}

app_joint_qdesn_apply_monotone_contract <- function(qhat, tau) {
  tau <- app_joint_qvp_validate_tau_grid(tau)
  qhat <- as.matrix(qhat)
  if (ncol(qhat) != length(tau)) {
    stop("qhat column count must match tau length.", call. = FALSE)
  }
  contract <- t(apply(qhat, 1L, function(x) app_isotonic_quantiles(tau, x)))
  colnames(contract) <- colnames(qhat)
  adjustment <- contract - qhat
  raw_crossing <- app_joint_qvp_crossing_diagnostics(qhat, tau)
  contract_crossing <- app_joint_qvp_crossing_diagnostics(contract, tau)
  list(
    qhat_raw = qhat,
    qhat_contract = contract,
    adjustment = adjustment,
    raw_crossing = raw_crossing,
    contract_crossing = contract_crossing,
    n_adjusted_quantiles = sum(abs(adjustment) > 1.0e-10, na.rm = TRUE),
    max_abs_adjustment = if (length(adjustment)) max(abs(adjustment), na.rm = TRUE) else 0,
    mean_abs_adjustment = if (length(adjustment)) mean(abs(adjustment), na.rm = TRUE) else 0
  )
}

app_joint_qdesn_vb_readiness_fixture <- function(
  Tn = 45L,
  washout_length = 10L,
  tau = c(0.05, 0.1, 0.5, 0.9, 0.95),
  seed = 2026070601L,
  innovation = "gaussian"
) {
  Tn <- as.integer(Tn)
  washout_length <- as.integer(washout_length)
  if (Tn < 20L) stop("Readiness fixture Tn must be at least 20.", call. = FALSE)
  if (washout_length < 0L || washout_length >= Tn - 5L) {
    stop("washout_length must leave at least five retained rows.", call. = FALSE)
  }
  tau <- app_joint_qvp_validate_tau_grid(tau)
  fixture <- app_joint_qvp_simulate_ts_toy_synthetic(
    Tn = Tn,
    tau = tau,
    seed = seed,
    innovation = innovation
  )
  retained <- seq.int(washout_length + 1L, Tn)
  qnames <- app_joint_qdesn_quantile_slug(tau)
  true_q <- as.matrix(fixture$true_q[retained, , drop = FALSE])
  colnames(true_q) <- qnames
  list(
    y = as.numeric(fixture$y[retained]),
    Z = as.matrix(fixture$Z[retained, , drop = FALSE]),
    tau = tau,
    true_q = true_q,
    full_fixture = fixture,
    Tn = Tn,
    washout_length = washout_length,
    retained_length = length(retained),
    seed = as.integer(seed),
    innovation = innovation,
    truth_quantile_method = "analytic_location_scale_toy"
  )
}

app_joint_qdesn_fit_joint_al_readiness <- function(fixture, controls) {
  app_joint_qvp_fit_al_vb_tiny(
    y = fixture$y,
    Z = fixture$Z,
    tau = fixture$tau,
    max_iter = controls$vb_max_iter,
    tol = controls$vb_tol,
    kappa = 1,
    tau0 = controls$tau0,
    zeta2 = controls$zeta2,
    a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma,
    alpha_prior_mean = "empirical_quantile",
    alpha_prior_sd = controls$alpha_prior_sd,
    alpha_min_spacing = controls$alpha_min_spacing,
    max_dense_dim = controls$max_dense_dim %||% 300L,
    rhs_vb_inner = controls$rhs_vb_inner
  )
}

app_joint_qdesn_fit_joint_exal_readiness <- function(fixture, controls, init = NULL) {
  app_joint_qvp_fit_exal_vb_ld_tiny(
    y = fixture$y,
    Z = fixture$Z,
    tau = fixture$tau,
    max_iter = controls$vb_max_iter,
    tol = controls$vb_tol,
    kappa = 1,
    tau0 = controls$tau0,
    zeta2 = controls$zeta2,
    a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma,
    init = init,
    alpha_prior_mean = "empirical_quantile",
    alpha_prior_sd = controls$alpha_prior_sd,
    alpha_min_spacing = controls$alpha_min_spacing,
    gamma_init = app_joint_qdesn_gamma_init_for_policy(fixture$tau, controls),
    max_dense_dim = controls$max_dense_dim %||% 300L,
    rhs_vb_inner = controls$rhs_vb_inner
  )
}

app_joint_qdesn_fit_independent_readiness <- function(fixture, controls, likelihood = c("al", "exal")) {
  likelihood <- match.arg(likelihood)
  tau <- fixture$tau
  fits <- vector("list", length(tau))
  qhat <- matrix(NA_real_, nrow = length(fixture$y), ncol = length(tau))
  alpha <- sigma <- gamma <- rep(NA_real_, length(tau))
  trace_rows <- rhs_rows <- list()
  for (kk in seq_along(tau)) {
    alpha_prior_sd_kk <- app_joint_qdesn_alpha_prior_sd_for_tau(controls$alpha_prior_sd, kk, length(tau))
    al_fit <- app_joint_qvp_fit_al_vb_tiny(
      y = fixture$y,
      Z = fixture$Z,
      tau = tau[[kk]],
      max_iter = controls$vb_max_iter,
      tol = controls$vb_tol,
      kappa = 1,
      tau0 = controls$tau0,
      zeta2 = controls$zeta2,
      a_sigma = controls$a_sigma,
      b_sigma = controls$b_sigma,
      alpha_prior_mean = "empirical_quantile",
      alpha_prior_sd = alpha_prior_sd_kk,
      alpha_min_spacing = 0,
      max_dense_dim = controls$max_dense_dim %||% 300L,
      rhs_vb_inner = controls$rhs_vb_inner
    )
    fit <- al_fit
    if (identical(likelihood, "exal")) {
      fit <- app_joint_qvp_fit_exal_vb_ld_tiny(
        y = fixture$y,
        Z = fixture$Z,
        tau = tau[[kk]],
        max_iter = controls$vb_max_iter,
        tol = controls$vb_tol,
        kappa = 1,
        tau0 = controls$tau0,
        zeta2 = controls$zeta2,
        a_sigma = controls$a_sigma,
        b_sigma = controls$b_sigma,
        init = al_fit,
        alpha_prior_mean = "empirical_quantile",
        alpha_prior_sd = alpha_prior_sd_kk,
        alpha_min_spacing = 0,
        gamma_init = app_joint_qdesn_gamma_init_for_policy(tau[[kk]], controls),
        max_dense_dim = controls$max_dense_dim %||% 300L,
        rhs_vb_inner = controls$rhs_vb_inner
      )
    }
    fits[[kk]] <- fit
    qhat[, kk] <- as.numeric(fit$qhat_mean[, 1L])
    alpha[[kk]] <- fit$alpha_mean[[1L]]
    sigma[[kk]] <- fit$sigma_mean[[1L]]
    gamma[[kk]] <- if (!is.null(fit$gamma_mean)) fit$gamma_mean[[1L]] else NA_real_
    trace_rows[[kk]] <- cbind(
      data.frame(tau = tau[[kk]], stringsAsFactors = FALSE),
      fit$trace
    )
    rhs_rows[[kk]] <- cbind(
      data.frame(tau = tau[[kk]], stringsAsFactors = FALSE),
      fit$rhs_prior_summary
    )
  }
  colnames(qhat) <- app_joint_qdesn_quantile_slug(tau)
  list(
    fits = fits,
    qhat_mean = qhat,
    alpha_mean = alpha,
    sigma_mean = sigma,
    gamma_mean = gamma,
    tau = tau,
    converged = all(vapply(fits, function(x) isTRUE(x$converged), logical(1L))),
    trace = app_joint_qdesn_bind_rows(trace_rows),
    rhs_prior_summary = app_joint_qdesn_bind_rows(rhs_rows),
    manifest_status = paste(vapply(fits, function(x) x$manifest$status[[1L]], character(1L)), collapse = ";")
  )
}

app_joint_qdesn_fit_summary_row <- function(model_id, display_label, likelihood, fit_structure, fit, fixture, controls) {
  contract <- app_joint_qdesn_apply_monotone_contract(fit$qhat_mean, fixture$tau)
  qerr <- contract$qhat_contract - fixture$true_q
  trace <- fit$trace %||% data.frame()
  rhs <- fit$rhs_prior_summary %||% data.frame()
  finite_rhs <- nrow(rhs) > 0L && all(is.finite(as.matrix(rhs[vapply(rhs, is.numeric, logical(1L))])))
  finite_trace <- nrow(trace) > 0L && all(is.finite(as.matrix(trace[vapply(trace, is.numeric, logical(1L))])))
  finite_sigma <- !is.null(fit$sigma_mean) && all(is.finite(fit$sigma_mean)) && all(fit$sigma_mean > 0)
  finite_gamma <- if (!identical(likelihood, "exal")) TRUE else !is.null(fit$gamma_mean) && all(is.finite(fit$gamma_mean))
  finite_qhat <- all(is.finite(fit$qhat_mean)) && all(is.finite(contract$qhat_contract))
  raw_crossing_pairs <- sum(contract$raw_crossing$n_crossing_pairs)
  contract_crossing_pairs <- sum(contract$contract_crossing$n_crossing_pairs)
  reached_max_iter <- !isTRUE(fit$converged)
  hard_fail <- !finite_qhat || !finite_sigma || !finite_gamma || !finite_trace || !finite_rhs || contract_crossing_pairs > 0
  review <- !hard_fail && (reached_max_iter || raw_crossing_pairs > 0 || contract$max_abs_adjustment > controls$review_adjustment_threshold)
  gate_status <- if (hard_fail) "fail" else if (review) "review" else "pass"
  reasons <- c(
    if (!finite_qhat) "nonfinite raw or contract quantiles",
    if (!finite_sigma) "nonfinite or nonpositive scale summary",
    if (!finite_gamma) "nonfinite exAL gamma summary",
    if (!finite_trace) "nonfinite or missing VB trace",
    if (!finite_rhs) "nonfinite or missing RHS prior summary",
    if (contract_crossing_pairs > 0) "contract quantiles cross",
    if (!hard_fail && reached_max_iter) "VB reached max iterations in bounded readiness run",
    if (!hard_fail && raw_crossing_pairs > 0) "raw quantiles required monotone repair",
    if (!hard_fail && contract$max_abs_adjustment > controls$review_adjustment_threshold) "large monotone adjustment"
  )
  data.frame(
    model_id = model_id,
    display_label = display_label,
    likelihood = likelihood,
    fit_structure = fit_structure,
    inference = if (identical(likelihood, "exal")) "VB-LD" else "VB",
    prior = "RHS",
    n_train = length(fixture$y),
    p = ncol(fixture$Z),
    K = length(fixture$tau),
    tau_grid = app_joint_qdesn_format_tau(fixture$tau),
    vb_max_iter = controls$vb_max_iter,
    vb_tol = controls$vb_tol,
    rhs_vb_inner = controls$rhs_vb_inner,
    converged = isTRUE(fit$converged),
    reached_max_iter = reached_max_iter,
    implementation_status = if (hard_fail) "fail" else "pass",
    gate_status = gate_status,
    finite_qhat = finite_qhat,
    finite_sigma = finite_sigma,
    finite_gamma = finite_gamma,
    finite_trace = finite_trace,
    finite_rhs_prior = finite_rhs,
    raw_crossing_pairs = raw_crossing_pairs,
    contract_crossing_pairs = contract_crossing_pairs,
    n_adjusted_quantiles = contract$n_adjusted_quantiles,
    max_abs_adjustment = contract$max_abs_adjustment,
    mean_abs_adjustment = contract$mean_abs_adjustment,
    truth_mae_contract = mean(abs(qerr)),
    truth_rmse_contract = sqrt(mean(qerr^2)),
    final_trace_iter = if (nrow(trace) && "iter" %in% names(trace)) max(trace$iter, na.rm = TRUE) else NA_integer_,
    final_trace_monitor = if (nrow(trace) && "monitor" %in% names(trace)) tail(trace$monitor, 1L) else NA_real_,
    status_reason = if (length(reasons)) paste(reasons, collapse = "; ") else "all readiness gates passed",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_raw_contract_rows <- function(model_id, display_label, fit, fixture) {
  contract <- app_joint_qdesn_apply_monotone_contract(fit$qhat_mean, fixture$tau)
  rows <- list()
  for (kk in seq_along(fixture$tau)) {
    rows[[kk]] <- data.frame(
      model_id = model_id,
      display_label = display_label,
      tau = fixture$tau[[kk]],
      raw_min = min(contract$qhat_raw[, kk], na.rm = TRUE),
      raw_max = max(contract$qhat_raw[, kk], na.rm = TRUE),
      contract_min = min(contract$qhat_contract[, kk], na.rm = TRUE),
      contract_max = max(contract$qhat_contract[, kk], na.rm = TRUE),
      max_abs_adjustment = max(abs(contract$adjustment[, kk]), na.rm = TRUE),
      mean_abs_adjustment = mean(abs(contract$adjustment[, kk]), na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, rows)
  out$total_raw_crossing_pairs <- sum(contract$raw_crossing$n_crossing_pairs)
  out$total_contract_crossing_pairs <- sum(contract$contract_crossing$n_crossing_pairs)
  out
}

app_joint_qdesn_k1_readiness_rows <- function(model_summaries) {
  independent <- model_summaries[model_summaries$fit_structure == "independent_single_tau", , drop = FALSE]
  if (!nrow(independent)) return(data.frame())
  gate_status <- ifelse(
    independent$implementation_status == "fail",
    "fail",
    ifelse(independent$raw_crossing_pairs > 0 | independent$reached_max_iter, "review", "pass")
  )
  data.frame(
    model_id = independent$model_id,
    display_label = independent$display_label,
    single_tau_fit_count = independent$K,
    all_single_tau_fits_finite = independent$finite_qhat & independent$finite_sigma & independent$finite_trace,
    combined_raw_crossing_pairs = independent$raw_crossing_pairs,
    combined_contract_crossing_pairs = independent$contract_crossing_pairs,
    gate_status = gate_status,
    note = "Independent comparator is assembled from one K=1 VB fit per tau, then passed through the same monotone contract used for scoring.",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_oracle_policy_rows <- function() {
  data.frame(
    dgp_family = c(
      "gaussian_location_scale",
      "laplace_location_scale",
      "gaussian_mixture",
      "student_t_location_scale",
      "asymmetric_laplace_tail",
      "regime_shift_or_heteroskedastic_seasonal"
    ),
    recommended_truth_quantile_method = c(
      "analytic",
      "analytic",
      "numerical_inversion",
      "analytic",
      "analytic",
      "analytic_or_numerical_by_declared_conditional_family"
    ),
    monte_carlo_allowed = c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE),
    seed_policy = c(
      "not needed",
      "not needed",
      "fixed inversion tolerance and recorded grid",
      "not needed",
      "not needed",
      "fixed oracle seed only if conditional quantile has no closed form"
    ),
    readiness_status = "pass",
    note = "Oracle quantiles must be materialized once in fixture artifacts and never recomputed inside fit/forecast runners.",
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_simulation_design_rows <- function() {
  data.frame(
    design_component = c(
      "full_simulated_length",
      "dgp_initialization_warmup",
      "effective_series",
      "desn_washout_length",
      "fit_retained_length",
      "validation_retained_length",
      "forecast_origin_spacing",
      "forecast_leads",
      "refit_policy",
      "long_fixture_launch"
    ),
    value = c("12000", "1:2000", "2001:12000", "500", "500", "1000", "30", "1:30", "no refit within 30-step block", "not launched by readiness audit"),
    readiness_status = c(rep("pass", 9L), "pass"),
    note = c(
      "Design target for the later fixture generation stage.",
      "DGP warmup is separate from DESN washout.",
      "Effective stored series has 10000 observations.",
      "DESN state washout before retained fit rows.",
      "Initial retained fit window for VB validation.",
      "Held-out validation window after fit rows.",
      "Matches the TT500 rolling-origin rhythm.",
      "Scores leads 1 through 30.",
      "Avoids turning the study into a refit-frequency comparison.",
      "This audit is readiness only and deliberately avoids the 12000-length generation."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_readiness_checklist <- function(model_summaries, k1_rows, oracle_policy, design_rows) {
  has_joint_al <- "joint_qdesn_rhs_vb" %in% model_summaries$model_id
  has_joint_exal <- "joint_exqdesn_rhs_vb" %in% model_summaries$model_id
  has_ind_al <- "qdesn_rhs_independent_vb" %in% model_summaries$model_id
  has_ind_exal <- "exqdesn_rhs_independent_vb" %in% model_summaries$model_id
  no_fails <- !any(model_summaries$implementation_status == "fail")
  contract_ok <- all(model_summaries$contract_crossing_pairs == 0)
  data.frame(
    check_id = c(
      "model_labels",
      "joint_al_vb_available",
      "joint_exal_vb_ld_available",
      "independent_comparators_available",
      "k1_reduction",
      "rhs_prior_finite",
      "raw_contract_quantiles",
      "oracle_policy",
      "long_series_geometry",
      "mcmc_deferred",
      "artifact_manifest",
      "no_long_fixture_launch"
    ),
    gate_status = c(
      "pass",
      if (has_joint_al) "pass" else "fail",
      if (has_joint_exal) "pass" else "fail",
      if (has_ind_al && has_ind_exal) "pass" else "fail",
      if (nrow(k1_rows) && all(k1_rows$all_single_tau_fits_finite)) "pass" else "fail",
      if (all(model_summaries$finite_rhs_prior)) "pass" else "fail",
      if (contract_ok) if (any(model_summaries$raw_crossing_pairs > 0 | model_summaries$n_adjusted_quantiles > 0)) "review" else "pass" else "fail",
      if (all(oracle_policy$readiness_status == "pass")) "pass" else "fail",
      if (all(design_rows$readiness_status == "pass")) "pass" else "fail",
      "pass",
      "pass",
      "pass"
    ),
    evidence = c(
      "Article labels use JOINT QDESN RHS, JOINT exQDESN RHS, QDESN RHS, and exQDESN RHS.",
      "AL joint VB function executed on deterministic readiness fixture.",
      "exAL joint VB-LD function executed on deterministic readiness fixture.",
      "Independent single-quantile AL and exAL comparators executed across the tau grid.",
      "Independent comparators use one K=1 fit per tau and combine through the monotone contract.",
      "RHS prior summaries are finite for all VB readiness fits.",
      "Raw outputs are preserved and contract outputs are monotone by construction.",
      "Truth-quantile method policy is declared before long fixture generation.",
      "12000-length geometry is documented but not launched.",
      "MCMC is intentionally deferred until VB behavior is stable.",
      "Every readiness artifact is hashed in artifact_manifest.csv.",
      "This audit uses a small deterministic fixture only."
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_launch_blocker_rows <- function(checklist, model_summaries) {
  fail_checks <- checklist[checklist$gate_status == "fail", , drop = FALSE]
  review_checks <- checklist[checklist$gate_status == "review", , drop = FALSE]
  review_models <- model_summaries[model_summaries$gate_status == "review", , drop = FALSE]
  rows <- list()
  if (nrow(fail_checks)) {
    rows[[length(rows) + 1L]] <- data.frame(
      severity = "fail",
      blocker = fail_checks$check_id,
      detail = fail_checks$evidence,
      action = "Fix before any long fixture generation.",
      stringsAsFactors = FALSE
    )
  }
  if (nrow(review_checks)) {
    rows[[length(rows) + 1L]] <- data.frame(
      severity = "review",
      blocker = review_checks$check_id,
      detail = review_checks$evidence,
      action = "Track during VB calibration; not a hard implementation blocker.",
      stringsAsFactors = FALSE
    )
  }
  if (nrow(review_models)) {
    rows[[length(rows) + 1L]] <- data.frame(
      severity = "review",
      blocker = review_models$model_id,
      detail = review_models$status_reason,
      action = "Use realistic VB iteration controls in the next calibration stage.",
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) {
    return(data.frame(
      severity = "pass",
      blocker = "none",
      detail = "No hard blockers were detected in the VB-first readiness audit.",
      action = "Proceed to implement long-series fixture generation and VB validation runners.",
      stringsAsFactors = FALSE
    ))
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_qdesn_next_phase_plan_rows <- function(overall_status) {
  data.frame(
    step_order = seq_len(6L),
    step_id = c(
      "freeze_vb_controls",
      "implement_long_fixture_registry",
      "materialize_oracle_quantiles",
      "run_vb_fit_validation",
      "run_vb_forecast_validation",
      "introduce_mcmc_reference"
    ),
    recommended_action = c(
      "Choose realistic VB max-iteration/adaptive controls from the readiness and prior screening evidence.",
      "Build the 12000-length DGP fixtures with 2000 DGP warmup, 500 DESN washout, 500 fit rows, and 1000 validation rows.",
      "Materialize analytic/numerical/Monte Carlo oracle quantiles once per DGP with hashes and seed roles.",
      "Fit JOINT QDESN RHS, JOINT exQDESN RHS, QDESN RHS, and exQDESN RHS on the retained fit window using VB only.",
      "Run the no-refit lead 1:30 forecast protocol with raw and contract quantile outputs.",
      "After VB behavior is stable, add MCMC references for the same model set."
    ),
    depends_on = c(
      "readiness audit review rows",
      "freeze_vb_controls",
      "implement_long_fixture_registry",
      "materialize_oracle_quantiles",
      "run_vb_fit_validation",
      "stable VB fit and forecast evidence"
    ),
    current_status = c(
      if (identical(overall_status, "fail")) "blocked" else "ready_for_review",
      if (identical(overall_status, "fail")) "blocked" else "next",
      "pending",
      "pending",
      "pending",
      "deferred"
    ),
    stringsAsFactors = FALSE
  )
}

app_joint_qdesn_readiness_readme_lines <- function(overall_status) {
  c(
    "# Joint QDESN VB-First Readiness Audit",
    "",
    "This artifact directory is a readiness audit for the new joint QDESN simulation study.",
    "It deliberately does not launch the 12000-length fixture generation.",
    "",
    sprintf("Overall status: `%s`.", overall_status),
    "",
    "The audit executes a small deterministic toy fixture to verify:",
    "",
    "- `JOINT QDESN RHS` VB;",
    "- `JOINT exQDESN RHS` VB-LD;",
    "- independent `QDESN RHS` K=1 fits across the tau grid;",
    "- independent `exQDESN RHS` K=1 fits across the tau grid;",
    "- finite RHS prior summaries;",
    "- raw and monotone-contract quantile outputs;",
    "- oracle quantile policy before long fixture generation;",
    "- reproducible CSV/provenance/manifest artifacts.",
    "",
    "Review statuses caused by bounded VB iteration controls are not article evidence.",
    "They indicate what must be calibrated before the long validation run."
  )
}

app_joint_qdesn_run_vb_readiness_audit <- function(
  out_dir = app_joint_qdesn_default_vb_readiness_dir(),
  Tn = 45L,
  washout_length = 10L,
  tau = c(0.05, 0.1, 0.5, 0.9, 0.95),
  seed = 2026070601L,
  innovation = "gaussian",
  vb_max_iter = 8L,
  vb_tol = 1.0e-4,
  rhs_vb_inner = 2L,
  tau0 = 1,
  zeta2 = Inf,
  a_sigma = 2,
  b_sigma = 1,
  alpha_prior_sd = 1,
  alpha_min_spacing = 0,
  review_adjustment_threshold = 1.0e-3
) {
  app_ensure_dir(out_dir)
  controls <- list(
    vb_max_iter = as.integer(vb_max_iter),
    vb_tol = as.numeric(vb_tol),
    rhs_vb_inner = as.integer(rhs_vb_inner),
    tau0 = as.numeric(tau0),
    zeta2 = as.numeric(zeta2),
    a_sigma = as.numeric(a_sigma),
    b_sigma = as.numeric(b_sigma),
    alpha_prior_sd = as.numeric(alpha_prior_sd),
    alpha_min_spacing = as.numeric(alpha_min_spacing),
    review_adjustment_threshold = as.numeric(review_adjustment_threshold)
  )
  fixture <- app_joint_qdesn_vb_readiness_fixture(
    Tn = Tn,
    washout_length = washout_length,
    tau = tau,
    seed = seed,
    innovation = innovation
  )

  joint_al <- app_joint_qdesn_fit_joint_al_readiness(fixture, controls)
  joint_exal <- app_joint_qdesn_fit_joint_exal_readiness(fixture, controls, init = joint_al)
  independent_al <- app_joint_qdesn_fit_independent_readiness(fixture, controls, likelihood = "al")
  independent_exal <- app_joint_qdesn_fit_independent_readiness(fixture, controls, likelihood = "exal")

  model_specs <- list(
    list(id = "joint_qdesn_rhs_vb", label = "JOINT QDESN RHS", likelihood = "al", structure = "joint", fit = joint_al),
    list(id = "joint_exqdesn_rhs_vb", label = "JOINT exQDESN RHS", likelihood = "exal", structure = "joint", fit = joint_exal),
    list(id = "qdesn_rhs_independent_vb", label = "QDESN RHS", likelihood = "al", structure = "independent_single_tau", fit = independent_al),
    list(id = "exqdesn_rhs_independent_vb", label = "exQDESN RHS", likelihood = "exal", structure = "independent_single_tau", fit = independent_exal)
  )

  model_summaries <- app_joint_qdesn_bind_rows(lapply(model_specs, function(spec) {
    app_joint_qdesn_fit_summary_row(
      model_id = spec$id,
      display_label = spec$label,
      likelihood = spec$likelihood,
      fit_structure = spec$structure,
      fit = spec$fit,
      fixture = fixture,
      controls = controls
    )
  }))
  raw_contract <- app_joint_qdesn_bind_rows(lapply(model_specs, function(spec) {
    app_joint_qdesn_raw_contract_rows(spec$id, spec$label, spec$fit, fixture)
  }))
  k1_rows <- app_joint_qdesn_k1_readiness_rows(model_summaries)
  oracle_policy <- app_joint_qdesn_oracle_policy_rows()
  design_rows <- app_joint_qdesn_simulation_design_rows()
  checklist <- app_joint_qdesn_readiness_checklist(model_summaries, k1_rows, oracle_policy, design_rows)
  overall_status <- if (any(checklist$gate_status == "fail") || any(model_summaries$implementation_status == "fail")) {
    "fail"
  } else if (any(checklist$gate_status == "review") || any(model_summaries$gate_status == "review")) {
    "review"
  } else {
    "pass"
  }
  blockers <- app_joint_qdesn_launch_blocker_rows(checklist, model_summaries)
  next_plan <- app_joint_qdesn_next_phase_plan_rows(overall_status)

  run_config <- data.frame(
    run_id = "joint_qdesn_simulation_vb_readiness_audit",
    audit_scope = "VB-first readiness only; no 12000-length fixture generation",
    out_dir = normalizePath(out_dir, mustWork = FALSE),
    seed = as.integer(seed),
    innovation = innovation,
    Tn = as.integer(Tn),
    washout_length = as.integer(washout_length),
    retained_length = fixture$retained_length,
    tau_grid = app_joint_qdesn_format_tau(fixture$tau),
    vb_max_iter = controls$vb_max_iter,
    vb_tol = controls$vb_tol,
    rhs_vb_inner = controls$rhs_vb_inner,
    tau0 = controls$tau0,
    zeta2 = controls$zeta2,
    a_sigma = controls$a_sigma,
    b_sigma = controls$b_sigma,
    alpha_prior_sd = controls$alpha_prior_sd,
    alpha_min_spacing = controls$alpha_min_spacing,
    review_adjustment_threshold = controls$review_adjustment_threshold,
    overall_status = overall_status,
    long_fixture_generation_launched = FALSE,
    stringsAsFactors = FALSE
  )

  toy_fixture_summary <- data.frame(
    fixture_id = "deterministic_ts_toy_readiness",
    seed = fixture$seed,
    innovation = fixture$innovation,
    full_length = fixture$Tn,
    washout_length = fixture$washout_length,
    retained_length = fixture$retained_length,
    p = ncol(fixture$Z),
    K = length(fixture$tau),
    tau_grid = app_joint_qdesn_format_tau(fixture$tau),
    truth_quantile_method = fixture$truth_quantile_method,
    finite_y = all(is.finite(fixture$y)),
    finite_Z = all(is.finite(fixture$Z)),
    finite_true_q = all(is.finite(fixture$true_q)),
    positive_scale_path = all(fixture$full_fixture$sigma > 0),
    true_quantile_crossing_pairs = sum(app_joint_qvp_crossing_diagnostics(fixture$true_q, fixture$tau)$n_crossing_pairs),
    stringsAsFactors = FALSE
  )

  writeLines(app_joint_qdesn_readiness_readme_lines(overall_status), file.path(out_dir, "README.md"), useBytes = TRUE)
  paths <- c(
    run_config = app_joint_qvp_write_csv(run_config, file.path(out_dir, "run_config.csv")),
    readiness_checklist = app_joint_qvp_write_csv(checklist, file.path(out_dir, "readiness_checklist.csv")),
    toy_fixture_summary = app_joint_qvp_write_csv(toy_fixture_summary, file.path(out_dir, "toy_fixture_summary.csv")),
    model_scope_readiness = app_joint_qvp_write_csv(model_summaries, file.path(out_dir, "model_scope_readiness.csv")),
    raw_contract_quantile_diagnostics = app_joint_qvp_write_csv(raw_contract, file.path(out_dir, "raw_contract_quantile_diagnostics.csv")),
    k1_reduction_readiness = app_joint_qvp_write_csv(k1_rows, file.path(out_dir, "k1_reduction_readiness.csv")),
    oracle_policy_readiness = app_joint_qvp_write_csv(oracle_policy, file.path(out_dir, "oracle_policy_readiness.csv")),
    simulation_design_readiness = app_joint_qvp_write_csv(design_rows, file.path(out_dir, "simulation_design_readiness.csv")),
    launch_blockers = app_joint_qvp_write_csv(blockers, file.path(out_dir, "launch_blockers.csv")),
    next_phase_plan = app_joint_qvp_write_csv(next_plan, file.path(out_dir, "next_phase_plan.csv")),
    provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(out_dir, "provenance.csv")),
    readme = normalizePath(file.path(out_dir, "README.md"), mustWork = TRUE)
  )
  manifest <- data.frame(
    label = names(paths),
    relative_path = basename(paths),
    size_bytes = as.numeric(file.info(paths)$size),
    sha256 = vapply(paths, app_sha256_file, character(1L)),
    stringsAsFactors = FALSE
  )
  manifest_path <- app_joint_qvp_write_csv(manifest, file.path(out_dir, "artifact_manifest.csv"))
  list(
    out_dir = normalizePath(out_dir, mustWork = TRUE),
    paths = c(paths, artifact_manifest = manifest_path),
    manifest = manifest,
    run_config = run_config,
    readiness_checklist = checklist,
    toy_fixture_summary = toy_fixture_summary,
    model_scope_readiness = model_summaries,
    raw_contract_quantile_diagnostics = raw_contract,
    k1_reduction_readiness = k1_rows,
    oracle_policy_readiness = oracle_policy,
    simulation_design_readiness = design_rows,
    launch_blockers = blockers,
    next_phase_plan = next_plan
  )
}
