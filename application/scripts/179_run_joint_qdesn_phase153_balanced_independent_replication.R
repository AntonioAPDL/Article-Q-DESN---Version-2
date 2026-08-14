#!/usr/bin/env Rscript

script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_readiness.R",
  "joint_qdesn_simulation_fixtures.R", "joint_qdesn_simulation_validation.R",
  "joint_qdesn_phase153_balanced_independent_replication.R"
)) source(app_path("application/R", path))

args <- app_parse_args(list(
  output_dir = app_joint_qdesn_phase153_default_vb_dir(),
  readiness_dir = app_joint_qdesn_phase153_default_readiness_dir(),
  fixture_dir = app_joint_qdesn_phase153_default_fixture_dir(),
  n_cores = "20",
  incomplete_only = "true",
  bootstrap_replicates = "2000"
))
value <- function(hyphen, underscore) args[[hyphen]] %||% args[[underscore]]

result <- app_joint_qdesn_run_phase153(
  out_dir = value("output-dir", "output_dir"),
  readiness_dir = value("readiness-dir", "readiness_dir"),
  fixture_dir = value("fixture-dir", "fixture_dir"),
  n_cores = as.integer(value("n-cores", "n_cores")),
  incomplete_only = app_as_bool(value("incomplete-only", "incomplete_only")),
  bootstrap_replicates = as.integer(value(
    "bootstrap-replicates", "bootstrap_replicates"
  ))
)
cat(sprintf("Phase153 replication artifacts written to %s\n", result$out_dir))
print(result$assessment)
if (result$assessment$gate_status[[1L]] == "fail") quit(status = 1L)
