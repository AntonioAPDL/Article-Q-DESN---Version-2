local({
  if (!exists("app_glofas_normal_driver_bank", mode = "function")) {
    script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[[1L]]
    repo_root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)),
      "..", ".."), mustWork = TRUE)
    source(file.path(repo_root, "application", "R", "00_packages.R"))
    app_set_repo_root(repo_root)
    source(app_path("application/R/latent_path_vb_al.R"))
    source(app_path("application/R/glofas_normal_driver_bank.R"))
    source(app_path("application/R/glofas_part4_normal_driver_prior.R"))
  }
  source("scripts/diagnostics/glofas_normal_driver_authority_audit.R", local = TRUE)
  td <- tempfile("normal_driver_authority_")
  dir.create(td)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)
  p123 <- file.path(td, "part123")
  p4 <- file.path(td, "part4")
  dir.create(file.path(p123, "objects"), recursive = TRUE)
  dir.create(file.path(p123, "forecasts"), recursive = TRUE)
  dir.create(file.path(p4, "objects"), recursive = TRUE)
  dates30 <- as.Date("2022-12-26") + 0:29
  fit_sha <- character(3L)
  banks <- vector("list", 3L)
  for (part in 1:3) {
    fit_path <- file.path(p123, "objects", sprintf("part%d_fit_normal_rhs_vb_fit.rds", part))
    saveRDS(list(part = part), fit_path)
    fit_sha[[part]] <- app_sha256_file(fit_path)
    components <- if (part == 1L) {
      list(usgs = matrix(part, 30L, 500L))
    } else if (part == 2L) {
      list(discrepancy = matrix(part, 30L, 500L))
    } else {
      list(usgs = matrix(1, 30L, 500L), discrepancy = matrix(2, 30L, 500L),
        glofas = matrix(3, 30L, 500L))
    }
    bank <- app_glofas_normal_driver_bank(
      dates30, components, as.Date("2022-12-25"), part,
      source_fit_path = fit_path, source_model_id = sprintf("part%d_normal_rhs", part)
    )
    bank$contract$source_fit_path <- file.path(td, "retired", basename(fit_path))
    bank$contract$contract_hash <- NULL
    bank$contract$contract_hash <- app_latent_path_contract_hash(
      bank$contract, "glofas_normal_driver_bank_"
    )
    banks[[part]] <- bank
    saveRDS(bank, file.path(p123, "objects",
      sprintf("part%d_normal_rhs_driver_bank.rds", part)))
    mode <- if (part == 3L) "matched_part3_normal_rhs_external_driver" else
      "normal_rhs_external_driver"
    for (family in c("independent_al", "independent_exal", "joint_al", "joint_exal")) {
      reps <- if (startsWith(family, "independent")) 7L else 1L
      for (i in seq_len(reps)) {
        suffix <- if (reps == 1L) "all7" else sprintf("q0p%02d", i)
        forecast <- list(forecast_mode = mode, n_paths = 500L,
          driver_contract = bank$contract)
        saveRDS(forecast, file.path(p123, "forecasts", sprintf(
          "part%d_forecast_%s_%s_forecast.rds", part, family, suffix)))
        fit <- if (part < 3L) {
          list(beta_cov = diag(2L))
        } else {
          list(beta_reference_cov_blocks = list(diag(2L)),
            beta_discrepancy_cov_blocks = list(diag(2L)))
        }
        saveRDS(fit, file.path(p123, "objects", sprintf(
          "part%d_fit_%s_%s_fit.rds", part, family, suffix)))
      }
    }
  }
  short <- app_glofas_normal_driver_bank(
    dates30[1:28], lapply(banks[[3]]$components, function(x) x[1:28, , drop = FALSE]),
    as.Date("2022-12-25"), 3L,
    source_fit_path = file.path(p123, "objects", "part3_fit_normal_rhs_vb_fit.rds"),
    source_model_id = "part3_normal_rhs"
  )
  prior <- app_glofas_part4_normal_driver_prior(short, expected_paths = 500L)
  saveRDS(prior, file.path(p4, "objects", "part4_normal_driver_prior.rds"))
  diagnostic <- list(future_gaussian_prior_used = TRUE,
    future_gaussian_prior_contract_hash = prior$contract$contract_hash,
    future_y_working_likelihood_used = FALSE)
  for (family in c("independent_al", "independent_exal")) for (i in 1:7) {
    saveRDS(list(fit = list(vb_diagnostics = diagnostic)), file.path(p4, "objects",
      sprintf("toy_%s_rhs_vb_p%02d_fit_side.rds", family, i)))
  }
  for (family in c("joint_al", "joint_exal")) {
    saveRDS(list(fits = replicate(7L, list(vb_diagnostics = diagnostic), simplify = FALSE)),
      file.path(p4, "objects", sprintf("toy_%s_rhs_vb_fit_side.rds", family)))
  }
  result <- gnda_run(p123, p4, file.path(td, "out"))
  stopifnot(
    result$summary$status == "COHERENT_NORMAL_DRIVER_AUTHORITY_CONTRACT_PASS",
    result$summary$part123_forecasts == 48L,
    result$summary$part4_fit_cores == 28L,
    result$summary$scoring_truth_reads == 0L,
    result$summary$model_fits == 0L
  )
  cat("GLOFAS_NORMAL_DRIVER_AUTHORITY_AUDIT_PASS truth_reads=0 model_fits=0\n")
})
