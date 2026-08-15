#!/usr/bin/env Rscript
# Purpose: run the reproducibility gate that must pass before a large Q-DESN
# application fit is launched. The gate materializes the source-registry row,
# registers and audits inputs, builds the panel, and checks the Q-DESN design
# without starting MCMC.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))

app_gate_run_stage <- function(script, args = character()) {
  cmd <- file.path("application", "scripts", script)
  status <- system2("Rscript", c(cmd, args))
  if (!identical(status, 0L)) {
    stop(sprintf("Input/design gate stage failed: %s", script), call. = FALSE)
  }
  invisible(TRUE)
}

app_gate_registry_row <- function(cfg, source_registry = NULL, cutoff_id = "") {
  registry_path <- if (!is.null(source_registry) && nzchar(as.character(source_registry))) {
    if (grepl("^/", source_registry)) source_registry else app_path(source_registry)
  } else {
    app_config_path(cfg, "source_registry")
  }
  registry <- app_read_csv(registry_path)
  app_check_required_columns(
    registry,
    c("cutoff_id", "cutoff_date", "source_audit_bundle_root", "source_audit_extra_roots", "enabled"),
    "authoritative cutoff source registry"
  )
  registry <- registry[app_as_bool_vec(registry$enabled), , drop = FALSE]
  if (nzchar(cutoff_id)) registry <- registry[registry$cutoff_id == cutoff_id, , drop = FALSE]
  if (nrow(registry) != 1L) {
    stop(
      sprintf("Expected exactly one enabled source-registry row for the gate but found %d.", nrow(registry)),
      call. = FALSE
    )
  }
  registry$source_registry_path <- registry_path
  registry[1L, , drop = FALSE]
}

args <- app_parse_args(list(
  config = "application/config/glofas_discrepancy_mcmc_large_dec25.yaml",
  source_registry = NULL,
  cutoff_id = "dec25_2022",
  run_id = NULL,
  design_fit_id = "",
  source_audit = "true"
))

cfg <- app_read_config(app_path(args$config))
run_id <- args$run_id %||% sprintf(
  "input_design_gate_%s_%s",
  if (nzchar(args$cutoff_id)) args$cutoff_id else "cutoff",
  format(Sys.time(), "%Y%m%d_%H%M%S")
)
row <- app_gate_registry_row(
  cfg,
  source_registry = args$source_registry,
  cutoff_id = args$cutoff_id %||% ""
)

base_args <- c("--config", args$config, "--run_id", run_id)

app_gate_run_stage(
  "00_materialize_from_source_registry.R",
  c(
    "--config", args$config,
    "--run_id", run_id,
    "--cutoff_id", row$cutoff_id[[1L]]
  )
)

if (app_as_bool(args$source_audit)) {
  extra_roots <- gsub(";", ",", row$source_audit_extra_roots[[1L]], fixed = TRUE)
  app_gate_run_stage(
    "00_audit_authoritative_source_bundle.R",
    c(
      "--config", args$config,
      "--run_id", run_id,
      "--bundle_root", row$source_audit_bundle_root[[1L]],
      "--cutoff_date", row$cutoff_date[[1L]],
      "--requirements", row$requirements_path[[1L]],
      "--extra_root", extra_roots
    )
  )
}

app_gate_run_stage("00_register_input_bundle.R", base_args)
app_gate_run_stage(
  "00_audit_glofas_retrospective_history.R",
  c(
    "--config", args$config,
    "--cutoff_id", row$cutoff_id[[1L]],
    "--output_dir", file.path(app_config_path(cfg, "runs"), run_id, "tables")
  )
)
app_gate_run_stage("00_check_inputs.R", base_args)
app_gate_run_stage("00_audit_input_bundle.R", base_args)
app_gate_run_stage("01_build_panel.R", base_args)

design_args <- base_args
if (nzchar(as.character(args$design_fit_id %||% ""))) {
  design_args <- c(design_args, "--fit_id", args$design_fit_id)
}
app_gate_run_stage("03_check_model_design.R", design_args)

cat(file.path(app_config_path(cfg, "runs"), run_id), "\n")
