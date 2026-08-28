#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE, digits = 17)

script_path <- normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]),
  winslash = "/", mustWork = TRUE
)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  at <- which(args == flag)
  if (!length(at) || at[[1L]] == length(args)) return(default)
  args[[at[[1L]] + 1L]]
}
config_path <- normalizePath(
  arg_value("--config", file.path(
    repo_root, "application", "config",
    "independent_validation_exdqlm_1p1p1_article_v12.yaml"
  )), winslash = "/", mustWork = TRUE
)
config <- yaml::read_yaml(config_path)
resolve_from_repo <- function(path) {
  path <- as.character(path)[1L]
  if (!grepl("^/", path)) path <- file.path(repo_root, path)
  path
}
validation_root <- normalizePath(
  resolve_from_repo(arg_value(
    "--validation-root",
    Sys.getenv("QDESN_VALIDATION_ROOT", unset = config$validation_root)
  )),
  winslash = "/", mustWork = TRUE
)
packet_root <- normalizePath(
  file.path(validation_root, config$packet_relative_path), winslash = "/", mustWork = TRUE
)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
packet_path <- function(name) file.path(packet_root, name)
article_path <- function(relative) file.path(repo_root, relative)
check_count <- 0L
check <- function(condition, label) {
  check_count <<- check_count + 1L
  if (!isTRUE(condition)) stop(sprintf("CHECK_FAILED: %s", label), call. = FALSE)
  invisible(TRUE)
}

validation_head <- system2(
  "git", c("-C", shQuote(validation_root), "rev-parse", "HEAD"), stdout = TRUE
)
check(identical(as.character(validation_head), as.character(config$validation_authority_commit)),
      "validation authority commit")
for (item in c(
  "handoff", "file_manifest", "point_candidate", "interval_candidate",
  "mcmc_diagnostics", "source_point_summary", "source_interval_summary",
  "point_winner_ledger", "interval_winner_ledger"
)) {
  path <- packet_path(config$packet[[item]])
  check(file.exists(path), paste(item, "exists"))
  check(identical(sha256(path), as.character(config$packet[[paste0(item, "_sha256")]])),
        paste(item, "hash"))
}

expected <- config$expected
models <- unlist(expected$models, use.names = FALSE)
families <- unlist(expected$families, use.names = FALSE)
taus <- as.numeric(unlist(expected$taus, use.names = FALSE))
inference_levels <- unlist(expected$inference, use.names = FALSE)
metric_roles <- unlist(expected$metric_roles, use.names = FALSE)

point_source <- read.csv(packet_path(config$packet$point_candidate), check.names = FALSE)
point <- read.csv(article_path(config$outputs$point_summary), check.names = FALSE)
point_compatibility <- read.csv(
  article_path(config$outputs$point_compatibility_summary), check.names = FALSE
)
point_expected <- point_source
point_expected$article_interface_id <- config$point_authority_id
check(isTRUE(all.equal(point, point_expected, check.attributes = FALSE, tolerance = 0)),
      "point output equals the complete candidate")
check(isTRUE(all.equal(point_compatibility, point_expected,
                       check.attributes = FALSE, tolerance = 0)),
      "compatibility output equals the complete candidate")
check(nrow(point) == as.integer(expected$point_rows), "point row count")
check(sum(point$model_variant == "exdqlm") == as.integer(expected$exdqlm_point_rows),
      "exdqlm point row count")
check(all(point$package_version[point$model_variant == "exdqlm"] ==
            as.character(config$package$version)), "exdqlm package version")
check(all(point$metric_estimator_contract[point$model_variant == "exdqlm"] ==
            config$estimator_separation$point_exdqlm), "point estimator")
check(all(point$package_version[point$model_variant != "exdqlm"] == "1.0.0"),
      "inherited package versions")

roles <- read.csv(packet_path(config$packet$interval_candidate), check.names = FALSE)
portable <- read.csv(article_path(config$outputs$interval_summary), check.names = FALSE)
check(nrow(roles) == as.integer(expected$interval_roles), "interval role count")
check(nrow(portable) == as.integer(expected$portable_interval_rows),
      "portable interval row count")
check(sum(roles$estimator_id == config$estimator_separation$interval_primary) ==
        as.integer(expected$interval_primary_estimator_roles), "primary interval estimator count")
check(sum(roles$estimator_id == config$estimator_separation$interval_inherited) ==
        as.integer(expected$interval_inherited_estimator_roles),
      "inherited interval estimator count")
check(sum(roles$model_variant == "exdqlm") ==
        as.integer(expected$exdqlm_interval_roles), "exdqlm interval role count")
check(all(roles$posterior_mean >= roles$cri_lower & roles$posterior_mean <= roles$cri_upper),
      "posterior means inside intervals")
check(!all(abs(roles$authoritative_value - roles$posterior_mean) < 1e-12),
      "point and interval estimators remain separate")

portable_key <- with(portable, paste(inference, model_variant, family, sprintf("%.2f", tau)))
role_columns <- list(
  fit = c("fit_qtrue_rmse", "fit_cri_lower", "fit_posterior_median", "fit_cri_upper",
          "fit_n_draws", "fit_n_chains", "fit_diagnostic_grade", "fit_replay_id"),
  forecast_mae = c(
    "forecast_qtrue_mae_H1000", "forecast_mae_cri_lower",
    "forecast_mae_posterior_median", "forecast_mae_cri_upper",
    "forecast_mae_n_draws", "forecast_mae_n_chains",
    "forecast_mae_diagnostic_grade", "forecast_mae_replay_id"),
  forecast_check = c(
    "forecast_check_loss_H1000", "forecast_check_cri_lower",
    "forecast_check_posterior_median", "forecast_check_cri_upper",
    "forecast_check_n_draws", "forecast_check_n_chains",
    "forecast_check_diagnostic_grade", "forecast_check_replay_id")
)
source_columns <- c(
  "posterior_mean", "cri_lower", "posterior_median", "cri_upper",
  "n_draws", "n_chains", "diagnostic_grade", "replay_id"
)
for (role in metric_roles) {
  block <- roles[roles$metric_role == role, , drop = FALSE]
  block_key <- with(block, paste(inference, model_variant, family, sprintf("%.2f", tau)))
  at <- match(portable_key, block_key)
  check(!anyNA(at), paste(role, "mapping complete"))
  for (j in seq_along(source_columns)) {
    observed <- portable[[role_columns[[role]][[j]]]]
    target <- block[[source_columns[[j]]]][at]
    condition <- if (is.numeric(target)) {
      isTRUE(all.equal(as.numeric(observed), as.numeric(target), tolerance = 0))
    } else identical(as.character(observed), as.character(target))
    check(condition, paste(role, source_columns[[j]], "mapping"))
  }
}

diagnostics <- read.csv(article_path(config$outputs$interval_diagnostics), check.names = FALSE)
check(nrow(diagnostics) == as.integer(expected$mcmc_diagnostic_rows),
      "diagnostic row count")
check(sum(diagnostics$diagnostic_grade == "PASS") ==
        as.integer(expected$mcmc_diagnostic_pass_rows), "diagnostic pass count")
check(sum(diagnostics$diagnostic_grade == "WARN") ==
        as.integer(expected$mcmc_diagnostic_warn_rows), "diagnostic warning count")
check(sum(roles$diagnostic_grade == "WARN") ==
        as.integer(expected$displayed_warning_metrics), "displayed warning count")
role_replays <- sort(unique(as.character(roles$replay_id[roles$inference == "mcmc"])))
diagnostic_replays <- sort(unique(as.character(diagnostics$replay_id)))
check(length(diagnostic_replays) == as.integer(expected$mcmc_diagnostic_replays),
      "diagnostic replay count")
check(identical(diagnostic_replays, role_replays), "diagnostic replay set")
diagnostic_metrics <- split(as.character(diagnostics$metric), diagnostics$replay_id)
check(all(vapply(diagnostic_metrics, function(x) {
  length(x) == 3L && setequal(x, c("fit_rmse", "forecast_mae", "forecast_check_loss"))
}, logical(1L))), "three diagnostic metrics per replay")
displayed_warning_keys <- sort(with(
  roles[roles$diagnostic_grade == "WARN", , drop = FALSE],
  paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role, sep = "|")
))
metric_warning_keys <- sort(with(
  diagnostics[diagnostics$diagnostic_grade == "WARN", , drop = FALSE],
  paste(replay_id, metric, sep = "|")
))
check(identical(displayed_warning_keys,
                sort(unlist(expected$displayed_warning_keys, use.names = FALSE))),
      "displayed caution identities")
check(identical(metric_warning_keys,
                sort(unlist(expected$metric_diagnostic_warning_keys, use.names = FALSE))),
      "metric diagnostic warning identities")

comparison <- read.csv(article_path(config$outputs$interval_comparison), check.names = FALSE)
winner_counts <- table(factor(comparison$winner_model_variant, levels = models))
target_counts <- c(
  as.integer(expected$mcmc_winner_dqlm), as.integer(expected$mcmc_winner_exdqlm),
  as.integer(expected$mcmc_winner_qdesn_al_rhs_ns),
  as.integer(expected$mcmc_winner_qdesn_exal_rhs_ns)
)
check(nrow(comparison) == as.integer(expected$mcmc_metric_cells), "comparison row count")
check(identical(as.integer(winner_counts), target_counts), "winner counts")
check(sum(comparison$winner_runner_intervals_overlap) ==
        as.integer(expected$mcmc_winner_interval_overlaps), "interval overlap count")

point_winners <- read.csv(packet_path(config$packet$point_winner_ledger), check.names = FALSE)
interval_winners <- read.csv(packet_path(config$packet$interval_winner_ledger), check.names = FALSE)
check(sum(point_winners$winner_changed) == as.integer(expected$point_winner_changes),
      "point winner changes")
check(sum(interval_winners$winner_changed) == as.integer(expected$interval_winner_changes),
      "interval winner changes")

point_tables <- c(
  config$outputs$point_normal, config$outputs$point_laplace,
  config$outputs$point_gausmix, config$outputs$point_mcmc_normal,
  config$outputs$point_mcmc_laplace, config$outputs$point_mcmc_gausmix
)
interval_tables <- unlist(lapply(c("mcmc", "vb"), function(inf) {
  sprintf("tables/qdesn_validation_500obs_v12_%s_metric_intervals_%s.tex", inf, families)
}), use.names = FALSE)
for (path in c(point_tables, interval_tables)) {
  full <- article_path(path)
  check(file.exists(full) && file.info(full)$size > 1000, paste(path, "substantive"))
  text <- paste(readLines(full, warn = FALSE), collapse = "\n")
  check(grepl("\\\\textbf\\{", text), paste(path, "boldface winners"))
  expected_bold <- if (grepl("final_mcmc_", path, fixed = TRUE) ||
                       grepl("_metric_intervals_", path, fixed = TRUE)) 9L else 18L
  bold_count <- lengths(regmatches(text, gregexpr("\\\\textbf\\{", text)))[[1L]]
  check(identical(as.integer(bold_count), expected_bold),
        paste(path, "complete boldface mapping"))
}

figure_paths <- unlist(lapply(c("mcmc", "vb"), function(inf) {
  sprintf(
    "figures/independent_simulation/qdesn_validation_500obs_v12_%s_%s_intervals.pdf",
    inf, c("fit_rmse", "forecast_mae", "forecast_check_loss")
  )
}), use.names = FALSE)
check(length(figure_paths) == 6L, "six interval figures declared")
for (path in figure_paths) {
  full <- article_path(path)
  check(file.exists(full) && file.info(full)$size > 10000, paste(path, "substantive"))
}

main_text <- paste(readLines(article_path("main.tex"), warn = FALSE), collapse = "\n")
for (inf in c("mcmc", "vb")) {
  wrapper_path <- article_path(sprintf(
    "tables/qdesn_validation_500obs_v12_%s_metric_interval_figures.tex", inf
  ))
  wrapper_text <- paste(readLines(wrapper_path, warn = FALSE), collapse = "\n")
  for (label_id in c("fit-rmse", "forecast-mae", "forecast-check-loss")) {
    label <- sprintf("fig:simulation-500obs-%s-%s-intervals", inf, label_id)
    check(grepl(paste0("\\\\label\\{", label, "\\}"), wrapper_text),
          paste(label, "wrapper label"))
  }
}
for (label in c(
  "fig:simulation-500obs-mcmc-fit-rmse-intervals",
  "fig:simulation-500obs-mcmc-forecast-check-loss-intervals"
)) {
  check(grepl(paste0("\\\\ref\\{", label, "\\}"), main_text),
        paste(label, "main reference"))
}

prose_text <- paste(readLines(article_path(config$outputs$interval_prose), warn = FALSE),
                    collapse = "\n")
for (phrase in c(
  "exdqlm 1.1.1", "forecast changes are not material",
  "conclusions remain stable", "single fixed path for VB",
  "posterior means of draw-wise criteria"
)) {
  check(grepl(phrase, prose_text, fixed = TRUE), paste("required prose:", phrase))
}

preserved_path <- article_path(config$preserved_asset$path)
check(identical(sha256(preserved_path), as.character(config$preserved_asset$sha256)),
      "aCRPS dependence-sensitivity asset preserved")
check(!file.exists(article_path(
  "tables/qdesn_validation_500obs_metric_interval_contract_clarification.tex"
)), "superseded dependence-sensitivity filename absent")

verify_manifest <- function(relative) {
  path <- article_path(relative)
  check(file.exists(path), paste(relative, "exists"))
  lines <- readLines(path, warn = FALSE)
  at <- match("artifacts:", lines)
  check(!is.na(at) && at < length(lines), paste(relative, "artifact section"))
  records <- lines[seq.int(at + 1L, length(lines))]
  records <- records[grepl("^  .+: [0-9a-f]{64}$", records)]
  check(length(records) > 0L, paste(relative, "artifact records"))
  for (record in records) {
    match_record <- regexec("^  (.+): ([0-9a-f]{64})$", record)
    parts <- regmatches(record, match_record)[[1L]]
    artifact <- article_path(parts[[2L]])
    check(file.exists(artifact), paste(parts[[2L]], "manifest target"))
    check(identical(sha256(artifact), parts[[3L]]), paste(parts[[2L]], "manifest hash"))
  }
}
for (manifest in c(
  config$outputs$point_table_manifest, config$outputs$point_mcmc_manifest,
  config$outputs$point_figure_manifest, config$outputs$interval_manifest,
  config$outputs$projection_manifest
)) verify_manifest(manifest)

check(length(grep(
  "qdesn_validation_500obs_metric_dependence_sensitivity.tex",
  readLines(article_path("overleaf/article_files.txt"), warn = FALSE), fixed = TRUE
)) == 1L, "Overleaf manifest retains aCRPS sensitivity asset")

cat("INDEPENDENT_EXDQLM_1P1P1_ARTICLE_V12_CHECK=PASS\n")
cat(sprintf("CHECKS=%d POINT_ROWS=%d INTERVAL_ROLES=%d FIGURES=%d\n",
            check_count, nrow(point), nrow(roles), length(figure_paths)))
