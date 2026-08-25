#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_vb_spec_screening.R", "joint_exqdesn_phase149_case_specific_screening.R",
  "latent_path_design.R", "joint_exqdesn_phase151_feature_design_screening.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  output_dir = app_joint_exqdesn_phase151_default_dir(),
  readiness_dir = app_joint_exqdesn_phase151_default_readiness_dir(),
  fixture_dir = app_joint_exqdesn_phase151_default_fixture_dir(),
  candidate_ids = "",
  n_cores = "8",
  incomplete_only = "true"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]
candidate_ids <- app_joint_qdesn_parse_id_csv(value("candidate-ids", "candidate_ids"))
result <- app_joint_exqdesn_run_phase151(
  out_dir = value("output-dir", "output_dir"),
  readiness_dir = value("readiness-dir", "readiness_dir"),
  fixture_dir = value("fixture-dir", "fixture_dir"),
  candidate_ids = if (length(candidate_ids)) candidate_ids else NULL,
  n_cores = as.integer(value("n-cores", "n_cores")),
  incomplete_only = app_as_bool(value("incomplete-only", "incomplete_only"))
)
cat(sprintf("Phase151 screen written to %s\n", result$out_dir))
print(result$assessment)
if (result$assessment$gate_status[[1L]] == "fail") quit(status = 1L)
