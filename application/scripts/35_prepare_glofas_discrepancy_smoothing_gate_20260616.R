#!/usr/bin/env Rscript
# Purpose: prepare a focused p05/p50/p95 GloFAS gate for discrepancy-reservoir
# smoothing after the m420 full-seven audit. The generated runtime files are
# local/ignored; this script is the reproducible launch recipe.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_next_candidate_gate_20260614/c08_reservoir_only_m420/config_p50.yaml",
  base_model_grid = "local_trackers/runtime_configs/glofas_next_candidate_gate_20260614/c08_reservoir_only_m420/model_grid_p50.csv",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_discrepancy_smoothing_gate_20260616",
  batch_id = "glofas_discrepancy_smoothing_gate_20260616",
  preferred_cores = "9:63",
  skip_cores = "1,6,8,21,23,30,51"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))
slugify <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", tolower(as.character(x)))
as_range <- function(lo, hi) list(range = c(as.integer(lo), as.integer(hi)))

parse_core_spec <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x)) return(integer())
  parts <- unlist(strsplit(x, ",", fixed = TRUE), use.names = FALSE)
  out <- integer()
  for (part in trimws(parts)) {
    if (!nzchar(part)) next
    if (grepl(":", part, fixed = TRUE)) {
      ab <- as.integer(strsplit(part, ":", fixed = TRUE)[[1L]])
      if (length(ab) != 2L || any(!is.finite(ab))) stop(sprintf("Invalid core range: %s", part), call. = FALSE)
      out <- c(out, seq.int(ab[[1L]], ab[[2L]]))
    } else {
      val <- as.integer(part)
      if (!is.finite(val)) stop(sprintf("Invalid core id: %s", part), call. = FALSE)
      out <- c(out, val)
    }
  }
  unique(out)
}

set_reservoir_core <- function(cfg, m, alpha, beta_tau0, alpha_tau0) {
  cfg$reservoir$D <- 1L
  cfg$reservoir$n <- 300L
  cfg$reservoir$n_tilde <- list()
  cfg$reservoir$m <- as.integer(m)
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- as.numeric(alpha)
  cfg$reservoir$rho <- 0.95
  cfg$reservoir$pi_w <- 0.03
  cfg$reservoir$pi_in <- 1.0
  cfg$reservoir$win_scale_global <- 0.18
  cfg$reservoir$win_scale_bias <- 0.18
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$act_f <- "tanh"
  cfg$reservoir$act_k <- "identity"
  cfg$reservoir$standardize_inputs <- TRUE
  cfg$reservoir$add_bias <- TRUE
  cfg$reservoir$seed <- 20260512L

  cfg$feature_contract$version <- "latent_path_v0.3"
  cfg$feature_contract$two_block_design <- TRUE
  cfg$feature_contract$reservoir_input$internal_bias <- TRUE
  cfg$feature_contract$reservoir_input$output_lags <- as_range(1L, m)
  cfg$feature_contract$reservoir_input$covariates$ppt <- as_range(0L, m)
  cfg$feature_contract$reservoir_input$covariates$soil <- as_range(0L, m)
  cfg$feature_contract$reservoir_input$standardize <- TRUE
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$reservoir_state_lags <- list()
  cfg$feature_contract$readout$include_input_block <- FALSE
  cfg$feature_contract$readout$input_block$output_lags <- as_range(1L, 30L)
  cfg$feature_contract$readout$input_block$covariates$ppt <- as_range(0L, 30L)
  cfg$feature_contract$readout$input_block$covariates$soil <- as_range(0L, 30L)
  cfg$feature_contract$readout$input_block$include_internal_bias <- FALSE
  cfg$feature_contract$readout$include_horizon_scaled <- FALSE
  cfg$feature_contract$readout$standardize_output_lags <- TRUE
  cfg$feature_contract$readout$standardize_non_intercept <- FALSE
  cfg$feature_contract$forecast_alignment$output_lags_anchor <- "target_date"
  cfg$feature_contract$forecast_alignment$covariate_lags_anchor <- "target_date"

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

target_levels <- c(0.05, 0.50, 0.95)
intervals <- list(list(lower = 0.05, upper = 0.95, nominal = 0.90))

current_grid <- transform(
  expand.grid(
    m = c(360L, 420L, 540L),
    alpha = c(0.10, 0.30, 0.60),
    tau_profile = "current",
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  ),
  beta_tau0 = 0.10,
  alpha_tau0 = 0.03
)
tau_grid <- transform(
  expand.grid(
    m = 420L,
    alpha = c(0.10, 0.30, 0.60),
    tau_profile = c("tight", "loose"),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  ),
  beta_tau0 = ifelse(tau_profile == "tight", 0.03, 0.30),
  alpha_tau0 = ifelse(tau_profile == "tight", 0.01, 0.10)
)
candidate_table <- rbind(
  data.frame(
    candidate_id = "c01",
    candidate_name = "m420_alpha092_tau_current_control",
    m = 420L,
    alpha = 0.92,
    tau_profile = "current",
    beta_tau0 = 0.10,
    alpha_tau0 = 0.03,
    stringsAsFactors = FALSE
  ),
  transform(current_grid, candidate_id = NA_character_, candidate_name = NA_character_),
  transform(tau_grid, candidate_id = NA_character_, candidate_name = NA_character_)
)
idx_missing <- which(is.na(candidate_table$candidate_id) | !nzchar(candidate_table$candidate_id))
candidate_table$candidate_id[idx_missing] <- sprintf("c%02d", idx_missing)
candidate_table$candidate_name[idx_missing] <- sprintf(
  "m%03d_alpha%03d_tau_%s",
  as.integer(candidate_table$m[idx_missing]),
  as.integer(round(candidate_table$alpha[idx_missing] * 100)),
  candidate_table$tau_profile[idx_missing]
)
candidate_table <- candidate_table[order(candidate_table$candidate_id), , drop = FALSE]
candidate_table$candidate_slug <- paste(candidate_table$candidate_id, slugify(candidate_table$candidate_name), sep = "_")
candidate_table$D <- 1L
candidate_table$n <- 300L
candidate_table$rho <- 0.95
candidate_table$pi_w <- 0.03
candidate_table$pi_in <- 1.0
candidate_table$win <- 0.18
candidate_table$seed <- 20260512L
candidate_table$include_input_block <- FALSE

base_cfg <- app_read_config(app_path(args$base_config))
base_cfg$.__config_path__ <- NULL
base_grid <- app_validate_model_grid(app_path(args$base_model_grid), app_config_path(base_cfg, "schema"))
raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]

targets_all <- app_validate_quantile_grid(app_path(args$quantile_targets))
targets <- targets_all[round(as.numeric(targets_all$quantile_level), 8) %in% target_levels, , drop = FALSE]
targets <- targets[order(as.numeric(targets$quantile_level)), , drop = FALSE]
if (!identical(round(as.numeric(targets$quantile_level), 8), target_levels)) {
  stop("Quantile target file must contain p05, p50, and p95.", call. = FALSE)
}

out_dir <- app_path(args$out_dir)
app_ensure_dir(out_dir)
app_write_csv(candidate_table, file.path(out_dir, "candidate_grid.csv"))

n_jobs <- nrow(candidate_table) * nrow(targets)
core_pool <- setdiff(parse_core_spec(args$preferred_cores), parse_core_spec(args$skip_cores))
n_cores <- parallel::detectCores(logical = TRUE)
core_pool <- core_pool[core_pool >= 0L & core_pool < n_cores]
if (length(core_pool) < n_jobs) {
  stop(sprintf("Need %d cores but only %d valid preferred cores remain after exclusions.", n_jobs, length(core_pool)), call. = FALSE)
}
cores <- core_pool[seq_len(n_jobs)]

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
  "# Generated by application/scripts/35_prepare_glofas_discrepancy_smoothing_gate_20260616.R.",
  "# Focused p05/p50/p95 gate for smoother discrepancy reservoirs. One tmux session per fit.",
  ""
)

all_manifest <- list()
contract_rows <- list()
seed_rows <- list()
validation_rows <- list()
model_rows_all <- list()
qgrid_rows_all <- list()

job_index <- 0L
for (ci in seq_len(nrow(candidate_table))) {
  cand <- candidate_table[ci, , drop = FALSE]
  cand_dir <- file.path(out_dir, cand$candidate_slug[[1L]])
  app_ensure_dir(cand_dir)

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
    raw_row$notes <- sprintf("Raw GloFAS baseline for discrepancy smoothing gate %s; quantile=%s (%s).", cand$candidate_slug, qlev, qrole)
    qdesn_row$fit_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s_%s", fit_suffix, qid)
    qdesn_row$model_id <- qdesn_model_id
    qdesn_row$quantile_level <- qlev
    qdesn_row$reservoir_seed <- as.integer(cand$seed[[1L]])
    qdesn_row$config_hash <- "TO_BE_COMPUTED"
    qdesn_row$notes <- sprintf("Q-DESN discrepancy smoothing gate %s; quantile=%s (%s).", cand$candidate_slug, qlev, qrole)
    model_grid <- rbind(raw_row, qdesn_row)
    app_write_csv(model_grid, model_grid_path)
    model_rows_all[[length(model_rows_all) + 1L]] <- model_grid

    cfg <- set_reservoir_core(
      base_cfg,
      m = cand$m[[1L]],
      alpha = cand$alpha[[1L]],
      beta_tau0 = cand$beta_tau0[[1L]],
      alpha_tau0 = cand$alpha_tau0[[1L]]
    )
    cfg$application_name <- run_id
    cfg$description <- sprintf(
      "Focused GloFAS discrepancy-smoothing p05/p50/p95 gate. Candidate %s; quantile %s (%s).",
      cand$candidate_slug,
      qlev,
      qrole
    )
    cfg$paths$quantile_grid <- repo_rel(qgrid_path)
    cfg$paths$model_grid <- repo_rel(model_grid_path)
    cfg$paths$cache <- file.path("application/cache", run_id)
    cfg$scoring$intervals <- intervals
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- "User-approved focused p05/p50/p95 discrepancy-smoothing gate; not article-facing."
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
      D = cand$D,
      n = cand$n,
      reservoir_m = cand$m,
      include_input_block = isTRUE(cand$include_input_block),
      alpha = cand$alpha,
      rho = cand$rho,
      pi_w = cand$pi_w,
      pi_in = cand$pi_in,
      win_scale_global = cand$win,
      seed = cand$seed,
      beta_tau0 = cand$beta_tau0,
      alpha_tau0 = cand$alpha_tau0,
      readout_reservoir_state = isTRUE(fc$readout$include_reservoir_state),
      readout_input_block = isTRUE(fc$readout$include_input_block),
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
  sprintf("# GloFAS Discrepancy Smoothing Gate: %s", args$batch_id),
  "",
  "This directory is generated locally and ignored by git.",
  "",
  "Purpose: test whether smoother reservoir dynamics improve the fitted discrepancy path, especially p=0.95, without losing p05 or p50 forecast skill.",
  "",
  "Scope:",
  "- Quantiles: p05, p50, p95.",
  "- Reservoir-only readout contract; no direct input readout block.",
  "- Fixed D=1, n=300, rho=0.95, pi_w=0.03, pi_in=1.0, win=0.18, seed=20260512.",
  "- Vary m, leak alpha, and RHS tau0 profile around the current m420 candidate.",
  "",
  "Decision rule:",
  "- Do not promote directly from this gate.",
  "- Expand only candidates that improve p95 discrepancy history/score while preserving p50 and avoiding p05 degradation.",
  "- Compare against m420 full-seven and m360 full-seven baselines.",
  "",
  "Launch:",
  sprintf("`bash %s`", repo_rel(shell_path)),
  "",
  "Health:",
  "`Rscript application/scripts/36_summarize_glofas_discrepancy_smoothing_gate_20260616.R`"
)
writeLines(readme_lines, file.path(out_dir, "README.md"))

if (any(!prelaunch_validation$launchable_without_overwrite)) {
  warning("Some generated run IDs already have nonempty run directories. See prelaunch_validation.csv before launching.")
}
if (any(!prelaunch_validation$model_grid_valid | !prelaunch_validation$seed_contract_valid | !prelaunch_validation$covariate_policy_valid)) {
  stop("Prelaunch validation failed. See prelaunch_validation.csv.", call. = FALSE)
}

message("Prepared focused GloFAS discrepancy-smoothing gate in: ", repo_rel(out_dir))
message("Launcher prepared but not executed: ", repo_rel(shell_path))
cat(file.path(out_dir, "launch_manifest.csv"), "\n")
