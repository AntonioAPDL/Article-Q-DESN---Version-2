# Seasonal Search III contracts and staged selection for the GloFAS Normal DESN.
# Numerical fitting and recursive forecasting reuse the audited Search II engine.

app_glofas_search3_version <- function() "glofas_search3_rainy_season_v1"

app_glofas_search3_phases <- function() {
  c("october", "november", "operational", "february", "march")
}

app_glofas_search3_fold_registry <- function(
  development_path = app_path("application/config/glofas_search3_development_folds_20260923.csv"),
  confirmation_path = app_path("application/config/glofas_search3_confirmation_folds_20260923.csv")
) {
  out <- rbind(app_read_csv(development_path), app_read_csv(confirmation_path))
  out$origin_date <- as.Date(out$origin_date)
  out$primary <- as.logical(out$primary)
  out$retrospective_product <- "v3.1 LISFLOOD"
  app_glofas_search3_validate_folds(out)
  out
}

app_glofas_search3_validate_folds <- function(folds) {
  required <- c(
    "fold_id", "wet_season", "origin_date", "primary_horizon",
    "secondary_horizon", "phase", "panel", "ridge_pass", "primary"
  )
  missing <- setdiff(required, names(folds))
  if (length(missing)) stop(sprintf("Search III folds are missing: %s.", paste(missing, collapse = ", ")), call. = FALSE)
  folds$origin_date <- as.Date(folds$origin_date)
  if (!nrow(folds) || any(is.na(folds$origin_date)) || anyDuplicated(folds$fold_id)) {
    stop("Search III fold IDs and dates must be unique and finite.", call. = FALSE)
  }
  if (any(folds$origin_date >= as.Date("2022-12-25"))) {
    stop("Search III folds must exclude the repeatedly inspected 2022-12-25 origin.", call. = FALSE)
  }
  if (any(folds$primary_horizon != 28L) || any(folds$secondary_horizon != 30L)) {
    stop("Search III requires 28-day primary and 30-day secondary windows.", call. = FALSE)
  }
  rainy <- folds[folds$primary, , drop = FALSE]
  if (any(!rainy$phase %in% app_glofas_search3_phases())) {
    stop("Primary Search III folds use an unknown rainy-season phase.", call. = FALSE)
  }
  dev <- rainy[rainy$panel == "development", , drop = FALSE]
  conf <- rainy[rainy$panel == "confirmation", , drop = FALSE]
  if (nrow(dev) != 16L || nrow(conf) != 16L ||
      sum(dev$ridge_pass == "A") != 12L || sum(dev$ridge_pass == "B") != 4L) {
    stop("Search III fold counts do not match the frozen development/confirmation design.", call. = FALSE)
  }
  for (panel in list(dev, conf)) {
    windows <- lapply(seq_len(nrow(panel)), function(i) {
      seq.Date(panel$origin_date[[i]] + 1L, by = "day", length.out = panel$primary_horizon[[i]])
    })
    if (anyDuplicated(do.call(c, windows))) stop("Primary target windows overlap within a Search III panel.", call. = FALSE)
  }
  invisible(TRUE)
}

app_glofas_search3_folds <- function(folds, stage) {
  stage <- match.arg(stage, c(
    "ridge_a", "ridge_b", "ridge_guard", "rhs_pilot", "rhs_screen", "confirmation"
  ))
  if (stage == "ridge_a") return(folds[folds$panel == "development" & folds$ridge_pass == "A", , drop = FALSE])
  if (stage == "ridge_b") return(folds[folds$panel == "development" & folds$ridge_pass == "B", , drop = FALSE])
  if (stage == "ridge_guard") return(folds[folds$panel == "development" & folds$ridge_pass == "guard", , drop = FALSE])
  if (stage == "rhs_pilot") {
    ids <- c("dev14_oct", "dev14_op", "dev15_nov", "dev15_mar", "dev16_oct", "dev16_feb", "dev17_nov", "dev17_mar")
    return(folds[match(ids, folds$fold_id), , drop = FALSE])
  }
  if (stage == "rhs_screen") return(folds[folds$panel == "development", , drop = FALSE])
  folds[folds$panel == "confirmation", , drop = FALSE]
}

app_glofas_search3_candidate_key <- function(x) {
  cols <- c(
    "target", "D", "n_vector", "output_lag_max", "covariate_lag_max",
    "alpha", "rho", "pi_w", "pi_in", "effective_input_gain", "state_scaling", "ridge_tau2"
  )
  do.call(paste, c(lapply(x[cols], function(z) format(z, digits = 15, trim = TRUE)), sep = "|"))
}

app_glofas_search3_decorate_candidates <- function(x, target, role) {
  if (!nrow(x)) return(x)
  x$target <- target
  x$state_scaling <- "train_zscore"
  x$candidate_role <- role
  x$ridge_tau2 <- 100
  x$input_dimension <- mapply(app_glofas_search2_input_dimension, x$output_lag_max, x$covariate_lag_max)
  x$win_scale_global <- mapply(
    app_glofas_search2_win_scale, x$effective_input_gain, x$pi_in, x$input_dimension
  )
  x$win_scale_bias <- x$win_scale_global
  x$m <- x$output_lag_max
  x$washout <- 500L
  x$seed <- if (target == "reference") 20260512L else 20261521L
  x$intercept_var <- 1.0e6
  x$sigma_a <- 2
  x$sigma_b <- 1
  x$input_bound <- "none"
  x$act_f <- "tanh"
  x$act_k <- "identity"
  x$standardize_inputs <- TRUE
  x$dlm_extension_enabled <- FALSE
  x$geometry_label <- paste0("D", x$D, "_n", gsub(",", "x", x$n_vector))
  x
}

app_glofas_search3_grid <- function(target, stratum) {
  if (target == "reference" && stratum == "d1") {
    out <- expand.grid(
      n_state_features = c(1000L, 1500L, 2000L, 2500L, 3000L),
      output_lag_max = c(180L, 540L), covariate_lag_max = c(90L, 180L, 360L),
      alpha = c(.65, .70, .75, .80, .85), rho = c(.50, .60, .70, .75, .85),
      pi_w = c(.03, .10), pi_in = c(.10, .30),
      effective_input_gain = c(.35, .50, .75, 1.00), KEEP.OUT.ATTRS = FALSE
    )
    out$D <- 1L; out$n_vector <- as.character(out$n_state_features)
  } else if (target == "reference" && stratum == "d2") {
    out <- expand.grid(
      n_state_features = c(1000L, 1500L, 2000L, 3000L), output_lag_max = c(180L, 540L),
      covariate_lag_max = c(90L, 180L), alpha = c(.70, .80), rho = c(.50, .70),
      pi_w = c(.03, .10), pi_in = .10, effective_input_gain = c(.35, .50), KEEP.OUT.ATTRS = FALSE
    )
    out$D <- 2L; out$n_vector <- vapply(out$n_state_features, function(n) paste(rep(n %/% 2L, 2L), collapse = ","), character(1L))
  } else if (target == "discrepancy" && stratum == "basin_a") {
    out <- expand.grid(
      n_state_features = c(1000L, 1500L, 2000L, 2500L, 3000L), output_lag_max = c(180L, 540L),
      covariate_lag_max = c(180L, 360L), alpha = c(.85, .90, .95, .99), rho = c(.20, .30, .40),
      pi_w = c(.003, .005, .010, .030), pi_in = c(.10, .30),
      effective_input_gain = c(.35, .50, .75, 1.00), KEEP.OUT.ATTRS = FALSE
    )
    out$D <- 1L; out$n_vector <- as.character(out$n_state_features)
  } else if (target == "discrepancy" && stratum == "basin_b") {
    out <- expand.grid(
      n_state_features = c(1500L, 2500L, 3000L), output_lag_max = 540L,
      covariate_lag_max = c(180L, 360L), alpha = c(.55, .60, .65, .70), rho = c(.85, .90, .95),
      pi_w = c(.005, .010, .030, .10), pi_in = c(.10, .30),
      effective_input_gain = c(.35, .50, .75), KEEP.OUT.ATTRS = FALSE
    )
    out$D <- 1L; out$n_vector <- as.character(out$n_state_features)
  } else if (target == "discrepancy" && stratum == "d2") {
    out <- expand.grid(
      n_state_features = c(1000L, 1500L, 2000L, 3000L), output_lag_max = c(180L, 540L),
      covariate_lag_max = c(180L, 360L), alpha = c(.70, .90), rho = c(.30, .90),
      pi_w = c(.005, .03), pi_in = .10, effective_input_gain = c(.35, .50), KEEP.OUT.ATTRS = FALSE
    )
    out$D <- 2L; out$n_vector <- vapply(out$n_state_features, function(n) paste(rep(n %/% 2L, 2L), collapse = ","), character(1L))
  } else stop("Unknown Search III candidate stratum.", call. = FALSE)
  app_glofas_search3_decorate_candidates(out, target, paste0("search3_", stratum))
}

app_glofas_search3_maximin_excluding <- function(pool, n, excluded_keys = character()) {
  pool <- pool[!app_glofas_search3_candidate_key(pool) %in% excluded_keys, , drop = FALSE]
  if (nrow(pool) < n) stop("Search III candidate pool is smaller than its requested stratum.", call. = FALSE)
  app_glofas_search2_maximin(pool, n)
}

app_glofas_search3_candidates <- function(search2_candidates, search2_ridge_scores) {
  search2_candidates$source_candidate_id <- search2_candidates$candidate_id
  score <- search2_ridge_scores[search2_ridge_scores$method == "ridge" & is.finite(search2_ridge_scores$mean_primary_crps), , drop = FALSE]
  make_target <- function(target) {
    prefix <- if (target == "reference") "ref" else "dis"
    incumbent <- if (target == "reference") "search2_ref_008" else "search2_dis_009"
    baseline <- if (target == "reference") "search2_ref_001" else "search2_dis_001"
    exact <- if (target == "reference") c("search2_ref_049", "search2_ref_050", "search2_ref_069") else c("search2_dis_011", "search2_dis_017", "search2_dis_033")
    mandatory_ids <- c(incumbent, baseline, exact)
    mandatory <- search2_candidates[match(mandatory_ids, search2_candidates$candidate_id), , drop = FALSE]
    if (any(is.na(mandatory$candidate_id))) stop("Search III mandatory Search II controls are unavailable.", call. = FALSE)
    mandatory <- app_glofas_search3_decorate_candidates(mandatory, target, "mandatory_control")
    mandatory$control_label <- c("search2_incumbent", "search1_baseline", sub("search2_", "", exact))
    target_score <- score[score$target == target & !score$candidate_id %in% mandatory_ids, , drop = FALSE]
    target_score <- target_score[order(-target_score$mean_primary_crps), , drop = FALSE]
    sentinel_id <- as.character(target_score$candidate_id[[1L]])
    sentinel <- search2_candidates[search2_candidates$candidate_id == sentinel_id, , drop = FALSE]
    sentinel <- app_glofas_search3_decorate_candidates(sentinel, target, "poor_region_sentinel")
    sentinel$control_label <- "search2_poor_region_sentinel"
    fixed <- app_bind_rows_fill(list(mandatory, sentinel))
    keys <- app_glofas_search3_candidate_key(fixed)
    if (target == "reference") {
      d1 <- app_glofas_search3_maximin_excluding(app_glofas_search3_grid(target, "d1"), 28L, keys)
      keys <- c(keys, app_glofas_search3_candidate_key(d1))
      d2 <- app_glofas_search3_maximin_excluding(app_glofas_search3_grid(target, "d2"), 6L, keys)
      generated <- app_bind_rows_fill(list(d1, d2))
    } else {
      a <- app_glofas_search3_maximin_excluding(app_glofas_search3_grid(target, "basin_a"), 22L, keys)
      keys <- c(keys, app_glofas_search3_candidate_key(a))
      b <- app_glofas_search3_maximin_excluding(app_glofas_search3_grid(target, "basin_b"), 8L, keys)
      keys <- c(keys, app_glofas_search3_candidate_key(b))
      d2 <- app_glofas_search3_maximin_excluding(app_glofas_search3_grid(target, "d2"), 4L, keys)
      generated <- app_bind_rows_fill(list(a, b, d2))
    }
    generated$source_candidate_id <- NA_character_
    generated$control_label <- NA_character_
    out <- app_bind_rows_fill(list(fixed, generated))
    if (nrow(out) != 40L || anyDuplicated(app_glofas_search3_candidate_key(out))) {
      stop(sprintf("Search III %s manifest is not exactly 40 unique candidates.", target), call. = FALSE)
    }
    out$candidate_id <- sprintf("search3_%s_%03d", prefix, seq_len(nrow(out)))
    out$priority <- seq_len(nrow(out))
    out$mandatory_control <- out$candidate_role == "mandatory_control"
    out
  }
  out <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), make_target))
  rownames(out) <- NULL
  out[, c("candidate_id", "priority", setdiff(names(out), c("candidate_id", "priority"))), drop = FALSE]
}

app_glofas_search3_rhs_priors <- function(target) {
  if (target == "reference") {
    data.frame(
      prior_id = c("search3_ref_m015_learned", "search3_ref_m025_learned", "search3_ref_m040_learned"),
      prior_mode = "calibrated_m0", m0 = c(15, 25, 40), rhs_zeta2_fixed = NA_real_,
      rhs_a_zeta = 2, rhs_b_zeta = 4, stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      prior_id = c("search3_dis_m060_fixed16", "search3_dis_m100_fixed16", "search3_dis_m160_fixed16"),
      prior_mode = "calibrated_m0", m0 = c(60, 100, 160), rhs_zeta2_fixed = 16,
      rhs_a_zeta = 2, rhs_b_zeta = 4, stringsAsFactors = FALSE
    )
  }
}

app_glofas_search3_rhs_jobs <- function(architectures, folds, priors, stage, seeds = NULL) {
  jobs <- app_glofas_search2_rhs_manifest(architectures, folds, priors, stage)
  jobs$rhs_max_iter <- 200L
  jobs$rhs_min_iter <- 200L
  jobs$rhs_tol <- 1.0e-4
  jobs$rhs_freeze_beta_warmup_iters <- 20L
  jobs$rhs_min_beta_updates <- 180L
  jobs$rhs_freeze_tau_warmup_iters <- 0L
  jobs$rhs_min_tau_updates <- 30L
  jobs$terminal_consecutive_passes <- 3L
  if (!is.null(seeds)) {
    base <- jobs
    jobs <- app_bind_rows_fill(lapply(as.integer(seeds), function(seed) {
      x <- base
      x$base_candidate_id <- x$candidate_id
      x$seed <- seed
      x$candidate_id <- paste0(x$candidate_id, "__seed", seed)
      x$design_group_id <- paste(x$target, x$candidate_id, x$fold_id, sep = "__")
      x$job_id <- paste(stage, x$candidate_id, x$prior_id, x$fold_id, sep = "__")
      x
    }))
  }
  jobs
}

app_glofas_search3_fit_and_forecast <- function(model_packet, job_row, forecast_backend = "auto", prepared = NULL) {
  method <- as.character(job_row$method[[1L]])
  if (method == "rhs") {
    required <- c("rhs_max_iter", "rhs_min_iter", "rhs_freeze_beta_warmup_iters", "rhs_min_beta_updates")
    if (any(!required %in% names(job_row)) || job_row$rhs_max_iter[[1L]] != 200L ||
        job_row$rhs_min_iter[[1L]] != 200L || job_row$rhs_freeze_beta_warmup_iters[[1L]] != 20L ||
        job_row$rhs_min_beta_updates[[1L]] < 180L) {
      stop("Search III RHS jobs require the frozen exact-200/beta-freeze contract.", call. = FALSE)
    }
  }
  out <- app_glofas_search2_fit_and_forecast(model_packet, job_row, forecast_backend, prepared)
  if (method == "ridge") {
    out$summary$fit_completed <- TRUE
    out$summary$terminal_certificate_pass <- TRUE
    out$summary$terminal_certificate_passes <- NA_integer_
  } else {
    trace <- out$trace
    need <- as.integer(job_row$terminal_consecutive_passes[[1L]] %||% 3L)
    terminal <- utils::tail(trace, need)
    pass <- nrow(trace) == 200L && nrow(terminal) == need &&
      all(is.finite(terminal$max_delta)) && all(terminal$max_delta <= as.numeric(job_row$rhs_tol[[1L]])) &&
      sum(trace$beta_solve_performed %||% FALSE) >= 180L
    out$summary$fit_completed <- nrow(trace) == 200L
    out$summary$terminal_certificate_pass <- pass
    out$summary$terminal_certificate_passes <- need
  }
  out
}

app_glofas_search3_phase_aggregate <- function(score_rows, folds, fit_rows = data.frame(), require_complete = TRUE) {
  if (!nrow(score_rows)) return(data.frame())
  primary <- score_rows[score_rows$score_window == "primary_28", , drop = FALSE]
  secondary <- score_rows[score_rows$score_window == "secondary_30", , drop = FALSE]
  fold_meta <- folds[, c("fold_id", "wet_season", "phase", "panel", "primary"), drop = FALSE]
  primary <- merge(primary, fold_meta, by = "fold_id", all.x = TRUE, sort = FALSE)
  primary <- primary[primary$primary, , drop = FALSE]
  candidate <- if ("base_candidate_id" %in% names(primary)) {
    ifelse(is.na(primary$base_candidate_id) | !nzchar(primary$base_candidate_id), primary$candidate_id, primary$base_candidate_id)
  } else sub("__seed[0-9]+$", "", primary$candidate_id)
  primary$selection_candidate_id <- candidate
  keys <- intersect(c("target", "selection_candidate_id", "method", "prior_id"), names(primary))
  keys <- keys[vapply(primary[keys], function(x) any(!is.na(x)), logical(1L))]
  group <- interaction(primary[keys], drop = TRUE, lex.order = TRUE)
  rows <- lapply(split(seq_len(nrow(primary)), group), function(idx) {
    x <- primary[idx, , drop = FALSE]
    phase_means <- tapply(x$mean_crps, x$phase, mean)
    expected_phases <- app_glofas_search3_phases()
    complete <- all(expected_phases %in% names(phase_means))
    if (isTRUE(require_complete) && !complete) stop("Search III aggregate is missing a rainy-season phase.", call. = FALSE)
    sec <- secondary[secondary$job_id %in% x$job_id, , drop = FALSE]
    out <- data.frame(
      target = x$target[[1L]], candidate_id = x$selection_candidate_id[[1L]],
      method = x$method[[1L]], prior_id = if ("prior_id" %in% names(x)) x$prior_id[[1L]] else NA_character_,
      n_cells = nrow(x), n_folds = length(unique(x$fold_id)), n_seeds = length(unique(x$seed %||% NA_integer_)),
      phase_balanced_crps = mean(phase_means[expected_phases], na.rm = TRUE),
      worst_primary_crps = max(x$mean_crps), mean_secondary_crps = mean(sec$mean_crps),
      complete_phase_panel = complete, stringsAsFactors = FALSE
    )
    for (phase in expected_phases) out[[paste0("crps_", phase)]] <- as.numeric(phase_means[[phase]] %||% NA_real_)
    out
  })
  out <- do.call(rbind, rows)
  for (nm in c(
    "n_cells", "n_folds", "n_seeds", "phase_balanced_crps",
    "worst_primary_crps", "mean_secondary_crps",
    paste0("crps_", app_glofas_search3_phases())
  )) out[[nm]] <- as.numeric(out[[nm]])
  out$complete_phase_panel <- as.logical(out$complete_phase_panel)
  if (nrow(fit_rows)) {
    fit_rows$selection_candidate_id <- if ("base_candidate_id" %in% names(fit_rows)) {
      ifelse(is.na(fit_rows$base_candidate_id) | !nzchar(fit_rows$base_candidate_id), fit_rows$candidate_id, fit_rows$base_candidate_id)
    } else sub("__seed[0-9]+$", "", fit_rows$candidate_id)
    cert_keys <- intersect(c("target", "selection_candidate_id", "method", "prior_id"), names(fit_rows))
    cert_keys <- cert_keys[vapply(fit_rows[cert_keys], function(x) any(!is.na(x)), logical(1L))]
    cert <- aggregate(
      cbind(
        fit_completed = as.numeric(fit_rows$fit_completed %||% TRUE),
        terminal_certificate_pass = as.numeric(fit_rows$terminal_certificate_pass %||% TRUE)
      ),
      fit_rows[, cert_keys, drop = FALSE], mean
    )
    names(cert)[names(cert) == "selection_candidate_id"] <- "candidate_id"
    out <- merge(out, cert, by = intersect(c("target", "candidate_id", "method", "prior_id"), names(cert)), all.x = TRUE)
  }
  out$computationally_eligible <- out$complete_phase_panel &
    ifelse(is.na(out$fit_completed), TRUE, out$fit_completed == 1) &
    ifelse(is.na(out$terminal_certificate_pass), TRUE, out$terminal_certificate_pass == 1)
  # Backward-compatible alias. Scientific adoption additionally applies the
  # frozen guardrail, historical-fit, breadth, and development-direction gates.
  out$promotion_eligible <- out$computationally_eligible
  out <- out[order(out$target, !out$promotion_eligible, round(out$phase_balanced_crps, 4), out$worst_primary_crps, out$mean_secondary_crps), , drop = FALSE]
  out$rank <- ave(seq_len(nrow(out)), out$target, FUN = seq_along)
  rownames(out) <- NULL
  out
}

app_glofas_search3_pick_diverse <- function(candidates, ids, n) {
  pool <- candidates[candidates$candidate_id %in% ids, , drop = FALSE]
  if (!nrow(pool) || n <= 0L) return(character())
  as.character(app_glofas_search2_maximin(pool, min(n, nrow(pool)))$candidate_id)
}

app_glofas_search3_select_pass_a <- function(aggregate, candidates) {
  picked <- lapply(c("reference", "discrepancy"), function(target) {
    score <- aggregate[aggregate$target == target & aggregate$promotion_eligible, , drop = FALSE]
    score <- score[order(round(score$phase_balanced_crps, 4), score$worst_primary_crps, score$mean_secondary_crps), , drop = FALSE]
    mandatory <- candidates$candidate_id[candidates$target == target & candidates$mandatory_control]
    incumbent <- candidates$candidate_id[candidates$target == target & !is.na(candidates$control_label) & candidates$control_label == "search2_incumbent"]
    selected <- mandatory
    selected <- unique(c(selected, utils::head(setdiff(score$candidate_id, selected), 10L)))
    incumbent_score <- score$phase_balanced_crps[match(incumbent, score$candidate_id)]
    eligible <- score$candidate_id[score$phase_balanced_crps <= 1.15 * incumbent_score]
    diverse <- app_glofas_search3_pick_diverse(candidates, setdiff(eligible, selected), 20L - length(selected))
    selected <- unique(c(selected, diverse))
    selected <- unique(c(selected, score$candidate_id))[seq_len(20L)]
    out <- candidates[match(selected, candidates$candidate_id), , drop = FALSE]
    out$selection_stage <- "ridge_pass_a"
    out$selection_order <- seq_len(nrow(out))
    out
  })
  out <- app_bind_rows_fill(picked)
  if (nrow(out) != 40L) stop("Search III Pass A must advance exactly 20 candidates per target.", call. = FALSE)
  out
}

app_glofas_search3_select_guard_pool <- function(aggregate, candidates) {
  out <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    score <- aggregate[aggregate$target == target & aggregate$promotion_eligible, , drop = FALSE]
    score <- score[order(round(score$phase_balanced_crps, 4), score$worst_primary_crps, score$mean_secondary_crps), , drop = FALSE]
    incumbent <- candidates$candidate_id[candidates$target == target & !is.na(candidates$control_label) & candidates$control_label == "search2_incumbent"]
    selected <- unique(c(utils::head(score$candidate_id, 8L), incumbent))
    incumbent_score <- score$phase_balanced_crps[match(incumbent, score$candidate_id)]
    eligible <- score$candidate_id[score$phase_balanced_crps <= 1.15 * incumbent_score]
    selected <- unique(c(selected, app_glofas_search3_pick_diverse(candidates, setdiff(eligible, selected), 12L - length(selected))))
    selected <- unique(c(selected, score$candidate_id))[seq_len(12L)]
    candidates[match(selected, candidates$candidate_id), , drop = FALSE]
  }))
  if (nrow(out) != 24L) stop("Search III guardrail pool must contain 12 candidates per target.", call. = FALSE)
  out
}

app_glofas_search3_select_rhs_shortlist <- function(full_aggregate, guard_scores, candidates) {
  out <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    score <- full_aggregate[full_aggregate$target == target & full_aggregate$promotion_eligible, , drop = FALSE]
    score <- score[order(round(score$phase_balanced_crps, 4), score$worst_primary_crps, score$mean_secondary_crps), , drop = FALSE]
    guard <- guard_scores[guard_scores$target == target, , drop = FALSE]
    incumbent <- candidates$candidate_id[candidates$target == target & !is.na(candidates$control_label) & candidates$control_label == "search2_incumbent"]
    incumbent_guard <- mean(guard$mean_crps[guard$candidate_id == incumbent])
    guard_mean <- tapply(guard$mean_crps, guard$candidate_id, mean)
    eligible <- names(guard_mean)[is.finite(guard_mean) & guard_mean <= 1.10 * incumbent_guard]
    ranked <- score$candidate_id[score$candidate_id %in% eligible]
    selected <- unique(c(utils::head(ranked, 6L), incumbent))
    margin <- score$candidate_id[score$phase_balanced_crps <= 1.10 * score$phase_balanced_crps[match(incumbent, score$candidate_id)]]
    selected <- unique(c(selected, app_glofas_search3_pick_diverse(candidates, setdiff(intersect(eligible, margin), selected), 8L - length(selected))))
    selected <- unique(c(selected, ranked))
    if (length(selected) < 8L) stop(sprintf("Fewer than eight %s candidates pass dry/transition eligibility.", target), call. = FALSE)
    candidates[match(selected[seq_len(8L)], candidates$candidate_id), , drop = FALSE]
  }))
  if (nrow(out) != 16L) stop("Search III RHS shortlist must contain eight architectures per target.", call. = FALSE)
  out
}

app_glofas_search3_select_pilot_architectures <- function(full_aggregate, shortlist, candidates) {
  app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    score <- full_aggregate[full_aggregate$target == target & full_aggregate$promotion_eligible &
      full_aggregate$candidate_id %in% shortlist$candidate_id, , drop = FALSE]
    score <- score[order(round(score$phase_balanced_crps, 4), score$worst_primary_crps, score$mean_secondary_crps), , drop = FALSE]
    incumbent <- candidates$candidate_id[candidates$target == target & !is.na(candidates$control_label) & candidates$control_label == "search2_incumbent"]
    ids <- unique(c(incumbent, setdiff(score$candidate_id, incumbent)))[seq_len(3L)]
    candidates[match(ids, candidates$candidate_id), , drop = FALSE]
  }))
}

app_glofas_search3_select_prior <- function(score_rows) {
  primary <- score_rows[score_rows$score_window == "primary_28", , drop = FALSE]
  x <- aggregate(mean_crps ~ target + prior_id, primary, function(v) c(mean = mean(v), worst = max(v)))
  values <- x$mean_crps
  if (!is.matrix(values)) values <- do.call(rbind, values)
  x$mean_crps <- values[, "mean"]
  x$worst_crps <- values[, "worst"]
  x <- x[order(x$target, round(x$mean_crps, 4), x$worst_crps), , drop = FALSE]
  x$rank <- ave(seq_len(nrow(x)), x$target, FUN = seq_along)
  x[x$rank == 1L, , drop = FALSE]
}

app_glofas_search3_select_finalists <- function(rhs_aggregate, candidates) {
  out <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
    score <- rhs_aggregate[rhs_aggregate$target == target & rhs_aggregate$promotion_eligible, , drop = FALSE]
    score <- score[order(round(score$phase_balanced_crps, 4), score$worst_primary_crps, score$mean_secondary_crps), , drop = FALSE]
    incumbent <- candidates$candidate_id[candidates$target == target & !is.na(candidates$control_label) & candidates$control_label == "search2_incumbent"]
    ids <- unique(c(incumbent, setdiff(score$candidate_id, incumbent)))
    if (length(ids) < 3L) stop("Search III needs the incumbent and two eligible challengers per target.", call. = FALSE)
    candidates[match(ids[seq_len(3L)], candidates$candidate_id), , drop = FALSE]
  }))
  if (nrow(out) != 6L) stop("Search III confirmation must freeze exactly six candidates.", call. = FALSE)
  out
}

app_glofas_search3_seeds <- function(target) {
  if (target == "reference") c(20260512L, 20260914L, 20260915L, 20260916L) else
    c(20261521L, 20260914L, 20260915L, 20260916L)
}
