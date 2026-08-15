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
source(app_path("application/R/joint_qvp_qdesn.R"))

args <- app_parse_args(list(output_dir = "", registry = ""))
plain_args <- commandArgs(trailingOnly = TRUE)
plain_args <- plain_args[!startsWith(plain_args, "--")]

out_dir <- if (nzchar(as.character(args$output_dir))) {
  as.character(args$output_dir)
} else if (length(plain_args) >= 1L && nzchar(plain_args[[1L]])) {
  plain_args[[1L]]
} else {
  app_path("application/cache/joint_qvp_synthetic_dgp_registry_phase1_20260702")
}

registry_path <- if (nzchar(as.character(args$registry))) {
  as.character(args$registry)
} else {
  app_joint_qvp_default_synthetic_dgp_registry_path()
}

result <- app_joint_qvp_materialize_synthetic_dgp_registry(
  out_dir = out_dir,
  registry_path = registry_path
)

cat(sprintf("Joint-QVP synthetic DGP registry artifacts written to %s\n", result$out_dir))
cat(sprintf("Frozen registry rows: %s\n", nrow(result$registry)))
cat(sprintf("Scenario classes: bridge=%s, stress=%s\n",
  sum(result$registry$scenario_class == "bridge"),
  sum(result$registry$scenario_class == "stress")
))
cat(sprintf("Artifact manifest: %s\n", result$paths[["artifact_manifest"]]))
