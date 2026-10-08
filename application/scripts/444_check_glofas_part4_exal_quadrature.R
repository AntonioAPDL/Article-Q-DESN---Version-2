#!/usr/bin/env Rscript

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)

args <- app_parse_args(list(
  runtime_root = "local_trackers/runtime_configs/glofas_part4_exal_quadrature_certificate_r1_20261007"
))
root <- app_resolve_path(args$runtime_root, must_work = TRUE)
required <- file.path(root, c(
  "status/certificate.completed",
  "tables/quadrature_diagnostics.csv",
  "tables/quadrature_certificate.csv",
  "tables/quadrature_component_comparison.csv",
  "manifests/quadrature_contract.csv",
  "manifests/quadrature_output_manifest.csv",
  "reports/quadrature_findings.md"
))
if (any(!file.exists(required))) stop("Quadrature certificate closeout is incomplete.", call. = FALSE)

manifest <- app_read_csv(file.path(root, "manifests", "quadrature_output_manifest.csv"))
observed <- vapply(manifest$relative_path, function(path) {
  target <- file.path(root, path)
  if (!file.exists(target)) return(NA_character_)
  app_sha256_file(target)
}, character(1L))
if (anyNA(observed) || any(tolower(observed) != tolower(manifest$sha256))) {
  stop("Quadrature certificate output-manifest verification failed.", call. = FALSE)
}

decision <- trimws(readLines(file.path(root, "status", "certificate.completed"), warn = FALSE)[[1L]])
certificate <- app_read_csv(file.path(root, "tables", "quadrature_certificate.csv"))
contract <- app_read_csv(file.path(root, "manifests", "quadrature_contract.csv"))
if (nrow(certificate) != 2L || !identical(sort(as.character(certificate$source)), c("G", "Y")) ||
    !all(certificate$passed) || nrow(contract) != 1L ||
    !identical(as.character(contract$decision[[1L]]), decision) ||
    !identical(decision, "READY_FOR_TARGETED_JOINT_EXAL_CORRECTION")) {
  stop(sprintf("Quadrature certificate did not authorize production: %s", decision), call. = FALSE)
}
print(certificate, row.names = FALSE)
cat(sprintf("decision=%s\n", decision))
