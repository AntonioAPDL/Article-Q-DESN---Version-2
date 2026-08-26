#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(
  dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])),
  "..", ".."
), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_discrepancy_transition.R"))
source(app_path("application/R/glofas_discrepancy_transition_campaign.R"))

args <- app_parse_args(list(
  output_root = "local_trackers/runtime_configs/glofas_nested_context_canary_20260826"
))
root <- if (grepl("^/", args$output_root)) args$output_root else app_path(args$output_root)
root <- normalizePath(root, mustWork = TRUE)
manifest <- app_read_csv(file.path(root, "runtime_manifest.csv"))
rows <- list()
traces <- list()
for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  if (!file.exists(file.path(row$run_dir[[1L]], ".fit_recovery_complete"))) {
    stop(sprintf("Canary is incomplete: %s", row$candidate_id[[1L]]), call. = FALSE)
  }
  grid <- app_read_csv(row$model_grid_path[[1L]])
  qrow <- grid[grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE]
  fit_path <- file.path(row$run_dir[[1L]], "objects", paste0(qrow$fit_id[[1L]], ".rds"))
  fit <- readRDS(fit_path)
  diagnostic_path <- file.path(row$run_dir[[1L]], "tables", "qdesn_discrepancy_fit_diagnostics.csv")
  diagnostics <- app_read_csv(diagnostic_path)
  score_path <- file.path(root, "scores", paste0(row$candidate_id[[1L]], "_observed_fit_scores.csv"))
  observed <- app_read_csv(score_path)
  observed <- observed[observed$window %in% c("all", "last1000", "last200", "last50"), , drop = FALSE]
  observed$candidate_id <- row$candidate_id[[1L]]
  rows[[length(rows) + 1L]] <- observed
  mechanism <- fit$vb_diagnostics$mechanism_trace %||% data.frame()
  mechanism$candidate_id <- row$candidate_id[[1L]]
  traces[[length(traces) + 1L]] <- mechanism
  if (nrow(diagnostics) != 1L || !nrow(mechanism)) {
    stop(sprintf("Canary diagnostics are incomplete: %s", row$candidate_id[[1L]]), call. = FALSE)
  }
}
observed <- app_bind_rows_fill(rows)
mechanism <- app_bind_rows_fill(traces)
app_write_csv(observed, file.path(root, "tables", "canary_observed_fit_scores.csv"))
app_write_csv(mechanism, file.path(root, "tables", "canary_mechanism_trace.csv"))

wide <- reshape(
  observed[, c("candidate_id", "window", "log1p_mae")],
  idvar = "window", timevar = "candidate_id", direction = "wide"
)
names(wide) <- sub("^log1p_mae[.]", "mae_", names(wide))
for (id in c("may_nested_ctx0100", "may_state_ctx0100")) {
  wide[[paste0("relative_vs_exact_", id)]] <-
    wide[[paste0("mae_", id)]] / wide$mae_may_exact_t01 - 1
}
app_write_csv(wide, file.path(root, "tables", "canary_observed_guardrails.csv"))
nested_all <- wide$relative_vs_exact_may_nested_ctx0100[wide$window == "all"]
nested_tail <- max(wide$relative_vs_exact_may_nested_ctx0100[wide$window != "all"], na.rm = TRUE)
state_all <- wide$relative_vs_exact_may_state_ctx0100[wide$window == "all"]
authorized <- length(nested_all) == 1L && is.finite(nested_all) && is.finite(nested_tail) &&
  nested_all <= 0.03 && nested_tail <= 0.05 &&
  is.finite(state_all) && nested_all < state_all
decision <- data.frame(
  stage = "may_nested_context_canary",
  stage1_authorized = authorized,
  nested_all_relative_change = nested_all,
  nested_worst_trailing_relative_change = nested_tail,
  state_all_relative_change = state_all,
  decision = if (authorized) "nested_transfer_preserves_observed_fit" else "stop_initialization_is_not_sufficient",
  stringsAsFactors = FALSE
)
app_write_csv(decision, file.path(root, "tables", "canary_decision.csv"))
writeLines(if (authorized) "authorized" else "stopped", file.path(root, if (authorized) ".stage1_authorized" else ".stage1_blocked"))
writeLines(format(Sys.time(), tz = "UTC", usetz = TRUE), file.path(root, ".canary_complete"))
