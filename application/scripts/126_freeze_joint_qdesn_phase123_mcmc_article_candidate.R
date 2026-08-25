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
source(app_path("application/R/joint_qdesn_simulation_readiness.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_mcmc_readiness.R"))
source(app_path("application/R/joint_qdesn_phase123_mcmc_article_freeze.R"))

args <- app_parse_args(list(
  output_dir = "",
  phase122_dir = ""
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, winslash = "/", mustWork = must_work)
}

result <- app_joint_qdesn_run_phase123_mcmc_article_freeze(
  out_dir = resolve_path(
    arg_value("output_dir"),
    app_joint_qdesn_default_phase123_mcmc_article_freeze_dir(),
    must_work = FALSE
  ),
  phase122_dir = resolve_path(
    arg_value("phase122_dir"),
    app_joint_qdesn_default_phase122_mcmc_case_confirmation_dir(),
    must_work = TRUE
  )
)

cat(sprintf("Joint QDESN Phase 123 MCMC article-candidate freeze written to %s\n", result$out_dir))
cat("Health summary:\n")
print(result$health[, c("component", "status", "progress"), drop = FALSE], row.names = FALSE)
cat("Gate counts:\n")
print(table(result$gate_summary$status))
cat("Recommendation:\n")
print(result$recommendation, row.names = FALSE)
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
