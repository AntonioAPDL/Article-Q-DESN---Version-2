# Phase 176-180 targeted post-M0 recovery for held exAL validation cells.

app_joint_exqdesn_phase176_dirs <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root()
) {
  source <- app_joint_exqdesn_phase171_175_dirs(cache_root)
  c(source, list(
    phase176 = file.path(
      cache_root, "joint_exqdesn_phase176_post_m0_functional_audit_20260813"
    ),
    phase177_freeze = file.path(
      cache_root, "joint_exqdesn_phase177_same_spec_m0_freeze_20260813"
    ),
    phase177 = file.path(
      cache_root, "joint_exqdesn_phase177_same_spec_m0_confirmation_20260813"
    ),
    phase177_orchestration = file.path(
      cache_root, "joint_exqdesn_phase177_same_spec_m0_confirmation_20260813_orchestration"
    ),
    phase177_audit = file.path(
      cache_root, "joint_exqdesn_phase177_same_spec_m0_audit_20260813"
    ),
    phase178_freeze = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_case_specific_screen_freeze_20260813"
    ),
    phase178_fixtures = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_protected_fixtures_20260813"
    ),
    phase178 = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_case_specific_screen_20260813"
    ),
    phase178_orchestration = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_case_specific_screen_20260813_orchestration"
    ),
    phase178_audit = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_case_specific_screen_audit_20260813"
    ),
    phase178_m0_freeze = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_ranking_freeze_20260813"
    ),
    phase178_m0 = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_ranking_20260813"
    ),
    phase178_m0_orchestration = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_ranking_20260813_orchestration"
    ),
    phase178_m0_audit = file.path(
      cache_root, "joint_exqdesn_phase178_post_m0_ranking_audit_20260813"
    ),
    phase179_freeze = file.path(
      cache_root, "joint_exqdesn_phase179_post_m0_winner_confirmation_freeze_20260813"
    ),
    phase179 = file.path(
      cache_root, "joint_exqdesn_phase179_post_m0_winner_confirmation_20260813"
    ),
    phase179_orchestration = file.path(
      cache_root, "joint_exqdesn_phase179_post_m0_winner_confirmation_20260813_orchestration"
    ),
    phase179_audit = file.path(
      cache_root, "joint_exqdesn_phase179_post_m0_winner_audit_20260813"
    ),
    phase179_article_freeze = file.path(
      cache_root, "joint_exqdesn_phase179_article_fixture_confirmation_freeze_20260813"
    ),
    phase179_article_fixtures = file.path(
      cache_root, "joint_exqdesn_phase179_article_fixture_shards_20260813"
    ),
    phase179_article = file.path(
      cache_root, "joint_exqdesn_phase179_article_fixture_confirmation_20260813"
    ),
    phase179_article_orchestration = file.path(
      cache_root, "joint_exqdesn_phase179_article_fixture_confirmation_20260813_orchestration"
    ),
    phase179_article_audit = file.path(
      cache_root, "joint_exqdesn_phase179_article_fixture_confirmation_audit_20260813"
    ),
    phase180 = file.path(
      cache_root, "joint_exqdesn_phase180_post_m0_recovery_packet_20260813"
    ),
    phase180_staging = file.path(
      cache_root, "joint_exqdesn_phase180_article_assets_staging_20260813"
    ),
    phase180_handoff = file.path(
      cache_root, "joint_exqdesn_phase180_integration_handoff_20260813"
    )
  ))
}

app_joint_exqdesn_phase176_required_case_ids <- function() {
  c(
    "laplace_bridge__exqdesn_rhs_independent_vb",
    "normal_bridge__exqdesn_rhs_independent_vb",
    "persistent_heavy_tail__exqdesn_rhs_independent_vb",
    "regime_shift__exqdesn_rhs_independent_vb",
    "regime_shift__joint_exqdesn_rhs_vb"
  )
}

app_joint_exqdesn_phase176_policy_path <- function() {
  app_path("application/config/joint_exqdesn_phase176_180_post_m0_recovery_policy_v1.csv")
}

app_joint_exqdesn_phase178_authority_path <- function() {
  app_path("application/config/joint_exqdesn_phase178_prior_screen_authority_v1.csv")
}

app_joint_exqdesn_phase178_load_authority <- function(
  path = app_joint_exqdesn_phase178_authority_path()
) {
  out <- app_read_csv(path)
  app_check_required_columns(out, c(
    "schema_version", "prior_stage", "control_family", "prior_inference",
    "authority_after_exact_m0", "phase178_use", "relaunch_policy", "rationale"
  ), "Phase178 prior-screen authority")
  if (!nrow(out) || anyDuplicated(out$prior_stage) ||
      !"phases_118_150" %in% out$prior_stage ||
      !"phases_167_170" %in% out$prior_stage) {
    stop("Phase178 prior-screen authority is malformed.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase176_load_policy <- function(
  path = app_joint_exqdesn_phase176_policy_path()
) {
  policy <- app_read_csv(path)
  required <- c(
    "schema_version", "policy_id", "phase176_within_q99_severe",
    "phase176_within_overlap_severe", "phase176_between_q99_severe",
    "phase176_between_overlap_severe", "phase176_near_tie_floor",
    "phase177_n_chains", "phase177_n_iter", "phase177_burn",
    "phase177_thin", "phase177_check_crps_relative_ceiling",
    "phase177_fit_mae_relative_ceiling", "pre_m0_spec_ranking_authoritative",
    "exact_m0_required_for_new_winner", "article_fixture_allowed_for_selection",
    "selection_scope"
  )
  app_check_required_columns(policy, required, "Phase176-180 recovery policy")
  if (nrow(policy) != 1L || policy$policy_id[[1L]] != "post_m0_recovery_v1" ||
      isTRUE(policy$pre_m0_spec_ranking_authoritative[[1L]]) ||
      !isTRUE(policy$exact_m0_required_for_new_winner[[1L]]) ||
      isTRUE(policy$article_fixture_allowed_for_selection[[1L]]) ||
      policy$selection_scope[[1L]] != "case_specific_scenario_readout") {
    stop("Phase176-180 recovery policy violates its scientific boundary.", call. = FALSE)
  }
  policy
}

app_joint_exqdesn_phase176_source_dirs <- function(dirs) {
  list(
    phase171_freeze = dirs$phase171,
    phase172_confirmation = dirs$phase172,
    phase173_audit = dirs$phase173,
    phase173b_decision = dirs$phase173b,
    phase174_packet = dirs$phase174,
    phase155_historical_packet = dirs$phase155
  )
}

app_joint_exqdesn_phase176_verify_sources <- function(dirs) {
  sources <- app_joint_exqdesn_phase176_source_dirs(dirs)
  out <- app_joint_qdesn_bind_rows(lapply(names(sources), function(source_id) {
    app_joint_exqdesn_verify_manifest(sources[[source_id]], source_id)
  }))
  if (!nrow(out) || any(out$status != "pass")) {
    stop("Phase176 source-manifest verification failed.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase176_fallback_registry <- function(dirs) {
  decision <- app_read_csv(file.path(dirs$phase173b, "case_promotion_decision.csv"))
  required <- c(
    "case_id", "scenario_id", "fit_structure", "source_model_id",
    "source_candidate_id", "historical_forecast_truth_mae",
    "m0_forecast_truth_mae", "m0_forecast_truth_mae_jackknife_mcse",
    "qhat_functional_status", "posterior_summary_status",
    "posterior_summary_direction_consistent",
    "posterior_summary_forecast_mae_range", "action", "rationale"
  )
  app_check_required_columns(decision, required, "Phase173B promotion decision")
  wanted <- app_joint_exqdesn_phase176_required_case_ids()
  out <- decision[match(wanted, decision$case_id), required, drop = FALSE]
  if (nrow(out) != 5L || any(is.na(out$case_id)) ||
      !identical(as.character(out$case_id), wanted) ||
      any(out$action != "retain_historical_functional_hold")) {
    stop("Phase176 did not resolve the exact five held Phase173B cells.", call. = FALSE)
  }
  out$phase176_priority <- seq_len(nrow(out))
  out$screening_history_policy <- paste(
    "pre_M0_DESN_tau0_results_are_candidate_region_history_only;",
    "post_M0_confirmation_required_for_any_new_winner"
  )
  out$article_fixture_selection_allowed <- FALSE
  out
}

app_joint_exqdesn_phase176_subset_fit <- function(fit, draw_index) {
  draw_index <- as.integer(draw_index)
  n <- nrow(fit$beta_draws)
  if (!length(draw_index) || any(draw_index < 1L | draw_index > n)) {
    stop("Phase176 draw subset is invalid.", call. = FALSE)
  }
  out <- fit
  for (block in c("beta", "alpha", "sigma", "gamma")) {
    field <- paste0(block, "_draws")
    out[[field]] <- fit[[field]][draw_index, , drop = FALSE]
    out[[paste0(block, "_mean")]] <- colMeans(out[[field]])
  }
  out
}

app_joint_exqdesn_phase176_pair_metrics <- function(a, b) {
  keys <- c("row_index", "quantile_index", "tau")
  joined <- merge(a, b, by = keys, suffixes = c("_a", "_b"), sort = FALSE)
  joined$absolute_delta <- abs(joined$posterior_mean_b - joined$posterior_mean_a)
  pooled_sd <- sqrt((joined$posterior_sd_a^2 + joined$posterior_sd_b^2) / 2)
  joined$standardized_delta <- joined$absolute_delta /
    pmax(pooled_sd, .Machine$double.eps)
  overlap <- pmax(
    0,
    pmin(joined$q95_a, joined$q95_b) - pmax(joined$q05_a, joined$q05_b)
  )
  union <- pmax(joined$q95_a, joined$q95_b) -
    pmin(joined$q05_a, joined$q05_b)
  joined$central90_overlap_fraction <- overlap /
    pmax(union, .Machine$double.eps)
  joined
}

app_joint_exqdesn_phase176_pairwise_qhat <- function(
  moments, case_id, window, row_context = NULL
) {
  chain_ids <- sort(as.integer(names(moments)))
  pairs <- utils::combn(chain_ids, 2L, simplify = FALSE)
  detail <- vector("list", length(pairs))
  summary <- vector("list", length(pairs))
  for (ii in seq_along(pairs)) {
    pair <- pairs[[ii]]
    x <- app_joint_exqdesn_phase176_pair_metrics(
      moments[[as.character(pair[[1L]])]],
      moments[[as.character(pair[[2L]])]]
    )
    x$case_id <- case_id
    x$window <- window
    x$chain_a <- pair[[1L]]
    x$chain_b <- pair[[2L]]
    if (!is.null(row_context)) {
      context <- row_context[x$row_index, , drop = FALSE]
      x <- cbind(x, context)
    }
    detail[[ii]] <- x
    summary[[ii]] <- data.frame(
      case_id = case_id,
      window = window,
      chain_a = pair[[1L]],
      chain_b = pair[[2L]],
      mean_abs_qhat_delta = mean(x$absolute_delta),
      max_abs_qhat_delta = max(x$absolute_delta),
      rms_standardized_qhat_delta = sqrt(mean(x$standardized_delta^2)),
      q99_standardized_qhat_delta = as.numeric(stats::quantile(
        x$standardized_delta, 0.99, names = FALSE, type = 8
      )),
      q01_central90_overlap_fraction = as.numeric(stats::quantile(
        x$central90_overlap_fraction, 0.01, names = FALSE, type = 8
      )),
      stringsAsFactors = FALSE
    )
  }
  list(
    detail = app_joint_qdesn_bind_rows(detail),
    summary = app_joint_qdesn_bind_rows(summary)
  )
}

app_joint_exqdesn_phase176_canonical_clusters <- function(cluster, chain_ids) {
  cluster <- as.integer(cluster)
  groups <- split(as.integer(chain_ids), cluster)
  order_groups <- order(vapply(groups, min, integer(1L)))
  map <- setNames(seq_along(order_groups), names(groups)[order_groups])
  unname(map[as.character(cluster)])
}

app_joint_exqdesn_phase176_cluster_assignments <- function(
  pairwise_summary, case_id, cluster_counts = c(2L, 3L)
) {
  x <- pairwise_summary[pairwise_summary$window == "forecast", , drop = FALSE]
  chain_ids <- sort(unique(c(x$chain_a, x$chain_b)))
  if (length(chain_ids) < max(cluster_counts)) {
    stop("Phase176 has too few chains for the declared cluster audit.", call. = FALSE)
  }
  d <- matrix(0, length(chain_ids), length(chain_ids), dimnames = list(chain_ids, chain_ids))
  for (ii in seq_len(nrow(x))) {
    a <- as.character(x$chain_a[[ii]])
    b <- as.character(x$chain_b[[ii]])
    tie_break <- 1e-12 * (min(x$chain_a[[ii]], x$chain_b[[ii]]) * 100L +
      max(x$chain_a[[ii]], x$chain_b[[ii]]))
    value <- x$rms_standardized_qhat_delta[[ii]] + tie_break
    d[a, b] <- d[b, a] <- value
  }
  tree <- stats::hclust(stats::as.dist(d), method = "average")
  rows <- lapply(as.integer(cluster_counts), function(k) {
    cluster <- stats::cutree(tree, k = k)[as.character(chain_ids)]
    cluster <- app_joint_exqdesn_phase176_canonical_clusters(cluster, chain_ids)
    data.frame(
      case_id = case_id,
      cluster_count = k,
      chain_id = chain_ids,
      cluster_id = cluster,
      clustering_window = "forecast",
      clustering_metric = "RMS pairwise standardized posterior-qhat distance",
      truth_used_for_clustering = FALSE,
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase176_within_chain_drift <- function(
  fits, fixture, forecast_fixture, case_id
) {
  windows <- list(fit = fixture$Z, forecast = forecast_fixture$Z)
  summaries <- list()
  details <- list()
  at <- 0L
  for (chain_id in seq_along(fits)) {
    n <- nrow(fits[[chain_id]]$beta_draws)
    midpoint <- floor(n / 2L)
    early <- app_joint_exqdesn_phase176_subset_fit(fits[[chain_id]], seq_len(midpoint))
    late <- app_joint_exqdesn_phase176_subset_fit(
      fits[[chain_id]], seq.int(midpoint + 1L, n)
    )
    for (window in names(windows)) {
      at <- at + 1L
      a <- app_joint_exqdesn_phase170_qhat_moments(list(early), windows[[window]], fixture$tau)
      b <- app_joint_exqdesn_phase170_qhat_moments(list(late), windows[[window]], fixture$tau)
      x <- app_joint_exqdesn_phase176_pair_metrics(a, b)
      x$case_id <- case_id
      x$chain_id <- chain_id
      x$window <- window
      details[[at]] <- x
      summaries[[at]] <- data.frame(
        case_id = case_id,
        chain_id = chain_id,
        window = window,
        early_draws = midpoint,
        late_draws = n - midpoint,
        mean_abs_qhat_delta = mean(x$absolute_delta),
        q99_standardized_qhat_delta = as.numeric(stats::quantile(
          x$standardized_delta, 0.99, names = FALSE, type = 8
        )),
        q01_central90_overlap_fraction = as.numeric(stats::quantile(
          x$central90_overlap_fraction, 0.01, names = FALSE, type = 8
        )),
        stringsAsFactors = FALSE
      )
    }
  }
  list(
    detail = app_joint_qdesn_bind_rows(details),
    summary = app_joint_qdesn_bind_rows(summaries)
  )
}

app_joint_exqdesn_phase176_parameter_context <- function(fits, fixture, case_id) {
  K <- length(fixture$tau)
  tau_rows <- list()
  block_rows <- list()
  for (chain_id in seq_along(fits)) {
    fit <- fits[[chain_id]]
    for (k in seq_len(K)) {
      gamma <- fit$gamma_draws[, k]
      sigma <- fit$sigma_draws[, k]
      actual_sd <- app_joint_exqdesn_phase169_transformed_draw(
        fit, fixture$tau, "actual_sd", k
      )
      tau_rows[[length(tau_rows) + 1L]] <- data.frame(
        case_id = case_id, chain_id = chain_id, quantile_index = k,
        tau = fixture$tau[[k]], gamma_mean = mean(gamma),
        gamma_sd = stats::sd(gamma), sigma_mean = mean(sigma),
        sigma_sd = stats::sd(sigma), actual_sd_mean = mean(actual_sd),
        actual_sd_sd = stats::sd(actual_sd), stringsAsFactors = FALSE
      )
    }
    block_rows[[chain_id]] <- data.frame(
      case_id = case_id, chain_id = chain_id,
      alpha_l2 = sqrt(sum(colMeans(fit$alpha_draws)^2)),
      beta_l2 = sqrt(sum(colMeans(fit$beta_draws)^2)),
      mean_abs_alpha = mean(abs(colMeans(fit$alpha_draws))),
      mean_abs_beta = mean(abs(colMeans(fit$beta_draws))),
      stringsAsFactors = FALSE
    )
  }
  list(
    tau = app_joint_qdesn_bind_rows(tau_rows),
    block = app_joint_qdesn_bind_rows(block_rows)
  )
}

app_joint_exqdesn_phase176_group_sensitivity <- function(
  fits, assignments, fixture, artifacts, meta, historical_mae
) {
  rows <- list()
  for (k in sort(unique(assignments$cluster_count))) {
    block <- assignments[assignments$cluster_count == k, , drop = FALSE]
    for (cluster_id in sort(unique(block$cluster_id))) {
      members <- block$chain_id[block$cluster_id == cluster_id]
      complements <- setdiff(seq_along(fits), members)
      groups <- list(cluster_only = members, leave_cluster_out = complements)
      for (role in names(groups)) {
        ids <- groups[[role]]
        if (!length(ids)) next
        pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
          fits[ids], fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
        )
        scored <- app_joint_exqdesn_phase173_score_fit(
          pooled, fixture, artifacts, meta,
          sprintf("phase176_k%d_c%d_%s", k, cluster_id, role)
        )
        rows[[length(rows) + 1L]] <- cbind(
          meta,
          data.frame(
            cluster_count = k, cluster_id = cluster_id,
            sensitivity_role = role,
            chain_ids = paste(ids, collapse = ";"), chain_count = length(ids),
            historical_forecast_truth_mae = historical_mae,
            forecast_mae_delta_vs_historical =
              scored$metrics$forecast_truth_mae[[1L]] - historical_mae,
            stringsAsFactors = FALSE
          ),
          scored$metrics
        )
      }
    }
  }
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase176_localize <- function(pair_detail, drift_detail) {
  summarize <- function(x, source, group_fields) {
    groups <- interaction(x[group_fields], drop = TRUE, lex.order = TRUE)
    rows <- lapply(split(x, groups), function(block) {
      key <- block[1L, group_fields, drop = FALSE]
      cbind(
        data.frame(diagnostic_source = source, stringsAsFactors = FALSE), key,
        data.frame(
          comparisons = nrow(block),
          mean_abs_qhat_delta = mean(block$absolute_delta),
          q95_standardized_qhat_delta = as.numeric(stats::quantile(
            block$standardized_delta, 0.95, names = FALSE, type = 8
          )),
          q99_standardized_qhat_delta = as.numeric(stats::quantile(
            block$standardized_delta, 0.99, names = FALSE, type = 8
          )),
          q01_central90_overlap_fraction = as.numeric(stats::quantile(
            block$central90_overlap_fraction, 0.01, names = FALSE, type = 8
          )), stringsAsFactors = FALSE
        )
      )
    })
    app_joint_qdesn_bind_rows(rows)
  }
  pair_detail$tau_region <- ifelse(
    pair_detail$tau <= 0.10, "lower_tail",
    ifelse(pair_detail$tau >= 0.90, "upper_tail", "central")
  )
  drift_detail$tau_region <- ifelse(
    drift_detail$tau <= 0.10, "lower_tail",
    ifelse(drift_detail$tau >= 0.90, "upper_tail", "central")
  )
  app_joint_qdesn_bind_rows(list(
    summarize(pair_detail, "between_chain_pair", c("case_id", "window", "tau", "tau_region")),
    summarize(drift_detail, "within_chain_early_late", c("case_id", "window", "tau", "tau_region"))
  ))
}

app_joint_exqdesn_phase176_classify <- function(
  fallback, pairwise, drift, cluster_sensitivity,
  policy = app_joint_exqdesn_phase176_load_policy()
) {
  rows <- lapply(seq_len(nrow(fallback)), function(ii) {
    cell <- fallback[ii, , drop = FALSE]
    case_id <- cell$case_id[[1L]]
    p <- pairwise[pairwise$case_id == case_id & pairwise$window == "forecast", , drop = FALSE]
    w <- drift[drift$case_id == case_id & drift$window == "forecast", , drop = FALSE]
    s <- cluster_sensitivity[
      cluster_sensitivity$case_id == case_id &
        cluster_sensitivity$sensitivity_role == "cluster_only",
      , drop = FALSE
    ]
    historical <- as.numeric(cell$historical_forecast_truth_mae[[1L]])
    m0 <- as.numeric(cell$m0_forecast_truth_mae[[1L]])
    mcse <- as.numeric(cell$m0_forecast_truth_mae_jackknife_mcse[[1L]])
    if (!is.finite(mcse)) mcse <- 0
    cluster_min <- if (nrow(s)) min(s$forecast_truth_mae) else Inf
    cluster_max <- if (nrow(s)) max(s$forecast_truth_mae) else Inf
    any_cluster_improves <- is.finite(cluster_min) && cluster_min < historical
    all_clusters_improve <- is.finite(cluster_max) && cluster_max < historical
    m0_promising <- m0 <= historical + max(
      2 * mcse, as.numeric(policy$phase176_near_tie_floor[[1L]])
    )
    within_chain_severe <- max(w$q99_standardized_qhat_delta) >
      as.numeric(policy$phase176_within_q99_severe[[1L]]) ||
      min(w$q01_central90_overlap_fraction) <
        as.numeric(policy$phase176_within_overlap_severe[[1L]])
    between_chain_severe <- max(p$q99_standardized_qhat_delta) >
      as.numeric(policy$phase176_between_q99_severe[[1L]]) ||
      min(p$q01_central90_overlap_fraction) <
        as.numeric(policy$phase176_between_overlap_severe[[1L]])
    same_spec <- !within_chain_severe &&
      (m0_promising || any_cluster_improves) &&
      !(cell$fit_structure[[1L]] == "joint" && case_id ==
          "regime_shift__joint_exqdesn_rhs_vb" && !all_clusters_improve)
    classification <- if (same_spec) {
      "same_spec_additional_chains_eligible"
    } else {
      "post_m0_spec_screen_required"
    }
    rationale <- if (same_spec) {
      paste(
        "At least one posterior-chain allocation is competitive with the retained row,",
        "and within-chain qhat drift is not severe; estimate mode weights with new seeds",
        "before changing the specification."
      )
    } else {
      paste(
        "The current exact-M0 specification is not sufficiently stable and competitive",
        "to justify chain multiplication alone; reopen case-specific DESN/tau0 controls",
        "with post-M0 confirmation."
      )
    }
    data.frame(
      case_id = case_id, scenario_id = cell$scenario_id[[1L]],
      fit_structure = cell$fit_structure[[1L]],
      historical_forecast_truth_mae = historical,
      m0_forecast_truth_mae = m0,
      m0_delta_vs_historical = m0 - historical,
      m0_jackknife_mcse = mcse,
      pairwise_q99_max = max(p$q99_standardized_qhat_delta),
      pairwise_overlap_q01_min = min(p$q01_central90_overlap_fraction),
      within_chain_q99_max = max(w$q99_standardized_qhat_delta),
      within_chain_overlap_q01_min = min(w$q01_central90_overlap_fraction),
      cluster_forecast_mae_min = cluster_min,
      cluster_forecast_mae_max = cluster_max,
      any_cluster_improves = any_cluster_improves,
      all_clusters_improve = all_clusters_improve,
      between_chain_severe = between_chain_severe,
      within_chain_severe = within_chain_severe,
      recovery_classification = classification,
      rationale = rationale,
      pre_m0_screening_authoritative = FALSE,
      exact_m0_required_for_new_winner = TRUE,
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase176_process_case <- function(
  cell, freeze, artifacts
) {
  jobs <- freeze$plan[
    freeze$plan$scenario_id == cell$scenario_id[[1L]] &
      freeze$plan$fit_structure == cell$fit_structure[[1L]],
    , drop = FALSE
  ]
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  fixture <- app_joint_qdesn_scenario_fixture(
    artifacts, cell$scenario_id[[1L]], role = "fit"
  )
  forecast_fixture <- app_joint_exqdesn_phase173_forecast_fixture(
    artifacts, cell$scenario_id[[1L]], fixture
  )
  fits <- app_joint_exqdesn_phase173_load_fits(jobs, fixture)
  control <- freeze$controls[freeze$controls$cell_index == jobs$cell_index[[1L]], , drop = FALSE]
  meta <- app_joint_exqdesn_phase172_meta(jobs[1L, , drop = FALSE], control)
  designs <- list(fit = fixture$Z, forecast = forecast_fixture$Z)
  moments <- lapply(designs, function(Z) {
    setNames(lapply(seq_along(fits), function(chain_id) {
      app_joint_exqdesn_phase170_qhat_moments(
        list(fits[[chain_id]]), Z, fixture$tau
      )
    }), as.character(seq_along(fits)))
  })
  row_context <- list(
    fit = data.frame(
      full_time_index = fixture$row_meta$full_time_index,
      horizon = NA_integer_, stringsAsFactors = FALSE
    ),
    forecast = data.frame(
      full_time_index = forecast_fixture$row_meta$full_time_index,
      horizon = forecast_fixture$row_meta$horizon,
      stringsAsFactors = FALSE
    )
  )
  pair <- lapply(names(moments), function(window) {
    app_joint_exqdesn_phase176_pairwise_qhat(
      moments[[window]], cell$case_id[[1L]], window, row_context[[window]]
    )
  })
  pair_detail <- app_joint_qdesn_bind_rows(lapply(pair, `[[`, "detail"))
  pair_summary <- app_joint_qdesn_bind_rows(lapply(pair, `[[`, "summary"))
  assignments <- app_joint_exqdesn_phase176_cluster_assignments(
    pair_summary, cell$case_id[[1L]]
  )
  drift <- app_joint_exqdesn_phase176_within_chain_drift(
    fits, fixture, forecast_fixture, cell$case_id[[1L]]
  )
  parameters <- app_joint_exqdesn_phase176_parameter_context(
    fits, fixture, cell$case_id[[1L]]
  )
  group <- app_joint_exqdesn_phase176_group_sensitivity(
    fits, assignments, fixture, artifacts, meta,
    as.numeric(cell$historical_forecast_truth_mae[[1L]])
  )
  list(
    pair_detail = pair_detail,
    pair_summary = pair_summary,
    assignments = assignments,
    drift_detail = drift$detail,
    drift_summary = drift$summary,
    parameter_tau = parameters$tau,
    parameter_block = parameters$block,
    group_sensitivity = group
  )
}

app_joint_exqdesn_phase176_run <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  out_dir = NULL,
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  out_dir <- out_dir %||% dirs$phase176
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(out_dir, "phase176")
    if (all(check$status == "pass") &&
        !all(c("recovery_policy", "prior_screen_authority") %in% check$label)) {
      app_joint_exqdesn_phase176_upgrade_artifact(out_dir)
      check <- app_joint_exqdesn_verify_manifest(out_dir, "phase176")
    }
    if (all(check$status == "pass")) {
      return(list(
        out_dir = normalizePath(out_dir),
        classification = app_read_csv(file.path(out_dir, "fallback_classification.csv")),
        reused = TRUE
      ))
    }
  }
  source_verification <- app_joint_exqdesn_phase176_verify_sources(dirs)
  policy <- app_joint_exqdesn_phase176_load_policy()
  prior_authority <- app_joint_exqdesn_phase178_load_authority()
  fallback <- app_joint_exqdesn_phase176_fallback_registry(dirs)
  freeze <- app_joint_exqdesn_phase171_load(dirs$phase171)
  artifacts <- app_joint_qdesn_load_fixture_artifacts(dirs$fixture_dir)
  results <- lapply(seq_len(nrow(fallback)), function(ii) {
    app_joint_exqdesn_phase176_process_case(fallback[ii, , drop = FALSE], freeze, artifacts)
  })
  bind <- function(field) app_joint_qdesn_bind_rows(lapply(results, `[[`, field))
  pair_detail <- bind("pair_detail")
  pair_summary <- bind("pair_summary")
  assignments <- bind("assignments")
  drift_detail <- bind("drift_detail")
  drift_summary <- bind("drift_summary")
  parameter_tau <- bind("parameter_tau")
  parameter_block <- bind("parameter_block")
  group_sensitivity <- bind("group_sensitivity")
  classification <- app_joint_exqdesn_phase176_classify(
    fallback, pair_summary, drift_summary, group_sensitivity, policy
  )
  launch_registry <- classification[
    classification$recovery_classification ==
      "same_spec_additional_chains_eligible",
    , drop = FALSE
  ]
  screen_registry <- classification[
    classification$recovery_classification == "post_m0_spec_screen_required",
    , drop = FALSE
  ]
  localization <- app_joint_exqdesn_phase176_localize(pair_detail, drift_detail)
  cluster_parameter <- merge(
    assignments, parameter_tau,
    by = c("case_id", "chain_id"), all.x = TRUE, sort = FALSE
  )
  cluster_parameter <- merge(
    cluster_parameter, parameter_block,
    by = c("case_id", "chain_id"), all.x = TRUE, sort = FALSE
  )
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase176 post-M0 functional audit", "",
    "This no-sampling audit examines the five exAL cells retained from the historical Phase174 packet.",
    "It reconstructs posterior quantile paths from the verified Phase172 exact-M0 checkpoints.", "",
    "Chain clustering uses forecast qhat paths only; oracle truth and validation scores are excluded from cluster construction.",
    "Truth is used afterwards to describe cluster sensitivity, never to select a favorable cluster.", "",
    "Pre-M0 DESN/tau0 screens are retained only as candidate-region history. Any new specification winner must be ranked and confirmed under exact M0 on protected data.", "",
    sprintf("Same-spec extension eligible: %d", nrow(launch_registry)),
    sprintf("Post-M0 specification screen required: %d", nrow(screen_registry)),
    "No sampler is launched by this audit."
  ), readme, useBytes = TRUE)
  paths <- c(
    source_manifest_verification = write(source_verification, "source_manifest_verification.csv"),
    recovery_policy = write(policy, "recovery_policy.csv"),
    prior_screen_authority = write(prior_authority, "prior_screen_authority.csv"),
    fallback_registry = write(fallback, "fallback_registry.csv"),
    chain_qhat_distance = write(pair_summary, "chain_qhat_distance.csv"),
    chain_functional_cluster = write(assignments, "chain_functional_cluster.csv"),
    within_chain_functional_drift = write(drift_summary, "within_chain_functional_drift.csv"),
    instability_localization = write(localization, "instability_localization.csv"),
    chain_parameter_tau_context = write(parameter_tau, "chain_parameter_tau_context.csv"),
    chain_parameter_block_context = write(parameter_block, "chain_parameter_block_context.csv"),
    cluster_parameter_context = write(cluster_parameter, "cluster_parameter_context.csv"),
    cluster_weight_sensitivity = write(group_sensitivity, "cluster_weight_sensitivity.csv"),
    fallback_classification = write(classification, "fallback_classification.csv"),
    phase177_launch_registry = write(launch_registry, "phase177_launch_registry.csv"),
    phase178_screen_registry = write(screen_registry, "phase178_screen_registry.csv"),
    run_config = write(data.frame(
      phase_id = "phase176_post_m0_functional_audit",
      cache_root = cache_root, output_dir = final_dir,
      source_phase172 = dirs$phase172, source_phase173 = dirs$phase173,
      source_phase173b = dirs$phase173b, source_phase174 = dirs$phase174,
      held_cells = nrow(fallback), sampler_launched = FALSE,
      cluster_truth_usage = FALSE,
      pre_m0_screening_authoritative = FALSE,
      exact_m0_required_for_new_winner = TRUE,
      stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) {
      stop("Could not quarantine an existing Phase176 output.", call. = FALSE)
    }
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase176 output.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase176")
  if (any(check$status != "pass")) stop("Phase176 published manifest failed.", call. = FALSE)
  list(out_dir = final_dir, classification = classification, reused = FALSE)
}

app_joint_exqdesn_phase176_upgrade_artifact <- function(out_dir) {
  out_dir <- normalizePath(out_dir, mustWork = TRUE)
  check <- app_joint_exqdesn_verify_manifest(out_dir, "phase176_preupgrade")
  if (any(check$status != "pass")) {
    stop("Phase176 cannot be upgraded because its published hashes fail.", call. = FALSE)
  }
  classification <- app_read_csv(file.path(out_dir, "fallback_classification.csv"))
  if (nrow(classification) != 5L ||
      !setequal(classification$case_id, app_joint_exqdesn_phase176_required_case_ids()) ||
      any(classification$recovery_classification != "post_m0_spec_screen_required")) {
    stop("Phase176 post-publication upgrade found an incomplete classification.", call. = FALSE)
  }
  policy_path <- app_joint_qvp_write_csv(
    app_joint_exqdesn_phase176_load_policy(), file.path(out_dir, "recovery_policy.csv")
  )
  authority_path <- app_joint_qvp_write_csv(
    app_joint_exqdesn_phase178_load_authority(),
    file.path(out_dir, "prior_screen_authority.csv")
  )
  audit_path <- app_joint_qvp_write_csv(data.frame(
    audit_id = "phase176_post_publication_integrity_upgrade",
    original_manifest_rows = nrow(check),
    original_hashes_passed = sum(check$status == "pass"),
    complete_classification_rows = nrow(classification),
    sampling_repeated = FALSE, scientific_outputs_changed = FALSE,
    added_policy_metadata_only = TRUE, rerun_required = FALSE,
    rationale = paste(
      "The long calculation published a complete hash-valid artifact before a",
      "post-publication wrapper exit; policy metadata was added without recomputation."
    ), stringsAsFactors = FALSE
  ), file.path(out_dir, "post_publication_integrity_audit.csv"))
  old_manifest <- app_read_csv(file.path(out_dir, "artifact_manifest.csv"))
  old_paths <- file.path(out_dir, old_manifest$relative_path)
  names(old_paths) <- old_manifest$label
  paths <- c(
    old_paths, recovery_policy = policy_path,
    prior_screen_authority = authority_path,
    post_publication_integrity_audit = audit_path
  )
  paths <- paths[!duplicated(names(paths), fromLast = TRUE)]
  app_joint_exqdesn_write_manifest(paths, out_dir)
  upgraded <- app_joint_exqdesn_verify_manifest(out_dir, "phase176_upgraded")
  if (any(upgraded$status != "pass")) stop("Phase176 upgraded manifest failed.", call. = FALSE)
  invisible(upgraded)
}

app_joint_exqdesn_phase177_seed_plan <- function(
  cells, source_freeze, out_dir,
  n_chains = 16L, n_iter = 48000L, burn = 8000L, thin = 8L,
  seed_base = 176177000L
) {
  n_chains <- as.integer(n_chains)
  n_iter <- as.integer(n_iter)
  burn <- as.integer(burn)
  thin <- as.integer(thin)
  if (n_chains != 16L || n_iter != 48000L || burn != 8000L || thin != 8L ||
      (n_iter - burn) / thin != 5000L) {
    stop("Phase177 requires the frozen 16-chain 48k/8k/thin-8 budget.", call. = FALSE)
  }
  rows <- list()
  component_rows <- list()
  starts <- list()
  worker_id <- component_id <- 0L
  tau_grid <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
  for (ii in seq_len(nrow(cells))) {
    cell <- cells[ii, , drop = FALSE]
    source_job <- source_freeze$plan[
      source_freeze$plan$scenario_id == cell$scenario_id[[1L]] &
        source_freeze$plan$fit_structure == cell$fit_structure[[1L]],
      , drop = FALSE
    ][1L, , drop = FALSE]
    case_id <- source_job$mcmc_case_id[[1L]]
    init_rows <- source_freeze$init[source_freeze$init$mcmc_case_id == case_id, , drop = FALSE]
    sigma <- init_rows$value[init_rows$parameter_block == "sigma"]
    gamma <- init_rows$value[init_rows$parameter_block == "gamma"]
    cell_starts <- app_joint_exqdesn_phase156_chain_starts(
      list(sigma_mean = sigma, gamma_mean = gamma), tau_grid, case_id, n_chains
    )
    names(cell_starts)[names(cell_starts) == "scenario_id"] <- "mcmc_case_id"
    cell_starts$scenario_id <- cell$scenario_id[[1L]]
    cell_starts$base_scenario_id <- cell$scenario_id[[1L]]
    cell_starts$fit_structure <- cell$fit_structure[[1L]]
    starts[[ii]] <- cell_starts
    cell_seed <- as.integer(seed_base + ii * 1000000L)
    for (chain_id in seq_len(n_chains)) {
      worker_id <- worker_id + 1L
      chain_seed <- as.integer(cell_seed + chain_id * 10000L)
      wave_id <- as.integer(ceiling(chain_id / 4))
      worker_dir <- file.path(
        out_dir, "candidates", case_id, sprintf("chain_%02d", chain_id)
      )
      row <- source_job
      row$worker_id <- worker_id
      row$wave_id <- wave_id
      row$chain_id <- chain_id
      row$cell_seed <- cell_seed
      row$chain_seed <- chain_seed
      row$seed_role <- "phase177_new_seed_same_spec_exact_M0_chain"
      row$start_profile_id <- sprintf("%s__phase177_chain_%02d", case_id, chain_id)
      row$n_iter <- n_iter
      row$burn <- burn
      row$thin <- thin
      row$n_keep <- as.integer((n_iter - burn) / thin)
      row$worker_output_dir <- worker_dir
      row$source_phase171_chain_ids <- "1;2;3;4;5;6;7;8"
      row$new_packet_is_primary <- TRUE
      row$old_new_pooling_policy <- "external_replication_only_no_automatic_pooling"
      rows[[worker_id]] <- row
      if (cell$fit_structure[[1L]] == "joint") {
        component_id <- component_id + 1L
        component_rows[[component_id]] <- data.frame(
          component_id = component_id, worker_id = worker_id, wave_id = wave_id,
          cell_index = source_job$cell_index[[1L]], scenario_id = cell$scenario_id[[1L]],
          fit_structure = "joint", chain_id = chain_id,
          quantile_index = NA_integer_, tau = NA_real_, component_seed = chain_seed,
          seed_role = "phase177_joint_multiquantile_component", stringsAsFactors = FALSE
        )
      } else {
        for (k in seq_along(tau_grid)) {
          component_id <- component_id + 1L
          component_rows[[component_id]] <- data.frame(
            component_id = component_id, worker_id = worker_id, wave_id = wave_id,
            cell_index = source_job$cell_index[[1L]], scenario_id = cell$scenario_id[[1L]],
            fit_structure = "independent", chain_id = chain_id,
            quantile_index = k, tau = tau_grid[[k]],
            component_seed = as.integer(chain_seed + k * source_job$tau_seed_stride[[1L]]),
            seed_role = "phase177_independent_quantile_component", stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  plan <- app_joint_qdesn_bind_rows(rows)
  components <- app_joint_qdesn_bind_rows(component_rows)
  starts <- app_joint_qdesn_bind_rows(starts)
  old_seeds <- unique(c(
    as.integer(source_freeze$plan$chain_seed),
    as.integer(source_freeze$components$component_seed)
  ))
  new_seeds <- unique(c(as.integer(plan$chain_seed), as.integer(components$component_seed)))
  if (nrow(plan) != nrow(cells) * n_chains || anyDuplicated(plan$chain_seed) ||
      anyDuplicated(components$component_seed) || length(intersect(old_seeds, new_seeds)) ||
      any(new_seeds >= .Machine$integer.max)) {
    stop("Phase177 seed hierarchy collides or is malformed.", call. = FALSE)
  }
  list(plan = plan, components = components, starts = starts)
}

app_joint_exqdesn_phase177_prepare <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  phase176_dir = NULL,
  out_dir = NULL,
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  phase176_dir <- phase176_dir %||% dirs$phase176
  out_dir <- out_dir %||% dirs$phase177_freeze
  source_check <- app_joint_exqdesn_verify_manifest(phase176_dir, "phase176")
  if (any(source_check$status != "pass")) stop("Phase177 Phase176 source failed.", call. = FALSE)
  cells <- app_read_csv(file.path(phase176_dir, "phase177_launch_registry.csv"))
  if (!nrow(cells)) {
    stop("Phase176 authorized no same-spec Phase177 cells.", call. = FALSE)
  }
  if (any(cells$recovery_classification != "same_spec_additional_chains_eligible")) {
    stop("Phase177 registry contains an unauthorized cell.", call. = FALSE)
  }
  source <- app_joint_exqdesn_phase171_load(dirs$phase171)
  policy <- app_joint_exqdesn_phase176_load_policy()
  seeds <- app_joint_exqdesn_phase177_seed_plan(
    cells, source, dirs$phase177,
    n_chains = policy$phase177_n_chains[[1L]],
    n_iter = policy$phase177_n_iter[[1L]],
    burn = policy$phase177_burn[[1L]],
    thin = policy$phase177_thin[[1L]]
  )
  case_keys <- paste(cells$scenario_id, cells$fit_structure, sep = "__")
  controls <- source$controls[source$controls$mcmc_case_id %in% case_keys, , drop = FALSE]
  init <- source$init[source$init$mcmc_case_id %in% case_keys, , drop = FALSE]
  if (nrow(controls) != nrow(cells) ||
      !setequal(controls$mcmc_case_id, case_keys) || !nrow(init)) {
    stop("Phase177 could not preserve exact Phase171 controls and initialization.", call. = FALSE)
  }
  repo_head <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD"))
  seeds$plan$code_commit <- repo_head
  seeds$plan$fixture_manifest_sha256 <- app_sha256_file(
    file.path(dirs$fixture_dir, "artifact_manifest.csv")
  )
  readiness <- data.frame(
    phase_id = "phase177_same_spec_exact_M0_confirmation",
    gate_status = "pass", authorized_cells = nrow(cells),
    planned_workers = nrow(seeds$plan), planned_physical_components = nrow(seeds$components),
    n_chains_per_cell = 16L, n_iter = 48000L, burn = 8000L, thin = 8L,
    retained_draws_per_chain = 5000L,
    exact_method_id = "M0_v_collapsed_support_logit",
    new_packet_is_primary = TRUE, old_packet_role = "external_replication",
    automatic_old_new_pooling = FALSE, article_files_modified = FALSE,
    stringsAsFactors = FALSE
  )
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(final_dir, "phase177_freeze")
    if (all(check$status == "pass")) return(list(out_dir = final_dir, plan = app_read_csv(file.path(final_dir, "chain_plan.csv"))))
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase177 same-spec exact-M0 freeze", "",
    sprintf("Authorized cells: %d", nrow(cells)),
    "Each cell uses 16 new chains, 48,000 iterations, 8,000 burn-in iterations, and thinning by eight.",
    "The current exact article specification is unchanged. Seeds do not overlap Phase171/172.",
    "The new packet is primary; the old eight-chain packet is an external replication and is not automatically pooled."
  ), readme, useBytes = TRUE)
  paths <- c(
    phase176_manifest_verification = write(source_check, "phase176_manifest_verification.csv"),
    recovery_policy = write(policy, "recovery_policy.csv"),
    authorized_cells = write(cells, "authorized_cells.csv"),
    model_control_freeze = write(controls, "model_control_freeze.csv"),
    vb_initialization = write(init, "vb_initialization.csv"),
    chain_start_values = write(seeds$starts, "chain_start_values.csv"),
    chain_plan = write(seeds$plan, "chain_plan.csv"),
    component_seed_plan = write(seeds$components, "component_seed_plan.csv"),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    run_config = write(data.frame(
      phase_id = readiness$phase_id, fixture_dir = dirs$fixture_dir,
      source_phase171 = dirs$phase171, source_phase176 = phase176_dir,
      output_dir = dirs$phase177, code_commit = repo_head,
      stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase177 freeze.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase177 freeze.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase177_freeze")
  if (any(check$status != "pass")) stop("Phase177 freeze manifest failed.", call. = FALSE)
  list(out_dir = final_dir, plan = seeds$plan)
}

app_joint_exqdesn_phase177_health <- function(
  freeze_dir = app_joint_exqdesn_phase176_dirs()$phase177_freeze,
  orchestration_dir = app_joint_exqdesn_phase176_dirs()$phase177_orchestration
) {
  freeze <- app_joint_exqdesn_phase171_load(freeze_dir)
  complete <- vapply(
    freeze$plan$worker_output_dir,
    app_joint_exqdesn_phase172_worker_complete,
    logical(1L)
  )
  exit_paths <- file.path(
    orchestration_dir, "exits", sprintf("worker_%03d.exit", freeze$plan$worker_id)
  )
  failed <- vapply(exit_paths, function(path) {
    file.exists(path) && suppressWarnings(as.integer(readLines(path, warn = FALSE)[1L])) != 0L
  }, logical(1L))
  state <- ifelse(complete, "complete", ifelse(failed, "failed", "remaining"))
  plan <- freeze$plan
  plan$state <- state
  by_cell <- app_joint_qdesn_bind_rows(lapply(split(plan, plan$mcmc_case_id), function(x) {
    data.frame(
      mcmc_case_id = x$mcmc_case_id[[1L]], planned = nrow(x),
      complete = sum(x$state == "complete"), failed = sum(x$state == "failed"),
      remaining = sum(x$state == "remaining"), stringsAsFactors = FALSE
    )
  }))
  list(
    summary = data.frame(
      stage = "Phase177 same-spec exact-M0 confirmation", planned = nrow(plan),
      complete = sum(complete), failed = sum(failed & !complete),
      remaining = sum(!complete & !failed), percent_complete = 100 * mean(complete),
      stringsAsFactors = FALSE
    ),
    by_cell = by_cell, plan = plan
  )
}

app_joint_exqdesn_phase177_load_fits <- function(jobs, fixture) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  if (nrow(jobs) != 16L || !identical(as.integer(jobs$chain_id), seq_len(16L))) {
    stop("Phase177 requires exactly the frozen new chains 1-16.", call. = FALSE)
  }
  lapply(seq_len(nrow(jobs)), function(ii) {
    app_joint_exqdesn_phase157_read_fit(
      app_joint_exqdesn_phase172_checkpoint_dir(jobs$worker_output_dir[[ii]]),
      fixture$tau, jobs$chain_seed[[ii]], jobs$chain_id[[ii]]
    )
  })
}

app_joint_exqdesn_phase177_partition_stability <- function(
  fits, fixture, forecast_fixture, meta
) {
  if (length(fits) != 16L) {
    stop("Phase177 partition stability requires 16 chains.", call. = FALSE)
  }
  partitions <- list(
    first8_last8 = list(a = 1:8, b = 9:16),
    odd_even = list(a = seq(1L, 15L, 2L), b = seq(2L, 16L, 2L))
  )
  rows <- lapply(names(partitions), function(id) {
    groups <- partitions[[id]]
    list(
      fit = app_joint_exqdesn_phase173_compare_qhat_groups(
        fits[groups$a], fits[groups$b], fixture$Z, fixture$tau,
        meta, id, "fit"
      ),
      forecast = app_joint_exqdesn_phase173_compare_qhat_groups(
        fits[groups$a], fits[groups$b], forecast_fixture$Z, fixture$tau,
        meta, id, "forecast"
      )
    )
  })
  flattened <- unlist(rows, recursive = FALSE)
  list(
    detail = app_joint_qdesn_bind_rows(lapply(flattened, `[[`, "detail")),
    summary = app_joint_qdesn_bind_rows(lapply(flattened, `[[`, "summary"))
  )
}

app_joint_exqdesn_phase177_process_cell <- function(jobs, freeze, artifacts) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  control <- freeze$controls[
    freeze$controls$cell_index == jobs$cell_index[[1L]], , drop = FALSE
  ]
  if (nrow(control) != 1L) {
    stop("Phase177 could not resolve one frozen control row.", call. = FALSE)
  }
  fixture <- app_joint_qdesn_scenario_fixture(
    artifacts, jobs$scenario_id[[1L]], role = "fit"
  )
  forecast_fixture <- app_joint_exqdesn_phase173_forecast_fixture(
    artifacts, jobs$scenario_id[[1L]], fixture
  )
  fits <- app_joint_exqdesn_phase177_load_fits(jobs, fixture)
  meta <- app_joint_exqdesn_phase172_meta(jobs[1L, , drop = FALSE], control)
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
    fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
  )
  scored <- app_joint_exqdesn_phase173_score_fit(
    pooled, fixture, artifacts, meta, "phase177_new_packet"
  )
  diagnostics <- app_joint_exqdesn_phase173_parameter_diagnostics(
    fits, fixture, meta
  )
  partitions <- app_joint_exqdesn_phase177_partition_stability(
    fits, fixture, forecast_fixture, meta
  )
  full_metrics <- as.list(scored$metrics[1L, , drop = FALSE])
  loo <- app_joint_exqdesn_phase173_leave_one_out(
    fits, fixture, artifacts, meta, full_metrics
  )
  jackknife <- app_joint_exqdesn_phase173_jackknife(loo, meta)
  sensitivity <- app_joint_qdesn_bind_rows(lapply(
    c("mean", "median", "trimmed_mean"), function(type) {
      fit <- app_joint_exqdesn_phase173_summary_fit(fits, fixture, type)
      result <- app_joint_exqdesn_phase173_score_fit(
        fit, fixture, artifacts, meta, paste0("phase177_", type)
      )
      cbind(meta, data.frame(summary_type = type), result$metrics)
    }
  ))
  chain_distance <- app_joint_qvp_chain_to_pooled_summary(
    fits, pooled, fixture$Z, meta$case_id[[1L]], "phase177_new_packet",
    fixture$scenario_id, length(fixture$y), ncol(fixture$Z),
    length(fixture$tau)
  )
  for (field in setdiff(names(meta), names(chain_distance))) {
    chain_distance[[field]] <- meta[[field]][[1L]]
  }
  chain_summary <- app_joint_qdesn_bind_rows(lapply(
    jobs$worker_output_dir,
    function(dir) app_read_csv(file.path(dir, "chain_summary.csv"))
  ))
  summary <- cbind(meta, data.frame(
    source_model_id = if (meta$fit_structure[[1L]] == "joint") {
      "joint_exqdesn_rhs_vb"
    } else {
      "exqdesn_rhs_independent_vb"
    },
    mcmc_n_chains = length(fits),
    mcmc_n_iter = jobs$n_iter[[1L]],
    mcmc_burn = jobs$burn[[1L]],
    mcmc_thin = jobs$thin[[1L]],
    mcmc_n_keep_total = nrow(pooled$beta_draws),
    mcmc_init_source = pooled$init_source %||% "provided",
    all_chain_init_source_provided = all(chain_summary$init_source == "provided"),
    mcmc_draws_all_finite = all(chain_summary$draws_all_finite),
    mcmc_fit_truth_mae = scored$metrics$fit_truth_mae,
    mcmc_forecast_truth_mae = scored$metrics$forecast_truth_mae,
    mcmc_fit_check_loss_mean = scored$metrics$fit_check_loss_mean,
    mcmc_forecast_check_loss_mean = scored$metrics$forecast_check_loss_mean,
    mcmc_fit_crps_grid_mean = scored$metrics$fit_crps_grid_mean,
    mcmc_forecast_crps_grid_mean = scored$metrics$forecast_crps_grid_mean,
    mcmc_fit_raw_crossing_pairs = sum(scored$fit$raw_crossing$n_crossing_pairs),
    mcmc_forecast_raw_crossing_pairs = sum(scored$forecast$raw_crossing$n_crossing_pairs),
    mcmc_fit_contract_crossing_pairs = sum(scored$fit$contract_crossing$n_crossing_pairs),
    mcmc_forecast_contract_crossing_pairs = sum(scored$forecast$contract_crossing$n_crossing_pairs),
    max_rank_rhat = max(diagnostics$rank_rhat, na.rm = TRUE),
    max_folded_rhat = max(diagnostics$folded_rhat, na.rm = TRUE),
    min_bulk_ess = min(diagnostics$bulk_ess, na.rm = TRUE),
    min_tail_ess = min(diagnostics$tail_ess, na.rm = TRUE),
    runtime_seconds_total = sum(chain_summary$elapsed_seconds),
    packet_role = "new_16_chain_primary_packet",
    old_phase172_packet_role = "external_replication_not_pooled",
    stringsAsFactors = FALSE
  ))
  list(
    summary = summary, diagnostics = diagnostics,
    partition_detail = partitions$detail,
    partition_summary = partitions$summary,
    loo = loo, jackknife = jackknife, sensitivity = sensitivity,
    fit_raw = scored$fit$raw, fit = scored$fit$scored,
    fit_adjustment = scored$fit$adjustment,
    forecast_raw = scored$forecast$raw, forecast = scored$forecast$scored,
    forecast_adjustment = scored$forecast$adjustment,
    crossing = app_joint_qdesn_bind_rows(list(
      scored$fit$contract_crossing, scored$forecast$contract_crossing
    )),
    raw_crossing = app_joint_qdesn_bind_rows(list(
      scored$fit$raw_crossing, scored$forecast$raw_crossing
    )),
    chain_distance = chain_distance, chain_summary = chain_summary
  )
}

app_joint_exqdesn_phase177_reference_rows <- function(summary, dirs) {
  historical <- app_read_csv(file.path(dirs$phase174, "final_mcmc_case_summary.csv"))
  keys <- c("scenario_id", "source_model_id")
  wanted <- summary[, keys, drop = FALSE]
  out <- merge(
    wanted, historical,
    by = keys, all.x = TRUE, sort = FALSE,
    suffixes = c("", "_historical")
  )
  if (nrow(out) != nrow(summary) || any(!is.finite(out$mcmc_forecast_truth_mae))) {
    stop("Phase177 could not resolve the frozen Phase174 reference rows.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase177_assess <- function(
  summary, partition_summary, jackknife, sensitivity, reference,
  recovery_policy = app_joint_exqdesn_phase176_load_policy(),
  functional_policy = app_joint_exqdesn_phase173b_load_policy()
) {
  rows <- lapply(seq_len(nrow(summary)), function(ii) {
    cell <- summary[ii, , drop = FALSE]
    case_id <- cell$case_id[[1L]]
    old <- reference[
      reference$scenario_id == cell$scenario_id[[1L]] &
        reference$source_model_id == cell$source_model_id[[1L]],
      , drop = FALSE
    ]
    p <- partition_summary[partition_summary$case_id == case_id, , drop = FALSE]
    j <- jackknife[
      jackknife$case_id == case_id &
        jackknife$metric == "forecast_truth_mae", , drop = FALSE
    ]
    s <- sensitivity[sensitivity$case_id == case_id, , drop = FALSE]
    if (nrow(old) != 1L || nrow(j) != 1L || nrow(s) != 3L || nrow(p) != 4L) {
      stop(sprintf("Phase177 audit inputs are incomplete for '%s'.", case_id), call. = FALSE)
    }
    old_forecast <- as.numeric(old$mcmc_forecast_truth_mae[[1L]])
    new_forecast <- as.numeric(cell$mcmc_forecast_truth_mae[[1L]])
    mcse <- as.numeric(j$jackknife_mcse[[1L]])
    improvement_floor <- max(
      as.numeric(functional_policy$mcse_multiplier[[1L]]) * mcse,
      as.numeric(functional_policy$numerical_tolerance[[1L]])
    )
    summary_range <- diff(range(s$forecast_truth_mae))
    summary_ceiling <- max(
      as.numeric(functional_policy$summary_abs_range_floor[[1L]]),
      as.numeric(functional_policy$summary_relative_range_ceiling[[1L]]) *
        old_forecast
    )
    summary_direction_consistent <- all(s$forecast_truth_mae < old_forecast)
    partition_q99 <- max(p$q99_standardized_qhat_delta)
    partition_overlap <- min(p$q01_central90_overlap_fraction)
    qhat_status <- if (
      partition_q99 <= as.numeric(functional_policy$qhat_pass_q99_max[[1L]]) &&
        partition_overlap >= as.numeric(functional_policy$qhat_pass_overlap_min[[1L]])
    ) {
      "pass"
    } else if (
      partition_q99 <= as.numeric(functional_policy$qhat_review_q99_max[[1L]]) &&
        partition_overlap >= as.numeric(functional_policy$qhat_review_overlap_min[[1L]])
    ) {
      "review"
    } else {
      "hold"
    }
    finite_metrics <- all(is.finite(unlist(cell[c(
      "mcmc_fit_truth_mae", "mcmc_forecast_truth_mae",
      "mcmc_fit_check_loss_mean", "mcmc_forecast_check_loss_mean",
      "mcmc_fit_crps_grid_mean", "mcmc_forecast_crps_grid_mean"
    )], use.names = FALSE)))
    hard_pass <- isTRUE(cell$mcmc_draws_all_finite[[1L]]) && finite_metrics &&
      isTRUE(cell$all_chain_init_source_provided[[1L]]) &&
      cell$mcmc_fit_contract_crossing_pairs[[1L]] == 0L &&
      cell$mcmc_forecast_contract_crossing_pairs[[1L]] == 0L
    check_ratio <- cell$mcmc_forecast_check_loss_mean[[1L]] /
      old$mcmc_forecast_check_loss_mean[[1L]]
    crps_ratio <- cell$mcmc_forecast_crps_grid_mean[[1L]] /
      old$mcmc_forecast_crps_grid[[1L]]
    fit_ratio <- cell$mcmc_fit_truth_mae[[1L]] / old$mcmc_fit_truth_mae[[1L]]
    metric_noninferior <- check_ratio <=
      1 + as.numeric(recovery_policy$phase177_check_crps_relative_ceiling[[1L]]) &&
      crps_ratio <=
        1 + as.numeric(recovery_policy$phase177_check_crps_relative_ceiling[[1L]]) &&
      fit_ratio <=
        1 + as.numeric(recovery_policy$phase177_fit_mae_relative_ceiling[[1L]])
    material_forecast_gain <- old_forecast - new_forecast > improvement_floor
    summary_stable <- summary_range <= summary_ceiling &&
      (!isTRUE(functional_policy$require_summary_direction_consistency[[1L]]) ||
        summary_direction_consistent)
    functional_eligible <- qhat_status %in% c("pass", "review") && summary_stable
    action <- if (!hard_pass) {
      "hard_failure"
    } else if (material_forecast_gain && metric_noninferior && functional_eligible) {
      "promote_phase177_same_spec_m0"
    } else {
      "route_to_phase178_case_specific_screen"
    }
    data.frame(
      case_id = case_id, scenario_id = cell$scenario_id[[1L]],
      fit_structure = cell$fit_structure[[1L]],
      source_model_id = cell$source_model_id[[1L]],
      historical_forecast_truth_mae = old_forecast,
      phase177_forecast_truth_mae = new_forecast,
      forecast_mae_gain = old_forecast - new_forecast,
      forecast_mae_jackknife_mcse = mcse,
      required_gain = improvement_floor,
      check_loss_ratio = check_ratio, crps_ratio = crps_ratio,
      fit_mae_ratio = fit_ratio, metric_noninferior = metric_noninferior,
      qhat_partition_status = qhat_status,
      qhat_partition_q99_max = partition_q99,
      qhat_partition_overlap_min = partition_overlap,
      posterior_summary_forecast_mae_range = summary_range,
      posterior_summary_range_ceiling = summary_ceiling,
      posterior_summary_direction_consistent = summary_direction_consistent,
      hard_gate_status = if (hard_pass) "pass" else "fail",
      scalar_mixing_status = if (
        cell$max_rank_rhat[[1L]] <= 1.05 && cell$max_folded_rhat[[1L]] <= 1.05 &&
          cell$min_bulk_ess[[1L]] >= 400 && cell$min_tail_ess[[1L]] >= 200
      ) "pass" else "review",
      action = action,
      status_reason = if (action == "promote_phase177_same_spec_m0") {
        "new-seed exact-M0 packet has a resolved metric gain and stable quantile functional"
      } else if (action == "hard_failure") {
        "implementation, finiteness, initialization, or contract gate failed"
      } else if (!material_forecast_gain) {
        "forecast-MAE gain is absent or unresolved at chain-jackknife precision"
      } else if (!metric_noninferior) {
        "supporting score or fit noninferiority gate failed"
      } else {
        "posterior quantile functional remains allocation or summary sensitive"
      },
      exact_m0_used = TRUE, favorable_chain_subset_selected = FALSE,
      pre_m0_spec_ranking_authoritative = FALSE,
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase177_finalize <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  freeze_dir = NULL, out_dir = NULL, force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  freeze_dir <- freeze_dir %||% dirs$phase177_freeze
  out_dir <- out_dir %||% dirs$phase177_audit
  freeze <- app_joint_exqdesn_phase171_load(freeze_dir)
  health <- app_joint_exqdesn_phase177_health(
    freeze_dir, dirs$phase177_orchestration
  )
  if (health$summary$failed[[1L]] > 0L || health$summary$remaining[[1L]] > 0L) {
    stop("Phase177 cannot finalize before every frozen worker verifies.", call. = FALSE)
  }
  worker_verification <- app_joint_qdesn_bind_rows(lapply(
    seq_len(nrow(freeze$plan)), function(ii) {
      x <- app_joint_exqdesn_verify_manifest(
        freeze$plan$worker_output_dir[[ii]],
        sprintf("phase177_worker_%03d", freeze$plan$worker_id[[ii]])
      )
      x$worker_id <- freeze$plan$worker_id[[ii]]
      x
    }
  ))
  if (any(worker_verification$status != "pass")) {
    stop("Phase177 worker-manifest verification failed.", call. = FALSE)
  }
  artifacts <- app_joint_qdesn_load_fixture_artifacts(freeze$config$fixture_dir[[1L]])
  cells <- split(freeze$plan, freeze$plan$mcmc_case_id)
  results <- lapply(
    cells, app_joint_exqdesn_phase177_process_cell,
    freeze = freeze, artifacts = artifacts
  )
  bind <- function(name) app_joint_qdesn_bind_rows(lapply(results, `[[`, name))
  summary <- bind("summary")
  diagnostics <- bind("diagnostics")
  partition_detail <- bind("partition_detail")
  partition_summary <- bind("partition_summary")
  loo <- bind("loo")
  jackknife <- bind("jackknife")
  sensitivity <- bind("sensitivity")
  reference <- app_joint_exqdesn_phase177_reference_rows(summary, dirs)
  decision <- app_joint_exqdesn_phase177_assess(
    summary, partition_summary, jackknife, sensitivity, reference
  )
  fit_raw <- bind("fit_raw"); fit <- bind("fit")
  forecast_raw <- bind("forecast_raw"); forecast <- bind("forecast")
  fit_adjustment <- bind("fit_adjustment")
  forecast_adjustment <- bind("forecast_adjustment")
  crossing <- bind("crossing"); raw_crossing <- bind("raw_crossing")
  chain_distance <- bind("chain_distance"); chains <- bind("chain_summary")
  final <- data.frame(
    phase_id = "phase177_same_spec_exact_M0_audit",
    gate_status = if (any(decision$action == "hard_failure")) "fail" else
      if (any(decision$action == "route_to_phase178_case_specific_screen")) "review" else "pass",
    completed_cells = nrow(summary),
    promoted_cells = sum(decision$action == "promote_phase177_same_spec_m0"),
    phase178_cells = sum(decision$action == "route_to_phase178_case_specific_screen"),
    hard_failures = sum(decision$action == "hard_failure"),
    exact_m0 = TRUE, old_new_draws_automatically_pooled = FALSE,
    article_assets_modified = FALSE,
    recommendation = "freeze_promotions_and_route_unresolved_cells_to_phase178",
    stringsAsFactors = FALSE
  )
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(final_dir, "phase177_audit")
    if (all(check$status == "pass")) return(list(out_dir = final_dir, final = app_read_csv(file.path(final_dir, "phase177_assessment.csv"))))
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase177 same-spec exact-M0 audit", "",
    sprintf("- Gate: `%s`", final$gate_status[[1L]]),
    sprintf("- Completed / promoted / Phase178 / hard fail: %d / %d / %d / %d",
      final$completed_cells, final$promoted_cells, final$phase178_cells,
      final$hard_failures),
    "- All 16 new chains form the primary packet; no favorable subset was selected.",
    "- The earlier eight-chain packet remains an external replication.",
    "- Scalar mixing may remain review-level when the posterior quantile functional is stable."
  ), readme, useBytes = TRUE)
  paths <- c(
    freeze_manifest_verification = write(freeze$verification, "freeze_manifest_verification.csv"),
    worker_manifest_verification = write(worker_verification, "worker_manifest_verification.csv"),
    health_summary = write(health$summary, "health_summary.csv"),
    cell_health_summary = write(summary, "cell_health_summary.csv"),
    parameter_diagnostics = write(diagnostics, "parameter_diagnostics.csv"),
    qhat_partition_detail = write(partition_detail, "qhat_partition_detail.csv"),
    qhat_partition_summary = write(partition_summary, "qhat_partition_summary.csv"),
    chain_leave_one_out = write(loo, "chain_leave_one_out.csv"),
    metric_jackknife_mcse = write(jackknife, "metric_jackknife_mcse.csv"),
    posterior_summary_sensitivity = write(sensitivity, "posterior_summary_sensitivity.csv"),
    historical_reference = write(reference, "historical_reference.csv"),
    promotion_decision = write(decision, "promotion_decision.csv"),
    phase177_assessment = write(final, "phase177_assessment.csv"),
    fit_quantiles_raw = write(fit_raw, "fit_quantiles_raw.csv"),
    fit_quantiles = write(fit, "fit_quantiles.csv"),
    forecast_quantiles_raw = write(forecast_raw, "forecast_quantiles_raw.csv"),
    forecast_quantiles = write(forecast, "forecast_quantiles.csv"),
    fit_monotone_adjustment = write(fit_adjustment, "fit_monotone_adjustment.csv"),
    forecast_monotone_adjustment = write(forecast_adjustment, "forecast_monotone_adjustment.csv"),
    raw_crossing_summary = write(raw_crossing, "raw_crossing_summary.csv"),
    contract_crossing_summary = write(crossing, "contract_crossing_summary.csv"),
    chain_to_pooled_distance = write(chain_distance, "chain_to_pooled_distance.csv"),
    runtime_summary = write(chains, "runtime_summary.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase177 audit.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase177 audit.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase177_audit")
  if (any(check$status != "pass")) stop("Phase177 audit manifest failed.", call. = FALSE)
  list(out_dir = final_dir, final = final, decision = decision)
}

app_joint_exqdesn_phase178_neighborhood_path <- function() {
  app_path("application/config/joint_exqdesn_phase178_case_specific_neighborhood_v1.csv")
}

app_joint_exqdesn_phase178_compute_policy_path <- function() {
  app_path("application/config/joint_exqdesn_phase178_post_m0_compute_policy_v1.csv")
}

app_joint_exqdesn_phase178_load_neighborhood <- function(
  path = app_joint_exqdesn_phase178_neighborhood_path()
) {
  x <- app_read_csv(path)
  app_check_required_columns(x, c(
    "schema_version", "case_id", "tau0_low_multiplier",
    "tau0_high_multiplier", "include_tail_relaxation",
    "alternate_design_role", "alternate_design_reason", "selection_scope",
    "pre_m0_rank_authority", "exact_m0_rank_required"
  ), "Phase178 case-specific neighborhood")
  if (nrow(x) != 5L || anyDuplicated(x$case_id) ||
      !setequal(x$case_id, app_joint_exqdesn_phase176_required_case_ids()) ||
      any(x$selection_scope != "case_specific_scenario_readout") ||
      any(app_as_bool_vec(x$pre_m0_rank_authority)) ||
      any(!app_as_bool_vec(x$exact_m0_rank_required))) {
    stop("Phase178 case-specific neighborhood violates its scope.", call. = FALSE)
  }
  x
}

app_joint_exqdesn_phase178_load_compute_policy <- function(
  path = app_joint_exqdesn_phase178_compute_policy_path()
) {
  x <- app_read_csv(path)
  required <- c(
    "schema_version", "policy_id", "calibration_replicates",
    "ranking_replicates", "confirmation_replicates", "dgp_seed_base",
    "vb_method_id", "vb_max_iter", "vb_tol", "rhs_vb_inner",
    "m0_ranking_chains", "m0_ranking_n_iter", "m0_ranking_burn",
    "m0_ranking_thin", "m0_confirmation_chains",
    "m0_confirmation_n_iter", "m0_confirmation_burn",
    "m0_confirmation_thin", "max_candidates_per_cell",
    "max_m0_survivors_per_cell", "m0_check_loss_ratio_ceiling",
    "m0_crps_ratio_ceiling", "m0_fit_mae_ratio_ceiling",
    "m0_confirmation_win_fraction_floor", "m0_functional_q99_ceiling",
    "m0_functional_overlap_floor", "article_fixture_selection_allowed",
    "exact_m0_required_for_rank", "selection_scope"
  )
  app_check_required_columns(x, required, "Phase178 compute policy")
  if (nrow(x) != 1L || x$policy_id[[1L]] !=
      "phase178_post_m0_case_specific_v1" ||
      isTRUE(x$article_fixture_selection_allowed[[1L]]) ||
      !isTRUE(x$exact_m0_required_for_rank[[1L]]) ||
      x$selection_scope[[1L]] != "case_specific_scenario_readout" ||
      x$vb_method_id[[1L]] != "VB1_structured_v") {
    stop("Phase178 compute policy violates its scientific contract.", call. = FALSE)
  }
  x
}

app_joint_exqdesn_phase178_targets <- function(
  phase176_dir = app_joint_exqdesn_phase176_dirs()$phase176,
  phase177_audit_dir = app_joint_exqdesn_phase176_dirs()$phase177_audit,
  require_phase177_resolution = TRUE
) {
  check176 <- app_joint_exqdesn_verify_manifest(phase176_dir, "phase176")
  if (any(check176$status != "pass")) stop("Phase178 Phase176 source failed.", call. = FALSE)
  c176 <- app_read_csv(file.path(phase176_dir, "fallback_classification.csv"))
  direct <- c176[
    c176$recovery_classification == "post_m0_spec_screen_required", , drop = FALSE
  ]
  eligible <- c176[
    c176$recovery_classification == "same_spec_additional_chains_eligible", , drop = FALSE
  ]
  direct$phase178_entry_source <- "phase176_model_limited"
  direct$phase177_action <- "not_applicable"
  awaiting <- data.frame()
  routed <- data.frame()
  if (nrow(eligible)) {
    manifest <- file.path(phase177_audit_dir, "artifact_manifest.csv")
    if (!file.exists(manifest)) {
      awaiting <- eligible
      awaiting$phase178_entry_source <- "await_phase177_same_spec_resolution"
      awaiting$phase177_action <- "pending"
    } else {
      check177 <- app_joint_exqdesn_verify_manifest(
        phase177_audit_dir, "phase177_audit"
      )
      if (any(check177$status != "pass")) {
        stop("Phase178 Phase177 audit source failed.", call. = FALSE)
      }
      d177 <- app_read_csv(file.path(phase177_audit_dir, "promotion_decision.csv"))
      unresolved <- d177[
        d177$action == "route_to_phase178_case_specific_screen", , drop = FALSE
      ]
      if (nrow(unresolved)) {
        routed <- c176[match(unresolved$case_id, c176$case_id), , drop = FALSE]
        routed$phase178_entry_source <- "phase177_same_spec_not_qualified"
        routed$phase177_action <- unresolved$action
      }
    }
  }
  target_parts <- Filter(function(x) is.data.frame(x) && nrow(x) > 0L, list(direct, routed))
  targets <- if (length(target_parts)) {
    app_joint_qdesn_bind_rows(target_parts)
  } else {
    c176[0, , drop = FALSE]
  }
  targets <- targets[!duplicated(targets$case_id), , drop = FALSE]
  targets <- targets[match(
    intersect(app_joint_exqdesn_phase176_required_case_ids(), targets$case_id),
    targets$case_id
  ), , drop = FALSE]
  if (isTRUE(require_phase177_resolution) && nrow(awaiting)) {
    stop(sprintf(
      "Phase178 is waiting for Phase177 resolution of %d eligible cell(s).",
      nrow(awaiting)
    ), call. = FALSE)
  }
  list(targets = targets, awaiting = awaiting, phase176_verification = check176)
}

app_joint_exqdesn_phase178_candidate_templates <- function(
  targets,
  source_controls,
  neighborhood = app_joint_exqdesn_phase178_load_neighborhood()
) {
  if (!nrow(targets)) return(data.frame())
  rows <- list()
  tau <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
  for (ii in seq_len(nrow(targets))) {
    target <- targets[ii, , drop = FALSE]
    case_id <- target$case_id[[1L]]
    nhood <- neighborhood[neighborhood$case_id == case_id, , drop = FALSE]
    control <- source_controls[source_controls$case_id == case_id, , drop = FALSE]
    if (nrow(nhood) != 1L || nrow(control) != 1L) {
      stop(sprintf("Phase178 could not resolve controls for '%s'.", case_id), call. = FALSE)
    }
    base_alpha <- app_joint_qdesn_parse_numeric_vector(
      control$alpha_prior_sd[[1L]], "Phase178 alpha_prior_sd", allow_inf = TRUE
    )
    if (length(base_alpha) == 1L) base_alpha <- rep(base_alpha, length(tau))
    tail_alpha <- base_alpha * c(1.25, 1.15, 1, 1, 1, 1.15, 1.25)
    variants <- data.frame(
      variant_id = c("parity", "tau0_lower", "tau0_upper", "tail_relaxed"),
      candidate_role = c(
        "exact_phase174_parity", "post_m0_tau0_local", "post_m0_tau0_local",
        "post_m0_quantile_prior_local"
      ),
      tau0 = c(
        control$tau0[[1L]],
        control$tau0[[1L]] * nhood$tau0_low_multiplier[[1L]],
        control$tau0[[1L]] * nhood$tau0_high_multiplier[[1L]],
        control$tau0[[1L]]
      ),
      alpha_prior_sd = c(
        as.character(control$alpha_prior_sd[[1L]]),
        as.character(control$alpha_prior_sd[[1L]]),
        as.character(control$alpha_prior_sd[[1L]]),
        app_joint_qdesn_format_numeric_vector(tail_alpha)
      ),
      design_role = "direct",
      design_class = "direct",
      stringsAsFactors = FALSE
    )
    if (!isTRUE(nhood$include_tail_relaxation[[1L]])) {
      variants <- variants[variants$variant_id != "tail_relaxed", , drop = FALSE]
    }
    if (nhood$alternate_design_role[[1L]] != "none") {
      design <- app_joint_exqdesn_phase151_design_rows(
        target$scenario_id[[1L]],
        match(target$scenario_id[[1L]], app_joint_exqdesn_phase171_scenarios()),
        optimize = TRUE
      )
      design <- design[
        design$design_role == nhood$alternate_design_role[[1L]], , drop = FALSE
      ]
      if (nrow(design) != 1L) {
        stop(sprintf("Unknown Phase178 alternate design for '%s'.", case_id), call. = FALSE)
      }
      alt <- data.frame(
        variant_id = paste0("design_", design$design_role),
        candidate_role = "post_m0_bounded_design_check",
        tau0 = control$tau0[[1L]],
        alpha_prior_sd = as.character(control$alpha_prior_sd[[1L]]),
        design_role = design$design_role,
        design_class = design$design_class,
        stringsAsFactors = FALSE
      )
      for (field in setdiff(names(design), names(alt))) alt[[field]] <- design[[field]]
      variants <- app_joint_qdesn_bind_rows(list(variants, alt))
    }
    for (vv in seq_len(nrow(variants))) {
      variant <- variants[vv, , drop = FALSE]
      out <- control
      out$phase178_template_id <- paste(case_id, variant$variant_id[[1L]], sep = "__")
      out$case_id <- case_id
      out$base_scenario_id <- target$scenario_id[[1L]]
      out$scenario_id <- target$scenario_id[[1L]]
      out$fit_structure <- target$fit_structure[[1L]]
      out$model_id <- if (target$fit_structure[[1L]] == "joint") {
        "joint_exqdesn_rhs_vb"
      } else {
        "exqdesn_rhs_independent_vb"
      }
      out$variant_id <- variant$variant_id[[1L]]
      out$candidate_role <- variant$candidate_role[[1L]]
      out$tau0 <- as.numeric(variant$tau0[[1L]])
      out$alpha_prior_sd <- as.character(variant$alpha_prior_sd[[1L]])
      out$design_role <- variant$design_role[[1L]]
      out$design_class <- variant$design_class[[1L]]
      for (field in c(
        "reservoir_width", "reservoir_alpha", "reservoir_rho",
        "reservoir_pi_w", "reservoir_pi_in", "input_scale", "reservoir_seed"
      )) {
        out[[field]] <- if (field %in% names(variant)) variant[[field]][[1L]] else NA
      }
      out$pre_m0_rank_authority <- FALSE
      out$exact_m0_rank_required <- TRUE
      out$article_fixture_selection_allowed <- FALSE
      out$selection_scope <- "case_specific_scenario_readout"
      out$tau_seed_stride <- 1009L
      rows[[length(rows) + 1L]] <- out
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(out$phase178_template_id) ||
      any(table(out$case_id) > app_joint_exqdesn_phase178_load_compute_policy()$max_candidates_per_cell[[1L]]) ||
      any(out$tau0 <= 0) || any(app_as_bool_vec(out$pre_m0_rank_authority))) {
    stop("Phase178 candidate templates are malformed.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase178_build_dgp_registry <- function(
  base_registry,
  base_scenario_ids,
  policy = app_joint_exqdesn_phase178_load_compute_policy()
) {
  base_scenario_ids <- unique(as.character(base_scenario_ids))
  base <- base_registry[match(base_scenario_ids, base_registry$scenario_id), , drop = FALSE]
  if (any(is.na(base$scenario_id))) {
    stop("Phase178 base registry is missing a target scenario.", call. = FALSE)
  }
  roles <- c("calibration", "m0_ranking", "confirmation")
  counts <- c(
    calibration = as.integer(policy$calibration_replicates[[1L]]),
    m0_ranking = as.integer(policy$ranking_replicates[[1L]]),
    confirmation = as.integer(policy$confirmation_replicates[[1L]])
  )
  rows <- list()
  for (ss in seq_len(nrow(base))) {
    scenario_seed_index <- match(
      base$scenario_id[[ss]], sort(as.character(base_registry$scenario_id))
    )
    for (role_index in seq_along(roles)) {
      role <- roles[[role_index]]
      for (rr in seq_len(counts[[role]])) {
        x <- base[ss, , drop = FALSE]
        x$base_scenario_id <- x$scenario_id[[1L]]
        x$validation_partition <- role
        x$dgp_replicate_id <- sprintf("%s_r%03d", role, rr)
        x$base_seed <- as.integer(x$seed[[1L]])
        x$seed <- as.integer(
          policy$dgp_seed_base[[1L]] + scenario_seed_index * 10000L +
            role_index * 1000L + rr
        )
        x$seed_role <- paste0("phase178_protected_", role, "_dgp")
        x$scenario_id <- paste0(
          x$base_scenario_id[[1L]], "__phase178_", x$dgp_replicate_id[[1L]]
        )
        x$registry_version <- "joint_exqdesn_phase178_post_m0_protected_v1"
        x$notes <- paste(
          x$notes[[1L]],
          sprintf("Fresh Phase178 %s replicate; article fixture excluded.", role)
        )
        rows[[length(rows) + 1L]] <- x
      }
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  app_joint_qdesn_validate_simulation_registry(out)
  prior_seeds <- unique(c(
    as.integer(base_registry$seed),
    153000000L + seq_len(100000L)
  ))
  if (anyDuplicated(out$scenario_id) || anyDuplicated(out$seed) ||
      length(intersect(out$seed, prior_seeds))) {
    stop("Phase178 protected DGP ids or seeds collide.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase178_materialize_fixture_shards <- function(
  registry, out_dir, force = FALSE
) {
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    top <- app_joint_exqdesn_verify_manifest(final_dir, "phase178_fixtures")
    shard <- app_read_csv(file.path(final_dir, "fixture_shard_manifest.csv"))
    paths <- file.path(final_dir, shard$relative_path)
    good <- all(top$status == "pass") && all(file.exists(paths)) &&
      all(tolower(vapply(paths, app_sha256_file, character(1L))) ==
        tolower(shard$sha256))
    frozen <- app_read_csv(file.path(final_dir, "frozen_registry.csv"))
    if (good && identical(as.character(frozen$scenario_id), as.character(registry$scenario_id)) &&
        identical(as.integer(frozen$seed), as.integer(registry$seed))) {
      return(list(out_dir = final_dir, reused = TRUE, shard_manifest = shard))
    }
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  summaries <- splits <- origins <- validations <- list()
  shard_rows <- list()
  for (ii in seq_len(nrow(registry))) {
    fixture <- app_joint_qdesn_fixture_from_registry_row(registry[ii, , drop = FALSE])
    tables <- list(
      observed = app_joint_qdesn_observed_rows(fixture),
      design = app_joint_qdesn_design_rows(fixture),
      true_wide = app_joint_qdesn_true_quantile_wide_rows(fixture)
    )
    for (artifact in names(tables)) {
      relative <- paste0(fixture$scenario_id, "__", artifact, ".csv")
      path <- app_joint_qvp_write_csv(tables[[artifact]], file.path(tmp, relative))
      shard_rows[[length(shard_rows) + 1L]] <- data.frame(
        scenario_id = fixture$scenario_id, artifact = artifact,
        relative_path = relative, size_bytes = as.numeric(file.info(path)$size),
        sha256 = app_sha256_file(path), stringsAsFactors = FALSE
      )
    }
    summaries[[ii]] <- app_joint_qdesn_scenario_summary_row(fixture)
    splits[[ii]] <- app_joint_qdesn_split_metadata_row(fixture)
    origins[[ii]] <- app_joint_qdesn_forecast_origin_plan_rows(fixture)
    validations[[ii]] <- app_joint_qdesn_fixture_validation_rows(
      registry[ii, , drop = FALSE], list(fixture)
    )
    rm(fixture, tables); invisible(gc(FALSE))
  }
  shard_manifest <- app_joint_qdesn_bind_rows(shard_rows)
  validation <- app_joint_qdesn_bind_rows(validations)
  if (any(validation$status != "pass")) {
    stop("Phase178 fixture validation failed.", call. = FALSE)
  }
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  ids <- file.path(tmp, "selected_scenario_ids.txt")
  writeLines(registry$scenario_id, ids, useBytes = TRUE)
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase178 protected fixture shards", "",
    sprintf("- Scenarios: %d", nrow(registry)),
    sprintf("- Base mechanisms: %d", length(unique(registry$base_scenario_id))),
    "- Partitions are frozen as calibration, exact-M0 ranking, and confirmation.",
    "- The article realization is not present.",
    "- Per-scenario shards avoid another multi-gigabyte aggregate CSV bundle."
  ), readme, useBytes = TRUE)
  paths <- c(
    frozen_registry = write(registry, "frozen_registry.csv"),
    selected_scenario_ids = normalizePath(ids, mustWork = TRUE),
    scenario_summary = write(app_joint_qdesn_bind_rows(summaries), "scenario_summary.csv"),
    split_metadata = write(app_joint_qdesn_bind_rows(splits), "split_metadata.csv"),
    forecast_origin_plan = write(app_joint_qdesn_bind_rows(origins), "forecast_origin_plan.csv"),
    fixture_validation = write(validation, "fixture_validation.csv"),
    fixture_shard_manifest = write(shard_manifest, "fixture_shard_manifest.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase178 fixtures.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase178 fixtures.", call. = FALSE)
  top <- app_joint_exqdesn_verify_manifest(final_dir, "phase178_fixtures")
  if (any(top$status != "pass")) stop("Phase178 fixture manifest failed.", call. = FALSE)
  list(out_dir = final_dir, reused = FALSE, shard_manifest = shard_manifest)
}

app_joint_exqdesn_phase178_expand_vb_registry <- function(
  templates, dgp_registry,
  policy = app_joint_exqdesn_phase178_load_compute_policy()
) {
  dgp <- dgp_registry[dgp_registry$validation_partition == "calibration", , drop = FALSE]
  rows <- list()
  for (ii in seq_len(nrow(templates))) {
    template <- templates[ii, , drop = FALSE]
    reps <- dgp[dgp$base_scenario_id == template$base_scenario_id[[1L]], , drop = FALSE]
    for (rr in seq_len(nrow(reps))) {
      x <- template
      x$scenario_ids <- reps$scenario_id[[rr]]
      x$scenario_id <- reps$scenario_id[[rr]]
      x$dgp_replicate_id <- reps$dgp_replicate_id[[rr]]
      x$dgp_seed <- as.integer(reps$seed[[rr]])
      x$validation_partition <- "calibration"
      x$inference_method_id <- policy$vb_method_id[[1L]]
      x$vb_max_iter <- as.integer(policy$vb_max_iter[[1L]])
      x$adaptive_vb_max_iter_grid <- as.character(policy$vb_max_iter[[1L]])
      x$vb_tol <- as.numeric(policy$vb_tol[[1L]])
      x$rhs_vb_inner <- as.integer(policy$rhs_vb_inner[[1L]])
      x$use_existing_phase153 <- FALSE
      x$phase166_candidate_id <- paste(
        x$phase178_template_id[[1L]], reps$dgp_replicate_id[[rr]],
        policy$vb_method_id[[1L]], sep = "__"
      )
      rows[[length(rows) + 1L]] <- x
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(out$phase166_candidate_id) ||
      any(out$validation_partition != "calibration") ||
      any(app_as_bool_vec(out$article_fixture_selection_allowed))) {
    stop("Phase178 VB registry is malformed or leaks article data.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase178_fit_init_rows <- function(fit, candidate) {
  blocks <- list(
    beta = as.numeric(fit$beta_mean), alpha = as.numeric(fit$alpha_mean),
    sigma = as.numeric(fit$sigma_mean), gamma = as.numeric(fit$gamma_mean)
  )
  if (any(!is.finite(unlist(blocks, use.names = FALSE))) || any(blocks$sigma <= 0)) {
    stop("Phase178 VB initialization contains invalid values.", call. = FALSE)
  }
  app_joint_qdesn_bind_rows(lapply(names(blocks), function(block) {
    data.frame(
      mcmc_case_id = paste(
        candidate$phase178_template_id[[1L]],
        candidate$dgp_replicate_id[[1L]], sep = "__"
      ),
      phase178_template_id = candidate$phase178_template_id[[1L]],
      scenario_id = candidate$scenario_ids[[1L]],
      base_scenario_id = candidate$base_scenario_id[[1L]],
      dgp_replicate_id = candidate$dgp_replicate_id[[1L]],
      fit_structure = candidate$fit_structure[[1L]],
      parameter_block = block,
      parameter_index = seq_along(blocks[[block]]),
      value = blocks[[block]],
      initialization_method_id = candidate$inference_method_id[[1L]],
      stringsAsFactors = FALSE
    )
  }))
}

app_joint_exqdesn_phase178_fit_structured_v <- function(candidate, fixture) {
  args <- app_joint_exqdesn_phase166_control_args(candidate, fixture)
  warm <- app_joint_exqdesn_phase166_vb0_warm_start(candidate, fixture)
  fit <- if (candidate$fit_structure[[1L]] == "joint") {
    do.call(app_joint_exqdesn_fit_vb_dispatch, c(
      list(
        method_id = candidate$inference_method_id[[1L]],
        y = fixture$y, Z = fixture$Z, tau = fixture$tau, init = warm
      ), args
    ))
  } else {
    do.call(app_joint_exqdesn_fit_independent_vb_dispatch, c(
      list(
        method_id = candidate$inference_method_id[[1L]],
        y = fixture$y, Z = fixture$Z, tau = fixture$tau, init = warm
      ), args
    ))
  }
  fit
}

app_joint_exqdesn_phase178_candidate_design_id <- function(candidate) {
  for (field in c("phase166_candidate_id", "phase178_template_id", "candidate_id")) {
    value <- candidate[[field]]
    if (length(value) == 1L && !is.na(value) && nzchar(as.character(value))) {
      return(as.character(value))
    }
  }
  stop("Phase178 candidate has no stable design identifier.", call. = FALSE)
}

app_joint_exqdesn_phase178_load_candidate_fixture <- function(candidate, fixture_dir) {
  fixture_dirs <- app_joint_exqdesn_phase164_dirs()
  fixture_dirs$selected_fixtures <- fixture_dir
  artifacts <- app_joint_exqdesn_load_selected_fixture_artifacts(
    candidate$scenario_ids[[1L]], fixture_dirs
  )
  design_candidate <- candidate
  design_candidate$scenario_id <- candidate$scenario_ids[[1L]]
  design_candidate$candidate_id <- app_joint_exqdesn_phase178_candidate_design_id(candidate)
  transformed <- app_joint_exqdesn_phase151_transform_design(
    artifacts, design_candidate
  )
  artifacts$design <- transformed$design
  fixture <- app_joint_qdesn_scenario_fixture(
    artifacts, candidate$scenario_ids[[1L]], role = "fit"
  )
  list(artifacts = artifacts, fixture = fixture, design = transformed$diagnostic)
}

app_joint_exqdesn_phase178_evaluate_vb <- function(candidate, dirs) {
  loaded <- app_joint_exqdesn_phase178_load_candidate_fixture(
    candidate, dirs$phase178_fixtures
  )
  artifacts <- loaded$artifacts
  fixture <- loaded$fixture
  started <- proc.time()[["elapsed"]]
  fit <- app_joint_exqdesn_phase178_fit_structured_v(candidate, fixture)
  fit_seconds <- proc.time()[["elapsed"]] - started
  scored <- app_joint_exqdesn_phase166_score_fit(
    fit, fixture, candidate, artifacts
  )
  diagnostics <- if (candidate$fit_structure[[1L]] == "joint") {
    app_joint_exqdesn_phase166_vb_diagnostics(fit, candidate)
  } else {
    do.call(rbind, lapply(seq_along(fit$fits), function(k) {
      x <- app_joint_exqdesn_phase166_vb_diagnostics(fit$fits[[k]], candidate)
      x$quantile_index <- k; x$tau <- fixture$tau[[k]]; x
    }))
  }
  quadrature <- if (candidate$fit_structure[[1L]] == "joint") {
    app_joint_exqdesn_phase166_compact_quadrature(fit, candidate)
  } else {
    do.call(rbind, lapply(
      fit$fits, app_joint_exqdesn_phase166_compact_quadrature,
      candidate = candidate
    ))
  }
  scale_shape <- if (candidate$fit_structure[[1L]] == "joint") {
    app_joint_exqdesn_phase166_compact_scale_shape(fit, candidate)
  } else {
    do.call(rbind, lapply(
      fit$fits, app_joint_exqdesn_phase166_compact_scale_shape,
      candidate = candidate
    ))
  }
  finite_fit <- all(is.finite(c(
    fit$qhat_mean, fit$alpha_mean, fit$sigma_mean, fit$gamma_mean
  ))) && all(fit$sigma_mean > 0)
  contract_crossings <- scored$fit_summary$contract_crossing_pairs +
    scored$forecast_summary$contract_crossing_pairs
  implementation_fail <- !finite_fit || !scored$finite_scores ||
    contract_crossings > 0
  review <- any(!diagnostics$converged) ||
    any(quadrature$status == "review", na.rm = TRUE)
  gate <- if (implementation_fail) "fail" else if (review) "review" else "pass"
  candidate_summary <- cbind(
    candidate[, c(
      "phase166_candidate_id", "phase178_template_id", "case_id", "base_scenario_id",
      "dgp_replicate_id", "dgp_seed", "scenario_ids", "model_id",
      "fit_structure", "inference_method_id", "variant_id",
      "candidate_role", "design_role", "design_class", "tau0", "zeta2",
      "a_sigma", "b_sigma", "alpha_prior_sd", "gamma_init_policy"
    ), drop = FALSE],
    data.frame(
      candidate_id = candidate$phase166_candidate_id[[1L]],
      validation_partition = "calibration",
      pre_m0_rank_authority = FALSE,
      exact_m0_rank_required = TRUE,
      gate_status = gate,
      implementation_status = if (implementation_fail) "fail" else "pass",
      vb_converged = all(diagnostics$converged),
      vb_reached_max_iter = any(diagnostics$reached_max_iter),
      finite_fit = finite_fit, finite_scores = scored$finite_scores,
      fit_truth_mae = scored$fit_summary$truth_mae,
      fit_truth_rmse = scored$fit_summary$truth_rmse,
      fit_check_loss_mean = scored$fit_summary$check_loss_mean,
      fit_crps_grid_mean = scored$fit_summary$crps_grid_mean,
      fit_raw_crossing_pairs = scored$fit_summary$raw_crossing_pairs,
      fit_contract_crossing_pairs = scored$fit_summary$contract_crossing_pairs,
      forecast_truth_mae = scored$forecast_summary$truth_mae,
      forecast_truth_rmse = scored$forecast_summary$truth_rmse,
      forecast_check_loss_mean = scored$forecast_summary$check_loss_mean,
      forecast_crps_grid_mean = scored$forecast_summary$crps_grid_mean,
      forecast_raw_crossing_pairs = scored$forecast_summary$raw_crossing_pairs,
      forecast_contract_crossing_pairs = scored$forecast_summary$contract_crossing_pairs,
      fit_elapsed_seconds = fit_seconds,
      forecast_scoring_seconds = scored$forecast_seconds,
      total_elapsed_seconds = fit_seconds + scored$forecast_seconds,
      status_reason = if (implementation_fail) {
        "nonfinite fit/score or contract crossing"
      } else if (review) {
        "finite implementation with VB or quadrature review"
      } else {
        "all structured-VB feasibility gates passed"
      },
      stringsAsFactors = FALSE
    )
  )
  runtime <- data.frame(
    candidate_id = candidate$phase166_candidate_id[[1L]],
    runtime_component = c("fit", "forecast_scoring", "total"),
    elapsed_seconds = c(
      fit_seconds, scored$forecast_seconds,
      fit_seconds + scored$forecast_seconds
    ), stringsAsFactors = FALSE
  )
  list(
    candidate_summary = candidate_summary,
    tau_summary = scored$tau_summary,
    interval_summary = scored$interval_summary,
    vb_diagnostics = diagnostics,
    quadrature_summary = quadrature,
    scale_shape_summary = scale_shape,
    design_diagnostics = loaded$design,
    vb_initialization = app_joint_exqdesn_phase178_fit_init_rows(fit, candidate),
    runtime_summary = runtime
  )
}

app_joint_exqdesn_phase178_candidate_dir <- function(out_dir, candidate_id) {
  file.path(out_dir, "vb_candidates", candidate_id)
}

app_joint_exqdesn_phase178_verify_vb_candidate <- function(candidate_dir) {
  if (!file.exists(file.path(candidate_dir, "artifact_manifest.csv"))) return(FALSE)
  tryCatch({
    check <- app_joint_exqdesn_verify_manifest(candidate_dir, "phase178_vb_candidate")
    required <- c(
      "candidate_summary", "tau_summary", "interval_summary",
      "vb_diagnostics", "quadrature_summary", "scale_shape_summary",
      "design_diagnostics", "vb_initialization", "runtime_summary", "README"
    )
    all(check$status == "pass") && all(required %in% check$label)
  }, error = function(e) FALSE)
}

app_joint_exqdesn_phase178_write_vb_candidate <- function(
  result, candidate, out_dir
) {
  candidate_id <- candidate$phase166_candidate_id[[1L]]
  final_dir <- app_joint_exqdesn_phase178_candidate_dir(out_dir, candidate_id)
  if (app_joint_exqdesn_phase178_verify_vb_candidate(final_dir)) return(final_dir)
  app_ensure_dir(dirname(final_dir))
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".invalid.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase178 VB output.", call. = FALSE)
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase178 protected structured-VB feasibility checkpoint", "",
    sprintf("- Candidate: `%s`", candidate_id),
    sprintf("- Case: `%s`", candidate$case_id[[1L]]),
    sprintf("- Replicate: `%s`", candidate$dgp_replicate_id[[1L]]),
    "- This result may prune broken candidates but cannot promote a winner.",
    "- Exact M0 on protected data is required for ranking."
  ), readme, useBytes = TRUE)
  paths <- c(
    candidate_summary = write(result$candidate_summary, "candidate_summary.csv"),
    tau_summary = write(result$tau_summary, "tau_summary.csv"),
    interval_summary = write(result$interval_summary, "interval_summary.csv"),
    vb_diagnostics = write(result$vb_diagnostics, "vb_diagnostics.csv"),
    quadrature_summary = write(result$quadrature_summary, "quadrature_summary.csv"),
    scale_shape_summary = write(result$scale_shape_summary, "scale_shape_summary.csv"),
    design_diagnostics = write(result$design_diagnostics, "design_diagnostics.csv"),
    vb_initialization = write(result$vb_initialization, "vb_initialization.csv"),
    runtime_summary = write(result$runtime_summary, "runtime_summary.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (!file.rename(tmp, final_dir) ||
      !app_joint_exqdesn_phase178_verify_vb_candidate(final_dir)) {
    stop("Could not publish Phase178 VB checkpoint.", call. = FALSE)
  }
  final_dir
}

app_joint_exqdesn_phase178_run_vb_rows <- function(
  row_indices,
  freeze_dir = app_joint_exqdesn_phase176_dirs()$phase178_freeze,
  out_dir = app_joint_exqdesn_phase176_dirs()$phase178
) {
  check <- app_joint_exqdesn_verify_manifest(freeze_dir, "phase178_freeze")
  if (any(check$status != "pass")) stop("Phase178 freeze manifest failed.", call. = FALSE)
  registry <- app_read_csv(file.path(freeze_dir, "vb_candidate_registry.csv"))
  row_indices <- as.integer(row_indices)
  if (any(!is.finite(row_indices)) || any(row_indices < 1L | row_indices > nrow(registry))) {
    stop("Phase178 VB row indices are invalid.", call. = FALSE)
  }
  dirs <- app_joint_exqdesn_phase176_dirs()
  dirs$phase178_freeze <- freeze_dir; dirs$phase178 <- out_dir
  app_joint_qdesn_bind_rows(lapply(row_indices, function(row_id) {
    candidate <- registry[row_id, , drop = FALSE]
    final_dir <- app_joint_exqdesn_phase178_candidate_dir(
      out_dir, candidate$phase166_candidate_id[[1L]]
    )
    if (app_joint_exqdesn_phase178_verify_vb_candidate(final_dir)) {
      return(data.frame(row_index = row_id, status = "reused", message = "", stringsAsFactors = FALSE))
    }
    tryCatch({
      result <- app_joint_exqdesn_phase178_evaluate_vb(candidate, dirs)
      app_joint_exqdesn_phase178_write_vb_candidate(result, candidate, out_dir)
      data.frame(row_index = row_id, status = "completed", message = "", stringsAsFactors = FALSE)
    }, error = function(e) data.frame(
      row_index = row_id, status = "failed", message = conditionMessage(e),
      stringsAsFactors = FALSE
    ))
  }))
}

app_joint_exqdesn_phase178_prepare <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(),
  out_dir = NULL, fixture_dir = NULL,
  materialize_fixtures = TRUE, force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  out_dir <- out_dir %||% dirs$phase178_freeze
  fixture_dir <- fixture_dir %||% dirs$phase178_fixtures
  target <- app_joint_exqdesn_phase178_targets(
    dirs$phase176, dirs$phase177_audit, require_phase177_resolution = TRUE
  )
  if (!nrow(target$targets)) {
    stop("Phase178 has no unresolved cells after Phase176/177.", call. = FALSE)
  }
  policy <- app_joint_exqdesn_phase178_load_compute_policy()
  neighborhood <- app_joint_exqdesn_phase178_load_neighborhood()
  authority <- app_joint_exqdesn_phase178_load_authority()
  source <- app_joint_exqdesn_phase171_load(dirs$phase171)
  templates <- app_joint_exqdesn_phase178_candidate_templates(
    target$targets, source$controls, neighborhood
  )
  base_registry <- app_joint_qdesn_load_simulation_registry()
  dgp_registry <- app_joint_exqdesn_phase178_build_dgp_registry(
    base_registry, unique(target$targets$scenario_id), policy
  )
  fixture_result <- if (isTRUE(materialize_fixtures)) {
    app_joint_exqdesn_phase178_materialize_fixture_shards(
      dgp_registry, fixture_dir, force = force
    )
  } else {
    list(out_dir = fixture_dir, reused = NA, shard_manifest = data.frame())
  }
  vb_registry <- app_joint_exqdesn_phase178_expand_vb_registry(
    templates, dgp_registry, policy
  )
  expected_vb <- nrow(templates) * as.integer(policy$calibration_replicates[[1L]])
  if (nrow(vb_registry) != expected_vb) {
    stop("Phase178 VB candidate count does not match the frozen design.", call. = FALSE)
  }
  readiness <- data.frame(
    phase_id = "phase178_post_m0_case_specific_screen_freeze",
    gate_status = "pass", target_cells = nrow(target$targets),
    candidate_templates = nrow(templates),
    protected_dgp_rows = nrow(dgp_registry),
    vb_calibration_rows = nrow(vb_registry),
    article_fixture_rows = 0L, pre_m0_rank_authority = FALSE,
    exact_m0_required_for_rank = TRUE,
    global_specification_selected = FALSE,
    fixtures_materialized = isTRUE(materialize_fixtures),
    recommendation = "run_phase178_structured_vb_feasibility_then_exact_M0_ranking",
    stringsAsFactors = FALSE
  )
  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(final_dir, "phase178_freeze")
    if (all(check$status == "pass")) {
      return(list(out_dir = final_dir, readiness = app_read_csv(file.path(final_dir, "readiness_assessment.csv")), reused = TRUE))
    }
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Joint exQDESN Phase178 post-M0 case-specific screen freeze", "",
    sprintf("- Target cells: %d", nrow(target$targets)),
    sprintf("- Candidate templates: %d", nrow(templates)),
    sprintf("- Protected DGP rows: %d", nrow(dgp_registry)),
    sprintf("- Structured-VB calibration rows: %d", nrow(vb_registry)),
    "- Pre-M0 results define neighborhoods only and have no ranking authority.",
    "- Structured VB is a feasibility filter; exact M0 on protected rows ranks survivors.",
    "- The article realization is excluded from selection."
  ), readme, useBytes = TRUE)
  fixture_manifest <- file.path(fixture_dir, "artifact_manifest.csv")
  paths <- c(
    phase176_manifest_verification = write(target$phase176_verification, "phase176_manifest_verification.csv"),
    phase171_manifest_verification = write(source$verification, "phase171_manifest_verification.csv"),
    recovery_policy = write(app_joint_exqdesn_phase176_load_policy(), "recovery_policy.csv"),
    prior_screen_authority = write(authority, "prior_screen_authority.csv"),
    case_neighborhood = write(neighborhood, "case_neighborhood.csv"),
    compute_policy = write(policy, "compute_policy.csv"),
    target_cells = write(target$targets, "target_cells.csv"),
    candidate_templates = write(templates, "candidate_templates.csv"),
    protected_dgp_registry = write(dgp_registry, "protected_dgp_registry.csv"),
    vb_candidate_registry = write(vb_registry, "vb_candidate_registry.csv"),
    fixture_source = write(data.frame(
      fixture_dir = normalizePath(fixture_dir, mustWork = isTRUE(materialize_fixtures)),
      artifact_manifest_sha256 = if (file.exists(fixture_manifest)) app_sha256_file(fixture_manifest) else NA_character_,
      materialized = isTRUE(materialize_fixtures), stringsAsFactors = FALSE
    ), "fixture_source.csv"),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    run_config = write(data.frame(
      phase_id = readiness$phase_id, cache_root = cache_root,
      output_dir = final_dir, fixture_dir = fixture_dir,
      code_commit = app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD")),
      article_assets_modified = FALSE, stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase178 freeze.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase178 freeze.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase178_freeze")
  if (any(check$status != "pass")) stop("Phase178 freeze manifest failed.", call. = FALSE)
  list(out_dir = final_dir, readiness = readiness, reused = FALSE)
}

app_joint_exqdesn_phase178_vb_health <- function(
  freeze_dir = app_joint_exqdesn_phase176_dirs()$phase178_freeze,
  out_dir = app_joint_exqdesn_phase176_dirs()$phase178
) {
  registry <- app_read_csv(file.path(freeze_dir, "vb_candidate_registry.csv"))
  complete <- vapply(registry$phase166_candidate_id, function(id) {
    app_joint_exqdesn_phase178_verify_vb_candidate(
      app_joint_exqdesn_phase178_candidate_dir(out_dir, id)
    )
  }, logical(1L))
  data.frame(
    stage = "Phase178 protected structured-VB feasibility",
    planned = nrow(registry), complete = sum(complete),
    remaining = sum(!complete), percent_complete = 100 * mean(complete),
    stringsAsFactors = FALSE
  )
}

app_joint_exqdesn_phase178_expand_m0_registry <- function(
  survivor_templates, dgp_registry,
  policy = app_joint_exqdesn_phase178_load_compute_policy(),
  partition = "m0_ranking", seed_base = 178500000L
) {
  if (!partition %in% c("m0_ranking", "confirmation", "article_evaluation")) {
    stop("Unsupported exact-M0 validation partition.", call. = FALSE)
  }
  reps <- dgp_registry[dgp_registry$validation_partition == partition, , drop = FALSE]
  if (!nrow(reps)) stop("No DGP rows exist for the requested M0 partition.", call. = FALSE)
  rows <- list(); worker_id <- 0L; case_index <- 0L
  for (ii in seq_len(nrow(survivor_templates))) {
    template <- survivor_templates[ii, , drop = FALSE]
    block <- reps[reps$base_scenario_id == template$base_scenario_id[[1L]], , drop = FALSE]
    for (rr in seq_len(nrow(block))) {
      case_index <- case_index + 1L
      base <- template
      base$scenario_ids <- block$scenario_id[[rr]]
      base$scenario_id <- block$scenario_id[[rr]]
      base$dgp_replicate_id <- block$dgp_replicate_id[[rr]]
      base$dgp_seed <- as.integer(block$seed[[rr]])
      base$validation_partition <- partition
      base$mcmc_case_id <- paste(
        base$phase178_template_id[[1L]], base$dgp_replicate_id[[1L]], sep = "__"
      )
      base$n_chains <- if (partition == "m0_ranking") {
        as.integer(policy$m0_ranking_chains[[1L]])
      } else {
        as.integer(policy$m0_confirmation_chains[[1L]])
      }
      base$n_iter <- if (partition == "m0_ranking") {
        as.integer(policy$m0_ranking_n_iter[[1L]])
      } else {
        as.integer(policy$m0_confirmation_n_iter[[1L]])
      }
      base$burn <- if (partition == "m0_ranking") {
        as.integer(policy$m0_ranking_burn[[1L]])
      } else {
        as.integer(policy$m0_confirmation_burn[[1L]])
      }
      base$thin <- if (partition == "m0_ranking") {
        as.integer(policy$m0_ranking_thin[[1L]])
      } else {
        as.integer(policy$m0_confirmation_thin[[1L]])
      }
      base$inference_method_id <- "M0_v_collapsed_support_logit"
      base$exact_m0_rank <- TRUE
      base$article_fixture_selection_allowed <- FALSE
      for (chain_id in seq_len(base$n_chains[[1L]])) {
        worker_id <- worker_id + 1L
        x <- base
        x$worker_id <- worker_id
        x$chain_id <- chain_id
        x$wave_id <- as.integer(ceiling(chain_id / 4))
        x$chain_seed <- as.integer(
          seed_base + case_index * 250000L + chain_id * 10000L
        )
        x$seed_role <- paste0("phase178_", partition, "_exact_M0_chain")
        x$start_profile_id <- sprintf(
          "%s__%s__chain_%02d", x$phase178_template_id[[1L]],
          x$dgp_replicate_id[[1L]], chain_id
        )
        rows[[worker_id]] <- x
      }
    }
  }
  out <- app_joint_qdesn_bind_rows(rows)
  component <- app_joint_exqdesn_phase178_component_seed_plan(out)
  if (anyDuplicated(paste(out$mcmc_case_id, out$chain_id)) ||
      anyDuplicated(out$chain_seed) || anyDuplicated(component$component_seed) ||
      any(!is.finite(out$chain_seed)) || any(out$chain_seed >= .Machine$integer.max) ||
      any(app_as_bool_vec(out$article_fixture_selection_allowed)) ||
      any(!app_as_bool_vec(out$exact_m0_rank))) {
    stop("Phase178 exact-M0 worker registry is malformed.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase178_component_seed_plan <- function(plan) {
  tau <- c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)
  rows <- lapply(seq_len(nrow(plan)), function(ii) {
    job <- plan[ii, , drop = FALSE]
    if (job$fit_structure[[1L]] == "joint") {
      return(data.frame(
        worker_id = job$worker_id[[1L]], mcmc_case_id = job$mcmc_case_id[[1L]],
        chain_id = job$chain_id[[1L]], quantile_index = NA_integer_, tau = NA_real_,
        component_seed = as.integer(job$chain_seed[[1L]]),
        seed_role = "joint_multiquantile_component", stringsAsFactors = FALSE
      ))
    }
    stride <- as.integer(job$tau_seed_stride[[1L]])
    data.frame(
      worker_id = job$worker_id[[1L]], mcmc_case_id = job$mcmc_case_id[[1L]],
      chain_id = job$chain_id[[1L]], quantile_index = seq_along(tau), tau = tau,
      component_seed = as.integer(job$chain_seed[[1L]] + seq_along(tau) * stride),
      seed_role = "independent_quantile_component", stringsAsFactors = FALSE
    )
  })
  out <- app_joint_qdesn_bind_rows(rows)
  if (anyDuplicated(out$component_seed) || any(out$component_seed >= .Machine$integer.max)) {
    stop("Phase178 component seed plan has collisions or overflow.", call. = FALSE)
  }
  out
}

app_joint_exqdesn_phase178_finalize_vb <- function(
  freeze_dir = app_joint_exqdesn_phase176_dirs()$phase178_freeze,
  out_dir = app_joint_exqdesn_phase176_dirs()$phase178,
  force = FALSE
) {
  freeze_check <- app_joint_exqdesn_verify_manifest(freeze_dir, "phase178_freeze")
  if (any(freeze_check$status != "pass")) stop("Phase178 freeze verification failed.", call. = FALSE)
  registry <- app_read_csv(file.path(freeze_dir, "vb_candidate_registry.csv"))
  health <- app_joint_exqdesn_phase178_vb_health(freeze_dir, out_dir)
  if (health$remaining[[1L]] > 0L) {
    stop("Phase178 structured-VB feasibility is incomplete.", call. = FALSE)
  }
  load <- function(name) app_joint_qdesn_bind_rows(lapply(
    registry$phase166_candidate_id, function(id) {
      app_read_csv(file.path(
        app_joint_exqdesn_phase178_candidate_dir(out_dir, id), name
      ))
    }
  ))
  summary <- load("candidate_summary.csv")
  diagnostics <- load("vb_diagnostics.csv")
  design <- load("design_diagnostics.csv")
  initialization <- load("vb_initialization.csv")
  runtime <- load("runtime_summary.csv")
  parity <- summary[summary$variant_id == "parity", c(
    "case_id", "dgp_replicate_id", "forecast_truth_mae",
    "forecast_check_loss_mean", "forecast_crps_grid_mean", "fit_truth_mae"
  ), drop = FALSE]
  names(parity)[-(1:2)] <- paste0("parity_", names(parity)[-(1:2)])
  paired <- merge(
    summary, parity, by = c("case_id", "dgp_replicate_id"),
    all.x = TRUE, sort = FALSE
  )
  paired$delta_forecast_mae_vs_parity <- paired$forecast_truth_mae -
    paired$parity_forecast_truth_mae
  paired$delta_check_loss_vs_parity <- paired$forecast_check_loss_mean -
    paired$parity_forecast_check_loss_mean
  paired$delta_crps_vs_parity <- paired$forecast_crps_grid_mean -
    paired$parity_forecast_crps_grid_mean
  groups <- interaction(
    paired$case_id, paired$phase178_template_id, drop = TRUE, lex.order = TRUE
  )
  aggregate <- app_joint_qdesn_bind_rows(lapply(split(paired, groups), function(x) {
    data.frame(
      case_id = x$case_id[[1L]],
      base_scenario_id = x$base_scenario_id[[1L]],
      fit_structure = x$fit_structure[[1L]],
      phase178_template_id = x$phase178_template_id[[1L]],
      variant_id = x$variant_id[[1L]], candidate_role = x$candidate_role[[1L]],
      design_role = x$design_role[[1L]], tau0 = x$tau0[[1L]],
      alpha_prior_sd = x$alpha_prior_sd[[1L]],
      calibration_replicates = nrow(x),
      implementation_pass_fraction = mean(x$implementation_status == "pass"),
      vb_converged_fraction = mean(x$vb_converged),
      median_forecast_truth_mae = stats::median(x$forecast_truth_mae),
      mean_forecast_truth_mae = mean(x$forecast_truth_mae),
      sd_forecast_truth_mae = stats::sd(x$forecast_truth_mae),
      median_delta_forecast_mae_vs_parity = stats::median(x$delta_forecast_mae_vs_parity),
      win_fraction_vs_parity = mean(x$delta_forecast_mae_vs_parity < 0),
      median_check_loss_ratio_vs_parity = stats::median(
        x$forecast_check_loss_mean / x$parity_forecast_check_loss_mean
      ),
      median_crps_ratio_vs_parity = stats::median(
        x$forecast_crps_grid_mean / x$parity_forecast_crps_grid_mean
      ),
      contract_crossing_pairs = sum(
        x$fit_contract_crossing_pairs + x$forecast_contract_crossing_pairs
      ),
      structured_vb_role = "feasibility_and_coarse_pruning_only",
      exact_m0_rank_required = TRUE,
      stringsAsFactors = FALSE
    )
  }))
  templates <- app_read_csv(file.path(freeze_dir, "candidate_templates.csv"))
  policy <- app_joint_exqdesn_phase178_load_compute_policy(
    file.path(freeze_dir, "compute_policy.csv")
  )
  survivor_ids <- unlist(lapply(split(aggregate, aggregate$case_id), function(x) {
    eligible <- x[
      x$implementation_pass_fraction == 1 & x$contract_crossing_pairs == 0 &
        x$median_check_loss_ratio_vs_parity <= 1.15 &
        x$median_crps_ratio_vs_parity <= 1.15, , drop = FALSE
    ]
    parity_id <- x$phase178_template_id[x$variant_id == "parity"]
    eligible <- eligible[order(
      eligible$median_forecast_truth_mae, eligible$phase178_template_id
    ), , drop = FALSE]
    unique(c(
      parity_id,
      head(
        setdiff(eligible$phase178_template_id, parity_id),
        as.integer(policy$max_m0_survivors_per_cell[[1L]]) - 1L
      )
    ))
  }), use.names = FALSE)
  survivors <- templates[
    match(unique(survivor_ids), templates$phase178_template_id), , drop = FALSE
  ]
  if (any(is.na(survivors$phase178_template_id)) ||
      any(table(survivors$case_id) > policy$max_m0_survivors_per_cell[[1L]]) ||
      any(!vapply(split(survivors, survivors$case_id), function(x) any(x$variant_id == "parity"), logical(1L)))) {
    stop("Phase178 survivor freeze is malformed.", call. = FALSE)
  }
  dgp <- app_read_csv(file.path(freeze_dir, "protected_dgp_registry.csv"))
  m0_registry <- app_joint_exqdesn_phase178_expand_m0_registry(
    survivors, dgp, policy, partition = "m0_ranking"
  )
  assessment <- data.frame(
    phase_id = "phase178_structured_vb_feasibility",
    gate_status = if (any(summary$implementation_status == "fail")) "review" else "pass",
    completed_rows = nrow(summary), expected_rows = nrow(registry),
    survivor_templates = nrow(survivors),
    exact_m0_ranking_workers = nrow(m0_registry),
    vb_selected_final_winners = 0L,
    article_fixture_used = FALSE, pre_m0_rank_authority = FALSE,
    recommendation = "run_all_frozen_survivors_under_protected_exact_M0",
    stringsAsFactors = FALSE
  )
  final_dir <- file.path(out_dir, "vb_feasibility_audit")
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(final_dir, "phase178_vb_audit")
    if (all(check$status == "pass")) return(list(out_dir = final_dir, assessment = app_read_csv(file.path(final_dir, "assessment.csv"))))
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid()); app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase178 structured-VB feasibility audit", "",
    "Structured VB removed only invalid or grossly noncompetitive candidates.",
    "It did not select a final winner. Every frozen survivor is ranked under exact M0",
    "on a separate protected partition; parity is retained in every cell."
  ), readme, useBytes = TRUE)
  paths <- c(
    freeze_manifest_verification = write(freeze_check, "freeze_manifest_verification.csv"),
    health_summary = write(health, "health_summary.csv"),
    candidate_summary = write(summary, "candidate_summary.csv"),
    paired_candidate_summary = write(paired, "paired_candidate_summary.csv"),
    candidate_aggregate = write(aggregate, "candidate_aggregate.csv"),
    survivor_templates = write(survivors, "survivor_templates.csv"),
    exact_m0_ranking_registry = write(m0_registry, "exact_m0_ranking_registry.csv"),
    vb_diagnostics = write(diagnostics, "vb_diagnostics.csv"),
    design_diagnostics = write(design, "design_diagnostics.csv"),
    vb_initialization = write(initialization, "vb_initialization.csv"),
    runtime_summary = write(runtime, "runtime_summary.csv"),
    assessment = write(assessment, "assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase178 VB audit.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase178 VB audit.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase178_vb_audit")
  if (any(check$status != "pass")) stop("Phase178 VB audit manifest failed.", call. = FALSE)
  list(out_dir = final_dir, assessment = assessment, m0_registry = m0_registry)
}

app_joint_exqdesn_phase178_m0_worker_dir <- function(result_dir, job) {
  file.path(
    result_dir, "candidates", job$mcmc_case_id[[1L]],
    sprintf("chain_%02d", as.integer(job$chain_id[[1L]]))
  )
}

app_joint_exqdesn_phase178_m0_init_one <- function(row, fixture_dir, n_chains, vb_method_id) {
  candidate <- row
  candidate$inference_method_id <- vb_method_id
  candidate$phase166_candidate_id <- paste0(
    row$mcmc_case_id[[1L]], "__", vb_method_id, "_initialization"
  )
  loaded <- app_joint_exqdesn_phase178_load_candidate_fixture(candidate, fixture_dir)
  started <- proc.time()[["elapsed"]]
  fit <- app_joint_exqdesn_phase178_fit_structured_v(candidate, loaded$fixture)
  elapsed <- proc.time()[["elapsed"]] - started
  score <- app_joint_exqdesn_phase166_score_fit(
    fit, loaded$fixture, candidate, loaded$artifacts
  )
  init <- app_joint_exqdesn_phase178_fit_init_rows(fit, candidate)
  init$mcmc_case_id <- row$mcmc_case_id[[1L]]
  starts <- app_joint_exqdesn_phase156_chain_starts(
    list(sigma_mean = fit$sigma_mean, gamma_mean = fit$gamma_mean),
    loaded$fixture$tau, row$mcmc_case_id[[1L]], n_chains
  )
  names(starts)[names(starts) == "scenario_id"] <- "mcmc_case_id"
  starts$scenario_id <- row$scenario_ids[[1L]]
  starts$base_scenario_id <- row$base_scenario_id[[1L]]
  starts$fit_structure <- row$fit_structure[[1L]]
  finite <- all(is.finite(c(
    fit$beta_mean, fit$alpha_mean, fit$sigma_mean, fit$gamma_mean,
    score$fit_summary$truth_mae, score$forecast_summary$truth_mae
  ))) && all(fit$sigma_mean > 0)
  contract <- score$fit_summary$contract_crossing_pairs +
    score$forecast_summary$contract_crossing_pairs
  audit <- data.frame(
    mcmc_case_id = row$mcmc_case_id[[1L]],
    phase178_template_id = row$phase178_template_id[[1L]],
    case_id = row$case_id[[1L]], scenario_id = row$scenario_ids[[1L]],
    base_scenario_id = row$base_scenario_id[[1L]],
    dgp_replicate_id = row$dgp_replicate_id[[1L]],
    validation_partition = row$validation_partition[[1L]],
    fit_structure = row$fit_structure[[1L]],
    initialization_method_id = vb_method_id,
    vb_converged = isTRUE(fit$converged),
    finite_initialization = finite,
    fit_truth_mae = score$fit_summary$truth_mae,
    forecast_truth_mae = score$forecast_summary$truth_mae,
    fit_check_loss_mean = score$fit_summary$check_loss_mean,
    forecast_check_loss_mean = score$forecast_summary$check_loss_mean,
    fit_crps_grid_mean = score$fit_summary$crps_grid_mean,
    forecast_crps_grid_mean = score$forecast_summary$crps_grid_mean,
    fit_raw_crossing_pairs = score$fit_summary$raw_crossing_pairs,
    forecast_raw_crossing_pairs = score$forecast_summary$raw_crossing_pairs,
    fit_max_abs_adjustment = score$fit_summary$max_abs_adjustment,
    forecast_max_abs_adjustment = score$forecast_summary$max_abs_adjustment,
    fit_contract_crossing_pairs = score$fit_summary$contract_crossing_pairs,
    forecast_contract_crossing_pairs = score$forecast_summary$contract_crossing_pairs,
    elapsed_seconds = elapsed,
    status = if (finite && contract == 0L) "pass" else "fail",
    stringsAsFactors = FALSE
  )
  list(init = init, starts = starts, audit = audit, design = loaded$design)
}

app_joint_exqdesn_phase178_prepare_m0_freeze <- function(
  candidate_templates, dgp_registry, partition, source_dir, fixture_dir,
  out_dir, result_dir, phase_id, seed_base, n_vb_cores = 8L,
  policy = app_joint_exqdesn_phase178_load_compute_policy(), force = FALSE
) {
  source_check <- app_joint_exqdesn_verify_manifest(source_dir, paste0(phase_id, "_source"))
  fixture_check <- app_joint_exqdesn_verify_manifest(fixture_dir, paste0(phase_id, "_fixtures"))
  if (any(source_check$status != "pass") || any(fixture_check$status != "pass")) {
    stop("Exact-M0 freeze source verification failed.", call. = FALSE)
  }
  plan <- app_joint_exqdesn_phase178_expand_m0_registry(
    candidate_templates, dgp_registry, policy, partition, seed_base
  )
  plan$model_id <- ifelse(
    plan$fit_structure == "joint", "joint_exqdesn_rhs_mcmc",
    "independent_exqdesn_rhs_mcmc"
  )
  plan$display_label <- ifelse(
    plan$fit_structure == "joint", "Joint exQDESN RHS",
    "Independent exQDESN RHS"
  )
  plan$n_keep <- as.integer((plan$n_iter - plan$burn) / plan$thin)
  plan$worker_output_dir <- vapply(seq_len(nrow(plan)), function(ii) {
    app_joint_exqdesn_phase178_m0_worker_dir(result_dir, plan[ii, , drop = FALSE])
  }, character(1L))
  controls <- candidate_templates
  controls$candidate_id <- controls$phase178_template_id
  controls$cell_index <- seq_len(nrow(controls))
  controls$source_control_row_sha256 <- vapply(seq_len(nrow(controls)), function(ii) {
    app_joint_exqdesn_phase171_row_hash(controls[ii, , drop = FALSE])
  }, character(1L))
  plan$cell_index <- controls$cell_index[match(plan$phase178_template_id, controls$phase178_template_id)]
  plan$source_control_row_sha256 <- controls$source_control_row_sha256[
    match(plan$phase178_template_id, controls$phase178_template_id)
  ]
  plan$fixture_manifest_sha256 <- app_sha256_file(file.path(fixture_dir, "artifact_manifest.csv"))
  plan$code_commit <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD"))
  components <- app_joint_exqdesn_phase178_component_seed_plan(plan)
  cases <- plan[!duplicated(plan$mcmc_case_id), , drop = FALSE]
  run_init <- function(ii) try(
    app_joint_exqdesn_phase178_m0_init_one(
      cases[ii, , drop = FALSE], fixture_dir,
      cases$n_chains[[ii]], policy$vb_method_id[[1L]]
    ), silent = TRUE
  )
  initialization <- if (.Platform$OS.type != "windows" && n_vb_cores > 1L) {
    parallel::mclapply(
      seq_len(nrow(cases)), run_init,
      mc.cores = min(as.integer(n_vb_cores), nrow(cases)), mc.preschedule = FALSE
    )
  } else {
    lapply(seq_len(nrow(cases)), run_init)
  }
  failed <- vapply(initialization, inherits, logical(1L), "try-error")
  if (any(failed)) {
    messages <- vapply(initialization[failed], as.character, character(1L))
    stop(sprintf("Exact-M0 VB initialization failed: %s", paste(messages, collapse = " | ")), call. = FALSE)
  }
  init <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "init"))
  starts <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "starts"))
  init_audit <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "audit"))
  design_audit <- app_joint_qdesn_bind_rows(lapply(initialization, `[[`, "design"))
  if (any(init_audit$status != "pass") ||
      anyDuplicated(paste(plan$mcmc_case_id, plan$chain_id)) ||
      anyDuplicated(components$component_seed)) {
    stop("Exact-M0 initialization, seed, or preflight gate failed.", call. = FALSE)
  }

  final_dir <- normalizePath(out_dir, mustWork = FALSE)
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(final_dir, phase_id)
    if (all(check$status == "pass")) {
      return(list(out_dir = final_dir, plan = app_read_csv(file.path(final_dir, "chain_plan.csv")), reused = TRUE))
    }
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid())
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE, force = TRUE)
  app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  controls_path <- write(controls, "model_control_freeze.csv")
  plan$source_control_file_sha256 <- app_sha256_file(controls_path)
  readiness <- data.frame(
    phase_id = phase_id, gate_status = "pass", validation_partition = partition,
    candidate_templates = nrow(candidate_templates), mcmc_cases = nrow(cases),
    planned_workers = nrow(plan), planned_components = nrow(components),
    unique_chain_seeds = length(unique(plan$chain_seed)),
    unique_component_seeds = length(unique(components$component_seed)),
    exact_m0 = TRUE, article_fixture_used_for_selection = FALSE,
    global_specification_selected = FALSE,
    recommendation = paste0("launch_", phase_id), stringsAsFactors = FALSE
  )
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    sprintf("# %s", phase_id), "",
    sprintf("- Partition: `%s`", partition),
    sprintf("- Case-specific templates: %d", nrow(candidate_templates)),
    sprintf("- Parallel chain workers: %d", nrow(plan)),
    sprintf("- Physical sampler components: %d", nrow(components)),
    "- Structured-v initializes each candidate-replicate once.",
    "- Every ranking/confirmation draw uses exact M0; old pre-M0 ranks have no authority.",
    "- Workers are independently checkpointed and use one numerical thread."
  ), readme, useBytes = TRUE)
  paths <- c(
    source_manifest_verification = write(source_check, "source_manifest_verification.csv"),
    fixture_manifest_verification = write(fixture_check, "fixture_manifest_verification.csv"),
    model_control_freeze = controls_path,
    protected_dgp_registry = write(dgp_registry, "protected_dgp_registry.csv"),
    chain_plan = write(plan, "chain_plan.csv"),
    component_seed_plan = write(components, "component_seed_plan.csv"),
    vb_initialization = write(init, "vb_initialization.csv"),
    chain_start_values = write(starts, "chain_start_values.csv"),
    vb_initialization_audit = write(init_audit, "vb_initialization_audit.csv"),
    design_preflight = write(design_audit, "design_preflight.csv"),
    readiness_assessment = write(readiness, "readiness_assessment.csv"),
    run_config = write(data.frame(
      phase_id = phase_id, partition = partition,
      source_dir = normalizePath(source_dir), fixture_dir = normalizePath(fixture_dir),
      result_dir = result_dir, code_commit = unique(plan$code_commit),
      exact_m0_required = TRUE, article_fixture_selection_allowed = FALSE,
      stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine prior exact-M0 freeze.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish exact-M0 freeze.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, phase_id)
  if (any(check$status != "pass")) stop("Exact-M0 freeze manifest failed.", call. = FALSE)
  list(out_dir = final_dir, plan = plan, readiness = readiness, reused = FALSE)
}

app_joint_exqdesn_phase178_load_m0_freeze <- function(freeze_dir, source_id) {
  check <- app_joint_exqdesn_verify_manifest(freeze_dir, source_id)
  if (any(check$status != "pass")) stop("Exact-M0 freeze verification failed.", call. = FALSE)
  list(
    dir = normalizePath(freeze_dir), verification = check,
    config = app_read_csv(file.path(freeze_dir, "run_config.csv")),
    controls = app_read_csv(file.path(freeze_dir, "model_control_freeze.csv")),
    init = app_read_csv(file.path(freeze_dir, "vb_initialization.csv")),
    starts = app_read_csv(file.path(freeze_dir, "chain_start_values.csv")),
    plan = app_read_csv(file.path(freeze_dir, "chain_plan.csv")),
    components = app_read_csv(file.path(freeze_dir, "component_seed_plan.csv")),
    readiness = app_read_csv(file.path(freeze_dir, "readiness_assessment.csv"))
  )
}

app_joint_exqdesn_phase178_run_m0_worker <- function(
  freeze_dir, worker_id, source_id, reuse_completed = TRUE, failure_dir = NULL
) {
  freeze <- app_joint_exqdesn_phase178_load_m0_freeze(freeze_dir, source_id)
  worker_id <- as.integer(worker_id)[[1L]]
  job <- freeze$plan[freeze$plan$worker_id == worker_id, , drop = FALSE]
  if (nrow(job) != 1L) stop("Unknown exact-M0 worker id.", call. = FALSE)
  worker_dir <- job$worker_output_dir[[1L]]
  if (reuse_completed && app_joint_exqdesn_phase172_worker_complete(worker_dir)) {
    return(list(worker_id = worker_id, status = "reused_verified", worker_dir = worker_dir))
  }
  component <- freeze$components[freeze$components$worker_id == worker_id, , drop = FALSE]
  expected <- if (job$fit_structure[[1L]] == "joint") 1L else 7L
  if (nrow(component) != expected || anyDuplicated(component$component_seed)) {
    stop("Malformed exact-M0 component seed plan.", call. = FALSE)
  }
  has_checkpoint <- app_joint_exqdesn_phase172_checkpoint_complete(worker_dir)
  if (!has_checkpoint && dir.exists(worker_dir) &&
      length(list.files(worker_dir, all.files = TRUE, no.. = TRUE))) {
    quarantine <- paste0(worker_dir, ".incomplete.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(worker_dir, quarantine)) stop("Could not quarantine incomplete exact-M0 worker.", call. = FALSE)
  }
  app_ensure_dir(worker_dir)
  tryCatch({
    control <- freeze$controls[
      freeze$controls$phase178_template_id == job$phase178_template_id[[1L]], , drop = FALSE
    ]
    if (nrow(control) != 1L ||
        control$source_control_row_sha256[[1L]] != job$source_control_row_sha256[[1L]]) {
      stop("Exact-M0 worker could not resolve its frozen case-specific control.", call. = FALSE)
    }
    loaded <- app_joint_exqdesn_phase178_load_candidate_fixture(
      job, freeze$config$fixture_dir[[1L]]
    )
    fixture <- loaded$fixture
    K <- length(fixture$tau); p <- ncol(fixture$Z)
    init <- app_joint_exqdesn_phase169_init_from_rows(
      freeze$init, job$mcmc_case_id[[1L]], job$fit_structure[[1L]], K, p
    )
    init <- app_joint_exqdesn_phase169_apply_chain_start(
      init, freeze$starts, job, K, p
    )
    alpha_prior_sd <- app_joint_qdesn_parse_numeric_vector(
      control$alpha_prior_sd[[1L]], "alpha_prior_sd", allow_inf = TRUE
    )
    common <- list(
      y = fixture$y, Z = fixture$Z, tau = fixture$tau,
      n_iter = as.integer(job$n_iter[[1L]]), burn = as.integer(job$burn[[1L]]),
      thin = as.integer(job$thin[[1L]]), seed = as.integer(job$chain_seed[[1L]]),
      kappa = 1, tau0 = as.numeric(control$tau0[[1L]]),
      zeta2 = as.numeric(control$zeta2[[1L]]),
      a_sigma = as.numeric(control$a_sigma[[1L]]),
      b_sigma = as.numeric(control$b_sigma[[1L]]),
      gamma_init = init$gamma_mean, init = init,
      alpha_prior_mean = "empirical_quantile", alpha_prior_sd = alpha_prior_sd,
      alpha_min_spacing = if (job$fit_structure[[1L]] == "joint") {
        as.numeric(control$alpha_min_spacing[[1L]])
      } else 0,
      max_dense_dim = as.integer(control$max_dense_dim[[1L]]),
      gamma_slice_width = as.numeric(job$gamma_slice_width[[1L]]),
      gamma_slice_max_steps = as.integer(job$gamma_slice_max_steps[[1L]])
    )
    checkpoint <- if (has_checkpoint) {
      app_joint_exqdesn_phase172_load_checkpoint(
        worker_dir, fixture, job, component, freeze$dir
      )
    } else {
      started <- proc.time()[["elapsed"]]
      fit <- if (job$fit_structure[[1L]] == "joint") {
        do.call(app_joint_exqdesn_fit_mcmc_dispatch, c(
          list(method_id = "M0_v_collapsed_support_logit"), common
        ))
      } else {
        do.call(app_joint_exqdesn_fit_independent_mcmc_dispatch, c(
          list(
            method_id = "M0_v_collapsed_support_logit",
            tau_seed_stride = as.integer(job$tau_seed_stride[[1L]])
          ), common
        ))
      }
      elapsed <- proc.time()[["elapsed"]] - started
      app_joint_exqdesn_phase172_write_checkpoint(
        fit, fixture, job, control, component, elapsed,
        freeze$dir, worker_dir
      )
    }
    fit <- checkpoint$fit
    draws <- checkpoint$draws
    meta <- app_joint_exqdesn_phase172_meta(job, control)
    fit_score <- app_joint_qdesn_phase122_score_qhat(
      meta, fixture, app_joint_qdesn_predict_fit(fit, fixture$Z, fixture$tau),
      "qhat", paste0(source_id, "_chain_fit")
    )
    forecast_score <- app_joint_qdesn_phase122_forecast_scores(
      meta, loaded$artifacts, job$scenario_ids[[1L]], fixture, fit,
      "qhat", paste0(source_id, "_chain_forecast")
    )
    contract <- sum(fit_score$contract_crossing$n_crossing_pairs) +
      sum(forecast_score$contract_crossing$n_crossing_pairs)
    summary <- data.frame(
      worker_id = worker_id, mcmc_case_id = job$mcmc_case_id[[1L]],
      phase178_template_id = job$phase178_template_id[[1L]],
      case_id = job$case_id[[1L]], scenario_id = job$scenario_ids[[1L]],
      base_scenario_id = job$base_scenario_id[[1L]],
      dgp_replicate_id = job$dgp_replicate_id[[1L]],
      validation_partition = job$validation_partition[[1L]],
      fit_structure = job$fit_structure[[1L]],
      inference_method_id = job$inference_method_id[[1L]],
      chain_id = job$chain_id[[1L]], chain_seed = job$chain_seed[[1L]],
      n_iter = job$n_iter[[1L]], burn = job$burn[[1L]], thin = job$thin[[1L]],
      n_keep = nrow(draws), init_source = fit$init_source %||% "provided",
      draws_all_finite = all(is.finite(as.matrix(draws[, -1L, drop = FALSE]))),
      fit_truth_mae = mean(fit_score$scored$truth_abs_error),
      forecast_truth_mae = mean(forecast_score$scored$truth_abs_error),
      fit_check_loss_mean = mean(fit_score$scored$check_loss),
      forecast_check_loss_mean = mean(forecast_score$scored$check_loss),
      fit_crps_grid_mean = app_joint_qdesn_crps_grid_summary(fit_score$scored)$crps_grid_mean[[1L]],
      forecast_crps_grid_mean = app_joint_qdesn_crps_grid_summary(forecast_score$scored)$crps_grid_mean[[1L]],
      fit_raw_crossing_pairs = sum(fit_score$raw_crossing$n_crossing_pairs),
      forecast_raw_crossing_pairs = sum(forecast_score$raw_crossing$n_crossing_pairs),
      contract_crossing_pairs = contract,
      min_sigma = min(fit$sigma_draws), max_sigma = max(fit$sigma_draws),
      min_gamma = min(fit$gamma_draws), max_gamma = max(fit$gamma_draws),
      elapsed_seconds = as.numeric(checkpoint$metadata$elapsed_seconds[[1L]]),
      stringsAsFactors = FALSE
    )
    if (!summary$draws_all_finite[[1L]] || contract > 0L) {
      stop("Exact-M0 worker failed the finite/noncrossing contract.", call. = FALSE)
    }
    readme <- file.path(worker_dir, "README.md")
    writeLines(c(
      sprintf("# %s worker %d", source_id, worker_id), "",
      sprintf("- Candidate-replicate: `%s`", job$mcmc_case_id[[1L]]),
      sprintf("- Chain: %d", job$chain_id[[1L]]),
      sprintf("- Exact method: `%s`", job$inference_method_id[[1L]]),
      "- One chain per worker enables audited CPU-level parallelism.",
      "- Posterior draws are compressed CSV; no serialized R workspace is retained."
    ), readme, useBytes = TRUE)
    runtime <- summary[, c(
      "worker_id", "mcmc_case_id", "case_id", "chain_id", "chain_seed",
      "elapsed_seconds"
    ), drop = FALSE]
    paths <- c(
      checkpoint$paths,
      chain_summary = app_joint_qvp_write_csv(summary, file.path(worker_dir, "chain_summary.csv")),
      runtime = app_joint_qvp_write_csv(runtime, file.path(worker_dir, "runtime.csv")),
      provenance = app_joint_qvp_write_csv(app_joint_qvp_provenance_rows(), file.path(worker_dir, "provenance.csv")),
      README = normalizePath(readme, mustWork = TRUE)
    )
    app_joint_exqdesn_write_manifest(paths, worker_dir)
    if (!app_joint_exqdesn_phase172_worker_complete(worker_dir)) {
      stop("Exact-M0 worker manifest verification failed.", call. = FALSE)
    }
    stale <- c(
      file.path(worker_dir, "failure_receipt.csv"),
      if (!is.null(failure_dir) && nzchar(failure_dir)) {
        file.path(failure_dir, sprintf("worker_%04d.csv", worker_id))
      } else character()
    )
    if (any(file.exists(stale))) unlink(stale[file.exists(stale)], force = TRUE)
    list(worker_id = worker_id, status = "completed", worker_dir = worker_dir)
  }, error = function(e) {
    receipt <- data.frame(
      worker_id = worker_id, mcmc_case_id = job$mcmc_case_id[[1L]],
      case_id = job$case_id[[1L]], chain_id = job$chain_id[[1L]],
      message = conditionMessage(e),
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      stringsAsFactors = FALSE
    )
    app_joint_qvp_write_csv(receipt, file.path(worker_dir, "failure_receipt.csv"))
    if (!is.null(failure_dir) && nzchar(failure_dir)) {
      app_ensure_dir(failure_dir)
      app_joint_qvp_write_csv(
        receipt, file.path(failure_dir, sprintf("worker_%04d.csv", worker_id))
      )
    }
    stop(e)
  })
}

app_joint_exqdesn_phase178_m0_health <- function(freeze_dir, orchestration_dir, source_id) {
  freeze <- app_joint_exqdesn_phase178_load_m0_freeze(freeze_dir, source_id)
  complete <- vapply(
    freeze$plan$worker_output_dir,
    app_joint_exqdesn_phase172_worker_complete, logical(1L)
  )
  exits <- file.path(
    orchestration_dir, "exits", sprintf("worker_%04d.exit", freeze$plan$worker_id)
  )
  failed <- vapply(exits, function(path) {
    file.exists(path) && suppressWarnings(as.integer(readLines(path, warn = FALSE)[[1L]])) != 0L
  }, logical(1L))
  state <- ifelse(complete, "complete", ifelse(failed, "failed", "remaining"))
  plan <- freeze$plan; plan$state <- state
  by_case <- app_joint_qdesn_bind_rows(lapply(split(plan, plan$mcmc_case_id), function(x) {
    data.frame(
      mcmc_case_id = x$mcmc_case_id[[1L]], case_id = x$case_id[[1L]],
      phase178_template_id = x$phase178_template_id[[1L]],
      dgp_replicate_id = x$dgp_replicate_id[[1L]],
      planned = nrow(x), complete = sum(x$state == "complete"),
      failed = sum(x$state == "failed"), remaining = sum(x$state == "remaining"),
      stringsAsFactors = FALSE
    )
  }))
  list(
    summary = data.frame(
      stage = source_id, planned = nrow(plan), complete = sum(complete),
      failed = sum(failed & !complete), remaining = sum(!complete & !failed),
      percent_complete = 100 * mean(complete), stringsAsFactors = FALSE
    ),
    by_case = by_case, plan = plan
  )
}

app_joint_exqdesn_phase178_load_m0_fits <- function(jobs, fixture) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  expected <- seq_len(jobs$n_chains[[1L]])
  if (!identical(as.integer(jobs$chain_id), expected)) {
    stop("Exact-M0 case does not contain its complete frozen chain sequence.", call. = FALSE)
  }
  lapply(seq_len(nrow(jobs)), function(ii) {
    app_joint_exqdesn_phase157_read_fit(
      app_joint_exqdesn_phase172_checkpoint_dir(jobs$worker_output_dir[[ii]]),
      fixture$tau, jobs$chain_seed[[ii]], jobs$chain_id[[ii]]
    )
  })
}

app_joint_exqdesn_phase178_partition_stability <- function(
  fits, fixture, forecast_fixture, meta
) {
  n <- length(fits)
  if (n < 4L || n %% 2L != 0L) {
    stop("Exact-M0 functional stability requires an even chain count of at least four.", call. = FALSE)
  }
  half <- n / 2L
  partitions <- list(
    first_half_last_half = list(a = seq_len(half), b = half + seq_len(half)),
    odd_even = list(a = seq(1L, n, 2L), b = seq(2L, n, 2L))
  )
  rows <- lapply(names(partitions), function(id) {
    groups <- partitions[[id]]
    list(
      fit = app_joint_exqdesn_phase173_compare_qhat_groups(
        fits[groups$a], fits[groups$b], fixture$Z, fixture$tau, meta, id, "fit"
      ),
      forecast = app_joint_exqdesn_phase173_compare_qhat_groups(
        fits[groups$a], fits[groups$b], forecast_fixture$Z, fixture$tau,
        meta, id, "forecast"
      )
    )
  })
  flat <- unlist(rows, recursive = FALSE)
  list(
    detail = app_joint_qdesn_bind_rows(lapply(flat, `[[`, "detail")),
    summary = app_joint_qdesn_bind_rows(lapply(flat, `[[`, "summary"))
  )
}

app_joint_exqdesn_phase178_process_m0_case <- function(jobs, freeze) {
  jobs <- jobs[order(jobs$chain_id), , drop = FALSE]
  control <- freeze$controls[
    freeze$controls$phase178_template_id == jobs$phase178_template_id[[1L]], , drop = FALSE
  ]
  if (nrow(control) != 1L) stop("Could not resolve exact-M0 case control.", call. = FALSE)
  loaded <- app_joint_exqdesn_phase178_load_candidate_fixture(
    jobs[1L, , drop = FALSE], freeze$config$fixture_dir[[1L]]
  )
  fixture <- loaded$fixture
  forecast_fixture <- app_joint_exqdesn_phase173_forecast_fixture(
    loaded$artifacts, fixture$scenario_id, fixture
  )
  fits <- app_joint_exqdesn_phase178_load_m0_fits(jobs, fixture)
  meta <- app_joint_exqdesn_phase172_meta(jobs[1L, , drop = FALSE], control)
  pooled <- app_joint_qdesn_phase122_pool_mcmc_chains(
    fits, fixture$Z, length(fixture$tau), ncol(fixture$Z), fixture$tau
  )
  scored <- app_joint_exqdesn_phase173_score_fit(
    pooled, fixture, loaded$artifacts, meta, "post_m0_case_specific"
  )
  diagnostics <- app_joint_exqdesn_phase173_parameter_diagnostics(fits, fixture, meta)
  chain_distance <- app_joint_qvp_chain_to_pooled_summary(
    fits, pooled, fixture$Z, meta$case_id[[1L]], "post_m0_case_specific",
    fixture$scenario_id, length(fixture$y), ncol(fixture$Z),
    length(fixture$tau)
  )
  for (field in setdiff(names(meta), names(chain_distance))) {
    chain_distance[[field]] <- meta[[field]][[1L]]
  }
  forecast_hit <- app_joint_qdesn_hit_rate_summary(scored$forecast$scored)
  partitions <- app_joint_exqdesn_phase178_partition_stability(
    fits, fixture, forecast_fixture, meta
  )
  chain_summary <- app_joint_qdesn_bind_rows(lapply(
    jobs$worker_output_dir,
    function(path) app_read_csv(file.path(path, "chain_summary.csv"))
  ))
  sensitivity <- app_joint_qdesn_bind_rows(lapply(
    c("mean", "median", "trimmed_mean"), function(type) {
      summary_fit <- app_joint_exqdesn_phase173_summary_fit(fits, fixture, type)
      x <- app_joint_exqdesn_phase173_score_fit(
        summary_fit, fixture, loaded$artifacts, meta,
        paste0("post_m0_", type)
      )
      cbind(
        jobs[1L, c(
          "mcmc_case_id", "phase178_template_id", "case_id",
          "base_scenario_id", "dgp_replicate_id", "validation_partition"
        ), drop = FALSE],
        data.frame(summary_type = type, stringsAsFactors = FALSE), x$metrics
      )
    }
  ))
  partition_forecast <- partitions$summary[partitions$summary$window == "forecast", , drop = FALSE]
  implementation_pass <- all(chain_summary$draws_all_finite) &&
    sum(scored$fit$contract_crossing$n_crossing_pairs) == 0L &&
    sum(scored$forecast$contract_crossing$n_crossing_pairs) == 0L
  summary <- cbind(
    jobs[1L, c(
      "mcmc_case_id", "phase178_template_id", "case_id", "base_scenario_id",
      "dgp_replicate_id", "dgp_seed", "validation_partition", "fit_structure",
      "variant_id", "candidate_role", "design_role", "design_class", "tau0",
      "zeta2", "alpha_prior_sd", "inference_method_id"
    ), drop = FALSE],
    data.frame(
      mcmc_n_chains = length(fits), mcmc_n_iter = jobs$n_iter[[1L]],
      mcmc_burn = jobs$burn[[1L]], mcmc_thin = jobs$thin[[1L]],
      mcmc_n_keep_total = nrow(pooled$beta_draws),
      fit_truth_mae = scored$metrics$fit_truth_mae,
      forecast_truth_mae = scored$metrics$forecast_truth_mae,
      fit_check_loss_mean = scored$metrics$fit_check_loss_mean,
      forecast_check_loss_mean = scored$metrics$forecast_check_loss_mean,
      fit_crps_grid_mean = scored$metrics$fit_crps_grid_mean,
      forecast_crps_grid_mean = scored$metrics$forecast_crps_grid_mean,
      forecast_mean_abs_hit_rate_error = mean(forecast_hit$abs_hit_rate_error),
      forecast_max_abs_hit_rate_error = max(forecast_hit$abs_hit_rate_error),
      fit_raw_crossing_pairs = sum(scored$fit$raw_crossing$n_crossing_pairs),
      forecast_raw_crossing_pairs = sum(scored$forecast$raw_crossing$n_crossing_pairs),
      fit_contract_crossing_pairs = sum(scored$fit$contract_crossing$n_crossing_pairs),
      forecast_contract_crossing_pairs = sum(scored$forecast$contract_crossing$n_crossing_pairs),
      max_rank_rhat = max(diagnostics$rank_rhat, na.rm = TRUE),
      max_folded_rhat = max(diagnostics$folded_rhat, na.rm = TRUE),
      min_bulk_ess = min(diagnostics$bulk_ess, na.rm = TRUE),
      min_tail_ess = min(diagnostics$tail_ess, na.rm = TRUE),
      max_forecast_partition_q99 = max(
        partition_forecast$q99_standardized_qhat_delta, na.rm = TRUE
      ),
      min_forecast_partition_overlap = min(
        partition_forecast$q01_central90_overlap_fraction, na.rm = TRUE
      ),
      elapsed_seconds_total = sum(chain_summary$elapsed_seconds),
      implementation_status = if (implementation_pass) "pass" else "fail",
      scalar_mixing_status = if (
        max(diagnostics$rank_rhat, na.rm = TRUE) <= 1.05 &&
          min(diagnostics$bulk_ess, na.rm = TRUE) >= 400
      ) "pass" else "review",
      exact_m0_rank = TRUE, stringsAsFactors = FALSE
    )
  )
  list(
    summary = summary, diagnostics = diagnostics,
    partition_detail = partitions$detail, partition_summary = partitions$summary,
    sensitivity = sensitivity, chain_summary = chain_summary,
    chain_distance = chain_distance,
    fit_raw = scored$fit$raw, fit = scored$fit$scored,
    forecast_raw = scored$forecast$raw, forecast = scored$forecast$scored,
    fit_adjustment = scored$fit$adjustment,
    forecast_adjustment = scored$forecast$adjustment,
    raw_crossing = app_joint_qdesn_bind_rows(list(
      scored$fit$raw_crossing, scored$forecast$raw_crossing
    )),
    crossing = app_joint_qdesn_bind_rows(list(
      scored$fit$contract_crossing, scored$forecast$contract_crossing
    ))
  )
}

app_joint_exqdesn_phase178_m0_results <- function(freeze) {
  groups <- split(freeze$plan, freeze$plan$mcmc_case_id)
  results <- lapply(groups, app_joint_exqdesn_phase178_process_m0_case, freeze = freeze)
  bind <- function(name) app_joint_qdesn_bind_rows(lapply(results, `[[`, name))
  list(
    summary = bind("summary"), diagnostics = bind("diagnostics"),
    partition_detail = bind("partition_detail"),
    partition_summary = bind("partition_summary"), sensitivity = bind("sensitivity"),
    chain_summary = bind("chain_summary"), fit_raw = bind("fit_raw"), fit = bind("fit"),
    chain_distance = bind("chain_distance"),
    forecast_raw = bind("forecast_raw"), forecast = bind("forecast"),
    fit_adjustment = bind("fit_adjustment"),
    forecast_adjustment = bind("forecast_adjustment"),
    raw_crossing = bind("raw_crossing"), crossing = bind("crossing")
  )
}

app_joint_exqdesn_phase178_rank_m0_candidates <- function(
  summary, policy = app_joint_exqdesn_phase178_load_compute_policy()
) {
  parity <- summary[summary$variant_id == "parity", c(
    "case_id", "dgp_replicate_id", "forecast_truth_mae", "fit_truth_mae",
    "forecast_check_loss_mean", "forecast_crps_grid_mean"
  ), drop = FALSE]
  names(parity)[-(1:2)] <- paste0("parity_", names(parity)[-(1:2)])
  paired <- merge(summary, parity, by = c("case_id", "dgp_replicate_id"),
                  all.x = TRUE, sort = FALSE)
  for (metric in c(
    "forecast_truth_mae", "fit_truth_mae", "forecast_check_loss_mean",
    "forecast_crps_grid_mean"
  )) {
    paired[[paste0(metric, "_ratio_vs_parity")]] <- paired[[metric]] /
      paired[[paste0("parity_", metric)]]
  }
  group <- interaction(
    paired$case_id, paired$phase178_template_id, drop = TRUE, lex.order = TRUE
  )
  aggregate <- app_joint_qdesn_bind_rows(lapply(split(paired, group), function(x) {
    data.frame(
      case_id = x$case_id[[1L]], base_scenario_id = x$base_scenario_id[[1L]],
      fit_structure = x$fit_structure[[1L]],
      phase178_template_id = x$phase178_template_id[[1L]],
      variant_id = x$variant_id[[1L]], candidate_role = x$candidate_role[[1L]],
      design_role = x$design_role[[1L]], tau0 = x$tau0[[1L]],
      alpha_prior_sd = x$alpha_prior_sd[[1L]], ranking_replicates = nrow(x),
      implementation_pass_fraction = mean(x$implementation_status == "pass"),
      median_forecast_truth_mae = stats::median(x$forecast_truth_mae),
      median_fit_truth_mae = stats::median(x$fit_truth_mae),
      median_forecast_check_loss = stats::median(x$forecast_check_loss_mean),
      median_forecast_crps_grid = stats::median(x$forecast_crps_grid_mean),
      median_forecast_mae_ratio_vs_parity = stats::median(
        x$forecast_truth_mae_ratio_vs_parity
      ),
      forecast_win_fraction_vs_parity = mean(
        x$forecast_truth_mae < x$parity_forecast_truth_mae
      ),
      median_fit_mae_ratio_vs_parity = stats::median(
        x$fit_truth_mae_ratio_vs_parity
      ),
      median_check_loss_ratio_vs_parity = stats::median(
        x$forecast_check_loss_mean_ratio_vs_parity
      ),
      median_crps_ratio_vs_parity = stats::median(
        x$forecast_crps_grid_mean_ratio_vs_parity
      ),
      max_forecast_partition_q99 = max(x$max_forecast_partition_q99),
      min_forecast_partition_overlap = min(x$min_forecast_partition_overlap),
      scalar_mixing_review_fraction = mean(x$scalar_mixing_status == "review"),
      exact_m0_rank = all(x$exact_m0_rank), stringsAsFactors = FALSE
    )
  }))
  aggregate$guardrail_pass <- with(aggregate,
    implementation_pass_fraction == 1 & exact_m0_rank &
      median_check_loss_ratio_vs_parity <= policy$m0_check_loss_ratio_ceiling[[1L]] &
      median_crps_ratio_vs_parity <= policy$m0_crps_ratio_ceiling[[1L]] &
      median_fit_mae_ratio_vs_parity <= policy$m0_fit_mae_ratio_ceiling[[1L]])
  decisions <- app_joint_qdesn_bind_rows(lapply(split(aggregate, aggregate$case_id), function(x) {
    eligible <- x[x$guardrail_pass, , drop = FALSE]
    parity <- x[x$variant_id == "parity", , drop = FALSE]
    if (!nrow(eligible)) eligible <- parity
    winner <- eligible[order(
      eligible$median_forecast_truth_mae,
      eligible$median_forecast_check_loss,
      eligible$phase178_template_id
    ), , drop = FALSE][1L, , drop = FALSE]
    data.frame(
      case_id = winner$case_id, base_scenario_id = winner$base_scenario_id,
      fit_structure = winner$fit_structure,
      selected_template_id = winner$phase178_template_id,
      selected_variant_id = winner$variant_id,
      parity_template_id = parity$phase178_template_id[[1L]],
      selected_is_parity = winner$variant_id == "parity",
      selected_median_forecast_truth_mae = winner$median_forecast_truth_mae,
      selected_forecast_mae_ratio_vs_parity = winner$median_forecast_mae_ratio_vs_parity,
      selected_forecast_win_fraction_vs_parity = winner$forecast_win_fraction_vs_parity,
      selected_scalar_mixing_review_fraction = winner$scalar_mixing_review_fraction,
      decision_status = if (winner$guardrail_pass) "pass" else "review",
      next_action = "protected_confirmation_against_same_partition_parity",
      stringsAsFactors = FALSE
    )
  }))
  list(paired = paired, aggregate = aggregate, decisions = decisions)
}

app_joint_exqdesn_phase178_prepare_m0_ranking <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), n_vb_cores = 8L,
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  source_dir <- file.path(dirs$phase178, "vb_feasibility_audit")
  source_check <- app_joint_exqdesn_verify_manifest(source_dir, "phase178_vb_audit")
  if (any(source_check$status != "pass")) stop("Phase178 VB audit verification failed.", call. = FALSE)
  templates <- app_read_csv(file.path(source_dir, "survivor_templates.csv"))
  dgp <- app_read_csv(file.path(dirs$phase178_freeze, "protected_dgp_registry.csv"))
  app_joint_exqdesn_phase178_prepare_m0_freeze(
    candidate_templates = templates, dgp_registry = dgp,
    partition = "m0_ranking", source_dir = source_dir,
    fixture_dir = dirs$phase178_fixtures, out_dir = dirs$phase178_m0_freeze,
    result_dir = dirs$phase178_m0,
    phase_id = "phase178_post_m0_exact_ranking_freeze",
    seed_base = 178500000L, n_vb_cores = n_vb_cores, force = force
  )
}

app_joint_exqdesn_phase178_finalize_m0_ranking <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  source_id <- "phase178_post_m0_exact_ranking_freeze"
  health <- app_joint_exqdesn_phase178_m0_health(
    dirs$phase178_m0_freeze, dirs$phase178_m0_orchestration, source_id
  )
  if (health$summary$failed[[1L]] > 0L || health$summary$remaining[[1L]] > 0L) {
    stop("Phase178 exact-M0 ranking is incomplete or has worker failures.", call. = FALSE)
  }
  freeze <- app_joint_exqdesn_phase178_load_m0_freeze(dirs$phase178_m0_freeze, source_id)
  result <- app_joint_exqdesn_phase178_m0_results(freeze)
  policy <- app_joint_exqdesn_phase178_load_compute_policy()
  ranked <- app_joint_exqdesn_phase178_rank_m0_candidates(result$summary, policy)
  templates <- freeze$controls
  selected <- templates[
    match(ranked$decisions$selected_template_id, templates$phase178_template_id), , drop = FALSE
  ]
  parity <- templates[
    match(ranked$decisions$parity_template_id, templates$phase178_template_id), , drop = FALSE
  ]
  confirmation <- app_joint_qdesn_bind_rows(list(selected, parity))
  confirmation <- confirmation[!duplicated(confirmation$phase178_template_id), , drop = FALSE]
  confirmation$confirmation_role <- ifelse(
    confirmation$phase178_template_id %in%
      ranked$decisions$selected_template_id[!ranked$decisions$selected_is_parity],
    "selected_challenger", "parity"
  )
  if (any(is.na(selected$phase178_template_id)) ||
      any(!app_as_bool_vec(selected$exact_m0_rank_required)) ||
      any(app_as_bool_vec(selected$article_fixture_selection_allowed))) {
    stop("Phase178 winner freeze violates exact-M0 or protected-data policy.", call. = FALSE)
  }
  assessment <- data.frame(
    phase_id = "phase178_post_m0_exact_ranking_audit",
    gate_status = if (all(ranked$decisions$decision_status == "pass")) "pass" else "review",
    completed_workers = health$summary$complete[[1L]],
    failed_workers = health$summary$failed[[1L]],
    ranked_candidate_replicates = nrow(result$summary),
    target_cells = nrow(ranked$decisions), selected_templates = nrow(selected),
    selected_nonparity = sum(!ranked$decisions$selected_is_parity),
    pre_m0_rank_authority = FALSE, exact_m0_rank = TRUE,
    article_fixture_used = FALSE, global_specification_selected = FALSE,
    recommendation = "run_phase179_protected_selected_vs_parity_confirmation",
    stringsAsFactors = FALSE
  )
  final_dir <- dirs$phase178_m0_audit
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(final_dir, "phase178_m0_audit")
    if (all(check$status == "pass")) {
      return(list(out_dir = final_dir, assessment = app_read_csv(file.path(final_dir, "assessment.csv"))))
    }
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid()); app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  worker_manifests <- unique(file.path(
    freeze$plan$worker_output_dir, "artifact_manifest.csv"
  ))
  worker_verification <- data.frame(
    worker_output_dir = dirname(worker_manifests),
    artifact_manifest_sha256 = vapply(worker_manifests, app_sha256_file, character(1L)),
    status = "pass", stringsAsFactors = FALSE
  )
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase178 protected exact-M0 ranking audit", "",
    "Candidates were ranked separately within each scenario/readout cell on fresh protected replicates.",
    "The article fixture and pre-M0 MCMC ranks had no selection authority.",
    "Scalar mixing is reported as review evidence; finite, stable quantile-grid performance is primary.",
    "Selected challengers now require a paired protected confirmation against parity."
  ), readme, useBytes = TRUE)
  paths <- c(
    freeze_manifest_verification = write(freeze$verification, "freeze_manifest_verification.csv"),
    health_summary = write(health$summary, "health_summary.csv"),
    health_by_case = write(health$by_case, "health_by_case.csv"),
    worker_manifest_inventory = write(worker_verification, "worker_manifest_inventory.csv"),
    case_replicate_summary = write(result$summary, "case_replicate_summary.csv"),
    paired_candidate_summary = write(ranked$paired, "paired_candidate_summary.csv"),
    candidate_aggregate = write(ranked$aggregate, "candidate_aggregate.csv"),
    selection_decision = write(ranked$decisions, "selection_decision.csv"),
    selected_templates = write(selected, "selected_templates.csv"),
    confirmation_templates = write(confirmation, "confirmation_templates.csv"),
    parameter_diagnostics = write(result$diagnostics, "parameter_diagnostics.csv"),
    partition_stability = write(result$partition_summary, "partition_stability.csv"),
    posterior_summary_sensitivity = write(result$sensitivity, "posterior_summary_sensitivity.csv"),
    chain_to_pooled_distance = write(result$chain_distance, "chain_to_pooled_distance.csv"),
    raw_crossing_summary = write(result$raw_crossing, "raw_crossing_summary.csv"),
    contract_crossing_summary = write(result$crossing, "contract_crossing_summary.csv"),
    chain_summary = write(result$chain_summary, "chain_summary.csv"),
    fit_monotone_adjustment = write(result$fit_adjustment, "fit_monotone_adjustment.csv"),
    forecast_monotone_adjustment = write(result$forecast_adjustment, "forecast_monotone_adjustment.csv"),
    assessment = write(assessment, "assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase178 M0 audit.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase178 M0 audit.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase178_m0_audit")
  if (any(check$status != "pass")) stop("Phase178 M0 audit manifest failed.", call. = FALSE)
  list(out_dir = final_dir, assessment = assessment, decisions = ranked$decisions)
}

app_joint_exqdesn_phase179_prepare_protected_confirmation <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), n_vb_cores = 8L,
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  source_dir <- dirs$phase178_m0_audit
  check <- app_joint_exqdesn_verify_manifest(source_dir, "phase178_m0_audit")
  if (any(check$status != "pass")) stop("Phase178 ranking audit verification failed.", call. = FALSE)
  templates <- app_read_csv(file.path(source_dir, "confirmation_templates.csv"))
  dgp <- app_read_csv(file.path(dirs$phase178_freeze, "protected_dgp_registry.csv"))
  app_joint_exqdesn_phase178_prepare_m0_freeze(
    candidate_templates = templates, dgp_registry = dgp,
    partition = "confirmation", source_dir = source_dir,
    fixture_dir = dirs$phase178_fixtures, out_dir = dirs$phase179_freeze,
    result_dir = dirs$phase179,
    phase_id = "phase179_protected_winner_confirmation_freeze",
    seed_base = 179000000L, n_vb_cores = n_vb_cores, force = force
  )
}

app_joint_exqdesn_phase179_assess_protected_confirmation <- function(
  summary, ranking_decisions,
  policy = app_joint_exqdesn_phase178_load_compute_policy()
) {
  rows <- lapply(seq_len(nrow(ranking_decisions)), function(ii) {
    decision <- ranking_decisions[ii, , drop = FALSE]
    block <- summary[summary$case_id == decision$case_id[[1L]], , drop = FALSE]
    selected <- block[
      block$phase178_template_id == decision$selected_template_id[[1L]], , drop = FALSE
    ]
    parity <- block[
      block$phase178_template_id == decision$parity_template_id[[1L]], , drop = FALSE
    ]
    if (!nrow(selected) || !nrow(parity)) {
      stop("Phase179 protected confirmation is missing selected or parity rows.", call. = FALSE)
    }
    paired <- merge(
      selected, parity[, c(
        "dgp_replicate_id", "forecast_truth_mae", "fit_truth_mae",
        "forecast_check_loss_mean", "forecast_crps_grid_mean"
      ), drop = FALSE],
      by = "dgp_replicate_id", suffixes = c("", "_parity"), sort = FALSE
    )
    is_parity <- isTRUE(decision$selected_is_parity[[1L]])
    implementation <- all(paired$implementation_status == "pass")
    functional <- all(
      paired$max_forecast_partition_q99 <= policy$m0_functional_q99_ceiling[[1L]] &
        paired$min_forecast_partition_overlap >= policy$m0_functional_overlap_floor[[1L]]
    )
    forecast_ratio <- stats::median(
      paired$forecast_truth_mae / paired$forecast_truth_mae_parity
    )
    fit_ratio <- stats::median(paired$fit_truth_mae / paired$fit_truth_mae_parity)
    check_ratio <- stats::median(
      paired$forecast_check_loss_mean / paired$forecast_check_loss_mean_parity
    )
    crps_ratio <- stats::median(
      paired$forecast_crps_grid_mean / paired$forecast_crps_grid_mean_parity
    )
    win_fraction <- mean(
      paired$forecast_truth_mae <= paired$forecast_truth_mae_parity
    )
    performance <- is_parity || (
      forecast_ratio < 1 &&
        win_fraction >= policy$m0_confirmation_win_fraction_floor[[1L]] &&
        fit_ratio <= policy$m0_fit_mae_ratio_ceiling[[1L]] &&
        check_ratio <= policy$m0_check_loss_ratio_ceiling[[1L]] &&
        crps_ratio <= policy$m0_crps_ratio_ceiling[[1L]]
    )
    qualified <- implementation && functional && performance && !is_parity
    data.frame(
      case_id = decision$case_id[[1L]],
      base_scenario_id = decision$base_scenario_id[[1L]],
      fit_structure = decision$fit_structure[[1L]],
      selected_template_id = decision$selected_template_id[[1L]],
      parity_template_id = decision$parity_template_id[[1L]],
      selected_is_parity = is_parity,
      confirmation_replicates = nrow(paired),
      implementation_gate = if (implementation) "pass" else "fail",
      functional_gate = if (functional) "pass" else "review",
      performance_gate = if (performance) "pass" else "review",
      median_forecast_mae_ratio_vs_parity = forecast_ratio,
      forecast_win_fraction_vs_parity = win_fraction,
      median_fit_mae_ratio_vs_parity = fit_ratio,
      median_check_loss_ratio_vs_parity = check_ratio,
      median_crps_ratio_vs_parity = crps_ratio,
      scalar_mixing_review_fraction = mean(paired$scalar_mixing_status == "review"),
      article_confirmation_qualified = qualified,
      gate_status = if (!implementation) "fail" else if (qualified) "pass" else "review",
      next_action = if (qualified) {
        "run_frozen_article_fixture_exact_M0_confirmation"
      } else {
        "retain_phase174_authoritative_row"
      },
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase179_finalize_protected_confirmation <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  source_id <- "phase179_protected_winner_confirmation_freeze"
  health <- app_joint_exqdesn_phase178_m0_health(
    dirs$phase179_freeze, dirs$phase179_orchestration, source_id
  )
  if (health$summary$failed[[1L]] > 0L || health$summary$remaining[[1L]] > 0L) {
    stop("Phase179 protected confirmation is incomplete or has failures.", call. = FALSE)
  }
  freeze <- app_joint_exqdesn_phase178_load_m0_freeze(dirs$phase179_freeze, source_id)
  result <- app_joint_exqdesn_phase178_m0_results(freeze)
  ranking <- app_read_csv(file.path(dirs$phase178_m0_audit, "selection_decision.csv"))
  decision <- app_joint_exqdesn_phase179_assess_protected_confirmation(
    result$summary, ranking
  )
  qualified <- freeze$controls[
    match(
      decision$selected_template_id[decision$article_confirmation_qualified],
      freeze$controls$phase178_template_id
    ), , drop = FALSE
  ]
  qualified <- qualified[!is.na(qualified$phase178_template_id), , drop = FALSE]
  assessment <- data.frame(
    phase_id = "phase179_protected_winner_confirmation_audit",
    gate_status = if (any(decision$gate_status == "fail")) "fail" else if (
      any(decision$article_confirmation_qualified)
    ) "pass" else "review",
    completed_workers = health$summary$complete[[1L]],
    candidate_replicates = nrow(result$summary),
    target_cells = nrow(decision),
    qualified_article_confirmations = nrow(qualified),
    retained_phase174_cells = sum(!decision$article_confirmation_qualified),
    exact_m0 = TRUE, protected_data_only = TRUE,
    recommendation = if (nrow(qualified)) {
      "freeze_and_run_phase179_article_fixture_confirmations"
    } else {
      "skip_new_article_sampling_and_build_phase180_no_change_handoff"
    }, stringsAsFactors = FALSE
  )
  final_dir <- dirs$phase179_audit
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(final_dir, "phase179_protected_audit")
    if (all(check$status == "pass")) {
      return(list(out_dir = final_dir, assessment = app_read_csv(file.path(final_dir, "assessment.csv"))))
    }
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid()); app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase179 protected winner confirmation", "",
    "Each case-specific challenger was compared with its parity specification on the same fresh confirmation replicates.",
    "Performance and posterior-quantile functional stability gate article-fixture confirmation.",
    "Review-level scalar gamma/sigma mixing is retained as evidence but does not independently block a stable metric gain."
  ), readme, useBytes = TRUE)
  paths <- c(
    freeze_manifest_verification = write(freeze$verification, "freeze_manifest_verification.csv"),
    health_summary = write(health$summary, "health_summary.csv"),
    case_replicate_summary = write(result$summary, "case_replicate_summary.csv"),
    confirmation_decision = write(decision, "confirmation_decision.csv"),
    qualified_article_templates = write(qualified, "qualified_article_templates.csv"),
    parameter_diagnostics = write(result$diagnostics, "parameter_diagnostics.csv"),
    partition_stability = write(result$partition_summary, "partition_stability.csv"),
    posterior_summary_sensitivity = write(result$sensitivity, "posterior_summary_sensitivity.csv"),
    chain_to_pooled_distance = write(result$chain_distance, "chain_to_pooled_distance.csv"),
    raw_crossing_summary = write(result$raw_crossing, "raw_crossing_summary.csv"),
    contract_crossing_summary = write(result$crossing, "contract_crossing_summary.csv"),
    chain_summary = write(result$chain_summary, "chain_summary.csv"),
    fit_monotone_adjustment = write(result$fit_adjustment, "fit_monotone_adjustment.csv"),
    forecast_monotone_adjustment = write(result$forecast_adjustment, "forecast_monotone_adjustment.csv"),
    assessment = write(assessment, "assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase179 audit.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase179 audit.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase179_protected_audit")
  if (any(check$status != "pass")) stop("Phase179 audit manifest failed.", call. = FALSE)
  list(out_dir = final_dir, assessment = assessment, decision = decision)
}

app_joint_exqdesn_phase179_article_registry <- function(base_scenario_ids) {
  registry <- app_joint_qdesn_load_simulation_registry()
  out <- registry[match(unique(base_scenario_ids), registry$scenario_id), , drop = FALSE]
  if (any(is.na(out$scenario_id))) stop("Article registry is missing a qualified scenario.", call. = FALSE)
  out$base_scenario_id <- out$scenario_id
  out$validation_partition <- "article_evaluation"
  out$dgp_replicate_id <- "article_r001"
  out$base_seed <- out$seed
  out$seed_role <- "frozen_article_evaluation_seed"
  out$registry_version <- "joint_exqdesn_phase179_frozen_article_evaluation_v1"
  out$notes <- paste(
    out$notes,
    "Frozen article realization; used only after protected selection was complete."
  )
  app_joint_qdesn_validate_simulation_registry(out)
  out
}

app_joint_exqdesn_phase179_prepare_article_confirmation <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), n_vb_cores = 8L,
  force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  source_dir <- dirs$phase179_audit
  check <- app_joint_exqdesn_verify_manifest(source_dir, "phase179_protected_audit")
  if (any(check$status != "pass")) stop("Phase179 protected audit verification failed.", call. = FALSE)
  templates <- app_read_csv(file.path(source_dir, "qualified_article_templates.csv"))
  if (!nrow(templates)) {
    return(list(
      out_dir = NA_character_, plan = data.frame(), reused = TRUE,
      status = "no_qualified_replacements"
    ))
  }
  dgp <- app_joint_exqdesn_phase179_article_registry(templates$base_scenario_id)
  app_joint_exqdesn_phase178_materialize_fixture_shards(
    dgp, dirs$phase179_article_fixtures, force = force
  )
  app_joint_exqdesn_phase178_prepare_m0_freeze(
    candidate_templates = templates, dgp_registry = dgp,
    partition = "article_evaluation", source_dir = source_dir,
    fixture_dir = dirs$phase179_article_fixtures,
    out_dir = dirs$phase179_article_freeze,
    result_dir = dirs$phase179_article,
    phase_id = "phase179_frozen_article_fixture_exact_M0_freeze",
    seed_base = 179500000L, n_vb_cores = n_vb_cores, force = force
  )
}

app_joint_exqdesn_phase179_article_decision <- function(
  summary, phase174,
  policy = app_joint_exqdesn_phase178_load_compute_policy()
) {
  rows <- lapply(seq_len(nrow(summary)), function(ii) {
    current <- summary[ii, , drop = FALSE]
    historical <- phase174[phase174$case_id == current$case_id[[1L]], , drop = FALSE]
    if (nrow(historical) != 1L) stop("Article confirmation lacks one Phase174 reference row.", call. = FALSE)
    forecast_ratio <- current$forecast_truth_mae[[1L]] /
      historical$mcmc_forecast_truth_mae[[1L]]
    fit_ratio <- current$fit_truth_mae[[1L]] / historical$mcmc_fit_truth_mae[[1L]]
    check_ratio <- current$forecast_check_loss_mean[[1L]] /
      historical$mcmc_forecast_check_loss_mean[[1L]]
    crps_ratio <- current$forecast_crps_grid_mean[[1L]] /
      historical$mcmc_forecast_crps_grid[[1L]]
    implementation <- current$implementation_status[[1L]] == "pass"
    functional <- current$max_forecast_partition_q99[[1L]] <=
      policy$m0_functional_q99_ceiling[[1L]] &&
      current$min_forecast_partition_overlap[[1L]] >=
        policy$m0_functional_overlap_floor[[1L]]
    performance <- forecast_ratio < 1 &&
      fit_ratio <= policy$m0_fit_mae_ratio_ceiling[[1L]] &&
      check_ratio <= policy$m0_check_loss_ratio_ceiling[[1L]] &&
      crps_ratio <= policy$m0_crps_ratio_ceiling[[1L]]
    promote <- implementation && functional && performance
    data.frame(
      case_id = current$case_id[[1L]],
      base_scenario_id = current$base_scenario_id[[1L]],
      fit_structure = current$fit_structure[[1L]],
      phase178_template_id = current$phase178_template_id[[1L]],
      historical_forecast_truth_mae = historical$mcmc_forecast_truth_mae[[1L]],
      candidate_forecast_truth_mae = current$forecast_truth_mae[[1L]],
      forecast_mae_ratio = forecast_ratio,
      historical_fit_truth_mae = historical$mcmc_fit_truth_mae[[1L]],
      candidate_fit_truth_mae = current$fit_truth_mae[[1L]],
      fit_mae_ratio = fit_ratio, check_loss_ratio = check_ratio,
      crps_grid_ratio = crps_ratio,
      scalar_mixing_status = current$scalar_mixing_status[[1L]],
      implementation_gate = if (implementation) "pass" else "fail",
      functional_gate = if (functional) "pass" else "review",
      performance_gate = if (performance) "pass" else "review",
      promotion_action = if (promote) {
        "promote_post_m0_case_specific_replacement"
      } else {
        "retain_phase174_authoritative_row"
      },
      gate_status = if (!implementation) "fail" else if (promote) "pass" else "review",
      mixing_exception_applied = promote && current$scalar_mixing_status[[1L]] == "review",
      stringsAsFactors = FALSE
    )
  })
  app_joint_qdesn_bind_rows(rows)
}

app_joint_exqdesn_phase179_finalize_article_confirmation <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  source_id <- "phase179_frozen_article_fixture_exact_M0_freeze"
  if (!file.exists(file.path(dirs$phase179_article_freeze, "artifact_manifest.csv"))) {
    qualified_path <- file.path(dirs$phase179_audit, "qualified_article_templates.csv")
    if (file.exists(qualified_path) && nrow(app_read_csv(qualified_path)) == 0L) {
      return(list(out_dir = NA_character_, assessment = data.frame(
        gate_status = "pass", qualified_replacements = 0L,
        recommendation = "build_phase180_no_change_handoff",
        stringsAsFactors = FALSE
      )))
    }
    stop("Phase179 article confirmation freeze does not exist.", call. = FALSE)
  }
  health <- app_joint_exqdesn_phase178_m0_health(
    dirs$phase179_article_freeze, dirs$phase179_article_orchestration, source_id
  )
  if (health$summary$failed[[1L]] > 0L || health$summary$remaining[[1L]] > 0L) {
    stop("Phase179 article confirmation is incomplete or has failures.", call. = FALSE)
  }
  freeze <- app_joint_exqdesn_phase178_load_m0_freeze(
    dirs$phase179_article_freeze, source_id
  )
  result <- app_joint_exqdesn_phase178_m0_results(freeze)
  phase174 <- app_read_csv(file.path(dirs$phase174, "final_mcmc_case_summary.csv"))
  decision <- app_joint_exqdesn_phase179_article_decision(result$summary, phase174)
  replacement <- result$summary[
    result$summary$case_id %in%
      decision$case_id[decision$promotion_action == "promote_post_m0_case_specific_replacement"],
    , drop = FALSE
  ]
  assessment <- data.frame(
    phase_id = "phase179_article_fixture_exact_M0_audit",
    gate_status = if (any(decision$gate_status == "fail")) "fail" else "pass",
    completed_workers = health$summary$complete[[1L]],
    evaluated_cells = nrow(decision), qualified_replacements = nrow(replacement),
    mixing_review_promotions = sum(decision$mixing_exception_applied),
    exact_m0 = TRUE, selection_completed_before_article_fixture = TRUE,
    recommendation = "build_phase180_recovery_packet_and_integration_handoff",
    stringsAsFactors = FALSE
  )
  final_dir <- dirs$phase179_article_audit
  if (!force && file.exists(file.path(final_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(final_dir, "phase179_article_audit")
    if (all(check$status == "pass")) {
      return(list(out_dir = final_dir, assessment = app_read_csv(file.path(final_dir, "assessment.csv"))))
    }
  }
  tmp <- paste0(final_dir, ".tmp.", Sys.getpid()); app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase179 frozen article-fixture exact-M0 confirmation", "",
    "Only candidates selected and confirmed on protected replicates entered this evaluation.",
    "A replacement requires better canonical posterior-mean forecast MAE and finite, stable quantile-grid behavior.",
    "Review-level scalar mixing is disclosed and may be accepted when those functional gates pass."
  ), readme, useBytes = TRUE)
  paths <- c(
    freeze_manifest_verification = write(freeze$verification, "freeze_manifest_verification.csv"),
    health_summary = write(health$summary, "health_summary.csv"),
    article_case_summary = write(result$summary, "article_case_summary.csv"),
    article_promotion_decision = write(decision, "article_promotion_decision.csv"),
    qualified_replacements = write(replacement, "qualified_replacements.csv"),
    parameter_diagnostics = write(result$diagnostics, "parameter_diagnostics.csv"),
    partition_stability = write(result$partition_summary, "partition_stability.csv"),
    posterior_summary_sensitivity = write(result$sensitivity, "posterior_summary_sensitivity.csv"),
    chain_to_pooled_distance = write(result$chain_distance, "chain_to_pooled_distance.csv"),
    raw_crossing_summary = write(result$raw_crossing, "raw_crossing_summary.csv"),
    contract_crossing_summary = write(result$crossing, "contract_crossing_summary.csv"),
    chain_summary = write(result$chain_summary, "chain_summary.csv"),
    fit_monotone_adjustment = write(result$fit_adjustment, "fit_monotone_adjustment.csv"),
    forecast_monotone_adjustment = write(result$forecast_adjustment, "forecast_monotone_adjustment.csv"),
    assessment = write(assessment, "assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(final_dir)) {
    quarantine <- paste0(final_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(final_dir, quarantine)) stop("Could not quarantine Phase179 article audit.", call. = FALSE)
  }
  if (!file.rename(tmp, final_dir)) stop("Could not publish Phase179 article audit.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(final_dir, "phase179_article_audit")
  if (any(check$status != "pass")) stop("Phase179 article audit manifest failed.", call. = FALSE)
  list(out_dir = final_dir, assessment = assessment, decision = decision)
}

app_joint_exqdesn_phase180_compose_case_summary <- function(dirs) {
  phase174_check <- app_joint_exqdesn_verify_manifest(dirs$phase174, "phase174")
  if (any(phase174_check$status != "pass")) stop("Phase180 Phase174 source verification failed.", call. = FALSE)
  old <- app_read_csv(file.path(dirs$phase174, "final_mcmc_case_summary.csv"))
  current <- old
  article_audit <- dirs$phase179_article_audit
  if (!file.exists(file.path(article_audit, "artifact_manifest.csv"))) {
    return(list(
      case_summary = current, old = old, replacements = data.frame(),
      lineage = data.frame(), phase174_verification = phase174_check,
      article_verification = data.frame(), article_decision = data.frame()
    ))
  }
  article_check <- app_joint_exqdesn_verify_manifest(article_audit, "phase179_article_audit")
  if (any(article_check$status != "pass")) stop("Phase180 article-audit verification failed.", call. = FALSE)
  decision <- app_read_csv(file.path(article_audit, "article_promotion_decision.csv"))
  replacement <- app_read_csv(file.path(article_audit, "qualified_replacements.csv"))
  if (!nrow(replacement)) {
    return(list(
      case_summary = current, old = old, replacements = replacement,
      lineage = data.frame(), phase174_verification = phase174_check,
      article_verification = article_check, article_decision = decision
    ))
  }
  freeze <- app_joint_exqdesn_phase178_load_m0_freeze(
    dirs$phase179_article_freeze, "phase179_frozen_article_fixture_exact_M0_freeze"
  )
  init <- app_read_csv(file.path(freeze$dir, "vb_initialization_audit.csv"))
  fit_adjustment <- app_read_csv(file.path(article_audit, "fit_monotone_adjustment.csv"))
  forecast_adjustment <- app_read_csv(file.path(article_audit, "forecast_monotone_adjustment.csv"))
  chain_distance <- app_read_csv(file.path(article_audit, "chain_to_pooled_distance.csv"))
  source_sha <- app_sha256_file(file.path(article_audit, "artifact_manifest.csv"))
  lineage_rows <- list()
  for (ii in seq_len(nrow(replacement))) {
    row <- replacement[ii, , drop = FALSE]
    idx <- which(current$case_id == row$case_id[[1L]])
    if (length(idx) != 1L) stop("Phase180 could not map one replacement row.", call. = FALSE)
    init_row <- init[
      init$phase178_template_id == row$phase178_template_id[[1L]] &
        init$base_scenario_id == row$base_scenario_id[[1L]], , drop = FALSE
    ]
    if (nrow(init_row) != 1L) stop("Phase180 could not map one VB initialization row.", call. = FALSE)
    max_for <- function(x, field, default = NA_real_) {
      block <- x[x$case_id == row$case_id[[1L]], , drop = FALSE]
      values <- suppressWarnings(as.numeric(block[[field]]))
      values <- values[is.finite(values)]
      if (length(values)) max(values) else default
    }
    replace <- list(
      source_candidate_id = row$phase178_template_id[[1L]],
      phase121_candidate_id = row$phase178_template_id[[1L]],
      phase121_selection_status = "post_m0_case_specific_protected_selection",
      vb_converged = init_row$vb_converged[[1L]],
      vb_reached_max_iter = !init_row$vb_converged[[1L]],
      vb_adaptive_attempts = "VB0_point_v->VB1_structured_v",
      mcmc_n_chains = row$mcmc_n_chains[[1L]],
      mcmc_n_iter = row$mcmc_n_iter[[1L]], mcmc_burn = row$mcmc_burn[[1L]],
      mcmc_thin = row$mcmc_thin[[1L]],
      mcmc_n_keep_total = row$mcmc_n_keep_total[[1L]],
      mcmc_init_source = "provided", all_chain_init_source_provided = TRUE,
      mcmc_draws_all_finite = TRUE,
      vb_fit_truth_mae = init_row$fit_truth_mae[[1L]],
      mcmc_fit_truth_mae = row$fit_truth_mae[[1L]],
      vb_forecast_truth_mae = init_row$forecast_truth_mae[[1L]],
      mcmc_forecast_truth_mae = row$forecast_truth_mae[[1L]],
      vb_fit_check_loss_mean = init_row$fit_check_loss_mean[[1L]],
      mcmc_fit_check_loss_mean = row$fit_check_loss_mean[[1L]],
      vb_forecast_check_loss_mean = init_row$forecast_check_loss_mean[[1L]],
      mcmc_forecast_check_loss_mean = row$forecast_check_loss_mean[[1L]],
      vb_fit_raw_crossing_pairs = init_row$fit_raw_crossing_pairs[[1L]],
      mcmc_fit_raw_crossing_pairs = row$fit_raw_crossing_pairs[[1L]],
      vb_forecast_raw_crossing_pairs = init_row$forecast_raw_crossing_pairs[[1L]],
      mcmc_forecast_raw_crossing_pairs = row$forecast_raw_crossing_pairs[[1L]],
      vb_fit_contract_crossing_pairs = 0L,
      mcmc_fit_contract_crossing_pairs = row$fit_contract_crossing_pairs[[1L]],
      vb_forecast_contract_crossing_pairs = 0L,
      mcmc_forecast_contract_crossing_pairs = row$forecast_contract_crossing_pairs[[1L]],
      vb_fit_max_abs_adjustment = init_row$fit_max_abs_adjustment[[1L]],
      mcmc_fit_max_abs_adjustment = max_for(fit_adjustment, "abs_adjustment", 0),
      vb_forecast_max_abs_adjustment = init_row$forecast_max_abs_adjustment[[1L]],
      mcmc_forecast_max_abs_adjustment = max_for(forecast_adjustment, "abs_adjustment", 0),
      max_chain_to_pooled_normalized_distance = max_for(
        chain_distance, "max_normalized_to_pooled"
      ),
      vb_elapsed_seconds = init_row$elapsed_seconds[[1L]],
      mcmc_elapsed_seconds = row$elapsed_seconds_total[[1L]],
      total_elapsed_seconds = init_row$elapsed_seconds[[1L]] + row$elapsed_seconds_total[[1L]],
      source_block_id = "phase179_post_m0_case_specific_exact_M0",
      source_dir = app_prefer_repo_relative_path(article_audit),
      mcmc_forecast_crps_grid = row$forecast_crps_grid_mean[[1L]],
      mcmc_mean_abs_hit_rate_error = row$forecast_mean_abs_hit_rate_error[[1L]],
      mcmc_max_abs_hit_rate_error = row$forecast_max_abs_hit_rate_error[[1L]],
      max_chain_qhat_normalized_distance = max_for(
        chain_distance, "qhat_normalized_to_pooled"
      ),
      max_chain_sigma_normalized_distance = max_for(
        chain_distance, "sigma_normalized_to_pooled"
      ),
      max_chain_alpha_normalized_distance = max_for(
        chain_distance, "alpha_normalized_to_pooled"
      ),
      implementation_status = "pass",
      distance_status = "pass",
      chain_status = row$scalar_mixing_status[[1L]],
      raw_crossing_status = if (
        row$fit_raw_crossing_pairs[[1L]] + row$forecast_raw_crossing_pairs[[1L]] > 0L
      ) "review" else "pass",
      gate_status = if (row$scalar_mixing_status[[1L]] == "review") "review" else "pass",
      status_reason = "post-M0 case-specific candidate improved forecast MAE and passed protected/article functional gates",
      exact_control_match = TRUE, article_grade = TRUE,
      final_status = if (row$scalar_mixing_status[[1L]] == "review") "review" else "pass",
      inference_method_id = "M0_v_collapsed_support_logit",
      vb_initialization_method = "VB0_point_v_to_VB1_structured_v",
      max_rank_rhat = row$max_rank_rhat[[1L]],
      max_folded_rhat = row$max_folded_rhat[[1L]],
      min_bulk_ess = row$min_bulk_ess[[1L]], min_tail_ess = row$min_tail_ess[[1L]],
      phase173_gate_status = "superseded_by_phase179_post_m0_recovery",
      phase173b_action = "promote_post_m0_case_specific_replacement",
      phase173b_primary_metric_direction = "improved",
      phase173b_mixing_exception = row$scalar_mixing_status[[1L]] == "review",
      source_manifest_sha256 = source_sha
    )
    for (field in names(replace)) current[[field]][idx] <- replace[[field]]
    lineage_rows[[ii]] <- data.frame(
      case_id = row$case_id[[1L]], old_source_block_id = old$source_block_id[[idx]],
      new_source_block_id = replace$source_block_id,
      phase178_template_id = row$phase178_template_id[[1L]],
      old_forecast_truth_mae = old$mcmc_forecast_truth_mae[[idx]],
      new_forecast_truth_mae = row$forecast_truth_mae[[1L]],
      source_manifest_sha256 = source_sha, stringsAsFactors = FALSE
    )
  }
  unchanged <- !old$case_id %in% replacement$case_id
  old_hash <- vapply(which(unchanged), function(ii) {
    app_joint_exqdesn_phase171_row_hash(old[ii, , drop = FALSE])
  }, character(1L))
  new_hash <- vapply(which(unchanged), function(ii) {
    app_joint_exqdesn_phase171_row_hash(current[ii, , drop = FALSE])
  }, character(1L))
  if (!identical(old_hash, new_hash)) stop("Phase180 changed an unaffected Phase174 row.", call. = FALSE)
  list(
    case_summary = current, old = old, replacements = replacement,
    lineage = app_joint_qdesn_bind_rows(lineage_rows),
    phase174_verification = phase174_check,
    article_verification = article_check, article_decision = decision
  )
}

app_joint_exqdesn_phase180_build_packet <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  composed <- app_joint_exqdesn_phase180_compose_case_summary(dirs)
  case_summary <- composed$case_summary
  expected <- 32L
  hard_pass <- nrow(case_summary) == expected && !anyDuplicated(case_summary$case_id) &&
    all(is.finite(case_summary$mcmc_fit_truth_mae)) &&
    all(is.finite(case_summary$mcmc_forecast_truth_mae)) &&
    all(case_summary$mcmc_draws_all_finite) &&
    sum(case_summary$mcmc_fit_contract_crossing_pairs +
      case_summary$mcmc_forecast_contract_crossing_pairs) == 0L
  if (!hard_pass) stop("Phase180 recomposed packet failed its hard gate.", call. = FALSE)
  assessment <- app_joint_exqdesn_phase174_case_assessment(case_summary)
  winners <- app_joint_qdesn_phase155_metric_winners(case_summary)
  model_summary <- app_joint_qdesn_phase155_model_summary(case_summary)
  final <- data.frame(
    phase_id = "phase180_post_m0_recovery_packet",
    gate_status = if (any(case_summary$final_status == "review")) "review" else "pass",
    hard_implementation_gate = "pass", total_cells = nrow(case_summary),
    qualified_replacements = nrow(composed$replacements),
    unchanged_phase174_cells = nrow(case_summary) - nrow(composed$replacements),
    contract_crossing_pairs = sum(
      case_summary$mcmc_fit_contract_crossing_pairs +
        case_summary$mcmc_forecast_contract_crossing_pairs
    ),
    article_assets_modified = FALSE,
    recommendation = if (nrow(composed$replacements)) {
      "review_staged_assets_then_integrate_from_dedicated_article_chat"
    } else {
      "retain_phase174_without_manuscript_churn"
    }, stringsAsFactors = FALSE
  )
  out_dir <- dirs$phase180
  if (!force && file.exists(file.path(out_dir, "artifact_manifest.csv"))) {
    check <- app_joint_exqdesn_verify_manifest(out_dir, "phase180")
    if (all(check$status == "pass")) {
      return(list(out_dir = out_dir, final = app_read_csv(file.path(out_dir, "final_assessment.csv"))))
    }
  }
  tmp <- paste0(out_dir, ".tmp.", Sys.getpid()); app_ensure_dir(tmp)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(tmp, name))
  readme <- file.path(tmp, "README.md")
  writeLines(c(
    "# Phase180 post-M0 recovery packet", "",
    sprintf("- Qualified replacements: %d", nrow(composed$replacements)),
    sprintf("- Unchanged Phase174 cells: %d", nrow(case_summary) - nrow(composed$replacements)),
    "- Unaffected rows are canonically identical to Phase174.",
    "- This packet stages evidence only; it does not modify or publish article files."
  ), readme, useBytes = TRUE)
  paths <- c(
    phase174_manifest_verification = write(composed$phase174_verification, "phase174_manifest_verification.csv"),
    phase179_manifest_verification = write(composed$article_verification, "phase179_manifest_verification.csv"),
    article_promotion_decision = write(composed$article_decision, "article_promotion_decision.csv"),
    replacement_lineage = write(composed$lineage, "replacement_lineage.csv"),
    final_mcmc_case_summary = write(case_summary, "final_mcmc_case_summary.csv"),
    final_mcmc_case_assessment = write(assessment, "final_mcmc_case_assessment.csv"),
    model_summary = write(model_summary, "model_summary.csv"),
    scenario_winner_summary = write(winners, "scenario_winner_summary.csv"),
    final_assessment = write(final, "final_assessment.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, tmp)
  if (dir.exists(out_dir)) {
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine Phase180 packet.", call. = FALSE)
  }
  if (!file.rename(tmp, out_dir)) stop("Could not publish Phase180 packet.", call. = FALSE)
  check <- app_joint_exqdesn_verify_manifest(out_dir, "phase180")
  if (any(check$status != "pass")) stop("Phase180 packet manifest failed.", call. = FALSE)
  list(out_dir = out_dir, final = final, case_summary = case_summary)
}

app_joint_exqdesn_phase180_stage_article_assets <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  packet <- app_joint_exqdesn_phase180_build_packet(cache_root, force = FALSE)
  packet_check <- app_joint_exqdesn_verify_manifest(packet$out_dir, "phase180")
  if (any(packet_check$status != "pass")) stop("Phase180 packet verification failed.", call. = FALSE)
  case_summary <- app_read_csv(file.path(packet$out_dir, "final_mcmc_case_summary.csv"))
  final <- app_read_csv(file.path(packet$out_dir, "final_assessment.csv"))
  main_data <- app_joint_qdesn_phase155_main_table_data(case_summary)
  winners <- app_joint_qdesn_phase155_metric_winners(case_summary)
  winner_table <- app_joint_qdesn_phase155_winner_table(winners)
  gates <- data.frame(
    gate = c(
      "phase180_manifest", "balanced_grid", "unaffected_rows", "finite_scores",
      "exact_m0_replacements", "contract_crossings", "raw_crossings",
      "article_staging"
    ),
    status = c(
      "pass", "pass", "pass", "pass", "pass", "pass",
      if (sum(case_summary$mcmc_fit_raw_crossing_pairs +
        case_summary$mcmc_forecast_raw_crossing_pairs) > 0L) "review" else "pass",
      "pass"
    ),
    detail = c(
      sprintf("%d/%d packet hashes verify.", sum(packet_check$status == "pass"), nrow(packet_check)),
      "All 32 scenario-model cells are present exactly once.",
      sprintf("%d Phase174 cells remain canonically unchanged.", final$unchanged_phase174_cells[[1L]]),
      "All article-facing MCMC fit and forecast metrics are finite.",
      sprintf("%d replacements use exact M0 after protected case-specific selection.", final$qualified_replacements[[1L]]),
      sprintf("Contract crossings=%d.", final$contract_crossing_pairs[[1L]]),
      "Raw crossings remain disclosed diagnostics and are not the scored monotone contract.",
      "Files are staged outside tracked tables for the integration chat."
    ), stringsAsFactors = FALSE
  )
  out_dir <- dirs$phase180_staging
  if (dir.exists(out_dir)) {
    if (!force) stop("Phase180 staging exists; use force=TRUE to rebuild.", call. = FALSE)
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine Phase180 staging.", call. = FALSE)
  }
  tables_dir <- file.path(out_dir, "tables"); app_ensure_dir(tables_dir)
  table_paths <- c(
    model_csv = app_joint_qdesn_phase155_write_csv(
      main_data, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_model_summary.csv")
    ),
    model_tex = app_joint_qdesn_phase155_write_main_table(
      main_data, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_model_summary.tex")
    ),
    scenario_csv = app_joint_qdesn_phase155_write_csv(
      case_summary, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_scenario_summary.csv")
    ),
    winner_csv = app_joint_qdesn_phase155_write_csv(
      winners, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_winner_summary.csv")
    ),
    winner_tex = app_joint_qdesn_phase155_write_latex_table(
      winner_table,
      file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_winner_summary.tex"),
      "Lowest MCMC value within each scenario and metric after the protected post-M0 recovery audit.",
      "tab:joint-qdesn-article-validation-mcmc-balanced-winner-summary",
      "@{}>{\\raggedright\\arraybackslash}p{0.20\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}>{\\raggedright\\arraybackslash}p{0.18\\textwidth}@{}",
      size = "\\scriptsize", resize = TRUE
    ),
    gate_csv = app_joint_qdesn_phase155_write_csv(
      gates, file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_gate_summary.csv")
    ),
    gate_tex = app_joint_qdesn_phase155_write_latex_table(
      setNames(gates, c("Gate", "Status", "Detail")),
      file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_gate_summary.tex"),
      "Reproducibility and diagnostic gates for the protected post-M0 recovery packet.",
      "tab:joint-qdesn-article-validation-mcmc-balanced-gate-summary",
      "@{}>{\\raggedright\\arraybackslash}p{0.23\\textwidth}l>{\\raggedright\\arraybackslash}p{0.60\\textwidth}@{}",
      size = "\\scriptsize", resize = TRUE
    )
  )
  table_paths[["scenario_tex"]] <- app_joint_qdesn_phase155_write_wrapper(
    table_paths[["model_tex"]],
    file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex"),
    "Compatibility alias for the Phase180 scenario-level table."
  )
  asset_manifest <- data.frame(
    label = names(table_paths),
    article_relative_path = file.path("tables", basename(table_paths)),
    staged_path = normalizePath(table_paths),
    size_bytes = as.numeric(file.info(table_paths)$size),
    sha256 = vapply(table_paths, app_sha256_file, character(1L)),
    publish_authorized = FALSE, stringsAsFactors = FALSE
  )
  asset_path <- app_joint_qvp_write_csv(
    asset_manifest, file.path(out_dir, "staged_article_asset_manifest.csv")
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Phase180 staged article assets", "",
    "These files are review-only and do not modify the authoritative article checkout.",
    "The article integration chat must verify, compile, and publish them explicitly."
  ), readme, useBytes = TRUE)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(out_dir, name))
  paths <- c(
    staged_article_asset_manifest = asset_path,
    phase180_manifest_verification = write(packet_check, "phase180_manifest_verification.csv"),
    gate_summary = write(gates, "gate_summary.csv"),
    run_config = write(data.frame(
      phase_id = "phase180_article_assets_staging", source_dir = packet$out_dir,
      output_dir = out_dir, tracked_article_files_modified = FALSE,
      publish_authorized = FALSE, stringsAsFactors = FALSE
    ), "run_config.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE),
    setNames(table_paths, paste0("staged_", names(table_paths)))
  )
  app_joint_exqdesn_write_manifest(paths, out_dir)
  check <- app_joint_exqdesn_verify_manifest(out_dir, "phase180_staging")
  if (any(check$status != "pass")) stop("Phase180 staging manifest failed.", call. = FALSE)
  list(out_dir = out_dir, asset_manifest = asset_manifest, gates = gates)
}

app_joint_exqdesn_phase180_freeze_handoff <- function(
  cache_root = app_joint_exqdesn_phase164_cache_root(), force = FALSE
) {
  dirs <- app_joint_exqdesn_phase176_dirs(cache_root)
  stage <- app_joint_exqdesn_phase180_stage_article_assets(cache_root, force = FALSE)
  sources <- c(
    phase176 = dirs$phase176, phase177 = dirs$phase177_audit,
    phase178 = dirs$phase178_m0_audit, phase179 = dirs$phase179_audit,
    phase179_article = dirs$phase179_article_audit,
    phase180 = dirs$phase180, phase180_staging = stage$out_dir
  )
  present <- dir.exists(sources) & file.exists(file.path(sources, "artifact_manifest.csv"))
  source_verification <- app_joint_qdesn_bind_rows(lapply(names(sources)[present], function(id) {
    app_joint_exqdesn_verify_manifest(sources[[id]], id)
  }))
  if (nrow(source_verification) && any(source_verification$status != "pass")) {
    stop("Phase180 handoff source verification failed.", call. = FALSE)
  }
  branch <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "--abbrev-ref", "HEAD"))
  head <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "HEAD"))
  upstream <- app_joint_exqdesn_phase171_git_value(c("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"))
  status <- app_system2_repo("git", c("status", "--short"), stdout = TRUE, stderr = TRUE)
  out_dir <- dirs$phase180_handoff
  if (dir.exists(out_dir)) {
    if (!force) stop("Phase180 handoff exists; use force=TRUE to rebuild.", call. = FALSE)
    quarantine <- paste0(out_dir, ".superseded.", format(Sys.time(), "%Y%m%dT%H%M%S"))
    if (!file.rename(out_dir, quarantine)) stop("Could not quarantine Phase180 handoff.", call. = FALSE)
  }
  app_ensure_dir(out_dir)
  write <- function(x, name) app_joint_qvp_write_csv(x, file.path(out_dir, name))
  summary <- data.frame(
    lane = "joint_exqdesn_post_m0_recovery",
    branch = branch, upstream = upstream, head = head,
    worktree_clean = !length(status),
    source_hash_failures = sum(source_verification$status != "pass"),
    staged_article_assets = nrow(stage$asset_manifest),
    integration_state = if (!length(status) &&
      !sum(source_verification$status != "pass")) {
      "READY_FOR_INTEGRATION"
    } else {
      "NOT_READY_FOR_INTEGRATION"
    }, stringsAsFactors = FALSE
  )
  exclusions <- data.frame(
    path = unname(sources),
    role = "runtime_generated_hash_manifested_evidence",
    publish_to_article_git = FALSE, stringsAsFactors = FALSE
  )
  readme <- file.path(out_dir, "README.md")
  writeLines(c(
    "# Joint exQDESN post-M0 recovery integration handoff", "",
    sprintf("- State: `%s`", summary$integration_state[[1L]]),
    sprintf("- Branch: `%s`", branch), sprintf("- HEAD: `%s`", head),
    "- Only the staged table assets are article-safe publication candidates.",
    "- Runtime cache directories remain excluded from git and Overleaf."
  ), readme, useBytes = TRUE)
  paths <- c(
    integration_handoff_summary = write(summary, "integration_handoff_summary.csv"),
    source_manifest_verification = write(source_verification, "source_manifest_verification.csv"),
    article_safe_files = write(stage$asset_manifest, "article_safe_files.csv"),
    runtime_generated_exclusions = write(exclusions, "runtime_generated_exclusions.csv"),
    provenance = write(app_joint_qvp_provenance_rows(), "provenance.csv"),
    README = normalizePath(readme, mustWork = TRUE)
  )
  app_joint_exqdesn_write_manifest(paths, out_dir)
  list(out_dir = out_dir, summary = summary)
}
