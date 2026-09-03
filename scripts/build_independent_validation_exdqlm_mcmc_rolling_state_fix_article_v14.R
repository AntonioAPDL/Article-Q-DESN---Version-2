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
    "independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.yaml"
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
if (!startsWith(packet_root, paste0(validation_root, "/"))) {
  stop("The evidence path escapes the validation repository.", call. = FALSE)
}
rolling_packet_root <- normalizePath(
  file.path(validation_root, config$rolling_packet_relative_path),
  winslash = "/", mustWork = TRUE
)
if (!startsWith(rolling_packet_root, paste0(validation_root, "/"))) {
  stop("The rolling-state evidence path escapes the validation repository.", call. = FALSE)
}
validation_head <- system2(
  "git", c("-C", shQuote(validation_root), "rev-parse", "HEAD"), stdout = TRUE
)
if (!identical(as.character(validation_head), as.character(config$validation_authority_commit))) {
  stop("The shared-validation authority is not at the declared commit.", call. = FALSE)
}

sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])
verify_hash <- function(path, expected, label) {
  if (!file.exists(path) || !identical(sha256(path), as.character(expected))) {
    stop(sprintf("%s SHA-256 mismatch.", label), call. = FALSE)
  }
  invisible(path)
}
packet_path <- function(name) {
  path <- normalizePath(file.path(packet_root, name), winslash = "/", mustWork = TRUE)
  if (!startsWith(path, paste0(packet_root, "/"))) {
    stop("An evidence file escapes the frozen packet.", call. = FALSE)
  }
  path
}
rolling_packet_path <- function(name) {
  path <- normalizePath(file.path(rolling_packet_root, name), winslash = "/", mustWork = TRUE)
  if (!startsWith(path, paste0(rolling_packet_root, "/"))) {
    stop("A rolling-state evidence file escapes the frozen packet.", call. = FALSE)
  }
  path
}
validation_path <- function(relative) {
  if (length(relative) != 1L || is.na(relative) || !nzchar(relative) ||
      grepl("^/", relative) || grepl("(^|/)\\.\\.(/|$)", relative)) {
    stop("A validation input is not portable.", call. = FALSE)
  }
  path <- normalizePath(file.path(validation_root, relative), winslash = "/", mustWork = TRUE)
  if (!startsWith(path, paste0(validation_root, "/"))) {
    stop("A validation input escapes the shared authority.", call. = FALSE)
  }
  path
}
article_path <- function(relative) {
  if (length(relative) != 1L || is.na(relative) || !nzchar(relative) ||
      grepl("^/", relative) || grepl("(^|/)\\.\\.(/|$)", relative)) {
    stop("An article output is not portable.", call. = FALSE)
  }
  path <- file.path(repo_root, relative)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}
relative_article <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  prefix <- paste0(repo_root, "/")
  if (!startsWith(path, prefix)) stop("An output escapes the article repository.", call. = FALSE)
  substring(path, nchar(prefix) + 1L)
}
write_csv <- function(x, path) write.csv(x, path, row.names = FALSE, na = "")

for (item in c(
  "handoff", "file_manifest", "point_candidate", "interval_candidate",
  "mcmc_diagnostics", "source_point_summary", "source_interval_summary",
  "point_winner_ledger", "interval_winner_ledger"
)) {
  verify_hash(
    packet_path(config$packet[[item]]), config$packet[[paste0(item, "_sha256")]],
    gsub("_", " ", item)
  )
}
for (item in c(
  "handoff", "artifact_manifest", "replacement_contract", "point_candidate",
  "interval_candidate", "mcmc_diagnostics"
)) {
  verify_hash(
    rolling_packet_path(config$rolling_packet[[item]]),
    config$rolling_packet[[paste0(item, "_sha256")]],
    paste("rolling-state", gsub("_", " ", item))
  )
}
verifier <- file.path(
  validation_root, "validation", "fitforecast_v2", "scripts",
  "verify_independent_exdqlm_mcmc_rolling_state_fix_v1_promotion.R"
)
verifier_output <- local({
  original_directory <- getwd()
  on.exit(setwd(original_directory), add = TRUE)
  setwd(validation_root)
  system2(
    "Rscript", c(shQuote(verifier), paste0("--repo-root=", shQuote(validation_root))),
    stdout = TRUE, stderr = TRUE
  )
})
if (!identical(attr(verifier_output, "status"), NULL) ||
    !any(grepl("PROMOTION_PACKET_VERIFIED", verifier_output, fixed = TRUE))) {
  stop(paste(c("The frozen packet verifier failed:", verifier_output), collapse = "\n"),
       call. = FALSE)
}

handoff <- jsonlite::read_json(rolling_packet_path(config$rolling_packet$handoff), simplifyVector = TRUE)
git_object_file <- function(commit, relative, expected_hash, label) {
  path <- tempfile(pattern = "article-v14-baseline-")
  error_path <- tempfile(pattern = "article-v14-baseline-error-")
  on.exit(unlink(c(path, error_path)), add = TRUE)
  status <- system2(
    "git", c("-C", shQuote(repo_root), "show", paste0(commit, ":", relative)),
    stdout = path, stderr = error_path
  )
  if (!identical(status, 0L)) stop(sprintf("Could not read %s from Git.", label), call. = FALSE)
  verify_hash(path, expected_hash, label)
  read.csv(path, check.names = FALSE)
}
baseline_interval_summary <- git_object_file(
  config$baseline$article_commit, config$baseline$interval_summary,
  config$baseline$interval_summary_sha256, "baseline interval summary"
)
baseline_mcmc_diagnostics <- git_object_file(
  config$baseline$article_commit, config$baseline$mcmc_diagnostics,
  config$baseline$mcmc_diagnostics_sha256, "baseline MCMC diagnostics"
)
required_handoff <- c(
  status = "READY_FOR_INTEGRATION",
  package_version = as.character(config$package$version),
  scientific_decision = "READY_FOR_INTEGRATION_REPLACE_COMPLETE_EXDQLM_MCMC_BLOCK"
)
for (field in names(required_handoff)) {
  if (!identical(as.character(handoff[[field]]), required_handoff[[field]])) {
    stop(sprintf("Handoff field %s is inconsistent.", field), call. = FALSE)
  }
}

expected <- config$expected
models <- unlist(expected$models, use.names = FALSE)
families <- unlist(expected$families, use.names = FALSE)
taus <- as.numeric(unlist(expected$taus, use.names = FALSE))
inference_levels <- unlist(expected$inference, use.names = FALSE)
metric_roles <- unlist(expected$metric_roles, use.names = FALSE)
point <- read.csv(packet_path(config$packet$point_candidate), check.names = FALSE)
roles <- read.csv(packet_path(config$packet$interval_candidate), check.names = FALSE)
baseline_point <- point
baseline_roles <- roles
rolling_point <- read.csv(
  rolling_packet_path(config$rolling_packet$point_candidate), check.names = FALSE
)
rolling_roles <- read.csv(
  rolling_packet_path(config$rolling_packet$interval_candidate), check.names = FALSE
)
rolling_point_key <- with(rolling_point, paste(inference, model_variant, family, sprintf("%.2f", tau)))
expected_rolling_point <- with(
  expand.grid(inference = "mcmc", model_variant = "exdqlm", family = families,
              tau = taus, stringsAsFactors = FALSE),
  paste(inference, model_variant, family, sprintf("%.2f", tau))
)
if (nrow(rolling_point) != as.integer(expected$rolling_point_rows) ||
    anyDuplicated(rolling_point_key) || !setequal(rolling_point_key, expected_rolling_point) ||
    any(!rolling_point$article_consumption_allowed)) {
  stop("The rolling-state point block is not the complete nine-cell MCMC exDQLM block.", call. = FALSE)
}
point_key_before <- with(point, paste(inference, model_variant, family, sprintf("%.2f", tau)))
point_match <- match(rolling_point_key, point_key_before)
point_metric_columns <- c("fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000")
for (column in intersect(names(rolling_point), names(point))) point[point_match, column] <- rolling_point[[column]]
point[point_match, point_metric_columns] <- rolling_point[point_metric_columns]
rolling_source_path <- paste0(
  config$rolling_packet_relative_path, "/", config$rolling_packet$point_candidate
)
for (prefix in c("fit", "forecast_mae", "forecast_check")) {
  point[point_match, paste0(prefix, "_source_candidate_id")] <-
    "independent_exdqlm_mcmc_rolling_state_fix_v1"
  point[point_match, paste0(prefix, "_source_run_tag")] <- rolling_point$source_run_id
  point[point_match, paste0(prefix, "_source_signoff_grade")] <- "PASS"
  point[point_match, paste0(prefix, "_source_status")] <- "COMPLETE"
  point[point_match, paste0(prefix, "_source_path")] <- rolling_source_path
  point[point_match, paste0(prefix, "_source_sha256")] <-
    as.character(config$rolling_packet$point_candidate_sha256)
}
point$source_registry_hash_value[point_match] <-
  as.character(config$rolling_packet$artifact_manifest_sha256)
point$validation_branch[point_match] <-
  "validation/independent-exdqlm-mcmc-rolling-state-fix-v1-1.0.0"
point$validation_commit[point_match] <- "280917362fe0d9c55a0d35853513b1d689bcfea0"
point$validation_closeout_commit[point_match] <- "280917362fe0d9c55a0d35853513b1d689bcfea0"
point$source_promotion_id[point_match] <- "independent_exdqlm_mcmc_rolling_state_fix_v1_20260829"
point$rolling_rebaseline_state[point_match] <- "ROLLING_STATE_POSTERIOR_PREDICTIVE_MOMENTS_V1"
point$promotion_validation_branch[point_match] <-
  "validation/independent-exdqlm-mcmc-rolling-state-fix-v1-1.0.0"
point$promotion_validation_commit[point_match] <- "280917362fe0d9c55a0d35853513b1d689bcfea0"
point$rolling_evidence_promotion_id[point_match] <-
  "independent_exdqlm_mcmc_rolling_state_fix_v1_20260829"
point$confirmation_execution_commit[point_match] <- "7ace6618601b7dd8d8c5fd3bd676000ba40f11e8"
point$confirmation_closeout_commit[point_match] <- "aff65ae9347a9c2197fb93a5c845ddafea4ca66d"
point$confirmation_state[point_match] <- "COMPLETE"
point$signoff_grade[point_match] <- "PASS"
point$status[point_match] <- "COMPLETE"
point$metric_source_mixed[point_match] <- FALSE
point$article_interface_id <- config$point_authority_id
untouched_point <- setdiff(seq_len(nrow(point)), point_match)
baseline_point_compare <- baseline_point
baseline_point_compare$article_interface_id <- config$point_authority_id
if (!isTRUE(all.equal(point[untouched_point, ], baseline_point_compare[untouched_point, ],
                      check.attributes = FALSE, tolerance = 0))) {
  stop("A non-target point row changed during the rolling-state replacement.", call. = FALSE)
}

rolling_role_key <- with(rolling_roles, paste(
  inference, model_variant, family, sprintf("%.2f", tau), metric_role
))
expected_rolling_roles <- with(
  expand.grid(inference = "mcmc", model_variant = "exdqlm", family = families,
              tau = taus, metric_role = metric_roles, stringsAsFactors = FALSE),
  paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role)
)
if (nrow(rolling_roles) != as.integer(expected$rolling_interval_roles) ||
    anyDuplicated(rolling_role_key) || !setequal(rolling_role_key, expected_rolling_roles)) {
  stop("The rolling-state interval block is not the complete 27-role MCMC exDQLM block.", call. = FALSE)
}
role_key_before <- with(roles, paste(
  inference, model_variant, family, sprintf("%.2f", tau), metric_role
))
role_match <- match(rolling_role_key, role_key_before)
for (column in intersect(names(rolling_roles), names(roles))) roles[role_match, column] <- rolling_roles[[column]]
rolling_replay_id <- paste0(
  "rolling_state_v1_", rolling_roles$family, "_", gsub("\\.", "p", sprintf("%.2f", rolling_roles$tau))
)
roles$replay_id[role_match] <- rolling_replay_id
new_diagnostics_raw <- read.csv(
  rolling_packet_path(config$rolling_packet$mcmc_diagnostics), check.names = FALSE
)
diag_key <- with(new_diagnostics_raw, paste(family, sprintf("%.2f", tau), metric))
role_diag_key <- with(rolling_roles, paste(
  family, sprintf("%.2f", tau),
  ifelse(metric_role == "fit", "fit_rmse",
         ifelse(metric_role == "forecast_check", "forecast_check_loss", "forecast_mae"))
))
roles$diagnostic_grade[role_match] <- new_diagnostics_raw$diagnostic_grade[match(role_diag_key, diag_key)]
untouched_roles <- setdiff(seq_len(nrow(roles)), role_match)
if (!isTRUE(all.equal(roles[untouched_roles, ], baseline_roles[untouched_roles, ],
                      check.attributes = FALSE, tolerance = 0))) {
  stop("A non-target interval role changed during the rolling-state replacement.", call. = FALSE)
}

point_key <- with(point, paste(inference, model_variant, family, sprintf("%.2f", tau)))
point_grid <- expand.grid(
  inference = inference_levels, model_variant = models, family = families, tau = taus,
  stringsAsFactors = FALSE
)
grid_key <- with(point_grid, paste(inference, model_variant, family, sprintf("%.2f", tau)))
if (nrow(point) != as.integer(expected$point_rows) || anyDuplicated(point_key) ||
    !setequal(point_key, grid_key) || any(!point$article_consumption_allowed) ||
    any(!is.finite(unlist(point[c(
      "fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000"
    )])))) {
  stop("The point candidate does not contain the declared 72-row comparison.", call. = FALSE)
}
is_exdqlm <- point$model_variant == "exdqlm"
is_rolling_exdqlm <- is_exdqlm & point$inference == "mcmc"
if (sum(is_exdqlm) != as.integer(expected$exdqlm_point_rows) ||
    any(point$package_version[is_exdqlm] != as.character(config$package$version)) ||
    any(point$metric_estimator_contract[is_rolling_exdqlm] !=
          as.character(config$estimator_separation$point_exdqlm)) ||
    any(point$package_version[!is_exdqlm] != "1.0.0")) {
  stop("Point-estimator or package-version separation failed.", call. = FALSE)
}

role_key <- with(roles, paste(
  inference, model_variant, family, sprintf("%.2f", tau), metric_role
))
role_grid <- expand.grid(
  inference = inference_levels, model_variant = models, family = families,
  tau = taus, metric_role = metric_roles, stringsAsFactors = FALSE
)
role_grid_key <- with(role_grid, paste(
  inference, model_variant, family, sprintf("%.2f", tau), metric_role
))
valid_estimators <- unlist(config$estimator_separation[c("interval_primary", "interval_inherited")])
if (nrow(roles) != as.integer(expected$interval_roles) || anyDuplicated(role_key) ||
    !setequal(role_key, role_grid_key) || any(!is.finite(unlist(roles[c(
      "posterior_mean", "cri_lower", "posterior_median", "cri_upper"
    )]))) || any(roles$cri_lower > roles$posterior_median) ||
    any(roles$posterior_median > roles$cri_upper) ||
    any(roles$posterior_mean < roles$cri_lower) ||
    any(roles$posterior_mean > roles$cri_upper) ||
    any(!roles$estimator_id %in% valid_estimators)) {
  stop("The interval candidate violates its declared comparison grid.", call. = FALSE)
}
role_exdqlm <- roles$model_variant == "exdqlm"
if (sum(role_exdqlm) != as.integer(expected$exdqlm_interval_roles) ||
    any(roles$estimator_id[role_exdqlm] != config$estimator_separation$interval_primary) ||
    sum(!role_exdqlm) != as.integer(expected$non_exdqlm_interval_roles) ||
    sum(roles$estimator_id == config$estimator_separation$interval_primary) !=
      as.integer(expected$interval_primary_estimator_roles) ||
    sum(roles$estimator_id == config$estimator_separation$interval_inherited) !=
      as.integer(expected$interval_inherited_estimator_roles)) {
  stop("Interval-estimator separation failed.", call. = FALSE)
}
if (all(abs(roles$authoritative_value - roles$posterior_mean) < 1e-12)) {
  stop("Point and posterior-mean estimators were inadvertently conflated.", call. = FALSE)
}
point_metric_names <- c("fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000")
point_winners <- unlist(lapply(families, function(family) {
  unlist(lapply(taus, function(tau) {
    cell <- point[point$inference == "mcmc" & point$family == family &
                    abs(point$tau - tau) < 1e-12, , drop = FALSE]
    vapply(point_metric_names, function(metric) {
      cell$model_variant[[which.min(cell[[metric]])]]
    }, character(1L))
  }), use.names = FALSE)
}), use.names = FALSE)
point_winner_counts <- table(factor(point_winners, levels = models))
expected_point_winner_counts <- as.integer(unlist(expected[c(
  "mcmc_point_winner_dqlm", "mcmc_point_winner_exdqlm",
  "mcmc_point_winner_qdesn_al_rhs_ns", "mcmc_point_winner_qdesn_exal_rhs_ns"
)]))
if (!identical(as.integer(point_winner_counts), expected_point_winner_counts)) {
  stop("The MCMC point-table winner counts are inconsistent.", call. = FALSE)
}
# Assemble the complete 162-row diagnostic record before writing any output.
new_diagnostics <- new_diagnostics_raw
new_diagnostics$replay_id <- paste0(
  "rolling_state_v1_", new_diagnostics$family, "_",
  gsub("\\.", "p", sprintf("%.2f", new_diagnostics$tau))
)
diagnostic_columns <- names(baseline_mcmc_diagnostics)
if (!all(diagnostic_columns %in% names(new_diagnostics))) {
  stop("The new diagnostics do not contain the published diagnostic fields.", call. = FALSE)
}
old_exdqlm_rows <- baseline_interval_summary$model_variant == "exdqlm" &
  baseline_interval_summary$inference == "mcmc"
old_exdqlm_replays <- unique(unlist(baseline_interval_summary[
  old_exdqlm_rows,
  c("fit_replay_id", "forecast_mae_replay_id", "forecast_check_replay_id")
], use.names = FALSE))
complete_diagnostics <- rbind(
  baseline_mcmc_diagnostics[
    !baseline_mcmc_diagnostics$replay_id %in% old_exdqlm_replays,
    diagnostic_columns, drop = FALSE
  ],
  new_diagnostics[diagnostic_columns]
)

# The v11.1 point update replaced one inherited Q--DESN replay without
# regenerating the portable full-surface diagnostic CSV. Recompute its three
# metric diagnostics from the hash-pinned retained draws, then replace the
# unused replay so that the diagnostic surface matches the displayed roles.
replay_cfg <- config$inherited_diagnostic_replay
diagnostic_code <- validation_path(replay_cfg$diagnostic_code)
verify_hash(diagnostic_code, replay_cfg$diagnostic_code_sha256,
            "inherited replay diagnostic code")
source(diagnostic_code, local = environment())
replay_draws <- do.call(rbind, lapply(seq_len(3L), function(chain_id) {
  field <- paste0("draw_", chain_id)
  path <- validation_path(replay_cfg[[field]])
  verify_hash(path, replay_cfg[[paste0(field, "_sha256")]],
              paste("inherited replay chain", chain_id))
  draws <- read.csv(path, check.names = FALSE)
  if (nrow(draws) != 1000L || any(!is.finite(unlist(draws[c(
    "fit_rmse", "forecast_mae", "forecast_check_loss"
  )])))) {
    stop("An inherited replay draw file is incomplete.", call. = FALSE)
  }
  draws$chain_id <- chain_id
  draws
}))
replay_diagnostics <- ffv2_metric_chain_diagnostics(replay_draws)
replay_diagnostics$diagnostic_error <- ""
replay_diagnostics$diagnostic_grade <- ifelse(
  is.finite(replay_diagnostics$split_rhat) & replay_diagnostics$split_rhat <= 1.05 &
    is.finite(replay_diagnostics$bulk_ess) & replay_diagnostics$bulk_ess >= 400 &
    is.finite(replay_diagnostics$tail_ess) & replay_diagnostics$tail_ess >= 200 &
    is.finite(replay_diagnostics$mcse_fraction_interval_width) &
      replay_diagnostics$mcse_fraction_interval_width <= 0.05 &
    is.finite(replay_diagnostics$endpoint_max_range_pooled_sd) &
      replay_diagnostics$endpoint_max_range_pooled_sd <= 0.50,
  "PASS", "WARN"
)
replay_diagnostics$replay_id <- as.character(replay_cfg$replay_id)
if (!all(diagnostic_columns %in% names(replay_diagnostics))) {
  stop("The recomputed replay diagnostics lack published fields.", call. = FALSE)
}
complete_diagnostics <- complete_diagnostics[
  complete_diagnostics$replay_id != as.character(replay_cfg$superseded_replay_id),
  , drop = FALSE
]
complete_diagnostics <- rbind(
  complete_diagnostics,
  replay_diagnostics[diagnostic_columns]
)
complete_diagnostics <- complete_diagnostics[order(
  complete_diagnostics$replay_id, complete_diagnostics$metric
), , drop = FALSE]
role_replays <- sort(unique(as.character(
  roles$replay_id[roles$inference == "mcmc"]
)))
diagnostic_replays <- sort(unique(as.character(complete_diagnostics$replay_id)))
diagnostic_metrics <- split(
  as.character(complete_diagnostics$metric), complete_diagnostics$replay_id
)
if (nrow(complete_diagnostics) != as.integer(expected$mcmc_diagnostic_rows) ||
    length(diagnostic_replays) != as.integer(expected$mcmc_diagnostic_replays) ||
    !identical(diagnostic_replays, role_replays) ||
    any(!vapply(diagnostic_metrics, function(x) {
      setequal(x, c("fit_rmse", "forecast_mae", "forecast_check_loss")) && length(x) == 3L
    }, logical(1L))) ||
    sum(complete_diagnostics$diagnostic_grade == "PASS") !=
      as.integer(expected$mcmc_diagnostic_pass_rows) ||
    sum(complete_diagnostics$diagnostic_grade == "WARN") !=
      as.integer(expected$mcmc_diagnostic_warn_rows)) {
  stop("The complete MCMC diagnostic record has unexpected counts.", call. = FALSE)
}

family_labels <- c(normal = "Gaussian", laplace = "Laplace", gausmix = "Gaussian mixture")
model_labels_tex <- c(
  dqlm = "DQLM", exdqlm = "exDQLM",
  qdesn_al_rhs_ns = "Q--DESN AL--RHS",
  qdesn_exal_rhs_ns = "Q--DESN exAL--RHS"
)
model_labels_plot <- gsub("--", "-", model_labels_tex, fixed = TRUE)
metric_labels <- c(
  fit_qtrue_rmse = "Fit RMSE",
  forecast_qtrue_mae_H1000 = "Forecast MAE",
  forecast_check_loss_H1000 = "Forecast check loss"
)
metric_role_labels <- c(
  fit = "Fit RMSE", forecast_mae = "Forecast MAE",
  forecast_check = "Forecast check loss"
)
metric_role_caption_labels <- c(
  fit = "fit RMSE", forecast_mae = "forecast MAE",
  forecast_check = "forecast check loss"
)
metric_role_files <- c(
  fit = "fit_rmse", forecast_mae = "forecast_mae",
  forecast_check = "forecast_check_loss"
)
metric_role_label_ids <- gsub("_", "-", metric_role_files, fixed = TRUE)
fmt <- function(value) {
  value <- as.numeric(value)
  if (!is.finite(value)) return("--")
  if (abs(value) >= 100) return(sprintf("%.1f", value))
  if (abs(value) >= 10) return(sprintf("%.2f", value))
  if (abs(value) >= 1) return(sprintf("%.3f", value))
  sprintf("%.4f", value)
}

# Point-estimate projection ---------------------------------------------------
outputs <- config$outputs
point_summary_path <- article_path(outputs$point_summary)
point_compatibility_path <- article_path(outputs$point_compatibility_summary)
write_csv(point, point_summary_path)
write_csv(point, point_compatibility_path)

point_row <- function(inf, family, tau, model) {
  x <- point[
    point$inference == inf & point$family == family &
      abs(point$tau - tau) < 1e-12 & point$model_variant == model,
    , drop = FALSE
  ]
  if (nrow(x) != 1L) stop("A point cell is not unique.", call. = FALSE)
  x
}
point_cell <- function(inf, family, tau, model, metric) {
  x <- point_row(inf, family, tau, model)
  value <- as.numeric(x[[metric]])
  candidates <- vapply(models, function(m) {
    as.numeric(point_row(inf, family, tau, m)[[metric]])
  }, numeric(1L))
  text <- fmt(value)
  if (abs(value - min(candidates)) < 1e-10) text <- paste0("\\textbf{", text, "}")
  text
}
point_model_label <- function(inf, family, model) {
  x <- point[point$inference == inf & point$family == family &
               point$model_variant == model, , drop = FALSE]
  label <- model_labels_tex[[model]]
  if (any(x$signoff_grade == "FAIL")) paste0(label, "$^{\\ddagger}$") else
    if (any(x$signoff_grade == "WARN")) paste0(label, "$^{\\dagger}$") else label
}
point_header <- c(
  "Model & \\multicolumn{3}{c}{$p=0.05$} & \\multicolumn{3}{c}{$p=0.25$} & \\multicolumn{3}{c}{$p=0.50$} \\\\",
  "\\cmidrule(lr){2-4} \\cmidrule(lr){5-7} \\cmidrule(lr){8-10}",
  paste(" &", paste(rep(unname(metric_labels), length(taus)), collapse = " & "), "\\\\")
)
point_rows <- function(inf, family) {
  vapply(models, function(model) {
    cells <- unlist(lapply(taus, function(tau) {
      vapply(names(metric_labels), function(metric) {
        point_cell(inf, family, tau, model, metric)
      }, character(1L))
    }), use.names = FALSE)
    paste0(point_model_label(inf, family, model), " & ", paste(cells, collapse = " & "), " \\\\")
  }, character(1L))
}
render_point_family <- function(family, mcmc_only = FALSE) {
  lines <- c(
    "\\begin{table}[!htbp]", "\\centering", "\\scriptsize",
    "\\setlength{\\tabcolsep}{3.4pt}", "\\resizebox{\\textwidth}{!}{%",
    "\\begin{tabular}{@{}lrrrrrrrrr@{}}", "\\toprule", point_header, "\\midrule"
  )
  if (mcmc_only) {
    lines <- c(lines, point_rows("mcmc", family))
  } else {
    lines <- c(
      lines, "\\multicolumn{10}{@{}l}{\\textit{VB}} \\\\", point_rows("vb", family),
      "\\addlinespace[2pt]", "\\midrule",
      "\\multicolumn{10}{@{}l}{\\textit{MCMC}} \\\\", point_rows("mcmc", family)
    )
  }
  caption <- if (mcmc_only) {
    sprintf(paste0(
      "MCMC single-quantile comparison for the %s simulation family. ",
      "Fit RMSE evaluates recovery of the true conditional quantile over the 500-observation ",
      "training sample. Forecast MAE and check loss average the rolling-origin evaluations ",
      "over the 1,000-observation test sample, using leads 1--30 and origin stride 30. ",
      "Lower values are better; boldface marks the lowest unrounded value by target and criterion."
    ), family_labels[[family]])
  } else {
    sprintf(paste0(
      "Single-quantile comparison for the %s simulation family. Fit RMSE evaluates recovery ",
      "of the true conditional quantile over the 500-observation training sample. Forecast ",
      "MAE and check loss average the rolling-origin evaluations over the 1,000-observation ",
      "test sample, using leads 1--30 and origin stride 30. Lower values are better; ",
      "boldface marks the lowest unrounded value within each inferential method, target, and criterion."
    ), family_labels[[family]])
  }
  label <- sprintf(
    "tab:simulation-500obs-%s%s", if (mcmc_only) "mcmc-" else "final-", family
  )
  c(lines, "\\bottomrule", "\\end{tabular}%", "}",
    paste0("\\caption{", caption, "}"), paste0("\\label{", label, "}"), "\\end{table}")
}

point_family_paths <- setNames(vapply(families, function(family) {
  article_path(outputs[[paste0("point_", family)]])
}, character(1L)), families)
point_mcmc_paths <- setNames(vapply(families, function(family) {
  article_path(outputs[[paste0("point_mcmc_", family)]])
}, character(1L)), families)
for (family in families) {
  writeLines(render_point_family(family), point_family_paths[[family]], useBytes = TRUE)
  writeLines(render_point_family(family, TRUE), point_mcmc_paths[[family]], useBytes = TRUE)
}

protocol_path <- article_path(outputs$point_protocol)
writeLines(c(
  "\\begin{table}[!htbp]", "\\centering", "\\small",
  "\\begin{tabular}{@{}ll@{}}", "\\toprule", "Component & Evaluation design \\\\",
  "\\midrule", "Training sample & 500 observations after warmup \\\\",
  "Held-out sample & The following 1,000 observations \\\\",
  "Forecast evaluation & Rolling origins, leads 1--30, origin stride 30 \\\\",
  "Target quantiles & $p=0.05,0.25,0.50$ \\\\",
  "Criteria & Fit RMSE, forecast MAE, forecast check loss \\\\",
  "\\bottomrule", "\\end{tabular}",
  "\\caption{Evaluation design for the independent single-quantile simulation comparison.}",
  "\\label{tab:simulation-500obs-protocol}", "\\end{table}"
), protocol_path, useBytes = TRUE)
point_family_wrapper_path <- article_path(outputs$point_family_wrapper)
writeLines(c(
  "\\input{tables/qdesn_validation_tt500_final_protocol.tex}",
  "\\input{tables/qdesn_validation_tt500_final_normal.tex}",
  "\\input{tables/qdesn_validation_tt500_final_laplace.tex}",
  "\\input{tables/qdesn_validation_tt500_final_gausmix.tex}"
), point_family_wrapper_path, useBytes = TRUE)
point_mcmc_wrapper_path <- article_path(outputs$point_mcmc_wrapper)
writeLines(sprintf(
  "\\input{tables/qdesn_validation_tt500_final_mcmc_%s.tex}", families
), point_mcmc_wrapper_path, useBytes = TRUE)

combined_path <- article_path(outputs$point_combined)
combined <- c(
  "\\begingroup", "\\scriptsize", "\\setlength{\\tabcolsep}{2.0pt}",
  "\\begin{longtable}{@{}lrrrrrrrrr@{}}",
  paste0(
    "\\caption{Consolidated independent single-quantile fit-and-forecast comparison. ",
    "Lower values are better; boldface marks the lowest value within each simulation family, ",
    "inferential method, target, and criterion.}",
    "\\label{tab:simulation-fitforecast-results}\\\\"
  ), "\\toprule", point_header, "\\midrule", "\\endfirsthead",
  "\\caption[]{Consolidated independent single-quantile comparison (continued).}\\\\",
  "\\toprule", point_header, "\\midrule", "\\endhead", "\\bottomrule",
  "\\endlastfoot"
)
for (family in families) {
  combined <- c(combined, sprintf(
    "\\multicolumn{10}{@{}l}{\\textbf{%s innovations}} \\\\", family_labels[[family]]
  ))
  for (inf in inference_levels) {
    combined <- c(combined, sprintf(
      "\\multicolumn{10}{@{}l}{\\textit{%s}} \\\\", toupper(inf)
    ), point_rows(inf, family), "\\addlinespace[2pt]")
  }
}
writeLines(c(combined, "\\end{longtable}", "\\endgroup"), combined_path, useBytes = TRUE)

metric_specs <- list(
  fit_qtrue_rmse = list(label = "Fit RMSE", signoff = "fit_source_signoff_grade",
                        candidate = "fit_source_candidate_id", run = "fit_source_run_tag",
                        path = "fit_source_path", sha = "fit_source_sha256"),
  forecast_qtrue_mae_H1000 = list(
    label = "Forecast MAE", signoff = "forecast_mae_source_signoff_grade",
    candidate = "forecast_mae_source_candidate_id", run = "forecast_mae_source_run_tag",
    path = "forecast_mae_source_path", sha = "forecast_mae_source_sha256"),
  forecast_check_loss_H1000 = list(
    label = "Forecast check loss", signoff = "forecast_check_source_signoff_grade",
    candidate = "forecast_check_source_candidate_id", run = "forecast_check_source_run_tag",
    path = "forecast_check_source_path", sha = "forecast_check_source_sha256")
)
portable_source <- function(path) {
  path <- as.character(path)
  marker <- "validation/fitforecast_v2/"
  at <- regexpr(marker, path, fixed = TRUE)
  if (at[[1L]] < 1L) return(path)
  substring(path, at[[1L]])
}
point_mcmc <- point[point$inference == "mcmc", , drop = FALSE]
figure_rows <- list()
for (i in seq_len(nrow(point_mcmc))) {
  for (metric in names(metric_specs)) {
    spec <- metric_specs[[metric]]
    block <- point_mcmc[
      point_mcmc$family == point_mcmc$family[[i]] &
        abs(point_mcmc$tau - point_mcmc$tau[[i]]) < 1e-12,
      , drop = FALSE
    ]
    value <- as.numeric(point_mcmc[[metric]][[i]])
    best <- min(as.numeric(block[[metric]]))
    figure_rows[[length(figure_rows) + 1L]] <- data.frame(
      model_variant = point_mcmc$model_variant[[i]],
      model_label = model_labels_plot[[point_mcmc$model_variant[[i]]]],
      family = point_mcmc$family[[i]],
      family_label = family_labels[[point_mcmc$family[[i]]]],
      tau = point_mcmc$tau[[i]], metric = metric, metric_label = spec$label,
      value = value, best_value = best, ratio_to_best = value / best,
      is_winner = abs(value - best) < 1e-10,
      source_signoff_grade = as.character(point_mcmc[[spec$signoff]][[i]]),
      source_candidate_id = as.character(point_mcmc[[spec$candidate]][[i]]),
      source_run_tag = as.character(point_mcmc[[spec$run]][[i]]),
      source_path_relative = portable_source(point_mcmc[[spec$path]][[i]]),
      source_sha256 = as.character(point_mcmc[[spec$sha]][[i]]),
      source_promotion_id = point_mcmc$source_promotion_id[[i]],
      source_registry_hash_value = point_mcmc$source_registry_hash_value[[i]],
      stringsAsFactors = FALSE
    )
  }
}
figure_data <- do.call(rbind, figure_rows)
point_figure_data_path <- article_path(outputs$point_figure_data)
write_csv(figure_data, point_figure_data_path)

normalize_pdf_creation_date <- function(path) {
  bytes <- readBin(path, what = "raw", n = file.info(path)$size)
  marker <- charToRaw("/CreationDate (D:")
  candidates <- which(bytes == marker[[1L]])
  hits <- candidates[vapply(candidates, function(at) {
    end <- at + length(marker) - 1L
    end <= length(bytes) && identical(bytes[at:end], marker)
  }, logical(1L))]
  if (length(hits) != 1L) stop("A generated PDF has an unexpected creation date.", call. = FALSE)
  closing <- which(seq_along(bytes) > hits[[1L]] & bytes == charToRaw(")")[[1L]])
  if (!length(closing)) stop("A generated PDF creation date is unterminated.", call. = FALSE)
  close_at <- closing[[1L]]
  old <- rawToChar(bytes[hits[[1L]]:close_at])
  replacement <- "/CreationDate (D:20000101000000+00'00)"
  if (nchar(old, type = "bytes") != nchar(replacement, type = "bytes")) {
    stop("A generated PDF creation date has an unexpected width.", call. = FALSE)
  }
  bytes[hits[[1L]]:close_at] <- charToRaw(replacement)
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
  invisible(path)
}

if (!requireNamespace("ggplot2", quietly = TRUE) ||
    !requireNamespace("scales", quietly = TRUE)) {
  stop("ggplot2 and scales are required to generate the article figures.", call. = FALSE)
}
figure_data$model_label <- factor(
  figure_data$model_label, levels = rev(unname(model_labels_plot[models]))
)
figure_data$family_label <- factor(
  figure_data$family_label, levels = unname(family_labels[families])
)
figure_data$metric_label <- factor(
  figure_data$metric_label, levels = unname(metric_labels)
)
figure_data$tau_label <- factor(
  sprintf("p = %.2f", figure_data$tau), levels = sprintf("p = %.2f", taus)
)
marker <- ifelse(figure_data$source_signoff_grade == "FAIL", " x",
                 ifelse(figure_data$source_signoff_grade == "WARN", " +", ""))
figure_data$cell_label <- paste0(vapply(figure_data$value, fmt, character(1L)), marker)
fill_max <- max(figure_data$ratio_to_best)
legend_breaks <- c(1, 2, 4, 8, 16)
legend_breaks <- legend_breaks[legend_breaks <= fill_max]
point_plot <- ggplot2::ggplot(
  figure_data, ggplot2::aes(x = tau_label, y = model_label, fill = ratio_to_best)
) +
  ggplot2::geom_tile(ggplot2::aes(colour = is_winner), linewidth = 0.55) +
  ggplot2::geom_text(ggplot2::aes(label = cell_label), size = 2.55) +
  ggplot2::facet_grid(metric_label ~ family_label, scales = "free") +
  ggplot2::scale_colour_manual(values = c(`TRUE` = "black", `FALSE` = "white"),
                               guide = "none") +
  ggplot2::scale_fill_gradientn(
    colours = c("#f7fbff", "#fee8c8", "#fdbb84", "#e34a33"),
    trans = "log10", limits = c(1, fill_max), oob = scales::squish,
    breaks = legend_breaks, labels = paste0(legend_breaks, "x"), name = "Relative to best"
  ) +
  ggplot2::labs(x = NULL, y = NULL) + ggplot2::theme_bw(base_size = 9) +
  ggplot2::theme(
    panel.grid = ggplot2::element_blank(),
    strip.background = ggplot2::element_rect(fill = "#eeeeee", colour = "#777777"),
    legend.position = "bottom", plot.margin = ggplot2::margin(6, 6, 6, 6)
  )
point_figure_path <- article_path(outputs$point_figure_pdf)
ggplot2::ggsave(point_figure_path, point_plot, width = 11.2, height = 8,
                units = "in", device = grDevices::cairo_pdf)
normalize_pdf_creation_date(point_figure_path)

# Posterior-interval projection ----------------------------------------------
role_base_columns <- c("inference", "model_variant", "model_label", "family", "tau")
portable <- unique(roles[role_base_columns])
portable_key <- with(portable, paste(inference, model_variant, family, sprintf("%.2f", tau)))
role_contract <- list(
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
for (role in metric_roles) {
  block <- roles[roles$metric_role == role, , drop = FALSE]
  block_key <- with(block, paste(inference, model_variant, family, sprintf("%.2f", tau)))
  at <- match(portable_key, block_key)
  if (anyNA(at)) stop("An interval role is missing from the portable summary.", call. = FALSE)
  names_out <- role_contract[[role]]
  source_columns <- c(
    "posterior_mean", "cri_lower", "posterior_median", "cri_upper",
    "n_draws", "n_chains", "diagnostic_grade", "replay_id"
  )
  for (j in seq_along(source_columns)) portable[[names_out[[j]]]] <- block[[source_columns[[j]]]][at]
}
portable <- portable[order(
  match(portable$inference, inference_levels), match(portable$family, families),
  portable$tau, match(portable$model_variant, models)
), , drop = FALSE]
if (nrow(portable) != as.integer(expected$portable_interval_rows)) {
  stop("The portable interval summary does not contain 72 rows.", call. = FALSE)
}
interval_summary_path <- article_path(outputs$interval_summary)
write_csv(portable, interval_summary_path)

interval_cell <- function(row, role, best) {
  center <- as.numeric(row$posterior_mean)
  text <- fmt(center)
  if (isTRUE(best)) text <- paste0("\\textbf{", text, "}")
  if (identical(as.character(row$diagnostic_grade), "WARN")) {
    text <- paste0(text, "\\textsuperscript{\\(\\dagger\\)}")
  }
  paste0("\\shortstack{", text, "\\\\{\\scriptsize [", fmt(row$cri_lower),
         ", ", fmt(row$cri_upper), "]}}")
}
render_interval_family <- function(inf, family) {
  x <- roles[roles$inference == inf & roles$family == family, , drop = FALSE]
  lines <- c(
    "\\begin{table}[!ht]", "\\centering", "\\scriptsize", "\\setstretch{1}",
    "\\setlength{\\tabcolsep}{4pt}", "\\begin{tabular}{@{}clccc@{}}",
    "\\toprule", "Target & Model & Fit RMSE & Forecast MAE & Forecast check loss \\\\",
    "\\midrule"
  )
  for (tau in taus) {
    block <- x[abs(x$tau - tau) < 1e-12, , drop = FALSE]
    for (i in seq_along(models)) {
      model <- models[[i]]
      cells <- vapply(metric_roles, function(role) {
        rb <- block[block$metric_role == role, , drop = FALSE]
        rb <- rb[match(models, rb$model_variant), , drop = FALSE]
        interval_cell(rb[i, , drop = FALSE], role, i == which.min(rb$posterior_mean))
      }, character(1L))
      target <- if (i == 1L) sprintf("$p=%.2f$", tau) else ""
      lines <- c(lines, paste0(
        paste(c(target, model_labels_tex[[model]], cells), collapse = " & "), " \\\\"
      ))
    }
    if (tau != max(taus)) lines <- c(lines, "\\addlinespace[2pt]")
  }
  qualifier <- if (inf == "vb") "Approximate posterior" else "Posterior"
  interval_text <- if (inf == "vb") {
    "variational posterior means with equal-tailed approximate 95\\% intervals"
  } else {
    "posterior means with equal-tailed 95\\% credible intervals"
  }
  warning_text <- if (inf == "mcmc") {
    " A dagger marks a diagnostic caution recorded for the source analysis."
  } else ""
  caption <- sprintf(paste0(
    "%s metric intervals for the %s single-quantile simulation family. Entries are %s; ",
      "lower is better, and boldface marks the lowest unrounded posterior mean by target and criterion.%s"
  ), qualifier, family_labels[[family]], interval_text, warning_text)
  c(lines, "\\bottomrule", "\\end{tabular}", paste0("\\caption{", caption, "}"),
    sprintf("\\label{tab:simulation-500obs-%s-intervals-%s}", inf, family),
    "\\end{table}")
}

interval_table_paths <- character(0)
interval_table_wrapper_paths <- character(0)
for (inf in c("mcmc", "vb")) {
  paths <- character(0)
  for (family in families) {
    path <- article_path(sprintf(
      "tables/qdesn_validation_500obs_v14_%s_metric_intervals_%s.tex", inf, family
    ))
    writeLines(render_interval_family(inf, family), path, useBytes = TRUE)
    paths <- c(paths, path)
  }
  wrapper <- article_path(sprintf(
    "tables/qdesn_validation_500obs_v14_%s_metric_interval_tables.tex", inf
  ))
  wrapper_lines <- unlist(lapply(paths, function(path) c(
    "\\clearpage", sprintf("\\input{tables/%s}", basename(path))
  )), use.names = FALSE)
  writeLines(c(wrapper_lines, "\\clearpage"), wrapper, useBytes = TRUE)
  interval_table_paths <- c(interval_table_paths, paths)
  interval_table_wrapper_paths <- c(interval_table_wrapper_paths, wrapper)
}

roles$model_label_plot <- factor(
  unname(model_labels_plot[roles$model_variant]), levels = rev(unname(model_labels_plot[models]))
)
roles$panel_label_plot <- factor(
  paste(unname(family_labels[roles$family]), sprintf("p = %.2f", roles$tau), sep = "\n"),
  levels = unlist(lapply(unname(family_labels[families]), function(family) {
    paste(family, sprintf("p = %.2f", taus), sep = "\n")
  }), use.names = FALSE)
)
interval_plot <- function(inf, role) {
  block <- roles[roles$inference == inf & roles$metric_role == role, , drop = FALSE]
  ggplot2::ggplot(
    block, ggplot2::aes(
      x = posterior_mean, y = model_label_plot, xmin = cri_lower, xmax = cri_upper,
      colour = model_variant
    )
  ) +
    ggplot2::geom_errorbar(orientation = "y", width = 0.18, linewidth = 0.72) +
    ggplot2::geom_point(shape = 4, size = 2.8, stroke = 1.05) +
    ggplot2::facet_wrap(~panel_label_plot, ncol = 3L, scales = "free_x") +
    ggplot2::scale_colour_manual(
      values = c(dqlm = "#0072B2", exdqlm = "#56B4E9",
                 qdesn_al_rhs_ns = "#D55E00", qdesn_exal_rhs_ns = "#009E73"),
      breaks = models, labels = unname(model_labels_plot[models]), drop = FALSE
    ) +
    ggplot2::scale_x_continuous(
      expand = ggplot2::expansion(mult = c(0.04, 0.06)),
      breaks = scales::breaks_pretty(n = 4L),
      # Use an explicit formatter because the script retains full numerical
      # precision for evidence checks; inheriting that global setting would
      # expose binary floating-point tails on the plotted axes.
      labels = function(x) sprintf("%.2f", x),
      guide = ggplot2::guide_axis(check.overlap = TRUE)
    ) +
    ggplot2::labs(
      title = sprintf("%s: %s", if (inf == "mcmc") "MCMC" else "Variational Bayes",
                      metric_role_labels[[role]]),
      subtitle = if (inf == "mcmc") {
        "Posterior mean (x) and equal-tailed 95% credible interval"
      } else {
        "Variational posterior mean (x) and equal-tailed approximate 95% interval"
      },
      x = metric_role_labels[[role]], y = NULL, colour = NULL
    ) +
    ggplot2::theme_minimal(base_size = 9.5, base_family = "sans") +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 11.5),
      plot.subtitle = ggplot2::element_text(size = 9, colour = "#333333"),
      panel.grid.major.y = ggplot2::element_blank(), panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(colour = "#E3E3E3", linewidth = 0.3),
      strip.text = ggplot2::element_text(face = "bold", size = 8.6, lineheight = 0.95),
      strip.background = ggplot2::element_rect(
        fill = "#F3F3F3", colour = "#D0D0D0", linewidth = 0.35
      ),
      axis.text.x = ggplot2::element_text(size = 7.4),
      axis.text.y = ggplot2::element_text(size = 7.8, colour = "#222222"),
      panel.spacing = grid::unit(1.15, "lines"), legend.position = "bottom",
      plot.margin = ggplot2::margin(7, 7, 5, 7)
    )
}
interval_figure_paths <- character(0)
interval_figure_wrapper_paths <- character(0)
for (inf in c("mcmc", "vb")) {
  wrapper_lines <- character(0)
  for (role in metric_roles) {
    path <- article_path(sprintf(
      "figures/independent_simulation/qdesn_validation_500obs_v14_%s_%s_intervals.pdf",
      inf, metric_role_files[[role]]
    ))
    ggplot2::ggsave(path, interval_plot(inf, role), width = 7.2, height = 6.6,
                    units = "in", device = grDevices::cairo_pdf, bg = "white")
    normalize_pdf_creation_date(path)
    interval_figure_paths <- c(interval_figure_paths, path)
    interval_text <- if (inf == "mcmc") {
      "equal-tailed 95\\% posterior intervals"
    } else {
      "equal-tailed approximate 95\\% variational posterior intervals"
    }
    caption <- paste0(
      if (inf == "mcmc") "MCMC" else "Variational Bayes",
      " posterior uncertainty for ", metric_role_caption_labels[[role]],
      " in the single-quantile simulation study. Horizontal segments show ", interval_text,
      "; crosses mark posterior means. Each panel uses its own horizontal scale, and lower ",
      "values are better. Intervals condition on the simulated data, evaluation design, ",
      "and model specification selected for each setting and criterion."
    )
    wrapper_lines <- c(
      wrapper_lines, "\\begin{figure}[!htbp]", "\\centering",
      sprintf("\\includegraphics[width=0.98\\textwidth]{%s}", relative_article(path)),
      paste0("\\caption{", caption, "}"),
      sprintf("\\label{fig:simulation-500obs-%s-%s-intervals}",
              inf, metric_role_label_ids[[role]]), "\\end{figure}", ""
    )
  }
  wrapper <- article_path(sprintf(
    "tables/qdesn_validation_500obs_v14_%s_metric_interval_figures.tex", inf
  ))
  writeLines(head(wrapper_lines, -1L), wrapper, useBytes = TRUE)
  interval_figure_wrapper_paths <- c(interval_figure_wrapper_paths, wrapper)
}

old_diagnostics_path <- article_path(outputs$interval_diagnostics)
write_csv(complete_diagnostics, old_diagnostics_path)

metric_contract <- data.frame(
  metric = c("fit_rmse", "forecast_mae", "forecast_check_loss"),
  mean_column = c("fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000"),
  lower_column = c("fit_cri_lower", "forecast_mae_cri_lower", "forecast_check_cri_lower"),
  upper_column = c("fit_cri_upper", "forecast_mae_cri_upper", "forecast_check_cri_upper"),
  stringsAsFactors = FALSE
)
comparison_rows <- list()
mcmc_portable <- portable[portable$inference == "mcmc", , drop = FALSE]
for (family in families) for (tau in taus) for (j in seq_len(nrow(metric_contract))) {
  spec <- metric_contract[j, , drop = FALSE]
  cell <- mcmc_portable[
    mcmc_portable$family == family & abs(mcmc_portable$tau - tau) < 1e-12,
    , drop = FALSE
  ]
  cell <- cell[match(models, cell$model_variant), , drop = FALSE]
  means <- as.numeric(cell[[spec$mean_column]])
  ord <- order(means, seq_along(models))
  winner <- cell[ord[[1L]], , drop = FALSE]
  runner <- cell[ord[[2L]], , drop = FALSE]
  winner_lower <- as.numeric(winner[[spec$lower_column]])
  winner_upper <- as.numeric(winner[[spec$upper_column]])
  runner_lower <- as.numeric(runner[[spec$lower_column]])
  runner_upper <- as.numeric(runner[[spec$upper_column]])
  comparison_rows[[length(comparison_rows) + 1L]] <- data.frame(
    family = family, tau = tau, metric = spec$metric,
    winner_model_variant = winner$model_variant,
    winner_model_label = winner$model_label,
    winner_posterior_mean = means[ord[[1L]]],
    winner_cri_lower = winner_lower, winner_cri_upper = winner_upper,
    runner_up_model_variant = runner$model_variant,
    runner_up_model_label = runner$model_label,
    runner_up_posterior_mean = means[ord[[2L]]],
    runner_up_cri_lower = runner_lower, runner_up_cri_upper = runner_upper,
    posterior_mean_gap = means[ord[[2L]]] - means[ord[[1L]]],
    winner_runner_intervals_overlap =
      max(winner_lower, runner_lower) <= min(winner_upper, runner_upper),
    stringsAsFactors = FALSE
  )
}
comparison <- do.call(rbind, comparison_rows)
winner_counts <- table(factor(comparison$winner_model_variant, levels = models))
expected_counts <- c(
  as.integer(expected$mcmc_winner_dqlm), as.integer(expected$mcmc_winner_exdqlm),
  as.integer(expected$mcmc_winner_qdesn_al_rhs_ns),
  as.integer(expected$mcmc_winner_qdesn_exal_rhs_ns)
)
if (nrow(comparison) != as.integer(expected$mcmc_metric_cells) ||
    !identical(as.integer(winner_counts), expected_counts) ||
    sum(comparison$winner_runner_intervals_overlap) !=
      as.integer(expected$mcmc_winner_interval_overlaps)) {
  stop("The interval winner comparison is inconsistent.", call. = FALSE)
}
interval_comparison_path <- article_path(outputs$interval_comparison)
write_csv(comparison, interval_comparison_path)

interval_results_path <- article_path(outputs$interval_results)
writeLines(c(
  sprintf(paste0(
    "Across the %d family--quantile--criterion comparisons in the MCMC panels, ",
    "Q--DESN exAL--RHS has the lowest posterior mean in %d comparisons and ",
    "Q--DESN AL--RHS in %d; DQLM has the lowest mean in %d and exDQLM in %d. ",
    "The two Q--DESN variants account for %d of the %d lowest posterior means."
  ), nrow(comparison), expected_counts[[4L]], expected_counts[[3L]],
  expected_counts[[1L]], expected_counts[[2L]],
  sum(expected_counts[3:4]), nrow(comparison)), "",
  sprintf(paste0(
    "For all %d comparisons, the equal-tailed intervals of the two lowest ",
    "posterior means overlap. Boldface identifies the lowest posterior mean ",
    "under each pre-specified case- and criterion-specific model specification. ",
    "The interval overlap limits conclusions about differences between the two ",
    "lowest-scoring methods."
  ), sum(comparison$winner_runner_intervals_overlap))
), interval_results_path, useBytes = TRUE)

displayed_warning_n <- sum(roles$diagnostic_grade == "WARN")
displayed_warning_keys <- sort(with(
  roles[roles$diagnostic_grade == "WARN", , drop = FALSE],
  paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role, sep = "|")
))
metric_warning_keys <- sort(with(
  complete_diagnostics[complete_diagnostics$diagnostic_grade == "WARN", , drop = FALSE],
  paste(replay_id, metric, sep = "|")
))
if (displayed_warning_n != as.integer(expected$displayed_warning_metrics) ||
    !identical(displayed_warning_keys,
               sort(unlist(expected$displayed_warning_keys, use.names = FALSE))) ||
    !identical(metric_warning_keys,
               sort(unlist(expected$metric_diagnostic_warning_keys, use.names = FALSE)))) {
  stop("The diagnostic-caution identities are inconsistent.", call. = FALSE)
}
interval_prose_path <- article_path(outputs$interval_prose)
writeLines(c(
  paste0(
    "Each criterion is recomputed for every retained conditional-quantile draw. ",
    "Table entries report the posterior mean and equal-tailed 95\\% credible interval ",
    "of the resulting draw-wise criterion. Fit RMSE measures recovery of the true ",
    "conditional quantile over the 500-observation training sample; forecast MAE and ",
    "check loss average the 1,000 rolling-origin and horizon evaluations used in the ",
    "point comparison. The intervals condition on the simulated data, evaluation ",
    "design, and criterion-specific fitted model. Variational Bayes intervals are approximate."
  ), "",
    paste0(
      "The exDQLM entries use exdqlm 1.1.1; the DQLM and both Q--DESN ",
      "entries use their stated specifications. In rolling-origin exDQLM MCMC evaluation, ",
      "the initial parameter posterior is retained while the filtering distribution is updated ",
      "sequentially with responses available at each origin. The observation-error mean and variance ",
      "used in this update are averaged over paired retained draws of the scale and asymmetry ",
      "parameters before the updated state is propagated over the requested forecast horizons. ",
      "Point estimates and posterior intervals use distinct ",
      "estimators: point estimates summarize a single fixed path for VB and chain-level ",
      "fixed paths for MCMC, whereas interval centers are posterior means of draw-wise criteria. ",
      "The two summaries are therefore interpreted separately."
  ), "",
  sprintf(
    paste0(
      "%d of the 108 displayed MCMC summaries are marked by daggers to indicate ",
      "diagnostic cautions; the supplement provides details."
    ), displayed_warning_n
  )
), interval_prose_path, useBytes = TRUE)

# Provenance records ---------------------------------------------------------
point_artifacts <- c(
  point_summary_path, point_compatibility_path, protocol_path, point_family_paths,
  point_family_wrapper_path, combined_path, point_mcmc_paths, point_mcmc_wrapper_path,
  point_figure_data_path, point_figure_path
)
write_manifest <- function(path, title, artifacts, extra = character(0)) {
  artifacts <- unique(normalizePath(artifacts, winslash = "/", mustWork = TRUE))
  writeLines(c(
    title, paste0("projection_id: ", config$projection_id),
    paste0("point_authority_id: ", config$point_authority_id),
    paste0("interval_authority_id: ", config$interval_authority_id),
    paste0("validation_head: ", validation_head),
    paste0("package_version: ", config$package$version),
    paste0("package_source_commit: ", config$package$source_commit),
    paste0("baseline_point_candidate_sha256: ", config$packet$point_candidate_sha256),
    paste0("baseline_interval_candidate_sha256: ", config$packet$interval_candidate_sha256),
    paste0("rolling_point_candidate_sha256: ", config$rolling_packet$point_candidate_sha256),
    paste0("rolling_interval_candidate_sha256: ", config$rolling_packet$interval_candidate_sha256),
    extra, "artifacts:",
    sprintf("  %s: %s", vapply(artifacts, relative_article, character(1L)),
            unname(tools::sha256sum(artifacts)))
  ), path, useBytes = TRUE)
}
point_table_manifest_path <- article_path(outputs$point_table_manifest)
write_manifest(
  point_table_manifest_path, "Independent single-quantile article record (v14)",
  point_artifacts,
  c("point_estimator_exdqlm: fixed_path_point_metric_three_chain_mean_v1", "row_count: 72")
)
point_mcmc_manifest_path <- article_path(outputs$point_mcmc_manifest)
write_manifest(
  point_mcmc_manifest_path, "Independent single-quantile MCMC article tables (v14)",
  c(point_mcmc_paths, point_mcmc_wrapper_path), c("row_count_mcmc: 36")
)
point_figure_manifest_path <- article_path(outputs$point_figure_manifest)
write_manifest(
  point_figure_manifest_path, "Independent single-quantile MCMC performance figure (v14)",
  c(point_figure_data_path, point_figure_path), c("figure_data_rows: 108")
)

preserved_path <- article_path(config$preserved_asset$path)
verify_hash(preserved_path, config$preserved_asset$sha256, "aCRPS dependence-sensitivity text")
interval_artifacts <- c(
  interval_summary_path, old_diagnostics_path, interval_comparison_path,
  interval_results_path, interval_prose_path, interval_table_paths,
  interval_table_wrapper_paths, interval_figure_paths, interval_figure_wrapper_paths,
  preserved_path
)
interval_manifest_path <- article_path(outputs$interval_manifest)
write_manifest(
  interval_manifest_path, "Independent posterior metric intervals (v14)",
  interval_artifacts,
  c(
    "interval_display_center: posterior_mean_draw_metric",
    "point_interval_estimator_separation: enforced",
    "preserved_dependence_sensitivity_filename: qdesn_validation_500obs_metric_dependence_sensitivity.tex"
  )
)
projection_manifest_path <- article_path(outputs$projection_manifest)
write_manifest(
  projection_manifest_path, "Independent exdqlm 1.1.1 article projection (v14)",
  c(point_artifacts, point_table_manifest_path, point_mcmc_manifest_path,
    point_figure_manifest_path, interval_artifacts, interval_manifest_path),
  c(
    "point_rows: 72", "interval_roles: 216", "replaced_exdqlm_mcmc_point_rows: 9",
    "replaced_exdqlm_mcmc_interval_roles: 27", "interval_figures: 6",
    sprintf("displayed_warning_metrics: %d", displayed_warning_n)
  )
)

cat("INDEPENDENT_EXDQLM_MCMC_ROLLING_STATE_FIX_ARTICLE_V14_BUILD=PASS\n")
cat(sprintf("POINT_ROWS=%d EXDQLM_POINT_ROWS=%d\n", nrow(point), sum(is_exdqlm)))
cat(sprintf("INTERVAL_ROLES=%d EXDQLM_INTERVAL_ROLES=%d WARN_DISPLAYED=%d\n",
            nrow(roles), sum(role_exdqlm), displayed_warning_n))
cat(sprintf("FIGURES=%d TABLES=%d\n", length(interval_figure_paths),
            length(c(point_family_paths, point_mcmc_paths, interval_table_paths))))
