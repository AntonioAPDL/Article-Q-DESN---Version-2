# Post-Search-II execution contract for the GloFAS application.

app_glofas_post_search2_required_components <- function() {
  c("reference", "discrepancy")
}

app_glofas_post_search2_final_design_contract <- function(selection) {
  c_dec25 <- app_glofas_dec25_contract()
  panel_start <- as.Date("1987-05-29")
  panel_dates <- seq.Date(panel_start, c_dec25$train_end, by = "day")
  components <- app_glofas_post_search2_required_components()
  rows <- lapply(components, function(component) {
    app_glofas_post_search2_component_row(selection, component)
  })
  component_drop <- vapply(rows, function(row) {
    max(
      as.integer(row$washout[[1L]]),
      as.integer(row$output_lag_max[[1L]]),
      as.integer(row$covariate_lag_max[[1L]])
    )
  }, integer(1L))
  effective_drop <- max(component_drop)
  expected_dates <- panel_dates[seq.int(effective_drop + 1L, length(panel_dates))]
  if (effective_drop != 540L || length(expected_dates) != 12455L ||
      min(expected_dates) != as.Date("1988-11-19") ||
      max(expected_dates) != c_dec25$train_end) {
    stop("The adopted Search-II design no longer matches its frozen Dec-25 date contract.", call. = FALSE)
  }
  list(
    panel_start = panel_start,
    panel_end = c_dec25$train_end,
    panel_rows = length(panel_dates),
    component_drop = stats::setNames(component_drop, components),
    effective_drop = effective_drop,
    expected_dates = expected_dates,
    design_start = min(expected_dates),
    design_end = max(expected_dates),
    design_rows = length(expected_dates),
    stacked_rows = 2L * length(expected_dates)
  )
}

app_glofas_post_search2_validate_final_dates <- function(dates, selection, label) {
  contract <- app_glofas_post_search2_final_design_contract(selection)
  app_glofas_dec25_final_split(
    dates,
    expected_n = contract$design_rows,
    expected_dates = contract$expected_dates,
    label = label
  )
}

app_glofas_post_search2_needs_calibration <- function(job_type, model_family) {
  is_normal_ridge_job <- as.character(model_family[[1L]]) %in% "normal_ridge" &&
    as.character(job_type[[1L]]) %in% c("part1_fit", "part1_forecast")
  !is_normal_ridge_job
}

app_glofas_post_search2_value <- function(row, name, default = NULL) {
  if (!name %in% names(row) || !length(row[[name]])) return(default)
  value <- row[[name]][[1L]]
  if (length(value) == 1L && (is.na(value) || (is.character(value) && !nzchar(value)))) default else value
}

app_glofas_post_search2_read_selection <- function(path, require_adopted = TRUE) {
  path <- app_resolve_path(path, must_work = TRUE)
  manifest <- app_read_csv(path)
  required <- c(
    "component", "candidate_id", "canonical_seed", "D", "n_vector", "m",
    "output_lag_max", "covariate_lag_max", "washout", "alpha", "rho",
    "pi_w", "pi_in", "effective_input_gain", "standardize_inputs",
    "state_scaling", "input_bound", "act_f", "prior_id", "prior_mode",
    "m0", "rhs_zeta2_fixed", "rhs_a_zeta", "rhs_b_zeta", "adoption_status"
  )
  app_check_required_columns(manifest, required, "post-Search-II selected component manifest")
  manifest$component <- tolower(trimws(as.character(manifest$component)))
  if (!setequal(manifest$component, app_glofas_post_search2_required_components()) ||
      anyDuplicated(manifest$component)) {
    stop("Selection manifest must contain exactly one reference and one discrepancy row.", call. = FALSE)
  }
  if (isTRUE(require_adopted) && any(tolower(trimws(as.character(manifest$adoption_status))) != "adopted")) {
    stop("Every selected component must have adoption_status=adopted.", call. = FALSE)
  }
  expected <- list(
    reference = list(candidate_id = "search2_ref_008", seed = 20260512L, zeta2 = NA_real_),
    discrepancy = list(candidate_id = "search2_dis_009", seed = 20261521L, zeta2 = 16)
  )
  for (component in names(expected)) {
    row <- manifest[manifest$component == component, , drop = FALSE]
    spec <- expected[[component]]
    if (!identical(as.character(row$candidate_id[[1L]]), spec$candidate_id) ||
        as.integer(row$canonical_seed[[1L]]) != spec$seed) {
      stop(sprintf("%s selection does not match the frozen Search II adoption.", component), call. = FALSE)
    }
    zeta <- suppressWarnings(as.numeric(row$rhs_zeta2_fixed[[1L]]))
    if ((is.na(spec$zeta2) && is.finite(zeta)) ||
        (is.finite(spec$zeta2) && (!is.finite(zeta) || abs(zeta - spec$zeta2) > 1.0e-12))) {
      stop(sprintf("%s slab policy does not match the frozen Search II adoption.", component), call. = FALSE)
    }
  }
  attr(manifest, "selection_path") <- path
  attr(manifest, "selection_sha256") <- app_sha256_file(path)
  manifest
}

app_glofas_post_search2_component_row <- function(selection, component) {
  component <- match.arg(component, app_glofas_post_search2_required_components())
  selected <- selection[selection$component == component, , drop = FALSE]
  if (nrow(selected) != 1L) stop(sprintf("Missing selected %s component.", component), call. = FALSE)
  defaults <- app_glofas_normal_part1_default_values()
  input_gain <- as.numeric(selected$effective_input_gain[[1L]])
  if (!is.finite(input_gain) || input_gain <= 0) stop("Selected effective input gain must be positive.", call. = FALSE)
  data.frame(
    candidate_id = as.character(selected$candidate_id[[1L]]),
    rhs_candidate_id = paste0(as.character(selected$candidate_id[[1L]]), "__final_full_data_rhs"),
    target = component,
    D = as.integer(selected$D[[1L]]),
    n_vector = as.character(selected$n_vector[[1L]]),
    n_tilde = "",
    m = as.integer(selected$m[[1L]]),
    output_lag_max = as.integer(selected$output_lag_max[[1L]]),
    covariate_lag_max = as.integer(selected$covariate_lag_max[[1L]]),
    auxiliary_lag_max = as.integer(selected$output_lag_max[[1L]]),
    input_contract = if (identical(component, "discrepancy")) "disc_covars" else "reference_usgs_covars",
    washout = as.integer(selected$washout[[1L]]),
    alpha = as.numeric(selected$alpha[[1L]]),
    rho = as.numeric(selected$rho[[1L]]),
    seed = as.integer(selected$canonical_seed[[1L]]),
    pi_w = as.numeric(selected$pi_w[[1L]]),
    pi_in = as.numeric(selected$pi_in[[1L]]),
    win_scale_global = input_gain,
    win_scale_bias = 1,
    standardize_inputs = app_as_bool(selected$standardize_inputs[[1L]]),
    state_scaling = as.character(selected$state_scaling[[1L]]),
    input_bound = as.character(selected$input_bound[[1L]]),
    act_f = as.character(selected$act_f[[1L]]),
    act_k = "identity",
    ridge_tau2 = defaults$ridge_tau2,
    intercept_var = defaults$intercept_var,
    sigma_a = defaults$sigma_a,
    sigma_b = defaults$sigma_b,
    validation_n = 0L,
    prior_id = as.character(selected$prior_id[[1L]]),
    prior_mode = as.character(selected$prior_mode[[1L]]),
    m0 = as.numeric(selected$m0[[1L]]),
    rhs_tau0 = NA_real_,
    rhs_zeta2_fixed = suppressWarnings(as.numeric(selected$rhs_zeta2_fixed[[1L]])),
    rhs_a_zeta = as.numeric(selected$rhs_a_zeta[[1L]]),
    rhs_b_zeta = as.numeric(selected$rhs_b_zeta[[1L]]),
    rhs_max_iter = 100L,
    rhs_min_iter = 30L,
    rhs_tol = 1.0e-4,
    rhs_update_every = 1L,
    rhs_freeze_tau_warmup_iters = 0L,
    rhs_min_tau_updates = 0L,
    rhs_freeze_beta_warmup_iters = 20L,
    rhs_min_beta_updates = 30L,
    source_selection_sha256 = as.character(attr(selection, "selection_sha256") %||% NA_character_),
    stringsAsFactors = FALSE
  )
}

app_glofas_post_search2_quantile_slab <- function(component_row) {
  fixed <- suppressWarnings(as.numeric(component_row$rhs_zeta2_fixed[[1L]]))
  a_zeta <- as.numeric(component_row$rhs_a_zeta[[1L]])
  b_zeta <- as.numeric(component_row$rhs_b_zeta[[1L]])
  if (!is.finite(a_zeta) || a_zeta <= 0 || !is.finite(b_zeta) || b_zeta <= 0) {
    stop("Selected RHS slab hyperparameters must be finite and positive.", call. = FALSE)
  }
  list(
    zeta2 = if (is.finite(fixed)) fixed else b_zeta / a_zeta,
    slab_fixed = is.finite(fixed),
    a_zeta = a_zeta,
    b_zeta = b_zeta,
    policy = if (is.finite(fixed)) "fixed" else "learned"
  )
}

app_glofas_post_search2_joint_candidate <- function(selection, candidate_id = "post_search2_part3_joint") {
  ref <- app_glofas_post_search2_component_row(selection, "reference")
  disc <- app_glofas_post_search2_component_row(selection, "discrepancy")
  fields <- c(
    "n_vector", "m", "output_lag_max", "covariate_lag_max", "auxiliary_lag_max",
    "input_contract", "washout", "alpha", "rho", "seed", "pi_w", "pi_in",
    "win_scale_global", "win_scale_bias", "standardize_inputs", "state_scaling",
    "input_bound", "act_f", "act_k"
  )
  out <- data.frame(
    candidate_id = as.character(candidate_id),
    model_family = "normal_joint_historical_bridge",
    ridge_tau2 = ref$ridge_tau2,
    intercept_var = ref$intercept_var,
    sigma_a = ref$sigma_a,
    sigma_b = ref$sigma_b,
    validation_n = 0L,
    rhs_tau0_reference = NA_real_,
    rhs_tau0_discrepancy = NA_real_,
    rhs_zeta2_fixed_reference = ref$rhs_zeta2_fixed,
    rhs_zeta2_fixed_discrepancy = disc$rhs_zeta2_fixed,
    rhs_a_zeta = ref$rhs_a_zeta,
    rhs_b_zeta = ref$rhs_b_zeta,
    rhs_max_iter = 100L,
    rhs_min_iter = 30L,
    rhs_tol = 1.0e-4,
    rhs_update_every = 1L,
    rhs_freeze_tau_warmup_iters = 0L,
    rhs_min_tau_updates = 0L,
    rhs_freeze_beta_warmup_iters = 20L,
    rhs_min_beta_updates = 30L,
    ref_source_candidate_id = ref$candidate_id,
    disc_source_candidate_id = disc$candidate_id,
    ref_prior_id = ref$prior_id,
    disc_prior_id = disc$prior_id,
    ref_prior_mode = ref$prior_mode,
    disc_prior_mode = disc$prior_mode,
    ref_m0 = ref$m0,
    disc_m0 = disc$m0,
    source_selection_sha256 = as.character(attr(selection, "selection_sha256") %||% NA_character_),
    stringsAsFactors = FALSE
  )
  for (field in fields) {
    out[[paste0("ref_", field)]] <- ref[[field]][[1L]]
    out[[paste0("disc_", field)]] <- disc[[field]][[1L]]
  }
  out
}

app_glofas_post_search2_calibrate_tau0 <- function(component_row, ridge_fit, p, n_fit) {
  tau0 <- app_glofas_search2_resolve_rhs_tau0(component_row, ridge_fit, p = p, n_fit = n_fit)
  if (length(tau0) != 1L || !is.finite(tau0) || tau0 <= 0) {
    stop("Full-data RHS tau0 calibration failed.", call. = FALSE)
  }
  as.numeric(tau0)
}

app_glofas_post_search2_calibration_record <- function(
  selection, reference_ridge_fit, discrepancy_ridge_fit,
  p_reference, p_discrepancy, n_reference, n_discrepancy
) {
  ref <- app_glofas_post_search2_component_row(selection, "reference")
  disc <- app_glofas_post_search2_component_row(selection, "discrepancy")
  rows <- list(
    reference = data.frame(
      component = "reference", candidate_id = ref$candidate_id,
      p = as.integer(p_reference), n_fit = as.integer(n_reference), m0 = ref$m0,
      sigma_reference = sqrt(as.numeric(reference_ridge_fit$sigma2_mean)),
      rhs_tau0 = app_glofas_post_search2_calibrate_tau0(ref, reference_ridge_fit, p_reference, n_reference),
      rhs_zeta2_fixed = ref$rhs_zeta2_fixed, stringsAsFactors = FALSE
    ),
    discrepancy = data.frame(
      component = "discrepancy", candidate_id = disc$candidate_id,
      p = as.integer(p_discrepancy), n_fit = as.integer(n_discrepancy), m0 = disc$m0,
      sigma_reference = sqrt(as.numeric(discrepancy_ridge_fit$sigma2_mean)),
      rhs_tau0 = app_glofas_post_search2_calibrate_tau0(disc, discrepancy_ridge_fit, p_discrepancy, n_discrepancy),
      rhs_zeta2_fixed = disc$rhs_zeta2_fixed, stringsAsFactors = FALSE
    )
  )
  app_bind_rows_fill(rows)
}

app_glofas_post_search2_apply_calibration <- function(candidate_row, calibration) {
  app_check_required_columns(calibration, c("component", "rhs_tau0"), "full-data calibration")
  ref <- calibration[calibration$component == "reference", , drop = FALSE]
  disc <- calibration[calibration$component == "discrepancy", , drop = FALSE]
  if (nrow(ref) != 1L || nrow(disc) != 1L) stop("Calibration must contain one row per component.", call. = FALSE)
  candidate_row$rhs_tau0_reference <- as.numeric(ref$rhs_tau0[[1L]])
  candidate_row$rhs_tau0_discrepancy <- as.numeric(disc$rhs_tau0[[1L]])
  candidate_row
}

app_glofas_post_search2_anchor_manifest <- function(selection, calibration, runtime_root, design_hashes) {
  ref <- app_glofas_post_search2_component_row(selection, "reference")
  disc <- app_glofas_post_search2_component_row(selection, "discrepancy")
  make_row <- function(role, stage, row, tau0, design_hash) {
    data.frame(
      role = role, stage = stage, candidate_id = row$candidate_id,
      source_runtime_root = as.character(runtime_root), score_path = "",
      method = "post_search2_full_data_rhs_vb", status = "completed",
      n_vector = row$n_vector, m = row$m,
      output_lag_max = row$output_lag_max, covariate_lag_max = row$covariate_lag_max,
      washout = row$washout, alpha = row$alpha, rho = row$rho, seed = row$seed,
      pi_w = row$pi_w, pi_in = row$pi_in,
      win_scale_global = row$win_scale_global, win_scale_bias = row$win_scale_bias,
      standardize_inputs = row$standardize_inputs, state_scaling = row$state_scaling,
      input_bound = row$input_bound, act_f = row$act_f, act_k = row$act_k,
      rhs_tau0 = as.numeric(tau0), rhs_zeta2_fixed = row$rhs_zeta2_fixed,
      design_hash = as.character(design_hash), frozen = TRUE,
      stringsAsFactors = FALSE
    )
  }
  out <- app_bind_rows_fill(list(
    make_row("reference_anchor", "G1", ref,
      calibration$rhs_tau0[calibration$component == "reference"], design_hashes$reference),
    make_row("discrepancy_anchor", "G2", disc,
      calibration$rhs_tau0[calibration$component == "discrepancy"], design_hashes$discrepancy)
  ))
  app_glofas_part4_validate_anchor_manifest(out, require_frozen = TRUE)
}
