# Read-only separation of immutable historical receipts from active reporting.
# Historical lookup is restricted to these reviewed ancestors, never an object search.
app_ind_authority_commits <- c(
  presentation = "282206caf176d5e8e13857dd1070f2fac02586fc",
  oracle = "0b747f401e6fbaa7d231adaa8576a9814a7d861d",
  current_reporting = "fe4235d700c007c1255aedddac530ae8539181e8")

app_ind_require <- function(ok, label) {
  if (!isTRUE(ok)) stop(paste0("INDEPENDENT_AUTHORITY_FAILED: ", label), call. = FALSE)
  invisible(TRUE)
}
app_ind_sha <- function(path) unname(tools::sha256sum(path)[[1L]])
app_ind_require_ancestor <- function(root, commit) {
  app_ind_require(commit %in% unname(app_ind_authority_commits), "unapproved historical reference")
  for (tip in c("refs/remotes/origin/main", "HEAD")) {
    status <- system2("git", c("-C", shQuote(root), "merge-base", "--is-ancestor", commit, tip),
      stdout = FALSE, stderr = FALSE)
    app_ind_require(identical(status, 0L), paste("fixed reference is not an ancestor of", tip))
  }
  invisible(TRUE)
}
app_ind_git_text <- function(root, path, commit) {
  app_ind_require_ancestor(root, commit)
  app_ind_require(grepl("^[A-Za-z0-9_./-]+$", path), "unsafe historical source path")
  text <- system2("git", c("-C", shQuote(root), "show", shQuote(paste0(commit, ":", path))),
    stdout = TRUE, stderr = TRUE)
  app_ind_require(is.null(attr(text, "status")), paste("missing historical source", path))
  paste(text, collapse = "\n")
}
app_ind_git_sha <- function(root, path, commit) {
  app_ind_require_ancestor(root, commit)
  app_ind_require(grepl("^[A-Za-z0-9_./-]+$", path), "unsafe historical source path")
  command <- paste("git -C", shQuote(root), "show", shQuote(paste0(commit, ":", path)), "| sha256sum")
  output <- system2("sh", c("-c", shQuote(command)), stdout = TRUE, stderr = TRUE)
  app_ind_require(is.null(attr(output, "status")) && length(output) == 1L &&
    grepl("^[0-9a-f]{64}[[:space:]]", output), paste("historical source digest", path))
  sub("[[:space:]].*$", "", output)
}
app_ind_current_hash <- function(root, path, expected) {
  app_ind_require(file.exists(file.path(root, path)) &&
    identical(app_ind_sha(file.path(root, path)), expected), paste("immutable current asset", path))
}
app_ind_historical_hash <- function(root, path, expected, role) {
  commit <- app_ind_authority_commits[[role]]
  app_ind_require(!is.null(commit), "unknown historical role")
  app_ind_require_ancestor(root, commit)
  allowed <- switch(role,
    presentation = c("scripts/build_qdesn_pro_review_presentation.R", "scripts/qdesn_evaluation_figure_style.R"),
    oracle = c("scripts/check_qdesn_final_manuscript_revision.R",
      "scripts/check_independent_validation_dgp_oracle_figures_v14.R",
      "main.tex", "qdesn-supplement.tex", "overleaf/article_files.txt"),
    character())
  if (file.exists(file.path(root, path)) && identical(app_ind_sha(file.path(root, path)), expected)) {
    return(invisible(TRUE))
  }
  app_ind_require(path %in% allowed, paste("historical fallback forbidden for scientific/output asset", path))
  app_ind_require(identical(app_ind_git_sha(root, path, commit), expected),
    paste("fixed historical digest", role, path))
}
app_ind_effective_tex <- function(root, path, seen = character()) {
  if (path %in% seen) return(character())
  text <- readLines(file.path(root, path), warn = FALSE)
  text <- sub("(?<!\\\\)%.*$", "", text, perl = TRUE)
  inputs <- unlist(regmatches(text, gregexpr("\\\\input\\{[^}]+\\}", text, perl = TRUE)))
  inputs <- sub("^\\\\input\\{(.*)\\}$", "\\1", inputs)
  inputs <- inputs[!grepl("\\\\", inputs)]
  inputs <- ifelse(grepl("[.]tex$", inputs), inputs, paste0(inputs, ".tex"))
  inputs <- inputs[file.exists(file.path(root, inputs))]
  unique(c(path, unlist(lapply(inputs, function(p) app_ind_effective_tex(root, p, c(seen, path))))))
}
app_ind_current_routing <- function(root, main = NULL, supplement = NULL) {
  read <- function(path) paste(readLines(file.path(root, path), warn = FALSE), collapse = "\n")
  if (is.null(main)) main <- read("main.tex")
  if (is.null(supplement)) supplement <- read("qdesn-supplement.tex")
  has <- function(x, text) grepl(text, x, fixed = TRUE)
  app_ind_require(has(main, "\\input{tables/independent_train500_eval300_mcmc_figures_v1.tex}") &&
    !has(main, "\\input{tables/qdesn_pro_review_mcmc_forecast_figures.tex}"), "live main forecast routing")
  app_ind_require(has(supplement, "\\input{tables/independent_train500_eval300_mcmc_mae_figure_v1.tex}") &&
    has(supplement, "\\input{tables/independent_train500_eval500_mcmc_figures_v1.tex}") &&
    !has(main, "\\input{tables/independent_train500_eval300_mcmc_mae_figure_v1.tex}"), "live supplementary recovery and sensitivity routing")
  wrapper <- read("tables/independent_train500_eval300_mcmc_figures_v1.tex")
  app_ind_require(has(wrapper, "eval300_mcmc_forecast_check_v1.pdf") &&
    !has(wrapper, "eval300_mcmc_forecast_mae_v1.pdf"), "live main figure contains check loss only")
  app_ind_require(!has(main, "fig:simulation-500obs-mcmc-forecast-mae-intervals") &&
    has(main, "fig:simulation-500obs-mcmc-forecast-check-loss-intervals"), "live main references the primary criterion only")
  invisible(TRUE)
}
app_ind_check_current_reporting <- function(root) {
  commit <- app_ind_authority_commits[["current_reporting"]]
  app_ind_require_ancestor(root, commit)
  fixed <- c("application/config/independent_forecast_300_500_v1.json",
    "tables/independent_forecast_300_500_v1.csv", "tables/independent_fit_preserved_300_500_v1.csv",
    "tables/independent_forecast_300_500_replay_checks.csv", "tables/independent_forecast_300_500_vb_coverage.csv",
    "tables/independent_forecast_300_500_dgp_references.csv", "scripts/build_qdesn_pro_review_presentation.R")
  for (path in fixed) app_ind_current_hash(root, path, app_ind_git_sha(root, path, commit))
  receipt <- jsonlite::read_json(file.path(root, "tables/independent_forecast_300_500_article_manifest_v1.json"), simplifyVector = TRUE)
  app_ind_require(identical(receipt$schema, "independent-forecast-300-500-article-v1") &&
    identical(receipt$authority_id, "independent_forecast_300_primary_500_sensitivity_v1") &&
    receipt$primary_cutoff == 300L && receipt$sensitivity_cutoff == 500L &&
    receipt$fits_launched == 0L && receipt$forecasts_launched == 0L && receipt$fit_unchanged &&
    identical(receipt$vb_forecasts, "OMITTED_NO_AUTHENTIC_PREFIX_DRAWS"), "live 300/500 authority contract")
  for (group in c("sources", "outputs")) for (path in names(receipt[[group]])) {
    app_ind_require(grepl("^(main[.]tex$|qdesn-supplement[.]tex$|overleaf/article_files[.]txt$|application/|scripts/|tables/|figures/|docs/)", path) &&
      !grepl("(^|/)[.][.](/|$)|(^|/)(cache|local_trackers|logs)(/|$)", path), "safe live receipt path")
    app_ind_current_hash(root, path, receipt[[group]][[path]])
  }
  rows <- read.csv(file.path(root, "tables/independent_forecast_300_500_v1.csv"))
  app_ind_require(nrow(rows) == 144L && all(rows$n_chains == 3L) &&
    all(rows$forecast_pairs == rows$cutoff) && all(rows$forecast_origins == ceiling(rows$cutoff/30)) &&
    all(rows$last_lead == ifelse(rows$cutoff == 300L, 30L, 20L)), "live balanced origin/horizon surface")
  app_ind_current_routing(root)
  selected <- unique(c(app_ind_effective_tex(root, "main.tex"), app_ind_effective_tex(root, "qdesn-supplement.tex")))
  retired <- c("tables/qdesn_pro_review_mcmc_forecast_figures.tex",
    "tables/qdesn_validation_500obs_v14_mcmc_forecast_metric_interval_figures.tex",
    "tables/qdesn_validation_mcmc_five_chain_sensitivity.tex")
  app_ind_require(!any(retired %in% selected) &&
    all(c("tables/qdesn_single_quantile_mcmc_fit_figure_display.tex",
      "tables/qdesn_single_quantile_vb_fit_figure_display.tex",
      "tables/independent_forecast_calibration_figure_v1.tex") %in% selected), "live closure excludes retired forecasts and retains fitting/calibration")
  upload <- readLines(file.path(root, "overleaf/article_files.txt"), warn = FALSE)
  required <- c("tables/independent_train500_eval300_mcmc_figures_v1.tex",
    "tables/independent_train500_eval300_mcmc_mae_figure_v1.tex",
    "tables/independent_train500_eval500_mcmc_figures_v1.tex",
    "tables/qdesn_single_quantile_mcmc_fit_figure_display.tex", "tables/qdesn_single_quantile_vb_fit_figure_display.tex",
    sprintf("figures/independent_simulation/independent_train500_eval%d_mcmc_forecast_%s_v1.pdf",
      rep(c(300L, 500L), each = 2L), rep(c("check", "mae"), 2L)))
  app_ind_require(all(required %in% upload) &&
    !any(grepl("qdesn_pro_review_mcmc_forecast|qdesn_validation_500obs_v14_mcmc_forecast|v14_vb_forecast_", upload)), "live article-only IND publication surface")
  invisible(TRUE)
}
