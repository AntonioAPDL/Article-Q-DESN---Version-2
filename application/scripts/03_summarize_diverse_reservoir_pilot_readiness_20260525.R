#!/usr/bin/env Rscript
# Purpose: combine the prepared diverse candidate table, exact launch-seed
# reservoir screen, and sampler-free design validation into one compact
# launch-readiness summary. This script is read-only with respect to run
# artifacts and does not launch model fitting.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  batch = "application/config/glofas_diverse_reservoir_pilot_batch_20260525.csv",
  validation = "application/config/glofas_diverse_reservoir_pilot_batch_20260525_validation.csv",
  reservoir_screen_run_id = "reservoir_diverse8_exact_seed_20260525",
  output = "application/config/glofas_diverse_reservoir_pilot_batch_20260525_readiness.csv"
))

batch <- app_read_csv(app_resolve_path(args$batch, must_work = TRUE))
validation <- app_read_csv(app_resolve_path(args$validation, must_work = TRUE))

screen_dir <- app_path("application/runs", args$reservoir_screen_run_id)
screen_summary_path <- file.path(screen_dir, "tables", "reservoir_screening_architecture_summary.csv")
if (!file.exists(screen_summary_path)) {
  stop(sprintf("Missing exact reservoir-screen architecture summary: %s.", screen_summary_path), call. = FALSE)
}
screen <- app_read_csv(screen_summary_path)

read_design_summary <- function(path) {
  if (!file.exists(path)) return(data.frame())
  x <- app_read_csv(path)
  if (!nrow(x)) return(data.frame())
  x[1L, , drop = FALSE]
}

design_rows <- lapply(seq_len(nrow(validation)), function(i) {
  row <- validation[i, , drop = FALSE]
  dsum <- read_design_summary(app_path(row$design_preflight_path[[1L]]))
  if (!nrow(dsum)) {
    return(data.frame(
      spec_id = row$spec_id[[1L]],
      n_stacked_rows = NA_integer_,
      n_augmented_features = NA_integer_,
      n_beta_features = NA_integer_,
      n_alpha_features = NA_integer_,
      n_reservoir_features = NA_integer_,
      n_reservoir_input_output_lag_features = NA_integer_,
      n_reservoir_input_covariate_lag_features = NA_integer_,
      horizon_max = NA_integer_,
      design_hash = NA_character_,
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    spec_id = row$spec_id[[1L]],
    n_stacked_rows = dsum$n_stacked_rows[[1L]],
    n_augmented_features = dsum$n_augmented_features[[1L]],
    n_beta_features = dsum$n_beta_features[[1L]],
    n_alpha_features = dsum$n_alpha_features[[1L]],
    n_reservoir_features = dsum$n_reservoir_features[[1L]],
    n_reservoir_input_output_lag_features = dsum$n_reservoir_input_output_lag_features[[1L]],
    n_reservoir_input_covariate_lag_features = dsum$n_reservoir_input_covariate_lag_features[[1L]],
    horizon_max = dsum$horizon_max[[1L]],
    design_hash = dsum$design_hash[[1L]],
    stringsAsFactors = FALSE
  )
})
design <- app_bind_rows_fill(design_rows)

cols_screen <- intersect(
  c(
    "spec_id", "decision", "pass_rate", "repair_rate", "fail_rate",
    "accepted_seeds", "repair_seeds", "rejected_seeds", "recommended_seed_ids",
    "median_relative_effective_rank_entropy", "median_condition_cov"
  ),
  names(screen)
)
screen_small <- screen[, cols_screen, drop = FALSE]
names(screen_small) <- sub("^decision$", "exact_seed_screen_decision", names(screen_small))
names(screen_small) <- sub("^fail_rate$", "exact_seed_fail_rate", names(screen_small))
names(screen_small) <- sub("^accepted_seeds$", "exact_seed_accepted_seeds", names(screen_small))
names(screen_small) <- sub("^rejected_seeds$", "exact_seed_rejected_seeds", names(screen_small))

out <- merge(batch, screen_small, by = "spec_id", all.x = TRUE, sort = FALSE)
out <- merge(
  out,
  validation[, c("spec_id", "validation_status", "run_id", "run_dir", "check_inputs_exit", "build_panel_exit", "design_check_exit", "design_check_seconds"), drop = FALSE],
  by = "spec_id",
  all.x = TRUE,
  sort = FALSE
)
out <- merge(out, design, by = "spec_id", all.x = TRUE, sort = FALSE)
out <- out[order(as.integer(out$pilot_rank)), , drop = FALSE]

out$launch_gate_status <- ifelse(
  out$multiseed_decision %in% c("pass", "repair") &
    out$multiseed_triage_class == "main_admissible" &
    out$exact_seed_screen_decision %in% c("pass", "repair") &
    out$validation_status == "passed" &
    as.integer(out$check_inputs_exit) == 0L &
    as.integer(out$build_panel_exit) == 0L &
    as.integer(out$design_check_exit) == 0L,
  "ready_for_explicit_launch_decision",
  "not_ready"
)

ordered_cols <- c(
  "pilot_rank", "spec_id", "pilot_role", "launch_gate_status",
  "config_path", "model_grid_path", "run_id_template",
  "D", "n_vector", "total_units", "n_tilde", "m", "washout",
  "alpha", "rho", "pi_w", "pi_in", "win_scale_global", "win_scale_bias",
  "launch_seed", "rhs_tau0", "vb_max_iter", "vb_n_draws",
  "multiseed_decision", "multiseed_triage_class", "multiseed_fail_rate",
  "multiseed_rejected_seeds", "exact_seed_screen_decision",
  "exact_seed_fail_rate", "exact_seed_rejected_seeds",
  "max_saturation_fraction", "min_relative_effective_rank_entropy",
  "max_condition_cov", "max_abs_corr",
  "validation_status", "run_id", "run_dir", "design_check_seconds",
  "n_stacked_rows", "n_augmented_features", "n_beta_features",
  "n_alpha_features", "n_reservoir_features",
  "n_reservoir_input_output_lag_features",
  "n_reservoir_input_covariate_lag_features",
  "horizon_max", "design_hash"
)
ordered_cols <- c(intersect(ordered_cols, names(out)), setdiff(names(out), ordered_cols))
out <- out[, ordered_cols, drop = FALSE]

out_path <- app_resolve_path(args$output, must_work = FALSE)
app_write_csv(out, out_path)
print(out[, c("pilot_rank", "spec_id", "pilot_role", "launch_gate_status", "exact_seed_screen_decision", "validation_status", "n_augmented_features"), drop = FALSE])
cat(sprintf("wrote %s\n", app_prefer_repo_relative_path(out_path)))
