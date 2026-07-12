repo_root <- if (exists("app_repo_root", mode = "function")) {
  app_repo_root()
} else if (dir.exists(file.path(getwd(), "application/R"))) {
  normalizePath(getwd(), mustWork = TRUE)
} else {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  if (!is.na(file_arg)) {
    normalizePath(file.path(dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)), "..", ".."), mustWork = TRUE)
  } else {
    stop("Cannot determine repository root for joint QDESN Phase126 article asset test.", call. = FALSE)
  }
}

source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/synthesize_quantiles.R"))
source(app_path("application/R/score_forecasts.R"))
source(app_path("application/R/joint_qvp_qdesn.R"))
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))
source(app_path("application/R/joint_qdesn_phase125_balanced_mcmc_audit.R"))
source(app_path("application/R/joint_qdesn_phase126_article_assets.R"))

check_manifest <- function(dir) {
  manifest <- utils::read.csv(file.path(dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) > 0L)
  stopifnot(all(nchar(manifest$sha256) == 64L))
  for (ii in seq_len(nrow(manifest))) {
    path <- file.path(dir, manifest$relative_path[[ii]])
    stopifnot(file.exists(path))
    stopifnot(identical(app_sha256_file(path), manifest$sha256[[ii]]))
  }
  invisible(manifest)
}

phase125_dir <- app_joint_qdesn_default_phase125_balanced_mcmc_audit_dir()
stopifnot(dir.exists(phase125_dir))

tables_dir <- tempfile("joint_qdesn_phase126_tables_")
out_dir <- tempfile("joint_qdesn_phase126_assets_")
audit_dir <- tempfile("joint_qdesn_phase126_audit_")
dir.create(tables_dir, recursive = TRUE)

result <- app_joint_qdesn_run_phase126_article_assets(
  phase125_dir = phase125_dir,
  tables_dir = tables_dir,
  out_dir = out_dir
)

stopifnot(identical(result$readiness$hard_implementation_gate[[1L]], "pass"))
stopifnot(identical(result$readiness$overall_gate[[1L]], "review"))
stopifnot(identical(as.integer(result$readiness$n_scenarios[[1L]]), 8L))
stopifnot(identical(as.integer(result$readiness$n_case_rows[[1L]]), 32L))
stopifnot(identical(as.integer(result$readiness$n_model_rows[[1L]]), 4L))
stopifnot(identical(as.integer(result$readiness$mcmc_forecast_contract_crossing_pairs[[1L]]), 0L))
stopifnot(as.integer(result$readiness$mcmc_forecast_raw_crossing_pairs[[1L]]) > 0L)
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_model_summary.tex")))
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_mcmc_balanced_scenario_summary.tex")))
stopifnot(file.exists(file.path(tables_dir, "joint_qdesn_article_validation_asset_manifest.csv")))

asset_manifest <- utils::read.csv(file.path(out_dir, "article_asset_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(any(asset_manifest$label == "model_tex"))
stopifnot(all(grepl("phase125", asset_manifest$source_phase125_dir)))
check_manifest(out_dir)

main_tex <- tempfile("phase126_main_", fileext = ".tex")
supp_tex <- tempfile("phase126_supp_", fileext = ".tex")
writeLines(c(
  "\\subsection{Joint Multi-Quantile Frozen-Feature Validation}",
  "The balanced grid uses eight synthetic scenarios and 32 scenario--model MCMC rows.",
  "The validation remains a quantile-grid readout study, not a scalar predictive-density construction.",
  "\\input{tables/joint_qdesn_article_validation_mcmc_balanced_model_summary.tex}"
), main_tex)
writeLines("\\input{tables/joint_qdesn_article_validation_provenance_tables.tex}", supp_tex)

audit <- app_joint_qdesn_run_phase126_article_asset_audit(
  phase126_dir = out_dir,
  tables_dir = tables_dir,
  main_tex = main_tex,
  supplement_tex = supp_tex,
  out_dir = audit_dir
)

stopifnot(identical(audit$audit_summary$audit_status[[1L]], "review"))
stopifnot(!any(audit$manuscript_checks$status == "fail"))
stopifnot(!any(audit$asset_checks$status == "fail"))
check_manifest(audit_dir)

cat("Joint QDESN Phase126 article asset tests passed.\n")
