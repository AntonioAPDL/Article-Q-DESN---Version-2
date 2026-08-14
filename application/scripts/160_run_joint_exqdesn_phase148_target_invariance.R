#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
script_arg <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(normalizePath(script_arg)), "..", ".."))
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (path in c(
  "input_contract.R", "synthesize_quantiles.R", "score_forecasts.R",
  "joint_qvp_qdesn.R", "joint_qdesn_simulation_validation.R",
  "joint_exqdesn_phase148_target_invariance.R"
)) source(app_path("application/R", path))

value <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[[1L]]) else default
}

result <- app_joint_exqdesn_run_phase148_target_invariance(
  out_dir = value("output-dir", app_joint_exqdesn_phase148_default_dir()),
  n_iter = as.integer(value("n-iter", "12000")),
  burn = as.integer(value("burn", "2000")),
  thin = as.integer(value("thin", "2"))
)
cat(sprintf("Phase148 target-invariance artifact written to %s\n", result$out_dir))
print(result$assessment)
if (identical(result$assessment$gate_status[[1L]], "fail")) quit(status = 1L)
