#!/usr/bin/env Rscript

gnda_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("Normal-driver authority audit: ", why), call. = FALSE)
  invisible(TRUE)
}

gnda_quantile_fit_covariance <- function(path) {
  fit <- readRDS(path)
  part <- as.integer(sub("^part([123])_.*", "\\1", basename(path)))
  ok <- if (part %in% c(1L, 2L)) {
    !is.null(fit$beta_cov_blocks) || !is.null(fit$beta_cov)
  } else {
    !is.null(fit$beta_reference_cov_blocks) &&
      !is.null(fit$beta_discrepancy_cov_blocks)
  }
  data.frame(
    relative_path = file.path("objects", basename(path)),
    part = part,
    covariance_available = ok,
    sha256 = app_sha256_file(path),
    stringsAsFactors = FALSE
  )
}

gnda_part4_core_rows <- function(path, expected_prior_hash) {
  object <- readRDS(path)
  cores <- if (!is.null(object$fits)) object$fits else list(object$fit)
  rows <- lapply(seq_along(cores), function(i) {
    diagnostics <- cores[[i]]$vb_diagnostics %||% list()
    data.frame(
      relative_path = file.path("objects", basename(path)),
      core_index = i,
      prior_used = isTRUE(diagnostics$future_gaussian_prior_used),
      prior_hash = as.character(
        diagnostics$future_gaussian_prior_contract_hash %||% NA_character_
      ),
      future_y_working_likelihood_used = isTRUE(
        diagnostics$future_y_working_likelihood_used
      ),
      expected_prior_hash = expected_prior_hash,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

gnda_run <- function(part123_root, part4_root, output_dir) {
  part123_root <- normalizePath(part123_root, mustWork = TRUE)
  part4_root <- normalizePath(part4_root, mustWork = TRUE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = TRUE)

  bank_rows <- forecast_rows <- list()
  for (part in 1:3) {
    bank_path <- file.path(
      part123_root, "objects", sprintf("part%d_normal_rhs_driver_bank.rds", part)
    )
    fit_path <- file.path(
      part123_root, "objects", sprintf("part%d_fit_normal_rhs_vb_fit.rds", part)
    )
    gnda_require(file.exists(bank_path) && file.exists(fit_path),
      sprintf("Part %d bank or source fit is missing", part))
    bank <- readRDS(bank_path)
    source_before <- as.character(bank$contract$source_fit_path %||% NA_character_)
    old_hash <- as.character(bank$contract$contract_hash)
    rebound <- app_rebind_glofas_normal_driver_bank_source(bank, fit_path)
    app_validate_glofas_normal_driver_bank(
      rebound,
      required_components = names(rebound$components),
      expected_paths = 500L,
      expected_dates = as.Date(rebound$contract$future_dates),
      require_source_available = TRUE
    )
    rebound_path <- file.path(
      output_dir, sprintf("part%d_normal_rhs_driver_bank_rebound.rds", part)
    )
    saveRDS(rebound, rebound_path, version = 2L)
    bank_rows[[part]] <- data.frame(
      part = part,
      original_bank_path = bank_path,
      original_bank_sha256 = app_sha256_file(bank_path),
      source_path_before = source_before,
      source_path_available_before = !is.na(source_before) && file.exists(source_before),
      source_fit_path = normalizePath(fit_path),
      source_fit_sha256 = app_sha256_file(fit_path),
      expected_source_fit_sha256 = as.character(bank$contract$source_fit_sha256),
      original_contract_hash = old_hash,
      rebound_contract_hash = as.character(rebound$contract$contract_hash),
      rebound_bank_path = rebound_path,
      rebound_bank_sha256 = app_sha256_file(rebound_path),
      horizon = as.integer(rebound$contract$horizon),
      n_paths = as.integer(rebound$contract$n_paths),
      response_scale = as.character(rebound$contract$response_scale),
      stringsAsFactors = FALSE
    )

    pattern <- sprintf(
      "^part%d_forecast_(independent|joint)_(al|exal).*forecast[.]rds$", part
    )
    paths <- list.files(file.path(part123_root, "forecasts"), pattern = pattern,
      full.names = TRUE)
    expected_mode <- if (part == 3L) {
      "matched_part3_normal_rhs_external_driver"
    } else {
      "normal_rhs_external_driver"
    }
    expected_hash <- old_hash
    forecast_rows[[part]] <- do.call(rbind, lapply(paths, function(path) {
      object <- readRDS(path)
      data.frame(
        part = part,
        relative_path = file.path("forecasts", basename(path)),
        forecast_mode = as.character(object$forecast_mode %||% NA_character_),
        expected_mode = expected_mode,
        n_paths = as.integer(object$n_paths %||% NA_integer_),
        driver_contract_hash = as.character(
          object$driver_contract$contract_hash %||% NA_character_
        ),
        expected_driver_contract_hash = expected_hash,
        mode_pass = identical(as.character(object$forecast_mode), expected_mode),
        path_count_pass = identical(as.integer(object$n_paths), 500L),
        driver_hash_pass = identical(
          as.character(object$driver_contract$contract_hash), expected_hash
        ),
        sha256 = app_sha256_file(path),
        stringsAsFactors = FALSE
      )
    }))
  }
  banks <- do.call(rbind, bank_rows)
  forecasts <- do.call(rbind, forecast_rows)
  gnda_require(nrow(forecasts) == 48L,
    sprintf("expected 48 Part 1-3 quantile forecasts, found %d", nrow(forecasts)))
  gnda_require(all(forecasts$mode_pass & forecasts$path_count_pass &
    forecasts$driver_hash_pass), "Part 1-3 forecast contract mismatch")

  fit_paths <- list.files(file.path(part123_root, "objects"),
    pattern = "^part[123]_fit_(independent|joint)_(al|exal).*fit[.]rds$",
    full.names = TRUE)
  covariance <- do.call(rbind, lapply(fit_paths, gnda_quantile_fit_covariance))
  gnda_require(nrow(covariance) == 48L,
    sprintf("expected 48 Part 1-3 quantile fits, found %d", nrow(covariance)))
  gnda_require(all(covariance$covariance_available),
    "a retained quantile fit lacks full coefficient covariance")

  prior_path <- file.path(part4_root, "objects", "part4_normal_driver_prior.rds")
  gnda_require(file.exists(prior_path), "Part 4 Normal-driver prior is missing")
  prior <- readRDS(prior_path)
  app_validate_glofas_part4_normal_driver_prior(
    prior,
    expected_dates = as.Date(prior$contract$future_dates),
    expected_scale = "log1p",
    expected_paths = 500L
  )
  gnda_require(identical(
    as.character(prior$contract$source_fit_sha256),
    as.character(banks$source_fit_sha256[banks$part == 3L])
  ), "Part 4 prior is not bound to the retained Part 3 Normal-RHS fit")

  part4_paths <- list.files(file.path(part4_root, "objects"),
    pattern = "_(independent|joint)_(al|exal)_rhs_vb.*fit_side[.]rds$",
    full.names = TRUE)
  part4 <- do.call(rbind, lapply(part4_paths, gnda_part4_core_rows,
    expected_prior_hash = as.character(prior$contract$contract_hash)))
  gnda_require(length(part4_paths) == 16L,
    sprintf("expected 16 Part 4 quantile fit artifacts, found %d", length(part4_paths)))
  gnda_require(nrow(part4) == 28L,
    sprintf("expected 28 Part 4 fit cores, found %d", nrow(part4)))
  gnda_require(all(part4$prior_used) &&
    all(part4$prior_hash == part4$expected_prior_hash) &&
    !any(part4$future_y_working_likelihood_used),
    "Part 4 future-USGS replacement-prior contract mismatch")

  utils::write.csv(banks, file.path(output_dir, "driver_bank_rebinding.csv"),
    row.names = FALSE)
  utils::write.csv(forecasts, file.path(output_dir, "part123_forecast_contracts.csv"),
    row.names = FALSE)
  utils::write.csv(covariance, file.path(output_dir, "part123_covariance_audit.csv"),
    row.names = FALSE)
  utils::write.csv(part4, file.path(output_dir, "part4_prior_contracts.csv"),
    row.names = FALSE)
  summary <- data.frame(
    status = "COHERENT_NORMAL_DRIVER_AUTHORITY_CONTRACT_PASS",
    banks = nrow(banks),
    part123_forecasts = nrow(forecasts),
    part123_fits_with_covariance = sum(covariance$covariance_available),
    part4_fit_artifacts = length(part4_paths),
    part4_fit_cores = nrow(part4),
    scoring_truth_reads = 0L,
    model_fits = 0L,
    stringsAsFactors = FALSE
  )
  utils::write.csv(summary, file.path(output_dir, "summary.csv"), row.names = FALSE)
  files <- list.files(output_dir, full.names = TRUE)
  manifest <- data.frame(
    relative_path = basename(files),
    size_bytes = file.info(files)$size,
    sha256 = unname(tools::sha256sum(files)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(manifest, file.path(output_dir, "artifact_manifest.csv"),
    row.names = FALSE)
  invisible(list(summary = summary, output_dir = output_dir))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(TRUE)
  gnda_require(length(args) == 6L && identical(args[c(1, 3, 5)],
    c("--part123-root", "--part4-root", "--output")),
    "usage: --part123-root DIR --part4-root DIR --output DIR")
  script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
  repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)),
    "..", ".."), mustWork = TRUE)
  source(file.path(repo_root, "application", "R", "00_packages.R"))
  app_set_repo_root(repo_root)
  source(app_path("application/R/latent_path_vb_al.R"))
  source(app_path("application/R/glofas_normal_driver_bank.R"))
  source(app_path("application/R/glofas_part4_normal_driver_prior.R"))
  gnda_run(args[[2L]], args[[4L]], args[[6L]])
}
