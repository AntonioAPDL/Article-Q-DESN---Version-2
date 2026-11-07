local({
  source("scripts/diagnostics/glofas_global_path_tail_closeout.R", local = TRUE)
  td <- tempfile("glofas_tail_closeout_"); dir.create(td)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)
  probabilities <- c(.05, .5, .95)
  accepted <- reporting <- references <- character(3L)
  values <- list(c(2, 1), c(1, 1), c(0, 2))
  for (i in seq_along(probabilities)) {
    accepted[[i]] <- file.path(td, paste0("accepted", i, ".csv"))
    utils::write.csv(data.frame(horizon = 1:28,
      quantile_transformed = rep(values[[i]], 14L)), accepted[[i]], row.names = FALSE)
    grid <- expand.grid(horizon = 1:28,
      reporting_operator = c("marginal_future_response_quantile",
        "legacy_weighted_mean_readout_location",
        "local_gaussian_delta_marginal_quantile"),
      path_law = c("same_family_al_transition", "gaussian_path_prior"),
      member_policy = c("unit_member_likelihood_v1",
        "fractional_marginal_information_diagnostic_v1"),
      stringsAsFactors = FALSE)
    base <- if (i == 1L) rep(c(2, 1), 14L) else if (i == 2L) rep(1, 28L) else rep(c(0, 2), 14L)
    grid$estimate <- base[grid$horizon]
    legacy <- grid$reporting_operator == "legacy_weighted_mean_readout_location"
    grid$estimate[legacy] <- i
    reporting[[i]] <- file.path(td, paste0("reporting", i, ".csv"))
    utils::write.csv(grid, reporting[[i]], row.names = FALSE)
    references[[i]] <- file.path(td, paste0("reference", i, ".csv"))
    utils::write.csv(data.frame(contract = rep(c("a", "b"), each = 2L),
      method = rep(c("importance", "tempered"), 2L),
      status = "ok", diagnostic_thresholds_passed = c(FALSE, TRUE, TRUE, TRUE),
      complete = TRUE, particles = 256, evaluations = 256,
      effective_sample_size = 200, maximum_weight = .01,
      normalized_entropy = .99, elapsed_seconds = 1), references[[i]], row.names = FALSE)
  }
  out <- file.path(td, "out")
  result <- ggtc_run(accepted, reporting, references, out)
  stopifnot(result$decision$status ==
    "STRUCTURAL_INDEPENDENT_TAIL_PATH_TARGET_INCOHERENCE")
  stopifnot(file.exists(result$pdf), file.exists(file.path(out, "artifact_manifest.csv")))
  cat("GLOFAS_GLOBAL_PATH_TAIL_CLOSEOUT_PASS authentic_reads=0 model_runs=0\n")
})
