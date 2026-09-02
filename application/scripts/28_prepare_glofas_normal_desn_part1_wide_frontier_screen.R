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
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  run_label = paste0("glofas_normal_part1_wide_frontier_", format(Sys.time(), "%Y%m%d_%H%M%S")),
  current_reference_runtime_root = "local_trackers/runtime_configs/glofas_normal_part1_ridge_n300_1000_20260901",
  include_expensive_frontier = "true"
))

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
current_reference_runtime_root <- app_resolve_path(args$current_reference_runtime_root, must_work = TRUE)
base_cfg <- app_read_config(base_config)
manifest <- app_glofas_normal_part1_wide_frontier_manifest(
  include_expensive_frontier = app_as_bool(args$include_expensive_frontier)
)

run_label <- as.character(args$run_label)[[1L]]
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) {
  stop("run_label must be path-safe.", call. = FALSE)
}
root <- app_path("local_trackers", "runtime_configs", run_label)
dirs <- file.path(root, c("configs", "logs", "scores", "status", "tables", "objects", "figures"))
invisible(lapply(dirs, app_ensure_dir))

app_write_csv(manifest, file.path(root, "configs", "candidate_manifest.csv"))

axis_summary <- app_bind_rows_fill(list(
  data.frame(axis = "total", value = "candidate_count", n = nrow(manifest), stringsAsFactors = FALSE),
  data.frame(axis = "depth", value = paste0("D", sort(unique(manifest$D))), n = as.integer(table(factor(manifest$D, levels = sort(unique(manifest$D))))), stringsAsFactors = FALSE),
  data.frame(axis = "lag", value = names(table(manifest$lag_id)), n = as.integer(table(manifest$lag_id)), stringsAsFactors = FALSE),
  data.frame(axis = "alpha", value = names(table(manifest$alpha)), n = as.integer(table(manifest$alpha)), stringsAsFactors = FALSE),
  data.frame(axis = "rho", value = names(table(manifest$rho)), n = as.integer(table(manifest$rho)), stringsAsFactors = FALSE),
  data.frame(axis = "geometry", value = names(table(manifest$geometry_id)), n = as.integer(table(manifest$geometry_id)), stringsAsFactors = FALSE)
))
app_write_csv(axis_summary, file.path(root, "tables", "wide_frontier_axis_summary.csv"))

app_write_yaml(
  list(
    run_label = run_label,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    repo_root = app_repo_root(),
    git_head = app_git_sha(short = FALSE),
    base_config = base_config,
    base_config_sha256 = app_sha256_file(base_config),
    current_reference_runtime_root = current_reference_runtime_root,
    current_reference_manifest_sha256 = app_sha256_file(file.path(current_reference_runtime_root, "configs", "candidate_manifest.csv")),
    input_manifest = app_config_path(base_cfg, "input_manifest"),
    input_manifest_sha256 = app_sha256_file(app_config_path(base_cfg, "input_manifest")),
    cutoff_path = app_config_path(base_cfg, "cutoffs"),
    cutoff_sha256 = app_sha256_file(app_config_path(base_cfg, "cutoffs")),
    screen = list(
      likelihood = "normal",
      readout = "intercept_plus_reservoir_states_only",
      target = "historical_usgs_log1p_up_to_cutoff",
      stage = "part1_scaled_ridge_wide_frontier",
      rationale = paste(
        "Follow-up capacity-frontier screen after the n300-1000 Part 1 ridge",
        "screen showed a shallow-wide L360 alpha/rho cluster."
      )
    ),
    candidate_contract = list(
      total_candidates = nrow(manifest),
      workers_planned = 20L,
      direct_readout_inputs = FALSE,
      retained_fit_objects_by_default = FALSE,
      d1 = list(
        n = c(500L, 800L, 1000L, 1500L, 2000L, 3000L, 4000L, 5000L),
        lags = c("L360", "Y360_X180", "Y360_X540", "Y540_X360", "Y720_X360"),
        alpha = c(0.20, 0.30, 0.40, 0.50, 0.60),
        rho = c(0.90, 0.95, 0.99)
      ),
      d2 = list(
        n_pairs = c("500;500", "800;800", "1000;1000", "1500;1500", "2500;2500"),
        lags = c("L360", "Y360_X180", "Y540_X360"),
        alpha = c(0.20, 0.40, 0.60),
        rho = c(0.95, 0.99)
      )
    )
  ),
  file.path(root, "configs", "run_manifest.yaml")
)
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))

cat(root, "\n")
