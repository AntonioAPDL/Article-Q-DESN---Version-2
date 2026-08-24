closeout_root <- tempfile("glofas_program_closeout_")
dir.create(closeout_root, recursive = TRUE)
make_closeout_phase <- function(name, score, improvement, eligible = FALSE) {
  root <- file.path(closeout_root, name)
  dir.create(root)
  ranking <- data.frame(
    candidate_id = paste0(name, "_leader"),
    screen_rank = 1L,
    forecast_p50_check_loss_mean = score,
    forecast_improvement_fraction = improvement,
    observed_log1p_mae_all = 0.06,
    observed_log1p_mae_last200 = 0.05,
    eligible_for_full7_review = eligible,
    stringsAsFactors = FALSE
  )
  app_write_csv(ranking, file.path(root, "constrained_median_ranking.csv"))
  app_write_csv(data.frame(
    batch_complete = TRUE,
    completed_candidates = 1L,
    preflight_rejected_candidates = 0L,
    total_candidates = 1L,
    stringsAsFactors = FALSE
  ), file.path(root, "selection_decision.csv"))
  list(
    phase_id = name,
    runtime_root = root,
    expected_total = 1L,
    expected_completed = 1L,
    expected_preflight_rejected = 0L,
    expected_ranking_sha256 = app_sha256_file(file.path(root, "constrained_median_ranking.csv")),
    expected_leader = paste0(name, "_leader")
  )
}

closeout_contract <- list(
  program_id = "fixture",
  baseline = list(
    candidate_id = "baseline",
    forecast_p50_check_loss_mean = 1,
    minimum_relative_improvement = 0.03
  ),
  expected_decision = "retain_fr09_and_close_local_desn_screening_program",
  phases = list(
    make_closeout_phase("phase_a", 0.99, 0.01),
    make_closeout_phase("phase_b", 0.98, 0.02)
  )
)
closeout_result <- app_glofas_screening_program_closeout(closeout_contract)
stopifnot(nrow(closeout_result$phases) == 2L)
stopifnot(closeout_result$decision$total_candidates[[1L]] == 2L)
stopifnot(identical(closeout_result$decision$best_phase_id[[1L]], "phase_b"))
stopifnot(!app_as_bool(closeout_result$decision$full7_warranted[[1L]]))
stopifnot(identical(
  closeout_result$decision$decision[[1L]],
  "retain_fr09_and_close_local_desn_screening_program"
))

drifted <- closeout_contract
drifted$phases[[1L]]$expected_ranking_sha256 <- paste(rep("0", 64L), collapse = "")
stopifnot(inherits(try(
  app_glofas_screening_program_closeout(drifted),
  silent = TRUE
), "try-error"))

