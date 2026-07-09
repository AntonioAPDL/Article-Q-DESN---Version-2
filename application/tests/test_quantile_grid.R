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
