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
