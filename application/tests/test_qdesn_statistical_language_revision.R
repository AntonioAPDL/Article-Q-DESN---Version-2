#!/usr/bin/env Rscript

# Bounded editorial/invariance tests. Mutations are strings in memory; no
# manuscript, retained forecast, model object, or repository file is changed.
local({
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (exists("app_repo_root", mode = "function")) {
    root <- app_repo_root()
  } else {
    stopifnot(length(file_arg) == 1L)
    root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)),
      "..", ".."), mustWork = TRUE)
  }
  source(file.path(root, "scripts/check_qdesn_statistical_language_revision.R"),
    local = TRUE)
  read_text <- function(path) paste(readLines(file.path(root, path), warn = FALSE),
    collapse = "\n")
  main <- read_text("main.tex")
  supplement <- read_text("qdesn-supplement.tex")
  history <- read_text("docs/implementation_notes/statistical_language_reader_revision_20261019.md")
  passed <- app_check_statistical_language_revision(root)
  mutations <- 0L
  mutate_text <- function(text, before, after) {
    # Prose may wrap over source lines. Normalize whitespace before mutation
    # and require a real replacement, so a non-matching fixture cannot pass.
    text <- gsub("[[:space:]]+", " ", text)
    before <- gsub("[[:space:]]+", " ", before)
    changed <- gsub(before, after, text, fixed = TRUE)
    if (identical(changed, text)) stop(paste("Mutation fixture not found:", before),
      call. = FALSE)
    changed
  }
  reject <- function(label, changed_main = main, changed_supplement = supplement,
                     changed_history = history) {
    result <- tryCatch({
      app_statistical_language_semantics(changed_main, changed_supplement,
        changed_history)
      NULL
    }, error = identity)
    if (!inherits(result, "error")) stop(paste("Mutation was not rejected:", label),
      call. = FALSE)
    mutations <<- mutations + 1L
  }
  reject("GloFAS inputs relabeled as the latent quantity", changed_supplement = mutate_text(
    supplement, "Unknown future reference-streamflow values", "Unknown future GloFAS responses"))
  reject("undefined inverse logit", changed_supplement = mutate_text(
    supplement, "\\expit(a)=\\{1+\\exp(-a)\\}^{-1}", "\\expit(a)"))
  reject("dropped transformation Jacobian", changed_supplement = mutate_text(
    supplement, "J(\\vect\\eta)=\\sigma(U-L)\\expit(\\eta_2)", "J=1"))
  reject("forecast origin confused with fitting endpoint", changed_supplement = mutate_text(
    supplement, "_{o+h}", "_{T+h}"))
  reject("sorting and projection conflated", changed_supplement = mutate_text(
    supplement, "rearrangement by sorting", "rearrangement such as isotonic projection"))
  reject("supplementary acronym not introduced", changed_supplement = mutate_text(
    supplement, "Bayes (VB)", "Bayes"))
  reject("probability integration weights changed", changed_supplement = mutate_text(supplement,
    "0.025,\\ 0.10,\\ 0.20,\\ 0.25,\\ 0.20,\\ 0.10,\\ 0.025",
    "0.10,\\ 0.10,\\ 0.20,\\ 0.25,\\ 0.20,\\ 0.10,\\ 0.10"))
  reject("numerical monitor called a full ELBO", changed_supplement = paste(
    supplement, "Return ELBO history."))
  reject("optional baseline described as fitted", changed_supplement = mutate_text(supplement,
    "it was not fitted in the reported multiquantile simulation",
    "it was fitted in the reported multiquantile simulation"))
  reject("product-prior scale factor dropped", changed_supplement = mutate_text(supplement,
    "C_\\Delta(\\Theta_\\Delta)p(\\Theta_\\Delta)", "p(\\Theta_\\Delta)"))
  reject("cross-quantile covariance removed", changed_supplement = mutate_text(supplement,
    "\\operatorname{Cov}_q(\\beta_{k,j},\\beta_{k-1,j})", "0"))
  reject("variational stopping described as strict convergence", changed_supplement = paste(
    supplement, "Both fits have strict convergence."))
  reject("achieved stopping statistic changed", changed_supplement = mutate_text(
    supplement, "8.9279687", "1.9"))
  reject("input lag relabeled as measured reservoir memory", changed_supplement = paste(
    supplement, "The reservoir memory is 540 observations."))
  reject("historical unverified-target table made active", changed_supplement = paste(
    supplement, paste0("\\input{tables/",
      "joint_qdesn_article_validation_phase153_replication_summary_mq_display.tex}")))
  reject("historical target caveat lost", changed_history = mutate_text(
    history, "not verified under the corrected current posterior target", "verified"))
  reject("accepted simulation finding made provisional again", changed_main = paste(
    main, "[Simulation findings to be updated.]"))
  reject("streamflow finding broadened to undefined superiority", changed_main = mutate_text(
    main, "reduces quantile forecast loss relative to the uncorrected ensemble",
    "provides the best forecast correction"))
  reject("streamflow score improvement loses its comparator", changed_main = mutate_text(
    main, "relative to the uncorrected ensemble", "overall"))
  reject("streamflow interval-coverage result removed from the application", changed_main = mutate_text(
    main, "coverage of 21 of 28 observations for the nominal 90\\% interval",
    "favorable interval coverage"))
  reject("streamflow undercoverage concealed in the discussion", changed_main = mutate_text(
    main, "nominal 90\\% interval covers 75\\%", "interval has favorable coverage for"))
  reject("abstract acronym introduced without expansion", changed_main = mutate_text(
    main, "Asymmetric Laplace (AL)", "Asymmetric Laplace"))
  reject("pending PriceFM finding silently finalized", changed_main = mutate_text(
    main, "[PriceFM findings to be updated.]", "PriceFM is final."))
  reject("post-inspection selection history concealed", changed_main = mutate_text(
    main, "adopted after exploratory assessment", "prespecified before analysis"))
  reject("historical MQ caption restored", changed_supplement = mutate_text(
    supplement, "\\input{tables/qdesn_multiquantile_score_display.tex}",
    "\\input{tables/joint_qdesn_pure_desn_v2_mq_score_table.tex}"))
  cat(sprintf(paste0("QDESN_STATISTICAL_LANGUAGE_REVISION_TEST_PASS checks=%d ",
    "expected_mutation_rejections=%d scientific_runs=0\n"), length(passed), mutations))
})
