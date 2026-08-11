qg <- app_validate_quantile_grid(app_config_path(cfg, "quantile_grid"))
stopifnot(nrow(qg) == 7L)
stopifnot(identical(qg$quantile_level, sort(qg$quantile_level)))

toy <- data.frame(
  model_id = "toy",
  origin_date = as.Date("2026-01-01"),
  target_date = as.Date("2026-01-02"),
  horizon = 1L,
  quantile_level = c(0.1, 0.5, 0.9),
  qhat = c(3, 2, 4)
)
toy2 <- app_synthesize_quantile_grid(toy)
stopifnot(all(diff(toy2$qhat_monotone) >= -1e-12))

source_p05 <- data.frame(
  model_id = c("raw_p05", "qdesn_p05"),
  origin_date = as.Date("2022-12-25"),
  target_date = as.Date("2022-12-26"),
  horizon = 1L,
  quantile_level = 0.05,
  qhat = c(0.8, 1.0),
  stringsAsFactors = FALSE
)
source_p95 <- source_p05
source_p95$model_id <- c("raw_p95", "qdesn_p95")
source_p95$quantile_level <- 0.95
source_p95$qhat <- c(2.2, 2.0)
manifest_p05 <- data.frame(
  raw_fit_id = "raw_p05",
  qdesn_fit_id = "qdesn_p05",
  raw_synthesis_model_id = "raw_authoritative",
  qdesn_synthesis_model_id = "qdesn_authoritative",
  stringsAsFactors = FALSE
)
manifest_p95 <- manifest_p05
manifest_p95$raw_fit_id <- "raw_p95"
manifest_p95$qdesn_fit_id <- "qdesn_p95"

mapped <- rbind(
  app_apply_synthesis_model_identity(source_p05, manifest_p05),
  app_apply_synthesis_model_identity(source_p95, manifest_p95)
)
stopifnot(identical(sort(unique(mapped$model_id)), c("qdesn_authoritative", "raw_authoritative")))
stopifnot(identical(sort(unique(mapped$source_model_id)), c("qdesn_p05", "qdesn_p95", "raw_p05", "raw_p95")))
grid_audit <- app_synthesis_model_grid_audit(mapped, c(0.05, 0.95))
stopifnot(nrow(grid_audit) == 2L, all(grid_audit$complete_quantile_grid))

unmapped_audit <- app_synthesis_model_grid_audit(rbind(source_p05, source_p95), c(0.05, 0.95))
stopifnot(nrow(unmapped_audit) == 4L, !any(unmapped_audit$complete_quantile_grid))
