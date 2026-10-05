#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep(
  "^--file=", commandArgs(FALSE), value = TRUE
)[1L]))), "_joint_qdesn_recursive_mean_forecast_bootstrap.R"))
args <- app_parse_args(list(root = NA_character_, source_root = NA_character_,
  baseline_root = NA_character_, out_dir = NA_character_,
  review_contract_path = NA_character_))
argument <- function(name) args[[gsub("_", "-", name)]] %||% args[[name]]
root <- normalizePath(argument("root"), mustWork = TRUE)
source_root <- normalizePath(argument("source_root"), mustWork = TRUE)
baseline <- normalizePath(argument("baseline_root"), mustWork = TRUE)
out <- argument("out_dir")
review_path <- normalizePath(argument("review_contract_path"), mustWork = TRUE)
if (is.na(out) || !nzchar(out)) stop("Provide --out-dir.", call. = FALSE)
app_ensure_dir(out)
out <- normalizePath(out, mustWork = TRUE)
if (out %in% c(root, source_root, baseline)) {
  stop("The audit output must be separate from its source roots.", call. = FALSE)
}
read <- function(base, path) app_read_csv(file.path(base, path))
write <- function(x, name) app_write_csv(x, file.path(out, name))
checks <- list()
verify <- function(base, path, payload_base = dirname(file.path(base, path))) {
  manifest <- read(base, path)
  app_check_required_columns(manifest, c("relative_path", "size_bytes", "sha256"), path)
  paths <- file.path(payload_base, manifest$relative_path)
  stopifnot(nrow(manifest) > 0L, !anyDuplicated(manifest$relative_path),
    all(file.exists(paths)),
    all(as.numeric(file.info(paths)$size) == as.numeric(manifest$size_bytes)),
    all(tolower(unname(tools::sha256sum(paths))) == tolower(manifest$sha256)))
  checks[[length(checks) + 1L]] <<- data.frame(
    root = base, manifest = path, manifest_sha256 = app_sha256_file(file.path(base, path)),
    verified_payloads = nrow(manifest), status = "pass")
}
stopifnot(file.exists(file.path(root, "final_packet/DONE")),
  file.exists(file.path(baseline, "final_packet/DONE")))
verify(root, "final_packet/artifact_manifest.csv")
verify(baseline, "final_packet/artifact_manifest.csv")
verify(source_root, "mcmc_final_artifact_manifest.csv")
verify(source_root, "vb_final_artifact_manifest.csv")
verify(source_root, "mcmc_worker_artifact_registry.csv")
verify(source_root, "vb_worker_artifact_registry.csv")
verify(root, "source_inventory.csv", source_root)
verify(root, "dgp_oracle_manifest.csv")
plan <- read(root, "cell_plan.csv")
summary <- read(root, "final_packet/forecast_score_summary.csv")
prior <- read(baseline, "final_packet/forecast_score_summary.csv")
keys <- c("scenario_id", "model_cell_id", "inference_method")
key <- function(x) do.call(paste, c(x[keys], sep = "|"))
stopifnot(nrow(plan) == 64L, nrow(summary) == 64L, nrow(prior) == 64L,
  !anyDuplicated(key(summary)), !anyDuplicated(key(prior)),
  setequal(key(summary), key(prior)),
  all(table(summary$inference_method) == 32L),
  all(table(summary$scenario_id, summary$inference_method) == 4L),
  all(is.finite(summary$posterior_score_mean)),
  all(is.finite(summary$path_posterior_score_mean)),
  all(is.finite(summary$posterior_score_q025)),
  all(is.finite(summary$posterior_score_q975)),
  all(summary$canonical_contract_crossing_pairs == 0L),
  all(plan$protected_rows_used_for_selection == 0L),
  !any(app_as_bool_vec(plan$article_fixture_used_for_selection)),
  !any(app_as_bool_vec(plan$raw_inputs_in_readout)),
  all(app_as_bool_vec(plan$full_states_all_layers)))
for (worker in plan$worker_id) {
  verify(app_joint_recursive_cell_dir(root, worker), "artifact_manifest.csv")
}
registry <- read(source_root, "mcmc_posterior_summary_registry.csv")
chain_plan <- read(source_root, "mcmc_worker_plan.csv")
expected <- chain_plan[match(registry$worker_id, chain_plan$worker_id), ]
stopifnot(nrow(registry) == 160L, all(table(registry$model_cell_id) == 5L),
  all(registry$n_iter == expected$n_iter), all(registry$burn == expected$burn),
  all(registry$thin == expected$thin), all(registry$n_keep == expected$n_keep),
  all(registry$inference_method_id[registry$likelihood_family == "exAL"] ==
    "M0_v_collapsed_support_logit"))
for (worker in registry$worker_id) {
  verify(file.path(source_root, "mcmc_workers", sprintf("worker_%04d", worker)),
    "artifact_manifest.csv")
}
targets <- read(source_root, "mcmc_posterior_target_hash_audit.csv")
stopifnot(nrow(targets) == 32L, all(targets$n_chains == 5L),
  all(app_as_bool_vec(targets$verified)))
crossings <- read(root, "final_packet/crossing_summary.csv")
stopifnot(all(crossings$posterior_contract_crossing_pairs_max == 0L),
  all(crossings$path_posterior_contract_crossing_pairs_max == 0L))
diagnostics <- read(root, "final_packet/mean_design_diagnostics.csv")
contract <- app_joint_recursive_read_contract(file.path(root, "frozen_contract.csv"))
decision <- app_joint_recursive_final_score_stability(diagnostics, contract,
  allowed_review_contract_sha256 = app_sha256_file(review_path))
status <- read(root, "final_packet/packet_status.csv")
stopifnot(all(decision$accepted), sum(decision$strict_pass) == 63L,
  sum(decision$review_valid) == 1L,
  status$status[[1L]] == "COMPLETE_WITH_ONE_SCORE_STABILITY_REVIEW")
backbones <- read(root, "selected_backbones.csv")
old_backbones <- read(baseline, "selected_backbones.csv")
stopifnot(nrow(backbones) == 8L, nrow(old_backbones) == 8L,
  all(vapply(split(plan$architecture_signature, plan$scenario_id),
    function(x) length(unique(x)) == 1L, logical(1L))))
specs <- merge(backbones, old_backbones, by = "scenario_id", suffixes = c("", "_baseline"))
specs$specification_changed <- specs$architecture_signature != specs$architecture_signature_baseline |
  specs$rhs_tau0 != specs$rhs_tau0_baseline
stopifnot(sum(specs$specification_changed) == 2L)
write(specs, "specification_comparison.csv")
comparison <- merge(summary, prior, by = keys, suffixes = c("", "_baseline"))
comparison$specification_changed <- specs$specification_changed[
  match(comparison$scenario_id, specs$scenario_id)]
comparison$mean_difference <- comparison$posterior_score_mean - comparison$posterior_score_mean_baseline
comparison$mean_change_percent <- 100 * comparison$mean_difference /
  comparison$posterior_score_mean_baseline
comparison$interval_width_ratio <- comparison$posterior_score_interval_width /
  comparison$posterior_score_interval_width_baseline
comparison$intervals_overlap_baseline <- comparison$posterior_score_q025 <=
  comparison$posterior_score_q975_baseline & comparison$posterior_score_q975 >=
  comparison$posterior_score_q025_baseline
comparison$lower_mean_candidate <- comparison$mean_difference < 0
comparison$interpretation <- ifelse(!comparison$specification_changed,
  "verified_unchanged_reuse", ifelse(comparison$lower_mean_candidate,
    "lower_mean_descriptive_candidate", "higher_mean_report_regression"))
stopifnot(all(comparison$mean_difference[!comparison$specification_changed] == 0))
write(comparison, "complete_packet_comparison.csv")
write(comparison[comparison$inference_method == "mcmc", ], "mcmc_comparison.csv")
write(comparison[comparison$specification_changed, ], "changed_case_comparison.csv")
policy <- summary[, c(keys, "posterior_score_mean", "posterior_score_interval_width",
  "path_posterior_score_mean", "path_posterior_score_interval_width")]
policy$mean_state_minus_path_mean <- policy$posterior_score_mean - policy$path_posterior_score_mean
policy$mean_state_to_path_width_ratio <- policy$posterior_score_interval_width /
  policy$path_posterior_score_interval_width
write(policy, "recursive_policy_comparison.csv")
contrasts <- read(root, "final_packet/posterior_contrast_summary.csv")
contrasts$interpretation <- ifelse(contrasts$q975_difference < 0,
  "left_lower_under_descriptive_coupling", ifelse(contrasts$q025_difference > 0,
    "right_lower_under_descriptive_coupling", "interval_includes_zero"))
write(contrasts, "posterior_contrasts.csv")
winners <- app_joint_qdesn_bind_rows(lapply(split(summary,
  interaction(summary$scenario_id, summary$inference_method, drop = TRUE)), function(x) {
    x <- x[order(x$posterior_score_mean), ]
    data.frame(scenario_id = x$scenario_id[[1L]], inference_method = x$inference_method[[1L]],
      winner = x$model_cell_id[[1L]], runner_up = x$model_cell_id[[2L]],
      winner_mean = x$posterior_score_mean[[1L]], runner_up_mean = x$posterior_score_mean[[2L]],
      winner_runner_intervals_overlap = x$posterior_score_q975[[1L]] >= x$posterior_score_q025[[2L]],
      claim_scope = "descriptive_numerical_minimum")
  }))
write(winners, "winner_comparison.csv")
fit_rows <- lapply(seq_len(nrow(plan)), function(i) {
  row <- plan[i, ]
  design <- readRDS(file.path(source_root, row$design_relative_path[[1L]]))
  if (row$inference_method[[1L]] == "vb") {
    init <- readRDS(file.path(source_root, row$initializer_relative_path[[1L]]))
    qhat <- app_joint_qdesn_predict_fit(init, design$Z[design$fit_local, , drop = FALSE], design$tau)
  } else {
    chains <- registry$worker_id[registry$model_cell_id == row$model_cell_id[[1L]]]
    matrices <- lapply(chains, function(j) as.matrix(read(source_root,
      file.path("mcmc_workers", sprintf("worker_%04d", j), "qhat_fit_mean.csv"))))
    qhat <- Reduce(`+`, matrices) / length(matrices)
  }
  truth <- design$true_q[design$fit_local, , drop = FALSE]
  stopifnot(identical(dim(qhat), dim(truth)), all(is.finite(qhat)))
  action <- app_joint_qdesn_apply_monotone_contract(qhat, design$tau)
  cbind(row[, keys], data.frame(fit_oracle_mae = mean(abs(action$qhat_contract - truth)),
    fit_oracle_rmse = sqrt(mean((action$qhat_contract - truth)^2)),
    fit_raw_crossing_pairs = sum(action$raw_crossing$n_crossing_pairs),
    fit_contract_crossing_pairs = sum(action$contract_crossing$n_crossing_pairs),
    scope = "canonical_posterior_mean_action_oracle_diagnostic"))
})
fit <- app_joint_qdesn_bind_rows(fit_rows)
stopifnot(nrow(fit) == 64L, all(is.finite(fit$fit_oracle_mae)),
  all(fit$fit_contract_crossing_pairs == 0L))
write(fit, "fit_oracle_diagnostics.csv")
repairs <- data.frame(workers_with_repairs = sum(registry$precision_repair_count > 0),
  total_repairs = sum(registry$precision_repair_count),
  max_relative_jitter = max(registry$precision_repair_max_relative_jitter),
  exal_M0_workers = sum(registry$likelihood_family == "exAL"))
write(repairs, "sampler_audit.csv")
lane_parent <- dirname(repo_root)
lane_names <- c("joint_pure_desn_expanded_screen_20260925",
  "joint_pure_desn_expanded_continuation_20261003",
  "joint_pure_desn_recursive_selection_20260925",
  "joint_pure_desn_expanded_score_closeout_20261004",
  "joint_pure_desn_score_review_closeout_20261002")
lane_roots <- file.path(lane_parent, paste0("Article-Q-DESN---Version-2__wt__", lane_names))
payloads <- unique(unlist(lapply(lane_roots, function(d) {
  unlist(lapply(file.path(d, c("application/cache", "local_trackers")), function(p) {
    list.files(p, pattern = "[.](rds|rda|rdata|csv[.]gz)$", ignore.case = TRUE,
      full.names = TRUE, recursive = TRUE)
  }), use.names = FALSE)
}), use.names = FALSE))
info <- file.info(payloads)
storage <- data.frame(path = payloads, size_bytes = as.numeric(info$size),
  modified_at_utc = format(info$mtime, tz = "UTC", usetz = TRUE),
  within_last_four_weeks = info$mtime >= as.POSIXct("2026-09-07", tz = "UTC"),
  action = "retain_dependency_or_scientific_evidence", stringsAsFactors = FALSE)
duplicate <- startsWith(storage$path, paste0(baseline, "/oracle_banks/")) |
  (startsWith(storage$path, paste0(baseline, "/oracle_shards/")) &
    basename(storage$path) == "oracle_shard.rds")
storage$action[duplicate] <- "eligible_only_after_byte_identical_cleanup_audit"
write(storage, "storage_file_inventory.csv")
write(aggregate(storage$size_bytes, list(action = storage$action), sum),
  "storage_summary.csv")
write(app_joint_qdesn_bind_rows(checks), "manifest_audit.csv")
hash_sources <- c(file.path(root, "frozen_contract.csv"), file.path(root, "cell_plan.csv"),
  review_path, file.path(root, "final_packet/artifact_manifest.csv"),
  file.path(baseline, "final_packet/artifact_manifest.csv"))
write(data.frame(path = hash_sources, sha256 = unname(tools::sha256sum(hash_sources))),
  "source_hashes.csv")
mcmc_changed <- comparison[comparison$inference_method == "mcmc" & comparison$specification_changed, ]
report <- c("# Frozen JOINT expanded-continuation comparison", "",
  "All 64 score cells are complete: 32 VB and 32 MCMC; 63 strict stability passes and one bounded review.",
  "Every exAL MCMC worker uses exact M0. The primary metric is DGP-integrated finite-grid aCRPS.",
  "The baseline is the previous frozen narrow pure-DESN packet, not automatic published-article authority.",
  "The six reused scenarios match exactly; two scenarios have new specifications selected within the observational window.",
  "The protected article window did not select the specifications. Forecast gains and regressions are reported together.", "",
  sprintf("Changed MCMC cells with lower means: %d / %d.", sum(mcmc_changed$lower_mean_candidate), nrow(mcmc_changed)),
  "", "| Case | Model | Old Mean | New Mean | Change | 95% Intervals Overlap |", "|---|---|---:|---:|---:|---|",
  vapply(seq_len(nrow(mcmc_changed)), function(i) {
    x <- mcmc_changed[i, ]
    sprintf("| %s | %s %s | %.6f | %.6f | %+.2f%% | %s |", x$scenario_id,
      x$fit_structure, x$likelihood_family, x$posterior_score_mean_baseline,
      x$posterior_score_mean, x$mean_change_percent, x$intervals_overlap_baseline)
  }, character(1L)), "",
  "The one stability review is Laplace Bridge joint AL MCMC; its original strict failure remains archived.",
  "VB intervals omit intercept covariance and are partial; MCMC intervals are conditional on each recursive policy.",
  "Joint-versus-independent contrasts use deterministic index coupling and are descriptive posterior comparisons.",
  "Scalar mixing remains a diagnostic; poor scalar mixing alone does not veto a finite, stable predictive result.",
  "Lower-mean rows are integration-review candidates. Publication needs a coherent packet decision and must retain regressions.",
  "Fit MAE/RMSE are canonical oracle diagnostics; they are not forecast scores or posterior score intervals.")
writeLines(report, file.path(out, "COMPARISON.md"))
paths <- list.files(out, full.names = TRUE)
paths <- paths[!basename(paths) %in% c("artifact_manifest.csv", "artifact_manifest_verification.csv", "DONE")]
app_joint_shared_write_manifest(out, setNames(paths, basename(paths)))
verification <- app_joint_shared_verify_manifest(out)
stopifnot(all(app_as_bool_vec(verification$verified)))
write(verification, "artifact_manifest_verification.csv")
file.create(file.path(out, "DONE"))
cat(sprintf("JOINT_AUDIT_COMPLETE cells=%d manifests=%d lower_mean_changed_mcmc=%d/%d out=%s\n",
  nrow(summary), length(checks), sum(mcmc_changed$lower_mean_candidate), nrow(mcmc_changed), out))
