#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/covariate_design.R"))
source(app_path("application/R/build_application_panel.R"))
source(app_path("application/R/latent_path_design.R"))
source(app_path("application/R/discrepancy_design.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  run_label = "glofas_normal_rhs_fixed_a050_r090_n5000_20260901",
  previous_rhs_score_path = "local_trackers/runtime_configs/glofas_normal_rhs_top10_vb_20260901/tables/normal_rhs_scores_latest.csv",
  alpha = "0.5",
  rho = "0.9",
  tau0 = "1",
  max_iter = "100",
  min_iter = "30",
  tol = "1e-4",
  workers = "20"
))

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
previous_rhs_score_path <- app_resolve_path(args$previous_rhs_score_path, must_work = TRUE)
alpha <- as.numeric(args$alpha)
rho <- as.numeric(args$rho)
tau0 <- as.numeric(args$tau0)
max_iter <- as.integer(args$max_iter)
min_iter <- as.integer(args$min_iter)
tol <- as.numeric(args$tol)
workers <- as.integer(args$workers)
if (!is.finite(alpha) || alpha <= 0 || alpha >= 1) stop("--alpha must lie in (0, 1).", call. = FALSE)
if (!is.finite(rho) || rho <= 0 || rho >= 1) stop("--rho must lie in (0, 1).", call. = FALSE)
if (!is.finite(tau0) || tau0 <= 0) stop("--tau0 must be positive.", call. = FALSE)
if (!is.finite(max_iter) || max_iter < 1L) stop("--max_iter must be positive.", call. = FALSE)
if (!is.finite(min_iter) || min_iter < 1L) stop("--min_iter must be positive.", call. = FALSE)
if (min_iter > max_iter) stop("--min_iter cannot exceed --max_iter.", call. = FALSE)
if (!is.finite(tol) || tol < 0) stop("--tol must be finite and nonnegative.", call. = FALSE)
if (!is.finite(workers) || workers < 1L) stop("--workers must be positive.", call. = FALSE)

run_label <- as.character(args$run_label)[[1L]]
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) {
  stop("run_label must be path-safe.", call. = FALSE)
}
root <- app_path("local_trackers", "runtime_configs", run_label)
dirs <- file.path(root, c(
  "configs", "logs", "scores", "status", "tables", "objects", "figures",
  "traces", "coefficients", "warm_starts"
))
invisible(lapply(dirs, app_ensure_dir))

d1_n <- c(500L, 800L, 1000L, 1500L, 2000L, 2500L, 3000L, 4000L, 5000L)
d2_n <- c(250L, 500L, 750L, 1000L, 1500L, 2000L, 2500L)
geometries <- c(
  stats::setNames(as.list(d1_n), paste0("D1_n", d1_n)),
  stats::setNames(lapply(d2_n, function(n) c(n, n)), paste0("D2_n", d2_n, "x", d2_n))
)
lag_grid <- data.frame(
  lag_id = c("L360", "Y360_X180", "Y360_X360", "Y540_X180", "Y720_X180"),
  m = c(360L, 360L, 360L, 540L, 720L),
  output_lag_max = c(360L, 360L, 360L, 540L, 720L),
  covariate_lag_max = c(360L, 180L, 360L, 180L, 180L),
  stringsAsFactors = FALSE
)
dynamic_grid <- data.frame(
  dynamics_id = app_glofas_normal_part1_dynamics_label(alpha, rho),
  alpha = alpha,
  rho = rho,
  stringsAsFactors = FALSE
)
candidate_manifest <- app_glofas_normal_part1_candidate_manifest_from_axes(
  geometries = geometries,
  lag_grid = lag_grid,
  dynamic_grid = dynamic_grid,
  candidate_prefix = "part1fix",
  include_expensive_frontier = TRUE
)
candidate_manifest$candidate_id <- sprintf(
  "part1fix_%04d_%s__%s__a050_r090",
  seq_len(nrow(candidate_manifest)),
  candidate_manifest$geometry_id,
  candidate_manifest$lag_id
)
candidate_manifest$screen_role <- "fixed_alpha_rho_normal_rhs_vb"
candidate_manifest$warm_start_path <- file.path(root, "objects", paste0(candidate_manifest$candidate_id, "_ridge_warm_start.rds"))
candidate_manifest <- candidate_manifest[
  order(
    as.integer(candidate_manifest$D),
    match(as.character(candidate_manifest$lag_id), lag_grid$lag_id),
    as.integer(candidate_manifest$n_state_features)
  ),
  ,
  drop = FALSE
]
candidate_manifest$priority <- seq_len(nrow(candidate_manifest))

app_write_csv(candidate_manifest, file.path(root, "configs", "top10_ridge_candidates.csv"))
app_write_csv(candidate_manifest, file.path(root, "configs", "fixed_a050_r090_candidate_manifest.csv"))
writeLines(as.character(candidate_manifest$candidate_id), file.path(root, "configs", "warm_start_candidate_ids.txt"))

rhs_manifest <- cbind(
  data.frame(
    rhs_candidate_id = sprintf("normal_rhs_fixed_a050_r090_%04d_%s__tau1", seq_len(nrow(candidate_manifest)), candidate_manifest$candidate_id),
    rhs_tau0 = tau0,
    rhs_tau0_label = "tau1",
    rhs_max_iter = max_iter,
    rhs_min_iter = min_iter,
    rhs_tol = tol,
    rhs_update_every = 1L,
    rhs_freeze_tau_warmup_iters = 0L,
    rhs_min_tau_updates = 0L,
    warm_start_source = "rebuild_exact_ridge_from_usgs_only_design",
    stringsAsFactors = FALSE
  ),
  candidate_manifest
)
app_write_csv(rhs_manifest, file.path(root, "configs", "top10_rhs_tau0_manifest.csv"))
writeLines(as.character(rhs_manifest$rhs_candidate_id), file.path(root, "configs", "rhs_candidate_ids.txt"))

previous_scores <- app_read_csv(previous_rhs_score_path)
previous_scores$valid_mean_crps <- suppressWarnings(as.numeric(previous_scores$valid_mean_crps))
previous_best <- previous_scores[previous_scores$status == "completed" & is.finite(previous_scores$valid_mean_crps), , drop = FALSE]
previous_best <- previous_best[order(previous_best$valid_mean_crps), , drop = FALSE]
selection_summary <- data.frame(
  metric = c(
    "candidate_count", "rhs_fit_count", "alpha", "rho", "tau0",
    "max_iter", "min_iter", "tol", "workers_planned",
    "max_total_state_features", "D_values", "lag_ids",
    "previous_best_rhs_candidate", "previous_best_valid_mean_crps"
  ),
  value = c(
    nrow(candidate_manifest),
    nrow(rhs_manifest),
    alpha,
    rho,
    tau0,
    max_iter,
    min_iter,
    tol,
    workers,
    max(candidate_manifest$n_state_features),
    paste(sort(unique(candidate_manifest$D)), collapse = ";"),
    paste(lag_grid$lag_id, collapse = ";"),
    previous_best$rhs_candidate_id[[1L]] %||% NA_character_,
    sprintf("%.9f", previous_best$valid_mean_crps[[1L]] %||% NA_real_)
  ),
  stringsAsFactors = FALSE
)
app_write_csv(selection_summary, file.path(root, "configs", "fixed_a050_r090_selection_summary.csv"))
app_write_csv(selection_summary, file.path(root, "configs", "top10_rhs_selection_summary.csv"))

base_cfg <- app_read_config(base_config)
app_write_yaml(
  list(
    run_label = run_label,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    repo_root = app_repo_root(),
    git_head = app_git_sha(short = FALSE),
    base_config = base_config,
    base_config_sha256 = app_sha256_file(base_config),
    input_manifest = app_config_path(base_cfg, "input_manifest"),
    input_manifest_sha256 = app_sha256_file(app_config_path(base_cfg, "input_manifest")),
    cutoff_path = app_config_path(base_cfg, "cutoffs"),
    cutoff_sha256 = app_sha256_file(app_config_path(base_cfg, "cutoffs")),
    previous_rhs_score_path = previous_rhs_score_path,
    previous_rhs_score_sha256 = app_sha256_file(previous_rhs_score_path),
    candidate_manifest_sha256 = app_sha256_file(file.path(root, "configs", "fixed_a050_r090_candidate_manifest.csv")),
    rhs_manifest_sha256 = app_sha256_file(file.path(root, "configs", "top10_rhs_tau0_manifest.csv")),
    selection_summary_sha256 = app_sha256_file(file.path(root, "configs", "fixed_a050_r090_selection_summary.csv")),
    screen = list(
      scientific_scope = "USGS-only observed history up to cutoff",
      likelihood = "normal",
      prior = "regularized_horseshoe_rhs_vb",
      readout = "intercept_plus_reservoir_states_only",
      direct_readout_inputs = FALSE,
      selection_basis = "fixed alpha/rho broad capacity and lag screen",
      alpha = alpha,
      rho = rho,
      tau0 = tau0,
      d1_n = d1_n,
      d2_equal_layer_n = d2_n,
      max_total_state_features = max(candidate_manifest$n_state_features),
      lag_grid = split(lag_grid, seq_len(nrow(lag_grid))),
      total_rhs_fits = nrow(rhs_manifest),
      max_iter = max_iter,
      min_iter = min_iter,
      tol = tol,
      workers_planned = workers,
      trace_columns = c(
        "normal_rhs_partial_elbo",
        "normal_rhs_partial_elbo_delta",
        "normal_rhs_partial_elbo_relative_delta"
      ),
      elbo_accounting_label = "normal_rhs_partial_mean_field_accounting_log_precision_approx"
    )
  ),
  file.path(root, "configs", "run_manifest.yaml")
)
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))

cat(root, "\n")
