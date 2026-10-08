#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/glofas_part4_exal_inner_audit.R"))

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_part4_exal_inner_probe_r1_20261006"
))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
status_files <- list.files(file.path(root, "status"), full.names = TRUE)
count <- function(suffix) sum(grepl(paste0("\\.", suffix, "$"), status_files))
cat(sprintf("completed=%d running=%d failed=%d\n", count("completed"), count("running"), count("failed")))
if (count("running") || count("failed")) quit(status = 2L)

manifest_path <- file.path(root, "manifests", "probe_output_manifest.csv")
gate_path <- file.path(root, "tables", "final_probe_gate.csv")
decision_path <- file.path(root, "status", "probe.completed")
required <- c(manifest_path, gate_path, decision_path, file.path(root, "manifests", "probe_contract.csv"))
if (any(!file.exists(required))) stop("The probe closeout artifacts are incomplete.", call. = FALSE)
manifest <- app_read_csv(manifest_path)
observed <- vapply(manifest$relative_path, function(path) {
  target <- file.path(root, path)
  if (!file.exists(target)) return(NA_character_)
  app_sha256_file(target)
}, character(1L))
if (anyNA(observed) || any(tolower(observed) != tolower(manifest$sha256))) {
  stop("Probe output manifest verification failed.", call. = FALSE)
}
gate <- app_read_csv(gate_path)
decision <- trimws(readLines(decision_path, warn = FALSE)[[1L]])
recomputed <- app_glofas_part4_exal_probe_decision(gate)
if (!identical(decision, recomputed)) stop("Probe decision does not reproduce.", call. = FALSE)
print(gate[, c(
  "quantile_level", "stage", "recorded_converged", "inner_iterations",
  "parameter_change", "quadrature_pass", "blocker"
)], row.names = FALSE)
cat(sprintf("decision=%s\n", decision))
