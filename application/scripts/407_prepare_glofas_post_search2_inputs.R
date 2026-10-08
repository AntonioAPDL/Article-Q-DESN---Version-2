#!/usr/bin/env Rscript

# Validate the runtime-owned Dec-25 input bundle before a production DAG exists.

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg[[1L]])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
for (file in c(
  "input_contract.R", "engine_contract.R", "model_contract.R", "feature_contract.R",
  "covariate_design.R", "build_application_panel.R", "fit_qdesn_latent_path.R",
  "glofas_part4_ensemble_likelihood_contract.R", "glofas_part4_latent_family.R",
  "register_input_bundle.R"
)) source(app_path("application/R", file))

args <- app_parse_args(list(
  config = "",
  hash_contract = "application/config/glofas_dec25_input_hash_contract.csv",
  audit_output = "",
  readiness_output = ""
))

config_path <- app_resolve_path(args$config, must_work = TRUE)
hash_contract_path <- app_resolve_path(args$hash_contract, must_work = TRUE)
audit_output <- app_resolve_path(args$audit_output, must_work = FALSE)
readiness_output <- app_resolve_path(args$readiness_output, must_work = FALSE)
if (!nzchar(args$audit_output) || !nzchar(args$readiness_output)) {
  stop("--audit_output and --readiness_output are required.", call. = FALSE)
}

cfg <- app_read_config(config_path)
registered <- app_register_input_bundle(
  bundle_config_path = app_config_path(cfg, "input_bundle"),
  schema_path = app_config_path(cfg, "schema"),
  manifest_output = app_config_path(cfg, "input_manifest"),
  bundle_manifest_output = app_config_path(cfg, "input_bundle_manifest"),
  require_files = TRUE
)
if (!isTRUE(registered$ok)) {
  stop(paste(registered$issues, collapse = " | "), call. = FALSE)
}

validated <- app_validate_input_manifest(
  app_config_path(cfg, "input_manifest"),
  app_config_path(cfg, "schema"),
  require_files = TRUE
)
if (!isTRUE(validated$ok)) {
  stop(paste(validated$issues, collapse = " | "), call. = FALSE)
}

hash_contract <- app_read_csv(hash_contract_path)
app_check_required_columns(
  hash_contract,
  c("input_id", "relative_path", "size_bytes", "sha256", "required", "model_role"),
  "GloFAS Dec-25 input hash contract"
)
if (anyDuplicated(hash_contract$input_id)) {
  stop("Input hash contract contains duplicate input_id values.", call. = FALSE)
}
manifest <- validated$manifest
if (!setequal(hash_contract$input_id, manifest$input_id)) {
  stop("Runtime input manifest does not contain exactly the hash-contract inputs.", call. = FALSE)
}
hash_checks <- lapply(seq_len(nrow(hash_contract)), function(i) {
  expected <- hash_contract[i, , drop = FALSE]
  actual <- manifest[manifest$input_id == expected$input_id[[1L]], , drop = FALSE]
  local_path <- actual$local_path[[1L]]
  local_abs <- if (grepl("^/", local_path)) local_path else app_path(local_path)
  info <- file.info(local_abs)
  data.frame(
    check = paste0("hash_contract_", expected$input_id[[1L]]),
    status = if (
      nrow(actual) == 1L &&
      identical(tolower(actual$sha256[[1L]]), tolower(expected$sha256[[1L]])) &&
      identical(as.numeric(info$size[[1L]]), as.numeric(expected$size_bytes[[1L]]))
    ) "pass" else "fail",
    detail = sprintf("sha256=%s;size=%s", actual$sha256[[1L]], info$size[[1L]]),
    stringsAsFactors = FALSE
  )
})

panel <- app_glofas_part4_build_panel(cfg)
cutoffs <- app_validate_cutoffs(app_config_path(cfg, "cutoffs"))
cutoff_row <- cutoffs[cutoffs$cutoff_id == "dec25_2022", , drop = FALSE]
if (nrow(cutoff_row) != 1L) {
  stop("Expected exactly one enabled dec25_2022 cutoff row.", call. = FALSE)
}
window_checks <- app_glofas_part4_window_audit(panel, cutoff_row)
source_checks <- app_glofas_part4_validate_no_forecast_contract(cfg)

manifest_row <- function(id) manifest[manifest$input_id == id, , drop = FALSE]
gauge <- manifest_row("reference_gauge")
retro <- manifest_row("glofas_retrospective")
covar <- manifest_row("ppt_soil_covariates")
covar_path <- covar$local_path[[1L]]
covar_abs <- if (grepl("^/", covar_path)) covar_path else app_path(covar_path)
covar_names <- tolower(names(app_read_csv(covar_abs)))
forbidden_covars <- grep("pca|gdpc|gefs|cefs|climate_index", covar_names, value = TRUE)

semantic_checks <- data.frame(
  check = c(
    "response_scale_log1p",
    "gauge_covers_requested_window",
    "retrospective_ends_at_cutoff",
    "ppt_soil_covers_requested_window",
    "ppt_soil_required_columns",
    "ppt_soil_forbidden_columns_absent"
  ),
  status = c(
    if (identical(tolower(as.character(cfg$data$transform$response)), "log1p")) "pass" else "fail",
    if (as.Date(gauge$date_max[[1L]]) >= as.Date("2023-01-24")) "pass" else "fail",
    if (identical(as.Date(retro$date_max[[1L]]), as.Date("2022-12-25"))) "pass" else "fail",
    if (as.Date(covar$date_max[[1L]]) >= as.Date("2023-01-24")) "pass" else "fail",
    if (all(c("date", "ppt", "soil") %in% covar_names)) "pass" else "fail",
    if (!length(forbidden_covars)) "pass" else "fail"
  ),
  detail = c(
    as.character(cfg$data$transform$response),
    as.character(gauge$date_max[[1L]]),
    as.character(retro$date_max[[1L]]),
    as.character(covar$date_max[[1L]]),
    paste(intersect(c("date", "ppt", "soil"), covar_names), collapse = "|"),
    if (length(forbidden_covars)) paste(forbidden_covars, collapse = "|") else "none"
  ),
  stringsAsFactors = FALSE
)

hash_audit <- do.call(rbind, hash_checks)
window_audit <- data.frame(
  check = paste0("part4_window_", window_checks$check),
  status = window_checks$status,
  detail = window_checks$detail,
  stringsAsFactors = FALSE
)
source_audit <- data.frame(
  check = paste0("part4_source_", source_checks$check),
  status = source_checks$status,
  detail = source_checks$detail,
  stringsAsFactors = FALSE
)
audit <- rbind(hash_audit, semantic_checks, window_audit, source_audit)
app_write_csv(audit, audit_output)
if (any(audit$status != "pass")) {
  stop(
    sprintf("Post-Search-II input readiness failed: %s", paste(audit$check[audit$status != "pass"], collapse = ", ")),
    call. = FALSE
  )
}

readiness <- list(
  schema_version = "glofas_post_search2_input_readiness_v1",
  status = "ready",
  checked_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  config_path = app_prefer_repo_relative_path(config_path),
  config_sha256 = app_sha256_file(config_path),
  hash_contract_path = app_prefer_repo_relative_path(hash_contract_path),
  hash_contract_sha256 = app_sha256_file(hash_contract_path),
  input_manifest_path = app_prefer_repo_relative_path(app_config_path(cfg, "input_manifest")),
  input_manifest_sha256 = app_sha256_file(app_config_path(cfg, "input_manifest")),
  bundle_manifest_path = app_prefer_repo_relative_path(app_config_path(cfg, "input_bundle_manifest")),
  bundle_manifest_sha256 = app_sha256_file(app_config_path(cfg, "input_bundle_manifest")),
  audit_path = app_prefer_repo_relative_path(audit_output),
  audit_sha256 = app_sha256_file(audit_output),
  cutoff = "2022-12-25",
  requested_forecast_window = c("2022-12-26", "2023-01-24"),
  issued_ensemble_window = c("2022-12-26", "2023-01-22"),
  issued_horizons = 28L,
  ensemble_members = 51L,
  response_scale = "log1p",
  model_covariates = c("ppt", "soil"),
  forbidden_model_covariates = forbidden_covars,
  checks = nrow(audit)
)
app_write_json(readiness, readiness_output)
cat("POST_SEARCH2_INPUT_READINESS_PASS\n")
