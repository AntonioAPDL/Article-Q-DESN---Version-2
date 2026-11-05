# Pure generated specification/replay metadata; zero files or model objects read.
local({
  source("scripts/diagnostics/glofas_specification_reconciliation.R", local = TRUE)
  checks <- 0L
  ok <- function(x) { stopifnot(isTRUE(x)); checks <<- checks + 1L; invisible(TRUE) }
  reject <- function(expr, text = NULL) {
    err <- tryCatch({ force(expr); NULL }, error = function(e) e)
    ok(inherits(err, "error")); if (!is.null(text)) ok(grepl(text, conditionMessage(err), fixed = TRUE))
  }
  decision <- list(schema_version = "glofas_specification_decision_v1", decision_id = "generated_preserve",
    authority = "explicit_author_instruction", instruction_reference = "generated explicit instruction fixture",
    policy = "preserve_executed", scope = "specification_reconciliation_and_preflight_only",
    allow_model_runs = FALSE, allow_scoring = FALSE, allow_article_changes = FALSE)
  selected <- data.frame(component = c("reference", "discrepancy"),
    candidate_id = c("search3_ref_001", "search3_dis_007"), D = 1L, n_vector = c("1500", "1000"),
    n_state_features = c(1500L, 1000L), m = c(540L, 180L), output_lag_max = c(540L, 180L),
    covariate_lag_max = c(90L, 180L), input_dimension = c(722L, 542L), washout = 500L,
    alpha = c(.75, .85), rho = c(.6, .2), canonical_seed = c(20260512L, 20261521L),
    seed = c(20260512L, 20261521L), pi_w = c(.1, .003), pi_in = .1,
    effective_input_gain = c(.5, .35), standardize_inputs = TRUE, state_scaling = "train_zscore",
    input_bound = "none", act_f = "tanh", act_k = "identity", stringsAsFactors = FALSE)
  selected$win_scale_global <- selected$effective_input_gain / sqrt(selected$pi_in * selected$input_dimension)
  selected$win_scale_bias <- selected$win_scale_global
  executed <- selected
  executed$win_scale_global <- executed$effective_input_gain; executed$win_scale_bias <- 1
  executed$canonical_seed <- executed$effective_input_gain <- executed$input_dimension <- executed$D <- NULL
  result <- app_glofas_reconcile_specification(selected, executed, "preserve_executed", decision)
  ok(result$status == "RECONCILED_NOT_A_MODEL_CHANGE" && result$specification_basis == "executed_frozen_v1")
  ok(all(result$shared_feature_checks$pass) && nrow(result$shared_feature_checks) == 40L)
  ok(!result$screened_and_executed_feature_maps_identical && !result$selected_registry_is_execution_identity)
  ok(all(result$authorized_specification$win_scale_global == c(.5, .35)))
  ok(max(abs(result$gain_comparison$expected_screened_scale - c(.0588438941447313, .0475410096808641))) < 1e-15)
  ok(max(abs(result$gain_comparison$global_multiplier_ratio - sqrt(c(72.2, 54.2)))) < 1e-12)
  ok(max(abs(result$gain_comparison$bias_multiplier_ratio - 1 / selected$win_scale_global)) < 1e-12)
  ok(result$original_RDS_reads == 0L && result$model_runs == 0L && result$weights_generated == 0L &&
    !result$forecast_losses_used_for_decision && !result$future_USGS_accessed)
  # Historical anchors name their component by role rather than component.
  anchors <- executed; anchors$role <- paste0(anchors$component, "_anchor"); anchors$component <- NULL
  anchors <- anchors[2:1, , drop = FALSE]
  by_role <- app_glofas_reconcile_specification(selected[2:1, ], anchors, "preserve_executed", decision)
  ok(identical(by_role$authorized_specification, result$authorized_specification))
  # Additional selected training-score fields are ignored, not used for choice.
  scores <- selected; scores$mean_primary_crps <- c(999, -999)
  ok(identical(app_glofas_reconcile_specification(scores, executed, "preserve_executed", decision), result))
  hash <- strrep("a", 64L)
  block <- function(row) list(depth = 1L, layer_widths = as.numeric(row$n_state_features),
    input_dimension = as.numeric(row$input_dimension), history_last_date = "2022-12-25", history_length = 12995L,
    W_sha256 = hash, Win_sha256 = hash, reducers_sha256 = hash, last_states_sha256 = hash,
    input_spec_sha256 = hash, feature_metadata_sha256 = hash, config_sha256 = hash,
    scaler_sha256 = hash, historical_values_sha256 = hash,
    actual_meta = list(win_scale_global = row$win_scale_global, win_scale_bias = row$win_scale_bias,
      standardize_inputs = row$standardize_inputs, input_bound = row$input_bound,
      alpha = row$alpha, act_f = row$act_f, act_k = row$act_k))
  replay <- list(status = "PASS_FEATURE_REPLAY_ONLY_NOT_POSTERIOR_ACCURACY", context_unchanged = TRUE,
    RNG_unchanged = TRUE, forbidden_calls = 0L, saved_callback_calls = 0L, applied_updates = 0L,
    future_truth_read = FALSE, actual_context_identity = list(context_sha256 = hash,
      covariate_timeline_sha256 = hash, issued_member_rows_sha256 = hash,
      blocks = list(beta = block(result$executed_specification[1L, ]),
        alpha = block(result$executed_specification[2L, ]))))
  bound <- app_glofas_bind_executed_replay(result, replay)
  ok(bound$executed_numeric_replay_bound && all(bound$replay_checks$pass) && nrow(bound$replay_checks) == 14L)
  proof <- app_glofas_assert_specification_basis(bound$authorized_specification, bound,
    "preserve_executed", "executed_frozen_v1", bound$frozen_numeric_identity)
  ok(proof$status == "SPECIFICATION_PREFLIGHT_PASS_NOT_RUN_AUTHORIZATION" &&
    !proof$allow_model_runs && !proof$allow_scoring && !proof$allow_article_changes)
  wrong <- bound$authorized_specification; wrong$win_scale_global <- selected$win_scale_global
  reject(app_glofas_assert_specification_basis(wrong, bound, "preserve_executed", "executed_frozen_v1",
    bound$frozen_numeric_identity), "changes the explicitly authorized")
  reject(app_glofas_assert_specification_basis(bound$authorized_specification, bound,
    "preserve_executed", "screened_normalized_v1", bound$frozen_numeric_identity), "policy/basis")
  reject(app_glofas_assert_specification_basis(bound$authorized_specification, bound,
    "preserve_executed", "executed_frozen_v1", NULL), "exact frozen numeric")
  wrong_identity <- bound$frozen_numeric_identity; wrong_identity$blocks$beta$Win_sha256 <- strrep("b", 64L)
  reject(app_glofas_assert_specification_basis(bound$authorized_specification, bound,
    "preserve_executed", "executed_frozen_v1", wrong_identity), "exact frozen numeric")
  alternate <- decision; alternate$policy <- "restore_screened"
  restored <- app_glofas_reconcile_specification(selected, executed, "restore_screened", alternate)
  ok(restored$specification_basis == "screened_normalized_v1" && !restored$can_reuse_executed_numeric_design)
  proof <- app_glofas_assert_specification_basis(restored$authorized_specification, restored,
    "restore_screened", "screened_normalized_v1", NULL)
  ok(!proof$allow_model_runs)
  reject(app_glofas_assert_specification_basis(restored$authorized_specification, restored,
    "restore_screened", "screened_normalized_v1", bound$frozen_numeric_identity), "cannot claim executed")
  reject(app_glofas_reconcile_specification(selected, executed, NULL, decision), "unambiguous")
  reject(app_glofas_reconcile_specification(selected, executed, "best_score", decision), "unambiguous")
  reject(app_glofas_reconcile_specification(selected, executed, "restore_screened", decision), "author decision")
  bad_decision <- decision; bad_decision$allow_model_runs <- TRUE
  reject(app_glofas_reconcile_specification(selected, executed, "preserve_executed", bad_decision), "no-run")
  bad <- selected; bad$component <- "reference"
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "duplicate or missing")
  bad <- selected; bad$target <- rev(bad$component)
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "conflicting component")
  bad <- selected; names(bad)[2L] <- names(bad)[1L]
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "unique-field")
  bad <- selected; bad$win_scale_bias <- NULL
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "missing screened")
  bad <- selected; bad$win_scale_global[1L] <- .5
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "normalization")
  for (field in c("effective_input_gain", "win_scale_global", "win_scale_bias", "pi_in", "alpha", "rho", "seed")) {
    bad <- selected; bad[[field]][1L] <- Inf
    reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "finite")
  }
  bad <- executed; bad$win_scale_bias[1L] <- .5
  reject(app_glofas_reconcile_specification(selected, bad, "preserve_executed", decision), "bias-one")
  bad <- executed; bad$alpha[1L] <- .5
  reject(app_glofas_reconcile_specification(selected, bad, "preserve_executed", decision), "shared feature")
  bad <- selected; bad$input_dimension[1L] <- 723L
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "dimension disagrees")
  bad <- selected; bad$n_vector[1L] <- "1500;1000"
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "one-layer")
  bad <- selected; bad$canonical_seed[1L] <- 99L
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "conflicting seed")
  bad <- selected; bad$standardize_inputs[1L] <- "sometimes"
  reject(app_glofas_reconcile_specification(bad, executed, "preserve_executed", decision), "Boolean")
  bad_replay <- replay; bad_replay$future_truth_read <- TRUE
  reject(app_glofas_bind_executed_replay(result, bad_replay), "truth-free")
  bad_replay <- replay; bad_replay$actual_context_identity$blocks$beta$actual_meta$win_scale_global <- selected$win_scale_global[1L]
  reject(app_glofas_bind_executed_replay(result, bad_replay), "actual win_scale_global")
  bad_replay <- replay; bad_replay$actual_context_identity$blocks$beta$Win_sha256 <- "invalid"
  reject(app_glofas_bind_executed_replay(result, bad_replay), "fingerprints")
  bad_replay <- replay; bad_replay$actual_context_identity$blocks$alpha$history_last_date <- "2023-01-01"
  reject(app_glofas_bind_executed_replay(result, bad_replay), "dimensions/date")
  source("scripts/audit_glofas_specification_reconciliation.R", local = TRUE)
  scratch <- tempfile("gsr_generated_"); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  ok(system2("/usr/bin/git", c("init", "--quiet", shQuote(scratch))) == 0L)
  writeLines("local_trackers/", file.path(scratch, ".gitignore"))
  dir.create(file.path(scratch, "local_trackers"))
  fresh <- file.path(scratch, "local_trackers", "new_audit")
  app_gsr_audit_output(scratch, fresh); ok(!file.exists(fresh))
  dir.create(fresh)
  reject(app_gsr_audit_output(scratch, fresh), "fresh ignored")
  linked <- file.path(scratch, "local_trackers", "linked_audit")
  ok(file.symlink(fresh, linked))
  reject(app_gsr_audit_output(scratch, linked), "symlink")
  reject(app_gsr_audit_output(scratch, file.path(linked, "new_audit")), "symlink")
  reject(app_gsr_audit_output(scratch, file.path(scratch, "local_trackers", "missing", "new_audit")),
    "missing metadata")
  meta <- file.path(scratch, "tiny.json"); writeLines("{}", meta)
  pinned <- app_gsr_audit_pin(meta, unname(tools::sha256sum(meta)), ".json")
  ok(pinned$size_bytes > 0 && pinned$size_bytes < 10)
  reject(app_gsr_audit_pin(meta, strrep("0", 64L), ".json"), "hash changed")
  linked_meta <- file.path(scratch, "linked.json"); ok(file.symlink(meta, linked_meta))
  reject(app_gsr_audit_pin(linked_meta), "symlink")
  reject(app_gsr_audit_pin(file.path(scratch, "does_not_exist.json")), "missing metadata")
  reject(app_gsr_audit_pin(file.path(scratch, "never_opened.rds")), "non-RDS")
  help <- system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "scripts/audit_glofas_specification_reconciliation.R", "--help"), stdout = TRUE)
  ok(is.null(attr(help, "status")) && any(grepl("--selected-sha256", help, fixed = TRUE)))
  cat(sprintf("PASS: GloFAS specification reconciliation (%d generated checks; zero RDS reads or model runs)\n", checks))
})
