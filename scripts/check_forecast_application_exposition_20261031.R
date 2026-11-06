#!/usr/bin/env Rscript

# Current-method exposition only. This guard neither fits a model nor changes
# the reporting operator or the frozen numerical authority.

app_forecast_exposition_pricefm_sections <- function() {
  list(
    main_pricefm = list(file = "main.tex",
      begin = "\\section{Application: Electricity-Price Quantile Forecasting}",
      end = "\\section{Discussion}"),
    supplement_pricefm = list(file = "qdesn-supplement.tex",
      begin = "\\subsection{PriceFM Design and Additional Results}",
      end = "\\section{GloFAS Reference--Discrepancy Forecast Correction}")
  )
}

app_forecast_exposition_segment <- function(text, begin, end) {
  start <- regexpr(begin, text, fixed = TRUE)[[1L]]
  if (start < 1L) stop(paste("Missing approved section:", begin), call. = FALSE)
  remainder <- substring(text, start)
  finish <- regexpr(end, remainder, fixed = TRUE)[[1L]]
  if (finish < 1L) stop(paste("Missing approved boundary:", end), call. = FALSE)
  substring(remainder, 1L, finish - 1L)
}

app_forecast_exposition_text_sha256 <- function(text) {
  digest::digest(enc2utf8(text), algo = "sha256", serialize = FALSE)
}

app_forecast_exposition_pricefm_authorization <- function(repo_root, main, supplement) {
  contract_path <- file.path(repo_root, "docs/reproducibility/",
    "forecast_application_exposition_20261031.json")
  expected_pin <- "edfeb297afb4bcf9ed2a5d8ee06e500561fe189652a9aaedcd093e777a5f0716"
  if (!file.exists(contract_path) ||
      !identical(digest::digest(file = contract_path, algo = "sha256"), expected_pin)) {
    stop("Unverified forecast/application exposition authorization.", call. = FALSE)
  }
  contract <- jsonlite::fromJSON(contract_path, simplifyVector = FALSE)
  baseline <- "8b28ba51176c25624b638fac54fce2699b9af078"
  if (!identical(contract$schema_version, "forecast_application_exposition_v1") ||
      !identical(contract$baseline, baseline) ||
      !identical(contract$scope, "current_method_exposition_only") ||
      !identical(contract$scientific_results_changed, FALSE) ||
      !identical(contract$fitting_or_forecasting_authorized, FALSE)) {
    stop("Exposition authorization changes its approved scientific scope.", call. = FALSE)
  }
  expected <- app_forecast_exposition_pricefm_sections()
  if (!identical(names(contract$sections), names(expected))) {
    stop("Exposition authorization must name exactly two approved PriceFM sections.", call. = FALSE)
  }
  texts <- list("main.tex" = main, "qdesn-supplement.tex" = supplement)
  checks <- character()
  for (role in names(expected)) {
    rule <- expected[[role]]
    row <- contract$sections[[role]]
    if (!identical(names(row), c("file", "begin", "end", "before_sha256", "after_sha256")) ||
        !identical(row$file, rule$file) || !identical(row$begin, rule$begin) ||
        !identical(row$end, rule$end) ||
        !grepl("^[a-f0-9]{64}$", row$before_sha256) ||
        !grepl("^[a-f0-9]{64}$", row$after_sha256)) {
      stop(paste("Invalid narrowly scoped PriceFM authorization:", role), call. = FALSE)
    }
    command <- c("-C", shQuote(repo_root), "show",
      shQuote(paste0(baseline, ":", rule$file)))
    before_lines <- suppressWarnings(system2("git", command, stdout = TRUE, stderr = TRUE))
    if (!is.null(attr(before_lines, "status"))) {
      stop("Cannot authenticate original PriceFM exposition.", call. = FALSE)
    }
    before <- app_forecast_exposition_segment(paste(before_lines, collapse = "\n"),
      rule$begin, rule$end)
    after <- app_forecast_exposition_segment(texts[[rule$file]], rule$begin, rule$end)
    if (!identical(app_forecast_exposition_text_sha256(before), row$before_sha256) ||
        !identical(app_forecast_exposition_text_sha256(after), row$after_sha256)) {
      stop(paste("PriceFM text is outside its exact approved revision:", role), call. = FALSE)
    }
    checks <- c(checks, paste("Exact source-bound PriceFM exposition:", role))
  }
  checks
}

app_forecast_exposition_glofas_version <- function(main, supplement) {
  alias <- "\\input{tables/glofas_same_family_20261103_display_aliases.tex}"
  present <- c(grepl(alias, main, fixed = TRUE), grepl(alias, supplement, fixed = TRUE))
  if (any(present) && !all(present)) {
    stop("Corrected GloFAS aliases must be explicit in both manuscripts.", call. = FALSE)
  }
  if (all(present)) "same_family_20261103" else "historical_gaussian_driver_20261031"
}

app_forecast_exposition_glofas_authority <- function(repo_root, main, supplement) {
  version <- app_forecast_exposition_glofas_version(main, supplement)
  authority <- file.path(repo_root, "tables/glofas_same_family_current_authority.json")
  if (identical(version, "historical_gaussian_driver_20261031")) {
    if (file.exists(authority)) {
      stop("Corrected GloFAS authority cannot retain historical active aliases.", call. = FALSE)
    }
    return(character())
  }
  helper <- file.path(repo_root, "scripts/glofas_current_article_authority.py")
  if (!file.exists(authority) || !file.exists(helper)) {
    stop("Corrected GloFAS exposition requires its current-authority contract and validator.",
      call. = FALSE)
  }
  program <- paste(
    "import importlib.util, pathlib, sys",
    "root = pathlib.Path(sys.argv[1])",
    "spec = importlib.util.spec_from_file_location('glofas_authority', root / 'scripts/glofas_current_article_authority.py')",
    "module = importlib.util.module_from_spec(spec)",
    "spec.loader.exec_module(module)",
    "module.validate_authority_tree(root)",
    "print('GLOFAS_CURRENT_ARTICLE_AUTHORITY_TREE_VERIFIED')",
    sep = "; "
  )
  result <- suppressWarnings(system2("/usr/bin/python3.11",
    c("-I", "-S", "-B", "-c", shQuote(program), shQuote(normalizePath(repo_root))),
    stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(result, "status")) ||
      !any(result == "GLOFAS_CURRENT_ARTICLE_AUTHORITY_TREE_VERIFIED")) {
    stop(paste("Corrected GloFAS current-authority validation failed:",
      paste(result[seq_len(min(12L, length(result)))], collapse = "\n")), call. = FALSE)
  }
  "Corrected GloFAS authority, numerical assets, and effective aliases verified."
}

app_forecast_application_exposition_semantics <- function(main, supplement) {
  checks <- character()
  require_check <- function(value, message) {
    if (!isTRUE(value)) stop(message, call. = FALSE)
    checks <<- c(checks, message)
  }
  has <- function(text, needle) grepl(needle, text, fixed = TRUE)
  plain <- function(text) gsub("[[:space:]]+", " ", text)
  section <- function(text, label) {
    marker <- paste0("\\label{", label, "}")
    start <- regexpr(marker, text, fixed = TRUE)[[1L]]
    require_check(start > 0L, paste("Required statistical section:", label))
    tail <- substring(text, start + nchar(marker))
    finish <- regexpr("\\section{", tail, fixed = TRUE)[[1L]]
    if (finish > 0L) substring(tail, 1L, finish - 1L) else tail
  }
  model <- gsub("&", "", plain(section(main, "sec:model")), fixed = TRUE)
  forecast <- plain(section(main, "sec:forecast"))
  glofas <- plain(section(main, "sec:data"))
  pricefm <- plain(section(main, "sec:pricefm-application"))
  sf <- plain(section(supplement, "sec:forecast_synthesis"))
  sg <- plain(section(supplement, "sec:glofas_discrepancy"))
  corrected_glofas <- identical(app_forecast_exposition_glofas_version(main, supplement),
    "same_family_20261103")
  require_check(has(gsub("\\cdot", "", model, fixed = TRUE), "d_u=m+q(m_z+1)") &&
    has(model, "\\vect z_{t-m_z}") && has(model, "\\vect h_{t-1"),
    "Define exogenous lags and recurrent state separately from the input-vector dimension.")
  require_check(has(model, "n_1\\times d_u") &&
    has(model, "r=n_D+\\sum_{d<D}\\tilde n_d+d_u"),
    "Input matrices and a readout with direct inputs use the same declared input dimension.")
  require_check(has(forecast, "parameter draw") && has(forecast, "history") &&
    has(forecast, "\\exAL_{p_0}") && has(forecast, "\\beta") &&
    (grepl("(same|fixed)[^.]{0,110}parameter draw|parameter draw[^.]{0,110}(fixed|same)", forecast) ||
      has(forecast, "The parameters remain fixed along the trajectory")),
    "Recursive response simulation retains its paired parameters over the trajectory.")
  require_check((grepl("(own|separate)[^.]{0,100}(history|histories)|history[^.]{0,100}(own|separate)", forecast) ||
      (has(forecast, "draw's history") && has(forecast, "own predictors")) ||
      has(forecast, "Append the response to that draw's history before updating the reservoir")) &&
    !has(forecast, "a common averaged response history"),
    "Each draw propagates its own response history rather than a shared mean path.")
  require_check(has(forecast, "future responses") &&
    has(forecast, "covariate") && has(forecast, "fitting endpoint") &&
    has(forecast, "do not refit"),
    "Explain unknown response lags, covariate conditioning and fixed fitted parameters across origins.")
  require_check(grepl("(fresh|new)[^.]{0,60}(error|errors)|error[^.]{0,60}(fresh|new)", forecast) &&
    has(forecast, "AL") && has(forecast, "exAL"),
    "Future likelihood errors are newly generated, not reused fitting variables.")
  require_check((has(forecast, "A posterior predictive quantile integrates over") &&
      has(forecast, "intermediate responses and parameters") &&
      has(forecast, "conditions on one simulated history")) ||
    has(forecast, "A conditional location along one simulated history is not a quantile integrated over all possible histories"),
    "Distinguish conditional locations from multistep predictive quantiles.")
  require_check(has(forecast, "\\bar{\\vect x}_{o+h}") &&
    has(forecast, "ordered quantile grid at each step") &&
    has(forecast, "endpoint quantiles") &&
    has(forecast, "not sampling from a single exAL regression") &&
    has(sf, "primary calculation evaluates coefficient draws at their averaged predictors") &&
    has(sf, "endpoint clamping, not extrapolation"),
    "Do not relabel current MQ averaging or its inverse-CDF response law.")
  require_check(has(glofas, "\\vect x_t^{\\mathrm{ref}") &&
    has(glofas, "\\vect x_t^{\\mathrm{disc}") &&
    has(glofas, "\\vect\\beta_p") && has(glofas, "\\vect\\delta_p") &&
    (has(glofas, "GloFAS-minus-reference") || has(glofas, "g_t^{\\mathrm{ret}}-y_t")),
    "Keep reference and discrepancy regressions and their two predictor maps identifiable.")
  if (corrected_glofas) {
    require_check(has(glofas, "normalized sequential distribution") &&
      has(glofas, "same likelihood as the observed gauge record") &&
      has(glofas, "\\text{Future reference:}") &&
      has(sg, "\\prod_{h=1}^{28}f_{p_k}") && has(sg, "L_{F,k}") &&
      !has(sg, "\\phi_{28}(\\vect y_{F,k};\\vect m_N,\\mat V_N)") &&
      has(sg, "Each level retains its own path"),
      "Corrected GloFAS uses normalized same-family future responses and separate MQ paths, not a Gaussian driver prior.")
  } else {
    require_check(has(glofas, "Gaussian") && has(glofas, "latent") &&
      has(glofas, "path") && has(glofas, "prior") &&
      has(sg, "There is no additional future-reference likelihood for these quantile models"),
      "The historical quantile application uses its Gaussian path prior, not a new response transition.")
  }
  require_check(has(glofas, "51") &&
    (has(glofas, "ordinary likelihood factor") || has(glofas, "one ordinary factor")) &&
    has(glofas, "j<h") &&
    has(glofas, "all 51 members still enter the likelihood individually") &&
    grepl("(earlier|lagged)[^.]{0,100}(value|values|path|input)|path[^.]{0,100}earlier", glofas) &&
    grepl("(mean|average)[^.]{0,100}(ensemble|issued)|ensemble[^.]{0,100}(mean|average)", glofas),
    "Explain causal latent inputs and distinguish ensemble summaries from the individual member likelihoods.")
  if (corrected_glofas) {
    require_check(has(sg, "At each horizon, the 51 issued members are modeled as conditionally independent") &&
      has(sg, "preceding input histories") &&
      !has(sg, "independent across members and horizons"),
      "Condition within-horizon members on the causal path and parameters, not across-horizon independence.")
    require_check(has(glofas, "\\Phi^{-1}(p)\\sqrt{V_{p,hh}}") &&
      has(sg, "\\Phi^{-1}(p_k)\\sqrt{V_{k,hh}}") &&
      has(glofas, "marginal response quantile") && has(sg, "local Gaussian--Delta approximation") &&
      has(sg, "No additional observation error is added") &&
      has(glofas, "future USGS measurements are reserved for scoring") &&
      has(glofas, "Both use realized values during the forecast window"),
      "Report Gaussian--Delta marginal response quantiles without extra noise and preserve truth/weather roles.")
    require_check(has(glofas, "Gaussian DESN with ridge regularization has the lowest") &&
      has(glofas, "all four AL and exAL regressions score above the raw ensemble") &&
      has(glofas, "inverted on eight dates") &&
      has(sg, "retained without clipping or truncation") &&
      has(sg, "no post-hoc crossing correction is applied"),
      "Retain adverse quantile-regression loss, inversion, crossing, and physical-support findings.")
  } else {
    require_check(has(sg, paste0("At each horizon, the 51 issued members are modeled as ",
        "conditionally independent given the regression parameters, the latent future reference ",
        "path \\(\\vect y_{F,k}\\), and preceding input histories.")) &&
      !has(sg, "independent across members and horizons"),
      "Condition historical member densities on preceding inputs without asserting across-horizon independence.")
    require_check(has(glofas, "variational mean") &&
      has(glofas, "not obtained by taking a quantile") &&
      has(glofas, "future USGS measurements are reserved for scoring"),
      "Name the historical GloFAS location summary and retain its future-truth firewall.")
  }
  require_check((has(pricefm, "38") || has(pricefm, "\\PricefmFullRegions")) &&
    grepl("(separately|independently)[^.]{0,100}(regional|region)|regional[^.]{0,100}(separately|independently)", pricefm) &&
    has(pricefm, "univariate") && has(pricefm, "neighbor"),
    "Explain separately fitted univariate regional regressions with neighboring predictors.")
  require_check(has(pricefm, "direct") && has(pricefm, "horizon") &&
    has(pricefm, "variational") &&
    !has(pricefm, "future prices are simulated recursively"),
    "Current PriceFM results remain direct-horizon variational-mean readouts.")
  require_check(has(pricefm, "load") && has(pricefm, "solar") && has(pricefm, "wind") &&
    has(pricefm, "forecasts") && has(pricefm, "not independently verified"),
    "Distinguish supplied day-ahead covariate forecasts from certified issue-time vintages.")
  require_check(has(main, "[PriceFM findings to be updated.]") &&
    (if (corrected_glofas) !has(glofas, "historical weighted analysis until all six unit-member refits") else
      has(glofas, "historical weighted analysis until all six unit-member refits")),
    "Keep the independent pending application and the versioned GloFAS authority distinct.")
  invisible(checks)
}

app_check_forecast_application_exposition <- function(repo_root) {
  read_source <- function(path) paste(readLines(file.path(repo_root, path), warn = FALSE),
    collapse = "\n")
  source(file.path(repo_root, "scripts/reader_online_appendix_legacy_adapter_20261106.R"), local = TRUE)
  reader_appendix <- app_reader_appendix_adapter(repo_root)
  read_source <- reader_appendix$read
  main <- read_source("main.tex")
  supplement <- read_source("qdesn-supplement.tex")
  authority_checks <- app_forecast_exposition_glofas_authority(repo_root, main, supplement)
  checks <- app_forecast_application_exposition_semantics(main, supplement)
  checks <- c(checks, authority_checks)
  checks <- c(checks, app_forecast_exposition_pricefm_authorization(repo_root, main, supplement))
  cat(sprintf("FORECAST_APPLICATION_EXPOSITION_CHECK=PASS checks=%d scientific_runs=0\n",
    length(checks)))
  invisible(checks)
}

if (sys.nframe() == 0L) {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
  script <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  app_check_forecast_application_exposition(normalizePath(file.path(dirname(script), "..")))
}
