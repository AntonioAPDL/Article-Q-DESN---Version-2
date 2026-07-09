phase4k_assets_registry <- app_joint_qvp_load_synthetic_dgp_registry()
phase4k_assets_ids <- c("normal_bridge", "laplace_bridge")
phase4k_assets_base_registry <- phase4k_assets_registry[phase4k_assets_registry$scenario_id %in% phase4k_assets_ids, , drop = FALSE]
phase4k_assets_base_registry <- phase4k_assets_base_registry[match(phase4k_assets_ids, phase4k_assets_base_registry$scenario_id), , drop = FALSE]
phase4k_assets_base_registry$tau_grid <- "0.25,0.5,0.75"
phase4k_assets_base_registry$simulated_length <- 34L
phase4k_assets_base_registry$washout_length <- 6L
phase4k_assets_base_registry$train_length <- 18L
phase4k_assets_base_registry$test_length <- 10L
phase4k_assets_base_registry$seed <- c(202607121L, 202607122L)
app_joint_qvp_validate_synthetic_dgp_registry(phase4k_assets_base_registry)

phase4k_assets_launch_dir <- tempfile("joint_qvp_phase4k_assets_launch_")
phase4k_assets_launch <- app_joint_qvp_run_synthetic_dgp_phase4j_tau0_candidate_launch(
  out_dir = phase4k_assets_launch_dir,
  registry = phase4k_assets_base_registry,
  scenario_ids = phase4k_assets_ids,
  tier = "tau0_candidate_launch",
  tau0_arms = c(0.10, 0.15),
  n_replicates = 1L,
  seed_base = 202607930L,
  simulated_length = 34L,
  washout_length = 6L,
  train_length = 18L,
  test_length = 10L,
  vb_max_iter = 5L,
  adaptive_vb_max_iter_grid = 5L,
  refit_stride = 99L,
  forecast_origin_stride = 1L,
  max_origins_per_scenario = 2L
)
writeLines("0", file.path(phase4k_assets_launch$out_dir, "phase4j_launch.exitcode"), useBytes = TRUE)

phase4k_assets_audit <- app_joint_qvp_audit_synthetic_dgp_phase4j_tau0_candidate_launch(
  out_dir = phase4k_assets_launch$out_dir,
  audit_dir = file.path(phase4k_assets_launch$out_dir, "phase4j_launch_audit")
)
phase4k_assets_freeze_dir <- tempfile("joint_qvp_phase4k_assets_freeze_")
phase4k_assets_freeze <- app_joint_qvp_freeze_synthetic_dgp_phase4k_article_candidate(
  launch_dir = phase4k_assets_launch$out_dir,
  audit_dir = phase4k_assets_audit$audit_dir,
  freeze_dir = phase4k_assets_freeze_dir,
  expected_selected_arm = "",
  allow_selected_arm_override = TRUE
)

phase4k_assets_table_dir <- tempfile("joint_qvp_phase4k_assets_tables_")
phase4k_assets_figure_dir <- tempfile("joint_qvp_phase4k_assets_figures_")
phase4k_assets <- app_joint_qvp_build_synthetic_dgp_phase4k_article_assets(
  freeze_dir = phase4k_assets_freeze$freeze_dir,
  table_dir = phase4k_assets_table_dir,
  figure_dir = phase4k_assets_figure_dir
)
phase4k_asset_manifest_path <- file.path(phase4k_assets$table_dir, "joint_qvp_synthetic_dgp_phase4k_asset_manifest.csv")
stopifnot(file.exists(phase4k_asset_manifest_path))
phase4k_asset_manifest <- utils::read.csv(phase4k_asset_manifest_path, stringsAsFactors = FALSE)
stopifnot(sum(phase4k_asset_manifest$artifact_type == "table") >= 7L)
stopifnot(sum(phase4k_asset_manifest$artifact_type == "figure") >= 5L)
stopifnot(all(nchar(phase4k_asset_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4k_asset_manifest))) {
  artifact_path <- app_joint_qvp_phase4k_resolve_path(phase4k_asset_manifest$path[[ii]], must_work = TRUE)
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4k_asset_manifest$sha256[[ii]]))
  stopifnot(file.info(artifact_path)$size > 0)
}

phase4k_asset_audit <- app_joint_qvp_audit_synthetic_dgp_phase4k_article_assets(
  freeze_dir = phase4k_assets_freeze$freeze_dir,
  table_dir = phase4k_assets$table_dir,
  figure_dir = phase4k_assets$figure_dir,
  audit_dir = file.path(phase4k_assets_freeze$freeze_dir, "phase4k_article_asset_audit"),
  expected_selected_arm = "",
  expected_selected_tau0 = NA_real_,
  allow_selected_arm_override = TRUE
)
stopifnot(phase4k_asset_audit$audit$audit_gate_status[[1L]] %in% c("pass", "review"))
stopifnot(file.exists(file.path(phase4k_asset_audit$audit_dir, "artifact_manifest.csv")))
phase4k_audit_manifest <- utils::read.csv(file.path(phase4k_asset_audit$audit_dir, "artifact_manifest.csv"), stringsAsFactors = FALSE)
stopifnot(all(nchar(phase4k_audit_manifest$sha256) == 64L))
for (ii in seq_len(nrow(phase4k_audit_manifest))) {
  artifact_path <- file.path(phase4k_asset_audit$audit_dir, phase4k_audit_manifest$relative_path[[ii]])
  stopifnot(file.exists(artifact_path))
  stopifnot(identical(app_sha256_file(artifact_path), phase4k_audit_manifest$sha256[[ii]]))
}

phase4k_checklist <- utils::read.csv(file.path(phase4k_asset_audit$audit_dir, "phase4k_manuscript_integration_checklist.csv"), stringsAsFactors = FALSE)
stopifnot(any(grepl("Manuscript can consume Phase 4k assets", phase4k_checklist$item, fixed = TRUE)))
stopifnot(all(phase4k_checklist$status %in% c("pass", "review", "ready", "blocked", "fail")))
