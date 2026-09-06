#!/usr/bin/env Rscript

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/glofas_part4_ensemble_likelihood_contract.R"))

args <- app_parse_args(list(runtime_root = ""))
if (!nzchar(as.character(args$runtime_root)[[1L]])) {
  stop("--runtime_root is required.", call. = FALSE)
}

health <- app_glofas_part4_check_bundle(as.character(args$runtime_root)[[1L]])
runtime_abs <- app_resolve_path(args$runtime_root, must_work = TRUE)
app_ensure_dir(file.path(runtime_abs, "tables"))
app_write_csv(health$summary, file.path(runtime_abs, "tables", "part4_health_latest.csv"))
app_write_csv(health$status_counts, file.path(runtime_abs, "tables", "part4_status_counts_latest.csv"))

cat("Part 4 ensemble-likelihood launch-bundle health\n")
print(health$summary, row.names = FALSE)
cat("\nStatus counts\n")
print(health$status_counts, row.names = FALSE)
