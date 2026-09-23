search3_folds <- app_glofas_search3_fold_registry()
stopifnot(nrow(search3_folds) == 36L)
stopifnot(sum(search3_folds$panel == "development" & search3_folds$primary) == 16L)
stopifnot(sum(search3_folds$panel == "confirmation" & search3_folds$primary) == 16L)
stopifnot(nrow(app_glofas_search3_folds(search3_folds, "ridge_a")) == 12L)
stopifnot(nrow(app_glofas_search3_folds(search3_folds, "ridge_b")) == 4L)
stopifnot(nrow(app_glofas_search3_folds(search3_folds, "ridge_guard")) == 2L)
stopifnot(nrow(app_glofas_search3_folds(search3_folds, "rhs_pilot")) == 8L)
stopifnot(nrow(app_glofas_search3_folds(search3_folds, "rhs_screen")) == 18L)
stopifnot(nrow(app_glofas_search3_folds(search3_folds, "confirmation")) == 18L)
stopifnot(!any(search3_folds$origin_date == as.Date("2022-12-25")))

search2_candidates <- app_bind_rows_fill(lapply(c("reference", "discrepancy"), function(target) {
  app_glofas_search2_candidate_manifest(target, n_space_filling = 64L)
}))
search2_scores <- data.frame(
  candidate_id = search2_candidates$candidate_id,
  target = search2_candidates$target,
  method = "ridge",
  mean_primary_crps = seq(0.1, 0.3, length.out = nrow(search2_candidates)),
  stringsAsFactors = FALSE
)
search3_candidates <- app_glofas_search3_candidates(search2_candidates, search2_scores)
stopifnot(nrow(search3_candidates) == 80L)
stopifnot(all(table(search3_candidates$target) == 40L))
stopifnot(all(table(search3_candidates$mandatory_control, search3_candidates$target)["TRUE", ] == 5L))
stopifnot(!anyDuplicated(app_glofas_search3_candidate_key(search3_candidates)))
stopifnot(all(search3_candidates$state_scaling == "train_zscore"))
stopifnot(all(search3_candidates$n_state_features[is.na(search3_candidates$source_candidate_id)] <= 3000L))

pass_a_folds <- app_glofas_search3_folds(search3_folds, "ridge_a")
score_fixture <- do.call(rbind, lapply(seq_len(nrow(search3_candidates)), function(i) {
  candidate <- search3_candidates[i, ]
  do.call(rbind, lapply(seq_len(nrow(pass_a_folds)), function(j) {
    fold <- pass_a_folds[j, ]
    do.call(rbind, lapply(c("primary_28", "secondary_30"), function(window) {
      data.frame(
        job_id = paste(candidate$candidate_id, fold$fold_id, window, sep = "__"),
        candidate_id = candidate$candidate_id, fold_id = fold$fold_id,
        target = candidate$target, method = "ridge", prior_id = NA_character_, seed = candidate$seed,
        score_window = window, mean_crps = 0.1 + i / 10000 + j / 100000,
        stringsAsFactors = FALSE
      )
    }))
  }))
}))
fit_fixture <- unique(score_fixture[, c("job_id", "candidate_id", "target", "method", "prior_id", "seed")])
fit_fixture$fit_completed <- TRUE
fit_fixture$terminal_certificate_pass <- TRUE
aggregate_fixture <- app_glofas_search3_phase_aggregate(score_fixture, pass_a_folds, fit_fixture)
stopifnot(nrow(aggregate_fixture) == 80L)
advanced_fixture <- app_glofas_search3_select_pass_a(aggregate_fixture, search3_candidates)
stopifnot(nrow(advanced_fixture) == 40L, all(table(advanced_fixture$target) == 20L))

priors_ref <- app_glofas_search3_rhs_priors("reference")
priors_dis <- app_glofas_search3_rhs_priors("discrepancy")
stopifnot(identical(priors_ref$m0, c(15, 25, 40)))
stopifnot(identical(priors_dis$m0, c(60, 100, 160)))
stopifnot(all(priors_dis$rhs_zeta2_fixed == 16))
rhs_jobs <- app_glofas_search3_rhs_jobs(
  search3_candidates[search3_candidates$target == "reference", ][1:3, ],
  app_glofas_search3_folds(search3_folds, "rhs_pilot"), priors_ref, "toy_rhs"
)
stopifnot(nrow(rhs_jobs) == 72L)
stopifnot(all(rhs_jobs$rhs_min_iter == 200L), all(rhs_jobs$rhs_max_iter == 200L))
stopifnot(all(rhs_jobs$rhs_freeze_beta_warmup_iters == 20L))
stopifnot(all(rhs_jobs$rhs_min_beta_updates == 180L))
stopifnot(all(rhs_jobs$terminal_consecutive_passes == 3L))

prior_score_fixture <- expand.grid(
  target = c("reference", "discrepancy"), prior_id = c("a", "b", "c"), replicate = 1:4,
  KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
)
prior_score_fixture$score_window <- "primary_28"
prior_score_fixture$mean_crps <- ifelse(prior_score_fixture$prior_id == "b", .09, .11)
selected_prior_fixture <- app_glofas_search3_select_prior(prior_score_fixture)
stopifnot(nrow(selected_prior_fixture) == 2L, all(selected_prior_fixture$prior_id == "b"))

cat("test_glofas_search3_rainy_season: OK\n")
