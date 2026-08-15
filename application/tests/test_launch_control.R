main_launch_cfg <- app_read_config(app_path("application/config/glofas_latent_path_al_vb_dec25_main.yaml"))
main_stage_files <- c("00_check_inputs.R", "03_fit_models.R", "06_preflight_launch.R")

missing_confirm_msg <- tryCatch(
  {
    app_validate_run_all_launch_request(
      main_launch_cfg,
      run_id = "test_launch_control_missing_confirm",
      stage_files = main_stage_files,
      confirm_final_launch = FALSE,
      allow_existing_run_dir = FALSE,
      preflight = TRUE
    )
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("--confirm_final_launch true", missing_confirm_msg, fixed = TRUE))

fit_stage_msg <- tryCatch(
  {
    app_validate_fit_stage_launch_request(
      main_launch_cfg,
      run_id = "test_launch_control_missing_confirm_direct_fit",
      confirm_final_launch = FALSE
    )
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("--confirm_final_launch true", fit_stage_msg, fixed = TRUE))

blocked_msg <- tryCatch(
  {
    app_validate_run_all_launch_request(
      main_launch_cfg,
      run_id = "latent_path_main_al_vb_n1000_m360_20260515_024133",
      stage_files = main_stage_files,
      confirm_final_launch = TRUE,
      allow_existing_run_dir = FALSE,
      preflight = TRUE
    )
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("blocked", blocked_msg, fixed = TRUE))

tmp_root_launch <- tempfile("qdesn_launch_control_")
dir.create(file.path(tmp_root_launch, "runs", "existing_run"), recursive = TRUE)
writeLines("already here", file.path(tmp_root_launch, "runs", "existing_run", "marker.txt"))
existing_cfg <- main_launch_cfg
existing_cfg$paths$runs <- file.path(tmp_root_launch, "runs")
existing_msg <- tryCatch(
  {
    app_validate_run_all_launch_request(
      existing_cfg,
      run_id = "existing_run",
      stage_files = main_stage_files,
      confirm_final_launch = TRUE,
      allow_existing_run_dir = FALSE,
      preflight = TRUE
    )
    ""
  },
  error = conditionMessage
)
stopifnot(grepl("already exists and is nonempty", existing_msg, fixed = TRUE))

stage_plan <- app_validate_run_all_launch_request(
  existing_cfg,
  run_id = "fresh_confirmed_run",
  stage_files = main_stage_files,
  confirm_final_launch = TRUE,
  allow_existing_run_dir = FALSE,
  preflight = TRUE
)
stopifnot(nrow(stage_plan) == length(main_stage_files))
stopifnot(any(stage_plan$enters_fit_stage))
stopifnot(all(stage_plan$final_launch_config))
stopifnot(all(stage_plan$final_launch_confirmed))

profile_stage_plan <- app_validate_run_all_launch_request(
  main_launch_cfg,
  run_id = "safe_profile_only",
  stage_files = "03_profile_latent_path_al_vb.R",
  confirm_final_launch = FALSE,
  allow_existing_run_dir = FALSE,
  preflight = FALSE
)
stopifnot(nrow(profile_stage_plan) == 1L)
stopifnot(!any(profile_stage_plan$enters_fit_stage))
