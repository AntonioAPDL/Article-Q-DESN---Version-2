#!/usr/bin/env Rscript
# Purpose: prepare a diverse median-only GloFAS Q-DESN specification search.
# The generated configs live under local_trackers/ and are intentionally ignored.
# This script prepares and validates launch artifacts; it does not itself fit models.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_readout_refinement_gate_20260606/reservoir_only_m360/config_p50.yaml",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  out_dir = "local_trackers/runtime_configs/glofas_diverse_median_grid_20260608",
  batch_id = "glofas_diverse_median_grid_20260608",
  first_core = 14
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
as_range <- function(lo, hi) list(range = c(as.integer(lo), as.integer(hi)))
slugify <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", as.character(x))
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))

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
  cfg$reservoir$D <- as.integer(depth)
  cfg$reservoir$n <- if (depth == 1L) n_vec[[1L]] else as.list(n_vec)
  cfg$reservoir$n_tilde <- list()
  cfg$reservoir$m <- as.integer(candidate$m[[1L]])
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
  cfg$reservoir$seed <- as.integer(candidate$seed[[1L]])

  m <- as.integer(candidate$m[[1L]])
  cfg$feature_contract$reservoir_input$output_lags <- as_range(1L, m)
  cfg$feature_contract$reservoir_input$covariates$ppt <- as_range(0L, m)
  cfg$feature_contract$reservoir_input$covariates$soil <- as_range(0L, m)
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$include_input_block <- FALSE
  cfg$feature_contract$readout$input_block$output_lags <- as_range(1L, 30L)
  cfg$feature_contract$readout$input_block$covariates$ppt <- as_range(0L, 30L)
  cfg$feature_contract$readout$input_block$covariates$soil <- as_range(0L, 30L)

  cfg$inference$vb_ld$rhs_tau0 <- as.numeric(candidate$beta_tau0[[1L]])
  cfg$inference$vb_ld$rhs_alpha_tau0 <- as.numeric(candidate$alpha_tau0[[1L]])
  cfg$inference$vb_ld$max_iter <- 150L
  cfg$inference$vb_ld$max_iter_hard_cap <- 150L
  cfg$inference$vb_ld$n_draws <- 2000L
  cfg$inference$vb_ld$diagnostics$profile_substeps <- FALSE
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg
}

candidate_grid <- data.frame(
  candidate_id = sprintf("G%02d", 1:16),
  search_role = c(
    "current_reference",
    "longer_memory",
    "shorter_rich_memory",
    "slower_dynamics",
    "faster_dynamics",
    "higher_persistence",
    "lower_persistence",
    "weaker_input_drive",
    "stronger_input_drive",
    "larger_capacity",
    "smaller_capacity",
    "deep_compact",
    "deep_smoother",
    "balanced_prior",
    "looser_reference_prior",
    "looser_discrepancy_prior"
  ),
  D = c(1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L, 1L, 1L, 1L),
  n = c("300", "300", "300", "300", "300", "300", "300", "300", "300", "500", "200", "150x150", "150x150", "300", "300", "300"),
  m = c(360L, 540L, 240L, 360L, 360L, 360L, 360L, 360L, 360L, 360L, 360L, 360L, 360L, 360L, 360L, 360L),
  alpha = c(0.92, 0.92, 0.92, 0.80, 0.98, 0.92, 0.92, 0.92, 0.92, 0.92, 0.92, 0.92, 0.80, 0.92, 0.92, 0.92),
  rho = c(0.95, 0.95, 0.95, 0.95, 0.95, 0.98, 0.90, 0.95, 0.95, 0.95, 0.95, 0.95, 0.95, 0.95, 0.95, 0.95),
  pi_w = 0.03,
  pi_in = 1.00,
  win_scale_global = c(0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.10, 0.30, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18),
  win_scale_bias = c(0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.10, 0.30, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18, 0.18),
  beta_tau0 = c(0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.03, 0.30, 0.10),
  alpha_tau0 = c(0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.03, 0.10),
  seed = 20260512L,
  stringsAsFactors = FALSE
)

base_cfg <- copy_without_runtime_fields(app_read_config(app_path(args$base_config)))
targets_all <- app_validate_quantile_grid(app_path(args$quantile_targets))
target <- targets_all[abs(as.numeric(targets_all$quantile_level) - 0.5) < 1e-12, , drop = FALSE]
if (nrow(target) != 1L) stop("Expected exactly one p50 target row.", call. = FALSE)
qid <- q_label(target$quantile_id[[1L]])
qlev <- as.numeric(target$quantile_level[[1L]])

base_grid <- app_validate_model_grid(app_config_path(base_cfg, "model_grid"), app_config_path(base_cfg, "schema"))
raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
if (!nrow(raw_base) || !nrow(qdesn_base)) {
  stop("Base model grid must contain raw_glofas and qdesn_glofas_discrepancy rows.", call. = FALSE)
}

out_dir <- app_path(args$out_dir)
app_ensure_dir(out_dir)
app_write_csv(candidate_grid, file.path(out_dir, "candidate_grid.csv"))

manifest_rows <- vector("list", nrow(candidate_grid))
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
  "# Generated by application/scripts/22_prepare_glofas_diverse_median_grid_20260608.R.",
  "# Median-only p50 search. One tmux session per candidate, one pinned core each.",
  ""
)

for (i in seq_len(nrow(candidate_grid))) {
  cand <- candidate_grid[i, , drop = FALSE]
  candidate_slug <- tolower(sprintf(
    "%s_%s_d%sn%s_m%s_a%s_r%s_w%s_bt%s_at%s",
    cand$candidate_id,
    cand$search_role,
    cand$D,
    gsub("x", "x", cand$n),
    cand$m,
    gsub("[.]", "p", sprintf("%.2f", cand$alpha)),
    gsub("[.]", "p", sprintf("%.2f", cand$rho)),
    gsub("[.]", "p", sprintf("%.2f", cand$win_scale_global)),
    gsub("[.]", "p", format(cand$beta_tau0, scientific = FALSE, trim = TRUE)),
    gsub("[.]", "p", format(cand$alpha_tau0, scientific = FALSE, trim = TRUE))
  ))
  candidate_slug <- slugify(candidate_slug)
  cand_dir <- file.path(out_dir, candidate_slug)
  app_ensure_dir(cand_dir)

  run_id <- sprintf("%s_%s_%s", args$batch_id, candidate_slug, qid)
  qgrid_path <- file.path(cand_dir, sprintf("quantile_grid_%s.csv", qid))
  model_grid_path <- file.path(cand_dir, sprintf("model_grid_%s.csv", qid))
  config_path <- file.path(cand_dir, sprintf("config_%s.yaml", qid))
  app_write_csv(target, qgrid_path)

  raw_row <- raw_base
  qdesn_row <- qdesn_base
  raw_row$fit_id <- paste0("raw_glofas_", candidate_slug, "_", qid)
  raw_row$model_id <- paste0("raw_glofas_", candidate_slug)
  raw_row$quantile_level <- qlev
  raw_row$config_hash <- "TO_BE_COMPUTED"
  raw_row$notes <- sprintf("Raw GloFAS median baseline for diverse median-grid candidate %s (%s).", cand$candidate_id, cand$search_role)
  qdesn_row$fit_id <- paste0("qdesn_latent_path_rhs_al_vb_", candidate_slug, "_", qid)
  qdesn_row$model_id <- paste0("qdesn_latent_path_rhs_al_vb_", candidate_slug)
  qdesn_row$quantile_level <- qlev
  qdesn_row$reservoir_seed <- as.integer(cand$seed[[1L]])
  qdesn_row$config_hash <- "TO_BE_COMPUTED"
  qdesn_row$notes <- sprintf(
    paste(
      "Q-DESN median-grid candidate %s (%s): D=%s, n=%s, m=%s, alpha=%s, rho=%s,",
      "win=%s, beta_tau0=%s, alpha_tau0=%s. Full-seven quantiles should be run only if this p50 gate is competitive."
    ),
    cand$candidate_id, cand$search_role, cand$D, cand$n, cand$m, cand$alpha,
    cand$rho, cand$win_scale_global, cand$beta_tau0, cand$alpha_tau0
  )
  model_grid <- rbind(raw_row, qdesn_row)
  app_write_csv(model_grid, model_grid_path)
  app_validate_model_grid(model_grid_path, app_config_path(base_cfg, "schema"))

  cfg <- set_reservoir_contract(base_cfg, cand)
  cfg$application_name <- run_id
  cfg$description <- paste(
    sprintf("Diverse median-only GloFAS Q-DESN search candidate %s (%s).", cand$candidate_id, cand$search_role),
    "This is a p50 screening run; promote or full-seven relaunch only after candidate ranking and visual diagnostics."
  )
  cfg$paths$quantile_grid <- repo_rel(qgrid_path)
  cfg$paths$model_grid <- repo_rel(model_grid_path)
  cfg$paths$cache <- file.path("application/cache", run_id)
  cfg$scoring$intervals <- list(list(lower = 0.05, upper = 0.95, nominal = 0.90))
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- "User-approved diverse median-grid screen. This is a p50 gate, not an article-facing promotion target."
  app_write_yaml(cfg, config_path)

  core <- as.integer(args$first_core) + i - 1L
  session <- sprintf("%s_%s", args$batch_id, cand$candidate_id)
  log_path <- file.path("application/logs", paste0(run_id, ".log"))
  command <- sprintf(
    "taskset -c %d Rscript application/scripts/run_all.R --config %s --run_id %s --preflight true --confirm_final_launch true > %s 2>&1",
    core,
    repo_rel(config_path),
    run_id,
    log_path
  )

  manifest_rows[[i]] <- data.frame(
    batch_id = args$batch_id,
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
    m = cand$m,
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

  launcher <- c(
    launcher,
    sprintf("# %s: %s", cand$candidate_id, cand$search_role),
    sprintf("if tmux has-session -t %s 2>/dev/null; then echo 'Session exists: %s' >&2; exit 1; fi", shQuote(session), session),
    sprintf("tmux new-session -d -s %s %s", shQuote(session), shQuote(command)),
    ""
  )
}

launch_manifest <- do.call(rbind, manifest_rows)
app_write_csv(launch_manifest, file.path(out_dir, "launch_manifest.csv"))

launcher_path <- file.path(out_dir, sprintf("launch_all_%s.sh", args$batch_id))
writeLines(launcher, launcher_path)
Sys.chmod(launcher_path, "0755")

readme <- c(
  sprintf("# GloFAS Diverse Median Grid: %s", args$batch_id),
  "",
  "This directory is generated locally and ignored by git.",
  "",
  "Purpose: run a median-only p50 screen across a deliberately diverse but bounded set of Q-DESN specifications.",
  "",
  "Baseline to beat:",
  "- Current promoted full-seven candidate: `glofas_reservoir_only_m360_full7_20260607`.",
  "- Best previous median-only p50 reference: approximately `0.5690` mean check loss.",
  "",
  "Search axes:",
  "- Memory: `m=240,360,540`.",
  "- Dynamics: `alpha=0.80,0.92,0.98`; `rho=0.90,0.95,0.98`.",
  "- Input scale: `win=0.10,0.18,0.30`.",
  "- Capacity/depth: `D=1,n=200/300/500` and `D=2,n=150x150`.",
  "- RHS prior asymmetry: `(beta_tau0,alpha_tau0)` near `(0.10,0.03)` plus balanced/looser variants.",
  "",
  "Decision rule:",
  "1. Rank by p50 check loss and inspect fit figures.",
  "2. Repeat the top three or four candidates with additional seeds.",
  "3. Run p05/p50/p95 only for seed-stable winners.",
  "4. Run full-seven quantiles only after the p50 and three-quantile gates pass.",
  "",
  "Prepared files:",
  "- `candidate_grid.csv`: scientific candidate grid.",
  "- `launch_manifest.csv`: one row per p50 run.",
  sprintf("- `%s`: generated tmux launcher.", basename(launcher_path))
)
writeLines(readme, file.path(out_dir, "README.md"))

cat(repo_rel(file.path(out_dir, "launch_manifest.csv")), "\n")
