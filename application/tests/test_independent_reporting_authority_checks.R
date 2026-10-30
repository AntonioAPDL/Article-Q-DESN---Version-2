#!/usr/bin/env Rscript
# Read-only negative tests: mutations are strings/expected digests, not files.
local({
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- if (exists("app_repo_root", mode = "function")) app_repo_root() else
    normalizePath(file.path(dirname(sub("^--file=", "", file_arg[[1L]])), "..", ".."), mustWork = TRUE)
  source(file.path(root, "scripts/independent_reporting_authority_checks.R"), local = TRUE)
  for (commit in app_ind_authority_commits) app_ind_require_ancestor(root, commit)
  presentation <- jsonlite::read_json(file.path(root, "tables/qdesn_pro_review_presentation_manifest.json"))
  app_ind_current_hash(root, "tables/qdesn_pro_review_presentation_manifest.json",
    app_ind_git_sha(root, "tables/qdesn_pro_review_presentation_manifest.json", app_ind_authority_commits[["presentation"]]))
  app_ind_historical_hash(root, presentation$source_script, presentation$script_sha256, "presentation")
  main <- paste(readLines(file.path(root, "main.tex")), collapse = "\n")
  supplement <- paste(readLines(file.path(root, "qdesn-supplement.tex")), collapse = "\n")
  app_ind_current_routing(root, main, supplement)
  rejected <- 0L
  reject <- function(expression) {
    result <- tryCatch({force(expression); NULL}, error = identity)
    stopifnot(inherits(result, "error"))
    rejected <<- rejected + 1L
  }
  wrong <- paste(rep("0", 64L), collapse = "")
  reject(app_ind_git_text(root, "main.tex", "HEAD"))
  reject(app_ind_git_text(root, "main.tex", "483e6edbec72ec76e48f2259e943e674b76e5041"))
  reject(app_ind_historical_hash(root, presentation$source_script, wrong, "presentation"))
  reject(app_ind_historical_hash(root,
    "figures/independent_simulation/qdesn_validation_500obs_v14_mcmc_fit_rmse_intervals.pdf", wrong, "oracle"))
  reject(app_ind_historical_hash(root,
    "tables/independent_forecast_300_500_v1.csv", wrong, "oracle"))
  stale <- gsub("\\input{tables/independent_train500_eval300_mcmc_figures_v1.tex}",
    "\\input{tables/qdesn_pro_review_mcmc_forecast_figures.tex}", main, fixed = TRUE)
  stopifnot(!identical(stale, main))
  reject(app_ind_current_routing(root, stale, supplement))
  reject(app_ind_current_routing(root, paste(main,
    "\\input{tables/independent_train500_eval300_mcmc_mae_figure_v1.tex}"), supplement))
  app_ind_check_current_reporting(root)
  cat(sprintf("INDEPENDENT_REPORTING_AUTHORITY_CHECKS_PASS expected_mutation_rejections=%d scientific_runs=0\n", rejected))
})
