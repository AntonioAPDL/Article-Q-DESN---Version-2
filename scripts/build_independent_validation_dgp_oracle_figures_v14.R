#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/", mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- which(args == flag)
  if (!length(at) || at[[1L]] == length(args)) return(default)
  args[[at[[1L]] + 1L]]
}

config_path <- normalizePath(
  arg_value("--config", file.path(
    repo_root, "application", "config",
    "independent_validation_dgp_oracle_figures_v14.yaml"
  )), winslash = "/", mustWork = TRUE
)
config <- yaml::read_yaml(config_path)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
verify_hash <- function(path, expected, label) {
  if (!file.exists(path) || !identical(sha256(path), as.character(expected))) {
    stop(sprintf("%s SHA-256 mismatch.", label), call. = FALSE)
  }
  invisible(path)
}
resolve_from_repo <- function(path) {
  path <- as.character(path)[1L]
  if (!grepl("^/", path)) path <- file.path(repo_root, path)
  path
}
article_path <- function(relative, must_work = FALSE) {
  if (length(relative) != 1L || is.na(relative) || !nzchar(relative) ||
      grepl("^/", relative) || grepl("(^|/)\\.\\.(/|$)", relative)) {
    stop("An article path is not portable.", call. = FALSE)
  }
  path <- file.path(repo_root, relative)
  if (must_work) return(normalizePath(path, winslash = "/", mustWork = TRUE))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}
relative_article <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(repo_root, "/")
  if (!startsWith(path, prefix)) stop("An output escapes the article repository.", call. = FALSE)
  substring(path, nchar(prefix) + 1L)
}
write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, na = "")

if (!requireNamespace("ggplot2", quietly = TRUE) ||
    !requireNamespace("yaml", quietly = TRUE)) {
  stop("yaml and ggplot2 are required.", call. = FALSE)
}
source(file.path(repo_root, "scripts", "qdesn_evaluation_figure_style.R"))

ancestor_status <- system2(
  "git", c("-C", repo_root, "merge-base", "--is-ancestor",
           as.character(config$article_minimum_commit), "HEAD")
)
if (!identical(ancestor_status, 0L)) {
  stop("The required article baseline is not an ancestor of HEAD.", call. = FALSE)
}

validation_root <- normalizePath(
  resolve_from_repo(arg_value(
    "--validation-root",
    Sys.getenv("QDESN_VALIDATION_ROOT", unset = config$validation_root)
  )), winslash = "/", mustWork = TRUE
)
validation_head <- system2(
  "git", c("-C", validation_root, "rev-parse", "HEAD"), stdout = TRUE
)
if (!identical(as.character(validation_head), as.character(config$validation_authority_commit))) {
  stop("The validation worktree is not at the frozen oracle authority.", call. = FALSE)
}
oracle_source <- normalizePath(
  file.path(validation_root, config$oracle$relative_path), winslash = "/", mustWork = TRUE
)
if (!startsWith(oracle_source, paste0(validation_root, "/"))) {
  stop("The oracle source escapes the validation worktree.", call. = FALSE)
}
verify_hash(oracle_source, config$oracle$sha256, "validation oracle asset")

interval_path <- article_path(config$inputs$interval_summary, must_work = TRUE)
verify_hash(interval_path, config$inputs$interval_summary_sha256, "v12 interval summary")
oracle_asset_path <- article_path(config$outputs$oracle_asset)
if (!isTRUE(file.copy(oracle_source, oracle_asset_path, overwrite = TRUE, copy.mode = FALSE))) {
  stop("Could not project the oracle asset into the article repository.", call. = FALSE)
}
verify_hash(oracle_asset_path, config$oracle$sha256, "projected oracle asset")

interval <- read.csv(interval_path, check.names = FALSE)
oracle <- read.csv(oracle_asset_path, check.names = FALSE)
expected <- config$expected
models <- unlist(expected$models, use.names = FALSE)
families <- unlist(expected$families, use.names = FALSE)
taus <- as.numeric(unlist(expected$taus, use.names = FALSE))
inference_levels <- unlist(expected$inference, use.names = FALSE)
metric_roles <- unlist(expected$metric_roles, use.names = FALSE)
render_inference_arg <- arg_value("--inference", "all")
render_role_arg <- arg_value("--metric-role", "all")
if (!render_inference_arg %in% c("all", inference_levels) ||
    !render_role_arg %in% c("all", metric_roles)) {
  stop("Unknown --inference or --metric-role render selector.", call. = FALSE)
}
render_inference_levels <- if (render_inference_arg == "all") {
  inference_levels
} else {
  render_inference_arg
}
render_metric_roles <- if (render_role_arg == "all") metric_roles else render_role_arg

required_interval <- c(
  "inference", "model_variant", "model_label", "family", "tau",
  "fit_qtrue_rmse", "fit_cri_lower", "fit_posterior_median", "fit_cri_upper",
  "fit_n_draws", "fit_n_chains", "fit_diagnostic_grade", "fit_replay_id",
  "forecast_qtrue_mae_H1000", "forecast_mae_cri_lower",
  "forecast_mae_posterior_median", "forecast_mae_cri_upper",
  "forecast_mae_n_draws", "forecast_mae_n_chains",
  "forecast_mae_diagnostic_grade", "forecast_mae_replay_id",
  "forecast_check_loss_H1000", "forecast_check_cri_lower",
  "forecast_check_posterior_median", "forecast_check_cri_upper",
  "forecast_check_n_draws", "forecast_check_n_chains",
  "forecast_check_diagnostic_grade", "forecast_check_replay_id"
)
if (!all(required_interval %in% names(interval)) ||
    nrow(interval) != as.integer(expected$interval_rows)) {
  stop("The v12 interval summary does not satisfy the frozen contract.", call. = FALSE)
}
interval_key <- with(
  interval, paste(inference, model_variant, family, sprintf("%.2f", tau), sep = "|")
)
if (anyDuplicated(interval_key) ||
    !setequal(unique(interval$model_variant), models) ||
    !setequal(unique(interval$family), families) ||
    !setequal(unique(interval$inference), inference_levels) ||
    !setequal(unique(interval$tau), taus)) {
  stop("The v12 interval summary has an unexpected analysis surface.", call. = FALSE)
}

role_contract <- list(
  fit_rmse = c(
    mean = "fit_qtrue_rmse", lower = "fit_cri_lower",
    median = "fit_posterior_median", upper = "fit_cri_upper",
    n_draws = "fit_n_draws", n_chains = "fit_n_chains",
    grade = "fit_diagnostic_grade", replay = "fit_replay_id"
  ),
  forecast_mae = c(
    mean = "forecast_qtrue_mae_H1000", lower = "forecast_mae_cri_lower",
    median = "forecast_mae_posterior_median", upper = "forecast_mae_cri_upper",
    n_draws = "forecast_mae_n_draws", n_chains = "forecast_mae_n_chains",
    grade = "forecast_mae_diagnostic_grade", replay = "forecast_mae_replay_id"
  ),
  forecast_check = c(
    mean = "forecast_check_loss_H1000", lower = "forecast_check_cri_lower",
    median = "forecast_check_posterior_median", upper = "forecast_check_cri_upper",
    n_draws = "forecast_check_n_draws", n_chains = "forecast_check_n_chains",
    grade = "forecast_check_diagnostic_grade", replay = "forecast_check_replay_id"
  )
)
figure_blocks <- lapply(metric_roles, function(role) {
  spec <- role_contract[[role]]
  data.frame(
    inference = interval$inference,
    model_variant = interval$model_variant,
    model_label = interval$model_label,
    family = interval$family,
    tau = interval$tau,
    metric_role = role,
    posterior_mean = as.numeric(interval[[spec[["mean"]]]]),
    cri_lower = as.numeric(interval[[spec[["lower"]]]]),
    posterior_median = as.numeric(interval[[spec[["median"]]]]),
    cri_upper = as.numeric(interval[[spec[["upper"]]]]),
    n_draws = as.integer(interval[[spec[["n_draws"]]]]),
    n_chains = as.integer(interval[[spec[["n_chains"]]]]),
    diagnostic_grade = as.character(interval[[spec[["grade"]]]]),
    replay_id = as.character(interval[[spec[["replay"]]]]),
    stringsAsFactors = FALSE
  )
})
figure_data <- do.call(rbind, figure_blocks)
figure_data <- figure_data[order(
  match(figure_data$inference, inference_levels),
  match(figure_data$metric_role, metric_roles),
  match(figure_data$family, families), figure_data$tau,
  match(figure_data$model_variant, models)
), , drop = FALSE]
row.names(figure_data) <- NULL
figure_key <- with(
  figure_data,
  paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role, sep = "|")
)
if (nrow(figure_data) != as.integer(expected$figure_rows) || anyDuplicated(figure_key) ||
    any(!is.finite(unlist(figure_data[c(
      "posterior_mean", "cri_lower", "posterior_median", "cri_upper"
    )]))) || any(figure_data$cri_lower > figure_data$posterior_mean) ||
    any(figure_data$posterior_mean > figure_data$cri_upper)) {
  stop("The expanded interval figure data failed validation.", call. = FALSE)
}

required_oracle <- c(
  "family", "tau", "metric_role", "metric_name", "plot_reference_type",
  "plot_reference_value", "expected_reference_value", "realized_reference_value",
  "formula", "source_series_sha256", "forecast_origins", "forecast_pairs"
)
oracle_key <- with(oracle, paste(family, sprintf("%.2f", tau), metric_role, sep = "|"))
if (!all(required_oracle %in% names(oracle)) ||
    nrow(oracle) != as.integer(expected$oracle_rows) || anyDuplicated(oracle_key) ||
    !setequal(unique(oracle$family), families) ||
    !setequal(unique(oracle$tau), taus) ||
    !setequal(unique(oracle$metric_role), metric_roles) ||
    any(!is.finite(oracle$plot_reference_value)) ||
    any(oracle$plot_reference_value < 0) ||
    any(oracle$plot_reference_value[oracle$metric_role != "forecast_check"] != 0) ||
    any(oracle$plot_reference_value[oracle$metric_role == "forecast_check"] <= 0) ||
    any(oracle$forecast_origins != 34L) || any(oracle$forecast_pairs != 1000L)) {
  stop("The DGP oracle asset failed its article projection contract.", call. = FALSE)
}

join_key <- with(
  figure_data, paste(family, sprintf("%.2f", tau), metric_role, sep = "|")
)
at <- match(join_key, oracle_key)
if (anyNA(at)) stop("An interval figure cell has no DGP oracle reference.", call. = FALSE)
for (name in setdiff(required_oracle, c("family", "tau", "metric_role"))) {
  figure_data[[name]] <- oracle[[name]][at]
}
figure_data_path <- article_path(config$outputs$figure_data)
write_csv(figure_data, figure_data_path)

metric_files <- c(
  fit_rmse = "fit_rmse", forecast_mae = "forecast_mae",
  forecast_check = "forecast_check_loss"
)
figure_paths <- character(0)
for (inference in render_inference_levels) {
  for (role in metric_roles) {
    if (!role %in% render_metric_roles) next
    path <- article_path(file.path(
      config$outputs$figure_directory,
      sprintf("%s_%s_%s_intervals.pdf", config$outputs$figure_prefix,
              inference, metric_files[[role]])
    ))
    qdesn_save_vector_pdf(
      path,
      qdesn_independent_interval_plot(figure_data, inference, role),
      width = 7.2, height = 6.6
    )
    figure_paths <- c(figure_paths, path)
  }
}

cat(sprintf(
  paste0(
    "INDEPENDENT_DGP_ORACLE_FIGURES_V14_BUILT rows=%d oracle=%d figures=%d ",
    "inference=%s metric_role=%s\n"
  ),
  nrow(figure_data), nrow(oracle), length(figure_paths),
  render_inference_arg, render_role_arg
))
