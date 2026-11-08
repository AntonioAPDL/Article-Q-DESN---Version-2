source(app_path("application/R/glofas_part4_hybrid_authority_handoff.R"))

tau <- c(.05, .2, .35, .5, .65, .8, .95)
stopifnot(abs(sum(gpah_grid_weights(tau)) - .9) < 1e-15)

toy <- expand.grid(horizon = 1:28, quantile_level = tau,
  family = c("Independent AL", "Raw GloFAS"), stringsAsFactors = FALSE)
toy$target_date <- as.character(as.Date("2023-01-01") + toy$horizon - 1L)
toy$y_reference <- toy$horizon / 10
toy$qhat <- toy$y_reference + (toy$quantile_level - .5)
scores <- gpah_recompute_scores(toy)
stopifnot(nrow(scores) == 2L, all(scores$n_scored_horizons == 28L),
  all(scores$crossing_pairs == 0L))

fixture <- data.frame(
  family = gpah_family_order, mean_check_loss = seq(.1, .7, .1),
  crps_grid_log1p = seq(.2, 1.4, .2), coverage90 = seq(.1, .7, .1),
  crossing_pairs = 0:6, stringsAsFactors = FALSE)
tex <- gpah_score_tex(fixture)
stopifnot(any(grepl("Independent AL", tex, fixed = TRUE)),
  any(grepl("Raw GloFAS", tex, fixed = TRUE)))

aliases <- gpah_aliases("test_hybrid", fixture)
stopifnot(any(grepl("test_hybrid", aliases, fixed = TRUE)),
  !any(grepl("glofas_same_family_20261103", aliases, fixed = TRUE)))

cat("GLOFAS_PART4_HYBRID_AUTHORITY_HANDOFF_TEST_PASS\n")
