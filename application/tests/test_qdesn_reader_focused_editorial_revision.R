#!/usr/bin/env Rscript
# Read-only editorial regression: no fitting, scoring, or runtime inspection.
file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)),
                                    "..", ".."), mustWork = TRUE)
read_source <- function(relative) {
  paste(readLines(file.path(repo_root, relative), warn = FALSE), collapse = "\n")
}
main <- read_source("main.tex")
supplement <- read_source("qdesn-supplement.tex")
caption <- read_source("figures/quantile_initialization/quantile_initialization_caption.tex")
checks <- 0L
expect <- function(value, message) {
  checks <<- checks + 1L
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
has <- function(text, value) grepl(value, text, fixed = TRUE)
prose <- function(text) gsub("[[:space:]]+", " ", text)
intro <- strsplit(main, "\\section{Introduction}", fixed = TRUE)[[1L]][2L]
intro <- strsplit(intro, "\\section{Fixed-Feature Bayesian Quantile Models}",
                  fixed = TRUE)[[1L]][1L]
expect(has(prose(intro), "We introduce the quantile deep echo state network (Q--DESN)"),
       "Introduce Q--DESN independently as the proposed regression.")
expect(has(intro, "joint multiquantile extension"),
       "Name the extension as a multiquantile model.")
expect(has(prose(intro), "both single-level and joint multiquantile regressions") &&
         has(intro, "full conditional distributions") && has(intro, "Gibbs-based"),
       "Describe AL conditional tractability without claiming a closed-form posterior.")
expect(has(intro, "spatiotemporal forecasting") &&
         has(intro, "McDermottWikle2018DeepESNUQ") &&
         has(intro, "bootstrap ensemble") && has(intro, "penalized quantile sheets"),
       "Retain the distinct Bayesian DESN and quantile-reservoir precedents.")
expect(has(prose(intro), "simultaneous quantile estimation itself is already present"),
       "Do not claim simultaneous quantile fitting is new by itself.")
expect(has(intro, "quantile curves can cross") && has(intro, "does not impose noncrossing"),
       "Explain why grids are ordered and distinguish shrinkage from a constraint.")
for (text in list(main, supplement, caption)) {
  expect(!grepl("working[-[:space:]]+(likelihood|regression|model)", text,
                ignore.case = TRUE, perl = TRUE), "Use ordinary statistical terminology.")
  expect(!grepl("sandwich|post hoc covariance|post-hoc covariance", text,
                ignore.case = TRUE), "Remove the unstudied correction digression.")
}
expect(has(prose(main), "the linear quantile regression is"),
       "Introduce the regression before the reservoir details.")
expect(has(prose(main), "randomly drawn before fitting and then held fixed"),
       "Reservoir randomization precedes inference.")
expect(has(prose(main), "fixed hyperprior scale") && has(main, "random global scale") &&
         has(prose(main), "prior reference number of coefficients"),
       "Prior-scale recommendations are not numerical starting values.")
expect(has(main, "\\propto\\exp\\!\\left\\{-\\ell_c") &&
         has(main, "not a normalized scalar-response sampling"),
       "Retain the proportional composite posterior and repeated-response interpretation.")
expect(!has(main, "We use learning rate one"), "Avoid redundant learning-rate commentary.")
expect(has(prose(main), "recovers the single-level Q--DESN slope prior"),
       "Preserve the single-quantile nesting.")
for (heading in c("Multi-step quantile forecasts", "Forecast scores",
                  "DESN specification and selection")) {
  expect(has(main, paste0("\\subsection{", heading, "}")),
         paste("Missing reader-oriented subsection:", heading))
}
expect(!has(main, "eq:monotone-reporting-main") &&
         has(supplement, "eq:supp_monotone_projection") &&
         has(main, "equal-weight isotonic projection"),
       "Move projection algebra without losing the actual scoring rule.")
expect(has(main, "oracle finite-grid") && has(supplement, "oracle finite-grid") &&
         has(main, "S_{\\mathrm{DGP}}^{(b)}") && has(main, "p_K-p_1"),
       "Rename only the display name, retaining the finite-grid score and range.")
expect(has(main, "score intervals condition on that summary"),
       "Define the uncertainty displayed in the primary joint comparison.")
for (model in c("independent AL Q--DESN", "joint AL Q--DESN",
                "independent exAL Q--DESN", "joint exAL Q--DESN")) {
  expect(has(main, model), paste("Name the common-feature comparison:", model))
}
expect(has(main, "Gaussian-DESN ridge regressions") &&
         has(main, "generated reservoir states"),
       "Explain preliminary specification comparison and state diagnostics.")
expect(!has(main, "initialize Gaussian RHS--VB, then the median AL regression") &&
         has(prose(main), "initialization sequence given in the supplement"),
       "Keep one supplementary initialization account and a valid pointer.")
expect(has(caption, "PriceFM uses independent VB fits only") &&
         has(caption, "prior calibration"),
       "Preserve study-specific fitting and prior-calibration distinctions.")
for (placeholder in c("Simulation", "GloFAS", "PriceFM")) {
  expect(has(main, paste0("[", placeholder, " findings to be updated.]")),
         "Do not replace the intentional abstract findings placeholders.")
}
expect(has(prose(main), "Future USGS values are excluded from fitting") &&
         has(main, "latter is unscored") && has(main, "21 of 28") &&
         has(main, "slightly higher aggregate AQL"),
       "Retain the material application information boundaries and adverse results.")
expect(has(prose(supplement), "log-scale slice transition") &&
         has(supplement, "eq:supp_joint_increment_moments"),
       "Keep executed AL transitions and joint covariance mathematics identifiable.")
cat(sprintf("QDESN_READER_FOCUSED_EDITORIAL_REVISION_PASS: %d checks\n", checks))
