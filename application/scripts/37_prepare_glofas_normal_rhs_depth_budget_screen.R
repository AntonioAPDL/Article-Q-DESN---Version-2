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
  run_label = "glofas_normal_rhs_depth_budget_20260902",
  previous_rhs_score_path = "local_trackers/runtime_configs/glofas_normal_rhs_top10_vb_20260901/tables/normal_rhs_scores_latest.csv",
  alpha = "0.5",
  rho = "0.9",
  tau0_values = "1,1e-3,1e-12,1e-24",
  max_iter = "100",
  min_iter = "30",
  tol = "1e-4",
  workers = "20"
))

parse_numeric_values <- function(x, label) {
  x <- gsub("[[:space:]]+", "", as.character(x)[[1L]])
  out <- suppressWarnings(as.numeric(strsplit(x, "[,;|]", perl = TRUE)[[1L]]))
  if (!length(out) || any(!is.finite(out))) {
    stop(sprintf("%s must contain finite numeric values.", label), call. = FALSE)
  }
  out
}

tau_label <- function(x) {
  x <- as.numeric(x)
  if (!is.finite(x) || x <= 0) stop("tau0 values must be positive.", call. = FALSE)
  if (abs(x - 1) < .Machine$double.eps) return("tau1")
  sx <- format(x, scientific = TRUE, digits = 15)
  sx <- sub("e\\+?0*", "e", sx)
  sx <- sub("e-0*", "em", sx)
  sx <- gsub("\\.", "p", sx)
  paste0("tau", sx)
}

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
previous_rhs_score_path <- app_resolve_path(args$previous_rhs_score_path, must_work = TRUE)
alpha <- as.numeric(args$alpha)
rho <- as.numeric(args$rho)
tau0_values <- parse_numeric_values(args$tau0_values, "tau0_values")
max_iter <- as.integer(args$max_iter)
min_iter <- as.integer(args$min_iter)
tol <- as.numeric(args$tol)
workers <- as.integer(args$workers)
if (!is.finite(alpha) || alpha <= 0 || alpha >= 1) stop("--alpha must lie in (0, 1).", call. = FALSE)
if (!is.finite(rho) || rho <= 0 || rho >= 1) stop("--rho must lie in (0, 1).", call. = FALSE)
if (any(tau0_values <= 0)) stop("--tau0_values must be positive.", call. = FALSE)
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

geometries <- app_glofas_normal_part1_depth_budget_geometries(
  depth_values = 2:10,
  total_state_budget = 5000L,
  anchor_first_layer = 3000L,
  extra_state_budget = 3000L,
  include_reference = TRUE
)
lag_grid <- data.frame(
  lag_id = "Y360_X180",
  m = 360L,
  output_lag_max = 360L,
  covariate_lag_max = 180L,
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
  candidate_prefix = "part1depth",
  include_expensive_frontier = TRUE
)
candidate_manifest$geometry_family <- ifelse(
  grepl("_reference$", candidate_manifest$geometry_id),
  "reference",
  ifelse(grepl("_budget5000_equal$", candidate_manifest$geometry_id),
    "budget5000_equal",
    "anchor3000_extra3000"
  )
)
candidate_manifest <- candidate_manifest[
  order(
    match(candidate_manifest$geometry_family, c("reference", "budget5000_equal", "anchor3000_extra3000")),
    as.integer(candidate_manifest$D),
    candidate_manifest$geometry_id
  ),
  ,
  drop = FALSE
]
candidate_manifest$candidate_id <- sprintf(
  "part1depth_%04d_%s__Y360_X180__a050_r090",
  seq_len(nrow(candidate_manifest)),
  candidate_manifest$geometry_id
)
candidate_manifest$screen_role <- "depth_budget_and_anchor_extension_normal_rhs_vb"
candidate_manifest$warm_start_path <- file.path(root, "objects", paste0(candidate_manifest$candidate_id, "_ridge_warm_start.rds"))
candidate_manifest$priority <- seq_len(nrow(candidate_manifest))
rownames(candidate_manifest) <- NULL

app_write_csv(candidate_manifest, file.path(root, "configs", "top10_ridge_candidates.csv"))
app_write_csv(candidate_manifest, file.path(root, "configs", "depth_budget_candidate_manifest.csv"))
writeLines(as.character(candidate_manifest$candidate_id), file.path(root, "configs", "warm_start_candidate_ids.txt"))

rhs_rows <- vector("list", nrow(candidate_manifest) * length(tau0_values))
k <- 0L
for (i in seq_len(nrow(candidate_manifest))) {
  for (tau0 in tau0_values) {
    k <- k + 1L
    label <- tau_label(tau0)
    rhs_rows[[k]] <- cbind(
      data.frame(
        rhs_candidate_id = sprintf(
          "normal_rhs_depth_%04d_%s__%s",
          k,
          candidate_manifest$candidate_id[[i]],
          label
        ),
        rhs_tau0 = tau0,
        rhs_tau0_label = label,
        rhs_max_iter = max_iter,
        rhs_min_iter = min_iter,
        rhs_tol = tol,
        rhs_update_every = 1L,
        rhs_freeze_tau_warmup_iters = 0L,
        rhs_min_tau_updates = 0L,
        warm_start_source = "rebuild_exact_ridge_from_usgs_only_design",
        practical_crps_equivalence = 1.0e-4,
        stringsAsFactors = FALSE
      ),
      candidate_manifest[i, , drop = FALSE]
    )
  }
}
rhs_manifest <- app_bind_rows_fill(rhs_rows)
app_write_csv(rhs_manifest, file.path(root, "configs", "top10_rhs_tau0_manifest.csv"))
app_write_csv(rhs_manifest, file.path(root, "configs", "depth_budget_rhs_manifest.csv"))
writeLines(as.character(rhs_manifest$rhs_candidate_id), file.path(root, "configs", "rhs_candidate_ids.txt"))

previous_scores <- app_read_csv(previous_rhs_score_path)
previous_scores$valid_mean_crps <- suppressWarnings(as.numeric(previous_scores$valid_mean_crps))
previous_best <- previous_scores[
  previous_scores$status == "completed" & is.finite(previous_scores$valid_mean_crps),
  ,
  drop = FALSE
]
previous_best <- previous_best[order(previous_best$valid_mean_crps), , drop = FALSE]
selection_summary <- data.frame(
  metric = c(
    "geometry_count", "rhs_fit_count", "alpha", "rho", "tau0_values",
    "max_iter", "min_iter", "tol", "workers_planned",
    "lag_id", "output_lag_max", "covariate_lag_max",
    "state_budget_equal_family", "state_budget_anchor_family",
    "depth_values", "previous_best_rhs_candidate", "previous_best_valid_mean_crps",
    "practical_crps_equivalence"
  ),
  value = c(
    nrow(candidate_manifest),
    nrow(rhs_manifest),
    alpha,
    rho,
    paste(format(tau0_values, scientific = TRUE), collapse = ";"),
    max_iter,
    min_iter,
    tol,
    workers,
    lag_grid$lag_id[[1L]],
    lag_grid$output_lag_max[[1L]],
    lag_grid$covariate_lag_max[[1L]],
    "sum(n)=5000 for D=2..10",
    "n1=3000 plus sum(n2:D)=3000 for D=2..10",
    paste(2:10, collapse = ";"),
    previous_best$rhs_candidate_id[[1L]] %||% NA_character_,
    sprintf("%.9f", previous_best$valid_mean_crps[[1L]] %||% NA_real_),
    "1e-4"
  ),
  stringsAsFactors = FALSE
)
app_write_csv(selection_summary, file.path(root, "configs", "depth_budget_selection_summary.csv"))
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
    candidate_manifest_sha256 = app_sha256_file(file.path(root, "configs", "depth_budget_candidate_manifest.csv")),
    rhs_manifest_sha256 = app_sha256_file(file.path(root, "configs", "depth_budget_rhs_manifest.csv")),
    selection_summary_sha256 = app_sha256_file(file.path(root, "configs", "depth_budget_selection_summary.csv")),
    screen = list(
      scientific_scope = "USGS-only observed history up to cutoff",
      likelihood = "normal",
      prior = "regularized_horseshoe_rhs_vb",
      readout = "intercept_plus_reservoir_states_only",
      direct_readout_inputs = FALSE,
      purpose = "final depth-screen for Part 1 before moving to the historical two-DESN Part 2 model",
      fixed_axes = list(
        alpha = alpha,
        rho = rho,
        lag_id = lag_grid$lag_id[[1L]],
        output_lags = "1:360",
        covariate_lags = "0:180",
        tau0_values = as.list(tau0_values)
      ),
      geometry_families = list(
        reference = "D=1, n=3000",
        equal_state_budget = "D=2..10 with sum(n)=5000",
        anchored_extension = "D=2..10 with n1=3000 and sum(n2:D)=3000"
      ),
      total_geometries = nrow(candidate_manifest),
      total_rhs_fits = nrow(rhs_manifest),
      max_iter = max_iter,
      min_iter = min_iter,
      tol = tol,
      workers_planned = workers,
      practical_crps_equivalence = 1.0e-4
    )
  ),
  file.path(root, "configs", "run_manifest.yaml")
)
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))

cat(root, "\n")
