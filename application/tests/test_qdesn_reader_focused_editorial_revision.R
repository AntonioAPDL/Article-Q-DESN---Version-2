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
section <- function(text, label) {
  marker <- paste0("\\label{", label, "}")
  begin <- regexpr(marker, text, fixed = TRUE)[1L]
  expect(begin > 0L, paste("Missing semantic section label:", label))
  remaining <- substring(text, begin + nchar(marker))
  end <- regexpr("\\section{", remaining, fixed = TRUE)[1L]
  if (end > 0L) substring(remaining, 1L, end - 1L) else remaining
}
model <- section(main, "sec:model")
mq <- section(main, "subsec:joint-qdesn")
computation <- section(main, "sec:inference")
forecast <- section(main, "sec:forecast")
selection <- section(main, "sec:selection")
intro <- strsplit(main, "\\section{Introduction}", fixed = TRUE)[[1L]][2L]
intro <- strsplit(intro, "\\section{Fixed-Feature Bayesian Quantile Models}",
                  fixed = TRUE)[[1L]][1L]
expect(grepl("we introduce the quantile deep echo state network \\(Q--DESN\\)",
             prose(intro), ignore.case = TRUE),
       "Introduce Q--DESN independently as the proposed regression.")
expect(has(prose(intro), "multiquantile deep echo state network (MQ--DESN)") &&
         has(prose(intro), "adjacent quantile-specific slope differences") &&
         has(prose(mq), "shares information across levels"),
       "Define MQ--DESN as joint estimation across probability levels.")
expect(has(prose(intro), "full conditional distributions") &&
         has(prose(intro), "including for MQ--DESN") &&
         has(computation, "GIG") && has(prose(computation), "AL even in the multiquantile regression"),
       "Describe AL conditional tractability without claiming a closed-form posterior.")
expect(!grepl("nominal frequentist coverage", prose(intro), fixed = TRUE) ||
         (has(intro, "YangWangHe2016ALInference") &&
          has(prose(intro), "coefficient credible intervals") &&
          has(prose(intro), "misspecification")),
       "Scope the AL coverage concern to coefficient intervals under misspecification.")
expect(!grepl("coverage was closer|better.*coverage", prose(intro)) ||
         (has(intro, "yan2025new") &&
          has(prose(intro), "regression simulations") &&
          has(prose(intro), "coefficient")),
       "Attribute exAL coverage evidence to the tested simulation and interval target.")
expect(has(intro, "spatiotemporal forecasting") &&
         has(intro, "McDermottWikle2018DeepESNUQ") &&
         has(intro, "bootstrap ensemble") && has(intro, "penalized quantile sheets"),
       "Retain the distinct Bayesian DESN and quantile-reservoir precedents.")
expect(has(prose(intro), "then jointly estimate lead-dependent residual quantiles") &&
         has(intro, "penalized quantile sheets"),
       "Credit simultaneous quantile-sheet estimation while distinguishing its residual target.")
expect(has(prose(mq), "estimated curves can cross") &&
         has(prose(mq), "does not constrain") &&
         has(prose(mq), "gap to be nonnegative"),
       "Explain why grids are ordered and distinguish shrinkage from a constraint.")
expect(!has(intro, "That construction models the response distribution through") &&
         has(intro, "McDermottWikle2018DeepESNUQ"),
       "Remove the requested detailed contrast while retaining Bayesian DESN credit.")
expect(has(prose(intro), "Interval forecasts use pairs of estimated response quantiles") &&
         has(prose(intro), "without an additional residual-calibration regression or bootstrap ensemble"),
       "State the interval-forecast construction and its direct-estimation contrast.")
expect(has(prose(intro), "We model response quantiles directly using asymmetric Laplace") &&
         has(prose(intro), "extends this regression") &&
         has(prose(intro), "Markov chain Monte Carlo (MCMC)") &&
         has(prose(intro), "variational Bayes (VB) approximations"),
       "Identify joint direct regression and its computation, not a literal one-step algorithm.")
expect(has(prose(mq), "BarlowBrunk1972IsotonicDual,chernozhukov2010, DeLeonPradoSanso2026HydrologicProducts") &&
         has(mq, "eq:isotonic-projection-main"),
       "Cite the authenticated hydrologic ordering procedure.")
expect(has(mq, "predictor-dependent variation") && has(mq, "ordered intercepts") &&
         has(prose(mq), "equal-weight least-squares projection"),
       "Explain the crossing mechanism without claiming exact monotonicity or no postprocessing.")
expect(has(prose(intro), "\\citet{DeLeonPradoSanso2026HydrologicProducts} combine hydrologic products") &&
         !has(prose(intro), "The earlier hydrologic model of") &&
         !has(prose(intro), "It supports both MCMC and variational inference"),
       "Credit the hydrologic study directly without the unnecessary computation aside.")
expect(has(prose(intro), "asks whether Q--DESN can reproduce forecast behavior") &&
         has(prose(intro), "linear structural dynamics used by DQLMs and exDQLMs"),
       "State the linear-dynamics simulation purpose without claiming proven equivalence.")
expect(sum(gregexpr("The first simulation", intro, fixed = TRUE)[[1L]] > 0L) == 1L,
       "Introduce the first simulation once rather than repeat its purpose in the roadmap.")
roadmap <- substring(intro, regexpr("Sections~", intro, fixed = TRUE)[1L])
expect(has(prose(roadmap), "streamflow ensemble correction") &&
         has(prose(roadmap), "electricity-price forecasting") &&
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
expect(has(prose(intro), "randomly drawn and held fixed before regression estimation") &&
         has(prose(model), "drawn before estimating the regression parameters"),
       "Reservoir randomization precedes inference.")
expect(has(prose(main), "fixed hyperprior scale") && has(main, "random global scale") &&
         has(prose(main), "prior reference number of slopes") &&
         has(prose(main), "not a starting value"),
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
expect(has(main, "eq:isotonic-projection-main") &&
         has(supplement, "eq:supp_monotone_projection") &&
         has(prose(main), "each scored draw"),
       "Define the projection near MQ and retain its actual draw-level scoring rule.")
expect(has(prose(main), "oracle finite-grid") && has(prose(supplement), "oracle finite-grid") &&
         has(main, "S_{\\mathrm{DGP}}^{(b)}") && has(main, "p_K-p_1"),
       "Rename only the display name, retaining the finite-grid score and range.")
expect(has(prose(main), "score intervals describe readout uncertainty conditional on these averaged future predictors") &&
         has(main, "\\bar{\\vect x}_{o+h}") &&
         has(prose(main), "model-generated future predictor trajectories"),
       "Define the uncertainty displayed in the primary joint comparison.")
expect(has(prose(main), "shared by independent Q--DESN under AL and exAL and MQ--DESN under AL and exAL") &&
         has(prose(main), "These four regressions use the same selected temporal representation"),
       "Name both likelihoods and both fitting structures in the common-feature comparison.")
expect(has(prose(selection), "Gaussian regression on the same DESN predictors") &&
         has(prose(selection), "mean-regression coefficients") &&
         has(prose(selection), "Gaussian RHS--VB fit is a Gaussian regression") &&
         has(prose(main), "Checks of the reservoir states assess finite values") &&
         has(prose(main), "echo state property"),
       "Explain preliminary specification comparison and state diagnostics.")
expect(!has(main, "initialize Gaussian RHS--VB, then the median AL regression") &&
         has(prose(supplement), "initialization sequence") &&
         has(supplement, "fig:supp-quantile-sequential-initialization"),
       "Keep the complete initialization account in the supplement.")
expect(has(prose(caption), "PriceFM uses independent VB fits only") &&
         has(caption, "prior calibration"),
       "Preserve study-specific fitting and prior-calibration distinctions.")
expect(!has(main, "[Simulation findings to be updated.]") &&
         !has(main, "[GloFAS findings to be updated.]") &&
         has(main, "[PriceFM findings to be updated.]"),
       "Complete accepted simulation and GloFAS findings; retain pending PriceFM.")
expect(has(prose(main), "future USGS measurements are reserved for scoring") &&
         has(supplement, "unscored") &&
         has(prose(supplement), "retrospective GloFAS ends") &&
         has(prose(main), "21 of 28") &&
         has(prose(main), "aggregate loss is slightly higher"),
       "Retain the material application information boundaries and adverse results.")
for (heading in c("Single-quantile simulation design", "Single-quantile results",
                  "Multiquantile simulation design", "Multiquantile results")) {
  expect(has(main, paste0("\\subsection{", heading, "}")),
         paste("Missing distinct simulation design/results subsection:", heading))
}
expect(has(main, "\\mat G_\\theta\\vect\\theta_{t-1,f}") &&
         has(main, "H_f^{-1}(p)") && has(main, "WestHarrison1997") &&
         has(prose(main), "observation-error family") &&
         has(prose(main), "historical refinement also used forecast performance on the evaluation series"),
       "Explain quantile-centered linear dynamics without rewriting the actual selection history.")
expect(has(main, "DeLeonEtAl2026Exdqlm") && !has(main, "version 1.1.2") &&
         has(prose(supplement), "version 1.1.1"),
       "Cite the package paper while preserving authenticated historical execution versions.")
expect(has(prose(supplement), "slice sampling on the logarithmic scale") &&
         has(supplement, "eq:supp_joint_increment_moments"),
       "Keep executed AL transitions and joint covariance mathematics identifiable.")
expect(has(prose(intro), "final regression layer, called the readout"),
       "Define the readout at first introduction.")
expect(has(prose(main), "continuous ranked probability score (CRPS)") &&
         has(prose(main), "data-generating process (DGP)") &&
         has(main, "K\\geq2"),
       "Define the score acronyms and the finite-grid cardinality condition.")
expect(has(main, "\\vect\\beta_k\\in\\R^r") &&
         has(main, "\\label{subsec:desn-features}"),
       "Identify multiquantile slope dimensions and the feature-construction reference.")

# Mathematical/interpretive guards are insensitive to line wrapping and do
# not require a claim to remain in the introduction after an approved move.
method_invariants <- function(main, supplement) {
  flat_main <- prose(main)
  flat_supplement <- prose(supplement)
  mq_begin <- regexpr("\\label{sec:joint_qdesn_supp}", supplement, fixed = TRUE)[1L]
  mq_text <- substring(supplement, mq_begin)
  mq_end <- regexpr("\\section{Forecast Summaries and Scores}", mq_text, fixed = TRUE)[1L]
  if (mq_end > 0L) mq_text <- substring(mq_text, 1L, mq_end - 1L)
  c(
    scale_shape_prior = has(main, "\\sigma\\sim\\IG(a_\\sigma,b_\\sigma)") &&
      has(flat_main, "proper shape-prior density"),
    full_product_prior = has(main, "\\label{eq:rhs-product-main}") &&
      has(main, "\\Normal(0\\mid\\beta_j,\\zeta^2)") &&
      has(flat_main, "scale-dependent normalizer"),
    global_shape = has(main, "\\((r+1)/2\\)") &&
      has(supplement, "\\frac{r+1}{2}"),
    actual_first_slope = has(mq_text, "\\vect\\Delta_1=\\vect\\beta_1") &&
      !has(mq_text, "\\beta_{\\mathrm{base}}") &&
      has(mq_text, "C_\\Delta(\\Theta_\\Delta)p(\\Theta_\\Delta)"),
    covariance = has(supplement, "\\mat H\\mat\\Sigma\\mat H^\\top") &&
      has(supplement, "\\operatorname{Cov}_q(\\beta_{k,j},\\beta_{k-1,j})"),
    forecast_estimand = has(flat_main, "Neither averaging conditional-quantile locations") &&
      has(flat_main, "fully marginalized predictive distribution") &&
      has(main, "\\label{eq:forecast-location-main}"),
    method_specific_recursion = has(flat_main, "Single-level Q--DESN uses its AL or exAL forecast law") &&
      has(flat_main, "ordered quantile grid at each step") &&
      has(flat_main, "endpoint quantiles"),
    coordinate_entropy = has(supplement, "\\label{eq:supp_elbo_transformed_coordinates}") &&
      has(supplement, "J(\\vect\\eta)=\\sigma(U-L)\\expit(\\eta_2)") &&
      has(flat_supplement, "Jacobian exactly once")
  )
}
for (name in names(method_invariants(main, supplement))) {
  expect(method_invariants(main, supplement)[[name]],
         paste("Advisor-revision method invariant:", name))
}
mutate <- function(text, before, after) {
  expect(has(text, before), paste("Missing mutation fixture:", before))
  sub(before, after, text, fixed = TRUE)
}
mutations <- list(
  list("scale prior omitted", mutate(main, "\\sigma\\sim\\IG(a_\\sigma,b_\\sigma)", "\\sigma>0"), supplement),
  list("product factor dropped", mutate(main, "\\Normal(0\\mid\\beta_j,\\zeta^2)", "1"), supplement),
  list("global shape loses prior contribution", mutate(main, "\\((r+1)/2\\)", "\\(r/2\\)"), supplement),
  list("random baseline inserted into fitted target", main,
       mutate(supplement, "\\vect\\Delta_1=\\vect\\beta_1",
              "\\vect\\Delta_1=\\vect\\beta_1-\\vect\\beta_{\\mathrm{base}}")),
  list("cross-level covariance removed", main,
       mutate(supplement, "\\operatorname{Cov}_q(\\beta_{k,j},\\beta_{k-1,j})", "0")),
  list("location average asserted to be predictive quantile",
       mutate(main, "Neither averaging conditional-quantile locations",
              "Averaging conditional-quantile locations always"), supplement),
  list("coordinate Jacobian lost", main,
       mutate(supplement, "J(\\vect\\eta)=\\sigma(U-L)\\expit(\\eta_2)", "J=1"))
)
for (item in mutations) {
  expect(!all(method_invariants(item[[2L]], item[[3L]])),
         paste("Mutation must be rejected:", item[[1L]]))
}
cat(sprintf(paste0("QDESN_READER_FOCUSED_EDITORIAL_REVISION_PASS: %d checks ",
                  "expected_mutation_rejections=%d scientific_runs=0\n"),
            checks, length(mutations)))
