#!/usr/bin/env Rscript
# Purpose: prepare a coherent full seven-quantile GloFAS launch for the
# confirmed deep-identity D4/w100/m300/alpha=0.05 application candidate. This
# script generates configs, manifests, launch scripts, and a synthesis watcher;
# it does not fit models by itself.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_deep_identity_followup_grid_20260618/confirm_primary_d4_w100_m300_a050_r95_bt1em3_at3em2_max250/config_p50.yaml",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_deep_identity_d4w100m300a050_full7_20260618",
  batch_id = "glofas_deep_identity_d4w100m300a050_full7_20260618",
  first_core = "30"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))

target_levels <- c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95)
intervals <- list(
  list(lower = 0.05, upper = 0.95, nominal = 0.90),
  list(lower = 0.15, upper = 0.80, nominal = 0.65),
  list(lower = 0.35, upper = 0.65, nominal = 0.30)
)

copy_cfg <- function(cfg) {
  cfg$.__config_path__ <- NULL
  cfg
}

enforce_selected_contract <- function(cfg) {
  cfg$reservoir$D <- 4L
  cfg$reservoir$n <- as.list(rep(100L, 4L))
  cfg$reservoir$n_tilde <- as.list(rep(100L, 3L))
  cfg$reservoir$m <- 300L
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- as.list(rep(0.05, 4L))
  cfg$reservoir$rho <- as.list(rep(0.95, 4L))
  cfg$reservoir$pi_w <- as.list(rep(0.03, 4L))
  cfg$reservoir$pi_in <- as.list(rep(1.0, 4L))
  cfg$reservoir$win_scale_global <- 0.18
  cfg$reservoir$win_scale_bias <- 0.18
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$act_f <- "tanh"
  cfg$reservoir$act_k <- "identity"
  cfg$reservoir$standardize_inputs <- TRUE
  cfg$reservoir$add_bias <- TRUE
  cfg$reservoir$seed <- 20260512L

  cfg$covariates$readout$include_lags <- TRUE
  cfg$covariates$readout$lags <- list(range = c(0L, 300L))
  cfg$covariates$readout$standardize <- TRUE
  cfg$covariates$readout$scale_reference <- "retrospective_train"

  cfg$feature_contract$version <- "latent_path_v0.3"
  cfg$feature_contract$two_block_design <- TRUE
  cfg$feature_contract$reservoir_input$internal_bias <- TRUE
  cfg$feature_contract$reservoir_input$output_lags <- list(range = c(1L, 300L))
  cfg$feature_contract$reservoir_input$covariates$ppt <- list(range = c(0L, 300L))
  cfg$feature_contract$reservoir_input$covariates$soil <- list(range = c(0L, 300L))
  cfg$feature_contract$reservoir_input$standardize <- TRUE
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$reservoir_state_lags <- list()
  cfg$feature_contract$readout$include_input_block <- FALSE
  cfg$feature_contract$readout$input_block$output_lags <- list(range = c(1L, 300L))
  cfg$feature_contract$readout$input_block$covariates$ppt <- list(range = c(0L, 300L))
  cfg$feature_contract$readout$input_block$covariates$soil <- list(range = c(0L, 300L))
  cfg$feature_contract$readout$input_block$include_internal_bias <- FALSE
  cfg$feature_contract$readout$include_horizon_scaled <- FALSE
  cfg$feature_contract$readout$standardize_output_lags <- TRUE
  cfg$feature_contract$readout$standardize_non_intercept <- FALSE
  cfg$feature_contract$forecast_alignment$output_lags_anchor <- "target_date"
  cfg$feature_contract$forecast_alignment$covariate_lags_anchor <- "target_date"

  cfg$inference$default_method <- "vb_ld"
  cfg$inference$likelihood_family <- "al"
  cfg$inference$coefficient_prior_default <- "rhs"
  cfg$inference$vb_ld$max_iter <- 250L
  cfg$inference$vb_ld$max_iter_hard_cap <- 250L
  cfg$inference$vb_ld$tol <- 1e-3
  cfg$inference$vb_ld$tol_par <- 1e-3
  cfg$inference$vb_ld$n_samp_xi <- 500L
  cfg$inference$vb_ld$n_draws <- 2000L
  cfg$inference$vb_ld$rhs_tau0 <- 1e-3
  cfg$inference$vb_ld$rhs_slab_s2 <- 1.0
  cfg$inference$vb_ld$rhs_a_zeta <- 2.0
  cfg$inference$vb_ld$rhs_b_zeta <- 4.0
  cfg$inference$vb_ld$rhs_alpha_tau0 <- 0.03
  cfg$inference$vb_ld$rhs_alpha_slab_s2 <- 1.0
  cfg$inference$vb_ld$rhs_alpha_a_zeta <- 2.0
  cfg$inference$vb_ld$rhs_alpha_b_zeta <- 4.0
  cfg$inference$vb_ld$diagnostics$profile_substeps <- FALSE
  cfg$inference$vb_ld$diagnostics$trace_iterations <- FALSE

  cfg$execution$seed_contract <- cfg$execution$seed_contract %||% list()
  cfg$execution$seed_contract$require_config_model_grid_match <- TRUE
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- paste(
    "User-approved full-seven component for the confirmed D4/w100/m300/alpha=0.05 deep-identity GloFAS candidate.",
    "Do not promote a single component; synthesize all seven quantiles first."
  )
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg
}

base_cfg <- enforce_selected_contract(copy_cfg(app_read_config(app_path(args$base_config))))
targets_all <- app_validate_quantile_grid(app_path(args$quantile_targets))
targets <- targets_all[round(as.numeric(targets_all$quantile_level), 8) %in% target_levels, , drop = FALSE]
targets <- targets[order(as.numeric(targets$quantile_level)), , drop = FALSE]
if (!identical(round(as.numeric(targets$quantile_level), 8), target_levels)) {
  stop("Quantile target file must contain p05, p15, p35, p50, p65, p80, and p95.", call. = FALSE)
}

out_dir <- app_path(args$out_dir)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "logs"))

base_grid <- app_validate_model_grid(app_config_path(base_cfg, "model_grid"), app_config_path(base_cfg, "schema"))
raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
if (!nrow(raw_base) || !nrow(qdesn_base)) {
  stop("Base model grid must contain one raw_glofas row and one qdesn_glofas_discrepancy row.", call. = FALSE)
}

first_core <- as.integer(args$first_core)
cores <- first_core + seq_len(nrow(targets)) - 1L
n_cores <- parallel::detectCores(logical = TRUE)
if (any(!is.finite(cores)) || any(cores < 0L | cores >= n_cores)) {
  stop(sprintf("Requested core range is invalid for %d detected cores: %s", n_cores, paste(cores, collapse = ", ")), call. = FALSE)
}

fit_suffix <- "glofas_deep_identity_d4w100m300a050_full7"
raw_model_id <- paste0("raw_glofas_", fit_suffix)
qdesn_model_id <- paste0("qdesn_latent_path_rhs_al_vb_", fit_suffix)

launch_rows <- vector("list", nrow(targets))
source_rows <- vector("list", nrow(targets))
all_model_rows <- vector("list", nrow(targets))
all_qgrid_rows <- vector("list", nrow(targets))
prelaunch_rows <- vector("list", nrow(targets))

launch_lines <- c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  sprintf("cd %s", shQuote(app_repo_root())),
  "export OMP_NUM_THREADS=1",
  "export OPENBLAS_NUM_THREADS=1",
  "export MKL_NUM_THREADS=1",
  "export VECLIB_MAXIMUM_THREADS=1",
  "export NUMEXPR_NUM_THREADS=1",
  "",
  "# Generated by application/scripts/42_prepare_glofas_deep_identity_full7_20260618.R.",
  "# Review launch_manifest.csv before running. Each quantile uses one tmux session.",
  ""
)

for (i in seq_len(nrow(targets))) {
  qid <- q_label(targets$quantile_id[[i]])
  qlev <- as.numeric(targets$quantile_level[[i]])
  role <- as.character(targets$role[[i]])
  run_id <- sprintf("%s_%s", args$batch_id, qid)
  qgrid_path <- file.path(out_dir, sprintf("quantile_grid_%s.csv", qid))
  model_grid_path <- file.path(out_dir, sprintf("model_grid_%s.csv", qid))
  config_path <- file.path(out_dir, sprintf("config_%s.yaml", qid))
  log_path <- file.path("application/logs", sprintf("%s.log", run_id))
  session <- sprintf("%s_%s", args$batch_id, qid)
  core <- cores[[i]]

  app_write_csv(targets[i, , drop = FALSE], qgrid_path)
  all_qgrid_rows[[i]] <- targets[i, , drop = FALSE]

  raw_row <- raw_base
  qdesn_row <- qdesn_base
  raw_row$fit_id <- sprintf("%s_%s", raw_model_id, qid)
  raw_row$model_id <- raw_model_id
  raw_row$quantile_level <- qlev
  raw_row$config_hash <- "TO_BE_COMPUTED"
  raw_row$notes <- sprintf("Raw GloFAS baseline for %s; quantile=%s (%s).", args$batch_id, qlev, role)
  qdesn_row$fit_id <- sprintf("%s_%s", qdesn_model_id, qid)
  qdesn_row$model_id <- qdesn_model_id
  qdesn_row$quantile_level <- qlev
  qdesn_row$reservoir_seed <- 20260512L
  qdesn_row$config_hash <- "TO_BE_COMPUTED"
  qdesn_row$notes <- sprintf("Q-DESN D4/w100/m300/alpha=0.05 full-seven component for %s; quantile=%s (%s).", args$batch_id, qlev, role)
  model_grid <- rbind(raw_row, qdesn_row)
  app_write_csv(model_grid, model_grid_path)
  all_model_rows[[i]] <- model_grid

  cfg <- enforce_selected_contract(base_cfg)
  cfg$application_name <- run_id
  cfg$description <- paste(
    "Single-quantile component of the confirmed GloFAS deep-identity D4/w100/m300/alpha=0.05 full-seven Q-DESN launch.",
    sprintf("Quantile %s (%s).", qlev, role)
  )
  cfg$paths$quantile_grid <- repo_rel(qgrid_path)
  cfg$paths$model_grid <- repo_rel(model_grid_path)
  cfg$paths$cache <- file.path("application/cache", run_id)
  cfg$scoring$intervals <- intervals
  app_write_yaml(cfg, config_path)

  validated_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
  app_validate_qdesn_model_grid_prior_contract(validated_grid)
  app_validate_qdesn_seed_contract(cfg, validated_grid)
  engine_report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, validated_grid),
    stop_on_failure = TRUE
  )

  run_dir <- file.path("application/runs", run_id)
  prelaunch_rows[[i]] <- data.frame(
    quantile_id = qid,
    quantile_level = qlev,
    config_path = repo_rel(config_path),
    model_grid_valid = TRUE,
    seed_contract_valid = TRUE,
    engine_api_ok = isTRUE(engine_report$ok),
    run_dir_exists = file.exists(app_path(run_dir)),
    launchable_without_overwrite = !file.exists(app_path(run_dir)),
    stringsAsFactors = FALSE
  )

  launch_rows[[i]] <- data.frame(
    batch_id = args$batch_id,
    run_index = i,
    quantile_id = qid,
    quantile_level = qlev,
    role = role,
    run_id = run_id,
    config_path = repo_rel(config_path),
    quantile_grid_path = repo_rel(qgrid_path),
    model_grid_path = repo_rel(model_grid_path),
    core = core,
    raw_fit_id = raw_row$fit_id,
    qdesn_fit_id = qdesn_row$fit_id,
    raw_model_id = raw_model_id,
    qdesn_model_id = qdesn_model_id,
    log_path = log_path,
    session = session,
    launch_status = "prepared_not_launched",
    stringsAsFactors = FALSE
  )

  source_rows[[i]] <- data.frame(
    batch_id = args$batch_id,
    run_index = i,
    quantile_id = qid,
    quantile_level = qlev,
    role = role,
    run_id = run_id,
    config_path = repo_rel(config_path),
    quantile_grid_path = repo_rel(qgrid_path),
    model_grid_path = repo_rel(model_grid_path),
    run_dir = run_dir,
    raw_fit_id = raw_row$fit_id,
    qdesn_fit_id = qdesn_row$fit_id,
    raw_model_id = raw_model_id,
    qdesn_model_id = qdesn_model_id,
    source_kind = "new_full7_component",
    required = TRUE,
    enabled = TRUE,
    stringsAsFactors = FALSE
  )

  command <- sprintf(
    "taskset -c %d Rscript application/scripts/run_all.R --config %s --run_id %s --preflight true --confirm_final_launch true > %s 2>&1",
    core,
    repo_rel(config_path),
    run_id,
    log_path
  )
  launch_lines <- c(
    launch_lines,
    sprintf("# %s: %s", qid, role),
    sprintf("if tmux has-session -t %s 2>/dev/null; then echo 'Session exists: %s' >&2; exit 1; fi", shQuote(session), session),
    sprintf("if [ -e %s ]; then echo 'Run dir exists: %s' >&2; exit 1; fi", shQuote(run_dir), run_dir),
    sprintf("tmux new-session -d -s %s %s", shQuote(session), shQuote(command)),
    ""
  )
}

launch_manifest <- do.call(rbind, launch_rows)
source_manifest <- do.call(rbind, source_rows)
prelaunch <- do.call(rbind, prelaunch_rows)
model_grid_all <- do.call(rbind, all_model_rows)
quantile_grid_all <- do.call(rbind, all_qgrid_rows)
app_write_csv(launch_manifest, file.path(out_dir, "launch_manifest.csv"))
app_write_csv(source_manifest, file.path(out_dir, "synthesis_source_manifest.csv"))
app_write_csv(source_manifest, file.path(out_dir, "component_manifest.csv"))
app_write_csv(prelaunch, file.path(out_dir, "prelaunch_validation.csv"))
app_write_csv(model_grid_all, file.path(out_dir, "model_grid_all.csv"))
app_write_csv(quantile_grid_all, file.path(out_dir, "quantile_grid_all.csv"))

synthesis_cfg <- enforce_selected_contract(base_cfg)
synthesis_cfg$application_name <- paste0(args$batch_id, "_synthesis")
synthesis_cfg$description <- "Post-hoc monotone synthesis and scoring config for the confirmed GloFAS deep-identity D4/w100/m300/alpha=0.05 full-seven candidate."
synthesis_cfg$paths$quantile_grid <- repo_rel(file.path(out_dir, "quantile_grid_all.csv"))
synthesis_cfg$paths$model_grid <- repo_rel(file.path(out_dir, "model_grid_all.csv"))
synthesis_cfg$paths$cache <- file.path("application/cache", paste0(args$batch_id, "_synthesis"))
synthesis_cfg$scoring$intervals <- intervals
synthesis_cfg$execution$final_launch$enabled <- FALSE
synthesis_cfg$execution$final_launch$note <- "Synthesis-only config; consumes completed per-quantile component runs and does not fit models."
synthesis_cfg$post_analysis$run_after_outputs <- FALSE
app_write_yaml(synthesis_cfg, file.path(out_dir, "synthesis_config.yaml"))

launch_path <- file.path(out_dir, sprintf("launch_all_%s.sh", args$batch_id))
writeLines(launch_lines, launch_path)
Sys.chmod(launch_path, "0755")

synth_path <- file.path(out_dir, sprintf("synthesize_%s.sh", args$batch_id))
synth_lines <- c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  sprintf("cd %s", shQuote(app_repo_root())),
  "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R \\",
  sprintf("  --config %s \\", shQuote(repo_rel(file.path(out_dir, "synthesis_config.yaml")))),
  sprintf("  --source_manifest %s \\", shQuote(repo_rel(file.path(out_dir, "synthesis_source_manifest.csv")))),
  sprintf("  --run_id %s", shQuote(paste0(args$batch_id, "_synthesis_final")))
)
writeLines(synth_lines, synth_path)
Sys.chmod(synth_path, "0755")

diag_path <- file.path(out_dir, sprintf("make_diagnostics_%s.sh", args$batch_id))
diag_lines <- c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  sprintf("cd %s", shQuote(app_repo_root())),
  "Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R \\",
  sprintf("  --config %s \\", shQuote(repo_rel(file.path(out_dir, "synthesis_config.yaml")))),
  sprintf("  --source_manifest %s \\", shQuote(repo_rel(file.path(out_dir, "synthesis_source_manifest.csv")))),
  sprintf("  --synthesis_run_id %s \\", shQuote(paste0(args$batch_id, "_synthesis_final"))),
  sprintf("  --run_id %s \\", shQuote(paste0(args$batch_id, "_diagnostic_figures"))),
  sprintf("  --figure_prefix %s", shQuote("glofas_deep_identity_full7"))
)
writeLines(diag_lines, diag_path)
Sys.chmod(diag_path, "0755")

watch_path <- file.path(out_dir, sprintf("watch_and_synthesize_%s.sh", args$batch_id))
watch_lines <- c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  sprintf("cd %s", shQuote(app_repo_root())),
  sprintf("manifest=%s", shQuote(repo_rel(file.path(out_dir, "synthesis_source_manifest.csv")))),
  sprintf("synth=%s", shQuote(repo_rel(synth_path))),
  sprintf("diag=%s", shQuote(repo_rel(diag_path))),
  sprintf("log=%s", shQuote(file.path("application/logs", paste0(args$batch_id, "_watch_and_synthesize.log")))),
  "echo \"$(date -Is) watch started\" >> \"$log\"",
  "while true; do",
  "  read -r total done_count < <(python3 - \"$manifest\" <<'PY'",
  "import csv",
  "import pathlib",
  "import sys",
  "",
  "manifest = pathlib.Path(sys.argv[1])",
  "total = 0",
  "done = 0",
  "with manifest.open(newline='') as handle:",
  "    for row in csv.DictReader(handle):",
  "        total += 1",
  "        run_dir = pathlib.Path(row['run_dir'])",
  "        fit = run_dir / 'tables' / 'fit_status.csv'",
  "        pred = run_dir / 'tables' / 'prediction_quantiles.csv'",
  "        if fit.is_file() and fit.stat().st_size > 0 and pred.is_file() and pred.stat().st_size > 0:",
  "            if 'completed' in fit.read_text():",
  "                done += 1",
  "print(total, done)",
  "PY",
  "  )",
  "  echo \"$(date -Is) completed=${done_count}/${total}\" >> \"$log\"",
  "  if [ \"$done_count\" -eq \"$total\" ] && [ \"$total\" -gt 0 ]; then break; fi",
  "  sleep 300",
  "done",
  "bash \"$synth\" >> \"$log\" 2>&1",
  "bash \"$diag\" >> \"$log\" 2>&1",
  "echo \"$(date -Is) synthesis and diagnostics complete\" >> \"$log\""
)
writeLines(watch_lines, watch_path)
Sys.chmod(watch_path, "0755")

readme <- c(
  sprintf("# GloFAS Deep-Identity Full-Seven Candidate: %s", args$batch_id),
  "",
  "This directory is generated locally and ignored by git.",
  "",
  "Purpose: fit all seven quantiles for the confirmed p50 winner from the deep-identity follow-up grid.",
  "",
  "Selected contract:",
  "- DESN: `D=4`, `n=[100,100,100,100]`, identity reducers `n_tilde=[100,100,100]`.",
  "- Memory: `m=300`, washout `500`.",
  "- Dynamics: `alpha=0.05`, `rho=0.95` in every layer.",
  "- Sparsity/input: `pi_w=0.03`, `pi_in=1.00`, `win_scale_global=0.18`, `win_scale_bias=0.18`.",
  "- Seed: `20260512`.",
  "- Priors: shared `tau0=1e-3`; discrepancy `tau0=0.03`; slab `1.0`; `a_zeta=2`, `b_zeta=4`.",
  "- Inference: AL / VB-LD, `max_iter=250`, `tol=1e-3`, `tol_par=1e-3`, `n_draws=2000`.",
  "",
  "Prepared files:",
  sprintf("- launch manifest: `%s`", repo_rel(file.path(out_dir, "launch_manifest.csv"))),
  sprintf("- prelaunch validation: `%s`", repo_rel(file.path(out_dir, "prelaunch_validation.csv"))),
  sprintf("- synthesis source manifest: `%s`", repo_rel(file.path(out_dir, "synthesis_source_manifest.csv"))),
  sprintf("- synthesis config: `%s`", repo_rel(file.path(out_dir, "synthesis_config.yaml"))),
  sprintf("- launcher: `%s`", repo_rel(launch_path)),
  sprintf("- synthesis script: `%s`", repo_rel(synth_path)),
  sprintf("- diagnostic script: `%s`", repo_rel(diag_path)),
  sprintf("- watcher: `%s`", repo_rel(watch_path)),
  "",
  "Launch:",
  sprintf("`bash %s`", repo_rel(launch_path)),
  "",
  "After launch, start the watcher:",
  sprintf("`tmux new-session -d -s %s_watch 'bash %s'`", args$batch_id, repo_rel(watch_path)),
  "",
  "Promotion is not automatic. Promote only after synthesis readiness, diagnostics, and human figure review pass."
)
writeLines(readme, file.path(out_dir, "README.md"))

if (!all(prelaunch$launchable_without_overwrite)) {
  stop("One or more full-seven run directories already exist; refusing to prepare launchable package.", call. = FALSE)
}

cat("Prepared full-seven runtime package:\n")
cat(repo_rel(out_dir), "\n")
cat("Prelaunch rows:\n")
print(prelaunch, row.names = FALSE)
cat("Launcher:\n")
cat(repo_rel(launch_path), "\n")
