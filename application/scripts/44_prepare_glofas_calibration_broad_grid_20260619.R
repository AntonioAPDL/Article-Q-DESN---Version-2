#!/usr/bin/env Rscript
# Purpose: prepare a calibration-first full-seven GloFAS Q-DESN grid around the
# promoted deep-identity D4 application candidate. The generated runtime package
# is local/ignored and contains configs, manifests, a bounded scheduler, and
# finalization commands.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_deep_identity_d4w100m300a050_full7_20260618/config_p50.yaml",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_calibration_broad_grid_20260619",
  batch_id = "glofas_calibration_broad_grid_20260619",
  first_core = "24",
  n_cores = "24",
  max_active = "24"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))

target_levels <- c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95)
intervals <- list(
  list(lower = 0.05, upper = 0.95, nominal = 0.90),
  list(lower = 0.15, upper = 0.80, nominal = 0.65),
  list(lower = 0.35, upper = 0.65, nominal = 0.30)
)

stage_a_candidates <- data.frame(
  candidate_id = c(
    "cal01_anchor",
    "cal02_disc006",
    "cal03_disc010",
    "cal04_disc020",
    "cal05_disc001",
    "cal06_shared0003_disc006",
    "cal07_shared003_disc006",
    "cal08_disc006_slab4"
  ),
  stage = "A_calibration_full7",
  D = 4L,
  width = 100L,
  reservoir_m = 300L,
  alpha = 0.05,
  shared_tau0 = c(1e-3, 1e-3, 1e-3, 1e-3, 1e-3, 3e-4, 3e-3, 1e-3),
  discrepancy_tau0 = c(0.03, 0.06, 0.10, 0.20, 0.01, 0.06, 0.06, 0.06),
  shared_slab_s2 = 1.0,
  discrepancy_slab_s2 = c(1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 4.0),
  posterior_predictive_sampling = "disabled",
  purpose = c(
    "baseline repeat",
    "loosen discrepancy",
    "stronger discrepancy flexibility",
    "aggressive discrepancy flexibility",
    "tighter discrepancy",
    "protect shared block with looser discrepancy",
    "loosen shared block with looser discrepancy",
    "larger discrepancy slab"
  ),
  stringsAsFactors = FALSE
)

stage_b_candidates <- data.frame(
  candidate_id = c(
    "arch01_anchor",
    "arch02_m360",
    "arch03_m420",
    "arch04_a035",
    "arch05_a075",
    "arch06_w120",
    "arch07_w140",
    "arch08_d3w200",
    "arch09_d5w80",
    "arch10_d6w70"
  ),
  stage = "B_architecture_gate_p05p50p95",
  D = c(4L, 4L, 4L, 4L, 4L, 4L, 4L, 3L, 5L, 6L),
  width = c(100L, 100L, 100L, 100L, 100L, 120L, 140L, 200L, 80L, 70L),
  reservoir_m = c(300L, 360L, 420L, 300L, 300L, 300L, 300L, 300L, 300L, 300L),
  alpha = c(0.05, 0.05, 0.05, 0.035, 0.075, 0.05, 0.05, 0.05, 0.05, 0.05),
  shared_tau0 = 1e-3,
  discrepancy_tau0 = 0.03,
  shared_slab_s2 = 1.0,
  discrepancy_slab_s2 = 1.0,
  posterior_predictive_sampling = "disabled",
  purpose = c(
    "current anchor",
    "modest longer memory",
    "stronger memory test",
    "slower reservoir",
    "faster reservoir",
    "modest wider state",
    "wider bounded state",
    "strong earlier shallower comparator",
    "deeper compact model",
    "adventurous depth test"
  ),
  stringsAsFactors = FALSE
)

copy_cfg <- function(cfg) {
  cfg$.__config_path__ <- NULL
  cfg
}

repeat_value <- function(x, n) as.list(rep(x, n))

apply_candidate_contract <- function(cfg, candidate, full7 = TRUE) {
  D <- as.integer(candidate$D[[1L]])
  width <- as.integer(candidate$width[[1L]])
  m <- as.integer(candidate$reservoir_m[[1L]])
  alpha <- as.numeric(candidate$alpha[[1L]])

  cfg$reservoir$D <- D
  cfg$reservoir$n <- repeat_value(width, D)
  cfg$reservoir$n_tilde <- if (D > 1L) repeat_value(width, D - 1L) else list()
  cfg$reservoir$m <- m
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- repeat_value(alpha, D)
  cfg$reservoir$rho <- repeat_value(0.95, D)
  cfg$reservoir$pi_w <- repeat_value(0.03, D)
  cfg$reservoir$pi_in <- repeat_value(1.0, D)
  cfg$reservoir$win_scale_global <- 0.18
  cfg$reservoir$win_scale_bias <- 0.18
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$act_f <- "tanh"
  cfg$reservoir$act_k <- "identity"
  cfg$reservoir$standardize_inputs <- TRUE
  cfg$reservoir$add_bias <- TRUE
  cfg$reservoir$seed <- 20260512L

  cfg$covariates$readout$include_lags <- TRUE
  cfg$covariates$readout$lags <- list(range = c(0L, m))
  cfg$covariates$readout$standardize <- TRUE
  cfg$covariates$readout$scale_reference <- "retrospective_train"

  cfg$feature_contract$version <- "latent_path_v0.3"
  cfg$feature_contract$two_block_design <- TRUE
  cfg$feature_contract$reservoir_input$internal_bias <- TRUE
  cfg$feature_contract$reservoir_input$output_lags <- list(range = c(1L, m))
  cfg$feature_contract$reservoir_input$covariates$ppt <- list(range = c(0L, m))
  cfg$feature_contract$reservoir_input$covariates$soil <- list(range = c(0L, m))
  cfg$feature_contract$reservoir_input$standardize <- TRUE
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$reservoir_state_lags <- list()
  cfg$feature_contract$readout$include_input_block <- FALSE
  cfg$feature_contract$readout$input_block$output_lags <- list(range = c(1L, m))
  cfg$feature_contract$readout$input_block$covariates$ppt <- list(range = c(0L, m))
  cfg$feature_contract$readout$input_block$covariates$soil <- list(range = c(0L, m))
  cfg$feature_contract$readout$input_block$include_internal_bias <- FALSE
  cfg$feature_contract$readout$include_horizon_scaled <- FALSE
  cfg$feature_contract$readout$standardize_output_lags <- TRUE
  cfg$feature_contract$readout$standardize_non_intercept <- FALSE
  cfg$feature_contract$forecast_alignment$output_lags_anchor <- "target_date"
  cfg$feature_contract$forecast_alignment$covariate_lags_anchor <- "target_date"

  cfg$prediction$posterior_predictive_sampling <- as.character(candidate$posterior_predictive_sampling[[1L]])

  cfg$inference$default_method <- "vb_ld"
  cfg$inference$likelihood_family <- "al"
  cfg$inference$coefficient_prior_default <- "rhs"
  cfg$inference$vb_ld$max_iter <- if (isTRUE(full7)) 250L else 150L
  cfg$inference$vb_ld$max_iter_hard_cap <- if (isTRUE(full7)) 250L else 150L
  cfg$inference$vb_ld$tol <- 1e-3
  cfg$inference$vb_ld$tol_par <- 1e-3
  cfg$inference$vb_ld$n_samp_xi <- 500L
  cfg$inference$vb_ld$n_draws <- 2000L
  cfg$inference$vb_ld$rhs_tau0 <- as.numeric(candidate$shared_tau0[[1L]])
  cfg$inference$vb_ld$rhs_slab_s2 <- as.numeric(candidate$shared_slab_s2[[1L]])
  cfg$inference$vb_ld$rhs_a_zeta <- 2.0
  cfg$inference$vb_ld$rhs_b_zeta <- 4.0
  cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(candidate$discrepancy_tau0[[1L]])
  cfg$inference$vb_ld$rhs_alpha_slab_s2 <- as.numeric(candidate$discrepancy_slab_s2[[1L]])
  cfg$inference$vb_ld$rhs_alpha_a_zeta <- 2.0
  cfg$inference$vb_ld$rhs_alpha_b_zeta <- 4.0
  cfg$inference$vb_ld$rhs_freeze_tau_warmup_iters <- 50L
  cfg$inference$vb_ld$rhs_update_every <- 1L
  cfg$inference$vb_ld$rhs_min_tau_updates <- 1L
  cfg$inference$vb_ld$diagnostics$profile_substeps <- FALSE
  cfg$inference$vb_ld$diagnostics$trace_iterations <- FALSE

  cfg$execution$seed_contract <- cfg$execution$seed_contract %||% list()
  cfg$execution$seed_contract$require_config_model_grid_match <- TRUE
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- paste(
    "User-approved GloFAS calibration/broad-grid component.",
    "Do not promote a component or candidate without full synthesis and diagnostics."
  )
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg
}

make_fit_suffix <- function(batch_id, candidate_id, full7 = TRUE) {
  sprintf("%s_%s_%s", batch_id, candidate_id, if (isTRUE(full7)) "full7" else "gate")
}

prepare_candidate <- function(candidate, targets, base_cfg, base_grid, out_dir, batch_id, full7, core_start, core_count) {
  candidate_id <- as.character(candidate$candidate_id[[1L]])
  candidate_dir <- file.path(out_dir, candidate_id)
  app_ensure_dir(candidate_dir)
  app_ensure_dir(file.path(candidate_dir, "logs"))

  raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
  qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
  if (!nrow(raw_base) || !nrow(qdesn_base)) {
    stop("Base model grid must contain raw_glofas and qdesn_glofas_discrepancy rows.", call. = FALSE)
  }

  fit_suffix <- make_fit_suffix(batch_id, candidate_id, full7)
  raw_model_id <- paste0("raw_glofas_", fit_suffix)
  qdesn_model_id <- paste0("qdesn_latent_path_rhs_al_vb_", fit_suffix)
  rows_launch <- vector("list", nrow(targets))
  rows_source <- vector("list", nrow(targets))
  rows_model <- vector("list", nrow(targets))
  rows_qgrid <- vector("list", nrow(targets))
  rows_pre <- vector("list", nrow(targets))

  for (i in seq_len(nrow(targets))) {
    qid <- q_label(targets$quantile_id[[i]])
    qlev <- as.numeric(targets$quantile_level[[i]])
    role <- as.character(targets$role[[i]])
    run_id <- sprintf("%s_%s_%s", batch_id, candidate_id, qid)
    qgrid_path <- file.path(candidate_dir, sprintf("quantile_grid_%s.csv", qid))
    model_grid_path <- file.path(candidate_dir, sprintf("model_grid_%s.csv", qid))
    config_path <- file.path(candidate_dir, sprintf("config_%s.yaml", qid))
    log_path <- file.path("application/logs", sprintf("%s.log", run_id))
    session <- sprintf("%s_%s_%s", batch_id, candidate_id, qid)
    core <- core_start + ((i - 1L) %% core_count)

    app_write_csv(targets[i, , drop = FALSE], qgrid_path)
    rows_qgrid[[i]] <- targets[i, , drop = FALSE]

    raw_row <- raw_base
    qdesn_row <- qdesn_base
    raw_row$fit_id <- sprintf("%s_%s", raw_model_id, qid)
    raw_row$model_id <- raw_model_id
    raw_row$quantile_level <- qlev
    raw_row$config_hash <- "TO_BE_COMPUTED"
    raw_row$notes <- sprintf("Raw GloFAS baseline for %s/%s; quantile=%s (%s).", batch_id, candidate_id, qlev, role)
    qdesn_row$fit_id <- sprintf("%s_%s", qdesn_model_id, qid)
    qdesn_row$model_id <- qdesn_model_id
    qdesn_row$quantile_level <- qlev
    qdesn_row$reservoir_seed <- 20260512L
    qdesn_row$config_hash <- "TO_BE_COMPUTED"
    qdesn_row$notes <- sprintf("Q-DESN calibration/broad-grid component %s; quantile=%s (%s).", candidate_id, qlev, role)
    model_grid <- rbind(raw_row, qdesn_row)
    app_write_csv(model_grid, model_grid_path)
    rows_model[[i]] <- model_grid

    cfg <- apply_candidate_contract(copy_cfg(base_cfg), candidate, full7 = full7)
    cfg$application_name <- run_id
    cfg$description <- sprintf("GloFAS Q-DESN calibration/broad-grid component %s, quantile %s (%s).", candidate_id, qlev, role)
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
    rows_pre[[i]] <- data.frame(
      candidate_id = candidate_id,
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

    rows_launch[[i]] <- data.frame(
      batch_id = batch_id,
      candidate_id = candidate_id,
      stage = as.character(candidate$stage[[1L]]),
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
      run_dir = run_dir,
      launch_status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )

    rows_source[[i]] <- data.frame(
      batch_id = batch_id,
      candidate_id = candidate_id,
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
      source_kind = if (isTRUE(full7)) "calibration_full7_component" else "architecture_gate_component",
      required = TRUE,
      enabled = TRUE,
      stringsAsFactors = FALSE
    )
  }

  launch_manifest <- do.call(rbind, rows_launch)
  source_manifest <- do.call(rbind, rows_source)
  prelaunch <- do.call(rbind, rows_pre)
  model_grid_all <- do.call(rbind, rows_model)
  quantile_grid_all <- do.call(rbind, rows_qgrid)
  app_write_csv(launch_manifest, file.path(candidate_dir, "launch_manifest.csv"))
  app_write_csv(source_manifest, file.path(candidate_dir, "synthesis_source_manifest.csv"))
  app_write_csv(source_manifest, file.path(candidate_dir, "component_manifest.csv"))
  app_write_csv(prelaunch, file.path(candidate_dir, "prelaunch_validation.csv"))
  app_write_csv(model_grid_all, file.path(candidate_dir, "model_grid_all.csv"))
  app_write_csv(quantile_grid_all, file.path(candidate_dir, "quantile_grid_all.csv"))

  synthesis_cfg <- apply_candidate_contract(copy_cfg(base_cfg), candidate, full7 = full7)
  synthesis_cfg$application_name <- paste0(batch_id, "_", candidate_id, "_synthesis")
  synthesis_cfg$description <- sprintf("Post-hoc synthesis and scoring config for GloFAS candidate %s.", candidate_id)
  synthesis_cfg$paths$quantile_grid <- repo_rel(file.path(candidate_dir, "quantile_grid_all.csv"))
  synthesis_cfg$paths$model_grid <- repo_rel(file.path(candidate_dir, "model_grid_all.csv"))
  synthesis_cfg$paths$cache <- file.path("application/cache", paste0(batch_id, "_", candidate_id, "_synthesis"))
  synthesis_cfg$scoring$intervals <- intervals
  synthesis_cfg$execution$final_launch$enabled <- FALSE
  synthesis_cfg$execution$final_launch$note <- "Synthesis-only config; consumes completed per-quantile components."
  synthesis_cfg$post_analysis$run_after_outputs <- FALSE
  app_write_yaml(synthesis_cfg, file.path(candidate_dir, "synthesis_config.yaml"))

  source_manifest
}

write_stage_scheduler <- function(out_dir, batch_id, manifest_rel, max_active, stage_name) {
  path <- file.path(out_dir, sprintf("launch_%s_scheduler.sh", stage_name))
  state_path <- file.path(out_dir, sprintf("%s_scheduler_state.csv", stage_name))
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    "export OMP_NUM_THREADS=1",
    "export OPENBLAS_NUM_THREADS=1",
    "export MKL_NUM_THREADS=1",
    "export VECLIB_MAXIMUM_THREADS=1",
    "export NUMEXPR_NUM_THREADS=1",
    sprintf("manifest=%s", shQuote(manifest_rel)),
    sprintf("state=%s", shQuote(repo_rel(state_path))),
    sprintf("max_active=%d", as.integer(max_active)),
    sprintf("prefix=%s", shQuote(paste0(batch_id, "_"))),
    "mkdir -p application/logs",
    "echo 'time,event,candidate_id,quantile_id,session,run_id,detail' > \"$state\"",
    "python3 - \"$manifest\" <<'PY' | while IFS=$'\\t' read -r batch_id candidate_id stage quantile_id quantile_level role run_id config_path core log_path session run_dir; do",
    "import csv",
    "import sys",
    "with open(sys.argv[1], newline='') as handle:",
    "    for row in csv.DictReader(handle):",
    "        print('\\t'.join(str(row.get(k, '')) for k in ['batch_id','candidate_id','stage','quantile_id','quantile_level','role','run_id','config_path','core','log_path','session','run_dir']))",
    "PY",
    "  while true; do",
    "    active=$(tmux list-sessions -F '#S' 2>/dev/null | grep -c \"^${prefix}\" || true)",
    "    if [ \"$active\" -lt \"$max_active\" ]; then break; fi",
    "    sleep 60",
    "  done",
    "  if [ -e \"$run_dir/tables/fit_status.csv\" ]; then",
    "    echo \"$(date -Is),skip_existing,$candidate_id,$quantile_id,$session,$run_id,$run_dir\" >> \"$state\"",
    "    continue",
    "  fi",
    "  if tmux has-session -t \"$session\" 2>/dev/null; then",
    "    echo \"$(date -Is),skip_session_exists,$candidate_id,$quantile_id,$session,$run_id,$run_dir\" >> \"$state\"",
    "    continue",
    "  fi",
    "  cmd=\"taskset -c $core Rscript application/scripts/run_all.R --config $config_path --run_id $run_id --preflight true --confirm_final_launch true > $log_path 2>&1\"",
    "  tmux new-session -d -s \"$session\" \"$cmd\"",
    "  echo \"$(date -Is),launched,$candidate_id,$quantile_id,$session,$run_id,core=$core\" >> \"$state\"",
    "done",
    "echo \"$(date -Is),scheduler_complete,,,,,\" >> \"$state\""
  )
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

write_candidate_finalizer <- function(out_dir, batch_id, candidates, stage_name, figure_prefix) {
  path <- file.path(out_dir, sprintf("finalize_%s_candidates.sh", stage_name))
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    sprintf("log=%s", shQuote(file.path("application/logs", sprintf("%s_%s_finalize.log", batch_id, stage_name)))),
    "echo \"$(date -Is) finalizer started\" >> \"$log\""
  )
  for (candidate_id in candidates$candidate_id) {
    candidate_dir <- repo_rel(file.path(out_dir, candidate_id))
    synth_run <- sprintf("%s_%s_synthesis_final", batch_id, candidate_id)
    diag_run <- sprintf("%s_%s_diagnostic_figures", batch_id, candidate_id)
    lines <- c(
      lines,
      sprintf("echo '--- %s ---' >> \"$log\"", candidate_id),
      sprintf(
        "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R --config %s --source_manifest %s --run_id %s >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(synth_run)
      ),
      sprintf(
        "Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R --config %s --source_manifest %s --synthesis_run_id %s --run_id %s --figure_prefix %s >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(synth_run),
        shQuote(diag_run),
        shQuote(figure_prefix)
      )
    )
  }
  lines <- c(lines, "echo \"$(date -Is) finalizer complete\" >> \"$log\"")
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

write_stage_watcher <- function(out_dir, batch_id, manifest_rel, finalizer_rel, stage_name) {
  path <- file.path(out_dir, sprintf("watch_and_finalize_%s.sh", stage_name))
  log_path <- file.path("application/logs", sprintf("%s_%s_watch.log", batch_id, stage_name))
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    sprintf("manifest=%s", shQuote(manifest_rel)),
    sprintf("finalizer=%s", shQuote(finalizer_rel)),
    sprintf("log=%s", shQuote(log_path)),
    "echo \"$(date -Is) watch started\" >> \"$log\"",
    "while true; do",
    "  read -r total done_count failed_count < <(python3 - \"$manifest\" <<'PY'",
    "import csv",
    "import pathlib",
    "import sys",
    "total = done = failed = 0",
    "with open(sys.argv[1], newline='') as handle:",
    "    for row in csv.DictReader(handle):",
    "        total += 1",
    "        run_dir = pathlib.Path(row['run_dir'])",
    "        fit = run_dir / 'tables' / 'fit_status.csv'",
    "        pred = run_dir / 'tables' / 'prediction_quantiles.csv'",
    "        if fit.is_file():",
    "            txt = fit.read_text(errors='ignore')",
    "            if 'failed' in txt.lower():",
    "                failed += 1",
    "            if 'completed' in txt.lower() and pred.is_file() and pred.stat().st_size > 0:",
    "                done += 1",
    "print(total, done, failed)",
    "PY",
    "  )",
    "  echo \"$(date -Is) completed=${done_count}/${total} failed=${failed_count}\" >> \"$log\"",
    "  if [ \"$failed_count\" -gt 0 ]; then echo \"failure detected; not finalizing\" >> \"$log\"; exit 1; fi",
    "  if [ \"$done_count\" -eq \"$total\" ] && [ \"$total\" -gt 0 ]; then break; fi",
    "  sleep 300",
    "done",
    "bash \"$finalizer\" >> \"$log\" 2>&1",
    "echo \"$(date -Is) watch/finalize complete\" >> \"$log\""
  )
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

out_dir <- app_path(args$out_dir)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "logs"))

base_cfg <- copy_cfg(app_read_config(app_path(args$base_config)))
base_grid <- app_validate_model_grid(app_config_path(base_cfg, "model_grid"), app_config_path(base_cfg, "schema"))
targets_all <- app_validate_quantile_grid(app_path(args$quantile_targets))
targets_stage_a <- targets_all[round(as.numeric(targets_all$quantile_level), 8) %in% target_levels, , drop = FALSE]
targets_stage_a <- targets_stage_a[order(as.numeric(targets_stage_a$quantile_level)), , drop = FALSE]
if (!identical(round(as.numeric(targets_stage_a$quantile_level), 8), target_levels)) {
  stop("Quantile target file must contain p05, p15, p35, p50, p65, p80, and p95.", call. = FALSE)
}
targets_stage_b <- targets_stage_a[round(as.numeric(targets_stage_a$quantile_level), 8) %in% c(0.05, 0.50, 0.95), , drop = FALSE]

first_core <- as.integer(args$first_core)
n_core_use <- as.integer(args$n_cores)
max_active <- as.integer(args$max_active)
n_detected <- parallel::detectCores(logical = TRUE)
if (any(!is.finite(c(first_core, n_core_use, max_active))) || first_core < 0L || n_core_use < 1L || max_active < 1L) {
  stop("Invalid core scheduler arguments.", call. = FALSE)
}
if ((first_core + n_core_use - 1L) >= n_detected) {
  stop(sprintf("Requested cores %d:%d exceed detected core count %d.", first_core, first_core + n_core_use - 1L, n_detected), call. = FALSE)
}

app_write_csv(stage_a_candidates, file.path(out_dir, "stage_a_candidate_manifest.csv"))
app_write_csv(stage_b_candidates, file.path(out_dir, "stage_b_candidate_manifest.csv"))

stage_a_sources <- lapply(seq_len(nrow(stage_a_candidates)), function(i) {
  prepare_candidate(stage_a_candidates[i, , drop = FALSE], targets_stage_a, base_cfg, base_grid, out_dir, args$batch_id, TRUE, first_core, n_core_use)
})
stage_a_manifest <- app_bind_rows_fill(stage_a_sources)
app_write_csv(stage_a_manifest, file.path(out_dir, "stage_a_component_launch_manifest.csv"))
stage_a_launch_manifest <- app_bind_rows_fill(lapply(stage_a_candidates$candidate_id, function(candidate_id) {
  app_read_csv(file.path(out_dir, candidate_id, "launch_manifest.csv"))
}))
stage_a_launch_manifest$core <- first_core + ((seq_len(nrow(stage_a_launch_manifest)) - 1L) %% n_core_use)
app_write_csv(stage_a_launch_manifest, file.path(out_dir, "stage_a_scheduler_manifest.csv"))

stage_b_sources <- lapply(seq_len(nrow(stage_b_candidates)), function(i) {
  prepare_candidate(stage_b_candidates[i, , drop = FALSE], targets_stage_b, base_cfg, base_grid, out_dir, args$batch_id, FALSE, first_core, n_core_use)
})
stage_b_manifest <- app_bind_rows_fill(stage_b_sources)
app_write_csv(stage_b_manifest, file.path(out_dir, "stage_b_component_launch_manifest.csv"))
stage_b_launch_manifest <- app_bind_rows_fill(lapply(stage_b_candidates$candidate_id, function(candidate_id) {
  app_read_csv(file.path(out_dir, candidate_id, "launch_manifest.csv"))
}))
stage_b_launch_manifest$core <- first_core + ((seq_len(nrow(stage_b_launch_manifest)) - 1L) %% n_core_use)
app_write_csv(stage_b_launch_manifest, file.path(out_dir, "stage_b_scheduler_manifest.csv"))

stage_a_launch <- write_stage_scheduler(
  out_dir,
  args$batch_id,
  repo_rel(file.path(out_dir, "stage_a_scheduler_manifest.csv")),
  max_active,
  "stage_a"
)
stage_b_launch <- write_stage_scheduler(
  out_dir,
  args$batch_id,
  repo_rel(file.path(out_dir, "stage_b_scheduler_manifest.csv")),
  max_active,
  "stage_b"
)
stage_a_finalize <- write_candidate_finalizer(out_dir, args$batch_id, stage_a_candidates, "stage_a", "glofas_calibration_grid_full7")
stage_b_finalize <- write_candidate_finalizer(out_dir, args$batch_id, stage_b_candidates, "stage_b", "glofas_architecture_gate")
stage_a_watch <- write_stage_watcher(
  out_dir,
  args$batch_id,
  repo_rel(file.path(out_dir, "stage_a_scheduler_manifest.csv")),
  repo_rel(stage_a_finalize),
  "stage_a"
)
stage_b_watch <- write_stage_watcher(
  out_dir,
  args$batch_id,
  repo_rel(file.path(out_dir, "stage_b_scheduler_manifest.csv")),
  repo_rel(stage_b_finalize),
  "stage_b"
)

readme <- c(
  "# GloFAS Calibration and Broad Grid Runtime Package",
  "",
  "Generated by `application/scripts/44_prepare_glofas_calibration_broad_grid_20260619.R`.",
  "",
  "This directory is ignored by git and is intended as the live operational tracker.",
  "",
  "Stage A is the calibration-first full-seven grid. Stage B is the p05/p50/p95 architecture gate.",
  "",
  "Prepared files:",
  sprintf("- Stage A candidates: `%s`", repo_rel(file.path(out_dir, "stage_a_candidate_manifest.csv"))),
  sprintf("- Stage A components: `%s`", repo_rel(file.path(out_dir, "stage_a_component_launch_manifest.csv"))),
  sprintf("- Stage A scheduler manifest: `%s`", repo_rel(file.path(out_dir, "stage_a_scheduler_manifest.csv"))),
  sprintf("- Stage A scheduler: `%s`", repo_rel(stage_a_launch)),
  sprintf("- Stage A finalizer: `%s`", repo_rel(stage_a_finalize)),
  sprintf("- Stage A watcher: `%s`", repo_rel(stage_a_watch)),
  sprintf("- Stage B candidates: `%s`", repo_rel(file.path(out_dir, "stage_b_candidate_manifest.csv"))),
  sprintf("- Stage B components: `%s`", repo_rel(file.path(out_dir, "stage_b_component_launch_manifest.csv"))),
  sprintf("- Stage B scheduler manifest: `%s`", repo_rel(file.path(out_dir, "stage_b_scheduler_manifest.csv"))),
  sprintf("- Stage B scheduler: `%s`", repo_rel(stage_b_launch)),
  sprintf("- Stage B finalizer: `%s`", repo_rel(stage_b_finalize)),
  sprintf("- Stage B watcher: `%s`", repo_rel(stage_b_watch)),
  "",
  "Recommended execution order:",
  "",
  "1. Clean old non-reference GloFAS heavy objects.",
  "2. Launch Stage A scheduler.",
  "3. Monitor Stage A completion.",
  "4. Run Stage A finalizer.",
  "5. Select calibration settings.",
  "6. Launch Stage B only after Stage A evidence is reviewed.",
  "",
  "Do not promote any candidate without full synthesis, diagnostics, and human figure review."
)
writeLines(readme, file.path(out_dir, "README.md"))

cat("Prepared GloFAS calibration/broad-grid package:\n")
cat(repo_rel(out_dir), "\n")
cat(sprintf("Stage A components: %d\n", nrow(stage_a_manifest)))
cat(sprintf("Stage B components: %d\n", nrow(stage_b_manifest)))
cat("Stage A scheduler:\n")
cat(repo_rel(stage_a_launch), "\n")
cat("Stage A finalizer:\n")
cat(repo_rel(stage_a_finalize), "\n")
