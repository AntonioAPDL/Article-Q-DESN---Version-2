#!/usr/bin/env Rscript
# Purpose: promote storage-light application outputs into article-facing
# tables/ and figures/ paths after launch-readiness checks pass.
# Inputs: completed run directory identified by --run_id.
# Outputs: promoted tables/figures plus a promotion manifest with hashes.
# Failure behavior: stops if required launch-readiness checks failed.

repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "application/R/00_packages.R"))
app_set_repo_root(repo_root)
source(app_path("application/R/artifact_hygiene.R"))
source(app_path("application/R/promote_application_outputs.R"))

args <- app_parse_args(list(
  config = "application/config/glofas_latent_path_al_vb_dec25_main.yaml",
  run_id = NULL,
  output_slug = NULL,
  allow_required_failures = FALSE,
  include_post_fit_figures = TRUE,
  include_provenance_snapshots = TRUE,
  allow_ignored_config = FALSE
))

if (is.null(args$run_id) || !nzchar(as.character(args$run_id))) {
  stop("08_promote_application_outputs.R requires --run_id for a completed run.", call. = FALSE)
}

cfg <- app_read_config(app_path(args$config))
app_assert_promotion_config_allowed(
  cfg,
  cfg$.__config_path__,
  allow_ignored_config = args$allow_ignored_config
)
run_dirs <- app_create_run_dirs(cfg, run_id = args$run_id)
slug <- as.character(args$output_slug %||% args$run_id)[[1L]]
slug <- gsub("[^A-Za-z0-9_.-]+", "_", slug)

readiness_path <- file.path(run_dirs$tables, "launch_readiness_report.csv")
if (!file.exists(readiness_path)) {
  stop(sprintf("Missing launch-readiness report: %s", readiness_path), call. = FALSE)
}
readiness <- app_read_csv(readiness_path)
required_failed <- readiness[app_as_bool_vec(readiness$required) & readiness$status != "ok", , drop = FALSE]
if (nrow(required_failed) && !app_as_bool(args$allow_required_failures)) {
  stop(
    sprintf(
      "Refusing to promote %s because %d required launch-readiness checks failed.",
      args$run_id,
      nrow(required_failed)
    ),
    call. = FALSE
  )
}

generated_dir <- file.path(app_config_path(cfg, "generated_outputs"), basename(run_dirs$run_dir))
article_tables_dir <- app_path(cfg$paths$promoted_tables %||% "tables")
article_figures_dir <- app_path(cfg$paths$promoted_figures %||% "figures")

table_map <- data.frame(
  role = c(
    "score_summary_tex",
    "score_summary_csv",
    "post_fit_metrics_by_model",
    "post_fit_metrics_by_horizon",
    "post_fit_forecast_window_band_check",
    "post_fit_parameter_summary",
    "post_fit_trace_summary",
    "launch_readiness_report",
    "launch_readiness_summary"
  ),
  source = c(
    file.path(generated_dir, "glofas_application_score_summary.tex"),
    file.path(run_dirs$tables, "score_summary.csv"),
    file.path(run_dirs$tables, "post_fit_metrics_by_model.csv"),
    file.path(run_dirs$tables, "post_fit_metrics_by_horizon.csv"),
    file.path(run_dirs$tables, "post_fit_forecast_window_band_check.csv"),
    file.path(run_dirs$tables, "post_fit_parameter_summary.csv"),
    file.path(run_dirs$tables, "post_fit_trace_summary.csv"),
    file.path(run_dirs$tables, "launch_readiness_report.csv"),
    file.path(run_dirs$tables, "launch_readiness_summary.txt")
  ),
  dest = c(
    file.path(article_tables_dir, sprintf("glofas_application_score_summary__%s.tex", slug)),
    file.path(article_tables_dir, sprintf("glofas_application_score_summary__%s.csv", slug)),
    file.path(article_tables_dir, sprintf("glofas_application_post_fit_metrics_by_model__%s.csv", slug)),
    file.path(article_tables_dir, sprintf("glofas_application_post_fit_metrics_by_horizon__%s.csv", slug)),
    file.path(article_tables_dir, sprintf("glofas_application_forecast_window_band_check__%s.csv", slug)),
    file.path(article_tables_dir, sprintf("glofas_application_post_fit_parameter_summary__%s.csv", slug)),
    file.path(article_tables_dir, sprintf("glofas_application_post_fit_trace_summary__%s.csv", slug)),
    file.path(article_tables_dir, sprintf("glofas_application_launch_readiness_report__%s.csv", slug)),
    file.path(article_tables_dir, sprintf("glofas_application_launch_readiness_summary__%s.txt", slug))
  ),
  storage_class = "article_table",
  required = TRUE,
  stringsAsFactors = FALSE
)

generated_figures <- c(
  discrepancy_corrected_quantile_paths = file.path(generated_dir, "figures", "glofas_qdesn_discrepancy_corrected_quantile_paths.pdf"),
  discrepancy_draws_by_horizon = file.path(generated_dir, "figures", "glofas_qdesn_discrepancy_draws_by_horizon.pdf")
)
figure_map <- data.frame(
  role = names(generated_figures),
  source = unname(generated_figures),
  dest = file.path(
    article_figures_dir,
    "glofas_application",
    sprintf("%s__%s.pdf", tools::file_path_sans_ext(basename(unname(generated_figures))), slug)
  ),
  storage_class = "article_figure",
  required = TRUE,
  stringsAsFactors = FALSE
)

if (app_as_bool(args$include_post_fit_figures)) {
  post_fit_sources <- sort(list.files(
    file.path(run_dirs$figures, "post_fit_analysis"),
    pattern = "[.]pdf$",
    full.names = TRUE
  ))
  if (length(post_fit_sources)) {
    post_fit_map <- data.frame(
      role = paste0("post_fit_", tools::file_path_sans_ext(basename(post_fit_sources))),
      source = post_fit_sources,
      dest = file.path(
        article_figures_dir,
        "glofas_application",
        "post_fit",
        sprintf("%s__%s.pdf", tools::file_path_sans_ext(basename(post_fit_sources)), slug)
      ),
      storage_class = "post_fit_figure",
      required = TRUE,
      stringsAsFactors = FALSE
    )
    figure_map <- rbind(figure_map, post_fit_map)
  }
}

promote_map <- rbind(table_map, figure_map)
if (app_as_bool(args$include_provenance_snapshots)) {
  promote_map <- rbind(
    promote_map,
    app_build_promotion_provenance_map(run_dirs, article_tables_dir, slug)
  )
}
promote_map$source <- normalizePath(promote_map$source, mustWork = FALSE)
if (!"required" %in% names(promote_map)) promote_map$required <- TRUE
missing <- promote_map[app_as_bool_vec(promote_map$required) & !file.exists(promote_map$source), , drop = FALSE]
if (nrow(missing)) {
  stop(sprintf("Missing promotion source files: %s", paste(missing$source, collapse = "; ")), call. = FALSE)
}
promote_map <- promote_map[file.exists(promote_map$source), , drop = FALSE]

for (dir in unique(dirname(promote_map$dest))) app_ensure_dir(dir)
for (i in seq_len(nrow(promote_map))) {
  ok <- file.copy(promote_map$source[[i]], promote_map$dest[[i]], overwrite = TRUE, copy.date = TRUE)
  if (!isTRUE(ok)) stop(sprintf("Failed to promote %s", promote_map$source[[i]]), call. = FALSE)
}

app_promotion_single_value <- function(values, label, source_path) {
  values <- unique(trimws(as.character(values)))
  values <- values[!is.na(values) & nzchar(values) & values != "NA"]
  if (!length(values)) return(NA_character_)
  if (length(values) > 1L) {
    stop(
      sprintf("Multiple %s values found in %s: %s", label, source_path, paste(values, collapse = ", ")),
      call. = FALSE
    )
  }
  values[[1L]]
}

app_promotion_engine_sha <- function(run_dirs, readiness) {
  post_analysis_manifest_path <- file.path(run_dirs$tables, "post_analysis_manifest.csv")
  if (file.exists(post_analysis_manifest_path)) {
    post_analysis_manifest <- app_read_csv(post_analysis_manifest_path)
    if ("engine_repo_sha" %in% names(post_analysis_manifest) && nrow(post_analysis_manifest)) {
      sha <- app_promotion_single_value(
        post_analysis_manifest$engine_repo_sha,
        "engine_repo_sha",
        post_analysis_manifest_path
      )
      if (!is.na(sha)) {
        return(list(
          sha = sha,
          source = normalizePath(post_analysis_manifest_path, mustWork = FALSE),
          field = "engine_repo_sha"
        ))
      }
    }
  }

  if (all(c("check", "detail") %in% names(readiness))) {
    engine_rows <- readiness[readiness$check == "qdesn_engine_sha_recorded", , drop = FALSE]
    if (nrow(engine_rows)) {
      sha <- app_promotion_single_value(engine_rows$detail, "qdesn_engine_sha_recorded detail", readiness_path)
      if (!is.na(sha)) {
        return(list(
          sha = sha,
          source = normalizePath(readiness_path, mustWork = FALSE),
          field = "detail"
        ))
      }
    }
  }

  engine_contract_path <- file.path(run_dirs$manifest, "qdesn_engine_contract.csv")
  if (file.exists(engine_contract_path)) {
    engine_contract <- app_read_csv(engine_contract_path)
    if ("repo_git_sha" %in% names(engine_contract) && nrow(engine_contract)) {
      sha <- app_promotion_single_value(engine_contract$repo_git_sha, "repo_git_sha", engine_contract_path)
      if (!is.na(sha)) {
        return(list(
          sha = sha,
          source = normalizePath(engine_contract_path, mustWork = FALSE),
          field = "repo_git_sha"
        ))
      }
    }
  }

  list(sha = NA_character_, source = NA_character_, field = NA_character_)
}

engine_provenance <- app_promotion_engine_sha(run_dirs, readiness)

manifest <- data.frame(
  output_role = promote_map$role,
  storage_class = promote_map$storage_class,
  promoted_path = normalizePath(promote_map$dest, mustWork = FALSE),
  source_path = promote_map$source,
  run_id = basename(run_dirs$run_dir),
  config_path = normalizePath(cfg$.__config_path__, mustWork = FALSE),
  article_git_sha = app_git_sha(short = FALSE) %||% NA_character_,
  engine_repo_sha = engine_provenance$sha,
  engine_repo_sha_source = engine_provenance$source,
  engine_repo_sha_field = engine_provenance$field,
  source_sha256 = vapply(promote_map$source, app_sha256_file, character(1L)),
  promoted_sha256 = vapply(promote_map$dest, app_sha256_file, character(1L)),
  file_size_bytes = file.info(promote_map$dest)$size,
  promoted_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  stringsAsFactors = FALSE
)

manifest_path <- file.path(article_tables_dir, sprintf("glofas_application_promotion_manifest__%s.csv", slug))
app_write_csv(manifest, manifest_path)
cat(manifest_path, "\n")
