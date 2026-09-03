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
  worker_index = "",
  total_workers = "",
  spectral_radius_exact_max_n = "256",
  retain_detail = "false"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
options(app_qdesn_spectral_radius_exact_max_n = as.integer(args$spectral_radius_exact_max_n))

manifest <- app_read_csv(file.path(runtime_root, "configs", "candidate_manifest.csv"))
candidate_ids <- as.character(manifest$candidate_id)
single_id <- as.character(args$candidate_id %||% "")[[1L]]
if (nzchar(single_id)) {
  candidate_ids <- single_id
} else {
  worker_index <- suppressWarnings(as.integer(args$worker_index))
  total_workers <- suppressWarnings(as.integer(args$total_workers))
  if (!is.finite(worker_index) || !is.finite(total_workers) ||
      worker_index < 1L || total_workers < 1L || worker_index > total_workers) {
    stop("Use either --candidate_id or finite --worker_index/--total_workers.", call. = FALSE)
  }
  owned <- ((seq_along(candidate_ids) - 1L) %% total_workers) + 1L == worker_index
  candidate_ids <- candidate_ids[owned]
}
if (!length(candidate_ids)) {
  cat("No candidates assigned to this worker.\n")
  quit(save = "no", status = 0L)
}

run_manifest <- app_read_yaml(file.path(runtime_root, "configs", "run_manifest.yaml"))
base_cfg <- app_read_config(run_manifest$base_config)

reference_caches <- list()
get_reference_cache <- function(row) {
  key <- app_glofas_normal_part2_reference_cache_key(row)
  if (is.null(reference_caches[[key]])) {
    reference_caches[[key]] <<- app_glofas_normal_part2_prepare_reference_cache(
      base_cfg = base_cfg,
      candidate_row = row,
      panel_bundle = NULL,
      include_ridge_fit = TRUE
    )
  }
  reference_caches[[key]]
}

retain_detail <- app_as_bool(args$retain_detail)
for (candidate_id in candidate_ids) {
  row <- manifest[manifest$candidate_id == candidate_id, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop(sprintf("Expected one manifest row for %s.", candidate_id), call. = FALSE)
  }
  done <- file.path(runtime_root, "status", paste0(candidate_id, ".done"))
  failed <- file.path(runtime_root, "status", paste0(candidate_id, ".failed"))
  running <- file.path(runtime_root, "status", paste0(candidate_id, ".running"))
  summary_path <- file.path(runtime_root, "scores", paste0(candidate_id, "_summary.csv"))
  detail_path <- file.path(runtime_root, "scores", paste0(candidate_id, "_validation_detail.csv"))
  if (file.exists(done) && file.exists(summary_path)) {
    cat(sprintf("%s already completed\n", candidate_id))
    next
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

  started <- Sys.time()
  result <- tryCatch(
    app_glofas_normal_part2_score_ridge_candidate(
      base_cfg = base_cfg,
      candidate_row = row,
      panel_bundle = NULL,
      reference_cache = get_reference_cache(row)
    ),
    error = function(e) e
  )
  if (inherits(result, "error")) {
    failure <- app_glofas_normal_part2_failure_row(row, result, started = started)
    app_write_csv(failure, summary_path)
    writeLines(conditionMessage(result), failed)
    if (file.exists(running)) unlink(running)
    cat(sprintf("%s failed: %s\n", candidate_id, conditionMessage(result)))
    next
  }

  app_write_csv(result$summary, summary_path)
  if (isTRUE(retain_detail)) app_write_csv(result$detail, detail_path)
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), done)
  if (file.exists(running)) unlink(running)
  cat(sprintf("%s completed\n", candidate_id))
}
