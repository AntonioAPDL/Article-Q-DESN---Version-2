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
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))

args <- app_parse_args(list(
  base_config = "local_trackers/runtime_configs/glofas_fr09_shared_reference_input_tau1em1_p50_20260829/candidate/config_p50.yaml",
  run_label = paste0("glofas_normal_part2_ridge_input_arch_screen_", format(Sys.time(), "%Y%m%d_%H%M%S")),
  candidate_prefix = "part2ridge",
  validation_n = ""
))

base_config <- app_resolve_path(args$base_config, must_work = TRUE)
base_cfg <- app_read_config(base_config)
validation_n <- suppressWarnings(as.integer(args$validation_n))
if (!is.finite(validation_n)) validation_n <- NULL
manifest <- app_glofas_normal_part2_ridge_candidate_manifest(
  candidate_prefix = args$candidate_prefix,
  validation_n = validation_n
)

run_label <- as.character(args$run_label)[[1L]]
if (!nzchar(run_label) || grepl("[^A-Za-z0-9_.-]", run_label)) {
  stop("run_label must be path-safe.", call. = FALSE)
}
root <- app_path("local_trackers", "runtime_configs", run_label)
dirs <- file.path(root, c("configs", "logs", "scores", "status", "tables", "figures"))
invisible(lapply(dirs, app_ensure_dir))

app_write_csv(manifest, file.path(root, "configs", "candidate_manifest.csv"))
writeLines(as.character(manifest$candidate_id), file.path(root, "configs", "candidate_ids.txt"))
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
    screen = list(
      stage = "part2_historical_two_desn_scaled_ridge",
      likelihood = "normal",
      target = "historical_paired_usgs_and_glofas_up_to_cutoff",
      reference_block = app_glofas_normal_part2_fixed_reference_winner(),
      discrepancy_block = list(
        fixed_m = 360L,
        output_lags = "1:360",
        covariate_lags_when_enabled = "0:180",
        auxiliary_lags_when_enabled = "1:360",
        input_contracts = app_glofas_normal_part2_input_contracts(),
        geometries = app_glofas_normal_part2_discrepancy_geometry_grid(),
        dynamics = app_glofas_normal_part2_discrepancy_dynamic_grid()
      ),
      scoring = list(
        primary = "corrected_valid_mean_crps",
        discrepancy_diagnostic = "discrepancy_valid_mean_crps",
        guardrails = c("corrected_valid_mae", "corrected_valid_rmse", "last50/last200 windows"),
        readout = "intercept_plus_reservoir_states_only"
      ),
      candidates = nrow(manifest)
    )
  ),
  file.path(root, "configs", "run_manifest.yaml")
)
app_write_git_state(file.path(root, "configs", "git_state.txt"))
app_write_session_info(file.path(root, "configs", "session_info.txt"))

cat(root, "\n")
