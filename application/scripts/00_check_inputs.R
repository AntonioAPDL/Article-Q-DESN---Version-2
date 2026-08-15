#!/usr/bin/env Rscript
# Purpose: validate the frozen local input manifest, schemas, and grids.
# Inputs: application config, input_manifest.csv, expected_schema.yaml.
# Outputs: run manifest, git/session state, and input-check status.
# Failure behavior: stops before modeling if required inputs are missing.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/input_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/engine_contract.R"))

args <- app_parse_args(list(config = "application/config/glofas_discrepancy_application.yaml", run_id = NULL))
cfg <- app_read_config(app_path(args$config))
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id %||% app_run_id(cfg))
app_stage_start("00_check_inputs", run_dirs)

app_write_yaml(cfg, file.path(run_dirs$manifest, "run_config.yaml"))
app_write_json(cfg, file.path(run_dirs$manifest, "run_config.json"))
app_write_git_state(file.path(run_dirs$manifest, "git_state.txt"))
app_write_session_info(file.path(run_dirs$manifest, "session_info.txt"))

manifest_path <- app_config_path(cfg, "input_manifest")
schema_path <- app_config_path(cfg, "schema")
result <- tryCatch(
  app_validate_input_manifest(manifest_path, schema_path, require_files = TRUE),
  error = function(e) {
    msg <- conditionMessage(e)
    app_write_csv(data.frame(issue = msg), file.path(run_dirs$logs, "input_manifest_issues.csv"))
    app_stage_done("00_check_inputs", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)
qg <- app_validate_quantile_grid(app_config_path(cfg, "quantile_grid"))
mg <- app_validate_model_grid(app_config_path(cfg, "model_grid"), schema_path)
app_validate_qdesn_model_grid_prior_contract(mg)
seed_contract <- tryCatch(
  app_validate_qdesn_seed_contract(cfg, mg),
  error = function(e) {
    msg <- conditionMessage(e)
    app_write_csv(data.frame(issue = msg), file.path(run_dirs$logs, "qdesn_seed_contract_issues.csv"))
    app_stage_done("00_check_inputs", run_dirs, status = "failed", message = msg)
    stop(msg, call. = FALSE)
  }
)
cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
require_qdesn <- any(mg$model_family %in% c("qdesn_reference_only", "qdesn_glofas_discrepancy") & app_as_bool_vec(mg$enabled))
require_discrepancy <- app_qdesn_engine_requires_discrepancy_export(cfg, mg)
engine_report <- if (require_qdesn) {
  app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = require_discrepancy,
    stop_on_failure = FALSE
  )
} else {
  list(
    ok = TRUE,
    engine = app_qdesn_engine_name(cfg),
    installed = NA,
    version = NA_character_,
    repo_hint = app_qdesn_engine_repo_hint(cfg),
    repo_hint_exists = !is.na(app_qdesn_engine_repo_hint(cfg)) && dir.exists(app_qdesn_engine_repo_hint(cfg)),
    repo_git_sha = app_qdesn_engine_repo_sha(app_qdesn_engine_repo_hint(cfg)),
    required_exports = character(),
    missing_exports = character(),
    require_discrepancy = FALSE,
    message = "Q-DESN engine check skipped because no enabled Q-DESN model-grid rows require it."
  )
}
app_write_csv(app_qdesn_engine_contract_row(engine_report), file.path(run_dirs$manifest, "qdesn_engine_contract.csv"))
support_report <- if (any(mg$model_family == "qdesn_glofas_discrepancy" & app_as_bool_vec(mg$enabled))) {
  app_qdesn_discrepancy_inference_support(cfg, mg, engine_report)
} else {
  data.frame()
}
if (nrow(support_report)) {
  app_write_csv(support_report, file.path(run_dirs$manifest, "qdesn_inference_support.csv"))
}
app_write_csv(seed_contract, file.path(run_dirs$manifest, "qdesn_seed_contract.csv"))
support_ok <- app_qdesn_inference_support_allows_input_gate(cfg, support_report)
seed_ok <- !nrow(seed_contract) || all(seed_contract$status == "ok")

status <- data.frame(
  check = c("input_manifest", "quantile_grid", "model_grid", "qdesn_seed_contract", "cutoffs", "qdesn_engine_contract", "qdesn_inference_support"),
  status = c(
    if (result$ok) "ok" else "failed",
    "ok",
    "ok",
    if (seed_ok) "ok" else "failed",
    if (nrow(cutoffs)) "ok" else "empty",
    if (engine_report$ok) "ok" else "failed",
    if (support_ok) "ok" else "failed"
  ),
  n_rows = c(nrow(result$manifest), nrow(qg), nrow(mg), nrow(seed_contract), nrow(cutoffs), length(engine_report$required_exports), nrow(support_report)),
  stringsAsFactors = FALSE
)
app_write_csv(status, file.path(run_dirs$tables, "input_check_status.csv"))
app_write_csv(result$manifest, file.path(run_dirs$manifest, "input_manifest_used.csv"))
app_write_csv(qg, file.path(run_dirs$manifest, "quantile_grid_used.csv"))
app_write_csv(mg, file.path(run_dirs$manifest, "model_grid_used.csv"))
if (!is.null(cfg$paths$input_bundle_manifest)) {
  bundle_manifest_path <- app_config_path(cfg, "input_bundle_manifest")
  if (file.exists(bundle_manifest_path)) {
    app_write_csv(app_read_csv(bundle_manifest_path), file.path(run_dirs$manifest, "input_bundle_manifest_used.csv"))
  }
}

if (!result$ok) {
  app_write_csv(data.frame(issue = result$issues), file.path(run_dirs$logs, "input_manifest_issues.csv"))
  app_stage_done("00_check_inputs", run_dirs, status = "failed", message = paste(result$issues, collapse = "; "))
  stop(paste(result$issues, collapse = "\n"), call. = FALSE)
}

if (!engine_report$ok && isTRUE(cfg$dependencies$fail_if_qdesn_engine_missing)) {
  app_stage_done("00_check_inputs", run_dirs, status = "failed", message = engine_report$message)
  stop(engine_report$message, call. = FALSE)
}

if (!support_ok) {
  msg <- paste(
    "At least one enabled Q-DESN discrepancy fit is not supported by the configured engine.",
    "See manifest/qdesn_inference_support.csv."
  )
  app_stage_done("00_check_inputs", run_dirs, status = "failed", message = msg)
  stop(msg, call. = FALSE)
}

app_stage_done("00_check_inputs", run_dirs)
cat(run_dirs$run_dir, "\n")
