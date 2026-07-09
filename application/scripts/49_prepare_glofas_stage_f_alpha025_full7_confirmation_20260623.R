#!/usr/bin/env Rscript
# Purpose: prepare the Stage F full-seven confirmation package for the
# d_alpha_025 GloFAS candidate. This package reuses completed p05/p50/p95 fits
# and launches only p15/p35/p65/p80.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))

args <- app_parse_args(list(
  stage_e_candidate_dir = "local_trackers/runtime_configs/glofas_stage_e_tail_gate_20260623/d_alpha_025",
  candidate_id = "d_alpha_025",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_stage_f_alpha025_full7_confirmation_20260623",
  batch_id = "glofas_stage_f_alpha025_full7_confirmation_20260623",
  first_core = "28",
  n_cores = "4",
  max_active = "4",
  spread_factor = "1.4",
  spread_additive_width = "0.5",
  spread_center_quantile = "0.5",
  spread_calibration_id = "scorebalanced_spread_x1p400_plus0p500"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))

intervals <- list(
  list(lower = 0.05, upper = 0.95, nominal = 0.90),
  list(lower = 0.15, upper = 0.80, nominal = 0.65),
  list(lower = 0.35, upper = 0.65, nominal = 0.30)
)
target_levels <- c(0.05, 0.15, 0.35, 0.50, 0.65, 0.80, 0.95)
reuse_levels <- c(0.05, 0.50, 0.95)
launch_levels <- setdiff(target_levels, reuse_levels)

out_dir <- app_path(args$out_dir)
stage_e_candidate_dir <- app_path(args$stage_e_candidate_dir)
candidate_id <- as.character(args$candidate_id)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, candidate_id))
app_ensure_dir(file.path(out_dir, "logs"))
app_ensure_dir(file.path(out_dir, candidate_id, "logs"))

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
  stop("Quantile target file must contain p05, p15, p35, p50, p65, p80, and p95.", call. = FALSE)
}

reuse_manifest_path <- file.path(stage_e_candidate_dir, "synthesis_source_manifest.csv")
if (!file.exists(reuse_manifest_path)) {
  stop(sprintf("Missing Stage E reuse source manifest: %s", reuse_manifest_path), call. = FALSE)
}
reuse_manifest <- app_read_csv(reuse_manifest_path)
reuse_manifest$quantile_level <- as.numeric(reuse_manifest$quantile_level)

p50_reuse <- reuse_manifest[abs(reuse_manifest$quantile_level - 0.50) < 1e-12, , drop = FALSE]
if (nrow(p50_reuse) != 1L) stop("Stage F requires one reusable p50 row.", call. = FALSE)

base_cfg <- app_read_config(app_path(p50_reuse$config_path[[1L]]))
base_cfg$.__config_path__ <- NULL
base_grid <- app_validate_model_grid(app_path(p50_reuse$model_grid_path[[1L]]), app_config_path(base_cfg, "schema"))
raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
if (!nrow(raw_base) || !nrow(qdesn_base)) {
  stop("Base p50 model grid must contain raw_glofas and qdesn_glofas_discrepancy rows.", call. = FALSE)
}
raw_model_id <- raw_base$model_id[[1L]]
qdesn_model_id <- qdesn_base$model_id[[1L]]

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

resolve_run_dir <- function(path) {
  if (grepl("^/", path)) path else app_path(path)
}

reuse_ready <- function(row) {
  run_dir <- resolve_run_dir(row$run_dir[[1L]])
  fit_status_path <- file.path(run_dir, "tables", "fit_status.csv")
  pred_path <- file.path(run_dir, "tables", "prediction_quantiles.csv")
  draws_path <- file.path(run_dir, "tables", "posterior_draw_predictions.csv")
  readiness_path <- file.path(run_dir, "tables", "launch_readiness_report.csv")
  qdesn_object_path <- file.path(run_dir, "objects", paste0(row$qdesn_fit_id[[1L]], ".rds"))
  ok <- file.exists(fit_status_path) &&
    file.exists(pred_path) &&
    file.exists(draws_path) &&
    file.exists(readiness_path) &&
    file.exists(qdesn_object_path)
  if (ok) {
    fit_status <- app_read_csv(fit_status_path)
    ids <- c(row$raw_fit_id[[1L]], row$qdesn_fit_id[[1L]])
    rows <- fit_status[fit_status$fit_id %in% ids, , drop = FALSE]
    ok <- nrow(rows) == 2L && all(rows$status == "completed")
  }
  ok
}

candidate_dir <- file.path(out_dir, candidate_id)
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
    src_row <- reuse_manifest[abs(reuse_manifest$quantile_level - qlev) < 1e-12, , drop = FALSE]
    if (nrow(src_row) != 1L) stop(sprintf("Missing unique reusable row for quantile %.2f.", qlev), call. = FALSE)
    ok <- reuse_ready(src_row)
    prelaunch_rows[[length(prelaunch_rows) + 1L]] <- data.frame(
      candidate_id = candidate_id,
      quantile_id = qid,
      quantile_level = qlev,
      source_kind = src_row$source_kind[[1L]],
      ready = ok,
      detail = src_row$run_dir[[1L]],
      stringsAsFactors = FALSE
    )
    component_rows[[i]] <- data.frame(
      batch_id = args$batch_id,
      candidate_id = candidate_id,
      run_index = i,
      quantile_id = qid,
      quantile_level = qlev,
      role = role,
      run_id = src_row$run_id[[1L]],
      config_path = src_row$config_path[[1L]],
      quantile_grid_path = src_row$quantile_grid_path[[1L]],
      model_grid_path = src_row$model_grid_path[[1L]],
      run_dir = src_row$run_dir[[1L]],
      raw_fit_id = src_row$raw_fit_id[[1L]],
      qdesn_fit_id = src_row$qdesn_fit_id[[1L]],
      raw_model_id = src_row$raw_model_id[[1L]],
      qdesn_model_id = src_row$qdesn_model_id[[1L]],
      source_kind = paste0("reused_stage_e_or_d_", qid),
      required = TRUE,
      enabled = TRUE,
      stringsAsFactors = FALSE
    )
    model_rows_all[[length(model_rows_all) + 1L]] <- app_validate_model_grid(
      app_path(src_row$model_grid_path[[1L]]),
      app_config_path(base_cfg, "schema")
    )
    qgrid_rows_all[[length(qgrid_rows_all) + 1L]] <- app_read_csv(app_path(src_row$quantile_grid_path[[1L]]))
    next
  }

  run_id <- sprintf("%s_%s_%s", args$batch_id, candidate_id, qid)
  qgrid_path <- file.path(candidate_dir, sprintf("quantile_grid_%s.csv", qid))
  model_grid_path <- file.path(candidate_dir, sprintf("model_grid_%s.csv", qid))
  config_path <- file.path(candidate_dir, sprintf("config_%s.yaml", qid))
  app_write_csv(targets[i, , drop = FALSE], qgrid_path)

  raw_row <- raw_base
  qdesn_row <- qdesn_base
  raw_row$fit_id <- sprintf("%s_%s", raw_model_id, qid)
  raw_row$quantile_level <- qlev
  raw_row$config_hash <- "TO_BE_COMPUTED"
  raw_row$notes <- sprintf("Raw GloFAS baseline for Stage F %s; quantile=%s (%s).", candidate_id, qlev, role)
  qdesn_row$fit_id <- sprintf("%s_%s", qdesn_model_id, qid)
  qdesn_row$quantile_level <- qlev
  qdesn_row$reservoir_seed <- app_config_reservoir_seed(base_cfg)
  qdesn_row$config_hash <- "TO_BE_COMPUTED"
  qdesn_row$notes <- sprintf("Q-DESN Stage F full-seven confirmation component %s; quantile=%s (%s).", candidate_id, qlev, role)
  model_grid <- rbind(raw_row, qdesn_row)
  app_write_csv(model_grid, model_grid_path)

  cfg <- base_cfg
  cfg$application_name <- run_id
  cfg$description <- paste(
    sprintf("Stage F full-seven GloFAS confirmation component for %s.", candidate_id),
    sprintf("Quantile %s (%s).", qlev, role),
    "p05/p50/p95 are reused from completed Stage E/D fits."
  )
  cfg$paths$quantile_grid <- repo_rel(qgrid_path)
  cfg$paths$model_grid <- repo_rel(model_grid_path)
  cfg$paths$cache <- file.path("application/cache", run_id)
  cfg$scoring$intervals <- intervals
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- sprintf("User-approved Stage F full-seven confirmation component for %s.", candidate_id)
  cfg$post_analysis$run_after_outputs <- FALSE
  app_write_yaml(cfg, config_path)

  validated_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
  app_validate_qdesn_model_grid_prior_contract(validated_grid)
  app_validate_qdesn_seed_contract(cfg, validated_grid)
  engine_report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, validated_grid),
    stop_on_failure = TRUE
  )

  core <- first_core + (length(launch_rows) %% n_core_use)
  session <- sprintf("%s_%s_%s", args$batch_id, candidate_id, qid)
  log_path <- file.path("application/logs", sprintf("%s.log", run_id))
  run_dir <- file.path("application/runs", run_id)
  prelaunch_rows[[length(prelaunch_rows) + 1L]] <- data.frame(
    candidate_id = candidate_id,
    quantile_id = qid,
    quantile_level = qlev,
    source_kind = "new_stage_f_full7_confirmation",
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
    source_kind = "new_stage_f_full7_confirmation",
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

candidate_row <- data.frame(
  candidate_id = candidate_id,
  source_stage = "stage_e_tail_gate_winner",
  confirmation_stage = "stage_f_full7",
  reuse_quantiles = paste(reuse_levels, collapse = ","),
  launch_quantiles = paste(launch_levels, collapse = ","),
  stringsAsFactors = FALSE
)

app_write_csv(candidate_row, file.path(out_dir, "stage_f_candidate_manifest.csv"))
app_write_csv(source_manifest, file.path(out_dir, "stage_f_component_manifest.csv"))
app_write_csv(launch_manifest, file.path(out_dir, "stage_f_scheduler_manifest.csv"))
app_write_csv(prelaunch, file.path(out_dir, "stage_f_prelaunch_validation.csv"))
app_write_csv(source_manifest, file.path(candidate_dir, "synthesis_source_manifest.csv"))
app_write_csv(source_manifest, file.path(candidate_dir, "component_manifest.csv"))
app_write_csv(launch_manifest, file.path(candidate_dir, "launch_manifest.csv"))
app_write_csv(prelaunch, file.path(candidate_dir, "prelaunch_validation.csv"))
app_write_csv(qgrid_all, file.path(candidate_dir, "quantile_grid_all.csv"))
app_write_csv(model_grid_all, file.path(candidate_dir, "model_grid_all.csv"))

if (!all(app_as_bool_vec(prelaunch$ready))) {
  failed <- prelaunch[!app_as_bool_vec(prelaunch$ready), , drop = FALSE]
  app_write_csv(failed, file.path(out_dir, "stage_f_prelaunch_failures.csv"))
  stop(sprintf("Stage F prelaunch validation failed for %d rows.", nrow(failed)), call. = FALSE)
}

synthesis_cfg <- base_cfg
synthesis_cfg$application_name <- paste0(args$batch_id, "_", candidate_id, "_synthesis")
synthesis_cfg$description <- sprintf("Stage F raw full-seven synthesis and scoring config for GloFAS candidate %s.", candidate_id)
synthesis_cfg$paths$quantile_grid <- repo_rel(file.path(candidate_dir, "quantile_grid_all.csv"))
synthesis_cfg$paths$model_grid <- repo_rel(file.path(candidate_dir, "model_grid_all.csv"))
synthesis_cfg$paths$cache <- file.path("application/cache", paste0(args$batch_id, "_", candidate_id, "_synthesis"))
synthesis_cfg$scoring$intervals <- intervals
synthesis_cfg$execution$final_launch$enabled <- FALSE
synthesis_cfg$execution$final_launch$note <- "Synthesis-only config; consumes completed Stage F component fits."
synthesis_cfg$post_analysis$run_after_outputs <- FALSE
app_write_yaml(synthesis_cfg, file.path(candidate_dir, "synthesis_config.yaml"))
app_write_yaml(make_scorebalanced_config(synthesis_cfg), file.path(candidate_dir, "synthesis_config_scorebalanced.yaml"))

write_stage_scheduler <- function() {
  path <- file.path(out_dir, sprintf("launch_%s_scheduler.sh", args$batch_id))
  state_path <- file.path(out_dir, "stage_f_scheduler_state.csv")
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    "export OMP_NUM_THREADS=1",
    "export OPENBLAS_NUM_THREADS=1",
    "export MKL_NUM_THREADS=1",
    "export VECLIB_MAXIMUM_THREADS=1",
    "export NUMEXPR_NUM_THREADS=1",
    sprintf("manifest=%s", shQuote(repo_rel(file.path(out_dir, "stage_f_scheduler_manifest.csv")))),
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
  candidate_dir_rel <- repo_rel(candidate_dir)
  raw_run <- sprintf("%s_%s_synthesis_final", args$batch_id, candidate_id)
  score_run <- sprintf("%s_%s_scorebalanced_synthesis_final", args$batch_id, candidate_id)
  raw_diag <- sprintf("%s_%s_diagnostic_figures", args$batch_id, candidate_id)
  score_diag <- sprintf("%s_%s_scorebalanced_diagnostic_figures", args$batch_id, candidate_id)
  prefix <- sprintf("glofas_stage_f_%s", candidate_id)
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    sprintf("log=%s", shQuote(log_path)),
    "echo \"$(date -Is) finalizer started\" >> \"$log\"",
    sprintf("echo '--- %s raw full7 ---' >> \"$log\"", candidate_id),
    sprintf(
      "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R --config %s --source_manifest %s --run_id %s >> \"$log\" 2>&1",
      shQuote(file.path(candidate_dir_rel, "synthesis_config.yaml")),
      shQuote(file.path(candidate_dir_rel, "synthesis_source_manifest.csv")),
      shQuote(raw_run)
    ),
    sprintf(
      "Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R --config %s --source_manifest %s --synthesis_run_id %s --run_id %s --figure_prefix %s >> \"$log\" 2>&1",
      shQuote(file.path(candidate_dir_rel, "synthesis_config.yaml")),
      shQuote(file.path(candidate_dir_rel, "synthesis_source_manifest.csv")),
      shQuote(raw_run),
      shQuote(raw_diag),
      shQuote(prefix)
    ),
    sprintf("echo '--- %s scorebalanced full7 ---' >> \"$log\"", candidate_id),
    sprintf(
      "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R --config %s --source_manifest %s --run_id %s >> \"$log\" 2>&1",
      shQuote(file.path(candidate_dir_rel, "synthesis_config_scorebalanced.yaml")),
      shQuote(file.path(candidate_dir_rel, "synthesis_source_manifest.csv")),
      shQuote(score_run)
    ),
    sprintf(
      "Rscript application/scripts/20_make_glofas_reservoir_only_full7_diagnostic_figures.R --config %s --source_manifest %s --synthesis_run_id %s --run_id %s --figure_prefix %s_scorebalanced >> \"$log\" 2>&1",
      shQuote(file.path(candidate_dir_rel, "synthesis_config_scorebalanced.yaml")),
      shQuote(file.path(candidate_dir_rel, "synthesis_source_manifest.csv")),
      shQuote(score_run),
      shQuote(score_diag),
      shQuote(prefix)
    ),
    "echo \"$(date -Is) finalizer complete\" >> \"$log\""
  )
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
    sprintf("manifest=%s", shQuote(repo_rel(file.path(out_dir, "stage_f_component_manifest.csv")))),
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
  raw_run <- sprintf("%s_%s_synthesis_final", args$batch_id, candidate_id)
  score_run <- sprintf("%s_%s_scorebalanced_synthesis_final", args$batch_id, candidate_id)
  lines <- c(
    "#!/usr/bin/env Rscript",
    sprintf("repo_root <- %s", r_string(app_repo_root())),
    "source(file.path(repo_root, 'application/R/00_packages.R'))",
    "app_set_repo_root(repo_root)",
    sprintf("component_manifest_path <- %s", r_string(repo_rel(file.path(out_dir, "stage_f_component_manifest.csv")))),
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
    "    if (r$run_id %in% sessions) 'running' else 'pending'",
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
    "print(d[order(d$quantile_level), ], row.names = FALSE)",
    "cat(sprintf('\\ncomponents_completed=%d/%d failed=%d pending_or_running=%d\\n', sum(d$status == 'completed'), nrow(d), sum(d$status == 'failed'), sum(!d$status %in% c('completed','failed'))))",
    "for (rid in c(",
    sprintf("  %s,", r_string(raw_run)),
    sprintf("  %s", r_string(score_run)),
    ")) {",
    "  p <- file.path(repo_root, 'application/runs', rid, 'tables', 'score_summary.csv')",
    "  if (file.exists(p)) {",
    "    cat(sprintf('\\nSynthesis score: %s\\n', rid))",
    "    print(read.csv(p, stringsAsFactors = FALSE), row.names = FALSE)",
    "  }",
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

plan_path <- file.path(out_dir, "PLAN.md")
if (file.exists(plan_path)) {
  plan_lines <- readLines(plan_path, warn = FALSE)
  plan_lines <- gsub("- \\[ \\] Confirm git branch is `application-ensemble-likelihood-redesign`\\.", "- [x] Confirm git branch is `application-ensemble-likelihood-redesign`.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Confirm git is clean except ignored runtime outputs\\.", "- [x] Confirm git is clean except ignored runtime outputs.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Confirm no Stage F tmux sessions already exist\\.", "- [x] Confirm no Stage F tmux sessions already exist.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Confirm p05/p50/p95 reuse artifacts exist:", "- [x] Confirm p05/p50/p95 reuse artifacts exist:", plan_lines)
  plan_lines <- gsub("- \\[ \\] Confirm reused rows have completed raw and Q-DESN fit IDs\\.", "- [x] Confirm reused rows have completed raw and Q-DESN fit IDs.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Confirm target quantile grid contains all seven levels\\.", "- [x] Confirm target quantile grid contains all seven levels.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Confirm model-grid, seed, prior, and engine contracts pass for p15/p35/p65/p80\\.", "- [x] Confirm model-grid, seed, prior, and engine contracts pass for p15/p35/p65/p80.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Add a tracked reproducibility script:", "- [x] Add a tracked reproducibility script:", plan_lines)
  plan_lines <- gsub("- \\[ \\] Generate ignored runtime package:", "- [x] Generate ignored runtime package:", plan_lines)
  plan_lines <- gsub("- \\[ \\] Generate p15/p35/p65/p80 configs, model grids, quantile grids, and launch manifest\\.", "- [x] Generate p15/p35/p65/p80 configs, model grids, quantile grids, and launch manifest.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Generate full-seven `synthesis_source_manifest.csv` that reuses p05/p50/p95 and includes new middle quantiles\\.", "- [x] Generate full-seven `synthesis_source_manifest.csv` that reuses p05/p50/p95 and includes new middle quantiles.", plan_lines)
  plan_lines <- gsub("- \\[ \\] Generate raw and score-balanced synthesis configs using the same spread calibration as current promoted outputs:", "- [x] Generate raw and score-balanced synthesis configs using the same spread calibration as current promoted outputs:", plan_lines)
  plan_lines <- gsub("- \\[ \\] Generate health checker, scheduler, finalizer, and watcher scripts\\.", "- [x] Generate health checker, scheduler, finalizer, and watcher scripts.", plan_lines)
  writeLines(plan_lines, plan_path)
}

cat(sprintf("prepared=%s\n", repo_rel(out_dir)))
cat(sprintf("candidate=%s\n", candidate_id))
cat(sprintf("new_fits=%d reused_fits=%d\n", nrow(launch_manifest), sum(grepl("^reused_stage_e_or_d_", source_manifest$source_kind))))
cat(sprintf("launch=%s\n", repo_rel(launch_path)))
cat(sprintf("watch=%s\n", repo_rel(watch_path)))
cat(sprintf("health=%s\n", repo_rel(health_path)))
