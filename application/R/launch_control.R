# Launch-control helpers for expensive application workflows.

app_blocked_run_ids <- function(cfg = NULL) {
  configured <- cfg$execution$blocked_run_ids %||% character()
  unique(c(
    as.character(unlist(configured, use.names = FALSE)),
    "latent_path_main_al_vb_n1000_m360_20260515_024133"
  ))
}

app_run_dir_is_nonempty <- function(run_dir) {
  dir.exists(run_dir) && length(list.files(run_dir, all.files = TRUE, no.. = TRUE)) > 0L
}

app_stage_plan_row <- function(stage_files, final_launch, confirm_final_launch, preflight) {
  data.frame(
    stage_order = seq_along(stage_files),
    stage_file = stage_files,
    enters_fit_stage = basename(stage_files) == "03_fit_models.R",
    final_launch_config = isTRUE(final_launch),
    final_launch_confirmed = isTRUE(confirm_final_launch),
    preflight_requested = isTRUE(preflight),
    stringsAsFactors = FALSE
  )
}

app_validate_run_id_for_launch <- function(cfg, run_id) {
  run_id <- as.character(run_id %||% "")[[1L]]
  if (!nzchar(run_id)) {
    stop("A nonempty run_id is required for application launch control.", call. = FALSE)
  }
  blocked <- app_blocked_run_ids(cfg)
  if (run_id %in% blocked) {
    stop(
      sprintf(
        "Run id '%s' is blocked because it belongs to a cancelled or retired launch attempt.",
        run_id
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_validate_final_launch_confirmation <- function(
  cfg,
  stage_files = "03_fit_models.R",
  confirm_final_launch = FALSE
) {
  final_launch <- isTRUE(cfg$execution$final_launch$enabled %||% FALSE)
  enters_fit <- any(basename(stage_files) == "03_fit_models.R")
  if (isTRUE(final_launch) && isTRUE(enters_fit) && !app_as_bool(confirm_final_launch)) {
    stop(
      paste(
        "This configuration has execution.final_launch.enabled: true and the",
        "requested stages include 03_fit_models.R. Add",
        "--confirm_final_launch true only when you intend to start the real",
        "application fit."
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_validate_run_directory_for_workflow <- function(
  cfg,
  run_id,
  allow_existing_run_dir = FALSE
) {
  run_dir <- file.path(app_config_path(cfg, "runs"), run_id)
  if (app_run_dir_is_nonempty(run_dir) && !app_as_bool(allow_existing_run_dir)) {
    stop(
      paste(
        sprintf("Run directory already exists and is nonempty: %s", run_dir),
        "Choose a fresh run_id or pass --allow_existing_run_dir true only for",
        "an intentional resume."
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

app_validate_run_all_launch_request <- function(
  cfg,
  run_id,
  stage_files,
  confirm_final_launch = FALSE,
  allow_existing_run_dir = FALSE,
  preflight = FALSE
) {
  app_validate_run_id_for_launch(cfg, run_id)
  app_validate_final_launch_confirmation(
    cfg,
    stage_files = stage_files,
    confirm_final_launch = confirm_final_launch
  )
  app_validate_run_directory_for_workflow(
    cfg,
    run_id = run_id,
    allow_existing_run_dir = allow_existing_run_dir
  )
  app_stage_plan_row(
    stage_files = stage_files,
    final_launch = isTRUE(cfg$execution$final_launch$enabled %||% FALSE),
    confirm_final_launch = app_as_bool(confirm_final_launch),
    preflight = app_as_bool(preflight)
  )
}

app_validate_fit_stage_launch_request <- function(
  cfg,
  run_id,
  confirm_final_launch = FALSE
) {
  app_validate_run_id_for_launch(cfg, run_id)
  app_validate_final_launch_confirmation(
    cfg,
    stage_files = "03_fit_models.R",
    confirm_final_launch = confirm_final_launch
  )
  invisible(TRUE)
}
