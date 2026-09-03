#!/usr/bin/env Rscript

repo_root <- normalizePath(
  file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])), "..", ".."),
  mustWork = TRUE
)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/engine_contract.R"))
source(app_path("application/R/model_contract.R"))
source(app_path("application/R/feature_contract.R"))
source(app_path("application/R/latent_path_runtime_backend.R"))
source(app_path("application/R/latent_path_checkpoint.R"))
source(app_path("application/R/latent_path_vb_al.R"))
source(app_path("application/R/glofas_constrained_median_screening.R"))

args <- app_parse_args(list(
  space = "application/config/glofas_constrained_median_screen_space_FR09_TEMPLATE.yaml",
  output_root = "",
  authorize_launch = FALSE,
  audit_only = FALSE
))

resolve_path <- function(path, must_work = FALSE) {
  if (grepl("^/", path)) normalizePath(path, mustWork = must_work) else app_resolve_path(path, must_work = must_work)
}

git_value <- function(...) {
  out <- system2("git", c("-C", repo_root, ...), stdout = TRUE, stderr = TRUE)
  if (!length(out) || any(grepl("^fatal:", out))) NA_character_ else out[[1L]]
}

audit_only <- app_as_bool(args$audit_only)
space_path <- resolve_path(args$space, must_work = TRUE)
space <- app_glofas_median_screen_validate_space(app_read_yaml(space_path), allow_empty = audit_only)
authorized <- app_as_bool(args$authorize_launch) && app_as_bool(space$launch_authorized %||% FALSE)
if (audit_only && app_as_bool(args$authorize_launch)) {
  stop("--audit_only true cannot be combined with --authorize_launch true.", call. = FALSE)
}
if (app_as_bool(args$authorize_launch) && !app_as_bool(space$launch_authorized %||% FALSE)) {
  stop("--authorize_launch true requires launch_authorized: true in the reviewed screening-space file.", call. = FALSE)
}

output_root_value <- as.character(args$output_root %||% "")
if (!nzchar(output_root_value)) output_root_value <- as.character(space$output_root %||% "")
if (!nzchar(output_root_value)) {
  output_root_value <- file.path("local_trackers", "runtime_configs", space$screen_id)
}
output_root <- resolve_path(output_root_value, must_work = FALSE)
owned_root <- normalizePath(app_path("local_trackers", "runtime_configs"), mustWork = FALSE)
prefix <- paste0(owned_root, .Platform$file.sep)
if (!identical(output_root, owned_root) && !startsWith(output_root, prefix)) {
  stop("Screening output_root must remain under local_trackers/runtime_configs.", call. = FALSE)
}
for (name in c("candidates", "runs", "logs", "scores", "status", "common_cache", "cleanup")) {
  app_ensure_dir(file.path(output_root, name))
}

base <- space$base %||% list()
baseline_contract_ref <- base$baseline_contract %||% NULL
baseline_verification <- if (!is.null(baseline_contract_ref) && nzchar(as.character(baseline_contract_ref[[1L]]))) {
  app_glofas_median_screen_verify_baseline(as.character(baseline_contract_ref[[1L]]))
} else NULL

verified_path <- function(name, legacy_value = NULL, required = TRUE) {
  verified <- if (!is.null(baseline_verification)) baseline_verification$artifacts[[name]]$path else NULL
  declared <- if (!is.null(legacy_value) && nzchar(as.character(legacy_value[[1L]]))) {
    resolve_path(as.character(legacy_value[[1L]]), must_work = required)
  } else NULL
  if (!is.null(verified) && !is.null(declared) && !identical(verified, declared)) {
    stop(sprintf("base.%s conflicts with the verified baseline contract.", name), call. = FALSE)
  }
  value <- verified %||% declared
  if (required && is.null(value)) stop(sprintf("No verified path is available for base artifact '%s'.", name), call. = FALSE)
  value
}

base_config_path <- verified_path("base_config", base$config)
base_model_grid_path <- verified_path("base_model_grid", base$model_grid)
base_cfg <- if (!is.null(baseline_verification)) baseline_verification$base_cfg else app_read_config(base_config_path)
base_grid <- if (!is.null(baseline_verification)) baseline_verification$model_grid else app_read_csv(base_model_grid_path)
if (!is.null(baseline_verification)) {
  expected_candidate <- as.character(baseline_verification$contract$candidate_id[[1L]])
  declared_candidate <- as.character(base$candidate_id %||% expected_candidate)
  if (!identical(declared_candidate, expected_candidate)) {
    stop("base.candidate_id conflicts with the verified baseline contract.", call. = FALSE)
  }
  space$baseline <- baseline_verification$metrics
}

source_panel <- file.path(app_config_path(base_cfg, "cache"), "application_panel.rds")
target_panel <- file.path(output_root, "common_cache", "application_panel.rds")
if (!file.exists(source_panel)) stop(sprintf("Verified baseline application panel is missing: %s.", source_panel), call. = FALSE)
if (!file.exists(target_panel) && !file.copy(source_panel, target_panel, copy.mode = TRUE, copy.date = TRUE)) {
  stop("Could not copy the verified application panel into the screening cache.", call. = FALSE)
}
source_panel_sha <- app_sha256_file(source_panel)
target_panel_sha <- app_sha256_file(target_panel)
if (!identical(source_panel_sha, target_panel_sha)) {
  stop("The screening application-panel copy failed its SHA-256 check.", call. = FALSE)
}
app_write_csv(data.frame(
  artifact = "application_panel.rds",
  source_path = normalizePath(source_panel, mustWork = TRUE),
  target_path = normalizePath(target_panel, mustWork = TRUE),
  sha256 = target_panel_sha,
  stringsAsFactors = FALSE
), file.path(output_root, "common_cache_contract.csv"))

engine_report <- app_check_qdesn_engine_api(
  base_cfg,
  require_discrepancy = app_qdesn_engine_requires_discrepancy_export(base_cfg, base_grid),
  stop_on_failure = TRUE
)
if (!is.null(baseline_verification)) {
  expected_engine <- baseline_verification$contract$engine %||% list()
  engine_checks <- c(
    identical(as.character(engine_report$repo_hint), as.character(expected_engine$repo_hint)),
    identical(as.character(engine_report$repo_branch), as.character(expected_engine$required_branch)),
    identical(as.character(engine_report$repo_git_sha), as.character(expected_engine$required_commit)),
    identical(as.character(engine_report$load_mode), as.character(expected_engine$load_mode))
  )
  if (!all(engine_checks)) stop("Resolved Q-DESN engine does not match the verified FR09 engine contract.", call. = FALSE)
}
app_write_csv(app_qdesn_engine_contract_row(engine_report), file.path(output_root, "qdesn_engine_contract.csv"))
if (!is.null(baseline_verification)) {
  app_write_csv(baseline_verification$audit, file.path(output_root, "baseline_artifact_audit.csv"))
  app_write_yaml(baseline_verification$contract$current_values, file.path(output_root, "current_baseline_values.yaml"))
}

quantile_grid <- data.frame(
  quantile_id = "p50",
  quantile_level = 0.5,
  role = "median_screen",
  enabled = TRUE,
  stringsAsFactors = FALSE
)
quantile_grid_path <- file.path(output_root, "quantile_grid_p50.csv")
app_write_csv(quantile_grid, quantile_grid_path)

quantile <- suppressWarnings(as.numeric(base_grid$quantile_level))
qdesn <- base_grid$model_family == "qdesn_glofas_discrepancy" & abs(quantile - 0.5) < 1e-12
raw <- base_grid$model_family == "raw_glofas" & (is.na(quantile) | abs(quantile - 0.5) < 1e-12)
if (sum(qdesn) != 1L) stop("Base model grid must contain exactly one p50 Q-DESN discrepancy row.", call. = FALSE)
if (sum(raw) > 1L) stop("Base model grid contains multiple p50 raw-GloFAS rows.", call. = FALSE)
base_grid <- base_grid[qdesn | raw, , drop = FALSE]

source_fit <- base$source_fit_object %||% NULL
source_fit_path <- verified_path("source_fit", source_fit, required = FALSE)
source_fit_sha <- if (!is.null(source_fit_path)) app_sha256_file(source_fit_path) else NA_character_
declared_fit_sha <- as.character(base$source_fit_sha256 %||% "")
if (nzchar(declared_fit_sha) && !identical(tolower(declared_fit_sha), tolower(source_fit_sha))) {
  stop("Base warm-start fit SHA-256 does not match the source object.", call. = FALSE)
}
source_contract_raw <- if (!is.null(baseline_verification)) {
  baseline_verification$source_contract
} else base$source_contract %||% NULL
source_contract_origin <- "none"
source_contract <- if (is.character(source_contract_raw) && length(source_contract_raw) == 1L) {
  source_contract_origin <- "explicit_path"
  app_latent_path_read_warm_start_contract(resolve_path(source_contract_raw, must_work = TRUE))
} else {
  if (!is.null(source_contract_raw)) {
    source_contract_origin <- if (!is.null(baseline_verification)) "verified_baseline_contract" else "explicit_inline"
  }
  source_contract_raw
}
if (is.null(source_contract) && !is.null(source_fit_path)) {
  source_contract <- app_latent_path_warm_start_contract_from_fit(source_fit_path)
  if (!is.null(source_contract)) source_contract_origin <- "embedded_in_source_fit"
}
source_contract_hash <- if (!is.null(source_contract)) {
  app_latent_path_contract_hash(source_contract, "source_contract_")
} else NA_character_
if (!is.null(source_contract)) {
  app_write_yaml(source_contract, file.path(output_root, "source_warm_start_contract.yaml"))
}
space$base$config <- base_config_path
space$base$model_grid <- base_model_grid_path
space$base$source_fit_object <- source_fit_path
space$base$source_fit_sha256 <- source_fit_sha

if (audit_only) {
  app_write_yaml(space, file.path(output_root, "screening_space_snapshot.yaml"))
  app_write_git_state(file.path(output_root, "git_state.txt"))
  app_write_session_info(file.path(output_root, "session_info.txt"))
  provenance <- data.frame(
    field = c(
      "audited_at", "audit_only", "article_repo", "article_branch", "article_head",
      "origin_main", "space_path", "space_sha256", "baseline_contract",
      "baseline_contract_sha256", "base_config", "base_config_sha256",
      "base_model_grid", "base_model_grid_sha256", "source_fit_sha256",
      "source_contract_sha256", "source_contract_origin", "engine_repo",
      "engine_branch", "engine_commit", "launch_authorized", "candidate_count"
    ),
    value = c(
      format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), "TRUE", repo_root,
      git_value("rev-parse", "--abbrev-ref", "HEAD"), git_value("rev-parse", "HEAD"),
      git_value("rev-parse", "origin/main"), space_path, app_sha256_file(space_path),
      baseline_verification$contract_path %||% "",
      baseline_verification$contract_sha256 %||% "", base_config_path,
      app_sha256_file(base_config_path), base_model_grid_path,
      app_sha256_file(base_model_grid_path), source_fit_sha, source_contract_hash,
      source_contract_origin, engine_report$repo_hint, engine_report$repo_branch,
      engine_report$repo_git_sha, "FALSE", "0"
    ),
    stringsAsFactors = FALSE
  )
  app_write_csv(provenance, file.path(output_root, "provenance.csv"))
  launch_path <- file.path(output_root, "launch_screen.sh")
  writeLines(c(
    "#!/usr/bin/env bash", "set -euo pipefail", "",
    "echo 'Launch blocked: investigator-reviewed ranges have not been supplied.' >&2; exit 2"
  ), launch_path)
  Sys.chmod(launch_path, mode = "0750")
  cat(sprintf("Verified FR09 baseline and engine; audit-only preparation wrote %s.\n", output_root))
  quit(save = "no", status = 0L)
}

manifest <- app_glofas_median_screen_candidate_manifest(space)

inference_override <- (space$fixed %||% list())$inference %||% list()
preflight <- space$reservoir_preflight %||% list()
preflight_enabled <- app_as_bool(preflight$enabled %||% FALSE)
preflight_target <- match.arg(
  as.character(preflight$diagnostic_target %||% "reservoir"),
  c("layers", "reservoir", "readout", "both")
)
preflight_reject_decision <- match.arg(
  as.character(preflight$reject_decision %||% "reject"),
  c("reject", "none")
)
runtime_rows <- list()
candidate_contract_rows <- list()
warm_source_cache <- new.env(parent = emptyenv())
for (i in seq_len(nrow(manifest))) {
  row <- manifest[i, , drop = FALSE]
  candidate_id <- as.character(row$candidate_id[[1L]])
  candidate_root <- file.path(output_root, "candidates", candidate_id)
  app_ensure_dir(candidate_root)

  cfg <- app_glofas_median_screen_apply_candidate(base_cfg, row)
  cfg$application_name <- paste0("glofas_constrained_median_screen_", candidate_id)
  cfg$description <- sprintf("Constrained p50 screening candidate %s", candidate_id)
  cfg$paths$model_grid <- file.path(candidate_root, "model_grid_p50.csv")
  cfg$paths$quantile_grid <- quantile_grid_path
  cfg$paths$cache <- file.path(output_root, "common_cache")
  cfg$paths$runs <- file.path(output_root, "runs")
  cfg$paths$logs <- file.path(output_root, "logs")
  cfg$paths$generated_outputs <- file.path(output_root, "generated")
  cfg$inference$vb_ld <- app_qdesn_deep_merge(cfg$inference$vb_ld %||% list(), inference_override)
  linked_contract <- app_glofas_median_screen_linked_desn_contract(cfg)
  require_linked_default <- app_as_bool(
    (space$contracts %||% list())$require_same_desn_by_default %||%
      (space$linked_factorial %||% list())$require_same_desn %||%
      FALSE
  )
  require_linked <- app_as_bool(
    app_glofas_median_screen_row_value(row, "require_linked_desn", require_linked_default)
  )
  if (require_linked && !isTRUE(linked_contract$pass)) {
    stop(sprintf("Candidate %s violates the required shared DESN specification contract.", candidate_id), call. = FALSE)
  }
  cfg$post_analysis$run_after_outputs <- TRUE
  cfg$post_analysis$recent_history_n <- 200L
  cfg$post_analysis$storage$write_history_draws_rds <- FALSE
  cfg$post_analysis$storage$write_history_draws_csv <- FALSE
  cfg$execution$artifacts <- app_qdesn_deep_merge(
    cfg$execution$artifacts %||% list(),
    list(
      retain_fit_object = TRUE,
      retain_design_object = TRUE,
      retain_prediction_design_object = FALSE,
      retain_reference_fit_object = FALSE
    )
  )
  app_validate_fit_artifact_policy(cfg)
  cfg$execution$final_launch$enabled <- authorized
  cfg$execution$final_launch$note <- if (authorized) {
    sprintf("Explicitly authorized constrained p50 screen %s", space$screen_id)
  } else {
    "Prepared only; launch is not authorized"
  }

  candidate_source_fit_path <- source_fit_path
  candidate_source_cfg <- base_cfg
  candidate_source_contract <- source_contract
  candidate_source_contract_origin <- source_contract_origin
  candidate_source_cached <- NULL
  warm_start_policy <- tolower(as.character(app_glofas_median_screen_row_value(row, "warm_start_policy", "auto")))
  row_source_fit <- as.character(app_glofas_median_screen_row_value(row, "warm_start_source_fit_object", ""))
  row_source_config <- as.character(app_glofas_median_screen_row_value(row, "warm_start_source_config", ""))
  if (identical(warm_start_policy, "cold")) {
    if (nzchar(row_source_fit) || nzchar(row_source_config)) {
      stop(sprintf("Candidate %s requests a cold start but supplies warm-start artifacts.", candidate_id), call. = FALSE)
    }
    candidate_source_fit_path <- NULL
    candidate_source_contract <- NULL
    candidate_source_contract_origin <- "disabled_by_candidate_policy"
  } else if (nzchar(row_source_fit)) {
    candidate_source_fit_path <- resolve_path(row_source_fit, must_work = TRUE)
    if (!nzchar(row_source_config)) {
      stop(sprintf("Candidate %s supplies a warm-start fit without its source config.", candidate_id), call. = FALSE)
    }
    candidate_source_config_path <- resolve_path(row_source_config, must_work = TRUE)
    cache_key <- paste(candidate_source_fit_path, candidate_source_config_path, sep = "\r")
    candidate_source_cached <- get0(cache_key, envir = warm_source_cache, inherits = FALSE)
    if (is.null(candidate_source_cached)) {
      candidate_source_cached <- list(
        cfg = app_read_config(candidate_source_config_path),
        contract = app_latent_path_warm_start_contract_from_fit(candidate_source_fit_path),
        fit_sha256 = app_sha256_file(candidate_source_fit_path)
      )
      if (is.null(candidate_source_cached$contract)) {
        stop(sprintf("Candidate %s source fit lacks a semantic warm-start contract.", candidate_id), call. = FALSE)
      }
      candidate_source_cached$contract_sha256 <- app_latent_path_contract_hash(
        candidate_source_cached$contract,
        "source_contract_"
      )
      assign(cache_key, candidate_source_cached, envir = warm_source_cache)
    }
    candidate_source_cfg <- candidate_source_cached$cfg
    candidate_source_contract <- candidate_source_cached$contract
    candidate_source_contract_origin <- "embedded_in_candidate_source_fit"
  } else if (nzchar(row_source_config)) {
    stop(sprintf("Candidate %s supplies a warm-start source config without a fit object.", candidate_id), call. = FALSE)
  }
  candidate_source_sha <- if (!is.null(candidate_source_cached)) {
    candidate_source_cached$fit_sha256
  } else if (!is.null(candidate_source_fit_path)) {
    app_sha256_file(candidate_source_fit_path)
  } else NA_character_
  candidate_source_contract_hash <- if (!is.null(candidate_source_cached)) {
    candidate_source_cached$contract_sha256
  } else if (!is.null(candidate_source_contract)) {
    app_latent_path_contract_hash(candidate_source_contract, "source_contract_")
  } else NA_character_

  warm <- app_glofas_median_screen_warm_start_plan(
    candidate_source_cfg,
    cfg,
    source_fit = candidate_source_fit_path,
    source_contract = candidate_source_contract
  )
  if (isTRUE(warm$enabled)) {
    cfg$inference$vb_ld$warm_start <- list(
      enabled = TRUE,
      fit_object = candidate_source_fit_path,
      use_theta = warm$use_theta,
      use_future = warm$use_future,
      use_sigma = warm$use_sigma,
      require_theta = warm$use_theta,
      require_future = warm$use_future,
      require_sigma = FALSE,
      require_contract = TRUE,
      compatibility_mode = warm$compatibility_mode,
      source_contract = candidate_source_contract,
      covariance_jitter = 1e-8
    )
  } else {
    cfg$inference$vb_ld$warm_start <- list(enabled = FALSE)
  }

  candidate_engine_report <- app_check_qdesn_engine_api(
    cfg,
    require_discrepancy = app_qdesn_engine_requires_discrepancy_export(cfg, base_grid),
    stop_on_failure = TRUE
  )
  if (!identical(candidate_engine_report$repo_git_sha, engine_report$repo_git_sha) ||
      !identical(candidate_engine_report$repo_branch, engine_report$repo_branch) ||
      !identical(candidate_engine_report$repo_hint, engine_report$repo_hint)) {
    stop(sprintf("Candidate %s changed the verified Q-DESN engine contract.", candidate_id), call. = FALSE)
  }

  model_grid <- base_grid
  q_idx <- model_grid$model_family == "qdesn_glofas_discrepancy"
  raw_idx <- model_grid$model_family == "raw_glofas"
  fit_id <- paste0("qdesn_constrained_median_", candidate_id, "_p50")
  model_grid$fit_id[q_idx] <- fit_id
  model_grid$model_id[q_idx] <- fit_id
  model_grid$quantile_level[q_idx] <- 0.5
  model_grid$notes[q_idx] <- sprintf("Constrained p50 candidate %s", candidate_id)
  if (any(raw_idx)) {
    model_grid$fit_id[raw_idx] <- paste0("raw_glofas_", candidate_id, "_p50")
    model_grid$model_id[raw_idx] <- paste0("raw_glofas_", candidate_id, "_p50")
    model_grid$quantile_level[raw_idx] <- 0.5
  }
  model_grid$config_hash <- "RUNTIME_CONFIG_HASH_RECORDED_IN_MANIFEST"
  app_write_csv(model_grid, cfg$paths$model_grid)

  config_path <- file.path(candidate_root, "config_p50.yaml")
  app_write_yaml(cfg, config_path)
  run_id <- paste0(space$screen_id, "_", candidate_id)
  preflight_run_id <- paste0(run_id, "__reservoir_preflight")
  preflight_summary_path <- file.path(
    output_root, "runs", preflight_run_id, "tables",
    "reservoir_screening_architecture_summary.csv"
  )
  runtime_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    candidate_set = row$candidate_set[[1L]],
    priority = as.integer(row$priority[[1L]]),
    config_path = config_path,
    config_sha256 = app_sha256_file(config_path),
    model_grid_path = cfg$paths$model_grid,
    model_grid_sha256 = app_sha256_file(cfg$paths$model_grid),
    run_id = run_id,
    run_dir = file.path(output_root, "runs", run_id),
    log_path = file.path(output_root, "logs", paste0(candidate_id, ".log")),
    warm_start_enabled = isTRUE(warm$enabled),
    warm_start_policy = warm_start_policy,
    warm_start_compatibility_mode = warm$compatibility_mode,
    warm_start_requires_cold_confirmation = isTRUE(warm$requires_cold_confirmation),
    warm_start_reason = warm$reason,
    warm_start_source_fit_object = candidate_source_fit_path %||% "",
    warm_start_source_sha256 = if (is.na(candidate_source_sha)) "" else candidate_source_sha,
    source_contract_sha256 = candidate_source_contract_hash,
    source_contract_origin = candidate_source_contract_origin,
    source_candidate_id = as.character(app_glofas_median_screen_row_value(row, "source_candidate_id", "")),
    candidate_role = as.character(app_glofas_median_screen_row_value(row, "candidate_role", row$candidate_set[[1L]])),
    reservoir_preflight_enabled = preflight_enabled,
    reservoir_preflight_target = preflight_target,
    reservoir_preflight_reject_decision = preflight_reject_decision,
    reservoir_preflight_run_id = preflight_run_id,
    reservoir_preflight_summary_path = preflight_summary_path,
    reservoir_preflight_max_corr_features_full = as.integer(preflight$max_corr_features_full %||% 5000L),
    reservoir_preflight_corr_block_size = as.integer(preflight$corr_block_size %||% 512L),
    reservoir_preflight_spectral_radius_exact_max_n = as.integer(preflight$spectral_radius_exact_max_n %||% 512L),
    reservoir_preflight_cheap_validation = app_as_bool(preflight$cheap_validation %||% FALSE),
    qdesn_engine_repo = candidate_engine_report$repo_hint,
    qdesn_engine_branch = candidate_engine_report$repo_branch,
    qdesn_engine_commit = candidate_engine_report$repo_git_sha,
    reference_block_config_hash = app_qdesn_block_config_hash(cfg, "reference"),
    discrepancy_block_config_hash = app_qdesn_block_config_hash(cfg, "discrepancy"),
    launch_authorized = authorized,
    status = if (authorized) "prepared_authorized" else "prepared_not_authorized",
    stringsAsFactors = FALSE
  )
  candidate_contract_rows[[i]] <- data.frame(
    candidate_id = candidate_id,
    reference_design_hash = app_glofas_median_screen_design_signature(cfg, "reference"),
    discrepancy_design_hash = app_glofas_median_screen_design_signature(cfg, "discrepancy"),
    reference_layout_hash = app_glofas_median_screen_layout_signature(cfg, "reference"),
    discrepancy_layout_hash = app_glofas_median_screen_layout_signature(cfg, "discrepancy"),
    linked_desn_contract_required = require_linked,
    linked_desn_contract_pass = linked_contract$pass,
    linked_desn_reference_hash = linked_contract$reference_hash,
    linked_desn_discrepancy_hash = linked_contract$discrepancy_hash,
    reference_seed = linked_contract$reference_seed,
    discrepancy_seed = linked_contract$discrepancy_seed,
    warm_start_policy = warm_start_policy,
    candidate_role = as.character(app_glofas_median_screen_row_value(row, "candidate_role", row$candidate_set[[1L]])),
    common_washout = app_qdesn_common_washout(cfg),
    full7_required_for_distributional_crps = TRUE,
    auto_launch_full7 = FALSE,
    stringsAsFactors = FALSE
  )
}

runtime_manifest <- app_bind_rows_fill(runtime_rows)
app_write_csv(manifest, file.path(output_root, "candidate_manifest.csv"))
app_write_csv(runtime_manifest, file.path(output_root, "runtime_manifest.csv"))
app_write_csv(app_bind_rows_fill(candidate_contract_rows), file.path(output_root, "candidate_contracts.csv"))
app_write_yaml(space, file.path(output_root, "screening_space_snapshot.yaml"))
app_write_git_state(file.path(output_root, "git_state.txt"))
app_write_session_info(file.path(output_root, "session_info.txt"))

provenance <- data.frame(
  field = c(
    "prepared_at", "article_repo", "article_branch", "article_head", "origin_main",
    "space_path", "space_sha256", "base_config", "base_config_sha256",
    "base_model_grid", "base_model_grid_sha256", "source_fit_sha256",
    "source_contract_sha256", "source_contract_origin", "baseline_contract",
    "baseline_contract_sha256", "engine_repo", "engine_branch", "engine_commit",
    "launch_authorized", "candidate_count"
  ),
  value = c(
    format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), repo_root,
    git_value("rev-parse", "--abbrev-ref", "HEAD"), git_value("rev-parse", "HEAD"),
    git_value("rev-parse", "origin/main"), space_path, app_sha256_file(space_path),
    base_config_path, app_sha256_file(base_config_path), base_model_grid_path,
    app_sha256_file(base_model_grid_path), source_fit_sha, source_contract_hash,
    source_contract_origin, baseline_verification$contract_path %||% "",
    baseline_verification$contract_sha256 %||% "", engine_report$repo_hint,
    engine_report$repo_branch, engine_report$repo_git_sha,
    as.character(authorized), as.character(nrow(runtime_manifest))
  ),
  stringsAsFactors = FALSE
)
app_write_csv(provenance, file.path(output_root, "provenance.csv"))

scheduler <- space$scheduler %||% list()
finalization <- space$finalization %||% list()
cores <- paste(unlist(scheduler$cores %||% c(0L, 1L, 2L, 3L), use.names = FALSE), collapse = ",")
launch_lines <- c(
  "#!/usr/bin/env bash",
  "set -euo pipefail",
  "",
  if (authorized) {
    sprintf(
      paste(
        "bash application/scripts/glofas_constrained_median_screen_orchestrate.sh",
        "%s %s %d %s %.6g %.6g %.6g %s %s"
      ),
      shQuote(output_root),
      shQuote(file.path(output_root, "runtime_manifest.csv")),
      as.integer(scheduler$max_parallel %||% 4L),
      shQuote(cores),
      as.numeric(scheduler$max_load %||% 58),
      as.numeric(scheduler$min_memory_gb %||% 48),
      as.numeric(scheduler$min_disk_gb %||% 120),
      if (app_as_bool(finalization$run_after_scheduler %||% FALSE)) "true" else "false",
      if (app_as_bool(finalization$cleanup_after_complete_batch %||% FALSE)) "true" else "false"
    )
  } else {
    "echo 'Launch blocked: regenerate with reviewed launch_authorized: true and --authorize_launch true.' >&2; exit 2"
  }
)
launch_path <- file.path(output_root, "launch_screen.sh")
writeLines(launch_lines, launch_path)
Sys.chmod(launch_path, mode = "0750")

cat(file.path(output_root, "runtime_manifest.csv"), "\n")
cat(sprintf("Prepared %d candidates; launch_authorized=%s.\n", nrow(runtime_manifest), authorized))
