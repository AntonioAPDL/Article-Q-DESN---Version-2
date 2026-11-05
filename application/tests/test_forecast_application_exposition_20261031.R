#!/usr/bin/env Rscript

# No-fit manuscript semantics and exact text-authorization regression. All
# negative fixtures mutate strings in memory; no scientific evidence changes.
local({
  if (exists("app_repo_root", mode = "function")) {
    root <- app_repo_root()
  } else {
    file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    stopifnot(length(file_arg) == 1L)
    root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)),
      "..", ".."), mustWork = TRUE)
  }
  source(file.path(root, "scripts/check_forecast_application_exposition_20261031.R"),
    local = TRUE)
  read_text <- function(path) paste(readLines(file.path(root, path), warn = FALSE),
    collapse = "\n")
  main <- read_text("main.tex")
  supplement <- read_text("qdesn-supplement.tex")
  checks <- app_check_forecast_application_exposition(root)
  mutations <- 0L
  if (identical(app_forecast_exposition_glofas_version(main, supplement),
      "same_family_20261103")) {
    missing_contract <- tryCatch({
      app_forecast_exposition_glofas_authority(
        file.path(tempdir(), "glofas_missing_authority_fixture"), main, supplement)
      NULL
    }, error = identity)
    stopifnot(inherits(missing_contract, "error"),
      grepl("requires its current-authority contract", conditionMessage(missing_contract), fixed = TRUE))
    alias <- "\\input{tables/glofas_same_family_20261103_display_aliases.tex}"
    missing_inputs <- tryCatch({
      app_forecast_exposition_glofas_authority(root,
        gsub(alias, "", main, fixed = TRUE),
        gsub(alias, "", supplement, fixed = TRUE))
      NULL
    }, error = identity)
    stopifnot(inherits(missing_inputs, "error"),
      grepl("cannot retain historical active aliases", conditionMessage(missing_inputs), fixed = TRUE))
    mutations <- mutations + 2L
  }
  frozen_text <- function(path) {
    result <- system2("git", c("-C", shQuote(root), "show", shQuote(paste0(
      "0d111e0c2bf3951378aec2bbfc1f46fd9ecd8437:", path))), stdout = TRUE, stderr = TRUE)
    stopifnot(is.null(attr(result, "status")))
    paste(result, collapse = "\n")
  }
  fixtures <- list(current = list(main = main, supplement = supplement),
    historical = list(main = frozen_text("main.tex"),
      supplement = frozen_text("qdesn-supplement.tex")))
  mutate <- function(text, before, after) {
    text <- gsub("[[:space:]]+", " ", text)
    before <- gsub("[[:space:]]+", " ", before)
    text <- gsub("&", "", text, fixed = TRUE)
    before <- gsub("&", "", before, fixed = TRUE)
    changed <- gsub(before, after, text, fixed = TRUE)
    if (identical(text, changed)) stop(paste("Missing negative fixture:", before))
    changed
  }
  reject_semantics <- function(label, changed_main = main, changed_supplement = supplement) {
    error <- tryCatch({
      app_forecast_application_exposition_semantics(changed_main, changed_supplement)
      NULL
    }, error = identity)
    if (!inherits(error, "error")) stop(paste("Missed semantic mutation:", label))
    mutations <<- mutations + 1L
  }
  reject_authorization <- function(label, changed_main = main, changed_supplement = supplement) {
    error <- tryCatch({
      app_forecast_exposition_pricefm_authorization(root, changed_main, changed_supplement)
      NULL
    }, error = identity)
    if (!inherits(error, "error")) stop(paste("Missed text-authorization mutation:", label))
    mutations <<- mutations + 1L
  }
  for (fixture in fixtures) {
  main <- fixture$main
  supplement <- fixture$supplement
  corrected <- identical(app_forecast_exposition_glofas_version(main, supplement),
    "same_family_20261103")
  clarity_revision <- !grepl("eq:recursive-posterior-predictive-main", main, fixed = TRUE)
  app_forecast_application_exposition_semantics(main, supplement)
  reject_semantics("wrong covariate lag dimension", changed_main = mutate(main,
    if (clarity_revision) "d_u=m+q\\cdot(m_z+1)" else "d_u=m+q(m_z+1)", "d_u=m+q*m_z"))
  reject_semantics("old input matrix dimension", changed_main = mutate(main,
    "n_1\\times d_u", "n_1\\times(m+q)"))
  reject_semantics("readout dimension omits lagged covariates", changed_main = mutate(main,
    "r=n_D+\\sum_{d<D}\\tilde n_d+d_u", "r=n_D+\\sum_{d<D}\\tilde n_d"))
  reject_semantics("parameter draw changes inside a trajectory", changed_main = mutate(main,
    if (clarity_revision) "The parameters remain fixed along the trajectory" else "parameter draw remains fixed",
    "parameter draw is redrawn"))
  reject_semantics("trajectory histories collapsed", changed_main = mutate(main,
    "that draw's history", "a common averaged response history"))
  reject_semantics("training errors reused in forecasting", changed_main = mutate(main,
    if (clarity_revision) "fresh error" else "fresh errors", "training errors"))
  reject_semantics("path-conditional location called the marginal quantile", changed_main = mutate(main,
    if (clarity_revision) "is not a quantile integrated over all possible histories" else "intermediate responses and parameters",
    "is the quantile of the conditional location"))
  reject_semantics("unassigned multiquantile response likelihood", changed_main = mutate(main,
    "ordered quantile grid at each step", "single exAL response law at each step"))
  reject_semantics("MQ interpolation falsely called single-exAL sampling", changed_main = mutate(main,
    "not sampling from a single exAL regression", "sampling from a single exAL regression"))
  reject_semantics("unimplemented MQ pathwise authority", changed_supplement = mutate(supplement,
    "primary calculation evaluates coefficient draws at their averaged predictors",
    "primary calculation evaluates coefficient draws along their own future paths"))
  if (corrected) {
    reject_semantics("same-family future factor removed", changed_supplement = mutate(supplement,
      "\\prod_{h=1}^{28}f_{p_k}", "1"))
    reject_semantics("Gaussian driver prior restored", changed_supplement = paste(supplement,
      "\\phi_{28}(\\vect y_{F,k};\\vect m_N,\\mat V_N)"))
    reject_semantics("future path law no longer normalized", changed_main = mutate(main,
      "normalized sequential distribution", "arbitrary future kernel"))
    reject_semantics("MQ future paths shared across levels", changed_supplement = mutate(supplement,
      "Each level retains its own path", "All levels share one path"))
    reject_semantics("path mean called its response quantile", changed_main = mutate(main,
      "\\Phi^{-1}(p)\\sqrt{V_{p,hh}}", "0"))
    reject_semantics("extra response error added", changed_supplement = mutate(supplement,
      "No additional observation error is added", "Additional observation error is added"))
    reject_semantics("future weather incorrectly certified", changed_main = mutate(main,
      "Both use realized values during the forecast window", "Both use verified issuance-time forecasts"))
    reject_semantics("adverse quantile scores concealed", changed_main = mutate(main,
      "all four AL and exAL regressions score above the raw ensemble", "all four quantile regressions improve the loss"))
    reject_semantics("negative quantiles silently clipped", changed_supplement = mutate(supplement,
      "retained without clipping or truncation", "clipped at zero"))
    reject_semantics("post-hoc crossing correction introduced", changed_supplement = mutate(supplement,
      "no post-hoc crossing correction is applied", "post-hoc crossing correction is applied"))
    reject_semantics("corrected alias missing from one manuscript", changed_main = mutate(main,
      "\\input{tables/glofas_same_family_20261103_display_aliases.tex}", ""))
  } else {
  reject_semantics("additional future gauge likelihood", changed_supplement = mutate(supplement,
    "There is no additional future-reference likelihood for these quantile models",
    "There is an additional future-reference likelihood for these quantile models"))
  reject_semantics("future path called GloFAS rather than reference", changed_main = mutate(main,
    "\\vect x_t^{\\mathrm{ref}", "\\vect x_t^{\\mathrm{product}"))
  reject_semantics("Gaussian path prior silently changed", changed_main = mutate(main,
    "Gaussian", "AL"))
  reject_semantics("mean reference location called a predictive quantile", changed_main = mutate(main,
    "variational mean", "predictive quantile"))
  }
  reject_semantics("future design is no longer strictly lagged", changed_main = mutate(main,
    "j<h", "j\\le h"))
  reject_semantics("ensemble likelihood collapsed to one summary", changed_main = mutate(main,
    "all 51 members still enter the likelihood individually",
    "the ensemble enters as one average"))
  reject_semantics("unqualified across-horizon ensemble independence", changed_supplement = mutate(supplement,
    "At each horizon, the 51 issued members are modeled as conditionally independent",
    "Conditional on the regression parameters and latent future reference path, issued members are independent across members and horizons."))
  reject_semantics("future gauge truth enters fitting", changed_main = mutate(main,
    "future USGS measurements are reserved for scoring",
    "future USGS measurements are included in fitting"))
  reject_semantics("regional response silently made multivariate", changed_main = mutate(main,
    "A univariate Q--DESN regression", "A multivariate Q--DESN regression"))
  reject_semantics("direct forecasts relabeled as recursive", changed_main = mutate(main,
    "direct multihorizon predictors", "recursive multihorizon predictors"))
  reject_semantics("covariate vintages certified without evidence", changed_main = mutate(main,
    "not independently verified", "verified before every origin"))
  reject_semantics("pending PriceFM result finalized", changed_main = mutate(main,
    "[PriceFM findings to be updated.]", "The PriceFM result is final."))
  for (rule in app_forecast_exposition_pricefm_sections()) {
    before <- app_forecast_exposition_segment(if (rule$file == "main.tex") main else supplement,
      rule$begin, rule$end)
    after <- sub(rule$begin, paste0(rule$begin, " UNREVIEWED TEXT "), before, fixed = TRUE)
    if (rule$file == "main.tex") {
      reject_authorization("unreviewed main PriceFM edit",
        changed_main = sub(before, after, main, fixed = TRUE))
    } else {
      reject_authorization("unreviewed supplementary PriceFM edit",
        changed_supplement = sub(before, after, supplement, fixed = TRUE))
    }
  }
  }
  cat(sprintf(paste0("FORECAST_APPLICATION_EXPOSITION_TEST_PASS checks=%d ",
    "expected_mutation_rejections=%d source_versions=2 scientific_runs=0\n"), length(checks), mutations))
})
