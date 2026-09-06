#!/usr/bin/env Rscript

source(file.path(dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))), "_joint_qdesn_shared_backbone_bootstrap.R"))
args <- app_parse_args(list(
  output_dir = app_joint_shared_default_root(),
  authority_registry = app_joint_shared_default_authority_registry(),
  authority_manifest = "",
  scenario_id = app_joint_shared_read_contract()$pilot_scenario,
  contract_path = app_joint_shared_contract_path(),
  scenario_registry_path = app_joint_shared_scenario_path()
))
authority_registry <- args[["authority-registry"]] %||% args$authority_registry
authority_manifest <- args[["authority-manifest"]] %||% args$authority_manifest
if (!nzchar(authority_manifest)) {
  authority_manifest <- file.path(dirname(authority_registry), "artifact_manifest.csv")
}
result <- app_joint_shared_prepare_ridge(
  out_dir = args[["output-dir"]] %||% args$output_dir,
  authority_registry = authority_registry,
  scenario_id = args[["scenario-id"]] %||% args$scenario_id,
  contract_path = args[["contract-path"]] %||% args$contract_path,
  scenario_registry_path = args[["scenario-registry-path"]] %||% args$scenario_registry_path,
  authority_manifest = authority_manifest
)
print(result$readiness)
cat(sprintf("Prepared shared-backbone ridge screen at %s\n", result$out_dir))
