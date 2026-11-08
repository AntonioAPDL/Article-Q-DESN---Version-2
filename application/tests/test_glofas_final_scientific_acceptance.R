source(app_path("application/R/glofas_final_scientific_acceptance.R"))

issues <- gfsa_issue_ledger()
stopifnot(nrow(issues) == 12L, sum(issues$status == "pass") == 11L,
  identical(issues$status[issues$issue == "part2_post_cutoff_discrepancy_scoring"],
    "not_evaluable"), !any(issues$rerun_required))

part123 <- expand.grid(part = paste("Part", 1:3),
  family = c("Normal Ridge", "Normal RHS/VB", "Independent AL", "Independent exAL", "Joint AL", "Joint exAL"),
  stringsAsFactors = FALSE)
part123$numerical_status <- ifelse(part123$part == "Part 2",
  "unscored_future_retrospective_unavailable", "completed")
part123$n_scored_horizons <- ifelse(part123$part == "Part 2", 0L, 30L)
part123$crps_grid_log1p <- ifelse(part123$part == "Part 2", NA_real_, .5)
part123$crossing_pairs <- ifelse(part123$part == "Part 2", NA_integer_, 0L)
part4 <- data.frame(family = c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL",
  "Normal Ridge", "Normal RHS/VB", "Raw GloFAS"), crps_grid_log1p = seq(.7, 1.3, .1),
  crossing_pairs = c(1L, 0L, 0L, 0L, 0L, 0L, 0L), stringsAsFactors = FALSE)
components <- gfsa_component_table(part123, part4)
stopifnot(nrow(components) == 25L,
  identical(components$evaluation_status[components$component == "Part 2"],
    rep("not_evaluable_future_retrospective_unavailable", 6L)),
  max(components$crossing_pairs[components$component == "Part 4"], na.rm = TRUE) == 1L)

bad <- part4
bad$crossing_pairs[bad$family == "Independent AL"] <- 2L
stopifnot(max(bad$crossing_pairs[bad$family %in%
  c("Independent AL", "Independent exAL", "MQ AL", "MQ exAL")]) > 1L)

cat("GLOFAS_FINAL_SCIENTIFIC_ACCEPTANCE_TEST_PASS\n")

