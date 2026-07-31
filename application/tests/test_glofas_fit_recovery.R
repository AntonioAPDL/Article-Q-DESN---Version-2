recovery_candidates <- data.frame(
  candidate_id = c("a", "b"),
  role = c("parity", "ablation"),
  include_input_block = c(TRUE, FALSE),
  direct_output_lag_max = c(360, NA),
  direct_covariate_lag_max = c(360, NA),
  alpha = c(0.92, 0.10),
  rhs_tau0 = c(0.10, 0.001),
  rhs_alpha_tau0 = c(0.03, 0.001),
  retain_heavy = c(TRUE, FALSE),
  priority = c(1, 2),
  stringsAsFactors = FALSE
)
validated_candidates <- app_glofas_fit_recovery_validate_candidates(recovery_candidates)
stopifnot(validated_candidates$expected_n_block_features[[1L]] == 1383L)
stopifnot(validated_candidates$expected_n_block_features[[2L]] == 301L)

dates <- as.Date("2022-12-01") + 0:9
history_input <- data.frame(
  target_date = dates,
  y_reference = log1p(seq_len(10)),
  q_y_median = log1p(seq_len(10) + 1),
  glofas_retrospective = log1p(seq_len(10) + 2),
  stringsAsFactors = FALSE
)
history <- app_glofas_fit_recovery_history(
  history_input,
  candidate_id = "fixture",
  cutoff_date = as.Date("2022-12-10")
)
stopifnot(nrow(history) == 10L)
stopifnot(max(history$target_date) == as.Date("2022-12-10"))
scores <- app_glofas_fit_recovery_score_history(history, windows = c(NA_integer_, 5L))
stopifnot(identical(scores$window, c("all", "last5")))
stopifnot(isTRUE(all.equal(
  scores$p50_check_loss_mean,
  0.5 * scores$p50_degenerate_crps_proxy_mean
)))
stopifnot(isTRUE(all.equal(scores$check_loss_mean, scores$p50_check_loss_mean)))
tail_scores <- app_glofas_fit_recovery_score_history(history, windows = NA_integer_, tau = 0.05)
stopifnot(tail_scores$quantile_level[[1L]] == 0.05)
stopifnot(is.finite(tail_scores$check_loss_mean[[1L]]))
stopifnot(is.na(tail_scores$p50_check_loss_mean[[1L]]))
stopifnot(all(scores$original_mae > 0))

history_b <- history
history_b$candidate_id <- "fixture_b"
history_b <- history_b[-1L, , drop = FALSE]
aligned <- app_glofas_fit_recovery_align_histories(list(history, history_b))
stopifnot(length(aligned) == 2L)
stopifnot(nrow(aligned[[1L]]) == 9L)
stopifnot(identical(aligned[[1L]]$target_date, aligned[[2L]]$target_date))

observed_contract <- data.frame(
  design_hash = "abc",
  n_beta_features = 1383L,
  n_alpha_features = 1383L,
  two_block_design = TRUE,
  stringsAsFactors = FALSE
)
contract_audit <- app_glofas_fit_recovery_contract_audit(
  observed_contract,
  expected = list(
    design_hash = "abc",
    n_beta_features = 1383L,
    n_alpha_features = 1383L,
    two_block_design = TRUE
  )
)
stopifnot(all(contract_audit$equal))

bad_candidates <- recovery_candidates
bad_candidates$candidate_id[[2L]] <- "a"
bad_message <- tryCatch(
  {
    app_glofas_fit_recovery_validate_candidates(bad_candidates)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("unique", bad_message))

cleanup_root <- tempfile("glofas_fit_recovery_cleanup_")
run_dir <- file.path(cleanup_root, "run_a")
dir.create(file.path(run_dir, "objects"), recursive = TRUE)
saveRDS(list(x = 1), file.path(run_dir, "objects", "fit.rds"))
dry_cleanup <- app_glofas_fit_recovery_cleanup(
  run_dir,
  runs_root = cleanup_root,
  execute = FALSE
)
stopifnot(nrow(dry_cleanup) == 1L)
stopifnot(file.exists(dry_cleanup$path[[1L]]))
writeLines("complete", file.path(run_dir, ".fit_recovery_complete"))
done_cleanup <- app_glofas_fit_recovery_cleanup(
  run_dir,
  runs_root = cleanup_root,
  execute = TRUE
)
stopifnot(isTRUE(done_cleanup$executed[[1L]]))
stopifnot(!file.exists(done_cleanup$path[[1L]]))
unlink(cleanup_root, recursive = TRUE)
