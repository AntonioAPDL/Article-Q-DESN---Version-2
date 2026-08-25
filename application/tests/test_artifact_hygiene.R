artifact_inventory <- app_generated_artifact_inventory(large_file_bytes = 1024^4)
stopifnot(is.data.frame(artifact_inventory))
stopifnot(all(c("category", "path", "extension", "size_bytes", "git_status") %in% names(artifact_inventory)))
if (nrow(artifact_inventory)) {
  stopifnot(!any(grepl("^/", artifact_inventory$path)))
  stopifnot(all(nzchar(artifact_inventory$category)))
}

default_policy <- app_fit_artifact_policy(list())
stopifnot(isTRUE(app_fit_artifact_retained(default_policy, "retain_fit_object")))
stopifnot(isTRUE(app_fit_artifact_retained(default_policy, "retain_design_object")))
stopifnot(isTRUE(app_fit_artifact_retained(default_policy, "compact_latent_path_design")))
custom_policy <- app_fit_artifact_policy(list(execution = list(artifacts = list(
  retain_fit_object = FALSE,
  retain_prediction_design_object = "false"
))))
stopifnot(!isTRUE(app_fit_artifact_retained(custom_policy, "retain_fit_object")))
stopifnot(isTRUE(app_fit_artifact_retained(custom_policy, "retain_design_object")))
stopifnot(!isTRUE(app_fit_artifact_retained(custom_policy, "retain_prediction_design_object")))
stopifnot(is.na(app_artifact_path_for_manifest("application/runs/toy/objects/fit.rds", retained = FALSE)))
post_analysis_msg <- tryCatch(
  {
    app_validate_fit_artifact_policy(
      list(post_analysis = list(run_after_outputs = TRUE)),
      custom_policy
    )
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("post_analysis.run_after_outputs requires retained fit", post_analysis_msg, fixed = TRUE))

tmp_artifact_root <- tempfile("qdesn_artifact_root_")
dir.create(file.path(tmp_artifact_root, "application", "runs", "run_alpha", "objects"), recursive = TRUE)
dir.create(file.path(tmp_artifact_root, "application", "runs", "run_alpha", "tables"), recursive = TRUE)
dir.create(file.path(tmp_artifact_root, "application", "runs", "run_alpha", "manifest"), recursive = TRUE)
dir.create(file.path(tmp_artifact_root, "application", "runs", "run_alpha", "figures", "post_fit_analysis"), recursive = TRUE)
dir.create(file.path(tmp_artifact_root, "application", "outputs", "generated", "run_alpha", "figures"), recursive = TRUE)
dir.create(file.path(tmp_artifact_root, "tables"), recursive = TRUE)

writeLines("heavy", file.path(tmp_artifact_root, "application", "runs", "run_alpha", "objects", "fit.rds"))
writeLines("config", file.path(tmp_artifact_root, "application", "runs", "run_alpha", "manifest", "run_config.yaml"))
app_write_csv(
  data.frame(required = c(TRUE, FALSE), status = c("ok", "failed")),
  file.path(tmp_artifact_root, "application", "runs", "run_alpha", "tables", "launch_readiness_report.csv")
)
app_write_csv(
  data.frame(output_role = "score", run_id = "run_alpha"),
  file.path(tmp_artifact_root, "tables", "glofas_application_promotion_manifest__run_alpha.csv")
)
writeLines("pdf", file.path(tmp_artifact_root, "application", "outputs", "generated", "run_alpha", "figures", "toy.pdf"))

run_inventory <- app_run_level_artifact_inventory(root = tmp_artifact_root)
stopifnot(is.data.frame(run_inventory))
stopifnot(nrow(run_inventory) == 1L)
stopifnot(identical(run_inventory$run_id[[1L]], "run_alpha"))
stopifnot(run_inventory$heavy_object_count[[1L]] == 1L)
stopifnot(isTRUE(run_inventory$has_generated_outputs[[1L]]))
stopifnot(isTRUE(run_inventory$has_promoted_outputs[[1L]]))
stopifnot(run_inventory$required_readiness_failures[[1L]] == 0L)

lifecycle_root <- tempfile("glofas_lifecycle_")
for (run_id in c("loser", "winner", "unterminated")) {
  dir.create(file.path(lifecycle_root, run_id, "objects"), recursive = TRUE)
  writeLines("heavy payload", file.path(lifecycle_root, run_id, "objects", "fit.rds"))
  writeLines("diagnostic log", file.path(lifecycle_root, run_id, "worker.log"))
}
file.create(file.path(lifecycle_root, "loser", ".fit_recovery_complete"))
file.create(file.path(lifecycle_root, "winner", ".fit_recovery_complete"))
runtime_path_warnings <- character()
runtime_paths <- withCallingHandlers(
  app_runtime_paths_under_root(lifecycle_root),
  warning = function(w) {
    runtime_path_warnings <<- c(runtime_path_warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)
stopifnot(!length(runtime_path_warnings))
stopifnot(is.character(runtime_paths))
lifecycle_manifest <- app_glofas_heavy_artifact_manifest(
  lifecycle_root,
  delete_run_ids = c("loser", "unterminated"),
  protected_run_ids = "winner",
  active_paths = character()
)
stopifnot(lifecycle_manifest$action[lifecycle_manifest$run_id == "loser"] == "delete")
stopifnot(lifecycle_manifest$action[lifecycle_manifest$run_id == "winner"] == "keep")
stopifnot(lifecycle_manifest$action[lifecycle_manifest$run_id == "unterminated"] == "keep")
lifecycle_dry <- app_glofas_execute_artifact_manifest(
  lifecycle_manifest,
  lifecycle_root,
  execute = FALSE
)
stopifnot(file.exists(lifecycle_dry$path[lifecycle_dry$run_id == "loser"]))
lifecycle_active_error <- tryCatch(
  {
    app_glofas_execute_artifact_manifest(
      lifecycle_manifest,
      lifecycle_root,
      execute = TRUE,
      active_paths = file.path(lifecycle_root, "loser")
    )
    NULL
  },
  error = function(e) e
)
stopifnot(inherits(lifecycle_active_error, "error"))
stopifnot(grepl("became active", conditionMessage(lifecycle_active_error), fixed = TRUE))
loser_path <- lifecycle_manifest$path[lifecycle_manifest$run_id == "loser"]
writeLines("changed payload", loser_path)
lifecycle_hash_error <- tryCatch(
  {
    app_glofas_execute_artifact_manifest(
      lifecycle_manifest,
      lifecycle_root,
      execute = TRUE,
      active_paths = character()
    )
    NULL
  },
  error = function(e) e
)
stopifnot(inherits(lifecycle_hash_error, "error"))
stopifnot(grepl("changed after dry-run", conditionMessage(lifecycle_hash_error), fixed = TRUE))
writeLines("heavy payload", loser_path)
outside_path <- tempfile("glofas_lifecycle_outside_", fileext = ".rds")
writeLines("outside", outside_path)
outside_manifest <- lifecycle_manifest[lifecycle_manifest$run_id == "loser", , drop = FALSE]
outside_manifest$path <- outside_path
outside_manifest$sha256 <- app_sha256_file(outside_path)
outside_error <- tryCatch(
  {
    app_glofas_execute_artifact_manifest(
      outside_manifest,
      lifecycle_root,
      execute = TRUE,
      active_paths = character()
    )
    NULL
  },
  error = function(e) e
)
stopifnot(inherits(outside_error, "error"))
stopifnot(grepl("escaped", conditionMessage(outside_error), fixed = TRUE))
unlink(outside_path)
lifecycle_done <- app_glofas_execute_artifact_manifest(
  lifecycle_manifest,
  lifecycle_root,
  execute = TRUE,
  active_paths = character()
)
stopifnot(!file.exists(lifecycle_done$path[lifecycle_done$run_id == "loser"]))
stopifnot(file.exists(lifecycle_done$path[lifecycle_done$run_id == "winner"]))
stopifnot(file.exists(file.path(lifecycle_root, "loser", "worker.log")))

regeneration_dir <- file.path(lifecycle_root, "regenerable", "objects")
dir.create(regeneration_dir, recursive = TRUE)
regeneration_path <- file.path(regeneration_dir, "fit.rds")
regeneration_payload <- list(
  schema_version = "artifact_regeneration_test_v1",
  values = c(1, 3, 5, 7),
  labels = c("a", "b")
)
saveRDS(regeneration_payload, regeneration_path, compress = FALSE, version = 3L)
file.create(file.path(lifecycle_root, "regenerable", ".fit_recovery_complete"))
regeneration_manifest <- app_glofas_heavy_artifact_manifest(
  lifecycle_root,
  delete_run_ids = "regenerable",
  active_paths = character()
)
regeneration_hash <- regeneration_manifest$sha256[
  regeneration_manifest$run_id == "regenerable"
]
regeneration_done <- app_glofas_execute_artifact_manifest(
  regeneration_manifest,
  lifecycle_root,
  execute = TRUE,
  active_paths = character()
)
stopifnot(!file.exists(regeneration_path))
stopifnot(all(
  regeneration_done$execution_status[
    regeneration_done$run_id == "regenerable"
  ] == "deleted_verified"
))
saveRDS(regeneration_payload, regeneration_path, compress = FALSE, version = 3L)
stopifnot(identical(app_sha256_file(regeneration_path), regeneration_hash[[1L]]))
unlink(lifecycle_root, recursive = TRUE)
