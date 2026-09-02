#!/usr/bin/env Rscript

Sys.setenv(
  OMP_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  VECLIB_MAXIMUM_THREADS = "1",
  NUMEXPR_NUM_THREADS = "1"
)

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
source(app_path("application/R/glofas_structural_normal_dlm.R"))
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))

args <- app_parse_args(list(
  runtime_root = "",
  candidate_id = "",
  spectral_radius_exact_max_n = "256",
  force = "false"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
candidate_id <- as.character(args$candidate_id)[[1L]]
if (!nzchar(candidate_id)) stop("--candidate_id is required.", call. = FALSE)
options(app_qdesn_spectral_radius_exact_max_n = as.integer(args$spectral_radius_exact_max_n))

top10 <- app_read_csv(file.path(runtime_root, "configs", "top10_ridge_candidates.csv"))
row <- top10[top10$candidate_id == candidate_id, , drop = FALSE]
if (nrow(row) != 1L) stop(sprintf("Expected one top10 row for %s.", candidate_id), call. = FALSE)

done <- file.path(runtime_root, "status", paste0(candidate_id, ".warm.done"))
failed <- file.path(runtime_root, "status", paste0(candidate_id, ".warm.failed"))
running <- file.path(runtime_root, "status", paste0(candidate_id, ".warm.running"))
warm_path <- as.character(row$warm_start_path[[1L]])
summary_path <- file.path(runtime_root, "warm_starts", paste0(candidate_id, "_warm_start_summary.csv"))
if (!app_as_bool(args$force) && file.exists(done) && file.exists(warm_path) && file.exists(summary_path)) {
  cat(sprintf("%s warm start already completed\n", candidate_id))
  quit(save = "no", status = 0L)
}
if (file.exists(failed)) unlink(failed)
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), running)

run_manifest <- app_read_yaml(file.path(runtime_root, "configs", "run_manifest.yaml"))
base_cfg <- app_read_config(run_manifest$base_config)
panel_bundle <- app_glofas_normal_part1_prepare_panel(base_cfg)

started <- Sys.time()
result <- tryCatch(
  app_glofas_normal_part1_rebuild_ridge_warm_start(
    base_cfg = base_cfg,
    candidate_row = row,
    panel_bundle = panel_bundle,
    hash_design = TRUE
  ),
  error = function(e) e
)
if (inherits(result, "error")) {
  failure <- app_glofas_normal_part1_failure_row(row, result, started = started)
  app_write_csv(failure, summary_path)
  writeLines(conditionMessage(result), failed)
  if (file.exists(running)) unlink(running)
  quit(save = "no", status = 1L)
}

app_glofas_normal_part1_save_ridge_warm_start(result, warm_path)
summary <- result$summary
summary$warm_start_path <- warm_path
summary$warm_start_sha256 <- app_sha256_file(warm_path)
summary$runtime_seconds <- as.numeric(difftime(Sys.time(), started, units = "secs"))
app_write_csv(summary, summary_path)
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), done)
if (file.exists(running)) unlink(running)
cat(sprintf("%s warm start completed\n", candidate_id))
