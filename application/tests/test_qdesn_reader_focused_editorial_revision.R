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
expect(has(prose(intro), "multiquantile deep echo state network (MQ--DESN)") &&
         has(prose(intro), "estimating their readouts jointly"),
       "Define MQ--DESN as joint estimation across probability levels.")
expect(has(prose(intro), "both Q--DESN and MQ--DESN regressions") &&
         has(prose(intro), "full conditional distributions") && has(intro, "Gibbs-based"),
       "Describe AL conditional tractability without claiming a closed-form posterior.")
expect(has(prose(intro), "Under misspecification") &&
         has(prose(intro), "AL coefficient credible intervals need not have nominal frequentist coverage") &&
         has(intro, "YangWangHe2016ALInference"),
       "Scope the AL coverage concern to coefficient intervals under misspecification.")
expect(has(prose(intro), "In their regression simulations") &&
         has(intro, "yan2025new") &&
         has(prose(intro), "coefficient credible-interval coverage was closer to nominal than under AL in lower-tail settings"),
       "Attribute exAL coverage evidence to the tested simulation and interval target.")
expect(has(intro, "spatiotemporal forecasting") &&
         has(intro, "McDermottWikle2018DeepESNUQ") &&
         has(intro, "bootstrap ensemble") && has(intro, "penalized quantile sheets"),
       "Retain the distinct Bayesian DESN and quantile-reservoir precedents.")
expect(has(prose(intro), "then jointly estimate lead-dependent residual quantiles") &&
         has(intro, "penalized quantile sheets"),
       "Credit simultaneous quantile-sheet estimation while distinguishing its residual target.")
expect(has(intro, "quantile curves can cross") &&
         has(prose(intro), "encourages noncrossing but does not enforce it"),
       "Explain why grids are ordered and distinguish shrinkage from a constraint.")
expect(!has(intro, "That construction models the response distribution through") &&
         has(intro, "McDermottWikle2018DeepESNUQ"),
       "Remove the requested detailed contrast while retaining Bayesian DESN credit.")
expect(has(prose(intro), "For interval forecasts, it uses pairs of fitted response quantiles") &&
         has(prose(intro), "without a second-stage residual-calibration regression or bootstrap ensemble"),
       "State the interval-forecast construction and its direct-estimation contrast.")
expect(has(prose(intro), "within one Bayesian regression") &&
         has(prose(intro), "we derive MCMC updates and model-specific VB approximations") &&
         has(prose(intro), "rather than from estimating residual quantiles after point prediction"),
       "Identify joint direct regression and its computation, not a literal one-step algorithm.")
expect(has(prose(intro), "BarlowBrunk1972IsotonicDual,chernozhukov2010, DeLeonPradoSanso2026HydrologicProducts") &&
         has(prose(intro), "isotonic regression, which projects them onto an ordered grid"),
       "Cite the authenticated hydrologic ordering procedure.")
expect(has(intro, "continuous-shrinkage approach") &&
         has(intro, "predictor-dependent variation") && has(intro, "ordered intercepts") &&
         has(prose(main), "equal-weight isotonic projection"),
       "Explain the crossing mechanism without claiming exact monotonicity or no postprocessing.")
expect(has(prose(intro), "\\citet{DeLeonPradoSanso2026HydrologicProducts} combine hydrologic products") &&
         !has(prose(intro), "The earlier hydrologic model of") &&
         !has(prose(intro), "It supports both MCMC and variational inference"),
       "Credit the hydrologic study directly without the unnecessary computation aside.")
expect(has(prose(intro), "examines whether Q--DESN can recover conditional quantile paths") &&
         has(prose(intro), "forecast accuracy comparable to DQLMs and exDQLMs") &&
         has(prose(intro), "under linear structural data-generating mechanisms"),
       "State the linear-dynamics simulation purpose without claiming proven equivalence.")
expect(sum(gregexpr("The first simulation", intro, fixed = TRUE)[[1L]] > 0L) == 1L,
       "Introduce the first simulation once rather than repeat its purpose in the roadmap.")
roadmap <- strsplit(intro, "The second simulation", fixed = TRUE)[[1L]][2L]
expect(has(prose(roadmap), "retrospective correction of streamflow ensemble forecasts") &&
         has(prose(roadmap), "electricity-price quantile forecasting against a pretrained neural model") &&
         !has(roadmap, "GloFAS") && !has(roadmap, "PriceFM") &&
         !has(roadmap, "climate model"),
       "Use accurate generic application descriptions; introduce product names in their sections.")
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
         has(prose(main), "equal-weight isotonic projection"),
       "Move projection algebra without losing the actual scoring rule.")
expect(has(prose(main), "oracle finite-grid") && has(prose(supplement), "oracle finite-grid") &&
         has(main, "S_{\\mathrm{DGP}}^{(b)}") && has(main, "p_K-p_1"),
       "Rename only the display name, retaining the finite-grid score and range.")
expect(has(main, "score intervals condition on that summary"),
       "Define the uncertainty displayed in the primary joint comparison.")
expect(has(prose(main), "shared by independent Q--DESN under AL and exAL and MQ--DESN under AL and exAL") &&
         has(prose(main), "These four regressions use the same selected temporal representation"),
       "Name both likelihoods and both fitting structures in the common-feature comparison.")
expect(has(prose(main), "Gaussian regressions on DESN features (Gaussian-DESN)") &&
         has(prose(main), "estimate the conditional mean") &&
         has(main, "generated reservoir states"),
       "Explain preliminary specification comparison and state diagnostics.")
expect(!has(main, "initialize Gaussian RHS--VB, then the median AL regression") &&
         has(prose(main), "initialization sequence given in the supplement"),
       "Keep one supplementary initialization account and a valid pointer.")
expect(has(prose(caption), "PriceFM uses independent VB fits only") &&
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
expect(has(prose(intro), "final regression layer (the readout)"),
       "Define the readout at first introduction.")
expect(has(prose(main), "continuous ranked probability score (CRPS)") &&
         has(prose(main), "data-generating process (DGP)") &&
         has(main, "K\\geq2"),
       "Define the score acronyms and the finite-grid cardinality condition.")
expect(has(main, "\\vect\\beta_k\\in\\R^r") &&
         has(main, "\\label{subsec:desn-features}"),
       "Identify multiquantile slope dimensions and the feature-construction reference.")
cat(sprintf("QDESN_READER_FOCUSED_EDITORIAL_REVISION_PASS: %d checks\n", checks))
