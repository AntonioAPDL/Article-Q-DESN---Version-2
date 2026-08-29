#!/usr/bin/env Rscript

if (!exists("app_path", mode = "function")) {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
  test_root <- normalizePath(file.path(
    dirname(sub("^--file=", "", file_arg)), "..", ".."
  ), winslash = "/", mustWork = TRUE)
  source(file.path(test_root, "application", "R", "00_packages.R"))
  app_set_repo_root(test_root)
}

cfg <- yaml::read_yaml(app_path(
  "application/config/independent_validation_dgp_oracle_figures_v13.yaml"
))
validation_setting <- Sys.getenv("QDESN_VALIDATION_ROOT", unset = cfg$validation_root)
validation_candidate <- if (grepl("^/", validation_setting)) {
  validation_setting
} else {
  file.path(app_path("."), validation_setting)
}

if (!dir.exists(validation_candidate)) {
  cat(paste0(
    "Independent DGP oracle figure v13 checks skipped: the frozen validation ",
    "worktree is unavailable; set QDESN_VALIDATION_ROOT to run this integration test.\n"
  ))
} else {
  checker <- app_path("scripts/check_independent_validation_dgp_oracle_figures_v13.R")
  checker_output <- system2("Rscript", shQuote(checker), stdout = TRUE, stderr = TRUE)
  stopifnot(is.null(attr(checker_output, "status")))
  stopifnot(any(grepl(
    "INDEPENDENT_DGP_ORACLE_FIGURES_V13_CHECK=PASS", checker_output, fixed = TRUE
  )))

  figure_data <- app_read_csv(app_path(cfg$outputs$figure_data))
  stopifnot(nrow(figure_data) == 216L)
  stopifnot(sum(figure_data$metric_role == "fit_rmse") == 72L)
  stopifnot(sum(figure_data$metric_role == "forecast_mae") == 72L)
  stopifnot(sum(figure_data$metric_role == "forecast_check") == 72L)
  stopifnot(all(figure_data$plot_reference_value[
    figure_data$metric_role != "forecast_check"
  ] == 0))
  stopifnot(all(figure_data$plot_reference_value[
    figure_data$metric_role == "forecast_check"
  ] > 0))

  cat("Independent DGP oracle figure v13 checks passed.\n")
}
