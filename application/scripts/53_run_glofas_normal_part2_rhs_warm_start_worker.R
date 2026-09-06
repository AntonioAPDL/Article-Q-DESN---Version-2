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
source(app_path("application/R/glofas_normal_desn_part1_screening.R"))
source(app_path("application/R/glofas_normal_desn_part2_bridge.R"))

args <- app_parse_args(list(
  runtime_root = "",
  candidate_id = "",
  force = "false"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
candidate_id <- as.character(args$candidate_id)[[1L]]
if (!nzchar(candidate_id)) stop("--candidate_id is required.", call. = FALSE)

top <- app_read_csv(file.path(runtime_root, "configs", "top_ridge_candidates.csv"))
row <- top[top$candidate_id == candidate_id, , drop = FALSE]
if (nrow(row) != 1L) stop(sprintf("Expected one top-ridge row for %s.", candidate_id), call. = FALSE)

done <- file.path(runtime_root, "status", paste0(candidate_id, ".warm.done"))
failed <- file.path(runtime_root, "status", paste0(candidate_id, ".warm.failed"))
running <- file.path(runtime_root, "status", paste0(candidate_id, ".warm.running"))
warm_path <- as.character(row$warm_start_path[[1L]])

if (!app_as_bool(args$force) && file.exists(done) && file.exists(warm_path)) {
  cat(sprintf("%s warm start already completed\n", candidate_id))
  quit(save = "no", status = 0L)
}
if (file.exists(failed)) unlink(failed)
writeLines(
  c(
    sprintf("candidate_id=%s", candidate_id),
    sprintf("started_at=%s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    sprintf("pid=%s", Sys.getpid())
  ),
  running
)

run_manifest <- app_read_yaml(file.path(runtime_root, "configs", "run_manifest.yaml"))
base_cfg <- app_read_config(run_manifest$base_config)
started <- Sys.time()
result <- tryCatch(
  app_glofas_normal_part2_fit_ridge_components(
    base_cfg = base_cfg,
    candidate_row = row,
    panel_bundle = NULL,
    reference_cache = NULL
  ),
  error = function(e) e
)
if (inherits(result, "error")) {
  writeLines(conditionMessage(result), failed)
  app_write_csv(
    data.frame(
      candidate_id = candidate_id,
      status = "failed",
      error_message = conditionMessage(result),
      runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      stringsAsFactors = FALSE
    ),
    file.path(runtime_root, "scores", paste0(candidate_id, "_warm_start_summary.csv"))
  )
  if (file.exists(running)) unlink(running)
  quit(save = "no", status = 1L)
}

app_ensure_dir(dirname(warm_path))
saveRDS(result$warm_start, warm_path, version = 2L)
app_glofas_normal_part2_validate_warm_start(
  result$warm_start,
  design = result$design,
  train_idx = result$split$train_idx
)
app_write_csv(
  data.frame(
    candidate_id = candidate_id,
    status = "completed",
    warm_start_path = warm_path,
    warm_start_sha256 = app_sha256_file(warm_path),
    runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
    stringsAsFactors = FALSE
  ),
  file.path(runtime_root, "scores", paste0(candidate_id, "_warm_start_summary.csv"))
)
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), done)
if (file.exists(running)) unlink(running)
cat(sprintf("%s warm start completed\n", candidate_id))
