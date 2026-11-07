# Read-only reconciliation of committed small GloFAS authority CSVs.
local({
  source("scripts/diagnostics/glofas_authority_reconciliation.R", local = TRUE)
  result <- gar_reconcile(".")
  stopifnot(
    identical(result$schema_version, "glofas_authority_reconciliation_v1"),
    identical(result$common_probabilities, c(.05, .35, .5, .65, .8, .95)),
    nrow(result$summary) == 3L,
    abs(result$summary$acrps[result$summary$authority ==
      "previous_raw_common_grid"] - 1.121443) < 1e-5,
    abs(result$summary$acrps[result$summary$authority ==
      "previous_monotone_common_grid"] - 1.121410) < 1e-5,
    abs(result$summary$acrps[result$summary$authority ==
      "current_independent_al_common_grid"] - 1.512114) < 1e-5,
    result$summary$crossing_pairs[result$summary$authority ==
      "previous_raw_common_grid"] == 3L,
    result$summary$crossing_pairs[result$summary$authority ==
      "previous_monotone_common_grid"] == 0L,
    result$summary$crossing_pairs[result$summary$authority ==
      "current_independent_al_common_grid"] == 34L,
    result$summary$maximum_crossing[result$summary$authority ==
      "current_independent_al_common_grid"] > 4,
    all(nchar(result$input_sha256) == 64L),
    identical(result$future_truth_role, "postfit_descriptive_scoring_only"),
    !result$model_selection_performed,
    result$files_written == 0L)
  historical_crossings <- vapply(result$historical,
    function(x) x$crossings$pairs, integer(1L))
  stopifnot(all(historical_crossings <= 2L))
  message("GLOFAS_AUTHORITY_RECONCILIATION_PASS inputs=",
    length(result$input_sha256), " common_grid=6 model_selection=FALSE")
})

