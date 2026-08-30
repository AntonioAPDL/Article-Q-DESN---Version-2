#!/usr/bin/env Rscript

if (!exists("app_path", mode = "function")) {
  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]
  test_root <- normalizePath(file.path(
    dirname(sub("^--file=", "", file_arg)), "..", ".."
  ), winslash = "/", mustWork = TRUE)
  source(file.path(test_root, "application", "R", "00_packages.R"))
  app_set_repo_root(test_root)
}

cfg <- yaml::read_yaml(app_path(
  "application/config/independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.yaml"
))
validation_setting <- Sys.getenv("QDESN_VALIDATION_ROOT", unset = cfg$validation_root)
validation_candidate <- if (grepl("^/", validation_setting)) {
  validation_setting
} else {
  file.path(app_path("."), validation_setting)
}
if (!dir.exists(validation_candidate)) {
  cat(paste0(
    "Independent exdqlm 1.1.1 article v14 checks skipped: the shared-validation ",
    "authority is unavailable; set QDESN_VALIDATION_ROOT to run this integration test.\n"
  ))
} else {
validation_root <- normalizePath(validation_candidate, winslash = "/", mustWork = TRUE)
packet_root <- file.path(validation_root, cfg$packet_relative_path)
rolling_packet_root <- file.path(validation_root, cfg$rolling_packet_relative_path)
sha256 <- function(path) unname(tools::sha256sum(path)[[1L]])

stopifnot(identical(
  system2("git", c("-C", shQuote(validation_root), "rev-parse", "HEAD"), stdout = TRUE),
  as.character(cfg$validation_authority_commit)
))
for (item in c(
  "handoff", "file_manifest", "point_candidate", "interval_candidate",
  "mcmc_diagnostics", "source_point_summary", "source_interval_summary",
  "point_winner_ledger", "interval_winner_ledger"
)) {
  path <- file.path(packet_root, cfg$packet[[item]])
  stopifnot(file.exists(path))
  stopifnot(identical(sha256(path), as.character(cfg$packet[[paste0(item, "_sha256")]])))
}

point_source <- read.csv(
  file.path(packet_root, cfg$packet$point_candidate), check.names = FALSE
)
rolling_point <- read.csv(
  file.path(rolling_packet_root, cfg$rolling_packet$point_candidate), check.names = FALSE
)
point_key <- with(point_source, paste(inference, model_variant, family, sprintf("%.2f", tau)))
rolling_point_key <- with(rolling_point, paste(inference, model_variant, family, sprintf("%.2f", tau)))
point_at <- match(rolling_point_key, point_key)
for (column in intersect(names(rolling_point), names(point_source))) {
  point_source[point_at, column] <- rolling_point[[column]]
}
point <- app_read_csv(app_path("tables/qdesn_validation_500obs_trainonly_summary.csv"))
point_source$article_interface_id <- cfg$point_authority_id
untouched_point <- setdiff(seq_len(nrow(point)), point_at)
stopifnot(isTRUE(all.equal(point[untouched_point, ], point_source[untouched_point, ],
                           check.attributes = FALSE, tolerance = 0)))
for (column in c("fit_qtrue_rmse", "forecast_qtrue_mae_H1000", "forecast_check_loss_H1000")) {
  stopifnot(isTRUE(all.equal(point[point_at, column], rolling_point[[column]], tolerance = 0)))
}
stopifnot(nrow(point) == 72L, sum(point$inference == "vb") == 36L,
          sum(point$inference == "mcmc") == 36L)
stopifnot(sum(point$model_variant == "exdqlm") == 18L)
stopifnot(all(point$package_version[point$model_variant == "exdqlm"] == "1.1.1"))
stopifnot(all(point$package_version[point$model_variant != "exdqlm"] == "1.0.0"))
stopifnot(all(
  point$metric_estimator_contract[point$model_variant == "exdqlm" & point$inference == "mcmc"] ==
    "fixed_path_point_metric_three_chain_mean_v1"
))

roles <- read.csv(
  file.path(packet_root, cfg$packet$interval_candidate), check.names = FALSE
)
rolling_roles <- read.csv(
  file.path(rolling_packet_root, cfg$rolling_packet$interval_candidate), check.names = FALSE
)
roles_key <- with(roles, paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role))
rolling_roles_key <- with(rolling_roles, paste(inference, model_variant, family, sprintf("%.2f", tau), metric_role))
roles_at <- match(rolling_roles_key, roles_key)
for (column in intersect(names(rolling_roles), names(roles))) roles[roles_at, column] <- rolling_roles[[column]]
roles$replay_id[roles_at] <- paste0(
  "rolling_state_v1_", rolling_roles$family, "_",
  gsub("\\.", "p", sprintf("%.2f", rolling_roles$tau))
)
rolling_diagnostics <- read.csv(
  file.path(rolling_packet_root, cfg$rolling_packet$mcmc_diagnostics), check.names = FALSE
)
dk <- with(rolling_diagnostics, paste(family, sprintf("%.2f", tau), metric))
rk <- with(rolling_roles, paste(
  family, sprintf("%.2f", tau),
  ifelse(metric_role == "fit", "fit_rmse",
         ifelse(metric_role == "forecast_check", "forecast_check_loss", "forecast_mae"))
))
roles$diagnostic_grade[roles_at] <- rolling_diagnostics$diagnostic_grade[match(rk, dk)]
role_key <- with(roles, paste(inference, model_variant, family, tau, metric_role))
stopifnot(nrow(roles) == 216L, !anyDuplicated(role_key))
stopifnot(sum(roles$model_variant == "exdqlm") == 54L)
stopifnot(sum(roles$estimator_id ==
                "posterior_mean_draw_metric_equal_tailed_95cri_v1") == 214L)
stopifnot(sum(roles$estimator_id ==
                "chain_balanced_draw_metric_equal_tailed_95cri_v1") == 2L)
stopifnot(all(is.finite(roles$posterior_mean)), all(is.finite(roles$cri_lower)),
          all(is.finite(roles$cri_upper)))
stopifnot(all(roles$cri_lower <= roles$posterior_median),
          all(roles$posterior_median <= roles$cri_upper),
          all(roles$posterior_mean >= roles$cri_lower),
          all(roles$posterior_mean <= roles$cri_upper))
stopifnot(any(abs(roles$authoritative_value - roles$posterior_mean) > 1.0e-12))
stopifnot(sum(roles$diagnostic_grade == "WARN") == 5L)

portable <- app_read_csv(app_path(cfg$outputs$interval_summary))
portable_key <- with(portable, paste(inference, model_variant, family, tau))
role_map <- list(
  fit = c("fit_qtrue_rmse", "fit_cri_lower", "fit_posterior_median", "fit_cri_upper"),
  forecast_mae = c(
    "forecast_qtrue_mae_H1000", "forecast_mae_cri_lower",
    "forecast_mae_posterior_median", "forecast_mae_cri_upper"),
  forecast_check = c(
    "forecast_check_loss_H1000", "forecast_check_cri_lower",
    "forecast_check_posterior_median", "forecast_check_cri_upper")
)
source_fields <- c("posterior_mean", "cri_lower", "posterior_median", "cri_upper")
for (role in names(role_map)) {
  block <- roles[roles$metric_role == role, , drop = FALSE]
  block_key <- with(block, paste(inference, model_variant, family, tau))
  at <- match(portable_key, block_key)
  stopifnot(!anyNA(at))
  for (j in seq_along(source_fields)) {
    stopifnot(isTRUE(all.equal(
      as.numeric(portable[[role_map[[role]][[j]]]]),
      as.numeric(block[[source_fields[[j]]]][at]), tolerance = 0
    )))
  }
}

diagnostics <- app_read_csv(app_path(cfg$outputs$interval_diagnostics))
stopifnot(nrow(diagnostics) == 162L)
stopifnot(sum(diagnostics$diagnostic_grade == "PASS") == 158L)
stopifnot(sum(diagnostics$diagnostic_grade == "WARN") == 4L)
comparison <- app_read_csv(app_path(cfg$outputs$interval_comparison))
stopifnot(nrow(comparison) == 27L, all(comparison$winner_runner_intervals_overlap))
stopifnot(identical(
  as.integer(table(factor(comparison$winner_model_variant, levels = unlist(cfg$expected$models)))),
  c(4L, 5L, 8L, 10L)
))
stopifnot(identical(
  sha256(app_path(cfg$preserved_asset$path)), as.character(cfg$preserved_asset$sha256)
))

checker <- app_path("scripts/check_independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.R")
checker_output <- system2("Rscript", shQuote(checker), stdout = TRUE, stderr = TRUE)
stopifnot(is.null(attr(checker_output, "status")))
stopifnot(any(grepl(
  "INDEPENDENT_EXDQLM_MCMC_ROLLING_STATE_FIX_ARTICLE_V14_CHECK=PASS", checker_output, fixed = TRUE
)))

cat("Independent exdqlm 1.1.1 article v14 checks passed.\n")
}
