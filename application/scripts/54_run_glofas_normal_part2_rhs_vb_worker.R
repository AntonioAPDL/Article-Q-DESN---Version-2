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
  rhs_candidate_id = "",
  force = "false"
))

runtime_root <- app_resolve_path(args$runtime_root, must_work = TRUE)
rhs_candidate_id <- as.character(args$rhs_candidate_id)[[1L]]
if (!nzchar(rhs_candidate_id)) stop("--rhs_candidate_id is required.", call. = FALSE)

manifest <- app_read_csv(file.path(runtime_root, "configs", "part2_rhs_tau0_manifest.csv"))
row <- manifest[manifest$rhs_candidate_id == rhs_candidate_id, , drop = FALSE]
if (nrow(row) != 1L) stop(sprintf("Expected one Part 2 RHS manifest row for %s.", rhs_candidate_id), call. = FALSE)

done <- file.path(runtime_root, "status", paste0(rhs_candidate_id, ".done"))
failed <- file.path(runtime_root, "status", paste0(rhs_candidate_id, ".failed"))
running <- file.path(runtime_root, "status", paste0(rhs_candidate_id, ".running"))
summary_path <- file.path(runtime_root, "scores", paste0(rhs_candidate_id, "_rhs_summary.csv"))
detail_path <- file.path(runtime_root, "scores", paste0(rhs_candidate_id, "_rhs_validation_detail.csv"))
trace_path <- file.path(runtime_root, "traces", paste0(rhs_candidate_id, "_rhs_trace.csv"))
coef_path <- file.path(runtime_root, "coefficients", paste0(rhs_candidate_id, "_rhs_coefficients.csv"))
activity_path <- file.path(runtime_root, "coefficients", paste0(rhs_candidate_id, "_rhs_activity.csv"))
compact_path <- file.path(runtime_root, "objects", paste0(rhs_candidate_id, "_normal_part2_rhs_compact.rds"))
warm_path <- as.character(row$warm_start_path[[1L]])

if (!app_as_bool(args$force) && file.exists(done) && file.exists(summary_path)) {
  cat(sprintf("%s already completed\n", rhs_candidate_id))
  quit(save = "no", status = 0L)
}
if (!file.exists(warm_path)) {
  stop(sprintf("Missing ridge warm start for %s: %s", rhs_candidate_id, warm_path), call. = FALSE)
}
if (file.exists(failed)) unlink(failed)
writeLines(
  c(
    sprintf("rhs_candidate_id=%s", rhs_candidate_id),
    sprintf("started_at=%s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    sprintf("pid=%s", Sys.getpid())
  ),
  running
)

run_manifest <- app_read_yaml(file.path(runtime_root, "configs", "run_manifest.yaml"))
base_cfg <- app_read_config(run_manifest$base_config)
warm <- readRDS(warm_path)
started <- Sys.time()
result <- tryCatch(
  app_glofas_normal_part2_score_rhs_candidate(
    base_cfg = base_cfg,
    rhs_row = row,
    panel_bundle = NULL,
    warm_start = warm
  ),
  error = function(e) e
)
if (inherits(result, "error")) {
  failure <- app_glofas_normal_part2_failure_row(row, result, started = started)
  app_write_csv(failure, summary_path)
  writeLines(conditionMessage(result), failed)
  if (file.exists(running)) unlink(running)
  quit(save = "no", status = 1L)
}

app_write_csv(result$summary, summary_path)
app_write_csv(result$detail, detail_path)
app_write_csv(result$trace, trace_path)
app_write_csv(result$activity, activity_path)
app_write_csv(result$coefficients, coef_path)

reference_fit <- result$reference_fit
discrepancy_fit <- result$discrepancy_fit
reference_fit$beta_cov <- NULL
reference_fit$precision <- NULL
reference_fit$precision_chol <- NULL
discrepancy_fit$beta_cov <- NULL
discrepancy_fit$precision <- NULL
discrepancy_fit$precision_chol <- NULL
saveRDS(
  list(
    summary = result$summary,
    reference_fit = reference_fit,
    discrepancy_fit = discrepancy_fit,
    trace_path = trace_path,
    coefficient_path = coef_path,
    activity_path = activity_path,
    warm_start_path = warm_path,
    warm_start_sha256 = app_sha256_file(warm_path)
  ),
  compact_path,
  version = 2L
)
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), done)
if (file.exists(running)) unlink(running)
cat(sprintf("%s completed\n", rhs_candidate_id))
