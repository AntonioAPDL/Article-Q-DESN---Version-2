#!/usr/bin/env Rscript

# Editorial and scientific-invariance checks for the final unified revision.
# This script reads tracked article sources only; it does not fit a model,
# recompute a score, or modify an article asset.

options(stringsAsFactors = FALSE, digits = 17)

file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
repo_path <- function(relative) file.path(repo_root, relative)
sha256 <- function(relative) unname(tools::sha256sum(repo_path(relative))[[1L]])
expect <- function(value, message) {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
read_text <- function(relative) {
  paste(readLines(repo_path(relative), warn = FALSE), collapse = "\n")
}

immutable_hashes <- c(
  "tables/qdesn_validation_500obs_metric_intervals_v14_summary.csv" =
    "897ec68de29b8bdec29ef8b5058dec5b9760707b5320eb82a2ff1112e6730080",
  "tables/qdesn_validation_500obs_dgp_oracle_reference_v1.csv" =
    "1adc9c8c83b3564ef84be90e146286feac604484638ee31bbe684b66cbe928a8",
  "tables/qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv" =
    "fefad4ff09b221483a2c299a06b7142d41090e06cfa9ad37f396a2551e9f398a",
  "tables/joint_qdesn_corrected_v4_posterior_dgp_integrated_acrps_summary.csv" =
    "2470ef53eed99899fea41b1f97cde18687b11c9d9b6455cda8dff8ea29b8adf8",
  "tables/joint_qdesn_corrected_v4_scenario_winner_summary.csv" =
    "f98ba9b18f4985afc085d68455e60a7e0bf19fd27bc86022591febd3518b98b2",
  "tables/joint_qdesn_corrected_v4_joint_independent_contrast_summary.csv" =
    "49cf419bdf0f4c89280f8b1d6a632c261d9c8b3eee70244376f6589f85a2fc34",
  "tables/joint_qdesn_corrected_v4_forecast_metric_summary.csv" =
    "8258d729ede6f577c0abbf3cabeb040d22cec0aafb72606aaa30c32322f8cdd6",
  "tables/joint_qdesn_corrected_v4_oracle_recovery_summary.csv" =
    "c160c0e12183ca3e1404e5efad8547dcb0599fe6b562b301a720173398b5d1aa",
  "tables/joint_qdesn_corrected_v4_crossing_and_adjustment_summary.csv" =
    "4f1efb0a95f23df485643ff9450272488eb48559c1f85fdd5dfd7c25e6be81e5",
  "tables/joint_qdesn_corrected_v4_phase181_reconciliation.csv" =
    "02deccb5d29df490b1031c52c9f3f1ffc817a37ffca4a14aaf3713c93d62274c",
  "tables/glofas_application_current_score_summary.csv" =
    "c15d21cda11c8c8a89742b32b8a0c07b85851176dac29c30076941e32c52c998",
  "tables/glofas_application_current_selection_manifest.csv" =
    "25691eddb333d85dbc00de8ec33389d23796499343e0b01500778754e94f2c1c",
  "tables/glofas_application_part4_forecast_scores__glofas_part4_joint_al_sweep10_20260911.csv" =
    "829d4467e4b734d4cd7a0dbab40ba72fe9b9c91c328908461f82f3093167d498",
  "tables/glofas_application_part4_selection_decision__glofas_part4_joint_al_sweep10_20260911.csv" =
    "59792f78a055943cab6dd2e6e3eb829f08df9df6e2f98add05a4bec595b907de",
  "tables/pricefm_r98_authoritative_registry.csv" =
    "4cf8ff653c6bd7fc64a2992fbfb6e1df48867d1b7d840cd8544fb30a5c538cb6",
  "tables/pricefm_r98_authority_transition_ledger.csv" =
    "35b0f3d55a1e5ac7e489b3cf171c0f9865e07a012e2fbb4a4674302fa5ef53cd",
  "tables/pricefm_r98_global_comparison.csv" =
    "e3831615ceefe497d68f72176c4a68437448634868aed4c2fada5029ec2768b4",
  "tables/pricefm_r98_fold_comparison.csv" =
    "b43bb3e933aa6507f00d740ca82884f626b67e9cf3f5c16c953cb489b5032db8",
  "tables/pricefm_r98_region_comparison.csv" =
    "b4ff02abf4cda266169acdba2c99708c4ff0b088891a2623256df00af99f21e1"
)
for (relative in names(immutable_hashes)) {
  expect(file.exists(repo_path(relative)), paste("Missing scientific input:", relative))
  expect(identical(sha256(relative), immutable_hashes[[relative]]),
         paste("Scientific input changed:", relative))
}

independent <- read.csv(
  repo_path("tables/qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv"),
  check.names = FALSE
)
joint_score <- read.csv(
  repo_path("tables/joint_qdesn_pure_desn_v1_forecast_score_summary.csv"),
  check.names = FALSE
)
joint_oracle <- read.csv(
  repo_path("tables/joint_qdesn_pure_desn_v1_fit_oracle_diagnostics.csv"),
  check.names = FALSE
)
crossing <- read.csv(
  repo_path("tables/joint_qdesn_pure_desn_v1_forecast_score_summary.csv"),
  check.names = FALSE
)
expect(nrow(independent) == 216L &&
         sum(independent$diagnostic_grade == "WARN") == 5L,
       "The independent figure surface or warning count changed.")
joint_score <- joint_score[joint_score$inference_method == "mcmc", , drop = FALSE]
joint_oracle <- joint_oracle[joint_oracle$inference_method == "mcmc", , drop = FALSE]
crossing <- crossing[crossing$inference_method == "mcmc", , drop = FALSE]
expect(nrow(joint_score) == 32L && nrow(joint_oracle) == 32L &&
         all(joint_score$canonical_contract_crossing_pairs == 0L) &&
         all(crossing$canonical_contract_crossing_pairs == 0L),
       "The JOINT article surface or transformed crossings changed.")
forecast_crossing <- aggregate(
  canonical_raw_crossing_pairs ~ model_id, crossing, sum
)
expected_crossing <- c(
  joint_qdesn_rhs_mcmc = 11L,
  qdesn_rhs_independent_mcmc = 2645L,
  joint_exqdesn_rhs_mcmc = 0L,
  exqdesn_rhs_independent_mcmc = 288L
)
observed_crossing <- forecast_crossing$canonical_raw_crossing_pairs[
  match(names(expected_crossing), forecast_crossing$model_id)
]
expect(identical(as.integer(observed_crossing), unname(expected_crossing)),
       "The JOINT raw crossing totals changed.")

main <- read_text("main.tex")
supplement <- read_text("qdesn-supplement.tex")
manuscript <- paste(main, supplement, sep = "\n")
pricefm_aliases <- read_text("tables/pricefm_full_current_outputs.tex")
internal_terms <- paste0(
  "\\b(lane|worker|queue|coordinator|handoff|launch lock|runtime artifact|",
  "promotion packet|score contract|frozen HEAD|frozen branch)\\b"
)
expect(!grepl(internal_terms, manuscript, ignore.case = TRUE, perl = TRUE),
       "Internal development terminology entered the manuscript.")
expect(!grepl("\\\\lambda\\s*\\(\\s*\\\\gamma", manuscript, perl = TRUE),
       "The exAL shift/local-scale notation collision remains.")
expect(!grepl("\\\\mathcal\\s*\\{[PCGRM]\\}", manuscript, perl = TRUE),
       "A one-use calligraphic collection symbol remains.")
expect(!grepl("p_q|q=1,\\\\ldots,Q|Q=1", manuscript, perl = TRUE),
       "The superseded quantile-grid index notation remains.")
expect(grepl("D_{p_0}(\\gamma)", main, fixed = TRUE) &&
         grepl("D_{p_0}(\\gamma)", supplement, fixed = TRUE),
       "The exAL positive-shift coefficient is not defined consistently.")
expect(grepl("\\aCRPS_{p_1:p_K}", main, fixed = TRUE) &&
         grepl("\\aCRPS_{p_1:p_K}", supplement, fixed = TRUE),
       "The finite-grid integrated check-loss notation is inconsistent.")

expect(grepl(
  "tables/qdesn_validation_500obs_v14_mcmc_forecast_metric_interval_figures.tex",
  main, fixed = TRUE
), "The main article does not contain the independent forecast figures.")
expect(grepl("tables/joint_qdesn_pure_desn_v1_forecast_figure.tex",
             main, fixed = TRUE),
       "The main article does not contain the JOINT forecast figure.")
expect(grepl(
  "tables/qdesn_validation_500obs_v14_mcmc_fit_metric_interval_figure.tex",
  supplement, fixed = TRUE
) && grepl("tables/qdesn_validation_500obs_v14_vb_metric_interval_figures.tex",
           supplement, fixed = TRUE) &&
  grepl("tables/joint_qdesn_pure_desn_v1_fit_figure.tex",
        supplement, fixed = TRUE),
"The supplement does not contain all fitting-sample figures.")
expect(!grepl("v14_vb_forecast_", supplement, fixed = TRUE),
       "Repeated VB forecast figures remain active in the supplement.")

reader_facing_independent <- paste(c(
  main,
  supplement,
  read_text("tables/qdesn_validation_500obs_metric_intervals_v14_prose.tex"),
  read_text("tables/qdesn_validation_500obs_v14_mcmc_forecast_metric_interval_figures.tex"),
  read_text("tables/qdesn_validation_500obs_v14_mcmc_metric_intervals_normal.tex"),
  read_text("tables/qdesn_validation_500obs_v14_mcmc_metric_intervals_laplace.tex"),
  read_text("tables/qdesn_validation_500obs_v14_mcmc_metric_intervals_gausmix.tex")
), collapse = "\n")
expect(!grepl(
  "dagger|diagnostic caution|diagnostic qualification|receive warnings|warning details",
  reader_facing_independent, ignore.case = TRUE
), "Internal independent-validation diagnostics remain reader-facing.")

reader_facing_joint <- paste(c(
  main,
  supplement,
  read_text("tables/joint_qdesn_pure_desn_v1_score_table.tex"),
  read_text("tables/joint_qdesn_pure_desn_v1_crossing_table.tex"),
  read_text("tables/joint_qdesn_pure_desn_v1_recursive_policy_table.tex"),
  read_text("tables/joint_qdesn_pure_desn_v1_oracle_recovery_table.tex"),
  read_text("tables/joint_qdesn_pure_desn_v1_forecast_figure.tex"),
  read_text("tables/joint_qdesn_pure_desn_v1_fit_figure.tex")
), collapse = "\n")
expect(!grepl(
  "canonical-action|Canonical action|black vertical|raw/reported",
  reader_facing_joint, ignore.case = TRUE
), "Reader-facing JOINT presentation still contains internal action or count labels.")
expect(grepl("47,520 adjacent-level", main, fixed = TRUE) &&
         grepl("0.023\\%", main, fixed = TRUE) &&
         grepl("5.566\\%", main, fixed = TRUE) &&
         grepl("0.606\\%", main, fixed = TRUE),
       "The main article does not report normalized JOINT crossing rates.")
expect(grepl(
  "posterior draws",
  read_text("tables/joint_qdesn_pure_desn_v1_crossing_table.tex"),
  fixed = TRUE
), "The supplement does not distinguish crossing frequency from adjustment magnitude.")

expect(grepl("prospectively", main, fixed = TRUE) &&
         grepl("slightly higher aggregate AQL", main, fixed = TRUE) &&
         grepl("7.217", pricefm_aliases, fixed = TRUE) &&
         grepl("7.039", pricefm_aliases, fixed = TRUE),
       "The main article does not state the R98 PriceFM result accurately.")
expect(!grepl("PricefmSelection|pricefm_r91_selective_promotions|PricefmAligned",
              manuscript, perl = TRUE),
       "A deprecated R91/R92 PriceFM reader-facing construct remains.")
# The complete R98 registry remains immutable and hash-verified in Git above.
# It and the transition ledger contain local source paths, not TeX inputs.
# They must not enter the article-only upload.
expect(!grepl("pricefm_r98_authoritative_registry.csv|pricefm_r98_authority_transition_ledger.csv",
              read_text("overleaf/article_files.txt")),
       "Machine-local PriceFM provenance entered the article-only snapshot.")

article_files <- readLines(repo_path("overleaf/article_files.txt"), warn = FALSE)
public_text_files <- article_files[grepl("\\.(tex|csv|json|bib)$", article_files)]
public_text <- paste(vapply(public_text_files, read_text, character(1L)), collapse = "\n")
expect(!grepl("/data/|/home/|/tmp/|local_trackers|application/cache|\\.(rds|rda|RData)([\"[:space:]]|$)",
              public_text, ignore.case = TRUE),
       "Private source paths or runtime-object references remain in the upload.")
expect(!any(grepl("v14_vb_forecast_", article_files, fixed = TRUE)),
       "Repeated VB forecast figures remain in the article-only snapshot.")
expect(file.exists(repo_path(
  "docs/implementation_notes/joint_qvp_rhs_deferred_rerun_register_20260908.md"
)), "The deferred RHS correction register is missing.")

# Search III replaces the live GloFAS projection, not the retained historical
# ledgers or any independent, JOINT, or PriceFM scientific input above.
glofas_tag <- "glofas_search3_part1234_final_20261007"
glofas_aliases <- read_text("tables/glofas_application_current_outputs.tex")
glofas_read <- function(suffix) read.csv(repo_path(paste0(
  "tables/", glofas_tag, "_", suffix, ".csv"
)), check.names = FALSE)
expect(grepl(glofas_tag, glofas_aliases, fixed = TRUE) &&
         grepl("search3\\_ref\\_001", glofas_aliases, fixed = TRUE) &&
         grepl("search3\\_dis\\_007", glofas_aliases, fixed = TRUE),
       "The active GloFAS aliases do not identify Search III.")
glofas_scores <- glofas_read("part4_scores")
expect(nrow(glofas_scores) == 7L && !anyDuplicated(glofas_scores$family) &&
         all(glofas_scores$n_scored_horizons == 28L) &&
         glofas_scores$family[which.min(glofas_scores$crps_grid_log1p)] == "Independent AL",
       "The complete descriptive seven-family issued-window comparison changed.")
glofas_recursive <- glofas_read("part123_scores")
glofas_no_score <- glofas_recursive[glofas_recursive$part == "Part 2", ]
expect(nrow(glofas_recursive) == 18L && nrow(glofas_no_score) == 6L &&
         all(glofas_no_score$n_scored_horizons == 0L) &&
         all(is.na(glofas_no_score$crps_grid_log1p)) &&
         all(glofas_recursive$n_scored_horizons[glofas_recursive$part != "Part 2"] == 30L),
       "The Part 2 no-score or 30-versus-28-horizon boundary changed.")
glofas_convergence <- glofas_read("convergence")
expect(nrow(glofas_convergence) == 2L &&
         all(glofas_convergence$converged_outer & glofas_convergence$converged_inner &
             glofas_convergence$converged_rhs & glofas_convergence$full_state_pass) &&
         all(glofas_convergence$terminal_consecutive_passes >= 3L) &&
         nrow(glofas_read("calibration")) == 49L,
       "Both corrected joint fits or the complete calibration surface failed.")
expect(!any(glofas_read("selected_specifications")$protected_window_selection) &&
         all(glofas_read("decision_ledger")$protected_window_selection == "No"),
       "Protected-window results entered GloFAS model selection.")
for (macro in c("CurrentPartOneFigure", "CurrentPartTwoFigure", "CurrentPartThreeFigure",
                "CurrentConvergenceFigure", "CurrentCalibrationFigure")) {
  expect(grepl(paste0("\\GlofasApplication", macro), supplement, fixed = TRUE),
         paste("Supplement omits the GloFAS figure role:", macro))
}
expect(grepl("\\GlofasApplicationCurrentForecastWindowFigure", main, fixed = TRUE) &&
         grepl("descriptive", main, fixed = TRUE) &&
         grepl("three and one adjacent-quantile crossing pairs", main, fixed = TRUE),
       "Main GloFAS results omit the issued-window figure, descriptive scope, or crossing disclosure.")
active_glofas <- article_files[grepl("^tables/glofas_|^figures/glofas", article_files)]
expect(length(active_glofas) > 10L &&
         !any(grepl("sweep10|fr09|part4_joint_al_sweep", active_glofas, ignore.case = TRUE)) &&
         paste0("tables/", glofas_tag, "_publication_manifest.csv") %in% article_files,
       "Overleaf contains stale GloFAS authority or lacks its publication manifest.")
glofas_reader_text <- paste(c(manuscript, vapply(
  active_glofas[grepl("\\.(tex|csv)$", active_glofas)], read_text, character(1L)
)), collapse = "\n")
expect(!grepl("glofas_part4_joint_al_sweep10|0\\.8374|0\\.004153|cap-stabilized|not strictly outer-converged|selected Joint AL|near-nominal",
              glofas_reader_text, ignore.case = TRUE) &&
         !grepl("/data/|/home/|/tmp/|local_trackers|application/cache|\\.(rds|rda|RData|log)([\"[:space:]]|$)",
                glofas_reader_text, ignore.case = TRUE),
       "Stale authority or private/runtime information remains reader-facing.")
glofas_check <- system2(file.path(R.home("bin"), "Rscript"),
  shQuote(repo_path("application/scripts/448_check_glofas_search3_article_projection.R")),
  stdout = TRUE, stderr = TRUE)
expect(is.null(attr(glofas_check, "status")) &&
         any(grepl("GLOFAS_SEARCH3_ARTICLE_PROJECTION_CHECK=PASS", glofas_check, fixed = TRUE)),
       "The full GloFAS projection contract failed.")

abstract <- sub(".*\\\\begin\\{abstract\\}", "", main)
abstract <- sub("\\\\end\\{abstract\\}.*", "", abstract)
abstract_plain <- gsub("\\\\[A-Za-z]+|[{}$]", " ", abstract)
abstract_words <- strsplit(trimws(gsub("[^[:alnum:]'-]+", " ", abstract_plain)),
                           "[[:space:]]+")[[1L]]
expect(length(abstract_words) <= 250L,
       "The abstract exceeds the 250-word editorial limit.")

# Advisor-revision checks supplement, rather than replace, the numerical,
# provenance, privacy, and figure-placement assertions above.
main_title_text <- gsub("\\\\", " ", main, fixed = TRUE)
expect(grepl("Bayesian Quantile Regression with Deep Echo State Network Features",
             main_title_text, fixed = TRUE) &&
         grepl("Bayesian Quantile Regression with Deep Echo State Network Features",
               supplement, fixed = TRUE),
       "The main and supplementary titles disagree.")
model_start <- regexpr("\\subsection{Single-level quantile regression}", main,
                       fixed = TRUE)[1L]
desn_start <- regexpr("\\subsection{Deep echo state network features}", main,
                      fixed = TRUE)[1L]
expect(model_start > 0L && desn_start > model_start,
       "The quantile regression must precede the DESN construction.")
expect(grepl("\\vect b_1^{\\mathrm{in}}", main, fixed = TRUE) &&
         grepl("\\vect b_1^{\\mathrm{in}}", supplement, fixed = TRUE),
       "The fixed first-layer input bias is not described consistently.")
expect(grepl("\\label{eq:supp_ns_product_factor}", supplement, fixed = TRUE) &&
         grepl("C_\\Delta(\\Theta_\\Delta)p(\\Theta_\\Delta)", supplement, fixed = TRUE) &&
         grepl("C_0(\\Theta_0)p(\\Theta_0)", supplement, fixed = TRUE),
       "The complete product-RHS prior omits its scale-dependent factors.")
expect(grepl("fitted anchor hierarchy at any", supplement, fixed = TRUE) &&
         !grepl("if \\(K>1\\)", supplement, fixed = TRUE),
       "The fitted anchor algorithm must not infer a random baseline from grid size.")
expect(grepl("evaluat", main, fixed = TRUE) &&
         grepl("over the evaluation range", main, fixed = TRUE) &&
         grepl("\\label{eq:crps-integrated-check-main}", main, fixed = TRUE) &&
         grepl("\\label{eq:supp-crps-integrated-check}", supplement, fixed = TRUE),
       "The score definitions must retain integrated check loss and evaluation-range scope.")
expect(grepl("DeLeonPradoSanso2026HydrologicProducts", main, fixed = TRUE) &&
         grepl("@misc{DeLeonPradoSanso2026HydrologicProducts,", read_text("refs.bib"),
               fixed = TRUE),
       "The distinct hydrologic predecessor is not cited.")
expect(grepl("released load, solar, and wind forecast", main, fixed = TRUE) &&
         grepl("issue-time vintages were not separately verified", main, fixed = TRUE) &&
         !grepl("retrospectively observed own-region", manuscript, fixed = TRUE) &&
         grepl("\\label{tab:supp-pricefm-fold-design}", supplement, fixed = TRUE),
       "PriceFM covariate availability or the executed fold design is misstated.")
expect(grepl("do not isolate", supplement, fixed = TRUE) &&
         grepl("historical comparisons", supplement, fixed = TRUE) &&
         grepl("not been", supplement, fixed = TRUE) &&
         grepl("corrected current posterior target", supplement, fixed = TRUE),
       "Historical sensitivities must not certify the current posterior analysis.")
expect(grepl("historical single-chain comparison",
             read_text("tables/qdesn_validation_mcmc_five_chain_sensitivity.tex"),
             fixed = TRUE) &&
         !grepl("main article's Gaussian MCMC",
                read_text("tables/qdesn_validation_mcmc_five_chain_sensitivity.tex"),
                fixed = TRUE),
       "The historical sensitivity caption falsely identifies its reference as current.")

cat(sprintf(
  paste0("QDESN_FINAL_MANUSCRIPT_REVISION_CHECK=PASS scientific_files=%d ",
         "independent_roles=216 joint_oracle=32 joint_forecast=32 ",
         "reader_facing_internal_markers=0 abstract_words=%d\n"),
  length(immutable_hashes), length(abstract_words)
))
