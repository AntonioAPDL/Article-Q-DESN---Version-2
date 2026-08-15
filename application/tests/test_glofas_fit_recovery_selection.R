stopifnot(identical(app_glofas_selection_quantile_id(0.05), "p05"))
stopifnot(identical(app_glofas_selection_quantile_id(0.5), "p50"))
stopifnot(identical(app_glofas_selection_quantile_id(0.95), "p95"))

selection_shortlist <- data.frame(
  candidate_id = c("candidate_a", "candidate_b"),
  role = c("leader", "control"),
  source_priority = c(1L, 2L),
  advance_to_triage = c(TRUE, FALSE),
  retain_heavy = c(TRUE, TRUE),
  description = c("fixture leader", "fixture control"),
  stringsAsFactors = FALSE
)
validated_shortlist <- app_glofas_selection_validate_shortlist(selection_shortlist)
stopifnot(nrow(validated_shortlist) == 1L)
stopifnot(identical(validated_shortlist$candidate_id[[1L]], "candidate_a"))

selection_dates <- as.Date("2022-01-01") + 0:9
selection_history <- do.call(rbind, lapply(seq_along(selection_dates), function(i) {
  y <- 1 + i / 20
  q <- if (i == 1L) c(y - 0.1, y + 0.2, y + 0.1) else c(y - 0.2, y, y + 0.2)
  data.frame(
    candidate_id = "candidate_a",
    target_date = selection_dates[[i]],
    cutoff_date = max(selection_dates),
    y_log1p = y,
    qhat_log1p = q,
    raw_log1p = y + 0.1,
    y_original = expm1(y),
    qhat_original = expm1(q),
    raw_original = expm1(y + 0.1),
    quantile_id = c("p05", "p50", "p95"),
    quantile_level = c(0.05, 0.5, 0.95),
    history_path = "fixture.csv",
    stringsAsFactors = FALSE
  )
}))

selection_synthesized <- app_glofas_selection_apply_isotonic(selection_history)
stopifnot(sum(selection_synthesized$crossing$n_adjacent_crossings) == 1L)
stopifnot(isTRUE(all.equal(selection_synthesized$history$qhat_isotonic[
  selection_synthesized$history$target_date == selection_dates[[1L]]
], c(0.95, 1.2, 1.2), tolerance = 1e-12)))

selection_tail <- app_glofas_selection_tail_audit(selection_synthesized$history)
stopifnot(nrow(selection_tail$summary) == 1L)
stopifnot(selection_tail$summary$n_dates[[1L]] == length(selection_dates))
stopifnot(is.finite(selection_tail$summary$fitted_max_to_observed_max[[1L]]))
stopifnot(selection_tail$summary$max_inverse_transform_abs_error[[1L]] < 1e-12)
stopifnot(all(selection_tail$excursions$qhat_original > selection_tail$excursions$observed_max))

if (requireNamespace("ggplot2", quietly = TRUE) && isTRUE(capabilities("cairo"))) {
  selection_plot <- ggplot2::ggplot(data.frame(x = 1:2, y = 1:2), ggplot2::aes(x, y)) +
    ggplot2::geom_line()
  selection_png <- tempfile(fileext = ".png")
  selection_pdf <- tempfile(fileext = ".pdf")
  app_glofas_selection_save_plot(selection_plot, selection_png, 3, 2)
  app_glofas_selection_save_plot(selection_plot, selection_pdf, 3, 2)
  stopifnot(file.info(selection_png)$size > 0, file.info(selection_pdf)$size > 0)
  unlink(c(selection_png, selection_pdf))
}

selection_scores <- app_glofas_selection_score_windows(
  selection_synthesized$history,
  selection_synthesized$crossing,
  windows = c(NA_integer_, 5L)
)
stopifnot(nrow(selection_scores$summary) == 4L)
stopifnot(all(selection_scores$summary$n_quantiles == 3L))
stopifnot(all(is.finite(selection_scores$summary$triage_integrated_quantile_score)))
stopifnot(nrow(selection_scores$by_quantile) == 12L)
stopifnot(nrow(selection_scores$by_date) == 30L)

selection_gate <- data.frame(
  candidate_id = rep("candidate_a", 3L),
  quantile_id = c("p05", "p50", "p95"),
  gate_pass = TRUE,
  stringsAsFactors = FALSE
)
selection_ranking <- app_glofas_selection_rank(
  selection_scores$summary,
  selection_gate,
  validated_shortlist
)
stopifnot(nrow(selection_ranking) == 1L)
stopifnot(selection_ranking$triage_rank[[1L]] == 1L)
stopifnot(isTRUE(selection_ranking$advance_eligible[[1L]]))

warm_contract_fixture <- data.frame(
  vb_warm_start_enabled = TRUE,
  vb_warm_start_used = TRUE,
  vb_warm_start_theta_used = TRUE,
  vb_warm_start_future_used = FALSE,
  vb_warm_start_sigma_used = FALSE,
  stringsAsFactors = FALSE
)
stopifnot(app_glofas_selection_warm_start_contract("new_tail_fit", warm_contract_fixture))
stopifnot(app_glofas_selection_warm_start_contract("new_full7_fit", warm_contract_fixture))
stopifnot(app_glofas_selection_warm_start_contract("reused_p50", warm_contract_fixture))
stopifnot(!app_glofas_selection_warm_start_contract(
  "new_cold_start_transition_full7_fit", warm_contract_fixture
))

cold_contract_fixture <- warm_contract_fixture
cold_contract_fixture[] <- FALSE
stopifnot(app_glofas_selection_warm_start_contract(
  "new_cold_start_transition_full7_fit", cold_contract_fixture
))
stopifnot(app_glofas_selection_warm_start_contract(
  "new_cold_start_tail_repair_fit", cold_contract_fixture
))
stopifnot(app_glofas_selection_warm_start_contract(
  "new_cold_start_p95_global_scale_warmup_fit", cold_contract_fixture
))
stopifnot(app_glofas_selection_warm_start_contract(
  "immutable_effective_k0_control", cold_contract_fixture
))
stopifnot(!app_glofas_selection_warm_start_contract("new_tail_fit", cold_contract_fixture))
unsupported_source_error <- tryCatch(
  {
    app_glofas_selection_warm_start_contract("unknown_source", cold_contract_fixture)
    ""
  },
  error = function(e) conditionMessage(e)
)
stopifnot(grepl("Unsupported quantile source kind", unsupported_source_error))
