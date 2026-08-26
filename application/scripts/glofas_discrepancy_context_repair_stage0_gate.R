#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(
    dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])),
    "..", ".."
  ),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/glofas_discrepancy_transition.R"))
source(app_path("application/R/glofas_discrepancy_transition_campaign.R"))
source(app_path("application/R/glofas_discrepancy_context_repair_campaign.R"))

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_discrepancy_context_repair_20260825",
  policy_path = paste0(
    "application/config/",
    "glofas_discrepancy_context_repair_stage0_gate_amendment_20260825.yaml"
  )
))
output_root <- if (grepl("^/", args$output_root)) {
  normalizePath(args$output_root, mustWork = TRUE)
} else {
  normalizePath(app_path(args$output_root), mustWork = TRUE)
}
manifest <- app_read_csv(file.path(output_root, "runtime_manifest_stage0.csv"))
stage1_manifest <- app_read_csv(file.path(output_root, "runtime_manifest_stage1.csv"))
campaign <- app_read_yaml(file.path(output_root, "campaign_snapshot.yaml"))
policy_path <- if (grepl("^/", args$policy_path)) {
  normalizePath(args$policy_path, mustWork = TRUE)
} else {
  normalizePath(app_path(args$policy_path), mustWork = TRUE)
}
policy <- app_read_yaml(policy_path)
source_inventory <- app_read_csv(file.path(output_root, "source_fit_inventory.csv"))
if (nrow(manifest) != as.integer(campaign$execution$expected_stage0_fits)) {
  stop("Stage-0 manifest cardinality changed.", call. = FALSE)
}
if (!identical(
    as.character(policy$schema_version),
    "glofas_discrepancy_context_repair_stage0_gate_amendment_v1"
  ) || !identical(as.character(policy$campaign_id), as.character(campaign$campaign_id))) {
  stop("Stage-0 gate amendment identity is invalid.", call. = FALSE)
}
runtime_manifest_path <- file.path(output_root, "runtime_manifest.csv")
campaign_snapshot_path <- file.path(output_root, "campaign_snapshot.yaml")
if (!identical(
    app_sha256_file(runtime_manifest_path),
    as.character(policy$evidence_binding$runtime_manifest_sha256)
  ) || !identical(
    app_sha256_file(campaign_snapshot_path),
    as.character(policy$evidence_binding$campaign_snapshot_sha256)
  )) {
  stop("Stage-0 gate amendment does not match this runtime packet.", call. = FALSE)
}
dependency_audit <- app_glofas_context_repair_validate_stage1_dependency(
  stage1_manifest, policy
)
app_write_csv(
  dependency_audit,
  file.path(output_root, "tables", "stage1_warm_dependency_audit.csv")
)

initial_evidence <- c(
  "stage0_gate_summary.csv",
  "stage0_numerical_gate.csv",
  "stage0_source_score_comparison.csv"
)
if (file.exists(file.path(output_root, ".stage0_failed"))) {
  dir.create(file.path(output_root, "status"), recursive = TRUE, showWarnings = FALSE)
  failed_snapshot <- file.path(output_root, "status", "stage0_failed_initial.txt")
  if (!file.exists(failed_snapshot)) {
    file.copy(file.path(output_root, ".stage0_failed"), failed_snapshot)
  }
  for (name in initial_evidence) {
    source_path <- file.path(output_root, "tables", name)
    target_path <- file.path(
      output_root, "tables", sub("[.]csv$", "_initial.csv", name)
    )
    if (file.exists(source_path) && !file.exists(target_path)) {
      file.copy(source_path, target_path)
    }
  }
}

rows <- list()
score_rows <- list()
for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  run_dir <- row$run_dir[[1L]]
  if (!file.exists(file.path(run_dir, ".fit_recovery_complete"))) {
    stop(sprintf("Stage-0 run is not complete: %s.", row$candidate_id[[1L]]), call. = FALSE)
  }
  grid <- app_read_csv(row$model_grid_path[[1L]])
  qrow <- grid[grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  if (nrow(qrow) != 1L) stop("Stage-0 Q-DESN model row is nonunique.", call. = FALSE)
  fit_path <- file.path(run_dir, "objects", paste0(qrow$fit_id[[1L]], ".rds"))
  diagnostics_path <- file.path(run_dir, "tables", "qdesn_discrepancy_fit_diagnostics.csv")
  prediction_path <- file.path(run_dir, "tables", "prediction_quantiles.csv")
  if (!all(file.exists(c(fit_path, diagnostics_path, prediction_path)))) {
    stop(sprintf("Stage-0 evidence is incomplete for %s.", row$candidate_id[[1L]]), call. = FALSE)
  }
  if (!identical(app_sha256_file(row$warm_start_source_fit_object[[1L]]),
      row$warm_start_source_sha256[[1L]])) {
    stop(sprintf("Stage-0 source fit changed for %s.", row$candidate_id[[1L]]), call. = FALSE)
  }
  fit <- readRDS(fit_path)
  trace <- app_glofas_context_repair_trace_summary(fit)
  diagnostics <- app_read_csv(diagnostics_path)
  if (nrow(diagnostics) != 1L) stop("Stage-0 fit diagnostics are nonunique.", call. = FALSE)
  source <- source_inventory[
    source_inventory$source_candidate_id == row$warm_start_source_candidate[[1L]] &
      source_inventory$cutoff_id == row$cutoff_id[[1L]],
    ,
    drop = FALSE
  ]
  if (nrow(source) != 1L) stop("Stage-0 source inventory mapping failed.", call. = FALSE)
  source_fit <- readRDS(source$source_fit_object[[1L]])
  source_trace <- app_glofas_context_repair_trace_summary(source_fit)
  rows[[length(rows) + 1L]] <- cbind(
    data.frame(
      candidate_id = row$candidate_id[[1L]],
      base_candidate_id = row$base_candidate_id[[1L]],
      cutoff_id = row$cutoff_id[[1L]],
      fit_object = fit_path,
      fit_sha256 = app_sha256_file(fit_path),
      source_fit_object = source$source_fit_object[[1L]],
      source_fit_sha256 = source$source_fit_sha256[[1L]],
      source_vb_converged = source_trace$vb_converged[[1L]],
      source_vb_iterations = source_trace$vb_iterations[[1L]],
      warm_start_enabled = app_as_bool(diagnostics$vb_warm_start_enabled[[1L]]),
      warm_start_used = app_as_bool(diagnostics$vb_warm_start_used[[1L]]),
      warm_theta_used = app_as_bool(diagnostics$vb_warm_start_theta_used[[1L]]),
      warm_future_used = app_as_bool(diagnostics$vb_warm_start_future_used[[1L]]),
      warm_sigma_used = app_as_bool(diagnostics$vb_warm_start_sigma_used[[1L]]),
      warm_compatibility_class = as.character(
        diagnostics$vb_warm_start_compatibility_class[[1L]]
      ),
      warm_source_hash_matches = identical(
        as.character(diagnostics$vb_warm_start_source_sha256[[1L]]),
        as.character(source$source_fit_sha256[[1L]])
      ),
      finite_theta = app_as_bool(diagnostics$finite_theta[[1L]]),
      finite_sigma = app_as_bool(diagnostics$finite_sigma[[1L]]),
      stringsAsFactors = FALSE
    ),
    trace
  )
  scored <- app_glofas_transition_score_prediction_table(
    app_read_csv(prediction_path),
    candidate_id = row$base_candidate_id[[1L]],
    cutoff_id = row$cutoff_id[[1L]],
    selection_role = row$selection_role[[1L]]
  )
  score_rows[[length(score_rows) + 1L]] <- scored$summary
  rm(fit, source_fit)
  gc(FALSE)
}

audit <- app_bind_rows_fill(rows)
scores <- app_bind_rows_fill(score_rows)
audit$passes_warm_contract <- with(audit,
  warm_start_enabled & warm_start_used & warm_theta_used &
    warm_future_used & warm_sigma_used &
    warm_compatibility_class == "exact_design" & warm_source_hash_matches
)
audit$passes_finiteness <- audit$finite_theta & audit$finite_sigma
audit$passes_stage0_gate <- audit$passes_warm_contract &
  audit$passes_finiteness & audit$vb_numerical_gate
gate_decision <- app_glofas_context_repair_stage0_gate_decision(audit, policy)
audit <- gate_decision$audit
app_write_csv(audit, file.path(output_root, "tables", "stage0_numerical_gate.csv"))
app_write_csv(scores, file.path(output_root, "tables", "stage0_transition_scores.csv"))

aggregate <- app_glofas_transition_equal_origin_aggregate(scores)
t01 <- aggregate$future_p50_check_loss[aggregate$candidate_id == "t01_last"]
t10 <- aggregate$future_p50_check_loss[aggregate$candidate_id == "t10_last_gctx"]
if (length(t01) != 1L || length(t10) != 1L) {
  stop("Stage 0 lacks unique T01/T10 aggregate scores.", call. = FALSE)
}
summary <- cbind(gate_decision$summary, data.frame(
  t01_future_p50_check_loss = t01,
  t10_future_p50_check_loss = t10,
  t10_relative_gain_vs_t01 = (t01 - t10) / t01,
  checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stringsAsFactors = FALSE
))
app_write_csv(summary, file.path(output_root, "tables", "stage0_gate_summary.csv"))

source_root <- normalizePath(campaign$source_campaign$root, mustWork = TRUE)
source_scores_path <- file.path(source_root, "tables", "transition_run_scores.csv")
if (!file.exists(source_scores_path)) {
  stop("Frozen source transition scores are missing.", call. = FALSE)
}
source_scores <- app_read_csv(source_scores_path)
source_scores <- source_scores[
  source_scores$candidate_id %in% c("t01_last", "t10_last_gctx") &
    source_scores$selection_role == campaign$scoring$primary_origin_role,
  c("candidate_id", "cutoff_id", "future_p50_check_loss", "future_bias"),
  drop = FALSE
]
names(source_scores)[3:4] <- c(
  "source_future_p50_check_loss", "source_future_bias"
)
continuation_compare <- merge(
  scores,
  source_scores,
  by = c("candidate_id", "cutoff_id"),
  all.x = TRUE
)
continuation_compare$check_loss_change_from_source <-
  continuation_compare$future_p50_check_loss -
  continuation_compare$source_future_p50_check_loss
continuation_compare$bias_change_from_source <-
  continuation_compare$future_bias - continuation_compare$source_future_bias
app_write_csv(
  continuation_compare,
  file.path(output_root, "tables", "stage0_source_score_comparison.csv")
)
policy_snapshot <- file.path(output_root, "stage0_gate_policy_snapshot.yaml")
if (!file.copy(policy_path, policy_snapshot, overwrite = TRUE)) {
  stop("Could not snapshot the Stage-0 gate amendment.", call. = FALSE)
}
git_value <- function(args) {
  value <- system2("git", c("-C", repo_root, args), stdout = TRUE, stderr = TRUE)
  if (!length(value)) NA_character_ else value[[1L]]
}
resume_provenance <- data.frame(
  field = c(
    "resumed_at", "repo_head", "repo_tree", "repo_branch", "policy_path",
    "policy_sha256", "runtime_manifest_sha256", "campaign_snapshot_sha256",
    "stage0_numerical_gate_sha256", "stage0_source_score_comparison_sha256",
    "stage1_dependency_audit_sha256", "stage1_authorized"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    git_value(c("rev-parse", "HEAD")),
    git_value(c("rev-parse", "HEAD^{tree}")),
    git_value(c("rev-parse", "--abbrev-ref", "HEAD")),
    policy_path,
    app_sha256_file(policy_snapshot),
    app_sha256_file(runtime_manifest_path),
    app_sha256_file(campaign_snapshot_path),
    app_sha256_file(file.path(output_root, "tables", "stage0_numerical_gate.csv")),
    app_sha256_file(file.path(output_root, "tables", "stage0_source_score_comparison.csv")),
    app_sha256_file(file.path(output_root, "tables", "stage1_warm_dependency_audit.csv")),
    as.character(summary$stage1_authorized[[1L]])
  ),
  stringsAsFactors = FALSE
)
app_write_csv(
  resume_provenance,
  file.path(output_root, "stage0_gate_resume_provenance.csv")
)
if (!isTRUE(summary$stage1_authorized[[1L]])) {
  writeLines(
    "Stage 0 failed; Stage 1 is not authorized.",
    file.path(output_root, ".stage0_failed")
  )
  stop("Stage 0 did not pass its frozen numerical and warm-start gate.", call. = FALSE)
}
if (file.exists(file.path(output_root, ".stage0_failed"))) {
  unlink(file.path(output_root, ".stage0_failed"))
}
writeLines(
  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  file.path(output_root, ".stage0_passed")
)
cat(file.path(output_root, "tables", "stage0_gate_summary.csv"), "\n")
