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

rejected_dir <- file.path(cleanup_root, "run_rejected")
dir.create(file.path(rejected_dir, "objects"), recursive = TRUE)
saveRDS(list(x = 2), file.path(rejected_dir, "objects", "rejected_fit.rds"))
writeLines("rejected", file.path(rejected_dir, ".reservoir_preflight_rejected"))
rejected_cleanup <- app_glofas_fit_recovery_cleanup(
  rejected_dir,
  runs_root = cleanup_root,
  execute = TRUE
)
stopifnot(nrow(rejected_cleanup) == 1L)
stopifnot(isTRUE(rejected_cleanup$executed[[1L]]))
stopifnot(!file.exists(rejected_cleanup$path[[1L]]))

empty_rejected_dir <- file.path(cleanup_root, "empty_rejected")
dir.create(empty_rejected_dir, recursive = TRUE)
writeLines("rejected", file.path(empty_rejected_dir, ".reservoir_preflight_rejected"))
empty_rejected_cleanup <- app_glofas_fit_recovery_cleanup(
  empty_rejected_dir,
  runs_root = cleanup_root,
  execute = TRUE
)
stopifnot(is.data.frame(empty_rejected_cleanup))
stopifnot(nrow(empty_rejected_cleanup) == 0L)
unlink(cleanup_root, recursive = TRUE)

portability_dates <- as.Date("2022-01-01") + 0:3
portability_q <- data.frame(
  target_date = portability_dates,
  horizon = 1:4,
  qhat = c(1.0, 1.1, 1.2, 1.3),
  y_reference = c(1.0, 1.2, 1.1, 1.4),
  q_g_hat = c(1.2, 1.3, 1.4, 1.5),
  d_g_hat = rep(0.2, 4),
  stringsAsFactors = FALSE
)
portability_raw <- data.frame(
  target_date = portability_dates,
  qhat = c(0.7, 0.8, 0.8, 0.9),
  stringsAsFactors = FALSE
)
portability_history <- data.frame(
  target_date = as.Date("2021-01-01") + 0:199,
  observed_discrepancy = seq(-0.5, 0.5, length.out = 200),
  stringsAsFactors = FALSE
)
portability_ok <- app_glofas_fit_recovery_portability_audit(
  portability_q, portability_raw, portability_history
)
stopifnot(isTRUE(portability_ok$summary$scientific_portability_gate_pass[[1L]]))
stopifnot(portability_ok$summary$component_identity_max_abs_error[[1L]] < 1e-12)

portability_explosive <- portability_q
portability_explosive$d_g_hat <- -6
portability_explosive$qhat <- portability_explosive$q_g_hat - portability_explosive$d_g_hat
portability_bad <- app_glofas_fit_recovery_portability_audit(
  portability_explosive, portability_raw, portability_history
)
stopifnot(!portability_bad$summary$performance_gate_pass[[1L]])
stopifnot(!portability_bad$summary$forecast_scale_gate_pass[[1L]])
stopifnot(!portability_bad$summary$discrepancy_support_gate_pass[[1L]])
stopifnot(isTRUE(portability_bad$summary$component_identity_gate_pass[[1L]]))

portability_identity <- portability_q
portability_identity$qhat[[1L]] <- portability_identity$qhat[[1L]] + 0.1
portability_identity_bad <- app_glofas_fit_recovery_portability_audit(
  portability_identity, portability_raw, portability_history
)
stopifnot(!portability_identity_bad$summary$component_identity_gate_pass[[1L]])

transition_cutoffs <- c("nov12_2021", "dec21_2021", "may11_2022", "jan23_2021")
transition_roles <- c(rep("primary_v31", 3L), "supplemental_source_vintage")
transition_fixture <- rbind(
  data.frame(
    candidate_id = "fr09_recursive_level",
    cutoff_id = transition_cutoffs,
    validation_role = transition_roles,
    discrepancy_transition_strategy = "recursive_level",
    discrepancy_tau0 = 0.001,
    qdesn_check_loss_mean = c(0.20, 0.30, 0.10, 0.25),
    raw_check_loss_mean = c(0.18, 0.22, 0.12, 0.20),
    technical_gate_pass = TRUE,
    scientific_portability_gate_pass = c(TRUE, FALSE, TRUE, TRUE),
    stringsAsFactors = FALSE
  ),
  data.frame(
    candidate_id = "fr09_persistence_innovation",
    cutoff_id = transition_cutoffs,
    validation_role = transition_roles,
    discrepancy_transition_strategy = "persistence_anchored_innovation",
    discrepancy_tau0 = 0.001,
    qdesn_check_loss_mean = c(0.15, 0.17, 0.09, 0.18),
    raw_check_loss_mean = c(0.18, 0.22, 0.12, 0.20),
    technical_gate_pass = TRUE,
    scientific_portability_gate_pass = TRUE,
    stringsAsFactors = FALSE
  )
)
transition_fixture$check_loss_ratio_vs_raw <- with(
  transition_fixture,
  qdesn_check_loss_mean / raw_check_loss_mean
)
transition_fixture$check_loss_reduction_vs_raw <- with(
  transition_fixture,
  (raw_check_loss_mean - qdesn_check_loss_mean) / raw_check_loss_mean
)
transition_ranking <- app_glofas_transition_validation_summary(transition_fixture)
stopifnot(identical(transition_ranking$candidate_id[[1L]], "fr09_persistence_innovation"))
stopifnot(transition_ranking$n_primary_cutoffs[[1L]] == 3L)
stopifnot(transition_ranking$n_supplemental_cutoffs[[1L]] == 1L)
stopifnot(isTRUE(transition_ranking$eligible_for_full7_review[[1L]]))
stopifnot(!transition_ranking$auto_launch_full7[[1L]])
stopifnot(!transition_ranking$eligible_for_full7_review[[2L]])

transition_paired <- app_glofas_transition_paired_comparison(transition_fixture)
stopifnot(nrow(transition_paired) == length(transition_cutoffs))
expected_reduction <- (c(0.20, 0.30, 0.10, 0.25) - c(0.15, 0.17, 0.09, 0.18)) /
  c(0.20, 0.30, 0.10, 0.25)
stopifnot(isTRUE(all.equal(
  transition_paired$innovation_check_loss_reduction_vs_recursive,
  expected_reduction
)))

transition_incomplete <- transition_fixture[
  !(transition_fixture$candidate_id == "fr09_persistence_innovation" &
      transition_fixture$cutoff_id == "jan23_2021"),
  ,
  drop = FALSE
]
transition_pair_error <- tryCatch(
  {
    app_glofas_transition_paired_comparison(transition_incomplete)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("same cutoff grid", transition_pair_error))

transition_duplicate <- rbind(transition_fixture, transition_fixture[1L, , drop = FALSE])
transition_duplicate_error <- tryCatch(
  {
    app_glofas_transition_validation_summary(transition_duplicate)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("one row per candidate and cutoff", transition_duplicate_error))

transition_missing_gate <- transition_fixture
transition_missing_gate$scientific_portability_gate_pass[[1L]] <- NA
transition_gate_error <- tryCatch(
  {
    app_glofas_transition_validation_summary(transition_missing_gate)
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("fully determined", transition_gate_error))
