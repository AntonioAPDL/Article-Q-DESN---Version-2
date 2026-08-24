#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/glofas_screening_program_closeout.R"))

args <- app_parse_args(list(
  contract = "application/config/glofas_screening_program_closeout_20260824.yaml",
  output_root = "local_trackers/runtime_configs/glofas_screening_program_closeout_20260824"
))
contract_path <- app_resolve_path(args$contract, must_work = TRUE)
output_root <- app_resolve_path(args$output_root, must_work = FALSE)
app_ensure_dir(output_root)

contract <- app_read_yaml(contract_path)
result <- app_glofas_screening_program_closeout(contract)
app_write_csv(result$phases, file.path(output_root, "campaign_summary.csv"))
app_write_csv(result$decision, file.path(output_root, "program_decision.csv"))

evidence_paths <- unique(c(
  contract_path,
  result$phases$ranking_path,
  result$phases$selection_path,
  app_resolve_path(contract$mechanism_audit$path, must_work = TRUE)
))
evidence <- data.frame(
  path = evidence_paths,
  sha256 = vapply(evidence_paths, app_sha256_file, character(1L)),
  size_bytes = as.numeric(file.info(evidence_paths)$size),
  stringsAsFactors = FALSE
)
app_write_csv(evidence, file.path(output_root, "evidence_manifest.csv"))
app_write_csv(data.frame(
  status = "completed",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  program_id = result$decision$program_id[[1L]],
  decision = result$decision$decision[[1L]],
  campaign_summary_sha256 = app_sha256_file(file.path(output_root, "campaign_summary.csv")),
  program_decision_sha256 = app_sha256_file(file.path(output_root, "program_decision.csv")),
  evidence_manifest_sha256 = app_sha256_file(file.path(output_root, "evidence_manifest.csv")),
  stringsAsFactors = FALSE
), file.path(output_root, "audit_status.csv"))

cat(normalizePath(file.path(output_root, "program_decision.csv"), mustWork = TRUE), "\n")

