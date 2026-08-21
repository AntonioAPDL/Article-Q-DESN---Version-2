#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/",
  mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  idx <- which(args == flag)
  if (!length(idx) || idx[[1L]] == length(args)) return(default)
  args[[idx[[1L]] + 1L]]
}
config_path <- normalizePath(
  get_arg(
    "--config",
    file.path(repo_root, "application", "config", "independent_validation_trainonly_v1.yaml")
  ),
  winslash = "/",
  mustWork = TRUE
)
config <- yaml::read_yaml(config_path)
validation_root <- normalizePath(
  get_arg("--validation-root", config$validation_root),
  winslash = "/",
  mustWork = TRUE
)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
as_bool <- function(x) {
  if (is.logical(x)) return(!is.na(x) & x)
  tolower(as.character(x)) %in% c("true", "t", "1", "yes")
}
resolve_validation <- function(relative_path) {
  normalizePath(file.path(validation_root, relative_path), winslash = "/", mustWork = TRUE)
}
resolve_portable_validation_path <- function(path, label) {
  if (length(path) != 1L || is.na(path) || !nzchar(path) || grepl("^/", path)) {
    stop(sprintf("%s must be a nonempty validation-relative path.", label), call. = FALSE)
  }
  resolved <- normalizePath(file.path(validation_root, path), winslash = "/", mustWork = TRUE)
  if (!startsWith(resolved, paste0(validation_root, "/"))) {
    stop(sprintf("%s escapes the validation root.", label), call. = FALSE)
  }
  resolved
}
resolve_article <- function(relative_path) {
  normalizePath(file.path(repo_root, relative_path), winslash = "/", mustWork = TRUE)
}

interface_path <- resolve_validation(config$interface_relative_path)
source_manifest_path <- resolve_validation(config$manifest_relative_path)
source_ledger_path <- resolve_validation(config$source_ledger_relative_path)
article_delta_path <- resolve_validation(config$article_delta_relative_path)
promotion_decision_path <- resolve_validation(config$promotion_decision_ledger_relative_path)
remaining_gap_path <- resolve_validation(config$remaining_gap_ledger_relative_path)
promotion_effect_path <- resolve_validation(config$promotion_effect_relative_path)
chain_evidence_path <- resolve_validation(config$chain_evidence_relative_path)
promoted_specifications_path <- resolve_validation(config$promoted_specifications_relative_path)
rollback_ledger_path <- resolve_validation(config$rollback_ledger_relative_path)
if (!identical(sha256(interface_path), as.character(config$interface_sha256)) ||
    !identical(sha256(source_manifest_path), as.character(config$manifest_sha256)) ||
    !identical(sha256(source_ledger_path), as.character(config$source_ledger_sha256)) ||
    !identical(sha256(article_delta_path), as.character(config$article_delta_sha256)) ||
    !identical(sha256(promotion_decision_path), as.character(config$promotion_decision_ledger_sha256)) ||
    !identical(sha256(remaining_gap_path), as.character(config$remaining_gap_ledger_sha256)) ||
    !identical(sha256(promotion_effect_path), as.character(config$promotion_effect_sha256)) ||
    !identical(sha256(chain_evidence_path), as.character(config$chain_evidence_sha256)) ||
    !identical(sha256(promoted_specifications_path),
               as.character(config$promoted_specifications_sha256)) ||
    !identical(sha256(rollback_ledger_path), as.character(config$rollback_ledger_sha256))) {
  stop("Pinned validation input hashes do not match.", call. = FALSE)
}

source <- read.csv(interface_path, check.names = FALSE, stringsAsFactors = FALSE)
source_manifest <- jsonlite::read_json(source_manifest_path, simplifyVector = TRUE)
source_ledger <- read.csv(source_ledger_path, check.names = FALSE, stringsAsFactors = FALSE)
article_delta <- read.csv(article_delta_path, check.names = FALSE, stringsAsFactors = FALSE)
summary <- read.csv(resolve_article(config$outputs$summary_csv), check.names = FALSE,
                    stringsAsFactors = FALSE)
compat <- read.csv(resolve_article(config$outputs$compatibility_summary_csv), check.names = FALSE,
                   stringsAsFactors = FALSE)
if (!identical(source, summary) || !identical(source, compat) || nrow(source) != 72L) {
  stop("Generated article summaries differ from the pinned interface.", call. = FALSE)
}
manifest_jobs <- as.integer(unlist(source_manifest$campaign_jobs, use.names = TRUE))
expected_jobs <- as.integer(unlist(config$campaign_jobs, use.names = TRUE))
names(manifest_jobs) <- names(unlist(source_manifest$campaign_jobs, use.names = TRUE))
names(expected_jobs) <- names(unlist(config$campaign_jobs, use.names = TRUE))
if (!identical(as.character(source_manifest$promotion_id), as.character(config$promotion_id)) ||
    !identical(as.character(source_manifest$promotion_status), as.character(config$promotion_status)) ||
    !identical(as.character(source_manifest$scientific_decision), as.character(config$scientific_decision)) ||
    !identical(as.character(source_manifest$base_promotion_id), as.character(config$base_promotion_id)) ||
    !identical(as.character(source_manifest$rendered_article_base_id),
               as.character(config$rendered_article_base_id)) ||
    !identical(as.character(source_manifest$exal_method_id), as.character(config$exal_method_id)) ||
    !identical(as.character(source_manifest$al_method_id), as.character(config$al_method_id)) ||
    !identical(as.character(source_manifest$run_id), as.character(config$campaign_run_id)) ||
    !identical(as.character(source_manifest$run_tag), as.character(config$campaign_run_tag)) ||
    !identical(as.character(source_manifest$scientific_design_commit),
               as.character(config$scientific_design_commit)) ||
    !identical(as.character(source_manifest$confirmation_execution_commit),
               as.character(config$confirmation_execution_commit)) ||
    !identical(as.character(source_manifest$closeout_implementation_commit),
               as.character(config$closeout_implementation_commit)) ||
    !identical(manifest_jobs, expected_jobs) ||
    !identical(as.integer(source_manifest$canonical_chains), as.integer(config$canonical_chains)) ||
    !identical(as.integer(source_manifest$promoted_metric_roles), as.integer(config$promoted_metric_roles)) ||
    !identical(as.integer(source_manifest$article_numeric_updates_from_rendered_v6),
               as.integer(config$article_numeric_updates_from_rendered_base)) ||
    !identical(as.integer(source_manifest$retained_iterations_per_chain),
               as.integer(config$retained_iterations_per_chain)) ||
    !identical(as.character(source_manifest$promotion_effect_from_v8_sha256),
               as.character(config$promotion_effect_sha256)) ||
    !identical(as.character(source_manifest$chain_evidence_sha256),
               as.character(config$chain_evidence_sha256)) ||
    !identical(as.character(source_manifest$promoted_specifications_sha256),
               as.character(config$promoted_specifications_sha256)) ||
    !identical(as.character(source_manifest$rollback_ledger_sha256),
               as.character(config$rollback_ledger_sha256)) ||
    !identical(as.integer(source_manifest$binary_payload_count), 0L) ||
    !isTRUE(source_manifest$storage_policy_pass)) {
  stop("The adaptive-confirmation manifest does not match the pinned article contract.",
       call. = FALSE)
}
if (!all(c("source_id", "path", "sha256", "role") %in% names(source_ledger)) ||
    anyDuplicated(source_ledger$source_id) || any(grepl("^/", source_ledger$path))) {
  stop("The source ledger is malformed or nonportable.", call. = FALSE)
}
source_ledger_paths <- vapply(seq_len(nrow(source_ledger)), function(i) {
  resolve_portable_validation_path(source_ledger$path[[i]], sprintf("Source ledger row %d", i))
}, character(1L))
if (!identical(unname(tools::sha256sum(source_ledger_paths)), unname(source_ledger$sha256))) {
  stop("A source-ledger hash is stale.", call. = FALSE)
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
delta_required <- c(
  "inference", "model_variant", "family", "tau", "metric", "rendered_v6_value",
  "authoritative_value", "relative_gain_pct", "source_promotion_id"
)
if (!all(delta_required %in% names(article_delta)) ||
    nrow(article_delta) != as.integer(config$article_numeric_updates_from_rendered_base) ||
    anyDuplicated(with(article_delta, paste(inference, model_variant, family, tau, metric))) ||
    any(!article_delta$metric %in% metric_cols) ||
    any(article_delta$authoritative_value >= article_delta$rendered_v6_value) ||
    any(article_delta$relative_gain_pct <= 0)) {
  stop("The article-delta ledger violates the strict-improvement contract.", call. = FALSE)
}
delta_matches <- vapply(seq_len(nrow(article_delta)), function(i) {
  row <- article_delta[i, , drop = FALSE]
  source_row <- source[
    source$inference == row$inference & source$model_variant == row$model_variant &
      source$family == row$family & abs(source$tau - row$tau) < 1e-12,
    ,
    drop = FALSE
  ]
  nrow(source_row) == 1L &&
    abs(as.numeric(source_row[[row$metric]][[1L]]) - row$authoritative_value) < 1e-12 &&
    identical(as.character(source_row$source_promotion_id[[1L]]),
              as.character(row$source_promotion_id[[1L]]))
}, logical(1L))
if (!all(delta_matches)) {
  stop("The article-delta ledger does not match the generated summary.", call. = FALSE)
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
expected_state_counts <- as.integer(unlist(config$expected_confirmation_states, use.names = TRUE))
names(expected_state_counts) <- names(unlist(config$expected_confirmation_states, use.names = TRUE))
observed_state_counts <- table(factor(
  source$confirmation_state,
  levels = names(expected_state_counts)
))
confirmed <- source$confirmation_state != "INHERITED_FROM_V5"
current_confirmed <- source$confirmation_state == config$current_confirmation_state
if (!identical(as.integer(observed_state_counts), unname(expected_state_counts)) ||
    sum(confirmed) != as.integer(config$confirmed_rows_total) ||
    sum(current_confirmed) != as.integer(config$current_confirmed_rows) ||
    any(source$confirmation_chain_count[confirmed] != as.integer(config$confirmation_chains_per_cell)) ||
    any(source$confirmation_chain_count[!confirmed] != 0L) ||
    any(!nzchar(source$confirmation_execution_commit[confirmed])) ||
    any(!nzchar(source$confirmation_closeout_commit[confirmed])) ||
    any(source$metric_estimator_contract[current_confirmed] != config$current_estimator_contract) ||
    any(source$confirmation_execution_commit[current_confirmed] != config$confirmation_execution_commit) ||
    any(source$confirmation_closeout_commit[current_confirmed] != config$closeout_implementation_commit) ||
    any(source$source_promotion_id[current_confirmed] != config$promotion_id)) {
  stop("Generated summary violates the cumulative confirmation estimator contract.",
       call. = FALSE)
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
    !grepl("Forecast check loss", table_text, fixed = TRUE) ||
    !grepl("pre-specified repeated-chain aggregate", table_text, fixed = TRUE)) {
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
    !grepl("A subsequent paired confirmation revisited", main_text, fixed = TRUE) ||
    !grepl("A forecast-first follow-up then revisited", main_text, fixed = TRUE) ||
    !grepl("A subsequent adaptive forecast-gap campaign", main_text, fixed = TRUE) ||
    !grepl("A further targeted confirmation retained", main_text, fixed = TRUE) ||
    grepl("A separate full-budget confirmation used one coherent", main_text, fixed = TRUE) ||
    !grepl("tables/qdesn_validation_tt500_final_tables.tex", supp_text, fixed = TRUE) ||
    !grepl("train-only preprocessing correction", supp_text, fixed = TRUE) ||
    !grepl("A later paired confirmation targeted", supp_text, fixed = TRUE) ||
    !grepl("Two later forecast-focused confirmations", supp_text, fixed = TRUE) ||
    !grepl("A final targeted confirmation used", supp_text, fixed = TRUE)) {
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
    !grepl(config$article_delta_sha256, manifest_text, fixed = TRUE) ||
    !grepl(config$rolling_rebaseline_state, manifest_text, fixed = TRUE) ||
    !grepl(config$qdesn_forecast_metric_contract, manifest_text, fixed = TRUE) ||
    !grepl(config$exal_method_id, manifest_text, fixed = TRUE) ||
    !grepl(config$current_estimator_contract, manifest_text, fixed = TRUE) ||
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
