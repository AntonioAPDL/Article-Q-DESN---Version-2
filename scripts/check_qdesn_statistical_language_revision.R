#!/usr/bin/env Rscript

# Read-only bounds for the approved statistical-language revision. These
# assertions protect interpretation and scientific inputs; they do not certify
# historical execution, refit models, rescore forecasts, or diagnose mixing.

app_statistical_language_semantics <- function(main, supplement, history) {
  checks <- character()
  require_check <- function(value, message) {
    if (!isTRUE(value)) stop(message, call. = FALSE)
    checks <<- c(checks, message)
  }
  has <- function(x, text) grepl(text, x, fixed = TRUE)
  plain <- function(x) gsub("[[:space:]]+", " ", x)
  section <- function(x, label) {
    marker <- paste0("\\label{", label, "}")
    position <- regexpr(marker, x, fixed = TRUE)[1L]
    require_check(position > 0L, paste("Required section:", label))
    text <- substring(x, position + nchar(marker))
    end <- regexpr("\\section{", text, fixed = TRUE)[1L]
    if (end > 0L) substring(text, 1L, end - 1L) else text
  }
  equation <- function(x, label) {
    marker <- paste0("\\label{", label, "}")
    at <- regexpr(marker, x, fixed = TRUE)[1L]
    require_check(at > 0L, paste("Required equation:", label))
    before <- substring(x, 1L, at)
    starts <- gregexpr("\\begin{equation}", before, fixed = TRUE)[[1L]]
    require_check(any(starts > 0L), paste("Numbered equation:", label))
    text <- substring(x, tail(starts[starts > 0L], 1L))
    end <- regexpr("\\end{equation}", text, fixed = TRUE)[1L]
    require_check(end > 0L, paste("Complete equation:", label))
    substring(text, 1L, end + nchar("\\end{equation}") - 1L)
  }
  main_plain <- plain(main)
  supplement_plain <- plain(supplement)
  forecast <- section(supplement, "sec:forecast_synthesis")
  forecast_plain <- plain(forecast)
  stopping <- section(supplement, "subsec:glofas_checks")
  abstract <- sub(".*\\\\begin\\{abstract\\}", "", main)
  abstract <- sub("\\\\end\\{abstract\\}.*", "", abstract)
  abstract_plain <- plain(abstract)
  main_body <- plain(sub(".*\\\\end\\{abstract\\}", "", main))
  glofas <- plain(section(main, "sec:data"))
  discussion <- plain(section(main, "sec:discussion"))
  unit_target <- equation(supplement, "eq:supp_glofas_unit_member_target")

  require_check(!has(supplement_plain, "Unknown future GloFAS responses") &&
    has(supplement_plain, "Unknown future reference-streamflow values"),
    "Name the latent reference streamflow, not the observed GloFAS inputs.")
  require_check(has(supplement_plain, "asymmetric Laplace (AL)") &&
    has(supplement_plain, "extended asymmetric Laplace (exAL)") &&
    has(supplement_plain, "Regularized-horseshoe (RHS)") &&
    has(supplement_plain, "Bayes (VB)") && has(supplement_plain, "(VB--LD)"),
    "The supplement must introduce its model and approximation abbreviations.")
  require_check(has(supplement, "\\expit(a)=\\{1+\\exp(-a)\\}^{-1}") &&
    has(supplement, "J(\\vect\\eta)=\\sigma(U-L)\\expit(\\eta_2)"),
    "Define expit without deleting the transformation Jacobian.")
  require_check(has(forecast, "_{o+h}") && has(forecast, "q_{o,h,k}") &&
    !has(forecast, "_{T+h}") && !has(forecast, "q_{T,h,k}") &&
    has(forecast_plain, "fitting endpoint"),
    "Generic forecast origins must be o, distinct from the fitting endpoint T.")
  require_check(has(forecast_plain, "equal-weight isotonic projection") &&
    grepl("Projection is[[:space:]]+not sorting", forecast_plain) &&
    !grepl("rearrangement[^.]{0,100}such as isotonic projection", forecast_plain) &&
    !has(forecast_plain, "rearrangement is applied") &&
    !has(forecast_plain, "may use isotonic projection"),
    "Keep isotonic projection distinct from rearrangement by sorting.")
  require_check(grepl("(not guaranteed|neither operation is guaranteed) to improve the particular weighted score",
    forecast_plain) &&
    has(forecast, "\\sum_k\\omega_k=p_K-p_1") &&
    has(forecast, "0.025,\\ 0.10,\\ 0.20,\\ 0.25,\\ 0.20,\\ 0.10,\\ 0.025"),
    "Retain the actual monotone rule and unnormalized probability weights.")
  require_check(has(forecast, "\\exAL_{p_0}") &&
    has(forecast_plain, "shape fixed at zero for AL") &&
    has(forecast_plain, "Single-level recursion is run separately at each fitted level"),
    "Retain the separate AL and exAL single-level response laws.")
  require_check(has(forecast_plain, "Linear inverse-CDF interpolation") &&
    has(forecast_plain, "endpoint clamping, not extrapolation") &&
    has(forecast_plain, "primary calculation evaluates coefficient draws at their averaged predictors") &&
    has(main_plain, "not sampling from a single exAL regression"),
    "Distinguish ordered-grid response generation from single-level sampling and averaged-feature scoring.")
  require_check(!has(supplement_plain, "ELBO history") &&
    has(supplement_plain, "objective values") &&
    has(supplement_plain, "stopping diagnostics") &&
    has(supplement, "\\label{eq:supp_elbo_transformed_coordinates}") &&
    has(supplement, "\\label{eq:supp_generic_elbo}"),
    "Distinguish numerical objective histories from the derived ELBO.")
  require_check(has(supplement, "\\vect\\Delta_1=\\vect\\beta_1") &&
    has(supplement_plain, "no additional random baseline is estimated") &&
    has(supplement_plain, "At \\(K=1\\)") &&
    has(supplement, "C_\\Delta(\\Theta_\\Delta)p(\\Theta_\\Delta)") &&
    has(supplement, "\\operatorname{Cov}_q(\\beta_{k,j},\\beta_{k-1,j})") &&
    !has(supplement_plain, "scale-dependent product masses") &&
    !has(supplement_plain, "first innovation"),
    "Derive the fitted first-slope hierarchy without substituting an optional random baseline.")
  require_check(has(supplement_plain, "point estimates") &&
    has(supplement_plain, "uncertainty") &&
    has(supplement, "\\mat H\\mat\\Sigma\\mat H^\\top"),
    "Retain fixed-intercept uncertainty scope and stacked slope covariance.")
  require_check(!grepl("strict(ly)? converg", plain(stopping), ignore.case = TRUE) &&
    has(plain(stopping), "stopping criteria") &&
    has(plain(stopping), "three consecutive") &&
    has(stopping, "10^{-3}") && has(stopping, "8.9279687") &&
    has(stopping, "7.7748371") && has(stopping, "2.6080582") &&
    has(stopping, "3.8253514"),
    "Describe variational stopping without altering its thresholds or achieved values.")
  require_check(has(supplement_plain, "maximum response lag") &&
    !grepl("memory[^.]{0,35}(540|180)", supplement_plain, ignore.case = TRUE) &&
    !has(supplement_plain, "forecasts with memory"),
    "Do not relabel input lag order as a measured reservoir memory.")
  require_check(!has(supplement, paste0("\\input{tables/",
    "joint_qdesn_article_validation_phase153_replication_summary_mq_display.tex}")) &&
    has(plain(history), "not verified under the corrected current posterior target") &&
    has(history, "joint_qdesn_article_validation_phase153_replication_summary"),
    "Separate historical unverified-target replication from current evidence.")
  mq_display_roles <- c("score", "secondary_score", "recursive_policy",
    "vb_score", "contrast", "crossing", "oracle_recovery")
  require_check(all(vapply(mq_display_roles, function(role) has(supplement,
    sprintf("\\input{tables/qdesn_multiquantile_%s_display.tex}", role)), logical(1))) &&
    !grepl(paste0("\\\\input\\{tables/joint_qdesn_pure_desn_v2_mq_",
      "(score|secondary_score|recursive_policy|vb_score|contrast|crossing|oracle_recovery)[^}]*\\}"),
      supplement),
    "Use all seven MQ table derivatives, not their historical caption sources.")
  require_check(!has(main, "[Simulation findings to be updated.]") &&
    !has(main, "[GloFAS findings to be updated.]") &&
    has(abstract_plain, "Asymmetric Laplace") &&
    has(abstract_plain, "extended asymmetric Laplace") &&
    has(abstract, "[PriceFM findings to be updated.]") &&
    has(abstract_plain, "crossing") &&
    has(abstract_plain, "retrospective streamflow application") &&
    has(abstract_plain, "Global Flood Awareness System ensembles") &&
    has(abstract_plain, "quantile-specific forecast correction") &&
    !has(abstract_plain, "reduces quantile forecast loss") &&
    !has(tolower(abstract_plain), "best forecast correction"),
    "Keep accepted simulation findings, neutral streamflow purpose, and provisional PriceFM findings distinct.")
  require_check(has(glofas, "coverage of 21 of 28 observations for the nominal 90\\% interval") &&
    has(glofas, "historical weighted analysis until all six unit-member refits") &&
    has(glofas, "it is not a result of the revised likelihood") &&
    has(glofas, "numerical results and displays in this draft remain from the earlier weighted analysis") &&
    has(discussion, "Streamflow findings will be updated after the unit-member refits") &&
    !has(discussion, "nominal 90\\% interval covers 75\\%"),
    "Identify historical streamflow results explicitly and withhold conclusions about pending unit-member refits.")
  require_check(has(unit_target, "\\prod_{h=1}^{28}\\prod_{e=1}^{51}") &&
    has(unit_target, "\\phi_{28}(\\vect y_{F,k};\\vect m_N,\\mat V_N)") &&
    !has(unit_target, "1/51") && !has(unit_target, "\\frac{1}{51}") &&
    has(supplement_plain, "Every included historical observation and issued member contributes one density factor") &&
    has(supplement_plain, "There is no additional future-reference likelihood for these quantile models") &&
    has(supplement_plain, "1,428 factors per level"),
    "Retain ordinary unit-member likelihoods, the historical path prior, and no extra future-reference likelihood.")
  require_check(has(plain(stopping), "describe the historical weighted analysis") &&
    has(plain(stopping), "after the unit-member refits and their checks are complete"),
    "Historical stopping evidence must not be relabeled as completed unit-member inference.")
  require_check(has(discussion, "slightly higher aggregate AQL than PriceFM"),
    "Preserve the adverse aggregate electricity-price finding while its section remains provisional.")
  historical_selection <- has(main_plain, "historical forecast-based refinement") ||
    (has(main_plain, "historical refinement") &&
      has(main_plain, "forecast performance on the evaluation series"))
  common_target <- has(supplement_plain, "same posterior target") ||
    grepl("same data, likelihood,? and prior", supplement_plain)
  require_check(historical_selection &&
    grepl("(adopted after exploratory assessment|was chosen after inspecting results over the longer period)", main_plain) &&
    grepl("(revised after inspecting|shorter primary period was selected after inspecting the longer-period results)", supplement_plain) && common_target,
    "Preserve selection history and the common posterior target across chains.")
  require_check(has(tolower(main_plain), "score intervals") &&
    has(main_plain, "averaged") && has(main_plain, "predictors") &&
    has(supplement_plain, "pairing") && has(supplement_plain, "depend"),
    "State score conditioning and the dependence on between-model pairing.")
  invisible(checks)
}

app_check_statistical_language_revision <- function(repo_root) {
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  baseline <- "a96e661613ec7e733196a0b994f45350a3078332"
  checks <- character()
  require_check <- function(value, message) {
    if (!isTRUE(value)) stop(message, call. = FALSE)
    checks <<- c(checks, message)
  }
  git <- function(arguments) {
    result <- system2("git", c("-C", shQuote(repo_root), arguments),
                      stdout = TRUE, stderr = TRUE)
    require_check(is.null(attr(result, "status")),
                  paste("Git read-only verification:", paste(arguments, collapse = " ")))
    result
  }
  read_source <- function(relative) paste(readLines(file.path(repo_root, relative),
    warn = FALSE), collapse = "\n")
  baseline_text <- function(relative) paste(git(c("show", shQuote(paste0(
    baseline, ":", relative)))), collapse = "\n")
  paths <- git(c("ls-tree", "-r", "--name-only", baseline))
  scientific_csv <- paths[grepl("^tables/.*[.]csv$", paths)]
  pricefm_paths <- paths[grepl("pricefm", paths, ignore.case = TRUE)]
  independent_pdfs <- c(sprintf(
    "figures/independent_simulation/independent_train500_eval%d_mcmc_forecast_%s_v1.pdf",
    rep(c(300L, 500L), each = 2L), rep(c("mae", "check"), 2L)),
    "figures/independent_simulation/qdesn_pro_review_mcmc_fit_rmse.pdf",
    "figures/independent_simulation/qdesn_pro_review_vb_fit_rmse.pdf")
  protected <- sort(unique(c(scientific_csv, pricefm_paths, independent_pdfs)))
  require_check(length(scientific_csv) >= 300L && length(pricefm_paths) >= 20L,
                "The frozen scientific and PriceFM inventories must be complete.")
  expected <- git(c("ls-tree", "-r", baseline, "--", vapply(protected,
    shQuote, character(1))))
  expected_paths <- sub("^[^\t]+\t", "", expected)
  expected_blobs <- sub("^[0-9]+ blob ([a-f0-9]+)\t.*$", "\\1", expected)
  require_check(length(expected_paths) == length(protected) &&
    setequal(expected_paths, protected),
                "The protected file list must be resolved against the frozen baseline.")
  expected_blobs <- expected_blobs[match(protected, expected_paths)]
  require_check(all(file.exists(file.path(repo_root, protected))),
                "No protected scientific or PriceFM evidence may be deleted.")
  observed <- git(c("hash-object", "--", vapply(protected, shQuote, character(1))))
  if (!identical(observed, expected_blobs)) {
    changed <- protected[observed != expected_blobs]
    stop(paste("Protected scientific or PriceFM file changed:",
               paste(changed, collapse = ", ")), call. = FALSE)
  }
  checks <- c(checks, "Scientific CSVs, PriceFM files, and frozen IND figures unchanged.")
  source_guard <- new.env(parent = baseenv())
  sys.source(file.path(repo_root,
    "scripts/glofas_unit_member_integration_source_guard.R"), envir = source_guard)
  # Pin the complete authorization, not just its pathname. Without this manifest
  # the original zero-scientific-source-change editorial restriction still applies.
  checks <- c(checks, source_guard$app_check_glofas_unit_member_integration_sources(
    repo_root, manifest_sha256 =
      "176c0340fbcc7c2efdda7fe01d9e13c44906ffafa311bc48a16a645156905dd6"))
  main <- read_source("main.tex")
  supplement <- read_source("qdesn-supplement.tex")
  segment <- function(text, begin, end) {
    start <- regexpr(begin, text, fixed = TRUE)[1L]
    require_check(start > 0L, paste("Missing protected segment:", begin))
    text <- substring(text, start)
    stop <- regexpr(end, text, fixed = TRUE)[1L]
    require_check(stop > 0L, paste("Missing protected boundary:", end))
    substring(text, 1L, stop - 1L)
  }
  main_begin <- "\\section{Application: Electricity-Price Quantile Forecasting}"
  supplement_begin <- "\\subsection{PriceFM Design and Additional Results}"
  require_check(identical(segment(main, main_begin, "\\section{Discussion}"),
    segment(baseline_text("main.tex"), main_begin, "\\section{Discussion}")),
    "Keep the complete provisional PriceFM main section unchanged.")
  require_check(identical(segment(supplement, supplement_begin,
    "\\section{GloFAS Reference--Discrepancy Forecast Correction}"),
    segment(baseline_text("qdesn-supplement.tex"), supplement_begin,
    "\\section{GloFAS Reference--Discrepancy Forecast Correction}")),
    "Keep the complete provisional PriceFM supplement section unchanged.")
  receipt_path <- "tables/qdesn_sections5_7_presentation_manifest.json"
  receipt <- jsonlite::fromJSON(file.path(repo_root, receipt_path), simplifyVector = FALSE)
  old_receipt <- jsonlite::fromJSON(baseline_text(receipt_path), simplifyVector = FALSE)
  pricefm_entries <- function(x) Filter(function(row) {
    is.character(row$role) && startsWith(row$role, "pricefm_")
  }, x$outputs)
  pricefm_sources <- function(x) Filter(function(row) {
    grepl("pricefm", row$file, ignore.case = TRUE)
  }, x$sources)
  pricefm_aliases <- function(x) x$supp_aliases[grepl("^Pricefm", names(x$supp_aliases))]
  require_check(length(pricefm_entries(receipt)) == 2L &&
    identical(pricefm_entries(receipt), pricefm_entries(old_receipt)) &&
    identical(pricefm_sources(receipt), pricefm_sources(old_receipt)) &&
    identical(pricefm_aliases(receipt), pricefm_aliases(old_receipt)),
    "Excluded PriceFM role receipts, source pins, and aliases must be unchanged.")
  old_alias_lines <- grep("\\\\Pricefm", strsplit(baseline_text(
    "tables/qdesn_sections5_7_supp_display_overrides.tex"), "\n", fixed = TRUE)[[1L]], value = TRUE)
  new_alias_lines <- grep("\\\\Pricefm", readLines(file.path(repo_root,
    "tables/qdesn_sections5_7_supp_display_overrides.tex")), value = TRUE)
  require_check(identical(old_alias_lines, new_alias_lines),
                "Actual PriceFM publication aliases must remain unchanged.")
  history <- read_source("docs/implementation_notes/statistical_language_reader_revision_20261019.md")
  checks <- c(checks, app_statistical_language_semantics(main, supplement, history))
  cat(sprintf(paste0("QDESN_STATISTICAL_LANGUAGE_REVISION_CHECK=PASS checks=%d ",
    "scientific_csv_files=%d pricefm_files=%d scientific_runs=0\n"),
    length(checks), length(scientific_csv), length(pricefm_paths)))
  invisible(checks)
}

if (sys.nframe() == 0L) {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
  script <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
  root <- normalizePath(file.path(dirname(script), ".."), mustWork = TRUE)
  app_check_statistical_language_revision(root)
}
