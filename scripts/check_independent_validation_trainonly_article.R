#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/",
  mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
config_path <- file.path(repo_root, "application", "config", "independent_validation_trainonly_v1.yaml")
config <- yaml::read_yaml(config_path)
validation_root <- normalizePath(config$validation_root, winslash = "/", mustWork = TRUE)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
as_bool <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  tolower(as.character(x)) %in% c("true", "t", "1", "yes")
}
resolve_validation <- function(relative_path) {
  normalizePath(file.path(validation_root, relative_path), winslash = "/", mustWork = TRUE)
}
resolve_article <- function(relative_path) {
  normalizePath(file.path(repo_root, relative_path), winslash = "/", mustWork = TRUE)
}

interface_path <- resolve_validation(config$interface_relative_path)
source_manifest_path <- resolve_validation(config$manifest_relative_path)
source_ledger_path <- resolve_validation(config$source_ledger_relative_path)
if (!identical(sha256(interface_path), as.character(config$interface_sha256)) ||
    !identical(sha256(source_manifest_path), as.character(config$manifest_sha256)) ||
    !identical(sha256(source_ledger_path), as.character(config$source_ledger_sha256))) {
  stop("Pinned validation input hashes do not match.", call. = FALSE)
}

source <- read.csv(interface_path, check.names = FALSE, stringsAsFactors = FALSE)
summary <- read.csv(resolve_article(config$outputs$summary_csv), check.names = FALSE,
                    stringsAsFactors = FALSE)
compat <- read.csv(resolve_article(config$outputs$compatibility_summary_csv), check.names = FALSE,
                   stringsAsFactors = FALSE)
if (!identical(source, summary) || !identical(source, compat) || nrow(source) != 72L) {
  stop("Generated article summaries differ from the pinned interface.", call. = FALSE)
}

expected <- expand.grid(
  inference = unlist(config$expected_inference, use.names = FALSE),
  model_variant = unlist(config$expected_models, use.names = FALSE),
  family = unlist(config$expected_families, use.names = FALSE),
  tau = as.numeric(unlist(config$expected_taus, use.names = FALSE)),
  stringsAsFactors = FALSE
)
source_key <- with(source, paste(inference, model_variant, family, sprintf("%.2f", tau)))
expected_key <- with(expected, paste(inference, model_variant, family, sprintf("%.2f", tau)))
metric_cols <- c("fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000")
if (anyDuplicated(source_key) || !setequal(source_key, expected_key) ||
    any(!is.finite(as.numeric(unlist(source[metric_cols], use.names = FALSE)))) ||
    any(source$status != "SUCCESS") || any(grepl("ridge", source$model_variant)) ||
    !all(source$preprocessing_scope[grepl("^qdesn_", source$model_variant)] == "train_only") ||
    !all(source$source_registry_hash_value == config$source_registry_hash_value)) {
  stop("Generated summary violates the scientific table contract.", call. = FALSE)
}
qdesn_rows <- grepl("^qdesn_", source$model_variant)
if (!all(as_bool(source$article_consumption_allowed)) ||
    any(source$rolling_rebaseline_state != config$rolling_rebaseline_state) ||
    any(source$forecast_metric_contract[qdesn_rows] != config$qdesn_forecast_metric_contract) ||
    any(source$promotion_validation_branch != config$promotion_validation_branch) ||
    any(source$promotion_validation_commit != config$promotion_validation_commit) ||
    any(source$rolling_evidence_promotion_id[qdesn_rows] != config$promotion_id)) {
  stop("Generated summary is not the authoritative rolling-origin rebaseline.", call. = FALSE)
}

table_paths <- unlist(config$outputs[c(
  "protocol_tex", "family_wrapper_tex", "combined_tex", "normal_tex", "laplace_tex",
  "gausmix_tex", "mcmc_wrapper_tex", "mcmc_normal_tex", "mcmc_laplace_tex",
  "mcmc_gausmix_tex"
)], use.names = FALSE)
table_paths <- vapply(table_paths, resolve_article, character(1L))
table_text <- paste(unlist(lapply(table_paths, readLines, warn = FALSE)), collapse = "\n")
if (grepl("QDESN ridge|exQDESN ridge|VB--LD|Final TT500", table_text) ||
    !grepl("Q--DESN AL--RHS", table_text, fixed = TRUE) ||
    !grepl("Q--DESN exAL--RHS", table_text, fixed = TRUE) ||
    !grepl("Forecast check loss", table_text, fixed = TRUE)) {
  stop("Generated tables contain a stale label or omit a required label.", call. = FALSE)
}

figure_data_path <- resolve_article(config$outputs$figure_data)
figure_pdf_path <- resolve_article(config$outputs$figure_pdf)
figure_data <- read.csv(figure_data_path, check.names = FALSE, stringsAsFactors = FALSE)
if (nrow(figure_data) != 108L || file.info(figure_pdf_path)$size < 5000L ||
    !setequal(unique(figure_data$metric), metric_cols) ||
    any(!is.finite(figure_data$ratio_to_best)) ||
    any(figure_data$ratio_to_best < 1 - 1e-10)) {
  stop("The MCMC comparison figure is incomplete.", call. = FALSE)
}

main_text <- paste(readLines(file.path(repo_root, "main.tex"), warn = FALSE), collapse = "\n")
supp_text <- paste(readLines(file.path(repo_root, "qdesn-supplement.tex"), warn = FALSE), collapse = "\n")
if (!grepl("tables/qdesn_validation_tt500_final_mcmc_tables.tex", main_text, fixed = TRUE) ||
    !grepl("figures/independent_simulation/qdesn_mcmc_metric_envelope_heatmap.pdf", main_text,
           fixed = TRUE) ||
    !grepl("train-only preprocessing", main_text, fixed = TRUE) ||
    grepl("A separate full-budget confirmation used one coherent", main_text, fixed = TRUE) ||
    !grepl("tables/qdesn_validation_tt500_final_tables.tex", supp_text, fixed = TRUE) ||
    !grepl("train-only preprocessing replay", supp_text, fixed = TRUE)) {
  stop("Manuscript prose is not wired to the corrected artifacts.", call. = FALSE)
}

manifest_paths <- vapply(
  unlist(config$outputs[c("table_manifest", "mcmc_manifest", "figure_manifest")], use.names = FALSE),
  resolve_article,
  character(1L)
)
manifest_text <- paste(unlist(lapply(manifest_paths, readLines, warn = FALSE)), collapse = "\n")
if (!grepl(config$promotion_id, manifest_text, fixed = TRUE) ||
    !grepl(config$interface_sha256, manifest_text, fixed = TRUE) ||
    !grepl(config$rolling_rebaseline_state, manifest_text, fixed = TRUE) ||
    !grepl(config$qdesn_forecast_metric_contract, manifest_text, fixed = TRUE) ||
    grepl("/home/jaguir26/local/src", manifest_text, fixed = TRUE)) {
  stop("Generated manifests violate the provenance contract.", call. = FALSE)
}

verify_indented_hashes <- function(manifest_path) {
  entries <- grep(
    "^  [^:]+: [[:xdigit:]]{64}$",
    readLines(manifest_path, warn = FALSE),
    value = TRUE
  )
  if (!length(entries)) {
    stop(sprintf("No artifact hashes found in %s.", basename(manifest_path)), call. = FALSE)
  }
  relative_paths <- sub("^  ([^:]+): [[:xdigit:]]{64}$", "\\1", entries)
  expected_hashes <- sub("^  [^:]+: ([[:xdigit:]]{64})$", "\\1", entries)
  artifact_paths <- vapply(relative_paths, resolve_article, character(1L))
  if (!identical(unname(tools::sha256sum(artifact_paths)), unname(expected_hashes))) {
    stop(sprintf("An artifact hash is stale in %s.", basename(manifest_path)), call. = FALSE)
  }
}
verify_indented_hashes(manifest_paths[[1L]])
verify_indented_hashes(manifest_paths[[2L]])

figure_manifest <- readLines(manifest_paths[[3L]], warn = FALSE)
manifest_value <- function(key) {
  values <- sub(paste0("^", key, ": "), "", grep(paste0("^", key, ": "), figure_manifest, value = TRUE))
  if (length(values) != 1L) {
    stop(sprintf("Figure manifest field %s is missing or duplicated.", key), call. = FALSE)
  }
  values[[1L]]
}
figure_artifacts <- vapply(
  c(manifest_value("figure_data"), manifest_value("figure_pdf")),
  resolve_article,
  character(1L)
)
figure_hashes <- c(manifest_value("figure_data_sha256"), manifest_value("figure_pdf_sha256"))
if (!identical(unname(tools::sha256sum(figure_artifacts)), unname(figure_hashes))) {
  stop("A figure artifact hash is stale.", call. = FALSE)
}

forbidden <- list.files(
  repo_root,
  pattern = "[.](rds|rda|RData)$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)
tracked_forbidden <- forbidden[vapply(forbidden, function(path) {
  relative <- substring(normalizePath(path, winslash = "/"), nchar(repo_root) + 2L)
  status <- system2("git", c("-C", repo_root, "ls-files", "--error-unmatch", relative),
                    stdout = FALSE, stderr = FALSE)
  identical(status, 0L)
}, logical(1L))]
if (length(tracked_forbidden)) {
  stop("A forbidden binary payload is tracked in the article repository.", call. = FALSE)
}

cat("ARTICLE_VALIDATION_CHECK=PASS\n")
cat(sprintf("ROWS=%d\n", nrow(source)))
cat(sprintf("VB_ROWS=%d\n", sum(source$inference == "vb")))
cat(sprintf("MCMC_ROWS=%d\n", sum(source$inference == "mcmc")))
cat(sprintf("RIDGE_ROWS=%d\n", sum(grepl("ridge", source$model_variant))))
cat(sprintf("FIGURE_ROWS=%d\n", nrow(figure_data)))
cat(sprintf("SIGNOFF=%s\n", paste(names(table(source$signoff_grade)), table(source$signoff_grade), collapse = ",")))
