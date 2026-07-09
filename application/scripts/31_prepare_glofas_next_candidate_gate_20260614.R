#!/usr/bin/env Rscript
# Purpose: prepare a controlled p05/p50/p95 GloFAS candidate gate after the
# reservoir-only, D14 true-seed, and D14 oracle full-seven audits.
#
# This script writes ignored runtime configs, manifests, validation tables, and
# a launcher. It does not start any model fits.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))

args <- app_parse_args(list(
  reservoir_base_config = "local_trackers/runtime_configs/glofas_reservoir_only_m360_full7_20260607/config_p50.yaml",
  d14_base_config = "local_trackers/runtime_configs/glofas_d14_true_seed_full7_20260611/config_p50.yaml",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_next_candidate_gate_20260614",
  batch_id = "glofas_next_candidate_gate_20260614",
  first_core = "8"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
as_range <- function(lo, hi) list(range = c(as.integer(lo), as.integer(hi)))
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))
slugify <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", tolower(as.character(x)))
bool_chr <- function(x) if (isTRUE(x)) "yes" else "no"

copy_cfg <- function(cfg) {
  cfg$.__config_path__ <- NULL
  cfg
}

set_reservoir_core <- function(cfg, D, n, m, alpha, rho, pi_w = 0.03, pi_in = 1.0,
                               win = 0.18, seed) {
  n_vec <- as.integer(strsplit(as.character(n), "x", fixed = TRUE)[[1L]])
  depth <- as.integer(D)
  if (length(n_vec) != depth) {
    stop(sprintf("Candidate D=%s but n='%s' has %d layer sizes.", D, n, length(n_vec)), call. = FALSE)
  }
  cfg$reservoir$D <- depth
  cfg$reservoir$n <- if (depth == 1L) n_vec[[1L]] else as.list(n_vec)
  cfg$reservoir$n_tilde <- list()
  cfg$reservoir$m <- as.integer(m)
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- if (depth == 1L) as.numeric(alpha) else as.list(rep(as.numeric(alpha), depth))
  cfg$reservoir$rho <- if (depth == 1L) as.numeric(rho) else as.list(rep(as.numeric(rho), depth))
  cfg$reservoir$pi_w <- if (depth == 1L) as.numeric(pi_w) else as.list(rep(as.numeric(pi_w), depth))
  cfg$reservoir$pi_in <- if (depth == 1L) as.numeric(pi_in) else as.list(rep(as.numeric(pi_in), depth))
  cfg$reservoir$win_scale_global <- as.numeric(win)
  cfg$reservoir$win_scale_bias <- as.numeric(win)
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$act_f <- "tanh"
  cfg$reservoir$act_k <- "identity"
  cfg$reservoir$standardize_inputs <- TRUE
  cfg$reservoir$add_bias <- TRUE
  cfg$reservoir$seed <- as.integer(seed)
  cfg
}

set_feature_core <- function(cfg, reservoir_m, direct_lag, include_input_block,
                             standardize_non_intercept = FALSE) {
  cfg$feature_contract$version <- "latent_path_v0.3"
  cfg$feature_contract$two_block_design <- TRUE
  cfg$feature_contract$reservoir_input$internal_bias <- TRUE
  cfg$feature_contract$reservoir_input$output_lags <- as_range(1L, reservoir_m)
  cfg$feature_contract$reservoir_input$covariates$ppt <- as_range(0L, reservoir_m)
  cfg$feature_contract$reservoir_input$covariates$soil <- as_range(0L, reservoir_m)
  cfg$feature_contract$reservoir_input$standardize <- TRUE
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$reservoir_state_lags <- list()
  cfg$feature_contract$readout$include_input_block <- isTRUE(include_input_block)
  cfg$feature_contract$readout$input_block$output_lags <- as_range(1L, direct_lag)
  cfg$feature_contract$readout$input_block$covariates$ppt <- as_range(0L, direct_lag)
  cfg$feature_contract$readout$input_block$covariates$soil <- as_range(0L, direct_lag)
  cfg$feature_contract$readout$input_block$include_internal_bias <- FALSE
  cfg$feature_contract$readout$include_horizon_scaled <- FALSE
  cfg$feature_contract$readout$standardize_output_lags <- TRUE
  cfg$feature_contract$readout$standardize_non_intercept <- isTRUE(standardize_non_intercept)
  cfg$feature_contract$forecast_alignment$output_lags_anchor <- "target_date"
  cfg$feature_contract$forecast_alignment$covariate_lags_anchor <- "target_date"
  cfg
}

set_inference_core <- function(cfg, beta_tau0, alpha_tau0) {
  cfg$inference$vb_ld$max_iter <- 150L
  cfg$inference$vb_ld$max_iter_hard_cap <- 150L
  cfg$inference$vb_ld$n_draws <- 2000L
  cfg$inference$vb_ld$rhs_tau0 <- as.numeric(beta_tau0)
  cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(alpha_tau0)
  cfg$inference$vb_ld$diagnostics$profile_substeps <- FALSE
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg$execution$seed_contract <- cfg$execution$seed_contract %||% list()
  cfg$execution$seed_contract$require_config_model_grid_match <- TRUE
  cfg
}

candidate_table <- data.frame(
  candidate_id = sprintf("c%02d", 1:8),
  candidate_name = c(
    "reservoir_only_m360_control",
    "d14_direct_current",
    "d14_reservoir_only_seed20260610",
    "d14_direct_standardized",
    "d14_direct_stronger_discrepancy_shrinkage",
    "d14_direct_weaker_discrepancy_shrinkage",
    "reservoir_only_seed20260610",
    "reservoir_only_m420"
  ),
  source_base = c("reservoir", "d14", "d14", "d14", "d14", "d14", "reservoir", "reservoir"),
  role = c(
    "current full-seven winner control",
    "D14 full-seven failure reproducer",
    "D14 reservoir dynamics without direct readout block",
    "D14 direct block with non-intercept readout standardization",
    "D14 direct block with stronger discrepancy shrinkage",
    "D14 direct block with weaker discrepancy shrinkage",
    "reservoir-only baseline contract with D14 seed",
    "reservoir-only baseline contract with longer memory"
  ),
  D = 1L,
  n = "300",
  reservoir_m = c(360L, 360L, 360L, 360L, 360L, 360L, 360L, 420L),
  direct_lag = c(30L, 360L, 30L, 360L, 360L, 360L, 30L, 30L),
  include_input_block = c(FALSE, TRUE, FALSE, TRUE, TRUE, TRUE, FALSE, FALSE),
  standardize_non_intercept = c(FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE),
  alpha = c(0.92, 0.98, 0.98, 0.98, 0.98, 0.98, 0.92, 0.92),
  rho = 0.95,
  pi_w = 0.03,
  pi_in = 1.0,
  win = 0.18,
  seed = c(20260512L, 20260610L, 20260610L, 20260610L, 20260610L, 20260610L, 20260610L, 20260512L),
  beta_tau0 = 0.1,
  alpha_tau0 = c(0.03, 0.03, 0.03, 0.03, 0.01, 0.1, 0.03, 0.03),
  stringsAsFactors = FALSE
)
candidate_table$candidate_slug <- paste(candidate_table$candidate_id, slugify(candidate_table$candidate_name), sep = "_")

target_levels <- c(0.05, 0.50, 0.95)
intervals <- list(
  list(lower = 0.05, upper = 0.95, nominal = 0.90)
)

out_dir <- app_path(args$out_dir)
app_ensure_dir(out_dir)
targets_all <- app_validate_quantile_grid(app_path(args$quantile_targets))
targets <- targets_all[round(as.numeric(targets_all$quantile_level), 8) %in% target_levels, , drop = FALSE]
targets <- targets[order(as.numeric(targets$quantile_level)), , drop = FALSE]
if (!identical(round(as.numeric(targets$quantile_level), 8), target_levels)) {
  stop("Quantile target file must contain p05, p50, and p95.", call. = FALSE)
}

reservoir_base <- copy_cfg(app_read_config(app_path(args$reservoir_base_config)))
d14_base <- copy_cfg(app_read_config(app_path(args$d14_base_config)))
base_by_name <- list(reservoir = reservoir_base, d14 = d14_base)

base_grid_by_name <- list(
  reservoir = app_validate_model_grid(app_config_path(reservoir_base, "model_grid"), app_config_path(reservoir_base, "schema")),
  d14 = app_validate_model_grid(app_config_path(d14_base, "model_grid"), app_config_path(d14_base, "schema"))
)

n_jobs <- nrow(candidate_table) * nrow(targets)
n_cores <- parallel::detectCores(logical = TRUE)
cores <- as.integer(args$first_core) + seq_len(n_jobs) - 1L
if (any(cores < 0L | cores >= n_cores)) {
  stop(sprintf("Requested core range is invalid for %d detected cores: %s", n_cores, paste(cores, collapse = ", ")), call. = FALSE)
}

app_write_csv(candidate_table, file.path(out_dir, "candidate_grid.csv"))

reference_scores <- data.frame(
  run_id = c(
    "glofas_reservoir_only_m360_full7_20260607_synthesis_final",
    "glofas_d14_true_seed_full7_20260611_synthesis_final",
    "glofas_d14_oracle_full7_20260613_synthesis_final"
  ),
  role = c("current_baseline", "d14_true_seed_diagnostic", "d14_oracle_diagnostic"),
  qdesn_check_loss = c(0.577575321885477, 0.8271236, 0.9033123),
  raw_check_loss = c(0.763942704562467, 0.763942704562467, 0.763942704562467),
  qdesn_crps = c(1.155944, 1.501764, 1.665296),
  raw_crps = c(1.442359, 1.442359, 1.442359),
  decision = c("baseline_to_beat", "rejected", "rejected"),
  stringsAsFactors = FALSE
)
app_write_csv(reference_scores, file.path(out_dir, "score_reference_table.csv"))

all_manifest <- list()
contract_rows <- list()
seed_rows <- list()
validation_rows <- list()
model_rows_all <- list()
qgrid_rows_all <- list()
shell_lines <- c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  sprintf("cd %s", shQuote(app_repo_root())),
  "export OMP_NUM_THREADS=1",
  "export OPENBLAS_NUM_THREADS=1",
  "export MKL_NUM_THREADS=1",
  "export VECLIB_MAXIMUM_THREADS=1",
  "export NUMEXPR_NUM_THREADS=1",
  "",
  "# Generated by application/scripts/31_prepare_glofas_next_candidate_gate_20260614.R.",
  "# Controlled p05/p50/p95 GloFAS candidate gate. One tmux session per fit.",
  ""
)

job_index <- 0L
for (ci in seq_len(nrow(candidate_table))) {
  cand <- candidate_table[ci, , drop = FALSE]
  cand_dir <- file.path(out_dir, cand$candidate_slug[[1L]])
  app_ensure_dir(cand_dir)
  base_cfg <- base_by_name[[cand$source_base[[1L]]]]
  base_grid <- base_grid_by_name[[cand$source_base[[1L]]]]
  raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
  qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]

  for (qi in seq_len(nrow(targets))) {
    job_index <- job_index + 1L
    qid <- q_label(targets$quantile_id[[qi]])
    qlev <- as.numeric(targets$quantile_level[[qi]])
    qrole <- as.character(targets$role[[qi]])
    run_id <- sprintf("%s_%s_%s", args$batch_id, cand$candidate_slug[[1L]], qid)
    fit_suffix <- sprintf("%s_%s", args$batch_id, cand$candidate_slug[[1L]])
    raw_model_id <- sprintf("raw_glofas_%s", fit_suffix)
    qdesn_model_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s", fit_suffix)
    qgrid_path <- file.path(cand_dir, sprintf("quantile_grid_%s.csv", qid))
    model_grid_path <- file.path(cand_dir, sprintf("model_grid_%s.csv", qid))
    config_path <- file.path(cand_dir, sprintf("config_%s.yaml", qid))
    core <- cores[[job_index]]

    app_write_csv(targets[qi, , drop = FALSE], qgrid_path)
    qgrid_rows_all[[length(qgrid_rows_all) + 1L]] <- targets[qi, , drop = FALSE]

    raw_row <- raw_base
    qdesn_row <- qdesn_base
    raw_row$fit_id <- sprintf("raw_glofas_%s_%s", fit_suffix, qid)
    raw_row$model_id <- raw_model_id
    raw_row$quantile_level <- qlev
    raw_row$config_hash <- "TO_BE_COMPUTED"
    raw_row$notes <- sprintf("Raw GloFAS baseline for next-candidate gate %s; quantile=%s (%s).", cand$candidate_slug, qlev, qrole)
    qdesn_row$fit_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s_%s", fit_suffix, qid)
    qdesn_row$model_id <- qdesn_model_id
    qdesn_row$quantile_level <- qlev
    qdesn_row$reservoir_seed <- as.integer(cand$seed[[1L]])
    qdesn_row$config_hash <- "TO_BE_COMPUTED"
    qdesn_row$notes <- sprintf("Q-DESN next-candidate gate %s; quantile=%s (%s).", cand$candidate_slug, qlev, qrole)
    model_grid <- rbind(raw_row, qdesn_row)
    app_write_csv(model_grid, model_grid_path)
    model_rows_all[[length(model_rows_all) + 1L]] <- model_grid

    cfg <- base_cfg
    cfg <- set_reservoir_core(
      cfg,
      D = cand$D[[1L]],
      n = cand$n[[1L]],
      m = cand$reservoir_m[[1L]],
      alpha = cand$alpha[[1L]],
      rho = cand$rho[[1L]],
      pi_w = cand$pi_w[[1L]],
      pi_in = cand$pi_in[[1L]],
      win = cand$win[[1L]],
      seed = cand$seed[[1L]]
    )
    cfg <- set_feature_core(
      cfg,
      reservoir_m = cand$reservoir_m[[1L]],
      direct_lag = cand$direct_lag[[1L]],
      include_input_block = cand$include_input_block[[1L]],
      standardize_non_intercept = cand$standardize_non_intercept[[1L]]
    )
    cfg <- set_inference_core(
      cfg,
      beta_tau0 = cand$beta_tau0[[1L]],
      alpha_tau0 = cand$alpha_tau0[[1L]]
    )
    cfg$application_name <- run_id
    cfg$description <- sprintf(
      "Controlled GloFAS next-candidate p05/p50/p95 gate. Candidate %s (%s); quantile %s (%s).",
      cand$candidate_slug,
      cand$role,
      qlev,
      qrole
    )
    cfg$paths$quantile_grid <- repo_rel(qgrid_path)
    cfg$paths$model_grid <- repo_rel(model_grid_path)
    cfg$paths$cache <- file.path("application/cache", run_id)
    cfg$scoring$intervals <- intervals
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- "User-approved controlled p05/p50/p95 gate; not a manuscript promotion target."
    app_write_yaml(cfg, config_path)

    validated_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
    app_validate_qdesn_model_grid_prior_contract(validated_grid)
    seed_contract <- app_qdesn_seed_contract_report(cfg, validated_grid)
    app_validate_qdesn_seed_contract(cfg, validated_grid)
    seed_contract$candidate_id <- cand$candidate_id
    seed_contract$candidate_name <- cand$candidate_name
    seed_contract$run_id <- run_id
    seed_rows[[length(seed_rows) + 1L]] <- seed_contract

    fc <- app_feature_contract(cfg)
    policy <- app_validate_covariate_source_policy(
      cfg,
      cutoff_row = data.frame(origin_date = as.Date("2022-12-25")),
      stop_on_failure = FALSE
    )
    contract_rows[[length(contract_rows) + 1L]] <- data.frame(
      candidate_id = cand$candidate_id,
      candidate_name = cand$candidate_name,
      run_id = run_id,
      quantile_id = qid,
      quantile_level = qlev,
      source_base = cand$source_base,
      D = cand$D,
      n = cand$n,
      reservoir_m = cand$reservoir_m,
      direct_lag = cand$direct_lag,
      include_input_block = isTRUE(cand$include_input_block),
      standardize_non_intercept = isTRUE(cand$standardize_non_intercept),
      alpha = cand$alpha,
      rho = cand$rho,
      pi_w = cand$pi_w,
      pi_in = cand$pi_in,
      win_scale_global = cand$win,
      seed = cand$seed,
      beta_tau0 = cand$beta_tau0,
      alpha_tau0 = cand$alpha_tau0,
      readout_output_lag_n = length(fc$readout$input_block$output_lags),
      readout_ppt_lag_n = length(fc$readout$input_block$covariates$ppt %||% integer(0)),
      readout_soil_lag_n = length(fc$readout$input_block$covariates$soil %||% integer(0)),
      reservoir_output_lag_n = length(fc$reservoir_input$output_lags),
      reservoir_ppt_lag_n = length(fc$reservoir_input$covariate_lags$ppt %||% integer(0)),
      reservoir_soil_lag_n = length(fc$reservoir_input$covariate_lags$soil %||% integer(0)),
      covariate_policy_status = policy$status[[1L]],
      covariate_future_policy = policy$future_policy[[1L]],
      covariate_uses_realized_future = policy$uses_realized_future[[1L]],
      stringsAsFactors = FALSE
    )

    existing_run_dir <- app_path(file.path("application/runs", run_id))
    validation_rows[[length(validation_rows) + 1L]] <- data.frame(
      candidate_id = cand$candidate_id,
      candidate_name = cand$candidate_name,
      run_id = run_id,
      config_path = repo_rel(config_path),
      model_grid_valid = TRUE,
      seed_contract_valid = all(seed_contract$status == "ok"),
      covariate_policy_valid = identical(policy$status[[1L]], "PASS"),
      run_dir_exists = dir.exists(existing_run_dir),
      run_dir_nonempty = dir.exists(existing_run_dir) && length(list.files(existing_run_dir, all.files = TRUE, no.. = TRUE)) > 0L,
      launchable_without_overwrite = !(dir.exists(existing_run_dir) && length(list.files(existing_run_dir, all.files = TRUE, no.. = TRUE)) > 0L),
      stringsAsFactors = FALSE
    )

    session <- sprintf("%s_%s_%s", args$batch_id, cand$candidate_id[[1L]], qid)
    log_path <- file.path("application/logs", sprintf("%s.log", run_id))
    command <- sprintf(
      "taskset -c %d Rscript application/scripts/run_all.R --config %s --run_id %s --preflight true --confirm_final_launch true > %s 2>&1",
      core,
      repo_rel(config_path),
      run_id,
      log_path
    )
    shell_lines <- c(
      shell_lines,
      sprintf("# %s %s quantile=%s", cand$candidate_id, cand$candidate_name, qid),
      sprintf("if tmux has-session -t %s 2>/dev/null; then echo 'Session exists: %s' >&2; exit 1; fi", shQuote(session), session),
      sprintf("tmux new-session -d -s %s %s", shQuote(session), shQuote(command)),
      ""
    )

    all_manifest[[length(all_manifest) + 1L]] <- data.frame(
      batch_id = args$batch_id,
      run_index = job_index,
      candidate_id = cand$candidate_id,
      candidate_name = cand$candidate_name,
      candidate_slug = cand$candidate_slug,
      quantile_id = qid,
      quantile_level = qlev,
      role = qrole,
      run_id = run_id,
      session = session,
      config_path = repo_rel(config_path),
      quantile_grid_path = repo_rel(qgrid_path),
      model_grid_path = repo_rel(model_grid_path),
      core = core,
      raw_fit_id = raw_row$fit_id,
      qdesn_fit_id = qdesn_row$fit_id,
      raw_model_id = raw_model_id,
      qdesn_model_id = qdesn_model_id,
      launch_status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
  }
}

launch_manifest <- app_bind_rows_fill(all_manifest)
model_contract <- app_bind_rows_fill(contract_rows)
seed_contract <- app_bind_rows_fill(seed_rows)
prelaunch_validation <- app_bind_rows_fill(validation_rows)

app_write_csv(launch_manifest, file.path(out_dir, "launch_manifest.csv"))
app_write_csv(model_contract, file.path(out_dir, "model_contract_audit.csv"))
app_write_csv(seed_contract, file.path(out_dir, "seed_contract_prelaunch_all.csv"))
app_write_csv(prelaunch_validation, file.path(out_dir, "prelaunch_validation.csv"))
app_write_csv(app_bind_rows_fill(model_rows_all), file.path(out_dir, "model_grid_all.csv"))
app_write_csv(app_bind_rows_fill(qgrid_rows_all), file.path(out_dir, "quantile_grid_all.csv"))

shell_path <- file.path(out_dir, sprintf("launch_all_%s.sh", args$batch_id))
writeLines(shell_lines, shell_path)
Sys.chmod(shell_path, "0755")

readme_lines <- c(
  sprintf("# GloFAS Next-Candidate Gate: %s", args$batch_id),
  "",
  "This directory is generated locally and ignored by git.",
  "",
  "Purpose: run a controlled p05/p50/p95 gate before spending another full-seven launch.",
  "",
  "Primary question: do direct/covariate readout features damage tail stability, and can scaling or discrepancy shrinkage repair them?",
  "",
  "Files:",
  sprintf("- `candidate_grid.csv`: candidate definitions."),
  sprintf("- `launch_manifest.csv`: one row per candidate/quantile fit."),
  sprintf("- `model_contract_audit.csv`: feature and prior contract audit."),
  sprintf("- `seed_contract_prelaunch_all.csv`: Q-DESN reference/discrepancy seed contract."),
  sprintf("- `prelaunch_validation.csv`: launch safety checks."),
  sprintf("- `%s`: starts all candidate/quantile fits.", basename(shell_path)),
  "",
  "This gate is not article-facing. Promote nothing from it directly.",
  "",
  "Recommended command after launch/completion:",
  "`Rscript application/scripts/32_summarize_glofas_next_candidate_gate_20260614.R`"
)
writeLines(readme_lines, file.path(out_dir, "README.md"))

if (any(!prelaunch_validation$launchable_without_overwrite)) {
  warning("Some generated run IDs already have nonempty run directories. See prelaunch_validation.csv before launching.")
}
if (any(!prelaunch_validation$model_grid_valid | !prelaunch_validation$seed_contract_valid | !prelaunch_validation$covariate_policy_valid)) {
  stop("Prelaunch validation failed. See prelaunch_validation.csv.", call. = FALSE)
}

message("Prepared controlled GloFAS next-candidate gate in: ", repo_rel(out_dir))
message("Launcher prepared but not executed: ", repo_rel(shell_path))
cat(file.path(out_dir, "launch_manifest.csv"), "\n")
