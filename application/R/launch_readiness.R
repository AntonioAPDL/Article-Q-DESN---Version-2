# Launch-readiness checks for the GloFAS Q-DESN application.

app_launch_check_row <- function(gate, check, ok, detail = "", required = TRUE) {
  data.frame(
    gate = gate,
    check = check,
    required = isTRUE(required),
    status = if (isTRUE(ok)) "ok" else "failed",
    detail = detail %||% "",
    stringsAsFactors = FALSE
  )
}

app_git_status_lines <- function(repo) {
  if (is.na(repo) || !nzchar(repo) || !dir.exists(repo)) return(NA_character_)
  out <- tryCatch(
    system2("git", c("-C", repo, "status", "--short"), stdout = TRUE, stderr = TRUE),
    error = function(e) sprintf("git status failed: %s", conditionMessage(e))
  )
  out %||% character()
}

app_git_clean_check <- function(repo, label, required = TRUE) {
  lines <- app_git_status_lines(repo)
  if (length(lines) == 1L && is.na(lines)) {
    return(app_launch_check_row("code", paste0(label, "_repo_exists"), FALSE, repo, required = required))
  }
  ok <- length(lines) == 0L
  app_launch_check_row(
    "code",
    paste0(label, "_git_clean"),
    ok,
    if (ok) "git status --short is empty" else paste(lines, collapse = "; "),
    required = required
  )
}

app_git_upstream_check <- function(repo, label, required = TRUE) {
  if (is.na(repo) || !nzchar(repo) || !dir.exists(repo)) {
    return(app_launch_check_row("code", paste0(label, "_repo_exists"), FALSE, repo, required = required))
  }
  upstream <- tryCatch(
    system2("git", c("-C", repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"), stdout = TRUE, stderr = TRUE),
    error = function(e) character()
  )
  if (!length(upstream) || !nzchar(upstream[[1L]]) || grepl("fatal:", upstream[[1L]], fixed = TRUE)) {
    return(app_launch_check_row("code", paste0(label, "_git_upstream_synced"), FALSE, "No upstream branch is configured.", required = required))
  }
  counts <- tryCatch(
    system2("git", c("-C", repo, "rev-list", "--left-right", "--count", paste0(upstream[[1L]], "...HEAD")), stdout = TRUE, stderr = TRUE),
    error = function(e) character()
  )
  counts_line <- if (length(counts)) counts[[1L]] else ""
  pieces <- suppressWarnings(as.integer(strsplit(trimws(counts_line), "[[:space:]]+")[[1L]]))
  ok <- length(pieces) == 2L && all(is.finite(pieces)) && all(pieces == 0L)
  behind <- if (length(pieces) >= 1L) pieces[[1L]] else NA_integer_
  ahead <- if (length(pieces) >= 2L) pieces[[2L]] else NA_integer_
  app_launch_check_row(
    "code",
    paste0(label, "_git_upstream_synced"),
    ok,
    if (ok) sprintf("local branch is synchronized with %s", upstream[[1L]]) else sprintf("behind=%s ahead=%s relative to %s", behind, ahead, upstream[[1L]]),
    required = required
  )
}

app_launch_status_files <- function() {
  c(
    "00_check_inputs",
    "00_audit_input_bundle",
    "01_build_panel",
    "02_make_input_figures",
    "03_fit_models",
    "04_score_models",
    "05_make_outputs"
  )
}

app_launch_stage_checks <- function(run_dirs, stages = app_launch_status_files()) {
  rows <- vector("list", length(stages))
  for (i in seq_along(stages)) {
    stage <- stages[[i]]
    path <- file.path(run_dirs$logs, paste0(stage, "_status.csv"))
    if (!file.exists(path)) {
      rows[[i]] <- app_launch_check_row("stages", stage, FALSE, sprintf("Missing status file: %s", path))
      next
    }
    status <- app_read_csv(path)
    ok <- nrow(status) >= 1L && identical(status$status[[nrow(status)]], "completed")
    detail <- if (ok) {
      sprintf("completed at %s", status$time[[nrow(status)]])
    } else {
      paste(status$message %||% "stage did not complete", collapse = "; ")
    }
    rows[[i]] <- app_launch_check_row("stages", stage, ok, detail)
  }
  do.call(rbind, rows)
}

app_pdf_page_count <- function(path) {
  if (!nzchar(Sys.which("pdfinfo"))) return(NA_integer_)
  out <- tryCatch(
    system2("pdfinfo", path, stdout = TRUE, stderr = TRUE),
    error = function(e) character()
  )
  line <- grep("^Pages:", out, value = TRUE)
  if (!length(line)) return(NA_integer_)
  suppressWarnings(as.integer(trimws(sub("^Pages:", "", line[[1L]]))))
}

app_launch_figure_checks <- function(run_dirs, min_size_bytes = 1000L, check_pdf_pages = TRUE) {
  manifest_path <- file.path(run_dirs$tables, "figure_manifest.csv")
  if (!file.exists(manifest_path)) {
    return(app_launch_check_row("figures", "figure_manifest", FALSE, sprintf("Missing figure manifest: %s", manifest_path)))
  }
  manifest <- app_read_csv(manifest_path)
  if (!nrow(manifest)) {
    return(app_launch_check_row("figures", "figure_manifest_nonempty", FALSE, "Figure manifest has no rows."))
  }

  paths <- manifest$output_path
  abs_paths <- ifelse(grepl("^/", paths), paths, app_path(paths))
  exists_ok <- file.exists(abs_paths)
  sizes <- rep(NA_real_, length(abs_paths))
  sizes[exists_ok] <- file.info(abs_paths[exists_ok])$size
  size_ok <- exists_ok & is.finite(sizes) & sizes >= min_size_bytes

  rows <- list(
    app_launch_check_row(
      "figures",
      "figure_files_exist",
      all(exists_ok),
      if (all(exists_ok)) sprintf("%d figure files found", length(abs_paths)) else paste(paths[!exists_ok], collapse = "; ")
    ),
    app_launch_check_row(
      "figures",
      "figure_files_nontrivial",
      all(size_ok),
      if (all(size_ok)) sprintf("all figure files are at least %d bytes", min_size_bytes) else paste(paths[!size_ok], collapse = "; ")
    )
  )

  if (isTRUE(check_pdf_pages)) {
    pdf_paths <- abs_paths[tolower(tools::file_ext(abs_paths)) == "pdf" & exists_ok]
    pages <- vapply(pdf_paths, app_pdf_page_count, integer(1L))
    page_ok <- length(pdf_paths) > 0L && all(is.finite(pages) & pages >= 1L)
    rows[[length(rows) + 1L]] <- app_launch_check_row(
      "figures",
      "pdf_pages_readable",
      page_ok,
      if (page_ok) paste(sprintf("%s:%d", basename(pdf_paths), pages), collapse = "; ") else "At least one PDF page count could not be read."
    )
  }

  do.call(rbind, rows)
}

app_launch_prediction_checks <- function(run_dirs, cfg = NULL) {
  pred_path <- file.path(run_dirs$tables, "prediction_quantiles.csv")
  draw_path <- file.path(run_dirs$tables, "posterior_draw_predictions.csv")
  score_path <- file.path(run_dirs$tables, "score_summary.csv")
  fit_path <- file.path(run_dirs$tables, "fit_status.csv")
  final_launch <- !is.null(cfg) && isTRUE(cfg$execution$final_launch$enabled %||% FALSE)

  rows <- list()
  rows[[length(rows) + 1L]] <- app_launch_check_row("outputs", "prediction_table_exists", file.exists(pred_path), pred_path)
  rows[[length(rows) + 1L]] <- app_launch_check_row("outputs", "score_summary_exists", file.exists(score_path), score_path)
  rows[[length(rows) + 1L]] <- app_launch_check_row("outputs", "fit_status_exists", file.exists(fit_path), fit_path)
  if (!file.exists(pred_path) || !file.exists(score_path) || !file.exists(fit_path)) {
    return(do.call(rbind, rows))
  }

  pred <- app_read_csv(pred_path)
  score <- app_read_csv(score_path)
  fit_status <- app_read_csv(fit_path)
  required_pred <- c(
    "fit_id", "model_id", "model_family", "quantile_level", "qhat",
    "y_reference", "q_g_hat", "d_g_hat", "prediction_contract",
    "contract_version", "forecast_scope", "q_g_source",
    "discrepancy_feature_strategy", "prediction_unit",
    "posterior_draw_contract", "posterior_predictive_sampling",
    "beyond_issued_horizon",
    "origin_date", "target_date", "horizon"
  )
  missing_pred <- setdiff(required_pred, names(pred))
  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "outputs",
    "prediction_table_columns",
    !length(missing_pred),
    if (!length(missing_pred)) "required columns present" else paste(missing_pred, collapse = ", ")
  )
  if (!length(missing_pred)) {
    contract_ok <- tryCatch({
      app_validate_prediction_table_contract(pred, final_launch = final_launch)
      TRUE
    }, error = function(e) conditionMessage(e))
    rows[[length(rows) + 1L]] <- app_launch_check_row(
      "outputs",
      "prediction_contract_valid",
      identical(contract_ok, TRUE),
      if (identical(contract_ok, TRUE)) "prediction contract metadata and qhat identity are valid" else contract_ok
    )

    pred$qhat <- as.numeric(pred$qhat)
    pred$y_reference <- as.numeric(pred$y_reference)
    rows[[length(rows) + 1L]] <- app_launch_check_row(
      "outputs",
      "finite_predictions",
      nrow(pred) > 0L && all(is.finite(pred$qhat)) && all(is.finite(pred$y_reference)),
      sprintf("%d prediction rows", nrow(pred))
    )
    rows[[length(rows) + 1L]] <- app_launch_check_row(
      "outputs",
      "prediction_contract_recorded",
      all(nzchar(pred$prediction_contract)),
      paste(sort(unique(pred$prediction_contract)), collapse = "; ")
    )
  }

  if (isTRUE(final_launch) || file.exists(draw_path)) {
    rows[[length(rows) + 1L]] <- app_launch_check_row(
      "outputs",
      "posterior_draw_table_exists",
      file.exists(draw_path),
      draw_path,
      required = final_launch
    )
    if (file.exists(draw_path)) {
      draw <- app_read_csv(draw_path)
      draw_ok <- tryCatch({
        app_validate_posterior_draw_prediction_table(draw)
        TRUE
      }, error = function(e) conditionMessage(e))
      rows[[length(rows) + 1L]] <- app_launch_check_row(
        "outputs",
        "posterior_draw_contract_valid",
        identical(draw_ok, TRUE),
        if (identical(draw_ok, TRUE)) {
          sprintf("%d posterior-draw prediction rows satisfy q_y_draw = q_g_draw - d_g_draw", nrow(draw))
        } else {
          draw_ok
        },
        required = final_launch || file.exists(draw_path)
      )
    }
  }

  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "outputs",
    "score_summary_nonempty",
    nrow(score) > 0L && all(c("model_id", "check_loss_mean") %in% names(score)),
    sprintf("%d scored model rows", nrow(score))
  )
  failed_required <- fit_status$status == "failed" & app_as_bool_vec(fit_status$required)
  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "outputs",
    "required_fits_completed",
    !any(failed_required),
    if (!any(failed_required)) "no required fit failures" else paste(fit_status$fit_id[failed_required], collapse = "; ")
  )

  do.call(rbind, rows)
}

app_launch_manifest_checks <- function(cfg, run_dirs) {
  rows <- list()
  input_result <- tryCatch(
    app_validate_input_manifest(app_config_path(cfg, "input_manifest"), app_config_path(cfg, "schema"), require_files = TRUE),
    error = function(e) list(ok = FALSE, issues = conditionMessage(e))
  )
  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "inputs",
    "input_manifest_valid",
    isTRUE(input_result$ok),
    if (isTRUE(input_result$ok)) "input manifest matches registered files" else paste(input_result$issues, collapse = "; ")
  )

  qg_ok <- tryCatch({
    app_validate_quantile_grid(app_config_path(cfg, "quantile_grid"))
    TRUE
  }, error = function(e) conditionMessage(e))
  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "inputs",
    "quantile_grid_valid",
    identical(qg_ok, TRUE),
    if (identical(qg_ok, TRUE)) "enabled levels are valid" else qg_ok
  )

  mg <- NULL
  mg_ok <- tryCatch({
    mg <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
    app_validate_qdesn_model_grid_prior_contract(mg)
    TRUE
  }, error = function(e) conditionMessage(e))
  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "inputs",
    "model_grid_valid",
    identical(mg_ok, TRUE),
    if (identical(mg_ok, TRUE)) "model grid and Q-DESN prior contract are valid" else mg_ok
  )

  seed_check <- tryCatch({
    if (is.null(mg)) {
      mg <- app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema"))
    }
    report <- app_validate_qdesn_seed_contract(cfg, mg)
    detail <- if (!nrow(report)) {
      "no enabled Q-DESN seed rows to validate"
    } else {
      paste(sprintf(
        "%s: effective=%s reference=%s discrepancy=%s",
        report$fit_id,
        report$effective_reservoir_seed,
        report$reference_reservoir_seed,
        report$discrepancy_reservoir_seed
      ), collapse = "; ")
    }
    list(ok = TRUE, detail = detail)
  }, error = function(e) list(ok = FALSE, detail = conditionMessage(e)))
  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "inputs",
    "qdesn_seed_contract",
    isTRUE(seed_check$ok),
    seed_check$detail
  )

  used_files <- c(
    file.path(run_dirs$manifest, "input_manifest_used.csv"),
    file.path(run_dirs$manifest, "model_grid_used.csv"),
    file.path(run_dirs$manifest, "quantile_grid_used.csv"),
    file.path(run_dirs$manifest, "run_config.yaml"),
    file.path(run_dirs$manifest, "git_state.txt"),
    file.path(run_dirs$manifest, "session_info.txt")
  )
  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "provenance",
    "run_manifest_files_present",
    all(file.exists(used_files)),
    if (all(file.exists(used_files))) "run manifest files present" else paste(used_files[!file.exists(used_files)], collapse = "; ")
  )

  do.call(rbind, rows)
}

app_launch_engine_checks <- function(cfg) {
  required <- isTRUE(cfg$dependencies$fail_if_qdesn_engine_missing %||% TRUE)
  model_grid <- tryCatch(
    app_validate_model_grid(app_config_path(cfg, "model_grid"), app_config_path(cfg, "schema")),
    error = function(e) NULL
  )
  report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, model_grid),
    stop_on_failure = FALSE
  )
  rows <- list(
    app_launch_check_row("engine", "qdesn_engine_api", isTRUE(report$ok), report$message, required = required),
    app_launch_check_row(
      "engine",
      "qdesn_engine_sha_recorded",
      !is.na(report$repo_git_sha) && nzchar(report$repo_git_sha),
      report$repo_git_sha %||% "missing engine git SHA",
      required = required
    ),
    app_launch_check_row(
      "engine",
      "qdesn_engine_source_policy",
      isTRUE(report$source_policy_ok),
      report$source_policy_message %||% "missing source policy result",
      required = required
    )
  )
  if (!is.null(model_grid)) {
    support <- app_qdesn_discrepancy_inference_support(cfg, model_grid, report)
    if (nrow(support)) {
      fit_ready <- app_qdesn_inference_support_all_fit_ready(support, required_only = TRUE)
      rows[[length(rows) + 1L]] <- app_launch_check_row(
        "engine",
        "qdesn_discrepancy_required_fit_support",
        fit_ready,
        if (fit_ready) {
          "all required discrepancy fit rows are supported by the configured engine"
        } else {
          paste(support$fit_id[app_as_bool_vec(support$required) & !app_as_bool_vec(support$fit_supported)], collapse = "; ")
        },
        required = required && isTRUE(cfg$execution$final_launch$enabled %||% FALSE)
      )
    }
  }
  do.call(rbind, rows)
}

app_check_launch_readiness <- function(cfg, run_id, control = list()) {
  if (is.null(run_id) || !nzchar(as.character(run_id[[1L]]))) {
    stop("Launch preflight requires an existing --run_id to audit.", call. = FALSE)
  }
  run_dirs <- app_create_run_dirs(cfg, run_id = run_id)
  min_figure_size_bytes <- as.integer(control$min_figure_size_bytes %||% 1000L)
  check_pdf_pages <- app_as_bool(control$check_pdf_pages %||% TRUE)
  check_git <- app_as_bool(control$check_git %||% TRUE)

  rows <- list(
    app_launch_manifest_checks(cfg, run_dirs),
    app_launch_engine_checks(cfg),
    app_launch_stage_checks(run_dirs),
    app_launch_figure_checks(run_dirs, min_size_bytes = min_figure_size_bytes, check_pdf_pages = check_pdf_pages),
    app_launch_prediction_checks(run_dirs, cfg = cfg)
  )

  if (isTRUE(check_git)) {
    rows[[length(rows) + 1L]] <- app_git_clean_check(app_repo_root(), "article")
    rows[[length(rows) + 1L]] <- app_git_upstream_check(app_repo_root(), "article")
    repo_hint <- app_qdesn_engine_repo_hint(cfg)
    if (!is.na(repo_hint) && nzchar(repo_hint)) {
      rows[[length(rows) + 1L]] <- app_git_clean_check(repo_hint, "engine")
      rows[[length(rows) + 1L]] <- app_git_upstream_check(repo_hint, "engine")
    }
  }

  dry_run_flag <- isTRUE(cfg$execution$prelaunch$enabled %||% FALSE) ||
    isTRUE(cfg$execution$pilot$enabled %||% FALSE) ||
    grepl("pilot|dryrun|dry_run|prelaunch", run_id, ignore.case = TRUE)
  rows[[length(rows) + 1L]] <- app_launch_check_row(
    "boundary",
    "not_final_launch",
    dry_run_flag,
    if (dry_run_flag) "audited run is marked as a pilot or prelaunch dry run" else "run is not marked as prelaunch; verify before final launch",
    required = FALSE
  )

  report <- do.call(rbind, rows)
  rownames(report) <- NULL
  report
}

app_write_launch_readiness <- function(report, run_dirs) {
  app_write_csv(report, file.path(run_dirs$tables, "launch_readiness_report.csv"))
  required_failed <- report[report$required & report$status != "ok", , drop = FALSE]
  summary_lines <- c(
    "GloFAS Q-DESN launch-readiness report",
    sprintf("Run: %s", basename(run_dirs$run_dir)),
    sprintf("Required checks: %d", sum(report$required)),
    sprintf("Required failures: %d", nrow(required_failed)),
    "",
    if (nrow(required_failed)) {
      paste(sprintf("- [%s] %s: %s", required_failed$gate, required_failed$check, required_failed$detail), collapse = "\n")
    } else {
      "All required preflight checks passed. The final launch has not been executed by this stage."
    }
  )
  writeLines(summary_lines, file.path(run_dirs$tables, "launch_readiness_summary.txt"))
  invisible(required_failed)
}
