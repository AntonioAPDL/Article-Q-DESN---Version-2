#!/usr/bin/env Rscript
# Purpose: prepare the D14 true-seed full-seven GloFAS launch and a broad,
# median-only exploration grid around the current best D14 region.
#
# This script writes ignored runtime configs, manifests, and launchers. It does
# not launch any fits.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))

args <- app_parse_args(list(
  d14_base_config = "local_trackers/runtime_configs/glofas_directskip_true_seed_gate_20260610/d14_faster_direct360_seed20260610_d1n300_m360_dir360_a0p98_r0p95_w0p18_bt0p1_at0p03/config_p50.yaml",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  full7_out_dir = "local_trackers/runtime_configs/glofas_d14_true_seed_full7_20260611",
  full7_batch_id = "glofas_d14_true_seed_full7_20260611",
  exploration_out_dir = "local_trackers/runtime_configs/glofas_d14_broad_median_exploration_20260611",
  exploration_batch_id = "glofas_d14_broad_median_exploration_20260611",
  full7_first_core = "36",
  exploration_first_core = "8"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
slugify <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", as.character(x))
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))
as_range <- function(lo, hi) list(range = c(as.integer(lo), as.integer(hi)))

copy_without_runtime_fields <- function(cfg) {
  cfg$.__config_path__ <- NULL
  cfg
}

set_vector_or_scalar <- function(x) {
  if (length(x) == 1L) as.numeric(x) else as.numeric(x)
}

set_reservoir_contract <- function(cfg, candidate) {
  n_vec <- as.integer(strsplit(candidate$n[[1L]], "x", fixed = TRUE)[[1L]])
  depth <- length(n_vec)
  reservoir_m <- as.integer(candidate$reservoir_m[[1L]])
  direct_lag <- as.integer(candidate$direct_lag[[1L]])

  cfg$reservoir$D <- as.integer(depth)
  cfg$reservoir$n <- if (depth == 1L) n_vec[[1L]] else as.list(n_vec)
  cfg$reservoir$n_tilde <- list()
  cfg$reservoir$m <- reservoir_m
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- set_vector_or_scalar(rep(as.numeric(candidate$alpha[[1L]]), depth))
  cfg$reservoir$rho <- set_vector_or_scalar(rep(as.numeric(candidate$rho[[1L]]), depth))
  cfg$reservoir$pi_w <- set_vector_or_scalar(rep(as.numeric(candidate$pi_w[[1L]]), depth))
  cfg$reservoir$pi_in <- set_vector_or_scalar(rep(as.numeric(candidate$pi_in[[1L]]), depth))
  cfg$reservoir$win_scale_global <- as.numeric(candidate$win_scale_global[[1L]])
  cfg$reservoir$win_scale_bias <- as.numeric(candidate$win_scale_bias[[1L]])
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$act_f <- "tanh"
  cfg$reservoir$act_k <- "identity"
  cfg$reservoir$standardize_inputs <- TRUE
  cfg$reservoir$add_bias <- TRUE
  cfg$reservoir$seed <- as.integer(candidate$seed[[1L]])

  cfg$feature_contract$reservoir_input$output_lags <- as_range(1L, reservoir_m)
  cfg$feature_contract$reservoir_input$covariates$ppt <- as_range(0L, reservoir_m)
  cfg$feature_contract$reservoir_input$covariates$soil <- as_range(0L, reservoir_m)
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$include_input_block <- TRUE
  cfg$feature_contract$readout$input_block$output_lags <- as_range(1L, direct_lag)
  cfg$feature_contract$readout$input_block$covariates$ppt <- as_range(0L, direct_lag)
  cfg$feature_contract$readout$input_block$covariates$soil <- as_range(0L, direct_lag)
  cfg$feature_contract$readout$input_block$include_internal_bias <- FALSE
  cfg$feature_contract$readout$standardize_output_lags <- TRUE
  cfg$feature_contract$readout$standardize_non_intercept <- FALSE

  cfg$inference$vb_ld$rhs_tau0 <- as.numeric(candidate$beta_tau0[[1L]])
  cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(candidate$alpha_tau0[[1L]])
  cfg$inference$vb_ld$max_iter <- 150L
  cfg$inference$vb_ld$max_iter_hard_cap <- 150L
  cfg$inference$vb_ld$n_draws <- 2000L
  cfg$inference$vb_ld$diagnostics$profile_substeps <- FALSE
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg$execution$seed_contract <- cfg$execution$seed_contract %||% list()
  cfg$execution$seed_contract$require_config_model_grid_match <- TRUE
  cfg
}

candidate_slug <- function(cand) {
  slugify(tolower(sprintf(
    "%s_%s_d%sn%s_m%s_dir%s_a%s_r%s_w%s_bt%s_at%s_s%s",
    cand$candidate_id,
    cand$search_role,
    cand$D,
    cand$n,
    cand$reservoir_m,
    cand$direct_lag,
    gsub("[.]", "p", sprintf("%.3f", as.numeric(cand$alpha))),
    gsub("[.]", "p", sprintf("%.3f", as.numeric(cand$rho))),
    gsub("[.]", "p", sprintf("%.2f", as.numeric(cand$win_scale_global))),
    gsub("[.]", "p", format(as.numeric(cand$beta_tau0), scientific = FALSE, trim = TRUE)),
    gsub("[.]", "p", format(as.numeric(cand$alpha_tau0), scientific = FALSE, trim = TRUE)),
    cand$seed
  )))
}

intervals <- list(
  list(lower = 0.05, upper = 0.95, nominal = 0.90),
  list(lower = 0.15, upper = 0.80, nominal = 0.65),
  list(lower = 0.35, upper = 0.65, nominal = 0.30)
)

n_cores <- parallel::detectCores(logical = TRUE)
validate_core_range <- function(first_core, n_jobs, label) {
  cores <- as.integer(first_core) + seq_len(n_jobs) - 1L
  if (any(!is.finite(cores)) || any(cores < 0L) || any(cores >= n_cores)) {
    stop(sprintf(
      "%s core assignment is invalid for %d detected cores: requested %s.",
      label,
      n_cores,
      paste(cores, collapse = ", ")
    ), call. = FALSE)
  }
  invisible(cores)
}

base_cfg <- copy_without_runtime_fields(app_read_config(app_path(args$d14_base_config)))
targets <- app_validate_quantile_grid(app_path(args$quantile_targets))
base_grid <- app_validate_model_grid(app_config_path(base_cfg, "model_grid"), app_config_path(base_cfg, "schema"))
raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
if (!nrow(raw_base) || !nrow(qdesn_base)) {
  stop("Base model grid must contain raw_glofas and qdesn_glofas_discrepancy rows.", call. = FALSE)
}

prepare_full7 <- function() {
  validate_core_range(args$full7_first_core, nrow(targets), "full7")
  out_dir <- app_path(args$full7_out_dir)
  app_ensure_dir(out_dir)

  fit_suffix <- "d14_true_seed_d1n300_m360_dir360_a098_r095_w018_bt1em01_at3em02_full7"
  raw_model_id <- paste0("raw_glofas_", fit_suffix)
  qdesn_model_id <- paste0("qdesn_latent_path_rhs_al_vb_", fit_suffix)

  manifest_rows <- vector("list", nrow(targets))
  all_model_rows <- vector("list", nrow(targets))
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
    "# Generated by application/scripts/25_prepare_glofas_d14_full7_and_exploration_20260611.R.",
    "# D14 true-seed full-seven launch. One tmux session per quantile.",
    ""
  )

  for (i in seq_len(nrow(targets))) {
    qid <- q_label(targets$quantile_id[[i]])
    qlev <- as.numeric(targets$quantile_level[[i]])
    role <- as.character(targets$role[[i]])
    run_id <- sprintf("%s_%s", args$full7_batch_id, qid)
    qgrid_path <- file.path(out_dir, sprintf("quantile_grid_%s.csv", qid))
    model_grid_path <- file.path(out_dir, sprintf("model_grid_%s.csv", qid))
    config_path <- file.path(out_dir, sprintf("config_%s.yaml", qid))
    core <- as.integer(args$full7_first_core) + i - 1L
    app_write_csv(targets[i, , drop = FALSE], qgrid_path)

    raw_row <- raw_base
    qdesn_row <- qdesn_base
    raw_row$fit_id <- sprintf("raw_glofas_%s_%s", fit_suffix, qid)
    raw_row$model_id <- raw_model_id
    raw_row$quantile_level <- qlev
    raw_row$config_hash <- "TO_BE_COMPUTED"
    raw_row$notes <- sprintf("Raw GloFAS quantile baseline for D14 true-seed full-seven launch; quantile=%s (%s).", qlev, role)
    qdesn_row$fit_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s_%s", fit_suffix, qid)
    qdesn_row$model_id <- qdesn_model_id
    qdesn_row$quantile_level <- qlev
    qdesn_row$reservoir_seed <- app_config_reservoir_seed(base_cfg)
    qdesn_row$config_hash <- "TO_BE_COMPUTED"
    qdesn_row$notes <- sprintf("Q-DESN D14 true-seed full-seven component; quantile=%s (%s).", qlev, role)
    model_grid <- rbind(raw_row, qdesn_row)
    app_write_csv(model_grid, model_grid_path)
    app_validate_qdesn_seed_contract(base_cfg, app_validate_model_grid(model_grid_path, app_config_path(base_cfg, "schema")))
    all_model_rows[[i]] <- model_grid

    cfg <- base_cfg
    cfg$application_name <- run_id
    cfg$description <- paste(
      "D14 true-seed full-seven GloFAS Q-DESN component.",
      sprintf("Quantile %s (%s).", qlev, role),
      "This launch follows the completed D14 p50 original and true-seed gates."
    )
    cfg$paths$quantile_grid <- repo_rel(qgrid_path)
    cfg$paths$model_grid <- repo_rel(model_grid_path)
    cfg$paths$cache <- file.path("application/cache", run_id)
    cfg$scoring$intervals <- intervals
    cfg$inference$vb_ld$max_iter <- 150L
    cfg$inference$vb_ld$max_iter_hard_cap <- 150L
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- "User-approved D14 true-seed full-seven component; synthesize only after all target quantiles complete."
    cfg$post_analysis$run_after_outputs <- FALSE
    app_write_yaml(cfg, config_path)

    session <- sprintf("%s_%s", args$full7_batch_id, qid)
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
      sprintf("# %s: %s", qid, role),
      sprintf("if tmux has-session -t %s 2>/dev/null; then echo 'Session exists: %s' >&2; exit 1; fi", shQuote(session), session),
      sprintf("tmux new-session -d -s %s %s", shQuote(session), shQuote(command)),
      ""
    )

    manifest_rows[[i]] <- data.frame(
      batch_id = args$full7_batch_id,
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
      launch_status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
  }

  launch_manifest <- do.call(rbind, manifest_rows)
  app_write_csv(launch_manifest, file.path(out_dir, "launch_manifest.csv"))
  source_manifest <- launch_manifest[, c(
    "batch_id", "run_index", "quantile_id", "quantile_level", "role", "run_id",
    "config_path", "raw_fit_id", "qdesn_fit_id", "raw_model_id", "qdesn_model_id"
  ), drop = FALSE]
  source_manifest$run_dir <- file.path("application/runs", source_manifest$run_id)
  source_manifest$required <- TRUE
  source_manifest$enabled <- TRUE
  app_write_csv(source_manifest, file.path(out_dir, "synthesis_source_manifest.csv"))
  app_write_csv(targets, file.path(out_dir, "quantile_grid_all.csv"))
  app_write_csv(do.call(rbind, all_model_rows), file.path(out_dir, "model_grid_all.csv"))

  synthesis_cfg <- base_cfg
  synthesis_cfg$application_name <- paste0(args$full7_batch_id, "_synthesis")
  synthesis_cfg$description <- "Post-hoc synthesis and scoring config for the D14 true-seed full-seven GloFAS Q-DESN launch."
  synthesis_cfg$paths$quantile_grid <- repo_rel(file.path(out_dir, "quantile_grid_all.csv"))
  synthesis_cfg$paths$model_grid <- repo_rel(file.path(out_dir, "model_grid_all.csv"))
  synthesis_cfg$paths$cache <- file.path("application/cache", paste0(args$full7_batch_id, "_synthesis"))
  synthesis_cfg$scoring$intervals <- intervals
  synthesis_cfg$execution$final_launch$enabled <- FALSE
  synthesis_cfg$execution$final_launch$note <- "Synthesis-only config; consumes completed D14 full-seven component runs."
  synthesis_cfg$post_analysis$run_after_outputs <- FALSE
  app_write_yaml(synthesis_cfg, file.path(out_dir, "synthesis_config.yaml"))

  shell_path <- file.path(out_dir, sprintf("launch_all_%s.sh", args$full7_batch_id))
  writeLines(shell_lines, shell_path)
  Sys.chmod(shell_path, "0755")

  synth_path <- file.path(out_dir, sprintf("synthesize_%s.sh", args$full7_batch_id))
  writeLines(c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    sprintf(
      "Rscript application/scripts/10_synthesize_glofas_quantile_runs.R --config %s --source_manifest %s --run_id %s_synthesis_final",
      repo_rel(file.path(out_dir, "synthesis_config.yaml")),
      repo_rel(file.path(out_dir, "synthesis_source_manifest.csv")),
      args$full7_batch_id
    )
  ), synth_path)
  Sys.chmod(synth_path, "0755")

  readme <- c(
    sprintf("# GloFAS D14 True-Seed Full-Seven Launch: %s", args$full7_batch_id),
    "",
    "Prepared locally and ignored by git.",
    "",
    "Evidence basis:",
    "- D14 was the best original-seed p50 direct-skip candidate.",
    "- D14 remained best under the corrected true-seed p50 gate.",
    "- This full-seven launch uses the same D14 true-seed specification.",
    "",
    "Launch:",
    sprintf("`bash %s`", repo_rel(shell_path)),
    "",
    "Synthesize after all component runs complete:",
    sprintf("`bash %s`", repo_rel(synth_path))
  )
  writeLines(readme, file.path(out_dir, "README.md"))
  invisible(launch_manifest)
}

prepare_exploration <- function() {
  out_dir <- app_path(args$exploration_out_dir)
  app_ensure_dir(out_dir)
  p50 <- targets[abs(as.numeric(targets$quantile_level) - 0.5) < 1e-12, , drop = FALSE]
  if (nrow(p50) != 1L) stop("Expected one p50 target.", call. = FALSE)
  qid <- q_label(p50$quantile_id[[1L]])
  qlev <- as.numeric(p50$quantile_level[[1L]])

  candidate_grid <- data.frame(
    candidate_id = sprintf("B%02d", 1:28),
    search_role = c(
      "d14_anchor_repeat",
      "alpha096_anchor",
      "alpha099_anchor",
      "rho093_anchor",
      "rho097_anchor",
      "win014_anchor",
      "win022_anchor",
      "win026_anchor",
      "memory300_direct300",
      "memory300_direct360",
      "memory420_direct360",
      "memory420_direct420",
      "memory540_direct360",
      "memory540_direct540",
      "direct240_memory360",
      "direct480_memory360",
      "direct540_memory360",
      "looser_beta_tau",
      "tighter_beta_tau",
      "looser_alpha_tau",
      "tighter_alpha_tau",
      "loose_both_tau",
      "capacity200_anchor",
      "capacity400_anchor",
      "capacity500_direct360",
      "seed20260611_anchor",
      "seed20260611_alpha099",
      "seed20260611_win022"
    ),
    D = rep(1L, 28),
    n = c(rep("300", 22), "200", "400", "500", "300", "300", "300"),
    reservoir_m = c(
      rep(360, 8),
      300, 300, 420, 420, 540, 540,
      360, 360, 360,
      rep(360, 11)
    ),
    direct_lag = c(
      rep(360, 8),
      300, 360, 360, 420, 360, 540,
      240, 480, 540,
      rep(360, 11)
    ),
    alpha = c(
      0.98, 0.96, 0.99, 0.98, 0.98, 0.98, 0.98, 0.98,
      rep(0.98, 17),
      0.98, 0.99, 0.98
    ),
    rho = c(
      0.95, 0.95, 0.95, 0.93, 0.97, 0.95, 0.95, 0.95,
      rep(0.95, 20)
    ),
    pi_w = 0.03,
    pi_in = 1.00,
    win_scale_global = c(
      0.18, 0.18, 0.18, 0.18, 0.18, 0.14, 0.22, 0.26,
      rep(0.18, 18),
      0.18, 0.22
    ),
    win_scale_bias = c(
      0.18, 0.18, 0.18, 0.18, 0.18, 0.14, 0.22, 0.26,
      rep(0.18, 18),
      0.18, 0.22
    ),
    beta_tau0 = c(
      rep(0.10, 17),
      0.30, 0.03, 0.10, 0.10, 0.30,
      rep(0.10, 6)
    ),
    alpha_tau0 = c(
      rep(0.03, 19),
      0.10, 0.01, 0.10,
      rep(0.03, 6)
    ),
    seed = c(rep(20260610L, 25), rep(20260611L, 3)),
    stringsAsFactors = FALSE
  )
  validate_core_range(args$exploration_first_core, nrow(candidate_grid), "exploration")
  app_write_csv(candidate_grid, file.path(out_dir, "candidate_grid.csv"))

  manifest_rows <- vector("list", nrow(candidate_grid))
  seed_contract_rows <- vector("list", nrow(candidate_grid))
  launcher <- c(
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    sprintf("cd %s", shQuote(app_repo_root())),
    "export OMP_NUM_THREADS=1",
    "export OPENBLAS_NUM_THREADS=1",
    "export MKL_NUM_THREADS=1",
    "export VECLIB_MAXIMUM_THREADS=1",
    "export NUMEXPR_NUM_THREADS=1",
    "",
    "# Generated by application/scripts/25_prepare_glofas_d14_full7_and_exploration_20260611.R.",
    "# Broad p50 exploration around D14. One tmux session per candidate.",
    ""
  )

  for (i in seq_len(nrow(candidate_grid))) {
    cand <- candidate_grid[i, , drop = FALSE]
    slug <- candidate_slug(cand)
    cand_dir <- file.path(out_dir, slug)
    app_ensure_dir(cand_dir)
    run_id <- sprintf("%s_%s_%s", args$exploration_batch_id, slug, qid)
    qgrid_path <- file.path(cand_dir, sprintf("quantile_grid_%s.csv", qid))
    model_grid_path <- file.path(cand_dir, sprintf("model_grid_%s.csv", qid))
    config_path <- file.path(cand_dir, sprintf("config_%s.yaml", qid))
    app_write_csv(p50, qgrid_path)

    raw_row <- raw_base
    qdesn_row <- qdesn_base
    raw_row$fit_id <- paste0("raw_glofas_", slug, "_", qid)
    raw_row$model_id <- paste0("raw_glofas_", slug)
    raw_row$quantile_level <- qlev
    raw_row$config_hash <- "TO_BE_COMPUTED"
    raw_row$notes <- sprintf("Raw GloFAS p50 baseline for broad exploration candidate %s (%s).", cand$candidate_id, cand$search_role)
    qdesn_row$fit_id <- paste0("qdesn_latent_path_rhs_al_vb_", slug, "_", qid)
    qdesn_row$model_id <- paste0("qdesn_latent_path_rhs_al_vb_", slug)
    qdesn_row$quantile_level <- qlev
    qdesn_row$reservoir_seed <- as.integer(cand$seed[[1L]])
    qdesn_row$config_hash <- "TO_BE_COMPUTED"
    qdesn_row$notes <- sprintf(
      "Broad D14-region p50 candidate %s (%s): n=%s, m=%s, direct=%s, alpha=%s, rho=%s, win=%s, beta_tau0=%s, alpha_tau0=%s, seed=%s.",
      cand$candidate_id, cand$search_role, cand$n, cand$reservoir_m, cand$direct_lag,
      cand$alpha, cand$rho, cand$win_scale_global, cand$beta_tau0, cand$alpha_tau0, cand$seed
    )
    model_grid <- rbind(raw_row, qdesn_row)
    app_write_csv(model_grid, model_grid_path)

    cfg <- set_reservoir_contract(base_cfg, cand)
    cfg$application_name <- run_id
    cfg$description <- paste(
      sprintf("Broad D14-region median-only GloFAS exploration candidate %s (%s).", cand$candidate_id, cand$search_role),
      "This is a p50 screening run; do not promote as article-facing without full-seven relaunch and synthesis."
    )
    cfg$paths$quantile_grid <- repo_rel(qgrid_path)
    cfg$paths$model_grid <- repo_rel(model_grid_path)
    cfg$paths$cache <- file.path("application/cache", run_id)
    cfg$scoring$intervals <- list(list(lower = 0.05, upper = 0.95, nominal = 0.90))
    cfg$execution$final_launch$enabled <- TRUE
    cfg$execution$final_launch$note <- "User-approved broad p50 exploration around D14; not an article-facing promotion target."
    app_write_yaml(cfg, config_path)

    validated_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
    seed_contract <- app_qdesn_seed_contract_report(cfg, validated_grid)
    app_validate_qdesn_seed_contract(cfg, validated_grid)
    seed_contract$candidate_id <- cand$candidate_id
    seed_contract$search_role <- cand$search_role
    seed_contract$run_id <- run_id
    seed_contract_rows[[i]] <- seed_contract
    app_write_csv(seed_contract, file.path(cand_dir, "seed_contract_prelaunch.csv"))

    core <- as.integer(args$exploration_first_core) + i - 1L
    session <- sprintf("%s_%s", args$exploration_batch_id, cand$candidate_id)
    log_path <- file.path("application/logs", paste0(run_id, ".log"))
    command <- sprintf(
      "taskset -c %d Rscript application/scripts/run_all.R --config %s --run_id %s --preflight true --confirm_final_launch true > %s 2>&1",
      core,
      repo_rel(config_path),
      run_id,
      log_path
    )
    launcher <- c(
      launcher,
      sprintf("# %s: %s", cand$candidate_id, cand$search_role),
      sprintf("if tmux has-session -t %s 2>/dev/null; then echo 'Session exists: %s' >&2; exit 1; fi", shQuote(session), session),
      sprintf("tmux new-session -d -s %s %s", shQuote(session), shQuote(command)),
      ""
    )

    manifest_rows[[i]] <- data.frame(
      batch_id = args$exploration_batch_id,
      candidate_id = cand$candidate_id,
      search_role = cand$search_role,
      run_index = i,
      quantile_id = qid,
      quantile_level = qlev,
      run_id = run_id,
      config_path = repo_rel(config_path),
      model_grid_path = repo_rel(model_grid_path),
      quantile_grid_path = repo_rel(qgrid_path),
      core = core,
      D = cand$D,
      n = cand$n,
      reservoir_m = cand$reservoir_m,
      direct_lag = cand$direct_lag,
      alpha = cand$alpha,
      rho = cand$rho,
      pi_w = cand$pi_w,
      pi_in = cand$pi_in,
      win_scale_global = cand$win_scale_global,
      win_scale_bias = cand$win_scale_bias,
      beta_tau0 = cand$beta_tau0,
      alpha_tau0 = cand$alpha_tau0,
      seed = cand$seed,
      raw_fit_id = raw_row$fit_id,
      qdesn_fit_id = qdesn_row$fit_id,
      raw_model_id = raw_row$model_id,
      qdesn_model_id = qdesn_row$model_id,
      log_path = log_path,
      launch_status = "prepared_not_launched",
      stringsAsFactors = FALSE
    )
  }

  launch_manifest <- do.call(rbind, manifest_rows)
  app_write_csv(launch_manifest, file.path(out_dir, "launch_manifest.csv"))
  seed_contract_all <- app_bind_rows_fill(seed_contract_rows)
  app_write_csv(seed_contract_all, file.path(out_dir, "seed_contract_prelaunch_all.csv"))

  launcher_path <- file.path(out_dir, sprintf("launch_all_%s.sh", args$exploration_batch_id))
  writeLines(launcher, launcher_path)
  Sys.chmod(launcher_path, "0755")

  readme <- c(
    sprintf("# GloFAS D14 Broad Median Exploration: %s", args$exploration_batch_id),
    "",
    "Prepared locally and ignored by git.",
    "",
    "Purpose: search around the D14 region while the D14 full-seven launch runs.",
    "",
    "Design axes:",
    "- D14 anchor and nearby alpha/rho/win-scale variants.",
    "- Memory/direct-lag alternatives around 300, 360, 420, and 540 days.",
    "- Readout prior sensitivity for beta and discrepancy alpha blocks.",
    "- Capacity variants at n=200, 400, and 500.",
    "- A small seed-stability slice at seed 20260611.",
    "",
    "Launch:",
    sprintf("`bash %s`", repo_rel(launcher_path)),
    "",
    "Decision rule:",
    "Rank by p50 check loss, then require visual diagnostics and at least one seed-stability check before any full-seven relaunch."
  )
  writeLines(readme, file.path(out_dir, "README.md"))
  invisible(launch_manifest)
}

full7_manifest <- prepare_full7()
exploration_manifest <- prepare_exploration()

cat(repo_rel(file.path(app_path(args$full7_out_dir), "launch_manifest.csv")), "\n")
cat(repo_rel(file.path(app_path(args$exploration_out_dir), "launch_manifest.csv")), "\n")
cat(sprintf("prepared_full7_rows=%d prepared_exploration_rows=%d\n", nrow(full7_manifest), nrow(exploration_manifest)))
