#!/usr/bin/env Rscript
# Purpose: prepare a broad but pattern-aware Stage G p50 GloFAS median screen.
# The screen is centered on the promoted Stage F alpha=0.025 candidate and
# expands only along directions supported by prior GloFAS evidence.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_stage_f_alpha025_full7_confirmation_20260623/d_alpha_025/config_p15.yaml",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_stage_g_median_screen_20260624",
  batch_id = "glofas_stage_g_median_screen_20260624",
  first_core = "16",
  n_cores = "32",
  max_active = "32",
  dry_run = FALSE
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
repeat_value <- function(x, n) as.list(rep(x, n))

out_dir <- app_path(args$out_dir)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "logs"))

first_core <- as.integer(args$first_core)
n_cores <- as.integer(args$n_cores)
max_active <- as.integer(args$max_active)
n_detected <- parallel::detectCores(logical = TRUE)
if (any(!is.finite(c(first_core, n_cores, max_active))) || first_core < 0L || n_cores < 1L || max_active < 1L) {
  stop("Invalid scheduler core arguments.", call. = FALSE)
}
if ((first_core + n_cores - 1L) >= n_detected) {
  stop(sprintf("Requested cores %d:%d exceed detected core count %d.", first_core, first_core + n_cores - 1L, n_detected), call. = FALSE)
}

base_cfg <- app_read_config(app_path(args$base_config))
base_cfg$.__config_path__ <- NULL
base_grid <- app_validate_model_grid(app_config_path(base_cfg, "model_grid"), app_config_path(base_cfg, "schema"))
raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
if (!nrow(raw_base) || !nrow(qdesn_base)) {
  stop("Base model grid must contain raw_glofas and qdesn_glofas_discrepancy rows.", call. = FALSE)
}

targets <- app_validate_quantile_grid(app_path(args$quantile_targets))
targets <- targets[abs(as.numeric(targets$quantile_level) - 0.50) < 1e-12, , drop = FALSE]
if (nrow(targets) != 1L) stop("The quantile target file must contain exactly one p50 row for Stage G.", call. = FALSE)

candidate <- function(candidate_id, block, D = 4L, width = 100L, m = 300L,
                      alpha = 0.025, rho = 0.95, pi_w = 0.03,
                      win_scale_global = 0.18, win_scale_bias = win_scale_global,
                      shared_tau0 = 1e-3, discrepancy_tau0 = 0.03,
                      shared_slab_s2 = 1.0, discrepancy_slab_s2 = 1.0,
                      seed = 20260512L, purpose = "") {
  data.frame(
    candidate_id = candidate_id,
    block = block,
    D = as.integer(D),
    width = as.integer(width),
    reservoir_m = as.integer(m),
    alpha = as.numeric(alpha),
    rho = as.numeric(rho),
    pi_w = as.numeric(pi_w),
    pi_in = 1.0,
    win_scale_global = as.numeric(win_scale_global),
    win_scale_bias = as.numeric(win_scale_bias),
    shared_tau0 = as.numeric(shared_tau0),
    discrepancy_tau0 = as.numeric(discrepancy_tau0),
    shared_slab_s2 = as.numeric(shared_slab_s2),
    discrepancy_slab_s2 = as.numeric(discrepancy_slab_s2),
    seed = as.integer(seed),
    purpose = purpose,
    stringsAsFactors = FALSE
  )
}

candidates <- list()
add_candidate <- function(...) candidates[[length(candidates) + 1L]] <<- candidate(...)

# A. The strongest observed signal is the leak-rate improvement from 0.035 to 0.025.
for (a in c(0.010, 0.015, 0.020, 0.0225, 0.025, 0.0275, 0.030, 0.035)) {
  add_candidate(
    sprintf("g_alpha_%04d", as.integer(round(a * 10000))),
    "alpha_ladder",
    alpha = a,
    purpose = "Local leak-rate ladder around the promoted Stage F alpha025 candidate."
  )
}

# B. Memory is retested only locally around m=300 and only with promising alphas.
for (a in c(0.015, 0.020, 0.025, 0.030)) {
  for (m in c(240, 270, 330)) {
    add_candidate(
      sprintf("g_mem_m%03d_a%04d", m, as.integer(round(a * 10000))),
      "alpha_memory",
      m = m,
      alpha = a,
      purpose = "Leak-memory interaction near the promoted architecture."
    )
  }
}

# C. Spectral radius may substitute for memory without increasing lag dimension.
for (a in c(0.015, 0.020, 0.025, 0.030)) {
  for (r in c(0.90, 0.98)) {
    add_candidate(
      sprintf("g_rho_%03d_a%04d", as.integer(round(r * 100)), as.integer(round(a * 10000))),
      "alpha_rho",
      alpha = a,
      rho = r,
      purpose = "Leak-spectral-radius interaction."
    )
  }
}

# D. Input scale controls reservoir excitation and has not been deeply explored
# under the winning alpha regime.
for (w in c(0.10, 0.14, 0.22, 0.26)) {
  add_candidate(
    sprintf("g_win_%03d", as.integer(round(w * 100))),
    "input_scale",
    alpha = 0.025,
    win_scale_global = w,
    win_scale_bias = w,
    purpose = "Input-scale perturbation under the promoted alpha regime."
  )
}

# E. Sparse topology perturbations around the default pi_w=0.03.
for (pw in c(0.015, 0.050, 0.080, 0.120)) {
  add_candidate(
    sprintf("g_piw_%04d", as.integer(round(pw * 10000))),
    "sparsity",
    alpha = 0.025,
    pi_w = pw,
    purpose = "Reservoir sparsity perturbation under the promoted alpha regime."
  )
}

# F. Architecture sentinels are re-tested under alpha=0.025 rather than under the
# weaker alpha=0.035/0.050 regimes.
arch <- data.frame(
  candidate_id = c("g_d3_w100", "g_d3_w140", "g_d3_w180", "g_d4_w080", "g_d4_w120", "g_d5_w080", "g_d5_w100", "g_d6_w070"),
  D = c(3, 3, 3, 4, 4, 5, 5, 6),
  width = c(100, 140, 180, 80, 120, 80, 100, 70),
  stringsAsFactors = FALSE
)
for (i in seq_len(nrow(arch))) {
  add_candidate(
    arch$candidate_id[[i]],
    "depth_width",
    D = arch$D[[i]],
    width = arch$width[[i]],
    alpha = 0.025,
    purpose = "Depth-width sentinel under the promoted alpha regime."
  )
}

# G. Prior effects were weaker historically, so this is deliberately compact.
for (dt in c(0.010, 0.015, 0.060, 0.100)) {
  add_candidate(
    sprintf("g_disc_tau_%s", gsub("[.]", "p", format(dt, scientific = FALSE))),
    "prior_interaction",
    alpha = 0.025,
    discrepancy_tau0 = dt,
    purpose = "Discrepancy RHS shrinkage perturbation under alpha025."
  )
}
for (st in c(0.0003, 0.003)) {
  for (dt in c(0.015, 0.060)) {
    add_candidate(
      sprintf("g_shared_%s_disc_%s",
              gsub("[.]", "p", format(st, scientific = FALSE)),
              gsub("[.]", "p", format(dt, scientific = FALSE))),
      "prior_interaction",
      alpha = 0.025,
      shared_tau0 = st,
      discrepancy_tau0 = dt,
      purpose = "Joint shared/discrepancy RHS shrinkage perturbation under alpha025."
    )
  }
}

# H. Seed robustness is tested only for the current winner geometry.
for (s in 20260526:20260531) {
  add_candidate(
    sprintf("g_seed_%d", s),
    "seed_robustness",
    alpha = 0.025,
    seed = s,
    purpose = "Seed robustness for the promoted Stage F geometry."
  )
}

candidates <- do.call(rbind, candidates)
candidates$stage <- "G_median_pattern_aware_screen"
candidates$quantile_level <- 0.50
if (anyDuplicated(candidates$candidate_id)) {
  dupes <- unique(candidates$candidate_id[duplicated(candidates$candidate_id)])
  stop(sprintf("Duplicate candidate ids: %s", paste(dupes, collapse = ", ")), call. = FALSE)
}

apply_candidate <- function(cfg, cand) {
  D <- as.integer(cand$D[[1L]])
  width <- as.integer(cand$width[[1L]])
  m <- as.integer(cand$reservoir_m[[1L]])
  alpha <- as.numeric(cand$alpha[[1L]])
  rho <- as.numeric(cand$rho[[1L]])
  pi_w <- as.numeric(cand$pi_w[[1L]])
  win <- as.numeric(cand$win_scale_global[[1L]])
  win_bias <- as.numeric(cand$win_scale_bias[[1L]])

  cfg$reservoir$D <- D
  cfg$reservoir$n <- repeat_value(width, D)
  cfg$reservoir$n_tilde <- if (D > 1L) repeat_value(width, D - 1L) else list()
  cfg$reservoir$m <- m
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- repeat_value(alpha, D)
  cfg$reservoir$rho <- repeat_value(rho, D)
  cfg$reservoir$pi_w <- repeat_value(pi_w, D)
  cfg$reservoir$pi_in <- repeat_value(1.0, D)
  cfg$reservoir$win_scale_global <- win
  cfg$reservoir$win_scale_bias <- win_bias
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$act_f <- "tanh"
  cfg$reservoir$act_k <- "identity"
  cfg$reservoir$standardize_inputs <- TRUE
  cfg$reservoir$add_bias <- TRUE
  cfg$reservoir$seed <- as.integer(cand$seed[[1L]])

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
  cfg$feature_contract$readout$include_horizon_scaled <- FALSE
  cfg$feature_contract$readout$standardize_output_lags <- TRUE
  cfg$feature_contract$readout$standardize_non_intercept <- FALSE
  cfg$feature_contract$forecast_alignment$output_lags_anchor <- "target_date"
  cfg$feature_contract$forecast_alignment$covariate_lags_anchor <- "target_date"

  cfg$prediction$posterior_predictive_sampling <- "disabled"
  cfg$inference$default_method <- "vb_ld"
  cfg$inference$likelihood_family <- "al"
  cfg$inference$coefficient_prior_default <- "rhs"
  cfg$inference$vb_ld$max_iter <- 150L
  cfg$inference$vb_ld$max_iter_hard_cap <- 150L
  cfg$inference$vb_ld$tol <- 1e-3
  cfg$inference$vb_ld$tol_par <- 1e-3
  cfg$inference$vb_ld$n_samp_xi <- 500L
  cfg$inference$vb_ld$n_draws <- 2000L
  cfg$inference$vb_ld$rhs_tau0 <- as.numeric(cand$shared_tau0[[1L]])
  cfg$inference$vb_ld$rhs_slab_s2 <- as.numeric(cand$shared_slab_s2[[1L]])
  cfg$inference$vb_ld$rhs_a_zeta <- 2.0
  cfg$inference$vb_ld$rhs_b_zeta <- 4.0
  cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(cand$discrepancy_tau0[[1L]])
  cfg$inference$vb_ld$rhs_alpha_slab_s2 <- as.numeric(cand$discrepancy_slab_s2[[1L]])
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
  cfg$execution$final_launch$note <- "User-approved Stage G median-only pattern-aware screen."
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg
}

component_rows <- vector("list", nrow(candidates))
pre_rows <- vector("list", nrow(candidates))
for (i in seq_len(nrow(candidates))) {
  cand <- candidates[i, , drop = FALSE]
  candidate_id <- cand$candidate_id[[1L]]
  cand_dir <- file.path(out_dir, candidate_id)
  app_ensure_dir(cand_dir)
  app_ensure_dir(file.path(cand_dir, "logs"))
  run_id <- sprintf("%s_%s_p50", args$batch_id, candidate_id)
  qgrid_path <- file.path(cand_dir, "quantile_grid_p50.csv")
  model_grid_path <- file.path(cand_dir, "model_grid_p50.csv")
  config_path <- file.path(cand_dir, "config_p50.yaml")
  app_write_csv(targets, qgrid_path)

  raw_model_id <- sprintf("raw_glofas_%s_%s", args$batch_id, candidate_id)
  qdesn_model_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s_%s", args$batch_id, candidate_id)
  raw_row <- raw_base
  qdesn_row <- qdesn_base
  raw_row$fit_id <- paste0(raw_model_id, "_p50")
  raw_row$model_id <- raw_model_id
  raw_row$quantile_level <- 0.50
  raw_row$config_hash <- "TO_BE_COMPUTED"
  raw_row$notes <- sprintf("Raw GloFAS baseline for Stage G candidate %s.", candidate_id)
  qdesn_row$fit_id <- paste0(qdesn_model_id, "_p50")
  qdesn_row$model_id <- qdesn_model_id
  qdesn_row$quantile_level <- 0.50
  qdesn_row$reservoir_seed <- as.integer(cand$seed[[1L]])
  qdesn_row$config_hash <- "TO_BE_COMPUTED"
  qdesn_row$notes <- sprintf("Q-DESN Stage G median screen candidate %s.", candidate_id)
  model_grid <- rbind(raw_row, qdesn_row)
  app_write_csv(model_grid, model_grid_path)

  cfg <- apply_candidate(base_cfg, cand)
  cfg$application_name <- run_id
  cfg$description <- sprintf("GloFAS Stage G p50 pattern-aware median-screen candidate %s.", candidate_id)
  cfg$paths$quantile_grid <- repo_rel(qgrid_path)
  cfg$paths$model_grid <- repo_rel(model_grid_path)
  cfg$paths$cache <- file.path("application/cache", run_id)
  cfg$scoring$intervals <- list(list(lower = 0.05, upper = 0.95, nominal = 0.90))
  app_write_yaml(cfg, config_path)

  validated_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
  app_validate_qdesn_model_grid_prior_contract(validated_grid)
  app_validate_qdesn_seed_contract(cfg, validated_grid)
  engine_report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, validated_grid),
    stop_on_failure = TRUE
  )

  core <- first_core + ((i - 1L) %% n_cores)
  log_path <- file.path("application/logs", sprintf("%s.log", run_id))
  session <- run_id
  run_dir <- file.path("application/runs", run_id)
  pre_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    block = cand$block[[1L]],
    quantile_id = "p50",
    config_path = repo_rel(config_path),
    model_grid_valid = TRUE,
    seed_contract_valid = TRUE,
    engine_api_ok = isTRUE(engine_report$ok),
    run_dir_exists = file.exists(app_path(run_dir)),
    launchable_without_overwrite = !file.exists(app_path(run_dir)),
    stringsAsFactors = FALSE
  )
  component_rows[[i]] <- data.frame(
    batch_id = args$batch_id,
    candidate_id = candidate_id,
    block = cand$block[[1L]],
    stage = cand$stage[[1L]],
    run_index = i,
    quantile_id = "p50",
    quantile_level = 0.50,
    role = "median_gate",
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
    source_kind = "new_stage_g_median_screen",
    required = TRUE,
    enabled = TRUE,
    launch_status = "prepared_not_launched",
    stringsAsFactors = FALSE
  )
}

component_manifest <- do.call(rbind, component_rows)
prelaunch <- do.call(rbind, pre_rows)
app_write_csv(candidates, file.path(out_dir, "candidate_manifest.csv"))
app_write_csv(component_manifest, file.path(out_dir, "median_screen_manifest.csv"))
app_write_csv(component_manifest, file.path(out_dir, "stage_g_scheduler_manifest.csv"))
app_write_csv(prelaunch, file.path(out_dir, "prelaunch_validation.csv"))

if (!all(app_as_bool_vec(prelaunch$engine_api_ok))) {
  app_write_csv(prelaunch[!app_as_bool_vec(prelaunch$engine_api_ok), , drop = FALSE],
                file.path(out_dir, "prelaunch_failures.csv"))
  stop("Stage G prelaunch validation failed. See prelaunch_failures.csv.", call. = FALSE)
}

plan_path <- file.path(out_dir, "PLAN.md")
writeLines(c(
  "# GloFAS Stage G median screen",
  "",
  "This ignored runtime package prepares a broad but pattern-aware p50 screen",
  "centered on the promoted Stage F alpha025 score-balanced candidate.",
  "",
  "## Evidence basis",
  "",
  "- Stage F alpha=0.025 is the current promoted GloFAS application output.",
  "- Stage D showed alpha=0.025 was the strongest median improvement.",
  "- Stage E showed the alpha025 improvement survived p05/p95 tail checks.",
  "- Prior-only perturbations were historically weak; they are compact here.",
  "- Width/depth perturbations are re-tested only under the better alpha regime.",
  "",
  "## Screen structure",
  "",
  paste0("- Candidates: ", nrow(candidates)),
  paste0("- Scheduler cores: ", first_core, ":", first_core + n_cores - 1L),
  paste0("- Max active jobs: ", max_active),
  "",
  "Blocks:",
  paste0("- ", names(table(candidates$block)), ": ", as.integer(table(candidates$block)), " candidates"),
  "",
  "## Gates",
  "",
  "1. Run p50 only for all candidates.",
  "2. Rank by Q-DESN p50 check loss, with VB convergence and figure sanity as secondary checks.",
  "3. Advance only the top 5-8 candidates to a p05/p50/p95 tail gate.",
  "4. Advance only one or two tail-gate winners to full-seven synthesis.",
  "5. Promote only if full-seven score-balanced output beats the current Stage F promoted candidate.",
  "",
  "## Launch",
  "",
  "Run only after explicit confirmation:",
  "",
  "```bash",
  paste0("bash ", repo_rel(file.path(out_dir, "launch_stage_g_median_screen_scheduler.sh"))),
  "```"
), plan_path)

write_scheduler <- function() {
  path <- file.path(out_dir, "launch_stage_g_median_screen_scheduler.sh")
  state_path <- file.path(out_dir, "scheduler_state.csv")
  lines <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("MANIFEST=%s", shQuote(repo_rel(file.path(out_dir, "stage_g_scheduler_manifest.csv")))),
    sprintf("STATE=%s", shQuote(repo_rel(state_path))),
    sprintf("MAX_ACTIVE=%d", max_active),
    "mkdir -p application/logs",
    "echo 'run_id,status,started_at,core,session,log_path,pid,exit_code' > \"$STATE\"",
    "pids=()",
    "run_ids=()",
    "cores=()",
    "sessions=()",
    "logs=()",
    "",
    "strip_csv_quotes() {",
    "  local x=\"$1\"",
    "  x=\"${x#\\\"}\"",
    "  x=\"${x%\\\"}\"",
    "  printf '%s' \"$x\"",
    "}",
    "",
    "compact_jobs() {",
    "  local new_pids=() new_run_ids=() new_cores=() new_sessions=() new_logs=()",
    "  local i pid run_id core session log_path exit_code",
    "  for i in \"${!pids[@]}\"; do",
    "    pid=\"${pids[$i]}\"",
    "    run_id=\"${run_ids[$i]}\"",
    "    core=\"${cores[$i]}\"",
    "    session=\"${sessions[$i]}\"",
    "    log_path=\"${logs[$i]}\"",
    "    if kill -0 \"$pid\" 2>/dev/null; then",
    "      new_pids+=(\"$pid\")",
    "      new_run_ids+=(\"$run_id\")",
    "      new_cores+=(\"$core\")",
    "      new_sessions+=(\"$session\")",
    "      new_logs+=(\"$log_path\")",
    "    else",
    "      set +e",
    "      wait \"$pid\"",
    "      exit_code=$?",
    "      set -e",
    "      echo \"$run_id,finished,$(date -Is),$core,$session,$log_path,$pid,$exit_code\" >> \"$STATE\"",
    "    fi",
    "  done",
    "  pids=(\"${new_pids[@]}\")",
    "  run_ids=(\"${new_run_ids[@]}\")",
    "  cores=(\"${new_cores[@]}\")",
    "  sessions=(\"${new_sessions[@]}\")",
    "  logs=(\"${new_logs[@]}\")",
    "}",
    "",
    "wait_for_slot() {",
    "  while true; do",
    "    compact_jobs",
    "    if [[ \"${#pids[@]}\" -lt \"$MAX_ACTIVE\" ]]; then break; fi",
    "    sleep 30",
    "  done",
    "}",
    "",
    "while IFS=, read -r batch_id candidate_id block stage run_index quantile_id quantile_level role run_id config_path quantile_grid_path model_grid_path core raw_fit_id qdesn_fit_id raw_model_id qdesn_model_id log_path session run_dir source_kind required enabled launch_status; do",
    "  run_id=$(strip_csv_quotes \"$run_id\")",
    "  config_path=$(strip_csv_quotes \"$config_path\")",
    "  core=$(strip_csv_quotes \"$core\")",
    "  log_path=$(strip_csv_quotes \"$log_path\")",
    "  session=$(strip_csv_quotes \"$session\")",
    "  run_dir=$(strip_csv_quotes \"$run_dir\")",
    "  enabled=$(strip_csv_quotes \"$enabled\")",
    "  if [[ \"$enabled\" != \"TRUE\" && \"$enabled\" != \"true\" ]]; then continue; fi",
    "  wait_for_slot",
    "  if [[ -d \"$run_dir\" ]]; then",
    "    echo \"$run_id,skipped_existing,$(date -Is),$core,$session,$log_path,,\" >> \"$STATE\"",
    "    continue",
    "  fi",
    "  taskset -c \"$core\" Rscript application/scripts/run_all.R --config \"$config_path\" --run_id \"$run_id\" --preflight true --confirm_final_launch true > \"$log_path\" 2>&1 &",
    "  pid=$!",
    "  pids+=(\"$pid\")",
    "  run_ids+=(\"$run_id\")",
    "  cores+=(\"$core\")",
    "  sessions+=(\"$session\")",
    "  logs+=(\"$log_path\")",
    "  echo \"$run_id,launched,$(date -Is),$core,$session,$log_path,$pid,\" >> \"$STATE\"",
    "done < <(tail -n +2 \"$MANIFEST\")",
    "while [[ \"${#pids[@]}\" -gt 0 ]]; do",
    "  compact_jobs",
    "  if [[ \"${#pids[@]}\" -gt 0 ]]; then sleep 30; fi",
    "done",
    "echo \"scheduler_complete,done,$(date -Is),,,,,\" >> \"$STATE\""
  )
  writeLines(lines, path)
  Sys.chmod(path, mode = "0755")
  path
}

write_health_check <- function() {
  path <- file.path(out_dir, "health_check_stage_g_median_screen.R")
  lines <- c(
    "#!/usr/bin/env Rscript",
    sprintf("repo_root <- %s", encodeString(repo_root, quote = "\"")),
    "source(file.path(repo_root, 'application/R/00_packages.R'))",
    "app_set_repo_root(repo_root)",
    sprintf("manifest <- app_read_csv(%s)", encodeString(repo_rel(file.path(out_dir, "stage_g_scheduler_manifest.csv")), quote = "\"")),
    "score_one <- function(row) {",
    "  run_dir <- app_path(row$run_dir[[1L]])",
    "  p <- file.path(run_dir, 'tables', 'score_summary.csv')",
    "  fit <- file.path(run_dir, 'tables', 'fit_status.csv')",
    "  status <- if (!dir.exists(run_dir)) 'pending' else if (!file.exists(fit)) 'running' else 'completed'",
    "  check <- NA_real_",
    "  if (file.exists(p)) {",
    "    s <- app_read_csv(p)",
    "    q <- s[grepl('qdesn', tolower(s$model_id)), , drop = FALSE]",
    "    if (nrow(q)) check <- as.numeric(q$check_loss_mean[[1L]])",
    "  }",
    "  data.frame(candidate_id=row$candidate_id[[1L]], block=row$block[[1L]], status=status, check_loss_mean=check, run_id=row$run_id[[1L]], stringsAsFactors=FALSE)",
    "}",
    "out <- do.call(rbind, lapply(seq_len(nrow(manifest)), function(i) score_one(manifest[i, , drop=FALSE])))",
    "out <- out[order(is.na(out$check_loss_mean), out$check_loss_mean), , drop=FALSE]",
    sprintf("app_write_csv(out, %s)", encodeString(repo_rel(file.path(out_dir, "health_check_latest.csv")), quote = "\"")),
    "print(out, row.names = FALSE)",
    "cat(sprintf('\\ncompleted=%d/%d failed_or_missing_score=%d pending_or_running=%d\\n', sum(out$status == 'completed'), nrow(out), sum(out$status == 'completed' & is.na(out$check_loss_mean)), sum(out$status != 'completed')))"
  )
  writeLines(lines, path)
  Sys.chmod(path, mode = "0755")
  path
}

scheduler_path <- write_scheduler()
health_path <- write_health_check()

cat(sprintf("Prepared %d Stage G median-screen candidates.\\n", nrow(candidates)))
cat(sprintf("Runtime directory: %s\\n", repo_rel(out_dir)))
cat(sprintf("Scheduler: %s\\n", repo_rel(scheduler_path)))
cat(sprintf("Health check: %s\\n", repo_rel(health_path)))
cat(sprintf("Plan: %s\\n", repo_rel(plan_path)))
