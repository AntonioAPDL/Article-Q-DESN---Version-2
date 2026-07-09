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
source(app_path("application/R/joint_qdesn_simulation_fixtures.R"))
source(app_path("application/R/joint_qdesn_simulation_validation.R"))
source(app_path("application/R/joint_qdesn_vb_spec_screening.R"))
source(app_path("application/R/joint_qdesn_calibration_screening.R"))

args <- app_parse_args(list(
  output_dir = "",
  phase112_dir = "",
  screening_output_dir = "",
  n_cores = "9"
))

arg_value <- function(name) {
  hyphen_name <- gsub("_", "-", name, fixed = TRUE)
  if (!is.null(args[[hyphen_name]])) return(args[[hyphen_name]])
  args[[name]]
}

parse_integer <- function(x) {
  out <- as.integer(suppressWarnings(as.numeric(as.character(x)[[1L]])))
  if (is.na(out)) stop(sprintf("Expected integer value, got '%s'.", as.character(x)[[1L]]), call. = FALSE)
  out
}

resolve_path <- function(path, default, must_work = FALSE) {
  path <- as.character(path)[[1L]]
  if (!nzchar(path)) path <- default
  out <- if (grepl("^/", path)) path else app_path(path)
  normalizePath(out, mustWork = must_work)
}

out_dir <- resolve_path(
  arg_value("output_dir"),
  app_joint_qdesn_default_phase113_top_candidate_readiness_dir(),
  must_work = FALSE
)
phase112_dir <- resolve_path(
  arg_value("phase112_dir"),
  app_joint_qdesn_default_next_vb_screening_dir(),
  must_work = TRUE
)
screening_output_dir <- resolve_path(
  arg_value("screening_output_dir"),
  app_joint_qdesn_default_phase113_vb_screening_dir(),
  must_work = FALSE
)

result <- app_joint_qdesn_run_phase113_top_candidate_readiness(
  out_dir = out_dir,
  phase112_dir = phase112_dir,
  screening_output_dir = screening_output_dir,
  n_cores = parse_integer(arg_value("n_cores"))
)

cat(sprintf("Joint QDESN Phase 113 top-candidate readiness artifacts written to %s\n", result$out_dir))
cat("Recommended candidates:\n")
print(
  result$recommended_registry[, c(
    "candidate_id", "candidate_role", "use_existing_artifacts", "vb_max_iter",
    "adaptive_vb_max_iter_grid", "rhs_vb_inner", "tau0", "zeta2",
    "alpha_prior_sd", "gamma_init_policy"
  ), drop = FALSE],
  row.names = FALSE
)
cat("Recommended Phase 113 launch command:\n")
cat(result$launch_command$command[[1L]], "\n")
cat(sprintf("Recommended registry: %s\n", result$paths[["phase113_recommended_registry"]]))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
