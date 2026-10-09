#!/usr/bin/env Rscript
# Presentation-only extraction of historical conditional quantiles from the
# same frozen Part 4 fits used by Figure 4. No fitting or random sampling.
options(stringsAsFactors = FALSE, digits = 17)
args <- commandArgs(trailingOnly = TRUE)
argument <- function(flag) {
  at <- match(flag, args)
  if (is.na(at) || at == length(args)) stop("Required argument: ", flag)
  args[[at + 1L]]
}
ledger_path <- normalizePath(argument("--authority-ledger"), mustWork = TRUE)
output_dir <- argument("--output-dir")
stopifnot(requireNamespace("jsonlite", quietly = TRUE))
sha <- function(path) {
  value <- system2("sha256sum", shQuote(path), stdout = TRUE)
  stopifnot(length(value) == 1L)
  strsplit(value, " +")[[1L]][[1L]]
}
verify <- function(path, expected_sha, expected_bytes = NULL) {
  stopifnot(file.exists(path), identical(sha(path), expected_sha))
  if (!is.null(expected_bytes)) stopifnot(file.info(path)$size == expected_bytes)
  invisible(TRUE)
}
verify(ledger_path, "b5ef0cc5a60db1bfebd670681d59b5e51d63394f20f8351caf0e48c4a0b54983", 5148)
ledger <- read.csv(ledger_path, check.names = FALSE)
design_record <- ledger[ledger$role == "truth_free_design", , drop = FALSE]
design_sha <- "a2fbcec6523802f01c98ec272253e58a598a5adc5c7b0f9063b615b36c07bcf9"
stopifnot(nrow(design_record) == 1L, design_record$sha256 == design_sha,
          design_record$authority_status == "canonical")
verify(design_record$path, design_sha, 4014831357)
runtime_root <- dirname(dirname(design_record$path))
run_label <- "glofas_part4_search3_dependency_closure_20260930_r4"
stopifnot(basename(runtime_root) == run_label)
probabilities <- c(.05, .20, .35, .50, .65, .80, .95)
jobs <- data.frame(
  role = c("normal_ridge", paste0("independent_al_", c("p05", "p20", "p35", "p50", "p65", "p80", "p95"))),
  suffix = c("normal_ridge_diagnostic", paste0("independent_al_rhs_vb_", c("p05", "p20", "p35", "p50", "p65", "p80", "p95"))),
  quantile_level = c(NA_real_, probabilities),
  fit_bytes = c(136686065, 137565881, 137565881, 137565881, 137565880, 137565881, 137565881, 137565881),
  fit_sha = c(
    "4262a6030b0587df9be73b0708f5df1cdc49fbe1c240a4182c3e52b7e2db0582",
    "4dab9567c280c2892f6f8b3df56a5623b54cb7fd1e108d74db2c20bbd97f1747",
    "9fe4292c2054de0160eda3800d2972f12a612bdf23b2229f66dc75c1f3d197aa",
    "0fff6fa0f609c2c9dafa055aed8bf257796c7414183b08c43472284f31e4fbd4",
    "a09c88cebe5a1878186264a57c5dc1c2966f9cbe8b49f6e17bedd3b08a5f4f41",
    "3c03ca2bf42999f99018617b0b773376041267a6759251aea34efa5fcab108d1",
    "1344f7ca616717d6504299633eb7ef4abfc039b2737436e883053d25a85eb1ba",
    "d297f72a37f3aac87def4a1421532e853430ef42554672117843d3f9bffbf276"),
  manifest_sha = c(
    "362b89a9202b308b03e208c53b277a64e648ad45e8aae68a7b28856c5d01bc0e",
    "9fbdfc38cf639cdc8eaa64c158def78c9eddc37f331d2fb3a3ee33a485d88e3c",
    "2fc5460a89bd4910aab3c50fd6a3c3932c5a6217b8c7eb47ee6fc3b52784c585",
    "b665b4a31be764721cb935853c1ebba17ba8d11f426a95b9d9057de7bb627bf0",
    "97913df12f9b4dd2281c74505de8297d7cf154137b1914ba1f1c53bdc067d26e",
    "78b10abec7ed9a2d3a87b5ac0d9897a3a4b158b3103e26cc468a5503613c293d",
    "44b7a64033fc67d2df2a5710e01ee3e16dd1e8677876701a914479034c82416b",
    "6cd1bf0b34ba718d568fd3f25355fb3b91a354613310c89a8ab11175cfaf8794"))
jobs$job_id <- paste0(run_label, "_", jobs$suffix)
fit_paths <- coefficient_paths <- character(nrow(jobs))
source_records <- vector("list", nrow(jobs))
for (i in seq_len(nrow(jobs))) {
  manifest_path <- file.path(runtime_root, "manifests", paste0(jobs$job_id[i], "_artifacts.csv"))
  verify(manifest_path, jobs$manifest_sha[i])
  manifest <- read.csv(manifest_path, check.names = FALSE)
  fit_record <- manifest[manifest$relative_path == paste0("objects/", jobs$job_id[i], "_fit_side.rds"), , drop = FALSE]
  coefficient_record <- manifest[manifest$relative_path == paste0("coefficients/", jobs$job_id[i], "_coefficients.csv"), , drop = FALSE]
  stopifnot(nrow(fit_record) == 1L, nrow(coefficient_record) == 1L,
            fit_record$sha256 == jobs$fit_sha[i], fit_record$size_bytes == jobs$fit_bytes[i])
  fit_paths[i] <- file.path(runtime_root, fit_record$relative_path)
  coefficient_paths[i] <- file.path(runtime_root, coefficient_record$relative_path)
  verify(fit_paths[i], jobs$fit_sha[i], jobs$fit_bytes[i])
  verify(coefficient_paths[i], coefficient_record$sha256, coefficient_record$size_bytes)
  source_records[[i]] <- list(role = jobs$role[i], fit_bytes = jobs$fit_bytes[i],
    fit_sha256 = jobs$fit_sha[i], artifact_manifest_sha256 = jobs$manifest_sha[i],
    coefficient_summary_sha256 = coefficient_record$sha256)
}

# Authenticate every source before reading any frozen fit or large design.
cat("Frozen Part 4 source hashes verified; reading fixed historical design once.\n")
design <- readRDS(design_record$path)
origin <- as.Date("2022-12-25")
dates <- seq(origin - 29, origin, by = "day")
stopifnot(is.data.frame(design$base_panel), is.matrix(design$X_beta),
          nrow(design$X_beta) == nrow(design$base_panel),
          identical(as.integer(design$beta_index), seq_len(ncol(design$X_beta))))
all_dates <- as.Date(design$base_panel$target_date)
stopifnot(!anyDuplicated(all_dates))
indices <- match(dates, all_dates)
stopifnot(!anyNA(indices), inherits(all_dates, "Date"), inherits(dates, "Date"),
          identical(as.numeric(all_dates[indices]), as.numeric(dates)))
cat("Historical dates match exactly; source Date storage:", typeof(all_dates),
    "; requested Date storage:", typeof(dates), "\n")
X <- design$X_beta[indices, , drop = FALSE]
beta_index <- as.integer(design$beta_index)
theta_names <- colnames(design$H_fixed)
stopifnot(all(is.finite(X)), identical(theta_names[beta_index], paste0("beta__", colnames(X))),
          all(is.finite(design$base_panel$y_transformed[indices])))
rm(design)
invisible(gc())

rows <- vector("list", nrow(jobs))
normal_shape <- normal_rate <- normal_sd_mean <- NA_real_
for (i in seq_len(nrow(jobs))) {
  result <- readRDS(fit_paths[i])
  expected_family <- if (i == 1L) "normal" else "al"
  stopifnot(result$method == "vb", result$likelihood_family == expected_family,
            result$fit$likelihood_family == expected_family,
            result$shared_design_reference$sha256 == design_sha)
  theta_mean <- as.numeric(result$fit$summary$theta_mean)
  coefficients <- read.csv(coefficient_paths[i], check.names = FALSE)
  stopifnot(length(theta_mean) == length(theta_names),
            identical(coefficients$coefficient, theta_names),
            identical(colnames(result$fit$draws$theta), theta_names),
            max(abs(theta_mean - coefficients$mean)) < 1e-12)
  location_mean <- as.numeric(X %*% theta_mean[beta_index])
  if (i == 1L) {
    # The Normal engine uses sigma_Y as a residual variance, with IG(shape,rate).
    # E[sqrt(sigma_Y)] = sqrt(rate) Gamma(shape-1/2)/Gamma(shape).
    sigma <- result$fit$variational_state$sigma
    normal_shape <- as.numeric(sigma$shape[["Y"]])
    normal_rate <- as.numeric(sigma$rate[["Y"]])
    stopifnot(is.finite(normal_shape), normal_shape > .5,
              is.finite(normal_rate), normal_rate > 0)
    normal_sd_mean <- exp(.5 * log(normal_rate) + lgamma(normal_shape - .5) - lgamma(normal_shape))
    rows[[i]] <- do.call(rbind, lapply(probabilities, function(p) data.frame(
      part = "Part 4", family = "Normal Ridge", target_date = dates,
      quantile_level = p, qhat = location_mean + stats::qnorm(p) * normal_sd_mean,
      location_mean = location_mean, expected_residual_sd = normal_sd_mean,
      period = "historical_fit", summary_role = "posterior_mean_conditional_response_quantile")))
  } else {
    stopifnot(abs(as.numeric(result$quantile_level) - jobs$quantile_level[i]) < 1e-12)
    rows[[i]] <- data.frame(part = "Part 4", family = "Independent AL", target_date = dates,
      quantile_level = jobs$quantile_level[i], qhat = location_mean,
      location_mean = location_mean, expected_residual_sd = NA_real_,
      period = "historical_fit", summary_role = "posterior_mean_conditional_response_quantile")
  }
  rm(result, coefficients)
  invisible(gc())
}
historical <- do.call(rbind, rows)
historical <- historical[order(historical$family, historical$target_date, historical$quantile_level), ]
stopifnot(nrow(historical) == 420L, all(is.finite(historical$qhat)),
          !anyDuplicated(historical[c("family", "target_date", "quantile_level")]),
          all(table(historical$family) == 210L))
for (family in unique(historical$family)) {
  block <- historical[historical$family == family, ]
  stopifnot(setequal(block$target_date, dates), all(table(block$target_date) == 7L),
            setequal(block$quantile_level, probabilities))
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
csv_name <- "glofas_search3_part4_history_fitted_quantiles.csv"
csv_path <- file.path(output_dir, csv_name)
write.csv(historical, csv_path, row.names = FALSE, na = "")
script_path <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
receipt <- list(schema = "glofas-part4-historical-conditional-quantile-extract-v1",
  purpose = "Presentation only: same frozen Part 4 fits; no fitting, forecasting, simulation, scoring, selection, or quantile projection",
  origin_date = as.character(origin), historical_dates = as.character(range(dates)),
  historical_rows = nrow(historical), families = c("Independent AL", "Normal Ridge"),
  quantile_grid = probabilities, scale = "Existing log(1 + flow) response scale; no repeated transformation",
  independent_al_summary = "Posterior mean conditional quantile: X_beta times posterior mean beta at each fitted level",
  normal_ridge_summary = "Posterior mean conditional response quantile: X_beta times posterior mean beta plus qnorm(tau) times E[sqrt(sigma_Y)]",
  normal_residual_parameterization = "sigma_Y is residual variance; q(sigma_Y) is inverse-gamma(shape,rate)",
  normal_residual_variance_shape = normal_shape, normal_residual_variance_rate = normal_rate,
  normal_expected_residual_sd = normal_sd_mean,
  normal_expected_residual_sd_formula = "sqrt(rate) * exp(lgamma(shape - 0.5) - lgamma(shape))",
  historical_uncertainty_scope = "Fitted conditional quantile posterior means, not coefficient credible limits or posterior-predictive mixture quantiles",
  forecast_ordinates = "Unchanged retained Part 4 future latent-path summaries; Normal future curves are empirical quantiles of retained latent_y_draw",
  future_truth = "Not accessed by this historical plotting extraction",
  crossing_correction = "None; raw fitted quantiles retained",
  source_authority = list(authority_ledger_sha256 = sha(ledger_path),
    truth_free_design = list(role = "fixed_historical_design", size_bytes = 4014831357, sha256 = design_sha),
    model_fits = source_records),
  extraction_script_sha256 = sha(script_path),
  outputs = list(historical_quantiles = list(file = csv_name, sha256 = sha(csv_path))))
jsonlite::write_json(receipt, file.path(output_dir, "glofas_search3_part4_history_fitted_quantile_provenance.json"),
                     pretty = TRUE, auto_unbox = TRUE, digits = 17)
cat("GLOFAS_HISTORICAL_QUANTILES_VERIFIED families=2 dates=30 levels=7 rows=420 no_refitting\n")
