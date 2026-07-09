#!/usr/bin/env Rscript
# Purpose: prepare a controlled Stage E p05/p50/p95 tail gate for selected
# GloFAS Stage D median-gate candidates. The package reuses completed p50 fits
# and launches only p05 and p95 tail fits.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))

args <- app_parse_args(list(
  stage_d_runtime_dir = "local_trackers/runtime_configs/glofas_stage_d_local_refinement_20260623",
  candidate_ids = "d_alpha_025,d_alpha_050,d_fast_tight,d_anchor_exact",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_stage_e_tail_gate_20260623",
  batch_id = "glofas_stage_e_tail_gate_20260623",
  first_core = "28",
  n_cores = "8",
  max_active = "8",
  spread_factor = "1.4",
  spread_additive_width = "0.5",
  spread_center_quantile = "0.5",
  spread_calibration_id = "scorebalanced_spread_x1p400_plus0p500"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))
parse_ids <- function(x) {
  ids <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  ids[nzchar(ids)]
}

make_scorebalanced_config <- function(cfg) {
  cfg$synthesis <- cfg$synthesis %||% list()
  cfg$synthesis$spread_calibration <- list(
    enabled = TRUE,
    factor = as.numeric(args$spread_factor),
    additive_width = as.numeric(args$spread_additive_width),
    center_quantile = as.numeric(args$spread_center_quantile),
    calibration_id = as.character(args$spread_calibration_id)
  )
  cfg
}

intervals <- list(list(lower = 0.05, upper = 0.95, nominal = 0.90))
target_levels <- c(0.05, 0.50, 0.95)
reuse_levels <- c(0.50)
launch_levels <- setdiff(target_levels, reuse_levels)

candidate_ids <- parse_ids(args$candidate_ids)
if (!length(candidate_ids)) stop("No Stage E candidate ids were provided.", call. = FALSE)

out_dir <- app_path(args$out_dir)
stage_d_dir <- app_path(args$stage_d_runtime_dir)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "logs"))

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

targets <- app_validate_quantile_grid(app_path(args$quantile_targets))
targets <- targets[round(as.numeric(targets$quantile_level), 8) %in% target_levels, , drop = FALSE]
targets <- targets[order(as.numeric(targets$quantile_level)), , drop = FALSE]
if (!identical(round(as.numeric(targets$quantile_level), 8), target_levels)) {
  stop("Quantile target file must contain p05, p50, and p95 for Stage E.", call. = FALSE)
}

stage_d_candidates <- app_read_csv(file.path(stage_d_dir, "candidate_manifest.csv"))
stage_d_components <- app_read_csv(file.path(stage_d_dir, "median_gate_manifest.csv"))
candidate_rows <- stage_d_candidates[stage_d_candidates$candidate_id %in% candidate_ids, , drop = FALSE]
if (nrow(candidate_rows) != length(candidate_ids)) {
  missing <- setdiff(candidate_ids, candidate_rows$candidate_id)
  stop(sprintf("Missing Stage D candidate definitions: %s", paste(missing, collapse = ", ")), call. = FALSE)
}

apply_quantile_to_config <- function(cfg, qlev, role, run_id, qgrid_path, model_grid_path) {
  cfg$application_name <- run_id
  cfg$description <- paste(
    "GloFAS Stage E tail-gate component.",
    sprintf("Quantile %s (%s).", qlev, role),
    "Completed p50 is reused from Stage D."
  )
  cfg$paths$quantile_grid <- repo_rel(qgrid_path)
  cfg$paths$model_grid <- repo_rel(model_grid_path)
  cfg$paths$cache <- file.path("application/cache", run_id)
  cfg$scoring$intervals <- intervals
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- "User-approved Stage E p05/p95 tail-gate component."
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg
}

prepare_one_candidate <- function(candidate_id, candidate_index, core_offset) {
  stage_d_cand_dir <- file.path(stage_d_dir, candidate_id)
  if (!dir.exists(stage_d_cand_dir)) stop(sprintf("Missing Stage D candidate dir: %s", stage_d_cand_dir), call. = FALSE)

  cand_dir <- file.path(out_dir, candidate_id)
  app_ensure_dir(cand_dir)
  app_ensure_dir(file.path(cand_dir, "logs"))

  base_cfg_path <- file.path(stage_d_cand_dir, "config_p50.yaml")
  base_grid_path <- file.path(stage_d_cand_dir, "model_grid_p50.csv")
  base_cfg <- app_read_config(base_cfg_path)
  base_cfg$.__config_path__ <- NULL
  base_grid <- app_validate_model_grid(base_grid_path, app_config_path(base_cfg, "schema"))
  raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
  qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
  if (!nrow(raw_base) || !nrow(qdesn_base)) {
    stop(sprintf("Candidate %s model grid must contain raw_glofas and qdesn_glofas_discrepancy rows.", candidate_id), call. = FALSE)
  }
  raw_model_id <- raw_base$model_id[[1L]]
  qdesn_model_id <- qdesn_base$model_id[[1L]]

  component_rows <- vector("list", nrow(targets))
  launch_rows <- list()
  model_rows_all <- list()
  qgrid_rows_all <- list()
  prelaunch_rows <- list()

  for (i in seq_len(nrow(targets))) {
    qid <- q_label(targets$quantile_id[[i]])
    qlev <- as.numeric(targets$quantile_level[[i]])
    role <- as.character(targets$role[[i]])
    is_reused <- any(abs(qlev - reuse_levels) < 1e-12)

    if (is_reused) {
      d_row <- stage_d_components[
        stage_d_components$candidate_id == candidate_id &
          abs(as.numeric(stage_d_components$quantile_level) - qlev) < 1e-12,
        ,
        drop = FALSE
      ]
      if (nrow(d_row) != 1L) stop(sprintf("Missing unique Stage D p50 row for %s.", candidate_id), call. = FALSE)
      fit_status_path <- file.path(app_path(d_row$run_dir[[1L]]), "tables", "fit_status.csv")
      pred_path <- file.path(app_path(d_row$run_dir[[1L]]), "tables", "prediction_quantiles.csv")
      ok <- file.exists(fit_status_path) && file.exists(pred_path)
      if (ok) {
        fit_status <- app_read_csv(fit_status_path)
        ids <- c(d_row$raw_fit_id[[1L]], d_row$qdesn_fit_id[[1L]])
        rows <- fit_status[fit_status$fit_id %in% ids, , drop = FALSE]
        ok <- nrow(rows) == 2L && all(rows$status == "completed")
      }
      prelaunch_rows[[length(prelaunch_rows) + 1L]] <- data.frame(
        candidate_id = candidate_id,
        quantile_id = qid,
        quantile_level = qlev,
        source_kind = "reused_stage_d_median_gate",
        ready = ok,
        detail = d_row$run_dir[[1L]],
        stringsAsFactors = FALSE
      )
      component_rows[[i]] <- data.frame(
        batch_id = args$batch_id,
        candidate_id = candidate_id,
        run_index = i,
        quantile_id = qid,
        quantile_level = qlev,
        role = role,
        run_id = d_row$run_id[[1L]],
        config_path = d_row$config_path[[1L]],
        quantile_grid_path = d_row$quantile_grid_path[[1L]],
        model_grid_path = d_row$model_grid_path[[1L]],
        run_dir = d_row$run_dir[[1L]],
        raw_fit_id = d_row$raw_fit_id[[1L]],
        qdesn_fit_id = d_row$qdesn_fit_id[[1L]],
        raw_model_id = d_row$raw_model_id[[1L]],
        qdesn_model_id = d_row$qdesn_model_id[[1L]],
        source_kind = paste0("reused_stage_d_median_gate_", candidate_id),
        required = TRUE,
        enabled = TRUE,
        stringsAsFactors = FALSE
      )
      model_rows_all[[length(model_rows_all) + 1L]] <- base_grid
      qgrid_rows_all[[length(qgrid_rows_all) + 1L]] <- app_read_csv(app_path(d_row$quantile_grid_path[[1L]]))
      next
    }

    run_id <- sprintf("%s_%s_%s", args$batch_id, candidate_id, qid)
    qgrid_path <- file.path(cand_dir, sprintf("quantile_grid_%s.csv", qid))
    model_grid_path <- file.path(cand_dir, sprintf("model_grid_%s.csv", qid))
    config_path <- file.path(cand_dir, sprintf("config_%s.yaml", qid))
    app_write_csv(targets[i, , drop = FALSE], qgrid_path)

    raw_row <- raw_base
    qdesn_row <- qdesn_base
    raw_row$fit_id <- sprintf("%s_%s", raw_model_id, qid)
    raw_row$quantile_level <- qlev
    raw_row$config_hash <- "TO_BE_COMPUTED"
    raw_row$notes <- sprintf("Raw GloFAS baseline for Stage E %s; quantile=%s (%s).", candidate_id, qlev, role)
    qdesn_row$fit_id <- sprintf("%s_%s", qdesn_model_id, qid)
    qdesn_row$quantile_level <- qlev
    qdesn_row$reservoir_seed <- app_config_reservoir_seed(base_cfg)
    qdesn_row$config_hash <- "TO_BE_COMPUTED"
    qdesn_row$notes <- sprintf("Q-DESN Stage E tail-gate component %s; quantile=%s (%s).", candidate_id, qlev, role)
    model_grid <- rbind(raw_row, qdesn_row)
    app_write_csv(model_grid, model_grid_path)

    cfg <- apply_quantile_to_config(base_cfg, qlev, role, run_id, qgrid_path, model_grid_path)
    app_write_yaml(cfg, config_path)

    validated_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
    app_validate_qdesn_model_grid_prior_contract(validated_grid)
    app_validate_qdesn_seed_contract(cfg, validated_grid)
    engine_report <- app_check_qdesn_engine_api(
      cfg,
      require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, validated_grid),
      stop_on_failure = TRUE
    )

    core <- first_core + ((core_offset + length(launch_rows)) %% n_core_use)
    session <- sprintf("%s_%s_%s", args$batch_id, candidate_id, qid)
    log_path <- file.path("application/logs", sprintf("%s.log", run_id))
    run_dir <- file.path("application/runs", run_id)
    prelaunch_rows[[length(prelaunch_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      quantile_id = qid,
      quantile_level = qlev,
      source_kind = "new_stage_e_tail_gate",
      ready = isTRUE(engine_report$ok) && !file.exists(app_path(run_dir)),
      detail = run_dir,
      stringsAsFactors = FALSE
    )
    launch_rows[[length(launch_rows) + 1L]] <- data.frame(
      batch_id = args$batch_id,
      candidate_id = candidate_id,
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
      run_dir = run_dir,
      launch_status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
    component_rows[[i]] <- data.frame(
      batch_id = args$batch_id,
      candidate_id = candidate_id,
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
      source_kind = "new_stage_e_tail_gate",
      required = TRUE,
      enabled = TRUE,
      stringsAsFactors = FALSE
    )
    model_rows_all[[length(model_rows_all) + 1L]] <- model_grid
    qgrid_rows_all[[length(qgrid_rows_all) + 1L]] <- targets[i, , drop = FALSE]
  }

  source_manifest <- do.call(rbind, component_rows)
  source_manifest <- source_manifest[order(source_manifest$run_index), , drop = FALSE]
  launch_manifest <- if (length(launch_rows)) do.call(rbind, launch_rows) else data.frame()
  prelaunch <- do.call(rbind, prelaunch_rows)
  qgrid_all <- do.call(rbind, qgrid_rows_all)
  qgrid_all <- qgrid_all[order(as.numeric(qgrid_all$quantile_level)), , drop = FALSE]
  model_grid_all <- app_bind_rows_fill(model_rows_all)

  app_write_csv(source_manifest, file.path(cand_dir, "synthesis_source_manifest.csv"))
  app_write_csv(source_manifest, file.path(cand_dir, "component_manifest.csv"))
  app_write_csv(launch_manifest, file.path(cand_dir, "launch_manifest.csv"))
  app_write_csv(prelaunch, file.path(cand_dir, "prelaunch_validation.csv"))
  app_write_csv(qgrid_all, file.path(cand_dir, "quantile_grid_all.csv"))
  app_write_csv(model_grid_all, file.path(cand_dir, "model_grid_all.csv"))

  synthesis_cfg <- base_cfg
  synthesis_cfg$application_name <- paste0(args$batch_id, "_", candidate_id, "_tail_synthesis")
  synthesis_cfg$description <- sprintf("Stage E p05/p50/p95 raw synthesis and scoring config for GloFAS candidate %s.", candidate_id)
  synthesis_cfg$paths$quantile_grid <- repo_rel(file.path(cand_dir, "quantile_grid_all.csv"))
  synthesis_cfg$paths$model_grid <- repo_rel(file.path(cand_dir, "model_grid_all.csv"))
  synthesis_cfg$paths$cache <- file.path("application/cache", paste0(args$batch_id, "_", candidate_id, "_tail_synthesis"))
  synthesis_cfg$scoring$intervals <- intervals
  synthesis_cfg$execution$final_launch$enabled <- FALSE
  synthesis_cfg$execution$final_launch$note <- "Tail-gate synthesis-only config; consumes completed Stage E component fits."
  synthesis_cfg$post_analysis$run_after_outputs <- FALSE
  app_write_yaml(synthesis_cfg, file.path(cand_dir, "synthesis_config.yaml"))
  app_write_yaml(make_scorebalanced_config(synthesis_cfg), file.path(cand_dir, "synthesis_config_scorebalanced.yaml"))

  list(source_manifest = source_manifest, launch_manifest = launch_manifest, prelaunch = prelaunch)
}

candidate_payloads <- vector("list", length(candidate_ids))
for (j in seq_along(candidate_ids)) {
  candidate_payloads[[j]] <- prepare_one_candidate(candidate_ids[[j]], j, (j - 1L) * length(launch_levels))
}

all_launch <- app_bind_rows_fill(lapply(candidate_payloads, `[[`, "launch_manifest"))
all_components <- app_bind_rows_fill(lapply(candidate_payloads, `[[`, "source_manifest"))
all_prelaunch <- app_bind_rows_fill(lapply(candidate_payloads, `[[`, "prelaunch"))
app_write_csv(candidate_rows, file.path(out_dir, "stage_e_candidate_manifest.csv"))
app_write_csv(all_launch, file.path(out_dir, "stage_e_scheduler_manifest.csv"))
app_write_csv(all_components, file.path(out_dir, "stage_e_component_manifest.csv"))
app_write_csv(all_prelaunch, file.path(out_dir, "stage_e_prelaunch_validation.csv"))

if (!all(app_as_bool_vec(all_prelaunch$ready))) {
  failed <- all_prelaunch[!app_as_bool_vec(all_prelaunch$ready), , drop = FALSE]
  app_write_csv(failed, file.path(out_dir, "stage_e_prelaunch_failures.csv"))
  stop(sprintf("Stage E prelaunch validation failed for %d rows.", nrow(failed)), call. = FALSE)
}

write_stage_scheduler <- function() {
  path <- file.path(out_dir, sprintf("launch_%s_scheduler.sh", args$batch_id))
  state_path <- file.path(out_dir, "stage_e_scheduler_state.csv")
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    "export OMP_NUM_THREADS=1",
    "export OPENBLAS_NUM_THREADS=1",
    "export MKL_NUM_THREADS=1",
    "export VECLIB_MAXIMUM_THREADS=1",
    "export NUMEXPR_NUM_THREADS=1",
    sprintf("manifest=%s", shQuote(repo_rel(file.path(out_dir, "stage_e_scheduler_manifest.csv")))),
    sprintf("state=%s", shQuote(repo_rel(state_path))),
    sprintf("max_active=%d", max_active),
    sprintf("prefix=%s", shQuote(paste0(args$batch_id, "_"))),
    "mkdir -p application/logs",
    "echo 'time,event,candidate_id,quantile_id,session,run_id,detail' > \"$state\"",
    "python3 - \"$manifest\" <<'PY' | while IFS=$'\\t' read -r batch_id candidate_id run_index quantile_id quantile_level role run_id config_path core log_path session run_dir; do",
    "import csv",
    "import sys",
    "cols = ['batch_id','candidate_id','run_index','quantile_id','quantile_level','role','run_id','config_path','core','log_path','session','run_dir']",
    "with open(sys.argv[1], newline='') as handle:",
    "    for row in csv.DictReader(handle):",
    "        print('\\t'.join(str(row.get(k, '')) for k in cols))",
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

write_stage_finalizer <- function() {
  path <- file.path(out_dir, sprintf("finalize_%s_candidates.sh", args$batch_id))
  log_path <- file.path("application/logs", sprintf("%s_finalize.log", args$batch_id))
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    sprintf("log=%s", shQuote(log_path)),
    "echo \"$(date -Is) finalizer started\" >> \"$log\""
  )
  for (candidate_id in candidate_ids) {
    candidate_dir <- repo_rel(file.path(out_dir, candidate_id))
    raw_run <- sprintf("%s_%s_tail_synthesis_final", args$batch_id, candidate_id)
    score_run <- sprintf("%s_%s_tail_scorebalanced_synthesis_final", args$batch_id, candidate_id)
    raw_diag <- sprintf("%s_%s_tail_diagnostic_figures", args$batch_id, candidate_id)
    score_diag <- sprintf("%s_%s_tail_scorebalanced_diagnostic_figures", args$batch_id, candidate_id)
    prefix <- sprintf("glofas_stage_e_%s", candidate_id)
    lines <- c(
      lines,
      sprintf("echo '--- %s raw tail ---' >> \"$log\"", candidate_id),
      sprintf(
        "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R --config %s --source_manifest %s --run_id %s >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(raw_run)
      ),
      sprintf(
        "Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R --config %s --source_manifest %s --synthesis_run_id %s --run_id %s --figure_prefix %s >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(raw_run),
        shQuote(raw_diag),
        shQuote(prefix)
      ),
      sprintf("echo '--- %s scorebalanced tail ---' >> \"$log\"", candidate_id),
      sprintf(
        "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R --config %s --source_manifest %s --run_id %s >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config_scorebalanced.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(score_run)
      ),
      sprintf(
        "Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R --config %s --source_manifest %s --synthesis_run_id %s --run_id %s --figure_prefix %s_scorebalanced >> \"$log\" 2>&1",
        shQuote(file.path(candidate_dir, "synthesis_config_scorebalanced.yaml")),
        shQuote(file.path(candidate_dir, "synthesis_source_manifest.csv")),
        shQuote(score_run),
        shQuote(score_diag),
        shQuote(prefix)
      )
    )
  }
  lines <- c(lines, "echo \"$(date -Is) finalizer complete\" >> \"$log\"")
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

write_stage_watcher <- function(finalizer_path) {
  path <- file.path(out_dir, sprintf("watch_and_finalize_%s.sh", args$batch_id))
  log_path <- file.path("application/logs", sprintf("%s_watch.log", args$batch_id))
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    sprintf("manifest=%s", shQuote(repo_rel(file.path(out_dir, "stage_e_component_manifest.csv")))),
    sprintf("finalizer=%s", shQuote(repo_rel(finalizer_path))),
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
    "        ids = {row['raw_fit_id'], row['qdesn_fit_id']}",
    "        if fit.is_file():",
    "            txt = fit.read_text(errors='ignore')",
    "            if 'failed' in txt.lower():",
    "                failed += 1",
    "            if all(x in txt for x in ids) and txt.lower().count('completed') >= 2 and pred.is_file() and pred.stat().st_size > 0:",
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

write_stage_health <- function() {
  path <- file.path(out_dir, sprintf("health_check_%s.R", args$batch_id))
  r_string <- function(x) paste0("\"", gsub("\\\\", "\\\\\\\\", gsub("\"", "\\\\\"", x, fixed = TRUE)), "\"")
  lines <- c(
    "#!/usr/bin/env Rscript",
    sprintf("repo_root <- %s", r_string(app_repo_root())),
    "source(file.path(repo_root, 'application/R/00_packages.R'))",
    "app_set_repo_root(repo_root)",
    sprintf("component_manifest_path <- %s", r_string(repo_rel(file.path(out_dir, "stage_e_component_manifest.csv")))),
    sprintf("out_path <- %s", r_string(repo_rel(file.path(out_dir, "health_check_latest.csv")))),
    "m <- read.csv(file.path(repo_root, component_manifest_path), stringsAsFactors = FALSE)",
    "sessions <- tryCatch(system(\"tmux list-sessions -F '#S'\", intern = TRUE, ignore.stderr = TRUE), error = function(e) character())",
    "rows <- lapply(seq_len(nrow(m)), function(i) {",
    "  r <- m[i, , drop = FALSE]",
    "  run_dir <- file.path(repo_root, r$run_dir)",
    "  fit_path <- file.path(run_dir, 'tables', 'fit_status.csv')",
    "  score_path <- file.path(run_dir, 'tables', 'score_summary.csv')",
    "  pred_path <- file.path(run_dir, 'tables', 'prediction_quantiles.csv')",
    "  status <- if (!file.exists(fit_path)) {",
    "    if ((('session' %in% names(r)) && r$session %in% sessions) || r$run_id %in% sessions) 'running' else 'pending'",
    "  } else {",
    "    fit <- read.csv(fit_path, stringsAsFactors = FALSE)",
    "    ids <- c(r$raw_fit_id, r$qdesn_fit_id)",
    "    if (any(tolower(fit$status) == 'failed')) 'failed' else if (all(ids %in% fit$fit_id) && all(fit$status[fit$fit_id %in% ids] == 'completed') && file.exists(pred_path)) 'completed' else 'running'",
    "  }",
    "  check <- raw_check <- NA_real_",
    "  if (file.exists(score_path)) {",
    "    s <- read.csv(score_path, stringsAsFactors = FALSE)",
    "    q <- s[grepl('qdesn', s$model_id, ignore.case = TRUE), , drop = FALSE]",
    "    raw <- s[grepl('raw_glofas', s$model_id, ignore.case = TRUE), , drop = FALSE]",
    "    check <- if (nrow(q) && 'check_loss_mean' %in% names(q)) as.numeric(q$check_loss_mean[1]) else NA_real_",
    "    raw_check <- if (nrow(raw) && 'check_loss_mean' %in% names(raw)) as.numeric(raw$check_loss_mean[1]) else NA_real_",
    "  }",
    "  data.frame(candidate_id=r$candidate_id, quantile_id=r$quantile_id, quantile_level=as.numeric(r$quantile_level), status=status, check_loss_mean=check, raw_check_loss_mean=raw_check, source_kind=r$source_kind, run_id=r$run_id, run_dir=r$run_dir, stringsAsFactors=FALSE)",
    "})",
    "d <- do.call(rbind, rows)",
    "write.csv(d, file.path(repo_root, out_path), row.names = FALSE)",
    "print(d[order(d$candidate_id, d$quantile_level), ], row.names = FALSE)",
    "cat(sprintf('\\ncomponents_completed=%d/%d failed=%d pending_or_running=%d\\n', sum(d$status == 'completed'), nrow(d), sum(d$status == 'failed'), sum(!d$status %in% c('completed','failed'))))",
    "agg <- aggregate(check_loss_mean ~ candidate_id, d[d$status == 'completed', ], mean, na.rm = TRUE)",
    "if (nrow(agg)) {",
    "  cat('\\ncompleted-component mean check loss by candidate:\\n')",
    "  print(agg[order(agg$check_loss_mean), ], row.names = FALSE)",
    "}"
  )
  writeLines(lines, path)
  Sys.chmod(path, "0755")
  path
}

launch_path <- write_stage_scheduler()
finalizer_path <- write_stage_finalizer()
watch_path <- write_stage_watcher(finalizer_path)
health_path <- write_stage_health()

writeLines(c(
  "# GloFAS Stage E Tail Gate",
  "",
  sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "Scope: Article-Q-DESN GloFAS application only. This package is ignored by git.",
  "",
  "## Objective",
  "",
  "Run a p05/p50/p95 tail gate for selected Stage D median-gate candidates.",
  "Completed Stage D p50 fits are reused. Only p05 and p95 are launched.",
  "",
  "## Candidates",
  "",
  paste(sprintf("- `%s`", candidate_ids), collapse = "\n"),
  "",
  "## Decision Standard",
  "",
  "This gate tests whether the Stage D median improvement survives lower and",
  "upper tails. It is not a full article-facing promotion gate. Advance at most",
  "two candidates to full-seven confirmation.",
  "",
  "## Checklist",
  "",
  "- [x] Stage E candidate set selected from Stage D evidence.",
  "- [x] p50 reuse contract validated.",
  "- [x] p05/p95 configs generated.",
  "- [x] Model-grid, seed, and engine contracts validated.",
  "- [x] Bounded tmux scheduler generated.",
  "- [x] Watch/finalize helper generated.",
  "- [x] Health-check helper generated.",
  "- [ ] p05/p95 tail fits completed.",
  "- [ ] Tail syntheses and diagnostics completed.",
  "- [ ] Select at most two candidates for full-seven confirmation.",
  "- [ ] Do not promote until full-seven score-balanced synthesis passes.",
  "",
  "## Files",
  "",
  sprintf("- Candidate manifest: `%s`", repo_rel(file.path(out_dir, "stage_e_candidate_manifest.csv"))),
  sprintf("- Component manifest: `%s`", repo_rel(file.path(out_dir, "stage_e_component_manifest.csv"))),
  sprintf("- Scheduler manifest: `%s`", repo_rel(file.path(out_dir, "stage_e_scheduler_manifest.csv"))),
  sprintf("- Prelaunch validation: `%s`", repo_rel(file.path(out_dir, "stage_e_prelaunch_validation.csv"))),
  sprintf("- Scheduler: `%s`", repo_rel(launch_path)),
  sprintf("- Watch/finalize: `%s`", repo_rel(watch_path)),
  sprintf("- Health check: `%s`", repo_rel(health_path)),
  "",
  "## Run Commands",
  "",
  sprintf("```bash\nbash %s\n```", repo_rel(launch_path)),
  "",
  sprintf("```bash\ntmux new-session -d -s %s_watch 'bash %s'\n```", args$batch_id, repo_rel(watch_path)),
  "",
  sprintf("```bash\nRscript %s\n```", repo_rel(health_path))
), file.path(out_dir, "PLAN.md"))

cat(sprintf("prepared=%s\n", repo_rel(out_dir)))
cat(sprintf("candidates=%s\n", paste(candidate_ids, collapse = ",")))
cat(sprintf("new_fits=%d reused_fits=%d\n", nrow(all_launch), sum(grepl("^reused_stage_d_median_gate_", all_components$source_kind))))
cat(sprintf("launch=%s\n", repo_rel(launch_path)))
cat(sprintf("watch=%s\n", repo_rel(watch_path)))
cat(sprintf("health=%s\n", repo_rel(health_path)))
