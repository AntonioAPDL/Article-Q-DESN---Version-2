pred_identity <- data.frame(
  fit_id = rep(c("q10", "q50", "q90"), each = 2L),
  model_id = "qdesn_test",
  model_family = "qdesn_glofas_discrepancy",
  origin_date = as.Date("2026-01-01"),
  target_date = rep(as.Date("2026-01-01") + 1:2, 3L),
  horizon = rep(1:2, 3L),
  quantile_level = rep(c(0.1, 0.5, 0.9), each = 2L),
  qhat = c(1.0, 1.2, 1.5, 1.7, 2.0, 2.2),
  qhat_monotone = c(1.0, 1.2, 1.5, 1.8, 1.9, 2.1),
  q_g_hat = c(1.3, 1.6, 1.8, 2.1, 2.2, 2.7),
  d_g_hat = c(0.3, 0.4, 0.3, 0.4, 0.2, 0.5),
  raw_glofas_quantile = c(1.25, 1.55, 1.75, 2.05, 2.15, 2.65),
  stringsAsFactors = FALSE
)

draw_identity <- data.frame(
  draw_id = rep(sprintf("draw_%02d", 1:3), each = 2L),
  draw_index = rep(1:3, each = 2L),
  fit_id = "q50",
  model_id = "qdesn_test",
  model_family = "qdesn_glofas_discrepancy",
  quantile_level = 0.5,
  origin_date = as.Date("2026-01-01"),
  target_date = rep(as.Date("2026-01-01") + 1:2, 3L),
  horizon = rep(1:2, 3L),
  q_y_draw = c(1.5, 1.7, 1.55, 1.72, 1.45, 1.68),
  d_g_draw = c(0.3, 0.4, 0.35, 0.38, 0.28, 0.42),
  raw_glofas_quantile = c(1.75, 2.05, 1.75, 2.05, 1.75, 2.05),
  stringsAsFactors = FALSE
)
draw_identity$q_g_draw <- draw_identity$q_y_draw + draw_identity$d_g_draw

identity_audit <- app_discrepancy_identity_audit(pred_identity, draw_identity)
stopifnot(nrow(identity_audit$prediction_summary) == 2L)
ind <- identity_audit$prediction_summary[identity_audit$prediction_summary$value_col == "qhat", , drop = FALSE]
mono <- identity_audit$prediction_summary[identity_audit$prediction_summary$value_col == "qhat_monotone", , drop = FALSE]
stopifnot(nrow(ind) == 1L)
stopifnot(nrow(mono) == 1L)
stopifnot(ind$reference_identity_error_max_abs < 1.0e-12)
stopifnot(ind$glofas_identity_error_max_abs < 1.0e-12)
stopifnot(mono$reference_identity_error_max_abs > 0.05)
stopifnot(any(identity_audit$readiness$check == "monotone_synthesis_identity_expected"))
stopifnot(all(identity_audit$readiness$passed))

tmp_identity_dir <- tempfile("qdesn_identity_audit_")
dir.create(file.path(tmp_identity_dir, "tables"), recursive = TRUE)
dir.create(file.path(tmp_identity_dir, "figures"), recursive = TRUE)
identity_outputs <- app_write_discrepancy_identity_audit(
  pred_identity,
  draw_identity,
  file.path(tmp_identity_dir, "tables"),
  file.path(tmp_identity_dir, "figures")
)
stopifnot(file.exists(identity_outputs[["discrepancy_identity_reconciliation"]]))
stopifnot(file.info(identity_outputs[["discrepancy_identity_reconciliation"]])$size > 1000)
stopifnot(file.exists(file.path(tmp_identity_dir, "tables", "discrepancy_identity_readiness.csv")))
