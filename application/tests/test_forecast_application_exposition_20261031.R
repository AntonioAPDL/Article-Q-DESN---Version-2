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
  reject_semantics("wrong covariate lag dimension", changed_main = mutate(main,
    "d_u=m+q(m_z+1)", "d_u=m+q*m_z"))
  reject_semantics("old input matrix dimension", changed_main = mutate(main,
    "n_1\\times d_u", "n_1\\times(m+q)"))
  reject_semantics("readout dimension omits lagged covariates", changed_main = mutate(main,
    "r=n_D+\\sum_{d<D}\\tilde n_d+d_u", "r=n_D+\\sum_{d<D}\\tilde n_d"))
  reject_semantics("parameter draw changes inside a trajectory", changed_main = mutate(main,
    "parameter draw remains fixed", "parameter draw is redrawn"))
  reject_semantics("trajectory histories collapsed", changed_main = mutate(main,
    "that draw's history", "a common averaged response history"))
  reject_semantics("training errors reused in forecasting", changed_main = mutate(main,
    "fresh errors", "training errors"))
  reject_semantics("path-conditional location called the marginal quantile", changed_main = mutate(main,
    "intermediate responses and parameters", "only the conditional location"))
  reject_semantics("unassigned multiquantile response likelihood", changed_main = mutate(main,
    "not sampling from a single exAL regression", "sampling from a single exAL regression"))
  reject_semantics("unimplemented MQ pathwise authority", changed_supplement = mutate(supplement,
    "primary calculation evaluates coefficient draws at their averaged predictors",
    "primary calculation evaluates coefficient draws along their own future paths"))
  reject_semantics("additional future gauge likelihood", changed_supplement = mutate(supplement,
    "There is no additional future-reference likelihood for these quantile models",
    "There is an additional future-reference likelihood for these quantile models"))
  reject_semantics("future path called GloFAS rather than reference", changed_main = mutate(main,
    "\\vect x_t^{\\mathrm{ref}", "\\vect x_t^{\\mathrm{product}"))
  reject_semantics("Gaussian path prior silently changed", changed_main = mutate(main,
    "Gaussian", "AL"))
  reject_semantics("future design is no longer strictly lagged", changed_main = mutate(main,
    "j<h", "j\\le h"))
  reject_semantics("ensemble likelihood collapsed to one summary", changed_main = mutate(main,
    "all 51 members still enter the likelihood individually",
    "the ensemble enters as one average"))
  reject_semantics("unqualified across-horizon ensemble independence", changed_supplement = mutate(supplement,
    paste0("At each horizon, the 51 issued members are modeled as ",
      "conditionally independent given the regression parameters, the latent future reference ",
      "path \\(\\vect y_{F,k}\\), and preceding input histories."),
    "Conditional on the regression parameters and latent future reference path, issued members are independent across members and horizons."))
  reject_semantics("mean reference location called a predictive quantile", changed_main = mutate(main,
    "variational mean", "predictive quantile"))
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
  cat(sprintf(paste0("FORECAST_APPLICATION_EXPOSITION_TEST_PASS checks=%d ",
    "expected_mutation_rejections=%d scientific_runs=0\n"), length(checks), mutations))
})
