#!/usr/bin/env Rscript

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
repo_root <- if (!is.na(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))

args <- app_parse_args(list(
  registry = "",
  output_dir = "",
  preflight_dir = "",
  scenario_ids = "",
  tier = "calibration",
  n_replicates = "5",
  seed_base = "",
  simulated_length = "",
  washout_length = "",
  train_length = "",
  test_length = "",
  vb_max_iter = "240",
  adaptive_vb_max_iter_grid = "240,360",
  refit_stride = "20",
  forecast_origin_stride = "10",
  max_origins_per_scenario = "40",
  article_output_dir = "",
  fallback_calibration_output_dir = "",
  execute = "false",
  overwrite = "false"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_csv <- function(x) {
  out <- trimws(strsplit(as.character(x), ",", fixed = TRUE)[[1L]])
  out[nzchar(out)]
}

parse_optional_int <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(NULL)
  out <- suppressWarnings(as.integer(x))
  if (is.na(out)) stop(sprintf("Expected integer, got '%s'.", x), call. = FALSE)
  out
}

parse_int <- function(x) {
  out <- parse_optional_int(x)
  if (is.null(out)) stop("Missing required integer argument.", call. = FALSE)
  out
}

parse_optional_number_or_inf <- function(x) {
  x <- as.character(x)[[1L]]
  if (!nzchar(x)) return(NULL)
  out <- suppressWarnings(as.numeric(x))
  if (is.na(out)) stop(sprintf("Expected numeric or Inf, got '%s'.", x), call. = FALSE)
  out
}

parse_int_grid <- function(x) {
  out <- suppressWarnings(as.integer(parse_csv(x)))
  out <- out[is.finite(out) & out > 0L]
  if (!length(out)) stop("adaptive-vb-max-iter-grid must contain at least one positive integer.", call. = FALSE)
  out
}

out_dir <- if (nzchar(as.character(arg_value("output_dir")))) {
  as.character(arg_value("output_dir"))
} else {
  app_joint_qvp_default_synthetic_dgp_forecast_calibration_contract_dir()
}
prep_dir <- if (nzchar(as.character(arg_value("preflight_dir")))) as.character(arg_value("preflight_dir")) else NULL
registry_path <- if (nzchar(as.character(arg_value("registry")))) {
  as.character(arg_value("registry"))
} else {
  app_joint_qvp_default_synthetic_dgp_registry_path()
}
scenario_ids <- parse_csv(arg_value("scenario_ids"))
article_output_dir <- if (nzchar(as.character(arg_value("article_output_dir")))) {
  as.character(arg_value("article_output_dir"))
} else {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_article_candidate_20260702")
}
fallback_calibration_output_dir <- if (nzchar(as.character(arg_value("fallback_calibration_output_dir")))) {
  as.character(arg_value("fallback_calibration_output_dir"))
} else {
  app_path("application/cache/joint_qvp_synthetic_dgp_forecast_calibration_phase4_calibration_contract_followup_20260702")
}

tier <- as.character(arg_value("tier"))[[1L]]
n_replicates <- parse_int(arg_value("n_replicates"))
seed_base <- parse_optional_int(arg_value("seed_base"))
simulated_length <- parse_optional_int(arg_value("simulated_length"))
washout_length <- parse_optional_int(arg_value("washout_length"))
train_length <- parse_optional_int(arg_value("train_length"))
test_length <- parse_optional_int(arg_value("test_length"))
vb_max_iter <- parse_int(arg_value("vb_max_iter"))
adaptive_grid <- parse_int_grid(arg_value("adaptive_vb_max_iter_grid"))
refit_stride <- parse_int(arg_value("refit_stride"))
forecast_origin_stride <- parse_int(arg_value("forecast_origin_stride"))
max_origins <- parse_optional_number_or_inf(arg_value("max_origins_per_scenario"))
if (is.null(max_origins)) max_origins <- 40
execute <- app_as_bool(arg_value("execute"))
overwrite <- app_as_bool(arg_value("overwrite"))

if (execute && dir.exists(out_dir) && length(list.files(out_dir, all.files = FALSE, no.. = TRUE)) && !overwrite) {
  stop(
    "Output directory already exists and is non-empty. Use --overwrite true only after confirming it is not an artifact you need to preserve: ",
    out_dir,
    call. = FALSE
  )
}

prep <- app_joint_qvp_prepare_synthetic_dgp_forecast_contract_calibration_rerun(
  out_dir = out_dir,
  prep_dir = prep_dir,
  registry_path = registry_path,
  scenario_ids = if (length(scenario_ids)) scenario_ids else NULL,
  tier = tier,
  n_replicates = n_replicates,
  seed_base = seed_base,
  simulated_length = simulated_length,
  washout_length = washout_length,
  train_length = train_length,
  test_length = test_length,
  vb_max_iter = vb_max_iter,
  adaptive_vb_max_iter_grid = adaptive_grid,
  refit_stride = refit_stride,
  forecast_origin_stride = forecast_origin_stride,
  max_origins_per_scenario = max_origins,
  article_output_dir = article_output_dir,
  fallback_calibration_output_dir = fallback_calibration_output_dir
)

if (!all(prep$preflight$status == "pass")) {
  failed <- prep$preflight$check_name[prep$preflight$status != "pass"]
  stop("Contract calibration preflight failed: ", paste(failed, collapse = ", "), call. = FALSE)
}

cat(sprintf("Joint-QVP contract calibration preflight written to %s\n", prep$prep_dir))
cat(sprintf("Planned calibration output: %s\n", prep$out_dir))
cat(sprintf("Replicated registry rows: %s\n", nrow(prep$calibration_registry)))
cat(sprintf("Expected forecast origins: %s\n", prep$plan$expected_forecast_origin_rows[[1L]]))
cat("Launch command:\n")
cat(prep$commands$command[prep$commands$step_id == "phase4_contract_calibration"], "\n")

if (!execute) {
  cat("Execution skipped. Re-run with --execute true to launch calibration and audits.\n")
  quit(save = "no", status = 0L)
}

cat("Launching full contract calibration campaign...\n")
calibration <- app_joint_qvp_run_synthetic_dgp_forecast_calibration(
  out_dir = out_dir,
  registry_path = registry_path,
  scenario_ids = if (length(scenario_ids)) scenario_ids else NULL,
  tier = tier,
  n_replicates = n_replicates,
  seed_base = seed_base,
  simulated_length = simulated_length,
  washout_length = washout_length,
  train_length = train_length,
  test_length = test_length,
  vb_max_iter = vb_max_iter,
  adaptive_vb_max_iter_grid = adaptive_grid,
  refit_stride = refit_stride,
  forecast_origin_stride = forecast_origin_stride,
  max_origins_per_scenario = max_origins
)

readiness <- app_joint_qvp_audit_synthetic_dgp_forecast_calibration(
  phase4_dir = calibration$out_dir,
  out_dir = file.path(calibration$out_dir, "phase4b_readiness_audit"),
  article_output_dir = article_output_dir,
  fallback_calibration_output_dir = fallback_calibration_output_dir
)

crossing <- app_joint_qvp_audit_synthetic_dgp_forecast_crossings(
  artifact_dir = calibration$out_dir,
  out_dir = file.path(calibration$out_dir, "phase4c_crossing_audit")
)

postrun <- data.frame(
  phase4_dir = app_prefer_repo_relative_path(calibration$out_dir),
  phase3_dir = app_prefer_repo_relative_path(calibration$phase3_out_dir),
  phase4_gate = calibration$forecast_calibration_assessment$gate_status[[1L]],
  phase4b_gate = readiness$calibration_readiness_summary$gate_status[[1L]],
  phase4b_recommendation = readiness$article_candidate_recommendation$recommendation_status[[1L]],
  phase4c_gate = crossing$crossing_remediation_recommendation$gate_status[[1L]],
  phase4c_recommendation = crossing$crossing_remediation_recommendation$recommendation_status[[1L]],
  contract_crossing_pairs = crossing$crossing_remediation_recommendation$contract_crossing_pairs[[1L]],
  raw_crossing_pairs = crossing$crossing_remediation_recommendation$raw_crossing_pairs[[1L]],
  mean_vb_max_iter_rate = readiness$calibration_readiness_summary$mean_vb_max_iter_rate[[1L]],
  runtime_total_sec = readiness$calibration_readiness_summary$runtime_total_sec[[1L]],
  recommended_next_command = readiness$article_candidate_recommendation$recommended_next_command[[1L]],
  stringsAsFactors = FALSE
)
postrun_path <- app_joint_qvp_write_csv(postrun, file.path(prep$prep_dir, "contract_rerun_postrun_summary.csv"))
manifest_paths <- file.path(prep$prep_dir, c(
  "contract_rerun_plan.csv",
  "contract_rerun_commands.csv",
  "contract_rerun_preflight.csv",
  "expected_artifacts.csv",
  "calibration_registry_preview.csv",
  "provenance.csv",
  "README.md",
  "contract_rerun_postrun_summary.csv"
))
manifest <- data.frame(
  label = sub("\\.csv$|\\.md$", "", basename(manifest_paths)),
  relative_path = basename(manifest_paths),
  size_bytes = as.numeric(file.info(manifest_paths)$size),
  sha256 = vapply(manifest_paths, app_sha256_file, character(1L)),
  stringsAsFactors = FALSE
)
manifest_path <- app_joint_qvp_write_csv(manifest, file.path(prep$prep_dir, "artifact_manifest.csv"))

cat(sprintf("Full contract calibration written to %s\n", calibration$out_dir))
cat(sprintf("Phase 4b readiness audit: %s\n", readiness$out_dir))
cat(sprintf("Phase 4c crossing audit: %s\n", crossing$out_dir))
cat(sprintf("Postrun summary: %s\n", postrun_path))
cat(sprintf("Preflight/postrun manifest: %s\n", manifest_path))
cat(sprintf("Contract crossing pairs: %s\n", postrun$contract_crossing_pairs[[1L]]))
cat(sprintf("Raw crossing pairs: %s\n", postrun$raw_crossing_pairs[[1L]]))
cat(sprintf("Readiness recommendation: %s\n", postrun$phase4b_recommendation[[1L]]))
