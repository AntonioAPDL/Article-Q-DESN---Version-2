#!/usr/bin/env Rscript
# Purpose: prepare a focused median-only follow-up queue around the strongest
# deep-identity GloFAS Q-DESN region found in the 2026-06-17 median grid.
# Runtime configs are generated under local_trackers/ and are intentionally
# ignored by git.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_deep_identity_median_grid_20260617/deepid_d4_w100_m300_a050_r95_bt1em3_at3em2/config_p50.yaml",
  base_model_grid = "local_trackers/runtime_configs/glofas_deep_identity_median_grid_20260617/deepid_d4_w100_m300_a050_r95_bt1em3_at3em2/model_grid_p50.csv",
  quantile_targets = "application/config/glofas_quantile_targets_dec25_synthesis_20260603.csv",
  scheduler_template = "local_trackers/runtime_configs/glofas_deep_identity_median_grid_20260617/scheduler.py",
  out_dir = "local_trackers/runtime_configs/glofas_deep_identity_followup_grid_20260618",
  batch_id = "glofas_deep_identity_followup_grid_20260618",
  max_jobs = "30",
  core_spec = "0-29"
))

repo_rel <- function(path) app_prefer_repo_relative_path(path)
as_range <- function(lo, hi) list(range = c(as.integer(lo), as.integer(hi)))
slugify <- function(x) gsub("[^A-Za-z0-9_.-]+", "_", tolower(as.character(x)))
slug_alpha <- function(x) sprintf("%03d", as.integer(round(as.numeric(x) * 1000)))
slug_num <- function(x, digits = 3L) sprintf(paste0("%0", digits, "d"), as.integer(round(as.numeric(x))))
q_label <- function(qid) gsub("[^A-Za-z0-9]+", "", as.character(qid))

parse_core_spec <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x)) return(integer())
  out <- integer()
  for (part in trimws(unlist(strsplit(x, ",", fixed = TRUE), use.names = FALSE))) {
    if (!nzchar(part)) next
    if (grepl("-", part, fixed = TRUE)) {
      ab <- suppressWarnings(as.integer(strsplit(part, "-", fixed = TRUE)[[1L]]))
      if (length(ab) != 2L || any(!is.finite(ab))) stop(sprintf("Invalid core range: %s", part), call. = FALSE)
      out <- c(out, seq.int(ab[[1L]], ab[[2L]]))
    } else if (grepl(":", part, fixed = TRUE)) {
      ab <- suppressWarnings(as.integer(strsplit(part, ":", fixed = TRUE)[[1L]]))
      if (length(ab) != 2L || any(!is.finite(ab))) stop(sprintf("Invalid core range: %s", part), call. = FALSE)
      out <- c(out, seq.int(ab[[1L]], ab[[2L]]))
    } else {
      val <- suppressWarnings(as.integer(part))
      if (!is.finite(val)) stop(sprintf("Invalid core id: %s", part), call. = FALSE)
      out <- c(out, val)
    }
  }
  unique(out)
}

copy_cfg <- function(cfg) {
  cfg$.__config_path__ <- NULL
  cfg
}

as_depth_list <- function(value, depth) {
  values <- rep(value, depth)
  if (depth == 1L) as.numeric(values[[1L]]) else as.list(as.numeric(values))
}

set_reservoir_core <- function(cfg, depth, width, memory, leak_alpha) {
  depth <- as.integer(depth)
  width <- as.integer(width)
  memory <- as.integer(memory)
  n_vec <- rep(width, depth)
  n_tilde_vec <- if (depth > 1L) rep(width, depth - 1L) else integer(0)

  cfg$reservoir$D <- depth
  cfg$reservoir$n <- if (depth == 1L) n_vec[[1L]] else as.list(n_vec)
  cfg$reservoir$n_tilde <- if (depth == 1L) list() else as.list(n_tilde_vec)
  cfg$reservoir$m <- memory
  cfg$reservoir$washout <- 500L
  cfg$reservoir$alpha <- as_depth_list(leak_alpha, depth)
  cfg$reservoir$rho <- as_depth_list(0.95, depth)
  cfg$reservoir$pi_w <- as_depth_list(0.03, depth)
  cfg$reservoir$pi_in <- as_depth_list(1.0, depth)
  cfg$reservoir$win_scale_global <- 0.18
  cfg$reservoir$win_scale_bias <- 0.18
  cfg$reservoir$input_bound <- "none"
  cfg$reservoir$act_f <- "tanh"
  cfg$reservoir$act_k <- "identity"
  cfg$reservoir$standardize_inputs <- TRUE
  cfg$reservoir$add_bias <- TRUE
  cfg$reservoir$seed <- 20260512L

  cfg$covariates$readout$include_lags <- TRUE
  cfg$covariates$readout$lags <- as_range(0L, memory)
  cfg$covariates$readout$standardize <- TRUE
  cfg$covariates$readout$scale_reference <- "retrospective_train"

  cfg$feature_contract$version <- "latent_path_v0.3"
  cfg$feature_contract$two_block_design <- TRUE
  cfg$feature_contract$reservoir_input$internal_bias <- TRUE
  cfg$feature_contract$reservoir_input$output_lags <- as_range(1L, memory)
  cfg$feature_contract$reservoir_input$covariates$ppt <- as_range(0L, memory)
  cfg$feature_contract$reservoir_input$covariates$soil <- as_range(0L, memory)
  cfg$feature_contract$reservoir_input$standardize <- TRUE
  cfg$feature_contract$readout$add_intercept <- TRUE
  cfg$feature_contract$readout$include_reservoir_state <- TRUE
  cfg$feature_contract$readout$reservoir_state_lags <- list()
  cfg$feature_contract$readout$include_input_block <- FALSE
  cfg$feature_contract$readout$input_block$output_lags <- as_range(1L, memory)
  cfg$feature_contract$readout$input_block$covariates$ppt <- as_range(0L, memory)
  cfg$feature_contract$readout$input_block$covariates$soil <- as_range(0L, memory)
  cfg$feature_contract$readout$input_block$include_internal_bias <- FALSE
  cfg$feature_contract$readout$include_horizon_scaled <- FALSE
  cfg$feature_contract$readout$standardize_output_lags <- TRUE
  cfg$feature_contract$readout$standardize_non_intercept <- FALSE
  cfg$feature_contract$forecast_alignment$output_lags_anchor <- "target_date"
  cfg$feature_contract$forecast_alignment$covariate_lags_anchor <- "target_date"
  cfg
}

set_inference_core <- function(cfg, max_iter) {
  max_iter <- as.integer(max_iter)
  cfg$inference$default_method <- "vb_ld"
  cfg$inference$likelihood_family <- "al"
  cfg$inference$coefficient_prior_default <- "rhs"
  cfg$inference$vb_ld$max_iter <- max_iter
  cfg$inference$vb_ld$max_iter_hard_cap <- max_iter
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
  cfg$inference$mcmc$rhs_tau0 <- 1e-3
  cfg$inference$mcmc$rhs_slab_s2 <- 1.0
  cfg$inference$mcmc$rhs_a_zeta <- 2.0
  cfg$inference$mcmc$rhs_b_zeta <- 4.0
  cfg$inference$mcmc$rhs_alpha_tau0 <- 0.03
  cfg$inference$mcmc$rhs_alpha_slab_s2 <- 1.0
  cfg$inference$mcmc$rhs_alpha_a_zeta <- 2.0
  cfg$inference$mcmc$rhs_alpha_b_zeta <- 4.0
  cfg$post_analysis$run_after_outputs <- FALSE
  cfg$execution$seed_contract <- cfg$execution$seed_contract %||% list()
  cfg$execution$seed_contract$require_config_model_grid_match <- TRUE
  cfg$execution$final_launch$enabled <- TRUE
  cfg$execution$final_launch$note <- "User-approved focused median-only deep identity follow-up; not an article-facing promotion target."
  cfg
}

local_grid <- expand.grid(
  D = 4L,
  width = c(80L, 100L, 120L),
  reservoir_m = c(240L, 300L, 360L),
  alpha = c(0.035, 0.050, 0.075),
  max_iter = 150L,
  candidate_family = "local_search",
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
confirm_grid <- data.frame(
  D = c(4L, 3L, 4L),
  width = c(100L, 200L, 100L),
  reservoir_m = c(300L, 300L, 300L),
  alpha = c(0.050, 0.050, 0.100),
  max_iter = c(250L, 250L, 250L),
  candidate_family = c("confirm_primary", "confirm_clean_backup", "confirm_stable_comparator"),
  stringsAsFactors = FALSE
)
candidate_table <- rbind(local_grid, confirm_grid)
candidate_table <- candidate_table[order(candidate_table$candidate_family != "local_search", candidate_table$D, candidate_table$width, candidate_table$reservoir_m, candidate_table$alpha, candidate_table$max_iter), , drop = FALSE]
candidate_table$candidate_id <- sprintf(
  "%s_d%d_w%s_m%s_a%s_r95_bt1em3_at3em2_max%d",
  candidate_table$candidate_family,
  candidate_table$D,
  slug_num(candidate_table$width, 3L),
  slug_num(candidate_table$reservoir_m, 3L),
  slug_alpha(candidate_table$alpha),
  candidate_table$max_iter
)
candidate_table$candidate_name <- candidate_table$candidate_id
candidate_table$candidate_slug <- slugify(candidate_table$candidate_id)
candidate_table$n <- vapply(seq_len(nrow(candidate_table)), function(i) {
  paste(rep(candidate_table$width[[i]], candidate_table$D[[i]]), collapse = "x")
}, character(1L))
candidate_table$n_tilde <- vapply(seq_len(nrow(candidate_table)), function(i) {
  if (candidate_table$D[[i]] <= 1L) "" else paste(rep(candidate_table$width[[i]], candidate_table$D[[i]] - 1L), collapse = "x")
}, character(1L))
candidate_table$washout <- 500L
candidate_table$rho <- 0.95
candidate_table$pi_w <- 0.03
candidate_table$pi_in <- 1.0
candidate_table$win_scale_global <- 0.18
candidate_table$win_scale_bias <- 0.18
candidate_table$seed <- 20260512L
candidate_table$beta_tau0 <- 1e-3
candidate_table$alpha_tau0 <- 0.03
candidate_table$rhs_slab_s2 <- 1.0
candidate_table$rhs_a_zeta <- 2.0
candidate_table$rhs_b_zeta <- 4.0
candidate_table$include_input_block <- FALSE
candidate_table$screening_required <- FALSE

out_dir <- app_path(args$out_dir)
app_ensure_dir(out_dir)
app_ensure_dir(file.path(out_dir, "logs"))
app_ensure_dir(file.path(out_dir, "status"))

target_level <- 0.50
intervals <- list(list(lower = 0.05, upper = 0.95, nominal = 0.90))
base_cfg <- copy_cfg(app_read_config(app_path(args$base_config)))
base_grid <- app_validate_model_grid(app_path(args$base_model_grid), app_config_path(base_cfg, "schema"))
raw_base <- base_grid[base_grid$model_family == "raw_glofas", , drop = FALSE][1L, , drop = FALSE]
qdesn_base <- base_grid[base_grid$model_family == "qdesn_glofas_discrepancy", , drop = FALSE][1L, , drop = FALSE]
if (!nrow(raw_base) || !nrow(qdesn_base)) {
  stop("Base model grid must contain one raw_glofas row and one qdesn_glofas_discrepancy row.", call. = FALSE)
}

targets_all <- app_validate_quantile_grid(app_path(args$quantile_targets))
targets <- targets_all[abs(as.numeric(targets_all$quantile_level) - target_level) < 1e-12, , drop = FALSE]
if (nrow(targets) != 1L) stop("Quantile target file must contain the p50 median row.", call. = FALSE)
qid <- q_label(targets$quantile_id[[1L]])
qlev <- as.numeric(targets$quantile_level[[1L]])
qrole <- as.character(targets$role[[1L]])

max_jobs <- suppressWarnings(as.integer(args$max_jobs))
if (!is.finite(max_jobs) || max_jobs <= 0L) stop("max_jobs must be a positive integer.", call. = FALSE)
core_pool <- parse_core_spec(args$core_spec)
n_cores <- parallel::detectCores(logical = TRUE)
core_pool <- core_pool[core_pool >= 0L & core_pool < n_cores]
if (length(core_pool) < max_jobs) {
  stop(sprintf("Need at least %d valid cores but core_spec yielded %d.", max_jobs, length(core_pool)), call. = FALSE)
}
core_pool <- core_pool[seq_len(max_jobs)]

app_write_csv(candidate_table, file.path(out_dir, "candidate_grid.csv"))

all_manifest <- list()
contract_rows <- list()
seed_rows <- list()
validation_rows <- list()
model_rows_all <- list()
qgrid_rows_all <- list()

for (ci in seq_len(nrow(candidate_table))) {
  cand <- candidate_table[ci, , drop = FALSE]
  cand_dir <- file.path(out_dir, cand$candidate_slug[[1L]])
  app_ensure_dir(cand_dir)

  run_id <- sprintf("%s_%s_%s", args$batch_id, cand$candidate_slug[[1L]], qid)
  fit_suffix <- sprintf("%s_%s", args$batch_id, cand$candidate_slug[[1L]])
  raw_model_id <- sprintf("raw_glofas_%s", fit_suffix)
  qdesn_model_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s", fit_suffix)
  qgrid_path <- file.path(cand_dir, sprintf("quantile_grid_%s.csv", qid))
  model_grid_path <- file.path(cand_dir, sprintf("model_grid_%s.csv", qid))
  config_path <- file.path(cand_dir, sprintf("config_%s.yaml", qid))
  log_path <- file.path("application/logs", sprintf("%s.log", run_id))
  time_path <- file.path(out_dir, "logs", sprintf("%s.time", run_id))
  scheduler_log_path <- file.path(out_dir, "logs", sprintf("%s.scheduler.log", run_id))

  app_write_csv(targets, qgrid_path)
  qgrid_rows_all[[length(qgrid_rows_all) + 1L]] <- targets

  raw_row <- raw_base
  qdesn_row <- qdesn_base
  raw_row$fit_id <- sprintf("raw_glofas_%s_%s", fit_suffix, qid)
  raw_row$model_id <- raw_model_id
  raw_row$quantile_level <- qlev
  raw_row$config_hash <- "TO_BE_COMPUTED"
  raw_row$notes <- sprintf("Raw GloFAS baseline for focused deep identity follow-up %s; quantile=%s (%s).", cand$candidate_slug, qlev, qrole)
  qdesn_row$fit_id <- sprintf("qdesn_latent_path_rhs_al_vb_%s_%s", fit_suffix, qid)
  qdesn_row$model_id <- qdesn_model_id
  qdesn_row$quantile_level <- qlev
  qdesn_row$reservoir_seed <- as.integer(cand$seed[[1L]])
  qdesn_row$config_hash <- "TO_BE_COMPUTED"
  qdesn_row$notes <- sprintf("Q-DESN focused deep identity follow-up %s; quantile=%s (%s).", cand$candidate_slug, qlev, qrole)
  model_grid <- rbind(raw_row, qdesn_row)
  app_write_csv(model_grid, model_grid_path)
  model_rows_all[[length(model_rows_all) + 1L]] <- model_grid

  cfg <- base_cfg
  cfg <- set_reservoir_core(
    cfg,
    depth = cand$D[[1L]],
    width = cand$width[[1L]],
    memory = cand$reservoir_m[[1L]],
    leak_alpha = cand$alpha[[1L]]
  )
  cfg <- set_inference_core(cfg, cand$max_iter[[1L]])
  cfg$application_name <- run_id
  cfg$description <- sprintf(
    "Focused median-only GloFAS deep identity follow-up. Candidate %s; quantile %s (%s).",
    cand$candidate_slug,
    qlev,
    qrole
  )
  cfg$paths$quantile_grid <- repo_rel(qgrid_path)
  cfg$paths$model_grid <- repo_rel(model_grid_path)
  cfg$paths$cache <- file.path("application/cache", run_id)
  cfg$scoring$intervals <- intervals
  app_write_yaml(cfg, config_path)

  validated_grid <- app_validate_model_grid(model_grid_path, app_config_path(cfg, "schema"))
  app_validate_qdesn_model_grid_prior_contract(validated_grid)
  seed_contract <- app_qdesn_seed_contract_report(cfg, validated_grid)
  app_validate_qdesn_seed_contract(cfg, validated_grid)
  seed_contract$candidate_id <- cand$candidate_id
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
    candidate_family = cand$candidate_family,
    candidate_name = cand$candidate_name,
    run_id = run_id,
    quantile_id = qid,
    quantile_level = qlev,
    D = cand$D,
    n = cand$n,
    n_tilde = cand$n_tilde,
    reservoir_m = cand$reservoir_m,
    washout = cand$washout,
    alpha = cand$alpha,
    rho = cand$rho,
    pi_w = cand$pi_w,
    pi_in = cand$pi_in,
    win_scale_global = cand$win_scale_global,
    win_scale_bias = cand$win_scale_bias,
    seed = cand$seed,
    beta_tau0 = cand$beta_tau0,
    alpha_tau0 = cand$alpha_tau0,
    rhs_slab_s2 = cand$rhs_slab_s2,
    max_iter = cand$max_iter,
    include_input_block = isTRUE(cand$include_input_block),
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

  all_manifest[[length(all_manifest) + 1L]] <- data.frame(
    batch_id = args$batch_id,
    run_index = ci,
    candidate_id = cand$candidate_id,
    candidate_family = cand$candidate_family,
    candidate_name = cand$candidate_name,
    candidate_slug = cand$candidate_slug,
    quantile_id = qid,
    quantile_level = qlev,
    role = qrole,
    run_id = run_id,
    config_path = repo_rel(config_path),
    quantile_grid_path = repo_rel(qgrid_path),
    model_grid_path = repo_rel(model_grid_path),
    log_path = log_path,
    scheduler_log_path = repo_rel(scheduler_log_path),
    time_path = repo_rel(time_path),
    raw_fit_id = raw_row$fit_id,
    qdesn_fit_id = qdesn_row$fit_id,
    raw_model_id = raw_model_id,
    qdesn_model_id = qdesn_model_id,
    core_pool = paste(core_pool, collapse = ","),
    launch_status = "prepared_not_launched",
    stringsAsFactors = FALSE
  )
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

scheduler_template <- app_path(args$scheduler_template)
if (!file.exists(scheduler_template)) stop(sprintf("Missing scheduler template: %s", scheduler_template), call. = FALSE)
scheduler_path <- file.path(out_dir, "scheduler.py")
file.copy(scheduler_template, scheduler_path, overwrite = TRUE)
Sys.chmod(scheduler_path, "0755")

launch_path <- file.path(out_dir, sprintf("launch_queued_%s.sh", args$batch_id))
status_path <- file.path(out_dir, "scheduler_status.csv")
launch_lines <- c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  sprintf("cd %s", shQuote(app_repo_root())),
  "export OMP_NUM_THREADS=1",
  "export OPENBLAS_NUM_THREADS=1",
  "export MKL_NUM_THREADS=1",
  "export VECLIB_MAXIMUM_THREADS=1",
  "export NUMEXPR_NUM_THREADS=1",
  sprintf(
    "python3 %s --repo-root %s --manifest %s --status-csv %s --max-jobs %d --cores %s",
    shQuote(repo_rel(scheduler_path)),
    shQuote(app_repo_root()),
    shQuote(repo_rel(file.path(out_dir, "launch_manifest.csv"))),
    shQuote(repo_rel(status_path)),
    max_jobs,
    shQuote(paste(core_pool, collapse = ","))
  )
)
writeLines(launch_lines, launch_path)
Sys.chmod(launch_path, "0755")

readme_lines <- c(
  sprintf("# GloFAS Focused Deep Identity Follow-Up: %s", args$batch_id),
  "",
  "This directory is generated locally and ignored by git.",
  "",
  "Purpose: focused median-only exploration around the completed grid winner `D4 w100 m300 alpha=0.05`, with a clean D3 backup and stable alpha=0.10 comparator.",
  "",
  "Scope:",
  "- Quantile: p50 only.",
  "- Local search: D=4; width in {80,100,120}; m in {240,300,360}; alpha in {0.035,0.050,0.075}; max_iter=150.",
  "- Confirmation: primary D4/w100/m300/a0.05, clean D3/w200/m300/a0.05, and D4/w100/m300/a0.10 comparator; max_iter=250.",
  "- Reservoir input: output lags 1:m and ppt/soil lags 0:m.",
  "- Readout contract: reservoir state only, no direct input block.",
  "- RHS priors: beta/shared tau0=1e-3; alpha/discrepancy tau0=0.03; slab_s2=1; a_zeta=2; b_zeta=4.",
  "",
  "Launch:",
  sprintf("`tmux new-session -d -s %s_sched 'bash %s'`", args$batch_id, repo_rel(launch_path)),
  "",
  "Health:",
  sprintf("`column -s, -t %s | less -S`", repo_rel(status_path)),
  "",
  "Promotion rule:",
  "- Do not promote directly from this median follow-up.",
  "- Use this grid to confirm the p50 architecture before full-seven quantile synthesis.",
  "- Run post-fit diagnostics for finalists before any full-seven launch."
)
writeLines(readme_lines, file.path(out_dir, "README.md"))

if (nrow(candidate_table) != 30L || nrow(launch_manifest) != 30L) {
  stop(sprintf("Expected 30 candidates/fits; got candidate=%d launch=%d.", nrow(candidate_table), nrow(launch_manifest)), call. = FALSE)
}
if (any(duplicated(launch_manifest$run_id))) stop("Generated duplicate run_id values.", call. = FALSE)
if (any(!prelaunch_validation$launchable_without_overwrite)) {
  stop("Some generated run IDs already have nonempty run directories. See prelaunch_validation.csv.", call. = FALSE)
}
if (any(!prelaunch_validation$model_grid_valid | !prelaunch_validation$seed_contract_valid | !prelaunch_validation$covariate_policy_valid)) {
  stop("Prelaunch validation failed. See prelaunch_validation.csv.", call. = FALSE)
}

message("Prepared focused GloFAS deep identity follow-up grid in: ", repo_rel(out_dir))
message("Candidates/fits: ", nrow(launch_manifest))
message("Queue max active jobs: ", max_jobs)
message("Launcher prepared but not executed: ", repo_rel(launch_path))
cat(file.path(out_dir, "launch_manifest.csv"), "\n")

