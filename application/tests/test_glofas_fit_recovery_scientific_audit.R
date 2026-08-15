scientific_dates <- as.Date("2020-01-01") + 0:5
scientific_levels <- c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95)
scientific_selection <- do.call(rbind, lapply(seq_along(scientific_dates), function(i) {
  y <- log1p(10 + i)
  q <- y + stats::qnorm(scientific_levels) * 0.08
  if (i == length(scientific_dates)) q[[7L]] <- log1p(1000)
  data.frame(
    candidate_id = "current",
    target_date = scientific_dates[[i]],
    quantile_level = scientific_levels,
    y_log1p = y,
    y_original = expm1(y),
    qhat_independent = q,
    qhat_isotonic = q,
    qhat_log1p = q,
    qhat_original = expm1(q),
    raw_log1p = NA_real_,
    raw_original = NA_real_,
    stringsAsFactors = FALSE
  )
}))
scientific_archive <- data.frame(
  quantile_level = scientific_selection$quantile_level,
  target_date = scientific_selection$target_date,
  y_reference = scientific_selection$y_log1p,
  qhat = scientific_selection$y_log1p + stats::qnorm(scientific_selection$quantile_level) * 0.05,
  stringsAsFactors = FALSE
)
scientific_selection_path <- tempfile(fileext = ".csv")
scientific_archive_path <- tempfile(fileext = ".csv")
utils::write.csv(scientific_selection, scientific_selection_path, row.names = FALSE)
utils::write.csv(scientific_archive, scientific_archive_path, row.names = FALSE)
scientific_manifest <- data.frame(
  candidate_id = c("current", "archive"),
  source_role = c("current_transition_candidate", "historical_available_comparator"),
  history_format = c("selection_long", "pre_cutoff_quantile_history"),
  history_path = c(scientific_selection_path, scientific_archive_path),
  history_sha256 = vapply(c(scientific_selection_path, scientific_archive_path), app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
scientific_common <- app_glofas_scientific_common_history(
  scientific_manifest, max(scientific_dates)
)
stopifnot(length(scientific_common$common_dates) == length(scientific_dates))
stopifnot(nrow(scientific_common$history) == 2L * length(scientific_dates) * length(scientific_levels))
scientific_synthesized <- app_glofas_scientific_apply_isotonic(scientific_common$history)
scientific_synthesized_reference <- app_glofas_selection_apply_isotonic(scientific_common$history)
stopifnot(isTRUE(all.equal(
  scientific_synthesized$history$qhat_isotonic,
  scientific_synthesized_reference$history$qhat_isotonic,
  tolerance = 1e-12
)))
scientific_scores <- app_glofas_scientific_score_windows(
  scientific_synthesized$history,
  scientific_synthesized$crossing,
  windows = c(NA_integer_, 3L)
)
stopifnot(setequal(scientific_scores$summary$score_scale, c("log1p", "original")))
stopifnot(all(is.finite(scientific_scores$summary$integrated_quantile_score_mean)))
scientific_distribution <- app_glofas_scientific_score_distribution(scientific_scores$by_date)
stopifnot(all(scientific_distribution$all_finite))
stopifnot(all(c("score_median", "score_q95", "score_max") %in% names(scientific_distribution)))

scientific_tail <- app_glofas_scientific_tail_audit(scientific_synthesized$history)
current_tail <- scientific_tail$summary[
  scientific_tail$summary$candidate_id == "current" &
    scientific_tail$summary$estimate_mode == "independent",
  , drop = FALSE
]
stopifnot(nrow(current_tail) == 1L)
stopifnot("fitted_max_to_observed_max_ratio" %in% names(current_tail))
stopifnot(current_tail$fitted_max_to_observed_max_ratio > 20)

scientific_component_history <- data.frame(
  target_date = scientific_dates,
  quantile_level = 0.95,
  y_reference = log1p(10 + seq_along(scientific_dates)),
  glofas_retrospective = log1p(12 + seq_along(scientific_dates)),
  stringsAsFactors = FALSE
)
scientific_component_history$observed_discrepancy <- with(
  scientific_component_history, glofas_retrospective - y_reference
)
scientific_component_history$q_g_median <- scientific_component_history$glofas_retrospective
scientific_component_history$d_g_median <- c(rep(0.1, 5L), -4)
scientific_component_history$q_y_median <- with(
  scientific_component_history, q_g_median - d_g_median
)
scientific_component_history$q_g_mean <- scientific_component_history$q_g_median
scientific_component_history$d_g_mean <- scientific_component_history$d_g_median
scientific_component_history$q_y_mean <- scientific_component_history$q_y_median
scientific_component <- app_glofas_scientific_component_audit(
  scientific_component_history, "current"
)
stopifnot(scientific_component$summary$prediction_identity_max_abs_error < 1e-12)
stopifnot(scientific_component$summary$fitted_abs_discrepancy_to_history_q995_ratio > 1.5)

scientific_X <- cbind(1, seq_len(6) / 10, c(0, 0, 0, 0, 0, 1))
scientific_alpha <- c(0.1, 0, -4.1)
scientific_X_beta <- cbind(1, scientific_component_history$q_y_mean)
scientific_beta <- c(0, 1)
scientific_fit <- list(variational_state = list(theta_mean = c(scientific_beta, scientific_alpha)))
scientific_design <- list(
  X_beta = scientific_X_beta,
  X_alpha = scientific_X,
  beta_index = 1:2,
  alpha_index = 3:5,
  feature_info_beta = data.frame(
    block = c("readout_intercept", "reservoir_state"),
    variable = c(NA, NA),
    stringsAsFactors = FALSE
  ),
  feature_info_alpha = data.frame(
    block = c("readout_intercept", "reservoir_state", "direct_output_lag"),
    variable = c(NA, NA, "discrepancy"),
    stringsAsFactors = FALSE
  ),
  base_panel = data.frame(target_date = scientific_dates),
  discrepancy_baseline_fixed = rep(0, 6L)
)
scientific_contribution <- app_glofas_scientific_contribution_audit(
  scientific_fit, scientific_design, scientific_component$detail, "current", top_n = 3L
)
stopifnot(scientific_contribution$alignment$max_abs_discrepancy_alignment_error < 1e-12)
stopifnot(scientific_contribution$alignment$max_abs_reference_alignment_error < 1e-12)
stopifnot(any(scientific_contribution$group_summary$feature_group == "direct_output_lag"))

scientific_gate <- app_glofas_scientific_promotion_gate(
  "current", scientific_distribution, scientific_tail$summary,
  scientific_component$summary, scientific_contribution$alignment
)
stopifnot(!scientific_gate$scientific_promotion_gate_pass)
stopifnot(grepl("p95_tail_scale", scientific_gate$failed_gates))
stopifnot(grepl("p95_discrepancy_support", scientific_gate$failed_gates))

scientific_pass_tail <- current_tail
scientific_pass_tail$fitted_max_to_observed_max_ratio <- 2
scientific_pass_tail$n_above_20x_observed_max <- 0L
scientific_pass_component <- scientific_component$summary
scientific_pass_component$fitted_abs_discrepancy_to_history_q995_ratio <- 1.1
scientific_pass_gate <- app_glofas_scientific_promotion_gate(
  "current", scientific_distribution, scientific_pass_tail,
  scientific_pass_component, scientific_contribution$alignment
)
stopifnot(scientific_pass_gate$scientific_promotion_gate_pass)
stopifnot(identical(scientific_pass_gate$decision[[1L]], "eligible_for_human_review"))
stopifnot(!scientific_pass_gate$auto_promote, !scientific_pass_gate$article_update_authorized)

unlink(c(scientific_selection_path, scientific_archive_path))
